test "build_single always returns same symbol" {
  let tree = HuffmanTree::build_single(42)
  let br = @bitreader.BitReader::new(b"\xFF")
  br.fill()
  assert_eq(tree.read_symbol(br), 42)
  assert_eq(tree.read_symbol(br), 42)
}

test "build_two returns correct symbol based on bit" {
  let tree = HuffmanTree::build_two(5, 10)
  let br = @bitreader.BitReader::new(b"\x02")
  br.fill()
  assert_eq(tree.read_symbol(br), 5)
  assert_eq(tree.read_symbol(br), 10)
  assert_eq(tree.read_symbol(br), 5)
}

test "build_implicit simple codes" {
  // code_lengths: symbol 0->1bit, symbol 1->2bits, symbol 2->3bits, symbol 3->3bits
  // Canonical codes (MSB): 0->0, 1->10, 2->110, 3->111
  //
  // Table is indexed by raw buffer bits (LSB-first from stream):
  //   symbol 0: table indices where bit0=0 -> indices 0,2,4,6
  //   symbol 1: table indices where bit0=1,bit1=0 -> indices 1,5
  //   symbol 2: table index bit0=1,bit1=1,bit2=0 -> index 3
  //   symbol 3: table index bit0=1,bit1=1,bit2=1 -> index 7
  //
  // Encode: symbol2, symbol0, symbol3, symbol1
  //   symbol2: bits 1,1,0 (3 bits)
  //   symbol0: bit  0     (1 bit)
  //   symbol3: bits 1,1,1 (3 bits)
  //   symbol1: bits 1,0   (2 bits)
  // Stream bits: 1,1,0,0,1,1,1,1,0
  // byte0 = 0b11110011 = 0xF3, byte1 = 0b00000000 = 0x00
  let cl = FixedArray::make(4, 0)
  cl[0] = 1
  cl[1] = 2
  cl[2] = 3
  cl[3] = 3
  let tree = HuffmanTree::build_implicit(cl)
  let br = @bitreader.BitReader::new(b"\xF3\x00")
  br.fill()
  assert_eq(tree.read_symbol(br), 2)
  assert_eq(tree.read_symbol(br), 0)
  assert_eq(tree.read_symbol(br), 3)
  assert_eq(tree.read_symbol(br), 1)
}

test "build_implicit rejects all-zero lengths" {
  let cl = FixedArray::make(4, 0)
  let mut errored = false
  try {
    HuffmanTree::build_implicit(cl) |> ignore
  } catch {
    HuffmanError(_) => errored = true
  }
  assert_true(errored)
}

test "is_single_node" {
  assert_true(HuffmanTree::build_single(0).is_single_node())
  assert_false(HuffmanTree::build_two(0, 1).is_single_node())
}
