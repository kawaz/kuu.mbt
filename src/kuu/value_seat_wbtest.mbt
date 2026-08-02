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
/// array を名乗るテスト型: `out` は number の array、parse_token はカンマ区切り数値列。
/// W2-8 の実行時 index 解決 (DR-127 §2.2 array 行の実行時列) の対象セルを作る。
priv struct CsvSeatType {}

///|
impl @extension.TypeExt for CsvSeatType with fn name(_self) {
  "csv"
}

///|
impl @extension.TypeExt for CsvSeatType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for CsvSeatType with fn output_type(_self) {
  Some(@abi.ValueType::Array(@abi.ValueType::Number))
}

///|
impl @extension.TypeExt for CsvSeatType with fn parse_token(_self, token) {
  let items : Array[@abi.Value] = []
  for piece in token.split(",") {
    match @extension.number_type().parse_token(piece.to_owned()) {
      Ok(value) => items.push(value)
      Err(fail) => return Err(fail)
    }
  }
  Ok(@abi.Array(items))
}

///|
impl @extension.TypeExt for CsvSeatType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
/// map を名乗るテスト型: `out` は number 値の map、parse_token は `k=v` のカンマ区切り。
/// W2-8 の実行時キー解決 (DR-127 §2.2 map 行 — 以降の segment は全て実行時) の対象セルを作る。
priv struct DictSeatType {}

///|
impl @extension.TypeExt for DictSeatType with fn name(_self) {
  "dict"
}

///|
impl @extension.TypeExt for DictSeatType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for DictSeatType with fn output_type(_self) {
  Some(@abi.ValueType::Map(@abi.ValueType::Number))
}

///|
impl @extension.TypeExt for DictSeatType with fn parse_token(_self, token) {
  let fields : Array[(String, @abi.Value)] = []
  for piece in token.split(",") {
    let entry = piece.to_owned()
    let mut split = -1
    for index in 0..<entry.length() {
      if entry[index] == '=' {
        split = index
        break
      }
    }
    if split < 0 {
      return Err({
        disposition: @abi.RecognizedButInvalid,
        reason: "invalid-range",
        message: "dict expects k=v pairs",
      })
    }
    match @extension.number_type().parse_token(entry[split + 1:].to_owned()) {
      Ok(value) => fields.push((entry[0:split].to_owned(), value))
      Err(fail) => return Err(fail)
    }
  }
  Ok(@abi.Object(fields))
}

///|
impl @extension.TypeExt for DictSeatType with fn default_seat_resolver(
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
  guard registry.register_type(CsvSeatType::{  } as &@extension.TypeExt) else {
    abort("duplicate test resident: csv")
  }
  guard registry.register_type(DictSeatType::{  } as &@extension.TypeExt) else {
    abort("duplicate test resident: dict")
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
  // 監査 M2 用: ctx.old を読んでから null を返す Value fn — 空座で「old を要する」と
  // 「null 返し (unset 形)」が交差するケースを露出させる。
  guard registry.register_cell_fn(
    @extension.cell_fn_descriptor(
      "peeky",
      [],
      @extension.CellFnOutput::Value,
      @extension.FnFallibility::Total,
      run=fn(_, ctx) {
        let _ = ctx.old()
        Ok(@extension.FnOutput::Value(@abi.Null))
      },
    ),
  ) else {
    abort("duplicate test cell fn: peeky")
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
  // DR-045: 効果は args 出現順の操作列 — effects の表明は sort せず順序込みで行う
  // (統括裁定 2026-08-02、時系列 test の観測面)。
  let eff_items : Array[String] = []
  for effect in view.effects {
    eff_items.push(wbtest_effect_address(effect))
  }
  "result=" +
  render_rval_sorted(view.result) +
  " sources=" +
  render_rval_sorted(view.sources) +
  " effects=" +
  test_join_comma(eff_items)
}

///|
/// 解決失敗 (DR-127 §4.1/§4.2 — 単枝では全体パース失敗として観測される) の reason + message を
/// 返す。値残余の解決失敗は裁定前の枝ローカル fold (§4.2、parse 相) が合成 ParseError で受け、
/// 乖離検査 (§3.2) など経路解決以外の失敗は従来どおり resolve 相の Err として現れる —
/// どちらも Failure に落ちるので、本ヘルパーは両位相を同じ形で観測する。
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
      // 全 error を結合して返す — 全枝落ちでは枝ごとの失敗理由が並ぶ (DR-053 §2 全保持) ため、
      // 先頭 1 件だけ見ると合成 ParseError (DR-127 §4.2) を見落とす。
      let parts : Array[String] = []
      for e in failure.errors {
        parts.push(e.reason + ": " + e.message)
      }
      test_join_comma(parts)
    }
    other => {
      fail("expected Failure, got " + render_outcome(other))
      panic()
    }
  }
}

///|
/// `seat_failure` の args_pos 付き変種 — 合成 ParseError の帰属 (DR-037 / DR-127 §4.2) を pin する。
fn seat_failure_pos(src : String, args : Array[String]) -> String raise {
  let ast = seat_ast(src)
  let parsed = parse_legacy(ast, args)
  match resolve_legacy(ast, parsed, args) {
    @engine.Failure(failure) => {
      guard failure.errors.length() > 0 else {
        fail("failure must carry a cause (DR-127 §4.2)")
        panic()
      }
      failure.errors[0].reason +
      ": " +
      failure.errors[0].message +
      " @" +
      failure.errors[0].args_pos.to_string()
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
  #|  {"name":"until","type":"string","long":true,"short":"u","link":"tr.until"},
  #|  {"name":"since","type":"string","long":true,"link":"tr.since"},
  #|  {"name":"bump","long":[":incr"],"link":"tr.until"},
  #|  {"name":"clear","long":[":unset"],"link":"tr.until"},
  #|  {"name":"reset","long":[":default"],"link":"tr.until"},
  #|  {"name":"wreck","long":[":stringy"],"link":"tr.until"},
  #|  {"name":"seven","long":[":set:7"],"link":"tr.until"},
  #|  {"name":"peek","long":[":peeky"],"link":"tr.until"}
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
    "result={tr={since=3,until=5}} sources={tr={since=link,until=link}} effects=tr.until,tr.since",
  )
}

///|
/// DR-127 §4 行 3: 後続の parser 産出がセル値を丸ごと置換 (部分書きは消える)。
test "DR-127 §4 行3: parser 産出の丸ごと置換" {
  assert_eq(
    seat_view(SEAT_SRC, ["--until", "9", "--tr", "1..5"]),
    "result={tr={since=1,until=5}} sources={tr={since=cli,until=cli}} effects=tr.until,tr",
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
    "result={tr={since=1,until=null}} sources={tr={since=link,until=null}} effects=tr,tr.until",
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
/// DR-127 §3: 空の座 (未 vivify) への ctx.old 依存 Value fn の適用は解決失敗 = 枝 Reject。
/// 判定は裁定前の枝ローカル fold (§4.2) が持ち、単枝では全体パース失敗として観測される —
/// 原因が合成 ParseError として errors に載る (§4.2 の合成義務)。
test "DR-127 §3: 未 vivify の空座への ctx.old 依存 fn は Reject" {
  let failure = seat_failure(SEAT_SRC, ["--bump"])
  assert_true(failure.contains("unresolvable_link_path"))
  assert_true(failure.contains("ctx.old"))
}

///|
/// DR-127 §4.1 / DR-131 §7: Sentinel を返す操作 (default / empty) の値残余座への適用は
/// 発火時 Reject。
test "DR-127 §4.1: Sentinel (default) は値残余座で Reject" {
  let failure = seat_failure(SEAT_SRC, ["--reset"])
  assert_true(failure.contains("unresolvable_link_path"))
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

///|
/// 監査 M2 (DR-127 §3): 空の座で `ctx.old()` を読んだ Value fn は、戻り値が null でも Reject —
/// 「ctx.old を要する」の判定は参照事実で、返した値が偶然成立形 (unset の null) と同綴りでも
/// Reject の理由は消えない。器がある座では同じ fn が成立する (交差の pin)。
test "DR-127 §3: old を読んで null を返す fn も空座では Reject" {
  let failure = seat_failure(SEAT_SRC, ["--peek"])
  assert_true(failure.contains("unresolvable_link_path"))
  assert_true(failure.contains("ctx.old"))
  // 器があれば同じ fn は成立する (null を座へ書く = set(null) と同じ着地)。
  assert_eq(
    seat_view(SEAT_SRC, ["--tr", "1..5", "--peek"]),
    "result={tr={since=1,until=null}} sources={tr={since=link,until=null}} effects=tr,tr.until",
  )
}

///|
/// 監査 M3 (DR-127 §3.2): `:set:VALUE` variant の literal も**フィールド側 type の
/// pieceProcessor を実際に通す** — string を宣言する entry の `:set:7` が着地座の number
/// パーサで読まれて Number(7) として座る (out 適合検査は parser 実行の代替ではない)。
test "DR-127 §3.2: variant literal はフィールド type のパーサで decode される" {
  assert_eq(
    seat_view(SEAT_SRC, ["--seven"]),
    "result={tr={since=null,until=7}} sources={tr={since=null,until=link}} effects=tr.until",
  )
}

///|
/// 監査 M4 (DR-126 §1): フィールド参照が指すのは registry の canonical 実体そのもの —
/// definitions.types の shadow (送信元 entry の parse 設定) をフィールド type へ再適用しない。
/// 送信元の "number" は base prefix opt-in で "0x10" を読めるが、着地座の canonical number は
/// 同じ literal を拒否する。
test "DR-126 §1: 送信元 type の shadow/config はフィールド type に再適用しない" {
  let src =
    #|{"definitions":{"types":{
    #|  "number":{"name":"number_parser","config":{"number_allow_base_prefix":true}}
    #|}},"options":[
    #|  {"name":"tr","type":"trange","long":true},
    #|  {"name":"plain","type":"number","long":true},
    #|  {"name":"hexy","type":"number","long":true,"link":"tr.until"}
    #|]}
  let ast = seat_ast(src)
  // 送信元世界の sanity: shadow された number は base-prefixed literal を読める。
  match parse_legacy(ast, ["--plain", "0x10"]) {
    @engine.Success(_) => ()
    other => {
      fail(
        "the shadowed sender number must accept 0x10, got " +
        render_outcome(other),
      )
      panic()
    }
  }
  // 着地座の canonical number (registry 実体、DR-126 §1: shadow されない) は同じ literal を拒否。
  match parse_legacy(ast, ["--hexy", "0x10"]) {
    @engine.Success(_) =>
      fail("the canonical field number must reject a base-prefixed literal")
    _ => ()
  }
}

///|
/// 監査 m1 (DR-127 §3.2): eq-split / short cluster 入口でも parser identity の差し替えが
/// 観測できる — string を宣言する entry の operand が着地座の number として座る。
test "DR-127 §3.2: eq / short 入口でもフィールド type で読む" {
  let expected = "result={tr={since=null,until=5}} sources={tr={since=null,until=link}} effects=tr.until"
  assert_eq(seat_view(SEAT_SRC, ["--until=5"]), expected)
  assert_eq(seat_view(SEAT_SRC, ["-u", "5"]), expected)
}

// ── W2-8: DR-127 §4.2 裁定前の枝ローカル効果列 fold ─────────────────────────────

///|
/// 同じ綴り `--u` に operand 形 (`:set`) と bare 形 (`:incr`) が同居し、余りトークンは
/// positional `rest` が吸えるため、`--u 5` は option-positional 境界をまたぐ 2 解釈になる
/// (DESIGN §15.4 の real ambiguous の形)。片方の枝だけが値残余の解決に失敗する非対称を作る。
const BRANCH_SRC : String =
  #|{"options":[
  #|  {"name":"tr","type":"trange","long":true},
  #|  {"name":"u","type":"string","long":[":set",":incr"],"link":"tr.until"}],
  #| "positionals":[{"name":"rest","type":"string","repeat":{"min":0}}]}

///|
/// DR-127 §4.2: 裁定は枝ローカルの効果列 fold の後に来る。`--u 5` の 2 解釈のうち bare `:incr`
/// 枝は空座 (未 vivify) への ctx.old 依存 fn で解決失敗 = 枝 Reject となり、operand `:set` 枝
/// (座へ 5 を書く) が勝つ — Ambiguous にも Failure にもならない (DR-127 §4 / DR-029)。
test "DR-127 §4.2: 値残余 Reject の枝が落ち、兄弟枝が勝つ" {
  assert_eq(
    seat_view(BRANCH_SRC, ["--u", "5"]),
    "result={rest=[],tr={since=null,until=5}} sources={rest=[],tr={since=null,until=link}} effects=tr.until",
  )
}

///|
/// 全枝落ちの対照: `--u` 単独は bare `:incr` の 1 解釈しか無く、その枝が値残余の解決失敗で
/// 落ちると完全経路 0 件 = 全体パース失敗。合成 ParseError が errors に載る (§4.2 の合成義務)。
test "DR-127 §4.2: 全枝が落ちれば全体パース失敗 + 原因の合成" {
  let failure = seat_failure(BRANCH_SRC, ["--u"])
  assert_true(failure.contains("unresolvable_link_path"))
  assert_true(failure.contains("ctx.old"))
}

///|
/// map セルの実行時キー解決 (DR-127 §2.2 map 行)。`--m a=1` の産出に存在するキーへの部分書きは
/// 成立し (§3: 座が実在すれば書ける)、存在しないキーは枝 Reject。
const MAP_SRC : String =
  #|{"options":[
  #|  {"name":"m","type":"dict","long":true},
  #|  {"name":"wa","type":"number","long":true,"link":"m.a"},
  #|  {"name":"wz","type":"number","long":[":set",":incr"],"link":"m.zzz"}],
  #| "positionals":[{"name":"rest","type":"string","repeat":{"min":0}}]}

///|
test "DR-127 §2.2 map: 実在するキーの座への部分書きは成立する" {
  assert_eq(
    seat_view(MAP_SRC, ["--m", "a=1", "--wa", "5"]),
    "result={m={a=5},rest=[]} sources={m={a=link},rest=[]} effects=m,m.a",
  )
}

///|
/// map キー不在は operand 形 (`set` の書き先不在) と bare 形 (`incr` の書き先不在) の両解釈で
/// 解決失敗 — 全枝が落ち、失敗レポートに座の診断 (missing-field) が載る。
test "DR-127 §2.2 map: キー不在は枝 Reject、全枝落ちで原因が載る" {
  let failure = seat_failure(MAP_SRC, ["--m", "a=1", "--wz", "5"])
  assert_true(failure.contains("unresolvable_link_path"))
  assert_true(failure.contains("missing-field:zzz"))
}

///|
/// array セルの実行時 index 解決 (DR-127 §1 / §2.2 array 行)。負 index は発火時点の現在長で
/// 確定する — `--arr 1,2,3` の後の `[-1]` は index 2 の座。
const ARR_SRC : String =
  #|{"options":[
  #|  {"name":"arr","type":"csv","long":true},
  #|  {"name":"last","type":"number","long":true,"link":"arr[-1]"},
  #|  {"name":"third","type":"number","long":true,"link":"arr[3]"}]}

///|
test "DR-127 §1: 負 index は発火時点の現在長で解決される" {
  // sources は要素ごとの構造分解 (W2-5 M1) だが、座単位の re-tag は W2-9 の領分 —
  // 現状は whole-cell carrier (最後に書いた binding の source) が全要素へ写る。
  // effects の値空間 index も字面の -1 のまま (解決済み非負への書き換えは W2-9)。
  assert_eq(
    seat_view(ARR_SRC, ["--arr", "1,2,3", "--last", "9"]),
    "result={arr=[1,2,9]} sources={arr=[link,link,link]} effects=arr,arr[-1]",
  )
}

///|
/// 範囲外 index は枝 Reject (definition-error ではない — 構造は静的合法、存在が実行時)。
/// 単枝なので全体パース失敗になり、合成 ParseError の args_pos は当該 binding の at_pos
/// (= operand `9` のトークン位置 3) に帰属する (DR-127 §4.2 / DR-037)。
test "DR-127 §2.2 array: 範囲外 index は枝 Reject、args_pos は at_pos 帰属" {
  let failure = seat_failure_pos(ARR_SRC, ["--arr", "1,2", "--third", "9"])
  assert_true(failure.contains("unresolvable_link_path"))
  assert_true(failure.contains("index-out-of-range:3"))
  assert_true(failure.contains("@3"))
}

///|
/// subcommand scope 配下でも枝ローカル fold の対象セル特定 (scope + 宣言名) が効く —
/// scope 配下の binding は scope label 付きで運ばれるため、対象セルの宣言 (ValueType /
/// 宣言 default) を root と取り違えると枝選別が誤る (W2-4 差異表 F-1 と同じ軸)。
test "DR-127 §4.2: subcommand scope 配下でも枝選別が効く" {
  let src =
    #|{"commands":[{"name":"go","options":[
    #|  {"name":"tr","type":"trange","long":true},
    #|  {"name":"u","type":"string","long":[":set",":incr"],"link":"tr.until"}],
    #| "positionals":[{"name":"rest","type":"string","repeat":{"min":0}}]}]}
  assert_eq(
    seat_view(src, ["go", "--u", "5"]),
    "result={go={rest=[],tr={since=null,until=5}}} sources={go={rest=[],tr={since=null,until=link}}} effects=tr.until",
  )
}
