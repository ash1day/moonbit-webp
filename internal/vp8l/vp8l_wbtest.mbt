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
    Invalid(_) => ()
    Unsupported(_) => fail("expected Invalid")
    TooLarge(_) => fail("expected Invalid")
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
    Invalid(_) => ()
    Unsupported(_) => fail("expected Invalid")
    TooLarge(_) => fail("expected Invalid")
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

///|
/// LSB-first bit writer for building VP8L streams in tests
struct BitWriter {
  bits : Array[Int32]
}

///|
fn BitWriter::put(self : BitWriter, value : Int32, n : Int32) -> Unit {
  for i in 0..<n {
    self.bits.push((value >> i) & 1)
  }
}

///|
fn BitWriter::to_bytes(self : BitWriter) -> Bytes {
  Bytes::makei((self.bits.length() + 7) / 8, fn(i) {
    let mut b = 0
    for k in 0..<8 {
      if 8 * i + k < self.bits.length() {
        b = b | (self.bits[8 * i + k] << k)
      }
    }
    b.to_byte()
  })
}

///|
/// A simple Huffman code with a single symbol
fn BitWriter::single_symbol_code(self : BitWriter, symbol : Int32) -> Unit {
  self.put(1, 1)
  self.put(0, 1)
  if symbol < 2 {
    self.put(0, 1)
    self.put(symbol, 1)
  } else {
    self.put(1, 1)
    self.put(symbol, 8)
  }
}

///|
/// Wraps a VP8L chunk payload in a RIFF container
fn vp8l_file(payload : Bytes) -> Bytes {
  let size = payload.length()
  let le32 = fn(v : Int32) -> Array[Byte] {
    [v.to_byte(), (v >> 8).to_byte(), (v >> 16).to_byte(), (v >> 24).to_byte()]
  }
  let file : Array[Byte] = [b'R', b'I', b'F', b'F']
  file.append(le32(4 + 8 + size + size % 2))
  file.append([b'W', b'E', b'B', b'P', b'V', b'P', b'8', b'L'])
  file.append(le32(size))
  for b in payload {
    file.push(b)
  }
  if size % 2 == 1 {
    file.push(b'\x00')
  }
  Bytes::from_array(file)
}

///|
/// A 1x1 VP8L payload whose entropy image uses only group `groups - 1`, so
/// that the other groups are coded but never used. dwebp decodes it to one
/// transparent black pixel.
fn sparse_groups_payload(groups : Int32) -> Bytes {
  let w = BitWriter::{ bits: [], }
  w.put(0x2f, 8)
  w.put(0, 14)
  w.put(0, 14)
  w.put(0, 1)
  w.put(0, 3)
  w.put(0, 1) // no transform
  w.put(0, 1) // no color cache
  w.put(1, 1) // entropy image
  w.put(0, 3) // huffman bits 2
  // entropy image: one pixel whose red and green hold the group index
  w.put(0, 1)
  let group = groups - 1
  for symbol in [group & 0xff, group >> 8, 0, 0, 0] {
    w.single_symbol_code(symbol)
  }
  for _ in 0..<groups {
    for _ in 0..<5 {
      w.single_symbol_code(0)
    }
  }
  w.to_bytes()
}

///|
test "only the Huffman groups the entropy image uses are kept" {
  let br = @bitreader.BitReader::new(sparse_groups_payload(1024))
  let (width, height) = read_header(br)
  let decoder = LosslessDecoder::new(br, width, height)
  ignore(decoder.read_transforms())
  ignore(decoder.read_color_cache())
  let info = decoder.read_huffman_codes(true, width, height, None)
  assert_eq(info.huffman_code_groups.length(), 1)
}

///|
test "an image with unused Huffman groups decodes like dwebp" {
  let file = vp8l_file(sparse_groups_payload(1024))
  let image = decode_vp8l(file)
  assert_eq(
    (image.width, image.height, image.data),
    (1, 1, b"\x00\x00\x00\x00"),
  )
}

///|
/// A normal (not simple) Huffman code for symbols 0 and 1, both of length 1:
/// the code length code has the single symbol 1 and max_symbol is 2
fn BitWriter::two_symbol_normal_code(self : BitWriter) -> Unit {
  self.put(0, 1) // normal code
  self.put(0, 4) // 4 code length code lengths: for 17, 18, 0 and 1
  for length in [0, 0, 0, 1] {
    self.put(length, 3)
  }
  self.put(1, 1) // max_symbol present
  self.put(0, 3) // 2 bits
  self.put(0, 2) // max_symbol = 2
}

///|
test "codes of unused groups are read without building a table" {
  let w = BitWriter::{ bits: [], }
  w.two_symbol_normal_code()
  w.two_symbol_normal_code()
  let decoder = LosslessDecoder::new(
    @bitreader.BitReader::new(w.to_bytes()),
    1,
    1,
  )
  assert_eq(decoder.read_huffman_code(280).is_single_node(), false)
  assert_eq(decoder.read_huffman_code(280, keep=false).is_single_node(), true)
}

///|
/// Expected pixels are from dwebp. The payloads have a simple green code with
/// two symbols and single-symbol codes for red, blue, alpha and distance.
test "simple codes assign the shorter code to the smaller symbol" {
  // symbols 200 then 10; the one pixel reads code 0
  let image = decode_vp8l(
    vp8l_file(b"\x2f\x00\x00\x00\x00\x38\xb2\x42\x44\x04"),
  )
  assert_eq(image.data, b"\x00\x0a\x00\x00")
}

///|
test "a simple code naming one symbol twice reads no bits" {
  // symbols 7 then 7, nine pixels and no pixel bits
  let image = decode_vp8l(
    vp8l_file(b"\x2f\x08\x00\x00\x00\xf8\xc1\x41\x44\x04"),
  )
  assert_eq(image.width, 9)
  for i in 0..<9 {
    assert_eq(image.data[4 * i + 1], b'\x07')
  }
}

///|
/// A simple code with two 8-bit symbols
fn simple_code_bits(first : Int32, second : Int32) -> Bytes {
  let w = BitWriter::{ bits: [], }
  w.put(1, 1) // simple
  w.put(1, 1) // two symbols
  w.put(1, 1) // 8-bit first symbol
  w.put(first, 8)
  w.put(second, 8)
  w.to_bytes()
}

///|
test "simple code symbols outside the alphabet are ignored like libwebp" {
  // the distance alphabet has 40 symbols; 200 is dropped and 5 remains
  let decoder = LosslessDecoder::new(
    @bitreader.BitReader::new(simple_code_bits(5, 200)),
    1,
    1,
  )
  assert_eq(decoder.read_huffman_code(40).is_single_node(), true)
  // with no symbol inside the alphabet there is no code at all
  let decoder = LosslessDecoder::new(
    @bitreader.BitReader::new(simple_code_bits(100, 200)),
    1,
    1,
  )
  try decoder.read_huffman_code(40) |> ignore catch {
    Invalid(_) => ()
    _ => fail("expected Invalid")
  } noraise {
    _ => fail("expected Invalid")
  }
}

///|
test "a pixel read from the color cache is inserted into the cache" {
  // 3x1 with a 2-entry cache. The opaque black first pixel hashes to slot 0.
  // The second pixel reads slot 1, which was never written: libwebp inserts
  // that transparent black at slot 0, so the third pixel, read from slot 0,
  // is transparent too. Expected pixels are from dwebp -pam.
  let image = decode_vp8l(
    vp8l_file(
      b"\x2f\x02\x00\x00\x00\x06\x21\x41\xc2\xff\xff\x41\x23\xfa\x1f\x0e",
    ),
  )
  assert_eq(image.data, b"\x00\x00\x00\xff\x00\x00\x00\x00\x00\x00\x00\x00")
}
