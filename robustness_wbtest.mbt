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
/// Every truncation of the payload of each VP8, VP8L and ALPH chunk, with the
/// chunk and RIFF sizes fixed up so that the decoders reach the cut
fn truncate_payloads(data : Bytes) -> Unit {
  let file = @riff.parse(data).unwrap()
  let chunks = file.chunks.map(fn(chunk) {
    (
      chunk.chunk_type.fourcc(),
      Bytes::makei(chunk.size, fn(i) { data[chunk.offset + i] }),
    )
  })
  for k, chunk in chunks {
    let (fourcc, payload) = chunk
    guard fourcc is ("VP8" | "VP8L" | "ALPH") else { continue }
    for len in 0..<payload.length() {
      let parts = chunks.mapi(fn(j, part) {
        let (cc, bytes) = part
        // ChunkType::fourcc drops the trailing space of "VP8 "
        let cc = if cc == "VP8" { "VP8 " } else { cc }
        if j == k {
          (cc, Bytes::makei(len, fn(i) { bytes[i] }))
        } else {
          (cc, bytes)
        }
      })
      decode_or_reject(build_webp(parts))
    }
  }
}

///|
/// Every truncation (of the file, and of each image payload) and four
/// single-byte changes at every position
fn mutate_all(path : String) -> Unit raise {
  let data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let n = data.length()
  for len in 0..<n {
    decode_or_reject(Bytes::makei(len, fn(i) { data[i] }))
  }
  truncate_payloads(data)
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
