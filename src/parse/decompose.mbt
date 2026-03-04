///| 文字列の部分文字列を取得（インデックスは文字単位）
fn string_slice(s : String, start : Int, end : Int) -> String {
  let buf = StringBuilder::new()
  for idx, ch in s {
    if idx >= end {
      break
    }
    if idx >= start {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///| ロングオプション分解: "--port=8080" → ("port", Some("8080"))
///| "--verbose" → ("verbose", None)
fn decompose_long(arg : String) -> (String, String?) {
  // "--" プレフィックスを除去して "=" の位置を探す
  let mut eq_pos = -1
  for i, ch in arg {
    if i >= 2 && ch == '=' {
      eq_pos = i
      break
    }
  }
  if eq_pos >= 0 {
    let name = string_slice(arg, 2, eq_pos)
    let value = string_slice(arg, eq_pos + 1, arg.length())
    (name, Some(value))
  } else {
    let name = string_slice(arg, 2, arg.length())
    (name, None)
  }
}

///| ショートオプション分解: "-abc" → ['a', 'b', 'c']
fn decompose_short(arg : String) -> Array[Char] {
  let chars : Array[Char] = []
  for i, ch in arg {
    if i >= 1 {
      chars.push(ch)
    }
  }
  chars
}
