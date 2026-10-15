///|
let hex_chars : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
fn bytes_to_hex(data : FixedArray[Byte]) -> String {
  let buf = StringBuilder()
  for i = 0; i < data.length(); i = i + 1 {
    let b = data[i].to_int()
    buf.write_char(hex_chars[b >> 4])
    buf.write_char(hex_chars[b & 0x0F])
  }
  buf.to_string()
}

///|
test "decode 1_webp_ll.webp" {
  let webp_data = @fs.read_file_to_bytes("testdata/lossless/1_webp_ll.webp")
  let result = decode_vp8l(webp_data)
  assert_eq(result.width, 400)
  assert_eq(result.height, 301)
  assert_eq(
    bytes_to_hex(@crypto.md5(result.data)),
    "416e5f28fb3ea4b557b9b5297f7a2032",
  )
}

///|
test "decode 2_webp_ll.webp" {
  let webp_data = @fs.read_file_to_bytes("testdata/lossless/2_webp_ll.webp")
  let result = decode_vp8l(webp_data)
  assert_eq(result.width, 386)
  assert_eq(result.height, 395)
  assert_eq(
    bytes_to_hex(@crypto.md5(result.data)),
    "3b03350de2c15513083d1ac1129e10ef",
  )
}

///|
test "decode 3_webp_ll.webp" {
  let webp_data = @fs.read_file_to_bytes("testdata/lossless/3_webp_ll.webp")
  let result = decode_vp8l(webp_data)
  assert_eq(result.width, 800)
  assert_eq(result.height, 600)
  assert_eq(
    bytes_to_hex(@crypto.md5(result.data)),
    "49f9329d2d1477360a2f886641ce93b1",
  )
}

///|
test "decode 4_webp_ll.webp" {
  let webp_data = @fs.read_file_to_bytes("testdata/lossless/4_webp_ll.webp")
  let result = decode_vp8l(webp_data)
  assert_eq(result.width, 421)
  assert_eq(result.height, 163)
  assert_eq(
    bytes_to_hex(@crypto.md5(result.data)),
    "9e5d8eadb1b60efac10d00c488ab96e0",
  )
}

///|
test "decode 5_webp_ll.webp" {
  let webp_data = @fs.read_file_to_bytes("testdata/lossless/5_webp_ll.webp")
  let result = decode_vp8l(webp_data)
  assert_eq(result.width, 300)
  assert_eq(result.height, 300)
  assert_eq(
    bytes_to_hex(@crypto.md5(result.data)),
    "8cc6797dc48c89ddc037ce6a51ebe2f8",
  )
}

///|
test "chunk larger than the file raises DecodeError" {
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x11, 0x00, 0x00, 0x00, // file size = 17
     0x57, 0x45, 0x42, 0x50, // WEBP
     0x56, 0x50, 0x38, 0x4c, // "VP8L"
     0xe8, 0x03, 0x00, 0x00, // chunk size = 1000
     0x2f, // only the signature is present
  ]
  try decode_vp8l(data) |> ignore catch {
    DecodeError(_) => ()
  } noraise {
    _ => fail("expected DecodeError")
  }
}

///|
test "chunk size near Int32 max raises DecodeError" {
  let data : Bytes = [
    0x52, 0x49, 0x46, 0x46, // RIFF
     0x11, 0x00, 0x00, 0x00, // file size = 17
     0x57, 0x45, 0x42, 0x50, // WEBP
     0x56, 0x50, 0x38, 0x4c, // "VP8L"
     0xf0, 0xff, 0xff, 0x7f, // chunk size = 0x7FFFFFF0
     0x2f,
  ]
  try decode_vp8l(data) |> ignore catch {
    DecodeError(_) => ()
  } noraise {
    _ => fail("expected DecodeError")
  }
}

///|
/// Expected values are the MD5 of the RGBA pixels written by `dwebp -pam`.
let lossless_vectors : Array[(String, Int32, Int32, String)] = [
  (
    "lossless-extra/bad_palette_index", 128, 128, "2dba96252d2b011d4a351c091e1739a5",
  ),
  (
    "lossless-extra/color_cache_bits_11", 128, 128, "50c39d15a3ec7f4bec1fe39d3e720cb2",
  ),
  ("lossless-extra/dual_transform", 100, 30, "a1c5d391fe310f8ac12110220972dcea"),
  ("lossless-extra/lossless1", 1000, 307, "8cad0211e20ad0f8c3049a03ab535888"),
  ("lossless-extra/lossless2", 1000, 307, "8cad0211e20ad0f8c3049a03ab535888"),
  ("lossless-extra/lossless3", 1000, 307, "8cad0211e20ad0f8c3049a03ab535888"),
  ("lossless-extra/lossless4", 256, 256, "0f1bc3398c60b7c7f39145e0750e2dc9"),
  (
    "lossless-extra/lossless_big_random_alpha", 2048, 2048, "42209ef35823688fbf8f135ff5f35607",
  ),
  (
    "lossless-extra/lossless_color_transform", 512, 512, "365b2322718137d55809146cbb1d984e",
  ),
  (
    "lossless-extra/one_color_no_palette", 100, 100, "4e0a293a5b638f0aba2c4fe2c3418d0e",
  ),
  ("regression/color_index", 30, 30, "645662fafb288f8dbaad2169fc7622ae"),
  (
    "regression/lossless_indexed_1bit_palette", 230, 128, "ca3599a883c01bb1263d115013d47ebd",
  ),
  (
    "regression/lossless_indexed_2bit_palette", 230, 128, "35b3b636d4ee63275e743a717c64f245",
  ),
  (
    "regression/lossless_indexed_4bit_palette", 500, 300, "67ae30effa2203d75575b2d571a27167",
  ),
  ("regression/tiny", 10, 7, "43f244c388586865f7913da7eaedabd3"),
]

///|
test "decode libwebp and regression lossless vectors" {
  for vector in lossless_vectors {
    let (name, width, height, md5) = vector
    let webp_data = @fs.read_file_to_bytes("testdata/\{name}.webp")
    let result = decode_vp8l(webp_data)
    assert_eq((name, result.width, result.height), (name, width, height))
    assert_eq((name, bytes_to_hex(@crypto.md5(result.data))), (name, md5))
  }
}

///|
test "get_copy_distance refills the bit buffer" {
  // prefix code 10 -> extra_bits = 4, offset = 2 << 4 = 32
  // the reader has not buffered anything yet but the bits are in the data
  let br = @bitreader.BitReader::new(b"\x05")
  assert_eq(get_copy_distance(br, 10), 32 + 5 + 1)
}
