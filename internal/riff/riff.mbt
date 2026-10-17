///|
fn read_u32_le(data : Bytes, offset : Int32) -> Int32 {
  data[offset].to_int() |
  (data[offset + 1].to_int() << 8) |
  (data[offset + 2].to_int() << 16) |
  (data[offset + 3].to_int() << 24)
}

///|
fn match_fourcc(data : Bytes, offset : Int32, expected : Bytes) -> Bool {
  data[offset] == expected[0] &&
  data[offset + 1] == expected[1] &&
  data[offset + 2] == expected[2] &&
  data[offset + 3] == expected[3]
}

///|
fn read_chunk_type(data : Bytes, offset : Int32) -> ChunkType {
  if match_fourcc(data, offset, b"VP8 ") {
    ChunkType::VP8
  } else if match_fourcc(data, offset, b"VP8L") {
    ChunkType::VP8L
  } else if match_fourcc(data, offset, b"VP8X") {
    ChunkType::VP8X
  } else if match_fourcc(data, offset, b"ALPH") {
    ChunkType::ALPH
  } else if match_fourcc(data, offset, b"ANIM") {
    ChunkType::ANIM
  } else if match_fourcc(data, offset, b"ANMF") {
    ChunkType::ANMF
  } else if match_fourcc(data, offset, b"ICCP") {
    ChunkType::ICCP
  } else if match_fourcc(data, offset, b"EXIF") {
    ChunkType::EXIF
  } else if match_fourcc(data, offset, b"XMP ") {
    ChunkType::XMP
  } else {
    let cc = Bytes::makei(4, fn(i) { data[offset + i] })
    ChunkType::Unknown(cc)
  }
}

///|
/// Whether a chunk header (8 bytes) fits between `pos` and `end`
fn has_chunk_header(pos : Int32, end : Int32) -> Bool {
  pos <= end && end - pos >= 8
}

///|
pub fn parse(data : Bytes) -> WebPFile? {
  if data.length() < 12 {
    return None
  }
  // Check RIFF magic
  if !match_fourcc(data, 0, b"RIFF") {
    return None
  }
  let file_size = read_u32_le(data, 4)
  // Check WEBP signature
  if !match_fourcc(data, 8, b"WEBP") {
    return None
  }
  let end = if file_size >= 0 && file_size < data.length() - 8 {
    file_size + 8
  } else {
    data.length()
  }
  match parse_chunks(data, 12, end) {
    Some(chunks) => Some({ file_size, chunks, })
    None => None
  }
}

///|
/// Reads the chunk headers from `start` up to `end`. Returns `None` for a
/// chunk size of 2 GiB or more.
pub fn parse_chunks(data : Bytes, start : Int32, end : Int32) -> Array[Chunk]? {
  let chunks : Array[Chunk] = []
  let mut pos = start
  while has_chunk_header(pos, end) {
    let chunk_type = read_chunk_type(data, pos)
    let chunk_size = read_u32_le(data, pos + 4)
    if chunk_size < 0 {
      return None
    }
    let data_offset = pos + 8
    chunks.push({ chunk_type, offset: data_offset, size: chunk_size, })
    // libwebp reads nothing after the image data of a still image
    if chunk_type is (VP8 | VP8L) {
      break
    }
    // A truncated last chunk is kept; its size is checked by the reader
    if chunk_size >= end - data_offset {
      break
    }
    // RIFF chunks are padded to even size
    pos = data_offset + chunk_size + chunk_size % 2
  }
  Some(chunks)
}
