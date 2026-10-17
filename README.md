# moonbit-webp

A WebP decoder written in pure MoonBit. It decodes lossless (VP8L), lossy
(VP8) and lossy-with-alpha images, and animations, to RGBA. On every test
image it produces exactly the same pixels as libwebp (`dwebp`, and
`WebPAnimDecoder` for animations).

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

### Animations

`decode` raises `Unsupported` for an animated file. `AnimationDecoder` draws
the frames one after another on the canvas, like libwebp's
`WebPAnimDecoder`, and returns a copy of the whole canvas for each frame:

```moonbit
let decoder = @webp.AnimationDecoder::new(webp_bytes)
// decoder.width(), decoder.height(), decoder.frame_count(),
// decoder.loop_count() (0 means forever)
while decoder.next_frame() is Some(frame) {
  // frame.image: the canvas, width * height * 4 bytes of RGBA
  // frame.timestamp: when the frame ends, in milliseconds
  // frame.duration: how long the frame is shown, in milliseconds
}
```

Frames are decoded one at a time, so memory stays at a few canvases however
many frames there are. A still image gives one frame. The background color
of the file is available as `decoder.background_color()`, but, as in
libwebp, frames are drawn on a transparent canvas.

### Untrusted input

`decode` reads the image size from the headers and checks it before it
allocates any pixel buffer. By default it accepts any size the format allows
(16384 x 16384), which lets a file of a few bytes make `decode` allocate
about 1.5 GB. Set `max_pixels` when the input comes from outside:

```moonbit
let image = @webp.decode(webp_bytes, max_pixels=4096 * 4096)
let decoder = @webp.AnimationDecoder::new(webp_bytes, max_pixels=4096 * 4096)
```

For an animation, `max_pixels` bounds the canvas; the decoder keeps two
canvases and one frame, and returns a new canvas for each frame.

`max_pixels` bounds the pixel buffers, not the total memory: `decode` also
copies parts of the input, so limit the input size as well.

Decoding a lossy image needs about 6 bytes of memory per pixel, including the
4-byte RGBA output (146 MB peak for a 24-megapixel image on native).

## What is supported

- Simple and extended (VP8X) WebP files
- Lossless images: all transforms, the color cache and LZ77 references
- Lossy images: all intra prediction modes, both loop filters and the fancy
  chroma upsampling that `dwebp` uses by default
- Alpha for lossy images (the ALPH chunk), uncompressed or compressed, with
  every filter
- Animations (ANIM and ANMF chunks): frame offsets, alpha blending and both
  dispose methods, with the same checks of the file structure as libwebp's
  demuxer

Not supported:

- Color profiles (ICCP) and EXIF/XMP metadata are ignored
- Encoding

## How it is tested

```bash
moon test --target all
```

- Every test image in `testdata/` (about 50 lossless, lossy and alpha images
  from libwebp's test vectors and the image-rs test suite) is decoded and the
  MD5 of the RGBA output is compared with `dwebp -pam`
- Each canvas of the animations in `testdata/` is compared with libwebp's
  `WebPAnimDecoder` (`tools/anim_oracle`), and each malformed structure that
  libwebp's demuxer rejects is checked to be rejected
- The lossy building blocks (transforms, predictors, loop filters,
  upsampling) are compared with values produced by libwebp's C functions
- Every truncation and many single-byte corruptions of several files must
  either decode or raise `DecodeError`; none may crash
- `tools/differential` decodes about 50,000 corrupted and truncated files
  with this library and with libwebp's C code. They agree on all but three,
  all of the same kind: a corrupt or truncated ALPH stream whose last code
  reads past its end, which libwebp's 8-bit alpha path accepts and this
  library rejects. This covers the kinds of damage the tool generates
  (single-byte changes, random changes to lossy token data, truncation);
  files built by hand in other ways have shown other differences, each fixed
  when found. (libwebp's SIMD code can produce other pixels than its C code
  on corrupt lossy data; this library follows the C code.)
- CI runs the tests on all four backends

Decoding the 24-megapixel `testdata/lossy-extra/bryce.webp` takes about
0.9 s on native and 2.2 s on wasm-gc.

## Packages

Only the root package and `image` are public. The decoders live under
`internal/` and cannot be imported from other modules.

| Package | Role |
|---------|------|
| `ash1day/webp` | `decode`, `AnimationDecoder`, VP8X, ALPH and animation handling |
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
