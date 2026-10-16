///|
let hex_chars : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
fn md5_hex(data : Bytes) -> String {
  let digest = @crypto.md5(data)
  let buf = StringBuilder()
  for i = 0; i < digest.length(); i = i + 1 {
    let b = digest[i].to_int()
    buf.write_char(hex_chars[b >> 4])
    buf.write_char(hex_chars[b & 0x0F])
  }
  buf.to_string()
}

///|
/// Expected values are the MD5 of the RGBA pixels written by `dwebp -pam`.
fn check_file(
  path : String,
  width : Int32,
  height : Int32,
  md5 : String,
) -> Unit raise {
  let webp_data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let result = decode(webp_data)
  assert_eq((path, result.width, result.height), (path, width, height))
  assert_eq((path, md5_hex(result.data)), (path, md5))
}

///|
test "decode alpha_no_compression.webp" {
  check_file(
    "alpha-extra/alpha_no_compression", 16, 16, "78641692a66d86607429770638f06c56",
  )
}

///|
fn check_alpha(
  name : String,
  width : Int32,
  height : Int32,
  md5 : String,
) -> Unit raise {
  check_file("alpha-extra/\{name}", width, height, md5)
}

///|
test "decode uncompressed alpha with each filter" {
  check_alpha(
    "alpha_filter_0_method_0", 128, 128, "431bf0e79ea18c15c5233a8220a86347",
  )
  check_alpha(
    "alpha_filter_1_method_0", 128, 128, "431bf0e79ea18c15c5233a8220a86347",
  )
  check_alpha(
    "alpha_filter_2_method_0", 128, 128, "431bf0e79ea18c15c5233a8220a86347",
  )
  check_alpha(
    "alpha_filter_3_method_0", 128, 128, "431bf0e79ea18c15c5233a8220a86347",
  )
}

///|
test "decode lossless-compressed alpha" {
  for filter in 0..<4 {
    check_alpha(
      "alpha_filter_\{filter}_method_1",
      128,
      128,
      "431bf0e79ea18c15c5233a8220a86347",
    )
  }
  for filter in 1..<4 {
    check_alpha(
      "alpha_filter_\{filter}",
      16,
      16,
      "78641692a66d86607429770638f06c56",
    )
  }
  check_alpha("alpha_color_cache", 588, 97, "a3c93b5a746f2521646c1a3cb0210927")
}

///|
test "decode gallery images with alpha" {
  check_file("alpha/1_webp_a", 400, 301, "650645a89c80efea0a88fe17ed893c73")
  check_file("alpha/2_webp_a", 386, 395, "998aadb0d37865a7a862ddb5923c1ea4")
  check_file("alpha/3_webp_a", 800, 600, "a22d0a97354c3e188c169be4e008eda9")
  check_file("alpha/4_webp_a", 421, 163, "eb9fff116ccd9879051cbbfbbdad549a")
  check_file("alpha/5_webp_a", 300, 300, "c468763bdb31cc89057d87c4ef48f438")
}

///|
test "decode dispatches lossless images to the VP8L decoder" {
  check_file(
    "lossless-extra/dual_transform", 100, 30, "a1c5d391fe310f8ac12110220972dcea",
  )
}

///|
test "decode reads lossless images with VP8X and metadata chunks" {
  check_file("regression/tiny", 10, 7, "43f244c388586865f7913da7eaedabd3")
}

///|
test "decode dispatches simple lossy images to the VP8 decoder" {
  check_file("lossy-extra/test", 128, 128, "50c39d15a3ec7f4bec1fe39d3e720cb2")
}

///|
fn check_error(webp_data : Bytes, message : String) -> Unit raise {
  try decode(webp_data) |> ignore catch {
    DecodeError(m) => assert_eq(m, message)
  } noraise {
    _ => fail("expected DecodeError(\{message})")
  }
}

///|
test "animated images raise DecodeError" {
  check_error(
    @fs.read_file_to_bytes("testdata/animated/random_lossy.webp"),
    "animated WebP is not supported",
  )
}

///|
/// Returns the file with byte `pos` replaced
fn patch(path : String, pos : Int32, value : Byte) -> Bytes raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  Bytes::makei(data.length(), fn(i) { if i == pos { value } else { data[i] } })
}

///|
test "VP8X canvas size must match the image size" {
  // byte 24 holds the low byte of the canvas width minus one (16x16 image)
  check_error(
    patch("alpha-extra/alpha_no_compression", 24, b'\x10'),
    "VP8X canvas size 17x16 does not match the image size 16x16",
  )
  check_error(
    patch("regression/tiny", 24, b'\x0a'),
    "VP8X canvas size 11x7 does not match the image size 10x7",
  )
}

///|
test "VP8X chunk must be 10 bytes" {
  // byte 16 holds the low byte of the VP8X chunk size
  check_error(
    patch("alpha-extra/alpha_no_compression", 16, b'\x08'),
    "invalid VP8X chunk size: 8",
  )
}

///|
/// Rebuilds the 16x16 alpha_no_compression image with another ALPH payload
fn with_alpha_chunk(alpha : Bytes) -> Bytes raise {
  let data = @fs.read_file_to_bytes(
    "testdata/alpha-extra/alpha_no_compression.webp",
  )
  let file = @riff.parse(data).unwrap()
  let out = Buffer()
  fn write_chunk(fourcc : String, payload : Bytes) {
    out.write_string_utf8(fourcc) |> ignore
    out.write_int_le(payload.length())
    out.write_bytes(payload)
    if payload.length() % 2 == 1 {
      out.write_byte(b'\x00')
    }
  }

  for chunk in file.chunks {
    let payload = Bytes::makei(chunk.size, fn(i) { data[chunk.offset + i] })
    match chunk.chunk_type {
      VP8X => write_chunk("VP8X", payload)
      ALPH => write_chunk("ALPH", alpha)
      VP8 => write_chunk("VP8 ", payload)
      _ => ()
    }
  }
  let body = out.to_bytes()
  let riff = Buffer()
  riff.write_string_utf8("RIFF") |> ignore
  riff.write_int_le(body.length() + 4)
  riff.write_string_utf8("WEBP") |> ignore
  riff.write_bytes(body)
  riff.to_bytes()
}

///|
test "uncompressed alpha shorter than the image raises DecodeError" {
  check_error(
    with_alpha_chunk(Bytes::make(1 + 16 * 16 - 1, b'\x00')),
    "ALPH chunk too short for 16x16 pixels",
  )
}

///|
test "uncompressed alpha of exactly width * height bytes decodes" {
  let original = @fs.read_file_to_bytes(
    "testdata/alpha-extra/alpha_no_compression.webp",
  )
  // the ALPH payload starts at byte 38 and has one byte to spare
  let alpha = Bytes::makei(1 + 16 * 16, fn(i) { original[38 + i] })
  let result = decode(with_alpha_chunk(alpha))
  assert_eq(md5_hex(result.data), "78641692a66d86607429770638f06c56")
}

///|
test "ALPH chunk without data raises DecodeError" {
  check_error(with_alpha_chunk(b""), "ALPH chunk has no data")
  check_error(with_alpha_chunk(b"\x01"), "ALPH chunk has no data")
}

///|
test "invalid ALPH header raises DecodeError" {
  // compression 2 and 3, pre-processing 2, reserved bits set
  for header in [b'\x02', b'\x03', b'\x20', b'\x40', b'\x80'] {
    let alpha = Bytes::makei(1 + 16 * 16, fn(i) {
      if i == 0 {
        header
      } else {
        b'\xff'
      }
    })
    check_error(
      with_alpha_chunk(alpha),
      "invalid ALPH header: \{header.to_int()}",
    )
  }
}

///|
test "malformed lossless-compressed alpha raises DecodeError" {
  for fill in [b'\x00', b'\xff', b'\x5a'] {
    let alpha = Bytes::makei(64, fn(i) { if i == 0 { b'\x01' } else { fill } })
    let webp_data = with_alpha_chunk(alpha)
    try decode(webp_data) |> ignore catch {
      DecodeError(_) => ()
    } noraise {
      _ => fail("expected DecodeError for fill \{fill}")
    }
  }
}
