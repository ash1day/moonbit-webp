///|
/// Converts a WebP file to PNG, as an example of using the decoder's output.
///
///   webp2png in.webp out.png
///
/// An animation is written as one PNG per frame: out.1.png, out.2.png, ...
/// The PNG is not compressed, to keep this example free of dependencies.
fn main {
  let args = @env.args()
  if args.length() != 3 {
    println("usage: webp2png in.webp out.png")
    return
  }
  let output = args[2]
  try {
    let data = @fs.read_file_to_bytes(args[1])
    let decoder = @webp.AnimationDecoder::new(data)
    if decoder.frame_count() == 1 {
      guard decoder.next_frame() is Some(frame) else { return }
      @fs.write_bytes_to_file(output, encode_png(frame.image))
      return
    }
    let stem = if output.has_suffix(".png") {
      output.view(end_offset=output.length() - 4).to_owned()
    } else {
      output
    }
    let mut n = 0
    while decoder.next_frame() is Some(frame) {
      n += 1
      @fs.write_bytes_to_file("\{stem}.\{n}.png", encode_png(frame.image))
      println("\{stem}.\{n}.png: ends at \{frame.timestamp} ms")
    }
  } catch {
    e => println("webp2png: \{e}")
  }
}

///|
/// An RGBA image as an 8-bit PNG with stored (uncompressed) deflate blocks
fn encode_png(image : @webp.ImageData) -> Bytes {
  let w = image.width
  let h = image.height
  // each row starts with filter type 0
  let raw = Bytes::makei(h * (w * 4 + 1), fn(i) {
    let row = i / (w * 4 + 1)
    let col = i % (w * 4 + 1)
    if col == 0 {
      b'\x00'
    } else {
      image.data[row * w * 4 + col - 1]
    }
  })
  let png = Buffer()
  png.write_bytes(b"\x89PNG\r\n\x1a\n")
  let ihdr = Buffer()
  write_u32_be(ihdr, w)
  write_u32_be(ihdr, h)
  // 8 bits per channel, RGBA, deflate, adaptive filtering, no interlace
  ihdr.write_bytes(b"\x08\x06\x00\x00\x00")
  write_chunk(png, "IHDR", ihdr.to_bytes())
  write_chunk(png, "IDAT", zlib_stored(raw))
  write_chunk(png, "IEND", b"")
  png.to_bytes()
}

///|
fn write_u32_be(buf : Buffer, value : Int32) -> Unit {
  for shift in [24, 16, 8, 0] {
    buf.write_byte((value >> shift).to_byte())
  }
}

///|
fn write_chunk(png : Buffer, kind : String, payload : Bytes) -> Unit {
  write_u32_be(png, payload.length())
  let body = Buffer()
  for c in kind {
    body.write_byte(c.to_int().to_byte())
  }
  body.write_bytes(payload)
  let bytes = body.to_bytes()
  png.write_bytes(bytes)
  write_u32_be(png, crc32(bytes).reinterpret_as_int())
}

///|
/// A zlib stream of stored deflate blocks
fn zlib_stored(data : Bytes) -> Bytes {
  let out = Buffer()
  out.write_bytes(b"\x78\x01")
  let mut pos = 0
  while pos < data.length() || pos == 0 {
    let len = if data.length() - pos < 65535 {
      data.length() - pos
    } else {
      65535
    }
    let last = pos + len == data.length()
    out.write_byte(if last { b'\x01' } else { b'\x00' })
    out.write_byte(len.to_byte())
    out.write_byte((len >> 8).to_byte())
    out.write_byte((len ^ 0xffff).to_byte())
    out.write_byte(((len ^ 0xffff) >> 8).to_byte())
    for i in pos..<(pos + len) {
      out.write_byte(data[i])
    }
    pos += len
    if last {
      break
    }
  }
  // Adler-32 of the uncompressed data
  let mut a = 1
  let mut b = 0
  for byte in data {
    a = (a + byte.to_int()) % 65521
    b = (b + a) % 65521
  }
  write_u32_be(out, (b << 16) | a)
  out.to_bytes()
}

///|
fn crc32(data : Bytes) -> UInt32 {
  let mut crc = 0xffffffffU
  for byte in data {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = if (crc & 1) != 0 { (crc >> 1) ^ 0xedb88320U } else { crc >> 1 }
    }
  }
  crc ^ 0xffffffffU
}
