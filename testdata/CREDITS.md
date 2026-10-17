# Test Data Credits

## Sources

### lossy/, lossless/, alpha/, animated/, regression/
From [image-rs/image-webp](https://github.com/image-rs/image-webp) (MIT OR Apache-2.0).
- gallery1: Downloaded from https://developers.google.com/speed/webp/gallery1
- gallery2: Downloaded from https://developers.google.com/speed/webp/gallery2
- animated: Manually created with ImageMagick
- regression: Manually constructed or from bug reports

### lossy-extra/, lossless-extra/, alpha-extra/
From [webmproject/libwebp-test-data](https://github.com/webmproject/libwebp-test-data) (BSD-3-Clause).
- Official WebP test vectors from the libwebp project

### animated-extra/
Made for this repository from `lossy/1.webp` and `alpha-extra/alpha_filter_1.webp`
(decoded with `dwebp` to `src.png` and `alpha.png`).
- offsets: three frames of different sizes and offsets, lossless, lossy and lossy with alpha:

  ```bash
  cwebp -lossless -crop 100 100 40 30 src.png -o f1.webp
  cwebp -q 70 -crop 200 50 21 17 src.png -o f2.webp
  cwebp -q 70 -crop 1 2 15 13 alpha.png -o f3.webp
  webpmux -frame f1.webp +100+0+0+0+b -frame f2.webp +80+12+8+0+b \
    -frame f3.webp +60+30+20+1-b -loop 3 -bgcolor 255,16,32,48 -o offsets.webp
  ```
- blend: eight frames with semi-transparent and fully transparent pixels,
  overlapping so that they go through every blending and dispose case of
  libwebp's WebPAnimDecoder. `make_blend_frames.py` (needs Pillow) draws
  `f1.png` to `f8.png`:

  ```bash
  python3 make_blend_frames.py
  for i in 1 2 4 5 7; do cwebp -lossless -exact f$i.png -o f$i.webp; done
  cwebp -q 80 -exact f3.png -o f3.webp
  cwebp -q 80 -noalpha f6.png -o f6.webp
  cwebp -q 75 -exact f8.png -o f8.webp
  webpmux -frame f1.webp +100+0+0+0+b -frame f2.webp +50+20+10+1+b \
    -frame f3.webp +70+10+8+0+b -frame f4.webp +30+0+0+1-b \
    -frame f5.webp +0+4+4+0+b -frame f6.webp +40+40+30+1+b \
    -frame f7.webp +60+36+20+0+b -frame f8.webp +90+0+0+0+b \
    -loop 0 -bgcolor 128,0,255,0 -o blend.webp
  ```

### lossy-crafted/
Made for this repository from `lossy-extra/test.webp` (decoded with
`dwebp -pam` to `src.pam`), to cover VP8 header values that libwebp's
encoder never writes. `encoder.patch` changes `src/enc/syntax_enc.c` of
libwebp 1.6.0 so that `WEBP_TEST_LF` writes non-zero reference and mode loop
filter deltas and `WEBP_TEST_RELATIVE` writes segment values relative to the
frame's (`absolute_delta = 0`).
- lf_delta: `WEBP_TEST_LF=1 cwebp -q 60 -f 40 src.pam`
- relative_segments: `WEBP_TEST_RELATIVE=1 cwebp -q 60 -f 40 src.pam`
- lf_delta_relative_sharpness5: both variables, `cwebp -q 60 -f 40 -sharpness 5 src.pam`
- sharpness3, sharpness6: unpatched `cwebp -q 60 -f 40 -sharpness 3` (and 6)
