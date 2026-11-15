#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
# The r5f and r5fstack implementations share most of their sources. pqm4 does
# this with symbolic links from m4fstack into m4f; Windows cannot follow those,
# so pqr5f keeps real copies, and each directory has to be self-contained anyway
# because a quoted #include resolves against the directory of the file that
# issues it - r5f/packing.h would pull r5f/smallpoly.h even from an r5fstack
# build.
#
# This checks that the shared copies have not drifted apart.
#
#   sh tools/check_variants.sh
set -e

root=$(cd "$(dirname "$0")/.." && pwd)
a=$root/crypto_sign/ml-dsa-44/r5f
b=$root/crypto_sign/ml-dsa-44/r5fstack

# Everything r5fstack takes unchanged from r5f. The files deliberately left out
# are the ones pqm4's m4fstack replaces: reduce.h, sign.c, smallntt.h,
# smallntt_769.S, smallpoly.c, smallpoly.h, plus its own stack.c/stack.h.
shared="api.h config.h macros.i macros_smallntt.i ntt.S ntt.h packing.c \
        packing.h params.h pointwise_mont.S pointwise_mont.h poly.c poly.h \
        polyvec.c polyvec.h pqr5f_arch.i rounding.c rounding.h sign.h \
        symmetric.h symmetric-shake.c vector.S vector.h"

status=0
for f in $shared; do
	if cmp -s "$a/$f" "$b/$f"; then
		:
	else
		printf '  DRIFTED  %s\n' "$f"
		status=1
	fi
done

if [ $status -eq 0 ]; then
	printf '  all %s shared files identical between r5f and r5fstack\n' \
	    "$(echo $shared | wc -w)"
fi

exit $status
