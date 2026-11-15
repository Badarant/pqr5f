/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
@ pqr5f: bare-metal reset path for the AM243x R5FSS0 core 0, GNU toolchain.
@
@ The MCU+ SDK's nortos kernel - boot, MPU, cache and PMU - is built only with
@ TI Arm Clang, so a GCC build has to bring its own. This replicates what that
@ kernel does for this board, no more: stacks, VFP, the five MPU regions
@ SysConfig generates, caches, then main().
@
@ The core resets into ARM state with the vector table at 0, which is where the
@ SBL jumps. C is compiled Thumb, so entry into main is interworking.

	.syntax unified
	.cpu cortex-r5
	.fpu vfpv3-d16
	.arm

	.section .vectors, "ax"
	.global _vectors
_vectors:
	ldr	pc, =_reset
	ldr	pc, =_undefined
	ldr	pc, =_svc
	ldr	pc, =_prefetch
	ldr	pc, =_abort
	nop
	ldr	pc, =_irq
	ldr	pc, =_fiq

	.text

@ Emit one character on UART0, which the SBL has already configured for its
@ own logging. Used to find how far the reset path gets when nothing else
@ reports. Clobbers r8 and r9, which nothing in _reset holds across a mark.
.macro MARK ch
	ldr	r8, =0x02800000
9991:	ldr	r9, [r8, #0x14]			@ LSR
	tst	r9, #0x20			@ THRE
	beq	9991b
	mov	r9, #\ch
	str	r9, [r8]
.endm

@ Unhandled exceptions stop here. Each says which it was and where, because a
@ silent hang and a data abort look the same on a console, and the faulting
@ address can be looked up in the .map directly.
@
@ lr holds the faulting instruction's address plus 4 in ARM state, plus 2 in
@ Thumb. Nothing returns, so clobbering lr is free.
_undefined:
	MARK 'U'
	b	_fault_addr
_prefetch:
	MARK 'P'
	b	_fault_addr
_abort:
	MARK 'X'
	b	_fault_addr

_fault_addr:
	mov	r0, lr
	bl	_puthex
	b	.

@ Print r0 as 8 hex digits. The digits are computed, not looked up, so this
@ works even when .rodata does not. Clobbers r0-r3, r8, r9.
	.global _puthex
	.type _puthex, %function
_puthex:
	mov	r3, #8
1:	mov	r2, r0, lsr #28
	cmp	r2, #9
	addle	r2, r2, #'0'
	addgt	r2, r2, #('a' - 10)
	ldr	r8, =0x02800000
2:	ldr	r9, [r8, #0x14]
	tst	r9, #0x20
	beq	2b
	str	r2, [r8]
	lsl	r0, r0, #4
	subs	r3, r3, #1
	bne	1b
	bx	lr
	.size _puthex, . - _puthex

@ A spin is greppable in a debugger, a reset loop is not.
_svc:
_irq:
_fiq:
	b	.

	.global _reset
	.type _reset, %function
_reset:
	cpsid	if

	@ One stack per mode, then System mode for the application. The sizes
	@ come from the linker script.
	msr	cpsr_c, #0xD1			@ FIQ
	ldr	sp, =__fiq_stack_top
	msr	cpsr_c, #0xD2			@ IRQ
	ldr	sp, =__irq_stack_top
	msr	cpsr_c, #0xD7			@ Abort
	ldr	sp, =__abort_stack_top
	msr	cpsr_c, #0xDB			@ Undefined
	ldr	sp, =__undef_stack_top
	msr	cpsr_c, #0xD3			@ Supervisor
	ldr	sp, =__svc_stack_top
	msr	cpsr_c, #0xDF			@ System
	ldr	sp, =__stack_top

	@ VFP. The port parks twiddles and a polynomial pointer in s16-s31, so
	@ without this the NTT is wrong, not merely slow.
	mrc	p15, 0, r0, c1, c0, 2
	orr	r0, r0, #(0xF << 20)		@ cp10 and cp11, full access
	mcr	p15, 0, r0, c1, c0, 2
	isb
	mov	r0, #(1 << 30)			@ FPEXC.EN
	vmsr	fpexc, r0

	bl	_mpu_init
	bl	_cache_init

	@ .data from its load address, then .bss.
	ldr	r0, =__data_load
	ldr	r1, =__data_start
	ldr	r2, =__data_end
1:	cmp	r1, r2
	ldrlo	r3, [r0], #4
	strlo	r3, [r1], #4
	blo	1b

	ldr	r0, =__bss_start
	ldr	r1, =__bss_end
	mov	r2, #0
2:	cmp	r0, r1
	strlo	r2, [r0], #4
	blo	2b

	bl	_pmu_init

	ldr	r0, =main
	blx	r0
3:	b	3b
	.size _reset, . - _reset

@ The five regions SysConfig generates for this board. Higher region numbers
@ win where they overlap, so region 0 is the background and 1-4 carve out of
@ it. DRSR = (log2(size) - 1) << 1 | enable.
	.type _mpu_init, %function
_mpu_init:
	mrc	p15, 0, r0, c1, c0, 0
	bic	r0, r0, #1			@ MPU off while reprogramming
	mcr	p15, 0, r0, c1, c0, 0
	isb

	ldr	r12, =_mpu_table
	mov	r11, #0
1:	ldr	r0, [r12], #4			@ base
	cmp	r0, #-1
	beq	2f
	mcr	p15, 0, r11, c6, c2, 0		@ RGNR
	isb
	mcr	p15, 0, r0, c6, c1, 0		@ DRBAR
	ldr	r0, [r12], #4			@ DRACR
	mcr	p15, 0, r0, c6, c1, 4
	ldr	r0, [r12], #4			@ DRSR
	mcr	p15, 0, r0, c6, c1, 2
	add	r11, r11, #1
	b	1b

2:	dsb
	isb
	mrc	p15, 0, r0, c1, c0, 0
	orr	r0, r0, #1			@ M: MPU on
	bic	r0, r0, #2			@ A: keep unaligned access legal
	mcr	p15, 0, r0, c1, c0, 0
	isb
	bx	lr
	.size _mpu_init, . - _mpu_init

	.align 2
_mpu_table:
	@ base        DRACR   DRSR                  what
	.word 0x00000000, 0x1204, (30 << 1) | 1	@ 2G background, device, XN
	.word 0x00000000, 0x020B, (14 << 1) | 1	@ ATCM  32K, normal WB
	.word 0x41010000, 0x020B, (14 << 1) | 1	@ BTCM  32K, normal WB
	.word 0x70000000, 0x020B, (20 << 1) | 1	@ MSRAM  2M, normal WB
	.word 0x60000000, 0x060B, (27 << 1) | 1	@ XIP  256M, normal WB, RO
	.word 0xFFFFFFFF

@ Invalidate L1 by set/way before enabling. The architectural loop rather than
@ the Cortex-R5 implementation-defined register, so it cannot fault.
	.type _cache_init, %function
_cache_init:
	mov	r0, #0
	mcr	p15, 0, r0, c7, c5, 0		@ ICIALLU
	mcr	p15, 2, r0, c0, c0, 0		@ CSSELR = L1 data
	isb
	mrc	p15, 1, r0, c0, c0, 0		@ CCSIDR
	and	r1, r0, #7
	add	r1, r1, #4			@ log2(line bytes)
	ubfx	r2, r0, #3, #10			@ associativity - 1
	ubfx	r3, r0, #13, #15		@ sets - 1
	clz	r4, r2
1:	mov	r5, r2
2:	lsl	r6, r5, r4
	orr	r6, r6, r3, lsl r1
	mcr	p15, 0, r6, c7, c6, 2		@ DCISW
	subs	r5, r5, #1
	bge	2b
	subs	r3, r3, #1
	bge	1b
	dsb

	mrc	p15, 0, r0, c1, c0, 0
	orr	r0, r0, #(1 << 2)		@ C
	orr	r0, r0, #(1 << 12)		@ I
#ifdef PQR5F_ALIGN_TRAP
	@ A: an unaligned access aborts instead of being fixed up by hardware.
	@ Off by default, because pqm4's instruction stream and the compiler's own
	@ output both rely on unaligned loads. Deliberately independent of
	@ STRICT_ALIGN, because the pair of builds is what proves anything:
	@ STRICT_ALIGN=1 ALIGN_TRAP=1 has to run clean, and ALIGN_TRAP=1 on its
	@ own has to take a data abort. Without that second run the first would
	@ only show that this bit was never enforcing anything.
	orr	r0, r0, #(1 << 1)		@ A
#endif
	mcr	p15, 0, r0, c1, c0, 0
	isb
	bx	lr
	.size _cache_init, . - _cache_init

@ Cycle counter, divider off so one tick is one cycle.
	.type _pmu_init, %function
_pmu_init:
	mov	r0, #((1 << 0) | (1 << 2))	@ E, and reset the cycle counter
	mcr	p15, 0, r0, c9, c12, 0		@ PMCR
	mov	r0, #(1 << 31)
	mcr	p15, 0, r0, c9, c12, 1		@ PMCNTENSET
	isb
	bx	lr
	.size _pmu_init, . - _pmu_init
