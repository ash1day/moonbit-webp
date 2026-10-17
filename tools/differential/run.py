"""Differential test against libwebp's dwebp.

Corrupts test images (every single-byte change of four kinds, random
multi-byte changes inside the lossy token data, and truncations), decodes
each file with this library and with dwebp, and reports every file where
they disagree: one accepts and the other rejects, or both accept with
different pixels.

There are two kinds of truncation. Cutting the file keeps the sizes in the
RIFF and chunk headers, so both decoders reject it at the container. Cutting
the payload of a VP8, VP8L or ALPH chunk and fixing up those sizes reaches
the end-of-stream handling inside the decoders.

Usage (from the repository root):

    moon build --target native --release
    DWEBP=/path/to/dwebp python3 tools/differential/run.py /tmp/webp-differential [seed]

This library follows libwebp's C code. On corrupt lossy data libwebp's SIMD
code can produce different pixels, and `dwebp -noasm` does not avoid it on
aarch64, where libwebp leaves out the C version of some functions. For an
exact reference, build dwebp without SIMD: in a copy of libwebp, create an
empty src/webp/config.h and run

    make -f makefile.unix examples/dwebp EXTRA_FLAGS=-DHAVE_CONFIG_H DWEBP_LIBS=

DWEBP defaults to `dwebp` on PATH. The run is deterministic for a given seed.

With ANIM_ORACLE set to a build of tools/anim_oracle (against the same
libwebp), the animated test files are corrupted the same way and every
canvas is compared with libwebp's WebPAnimDecoder. Files whose canvas is
larger than the tool's pixel limit, or that libwebp takes more than a few
seconds on, are skipped.
"""

import hashlib
import os
import random
import subprocess
import sys

SINGLE_BYTE_FILES = [
    "lossless-extra/dual_transform",
    "regression/color_index",
    "lossless-extra/one_color_no_palette",
    "regression/lossless_indexed_1bit_palette",
    "lossy-extra/small_31x13",
    "lossy-extra/very_short",
    "alpha-extra/alpha_filter_3",
    "alpha-extra/alpha_no_compression",
    "alpha-extra/alpha_filter_2",
]

TOKEN_FILES = [
    ("lossy-extra/test", 400),
    ("lossy-extra/small_31x13", 400),
    ("lossy-extra/very_short", 400),
    ("lossy-extra/lossy_q0_f100", 400),
    ("lossy/1", 150),
]

TRUNCATED_FILES = SINGLE_BYTE_FILES + [name for name, _ in TOKEN_FILES]

# at most this many truncation lengths per chunk; longer chunks are sampled
MAX_TRUNCATIONS = 300

ANIMATED_FILES = ["animated-extra/offsets", "animated-extra/blend"]

# DECODER can name another build, e.g. "node _build/js/release/build/
# tools/differential/differential.js" after moon build --target js --release
DECODER = os.environ.get(
    "DECODER", "_build/native/release/build/tools/differential/differential.exe"
).split()
DWEBP = os.environ.get("DWEBP", "dwebp")
ANIM_ORACLE = os.environ.get("ANIM_ORACLE")


def single_byte_cases(data, rng):
    for pos in range(12, len(data)):
        values = {data[pos] ^ 1, data[pos] ^ 0x10, data[pos] ^ 0x80, rng.randrange(256)}
        values.discard(data[pos])
        for value in sorted(values):
            out = bytearray(data)
            out[pos] = value
            yield bytes(out)


def token_cases(data, count, rng):
    # the first VP8 partition follows the 10-byte frame header at offset 20
    frame_tag = data[20] | data[21] << 8 | data[22] << 16
    tokens = 30 + (frame_tag >> 5)
    for _ in range(count):
        out = bytearray(data)
        for _ in range(rng.choice([1, 2, 3])):
            out[rng.randrange(tokens, len(data))] = rng.randrange(256)
        yield bytes(out)


def chunks(data):
    """The (fourcc, payload) pairs of a WebP file"""
    out = []
    pos = 12
    while pos + 8 <= len(data):
        size = int.from_bytes(data[pos + 4 : pos + 8], "little")
        out.append((data[pos : pos + 4], data[pos + 8 : pos + 8 + size]))
        pos += 8 + size + size % 2
    return out


def build(parts):
    body = b"".join(
        fourcc + len(payload).to_bytes(4, "little") + payload + b"\0" * (len(payload) % 2)
        for fourcc, payload in parts
    )
    return b"RIFF" + (len(body) + 4).to_bytes(4, "little") + b"WEBP" + body


def truncation_cases(data, rng):
    for length in range(12, len(data)):
        yield data[:length]
    parts = chunks(data)
    for k, (fourcc, payload) in enumerate(parts):
        if fourcc not in (b"VP8 ", b"VP8L", b"ALPH"):
            continue
        lengths = range(len(payload))
        if len(payload) > MAX_TRUNCATIONS:
            lengths = sorted(rng.sample(lengths, MAX_TRUNCATIONS))
        for length in lengths:
            yield build(parts[:k] + [(fourcc, payload[:length])] + parts[k + 1 :])


def frame_truncation_cases(data, rng):
    """Truncates the payload of each chunk inside each ANMF chunk, fixing up
    the chunk, ANMF and RIFF sizes"""
    parts = chunks(data)
    for k, (fourcc, payload) in enumerate(parts):
        if fourcc != b"ANMF":
            continue
        header, inner = payload[:16], chunks(b"\0" * 12 + payload[16:])
        for j, (inner_fourcc, inner_payload) in enumerate(inner):
            lengths = range(len(inner_payload))
            if len(inner_payload) > MAX_TRUNCATIONS:
                lengths = sorted(rng.sample(lengths, MAX_TRUNCATIONS))
            for length in lengths:
                cut = inner[:j] + [(inner_fourcc, inner_payload[:length])] + inner[j + 1 :]
                anmf = header + build(cut)[12:]
                yield build(parts[:k] + [(fourcc, anmf)] + parts[k + 1 :])


def oracle_line(path):
    """tools/anim_oracle's output in the form the decoder prints, None to skip"""
    try:
        result = subprocess.run(
            [ANIM_ORACLE, path], capture_output=True, text=True, timeout=5
        )
    except subprocess.TimeoutExpired:
        return None
    lines = result.stdout.split("\n")
    if not lines[0].startswith("canvas") or "error" in lines:
        return "ERR"
    _, w, h, _, loop, _, bg, _, n = lines[0].split()
    out = f"canvas_{w}_{h}_loop_{loop}_bgcolor_{int(bg, 16)}_frames_{n}"
    for line in lines[1:]:
        if line.startswith("frame"):
            _, _, _, ts, _, md5 = line.split()
            out += f"|{ts}:{md5}"
    return out


def compare_animations(out_dir, rng):
    paths = []
    for name in ANIMATED_FILES:
        with open(f"testdata/{name}.webp", "rb") as f:
            data = f.read()
        cases = list(single_byte_cases(data, rng)) + list(truncation_cases(data, rng))
        cases += list(frame_truncation_cases(data, rng))
        for k, case in enumerate(cases):
            path = os.path.join(out_dir, f"{name.replace('/', '_')}_anim_{k}.webp")
            with open(path, "wb") as f:
                f.write(case)
            paths.append(path)
    ours = run_decoder(["--animation"], paths)
    disagreements, skipped = [], 0
    for path in paths:
        mine = ours[path]
        if mine.startswith("ERR:TooLarge"):
            skipped += 1
            continue
        mine = "ERR" if mine.startswith("ERR") else mine
        theirs = oracle_line(path)
        if theirs is None:
            skipped += 1
        elif mine != theirs:
            disagreements.append((path, mine, theirs))
    print(f"{len(paths)} animation files, {skipped} skipped, {len(disagreements)} disagreements")
    for path, mine, theirs in disagreements:
        print(f"  {os.path.basename(path)}: ours {mine[:60]}, libwebp {theirs[:60]}")


def dwebp_md5(path):
    pam = path + ".pam"
    result = subprocess.run([DWEBP, "-quiet", "-pam", path, "-o", pam], capture_output=True)
    if result.returncode != 0:
        return "ERR"
    with open(pam, "rb") as f:
        data = f.read()
    os.remove(pam)
    return hashlib.md5(data[data.index(b"ENDHDR\n") + 7 :]).hexdigest()


def run_decoder(args, paths):
    """The decoder's result for each path. A crash is not a rejection: when a
    batch exits abnormally, each file is run alone and the ones that crash
    get "CRASH", which never matches libwebp."""
    results = {}
    for i in range(0, len(paths), 300):
        batch = paths[i : i + 300]
        out = subprocess.run(DECODER + args + batch, capture_output=True, text=True)
        if out.returncode != 0:
            for path in batch:
                one = subprocess.run(DECODER + args + [path], capture_output=True, text=True)
                line = one.stdout.strip()
                ok = one.returncode == 0 and line.startswith(path + " ")
                results[path] = line.rpartition(" ")[2] if ok else "CRASH"
            continue
        for line in out.stdout.splitlines():
            path, _, result = line.rpartition(" ")
            results[path] = result
    for path in paths:
        results.setdefault(path, "CRASH")
    return results


def our_md5s(paths):
    results = run_decoder([], paths)
    return {p: "ERR" if r.startswith("ERR") else r for p, r in results.items()}


def main():
    out_dir = sys.argv[1]
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    os.makedirs(out_dir, exist_ok=True)
    rng = random.Random(seed)
    version = subprocess.run([DWEBP, "-version"], capture_output=True, text=True).stdout.strip()
    print(f"{DWEBP} {version}, seed {seed}")

    paths = []
    def write(name, k, data):
        path = os.path.join(out_dir, f"{name.replace('/', '_')}_{k}.webp")
        with open(path, "wb") as f:
            f.write(data)
        paths.append(path)

    for name in SINGLE_BYTE_FILES:
        with open(f"testdata/{name}.webp", "rb") as f:
            data = f.read()
        for k, case in enumerate(single_byte_cases(data, rng)):
            write(name, k, case)
    for name, count in TOKEN_FILES:
        with open(f"testdata/{name}.webp", "rb") as f:
            data = f.read()
        for k, case in enumerate(token_cases(data, count, rng)):
            write(name + "_tokens", k, case)

    for name in TRUNCATED_FILES:
        with open(f"testdata/{name}.webp", "rb") as f:
            data = f.read()
        for k, case in enumerate(truncation_cases(data, rng)):
            write(name + "_truncated", k, case)

    ours = our_md5s(paths)
    disagreements = []
    for path in paths:
        theirs = dwebp_md5(path)
        if ours.get(path) != theirs:
            disagreements.append((path, ours.get(path), theirs))
    print(f"{len(paths)} files, {len(disagreements)} disagreements")
    for path, mine, theirs in disagreements:
        print(f"  {os.path.basename(path)}: ours {mine}, dwebp {theirs}")
    if ANIM_ORACLE:
        compare_animations(out_dir, rng)


if __name__ == "__main__":
    main()
