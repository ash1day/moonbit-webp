// The parts of the boolean decoder that do not depend on how the 64-bit
// value is stored; see bool_decoder_u64.mbt and bool_decoder_js.mbt.

///|
fn log2_floor(v : UInt32) -> Int32 {
  let mut n = 0
  let mut x = v
  while x > 1 {
    x = x >> 1
    n += 1
  }
  n
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
