// wire_decode_wbtest.mbt — wire_decode.mbt の単体テスト (MDR-005)。
// json_conformance_wbtest.mbt から昇格した decode 関数のうち、fixture 経由でなく直接検証している
// ケース (TypeShadow の carry 経路など) をここへ移す。

///|
/// issue typeshadow-carry-gap-or-leaf-positional-group: `dec_or_leaf` は TypeShadow の 7
/// フィールド全てを carry する (base/int_round だけに絞っていた旧実装への回帰防止)。
/// `fixtures/value-typing/or-leaf-factory-config.json` は bool_config / allow_base_prefix の
/// carry を end-to-end (JSON result) で pin 済みだが、tty preset 由来の is_tty/tty_stream/
/// tty_cygwin は同 fixture が触れていない軸 — 本 whitebox test で `dec_or_leaf` の返り値
/// (ElemDef) を直接検査し、shadow の非 canonical 値 (is_tty=true, tty_stream=Some("stderr"),
/// tty_cygwin=false, int_round=RFloor, allow_base_prefix=true, 非 canonical bool_config) が
/// 1 つも canonical default に落ちずそのまま or leaf へ届くことを固定する。
test "dec_or_leaf: TypeShadow の全フィールド (int_round/allow_base_prefix/bool_config/is_tty/tty_stream/tty_cygwin) が or leaf に carry される" {
  let shadows : Map[String, TypeShadow] = Map([])
  let custom_bool_config : BoolConfig = {
    true_values: ["on"],
    false_values: ["off"],
    case_insensitive: false,
  }
  shadows.set("dialect", {
    base: bool_type(),
    int_round: RFloor,
    allow_base_prefix: true,
    bool_config: custom_bool_config,
    is_tty: true,
    tty_stream: Some("stderr"),
    tty_cygwin: false,
  })
  let src =
    #|{"type": "dialect", "name": "leaf"}
  let j = @json.parse(src)
  let e = dec_or_leaf(j, shadows)
  assert_eq(e.name, "leaf")
  assert_eq(e.ty, bool_type())
  assert_eq(e.int_round, RFloor)
  assert_eq(e.allow_base_prefix, true)
  assert_eq(e.bool_config, custom_bool_config)
  assert_eq(e.is_tty, true)
  assert_eq(e.tty_stream, Some("stderr"))
  assert_eq(e.tty_cygwin, false)
}

///|
/// 対極 (shadow に無い bare 型名の場合): TypeShadow を経由しない or leaf は dec_ty の canonical
/// 型解決 + RError/false/bool_config_canonical()/false/None/true の canonical default に落ちる
/// ことの固定 (carry すべきものが無い場合に誤って何かを持ち込んでいないかの反証チェック)。
test "dec_or_leaf: shadow に無い bare 型名 (\"int\") は canonical default (int_round=RError 等) に落ちる" {
  let shadows : Map[String, TypeShadow] = Map([])
  let src =
    #|{"type": "int", "name": "leaf"}
  let j = @json.parse(src)
  let e = dec_or_leaf(j, shadows)
  assert_eq(e.ty, int_type())
  assert_eq(e.int_round, RError)
  assert_eq(e.allow_base_prefix, false)
  assert_eq(e.bool_config, bool_config_canonical())
  assert_eq(e.is_tty, false)
  assert_eq(e.tty_stream, None)
  assert_eq(e.tty_cygwin, true)
}

///|
/// codex レビュー Major 3 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見):
/// `dec_positional` の bare `{"exact": "..."}` shape 検出は `exact` が「唯一のキー」であることを
/// `only_key` で要求する。旧実装は `name`/`type`/`or`/`ref` の 4 キーだけを明示 deny していたため、
/// それ以外の同居キー (`repeat`/`optional`/`default` 等) は黙って無視され「受理したように見えて
/// 意味を捨てる」状態だった (`{"exact":"init","repeat":{...}}` が repeat 宣言を無視して
/// decode 成功していた) — 代表 3 キーそれぞれで DecodeSkip になることを固定し、この class の
/// silent-drop が再発しないことを確認する。
test "dec_positional: bare 'exact' combined with repeat/optional/default DecodeSkips (codex レビュー Major 3)" {
  let shadows : Map[String, TypeShadow] = Map([])
  let srcs : Array[String] = [
    (
      #|{"exact": "init", "repeat": {"min": 0}}
    ),
    (
      #|{"exact": "init", "optional": true}
    ),
    (
      #|{"exact": "init", "default": "x"}
    ),
  ]
  for src in srcs {
    let j = @json.parse(src)
    let _ = dec_positional(j, shadows) catch { DecodeSkip(_) => continue }
    fail("expected DecodeSkip for: " + src)
  }
}

///|
/// 対極 (codex レビュー Major 3): `exact` が唯一のキーの場合は正常に decode され、`is_exact:true` /
/// `name` = spelling の `ElemDef` (`exact_marker` 由来) を返す — `only_key` ガードが正当なケースまで
/// 巻き込んで壊していないことの確認 (self-written-rule-blind-spots の「新規ガード追加時は無変更ケース
/// も確認する」線)。
test "dec_positional: bare 'exact' alone decodes to an is_exact marker (対極, codex レビュー Major 3)" {
  let shadows : Map[String, TypeShadow] = Map([])
  let src =
    #|{"exact": "init"}
  let j = @json.parse(src)
  let e = dec_positional(j, shadows)
  assert_eq(e.is_exact, true)
  assert_eq(e.name, "init")
}
