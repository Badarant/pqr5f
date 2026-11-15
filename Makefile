# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
# pqr5f -- ML-DSA (Dilithium) for the Arm Cortex-R5F, as a static library.
#
# Everything is built out of crypto_sign/ml-dsa-44/r5f; the parameter set is
# chosen with -DDILITHIUM_MODE.
#
#   make                     # build all three schemes
#   make SCHEMES=44          # build one
#   make STRICT_ALIGN=1      # no unaligned access anywhere in the library
#   make clean
#
# Nothing here depends on a vendor SDK; the resulting library needs only
# memcpy, memset and randombytes from its environment.

CROSS        ?= arm-none-eabi-
CC            = $(CROSS)gcc
AR            = $(CROSS)ar
NM            = $(CROSS)nm

# Must match the rest of your firmware.
ARCH_FLAGS    = -mcpu=cortex-r5 -mthumb -mfpu=vfpv3-d16 -mfloat-abi=hard

# -O3 is what pqm4 builds with, and this is a speed-optimised implementation.
# -Os costs roughly a quarter of the arithmetic throughput.
OPT          ?= -O3

# -Wno-overflow: pqm4's zetas_769 table stores values above INT32_MAX in an
# int32_t array on purpose.
# -ffunction-sections/-fdata-sections let the linker drop what you do not call.
# A verify-only image (a bootloader) does not touch the small-NTT path at all.
# VARIANT=r5f is the speed-optimised implementation (pqm4's m4f), r5fstack the
# stack-optimised one (pqm4's m4fstack). The library name carries the variant.
VARIANT      ?= r5f
R5F_DIR       = crypto_sign/ml-dsa-44/$(VARIANT)

ifeq ($(VARIANT),r5fstack)
LIBSUFFIX     = -stack
endif

# fips202, randombytes.h and hal.h come from the mupq submodule, exactly as in
# pqm4 - they are not copied into this repository.
MUPQ         ?= mupq

CFLAGS       += $(ARCH_FLAGS) $(DEFINES) $(OPT) -std=c99 -Wall \
                -Wno-overflow -ffunction-sections -fdata-sections \
                -I$(R5F_DIR) -Icommon -I$(MUPQ)/common
ASFLAGS      += $(ARCH_FLAGS) $(DEFINES) \
                -I$(R5F_DIR) -Icommon -I$(MUPQ)/common

ifeq ($(VARIANT),r5fstack)
# Must come after -Wall, which would otherwise re-enable it. pqm4's stack.c
# unpacks coefficients with an if/else-if chain over idx % 8 that covers every
# case but has no final else, so the compiler cannot prove the result is
# initialised. The code is correct either way.
CFLAGS       += -Wno-maybe-uninitialized
endif

SCHEMES      ?= 44 65 87
BUILD_DIR    ?= build
BUILD_BASE   := $(BUILD_DIR)

# STRICT_ALIGN=1 removes every unaligned access from the library. Both halves
# are needed: the define switches the two byte-wise variants in the assembly,
# and -mno-unaligned-access stops the compiler emitting its own. GCC targets
# ARMv7-R with unaligned access allowed and takes it up in every C file here -
# all ten change when the flag is added, and packing.c grows by 17% - so the
# define on its own leaves a library that still aborts where unaligned access
# is forbidden.
ifeq ($(STRICT_ALIGN),1)
CFLAGS       += -DPQR5F_STRICT_ALIGN -mno-unaligned-access
ASFLAGS      += -DPQR5F_STRICT_ALIGN
# Its own directory: object names carry the variant but not this switch, so a
# shared one would quietly relink the previous build's objects.
BUILD_DIR    := $(BUILD_DIR)-align
endif

MODE_44       = 2
MODE_65       = 3
MODE_87       = 5

CSRC          = $(notdir $(wildcard $(R5F_DIR)/*.c)) fips202.c
# keccakf1600_asm.S, not keccakf1600.S: mupq/common has to be on the vpath for
# fips202.c and also holds keccakf1600.c, so an object named keccakf1600.o is
# claimed by whichever pattern rule matches first. The wrapper gives the
# assembly a name no .c file can take; the .S rule below is also declared
# before the .c one.
ASRC          = $(notdir $(wildcard $(R5F_DIR)/*.S)) keccakf1600_asm.S

vpath %.c $(R5F_DIR) common $(MUPQ)/common
vpath %.S $(R5F_DIR) common $(MUPQ)/common

# Objects are flat (build/44_poly.o) so only one directory has to be created,
# which keeps this portable between cmd.exe and Git Bash.
DUMMY := $(shell mkdir $(BUILD_DIR) 2>&1)

.PHONY: all clean vectors
all: $(foreach s,$(SCHEMES),$(BUILD_DIR)/libpqr5f-ml-dsa-$(s)$(LIBSUFFIX).a)

# The FIPS 204 vectors are neither checked in nor vendored: gen_acvp.py fetches
# NIST's files on request, asks before it does, and generates from them. So no
# NIST data ships with this repository, the way no TI SDK code does - only
# where to get it, and NIST's notice in NOTICE, which its terms require.
# ACVP_ARGS=--yes skips the prompt; --from <dir> uses a local checkout.
# "python" resolves to an unexecutable symlink when Cygwin is on PATH, hence
# py -3.
PYTHON       ?= $(shell py -3 -c "import sys; print(sys.executable)" 2>/dev/null || echo python)
ACVP_OUT      = test/ml-dsa/acvp
ACVP_ARGS    ?=

# One generator run writes all three parameter sets, so this is a single
# recipe. The pattern rule below is what a board build hits when it needs one
# of them, and it asks for one file, so it also runs the generator once.
vectors:
	$(PYTHON) tools/gen_acvp.py $(ACVP_OUT) $(ACVP_ARGS)

$(ACVP_OUT)/acvp_vectors_%.c:
	$(PYTHON) tools/gen_acvp.py $(ACVP_OUT) $(ACVP_ARGS)

# Objects carry both the variant and the parameter set, so switching either one
# cannot silently reuse the other's objects: make rebuilds from timestamps, and
# neither switch touches a source file.
define SCHEME_RULES
$(BUILD_DIR)/$(VARIANT)_$(1)_%.o: %.S
	$$(CC) $$(ASFLAGS) -DDILITHIUM_MODE=$$(MODE_$(1)) -c -x assembler-with-cpp $$< -o $$@

$(BUILD_DIR)/$(VARIANT)_$(1)_%.o: %.c
	$$(CC) $$(CFLAGS) -DDILITHIUM_MODE=$$(MODE_$(1)) -c $$< -o $$@

$(BUILD_DIR)/libpqr5f-ml-dsa-$(1)$$(LIBSUFFIX).a: \
    $$(patsubst %.c,$(BUILD_DIR)/$(VARIANT)_$(1)_%.o,$$(CSRC)) \
    $$(patsubst %.S,$(BUILD_DIR)/$(VARIANT)_$(1)_%.o,$$(ASRC))
	$$(AR) rcs $$@ $$^
	@$$(NM) $$@ | grep -q KeccakF1600_Initialize || \
		{ echo "ERROR: $$@ has the C Keccak, not the assembly one"; exit 1; }
endef

$(foreach s,$(SCHEMES),$(eval $(call SCHEME_RULES,$(s))))

clean:
	-rm -rf $(BUILD_BASE) $(BUILD_BASE)-align
