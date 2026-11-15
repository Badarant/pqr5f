/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f self-test and benchmark for the AM243x LaunchPad (Cortex-R5F).
 *
 * Prints, per operation, the minimum and mean cycle count over
 * PQR5F_BENCH_ITERATIONS runs, plus the FNV-1a checksums that let you compare
 * the result against the pqm4 M4 build (randombytes is deterministic here).
 *
 * Output goes through hal_send_str(), timing through pqr5f_cycles(); both live
 * in platform.c.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "platform.h"
#include "fips202.h"
#include "api.h"
#include "params.h"
#include "hal.h"

#ifndef PQR5F_BENCH_ITERATIONS
#define PQR5F_BENCH_ITERATIONS 10
#endif

#define MLEN 59

/* From PQR5F_PARAM, not from DILITHIUM_MODE. The pqclean baseline carries its
 * own params.h per parameter set and never defines DILITHIUM_MODE, so the
 * #else default this chain used to end in printed "ML-DSA-87" over every one
 * of its builds. A wrong label on a measurement log is worse than a build
 * error, hence the #error. */
#if PQR5F_PARAM == 44
#define SCHEME_NAME "ML-DSA-44"
#elif PQR5F_PARAM == 65
#define SCHEME_NAME "ML-DSA-65"
#elif PQR5F_PARAM == 87
#define SCHEME_NAME "ML-DSA-87"
#else
#error "PQR5F_PARAM must be 44, 65 or 87 - the board Makefile sets it"
#endif

/* The parameter set does not identify a build on its own: the two ported
 * variants produce the same checksums and differ only in time and stack, and
 * the baseline differs in all three. One flag per variant, no default. */
#ifdef PQR5F_VARIANT_FAST
#define VARIANT_NAME "-fast"
#elif defined(PQR5F_VARIANT_STACK)
#define VARIANT_NAME "-stack"
#elif defined(PQR5F_VARIANT_PQCLEAN)
#define VARIANT_NAME "-pqclean"
#else
#error "no PQR5F_VARIANT_* flag - the board Makefile sets one per variant"
#endif

static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t sk[CRYPTO_SECRETKEYBYTES];
static uint8_t sig[CRYPTO_BYTES];
static uint8_t msg[MLEN];

void randombytes_det_reset(const uint8_t *seed, size_t seedlen);
void pqr5f_bench_main(void *args);

static uint32_t fnv1a(const uint8_t *data, size_t len) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < len; i++) {
        h ^= data[i];
        h *= 16777619u;
    }
    return h;
}

static uint32_t cpu_mhz = 0;

/* On failure the checksums say which step was already wrong: they are a
 * property of the implementation, not of the run, because randombytes is
 * deterministic. Matching ones mean the step that reported the failure is the
 * first thing to go wrong, not merely the first to notice. */
static void dump_state(const char *what, size_t siglen) {
    pqr5f_puts(what);
    pqr5f_puts("\r\n  state pk ");
    pqr5f_puthex8(fnv1a(pk, sizeof(pk)));
    pqr5f_puts("  sk ");
    pqr5f_puthex8(fnv1a(sk, sizeof(sk)));
    pqr5f_puts("  sig ");
    pqr5f_puthex8(fnv1a(sig, sizeof(sig)));
    pqr5f_puts("  siglen ");
    pqr5f_putdec((uint32_t)siglen, 0);
    pqr5f_puts("\r\n");
}

static void report(const char *what, uint32_t min, uint64_t total, uint32_t n) {
    uint32_t mean = (uint32_t)(total / n);

    pqr5f_puts_pad(what, 8);
    pqr5f_puts(" min ");
    pqr5f_putdec(min, 10);
    pqr5f_puts(" cycles");
    if (cpu_mhz > 0) {
        pqr5f_puts(" (");
        pqr5f_putdec(pqr5f_udiv(min, cpu_mhz), 6);
        pqr5f_puts(" us)");
    }
    pqr5f_puts("   mean ");
    pqr5f_putdec(mean, 10);
    pqr5f_puts(" cycles\r\n");
}

/* Keccak is roughly 70 % of ML-DSA, and a wrong permutation breaks every
 * operation without any of them returning an error. These are the first 16
 * bytes of SHAKE of the empty string and of "abc", so a failure here says the
 * hashing layer is at fault and the polynomial arithmetic is not yet in
 * question. */
static int selftest_shake(void) {
    static const uint8_t want128[16] = {
        0x7f, 0x9c, 0x2b, 0xa4, 0xe8, 0x8f, 0x82, 0x7d,
        0x61, 0x60, 0x45, 0x50, 0x76, 0x05, 0x85, 0x3e };
    static const uint8_t want256[16] = {
        0x46, 0xb9, 0xdd, 0x2b, 0x0b, 0xa8, 0x8d, 0x13,
        0x23, 0x3b, 0x3f, 0xeb, 0x74, 0x3e, 0xeb, 0x24 };
    static const uint8_t want256abc[16] = {
        0x48, 0x33, 0x66, 0x60, 0x13, 0x60, 0xa8, 0x77,
        0x1c, 0x68, 0x63, 0x08, 0x0c, 0xc4, 0x11, 0x4d };
    uint8_t out[16];
    int ok = 1;

    shake128(out, sizeof(out), (const uint8_t *)"", 0);
    if (memcmp(out, want128, sizeof(out)) != 0) { hal_send_str("FAIL shake128(\"\")\r\n"); ok = 0; }

    shake256(out, sizeof(out), (const uint8_t *)"", 0);
    if (memcmp(out, want256, sizeof(out)) != 0) { hal_send_str("FAIL shake256(\"\")\r\n"); ok = 0; }

    shake256(out, sizeof(out), (const uint8_t *)"abc", 3);
    if (memcmp(out, want256abc, sizeof(out)) != 0) { hal_send_str("FAIL shake256(\"abc\")\r\n"); ok = 0; }

    hal_send_str(ok ? "shake self-test OK\r\n" : "shake self-test FAILED\r\n");
    return ok;
}

#ifdef PQR5F_STACK_PAINT
static void stack_row(const char *what) {
    pqr5f_puts_pad(what, 8);
    pqr5f_putdec((uint32_t)hal_checkstack(), 9);
    pqr5f_puts("\r\n");
}
#endif

void pqr5f_bench_main(void *args) {
    /* Keeps its original spelling on purpose: these bytes seed the
       deterministic randombytes, so respelling the string would change every
       published checksum. It is a test-vector constant, not a project name. */
    static const uint8_t seed[32] = "pqr5-deterministic-test-seed";
    /* 32-bit counter, 32-bit differences: correct even across one wrap. */
    uint32_t t0, dt, min_kg = UINT32_MAX, min_sg = UINT32_MAX, min_vf = UINT32_MAX;
    uint64_t tot_kg = 0, tot_sg = 0, tot_vf = 0;
    size_t siglen = 0;
    int rc;

    (void)args;

    hal_setup(CLOCK_BENCHMARK);

    cpu_mhz = pqr5f_cpu_hz() / 1000000u;

    pqr5f_puts("\r\npqr5f: " SCHEME_NAME VARIANT_NAME
               " on Cortex-R5F (AM243x) at ");
    pqr5f_putdec(cpu_mhz, 0);
    pqr5f_puts(" MHz\r\npk ");
    pqr5f_putdec(CRYPTO_PUBLICKEYBYTES, 0);
    pqr5f_puts("  sk ");
    pqr5f_putdec(CRYPTO_SECRETKEYBYTES, 0);
    pqr5f_puts("  sig ");
    pqr5f_putdec(CRYPTO_BYTES, 0);
    pqr5f_puts(" bytes, ");
    pqr5f_putdec(PQR5F_BENCH_ITERATIONS, 0);
    pqr5f_puts(" iterations\r\n");

    if (!selftest_shake()) {
        return;
    }

    for (size_t i = 0; i < MLEN; i++) {
        msg[i] = (uint8_t)i;
    }

    for (uint32_t it = 0; it < PQR5F_BENCH_ITERATIONS; it++) {
        /* Reset the PRG each iteration so every run signs the same key. */
        randombytes_det_reset(seed, sizeof(seed));

        t0 = pqr5f_cycles();
        rc = crypto_sign_keypair(pk, sk);
        dt = pqr5f_cycles() - t0;
        if (rc != 0) { dump_state("FAIL keypair", siglen); return; }
        tot_kg += dt; if (dt < min_kg) min_kg = dt;

        t0 = pqr5f_cycles();
        rc = crypto_sign_signature(sig, &siglen, msg, MLEN, sk);
        dt = pqr5f_cycles() - t0;
        if (rc != 0) { dump_state("FAIL signature", siglen); return; }
        tot_sg += dt; if (dt < min_sg) min_sg = dt;

        t0 = pqr5f_cycles();
        rc = crypto_sign_verify(sig, siglen, msg, MLEN, pk);
        dt = pqr5f_cycles() - t0;
        if (rc != 0) { dump_state("FAIL verify rejected a valid signature", siglen); return; }
        tot_vf += dt; if (dt < min_vf) min_vf = dt;
    }

    /* A tampered signature and a modified message must both be rejected. */
    sig[siglen / 2] ^= 0x01;
    rc = crypto_sign_verify(sig, siglen, msg, MLEN, pk);
    sig[siglen / 2] ^= 0x01;
    if (rc == 0) { hal_send_str("FAIL tampered signature accepted\r\n"); return; }

    msg[0] ^= 0x01;
    rc = crypto_sign_verify(sig, siglen, msg, MLEN, pk);
    msg[0] ^= 0x01;
    if (rc == 0) { hal_send_str("FAIL modified message accepted\r\n"); return; }

    report("keygen", min_kg, tot_kg, PQR5F_BENCH_ITERATIONS);
    report("sign",   min_sg, tot_sg, PQR5F_BENCH_ITERATIONS);
    report("verify", min_vf, tot_vf, PQR5F_BENCH_ITERATIONS);

    pqr5f_puts("checksums pk ");
    pqr5f_puthex8(fnv1a(pk, sizeof(pk)));
    pqr5f_puts("  sk ");
    pqr5f_puthex8(fnv1a(sk, sizeof(sk)));
    pqr5f_puts("  sig ");
    pqr5f_puthex8(fnv1a(sig, siglen));
    pqr5f_puts("  siglen ");
    pqr5f_putdec((uint32_t)siglen, 0);
    pqr5f_puts("\r\n");

#ifdef PQR5F_STACK_PAINT
    /* After the timing, not between the operations: painting touches the whole
     * stack and would leave the data cache full of it. */
    pqr5f_puts("\r\nstack high-water, bytes of ");
    pqr5f_putdec((uint32_t)hal_get_stack_size(), 0);
    pqr5f_puts(" reserved\r\n");

    randombytes_det_reset(seed, sizeof(seed));

    hal_spraystack();
    (void)crypto_sign_keypair(pk, sk);
    stack_row("keygen");

    hal_spraystack();
    (void)crypto_sign_signature(sig, &siglen, msg, MLEN, sk);
    stack_row("sign");

    hal_spraystack();
    (void)crypto_sign_verify(sig, siglen, msg, MLEN, pk);
    stack_row("verify");
#endif

    hal_send_str("pqr5f: OK\r\n");
}
