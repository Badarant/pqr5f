/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f: is the Cortex-R5F integer multiplier data-dependent?
 *
 * Two loops with identical structure and instruction counts. One runs MUL
 * with the operands held in r0 and r1 for the whole run, so an operand class
 * is held constant across every multiply; the other runs the loop alone, so
 * its cost can be subtracted. The difference between operand classes is the
 * measurement; there is no absolute to compare against.
 *
 * The multiplies are independent, so this measures throughput. A multiplier
 * that terminates early issues the easy cases faster, which shows up there.
 */
#include "pqr5f_arch.i"

	.text

@ void pqr5f_mul_chain(uint32_t a, uint32_t b, uint32_t iters)
	.global pqr5f_mul_chain
	.type pqr5f_mul_chain, %function
	.align 4
pqr5f_mul_chain:
	push	{r4}
1:
	.rept 16
	mul	r4, r0, r1
	.endr
	subs	r2, r2, #1
	bne	1b
	pop	{r4}
	bx	lr
	.size pqr5f_mul_chain, . - pqr5f_mul_chain

@ void pqr5f_mul_chain32(uint32_t a, uint32_t b, uint32_t iters)
@ The same loop with twice the multiplies. Subtracting the 16-operation run
@ from this one leaves exactly 16 multiplies, with the loop cost cancelling
@ instead of being estimated from an empty loop - where the branch has nothing
@ to overlap with and so costs more than it does in a real one.
	.global pqr5f_mul_chain32
	.type pqr5f_mul_chain32, %function
	.align 4
pqr5f_mul_chain32:
	push	{r4}
1:
	.rept 32
	mul	r4, r0, r1
	.endr
	subs	r2, r2, #1
	bne	1b
	pop	{r4}
	bx	lr
	.size pqr5f_mul_chain32, . - pqr5f_mul_chain32

@ void pqr5f_smull_chain(uint32_t a, uint32_t b, uint32_t iters)
@ Independent, like the MUL chain: throughput.
	.global pqr5f_smull_chain
	.type pqr5f_smull_chain, %function
	.align 4
pqr5f_smull_chain:
	push	{r4, r5}
1:
	.rept 16
	smull	r4, r5, r0, r1
	.endr
	subs	r2, r2, #1
	bne	1b
	pop	{r4, r5}
	bx	lr
	.size pqr5f_smull_chain, . - pqr5f_smull_chain

@ void pqr5f_smlal_chain(uint32_t a, uint32_t b, uint32_t iters)
@ Accumulates into the same pair, so each one waits for the last: this is
@ latency, not throughput. The multiplicands stay in r0 and r1 either way,
@ which is what holds the operand class.
	.global pqr5f_smlal_chain
	.type pqr5f_smlal_chain, %function
	.align 4
pqr5f_smlal_chain:
	push	{r4, r5}
	mov	r4, #0
	mov	r5, #0
1:
	.rept 16
	smlal	r4, r5, r0, r1
	.endr
	subs	r2, r2, #1
	bne	1b
	pop	{r4, r5}
	bx	lr
	.size pqr5f_smlal_chain, . - pqr5f_smlal_chain

@ void pqr5f_mont_chain(uint32_t a, uint32_t b, uint32_t iters)
@ montgomery_mul_32 from macros.i, unchanged, with Q and Qprime as ntt.S loads
@ them. r0 is the coefficient - the secret operand in signing - and r1 the
@ twiddle. The accumulator is reloaded from r0 every time so the class holds;
@ that mov costs the same in every run and cancels between them.
	.global pqr5f_mont_chain
	.type pqr5f_mont_chain, %function
	.align 4
pqr5f_mont_chain:
	push	{r4-r8}
	movw	r6, #:lower16:0xfc7fdfff
	movt	r6, #:upper16:0xfc7fdfff	@ Qprime
	movw	r7, #0xE001
	movt	r7, #0x7F			@ Q = 8380417
1:
	.rept 16
	mov	r4, r0
	smull	r5, r4, r4, r1
	mul	r8, r5, r6
	smlal	r5, r4, r8, r7
	.endr
	subs	r2, r2, #1
	bne	1b
	pop	{r4-r8}
	bx	lr
	.size pqr5f_mont_chain, . - pqr5f_mont_chain

@ void pqr5f_loop_empty(uint32_t a, uint32_t b, uint32_t iters)
@ The same loop without the multiplies, to subtract the counter and the branch.
	.global pqr5f_loop_empty
	.type pqr5f_loop_empty, %function
	.align 4
pqr5f_loop_empty:
	push	{r4}
1:
	subs	r2, r2, #1
	bne	1b
	pop	{r4}
	bx	lr
	.size pqr5f_loop_empty, . - pqr5f_loop_empty
