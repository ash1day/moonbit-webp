///|
pub using @image {type DecodeError, type ImageData}

///|
/// VP8X flag bits (libwebp src/webp/mux_types.h)
const ANIMATION_FLAG = 0x02

///|
/// The largest image a WebP file can hold (VP8L stores 14-bit dimensions)
pub const MAX_PIXELS : Int32 = 16384 * 16384

///|
/// Decodes a WebP file to RGBA. Images with more than `max_pixels` pixels
/// raise `DecodeError` before any pixel buffer is allocated.
pub fn decode(
  webp_data : Bytes,
  max_pixels~ : Int32 = MAX_PIXELS,
) -> ImageData raise DecodeError {
  decode_still(webp_data, read_still(webp_data, max_pixels))
}

///|
/// A still image whose headers have been read and checked
priv struct StillImage {
  file : @riff.WebPFile
  image : @riff.Chunk // the VP8 or VP8L chunk
  width : Int32
  height : Int32
}

///|
/// Whether the file has a VP8X chunk with the animation flag
fn is_animation(webp_data : Bytes) -> Bool {
  match @riff.parse(webp_data) {
    Some({ chunks: [{ chunk_type: VP8X, offset, size, }, ..], .. }) =>
      size >= 1 &&
      offset < webp_data.length() &&
      (webp_data[offset].to_int() & ANIMATION_FLAG) != 0
    _ => false
  }
}

///|
/// Reads and checks the headers of a still image, and its size against
/// `max_pixels`, without allocating any pixel buffer
fn read_still(
  webp_data : Bytes,
  max_pixels : Int32,
) -> StillImage raise DecodeError {
  let file = match @riff.parse(webp_data) {
    Some(f) => f
    None => raise Invalid("invalid RIFF/WebP header")
  }
  // like libwebp, only a VP8X right after "WEBP" makes the extended format
  let vp8x = match file.chunks {
    [{ chunk_type: VP8X, .. } as chunk, ..] =>
      Some(parse_vp8x(payload(webp_data, chunk)))
    _ => None
  }
  check_riff_size(webp_data, file, padded=vp8x is Some(_))
  if vp8x is None {
    check_simple_format(file)
  }
  if vp8x is Some(header) && (header.flags & ANIMATION_FLAG) != 0 {
    raise Unsupported("animated WebP is not supported")
  }
  // the RIFF parser stops after the image chunk
  guard file.chunks.last() is Some({ chunk_type: VP8 | VP8L, .. } as image) else {
    raise Invalid("no VP8 or VP8L chunk found")
  }
  let (width, height) = if image.chunk_type is VP8L {
    @vp8l.image_size(payload(webp_data, image))
  } else {
    @vp8.frame_size(payload(webp_data, image))
  }
  if vp8x is Some({ canvas_width, canvas_height, .. }) &&
    (canvas_width != width || canvas_height != height) {
    raise Invalid(
      "VP8X canvas size \{canvas_width}x\{canvas_height} does not match the image size \{width}x\{height}",
    )
  }
  if width * height > max_pixels {
    raise TooLarge("image size \{width}x\{height} exceeds \{max_pixels} pixels")
  }
  { file, image, width, height, }
}

///|
/// Decodes a still image read by `read_still`
fn decode_still(
  webp_data : Bytes,
  still : StillImage,
) -> ImageData raise DecodeError {
  let image = still.image
  // like libwebp, the bitstream runs to the end of the input, not of the chunk
  let bitstream = Bytes::makei(webp_data.length() - image.offset, fn(i) {
    webp_data[image.offset + i]
  })
  if image.chunk_type is VP8L {
    @vp8l.decode_bitstream(bitstream)
  } else {
    let alpha = match find_alpha_chunk(webp_data, still.file) {
      Some(chunk) => Some(decode_alpha(chunk, still.width, still.height))
      None => None
    }
    @vp8.decode_bitstream(bitstream, alpha?)
  }
}

///|
/// Like libwebp, rejects chunks that extend past the size in the RIFF header.
/// In the extended format libwebp counts the padding of odd-sized chunks too.
fn check_riff_size(
  webp_data : Bytes,
  file : @riff.WebPFile,
  padded~ : Bool,
) -> Unit raise DecodeError {
  // the size field counts from byte 8; the chunks before the image must fit
  if file.file_size < 0 || file.file_size > webp_data.length() - 8 {
    raise Invalid("file is shorter than the RIFF size")
  }
  let riff_end = file.file_size + 8
  for chunk in file.chunks {
    // subtracting the padding cannot overflow, adding it to the size can
    let padding = if padded { chunk.size % 2 } else { 0 }
    if chunk.offset > riff_end || chunk.size > riff_end - chunk.offset - padding {
      raise Invalid("\{chunk.chunk_type.fourcc()} chunk exceeds the RIFF size")
    }
  }
}

///|
/// Without VP8X, libwebp requires the image chunk to come first
fn check_simple_format(file : @riff.WebPFile) -> Unit raise DecodeError {
  match file.chunks {
    [] | [{ chunk_type: VP8 | VP8L, .. }, ..] => ()
    [{ chunk_type, .. }, ..] =>
      raise Invalid(
        "\{chunk_type.fourcc()} chunk before the image without VP8X",
      )
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
    raise Invalid("invalid VP8X chunk size: \{chunk.length()}")
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
    raise Invalid("\{chunk.chunk_type.fourcc()} chunk exceeds file size")
  }
  Bytes::makei(chunk.size, fn(i) { webp_data[chunk.offset + i] })
}
