///|
test "empty target domain is closed to array / map / record (DR-131 §3.1)" {
  // `empty` は対象 collection を空にするセル操作の指示語であり、「空」が定義できる
  // 値形だけが target になれる。それ以外への宣言は definition-error `invalid-range`。
  let cases : Array[(ValueType, Bool)] = [
    (ValueType::Array(ValueType::String), true),
    (ValueType::Map(ValueType::String), true),
    (ValueType::Record([]), true),
    (ValueType::Record([("x", "string")]), true),
    // scalar に「空」は無い (ゼロ値を空と読む暗黙ルールは導入しない)。
    (ValueType::String, false),
    (ValueType::Number, false),
    (ValueType::Bool, false),
    (ValueType::Null, false),
    // 器の形を静的に言えない `value` も対象外。
    (ValueType::Value, false),
    // tuple は固定アリティなので空値を持たない (DR-137 §2)。
    (ValueType::Tuple(["int", "int"]), false),
    // union は「どの variant の空か」が決まらない — container を含んでいても不可。
    (
      ValueType::Union([ValueType::Bool, ValueType::Record([("x", "string")])]),
      false,
    ),
    (
      ValueType::Union([
        ValueType::Tuple(["int", "int", "int"]),
        ValueType::String,
      ]),
      false,
    ),
  ]
  for entry in cases {
    let (value_type, expected) = entry
    assert_eq(empty_target_type_allows(value_type), expected)
  }
}
