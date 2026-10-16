# moonbit-webp

A WebP decoder written in pure MoonBit. Lossless (VP8L) and lossy (VP8)
images decode to the same pixels as libwebp's `dwebp`.

It is not published to mooncakes.io yet.

## What works

- `decode` (the root package): reads simple and extended (VP8X) WebP files,
  picks the lossless or lossy decoder and applies the ALPH chunk
- RIFF container parsing (`lib/riff`)
- VP8L lossless decoding to RGBA8 (`lib/vp8l`), including canonical Huffman
  codes, the color cache, LZ77 backward references and all four inverse
  transforms (predictor, color, subtract-green, color indexing)
- VP8 lossy decoding to RGBA8 (`lib/vp8`), bit-exact with libwebp: boolean
  decoder, intra prediction, inverse DCT/WHT, simple and normal loop filters,
  and the fancy chroma upsampling that `dwebp` uses by default
- Alpha for lossy images: the ALPH chunk, uncompressed or VP8L-compressed,
  with the horizontal, vertical and gradient filters

Animated images raise `DecodeError`.

```moonbit
// ImageData { width, height, data }
let image = @webp.decode(webp_bytes) catch {
  // Write `DecodeError(msg)`, not `@webp.DecodeError(msg)`: the type is
  // re-exported from `lib/image`, so only the unqualified constructor resolves
  DecodeError(msg) => {
    println(msg)
    return
  }
}
```

`data` holds `width * height * 4` bytes in RGBA order.

## Packages

| Package | Role |
|---------|------|
| (root) | `decode`, VP8X and ALPH |
| `lib/image` | `ImageData` and `DecodeError` |
| `lib/riff` | RIFF / WebP container chunks |
| `lib/bitreader` | LSB-first bit reader |
| `lib/huffman` | Canonical Huffman trees |
| `lib/transform` | VP8L inverse transforms |
| `lib/vp8l` | VP8L decoder |
| `lib/vp8` | VP8 decoder |

## Tests

```bash
moon test
```

The decoders are checked against the MD5 of the RGBA output of `dwebp` for the
images in `testdata/lossless`, `testdata/lossless-extra`, `testdata/lossy`,
`testdata/lossy-extra`, `testdata/alpha`, `testdata/alpha-extra` and
`testdata/regression`. The VP8 building blocks (transforms, predictors, loop
filters, upsampling) are also checked against values produced by libwebp's C
functions. Malformed input raises `DecodeError` instead of crashing. Test
images come from
[image-rs/image-webp](https://github.com/image-rs/image-webp) and
[libwebp-test-data](https://github.com/webmproject/libwebp-test-data); see
[testdata/CREDITS.md](testdata/CREDITS.md).

## License

Apache-2.0
