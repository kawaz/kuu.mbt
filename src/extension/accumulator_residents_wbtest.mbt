// accumulator_residents_wbtest.mbt — builtin fold/collect resident semantics.

///|
fn binding(
  name : String,
  op : @abi.EffectOp,
  value : @abi.Value,
  pos? : Int = 0,
) -> @abi.Binding {
  { ..@abi.Binding::new(name, value, @abi.Cli), op, at_pos: Some(pos) }
}

///|
/// append は各 set を順に保持し、CLI seat が commit した場合は lower seat を呼ばない。
test "append accumulator resident preserves set order without consulting lower seat" {
  let mut lower_calls = 0
  let lower : LowerSeat = fn(_include_default) {
    lower_calls = lower_calls + 1
    Ok([@abi.Binding::new("x", @abi.String("lower"), @abi.Default)])
  }
  let resident = append_accumulator()
  let result = resident.resolve_cli(
    "x",
    [
      binding("x", @abi.Set, @abi.String("a")),
      binding("x", @abi.Set, @abi.String("b")),
    ],
    true,
    lower,
  )
  match result {
    Ok(bindings) => {
      assert_eq(bindings.length(), 2)
      assert_eq(bindings[0].value, @abi.String("a"))
      assert_eq(bindings[1].value, @abi.String("b"))
      assert_eq(lower_calls, 0)
    }
    Err(_) => fail("append fold must succeed")
  }
}

///|
/// merge は同一 token の remove/splice/add を一発火として扱い、old=[a,b] から a を除いて c を足す。
test "merge accumulator resident owns grouped remove splice add semantics" {
  let lower : LowerSeat = fn(_include_default) {
    Ok([
      @abi.Binding::new("x", @abi.String("a"), @abi.Default),
      @abi.Binding::new("x", @abi.String("b"), @abi.Default),
    ])
  }
  let result = merge_accumulator().resolve_cli(
    "x",
    [
      binding("x", @abi.Remove, @abi.String("a"), pos=1),
      binding("x", @abi.Splice, @abi.Bool(false), pos=1),
      binding("x", @abi.Set, @abi.String("c"), pos=1),
    ],
    true,
    lower,
  )
  match result {
    Ok(bindings) => {
      assert_eq(bindings.length(), 2)
      assert_eq(bindings[0].value, @abi.String("b"))
      assert_eq(bindings[1].value, @abi.String("c"))
    }
    Err(_) => fail("merge fold must succeed")
  }
}

///|
/// kv_map の collect は first `=` split と同一 key のあと勝ちを resident 自身で行う。
test "kv_map accumulator resident collects values into a last-wins object" {
  let result = kv_map_accumulator().collect([
    @abi.String("A=1"),
    @abi.String("B=2"),
    @abi.String("A=3"),
  ])
  assert_eq(
    result,
    @abi.Object([
      ("A", @abi.Scalar(@abi.String("3"))),
      ("B", @abi.Scalar(@abi.String("2"))),
    ]),
  )
}

///|
/// unwrap_single は単一配列を再帰的に scalar へ縮退し、複数要素配列は配列形を保つ。
test "unwrap_single collector resident recursively unwraps only singleton arrays" {
  let result = unwrap_single_collector().collect(
    @abi.Object([
      ("one", @abi.Array([@abi.Scalar(@abi.String("x"))])),
      (
        "many",
        @abi.Array([
          @abi.Scalar(@abi.String("a")),
          @abi.Scalar(@abi.String("b")),
        ]),
      ),
    ]),
  )
  assert_eq(
    result,
    @abi.Object([
      ("one", @abi.Scalar(@abi.String("x"))),
      (
        "many",
        @abi.Array([
          @abi.Scalar(@abi.String("a")),
          @abi.Scalar(@abi.String("b")),
        ]),
      ),
    ]),
  )
}

///|
/// from_entries の無引数 resident は 2 要素配列の列を object へ変換する。
test "from_entries collector resident converts entry pairs into an object" {
  let result = from_entries_collector(Entries).collect(
    @abi.Array([
      @abi.Array([@abi.Scalar(@abi.String("a")), @abi.Scalar(@abi.Number(1.0))]),
      @abi.Array([@abi.Scalar(@abi.String("b")), @abi.Scalar(@abi.Number(2.0))]),
    ]),
  )
  assert_eq(
    result,
    @abi.Object([
      ("a", @abi.Scalar(@abi.Number(1.0))),
      ("b", @abi.Scalar(@abi.Number(2.0))),
    ]),
  )
}

///|
test "from_entries collector encodes the three canonical argument forms" {
  assert_eq(from_entries_collector(Entries).encode(), "entries".to_json())
  assert_eq(
    from_entries_collector(KeyValue("k", "v")).encode(),
    ["k", "v"].to_json(),
  )
  assert_eq(
    from_entries_collector(KeyPromote("path")).encode(),
    "path".to_json(),
  )
}

///|
test "from_entries keeps nonconforming arrays and missing named fields" {
  let one_item : @abi.ResultValue = @abi.Array([
    @abi.Array([@abi.Scalar(@abi.String("a"))]),
  ])
  assert_eq(from_entries_collector(Entries).collect(one_item), one_item)
  let missing_value : @abi.ResultValue = @abi.Array([
    @abi.Object([("k", @abi.Scalar(@abi.String("a")))]),
  ])
  assert_eq(
    from_entries_collector(KeyValue("k", "v")).collect(missing_value),
    missing_value,
  )
  assert_eq(
    from_entries_collector(Entries).collect(@abi.Array([])),
    @abi.Array([]),
  )
}

///|
test "from_entries stringifies every representable non-string result key" {
  let result = from_entries_collector(Entries).collect(
    @abi.Array([
      @abi.Array([
        @abi.Scalar(@abi.Number(1.0)),
        @abi.Scalar(@abi.String("number")),
      ]),
      @abi.Array([
        @abi.Scalar(@abi.Bool(true)),
        @abi.Scalar(@abi.String("bool")),
      ]),
      @abi.Array([
        @abi.Array([
          @abi.Scalar(@abi.Number(1.0)),
          @abi.Scalar(@abi.Bool(false)),
        ]),
        @abi.Scalar(@abi.String("array")),
      ]),
      @abi.Array([
        @abi.Object([
          ("x", @abi.Scalar(@abi.Number(1.0))),
          ("ok", @abi.Scalar(@abi.Bool(true))),
        ]),
        @abi.Scalar(@abi.String("object")),
      ]),
    ]),
  )
  assert_eq(
    result,
    @abi.Object([
      ("1", @abi.Scalar(@abi.String("number"))),
      ("true", @abi.Scalar(@abi.String("bool"))),
      ("[1,false]", @abi.Scalar(@abi.String("array"))),
      ("{\"x\":1,\"ok\":true}", @abi.Scalar(@abi.String("object"))),
    ]),
  )
}

///|
test "from_entries preserves duplicate keys and key-promote empty objects" {
  assert_eq(
    from_entries_collector(Entries).collect(
      @abi.Array([
        @abi.Array([
          @abi.Scalar(@abi.String("a")),
          @abi.Scalar(@abi.Number(1.0)),
        ]),
        @abi.Array([
          @abi.Scalar(@abi.String("a")),
          @abi.Scalar(@abi.Number(2.0)),
        ]),
      ]),
    ),
    @abi.Object([
      ("a", @abi.Scalar(@abi.Number(1.0))),
      ("a", @abi.Scalar(@abi.Number(2.0))),
    ]),
  )
  assert_eq(
    from_entries_collector(KeyPromote("key")).collect(
      @abi.Array([@abi.Object([("key", @abi.Scalar(@abi.String("a")))])]),
    ),
    @abi.Object([("a", @abi.Object([]))]),
  )
}

// ── DR-080 merge accumulator: §4 の canonical 例 ────────────────────────────

///|
/// DR-080 §4 の canonical 表を検証する共通ヘルパー。マーカーなしの発火は piece 列で
/// cell を上書きし、マーカーを含む発火は暗黙先頭 `@` を補って old と合成する。
fn merge_fire(
  pieces : Array[MergeMark],
  old : Array[@abi.Value],
) -> Array[@abi.Value] {
  if merge_pieces_has_no_marker(pieces) {
    let out : Array[@abi.Value] = []
    for p in pieces {
      match p {
        MAdd(v) => out.push(v)
        _ =>
          abort(
            "unreachable: merge_pieces_has_no_marker already filtered non-MAdd",
          )
      }
    }
    out
  } else {
    eval_merge_pieces(merge_pieces_with_implicit_splice(pieces), old)
  }
}

///|
fn vs(s : String) -> @abi.Value {
  @abi.String(s)
}

///|
/// 保証: DR-080 §4 canonical 表 (old = 直前発火の `[a,a,b,a,c]`) の1行目「マーカーなし = 上書き」。
/// `-f a,a,b,a,c` 単独発火は merge モードに入らず、piece 列そのものが結果になる。
test "DR-080 merge: no-marker fire overwrites the cell (canonical row 1)" {
  let pieces = [
    MAdd(vs("a")),
    MAdd(vs("a")),
    MAdd(vs("b")),
    MAdd(vs("a")),
    MAdd(vs("c")),
  ]
  assert_eq(merge_fire(pieces, []), [
    vs("a"),
    vs("a"),
    vs("b"),
    vs("a"),
    vs("c"),
  ])
}

///|
/// 保証 (canonical 表 2行目): 明示 `@` 単独発火は old をそのまま splice する (恒等)。
test "DR-080 merge: explicit @ alone splices old verbatim (canonical row 2)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MSplice], old), old)
}

///|
/// 保証 (canonical 表 3行目): remove のみの発火は暗黙先頭 `@` + 後方 remove として評価される。
test "DR-080 merge: remove-only fire is implicit-@ + trailing remove (canonical row 3)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a"))], old), [vs("b"), vs("c")])
}

///|
/// 保証 (canonical 表 4行目): 前置 remove が両方の `@` の splice 内容に効く — `seen_removes` が
/// 発火全体を通じて蓄積されることの直接証拠 (2 つの @ が同じフィルタ結果になる)。
test "DR-080 merge: a leading remove filters every subsequent splice (canonical row 4)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MSplice, MSplice], old), [
    vs("b"),
    vs("c"),
    vs("b"),
    vs("c"),
  ])
}

///|
/// 保証 (canonical 表 5行目): マーカーなし発火は何度でも単純上書き (old は完全に無視される)。
test "DR-080 merge: a second no-marker fire overwrites again, ignoring old (canonical row 5)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  let pieces = [MAdd(vs("d"))]
  assert_eq(merge_fire(pieces, old), [vs("d")])
}

///|
/// 保証 (canonical 表 6行目): `-a,@` (remove の後に明示 @) — remove 後の @ splice はフィルタ済み。
test "DR-080 merge: remove then explicit @ (canonical row 6)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MSplice], old), [vs("b"), vs("c")])
}

///|
/// 保証 (canonical 表 7行目): remove → @ → add — remove 後に追加された add は削除フィルタを
/// 受けない (「remove はそれ以後の add には効かない」の直接証拠)。
test "DR-080 merge: an add AFTER remove survives untouched (canonical row 7)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MSplice, MAdd(vs("a"))], old), [
    vs("b"),
    vs("c"),
    vs("a"),
  ])
}

///|
/// 保証 (canonical 表 8行目): remove → @ → add → remove — 後置 remove は「その時点までの
/// work_list」(add で加わった要素も含む) に効く。
test "DR-080 merge: a trailing remove strips a previously-surviving add (canonical row 8)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(
    merge_fire(
      [MRemove(vs("a")), MSplice, MAdd(vs("a")), MRemove(vs("a"))],
      old,
    ),
    [vs("b"), vs("c")],
  )
}

///|
/// 保証 (canonical 表 9行目): `-a,d` — 暗黙先頭 @ の後に remove、その後 add。
test "DR-080 merge: implicit @ + remove + add (canonical row 9)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MAdd(vs("d"))], old), [
    vs("b"),
    vs("c"),
    vs("d"),
  ])
}

///|
/// 保証 (canonical 表 10行目): `@,-a,@` — remove が「それより前にある @」にも効く (splice
/// フィルタは remove の位置に関わらず、その @ の評価時点で `seen_removes` に入っているかで決まる)。
/// `-a,@,@` (canonical 表 4行目) と同値になることを固定する。
test "DR-080 merge: @,-a,@ equals -a,@,@ (canonical row 10)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MSplice, MRemove(vs("a")), MSplice], old), [
    vs("b"),
    vs("c"),
    vs("b"),
    vs("c"),
  ])
}

///|
/// 保証 (canonical 表 11行目): `@,-a,a` — `-a,@,a` (canonical 表 7行目) と同値。
test "DR-080 merge: @,-a,a equals -a,@,a (canonical row 11)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MSplice, MRemove(vs("a")), MAdd(vs("a"))], old), [
    vs("b"),
    vs("c"),
    vs("a"),
  ])
}

///|
/// 保証 (canonical 表 12行目): 初回発火 (old = []) の `a,-a` — 暗黙 @ で old=[] を展開後、
/// add した "a" 自身を後続 remove が削除する。
test "DR-080 merge: first fire (old=[]) a,-a nets to empty (canonical row 12)" {
  assert_eq(merge_fire([MAdd(vs("a")), MRemove(vs("a"))], []), [])
}

///|
/// 保証 (canonical 表 13行目): 初回発火 (old = []) の `-a,a` — remove が先でも、その後の add は
/// 生き残る (remove はそれ以後の add に効かない)。
test "DR-080 merge: first fire (old=[]) -a,a keeps the trailing add (canonical row 13)" {
  assert_eq(merge_fire([MRemove(vs("a")), MAdd(vs("a"))], []), [vs("a")])
}
