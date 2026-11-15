/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f: time the multiplier across operand classes.
 *
 * The Arm architecture says nothing about how long a multiply takes; that is a
 * property of the implementation, documented per core rather than per
 * architecture. This answers the question for the core in hand.
 *
 * Each row runs the same code with the same instruction count and alignment,
 * and differs only in the operand values. The comparison is between rows;
 * there is no absolute to compare against. A set of identical rows is a bound,
 * not a proof: it says these classes do not differ, not that the multiplier is
 * constant time for every input.
 *
 * Timing and output go through the mupq HAL and nothing else, so this needs no
 * board header.
 */
#include <stdint.h>

#include "hal.h"

#define CHAIN 16u          /* operations per loop iteration, see multest.S */
#define ITERS 20000u

typedef void (*chain_fn)(uint32_t a, uint32_t b, uint32_t iters);

void pqr5f_mul_chain(uint32_t a, uint32_t b, uint32_t iters);
void pqr5f_mul_chain32(uint32_t a, uint32_t b, uint32_t iters);
void pqr5f_smull_chain(uint32_t a, uint32_t b, uint32_t iters);
void pqr5f_smlal_chain(uint32_t a, uint32_t b, uint32_t iters);
void pqr5f_mont_chain(uint32_t a, uint32_t b, uint32_t iters);
void pqr5f_loop_empty(uint32_t a, uint32_t b, uint32_t iters);

/* Early termination keys on the leading zeros or ones of one operand, and
 * which operand is implementation defined, so each is swept in turn. */
static const uint32_t CLASSES[] = {
    0x00000000u, 0x00000001u, 0x000000ffu, 0x0000ffffu,
    0x00ffffffu, 0xffffffffu, 0x5a5a5a5au,
};
#define NCLASSES (sizeof CLASSES / sizeof CLASSES[0])

static uint32_t loop_overhead;

static uint32_t cycles(void) { return (uint32_t)hal_get_time(); }

/* Restoring division, so nothing here calls into a library. */
static uint32_t udiv(uint32_t n, uint32_t d)
{
    uint32_t q = 0, r = 0;

    if (d == 0u) {
        return 0u;
    }
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) {
            r -= d;
            q |= 1u << i;
        }
    }
    return q;
}

static void put_dec(uint32_t v, int width)
{
    char digits[10];
    char out[16];
    int n = 0, i = 0;

    do {
        uint32_t next = v / 10u;
        digits[n++] = (char)('0' + (v - next * 10u));
        v = next;
    } while (v != 0u);

    for (int pad = width - n; pad > 0; pad--) {
        out[i++] = ' ';
    }
    while (n-- > 0) {
        out[i++] = digits[n];
    }
    out[i] = '\0';
    hal_send_str(out);
}

static void put_hex8(uint32_t v)
{
    static const char hex[] = "0123456789abcdef";
    char out[9];

    for (int i = 0; i < 8; i++) {
        out[i] = hex[(v >> (28 - 4 * i)) & 0xFu];
    }
    out[8] = '\0';
    hal_send_str(out);
}

static void row(chain_fn f, uint32_t shown, uint32_t a, uint32_t b)
{
    uint32_t t0, dt, per100, frac;

    f(a, b, 64u);                               /* warm up */
    t0 = cycles();
    f(a, b, ITERS);
    dt = cycles() - t0;

    dt = (dt > loop_overhead) ? dt - loop_overhead : 0u;

    /* Hundredths of a cycle per operation. 20000 * 16 operations at a handful
     * of cycles each stays inside 32 bits even after the * 100. */
    per100 = udiv(dt * 100u, ITERS * CHAIN);
    frac = per100 % 100u;

    hal_send_str("  0x");
    put_hex8(shown);
    hal_send_str("  ");
    put_dec(dt, 9);
    hal_send_str("  ");
    put_dec(per100 / 100u, 2);
    hal_send_str(frac < 10u ? ".0" : ".");
    put_dec(frac, 0);
    hal_send_str("\r\n");
}

static void sweep(chain_fn f, const char *name)
{
    unsigned i;

    hal_send_str("\r\n");
    hal_send_str(name);
    hal_send_str(", varying the first operand (second = 0xffffffff)\r\n");
    hal_send_str("  operand       cycles  per op\r\n");
    for (i = 0; i < NCLASSES; i++) {
        row(f, CLASSES[i], CLASSES[i], 0xffffffffu);
    }

    hal_send_str("  varying the second operand (first = 0xffffffff)\r\n");
    for (i = 0; i < NCLASSES; i++) {
        row(f, CLASSES[i], 0xffffffffu, CLASSES[i]);
    }
}

void pqr5f_multest(void)
{
    uint32_t t0, t16, t32, empty;

    hal_setup(CLOCK_BENCHMARK);

    pqr5f_loop_empty(0u, 0u, 64u);
    t0 = cycles();
    pqr5f_loop_empty(0u, 0u, ITERS);
    empty = cycles() - t0;

    /* Two-point calibration: the 32- and 16-operation loops differ by exactly
     * 16 multiplies, so the loop cost falls out of the difference. What is
     * left over in the 16-operation run is the loop's real marginal cost,
     * which is smaller than an empty loop suggests because there the branch
     * has nothing to overlap with. */
    pqr5f_mul_chain(0xffffffffu, 0xffffffffu, 64u);
    t0 = cycles();
    pqr5f_mul_chain(0xffffffffu, 0xffffffffu, ITERS);
    t16 = cycles() - t0;

    pqr5f_mul_chain32(0xffffffffu, 0xffffffffu, 64u);
    t0 = cycles();
    pqr5f_mul_chain32(0xffffffffu, 0xffffffffu, ITERS);
    t32 = cycles() - t0;

    loop_overhead = (t32 > t16 && (t32 - t16) < t16) ? t16 - (t32 - t16) : empty;

    hal_send_str("\r\npqr5f: multiplier timing\r\n");
    put_dec(ITERS, 0);
    hal_send_str(" iterations of ");
    put_dec(CHAIN, 0);
    hal_send_str(" operations\r\nloop cost: ");
    put_dec(loop_overhead, 0);
    hal_send_str(" cycles calibrated (");
    put_dec(empty, 0);
    hal_send_str(" measured on an empty loop, which overstates it)\r\n");

    sweep(pqr5f_mul_chain,   "MUL     (independent, throughput)");
    sweep(pqr5f_smull_chain, "SMULL   (independent, throughput)");
    sweep(pqr5f_smlal_chain, "SMLAL   (accumulating, latency)");
    sweep(pqr5f_mont_chain,  "montgomery_mul_32 (smull, mul, smlal)");

    hal_send_str("\r\nRows that match mean no early termination for those\r\n"
                 "operands. The first operand of the Montgomery sweep is the\r\n"
                 "coefficient, which is the one that carries secret data.\r\n");
}
