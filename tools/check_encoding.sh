#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
# Prove that the Cortex-R5F port did not change the instruction stream.
#
# Every pqr5f assembly file is assembled for cortex-r5 (ARMv7-R, T32) and its
# pqm4 ancestor for cortex-m4 (ARMv7E-M, T32); the two disassemblies are then
# compared. An empty diff means the R5F build executes exactly the same
# instructions as the reference M4 implementation, which is the strongest
# functional-equivalence statement available without R5F hardware.
#
# Usage: sh tools/check_encoding.sh [path-to-pqm4]
set -e

root=$(cd "$(dirname "$0")/.." && pwd)

# pqm4 is deliberately not a submodule of this project: it is needed only to
# verify the port, not to build or use it. Point at a local checkout, either
# with the first argument or with $PQM4.
pqm4=${1:-${PQM4:-$root/../pqm4}}

if [ ! -d "$pqm4/crypto_sign/ml-dsa-44/m4f" ]; then
	echo "pqm4 checkout not found at: $pqm4" >&2
	echo "usage: sh tools/check_encoding.sh /path/to/pqm4   (or set PQM4)" >&2
	echo "  git clone --recursive https://github.com/mupq/pqm4" >&2
	exit 2
fi
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT

CC=${CC:-arm-none-eabi-gcc}
OBJDUMP=${OBJDUMP:-arm-none-eabi-objdump}

M4FLAGS="-mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard"
R5FLAGS="-mcpu=cortex-r5 -mthumb -mfpu=vfpv3-d16 -mfloat-abi=hard"

m4dir=$pqm4/crypto_sign/ml-dsa-44/m4f
r5dir=$root/crypto_sign/ml-dsa-44/r5f
m4stack=$pqm4/crypto_sign/ml-dsa-44/m4fstack
r5stack=$root/crypto_sign/ml-dsa-44/r5fstack

# pqr5f file : pqm4 file
#
# Only smallntt_769.S differs between the two variants; the r5fstack copies of
# ntt.S, pointwise_mont.S and vector.S are byte-identical to the r5f ones (pqm4
# symlinks them, which Windows cannot do), and tools/check_variants.sh checks
# that they stay that way.
pairs="
$r5dir/ntt.S:$m4dir/ntt.S
$r5dir/pointwise_mont.S:$m4dir/pointwise_mont.s
$r5dir/vector.S:$m4dir/vector.s
$r5dir/smallntt_769.S:$m4dir/smallntt_769.S
$r5stack/smallntt_769.S:$m4stack/smallntt_769.S
$root/common/keccakf1600.S:$pqm4/common/keccakf1600.S
"

status=0
for pair in $pairs; do
	new=${pair%%:*}
	old=${pair##*:}
	name=$(basename "$new")

	# pqm4 symlinks m4fstack's shared headers to m4f and Windows cannot read
	# those, so the pqm4 side falls back to m4f. The pqr5f side gets no fallback:
	# reaching into our tree would compare our macros against themselves.
	$CC $R5FLAGS -I"$(dirname "$new")" -c -x assembler-with-cpp "$new" -o "$out/new.o"
	$CC $M4FLAGS -I"$(dirname "$old")" -I"$m4dir" -c -x assembler-with-cpp "$old" -o "$out/old.o"

	$OBJDUMP -d --no-show-raw-insn "$out/new.o" | tail -n +3 > "$out/new.txt"
	$OBJDUMP -d --no-show-raw-insn "$out/old.o" | tail -n +3 > "$out/old.txt"

	if diff -u "$out/old.txt" "$out/new.txt" > "$out/diff.txt"; then
		printf '  identical  %s\n' "$name"
	else
		printf '  DIFFERS    %s\n' "$name"
		sed -n '1,40p' "$out/diff.txt"
		status=1
	fi
done

exit $status
