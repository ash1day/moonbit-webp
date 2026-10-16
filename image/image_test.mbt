///|
test "DecodeError shows its kind and message" {
  inspect(
    @image.Invalid("bad VP8 start code"),
    content="invalid WebP: bad VP8 start code",
  )
  inspect(
    @image.Unsupported("animated WebP is not supported"),
    content="unsupported WebP: animated WebP is not supported",
  )
  inspect(
    @image.TooLarge("image size 16x16 exceeds 255 pixels"),
    content="WebP image too large: image size 16x16 exceeds 255 pixels",
  )
}
