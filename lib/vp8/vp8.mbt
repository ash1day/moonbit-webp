///|
/// Decodes the VP8 (lossy) image of a WebP file to RGBA
pub fn decode_vp8(webp_data : Bytes) -> @vp8l.ImageData raise @vp8l.DecodeError {
  let (hdr, br) = parse_frame_header(find_vp8_chunk(webp_data))
  let dec = Decoder::new(hdr, br)
  dec.decode_frame()
  let data = yuv_to_rgba(
    dec.y_plane,
    dec.y_stride,
    dec.u_plane,
    dec.v_plane,
    dec.uv_stride,
    hdr.width,
    hdr.height,
  )
  { width: hdr.width, height: hdr.height, data, }
}
