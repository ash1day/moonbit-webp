///|
/// Decodes each file given on the command line and prints one line per file:
/// the path, then the MD5 of the RGBA pixels or `ERR:` and the error.
/// tools/differential/run.py compares these lines with dwebp.
fn main {
  let args = @env.args()
  for i in 1..<args.length() {
    let path = args[i]
    let result = try {
      let data = @fs.read_file_to_bytes(path)
      hex(@crypto.md5(@webp.decode(data, max_pixels=1 << 22).data))
    } catch {
      @webp.DecodeError::Invalid(m)
      | @webp.DecodeError::Unsupported(m)
      | @webp.DecodeError::TooLarge(m) =>
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
