/*
 * pqr5f: Cortex-R5F port of pqm4 crypto_sign/ml-dsa-44/m4f/vector.s.
 * 
 * Modified from the pqm4 original. Modifications copyright 2026 Liviu
 * Silaghe, Apache-2.0; upstream terms unchanged - see NOTICE.
 *
 * Two edits: the architecture selection, and the optional byte-wise variant
 * described below. With PQR5F_STRICT_ALIGN off the instruction stream is
 * pqm4's, unchanged; tools/check_encoding.sh checks the encodings against
 * upstream.
 *
 * rej_uniform reads three bytes of SHAKE output with one unaligned
 * "ldr r5, [r2], #3", so it needs SCTLR.A == 0 and Normal memory, and it
 * reads up to one byte past buf+buflen. Assemble with -DPQR5F_STRICT_ALIGN
 * for an aligned, in-bounds byte-wise variant.
 */

#include "pqr5f_arch.i"
.macro redq a, tmp, q
    add     \tmp, \a,  #4194304
    asrs    \tmp, \tmp, #23
    mls     \a, \tmp, \q, \a
.endm

// void asm_reduce32(int32_t a[N]);
.global pqcrystals_dilithium_asm_reduce32
.type pqcrystals_dilithium_asm_reduce32, %function
.align 2
pqcrystals_dilithium_asm_reduce32:
    push {r4-r10}

    movw r12,#:lower16:8380417
    movt r12,#:upper16:8380417
    movw r10, #32
    1:
        ldr.w r1, [r0]
        ldr.w r2, [r0, #1*4]
        ldr.w r3, [r0, #2*4]
        ldr.w r4, [r0, #3*4]
        ldr.w r5, [r0, #4*4]
        ldr.w r6, [r0, #5*4]
        ldr.w r7, [r0, #6*4]
        ldr.w r8, [r0, #7*4]

        redq r1, r9, r12
        redq r2, r9, r12
        redq r3, r9, r12
        redq r4, r9, r12
        redq r5, r9, r12
        redq r6, r9, r12
        redq r7, r9, r12
        redq r8, r9, r12

        str.w r2, [r0, #1*4]
        str.w r3, [r0, #2*4]
        str.w r4, [r0, #3*4]
        str.w r5, [r0, #4*4]
        str.w r6, [r0, #5*4]
        str.w r7, [r0, #6*4]
        str.w r8, [r0, #7*4]
        str r1, [r0], #8*4
        subs r10, #1
        bne.w 1b

    pop {r4-r10}
    bx lr
.size pqcrystals_dilithium_asm_reduce32, .-pqcrystals_dilithium_asm_reduce32

.macro barrett_32 a, Qbar, Q, tmp
    smmulr.w \tmp, \a, \Qbar
    mls.w \a, \tmp, \Q, \a
.endm

// INPUT: target (signed), KYBER_Q (signed)
// OUTPUT: target adjusted to be between -KYBER_Q/2 and KYBER_Q/2
.macro central_reduce target, Q
  cmp \target, \Q, lsr #1
  it hi
  subhi \target, \Q
  cmn \target, \Q, lsr #1
  it lt
  addlt \target, \Q
.endm

// void asm_reduce32(int32_t a[N]);
.global pqcrystals_dilithium_small_asm_reduce32_central
.type pqcrystals_dilithium_small_asm_reduce32_central, %function
.align 2
pqcrystals_dilithium_small_asm_reduce32_central:
    push {r4-r12, lr}


    movw r9, #:lower16:5585133
    movt r9, #:upper16:5585133
    mov.w r10,#769

    movw r12, #32
    1:
        ldr.w r1, [r0]
        ldr.w r2, [r0, #1*4]
        ldr.w r3, [r0, #2*4]
        ldr.w r4, [r0, #3*4]
        ldr.w r5, [r0, #4*4]
        ldr.w r6, [r0, #5*4]
        ldr.w r7, [r0, #6*4]
        ldr.w r8, [r0, #7*4]

        barrett_32 r1, r9, r10, r11
        barrett_32 r2, r9, r10, r11
        barrett_32 r3, r9, r10, r11
        barrett_32 r4, r9, r10, r11
        barrett_32 r5, r9, r10, r11
        barrett_32 r6, r9, r10, r11
        barrett_32 r7, r9, r10, r11
        barrett_32 r8, r9, r10, r11


        str.w r2, [r0, #1*4]
        str.w r3, [r0, #2*4]
        str.w r4, [r0, #3*4]
        str.w r5, [r0, #4*4]
        str.w r6, [r0, #5*4]
        str.w r7, [r0, #6*4]
        str.w r8, [r0, #7*4]
        str r1, [r0], #8*4
        subs r12, #1
        bne.w 1b

    pop {r4-r12, pc}

.size pqcrystals_dilithium_small_asm_reduce32_central, .-pqcrystals_dilithium_small_asm_reduce32_central

.macro caddq a, tmp, q
    and     \tmp, \q, \a, asr #31
    add     \a, \a, \tmp
.endm

.macro freezeq a, tmp, q
    redq \a, \tmp, \q
    caddq \a, \tmp, \q
.endm

// void asm_caddq(int32_t a[N]);
.global pqcrystals_dilithium_asm_caddq
.type pqcrystals_dilithium_asm_caddq, %function
.align 2
pqcrystals_dilithium_asm_caddq:
    push {r4-r10}

    movw r12,#:lower16:8380417
    movt r12,#:upper16:8380417

    movw r10, #32
    1:
        ldr.w r1, [r0]
        ldr.w r2, [r0, #1*4]
        ldr.w r3, [r0, #2*4]
        ldr.w r4, [r0, #3*4]
        ldr.w r5, [r0, #4*4]
        ldr.w r6, [r0, #5*4]
        ldr.w r7, [r0, #6*4]
        ldr.w r8, [r0, #7*4]

        caddq r1, r9, r12
        caddq r2, r9, r12
        caddq r3, r9, r12
        caddq r4, r9, r12
        caddq r5, r9, r12
        caddq r6, r9, r12
        caddq r7, r9, r12
        caddq r8, r9, r12

        str.w r2, [r0, #1*4]
        str.w r3, [r0, #2*4]
        str.w r4, [r0, #3*4]
        str.w r5, [r0, #4*4]
        str.w r6, [r0, #5*4]
        str.w r7, [r0, #6*4]
        str.w r8, [r0, #7*4]
        str r1, [r0], #8*4
        subs r10, #1
        bne.w 1b

    pop {r4-r10}
    bx lr
.size pqcrystals_dilithium_asm_caddq, .-pqcrystals_dilithium_asm_caddq

// asm_rej_uniform(int32_t *a,unsigned int len,const unsigned char *buf, unsigned int buflen);
.global pqcrystals_dilithium_asm_rej_uniform
.type pqcrystals_dilithium_asm_rej_uniform, %function
.align 2
pqcrystals_dilithium_asm_rej_uniform:
    push.w {r4-r6}
    push.w {r1}
    // Store Q-1 in r12.
    movw r12,#:lower16:8380416
    movt r12,#:upper16:8380416

    add.w r6, r0, r1, lsl #2
    add.w r3, r2, r3
    sub.w r3, r3, #2

1:
    // If there are less than 3 bytes available, return.
    cmp.w r3, r2
    ble.w end

#ifdef PQR5F_STRICT_ALIGN
    // The same 24-bit little-endian load, aligned and without reading past the
    // end of the buffer. r4 is callee-saved above and otherwise unused here.
    ldrb r4, [r2]
    ldrb r5, [r2, #1]
    orr  r4, r4, r5, lsl #8
    ldrb r5, [r2, #2]
    orr  r5, r4, r5, lsl #16
    add  r2, r2, #3
#else
    ldr r5, [r2], #3
#endif
    ubfx r5, r5, #0, #23

    cmp.n r5, r12
    it le
    strle r5, [r0], #4

    cmp.n r0, r6
    bne.n 1b

end:
    pop.w {r5}

    sub.w r0, r6, r0
    sub.w r0, r5, r0, lsr #2
    pop.w {r4-r6}
    bx lr
.size pqcrystals_dilithium_asm_rej_uniform, .-pqcrystals_dilithium_asm_rej_uniform
