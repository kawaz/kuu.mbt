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
  long? : Array[String] = [],
  short? : Array[Char] = [],
  env? : Array[String] = [],
  is_dd? : Bool = false,
  is_global? : Bool = false,
  is_inherit? : Bool = false,
  repeat? : RepeatSpec? = None,
  multiple? : Bool = false,
) -> ElemDef {
  {
    name,
    ty,
    long,
    variants: [],
    short,
    env,
    is_dd,
    is_global,
    is_inherit,
    is_inheritable: false,
    link_depth: 0,
    ref_target: None,
    repeat,
    optional: false,
    multiple,
    separator: None,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    value_requires: [],
    deprecated: false,
    default_value: None,
    int_round: RError,
    allow_base_prefix: false,
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
    ..empty_def(),
    options: [el("port", TStr, long=["port"])],
  }
  let sc = ok_scope(def, [LongInst])
  // 貢献: (1) Seq([Exact("--port"), StrArg("port")]) の satellite が 1 本、(2) NativeMatch(EqSplit(...))
  // 1 本、計 greedy = 2 本。TStr なので value_prim = StrArg。
  assert_eq(sc.greedy.length(), 2)
  assert_eq(sc.greedy[0], Seq([Exact("--port"), StrArg("port")]))
  match sc.greedy[1] {
    NativeMatch(EqSplit(prefix=p, entries=es)) => {
      assert_eq(p, "--")
      assert_eq(es.length(), 1)
      assert_eq(es[0].key, "port")
      assert_eq(es[0].name, "port")
    }
    _ => abort("expected NativeMatch(EqSplit)")
  }
  // entity は name=port で 1 個、TFlag ではないので default_value は None。inherit_ / env_key
  // / config_seat / accum は installer が触っていないので初期値のまま。
  assert_eq(sc.entities.length(), 1)
  let ent = entity_of(sc, "port").unwrap()
  assert_eq(ent.ty, TStr)
  assert_eq(ent.env_key, None)
  assert_eq(ent.accum, None)
  assert_eq(ent.default_value, None)
}

// ── flag (TFlag) の default:false preset + fail_action ─────────────────────────

///|
/// 保証: TFlag entity には LOWERING §A.5 / DR-051 §2 に従い default:false を preset する
/// (未 fire でも false に落ちる)。flag の greedy satellite は Bind(name, VBool(true)) 版で、
/// eq-split matcher には登録されない (flag は value を持たないので `--flag=v` はそもそも来ない)。
test "long installer: flag gets Bind(true) satellite (no EqSplit entry) and default:false preset" {
  let def : Definition = {
    ..empty_def(),
    options: [el("verbose", TFlag, long=["verbose"])],
  }
  let sc = ok_scope(def, [LongInst])
  // TFlag なので eq-split entry は無い → greedy = Bind 衛星 1 本のみ。
  assert_eq(sc.greedy.length(), 1)
  assert_eq(
    sc.greedy[0],
    Seq([Exact("--verbose"), Bind("verbose", VBool(true))]),
  )
  let ent = entity_of(sc, "verbose").unwrap()
  // default:false preset (DR-051 §2)
  assert_eq(ent.default_value, Some(VBool(false)))
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
    options: [el("host", TStr, long=["host"], env=["HOST"])],
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
  // min:1 → min-1=0 mandatory heads → Ref("src") のみ 1 本
  assert_eq(sc.positional.length(), 1)
  assert_eq(sc.positional[0], Ref("src"))
  let ent = entity_of(sc, "src").unwrap()
  assert_eq(ent.accum, Some("flatten")) // DR-043 flatten
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
  assert_eq(sc.positional[0], StrArg("f"))
  assert_eq(sc.positional[1], BoundedTail(StrArg("f"), 2, false))
  // Ref template は登録されない (Ref 再帰なし)
  let ent = entity_of(sc, "f").unwrap()
  assert_eq(ent.accum, Some("flatten"))
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
    ..empty_def(),
    options: [el("verbose", TFlag, long=["verbose"], is_global=true)],
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
  // root には verbose entity + default:false preset がある
  let root_ent = entity_of(sc, "verbose").unwrap()
  assert_eq(root_ent.default_value, Some(VBool(false)))
}

// ── 順列耐性 (5 invariants + fixpoint): 順序が違っても同じ Scope に収束 ─────────

///|
/// 保証: 5 invariants + fixpoint により、chain の順序を変えても同じ Scope が組み上がる (DR-042 §invariants)。
/// long→env vs env→long で env seat が正しく立つか (env → ensure_entities → seat_env が同 pass に走るか
/// を fixpoint が救うか) を、chain の順序 2 種で確認する。
test "installer chain: order-independent thanks to 5 invariants + fixpoint" {
  let def : Definition = {
    ..empty_def(),
    options: [el("host", TStr, long=["host"], env=["HOST"])],
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
    options: [el("v", TFlag, long=["v"])], // long 属性あり
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
  // (4) LLiteral: no colon at all — a plain explicit spelling, passed through unchanged (e.g. an
  // alias's non-name-derived explicit trigger, DR-057 §3 "明示綴り非継承" — compress's "gzip").
  match classify_long_spelling("gzip", "compress", TStr) {
    LLiteral(s) => assert_eq(s, "gzip")
    _ => fail("expected LLiteral")
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
  // an unrecognized op word is not a valid DSL form — treated as a literal spelling (not a crash),
  // since production code has no DecodeSkip-style channel to reject it definition-time here.
  match classify_long_spelling("no:bogus:false", "ssl", TBool) {
    LLiteral(s) => assert_eq(s, "no:bogus:false")
    _ => fail("expected LLiteral (unrecognized op word)")
  }
}
