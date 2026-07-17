// accumulator_residents_wbtest.mbt — builtin fold/collect resident semantics.

///|
fn binding(
  name : String,
  op : @engine.EffectOp,
  value : @engine.Value,
  pos? : Int = 0,
) -> @engine.Binding {
  { ..@engine.mkb(name, value, @engine.Cli), op, at_pos: Some(pos) }
}

///|
/// append は各 set を順に保持し、CLI seat が commit した場合は lower seat を呼ばない。
test "append accumulator resident preserves set order without consulting lower seat" {
  let mut lower_calls = 0
  let lower : @engine.LowerSeat = fn(_include_default) {
    lower_calls = lower_calls + 1
    Ok([@engine.mkb("x", @engine.VStr("lower"), @engine.Default)])
  }
  let resident = append_accumulator()
  let result = resident.resolve_cli(
    "x",
    [
      binding("x", @engine.Set, @engine.VStr("a")),
      binding("x", @engine.Set, @engine.VStr("b")),
    ],
    true,
    lower,
  )
  match result {
    Ok(bindings) => {
      assert_eq(bindings.length(), 2)
      assert_eq(bindings[0].value, @engine.VStr("a"))
      assert_eq(bindings[1].value, @engine.VStr("b"))
      assert_eq(lower_calls, 0)
    }
    Err(_) => fail("append fold must succeed")
  }
}

///|
/// merge は同一 token の remove/splice/add を一発火として扱い、old=[a,b] から a を除いて c を足す。
test "merge accumulator resident owns grouped remove splice add semantics" {
  let lower : @engine.LowerSeat = fn(_include_default) {
    Ok([
      @engine.mkb("x", @engine.VStr("a"), @engine.Default),
      @engine.mkb("x", @engine.VStr("b"), @engine.Default),
    ])
  }
  let result = merge_accumulator().resolve_cli(
    "x",
    [
      binding("x", @engine.Remove, @engine.VStr("a"), pos=1),
      binding("x", @engine.Splice, @engine.VBool(false), pos=1),
      binding("x", @engine.Set, @engine.VStr("c"), pos=1),
    ],
    true,
    lower,
  )
  match result {
    Ok(bindings) => {
      assert_eq(bindings.length(), 2)
      assert_eq(bindings[0].value, @engine.VStr("b"))
      assert_eq(bindings[1].value, @engine.VStr("c"))
    }
    Err(_) => fail("merge fold must succeed")
  }
}

///|
/// kv_map の collect は first `=` split と同一 key のあと勝ちを resident 自身で行う。
test "kv_map accumulator resident collects values into a last-wins object" {
  let result = kv_map_accumulator().collect([
    @engine.VStr("A=1"),
    @engine.VStr("B=2"),
    @engine.VStr("A=3"),
  ])
  assert_eq(
    result,
    @engine.RObj([
      ("A", @engine.RScalar(@engine.VStr("3"))),
      ("B", @engine.RScalar(@engine.VStr("2"))),
    ]),
  )
}

///|
/// unwrap_single は単一配列を再帰的に scalar へ縮退し、複数要素配列は配列形を保つ。
test "unwrap_single collector resident recursively unwraps only singleton arrays" {
  let result = unwrap_single_collector().collect(
    @engine.RObj([
      ("one", @engine.RArr([@engine.RScalar(@engine.VStr("x"))])),
      (
        "many",
        @engine.RArr([
          @engine.RScalar(@engine.VStr("a")),
          @engine.RScalar(@engine.VStr("b")),
        ]),
      ),
    ]),
  )
  assert_eq(
    result,
    @engine.RObj([
      ("one", @engine.RScalar(@engine.VStr("x"))),
      (
        "many",
        @engine.RArr([
          @engine.RScalar(@engine.VStr("a")),
          @engine.RScalar(@engine.VStr("b")),
        ]),
      ),
    ]),
  )
}

///|
/// from_entries の無引数 resident は 2 要素配列の列を object へ変換する。
test "from_entries collector resident converts entry pairs into an object" {
  let result = from_entries_collector(Entries).collect(
    @engine.RArr([
      @engine.RArr([
        @engine.RScalar(@engine.VStr("a")),
        @engine.RScalar(@engine.VNum(1.0)),
      ]),
      @engine.RArr([
        @engine.RScalar(@engine.VStr("b")),
        @engine.RScalar(@engine.VNum(2.0)),
      ]),
    ]),
  )
  assert_eq(
    result,
    @engine.RObj([
      ("a", @engine.RScalar(@engine.VNum(1.0))),
      ("b", @engine.RScalar(@engine.VNum(2.0))),
    ]),
  )
}

// ── DR-080 merge accumulator: §4 の canonical 例 ────────────────────────────

///|
/// DR-080 §4 の canonical 表を検証する共通ヘルパー。マーカーなしの発火は piece 列で
/// cell を上書きし、マーカーを含む発火は暗黙先頭 `@` を補って old と合成する。
fn merge_fire(
  pieces : Array[MergeMark],
  old : Array[@engine.Value],
) -> Array[@engine.Value] {
  if merge_pieces_has_no_marker(pieces) {
    let out : Array[@engine.Value] = []
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
fn vs(s : String) -> @engine.Value {
  @engine.VStr(s)
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
