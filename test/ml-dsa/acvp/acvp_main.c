/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f: run NIST's FIPS 204 vectors.
 *
 * Everything else here checks pqr5f against another implementation - pqm4 on a
 * Cortex-M4, PQClean on the host. Those say the implementations agree. These
 * vectors come from the standard, so they say the implementation is right.
 *
 * keyGen takes xi and must produce the published key pair. sigGen takes a
 * secret key, a context string and a message, with the hedging randomness set
 * to zero, and must produce the published signature.
 *
 * Output goes through the mupq HAL and nothing else, so this runs on any board
 * that provides hal.h - the Cortex-M4 reference included.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "hal.h"
#include "acvp.h"
#include "api.h"
#include "params.h"

/* From PQR5F_PARAM, not from DILITHIUM_MODE, which the pqclean baseline never
 * defines - see the same chain in boards/lp-am243x/pqr5f_bench.c. The vectors
 * themselves are picked by the build system and were never affected; only
 * this label was, and only silently, which is why there is no default. */
#if PQR5F_PARAM == 44
#define SCHEME_LABEL "ML-DSA-44"
#elif PQR5F_PARAM == 65
#define SCHEME_LABEL "ML-DSA-65"
#elif PQR5F_PARAM == 87
#define SCHEME_LABEL "ML-DSA-87"
#else
#error "PQR5F_PARAM must be 44, 65 or 87 - the board Makefile sets it"
#endif

static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t sk[CRYPTO_SECRETKEYBYTES];
static uint8_t sig[CRYPTO_BYTES];

static uint32_t fnv1a(const uint8_t *data, size_t len)
{
    uint32_t h = 2166136261u;

    for (size_t i = 0; i < len; i++) {
        h ^= data[i];
        h *= 16777619u;
    }
    return h;
}

/* Formatting on top of hal_send_str, so this file needs no board header. */
static void put_dec(uint32_t v)
{
    char buf[11];
    int n = 0;

    do {
        uint32_t next = v / 10u;
        buf[n++] = (char)('0' + (v - next * 10u));
        v = next;
    } while (v != 0u);

    char out[12];
    int i = 0;
    while (n-- > 0) {
        out[i++] = buf[n];
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

static unsigned failures;

static void check(const char *what, unsigned id, uint32_t got, uint32_t want)
{
    if (got == want) {
        return;
    }
    failures++;
    hal_send_str("  FAIL ");
    hal_send_str(what);
    hal_send_str(" case ");
    put_dec(id);
    hal_send_str(": got ");
    put_hex8(got);
    hal_send_str(" want ");
    put_hex8(want);
    hal_send_str("\r\n");
}

void pqr5f_acvp(void)
{
    static const uint8_t zero32[32] = { 0 };
    unsigned i;

    hal_setup(CLOCK_BENCHMARK);

    hal_send_str("\r\npqr5f: FIPS 204 ACVP vectors, " SCHEME_LABEL "\r\n");

    hal_send_str("keyGen  ");
    put_dec(acvp_keygen_count);
    hal_send_str(" cases\r\n");
    for (i = 0; i < acvp_keygen_count; i++) {
        acvp_rng_set(acvp_keygen[i].seed, sizeof acvp_keygen[i].seed);
        if (crypto_sign_keypair(pk, sk) != 0) {
            hal_send_str("  FAIL keypair returned non-zero\r\n");
            failures++;
            continue;
        }
        check("keyGen pk", i, fnv1a(pk, sizeof pk), acvp_keygen[i].pk_fnv1a);
        check("keyGen sk", i, fnv1a(sk, sizeof sk), acvp_keygen[i].sk_fnv1a);
    }

    hal_send_str("sigGen  ");
    put_dec(acvp_siggen_count);
    hal_send_str(" cases\r\n");
    for (i = 0; i < acvp_siggen_count; i++) {
        const acvp_siggen_case *c = &acvp_siggen[i];
        size_t siglen = 0;

        /* Deterministic: the hedging value is all zeros. */
        acvp_rng_set(zero32, sizeof zero32);
        if (crypto_sign_signature_ctx(sig, &siglen, c->msg, c->msglen,
                                      c->ctx, c->ctxlen, c->sk) != 0) {
            hal_send_str("  FAIL signature returned non-zero\r\n");
            failures++;
            continue;
        }
        if (siglen != c->siglen) {
            hal_send_str("  FAIL sigGen length\r\n");
            failures++;
            continue;
        }
        check("sigGen", i, fnv1a(sig, siglen), c->sig_fnv1a);
    }

    if (failures == 0u) {
        hal_send_str("\r\npqr5f: ACVP OK\r\n");
    } else {
        hal_send_str("\r\npqr5f: ACVP FAILED, ");
        put_dec(failures);
        hal_send_str(" checks\r\n");
    }
}
