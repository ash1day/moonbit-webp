///|
pub fn apply_subtract_green(image_data : FixedArray[Byte]) -> Unit {
  let len = image_data.length()
  let mut i = 0
  while i + 3 < len {
    let g = image_data[i + 1]
    image_data[i] = image_data[i] + g
    image_data[i + 2] = image_data[i + 2] + g
    i += 4
  }
}
