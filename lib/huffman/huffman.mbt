///|
pub(all) suberror HuffmanError {
  HuffmanError(String)
}

///|
let max_allowed_code_length : Int32 = 15

///|
let max_table_bits : Int32 = 10

///|
priv enum HuffmanTreeInner {
  Single(Int32)
  Tree(
    table_mask~ : Int32,
    primary~ : FixedArray[Int32],
    secondary~ : FixedArray[Int32]
  )
}

///|
pub struct HuffmanTree {
  priv inner : HuffmanTreeInner
}

///|
fn next_codeword(codeword : Int32, table_size : Int32) -> Int32 {
  if codeword == table_size - 1 {
    return codeword
  }
  let xor = codeword ^ (table_size - 1)
  let mut adv = 0
  let mut x = xor
  while x > 1 {
    x = x >> 1
    adv += 1
  }
  let bit = 1 << adv
  (codeword & (bit - 1)) | bit
}

///|
pub fn HuffmanTree::build_single(symbol : Int32) -> HuffmanTree {
  { inner: Single(symbol), }
}

///|
pub fn HuffmanTree::build_two(zero : Int32, one : Int32) -> HuffmanTree {
  let primary = FixedArray::make(2, 0)
  primary[0] = (1 << 12) | zero
  primary[1] = (1 << 12) | one
  { inner: Tree(table_mask=0x1, primary~, secondary=FixedArray::make(0, 0)), }
}

///|
pub fn HuffmanTree::build_implicit(
  code_lengths : FixedArray[Int32],
) -> HuffmanTree raise HuffmanError {
  // Build histogram
  let mut num_symbols = 0
  let histogram = FixedArray::make(max_allowed_code_length + 1, 0)
  for i in 0..<code_lengths.length() {
    let length = code_lengths[i]
    histogram[length] += 1
    if length != 0 {
      num_symbols += 1
    }
  }
  // Special cases
  if num_symbols == 0 {
    raise HuffmanError("no symbols in huffman tree")
  }
  if num_symbols == 1 {
    let mut root_symbol = 0
    for i in 0..<code_lengths.length() {
      if code_lengths[i] != 0 {
        root_symbol = i
        break
      }
    }
    return HuffmanTree::build_single(root_symbol)
  }
  // Determine max code length
  let mut max_length = max_allowed_code_length
  while max_length > 1 && histogram[max_length] == 0 {
    max_length -= 1
  }
  // Compute offsets and validate codespace
  let offsets = FixedArray::make(16, 0)
  let mut codespace_used = 0
  offsets[1] = histogram[0]
  for i in 1..<max_length {
    offsets[i + 1] = offsets[i] + histogram[i]
    codespace_used = (codespace_used << 1) + histogram[i]
  }
  codespace_used = (codespace_used << 1) + histogram[max_length]
  if codespace_used != 1 << max_length {
    raise HuffmanError("invalid huffman codespace")
  }
  // Calculate table parameters
  let table_bits = if max_length < max_table_bits {
    max_length
  } else {
    max_table_bits
  }
  let table_size = 1 << table_bits
  let table_mask = table_size - 1
  let primary = FixedArray::make(table_size, 0)
  // Sort symbols by code length
  let next_index = FixedArray::make(16, 0)
  for i in 0..<16 {
    next_index[i] = offsets[i]
  }
  let sorted_symbols = FixedArray::make(code_lengths.length(), 0)
  for symbol in 0..<code_lengths.length() {
    let length = code_lengths[symbol]
    sorted_symbols[next_index[length]] = symbol
    next_index[length] += 1
  }
  let mut codeword = 0
  let mut si = histogram[0]
  // Populate primary table
  let primary_table_bits = table_bits
  for length in 1..<=primary_table_bits {
    let current_table_end = 1 << length
    for _j in 0..<histogram[length] {
      let symbol = sorted_symbols[si]
      si += 1
      let entry = (length << 12) | symbol
      primary[codeword] = entry
      codeword = next_codeword(codeword, current_table_end)
    }
    if length < primary_table_bits {
      // Double the table
      primary.blit_to(
        primary,
        len=current_table_end,
        src_offset=0,
        dst_offset=current_table_end,
      )
    }
  }
  // Populate secondary table
  let mut secondary = FixedArray::make(0, 0)
  if max_length > primary_table_bits {
    let mut subtable_start = 0
    let mut subtable_prefix = -1
    let mut secondary_len = 0
    for length in (primary_table_bits + 1)..<=max_length {
      let subtable_size = 1 << (length - primary_table_bits)
      for _j in 0..<histogram[length] {
        if (codeword & table_mask) != subtable_prefix {
          subtable_prefix = codeword & table_mask
          subtable_start = secondary_len
          primary[subtable_prefix] = (length << 12) | subtable_start
          // Resize secondary to subtable_start + subtable_size
          let new_len = subtable_start + subtable_size
          if new_len > secondary.length() {
            let new_secondary = FixedArray::make(new_len, 0)
            secondary.blit_to(
              new_secondary,
              len=secondary_len,
              src_offset=0,
              dst_offset=0,
            )
            secondary = new_secondary
          }
          secondary_len = new_len
        }
        let symbol = sorted_symbols[si]
        si += 1
        secondary[subtable_start + (codeword >> primary_table_bits)] = (
            symbol << 4
          ) |
          length
        codeword = next_codeword(codeword, 1 << length)
      }
      // Extend subtable if next length shares same prefix
      if length < max_length && (codeword & table_mask) == subtable_prefix {
        let current_len = secondary_len - subtable_start
        let new_len = secondary_len + current_len
        if new_len > secondary.length() {
          let new_secondary = FixedArray::make(new_len, 0)
          secondary.blit_to(
            new_secondary,
            len=secondary_len,
            src_offset=0,
            dst_offset=0,
          )
          secondary = new_secondary
        }
        secondary.blit_to(
          secondary,
          len=current_len,
          src_offset=subtable_start,
          dst_offset=secondary_len,
        )
        secondary_len = new_len
        primary[subtable_prefix] = ((length + 1) << 12) | subtable_start
      }
    }
    // Trim secondary to actual size
    if secondary_len < secondary.length() {
      let trimmed = FixedArray::make(secondary_len, 0)
      secondary.blit_to(trimmed, len=secondary_len, src_offset=0, dst_offset=0)
      secondary = trimmed
    }
  }
  { inner: Tree(table_mask~, primary~, secondary~), }
}

///|
pub fn HuffmanTree::read_symbol(
  self : HuffmanTree,
  br : @bitreader.BitReader,
) -> Int32 raise @bitreader.BitReaderError {
  match self.inner {
    Single(symbol) => symbol
    Tree(table_mask~, primary~, secondary~) => {
      let v = (br.peek_full() & 0x7FFF_FFFFL).to_int()
      let entry = primary[v & table_mask]
      let length = entry >> 12
      if length <= max_table_bits {
        br.consume(length)
        return entry & 0xFFF
      }
      // Secondary lookup
      let mask = (1 << (length - max_table_bits)) - 1
      let secondary_index = (entry & 0xFFF) + ((v >> max_table_bits) & mask)
      let secondary_entry = secondary[secondary_index]
      br.consume(secondary_entry & 0xF)
      secondary_entry >> 4
    }
  }
}

///|
pub fn HuffmanTree::is_single_node(self : HuffmanTree) -> Bool {
  match self.inner {
    Single(_) => true
    _ => false
  }
}

///|
pub fn HuffmanTree::peek_symbol(
  self : HuffmanTree,
  br : @bitreader.BitReader,
) -> (Int32, Int32)? {
  match self.inner {
    Single(symbol) => Some((0, symbol))
    Tree(table_mask~, primary~, ..) => {
      let v = (br.peek_full() & 0x7FFF_FFFFL).to_int()
      let entry = primary[v & table_mask]
      let length = entry >> 12
      if length <= max_table_bits {
        return Some((length, entry & 0xFFF))
      }
      None
    }
  }
}
