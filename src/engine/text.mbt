// text.mbt — shared character-array helpers for token and definition transforms.

///|
pub fn to_chars(s : String) -> Array[Char] {
  let chars : Array[Char] = []
  for char in s {
    chars.push(char)
  }
  chars
}

///|
pub fn chars_to_str(chars : Array[Char], start : Int, end : Int) -> String {
  let buffer = StringBuilder::new()
  let mut index = start
  while index < end {
    buffer.write_char(chars[index])
    index = index + 1
  }
  buffer.to_string()
}
