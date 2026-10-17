///|
/// Returns the rectangle (x, y, width, height) of each frame of the file
fn frame_rects(path : String) -> Array[(Int32, Int32, Int32, Int32)] raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  parse_frames(data, animation_chunks(data)).map(f => {
    (f.x, f.y, f.width, f.height)
  })
}

///|
/// Expected rectangles are the ones `webpinfo` prints for each ANMF chunk
test "parse_frames reads the rectangle of each frame" {
  assert_eq(frame_rects("animated-extra/offsets"), [
    (0, 0, 40, 30),
    (12, 8, 21, 17),
    (30, 20, 15, 13),
  ])
  assert_eq(frame_rects("animated/random_lossy"), [
    (0, 0, 99, 87),
    (0, 0, 99, 87),
    (0, 0, 99, 87),
    (0, 0, 99, 87),
  ])
  assert_eq(frame_rects("animated/random_lossless"), [
    (0, 0, 64, 63),
    (0, 0, 64, 63),
    (0, 0, 64, 63),
  ])
}

///|
/// libwebp's demuxer requires the 16-byte frame header (NewFrame)
test "parse_frames rejects an ANMF chunk shorter than 16 bytes" {
  let vp8x = Bytes::makei(10, fn(i) { if i == 0 { b'\x02' } else { b'\x00' } })
  for size = 15; size >= 0; size = size - 1 {
    let data = build_webp([("VP8X", vp8x), ("ANMF", Bytes::make(size, b'\x00'))])
    try parse_frames(data, animation_chunks(data)) |> ignore catch {
      Invalid(m) => assert_eq(m, "ANMF chunk is shorter than 16 bytes: \{size}")
      _ => fail("expected Invalid for \{size} bytes")
    } noraise {
      _ => fail("expected Invalid for \{size} bytes")
    }
  }
}

///|
/// Expected values are the ones `webpinfo` prints, whose "Blend" is the raw
/// bit (1 means do not blend)
test "parse_frames reads the duration, dispose and blend of each frame" {
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let frames = parse_frames(data, animation_chunks(data)).map(f => {
    (f.duration, f.dispose_to_background, f.blend)
  })
  assert_eq(frames, [(100, false, true), (80, false, true), (60, true, false)])
}

///|
test "parse_frames finds the ALPH and image chunks of each frame" {
  // sizes are the ones webpinfo prints, minus the 8-byte chunk header
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let frames = parse_frames(data, animation_chunks(data)).map(f => {
    (f.alpha.map(c => c.size), f.image.chunk_type.fourcc(), f.image.size)
  })
  assert_eq(frames, [
    (None, "VP8L", 1540),
    (None, "VP8", 80),
    (Some(26), "VP8", 40),
  ])
}

///|
/// Returns `data` with byte `pos` replaced
fn with_byte(data : Bytes, pos : Int32, value : Byte) -> Bytes {
  Bytes::makei(data.length(), fn(i) { if i == pos { value } else { data[i] } })
}

///|
fn check_animation_error(data : Bytes, message : String) -> Unit raise {
  try parse_animation(data) |> ignore catch {
    Invalid(m) => assert_eq(m, message)
    _ => fail("expected Invalid")
  } noraise {
    _ => fail("expected Invalid(\{message})")
  }
}

///|
test "a frame outside the canvas raises DecodeError" {
  // libwebp's demuxer rejects both files (tools/anim_oracle prints "error").
  // The third frame of offsets.webp is 15x13 at (30, 20) on a 45x33 canvas;
  // its X offset / 2 is at byte 1736 and its Y offset / 2 at byte 1739.
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  check_animation_error(
    with_byte(data, 1736, b'\x10'),
    "frame 3 (15x13 at 32, 20) does not fit in the 45x33 canvas",
  )
  check_animation_error(
    with_byte(data, 1739, b'\x0e'),
    "frame 3 (15x13 at 30, 28) does not fit in the 45x33 canvas",
  )
}

///|
test "parse_animation reads the loop count and background color" {
  // expected values are the ones tools/anim_oracle prints
  let info = path => {
    let animation = parse_animation(
      @fs.read_file_to_bytes("testdata/\{path}.webp"),
    )
    (animation.loop_count, animation.background_color)
  }
  assert_eq(info("animated-extra/offsets"), (3, 0xff102030))
  assert_eq(info("animated/random_lossy"), (0, 0xffffffff))
}

///|
test "an animation without an ANIM chunk raises DecodeError" {
  // libwebp's demuxer requires ANIM before the first ANMF; dwebp and
  // tools/anim_oracle reject this file. The ANIM chunk of offsets.webp is at
  // byte 30; renaming it makes it an unknown chunk.
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  check_animation_error(
    with_byte(data, 30, b'X'),
    "ANMF chunk before the ANIM chunk",
  )
}

///|
/// The parts of offsets.webp: the VP8X and ANIM payloads, and for each frame
/// the 16-byte ANMF header and the chunks inside the ANMF chunk
fn offsets_parts() -> (Bytes, Bytes, Array[(Bytes, Array[(String, Bytes)])]) raise {
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let top = @riff.parse_chunks(data, 12, data.length()).unwrap()
  let bytes_of = (data : Bytes, chunk : @riff.Chunk) => {
    Bytes::makei(chunk.size, fn(i) { data[chunk.offset + i] })
  }
  let frames = top[2:].map(fn(anmf) {
    let payload = bytes_of(data, anmf)
    let inner = @riff.parse_chunks(payload, 16, payload.length())
      .unwrap()
      .map(c => (fourcc_of(c.chunk_type), bytes_of(payload, c)))
    (Bytes::makei(16, fn(i) { payload[i] }), inner)
  })
  (bytes_of(data, top[0]), bytes_of(data, top[1]), frames)
}

///|
/// The four characters of a chunk type as written in the file
fn fourcc_of(chunk_type : @riff.ChunkType) -> String {
  match chunk_type {
    VP8 => "VP8 "
    XMP => "XMP "
    other => other.fourcc()
  }
}

///|
/// An ANMF chunk with the given frame header and chunks inside
fn anmf(header : Bytes, inner : Array[(String, Bytes)]) -> (String, Bytes) {
  let buf = Buffer()
  buf.write_bytes(header)
  let body = build_webp(inner)
  // build_webp adds the 12-byte RIFF header; keep only the chunks
  buf.write_bytes(Bytes::makei(body.length() - 12, fn(i) { body[12 + i] }))
  ("ANMF", buf.to_bytes())
}

///|
test "an ANIM chunk of 5 bytes reads the loop count from the padding byte" {
  // libwebp reads the padded size, 6 bytes; tools/anim_oracle prints
  // loop 3 for this file because the high byte (padding) is 0
  let (vp8x, anim, frames) = offsets_parts()
  let data = build_webp(
    [("VP8X", vp8x), ("ANIM", Bytes::makei(5, fn(i) { anim[i] }))] +
    frames.map(f => anmf(f.0, f.1)),
  )
  let animation = parse_animation(data)
  assert_eq(animation.loop_count, 3)
}

///|
test "an ANIM chunk shorter than 6 bytes with padding raises DecodeError" {
  // tools/anim_oracle prints "error" for this file
  let (vp8x, anim, frames) = offsets_parts()
  check_animation_error(
    build_webp(
      [("VP8X", vp8x), ("ANIM", Bytes::makei(4, fn(i) { anim[i] }))] +
      frames.map(f => anmf(f.0, f.1)),
    ),
    "ANIM chunk is shorter than 6 bytes: 4",
  )
}

///|
/// offsets.webp rebuilt from its parts, with `extra` chunks at `pos` among
/// the top-level chunks (0 is before VP8X)
fn offsets_with(extra : Array[(String, Bytes)], pos : Int32) -> Bytes raise {
  let (vp8x, anim, frames) = offsets_parts()
  let top = [("VP8X", vp8x), ("ANIM", anim)] + frames.map(f => anmf(f.0, f.1))
  build_webp(top[:pos].to_owned() + extra + top[pos:].to_owned())
}

///|
test "image chunks outside the frames of an animation raise DecodeError" {
  // libwebp's demuxer requires every image of an animation to be in an ANMF
  // chunk; tools/anim_oracle prints "error" for these files
  let (_, _, frames) = offsets_parts()
  let vp8 = frames[1].1[0]
  let alph = frames[2].1[0]
  check_animation_error(
    offsets_with([vp8], 5),
    "VP8 chunk outside the frames of an animation",
  )
  check_animation_error(
    offsets_with([vp8], 2),
    "VP8 chunk outside the frames of an animation",
  )
  check_animation_error(
    offsets_with([alph], 5),
    "ALPH chunk outside the frames of an animation",
  )
}

///|
/// offsets.webp with the chunks inside frame `index` replaced
fn offsets_with_frame(
  index : Int32,
  inner : Array[(String, Bytes)],
) -> Bytes raise {
  let (vp8x, anim, frames) = offsets_parts()
  build_webp(
    [("VP8X", vp8x), ("ANIM", anim)] +
    frames.mapi(fn(i, f) { anmf(f.0, if i == index { inner } else { f.1 }) }),
  )
}

///|
test "a frame with ALPH before VP8L or after its image raises DecodeError" {
  // VP8L carries its own alpha; libwebp's demuxer rejects both files
  // (tools/anim_oracle prints "error")
  let (_, _, frames) = offsets_parts()
  let vp8l = frames[0].1[0]
  let vp8 = frames[1].1[0]
  let alph = frames[2].1[0]
  check_animation_error(
    offsets_with_frame(0, [alph, vp8l]),
    "ALPH chunk before a VP8L chunk in frame 1",
  )
  check_animation_error(
    offsets_with_frame(1, [vp8, alph]),
    "ALPH chunk after the image in frame 2",
  )
}

///|
test "an animation without frames raises DecodeError" {
  // tools/anim_oracle prints "error" for this file
  let (vp8x, anim, _) = offsets_parts()
  check_animation_error(
    build_webp([("VP8X", vp8x), ("ANIM", anim)]),
    "animation without frames",
  )
}

///|
test "a frame without an image raises DecodeError" {
  // tools/anim_oracle prints "error" for both files
  check_animation_error(
    offsets_with_frame(0, []),
    "animation frame without an image",
  )
  check_animation_error(
    offsets_with_frame(2, []),
    "animation frame without an image",
  )
}
