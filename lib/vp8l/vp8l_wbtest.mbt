///|
let hex_chars : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e',
  'f',
]

///|
fn bytes_to_hex(data : FixedArray[Byte]) -> String {
  let buf = StringBuilder::new()
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
