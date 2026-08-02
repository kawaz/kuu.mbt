// value_seat_wbtest.mbt — DR-127 W2-7: 値空間残余の座への操作 (vivify / 操作語彙 / 時系列 /
// null 補形)。conformance fixture (計画 §3 の (2)(5)) は record を名乗る builtin type が spec に
// 無いため書けない (RECB 裁定待ち) — 本ファイルの wbtest が実装側の唯一の pin。

///|
/// record を名乗るテスト型: `out` は {since: number, until: number}、parse_token は
/// "A..B" (片側省略可) を部分 range として読む — DR-127 §3.1 の parser string 経路
/// (部分 presence は parser 産出として普通の値)。
priv struct RangeSeatType {}

///|
impl @extension.TypeExt for RangeSeatType with fn name(_self) {
  "trange"
}

///|
impl @extension.TypeExt for RangeSeatType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for RangeSeatType with fn output_type(_self) {
  Some(@abi.ValueType::Record([("since", "number"), ("until", "number")]))
}

///|
impl @extension.TypeExt for RangeSeatType with fn parse_token(_self, token) {
  let chars = token.to_array()
  let mut split = -1
  for index in 0..<chars.length() {
    if index + 1 < chars.length() &&
      chars[index] == '.' &&
      chars[index + 1] == '.' {
      split = index
      break
    }
  }
  if split < 0 {
    return Err({
      disposition: @abi.RecognizedButInvalid,
      reason: "invalid-range",
      message: "trange expects A..B",
    })
  }
  let head = token[0:split].to_owned()
  let tail = token[split + 2:].to_owned()
  let fields : Array[(String, @abi.Value)] = []
  if head.length() > 0 {
    match @extension.number_type().parse_token(head) {
      Ok(value) => fields.push(("since", value))
      Err(fail) => return Err(fail)
    }
  }
  if tail.length() > 0 {
    match @extension.number_type().parse_token(tail) {
      Ok(value) => fields.push(("until", value))
      Err(fail) => return Err(fail)
    }
  }
  Ok(@abi.Object(fields))
}

///|
impl @extension.TypeExt for RangeSeatType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
/// 値残余座への out 不適合を露出させるテスト用 Value fn: number を宣言する座へ string を返す。
fn seat_registry() -> @node.Registry {
  let registry = canonical_registry()
  guard registry.register_type(RangeSeatType::{  } as &@extension.TypeExt) else {
    abort("duplicate test resident: trange")
  }
  guard registry.register_cell_fn(
    @extension.cell_fn_descriptor(
      "stringy",
      [],
      @extension.CellFnOutput::Value,
      @extension.FnFallibility::Total,
      run=fn(_, _) { Ok(@extension.FnOutput::Value(@abi.String("oops"))) },
    ),
  ) else {
    abort("duplicate test cell fn: stringy")
  }
  registry
}

///|
fn seat_ast(src : String) -> AtomicAST raise {
  match
    parse_definition(
      @json.parse(src) catch {
        _ => abort("invalid test definition JSON")
      },
      extensions=seat_registry(),
    ) {
    Ok(ast) => ast
    Err(Rejected(errors)) => {
      let detail = if errors.length() > 0 {
        errors[0].message
      } else {
        "no definition error detail"
      }
      fail("parse_definition should accept the definition: " + detail)
      panic()
    }
    Err(Malformed(message)) => {
      fail("parse_definition should accept the definition: " + message)
      panic()
    }
  }
}

///|
fn seat_view(src : String, args : Array[String]) -> String raise {
  let ast = seat_ast(src)
  let parsed = parse_legacy(ast, args)
  // 実 API (`output`) と同じ分業: effects は parse 相の binding 列 (args 順の観測)、
  // result / sources は resolve 相の勝ち binding。
  let parse_binds = match parsed {
    @engine.Success(bindings) => bindings
    other => {
      fail("should parse, got " + render_outcome(other))
      panic()
    }
  }
  let resolved = resolve_legacy(ast, parsed, args)
  let effects = match resolved {
    @engine.Success(bindings) => bindings
    other => {
      fail("should resolve, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects=parse_binds, resolved=effects)
  let eff_items : Array[String] = []
  for effect in view.effects {
    eff_items.push(wbtest_effect_address(effect))
  }
  test_sort_items(eff_items)
  "result=" +
  render_rval_sorted(view.result) +
  " sources=" +
  render_rval_sorted(view.sources) +
  " effects=" +
  test_join_comma(eff_items)
}

///|
/// resolve 相の Reject (DR-127 §4.1/§4.2 — 単枝では全体パース失敗として観測される) の
/// reason + message を返す。
fn seat_failure(src : String, args : Array[String]) -> String raise {
  let ast = seat_ast(src)
  let parsed = parse_legacy(ast, args)
  match resolve_legacy(ast, parsed, args) {
    @engine.Success(_) => {
      fail("should fail to resolve")
      panic()
    }
    @engine.Failure(failure) => {
      guard failure.errors.length() > 0 else {
        fail("failure must carry a cause (DR-127 §4.2)")
        panic()
      }
      failure.errors[0].reason + ": " + failure.errors[0].message
    }
    other => {
      fail("expected Failure, got " + render_outcome(other))
      panic()
    }
  }
}

///|
const SEAT_SRC : String =
  #|{"options":[
  #|  {"name":"tr","type":"trange","long":true},
  #|  {"name":"until","type":"string","long":true,"link":"tr.until"},
  #|  {"name":"since","type":"string","long":true,"link":"tr.since"},
  #|  {"name":"bump","long":[":incr"],"link":"tr.until"},
  #|  {"name":"clear","long":[":unset"],"link":"tr.until"},
  #|  {"name":"reset","long":[":default"],"link":"tr.until"},
  #|  {"name":"wreck","long":[":stringy"],"link":"tr.until"}
  #|]}

///|
/// DR-127 §4 時系列表 行 1: 部分書き単独 — 器 `{}` を auto-vivify して {until: X}。value_parser は
/// 起動しない (operand はフィールド側 number のパーサで読まれる、§3.2)。宣言済み欠落座 since は
/// 射影の null 補形 (DR-130 §4.1) で null、sources も同型 (§5)。= vivify 済み器と null 座の同居。
test "DR-127 §4 行1: 部分書きが器を vivify し、欠落座は null 補形" {
  assert_eq(
    seat_view(SEAT_SRC, ["--until", "5"]),
    "result={tr={since=null,until=5}} sources={tr={since=null,until=link}} effects=tr.until",
  )
}

///|
/// DR-127 §4 行 2: 座ごとの set 更新。
test "DR-127 §4 行2: 座ごとに set 更新" {
  assert_eq(
    seat_view(SEAT_SRC, ["--until", "5", "--since", "3"]),
    "result={tr={since=3,until=5}} sources={tr={since=link,until=link}} effects=tr.since,tr.until",
  )
}

///|
/// DR-127 §4 行 3: 後続の parser 産出がセル値を丸ごと置換 (部分書きは消える)。
test "DR-127 §4 行3: parser 産出の丸ごと置換" {
  assert_eq(
    seat_view(SEAT_SRC, ["--until", "9", "--tr", "1..5"]),
    "result={tr={since=1,until=5}} sources={tr={since=cli,until=cli}} effects=tr,tr.until",
  )
}

///|
/// DR-127 §4 行 4: parser 産出の上に当該の座だけ更新。
test "DR-127 §4 行4: 産出の上への座更新" {
  assert_eq(
    seat_view(SEAT_SRC, ["--tr", "1..5", "--until", "9"]),
    "result={tr={since=1,until=9}} sources={tr={since=link,until=link}} effects=tr,tr.until",
  )
}

///|
/// DR-127 §4 行 5 (DR-045 既存規則) × DR-131 §2b: 値残余座への set(null) (= unset の null Value)
/// は座を null へ戻す通常の set — 器ごと消さず、セルの committed も保つ。
test "DR-131 §2b: set(null) は座を null へ戻す (器は保つ)" {
  assert_eq(
    seat_view(SEAT_SRC, ["--tr", "1..5", "--clear"]),
    "result={tr={since=1,until=null}} sources={tr={since=link,until=link}} effects=tr,tr.until",
  )
}

///|
/// DR-131 §7 / DR-127 §3: `unset` は ctx.old を要さず null を返すため空座でも成立する。器は
/// vivify しない (set 専用) — セルは未 commit のままで、座は論理 null (DR-130 §4.1)。
test "DR-131 §7: unset は空座でも成立し器を作らない" {
  assert_eq(
    seat_view(SEAT_SRC, ["--clear"]),
    "result={tr=null} sources={tr=null} effects=tr.until",
  )
}

///|
/// DR-114 §7 / DR-127 §4.1: 器がある座への ctx.old 依存 Value fn は座の現在値を old に取る。
test "DR-127 §4.1: 器のある座への incr は座の値を old に取る" {
  assert_eq(
    seat_view(SEAT_SRC, ["--tr", "1..5", "--bump"]),
    "result={tr={since=1,until=6}} sources={tr={since=link,until=link}} effects=tr,tr.until",
  )
}

///|
/// DR-127 §3: 空の座 (未 vivify) への ctx.old 依存 Value fn の適用は解決失敗 = 枝 Reject
/// (単枝では全体パース失敗)。原因が errors に載る (§4.2 の帰属原則)。
test "DR-127 §3: 未 vivify の空座への ctx.old 依存 fn は Reject" {
  let failure = seat_failure(SEAT_SRC, ["--bump"])
  assert_true(failure.contains("invalid-range"))
  assert_true(failure.contains("ctx.old"))
}

///|
/// DR-127 §4.1 / DR-131 §7: Sentinel を返す操作 (default / empty) の値残余座への適用は
/// 発火時 Reject。
test "DR-127 §4.1: Sentinel (default) は値残余座で Reject" {
  let failure = seat_failure(SEAT_SRC, ["--reset"])
  assert_true(failure.contains("invalid-range"))
  assert_true(failure.contains("DR-127"))
}

///|
/// DR-127 §3.2: 値残余座への Value fn の戻り値もフィールド type の `out` への適合検査を通る —
/// number を宣言する座へ string を返す fn は held Error (DR-126 §4 の乖離語彙を再利用)。
test "DR-127 §3.2: fn 戻り値の out 不適合は乖離 Error" {
  let failure = seat_failure(SEAT_SRC, ["--tr", "1..5", "--wreck"])
  assert_true(failure.contains("output_shape_mismatch"))
  assert_true(failure.contains("stringy"))
}

///|
/// DR-130 §4.1 受け入れ条件: 補形はトップの record だけでなく、宣言 ValueType の中に現れる
/// record 座すべてが対象 — accumulator (multiple) の要素 record も射影で null 補形される。
test "DR-130 §4.1: multiple 要素の record も null 補形" {
  let src =
    #|{"options":[
    #|  {"name":"spans","type":"trange","multiple":true,"long":true}
    #|]}
  assert_eq(
    seat_view(src, ["--spans", "1..", "--spans", "..2"]),
    "result={spans=[{since=1,until=null},{since=null,until=2}]} sources={spans=[{since=cli,until=null},{since=null,until=cli}]} effects=spans,spans",
  )
}

///|
/// DR-127 §3.2: positional の値残余 entry も operand はフィールド側 type で読む (long / eq /
/// short と同じ差し替え)。string を宣言する entry でも着地座の number として座る。
test "DR-127 §3.2: positional residual entry の operand もフィールド type で読む" {
  let src =
    #|{"options":[
    #|  {"name":"tr","type":"trange","long":true}
    #|],"positionals":[
    #|  {"name":"deadline","type":"string","link":"tr.until"}
    #|]}
  assert_eq(
    seat_view(src, ["7"]),
    "result={tr={since=null,until=7}} sources={tr={since=null,until=link}} effects=tr.until",
  )
}

///|
/// DR-127 §3.2 の防衛線: `:set:VALUE` variant の dsl literal は entry 自身の型で decode される
/// ため、フィールド type の out に合わない値は発火時に乖離 Error になる (variant literal の
/// decode 自体をフィールド type で行う静的化は未実装 — 現行はこの実行時検査が受け止める)。
test "DR-127 §3.2: variant literal の out 不適合も発火時に乖離 Error" {
  let src =
    #|{"options":[
    #|  {"name":"tr","type":"trange","long":true},
    #|  {"name":"five","type":"string","long":[":set:five"],"link":"tr.until"}
    #|]}
  let failure = seat_failure(src, ["--five"])
  assert_true(failure.contains("output_shape_mismatch"))
}

///|
/// 確認的固定 (統括裁定 2026-08-02): effects に載る operand は**補形前の生出力のまま** —
/// null 補形 (DR-130 §4.1) が効くのは result / sources の射影面だけで、DR-126 §4 の
/// 「検査は生出力に対して」と同根。parser が until を落として返したら operand でも欠落のまま。
test "effects の operand は null 補形しない (生出力のまま)" {
  let ast = seat_ast(SEAT_SRC)
  let args = ["--tr", "1.."]
  let parse_binds = match parse_legacy(ast, args) {
    @engine.Success(bindings) => bindings
    other => {
      fail("should parse, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects=parse_binds)
  let mut seat_operand : @abi.Value? = None
  for effect in view.effects {
    if effect.entity == "tr" {
      seat_operand = effect.operand
    }
  }
  // operand は {since: 1} のまま — until キーは補形されない。result 側は補形済み。
  assert_eq(seat_operand, Some(@abi.Object([("since", @abi.Number(1))])))
  assert_eq(render_rval_sorted(view.result), "{tr={since=1,until=null}}")
}
