// Prints what libwebp's WebPAnimDecoder makes of an animated WebP file, as
// the reference for this library's animation decoder. Unlike anim_dump, it
// does not clear the color of transparent pixels.
//
// Output, one line each:
//   canvas <width> <height> loop <count> bgcolor <0xAARRGGBB> frames <n>
//   frame <i> timestamp <ms> md5 <MD5 of the RGBA canvas>
// or "error" when libwebp rejects the file.
//
// Build against a libwebp checkout (see README.md in this directory).
#include <stdio.h>
#include <stdlib.h>

#include "webp/demux.h"

// Minimal MD5 (RFC 1321)
typedef struct {
  unsigned int a, b, c, d;
} Md5;

static unsigned int Rol(unsigned int x, int c) { return (x << c) | (x >> (32 - c)); }

static void Md5Block(Md5* m, const unsigned char* p) {
  static const unsigned int k[64] = {
      0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a,
      0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
      0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340,
      0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
      0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8,
      0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
      0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa,
      0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
      0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92,
      0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
      0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391};
  static const int r[64] = {7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7,
                            12, 17, 22, 5, 9,  14, 20, 5, 9,  14, 20, 5, 9,
                            14, 20, 5,  9, 14, 20, 4, 11, 16, 23, 4, 11, 16,
                            23, 4,  11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21,
                            6,  10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21};
  unsigned int w[16], a = m->a, b = m->b, c = m->c, d = m->d;
  int i;
  for (i = 0; i < 16; ++i) {
    w[i] = p[4 * i] | (p[4 * i + 1] << 8) | (p[4 * i + 2] << 16) |
           ((unsigned int)p[4 * i + 3] << 24);
  }
  for (i = 0; i < 64; ++i) {
    unsigned int f, t;
    int g;
    if (i < 16) {
      f = (b & c) | (~b & d);
      g = i;
    } else if (i < 32) {
      f = (d & b) | (~d & c);
      g = (5 * i + 1) % 16;
    } else if (i < 48) {
      f = b ^ c ^ d;
      g = (3 * i + 5) % 16;
    } else {
      f = c ^ (b | ~d);
      g = (7 * i) % 16;
    }
    t = d;
    d = c;
    c = b;
    b = b + Rol(a + f + k[i] + w[g], r[i]);
    a = t;
  }
  m->a += a;
  m->b += b;
  m->c += c;
  m->d += d;
}

static void Md5Hex(const unsigned char* data, size_t len, char out[33]) {
  Md5 m = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476};
  unsigned char tail[128] = {0};
  size_t i, rest = len % 64, tail_len = rest < 56 ? 64 : 128;
  unsigned long long bits = (unsigned long long)len * 8;
  for (i = 0; i + 64 <= len; i += 64) Md5Block(&m, data + i);
  for (i = 0; i < rest; ++i) tail[i] = data[len - rest + i];
  tail[rest] = 0x80;
  for (i = 0; i < 8; ++i) tail[tail_len - 8 + i] = (unsigned char)(bits >> (8 * i));
  for (i = 0; i < tail_len; i += 64) Md5Block(&m, tail + i);
  {
    const unsigned int v[4] = {m.a, m.b, m.c, m.d};
    for (i = 0; i < 16; ++i) {
      sprintf(out + 2 * i, "%02x", (v[i / 4] >> (8 * (i % 4))) & 0xff);
    }
  }
}

int main(int argc, char** argv) {
  FILE* f;
  long size;
  unsigned char* bytes;
  WebPData data;
  WebPAnimDecoder* dec;
  WebPAnimInfo info;
  int i = 0;
  if (argc != 2 || (f = fopen(argv[1], "rb")) == NULL) {
    fprintf(stderr, "usage: anim_frames FILE\n");
    return 2;
  }
  fseek(f, 0, SEEK_END);
  size = ftell(f);
  fseek(f, 0, SEEK_SET);
  bytes = (unsigned char*)malloc(size > 0 ? size : 1);
  if (fread(bytes, 1, size, f) != (size_t)size) return 2;
  fclose(f);
  data.bytes = bytes;
  data.size = size;
  dec = WebPAnimDecoderNew(&data, NULL);  // RGBA, not premultiplied
  if (dec == NULL || !WebPAnimDecoderGetInfo(dec, &info)) {
    printf("error\n");
    return 0;
  }
  printf("canvas %u %u loop %u bgcolor 0x%08x frames %u\n", info.canvas_width,
         info.canvas_height, info.loop_count, info.bgcolor, info.frame_count);
  while (WebPAnimDecoderHasMoreFrames(dec)) {
    uint8_t* rgba;
    int timestamp;
    char md5[33];
    if (!WebPAnimDecoderGetNext(dec, &rgba, &timestamp)) {
      printf("error\n");
      break;
    }
    Md5Hex(rgba, (size_t)info.canvas_width * info.canvas_height * 4, md5);
    printf("frame %d timestamp %d md5 %s\n", ++i, timestamp, md5);
  }
  WebPAnimDecoderDelete(dec);
  free(bytes);
  return 0;
}
