///|
/// Expected values are from libwebp's TransformOne_C and TransformWHT_C run on
/// the same input.
test "inverse DCT adds the residual to the prediction like libwebp" {
  let coeffs : FixedArray[Int32] = [
    -312, 45, 0, 7, 120, -33, 18, 0, -9, 64, 0, -2, 5, 0, -77, 300,
  ]
  let buf = FixedArray::make(4 * bps, 0)
  for y in 0..<4 {
    for x in 0..<4 {
      buf[x + y * bps] = 17 * x + 40 * y + 30
    }
  }
  inverse_dct(coeffs, 0, buf, 0)
  let got = []
  for y in 0..<4 {
    for x in 0..<4 {
      got.push(buf[x + y * bps])
    }
  }
  assert_eq(got, [
    29, 6, 69, 37, 21, 103, 0, 136, 78, 30, 178, 75, 107, 141, 86, 129,
  ])
}

///|
test "inverse WHT writes the DC of each 4x4 block like libwebp" {
  let dc : FixedArray[Int32] = [
    1000, -200, 35, 0, 77, -5, 0, 12, -300, 0, 9, 41, 0, 3, -60, 8,
  ]
  let coeffs = FixedArray::make(256, 0)
  inverse_wht(dc, coeffs)
  let got = []
  for i in 0..<16 {
    got.push(coeffs[i * 16])
  }
  assert_eq(got, [
    77, 66, 132, 113, 152, 140, 183, 213, 119, 139, 175, 178, 69, 37, 92, 113,
  ])
}

///|
/// libwebp's TransformWHT_C writes int16_t: 16 DCs of 32767 sum to 65534 after
/// the shift, which wraps to -2 (value from the C function)
test "inverse WHT output wraps to 16 bits like libwebp" {
  let dc = FixedArray::make(16, 32767)
  let coeffs = FixedArray::make(256, 0)
  inverse_wht(dc, coeffs)
  assert_eq(coeffs[0], -2)
}
