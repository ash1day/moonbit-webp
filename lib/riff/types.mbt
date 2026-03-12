///|
pub(all) enum ChunkType {
  VP8 // Lossy
  VP8L // Lossless
  VP8X // Extended
  ALPH // Alpha
  ANIM // Animation metadata
  ANMF // Animation frame
  ICCP // ICC profile
  EXIF // EXIF metadata
  XMP // XMP metadata
  Unknown(Bytes) // 4-byte FourCC
} derive(Show, Eq)

///|
pub(all) struct Chunk {
  chunk_type : ChunkType
  offset : Int // byte offset of chunk data (after type + size)
  size : Int // chunk data size
} derive(Show, Eq)

///|
pub(all) struct WebPFile {
  file_size : Int // RIFF file size
  chunks : Array[Chunk]
} derive(Show, Eq)
