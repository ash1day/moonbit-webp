///|
/// A frame of an animated WebP file, read from its ANMF chunk
#warnings("-unused_field")
priv struct AnimFrame {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
}

///|
/// Reads the ANMF chunks of an animated WebP file, in order
#warnings("-unused_value")
fn parse_frames(
  webp_data : Bytes,
  file : @riff.WebPFile,
) -> Array[AnimFrame] raise DecodeError {
  let frames = []
  for chunk in file.chunks {
    if chunk.chunk_type is ANMF {
      if chunk.size < 16 {
        raise Invalid("ANMF chunk is shorter than 16 bytes: \{chunk.size}")
      }
      let anmf = payload(webp_data, chunk)
      // offsets are stored divided by 2, sizes minus 1
      frames.push({
        x: read_le24(anmf, 0) * 2,
        y: read_le24(anmf, 3) * 2,
        width: read_le24(anmf, 6) + 1,
        height: read_le24(anmf, 9) + 1,
      })
    }
  }
  frames
}
