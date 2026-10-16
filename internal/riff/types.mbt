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
} derive(Eq, Debug)

///|
pub(all) struct Chunk {
  chunk_type : ChunkType
  offset : Int32 // byte offset of chunk data (after type + size)
  size : Int32 // chunk data size
} derive(Eq, Debug)

///|
pub(all) struct WebPFile {
  file_size : Int32 // RIFF file size
  chunks : Array[Chunk]
} derive(Eq, Debug)

///|
/// The four-character code of the chunk type, without trailing spaces
pub fn ChunkType::fourcc(self : ChunkType) -> String {
  match self {
    VP8 => "VP8"
    VP8L => "VP8L"
    VP8X => "VP8X"
    ALPH => "ALPH"
    ANIM => "ANIM"
    ANMF => "ANMF"
    ICCP => "ICCP"
    EXIF => "EXIF"
    XMP => "XMP"
    Unknown(cc) => {
      let buf = StringBuilder()
      for b in cc {
        buf.write_char(b.to_int().unsafe_to_char())
      }
      buf.to_string()
    }
  }
}

///|
#deprecated
pub extend ChunkType with Eq::{equal, not_equal}

///|
#deprecated
pub extend ChunkType with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Chunk with Eq::{equal, not_equal}

///|
#deprecated
pub extend Chunk with @debug.Debug::{to_repr}

///|
#deprecated
pub extend WebPFile with Eq::{equal, not_equal}

///|
#deprecated
pub extend WebPFile with @debug.Debug::{to_repr}
