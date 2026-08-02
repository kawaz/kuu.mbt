///|
test "composite values nest to arbitrary depth and compare structurally" {
  // The container is the whole of W2-3: no producer builds one yet, so the only thing that can be
  // pinned is that the shape exists, nests, and that derived Eq reaches into it.
  let inner : Value = Object([("port", Number(8080.0)), ("tls", Bool(true))])
  let tree : Value = Array([inner, Null, String("tail")])
  assert_eq(
    tree,
    Array([
      Object([("port", Number(8080.0)), ("tls", Bool(true))]),
      Null,
      String("tail"),
    ]),
  )
  // Field order is part of the value: an object is a field LIST, not a map, so a permutation is a
  // different value. Two producers writing the same fields in different orders stay distinguishable.
  assert_not_eq(
    Value::Object([("a", Number(1.0)), ("b", Number(2.0))]),
    Value::Object([("b", Number(2.0)), ("a", Number(1.0))]),
  )
  // A composite is never equal to a scalar, so no existing scalar comparison silently widens.
  assert_not_eq(Value::Array([]), Value::Null)
  assert_not_eq(Value::Object([]), Value::Null)
  assert_not_eq(Value::Array([]), Value::Object([]))
}

///|
test "composite values survive the JSON round trip through ConfigVal" {
  // `value_to_configval` is the encode half and `config_from_json` the decode half; the two meeting
  // on the same tree is what says the composite shapes line up 1:1 across the JSON-isomorphic type.
  let source : Value = Object([
    ("name", String("kuu")),
    ("ports", Array([Number(80.0), Number(443.0)])),
    ("nested", Object([("deep", Array([Bool(false), Null]))])),
  ])
  let decoded = config_from_json({
    "name": "kuu",
    "ports": [80, 443],
    "nested": { "deep": [false, null] },
  })
  assert_eq(value_to_configval(source), decoded)
  // Empty containers round-trip as themselves rather than collapsing into null.
  assert_eq(value_to_configval(Array([])), config_from_json([]))
  assert_eq(value_to_configval(Object([])), config_from_json({}))
}

///|
test "value_to_configval keeps the null layers apart" {
  // DR-130 §9.1: the two Nulls spell the same after conversion, but the conversion only runs in the
  // value → config direction. `config_to_value` (extension/config_value.mbt) still refuses a config
  // null, so a config seat's "supplies nothing" cannot arrive in the value space as `null`.
  assert_eq(value_to_configval(Null), ConfigVal::Null)
  assert_eq(value_to_configval(Array([Null])), ConfigVal::Array([Null]))
}
