/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * Deterministic randombytes() for the pqr5f self-test.
 *
 * The output stream is SHAKE128(seed) with a fixed seed, so a keygen/sign run
 * on the Cortex-R5F produces exactly the same key pair and signature as the
 * same test built for the Cortex-M4. That makes it possible to compare the two
 * ports byte for byte instead of only checking that verification succeeds.
 *
 * Obviously: never link this into anything but a test binary.
 */
#include <stdint.h>
#include <stddef.h>

#include "fips202.h"
#include "randombytes.h"

static shake128incctx ctx;
static int initialised = 0;

void randombytes_det_reset(const uint8_t *seed, size_t seedlen);

/*
 * Deliberately does not look at `initialised`: this must work no matter what
 * the RAM contained before. After programming over JTAG the target is often
 * resumed without the C startup having zeroed .bss, so any state left by the
 * previous image is still there.
 */
void randombytes_det_reset(const uint8_t *seed, size_t seedlen) {
    shake128_inc_init(&ctx);
    shake128_inc_absorb(&ctx, seed, seedlen);
    shake128_inc_finalize(&ctx);
    initialised = 1;
}

int PQCLEAN_randombytes(uint8_t *output, size_t n) {
    if (!initialised) {
        static const uint8_t default_seed[32] = {
            'p', 'q', 'r', '5', '-', 'd', 'e', 't',
            'e', 'r', 'm', 'i', 'n', 'i', 's', 't',
            'i', 'c', '-', 't', 'e', 's', 't', '-',
            's', 'e', 'e', 'd', 0, 0, 0, 0
        };
        randombytes_det_reset(default_seed, sizeof(default_seed));
    }
    shake128_inc_squeeze(output, n, &ctx);
    return 0;
}
