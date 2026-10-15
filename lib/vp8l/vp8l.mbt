///|
pub fn decode_vp8l(webp_data : Bytes) -> ImageData raise DecodeError {
  let file = match @riff.parse(webp_data) {
    Some(f) => f
    None => raise DecodeError("invalid RIFF/WebP header")
  }
  // Find VP8L chunk
  let mut vp8l_chunk : @riff.Chunk? = None
  for chunk in file.chunks {
    if chunk.chunk_type == @riff.ChunkType::VP8L {
      vp8l_chunk = Some(chunk)
      break
    }
  }
  let chunk = match vp8l_chunk {
    Some(c) => c
    None => raise DecodeError("no VP8L chunk found")
  }
  if chunk.size > webp_data.length() - chunk.offset {
    raise DecodeError("VP8L chunk exceeds file size")
  }
  let chunk_data = Bytes::makei(chunk.size, fn(i) {
    webp_data[chunk.offset + i]
  })
  let br = @bitreader.BitReader::new(chunk_data)
  let signature = read_bits(br, 8)
  if signature != 0x2F {
    raise DecodeError("invalid VP8L signature: \{signature}")
  }
  let width = read_bits(br, 14) + 1
  let height = read_bits(br, 14) + 1
  let _alpha_used = read_bits(br, 1)
  let version = read_bits(br, 3)
  if version != 0 {
    raise DecodeError("invalid VP8L version: \{version}")
  }
  let decoder = LosslessDecoder::new(br, width, height)
  let transformed_width = decoder.read_transforms()
  let transformed_size = transformed_width * height * 4
  let full_size = width * height * 4
  // Allocate max of transformed and full size for in-place expansion
  let buf_size = if transformed_size > full_size {
    transformed_size
  } else {
    full_size
  }
  let buf = FixedArray::make(buf_size, b'\x00')
  decoder.decode_image_stream(transformed_width, height, true, buf)
  // Apply inverse transforms in reverse order
  let mut current_width = transformed_width
  let len = decoder.transform_order.length()
  for ri = 0; ri < len; ri = ri + 1 {
    let i = len - 1 - ri
    let trans_index = decoder.transform_order[i]
    let transform = decoder.transforms[trans_index]
    match transform {
      Some(PredictorTransform(size_bits~, data~)) =>
        @transform.apply_predictor_transform(
          buf, current_width, height, size_bits, data,
        )
      Some(ColorTransform(size_bits~, data~)) =>
        @transform.apply_color_transform(
          buf, current_width, height, size_bits, data,
        )
      Some(SubtractGreen) =>
        @transform.apply_subtract_green(buf, current_width * height)
      Some(ColorIndexingTransform(table_size~, data~)) => {
        current_width = width
        @transform.apply_color_indexing(
          buf, current_width, height, table_size, data,
        )
      }
      None => ()
    }
  }
  let result = Bytes::makei(full_size, fn(i) { buf[i] })
  { width, height, data: result, }
}
