/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f: a randombytes that hands back exactly what it was given.
 *
 * ACVP keyGen supplies xi, and deterministic sigGen requires the hedging value
 * to be zero. Both arrive through randombytes(), so for these vectors it has
 * to replay a buffer rather than generate anything. Once the buffer runs out
 * it returns zeros, which is what deterministic signing wants anyway.
 *
 * Replaces test/randombytes_det.c in the ACVP build; both define the same
 * symbol.
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "acvp.h"

static const uint8_t *src;
static size_t         remaining;

void acvp_rng_set(const uint8_t *bytes, size_t len)
{
    src = bytes;
    remaining = len;
}

int PQCLEAN_randombytes(uint8_t *output, size_t n)
{
    size_t take = (n < remaining) ? n : remaining;

    if (take > 0u) {
        memcpy(output, src, take);
        src += take;
        remaining -= take;
    }
    if (n > take) {
        memset(output + take, 0, n - take);
    }
    return 0;
}
