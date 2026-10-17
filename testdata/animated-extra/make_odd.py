# Makes blend_odd.webp: blend.webp with a zero byte appended to every
# even-sized chunk inside its ANMF chunks, so that they all have odd sizes
# and padding.
import struct
import sys


def chunks(data, pos):
    out = []
    while pos + 8 <= len(data):
        size = struct.unpack("<I", data[pos + 4 : pos + 8])[0]
        out.append((data[pos : pos + 4], data[pos + 8 : pos + 8 + size]))
        pos += 8 + size + size % 2
    return out


def chunk(fourcc, payload):
    pad = b"\0" if len(payload) % 2 else b""
    return fourcc + struct.pack("<I", len(payload)) + payload + pad


src, dst = sys.argv[1], sys.argv[2]
data = open(src, "rb").read()
body = b""
for fourcc, payload in chunks(data, 12):
    if fourcc == b"ANMF":
        inner = chunks(payload, 16)
        odd = [(c, p + b"\0" if len(p) % 2 == 0 else p) for c, p in inner]
        payload = payload[:16] + b"".join(chunk(c, p) for c, p in odd)
    body += chunk(fourcc, payload)
open(dst, "wb").write(b"RIFF" + struct.pack("<I", len(body) + 4) + b"WEBP" + body)
