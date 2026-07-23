// merge_piece.mbt — classified merge operands consumed by the evaluator.

///|
pub(all) enum PieceMark {
  Add(String)
  Remove(String)
  Splice
} derive(Eq, Debug)

///|
pub fn classify_merge_piece(s : String) -> PieceMark {
  if s == "@" {
    return Splice
  }
  let chars : Array[Char] = []
  for char in s {
    chars.push(char)
  }
  if chars.length() > 0 && chars[0] == '-' {
    return Remove(chars_from(chars, 1))
  }
  if chars.length() >= 2 &&
    chars[0] == '+' &&
    (chars[1] == '-' || chars[1] == '@' || chars[1] == '+') {
    return Add(chars_from(chars, 1))
  }
  Add(s)
}

///|
fn chars_from(chars : Array[Char], start : Int) -> String {
  let buffer = StringBuilder::new()
  for index in start..<chars.length() {
    buffer.write_char(chars[index])
  }
  buffer.to_string()
}
