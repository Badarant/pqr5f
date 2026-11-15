/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Liviu Silaghe */
/*
 * pqr5f: root for a one-operation image, so code size can be attributed.
 *
 * keygen, sign and verify share most of their code - the NTT, Keccak, packing,
 * sampling - so there is no byte that belongs to one of them alone. What can be
 * measured is the closure: link an image that calls exactly one entry point,
 * let --gc-sections drop everything unreachable, and read what is left. That is
 * the figure that matters in practice, because it is what an image doing only
 * that operation has to carry - a verify-only bootloader, say.
 *
 * The columns therefore overlap, and summing them means counting the shared
 * code several times. PQR5F_OP=0 links all three for the combined total.
 *
 * Buffers live at a fixed address rather than in .bss: they are the harness's
 * own, and counting them would report the caller's working set as if it were
 * the implementation's. tools/codesize.py attributes by object file anyway, so
 * nothing here is counted either way.
 */
#include <stddef.h>
#include <stdint.h>

#include "api.h"

#define BUF(off) ((uint8_t *)(0x20100000u + (off)))

/* Not a real PRG. Keygen and signing need the symbol to link; its few bytes
 * belong to this file, which the attribution leaves out. */
void PQCLEAN_randombytes(uint8_t *out, size_t n);
void PQCLEAN_randombytes(uint8_t *out, size_t n)
{
    while (n--)
        *out++ = 0;
}

void _start(void);

void _start(void)
{
    uint8_t *pk = BUF(0), *sk = BUF(0x1000), *sig = BUF(0x3000);
    uint8_t *msg = BUF(0x5000);
    size_t siglen = 0;

#if PQR5F_OP == 1 || PQR5F_OP == 0
    crypto_sign_keypair(pk, sk);
#endif
#if PQR5F_OP == 2 || PQR5F_OP == 0
    crypto_sign_signature(sig, &siglen, msg, 32, sk);
#endif
#if PQR5F_OP == 3 || PQR5F_OP == 0
    crypto_sign_verify(sig, CRYPTO_BYTES, msg, 32, pk);
#endif
    (void)siglen;
    for (;;)
        ;
}
