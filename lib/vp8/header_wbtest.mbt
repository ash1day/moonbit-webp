///|
fn read_test_header(name : String) -> FrameHeader raise {
  let webp_data = @fs.read_file_to_bytes("testdata/lossy-extra/\{name}.webp")
  parse_frame_header(find_vp8_chunk(webp_data)).0
}

///|
/// Expected values are from `webpinfo -bitstream_info`.
test "parse frame header of small_31x13" {
  let h = read_test_header("small_31x13")
  assert_eq((h.width, h.height), (31, 13))
  assert_eq(
    (h.use_segment, h.simple_filter, h.filter_level),
    (false, false, 12),
  )
  assert_eq((h.sharpness, h.use_lf_delta), (0, true))
  assert_eq(h.num_partitions, 4)
  assert_eq(h.base_q, 39)
}

///|
test "parse frame header of test-nostrong" {
  let h = read_test_header("test-nostrong")
  assert_eq((h.width, h.height), (128, 128))
  assert_eq((h.use_segment, h.simple_filter, h.filter_level), (true, true, 16))
  assert_eq(h.num_partitions, 1)
  assert_eq(h.base_q, 36)
  assert_eq((h.dquv_dc, h.dquv_ac), (-2, -3))
}
