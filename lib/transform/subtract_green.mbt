///|
pub fn apply_subtract_green(
  image_data : FixedArray[Byte],
  num_pixels : Int32,
) -> Unit {
  for i = 0; i < num_pixels * 4; i = i + 4 {
    let g = image_data[i + 1]
    image_data[i] = image_data[i] + g
    image_data[i + 2] = image_data[i + 2] + g
  }
}
