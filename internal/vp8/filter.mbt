// Loop filters (RFC 6386 section 15), ported from libwebp src/dsp/dec.c.
// `p` is the offset of the first pixel after the edge; `step` moves across
// the edge and the loops move along it.

///|
/// VP8ksclip1: clips [-1020, 1020] to [-128, 127]
fn sclip1(v : Int32) -> Int32 {
  if v < -128 {
    -128
  } else if v > 127 {
    127
  } else {
    v
  }
}

///|
/// VP8ksclip2: clips [-112, 112] to [-16, 15]
fn sclip2(v : Int32) -> Int32 {
  if v < -16 {
    -16
  } else if v > 15 {
    15
  } else {
    v
  }
}

///|
fn abs(v : Int32) -> Int32 {
  if v < 0 {
    -v
  } else {
    v
  }
}

///|
/// Filters the two pixels on either side of the edge
fn do_filter2(buf : FixedArray[Byte], p : Int32, step : Int32) -> Unit {
  let p1 = buf[p - 2 * step].to_int()
  let p0 = buf[p - step].to_int()
  let q0 = buf[p].to_int()
  let q1 = buf[p + step].to_int()
  let a = 3 * (q0 - p0) + sclip1(p1 - q1)
  let a1 = sclip2((a + 4) >> 3)
  let a2 = sclip2((a + 3) >> 3)
  buf[p - step] = clip_8b(p0 + a2).to_byte()
  buf[p] = clip_8b(q0 - a1).to_byte()
}

///|
/// Filters four pixels (inner edges, normal filter)
fn do_filter4(buf : FixedArray[Byte], p : Int32, step : Int32) -> Unit {
  let p1 = buf[p - 2 * step].to_int()
  let p0 = buf[p - step].to_int()
  let q0 = buf[p].to_int()
  let q1 = buf[p + step].to_int()
  let a = 3 * (q0 - p0)
  let a1 = sclip2((a + 4) >> 3)
  let a2 = sclip2((a + 3) >> 3)
  let a3 = (a1 + 1) >> 1
  buf[p - 2 * step] = clip_8b(p1 + a3).to_byte()
  buf[p - step] = clip_8b(p0 + a2).to_byte()
  buf[p] = clip_8b(q0 - a1).to_byte()
  buf[p + step] = clip_8b(q1 - a3).to_byte()
}

///|
/// Filters six pixels (macroblock edges, normal filter)
fn do_filter6(buf : FixedArray[Byte], p : Int32, step : Int32) -> Unit {
  let p2 = buf[p - 3 * step].to_int()
  let p1 = buf[p - 2 * step].to_int()
  let p0 = buf[p - step].to_int()
  let q0 = buf[p].to_int()
  let q1 = buf[p + step].to_int()
  let q2 = buf[p + 2 * step].to_int()
  let a = sclip1(3 * (q0 - p0) + sclip1(p1 - q1))
  let a1 = (27 * a + 63) >> 7
  let a2 = (18 * a + 63) >> 7
  let a3 = (9 * a + 63) >> 7
  buf[p - 3 * step] = clip_8b(p2 + a3).to_byte()
  buf[p - 2 * step] = clip_8b(p1 + a2).to_byte()
  buf[p - step] = clip_8b(p0 + a1).to_byte()
  buf[p] = clip_8b(q0 - a1).to_byte()
  buf[p + step] = clip_8b(q1 - a2).to_byte()
  buf[p + 2 * step] = clip_8b(q2 - a3).to_byte()
}

///|
/// High edge variance
fn hev(buf : FixedArray[Byte], p : Int32, step : Int32, thresh : Int32) -> Bool {
  let p1 = buf[p - 2 * step].to_int()
  let p0 = buf[p - step].to_int()
  let q0 = buf[p].to_int()
  let q1 = buf[p + step].to_int()
  abs(p1 - p0) > thresh || abs(q1 - q0) > thresh
}

///|
fn needs_filter(
  buf : FixedArray[Byte],
  p : Int32,
  step : Int32,
  t : Int32,
) -> Bool {
  let p1 = buf[p - 2 * step].to_int()
  let p0 = buf[p - step].to_int()
  let q0 = buf[p].to_int()
  let q1 = buf[p + step].to_int()
  4 * abs(p0 - q0) + abs(p1 - q1) <= t
}

///|
fn needs_filter2(
  buf : FixedArray[Byte],
  p : Int32,
  step : Int32,
  t : Int32,
  it : Int32,
) -> Bool {
  let p3 = buf[p - 4 * step].to_int()
  let p2 = buf[p - 3 * step].to_int()
  let p1 = buf[p - 2 * step].to_int()
  let p0 = buf[p - step].to_int()
  let q0 = buf[p].to_int()
  let q1 = buf[p + step].to_int()
  let q2 = buf[p + 2 * step].to_int()
  let q3 = buf[p + 3 * step].to_int()
  if 4 * abs(p0 - q0) + abs(p1 - q1) > t {
    return false
  }
  abs(p3 - p2) <= it &&
  abs(p2 - p1) <= it &&
  abs(p1 - p0) <= it &&
  abs(q3 - q2) <= it &&
  abs(q2 - q1) <= it &&
  abs(q1 - q0) <= it
}

///|
fn simple_filter(
  buf : FixedArray[Byte],
  p : Int32,
  step : Int32,
  along : Int32,
  thresh : Int32,
) -> Unit {
  let thresh2 = 2 * thresh + 1
  for i in 0..<16 {
    if needs_filter(buf, p + i * along, step, thresh2) {
      do_filter2(buf, p + i * along, step)
    }
  }
}

///|
fn simple_v_filter16(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
) -> Unit {
  simple_filter(buf, p, stride, 1, thresh)
}

///|
fn simple_h_filter16(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
) -> Unit {
  simple_filter(buf, p, 1, stride, thresh)
}

///|
fn simple_v_filter16i(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
) -> Unit {
  for k in 1..<=3 {
    simple_v_filter16(buf, p + 4 * k * stride, stride, thresh)
  }
}

///|
fn simple_h_filter16i(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
) -> Unit {
  for k in 1..<=3 {
    simple_h_filter16(buf, p + 4 * k, stride, thresh)
  }
}

///|
/// FilterLoop26_C (macroblock edges) and FilterLoop24_C (inner edges)
fn filter_loop(
  buf : FixedArray[Byte],
  p : Int32,
  hstride : Int32,
  vstride : Int32,
  size : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
  macroblock_edge : Bool,
) -> Unit {
  let thresh2 = 2 * thresh + 1
  for i in 0..<size {
    let q = p + i * vstride
    if needs_filter2(buf, q, hstride, thresh2, ithresh) {
      if hev(buf, q, hstride, hev_thresh) {
        do_filter2(buf, q, hstride)
      } else if macroblock_edge {
        do_filter6(buf, q, hstride)
      } else {
        do_filter4(buf, q, hstride)
      }
    }
  }
}

///|
fn v_filter16(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  filter_loop(buf, p, stride, 1, 16, thresh, ithresh, hev_thresh, true)
}

///|
fn h_filter16(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  filter_loop(buf, p, 1, stride, 16, thresh, ithresh, hev_thresh, true)
}

///|
fn v_filter16i(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  for k in 1..<=3 {
    filter_loop(
      buf,
      p + 4 * k * stride,
      stride,
      1,
      16,
      thresh,
      ithresh,
      hev_thresh,
      false,
    )
  }
}

///|
fn h_filter16i(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  for k in 1..<=3 {
    filter_loop(
      buf,
      p + 4 * k,
      1,
      stride,
      16,
      thresh,
      ithresh,
      hev_thresh,
      false,
    )
  }
}

///|
fn v_filter8(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  filter_loop(buf, p, stride, 1, 8, thresh, ithresh, hev_thresh, true)
}

///|
fn h_filter8(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  filter_loop(buf, p, 1, stride, 8, thresh, ithresh, hev_thresh, true)
}

///|
fn v_filter8i(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  filter_loop(
    buf,
    p + 4 * stride,
    stride,
    1,
    8,
    thresh,
    ithresh,
    hev_thresh,
    false,
  )
}

///|
fn h_filter8i(
  buf : FixedArray[Byte],
  p : Int32,
  stride : Int32,
  thresh : Int32,
  ithresh : Int32,
  hev_thresh : Int32,
) -> Unit {
  filter_loop(buf, p + 4, 1, stride, 8, thresh, ithresh, hev_thresh, false)
}
