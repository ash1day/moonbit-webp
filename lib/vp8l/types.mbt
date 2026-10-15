///|
pub(all) suberror DecodeError {
  DecodeError(String)
}

///|
pub(all) struct ImageData {
  width : Int32
  height : Int32
  data : Bytes
}

///|
priv struct ColorCache {
  bits : Int32
  data : FixedArray[Int32] // packed ARGB
}

///|
priv struct HuffmanInfo {
  xsize : Int32
  color_cache : ColorCache?
  image : FixedArray[Int32]
  bits : Int32
  mask : Int32
  huffman_code_groups : Array[FixedArray[@huffman.HuffmanTree]]
}
