///|
test "read 3 bits from 0x9C" {
  // 0x9C = 10011100 binary
  // LSB-first: bits[0..3] = 1,0,0 = 4
  let br = BitReader::new(b"\x9C")
  let v = br.read_bits(3)
  assert_eq(v, 4)
}

///|
test "multiple reads crossing byte boundary" {
  // bytes: 0x9C, 0x41, 0xE1
  let br = BitReader::new(b"\x9C\x41\xE1")
  assert_eq(br.read_bits(3), 4) // 100
  assert_eq(br.read_bits(2), 3) // 11
  assert_eq(br.read_bits(6), 12) // 001100 (crosses byte boundary)
  assert_eq(br.read_bits(10), 40) // 0000101000
  assert_eq(br.read_bits(3), 7) // 111
}

///|
test "read past end raises error" {
  let br = BitReader::new(b"\x6A\x01\x02\x03\x04\x05\x06\x07\x08")
  assert_eq(br.read_bits(3), 2) // 010
  assert_eq(br.read_bits(5), 13) // 01101
  assert_eq(br.read_bits(32), 0x04030201)
  assert_eq(br.read_bits(32), 0x08070605)
  // no more bits, should error
  let result = br.read_bits(4) catch { _ => -1 }
  assert_eq(result, -1)
}

///|
test "a stream shorter than 8 bytes reads zeros up to 64 bits" {
  // libwebp's VP8LInitBitReader loads the stream into a zeroed 64-bit window
  let br = BitReader::new(b"\x6A")
  assert_eq(br.read_bits(3), 2) // 010
  assert_eq(br.read_bits(5), 13) // 01101
  assert_eq(br.read_bits(28), 0)
  assert_eq(br.read_bits(28), 0)
  let result = br.read_bits(1) catch { _ => -1 }
  assert_eq(result, -1)
}

///|
test "peek and consume" {
  let br = BitReader::new(b"\x9C")
  br.fill()
  assert_eq(br.peek(3), 4) // peek doesn't consume
  assert_eq(br.peek(3), 4) // still same value
  br.consume(3)
  assert_eq(br.peek(2), 3) // next 2 bits
}
