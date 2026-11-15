# pqr5f on the AM243x LaunchPad (LP-AM243)

Bare metal on R5FSS0 core 0, built with **arm-none-eabi-gcc** (verified with
10.3.1). No MCU+ SDK code is linked and no C library is on the output path; the
SDK is used only for its prebuilt boot loader and its image-signing scripts.

Runs on hardware and reproduces the reference checksums
(`pk e6a211b9  sk 061f9cb0  sig ddc2821d` for ML-DSA-87), which are the same
values the Cortex-M4 reference produces.

```bash
make SCHEME=ml-dsa-87 VARIANT=r5f    # .elf, .map and the signed image
```

The signed image for the SBL comes out of a plain `make`, because it is the
only thing the board boots - leaving it to an `image` goal produced trees that
looked built and could not be flashed. Without the MCU+ SDK installed the build
stops after the ELF and says so; `image` still exists for that step alone.

`SCHEME` names the algorithm and its parameter set in one token - `ml-dsa-44`,
`ml-dsa-65`, `ml-dsa-87` - so a pair that does not exist cannot be asked for,
and ML-KEM joins as more names rather than a second option. `VARIANT` is
`r5f` or `r5fstack`, `OPT` defaults to
`-O3`, which is what pqm4 uses. Each configuration builds into its own
directory, so switching one rebuilds rather than relinking the last.

GCC is the only toolchain here, and that is the point: pqm4 builds with
`arm-none-eabi-gcc`, so the remaining difference between a pqr5f number and a
published pqm4 one is the core.

## What else the image can be

Each option builds into its own directory, so they coexist and switching does
not relink the last one. `scripts/flash_app.bat` takes the matching keyword.

| option | instead of the benchmark | flash keyword |
| --- | --- | --- |
| `ACVP=1` | NIST's FIPS 204 vectors (fetched, see root README) | `acvp` |
| `MULTEST=1` | multiplier timing across operand classes | `multest` |
| `STACKPAINT=1` | adds stack high-water after the checksums | `paint` |
| `STRICT_ALIGN=1` | removes every unaligned access, assembly and compiler | `align` |
| `ALIGN_TRAP=1` | sets `SCTLR.A`, so an unaligned access aborts | `trap` |
| `PQM4=<path>` | assembles from an upstream pqm4 checkout | — |

```bash
make SCHEME=ml-dsa-87 VARIANT=r5f ACVP=1
scripts/flash_app.bat COM6 ml-dsa-87 r5f acvp
```

## What this directory supplies

| file | what it does |
| --- | --- |
| `startup.S` | vectors, mode stacks, VFP, MPU, cache invalidate and enable, `.data`/`.bss`, PMU, then `main` |
| `am243x_r5f.lds.in` | inner loops in ATCM, everything else in MSRAM; preprocessed per variant |
| `platform.c`, `platform.h` | UART0 transmit, cycle counter, the mupq HAL, a 4 KB heap for `snprintf` |
| `pqr5f_bench.c` | keygen / sign / verify timing and the checksum self-test |
| `scripts/flash_app.ps1`, `scripts/flash_app.bat` | write the signed image into OSPI |

The tests live in `../../test`, grouped by what they belong to:
`ml-dsa/acvp` for the FIPS 204 vectors, `multest` for the multiplier probe,
`randombytes_det.c` shared. None of them includes a header from this
directory - timing and output go through the mupq HAL - so the same files
run on the Cortex-M4 reference.

The five MPU regions in `startup.S` are the ones TI's SysConfig generates for
this board: a 2 GB device background, ATCM, BTCM, 2 MB of MSRAM and the XIP
window. `SCTLR.A` is left clear, because `rej_uniform` and the Keccak absorb
path do unaligned word loads.

`make` checks that `KeccakF1600_Initialize` is in the image before reporting
success. That symbol exists only in the assembly implementation, and this
Makefile has linked the C one instead without saying so: `mupq/common` must be
on the source path for `fips202.c`, and it also holds `keccakf1600.c`, so
whichever pattern rule matches the object name first wins. The assembly rules
are now declared before the C one.

## Building the assembly straight from pqm4

```bash
make SCHEME=ml-dsa-87 VARIANT=r5f PQM4=/path/to/pqm4
```

Assembles `ntt.S`, `pointwise_mont.s`, `vector.s`, `smallntt_769.S`,
`keccakf1600.S` and the two `.i` files from an upstream checkout instead of
this repository's copies. Every linked section comes out byte-identical to the
normal build, which is what the port's spelling changes being encoding-neutral
means in practice.

`r5f` only: pqm4 shares the `m4fstack` sources with symlinks, which Windows
cannot read. Two concessions are needed, both ARMv7-R:

- **`-Wa,-mthumb`**, because pqm4's files mostly omit `.thumb`: on an M-profile
  core the assembler already starts in Thumb state, on Cortex-R5 it does not.
- **`.cpu cortex-m4` stripped from `smallntt_769.S`**, the one upstream file
  that pins the CPU. It tags the object M-profile and the linker then refuses
  to merge it with the R-profile ones; a `.cpu` directive cannot be overridden
  from the command line.

## Running it

```bash
make SCHEME=ml-dsa-87 VARIANT=r5f
scripts/flash_app.bat COM6 ml-dsa-87 r5f
```

with the board in **UART BOOT MODE**; the SDK's EVM Setup page pictures the
switch positions. Then switch to **OSPI BOOT MODE** and power-cycle. The
console is the XDS110 Application/User UART at 115200 8N1.

Two images are written: TI's prebuilt `sbl_ospi` at `0x00000`, which does the
SOC initialisation, and ours at `0x80000`. Flashing needs `pyserial`, and the
signing step needs `pyelftools` and `construct`. Do not install
`tools/boot/multicore-elf/requirements.txt` as a whole: it pins 2019 versions
that no longer build.

Expected output:

```
pqr5f: ML-DSA-87 on Cortex-R5F (AM243x) at 800 MHz
pk 2592  sk 4896  sig 4627 bytes, 10 iterations
keygen   min ....... cycles (..... us)   mean ....... cycles
sign     min ....... cycles (..... us)   mean ....... cycles
verify   min ....... cycles (..... us)   mean ....... cycles
checksums pk e6a211b9  sk 061f9cb0  sig ddc2821d  siglen 4627
pqr5f: OK
```

The checksums are the regression baseline — see the table in the top-level
README. They are identical for both variants and on the Cortex-M4 reference.

There is no JTAG path. Loading over JTAG needs the SOC initialisation to have
run, and the only binary that does it is an SDK example that builds with TI Arm
Clang alone. The SBL does that work on the boot path instead.

## MSRAM starts at 0x70090000, not 0x70080000

The SBL keeps using memory after it has loaded the application, and its own
map — `sbl_ospi/am243x-lp/example.syscfg` — puts `MSRAM_1` at
`0x70070000..0x70090000`. An image linked at `0x70080000` lands inside that,
and comes up with holes in it: a window of a hundred-odd bytes here and there
holding whatever the loader wrote last.

The failure is quiet and moves with the layout. Constants read back as
garbage, so strings print as noise and a lookup table yields wrong results
without anything reporting an error. In one build the hole fell on
`__udivsi3` and the first `printf` executed an undefined instruction; in the
next it fell on `.rodata` and signing produced a wrong signature while key
generation stayed byte-correct.

So `MSRAM` here is `0x70090000` with length `0xF0000`, which clears the
loader's scratch and stops below `APPIMAGE` at `0x70180000`.

If a future image misbehaves in this shape — correct arithmetic, corrupt
constants — check the load address against that syscfg first.

## The TCM is 32 KiB, whatever the SoC header says

`cslr_soc_baseaddress.h` gives R5FSS0 Core0 an `ATCM_SIZE` and a `BTCM_SIZE` of
`0x10000` each, and SysConfig's `physicalLayout.json` agrees at 64 KiB. A JTAG
probe disagreed: a word written at `+0x1000` read back in both TCMs, while
`+0x8000` and `+0xfffc` failed with "unable to access device memory".

The datasheet reconciles them. The cluster has 128 KB of TCM either way, but it
is *128 KB per core in single-core mode and 64 KB per core in dual-core mode*.
This device runs dual-core, so each core gets 64 KB, split 32 KiB ATCM and
32 KiB BTCM. The header reports the single-core figure.

Declaring the linker regions at 64 KiB builds and links cleanly and then never
reaches `main`, because the boot code puts the top of the stack at the top of
the region. So the regions here are 32 KiB.

That probe needed the SDK's SOC-initialisation binary and is no longer in the
tree. The measurement stands; reproducing it would need a TI toolchain.

## If it faults

- **Nothing on the console** — the UART divisor assumes a 48 MHz input clock,
  which is what the SBL leaves configured.
- **Data abort in `rej_uniform` or Keccak** — an MPU region came out Device or
  Strongly-ordered, or `SCTLR.A` got set. Rebuild with `STRICT_ALIGN=1` to
  remove every unaligned access.
- **Undefined instruction on the first `vmov`/`vldm`** — the VFP is not
  enabled; see the `FPEXC` write in `startup.S`.
- **Stack overflow or corrupted results** — `__stack_size` in the linker script
  is 128 KiB, against the 108 KiB pqm4 measures for signing ML-DSA-87.
