///|
/// Boolean entropy decoder (RFC 6386 section 7), ported from libwebp
/// src/utils/bit_reader_utils.c as built for 64-bit targets (BITS = 56).
///
/// This is bool_decoder_u64.mbt for JavaScript, where `UInt64` is a BigInt
/// and slow: the 64-bit value is kept in two 32-bit halves, `hi` and `lo`,
/// with the same wrap-around arithmetic, so it decodes exactly the same.
priv struct BoolDecoder {
  data : Bytes
  mut pos : Int32
  mut hi : UInt32 // bits 32 to 63 of libwebp's value
  mut lo : UInt32 // bits 0 to 31
  mut range : UInt32 // current range minus 1, in [126, 254] for valid data
  mut bits : Int32 // number of valid bits left in the value
  mut eof : Bool
}

///|
fn BoolDecoder::new(data : Bytes) -> BoolDecoder {
  let dec = {
    data,
    pos: 0,
    hi: 0,
    lo: 0,
    range: 255 - 1,
    bits: -8,
    eof: false,
  }
  dec.load_new_bytes()
  dec
}

///|
/// VP8LoadNewBytes: 56 bits at once while at least 8 bytes remain
fn BoolDecoder::load_new_bytes(self : BoolDecoder) -> Unit {
  if self.pos + 8 <= self.data.length() {
    let d = self.data
    let p = self.pos
    // value = bits | (value << 56): only the low byte of the old value stays
    self.hi = (self.lo << 24) |
      (d[p].to_uint() << 16) |
      (d[p + 1].to_uint() << 8) |
      d[p + 2].to_uint()
    self.lo = (d[p + 3].to_uint() << 24) |
      (d[p + 4].to_uint() << 16) |
      (d[p + 5].to_uint() << 8) |
      d[p + 6].to_uint()
    self.pos += 7
    self.bits += 56
  } else {
    self.load_final_bytes()
  }
}

///|
/// value = (value << 8) | byte
fn BoolDecoder::push_byte(self : BoolDecoder, byte : UInt32) -> Unit {
  self.hi = (self.hi << 8) | (self.lo >> 24)
  self.lo = (self.lo << 8) | byte
}

///|
/// VP8LoadFinalBytes
fn BoolDecoder::load_final_bytes(self : BoolDecoder) -> Unit {
  if self.pos < self.data.length() {
    self.bits += 8
    self.push_byte(self.data[self.pos].to_uint())
    self.pos += 1
  } else if !self.eof {
    self.push_byte(0)
    self.bits += 8
    self.eof = true
  } else {
    self.bits = 0
  }
}

///|
/// The low 32 bits of value >> pos, for pos in [0, 63]
fn BoolDecoder::value_at(self : BoolDecoder, pos : Int32) -> UInt32 {
  if pos == 0 {
    self.lo
  } else if pos < 32 {
    (self.lo >> pos) | (self.hi << (32 - pos))
  } else {
    self.hi >> (pos - 32)
  }
}

///|
/// value -= x << pos, wrapping around like a 64-bit unsigned integer
fn BoolDecoder::subtract(self : BoolDecoder, x : UInt32, pos : Int32) -> Unit {
  let (x_hi, x_lo) = if pos == 0 {
    (0U, x)
  } else if pos < 32 {
    (x >> (32 - pos), x << pos)
  } else {
    (x << (pos - 32), 0U)
  }
  let borrow : UInt32 = if self.lo < x_lo { 1 } else { 0 }
  self.lo = self.lo - x_lo
  self.hi = self.hi - x_hi - borrow
}

///|
/// VP8GetBit
fn BoolDecoder::read_bool(self : BoolDecoder, prob : Int32) -> Bool {
  let mut range = self.range
  if self.bits < 0 {
    self.load_new_bytes()
  }
  let pos = self.bits
  let split = (range * prob.reinterpret_as_uint()) >> 8
  // range_t is 32 bits wide
  let value = self.value_at(pos)
  let bit = value > split
  if bit {
    range -= split
    self.subtract(split + 1, pos)
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
  let value = self.value_at(pos)
  let mask = (split - value).reinterpret_as_int() >> 31 // -1 or 0
  self.bits -= 1
  self.range = (self.range + mask.reinterpret_as_uint()) | 1
  self.subtract((split + 1) & mask.reinterpret_as_uint(), pos)
  (v ^ mask) - mask
}
