///|
/// Decodes the VP8 (lossy) image of a WebP file to RGBA. `alpha`, one value
/// per pixel, replaces the opaque alpha channel when given.
pub fn decode_vp8(
  webp_data : Bytes,
  alpha? : FixedArray[Byte],
) -> @image.ImageData raise @image.DecodeError {
  decode_bitstream(find_vp8_chunk(webp_data), alpha?)
}

///|
/// Decodes a VP8 bitstream: the payload of a VP8 chunk and whatever input
/// follows it, up to where the caller says the bitstream ends. `alpha`, one
/// value per pixel, replaces the opaque alpha channel when given.
pub fn decode_bitstream(
  bitstream : Bytes,
  alpha? : FixedArray[Byte],
) -> @image.ImageData raise @image.DecodeError {
  let (hdr, br) = parse_frame_header(bitstream)
  let dec = Decoder::new(hdr, br)
  dec.decode_frame()
  let rgba = yuv_to_rgba(
    dec.y_plane,
    dec.y_stride,
    dec.u_plane,
    dec.v_plane,
    dec.uv_stride,
    hdr.width,
    hdr.height,
  )
  if alpha is Some(alpha) {
    for i in 0..<(hdr.width * hdr.height) {
      rgba[4 * i + 3] = alpha[i]
    }
  }
  // `rgba` is not used after this point, so it can back the Bytes directly
  {
    width: hdr.width,
    height: hdr.height,
    data: rgba.unsafe_reinterpret_as_bytes(),
  }
}
