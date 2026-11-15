#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
# Check the board's checksums against an independent implementation.
#
# The on-target checksums were compared against pqm4 on a Cortex-M4, which
# shares every line of C with this port and the same assembly built for another
# core. A fault in that shared code would agree with itself. PQClean's clean
# implementation shares none of the optimised parts - its NTT, its packing and
# its Keccak are plain C - so agreeing with it is evidence rather than
# self-consistency.
#
# Runs on the host: PQClean's C is portable, and the point is that it is not
# the code under test.
#
# Usage: sh tools/check_pqclean.sh
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
pqclean=$root/mupq/pqclean

if [ ! -d "$pqclean/crypto_sign/ml-dsa-87/clean" ]; then
	echo "PQClean not found - run: git submodule update --init --recursive" >&2
	exit 2
fi

CC=${CC:-gcc}
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

cat > "$out/main.c" <<'EOF'
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include "api.h"

#define MLEN 59
void randombytes_det_reset(const uint8_t *seed, size_t seedlen);

static uint32_t fnv1a(const uint8_t *d, size_t n) {
	uint32_t h = 2166136261u;
	for (size_t i = 0; i < n; i++) { h ^= d[i]; h *= 16777619u; }
	return h;
}

int main(void) {
	/* Same bytes as the on-target tests, deliberately not respelled: they
	   seed the deterministic randombytes the published checksums come from. */
	static const uint8_t seed[32] = "pqr5-deterministic-test-seed";
	static uint8_t pk[CRYPTO_PUBLICKEYBYTES], sk[CRYPTO_SECRETKEYBYTES];
	static uint8_t sig[CRYPTO_BYTES], msg[MLEN];
	size_t siglen = 0;

	for (size_t i = 0; i < MLEN; i++) { msg[i] = (uint8_t)i; }
	randombytes_det_reset(seed, sizeof(seed));

	if (crypto_sign_keypair(pk, sk) != 0) { puts("FAIL keypair"); return 1; }
	if (crypto_sign_signature(sig, &siglen, msg, MLEN, sk) != 0) { puts("FAIL signature"); return 1; }
	if (crypto_sign_verify(sig, siglen, msg, MLEN, pk) != 0) { puts("FAIL verify"); return 1; }

	sig[siglen / 2] ^= 0x01;
	if (crypto_sign_verify(sig, siglen, msg, MLEN, pk) == 0) { puts("FAIL tampered accepted"); return 1; }
	sig[siglen / 2] ^= 0x01;        /* put it back before checksumming */

	printf("%08x %08x %08x %u\n", fnv1a(pk, sizeof(pk)), fnv1a(sk, sizeof(sk)),
	       fnv1a(sig, siglen), (unsigned)siglen);
	return 0;
}
EOF

# The baseline the board prints, from README.md.
expect_44="2c7ff1f9 b85cd891 9450ff0d 2420"
expect_65="4112a0a9 ee1ffb4c bf1b9199 3309"
expect_87="e6a211b9 061f9cb0 ddc2821d 4627"

status=0
for s in 44 65 87; do
	ns=MLDSA$s
	dir=$pqclean/crypto_sign/ml-dsa-$s/clean
	$CC -O2 -I"$dir" -I"$pqclean/common" -I"$root/mupq/common" \
		-Dcrypto_sign_keypair=PQCLEAN_${ns}_CLEAN_crypto_sign_keypair \
		-Dcrypto_sign_signature=PQCLEAN_${ns}_CLEAN_crypto_sign_signature \
		-Dcrypto_sign_verify=PQCLEAN_${ns}_CLEAN_crypto_sign_verify \
		-DCRYPTO_PUBLICKEYBYTES=PQCLEAN_${ns}_CLEAN_CRYPTO_PUBLICKEYBYTES \
		-DCRYPTO_SECRETKEYBYTES=PQCLEAN_${ns}_CLEAN_CRYPTO_SECRETKEYBYTES \
		-DCRYPTO_BYTES=PQCLEAN_${ns}_CLEAN_CRYPTO_BYTES \
		"$out/main.c" "$dir"/*.c "$pqclean/common/fips202.c" \
		"$root/test/randombytes_det.c" -o "$out/kat$s"

	got=$("$out/kat$s")
	eval "want=\$expect_$s"
	if [ "$got" = "$want" ]; then
		printf '  matches   ML-DSA-%s  %s\n' "$s" "$got"
	else
		printf '  DIFFERS   ML-DSA-%s\n    board    %s\n    pqclean  %s\n' "$s" "$want" "$got"
		status=1
	fi
done

exit $status
