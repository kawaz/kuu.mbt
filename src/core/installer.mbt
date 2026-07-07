// installer.mbt — parse_definition as a chain of installers (DR-042).
//
// UsefulAST (ElemDef / Definition / …) → AtomicAST (Scope / Node / Entity / …) を組み立てる lowering 層。
// 各 installer は special vocab (long / short / env / dd / ...) を所有し、apply 時に (1) その vocab を
// READ (削除しない — 宣言層は read-only, invariant ①'), (2) greedy 衛星 / matcher / re-scoping を
// add-if-absent で implant する, (3) 実体 (Entity) の seat (env / inherit) を宣言する。5 invariants により
// chain の順序に依存せず、idempotent。完全性は「chain のどの installer にも所有されない special vocab」の検査。
//
// MDR-002 §3 準拠: installer は node / value / matcher / resolve に依存し、評価器 (eval) には依存しない。
// MDR-002 追記「CPS の射程」の installer 規約: repeat はスパイン形 (positional の Ref / BoundedTail /
// ScopeNode) にのみ正規化し、Or / Seq / Rooted 内部への埋め込みは生成しない (取り分選好の局所化を避けるため)。
// MDR-003 命名規約: bare 予約語は末尾 `_` 化 — RepeatSpec の bare `lazy` は `lazy_` に rename。
// Entity 側の `inherit_` は node.mbt が rename 済み。

///|
/// UsefulAST element. Attribute arrays are READ-ONLY to installers (invariant ①': 宣言層 read-only).
/// The declaration layer is never emptied — help / diagnose / 再シリアライズが元の宣言を保持し、後段
/// installer (global 等) も引き続き参照できる。Idempotency は add-if-absent が担う。
pub(all) struct ElemDef {
  name : String
  ty : Ty
  long : Array[String] // long installer 所有: main-entry base spelling (`:set` = name 由来, kebab / それ以外 = 明示綴り, [] = main-entry なし DR-071)
  variants : Array[Variant] // long installer 所有 (variant DSL, DR-011/045)
  short : Array[Char] // short installer 所有
  env : Array[String] // env installer 所有
  is_dd : Bool // dd installer 所有 (type:"dd")
  is_global : Bool // global installer 所有 (子孫 command scope へコピー伝播)
  is_inherit : Bool // inherit installer 所有 (inherit seat 宣言)
  is_inheritable : Bool // inheritable installer 所有 (DR-059)
  link_depth : Int // >0 なら global COPY が declaring scope 何段下に置かれたか (satellite が Rooted で escape する段数)
  ref_target : String? // DR-020: この要素は named template への ref
  repeat : RepeatSpec? // repeat installer 所有 (DR-043)
  optional : Bool // repeat:{min:0,max:1} の糖衣 (DR-043) — repeat 語彙が所有
  multiple : Bool // multiple installer 所有 (DR-034/043)
  separator : String? // multiple パイプラインの separator (DR-034)
  fail_action : Bool // failure-action element (DR-048)
  is_config_file : Bool // type:"config_file" (DR-050)
  config_key : Array[String]? // 明示 config path (DR-050 §3); None = 同型
  export_key : ExportKey // 結果キー軸 (DR-052)
  requires : Array[String] // constraint installer (DR-055): 正の依存
  conflicts_with : Array[String] // constraint installer (DR-055): 対称ペア排他
  exclusive_group : Array[String] // constraint installer (DR-047): group labels
  value_requires : Array[(String, Array[String])] // DR-055 §1: (value → required) 値の枝に付いた requires
  deprecated : Bool // DR-058: 使用時 `@depr:<name>` warning
  default_value : Value?
} derive(Eq, Debug)

///|
/// alias 宣言 (DR-057): 参照ファミリー third member (ref / link / **alias**). 独立 element として
/// `{alias:"port", short:"n"}` の形で書く。`target` = canonical, `name` = alias 自身の名 (None なら
/// canonical と同名), `short` = alias 明示 short (canonical の short は継承しない §3), `long_override`
/// (DR-007 差分上書き): None = alias 名で name-derived variants を再導出, Some(xs) = 明示置換。
pub(all) struct AliasDef {
  target : String
  name : String?
  short : Array[Char]
  long_override : Array[String]?
  deprecated : Bool
} derive(Eq, Debug)

///|
/// variant entry (DR-011 / DR-045). `--no-ssl` のような distinct trigger が cell に EFFECT を適用する。
/// long installer が `{exact, link (by name), effect}` に lowering する (LOWERING §B.1)。
pub(all) struct Variant {
  trigger : String
  op : EffectOp
  operand : Value? // set variant のみ操作数を持つ; default / unset / empty は None
} derive(Eq, Debug)

///|
/// repeat 閉包 (DR-043)。`min` は必須 rep 数 (mandatory-head unroll)。`max`: None = 無限 (Ref tail),
/// Some(M) = 有限 (M-min BoundedTail heads、Ref 再帰なし LOWERING §B.8)。`optional:true` は
/// `{min:0,max:Some(1)}` の糖衣 (ここで還元、独立概念ではない DR-043)。`lazy_` は取り分選好
/// (greedy default / lazy 最短優先) — MDR-003 で bare `lazy` → `lazy_`。
pub(all) struct RepeatSpec {
  min : Int
  max : Int? // None = unbounded (Ref tail), Some(M) = bounded (BoundedTail)
  lazy_ : Bool // MDR-003: bare `lazy` は予約語衝突 → `lazy_`
} derive(Eq, Debug)

///|
/// subcommand (DR-041 §4)。`export_key`: null = scope key drop, 子は親 scope へ promote (DR-052)。
pub(all) struct CommandDef {
  name : String
  body : Definition
  export_key : ExportKey
} derive(Eq, Debug)

///|
/// 1 つの command scope の UsefulAST。`commands` は DR-018 sugar; command installer が greedy 排他
/// trigger + 新 backbone (DR-041 §4) に展開する。
pub(all) struct Definition {
  options : Array[ElemDef]
  positionals : Array[ElemDef]
  commands : Array[CommandDef]
  aliases : Array[AliasDef] // DR-057
} derive(Eq, Debug)

///|
/// canonical installers (DR-042 §canonical installer セット + DR-043 repeat/multiple)。
pub(all) enum Installer {
  LongInst
  ShortInst
  EnvInst
  DdInst
  CommandInst
  GlobalInst
  InheritInst
  RepeatInst
  MultipleInst
  ConfigInst
  ConstraintInst
  AliasInst
  InheritableInst
} derive(Eq, Debug)

///|
fn owned_vocab(i : Installer) -> String {
  match i {
    LongInst => "long"
    ShortInst => "short"
    EnvInst => "env"
    DdInst => "dd"
    CommandInst => "command"
    GlobalInst => "global"
    InheritInst => "inherit"
    RepeatInst => "repeat"
    MultipleInst => "multiple"
    ConfigInst => "config" // type:"config_file" と config_key 両方 (DR-050)
    ConstraintInst => "constraint" // requires / conflicts_with / exclusive_group (DR-055)
    AliasInst => "alias" // alias 宣言 (DR-057)
    InheritableInst => "inheritable" // inheritable (DR-059)
  }
}

///|
/// 1 scope 分の mutable build accumulator。installer は ADD だけ (add-if-absent)。build 層は
/// monotonically 成長し、全木の 1 pass が何も追加しなくなった時点で fixpoint。
priv struct Build {
  greedy : Array[Node]
  entities : Array[Entity]
  positional : Array[Node]
  constraints : Array[Constraint]
}

///|
/// scope-builder tree の 1 node。Definition tree を写す。`decl` は宣言層 (installer からは read-only
/// だが global installer が `options` に COPY を push する — invariant ②)。`build` は lowering 層。
priv struct SB {
  decl : Definition
  build : Build
  children : Array[SBChild]
}

///|
priv struct SBChild {
  name : String
  body : SB
}

///|
fn value_prim(ty : Ty, name : String) -> Node {
  match ty {
    // TNum / TInt は CLI 側では number-like 扱い (integer 値空間判定は config 段で行う)
    TNum | TInt => NumArg(name)
    _ => StrArg(name)
  }
}

///|
fn copy_strs(a : Array[String]) -> Array[String] {
  let r : Array[String] = []
  for x in a {
    r.push(x)
  }
  r
}

///|
/// 有効 long 綴り一覧 (post-normalize; `:set` は既に kebab(name) に展開済み)。[] = main-entry なし (DR-071)。
fn long_of(e : ElemDef) -> Array[String] {
  e.long
}

///|
fn copy_chars(a : Array[Char]) -> Array[Char] {
  let r : Array[Char] = []
  for x in a {
    r.push(x)
  }
  r
}

///|
fn copy_variants(a : Array[Variant]) -> Array[Variant] {
  let r : Array[Variant] = []
  for x in a {
    r.push(x)
  }
  r
}

///|
fn clone_elem(e : ElemDef) -> ElemDef {
  {
    name: e.name,
    ty: e.ty,
    long: copy_strs(e.long),
    variants: copy_variants(e.variants),
    short: copy_chars(e.short),
    env: copy_strs(e.env),
    is_dd: e.is_dd,
    is_global: e.is_global,
    is_inherit: e.is_inherit,
    is_inheritable: e.is_inheritable,
    link_depth: e.link_depth,
    ref_target: e.ref_target,
    repeat: e.repeat,
    optional: e.optional,
    multiple: e.multiple,
    separator: e.separator,
    fail_action: e.fail_action,
    is_config_file: e.is_config_file,
    config_key: e.config_key,
    export_key: e.export_key,
    requires: e.requires,
    conflicts_with: e.conflicts_with,
    exclusive_group: e.exclusive_group,
    value_requires: e.value_requires,
    deprecated: e.deprecated,
    default_value: e.default_value,
  }
}

///|
/// snake_case → kebab-case (DR-022): AST key は snake, CLI long は kebab。ASCII のみ想定。
fn kebab(name : String) -> String {
  let buf = StringBuilder::new()
  for c in name {
    if c == '_' {
      buf.write_char('-')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// 純構文 pre-pass (LOWERING §A / §C.4)。static check と installer fixpoint の前に走る:
///   Fix 2 (§B.1 / DR-071): option の `long` 配列内 `:set` main-entry descriptor を kebab(name) に展開
///   Fix 3 (DR-064 §5): dd 要素で name 未指定なら trigger 綴りを "--" に既定
fn normalize_surface(def : Definition) -> Unit {
  let mut i = 0
  while i < def.options.length() {
    def.options[i] = normalize_option(def.options[i])
    i = i + 1
  }
  i = 0
  while i < def.positionals.length() {
    def.positionals[i] = normalize_dd_name(def.positionals[i])
    i = i + 1
  }
  for c in def.commands {
    normalize_surface(c.body)
  }
}

///|
fn normalize_option(e : ElemDef) -> ElemDef {
  if e.is_dd {
    normalize_dd_name(e)
  } else {
    // DR-071 two-form long: `:set` = name-derived (kebab, DR-022 / LOWERING §B.1)。空 long は main-entry 無し。
    let resolved : Array[String] = []
    for l in e.long {
      resolved.push(if l == ":set" { kebab(e.name) } else { l })
    }
    { ..e, long: resolved }
  }
}

///|
fn normalize_dd_name(e : ElemDef) -> ElemDef {
  if e.is_dd && e.name == "" {
    { ..e, name: "--" } // DR-064 §5
  } else {
    e
  }
}

///|
fn clone_def(d : Definition) -> Definition {
  let os : Array[ElemDef] = []
  for e in d.options {
    os.push(clone_elem(e))
  }
  let ps : Array[ElemDef] = []
  for e in d.positionals {
    ps.push(clone_elem(e))
  }
  let cs : Array[CommandDef] = []
  for c in d.commands {
    cs.push({ name: c.name, body: clone_def(c.body), export_key: c.export_key })
  }
  let als : Array[AliasDef] = []
  for a in d.aliases {
    als.push(a) // AliasDef は immutable value data (nested mutable array を持たない)
  }
  { options: os, positionals: ps, commands: cs, aliases: als }
}

///|
/// 結果キー map の構築 (DR-052)。要素/コマンド名 → export_key。post-parse の結果 remap 用。alias
/// を desugar 済みの clone に対して収集する — command alias の export_key = EkKey(canonical) が
/// 建った Scope の keying と一致するように。
pub fn build_export_map(def : Definition) -> Map[String, ExportKey] {
  let d = clone_def(def)
  desugar_aliases(d)
  let m : Map[String, ExportKey] = Map([], capacity=0)
  collect_export(d, m)
  m
}

///|
fn collect_export(def : Definition, m : Map[String, ExportKey]) -> Unit {
  for e in def.options {
    m.set(e.name, e.export_key)
  }
  for e in def.positionals {
    m.set(e.name, e.export_key)
  }
  for c in def.commands {
    m.set(c.name, c.export_key)
    collect_export(c.body, m)
  }
}

///|
/// 要素の lowered head: 値プリミティブ / Ref (ref_target) / SepArg (separator)。
fn elem_head(e : ElemDef) -> Node {
  match e.ref_target {
    Some(r) => Ref(r)
    None =>
      match e.separator {
        Some(sep) => SepArg(e.name, sep)
        None => value_prim(e.ty, e.name)
      }
  }
}

///|
/// 有効 repeat spec (DR-043)。`optional:true` は `{min:0,max:1}` の糖衣 (独立概念ではない)。
fn elem_repeat(e : ElemDef) -> RepeatSpec? {
  match e.repeat {
    Some(s) => Some(s)
    None =>
      if e.optional {
        Some({ min: 0, max: Some(1), lazy_: false })
      } else {
        None
      }
  }
}

///|
/// `Opt(X)` = `Or([X, Seq([])])`。空 Seq が 0 トークン一致。
fn opt_node(x : Node) -> Node {
  Or([x, Seq([])])
}

///|
/// positional face の lowering。repeat 要素 (DR-043) は Ref 再帰: template
/// `name = Seq([head, Opt(Ref(name))])` を registry に登録し、spine には `min-1` mandatory + Ref。
/// bounded (max 有限) は Ref 再帰なしで BoundedTail に落ちる (LOWERING §B.8)。dd 要素は spine に載せない。
///
/// MDR-002 §CPS 規約: repeat はここでスパイン形 (positional の Ref / BoundedTail / ScopeNode) にのみ
/// 正規化し、Or/Seq/Rooted 内部への埋め込みは生成しない (取り分選好の局所化を避けるため)。
fn lower_positional(
  def : Definition,
  registry : Map[String, Node],
) -> Array[Node] {
  let out : Array[Node] = []
  for e in def.positionals {
    if not_dd(e) {
      let head = elem_head(e)
      match elem_repeat(e) {
        None => out.push(head)
        Some(spec) =>
          match spec.max {
            None => {
              // UNBOUNDED (DR-043): `name = Seq([head, Opt(Ref(name))])` の porous 自参照
              registry.set(e.name, Seq([head, opt_node(Ref(e.name))]))
              if spec.lazy_ {
                // lazy marker (evaluator が split 選好を引くための mangled key)
                registry.set("lazy:" + e.name, Exact("lazy"))
              }
              let m = if spec.min < 1 { 1 } else { spec.min }
              let mut k = 0
              while k < m - 1 {
                out.push(head) // mandatory unrolled heads (DR-043 min)
                k = k + 1
              }
              out.push(Ref(e.name)) // >= 1 porous recursive tail
            }
            Some(mx) => {
              // BOUNDED (LOWERING §B.8): min mandatory heads + BoundedTail(head, max-min)
              let m = if spec.min < 0 { 0 } else { spec.min }
              let mut k = 0
              while k < m {
                out.push(head)
                k = k + 1
              }
              let budget = if mx - m < 0 { 0 } else { mx - m }
              out.push(BoundedTail(head, budget, spec.lazy_))
            }
          }
      }
    }
  }
  out
}

///|
/// (cloned) Definition tree から scope-builder tree を組む。positional は 1 度だけ lower (以後は成長
/// しない — global copy は greedy 側に入る)。entities / greedy は fixpoint pass で埋める。
fn init_sb(def : Definition, registry : Map[String, Node]) -> SB {
  let positional = lower_positional(def, registry)
  let children : Array[SBChild] = []
  for c in def.commands {
    children.push({ name: c.name, body: init_sb(c.body, registry) })
  }
  {
    decl: def,
    build: { greedy: [], entities: [], positional, constraints: [] },
    children,
  }
}

///|
/// Core lowering (installer ではない — 決定的、順序無依存): option/positional ごとに entity 1 個を
/// name 割当で ensure (add-if-absent)。毎 pass 走る (global-copied option も entity を得るため)。
///
/// dd 要素は entity を持たない (LOWERING §B.4「値なし」/ DR-064 §1)。link_depth == 0 のみ ensure
/// (global link COPY は declaring cell へ link 同期するため子 scope 側 entity は不要 — DR-070 §1b gap 5)。
fn ensure_entities(sb : SB, has_cf : Bool) -> Unit {
  for e in sb.decl.options {
    if not_dd(e) && e.link_depth == 0 {
      ensure_entity(sb.build, e, has_cf)
    }
  }
  for e in sb.decl.positionals {
    if not_dd(e) {
      ensure_entity(sb.build, e, has_cf)
    }
  }
}

///|
fn ensure_entity(build : Build, e : ElemDef, has_cf : Bool) -> Unit {
  for ent in build.entities {
    if ent.name == e.name {
      return
    }
  }
  // repeat / multiple / separator は値 LIST — 名前付き accumulator registry に落とす (DR-036)。
  //   repeat → "flatten" (cons [T,[T,…]] → T[], DR-043)
  //   multiple / separator → "append" (DR-034)
  // 両方立った場合は multiple の append が勝つ (値 fold が支配)。
  // DR-044 §1 (kawaz 裁定): repeat / multiple / separator は cardinality 不問で常に配列
  //   (`repeat:{min:0,max:1}` = optional 糖衣も [] / [x] — scalar 昇格は collector 側の責務)。
  let accum : String? = if e.multiple {
    Some("append")
  } else {
    match elem_repeat(e) {
      Some(_) => Some("flatten")
      None => if e.separator is Some(_) { Some("append") } else { None }
    }
  }
  // 同型 config seat (DR-050 §3): config_file 要素が存在すれば全 value cell に config seat を宣言
  // (自身が config_file の要素は循環禁止で除く)。config_key は path override; None = 同型。
  let config_seat = has_cf && !e.is_config_file
  // flag preset default (LOWERING §A.5 / DR-051 §2): TFlag cell は default:false を preset
  // (未 fire でも false に落ちる)。明示 default があればそちらが勝つ。
  let default_value : Value? = match e.default_value {
    Some(v) => Some(v)
    None => if e.ty == TFlag { Some(VBool(false)) } else { None }
  }
  build.entities.push({
    name: e.name,
    ty: e.ty,
    env_key: None,
    config_seat,
    config_key: e.config_key,
    is_config_file: e.is_config_file,
    inherit_: false, // MDR-003: node.mbt 側 Entity.inherit_
    accum,
    default_value,
  })
}

///|
fn not_dd(e : ElemDef) -> Bool {
  !e.is_dd
}

// ── 各 installer ─────────────────────────────────────────────────────────────

///|
/// long: `long` を READ、name あたり greedy exact 衛星 (space form) と、value 系なら eq-split matcher
/// を add-if-absent で追加。衛星は name で entity に link (DR-042 §展開の標準パターン)。
fn inst_long(def : Definition, build : Build) -> Unit {
  let eq_entries : Array[LongEntry] = []
  for e in def.options {
    for l in long_of(e) {
      let trigger = "--" + l
      match e.ty {
        TFlag =>
          // flag: trigger fire → name=true。failure-action (DR-048) は追加で FailMark を発する
          // (FAILED parse で fire できる)。dd-internal な --help は raw-consumed で発火しない (先食い/内部一体)。
          add_greedy(
            build,
            maybe_root(
              e.link_depth,
              if e.fail_action {
                Seq([
                  Exact(trigger),
                  Bind(e.name, VBool(true)),
                  FailMark(e.name),
                ])
              } else {
                Seq([Exact(trigger), Bind(e.name, VBool(true))])
              },
            ),
          )
        _ => {
          add_greedy(
            build,
            maybe_root(
              e.link_depth,
              Seq([Exact(trigger), value_prim(e.ty, e.name)]),
            ),
          )
          eq_entries.push({ key: l, name: e.name, kind: e.ty })
        }
      }
    }
  }
  if eq_entries.length() > 0 {
    add_greedy(build, NativeMatch(EqSplit(prefix="--", entries=eq_entries)))
  }
  // Variant entries (DR-011 / DR-045): `{exact, link (by name), effect}` に lowering。
  // `set` variant は Bind (SET degenerate); default/unset/empty は EffMark (0-token effect)。
  for e in def.options {
    for v in e.variants {
      let trigger = "--" + v.trigger
      let sat = match v.op {
        Set => {
          let operand = match v.operand {
            Some(val) => val
            None => VBool(true)
          }
          Seq([Exact(trigger), Bind(e.name, operand)])
        }
        _ => Seq([Exact(trigger), EffMark(e.name, v.op)])
      }
      add_greedy(build, maybe_root(e.link_depth, sat))
    }
  }
}

///|
/// global link COPY (link_depth > 0) を `Rooted(node, depth)` で包む — bindings が declaring scope の
/// entity に landing するよう escape する (DR-042 link-sync)。link_depth == 0 は自宣言で wrap しない。
fn maybe_root(link_depth : Int, node : Node) -> Node {
  if link_depth > 0 {
    Rooted(node, link_depth)
  } else {
    node
  }
}

///|
/// short: `short` を READ、cluster/value-attach matcher を 1 本 add-if-absent。PoC では single-char
/// (`-v`, `-p 8080`) も matcher に集約するため、short は独立 exact 衛星を発しない (matcher-seat)。
fn inst_short(def : Definition, build : Build) -> Unit {
  let sh_entries : Array[ShortEntry] = []
  for e in def.options {
    for c in e.short {
      // DR-058: deprecated alias entry-copy は cluster entry でも警告する
      sh_entries.push({ ch: c, name: e.name, kind: e.ty, depr: e.deprecated })
    }
  }
  if sh_entries.length() > 0 {
    add_greedy(build, NativeMatch(ShortCombine(prefix="-", entries=sh_entries)))
  }
}

///|
/// env: `env` を READ、entity の env seat に登録 (invariant ④)。ladder 順序は engine 所有 (DR-031)、
/// default_fn を wrap しない。同 seat 再宣言は no-op (idempotent in-place set)。
fn inst_env(def : Definition, build : Build) -> Unit {
  for e in def.options {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
    }
  }
  for e in def.positionals {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
    }
  }
}

///|
fn seat_env(build : Build, name : String, key : String) -> Unit {
  for ent in build.entities {
    if ent.name == name {
      ent.env_key = Some(key)
    }
  }
}

///|
/// dd: `type:"dd"` を READ、greedy exact 衛星 (DdSat) を add-if-absent (DR-041 rev)。fire 時に spine
/// walk が「severed」モードに切り替わり以降 greedy off — greedy internal consumption 一体化ルール。
///
/// DR-064 §2 配置不問回収: dd は canonical には options[] だが positionals[] に置いても回収する
/// (env / inherit と同じく両 face を walk する対称形)。add-if-absent (add_greedy) が重複宣言を collapse。
fn inst_dd(def : Definition, build : Build) -> Unit {
  // DR-064 §5: dd の name は trigger 綴りに効く (normalize_surface が既定 "--" を供給、明示は上書き)。
  for e in def.options {
    if e.is_dd {
      add_greedy(build, DdSat(e.name))
    }
  }
  for e in def.positionals {
    if e.is_dd {
      add_greedy(build, DdSat(e.name))
    }
  }
}

///|
/// add-if-absent (invariant ①' 非削除): 構造等価な既存があれば追加しない。再適用を no-op に、fixpoint
/// を収束させる。
fn add_greedy(build : Build, g : Node) -> Unit {
  for existing in build.greedy {
    if existing == g {
      return
    }
  }
  build.greedy.push(g)
}

///|
/// inherit: `inherit` を READ、entity に inherit seat を宣言 (invariant ④, DR-031 cli>env>inherit>default)。
/// seat の実 lookup 「最近祖先の同名 entity 値」は runtime (resolve_scope) で解く。env と対称の seat 宣言型。
fn inst_inherit(def : Definition, build : Build) -> Unit {
  for e in def.options {
    if e.is_inherit {
      seat_inherit(build, e.name)
    }
  }
  for e in def.positionals {
    if e.is_inherit {
      seat_inherit(build, e.name)
    }
  }
}

///|
fn seat_inherit(build : Build, name : String) -> Unit {
  for ent in build.entities {
    if ent.name == name {
      ent.inherit_ = true // MDR-003
    }
  }
}

///|
/// global: `global` を READ、option 宣言を子孫 command scope の宣言層にコピー (invariant ②)。
/// long/short は次 pass 以降で子で展開する。shadowing (DR-032/033, 最小 scope): 子が同トリガを既に
/// 宣言していれば copy しない (自前が勝つ)。copy は `is_global` を保持し、fixpoint で更に下位へ再伝播。
fn inst_global(sb : SB) -> Unit {
  for opt in sb.decl.options {
    if opt.is_global {
      for child in sb.children {
        copy_global_into(child.body, opt)
      }
    }
  }
}

///|
fn copy_global_into(child : SB, opt : ElemDef) -> Unit {
  for existing in child.decl.options {
    if triggers_overlap(existing, opt) {
      return // shadow または既に copy 済 (idempotent)
    }
  }
  // copy は link 衛星 (DR-042): declaring scope の entity を bind (子は自 cell を持たない)。
  // link_depth = declaring scope からの段数 (+1 per re-propagation)。long/short が Rooted(node, depth)
  // で wrap する。
  //
  // INVARIANT (install-time count ↔ eval-time decrement, 現制約): この +1 は SCOPE (name/command) copy
  // level のみ数える (copy_global_into 1 段につき 1)。eval 側の Rooted `link` counter は 2 種の nesting
  // (nest = scope 段 / nest_index = rep #k 段) で減算される。したがって「link_depth == 衛星と declaring
  // scope の間の eval nesting 段数」の不変条件は「Rooted 衛星が IdxRepeat の下に置かれない」条件下でのみ
  // 成立する — 現行 lowering は Rooted を scope spine で wrap し、repeat head 内には入れないので満たす。
  // 将来 nested-group が scope/global を repeat 群に許容するなら、この +1 に rep-nesting depth も加算する。
  let copy = clone_elem(opt)
  child.decl.options.push({
    name: copy.name,
    ty: copy.ty,
    long: copy.long,
    variants: copy.variants,
    short: copy.short,
    env: copy.env,
    is_dd: copy.is_dd,
    is_global: copy.is_global,
    is_inherit: copy.is_inherit,
    is_inheritable: copy.is_inheritable,
    link_depth: copy.link_depth + 1,
    ref_target: copy.ref_target,
    repeat: copy.repeat,
    optional: copy.optional,
    multiple: copy.multiple,
    separator: copy.separator,
    fail_action: copy.fail_action,
    is_config_file: copy.is_config_file,
    config_key: copy.config_key,
    export_key: copy.export_key,
    requires: copy.requires,
    conflicts_with: copy.conflicts_with,
    exclusive_group: copy.exclusive_group,
    value_requires: copy.value_requires,
    deprecated: copy.deprecated,
    default_value: copy.default_value,
  })
}

///|
/// トリガ衝突: 2 option が long / short いずれかを共有すれば衝突 (shadow はトリガ基準 = 同名トリガ)。
fn triggers_overlap(a : ElemDef, b : ElemDef) -> Bool {
  for la in long_of(a) {
    for lb in long_of(b) {
      if la == lb {
        return true
      }
    }
  }
  for ca in a.short {
    for cb in b.short {
      if ca == cb {
        return true
      }
    }
  }
  false
}

// ── driver + completeness ────────────────────────────────────────────────────

///|
/// 1 scope node に 1 installer を適用。long/short/env/dd/inherit は当該 node の build に貢献。
/// global は子孫の宣言層にコピー。command は materialize 段で wire (展開は決定的 — DR-018 / DR-041 §4)。
fn apply_node(inst : Installer, sb : SB) -> Unit {
  match inst {
    LongInst => inst_long(sb.decl, sb.build)
    ShortInst => inst_short(sb.decl, sb.build)
    EnvInst => inst_env(sb.decl, sb.build)
    DdInst => inst_dd(sb.decl, sb.build)
    InheritInst => inst_inherit(sb.decl, sb.build)
    GlobalInst => inst_global(sb)
    CommandInst => () // materialize で wire
    RepeatInst => () // init_sb で決定的に lower (Ref 再帰 + template)
    MultipleInst => () // ensure_entity で accumulator flag を決定的に set
    ConfigInst => () // ensure_entity で config seat を決定的に set (席宣言型 DR-050/042 ④)
    ConstraintInst => inst_constraint(sb.decl, sb.build)
    AliasInst => () // desugar_aliases (init_sb 前) で決定的に展開 — entry-copies は fixpoint で long/short/command が展開
    InheritableInst => inst_inheritable(sb)
  }
}

///|
/// inheritable installer (DR-059): global の REVERSE 方向。子孫の inheritable 要素を全祖先 scope に
/// `<定義スコープ名>-<name>` 綴りでコピー (§1)。祖先の `--socket-ttl` が祖先 `ttl` cell に bind。
/// 全 `ttl` cell (定義 + 祖先コピー) に inherit seat が立つので、任意層の値が子孫の default として流れ下る
/// (§3 値意味論 — inherit seat の対 DR-031)。祖先が同トリガを自宣言なら shadow で copy しない (global 対称)。
fn inst_inheritable(sb : SB) -> Unit {
  // (1) 子孫の inheritable → THIS (祖先) scope の宣言層に prefixed write-entry を追加
  let entries : Array[(String, ElemDef)] = []
  gather_inheritable(sb.children, entries)
  for de in entries {
    let defining_name = de.0
    let e = de.1
    let trigger = defining_name + "-" + e.name // 全祖先同綴り (§1)
    add_inheritable_copy(sb, e, trigger)
  }
  // (2) subtree の inheritable 対象名 (自宣言 + 祖先コピー) 全てに inherit seat を打つ (§3)
  let names : Array[String] = []
  for e in sb.decl.options {
    if e.is_inheritable && !str_in(names, e.name) {
      names.push(e.name)
    }
  }
  for de in entries {
    if !str_in(names, de.1.name) {
      names.push(de.1.name)
    }
  }
  for name in names {
    seat_inherit(sb.build, name)
  }
}

///|
/// 子孫 scope の inheritable 要素を全て回収 (定義スコープ名で tag — §1 の prefix)。全 subtree を再帰。
fn gather_inheritable(
  children : Array[SBChild],
  out : Array[(String, ElemDef)],
) -> Unit {
  for ch in children {
    for e in ch.body.decl.options {
      if e.is_inheritable {
        out.push((ch.name, e))
      }
    }
    gather_inheritable(ch.body.children, out)
  }
}

///|
/// 祖先 scope の宣言層に prefixed write-entry を追加 (add-if-absent, shadow-aware)。祖先が同トリガを
/// 既に宣言 (§3 global 対称 shadow) なら copy しない。
fn add_inheritable_copy(sb : SB, e : ElemDef, trigger : String) -> Unit {
  for existing in sb.decl.options {
    if str_in(long_of(existing), trigger) {
      return // 自前優先 (shadow) / 既 copy (idempotent)
    }
  }
  sb.decl.options.push({
    name: e.name, // 祖先 write-target cell は要素名共有 (inherit-by-name)
    ty: e.ty,
    long: [trigger], // prefixed inheritable trigger (明示綴り)
    variants: [],
    short: [],
    env: [],
    is_dd: false,
    is_global: false,
    is_inherit: false, // inherit seat は inst_inheritable step(2) が立てる
    is_inheritable: false, // copy 自体は plain entry (再伝播しない)
    link_depth: 0,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple: false,
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
    default_value: None, // write-target に default を置かない (§3): 実書き込みのみが伝播する
  })
}

///|
/// constraint installer (DR-055 / DR-042 席宣言型): requires / conflicts_with / exclusive_group /
/// value_requires を scope の遅延述語として登録。構造衛星は無し (DR-047 完全 path の最終状態で評価)。
fn inst_constraint(def : Definition, build : Build) -> Unit {
  let all : Array[ElemDef] = []
  for e in def.options {
    all.push(e)
  }
  for e in def.positionals {
    all.push(e)
  }
  for e in all {
    if e.requires.length() > 0 {
      add_constraint(build, CRequires(e.name, copy_strs(e.requires)))
    }
    if e.conflicts_with.length() > 0 {
      add_constraint(build, CConflicts(e.name, copy_strs(e.conflicts_with)))
    }
    for vr in e.value_requires {
      add_constraint(build, CRequiresIf(e.name, vr.0, copy_strs(vr.1)))
    }
  }
  // exclusive_group: label per scope でメンバを集約 → 1 CExclusive per label
  let groups : Array[String] = []
  for e in all {
    for g in e.exclusive_group {
      if !str_in(groups, g) {
        groups.push(g)
      }
    }
  }
  for g in groups {
    let members : Array[String] = []
    for e in all {
      if str_in(e.exclusive_group, g) {
        members.push(e.name)
      }
    }
    add_constraint(build, CExclusive(g, members))
  }
}

///|
fn str_in(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

// ── alias desugaring (DR-057) ────────────────────────────────────────────────

///|
/// `s` に部分文字列 `sub` を含むか (name-derived variant 判定: variant.trigger が canonical.name を
/// 部分文字列に含むなら name-derived — DR-057 §3)。
fn str_has_sub(s : String, sub : String) -> Bool {
  if sub.length() == 0 {
    return true
  }
  let cs = to_chars(s)
  let cu = to_chars(sub)
  if cu.length() > cs.length() {
    return false
  }
  let mut i = 0
  while i + cu.length() <= cs.length() {
    let mut k = 0
    let mut ok = true
    while k < cu.length() {
      if cs[i + k] != cu[k] {
        ok = false
        break
      }
      k = k + 1
    }
    if ok {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// `s` の最初の `from` 出現を `to` に置換 (name-derived variant を alias 名で再導出: DR-057 §3
/// "--no-ssl" (canonical ssl) → alias tls で "--no-tls")。
fn str_replace_first(s : String, from : String, to : String) -> String {
  let cs = to_chars(s)
  let cf = to_chars(from)
  if cf.length() == 0 || cf.length() > cs.length() {
    return s
  }
  let mut i = 0
  while i + cf.length() <= cs.length() {
    let mut k = 0
    let mut ok = true
    while k < cf.length() {
      if cs[i + k] != cf[k] {
        ok = false
        break
      }
      k = k + 1
    }
    if ok {
      let buf = StringBuilder::new()
      buf.write_string(chars_to_str(cs, 0, i))
      buf.write_string(to)
      buf.write_string(chars_to_str(cs, i + cf.length(), cs.length()))
      return buf.to_string()
    }
    i = i + 1
  }
  s
}

///|
/// canonical option / positional 要素を name で検索。
fn find_elem(def : Definition, name : String) -> ElemDef? {
  for e in def.options {
    if e.name == name {
      return Some(e)
    }
  }
  for e in def.positionals {
    if e.name == name {
      return Some(e)
    }
  }
  None
}

///|
fn find_command(def : Definition, name : String) -> CommandDef? {
  for c in def.commands {
    if c.name == name {
      return Some(c)
    }
  }
  None
}

///|
/// alias entry-copy の空 body: entry 綴り + canonical name のみ携行、値源 / 結果キー / 制約は実体側の
/// まま (DR-057 §3)、それら field は set しない。
fn alias_entry(
  canonical_name : String,
  ty : Ty,
  long : Array[String],
  variants : Array[Variant],
  short : Array[Char],
  deprecated : Bool,
) -> ElemDef {
  {
    name: canonical_name, // effect / entity / result key は全て canonical name で keying (link 同型)
    ty,
    long, // 既に導出済み explicit 綴り列 (`:set` は含まない — normalize の対象外)
    variants,
    short,
    env: [],
    is_dd: false,
    is_global: false,
    is_inherit: false,
    is_inheritable: false,
    link_depth: 0,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple: false,
    separator: None,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    value_requires: [],
    deprecated,
    default_value: None,
  }
}

///|
/// alias 宣言 (DR-057) を option entry-copies / command defs に desugar。完全性検査が AliasInst の
/// "alias" 所有を確認した後、init_sb 前に 1 度だけ走る決定的 pre-pass。各 entry-copy は canonical name
/// で keying (satellites が canonical cell を bind、結果キーも canonical)、再導出綴りを携行し、fixpoint
/// の long/short/command installer が展開する (DR-057 §4)。command subtree にも再帰。
fn desugar_aliases(def : Definition) -> Unit {
  for a in def.aliases {
    let alias_name = match a.name {
      Some(n) => n
      None => a.target // 明示 name 無し → canonical 名を流用 (e.g. short-only alias)
    }
    match find_elem(def, a.target) {
      Some(canon) => {
        // 基底 long 綴り: name-derived (§3 / DESIGN §14.5)。canonical が name-derived を持つ
        // (long 配列に自 name を含む) 時のみ、alias 名で再導出。
        let long : Array[String] = []
        if str_in(long_of(canon), canon.name) {
          long.push(alias_name)
        }
        // 明示 `long` override (DR-007 差分上書き) は自綴りを add、継承 variants を cut。
        let variants : Array[Variant] = []
        match a.long_override {
          Some(extra) =>
            for l in extra {
              if !str_in(long, l) {
                long.push(l)
              }
            }
          None =>
            // canonical の NAME-DERIVED variants を alias 名で再導出。variant.trigger が canonical.name
            // を部分文字列に含めば name-derived (DR-057 §3); 明示 trigger (e.g. compress の "gzip") は
            // 非継承 (明示綴り非継承)。
            for v in canon.variants {
              if str_has_sub(v.trigger, canon.name) {
                variants.push({
                  trigger: str_replace_first(v.trigger, canon.name, alias_name),
                  op: v.op,
                  operand: v.operand,
                })
              }
            }
        }
        def.options.push(
          alias_entry(
            canon.name,
            canon.ty,
            long,
            variants,
            copy_chars(a.short),
            a.deprecated,
          ),
        )
      }
      None =>
        // command alias: co → checkout 部分木, 結果キーは checkout に寄せる (DR-057 §2)
        match find_command(def, a.target) {
          Some(cmd) =>
            def.commands.push({
              name: alias_name,
              body: clone_def(cmd.body),
              export_key: EkKey(a.target),
            })
          None => () // dangling alias target — 将来の absent-ref check 用に残置
        }
    }
  }
  for c in def.commands {
    desugar_aliases(c.body)
  }
}

///|
fn add_constraint(build : Build, c : Constraint) -> Unit {
  for existing in build.constraints {
    if existing == c {
      return
    }
  }
  build.constraints.push(c)
}

///|
/// 全木 1 pass の fixpoint: entities ensure (core) → installer 適用 → 子 scope 再帰。global は再帰前に
/// 子にコピーするので、`order` 内の global 位置に関わらず子は同 pass で成長した宣言層を見る。
fn tree_pass(order : Array[Installer], sb : SB, has_cf : Bool) -> Unit {
  ensure_entities(sb, has_cf)
  for inst in order {
    apply_node(inst, sb)
  }
  for child in sb.children {
    tree_pass(order, child.body, has_cf)
  }
}

///|
fn def_err(
  element : String,
  kind : DefErrKind,
  message : String,
  hint : String,
) -> DefError {
  { element, kind, message, hint }
}

///|
/// invariant ③ (DR-054): 2 installer が同 vocab を所有。全 intersection を収集。
fn collect_vocab_intersection(
  order : Array[Installer],
  out : Array[DefError],
) -> Unit {
  let seen : Array[String] = []
  for inst in order {
    let v = owned_vocab(inst)
    for s in seen {
      if s == v {
        out.push(
          def_err(
            v,
            DVocabIntersection,
            "vocab '\{v}' is claimed by two installers",
            "remove the duplicate installer owning '\{v}' from the chain",
          ),
        )
      }
    }
    seen.push(v)
  }
}

///|
/// invariant ①' completeness (DR-054): 木で使われているが chain のどの installer にも所有されない
/// special vocab は Error。全 (element ごと + commands) 収集。
fn collect_unknown_vocab(
  def : Definition,
  order : Array[Installer],
  out : Array[DefError],
) -> Unit {
  let owned : Array[String] = []
  for inst in order {
    owned.push(owned_vocab(inst))
  }
  scan_unknown(def, owned, out)
}

///|
fn scan_unknown(
  def : Definition,
  owned : Array[String],
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    push_elem_unknown(e, owned, out)
  }
  for e in def.positionals {
    push_elem_unknown(e, owned, out)
  }
  if def.commands.length() > 0 && !vocab_owned(owned, "command") {
    out.push(
      def_err(
        "(commands)",
        DUnknownVocab,
        "unknown special vocab 'command'",
        "add CommandInst to the installer chain",
      ),
    )
  }
  // alias vocab (DR-057): scope-level (aliases は per-ElemDef ではない)、commands と対称形。
  if def.aliases.length() > 0 && !vocab_owned(owned, "alias") {
    out.push(
      def_err(
        "(aliases)",
        DUnknownVocab,
        "unknown special vocab 'alias'",
        "add AliasInst to the installer chain",
      ),
    )
  }
  for c in def.commands {
    scan_unknown(c.body, owned, out)
  }
}

///|
fn push_elem_unknown(
  e : ElemDef,
  owned : Array[String],
  out : Array[DefError],
) -> Unit {
  match scan_elem_vocab(e, owned) {
    Some(v) =>
      out.push(
        def_err(
          e.name,
          DUnknownVocab,
          "unknown special vocab '\{v}' — no installer claimed it",
          "register an installer owning '\{v}' in the chain (§13.5)",
        ),
      )
    None => ()
  }
}

///|
fn vocab_owned(owned : Array[String], v : String) -> Bool {
  for o in owned {
    if o == v {
      return true
    }
  }
  false
}

///|
fn scan_elem_vocab(e : ElemDef, owned : Array[String]) -> String? {
  if long_of(e).length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:" + long_of(e)[0])
  }
  // variant DSL は long 属性の値語彙 (DR-042 §所有権の粒度) — long installer が所有。
  if e.variants.length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:variant:" + e.variants[0].trigger)
  }
  if e.short.length() > 0 && !vocab_owned(owned, "short") {
    return Some("short")
  }
  if e.env.length() > 0 && !vocab_owned(owned, "env") {
    return Some("env:" + e.env[0])
  }
  if e.is_dd && !vocab_owned(owned, "dd") {
    return Some("dd")
  }
  if e.is_global && !vocab_owned(owned, "global") {
    return Some("global")
  }
  if e.is_inherit && !vocab_owned(owned, "inherit") {
    return Some("inherit")
  }
  if e.is_inheritable && !vocab_owned(owned, "inheritable") {
    return Some("inheritable")
  }
  // repeat と optional 糖衣 (DR-043) は repeat installer 所有。
  match elem_repeat(e) {
    Some(_) => if !vocab_owned(owned, "repeat") { return Some("repeat") }
    None => ()
  }
  if e.multiple && !vocab_owned(owned, "multiple") {
    return Some("multiple")
  }
  // config vocab (DR-050): type:"config_file" と config_key 両方 config installer 所有。
  if e.is_config_file && !vocab_owned(owned, "config") {
    return Some("config:config_file")
  }
  match e.config_key {
    Some(_) =>
      if !vocab_owned(owned, "config") {
        return Some("config:config_key")
      }
    None => ()
  }
  // constraint vocab (DR-055)
  if e.requires.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:requires")
  }
  if e.conflicts_with.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:conflicts_with")
  }
  if e.exclusive_group.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:exclusive_group")
  }
  if e.value_requires.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:value_requires")
  }
  None
}

///|
/// zero-progress 静的 guard (DR-043): repeat head は >= 1 token 消費が必要 (再帰 unfold の loop を防止)。
/// ref head は「target が >= 1 消費」に還元 (消費 node のない ref cycle も捕捉)。
fn head_progresses(
  node : Node,
  registry : Map[String, Node],
  visiting : Array[String],
) -> Bool {
  match node {
    StrArg(_)
    | SepArg(_, _)
    | NumArg(_)
    | FilterArg(_, _)
    | ReqArg(_)
    | Exact(_)
    | NativeMatch(_)
    | DdSat(_)
    | CmdSat(_, _) => true
    NoDashStr(_) => true // dash-reject でなければ 1 token 消費
    IdxRepeat(_, _, _) => true // 名前付き indexed repeat は head を消費
    BoundedTail(_, budget, _) => budget >= 1 // >= 1 head 取れる時のみ消費
    Rooted(inner, _) => head_progresses(inner, registry, visiting)
    Bind(_, _) => false // 0-token
    EffMark(_, _) => false // 0-token effect (DR-045)
    FailMark(_) => false // 0-token failure-action (DR-048)
    DeprMark(_) => false // 0-token deprecation (DR-058)
    Ref(r) => {
      for v in visiting {
        if v == r {
          return false // 消費 node なしの cycle → 無 progress
        }
      }
      match registry.get(r) {
        Some(tpl) => {
          visiting.push(r)
          let ok = head_progresses(tpl, registry, visiting)
          let _ = visiting.pop()
          ok
        }
        None => false // unresolved ref
      }
    }
    Or(alts) => {
      for a in alts {
        if !head_progresses(a, registry, visiting) {
          return false
        }
      }
      alts.length() > 0
    }
    Seq(items) =>
      if items.length() >= 1 {
        head_progresses(items[0], registry, visiting)
      } else {
        false
      }
    Many(_) | Scoped(_, _) | ScopeNode(_) => true
  }
}

///|
/// HEAD position の ref (最初に消費される要素の ref), 無ければ None。消費 head の後の ref (repeat の
/// cons tail `Seq([head, Opt(Ref(self))])` 等) は head 位置ではないので、正当な repeat 自参照は None を返す。
fn head_ref_of(node : Node) -> String? {
  match node {
    Ref(r) => Some(r)
    Seq(items) => if items.length() >= 1 { head_ref_of(items[0]) } else { None }
    Or(alts) => {
      for a in alts {
        match head_ref_of(a) {
          Some(r) => return Some(r)
          None => ()
        }
      }
      None
    }
    Rooted(inner, _) => head_ref_of(inner)
    _ => None
  }
}

///|
/// `name` から head-position ref を辿ると loop するか (無限構造展開の circular ref, DR-054)。repeat
/// 自参照 (head が消費 node) はここで loop しない。
fn head_cycles(
  name : String,
  registry : Map[String, Node],
  visiting : Array[String],
) -> Bool {
  for v in visiting {
    if v == name {
      return true
    }
  }
  match registry.get(name) {
    Some(tpl) =>
      match head_ref_of(tpl) {
        Some(next) => {
          visiting.push(name)
          let r = head_cycles(next, registry, visiting)
          let _ = visiting.pop()
          r
        }
        None => false
      }
    None => false
  }
}

///|
/// node の head-position ref が cycle に到達するか (circular ref が同時に zero-progress として 2 重
/// 報告されないよう区別する用途)。
fn head_node_cycles(node : Node, registry : Map[String, Node]) -> Bool {
  match head_ref_of(node) {
    Some(r) => head_cycles(r, registry, [])
    None => false
  }
}

///|
/// zero-progress guard (DR-043 / DR-054): repeat head は >= 1 消費が必要。全件収集 — ただし ref
/// cycle による 非 progress は circular ref (collect_circular_ref) 側で報告するので、ここでは除外する
/// (kind を distinct に保つ)。
fn collect_zero_progress(
  def : Definition,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for e in def.positionals {
    match elem_repeat(e) {
      Some(_) => {
        let head = elem_head(e)
        if !head_progresses(head, registry, []) &&
          !head_node_cycles(head, registry) {
          out.push(
            def_err(
              e.name,
              DZeroProgress,
              "repeat element '\{e.name}' has a zero-progress head",
              "give the repeat head a token-consuming element",
            ),
          )
        }
      }
      None => ()
    }
  }
  for c in def.commands {
    collect_zero_progress(c.body, registry, out)
  }
}

///|
/// circular ref (DR-054): registry template の head-position ref chain が loop → 無限構造展開。
/// repeat 由来の自参照は pass (head が消費 node)。全件収集。
fn collect_circular_ref(
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for name, _ in registry {
    // repeat installer 登録の lazy-marker key ("lazy:<name>") はスキップ。
    if name.length() >= 5 && name[0:5] == "lazy:" {
      continue
    }
    if head_cycles(name, registry, []) {
      out.push(
        def_err(
          name,
          DCircularRef,
          "ref template '\{name}' is circular (infinite structural expansion)",
          "break the ref cycle or add a token-consuming head before the self-reference",
        ),
      )
    }
  }
}

///|
/// absent ref (DR-054 / DR-032): 要素 ref_target の解決先が無い (init_sb の repeat lowering + 事前
/// 登録済み template を含む registry で check)。全件収集。
fn collect_absent_ref(
  def : Definition,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    check_elem_absent_ref(e, registry, out)
  }
  for e in def.positionals {
    check_elem_absent_ref(e, registry, out)
  }
  for c in def.commands {
    collect_absent_ref(c.body, registry, out)
  }
}

///|
fn check_elem_absent_ref(
  e : ElemDef,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  match e.ref_target {
    Some(r) =>
      match registry.get(r) {
        Some(_) => ()
        None =>
          out.push(
            def_err(
              e.name,
              DAbsentRef,
              "ref target '\{r}' is not defined in scope or definitions",
              "define '\{r}' as a template (definitions) or in the scope",
            ),
          )
      }
    None => ()
  }
}

///|
/// invalid value range (DR-054 / DR-052): repeat min > max。全件収集。
fn collect_invalid_range(def : Definition, out : Array[DefError]) -> Unit {
  for e in def.positionals {
    match e.repeat {
      Some(spec) =>
        match spec.max {
          Some(mx) =>
            if spec.min > mx {
              out.push(
                def_err(
                  e.name,
                  DInvalidRange,
                  "repeat min \{spec.min} > max \{mx}",
                  "set the repeat max >= min",
                ),
              )
            }
          None => ()
        }
      None => ()
    }
  }
  for c in def.commands {
    collect_invalid_range(c.body, out)
  }
}

///|
/// 木のどこかに `type:"config_file"` 要素があるか (DR-050): あれば同型 config seat が全 value cell に立つ。
fn has_config_file(def : Definition) -> Bool {
  for e in def.options {
    if e.is_config_file {
      return true
    }
  }
  for e in def.positionals {
    if e.is_config_file {
      return true
    }
  }
  for c in def.commands {
    if has_config_file(c.body) {
      return true
    }
  }
  false
}

///|
/// config cycle (DR-050 §5 / DR-054): config_file 要素は config_key を持てない (自 path を config から
/// 引く循環)。全件収集。
fn collect_config_cycle(def : Definition, out : Array[DefError]) -> Unit {
  for e in def.options {
    if e.is_config_file && e.config_key is Some(_) {
      out.push(
        def_err(
          e.name,
          DConfigCycle,
          "config_file element '\{e.name}' cannot have a config_key (循環禁止)",
          "remove config_key from the config_file element",
        ),
      )
    }
  }
  for e in def.positionals {
    if e.is_config_file && e.config_key is Some(_) {
      out.push(
        def_err(
          e.name,
          DConfigCycle,
          "config_file element '\{e.name}' cannot have a config_key (循環禁止)",
          "remove config_key from the config_file element",
        ),
      )
    }
  }
  for c in def.commands {
    collect_config_cycle(c.body, out)
  }
}

///|
/// 1 scope 分の build 層の stable signature (fixpoint 検出用)。全て add-if-absent (monotonic 成長) で
/// 増えるので、build 層 (greedy / entities / positional / constraints) と宣言層 (decl.options) の要素数
/// 合計を Int で持てば十分。seat_env / seat_inherit は Entity 追加後に同 pass の apply_node で 1 回だけ
/// set され (idempotent)、以後の pass では既 set の値を上書きするだけなので、count-based sig で不動点に達する。
/// 注意: Node / Entity は Debug 派生のみで Show を持たないため、String 合成による sig は使えない (installer.mbt
/// から node.mbt を触らない制約下での回避策 — count-based で monotonic 成長を捕捉する)。
fn build_size(b : Build) -> Int {
  b.greedy.length() + b.entities.length() + b.constraints.length()
}

///|
fn tree_size(sb : SB) -> Int {
  let mut n = build_size(sb.build) + sb.decl.options.length()
  for child in sb.children {
    n = n + tree_size(child.body)
  }
  n
}

///|
/// scope-builder tree を Scope tree に materialize。subcommand は greedy `CmdSat(name, child)` に
/// (greedy-face resident; 排他 trigger が先食いで守り DR-018 priority、子は新 backbone DR-041 §4、fire
/// で親を sever)。
fn materialize(sb : SB) -> Scope {
  let greedy : Array[Node] = []
  for g in sb.build.greedy {
    greedy.push(g)
  }
  for child in sb.children {
    let cs = materialize(child.body)
    greedy.push(CmdSat(child.name, cs))
  }
  {
    greedy,
    positional: sb.build.positional,
    entities: sb.build.entities,
    constraints: sb.build.constraints,
  }
}

///|
/// UsefulAST → AtomicAST を installer chain として遂行 (DR-042)。`order` は適用 installer 列、5
/// invariants により結果は順序無依存。
///
/// chain は木全体で FIXPOINT まで回る (global が置いた宣言を後段 pass で long が展開する等の
/// inter-installer 依存を repeat で解決)。termination: add-if-absent と finite element×scope 空間
/// (copy of copy は name 同一で add-if-absent 止まる) により build 層が monotonically 成長し、変化なし
/// pass = fixpoint。
///
/// Returns Ok(atomic scope) or Err(全 definition-time errors)。static check は全て走って 1 list に append
/// (打ち切りなし)。各 DefError は {element, kind, message, hint} を持つ。
pub fn parse_definition(
  def0 : Definition,
  order : Array[Installer],
  registry? : Map[String, Node] = Map([], capacity=0),
) -> Result[Scope, Array[DefError]] {
  let def = clone_def(def0)
  // 純構文 pre-pass (LOWERING §A / §C.4): `:set` → kebab (Fix 2, DR-071) + dd name 既定 "--" (Fix 3, DR-064 §5)
  normalize_surface(def)
  // init_sb が registry に repeat-lowering template を植える (静的 ref check が見えるように)。
  // alias entry-copies は ref/repeat を持たず、command alias は check 済 body を clone するので、
  // static check は pre-desugar def で回す (この 1 本目の tree は registry 植え込みのみが目的)。
  let _ = init_sb(def, registry)
  let errs : Array[DefError] = []
  collect_vocab_intersection(order, errs) // DR-042③
  collect_unknown_vocab(def, order, errs) // DR-042① (alias vocab check 込み)
  collect_invalid_range(def, errs) // DR-052 (repeat min > max)
  collect_absent_ref(def, registry, errs) // DR-032
  collect_circular_ref(registry, errs) // DR-007/032
  collect_zero_progress(def, registry, errs) // DR-043
  collect_config_cycle(def, errs) // DR-050 §5
  if errs.length() > 0 {
    return Err(errs) // ALL definition-error 列挙
  }
  // alias 宣言 desugar (DR-057): 完全性検査 pass 後、決定的 pre-pass。option entry-copies /
  // command defs を追加 — fixpoint installer が展開する。
  desugar_aliases(def)
  let sb = init_sb(def, registry) // desugar 済 def で scope tree 再構築
  // 同型 default (DR-050 §3): config_file 要素があれば全 value cell に config seat を宣言。1 度計算、
  // ensure_entity に thread。
  let has_cf = has_config_file(def)
  let mut iters = 0
  while true {
    let prev = tree_size(sb)
    tree_pass(order, sb, has_cf)
    if tree_size(sb) == prev {
      break
    }
    iters = iters + 1
    if iters > 100 {
      return Err([
        def_err(
          "(chain)",
          DUnknownVocab,
          "installer chain did not converge (> 100 iterations)",
          "check for a runaway global copy or a mis-registered installer",
        ),
      ])
    }
  }
  Ok(materialize(sb))
}
