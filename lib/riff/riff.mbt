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
pub fn parse(data : Bytes) -> WebPFile? {
  if data.length() < 12 {
    return None
  }
  // Check RIFF magic
  if not(match_fourcc(data, 0, b"RIFF")) {
    return None
  }
  let file_size = read_u32_le(data, 4)
  // Check WEBP signature
  if not(match_fourcc(data, 8, b"WEBP")) {
    return None
  }
  // Parse chunks starting at offset 12
  let chunks : Array[Chunk] = []
  let mut pos = 12
  let end = if file_size + 8 < data.length() {
    file_size + 8
  } else {
    data.length()
  }
  while pos + 8 <= end {
    let chunk_type = read_chunk_type(data, pos)
    let chunk_size = read_u32_le(data, pos + 4)
    if chunk_size < 0 {
      return None
    }
    let data_offset = pos + 8
    chunks.push({ chunk_type, offset: data_offset, size: chunk_size, })
    // A truncated last chunk is kept; its size is checked by the reader
    if chunk_size >= end - data_offset {
      break
    }
    // RIFF chunks are padded to even size
    pos = data_offset + chunk_size + chunk_size % 2
  }
  Some({ file_size, chunks, })
}
