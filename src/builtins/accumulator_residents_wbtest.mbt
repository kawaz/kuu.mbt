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
