# anim_frames

Prints what libwebp's `WebPAnimDecoder` makes of an animated WebP file: the
canvas size, loop count, background color and, for each frame, the timestamp
and the MD5 of the RGBA canvas. The animation tests take their expected
values from it.

libwebp's `anim_dump` is not used because it clears the color of fully
transparent pixels before writing them.

Build it against a libwebp checkout without SIMD (see
`tools/differential/run.py`), from the libwebp directory:

```bash
make -f makefile.unix src/demux/libwebpdemux.a src/libwebp.a \
  sharpyuv/libsharpyuv.a EXTRA_FLAGS=-DHAVE_CONFIG_H
cc -O2 -Isrc path/to/anim_frames.c src/demux/libwebpdemux.a src/libwebp.a \
  sharpyuv/libsharpyuv.a -lpthread -o anim_frames
./anim_frames file.webp
```
