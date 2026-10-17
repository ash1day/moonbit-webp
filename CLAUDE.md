# moonbit-webp

pure MoonBit の WebP デコーダライブラリ。mooncakes.io への公開を準備中（公開するかどうかはユーザーが決める）。

## 開発ルール

- **公開API**: ルートパッケージの `pub fn decode(webp_data : Bytes, max_pixels? : Int = MAX_PIXELS) -> ImageData raise DecodeError` だけ。ヘッダーだけ読んでキャンバスサイズと `max_pixels` を照合してからデコードする
- **出力型**: `ImageData { width : Int, height : Int, data : Bytes }`（RGBA8、premultiply しない）
- **エラー型**: `DecodeError { Invalid(String), Unsupported(String), TooLarge(String) }`。`Show` を実装する
- **共通の型**: `ImageData` と `DecodeError` は `image/` に置き、ルートが `pub using` で再公開する
- **非公開**: 実装は `internal/` に置く（他のモジュールから import できない）
- **正解**: libwebp (`dwebp -pam`) と bit-exact。lossy の部品は `refs/libwebp` の C 関数を切り出して実行した値と照合する
- **公開 API の変更**: `moon info` で `pkg.generated.mbti` を更新してコミットする（CI が差分を検査する）
- **ライセンス表示**: libwebp / image-webp から移植したコードは `NOTICE` に記載する
- `moon fmt` は `Int` を `Int32` に書き換える。フォーマッタに従う

## テスト

```bash
moon test --target all
moon check --deny-warn
```

## パッケージ構成

```
webp.mbt          # decode（VP8X、振り分け、上限の照合）
alpha.mbt         # ALPH チャンク
anim.mbt          # アニメーション（ANIM / ANMF）
robustness_wbtest.mbt  # 切り詰めと 1 バイト書き換えで落ちないこと
image/            # ImageData / DecodeError
internal/
  riff/           # RIFF コンテナパーサ
  bitreader/      # LSB ファーストのビットリーダー
  huffman/        # Canonical Huffman ツリー
  transform/      # VP8L 逆変換
  vp8l/           # VP8L (lossless) デコーダ
  vp8/            # VP8 (lossy) デコーダ
testdata/         # テスト画像（.moonignore でパッケージから除外）
tools/differential/  # 壊れたファイルを libwebp と比べる差分テスト（run.py）
```
