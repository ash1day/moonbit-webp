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
  alpha : @riff.Chunk? // the ALPH chunk of a lossy frame
  image : @riff.Chunk // the VP8 or VP8L chunk
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
  for i, chunk in chunks {
    if chunk.chunk_type is ANMF {
      if chunk.size < 16 {
        raise Invalid("ANMF chunk is shorter than 16 bytes: \{chunk.size}")
      }
      if chunk.offset > webp_data.length() - 16 {
        raise Invalid("ANMF chunk exceeds file size")
      }
      // only the frame header; the frame's chunks follow it
      let anmf = Bytes::makei(16, fn(j) { webp_data[chunk.offset + j] })
      let (alpha, image) = frame_chunks(chunks, i + 1)
      // offsets are stored divided by 2, sizes minus 1
      frames.push({
        x: read_le24(anmf, 0) * 2,
        y: read_le24(anmf, 3) * 2,
        width: read_le24(anmf, 6) + 1,
        height: read_le24(anmf, 9) + 1,
        duration: read_le24(anmf, 12),
        dispose_to_background: (anmf[15].to_int() & 1) != 0,
        blend: (anmf[15].to_int() & 2) == 0,
        alpha,
        image,
      })
    }
  }
  frames
}

///|
/// The ALPH and image chunks of the frame whose chunks start at `start`. Like
/// libwebp's StoreFrame, takes at most one of each and stops at any other
/// chunk.
fn frame_chunks(
  chunks : Array[@riff.Chunk],
  start : Int32,
) -> (@riff.Chunk?, @riff.Chunk) raise DecodeError {
  let mut alpha = None
  let mut image = None
  for chunk in chunks[start:] {
    match (chunk.chunk_type, alpha, image) {
      (ALPH, None, _) => alpha = Some(chunk)
      (VP8 | VP8L, _, None) => image = Some(chunk)
      _ => break
    }
  }
  guard image is Some(image) else {
    raise Invalid("animation frame without an image")
  }
  (alpha, image)
}
