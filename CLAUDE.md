# moonbit-webp

## 開発ルール

- **出力型**: `ImageData { width: Int, height: Int, data: Bytes }` (RGBA8, 4bytes/pixel)
- **エラー型**: `pub(all) type! DecodeError String` (suberror パターン)
- **公開API**: `pub fn decode_webp(data: Bytes) -> ImageData raise DecodeError`
- **ピクセルレイアウト**: RGBA順 (R=offset 0, G=1, B=2, A=3)
- **standalone構成**: `lib/` 配下にサブパッケージ、統合PR時にフラット化
- **mizchi/image互換**: 統合時は `src/webp_decode.mbt`, `src/webp_encode.mbt` としてフラットに配置、`stream_decode.mbt` に WebP signature 追加

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
