/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
#ifndef PQR5F_ARCH_I
#define PQR5F_ARCH_I

/*
 * pqr5f -- Arm Cortex-R5F (ARMv7-R) port of the pqm4 ML-DSA assembly.
 *
 * Central architecture selection for every assembly file here.
 * The T32 instruction stream is pqm4's: ARMv7-R contains every ARMv7E-M
 * instruction these sources use, and the Cortex-R5F FPU is VFPv3-D16
 * (s0-s31), so pqm4's use of the FP register file as scratch works unchanged.
 *
 * Build with -mfpu=vfpv3xd and -DPQR5F_FPU_VFPV3XD for a single-precision-only
 * Cortex-R5F, or -DPQR5F_NO_ARCH_DIRECTIVES to take .cpu/.fpu from the command
 * line.
 *
 * Runtime requirements (see README.md):
 *   - the VFP must be enabled (CPACR cp10/cp11 + FPEXC.EN) before any call;
 *   - SCTLR.A must be 0 and buffers must be in Normal memory, because
 *     rej_uniform and the Keccak absorb path do unaligned word loads.
 *     -DPQR5F_STRICT_ALIGN gives byte-wise variants instead.
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
