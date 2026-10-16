///|
/// Why a WebP file could not be decoded. The message describes the problem
/// for humans; match on the constructor to tell the cases apart.
pub(all) suberror DecodeError {
  /// The data is not a valid WebP file (truncated, corrupt or inconsistent)
  Invalid(String)
  /// The file is valid but uses a feature this decoder does not implement,
  /// such as animation
  Unsupported(String)
  /// The image has more pixels than the `max_pixels` limit allows
  TooLarge(String)
}

///|
/// Decoded pixels: `width * height * 4` bytes in RGBA order
pub(all) struct ImageData {
  width : Int32
  height : Int32
  data : Bytes
}

///|
pub impl Show for DecodeError with fn output(self, logger) {
  match self {
    Invalid(message) => logger.write_string("invalid WebP: \{message}")
    Unsupported(message) => logger.write_string("unsupported WebP: \{message}")
    TooLarge(message) => logger.write_string("WebP image too large: \{message}")
  }
}

///|
pub extend DecodeError with Show::{to_string, output}
