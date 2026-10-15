///|
pub fn apply_color_indexing(
  image_data : FixedArray[Byte],
  width : Int32,
  height : Int32,
  table_size : Int32,
  table_data : FixedArray[Byte],
) -> Unit {
  if table_size > 16 {
    // Simple case: each green channel value is a direct index
    let len = image_data.length()
    let mut i = 0
    while i + 3 < len {
      let index = image_data[i + 1].to_int() // green channel
      if index < table_size {
        let t = index * 4
        image_data[i] = table_data[t]
        image_data[i + 1] = table_data[t + 1]
        image_data[i + 2] = table_data[t + 2]
        image_data[i + 3] = table_data[t + 3]
      } else {
        image_data[i] = b'\x00'
        image_data[i + 1] = b'\x00'
        image_data[i + 2] = b'\x00'
        image_data[i + 3] = b'\x00'
      }
      i += 4
    }
  } else {
    // Bit-packed case
    let (w_bits, bits_per_entry) = if table_size <= 2 {
      (3, 1) // 8 pixels per byte, 1 bit each
    } else if table_size <= 4 {
      (2, 2) // 4 pixels per byte, 2 bits each
    } else {
      (1, 4) // 2 pixels per byte, 4 bits each
    }
    let pixels_per_byte = 1 << w_bits
    let mask = (1 << bits_per_entry) - 1
    let packed_width = subsample_size(width, w_bits)
    // Process rows from bottom to top (expanding in-place)
    let mut y = height - 1
    while y >= 0 {
      // Read packed indices for this row
      let packed_row_start = y * packed_width * 4
      // First collect the packed green channel values
      let packed_indices = FixedArray::make(packed_width, b'\x00')
      for bx = 0; bx < packed_width; bx = bx + 1 {
        packed_indices[bx] = image_data[packed_row_start + bx * 4 + 1]
      }
      // Expand from right to left to avoid overwriting
      let output_row_start = y * width * 4
      let mut x = width - 1
      while x >= 0 {
        let packed_x = x / pixels_per_byte
        let sub_index = x % pixels_per_byte
        let packed_val = packed_indices[packed_x].to_int()
        let index = (packed_val >> (sub_index * bits_per_entry)) & mask
        let dst = output_row_start + x * 4
        if index < table_size {
          let src = index * 4
          image_data[dst] = table_data[src]
          image_data[dst + 1] = table_data[src + 1]
          image_data[dst + 2] = table_data[src + 2]
          image_data[dst + 3] = table_data[src + 3]
        } else {
          image_data[dst] = b'\x00'
          image_data[dst + 1] = b'\x00'
          image_data[dst + 2] = b'\x00'
          image_data[dst + 3] = b'\x00'
        }
        x -= 1
      }
      y -= 1
    }
  }
}
