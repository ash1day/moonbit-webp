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

///|
test "AnimationDecoder checks the canvas against max_pixels" {
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  try
    @webp.AnimationDecoder::new(data, max_pixels=45 * 33 - 1) |> ignore
  catch {
    TooLarge(m) => assert_eq(m, "canvas size 45x33 exceeds 1484 pixels")
    _ => fail("expected TooLarge")
  } noraise {
    _ => fail("expected TooLarge")
  }
  assert_eq(
    @webp.AnimationDecoder::new(data, max_pixels=45 * 33).frame_count(),
    3,
  )
  let still = @fs.read_file_to_bytes("testdata/lossy-extra/test.webp")
  try
    @webp.AnimationDecoder::new(still, max_pixels=128 * 128 - 1) |> ignore
  catch {
    TooLarge(_) => ()
    _ => fail("expected TooLarge")
  } noraise {
    _ => fail("expected TooLarge")
  }
}

///|
test "frames returned by next_frame do not change afterwards" {
  let data = @fs.read_file_to_bytes("testdata/animated-extra/blend.webp")
  let decoder = @webp.AnimationDecoder::new(data)
  let images = []
  while decoder.next_frame() is Some(frame) {
    images.push(frame.image.data)
  }
  assert_eq(images.length(), 8)
  assert_eq(md5_of(images[0]), "439ffb319c936c9768a4b07b7eea2c3a")
  assert_eq(md5_of(images[6]), "24afee6af2b86be85322deecc15e4a6d")
  assert_eq(decoder.next_frame() is None, true)
}

///|
test "AnimationDecoder accepts an ANMF chunk larger than its frame" {
  // frame 1's ANMF size (byte 48) changed from 1564 to 1605; libwebp
  // (tools/anim_oracle) decodes this file like the original
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let changed = Bytes::makei(data.length(), fn(i) {
    if i == 48 {
      b'\x45'
    } else {
      data[i]
    }
  })
  let decoder = @webp.AnimationDecoder::new(changed) catch {
    e => fail("expected a decoder, got \{e}")
  }
  assert_eq(decoder.frame_count(), 3)
}

///|
test "AnimationDecoder rejects a canvas whose RGBA does not fit in an array" {
  // a 32768x32768 canvas (VP8X width - 1 and height - 1 at bytes 24 and
  // 27) is within a raised max_pixels, but its 4 GiB of RGBA is not
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let big = Bytes::makei(data.length(), fn(i) {
    match i {
      24 | 27 => b'\xff'
      25 | 28 => b'\x7f'
      26 | 29 => b'\x00'
      _ => data[i]
    }
  })
  try @webp.AnimationDecoder::new(big, max_pixels=1 << 30) |> ignore catch {
    TooLarge(m) =>
      assert_eq(m, "canvas size 32768x32768 is too large for one RGBA buffer")
    e => fail("expected TooLarge, got \{e}")
  } noraise {
    _ => fail("expected TooLarge")
  }
}

///|
test "a still image that fails to decode fails again on the next call" {
  // 1_webp_ll.webp with its VP8L payload cut to 100 bytes and the sizes
  // fixed: the header is fine, the pixel data is not. Like an animation
  // frame, the frame is not skipped after an error.
  let data = @fs.read_file_to_bytes("testdata/lossless/1_webp_ll.webp")
  let cut = Bytes::makei(120, fn(i) {
    match i {
      4 => b'\x70' // RIFF size 112
      5 | 6 | 7 => b'\x00'
      16 => b'\x64' // VP8L size 100
      17 | 18 | 19 => b'\x00'
      _ => data[i]
    }
  })
  let decoder = @webp.AnimationDecoder::new(cut)
  for attempt in 0..<2 {
    try decoder.next_frame() |> ignore catch {
      Invalid(_) => ()
      e => fail("expected Invalid, got \{e}")
    } noraise {
      _ => fail("expected Invalid on attempt \{attempt}")
    }
  }
}

///|
test "a still image in AnimationDecoder follows decode, not the demuxer" {
  // 1_webp_a.webp without the alpha flag in VP8X (byte 20). decode, like
  // dwebp, still applies the ALPH chunk; libwebp's WebPAnimDecoder reads
  // still images through its demuxer, which drops the alpha (MD5
  // 01475fe29f24f96bfbfb02f398e9e558). AnimationDecoder follows decode.
  let data = @fs.read_file_to_bytes("testdata/alpha/1_webp_a.webp")
  let no_flag = Bytes::makei(data.length(), fn(i) {
    if i == 20 {
      (data[i].to_int() & 0xef).to_byte()
    } else {
      data[i]
    }
  })
  assert_eq(
    md5_of(@webp.decode(no_flag).data),
    "650645a89c80efea0a88fe17ed893c73",
  )
  let decoder = @webp.AnimationDecoder::new(no_flag)
  guard decoder.next_frame() is Some(frame) else { fail("expected a frame") }
  assert_eq(md5_of(frame.image.data), "650645a89c80efea0a88fe17ed893c73")
}
