// Macroblock parsing, reconstruction and loop filtering, ported from libwebp
// src/dec/tree_dec.c, src/dec/vp8_dec.c and src/dec/frame_dec.c.
//
// libwebp filters rows with a delay using a row cache. Here every macroblock
// is reconstructed first and the loop filter then runs over the planes in the
// same raster order. Prediction never reads the planes: it uses the work
// buffer and the unfiltered top samples, as libwebp does.

///|
let kbands : FixedArray[Int32] = [
  0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0,
]

///|
let kzigzag : FixedArray[Int32] = [
  0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15,
]

///|
let kcat3 : FixedArray[Int32] = [173, 148, 140]

///|
let kcat4 : FixedArray[Int32] = [176, 155, 140, 135]

///|
let kcat5 : FixedArray[Int32] = [180, 157, 141, 134, 130]

///|
let kcat6 : FixedArray[Int32] = [
  254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129,
]

///|
/// Offsets of the 16 luma 4x4 blocks in the work buffer
let kscan : FixedArray[Int32] = [
  0,
  4,
  8,
  12,
  4 * bps,
  4 + 4 * bps,
  8 + 4 * bps,
  12 + 4 * bps,
  8 * bps,
  4 + 8 * bps,
  8 + 8 * bps,
  12 + 8 * bps,
  12 * bps,
  4 + 12 * bps,
  8 + 12 * bps,
  12 + 12 * bps,
]

///|
let y_off : Int32 = bps * 1 + 8

///|
let u_off : Int32 = y_off + bps * 16 + bps

///|
let v_off : Int32 = u_off + 16

///|
let yuv_size : Int32 = bps * 17 + bps * 9

///|
priv struct MacroBlock {
  mut segment : Int32
  mut skip : Bool
  mut is_i4x4 : Bool
  imodes : FixedArray[Int32] // 16 4x4 modes, or the 16x16 mode in [0]
  mut uvmode : Int32
  coeffs : FixedArray[Int32] // 384: 16 Y, 4 U, 4 V blocks of 16
}

///|
priv struct FilterInfo {
  limit : Int32
  ilevel : Int32
  hev_thresh : Int32
}

///|
priv struct Decoder {
  hdr : FrameHeader
  br : BoolDecoder
  mb_w : Int32
  mb_h : Int32
  proba : FixedArray[Int32] // [type][band][ctx][proba]
  mut use_skip_proba : Bool
  mut skip_p : Int32
  quant : FixedArray[Int32] // per segment: y1 dc, y1 ac, y2 dc, y2 ac, uv dc, uv ac
  filter_type : Int32 // 0 none, 1 simple, 2 normal
  fstrengths : FixedArray[FilterInfo] // [segment][is_i4x4]
  intra_t : FixedArray[Int32]
  intra_l : FixedArray[Int32]
  nz_t : FixedArray[Int32]
  nz_dc_t : FixedArray[Int32]
  mut nz_l : Int32
  mut nz_dc_l : Int32
  // unfiltered bottom samples of the previous macroblock row
  y_t : FixedArray[Int32]
  u_t : FixedArray[Int32]
  v_t : FixedArray[Int32]
  yuv_b : FixedArray[Int32]
  // decoded planes
  y_stride : Int32
  uv_stride : Int32
  y_plane : FixedArray[Int32]
  u_plane : FixedArray[Int32]
  v_plane : FixedArray[Int32]
  // per macroblock: filter limit (0 = none), ilevel, hev threshold, inner
  f_limit : FixedArray[Int32]
  f_ilevel : FixedArray[Int32]
  f_hev : FixedArray[Int32]
  f_inner : FixedArray[Bool]
}

///|
fn proba_index(t : Int32, band : Int32, ctx : Int32) -> Int32 {
  ((t * 8 + band) * 3 + ctx) * 11
}

///|
fn clip(v : Int32, m : Int32) -> Int32 {
  if v < 0 {
    0
  } else if v > m {
    m
  } else {
    v
  }
}

///|
fn Decoder::new(hdr : FrameHeader, br : BoolDecoder) -> Decoder {
  let mb_w = (hdr.width + 15) >> 4
  let mb_h = (hdr.height + 15) >> 4
  // VP8ParseQuant
  let quant = FixedArray::make(4 * 6, 0)
  for s in 0..<4 {
    let q = if hdr.use_segment {
      hdr.quantizer[s] + (if hdr.absolute_delta { 0 } else { hdr.base_q })
    } else {
      hdr.base_q
    }
    let m = s * 6
    quant[m] = dc_table[clip(q + hdr.dqy1_dc, 127)]
    quant[m + 1] = ac_table[clip(q, 127)]
    quant[m + 2] = dc_table[clip(q + hdr.dqy2_dc, 127)] * 2
    let y2_ac = (ac_table[clip(q + hdr.dqy2_ac, 127)] * 101581) >> 16
    quant[m + 3] = if y2_ac < 8 { 8 } else { y2_ac }
    quant[m + 4] = dc_table[clip(q + hdr.dquv_dc, 117)]
    quant[m + 5] = ac_table[clip(q + hdr.dquv_ac, 127)]
  }
  // PrecomputeFilterStrengths
  let filter_type = if hdr.filter_level == 0 {
    0
  } else if hdr.simple_filter {
    1
  } else {
    2
  }
  let fstrengths = FixedArray::make(8, { limit: 0, ilevel: 0, hev_thresh: 0, })
  if filter_type > 0 {
    for s in 0..<4 {
      let base_level = if hdr.use_segment {
        hdr.filter_strength[s] +
        (if hdr.absolute_delta { 0 } else { hdr.filter_level })
      } else {
        hdr.filter_level
      }
      for i4x4 in 0..<2 {
        let mut level = base_level
        if hdr.use_lf_delta {
          level += hdr.ref_lf_delta[0]
          if i4x4 == 1 {
            level += hdr.mode_lf_delta[0]
          }
        }
        level = clip(level, 63)
        if level > 0 {
          let mut ilevel = level
          if hdr.sharpness > 0 {
            ilevel = if hdr.sharpness > 4 { ilevel >> 2 } else { ilevel >> 1 }
            if ilevel > 9 - hdr.sharpness {
              ilevel = 9 - hdr.sharpness
            }
          }
          if ilevel < 1 {
            ilevel = 1
          }
          let hev_thresh = if level >= 40 {
            2
          } else if level >= 15 {
            1
          } else {
            0
          }
          fstrengths[s * 2 + i4x4] = {
            limit: 2 * level + ilevel,
            ilevel,
            hev_thresh,
          }
        }
      }
    }
  }
  let y_stride = mb_w * 16
  let uv_stride = mb_w * 8
  {
    hdr,
    br,
    mb_w,
    mb_h,
    proba: FixedArray::make(4 * 8 * 3 * 11, 0),
    use_skip_proba: false,
    skip_p: 0,
    quant,
    filter_type,
    fstrengths,
    intra_t: FixedArray::make(4 * mb_w, 0),
    intra_l: FixedArray::make(4, 0),
    nz_t: FixedArray::make(mb_w, 0),
    nz_dc_t: FixedArray::make(mb_w, 0),
    nz_l: 0,
    nz_dc_l: 0,
    y_t: FixedArray::make(16 * mb_w, 0),
    u_t: FixedArray::make(8 * mb_w, 0),
    v_t: FixedArray::make(8 * mb_w, 0),
    yuv_b: FixedArray::make(yuv_size, 0),
    y_stride,
    uv_stride,
    y_plane: FixedArray::make(y_stride * mb_h * 16, 0),
    u_plane: FixedArray::make(uv_stride * mb_h * 8, 0),
    v_plane: FixedArray::make(uv_stride * mb_h * 8, 0),
    f_limit: FixedArray::make(mb_w * mb_h, 0),
    f_ilevel: FixedArray::make(mb_w * mb_h, 0),
    f_hev: FixedArray::make(mb_w * mb_h, 0),
    f_inner: FixedArray::make(mb_w * mb_h, false),
  }
}

///|
/// VP8ParseProba
fn Decoder::parse_proba(self : Decoder) -> Unit {
  let br = self.br
  let _ = br.read_bool(128) // update_proba is ignored
  for i in 0..<self.proba.length() {
    self.proba[i] = if br.read_bool(coeffs_update_proba[i]) {
      br.read_literal(8)
    } else {
      coeffs_proba0[i]
    }
  }
  self.use_skip_proba = br.read_bool(128)
  if self.use_skip_proba {
    self.skip_p = br.read_literal(8)
  }
}

///|
/// ParseIntraMode
fn Decoder::parse_intra_mode(
  self : Decoder,
  mb_x : Int32,
  block : MacroBlock,
) -> Unit {
  let br = self.br
  let hdr = self.hdr
  block.segment = if hdr.update_map {
    if !br.read_bool(hdr.segment_probs[0]) {
      if br.read_bool(hdr.segment_probs[1]) {
        1
      } else {
        0
      }
    } else if br.read_bool(hdr.segment_probs[2]) {
      3
    } else {
      2
    }
  } else {
    0
  }
  block.skip = if self.use_skip_proba {
    br.read_bool(self.skip_p)
  } else {
    false
  }
  block.is_i4x4 = !br.read_bool(145)
  let top = 4 * mb_x
  if !block.is_i4x4 {
    let ymode = if br.read_bool(156) {
      if br.read_bool(128) {
        1 // TM_PRED
      } else {
        3 // H_PRED
      }
    } else if br.read_bool(163) {
      2 // V_PRED
    } else {
      0 // DC_PRED
    }
    block.imodes[0] = ymode
    for i in 0..<4 {
      self.intra_t[top + i] = ymode
      self.intra_l[i] = ymode
    }
  } else {
    for y in 0..<4 {
      let mut ymode = self.intra_l[y]
      for x in 0..<4 {
        let prob = (self.intra_t[top + x] * 10 + ymode) * 9
        ymode = if !br.read_bool(bmodes_proba[prob]) {
          0 // B_DC_PRED
        } else if !br.read_bool(bmodes_proba[prob + 1]) {
          1 // B_TM_PRED
        } else if !br.read_bool(bmodes_proba[prob + 2]) {
          2 // B_VE_PRED
        } else if !br.read_bool(bmodes_proba[prob + 3]) {
          if !br.read_bool(bmodes_proba[prob + 4]) {
            3 // B_HE_PRED
          } else if !br.read_bool(bmodes_proba[prob + 5]) {
            4 // B_RD_PRED
          } else {
            5 // B_VR_PRED
          }
        } else if !br.read_bool(bmodes_proba[prob + 6]) {
          6 // B_LD_PRED
        } else if !br.read_bool(bmodes_proba[prob + 7]) {
          7 // B_VL_PRED
        } else if !br.read_bool(bmodes_proba[prob + 8]) {
          8 // B_HD_PRED
        } else {
          9 // B_HU_PRED
        }
        self.intra_t[top + x] = ymode
      }
      for x in 0..<4 {
        block.imodes[y * 4 + x] = self.intra_t[top + x]
      }
      self.intra_l[y] = ymode
    }
  }
  block.uvmode = if !br.read_bool(142) {
    0 // DC_PRED
  } else if !br.read_bool(114) {
    2 // V_PRED
  } else if br.read_bool(183) {
    1 // TM_PRED
  } else {
    3 // H_PRED
  }
}

///|
/// GetLargeValue
fn Decoder::get_large_value(
  self : Decoder,
  br : BoolDecoder,
  p : Int32,
) -> Int32 {
  let proba = self.proba
  if !br.read_bool(proba[p + 3]) {
    if !br.read_bool(proba[p + 4]) {
      2
    } else {
      3 + (if br.read_bool(proba[p + 5]) { 1 } else { 0 })
    }
  } else if !br.read_bool(proba[p + 6]) {
    if !br.read_bool(proba[p + 7]) {
      5 + (if br.read_bool(159) { 1 } else { 0 })
    } else {
      7 +
      2 * (if br.read_bool(165) { 1 } else { 0 }) +
      (if br.read_bool(145) { 1 } else { 0 })
    }
  } else {
    let bit1 = if br.read_bool(proba[p + 8]) { 1 } else { 0 }
    let bit0 = if br.read_bool(proba[p + 9 + bit1]) { 1 } else { 0 }
    let cat = 2 * bit1 + bit0
    let tab = match cat {
      0 => kcat3
      1 => kcat4
      2 => kcat5
      _ => kcat6
    }
    let mut v = 0
    for i in 0..<tab.length() {
      v += v + (if br.read_bool(tab[i]) { 1 } else { 0 })
    }
    v + 3 + (8 << cat)
  }
}

///|
/// GetCoeffs: returns the position after the last non-zero coefficient
fn Decoder::get_coeffs(
  self : Decoder,
  br : BoolDecoder,
  t : Int32,
  ctx : Int32,
  dc_q : Int32,
  ac_q : Int32,
  first : Int32,
  out : FixedArray[Int32],
  off : Int32,
) -> Int32 {
  let proba = self.proba
  let mut n = first
  let mut p = proba_index(t, kbands[n], ctx)
  while n < 16 {
    if !br.read_bool(proba[p]) {
      return n // previous coeff was the last non-zero one
    }
    while !br.read_bool(proba[p + 1]) {
      n += 1
      if n == 16 {
        return 16
      }
      p = proba_index(t, kbands[n], 0)
    }
    let (v, next_ctx) = if !br.read_bool(proba[p + 2]) {
      (1, 1)
    } else {
      (self.get_large_value(br, p), 2)
    }
    p = proba_index(t, kbands[n + 1], next_ctx)
    out[off + kzigzag[n]] = br.get_signed(v) * (if n > 0 { ac_q } else { dc_q })
    n += 1
  }
  16
}

///|
/// ParseResiduals: returns true when every coefficient is zero
fn Decoder::parse_residuals(
  self : Decoder,
  mb_x : Int32,
  block : MacroBlock,
  br : BoolDecoder,
) -> Bool {
  let coeffs = block.coeffs
  coeffs.fill(0)
  let q = block.segment * 6
  let mut all_zero = true
  let (first, ac_type) = if !block.is_i4x4 {
    let dc = FixedArray::make(16, 0)
    let ctx = self.nz_dc_t[mb_x] + self.nz_dc_l
    let nz = self.get_coeffs(
      br,
      1,
      ctx,
      self.quant[q + 2],
      self.quant[q + 3],
      0,
      dc,
      0,
    )
    let nz_dc = if nz > 0 { 1 } else { 0 }
    self.nz_dc_t[mb_x] = nz_dc
    self.nz_dc_l = nz_dc
    if nz > 1 {
      inverse_wht(dc, coeffs)
    } else {
      let dc0 = (dc[0] + 3) >> 3
      for i in 0..<16 {
        coeffs[i * 16] = dc0
      }
    }
    (1, 0)
  } else {
    (0, 3)
  }
  let mut tnz = self.nz_t[mb_x] & 0x0f
  let mut lnz = self.nz_l & 0x0f
  let mut dst = 0
  for _y in 0..<4 {
    let mut l = lnz & 1
    for _x in 0..<4 {
      let ctx = l + (tnz & 1)
      let nz = self.get_coeffs(
        br,
        ac_type,
        ctx,
        self.quant[q],
        self.quant[q + 1],
        first,
        coeffs,
        dst,
      )
      l = if nz > first { 1 } else { 0 }
      tnz = ((tnz >> 1) | (l << 7)) & 0xff
      // NzCodeBits: a block counts as non-zero when it has AC coefficients
      // or a non-zero DC
      if nz > 1 || coeffs[dst] != 0 {
        all_zero = false
      }
      dst += 16
    }
    tnz = tnz >> 4
    lnz = ((lnz >> 1) | (l << 7)) & 0xff
  }
  let mut out_t_nz = tnz
  let mut out_l_nz = lnz >> 4
  for ch in [0, 2] {
    tnz = (self.nz_t[mb_x] >> (4 + ch)) & 0xff
    lnz = (self.nz_l >> (4 + ch)) & 0xff
    for _y in 0..<2 {
      let mut l = lnz & 1
      for _x in 0..<2 {
        let ctx = l + (tnz & 1)
        let nz = self.get_coeffs(
          br,
          2,
          ctx,
          self.quant[q + 4],
          self.quant[q + 5],
          0,
          coeffs,
          dst,
        )
        l = if nz > 0 { 1 } else { 0 }
        tnz = ((tnz >> 1) | (l << 3)) & 0xff
        // NzCodeBits: a block counts as non-zero when it has AC coefficients
        // or a non-zero DC
        if nz > 1 || coeffs[dst] != 0 {
          all_zero = false
        }
        dst += 16
      }
      tnz = tnz >> 2
      lnz = ((lnz >> 1) | (l << 5)) & 0xff
    }
    out_t_nz = out_t_nz | (tnz << 4 << ch)
    out_l_nz = out_l_nz | ((lnz & 0xf0) << ch)
  }
  self.nz_t[mb_x] = out_t_nz & 0xff
  self.nz_l = out_l_nz & 0xff
  all_zero
}

///|
/// CheckMode: DC prediction without the missing neighbours
fn check_mode(mb_x : Int32, mb_y : Int32, mode : Int32) -> Int32 {
  if mode == 0 {
    if mb_x == 0 {
      if mb_y == 0 {
        6
      } else {
        5
      }
    } else if mb_y == 0 {
      4
    } else {
      0
    }
  } else {
    mode
  }
}

///|
/// ReconstructRow for one macroblock
fn Decoder::reconstruct(
  self : Decoder,
  mb_x : Int32,
  mb_y : Int32,
  block : MacroBlock,
) -> Unit {
  let b = self.yuv_b
  if mb_x > 0 {
    for j in -1..<16 {
      for i in 0..<4 {
        b[y_off + j * bps - 4 + i] = b[y_off + j * bps + 12 + i]
      }
    }
    for j in -1..<8 {
      for i in 0..<4 {
        b[u_off + j * bps - 4 + i] = b[u_off + j * bps + 4 + i]
        b[v_off + j * bps - 4 + i] = b[v_off + j * bps + 4 + i]
      }
    }
  }
  if mb_y > 0 {
    for i in 0..<16 {
      b[y_off - bps + i] = self.y_t[mb_x * 16 + i]
    }
    for i in 0..<8 {
      b[u_off - bps + i] = self.u_t[mb_x * 8 + i]
      b[v_off - bps + i] = self.v_t[mb_x * 8 + i]
    }
  }
  let coeffs = block.coeffs
  if block.is_i4x4 {
    let top_right = y_off - bps + 16
    if mb_y > 0 {
      for i in 0..<4 {
        b[top_right + i] = if mb_x >= self.mb_w - 1 {
          self.y_t[mb_x * 16 + 15]
        } else {
          self.y_t[(mb_x + 1) * 16 + i]
        }
      }
    }
    for k in 1..<=3 {
      for i in 0..<4 {
        b[top_right + 4 * k * bps + i] = b[top_right + i]
      }
    }
    for n in 0..<16 {
      let dst = y_off + kscan[n]
      predict_luma4(block.imodes[n], b, dst)
      inverse_dct(coeffs, n * 16, b, dst)
    }
  } else {
    predict_luma16(check_mode(mb_x, mb_y, block.imodes[0]), b, y_off)
    for n in 0..<16 {
      inverse_dct(coeffs, n * 16, b, y_off + kscan[n])
    }
  }
  let uv_mode = check_mode(mb_x, mb_y, block.uvmode)
  predict_chroma8(uv_mode, b, u_off)
  predict_chroma8(uv_mode, b, v_off)
  for n in 0..<4 {
    let dst = (n & 1) * 4 + (n >> 1) * 4 * bps
    inverse_dct(coeffs, (16 + n) * 16, b, u_off + dst)
    inverse_dct(coeffs, (20 + n) * 16, b, v_off + dst)
  }
  if mb_y < self.mb_h - 1 {
    for i in 0..<16 {
      self.y_t[mb_x * 16 + i] = b[y_off + 15 * bps + i]
    }
    for i in 0..<8 {
      self.u_t[mb_x * 8 + i] = b[u_off + 7 * bps + i]
      self.v_t[mb_x * 8 + i] = b[v_off + 7 * bps + i]
    }
  }
  for j in 0..<16 {
    let row = (mb_y * 16 + j) * self.y_stride + mb_x * 16
    for i in 0..<16 {
      self.y_plane[row + i] = b[y_off + j * bps + i]
    }
  }
  for j in 0..<8 {
    let row = (mb_y * 8 + j) * self.uv_stride + mb_x * 8
    for i in 0..<8 {
      self.u_plane[row + i] = b[u_off + j * bps + i]
      self.v_plane[row + i] = b[v_off + j * bps + i]
    }
  }
}

///|
/// Sets the work buffer borders at the start of a macroblock row
fn Decoder::init_row(self : Decoder, mb_y : Int32) -> Unit {
  let b = self.yuv_b
  for j in 0..<16 {
    b[y_off + j * bps - 1] = 129
  }
  for j in 0..<8 {
    b[u_off + j * bps - 1] = 129
    b[v_off + j * bps - 1] = 129
  }
  if mb_y > 0 {
    b[y_off - 1 - bps] = 129
    b[u_off - 1 - bps] = 129
    b[v_off - 1 - bps] = 129
  } else {
    for i in 0..<21 {
      b[y_off - bps - 1 + i] = 127
    }
    for i in 0..<9 {
      b[u_off - bps - 1 + i] = 127
      b[v_off - bps - 1 + i] = 127
    }
  }
}

///|
/// DoFilter
fn Decoder::filter_mb(self : Decoder, mb_x : Int32, mb_y : Int32) -> Unit {
  let i = mb_y * self.mb_w + mb_x
  let limit = self.f_limit[i]
  if limit == 0 {
    return
  }
  let ilevel = self.f_ilevel[i]
  let hev_thresh = self.f_hev[i]
  let inner = self.f_inner[i]
  let ys = self.y_stride
  let y = self.y_plane
  let y_dst = mb_y * 16 * ys + mb_x * 16
  if self.filter_type == 1 {
    if mb_x > 0 {
      simple_h_filter16(y, y_dst, ys, limit + 4)
    }
    if inner {
      simple_h_filter16i(y, y_dst, ys, limit)
    }
    if mb_y > 0 {
      simple_v_filter16(y, y_dst, ys, limit + 4)
    }
    if inner {
      simple_v_filter16i(y, y_dst, ys, limit)
    }
  } else {
    let uvs = self.uv_stride
    let u = self.u_plane
    let v = self.v_plane
    let uv_dst = mb_y * 8 * uvs + mb_x * 8
    if mb_x > 0 {
      h_filter16(y, y_dst, ys, limit + 4, ilevel, hev_thresh)
      h_filter8(u, uv_dst, uvs, limit + 4, ilevel, hev_thresh)
      h_filter8(v, uv_dst, uvs, limit + 4, ilevel, hev_thresh)
    }
    if inner {
      h_filter16i(y, y_dst, ys, limit, ilevel, hev_thresh)
      h_filter8i(u, uv_dst, uvs, limit, ilevel, hev_thresh)
      h_filter8i(v, uv_dst, uvs, limit, ilevel, hev_thresh)
    }
    if mb_y > 0 {
      v_filter16(y, y_dst, ys, limit + 4, ilevel, hev_thresh)
      v_filter8(u, uv_dst, uvs, limit + 4, ilevel, hev_thresh)
      v_filter8(v, uv_dst, uvs, limit + 4, ilevel, hev_thresh)
    }
    if inner {
      v_filter16i(y, y_dst, ys, limit, ilevel, hev_thresh)
      v_filter8i(u, uv_dst, uvs, limit, ilevel, hev_thresh)
      v_filter8i(v, uv_dst, uvs, limit, ilevel, hev_thresh)
    }
  }
}

///|
fn Decoder::decode_frame(self : Decoder) -> Unit raise @image.DecodeError {
  self.parse_proba()
  let block = {
    segment: 0,
    skip: false,
    is_i4x4: false,
    imodes: FixedArray::make(16, 0),
    uvmode: 0,
    coeffs: FixedArray::make(384, 0),
  }
  let partitions = self.hdr.partitions
  for mb_y in 0..<self.mb_h {
    let token_br = partitions[mb_y & (self.hdr.num_partitions - 1)]
    // VP8InitScanline
    self.nz_l = 0
    self.nz_dc_l = 0
    self.intra_l.fill(0)
    self.init_row(mb_y)
    for mb_x in 0..<self.mb_w {
      self.parse_intra_mode(mb_x, block)
      // VP8DecodeMB
      let skip = if !block.skip {
        self.parse_residuals(mb_x, block, token_br)
      } else {
        self.nz_t[mb_x] = 0
        self.nz_l = 0
        if !block.is_i4x4 {
          self.nz_dc_t[mb_x] = 0
          self.nz_dc_l = 0
        }
        block.coeffs.fill(0)
        true
      }
      if self.filter_type > 0 {
        let info = self.fstrengths[block.segment * 2 +
          (if block.is_i4x4 { 1 } else { 0 })]
        let i = mb_y * self.mb_w + mb_x
        self.f_limit[i] = info.limit
        self.f_ilevel[i] = info.ilevel
        self.f_hev[i] = info.hev_thresh
        self.f_inner[i] = block.is_i4x4 || !skip
      }
      if token_br.eof {
        raise @image.DecodeError("premature end of VP8 data")
      }
      self.reconstruct(mb_x, mb_y, block)
    }
    if self.br.eof {
      raise @image.DecodeError("premature end of VP8 partition 0")
    }
  }
  if self.filter_type > 0 {
    for mb_y in 0..<self.mb_h {
      for mb_x in 0..<self.mb_w {
        self.filter_mb(mb_x, mb_y)
      }
    }
  }
}
