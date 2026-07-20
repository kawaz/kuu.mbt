// wire_decode_wbtest.mbt — wire_decode.mbt の単体テスト (MDR-005)。
// json_conformance_test.mbt から昇格した decode 関数のうち、fixture 経由でなく直接検証している
// ケース (TypeShadow の carry 経路など) をここへ移す。

///|
/// issue typeshadow-carry-gap-or-leaf-positional-group: `dec_or_leaf` は TypeShadow の 7
/// フィールド全てを carry する (base/int_round だけに絞っていた旧実装への回帰防止)。
/// `fixtures/value-typing/or-leaf-factory-config.json` は bool_config / allow_base_prefix の
/// carry を end-to-end (JSON result) で pin 済みだが、tty preset 由来の is_tty/tty_stream/
/// tty_cygwin は同 fixture が触れていない軸 — 本 whitebox test で `dec_or_leaf` の返り値
/// (@engine.ElemDef) を直接検査し、shadow の非 canonical 値 (is_tty=true, tty_stream=Some("stderr"),
/// tty_cygwin=false, int_round=@engine.RFloor, allow_base_prefix=true, 非 canonical bool_config) が
/// 1 つも canonical default に落ちずそのまま or leaf へ届くことを固定する。
test "dec_or_leaf: TypeShadow の全フィールド (int_round/allow_base_prefix/bool_config/is_tty/tty_stream/tty_cygwin) が or leaf に carry される" {
  let shadows : Map[String, TypeShadow] = Map([])
  let custom_bool_config : @engine.BoolConfig = {
    true_values: ["on"],
    false_values: ["off"],
    case_insensitive: false,
  }
  shadows.set("dialect", {
    base: @builtins.bool_type(),
    is_tree_form: false,
    int_round: @engine.RFloor,
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
  assert_eq(e.ty, @builtins.bool_type(config=custom_bool_config))
  assert_eq(e.int_round, @engine.RFloor)
  assert_eq(e.allow_base_prefix, true)
  assert_eq(e.bool_config, custom_bool_config)
  assert_eq(e.is_tty, true)
  assert_eq(e.tty_stream, Some("stderr"))
  assert_eq(e.tty_cygwin, false)
}

///|
/// 対極 (shadow に無い bare 型名の場合): TypeShadow を経由しない or leaf は dec_ty の canonical
/// 型解決 + @engine.RError/false/@builtins.bool_config_canonical()/false/None/true の canonical default に落ちる
/// ことの固定 (carry すべきものが無い場合に誤って何かを持ち込んでいないかの反証チェック)。
test "dec_or_leaf: shadow に無い bare 型名 (\"int\") は canonical default (int_round=@engine.RError 等) に落ちる" {
  let shadows : Map[String, TypeShadow] = Map([])
  let src =
    #|{"type": "int", "name": "leaf"}
  let j = @json.parse(src)
  let e = dec_or_leaf(j, shadows)
  assert_eq(e.ty, @builtins.int_type())
  assert_eq(e.int_round, @engine.RError)
  assert_eq(e.allow_base_prefix, false)
  assert_eq(e.bool_config, @builtins.bool_config_canonical())
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
    let _ = dec_positional(j, shadows) catch {
      DecodeSkip(_) => continue
      UnknownType(element, type_name) =>
        abort("unexpected UnknownType for " + element + ": " + type_name)
    }
    fail("expected DecodeSkip for: " + src)
  }
}

///|
/// 対極 (codex レビュー Major 3): `exact` が唯一のキーの場合は正常に decode され、`is_exact:true` /
/// `name` = spelling の `@engine.ElemDef` (`exact_marker` 由来) を返す — `only_key` ガードが正当なケースまで
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

// ── moved whitebox coverage from the conformance runner ────────────────

///|
/// DESIGN §8.4 / DR-085 §3 の object-form filter args は構造化された
/// `FnInvocation.args` として保持される。U+E000 を複数含む値も分割せず
/// literal のまま decode することを固定する。
test "dec_filter_chain preserves U+E000 inside an object-form arg as one literal" {
  let tag = "\u{E000}"
  let raw_arg = "a" + tag + "b" + tag + tag + "c"
  let src = "[{\"name\":\"regex_match\",\"args\":[\"" +
    raw_arg +
    "\"]},{\"name\":\"trim\"}]"
  let j = @json.parse(src)
  let result = dec_filter_chain(Some(j)) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(result.length(), 2)
  assert_eq(result[0].name, "regex_match")
  assert_eq(result[0].args.length(), 1)
  assert_eq(result[0].args[0], raw_arg)
  assert_eq(result[1].name, "trim")
  assert_eq(result[1].args.length(), 0)
}

///|
test "dec_filter_chain gives colon-string and one-level array forms identical meaning" {
  let source =
    #|["in_range:1:10",["in_range","1","10"],["regex_match","a:b"]]
  let j = @json.parse(source)
  let result = dec_filter_chain(Some(j)) catch {
    DecodeSkip(reason) => abort("expected successful decode: " + reason)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(result.length(), 3)
  assert_eq(result[0], result[1])
  assert_eq(result[0], { name: "in_range", args: ["1", "10"] })
  assert_eq(result[2], { name: "regex_match", args: ["a:b"] })
}

///|
/// 保証 (DR-096 §3.3、kawaz 裁定 2026-07-12 — 空 prefix の無条件合法化): `long_prefix: ""` は
/// `long_eq_sep: "require"` との併用を要求しない。旧 DR-091 §3 の合法条件 (併用時のみ合法、それ
/// 以外は decode-time definition-error) は撤廃された — bare long トリガと素 operand の衝突は
/// アプリ毎の事情であり、衝突時は通常の読み列挙が @engine.Ambiguous (DR-053) に落とす、先回り禁止は置かない
/// (`fixtures/matcher-readings/long-empty-prefix-operand-collision.json` が衝突時の帰結を固定)。
/// `long_eq_sep: "require"` はこの衝突を定義側で排除したいアプリが選べる解決手段の一つに過ぎない。
test "dec_definition: long_prefix:\"\" WITH long_eq_sep:\"require\" decodes successfully and propagates to options" {
  let src =
    #|{"options":[{"name":"if","type":"string","long":true},{"name":"of","type":"string","long":true}],"config":{"long_prefix":"","long_eq_sep":"require"}}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options.length(), 2)
  for e in def.options {
    assert_eq(e.long_prefix, "")
    assert_eq(e.long_eq_sep, @engine.EsRequire)
  }
}

///|
/// 対極 (撤廃の直接固定): `long_prefix: ""` ALONE, with scope 既定 `long_eq_sep: @engine.EsAllow`
/// (= `long_eq_sep` を明示しない), decodes successfully — 旧 DR-091 §3 ならここが decode-time
/// definition-error だったが、DR-096 §3.3 の無条件合法化でそのまま通る。
test "dec_definition: long_prefix:\"\" ALONE (long_eq_sep unset, @engine.EsAllow) decodes successfully (対極, DR-096 §3.3 撤廃の固定)" {
  let src =
    #|{"options":[{"name":"if","type":"string","long":true}],"config":{"long_prefix":""}}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options[0].long_prefix, "")
  assert_eq(def.options[0].long_eq_sep, @engine.EsAllow)
}

///|
/// 保証 (要素単位の上書きは未規定語彙): an OPTION carrying `long_prefix` or
/// `long_eq_sep` directly (not on the enclosing definition/scope) is rejected by
/// `dec_option`'s `allowed_keys` as an unknown key — these 2 fields are scope-only wire vocabulary,
/// never element-level (team-lead 裁定 2026-07-11, the 対極 half of the previous 2 tests: this
/// pins that dec_option does NOT accept them, closing the door the earlier element-level design
/// had left open).
test "dec_option: long_prefix at the OPTION level is an unknown-key decode reject (scope-only vocabulary)" {
  let src =
    #|{"name":"if","type":"string","long":true,"long_prefix":""}
  let j = @json.parse(src)
  let _ = dec_option(j, Map([])) catch {
    DecodeSkip(_) => return
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  fail("expected DecodeSkip (long_prefix is not a valid option-level key)")
}

///|
/// 保証 (DESIGN §7.2「子要素は親の config を継承、上書き可能」): a root scope declares
/// `long_prefix: "+"`; a nested `commands[0]` declares NO `config` at all — its options must still
/// resolve `long_prefix` to the INHERITED `"+"` (not the pre-issue root default `"--"`), proving
/// the parent→child propagation `dec_command`/`dec_definition` now carry.
test "dec_definition: a child command with no own config inherits every key from the parent scope" {
  let src =
    #|{
    #|  "options": [{"name": "root_opt", "type": "string", "long": true}],
    #|  "config": {"long_prefix": "+"},
    #|  "commands": [
    #|    {"name": "sub", "options": [{"name": "sub_opt", "type": "string", "long": true}]}
    #|  ]
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options[0].long_prefix, "+")
  assert_eq(def.commands.length(), 1)
  assert_eq(def.commands[0].body.options[0].long_prefix, "+")
}

///|
/// 保証 (同上、上書き側): a child command declaring its OWN `config` with only `short_prefix`
/// overrides ONLY that key — `long_prefix` still resolves to the parent's `"+"` (merge is
/// per-key, not whole-object replacement, `dec_scope_config`'s doc comment).
test "dec_definition: a child command's own config overrides ONLY the keys it declares, inherits the rest" {
  let src =
    #|{
    #|  "options": [],
    #|  "config": {"long_prefix": "+"},
    #|  "commands": [
    #|    {
    #|      "name": "sub",
    #|      "options": [{"name": "sub_opt", "type": "string", "long": true, "short": "s"}],
    #|      "config": {"short_prefix": "="}
    #|    }
    #|  ]
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  let sub_opt = def.commands[0].body.options[0]
  assert_eq(sub_opt.short_prefix, "=") // 子が明示した上書き
  assert_eq(sub_opt.long_prefix, "+") // 親から継承 (子は long_prefix を書いていない)
}

///|
/// 保証 (孫スコープまでの多段継承): a grandchild command (root → mid → leaf, neither `mid` nor
/// `leaf` declaring their own `config`) still resolves the root's `long_prefix` — hierarchical
/// merge threads through every recursion level, not just 1 hop.
test "dec_definition: config inheritance threads through MULTIPLE nesting levels (grandchild)" {
  let src =
    #|{
    #|  "options": [],
    #|  "config": {"long_prefix": "+"},
    #|  "commands": [
    #|    {
    #|      "name": "mid",
    #|      "options": [],
    #|      "commands": [
    #|        {"name": "leaf", "options": [{"name": "v", "type": "string", "long": true}]}
    #|      ]
    #|    }
    #|  ]
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  let leaf = def.commands[0].body.commands[0].body
  assert_eq(leaf.options[0].long_prefix, "+")
}

///|
/// 保証 (DR-049 §4「明示 env: の値にも env_prefix は連結される」): `env: "PORT"` + scope
/// `env_prefix: "MYAPP"` → decode 後の `e.env[0]` が `"MYAPP_PORT"` に連結される。DESIGN §7.2
/// line 838 の例そのもの。
test "dec_definition: explicit env: gets env_prefix concatenated (DR-049 §4)" {
  let src =
    #|{
    #|  "options": [{"name": "port", "type": "number", "env": "PORT"}],
    #|  "config": {"env_prefix": "MYAPP"}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options[0].env, ["MYAPP_PORT"])
}

///|
/// 対極 (DR-049 §3「env_prefix 未設定なら prefix 部を省く」): `config` を一切書かないスコープでは
/// 明示 `env:` の値が一切改変されない — pre-issue の全 fixture (env installer 単体テスト等) が
/// この後方互換に依存する。
test "dec_definition: explicit env: is UNCHANGED when env_prefix is unset (対極, 後方互換)" {
  let src =
    #|{"options": [{"name": "port", "type": "number", "env": "PORT"}]}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options[0].env, ["PORT"])
}

///|
/// 保証 (DR-049 §3 名前導出規則、DESIGN §7.2 line 842 の例そのもの): `config: {env_prefix:"MYAPP",
/// auto_env:true}` 配下の `serve` スコープの `port` (env: 未指定) は decode 時点で
/// `MYAPP_SERVE_PORT` を自動導出する — scope_path (= `dec_command` が積む command name チェーン)
/// + env_prefix + name の全連結、UPPER のみ (name は既に snake_case)。
test "dec_definition: auto_env derives UPPER(env_prefix)_UPPER(scope_path)_UPPER(name) (DR-049 §3, DESIGN §7.2 example)" {
  let src =
    #|{
    #|  "options": [],
    #|  "config": {"env_prefix": "MYAPP", "env_auto": true},
    #|  "commands": [
    #|    {"name": "serve", "options": [{"name": "port", "type": "number"}]}
    #|  ]
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.commands[0].body.options[0].env, ["MYAPP_SERVE_PORT"])
}

///|
/// 対極 (DR-049 §4「明示 env: が auto_env に優先する」): auto_env:true 下でも `env:` を明示した
/// 要素には auto 導出が一切効かない (明示値 + env_prefix 連結のみ、scope_path は不参加) — auto_env
/// on の scope に混在する明示/暗黙の両方が正しく分岐することを 1 fixture で固定する。
test "dec_definition: auto_env does NOT override an element's explicit env: (DR-049 §4, 優先関係)" {
  let src =
    #|{
    #|  "options": [],
    #|  "config": {"env_prefix": "MYAPP", "env_auto": true},
    #|  "commands": [
    #|    {
    #|      "name": "serve",
    #|      "options": [
    #|        {"name": "port", "type": "number"},
    #|        {"name": "host", "type": "string", "env": "HOME"}
    #|      ]
    #|    }
    #|  ]
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  let opts = def.commands[0].body.options
  assert_eq(opts[0].env, ["MYAPP_SERVE_PORT"]) // auto 導出 (未指定)
  assert_eq(opts[1].env, ["MYAPP_HOME"]) // 明示値 + env_prefix 連結のみ、scope_path 不参加
}

///|
/// 保証 (DESIGN §7.2 line 842「env: 未指定の値セル持ち要素」— BCell gate): auto_env は positional
/// にも効く (`inst_env` が options/positionals 両方を走査するのと対称)。
test "dec_definition: auto_env also derives env for positionals (値セル持ち要素は BCell 全般)" {
  let src =
    #|{
    #|  "positionals": [{"name": "target", "type": "string"}],
    #|  "config": {"env_prefix": "MYAPP", "env_auto": true}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.positionals[0].env, ["MYAPP_TARGET"])
}

///|
/// 保証 (DR-014 フル 7 キーの decode 受理 + 階層継承の運搬): `short_prefix`/`long_eq_sep`/
/// `short_combine` も他のキーと同じ decode-time bake パターンで各要素へ伝わる。
test "dec_definition: short_prefix / long_eq_sep / short_combine all decode and bake onto options" {
  let src =
    #|{
    #|  "options": [{"name": "v", "type": "string", "long": true, "short": "v"}],
    #|  "config": {"short_prefix": "+", "long_eq_sep": "deny", "short_combine": false}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options[0].short_prefix, "+")
  assert_eq(def.options[0].long_eq_sep, @engine.EsDeny)
  assert_eq(def.options[0].short_combine, false)
}

///|
/// 保証 (allowed_keys 側の網羅性): `config` object 内の未知キーは decode-time reject — DR-014 の
/// 7 キー以外を発明しない歯止め。
test "dec_definition: an unknown config key is a decode-time reject" {
  let src =
    #|{"options":[],"config":{"bogus_key":true}}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let _ = dec_definition(o) catch {
    DecodeSkip(_) => return
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  fail("expected DecodeSkip (bogus_key is not a config vocabulary word)")
}

///|
/// 保証 (codex 指摘 Major 1, DR-049 §4「prefix を付けたくない完全指定 (例: HOME を読む) は、その
/// 要素の config で env_prefix:"" を上書きする (DR-014 の階層継承で要素単位の上書きが可能)」の
/// motivating case そのもの): scope が `env_prefix: "MYAPP"` を持つ中で、1つの要素だけ自分の
/// `config: {"env_prefix": ""}` を持つと、その要素の明示 `env: "HOME"` は連結されずそのまま残る
/// (DR-049 §3「env_prefix 未設定なら prefix 部を省く」が要素単位の resolved config にも同じ規則で
/// 効く)。同じスコープの他要素は scope 側の env_prefix 連結をそのまま受ける — 要素単位 override が
/// 兄弟要素に波及しないことも同時に固定する。
test "dec_definition: an element's own config env_prefix:\"\" opts that element out of the scope's env_prefix (DR-049 §4 HOME motivating case)" {
  let src =
    #|{
    #|  "options": [
    #|    {"name": "port", "type": "number", "env": "PORT"},
    #|    {"name": "home", "type": "string", "env": "HOME", "config": {"env_prefix": ""}}
    #|  ],
    #|  "config": {"env_prefix": "MYAPP"}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options[0].env, ["MYAPP_PORT"]) // 兄弟要素は scope の連結をそのまま受ける
  assert_eq(def.options[1].env, ["HOME"]) // opt-out 要素は連結されない
}

///|
/// 保証 (同上、long_prefix/short_combine 軸): scope 既定 (`long_prefix:"--"`) の中で 1 要素だけ
/// `config: {"long_prefix":"+"}` を持つと、その要素だけ `+` 綴りになり、兄弟要素は `--` のまま —
/// マージは要素単位で `dec_scope_config` を再適用するだけ (別ロジックを持たない) ことの直接確認。
test "dec_definition: an element's own config long_prefix overrides ONLY that element, siblings keep the scope default" {
  let src =
    #|{
    #|  "options": [
    #|    {"name": "a", "type": "string", "long": true},
    #|    {"name": "b", "type": "string", "long": true, "config": {"long_prefix": "+"}}
    #|  ]
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.options[0].long_prefix, "--")
  assert_eq(def.options[1].long_prefix, "+")
}

///|
/// 保証 (同上、positional 対称性 — DESIGN §7.2「子要素」は option/positional 双方を含む):
/// positional も要素単位 `config` を受理し、env_prefix override が同じ規則で効く。
test "dec_definition: a positional's own config env_prefix override works the same as an option's" {
  let src =
    #|{
    #|  "positionals": [
    #|    {"name": "target", "type": "string"},
    #|    {"name": "home", "type": "string", "env": "HOME", "config": {"env_prefix": ""}}
    #|  ],
    #|  "config": {"env_prefix": "MYAPP", "env_auto": true}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  assert_eq(def.positionals[0].env, ["MYAPP_TARGET"]) // auto_env 経由、scope env_prefix 連結
  assert_eq(def.positionals[1].env, ["HOME"]) // opt-out、明示 env: そのまま
}

///|
/// 保証 (要素単位 config の allowed_keys 網羅性): option の `config` object 内も scope config と
/// 同じキーのみ受理 — 未知キーは decode-time reject (DR-014 の語彙を要素単位でも発明しない)。
test "dec_definition: an option's own config rejects an unknown key just like scope config does" {
  let src =
    #|{"options":[{"name":"a","type":"string","config":{"bogus_key":true}}]}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let _ = dec_definition(o) catch {
    DecodeSkip(_) => return
    UnknownType(element, type_name) =>
      abort("unexpected UnknownType for " + element + ": " + type_name)
  }
  fail("expected DecodeSkip (bogus_key is not a config vocabulary word)")
}
