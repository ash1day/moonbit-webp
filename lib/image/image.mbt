///|
pub(all) suberror DecodeError {
  DecodeError(String)
}

///|
/// Decoded pixels: `width * height * 4` bytes in RGBA order
pub(all) struct ImageData {
  width : Int32
  height : Int32
  data : Bytes
}
