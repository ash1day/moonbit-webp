///|
// Minimal VP8 lossy: RIFF + WEBP + "VP8 " chunk
// From small_1x1.webp header bytes
test "parse RIFF header - lossy" {
  // "RIFF" + LE32(0x56) + "WEBP" + "VP8 " + LE32(0x3a) + 3 bytes of data
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x56, 0x00, 0x00, 0x00, // file size = 86
     0x57, 0x45, 0x42, 0x50, // WEBP
     0x56, 0x50, 0x38, 0x20, // "VP8 "
     0x3a, 0x00, 0x00, 0x00, // chunk size = 58
     0xf0, 0x02, 0x00, // start of VP8 data (enough for parse)
  ]
  let result = parse(data)
  assert_true(result is Some(_))
  let file = result.unwrap()
  assert_eq(file.file_size, 0x56)
  assert_eq(file.chunks.length(), 1)
  assert_eq(file.chunks[0].chunk_type, ChunkType::VP8)
  assert_eq(file.chunks[0].offset, 20)
  assert_eq(file.chunks[0].size, 0x3a)
}

///|
test "parse RIFF header - lossless" {
  // "RIFF" + LE32(0x20) + "WEBP" + "VP8L" + LE32(0x14) + 5 bytes of data
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x20, 0x00, 0x00, 0x00, // file size = 32
     0x57, 0x45, 0x42, 0x50, // WEBP
     0x56, 0x50, 0x38, 0x4c, // "VP8L"
     0x14, 0x00, 0x00, 0x00, // chunk size = 20
     0x2f, 0x8f, 0x01, 0x4b, 0x10, // start of VP8L data
  ]
  let result = parse(data)
  assert_true(result is Some(_))
  let file = result.unwrap()
  assert_eq(file.chunks.length(), 1)
  assert_eq(file.chunks[0].chunk_type, ChunkType::VP8L)
  assert_eq(file.chunks[0].size, 0x14)
}

///|
test "parse RIFF header - extended with multiple chunks" {
  // VP8X(10 bytes data) + ALPH(4 bytes data) + VP8(4 bytes data)
  // Total RIFF payload: 4(WEBP) + (8+10) + (8+4) + (8+4) = 46
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x2e, 0x00, 0x00, 0x00, // file size = 46
     0x57, 0x45, 0x42, 0x50, // WEBP
    // VP8X chunk
     0x56, 0x50, 0x38, 0x58, // "VP8X"
     0x0a, 0x00, 0x00, 0x00, // chunk size = 10
     0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // VP8X data
    // ALPH chunk
     0x41, 0x4c, 0x50, 0x48, // "ALPH"
     0x04, 0x00, 0x00, 0x00, // chunk size = 4
     0x00, 0x00, 0x00, 0x00, // ALPH data
    // VP8 chunk
     0x56, 0x50, 0x38, 0x20, // "VP8 "
     0x04, 0x00, 0x00, 0x00, // chunk size = 4
     0x00, 0x00, 0x00, 0x00, // VP8 data
  ]
  let result = parse(data)
  assert_true(result is Some(_))
  let file = result.unwrap()
  assert_eq(file.chunks.length(), 3)
  assert_eq(file.chunks[0].chunk_type, ChunkType::VP8X)
  assert_eq(file.chunks[0].size, 10)
  assert_eq(file.chunks[1].chunk_type, ChunkType::ALPH)
  assert_eq(file.chunks[1].size, 4)
  assert_eq(file.chunks[2].chunk_type, ChunkType::VP8)
  assert_eq(file.chunks[2].size, 4)
}

///|
test "parse rejects non-RIFF data" {
  let data : Bytes = [
    0x4e, 0x4f, 0x54, 0x5f, 0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
  ]
  assert_true(parse(data) is None)
}

///|
test "parse rejects non-WEBP RIFF" {
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x04, 0x00, 0x00, 0x00, // size = 4
     0x41, 0x56, 0x49, 0x20, // "AVI "
  ]
  assert_true(parse(data) is None)
}

///|
test "parse rejects negative chunk size" {
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x10, 0x00, 0x00, 0x00, // file size = 16
     0x57, 0x45, 0x42, 0x50, // WEBP
     0x56, 0x50, 0x38, 0x4c, // "VP8L"
     0xf8, 0xff, 0xff, 0xff, // chunk size = 0xFFFFFFF8
  ]
  assert_true(parse(data) is None)
}

///|
test "parse stops at a chunk of size Int32 max" {
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x10, 0x00, 0x00, 0x00, // file size = 16
     0x57, 0x45, 0x42, 0x50, // WEBP
     0x56, 0x50, 0x38, 0x4c, // "VP8L"
     0xff, 0xff, 0xff, 0x7f, // chunk size = 0x7FFFFFFF (padding overflows)
  ]
  let file = parse(data).unwrap()
  assert_eq(file.chunks.length(), 1)
}

///|
test "fourcc names chunk types" {
  assert_eq(ChunkType::VP8.fourcc(), "VP8")
  assert_eq(ChunkType::ALPH.fourcc(), "ALPH")
  assert_eq(ChunkType::Unknown(b"abcd").fourcc(), "abcd")
}

///|
test "parse stops after the image chunk like libwebp" {
  // the bytes after the VP8 chunk would read as a chunk of negative size
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x1c, 0x00, 0x00, 0x00, // file size = 28
     0x57, 0x45, 0x42, 0x50, // WEBP
     0x56, 0x50, 0x38, 0x20, // "VP8 "
     0x04, 0x00, 0x00, 0x00, // chunk size = 4
     0x00, 0x00, 0x00, 0x00, // VP8 data
     0x58, 0x4d, 0x50, 0x20, // "XMP "
     0xf8, 0xff, 0xff, 0xff, // chunk size = 0xFFFFFFF8
  ]
  let file = parse(data).unwrap()
  assert_eq(file.chunks.length(), 1)
  assert_eq(file.chunks[0].chunk_type, ChunkType::VP8)
}

///|
test "the chunk header check does not overflow near Int32 max" {
  // a 2 GiB input can leave the next chunk 2 bytes before its end
  assert_eq(has_chunk_header(0x7ffffffc, 0x7ffffffe), false)
  assert_eq(has_chunk_header(0x7ffffff6, 0x7ffffffe), true)
  assert_eq(has_chunk_header(12, 20), true)
  assert_eq(has_chunk_header(13, 20), false)
}
