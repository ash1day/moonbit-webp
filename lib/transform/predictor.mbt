///|
fn average2(a : Byte, b : Byte) -> Byte {
  ((a.to_int() + b.to_int()) / 2).to_byte()
}

///|
fn clamp_add_subtract_full(a : Int, b : Int, c : Int) -> Byte {
  let v = a + b - c
  (if v < 0 { 0 } else if v > 255 { 255 } else { v }).to_byte()
}

///|
fn clamp_add_subtract_half(a : Int, b : Int) -> Byte {
  let v = a + (a - b) / 2
  (if v < 0 { 0 } else if v > 255 { 255 } else { v }).to_byte()
}

///|
pub fn apply_predictor_transform(
  image_data : FixedArray[Byte],
  width : Int,
  height : Int,
  size_bits : Int,
  predictor_data : FixedArray[Byte]
) -> Unit {
  let block_xsize = subsample_size(width, size_bits)
  // Top-left pixel: add 0xFF to alpha channel
  image_data[3] = image_data[3] + b'\xFF'
  // First row: predictor mode 1 (left pixel)
  apply_predictor_1(image_data, 4, width * 4, width)
  // Left column: predictor mode 2 (top pixel) for first pixel of each row
  for y = 1; y < height; y = y + 1 {
    for i = 0; i < 4; i = i + 1 {
      let idx = y * width * 4 + i
      image_data[idx] = image_data[idx] + image_data[(y - 1) * width * 4 + i]
    }
  }
  // Interior pixels: use predictor mode from predictor_data
  for y = 1; y < height; y = y + 1 {
    for block_x = 0; block_x < block_xsize; block_x = block_x + 1 {
      let block_index = (y >> size_bits) * block_xsize + block_x
      let predictor = predictor_data[block_index * 4 + 1].to_int() // green channel holds mode
      let shifted = block_x << size_bits
      let start_x = if shifted < 1 { 1 } else { shifted }
      let end_shifted = (block_x + 1) << size_bits
      let end_x = if end_shifted < width { end_shifted } else { width }
      let start = (y * width + start_x) * 4
      let end = (y * width + end_x) * 4
      match predictor {
        0 => apply_predictor_0(image_data, start, end, width)
        1 => apply_predictor_1(image_data, start, end, width)
        2 => apply_predictor_2(image_data, start, end, width)
        3 => apply_predictor_3(image_data, start, end, width)
        4 => apply_predictor_4(image_data, start, end, width)
        5 => apply_predictor_5(image_data, start, end, width)
        6 => apply_predictor_6(image_data, start, end, width)
        7 => apply_predictor_7(image_data, start, end, width)
        8 => apply_predictor_8(image_data, start, end, width)
        9 => apply_predictor_9(image_data, start, end, width)
        10 => apply_predictor_10(image_data, start, end, width)
        11 => apply_predictor_11(image_data, start, end, width)
        12 => apply_predictor_12(image_data, start, end, width)
        13 => apply_predictor_13(image_data, start, end, width)
        _ => ()
      }
    }
  }
}

// Mode 0: add 0xFF to alpha channel only
///|
fn apply_predictor_0(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  _width : Int
) -> Unit {
  let mut i = start + 3
  while i < end {
    data[i] = data[i] + b'\xFF'
    i += 4
  }
}

// Mode 1: add left pixel
///|
fn apply_predictor_1(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  _width : Int
) -> Unit {
  let mut i = start
  while i < end {
    data[i] = data[i] + data[i - 4]
    i += 1
  }
}

// Mode 2: add top pixel
///|
fn apply_predictor_2(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let mut i = start
  while i < end {
    data[i] = data[i] + data[i - stride]
    i += 1
  }
}

// Mode 3: add top-right pixel
///|
fn apply_predictor_3(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let mut i = start
  while i < end {
    data[i] = data[i] + data[i - stride + 4]
    i += 1
  }
}

// Mode 4: add top-left pixel
///|
fn apply_predictor_4(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let mut i = start
  while i < end {
    data[i] = data[i] + data[i - stride - 4]
    i += 1
  }
}

// Mode 5: average(average(left, top-right), top)
///|
fn apply_predictor_5(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let prev = FixedArray::make(4, b'\x00')
  prev[0] = data[start - 4]
  prev[1] = data[start - 3]
  prev[2] = data[start - 2]
  prev[3] = data[start - 1]
  let mut i = start
  while i < end {
    for c = 0; c < 4; c = c + 1 {
      let tr = data[i + c - stride + 4]
      let t = data[i + c - stride]
      let predicted = average2(average2(prev[c], tr), t)
      let result = data[i + c] + predicted
      data[i + c] = result
      prev[c] = result
    }
    i += 4
  }
}

// Mode 6: average(left, top-left)
///|
fn apply_predictor_6(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let mut i = start
  while i < end {
    data[i] = data[i] + average2(data[i - 4], data[i - stride - 4])
    i += 1
  }
}

// Mode 7: average(left, top)
///|
fn apply_predictor_7(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let prev = FixedArray::make(4, b'\x00')
  prev[0] = data[start - 4]
  prev[1] = data[start - 3]
  prev[2] = data[start - 2]
  prev[3] = data[start - 1]
  let mut i = start
  while i < end {
    for c = 0; c < 4; c = c + 1 {
      let t = data[i + c - stride]
      let predicted = average2(prev[c], t)
      let result = data[i + c] + predicted
      data[i + c] = result
      prev[c] = result
    }
    i += 4
  }
}

// Mode 8: average(top-left, top)
///|
fn apply_predictor_8(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let mut i = start
  while i < end {
    data[i] = data[i] + average2(data[i - stride - 4], data[i - stride])
    i += 1
  }
}

// Mode 9: average(top, top-right)
///|
fn apply_predictor_9(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let mut i = start
  while i < end {
    data[i] = data[i] + average2(data[i - stride], data[i - stride + 4])
    i += 1
  }
}

// Mode 10: average(average(left, top-left), average(top, top-right))
///|
fn apply_predictor_10(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let prev = FixedArray::make(4, b'\x00')
  prev[0] = data[start - 4]
  prev[1] = data[start - 3]
  prev[2] = data[start - 2]
  prev[3] = data[start - 1]
  let mut i = start
  while i < end {
    for c = 0; c < 4; c = c + 1 {
      let tl = data[i + c - stride - 4]
      let t = data[i + c - stride]
      let tr = data[i + c - stride + 4]
      let predicted = average2(average2(prev[c], tl), average2(t, tr))
      let result = data[i + c] + predicted
      data[i + c] = result
      prev[c] = result
    }
    i += 4
  }
}

// Mode 11: select(left, top) based on gradient prediction
///|
fn apply_predictor_11(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let l = FixedArray::make(4, 0)
  l[0] = data[start - 4].to_int()
  l[1] = data[start - 3].to_int()
  l[2] = data[start - 2].to_int()
  l[3] = data[start - 1].to_int()
  let tl = FixedArray::make(4, 0)
  tl[0] = data[start - stride - 4].to_int()
  tl[1] = data[start - stride - 3].to_int()
  tl[2] = data[start - stride - 2].to_int()
  tl[3] = data[start - stride - 1].to_int()
  let mut i = start
  while i < end {
    let t = FixedArray::make(4, 0)
    t[0] = data[i - stride].to_int()
    t[1] = data[i - stride + 1].to_int()
    t[2] = data[i - stride + 2].to_int()
    t[3] = data[i - stride + 3].to_int()
    let mut predict_left = 0
    let mut predict_top = 0
    for c = 0; c < 4; c = c + 1 {
      let predict = l[c] + t[c] - tl[c]
      let diff_left = predict - l[c]
      let diff_top = predict - t[c]
      predict_left += (if diff_left < 0 { -diff_left } else { diff_left })
      predict_top += (if diff_top < 0 { -diff_top } else { diff_top })
    }
    if predict_left < predict_top {
      for c = 0; c < 4; c = c + 1 {
        let result = (data[i + c].to_int() + l[c]) & 0xFF
        data[i + c] = result.to_byte()
        l[c] = result
      }
    } else {
      for c = 0; c < 4; c = c + 1 {
        let result = (data[i + c].to_int() + t[c]) & 0xFF
        data[i + c] = result.to_byte()
        l[c] = result
      }
    }
    tl[0] = t[0]
    tl[1] = t[1]
    tl[2] = t[2]
    tl[3] = t[3]
    i += 4
  }
}

// Mode 12: clamp_add_subtract_full(left, top, top-left)
///|
fn apply_predictor_12(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let prev = FixedArray::make(4, b'\x00')
  prev[0] = data[start - 4]
  prev[1] = data[start - 3]
  prev[2] = data[start - 2]
  prev[3] = data[start - 1]
  let mut i = start
  while i < end {
    for c = 0; c < 4; c = c + 1 {
      let tl = data[i + c - stride - 4]
      let t = data[i + c - stride]
      let predicted = clamp_add_subtract_full(
        prev[c].to_int(),
        t.to_int(),
        tl.to_int(),
      )
      let result = data[i + c] + predicted
      data[i + c] = result
      prev[c] = result
    }
    i += 4
  }
}

// Mode 13: clamp_add_subtract_half(average(left, top), top-left)
///|
fn apply_predictor_13(
  data : FixedArray[Byte],
  start : Int,
  end : Int,
  width : Int
) -> Unit {
  let stride = width * 4
  let prev = FixedArray::make(4, b'\x00')
  prev[0] = data[start - 4]
  prev[1] = data[start - 3]
  prev[2] = data[start - 2]
  prev[3] = data[start - 1]
  let mut i = start
  while i < end {
    for c = 0; c < 4; c = c + 1 {
      let tl = data[i + c - stride - 4]
      let t = data[i + c - stride]
      let avg = (prev[c].to_int() + t.to_int()) / 2
      let predicted = clamp_add_subtract_half(avg, tl.to_int())
      let result = data[i + c] + predicted
      data[i + c] = result
      prev[c] = result
    }
    i += 4
  }
}
