# TODO

## 堅牢化（不正入力で panic / OOM しない）

- [x] riff: チャンクサイズが負 (0x80000000 以上) なら None を返す（無限ループして OOM していた）
- [x] riff: 終端を超えるチャンクで走査を止める（2 バイト境界への切り上げでのオーバーフローも含む）。途中で切れたチャンクは残し、範囲の検査は読む側で行う
- [x] vp8l: チャンクサイズが実データより大きい入力で DecodeError を返す（範囲外アクセスしていた）
- [x] transform: color transform に height を渡す（パレットで幅を詰めた後だと実在しない行まで処理する）
- [x] vp8l: get_copy_distance が fill せずに peek していたのを read_bits に変更（後方参照 1 回で最悪 58 bit 読む）
- [x] テスト: lossless-extra/ と regression/ の lossless 15 枚を dwebp の出力と照合する

## 整理

- [x] apply_subtract_green と apply_subtract_green_bounded の重複をなくす
- [x] color cache を Int (ARGB) で持ち、1 ピクセルごとの配列確保をやめる
- [ ] riff の非推奨警告（`derive(Show)`、`not(...)`）を解消する
- [x] 簡易ファジング: lossless 3 ファイルの切り詰めと 1 バイト書き換え（約 7,500 通り）で panic なし。テストには入れていない
- [ ] ヘッダーの幅・高さだけを見て `width * height * 4` を確保するので、30 バイトのファイルで最大 1 GiB 要求できる。呼び出し側が最大ピクセル数を指定できるようにする
- [x] 予測モードを libwebp と同じく下位 4 bit で解釈し、14, 15 はモード 0 として扱う

## lossy 対応

- [ ] VP8 (lossy) デコーダ: ブール符号デコーダ、フレームヘッダー、イントラ予測、逆 DCT/WHT、ループフィルター、YUV → RGBA
- [ ] ALPH チャンク（圧縮なし / VP8L 圧縮、フィルター）
- [ ] VP8X コンテナ（キャンバスサイズ、フラグ）
- [ ] 公開 API を `decode(webp_data) -> ImageData` にまとめる
- [ ] testdata/lossy, lossy-extra, alpha, alpha-extra を dwebp の出力と照合する
- [ ] mooncakes.io への publish を検討（CLAUDE.md の方針も更新）
