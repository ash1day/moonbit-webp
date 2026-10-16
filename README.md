# moonbit-webp

A WebP decoder written in pure MoonBit. It decodes lossless (VP8L), lossy
(VP8) and lossy-with-alpha images to RGBA, and produces exactly the same
pixels as libwebp's `dwebp`.

Because it has no C dependency, it runs on every MoonBit backend: wasm-gc,
wasm, JavaScript and native.

## Install

```bash
moon add ash1day/webp
```

Then import `ash1day/webp` in your package's `moon.pkg`.

## Usage

```moonbit
let image = @webp.decode(webp_bytes) catch {
  // Write the constructors without a prefix, or as
  // `@webp.DecodeError::Invalid(message)`. `@webp.Invalid(message)` does not
  // resolve because `DecodeError` is re-exported from `ash1day/webp/image`
  Invalid(message) => abort("corrupt file: \{message}")
  Unsupported(message) => abort("not supported: \{message}")
  TooLarge(message) => abort(message)
}
// image.width, image.height
// image.data: width * height * 4 bytes, RGBA, not premultiplied
```

`DecodeError` also implements `Show`, so `e.to_string()` gives a readable
message such as `invalid WebP: bad VP8 start code`.

### Untrusted input

`decode` reads the image size from the headers and checks it before it
allocates any pixel buffer. By default it accepts any size the format allows
(16384 x 16384), which lets a file of a few bytes make `decode` allocate
about 1.5 GB. Set `max_pixels` when the input comes from outside:

```moonbit
let image = @webp.decode(webp_bytes, max_pixels=4096 * 4096)
```

Decoding a lossy image needs about 6 bytes of memory per pixel, including the
4-byte RGBA output (146 MB peak for a 24-megapixel image on native).

## What is supported

- Simple and extended (VP8X) WebP files
- Lossless images: all transforms, the color cache and LZ77 references
- Lossy images: all intra prediction modes, both loop filters and the fancy
  chroma upsampling that `dwebp` uses by default
- Alpha for lossy images (the ALPH chunk), uncompressed or compressed, with
  every filter

Not supported:

- Animation (`Unsupported` is raised)
- Color profiles (ICCP) and EXIF/XMP metadata are ignored
- Encoding

## How it is tested

```bash
moon test --target all
```

- Every test image in `testdata/` (about 50 lossless, lossy and alpha images
  from libwebp's test vectors and the image-rs test suite) is decoded and the
  MD5 of the RGBA output is compared with `dwebp -pam`
- The lossy building blocks (transforms, predictors, loop filters,
  upsampling) are compared with values produced by libwebp's C functions
- Every truncation and many single-byte corruptions of several files must
  raise `DecodeError` instead of crashing
- CI runs the tests on all four backends

Decoding the 24-megapixel `testdata/lossy-extra/bryce.webp` takes about
0.9 s on native and 2.2 s on wasm-gc.

## Packages

Only the root package and `image` are public. The decoders live under
`internal/` and cannot be imported from other modules.

| Package | Role |
|---------|------|
| `ash1day/webp` | `decode`, VP8X and ALPH handling |
| `ash1day/webp/image` | `ImageData` and `DecodeError` (re-exported by the root) |
| `internal/vp8l` | Lossless decoder |
| `internal/vp8` | Lossy decoder |
| `internal/riff`, `bitreader`, `huffman`, `transform` | Building blocks |

## License

Apache-2.0. The decoders are ported from
[libwebp](https://chromium.googlesource.com/webm/libwebp) (BSD-3-Clause) and
[image-webp](https://github.com/image-rs/image-webp) (MIT or Apache-2.0); see
[NOTICE](NOTICE). Test images are credited in
[testdata/CREDITS.md](https://github.com/ash1day/moonbit-webp/blob/main/testdata/CREDITS.md).
