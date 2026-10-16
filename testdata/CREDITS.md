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
