///|
/// Decodes each file given on the command line and prints one line per file:
/// the path, then the MD5 of the RGBA pixels or `ERR:` and the error.
/// With `--animation` first, decodes each file with AnimationDecoder and
/// prints the canvas size, loop count, background color and the timestamp
/// and MD5 of each frame. tools/differential/run.py compares these lines
/// with dwebp, or with tools/anim_oracle for animations.
fn main {
  let args = @env.args()
  // under Node the arguments start with node and the script
  let first = if args.length() > 1 && args[1].has_suffix(".js") { 2 } else { 1 }
  let animation = args.length() > first && args[first] == "--animation"
  for i in (if animation { first + 1 } else { first })..<args.length() {
    let path = args[i]
    let result = try {
      let data = @fs.read_file_to_bytes(path)
      if animation {
        describe_animation(data)
      } else {
        hex(@crypto.md5(@webp.decode(data, max_pixels=1 << 22).data))
      }
    } catch {
      @webp.DecodeError::TooLarge(m) =>
        "ERR:TooLarge:" + m.replace_all(old=" ", new="_")
      @webp.DecodeError::Invalid(m) | @webp.DecodeError::Unsupported(m) =>
        "ERR:" + m.replace_all(old=" ", new="_")
      _ => "IOERR"
    }
    println("\{path} \{result}")
  }
}

///|
fn hex(digest : FixedArray[Byte]) -> String {
  let digits = "0123456789abcdef"
  let sb = StringBuilder()
  for b in digest {
    sb.write_char(digits[b.to_int() >> 4].unsafe_to_char())
    sb.write_char(digits[b.to_int() & 15].unsafe_to_char())
  }
  sb.to_string()
}

///|
fn describe_animation(data : Bytes) -> String raise @webp.DecodeError {
  let decoder = @webp.AnimationDecoder::new(data, max_pixels=1 << 22)
  let sb = StringBuilder()
  sb.write_string(
    "canvas_\{decoder.width()}_\{decoder.height()}_loop_\{decoder.loop_count()}",
  )
  sb.write_string(
    "_bgcolor_\{decoder.background_color()}_frames_\{decoder.frame_count()}",
  )
  while decoder.next_frame() is Some(frame) {
    sb.write_string("|\{frame.timestamp}:\{hex(@crypto.md5(frame.image.data))}")
  }
  sb.to_string()
}
