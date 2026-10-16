///|
/// Decodes the payload of an ALPH chunk to one alpha value per pixel
/// (libwebp src/dec/alpha_dec.c)
fn decode_alpha(
  chunk : Bytes,
  width : Int32,
  height : Int32,
) -> FixedArray[Byte] raise DecodeError {
  if chunk.length() <= 1 {
    raise DecodeError("ALPH chunk has no data")
  }
  let header = chunk[0].to_int()
  let compression = header & 3
  let filter = (header >> 2) & 3
  let pre_processing = (header >> 4) & 3
  let reserved = header >> 6
  if compression > 1 || pre_processing > 1 || reserved != 0 {
    raise DecodeError("invalid ALPH header: \{header}")
  }
  let payload = Bytes::makei(chunk.length() - 1, fn(i) { chunk[1 + i] })
  // filtered alpha values, one per pixel
  let deltas = if compression == 1 {
    let rgba = @vp8l.decode_image_stream(payload, width, height)
    Bytes::makei(width * height, fn(i) { rgba[4 * i + 1] })
  } else {
    if payload.length() < width * height {
      raise DecodeError("ALPH chunk too short for \{width}x\{height} pixels")
    }
    payload
  }
  let alpha = FixedArray::make(width * height, b'\x00')
  for y in 0..<height {
    let row = y * width
    let prev = if y == 0 { -1 } else { row - width }
    match filter {
      1 => horizontal_unfilter(alpha, prev, deltas, row, width)
      2 => vertical_unfilter(alpha, prev, deltas, row, width)
      3 => gradient_unfilter(alpha, prev, deltas, row, width)
      _ =>
        for i in 0..<width {
          alpha[row + i] = deltas[row + i]
        }
    }
  }
  alpha
}

///|
/// HorizontalUnfilter_C. Unfilters the row at `pos`; `prev` is the offset of
/// the previous row in `out`, or -1 for the first row.
fn horizontal_unfilter(
  out : FixedArray[Byte],
  prev : Int32,
  deltas : Bytes,
  pos : Int32,
  width : Int32,
) -> Unit {
  let mut pred = if prev < 0 { b'\x00' } else { out[prev] }
  for i in 0..<width {
    pred = pred + deltas[pos + i]
    out[pos + i] = pred
  }
}

///|
/// VerticalUnfilter_C
fn vertical_unfilter(
  out : FixedArray[Byte],
  prev : Int32,
  deltas : Bytes,
  pos : Int32,
  width : Int32,
) -> Unit {
  if prev < 0 {
    horizontal_unfilter(out, prev, deltas, pos, width)
  } else {
    for i in 0..<width {
      out[pos + i] = out[prev + i] + deltas[pos + i]
    }
  }
}

///|
/// GradientUnfilter_C
fn gradient_unfilter(
  out : FixedArray[Byte],
  prev : Int32,
  deltas : Bytes,
  pos : Int32,
  width : Int32,
) -> Unit {
  if prev < 0 {
    horizontal_unfilter(out, prev, deltas, pos, width)
  } else {
    let mut top_left = out[prev].to_int()
    let mut left = top_left
    for i in 0..<width {
      let top = out[prev + i].to_int()
      let g = left + top - top_left
      let pred = if (g & (0xff ^ -1)) == 0 {
        g
      } else if g < 0 {
        0
      } else {
        255
      }
      left = (deltas[pos + i].to_int() + pred) & 0xff
      top_left = top
      out[pos + i] = left.to_byte()
    }
  }
}
