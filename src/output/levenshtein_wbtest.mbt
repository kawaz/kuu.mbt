///|
test "同一文字列の距離は0" {
  assert_eq!(levenshtein_distance("abc", "abc"), 0)
}

///|
test "空文字列との距離は相手の長さ" {
  assert_eq!(levenshtein_distance("", "abc"), 3)
}

///|
test "両方空文字列の距離は0" {
  assert_eq!(levenshtein_distance("", ""), 0)
}

///|
test "逆方向の空文字列との距離は相手の長さ" {
  assert_eq!(levenshtein_distance("abc", ""), 3)
}

///|
test "隣接2文字の転置（port→prot）の距離は2" {
  assert_eq!(levenshtein_distance("port", "prot"), 2)
}

///|
test "1文字置換の距離は1" {
  assert_eq!(levenshtein_distance("cat", "car"), 1)
}

///|
test "1文字挿入の距離は1" {
  assert_eq!(levenshtein_distance("port", "ports"), 1)
}

///|
test "1文字削除の距離は1" {
  assert_eq!(levenshtein_distance("ports", "port"), 1)
}
