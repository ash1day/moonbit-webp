///|
/// libwebp stores dequantized coefficients in int16_t. The largest token,
/// 2114, times a quantizer of 100 is 211400, which wraps to 14792.
test "dequantized coefficients wrap to 16 bits like libwebp" {
  let webp_data = @fs.read_file_to_bytes("testdata/lossy-extra/small_1x1.webp")
  let (hdr, br) = parse_frame_header(find_vp8_chunk(webp_data))
  let dec = Decoder::new(hdr, br)
  let proba = dec.proba
  let enc = BoolEncoder::new()
  let p = proba_index(3, kbands[0], 0)
  enc.write_bool(proba[p], true) // not the end of the block
  enc.write_bool(proba[p + 1], true) // non-zero
  enc.write_bool(proba[p + 2], true) // larger than 1
  enc.write_bool(proba[p + 3], true)
  enc.write_bool(proba[p + 6], true)
  enc.write_bool(proba[p + 8], true) // category bit 1
  enc.write_bool(proba[p + 10], true) // category bit 0: cat6
  for prob in kcat6 {
    enc.write_bool(prob, true) // extra bits: 2047
  }
  enc.write_bool(128, false) // positive
  enc.write_bool(proba[proba_index(3, kbands[1], 2)], false) // end of block
  let out = FixedArray::make(16, 0)
  let nz = dec.get_coeffs(
    BoolDecoder::new(enc.flush()),
    3,
    0,
    100,
    100,
    0,
    out,
    0,
  )
  assert_eq((nz, out[0]), (1, 14792))
}
