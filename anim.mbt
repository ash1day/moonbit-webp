///|
/// A frame of an animated WebP file, read from its ANMF chunk
#warnings("-unused_field")
priv struct AnimFrame {
  x : Int32
  y : Int32
  width : Int32
  height : Int32
  duration : Int32 // milliseconds
  dispose_to_background : Bool // clear the frame's rectangle afterwards
  blend : Bool // alpha-blend onto the canvas instead of replacing it
}

///|
/// The chunks of an animated WebP file, including the ones inside ANMF chunks
#warnings("-unused_value")
fn animation_chunks(webp_data : Bytes) -> Array[@riff.Chunk] raise DecodeError {
  guard @riff.parse(webp_data) is Some(file) else {
    raise Invalid("invalid RIFF/WebP header")
  }
  let end = if file.file_size >= 0 && file.file_size < webp_data.length() - 8 {
    file.file_size + 8
  } else {
    webp_data.length()
  }
  guard @riff.parse_chunks(webp_data, 12, end, frames=true) is Some(chunks) else {
    raise Invalid("chunk size too large")
  }
  chunks
}

///|
/// Reads the ANMF chunks of an animated WebP file, in order
#warnings("-unused_value")
fn parse_frames(
  webp_data : Bytes,
  chunks : Array[@riff.Chunk],
) -> Array[AnimFrame] raise DecodeError {
  let frames = []
  for chunk in chunks {
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
        duration: read_le24(anmf, 12),
        dispose_to_background: (anmf[15].to_int() & 1) != 0,
        blend: (anmf[15].to_int() & 2) == 0,
      })
    }
  }
  frames
}
