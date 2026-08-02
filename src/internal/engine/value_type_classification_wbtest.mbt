///|
test "value_type primitive-only classification covers every constructor" {
  // Backs the `empty` target check: a declaration statically excludes every
  // container form only when every possible output is primitive.
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
