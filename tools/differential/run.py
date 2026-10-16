"""Differential test against libwebp's dwebp.

Corrupts test images (every single-byte change of four kinds, plus random
multi-byte changes inside the lossy token data), decodes each file with this
library and with dwebp, and reports every file where they disagree: one
accepts and the other rejects, or both accept with different pixels.

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

DECODER = "_build/native/release/build/tools/differential/differential.exe"
DWEBP = os.environ.get("DWEBP", "dwebp")


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


def dwebp_md5(path):
    pam = path + ".pam"
    result = subprocess.run([DWEBP, "-quiet", "-pam", path, "-o", pam], capture_output=True)
    if result.returncode != 0:
        return "ERR"
    with open(pam, "rb") as f:
        data = f.read()
    os.remove(pam)
    return hashlib.md5(data[data.index(b"ENDHDR\n") + 7 :]).hexdigest()


def our_md5s(paths):
    results = {}
    for i in range(0, len(paths), 300):
        out = subprocess.run([DECODER] + paths[i : i + 300], capture_output=True, text=True)
        for line in out.stdout.splitlines():
            path, _, result = line.rpartition(" ")
            results[path] = "ERR" if result.startswith("ERR") else result
    return results


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

    ours = our_md5s(paths)
    disagreements = []
    for path in paths:
        theirs = dwebp_md5(path)
        if ours.get(path) != theirs:
            disagreements.append((path, ours.get(path), theirs))
    print(f"{len(paths)} files, {len(disagreements)} disagreements")
    for path, mine, theirs in disagreements:
        print(f"  {os.path.basename(path)}: ours {mine}, dwebp {theirs}")


if __name__ == "__main__":
    main()
