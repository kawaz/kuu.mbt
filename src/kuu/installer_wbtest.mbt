// installer_wbtest.mbt — lowering の輪郭を最少ケースで固定する wbtest (MDR-002 §3 lowering 層)。
//
// フル conformance harness は task #5 で別途組み込む。ここは「installer 経路が
// UsefulAST を @engine.Scope 形に落とせているか」を構造的に確認する最小集合 (代表 installer 単体 + 合成 +
// 順列一致) のみ。テスト意図: 各 case の直前コメントで「何を保証 + 仕様根拠」を文章で残す
// (テスト = 動く仕様書; MDR-002 §3 の設計を後続セッションが読むだけで理解できるように)。

///|
/// 空の @engine.Definition (options / positionals / commands / aliases 全空)。個別 case は spread で必要 field
/// だけ差し替える。
fn empty_def() -> @engine.Definition {
  { options: [], positionals: [], commands: [], aliases: [] }
}

///|
fn is_resident(node : @engine.Node, kind : String, name : String) -> Bool {
  match node {
    Ext(extension) =>
      extension.kind() == kind &&
      @builtins.node_resident_name(node) == Some(name)
    _ => false
  }
}

///|
/// @engine.ElemDef を「必要な軸だけ named param で差し替える」ビルダー。全 field を毎回書くと slice の
/// helpers_wbtest.mbt と同じ肥大化を招くため、ここでは lowering wbtest が触る軸だけ label に出す。
fn el(
  name : String,
  ty : &@engine.TypeExt,
  // DR-071 §1 / kawaz 裁定 2026-07-08: `long` は wire 二形 (@engine.LongDecl) をそのまま受け取る — bool/array
  // の区別が installer 層の resolve_long (糖衣展開・DR-076 §2 flag 差し替え/補完) に必要なため、
  // Array[String] へ潰さない。既定は `LList([])` (= absent = 入口なし)。
  long? : @engine.LongDecl = LList([]),
  short? : Array[Char] = [],
  env? : Array[String] = [],
  is_tty? : Bool = false,
  tty_stream? : String? = None,
  tty_cygwin? : Bool = true,
  is_dd? : Bool = false,
  // issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見: positional-face nameless
  // exact-match leaf marker (installer.mbt's `@engine.ElemDef.is_exact` doc comment) — exposed here so
  // lowering wbtest cases can exercise it without hand-writing a full @engine.ElemDef literal, same
  // rationale as `is_dd` above.
  is_exact? : Bool = false,
  dd_match? : String? = None,
  dd_self_keep? : Bool = false,
  is_global? : Bool = false,
  is_inherit? : Bool = false,
  repeat? : @engine.RepeatSpec? = None,
  multiple? : Bool = false,
  accumulator? : String? = None,
  flatten? : Bool? = None,
  collector? : String? = None,
  ref_? : String? = None,
  piece_filters? : Array[String] = [],
  value_filters? : Array[String] = [],
  final_filters? : Array[String] = [],
  accum_filters? : Array[String] = [],
  // DR-091 §3 / DR-096 §1: long-only axis, `el`'s other builders (`opt`/`pos`,
  // json_conformance_test.mbt) already carry these — added here so lowering wbtest cases can
  // exercise `long_eq_sep` without hand-writing a full @engine.ElemDef literal.
  long_prefix? : String = "--",
  long_eq_sep? : @engine.EqSepMode = @engine.EsAllow,
  // issue scope-config-object-gap: same rationale, for the DESIGN §7.2 fields `inst_short`/
  // `inst_long` now consume directly (`short_prefix`/`short_attached_value`).
  short_prefix? : String = "-",
  short_combine? : Bool = true,
  short_attached_value? : @engine.AttachMode = @engine.AtAllow,
) -> @engine.ElemDef {
  {
    name,
    ty,
    long,
    variants: [],
    short,
    env,
    is_tty,
    tty_stream,
    tty_cygwin,
    is_dd,
    is_exact,
    dd_match,
    dd_self_keep,
    is_global,
    is_inherit,
    is_inheritable: false,
    link_depth: 0,
    ref_target: ref_,
    repeat,
    optional: false,
    multiple,
    accumulator,
    flatten,
    separator: None,
    collector,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: @engine.export_key_unset(),
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    required_group: [],
    // DR-093: `el()` follows the same "constraint axes stay at their zero value, spread-override
    // (`{ ..el(...), required: true }`) if a case needs it" pattern as requires/exclusive_group above.
    required: false,
    value_requires: [],
    deprecated: false,
    is_alias: false,
    hidden: false,
    completer: None,
    default_values: None,
    int_round: @engine.RError,
    allow_base_prefix: false,
    bool_config: @builtins.bool_config_canonical(),
    // `chain` (filters_wbtest.mbt, same package): keeps this builder's colon-shorthand ergonomics
    // (`piece_filters=["trim"]`) even though `@engine.ElemDef` fields are `Array[@engine.FilterSpelling]` in
    // production (issue filter-spelling-inband-encoding-retyping).
    piece_filters: chain(piece_filters),
    value_filters: chain(value_filters),
    final_filters: chain(final_filters),
    accum_filters: chain(accum_filters),
    long_prefix,
    short_prefix,
    env_prefix: "",
    auto_env: false,
    long_eq_sep,
    short_combine,
    short_attached_value,
    body: BCell,
  }
}

///|
/// canonical な installer chain (13 全部)。順列耐性テスト以外はこれを使う。
fn all_installers() -> Array[&@engine.InstallerExt] {
  [
    @builtins.long_installer(),
    @builtins.short_installer(),
    @builtins.env_installer(),
    @builtins.dd_installer(),
    @builtins.command_installer(),
    @builtins.global_installer(),
    @builtins.inherit_installer(),
    @builtins.repeat_installer(),
    @builtins.multiple_installer(),
    @builtins.config_installer(),
    @builtins.constraint_installer(),
    @builtins.alias_installer(),
    @builtins.inheritable_installer(),
  ]
}

///|
/// Ok を expect して @engine.Scope を取り出すヘルパ (Err は panic テストで assert)。fixture 実食は task #5 の
/// harness で扱うため、この層は「lowering が Ok を返した @engine.Scope の構造」を細かく検査する。
fn ok_scope(
  def : @engine.Definition,
  order : Array[&@engine.InstallerExt],
) -> @engine.Scope {
  match @builtins.lower_definition(def, order) {
    Ok(sc) => sc
    Err(_) => abort("expected Ok(@engine.Scope), got Err")
  }
}

///|
fn entity_of(sc : @engine.Scope, name : String) -> @engine.Entity? {
  for e in sc.entities {
    if e.name == name {
      return Some(e)
    }
  }
  None
}

// ── long installer 単体 (DR-042 §展開の標準パターン) ───────────────────────────

///|
/// 保証: long installer は option ごとに (1) `--<spelling>` の greedy exact 衛星を 1 本発し (value 系は
/// value プリミティブを直後に置いた @engine.Seq)、(2) eq-split matcher 1 本を集約し (全 value 系 entry を集めて)、
/// (3) entity を name で 1 個 ensure する。仕様根拠 = DR-042 §展開の標準パターン (installer は entry 表を
/// matcher の構成 data として使う) + LOWERING §B.1 (long entry の 2 form: name-derived / 明示綴り)。
test "long installer: value option gets 1 greedy @engine.Seq satellite + 1 @builtins.eq_split matcher + 1 entity" {
  let def : @engine.Definition = {
    ..empty_def()
    // DR-071 §1: `:set` is the main-entry sentinel `normalize_option` expands to kebab(name) — the
    // pre-normalize form `el(...)` must use (DR-011 明確化 2026-07-08: a colon-less string like
    // "port" is itself a variant DSL syntax error now, not a pass-through literal spelling).
    ,
    options: [el("port", @builtins.string_type(), long=LList([":set"]))],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  // 貢献: (1) @engine.Seq([@engine.Exact("--port"), @builtins.string_arg("port")]) の satellite が 1 本、(2) @engine.NativeMatch(@builtins.eq_split(...))
  // 1 本、計 greedy = 2 本。@builtins.string_type() なので value_prim = string resident。
  assert_eq(sc.greedy.length(), 2)
  assert_eq(
    sc.greedy[0],
    @engine.Seq([@engine.Exact("--port"), @builtins.string_arg("port", [])]),
  )
  match sc.greedy[1] {
    @engine.NativeMatch(matcher) => {
      assert_eq(matcher.kind(), "eq_split")
      let candidates = matcher.candidates()
      assert_eq(candidates.length(), 1)
      assert_eq(candidates[0].spelling, "--port")
      assert_eq(candidates[0].origin, "port")
    }
    _ => abort("expected @engine.NativeMatch")
  }
  // entity は name=port で 1 個、@builtins.flag_type() ではないので default_values は None。inherit_ / env_key
  // / config_seat / accum は installer が触っていないので初期値のまま。
  assert_eq(sc.entities.length(), 1)
  let ent = entity_of(sc, "port").unwrap()
  assert_eq(ent.ty, @builtins.string_type())
  assert_eq(ent.env_key, None)
  assert_eq(ent.accum, None)
  assert_eq(ent.default_values, None)
}

///|
/// 保証 (DR-058 §2): a deprecated VALUE main entry's satellite carries a trailing `deprecation resident`
/// warning marker after its value slot (`inst_long`'s space-form main-entry arm, node.mbt's
/// `deprecation resident` doc shape) — mirrors `inst_short`'s `depr: e.deprecated` short-cluster coverage
/// (builtins/matcher_residents_wbtest.mbt「short cluster: deprecated entry rides a @depr marker」). `deprecated: true`
/// on a plain (non-alias) element stands in for both cases DR-058 §2 requires a warning for — a
/// directly-deprecated canonical entry, and a deprecated alias entry-copy (DR-057 §3
/// `alias_entry`) — both fold into the SAME `@engine.ElemDef.deprecated` bool by the time `inst_long` runs,
/// so lowering cannot (and need not) distinguish them. Firing the entry (`--port 8080`) must NOT
/// alter the parsed value (`port` still binds `8080`) — only a `@depr:port` bookkeeping marker is
/// added, collected by `@engine.warnings_of`.
test "long installer: a deprecated value option's main-entry satellite carries a deprecation resident warning marker (DR-058 §2)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      {
        ..el("port", @builtins.string_type(), long=LList([":set"])),
        deprecated: true,
      },
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  assert_eq(
    sc.greedy[0],
    @engine.Seq([
      @engine.Exact("--port"),
      @builtins.string_arg("port", []),
      @builtins.deprecation_mark("port"),
    ]),
  )
  let o = @engine.parse_tree(
    @engine.ScopeNode(sc),
    ["--port", "8080"],
    defs=Map([]),
  )
  match o {
    @engine.Success(bs) => {
      assert_eq(resolved_values(bs, "port"), [@engine.VStr("8080")])
      assert_eq(@engine.warnings_of(o), ["port"])
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (DR-058 §2): a deprecated FLAG's @engine.Set-variant satellite (`inst_long`'s "@engine.Variant entries"
/// loop — the `:set:true` bare-fire DR-076 §2 規則1 composes for a classic flag) ALSO carries a
/// trailing `deprecation resident`, symmetric with the value main-entry case above. `inst_long` has 2 lowering
/// sites for a long entry point (space-form main-entry vs the variant loop, since a bare flag fire
/// is a @engine.Set variant, not a main entry — see the "long installer: a flag's `long:true`..." test
/// above); `inst_short` has only 1 (a cluster char has no variant/main-entry split, `depr` rides
/// the single `@builtins.ShortEntry`). Both `inst_long` sites need their own deprecation resident application for parity
/// with the short side — this test locks the variant-loop site (the previous test locks the
/// main-entry site). Firing `--verbose` both sets `verbose=true` AND records `@depr:verbose`.
test "long installer: a deprecated flag's @engine.Set-variant satellite carries a deprecation resident warning marker (DR-058 §2)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      {
        ..el("verbose", @builtins.flag_type(), long=LBool(true)),
        deprecated: true,
      },
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    @engine.Seq([
      @engine.Exact("--verbose"),
      @engine.Bind("verbose", @engine.VBool(true)),
      @builtins.deprecation_mark("verbose"),
    ]),
  )
  let o = @engine.parse_tree(@engine.ScopeNode(sc), ["--verbose"], defs=Map([]))
  match o {
    @engine.Success(bs) => {
      assert_eq(resolved_values(bs, "verbose"), [@engine.VBool(true)])
      assert_eq(@engine.warnings_of(o), ["verbose"])
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// codex レビュー Major 2 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見) / DR-058
/// §2: the deprecation resident append used to live ONLY in the `BCell`/`ref_target is None` main-entry arm — a
/// `BEnum` main entry (`@builtins.enum_value_node`-shaped satellite) never got it, so a deprecated
/// enum-constrained option silently warned NOTHING. DR-058 §2's warning contract is 値構造非依存 (it
/// fires because the ELEMENT is deprecated, not because of what shape its value slot has) — this
/// locks the BEnum arm now routes through the shared `with_depr` funnel (installer.mbt's `inst_long`)
/// alongside BCell.
test "long installer: a deprecated BEnum (values-constrained) main entry carries a deprecation resident warning marker (codex レビュー Major 2, DR-058 §2)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      {
        ..el("color", @builtins.string_type(), long=LList([":set"])),
        deprecated: true,
        body: BEnum(["red", "blue"]),
      },
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  assert_eq(
    sc.greedy[0],
    @engine.Seq([
      @engine.Exact("--color"),
      @builtins.enum_value_node("color", @builtins.string_type(), [
        "red", "blue",
      ]),
      @builtins.deprecation_mark("color"),
    ]),
  )
  let o = @engine.parse_tree(
    @engine.ScopeNode(sc),
    ["--color", "red"],
    defs=Map([]),
  )
  match o {
    @engine.Success(bs) => {
      assert_eq(resolved_values(bs, "color"), [@engine.VStr("red")])
      assert_eq(@engine.warnings_of(o), ["color"])
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// codex レビュー Major 2 続き: a `BOr` (structural or, variable-arity) main entry — the wrapper
/// itself never binds a value (branch leaves do, `@builtins.or_branch_node`'s doc comment), but DR-058 §2's
/// warning still attaches to the WRAPPING element's `@engine.Seq` (the satellite `inst_long` installs for
/// `e`, not to any individual branch — the deprecated axis lives on `e`, the BOr owner, not on the
/// leaves). This is the 2nd of the "代表 1-2 種" structural arms this Major asks for (BEnum above +
/// BOr here cover both non-BCell shapes `inst_long` special-cases before the generic `_` /
/// `ref_target` dispatch; ref±repeat's own 2 arms already got direct coverage from the fix itself
/// being applied there, per the commit's `with_depr` call sites).
test "long installer: a deprecated BOr (structural or) main entry carries a deprecation resident warning marker (codex レビュー Major 2, DR-058 §2)" {
  let num_branch : @engine.OrBranch = {
    id: "num",
    items: [el("num", @builtins.int_type())],
  }
  let flag_branch : @engine.OrBranch = {
    id: "flag",
    items: [el("flag", @builtins.bool_type())],
  }
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      {
        ..el("level", @builtins.string_type(), long=LList([":set"])),
        deprecated: true,
        body: BOr([num_branch, flag_branch]),
      },
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  match sc.greedy[0] {
    @engine.Seq([@engine.Exact("--level"), @engine.Or(_), marker]) if node_is_deprecation_mark(
        marker,
      ) => ()
    _ =>
      fail(
        "expected sc.greedy[0] == @engine.Seq([@engine.Exact(\"--level\"), @engine.Or(_), @builtins.deprecation_mark(\"level\")])",
      )
  }
  let o = @engine.parse_tree(
    @engine.ScopeNode(sc),
    ["--level", "5"],
    defs=Map([]),
  )
  match o {
    @engine.Success(bs) => {
      assert_eq(resolved_values(bs, "num"), [@engine.VNum(5.0)])
      assert_eq(@engine.warnings_of(o), ["level"])
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

// ── flag (@builtins.flag_type()) の default:false preset + fail_action ─────────────────────────

///|
/// 保証: @builtins.flag_type() entity には LOWERING §A.5 / DR-051 §2 に従い default:false を preset する (未 fire でも
/// false に落ちる)。DR-076 §2 規則1 (flag の `long:true` 糖衣は `:set:true` — bool の `[":set"]` 糖衣を
/// 差し替え): `el("verbose", @builtins.flag_type(), long=LBool(true))` は wire `{"long": true}` そのものを模しており、
/// `normalize_option` (`resolve_long` 経由) がこれを解釈して `variants` を合成する — installer_wbtest
/// が JSON decode を経由せず規則1 を直接検証できる (kawaz 裁定 2026-07-08「installer_wbtest からも
/// 規則1/2 が検証可能になる」の実演)。値セルの型 @builtins.flag_type()→@builtins.bool_type() 差し替えも同じ normalize_option の仕事。
/// flag の裸発火は合成された `:set:true` の @engine.Set variant が @engine.Variant entries loop 経由で @engine.Bind(name, true)
/// 衛星を生む。eq-split matcher には登録されない (この要素は main entry `:set` を持たない = 値パイプ
/// ライン自体が無い、古典 flag の糖衣 `long:true` → `[":set:true"]` のみのケース)。
test "long installer: a flag's `long:true` composes a `:set:true` variant → bare @engine.Bind(true) satellite (no @builtins.eq_split entry), default:false preset (DR-076 §2 規則1)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbose", @builtins.flag_type(), long=LBool(true))],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  // main entry 無し (long=[]) + @engine.Set variant 1 本 → eq-split entry は無い → greedy = @engine.Bind 衛星 1 本のみ。
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    @engine.Seq([
      @engine.Exact("--verbose"),
      @engine.Bind("verbose", @engine.VBool(true)),
    ]),
  )
  // normalize_option の @builtins.flag_type()→@builtins.bool_type() 差し替えは値セルの型のみに効く。entity 自体は name=verbose のまま。
  let ent = entity_of(sc, "verbose").unwrap()
  assert_eq(ent.ty, @builtins.bool_type())
  // default:false preset (DR-051 §2), stored as the length-1-degenerate array (DR-083 §1)
  assert_eq(ent.default_values, Some([@engine.VBool(false)]))
}

///|
/// 保証: DR-076 §2 規則2 (flag の明示 variant リストは非空なら `:set:true` を冪等に補完 — 値形+裸の
/// 同居): `long=LList([":set"])` は wire `{"long": [":set"]}` を模す。main entry `:set` はそのまま
/// 残り (値スロット形、`--verbose <bool>`)、`:set:true` (裸発火) が合成されて共存する。
test "long installer: a flag's explicit `long:[\":set\"]` composes `:set:true` ALONGSIDE the value-slot main entry (DR-076 §2 規則2, 値形+裸の同居)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbose", @builtins.flag_type(), long=LList([":set"]))],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  // main entry 1 本 (値スロット, @builtins.flag_type()→@builtins.bool_type() 差し替え後 bool resident) + @builtins.eq_split matcher 1 本 + variant 1 本
  // (裸発火 @engine.Bind) → greedy = 3 本。
  assert_eq(sc.greedy.length(), 3)
  let mut has_value_slot = false
  let mut has_bare_bind = false
  for g in sc.greedy {
    match g {
      @engine.Seq([@engine.Exact("--verbose"), resident]) if is_resident(
          resident, "builtin/bool", "verbose",
        ) => has_value_slot = true
      @engine.Seq(
        [
          @engine.Exact("--verbose"),
          @engine.Bind("verbose", @engine.VBool(true)),
        ]
      ) => has_bare_bind = true
      _ => ()
    }
  }
  assert_true(has_value_slot)
  assert_true(has_bare_bind)
}

// ── count (@builtins.count_type()) の default:0 preset + long 綴り合成 (DR-077 §3) ─────────────

///|
/// 保証: @builtins.count_type() entity には LOWERING §A.5 / DR-077 §3 に従い default:0 を preset する — flag の
/// default:false と対称。DR-077 §3 規則1 (count の `long:true` 糖衣は `:update:increment`):
/// `el("verbose", @builtins.count_type(), long=LBool(true))` は wire `{"long": true}` を模す。値セルの型 @builtins.count_type()→@builtins.number_type()
/// 差し替えは flag と違い `normalize_option` ではなく `ensure_entity` (@engine.Entity 構築) まで遅延する —
/// `@builtins.count_type()` タグは short/eq-split matcher (builtins/matcher_residents.mbt) が「非消費・固定 increment」を判定するのに
/// installer chain 全体を通して必要だから (`normalize_option` のコメント参照、@builtins.bool_type() は画一ルールで
/// 閉じるが @builtins.number_type() 全般には count 挙動を強制できない)。
test "long installer: a count's `long:true` composes an `:update:increment` variant → bare update-effect satellite (no @builtins.eq_split entry), default:0 preset (DR-077 §3 規則1)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbose", @builtins.count_type(), long=LBool(true))],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  // main entry 無し (long=[]) + @engine.Update variant 1 本 → eq-split entry は無い → greedy = effect resident 衛星 1 本のみ。
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    @engine.Seq([
      @engine.Exact("--verbose"),
      @builtins.effect_mark("verbose", @engine.Update("increment", [])),
    ]),
  )
  let ent = entity_of(sc, "verbose").unwrap()
  // ensure_entity が @builtins.count_type()→@builtins.number_type() の型差し替えを担う (normalize_option ではない)。
  assert_eq(ent.ty, @builtins.number_type())
  // default:0 preset (DR-077 §3), stored as the length-1-degenerate array (DR-083 §1)
  assert_eq(ent.default_values, Some([@engine.VNum(0.0)]))
}

///|
/// 保証: DR-077 §3 規則2 (count の明示 variant リストは非空なら `:update:increment` を冪等に補完):
/// `long=LList([":update:increment"])` を明示しても二重に足されない。flag の規則2 (§1 の 2 番目の
/// test) と対称。
test "long installer: a count's explicit `long:[\":update:increment\"]` does not duplicate the composed variant (DR-077 §3 規則2, 冪等)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.count_type(), long=LList([":update:increment"])),
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    @engine.Seq([
      @engine.Exact("--verbose"),
      @builtins.effect_mark("verbose", @engine.Update("increment", [])),
    ]),
  )
}

///|
/// 保証: DR-071 §1 三態同義 — count の long 糖衣は absent (LBool(false)) でも入口なし。short だけの
/// count (`--` 側は書かない) が成立することを固定する。
test "long installer: a count with long:false has no long entry point (DR-071 §1 三態同義)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.count_type(), long=LBool(false), short=['v']),
    ],
  }
  let sc = ok_scope(def, all_installers())
  for g in sc.greedy {
    match g {
      @engine.Seq([@engine.Exact("--verbose"), ..]) =>
        fail("expected no --verbose long entry")
      _ => ()
    }
  }
}

// ── env installer (席宣言型 DR-042 ④) ───────────────────────────────────────

///|
/// 保証: env installer は entity の env seat (env_key field) に env 変数名を書き込むだけで、greedy に
/// 衛星を追加しない (席宣言型)。ladder 順序 (cli > env > inherit > default, DR-031) は engine 所有で、
/// default_fn を wrap しない。同 pass で ensure_entities → inst_env の順に走るので、entity 未生成の
/// タイミングで inst_env が走っても次 pass で拾える (fixpoint 収束)。
test "env installer: seat env_key on entity, no greedy contribution" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("host", @builtins.string_type(), long=LList([":set"]), env=["HOST"]),
    ],
  }
  let sc = ok_scope(def, all_installers())
  let ent = entity_of(sc, "host").unwrap()
  assert_eq(ent.env_key, Some("HOST"))
}

// ── repeat (DR-043/DR-105 §3): append accum + flatten:true dial + Ref 再帰 ────

///|
/// 保証: unbounded repeat (max=None) は positional に (min-1 mandatory heads + Ref(name)) を積み、
/// entity には append accumulator + flatten:true ダイヤルを宣言する (DR-036 名前付き accumulator
/// registry、DR-105 §3: 旧独立 "flatten" accumulator は append の flatten ダイヤルに統合された)。
/// DR-044 §1 (kawaz 裁定): repeat / multiple / separator は cardinality 不問で常に配列 — なので
/// min:1 でも `repeat:{min:0,max:1}` (optional 糖衣) でも accumulator は必ず立つ。
test "repeat installer: unbounded repeat installs 'append'+flatten:true accum + Ref-recursion on positional spine" {
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [
      el(
        "src",
        @builtins.string_type(),
        repeat=Some({ min: 1, max: None, lazy_: false }),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  // min:1 → min-1=0 mandatory heads → Ref("src#cons") のみ 1 本 (codex 指摘 1 / DR-078 §2:
  // "#cons" mangle — repeat 自己参照 template key が definitions.templates の user namespace と
  // 衝突しないよう、DR-046 §4 の自動 id 空間サフィックスを使う。spec fixtures/lowering/repeat/basic.json
  // の golden も元々 "src#cons" を期待していた、緩比較 canon_tmpl が差を吸収していただけ)。
  assert_eq(sc.positional.length(), 1)
  assert_eq(sc.positional[0], Ref("src#cons"))
  let ent = entity_of(sc, "src").unwrap()
  assert_eq(ent.accum.unwrap().kind(), "append") // DR-105 §3
  assert_eq(ent.flatten, true)
  assert_eq(ent.is_multiple_decl, false) // no `multiple` declared — repeat-cons origin
}

///|
/// 保証: unbounded min:0 は `Ref` (0 でもよいを表現できない) ではなく `@engine.Many(head, lazy_)` に落ち、
/// `lazy_` は宣言の `repeat.lazy` がそのまま `@engine.Many` の 2nd field に渡る (issue 2026-07-08
/// min0-lazy-repeat-gap 根治: `@engine.BoundedTail`'s 3rd field と同じ座席を min:0 UNBOUNDED 側にも用意)。
test "repeat installer: min:0 unbounded repeat lowers to @engine.Many(head, lazy_) carrying the lazy spec" {
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [
      el(
        "xs",
        @builtins.string_type(),
        repeat=Some({ min: 0, max: None, lazy_: true }),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  assert_eq(sc.positional.length(), 1)
  assert_eq(
    sc.positional[0],
    @engine.Many(@builtins.string_arg("xs", []), true),
  )
  let ent = entity_of(sc, "xs").unwrap()
  assert_eq(ent.accum.unwrap().kind(), "append") // DR-044 §1: cardinality 不問で常に配列 / DR-105 §3
  assert_eq(ent.flatten, true)
}

// ── bounded repeat (LOWERING §B.8): min heads + @engine.BoundedTail、Ref 再帰なし ─────

///|
/// 保証: bounded (max 有限) は Ref 再帰を作らず @engine.BoundedTail(head, max-min, lazy_) に落ちる。取り分選好
/// (greedy default / lazy) は @engine.BoundedTail の 3 番目 field で保持され、unbounded 版 (Ref tail) と同じく
/// 先食い/取り分選好が効く (LOWERING §B.8: 「bounded repeats compose like unbounded ones」)。
test "repeat installer: bounded max lowers to min heads + @engine.BoundedTail (no Ref)" {
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [
      el(
        "f",
        @builtins.string_type(),
        repeat=Some({ min: 1, max: Some(3), lazy_: false }),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  // 1 mandatory head + @engine.BoundedTail(head, 2, false) — budget = 3-1
  assert_eq(sc.positional.length(), 2)
  assert_eq(sc.positional[0], @builtins.string_arg("f", []))
  assert_eq(
    sc.positional[1],
    @engine.BoundedTail(@builtins.string_arg("f", []), 2, false),
  )
  // Ref template は登録されない (Ref 再帰なし)
  let ent = entity_of(sc, "f").unwrap()
  assert_eq(ent.accum.unwrap().kind(), "append") // DR-105 §3
  assert_eq(ent.flatten, true)
}

// ── BGroup + bounded repeat → @engine.IdxRepeat budget (issue
// 2026-07-13-positional-group-trailing-missing-operand) ─────

///|
/// 保証: BGroup (named group repeat) の bounded (`max` 有限) spec は `@engine.IdxRepeat` の 4th field
/// (budget = `max - min`) に反映される — 以前はこの field 自体が存在せず、`lower_positional` の
/// BGroup ケースが `elem_repeat(e).max` を丸ごと無視して常に unbounded (budget=None) として lower
/// していたため、`repeat:{min:1,max:1}` のような bounded named-group でも greedy-max-forever に
/// なり、後続 positional のぶんまで over-consume していた
/// (`fixtures/repeat-parse/group-trailing-positional.json` が end-to-end で pin する現象、本
/// wbtest は lowering 層の budget 計算そのものを直接固定する — fixture が見るのは parse 結果だけで
/// この中間表現は見えない)。
test "BGroup installer: bounded max (min:1,max:1) lowers @engine.IdxRepeat's budget field to Some(0)" {
  let grp : @engine.ElemDef = {
    ..el("grp", @builtins.string_type()),
    repeat: Some({ min: 1, max: Some(1), lazy_: false }),
    body: BGroup([el("gflag", @builtins.string_type())]),
  }
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [grp, el("ctrl", @builtins.string_type())],
  }
  let sc = ok_scope(def, all_installers())
  assert_eq(sc.positional.length(), 2)
  assert_eq(
    sc.positional[0],
    @engine.IdxRepeat("grp", @builtins.string_arg("gflag", []), 1, Some(0)),
  )
  assert_eq(sc.positional[1], @builtins.string_arg("ctrl", []))
}

///|
/// 保証: budget は `max - min` (min:1,max:3 → budget=Some(2)) — 0 固定ではなく一般の bounded 範囲を
/// 正しく計算することを確認する (上のケースだけだと budget が常に 0 になる特殊化バグを見逃しうる)。
test "BGroup installer: bounded max (min:1,max:3) lowers @engine.IdxRepeat's budget field to Some(2)" {
  let grp : @engine.ElemDef = {
    ..el("grp", @builtins.string_type()),
    repeat: Some({ min: 1, max: Some(3), lazy_: false }),
    body: BGroup([el("gflag", @builtins.string_type())]),
  }
  let def : @engine.Definition = { ..empty_def(), positionals: [grp] }
  let sc = ok_scope(def, all_installers())
  assert_eq(sc.positional.length(), 1)
  assert_eq(
    sc.positional[0],
    @engine.IdxRepeat("grp", @builtins.string_arg("gflag", []), 1, Some(2)),
  )
}

///|
/// 保証: repeat 属性を持たない BGroup (`elem_repeat(e) is None`) は従来どおり budget=None
/// (min=0 の UNBOUNDED) — 本修正が「repeat 無指定 BGroup」の既存挙動を変えないことを固定する
/// (対極確認、self-written-rule-blind-spots の「新規追加時は既存の無変更ケースも確認する」線)。
test "BGroup installer: no repeat spec keeps @engine.IdxRepeat unbounded (min:0, budget:None)" {
  let grp : @engine.ElemDef = {
    ..el("grp", @builtins.string_type()),
    body: BGroup([el("gflag", @builtins.string_type())]),
  }
  let def : @engine.Definition = { ..empty_def(), positionals: [grp] }
  let sc = ok_scope(def, all_installers())
  assert_eq(sc.positional.length(), 1)
  assert_eq(
    sc.positional[0],
    @engine.IdxRepeat("grp", @builtins.string_arg("gflag", []), 0, None),
  )
}

///|
/// codex レビュー Major 4 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見): the
/// `is_exact` guard used to live ONLY at `ensure_entities`' top-level positionals loop — a `BGroup`
/// inner item never passed through that check (`ensure_entity_body`'s `BGroup` arm recurses into
/// `ensure_entity_body` directly, bypassing the top-level loop entirely), so an `is_exact` leaf
/// NESTED inside a group got a phantom `@engine.Entity{name: spelling, ty: @builtins.none_type()}`. Because `ensure_entity`
/// is add-if-absent (returns early once ANY entity with that name exists), this phantom entity
/// BLOCKED a real same-named element declared elsewhere from ever getting its own (correctly-typed)
/// entity — the exact failure mode this test locks the fix for. `grp` (BGroup containing an
/// `is_exact` leaf named "marker") is declared BEFORE the real "marker" positional so the bug (if
/// present) wins the add-if-absent race; the fix routes `is_exact` through `ensure_entity_body`'s
/// own top-of-function guard (now shared by every recursive call site), so the phantom never gets
/// registered and the real element's entity lands correctly.
test "ensure_entity_body: an is_exact leaf nested inside BGroup creates no phantom @engine.Entity, letting a same-named real element register its own (codex レビュー Major 4, DR-058 §2)" {
  let grp : @engine.ElemDef = {
    ..el("grp", @builtins.string_type()),
    body: BGroup([
      el("marker", @builtins.none_type(), is_exact=true),
      el("val", @builtins.string_type()),
    ]),
  }
  let marker_real : @engine.ElemDef = el("marker", @builtins.string_type())
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [grp, marker_real],
  }
  let sc = ok_scope(def, all_installers())
  let mut marker_count = 0
  for ent in sc.entities {
    if ent.name == "marker" {
      marker_count = marker_count + 1
      // the REAL element's type (@builtins.string_type()), not the phantom's @builtins.none_type() — proves the entity that landed
      // is `marker_real`'s, not a leftover from the BGroup's `is_exact` leaf.
      assert_eq(ent.ty, @builtins.string_type())
    }
  }
  assert_eq(marker_count, 1)
}

// ── multiple の collector 属性 (DR-036, issue 2026-07-09-dec-multiple-collector-decode) ─────

///|
/// 保証: `multiple:true` + collector 宣言 (@engine.ElemDef) は accum cell の @engine.Entity へそのまま写る
/// (`ensure_entity` の write-through、installer.mbt) — collector 自体を解釈・変換する installer は
/// 無く、宣言をそのまま @engine.Entity.collector に通す (DR-036 の decode/実体 lookup の「実体」側)。
test "multiple installer: a declared collector rides straight through to @engine.Entity.collector" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "tags",
        @builtins.string_type(),
        long=LList([":set"]),
        multiple=true,
        collector=Some("unwrap_single"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  let ent = entity_of(sc, "tags").unwrap()
  assert_eq(ent.accum.unwrap().kind(), "append") // DR-034: multiple の値 fold は append
  assert_eq(ent.collector.unwrap().kind(), "unwrap_single")
}

///|
/// 保証: collector は accum cell の伴属物 (node.mbt @engine.Entity.collector の doc comment) — multiple も
/// repeat も無いスカラーセルに collector だけ宣言しても `ensure_entity` は捨てる (accum が None なら
/// collector も強制 None、「累積すら起きないセルの collector」という無意味な組合せを AST に残さない)。
/// 実運用の decode 層 (dec_multiple, json_conformance_test.mbt) は collector を multiple:{...} の
/// 内側キーとしてのみ受理するので、この経路 (multiple:false かつ collector 宣言) は decode からは
/// 到達しない — installer 層の防御的な契約として単体で固定する。
test "multiple installer: a collector declared without multiple/repeat is dropped (accum is None)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "n",
        @builtins.number_type(),
        long=LList([":set"]),
        collector=Some("unwrap_single"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  let ent = entity_of(sc, "n").unwrap()
  assert_eq(ent.accum, None)
  assert_eq(ent.collector, None)
}

// ── dd installer (DR-064): 配置不問回収 (options[] / positionals[] 両対応) ──────

///|
/// 保証: dd (`type:"dd"`) は options[] と positionals[] のどちらに宣言しても回収され、@engine.DdSat 衛星が
/// greedy に 1 本入る (add-if-absent が重複を collapse)。ensure_entities は dd に entity を作らない
/// (LOWERING §B.4「値なし」)。DR-064 §2「dd は配置不問で lowered 形が同一」の仕様準拠テスト。
test "dd installer: options[] placement lowers to same @engine.DdSat with no entity (DR-064 §2)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("--", @builtins.string_type(), is_dd=true)],
  }
  let sc = ok_scope(def, all_installers())
  // @engine.DdSat("--") が greedy に 1 本、entity は 0 個 (dd は値なし)
  let mut has_dd = false
  for g in sc.greedy {
    if g == @engine.DdSat("--") {
      has_dd = true
    }
  }
  assert_true(has_dd)
  assert_eq(sc.entities.length(), 0)
}

// ── issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め: positional-face
// nameless exact-match leaf (`{"exact": "init"}`, DR-063 A.1 裸文字列→exact 正規化 / DR-018 配置で
// 役割決定)。lowering は `@builtins.elem_head` の `is_exact` 分岐で `@engine.Exact(name)` へ直接落ち (dd と同じ「entity
// を持たない」standing、上の dd installer テストと対称)、消費意味論は node.mbt の bare `@engine.Exact` の doc
// comment (「literal token match; binds nothing, consumes 1」) がそのまま定義する — 新規の parse
// 意味論を追加したわけではなく、既存 `@engine.Exact` node を positional spine 上で使えるようにしただけ。 ──

///|
/// 保証 (lowering 断面): `is_exact:true` の positional 要素は `@builtins.elem_head` を経て spine に裸の
/// `@engine.Exact(name)` が 1 本乗るだけで、entity は作られない (dd と同じ「値なし」standing、DR-064 §1 と
/// 同型の判断が exact literal にも及ぶ)。
test "positional exact literal: lowers to bare @engine.Exact(name) on the spine, no entity (issue 2026-07-15-audit-node-nodashstr-deprmark-variants)" {
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [el("init", @builtins.none_type(), is_exact=true)],
  }
  let sc = ok_scope(def, all_installers())
  assert_eq(sc.positional, [@engine.Exact("init")])
  assert_eq(sc.entities.length(), 0)
}

///|
/// 保証 (parse 側、一致): DR-041 の「照合消費プリミティブ」意味論通り、一致トークンは 1 消費で成功する
/// (@engine.Exact 自身は何も bind しない — result は空、node.mbt の doc comment 「binds nothing」の直接確認)。
test "positional exact literal: matching token consumes 1 and succeeds with no bindings (issue 2026-07-15-audit-node-nodashstr-deprmark-variants)" {
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [el("init", @builtins.none_type(), is_exact=true)],
  }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(@engine.ScopeNode(sc), ["init"], defs=Map([]))
  match o {
    @engine.Success(bs) => assert_eq(bs.length(), 0)
    other =>
      fail(
        "expected @engine.Success (matching literal), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (parse 側、不一致): DR-037 の「トリガ不一致は無音 Reject (held error を作らない)」通り、
/// @engine.Exact node 自身は消費せず読みゼロで消える。唯一の spine 要素がその読みゼロの当事者なので、
/// 完全経路が 1 本も残らない — held error も無い (実機確認: `d.errors.length() == 0`、
/// `render_outcome` は "fail:no complete parse" — 他の long/short トリガ不一致と同じ「無音」standing
/// であり、positional exact 専用の新規エラー経路は無い。node.mbt の bare `@engine.Exact` doc comment
/// 「an unmatched trigger is a silent Reject, NOT a @engine.Pending: no part of the entry was consumed, so
/// nothing is half-read」がそのままここでも成立する)。
test "positional exact literal: non-matching token silently rejects (0 complete paths, 0 held errors, issue 2026-07-15-audit-node-nodashstr-deprmark-variants)" {
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [el("init", @builtins.none_type(), is_exact=true)],
  }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(@engine.ScopeNode(sc), ["nope"], defs=Map([]))
  match o {
    @engine.Failure(d) => assert_eq(d.errors.length(), 0)
    other =>
      fail(
        "expected @engine.Failure (non-matching literal), got " +
        render_outcome(other),
      )
  }
}

// ── global installer + fixpoint: 子孫 scope へ link COPY 伝播 ─────────────────

///|
/// 保証: global option は fixpoint 中に子 scope の宣言層にコピーされ、long installer が子でも展開する
/// (link_depth=1 の @engine.Rooted 衛星に wrap)。子 scope 側 entity は生成しない (link_depth > 0 なら
/// ensure_entities がスキップ — DR-070 §1b gap 5)。1 pass では global copy の後の long 展開が
/// 子で行われないが、fixpoint (chain repeat) がそれを吸収する — order-independent の実証。
test "global + long + fixpoint: child scope receives @engine.Rooted satellite (link_depth=1) and no own entity" {
  let child : @engine.Definition = { ..empty_def() }
  let def : @engine.Definition = {
    ..empty_def()
    // DR-076 §2 規則1: `long=LBool(true)` (wire `{"long": true}`) は normalize_option が resolve_long
    // で `variants` へ `:set:true` を合成する — 上の "a flag's `long:true` composes..." テスト参照。
    ,
    options: [
      el("verbose", @builtins.flag_type(), long=LBool(true), is_global=true),
    ],
    commands: [
      { name: "sub", body: child, export_key: @engine.export_key_unset() },
    ],
  }
  let sc = ok_scope(def, all_installers())
  // 子 scope (@engine.CmdSat("sub", child_scope)) を取り出す
  let mut child_sc : @engine.Scope? = None
  for g in sc.greedy {
    match g {
      @engine.CmdSat(n, cs) => if n == "sub" { child_sc = Some(cs) }
      _ => ()
    }
  }
  let child_sc = child_sc.unwrap()
  // 子 scope 側 greedy に @engine.Rooted(@engine.Seq([@engine.Exact("--verbose"), @engine.Bind(...)]), 1) が入る
  let mut found = false
  for g in child_sc.greedy {
    match g {
      @engine.Rooted(_, depth) => if depth == 1 { found = true }
      _ => ()
    }
  }
  assert_true(found)
  // 子 scope に verbose entity は無い (link 同期で root cell に landing)
  assert_eq(entity_of(child_sc, "verbose"), None)
  // root には verbose entity + default:false preset がある (DR-083 §1: 長さ 1 縮退配列)
  let root_ent = entity_of(sc, "verbose").unwrap()
  assert_eq(root_ent.default_values, Some([@engine.VBool(false)]))
}

// ── 順列耐性 (5 invariants + fixpoint): 順序が違っても同じ @engine.Scope に収束 ─────────

///|
/// 保証: 5 invariants + fixpoint により、chain の順序を変えても同じ @engine.Scope が組み上がる (DR-042 §invariants)。
/// long→env vs env→long で env seat が正しく立つか (env → ensure_entities → seat_env が同 pass に走るか
/// を fixpoint が救うか) を、chain の順序 2 種で確認する。
test "installer chain: order-independent thanks to 5 invariants + fixpoint" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("host", @builtins.string_type(), long=LList([":set"]), env=["HOST"]),
    ],
  }
  let sc1 = ok_scope(def, [
    @builtins.long_installer(),
    @builtins.env_installer(),
  ])
  let sc2 = ok_scope(def, [
    @builtins.env_installer(),
    @builtins.long_installer(),
  ])
  // 両順で env seat / greedy 内容が一致
  assert_eq(entity_of(sc1, "host").unwrap().env_key, Some("HOST"))
  assert_eq(entity_of(sc2, "host").unwrap().env_key, Some("HOST"))
  assert_eq(sc1.greedy.length(), sc2.greedy.length())
  assert_eq(sc1.entities, sc2.entities)
}

// ── def-error 列挙 (DR-054 §4): 全 kind を 1 pass で収集 (打ち切りなし) ─────────

///|
/// 保証: parse_definition の static check は generic check と登録住人の check を全て走らせて 1 list に
/// append し、first-error 打ち切りしない (DR-054 §4 「コンパイラの定石」)。ここでは (a) unknown vocab
/// (chain に env installer が無い、env 属性を持つ要素あり) と (b) 登録済み repeat 住人の invalid range
/// (repeat min>max) を同時に混ぜ、両方の @engine.DefError が enumerate されることを確認する。
test "parse_definition enumerates all def-errors (no first-error 打ち切り, DR-054 §4)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("v", @builtins.flag_type(), env=["V"])], // env 属性あり
    positionals: [
      el(
        "f",
        @builtins.string_type(),
        repeat=Some({ min: 3, max: Some(1), lazy_: false }),
      ),
    ], // min > max
  }
  // repeat 住人は登録するが env 住人は登録しない。env の generic unknown-vocab と repeat 住人の
  // invalid-range が同じ pass で列挙される。
  match @builtins.lower_definition(def, [@builtins.repeat_installer()]) {
    Ok(_) => abort("expected Err")
    Err(errs) => {
      // 少なくとも @engine.DUnknownVocab (long / repeat) と @engine.DInvalidRange の 3 種を含む — 打ち切っていれば
      // 最初の 1 種で止まっていたはず。
      let mut has_unknown = false
      let mut has_range = false
      for e in errs {
        if e.kind == @engine.DUnknownVocab {
          has_unknown = true
        }
        if e.kind == @engine.DInvalidRange {
          has_range = true
        }
      }
      assert_true(has_unknown)
      assert_true(has_range)
    }
  }
}

// ── DR-078 §1/§3: ref target 解決 (definitions.templates への decode 配線の裏どり) ───

///|
/// 保証 (DR-078 §1「解決順は DR-032 のまま: スコープ内 → definitions (templates)」/ DR-054
/// absent-ref): `ref_target` の解決先が registry のどこにも無い場合、`parse_definition` は
/// `@engine.DAbsentRef` を definition-error として列挙する。ランタイム側の `check_elem_absent_ref`
/// (installer.mbt) は本 issue 以前から実装済みだったが、decode 層 (`ref` キー) が無かったため
/// この分岐は未踏だった — decode 配線後の疎通確認として、registry を意図的に空のまま
/// (`Map::new()`) `parse_definition` へ渡し、absent-ref が正しく検出されることを固定する。
test "parse_definition: a ref target absent from registry is @engine.DAbsentRef (DR-078 §1 / DR-054)" {
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [
      el(
        "hlcolors",
        @builtins.string_type(),
        ref_=Some("color"),
        repeat=Some({ min: 1, max: None, lazy_: false }),
      ),
    ],
  }
  // "color" は scope 内の兄弟要素にも registry (definitions.templates 相当の事前登録) にも無い
  // (registry 未指定 = 既定の空 map)。
  match @builtins.lower_definition(def, [@builtins.repeat_installer()]) {
    Ok(_) => abort("expected Err (absent ref target 'color')")
    Err(errs) => {
      let mut has_absent_ref = false
      for e in errs {
        if e.kind == @engine.DAbsentRef {
          has_absent_ref = true
        }
      }
      assert_true(has_absent_ref)
    }
  }
}

///|
/// 保証 (codex 節目レビュー指摘4、issue 2026-07-09-ref-template-result-shape): an option's `ref` +
/// `repeat` lowering (`inst_long`) wires a SINGLE `@engine.GreedyRepeat` spine slot — correct for
/// `min <= 1`, but a `min > 1` spec would silently fold the extra mandatory-head reps into that
/// same single slot, losing 先食い suppression / 取り分選好 for them while still parsing
/// "successfully" (a mis-shaped-but-quiet result, the exact failure mode
/// [[retreat-is-last-resort]]/契約 が禁じる). `parse_definition` must reject this at definition
/// time (`@engine.DInvalidRange`, mirrors the sibling positional `min > max` check just above) rather than
/// let it run mis-wired. Registry left empty (color 未登録) — `@engine.DAbsentRef` co-occurs, but this
/// test only asserts `@engine.DInvalidRange` is ALSO enumerated (DR-054 §4 no first-error 打ち切り)。
/// spec fixture 昇格済み (DR-082、fixtures/definition-error/option-ref-repeat-min-invalid-range.json)
/// — 本 wbtest はそれに先行する unit 層の pin として残す。
test "parse_definition: an option's ref+repeat with min > 1 is @engine.DInvalidRange (codex review #4)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "hlcolors",
        @builtins.string_type(),
        long=LList([":set"]),
        ref_=Some("color"),
        repeat=Some({ min: 2, max: None, lazy_: false }),
      ),
    ],
  }
  match
    @builtins.lower_definition(def, [
      @builtins.long_installer(),
      @builtins.repeat_installer(),
    ]) {
    Ok(_) => abort("expected Err (unsupported option ref+repeat min>1)")
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == @engine.DInvalidRange && e.element == "hlcolors" {
          has_range = true
        }
      }
      assert_true(has_range)
    }
  }
}

///|
/// 保証 (対極、codex 指摘4 の境界): `min <= 1` (mandatory-head unroll 無し、`@engine.GreedyRepeat` が単一
/// spine slot で足りる形) は REJECT されない — 上のテストが「壊れた形を通す」ことへの反例なら、
/// このテストは「正しく対応済みの形を誤って落とさない」ことへの反例 ([[self-written-rule-blind-spots]]
/// の対極確認)。`last-wins-repeat-rows.json` が固定する実際の形そのもの ({"min":1})。
test "parse_definition: an option's ref+repeat with min <= 1 is NOT rejected (codex review #4 対極)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "hlcolors",
        @builtins.string_type(),
        long=LList([":set"]),
        ref_=Some("color"),
        repeat=Some({ min: 1, max: None, lazy_: false }),
      ),
    ],
  }
  match
    @builtins.lower_definition(def, [
      @builtins.long_installer(),
      @builtins.repeat_installer(),
    ]) {
    Ok(_) =>
      abort(
        "expected Err (absent ref target 'color', registry left empty on purpose)",
      )
    Err(errs) =>
      for e in errs {
        if e.kind == @engine.DInvalidRange {
          abort(
            "min:1 must not raise @engine.DInvalidRange (only min>1 is unsupported)",
          )
        }
      }
  }
}

///|
/// 保証 (issue 2026-07-09-accum-fold-update-default-ops、team-lead 裁定 2026-07-10 最終版): a
/// `multiple` element carrying an `update` variant (`:update:<transform>`, DR-077 §1) is
/// @engine.DInvalidRange — `collect_unsupported_option_ref_repeat` (上記) と同型の「構造的に宣言できるが
/// 実装が対応できない組合せを definition-error で落とす」契約の3例目。DR-077 の `update` semantics
/// は `cell = f(old)` で `old` はセルの現在値だが、accum セルではその値が累積状態 (T[]) であり、
/// filters registry の transform は全て T=>T (scalar、`filters.mbt`'s `FilterSignature`、DR-077 §2
/// 「使えるのは transform シグネチャ T=>T の filter のみ」) — 構造的に型が噴合し、legal な解決が今の
/// registry には存在しない。これを ACCUMULATE fold の実行時に検出するのではなく、DR-077 §2 が既に
/// 「未登録の transform 名」「validate-only signature」を definition-error で閉じている
/// (`@builtins.classify_long_spelling` の `@builtins.LInvalid` 経路、両方とも `@engine.DUnknownVocab`) のと同じ層で静的に閉じる
/// (この3つ目は multiple 宣言との組合せなので `@builtins.classify_long_spelling` の DSL-parse 単体では判定でき
/// ず、`normalize_surface` が variants を確定させた後の別 pass になる)。
///
/// spec fixture 昇格済み (DR-082、fixtures/definition-error/accum-update-invalid-range.json) —
/// 本 wbtest はそれに先行する unit 層の pin として残す。
test "parse_definition: an update variant on a multiple element is @engine.DInvalidRange (accum-fold-update-default-ops)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "tags",
        @builtins.string_type(),
        long=LList([":set", "bump:update:increment"]),
        multiple=true,
      ),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (update variant on a multiple element is unsupported)",
      )
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == @engine.DInvalidRange && e.element == "tags" {
          has_range = true
        }
      }
      assert_true(has_range)
    }
  }
}

///|
/// 保証 (対極、上のテストの境界、[[self-written-rule-blind-spots]] の対極確認): scalar 要素
/// (multiple 無し) への update variant は REJECT されない — count (DR-077 §3 "number + default:0 +
/// update:increment の綴り合成") がまさにこの形で正規化される既存の正当な用法であり、multiple との
/// 組合せだけが不支持であることを固定する。
test "parse_definition: an update variant on a scalar (non-multiple) element is NOT rejected (対極)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "verbosity",
        @builtins.number_type(),
        long=LList([":set", "bump:update:increment"]),
      ),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == @engine.DInvalidRange {
          abort(
            "a scalar (non-multiple) element with an update variant must not raise @engine.DInvalidRange",
          )
        }
      }
  }
}

///|
/// 保証 (codex レビュー High 1、2026-07-10): alias の `long_override` (DR-057 §3 差分上書き) 経由の
/// `:update:<transform>` も、canonical 要素本体の `variants` (上の2テストが固定する経路) と同じく
/// @engine.DInvalidRange で REJECT される — `collect_unsupported_accum_update` が canonical 側の variants
/// しか見ないと、alias 経由の update variant が検査をすり抜けて `parse_definition` を通過し、発火時
/// に canonical (multiple 要素) への @engine.Update binding が resolve.mbt の accum 分岐に届いて abort に
/// 到達してしまう (修正前の実際の repro)。canonical `tags` (multiple:true) は自身は update variant
/// を持たず、alias `t` の long_override だけが `bump:update:increment` を持つ形で、alias 経由の
/// 検査が独立して機能することを固定する。
test "parse_definition: an alias's long_override update variant on a multiple canonical is @engine.DInvalidRange (codex High 1)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("tags", @builtins.string_type(), long=LList([":set"]), multiple=true),
    ],
    aliases: [
      {
        target: "tags",
        name: Some("t"),
        short: [],
        long_override: Some(LList(["bump:update:increment"])),
        deprecated: false,
      },
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (alias long_override update variant on a multiple canonical is unsupported)",
      )
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == @engine.DInvalidRange && e.element == "tags" {
          has_range = true
        }
      }
      assert_true(has_range)
    }
  }
}

///|
/// 保証 (対極、上のテストの境界): alias の long_override が update variant を持っていても、canonical
/// 側が multiple でなければ REJECT されない — multiple との組合せだけが不支持であることを alias 経路
/// でも固定する (scalar 版の対極テストと同じ観点)。
test "parse_definition: an alias's long_override update variant on a scalar canonical is NOT rejected (対極)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbosity", @builtins.number_type(), long=LList([":set"]))],
    aliases: [
      {
        target: "verbosity",
        name: Some("v"),
        short: [],
        long_override: Some(LList(["bump:update:increment"])),
        deprecated: false,
      },
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == @engine.DInvalidRange {
          abort(
            "an alias update variant on a scalar (non-multiple) canonical must not raise @engine.DInvalidRange",
          )
        }
      }
  }
}

///|
/// 保証 (codex レビュー High 2、2026-07-10): @builtins.count_type() の **short** 発火は variant を一切経由せず
/// `builtins/matcher_residents.mbt`'s `walk_short` が直接 `mk_eff(e.name, @engine.Update("increment", []), @engine.Cli)` を生成する
/// (`count_increment_variant` の `long:true` 糖衣経路とは別の生成源) — `collect_unsupported_accum_
/// update` の variant 走査ではこの経路が最初から見えないため、@builtins.count_type()×multiple という組合せ自体を
/// 要素レベルで閉じる (`collect_unsupported_count_multiple`)。修正前の実際の repro:
/// `{"name":"n","type":"count","short":["n"],"multiple":true}` は `parse_definition` を通過し、
/// args `["-n"]` の発火で resolve.mbt の accum 分岐の abort に到達していた。
/// spec fixture 昇格済み (DR-082、fixtures/definition-error/count-multiple-invalid-range.json) —
/// 本 wbtest はそれに先行する unit 層の pin として残す。
test "parse_definition: a count element with multiple is @engine.DInvalidRange (codex High 2, short-fired repro)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("n", @builtins.count_type(), short=['n'], multiple=true)],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (count element with multiple is unsupported)")
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == @engine.DInvalidRange && e.element == "n" {
          has_range = true
        }
      }
      assert_true(has_range)
    }
  }
}

///|
/// 保証 (対極、上のテストの境界): @builtins.count_type() 要素が multiple を持たなければ REJECT されない — count の
/// 通常用法 (`-vvv` の verbosity 加算等、multiple 無し) を誤って落とさないことを固定する。
test "parse_definition: a count element without multiple is NOT rejected (対極)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbosity", @builtins.count_type(), short=['v'])],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == @engine.DInvalidRange {
          abort(
            "a count element without multiple must not raise @engine.DInvalidRange",
          )
        }
      }
  }
}

// ── long DSL 分類 (DR-011 / DR-071 / DR-076): @builtins.classify_long_spelling 輪郭 ───────

///|
/// `@builtins.classify_long_spelling` is the SOLE interpreter of the colon DSL (DR-011/071/076), shared by
/// the JSON-fixture decoder (`dec_variant`) and `desugar_aliases`'s alias `long_override` (issue
/// 2026-07-08: aliases used to skip this classification entirely, misreading `":set:true"` as a
/// literal `"--:set:true"` spelling). This pins all 4 classification outcomes on representative
/// spellings, keyed on `own_name` (the caller's own resolved name — canonical OR alias, DR-057 §3).
test "@builtins.classify_long_spelling: the 4 outcomes on representative spellings" {
  // (1) @builtins.LMain: the bare `:set` sentinel resolves to `own_name` verbatim, no operand.
  match @builtins.classify_long_spelling(":set", "ssl", @builtins.bool_type()) {
    @builtins.LMain(n) => assert_eq(n, "ssl")
    _ => fail("expected @builtins.LMain")
  }
  // (2) @builtins.LVariant with an EMPTY prefix (`:set:true`, DR-076 §4): the element's own bare-degenerate
  // main entry — trigger is `own_name` verbatim (NOT "-"+own_name — that would be a bogus extra
  // spelling installer.mbt never intended, since it always does `"--" + v.trigger`).
  match
    @builtins.classify_long_spelling(":set:true", "ssl", @builtins.bool_type()) {
    @builtins.LVariant({ trigger, op, operand }) => {
      assert_eq(trigger, "ssl")
      assert_eq(op, @engine.Set)
      assert_eq(operand, Some(@engine.VBool(true)))
    }
    _ => fail("expected @builtins.LVariant")
  }
  // (3) @builtins.LVariant with a NON-empty prefix (`no:set:false`, DR-011): a separately-triggered named
  // variant — trigger is `prefix + "-" + own_name`.
  match
    @builtins.classify_long_spelling(
      "no:set:false",
      "ssl",
      @builtins.bool_type(),
    ) {
    @builtins.LVariant({ trigger, op, operand }) => {
      assert_eq(trigger, "no-ssl")
      assert_eq(op, @engine.Set)
      assert_eq(operand, Some(@engine.VBool(false)))
    }
    _ => fail("expected @builtins.LVariant")
  }
  // (4) @builtins.LInvalid: no colon at all — DR-011 明確化 (kawaz 裁定 2026-07-08): a colon-less string is a
  // variant DSL syntax error, NOT a literal-spelling fallback. An explicit non-name-derived spelling
  // (e.g. an alias's "gzip") belongs to a DR-057 alias element, not to `long`'s DSL.
  match
    @builtins.classify_long_spelling(
      "gzip",
      "compress",
      @builtins.string_type(),
    ) {
    @builtins.LInvalid(s) => assert_eq(s, "gzip")
    _ => fail("expected @builtins.LInvalid")
  }
  // a non-bool variant operand parses per the element's OWN type (DR-074/075 canonical lexicons) —
  // not just bool. `default:5` on a @builtins.number_type() element parses the operand as a number.
  match
    @builtins.classify_long_spelling(
      "default:default:5",
      "port",
      @builtins.number_type(),
    ) {
    @builtins.LVariant({ trigger, op, operand }) => {
      assert_eq(trigger, "default-port")
      assert_eq(op, @engine.Default)
      assert_eq(operand, Some(@engine.VNum(5.0)))
    }
    _ => fail("expected @builtins.LVariant")
  }
  // (5) @builtins.LInvalid: an unrecognized effect word (colon present, but not set/unset/empty/default) is
  // ALSO a syntax error (DR-011 明確化) — not a literal-spelling fallback either.
  match
    @builtins.classify_long_spelling(
      "no:bogus:false",
      "ssl",
      @builtins.bool_type(),
    ) {
    @builtins.LInvalid(s) => assert_eq(s, "no:bogus:false")
    _ => fail("expected @builtins.LInvalid (unrecognized op word)")
  }
}

///|
/// DR-011 明確化 (kawaz 裁定 2026-07-08): `parse_definition` surfaces a colon-less `long` spelling as
/// a DR-054 `unknown-vocab` definition-error (not a silently-accepted literal trigger).
test "parse_definition: a colon-less long spelling is a DR-054 unknown-vocab definition-error" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbose", @builtins.flag_type(), long=LList(["verbose"]))],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      fail(
        "expected Err (colon-less long spelling 'verbose' is a syntax error)",
      )
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == @engine.DUnknownVocab && e.element == "verbose" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// DR-011 明確化: an unrecognized effect word (colon present, op word outside set/unset/empty/default)
/// is the SAME syntax error as colon-less — also `unknown-vocab`.
test "parse_definition: an unrecognized effect word in long is a DR-054 unknown-vocab definition-error" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("ssl", @builtins.bool_type(), long=LList(["no:bogus:false"]))],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      fail("expected Err (unrecognized effect word 'bogus' is a syntax error)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == @engine.DUnknownVocab && e.element == "ssl" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// DR-011 明確化 (kawaz 裁定 2026-07-08): alias `long_override` (DR-057 §3 差分上書き) is the SAME
/// colon DSL canonical `long` uses (`@builtins.classify_long_spelling` shared, installer.mbt comment "二経路が
/// drift しないよう分類器を共用") — the 明確化 applies wherever the DSL appears, not just canonical
/// `long`. A colon-less `long_override` spelling must be an `unknown-vocab` definition-error too,
/// caught by `collect_invalid_alias_long_override` BEFORE `desugar_aliases` ever runs (so the invalid
/// spelling never silently becomes a literal trigger through the alias path either).
test "parse_definition: a colon-less alias long_override spelling is a DR-054 unknown-vocab definition-error" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbose", @builtins.flag_type(), long=LBool(true))],
    aliases: [
      {
        target: "verbose",
        name: Some("chatty"),
        short: [],
        long_override: Some(LList(["chatty"])), // colon-less — 文法エラー
        deprecated: false,
      },
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      fail(
        "expected Err (colon-less alias long_override spelling 'chatty' is a syntax error)",
      )
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == @engine.DUnknownVocab && e.element == "chatty" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

// ── alias long_override の DR-076 §2 flag 差し替え/補完 (issue 2026-07-08 根治) ────

///|
/// 保証 (issue 2026-07-08 dec-alias-long-override-flag-sugar-gap の根治): alias `long_override` の
/// `long:true` (LBool(true)) は、canonical 側の `long:true` と同じ規則1 (DR-076 §2: flag なら
/// `:set:true` へ差し替え) を適用する。alias `{alias:"verbose", name:"v", long:true}` (canonical
/// verbose = flag) は、値スロット形の main entry `--v <bool>` ではなく、`:set:true` の裸発火 variant
/// (@engine.Bind("verbose", true)) を生む — desugar_aliases が canonical の「元の型」(normalize_surface で
/// @builtins.bool_type() 化される前の @builtins.flag_type()) を保持した複製 (`orig`) から引き、alias 名・その元の型で resolve_long
/// を通すことで実現する。
test "desugar_aliases: alias long:true on a flag canonical composes :set:true (bare fire), not a value-slot main entry (DR-076 §2 規則1)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbose", @builtins.flag_type())],
    aliases: [
      {
        target: "verbose",
        name: Some("v"),
        short: [],
        long_override: Some(LBool(true)),
        deprecated: false,
      },
    ],
  }
  let sc = ok_scope(def, all_installers())
  // alias 側の trigger --v は @engine.Bind (裸発火) 衛星 1 本のみ — @builtins.eq_split (値スロット形) には登録されない。
  let mut has_bare_bind = false
  let mut has_value_slot = false
  for g in sc.greedy {
    match g {
      @engine.Seq(
        [@engine.Exact("--v"), @engine.Bind("verbose", @engine.VBool(true))]
      ) => has_bare_bind = true
      @engine.Seq([@engine.Exact("--v"), resident]) if is_resident(
          resident, "builtin/bool", "verbose",
        ) => has_value_slot = true
      _ => ()
    }
  }
  assert_true(has_bare_bind)
  assert_false(has_value_slot)
}

///|
/// 保証 (対照): alias `long_override` の `long:true` は canonical が string (非 flag) なら、通常どおり
/// `:set` (値スロット形) に糖衣展開される — 規則1 の差し替えは flag 型限定であることの固定。
test "desugar_aliases: alias long:true on a string canonical stays a value-slot main entry" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("host", @builtins.string_type())],
    aliases: [
      {
        target: "host",
        name: Some("h"),
        short: [],
        long_override: Some(LBool(true)),
        deprecated: false,
      },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let mut has_value_slot = false
  for g in sc.greedy {
    match g {
      @engine.Seq([@engine.Exact("--h"), resident]) if is_resident(
          resident, "builtin/string", "host",
        ) => has_value_slot = true
      _ => ()
    }
  }
  assert_true(has_value_slot)
}

// ── copy_global_into 冪等判定はトリガ集合まで見る (codex 指摘、regression 修正) ─────

///|
/// 保証 (codex 指摘の regression 修正): `copy_global_into` の idempotent 判定は「同名 + コピー由来」
/// だけでなく**トリガ集合の一致**まで見る。root と mid にそれぞれ独立に宣言された同名 (`x`) だが
/// 別トリガ (`:set:true` vs `no:set:false`) の global が祖先チェーンにある場合、両方とも孫スコープ
/// (sub) まで正しく伝播しなければならない — 「同名なら idempotent」という緩い判定だと、先に
/// コピーされた方 (トリガ A) が後続の別トリガ (トリガ B) のコピーを誤って抑止してしまう。
///
/// この regression は `parse()` 経由の end-to-end テストでは検出できなかった: DR-041 §4 の
/// 早閉じ+porous によって、sub 自体にトリガが 1 本しか無くても祖先 (mid) の greedy 面がまだ読める
/// ため、observable な parse 結果 (effects/result) が偶然「両方効いているように」見えてしまう。
/// そのため `materialize` 後の `@engine.Scope` 構造 (sub 自身の greedy 面に積まれた `@engine.Rooted` 衛星の本数) を
/// 直接検査する — sub 自身が両トリガの link 衛星を持つことが、porous に頼らない正しい伝播の証拠。
test "copy_global_into: two same-name different-trigger globals (declared independently at root and mid) both propagate to a grandchild scope" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      {
        ..el("x", @builtins.bool_type()),
        long: LList([":set:true"]),
        is_global: true,
      },
    ],
    commands: [
      {
        name: "mid",
        body: {
          ..empty_def(),
          options: [
            {
              ..el("x", @builtins.bool_type()),
              long: LList(["no:set:false"]),
              is_global: true,
            },
          ],
          commands: [
            {
              name: "sub",
              body: empty_def(),
              export_key: @engine.export_key_unset(),
            },
          ],
        },
        export_key: @engine.export_key_unset(),
      },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let mut mid_sc : @engine.Scope? = None
  for g in sc.greedy {
    match g {
      @engine.CmdSat(n, cs) => if n == "mid" { mid_sc = Some(cs) }
      _ => ()
    }
  }
  let mid_sc = mid_sc.unwrap()
  let mut sub_sc : @engine.Scope? = None
  for g in mid_sc.greedy {
    match g {
      @engine.CmdSat(n, cs) => if n == "sub" { sub_sc = Some(cs) }
      _ => ()
    }
  }
  let sub_sc = sub_sc.unwrap()
  // sub 自身の greedy 面に、root 由来 (:set:true) と mid 由来 (no:set:false) 両方の @engine.Rooted 衛星が
  // 積まれているはず — 1 本しか無ければ、後続コピーがトリガ違いにも関わらず誤って抑止された regression。
  let mut rooted_count = 0
  for g in sub_sc.greedy {
    match g {
      @engine.Rooted(_, _) => rooted_count = rooted_count + 1
      _ => ()
    }
  }
  assert_eq(rooted_count, 2)
}

// ── add_inheritable_copy の shadow 判定はトリガ集合まで見る (codex 指摘、regression 修正) ──

///|
/// 保証 (codex 指摘の regression 修正): `add_inheritable_copy` の自前優先 shadow 判定は、DR-076 後に
/// 裸発火トリガが `variants` 側に入るケース (例: alias `[":set:true"]` 由来) も見なければならない。
/// root の canonical `other` (flag, トリガなし) + alias `{alias:"other", name:"sub-ttl",
/// long:[":set:true"]}` で `--sub-ttl` を裸発火として与えておき、子 `sub` の inheritable `ttl` が
/// 同じ綴り `sub-ttl` (defining scope 名 "sub" + name "ttl" の prefix 導出) で祖先へ逆コピーされよう
/// とするケース。`long_of` (main long のみ) で shadow 判定すると alias 由来のトリガ (variants 側) を
/// 見落とし、`--sub-ttl` の入口が重複してしまう (root の greedy 面に同一 @engine.Exact トリガの衛星が 2 本
/// 立つ)。`all_long_triggers` (long + variants 横断) で判定すれば、既存の alias トリガを検出して
/// inheritable コピーが正しく shadow (抑止) される。
test "add_inheritable_copy: an alias-provided (variants-side) trigger shadows the inheritable reverse-copy" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("other", @builtins.flag_type())],
    commands: [
      {
        name: "sub",
        body: {
          ..empty_def(),
          options: [
            {
              ..el("ttl", @builtins.number_type()),
              is_inheritable: true,
              default_values: Some([@engine.VNum(60.0)]),
            },
          ],
        },
        export_key: @engine.export_key_unset(),
      },
    ],
    aliases: [
      {
        target: "other",
        name: Some("sub-ttl"),
        short: [],
        long_override: Some(LList([":set:true"])),
        deprecated: false,
      },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let mut count = 0
  for g in sc.greedy {
    match g {
      @engine.Seq([@engine.Exact("--sub-ttl"), ..]) => count = count + 1
      _ => ()
    }
  }
  // shadow が正しく効けば alias 由来の 1 本のみ (inheritable コピーは重複追加されない)。
  assert_eq(count, 1)
}

// ── DR-077: update 効果 + count (definition-error 系、installer 層) ──────────────

///|
/// 保証 (codex 指摘 2、DR-077 §2 「不在 → unknown-vocab」): `@builtins.classify_long_spelling` は
/// `:update:<name>` の `<name>` を filters registry へ実際に `@engine.lookup_filter` する (旧実装は
/// `parts[2] == "increment"` のハードコード allowlist だった — 節目レビューで指摘され registry
/// lookup ベースへ置換)。registry に存在しない名前 (`bogus`) は `None` の分岐で `@builtins.LInvalid` へ倒し
/// (installer.mbt コメント参照)、既存の push_invalid_long/collect_invalid_long_dsl 機構にそのまま
/// 合流して DR-054 definition-error (`@engine.DUnknownVocab`) になる。新しい definition-error チェックを
/// 増やさず既存機構に相乗りする設計判断の固定。「不在」ケース (次の wbtest の「存在するが
/// signature 不適合」ケースと対)。
test "DR-077 §2: an unrecognized update transform name is a DR-054 unknown-vocab definition-error" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.count_type(), long=LList([":update:bogus"])),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      fail("expected Err (unrecognized transform 'bogus' is unknown-vocab)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == @engine.DUnknownVocab && e.element == "verbose" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// 保証 (codex 指摘 2、DR-077 §2 「シグネチャ不適合 → definition-error」): `in_range` は filters
/// registry に**実在する**が signature は `Validate` (`filters.mbt`) — `T→T` の transform ではなく
/// `T→T raise` の validator なので `update` (DR-077 §1 `cell = f(old)`、旧値から新値を計算する
/// transform を要求) には使えない。前の wbtest (`bogus` = 不在) と対で「存在するが signature 不適合」
/// ケースを分離 pin する — どちらも現行 `@engine.DefErrKind` (DR-054) に signature 専用の細分 kind が無い
/// ため同じ `@engine.DUnknownVocab` に倒れる (installer.mbt の `@builtins.classify_long_spelling` doc comment 参照、
/// 実装の裁量として報告済み)。
test "DR-077 §2: a registered but Validate-signature filter is also a DR-054 unknown-vocab definition-error" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.count_type(), long=LList([":update:in_range"])),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      fail(
        "expected Err ('in_range' is Validate signature, not usable as an update transform)",
      )
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == @engine.DUnknownVocab && e.element == "verbose" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// 保証 (codex 指摘 2、DR-077 §2 の definition-time gate 精密化): 引数の arity は RUNTIME 関心
/// (`apply_transform`, resolve.mbt — closure 自身が拒否する、`@engine.apply_filter_chain` と同じ split)。
/// `@builtins.classify_long_spelling` の definition-time gate は「registry に存在するか」「signature が
/// Transform か」の 2 点だけを見る — args の個数は関知しない。よって `:update:increment:5` (0-arg
/// 組み込み `increment` に余分な args) は **definition としては妥当** (increment は登録済み・
/// Transform signature)、Err にはならない。旧実装は `parts.length() == 3` を definition-time で
/// 強制する hardcoded allowlist だったため extra args を unknown-vocab として弾いていたが、
/// registry lookup ベースの新実装ではこの静的チェックが無くなった (意図的な設計変更 — arity
/// mismatch は resolve.mbt 側で kind:filter の実行時 Error として顕在化する、対で固定する次の
/// wbtest 参照)。
test "DR-077 §2: extra args to a registered Transform are NOT a definition-error (arity is a runtime concern)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.count_type(), long=LList([":update:increment:5"])),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      fail(
        "expected Ok (increment:5 is definition-valid, arity is checked at runtime): " +
        deferrs_str(errs),
      )
  }
}

///|
/// End-to-end 保証: installer chain (`parse_definition`) が組んだ @engine.Scope に対する CLI 発火
/// (`-vvv`) → `parse()` の生 binding 列 → `resolve_scope` の cli seat fold、という完全なパイプライン
/// が DR-077 の実運用シナリオ (`-v -v -v` = verbose level 3) を一気通貫で満たすことを固定する
/// (resolve_wbtest.mbt の低レベル `ceff` 直接構築テストと対をなす、installer 由来の @engine.Scope での確認)。
test "DR-077 end-to-end: parse_definition → parse → resolve_scope ledgers -vvv to 3" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.count_type(), long=LBool(true), short=['v']),
    ],
  }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(@engine.ScopeNode(sc), ["-vvv"], defs=Map([]))
  match o {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) => {
          let mut found = false
          for b in resolved {
            if b.key == "verbose" {
              found = true
              assert_eq(b.value, @engine.VNum(3.0))
            }
          }
          assert_true(found)
        }
        Err(_) => fail("expected Ok from resolve_scope")
      }
    _ =>
      fail(
        "expected @engine.Success from parse (-vvv should parse as 3 short cluster fires)",
      )
  }
}

// ── positional × or × repeat (issue 2026-07-09-positional-or-repeat-lowering-gap) ─────

///|
/// 保証: DR-043「repeat の対象要素は形を問わない」は ref head だけでなく **BOr (構造 or) head にも
/// 一様に適用される** — `lower_positional` の BOr ケースは以前 `elem_repeat(e)` を一切見ず常に
/// `@engine.Or(nodes)` を単発で積んでいた (installer.mbt 旧コメント「repeat との組合せは対象 fixture に無いので
/// 未対応」)。`{name:"hlcolors", repeat:{min:1}, or:[{seq:rgb 3数値}, {type:"string", name:"colorname"}]}`
/// で `["red","blue"]` (2 文字列) が unexpected-token になっていたのがこのギャップの症状。
/// `lower_repeat_head(e, @engine.Or(nodes), registry, out)` へ配線し、hand-built `@engine.Many(@engine.Or(...))` (slice 相当)
/// と同じ「両 or 枝が並列に反復できる」挙動を wire lowering 経由でも実現する。
test "positional or+repeat installer: string branch repeats in parallel with the seq(rgb) branch (issue 2026-07-09)" {
  let rgb_seq : @engine.OrBranch = {
    id: "rgb",
    items: [
      el("r", @builtins.number_type()),
      el("g", @builtins.number_type()),
      el("b", @builtins.number_type()),
    ],
  }
  let name_leaf : @engine.OrBranch = {
    id: "colorname",
    items: [el("colorname", @builtins.string_type())],
  }
  let hlcolors : @engine.ElemDef = {
    ..el("hlcolors", @builtins.string_type()),
    repeat: Some({ min: 1, max: None, lazy_: false }),
    body: BOr([rgb_seq, name_leaf]),
  }
  let def : @engine.Definition = { ..empty_def(), positionals: [hlcolors] }
  let registry : Map[String, @engine.Node] = Map([])
  let sc = match @builtins.lower_definition(def, all_installers(), registry~) {
    Ok(s) => s
    Err(_) => abort("expected Ok(@engine.Scope)")
  }
  // 2 つの文字列トークンは rgb 枝に一致せず、string 枝 (colorname) が 2 回反復して吸収する。
  match
    @engine.parse_tree(@engine.ScopeNode(sc), ["red", "blue"], defs=registry) {
    @engine.Success(bs) => {
      let mut count = 0
      for b in bs {
        if b.key == "colorname" {
          count = count + 1
        }
      }
      assert_eq(count, 2)
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
  // 3 つの数値トークンは (a) rgb 枝 1 反復、(b) string 枝 3 反復、の 2 通りに構造的に読める
  // (DR-038 完全経路 2 本) — ambiguous。
  match
    @engine.parse_tree(@engine.ScopeNode(sc), ["255", "0", "0"], defs=registry) {
    @engine.Ambiguous(d) => assert_eq(d.interpretations.length(), 2)
    other => fail("expected @engine.Ambiguous, got " + render_outcome(other))
  }
}

// ── DR-078 §2 (codex 指摘 1): repeat 自己参照 template 名の user templates namespace 衝突 ──

///|
/// 保証: repeat installer が自己参照 cons template を registry へ登録するとき、要素名そのまま
/// (`e.name`) をキーに使うと、DR-078 で registry を共有するようになった `definitions.templates`
/// のユーザ宣言 (同名) を黙って上書きしてしまう。`registry.set(e.name + "#cons", ...)` への mangle
/// (`#` は DR-046 §4 の自動 id 空間、user ns 外の既裁定) により、ユーザが事前登録した同名キーの
/// エントリが repeat lowering を経ても無傷で残ることを固定する。
test "repeat installer: self-ref cons template key does not collide with a same-named registry entry" {
  let registry : Map[String, @engine.Node] = Map::from_array([
    ("x", @engine.Exact("user-defined-x")),
  ])
  let def : @engine.Definition = {
    ..empty_def(),
    positionals: [
      el(
        "x",
        @builtins.string_type(),
        repeat=Some({ min: 1, max: None, lazy_: false }),
      ),
    ],
  }
  match
    @builtins.lower_definition(def, [@builtins.repeat_installer()], registry~) {
    Ok(_) => {
      // ユーザが事前登録した "x" エントリは repeat lowering 後も無傷 (上書きされていない)。
      assert_eq(registry.get("x"), Some(@engine.Exact("user-defined-x")))
      // repeat 自身の自己参照 template は mangled key "x#cons" に登録される。
      match registry.get("x#cons") {
        Some(_) => ()
        None =>
          fail(
            "expected repeat's self-ref template under the mangled key 'x#cons'",
          )
      }
    }
    Err(_) => fail("expected Ok(@engine.Scope)")
  }
}

// ── DR-047 §5: requires 目的語の「値の有無」判定とフラグの暗黙 default (issue 2026-07-09-constraint-path-filtering-gap の調査結果) ──

///|
/// 保証 (issue 2026-07-09-constraint-path-filtering-gap、DR-047 §5 明確化 kawaz 裁定
/// 2026-07-09 で期待値が反転した wbtest): `requires` の目的語が bool 型 (フラグ含む) の場合、
/// 充足条件は「値の有無」ではなく「解決後の値が true であること」(値源不問)。判定は値源ラダーが
/// 解ける後段でしか行えないため、**`parse()` 単体では bool target の requires を KTop が常に
/// スキップする** (常に pass 扱い、"c" を一切与えなくても @engine.Success のまま — これは vacuous
/// satisfaction ではなく、後段フィルタを通す前の意図された中間状態)。`resolve.mbt` の
/// `apply_requires_filter` (final_filters/accum_filters と同じ側の後段処理) を通して初めて、c が
/// 未解決 (default:false のまま) なら requires 違反として @engine.Failure に確定する — vacuous
/// satisfaction は後段フィルタ適用で解消されることを、この2段 (parse() 単体 / フィルタ後) で
/// 固定する。次の wbtest (target が非フラグ = KTop のまま従来通り) との対で挙動差を確認する。
test "DR-047 §5: requires targeting a FLAG — KTop skips it, apply_requires_filter enforces it" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let c = el("c", @builtins.flag_type(), long=LList([":set"]))
  let def : @engine.Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  // parse() 単体: bool target なので KTop は常に pass 扱い (c を与えなくても @engine.Success)。
  match @engine.parse_tree(root, ["--a"], defs=Map([])) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (KTop skips bool-target requires), got " +
        render_outcome(other),
      )
  }
  // apply_requires_filter を通すと、c=false (未解決、暗黙 default:false) で requires
  // 違反が検出され @engine.Failure に確定する。
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
    ) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.kind == @engine.KConstraint && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (post-filter enforces bool-target requires), got " +
        render_outcome(other),
      )
  }
  // c を CLI で明示指定すれば true に解決され、フィルタ後も @engine.Success のまま。
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["--a", "--c"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      2,
    ) {
    @engine.Success(_) => ()
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (DR-088 §2/§4): `requires` の目的語が非フラグ (env 宣言あり、CLI/default 無し) でも、
/// KTop の探索中判定 (`value_declared`) は「env 宣言がある」ことだけで経路を完全と数える (値の実
/// 解決はしない、bare `parse()` の時点で既に `@engine.Success`) — DR-088 §1「宣言された値源はデフォルトの
/// 存在」の帰結。最終的な充足判定 (真の値があるか) は `apply_requires_filter` (post-parse、解決済み
/// bindings の読者) が担う: 実機再現の本体は次の wbtest ペア (env 実値あり/なし)。
test "DR-088: requires targeting an env-declared non-flag is a complete path at KTop even before resolving" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let c = el("c", @builtins.string_type(), long=LList([":set"]), env=["C"])
  let def : @engine.Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["--a"], defs=Map([])) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (env-declared target counts as a complete path at KTop, DR-088 §2), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (issue value-present-ladder-gap の本体、実機再現の pin、DR-088 §4 の 2 番目の canonical
/// 例): 非bool target `c` が env 経由のみで供給される (CLI/default 無し) 場合、
/// `apply_requires_filter` は resolve 済み値を読んで充足と判定する — 修正前は `value_present`
/// (= committed OR has_default) が env を一切見ず、常に requires_violated になっていた (本 issue
/// の実機再現そのもの)。
test "value-present-ladder-gap: requires targeting an env-only-sourced non-flag survives the filter" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let c = el("c", @builtins.string_type(), long=LList([":set"]), env=["C"])
  let def : @engine.Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map::from_array([("C", "x")]),
      1,
    ) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (env seat supplies c), got " +
        render_outcome(other),
      )
  }
}

///|
/// 対極: env が実際に未設定なら (CLI/default も無し) 従来どおり違反のまま @engine.Failure — env が
/// 「無条件に救済する」わけではないことの固定 (config/inherit 対極テストと対称)。
test "value-present-ladder-gap: requires targeting a non-flag with no env value still violates requires" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let c = el("c", @builtins.string_type(), long=LList([":set"]), env=["C"])
  let def : @engine.Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
    ) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.kind == @engine.KConstraint && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (requires unmet), got " +
        render_outcome(other),
      )
  }
}

// ── issue bool-requires-config-inherit-gap (kawaz 裁定 2026-07-10): DR-047 §5 明確化「値源
// 不問」を config / inherit にも拡張する。上の CLI/env 対の続きとして、config seat / inherit
// seat 経由でのみ true になる bool target が `apply_requires_filter` で正しく生存する
// ことと、その対極 (config/inherit 側が false・不在のときは従来通り違反のまま) を固定する。 ──

///|
/// 保証: bool target `c` が config seat 経由でのみ true になる場合、`apply_requires_filter`
/// は (呼び出し元が渡す) `provider~` を経由して実際に `resolve_scope_tree` で解決した値を参照して
/// 充足と判定する (issue resolve-first-constraint-pipeline Phase 1 — もはや自前ミニラダーを持たず、
/// 本物の resolve を読むだけ)。`c` は CLI/env 未指定のまま、config_file 要素 `cfg` に宣言 default
/// ("/app.toml") を持たせて Phase 1 (config_file 自身のパス解決) を成立させ、provider がそのパスで
/// `{c: true}` を返す。config seat は `installer.mbt` の `has_cf` 規約通り、scope に
/// `is_config_file` 要素が 1 つでもあれば (自身が config_file の要素を除く) 全 value cell に同型で
/// 付与される (DR-050 §3)。
test "issue bool-requires-config-inherit-gap: requires targeting a config-sourced bool survives the filter" {
  let cfg_file = {
    ..el("cfg", @builtins.string_type(), long=LList([":set"])),
    is_config_file: true,
    default_values: Some([@engine.VStr("/app.toml")]),
  }
  let a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let c = el("c", @builtins.flag_type(), long=LList([":set"]))
  let def : @engine.Definition = { ..empty_def(), options: [cfg_file, a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  let config = config_from_json(@json.parse("{\"c\":true}"))
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
      provider=fn(_p) { Some(config) },
    ) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (config seat supplies c=true), got " +
        render_outcome(other),
      )
  }
}

///|
/// 対極: config オブジェクトに `c` が無い / `false` の場合は従来どおり未充足のまま @engine.Failure
/// (config が「無条件に救済する」わけではないことの固定)。
test "issue bool-requires-config-inherit-gap: config-sourced bool absent/false still violates requires" {
  let cfg_file = {
    ..el("cfg", @builtins.string_type(), long=LList([":set"])),
    is_config_file: true,
    default_values: Some([@engine.VStr("/app.toml")]),
  }
  let a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let c = el("c", @builtins.flag_type(), long=LList([":set"]))
  let def : @engine.Definition = { ..empty_def(), options: [cfg_file, a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  fn check_failure(o : @engine.Outcome) -> Unit raise {
    match o {
      @engine.Failure(d) => {
        let mut found = false
        for e in d.errors {
          if e.kind == @engine.KConstraint && e.reason == "requires_violated" {
            found = true
          }
        }
        assert_true(found)
      }
      other =>
        fail(
          "expected @engine.Failure (requires unmet), got " +
          render_outcome(other),
        )
    }
  }
  let config_absent = config_from_json(@json.parse("{}"))
  let config_false = config_from_json(@json.parse("{\"c\":false}"))
  // config オブジェクトに c キー自体が無い (供給なし → default:false へフォールスルー)
  check_failure(
    apply_requires_filter(
      @engine.parse_tree(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
      provider=fn(_p) { Some(config_absent) },
    ),
  )
  // config オブジェクトが c:false を明示供給
  check_failure(
    apply_requires_filter(
      @engine.parse_tree(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
      provider=fn(_p) { Some(config_false) },
    ),
  )
}

///|
/// 保証: bool target `c` が祖先 scope の inherit 経由でのみ true になる場合、
/// `apply_requires_filter` は祖先 scope chain (`table` = `@engine.collect_scopes` 全体) を辿って
/// 充足と判定する (DESIGN §11.2)。root で `c` を CLI 指定し (`--c`)、`sub` サブコマンド内で
/// `a requires c` を宣言、`sub` 自身の `c` は `is_inherit:true` で自前の値を持たない — 祖先
/// (root) の解決済み値 (CLI committed) を見つけて生存する。
test "issue bool-requires-config-inherit-gap: requires targeting an inherit-sourced bool survives the filter" {
  let root_c = el("c", @builtins.flag_type(), long=LList([":set"]))
  let child_a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let child_c = el(
    "c",
    @builtins.flag_type(),
    long=LList([":set"]),
    is_inherit=true,
  )
  let child : @engine.Definition = {
    ..empty_def(),
    options: [child_a, child_c],
  }
  let def : @engine.Definition = {
    ..empty_def(),
    options: [root_c],
    commands: [
      { name: "sub", body: child, export_key: @engine.export_key_unset() },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["--c", "sub", "--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      3,
    ) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (root's committed c=true reaches sub via inherit), got " +
        render_outcome(other),
      )
  }
}

///|
/// 対極: root で `--c` を指定しなければ (祖先も未解決、暗黙 default:false) 従来どおり @engine.Failure
/// (inherit が「無条件に救済する」わけではないことの固定 — 上の config 対極テストと対称)。
test "issue bool-requires-config-inherit-gap: inherit-sourced bool absent still violates requires" {
  let root_c = el("c", @builtins.flag_type(), long=LList([":set"]))
  let child_a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let child_c = el(
    "c",
    @builtins.flag_type(),
    long=LList([":set"]),
    is_inherit=true,
  )
  let child : @engine.Definition = {
    ..empty_def(),
    options: [child_a, child_c],
  }
  let def : @engine.Definition = {
    ..empty_def(),
    options: [root_c],
    commands: [
      { name: "sub", body: child, export_key: @engine.export_key_unset() },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["sub", "--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      2,
    ) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.kind == @engine.KConstraint && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (requires unmet), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (回帰確認): 既存 CLI/env 経由テスト (上の DR-047 §5 対) が config_obj~ 未指定でも
/// 従来どおり動くこと — 新規 config/inherit 経路の追加が既存呼び出しシグネチャを壊していない
/// ことの固定 (`apply_requires_filter` の `config_obj~` 省略時デフォルト `None`)。
test "issue bool-requires-config-inherit-gap: existing CLI-committed bool target still survives without config_obj" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LList([":set"])),
    requires: ["c"],
  }
  let c = el("c", @builtins.flag_type(), long=LList([":set"]))
  let def : @engine.Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match
    apply_requires_filter(
      @engine.parse_tree(root, ["--a", "--c"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      2,
    ) {
    @engine.Success(_) => ()
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

// ── codex Medium 追従 (issue merge-no-separator-marker-gap): separator 無し merge 宣言の
// end-to-end 固定。resolve_wbtest.mbt の合成 @engine.Entity テストは eval.mbt/installer.mbt の value_prim
// ルーティングを一切通らない (@engine.Binding を手組みするため) — この gap は「実 CLI args → parse() →
// resolve_scope」の一気通貫でしか顕在化しなかった (`el()` の `separator: None` 固定と組み合わせて
// merge 宣言だけ足すことで、正に「separator 未宣言」の形が作れる)。 ─────────────────────────

///|
fn resolved_values(
  bs : Array[@engine.Binding],
  key : String,
) -> Array[@engine.Value] {
  let out : Array[@engine.Value] = []
  for b in bs {
    if b.key == key {
      out.push(b.value)
    }
  }
  out
}

///|
/// 保証 (上書き): separator 未宣言の merge 要素でも、マーカーを含まない単一発火は普通に add される
/// (DR-034 §6.3 の縮退 — 1 piece = トークン全体、`@engine.classify_merge_piece` を通しても marker に一致
/// しない文字列はそのまま literal)。
test "codex Medium: merge without separator — no-marker single fire adds (overwrite degenerate)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        @builtins.string_type(),
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match
    @engine.parse_tree(
      @engine.ScopeNode(sc),
      ["--fields", "hello"],
      defs=Map([]),
    ) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(resolved_values(resolved, "fields"), [@engine.VStr("hello")])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (remove 単独): 2 回目の発火 `-hello` は separator が無いので 1 piece のまま
/// `@engine.classify_merge_piece` に渡り、`-` 始まりなので remove マーカーと判定される (旧実装では
/// separator 無しだと separated resident に一切進まず、`-hello` はただの literal 文字列として上書きされ
/// `["-hello"]` になっていた — このケースが退行検知の主眼)。暗黙先頭 `@` が補われ old=[hello] を
/// splice、remove("hello") がそれを削って結果は空になる。
test "codex Medium: merge without separator — a lone remove-marker fire merges against prior old" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        @builtins.string_type(),
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match
    @engine.parse_tree(
      @engine.ScopeNode(sc),
      ["--fields", "hello", "--fields", "-hello"],
      defs=Map([]),
    ) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) => assert_eq(resolved_values(resolved, "fields"), [])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (@ 恒等): 2 回目の発火 `@` 単独も 1 piece のまま splice マーカーと判定され、old (直前発火の
/// [hello]) をそのまま展開する恒等操作になる (結果不変)。
test "codex Medium: merge without separator — a lone splice-marker fire is identity" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        @builtins.string_type(),
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match
    @engine.parse_tree(
      @engine.ScopeNode(sc),
      ["--fields", "hello", "--fields", "@"],
      defs=Map([]),
    ) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(resolved_values(resolved, "fields"), [@engine.VStr("hello")])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (escape): separator 無しでも escape 規約 (先頭 `+` を1個剥がす) は同じ pipeline で効く —
/// `+-x` は marker でなく literal `-x` の add になり、cell 上書き。
test "codex Medium: merge without separator — an escaped piece is a literal add" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        @builtins.string_type(),
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match
    @engine.parse_tree(@engine.ScopeNode(sc), ["--fields", "+-x"], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(resolved_values(resolved, "fields"), [@engine.VStr("-x")])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (DR-085 §1 訂正、kawaz 裁定 2026-07-10): a `regex_match` filter entry whose pattern fails to
/// compile is a definition-error, kind=@engine.DInvalidArgument (spec fixture 昇格済み: fixtures/definition-
/// error/regex-match-compile-invalid-argument.json — 本 wbtest はそれに先行する unit 層の pin として
/// 残す、`accum-update-invalid-range` の wbtest/fixture 対と同じ運用)。`[` は文字クラス開始のみで閉じ
/// `]` を欠く未完成構文 — regex エンジンの compile 段で方言を問わず共通に構文エラーになる (DR-085 §1
/// 波及節の「方言差の出ない共通パターン」条件を満たす不正 pattern)。
test "parse_definition: a regex_match filter with an uncompilable pattern is @engine.DInvalidArgument (DR-085 §1 訂正)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("code", @builtins.string_type(), long=LBool(true), piece_filters=[
        "regex_match:[",
      ]),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (regex_match pattern '[' fails to compile)")
    Err(errs) => {
      let mut has_invalid_argument = false
      for e in errs {
        if e.kind == @engine.DInvalidArgument && e.element == "code" {
          has_invalid_argument = true
        }
      }
      assert_true(has_invalid_argument)
    }
  }
}

///|
/// 保証 (対極、上のテストの境界、[[self-written-rule-blind-spots]] の対極確認): a compilable pattern
/// is NOT rejected at definition time — only compile FAILURE is a definition-error, not the mere
/// presence of a `regex_match` entry.
test "parse_definition: a regex_match filter with a compilable pattern is NOT rejected (対極)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("code", @builtins.string_type(), long=LBool(true), piece_filters=[
        "regex_match:^[a-z]+$",
      ]),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == @engine.DInvalidArgument {
          abort(
            "a regex_match entry with a compilable pattern must not raise @engine.DInvalidArgument",
          )
        }
      }
  }
}

///|
/// 保証: DR-085 波及節 / DR-102 属性分割が要求する 4 相 (piece_filters/value_filters/final_filters/
/// accum_filters) 全てで regex_match pattern compile 検査が効く — `collect_invalid_regex_pattern`
/// は綴りが `regex_match` かどうかの名前一致だけで判定するので、その要素が要求する registry が
/// scalar (final_filters) か ARRAY (accum_filters) かに関わらず compile 検査は無条件に走る。
/// value_filters/final_filters それぞれで固定する (piece_filters は上の2テストが既に固定済み)。
/// accum_filters は非 accum-registry 綴り (unknown-vocab) と compile 失敗 (invalid-argument) が
/// 同時に出るケース (下の対極テスト) で別途固定する。
test "parse_definition: regex_match compile check also fires for value_filters and final_filters" {
  let def_value : @engine.Definition = {
    ..empty_def(),
    options: [
      el("a", @builtins.string_type(), long=LBool(true), value_filters=[
        "regex_match:[",
      ]),
    ],
  }
  match @builtins.lower_definition(def_value, all_installers()) {
    Ok(_) => abort("expected Err (value_filters regex_match compile failure)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == @engine.DInvalidArgument && e.element == "a" {
          found = true
        }
      }
      assert_true(found)
    }
  }
  let def_final : @engine.Definition = {
    ..empty_def(),
    options: [
      el("b", @builtins.string_type(), long=LBool(true), final_filters=[
        "regex_match:[",
      ]),
    ],
  }
  match @builtins.lower_definition(def_final, all_installers()) {
    Ok(_) => abort("expected Err (final_filters regex_match compile failure)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == @engine.DInvalidArgument && e.element == "b" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// 保証 (対極、DR-102 §2 の明確化 note、codex レビュー M-5 — registry 所有ゲート): `accum_filters`
/// (ARRAY filter registry, accum 専用) に `regex_match` (scalar filter registry 専用の descriptor)
/// を書いた場合、pattern compile 検査 (`collect_invalid_regex_pattern`) は「その属性が要求する
/// registry が regex_match を実際に所有する場合のみ」走る — ARRAY filter registry は regex_match を
/// 所有しないため、accum_filters には compile 検査が一切走らず、`collect_unknown_filter` が単純な
/// @engine.DUnknownVocab (綴りが ARRAY registry の owns 集合に無い) のみを出す。旧テストは「両方出る」ことを
/// 固定していたが、これは DR-102 §2「自 registry のみを見る」単純化と矛盾する副次検査だった —
/// 明確化 note を反映しこの契約 (unknown-vocab のみ、invalid-argument は出ない) に更新する。
test "parse_definition: an accum element's accum_filters regex_match entry is unknown-vocab ONLY (registry ownership gate, DR-102 §2)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("c", @builtins.string_type(), long=LBool(true), multiple=true, accum_filters=[
        "regex_match:[",
      ]),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (accum_filters regex_match is not a registered ARRAY filter)",
      )
    Err(errs) => {
      let mut has_invalid_argument = false
      let mut has_unknown_vocab = false
      for e in errs {
        if e.element == "c" && e.kind == @engine.DInvalidArgument {
          has_invalid_argument = true
        }
        if e.element == "c" && e.kind == @engine.DUnknownVocab {
          has_unknown_vocab = true
        }
      }
      assert_false(has_invalid_argument)
      assert_true(has_unknown_vocab)
    }
  }
}

// ── issue type-none-support (DR-089): type 省略 = 値空間が空の node。値空間 (type) と消費 (構造) は
// 直交 (§1) — none は 0 トークンの純トリガにも repeat+filter の「食って捨てる」構造にもなれる。
// committed 基準の制約 (conflicts/exclusive/requires トリガ側) には通常どおり参加するが、値充足を
// 要求される requires 目的語には立てず定義時 definition-error (§4)。結果には現れない (§3)。 ────

///|
/// 保証: `type` を省略した「消費 0 の純トリガ」(DR-089 §2 canonical 例、`long:true` のみ) が
/// committed 制約 (`conflicts_with`) の判定に通常どおり参加する — トリガとして機能することの固定。
test "DR-089: an omitted-type (none) pure trigger participates in conflicts as a committed trigger" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LBool(true)),
    conflicts_with: ["b"],
  }
  let b = el("b", @builtins.flag_type(), long=LList([":set"]))
  let def : @engine.Definition = { ..empty_def(), options: [a, b] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["--a", "--b"], defs=Map([])) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.reason == "conflicts_with_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (conflicts enforced), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証: none 型セルが発火しても、シンプルモードの結果オブジェクトにキーが一切現れない (DR-089
/// §3「値の結果には現れない」、DR-051 §1/§4 の「値の無さはフィールドの不在」と同じ posture)。
test "DR-089: a fired none-typed pure trigger never appears in the result" {
  let sep = el("sep", @builtins.none_type(), long=LBool(true))
  let def : @engine.Definition = { ..empty_def(), options: [sep] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["--sep"], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(
            render_rval_sorted(build_result_export(sc, resolved, Map([]))),
            "{}",
          )
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (対極): none を明示 (`type:"none"`) しても消費 0 純トリガとして同じ挙動になる — 省略と
/// 明示綴りが同じタグに解決すること (DR-089 §2「省略は none の糖衣」) の固定。
test "DR-089: explicit type:none behaves identically to an omitted type" {
  let sep = el("sep2", @builtins.none_type(), long=LBool(true))
  let def : @engine.Definition = { ..empty_def(), options: [sep] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["--sep2"], defs=Map([])) {
    @engine.Success(bs) => assert_eq(bs.length(), 1)
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証: none 型を持つ positional + repeat の「食って捨てる」構造 (DR-089 §2 の `{"type": "none",
/// "repeat": {"min": 0}}` 例) が構造的に複数トークンを消費できる (消費は構造の関心、type とは直交
/// という §1 の帰結の end-to-end 固定)。
test "DR-089: a none-typed repeat positional structurally consumes multiple tokens (eat-and-discard)" {
  let colon = pos(
    "colon",
    @builtins.none_type(),
    repeat=Some({ min: 0, max: None, lazy_: false }),
  )
  let def : @engine.Definition = { ..empty_def(), positionals: [colon] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["x", "y"], defs=Map([])) {
    @engine.Success(bs) => {
      let mut n = 0
      for b in bs {
        if b.key == "colon" {
          n = n + 1
        }
      }
      assert_eq(n, 2)
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (DR-093 §3、DR-089 §4 の「値充足を要求される席には none は立てない → definition-error」を
/// 置換): none を requires 目的語に宣言しても definition-error にはならない — `A requires B` で B が
/// マーカー (値を運ばず発火事実だけを持つ要素) であることは意味を持つ宣言であり、definition-error
/// として弾く理由がない (DR-093 §1 の型委譲原理: 目的語の充足は「発火 = committed」で定義される)。
test "DR-093: a none-typed requires target is NOT a definition-error (supersedes DR-089 §4)" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LBool(true)),
    requires: ["c"],
  }
  let c = el("c", @builtins.none_type(), long=LBool(true))
  let def : @engine.Definition = { ..empty_def(), options: [a, c] }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(_) =>
      fail(
        "expected Ok (DR-093 §3 supersedes the DR-089 §4 definition-error)",
      )
  }
}

///|
/// 保証 (DR-093 §3 の帰結、対): none requires 目的語の充足は発火 (committed) — c ("--c" 相当の純
/// トリガ) が発火すれば a の requires が満たされ @engine.Success、発火しなければ requires_violated の
/// constraint Error で完全経路 0 本 = @engine.Failure になる。CRequires の目的語判定 (resolve.mbt の
/// `eval_requires`/`satisfied`) が none 分岐を正しく通ることを固定する。
test "DR-093: a none-typed requires target is satisfied by firing (committed), unmet otherwise" {
  let a = {
    ..el("a", @builtins.flag_type(), long=LBool(true)),
    requires: ["c"],
  }
  let c = el("c", @builtins.none_type(), long=LBool(true))
  let def : @engine.Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  // c 発火あり: requires 充足、@engine.Success (a=true, c は値空間なしなので結果に現れない)。
  match @engine.parse_tree(root, ["--a", "--c"], defs=Map([])) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (c fired, requires satisfied), got " +
        render_outcome(other),
      )
  }
  // c 発火なし: requires 未充足、constraint required_violated ではなく requires_violated の @engine.Failure。
  match @engine.parse_tree(root, ["--a"], defs=Map([])) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.element == "a" && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (c not fired, requires unmet), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (DR-093 §1/§2、値空間ありの通常 type の基本輪郭): required:true の option は最終状態の値の
/// 有無で充足を判定する — CLI 未指定 (値源なし) は required_violated の @engine.Failure、CLI 指定は @engine.Success。
/// DR-047 §5 の「値空間ありは最終状態の値の有無」が本 DR で不変のまま一様形に組み込まれたことの固定。
test "DR-093: a required:true option (value-space) is satisfied by CLI value, unmet with no value source" {
  let name = {
    ..el("name", @builtins.string_type(), long=LBool(true)),
    required: true,
  }
  let def : @engine.Definition = { ..empty_def(), options: [name] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  // 未指定: 値源 (default/env/config/inherit) が無いので required 未充足、@engine.Failure。
  match @engine.parse_tree(root, [], defs=Map([])) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.element == "name" && e.reason == "required_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (no value source, required unmet), got " +
        render_outcome(other),
      )
  }
  // CLI 指定: 値が在るので @engine.Success。
  match @engine.parse_tree(root, ["--name", "x"], defs=Map([])) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (CLI value present), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (DR-093 §1/§2、DR-047 §5「required:true + default は常に充足」が本 DR で不変): default を
/// 持つ要素は required:true でも CLI 未指定のまま自明に充足する — 「default があるのに明示も強制」
/// は表現不能 (DR-047 §6-3 の受け入れる帰結)。
test "DR-093: a required:true option with a declared default is vacuously satisfied (unchanged from DR-047 §5)" {
  let name = {
    ..el("name", @builtins.string_type(), long=LBool(true)),
    required: true,
    default_values: Some([@engine.VStr("fallback")]),
  }
  let def : @engine.Definition = { ..empty_def(), options: [name] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, [], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(
            render_rval_sorted(build_result_export(sc, resolved, Map([]))),
            "{name=fallback}",
          )
        Err(_) => fail("expected Ok resolve")
      }
    other =>
      fail(
        "expected @engine.Success (default satisfies required vacuously), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (DR-093 §2/§5、die の motivating case そのもの): none 型の dd 要素 (`dd_match` 未使用、
/// `@engine.DdSat` 発火経路) に required:true を付けると、発火 (committed) で充足し、未発火は
/// required_violated の constraint Error で完全経路 0 本 = @engine.Failure になる。kawaz/die の `--`
/// 必須が `{"type":"dd","required":true}` (新規 wire 語彙ゼロ) で表現できることの実装側の固定。
test "DR-093: a required:true dd element (@engine.DdSat) is satisfied by firing, unmet otherwise" {
  let dd = { ..el("--", @builtins.none_type(), is_dd=true), required: true }
  let x = pos("x", @builtins.string_type())
  let def : @engine.Definition = {
    ..empty_def(),
    options: [dd],
    positionals: [x],
  }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  // -- 発火あり: required 充足、@engine.Success。dd は値空間なしなので結果に "--" は現れない (DR-089 §3)。
  match @engine.parse_tree(root, ["--", "msg"], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(
            render_rval_sorted(build_result_export(sc, resolved, Map([]))),
            "{x=msg}",
          )
        Err(_) => fail("expected Ok resolve")
      }
    other =>
      fail("expected @engine.Success (-- fired), got " + render_outcome(other))
  }
  // -- 発火なし: required 未充足、constraint required_violated の @engine.Failure (kawaz/die の `die msg` 相当)。
  match @engine.parse_tree(root, ["msg"], defs=Map([])) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.element == "--" && e.reason == "required_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (-- not fired, required unmet), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (DR-093 §2/§5 の一般化、DR-090 拡張軸): `dd_match` を使う dd 要素 (`@engine.DdMatchSat` 発火経路) も
/// 同じ型委譲で required:true を扱う — 発火 (committed) で充足、未発火は required_violated。spelling
/// (トリガ綴り/パターン) と要素名が分離するケース (DR-090 §2「match があるとき name はトリガ綴りに
/// 使われず、要素の同一性・表示軸のみに効く」) でも、committed 観測は要素名で正しく行われることを
/// 固定する (`@engine.DdMatchSat` の 4 番目フィールド `elem_name` がこの委譲判定の実装対象)。
test "DR-093: a required:true dd element with dd_match (@engine.DdMatchSat) is satisfied by firing, unmet otherwise" {
  let dd = {
    ..el("marker", @builtins.none_type(), is_dd=true, dd_match=Some("^--$")),
    required: true,
  }
  let x = pos("x", @builtins.string_type())
  let def : @engine.Definition = {
    ..empty_def(),
    options: [dd],
    positionals: [x],
  }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["--", "msg"], defs=Map([])) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (marker fired via dd_match), got " +
        render_outcome(other),
      )
  }
  match @engine.parse_tree(root, ["msg"], defs=Map([])) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.element == "marker" && e.reason == "required_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (marker not fired, required unmet), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (DR-093 §3/§5、die の骨格そのもの — decode gap の追加サイクル): positional トリガの
/// requires が constraint 登録 (`inst_constraint`、option/positional 共通の `all` 配列) から
/// 評価 (`eval_constraints`/`eval_requires`) まで正しく効く。`dec_positional` の `allowed_keys` に
/// `requires` が無かった decode gap (option 側 `dec_option` には既にあった非対称) の修正対象。
/// 目的語が none 型 (dd) の場合、目的語の充足は発火 (committed、DR-093 §3)。
test "DR-093: a positional's requires (trigger side) reaches constraint registration and evaluation" {
  let dd = el("--", @builtins.none_type(), is_dd=true)
  let args = {
    ..pos("args", @builtins.string_type(), optional=true),
    requires: ["--"],
  }
  let def : @engine.Definition = {
    ..empty_def(),
    options: [dd],
    positionals: [args],
  }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  // -- 発火してから args が msg を消費: requires 充足、@engine.Success。
  match @engine.parse_tree(root, ["--", "msg"], defs=Map([])) {
    @engine.Success(_) => ()
    other =>
      fail(
        "expected @engine.Success (dd fired before args consumes), got " +
        render_outcome(other),
      )
  }
  // args (トリガ) が msg を消費して committed になるが -- (目的語) 未発火: requires 未充足。
  // 取り分次元の dead-end (0 消費側の残余 unexpected_token) も併走しうる (DR-053 §2「取り分次元の
  // dead-end も全保持」) ので、@engine.Failure であることと errors に requires_violated が「含まれる」こと
  // だけを見る (exact set 一致ではなく contains — fixture 側の輪郭確認とは異なる粒度で十分)。
  match @engine.parse_tree(root, ["msg"], defs=Map([])) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.element == "args" && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure to include requires_violated among held errors, got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (team-lead 監査 2026-07-11): none には値空間が無いので、値源を宣言する
/// `env`/`config_key`/`inherit` は静的に既知の不成立構成であり definition-error になる (DR-089
/// §4、DR-083 §5 と同型)。3 種の値源宣言をそれぞれ個別の none 要素に付けて固定する。
test "DR-089: a none-typed element declaring env/config_key/inherit is a definition-error" {
  let with_env = el("has_env", @builtins.none_type(), long=LBool(true), env=[
    "X",
  ])
  let with_config_key = {
    ..el("has_config_key", @builtins.none_type(), long=LBool(true)),
    config_key: Some(["k"]),
  }
  let with_inherit = {
    ..el("has_inherit", @builtins.none_type(), long=LBool(true)),
    is_inherit: true,
  }
  let def : @engine.Definition = {
    ..empty_def(),
    options: [with_env, with_config_key, with_inherit],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (none element with env/config_key/inherit is a definition-error)",
      )
    Err(errs) => {
      let mut has_env_flagged = false
      let mut has_config_key_flagged = false
      let mut has_inherit_flagged = false
      for e in errs {
        if e.element == "has_env" {
          has_env_flagged = true
        }
        if e.element == "has_config_key" {
          has_config_key_flagged = true
        }
        if e.element == "has_inherit" {
          has_inherit_flagged = true
        }
      }
      assert_true(has_env_flagged)
      assert_true(has_config_key_flagged)
      assert_true(has_inherit_flagged)
    }
  }
}

///|
/// DR-099 §3/§7: `is_tty=true` かつ `tty_stream=None` (= bare `type:"tty"`/`"builtin/tty"` の decode
/// 結果、あるいは definitions.types 経由で `tty_stream` を書き忘れた shadow) は definition-error
/// (kind=invalid-range) — fixture (`definition-error/tty-stream-missing.json`) は JSON decode 経由
/// (bare/explicit_ns の 2 spelling) をまとめて検査するのに対し、ここでは `collect_tty_stream_missing`
/// (installer.mbt) を @engine.ElemDef 直叩きで単体固定する (decode 層を経由しない、より狭い axis)。
test "DR-099 §3/§7: an option selecting builtin/tty without tty_stream is a definition-error" {
  let use_color = el(
    "use_color",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=None,
  )
  let def : @engine.Definition = { ..empty_def(), options: [use_color] }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (builtin/tty preset missing tty_stream is a definition-error, DR-099 §3/§7)",
      )
    Err(errs) => {
      let mut flagged = false
      for e in errs {
        if e.element == "use_color" && e.kind == @engine.DInvalidRange {
          flagged = true
        }
      }
      assert_true(flagged)
    }
  }
}

///|
/// DR-099 §3/§7 の definition-error 検査が positionals にも一様に効くことの固定 — fixture は
/// options のみを検査対象にしているため、positional 側の同じ検査経路
/// (`collect_tty_stream_missing` の `def.positionals` 走査) は fixture から見えない軸 (旧 DR-098 §4
/// テストと同じ役割分担)。
test "DR-099 §3/§7: a positional selecting builtin/tty without tty_stream is a definition-error" {
  let pos_elem = el(
    "stdin_tty",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=None,
  )
  let def : @engine.Definition = { ..empty_def(), positionals: [pos_elem] }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (builtin/tty preset missing tty_stream is a definition-error, DR-099 §3/§7)",
      )
    Err(errs) => {
      let mut flagged = false
      for e in errs {
        if e.element == "stdin_tty" && e.kind == @engine.DInvalidRange {
          flagged = true
        }
      }
      assert_true(flagged)
    }
  }
}

///|
/// DR-099 §2: `ensure_entity` (installer.mbt) は is_tty 要素を @builtins.bool_type() の暗黙 default:false プリセット
/// (LOWERING §A.5 / DR-051 §2、上の flag テストが固定するのと同じ機構) から除外する — 除外しないと
/// 「宣言 default 無し」という状態が `ensure_entity` の時点で消え、`resolve.mbt` の tty fold が観測
/// なし時に absent へ落ちる余地を失う (常に false が浮かび上がってしまう)。ここでは `parse_definition`
/// を通した実 @engine.Entity の `default_values` が `None` のままであることを直接固定する
/// (resolve.mbt 側の fold-fallthrough 自体は resolve_wbtest.mbt が別途検証)。
test "ensure_entity: a tty preset element without an explicit default keeps default_values None (DR-099 §2)" {
  let use_color = el(
    "use_color",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stdout"),
  )
  let def : @engine.Definition = { ..empty_def(), options: [use_color] }
  let sc = ok_scope(def, all_installers())
  assert_eq(entity_of(sc, "use_color").unwrap().default_values, None)
}

///|
/// 対極: 値源を一切宣言しない none 要素 (純トリガ) は影響を受けない — このチェックが none 全般を
/// 誤って拒否しないことの固定 (上の definition-error テストの反例)。
test "DR-089 対極: a none-typed element with no value-source declaration is not a definition-error" {
  let sep = el("sep3", @builtins.none_type(), long=LBool(true))
  let def : @engine.Definition = { ..empty_def(), options: [sep] }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) => {
      let mut msg = ""
      for e in errs {
        msg = msg + e.element + ":" + e.hint + " "
      }
      abort("expected Ok, got Err: " + msg)
    }
  }
}

///|
/// 対極: 既存の明示 type (@builtins.flag_type()) を持つ要素は type-none 対応 (decoder の省略受理、KTop/resolve の
/// none 判定分岐) を追加しても一切影響を受けない — 純粋な追加機能であることの固定。
test "DR-089 対極: a pre-existing explicit-type element is unaffected by none support" {
  let x = el("x", @builtins.flag_type(), long=LList([":set"]))
  let def : @engine.Definition = { ..empty_def(), options: [x] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["--x"], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(
            render_rval_sorted(build_result_export(sc, resolved, Map([]))),
            "{x=true}",
          )
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

// ── issue dr-088-positional-default-verification: 素の positional (optional/repeat 無し) +
// default 宣言は、DR-088 §1「宣言された値源はデフォルトの存在」により「トークンが無くても経路完全
// → 遅延解決で default 実体化」となる。旧実装は default の宣言を無視し、トークン 0 個を常に
// missing_operand の経路不成立として扱っていた (`lower_positional` が無条件に mandatory な値
// primitive を push、DR-044 の「配列に包む」optional 糖衣を明示指定しない限り 0-or-1 の構造を
// 表現できなかった)。 ────────────────────────────────────────────────────────

///|
/// 保証 (実機再現の pin、DR-088 §1/§2 の canonical 適用): `{name, type, default}` の素の
/// positional (optional/repeat 宣言なし) は、トークン供給なしでも @engine.Success になり、宣言済み
/// default の値が結果に実体化される — 旧実装は同じ入力で @engine.Failure(missing_operand) になっていた。
test "DR-088: a plain scalar positional with a declared default is a complete path with 0 tokens" {
  let seconds = {
    ..pos("seconds", @builtins.int_type()),
    default_values: Some([@engine.VNum(10.0)]),
  }
  let def : @engine.Definition = { ..empty_def(), positionals: [seconds] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, [], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(
            render_rval_sorted(build_result_export(sc, resolved, Map([]))),
            "{seconds=10}",
          )
        Err(_) => fail("expected Ok resolve")
      }
    other =>
      fail(
        "expected @engine.Success (declared default makes the path complete), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証: 同じ定義でトークンを供給すれば、供給値が (default ではなく) 結果に現れる — 構造的
/// optional 化がトークン供給時の通常経路を壊していないことの固定 (対称の成功面)。
test "DR-088: a plain scalar positional with a declared default still consumes a supplied token" {
  let seconds = {
    ..pos("seconds", @builtins.int_type()),
    default_values: Some([@engine.VNum(10.0)]),
  }
  let def : @engine.Definition = { ..empty_def(), positionals: [seconds] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["5"], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(
            render_rval_sorted(build_result_export(sc, resolved, Map([]))),
            "{seconds=5}",
          )
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 対極: default 宣言の無い素の positional は、この変更後も従来どおりトークン 0 個で
/// missing_operand の @engine.Failure になる — `fixtures/absent/required-positional.json` が pin する
/// 「必須 positional は absent にならない (present か parse failure の二択)」の輪郭を、この
/// 変更が壊していないことの固定 (構造的 optional 化は「宣言済み値源がある場合」限定)。
test "DR-088 対極: a plain scalar positional with NO declared default still misses on 0 tokens" {
  let file = pos("file", @builtins.string_type())
  let def : @engine.Definition = { ..empty_def(), positionals: [file] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, [], defs=Map([])) {
    @engine.Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.element == "file" && e.reason == "missing_operand" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Failure (no declared source, still required), got " +
        render_outcome(other),
      )
  }
}

///|
/// 対極2: `optional:true` (repeat 糖衣) を明示した positional は、この変更の影響を受けず従来どおり
/// 配列で結果に出る (DR-044 「max=1 でも配列」の特別化なし) — 構造的 optional 化の新経路
/// (`opt_node`) は `elem_repeat(e) is None` の場合限定であることの固定。
test "DR-088 対極2: an explicit optional:true positional is unaffected (still array-shaped)" {
  let tag = pos("tag", @builtins.string_type(), optional=true)
  let def : @engine.Definition = { ..empty_def(), positionals: [tag] }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, [], defs=Map([])) {
    @engine.Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(
            render_rval_sorted(build_result_export(sc, resolved, Map([]))),
            "{tag=[]}",
          )
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

// ── issue dr-090-dd-match-self-implementation: dd の一般化 (トリガ形 exact|pattern) ×
// (自己保持 self drop|keep)。canonical 用途は (exact,drop)=従来 dd と (pattern,keep)=xargs型。
// **host regex dialect の実機確認**: DR-090 §2/§3 の canonical 例そのままの `"^[^-]"` は
// この host (MoonBit core `@string.Regex`) では **compile 失敗する** (`[^-]` — `^` 直後の
// 未エスケープ `-` が範囲指定として誤解釈される)。エスケープした `"^[^\\-]"` (MoonBit 文字列
// リテラルでは `\\-`、JSON 文字列としては `"^[^\\-]"`) なら compile が通る — 本 wbtest は
// エスケープ済み pattern を使う。spec fixture 側にも報告済み (完了報告参照)。 ──────────────

///|
fn dd_value_to_str(v : @engine.Value) -> String {
  match v {
    @engine.VStr(s) => s
    @engine.VNum(d) => d.to_string()
    @engine.VBool(b) => b.to_string()
  }
}

///|
/// 保証 (実機再現の pin、DR-090 §2/§3 の canonical 適用): `xargs -n 1 rm -f a` 型の輪郭。
/// `-n` は known option として発火し値 `1` を消費 (値スロットは raw 消費、DR-041 §4 — dd pattern
/// と形が交わらない)。`rm` (最初の非ハイフン operand) が pattern dd に一致して発火・自己保持
/// (self:keep、消費0で @engine.Accept) — `rm` 自身を含め以降 (`-f`, `a`) が positional 域 + severed に
/// 流れ、`-f` は既知 option の綴りでも severed により raw のまま (再発火しない、実 xargs と同じ)。
test "DR-090: xargs-style pattern dd (self:keep) — option fires, value slot raw, pattern-dd self-keep, tail severed" {
  let n = { ..el("n", @builtins.int_type(), short=['n']) }
  let dd = {
    ..el(
      "dd",
      @builtins.string_type(),
      is_dd=true,
      dd_match=Some("^[^\\-]"),
      dd_self_keep=true,
    )
  }
  let rest = pos(
    "rest",
    @builtins.string_type(),
    repeat=Some({ min: 0, max: None, lazy_: false }),
  )
  let def : @engine.Definition = {
    ..empty_def(),
    options: [n, dd],
    positionals: [rest],
  }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["-n", "1", "rm", "-f", "a"], defs=Map([])) {
    @engine.Success(bs) => {
      assert_eq(elem_value_bs(bs, "n"), Some("1"))
      let rest_vals : Array[String] = []
      for b in bs {
        if b.key == "rest" {
          rest_vals.push(dd_value_to_str(b.value))
        }
      }
      assert_eq(rest_vals, ["rm", "-f", "a"])
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
fn elem_value_bs(bs : Array[@engine.Binding], key : String) -> String? {
  let mut v : String? = None
  for b in bs {
    if b.key == key {
      v = Some(dd_value_to_str(b.value))
    }
  }
  v
}

///|
/// 対極 (輪郭固定): 従来の exact dd (`match`/`self` いずれも未宣言) は本 DR の変更で一切
/// 影響を受けない — `--` を消費して捨て (self:drop 既定)、以降が severed で全 raw になる
/// 挙動は不変。@engine.DdSat ノードがそのまま使われ続けることの間接固定 (`@engine.DdMatchSat` へ切り替わらない)。
test "DR-090 対極: exact dd (no match/self declared) is unaffected — drop + severed as before" {
  let dd = el("--", @builtins.string_type(), is_dd=true)
  let rest = pos(
    "rest",
    @builtins.string_type(),
    repeat=Some({ min: 0, max: None, lazy_: false }),
  )
  let def : @engine.Definition = {
    ..empty_def(),
    options: [dd],
    positionals: [rest],
  }
  let sc = ok_scope(def, all_installers())
  let root = @engine.ScopeNode(sc)
  match @engine.parse_tree(root, ["--", "-x", "y"], defs=Map([])) {
    @engine.Success(bs) => {
      let rest_vals : Array[String] = []
      for b in bs {
        if b.key == "rest" {
          rest_vals.push(dd_value_to_str(b.value))
        }
      }
      // "--" 自身は消費されて捨てられる (self:drop) ので rest には現れない。
      assert_eq(rest_vals, ["-x", "y"])
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// 保証: dd の `match` 正規表現が host dialect で compile 不能な場合、definition-error になる
/// (DR-090 §2、DR-085 §1 訂正の regex_match pattern compile 失敗と同じ kind=@engine.DInvalidArgument)。
test "DR-090: an uncompilable dd match pattern is a definition-error" {
  let dd = {
    ..el("dd", @builtins.string_type(), is_dd=true, dd_match=Some("["))
  }
  let def : @engine.Definition = { ..empty_def(), options: [dd] }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (uncompilable dd match pattern)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.element == "dd" && e.kind == @engine.DInvalidArgument {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// 対極: compile 可能な pattern は definition-error にならない (上のテストの境界確認、
/// self-written-rule-blind-spots の対極確認と同じ姿勢)。
test "DR-090 対極: a compilable dd match pattern is NOT rejected" {
  let dd = {
    ..el("dd", @builtins.string_type(), is_dd=true, dd_match=Some("^[^\\-]"))
  }
  let def : @engine.Definition = { ..empty_def(), options: [dd] }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == @engine.DInvalidArgument {
          abort(
            "a dd with a compilable match pattern must not raise @engine.DInvalidArgument",
          )
        }
      }
  }
}

// ── DR-091 §3 / DR-096 §1: long_prefix / long_eq_sep end-to-end ─────────────

///|
/// Guarantees (DR-091 §3 "if=(type: file) 級" motivating case): a `long_prefix:"" +
/// long_eq_sep:@engine.EsRequire` element parses its eq-split form (`if=abc`, one token) — this is
/// the ONLY entry point left once the space-form main entry is withheld (below).
test "DR-091 §3 / DR-096 §1 end-to-end: long_prefix:\"\" + long_eq_sep:@engine.EsRequire accepts the eq form" {
  let if_elem = {
    ..el(
      "if",
      @builtins.string_type(),
      long=LBool(true),
      long_prefix="",
      long_eq_sep=@engine.EsRequire,
    )
  }
  let def : @engine.Definition = { ..empty_def(), options: [if_elem] }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(@engine.ScopeNode(sc), ["if=abc"], defs=Map([]))
  match o {
    @engine.Success(bs) => {
      let mut found = false
      for b in bs {
        if b.key == "if" {
          found = true
          assert_eq(b.value, @engine.VStr("abc"))
        }
      }
      assert_true(found)
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

///|
/// Guarantees (DR-091 §3 "long の space-form main entry の登録をスキップ"): with
/// `long_eq_sep:@engine.EsRequire`, the SPACE form (`if abc`, 2 tokens, no `=`) has NO entry point
/// at all — `inst_long` withheld the main entry, and `@builtins.eq_split` never fires on a token without `=`
/// (`node.mbt`'s `@builtins.eq_split` doc comment: "Fires only on tokens containing `=`"). With no other
/// element in this @engine.Definition able to consume either token, the parse must FAIL — this is the
/// direct 対極 of the eq-form acceptance case above.
test "DR-091 §3 / DR-096 §1 end-to-end: long_eq_sep:@engine.EsRequire rejects the space form (対極 of eq-form acceptance)" {
  let if_elem = {
    ..el(
      "if",
      @builtins.string_type(),
      long=LBool(true),
      long_prefix="",
      long_eq_sep=@engine.EsRequire,
    )
  }
  let def : @engine.Definition = { ..empty_def(), options: [if_elem] }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(@engine.ScopeNode(sc), ["if", "abc"], defs=Map([]))
  match o {
    @engine.Failure(_) => ()
    other =>
      fail(
        "expected @engine.Failure (space form must have no entry point), got " +
        render_outcome(other),
      )
  }
}

///|
/// Guarantees (DR-096 §3.3 — `long_eq_sep:@engine.EsRequire` の opt-in 衝突排除手段の直接固定): a
/// `long_prefix:""` + `long_eq_sep:@engine.EsRequire` element coexisting with an UNRELATED plain positional
/// in the SAME @engine.Definition does not swallow that positional's bare token — `foo` (no `=`) still
/// binds to `target`, `if` stays unfired (absent from the bindings). This is the eq-gate mechanism
/// an app can opt into to definitionally avoid the collision (空 prefix 単独では衝突は @engine.Ambiguous
/// に落ちる、`fixtures/matcher-readings/long-empty-prefix-operand-collision.json` 参照 — この
/// テストは @engine.EsRequire 併用時の非衝突を固定するもので、空 prefix の合法条件ではない)。
test "DR-096 §3.3 end-to-end: long_prefix:\"\" + long_eq_sep:@engine.EsRequire does not collide with a sibling plain positional (opt-in 衝突排除)" {
  let if_elem = {
    ..el(
      "if",
      @builtins.string_type(),
      long=LBool(true),
      long_prefix="",
      long_eq_sep=@engine.EsRequire,
    )
  }
  let target = el("target", @builtins.string_type())
  let def : @engine.Definition = {
    ..empty_def(),
    options: [if_elem],
    positionals: [target],
  }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(@engine.ScopeNode(sc), ["foo"], defs=Map([]))
  match o {
    @engine.Success(bs) => {
      let mut target_found = false
      let mut if_found = false
      for b in bs {
        if b.key == "target" {
          target_found = true
          assert_eq(b.value, @engine.VStr("foo"))
        }
        if b.key == "if" {
          if_found = true
        }
      }
      assert_true(target_found)
      assert_false(if_found)
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

// ── issue scope-config-object-gap: short_prefix / long_eq_sep wiring ──

///|
/// 保証 (DESIGN §7.2 / LOWERING §B.2「config `short_prefix`/`short_combine` がパラメータ」):
/// `inst_short` は `e.short_prefix` を `@builtins.short_combine` matcher の `prefix` に使う (旧ハードコード
/// `"-"` を置換)。既定の `"-"` はこのテストの対極 (long installer 同型テストの `"--"` 既定と対)。
test "short installer: e.short_prefix drives the @builtins.short_combine matcher's prefix (default \"-\")" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("verbose", @builtins.flag_type(), short=['v'])],
  }
  let sc = ok_scope(def, [@builtins.short_installer()])
  assert_eq(sc.greedy.length(), 1)
  match sc.greedy[0] {
    @engine.NativeMatch(matcher) => {
      assert_eq(matcher.kind(), "short_combine")
      let candidates = matcher.candidates()
      assert_eq(candidates.length(), 1)
      assert_eq(candidates[0].spelling, "-v")
      assert_eq(candidates[0].origin, "verbose")
    }
    _ => abort("expected @engine.NativeMatch")
  }
}

///|
/// 保証 (同上、非既定側): `short_prefix: "+"` (BSD 慣習等) を指定した要素は `@builtins.short_combine` matcher
/// の prefix にそのまま反映される。
test "short installer: a non-default short_prefix (\"+\") is honored" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.flag_type(), short=['v'], short_prefix="+"),
    ],
  }
  let sc = ok_scope(def, [@builtins.short_installer()])
  match sc.greedy[0] {
    @engine.NativeMatch(matcher) => {
      let candidates = matcher.candidates()
      assert_eq(candidates.length(), 1)
      assert_eq(candidates[0].spelling, "+v")
    }
    _ => abort("expected @engine.NativeMatch")
  }
}

///|
/// 保証 (同上、grouping 側 — DR-091 §3 の `eq_group`/`long_prefix` grouping と同型): 異なる
/// `short_prefix` を持つ要素は同じ `@builtins.short_combine` matcher に混ざらず、prefix ごとに別 matcher が
/// 立つ (異なる token 空間を誤って結合しない — `eq_group` の doc comment と同じ理由付け)。
test "short installer: distinct short_prefix values get SEPARATE @builtins.short_combine matchers (no cross-prefix combine)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.flag_type(), short=['v']),
      el("weird", @builtins.flag_type(), short=['w'], short_prefix="+"),
    ],
  }
  let sc = ok_scope(def, [@builtins.short_installer()])
  assert_eq(sc.greedy.length(), 2)
  let mut dash_count = 0
  let mut plus_count = 0
  for g in sc.greedy {
    match g {
      @engine.NativeMatch(matcher) => {
        let candidates = matcher.candidates()
        assert_eq(candidates.length(), 1)
        match candidates[0].spelling {
          "-v" => dash_count = dash_count + 1
          "+w" => plus_count = plus_count + 1
          other => abort("unexpected short matcher candidate: " + other)
        }
      }
      _ => abort("expected @engine.NativeMatch")
    }
  }
  assert_eq(dash_count, 1)
  assert_eq(plus_count, 1)
}

///|
/// 保証 (DR-014「-abc の結合許可」解釈A, team-lead 裁定 2026-07-11): `e.short_combine` は
/// `inst_short` の grouping を素通りして `@builtins.short_combine` matcher の `combine` param にそのまま
/// 反映される (`short_group` の pair-key 化)。matcher レベルの意味論確認は builtins/matcher_residents_wbtest.mbt、
/// ここでは @engine.ElemDef → matcher の配線そのものを固定する。
test "short installer: e.short_combine rides through to the @builtins.short_combine matcher's combine param" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.flag_type(), short=['v'], short_combine=false),
    ],
  }
  let sc = ok_scope(def, [@builtins.short_installer()])
  match sc.greedy[0] {
    @engine.NativeMatch(matcher) => {
      assert_eq(test_run_matcher(matcher, ["-vv"]).length(), 0)
      assert_eq(test_run_matcher(matcher, ["-v"]).length(), 1)
    }
    _ => abort("expected @engine.NativeMatch")
  }
}

///|
/// 保証 (同上、grouping 側): 同じ `short_prefix` を共有しつつ `short_combine` が異なる 2 要素は
/// `short_group` の pair-key 化により別 matcher に分かれる (`short_group` の doc comment の
/// tie-break 回避理由そのもの — 混ぜたら combine の意味論が矛盾する)。
test "short installer: same short_prefix but DIFFERENT short_combine values get separate matchers" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("verbose", @builtins.flag_type(), short=['v'], short_combine=true),
      el("weird", @builtins.flag_type(), short=['w'], short_combine=false),
    ],
  }
  let sc = ok_scope(def, [@builtins.short_installer()])
  assert_eq(sc.greedy.length(), 2)
  let mut true_count = 0
  let mut false_count = 0
  for g in sc.greedy {
    match g {
      @engine.NativeMatch(matcher) => {
        let candidates = matcher.candidates()
        assert_eq(candidates.length(), 1)
        match candidates[0].spelling {
          "-v" => {
            true_count = true_count + 1
            assert_true(test_run_matcher(matcher, ["-vv"]).length() > 0)
          }
          "-w" => {
            false_count = false_count + 1
            assert_eq(test_run_matcher(matcher, ["-ww"]).length(), 0)
          }
          other => abort("unexpected short matcher candidate: " + other)
        }
      }
      _ => abort("expected @engine.NativeMatch")
    }
  }
  assert_eq(true_count, 1)
  assert_eq(false_count, 1)
}

///|
/// 保証 (同上、end-to-end): `short_combine:false` 下で `-ab` (2 flag の同時結合) は parse 失敗
/// (読みが 0 本、builtins/matcher_residents_wbtest.mbt の matcher レベル確認の end-to-end 版)。`-a -b` (別トークン)
/// は引き続き両方発火する — combine が禁じるのは「1 トークンでの複数 entry 結合」だけであって、
/// 各 entry 個別の発火能力そのものではない、という解釈Aの帰結を実行結果で固定する。
test "short installer end-to-end: short_combine:false rejects -ab but accepts -a -b (解釈A)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("a", @builtins.flag_type(), short=['a'], short_combine=false),
      el("b", @builtins.flag_type(), short=['b'], short_combine=false),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match @engine.parse_tree(@engine.ScopeNode(sc), ["-ab"], defs=Map([])) {
    @engine.Failure(_) => ()
    other =>
      fail(
        "expected @engine.Failure (2-flag cluster withheld by combine:false), got " +
        render_outcome(other),
      )
  }
  match @engine.parse_tree(@engine.ScopeNode(sc), ["-a", "-b"], defs=Map([])) {
    @engine.Success(bs) => {
      let mut a_found = false
      let mut b_found = false
      for bd in bs {
        if bd.key == "a" {
          a_found = true
        }
        if bd.key == "b" {
          b_found = true
        }
      }
      assert_true(a_found)
      assert_true(b_found)
    }
    other =>
      fail(
        "expected @engine.Success (2 separate tokens, no combine needed), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (DR-014「--name=value の許可」/ DESIGN §7.2 / DR-096 §1「config (long_eq_sep/long_prefix) から
/// 規則を構成」): `long_eq_sep: @engine.EsDeny` の要素は `inst_long` が eq-split entry を一切登録
/// しない — space-form の greedy @engine.Seq 衛星のみが残る (`@builtins.eq_split` matcher 自体、要素が唯一なので、
/// 生成されない)。既定 (`@engine.EsAllow`) の対極として既存 "value option gets 1 greedy @engine.Seq + 1 @builtins.eq_split"
/// テストと対で読む。
test "long installer: long_eq_sep:@engine.EsDeny withholds this element's eq-split entry (space form survives)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "port",
        @builtins.string_type(),
        long=LList([":set"]),
        long_eq_sep=@engine.EsDeny,
      ),
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  // @builtins.eq_split entry が無いので、この要素単独では @engine.NativeMatch(@builtins.eq_split) 自体が greedy に現れない
  // (eq_prefixes/eq_groups が空のまま — inst_long の "0 entries なら matcher を足さない" ガード)。
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    @engine.Seq([@engine.Exact("--port"), @builtins.string_arg("port", [])]),
  )
}

///|
/// 保証 (同上、eq form の実行時失敗側): `long_eq_sep: @engine.EsDeny` の要素へ `--port=80` を渡すと
/// eq-split の読みが存在しないため、`=` を含むトークンは丸ごと unrecognized になり parse は失敗する
/// (space form `--port 80` は引き続き成功する、対比として同テスト内で確認)。
test "long installer: long_eq_sep:@engine.EsDeny end-to-end — eq form fails, space form succeeds" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el(
        "port",
        @builtins.string_type(),
        long=LList([":set"]),
        long_eq_sep=@engine.EsDeny,
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match @engine.parse_tree(@engine.ScopeNode(sc), ["--port=80"], defs=Map([])) {
    @engine.Failure(_) => ()
    other =>
      fail(
        "expected @engine.Failure (no eq-split reading registered), got " +
        render_outcome(other),
      )
  }
  match
    @engine.parse_tree(@engine.ScopeNode(sc), ["--port", "80"], defs=Map([])) {
    @engine.Success(bs) => {
      let mut found = false
      for b in bs {
        if b.key == "port" {
          found = true
          assert_eq(b.value, @engine.VStr("80"))
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected @engine.Success (space form unaffected), got " +
        render_outcome(other),
      )
  }
}

// ── DR-092: inf の CLI→binding 経路が値を一切改変しないことの end-to-end 固定 ────

///|
/// 保証 (DR-092 実装調査 2026-07-11、fixtures/value-typing/number-inf-nan.json の
/// `inf-on-float-accepted` 対の完全版): `--t inf` (float 型) が args → matcher → `@builtins.parse_float` →
/// `@engine.Binding.value` の全経路を通っても `@engine.VNum` の inf がそのまま (saturate/丸めなど一切なく) 届く
/// ことを end-to-end で固定する。fixture 側は「operand の JSON 表現が未確定」を理由に `result`
/// pin を見送っている (main が本 DR 実装確定後に別段で追加) — この wbtest は fixture pin を待たず
/// production コードパスの値保持を先に固定する。
test "long installer end-to-end: --t inf reaches the binding as @engine.VNum(Infinity) unaltered (DR-092)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [el("t", @builtins.float_type(), long=LBool(true))],
  }
  let sc = ok_scope(def, all_installers())
  let inf : Double = 1.0 / 0.0
  match
    @engine.parse_tree(@engine.ScopeNode(sc), ["--t", "inf"], defs=Map([])) {
    @engine.Success(bs) => {
      let mut found = false
      for b in bs {
        if b.key == "t" {
          found = true
          assert_eq(b.value, @engine.VNum(inf))
        }
      }
      assert_true(found)
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
  // 負の無限大 + Infinity の case-insensitive 綴り (DR-074 §7) も同経路で確認。
  match
    @engine.parse_tree(
      @engine.ScopeNode(sc),
      ["--t", "-Infinity"],
      defs=Map([]),
    ) {
    @engine.Success(bs) => {
      let mut found = false
      for b in bs {
        if b.key == "t" {
          found = true
          assert_eq(b.value, @engine.VNum(-inf))
        }
      }
      assert_true(found)
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

// ── codex 節目レビュー Major 2: variant trigger も e.long_prefix を使う ─────────

///|
/// 保証 (codex 指摘 Major 2, 2026-07-11 team-lead 監査 OK): main entry (inst_long 冒頭の
/// `e.long_prefix + l`) と eq-split (`eq_group(..., e.long_prefix)`) は既に `e.long_prefix` を
/// 使うが、variant トリガだけ `"--" + v.trigger` に固定されていた — `long_prefix:"+"` の scope で
/// `long: [":set", "no:set:false"]` (DR-011 の `no:set:false` variant DSL、trigger は
/// `"no-" + name`) を持つ要素は、修正前は main entry `+ssl` と variant `--no-ssl` に**綴りが分裂**
/// していた (同一 option family なのに prefix が食い違う)。修正後は両方 `+` prefix で揃う。
test "long installer: a variant trigger uses e.long_prefix, matching the main entry (codex Major 2)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      {
        ..el(
          "ssl",
          @builtins.bool_type(),
          long=LList([":set", "no:set:false"]),
          long_prefix="+",
        ),
        default_values: Some([@engine.VBool(true)]),
      },
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  let mut has_plus_main = false
  let mut has_plus_variant = false
  let mut has_dash_variant = false
  for g in sc.greedy {
    match g {
      @engine.Seq([@engine.Exact("+ssl"), resident]) if is_resident(
          resident, "builtin/bool", "ssl",
        ) => has_plus_main = true
      @engine.Seq(
        [@engine.Exact("+no-ssl"), @engine.Bind("ssl", @engine.VBool(false))]
      ) => has_plus_variant = true
      @engine.Seq([@engine.Exact("--no-ssl"), ..]) => has_dash_variant = true
      _ => ()
    }
  }
  assert_true(has_plus_main)
  assert_true(has_plus_variant)
  assert_false(has_dash_variant) // 修正前のバグ挙動 (分裂した "--" 綴り) が残っていないことの否定確認
}

///|
/// 対極 (regression guard): 既定 `long_prefix:"--"` では main entry と variant が両方とも従来通り
/// `"--"` 綴りになる — 修正が既定値の断面 (byte 同一) を変えないことを固定する。
test "long installer: default long_prefix keeps variant trigger at \"--\" (対極, no regression)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      {
        ..el("ssl", @builtins.bool_type(), long=LList([":set", "no:set:false"])),
        default_values: Some([@engine.VBool(true)]),
      },
    ],
  }
  let sc = ok_scope(def, [@builtins.long_installer()])
  let mut has_main = false
  let mut has_variant = false
  for g in sc.greedy {
    match g {
      @engine.Seq([@engine.Exact("--ssl"), resident]) if is_resident(
          resident, "builtin/bool", "ssl",
        ) => has_main = true
      @engine.Seq(
        [@engine.Exact("--no-ssl"), @engine.Bind("ssl", @engine.VBool(false))]
      ) => has_variant = true
      _ => ()
    }
  }
  assert_true(has_main)
  assert_true(has_variant)
}

// ── constraint installer: required on a structural or (BOr) element (issue
// 2026-07-13-structural-or-type-branch-required-missing) ─────

///|
/// 保証: `required:true` の要素が `BOr` (structural or、型付き枝) のとき、`CRequired` の候補集合は
/// wrapper 自身の name (`level`) ではなく各枝の leaf name (`num`/`flag`) に展開される —
/// `inst_constraint` が以前は無条件で `CRequired(e.name)` (旧 1-tuple 相当) を積んでいたため、BOr
/// wrapper 自身に値が commit されることが無い (`ensure_entity_body` の BOr コメント: "no own
/// scalar/array value of its own") この構造では required 判定が恒常的に失敗していた
/// (`fixtures/constraints-parse/required-structural-or-branch.json` が end-to-end で pin する
/// 現象、本 wbtest は `inst_constraint` の候補集合構築そのものを直接固定する — fixture は parse
/// 結果しか見えず、この中間表現 (CRequired の 2nd field) は見えない)。
test "constraint installer: required on a BOr element expands candidates to each branch's leaf name" {
  let num_branch : @engine.OrBranch = {
    id: "num",
    items: [el("num", @builtins.int_type())],
  }
  let flag_branch : @engine.OrBranch = {
    id: "flag",
    items: [el("flag", @builtins.bool_type())],
  }
  let level : @engine.ElemDef = {
    ..el("level", @builtins.string_type()),
    required: true,
    body: BOr([num_branch, flag_branch]),
  }
  let def : @engine.Definition = { ..empty_def(), options: [level] }
  let sc = ok_scope(def, all_installers())
  let mut found : @engine.Constraint? = None
  for c in sc.constraints {
    match c {
      CRequired(_, _) => found = Some(c)
      _ => ()
    }
  }
  match found {
    Some(CRequired(display, cands)) => {
      assert_eq(display, "level") // error.element は宣言元の name のまま (DESIGN §9.1)
      assert_eq(cands.length(), 2)
      let names : Array[String] = []
      for c in cands {
        names.push(c.name)
        // 直書き BOr の leaf は親 scope に直接 bind される (wrapper なし、codex M-2 修正)。
        assert_eq(c.wrapper, None)
      }
      assert_true(names.contains("num"))
      assert_true(names.contains("flag"))
    }
    _ => fail("expected a CRequired constraint to be registered for 'level'")
  }
}

///|
/// 保証 (対極, self-written-rule-blind-spots の「新規追加時は既存の無変更ケースも確認する」線):
/// `required:true` の要素が通常の `BCell` (structural or ではない) のとき、候補集合は従来どおり
/// 要素自身の name 1 個だけ (`[e.name]`) — BOr 展開ロジックが非 BOr ケースを巻き込んで壊さないこと
/// を固定する。
test "constraint installer: required on a plain BCell element keeps a single-name candidate list" {
  let filename : @engine.ElemDef = {
    ..el("filename", @builtins.string_type()),
    required: true,
  }
  let def : @engine.Definition = { ..empty_def(), positionals: [filename] }
  let sc = ok_scope(def, all_installers())
  let mut found : @engine.Constraint? = None
  for c in sc.constraints {
    match c {
      CRequired(_, _) => found = Some(c)
      _ => ()
    }
  }
  match found {
    Some(CRequired(display, cands)) => {
      assert_eq(display, "filename")
      assert_eq(cands, [{ name: "filename", wrapper: None }])
    }
    _ => fail("expected a CRequired constraint to be registered for 'filename'")
  }
}

// ── length_range 非負整数 bound (DR-105 §5 明確化 note (a)、codex #3 反映) ───────

///|
/// 保証: `length_range` の bound は非負整数限定 — 負数は kind=invalid-argument (spec fixture 昇格済み:
/// fixtures/definition-error/length-range-negative-argument-invalid-argument.json — 本 wbtest は
/// それに先行する unit 層の pin として残す、regex_match compile 検査の wbtest/fixture 対と同じ運用)。
/// `in_range` の canonical number (負数許容) とは異なる `length_range` 固有規則であることの片側。
test "parse_definition: length_range with a negative min is @engine.DInvalidArgument (DR-105 §5 note (a))" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("tags", @builtins.string_type(), long=LBool(true), multiple=true, accum_filters=[
        "length_range:-1:5",
      ]),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (length_range min -1 is negative)")
    Err(errs) => {
      let mut has_invalid_argument = false
      for e in errs {
        if e.kind == @engine.DInvalidArgument && e.element == "tags" {
          has_invalid_argument = true
        }
      }
      assert_true(has_invalid_argument)
    }
  }
}

///|
/// 保証 (もう片側、上記の対): `length_range` の bound が小数 (`1.5`) の場合も同じ非負整数制約により
/// kind=invalid-argument (spec fixture 昇格済み: fixtures/definition-error/
/// length-range-non-integer-argument-invalid-argument.json)。
test "parse_definition: length_range with a non-integer min is @engine.DInvalidArgument (DR-105 §5 note (a))" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("tags", @builtins.string_type(), long=LBool(true), multiple=true, accum_filters=[
        "length_range:1.5:5",
      ]),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (length_range min 1.5 is not an integer)")
    Err(errs) => {
      let mut has_invalid_argument = false
      for e in errs {
        if e.kind == @engine.DInvalidArgument && e.element == "tags" {
          has_invalid_argument = true
        }
      }
      assert_true(has_invalid_argument)
    }
  }
}

///|
/// 保証 (対極、[[self-written-rule-blind-spots]]): `in_range` は length_range と異なり canonical
/// number (負数・小数) を引き続き受理し、`length_range` の非負整数 bound は正当に受理される —
/// 新設した非負整数 gate が既存の in_range 挙動を巻き込んで壊していないことを固定する。
test "parse_definition: in_range keeps canonical-number bounds, length_range accepts non-negative-int bounds (対極)" {
  let def : @engine.Definition = {
    ..empty_def(),
    options: [
      el("ratio", @builtins.number_type(), long=LBool(true), final_filters=[
        "in_range:-1.5:2.5",
      ]),
      el("tags", @builtins.string_type(), long=LBool(true), multiple=true, accum_filters=[
        "length_range:0:5",
      ]),
    ],
  }
  match @builtins.lower_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) => abort("expected Ok, got Err: " + errs.length().to_string())
  }
}

// ── issue 2026-07-15-pending-parseerror-path-asymmetry: global option 値 starve の
// missing_operand path 重複解消 (DR-066 §4「発火時の動的パス」) ──────────────────

///|
/// 保証 (統括裁定、実機実証済み): `global:true` の number option がサブコマンド内で値 starve
/// (`["a", "--level"]`、"--level" の後に値が無い) したとき、`missing_operand` の @engine.ParseError は
/// **`path=["a"]` の 1 件だけ** になる — DR-066 §4「発火時の動的パス」の規範通り、実際に
/// "--level" が読まれた scope (子 command "a" の中) を指す。
///
/// 背景 (audit-held-path-rooted-escape 調査の副次発見、2026-07-15): global option は宣言元
/// (root) の @engine.Entity に対する `@engine.Rooted(node, depth)` 衛星として子 scope へコピーされる
/// (DR-042 global link-sync)。この衛星が値 starve すると、CPS の継続チェーンが同じ starve を
/// 複数回 (root-copy 自身の読み取り + 早閉じ後の親 scope 再評価) 独立に @engine.Pending として観測し、
/// 旧実装は各観測が `@engine.Cand.path` (`link` による @engine.Rooted-escape 調整込み、`@engine.complete_tree` の
/// completer lookup 専用) をそのまま `@engine.ParseError.path` にコピーしていたため、`path=[]` (escape
/// で prepend がスキップされたまま) と `path=["a"]` (正しく prepend されたもの) の 2 件が
/// 併存していた (depth 2 の nested command では 3 件併存することも実証済み)。
///
/// 検証で判明した重要事実 (adversarial マトリクス、この wbtest 追加前に実施): 提案されていた
/// 修正案 A (KTop 変換で `c.link > 0` の候補を除外) は **前提が成立しない** — `nest_cands`
/// (eval.mbt) は @engine.CmdSat 境界を 1 回跨ぐごとに `link` を必ず 1 減算するため、`depth` 段の境界を
/// 全て通過した時点で `link` は必ず 0 になる。実機確認 (`c.link` を dump) で、KTop に届く
/// 全候補が既に `link=0` であることを確認済み — 「`link>0` を除外する」条件は何も除外しない
/// no-op であり、`path=[]` の誤った候補は `link=0` のまま生き残ってしまう。
///
/// 採用した修正 (案 B): `@engine.Cand` に `fire_path` (`@engine.Cand.fire_path` の doc comment 参照) を新設し、
/// `nest_cands` で `link` の値に関わらず無条件に prepend する (@engine.Held の `@engine.ParseError.path` と同じ
/// 「発火時 walk 位置」の意味論)。`missing_operand` への変換 (eval.mbt KTop) は `c.path` ではなく
/// `c.fire_path` を使う — 同じ starve を複数回観測した候補は全て同じ `fire_path` を持つため、
/// `push_error` の (element, args_pos, kind, reason, path) dedup が自然に 1 件へ収束する。
test "global option value-starve inside a child command: missing_operand converges to path=[\"a\"] only (issue 2026-07-15-pending-parseerror-path-asymmetry, DR-066 §4)" {
  let level_opt : @engine.ElemDef = el(
    "level",
    @builtins.number_type(),
    long=LList([":set"]),
    is_global=true,
  )
  let def : @engine.Definition = {
    ..empty_def(),
    options: [level_opt],
    commands: [
      { name: "a", body: empty_def(), export_key: @engine.export_key_unset() },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(
    @engine.ScopeNode(sc),
    ["a", "--level"],
    defs=Map([]),
  )
  match o {
    @engine.Failure(d) => {
      assert_eq(d.errors.length(), 1)
      let e = d.errors[0]
      assert_eq(e.element, "level")
      assert_eq(e.reason, "missing_operand")
      assert_eq(e.path, ["a"])
    }
    other =>
      fail(
        "expected @engine.Failure (value-starved global option), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (対極、[[self-written-rule-blind-spots]]): 非 global (command-local) option の値 starve
/// は元々この重複を持たなかった (issue 本文「(1) 発生源特定」— `@engine.Rooted` 衛星が無いため `link`
/// escape 機構自体が発火しない) — `fire_path` 導入がこの既存の正常経路を壊していないことの確認。
/// `path=["a"]` 1 件のみ、`level_opt` を global=false のまま子 command "a" 専用として宣言する。
test "command-local (non-global) option value-starve: missing_operand path=[\"a\"] unaffected by fire_path (対極, issue 2026-07-15-pending-parseerror-path-asymmetry)" {
  let level_opt : @engine.ElemDef = el(
    "level",
    @builtins.number_type(),
    long=LList([":set"]),
  )
  let child : @engine.Definition = { ..empty_def(), options: [level_opt] }
  let def : @engine.Definition = {
    ..empty_def(),
    commands: [
      { name: "a", body: child, export_key: @engine.export_key_unset() },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let o = @engine.parse_tree(
    @engine.ScopeNode(sc),
    ["a", "--level"],
    defs=Map([]),
  )
  match o {
    @engine.Failure(d) => {
      assert_eq(d.errors.length(), 1)
      let e = d.errors[0]
      assert_eq(e.element, "level")
      assert_eq(e.reason, "missing_operand")
      assert_eq(e.path, ["a"])
    }
    other =>
      fail(
        "expected @engine.Failure (value-starved command-local option), got " +
        render_outcome(other),
      )
  }
}

// ── front_door: export_key map 露出 (issue 2026-07-15-front-door-export-key-map-access) ──

///|
/// front_door 経由だけで (`wire_decode.mbt` の非 pub fn — `dec_definition`/`@builtins.build_export_map`
/// 呼び出しの生 `@engine.Definition` 二度 decode 等 — に一切触れず) export_key 適用済み result が
/// 組めることの固定 (MDR-005 追記)。発端は kuu-cli の MoonBit PoC (kawaz/kuu-cli
/// impl/mbt、2026-07-15) が front_door の `parse_definition`/`parse` で conformance と同形の
/// JSON 出力を組もうとしたが、result の export_key 適用に必要な ekmap (`@builtins.build_export_map` の
/// 結果) に到達できなかったこと — `AtomicAST` は MDR-005 §1 の不透明ハンドル原則
/// (フィールド非公開、利用者は中身を読まず `parse`/`complete` に渡すだけでよい) により生
/// `@engine.Definition` を保持せず、`@builtins.build_export_map`/`dec_definition` はどちらも `wire_decode.mbt`
/// 内部の非 pub fn だった。
///
/// 解決: `AtomicAST` に `ekmap` (definition から静的に決定される export_key 写像) を同梱し、
/// `pub fn export_map(ast) -> Map[String, @engine.ExportKey]` を正面玄関に追加した — 不透明ハンドルの
/// 原則を保ったまま (利用者は相変わらず `AtomicAST` の中身を読まない)、result 構築素材だけを
/// 追加の玄関関数で取り出せる形。`apply_export_keys` (resolve.mbt) は元々 `pub` — 変換処理
/// 自体は新設していない、ekmap への到達経路だけを追加した。
///
/// `port` (export_key: "alias" で結果キーを差し替え) と `verbose` (export_key 未指定、name
/// 由来のまま) を混在させ、`parse_definition → export_map → parse → apply_export_keys` の
/// 一気通貫で結果キーが `{alias, verbose}` になり `port` という素の cell 名では現れないことを
/// 確認する (DR-052 §1: export_key は結果キー軸だけを差し替え、パース/effects の entity 名は
/// 元の cell name のまま — 本テストは result 側だけを見る)。
test "front_door: parse_definition -> export_map -> apply_export_keys builds a renamed result without touching wire_decode internals (issue 2026-07-15-front-door-export-key-map-access)" {
  let json = @json.parse(
    (
      #|{"options": [
      #|  {"name": "port", "type": "number", "long": true, "export_key": "alias"},
      #|  {"name": "verbose", "type": "flag", "long": true}
      #|]}
    ),
  )
  let ast = match parse_definition(json) {
    Ok(a) => a
    Err(_) => fail("expected Ok(AtomicAST) for a well-formed definition")
  }
  let ekmap = export_map(ast)
  match parse(ast, ["--port", "80", "--verbose"]) {
    @engine.Success(binds) => {
      let mapped = apply_export_keys(binds, ekmap)
      let keys = mapped.map(fn(b) { b.key })
      assert_true(keys.contains("alias"))
      assert_true(keys.contains("verbose"))
      assert_false(keys.contains("port"))
    }
    other => fail("expected @engine.Success, got " + render_outcome(other))
  }
}

// ── moved whitebox coverage from the conformance runner ────────────────

///|
/// issue group-inner-bool-default-false-duplicate-top-level: `ensure_entity` (installer.mbt) の
/// 暗黙 default:false 注入は flag preset (`type:"flag"`、@builtins.flag_type()) 固有であり、plain bool
/// (`type:"bool"`、@builtins.bool_type()) は未発火なら他の値型と同様 absent (`@engine.Entity.default_values == None`,
/// DR-099 §2 の `?? absent` 終端)。`normalize_option` (installer.mbt) が @builtins.flag_type()→@builtins.bool_type() の書き換え
/// と同じ場所で default:false を前倒し確定させるため、`ensure_entity` 到達時点では両者とも
/// 同じ bool resident でも default_values が食い違うことを @engine.Entity レベルで直接
/// 検査する — `fixtures/value-typing/{or-leaf-factory-config,positional-group-factory-config}.json`
/// は同じ回帰を JSON result (or 枝内 / group 内側) の断面で pin しているが、本 test は
/// `@engine.Scope.entities` という別の断面 (内部表現) から同じ性質を固定する。
test "ensure_entity: plain @builtins.bool_type() は @engine.Entity.default_values=None (absent)、flag preset (@builtins.flag_type()→@builtins.bool_type()) は Some([false]) を維持する" {
  let src =
    #|{"options": [
    #|  {"name": "plain", "type": "bool", "long": true},
    #|  {"name": "flg", "type": "flag", "long": true}
    #|]}
  let defo = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("bad json fixture")
  }
  let def = dec_definition(defo)
  let scope = match
    @builtins.lower_definition(def, canonical_registry().installers()) {
    Ok(sc) => sc
    Err(errs) => abort("definition rejected: " + deferrs_str(errs))
  }
  let mut plain_found = false
  let mut flg_found = false
  for ent in scope.entities {
    if ent.name == "plain" {
      plain_found = true
      assert_eq(ent.default_values, None)
    }
    if ent.name == "flg" {
      flg_found = true
      assert_eq(ent.default_values, Some([@engine.VBool(false)]))
    }
  }
  if !plain_found {
    abort("entity 'plain' not found in scope.entities")
  }
  if !flg_found {
    abort("entity 'flg' not found in scope.entities")
  }
}
