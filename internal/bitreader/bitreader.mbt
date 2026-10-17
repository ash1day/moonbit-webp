///|
pub(all) suberror BitReaderError {
  BitReaderError(String)
}

///|
pub(all) struct BitReader {
  data : Bytes
  mut buffer : Int64
  mut nbits : Int32
  mut byte_pos : Int32
}

///|
/// Like libwebp's VP8LInitBitReader, which loads up to 8 bytes into a zeroed
/// 64-bit window, a stream shorter than 8 bytes reads as if padded with zeros
pub fn BitReader::new(data : Bytes) -> BitReader {
  let data = if data.length() < 8 {
    Bytes::makei(8, fn(i) { if i < data.length() { data[i] } else { b'\x00' } })
  } else {
    data
  }
  { data, buffer: 0L, nbits: 0, byte_pos: 0, }
}

///|
pub fn BitReader::fill(self : BitReader) -> Unit {
  while self.nbits < 56 && self.byte_pos < self.data.length() {
    self.buffer = self.buffer |
      (self.data[self.byte_pos].to_int64() << self.nbits)
    self.nbits += 8
    self.byte_pos += 1
  }
}

///|
pub fn BitReader::read_bits(
  self : BitReader,
  n : Int32,
) -> Int32 raise BitReaderError {
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
pub fn BitReader::peek(self : BitReader, n : Int32) -> Int32 {
  (self.buffer & ((1L << n) - 1L)).to_int()
}

///|
pub fn BitReader::peek_full(self : BitReader) -> Int64 {
  self.buffer
}

///|
pub fn BitReader::consume(
  self : BitReader,
  n : Int32,
) -> Unit raise BitReaderError {
  if self.nbits < n {
    raise BitReaderError(
      "not enough bits to consume: need \{n}, have \{self.nbits}",
    )
  }
  self.buffer = self.buffer >> n
  self.nbits -= n
}
