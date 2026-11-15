# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
# pqr5f on the AM243x LaunchPad, bare metal, GNU toolchain.
#
#   make SCHEME=ml-dsa-87 VARIANT=r5f
#
# Produces build/<scheme>-<variant>/pqr5f-<scheme>-<variant>.elf and .map,
# so configurations never collide. The MCU+ SDK is
# not used: TI builds its nortos kernel - boot, MPU, cache, PMU - only with TI
# Arm Clang, so startup.S and platform.c supply that layer instead.
#
# The point of this target is that pqm4 builds with arm-none-eabi-gcc too, so
# a pqr5f measurement taken here differs from a published pqm4 one in the core
# and nothing else.

# Set before any rule: the PQM4= path defines an explicit rule early, which
# would otherwise become the default goal.
.DEFAULT_GOAL := all

SCHEME  ?= ml-dsa-44
VARIANT ?= r5f
OPT     ?= -O3

CROSS   ?= arm-none-eabi-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
SIZE     = $(CROSS)size

# Relative, deliberately: an absolute path from a Cygwin-flavoured make comes
# out as /cygdrive/c/... which a native Windows arm-none-eabi-gcc cannot open.
# Run make from this directory, or with -C.
ROOT  := ../..
HERE  := .

# One case per scheme that exists. ALG and PARAM are derived for the paths
# that need them; neither is an option, so neither can be set to something the
# other does not pair with. ML-KEM is a set of cases to add, not a change.
#
# All three ML-DSA parameter sets build from ml-dsa-44, picked by
# -DDILITHIUM_MODE, which is why SRC does not vary with PARAM.
ifeq ($(SCHEME),ml-dsa-44)
ALG := ml-dsa
PARAM := 44
MODE := 2
else ifeq ($(SCHEME),ml-dsa-65)
ALG := ml-dsa
PARAM := 65
MODE := 3
else ifeq ($(SCHEME),ml-dsa-87)
ALG := ml-dsa
PARAM := 87
MODE := 5
else
$(error SCHEME must be ml-dsa-44, ml-dsa-65 or ml-dsa-87)
endif

# One case per variant, so an unknown VARIANT is an error rather than a build
# of something else. r5f and r5fstack are the ported assembly. pqclean is
# PQClean's clean C, built for the same core as a measurement baseline: it has
# a directory per parameter set instead of -DDILITHIUM_MODE, and it namespaces
# its symbols, so the generic names the harness calls are mapped onto the
# namespaced ones here - the same mapping tools/check_pqclean.sh uses on the
# host.
ifeq ($(VARIANT),pqclean)
SRC   := $(ROOT)/mupq/pqclean/crypto_sign/$(SCHEME)/clean
# One list, expanded into the -D flags, rather than a flag per line: the ACVP
# harness needs crypto_sign_signature_ctx as well, and a hand-written list that
# is missing a name fails at link with nothing to point at the cause.
PQCNS   := PQCLEAN_MLDSA$(PARAM)_CLEAN
PQCNAMES := crypto_sign_keypair crypto_sign_signature crypto_sign_signature_ctx \
            crypto_sign_verify crypto_sign_verify_ctx \
            CRYPTO_PUBLICKEYBYTES CRYPTO_SECRETKEYBYTES CRYPTO_BYTES
ALG_DEFINES = $(foreach n,$(PQCNAMES),-D$(n)=$(PQCNS)_$(n))
# Its C arithmetic goes in ATCM, so the baseline is not measured from slower
# memory than the port it is compared against. See the linker script.
LDSDEFS += -DPQR5F_PQCLEAN
else ifneq ($(filter $(VARIANT),r5f r5fstack),)
SRC         := $(ROOT)/crypto_sign/ml-dsa-44/$(VARIANT)
ALG_DEFINES  = -DDILITHIUM_MODE=$(MODE)
else
$(error VARIANT must be r5f, r5fstack or pqclean)
endif

# Per configuration: object names carry no scheme, so a shared directory would
# relink the previous one instead of rebuilding.
BUILD := build/$(SCHEME)-$(VARIANT)

ARCH = -mcpu=cortex-r5 -mthumb -mfpu=vfpv3-d16 -mfloat-abi=hard

INCLUDES = -I$(SRC) -I$(ROOT)/common -I$(ROOT)/mupq/common -I$(ROOT)/test -I$(HERE)

# -Wno-overflow: pqm4's zetas_769 table stores values above INT32_MAX in an
# int32_t array on purpose. This is the GCC spelling of the suppression the TI
# build makes with -Wno-constant-conversion.
CFLAGS = $(ARCH) $(OPT) -g -Wall -Wextra -Wno-overflow \
         -ffunction-sections -fdata-sections -ffreestanding \
         $(ALG_DEFINES) -DPQR5F_PARAM=$(PARAM) $(INCLUDES)

# -Wno-maybe-uninitialized: pqm4's stack.c has an if/else-if chain over idx % 8
# with no final else. The clang spelling is -Wno-sometimes-uninitialized.
# One flag per variant, so the harness can name the build it is running
# without a default that would quietly mislabel a measurement log.
ifeq ($(VARIANT),r5f)
CFLAGS += -DPQR5F_VARIANT_FAST
endif
ifeq ($(VARIANT),pqclean)
CFLAGS += -DPQR5F_VARIANT_PQCLEAN
endif

ifeq ($(VARIANT),r5fstack)
CFLAGS += -Wno-maybe-uninitialized
# A flag rather than a string, so no quotes have to survive make and the shell.
CFLAGS += -DPQR5F_VARIANT_STACK
# Its 16 KB of stack fits in BTCM, so the hot data leaves the cache behind.
# The speed variant's 128 KB does not, and stays in MSRAM.
LDSDEFS += -DPQR5F_STACK_IN_BTCM
endif

ASFLAGS = $(ARCH) -g $(INCLUDES)

# No C library on the output path: platform.c formats numbers itself, so
# nothing reaches newlib's printf, its malloc, or libgcc's software divide.
# memcpy and memset still come from libc, which is all that is left of it.
# Generated, because which region holds the main stack depends on the variant
# and a linker script has no conditional of its own.
LDSCRIPT = $(BUILD)/link.lds

LDFLAGS = $(ARCH) -T$(LDSCRIPT) -nostartfiles \
          -Wl,--gc-sections -Wl,-Map=$(BUILD)/$(NAME).map

ifeq ($(VARIANT),pqclean)
# No assembly beyond the startup code: that is the whole point of the baseline.
#
# Keccak comes from mupq, not from PQClean's own common/. PQClean's fips202.c
# heap-allocates every Keccak context and calls exit() if the allocation
# fails, with no compile-time way out of it; mupq's is the embedded
# replacement - same API, context inline in the struct. That matters for more
# than linking: it keeps all working memory on the stack, so the painted
# high-water figure is still the whole RAM budget and stays comparable with
# the other two variants. mupq/common/keccakf1600.c supplies the permutation
# that the ported variants get from assembly.
ASM_SRC = $(HERE)/startup.S
C_SRC   = $(HERE)/platform.c \
          $(wildcard $(SRC)/*.c) \
          $(ROOT)/mupq/common/fips202.c \
          $(ROOT)/mupq/common/keccakf1600.c \
          $(ROOT)/test/randombytes_det.c \
          $(HERE)/pqr5f_bench.c
else
ASM_SRC = $(HERE)/startup.S \
          $(ROOT)/common/keccakf1600_asm.S \
          $(SRC)/ntt.S $(SRC)/pointwise_mont.S $(SRC)/vector.S \
          $(SRC)/smallntt_769.S

C_SRC   = $(HERE)/platform.c \
          $(SRC)/packing.c $(SRC)/poly.c $(SRC)/polyvec.c $(SRC)/rounding.c \
          $(SRC)/sign.c $(SRC)/smallpoly.c $(SRC)/symmetric-shake.c \
          $(ROOT)/mupq/common/fips202.c \
          $(ROOT)/test/randombytes_det.c \
          $(HERE)/pqr5f_bench.c

ifeq ($(VARIANT),r5fstack)
C_SRC += $(SRC)/stack.c
endif
endif

# PQM4=/path/to/pqm4 assembles the .S sources straight from an upstream
# checkout instead of this repository's copies, so the instruction stream comes
# from files no one here has touched. macros.i and macros_smallntt.i are picked
# up from the same place through the include path.
#
# r5f only: pqm4 shares m4fstack's sources with symlinks, which Windows cannot
# read. That is also why this repository keeps real copies.
ifneq ($(PQM4),)
ifneq ($(VARIANT),r5f)
$(error PQM4= builds only VARIANT=r5f - pqm4 symlinks the m4fstack sources)
endif
M4DIR   = $(PQM4)/crypto_sign/ml-dsa-44/m4f
ASM_SRC = $(HERE)/startup.S $(PQM4)/common/keccakf1600.S \
          $(M4DIR)/ntt.S $(M4DIR)/pointwise_mont.s $(M4DIR)/vector.s \
          $(M4DIR)/smallntt_769.S
# pqm4 omits .thumb: on an M-profile core the assembler starts in Thumb state,
# on Cortex-R5 it starts in ARM. -Wa,-mthumb supplies what pqr5f_arch.i does.
ASFLAGS += -Wa,-mthumb -I$(M4DIR) -I$(PQM4)/common
BUILD   := $(BUILD)-pqm4

# One upstream file needs a second concession: smallntt_769.S pins
# ".cpu cortex-m4", which tags the object M-profile, and the linker then
# refuses to merge it with the R-profile ones. A .cpu directive cannot be
# overridden from the command line, so that single line is stripped on the way
# into the build directory. The instruction stream is untouched.
$(BUILD)/smallntt_769.o: $(M4DIR)/smallntt_769.S | $(BUILD)
	sed '/^[[:space:]]*\.cpu[[:space:]]/d' $< > $(BUILD)/smallntt_769.upstream.S
	$(CC) $(ASFLAGS) -x assembler-with-cpp -c $(BUILD)/smallntt_769.upstream.S -o $@
endif

# MULTEST=1 builds the multiplier timing probe instead of the benchmark. It
# answers whether MUL on this core is data-dependent, which the architecture
# does not specify and only the implementation can tell. Appended after the
# PQM4 block, which replaces ASM_SRC outright.
# STACKPAINT=1 adds a stack high-water measurement after the checksums. It runs
# each operation once more, so it does not disturb the cycle counts, but it
# does touch the whole stack - keep it out of timing-only builds.
ifeq ($(STACKPAINT),1)
CFLAGS += -DPQR5F_STACK_PAINT
BUILD  := $(BUILD)-paint
endif

# ACVP=1 runs NIST's FIPS 204 vectors instead of the benchmark. It replaces the
# deterministic PRG with one that replays a supplied buffer, because keyGen is
# handed xi directly and deterministic signing needs a zero hedging value.
ifeq ($(ACVP),1)
ifneq ($(ALG),ml-dsa)
$(error ACVP vectors exist only for ALG=ml-dsa so far)
endif
ACVPDIR = $(ROOT)/test/$(ALG)/acvp
ACVPVEC = $(ACVPDIR)/acvp_vectors_$(PARAM).c
CFLAGS += -DPQR5F_ACVP -I$(ACVPDIR)
C_SRC  := $(filter-out $(ROOT)/test/randombytes_det.c $(HERE)/pqr5f_bench.c, \
                       $(C_SRC))
C_SRC  += $(ACVPDIR)/acvp_main.c $(ACVPDIR)/acvp_rng.c $(ACVPVEC)
BUILD  := $(BUILD)-acvp

# The vectors are generated from NIST's files, which gen_acvp.py fetches on
# request - no NIST data is checked in. The first build asks before
# downloading; pass ACVP_ARGS=--yes to answer in advance.
#
# This needs an explicit object rule: the pattern rule below finds its sources
# through vpath, which cannot look for a file that does not exist yet, so make
# would never discover the rule that creates it.
$(BUILD)/acvp_vectors_$(PARAM).o: $(ACVPVEC) | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(ACVPVEC):
	@$(MAKE) --no-print-directory -C $(ROOT) vectors ACVP_ARGS="$(ACVP_ARGS)"
endif

ifeq ($(MULTEST),1)
CFLAGS  += -DPQR5F_MULTEST
ASM_SRC += $(ROOT)/test/multest/multest.S
C_SRC   += $(ROOT)/test/multest/multest_main.c
BUILD   := $(BUILD)-multest
endif

# STRICT_ALIGN=1 builds the byte-wise variants of the two unaligned accesses -
# the 24-bit sample load in rej_uniform and the Keccak lane load and store - so
# the image runs with SCTLR.A set or with the SHAKE buffers in Device memory.
# The root Makefile spells the same thing DEFINES=-DPQR5F_STRICT_ALIGN.
#
# The flag has to reach ASFLAGS: every use of it is in assembly, and ASFLAGS
# carries no -D of its own, so defining it for the C compiler alone would leave
# the instruction stream unaligned while the build looked switched over. It
# goes into CFLAGS too, for a C guard that does not exist yet.
ifeq ($(STRICT_ALIGN),1)
ifeq ($(VARIANT),pqclean)
$(error STRICT_ALIGN=1 has nothing to do in VARIANT=pqclean - it has no assembly)
endif
CFLAGS  += -DPQR5F_STRICT_ALIGN
ASFLAGS += -DPQR5F_STRICT_ALIGN
# The define only reaches the hand-written assembly. GCC targets ARMv7-R with
# unaligned access allowed by default and uses it: every C object in this build
# changes when it is turned off, and packing.c grows by 17%. Without this flag
# an image built with STRICT_ALIGN=1 still takes a data abort once SCTLR.A is
# set, from the compiler's own loads rather than from pqm4's.
CFLAGS  += -mno-unaligned-access
BUILD   := $(BUILD)-align
endif

# ALIGN_TRAP=1 sets SCTLR.A in startup.S, so the core aborts on an unaligned
# access rather than fixing it up. Separate from STRICT_ALIGN on purpose - see
# the comment at the bit itself.
ifeq ($(ALIGN_TRAP),1)
CFLAGS  += -DPQR5F_ALIGN_TRAP
ASFLAGS += -DPQR5F_ALIGN_TRAP
BUILD   := $(BUILD)-trap
endif

NAME = pqr5f-$(SCHEME)-$(VARIANT)
OBJ  = $(addprefix $(BUILD)/,$(notdir $(patsubst %.c,%.o,$(C_SRC)) \
                                      $(patsubst %.s,%.o,$(patsubst %.S,%.o,$(ASM_SRC)))))

vpath %.c $(sort $(dir $(C_SRC)))
vpath %.S $(sort $(dir $(ASM_SRC)))
vpath %.s $(sort $(dir $(ASM_SRC)))

# Bootable image for the SBL. TI's packaging and signing scripts read an ELF
# and do not care which compiler produced it.
SDK    ?= C:/ti/mcu_plus_sdk_am243x_12_00_00_27
SIGNER  = $(SDK)/source/security/security_common/tools/boot/signing
# "python" resolves to an unexecutable symlink when Cygwin is on PATH.
PYTHON ?= $(shell py -3 -c "import sys; print(sys.executable)" 2>/dev/null || echo python)

# The signed image is part of a normal build, not a separate goal to remember:
# the board boots nothing else, so a tree holding only an .elf looks built and
# cannot be flashed. Skipped when the SDK is absent, since the ELF and the
# checksums do not need it.
HAVE_SDK := $(wildcard $(SDK)/tools/boot/multicore-elf/genimage_am64x.py)

.PHONY: all image clean
all: $(BUILD)/$(NAME).elf $(if $(HAVE_SDK),$(BUILD)/$(NAME).mcelf.hs_fs)
	@$(MAKE) --no-print-directory check-keccak
	@$(SIZE) $(BUILD)/$(NAME).elf
	$(if $(HAVE_SDK),,@echo "note: no MCU+ SDK at $(SDK) - built the ELF, but no bootable image")

# KeccakF1600_Initialize exists only in the assembly implementation, so it is a
# cheap sentinel for "the permutation that got linked is the one meant". Both
# ported builds here have silently linked the C reference before this check
# existed. For VARIANT=pqclean the expectation is the other way round: a
# baseline with assembly in it would not be a baseline, so the same sentinel
# has to be absent.
#
# The MULTEST=1 probe calls no Keccak at all, so --gc-sections leaves neither
# implementation in the image and there is nothing to check.
.PHONY: check-keccak
check-keccak:
ifeq ($(MULTEST),1)
	@:
else ifeq ($(VARIANT),pqclean)
	@! $(CROSS)nm $(BUILD)/$(NAME).elf | grep -q KeccakF1600_Initialize || \
		{ echo "ERROR: the assembly Keccak was linked into the pqclean baseline"; exit 1; }
else
	@$(CROSS)nm $(BUILD)/$(NAME).elf | grep -q KeccakF1600_Initialize || \
		{ echo "ERROR: the C Keccak was linked, not the assembly one"; exit 1; }
endif

image: $(BUILD)/$(NAME).mcelf.hs_fs

$(BUILD)/$(NAME).mcelf.hs_fs: $(BUILD)/$(NAME).elf
	$(PYTHON) $(SDK)/tools/boot/multicore-elf/genimage_am64x.py \
		--core-img=4:$(BUILD)/$(NAME).elf \
		--output=$(BUILD)/$(NAME).mcelf --xip=0x60000000:0x68000000
	$(PYTHON) $(SIGNER)/appimage_x509_cert_gen.py \
		--bin $(BUILD)/$(NAME).mcelf --authtype 1 \
		--key $(SIGNER)/app_degenerateKey.pem --output $@
	@rm -f $(BUILD)/$(NAME).mcelf

$(BUILD):
	@mkdir -p $(BUILD)

# Assembly rules first, deliberately. make takes the first pattern rule whose
# prerequisite it can find, and mupq/common - which has to be on the vpath for
# fips202.c - also holds keccakf1600.c. With the .c rule first, the target
# keccakf1600.o silently compiles the C reference instead of the assembly.
$(BUILD)/%.o: %.S | $(BUILD)
	$(CC) $(ASFLAGS) -c $< -o $@

# pqm4 names two of its files .s, which gcc does not preprocess by default.
$(BUILD)/%.o: %.s | $(BUILD)
	$(CC) $(ASFLAGS) -x assembler-with-cpp -c $< -o $@

$(BUILD)/%.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(LDSCRIPT): $(HERE)/am243x_r5f.lds.in | $(BUILD)
	$(CC) -E -P -x c $(LDSDEFS) $< -o $@

$(BUILD)/$(NAME).elf: $(OBJ) $(LDSCRIPT) | $(BUILD)
	$(CC) $(OBJ) $(LDFLAGS) -o $@

clean:
	rm -rf $(BUILD)
