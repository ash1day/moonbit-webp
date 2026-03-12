///|
pub fn subsample_size(size : Int, bits : Int) -> Int {
  (size + (1 << bits) - 1) >> bits
}
