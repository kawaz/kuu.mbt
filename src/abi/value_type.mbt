///|
/// DR-126 §1 / DR-107 §3 value type shared by output and input declarations.
/// Record field values are registry type-reference spellings; every other nested
/// value is another value type.
pub(all) enum ValueType {
  String
  Number
  Bool
  Null
  Value
  Array(ValueType)
  Map(ValueType)
  Record(Array[(String, String)])
  Union(Array[ValueType])
} derive(Eq, Debug)

///|
fn valid_type_reference_segment(
  chars : Array[Char],
  start : Int,
  end : Int,
) -> Bool {
  if start >= end || chars[start] < 'a' || chars[start] > 'z' {
    return false
  }
  for index in start..<end {
    let char = chars[index]
    if !((char >= 'a' && char <= 'z') ||
      (char >= '0' && char <= '9') ||
      char == '_') {
      return false
    }
  }
  true
}

///|
fn valid_type_reference(spelling : String) -> Bool {
  let chars = spelling.to_array()
  let mut slash = -1
  for index, char in chars {
    if char == '/' {
      if slash >= 0 {
        return false
      }
      slash = index
    }
  }
  if slash < 0 {
    valid_type_reference_segment(chars, 0, chars.length())
  } else {
    valid_type_reference_segment(chars, 0, slash) &&
    valid_type_reference_segment(chars, slash + 1, chars.length())
  }
}

///|
fn value_type_violations(
  value_type : ValueType,
  path : String,
  out : Array[String],
) -> Unit {
  match value_type {
    String | Number | Bool | Null | Value => ()
    Array(item_type) => value_type_violations(item_type, path + ".array", out)
    Map(item_type) => value_type_violations(item_type, path + ".map", out)
    Record(fields) =>
      for index, entry in fields {
        let (field, reference) = entry
        for previous in 0..<index {
          if fields[previous].0 == field {
            out.push("record field '" + field + "' is duplicated at " + path)
            break
          }
        }
        if !valid_type_reference(reference) {
          out.push(
            "record field '" +
            field +
            "' has invalid type reference '" +
            reference +
            "' at " +
            path,
          )
        }
      }
    Union(members) => {
      if members.length() < 2 {
        out.push(
          "union has " +
          members.length().to_string() +
          " member (needs 2+) at " +
          path,
        )
      }
      for index, item_type in members {
        for previous in 0..<index {
          if members[previous] == item_type {
            out.push("union member is duplicated at " + path)
            break
          }
        }
        value_type_violations(
          item_type,
          path + ".union[" + index.to_string() + "]",
          out,
        )
      }
    }
  }
}

///|
/// Checks the code-side equivalent of the descriptor schema's value-type
/// declaration constraints and returns every violation with a structural path.
pub fn ValueType::declaration_violations(self : ValueType) -> Array[String] {
  let out : Array[String] = []
  value_type_violations(self, "$", out)
  out
}
