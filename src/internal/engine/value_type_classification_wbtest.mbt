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

///|
/// 保証: `head_progresses` は「この node の head が 1 トークン以上消費するか」の述語であり、
/// 包み (結果スコープ / 反復) は**中身に委ねる**。`Many` / `GreedyRepeat` / `BoundedTail` が
/// inner 再帰なのに `Scoped` / `ScopeNode` / `IndexedRepeat` だけ無条件 true という非対称は、
/// zero-progress 静的検査 (`collect_element_zero_progress`) に「消費する」と嘘をつく形になる。
test "head_progresses: 包み node は消費判定を中身へ委ねる (zero-progress 検査の素材)" {
  let registry : Map[String, Node] = Map([])
  let consuming = RequiredArgument("x")
  // Bind は 0 トークンの Accept — 消費 node ではない。
  let inert = Bind("k", Bool(false))
  assert_true(head_progresses(consuming, registry, []))
  assert_false(head_progresses(inert, registry, []))

  // 結果スコープの包みは中身に委ねる (包み自体は消費しない)。
  assert_true(head_progresses(Scoped("g", consuming), registry, []))
  assert_false(head_progresses(Scoped("g", inert), registry, []))

  // 名前付き indexed repeat も反復回数ではなく head の形で決まる (Many と同じ扱い)。
  assert_true(
    head_progresses(IndexedRepeat("r", consuming, 0, None), registry, []),
  )
  assert_false(
    head_progresses(IndexedRepeat("r", inert, 0, None), registry, []),
  )
  assert_eq(
    head_progresses(Many(inert, false), registry, []),
    head_progresses(IndexedRepeat("r", inert, 0, None), registry, []),
  )

  // スコープは greedy / positional のいずれかが消費すれば消費する。空スコープは 0 消費。
  let empty_scope : Scope = {
    greedy: [],
    positional: [],
    entities: [],
    constraints: [],
  }
  assert_false(head_progresses(ScopeNode(empty_scope), registry, []))
  assert_true(
    head_progresses(
      ScopeNode({ ..empty_scope, positional: [consuming] }),
      registry,
      [],
    ),
  )
  assert_true(
    head_progresses(
      ScopeNode({ ..empty_scope, greedy: [consuming] }),
      registry,
      [],
    ),
  )
  assert_false(
    head_progresses(
      ScopeNode({ ..empty_scope, positional: [inert] }),
      registry,
      [],
    ),
  )
}
