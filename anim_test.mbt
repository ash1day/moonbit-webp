///|
fn md5_of(data : Bytes) -> String {
  let digest = @crypto.md5(data)
  let digits = "0123456789abcdef"
  let buf = StringBuilder()
  for b in digest {
    buf.write_char(digits[b.to_int() >> 4].unsafe_to_char())
    buf.write_char(digits[b.to_int() & 15].unsafe_to_char())
  }
  buf.to_string()
}

///|
test "AnimationDecoder returns each frame drawn on the canvas" {
  // expected values are from tools/anim_oracle (libwebp's WebPAnimDecoder)
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let decoder = @webp.AnimationDecoder::new(data)
  let frames = []
  while decoder.next_frame() is Some(frame) {
    frames.push(
      (
        frame.image.width,
        frame.image.height,
        frame.timestamp,
        frame.duration,
        md5_of(frame.image.data),
      ),
    )
  }
  assert_eq(frames, [
    (45, 33, 100, 100, "97093e67ffe41ac3cf737b7f7160fb92"),
    (45, 33, 180, 80, "04c3f92acd9fbfe2b650967ba66c328b"),
    (45, 33, 240, 60, "b37123e19f2e79090c1e5b3aea3c6345"),
  ])
}

///|
test "AnimationDecoder reports the canvas, frame count, loop count and background" {
  // expected values are from tools/anim_oracle
  let info = (path : String) => {
    let decoder = @webp.AnimationDecoder::new(
      @fs.read_file_to_bytes("testdata/\{path}.webp"),
    )
    (
      decoder.width(),
      decoder.height(),
      decoder.frame_count(),
      decoder.loop_count(),
      decoder.background_color(),
    )
  }
  assert_eq(info("animated-extra/offsets"), (45, 33, 3, 3, 0xff102030))
  assert_eq(info("animated-extra/blend"), (64, 48, 8, 0, 0x8000ff00))
}

///|
test "AnimationDecoder returns a still image as one frame" {
  // like libwebp's WebPAnimDecoder (tools/anim_oracle): one frame at time 0,
  // played once, with the pixels dwebp gives
  let data = @fs.read_file_to_bytes("testdata/lossy-extra/test.webp")
  let decoder = @webp.AnimationDecoder::new(data) catch {
    e => fail("expected a decoder, got \{e}")
  }
  assert_eq(
    (
      decoder.width(),
      decoder.height(),
      decoder.frame_count(),
      decoder.loop_count(),
      decoder.background_color(),
    ),
    (128, 128, 1, 1, 0xffffffff),
  )
  let frames = []
  while decoder.next_frame() is Some(frame) {
    frames.push((frame.timestamp, frame.duration, md5_of(frame.image.data)))
  }
  assert_eq(frames, [(0, 0, "50c39d15a3ec7f4bec1fe39d3e720cb2")])
}
