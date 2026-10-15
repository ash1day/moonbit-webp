# moonbit-webp

A WebP lossless (VP8L) decoder written in pure MoonBit.

This repository is a showcase. It is not published to mooncakes.io and is not
actively developed.

## What works

- RIFF container parsing (`lib/riff`)
- VP8L lossless decoding to RGBA8 (`lib/vp8l`), including canonical Huffman
  codes, the color cache, LZ77 backward references and all four inverse
  transforms (predictor, color, subtract-green, color indexing)

Lossy (VP8) images, the ALPH chunk and animation are not implemented.

```moonbit
let image = @vp8l.decode_vp8l(webp_bytes) // ImageData { width, height, data }
```

`data` holds `width * height * 4` bytes in RGBA order.

## Packages

| Package | Role |
|---------|------|
| `lib/riff` | RIFF / WebP container chunks |
| `lib/bitreader` | LSB-first bit reader |
| `lib/huffman` | Canonical Huffman trees |
| `lib/transform` | VP8L inverse transforms |
| `lib/vp8l` | VP8L decoder |

## Tests

```bash
moon test
```

The decoder is checked against the MD5 of the RGBA output of `dwebp` for the
lossless images in `testdata/lossless`, `testdata/lossless-extra` and
`testdata/regression`. Malformed input raises `DecodeError` instead of
crashing. Test images come from
[image-rs/image-webp](https://github.com/image-rs/image-webp) and
[libwebp-test-data](https://github.com/webmproject/libwebp-test-data); see
[testdata/CREDITS.md](testdata/CREDITS.md).

## License

Apache-2.0
