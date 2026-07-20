// text.mbt — character-array helpers for resident token scanning.

///|
/// Build a String from `chars[start..<end]` (half-open char-array slice).
fn chars_to_str(chars : Array[Char], start : Int, end : Int) -> String {
  let buffer = StringBuilder::new()
  let mut index = start
  while index < end {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}
