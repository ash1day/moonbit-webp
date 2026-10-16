///|
let hex_chars : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
fn md5_hex(data : Bytes) -> String {
  let digest = @crypto.md5(data)
  let buf = StringBuilder()
  for i = 0; i < digest.length(); i = i + 1 {
    let b = digest[i].to_int()
    buf.write_char(hex_chars[b >> 4])
    buf.write_char(hex_chars[b & 0x0F])
  }
  buf.to_string()
}

///|
/// Expected values are the MD5 of the RGBA pixels written by `dwebp -pam`.
fn check_lossy_file(
  path : String,
  width : Int32,
  height : Int32,
  md5 : String,
) -> Unit raise {
  let webp_data = @fs.read_file_to_bytes("testdata/\{path}.webp")
  let result = decode_vp8(webp_data)
  assert_eq((path, result.width, result.height), (path, width, height))
  assert_eq((path, md5_hex(result.data)), (path, md5))
}

///|
fn check_lossy(
  name : String,
  width : Int32,
  height : Int32,
  md5 : String,
) -> Unit raise {
  check_lossy_file("lossy-extra/\{name}", width, height, md5)
}

///|
test "decode small_1x1.webp" {
  check_lossy("small_1x1", 1, 1, "62d4725612d8da89301dcb4b6bcd6a34")
}

///|
test "decode small_13x1.webp" {
  check_lossy("small_13x1", 13, 1, "567c3f3346c0d36c4105c9a84ed9da3a")
}

///|
test "decode libwebp lossy vectors" {
  check_lossy("small_1x13", 1, 13, "567c3f3346c0d36c4105c9a84ed9da3a")
  check_lossy("small_31x13", 31, 13, "cba741e37793437baee0be7d2497b183")
  check_lossy("very_short", 63, 66, "c06895e3b8458758106e8b60b34dc2cb")
  check_lossy("test", 128, 128, "50c39d15a3ec7f4bec1fe39d3e720cb2")
  check_lossy("test-nostrong", 128, 128, "6c293afc1e0ea3f28fb1bbab6e3e6c59")
  check_lossy("lossy_q0_f100", 128, 128, "0d0d4262f3a9352cad6882bbb994a0f1")
  check_lossy(
    "lossy_extreme_probabilities", 800, 534, "72669cd8a8bad0051c3369bf63074a52",
  )
}

///|
test "decode gallery and regression lossy images" {
  check_lossy_file("lossy/1", 550, 368, "9dea43de6ab31100a631e0454c491192")
  check_lossy_file("lossy/2", 550, 404, "b2b789f9accd4cedb3de8192aa54b32e")
  check_lossy_file("lossy/3", 1280, 720, "c7865f6e57f80d9032c2822f45d15915")
  check_lossy_file("lossy/4", 1024, 772, "14b9d814ff52f79a4c7aa70a24a4908f")
  check_lossy_file("lossy/5", 1024, 752, "62a243d1e2b3614182cd645cdc218491")
  check_lossy_file("regression/dark", 1, 1, "f45c698b8e0ddbceb9d7a7975938989c")
}
