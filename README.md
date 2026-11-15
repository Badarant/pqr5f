# pqr5f : post-quantum cryptography for the Arm Cortex-R5F

Assembly implementations of the NIST post-quantum standards for
Cortex-R5F (ARMv7-R), ported from [pqm4](https://github.com/mupq/pqm4)'s
Cortex-M4 (ARMv7E-M) code with the instruction stream left intact.

pqr5f is an independent port, not affiliated with the mupq project. The name
follows mupq's convention of `pq` plus the target core, as its own ports do
([pqm4](https://github.com/mupq/pqm4),
[pqm3](https://github.com/mupq/pqm3),
[pqriscv](https://github.com/mupq/pqriscv),
[pqax](https://github.com/mupq/pqax)), and keeps the `F`: the FPU is optional
on the Cortex-R5, this code requires it, and a plain R5 cannot run it. See
[Requirements on the target](#requirements-on-the-target).

The port was produced with Claude Code, Anthropic's agentic coding tool: the
architecture-selection edits, the `PQR5F_STRICT_ALIGN` variants, the build
system, the board integration, the test harness and this document. The claims
here do not rest on that. `tools/check_encoding.sh` compares the assembled
encodings against the unmodified pqm4 originals, the self-test checks keygen,
signing and verification against checksums that are a property of the algorithm
and not of the implementation, and every figure under
[Performance](#performance) and [Code size](#code-size) is measured on hardware
or read out of the linker map. See [Verification](#verification).

What is here is ML-DSA (FIPS 204), both of pqm4's variants, ported and measured
on hardware. ML-KEM (FIPS 203) is planned next.

## Not for production

This is a benchmark. It exists to measure what pqm4's ML-DSA assembly costs on
a Cortex-R5F, and it is not ready to protect anything.

- **No side-channel claim is made beyond one measurement.** The multiplier was
  timed and does not terminate early, see [Timing](#timing). Nothing else has
  been established: no constant-time analysis has been run, the number of
  rejection-sampling iterations during signing depends on secret values and
  shows up in the total time, and there is no masking and no fault-injection
  countermeasure.
- **Passing NIST's vectors is a self-check**, not a CAVP or ACVP validation.
  Only an accredited laboratory can perform one.
- **The randomness is yours.** This library provides none, and the
  deterministic generator in `test/randombytes_det.c` exists so that two ports
  can be compared byte for byte. Linking it into anything real would make
  every key identical and public. See
  [Requirements on the target](#requirements-on-the-target).
- **Nobody else has reviewed this.** One author, one board, one memory map.

Use it to decide whether ML-DSA fits your Cortex-R5F. Do not ship it. See
[SECURITY.md](SECURITY.md) for what is and is not established.

## Why the instruction stream does not change

ARMv7-R is a superset of the ARMv7E-M encodings these implementations use:

| used by pqm4 | Cortex-M4 | Cortex-R5F |
| --- | --- | --- |
| T32 (Thumb-2) execution | only state | supported alongside A32 |
| DSP/SIMD (`smlad`, `smuad`, `smulwb`, `smlabt`, `pkhbt/pkhtb`, `uadd16/usub16`, `sadd16/ssub16`, `smmulr`) | optional extension, present | mandatory in ARMv7-R |
| `movw`/`movt`, `ldrd`/`strd`, IT blocks, `cbz` | yes | yes |
| FP register file as scratch (`vldm`, `vpush {s16-s24}`, `vmov`) | FPv4-SP, s0–s31 | VFPv3-D16, s0–s31 |

So this is a compatibility and integration port, not a rewrite.

## Layout

```
common/          pqr5f_arch.i, keccakf1600.S (ported), randombytes.h
crypto_sign/
  ml-dsa-44/
    r5f/         from pqm4's m4f      ; speed-optimised
    r5fstack/    from pqm4's m4fstack ; stack-optimised
mupq/            submodule: fips202, hal.h, and PQClean beneath it
boards/          board integration (AM243x LaunchPad)
test/            ml-dsa/ (self-test, FIPS 204 vectors), multest/ (multiplier)
tools/           verification scripts
```

Two conventions differ from pqm4, both because this repository has to work on
Windows, which cannot follow the symbolic links pqm4 uses:

- **One directory per implementation, not per parameter set.** ML-DSA-44, -65
  and -87 share the same code; select the parameter set with
  `-DDILITHIUM_MODE=2/3/5`.
- **The two variants keep real copies of their shared files.** Each directory
  has to be self-contained anyway, because a quoted `#include` resolves against
  the directory of the file issuing it. `tools/check_variants.sh` checks the
  copies do not drift.

## What the port changed

The DSP extension is mandatory on Cortex-R and VFPv3-D16 supplies the s0–s31
scratch space pqm4 spills twiddles and pointers into, so every instruction in
these files already exists on the target and the T32 stream is byte-identical
to upstream. Apart from file headers, the diff against pqm4 is:

1. **Architecture selection.** The `.cpu cortex-m4` / `.thumb` /
   `.syntax unified` lines scattered across files became one
   `#include "pqr5f_arch.i"`. `pointwise_mont.s` and `vector.s` were renamed to
   `.S` so the preprocessor runs on them.
2. **Unaligned accesses made optional.** `-DPQR5F_STRICT_ALIGN` replaces the two
   places that rely on them - the 24-bit sample load in
   `pqcrystals_dilithium_asm_rej_uniform`, and the data-pointer accesses in
   `__KeccakF1600_State{XOR,Extract}Lanes` - with byte-wise equivalents.
3. **`DILITHIUM_MODE` overridable** from the command line, so one directory
   builds all three parameter sets.

Nothing else. With `PQR5F_STRICT_ALIGN` off, every ported file assembles to the
same encodings as its pqm4 original.

## Requirements on the target

**Enable the VFP before calling anything.** This is not only about floating
point: `ntt.S` and `smallntt_769.S` keep twiddle factors, loop bounds *and the
polynomial pointer* in `s0`–`s24`, because the butterfly needs more live values
than the 14 available core registers. Without `FPEXC.EN` the code does not
work. A Cortex-R5 without the FPU option cannot run this port.

```c
static inline void pqr5f_enable_vfp(void) {
    uint32_t v;
    /* CPACR: full access to cp10/cp11 (privileged mode required) */
    __asm__ volatile("mrc p15, 0, %0, c1, c0, 2" : "=r"(v));
    v |= (3u << 20) | (3u << 22);
    __asm__ volatile("mcr p15, 0, %0, c1, c0, 2" :: "r"(v));
    __asm__ volatile("isb");
    v = 1u << 30;                       /* FPEXC.EN */
    __asm__ volatile("vmsr fpexc, %0" :: "r"(v));
}
```

**Allow unaligned accesses, or build with `STRICT_ALIGN=1`.** Clear
`SCTLR.A` and keep the SHAKE buffers in Normal memory; on ARMv7-R an unaligned
access to Device or Strongly-ordered memory always aborts. The default
`rej_uniform` also reads up to one byte past `buf + buflen`, harmless in RAM but
not across an MPU region boundary. `ldrd`/`strd` need word alignment only, which
the `uint64_t` Keccak state and `int32_t` polynomial arrays satisfy.

**Supply a strong enough `randombytes`.** This library does not provide one;
`PQCLEAN_randombytes` is the integrator's. FIPS 204 requires an approved RBG of
at least 192 bits of security strength for ML-DSA-65 and 256 bits for
ML-DSA-87. For ML-DSA-44 it requires at least 128 and recommends 192, and below
192 the claimed security strength drops from category 2 to category 1 - the
parameter set is unchanged, the claim about it is not. The deterministic
generator in `test/randombytes_det.c` is for reproducible test vectors and
benchmarks only.

**Interworking** with A32 caller code is handled by the linker: entry points are
`.type %function` inside `.thumb` code, and the returns (`pop {…, pc}`, `bx lr`)
are interworking branches on ARMv7-R.

## Building

```bash
git submodule update --init --recursive
make                       # all three parameter sets, speed-optimised
make VARIANT=r5fstack      # stack-optimised
make SCHEMES=65
make STRICT_ALIGN=1
```

Builds with `arm-none-eabi-gcc`, which is also what pqm4 uses, so a pqr5f
measurement differs from a published pqm4 one in the core and nothing else. The
result is `build/libpqr5f-ml-dsa-<scheme>[-stack].a`, whose only external
symbols are `memcpy`, `memset` and `PQCLEAN_randombytes`. Every build needs
both `crypto_sign/ml-dsa-44/<variant>` and `common` on the include path, in
that order.

Flags must match the firmware you link into:
`-mcpu=cortex-r5 -mthumb -mfpu=vfpv3-d16 -mfloat-abi=hard`, and `OPT` defaults
to `-O3`, which is what pqm4 uses.

For a board, see [boards/lp-am243x/README.md](boards/lp-am243x/README.md).

## Performance

AM243x LaunchPad, R5FSS0 core 0 at 800 MHz, `-O3`, the inner loops and their
tables in ATCM. Mean of 10 iterations, in cycles, from
`measurements/ml-dsa/measurements.csv`:

| scheme | variant | keygen | sign | verify |
| --- | --- | --- | --- | --- |
| ML-DSA-44 | `r5f` | 1,355,172 | 1,829,838 | 1,368,536 |
| ML-DSA-65 | `r5f` | 2,395,701 | 3,801,584 | 2,281,534 |
| ML-DSA-87 | `r5f` | 4,019,253 | 14,421,635 | 3,894,541 |
| ML-DSA-44 | `r5fstack` | 1,753,965 | 3,752,559 | 2,844,496 |
| ML-DSA-65 | `r5fstack` | 3,365,805 | 9,495,853 | 4,975,033 |
| ML-DSA-87 | `r5fstack` | 5,474,081 | 54,589,512 | 8,636,218 |

The two variants do not run from the same memory. `r5fstack` needs so little
stack that it fits in BTCM, so that is where its stack goes; `r5f` needs 128 KB
and keeps its stack in MSRAM. That is how each would be deployed, and it is
also why the rows above compare more than two implementations: with both
stacks in MSRAM the stack-optimised variant would be slower still, so what it
costs in time is understated here rather than overstated. The `.mainstack`
section of a linked image says which memory it got.

The benchmark reseeds the deterministic generator before every iteration, so
all iterations of one configuration execute the same instruction sequence. The
spread between them therefore cannot be algorithmic; it comes from the memory
system, and it tracks the stack footprint - the `r5f` rows, which touch tens of
kilobytes, move by thousands of cycles, while the `r5fstack` rows move by
single digits.

Signing is rejection-sampled, and one fixed seed is one draw of that loop
rather than an average over seeds. FIPS 204 Table 1 gives the expected
repetitions as 4.25, 5.1 and 3.85 for ML-DSA-44, 65 and 87, so ML-DSA-87
expects the fewest of the three; its 54.6 M above is an unlucky draw, not the
typical cost. The same caveat does not apply to `keygen` or `verify`.

[docs/ml-dsa/performance.html](docs/ml-dsa/performance.html) plots all three
operations against peak stack on one shared pair of axes, with ROM and the full
table.

Peak stack use, same board and configuration, in bytes. Measured by painting
the stack and scanning it afterwards, which needs its own image: build with
`STACKPAINT=1`.

| scheme | variant | keygen | sign | verify |
| --- | --- | --- | --- | --- |
| ML-DSA-44 | `r5f` | 38,432 | 44,928 | 9,008 |
| ML-DSA-65 | `r5f` | 60,968 | 68,992 | 9,984 |
| ML-DSA-87 | `r5f` | 97,832 | 107,904 | 12,048 |
| ML-DSA-44 | `r5fstack` | 4,544 | 5,208 | 2,840 |
| ML-DSA-65 | `r5fstack` | 4,544 | 6,752 | 2,840 |
| ML-DSA-87 | `r5fstack` | 4,544 | 8,280 | 2,840 |

The implementation has no static RAM at all - no object in the library defines
a `.data` or `.bss` symbol - so these figures are the whole RAM budget, not a
part of it.

That is what the second variant buys: `r5fstack` signing fits in 5.2–8.3 kB
instead of 45–108 kB, a factor of 8.6 at ML-DSA-44 rising to 13 at ML-DSA-87,
and its key generation is a flat 4,544 bytes and its verification a flat 2,840
across all three parameter sets. The cost is in the first table - 54.6 M cycles
instead of 14.4 M to sign with ML-DSA-87. Verification is modest either way, so
a verify-only image such as a secure bootloader can use the speed-optimised
variant and still need no more than 12,048 bytes of stack.

## Code size

ROM in bytes, `-O3`, linked with `--gc-sections` so each column is the closure
of one entry point - what an image doing only that operation would carry - and
not a share of a total. The three overlap: they share the NTT, Keccak, packing
and sampling code. "All three" is a real link of all of them together.

| scheme | variant | keygen | sign | verify | all three |
| --- | --- | --- | --- | --- | --- |
| ML-DSA-44 | `r5f` | 17,980 | 25,380 | 17,768 | 28,148 |
| ML-DSA-65 | `r5f` | 17,724 | 24,868 | 17,768 | 27,636 |
| ML-DSA-87 | `r5f` | 17,980 | 25,124 | 17,768 | 27,892 |
| ML-DSA-44 | `r5fstack` | 17,724 | 26,148 | 18,280 | 30,452 |
| ML-DSA-65 | `r5fstack` | 17,724 | 25,636 | 18,024 | 29,684 |
| ML-DSA-87 | `r5fstack` | 17,724 | 25,892 | 18,024 | 30,196 |

Measured by `tools/codesize.py`, which reads the sizes out of the linker map
and checks its arithmetic against `size(1)`; the rows are also in
`measurements/ml-dsa/codesize.csv`. `memcpy` and `memset` are excluded (up to
236 bytes here), since which C library you link is not a property of this
implementation. Static RAM is zero in every configuration: no object in the
library defines a `.data` or `.bss` symbol.

The ordering is not monotone in the security level. Around 70% of the image is
parameter-independent assembly - Keccak, both NTTs and their twiddle tables,
byte-identical across the three - and the rest is sampling and encode/decode
code whose cost follows the parameters' encoding geometry rather than the
lattice dimension. η = 2, which ML-DSA-44 shares with -87, needs a mod-5 fold
in rejection sampling and 3-bit packed fields where η = 4 writes nibbles; that
alone accounts for the whole `r5f` keygen spread. ML-DSA-44 additionally has
γ₁ = 2¹⁷ and γ₂ = (q−1)/88, whose 18- and 6-bit fields do not align to bytes,
which is what puts it above -87 in signing. The whole span is 512 bytes, under
2%, and a difference of a couple of hundred bytes is the size of the linker's
own alignment padding - so read these as image sizes, not as code sizes.

## Verification

**Instruction level.** `tools/check_encoding.sh` assembles each ported file for
`cortex-r5` and its pqm4 ancestor for `cortex-m4`, then diffs the two
disassemblies. All six are identical.

```bash
sh tools/check_encoding.sh /path/to/pqm4     # or: PQM4=... sh tools/...
```

pqm4 is deliberately **not** a submodule: it is needed to verify the port, not
to build or use it. `arm-none-eabi-gcc` is required too, so in practice this
runs on Linux or WSL.

**Linked image.** `boards/lp-am243x` can build the assembly straight from a
pqm4 checkout instead of this repository's copies
(`make … PQM4=/path/to/pqm4`); every linked section then comes out
byte-identical. That is the same claim as above, one level further down.

**With strict alignment.** `STRICT_ALIGN=1` is the one switch that departs from
pqm4's instruction stream on purpose, and it takes two things rather than one.
`-DPQR5F_STRICT_ALIGN` switches the two byte-wise variants in the assembly;
`-mno-unaligned-access` stops the compiler emitting unaligned accesses of its
own, which it otherwise does in every C file here. With the define alone an
image still aborts once `SCTLR.A` is set, from GCC's loads rather than pqm4's.
Both halves are in the option.

The whole cost is 252 bytes of text, 0.8%, measured on ML-DSA-87 `r5f` at
`-O3`: `packing.o` pays 280 of it and `vector.o` 12, while `fips202.o` comes
out 64 bytes *smaller*. `ntt.o`, `pointwise_mont.o` and `smallntt_769.o` are
untouched - they have no unaligned access to remove.

`ALIGN_TRAP=1`, in `boards/lp-am243x`, sets `SCTLR.A` so the core aborts on an
unaligned access instead of fixing it up. It is a separate switch deliberately,
because one build on its own proves nothing. All three runs below are on an
AM243x LaunchPad, ML-DSA-87 `r5f`:

| build | result |
| --- | --- |
| `STRICT_ALIGN=1` | passes, checksums unchanged |
| `STRICT_ALIGN=1 ALIGN_TRAP=1` | passes, checksums unchanged |
| `ALIGN_TRAP=1` alone | data abort, as it must |

The abort is the one that matters: without it the other two would only show
that the bit was never enforcing anything. It lands in
`pqcrystals_dilithium_asm_rej_uniform`, on `ldr.w r5, [r2], #3` - a word load
whose pointer advances three bytes an iteration, so it is unaligned on two
iterations in three. That is the access `STRICT_ALIGN=1` replaces, and the only
one reached before the abort.

Enforcement itself is free. The two passing builds differ by under 0.04% on
every operation, and signing comes out marginally *faster* with the bit set,
which bounds its cost at nothing: with no unaligned access left there is no
hardware fixup for it to replace. What costs is the byte-wise code - 3.4% on
key generation, 1.4% on signing and 3.5% on verification, against the figures
under [Performance](#performance). Signing pays least because it spends its
time in the NTT, which the switch does not touch.

**Against an independent implementation.** `tools/check_pqclean.sh` runs
PQClean's clean C on the host over the same deterministic stream. PQClean
shares none of the optimised parts - its NTT, packing and Keccak are plain C -
so agreeing with it is evidence rather than self-consistency.

**End to end.** `test/ml-dsa` contains a keygen → sign → verify → negative test
with a deterministic `randombytes`, so its FNV-1a checksums are a property of
the implementation rather than of the run. Run on an AM243x LaunchPad
(Cortex-R5F) and on a NUCLEO-L4R5ZI (Cortex-M4, pqm4's `m4f`), all three
parameter sets and both variants produce identical checksums:

| scheme | pk | sk | sig | siglen |
| --- | --- | --- | --- | --- |
| ML-DSA-44 | 2c7ff1f9 | b85cd891 | 9450ff0d | 2420 |
| ML-DSA-65 | 4112a0a9 | ee1ffb4c | bf1b9199 | 3309 |
| ML-DSA-87 | e6a211b9 | 061f9cb0 | ddc2821d | 4627 |

Treat these as the regression baseline: if the assembly is touched and they
change, something broke.

**Against the standard.** The checks above say pqr5f agrees with other
implementations. `test/ml-dsa/acvp` holds NIST's ACVP vectors for FIPS 204 - 25
keyGen and 3 sigGen cases per parameter set, generated by `tools/gen_acvp.py`
— which say the implementation is right. Build the board image with `ACVP=1` to
run them on hardware; it goes through the mupq HAL only, so the same test runs
on the Cortex-M4 reference.

All six configurations - three parameter sets by two variants - pass every case
on the AM243x LaunchPad.

That those cases actually reach the ported assembly was established by breaking
it on purpose: changing a single immediate operand in the assembly from 4 to 5
makes every case fail. A suite that passes is evidence only if it would have
failed.

```bash
make vectors                             # asks before downloading 9.9 MB
make vectors ACVP_ARGS=--yes             # for scripts and CI
make vectors ACVP_ARGS="--from ~/ACVP-Server"   # a checkout you already have
```

No NIST data is redistributed here - not the vectors, not arrays generated
from them, not a submodule pointing at them. What the repository carries is
where to get them and NIST's notice, quoted in `NOTICE` as its terms require.
NIST's repository is treated the way the TI SDK is: it lives on your machine,
and the build references it. `tools/gen_acvp.py` fetches three files on
request into a git-ignored cache, generates the C arrays, and asks first; a
board build with `ACVP=1` does the same, and takes `ACVP_ARGS=--yes`.

The fetch names a commit rather than a branch, and each file is checked
against a `sha256` in the script, so what you build from is one stated
revision. Everything except this test builds with no network at all.

NIST is the source of this data and its terms apply; `NOTICE` quotes them. A
pinned revision cannot change under you, so the only thing that can put that
quote out of date is moving the pin - and moving the pin means regenerating,
so the generator compares the two first and refuses to run if they have
diverged.

Passing the vectors is a self-check, not a CAVP or ACVP validation.

## Timing

`ntt.S` carries pqm4's warning that `UMULL` is constant time on the Cortex-M4
but not on the Cortex-M3. Nothing in that follows from the architecture: Arm
defines what an instruction computes, not how long it takes, so "is the long
multiply constant time on Arm-R?" has no architectural answer, only a per-core
one. It matters here because the Montgomery multiplications in `ntt.S` and
`pointwise_mont.S` take secret-dependent operands during signing.

So the multiplier was timed rather than looked up. `boards/lp-am243x` built
with `MULTEST=1` runs chains of identical instructions that differ only in
their operand values, sweeping the leading zeros and ones that early
termination would key on - `0x00000000`, `0x00000001`, `0x000000ff`,
`0x0000ffff`, `0x00ffffff`, `0xffffffff` and `0x5a5a5a5a` - in each operand
position in turn. Every row of every sweep comes out at the same cycle count:

| | cycles per operation | measured as |
| --- | --- | --- |
| `MUL` | 2.00 | throughput, independent |
| `SMULL` | 2.00 | throughput, independent |
| `SMLAL` | 2.94 | latency, accumulating |
| `montgomery_mul_32` | 12.00 | latency, serialised |

The multiplier does not terminate early, so the Montgomery multiplications do
not leak through it, and the long multiply costs exactly what the short one
does. Two caveats: this covers the mechanism that would cause
operand-dependent timing, not every input, and the 12 cycles for
`montgomery_mul_32` are what the sequence costs with nothing to overlap -
`ntt.S` interleaves butterflies so it does not pay that.

## Licensing

Original code is Apache-2.0 (see `LICENSE`). The ported files are modified
third-party sources and carry per-file modification notices; `NOTICE` records
what came from where and what was changed.

The upstream licences are not uniform. Most of what came from pqm4 is
dual-licensed Apache-2.0 / CC0-1.0, `ntt.S` and `keccakf1600.S` are CC0, and
`smallntt.h`, `smallntt_769.S` and `macros_smallntt.i` are Apache-2.0 alone,
Copyright (c) 2023 Junhao Huang. `NOTICE` says which is which.
