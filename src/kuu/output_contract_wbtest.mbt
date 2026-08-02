// output_contract_wbtest.mbt — DR-126 §4 の乖離検査と、複合セル値の result/sources 構造分解
// (DR-127 §6 / DR-122 §3) を、実際に複合を産む type resident を立てて固定する。
//
// conformance 側では pin できない: 定義が使える type は builtin factory だけで、record を名乗る
// builtin は存在しない (`schema/builtin-descriptors.json` の types は number/int/bool/tty)。
// DR-126 §4 自身も「壊れた builtin parser を注入できないため、この Error の pin は実装側テストの
// 領分」と書いており、本ファイルがその網である。

///|
/// `{"record": {"since": "number", "until": "number"}}` を名乗る value_parser。トークンごとに
/// 宣言と合う値・合わない値を撃ち分けられるようにしてある。
priv struct RangeTypeExt {}

///|
impl @extension.TypeExt for RangeTypeExt with fn name(_self) {
  "range"
}

///|
impl @extension.TypeExt for RangeTypeExt with fn encode(_self) {
  "v1".to_json()
}

///|
impl @extension.TypeExt for RangeTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for RangeTypeExt with fn output_type(_self) {
  Some(@abi.ValueType::Record([("since", "number"), ("until", "number")]))
}

///|
impl @extension.TypeExt for RangeTypeExt with fn parse_token(_self, token) {
  match token {
    // 宣言どおりの産出。
    "1..2" =>
      Ok(
        @abi.Object([("since", @abi.Number(1.0)), ("until", @abi.Number(2.0))]),
      )
    // (c) 宣言済みキーの欠落 — 正常。
    "1.." => Ok(@abi.Object([("since", @abi.Number(1.0))]))
    // (a) 宣言に無いキー。
    "zoned" =>
      Ok(
        @abi.Object([
          ("since", @abi.Number(1.0)),
          ("until", @abi.Number(2.0)),
          ("zone", @abi.String("utc")),
        ]),
      )
    // (a) 系 — wire JSON object が表現できない重複キー (統括裁定 2026-08-02)。
    "dup" =>
      Ok(
        @abi.Object([("since", @abi.Number(1.0)), ("since", @abi.Number(2.0))]),
      )
    // (b) フィールドの type が名乗る out との不一致。
    "wordy" => Ok(@abi.Object([("since", @abi.String("yesterday"))]))
    // 産出値そのものが record ですらない。
    "flat" => Ok(@abi.String("1..2"))
    // 乖離検査が Reject を Error に化けさせないことの対照。
    "nope" =>
      Err(@abi.TypeParseFail::{
        disposition: @abi.ValueSpaceMiss,
        reason: "not_a_range",
        message: "value \"nope\" is not a range",
      })
    _ =>
      Err(@abi.TypeParseFail::{
        disposition: @abi.ValueSpaceMiss,
        reason: "not_a_range",
        message: "value \"" + token + "\" is not a range",
      })
  }
}

///|
impl @extension.TypeExt for RangeTypeExt with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
fn range_registry() -> @node.Registry raise {
  let registry = canonical_registry()
  assert_true(registry.register_type(RangeTypeExt::{  } as &@extension.TypeExt))
  registry
}

///|
fn range_ast(source : String) -> AtomicAST raise {
  let registry = range_registry()
  match parse_definition(@json.parse(source), extensions=registry) {
    Ok(ast) => ast
    Err(_) => {
      fail("definition with a record-producing type must lower")
      panic()
    }
  }
}

///|
/// 保証 (DR-127 §6 / DR-122 §1・§3): value_parser 産の複合値は result で `ResultValue` の複合アーム
/// へ持ち上がり、sources はその同型 shadow tree として**座ごとに**タグを持つ。leaf 1 タグへ潰さない。
test "record 産出セルは result が構造を保ち sources が座ごとに分解される (DR-127 §6, DR-122 §3)" {
  let src =
    #|{"options": [{"name": "span", "type": "range", "long": true}]}
  let ast = range_ast(src)
  let args = ["--span", "1..2"]
  let outcome = resolve_legacy(ast, parse_legacy(ast, args), args)
  let bindings = match outcome {
    @engine.Success(b) => b
    other => {
      fail("resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects=bindings)
  // result: セル値の複合が `Scalar` に包まれたままにならない (射影後の `Scalar` は複合を持たない)。
  assert_eq(render_rval_sorted(view.result), "{span={since=1,until=2}}")
  // sources: 同じ形の shadow tree。両座とも産出発火のタグを持つ。
  assert_eq(render_rval_sorted(view.sources), "{span={since=cli,until=cli}}")
}

///|
/// 保証: 名前を持たない座に複合値が座っても provenance は失われない。射影は値の構造をそのまま
/// scope の形として出すので、shadow の walk は宣言の無い座へ降りてはならない。
test "nameless セルの複合値も座ごとの sources を持つ (DR-122 §3)" {
  let src =
    #|{"positionals": [{"name": "", "type": "range"}]}
  let ast = range_ast(src)
  let args = ["1..2"]
  let outcome = resolve_legacy(ast, parse_legacy(ast, args), args)
  let bindings = match outcome {
    @engine.Success(b) => b
    other => {
      fail("resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects=bindings)
  assert_eq(render_rval_sorted(view.result), "{since=1,until=2}")
  assert_eq(render_rval_sorted(view.sources), "{since=cli,until=cli}")
}

///|
/// 射影 tree に `Scalar(複合)` が 1 つも無いことを確かめる。W2-5 の canonical 化規則の直接検査。
fn no_scalar_holds_composite(value : @abi.ResultValue) -> Bool {
  match value {
    @abi.Scalar(scalar) => !(scalar is (@abi.Array(_) | @abi.Object(_)))
    @abi.Array(items) => items.iter().all(no_scalar_holds_composite)
    @abi.Object(fields) =>
      fields.iter().all(field => no_scalar_holds_composite(field.1))
  }
}

///|
/// 保証 (W2-5 の canonical 化規則、統括裁定 2026-08-02): **射影後の `Scalar` は複合を保持しない。**
/// `Scalar(Object([...]))` と `Object([...])` は同じ JSON の 2 表現であり、前者を選ぶと
/// `source_shadow` の scalar アームが持つタグが 1 つしかないため、DR-122 §1 (sources は result と
/// 同型) と DR-127 §6 (複合値を leaf 1 タグに潰さない) が同時に破れる。綴りの検査 (上の 2 test) は
/// 両表現を区別できないので、構造そのものを見る本 test が規則の網である。
test "射影後の Scalar は複合を保持しない (W2-5 canonical 化規則)" {
  let src =
    #|{"options": [{"name": "span", "type": "range", "long": true}]}
  let ast = range_ast(src)
  let args = ["--span", "1..2"]
  let outcome = resolve_legacy(ast, parse_legacy(ast, args), args)
  let bindings = match outcome {
    @engine.Success(b) => b
    other => {
      fail("resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects=bindings)
  assert_true(no_scalar_holds_composite(view.result))
  assert_true(no_scalar_holds_composite(view.sources))
  // セル値の複合は射影の複合アームに現れる (持ち上げが起きている side の表明)。
  match view.result {
    @abi.Object(fields) => {
      let mut span : @abi.ResultValue? = None
      for field in fields {
        if field.0 == "span" {
          span = Some(field.1)
        }
      }
      assert_eq(
        span,
        Some(
          @abi.Object([
            ("since", @abi.Scalar(@abi.Number(1.0))),
            ("until", @abi.Scalar(@abi.Number(2.0))),
          ]),
        ),
      )
    }
    _ => fail("root projection should be an Object")
  }
  // sources は同型で、座ごとに独立したタグを持つ (DR-122 §1 / §3)。
  match view.sources {
    @abi.Object(fields) => {
      let mut span : @abi.ResultValue? = None
      for field in fields {
        if field.0 == "span" {
          span = Some(field.1)
        }
      }
      assert_eq(
        span,
        Some(
          @abi.Object([
            ("since", @abi.Scalar(@abi.String("cli"))),
            ("until", @abi.Scalar(@abi.String("cli"))),
          ]),
        ),
      )
    }
    _ => fail("root sources should be an Object")
  }
}

///|
/// 乖離 1 件を撃って、held Error の reason を読む。
fn range_divergence_reason(token : String) -> String raise {
  let src =
    #|{"options": [{"name": "span", "type": "range", "long": true}]}
  let ast = range_ast(src)
  let args = ["--span", token]
  match parse_legacy(ast, args) {
    @engine.Failure(data) => {
      if data.errors.length() != 1 {
        fail(
          "a divergence must leave exactly one held Error, got " +
          data.errors.length().to_string(),
        )
      }
      data.errors[0].reason
    }
    other => {
      fail(
        "a divergent producer must not yield a complete reading, got " +
        render_outcome(other),
      )
      panic()
    }
  }
}

///|
/// 保証 (DR-126 §4 表 (a)): 宣言に無いキーを産んだら Error。closed な語彙 (DR-126 §2) の帰結であり、
/// Reject ではない — ユーザがどう入力しても回避できない失敗を Reject にすると、全解釈が静かに
/// 消えて原因の無いパース失敗だけが残る (DR-126 §4 の分界文)。
test "宣言外キーの産出は held Error (DR-126 §4 (a))" {
  assert_eq(range_divergence_reason("zoned"), "undeclared_field")
}

///|
/// 保証 (統括裁定 2026-08-02): 重複キーの Object は wire JSON が表現できず conformance の result
/// 射影にも乗らないので、(a) 系の Error として扱う。W2-3 の実測どおり素の JSON 綴りでは後勝ちに
/// 潰れる一方 `value_to_configval` は両方を保つため、通せば result と sources で座の数が食い違う。
test "重複キーの産出は held Error ((a) 系)" {
  assert_eq(range_divergence_reason("dup"), "duplicate_field")
}

///|
/// 保証 (DR-126 §4 表 (b)): 宣言済みキーの値がフィールドの type の名乗る `out` と合わなければ Error。
/// ここでは `since` が `number` を指すのに string が座っている。
test "フィールド type の out 不一致は held Error (DR-126 §4 (b))" {
  assert_eq(range_divergence_reason("wordy"), "field_type_mismatch")
}

///|
/// 保証: 産出値そのものが自己宣言の形と違う場合も同じ分界の Error 側に落ちる。
test "record を名乗る型がスカラを産んだら held Error" {
  assert_eq(range_divergence_reason("flat"), "output_shape_mismatch")
}

///|
/// 保証 (DR-126 §4 表 (c) / DR-130 §4.1): 宣言済みキーが生出力に無いのは**正常**。乖離検査は
/// 射影の null 補形より前に生出力を見るので、パーサが宣言済みフィールドを 1 つ落として返すことは
/// 従来どおり許される。
test "宣言済みキーの欠落は正常 (DR-126 §4 (c), DR-130 §4.1)" {
  let src =
    #|{"options": [{"name": "span", "type": "range", "long": true}]}
  let ast = range_ast(src)
  let args = ["--span", "1.."]
  let outcome = resolve_legacy(ast, parse_legacy(ast, args), args)
  match outcome {
    @engine.Success(bindings) => {
      let view = output_legacy(ast, effects=bindings)
      assert_eq(render_rval_sorted(view.result), "{span={since=1}}")
      assert_eq(render_rval_sorted(view.sources), "{span={since=cli}}")
    }
    other =>
      fail(
        "an omitted declared field must stay normal, got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証: 乖離検査は resident 自身の Reject を Error へ格上げしない。DR-126 §4 の分界文が分けている
/// 2 つ (「入力 → 値」の失敗 = Reject と「返した値 vs 自己宣言」の矛盾 = Error) が、同じ resident の
/// 中でも別のものとして残る。
test "resident 自身の Reject は乖離検査を通しても Reject のまま (DR-126 §4 分界文)" {
  let src =
    #|{"options": [{"name": "span", "type": "range", "long": true}]}
  let ast = range_ast(src)
  let args = ["--span", "nope"]
  match parse_legacy(ast, args) {
    @engine.Failure(data) =>
      for error in data.errors {
        assert_false(error.reason == "not_a_range")
      }
    other =>
      fail(
        "a value-space miss must not produce a complete reading, got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (DR-126 §4 の適用範囲): 検査は CLI 席だけのものではない。env 席も同じ resident の同じ
/// 産出を通るので、同じ乖離が同じ Error として現れる。
test "env 席の産出にも乖離検査が効く (DR-126 §4)" {
  let src =
    #|{"options": [{"name": "span", "type": "range", "long": true, "env": "SPAN"}]}
  let ast = range_ast(src)
  let env = fn(name : String) -> String? {
    if name == "SPAN" {
      Some("zoned")
    } else {
      None
    }
  }
  let outcome = resolve_legacy(ast, parse_legacy(ast, []), [], env~)
  match outcome {
    @engine.Failure(data) => {
      let mut found = false
      for error in data.errors {
        if error.reason == "undeclared_field" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "a divergent env value must surface as an Error, got " +
        render_outcome(other),
      )
  }
}
