/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
#ifndef PQR5F_ARCH_I
#define PQR5F_ARCH_I

/*
 * pqr5f -- Arm Cortex-R5F (ARMv7-R) port of the pqm4 ML-DSA assembly.
 *
 * Central architecture selection for every assembly file in this
 * project.  The port keeps the original T32 (Thumb-2) instruction stream: the
 * Cortex-R5F implements ARMv7-R, which contains every instruction used by the
 * ARMv7E-M sources (DSP/SIMD: smlad, smuad, smulwb, smlabt, pkhbt/pkhtb,
 * uadd16/usub16, sadd16/ssub16, smmulr; plus movw/movt, ldrd/strd, IT blocks).
 *
 * The Cortex-R5F FPU is VFPv3-D16 (s0-s31), so the pqm4 trick of using the
 * floating-point register file as extra scratch storage works unchanged.
 * Build with -mfpu=vfpv3xd and -DPQR5F_FPU_VFPV3XD for a single-precision-only
 * Cortex-R5F, or define PQR5F_NO_ARCH_DIRECTIVES to take .cpu/.fpu purely from
 * the command line.
 *
 * Runtime requirements on the target (see ../../../README.md):
 *   - the VFP must be enabled (CPACR cp10/cp11 + FPEXC.EN) before any of these
 *     routines is called;
 *   - SCTLR.A must be 0 and the buffers must live in Normal (not Device or
 *     Strongly-ordered) memory, because rej_uniform and the Keccak absorb path
 *     perform unaligned word loads.  Assemble with -DPQR5F_STRICT_ALIGN to get
 *     byte-wise variants instead.
 */

.syntax unified

#ifndef PQR5F_NO_ARCH_DIRECTIVES
.cpu cortex-r5
#if defined(PQR5F_FPU_VFPV3XD)
.fpu vfpv3xd
#else
.fpu vfpv3-d16
#endif
#endif

.thumb

#endif /* PQR5F_ARCH_I */
