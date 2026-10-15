///|
pub fn subsample_size(size : Int32, bits : Int32) -> Int32 {
  (size + (1 << bits) - 1) >> bits
}
