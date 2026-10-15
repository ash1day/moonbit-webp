///|
fn to_signed_byte(v : Int32) -> Int32 {
  let b = v & 0xFF
  if b >= 128 {
    b - 256
  } else {
    b
  }
}

///|
fn color_transform_delta(t : Int32, c : Int32) -> Int32 {
  // Rust: (i32::from(t) * i32::from(c)) as u32 >> 5
  // t and c are sign-extended i8 values (-128..127)
  // Multiply as signed, cast to unsigned, then logical shift right by 5
  let product = t * c
  (product.reinterpret_as_uint() >> 5).reinterpret_as_int()
}

///|
pub fn apply_color_transform(
  image_data : FixedArray[Byte],
  width : Int32,
  size_bits : Int32,
  transform_data : FixedArray[Byte],
) -> Unit {
  let block_xsize = subsample_size(width, size_bits)
  let height = image_data.length() / (width * 4)
  let mut y = 0
  while y < height {
    let row_start = y * width * 4
    let tf_row_start = (y >> size_bits) * block_xsize * 4
    let mut block_x = 0
    while block_x < block_xsize {
      let tf_offset = tf_row_start + block_x * 4
      let red_to_blue = transform_data[tf_offset].to_int()
      let green_to_blue = transform_data[tf_offset + 1].to_int()
      let green_to_red = transform_data[tf_offset + 2].to_int()
      let pixel_start = row_start + (block_x << size_bits) * 4
      let end_x = (block_x + 1) << size_bits
      let clamped_end_x = if end_x < width { end_x } else { width }
      let pixel_end = row_start + clamped_end_x * 4
      let mut p = pixel_start
      while p < pixel_end {
        let green = image_data[p + 1].to_int()
        let mut temp_red = image_data[p].to_int()
        let mut temp_blue = image_data[p + 2].to_int()
        temp_red = temp_red +
          color_transform_delta(
            to_signed_byte(green_to_red),
            to_signed_byte(green),
          )
        temp_blue = temp_blue +
          color_transform_delta(
            to_signed_byte(green_to_blue),
            to_signed_byte(green),
          )
        temp_blue = temp_blue +
          color_transform_delta(
            to_signed_byte(red_to_blue),
            to_signed_byte(temp_red),
          )
        image_data[p] = (temp_red & 0xFF).to_byte()
        image_data[p + 2] = (temp_blue & 0xFF).to_byte()
        p += 4
      }
      block_x += 1
    }
    y += 1
  }
}
