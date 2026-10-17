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
