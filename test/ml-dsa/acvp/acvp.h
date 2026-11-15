/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/* Shapes of the generated ACVP vector tables. See tools/gen_acvp.py. */
#ifndef PQR5F_ACVP_H
#define PQR5F_ACVP_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint8_t  seed[32];          /* xi, the keyGen input */
    uint32_t pk_fnv1a;
    uint32_t sk_fnv1a;
} acvp_keygen_case;

typedef struct {
    const uint8_t *sk;
    const uint8_t *msg;
    size_t         msglen;
    const uint8_t *ctx;
    size_t         ctxlen;
    uint32_t       sig_fnv1a;
    size_t         siglen;
} acvp_siggen_case;

extern const acvp_keygen_case acvp_keygen[];
extern const unsigned         acvp_keygen_count;
extern const acvp_siggen_case acvp_siggen[];
extern const unsigned         acvp_siggen_count;

/* Makes the next randombytes() calls return these bytes, then zeros. keyGen
 * needs xi handed to it exactly, and deterministic signing needs the hedging
 * value to be zero. */
void acvp_rng_set(const uint8_t *bytes, size_t len);

void pqr5f_acvp(void);

#endif
