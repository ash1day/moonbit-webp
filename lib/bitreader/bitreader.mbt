///|
pub(all) suberror BitReaderError {
  BitReaderError(String)
}

///|
pub(all) struct BitReader {
  data : Bytes
  mut buffer : Int64
  mut nbits : Int
  mut byte_pos : Int
}

///|
pub fn BitReader::new(data : Bytes) -> BitReader {
  { data, buffer: 0L, nbits: 0, byte_pos: 0 }
}

///|
pub fn BitReader::fill(self : BitReader) -> Unit {
  while self.nbits < 56 && self.byte_pos < self.data.length() {
    self.buffer = self.buffer | (self.data[self.byte_pos].to_int64() << self.nbits)
    self.nbits += 8
    self.byte_pos += 1
  }
}

///|
pub fn BitReader::read_bits(self : BitReader, n : Int) -> Int raise BitReaderError {
  if n == 0 {
    return 0
  }
  self.fill()
  if self.nbits < n {
    raise BitReaderError("not enough bits: need \{n}, have \{self.nbits}")
  }
  let mask = (1L << n) - 1L
  let value = (self.buffer & mask).to_int()
  self.buffer = self.buffer >> n
  self.nbits -= n
  value
}

///|
pub fn BitReader::peek(self : BitReader, n : Int) -> Int {
  ((self.buffer & ((1L << n) - 1L))).to_int()
}

///|
pub fn BitReader::peek_full(self : BitReader) -> Int64 {
  self.buffer
}

///|
pub fn BitReader::consume(self : BitReader, n : Int) -> Unit raise BitReaderError {
  if self.nbits < n {
    raise BitReaderError("not enough bits to consume: need \{n}, have \{self.nbits}")
  }
  self.buffer = self.buffer >> n
  self.nbits -= n
}
