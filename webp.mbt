///|
pub using @image {type DecodeError, type ImageData}

///|
/// VP8X flag bits (libwebp src/webp/mux_types.h)
const ANIMATION_FLAG = 0x02

///|
/// Decodes a WebP file to RGBA
pub fn decode(webp_data : Bytes) -> ImageData raise DecodeError {
  let file = match @riff.parse(webp_data) {
    Some(f) => f
    None => raise DecodeError("invalid RIFF/WebP header")
  }
  let vp8x = match find_chunk(webp_data, file, VP8X) {
    Some(chunk) => Some(parse_vp8x(chunk))
    None => None
  }
  if vp8x is None {
    check_simple_format(file)
  }
  if vp8x is Some(header) && (header.flags & ANIMATION_FLAG) != 0 {
    raise DecodeError("animated WebP is not supported")
  }
  let image = if find_chunk(webp_data, file, VP8L) is Some(_) {
    @vp8l.decode_vp8l(webp_data)
  } else {
    decode_lossy(webp_data, file)
  }
  if vp8x is Some({ canvas_width, canvas_height, .. }) &&
    (canvas_width != image.width || canvas_height != image.height) {
    raise DecodeError(
      "VP8X canvas size \{canvas_width}x\{canvas_height} does not match the image size \{image.width}x\{image.height}",
    )
  }
  image
}

///|
/// Decodes the VP8 image and applies the ALPH chunk if there is one
fn decode_lossy(
  webp_data : Bytes,
  file : @riff.WebPFile,
) -> ImageData raise DecodeError {
  let image = @vp8.decode_vp8(webp_data)
  match find_alpha_chunk(webp_data, file) {
    Some(chunk) => {
      let alpha = decode_alpha(chunk, image.width, image.height)
      let data = Bytes::makei(image.data.length(), fn(i) {
        if (i & 3) == 3 {
          alpha[i >> 2]
        } else {
          image.data[i]
        }
      })
      { width: image.width, height: image.height, data, }
    }
    None => image
  }
}

///|
/// Without VP8X, libwebp requires the image chunk to come first
fn check_simple_format(file : @riff.WebPFile) -> Unit raise DecodeError {
  match file.chunks {
    [] | [{ chunk_type: VP8 | VP8L, .. }, ..] => ()
    [{ chunk_type, .. }, ..] =>
      raise DecodeError("\{chunk_type} chunk before the image without VP8X")
  }
}

///|
priv struct Vp8xHeader {
  flags : Int32
  canvas_width : Int32
  canvas_height : Int32
}

///|
fn parse_vp8x(chunk : Bytes) -> Vp8xHeader raise DecodeError {
  if chunk.length() != 10 {
    raise DecodeError("invalid VP8X chunk size: \{chunk.length()}")
  }
  {
    flags: chunk[0].to_int(),
    canvas_width: read_le24(chunk, 4) + 1,
    canvas_height: read_le24(chunk, 7) + 1,
  }
}

///|
fn read_le24(data : Bytes, pos : Int32) -> Int32 {
  data[pos].to_int() |
  (data[pos + 1].to_int() << 8) |
  (data[pos + 2].to_int() << 16)
}

///|
/// Returns the payload of the first chunk of the given type
fn find_chunk(
  webp_data : Bytes,
  file : @riff.WebPFile,
  chunk_type : @riff.ChunkType,
) -> Bytes? raise DecodeError {
  for chunk in file.chunks {
    if chunk.chunk_type == chunk_type {
      return Some(payload(webp_data, chunk))
    }
  }
  None
}

///|
/// Returns the payload of the ALPH chunk that libwebp applies: the last one
/// before the VP8 chunk
fn find_alpha_chunk(
  webp_data : Bytes,
  file : @riff.WebPFile,
) -> Bytes? raise DecodeError {
  let mut alpha = None
  for chunk in file.chunks {
    match chunk.chunk_type {
      VP8 => break
      ALPH => alpha = Some(chunk)
      _ => ()
    }
  }
  match alpha {
    Some(chunk) => Some(payload(webp_data, chunk))
    None => None
  }
}

///|
fn payload(webp_data : Bytes, chunk : @riff.Chunk) -> Bytes raise DecodeError {
  if chunk.size > webp_data.length() - chunk.offset {
    raise DecodeError("\{chunk.chunk_type} chunk exceeds file size")
  }
  Bytes::makei(chunk.size, fn(i) { webp_data[chunk.offset + i] })
}
