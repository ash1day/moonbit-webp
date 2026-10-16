// YUV to RGBA conversion with fancy upsampling, ported from libwebp
// src/dsp/yuv.h and src/dsp/upsampling.c (the default output of dwebp).

///|
fn mult_hi(v : Int32, coeff : Int32) -> Int32 {
  (v * coeff) >> 8
}

///|
fn clip8(v : Int32) -> Int32 {
  if (v & (0x3fff ^ -1)) == 0 {
    v >> 6
  } else if v < 0 {
    0
  } else {
    255
  }
}

///|
fn write_rgba(
  out : FixedArray[Byte],
  pos : Int32,
  y : Int32,
  u : Int32,
  v : Int32,
) -> Unit {
  let yy = mult_hi(y, 19077)
  out[pos] = clip8(yy + mult_hi(v, 26149) - 14234).to_byte()
  out[pos + 1] = clip8(yy - mult_hi(u, 6419) - mult_hi(v, 13320) + 8708).to_byte()
  out[pos + 2] = clip8(yy + mult_hi(u, 33050) - 17685).to_byte()
  out[pos + 3] = b'\xff'
}

///|
/// UpsampleRgbaLinePair_C for one channel pair (u, v) handled separately.
/// `bottom_row` is -1 when there is no bottom line.
fn upsample_line_pair(
  out : FixedArray[Byte],
  width : Int32,
  y : FixedArray[Byte],
  top_row : Int32,
  bottom_row : Int32,
  y_stride : Int32,
  u : FixedArray[Byte],
  v : FixedArray[Byte],
  top_uv : Int32,
  cur_uv : Int32,
) -> Unit {
  let top_y = top_row * y_stride
  let bottom_y = bottom_row * y_stride
  let top_dst = top_row * width * 4
  let bottom_dst = bottom_row * width * 4
  let last_pixel_pair = (width - 1) >> 1
  let mut tl_u = u[top_uv].to_int()
  let mut tl_v = v[top_uv].to_int()
  let mut l_u = u[cur_uv].to_int()
  let mut l_v = v[cur_uv].to_int()
  write_rgba(
    out,
    top_dst,
    y[top_y].to_int(),
    (3 * tl_u + l_u + 2) >> 2,
    (3 * tl_v + l_v + 2) >> 2,
  )
  if bottom_row >= 0 {
    write_rgba(
      out,
      bottom_dst,
      y[bottom_y].to_int(),
      (3 * l_u + tl_u + 2) >> 2,
      (3 * l_v + tl_v + 2) >> 2,
    )
  }
  for x = 1; x <= last_pixel_pair; x = x + 1 {
    let t_u = u[top_uv + x].to_int()
    let t_v = v[top_uv + x].to_int()
    let c_u = u[cur_uv + x].to_int()
    let c_v = v[cur_uv + x].to_int()
    let avg_u = tl_u + t_u + l_u + c_u + 8
    let avg_v = tl_v + t_v + l_v + c_v + 8
    let diag_12_u = (avg_u + 2 * (t_u + l_u)) >> 3
    let diag_12_v = (avg_v + 2 * (t_v + l_v)) >> 3
    let diag_03_u = (avg_u + 2 * (tl_u + c_u)) >> 3
    let diag_03_v = (avg_v + 2 * (tl_v + c_v)) >> 3
    write_rgba(
      out,
      top_dst + (2 * x - 1) * 4,
      y[top_y + 2 * x - 1].to_int(),
      (diag_12_u + tl_u) >> 1,
      (diag_12_v + tl_v) >> 1,
    )
    write_rgba(
      out,
      top_dst + 2 * x * 4,
      y[top_y + 2 * x].to_int(),
      (diag_03_u + t_u) >> 1,
      (diag_03_v + t_v) >> 1,
    )
    if bottom_row >= 0 {
      write_rgba(
        out,
        bottom_dst + (2 * x - 1) * 4,
        y[bottom_y + 2 * x - 1].to_int(),
        (diag_03_u + l_u) >> 1,
        (diag_03_v + l_v) >> 1,
      )
      write_rgba(
        out,
        bottom_dst + 2 * x * 4,
        y[bottom_y + 2 * x].to_int(),
        (diag_12_u + c_u) >> 1,
        (diag_12_v + c_v) >> 1,
      )
    }
    tl_u = t_u
    tl_v = t_v
    l_u = c_u
    l_v = c_v
  }
  if (width & 1) == 0 {
    write_rgba(
      out,
      top_dst + (width - 1) * 4,
      y[top_y + width - 1].to_int(),
      (3 * tl_u + l_u + 2) >> 2,
      (3 * tl_v + l_v + 2) >> 2,
    )
    if bottom_row >= 0 {
      write_rgba(
        out,
        bottom_dst + (width - 1) * 4,
        y[bottom_y + width - 1].to_int(),
        (3 * l_u + tl_u + 2) >> 2,
        (3 * l_v + tl_v + 2) >> 2,
      )
    }
  }
}

///|
/// Converts the decoded planes to RGBA the way EmitFancyRGB does when the
/// whole picture is emitted at once
fn yuv_to_rgba(
  y : FixedArray[Byte],
  y_stride : Int32,
  u : FixedArray[Byte],
  v : FixedArray[Byte],
  uv_stride : Int32,
  width : Int32,
  height : Int32,
) -> FixedArray[Byte] {
  let out = FixedArray::make(width * height * 4, b'\x00')
  upsample_line_pair(out, width, y, 0, -1, y_stride, u, v, 0, 0)
  // rows 2k - 1 and 2k use chroma rows k - 1 and k
  let mut row = 1
  while row + 1 < height {
    let uv_row = (row + 1) / 2
    upsample_line_pair(
      out,
      width,
      y,
      row,
      row + 1,
      y_stride,
      u,
      v,
      (uv_row - 1) * uv_stride,
      uv_row * uv_stride,
    )
    row += 2
  }
  if (height & 1) == 0 {
    let uv_row = (height - 1) / 2
    upsample_line_pair(
      out,
      width,
      y,
      height - 1,
      -1,
      y_stride,
      u,
      v,
      uv_row * uv_stride,
      uv_row * uv_stride,
    )
  }
  out
}
