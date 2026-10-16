///|
/// Returns the rectangle (x, y, width, height) of each frame of the file
fn frame_rects(path : String) -> Array[(Int32, Int32, Int32, Int32)] raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let file = @riff.parse(data).unwrap()
  parse_frames(data, file).map(f => (f.x, f.y, f.width, f.height))
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
