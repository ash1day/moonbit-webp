///|
/// Boolean encoder from RFC 6386 section 7.3, used to produce test input.
priv struct BoolEncoder {
  out : Array[Int32]
  mut range : Int32
  mut bottom : UInt32
  mut bit_count : Int32
}

///|
fn BoolEncoder::new() -> BoolEncoder {
  { out: [], range: 255, bottom: 0, bit_count: 24, }
}

///|
fn BoolEncoder::add_one_to_output(self : BoolEncoder) -> Unit {
  let mut i = self.out.length() - 1
  while i >= 0 && self.out[i] == 255 {
    self.out[i] = 0
    i -= 1
  }
  self.out[i] += 1
}

///|
fn BoolEncoder::write_bool(
  self : BoolEncoder,
  prob : Int32,
  bit : Bool,
) -> Unit {
  let split = 1 + (((self.range - 1) * prob) >> 8)
  if bit {
    self.bottom += split.reinterpret_as_uint()
    self.range -= split
  } else {
    self.range = split
  }
  while self.range < 128 {
    self.range = self.range << 1
    if (self.bottom & (1U << 31)) != 0 {
      self.add_one_to_output()
    }
    self.bottom = self.bottom << 1
    self.bit_count -= 1
    if self.bit_count == 0 {
      self.out.push((self.bottom >> 24).reinterpret_as_int())
      self.bottom = self.bottom & 0xFFFFFF
      self.bit_count = 8
    }
  }
}

///|
fn BoolEncoder::flush(self : BoolEncoder) -> Bytes {
  for _ in 0..<32 {
    self.write_bool(128, false)
  }
  Bytes::makei(self.out.length(), fn(i) { self.out[i].to_byte() })
}

///|
test "bool decoder reads back what the RFC encoder wrote" {
  let probs = [128, 1, 255, 37, 200, 90, 128, 3, 250, 128]
  let bits = [true, false, true, true, false, false, true, false, true, true]
  let enc = BoolEncoder::new()
  for _ in 0..<20 {
    for i in 0..<bits.length() {
      enc.write_bool(probs[i], bits[i])
    }
  }
  let dec = BoolDecoder::new(enc.flush())
  for _ in 0..<20 {
    for i in 0..<bits.length() {
      assert_eq(dec.read_bool(probs[i]), bits[i])
    }
  }
}

///|
fn BoolEncoder::write_literal(
  self : BoolEncoder,
  value : Int32,
  n : Int32,
) -> Unit {
  for i = n - 1; i >= 0; i = i - 1 {
    self.write_bool(128, ((value >> i) & 1) == 1)
  }
}

///|
test "read_literal reads MSB first and read_signed reads the sign last" {
  let enc = BoolEncoder::new()
  enc.write_literal(0x2A, 7)
  enc.write_literal(5, 4)
  enc.write_bool(128, true) // sign: negative
  let dec = BoolDecoder::new(enc.flush())
  assert_eq(dec.read_literal(7), 0x2A)
  assert_eq(dec.read_signed(4), -5)
}
