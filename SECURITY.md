# Security policy

## Scope

pqr5f is a benchmark. It measures what pqm4's ML-DSA assembly costs on an Arm
Cortex-R5F. It is not a hardened implementation, it has not been reviewed by
anyone other than its author, and it is not intended for production use.

## What has been established

All of these are reproducible from the repository; see
[Verification](README.md#verification).

- The ported instruction stream is identical to pqm4's, checked by assembling
  both and diffing the disassemblies (`tools/check_encoding.sh`).
- Key generation, signing and verification agree with pqm4 on a Cortex-M4 and
  with PQClean's clean C on a host, over the same deterministic stream.
- NIST's ACVP vectors for FIPS 204 pass on the board in all six ported
  configurations. A deliberately corrupted build fails them, so the vectors
  are known to reach the ported assembly.
- The core's 32-bit multiplier does not terminate early on operand values, so
  the Montgomery multiplications do not leak through it. Measured, not assumed:
  see [Timing](README.md#timing).

## What has not been established

- **Constant-time behaviour of the implementation as a whole.** Only the
  multiplier was measured. No automated analysis has been run - no ctgrind, no
  TIMECOP, no dudect.
- **The signing time depends on secret values.** Rejection sampling repeats
  until it succeeds, and the number of attempts is visible in the total time.
- **Resistance to power, electromagnetic or fault-injection attacks.** There is
  no masking, no redundancy and no countermeasure of any kind.
- **Memory safety under hostile input.** The tests use well-formed inputs and
  NIST's vectors; nothing fuzzes the parsers.
- **Any independent review or audit.**

## Specific hazards in this repository

- `test/randombytes_det.c` is a deterministic generator with a fixed seed. It
  exists so that two ports can be compared byte for byte. A build that links it
  produces the same key pair every time, and that key is published in this
  repository's test checksums. Never link it into anything but a test.
- A passing ACVP run is a self-check. It is not a CAVP or ACVP validation,
  which only an accredited laboratory can perform.
- The library calls `PQCLEAN_randombytes` and does not provide it. FIPS 204
  constrains how strong that generator has to be, and below those strengths the
  claimed security category drops; see
  [Requirements on the target](README.md#requirements-on-the-target).

## Reporting

Open an issue in this repository. This is a single-author project with no
embargo process and no coordinated-disclosure timeline, so please do not expect
one.
