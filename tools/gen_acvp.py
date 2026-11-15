# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Liviu Silaghe
"""Turn NIST's ACVP vectors for FIPS 204 into C arrays for the board.

    python tools/gen_acvp.py test/ml-dsa/acvp/          # asks before fetching
    python tools/gen_acvp.py test/ml-dsa/acvp/ --yes    # for scripts and CI
    python tools/gen_acvp.py test/ml-dsa/acvp/ --from /path/to/ACVP-Server

No NIST data is redistributed with pqr5f - not the vectors, not the arrays this
generates from them, not a submodule pointing at them. The paths and digests
below are locating information, not content: they are what acknowledging NIST
as the source amounts to, and no vector can be rebuilt from them. NIST's
repository is treated the way the TI SDK is: something that lives on your
machine, that this fetches on request, and that the build references. The first
run asks before touching the network; --from uses a checkout you already have
and fetches nothing.

Downloads land in a cache outside the source tree (ACVP_CACHE, else
.acvp-cache/) and are verified against the digests below, so what gets
generated is the content of one named commit and not whatever a URL serves
today.

Only the groups this implementation answers to are taken from sigGen:
deterministic (so the hedging randomness is all zeros), the external signature
interface (ML-DSA.Sign with a context string), pure rather than pre-hash, and
with mu computed internally.

Outputs are compared by FNV-1a rather than byte by byte, so a public key does
not have to be carried in the image alongside the seed that produces it. For a
wrong implementation to agree, a 32-bit checksum would have to collide; the
inputs are the official ones either way.

Before generating anything, this checks that the NIST notice quoted in NOTICE
still matches the one upstream. See check_notice below for why that lives here
rather than in a script of its own.
"""
import hashlib
import json
import os
import pathlib
import re
import sys
import urllib.request

SCHEMES = {"ML-DSA-44": 44, "ML-DSA-65": 65, "ML-DSA-87": 87}
SIGGEN_CASES = 3          # the three with the shortest messages, to stay small

# The pin. Bumping it means replacing all four values together: the commit and
# the digest of each file at it. Raw URLs take a commit, so the fetch is of an
# immutable revision rather than of a branch tip.
ACVP_REPO = "https://github.com/usnistgov/ACVP-Server"
ACVP_COMMIT = "975de31eb83d87039ec88934fdc47d8c312b892d"   # RELEASE/v1.1.0.43
RAW = "https://raw.githubusercontent.com/usnistgov/ACVP-Server"

JSON_DIR = "gen-val/json-files"
KEYGEN_JSON = f"{JSON_DIR}/ML-DSA-keyGen-FIPS204/internalProjection.json"
SIGGEN_JSON = f"{JSON_DIR}/ML-DSA-sigGen-FIPS204/internalProjection.json"
# ACVP-Server has no LICENSE file; its terms are the License section of its
# README, which is why the README is fetched too and not just the vectors.
UPSTREAM_NOTICE = "README.md"

# sha256 of each file at ACVP_COMMIT, over content with newlines normalised to
# LF: a git checkout on Windows stores them as CRLF, so comparing raw bytes
# would reject a perfectly good local copy passed with --from.
DIGESTS = {
    UPSTREAM_NOTICE:
        "d5a569884ee83bd1c4737042d0a2cc7d68c6950690f75a73ef14f505a9aa3555",
    KEYGEN_JSON:
        "e67ee6540d40e11506c3c4e3b1f79fc1cefcd49820db99fc61f87cc8ba463baf",
    SIGGEN_JSON:
        "72dcaf5f69853ca267ccd16af9cb40949786aca0fcfbf05d1ebeba132b93af22",
}
SIZES = {UPSTREAM_NOTICE: 21473, KEYGEN_JSON: 882437, SIGGEN_JSON: 8971659}

# NOTICE delimits NIST's text with these, so a reader can see where the quote
# starts and stops without having to judge by indentation. They are also what
# the check below keys on: the quote is whatever lies between them.
NOTICE_BEGIN = "----- BEGIN TEXT QUOTED FROM NIST"
NOTICE_END = "----- END TEXT QUOTED FROM NIST"


def digest(data: bytes) -> str:
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def have(cache):
    """True when every file is present and matches its digest."""
    for rel, want in DIGESTS.items():
        p = cache / rel
        if not p.is_file() or digest(p.read_bytes()) != want:
            return False
    return True


def consent(total):
    """Ask before using the network. Nothing is downloaded without a yes."""
    print(f"The FIPS 204 test vectors are not part of pqr5f. To generate them,")
    print(f"{len(DIGESTS)} files ({total / 1e6:.1f} MB) have to be downloaded "
          f"from NIST:")
    print(f"  {ACVP_REPO}")
    print(f"  at commit {ACVP_COMMIT}")
    for rel in DIGESTS:
        print(f"    {SIZES[rel] / 1e6:7.2f} MB  {rel}")
    print("They are checked against the digests in this script, and nothing "
          "else is fetched.")
    if not sys.stdin.isatty():
        sys.exit("\nNo terminal to ask on. Re-run with --yes to allow the "
                 "download,\nor with --from <dir> to use a local ACVP-Server "
                 "checkout.")
    try:
        return input("\nDownload them now? [y/N] ").strip().lower() in ("y",
                                                                        "yes")
    except (EOFError, KeyboardInterrupt):
        return False


def fetch(cache, assume_yes):
    if have(cache):
        return
    if not (assume_yes or consent(sum(SIZES.values()))):
        sys.exit("Declined - nothing was downloaded and nothing was "
                 "generated.")
    for rel, want in DIGESTS.items():
        dest = cache / rel
        if dest.is_file() and digest(dest.read_bytes()) == want:
            continue
        url = f"{RAW}/{ACVP_COMMIT}/{rel}"
        print(f"  fetching {rel}")
        with urllib.request.urlopen(url, timeout=180) as r:
            data = r.read()
        got = digest(data)
        if got != want:
            sys.exit(f"\n{rel} does not match the expected content.\n"
                     f"  expected sha256 {want}\n"
                     f"  got             {got}\n"
                     f"Nothing was written. Either the pin in this script is "
                     f"wrong, or what\nwas served is not what it claims to be.")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
    print(f"  cached under {cache}")


def use_local(src, cache):
    """Verify a checkout the user already has, instead of downloading."""
    for rel, want in DIGESTS.items():
        p = src / rel
        if not p.is_file():
            sys.exit(f"{p} not found - is {src} an ACVP-Server checkout?")
        got = digest(p.read_bytes())
        if got != want:
            sys.exit(f"{p} is not the pinned revision.\n"
                     f"  expected sha256 {want}\n  got             {got}\n"
                     f"Check out {ACVP_COMMIT}, or bump the pin in this "
                     f"script.")
    return src


def paragraphs(text):
    """Paragraphs with whitespace flattened, so line wrapping does not count."""
    return [re.sub(r"\s+", " ", p).strip()
            for p in re.split(r"\n\s*\n", text) if p.strip()]


def check_notice(acvp_root, notice_path):
    """Fail unless NOTICE quotes NIST's notice word for word.

    The pin names one immutable revision, so what NOTICE says about it cannot
    rot on its own and a periodic check would have nothing to find. The one
    event that can invalidate it is moving the pin - and moving the pin means
    regenerating the vectors, which means coming through here. So the check
    belongs on this path, where it fires exactly when it can matter, rather
    than on a schedule that is either too early or too late.
    """
    readme = acvp_root / UPSTREAM_NOTICE
    if not readme.is_file():
        sys.exit(f"{readme} not found")

    section = re.search(r"^##+\s*License\s*$(.*?)^##+\s",
                        readme.read_text(encoding="utf-8"),
                        re.MULTILINE | re.DOTALL)
    if not section:
        sys.exit(f"No License section in {readme} - upstream has restructured "
                 f"its README; re-read it and update {notice_path.name}")
    upstream = paragraphs(section.group(1))

    # The quote is exactly what lies between the two markers. Keying on them
    # rather than on indentation means the block can be laid out however reads
    # best, and that removing the markers is an error rather than a silent
    # change of what gets compared.
    text = notice_path.read_text(encoding="utf-8")
    begin = text.find(NOTICE_BEGIN)
    end = text.find(NOTICE_END)
    if begin < 0 or end < 0:
        sys.exit(f"{notice_path.name} does not delimit the quoted NIST text "
                 f"(looked for {NOTICE_BEGIN!r} and {NOTICE_END!r}). The quote "
                 f"has to stay marked, so a reader can tell NIST's words from "
                 f"this project's.")
    if end < begin:
        sys.exit(f"{notice_path.name}: the quote's end marker precedes its "
                 f"start marker")
    ours = paragraphs(text[text.index("\n", begin) + 1:end])

    if ours != upstream:
        extra = [p for p in ours if p not in upstream]
        missing = [p for p in upstream if p not in ours]
        sys.exit(
            f"The NIST notice in {notice_path.name} is not the one in "
            f"{readme}.\n"
            f"  {len(upstream)} paragraph(s) upstream, {len(ours)} quoted; "
            f"{len(missing)} missing, {len(extra)} not upstream.\n"
            + "".join(f"\n  only upstream: {p[:160]}...\n" for p in missing[:3])
            + "".join(f"\n  only in ours:  {p[:160]}...\n" for p in extra[:3])
            + f"\nThe pin has moved to a revision whose terms differ. Read "
              f"the License\nsection of {readme} and copy it across before "
              f"distributing anything built\nfrom this.")


def fnv1a(data: bytes) -> int:
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return h


def c_bytes(name: str, data: bytes) -> str:
    rows = [", ".join(f"0x{b:02x}" for b in data[i:i + 12])
            for i in range(0, len(data), 12)]
    body = ",\n    ".join(rows)
    return f"static const uint8_t {name}[{len(data)}] = {{\n    {body}\n}};\n"


def main(outdir, assume_yes=False, local=None):
    repo = pathlib.Path(__file__).resolve().parent.parent
    if local:
        acvp_root = use_local(pathlib.Path(local), None)
    else:
        acvp_root = pathlib.Path(os.environ.get("ACVP_CACHE",
                                                repo / ".acvp-cache"))
        fetch(acvp_root, assume_yes)
    check_notice(acvp_root, repo / "NOTICE")
    keygen = json.load(open(acvp_root / KEYGEN_JSON))
    siggen = json.load(open(acvp_root / SIGGEN_JSON))
    outdir = pathlib.Path(outdir)

    for setname, scheme in SCHEMES.items():
        out = [f"/* {setname} test vectors from the National Institute of",
               " * Standards and Technology (NIST), ACVP-Server, gen-val/",
               " * json-files/ML-DSA-{keyGen,sigGen}-FIPS204. NIST is the",
               " * source of this data; see NOTICE for its terms.",
               " *",
               " * Changed from the NIST originals: a subset of the cases,",
               " * rewritten as C arrays, with the expected outputs reduced to",
               " * FNV-1a checksums. Generated by tools/gen_acvp.py - do not",
               " * edit, regenerate instead.",
               " */",
               "#include <stdint.h>", "#include \"acvp.h\"", ""]

        kg = [t for g in keygen["testGroups"] if g["parameterSet"] == setname
              for t in g["tests"]]
        rows = []
        for t in kg:
            seed = bytes.fromhex(t["seed"])
            assert len(seed) == 32, len(seed)
            rows.append(f'    {{ {{{", ".join(f"0x{b:02x}" for b in seed)}}}, '
                        f'0x{fnv1a(bytes.fromhex(t["pk"])):08x}u, '
                        f'0x{fnv1a(bytes.fromhex(t["sk"])):08x}u }}')
        out.append(f"const acvp_keygen_case acvp_keygen[] = {{\n"
                   + ",\n".join(rows) + "\n};")
        out.append(f"const unsigned acvp_keygen_count = "
                   f"{len(rows)}u;\n")

        sg = [(g, t) for g in siggen["testGroups"]
              if g["parameterSet"] == setname
              and g.get("deterministic") is True
              and g.get("signatureInterface") == "external"
              and not g.get("externalMu")
              and g.get("preHash") == "pure"
              for t in g["tests"]]
        sg.sort(key=lambda gt: len(gt[1]["message"]))
        sg = sg[:SIGGEN_CASES]

        entries = []
        for i, (_, t) in enumerate(sg):
            sk = bytes.fromhex(t["sk"])
            msg = bytes.fromhex(t["message"])
            ctx = bytes.fromhex(t.get("context", ""))
            out.append(c_bytes(f"sg{i}_sk", sk))
            out.append(c_bytes(f"sg{i}_msg", msg))
            if ctx:
                out.append(c_bytes(f"sg{i}_ctx", ctx))
            entries.append(
                f"    {{ sg{i}_sk, sg{i}_msg, sizeof sg{i}_msg, "
                f"{f'sg{i}_ctx' if ctx else 'NULL'}, {len(ctx)}u, "
                f"0x{fnv1a(bytes.fromhex(t['signature'])):08x}u, "
                f"{len(bytes.fromhex(t['signature']))}u }}")
        out.append("const acvp_siggen_case acvp_siggen[] = {\n"
                   + ",\n".join(entries) + "\n};")
        out.append(f"const unsigned acvp_siggen_count = {len(entries)}u;")

        path = outdir / f"acvp_vectors_{scheme}.c"
        path.write_bytes(("\n".join(out) + "\n").encode())
        print(f"  {path.name}: {len(kg)} keyGen, {len(entries)} sigGen, "
              f"{path.stat().st_size} bytes")


if __name__ == "__main__":
    args = sys.argv[1:]
    yes = "--yes" in args
    args = [a for a in args if a != "--yes"]
    src = None
    if "--from" in args:
        i = args.index("--from")
        if i + 1 >= len(args):
            sys.exit("--from needs a path")
        src = args[i + 1]
        del args[i:i + 2]
    if len(args) != 1:
        print(__doc__)
        sys.exit(2)
    main(args[0], yes, src)
