///|
/// Boolean entropy decoder (RFC 6386 section 7), ported from libwebp
/// src/utils/bit_reader_utils.c so that `get_signed` behaves exactly like
/// VP8GetSigned. Reading past the end of the data yields zero bits.
priv struct BoolDecoder {
  data : Bytes
  mut pos : Int32
  mut value : Int32
  mut range : Int32 // current range minus 1, in [126, 254]
  mut bits : Int32 // number of valid bits left in `value`
  mut eof : Bool
}

///|
fn BoolDecoder::new(data : Bytes) -> BoolDecoder {
  let dec = { data, pos: 0, value: 0, range: 255 - 1, bits: -8, eof: false, }
  dec.load_new_bytes()
  dec
}

///|
fn BoolDecoder::load_new_bytes(self : BoolDecoder) -> Unit {
  if self.pos < self.data.length() {
    self.bits += 8
    self.value = self.data[self.pos].to_int() | (self.value << 8)
    self.pos += 1
  } else if !self.eof {
    self.value = self.value << 8
    self.bits += 8
    self.eof = true
  } else {
    self.bits = 0
  }
}

///|
fn log2_floor(v : Int32) -> Int32 {
  let mut n = 0
  let mut x = v
  while x > 1 {
    x = x >> 1
    n += 1
  }
  n
}

///|
/// VP8GetBit
fn BoolDecoder::read_bool(self : BoolDecoder, prob : Int32) -> Bool {
  let mut range = self.range
  if self.bits < 0 {
    self.load_new_bytes()
  }
  let pos = self.bits
  let split = (range * prob) >> 8
  let value = self.value >> pos
  let bit = value > split
  if bit {
    range -= split
    self.value -= (split + 1) << pos
  } else {
    range = split + 1
  }
  let shift = 7 ^ log2_floor(range)
  range = range << shift
  self.bits -= shift
  self.range = range - 1
  bit
}

///|
/// VP8GetSigned: returns `v` or `-v` reading one bit at probability 1/2
fn BoolDecoder::get_signed(self : BoolDecoder, v : Int32) -> Int32 {
  if self.bits < 0 {
    self.load_new_bytes()
  }
  let pos = self.bits
  let split = self.range >> 1
  let value = self.value >> pos
  let mask = (split - value) >> 31 // -1 or 0
  self.bits -= 1
  self.range = (self.range + mask) | 1
  self.value -= ((split + 1) & mask) << pos
  (v ^ mask) - mask
}

///|
/// VP8GetValue: `n` bits with probability 128, most significant bit first
fn BoolDecoder::read_literal(self : BoolDecoder, n : Int32) -> Int32 {
  let mut v = 0
  for _ in 0..<n {
    v = (v << 1) | (if self.read_bool(128) { 1 } else { 0 })
  }
  v
}

///|
/// VP8GetSignedValue: magnitude, then the sign bit
fn BoolDecoder::read_signed(self : BoolDecoder, n : Int32) -> Int32 {
  let v = self.read_literal(n)
  if self.read_bool(128) {
    -v
  } else {
    v
  }
}
