///|
priv struct FrameHeader {
  width : Int32
  height : Int32
  // segment header (RFC 6386 section 9.3)
  use_segment : Bool
  update_map : Bool
  absolute_delta : Bool
  quantizer : FixedArray[Int32] // per segment
  filter_strength : FixedArray[Int32] // per segment
  segment_probs : FixedArray[Int32]
  // filter header (section 9.6)
  simple_filter : Bool
  filter_level : Int32
  sharpness : Int32
  use_lf_delta : Bool
  ref_lf_delta : FixedArray[Int32]
  mode_lf_delta : FixedArray[Int32]
  // token partitions (section 9.5)
  num_partitions : Int32
  partitions : Array[BoolDecoder]
  // quantizer indices (section 9.6)
  base_q : Int32
  dqy1_dc : Int32
  dqy2_dc : Int32
  dqy2_ac : Int32
  dquv_dc : Int32
  dquv_ac : Int32
}

///|
fn find_vp8_chunk(webp_data : Bytes) -> Bytes raise @image.DecodeError {
  let file = match @riff.parse(webp_data) {
    Some(f) => f
    None => raise @image.Invalid("invalid RIFF/WebP header")
  }
  for chunk in file.chunks {
    if chunk.chunk_type == @riff.ChunkType::VP8 {
      if chunk.size > webp_data.length() - chunk.offset {
        raise @image.Invalid("VP8 chunk exceeds file size")
      }
      // Like libwebp, the bitstream runs to the end of the input, not of the
      // chunk
      return Bytes::makei(webp_data.length() - chunk.offset, fn(i) {
        webp_data[chunk.offset + i]
      })
    }
  }
  raise @image.Invalid("no VP8 chunk found")
}

///|
fn slice(data : Bytes, start : Int32, len : Int32) -> Bytes {
  Bytes::makei(len, fn(i) { data[start + i] })
}

///|
fn read_optional_signed(br : BoolDecoder, n : Int32) -> Int32 {
  if br.read_bool(128) {
    br.read_signed(n)
  } else {
    0
  }
}

///|
/// Reads the width and height from the 10-byte frame header of a VP8 chunk
/// payload, validating the header without decoding anything
pub fn frame_size(chunk : Bytes) -> (Int32, Int32) raise @image.DecodeError {
  if chunk.length() < 10 {
    raise @image.Invalid("truncated VP8 header")
  }
  let bits = chunk[0].to_int() |
    (chunk[1].to_int() << 8) |
    (chunk[2].to_int() << 16)
  if (bits & 1) != 0 {
    raise @image.Invalid("not a key frame")
  }
  if ((bits >> 1) & 7) > 3 {
    raise @image.Invalid("unknown VP8 profile")
  }
  if ((bits >> 4) & 1) == 0 {
    raise @image.Invalid("frame not displayable")
  }
  if chunk[3] != b'\x9d' || chunk[4] != b'\x01' || chunk[5] != b'\x2a' {
    raise @image.Invalid("bad VP8 start code")
  }
  let width = ((chunk[7].to_int() << 8) | chunk[6].to_int()) & 0x3fff
  let height = ((chunk[9].to_int() << 8) | chunk[8].to_int()) & 0x3fff
  if width == 0 || height == 0 {
    raise @image.Invalid("zero width or height")
  }
  (width, height)
}

///|
/// Parses the frame header and the first partition header. Returns the header
/// and the boolean decoder positioned at the per-macroblock modes.
fn parse_frame_header(
  chunk : Bytes,
) -> (FrameHeader, BoolDecoder) raise @image.DecodeError {
  let (width, height) = frame_size(chunk)
  let partition_length = (
      chunk[0].to_int() | (chunk[1].to_int() << 8) | (chunk[2].to_int() << 16)
    ) >>
    5
  let rest = chunk.length() - 10
  if partition_length > rest {
    raise @image.Invalid("bad partition length")
  }
  let br = BoolDecoder::new(slice(chunk, 10, partition_length))
  let _color_space = br.read_bool(128)
  let _clamp_type = br.read_bool(128)
  // segment header
  let quantizer = FixedArray::make(4, 0)
  let filter_strength = FixedArray::make(4, 0)
  let segment_probs = FixedArray::make(3, 255)
  let use_segment = br.read_bool(128)
  let mut update_map = false
  let mut absolute_delta = true
  if use_segment {
    update_map = br.read_bool(128)
    if br.read_bool(128) {
      absolute_delta = br.read_bool(128)
      for s in 0..<4 {
        quantizer[s] = read_optional_signed(br, 7)
      }
      for s in 0..<4 {
        filter_strength[s] = read_optional_signed(br, 6)
      }
    }
    if update_map {
      for s in 0..<3 {
        segment_probs[s] = if br.read_bool(128) {
          br.read_literal(8)
        } else {
          255
        }
      }
    }
  }
  // filter header
  let simple_filter = br.read_bool(128)
  let filter_level = br.read_literal(6)
  let sharpness = br.read_literal(3)
  let use_lf_delta = br.read_bool(128)
  let ref_lf_delta = FixedArray::make(4, 0)
  let mode_lf_delta = FixedArray::make(4, 0)
  if use_lf_delta && br.read_bool(128) {
    for i in 0..<4 {
      if br.read_bool(128) {
        ref_lf_delta[i] = br.read_signed(6)
      }
    }
    for i in 0..<4 {
      if br.read_bool(128) {
        mode_lf_delta[i] = br.read_signed(6)
      }
    }
  }
  // token partitions
  let num_partitions = 1 << br.read_literal(2)
  let sizes_start = 10 + partition_length
  let last_part = num_partitions - 1
  if rest - partition_length < 3 * last_part {
    raise @image.Invalid("cannot parse partitions")
  }
  let mut part_start = sizes_start + 3 * last_part
  let mut size_left = chunk.length() - part_start
  let partitions = []
  for p in 0..<last_part {
    let sz = sizes_start + 3 * p
    let mut psize = chunk[sz].to_int() |
      (chunk[sz + 1].to_int() << 8) |
      (chunk[sz + 2].to_int() << 16)
    if psize > size_left {
      psize = size_left
    }
    partitions.push(BoolDecoder::new(slice(chunk, part_start, psize)))
    part_start += psize
    size_left -= psize
  }
  partitions.push(BoolDecoder::new(slice(chunk, part_start, size_left)))
  // quantizer indices
  let base_q = br.read_literal(7)
  let dqy1_dc = read_optional_signed(br, 4)
  let dqy2_dc = read_optional_signed(br, 4)
  let dqy2_ac = read_optional_signed(br, 4)
  let dquv_dc = read_optional_signed(br, 4)
  let dquv_ac = read_optional_signed(br, 4)
  (
    {
      width,
      height,
      use_segment,
      update_map,
      absolute_delta,
      quantizer,
      filter_strength,
      segment_probs,
      simple_filter,
      filter_level,
      sharpness,
      use_lf_delta,
      ref_lf_delta,
      mode_lf_delta,
      num_partitions,
      partitions,
      base_q,
      dqy1_dc,
      dqy2_dc,
      dqy2_ac,
      dquv_dc,
      dquv_ac,
    },
    br,
  )
}
