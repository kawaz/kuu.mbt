// merge_piece.mbt — classified merge operands consumed by the evaluator.

///|
pub(all) enum PieceMark {
  PkAdd(String)
  PkRemove(String)
  PkSplice
} derive(Eq, Debug)

///|
pub fn classify_merge_piece(s : String) -> PieceMark {
  if s == "@" {
    return PkSplice
  }
  let chars : Array[Char] = []
  for char in s {
    chars.push(char)
  }
  if chars.length() > 0 && chars[0] == '-' {
    return PkRemove(chars_from(chars, 1))
  }
  if chars.length() >= 2 &&
    chars[0] == '+' &&
    (chars[1] == '-' || chars[1] == '@' || chars[1] == '+') {
    return PkAdd(chars_from(chars, 1))
  }
  PkAdd(s)
}

///|
fn chars_from(chars : Array[Char], start : Int) -> String {
  let buffer = StringBuilder::new()
  for index in start..<chars.length() {
    buffer.write_char(chars[index])
  }
  buffer.to_string()
}
