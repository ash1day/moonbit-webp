///|
/// Decodes `data`, accepting either an image or a DecodeError; any other
/// outcome (a panic from an out-of-bounds access) fails the test run. The
/// pixel limit keeps corrupted headers from requesting huge buffers.
fn decode_or_reject(data : Bytes) -> Unit {
  try decode(data, max_pixels=1 << 16) |> ignore catch {
    _ => ()
  }
}

///|
/// Every truncation and four single-byte changes at every position
fn mutate_all(path : String) -> Unit raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let n = data.length()
  for len in 0..<n {
    decode_or_reject(Bytes::makei(len, fn(i) { data[i] }))
  }
  for pos in 0..<n {
    let original = data[pos].to_int()
    for value in [0, 0xff, original ^ 1, original ^ 0x80] {
      decode_or_reject(
        Bytes::makei(n, fn(i) {
          if i == pos {
            value.to_byte()
          } else {
            data[i]
          }
        }),
      )
    }
  }
}

///|
test "truncated and corrupted lossy files do not crash" {
  mutate_all("lossy-extra/small_31x13")
}

///|
test "truncated and corrupted files with alpha do not crash" {
  mutate_all("alpha-extra/alpha_filter_3")
  mutate_all("alpha-extra/alpha_no_compression")
}

///|
test "truncated and corrupted lossless files do not crash" {
  mutate_all("lossless-extra/dual_transform")
  mutate_all("regression/color_index")
}
