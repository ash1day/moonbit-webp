///|
/// Stride of the macroblock work buffer, as BPS in libwebp
let bps : Int32 = 32

///|
fn mul1(a : Int32) -> Int32 {
  ((a * 20091) >> 16) + a
}

///|
fn mul2(a : Int32) -> Int32 {
  (a * 35468) >> 16
}

///|
fn clip_8b(v : Int32) -> Int32 {
  if v < 0 {
    0
  } else if v > 255 {
    255
  } else {
    v
  }
}

///|
/// TransformOne_C: adds the inverse DCT of the 16 coefficients at `offset` to
/// the 4x4 block at `dst_offset`
fn inverse_dct(
  coeffs : FixedArray[Int32],
  offset : Int32,
  dst : FixedArray[Int32],
  dst_offset : Int32,
) -> Unit {
  let tmp = FixedArray::make(16, 0)
  for i in 0..<4 {
    // vertical pass
    let in0 = coeffs[offset + i]
    let in4 = coeffs[offset + 4 + i]
    let in8 = coeffs[offset + 8 + i]
    let in12 = coeffs[offset + 12 + i]
    let a = in0 + in8
    let b = in0 - in8
    let c = mul2(in4) - mul1(in12)
    let d = mul1(in4) + mul2(in12)
    tmp[i * 4] = a + d
    tmp[i * 4 + 1] = b + c
    tmp[i * 4 + 2] = b - c
    tmp[i * 4 + 3] = a - d
  }
  for i in 0..<4 {
    // horizontal pass
    let dc = tmp[i] + 4
    let a = dc + tmp[8 + i]
    let b = dc - tmp[8 + i]
    let c = mul2(tmp[4 + i]) - mul1(tmp[12 + i])
    let d = mul1(tmp[4 + i]) + mul2(tmp[12 + i])
    let row = dst_offset + i * bps
    dst[row] = clip_8b(dst[row] + ((a + d) >> 3))
    dst[row + 1] = clip_8b(dst[row + 1] + ((b + c) >> 3))
    dst[row + 2] = clip_8b(dst[row + 2] + ((b - c) >> 3))
    dst[row + 3] = clip_8b(dst[row + 3] + ((a - d) >> 3))
  }
}

///|
/// TransformWHT_C: writes the inverse WHT of the 16 luma DC coefficients into
/// coefficient 0 of each of the 16 luma blocks
fn inverse_wht(dc : FixedArray[Int32], coeffs : FixedArray[Int32]) -> Unit {
  let tmp = FixedArray::make(16, 0)
  for i in 0..<4 {
    let a0 = dc[i] + dc[12 + i]
    let a1 = dc[4 + i] + dc[8 + i]
    let a2 = dc[4 + i] - dc[8 + i]
    let a3 = dc[i] - dc[12 + i]
    tmp[i] = a0 + a1
    tmp[8 + i] = a0 - a1
    tmp[4 + i] = a3 + a2
    tmp[12 + i] = a3 - a2
  }
  for i in 0..<4 {
    let dc0 = tmp[i * 4] + 3
    let a0 = dc0 + tmp[3 + i * 4]
    let a1 = tmp[1 + i * 4] + tmp[2 + i * 4]
    let a2 = tmp[1 + i * 4] - tmp[2 + i * 4]
    let a3 = dc0 - tmp[3 + i * 4]
    let out = i * 64
    coeffs[out] = (a0 + a1) >> 3
    coeffs[out + 16] = (a3 + a2) >> 3
    coeffs[out + 32] = (a0 - a1) >> 3
    coeffs[out + 48] = (a3 - a2) >> 3
  }
}
