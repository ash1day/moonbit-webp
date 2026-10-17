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
    Invalid(m) => assert_eq(m, message)
    Unsupported(_) => fail("expected Invalid")
    TooLarge(_) => fail("expected Invalid")
  } noraise {
    _ => fail("expected DecodeError(\{message})")
  }
}

///|
test "animated images raise Unsupported" {
  let data = @fs.read_file_to_bytes("testdata/animated/random_lossy.webp")
  try decode(data) |> ignore catch {
    Unsupported(m) =>
      assert_eq(m, "animated WebP; decode it with AnimationDecoder")
    _ => fail("expected Unsupported")
  } noraise {
    _ => fail("expected Unsupported")
  }
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
/// Builds a WebP file from (FourCC, payload) pairs
fn build_webp(chunks : Array[(String, Bytes)]) -> Bytes {
  let body = Buffer()
  for chunk in chunks {
    let (fourcc, payload) = chunk
    body.write_string_utf8(fourcc) |> ignore
    body.write_int_le(payload.length())
    body.write_bytes(payload)
    if payload.length() % 2 == 1 {
      body.write_byte(b'\x00')
    }
  }
  let riff = Buffer()
  riff.write_string_utf8("RIFF") |> ignore
  riff.write_int_le(body.length() + 4)
  riff.write_string_utf8("WEBP") |> ignore
  riff.write_bytes(body.to_bytes())
  riff.to_bytes()
}

///|
/// The VP8X, ALPH and VP8 payloads of the 16x16 alpha_no_compression image
fn alpha_test_chunks() -> (Bytes, Bytes, Bytes) raise {
  let data = @fs.read_file_to_bytes(
    "testdata/alpha-extra/alpha_no_compression.webp",
  )
  let file = @riff.parse(data).unwrap()
  let payloads = file.chunks.map(fn(chunk) {
    Bytes::makei(chunk.size, fn(i) { data[chunk.offset + i] })
  })
  (payloads[0], payloads[1], payloads[2])
}

///|
/// Rebuilds the 16x16 alpha_no_compression image with another ALPH payload
fn with_alpha_chunk(alpha : Bytes) -> Bytes raise {
  let (vp8x, _, vp8) = alpha_test_chunks()
  build_webp([("VP8X", vp8x), ("ALPH", alpha), ("VP8 ", vp8)])
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
      Invalid(_) => ()
      Unsupported(_) => fail("expected Invalid")
      TooLarge(_) => fail("expected Invalid")
    } noraise {
      _ => fail("expected DecodeError for fill \{fill}")
    }
  }
}

///|
/// An uncompressed ALPH payload that makes every pixel's alpha 0x80
fn constant_alpha() -> Bytes {
  Bytes::makei(1 + 16 * 16, fn(i) { if i == 0 { b'\x00' } else { b'\x80' } })
}

///|
test "the last ALPH chunk before VP8 is used" {
  // expected values are from dwebp -pam on the same chunks
  let (vp8x, alpha, vp8) = alpha_test_chunks()
  let result = decode(
    build_webp([
      ("VP8X", vp8x),
      ("ALPH", alpha),
      ("ALPH", constant_alpha()),
      ("VP8 ", vp8),
    ]),
  )
  assert_eq(md5_hex(result.data), "711f0dd53c0158d83bf5cea28427d7f2")
}

///|
test "ALPH chunks after VP8 are ignored" {
  let (vp8x, alpha, vp8) = alpha_test_chunks()
  let after_only = decode(
    build_webp([("VP8X", vp8x), ("VP8 ", vp8), ("ALPH", constant_alpha())]),
  )
  assert_eq(md5_hex(after_only.data), "877731de5af73ba624d64cd36bf74d61")
  let before_and_after = decode(
    build_webp([
      ("VP8X", vp8x),
      ("ALPH", alpha),
      ("VP8 ", vp8),
      ("ALPH", constant_alpha()),
    ]),
  )
  assert_eq(md5_hex(before_and_after.data), "78641692a66d86607429770638f06c56")
}

///|
test "without VP8X the image chunk must come first" {
  let (_, _, vp8) = alpha_test_chunks()
  check_error(
    build_webp([("ALPH", constant_alpha()), ("VP8 ", vp8)]),
    "ALPH chunk before the image without VP8X",
  )
  check_error(
    build_webp([("ICCP", b"abcd"), ("VP8 ", vp8)]),
    "ICCP chunk before the image without VP8X",
  )
}

///|
fn check_limit_error(
  webp_data : Bytes,
  max_pixels : Int32,
  message : String,
) -> Unit raise {
  try decode(webp_data, max_pixels~) |> ignore catch {
    TooLarge(m) => assert_eq(m, message)
    _ => fail("expected TooLarge")
  } noraise {
    _ => fail("expected DecodeError(\{message})")
  }
}

///|
test "lossy images larger than max_pixels raise TooLarge" {
  let data = @fs.read_file_to_bytes(
    "testdata/alpha-extra/alpha_no_compression.webp",
  )
  check_limit_error(data, 255, "image size 16x16 exceeds 255 pixels")
  let result = decode(data, max_pixels=256)
  assert_eq(md5_hex(result.data), "78641692a66d86607429770638f06c56")
}

///|
test "lossless images larger than max_pixels raise TooLarge" {
  let data = @fs.read_file_to_bytes("testdata/regression/tiny.webp")
  check_limit_error(data, 69, "image size 10x7 exceeds 69 pixels")
  let result = decode(data, max_pixels=70)
  assert_eq(md5_hex(result.data), "43f244c388586865f7913da7eaedabd3")
}

///|
test "a tiny file claiming 16384x16384 pixels is rejected before allocating" {
  // VP8L header only: signature, then width - 1 and height - 1 = 16383
  let data = build_webp([("VP8L", b"\x2f\xff\xff\xff\x0f")])
  check_limit_error(
    data,
    1 << 20,
    "image size 16384x16384 exceeds 1048576 pixels",
  )
}

///|
test "VP8X canvas size is checked before decoding the image" {
  let data = @fs.read_file_to_bytes("testdata/regression/tiny.webp")
  let file = @riff.parse(data).unwrap()
  let vp8x = file.chunks[0]
  let vp8l = file.chunks[2]
  // canvas width 11 instead of 10, and only the VP8L header without pixels
  let canvas = Bytes::makei(vp8x.size, fn(i) {
    if i == 4 {
      b'\x0a'
    } else {
      data[vp8x.offset + i]
    }
  })
  let header = Bytes::makei(5, fn(i) { data[vp8l.offset + i] })
  check_error(
    build_webp([("VP8X", canvas), ("VP8L", header)]),
    "VP8X canvas size 11x7 does not match the image size 10x7",
  )
}

///|
test "chunks beyond the RIFF size are rejected" {
  // byte 4 holds the low byte of the RIFF size: 0x148 becomes 0x10c, which
  // ends the RIFF data inside the ALPH chunk
  check_error(
    patch("alpha-extra/alpha_no_compression", 4, b'\x0c'),
    "ALPH chunk exceeds the RIFF size",
  )
}

///|
test "a RIFF size that ends before the image chunk is rejected" {
  let data = @fs.read_file_to_bytes("testdata/lossy-extra/test.webp")
  // RIFF size 12: only the "WEBP" tag and the VP8 chunk header fit
  let riff_size = [b'\x0c', b'\x00', b'\x00', b'\x00']
  let patched = Bytes::makei(data.length(), fn(i) {
    if i >= 4 && i < 8 {
      riff_size[i - 4]
    } else {
      data[i]
    }
  })
  check_error(patched, "VP8 chunk exceeds the RIFF size")
}

///|
test "a RIFF size larger than the file is rejected" {
  // byte 5 raises the RIFF size from 0x148 to 0x248, beyond the 336-byte file
  check_error(
    patch("alpha-extra/alpha_no_compression", 5, b'\x02'),
    "file is shorter than the RIFF size",
  )
}

///|
/// Returns the file with the size of its first chunk lowered by `delta`
fn shrink_first_chunk(path : String, delta : Int32) -> Bytes raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let size = (data[16].to_int() | (data[17].to_int() << 8)) - delta
  Bytes::makei(data.length(), fn(i) {
    match i {
      16 => size.to_byte()
      17 => (size >> 8).to_byte()
      _ => data[i]
    }
  })
}

///|
test "image bitstreams run to the end of the file like in libwebp" {
  // libwebp reads VP8 and VP8L data up to the end of the input, so a chunk
  // size smaller than the data does not change the image (checked with dwebp)
  for delta in [1, 2, 16] {
    let lossless = decode(
      shrink_first_chunk("lossless-extra/dual_transform", delta),
    )
    assert_eq(md5_hex(lossless.data), "a1c5d391fe310f8ac12110220972dcea")
    let lossy = decode(shrink_first_chunk("lossy-extra/small_31x13", delta))
    assert_eq(md5_hex(lossy.data), "cba741e37793437baee0be7d2497b183")
  }
}

///|
test "a VP8 frame whose last partition has no data is rejected" {
  // byte 66 is in the partition size table of this four-partition image;
  // 0x80 makes the earlier partitions take all the data (dwebp:
  // NOT_ENOUGH_DATA)
  check_error(
    patch("lossy-extra/small_31x13", 66, b'\x80'),
    "no data for the last VP8 partition",
  )
}

///|
test "corrupt token data decodes like libwebp's 64-bit bool decoder" {
  // Corrupting the first token byte drives the bool decoder's value above its
  // range, where libwebp's 64-bit value refilled 7 bytes at a time decides the
  // result. The expected value is from dwebp, with and without SIMD.
  let image = decode(patch("lossy-extra/small_31x13", 74, b'\xff'))
  assert_eq(md5_hex(image.data), "e4553c677897665eefcbf52adc49aa39")
}

///|
test "VP8X is read only from the first chunk" {
  // libwebp's ParseVP8X looks only right after "WEBP"; dwebp rejects this
  let (vp8x, _, vp8) = alpha_test_chunks()
  check_error(
    build_webp([("ICCP", b"abcd"), ("VP8X", vp8x), ("VP8 ", vp8)]),
    "ICCP chunk before the image without VP8X",
  )
}

///|
/// Returns the file with the RIFF size one byte smaller, so that it leaves
/// out the padding byte of an odd-sized last chunk
fn without_padding_in_riff_size(data : Bytes) -> Bytes {
  Bytes::makei(data.length(), fn(i) {
    if i == 4 {
      data[4] - 1
    } else {
      data[i]
    }
  })
}

///|
test "with VP8X the RIFF size must include chunk padding" {
  // libwebp's ParseOptionalChunks counts padded chunk sizes; without VP8X
  // only the payload is checked. Both results are from dwebp.
  let (vp8x, _, vp8) = alpha_test_chunks()
  let odd_vp8 = Bytes::makei(vp8.length() + 1, fn(i) {
    if i < vp8.length() {
      vp8[i]
    } else {
      b'\x00'
    }
  })
  check_error(
    without_padding_in_riff_size(
      build_webp([("VP8X", vp8x), ("VP8 ", odd_vp8)]),
    ),
    "VP8 chunk exceeds the RIFF size",
  )
  let simple = decode(
    without_padding_in_riff_size(build_webp([("VP8 ", odd_vp8)])),
  )
  assert_eq(md5_hex(simple.data), "877731de5af73ba624d64cd36bf74d61")
}

///|
test "a first partition as long as the VP8 chunk raises DecodeError" {
  // libwebp's VP8GetInfo requires the partition to be shorter than the
  // declared chunk size; dwebp rejects this file. The first partition of
  // small_31x13 is 35 bytes long and the VP8 chunk size is at byte 16.
  let data = patch("lossy-extra/small_31x13", 16, b'\x23')
  check_error(
    Bytes::makei(data.length(), fn(i) {
      if i >= 17 && i < 20 {
        b'\x00'
      } else {
        data[i]
      }
    }),
    "VP8 partition length 35 is not shorter than the chunk size 35",
  )
}

///|
test "a VP8L alpha stream shorter than 8 bytes is read as if padded with zeros" {
  // A 2x2 image whose 5-byte ALPH stream needs bits past its end. libwebp's
  // VP8LInitBitReader loads up to 8 bytes and leaves the rest zero, so dwebp
  // decodes it; the MD5 is from dwebp -pam.
  let data : Array[Bytes] = [
    b"\x52\x49\x46\x46\x50\x00\x00\x00\x57\x45\x42\x50\x56\x50\x38\x58", b"\x0a\x00\x00\x00\x10\x00\x00\x00\x01\x00\x00\x01\x00\x00\x41\x4c",
    b"\x50\x48\x06\x00\x00\x00\x01\x98\x80\x09\x88\x88\x56\x50\x38\x20", b"\x24\x00\x00\x00\x90\x01\x00\x9d\x01\x2a\x02\x00\x02\x00\x02\xc0",
    b"\x4c\x25\xa0\x02\x74\x00\xc4\xe6\x26\x00\xfc\x16\x13\xfa\xc7\xf1", b"\xbf\xe6\xbf\xd0\xa0\x6c\xb0\x00",
  ]
  let buf = Buffer()
  for part in data {
    buf.write_bytes(part)
  }
  let result = decode(buf.to_bytes()) catch {
    e => fail("expected the image, got \{e}")
  }
  assert_eq(md5_hex(result.data), "383c9090fc102f86572e1651f614b415")
}
