# moonbit-webp

見せるだけのリポジトリ。mooncakes.io には publish しない。

## 開発ルール

- **出力型**: `ImageData { width: Int, height: Int, data: Bytes }` (RGBA8, 4bytes/pixel)
- **エラー型**: `pub(all) suberror DecodeError { DecodeError(String) }`
- **公開API**: ルートパッケージの `pub fn decode(webp_data : Bytes) -> ImageData raise DecodeError`。VP8X / ALPH を扱い、`@vp8l.decode_vp8l` (lossless) と `@vp8.decode_vp8` (lossy、alpha なし) に振り分ける
- **共通の型**: `ImageData` と `DecodeError` は `lib/image` に置き、`lib/vp8l` とルートが `pub using` で再公開する
- **lossy の正解**: libwebp (`dwebp -pam`) と bit-exact。部品は `refs/libwebp` の C 関数を切り出して実行した値と照合する
- **ピクセルレイアウト**: RGBA順 (R=offset 0, G=1, B=2, A=3)
- **standalone構成**: `lib/` 配下にサブパッケージ

## テスト

```bash
moon test
```

## パッケージ構成

```
webp.mbt         # decode（VP8X、振り分け）
alpha.mbt        # ALPH チャンク
lib/
  image/         # ImageData / DecodeError
  riff/          # RIFFコンテナパーサ
  bitreader/     # LSBファーストのビットリーダー
  huffman/       # Canonical Huffmanツリー
  transform/     # VP8L逆変換
  vp8l/          # VP8Lデコーダ本体
  vp8/           # VP8 (lossy) デコーダ。libwebp と bit-exact
```
