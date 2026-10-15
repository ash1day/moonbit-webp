# moonbit-webp

見せるだけのリポジトリ。mooncakes.io には publish しない。

## 開発ルール

- **出力型**: `ImageData { width: Int, height: Int, data: Bytes }` (RGBA8, 4bytes/pixel)
- **エラー型**: `pub(all) suberror DecodeError { DecodeError(String) }`
- **公開API**: `pub fn decode_vp8l(webp_data : Bytes) -> ImageData raise DecodeError` (lossless のみ)
- **ピクセルレイアウト**: RGBA順 (R=offset 0, G=1, B=2, A=3)
- **standalone構成**: `lib/` 配下にサブパッケージ

## テスト

```bash
moon test
```

## パッケージ構成

```
lib/
  riff/          # RIFFコンテナパーサ
  bitreader/     # LSBファーストのビットリーダー
  huffman/       # Canonical Huffmanツリー
  transform/     # VP8L逆変換
  vp8l/          # VP8Lデコーダ本体
```
