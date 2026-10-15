///|
test "subsample_size" {
  assert_eq(subsample_size(10, 2), 3) // ceil(10/4) = 3
  assert_eq(subsample_size(8, 2), 2) // ceil(8/4) = 2
  assert_eq(subsample_size(1, 3), 1) // ceil(1/8) = 1
  assert_eq(subsample_size(16, 4), 1) // ceil(16/16) = 1
  assert_eq(subsample_size(17, 4), 2) // ceil(17/16) = 2
}

///|
test "subtract_green basic" {
  // pixel: R=10, G=20, B=30, A=255
  // After: R=(10+20)&0xFF=30, G=20, B=(30+20)&0xFF=50, A=255
  let data : FixedArray[Byte] = [10, 20, 30, 255]
  apply_subtract_green(data, 1)
  assert_eq(data[0].to_int(), 30)
  assert_eq(data[1].to_int(), 20)
  assert_eq(data[2].to_int(), 50)
  assert_eq(data[3].to_int(), 255)
}

///|
test "subtract_green wrapping" {
  // R=250, G=20 -> (250+20)&0xFF = 14 (wraps)
  let data : FixedArray[Byte] = [250, 20, 200, 128]
  apply_subtract_green(data, 1)
  assert_eq(data[0].to_int(), 14) // (250+20) & 0xFF
  assert_eq(data[2].to_int(), 220) // (200+20) & 0xFF
}

///|
test "subtract_green multiple pixels" {
  let data : FixedArray[Byte] = [10, 20, 30, 255, 100, 50, 200, 128]
  apply_subtract_green(data, 2)
  assert_eq(data[0].to_int(), 30) // 10+20
  assert_eq(data[2].to_int(), 50) // 30+20
  assert_eq(data[4].to_int(), 150) // 100+50
  assert_eq(data[6].to_int(), 250) // 200+50
}

///|
test "predictor mode 0 - black + alpha" {
  // Mode 0: only adds 0xFF to alpha channel (offset +3)
  let data : FixedArray[Byte] = [0, 0, 0, 0, 10, 20, 30, 40]
  apply_predictor_0(data, 4, 8, 1)
  assert_eq(data[4].to_int(), 10) // R unchanged
  assert_eq(data[5].to_int(), 20) // G unchanged
  assert_eq(data[6].to_int(), 30) // B unchanged
  assert_eq(data[7].to_int(), (40 + 255) & 0xFF) // A += 0xFF -> 39
}

///|
test "predictor mode 1 - left pixel" {
  // pixel0: [10, 20, 30, 40], pixel1: [5, 6, 7, 8]
  // After mode 1: pixel1[c] += pixel0[c]
  let data : FixedArray[Byte] = [10, 20, 30, 40, 5, 6, 7, 8]
  apply_predictor_1(data, 4, 8, 1)
  assert_eq(data[4].to_int(), 15) // 5+10
  assert_eq(data[5].to_int(), 26) // 6+20
  assert_eq(data[6].to_int(), 37) // 7+30
  assert_eq(data[7].to_int(), 48) // 8+40
}

///|
test "predictor mode 2 - top pixel" {
  // width=1, stride=4. pixel0(top): [10,20,30,40], pixel1(bottom): [5,6,7,8]
  let data : FixedArray[Byte] = [10, 20, 30, 40, 5, 6, 7, 8]
  apply_predictor_2(data, 4, 8, 1)
  assert_eq(data[4].to_int(), 15) // 5+10
  assert_eq(data[5].to_int(), 26) // 6+20
  assert_eq(data[6].to_int(), 37) // 7+30
  assert_eq(data[7].to_int(), 48) // 8+40
}

///|
test "predictor mode 6 - average(left, top-left)" {
  // width=2, stride=8
  // Row 0: pixel0=[10,20,30,40], pixel1=[50,60,70,80]
  // Row 1: pixel2=[100,110,120,130], pixel3=[5,6,7,8]
  // For pixel3 (start=12, end=16, width=2):
  //   left = pixel2 = [100,110,120,130]
  //   top-left = pixel0 = [10,20,30,40]
  //   pred[c] = average2(left[c], tl[c])
  //   pred[0] = average2(100, 10) = 55
  //   result[0] = 5 + 55 = 60
  let data : FixedArray[Byte] = [
    10, 20, 30, 40, 50, 60, 70, 80, 100, 110, 120, 130, 5, 6, 7, 8,
  ]
  apply_predictor_6(data, 12, 16, 2)
  assert_eq(data[12].to_int(), 60) // 5 + average2(100,10) = 5+55
  assert_eq(data[13].to_int(), 71) // 6 + average2(110,20) = 6+65
}

///|
test "color_indexing direct (table > 16)" {
  // 17 colors, only first 2 matter
  let table = FixedArray::make(17 * 4, b'\x00')
  // color 0: red
  table[0] = b'\xFF'
  table[3] = b'\xFF'
  // color 1: green
  table[5] = b'\xFF'
  table[7] = b'\xFF'
  // pixel0 index=0, pixel1 index=1 (green channel)
  let data : FixedArray[Byte] = [0, 0, 0, 0, 0, 1, 0, 0]
  apply_color_indexing(data, 2, 1, 17, table)
  // pixel0 should be color0: [255,0,0,255]
  assert_eq(data[0].to_int(), 255) // R
  assert_eq(data[1].to_int(), 0) // G
  assert_eq(data[2].to_int(), 0) // B
  assert_eq(data[3].to_int(), 255) // A
  // pixel1 should be color1: [0,255,0,255]
  assert_eq(data[4].to_int(), 0)
  assert_eq(data[5].to_int(), 255)
  assert_eq(data[6].to_int(), 0)
  assert_eq(data[7].to_int(), 255)
}

///|
test "color_indexing bit-packed (table <= 4)" {
  // table_size=4, bits_per_entry=2, pixels_per_byte=4
  let table : FixedArray[Byte] = [
    10, 20, 30, 255, // color 0
     40, 50, 60, 255, // color 1
     70, 80, 90, 255, // color 2
     100, 110, 120, 255, // color 3
  ]
  // actual width=4, packed_width=ceil(4/4)=1
  // packed green byte encodes 4 indices at 2 bits each
  // indices: [2, 0, 3, 1] -> 2|(0<<2)|(3<<4)|(1<<6) = 2+0+48+64 = 114 = 0x72
  let data = FixedArray::make(16, b'\x00') // 4 pixels * 4 bytes
  data[1] = (0x72).to_byte() // packed green channel
  apply_color_indexing(data, 4, 1, 4, table)
  // pixel 0 should be color 2: [70, 80, 90, 255]
  assert_eq(data[0].to_int(), 70)
  assert_eq(data[1].to_int(), 80)
  assert_eq(data[2].to_int(), 90)
  assert_eq(data[3].to_int(), 255)
  // pixel 1 should be color 0: [10, 20, 30, 255]
  assert_eq(data[4].to_int(), 10)
  assert_eq(data[5].to_int(), 20)
  // pixel 2 should be color 3: [100, 110, 120, 255]
  assert_eq(data[8].to_int(), 100)
  assert_eq(data[9].to_int(), 110)
  // pixel 3 should be color 1: [40, 50, 60, 255]
  assert_eq(data[12].to_int(), 40)
  assert_eq(data[13].to_int(), 50)
}

///|
test "color_indexing out of bounds index" {
  // table has 17 entries, but pixel references index 20 (out of bounds -> zeroed)
  let table = FixedArray::make(17 * 4, b'\xFF')
  let data : FixedArray[Byte] = [0, 20, 0, 0] // index=20, out of bounds
  apply_color_indexing(data, 1, 1, 17, table)
  assert_eq(data[0].to_int(), 0)
  assert_eq(data[1].to_int(), 0)
  assert_eq(data[2].to_int(), 0)
  assert_eq(data[3].to_int(), 0)
}

///|
test "color_transform_delta basic" {
  // t=1, c=32 -> 1*32 = 32, unsigned >> 5 = 1
  assert_eq(color_transform_delta(1, 32), 1)
  // t=-1, c=32 -> -1*32 = -32, as u32 = 0xFFFFFFE0, >> 5 = 0x07FFFFFF
  let result = color_transform_delta(-1, 32)
  assert_eq(result, 0x07FFFFFF)
}

///|
test "to_signed_byte" {
  assert_eq(to_signed_byte(0), 0)
  assert_eq(to_signed_byte(127), 127)
  assert_eq(to_signed_byte(128), -128)
  assert_eq(to_signed_byte(255), -1)
  assert_eq(to_signed_byte(256), 0) // wraps via & 0xFF
}

///|
test "color_transform only touches the given rows" {
  // 1x1 image in a buffer that has room for 2 rows, as after color indexing
  // packs the width. green_to_red = 1, green = 32 -> red += 1
  let data : FixedArray[Byte] = [0, 32, 0, 0, 0, 32, 0, 0]
  let transform : FixedArray[Byte] = [0, 0, 1, 0]
  apply_color_transform(data, 1, 1, 2, transform)
  assert_eq(data[0].to_int(), 1)
  assert_eq(data[4].to_int(), 0) // second row is outside the image
}

///|
test "subtract_green stops at num_pixels" {
  let data : FixedArray[Byte] = [10, 20, 30, 255, 100, 50, 200, 128]
  apply_subtract_green(data, 1)
  assert_eq(data[0].to_int(), 30) // 10+20
  assert_eq(data[4].to_int(), 100) // outside the image
}

///|
test "predictor modes 14 and 15 behave as mode 0 like libwebp" {
  for mode in [14, 15] {
    // 2x2 image of zero residuals; only pixel (1, 1) uses the block's mode
    let data = FixedArray::make(16, b'\x00')
    let predictor : FixedArray[Byte] = [0, mode.to_byte(), 0, 0]
    apply_predictor_transform(data, 2, 2, 2, predictor)
    assert_eq(data[15].to_int(), 255)
  }
}

///|
test "predictor mode uses only the low 4 bits like libwebp" {
  // mode 17 & 0xF = 1 (left pixel); red of pixel (0, 0) is 10
  let data = FixedArray::make(16, b'\x00')
  data[0] = b'\x0A'
  let predictor : FixedArray[Byte] = [0, 17, 0, 0]
  apply_predictor_transform(data, 2, 2, 2, predictor)
  assert_eq(data[12].to_int(), 10)
}
