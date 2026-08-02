///|
test "value_type record declarations enforce only wire-equivalent constraints" {
  // JSON objects cannot carry duplicate keys, so code-side records reject them;
  // field names themselves remain unconstrained because the schema has no propertyNames rule.
  assert_eq(ValueType::Record([("", "string")]).declaration_violations(), [])
  assert_true(
    ValueType::Record([("x", "string"), ("x", "number")])
    .declaration_violations()
    .length() >
    0,
  )
}

///|
test "value_type reference spelling matches the descriptor schema pattern" {
  // Bare, builtin-qualified, and extension-qualified names are valid; uppercase,
  // punctuation, leading digits, and multi-level namespaces are separate invalid classes.
  for spelling in ["string", "builtin/number", "myapp/foo", "a0_b/c2_d"] {
    assert_eq(ValueType::Record([("x", spelling)]).declaration_violations(), [])
  }
  for spelling in ["", "Bad", "bad-name", "1bad", "a/b/c", "/bad", "bad/"] {
    assert_true(
      ValueType::Record([("x", spelling)]).declaration_violations().length() > 0,
    )
  }
}

///|
test "value_type unions preserve nesting while enforcing size and uniqueness" {
  // Union members cover the entire value_type grammar, including another union;
  // only minItems and structural uniqueItems constrain the declaration.
  let nested = ValueType::Union([
    ValueType::Bool,
    ValueType::Union([ValueType::String, ValueType::Null]),
  ])
  assert_eq(nested.declaration_violations(), [])
  assert_true(ValueType::Union([]).declaration_violations().length() > 0)
  assert_true(
    ValueType::Union([ValueType::Bool, ValueType::Bool])
    .declaration_violations()
    .length() >
    0,
  )
}
