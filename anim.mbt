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

///|
/// An animated WebP file: the canvas from the VP8X chunk and the frames
#warnings("-unused_field")
priv struct Animation {
  canvas_width : Int32
  canvas_height : Int32
  loop_count : Int32 // 0 means forever
  background_color : UInt32 // 0xAARRGGBB; libwebp does not draw it
  frames : Array[AnimFrame]
}

///|
/// Reads the structure of an animated WebP file without decoding any frame
#warnings("-unused_value")
fn parse_animation(webp_data : Bytes) -> Animation raise DecodeError {
  let chunks = animation_chunks(webp_data)
  guard chunks is [{ chunk_type: VP8X, .. } as vp8x, ..] else {
    raise Invalid("animated WebP without VP8X")
  }
  let header = parse_vp8x(payload(webp_data, vp8x))
  let mut anim = None
  for chunk in chunks {
    match chunk.chunk_type {
      // libwebp uses the first ANIM chunk and ignores the others
      ANIM if anim is None => anim = Some(read_anim(webp_data, chunk))
      ANMF if anim is None => raise Invalid("ANMF chunk before the ANIM chunk")
      _ => ()
    }
  }
  let (loop_count, background_color) = match anim {
    Some(anim) =>
      (
        anim[4].to_int() | (anim[5].to_int() << 8),
        (read_le24(anim, 0) | (anim[3].to_int() << 24)).reinterpret_as_uint(),
      )
    None => (0, 0xffffffffU)
  }
  let frames = parse_frames(webp_data, chunks)
  // offsets and sizes are at most 25 bits, so the sums cannot overflow
  for i, f in frames {
    if f.x + f.width > header.canvas_width ||
      f.y + f.height > header.canvas_height {
      raise Invalid(
        "frame \{i + 1} (\{f.width}x\{f.height} at \{f.x}, \{f.y}) does not fit in the \{header.canvas_width}x\{header.canvas_height} canvas",
      )
    }
  }
  {
    canvas_width: header.canvas_width,
    canvas_height: header.canvas_height,
    loop_count,
    background_color,
    frames,
  }
}

///|
/// The 6 bytes of an ANIM chunk. Like libwebp, a 5-byte chunk is read with
/// its padding byte.
fn read_anim(webp_data : Bytes, chunk : @riff.Chunk) -> Bytes raise DecodeError {
  if chunk.size + chunk.size % 2 < 6 {
    raise Invalid("ANIM chunk is shorter than 6 bytes: \{chunk.size}")
  }
  if chunk.offset > webp_data.length() - 6 {
    raise Invalid("ANIM chunk exceeds file size")
  }
  Bytes::makei(6, fn(i) { webp_data[chunk.offset + i] })
}
