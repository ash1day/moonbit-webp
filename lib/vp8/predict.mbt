// Intra predictors (RFC 6386 section 12), ported from libwebp src/dsp/dec.c.
// `dst` is the offset of the top-left pixel of the block in a work buffer of
// stride `bps`; the top row, the left column and the top-left sample are read
// from around it.

///|
fn avg2(a : Int32, b : Int32) -> Int32 {
  (a + b + 1) >> 1
}

///|
fn avg3(a : Int32, b : Int32, c : Int32) -> Int32 {
  (a + 2 * b + c + 2) >> 2
}

///|
fn fill_block(
  buf : FixedArray[Int32],
  dst : Int32,
  size : Int32,
  value : Int32,
) -> Unit {
  for y in 0..<size {
    for x in 0..<size {
      buf[dst + x + y * bps] = value
    }
  }
}

///|
fn true_motion(buf : FixedArray[Int32], dst : Int32, size : Int32) -> Unit {
  let top_left = buf[dst - bps - 1]
  for y in 0..<size {
    let left = buf[dst + y * bps - 1]
    for x in 0..<size {
      buf[dst + x + y * bps] = clip_8b(left + buf[dst - bps + x] - top_left)
    }
  }
}

///|
fn vertical(buf : FixedArray[Int32], dst : Int32, size : Int32) -> Unit {
  for y in 0..<size {
    for x in 0..<size {
      buf[dst + x + y * bps] = buf[dst - bps + x]
    }
  }
}

///|
fn horizontal(buf : FixedArray[Int32], dst : Int32, size : Int32) -> Unit {
  for y in 0..<size {
    let left = buf[dst + y * bps - 1]
    for x in 0..<size {
      buf[dst + x + y * bps] = left
    }
  }
}

///|
fn sum_top(buf : FixedArray[Int32], dst : Int32, size : Int32) -> Int32 {
  let mut sum = 0
  for i in 0..<size {
    sum += buf[dst - bps + i]
  }
  sum
}

///|
fn sum_left(buf : FixedArray[Int32], dst : Int32, size : Int32) -> Int32 {
  let mut sum = 0
  for i in 0..<size {
    sum += buf[dst + i * bps - 1]
  }
  sum
}

///|
/// 16x16 luma, indexed like VP8PredLuma16: 0 DC, 1 TM, 2 V, 3 H,
/// 4 DC without top, 5 DC without left, 6 DC without top and left
fn predict_luma16(mode : Int32, buf : FixedArray[Int32], dst : Int32) -> Unit {
  match mode {
    0 => {
      let dc = 16 + sum_top(buf, dst, 16) + sum_left(buf, dst, 16)
      fill_block(buf, dst, 16, dc >> 5)
    }
    1 => true_motion(buf, dst, 16)
    2 => vertical(buf, dst, 16)
    3 => horizontal(buf, dst, 16)
    4 => fill_block(buf, dst, 16, (8 + sum_left(buf, dst, 16)) >> 4)
    5 => fill_block(buf, dst, 16, (8 + sum_top(buf, dst, 16)) >> 4)
    _ => fill_block(buf, dst, 16, 0x80)
  }
}

///|
/// 8x8 chroma, indexed like VP8PredChroma8 (same modes as predict_luma16)
fn predict_chroma8(mode : Int32, buf : FixedArray[Int32], dst : Int32) -> Unit {
  match mode {
    0 => {
      let dc = 8 + sum_top(buf, dst, 8) + sum_left(buf, dst, 8)
      fill_block(buf, dst, 8, dc >> 4)
    }
    1 => true_motion(buf, dst, 8)
    2 => vertical(buf, dst, 8)
    3 => horizontal(buf, dst, 8)
    4 => fill_block(buf, dst, 8, (4 + sum_left(buf, dst, 8)) >> 3)
    5 => fill_block(buf, dst, 8, (4 + sum_top(buf, dst, 8)) >> 3)
    _ => fill_block(buf, dst, 8, 0x80)
  }
}

///|
/// 4x4 luma, indexed like VP8PredLuma4: 0 DC, 1 TM, 2 VE, 3 HE, 4 RD, 5 VR,
/// 6 LD, 7 VL, 8 HD, 9 HU
fn predict_luma4(mode : Int32, buf : FixedArray[Int32], dst : Int32) -> Unit {
  let top = dst - bps
  // top-left, top (A..H, H is top-right of the 4x4 block) and left (I..L)
  let x = buf[top - 1]
  let a = buf[top]
  let b = buf[top + 1]
  let c = buf[top + 2]
  let d = buf[top + 3]
  let e = buf[top + 4]
  let f = buf[top + 5]
  let g = buf[top + 6]
  let h = buf[top + 7]
  let i = buf[dst - 1]
  let j = buf[dst + bps - 1]
  let k = buf[dst + 2 * bps - 1]
  let l = buf[dst + 3 * bps - 1]
  fn set(px : Int32, py : Int32, v : Int32) {
    buf[dst + px + py * bps] = v
  }

  match mode {
    0 =>
      fill_block(
        buf,
        dst,
        4,
        (4 + sum_top(buf, dst, 4) + sum_left(buf, dst, 4)) >> 3,
      )
    1 => true_motion(buf, dst, 4)
    2 => {
      let vals = [avg3(x, a, b), avg3(a, b, c), avg3(b, c, d), avg3(c, d, e)]
      for py in 0..<4 {
        for px in 0..<4 {
          set(px, py, vals[px])
        }
      }
    }
    3 => {
      let vals = [avg3(x, i, j), avg3(i, j, k), avg3(j, k, l), avg3(k, l, l)]
      for py in 0..<4 {
        for px in 0..<4 {
          set(px, py, vals[py])
        }
      }
    }
    4 => {
      set(0, 3, avg3(j, k, l))
      let ijk = avg3(i, j, k)
      set(1, 3, ijk)
      set(0, 2, ijk)
      let xij = avg3(x, i, j)
      set(2, 3, xij)
      set(1, 2, xij)
      set(0, 1, xij)
      let axi = avg3(a, x, i)
      set(3, 3, axi)
      set(2, 2, axi)
      set(1, 1, axi)
      set(0, 0, axi)
      let bax = avg3(b, a, x)
      set(3, 2, bax)
      set(2, 1, bax)
      set(1, 0, bax)
      let cba = avg3(c, b, a)
      set(3, 1, cba)
      set(2, 0, cba)
      set(3, 0, avg3(d, c, b))
    }
    5 => {
      let xa = avg2(x, a)
      set(0, 0, xa)
      set(1, 2, xa)
      let ab = avg2(a, b)
      set(1, 0, ab)
      set(2, 2, ab)
      let bc = avg2(b, c)
      set(2, 0, bc)
      set(3, 2, bc)
      set(3, 0, avg2(c, d))
      set(0, 3, avg3(k, j, i))
      set(0, 2, avg3(j, i, x))
      let ixa = avg3(i, x, a)
      set(0, 1, ixa)
      set(1, 3, ixa)
      let xab = avg3(x, a, b)
      set(1, 1, xab)
      set(2, 3, xab)
      let abc = avg3(a, b, c)
      set(2, 1, abc)
      set(3, 3, abc)
      set(3, 1, avg3(b, c, d))
    }
    6 => {
      set(0, 0, avg3(a, b, c))
      let bcd = avg3(b, c, d)
      set(1, 0, bcd)
      set(0, 1, bcd)
      let cde = avg3(c, d, e)
      set(2, 0, cde)
      set(1, 1, cde)
      set(0, 2, cde)
      let def = avg3(d, e, f)
      set(3, 0, def)
      set(2, 1, def)
      set(1, 2, def)
      set(0, 3, def)
      let efg = avg3(e, f, g)
      set(3, 1, efg)
      set(2, 2, efg)
      set(1, 3, efg)
      let fgh = avg3(f, g, h)
      set(3, 2, fgh)
      set(2, 3, fgh)
      set(3, 3, avg3(g, h, h))
    }
    7 => {
      set(0, 0, avg2(a, b))
      let bc = avg2(b, c)
      set(1, 0, bc)
      set(0, 2, bc)
      let cd = avg2(c, d)
      set(2, 0, cd)
      set(1, 2, cd)
      let de = avg2(d, e)
      set(3, 0, de)
      set(2, 2, de)
      set(0, 1, avg3(a, b, c))
      let bcd = avg3(b, c, d)
      set(1, 1, bcd)
      set(0, 3, bcd)
      let cde = avg3(c, d, e)
      set(2, 1, cde)
      set(1, 3, cde)
      let def = avg3(d, e, f)
      set(3, 1, def)
      set(2, 3, def)
      set(3, 2, avg3(e, f, g))
      set(3, 3, avg3(f, g, h))
    }
    8 => {
      let ix = avg2(i, x)
      set(0, 0, ix)
      set(2, 1, ix)
      let ji = avg2(j, i)
      set(0, 1, ji)
      set(2, 2, ji)
      let kj = avg2(k, j)
      set(0, 2, kj)
      set(2, 3, kj)
      set(0, 3, avg2(l, k))
      set(3, 0, avg3(a, b, c))
      set(2, 0, avg3(x, a, b))
      let ixa = avg3(i, x, a)
      set(1, 0, ixa)
      set(3, 1, ixa)
      let jix = avg3(j, i, x)
      set(1, 1, jix)
      set(3, 2, jix)
      let kji = avg3(k, j, i)
      set(1, 2, kji)
      set(3, 3, kji)
      set(1, 3, avg3(l, k, j))
    }
    _ => {
      set(0, 0, avg2(i, j))
      let jk = avg2(j, k)
      set(2, 0, jk)
      set(0, 1, jk)
      let kl = avg2(k, l)
      set(2, 1, kl)
      set(0, 2, kl)
      set(1, 0, avg3(i, j, k))
      let jkl = avg3(j, k, l)
      set(3, 0, jkl)
      set(1, 1, jkl)
      let kll = avg3(k, l, l)
      set(3, 1, kll)
      set(1, 2, kll)
      set(3, 2, l)
      set(2, 2, l)
      set(0, 3, l)
      set(1, 3, l)
      set(2, 3, l)
      set(3, 3, l)
    }
  }
}
