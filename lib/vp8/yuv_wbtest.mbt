///|
fn to_ints(values : Array[Int32]) -> FixedArray[Int32] {
  FixedArray::makei(values.length(), fn(i) { values[i] })
}

///|
/// Expected values are from libwebp's UpsampleRgbaLinePair_C, driven the way
/// EmitFancyRGB drives it when the whole picture is emitted at once.
test "fancy upsampling to RGBA matches libwebp" {
  {
    let y = to_ints([
      167, 241, 217, 42, 130, 200, 216, 254, 67, 77, 152, 85, 140, 226, 179, 71,
      23, 17, 152, 84, 47, 17, 45, 5, 88,
    ])
    let u = to_ints([245, 214, 7, 146, 51, 65, 13, 229, 48])
    let v = to_ints([107, 136, 153, 72, 98, 243, 35, 95, 209])
    let expected : Array[Int32] = [
      142, 147, 255, 255, 240, 231, 255, 255, 236, 196, 255, 255, 49, 7, 99, 255,
      166, 143, 0, 255, 166, 203, 255, 255, 196, 220, 255, 255, 255, 255, 255, 255,
      77, 48, 73, 255, 127, 70, 0, 255, 83, 180, 245, 255, 15, 105, 127, 255, 101,
      173, 112, 255, 255, 255, 150, 255, 255, 164, 55, 255, 0, 123, 34, 255, 0, 62,
      0, 255, 0, 44, 0, 255, 165, 171, 76, 255, 194, 44, 0, 255, 0, 137, 0, 255,
      0, 77, 0, 255, 0, 62, 78, 255, 0, 0, 34, 255, 178, 53, 0, 255,
    ]
    let rgba = yuv_to_rgba(y, 5, u, v, 3, 5, 5)
    assert_eq(Array::makei(rgba.length(), fn(i) { rgba[i].to_int() }), expected)
  }
  {
    let y = to_ints([
      78, 226, 179, 84, 5, 144, 176, 253, 135, 155, 48, 171, 25, 196, 102, 143, 47,
      34, 48, 168, 94, 35, 91, 11,
    ])
    let u = to_ints([177, 214, 16, 51, 144, 197])
    let v = to_ints([235, 173, 15, 37, 102, 130])
    let expected : Array[Int32] = [
      243, 0, 171, 255, 255, 147, 255, 255, 255, 110, 255, 255, 151, 9, 253, 255,
      70, 0, 5, 255, 216, 108, 185, 255, 220, 155, 255, 255, 255, 249, 255, 255,
      46, 214, 0, 255, 69, 234, 35, 255, 0, 101, 0, 255, 90, 241, 108, 255, 0, 116,
      0, 255, 74, 255, 68, 255, 0, 180, 0, 255, 39, 219, 67, 255, 0, 81, 4, 255,
      0, 56, 13, 255, 0, 52, 78, 255, 143, 181, 244, 255, 49, 106, 123, 255, 0, 26,
      81, 255, 79, 69, 200, 255, 0, 0, 133, 255,
    ]
    let rgba = yuv_to_rgba(y, 4, u, v, 2, 4, 6)
    assert_eq(Array::makei(rgba.length(), fn(i) { rgba[i].to_int() }), expected)
  }
  let y = to_ints([245])
  let u = to_ints([211])
  let v = to_ints([141])
  let expected : Array[Int32] = [255, 224, 255, 255]
  let rgba = yuv_to_rgba(y, 1, u, v, 1, 1, 1)
  assert_eq(Array::makei(rgba.length(), fn(i) { rgba[i].to_int() }), expected)
}
