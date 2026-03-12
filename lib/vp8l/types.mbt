///|
pub(all) suberror DecodeError {
  DecodeError(String)
}

///|
pub(all) struct ImageData {
  width : Int
  height : Int
  data : Bytes
}

///|
priv struct ColorCache {
  bits : Int
  data : FixedArray[FixedArray[Byte]]
}

///|
priv struct HuffmanInfo {
  xsize : Int
  color_cache : ColorCache?
  image : FixedArray[Int]
  bits : Int
  mask : Int
  huffman_code_groups : Array[FixedArray[@huffman.HuffmanTree]]
}
