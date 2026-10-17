///|
/// A frame of an animated WebP file, read from its ANMF chunk
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
  // an ALPH chunk, or the alpha bit of the VP8L header (libwebp's has_alpha)
  has_alpha : Bool
}

///|
/// The chunks of an animated WebP file, including the ones inside ANMF chunks
fn animation_chunks(webp_data : Bytes) -> Array[@riff.Chunk] raise DecodeError {
  // only the header: the chunks are scanned differently from a still image
  guard @riff.parse_header(webp_data) is Some(file_size) else {
    raise Invalid("invalid RIFF/WebP header")
  }
  // like libwebp's demuxer, which reads nothing after the RIFF data
  if file_size < 0 || file_size > webp_data.length() - 8 {
    raise Invalid("file is shorter than the RIFF size")
  }
  let end = file_size + 8
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
          has_alpha: alpha is Some(_) ||
          (image.chunk_type is VP8L && vp8l_alpha_bit(webp_data, image)),
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
priv struct Animation {
  canvas_width : Int32
  canvas_height : Int32
  loop_count : Int32 // 0 means forever
  background_color : UInt32 // 0xAARRGGBB; libwebp does not draw it
  frames : Array[AnimFrame]
}

///|
/// Reads the structure of an animated WebP file without decoding any frame
fn parse_animation(webp_data : Bytes) -> Animation raise DecodeError {
  let chunks = animation_chunks(webp_data)
  guard chunks is [{ chunk_type: VP8X, .. } as vp8x, ..] else {
    raise Invalid("animated WebP without VP8X")
  }
  let header = parse_vp8x(payload(webp_data, vp8x))
  // libwebp's MAX_IMAGE_AREA
  if header.canvas_width.to_int64() * header.canvas_height.to_int64() >=
    1L << 32 {
    raise Invalid(
      "canvas is too large: \{header.canvas_width}x\{header.canvas_height}",
    )
  }
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
  // the bitstream decode_frame reads: the chunk with its padding
  let bitstream = frame_bitstream(webp_data, chunk)
  if chunk.chunk_type is VP8L {
    @vp8l.image_size(bitstream)
  } else {
    @vp8.frame_size(bitstream, chunk_size=chunk.size)
  }
}

///|
/// Decodes the image of one frame, at the frame's size
fn decode_frame(
  webp_data : Bytes,
  frame : AnimFrame,
) -> ImageData raise DecodeError {
  let image = frame.image
  let bitstream = frame_bitstream(webp_data, image)
  if image.chunk_type is VP8L {
    @vp8l.decode_bitstream(bitstream)
  } else {
    let alpha = match frame.alpha {
      Some(chunk) =>
        Some(decode_alpha(payload(webp_data, chunk), frame.width, frame.height))
      None => None
    }
    @vp8.decode_bitstream(bitstream, alpha?)
  }
}

///|
/// Draws the frames of an animation one after another on a canvas, like
/// libwebp's WebPAnimDecoder (RGBA, not premultiplied)
priv struct Compositor {
  animation : Animation
  canvas : FixedArray[Byte]
  // the canvas after the previous frame, with its dispose method applied
  disposed : FixedArray[Byte]
  mut next : Int32 // index of the next frame
  mut timestamp : Int32 // milliseconds at the end of the previous frame
  mut previous_was_key_frame : Bool
}

///|
fn Compositor::new(animation : Animation) -> Compositor {
  let size = animation.canvas_width * animation.canvas_height * 4
  {
    animation,
    canvas: FixedArray::make(size, b'\x00'),
    disposed: FixedArray::make(size, b'\x00'),
    next: 0,
    timestamp: 0,
    previous_was_key_frame: false,
  }
}

///|
/// Draws the next frame and returns the time at which it ends, or `None`
/// after the last frame. Follows libwebp's WebPAnimDecoderGetNext.
fn Compositor::draw_next(
  self : Compositor,
  webp_data : Bytes,
) -> Int32? raise DecodeError {
  let frames = self.animation.frames
  if self.next >= frames.length() {
    return None
  }
  let frame = frames[self.next]
  let previous = if self.next > 0 { Some(frames[self.next - 1]) } else { None }
  let key_frame = self.is_key_frame(frame, previous)
  if key_frame {
    self.canvas.fill(b'\x00')
  } else {
    self.disposed.blit_to(self.canvas, len=self.canvas.length())
  }
  let image = decode_frame(webp_data, frame)
  let stride = self.animation.canvas_width * 4
  for y in 0..<frame.height {
    let row = (frame.y + y) * stride + frame.x * 4
    for i in 0..<(frame.width * 4) {
      self.canvas[row + i] = image.data[y * frame.width * 4 + i]
    }
  }
  if previous is Some(previous) && frame.blend && !key_frame {
    for y in frame.y..<(frame.y + frame.height) {
      if previous.dispose_to_background {
        // the previous frame's rectangle is transparent black, which blends
        // to the frame's own pixel; blend only the rest of the row
        self.blend_outside(frame, previous, y)
      } else {
        self.blend_row(y, frame.x, frame.width)
      }
    }
  }
  self.canvas.blit_to(self.disposed, len=self.canvas.length())
  if frame.dispose_to_background {
    for y in frame.y..<(frame.y + frame.height) {
      let start = y * stride + frame.x * 4
      self.disposed.fill(b'\x00', start~, end=start + frame.width * 4)
    }
  }
  self.previous_was_key_frame = key_frame
  self.timestamp += frame.duration
  self.next += 1
  Some(self.timestamp)
}

///|
/// libwebp's IsKeyFrame: whether the frame is drawn on a transparent canvas
/// instead of the previous one
fn Compositor::is_key_frame(
  self : Compositor,
  frame : AnimFrame,
  previous : AnimFrame?,
) -> Bool {
  guard previous is Some(previous) else { return true }
  if (!frame.has_alpha || !frame.blend) && self.is_full(frame) {
    return true
  }
  previous.dispose_to_background &&
  (self.is_full(previous) || self.previous_was_key_frame)
}

///|
fn Compositor::is_full(self : Compositor, frame : AnimFrame) -> Bool {
  frame.width == self.animation.canvas_width &&
  frame.height == self.animation.canvas_height
}

///|
/// libwebp's FindBlendRangeAtRow: blends the parts of row `y` of the frame
/// that lie outside the previous frame's rectangle
fn Compositor::blend_outside(
  self : Compositor,
  frame : AnimFrame,
  previous : AnimFrame,
  y : Int32,
) -> Unit {
  let frame_end = frame.x + frame.width
  let previous_end = previous.x + previous.width
  if y < previous.y ||
    y >= previous.y + previous.height ||
    frame.x >= previous_end ||
    frame_end <= previous.x {
    self.blend_row(y, frame.x, frame.width)
    return
  }
  if frame.x < previous.x {
    self.blend_row(y, frame.x, previous.x - frame.x)
  }
  if frame_end > previous_end {
    self.blend_row(y, previous_end, frame_end - previous_end)
  }
}

///|
/// Blends `width` pixels of row `y` from `x` onto the disposed canvas
fn Compositor::blend_row(
  self : Compositor,
  y : Int32,
  x : Int32,
  width : Int32,
) -> Unit {
  let start = (y * self.animation.canvas_width + x) * 4
  for i = start; i < start + width * 4; i = i + 4 {
    if self.canvas[i + 3] != b'\xff' {
      blend_pixel(self.canvas, self.disposed, i)
    }
  }
}

///|
/// libwebp's BlendPixelNonPremult: draws the pixel of `src` at `i` over the
/// one of `dst`, in place in `src`
fn blend_pixel(
  src : FixedArray[Byte],
  dst : FixedArray[Byte],
  i : Int32,
) -> Unit {
  let src_a = src[i + 3].to_int()
  if src_a == 0 {
    for c in 0..<4 {
      src[i + c] = dst[i + c]
    }
    return
  }
  let dst_a = dst[i + 3].to_int()
  // approximately dst_a * (255 - src_a) / 255
  let dst_factor_a = (dst_a * (256 - src_a)) >> 8
  let blend_a = src_a + dst_factor_a
  let scale = (1 << 24) / blend_a
  for c in 0..<3 {
    let unscaled = src[i + c].to_int() * src_a +
      dst[i + c].to_int() * dst_factor_a
    // libwebp computes this in 32 bits; it cannot overflow
    src[i + c] = ((unscaled.to_int64() * scale.to_int64()) >> 24).to_byte()
  }
  src[i + 3] = blend_a.to_byte()
}

///|
/// The alpha_is_used bit of a VP8L header
fn vp8l_alpha_bit(webp_data : Bytes, chunk : @riff.Chunk) -> Bool {
  // after the signature byte, 14 bits of width - 1 and 14 of height - 1
  chunk.size >= 5 && (webp_data[chunk.offset + 4].to_int() & 0x10) != 0
}

///|
/// One frame of an animation: the whole canvas after the frame is drawn
pub(all) struct AnimationFrame {
  /// The canvas, `width * height * 4` bytes of RGBA, not premultiplied
  image : ImageData
  /// When the frame ends, in milliseconds from the start of the animation
  timestamp : Int32
  /// How long the frame is shown, in milliseconds
  duration : Int32
}

///|
/// Decodes an animated WebP file frame by frame, drawing each frame on the
/// canvas like libwebp's WebPAnimDecoder. A still image is one frame.
struct AnimationDecoder {
  webp_data : Bytes
  source : FrameSource
}

///|
priv enum FrameSource {
  Animated(Compositor)
  // a still image, until its one frame has been returned
  Still(StillImage, Ref[Bool])
}

///|
/// Reads and checks the structure of a WebP file. Raises `TooLarge` when the
/// canvas has more than `max_pixels` pixels.
///
/// Like libwebp's WebPAnimDecoder, a still image is an animation of one frame
/// at time 0 that plays once; it decodes like `decode`.
pub fn AnimationDecoder::new(
  webp_data : Bytes,
  max_pixels~ : Int32 = MAX_PIXELS,
) -> AnimationDecoder raise DecodeError {
  if !is_animation(webp_data) {
    let still = read_still(webp_data, max_pixels)
    return { webp_data, source: Still(still, Ref(false)), }
  }
  let animation = parse_animation(webp_data)
  let width = animation.canvas_width
  let height = animation.canvas_height
  // the canvas is up to 2^32 pixels, so compare in 64 bits
  if width.to_int64() * height.to_int64() > max_pixels.to_int64() {
    raise TooLarge(
      "canvas size \{width}x\{height} exceeds \{max_pixels} pixels",
    )
  }
  { webp_data, source: Animated(Compositor::new(animation)), }
}

///|
/// Draws the next frame and returns it, or `None` after the last frame.
/// Each frame's image is a new copy of the canvas.
pub fn AnimationDecoder::next_frame(
  self : AnimationDecoder,
) -> AnimationFrame? raise DecodeError {
  match self.source {
    Still(_, { val: true, }) => None
    Still(still, done) => {
      done.val = true
      Some({
        image: decode_still(self.webp_data, still),
        timestamp: 0,
        duration: 0,
      })
    }
    Animated(compositor) => {
      guard compositor.draw_next(self.webp_data) is Some(timestamp) else {
        return None
      }
      let canvas = compositor.canvas
      let animation = compositor.animation
      Some({
        image: {
          width: animation.canvas_width,
          height: animation.canvas_height,
          data: Bytes::makei(canvas.length(), fn(i) { canvas[i] }),
        },
        timestamp,
        duration: animation.frames[compositor.next - 1].duration,
      })
    }
  }
}

///|
/// The canvas width
pub fn AnimationDecoder::width(self : AnimationDecoder) -> Int32 {
  match self.source {
    Still(still, _) => still.width
    Animated(compositor) => compositor.animation.canvas_width
  }
}

///|
/// The canvas height
pub fn AnimationDecoder::height(self : AnimationDecoder) -> Int32 {
  match self.source {
    Still(still, _) => still.height
    Animated(compositor) => compositor.animation.canvas_height
  }
}

///|
/// The number of frames
pub fn AnimationDecoder::frame_count(self : AnimationDecoder) -> Int32 {
  match self.source {
    Still(_, _) => 1
    Animated(compositor) => compositor.animation.frames.length()
  }
}

///|
/// How many times the animation plays; 0 means forever
pub fn AnimationDecoder::loop_count(self : AnimationDecoder) -> Int32 {
  match self.source {
    Still(_, _) => 1
    Animated(compositor) => compositor.animation.loop_count
  }
}

///|
/// The background color in the ANIM chunk, as 0xAARRGGBB (0xffffffff for a
/// still image). Like libwebp's WebPAnimDecoder, the decoder does not use
/// it: frames are drawn on a transparent canvas.
pub fn AnimationDecoder::background_color(self : AnimationDecoder) -> UInt32 {
  match self.source {
    Still(_, _) => 0xffffffff
    Animated(compositor) => compositor.animation.background_color
  }
}

///|
/// The bitstream of a frame's VP8 or VP8L chunk. Unlike a still image's, it
/// ends with the chunk and its padding, as in libwebp's demuxer.
fn frame_bitstream(webp_data : Bytes, chunk : @riff.Chunk) -> Bytes {
  // animation_chunks checked that the padded chunk is in the RIFF data
  Bytes::makei(chunk.size + chunk.size % 2, fn(i) {
    webp_data[chunk.offset + i]
  })
}
