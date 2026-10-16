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
- [x] riff の非推奨警告（`derive(Show)`、`not(...)`）を解消する（警告 0 件、CI で `--deny-warn`）
- [x] 簡易ファジング: lossless 3 ファイルの切り詰めと 1 バイト書き換え（約 7,500 通り）で panic なし。小さいファイル 5 枚の全切り詰めと 1 バイト書き換えを `robustness_wbtest.mbt` で回帰テストにした
- [x] ヘッダーの幅・高さだけを見て `width * height * 4` を確保するので、30 バイトのファイルで最大 1 GiB 要求できる。`decode` の `max_pixels` で上限を指定でき、確保の前に照合する（既定値は形式上の最大 16384 x 16384 で、dwebp が読めるものは拒否しない）。`decode_vp8` / `decode_vp8l` は `internal/` に移したので利用者からは呼べない
- [x] 予測モードを libwebp と同じく下位 4 bit で解釈し、14, 15 はモード 0 として扱う

## lossy 対応

- [x] VP8 (lossy) デコーダ（`lib/vp8`、libwebp と bit-exact）
  - ブール符号デコーダ、ヘッダー、モードと係数、逆 DCT/WHT、イントラ予測、ループフィルター、fancy upsampling
  - 部品ごとに libwebp の C 関数を切り出したオラクルと照合
  - lossy-extra 10 枚（bryce を含む）、lossy/ 5 枚、regression/dark を dwebp と照合
  - 簡易ファジング: 3 ファイルの切り詰めと 1 バイト書き換え（約 2,700 通り）で panic なし
- [x] `ImageData` / `DecodeError` を `lib/image` に移す（`lib/vp8l` とルートは `pub using` で再公開）
- [ ] テスト画像に無いヘッダー値: `ref_lf_delta` / `mode_lf_delta` が 0 以外、segment の `absolute_delta = 0`（libwebp のエンコーダは出力しない）。sharpness 3 と 6 は cwebp で作った画像で dwebp と一致を確認済み（リポジトリには未追加）
- [x] lossy のデコードが約 15 バイト/画素かかっていた（bryce で 350 MB）。Y/U/V 平面を `Byte` にし、RGBA を `Bytes` にコピーせず、alpha をその場で書き込んで約 6 バイト/画素（146 MB）にした
- [x] ALPH チャンク（圧縮なし / VP8L 圧縮、フィルター 0〜3）
- [x] VP8X コンテナ（チャンクサイズ、アニメーションの拒否、キャンバスと画像のサイズの一致）
- [x] 公開 API をルートパッケージの `decode(webp_data) -> ImageData` にまとめる
- [x] testdata/alpha, alpha-extra を dwebp の出力と照合する
  - 簡易ファジング: alpha 5 ファイルの切り詰めと 1 バイト書き換え（約 36,000 通り）で panic なし
- [x] ALPH チャンクは libwebp と同じく VP8 より前の最後の 1 つを使い、VP8 より後ろは無視する。VP8X がないときは最初のチャンクが VP8 / VP8L でなければエラー（dwebp で確認）
- [x] VP8X のキャンバスサイズを、libwebp と同じくフレームヘッダーだけ読んでデコードの前に照合する
- [ ] `decode` は RIFF を 1 回だけ解析するが、`decode_vp8` / `decode_vp8l` がファイル全体を受け取って解析し直し、チャンクもコピーしている
- [ ] アニメーション（ANIM / ANMF）
- [ ] mooncakes.io への publish（ユーザーが決める）

## 公開の準備

- [x] testdata をパッケージから除外（`.moonignore`、26 MB → 67 KB）。未使用の `testdata/reference/` と `libwebp_tests.md5` を削除
- [x] 実装を `internal/` に移し、公開 API を `decode` / `MAX_PIXELS` / `ImageData` / `DecodeError` に絞る
- [x] `NOTICE` に libwebp (BSD-3-Clause) と image-webp (MIT) の表示
- [x] `DecodeError` を `Invalid` / `Unsupported` / `TooLarge` に分け、`Show` を実装
- [x] `pkg.generated.mbti` をコミット、CI（`--deny-warn`、fmt、mbti の差分、4 ターゲットのテスト）
- [x] CI が GitHub 上で通ることを確認
- [x] Codex のレビュー指摘: 使われない Huffman グループを保持しない（1x1 画像で 65536 グループの表を確保させられた）、RIFF ヘッダーのサイズを超えるチャンクを拒否する（どちらも libwebp と同じ）。再検証の指摘: 使われないグループの符号は検証だけして表を作らない（1.7 MB の入力で JS 13 秒 → 0.1 秒）、二次テーブルを倍々に伸ばす、RIFF サイズより短いファイルを拒否する
- [ ] `ImageData` を他の MoonBit 画像ライブラリと相互運用しやすくする（変換関数や PNG 書き出しの例）
