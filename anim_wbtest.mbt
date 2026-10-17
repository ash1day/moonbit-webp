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

///|
test "undefined VP8X flags in an animation raise DecodeError" {
  // libwebp's demuxer accepts only the ICC, alpha, EXIF, XMP and animation
  // bits; tools/anim_oracle prints "error" for each of these files
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let flags = data[20].to_int()
  for bit in [0x01, 0x40, 0x80] {
    check_animation_error(
      with_byte(data, 20, (flags | bit).to_byte()),
      "invalid VP8X flags: \{flags | bit}",
    )
  }
}

///|
test "a second VP8X chunk in an animation raises DecodeError" {
  // tools/anim_oracle prints "error" for this file
  let (vp8x, _, _) = offsets_parts()
  check_animation_error(offsets_with([("VP8X", vp8x)], 5), "second VP8X chunk")
}

///|
/// `data` with `extra` appended inside the RIFF data, and the RIFF size
/// changed by `riff_delta` beyond that
fn with_riff_tail(data : Bytes, extra : Bytes, riff_delta : Int32) -> Bytes {
  let buf = Buffer()
  buf.write_bytes(data)
  buf.write_bytes(extra)
  let out = buf.to_bytes()
  let size = data.length() - 8 + extra.length() + riff_delta
  Bytes::makei(out.length(), fn(i) {
    if i >= 4 && i < 8 {
      (size >> (8 * (i - 4))).to_byte()
    } else {
      out[i]
    }
  })
}

///|
test "the RIFF data of an animation must end at a chunk boundary" {
  // libwebp's demuxer needs a whole chunk header after each chunk until the
  // end of the RIFF data; tools/anim_oracle prints "error" for the first two
  // files and decodes the last two
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  check_animation_error(
    with_riff_tail(data, b"abc", 0),
    "3 bytes after the last chunk",
  )
  check_animation_error(
    with_riff_tail(data, b"", 2),
    "file is shorter than the RIFF size",
  )
  // bytes after the RIFF data are ignored, and so are unknown chunks
  assert_eq(
    parse_animation(with_riff_tail(data, b"\x00\x00", -2)).frames.length(),
    3,
  )
  assert_eq(
    parse_animation(with_riff_tail(data, b"JUNK\x03\x00\x00\x00xyz\x00", 0)).frames.length(),
    3,
  )
}

///|
test "the chunks of a frame must fit in its ANMF chunk" {
  // The ANMF chunk of frame 2 holds 104 bytes; its size is at byte 1620.
  // libwebp checks the frame's chunks against the padded ANMF size and
  // otherwise ignores it: tools/anim_oracle prints "error" for 102 and
  // decodes 103 and 106.
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  check_animation_error(
    with_byte(data, 1620, b'\x66'),
    "the chunks of frame 2 do not fit in its ANMF chunk",
  )
  assert_eq(parse_animation(with_byte(data, 1620, b'\x67')).frames.length(), 3)
  assert_eq(parse_animation(with_byte(data, 1620, b'\x6a')).frames.length(), 3)
}

///|
test "the size of a frame comes from its bitstream, not its ANMF header" {
  // libwebp's SetFrameInfo replaces the ANMF size with the bitstream's.
  // Frame 3 is 15x13 at (30, 20); its ANMF width - 1 is at byte 1742.
  // tools/anim_oracle decodes both files like the original.
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  for width in [b'\x28', b'\x04'] {
    let frames = parse_animation(with_byte(data, 1742, width)).frames catch {
        e => fail("expected the frames, got \{e}")
      }
    assert_eq((frames[2].width, frames[2].height), (15, 13))
  }
}

///|
/// `data` with the 24-bit value at `pos` replaced
fn with_le24(data : Bytes, pos : Int32, value : Int32) -> Bytes {
  Bytes::makei(data.length(), fn(i) {
    if i >= pos && i < pos + 3 {
      (value >> (8 * (i - pos))).to_byte()
    } else {
      data[i]
    }
  })
}

///|
test "an ANMF header with an area of 2^32 pixels or more raises DecodeError" {
  // libwebp checks the ANMF size before replacing it with the bitstream's.
  // Frame 3's ANMF width - 1 and height - 1 are at bytes 1742 and 1745;
  // tools/anim_oracle rejects 65536x65536 and decodes 65536x65535.
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let wide = with_le24(data, 1742, 0xffff)
  check_animation_error(
    with_le24(wide, 1745, 0xffff),
    "frame 3 is too large: 65536x65536",
  )
  assert_eq(parse_animation(with_le24(wide, 1745, 0xfffe)).frames.length(), 3)
}

///|
test "a canvas of 2^32 pixels or more raises DecodeError" {
  // The VP8X canvas width - 1 and height - 1 are at bytes 24 and 27;
  // tools/anim_oracle rejects a 65536x65536 canvas
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  check_animation_error(
    with_le24(with_le24(data, 24, 0xffff), 27, 0xffff),
    "canvas is too large: 65536x65536",
  )
}

///|
test "extra ANIM chunks and unknown chunks in frames are ignored" {
  // tools/anim_oracle decodes all three files like the original
  let (_, anim, frames) = offsets_parts()
  let other_anim = Bytes::makei(6, fn(i) {
    if i == 4 {
      b'\x07'
    } else {
      anim[i]
    }
  })
  let second = parse_animation(offsets_with([("ANIM", other_anim)], 2))
  assert_eq((second.loop_count, second.frames.length()), (3, 3))
  let after = parse_animation(offsets_with([("ANIM", other_anim)], 5))
  assert_eq((after.loop_count, after.frames.length()), (3, 3))
  let junk = parse_animation(
    offsets_with_frame(0, frames[0].1 + [("JUNK", b"ab")]),
  )
  assert_eq(junk.frames.length(), 3)
}

///|
/// Checks each frame decoded on its own against the MD5 of the RGBA pixels
/// that dwebp -pam writes for the frame extracted with webpmux -get frame
fn check_frames(
  path : String,
  expected : Array[(Int32, Int32, String)],
) -> Unit raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let animation = parse_animation(data)
  let decoded = animation.frames.map(f => {
    let image = decode_frame(data, f)
    (image.width, image.height, md5_hex(image.data))
  })
  assert_eq((path, decoded), (path, expected))
}

///|
test "each frame decodes like the frame extracted with webpmux" {
  check_frames("animated-extra/offsets", [
    (40, 30, "26269e3c54eb6c364ee35ee983db903f"),
    (21, 17, "46de9d606be008f5c264cebfa3b51705"),
    (15, 13, "f0b5534ed60d610d9c2ce4b069fc635a"),
  ])
  check_frames("animated/random_lossy", [
    (99, 87, "e79794cc54b79b067ff8e76a259b67a8"),
    (99, 87, "47d539f1e4dc679ed8d7f03fabbd326a"),
    (99, 87, "ada5d26e8ce7d5f50d59648e54306bb7"),
    (99, 87, "c5b92ab9ae350cf9199a4a36078d2c43"),
  ])
  check_frames("animated/random_lossless", [
    (64, 63, "dca76dfb37bf0a05142d87ec0f32acce"),
    (64, 63, "ed10889d93d7972db40cf74220faaf65"),
    (64, 63, "4d23e9b3c872eb167add98919104c423"),
  ])
}

///|
/// Checks the canvas after each frame against tools/anim_oracle: the time at
/// which the frame ends and the MD5 of the RGBA canvas
fn check_canvases(
  path : String,
  expected : Array[(Int32, String)],
) -> Unit raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let compositor = Compositor::new(parse_animation(data))
  let canvases = []
  while compositor.draw_next(data) is Some(timestamp) {
    canvases.push(
      (
        timestamp,
        md5_hex(
          Bytes::makei(compositor.canvas.length(), fn(i) {
            compositor.canvas[i]
          }),
        ),
      ),
    )
  }
  assert_eq((path, canvases), (path, expected))
}

///|
test "frames are drawn on the canvas like libwebp's WebPAnimDecoder" {
  check_canvases("animated-extra/offsets", [
    (100, "97093e67ffe41ac3cf737b7f7160fb92"),
    (180, "04c3f92acd9fbfe2b650967ba66c328b"),
    (240, "b37123e19f2e79090c1e5b3aea3c6345"),
  ])
  check_canvases("animated/random_lossy", [
    (150, "e79794cc54b79b067ff8e76a259b67a8"),
    (300, "47d539f1e4dc679ed8d7f03fabbd326a"),
    (450, "ada5d26e8ce7d5f50d59648e54306bb7"),
    (600, "c5b92ab9ae350cf9199a4a36078d2c43"),
  ])
  check_canvases("animated/random_lossless", [
    (100, "dca76dfb37bf0a05142d87ec0f32acce"),
    (200, "ed10889d93d7972db40cf74220faaf65"),
    (300, "4d23e9b3c872eb167add98919104c423"),
  ])
}

///|
test "semi-transparent frames blend and dispose like WebPAnimDecoder" {
  // blend.webp goes through key frames after a disposed full frame, blending
  // over a kept frame, blending around a disposed frame, and frames without
  // alpha
  check_canvases("animated-extra/blend", [
    (100, "439ffb319c936c9768a4b07b7eea2c3a"),
    (150, "064f848a7537bea10f8c790e006885af"),
    (220, "e9eec226f69f028545702a9d41d8dab9"),
    (250, "46e71583aa1057196f4865c11b0d6296"),
    (250, "9a957974da1333baf3f32a932d372624"),
    (290, "8d315035c5969b5d68126ebf629975e6"),
    (350, "24afee6af2b86be85322deecc15e4a6d"),
    (440, "3088772901be2c80cee96b6b8c077017"),
  ])
}

///|
test "the size of an ANMF chunk does not decide where the next chunk is" {
  // libwebp's demuxer reads the chunks after the frame header in sequence,
  // so a larger ANMF size that still holds the frame's chunks is accepted.
  // Frame 1's ANMF size is at byte 48 (1564 = 0x061c); 0x0645 is 1605.
  // tools/anim_oracle decodes this file like the original.
  let data = @fs.read_file_to_bytes("testdata/animated-extra/offsets.webp")
  let animation = parse_animation(with_byte(data, 48, b'\x45')) catch {
    e => fail("expected the animation, got \{e}")
  }
  assert_eq(animation.frames.length(), 3)
}
