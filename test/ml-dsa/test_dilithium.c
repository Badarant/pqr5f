/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f self-test: keygen -> sign -> verify -> negative test, with FNV-1a
 * checksums of every artefact.
 *
 * Because randombytes is deterministic here (test/randombytes_det.c), the four
 * checksums printed by this test are a property of the *implementation*, not of
 * the run. Build the same test against pqm4's m4f implementation on your
 * Cortex-M4 board and against this port on the Cortex-R5F: the checksums must
 * match. That is an end-to-end equivalence check of the ported assembly,
 * complementary to the instruction-level check in tools/check_encoding.sh.
 *
 * The checksums are also implementation independent: ML-DSA keygen and signing
 * are pure functions of the randombytes stream and the message, so the clean C
 * reference must print the same values as any optimised assembly version.
 *
 * Link against: the ML-DSA implementation, test/randombytes_det.c, and a
 * console (see the PQR5F_TEST_NO_HAL switch below).
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#include "api.h"

/*
 * Console. By default this uses the mupq HAL, which pqm4 provides for every
 * supported board (common/hal-opencm3.c for the NUCLEO-L4R5ZI, for instance),
 * so the test drops straight into a pqm4 checkout.
 *
 * Build with -DPQR5F_TEST_NO_HAL to use it anywhere else - a bootloader with
 * its own UART routine, say. You then supply these two yourself:
 *
 *     void pqr5f_test_init(void);              // bring up your console
 *     void pqr5f_test_puts(const char *s);     // write a NUL-terminated string
 */
#ifdef PQR5F_TEST_NO_HAL
void pqr5f_test_init(void);
void pqr5f_test_puts(const char *s);
#else
#include "hal.h"
#define pqr5f_test_init()  hal_setup(CLOCK_FAST)
#define pqr5f_test_puts(s) hal_send_str(s)
#endif

void randombytes_det_reset(const uint8_t *seed, size_t seedlen);

#define MLEN 59

static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
static uint8_t sk[CRYPTO_SECRETKEYBYTES];
static uint8_t sig[CRYPTO_BYTES];
static uint8_t m[MLEN];

static uint32_t fnv1a(const uint8_t *data, size_t len) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < len; i++) {
        h ^= data[i];
        h *= 16777619u;
    }
    return h;
}

static void send_hex(const char *label, uint32_t value) {
    static const char digits[] = "0123456789abcdef";
    char line[64];
    size_t i = 0;

    while (*label && i < sizeof(line) - 12) {
        line[i++] = *label++;
    }
    for (int shift = 28; shift >= 0; shift -= 4) {
        line[i++] = digits[(value >> shift) & 0xf];
    }
    line[i++] = '\n';
    line[i] = '\0';
    pqr5f_test_puts(line);
}

int main(void) {
    /* Keeps its original spelling on purpose: these bytes seed the
       deterministic randombytes, so respelling the string would change every
       published checksum. It is a test-vector constant, not a project name. */
    static const uint8_t seed[32] = "pqr5-deterministic-test-seed";
    size_t siglen;
    int rc;

    pqr5f_test_init();

    /*
     * Seed explicitly rather than relying on the lazy default inside
     * randombytes_det.c. That default only fires when its "initialised" flag
     * is zero, which assumes .bss was cleared and that nothing else has drawn
     * from the stream - neither holds if the application ran first, or if the
     * target was resumed after a JTAG download without a full reset.
     */
    randombytes_det_reset(seed, sizeof(seed));

    for (size_t i = 0; i < MLEN; i++) {
        m[i] = (uint8_t)i;
    }

    if (crypto_sign_keypair(pk, sk) != 0) {
        pqr5f_test_puts("ERROR keypair\n");
        return 1;
    }
    send_hex("pk  ", fnv1a(pk, sizeof(pk)));
    send_hex("sk  ", fnv1a(sk, sizeof(sk)));

    if (crypto_sign_signature(sig, &siglen, m, MLEN, sk) != 0) {
        pqr5f_test_puts("ERROR signature\n");
        return 1;
    }
    send_hex("sig ", fnv1a(sig, siglen));
    send_hex("len ", (uint32_t)siglen);

    rc = crypto_sign_verify(sig, siglen, m, MLEN, pk);
    if (rc != 0) {
        pqr5f_test_puts("ERROR verify rejected a valid signature\n");
        return 1;
    }

    /* Negative test: flipping one bit must make verification fail. */
    sig[siglen / 2] ^= 0x01;
    rc = crypto_sign_verify(sig, siglen, m, MLEN, pk);
    sig[siglen / 2] ^= 0x01;
    if (rc == 0) {
        pqr5f_test_puts("ERROR verify accepted a tampered signature\n");
        return 1;
    }

    /* Negative test: a modified message must fail too. */
    m[0] ^= 0x01;
    rc = crypto_sign_verify(sig, siglen, m, MLEN, pk);
    m[0] ^= 0x01;
    if (rc == 0) {
        pqr5f_test_puts("ERROR verify accepted a modified message\n");
        return 1;
    }

    pqr5f_test_puts("OK\n");
    return 0;
}
