///|
priv struct LosslessDecoder {
  br : @bitreader.BitReader
  transforms : FixedArray[@transform.TransformType?]
  transform_order : Array[Int32]
  width : Int32
  height : Int32
}

///|
fn LosslessDecoder::new(
  br : @bitreader.BitReader,
  width : Int32,
  height : Int32,
) -> LosslessDecoder {
  {
    br,
    transforms: FixedArray::make(4, None),
    transform_order: [],
    width,
    height,
  }
}

// Helper: wrap BitReader.read_bits to DecodeError

///|
fn read_bits(br : @bitreader.BitReader, n : Int32) -> Int32 raise DecodeError {
  br.read_bits(n) catch {
    @bitreader.BitReaderError(msg) => raise Invalid(msg)
  }
}

// Helper: wrap HuffmanTree.read_symbol to DecodeError

///|
fn read_symbol(
  tree : @huffman.HuffmanTree,
  br : @bitreader.BitReader,
) -> Int32 raise DecodeError {
  tree.read_symbol(br) catch {
    @bitreader.BitReaderError(msg) => raise Invalid(msg)
  }
}

// Helper: wrap HuffmanTree.build_implicit to DecodeError

///|
fn build_huffman(
  code_lengths : FixedArray[Int32],
) -> @huffman.HuffmanTree raise DecodeError {
  @huffman.HuffmanTree::build_implicit(code_lengths) catch {
    @huffman.HuffmanError(msg) => raise Invalid(msg)
  }
}

///|
fn LosslessDecoder::read_transforms(
  self : LosslessDecoder,
) -> Int32 raise DecodeError {
  let mut xsize = self.width
  while read_bits(self.br, 1) == 1 {
    let transform_type_val = read_bits(self.br, 2)
    if self.transforms[transform_type_val] is Some(_) {
      raise Invalid("duplicate transform type")
    }
    self.transform_order.push(transform_type_val)
    let transform = match transform_type_val {
      0 => {
        let size_bits = read_bits(self.br, 3) + 2
        let block_xsize = @transform.subsample_size(xsize, size_bits)
        let block_ysize = @transform.subsample_size(self.height, size_bits)
        let predictor_data = FixedArray::make(
          block_xsize * block_ysize * 4,
          b'\x00',
        )
        self.decode_image_stream(
          block_xsize, block_ysize, false, predictor_data,
        )
        @transform.TransformType::PredictorTransform(
          size_bits~,
          data=predictor_data,
        )
      }
      1 => {
        let size_bits = read_bits(self.br, 3) + 2
        let block_xsize = @transform.subsample_size(xsize, size_bits)
        let block_ysize = @transform.subsample_size(self.height, size_bits)
        let transform_data = FixedArray::make(
          block_xsize * block_ysize * 4,
          b'\x00',
        )
        self.decode_image_stream(
          block_xsize, block_ysize, false, transform_data,
        )
        @transform.TransformType::ColorTransform(
          size_bits~,
          data=transform_data,
        )
      }
      2 => @transform.TransformType::SubtractGreen
      3 => {
        let color_table_size = read_bits(self.br, 8) + 1
        let color_map = FixedArray::make(color_table_size * 4, b'\x00')
        self.decode_image_stream(color_table_size, 1, false, color_map)
        adjust_color_map(color_map)
        let bits = if color_table_size <= 2 {
          3
        } else if color_table_size <= 4 {
          2
        } else if color_table_size <= 16 {
          1
        } else {
          0
        }
        xsize = @transform.subsample_size(xsize, bits)
        @transform.TransformType::ColorIndexingTransform(
          table_size=color_table_size,
          data=color_map,
        )
      }
      _ => raise Invalid("invalid transform type")
    }
    self.transforms[transform_type_val] = Some(transform)
  }
  xsize
}

///|
fn adjust_color_map(color_map : FixedArray[Byte]) -> Unit {
  for i = 4; i < color_map.length(); i = i + 1 {
    color_map[i] = color_map[i] + color_map[i - 4]
  }
}

///|
fn LosslessDecoder::decode_image_stream(
  self : LosslessDecoder,
  xsize : Int32,
  ysize : Int32,
  is_argb_img : Bool,
  data : FixedArray[Byte],
) -> Unit raise DecodeError {
  let color_cache_bits = self.read_color_cache()
  let color_cache : ColorCache? = match color_cache_bits {
    Some(bits) => Some({ bits, data: FixedArray::make(1 << bits, 0), })
    None => None
  }
  let huffman_info = self.read_huffman_codes(
    is_argb_img, xsize, ysize, color_cache,
  )
  self.decode_image_data(xsize, ysize, huffman_info, data)
}

///|
fn LosslessDecoder::read_color_cache(
  self : LosslessDecoder,
) -> Int32? raise DecodeError {
  if read_bits(self.br, 1) == 1 {
    let code_bits = read_bits(self.br, 4)
    if code_bits < 1 || code_bits > 11 {
      raise Invalid("invalid color cache bits: \{code_bits}")
    }
    Some(code_bits)
  } else {
    None
  }
}

///|
fn LosslessDecoder::read_huffman_codes(
  self : LosslessDecoder,
  read_meta : Bool,
  xsize : Int32,
  ysize : Int32,
  color_cache : ColorCache?,
) -> HuffmanInfo raise DecodeError {
  let mut num_huff_groups = 1
  let mut huffman_bits = 0
  let mut huffman_xsize = 1
  let mut huffman_ysize = 1
  let mut entropy_image : FixedArray[Int32] = FixedArray::make(0, 0)
  if read_meta && read_bits(self.br, 1) == 1 {
    huffman_bits = read_bits(self.br, 3) + 2
    huffman_xsize = @transform.subsample_size(xsize, huffman_bits)
    huffman_ysize = @transform.subsample_size(ysize, huffman_bits)
    let meta_data = FixedArray::make(huffman_xsize * huffman_ysize * 4, b'\x00')
    self.decode_image_stream(huffman_xsize, huffman_ysize, false, meta_data)
    entropy_image = FixedArray::make(huffman_xsize * huffman_ysize, 0)
    for i = 0; i < entropy_image.length(); i = i + 1 {
      let meta_huff_code = (meta_data[i * 4].to_int() << 8) |
        meta_data[i * 4 + 1].to_int()
      if meta_huff_code >= num_huff_groups {
        num_huff_groups = meta_huff_code + 1
      }
      entropy_image[i] = meta_huff_code
    }
  }
  // Like libwebp, keep only the groups the entropy image refers to, renumbered
  // in order of first use. Unused groups are still read from the bitstream
  // but dropped, so a tiny image cannot make the decoder hold 65536 groups.
  let mapping = FixedArray::make(num_huff_groups, -1)
  let mut num_used = 0
  if entropy_image.length() == 0 {
    mapping[0] = 0
    num_used = 1
  }
  for i = 0; i < entropy_image.length(); i = i + 1 {
    let group = entropy_image[i]
    if mapping[group] < 0 {
      mapping[group] = num_used
      num_used += 1
    }
    entropy_image[i] = mapping[group]
  }
  let hufftree_groups : Array[FixedArray[@huffman.HuffmanTree]] = Array::make(
    num_used,
    [],
  )
  for i = 0; i < num_huff_groups; i = i + 1 {
    let group = FixedArray::make(
      huffman_codes_per_meta_code,
      @huffman.HuffmanTree::build_single(0),
    )
    for j = 0; j < huffman_codes_per_meta_code; j = j + 1 {
      let mut alpha_size = alphabet_size[j]
      if j == 0 {
        match color_cache {
          Some(cc) => alpha_size = alpha_size + (1 << cc.bits)
          None => ()
        }
      }
      group[j] = self.read_huffman_code(alpha_size, keep=mapping[i] >= 0)
    }
    if mapping[i] >= 0 {
      hufftree_groups[mapping[i]] = group
    }
  }
  let huffman_mask = if huffman_bits == 0 {
    0x7FFF_FFFF
  } else {
    (1 << huffman_bits) - 1
  }
  {
    xsize: huffman_xsize,
    color_cache,
    image: entropy_image,
    bits: huffman_bits,
    mask: huffman_mask,
    huffman_code_groups: hufftree_groups,
  }
}

///|
fn LosslessDecoder::read_huffman_code(
  self : LosslessDecoder,
  alphabet_size : Int32,
  keep~ : Bool = true,
) -> @huffman.HuffmanTree raise DecodeError {
  let simple = read_bits(self.br, 1) == 1
  if simple {
    let num_symbols = read_bits(self.br, 1) + 1
    let is_first_8bits = read_bits(self.br, 1)
    let zero_symbol = read_bits(self.br, 1 + 7 * is_first_8bits)
    if zero_symbol >= alphabet_size {
      raise Invalid("simple huffman symbol out of range")
    }
    if num_symbols == 1 {
      @huffman.HuffmanTree::build_single(zero_symbol)
    } else {
      let one_symbol = read_bits(self.br, 8)
      if one_symbol >= alphabet_size {
        raise Invalid("simple huffman symbol out of range")
      }
      @huffman.HuffmanTree::build_two(zero_symbol, one_symbol)
    }
  } else {
    let code_length_code_lengths = FixedArray::make(code_length_codes, 0)
    let num_code_lengths = 4 + read_bits(self.br, 4)
    for i = 0; i < num_code_lengths; i = i + 1 {
      code_length_code_lengths[code_length_code_order[i]] = read_bits(
        self.br,
        3,
      )
    }
    let new_code_lengths = self.read_huffman_code_lengths(
      code_length_code_lengths, alphabet_size,
    )
    if keep {
      build_huffman(new_code_lengths)
    } else {
      // an unused group: check the code like libwebp, but build no table
      @huffman.validate_code_lengths(new_code_lengths) catch {
        @huffman.HuffmanError(msg) => raise Invalid(msg)
      }
      @huffman.HuffmanTree::build_single(0)
    }
  }
}

///|
fn LosslessDecoder::read_huffman_code_lengths(
  self : LosslessDecoder,
  code_length_code_lengths : FixedArray[Int32],
  num_symbols : Int32,
) -> FixedArray[Int32] raise DecodeError {
  let table = build_huffman(code_length_code_lengths)
  let mut max_symbol = if read_bits(self.br, 1) == 1 {
    let length_nbits = 2 + 2 * read_bits(self.br, 3)
    let max_minus_two = read_bits(self.br, length_nbits)
    if max_minus_two > num_symbols - 2 {
      raise Invalid("max_symbol too large")
    }
    2 + max_minus_two
  } else {
    num_symbols
  }
  let code_lengths = FixedArray::make(num_symbols, 0)
  let mut prev_code_len = 8
  let mut symbol = 0
  while symbol < num_symbols {
    if max_symbol == 0 {
      break
    }
    max_symbol -= 1
    self.br.fill()
    let code_len = read_symbol(table, self.br)
    if code_len < 16 {
      code_lengths[symbol] = code_len
      symbol += 1
      if code_len != 0 {
        prev_code_len = code_len
      }
    } else {
      let use_prev = code_len == 16
      let slot = code_len - 16
      let extra_bits = match slot {
        0 => 2
        1 => 3
        2 => 7
        _ => raise Invalid("invalid code length code")
      }
      let repeat_offset = match slot {
        0 | 1 => 3
        2 => 11
        _ => raise Invalid("invalid code length code")
      }
      let mut repeat = read_bits(self.br, extra_bits) + repeat_offset
      if symbol + repeat > num_symbols {
        raise Invalid("code length repeat overflow")
      }
      let length = if use_prev { prev_code_len } else { 0 }
      while repeat > 0 {
        repeat -= 1
        code_lengths[symbol] = length
        symbol += 1
      }
    }
  }
  code_lengths
}

///|
fn get_huff_index(info : HuffmanInfo, x : Int32, y : Int32) -> Int32 {
  if info.bits == 0 {
    return 0
  }
  let position = (y >> info.bits) * info.xsize + (x >> info.bits)
  info.image[position]
}

///|
fn LosslessDecoder::decode_image_data(
  self : LosslessDecoder,
  width : Int32,
  height : Int32,
  huffman_info : HuffmanInfo,
  data : FixedArray[Byte],
) -> Unit raise DecodeError {
  let num_values = width * height
  let huff_index = get_huff_index(huffman_info, 0, 0)
  let mut tree = huffman_info.huffman_code_groups[huff_index]
  let mut index = 0
  let mut next_block_start = 0
  while index < num_values {
    self.br.fill()
    if index >= next_block_start {
      let x = index % width
      let y = index / width
      let mask_end = x | huffman_info.mask
      next_block_start = (if mask_end < width - 1 {
          mask_end
        } else {
          width - 1
        }) +
        y * width +
        1
      let huff_index = get_huff_index(huffman_info, x, y)
      tree = huffman_info.huffman_code_groups[huff_index]
      // Fast path: if all color codes are single-node
      if tree[0].is_single_node() &&
        tree[1].is_single_node() &&
        tree[2].is_single_node() &&
        tree[3].is_single_node() {
        let code = read_symbol(tree[green], self.br)
        if code < 256 {
          let n = if huffman_info.bits == 0 {
            num_values - index
          } else {
            next_block_start - index
          }
          let red_val = read_symbol(tree[red], self.br)
          let blue_val = read_symbol(tree[blue], self.br)
          let alpha_val = read_symbol(tree[alpha], self.br)
          let rv = red_val.to_byte()
          let gv = code.to_byte()
          let bv = blue_val.to_byte()
          let av = alpha_val.to_byte()
          for i = 0; i < n; i = i + 1 {
            data[(index + i) * 4] = rv
            data[(index + i) * 4 + 1] = gv
            data[(index + i) * 4 + 2] = bv
            data[(index + i) * 4 + 3] = av
          }
          match huffman_info.color_cache {
            Some(cc) => color_cache_insert(cc, data, index * 4)
            None => ()
          }
          index += n
          continue
        }
      }
    }
    let code = read_symbol(tree[green], self.br)
    if code < 256 {
      let green_val = code.to_byte()
      let red_val = read_symbol(tree[red], self.br).to_byte()
      let blue_val = read_symbol(tree[blue], self.br).to_byte()
      if self.br.nbits < 15 {
        self.br.fill()
      }
      let alpha_val = read_symbol(tree[alpha], self.br).to_byte()
      data[index * 4] = red_val
      data[index * 4 + 1] = green_val
      data[index * 4 + 2] = blue_val
      data[index * 4 + 3] = alpha_val
      match huffman_info.color_cache {
        Some(cc) => color_cache_insert(cc, data, index * 4)
        None => ()
      }
      index += 1
    } else if code < 256 + 24 {
      let length_symbol = code - 256
      let length = get_copy_distance(self.br, length_symbol)
      let dist_symbol = read_symbol(tree[dist], self.br)
      let dist_code = get_copy_distance(self.br, dist_symbol)
      let distance = plane_code_to_distance(width, dist_code)
      if index < distance || num_values - index < length {
        raise Invalid("backward reference out of bounds")
      }
      if distance == 1 {
        let src = (index - distance) * 4
        let rv = data[src]
        let gv = data[src + 1]
        let bv = data[src + 2]
        let av = data[src + 3]
        for i = 0; i < length; i = i + 1 {
          data[(index + i) * 4] = rv
          data[(index + i) * 4 + 1] = gv
          data[(index + i) * 4 + 2] = bv
          data[(index + i) * 4 + 3] = av
        }
      } else {
        for i = 0; i < length * 4; i = i + 1 {
          data[index * 4 + i] = data[index * 4 + i - distance * 4]
        }
      }
      match huffman_info.color_cache {
        Some(cc) =>
          for i = 0; i < length; i = i + 1 {
            color_cache_insert(cc, data, (index + i) * 4)
          }
        None => ()
      }
      index += length
    } else {
      let cc = match huffman_info.color_cache {
        Some(cc) => cc
        None => raise Invalid("color cache code without color cache")
      }
      let cache_index = code - 280
      let argb = cc.data[cache_index]
      data[index * 4] = (argb >> 16).to_byte()
      data[index * 4 + 1] = (argb >> 8).to_byte()
      data[index * 4 + 2] = argb.to_byte()
      data[index * 4 + 3] = (argb >> 24).to_byte()
      index += 1
    }
  }
}

///|
fn color_cache_insert(
  cc : ColorCache,
  rgba : FixedArray[Byte],
  offset : Int32,
) -> Unit {
  let argb = (rgba[offset + 3].to_int() << 24) |
    (rgba[offset].to_int() << 16) |
    (rgba[offset + 1].to_int() << 8) |
    rgba[offset + 2].to_int()
  let hash = (0x1E35A7BD * argb).reinterpret_as_uint() >> (32 - cc.bits)
  cc.data[hash.reinterpret_as_int()] = argb
}

///|
fn get_copy_distance(
  br : @bitreader.BitReader,
  prefix_code : Int32,
) -> Int32 raise DecodeError {
  if prefix_code < 4 {
    return prefix_code + 1
  }
  let extra_bits = (prefix_code - 2) >> 1
  let offset = (2 + (prefix_code & 1)) << extra_bits
  offset + read_bits(br, extra_bits) + 1
}

///|
fn plane_code_to_distance(xsize : Int32, plane_code : Int32) -> Int32 {
  if plane_code > 120 {
    plane_code - 120
  } else {
    let (xoffset, yoffset) = distance_map[plane_code - 1]
    let d = xoffset + yoffset * xsize
    if d < 1 {
      1
    } else {
      d
    }
  }
}
