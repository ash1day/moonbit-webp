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
  // like libwebp's demuxer, which reads nothing after the RIFF data
  if file.file_size < 0 || file.file_size > webp_data.length() - 8 {
    raise Invalid("file is shorter than the RIFF size")
  }
  let end = file.file_size + 8
  guard @riff.parse_chunks(webp_data, 12, end, frames=true) is Some(chunks) else {
    raise Invalid("chunk size too large")
  }
  // every chunk must fit, and the RIFF data must end after a whole chunk
  let mut pos = 12
  for chunk in chunks {
    if chunk.size > end - chunk.offset - chunk.size % 2 {
      raise Invalid("\{chunk.chunk_type.fourcc()} chunk exceeds the RIFF size")
    }
    // the scan continues inside ANMF chunks, after the frame header
    pos = if chunk.chunk_type is ANMF && chunk.size >= 16 {
      chunk.offset + 16
    } else {
      chunk.offset + chunk.size + chunk.size % 2
    }
  }
  if pos != end {
    raise Invalid("\{end - pos} bytes after the last chunk")
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
  let mut i = 0
  while i < chunks.length() {
    let chunk = chunks[i]
    i += 1
    match chunk.chunk_type {
      ANMF => {
        if chunk.size < 16 {
          raise Invalid("ANMF chunk is shorter than 16 bytes: \{chunk.size}")
        }
        if chunk.offset > webp_data.length() - 16 {
          raise Invalid("ANMF chunk exceeds file size")
        }
        // only the frame header; the frame's chunks follow it
        let anmf = Bytes::makei(16, fn(j) { webp_data[chunk.offset + j] })
        let (alpha, image, next) = frame_chunks(chunks, i, frames.length() + 1)
        i = next
        let last = chunks[next - 1]
        if last.offset + last.size + last.size % 2 >
          chunk.offset + chunk.size + chunk.size % 2 {
          raise Invalid(
            "the chunks of frame \{frames.length() + 1} do not fit in its ANMF chunk",
          )
        }
        // libwebp checks the ANMF size against MAX_IMAGE_AREA (2^32)
        let anmf_width = read_le24(anmf, 6) + 1
        let anmf_height = read_le24(anmf, 9) + 1
        if anmf_width.to_int64() * anmf_height.to_int64() >= 1L << 32 {
          raise Invalid(
            "frame \{frames.length() + 1} is too large: \{anmf_width}x\{anmf_height}",
          )
        }
        // like libwebp's SetFrameInfo, the size comes from the bitstream
        let (width, height) = image_size(webp_data, image)
        // offsets are stored divided by 2
        frames.push({
          x: read_le24(anmf, 0) * 2,
          y: read_le24(anmf, 3) * 2,
          width,
          height,
          duration: read_le24(anmf, 12),
          dispose_to_background: (anmf[15].to_int() & 1) != 0,
          blend: (anmf[15].to_int() & 2) == 0,
          alpha,
          image,
        })
      }
      // libwebp's demuxer: every image of an animation is in an ANMF chunk
      ALPH | VP8 | VP8L =>
        raise Invalid(
          "\{chunk.chunk_type.fourcc()} chunk outside the frames of an animation",
        )
      _ => ()
    }
  }
  frames
}

///|
/// The ALPH and image chunks of the frame whose chunks start at `start`, and
/// the index after them. Like libwebp's StoreFrame, takes at most one of each
/// and stops at any other chunk. `frame` (from 1) is for error messages.
fn frame_chunks(
  chunks : Array[@riff.Chunk],
  start : Int32,
  frame : Int32,
) -> (@riff.Chunk?, @riff.Chunk, Int32) raise DecodeError {
  let mut alpha = None
  let mut image = None
  let mut next = start
  while next < chunks.length() {
    match (chunks[next].chunk_type, alpha, image) {
      (ALPH, None, Some(_)) =>
        raise Invalid("ALPH chunk after the image in frame \{frame}")
      (ALPH, None, None) => alpha = Some(chunks[next])
      (VP8L, Some(_), None) =>
        raise Invalid("ALPH chunk before a VP8L chunk in frame \{frame}")
      (VP8 | VP8L, _, None) => image = Some(chunks[next])
      _ => break
    }
    next += 1
  }
  guard image is Some(image) else {
    raise Invalid("animation frame without an image")
  }
  (alpha, image, next)
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
  // ICC, alpha, EXIF, XMP and animation (libwebp's ALL_VALID_FLAGS)
  if (header.flags | 0x3e) != 0x3e {
    raise Invalid("invalid VP8X flags: \{header.flags}")
  }
  let mut anim = None
  for chunk in chunks[1:] {
    match chunk.chunk_type {
      VP8X => raise Invalid("second VP8X chunk")
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
  if frames.is_empty() {
    raise Invalid("animation without frames")
  }
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
  // with padding, shorter than 6 bytes
  if chunk.size < 5 {
    raise Invalid("ANIM chunk is shorter than 6 bytes: \{chunk.size}")
  }
  if chunk.offset > webp_data.length() - 6 {
    raise Invalid("ANIM chunk exceeds file size")
  }
  Bytes::makei(6, fn(i) { webp_data[chunk.offset + i] })
}

///|
/// The width and height in the header of a VP8 or VP8L chunk
fn image_size(
  webp_data : Bytes,
  chunk : @riff.Chunk,
) -> (Int32, Int32) raise DecodeError {
  if chunk.chunk_type is VP8L {
    @vp8l.image_size(payload(webp_data, chunk))
  } else {
    @vp8.frame_size(payload(webp_data, chunk))
  }
}
