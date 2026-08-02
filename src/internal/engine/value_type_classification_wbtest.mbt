///|
test "value_type primitive-only classification covers every constructor" {
  // The W2-2 compatibility classifier preserves primitive residual behavior only
  // when every possible output is primitive; structural/value outputs stay opaque.
  let cases : Array[(ValueType, Bool)] = [
    (ValueType::String, true),
    (ValueType::Number, true),
    (ValueType::Bool, true),
    (ValueType::Null, true),
    (ValueType::Value, false),
    (ValueType::Array(ValueType::String), false),
    (ValueType::Map(ValueType::String), false),
    (ValueType::Record([]), false),
    (
      ValueType::Union([ValueType::Bool, ValueType::Record([("x", "string")])]),
      false,
    ),
    (
      ValueType::Union([
        ValueType::String,
        ValueType::Number,
        ValueType::Bool,
        ValueType::Null,
      ]),
      true,
    ),
  ]
  for entry in cases {
    let (value_type, expected) = entry
    assert_eq(value_type_primitive_only(value_type), expected)
  }
}

///|
test "an undeclared residual remains opaque" {
  // None means the resident makes no structural promise, so it cannot use the
  // primitive absent-reference path.
  assert_false(residual_is_primitive_only(None))
}
