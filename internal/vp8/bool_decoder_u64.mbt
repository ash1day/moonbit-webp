///|
/// Boolean entropy decoder (RFC 6386 section 7), ported from libwebp
/// src/utils/bit_reader_utils.c as built for 64-bit targets (BITS = 56). The
/// value is kept in 64 bits and refilled 7 bytes at a time like libwebp, so
/// that corrupt data, where the value outgrows the range, decodes the same.
/// Reading past the end of the data yields zero bits.
///
/// This file is for targets with native 64-bit integers; on JavaScript,
/// where `UInt64` is a BigInt, bool_decoder_js.mbt keeps the value in two
/// 32-bit halves instead.
priv struct BoolDecoder {
  data : Bytes
  mut pos : Int32
  mut value : UInt64
  mut range : UInt32 // current range minus 1, in [126, 254] for valid data
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
/// VP8LoadNewBytes: 56 bits at once while at least 8 bytes remain
fn BoolDecoder::load_new_bytes(self : BoolDecoder) -> Unit {
  if self.pos + 8 <= self.data.length() {
    let mut bits : UInt64 = 0
    for i in 0..<7 {
      bits = (bits << 8) | self.data[self.pos + i].to_uint64()
    }
    self.pos += 7
    self.value = bits | (self.value << 56)
    self.bits += 56
  } else {
    self.load_final_bytes()
  }
}

///|
/// VP8LoadFinalBytes
fn BoolDecoder::load_final_bytes(self : BoolDecoder) -> Unit {
  if self.pos < self.data.length() {
    self.bits += 8
    self.value = self.data[self.pos].to_uint64() | (self.value << 8)
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
/// VP8GetBit
fn BoolDecoder::read_bool(self : BoolDecoder, prob : Int32) -> Bool {
  let mut range = self.range
  if self.bits < 0 {
    self.load_new_bytes()
  }
  let pos = self.bits
  let split = (range * prob.reinterpret_as_uint()) >> 8
  // range_t is 32 bits wide
  let value = (self.value >> pos).to_uint()
  let bit = value > split
  if bit {
    range -= split
    self.value -= (split + 1).to_uint64() << pos
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
  let value = (self.value >> pos).to_uint()
  let mask = (split - value).reinterpret_as_int() >> 31 // -1 or 0
  self.bits -= 1
  self.range = (self.range + mask.reinterpret_as_uint()) | 1
  self.value -= ((split + 1) & mask.reinterpret_as_uint()).to_uint64() << pos
  (v ^ mask) - mask
}
