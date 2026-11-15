# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
"""Measure pqr5f code size per operation, scheme, variant and -O level.

    python tools/codesize.py                       # the default sweep
    python tools/codesize.py --opt -O3 --csv out.csv

For each configuration this links an image that calls exactly one entry point,
lets --gc-sections drop what that operation cannot reach, and reads the section
sizes back out of the map file, attributing each one to the object it came from.

Only objects built from this repository are counted. memcpy and memset come
from the toolchain's C library and are reported separately, because which libc
you link is not a property of this implementation.

The three operation columns overlap: keygen, sign and verify share the NTT,
Keccak, packing and sampling code, so each column is the closure of one
operation - what an image doing only that would carry - and not a share of a
total. The "all three" row is a real link of all of them together.

Stack is not measured here; it is a runtime property, measured on the board
with STACKPAINT=1.
"""
import argparse
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HARNESS = ROOT / "test" / "codesize"
WORK = ROOT / "build" / "codesize"

CROSS = "arm-none-eabi-"
ARCH = ["-mcpu=cortex-r5", "-mthumb", "-mfpu=vfpv3-d16", "-mfloat-abi=hard"]
MODES = {"44": 2, "65": 3, "87": 5}
OPS = {1: "keygen", 2: "sign", 3: "verify", 0: "all three"}

# .data counts towards both: its initialisers sit in ROM and its variables in
# RAM. .bss is RAM only, .text and .rodata ROM only.
ROM_SECTIONS = (".text", ".rodata", ".data")
RAM_SECTIONS = (".data", ".bss", "COMMON")

# One line per input section, or the name on its own line when it is long:
#   .text.foo      0x0000000c       0x2c build/poly.o
MAP_ONE = re.compile(r"^\s(\.\S+|COMMON)\s+0x[0-9a-f]+\s+0x([0-9a-f]+)\s+(\S+)$")
MAP_NAME = re.compile(r"^\s(\.\S+|COMMON)$")
MAP_REST = re.compile(r"^\s+0x[0-9a-f]+\s+0x([0-9a-f]+)\s+(\S+)$")
# Output sections start in column 0; *fill* carries no object name.
MAP_OUT = re.compile(r"^(\.\S+)\s")
MAP_FILL = re.compile(r"^\s\*fill\*\s+0x[0-9a-f]+\s+0x([0-9a-f]+)")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"failed: {' '.join(str(c) for c in cmd)}\n{r.stdout}{r.stderr}")


def sources(scheme, variant):
    if variant == "pqclean":
        # One directory per parameter set, and no assembly at all. Keccak comes
        # from mupq rather than from PQClean's own common/, whose fips202.c
        # heap-allocates every context - see boards/lp-am243x/Makefile.
        d = ROOT / "mupq" / "pqclean" / "crypto_sign" / f"ml-dsa-{scheme}" / "clean"
        c = sorted(d.glob("*.c")) + [ROOT / "mupq" / "common" / "fips202.c",
                                     ROOT / "mupq" / "common" / "keccakf1600.c"]
        return c, []
    d = ROOT / "crypto_sign" / "ml-dsa-44" / variant
    c = sorted(d.glob("*.c")) + [ROOT / "mupq" / "common" / "fips202.c"]
    s = sorted(d.glob("*.S")) + [ROOT / "common" / "keccakf1600_asm.S"]
    return c, s


def build(scheme, variant, opt, op, out):
    """Compile and link one image; return its map file."""
    d = out / f"{scheme}-{variant}-{opt.lstrip('-')}"
    d.mkdir(parents=True, exist_ok=True)
    csrc, ssrc = sources(scheme, variant)
    if variant == "pqclean":
        impl = ROOT / "mupq" / "pqclean" / "crypto_sign" / f"ml-dsa-{scheme}" / "clean"
        # PQClean namespaces its symbols per parameter set and the harness
        # calls the generic names, so they are mapped here. Same list as
        # PQCNAMES in boards/lp-am243x/Makefile; keep the two together.
        ns = f"PQCLEAN_MLDSA{scheme}_CLEAN"
        mode = [f"-D{n}={ns}_{n}" for n in (
            "crypto_sign_keypair", "crypto_sign_signature",
            "crypto_sign_signature_ctx", "crypto_sign_verify",
            "crypto_sign_verify_ctx", "CRYPTO_PUBLICKEYBYTES",
            "CRYPTO_SECRETKEYBYTES", "CRYPTO_BYTES")]
    else:
        impl = ROOT / "crypto_sign" / "ml-dsa-44" / variant
        mode = [f"-DDILITHIUM_MODE={MODES[scheme]}"]
    inc = ["-I" + str(impl), "-I" + str(ROOT / "common"),
           "-I" + str(ROOT / "mupq" / "common")]
    common = ARCH + mode + inc + ["-ffunction-sections", "-fdata-sections",
                                  "-ffreestanding", "-w"]

    objs = []
    for f in csrc:
        o = d / (f.stem + ".o")
        if not o.exists():
            run([CROSS + "gcc", *common, opt, "-std=c99", "-c", str(f),
                 "-o", str(o)])
        objs.append(o)
    for f in ssrc:
        o = d / (f.stem + ".o")
        if not o.exists():
            run([CROSS + "gcc", *common, "-c", "-x", "assembler-with-cpp",
                 str(f), "-o", str(o)])
        objs.append(o)

    # The harness is recompiled per operation; everything else is shared.
    hobj = d / f"codesize_op{op}.o"
    run([CROSS + "gcc", *common, opt, f"-DPQR5F_OP={op}", "-c",
         str(HARNESS / "codesize.c"), "-o", str(hobj)])

    elf = d / f"op{op}.elf"
    mapf = d / f"op{op}.map"
    run([CROSS + "gcc", *ARCH, str(hobj), *[str(o) for o in objs],
         "-T", str(HARNESS / "codesize.lds"), "-nostartfiles",
         "-Wl,--gc-sections", f"-Wl,-Map={mapf}", "-o", str(elf)])
    return mapf, elf


def elf_size(elf):
    """(ROM, RAM) as size(1) sees it, for checking the map arithmetic."""
    out = subprocess.run([CROSS + "size", str(elf)], capture_output=True,
                         text=True, check=True).stdout.splitlines()[1].split()
    text, data, bss = int(out[0]), int(out[1]), int(out[2])
    return text + data, data + bss


def parse(mapf):
    """{object stem: {'rom': n, 'ram': n}} for the sections that survived.

    The map opens with a "Discarded input sections" block listing everything
    --gc-sections dropped, in the same format as the sections that were kept.
    Summing from the top therefore reports more than the image contains - more,
    in fact, than the image that calls all three operations. Only the part from
    "Linker script and memory map" onwards describes what was linked.
    """
    by_obj = {}
    pending = None
    text = mapf.read_text(errors="replace")
    at = text.find("Linker script and memory map")
    if at < 0:
        sys.exit(f"{mapf}: no 'Linker script and memory map' section")
    section = None          # the output section currently being listed
    for line in text[at:].splitlines():
        out = MAP_OUT.match(line)
        if out:
            section = out.group(1)
            continue
        if f := MAP_FILL.match(line):
            # Alignment padding: real bytes in the image, attributable to no
            # object. Counted so the total reconciles with size(1).
            if section and section.startswith(ROM_SECTIONS):
                by_obj.setdefault("*fill*", {"rom": 0, "ram": 0})["rom"] += \
                    int(f.group(1), 16)
            continue
        m = MAP_ONE.match(line)
        if m:
            name, size, obj = m.group(1), int(m.group(2), 16), m.group(3)
            pending = None
        elif pending and (m := MAP_REST.match(line)):
            name, size, obj = pending, int(m.group(1), 16), m.group(2)
            pending = None
        else:
            n = MAP_NAME.match(line)
            pending = n.group(1) if n else None
            continue
        if size == 0 or not (obj.endswith(".o") or ".o)" in obj):
            continue
        stem = pathlib.Path(obj.split("(")[-1].rstrip(")")).stem
        e = by_obj.setdefault(stem, {"rom": 0, "ram": 0})
        if name.startswith(ROM_SECTIONS):
            e["rom"] += size
        if name.startswith(RAM_SECTIONS) or name == "COMMON":
            e["ram"] += size
    return by_obj


def split(by_obj):
    """Ours versus the toolchain's, keyed by object stem."""
    harness = {"codesize_op0", "codesize_op1", "codesize_op2", "codesize_op3"}
    ours = {"rom": 0, "ram": 0}
    libc = {"rom": 0, "ram": 0}
    for stem, v in by_obj.items():
        if stem in harness:
            continue
        tgt = libc if stem.startswith(("mem", "lib")) or stem in (
            "memcpy", "memset", "memcpy-stub") else ours
        tgt["rom"] += v["rom"]
        tgt["ram"] += v["ram"]
    return ours, libc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--opt", action="append",
                    help="repeatable; default -Os -O2 -O3")
    ap.add_argument("--scheme", action="append", help="default 44 65 87")
    ap.add_argument("--variant", action="append",
                    help="r5f, r5fstack or pqclean; default r5f r5fstack")
    ap.add_argument("--csv")
    ap.add_argument("--keep", action="store_true",
                    help="leave the build tree in place")
    a = ap.parse_args()
    opts = a.opt or ["-Os", "-O2", "-O3"]
    schemes = a.scheme or list(MODES)
    variants = a.variant or ["r5f", "r5fstack"]

    shutil.rmtree(WORK, ignore_errors=True)
    rows = []
    for scheme in schemes:
        for variant in variants:
            for opt in opts:
                for op in (1, 2, 3, 0):
                    mapf, elf = build(scheme, variant, opt, op, WORK)
                    by_obj = parse(mapf)
                    # Everything the map accounts for must equal what the
                    # linker produced. The first version of this parser summed
                    # the discarded sections too and reported more than the
                    # image contained; without this check that passed silently.
                    tot = (sum(v["rom"] for v in by_obj.values()),
                           sum(v["ram"] for v in by_obj.values()))
                    if tot != elf_size(elf):
                        sys.exit(f"{mapf}: map accounts for ROM/RAM {tot}, "
                                 f"but the image is {elf_size(elf)} - the map "
                                 f"parse is wrong, not the image")
                    ours, libc = split(by_obj)
                    rows.append((scheme, variant, opt, OPS[op],
                                 ours["rom"], ours["ram"],
                                 libc["rom"], libc["ram"]))
                    print(f"  ml-dsa-{scheme} {variant:9} {opt:4} "
                          f"{OPS[op]:9}  ROM {ours['rom']:6}  RAM "
                          f"{ours['ram']:6}", flush=True)

    if a.csv:
        out = pathlib.Path(a.csv)
        out.write_text("scheme,variant,opt,operation,rom,ram,libc_rom,libc_ram\n"
                       + "".join(f"ml-dsa-{s},{v},{o},{op},{r},{m},{lr},{lm}\n"
                                 for s, v, o, op, r, m, lr, lm in rows))
        print(f"\n  {out}: {len(rows)} rows")
    if not a.keep:
        shutil.rmtree(WORK, ignore_errors=True)


if __name__ == "__main__":
    main()
