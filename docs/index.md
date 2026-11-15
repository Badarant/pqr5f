---
title: pqr5f measurements
---

# pqr5f — measured results

Post-quantum cryptography for the Arm Cortex-R5F, ported from pqm4 with the
instruction stream left intact.

**This is a benchmark, not a product.** It measures what the ML-DSA assembly
costs on this core. No side-channel claim is made beyond a single measurement
of the multiplier, nothing here has been reviewed by anyone other than its
author, and passing NIST's vectors is a self-check rather than a validation.
Use it to decide whether ML-DSA fits your Cortex-R5F; do not ship it.

## ML-DSA (FIPS 204)

- [Time, peak stack and ROM, nine builds](ml-dsa/performance.html) — PQClean's
  C reference and both ported assembly variants, three parameter sets each, on
  an AM243x LaunchPad at 800 MHz.

The figures come from `measurements/ml-dsa/measurements.csv` (cycles and peak
stack, measured on the board) and `measurements/ml-dsa/codesize.csv` (ROM, read
out of the linker map), both in the repository.
