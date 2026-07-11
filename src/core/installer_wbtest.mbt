// installer_wbtest.mbt — lowering の輪郭を最少ケースで固定する wbtest (MDR-002 §3 lowering 層)。
//
// フル conformance harness は task #5 で別途組み込む。ここは「installer 経路が
// UsefulAST を Scope 形に落とせているか」を構造的に確認する最小集合 (代表 installer 単体 + 合成 +
// 順列一致) のみ。テスト意図: 各 case の直前コメントで「何を保証 + 仕様根拠」を文章で残す
// (テスト = 動く仕様書; MDR-002 §3 の設計を後続セッションが読むだけで理解できるように)。

///|
/// 空の Definition (options / positionals / commands / aliases 全空)。個別 case は spread で必要 field
/// だけ差し替える。
fn empty_def() -> Definition {
  { options: [], positionals: [], commands: [], aliases: [] }
}

///|
/// ElemDef を「必要な軸だけ named param で差し替える」ビルダー。全 field を毎回書くと slice の
/// helpers_wbtest.mbt と同じ肥大化を招くため、ここでは lowering wbtest が触る軸だけ label に出す。
fn el(
  name : String,
  ty : Ty,
  // DR-071 §1 / kawaz 裁定 2026-07-08: `long` は wire 二形 (LongDecl) をそのまま受け取る — bool/array
  // の区別が installer 層の resolve_long (糖衣展開・DR-076 §2 flag 差し替え/補完) に必要なため、
  // Array[String] へ潰さない。既定は `LList([])` (= absent = 入口なし)。
  long? : LongDecl = LList([]),
  short? : Array[Char] = [],
  env? : Array[String] = [],
  is_dd? : Bool = false,
  dd_match? : String? = None,
  dd_self_keep? : Bool = false,
  is_global? : Bool = false,
  is_inherit? : Bool = false,
  repeat? : RepeatSpec? = None,
  multiple? : Bool = false,
  accumulator? : String? = None,
  collector? : String? = None,
  ref_? : String? = None,
  piece_filters? : Array[String] = [],
  value_filters? : Array[String] = [],
  cell_filters? : Array[String] = [],
  // DR-091 §3: long-only axis, `el`'s other builders (`opt`/`pos`, json_conformance_wbtest.mbt)
  // already carry these — added here so lowering wbtest cases can exercise `require_equal_separator`
  // without hand-writing a full ElemDef literal.
  long_prefix? : String = "--",
  require_equal_separator? : Bool = false,
) -> ElemDef {
  {
    name,
    ty,
    long,
    variants: [],
    short,
    env,
    is_dd,
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
    separator: None,
    collector,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    value_requires: [],
    deprecated: false,
    default_values: None,
    int_round: RError,
    allow_base_prefix: false,
    // `chain` (filters_wbtest.mbt, same package): keeps this builder's colon-shorthand ergonomics
    // (`piece_filters=["trim"]`) even though `ElemDef` fields are `Array[FilterSpelling]` in
    // production (issue filter-spelling-inband-encoding-retyping).
    piece_filters: chain(piece_filters),
    value_filters: chain(value_filters),
    cell_filters: chain(cell_filters),
    long_prefix,
    require_equal_separator,
    body: BCell,
  }
}

///|
/// canonical な installer chain (13 全部)。順列耐性テスト以外はこれを使う。
fn all_installers() -> Array[Installer] {
  [
    LongInst,
    ShortInst,
    EnvInst,
    DdInst,
    CommandInst,
    GlobalInst,
    InheritInst,
    RepeatInst,
    MultipleInst,
    ConfigInst,
    ConstraintInst,
    AliasInst,
    InheritableInst,
  ]
}

///|
/// Ok を expect して Scope を取り出すヘルパ (Err は panic テストで assert)。fixture 実食は task #5 の
/// harness で扱うため、この層は「lowering が Ok を返した Scope の構造」を細かく検査する。
fn ok_scope(def : Definition, order : Array[Installer]) -> Scope {
  match parse_definition(def, order) {
    Ok(sc) => sc
    Err(_) => abort("expected Ok(Scope), got Err")
  }
}

///|
fn entity_of(sc : Scope, name : String) -> Entity? {
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
/// value プリミティブを直後に置いた Seq)、(2) eq-split matcher 1 本を集約し (全 value 系 entry を集めて)、
/// (3) entity を name で 1 個 ensure する。仕様根拠 = DR-042 §展開の標準パターン (installer は entry 表を
/// matcher の構成 data として使う) + LOWERING §B.1 (long entry の 2 form: name-derived / 明示綴り)。
test "long installer: value option gets 1 greedy Seq satellite + 1 EqSplit matcher + 1 entity" {
  let def : Definition = {
    ..empty_def()
    // DR-071 §1: `:set` is the main-entry sentinel `normalize_option` expands to kebab(name) — the
    // pre-normalize form `el(...)` must use (DR-011 明確化 2026-07-08: a colon-less string like
    // "port" is itself a variant DSL syntax error now, not a pass-through literal spelling).
    ,
    options: [el("port", TStr, long=LList([":set"]))],
  }
  let sc = ok_scope(def, [LongInst])
  // 貢献: (1) Seq([Exact("--port"), StrArg("port")]) の satellite が 1 本、(2) NativeMatch(EqSplit(...))
  // 1 本、計 greedy = 2 本。TStr なので value_prim = StrArg。
  assert_eq(sc.greedy.length(), 2)
  assert_eq(sc.greedy[0], Seq([Exact("--port"), StrArg("port", [])]))
  match sc.greedy[1] {
    NativeMatch(EqSplit(prefix=p, entries=es)) => {
      assert_eq(p, "--")
      assert_eq(es.length(), 1)
      assert_eq(es[0].key, "port")
      assert_eq(es[0].name, "port")
    }
    _ => abort("expected NativeMatch(EqSplit)")
  }
  // entity は name=port で 1 個、TFlag ではないので default_values は None。inherit_ / env_key
  // / config_seat / accum は installer が触っていないので初期値のまま。
  assert_eq(sc.entities.length(), 1)
  let ent = entity_of(sc, "port").unwrap()
  assert_eq(ent.ty, TStr)
  assert_eq(ent.env_key, None)
  assert_eq(ent.accum, None)
  assert_eq(ent.default_values, None)
}

// ── flag (TFlag) の default:false preset + fail_action ─────────────────────────

///|
/// 保証: TFlag entity には LOWERING §A.5 / DR-051 §2 に従い default:false を preset する (未 fire でも
/// false に落ちる)。DR-076 §2 規則1 (flag の `long:true` 糖衣は `:set:true` — bool の `[":set"]` 糖衣を
/// 差し替え): `el("verbose", TFlag, long=LBool(true))` は wire `{"long": true}` そのものを模しており、
/// `normalize_option` (`resolve_long` 経由) がこれを解釈して `variants` を合成する — installer_wbtest
/// が JSON decode を経由せず規則1 を直接検証できる (kawaz 裁定 2026-07-08「installer_wbtest からも
/// 規則1/2 が検証可能になる」の実演)。値セルの型 TFlag→TBool 差し替えも同じ normalize_option の仕事。
/// flag の裸発火は合成された `:set:true` の Set variant が Variant entries loop 経由で Bind(name, true)
/// 衛星を生む。eq-split matcher には登録されない (この要素は main entry `:set` を持たない = 値パイプ
/// ライン自体が無い、古典 flag の糖衣 `long:true` → `[":set:true"]` のみのケース)。
test "long installer: a flag's `long:true` composes a `:set:true` variant → bare Bind(true) satellite (no EqSplit entry), default:false preset (DR-076 §2 規則1)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TFlag, long=LBool(true))],
  }
  let sc = ok_scope(def, [LongInst])
  // main entry 無し (long=[]) + Set variant 1 本 → eq-split entry は無い → greedy = Bind 衛星 1 本のみ。
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    Seq([Exact("--verbose"), Bind("verbose", VBool(true))]),
  )
  // normalize_option の TFlag→TBool 差し替えは値セルの型のみに効く。entity 自体は name=verbose のまま。
  let ent = entity_of(sc, "verbose").unwrap()
  assert_eq(ent.ty, TBool)
  // default:false preset (DR-051 §2), stored as the length-1-degenerate array (DR-083 §1)
  assert_eq(ent.default_values, Some([VBool(false)]))
}

///|
/// 保証: DR-076 §2 規則2 (flag の明示 variant リストは非空なら `:set:true` を冪等に補完 — 値形+裸の
/// 同居): `long=LList([":set"])` は wire `{"long": [":set"]}` を模す。main entry `:set` はそのまま
/// 残り (値スロット形、`--verbose <bool>`)、`:set:true` (裸発火) が合成されて共存する。
test "long installer: a flag's explicit `long:[\":set\"]` composes `:set:true` ALONGSIDE the value-slot main entry (DR-076 §2 規則2, 値形+裸の同居)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TFlag, long=LList([":set"]))],
  }
  let sc = ok_scope(def, [LongInst])
  // main entry 1 本 (値スロット, TFlag→TBool 差し替え後 BoolArg) + EqSplit matcher 1 本 + variant 1 本
  // (裸発火 Bind) → greedy = 3 本。
  assert_eq(sc.greedy.length(), 3)
  let mut has_value_slot = false
  let mut has_bare_bind = false
  for g in sc.greedy {
    match g {
      Seq([Exact("--verbose"), BoolArg("verbose", _)]) => has_value_slot = true
      Seq([Exact("--verbose"), Bind("verbose", VBool(true))]) =>
        has_bare_bind = true
      _ => ()
    }
  }
  assert_true(has_value_slot)
  assert_true(has_bare_bind)
}

// ── count (TCount) の default:0 preset + long 綴り合成 (DR-077 §3) ─────────────

///|
/// 保証: TCount entity には LOWERING §A.5 / DR-077 §3 に従い default:0 を preset する — flag の
/// default:false と対称。DR-077 §3 規則1 (count の `long:true` 糖衣は `:update:increment`):
/// `el("verbose", TCount, long=LBool(true))` は wire `{"long": true}` を模す。値セルの型 TCount→TNum
/// 差し替えは flag と違い `normalize_option` ではなく `ensure_entity` (Entity 構築) まで遅延する —
/// `TCount` タグは short/eq-split matcher (matcher.mbt) が「非消費・固定 increment」を判定するのに
/// installer chain 全体を通して必要だから (`normalize_option` のコメント参照、TBool は画一ルールで
/// 閉じるが TNum 全般には count 挙動を強制できない)。
test "long installer: a count's `long:true` composes an `:update:increment` variant → bare update-effect satellite (no EqSplit entry), default:0 preset (DR-077 §3 規則1)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TCount, long=LBool(true))],
  }
  let sc = ok_scope(def, [LongInst])
  // main entry 無し (long=[]) + Update variant 1 本 → eq-split entry は無い → greedy = EffMark 衛星 1 本のみ。
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    Seq([Exact("--verbose"), EffMark("verbose", Update("increment", []))]),
  )
  let ent = entity_of(sc, "verbose").unwrap()
  // ensure_entity が TCount→TNum の型差し替えを担う (normalize_option ではない)。
  assert_eq(ent.ty, TNum)
  // default:0 preset (DR-077 §3), stored as the length-1-degenerate array (DR-083 §1)
  assert_eq(ent.default_values, Some([VNum(0.0)]))
}

///|
/// 保証: DR-077 §3 規則2 (count の明示 variant リストは非空なら `:update:increment` を冪等に補完):
/// `long=LList([":update:increment"])` を明示しても二重に足されない。flag の規則2 (§1 の 2 番目の
/// test) と対称。
test "long installer: a count's explicit `long:[\":update:increment\"]` does not duplicate the composed variant (DR-077 §3 規則2, 冪等)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TCount, long=LList([":update:increment"]))],
  }
  let sc = ok_scope(def, [LongInst])
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    Seq([Exact("--verbose"), EffMark("verbose", Update("increment", []))]),
  )
}

///|
/// 保証: DR-071 §1 三態同義 — count の long 糖衣は absent (LBool(false)) でも入口なし。short だけの
/// count (`--` 側は書かない) が成立することを固定する。
test "long installer: a count with long:false has no long entry point (DR-071 §1 三態同義)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TCount, long=LBool(false), short=['v'])],
  }
  let sc = ok_scope(def, all_installers())
  for g in sc.greedy {
    match g {
      Seq([Exact("--verbose"), ..]) => fail("expected no --verbose long entry")
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
  let def : Definition = {
    ..empty_def(),
    options: [el("host", TStr, long=LList([":set"]), env=["HOST"])],
  }
  let sc = ok_scope(def, all_installers())
  let ent = entity_of(sc, "host").unwrap()
  assert_eq(ent.env_key, Some("HOST"))
}

// ── repeat (DR-043): flatten accumulator + Ref 再帰 ───────────────────────────

///|
/// 保証: unbounded repeat (max=None) は positional に (min-1 mandatory heads + Ref(name)) を積み、
/// entity には flatten accumulator を宣言する (DR-036 名前付き accumulator registry)。DR-044 §1
/// (kawaz 裁定): repeat / multiple / separator は cardinality 不問で常に配列 — なので min:1 でも
/// `repeat:{min:0,max:1}` (optional 糖衣) でも accumulator は必ず立つ。
test "repeat installer: unbounded repeat installs 'flatten' accum + Ref-recursion on positional spine" {
  let def : Definition = {
    ..empty_def(),
    positionals: [
      el("src", TStr, repeat=Some({ min: 1, max: None, lazy_: false })),
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
  assert_eq(ent.accum, Some("flatten")) // DR-043 flatten
}

///|
/// 保証: unbounded min:0 は `Ref` (0 でもよいを表現できない) ではなく `Many(head, lazy_)` に落ち、
/// `lazy_` は宣言の `repeat.lazy` がそのまま `Many` の 2nd field に渡る (issue 2026-07-08
/// min0-lazy-repeat-gap 根治: `BoundedTail`'s 3rd field と同じ座席を min:0 UNBOUNDED 側にも用意)。
test "repeat installer: min:0 unbounded repeat lowers to Many(head, lazy_) carrying the lazy spec" {
  let def : Definition = {
    ..empty_def(),
    positionals: [
      el("xs", TStr, repeat=Some({ min: 0, max: None, lazy_: true })),
    ],
  }
  let sc = ok_scope(def, all_installers())
  assert_eq(sc.positional.length(), 1)
  assert_eq(sc.positional[0], Many(StrArg("xs", []), true))
  let ent = entity_of(sc, "xs").unwrap()
  assert_eq(ent.accum, Some("flatten")) // DR-044 §1: cardinality 不問で常に配列
}

// ── bounded repeat (LOWERING §B.8): min heads + BoundedTail、Ref 再帰なし ─────

///|
/// 保証: bounded (max 有限) は Ref 再帰を作らず BoundedTail(head, max-min, lazy_) に落ちる。取り分選好
/// (greedy default / lazy) は BoundedTail の 3 番目 field で保持され、unbounded 版 (Ref tail) と同じく
/// 先食い/取り分選好が効く (LOWERING §B.8: 「bounded repeats compose like unbounded ones」)。
test "repeat installer: bounded max lowers to min heads + BoundedTail (no Ref)" {
  let def : Definition = {
    ..empty_def(),
    positionals: [
      el("f", TStr, repeat=Some({ min: 1, max: Some(3), lazy_: false })),
    ],
  }
  let sc = ok_scope(def, all_installers())
  // 1 mandatory head + BoundedTail(head, 2, false) — budget = 3-1
  assert_eq(sc.positional.length(), 2)
  assert_eq(sc.positional[0], StrArg("f", []))
  assert_eq(sc.positional[1], BoundedTail(StrArg("f", []), 2, false))
  // Ref template は登録されない (Ref 再帰なし)
  let ent = entity_of(sc, "f").unwrap()
  assert_eq(ent.accum, Some("flatten"))
}

// ── multiple の collector 属性 (DR-036, issue 2026-07-09-dec-multiple-collector-decode) ─────

///|
/// 保証: `multiple:true` + collector 宣言 (ElemDef) は accum cell の Entity へそのまま写る
/// (`ensure_entity` の write-through、installer.mbt) — collector 自体を解釈・変換する installer は
/// 無く、宣言をそのまま Entity.collector に通す (DR-036 の decode/実体 lookup の「実体」側)。
test "multiple installer: a declared collector rides straight through to Entity.collector" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "tags",
        TStr,
        long=LList([":set"]),
        multiple=true,
        collector=Some("unwrap_single"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  let ent = entity_of(sc, "tags").unwrap()
  assert_eq(ent.accum, Some("append")) // DR-034: multiple の値 fold は append
  assert_eq(ent.collector, Some("unwrap_single"))
}

///|
/// 保証: collector は accum cell の伴属物 (node.mbt Entity.collector の doc comment) — multiple も
/// repeat も無いスカラーセルに collector だけ宣言しても `ensure_entity` は捨てる (accum が None なら
/// collector も強制 None、「累積すら起きないセルの collector」という無意味な組合せを AST に残さない)。
/// 実運用の decode 層 (dec_multiple, json_conformance_wbtest.mbt) は collector を multiple:{...} の
/// 内側キーとしてのみ受理するので、この経路 (multiple:false かつ collector 宣言) は decode からは
/// 到達しない — installer 層の防御的な契約として単体で固定する。
test "multiple installer: a collector declared without multiple/repeat is dropped (accum is None)" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el("n", TNum, long=LList([":set"]), collector=Some("unwrap_single")),
    ],
  }
  let sc = ok_scope(def, all_installers())
  let ent = entity_of(sc, "n").unwrap()
  assert_eq(ent.accum, None)
  assert_eq(ent.collector, None)
}

// ── dd installer (DR-064): 配置不問回収 (options[] / positionals[] 両対応) ──────

///|
/// 保証: dd (`type:"dd"`) は options[] と positionals[] のどちらに宣言しても回収され、DdSat 衛星が
/// greedy に 1 本入る (add-if-absent が重複を collapse)。ensure_entities は dd に entity を作らない
/// (LOWERING §B.4「値なし」)。DR-064 §2「dd は配置不問で lowered 形が同一」の仕様準拠テスト。
test "dd installer: options[] placement lowers to same DdSat with no entity (DR-064 §2)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("--", TStr, is_dd=true)],
  }
  let sc = ok_scope(def, all_installers())
  // DdSat("--") が greedy に 1 本、entity は 0 個 (dd は値なし)
  let mut has_dd = false
  for g in sc.greedy {
    if g == DdSat("--") {
      has_dd = true
    }
  }
  assert_true(has_dd)
  assert_eq(sc.entities.length(), 0)
}

// ── global installer + fixpoint: 子孫 scope へ link COPY 伝播 ─────────────────

///|
/// 保証: global option は fixpoint 中に子 scope の宣言層にコピーされ、long installer が子でも展開する
/// (link_depth=1 の Rooted 衛星に wrap)。子 scope 側 entity は生成しない (link_depth > 0 なら
/// ensure_entities がスキップ — DR-070 §1b gap 5)。1 pass では global copy の後の long 展開が
/// 子で行われないが、fixpoint (chain repeat) がそれを吸収する — order-independent の実証。
test "global + long + fixpoint: child scope receives Rooted satellite (link_depth=1) and no own entity" {
  let child : Definition = { ..empty_def() }
  let def : Definition = {
    ..empty_def()
    // DR-076 §2 規則1: `long=LBool(true)` (wire `{"long": true}`) は normalize_option が resolve_long
    // で `variants` へ `:set:true` を合成する — 上の "a flag's `long:true` composes..." テスト参照。
    ,
    options: [el("verbose", TFlag, long=LBool(true), is_global=true)],
    commands: [{ name: "sub", body: child, export_key: EkUnset }],
  }
  let sc = ok_scope(def, all_installers())
  // 子 scope (CmdSat("sub", child_scope)) を取り出す
  let mut child_sc : Scope? = None
  for g in sc.greedy {
    match g {
      CmdSat(n, cs) => if n == "sub" { child_sc = Some(cs) }
      _ => ()
    }
  }
  let child_sc = child_sc.unwrap()
  // 子 scope 側 greedy に Rooted(Seq([Exact("--verbose"), Bind(...)]), 1) が入る
  let mut found = false
  for g in child_sc.greedy {
    match g {
      Rooted(_, depth) => if depth == 1 { found = true }
      _ => ()
    }
  }
  assert_true(found)
  // 子 scope に verbose entity は無い (link 同期で root cell に landing)
  assert_eq(entity_of(child_sc, "verbose"), None)
  // root には verbose entity + default:false preset がある (DR-083 §1: 長さ 1 縮退配列)
  let root_ent = entity_of(sc, "verbose").unwrap()
  assert_eq(root_ent.default_values, Some([VBool(false)]))
}

// ── 順列耐性 (5 invariants + fixpoint): 順序が違っても同じ Scope に収束 ─────────

///|
/// 保証: 5 invariants + fixpoint により、chain の順序を変えても同じ Scope が組み上がる (DR-042 §invariants)。
/// long→env vs env→long で env seat が正しく立つか (env → ensure_entities → seat_env が同 pass に走るか
/// を fixpoint が救うか) を、chain の順序 2 種で確認する。
test "installer chain: order-independent thanks to 5 invariants + fixpoint" {
  let def : Definition = {
    ..empty_def(),
    options: [el("host", TStr, long=LList([":set"]), env=["HOST"])],
  }
  let sc1 = ok_scope(def, [LongInst, EnvInst])
  let sc2 = ok_scope(def, [EnvInst, LongInst])
  // 両順で env seat / greedy 内容が一致
  assert_eq(entity_of(sc1, "host").unwrap().env_key, Some("HOST"))
  assert_eq(entity_of(sc2, "host").unwrap().env_key, Some("HOST"))
  assert_eq(sc1.greedy.length(), sc2.greedy.length())
  assert_eq(sc1.entities, sc2.entities)
}

// ── def-error 列挙 (DR-054 §4): 全 kind を 1 pass で収集 (打ち切りなし) ─────────

///|
/// 保証: parse_definition の static check は全 kind を走らせて 1 list に append し、first-error 打ち切り
/// しない (DR-054 §4 「コンパイラの定石」)。ここでは (a) unknown vocab (chain に long installer が無い、
/// long 属性を持つ要素あり) と (b) invalid range (repeat min>max) を同時に混ぜ、両方の DefError が
/// enumerate されることを確認する。
test "parse_definition enumerates all def-errors (no first-error 打ち切り, DR-054 §4)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("v", TFlag, long=LList(["v"]))], // long 属性あり
    positionals: [
      el("f", TStr, repeat=Some({ min: 3, max: Some(1), lazy_: false })),
    ], // min > max
  }
  // chain には LongInst / RepeatInst 共に無い → long vocab は unknown、repeat vocab も unknown、
  // かつ min>max の invalid range も同時に。3 種の DefError が列挙されるはず。
  match parse_definition(def, [ShortInst]) {
    Ok(_) => abort("expected Err")
    Err(errs) => {
      // 少なくとも DUnknownVocab (long / repeat) と DInvalidRange の 3 種を含む — 打ち切っていれば
      // 最初の 1 種で止まっていたはず。
      let mut has_unknown = false
      let mut has_range = false
      for e in errs {
        if e.kind == DUnknownVocab {
          has_unknown = true
        }
        if e.kind == DInvalidRange {
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
/// `DAbsentRef` を definition-error として列挙する。ランタイム側の `check_elem_absent_ref`
/// (installer.mbt) は本 issue 以前から実装済みだったが、decode 層 (`ref` キー) が無かったため
/// この分岐は未踏だった — decode 配線後の疎通確認として、registry を意図的に空のまま
/// (`Map::new()`) `parse_definition` へ渡し、absent-ref が正しく検出されることを固定する。
test "parse_definition: a ref target absent from registry is DAbsentRef (DR-078 §1 / DR-054)" {
  let def : Definition = {
    ..empty_def(),
    positionals: [
      el(
        "hlcolors",
        TStr,
        ref_=Some("color"),
        repeat=Some({ min: 1, max: None, lazy_: false }),
      ),
    ],
  }
  // "color" は scope 内の兄弟要素にも registry (definitions.templates 相当の事前登録) にも無い
  // (registry 未指定 = 既定の空 map)。
  match parse_definition(def, [RepeatInst]) {
    Ok(_) => abort("expected Err (absent ref target 'color')")
    Err(errs) => {
      let mut has_absent_ref = false
      for e in errs {
        if e.kind == DAbsentRef {
          has_absent_ref = true
        }
      }
      assert_true(has_absent_ref)
    }
  }
}

///|
/// 保証 (codex 節目レビュー指摘4、issue 2026-07-09-ref-template-result-shape): an option's `ref` +
/// `repeat` lowering (`inst_long`) wires a SINGLE `GreedyRepeat` spine slot — correct for
/// `min <= 1`, but a `min > 1` spec would silently fold the extra mandatory-head reps into that
/// same single slot, losing 先食い suppression / 取り分選好 for them while still parsing
/// "successfully" (a mis-shaped-but-quiet result, the exact failure mode
/// [[retreat-is-last-resort]]/契約 が禁じる). `parse_definition` must reject this at definition
/// time (`DInvalidRange`, mirrors the sibling positional `min > max` check just above) rather than
/// let it run mis-wired. Registry left empty (color 未登録) — `DAbsentRef` co-occurs, but this
/// test only asserts `DInvalidRange` is ALSO enumerated (DR-054 §4 no first-error 打ち切り)。
/// spec fixture 昇格済み (DR-082、fixtures/definition-error/option-ref-repeat-min-invalid-range.json)
/// — 本 wbtest はそれに先行する unit 層の pin として残す。
test "parse_definition: an option's ref+repeat with min > 1 is DInvalidRange (codex review #4)" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "hlcolors",
        TStr,
        long=LList([":set"]),
        ref_=Some("color"),
        repeat=Some({ min: 2, max: None, lazy_: false }),
      ),
    ],
  }
  match parse_definition(def, [LongInst, RepeatInst]) {
    Ok(_) => abort("expected Err (unsupported option ref+repeat min>1)")
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == DInvalidRange && e.element == "hlcolors" {
          has_range = true
        }
      }
      assert_true(has_range)
    }
  }
}

///|
/// 保証 (対極、codex 指摘4 の境界): `min <= 1` (mandatory-head unroll 無し、`GreedyRepeat` が単一
/// spine slot で足りる形) は REJECT されない — 上のテストが「壊れた形を通す」ことへの反例なら、
/// このテストは「正しく対応済みの形を誤って落とさない」ことへの反例 ([[self-written-rule-blind-spots]]
/// の対極確認)。`last-wins-repeat-rows.json` が固定する実際の形そのもの ({"min":1})。
test "parse_definition: an option's ref+repeat with min <= 1 is NOT rejected (codex review #4 対極)" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "hlcolors",
        TStr,
        long=LList([":set"]),
        ref_=Some("color"),
        repeat=Some({ min: 1, max: None, lazy_: false }),
      ),
    ],
  }
  match parse_definition(def, [LongInst, RepeatInst]) {
    Ok(_) =>
      abort(
        "expected Err (absent ref target 'color', registry left empty on purpose)",
      )
    Err(errs) =>
      for e in errs {
        if e.kind == DInvalidRange {
          abort(
            "min:1 must not raise DInvalidRange (only min>1 is unsupported)",
          )
        }
      }
  }
}

///|
/// 保証 (issue 2026-07-09-accum-fold-update-default-ops、team-lead 裁定 2026-07-10 最終版): a
/// `multiple` element carrying an `update` variant (`:update:<transform>`, DR-077 §1) is
/// DInvalidRange — `collect_unsupported_option_ref_repeat` (上記) と同型の「構造的に宣言できるが
/// 実装が対応できない組合せを definition-error で落とす」契約の3例目。DR-077 の `update` semantics
/// は `cell = f(old)` で `old` はセルの現在値だが、accum セルではその値が累積状態 (T[]) であり、
/// filters registry の transform は全て T=>T (scalar、`filters.mbt`'s `FilterSignature`、DR-077 §2
/// 「使えるのは transform シグネチャ T=>T の filter のみ」) — 構造的に型が噴合し、legal な解決が今の
/// registry には存在しない。これを ACCUMULATE fold の実行時に検出するのではなく、DR-077 §2 が既に
/// 「未登録の transform 名」「validate-only signature」を definition-error で閉じている
/// (`classify_long_spelling` の `LInvalid` 経路、両方とも `DUnknownVocab`) のと同じ層で静的に閉じる
/// (この3つ目は multiple 宣言との組合せなので `classify_long_spelling` の DSL-parse 単体では判定でき
/// ず、`normalize_surface` が variants を確定させた後の別 pass になる)。
///
/// spec fixture 昇格済み (DR-082、fixtures/definition-error/accum-update-invalid-range.json) —
/// 本 wbtest はそれに先行する unit 層の pin として残す。
test "parse_definition: an update variant on a multiple element is DInvalidRange (accum-fold-update-default-ops)" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "tags",
        TStr,
        long=LList([":set", "bump:update:increment"]),
        multiple=true,
      ),
    ],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (update variant on a multiple element is unsupported)",
      )
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == DInvalidRange && e.element == "tags" {
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
  let def : Definition = {
    ..empty_def(),
    options: [
      el("verbosity", TNum, long=LList([":set", "bump:update:increment"])),
    ],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == DInvalidRange {
          abort(
            "a scalar (non-multiple) element with an update variant must not raise DInvalidRange",
          )
        }
      }
  }
}

///|
/// 保証 (codex レビュー High 1、2026-07-10): alias の `long_override` (DR-057 §3 差分上書き) 経由の
/// `:update:<transform>` も、canonical 要素本体の `variants` (上の2テストが固定する経路) と同じく
/// DInvalidRange で REJECT される — `collect_unsupported_accum_update` が canonical 側の variants
/// しか見ないと、alias 経由の update variant が検査をすり抜けて `parse_definition` を通過し、発火時
/// に canonical (multiple 要素) への Update binding が resolve.mbt の accum 分岐に届いて abort に
/// 到達してしまう (修正前の実際の repro)。canonical `tags` (multiple:true) は自身は update variant
/// を持たず、alias `t` の long_override だけが `bump:update:increment` を持つ形で、alias 経由の
/// 検査が独立して機能することを固定する。
test "parse_definition: an alias's long_override update variant on a multiple canonical is DInvalidRange (codex High 1)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("tags", TStr, long=LList([":set"]), multiple=true)],
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
  match parse_definition(def, all_installers()) {
    Ok(_) =>
      abort(
        "expected Err (alias long_override update variant on a multiple canonical is unsupported)",
      )
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == DInvalidRange && e.element == "tags" {
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
  let def : Definition = {
    ..empty_def(),
    options: [el("verbosity", TNum, long=LList([":set"]))],
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
  match parse_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == DInvalidRange {
          abort(
            "an alias update variant on a scalar (non-multiple) canonical must not raise DInvalidRange",
          )
        }
      }
  }
}

///|
/// 保証 (codex レビュー High 2、2026-07-10): TCount の **short** 発火は variant を一切経由せず
/// `matcher.mbt`'s `walk_short` が直接 `mk_eff(e.name, Update("increment", []), Cli)` を生成する
/// (`count_increment_variant` の `long:true` 糖衣経路とは別の生成源) — `collect_unsupported_accum_
/// update` の variant 走査ではこの経路が最初から見えないため、TCount×multiple という組合せ自体を
/// 要素レベルで閉じる (`collect_unsupported_count_multiple`)。修正前の実際の repro:
/// `{"name":"n","type":"count","short":["n"],"multiple":true}` は `parse_definition` を通過し、
/// argv `["-n"]` の発火で resolve.mbt の accum 分岐の abort に到達していた。
/// spec fixture 昇格済み (DR-082、fixtures/definition-error/count-multiple-invalid-range.json) —
/// 本 wbtest はそれに先行する unit 層の pin として残す。
test "parse_definition: a count element with multiple is DInvalidRange (codex High 2, short-fired repro)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("n", TCount, short=['n'], multiple=true)],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (count element with multiple is unsupported)")
    Err(errs) => {
      let mut has_range = false
      for e in errs {
        if e.kind == DInvalidRange && e.element == "n" {
          has_range = true
        }
      }
      assert_true(has_range)
    }
  }
}

///|
/// 保証 (対極、上のテストの境界): TCount 要素が multiple を持たなければ REJECT されない — count の
/// 通常用法 (`-vvv` の verbosity 加算等、multiple 無し) を誤って落とさないことを固定する。
test "parse_definition: a count element without multiple is NOT rejected (対極)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbosity", TCount, short=['v'])],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == DInvalidRange {
          abort("a count element without multiple must not raise DInvalidRange")
        }
      }
  }
}

// ── long DSL 分類 (DR-011 / DR-071 / DR-076): classify_long_spelling 輪郭 ───────

///|
/// `classify_long_spelling` is the SOLE interpreter of the colon DSL (DR-011/071/076), shared by
/// the JSON-fixture decoder (`dec_variant`) and `desugar_aliases`'s alias `long_override` (issue
/// 2026-07-08: aliases used to skip this classification entirely, misreading `":set:true"` as a
/// literal `"--:set:true"` spelling). This pins all 4 classification outcomes on representative
/// spellings, keyed on `own_name` (the caller's own resolved name — canonical OR alias, DR-057 §3).
test "classify_long_spelling: the 4 outcomes on representative spellings" {
  // (1) LMain: the bare `:set` sentinel resolves to `own_name` verbatim, no operand.
  match classify_long_spelling(":set", "ssl", TBool) {
    LMain(n) => assert_eq(n, "ssl")
    _ => fail("expected LMain")
  }
  // (2) LVariant with an EMPTY prefix (`:set:true`, DR-076 §4): the element's own bare-degenerate
  // main entry — trigger is `own_name` verbatim (NOT "-"+own_name — that would be a bogus extra
  // spelling installer.mbt never intended, since it always does `"--" + v.trigger`).
  match classify_long_spelling(":set:true", "ssl", TBool) {
    LVariant({ trigger, op, operand }) => {
      assert_eq(trigger, "ssl")
      assert_eq(op, Set)
      assert_eq(operand, Some(VBool(true)))
    }
    _ => fail("expected LVariant")
  }
  // (3) LVariant with a NON-empty prefix (`no:set:false`, DR-011): a separately-triggered named
  // variant — trigger is `prefix + "-" + own_name`.
  match classify_long_spelling("no:set:false", "ssl", TBool) {
    LVariant({ trigger, op, operand }) => {
      assert_eq(trigger, "no-ssl")
      assert_eq(op, Set)
      assert_eq(operand, Some(VBool(false)))
    }
    _ => fail("expected LVariant")
  }
  // (4) LInvalid: no colon at all — DR-011 明確化 (kawaz 裁定 2026-07-08): a colon-less string is a
  // variant DSL syntax error, NOT a literal-spelling fallback. An explicit non-name-derived spelling
  // (e.g. an alias's "gzip") belongs to a DR-057 alias element, not to `long`'s DSL.
  match classify_long_spelling("gzip", "compress", TStr) {
    LInvalid(s) => assert_eq(s, "gzip")
    _ => fail("expected LInvalid")
  }
  // a non-bool variant operand parses per the element's OWN type (DR-074/075 canonical lexicons) —
  // not just bool. `default:5` on a TNum element parses the operand as a number.
  match classify_long_spelling("default:default:5", "port", TNum) {
    LVariant({ trigger, op, operand }) => {
      assert_eq(trigger, "default-port")
      assert_eq(op, Default)
      assert_eq(operand, Some(VNum(5.0)))
    }
    _ => fail("expected LVariant")
  }
  // (5) LInvalid: an unrecognized effect word (colon present, but not set/unset/empty/default) is
  // ALSO a syntax error (DR-011 明確化) — not a literal-spelling fallback either.
  match classify_long_spelling("no:bogus:false", "ssl", TBool) {
    LInvalid(s) => assert_eq(s, "no:bogus:false")
    _ => fail("expected LInvalid (unrecognized op word)")
  }
}

///|
/// DR-011 明確化 (kawaz 裁定 2026-07-08): `parse_definition` surfaces a colon-less `long` spelling as
/// a DR-054 `unknown-vocab` definition-error (not a silently-accepted literal trigger).
test "parse_definition: a colon-less long spelling is a DR-054 unknown-vocab definition-error" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TFlag, long=LList(["verbose"]))],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) =>
      fail(
        "expected Err (colon-less long spelling 'verbose' is a syntax error)",
      )
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == DUnknownVocab && e.element == "verbose" {
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
  let def : Definition = {
    ..empty_def(),
    options: [el("ssl", TBool, long=LList(["no:bogus:false"]))],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) =>
      fail("expected Err (unrecognized effect word 'bogus' is a syntax error)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == DUnknownVocab && e.element == "ssl" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// DR-011 明確化 (kawaz 裁定 2026-07-08): alias `long_override` (DR-057 §3 差分上書き) is the SAME
/// colon DSL canonical `long` uses (`classify_long_spelling` shared, installer.mbt comment "二経路が
/// drift しないよう分類器を共用") — the 明確化 applies wherever the DSL appears, not just canonical
/// `long`. A colon-less `long_override` spelling must be an `unknown-vocab` definition-error too,
/// caught by `collect_invalid_alias_long_override` BEFORE `desugar_aliases` ever runs (so the invalid
/// spelling never silently becomes a literal trigger through the alias path either).
test "parse_definition: a colon-less alias long_override spelling is a DR-054 unknown-vocab definition-error" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TFlag, long=LBool(true))],
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
  match parse_definition(def, all_installers()) {
    Ok(_) =>
      fail(
        "expected Err (colon-less alias long_override spelling 'chatty' is a syntax error)",
      )
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == DUnknownVocab && e.element == "chatty" {
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
/// (Bind("verbose", true)) を生む — desugar_aliases が canonical の「元の型」(normalize_surface で
/// TBool 化される前の TFlag) を保持した複製 (`orig`) から引き、alias 名・その元の型で resolve_long
/// を通すことで実現する。
test "desugar_aliases: alias long:true on a flag canonical composes :set:true (bare fire), not a value-slot main entry (DR-076 §2 規則1)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TFlag)],
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
  // alias 側の trigger --v は Bind (裸発火) 衛星 1 本のみ — EqSplit (値スロット形) には登録されない。
  let mut has_bare_bind = false
  let mut has_value_slot = false
  for g in sc.greedy {
    match g {
      Seq([Exact("--v"), Bind("verbose", VBool(true))]) => has_bare_bind = true
      Seq([Exact("--v"), BoolArg("verbose", _)]) => has_value_slot = true
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
  let def : Definition = {
    ..empty_def(),
    options: [el("host", TStr)],
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
      Seq([Exact("--h"), StrArg("host", _)]) => has_value_slot = true
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
/// そのため `materialize` 後の `Scope` 構造 (sub 自身の greedy 面に積まれた `Rooted` 衛星の本数) を
/// 直接検査する — sub 自身が両トリガの link 衛星を持つことが、porous に頼らない正しい伝播の証拠。
test "copy_global_into: two same-name different-trigger globals (declared independently at root and mid) both propagate to a grandchild scope" {
  let def : Definition = {
    ..empty_def(),
    options: [{ ..el("x", TBool), long: LList([":set:true"]), is_global: true }],
    commands: [
      {
        name: "mid",
        body: {
          ..empty_def(),
          options: [
            { ..el("x", TBool), long: LList(["no:set:false"]), is_global: true },
          ],
          commands: [{ name: "sub", body: empty_def(), export_key: EkUnset }],
        },
        export_key: EkUnset,
      },
    ],
  }
  let sc = ok_scope(def, all_installers())
  let mut mid_sc : Scope? = None
  for g in sc.greedy {
    match g {
      CmdSat(n, cs) => if n == "mid" { mid_sc = Some(cs) }
      _ => ()
    }
  }
  let mid_sc = mid_sc.unwrap()
  let mut sub_sc : Scope? = None
  for g in mid_sc.greedy {
    match g {
      CmdSat(n, cs) => if n == "sub" { sub_sc = Some(cs) }
      _ => ()
    }
  }
  let sub_sc = sub_sc.unwrap()
  // sub 自身の greedy 面に、root 由来 (:set:true) と mid 由来 (no:set:false) 両方の Rooted 衛星が
  // 積まれているはず — 1 本しか無ければ、後続コピーがトリガ違いにも関わらず誤って抑止された regression。
  let mut rooted_count = 0
  for g in sub_sc.greedy {
    match g {
      Rooted(_, _) => rooted_count = rooted_count + 1
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
/// 見落とし、`--sub-ttl` の入口が重複してしまう (root の greedy 面に同一 Exact トリガの衛星が 2 本
/// 立つ)。`all_long_triggers` (long + variants 横断) で判定すれば、既存の alias トリガを検出して
/// inheritable コピーが正しく shadow (抑止) される。
test "add_inheritable_copy: an alias-provided (variants-side) trigger shadows the inheritable reverse-copy" {
  let def : Definition = {
    ..empty_def(),
    options: [el("other", TFlag)],
    commands: [
      {
        name: "sub",
        body: {
          ..empty_def(),
          options: [
            {
              ..el("ttl", TNum),
              is_inheritable: true,
              default_values: Some([VNum(60.0)]),
            },
          ],
        },
        export_key: EkUnset,
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
      Seq([Exact("--sub-ttl"), ..]) => count = count + 1
      _ => ()
    }
  }
  // shadow が正しく効けば alias 由来の 1 本のみ (inheritable コピーは重複追加されない)。
  assert_eq(count, 1)
}

// ── DR-077: update 効果 + count (definition-error 系、installer 層) ──────────────

///|
/// 保証 (codex 指摘 2、DR-077 §2 「不在 → unknown-vocab」): `classify_long_spelling` は
/// `:update:<name>` の `<name>` を filters registry へ実際に `lookup_filter` する (旧実装は
/// `parts[2] == "increment"` のハードコード allowlist だった — 節目レビューで指摘され registry
/// lookup ベースへ置換)。registry に存在しない名前 (`bogus`) は `None` の分岐で `LInvalid` へ倒し
/// (installer.mbt コメント参照)、既存の push_invalid_long/collect_invalid_long_dsl 機構にそのまま
/// 合流して DR-054 definition-error (`DUnknownVocab`) になる。新しい definition-error チェックを
/// 増やさず既存機構に相乗りする設計判断の固定。「不在」ケース (次の wbtest の「存在するが
/// signature 不適合」ケースと対)。
test "DR-077 §2: an unrecognized update transform name is a DR-054 unknown-vocab definition-error" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TCount, long=LList([":update:bogus"]))],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) =>
      fail("expected Err (unrecognized transform 'bogus' is unknown-vocab)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == DUnknownVocab && e.element == "verbose" {
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
/// ケースを分離 pin する — どちらも現行 `DefErrKind` (DR-054) に signature 専用の細分 kind が無い
/// ため同じ `DUnknownVocab` に倒れる (installer.mbt の `classify_long_spelling` doc comment 参照、
/// 実装の裁量として報告済み)。
test "DR-077 §2: a registered but Validate-signature filter is also a DR-054 unknown-vocab definition-error" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TCount, long=LList([":update:in_range"]))],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) =>
      fail(
        "expected Err ('in_range' is Validate signature, not usable as an update transform)",
      )
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == DUnknownVocab && e.element == "verbose" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// 保証 (codex 指摘 2、DR-077 §2 の definition-time gate 精密化): 引数の arity は RUNTIME 関心
/// (`apply_transform`, resolve.mbt — closure 自身が拒否する、`apply_filter_chain` と同じ split)。
/// `classify_long_spelling` の definition-time gate は「registry に存在するか」「signature が
/// Transform か」の 2 点だけを見る — args の個数は関知しない。よって `:update:increment:5` (0-arg
/// 組み込み `increment` に余分な args) は **definition としては妥当** (increment は登録済み・
/// Transform signature)、Err にはならない。旧実装は `parts.length() == 3` を definition-time で
/// 強制する hardcoded allowlist だったため extra args を unknown-vocab として弾いていたが、
/// registry lookup ベースの新実装ではこの静的チェックが無くなった (意図的な設計変更 — arity
/// mismatch は resolve.mbt 側で kind:filter の実行時 Error として顕在化する、対で固定する次の
/// wbtest 参照)。
test "DR-077 §2: extra args to a registered Transform are NOT a definition-error (arity is a runtime concern)" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TCount, long=LList([":update:increment:5"]))],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      fail(
        "expected Ok (increment:5 is definition-valid, arity is checked at runtime): " +
        deferrs_str(errs),
      )
  }
}

///|
/// End-to-end 保証: installer chain (`parse_definition`) が組んだ Scope に対する CLI 発火
/// (`-vvv`) → `parse()` の生 binding 列 → `resolve_scope` の cli seat fold、という完全なパイプライン
/// が DR-077 の実運用シナリオ (`-v -v -v` = verbose level 3) を一気通貫で満たすことを固定する
/// (resolve_wbtest.mbt の低レベル `ceff` 直接構築テストと対をなす、installer 由来の Scope での確認)。
test "DR-077 end-to-end: parse_definition → parse → resolve_scope ledgers -vvv to 3" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TCount, long=LBool(true), short=['v'])],
  }
  let sc = ok_scope(def, all_installers())
  let o = parse(ScopeNode(sc), ["-vvv"], defs=Map([]))
  match o {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) => {
          let mut found = false
          for b in resolved {
            if b.key == "verbose" {
              found = true
              assert_eq(b.value, VNum(3.0))
            }
          }
          assert_true(found)
        }
        Err(_) => fail("expected Ok from resolve_scope")
      }
    _ =>
      fail(
        "expected Success from parse (-vvv should parse as 3 short cluster fires)",
      )
  }
}

// ── positional × or × repeat (issue 2026-07-09-positional-or-repeat-lowering-gap) ─────

///|
/// 保証: DR-043「repeat の対象要素は形を問わない」は ref head だけでなく **BOr (構造 or) head にも
/// 一様に適用される** — `lower_positional` の BOr ケースは以前 `elem_repeat(e)` を一切見ず常に
/// `Or(nodes)` を単発で積んでいた (installer.mbt 旧コメント「repeat との組合せは対象 fixture に無いので
/// 未対応」)。`{name:"hlcolors", repeat:{min:1}, or:[{seq:rgb 3数値}, {type:"string", name:"colorname"}]}`
/// で `["red","blue"]` (2 文字列) が unexpected-token になっていたのがこのギャップの症状。
/// `lower_repeat_head(e, Or(nodes), registry, out)` へ配線し、hand-built `Many(Or(...))` (slice 相当)
/// と同じ「両 or 枝が並列に反復できる」挙動を wire lowering 経由でも実現する。
test "positional or+repeat installer: string branch repeats in parallel with the seq(rgb) branch (issue 2026-07-09)" {
  let rgb_seq : OrBranch = {
    id: "rgb",
    items: [el("r", TNum), el("g", TNum), el("b", TNum)],
  }
  let name_leaf : OrBranch = { id: "colorname", items: [el("colorname", TStr)] }
  let hlcolors : ElemDef = {
    ..el("hlcolors", TStr),
    repeat: Some({ min: 1, max: None, lazy_: false }),
    body: BOr([rgb_seq, name_leaf]),
  }
  let def : Definition = { ..empty_def(), positionals: [hlcolors] }
  let registry : Map[String, Node] = Map([])
  let sc = match parse_definition(def, all_installers(), registry~) {
    Ok(s) => s
    Err(_) => abort("expected Ok(Scope)")
  }
  // 2 つの文字列トークンは rgb 枝に一致せず、string 枝 (colorname) が 2 回反復して吸収する。
  match parse(ScopeNode(sc), ["red", "blue"], defs=registry) {
    Success(bs) => {
      let mut count = 0
      for b in bs {
        if b.key == "colorname" {
          count = count + 1
        }
      }
      assert_eq(count, 2)
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
  // 3 つの数値トークンは (a) rgb 枝 1 反復、(b) string 枝 3 反復、の 2 通りに構造的に読める
  // (DR-038 完全経路 2 本) — ambiguous。
  match parse(ScopeNode(sc), ["255", "0", "0"], defs=registry) {
    Ambiguous(d) => assert_eq(d.interpretations.length(), 2)
    other => fail("expected Ambiguous, got " + render_outcome(other))
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
  let registry : Map[String, Node] = Map::from_array([
    ("x", Exact("user-defined-x")),
  ])
  let def : Definition = {
    ..empty_def(),
    positionals: [
      el("x", TStr, repeat=Some({ min: 1, max: None, lazy_: false })),
    ],
  }
  match parse_definition(def, [RepeatInst], registry~) {
    Ok(_) => {
      // ユーザが事前登録した "x" エントリは repeat lowering 後も無傷 (上書きされていない)。
      assert_eq(registry.get("x"), Some(Exact("user-defined-x")))
      // repeat 自身の自己参照 template は mangled key "x#cons" に登録される。
      match registry.get("x#cons") {
        Some(_) => ()
        None =>
          fail(
            "expected repeat's self-ref template under the mangled key 'x#cons'",
          )
      }
    }
    Err(_) => fail("expected Ok(Scope)")
  }
}

// ── DR-047 §5: requires 目的語の「値の有無」判定とフラグの暗黙 default (issue 2026-07-09-constraint-path-filtering-gap の調査結果) ──

///|
/// 保証 (issue 2026-07-09-constraint-path-filtering-gap、DR-047 §5 明確化 kawaz 裁定
/// 2026-07-09 で期待値が反転した wbtest): `requires` の目的語が bool 型 (フラグ含む) の場合、
/// 充足条件は「値の有無」ではなく「解決後の値が true であること」(値源不問)。判定は値源ラダーが
/// 解ける後段でしか行えないため、**`parse()` 単体では bool target の requires を KTop が常に
/// スキップする** (常に pass 扱い、"c" を一切与えなくても Success のまま — これは vacuous
/// satisfaction ではなく、後段フィルタを通す前の意図された中間状態)。`resolve.mbt` の
/// `apply_requires_filter` (cell_filters と同じ側の後段処理) を通して初めて、c が
/// 未解決 (default:false のまま) なら requires 違反として Failure に確定する — vacuous
/// satisfaction は後段フィルタ適用で解消されることを、この2段 (parse() 単体 / フィルタ後) で
/// 固定する。次の wbtest (target が非フラグ = KTop のまま従来通り) との対で挙動差を確認する。
test "DR-047 §5: requires targeting a FLAG — KTop skips it, apply_requires_filter enforces it" {
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TFlag, long=LList([":set"]))
  let def : Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  // parse() 単体: bool target なので KTop は常に pass 扱い (c を与えなくても Success)。
  match parse(root, ["--a"], defs=Map([])) {
    Success(_) => ()
    other =>
      fail(
        "expected Success (KTop skips bool-target requires), got " +
        render_outcome(other),
      )
  }
  // apply_requires_filter を通すと、c=false (未解決、暗黙 default:false) で requires
  // 違反が検出され Failure に確定する。
  match
    apply_requires_filter(
      parse(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
    ) {
    Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.kind == KConstraint && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "expected Failure (post-filter enforces bool-target requires), got " +
        render_outcome(other),
      )
  }
  // c を CLI で明示指定すれば true に解決され、フィルタ後も Success のまま。
  match
    apply_requires_filter(
      parse(root, ["--a", "--c"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      2,
    ) {
    Success(_) => ()
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (DR-088 §2/§4): `requires` の目的語が非フラグ (env 宣言あり、CLI/default 無し) でも、
/// KTop の探索中判定 (`value_declared`) は「env 宣言がある」ことだけで経路を完全と数える (値の実
/// 解決はしない、bare `parse()` の時点で既に `Success`) — DR-088 §1「宣言された値源はデフォルトの
/// 存在」の帰結。最終的な充足判定 (真の値があるか) は `apply_requires_filter` (post-parse、解決済み
/// bindings の読者) が担う: 実機再現の本体は次の wbtest ペア (env 実値あり/なし)。
test "DR-088: requires targeting an env-declared non-flag is a complete path at KTop even before resolving" {
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TStr, long=LList([":set"]), env=["C"])
  let def : Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["--a"], defs=Map([])) {
    Success(_) => ()
    other =>
      fail(
        "expected Success (env-declared target counts as a complete path at KTop, DR-088 §2), got " +
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
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TStr, long=LList([":set"]), env=["C"])
  let def : Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match
    apply_requires_filter(
      parse(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map::from_array([("C", "x")]),
      1,
    ) {
    Success(_) => ()
    other =>
      fail(
        "expected Success (env seat supplies c), got " + render_outcome(other),
      )
  }
}

///|
/// 対極: env が実際に未設定なら (CLI/default も無し) 従来どおり違反のまま Failure — env が
/// 「無条件に救済する」わけではないことの固定 (config/inherit 対極テストと対称)。
test "value-present-ladder-gap: requires targeting a non-flag with no env value still violates requires" {
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TStr, long=LList([":set"]), env=["C"])
  let def : Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match
    apply_requires_filter(
      parse(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
    ) {
    Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.kind == KConstraint && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail("expected Failure (requires unmet), got " + render_outcome(other))
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
    ..el("cfg", TStr, long=LList([":set"])),
    is_config_file: true,
    default_values: Some([VStr("/app.toml")]),
  }
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TFlag, long=LList([":set"]))
  let def : Definition = { ..empty_def(), options: [cfg_file, a, c] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match
    apply_requires_filter(
      parse(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
      provider=fn(_p) { Some(CObj([("c", CBool(true))])) },
    ) {
    Success(_) => ()
    other =>
      fail(
        "expected Success (config seat supplies c=true), got " +
        render_outcome(other),
      )
  }
}

///|
/// 対極: config オブジェクトに `c` が無い / `false` の場合は従来どおり未充足のまま Failure
/// (config が「無条件に救済する」わけではないことの固定)。
test "issue bool-requires-config-inherit-gap: config-sourced bool absent/false still violates requires" {
  let cfg_file = {
    ..el("cfg", TStr, long=LList([":set"])),
    is_config_file: true,
    default_values: Some([VStr("/app.toml")]),
  }
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TFlag, long=LList([":set"]))
  let def : Definition = { ..empty_def(), options: [cfg_file, a, c] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  fn check_failure(o : Outcome) -> Unit raise {
    match o {
      Failure(d) => {
        let mut found = false
        for e in d.errors {
          if e.kind == KConstraint && e.reason == "requires_violated" {
            found = true
          }
        }
        assert_true(found)
      }
      other =>
        fail("expected Failure (requires unmet), got " + render_outcome(other))
    }
  }
  // config オブジェクトに c キー自体が無い (供給なし → default:false へフォールスルー)
  check_failure(
    apply_requires_filter(
      parse(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
      provider=fn(_p) { Some(CObj([])) },
    ),
  )
  // config オブジェクトが c:false を明示供給
  check_failure(
    apply_requires_filter(
      parse(root, ["--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      1,
      provider=fn(_p) { Some(CObj([("c", CBool(false))])) },
    ),
  )
}

///|
/// 保証: bool target `c` が祖先 scope の inherit 経由でのみ true になる場合、
/// `apply_requires_filter` は祖先 scope chain (`table` = `collect_scopes` 全体) を辿って
/// 充足と判定する (DESIGN §11.2)。root で `c` を CLI 指定し (`--c`)、`sub` サブコマンド内で
/// `a requires c` を宣言、`sub` 自身の `c` は `is_inherit:true` で自前の値を持たない — 祖先
/// (root) の解決済み値 (CLI committed) を見つけて生存する。
test "issue bool-requires-config-inherit-gap: requires targeting an inherit-sourced bool survives the filter" {
  let root_c = el("c", TFlag, long=LList([":set"]))
  let child_a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let child_c = el("c", TFlag, long=LList([":set"]), is_inherit=true)
  let child : Definition = { ..empty_def(), options: [child_a, child_c] }
  let def : Definition = {
    ..empty_def(),
    options: [root_c],
    commands: [{ name: "sub", body: child, export_key: EkUnset }],
  }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match
    apply_requires_filter(
      parse(root, ["--c", "sub", "--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      3,
    ) {
    Success(_) => ()
    other =>
      fail(
        "expected Success (root's committed c=true reaches sub via inherit), got " +
        render_outcome(other),
      )
  }
}

///|
/// 対極: root で `--c` を指定しなければ (祖先も未解決、暗黙 default:false) 従来どおり Failure
/// (inherit が「無条件に救済する」わけではないことの固定 — 上の config 対極テストと対称)。
test "issue bool-requires-config-inherit-gap: inherit-sourced bool absent still violates requires" {
  let root_c = el("c", TFlag, long=LList([":set"]))
  let child_a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let child_c = el("c", TFlag, long=LList([":set"]), is_inherit=true)
  let child : Definition = { ..empty_def(), options: [child_a, child_c] }
  let def : Definition = {
    ..empty_def(),
    options: [root_c],
    commands: [{ name: "sub", body: child, export_key: EkUnset }],
  }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match
    apply_requires_filter(
      parse(root, ["sub", "--a"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      2,
    ) {
    Failure(d) => {
      let mut found = false
      for e in d.errors {
        if e.kind == KConstraint && e.reason == "requires_violated" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail("expected Failure (requires unmet), got " + render_outcome(other))
  }
}

///|
/// 保証 (回帰確認): 既存 CLI/env 経由テスト (上の DR-047 §5 対) が config_obj~ 未指定でも
/// 従来どおり動くこと — 新規 config/inherit 経路の追加が既存呼び出しシグネチャを壊していない
/// ことの固定 (`apply_requires_filter` の `config_obj~` 省略時デフォルト `None`)。
test "issue bool-requires-config-inherit-gap: existing CLI-committed bool target still survives without config_obj" {
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TFlag, long=LList([":set"]))
  let def : Definition = { ..empty_def(), options: [a, c] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match
    apply_requires_filter(
      parse(root, ["--a", "--c"], defs=Map([])),
      root,
      Map([]),
      Map([]),
      2,
    ) {
    Success(_) => ()
    other => fail("expected Success, got " + render_outcome(other))
  }
}

// ── codex Medium 追従 (issue merge-no-separator-marker-gap): separator 無し merge 宣言の
// end-to-end 固定。resolve_wbtest.mbt の合成 Entity テストは eval.mbt/installer.mbt の value_prim
// ルーティングを一切通らない (Binding を手組みするため) — この gap は「実 CLI argv → parse() →
// resolve_scope」の一気通貫でしか顕在化しなかった (`el()` の `separator: None` 固定と組み合わせて
// merge 宣言だけ足すことで、正に「separator 未宣言」の形が作れる)。 ─────────────────────────

///|
fn resolved_values(bs : Array[Binding], key : String) -> Array[Value] {
  let out : Array[Value] = []
  for b in bs {
    if b.key == key {
      out.push(b.value)
    }
  }
  out
}

///|
/// 保証 (上書き): separator 未宣言の merge 要素でも、マーカーを含まない単一発火は普通に add される
/// (DR-034 §6.3 の縮退 — 1 piece = トークン全体、`classify_merge_piece` を通しても marker に一致
/// しない文字列はそのまま literal)。
test "codex Medium: merge without separator — no-marker single fire adds (overwrite degenerate)" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        TStr,
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match parse(ScopeNode(sc), ["--fields", "hello"], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(resolved_values(resolved, "fields"), [VStr("hello")])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (remove 単独): 2 回目の発火 `-hello` は separator が無いので 1 piece のまま
/// `classify_merge_piece` に渡り、`-` 始まりなので remove マーカーと判定される (旧実装では
/// separator 無しだと SepArg に一切進まず、`-hello` はただの literal 文字列として上書きされ
/// `["-hello"]` になっていた — このケースが退行検知の主眼)。暗黙先頭 `@` が補われ old=[hello] を
/// splice、remove("hello") がそれを削って結果は空になる。
test "codex Medium: merge without separator — a lone remove-marker fire merges against prior old" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        TStr,
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match
    parse(
      ScopeNode(sc),
      ["--fields", "hello", "--fields", "-hello"],
      defs=Map([]),
    ) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) => assert_eq(resolved_values(resolved, "fields"), [])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (@ 恒等): 2 回目の発火 `@` 単独も 1 piece のまま splice マーカーと判定され、old (直前発火の
/// [hello]) をそのまま展開する恒等操作になる (結果不変)。
test "codex Medium: merge without separator — a lone splice-marker fire is identity" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        TStr,
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match
    parse(ScopeNode(sc), ["--fields", "hello", "--fields", "@"], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(resolved_values(resolved, "fields"), [VStr("hello")])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (escape): separator 無しでも escape 規約 (先頭 `+` を1個剥がす) は同じ pipeline で効く —
/// `+-x` は marker でなく literal `-x` の add になり、cell 上書き。
test "codex Medium: merge without separator — an escaped piece is a literal add" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el(
        "fields",
        TStr,
        long=LBool(true),
        multiple=true,
        accumulator=Some("merge"),
      ),
    ],
  }
  let sc = ok_scope(def, all_installers())
  match parse(ScopeNode(sc), ["--fields", "+-x"], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(resolved_values(resolved, "fields"), [VStr("-x")])
        Err(_) => fail("expected Ok")
      }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (DR-085 §1 訂正、kawaz 裁定 2026-07-10): a `regex_match` filter entry whose pattern fails to
/// compile is a definition-error, kind=DInvalidArgument (spec fixture 昇格済み: fixtures/definition-
/// error/regex-match-compile-invalid-argument.json — 本 wbtest はそれに先行する unit 層の pin として
/// 残す、`accum-update-invalid-range` の wbtest/fixture 対と同じ運用)。`[` は文字クラス開始のみで閉じ
/// `]` を欠く未完成構文 — regex エンジンの compile 段で方言を問わず共通に構文エラーになる (DR-085 §1
/// 波及節の「方言差の出ない共通パターン」条件を満たす不正 pattern)。
test "parse_definition: a regex_match filter with an uncompilable pattern is DInvalidArgument (DR-085 §1 訂正)" {
  let def : Definition = {
    ..empty_def(),
    options: [
      el("code", TStr, long=LBool(true), piece_filters=["regex_match:["]),
    ],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (regex_match pattern '[' fails to compile)")
    Err(errs) => {
      let mut has_invalid_argument = false
      for e in errs {
        if e.kind == DInvalidArgument && e.element == "code" {
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
  let def : Definition = {
    ..empty_def(),
    options: [
      el("code", TStr, long=LBool(true), piece_filters=["regex_match:^[a-z]+$"]),
    ],
  }
  match parse_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == DInvalidArgument {
          abort(
            "a regex_match entry with a compilable pattern must not raise DInvalidArgument",
          )
        }
      }
  }
}

///|
/// 保証: DR-085 波及節が要求する 3 相 (piece_filters/value_filters/cell_filters) 全てで regex_match
/// pattern compile 検査が効く — `regex_match` は plain `FilterDescriptor` (filters.mbt) で3相どれでも
/// 使える (accum cell_filters の array-vs-scalar 語彙分離のような相限定が無い)、その通り検査される
/// ことを value_filters/cell_filters それぞれで固定する (piece_filters は上の2テストが既に固定済み)。
test "parse_definition: regex_match compile check also fires for value_filters and cell_filters" {
  let def_value : Definition = {
    ..empty_def(),
    options: [el("a", TStr, long=LBool(true), value_filters=["regex_match:["])],
  }
  match parse_definition(def_value, all_installers()) {
    Ok(_) => abort("expected Err (value_filters regex_match compile failure)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == DInvalidArgument && e.element == "a" {
          found = true
        }
      }
      assert_true(found)
    }
  }
  let def_cell : Definition = {
    ..empty_def(),
    options: [el("b", TStr, long=LBool(true), cell_filters=["regex_match:["])],
  }
  match parse_definition(def_cell, all_installers()) {
    Ok(_) => abort("expected Err (cell_filters regex_match compile failure)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.kind == DInvalidArgument && e.element == "b" {
          found = true
        }
      }
      assert_true(found)
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
  let a = { ..el("a", TFlag, long=LBool(true)), conflicts_with: ["b"] }
  let b = el("b", TFlag, long=LList([":set"]))
  let def : Definition = { ..empty_def(), options: [a, b] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["--a", "--b"], defs=Map([])) {
    Failure(d) => {
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
        "expected Failure (conflicts enforced), got " + render_outcome(other),
      )
  }
}

///|
/// 保証: none 型セルが発火しても、シンプルモードの結果オブジェクトにキーが一切現れない (DR-089
/// §3「値の結果には現れない」、DR-051 §1/§4 の「値の無さはフィールドの不在」と同じ posture)。
test "DR-089: a fired none-typed pure trigger never appears in the result" {
  let sep = el("sep", TNone, long=LBool(true))
  let def : Definition = { ..empty_def(), options: [sep] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["--sep"], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(proj_result_export(sc, resolved, Map([])), "{}")
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (対極): none を明示 (`type:"none"`) しても消費 0 純トリガとして同じ挙動になる — 省略と
/// 明示綴りが同じタグに解決すること (DR-089 §2「省略は none の糖衣」) の固定。
test "DR-089: explicit type:none behaves identically to an omitted type" {
  let sep = el("sep2", TNone, long=LBool(true))
  let def : Definition = { ..empty_def(), options: [sep] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["--sep2"], defs=Map([])) {
    Success(bs) => assert_eq(bs.length(), 1)
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証: none 型を持つ positional + repeat の「食って捨てる」構造 (DR-089 §2 の `{"type": "none",
/// "repeat": {"min": 0}}` 例) が構造的に複数トークンを消費できる (消費は構造の関心、type とは直交
/// という §1 の帰結の end-to-end 固定)。
test "DR-089: a none-typed repeat positional structurally consumes multiple tokens (eat-and-discard)" {
  let colon = pos(
    "colon",
    TNone,
    repeat=Some({ min: 0, max: None, lazy_: false }),
  )
  let def : Definition = { ..empty_def(), positionals: [colon] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["x", "y"], defs=Map([])) {
    Success(bs) => {
      let mut n = 0
      for b in bs {
        if b.key == "colon" {
          n = n + 1
        }
      }
      assert_eq(n, 2)
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証: none を requires 目的語に宣言すると、値充足を要求される席に none は立てないため定義時
/// definition-error になる (DR-089 §4、DR-083 §5 と同型の静的既知チェック)。
test "DR-089: a none-typed requires target is a definition-error" {
  let a = { ..el("a", TFlag, long=LList([":set"])), requires: ["c"] }
  let c = el("c", TNone, long=LBool(true))
  let def : Definition = { ..empty_def(), options: [a, c] }
  match parse_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (none requires target is a definition-error)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.element == "a" {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// 保証 (team-lead 監査 2026-07-11): none には値空間が無いので、値源を宣言する
/// `env`/`config_key`/`inherit` は静的に既知の不成立構成であり definition-error になる (DR-089
/// §4、DR-083 §5 と同型)。3 種の値源宣言をそれぞれ個別の none 要素に付けて固定する。
test "DR-089: a none-typed element declaring env/config_key/inherit is a definition-error" {
  let with_env = el("has_env", TNone, long=LBool(true), env=["X"])
  let with_config_key = {
    ..el("has_config_key", TNone, long=LBool(true)),
    config_key: Some(["k"]),
  }
  let with_inherit = {
    ..el("has_inherit", TNone, long=LBool(true)),
    is_inherit: true,
  }
  let def : Definition = {
    ..empty_def(),
    options: [with_env, with_config_key, with_inherit],
  }
  match parse_definition(def, all_installers()) {
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
/// 対極: 値源を一切宣言しない none 要素 (純トリガ) は影響を受けない — このチェックが none 全般を
/// 誤って拒否しないことの固定 (上の definition-error テストの反例)。
test "DR-089 対極: a none-typed element with no value-source declaration is not a definition-error" {
  let sep = el("sep3", TNone, long=LBool(true))
  let def : Definition = { ..empty_def(), options: [sep] }
  match parse_definition(def, all_installers()) {
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
/// 対極: 既存の明示 type (TFlag) を持つ要素は type-none 対応 (decoder の省略受理、KTop/resolve の
/// none 判定分岐) を追加しても一切影響を受けない — 純粋な追加機能であることの固定。
test "DR-089 対極: a pre-existing explicit-type element is unaffected by none support" {
  let x = el("x", TFlag, long=LList([":set"]))
  let def : Definition = { ..empty_def(), options: [x] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["--x"], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(proj_result_export(sc, resolved, Map([])), "{x=true}")
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected Success, got " + render_outcome(other))
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
/// positional (optional/repeat 宣言なし) は、トークン供給なしでも Success になり、宣言済み
/// default の値が結果に実体化される — 旧実装は同じ入力で Failure(missing_operand) になっていた。
test "DR-088: a plain scalar positional with a declared default is a complete path with 0 tokens" {
  let seconds = { ..pos("seconds", TInt), default_values: Some([VNum(10.0)]) }
  let def : Definition = { ..empty_def(), positionals: [seconds] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, [], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(proj_result_export(sc, resolved, Map([])), "{seconds=10}")
        Err(_) => fail("expected Ok resolve")
      }
    other =>
      fail(
        "expected Success (declared default makes the path complete), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証: 同じ定義でトークンを供給すれば、供給値が (default ではなく) 結果に現れる — 構造的
/// optional 化がトークン供給時の通常経路を壊していないことの固定 (対称の成功面)。
test "DR-088: a plain scalar positional with a declared default still consumes a supplied token" {
  let seconds = { ..pos("seconds", TInt), default_values: Some([VNum(10.0)]) }
  let def : Definition = { ..empty_def(), positionals: [seconds] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["5"], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(proj_result_export(sc, resolved, Map([])), "{seconds=5}")
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 対極: default 宣言の無い素の positional は、この変更後も従来どおりトークン 0 個で
/// missing_operand の Failure になる — `fixtures/absent/required-positional.json` が pin する
/// 「必須 positional は absent にならない (present か parse failure の二択)」の輪郭を、この
/// 変更が壊していないことの固定 (構造的 optional 化は「宣言済み値源がある場合」限定)。
test "DR-088 対極: a plain scalar positional with NO declared default still misses on 0 tokens" {
  let file = pos("file", TStr)
  let def : Definition = { ..empty_def(), positionals: [file] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, [], defs=Map([])) {
    Failure(d) => {
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
        "expected Failure (no declared source, still required), got " +
        render_outcome(other),
      )
  }
}

///|
/// 対極2: `optional:true` (repeat 糖衣) を明示した positional は、この変更の影響を受けず従来どおり
/// 配列で結果に出る (DR-044 「max=1 でも配列」の特別化なし) — 構造的 optional 化の新経路
/// (`opt_node`) は `elem_repeat(e) is None` の場合限定であることの固定。
test "DR-088 対極2: an explicit optional:true positional is unaffected (still array-shaped)" {
  let tag = pos("tag", TStr, optional=true)
  let def : Definition = { ..empty_def(), positionals: [tag] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, [], defs=Map([])) {
    Success(bs) =>
      match resolve_scope(sc, bs, Map([])) {
        Ok(resolved) =>
          assert_eq(proj_result_export(sc, resolved, Map([])), "{tag=[]}")
        Err(_) => fail("expected Ok resolve")
      }
    other => fail("expected Success, got " + render_outcome(other))
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
fn dd_value_to_str(v : Value) -> String {
  match v {
    VStr(s) => s
    VNum(d) => d.to_string()
    VBool(b) => b.to_string()
  }
}

///|
/// 保証 (実機再現の pin、DR-090 §2/§3 の canonical 適用): `xargs -n 1 rm -f a` 型の輪郭。
/// `-n` は known option として発火し値 `1` を消費 (値スロットは raw 消費、DR-041 §4 — dd pattern
/// と形が交わらない)。`rm` (最初の非ハイフン operand) が pattern dd に一致して発火・自己保持
/// (self:keep、消費0で Accept) — `rm` 自身を含め以降 (`-f`, `a`) が positional 域 + severed に
/// 流れ、`-f` は既知 option の綴りでも severed により raw のまま (再発火しない、実 xargs と同じ)。
test "DR-090: xargs-style pattern dd (self:keep) — option fires, value slot raw, pattern-dd self-keep, tail severed" {
  let n = { ..el("n", TInt, short=['n']) }
  let dd = {
    ..el("dd", TStr, is_dd=true, dd_match=Some("^[^\\-]"), dd_self_keep=true)
  }
  let rest = pos("rest", TStr, repeat=Some({ min: 0, max: None, lazy_: false }))
  let def : Definition = {
    ..empty_def(),
    options: [n, dd],
    positionals: [rest],
  }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["-n", "1", "rm", "-f", "a"], defs=Map([])) {
    Success(bs) => {
      assert_eq(elem_value_bs(bs, "n"), Some("1"))
      let rest_vals : Array[String] = []
      for b in bs {
        if b.key == "rest" {
          rest_vals.push(dd_value_to_str(b.value))
        }
      }
      assert_eq(rest_vals, ["rm", "-f", "a"])
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
fn elem_value_bs(bs : Array[Binding], key : String) -> String? {
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
/// 挙動は不変。DdSat ノードがそのまま使われ続けることの間接固定 (`DdMatchSat` へ切り替わらない)。
test "DR-090 対極: exact dd (no match/self declared) is unaffected — drop + severed as before" {
  let dd = el("--", TStr, is_dd=true)
  let rest = pos("rest", TStr, repeat=Some({ min: 0, max: None, lazy_: false }))
  let def : Definition = { ..empty_def(), options: [dd], positionals: [rest] }
  let sc = ok_scope(def, all_installers())
  let root = ScopeNode(sc)
  match parse(root, ["--", "-x", "y"], defs=Map([])) {
    Success(bs) => {
      let rest_vals : Array[String] = []
      for b in bs {
        if b.key == "rest" {
          rest_vals.push(dd_value_to_str(b.value))
        }
      }
      // "--" 自身は消費されて捨てられる (self:drop) ので rest には現れない。
      assert_eq(rest_vals, ["-x", "y"])
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証: dd の `match` 正規表現が host dialect で compile 不能な場合、definition-error になる
/// (DR-090 §2、DR-085 §1 訂正の regex_match pattern compile 失敗と同じ kind=DInvalidArgument)。
test "DR-090: an uncompilable dd match pattern is a definition-error" {
  let dd = { ..el("dd", TStr, is_dd=true, dd_match=Some("[")) }
  let def : Definition = { ..empty_def(), options: [dd] }
  match parse_definition(def, all_installers()) {
    Ok(_) => abort("expected Err (uncompilable dd match pattern)")
    Err(errs) => {
      let mut found = false
      for e in errs {
        if e.element == "dd" && e.kind == DInvalidArgument {
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
  let dd = { ..el("dd", TStr, is_dd=true, dd_match=Some("^[^\\-]")) }
  let def : Definition = { ..empty_def(), options: [dd] }
  match parse_definition(def, all_installers()) {
    Ok(_) => ()
    Err(errs) =>
      for e in errs {
        if e.kind == DInvalidArgument {
          abort(
            "a dd with a compilable match pattern must not raise DInvalidArgument",
          )
        }
      }
  }
}

// ── DR-091 §3: long_prefix / require_equal_separator end-to-end ─────────────

///|
/// Guarantees (DR-091 §3 "if=(type: file) 級" motivating case): a `long_prefix:"" +
/// require_equal_separator:true` element parses its eq-split form (`if=abc`, one token) — this is
/// the ONLY entry point left once the space-form main entry is withheld (below).
test "DR-091 §3 end-to-end: long_prefix:\"\" + require_equal_separator:true accepts the eq form" {
  let if_elem = {
    ..el(
      "if",
      TStr,
      long=LBool(true),
      long_prefix="",
      require_equal_separator=true,
    )
  }
  let def : Definition = { ..empty_def(), options: [if_elem] }
  let sc = ok_scope(def, all_installers())
  let o = parse(ScopeNode(sc), ["if=abc"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut found = false
      for b in bs {
        if b.key == "if" {
          found = true
          assert_eq(b.value, VStr("abc"))
        }
      }
      assert_true(found)
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// Guarantees (DR-091 §3 "long の space-form main entry の登録をスキップ"): with
/// `require_equal_separator:true`, the SPACE form (`if abc`, 2 tokens, no `=`) has NO entry point
/// at all — `inst_long` withheld the main entry, and `EqSplit` never fires on a token without `=`
/// (`node.mbt`'s `EqSplit` doc comment: "Fires only on tokens containing `=`"). With no other
/// element in this Definition able to consume either token, the parse must FAIL — this is the
/// direct 対極 of the eq-form acceptance case above.
test "DR-091 §3 end-to-end: require_equal_separator:true rejects the space form (対極 of eq-form acceptance)" {
  let if_elem = {
    ..el(
      "if",
      TStr,
      long=LBool(true),
      long_prefix="",
      require_equal_separator=true,
    )
  }
  let def : Definition = { ..empty_def(), options: [if_elem] }
  let sc = ok_scope(def, all_installers())
  let o = parse(ScopeNode(sc), ["if", "abc"], defs=Map([]))
  match o {
    Failure(_) => ()
    other =>
      fail(
        "expected Failure (space form must have no entry point), got " +
        render_outcome(other),
      )
  }
}

///|
/// Guarantees (DR-091 §3 "空 prefix を許すと... 素 operand と long 経路が衝突しない" — the
/// non-collision half): a `long_prefix:""` element coexisting with an UNRELATED plain positional
/// in the SAME Definition does not swallow that positional's bare token — `foo` (no `=`) still
/// binds to `target`, `if` stays unfired (absent from the bindings). This is what makes the empty
/// prefix safe to declare alongside ordinary positionals, not just in isolation.
test "DR-091 §3 end-to-end: a long_prefix:\"\" element does not collide with a sibling plain positional (素 operand 非衝突)" {
  let if_elem = {
    ..el(
      "if",
      TStr,
      long=LBool(true),
      long_prefix="",
      require_equal_separator=true,
    )
  }
  let target = el("target", TStr)
  let def : Definition = {
    ..empty_def(),
    options: [if_elem],
    positionals: [target],
  }
  let sc = ok_scope(def, all_installers())
  let o = parse(ScopeNode(sc), ["foo"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut target_found = false
      let mut if_found = false
      for b in bs {
        if b.key == "target" {
          target_found = true
          assert_eq(b.value, VStr("foo"))
        }
        if b.key == "if" {
          if_found = true
        }
      }
      assert_true(target_found)
      assert_false(if_found)
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
}
