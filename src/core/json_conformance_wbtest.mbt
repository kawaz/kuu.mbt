// json_conformance_wbtest.mbt — JSON-DIRECT conformance runner (query: "parse" + "lower").
//
// PORTED FROM: kawaz/kuu.mbt slice/poc/{json_conformance_wbtest,lower_runner_wbtest,helpers_wbtest,
// fixture_runner_wbtest}.mbt — verbatim structure with API adaptations for main src/core:
//   - ParseError is a 6-tuple (element/argv_pos/kind/reason/message/path, DR-066 §3/§4): proj_errors
//     and exp_errors_decode include `reason` when the fixture asserts it on ANY error in the set, and
//     `path` likewise on its own independent opt-in (per-field, per-fixture-set — DR-066 §4/§5:
//     message is never compared, reason/path are each optional and asserted independently).
//   - resolve_scope / resolve_scope_config return `Result[Array[Binding], ParseError]` in main
//     (slice returned Result[..., String] for the config variant and Array[Binding] for the flat
//     variant). Both sites in resolve_tree/do_resolve wrap the ParseError message.
//   - env_value in main takes (element, ty, s, at_pos)->Result; the variant-DSL operand still needs
//     the naive slice-form coercion → local `dsl_variant_value` helper.
//
// The two-ledger contract (expected_skips / known_divergences) starts EMPTY per MDR-001 §6: fixtures
// are re-fed against the new implementation, and every observed skip / divergence is reported by the
// test so we can classify them off-line. Empty ledger + failing test = the fixture-first mode.

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1 — Local helpers (mirror slice/poc/helpers_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

// ── deprecated-free Json accessors (moon nightly: as_* 系は deprecated) ───────

///|
fn Json::j_obj(self : Json) -> Map[String, Json]? {
  if self is Object(m) {
    Some(m)
  } else {
    None
  }
}

///|
fn Json::j_arr(self : Json) -> Array[Json]? {
  if self is Array(a) {
    Some(a)
  } else {
    None
  }
}

///|
fn Json::j_str(self : Json) -> String? {
  if self is String(x) {
    Some(x)
  } else {
    None
  }
}

///|
fn Json::j_bool(self : Json) -> Bool? {
  if self is True {
    Some(true)
  } else if self is False {
    Some(false)
  } else {
    None
  }
}

///|
fn Json::j_num(self : Json) -> Double? {
  if self is Number(n, ..) {
    Some(n)
  } else {
    None
  }
}

///|
/// Deterministic codepoint ordering (MoonBit's builtin sorts by length first).
fn str_less(a : String, b : String) -> Bool {
  let ca = to_chars(a)
  let cb = to_chars(b)
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  let mut i = 0
  while i < n {
    let x = ca[i].to_int()
    let y = cb[i].to_int()
    if x < y {
      return true
    }
    if x > y {
      return false
    }
    i = i + 1
  }
  ca.length() < cb.length()
}

///|
fn sort_items(arr : Array[String]) -> Unit {
  let mut i = 1
  while i < arr.length() {
    let key = arr[i]
    let mut j = i - 1
    while j >= 0 && str_less(key, arr[j]) {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
    i = i + 1
  }
}

///|
fn join_comma(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in items {
    if !first {
      buf.write_string(",")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

///|
fn join_pipe(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in items {
    if !first {
      buf.write_string("|")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

///|
fn str_has_prefix(s : String, pre : String) -> Bool {
  let cs = to_chars(s)
  let cp = to_chars(pre)
  if cp.length() > cs.length() {
    return false
  }
  let mut i = 0
  while i < cp.length() {
    if cs[i] != cp[i] {
      return false
    }
    i = i + 1
  }
  true
}

// ── render helpers ────────────────────────────────────────────────────────────

///|
fn render_val(v : Value) -> String {
  match v {
    VStr(s) => s
    VBool(b) => if b { "true" } else { "false" }
    VNum(d) => {
      let i = d.to_int()
      if i.to_double() == d {
        i.to_string()
      } else {
        d.to_string()
      }
    }
  }
}

///|
fn render_src(s : Source) -> String {
  match s {
    Cli => "cli"
    Env => "env"
    Config => "config"
    Inherit => "inherit"
    Default => "default"
  }
}

///|
fn render_kind(k : ErrKind) -> String {
  match k {
    KParse => "parse"
    KFilter => "filter"
    KConstraint => "constraint"
  }
}

///|
fn render_def_kind(k : DefErrKind) -> String {
  match k {
    DVocabIntersection => "vocab-intersection"
    DUnknownVocab => "unknown-vocab"
    DInvalidRange => "invalid-range"
    DAbsentRef => "absent-ref"
    DCircularRef => "circular-ref"
    DZeroProgress => "zero-progress"
    DConfigCycle => "config-cycle"
    DInvalidArgument => "invalid-argument"
  }
}

///|
fn deferrs_str(errs : Array[DefError]) -> String {
  let items : Array[String] = []
  for e in errs {
    items.push("\{e.element}/\{render_def_kind(e.kind)}")
  }
  sort_items(items)
  join_comma(items)
}

///|
/// Compact one-line rendering of an Outcome for the runner's "EXPECTED-* got=" diagnostics.
fn render_outcome(o : Outcome) -> String {
  match o {
    Success(binds) => "ok{" + render_binds_result(binds) + "}"
    Failure(d) =>
      match d.fired_action {
        Some(n) => "action:" + n
        None =>
          if d.errors.length() > 0 {
            "fail:" + primary_message(d.errors)
          } else {
            "fail:no complete parse"
          }
      }
    Ambiguous(d) => "ambiguous:" + d.interpretations.length().to_string()
  }
}

///|
fn primary_message(errors : Array[ParseError]) -> String {
  let mut best = errors[0]
  for e in errors {
    if e.argv_pos > best.argv_pos {
      best = e
    }
  }
  best.message
}

///|
/// Result-side binding renderer for render_outcome ("ok{k=v,…}"). Skips markers.
fn render_binds_result(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if !is_sentinel(b.key) {
      items.push("\{b.key}=\{render_val(b.value)}")
    }
  }
  sort_items(items)
  join_comma(items)
}

// ── generic set-membership helper for arrays of strings ────────────────────────

///|
fn conformance_str_in(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

// ── EffectOp / ExportKey helpers ──────────────────────────────────────────────

///|
fn eff_op(op : EffectOp) -> String {
  match op {
    Set => "set"
    Default => "default"
    Unset => "unset"
    Empty => "empty"
    // DR-077 §1 (5th op): the transform name rides along so two DIFFERENT update transforms (e.g.
    // "increment" vs a future "add") render distinctly. Args are appended ONLY when non-empty
    // (mirrors DR-077 §2's colon-DSL nesting, `:update:add:5`) so the 0-arg `increment` case reads
    // as plain "update:increment", not "update:increment:" with a dangling separator.
    Update(transform, args) =>
      if args.length() == 0 {
        "update:" + transform
      } else {
        "update:" + transform + ":" + join_comma(args)
      }
    // DR-080 §2 merge accumulator piece markers — fixture (merge-basic.json 等) の effects oracle
    // が pin する op 名そのもの ("set" は既存の add piece 表示と同じ、remove/splice がこの2値)。
    Remove => "remove"
    Splice => "splice"
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2 — Builders (mirror slice helpers: opt/pos/dd_marker/cmd/alias/rep/def_)
// ═══════════════════════════════════════════════════════════════════════════════

///|
fn opt(
  name : String,
  ty : Ty,
  long? : LongDecl = LList([]),
  variants? : Array[Variant] = [],
  short? : Array[Char] = [],
  env? : Array[String] = [],
  global? : Bool = false,
  inherit_? : Bool = false,
  inheritable? : Bool = false,
  repeat? : RepeatSpec? = None,
  multiple? : Bool = false,
  accumulator? : String? = None,
  collector? : String? = None,
  fail_action? : Bool = false,
  config_file? : Bool = false,
  config_key? : Array[String]? = None,
  export_? : ExportKey = EkUnset,
  requires? : Array[String] = [],
  conflicts? : Array[String] = [],
  exclusive? : Array[String] = [],
  required? : Bool = false,
  value_requires? : Array[(String, String, Array[String])] = [],
  default? : Array[Value]? = None,
  int_round? : RoundMode = RError,
  allow_base_prefix? : Bool = false,
  bool_config? : BoolConfig = bool_config_canonical(),
  piece_filters? : Array[FilterSpelling] = [],
  value_filters? : Array[FilterSpelling] = [],
  cell_filters? : Array[FilterSpelling] = [],
  ref_? : String? = None,
  long_prefix? : String = "--",
  short_prefix? : String = "-",
  env_prefix? : String = "",
  auto_env? : Bool = false,
  allow_equal_separator? : Bool = true,
  short_combine? : Bool = true,
  require_equal_separator? : Bool = false,
  body? : ElemBody = BCell,
) -> ElemDef {
  {
    name,
    ty,
    long,
    variants,
    short,
    env,
    is_dd: false,
    dd_match: None,
    dd_self_keep: false,
    is_global: global,
    is_inherit: inherit_,
    is_inheritable: inheritable,
    link_depth: 0,
    ref_target: ref_,
    repeat,
    optional: false,
    multiple,
    accumulator,
    separator: None,
    collector,
    fail_action,
    is_config_file: config_file,
    config_key,
    export_key: export_,
    requires,
    conflicts_with: conflicts,
    exclusive_group: exclusive,
    required,
    value_requires,
    deprecated: false,
    default_values: default,
    int_round,
    allow_base_prefix,
    bool_config,
    piece_filters,
    value_filters,
    cell_filters,
    long_prefix,
    short_prefix,
    env_prefix,
    auto_env,
    allow_equal_separator,
    short_combine,
    require_equal_separator,
    body,
  }
}

///|
fn pos(
  name : String,
  ty : Ty,
  inherit_? : Bool = false,
  repeat? : RepeatSpec? = None,
  optional? : Bool = false,
  multiple? : Bool = false,
  accumulator? : String? = None,
  separator? : String? = None,
  collector? : String? = None,
  config_key? : Array[String]? = None,
  export_? : ExportKey = EkUnset,
  ref_? : String? = None,
  default? : Array[Value]? = None,
  int_round? : RoundMode = RError,
  allow_base_prefix? : Bool = false,
  bool_config? : BoolConfig = bool_config_canonical(),
  piece_filters? : Array[FilterSpelling] = [],
  value_filters? : Array[FilterSpelling] = [],
  cell_filters? : Array[FilterSpelling] = [],
  env? : Array[String] = [],
  required? : Bool = false,
  requires? : Array[String] = [],
  body? : ElemBody = BCell,
) -> ElemDef {
  {
    name,
    ty,
    long: LList([]),
    variants: [],
    short: [],
    env,
    is_dd: false,
    dd_match: None,
    dd_self_keep: false,
    is_global: false,
    is_inherit: inherit_,
    is_inheritable: false,
    link_depth: 0,
    ref_target: ref_,
    repeat,
    optional,
    multiple,
    accumulator,
    separator,
    collector,
    fail_action: false,
    is_config_file: false,
    config_key,
    export_key: export_,
    requires,
    conflicts_with: [],
    exclusive_group: [],
    required,
    value_requires: [],
    deprecated: false,
    default_values: default,
    int_round,
    allow_base_prefix,
    bool_config,
    piece_filters,
    value_filters,
    cell_filters,
    // positional 要素は long/short spelling を持たない (`long: LList([])`/`short: []` 上、`long_of`
    // は常に [] を返す) — `long_prefix`/`short_prefix`/`allow_equal_separator`/`short_combine`/
    // `require_equal_separator` は long/short-only 語彙なので既定値のまま未使用フィールドとして持ち
    // 回るだけ (`opt`/`inst_long`/`inst_short` 側の実際の消費経路と同じ理由付け)。`env_prefix`/
    // `auto_env` は env 席が positional にも効く (`inst_env` が def.positionals も走査) ため、
    // `dec_definition` が呼び出し側でこの2つだけ scope config を焼き込む (下記コメント参照)。
    long_prefix: "--",
    short_prefix: "-",
    env_prefix: "",
    auto_env: false,
    allow_equal_separator: true,
    short_combine: true,
    require_equal_separator: false,
    body,
  }
}

///|
fn dd_marker(
  match_? : String? = None,
  self_keep? : Bool = false,
  required? : Bool = false,
) -> ElemDef {
  {
    name: "--",
    ty: TStr,
    long: LList([]),
    variants: [],
    short: [],
    env: [],
    is_dd: true,
    dd_match: match_,
    dd_self_keep: self_keep,
    is_global: false,
    is_inherit: false,
    is_inheritable: false,
    link_depth: 0,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple: false,
    accumulator: None,
    separator: None,
    collector: None,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    required,
    value_requires: [],
    deprecated: false,
    default_values: None,
    int_round: RError,
    allow_base_prefix: false,
    bool_config: bool_config_canonical(),
    piece_filters: [],
    value_filters: [],
    cell_filters: [],
    // dd marker element も `long: LList([])` で long spelling を持たない — 同じ理由で既定値。
    long_prefix: "--",
    short_prefix: "-",
    env_prefix: "",
    auto_env: false,
    allow_equal_separator: true,
    short_combine: true,
    require_equal_separator: false,
    body: BCell,
  }
}

///|
/// Canonical full installer chain (DR-042 §canonical set + DR-043/050/055/057/059).
fn full_installers() -> Array[Installer] {
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

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — LSec 5-face 断面 model + renderers + projectors (mirrors slice/poc/lower_runner_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

///|
struct LEnt {
  name : String
  typ : String
  default_ : Value?
  env : String?
  inherit_ : Bool
  config_key : Array[String]?
  accum : String?
}

///|
enum GItem {
  GExact(String)
  GSet(String, Value, String)
  GEff(String, String, EffectOp)
  GSeqSat(String, String)
  GMatch(String, Array[(String, String)])
  GCmd(String, LSec)
}

///|
enum TNode {
  TSeq(Array[TNode])
  TRefEnt(String)
  TRefTmpl(String, Bool)
  TExact(String)
}

///|
struct LSec {
  greedy : Array[GItem]
  positionals : Array[TNode]
  entities : Array[LEnt]
  constraints : Array[Constraint]
  templates : Array[(String, TNode)]
}

///|
fn canon_tmpl(k : String) -> String {
  let buf = StringBuilder::new()
  for c in k {
    if c == '#' {
      break
    }
    buf.write_char(c)
  }
  buf.to_string() + "#T"
}

///|
fn lent_str(e : LEnt) -> String {
  let fs : Array[String] = ["type=" + e.typ]
  match e.default_ {
    Some(v) => fs.push("default=" + render_val(v))
    None => ()
  }
  match e.env {
    Some(k) => fs.push("env=" + k)
    None => ()
  }
  if e.inherit_ {
    fs.push("inherit_=true")
  }
  match e.config_key {
    Some(p) => fs.push("config_key=[" + join_comma(p) + "]")
    None => ()
  }
  match e.accum {
    Some(a) => fs.push("accumulator=" + a)
    None => ()
  }
  sort_items(fs)
  e.name + "{" + join_comma(fs) + "}"
}

///|
fn lcon_str(c : Constraint) -> String {
  fn sorted(xs : Array[String]) -> String {
    let ss : Array[String] = []
    for x in xs {
      ss.push(x)
    }
    sort_items(ss)
    join_comma(ss)
  }

  match c {
    CRequires(el, ts) =>
      "requires{element=" + el + ",targets=[" + sorted(ts) + "]}"
    CConflicts(el, ts) =>
      "conflicts_with{element=" + el + ",targets=[" + sorted(ts) + "]}"
    CRequiresIf(entity, branch_id, v, ts) =>
      // DR-055 §1 + DR-052 §値枝 id 直交: entity は committed 判定対象、branch_id は違反時 element。
      // 断面には両方 emit する (entity と branch_id が別ならその非対称が読める; id なしの parent 直属
      // 値依存 requires では entity == branch_id となり冗長だが projection は fixture 側と対称に保つ)。
      "requires_if{entity=" +
      entity +
      ",element=" +
      branch_id +
      ",value=" +
      v +
      ",targets=[" +
      sorted(ts) +
      "]}"
    CExclusive(g, ms) =>
      "exclusive_group{group=" + g + ",members=[" + sorted(ms) + "]}"
    CRequired(el) => "required{element=" + el + "}"
  }
}

///|
fn gmatch_entries_str(entries : Array[(String, String)]) -> String {
  let keys : Array[String] = []
  let vals : Array[String] = []
  for kv in entries {
    let mut found = false
    let mut i = 0
    while i < keys.length() {
      if keys[i] == kv.0 {
        found = true
        if vals[i] != kv.1 {
          vals[i] = vals[i] + "!" + kv.1
        }
      }
      i = i + 1
    }
    if !found {
      keys.push(kv.0)
      vals.push(kv.1)
    }
  }
  let items : Array[String] = []
  let mut i = 0
  while i < keys.length() {
    items.push(keys[i] + "->" + vals[i])
    i = i + 1
  }
  sort_items(items)
  join_comma(items)
}

///|
fn lower_eff_op(op : EffectOp) -> String {
  match op {
    Set => "set"
    Default => "default"
    Unset => "unset"
    Empty => "empty"
    Update(transform, args) =>
      if args.length() == 0 {
        "update:" + transform
      } else {
        "update:" + transform + ":" + join_comma(args)
      }
    // DR-080 §2 merge accumulator piece markers (eff_op と同じ語彙、lower path 用の並行実装)。
    Remove => "remove"
    Splice => "splice"
  }
}

///|
fn gitem_str(g : GItem) -> String {
  match g {
    GExact(s) => "exact(" + s + ")"
    GSet(ex, v, link) =>
      "set{exact=" + ex + ",value=" + render_val(v) + ",link=" + link + "}"
    GEff(ex, link, op) =>
      "eff{exact=" + ex + ",link=" + link + ",op=" + lower_eff_op(op) + "}"
    GSeqSat(trig, ref_) =>
      "seq{exact=" + trig + ",ref=" + ref_ + ",link=" + ref_ + "}"
    GMatch(kind, entries) =>
      "matcher(" + kind + "){" + gmatch_entries_str(entries) + "}"
    GCmd(name, child) =>
      "cmd{exact=" + name + ",scope=(" + lsec_str(child) + ")}"
  }
}

///|
fn tnode_str(t : TNode) -> String {
  match t {
    TSeq(xs) => {
      let items : Array[String] = []
      for x in xs {
        items.push(tnode_str(x))
      }
      "seq[" + join_comma(items) + "]"
    }
    TRefEnt(n) => "ref{" + n + ",link=" + n + "}"
    TRefTmpl(id, opt_) =>
      "ref{" + id + (if opt_ { ",optional" } else { "" }) + "}"
    TExact(s) => "exact(" + s + ")"
  }
}

///|
fn lsec_str(s : LSec) -> String {
  let parts : Array[String] = []
  if s.greedy.length() > 0 {
    let items : Array[String] = []
    for g in s.greedy {
      items.push(gitem_str(g))
    }
    sort_items(items)
    parts.push("G[" + join_comma(items) + "]")
  }
  if s.positionals.length() > 0 {
    let items : Array[String] = []
    for p in s.positionals {
      items.push(tnode_str(p))
    }
    parts.push("P[" + join_comma(items) + "]")
  }
  if s.entities.length() > 0 {
    let items : Array[String] = []
    for e in s.entities {
      items.push(lent_str(e))
    }
    sort_items(items)
    parts.push("E[" + join_comma(items) + "]")
  }
  if s.constraints.length() > 0 {
    let items : Array[String] = []
    for c in s.constraints {
      items.push(lcon_str(c))
    }
    sort_items(items)
    parts.push("C[" + join_comma(items) + "]")
  }
  if s.templates.length() > 0 {
    let items : Array[String] = []
    for kv in s.templates {
      items.push(kv.0 + "=" + tnode_str(kv.1))
    }
    sort_items(items)
    parts.push("T[" + join_comma(items) + "]")
  }
  join_pipe(parts)
}

// ── projection: canon Scope → 断面 LSec ────────────────────────────────────────

///|
fn prim_name(n : Node) -> String? {
  match n {
    StrArg(x, _) => Some(x)
    NumArg(x, _, _) => Some(x)
    // TInt は DR-075 §1 で値空間判定に切替、CLI 相で IntArg 経由。lower 断面では他の value primitive
    // と同型の値セル (n) として扱う (Some(x) を返す)。
    IntArg(x, _, _, _) => Some(x)
    FloatArg(x, _) => Some(x)
    // DR-076 §1/§4: bool is now a normal value type, same satellite shape as string/number/int/float.
    BoolArg(x, _, _) => Some(x)
    SepArg(x, _, _, _, _, _, _, _) => Some(x)
    FilterArg(x, _) => Some(x)
    ReqArg(x) => Some(x)
    NoDashStr(x) => Some(x)
    _ => None
  }
}

///|
fn proj_seq_sat(xs : Array[Node]) -> GItem {
  match xs {
    [Exact(t), Bind(n, v)] => GSet(t, v, n)
    [Exact(t), Bind(n, v), FailMark(_)] => GSet(t, v, n)
    [Exact(t), Bind(n, v), DeprMark(_)] => GSet(t, v, n)
    [Exact(t), EffMark(n, op)] => GEff(t, n, op)
    [Exact(t), tail] =>
      match prim_name(tail) {
        Some(n) => GSeqSat(t, n)
        None => GExact("?seq:" + t)
      }
    _ => GExact("?seq:?")
  }
}

///|
fn proj_greedy(node : Node, reg : Map[String, Node]) -> GItem {
  match node {
    DdSat(name) => GExact(name)
    // DR-090: no golden lowering fixture exercises this yet (spec fixtures for DR-090 are
    // "query":"parse"輪郭, not lowering shape comparisons) — minimal, informative encoding via
    // the existing GMatch shape rather than inventing a new GItem variant for an untested path.
    DdMatchSat(spelling, is_pattern, self_keep, _) =>
      GMatch("dd_match:" + (if self_keep { "keep" } else { "drop" }), [
        (spelling, if is_pattern { "pattern" } else { "exact" }),
      ])
    Exact(s) => GExact(s)
    Rooted(inner, _) => proj_greedy(inner, reg)
    CmdSat(name, child) => GCmd(name, proj_scope(child, reg))
    NativeMatch(EqSplit(prefix~, entries~)) => {
      let es : Array[(String, String)] = []
      for e in entries {
        es.push((prefix + e.key, e.name))
      }
      GMatch("eq_split", es)
    }
    NativeMatch(ShortCombine(prefix=_, entries~, ..)) => {
      let es : Array[(String, String)] = []
      for e in entries {
        es.push(("\{e.ch}", e.name))
      }
      GMatch("short_combine", es)
    }
    Seq(xs) => proj_seq_sat(xs)
    _ => GExact("?greedy")
  }
}

///|
fn proj_pos(node : Node) -> TNode {
  match node {
    Ref(k) => TRefTmpl(canon_tmpl(k), false)
    Seq(xs) => {
      let items : Array[TNode] = []
      for x in xs {
        items.push(proj_tnode(x))
      }
      TSeq(items)
    }
    other =>
      match prim_name(other) {
        Some(n) => TRefEnt(n)
        None => TExact("?pos")
      }
  }
}

///|
fn proj_tnode(node : Node) -> TNode {
  match node {
    Seq(xs) => {
      let items : Array[TNode] = []
      for x in xs {
        items.push(proj_tnode(x))
      }
      TSeq(items)
    }
    Or([inner, Seq([])]) =>
      match inner {
        Ref(k) => TRefTmpl(canon_tmpl(k), true)
        other => proj_tnode(other)
      }
    Ref(k) => TRefTmpl(canon_tmpl(k), false)
    Exact(s) => TExact(s)
    other =>
      match prim_name(other) {
        Some(n) => TRefEnt(n)
        None => TExact("?tnode")
      }
  }
}

///|
fn proj_entity(e : Entity) -> LEnt {
  let typ = if e.is_config_file {
    "config_file"
  } else {
    match e.ty {
      TStr => "string"
      // DR-077 §3: `Entity.ty` is already collapsed TCount→TNum by `ensure_entity` for every real
      // count cell — folded in defensively (this arm should never actually see TCount).
      TNum | TCount => "number"
      TFloat => "float"
      TInt => "int"
      TFlag | TBool => "bool"
      TNone => "none"
    }
  }
  {
    name: e.name,
    typ,
    // DR-083 §1: LEnt is the golden-fixture "5-face" oracle format, which only knows a scalar
    // default (`dec_lent` below decodes `"default"` via a single `json_to_value`, no accum-array
    // shape) — project the scalar face of `Entity.default_values` for this cross-check.
    default_: default_scalar(e),
    env: e.env_key,
    inherit_: e.inherit_,
    config_key: e.config_key,
    accum: e.accum,
  }
}

///|
fn collect_reftmpls(
  nodes : Array[Node],
  reg : Map[String, Node],
  out : Array[String],
) -> Unit {
  fn is_tmpl_key(k : String) -> Bool {
    !str_has_prefix(k, "lazy:") && reg.get(k) is Some(_)
  }

  fn walk(n : Node) -> Unit {
    match n {
      Ref(k) =>
        if is_tmpl_key(k) && !conformance_str_in(out, k) {
          out.push(k)
          match reg.get(k) {
            Some(body) => walk(body)
            None => ()
          }
        }
      Seq(xs) =>
        for x in xs {
          walk(x)
        }
      Or(xs) =>
        for x in xs {
          walk(x)
        }
      Many(inner, _) => walk(inner)
      BoundedTail(inner, _, _) => walk(inner)
      Scoped(_, inner) => walk(inner)
      Rooted(inner, _) => walk(inner)
      _ => ()
    }
  }

  for n in nodes {
    walk(n)
  }
}

///|
fn proj_scope(sc : Scope, reg : Map[String, Node]) -> LSec {
  let greedy : Array[GItem] = []
  for g in sc.greedy {
    greedy.push(proj_greedy(g, reg))
  }
  let positionals : Array[TNode] = []
  for p in sc.positional {
    positionals.push(proj_pos(p))
  }
  let entities : Array[LEnt] = []
  for e in sc.entities {
    entities.push(proj_entity(e))
  }
  let constraints : Array[Constraint] = []
  for c in sc.constraints {
    constraints.push(c)
  }
  let ref_ids : Array[String] = []
  collect_reftmpls(sc.positional, reg, ref_ids)
  let templates : Array[(String, TNode)] = []
  for k in ref_ids {
    match reg.get(k) {
      Some(body) => templates.push((canon_tmpl(k), proj_tnode(body)))
      None => ()
    }
  }
  { greedy, positionals, entities, constraints, templates }
}

// ── lower runner (canon_of / pick3 / run_lower) ────────────────────────────────

///|
fn canon_of(def : Definition, order : Array[Installer]) -> String {
  let reg : Map[String, Node] = Map([])
  match parse_definition(def, order, registry=reg) {
    Ok(sc) => lsec_str(proj_scope(sc, reg))
    Err(e) => "ERR:" + deferrs_str(e)
  }
}

///|
fn order_sig(order : Array[Installer]) -> String {
  let buf = StringBuilder::new()
  for x in order {
    buf.write_string(owned_vocab(x))
    buf.write_string(";")
  }
  buf.to_string()
}

///|
fn pick3(order : Array[Installer]) -> Array[Array[Installer]] {
  let ident : Array[Installer] = []
  for x in order {
    ident.push(x)
  }
  let rev : Array[Installer] = []
  let mut i = order.length() - 1
  while i >= 0 {
    rev.push(order[i])
    i = i - 1
  }
  let rot : Array[Installer] = []
  if order.length() > 0 {
    let mut j = 1
    while j < order.length() {
      rot.push(order[j])
      j = j + 1
    }
    rot.push(order[0])
  }
  let out : Array[Array[Installer]] = []
  let sigs : Array[String] = []
  for cand in [ident, rev, rot] {
    let sig = order_sig(cand)
    if !conformance_str_in(sigs, sig) {
      sigs.push(sig)
      out.push(cand)
    }
  }
  out
}

///|
fn run_lower(def : Definition, order : Array[Installer], want : LSec) -> String {
  let got = canon_of(def, order)
  let wantS = lsec_str(want)
  let mut perm_ok = true
  for p in pick3(order) {
    if canon_of(def, p) != got {
      perm_ok = false
    }
  }
  if !perm_ok {
    "PERM-DIVERGE|got=" + got + "|want=" + wantS
  } else if got == wantS {
    "PASS"
  } else {
    "DIVERGE|got=" + got + "|want=" + wantS
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4 — Parse-path projections (mirror slice fixture_runner_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

///|
/// Key-sorted rendering of the built result object (CONFORMANCE §3: result is structural, key order
/// non-normative). Arrays keep order.
fn render_rval_sorted(r : RVal) -> String {
  match r {
    RScalar(v) => render_val(v)
    RArr(vs) => {
      let items : Array[String] = []
      for v in vs {
        items.push(render_rval_sorted(v))
      }
      "[" + join_comma(items) + "]"
    }
    RObj(kvs) => {
      let items : Array[String] = []
      for kv in kvs {
        items.push(kv.0 + "=" + render_rval_sorted(kv.1))
      }
      sort_items(items)
      "{" + join_comma(items) + "}"
    }
  }
}

///|
/// §2 CLI effects, EXCLUDING config_file infra cells. `set`/`remove` render an operand (DR-080 §2:
/// remove's operand is the type-parsed value being removed, same wire shape as set's); every other
/// op (default/unset/empty/update/splice) renders bare — `splice` carries no operand (DR-080 §2 `@`
/// just points at old, DESIGN's placeholder-value convention).
fn proj_effects_ex(sc : Scope, binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if is_sentinel(b.key) {
      continue
    }
    if is_config_file_cell(sc, b.key) {
      continue
    }
    // DR-089 §3 (team-lead 裁定 2026-07-11): none の発火は effects にも現れない (観測は
    // ParserContext/explains 層の管掌、値空間なしの set エントリを発明しない)。内部表現は
    // `flag_bare_true_variant` 再利用の Set+VBool(true) placeholder のままで良く (installer.mbt)、
    // ここ (射影層) だけで除外する — `is_config_file_cell` と同じ「Entity 属性を見て特定 cell を
    // 射影から外す」パターン。
    if is_none_cell(sc, b.key) {
      continue
    }
    // DR-093 §2/§7: dd 発火の committed 観測用 binding も同じ理由 (値空間なし、DR-089 §3) で
    // effects から除外する — entity を持たないので `is_none_cell` では捉えられない (`is_dd_cell`
    // 参照)。
    if is_dd_cell(sc, b.key) {
      continue
    }
    match b.op {
      Set | Remove =>
        items.push(
          "\{b.key}:\{eff_op(b.op)}(\{render_val(b.value)})@\{render_src(b.source)}",
        )
      _ => items.push("\{b.key}:\{eff_op(b.op)}@\{render_src(b.source)}")
    }
  }
  join_comma(items)
}

///|
fn is_config_file_cell(sc : Scope, name : String) -> Bool {
  for e in sc.entities {
    if e.name == name && e.is_config_file {
      return true
    }
  }
  false
}

///|
fn is_none_cell(sc : Scope, name : String) -> Bool {
  for e in sc.entities {
    if e.name == name && e.ty == TNone {
      return true
    }
  }
  false
}

///|
/// DR-093 §2/§7 波及: dd 要素 (`DdSat`/`DdMatchSat`) は entity を持たない (DR-030「実体=値セル」/
/// LOWERING §B.4、`ensure_entities` の `not_dd` ガード) が、DR-093 の committed 観測用 binding
/// (発火時の `flag_bare_true_variant` 同型 `Set VBool(true)` placeholder) は他の値と同じ `binds`
/// 配列に乗る。`is_none_cell` は entity 走査なので dd 要素の binding を捉えられない — scope の
/// greedy 面を直接走査して dd 要素名を集める、対になる判定。`proj_effects_ex` は `binds` をルート
/// scope 基準でフラットに舐める (`b.key` のみ比較、`b.scope` 不問) ので、`CmdSat` の子 scope も
/// 再帰的に見る (dd/global-sever.json のような子コマンドスコープ dd の実測で必須と判明)。
fn is_dd_cell(sc : Scope, name : String) -> Bool {
  fn scan(g : Node) -> Bool {
    match g {
      DdSat(trigger) => trigger == name
      DdMatchSat(_, _, _, elem_name) => elem_name == name
      Or(alts) => {
        for a in alts {
          if scan(a) {
            return true
          }
        }
        false
      }
      Rooted(inner, _) => scan(inner)
      CmdSat(_, child) => is_dd_cell(child, name)
      _ => false
    }
  }

  for g in sc.greedy {
    if scan(g) {
      return true
    }
  }
  false
}

///|
/// A `path` array rendered as a single comparable token (DR-066 §4 snoc form, root-first). `>` joins
/// segments — element/scope names are installer-derived identifiers (kuu source names), never
/// containing `>` — so this stays unambiguous the same way `/` separates the kind/reason fields.
fn render_path(path : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in path {
    if !first {
      buf.write_string(">")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

///|
/// §2 failure error set. Emits `element@pos/kind` per error; `reason` and `path` (DR-066 §4) each
/// ride along independently when the fixture asserted that field on ANY error in the set (per-field
/// opt-in, CONFORMANCE §3/§5) — `/reason` first (kept at its original position for fixtures already
/// asserting only reason), `|path` appended after (a separate delimiter so "no reason, but path
/// asserted" cannot collide with "reason asserted, no path"). sorted as a set.
fn proj_errors(
  errs : Array[ParseError],
  with_reason : Bool,
  with_path : Bool,
) -> String {
  let items : Array[String] = []
  for e in errs {
    let mut item = "\{e.element}@\{e.argv_pos}/\{render_kind(e.kind)}"
    if with_reason {
      item = item + "/\{e.reason}"
    }
    if with_path {
      item = item + "|\{render_path(e.path)}"
    }
    items.push(item)
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

///|
fn proj_warnings(o : Outcome) -> String {
  let ws = warnings_of(o)
  sort_items(ws)
  join_comma(ws)
}

///|
/// spec issue conformance-tried-triggers-help-entry-fields (CONFORMANCE §2/§3): DR-053 §4's
/// tried_triggers material as a sorted set (順序非規範、`proj_errors`と同じ `{a,b,c}` 表記 — 空集合
/// は `{}` になり「exact trigger 0 個」を明示的に表現する、空文字列との取り違えを避ける)。
fn proj_tried_triggers(triggers : Array[String]) -> String {
  let items : Array[String] = []
  for t in triggers {
    items.push(t)
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

///|
/// Result with the DR-052 result-key axis applied.
fn proj_result_export(
  sc : Scope,
  binds : Array[Binding],
  ekmap : Map[String, ExportKey],
) -> String {
  render_rval_sorted(
    build_result(
      apply_export_keys(binds, ekmap),
      accum_cells(sc, ekmap),
      apply_export_to_defaults(default_cells(sc), ekmap),
      [],
      nones=none_cells(sc),
    ),
  )
}

///|
/// Resolved value-source tags per cell (DR-031). Config_file infra cells are excluded. Flag-preset
/// defaults report `default` when no other seat surfaced (LOWERING §A.5). An accum cell's `Unset`
/// binding (issue 2026-07-09-accum-filters-non-set-op-semantics) reports `default` regardless of
/// its own `source` field — `Unset` is CLI-fired (`b.source == Cli`) but uncommitted (DR-045
/// "default 値へ戻す... committed=false"), so the value tag must reflect the LADDER OUTCOME
/// ("as if untouched", same as `unset-ladder.json`'s scalar precedent where a scalar cell's fold
/// already re-seats to a lower ladder rung on unset) rather than the firing token's own source. A
/// LATER `Set` after an `Unset` still wins normally (the loop keeps overwriting `src` in order) —
/// mirrors `build_result`'s ACCUMULATE fold treating `Unset` as a clear-point, not a terminal state.
fn proj_sources(
  sc : Scope,
  resolved : Array[Binding],
  ek : Map[String, ExportKey],
) -> String {
  let items : Array[String] = []
  for e in sc.entities {
    if e.is_config_file {
      continue
    }
    // DR-089 §3: none has no value, so it has no "source" either (結果非掲載と同じ posture — 発火の
    // 観測は explains 層の管掌で、この射影の関心ではない)。
    if e.ty == TNone {
      continue
    }
    // issue accum-export-key-rename-asymmetry の続き (fixture export-key/rename-multiple.json
    // で実機確認): sources 射影も `proj_result_export`/`accum_cells` と同じ DR-052 §1 解決
    // (`exposed_key_of`, resolve.mbt) を経由させる — こちらも今まで `ek` を一切見ておらず、
    // rename された cell の source 行が旧名のまま出るバグだった (rename.json は元々 sources を
    // 検証していなかったため顕在化していなかった)。EkNull (透過) の cell は sources にも出さない
    // (result 側の透過と同じ posture)。
    match exposed_key_of(e.name, ek) {
      None => ()
      Some(exposed) => {
        let mut src : String? = None
        for b in resolved {
          if b.key == e.name && !is_sentinel(b.key) {
            src = match b.op {
              Unset => Some("default")
              _ => Some(render_src(b.source))
            }
          }
        }
        match src {
          Some(s) => items.push(exposed + "=" + s)
          None =>
            // DR-044 uniform array (issue 2026-07-09-env-separator-split-gap's env-separator-
            // split.json, `sources` check): an unfired multiple/repeat cell decays to `[]` (never
            // absent, same guarantee flag/bool's default preset gets below) — regardless of type,
            // and regardless of whether the element ALSO declared an explicit `default:` (accum
            // cells usually don't; the empty array IS the implicit default here, unconditionally).
            if e.accum is Some(_) {
              items.push(exposed + "=default")
            } else if (e.ty == TFlag || e.ty == TBool) && e.accum is None {
              match default_scalar(e) {
                Some(_) => items.push(exposed + "=default")
                None => ()
              }
            }
        }
      }
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
fn proj_sources_tree(resolved : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in resolved {
    if is_sentinel(b.key) {
      continue
    }
    let mut key = ""
    for seg in b.scope {
      key = key + seg + "."
    }
    key = key + b.key
    items.push(key + "=" + render_src(b.source))
  }
  sort_items(items)
  join_comma(items)
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5 — JSON conformance runner (mirror slice json_conformance_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

// ── skip signal ────────────────────────────────────────────────────────────────

///|
suberror DecodeSkip {
  DecodeSkip(String)
}

// ── decoded case & fixture ────────────────────────────────────────────────────

///|
enum CfgInj {
  NoCfg
  CfgObj(ConfigVal)
  CfgFiles(Array[(String, ConfigVal)])
}

///|
struct DCase {
  argv : Array[String]
  id : String
  outcome : String
  exp_effects : String?
  exp_result : String?
  // errors face: (asserted-set-string, whether fixture provided reason/path on any error, DR-066 §4/§5)
  exp_errors : String?
  exp_errors_with_reason : Bool
  exp_errors_with_path : Bool
  exp_interps : Array[String]?
  exp_warnings : String?
  exp_sources : String?
  fired_cmp : Bool
  fired_exp : String?
  // spec issue conformance-tried-triggers-help-entry-fields (CONFORMANCE §2/§3): help_entry is
  // opt-in on failure OR ambiguous (structural equality — a plain String? compare like fired_action's).
  help_cmp : Bool
  help_exp : String?
  // tried_triggers is opt-in on failure only, set comparison (順序非規範) — held as the SAME
  // sorted `{a,b,c}` projection string `proj_tried_triggers` produces from the live Outcome, so
  // comparison is a plain String `!=` like every other set-compared face (errors/warnings/sources).
  tried_cmp : Bool
  tried_exp : String?
  resolve : Bool
  env : Map[String, String]
  cfg : CfgInj
}

///|
struct DecodedFixture {
  scope : Scope
  registry : Map[String, Node]
  ekmap : Map[String, ExportKey]
  cases : Array[DCase]
}

///|
enum DElem {
  DOpt(ElemDef)
  DAlias(AliasDef)
}

///|
enum DCmd {
  DCommand(CommandDef)
  DCmdAlias(AliasDef)
}

// ── JSON helpers ──────────────────────────────────────────────────────────────

///|
fn jf_str(o : Map[String, Json], key : String) -> String? {
  match o.get(key) {
    Some(j) => j.j_str()
    None => None
  }
}

///|
/// DR-067 §2 name/id 構文制約 (codex 節目レビュー指摘1, issue 2026-07-09-ref-template-result-shape):
/// `#` を含む name/id はユーザ定義で禁止 — repeat lowering の内部 template キー
/// (`e.name + "#cons"`, installer.mbt `lower_repeat_head`)・`next_or_branch_id`'s 自動採番
/// ("#0"/"#1"/…)・resolve.mbt の row/fire sentinel ("#row"/"#fire") が共有する予約名前空間
/// (DR-046 §4)。id 未指定なら name が id を兼ねる (DR-046 §2) ため name にも同じ制約が及ぶ — ここを
/// enforce しないと `{"name": "src#cons"}` のような wire がその内部キーと衝突しうる。既存の decode
/// error と同じ語彙 (`raise DecodeSkip`) で reject する。呼び出し側は name/id を読んだ「その場」で
/// これを通す (missing チェックの直後、他フィールドの decode より前 — 診断が name/id の妥当性で早期
/// に止まるようにする)。
fn check_reserved_name(name : String, what : String) -> Unit raise DecodeSkip {
  if name.contains("#") {
    raise DecodeSkip(
      what +
      " name/id '" +
      name +
      "' contains '#' (DR-067 §2: '#' はユーザ定義で禁止、内部予約名前空間)",
    )
  }
}

///|
fn has_key(o : Map[String, Json], k : String) -> Bool {
  match o.get(k) {
    Some(_) => true
    None => false
  }
}

///|
fn allowed_keys(
  o : Map[String, Json],
  allowed : Array[String],
  what : String,
) -> Unit raise DecodeSkip {
  for k, _ in o {
    if !conformance_str_in(allowed, k) {
      raise DecodeSkip(what + " has unsupported key '" + k + "'")
    }
  }
}

///|
fn bool_field(
  o : Map[String, Json],
  k : String,
  dflt : Bool,
) -> Bool raise DecodeSkip {
  match o.get(k) {
    None => dflt
    Some(j) =>
      match j.j_bool() {
        Some(b) => b
        None => raise DecodeSkip(k + " is not a bool")
      }
  }
}

///|
fn num_int(j : Json, ctx : String) -> Int raise DecodeSkip {
  match j.j_num() {
    Some(d) => d.to_int()
    None => raise DecodeSkip(ctx + " is not a number")
  }
}

///|
fn json_to_value(j : Json) -> Value raise DecodeSkip {
  match j.j_bool() {
    Some(b) => return VBool(b)
    None => ()
  }
  match j.j_str() {
    Some(s) => return VStr(s)
    None => ()
  }
  match j.j_num() {
    Some(d) => return VNum(d)
    None => ()
  }
  raise DecodeSkip("non-scalar value in effects/result")
}

///|
/// DR-083 §1: a declared `"default"` decodes to the length-1-degenerate array uniformly — a bare
/// JSON scalar lifts to a single-piece array (`[v]`), a JSON array decodes elementwise (one Value
/// per already-split piece, DR-083 §2). Which shape is STRUCTURALLY legal for a given element
/// (scalar element ⇒ length must end up 1) is a definition-time check, NOT a decode-time gate —
/// `collect_scalar_array_default` (installer.mbt) is the one that rejects a >1-length default on a
/// non-accum element; this decoder accepts either JSON shape unconditionally.
fn json_to_default_values(j : Json) -> Array[Value] raise DecodeSkip {
  match j.j_arr() {
    Some(a) => {
      let vs : Array[Value] = []
      for it in a {
        vs.push(json_to_value(it))
      }
      vs
    }
    None => [json_to_value(j)]
  }
}

///|
fn json_to_rval(j : Json) -> RVal raise DecodeSkip {
  match j.j_obj() {
    Some(o) => {
      let kvs : Array[(String, RVal)] = []
      for k, v in o {
        kvs.push((k, json_to_rval(v)))
      }
      return RObj(kvs)
    }
    None => ()
  }
  match j.j_arr() {
    Some(a) => {
      let vs : Array[RVal] = []
      for v in a {
        vs.push(json_to_rval(v))
      }
      return RArr(vs)
    }
    None => ()
  }
  RScalar(json_to_value(j))
}

///|
fn json_to_configval(j : Json) -> ConfigVal {
  match j.j_obj() {
    Some(o) => {
      let kvs : Array[(String, ConfigVal)] = []
      for k, v in o {
        kvs.push((k, json_to_configval(v)))
      }
      return CObj(kvs)
    }
    None => ()
  }
  match j.j_arr() {
    Some(a) => {
      let vs : Array[ConfigVal] = []
      for v in a {
        vs.push(json_to_configval(v))
      }
      return CArr(vs)
    }
    None => ()
  }
  match j.j_bool() {
    Some(b) => return CBool(b)
    None => ()
  }
  match j.j_str() {
    Some(s) => return CStr(s)
    None => ()
  }
  match j.j_num() {
    Some(d) => return CNum(d)
    None => ()
  }
  CNull
}

///|
fn dec_strs(j : Json?) -> Array[String] raise DecodeSkip {
  match j {
    None => []
    Some(x) =>
      match x.j_str() {
        Some(s) => [s]
        None =>
          match x.j_arr() {
            Some(a) => {
              let r : Array[String] = []
              for e in a {
                match e.j_str() {
                  Some(s) => r.push(s)
                  None =>
                    raise DecodeSkip("string-array element is not a string")
                }
              }
              r
            }
            None => raise DecodeSkip("expected a string or string[]")
          }
      }
  }
}

///|
/// Decode a filters-chain field (`piece_filters`/`value_filters`/`cell_filters`, DR-009 §DSL 文法)
/// into `Array[FilterSpelling]` (node.mbt, issue filter-spelling-inband-encoding-retyping): same
/// shape as `dec_strs` (a string, or a string[]), but each array element may ALSO be the DR-085 §3
/// / DESIGN §8.4 object form `{"name": ..., "args": [...]}` — needed when a filter's own arg
/// contains a colon (e.g. `regex_match`'s `^https?://` pattern breaks the colon-shorthand DSL's
/// all-colon-split rule, DR-009). Both forms decode to the SAME `FilterSpelling` struct (colon
/// shorthand → `filters.mbt`'s `parse_filter_shorthand`, object form → `name`/`args` read straight
/// off the JSON object) — no in-band string encoding is needed since the result type carries `args`
/// as a real `Array[String]`, replacing the earlier U+E000 PUA-tag single-string encoding that
/// shared `Array[String]` with plain shorthand strings (that scheme had a latent hole: an object-
/// form arg VALUE containing the tag character itself would have mis-split). `dec_strs` itself is
/// intentionally NOT reused here: it's shared by `requires`/`conflicts_with`/`exclusive_group`/
/// `env`/`targets`/`members`, none of which have an object form — this is a sibling decoder
/// specific to the 3 filter-chain fields, not a generalized replacement.
fn dec_filter_chain(j : Json?) -> Array[FilterSpelling] raise DecodeSkip {
  match j {
    None => []
    Some(x) =>
      match x.j_str() {
        Some(s) => [parse_filter_shorthand(s)]
        None =>
          match x.j_arr() {
            Some(a) => {
              let r : Array[FilterSpelling] = []
              for e in a {
                match e.j_str() {
                  Some(s) => r.push(parse_filter_shorthand(s))
                  None =>
                    match e.j_obj() {
                      Some(o) => {
                        allowed_keys(
                          o,
                          ["name", "args"],
                          "filter (object form)",
                        )
                        let name = match jf_str(o, "name") {
                          Some(n) => n
                          None =>
                            raise DecodeSkip(
                              "filter object form missing 'name'",
                            )
                        }
                        let args = match o.get("args") {
                          Some(aj) =>
                            match aj.j_arr() {
                              Some(aa) => {
                                let out : Array[String] = []
                                for av in aa {
                                  match av.j_str() {
                                    Some(s) => out.push(s)
                                    None =>
                                      raise DecodeSkip(
                                        "filter object form 'args' element is not a string",
                                      )
                                  }
                                }
                                out
                              }
                              None =>
                                raise DecodeSkip(
                                  "filter object form 'args' is not an array",
                                )
                            }
                          None => []
                        }
                        r.push({ name, args })
                      }
                      None =>
                        raise DecodeSkip(
                          "filter chain element is not a string or object",
                        )
                    }
                }
              }
              r
            }
            None =>
              raise DecodeSkip(
                "expected a string or filter[] (string | object form)",
              )
          }
      }
  }
}

// ── expected-string builders ──────────────────────────────────────────────────

///|
fn exp_effects_str(eff : Json) -> String raise DecodeSkip {
  let a = match eff.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("effects is not an array")
  }
  let items : Array[String] = []
  for e in a {
    let eo = match e.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("effect is not an object")
    }
    let entity = match jf_str(eo, "entity") {
      Some(s) => s
      None => raise DecodeSkip("effect missing 'entity'")
    }
    let op = match jf_str(eo, "op") {
      Some(s) => s
      None => raise DecodeSkip("effect missing 'op'")
    }
    let source = match jf_str(eo, "source") {
      Some(s) => s
      None => raise DecodeSkip("effect missing 'source'")
    }
    // DR-077 §1: an `update` effect's descriptor carries a `transform` name alongside `op` (mirrors
    // the wire effect descriptor `{op:"update", transform:"increment"}`) — folded into the SAME
    // op-string `eff_op`/`lower_eff_op` render for the 0-arg case ("update:increment"), so a fixture
    // needs no separate comparison branch. Absent for every other op (unaffected).
    let op_str = match jf_str(eo, "transform") {
      Some(t) => op + ":" + t
      None => op
    }
    match eo.get("operand") {
      Some(j) =>
        items.push(
          "\{entity}:\{op_str}(\{render_val(json_to_value(j))})@\{source}",
        )
      None => items.push("\{entity}:\{op_str}@\{source}")
    }
  }
  join_comma(items)
}

///|
fn exp_result_str(res : Json) -> String raise DecodeSkip {
  render_rval_sorted(json_to_rval(res))
}

///|
/// Decode a fixture error's `path` array (DR-066 §4, root-first) into the same `>`-joined token
/// `render_path` produces on the got side, so string comparison lines up.
fn exp_error_path(eo : Map[String, Json]) -> String raise DecodeSkip {
  match eo.get("path") {
    Some(j) =>
      match j.j_arr() {
        Some(segs) => {
          let parts : Array[String] = []
          for s in segs {
            match s.j_str() {
              Some(str) => parts.push(str)
              None => raise DecodeSkip("error 'path' element is not a string")
            }
          }
          render_path(parts)
        }
        None => raise DecodeSkip("error 'path' is not an array")
      }
    None => "" // absent on a specific error — compare against empty ([]) path on got side
  }
}

///|
/// Decode the fixture's errors[] and report the sorted set-string plus whether any error had a
/// `reason` and/or `path` field (DR-066 §4/§5, each an INDEPENDENT per-fixture-set opt-in):
/// with_reason / with_path drive got-side inclusion so the per-field opt-in comparison stays aligned.
fn exp_errors_decode(errs : Json) -> (String, Bool, Bool) raise DecodeSkip {
  let a = match errs.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("errors is not an array")
  }
  // detect reason/path opt-in first (per fixture set, not per element)
  let mut with_reason = false
  let mut with_path = false
  for e in a {
    match e.j_obj() {
      Some(eo) => {
        if has_key(eo, "reason") {
          with_reason = true
        }
        if has_key(eo, "path") {
          with_path = true
        }
      }
      None => raise DecodeSkip("error is not an object")
    }
  }
  let items : Array[String] = []
  for e in a {
    let eo = e.j_obj().unwrap()
    let element = match jf_str(eo, "element") {
      Some(s) => s
      None => ""
    }
    let pos = match eo.get("argv_pos") {
      Some(j) =>
        match j.j_num() {
          Some(d) => d.to_int().to_string()
          None => raise DecodeSkip("error 'argv_pos' is not a number")
        }
      None => raise DecodeSkip("error missing 'argv_pos'")
    }
    let kind = match jf_str(eo, "kind") {
      Some(s) => s
      None => raise DecodeSkip("error missing 'kind'")
    }
    let mut item = "\{element}@\{pos}/\{kind}"
    if with_reason {
      let reason = match jf_str(eo, "reason") {
        Some(s) => s
        None => "" // absent on a specific error — compare against empty reason on got side
      }
      item = item + "/\{reason}"
    }
    if with_path {
      item = item + "|\{exp_error_path(eo)}"
    }
    items.push(item)
  }
  sort_items(items)
  ("{" + join_comma(items) + "}", with_reason, with_path)
}

///|
fn exp_warnings_str(j : Json) -> String raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("warnings is not an array")
  }
  let items : Array[String] = []
  for e in a {
    let eo = match e.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("warning is not an object")
    }
    match jf_str(eo, "element") {
      Some(el) => items.push(el)
      None => raise DecodeSkip("warning missing 'element'")
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
fn exp_sources_str(j : Json) -> String raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("sources is not an object")
  }
  let items : Array[String] = []
  for k, v in o {
    let src = match v.j_str() {
      Some(s) => s
      None => raise DecodeSkip("source value is not a string")
    }
    items.push(k + "=" + src)
  }
  sort_items(items)
  join_comma(items)
}

///|
fn exp_claimants_str(j : Json) -> String raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("claimants is not an object")
  }
  let items : Array[String] = []
  for k, v in o {
    let ent = match v.j_str() {
      Some(s) => s
      None =>
        raise DecodeSkip("claimant value (occupying entity) is not a string")
    }
    items.push(k + "=" + ent)
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

///|
fn exp_interp_str(e : Json) -> String raise DecodeSkip {
  match e.j_obj() {
    Some(o) =>
      if has_key(o, "claimants") {
        allowed_keys(o, ["result", "claimants"], "interpretation wrapper")
        let view = match o.get("result") {
          Some(r) => render_rval_sorted(json_to_rval(r))
          None => raise DecodeSkip("interpretation wrapper missing 'result'")
        }
        view + "#claimants" + exp_claimants_str(o.get("claimants").unwrap())
      } else {
        render_rval_sorted(json_to_rval(e))
      }
    None => render_rval_sorted(json_to_rval(e))
  }
}

///|
fn dec_interps(j : Json) -> Array[String] raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("interpretations is not an array")
  }
  let out : Array[String] = []
  for e in a {
    out.push(exp_interp_str(e))
  }
  sort_items(out)
  out
}

// ── definition decoders ───────────────────────────────────────────────────────

///|
fn dec_short(o : Map[String, Json]) -> Array[Char] raise DecodeSkip {
  match o.get("short") {
    None => []
    Some(j) =>
      match j.j_str() {
        Some(s) => to_chars(s)
        None =>
          match j.j_arr() {
            Some(a) => {
              let cs : Array[Char] = []
              for e in a {
                match e.j_str() {
                  Some(s) =>
                    for c in to_chars(s) {
                      cs.push(c)
                    }
                  None => raise DecodeSkip("short[] element is not a string")
                }
              }
              cs
            }
            None => raise DecodeSkip("short is a bool/other (stage 2)")
          }
      }
  }
}

///|
/// DR-074 §3: `"flag"` is a presence-only trigger (`TFlag`, no `=value` form ever — e.g. `--help`);
/// `"bool"` is the value-typed canonical bool (`TBool`, additionally takes `--x=value` unless it
/// carries variant spellings, installer.mbt `inst_long`). The two JSON type strings map to
/// DIFFERENT Ty variants now (they used to collapse to one `TFlag`, which made a value-typed
/// bool's `--enabled=true` eq-split unreachable — see fixtures/value-typing/bool-canonical.json).
/// Likewise DR-074 §1: `"number"` (`TNum`, rejects inf) and `"float"` (`TFloat`, accepts inf) map to
/// DIFFERENT Ty variants (they used to collapse to one `TNum` — see
/// fixtures/value-typing/number-inf-nan.json's `--t`/`--n` type-dependent inf accept域).
fn dec_ty(t : String) -> Ty raise DecodeSkip {
  match t {
    "string" => TStr
    "number" => TNum
    "float" => TFloat
    "int" => TInt
    "flag" => TFlag
    "bool" => TBool
    // DR-077 §3: `"count"` is the PRE-normalize marker (mirrors `"flag"` → `TFlag`) — installer.mbt
    // collapses it to `TNum` at `ensure_entity`, not here (decode's only job is the wire type
    // string → Ty tag, same as every other arm).
    "count" => TCount
    // DR-089 §2: type:"none" は第一級 — 値空間が空の型 (省略の明示綴り、同じタグに解決する)。
    "none" => TNone
    other => raise DecodeSkip("value type '" + other + "'")
  }
}

///|
/// DR-061 §3 configurable factory の type shadow: user 定義の型名を base Ty + parse 相 config に
/// 解決する。fixture の `definitions.types.<name>` → TypeShadow の map で保持し、dec_option /
/// dec_positional の `type: "<name>"` 解決で consultation する。canonical 型名 (string/number/int/...)
/// は shadow で override 可能だが本 fixture では未使用 (`int_parser`/`number_parser`/`bool_parser`
/// factory のみ扱う)。
struct TypeShadow {
  base : Ty
  int_round : RoundMode
  // DR-074 §2 `number_allow_base_prefix` (`number_parser` factory config)。canonical default = false。
  // TypeShadow が担う base 側の flag は canonical default が false なので、int_round と直交な平坦キー。
  allow_base_prefix : Bool
  // DR-074 §4 `bool_parser` factory config (`true_values`/`false_values`/`case_insensitive` を 1
  // struct に束ねた carrier、ElemDef.bool_config と同型)。canonical default = `bool_config_canonical()`。
  bool_config : BoolConfig
} derive(Eq, Debug)

///|
/// Decode `definitions.types` (DR-061 §3 `{name: <factory>, config: {<key>: <value>, ...}}`) into
/// a shadow map. 各 shadow は base Ty (factory 名から導出) と平坦 config キーで構成される。
/// 現状サポート: `int_parser` (base = TInt、config = `int_round`)、`number_parser` (base = TNum、
/// config = `number_allow_base_prefix`)、`bool_parser` (base = TBool、config = `true_values` /
/// `false_values` / `case_insensitive`、DR-074 §3/§4)。他の factory 名は DecodeSkip で明示的に
/// unsupported 扱い (typo 検出、DR-061 §4 は factory 自身が config 値を検証する規定なので、
/// type/factory 認識のこの層は capability gate として振る舞う)。
///
/// DR-094 §3/§9 案A: factory 名は `<bare>` (builtin ns の糖衣) / `builtin/<bare>` (ns 明示) の
/// 2 形が同一実体に解決される。旧 ad-hoc prefix `kuu_<bare>` は fixture pin bump (37aa3b3d) 完了に
/// 伴い移行期間を終え、unsupported factory として明示的に拒否される (unknown-vocab の一部、
/// DR-054)。
fn dec_types(j : Json) -> Map[String, TypeShadow] raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("definitions.types is not an object")
  }
  let out : Map[String, TypeShadow] = Map([])
  for name, tj in o {
    let to = match tj.j_obj() {
      Some(x) => x
      None =>
        raise DecodeSkip(
          "definitions.types[" +
          name +
          "] is not an object (expected {name, config})",
        )
    }
    allowed_keys(to, ["name", "config"], "type shadow")
    let factory = match jf_str(to, "name") {
      Some(s) => s
      None =>
        raise DecodeSkip(
          "definitions.types[" + name + "] missing factory 'name'",
        )
    }
    match factory {
      "int_parser" | "builtin/int_parser" => {
        // DR-075 §2 int_round (10 モード語彙、round_mode_of で解決) + DR-074 §2 の (int にも波及する)
        // `number_allow_base_prefix`。config 未指定は canonical default (RError + false)。
        let mut mode = RError
        let mut base_prefix = false
        match to.get("config") {
          Some(cj) => {
            let co = match cj.j_obj() {
              Some(x) => x
              None =>
                raise DecodeSkip(
                  "definitions.types[" + name + "].config is not an object",
                )
            }
            allowed_keys(
              co,
              ["int_round", "number_allow_base_prefix"],
              "int_parser config",
            )
            match co.get("int_round") {
              Some(vj) =>
                match vj.j_str() {
                  Some(s) =>
                    match round_mode_of(s) {
                      Some(m) => mode = m
                      None =>
                        raise DecodeSkip(
                          "definitions.types[" +
                          name +
                          "].config.int_round '" +
                          s +
                          "' is not a canonical RoundMode",
                        )
                    }
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.int_round is not a string",
                    )
                }
              None => ()
            }
            match co.get("number_allow_base_prefix") {
              Some(vj) =>
                match vj.j_bool() {
                  Some(b) => base_prefix = b
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.number_allow_base_prefix is not a bool",
                    )
                }
              None => ()
            }
          }
          None => ()
        }
        out.set(name, {
          base: TInt,
          int_round: mode,
          allow_base_prefix: base_prefix,
          bool_config: bool_config_canonical(),
        })
      }
      "number_parser" | "builtin/number_parser" => {
        // DR-074 §2 `number_allow_base_prefix` = 統合 opt-in で 0x/0o/0b + hex float 一括有効化
        // (単一 flag、canonical default false)。他 config キー (`number_thousand_sep` /
        // `number_leading_zero`) は本 substrate 未サポート (fixture が使わないため)。
        let mut base_prefix = false
        match to.get("config") {
          Some(cj) => {
            let co = match cj.j_obj() {
              Some(x) => x
              None =>
                raise DecodeSkip(
                  "definitions.types[" + name + "].config is not an object",
                )
            }
            allowed_keys(
              co,
              ["number_allow_base_prefix"],
              "number_parser config",
            )
            match co.get("number_allow_base_prefix") {
              Some(vj) =>
                match vj.j_bool() {
                  Some(b) => base_prefix = b
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.number_allow_base_prefix is not a bool",
                    )
                }
              None => ()
            }
          }
          None => ()
        }
        out.set(name, {
          base: TNum,
          int_round: RError,
          allow_base_prefix: base_prefix,
          bool_config: bool_config_canonical(),
        })
      }
      "bool_parser" | "builtin/bool_parser" => {
        // DR-074 §3/§4 bool_parser factory config: `true_values`/`false_values`/`case_insensitive`
        // の 3 平坦 config キー。canonical default は既存 parse_bool と同値
        // (bool_config_canonical())、未指定キーはそれぞれの default を個別に維持する (3 キー独立
        // override — 1 キーだけ opt-in しても他の 2 キーは canonical のまま、DR-061 §4 の平坦
        // config キー原則と同じ「キー単位で独立」の扱い、int_parser/number_parser と同型)。
        let canon = bool_config_canonical()
        let mut true_values = canon.true_values
        let mut false_values = canon.false_values
        let mut case_insensitive = canon.case_insensitive
        match to.get("config") {
          Some(cj) => {
            let co = match cj.j_obj() {
              Some(x) => x
              None =>
                raise DecodeSkip(
                  "definitions.types[" + name + "].config is not an object",
                )
            }
            allowed_keys(
              co,
              ["true_values", "false_values", "case_insensitive"],
              "bool_parser config",
            )
            match co.get("true_values") {
              Some(vj) => true_values = dec_str_array(vj, name, "true_values")
              None => ()
            }
            match co.get("false_values") {
              Some(vj) => false_values = dec_str_array(vj, name, "false_values")
              None => ()
            }
            match co.get("case_insensitive") {
              Some(vj) =>
                match vj.j_bool() {
                  Some(b) => case_insensitive = b
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.case_insensitive is not a bool",
                    )
                }
              None => ()
            }
          }
          None => ()
        }
        out.set(name, {
          base: TBool,
          int_round: RError,
          allow_base_prefix: false,
          bool_config: { true_values, false_values, case_insensitive },
        })
      }
      other =>
        raise DecodeSkip(
          "definitions.types[" +
          name +
          "] unsupported factory '" +
          other +
          "' (only int_parser / number_parser / bool_parser are wired in the current substrate)",
        )
    }
  }
  out
}

///|
/// DR-078 §1 `definitions.templates`: name → shared consumption-grammar `Node`, decoded straight
/// into the `registry` a `ref` element's head resolves against (`ElemDef.ref_target`/`elem_head`,
/// installer.mbt — this decode is the ONLY missing piece, the runtime side was already complete).
/// Mutates `registry` in place (same map `dec_fixture` later threads into `parse_definition`) rather
/// than returning a fresh map — `registry` also receives `parse_definition`'s OWN repeat-recursion
/// entries later (`init_sb`), so it has to be the single shared mutable instance throughout, not a
/// value merged in afterward.
fn dec_templates(
  j : Json,
  shadows : Map[String, TypeShadow],
  registry : Map[String, Node],
) -> Unit raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("definitions.templates is not an object")
  }
  for name, tj in o {
    check_reserved_name(name, "definitions.templates")
    registry.set(name, dec_template_body(tj, shadows))
  }
}

///|
/// One `definitions.templates` entry's body (DR-078 §1 "値は要素定義と同じ構造記法 (or / seq /
/// 裸文字列等、LOWERING §A 群の糖衣がそのまま効く)"). Three shapes, mirroring `dec_or_structural`'s
/// own branch-shape handling (§1's example is literally an `or` of a `seq` branch + a bare-leaf
/// branch — this reuses that SAME decoder + `or_branch_node`, installer.mbt, rather than
/// duplicating the or/seq/leaf grammar a second time):
///   `{"or": [...]}`   — structural or (DR-055 value-enum `or` form is rejected: a template's
///                       job is a shared CONSUMPTION grammar, not a constraint-declaration sugar)
///   `{"seq": [...]}`  — a bare sequence of leaf cells (no outer `or`)
///   `{"type":..,"name":..}` — a single bare leaf cell (no `seq` wrapper, DR-078 §1 "裸文字列等")
fn dec_template_body(
  j : Json,
  shadows : Map[String, TypeShadow],
) -> Node raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("definitions.templates entry is not an object")
  }
  match o.get("or") {
    Some(orj) => {
      allowed_keys(o, ["or"], "template body (or)")
      match dec_or_structural(orj, shadows) {
        Some(branches) => {
          let nodes : Array[Node] = []
          for br in branches {
            nodes.push(or_branch_node(br))
          }
          Or(nodes)
        }
        None =>
          raise DecodeSkip(
            "definitions.templates 'or' has no structural branches (DR-055 value-enum form is option-only, not a shared consumption template)",
          )
      }
    }
    None =>
      match o.get("seq") {
        Some(sj) => {
          allowed_keys(o, ["seq"], "template body (seq)")
          let sa = match sj.j_arr() {
            Some(x) => x
            None => raise DecodeSkip("template body 'seq' is not an array")
          }
          let nodes : Array[Node] = []
          for e in sa {
            nodes.push(elem_head(dec_or_leaf(e, shadows)))
          }
          Seq(nodes)
        }
        None => elem_head(dec_or_leaf(j, shadows)) // bare leaf {"type":..,"name":..}
      }
  }
}

///|
/// wire bool|array long → `LongDecl`, UNCHANGED — this is decode's entire responsibility for `long`
/// now (kawaz 裁定 2026-07-08): the two-form distinction (DR-071 §1) is preserved as data instead of
/// being collapsed into an `Array[String]` here, because collapsing it destroys information
/// `resolve_long` (installer.mbt) needs (a bare `long:true` and an explicit `long:[":set"]` decode to
/// the SAME `[":set"]` array, yet DR-076 §2 requires DIFFERENT flag sugar for each). Type-dependent
/// sugar expansion, colon-DSL classification, and syntax-error detection all moved to installer.mbt's
/// `resolve_long` / `collect_invalid_long_dsl` — decode only mirrors the wire shape.
fn dec_long(j : Json) -> LongDecl raise DecodeSkip {
  match j.j_bool() {
    Some(b) => LBool(b)
    None =>
      match j.j_arr() {
        Some(a) => {
          let strs : Array[String] = []
          for e in a {
            match e.j_str() {
              Some(s) => strs.push(s)
              None => raise DecodeSkip("long[] element is not a string")
            }
          }
          LList(strs)
        }
        None => raise DecodeSkip("long is not a bool/array")
      }
  }
}

///|
fn dec_repeat(j : Json) -> RepeatSpec raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("repeat is not an object")
  }
  allowed_keys(o, ["min", "max", "lazy"], "repeat")
  let min = match o.get("min") {
    Some(m) => num_int(m, "repeat.min")
    None => 0
  }
  let max = match o.get("max") {
    Some(m) => Some(num_int(m, "repeat.max"))
    None => None
  }
  let lazy_ = bool_field(o, "lazy", false)
  { min, max, lazy_ }
}

///|
/// The DR-036 `collector` vocab this decode layer actually wires end-to-end (issue
/// 2026-07-09-dec-multiple-collector-decode). `unwrap_single` has a real runtime (resolve.mbt's
/// `apply_collector`/`unwrap_single`, applied to the accum cell's final array in `build_result`).
/// `to_set`/`from_entries` are DR-036 registry presets but NOT reachable through this simple
/// by-name field: `to_set` has no runtime implementation at all yet, and `from_entries` (DR-044)
/// takes a shape config (`FromEntries`: Entries/KeyValue/KeyPromote) this single-string field can't
/// carry — accepting either name here would decode successfully but silently render the plain
/// array at runtime (a decode/runtime capability mismatch), so both are explicitly rejected with a
/// reason instead of falling into the generic "unknown" message.
fn known_collector(name : String) -> Bool {
  name == "unwrap_single"
}

///|
/// DR-036 `multiple`. Returns (fires, separator, collector). The `accumulator` key's accepted
/// vocab stays "append"-only (issue acceptance criterion 判断: DR-036 also lists merge/override/
/// increment/flatten, but `installer.mbt`'s `ensure_entity` hardcodes the accum registry entry
/// from `e.multiple`/`elem_repeat`/`e.separator` alone — it never reads the decoded accumulator
/// string. Accepting a wider vocab here would decode successfully while installer.mbt silently
/// keeps treating every multiple cell as plain "append", a decode/runtime mismatch of the same
/// kind `known_collector`'s doc comment describes for `to_set`/`from_entries`. Widening this needs
/// `ensure_entity` to actually consult the accumulator name first).
/// DR-080 §1: "merge" を accumulator 語彙に追加 (append の兄弟)。戻り値の4番目 (accumulator 名)
/// は None = 未指定 (`ensure_entity` が既定 "append" にフォールバック)、Some("merge") が DR-080 の
/// merge accumulator を選ぶ。bool/string 糖衣 (`true`/`"append"`) は常に "append" 相当 (accumulator
/// 名 None = デフォルト) — merge は object 形の `accumulator` キーでのみ選べる (DR-080 §1 の宣言例)。
/// DR-091 §2: "kv_map" を同じ枠 (object 形の `accumulator` キー限定) に追加 — `installer.mbt`'s
/// `value_prim`/`elem_head`/`inst_long` main entry が `Some("kv_map")` を見て `KvArg` を emit し、
/// `resolve.mbt`'s `build_result` が `AccumCell.accum == "kv_map"` を見て畳み結果を RObj にする
/// (merge と同じ「宣言をそのまま Entity.accum へ通す」経路、ここは受理するだけ)。
fn dec_multiple(j : Json) -> (Bool, String?, String?, String?) raise DecodeSkip {
  match j.j_bool() {
    Some(b) => return (b, None, None, None)
    None => ()
  }
  match j.j_str() {
    Some("append") => return (true, None, None, None)
    Some(other) => raise DecodeSkip("multiple preset '" + other + "'")
    None => ()
  }
  match j.j_obj() {
    Some(o) => {
      allowed_keys(o, ["accumulator", "separator", "collector"], "multiple")
      let accumulator = match jf_str(o, "accumulator") {
        Some("append") => None // 既定と同義 — Entity.accum への写しは ensure_entity が "append" にフォールバック
        Some("merge") => Some("merge")
        Some("kv_map") => Some("kv_map")
        Some(a) => raise DecodeSkip("multiple.accumulator '" + a + "'")
        None => None
      }
      let collector = match jf_str(o, "collector") {
        Some(c) =>
          if known_collector(c) {
            Some(c)
          } else {
            raise DecodeSkip(
              "multiple.collector '" + c + "' has no wired runtime yet",
            )
          }
        None => None
      }
      (true, jf_str(o, "separator"), collector, accumulator)
    }
    None => raise DecodeSkip("multiple is not a bool/string/object")
  }
}

///|
fn dec_export(j : Json) -> ExportKey {
  match j.j_str() {
    Some("") => EkNull
    Some(s) => EkKey(s)
    None => EkNull
  }
}

///|
fn dec_alias(o : Map[String, Json]) -> AliasDef raise DecodeSkip {
  allowed_keys(
    o,
    ["alias", "name", "short", "long", "deprecated", "type"],
    "alias",
  )
  let target = match jf_str(o, "alias") {
    Some(t) => t
    None => raise DecodeSkip("alias missing target")
  }
  let name = jf_str(o, "name")
  match name {
    Some(n) => check_reserved_name(n, "alias")
    None => ()
  }
  let short = dec_short(o)
  // DR-076 §2 flag 差し替え/補完の alias 側適用 (issue 2026-07-08 dec-alias-long-override-flag-
  // sugar-gap): decode はここでも canonical 側の dec_long と同じく wire の bool|array 二形を
  // `LongDecl` にそのまま写すだけ — 型依存の糖衣解釈は installer.mbt の desugar_aliases
  // (resolve_long 経由) が担う。
  let long_override : LongDecl? = match o.get("long") {
    Some(lj) => Some(dec_long(lj))
    None => None
  }
  let deprecated = bool_field(o, "deprecated", false)
  { target, name, short, long_override, deprecated }
}

///|
/// DR-055 value-enum 形式の or 枝を decode し、(1) enum 消費構造用の全 exact 値 (requires の有無を
/// 問わない — issue values-decode-support, BEnum の `dec_option` 呼び出しが使う) と (2) 制約用の
/// value_requires (requires を持つ枝だけ) の両方を1パスで返す。従来は (2) だけを返していたが、今回
/// values/or の消費意味論を合流させるにあたり同じ走査で (1) も一緒に収集するよう拡張した (二重
/// 実装を避ける)。
fn dec_or(
  j : Json,
  parent_name : String,
) -> (Array[String], Array[(String, String, Array[String])]) raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("or is not an array")
  }
  // MDR-004 §2: the capability gate that used to reject "seq"/"type" branches here is GONE — the
  // caller (`dec_option`) now shape-detects BEFORE calling `dec_or`, routing structural branches to
  // `dec_or_structural` instead. This function only ever sees the value-enum form now.
  // DR-055 §1 + DR-052 §値枝 id 直交: 各枝の tuple = (branch_id, exact_value, targets)。branch_id は
  // `id` フィールド (fixture の `id: "fmt_json"`) を採用、未指定なら parent_name にフォールバック
  // (parent 直属 value_requires と等価挙動)。
  let exacts : Array[String] = []
  let vrs : Array[(String, String, Array[String])] = []
  for e in a {
    let bo = match e.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("or branch is not an object")
    }
    allowed_keys(bo, ["exact", "id", "requires"], "or branch")
    let exact = match jf_str(bo, "exact") {
      Some(s) => s
      None =>
        raise DecodeSkip(
          "or branch missing 'exact' (only exact value枝 supported)",
        )
    }
    exacts.push(exact)
    let reqs = dec_strs(bo.get("requires"))
    if reqs.length() > 0 {
      let branch_id = jf_str(bo, "id").unwrap_or(parent_name)
      check_reserved_name(branch_id, "or branch")
      vrs.push((branch_id, exact, reqs))
    }
  }
  (exacts, vrs)
}

///|
/// MDR-004 kawaz 裁定 2026-07-08: auto `OrBranch.id` numbering for structural branches without an
/// explicit `"id"`. "採番 seq は decode 1 回のパーサ全体で単調増加... 一意なら何でもよい" — a single
/// monotonic counter for the whole decode run satisfies this; the `#` prefix keeps it out of user
/// namespace (fixture ids are plain strings like `"fmt_json"`, never `#`-prefixed).
let or_branch_seq : Array[Int] = [0]

///|
fn next_or_branch_id() -> String {
  let n = or_branch_seq[0]
  or_branch_seq[0] = n + 1
  "#" + n.to_string()
}

///|
/// DESIGN §5.3 `values` shorthand: a flat array of exact-match string literals (`["red","green",
/// "blue"]`). The seq-branch form (`"values": [..., [{"name":"r",...},...]]`, DESIGN §5.3 後半) is
/// OUT OF SCOPE for this issue (no target fixture exercises it) — a non-string element raises
/// DecodeSkip rather than silently degrading, so a future seq-branch fixture surfaces as a decode
/// gap instead of a wrong parse.
fn dec_values(j : Json) -> Array[String] raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("values is not an array")
  }
  let out : Array[String] = []
  for e in a {
    match e.j_str() {
      Some(s) => out.push(s)
      None =>
        raise DecodeSkip(
          "values element is not a string (seq-branch values form not supported)",
        )
    }
  }
  out
}

///|
/// Strict `Array[String]` decode for a factory config key that DR-061 §4 declares as `{"type":
/// "array", "items": "string"}` (e.g. `bool_parser`'s `true_values`/`false_values`, DR-074 §4) —
/// unlike `dec_strs`, no bare-string sugar (config schema says array, not `string | string[]`).
/// `type_name`/`field` are only for the DecodeSkip message.
fn dec_str_array(
  j : Json,
  type_name : String,
  field : String,
) -> Array[String] raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None =>
      raise DecodeSkip(
        "definitions.types[" +
        type_name +
        "].config." +
        field +
        " is not an array",
      )
  }
  let out : Array[String] = []
  for e in a {
    match e.j_str() {
      Some(s) => out.push(s)
      None =>
        raise DecodeSkip(
          "definitions.types[" +
          type_name +
          "].config." +
          field +
          " element is not a string",
        )
    }
  }
  out
}

///|
/// MDR-004 §2: shape-detect a JSON `"or"` array — `None` if it's the DR-055 value-enum form (every
/// branch has `"exact"`, handled by `dec_or` instead), `Some(branches)` if it's the STRUCTURAL
/// consumption-grammar form (any branch has `"seq"`/`"type"` — a multi-cell `{"seq":[...]}` branch
/// or a single-cell `{"type":..,"name":..}` branch, used verbatim as the branch object itself).
fn dec_or_structural(
  j : Json,
  shadows : Map[String, TypeShadow],
) -> Array[OrBranch]? raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("or is not an array")
  }
  let mut structural = false
  for e in a {
    match e.j_obj() {
      Some(bo) =>
        if has_key(bo, "seq") || has_key(bo, "type") {
          structural = true
        }
      None => ()
    }
  }
  if !structural {
    return None
  }
  let branches : Array[OrBranch] = []
  for e in a {
    let bo = match e.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("or branch is not an object")
    }
    let id = match jf_str(bo, "id") {
      Some(s) => {
        check_reserved_name(s, "or branch")
        s
      }
      None => next_or_branch_id()
    }
    let items : Array[ElemDef] = match bo.get("seq") {
      Some(sj) => {
        let sa = match sj.j_arr() {
          Some(x) => x
          None => raise DecodeSkip("or branch 'seq' is not an array")
        }
        let its : Array[ElemDef] = []
        for ij in sa {
          its.push(dec_or_leaf(ij, shadows))
        }
        its
      }
      // a single-cell branch IS the leaf object itself (no "seq" wrapper, DESIGN §1.2 裸配列 seq 糖衣
      // — wire form already normalizes bare-seq sugar, so here a missing "seq" key on a branch that
      // has "type"/"name" directly is exactly the 1-item case).
      None => [dec_or_leaf(e, shadows)]
    }
    branches.push({ id, items })
  }
  Some(branches)
}

///|
/// A leaf cell inside a structural `"or"` branch: `{"type":..,"name":..}`. Minimal — BCell only, no
/// long/short/env/etc (the shared trigger, if any, lives on the PARENT option's `long`, factored out
/// per the `variable-arity-ambiguous.json` wire form; an anonymous positional or-branch leaf has no
/// trigger at all).
fn dec_or_leaf(
  j : Json,
  shadows : Map[String, TypeShadow],
) -> ElemDef raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("or branch leaf is not an object")
  }
  allowed_keys(o, ["type", "name"], "or branch leaf")
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("or branch leaf missing 'name'")
  }
  check_reserved_name(name, "or branch leaf")
  // DR-089 §2: type 省略 = none の糖衣 (or branch leaf も他の要素種と同じ規約)。
  let (ty, int_round_from_shadow) = match jf_str(o, "type") {
    Some(t) =>
      match shadows.get(t) {
        Some(sh) => (sh.base, sh.int_round)
        None => (dec_ty(t), RError)
      }
    None => (TNone, RError)
  }
  pos(name, ty, int_round=int_round_from_shadow)
}

///|
fn dec_option(
  j : Json,
  shadows : Map[String, TypeShadow],
) -> DElem raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("option is not an object")
  }
  if has_key(o, "alias") {
    return DAlias(dec_alias(o))
  }
  allowed_keys(
    o,
    [
      "id", "name", "type", "long", "short", "env", "default", "global", "inherit",
      "inheritable", "multiple", "separator", "requires", "conflicts_with", "exclusive_group",
      "required", "export_key", "config_key", "deprecated", "or", "values", "piece_filters",
      "value_filters", "cell_filters", "ref", "repeat",
      // DR-090 §2: dd 専用の2軸拡張キー — 他 type では無意味だが、dd 分岐 (下) だけが読む
      // ("option" 共通 allowed_keys に足すのは他 wire 属性 (env/config_key 等) と同じ扱い方)。
       "match", "self",
      // codex 節目レビュー Major 1 (DESIGN §7.2「子要素は親の config を継承、上書き可能」/ DR-049
      // §4 要素単位 env_prefix 上書き): 要素単位の scope config override — `dec_option` 自身は
      // この値を消費しない (`allowed_keys` を通すためだけ)、実際の decode/merge は呼び出し元
      // `dec_definition` が `oj` を再読して行う (`dec_scope_config` の 2 段目呼び出し)。
       "config",
    ],
    "option",
  )
  let tystr = match jf_str(o, "type") {
    Some(t) => t
    None =>
      if has_key(o, "or") || has_key(o, "ref") || has_key(o, "values") {
        // DR-078 §1: a `ref` element's own consumption is replaced by the referenced template
        // (`elem_head`'s `Ref(r)` head, ty unused there) — same "type is moot" reasoning `or`
        // already gets. `values` gets the same default (DR-028 追記: values を持つ node は type
        // フィールドなしで enum 型を兼ねる) — DESIGN §5.3's `values` shorthand is string-literal-
        // only in this issue's scope (seq-branch values form not implemented), so the enum's own
        // values are always strings regardless of this default.
        "string"
      } else {
        // DR-089 §2: type 省略 = none の糖衣 (or/ref/values いずれも無い場合)。旧実装は
        // ここを DecodeSkip (type 必須) にしていたが、DR-089 で「無いものに勝手に値型をあてるのは
        // 手抜き」(kawaz) として default-typing 案が明示的に不採用になったのと対称に、旧
        // DecodeSkip も「無いものをエラー扱いする」誤りだった — 値空間が無いこと自体は正当な宣言。
        "none"
      }
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("option missing 'name'")
  }
  check_reserved_name(name, "option")
  // MDR-004 §2: "or" is shape-detected FIRST — the DR-055 value-enum form ({"exact":...} branches,
  // dec_or, parent name = branch-id フォールバック先) and the structural consumption-grammar form
  // (BOr, dec_or_structural) share the same JSON key but are otherwise unrelated (§5.3 values 正規形
  // vs §1 消費文法の枝)。
  let structural_or = match o.get("or") {
    Some(orj) => dec_or_structural(orj, shadows)
    None => None
  }
  // issue values-decode-support (DESIGN §5.3 "values は or のショートハンド" + team-lead 裁定
  // 2026-07-10「values と or (value-enum形式) の消費意味論を分岐させない」): `values` はここで
  // `or` value-enum 相当 (全 exact 値のリスト) へ正規化し、以降 `value_enum`/`value_requires` の
  // 決定を「values 由来」と「or 由来」で完全に同じ経路に流す — 糖衣と正規形で観測挙動が割れない
  // ようにする。`values` と `or` の同時指定は対象 fixture に無く未定義 (values を優先、無視した
  // `or` があれば下の `value_requires` 判定には現れない — 想定外の組合せなので検出はしない)。
  let (value_enum, value_requires) : (
    Array[String]?,
    Array[(String, String, Array[String])],
  ) = match structural_or {
    Some(_) => (None, [])
    None =>
      match o.get("values") {
        Some(vj) => (Some(dec_values(vj)), [])
        None =>
          match o.get("or") {
            Some(orj) => {
              let (exacts, vrs) = dec_or(orj, name)
              (Some(exacts), vrs)
            }
            None => (None, [])
          }
      }
  }
  if tystr == "dd" {
    // DR-090 §2: `match` (regex トリガ) / `self` (`"drop"` 既定 | `"keep"`)。`self` の語彙外文字列は
    // decode 時点で拒否 (綴りミスを黙って drop 扱いにしない、DR-054 の「構文の驚きは v1 Error」筋)。
    let match_ = jf_str(o, "match")
    let self_keep = match jf_str(o, "self") {
      Some("drop") | None => false
      Some("keep") => true
      Some(other) =>
        raise DecodeSkip("dd 'self' has unknown value '" + other + "'")
    }
    // DR-093 §2/§5: dd も required を持てる (`{"type":"dd","required":true}`、新規 wire 語彙ゼロ)。
    let required = bool_field(o, "required", false)
    return DOpt({ ..dd_marker(match_~, self_keep~, required~), name, })
  }
  // DR-061 §3: type shadow lookup — user 定義の type 名なら base Ty + parse 相 config を採用、
  // canonical 型名 (string/int/...) にフォールバック。help/config_file は語彙 keyword で shadow の
  // 適用対象外 (installer 語彙、DR-042)。
  let (
    ty,
    fail_action,
    config_file,
    int_round_from_shadow,
    base_prefix_from_shadow,
    bool_config_from_shadow,
  ) = match tystr {
    "help" => (TFlag, true, false, RError, false, bool_config_canonical())
    "config_file" => (TStr, false, true, RError, false, bool_config_canonical())
    _ =>
      match shadows.get(tystr) {
        Some(sh) =>
          (
            sh.base,
            false,
            false,
            sh.int_round,
            sh.allow_base_prefix,
            sh.bool_config,
          )
        None =>
          (dec_ty(tystr), false, false, RError, false, bool_config_canonical())
      }
  }
  // DR-071 §1 / kawaz 裁定 2026-07-08: decode は wire の bool|array 二形をそのまま `LongDecl` に写す
  // だけ — 糖衣展開・colon DSL 分類 (variants の分離を含む) は installer.mbt の `resolve_long` が
  // `normalize_option` から担う (下記 `opt(...)` は `variants` を渡さない = 常に [] のまま宣言層へ)。
  let long_decl : LongDecl = match o.get("long") {
    Some(lj) => dec_long(lj)
    None => LList([])
  }
  let short = dec_short(o)
  let env = dec_strs(o.get("env"))
  let default : Array[Value]? = match o.get("default") {
    Some(d) => Some(json_to_default_values(d))
    None => None
  }
  let global = bool_field(o, "global", false)
  let inherit_flag = bool_field(o, "inherit", false)
  let inheritable = bool_field(o, "inheritable", false)
  let (multiple, sep, coll, acc) = match o.get("multiple") {
    Some(m) => dec_multiple(m)
    None => (false, None, None, None)
  }
  let requires = dec_strs(o.get("requires"))
  let conflicts = dec_strs(o.get("conflicts_with"))
  let exclusive = dec_strs(o.get("exclusive_group"))
  let required = bool_field(o, "required", false)
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  let config_key : Array[String]? = match o.get("config_key") {
    Some(c) => Some(dec_strs(Some(c)))
    None => None
  }
  let deprecated = bool_field(o, "deprecated", false)
  let piece_filters = dec_filter_chain(o.get("piece_filters"))
  let value_filters = dec_filter_chain(o.get("value_filters"))
  let cell_filters = dec_filter_chain(o.get("cell_filters"))
  // DR-091 §3 (team-lead 裁定 2026-07-11 修正): `long_prefix`/`require_equal_separator` are NOT
  // element-level wire keys — the canonical source is `dec_definition`'s scope-level read (DESIGN
  // §7.2's sibling, "scope config" per DR-091 §3), which overrides every `ElemDef` this function
  // returns AFTER decode. An option JSON object carrying either key hits the `allowed_keys` reject
  // above (element-level override would be an un-specced vocabulary invention). `opt(...)` below
  // omits both — they keep `opt`'s defaults (`"--"`/`false`) here and get set for real by the
  // caller (`dec_definition`).
  let ref_ = jf_str(o, "ref")
  // DR-078 §1 option repeat (issue 2026-07-09-ref-template-result-shape, new capability): `repeat`
  // used to be positional-only (`dec_positional`'s own decode above) — mirrored here now that
  // installer.mbt's `inst_long` wires it into an option's satellite (`GreedyRepeat`, eval.mbt).
  let repeat : RepeatSpec? = match o.get("repeat") {
    Some(r) => Some(dec_repeat(r))
    None => None
  }
  DOpt({
    ..opt(
      name,
      ty,
      long=long_decl,
      short~,
      repeat~,
      env~,
      global~,
      inherit_=inherit_flag,
      inheritable~,
      multiple~,
      accumulator=acc,
      fail_action~,
      config_file~,
      config_key~,
      export_~,
      requires~,
      conflicts~,
      exclusive~,
      required~,
      value_requires~,
      default~,
      int_round=int_round_from_shadow,
      allow_base_prefix=base_prefix_from_shadow,
      bool_config=bool_config_from_shadow,
      piece_filters~,
      value_filters~,
      cell_filters~,
      ref_~,
      body=match structural_or {
        Some(branches) => BOr(branches)
        None =>
          match value_enum {
            Some(values) => BEnum(values)
            None => BCell
          }
      },
    ),
    separator: sep,
    collector: coll,
    deprecated,
  })
}

///|
fn dec_positional(
  j : Json,
  shadows : Map[String, TypeShadow],
) -> ElemDef raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("positional is not an object")
  }
  allowed_keys(
    o,
    [
      "id", "name", "type", "repeat", "optional", "multiple", "separator", "export_key",
      "config_key", "default", "positionals", "or", "piece_filters", "value_filters",
      "cell_filters", "ref", "env", "required", "requires",
      // codex 節目レビュー Major 1 (dec_option 側と同じ要素単位 scope config override、
      // 対称の positional 版)。
       "config",
    ],
    "positional",
  )
  // MDR-004 §2: "positionals" (named nested group, BGroup) and "or" (anonymous structural or,
  // BOr) are decoded via ElemBody now — the gates that used to reject these keys are GONE. A
  // positional's "or" is ALWAYS structural (there is no DR-055 value-enum-or concept for
  // positionals — that's an option-only constraint-declaration sugar, §5.3).
  match o.get("positionals") {
    Some(pj) => return dec_positional_group(o, pj, shadows)
    None => ()
  }
  match o.get("or") {
    Some(orj) =>
      match dec_or_structural(orj, shadows) {
        Some(branches) => return { ..pos("", TStr), body: BOr(branches) }
        None =>
          raise DecodeSkip(
            "positional 'or' has no structural branches (all-exact value-enum form is option-only, DR-055 §1 / §5.3)",
          )
      }
    None => ()
  }
  // DR-061 §3: positional も type shadow を consultation (dec_option と同型)。
  // DR-089 §2: type 省略 = none の糖衣 (旧実装は TStr を勝手にあてる default-typing だった —
  // DR-089 の「採用しなかった案」が明示的に否定するパターン。`ref` 付きの場合はそもそも ty が
  // 未使用 (elem_head の Ref(r) head、下の `dec_or_structural`/`positionals` 分岐同様) なので
  // TNone に変えても無害)。
  let (
    ty,
    int_round_from_shadow,
    base_prefix_from_shadow,
    bool_config_from_shadow,
  ) = match jf_str(o, "type") {
    Some(t) =>
      match shadows.get(t) {
        Some(sh) =>
          (sh.base, sh.int_round, sh.allow_base_prefix, sh.bool_config)
        None => (dec_ty(t), RError, false, bool_config_canonical())
      }
    None => (TNone, RError, false, bool_config_canonical())
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("positional missing 'name'")
  }
  check_reserved_name(name, "positional")
  let repeat : RepeatSpec? = match o.get("repeat") {
    Some(r) => Some(dec_repeat(r))
    None => None
  }
  let optional = bool_field(o, "optional", false)
  let (multiple, sep, coll, acc) = match o.get("multiple") {
    Some(m) => dec_multiple(m)
    None => (false, None, None, None)
  }
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  let config_key : Array[String]? = match o.get("config_key") {
    Some(c) => Some(dec_strs(Some(c)))
    None => None
  }
  let default : Array[Value]? = match o.get("default") {
    Some(d) => Some(json_to_default_values(d))
    None => None
  }
  let piece_filters = dec_filter_chain(o.get("piece_filters"))
  let value_filters = dec_filter_chain(o.get("value_filters"))
  let cell_filters = dec_filter_chain(o.get("cell_filters"))
  let ref_ = jf_str(o, "ref")
  // DR-088 (issue dr-088-positional-default-verification): positionals can declare `env` too
  // (Entity.env_key applies uniformly across options/positionals, `dec_option`'s same-named
  // field) — this was missing from the positional decoder entirely (`allowed_keys` rejected it
  // outright), a genuine decode gap surfaced by `positional-env-presence.json`.
  let env = dec_strs(o.get("env"))
  // DR-093 §1/§2/§5: positional も required を持てる (corpus/real-cli の
  // `{"name":"path","type":"string","required":true}` 実例が示す通り、option 限定ではない)。
  let required = bool_field(o, "required", false)
  // DR-093 §3/§5: positional も requires (他要素への依存) を持てる — die の骨格
  // (`{"name":"args","requires":["--"]}`) は requires のトリガ側が positional である実例。
  // option 側 (`dec_option`) は既に対応済みだったが positional 側は decode gap だった
  // (fixtures/constraints-parse/requires-dd-target.json が発見)。
  let requires = dec_strs(o.get("requires"))
  pos(
    name,
    ty,
    repeat~,
    optional~,
    multiple~,
    accumulator=acc,
    separator=sep,
    collector=coll,
    config_key~,
    export_~,
    ref_~,
    default~,
    int_round=int_round_from_shadow,
    allow_base_prefix=base_prefix_from_shadow,
    bool_config=bool_config_from_shadow,
    piece_filters~,
    value_filters~,
    env~,
    cell_filters~,
    required~,
    requires~,
  )
}

///|
/// MDR-004 §1/§3: a named group positional (`{"name":"xs","repeat":{...},"positionals":[...]}`) —
/// `BGroup(items)`. Inner items are decoded via `dec_positional` itself (recursive — an inner leaf
/// like transparent-seq's `k` is just a normal positional decode, `export_key:null` included).
fn dec_positional_group(
  o : Map[String, Json],
  pj : Json,
  shadows : Map[String, TypeShadow],
) -> ElemDef raise DecodeSkip {
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("positional (named group) missing 'name'")
  }
  check_reserved_name(name, "positional (named group)")
  let repeat : RepeatSpec? = match o.get("repeat") {
    Some(r) => Some(dec_repeat(r))
    None => None
  }
  let inner_arr = match pj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("positionals is not an array")
  }
  let items : Array[ElemDef] = []
  for ij in inner_arr {
    items.push(dec_positional(ij, shadows))
  }
  { ..pos(name, TStr, repeat~), body: BGroup(items) }
}

///|
/// DR-014 / DESIGN §7.2 (issue scope-config-object-gap): the resolved (post-inheritance) value of
/// every scope `config` key, threaded top-down through `dec_definition`/`dec_command`'s recursion —
/// this IS the "子要素は親の config を継承、上書き可能" hierarchy (DESIGN §7.2), realized as
/// "each scope merges its own `config` object over the value it received from its parent" rather
/// than a stored-on-`Definition` carrier (installer.mbt never reads a `Definition`-level config; the
/// resolved tuple gets baked onto each `ElemDef` the scope owns, same pattern DR-091 §3 established
/// for the original 2-field minimal implementation).
struct ScopeConfig {
  long_prefix : String
  short_prefix : String
  env_prefix : String
  auto_env : Bool
  allow_equal_separator : Bool
  short_combine : Bool
  require_equal_separator : Bool
} derive(Eq, Debug)

///|
/// The canonical config, in effect at the root scope when no `config` object is ever written
/// (equivalent to every key's DESIGN §7.2 default) — matches DR-091 §3's pre-issue defaults exactly
/// (`long_prefix:"--"`, `require_equal_separator:false`) for the 2 fields that already existed.
fn default_scope_config() -> ScopeConfig {
  {
    long_prefix: "--",
    short_prefix: "-",
    env_prefix: "",
    auto_env: false,
    allow_equal_separator: true,
    short_combine: true,
    require_equal_separator: false,
  }
}

///|
/// Merges THIS scope's own `config` object (JSON, may be partly or fully absent) over `parent`
/// (the already-resolved config the enclosing scope handed down) — a key ABSENT from `co` inherits
/// `parent`'s resolved value; a key PRESENT overrides it. This single merge step, applied once per
/// scope in the top-down recursion, is the entire "階層継承可能" mechanism DR-014 specifies — no
/// separate reconciliation pass is needed because each scope only ever sees its own JSON object and
/// the one already-merged value from above.
fn dec_scope_config(
  co : Map[String, Json],
  parent : ScopeConfig,
) -> ScopeConfig raise DecodeSkip {
  allowed_keys(
    co,
    [
      "long_prefix", "short_prefix", "env_prefix", "auto_env", "allow_equal_separator",
      "short_combine", "require_equal_separator",
    ],
    "definition.config",
  )
  let long_prefix = match jf_str(co, "long_prefix") {
    Some(s) => s
    None => parent.long_prefix
  }
  let short_prefix = match jf_str(co, "short_prefix") {
    Some(s) => s
    None => parent.short_prefix
  }
  let env_prefix = match jf_str(co, "env_prefix") {
    Some(s) => s
    None => parent.env_prefix
  }
  let auto_env = bool_field(co, "auto_env", parent.auto_env)
  let allow_equal_separator = bool_field(
    co,
    "allow_equal_separator",
    parent.allow_equal_separator,
  )
  let short_combine = bool_field(co, "short_combine", parent.short_combine)
  let require_equal_separator = bool_field(
    co,
    "require_equal_separator",
    parent.require_equal_separator,
  )
  {
    long_prefix,
    short_prefix,
    env_prefix,
    auto_env,
    allow_equal_separator,
    short_combine,
    require_equal_separator,
  }
}

///|
/// DR-091 §3 自然な帰結チェックを 1 箇所に集約 (codex 節目レビュー Major 1 監査時点で発見: 元々
/// `dec_definition` の SCOPE レベルにだけインライン展開されていた — 要素単位 config override
/// (DR-049 §4「その要素の config で env_prefix:"" を上書きする」で明示される、DESIGN §7.2「子要素」
/// は command だけでなく option/positional も含む) を追加する以上、同じ不整合はスコープ単位の
/// resolved config だけでなく、要素単位で resolved した config でも起こりうる (例: 要素が独自に
/// `long_prefix:""` を上書きしつつ `require_equal_separator` を明示しない場合、親から継承した値が
/// false のままだと同じ「空 prefix が素 operand と衝突する」問題が要素単位で再現する) — checker を
/// 関数化して両呼び出し点 (スコープ解決直後・要素ごとのマージ直後) から同一ロジックで検証する。
///
/// `require_equal_separator: true` × `allow_equal_separator: false` の矛盾チェックは、ここには
/// 無い — installer 層 `collect_eq_separator_conflict` (installer.mbt) へ移設済み (DESIGN §7.2
/// が definition-error と規範化、decode 層の `DecodeSkip` では query:definition_error fixture で
/// element 別に pin できないため — `collect_eq_separator_conflict` の doc comment 参照)。
fn validate_scope_config(cfg : ScopeConfig) -> Unit raise DecodeSkip {
  // DR-091 §3 "単独の空 prefix は未定義動作のまま": `long_prefix: ""` は
  // `require_equal_separator: true` との併用時のみ合法 — 空 prefix 単独ならこの scope の
  // SPACE-FORM main entry が ANY トークンにマッチしてしまい、素 operand と衝突する
  // (`ElemDef.require_equal_separator` の doc comment 参照)。definition-error として決定的に
  // reject (`collect_unsupported_accum_update` 等と同じ「静的、実行時でない」姿勢)。
  if cfg.long_prefix == "" && !cfg.require_equal_separator {
    raise DecodeSkip(
      "long_prefix: \"\" requires require_equal_separator: true (DR-091 §3)",
    )
  }
}

///|
/// "_" 連結 (DR-049 §3 auto_env 名導出の連結セパレータ)。空 segment は呼び出し側が既に除外している
/// 前提 (`auto_env_name` — env_prefix 未設定時に prefix segment 自体を積まない、DR-049 §3
/// 「env_prefix 未設定なら prefix 部を省く」)。
fn join_us(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in items {
    if !first {
      buf.write_string("_")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

///|
/// DR-049 §3 auto_env 名導出: `UPPER(env_prefix) "_" UPPER(scope_path を "_" 連結) "_" UPPER(name)`。
/// `env_prefix` 未設定 (`""`) なら prefix segment を省く (§3 明記)。`name` は wire format の
/// snake_case (DR-022) なので変換は uppercase のみ (kebab/camel からの変換規則は定義しない、§3)。
fn auto_env_name(
  env_prefix : String,
  scope_path : Array[String],
  name : String,
) -> String {
  let segs : Array[String] = []
  if env_prefix != "" {
    segs.push(env_prefix.to_upper())
  }
  for s in scope_path {
    segs.push(s.to_upper())
  }
  segs.push(name.to_upper())
  join_us(segs)
}

///|
/// DR-049 §3/§4: applies THIS scope's resolved `env_prefix`/`auto_env` to one option/positional
/// element. Two independent effects (§4「明示 env: が auto_env に優先する」means these are mutually
/// exclusive per element, not layered):
/// - explicit `env:` (§4): env_prefix prepends to EVERY declared env key (`UPPER(env_prefix) + "_"
///   + <value>` — the value itself is left as the author wrote it, only the prefix segment is
///   uppercased per §3's "UPPER(env_prefix)"), UNLESS env_prefix is `""` (§3 "未設定なら prefix 部
///   を省く" — the element is left byte-for-byte unchanged, preserving every pre-issue fixture that
///   declares `env:` with no scope config at all).
/// - no explicit `env:` + `auto_env: true` (§3): derives the full name via `auto_env_name` — gated to
///   `BCell` bodies only ("値セル持ち要素", DESIGN §7.2 line 842 — a `BOr`/`BGroup`/`BEnum` wrapper
///   has no single value slot for a scalar env lookup to bind to, matcher/leaf-level auto_env is not
///   specified anywhere and would be an invented extension).
fn apply_env_config(
  e : ElemDef,
  env_prefix : String,
  auto_env : Bool,
  scope_path : Array[String],
) -> ElemDef {
  if e.env.length() > 0 {
    if env_prefix == "" {
      e
    } else {
      let prefixed : Array[String] = []
      for v in e.env {
        prefixed.push(env_prefix.to_upper() + "_" + v)
      }
      { ..e, env: prefixed }
    }
  } else if auto_env && e.body is BCell {
    { ..e, env: [auto_env_name(env_prefix, scope_path, e.name)] }
  } else {
    e
  }
}

///|
fn dec_command(
  j : Json,
  shadows : Map[String, TypeShadow],
  parent_config : ScopeConfig,
  scope_path : Array[String],
) -> DCmd raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("command is not an object")
  }
  if has_key(o, "alias") {
    return DCmdAlias(dec_alias(o))
  }
  allowed_keys(
    o,
    [
      "type", "name", "options", "positionals", "commands", "export_key",
      // DR-014 / DESIGN §7.2 / DR-091 §3: a command's own object IS its Definition's `o`
      // (`dec_definition` is called with THIS SAME map below) — so `config` is legal here too.
       "config",
    ],
    "command",
  )
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("command missing 'name'")
  }
  check_reserved_name(name, "command")
  // 子コマンドの definition は親の shadows を継承する (DR-061 は scope 継承を規定していないが、
  // slice実装は fixture が命令的に flat な type shadow を宣言するだけなので親→子への単純伝搬で足りる)
  //
  // DR-014 階層継承 / DR-049 §3 scope_path: この command 自身の name を scope_path に足して子へ
  // 渡す — auto_env のフル修飾名導出 (DR-049 §3「スコープパスはフル修飾」) が使う。
  let body = dec_definition(
    o,
    shadows~,
    parent_config~,
    scope_path=scope_path + [name],
  )
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  DCommand({ name, body, export_key: export_ })
}

///|
fn dec_definition(
  o : Map[String, Json],
  shadows? : Map[String, TypeShadow] = Map([]),
  parent_config? : ScopeConfig = default_scope_config(),
  scope_path? : Array[String] = [],
) -> Definition raise DecodeSkip {
  // DR-014 / DESIGN §7.2 (issue scope-config-object-gap; supersedes DR-091 §3's original 2-field-
  // only, non-inheriting scope config): この呼び出しの `o` (root definition object、または 1つの
  // command の own definition object — `dec_command` が自分の `o` をそのまま渡す) が持つ
  // `config: {long_prefix, short_prefix, env_prefix, auto_env, allow_equal_separator, short_combine,
  // require_equal_separator}` (DESIGN §7.2 の wire 形そのもの) を `parent_config` (呼び出し元から
  // 継承した既解決値) の上に `dec_scope_config` でマージする — 明示したキーだけ上書き、省略した
  // キーは親の値をそのまま継承する (DESIGN §7.2「子要素は親の config を継承、上書き可能」)。
  // `config` 自体を省略したスコープは `parent_config` をそのまま使う (= 何も上書きしない、継承の
  // 恒等射)。ルートスコープの `parent_config` 既定は `default_scope_config()` (DR-091 §3 の
  // pre-issue 既定と同一値)。
  let config = match o.get("config") {
    Some(cj) => {
      let co = match cj.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("config is not an object")
      }
      dec_scope_config(co, parent_config)
    }
    None => parent_config
  }
  validate_scope_config(config)
  let options : Array[ElemDef] = []
  let positionals : Array[ElemDef] = []
  let commands : Array[CommandDef] = []
  let aliases : Array[AliasDef] = []
  match o.get("options") {
    Some(arr) => {
      let a = match arr.j_arr() {
        Some(x) => x
        None => raise DecodeSkip("options is not an array")
      }
      for oj in a {
        match dec_option(oj, shadows) {
          DOpt(e) => {
            // codex 節目レビュー Major 1 (DR-049 §4「その要素の config で env_prefix:"" を上書きする
            // (DR-014 の階層継承で要素単位の上書きが可能)」/ DESIGN §7.2「子要素は親の config を
            // 継承、上書き可能」の『子要素』は command scope に限らない): `dec_option` は要素の生
            // JSON を `allowed_keys` 済み `Map[String, Json]` として保持しないので、要素単位の
            // `config` はここ (呼び出し元) で `oj` を直接再読して取り出す — `dec_scope_config` を
            // このスコープの `config` を親として要素の `config` に適用すれば、既存の階層マージ
            // ロジックをそのまま要素レベルへ 1 段延長できる (別実装を持たない)。
            let elem_config = match oj.j_obj() {
              Some(oo) =>
                match oo.get("config") {
                  Some(ecj) => {
                    let eco = match ecj.j_obj() {
                      Some(x) => x
                      None => raise DecodeSkip("option config is not an object")
                    }
                    let merged = dec_scope_config(eco, config)
                    validate_scope_config(merged)
                    merged
                  }
                  None => config
                }
              None => config // 到達不能 (dec_option が既に object であることを検証済み)
            }
            options.push(
              apply_env_config(
                {
                  ..e,
                  long_prefix: elem_config.long_prefix,
                  short_prefix: elem_config.short_prefix,
                  allow_equal_separator: elem_config.allow_equal_separator,
                  short_combine: elem_config.short_combine,
                  require_equal_separator: elem_config.require_equal_separator,
                },
                elem_config.env_prefix,
                elem_config.auto_env,
                scope_path,
              ),
            )
          }
          DAlias(al) => aliases.push(al)
        }
      }
    }
    None => ()
  }
  match o.get("positionals") {
    Some(arr) => {
      let a = match arr.j_arr() {
        Some(x) => x
        None => raise DecodeSkip("positionals is not an array")
      }
      for pj in a {
        let e = dec_positional(pj, shadows)
        // Major 1 と同じ要素単位 override、positional 版 (DESIGN §7.2「子要素」の対称範囲)。
        let elem_config = match pj.j_obj() {
          Some(po) =>
            match po.get("config") {
              Some(ecj) => {
                let eco = match ecj.j_obj() {
                  Some(x) => x
                  None => raise DecodeSkip("positional config is not an object")
                }
                let merged = dec_scope_config(eco, config)
                validate_scope_config(merged)
                merged
              }
              None => config
            }
          None => config // 到達不能 (dec_positional が既に object であることを検証済み)
        }
        positionals.push(
          apply_env_config(
            {
              ..e,
              long_prefix: elem_config.long_prefix,
              short_prefix: elem_config.short_prefix,
              allow_equal_separator: elem_config.allow_equal_separator,
              short_combine: elem_config.short_combine,
              require_equal_separator: elem_config.require_equal_separator,
            },
            elem_config.env_prefix,
            elem_config.auto_env,
            scope_path,
          ),
        )
      }
    }
    None => ()
  }
  match o.get("commands") {
    Some(arr) => {
      let a = match arr.j_arr() {
        Some(x) => x
        None => raise DecodeSkip("commands is not an array")
      }
      for cj in a {
        match dec_command(cj, shadows, config, scope_path) {
          DCommand(c) => commands.push(c)
          DCmdAlias(al) => aliases.push(al)
        }
      }
    }
    None => ()
  }
  { options, positionals, commands, aliases }
}

///|
fn dec_argv(cj : Map[String, Json]) -> Array[String] raise DecodeSkip {
  let aj = match cj.get("argv") {
    Some(x) => x
    None => raise DecodeSkip("case missing 'argv'")
  }
  let a = match aj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("argv is not an array")
  }
  let out : Array[String] = []
  for t in a {
    match t.j_str() {
      Some(s) => out.push(s)
      None => raise DecodeSkip("argv element is not a string")
    }
  }
  out
}

///|
fn dec_case(cj : Json) -> DCase raise DecodeSkip {
  let co = match cj.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("case is not an object")
  }
  allowed_keys(
    co,
    ["id", "argv", "expect", "env", "config", "config_files", "why"],
    "case",
  )
  let argv = dec_argv(co)
  let id = jf_str(co, "id").unwrap_or("")
  let expect = match co.get("expect") {
    Some(e) => e
    None => raise DecodeSkip("case missing 'expect'")
  }
  let eo = match expect.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("expect is not an object")
  }
  let outcome = match jf_str(eo, "outcome") {
    Some(o) =>
      if o == "success" || o == "failure" || o == "ambiguous" {
        o
      } else {
        raise DecodeSkip("outcome '" + o + "'")
      }
    None => raise DecodeSkip("expect missing 'outcome'")
  }
  let env : Map[String, String] = Map([])
  match co.get("env") {
    Some(ej) => {
      let eobj = match ej.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("case env is not an object")
      }
      for k, v in eobj {
        match v.j_str() {
          Some(s) => env.set(k, s)
          None => raise DecodeSkip("case env value is not a string")
        }
      }
    }
    None => ()
  }
  let cfg = match co.get("config") {
    Some(cjj) => CfgObj(json_to_configval(cjj))
    None =>
      match co.get("config_files") {
        Some(fj) =>
          match fj.j_obj() {
            Some(fo) => {
              let files : Array[(String, ConfigVal)] = []
              for k, v in fo {
                files.push((k, json_to_configval(v)))
              }
              CfgFiles(files)
            }
            None => NoCfg
          }
        None => NoCfg
      }
  }
  let has_sources = has_key(eo, "sources")
  let resolve = has_sources ||
    has_key(co, "env") ||
    (match cfg {
      NoCfg => false
      _ => true
    })
  let exp_effects = match eo.get("effects") {
    Some(x) => Some(exp_effects_str(x))
    None => None
  }
  let exp_result = match eo.get("result") {
    Some(x) => Some(exp_result_str(x))
    None => None
  }
  let (exp_errors, exp_errors_with_reason, exp_errors_with_path) = match
    eo.get("errors") {
    Some(x) => {
      let (s, wr, wp) = exp_errors_decode(x)
      (Some(s), wr, wp)
    }
    None => (None, false, false)
  }
  let exp_interps = match eo.get("interpretations") {
    Some(x) => Some(dec_interps(x))
    None => None
  }
  let exp_warnings = match eo.get("warnings") {
    Some(x) => Some(exp_warnings_str(x))
    None => None
  }
  let exp_sources = if has_sources {
    Some(exp_sources_str(eo.get("sources").unwrap()))
  } else {
    None
  }
  let (fired_cmp, fired_exp) = if outcome == "failure" &&
    has_key(eo, "fired_action") {
    (true, jf_str(eo, "fired_action"))
  } else {
    (false, None)
  }
  // spec issue conformance-tried-triggers-help-entry-fields: help_entry is opt-in on failure OR
  // ambiguous (DR-053 §4 material — both outcomes can carry a selected/discoverable help entry).
  let (help_cmp, help_exp) = if (outcome == "failure" || outcome == "ambiguous") &&
    has_key(eo, "help_entry") {
    (true, jf_str(eo, "help_entry"))
  } else {
    (false, None)
  }
  // tried_triggers is opt-in on failure only (DR-053 §4 material tied to the failure position —
  // ambiguous has no single failure position to derive it from). Projected to the SAME sorted
  // `{a,b,c}` string the live Outcome comparison uses, at decode time — a plain String compare
  // at the comparison site, matching every other set-compared face.
  let (tried_cmp, tried_exp) = if outcome == "failure" &&
    has_key(eo, "tried_triggers") {
    (true, Some(proj_tried_triggers(dec_strs(eo.get("tried_triggers")))))
  } else {
    (false, None)
  }
  {
    argv,
    id,
    outcome,
    exp_effects,
    exp_result,
    exp_errors,
    exp_errors_with_reason,
    exp_errors_with_path,
    exp_interps,
    exp_warnings,
    exp_sources,
    fired_cmp,
    fired_exp,
    help_cmp,
    help_exp,
    tried_cmp,
    tried_exp,
    resolve,
    env,
    cfg,
  }
}

// ── definition_error path (DR-082) ─────────────────────────────────────────────

///|
/// DR-082 §1: `query: "definition_error"` fixture の 1 case — DR-054 §4 の `parse_definition()`
/// 返値をそのまま転用する。`argv` は無い (定義の静的検査であり実行しない)。比較対象は
/// element+kind の組の集合のみ (message/hint はレンダラ管轄なので比較しない、DR-082 §1 — parse
/// fixture の `errors` が message を比較しないのと同流儀)。`exp_errors` は `deferrs_str` と同じ
/// ソート済み "element/kind" 連結表現なので、実行時にそのまま文字列比較できる。
struct DDefErrorCase {
  id : String
  exp_errors : String
}

///|
struct DDefErrorFixture {
  def : Definition
  registry : Map[String, Node]
  cases : Array[DDefErrorCase]
}

///|
fn dec_def_error_case(cj : Json) -> DDefErrorCase raise DecodeSkip {
  let co = match cj.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("case is not an object")
  }
  allowed_keys(co, ["id", "why", "expect"], "definition_error case")
  let id = match jf_str(co, "id") {
    Some(s) => s
    None => raise DecodeSkip("case missing 'id'")
  }
  let eo = match co.get("expect") {
    Some(x) =>
      match x.j_obj() {
        Some(o) => o
        None => raise DecodeSkip("expect is not an object")
      }
    None => raise DecodeSkip("case missing 'expect'")
  }
  allowed_keys(eo, ["outcome", "errors"], "definition_error case's expect")
  match jf_str(eo, "outcome") {
    Some("definition-error") => ()
    Some(o) =>
      raise DecodeSkip("expect.outcome '" + o + "' is not 'definition-error'")
    None => raise DecodeSkip("expect missing 'outcome'")
  }
  let errsj = match eo.get("errors") {
    Some(x) => x
    None => raise DecodeSkip("expect missing 'errors'")
  }
  let arr = match errsj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("expect.errors is not an array")
  }
  let items : Array[String] = []
  for ej in arr {
    let ejo = match ej.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("expect.errors entry is not an object")
    }
    allowed_keys(
      ejo,
      ["element", "kind"],
      "definition_error case's expect.errors entry",
    )
    let element = match jf_str(ejo, "element") {
      Some(s) => s
      None => raise DecodeSkip("errors entry missing 'element'")
    }
    let kind = match jf_str(ejo, "kind") {
      Some(s) => s
      None => raise DecodeSkip("errors entry missing 'kind'")
    }
    items.push(element + "/" + kind)
  }
  sort_items(items)
  { id, exp_errors: join_comma(items) }
}

///|
/// `dec_fixture` (query="parse") と対照的に、ここでは `parse_definition` を呼ばない — definition_
/// error fixture の主旨は「parse_definition が Err を返すこと」自体を検証することなので、
/// `dec_fixture` のように `Err` を即 `DecodeSkip` してしまうと本題を検証できなくなる
/// (`dec_fixture`'s `"definition rejected: ..."` 分岐と対照)。`definition`/`definitions` の decode
/// (dec_definition/dec_types/dec_templates) は "parse" と同じ経路を再利用する — 検証差分はこの後の
/// `parse_definition` 呼び出しタイミング (fixture decode 時ではなく case 実行時) だけ。
fn dec_definition_error_fixture(j : Json) -> DDefErrorFixture raise DecodeSkip {
  let top = match j.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  let defj = match top.get("definition") {
    Some(d) => d
    None => raise DecodeSkip("missing 'definition'")
  }
  let defo = match defj.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("definition is not an object")
  }
  allowed_keys(
    defo,
    [
      "options", "positionals", "commands", "definitions",
      // DR-091 §3 (scope config, DESIGN §7.2 の兄弟): `dec_definition` が読む nested config object。
       "config",
    ],
    "definition",
  )
  let registry : Map[String, Node] = Map([])
  let shadows = match defo.get("definitions") {
    Some(dj) => {
      let d = match dj.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("definitions is not an object")
      }
      allowed_keys(d, ["types", "templates"], "definitions")
      let ts = match d.get("types") {
        Some(tj) => dec_types(tj)
        None => Map([])
      }
      match d.get("templates") {
        Some(tmplj) => dec_templates(tmplj, ts, registry)
        None => ()
      }
      ts
    }
    None => Map([])
  }
  let def = dec_definition(defo, shadows~)
  let casesj = match top.get("cases") {
    Some(c) => c
    None => raise DecodeSkip("missing 'cases'")
  }
  let carr = match casesj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("cases is not an array")
  }
  let cases : Array[DDefErrorCase] = []
  for cj in carr {
    cases.push(dec_def_error_case(cj))
  }
  { def, registry, cases }
}

///|
/// DR-082 §1: run `parse_definition` and compare its `Err` (element+kind set) against the fixture's
/// expectation. An unexpected `Ok` (the definition was NOT rejected) is itself a mismatch —
/// `render_outcome`-style "EXPECTED-*" convention mirrors the parse-path runner's diagnostics.
fn run_definition_error(fx : DDefErrorFixture, c : DDefErrorCase) -> String {
  match parse_definition(fx.def, full_installers(), registry=fx.registry) {
    Ok(_) => "EXPECTED-DEFINITION-ERROR got=ok"
    Err(errs) => {
      let got = deferrs_str(errs)
      if got == c.exp_errors {
        "PASS"
      } else {
        "errors got=\{got} want=\{c.exp_errors}"
      }
    }
  }
}

///|
fn dec_fixture(j : Json) -> DecodedFixture raise DecodeSkip {
  let top = match j.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  match jf_str(top, "query") {
    Some("parse") => ()
    Some(q) => raise DecodeSkip("query '" + q + "' (parse/lower only)")
    None => raise DecodeSkip("missing 'query'")
  }
  let defj = match top.get("definition") {
    Some(d) => d
    None => raise DecodeSkip("missing 'definition'")
  }
  let defo = match defj.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("definition is not an object")
  }
  // DR-061 §3 configurable factory: `definitions.types` を許容し、その中身を shadow map に decode。
  // shadow は dec_definition に thread されて type 名解決で consultation される。
  // DR-078 §1: `definitions.templates` (共有消費文法、id→Node) も同じ `definitions` オブジェクトの
  // 区分として許容し、`registry` (parse_definition の ref 解決空間) を事前に埋める — types (shadow
  // map) とは別の受け皿 (§2: templates は外部 registry を持たない唯一の区分、クロージャなしの純構造)。
  allowed_keys(
    defo,
    [
      "options", "positionals", "commands", "definitions",
      // DR-091 §3 (scope config, DESIGN §7.2 の兄弟): `dec_definition` が読む nested config object。
       "config",
    ],
    "definition",
  )
  let registry : Map[String, Node] = Map([])
  let shadows = match defo.get("definitions") {
    Some(dj) => {
      let d = match dj.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("definitions is not an object")
      }
      allowed_keys(d, ["types", "templates"], "definitions")
      let ts = match d.get("types") {
        Some(tj) => dec_types(tj)
        None => Map([])
      }
      match d.get("templates") {
        Some(tmplj) => dec_templates(tmplj, ts, registry)
        None => ()
      }
      ts
    }
    None => Map([])
  }
  let def = dec_definition(defo, shadows~)
  let scope = match parse_definition(def, full_installers(), registry~) {
    Ok(sc) => sc
    Err(errs) => raise DecodeSkip("definition rejected: " + deferrs_str(errs))
  }
  let ekmap = build_export_map(def)
  let casesj = match top.get("cases") {
    Some(c) => c
    None => raise DecodeSkip("missing 'cases'")
  }
  let carr = match casesj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("cases is not an array")
  }
  let cases : Array[DCase] = []
  for cj in carr {
    cases.push(dec_case(cj))
  }
  { scope, registry, ekmap, cases }
}

// ── lower path ────────────────────────────────────────────────────────────────

///|
struct DecodedLower {
  def : Definition
  order : Array[Installer]
  want : LSec
}

///|
fn dec_installer(name : String) -> Installer raise DecodeSkip {
  for i in full_installers() {
    if owned_vocab(i) == name {
      return i
    }
  }
  raise DecodeSkip("unknown installer '" + name + "'")
}

///|
fn dec_installers(top : Map[String, Json]) -> Array[Installer] raise DecodeSkip {
  match top.get("installers") {
    None => full_installers()
    Some(j) =>
      match j.j_arr() {
        None => full_installers()
        Some(a) => {
          let out : Array[Installer] = []
          for e in a {
            match e.j_str() {
              Some(s) => out.push(dec_installer(s))
              None => raise DecodeSkip("installers[] element is not a string")
            }
          }
          out
        }
      }
  }
}

///|
fn req_field(o : Map[String, Json], key : String) -> String raise DecodeSkip {
  match jf_str(o, key) {
    Some(s) => s
    None => raise DecodeSkip("golden node missing string field '" + key + "'")
  }
}

///|
fn dec_ref_link(
  o : Map[String, Json],
  what : String,
) -> String raise DecodeSkip {
  allowed_keys(o, ["ref", "link"], what)
  let r = req_field(o, "ref")
  let l = req_field(o, "link")
  if l != r {
    raise DecodeSkip(
      what +
      " has ref≠link (unrepresentable in 断面: ref=" +
      r +
      " link=" +
      l +
      ")",
    )
  }
  r
}

///|
fn dec_gitem(j : Json) -> GItem raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("greedy item is not an object")
  }
  if has_key(o, "scope") {
    allowed_keys(o, ["exact", "scope"], "golden command subtree")
    let name = req_field(o, "exact")
    let so = match o.get("scope").unwrap().j_obj() {
      Some(x) => x
      None => raise DecodeSkip("command 'scope' is not an object")
    }
    return GCmd(name, dec_lsec(so))
  }
  if has_key(o, "matcher") {
    allowed_keys(o, ["matcher", "entries"], "golden matcher")
    let kind = req_field(o, "matcher")
    let entries : Array[(String, String)] = []
    match o.get("entries") {
      Some(ej) =>
        match ej.j_obj() {
          Some(eo) =>
            for k, v in eo {
              match v.j_str() {
                Some(nm) => entries.push((k, nm))
                None => raise DecodeSkip("matcher entry value is not a string")
              }
            }
          None => raise DecodeSkip("matcher 'entries' is not an object")
        }
      None => raise DecodeSkip("matcher missing 'entries'")
    }
    return GMatch(kind, entries)
  }
  if has_key(o, "seq") {
    allowed_keys(o, ["seq"], "golden seq satellite")
    let sa = match o.get("seq").unwrap().j_arr() {
      Some(x) => x
      None => raise DecodeSkip("greedy seq is not an array")
    }
    if sa.length() != 2 {
      raise DecodeSkip("greedy seq satellite is not [exact, ref]")
    }
    let trig = match sa[0].j_obj() {
      Some(x) => {
        allowed_keys(x, ["exact"], "golden seq trigger")
        req_field(x, "exact")
      }
      None => raise DecodeSkip("greedy seq[0] is not an object")
    }
    let refn = match sa[1].j_obj() {
      Some(x) => dec_ref_link(x, "golden seq value cell")
      None => raise DecodeSkip("greedy seq[1] is not an object")
    }
    return GSeqSat(trig, refn)
  }
  if has_key(o, "value") {
    allowed_keys(o, ["exact", "value", "link"], "golden set descriptor")
    return GSet(
      req_field(o, "exact"),
      json_to_value(o.get("value").unwrap()),
      req_field(o, "link"),
    )
  }
  // DR-045 effect descriptor (`{exact, link, effect: {op, transform?, args?}}`) — the non-Set ops
  // (default/unset/empty/update, DR-011/077) that lower to `Seq([Exact, EffMark])` (see the
  // `[Exact(t), EffMark(n, op)] => GEff(t, n, op)` projection below). No `lower fixture` used this
  // shape before DR-077 (every prior lowering fixture only exercised Set), so this decode path is
  // new — added for count's `:update:increment` lowering fixtures, but generic over all 4 non-set
  // ops.
  if has_key(o, "effect") {
    allowed_keys(o, ["exact", "link", "effect"], "golden effect descriptor")
    let ex = req_field(o, "exact")
    let link = req_field(o, "link")
    let effo = match o.get("effect").unwrap().j_obj() {
      Some(x) => x
      None => raise DecodeSkip("effect is not an object")
    }
    return GEff(ex, link, dec_eff_op(effo))
  }
  allowed_keys(o, ["exact"], "golden greedy exact")
  GExact(req_field(o, "exact"))
}

///|
/// DR-045 op vocab (`set`/`default`/`unset`/`empty`) + DR-077 §1's 5th op (`update`, which additionally
/// carries a `transform` name + optional `args`). `set` is accepted for completeness even though
/// GSet's dedicated `{value, link}` shorthand is the normal spelling for it in a fixture.
fn dec_eff_op(o : Map[String, Json]) -> EffectOp raise DecodeSkip {
  let opstr = match jf_str(o, "op") {
    Some(s) => s
    None => raise DecodeSkip("effect missing 'op'")
  }
  match opstr {
    "set" => Set
    "default" => Default
    "unset" => Unset
    "empty" => Empty
    "update" => {
      let transform = match jf_str(o, "transform") {
        Some(t) => t
        None => raise DecodeSkip("update effect missing 'transform'")
      }
      let args : Array[String] = match o.get("args") {
        Some(aj) =>
          match aj.j_arr() {
            Some(a) => {
              let r : Array[String] = []
              for e in a {
                match e.j_str() {
                  Some(s) => r.push(s)
                  None =>
                    raise DecodeSkip(
                      "update effect args element is not a string",
                    )
                }
              }
              r
            }
            None => raise DecodeSkip("update effect 'args' is not an array")
          }
        None => []
      }
      Update(transform, args)
    }
    other => raise DecodeSkip("unrecognized effect op '" + other + "'")
  }
}

///|
fn dec_pos_tnode(j : Json) -> TNode raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("positional node is not an object")
  }
  if has_key(o, "link") {
    return TRefEnt(dec_ref_link(o, "positional entity ref"))
  }
  match jf_str(o, "ref") {
    Some(k) => {
      allowed_keys(o, ["ref", "optional"], "positional template ref")
      TRefTmpl(canon_tmpl(k), bool_field(o, "optional", false))
    }
    None => raise DecodeSkip("unrecognized positional node")
  }
}

///|
fn dec_tmpl_body(j : Json) -> TNode raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("template body is not an object")
  }
  if has_key(o, "seq") {
    allowed_keys(o, ["seq"], "template seq")
    let sa = match o.get("seq").unwrap().j_arr() {
      Some(x) => x
      None => raise DecodeSkip("template seq is not an array")
    }
    let items : Array[TNode] = []
    for e in sa {
      items.push(dec_tmpl_body(e))
    }
    return TSeq(items)
  }
  if has_key(o, "link") {
    return TRefEnt(dec_ref_link(o, "template entity ref"))
  }
  if has_key(o, "ref") {
    allowed_keys(o, ["ref", "optional"], "template ref")
    return TRefTmpl(
      canon_tmpl(req_field(o, "ref")),
      bool_field(o, "optional", false),
    )
  }
  allowed_keys(o, ["exact"], "template literal")
  TExact(req_field(o, "exact"))
}

///|
fn dec_lent(name : String, j : Json) -> LEnt raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("entity is not an object")
  }
  allowed_keys(
    o,
    ["type", "default", "env", "inherit", "config_key", "accumulator"],
    "golden entity",
  )
  let typ = req_field(o, "type")
  let default_ = match o.get("default") {
    Some(d) => Some(json_to_value(d))
    None => None
  }
  let config_key : Array[String]? = match o.get("config_key") {
    Some(c) => Some(dec_strs(Some(c)))
    None => None
  }
  {
    name,
    typ,
    default_,
    env: jf_str(o, "env"),
    inherit_: bool_field(o, "inherit", false),
    config_key,
    accum: jf_str(o, "accumulator"),
  }
}

///|
fn dec_lcon(j : Json) -> Constraint raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("constraint is not an object")
  }
  match req_field(o, "kind") {
    "requires" => {
      allowed_keys(o, ["kind", "element", "targets"], "requires constraint")
      CRequires(req_field(o, "element"), dec_strs(o.get("targets")))
    }
    "conflicts_with" => {
      allowed_keys(
        o,
        ["kind", "element", "targets"],
        "conflicts_with constraint",
      )
      CConflicts(req_field(o, "element"), dec_strs(o.get("targets")))
    }
    "requires_if" => {
      // DR-055 §1 + DR-052 §値枝 id 直交: fixture 側が constraints[] を直宣言する場面での decoder。
      // `entity` (committed 判定対象) と `element` (違反時 emit する branch_id) の両方を受け付ける。
      // `entity` 省略時は `element` にフォールバック (parent 直属 value_requires 相当の暗黙形)。
      allowed_keys(
        o,
        ["kind", "entity", "element", "value", "targets"],
        "requires_if constraint",
      )
      let element = req_field(o, "element")
      let entity = jf_str(o, "entity").unwrap_or(element)
      CRequiresIf(
        entity,
        element,
        req_field(o, "value"),
        dec_strs(o.get("targets")),
      )
    }
    "exclusive_group" => {
      allowed_keys(
        o,
        ["kind", "group", "members"],
        "exclusive_group constraint",
      )
      CExclusive(req_field(o, "group"), dec_strs(o.get("members")))
    }
    other => raise DecodeSkip("unsupported constraint kind '" + other + "'")
  }
}

///|
fn dec_lsec(o : Map[String, Json]) -> LSec raise DecodeSkip {
  allowed_keys(
    o,
    ["greedy", "positionals", "entities", "constraints", "templates"],
    "golden 断面",
  )
  let greedy : Array[GItem] = []
  match o.get("greedy") {
    Some(gj) =>
      match gj.j_arr() {
        Some(a) =>
          for e in a {
            greedy.push(dec_gitem(e))
          }
        None => raise DecodeSkip("greedy is not an array")
      }
    None => ()
  }
  let positionals : Array[TNode] = []
  match o.get("positionals") {
    Some(pj) =>
      match pj.j_arr() {
        Some(a) =>
          for e in a {
            positionals.push(dec_pos_tnode(e))
          }
        None => raise DecodeSkip("positionals is not an array")
      }
    None => ()
  }
  let entities : Array[LEnt] = []
  match o.get("entities") {
    Some(en) =>
      match en.j_obj() {
        Some(eo) =>
          for k, v in eo {
            entities.push(dec_lent(k, v))
          }
        None => raise DecodeSkip("entities is not an object")
      }
    None => ()
  }
  let constraints : Array[Constraint] = []
  match o.get("constraints") {
    Some(cj) =>
      match cj.j_arr() {
        Some(a) =>
          for e in a {
            constraints.push(dec_lcon(e))
          }
        None => raise DecodeSkip("constraints is not an array")
      }
    None => ()
  }
  let templates : Array[(String, TNode)] = []
  match o.get("templates") {
    Some(tj) =>
      match tj.j_obj() {
        Some(to) =>
          for k, v in to {
            templates.push((canon_tmpl(k), dec_tmpl_body(v)))
          }
        None => raise DecodeSkip("templates is not an object")
      }
    None => ()
  }
  { greedy, positionals, entities, constraints, templates }
}

///|
fn dec_lower(j : Json) -> DecodedLower raise DecodeSkip {
  let top = match j.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  let defo = match top.get("definition") {
    Some(d) =>
      match d.j_obj() {
        Some(o) => o
        None => raise DecodeSkip("definition is not an object")
      }
    None => raise DecodeSkip("missing 'definition'")
  }
  // DR-061 §3 configurable factory: `definitions.types` を許容し、その中身を shadow map に decode。
  // shadow は dec_definition に thread されて type 名解決で consultation される。
  allowed_keys(
    defo,
    [
      "options", "positionals", "commands", "definitions",
      // DR-091 §3 (scope config, DESIGN §7.2 の兄弟): `dec_definition` が読む nested config object。
       "config",
    ],
    "definition",
  )
  let shadows = match defo.get("definitions") {
    Some(dj) => {
      let d = match dj.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("definitions is not an object")
      }
      allowed_keys(d, ["types"], "definitions")
      match d.get("types") {
        Some(tj) => dec_types(tj)
        None => Map([])
      }
    }
    None => Map([])
  }
  let def = dec_definition(defo, shadows~)
  let order = dec_installers(top)
  let expo = match top.get("expect") {
    Some(e) =>
      match e.j_obj() {
        Some(o) => o
        None => raise DecodeSkip("expect is not an object")
      }
    None => raise DecodeSkip("missing 'expect'")
  }
  { def, order, want: dec_lsec(expo) }
}

// ── fixtures discovery ────────────────────────────────────────────────────────

///|
fn is_json_file(name : String) -> Bool {
  let cs = to_chars(name)
  let n = cs.length()
  n >= 5 &&
  cs[n - 5] == '.' &&
  cs[n - 4] == 'j' &&
  cs[n - 3] == 's' &&
  cs[n - 2] == 'o' &&
  cs[n - 1] == 'n'
}

///|
fn fixtures_root() -> String {
  match @env.get_env_var("KUU_FIXTURES") {
    Some(p) => if p != "" && @fs.path_exists(p) { return p }
    None => ()
  }
  for
    cand in [
      "../../../kuu/main/fixtures", "../../kuu/main/fixtures", "../../../../kuu/main/fixtures",
    ] {
    if @fs.path_exists(cand) {
      return cand
    }
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "?"
  }
  abort(
    "fixtures root not found (set KUU_FIXTURES to kuu/main/fixtures); cwd=" +
    cwd,
  )
}

///|
fn collect_rel(root : String, rel : String, out : Array[String]) -> Unit raise {
  let dir = if rel == "" { root } else { root + "/" + rel }
  for name in @fs.read_dir(dir) {
    let r = if rel == "" { name } else { rel + "/" + name }
    let p = root + "/" + r
    if @fs.is_dir(p) {
      collect_rel(root, r, out)
    } else if is_json_file(name) {
      out.push(r)
    }
  }
}

// ── the case runner ───────────────────────────────────────────────────────────

///|
fn scope_needs_default_ladder(sc : Scope) -> Bool {
  for g in sc.greedy {
    match g {
      CmdSat(_, _) => return false
      _ => ()
    }
  }
  for e in sc.entities {
    if e.ty != TFlag && e.ty != TBool && e.default_values is Some(_) {
      return true
    }
    // DR-009 value_filters/cell_filters (issue 2026-07-09-filters-registry-foundation) are applied by
    // `resolve_entity` (resolve.mbt's `apply_entity_filters`), NOT by the raw CLI `binds` array
    // this function's `false` result routes to. `resolve_entity_raw`'s CLI-seat fold interprets an
    // accum cell's op sequence now (issue 2026-07-09-accum-entity-filters-wiring's raw-preservation
    // groundwork, extended by issue 2026-07-09-accum-fold-update-default-ops's committed tracking +
    // ladder fall-through), so an accum cell with value_filters/cell_filters ALSO needs the resolve
    // path — the guard that used to exclude accum (`e.accum is None &&`) is removed. `apply_entity_
    // filters` already skips cell_filters for an accum cell (accumulated-array post is a separate
    // stage, issue accum-post-filters-stage7); routing through resolve here only activates
    // value_filters(each).
    if e.value_filters.length() > 0 || e.cell_filters.length() > 0 {
      return true
    }
    // DR-080 波及節: a merge-accumulator cell's Set/Remove/Splice PIECE bindings only fold into
    // the cell's final state inside `resolve_merge_accum` (resolve.mbt) — the raw-`binds` fold
    // this function's `false` result routes to (`build_result`'s generic ACCUMULATE match) has no
    // concept of "同じ at_pos の piece 列 = 1 発火" grouping or old-composition, and would push a
    // `Splice`/`Remove` binding's placeholder/operand value straight into the array (wrong on
    // every axis: no overwrite-vs-merge distinction, no @ old-splice, `Remove`'s operand and
    // `Splice`'s `VBool(false)` placeholder both leak into the result). A merge cell ALWAYS needs
    // the resolve path, even with no env/config/default/filters declared.
    if e.accum is Some("merge") {
      return true
    }
  }
  false
}

///|
fn has_commands(sc : Scope) -> Bool {
  for g in sc.greedy {
    match g {
      CmdSat(_, _) => return true
      _ => ()
    }
  }
  false
}

///|
fn cfg_lookup(files : Array[(String, ConfigVal)], p : String) -> ConfigVal? {
  for kv in files {
    if kv.0 == p {
      return Some(kv.1)
    }
  }
  None
}

///|
fn pe_msg(pe : ParseError) -> String {
  pe.message
}

///|
/// The `ParseError`-preserving form (`"failure"`-branch resolve check, DR-009 §7 cell_filters etc.
/// surfacing as a resolve-layer Err even when `parse()` itself succeeded — see `do_resolve`'s
/// string-message wrapper below, kept for its existing "success"-branch callers).
fn do_resolve_pe(
  sc : Scope,
  cli : Array[Binding],
  dc : DCase,
) -> Result[Array[Binding], ParseError] {
  // `at_pos: dc.argv.length()` — a resolve-layer Error (env/config seat parse failure, or a
  // DR-009 §7 value_filters/cell_filters reject) is not read at a token position, it surfaces after
  // the argv path completed (`ladder_err`'s doc comment, resolve.mbt). Threading the real final
  // position here (instead of `resolve_scope`/`resolve_scope_config`'s `at_pos? = -1` default)
  // matches `eval_constraints`'s convention for the same conceptual point (DR-053 §2).
  let at_pos = dc.argv.length()
  match dc.cfg {
    NoCfg => resolve_scope(sc, cli, dc.env, at_pos~)
    CfgObj(obj) =>
      resolve_scope_config(sc, cli, dc.env, fn(_p) { Some(obj) }, at_pos~)
    CfgFiles(files) =>
      resolve_scope_config(
        sc,
        cli,
        dc.env,
        fn(p) { cfg_lookup(files, p) },
        at_pos~,
      )
  }
}

///|
fn do_resolve(
  sc : Scope,
  cli : Array[Binding],
  dc : DCase,
) -> Result[Array[Binding], String] {
  match do_resolve_pe(sc, cli, dc) {
    Ok(rb) => Ok(rb)
    Err(pe) => Err(pe_msg(pe))
  }
}

///|
/// `dc.cfg` (NoCfg/CfgObj/CfgFiles) → `resolve.mbt`'s `resolve_scope_tree` provider 契約への薄い
/// アダプタ (issue resolve-first-constraint-pipeline Phase 1: 再帰的な木解決ロジック自体は
/// `resolve_scope_tree` 側に一本化、ここでは DCase 分岐と `Result[..., ParseError]` →
/// `Result[..., String]` のハーネス向け整形だけを担う — `do_resolve_pe`/`run_case` の
/// `bool_requires_provider` と同型の分岐)。
fn resolve_tree(
  sc : Scope,
  binds : Array[Binding],
  dc : DCase,
  path : Array[String],
  inherited : Map[String, Value],
) -> Result[Array[Binding], String] {
  let provider : (String) -> ConfigVal? = match dc.cfg {
    NoCfg => fn(_p) { None }
    CfgObj(obj) => fn(_p) { Some(obj) }
    CfgFiles(files) => fn(p) { cfg_lookup(files, p) }
  }
  // See `do_resolve_pe`'s comment: real final argv position, not the `-1` default.
  let at_pos = dc.argv.length()
  match
    resolve_scope_tree(sc, binds, dc.env, provider, path~, inherited~, at_pos~) {
    Ok(rb) => Ok(rb)
    Err(pe) => Err(pe_msg(pe))
  }
}

///|
fn run_case(df : DecodedFixture, dc : DCase) -> String {
  let sc = df.scope
  let root = ScopeNode(sc)
  // DR-047 §5 明確化 (kawaz 裁定 2026-07-09): bool-target requires/CRequiresIf は KTop (CLI 面
  // のみ) では常にスキップされているので、値源 (env) が解ける後段でここでフィルタする
  // (cell_filters と同じ側、`resolve.mbt` の `apply_requires_filter` — 経路数に応じて
  // success/ambiguous/failure を再確定)。DR-021 → DR-073 の export-key collision 昇格
  // (`promote_collision_ambiguous`) より先に適用する — 責務が異なる2つの後処理 (「経路の成立
  //自体」と「export-key 衝突による Success→Ambiguous 昇格」) を素直に直列に並べる。
  // issue resolve-first-constraint-pipeline (Phase 1、旧 bool-requires-config-inherit-gap 裁定
  // 2026-07-10 (b) を置き換え): apply_requires_filter は候補ごとに `resolve_scope_tree` を
  // 実際に呼ぶようになったので、`resolve_scope_config` と同じ `provider: (String) -> ConfigVal?`
  // 契約をそのまま渡せる — `do_resolve_pe` が dc.cfg から作る provider と同型 (CfgFiles も
  // 均一に扱われ、単一 ConfigVal だった旧契約の既知の残存ギャップが解消)。
  let bool_requires_provider : (String) -> ConfigVal? = match dc.cfg {
    NoCfg => fn(_p) { None }
    CfgObj(obj) => fn(_p) { Some(obj) }
    CfgFiles(files) => fn(p) { cfg_lookup(files, p) }
  }
  let outcome = promote_collision_ambiguous(
    apply_requires_filter(
      parse(root, dc.argv, defs=df.registry),
      root,
      df.registry,
      dc.env,
      dc.argv.length(),
      provider=bool_requires_provider,
    ),
    df.ekmap,
  )
  let problems : Array[String] = []
  let use_resolve = dc.resolve || scope_needs_default_ladder(sc)
  match dc.outcome {
    "success" =>
      match outcome {
        Success(binds) => {
          match dc.exp_effects {
            Some(ee) => {
              let ae = proj_effects_ex(sc, binds)
              if ae != ee {
                problems.push("effects got=\{ae} want=\{ee}")
              }
            }
            None => ()
          }
          if dc.resolve && has_commands(sc) {
            match resolve_tree(sc, binds, dc, [], Map([])) {
              Ok(rb) => {
                match dc.exp_result {
                  Some(er) => {
                    let ar = proj_result_export(sc, rb, df.ekmap)
                    if ar != er {
                      problems.push("result got=\{ar} want=\{er}")
                    }
                  }
                  None => ()
                }
                match dc.exp_sources {
                  Some(es) => {
                    let asr = proj_sources_tree(rb)
                    if asr != es {
                      problems.push("sources got=\{asr} want=\{es}")
                    }
                  }
                  None => ()
                }
              }
              Err(msg) => problems.push("resolve error: " + msg)
            }
          } else if use_resolve {
            match do_resolve(sc, binds, dc) {
              Ok(rb) => {
                match dc.exp_result {
                  Some(er) => {
                    let ar = proj_result_export(sc, rb, df.ekmap)
                    if ar != er {
                      problems.push("result got=\{ar} want=\{er}")
                    }
                  }
                  None => ()
                }
                match dc.exp_sources {
                  Some(es) => {
                    let asr = proj_sources(sc, rb, df.ekmap)
                    if asr != es {
                      problems.push("sources got=\{asr} want=\{es}")
                    }
                  }
                  None => ()
                }
              }
              Err(msg) => problems.push("resolve error: " + msg)
            }
          } else {
            match dc.exp_result {
              Some(er) => {
                let ar = proj_result_export(sc, binds, df.ekmap)
                if ar != er {
                  problems.push("result got=\{ar} want=\{er}")
                }
              }
              None => ()
            }
          }
          match dc.exp_warnings {
            Some(ew) => {
              let aw = proj_warnings(outcome)
              if aw != ew {
                problems.push("warnings got=\{aw} want=\{ew}")
              }
            }
            None => ()
          }
        }
        other => problems.push("EXPECTED-SUCCESS got=" + render_outcome(other))
      }
    "failure" =>
      match outcome {
        Failure(d) => {
          match dc.exp_errors {
            Some(ex) => {
              let ae = proj_errors(
                d.errors,
                dc.exp_errors_with_reason,
                dc.exp_errors_with_path,
              )
              if ae != ex {
                problems.push("errors got=\{ae} want=\{ex}")
              }
            }
            None => ()
          }
          if dc.fired_cmp {
            let got = match d.fired_action {
              Some(s) => s
              None => "(none)"
            }
            let want = match dc.fired_exp {
              Some(s) => s
              None => "(none)"
            }
            if got != want {
              problems.push("fired_action got=\{got} want=\{want}")
            }
          }
          if dc.help_cmp {
            let got = match d.help_entry {
              Some(s) => s
              None => "(none)"
            }
            let want = match dc.help_exp {
              Some(s) => s
              None => "(none)"
            }
            if got != want {
              problems.push("help_entry got=\{got} want=\{want}")
            }
          }
          if dc.tried_cmp {
            let got = proj_tried_triggers(d.tried_triggers)
            let want = match dc.tried_exp {
              Some(s) => s
              None => "{}"
            }
            if got != want {
              problems.push("tried_triggers got=\{got} want=\{want}")
            }
          }
        }
        // DR-009 §7 cell_filters (and any other resolve-layer check, e.g. a future
        // constraint that only resolve sees): `parse()` itself can succeed while the VALUE
        // resolution layer (env/config/inherit/default ladder fill + filter chains,
        // resolve.mbt) still rejects — a "failure" fixture case exercising THAT path needs
        // the resolve check run here too, mirroring the "success" branch's
        // `use_resolve`-gated `do_resolve` call. Without this, a resolve-layer Err was
        // invisible to `"failure"` fixtures entirely (this function's `match outcome` never
        // called resolve at all before) — `Success` fell straight to the `other` catch-all
        // below and got mis-reported as EXPECTED-FAILURE got=ok{...}.
        Success(binds) if use_resolve =>
          match do_resolve_pe(sc, binds, dc) {
            Err(pe) =>
              match dc.exp_errors {
                Some(ex) => {
                  let ae = proj_errors(
                    [pe],
                    dc.exp_errors_with_reason,
                    dc.exp_errors_with_path,
                  )
                  if ae != ex {
                    problems.push("errors got=\{ae} want=\{ex}")
                  }
                }
                None => ()
              }
            Ok(_) =>
              problems.push("EXPECTED-FAILURE got=ok (resolve also succeeded)")
          }
        other => problems.push("EXPECTED-FAILURE got=" + render_outcome(other))
      }
    _ =>
      match outcome {
        Ambiguous(d) => {
          match dc.exp_interps {
            Some(ei) => {
              let got : Array[String] = []
              for interp in d.interpretations {
                // Result-object view is always rendered (DR-053 §3 骨格温存)
                let view = render_rval_sorted(
                  build_result(
                    apply_export_keys(interp.binds, df.ekmap),
                    accum_cells(sc, df.ekmap),
                    [],
                    [],
                    nones=none_cells(sc),
                  ),
                )
                // DR-073 §1: append `#claimants{...}` suffix only when the interpretation carries
                // a non-empty claimants面 (matches exp_interp_str's `view + "#claimants" + ...`
                // encoding at line 1500). Non-collision interpretations render as bare view — the
                // renderer must not synthesize an empty `#claimants{}` for those (would fail the
                // structural or-position/repeat/prefix-guard ambiguous fixtures whose expected
                // form is view-only, not `view#claimants{}`).
                if interp.claimants.length() == 0 {
                  got.push(view)
                } else {
                  let items : Array[String] = []
                  for kv in interp.claimants {
                    items.push(kv.0 + "=" + kv.1)
                  }
                  sort_items(items)
                  got.push(view + "#claimants{" + join_comma(items) + "}")
                }
              }
              sort_items(got)
              let ag = join_comma(got)
              let ew = join_comma(ei)
              if ag != ew {
                problems.push("interpretations got=[\{ag}] want=[\{ew}]")
              }
            }
            None => ()
          }
          if dc.help_cmp {
            let got = match d.help_entry {
              Some(s) => s
              None => "(none)"
            }
            let want = match dc.help_exp {
              Some(s) => s
              None => "(none)"
            }
            if got != want {
              problems.push("help_entry got=\{got} want=\{want}")
            }
          }
        }
        other =>
          problems.push("EXPECTED-AMBIGUOUS got=" + render_outcome(other))
      }
  }
  if problems.length() == 0 {
    "PASS"
  } else {
    let sb = StringBuilder::new()
    let mut first = true
    for p in problems {
      if !first {
        sb.write_string(" | ")
      }
      sb.write_string(p)
      first = false
    }
    sb.to_string()
  }
}

// ── ledgers (MDR-001 §6: start empty, populate as fixtures classify) ─────────

///|
/// The FROZEN divergence ledger (fixture = 正本, main src/core = 被検体).
///
/// Each entry is the FULL `rel::slug :: verdict` string of a comparison that currently diverges —
/// a KNOWN gap either INHERITED from slice/poc (未実装が正本仕様に追従していない) or a suspected
/// fixture-authoring issue frozen for later resolution. The runner asserts the observed divergence
/// SET equals this ledger: UNEXPECTED and VANISHED entries both fail (verdict-granularity freeze,
/// MDR-001 §6). Empty = full conformance (no known gaps against the fixture corpus).
fn known_divergences() -> Array[String] {
  []
}

///|
/// The FROZEN skip ledger — decode-time twin of `known_divergences`. Each entry is `(rel, reason)`:
/// a fixture the decoder cannot losslessly represent, so it raises DecodeSkip before any case runs.
/// UNEXPECTED / VANISHED / CHANGED SKIP REASON all fail the run (like divergences, MDR-001 §6).
///
/// MDR-004 (ElemBody body grammar) resolved the 4 structural-or / nested-group skips inherited from
/// slice (BOr option/positional lowering + BGroup+IdxRepeat lowering), and the parallel
/// number_allow_base_prefix work (hex/oct/bin integer + hex float lexer) resolved the remaining
/// `definitions.types[number]` factory-config gap — all previously-frozen skip entries are removed
/// since every fixture now decodes and runs losslessly (full conformance, no known skip gaps).
fn expected_skips() -> Array[(String, String)] {
  []
}

///|
fn case_key(rel : String, id : String) -> String {
  rel + "::" + id
}

///|
fn is_kebab(s : String) -> Bool {
  if s == "" {
    return false
  }
  let mut prev_dash = true
  for c in s {
    if c == '-' {
      if prev_dash {
        return false
      }
      prev_dash = true
    } else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      prev_dash = false
    } else {
      return false
    }
  }
  !prev_dash
}

///|
fn raw_case_ids(j : Json) -> Array[String]? {
  let top = match j.j_obj() {
    Some(o) => o
    None => return None
  }
  let casesj = match top.get("cases") {
    Some(c) => c
    None => return None
  }
  let carr = match casesj.j_arr() {
    Some(x) => x
    None => return None
  }
  let ids : Array[String] = []
  for cj in carr {
    ids.push(
      match cj.j_obj() {
        Some(co) => jf_str(co, "id").unwrap_or("")
        None => ""
      },
    )
  }
  Some(ids)
}

///|
fn check_ids(rel : String, ids : Array[String]) -> Array[String] {
  let bad : Array[String] = []
  let seen : Map[String, Int] = Map([])
  let mut ci = 0
  for id in ids {
    ci = ci + 1
    if id == "" {
      bad.push(
        rel +
        "::case#" +
        ci.to_string() +
        " — id 欠落または非文字列 (DR-072: 各 case は required の kebab-case id を持つ)",
      )
    } else if !is_kebab(id) {
      bad.push(
        rel +
        "::case#" +
        ci.to_string() +
        " — id '" +
        id +
        "' が kebab-case ([a-z0-9-]) でない",
      )
    } else {
      match seen.get(id) {
        Some(first) =>
          bad.push(
            rel +
            "::case#" +
            ci.to_string() +
            " — id '" +
            id +
            "' が fixture 内で重複 (初出 case#" +
            first.to_string() +
            ")",
          )
        None => seen.set(id, ci)
      }
    }
  }
  bad
}

///|
fn load_json(path : String) -> Json raise {
  @json.parse(@fs.read_file_to_string(path))
}

///|
test "conformance: fixtures を JSON 直読みで実食 (parse 語彙網羅 + lower 5 面断面)" {
  let root = fixtures_root()
  let rels : Array[String] = []
  collect_rel(root, "", rels) catch {
    _ => abort("fixtures walk failed under " + root)
  }
  sort_items(rels)
  let decoded : Array[String] = []
  let skips : Array[(String, String)] = []
  let mismatches : Array[String] = []
  let malformed : Array[String] = []
  let mut ran_cases = 0
  for rel in rels {
    let full = root + "/" + rel
    let j = load_json(full) catch {
      _ => {
        skips.push((rel, "load/parse error"))
        continue
      }
    }
    let id_bad : Array[String] = match raw_case_ids(j) {
      Some(ids) => check_ids(rel, ids)
      None => []
    }
    for b in id_bad {
      malformed.push(b)
    }
    let q = match j.j_obj() {
      Some(o) => jf_str(o, "query").unwrap_or("")
      None => ""
    }
    if q == "lower" {
      let dl = dec_lower(j) catch {
        DecodeSkip(reason) => {
          skips.push((rel, reason))
          continue
        }
      }
      decoded.push(rel)
      ran_cases = ran_cases + 1
      let verdict = run_lower(dl.def, dl.order, dl.want)
      if verdict != "PASS" {
        mismatches.push(rel + "::lower :: " + verdict)
      }
      continue
    }
    if q == "definition_error" {
      let fx = dec_definition_error_fixture(j) catch {
        DecodeSkip(reason) => {
          skips.push((rel, reason))
          continue
        }
      }
      decoded.push(rel)
      for c in fx.cases {
        ran_cases = ran_cases + 1
        let verdict = run_definition_error(fx, c)
        if verdict != "PASS" {
          mismatches.push(case_key(rel, c.id) + " :: " + verdict)
        }
      }
      continue
    }
    let df = dec_fixture(j) catch {
      DecodeSkip(reason) => {
        skips.push((rel, reason))
        continue
      }
    }
    decoded.push(rel)
    if id_bad.length() > 0 {
      continue
    }
    for c in df.cases {
      ran_cases = ran_cases + 1
      let verdict = run_case(df, c)
      if verdict != "PASS" {
        mismatches.push(case_key(rel, c.id) + " :: " + verdict)
      }
    }
  }
  println(
    "[json-conformance] decoded=\{decoded.length()} ran_cases=\{ran_cases} skipped=\{skips.length()} mismatches=\{mismatches.length()}",
  )
  println("[json-conformance] decoded: " + join_comma(decoded))
  let hist : Map[String, Int] = Map([])
  for pair in skips {
    let r = pair.1
    hist.set(
      r,
      (match hist.get(r) {
        Some(n) => n
        None => 0
      }) +
      1,
    )
  }
  let hitems : Array[String] = []
  for r, n in hist {
    hitems.push("\{n}× \{r}")
  }
  sort_items(hitems)
  for h in hitems {
    println("[json-conformance]   skip " + h)
  }
  for m in mismatches {
    println("[json-conformance]   diverge " + m)
  }
  for m in malformed {
    println("[json-conformance]   malformed " + m)
  }
  // Assert malformed-id list is empty.
  if malformed.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("fixture case-id well-formedness violation (DR-072):\n")
    for m in malformed {
      sb.write_string("  " + m + "\n")
    }
    println(sb.to_string())
    abort(sb.to_string())
  }
  // Skip ledger assertion (empty ledger; any observed skip is UNEXPECTED for now).
  let sk_ledger = expected_skips()
  let unexpected_skips : Array[String] = []
  let changed_skips : Array[String] = []
  for pair in skips {
    let rel = pair.0
    let reason = pair.1
    let mut found_reason : String? = None
    for e in sk_ledger {
      if e.0 == rel {
        found_reason = Some(e.1)
        break
      }
    }
    match found_reason {
      None => unexpected_skips.push(rel + " :: " + reason)
      Some(want) =>
        if want != reason {
          changed_skips.push(rel + " :: got=" + reason + " want=" + want)
        }
    }
  }
  let vanished_skips : Array[String] = []
  for e in sk_ledger {
    let mut still_skipped = false
    for pair in skips {
      if pair.0 == e.0 {
        still_skipped = true
        break
      }
    }
    if !still_skipped {
      vanished_skips.push(e.0)
    }
  }
  if unexpected_skips.length() > 0 ||
    vanished_skips.length() > 0 ||
    changed_skips.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("skip ledger mismatch:\n")
    if unexpected_skips.length() > 0 {
      sb.write_string("  UNEXPECTED SKIP:\n")
      for s in unexpected_skips {
        sb.write_string("    " + s + "\n")
      }
    }
    if vanished_skips.length() > 0 {
      sb.write_string("  VANISHED SKIP:\n")
      for s in vanished_skips {
        sb.write_string("    " + s + "\n")
      }
    }
    if changed_skips.length() > 0 {
      sb.write_string("  CHANGED SKIP REASON:\n")
      for s in changed_skips {
        sb.write_string("    " + s + "\n")
      }
    }
    println(sb.to_string())
    abort(sb.to_string())
  }
  // Divergence ledger assertion (empty ledger; any observed divergence is UNEXPECTED).
  let known = known_divergences()
  let unexpected : Array[String] = []
  for m in mismatches {
    if !conformance_str_in(known, m) {
      unexpected.push(m)
    }
  }
  let vanished : Array[String] = []
  for k in known {
    if !conformance_str_in(mismatches, k) {
      vanished.push(k)
    }
  }
  if unexpected.length() > 0 || vanished.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("divergence ledger mismatch:\n")
    if unexpected.length() > 0 {
      sb.write_string("  UNEXPECTED:\n")
      for m in unexpected {
        sb.write_string("    " + m + "\n")
      }
    }
    if vanished.length() > 0 {
      sb.write_string("  VANISHED:\n")
      for k in vanished {
        sb.write_string("    " + k + "\n")
      }
    }
    println(sb.to_string())
    abort(sb.to_string())
  }
}

///|
/// MDR-004 §4 / 実装順 5: OrBranch.id (無指定なら自動採番 `#{seq}`) は内部照合専用で、観測面
/// (held Error / ambiguous interpretations / success result) のどこにも漏れてはいけない。対象
/// 4 fixture はどれも "id" キー無指定 (= 自動採番のみ) なので、既にそれ自体が非漏出の状況証拠で
/// はある — が、fixture 任せだと「将来誰かが .id を表示経路に配線してしまう」退行を検出できない
/// (codex REVIEW-M5)。ここでは同じ定義形 (対称 or の 2 枝、held-errors-same-depth.json と同型) を
/// inline JSON で組み、failure (0 本成立) / ambiguous (2 本成立) / success (1 本のみ生存) の 3 outcome
/// すべてで、rendered text に自動 id パターン ("#0" / "#1") が一切現れないこと、かつ本来の leaf 名
/// (a/b) は現れることを同時に固定する。
test "conformance: OrBranch auto id (#{seq}) は held-error / ambiguous / success のどこにも漏れない (MDR-004 §4)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "positionals": [
    #|      {"or": [{"type": "number", "name": "a"}, {"type": "number", "name": "b"}]}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let j = @json.parse(src)
  let df = dec_fixture(j)
  let no_leak = fn(s : String) -> Unit {
    if s.contains("#0") || s.contains("#1") {
      abort("auto branch id leaked into observable text: \{s}")
    }
  }
  // failure (0 本成立): 非数値 1 token は両枝とも同位置で dead-end (same-depth 同型)。
  let fail_outcome = parse(ScopeNode(df.scope), ["x"], defs=df.registry)
  match fail_outcome {
    Failure(d) => {
      let texts : Array[String] = []
      for e in d.errors {
        texts.push(e.element + ":" + e.message)
      }
      let joined = join_comma(texts)
      no_leak(joined)
      if !joined.contains("a:") || !joined.contains("b:") {
        abort("expected both leaf names (a/b) in failure text, got: \{joined}")
      }
    }
    other => abort("expected Failure, got " + render_outcome(other))
  }
  // ambiguous (2 本成立): 数値 1 token は両枝が同位置で成立 → 2 完全経路。
  let amb_outcome = parse(ScopeNode(df.scope), ["5"], defs=df.registry)
  match amb_outcome {
    Ambiguous(d) => {
      let views : Array[String] = []
      for interp in d.interpretations {
        views.push(
          render_rval_sorted(
            build_result(
              apply_export_keys(interp.binds, df.ekmap),
              accum_cells(df.scope, df.ekmap),
              [],
              [],
            ),
          ),
        )
      }
      let joined = join_comma(views)
      no_leak(joined)
      if !joined.contains("a=5") || !joined.contains("b=5") {
        abort(
          "expected both interpretations (a=5/b=5) in ambiguous text, got: \{joined}",
        )
      }
    }
    other => abort("expected Ambiguous, got " + render_outcome(other))
  }
  // success (1 本のみ生存) は対称 2 枝 (a/b 共に number) では作れない — 両枝は常に対称に成立/
  // 不成立するため、単一トークン argv では必ず failure か ambiguous になる。success 面の非漏出は
  // path-search/variable-arity-ambiguous.json::non-number-collapses-to-name (既存 conformance、
  // 非対称 2 枝で数値枝のみ死ぬケース) が別途固定済みなので、本 wbtest は failure/ambiguous の
  // 2 outcome をスコープとする。
}

// ── DR-078: definitions.templates + ref (蒸留 1:1 audit 漏れ #1/#2, slice phase4:114/phase10:64) ──

///|
/// 保証 (蒸留 1:1 audit 漏れ #1、slice `poc/phase4_wbtest.mbt:125-152` 相当、DR-078 §1 の decode
/// 配線疎通): `hlcolors := color+` (positional が `ref:"color"` + `repeat:{min:1}`、`color` は
/// `definitions.templates` に `or [ [r,g,b] な 3 数値 seq | 文字列 colorname ]` (DR-078 §1 の例
/// そのもの) として宣言された共有 template) が正しく decode → lowering → parse される。
/// 文字列名の繰り返し (`red blue`) は各発火が colorname 枝を辿るだけの一義的な parse。
/// `255 0 0` は「1 回発火・rgb 枝 (3 トークン消費)」と「3 回発火・colorname 枝 (1 トークンずつ)」の
/// 構造的に異なる完全経路が両立し、ambiguous:2 になる (or 枝の違いは DR-043 の取り分選好の対象外 —
/// 選好は「同じ closure の分け方」の中でしか効かない、次の wbtest で対で固定)。
test "DR-078: definitions.templates + ref — repeat over a shared or-template (hlcolors := color+)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"templates": {"color": {"or": [
    #|      {"seq": [{"type": "number", "name": "r"}, {"type": "number", "name": "g"}, {"type": "number", "name": "b"}]},
    #|      {"type": "string", "name": "colorname"}
    #|    ]}}},
    #|    "positionals": [
    #|      {"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let df = dec_fixture(@json.parse(src))
  // 純文字列の繰り返し: colorname 枝のみが成立する一義的な parse (rgb 枝は数値でないトークンで dead-end)。
  // render_outcome は binding を flat key=value (sort 済み) で描画する (slice の ok{name=blue,name=red}
  // と同じ形、色テンプレの leaf 名は "colorname")。
  assert_eq(
    render_outcome(
      parse(ScopeNode(df.scope), ["red", "blue"], defs=df.registry),
    ),
    "ok{colorname=blue,colorname=red}",
  )
  // rgb 枝 (1 回発火, 3 トークン) vs colorname 枝 (3 回発火, 1 トークンずつ) — 構造的に異なる完全経路
  // が両立し ambiguous:2 (DR-038)。
  assert_eq(
    render_outcome(
      parse(ScopeNode(df.scope), ["255", "0", "0"], defs=df.registry),
    ),
    "ambiguous:2",
  )
}

///|
/// 保証 (蒸留 1:1 audit 漏れ #2、slice `poc/phase10_wbtest.mbt:90-108` 相当): repeat の取り分選好
/// (preference、DR-043) は「同じ closure の分け方」次元にのみ効き、or 枝の違い (構造的に異なる完全
/// 経路) を侵食してかき消さない。`255 0 0` は前 wbtest と同じく ambiguous:2 のまま — 選好は「同点の
/// share だけ絞る」ものであって「or 枝の差を潰す」ものではないことを固定する。純文字列 argv には
/// rgb 読みが無いので (すべて非数値) split は一意 — 選好の有無に関わらず成立するケースとして対比する。
test "DR-078: preference does not erode or-branch ambiguity (share-dimension only, DR-043)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"templates": {"color": {"or": [
    #|      {"seq": [{"type": "number", "name": "r"}, {"type": "number", "name": "g"}, {"type": "number", "name": "b"}]},
    #|      {"type": "string", "name": "colorname"}
    #|    ]}}},
    #|    "positionals": [
    #|      {"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(
    render_outcome(
      parse(ScopeNode(df.scope), ["255", "0", "0"], defs=df.registry),
    ),
    "ambiguous:2",
  )
  assert_eq(
    render_outcome(
      parse(ScopeNode(df.scope), ["red", "green", "blue"], defs=df.registry),
    ),
    "ok{colorname=blue,colorname=green,colorname=red}",
  )
}

///|
/// 保証 (codex 節目レビュー指摘1、issue 2026-07-09-ref-template-result-shape): wire schema の name/id
/// 制約 `^[^#]+$` (DR-067 §2「`#` を含む name/id はユーザ定義で禁止」、内部予約名前空間 = repeat
/// lowering の `<name>#cons` / `next_or_branch_id` の `#0`/`#1`/… / resolve.mbt の row/fire sentinel
/// "#row"/"#fire") を decode 層が enforce することを、`#` の出現しうる箇所ごとにマトリクスで固定する
/// — 1 箇所だけ確認すると「たまたま通ってた」を見逃す (empirical-verification のサンプル数原則)。
/// positional の name / option の name / definitions.templates の template key の 3 カテゴリで
/// decode が `DecodeSkip` (definition の decode error、既存語彙のまま) を投げることを確認する。
test "decode: a `#` in name/id is rejected at every user-facing name surface (codex review #1)" {
  // (1) positional の name。`@json.parse` (raise ParseError) を try の外で先に評価しておく —
  // `dec_fixture` 自身の `raise DecodeSkip` だけを catch で汲む。
  let pos_src =
    #|{"query":"parse","definition":{"positionals":[{"name":"src#cons","type":"string"}]},"cases":[]}
  let pos_j = @json.parse(pos_src)
  let _ = dec_fixture(pos_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("#"))
      return
    }
  }
  abort("positional name 'src#cons': expected DecodeSkip, decode succeeded")
}

///|
test "decode: a `#` in an option's name is rejected (codex review #1)" {
  let opt_src =
    #|{"query":"parse","definition":{"options":[{"name":"hl#colors","type":"string","long":true}]},"cases":[]}
  let opt_j = @json.parse(opt_src)
  let _ = dec_fixture(opt_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("#"))
      return
    }
  }
  abort("option name 'hl#colors': expected DecodeSkip, decode succeeded")
}

///|
/// definitions.templates の template key (DR-078 §1 の ref 対象名) も同じ予約名前空間 — `ref:` が
/// 指す先の key が `#` を含めば、repeat lowering の内部 template キー (`<name>#cons`) と衝突しうる。
test "decode: a `#` in a definitions.templates key is rejected (codex review #1)" {
  let tmpl_src =
    #|{"query":"parse","definition":{"definitions":{"templates":{"co#lor":{"type":"string","name":"c"}}},"positionals":[{"name":"hlcolor","ref":"co#lor"}]},"cases":[]}
  let tmpl_j = @json.parse(tmpl_src)
  let _ = dec_fixture(tmpl_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("#"))
      return
    }
  }
  abort("template key 'co#lor': expected DecodeSkip, decode succeeded")
}

///|
/// 対極確認 ([[self-written-rule-blind-spots]]): `#` を含まない普通の name は一切影響を受けない —
/// 上の 3 テストが「拒否すべき形を通さない」ことの確認なら、これは「拒否してはいけない形を誤って落と
/// さない」ことの確認。`hlcolors := color+` (このissueの本題そのもの) が今も decode + parse を通る
/// ことを固定する。
test "decode: an ordinary `#`-free name is unaffected by the reserved-name check (codex review #1 対極)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"templates": {"color": {"or": [
    #|      {"seq": [{"type": "number", "name": "r"}, {"type": "number", "name": "g"}, {"type": "number", "name": "b"}]},
    #|      {"type": "string", "name": "colorname"}
    #|    ]}}},
    #|    "positionals": [
    #|      {"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(
    render_outcome(parse(ScopeNode(df.scope), ["red"], defs=df.registry)),
    "ok{colorname=red}",
  )
}

///|
/// DR-066 §4 harness smoke test: `errors[].path` opt-in actually drives `run_case`'s comparison,
/// not just decodes without effect. A `--n` (number) value slot inside a `sub` command scope fails
/// to parse ("abc" is not a number) one command deep. The CORRECT-path case (`path: ["sub"]`) must
/// PASS; the WRONG-path case (`path: ["not-sub"]`, everything else identical) must FAIL — proving
/// `proj_errors`/`exp_errors_decode` round-trip the path into the comparison, mirroring how the
/// existing `reason` opt-in is exercised end-to-end by the real fixture corpus.
test "conformance harness: errors[].path opt-in is compared, not merely decoded (DR-066 §4)" {
  let src =
    #|{
    #|  "why": "DR-066 §4 harness smoke test for errors[].path opt-in",
    #|  "query": "parse",
    #|  "definition": {
    #|    "commands": [
    #|      {
    #|        "type": "command",
    #|        "name": "sub",
    #|        "options": [
    #|          {"name": "n", "type": "number", "long": true}
    #|        ]
    #|      }
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "correct-path",
    #|      "why": "path: [\"sub\"] matches the actual ancestor (n fails inside the sub command scope)",
    #|      "argv": ["sub", "--n", "abc"],
    #|      "expect": {
    #|        "outcome": "failure",
    #|        "errors": [
    #|          {"element": "n", "argv_pos": 2, "kind": "parse", "reason": "not_a_number", "path": ["sub"]}
    #|        ]
    #|      }
    #|    },
    #|    {
    #|      "id": "wrong-path",
    #|      "why": "path: [\"not-sub\"] is deliberately wrong — must be caught as a mismatch",
    #|      "argv": ["sub", "--n", "abc"],
    #|      "expect": {
    #|        "outcome": "failure",
    #|        "errors": [
    #|          {"element": "n", "argv_pos": 2, "kind": "parse", "reason": "not_a_number", "path": ["not-sub"]}
    #|        ]
    #|      }
    #|    }
    #|  ]
    #|}
  let j = @json.parse(src)
  let df = dec_fixture(j)
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if c.id == "correct-path" {
      if verdict != "PASS" {
        abort("expected PASS for correct-path, got: \{verdict}")
      }
    } else if verdict == "PASS" {
      abort("expected a path mismatch for wrong-path, got PASS")
    }
  }
}

///|
/// 保証 (issue 2026-07-09-constraint-path-filtering-gap の元 exact repro、DR-047 §5 明確化
/// kawaz 裁定 2026-07-09 後の end-to-end 確認): alias で同一トリガ `--v` を持つ 2 経路 (a に
/// `requires:["c"]`、c はフラグ) に対し、`run_case` (= `apply_requires_filter` →
/// `promote_collision_ambiguous` の直列適用込みの harness 本経路) が3ケースとも正しい outcome を
/// 返すことを固定する。`c` には `env:["C"]` を追加している (元 exact repro には無かったが、env
/// 救済ケースの検証に必要 — DR-047 §5 明確化「値源不問」の env 面カバー)。
test "DR-047 §5 end-to-end: exact issue repro (alias same trigger, requires) via run_case" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "a", "type": "flag", "requires": ["c"]},
    #|      {"alias": "a", "name": "v", "long": [":set:true"]},
    #|      {"name": "b", "type": "flag"},
    #|      {"alias": "b", "name": "v", "long": [":set:true"]},
    #|      {"name": "c", "type": "flag", "long": true, "env": ["C"]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "c-unset-a-excluded",
    #|      "argv": ["--v"],
    #|      "expect": {"outcome": "success", "effects": [
    #|        {"entity": "b", "op": "set", "operand": true, "source": "cli"}
    #|      ]}
    #|    },
    #|    {
    #|      "id": "c-cli-both-survive",
    #|      "argv": ["--v", "--c"],
    #|      "expect": {"outcome": "ambiguous"}
    #|    },
    #|    {
    #|      "id": "c-env-both-survive",
    #|      "argv": ["--v"],
    #|      "env": {"C": "true"},
    #|      "expect": {"outcome": "ambiguous"}
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 3)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("case '" + c.id + "' expected PASS, got: " + verdict)
    }
  }
}

///|
/// 保証 (DR-088 更新、issue value-present-ladder-gap): target `c` が非フラグ (string、default
/// 無し、env 宣言あり) の場合、env 宣言は「その値源から遅延解決する default_fn が設定されている」
/// のと同型 (DR-088 §1) — 探索中は宣言の有無だけで経路完全性を判定し (§2)、最終判定は解決後の
/// 実値を見る (§3)。env に実値があれば requires は充足する — 旧実装は `committed` の定義に
/// env を含めない (DR-047 §5「committed の定義は本 DR で変更しない」) ことを根拠に env 供給の
/// non-bool target を一律未充足としていたが、これは committed (トリガ判定の基準) と目的語の値
/// 充足判定 (別の基準、DR-088 で env 宣言込みに拡張) を混同していた誤りだった (spec fixture
/// `constraints-parse/requires-bool-target-contrast.json::c-env-set-satisfies-requires` として
/// 修正済み、本 wbtest はその同型ケースを end-to-end で固定)。
test "DR-088 end-to-end: non-bool target requires is satisfied via the env rescue path" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "a", "type": "flag", "long": true, "requires": ["c"]},
    #|      {"name": "c", "type": "string", "long": true, "env": ["C"]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "c-env-set-satisfies-requires",
    #|      "argv": ["--a"],
    #|      "env": {"C": "x"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "a", "op": "set", "operand": true, "source": "cli"}]
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 保証 (team-lead 指摘: 生存 0 → Failure の fired_action/help_entry/tried_triggers が既存
/// KTop 発 Failure と同じ素材関数 (`collect_actions`/`argmin_action`/`find_help_entry`/
/// `tried_triggers_of`) から構築され、整合が取れていることの end-to-end 確認): help
/// (`type:"help"`, DR-048 失敗時アクション) が selected な経路が、bool-target requires 違反で
/// `apply_requires_filter` により Failure に変換されても、`fired_action` が正しく "help"
/// になることを固定する。`--help --a` で help・a 共に発火 (help selected)、a は requires:[c]
/// 未充足 (c はフラグ、CLI/env どちらも未指定で false) → Success(1本) が Failure に変換される
/// 経路で、KTop 発 Failure (`failure-actions/help-basic.json`) と同じ fired_action 契約が
/// 保たれることを確認する (DR-053 §2 「fired_action と errors が 1 Failure に両立」)。
test "DR-047 §5 end-to-end: fired_action (help) survives the post-filter Success→Failure conversion" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "help", "type": "help", "long": true},
    #|      {"name": "a", "type": "flag", "long": true, "requires": ["c"]},
    #|      {"name": "c", "type": "flag", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "help-selected-survives-bool-requires-failure",
    #|      "argv": ["--help", "--a"],
    #|      "expect": {
    #|        "outcome": "failure",
    #|        "errors": [{"element": "a", "argv_pos": 2, "kind": "constraint", "reason": "requires_violated"}],
    #|        "fired_action": "help"
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 保証 (issue filter-spelling-inband-encoding-retyping — in-band 穴の閉鎖の pin): DESIGN §8.4 /
/// DR-085 §3 のオブジェクト形式 filter spelling (`{"name":..,"args":[...]}`) は、args の値そのものに
/// U+E000 (旧実装が colon 衝突回避のタグに使っていた Private Use Area 文字) が含まれていても、
/// `FilterSpelling.args` (node.mbt) の各要素として一切分割されず literal のまま保持される。旧実装
/// (U+E000 タグ付き単一文字列への in-band encode/decode) はこの入力で誤って分割・破壊していた —
/// タグ文字を含む値そのものが decode を壊す潜在穴だったため、それを埋めた側の pin。`args` に U+E000
/// を複数個 (要素の内部と要素境界紛いの位置の両方) 埋め込み、構造化フィールドがどこにも colon/tag
/// 分割ロジックを経由しないことを固定する。
test "dec_filter_chain: an object-form arg value containing U+E000 (retired in-band PUA tag) survives as a literal, unsplit" {
  let tag = "\u{E000}"
  let raw_arg = "a" + tag + "b" + tag + tag + "c"
  let src = "[{\"name\":\"regex_match\",\"args\":[\"" +
    raw_arg +
    "\"]},{\"name\":\"trim\"}]"
  let j = @json.parse(src)
  let result = dec_filter_chain(Some(j)) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
  }
  assert_eq(result.length(), 2)
  assert_eq(result[0].name, "regex_match")
  assert_eq(result[0].args.length(), 1)
  assert_eq(result[0].args[0], raw_arg)
  assert_eq(result[1].name, "trim")
  assert_eq(result[1].args.length(), 0)
}

// ── DR-091 §3: long_prefix / require_equal_separator decode (scope-level, team-lead 裁定
// 2026-07-11: 正本は definition/scope の wire キー — 要素単位は未規定語彙のため不受理) ──────────

///|
/// 保証 (DR-091 §3 "単独の空 prefix は未定義動作のまま" → decode-time definition-error): a
/// DEFINITION (scope) declaring `long_prefix: ""` WITHOUT `require_equal_separator: true` is
/// rejected at decode (`DecodeSkip`) — this is the exact ambiguity §3 exists to close (an
/// empty-prefix space-form trigger would match ANY bare token in that scope), so it must never
/// reach `parse_definition`/`inst_long` at all.
test "dec_definition: long_prefix:\"\" without require_equal_separator:true is a decode-time reject (DR-091 §3)" {
  let src =
    #|{"options":[{"name":"if","type":"string","long":true}],"config":{"long_prefix":""}}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let _ = dec_definition(o) catch { DecodeSkip(_) => return }
  fail("expected DecodeSkip, but dec_definition succeeded")
}

///|
/// 対極: `long_prefix: ""` PAIRED with `require_equal_separator: true` decodes successfully AND
/// propagates to every option in that scope's `options` array — the eq gate is what makes the
/// empty prefix safe (`ElemDef.require_equal_separator`'s doc comment), and `dec_definition`
/// (not `dec_option`) is the single place that writes these 2 fields onto each `ElemDef`.
test "dec_definition: long_prefix:\"\" WITH require_equal_separator:true decodes successfully and propagates to options (対極)" {
  let src =
    #|{"options":[{"name":"if","type":"string","long":true},{"name":"of","type":"string","long":true}],"config":{"long_prefix":"","require_equal_separator":true}}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
  }
  assert_eq(def.options.length(), 2)
  for e in def.options {
    assert_eq(e.long_prefix, "")
    assert_eq(e.require_equal_separator, true)
  }
}

///|
/// 保証 (要素単位の上書きは未規定語彙): an OPTION carrying `long_prefix` or
/// `require_equal_separator` directly (not on the enclosing definition/scope) is rejected by
/// `dec_option`'s `allowed_keys` as an unknown key — these 2 fields are scope-only wire vocabulary,
/// never element-level (team-lead 裁定 2026-07-11, the 対極 half of the previous 2 tests: this
/// pins that dec_option does NOT accept them, closing the door the earlier element-level design
/// had left open).
test "dec_option: long_prefix at the OPTION level is an unknown-key decode reject (scope-only vocabulary)" {
  let src =
    #|{"name":"if","type":"string","long":true,"long_prefix":""}
  let j = @json.parse(src)
  let _ = dec_option(j, Map([])) catch { DecodeSkip(_) => return }
  fail("expected DecodeSkip (long_prefix is not a valid option-level key)")
}

// ── issue scope-config-object-gap: DR-014 full 7-key config object + 階層継承 ─────

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
    #|  "config": {"env_prefix": "MYAPP", "auto_env": true},
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
    #|  "config": {"env_prefix": "MYAPP", "auto_env": true},
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
    #|  "config": {"env_prefix": "MYAPP", "auto_env": true}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
  }
  assert_eq(def.positionals[0].env, ["MYAPP_TARGET"])
}

///|
/// 保証 (移設後 — DESIGN §7.2 が definition-error と規範化、installer.mbt
/// `collect_eq_separator_conflict`): `require_equal_separator: true` (space form withhold) と
/// `allow_equal_separator: false` (eq form withhold) の組合せは、もはや decode-time reject では
/// ない — decode 自体は成功し、両フィールドがそのまま `options[0]` へ焼き込まれる。旧実装は
/// decode 層 (`validate_scope_config`) が scope config 単位で `DecodeSkip` を raise していたが、
/// query:definition_error fixture では decode 不能 = skip 扱いになり element 別に pin できない
/// ため、element 単位で報告できる installer 層 (`parse_definition` の Err 経路、DR-054 §4 全列挙)
/// へ矛盾検出そのものを移設した。矛盾が実際に definition-error として検出されることの固定は
/// installer_wbtest.mbt の "parse_definition: require_equal_separator:true ×
/// allow_equal_separator:false ..." 系テスト側で行う。
test "dec_definition: require_equal_separator:true + allow_equal_separator:false decodes successfully (矛盾検出は installer 層 collect_eq_separator_conflict へ移設)" {
  let src =
    #|{"options":[{"name":"if","type":"string","long":true}],"config":{"require_equal_separator":true,"allow_equal_separator":false}}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
  }
  assert_eq(def.options[0].require_equal_separator, true)
  assert_eq(def.options[0].allow_equal_separator, false)
}

///|
/// 保証 (DR-014 フル 7 キーの decode 受理 + 階層継承の運搬): `short_prefix`/`allow_equal_separator`/
/// `short_combine` も他の 4 キーと同じ decode-time bake パターンで各要素へ伝わる。`short_combine`
/// は消費側配線が未実装 (issue scope-config-object-gap 停止報告) だが、decode・継承・保持は他
/// キーと同等であることをここで固定する。
test "dec_definition: short_prefix / allow_equal_separator / short_combine all decode and bake onto options" {
  let src =
    #|{
    #|  "options": [{"name": "v", "type": "string", "long": true, "short": "v"}],
    #|  "config": {"short_prefix": "+", "allow_equal_separator": false, "short_combine": false}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
  }
  assert_eq(def.options[0].short_prefix, "+")
  assert_eq(def.options[0].allow_equal_separator, false)
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
  let _ = dec_definition(o) catch { DecodeSkip(_) => return }
  fail("expected DecodeSkip (bogus_key is not a config vocabulary word)")
}

///|
/// 保証 (issue type-none-support, DR-089 §2/§3): JSON fixture 上で `type` を省略した option が
/// none として decode され、消費 0 の純トリガとして発火・resolve を通り、シンプルモードの結果には
/// キーが一切現れない (`result: {}`) — DR-051 §1/§4 の「値の無さはフィールド不在」と同型。
/// effects にも現れない (team-lead 裁定 2026-07-11: 観測は ParserContext/explains 層の管掌、値
/// 空間なしの set エントリを発明しない — 内部表現は `flag_bare_true_variant` 再利用の Set +
/// VBool(true) placeholder のままだが、`proj_effects_ex` 側で none cell を除外する)。
test "DR-089 end-to-end: an omitted-type option decodes to none, fires as a pure trigger, absent from result" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "sep", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "sep-fires-pure-trigger",
    #|      "argv": ["--sep"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 対極: `type: "none"` を明示しても同じ挙動 (DR-089 §2「省略 = none の糖衣」の end-to-end 対称確認)。
test "DR-089 end-to-end: an explicit type:none option behaves identically to omission" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "sep", "type": "none", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "sep-fires-pure-trigger-explicit",
    #|      "argv": ["--sep"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── DR-092: inf / 非整数 float の JSON serialize 規約 (end-to-end via dec_fixture/run_case) ──

///|
/// 保証 (DR-092 §1/§2「inf は JSON string sentinel "Infinity"/"-Infinity" で表す」、実装調査
/// 2026-07-11 の実機確認結果): fixture の `result` 位置に JSON 文字列 `"Infinity"` を書いた期待値
/// (DR-092 §1 の wire 表現そのもの) が、実際の `--t inf` (float 型) 実行結果と一致する — 双方とも
/// `render_val` を経由し、GOT 側は `VNum(inf)` → MoonBit Ryu 実装の "Infinity" 特殊形、EXPECT 側は
/// JSON string decode (`json_to_value` は文字列をそのまま `VStr` に写す) → `render_val(VStr(s)) =
/// s` の素通し、で同じ文字列 "Infinity" に収束する。**production コード変更なしで DR-092 の wire
/// 表現規約が conformance harness 上で既に成立する**ことを end-to-end で固定する
/// (fixtures/value-typing/number-inf-nan.json への実 pin は main が別段で行う予定、本テストは
/// spec fixture を一切変更せずインライン JSON で同じ輪郭を先に固定するもの)。
test "DR-092 end-to-end: --t inf round-trips through result as the JSON string sentinel \"Infinity\"" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "t", "type": "float", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "inf-result-serializes-as-json-string-sentinel",
    #|      "argv": ["--t", "inf"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "t", "op": "set", "operand": "Infinity", "source": "cli"}],
    #|        "result": {"t": "Infinity"}
    #|      }
    #|    },
    #|    {
    #|      "id": "neg-inf-result-serializes-as-json-string-sentinel",
    #|      "argv": ["--t", "-Infinity"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "t", "op": "set", "operand": "-Infinity", "source": "cli"}],
    #|        "result": {"t": "-Infinity"}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

///|
/// 保証 (DR-092 §4「非整数 float の canonical serialize = shortest round-trip」、end-to-end):
/// `--t 3.14159` の result が入力綴りそのまま (丸め/桁欠落なし) で戻る — shortest round-trip の
/// 「入力と同じ最短表現に落ち着く」性質を CLI 入力からの往復で確認する (`value_str`/`render_val`
/// 直接テストの resolve_wbtest.mbt 版と対で、こちらは実 argv からの end-to-end)。
test "DR-092 end-to-end: a non-integer float CLI value round-trips via shortest round-trip in result" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "t", "type": "float", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "non-integer-float-shortest-round-trip",
    #|      "argv": ["--t", "3.14159"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "t", "op": "set", "operand": 3.14159, "source": "cli"}],
    #|        "result": {"t": 3.14159}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── codex 節目レビュー Major 1: 要素単位 scope config override ─────────────────

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
    #|  "config": {"env_prefix": "MYAPP", "auto_env": true}
    #|}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let def = dec_definition(o) catch {
    DecodeSkip(r) => abort("expected successful decode, got DecodeSkip: " + r)
  }
  assert_eq(def.positionals[0].env, ["MYAPP_TARGET"]) // auto_env 経由、scope env_prefix 連結
  assert_eq(def.positionals[1].env, ["HOME"]) // opt-out、明示 env: そのまま
}

///|
/// 保証 (要素単位 override でも DR-091 §3 の静的検査が働く — `validate_scope_config` を要素マージ
/// 直後にも呼ぶことの直接確認): 要素が `config: {"long_prefix": ""}` だけを上書きし
/// `require_equal_separator` を明示しない場合、scope 既定の `require_equal_separator: false` を
/// 継承したままになるため、スコープレベルと同じ「空 prefix が素 operand と衝突する」不整合が
/// 要素単位でも再現し decode-time reject される。
test "dec_definition: an element's own config can ALSO trigger the long_prefix:\"\" + !require_equal_separator reject" {
  let src =
    #|{"options":[{"name":"if","type":"string","long":true,"config":{"long_prefix":""}}]}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let _ = dec_definition(o) catch { DecodeSkip(_) => return }
  fail(
    "expected DecodeSkip (element-level long_prefix:\"\" without require_equal_separator:true)",
  )
}

///|
/// 保証 (要素単位 config の allowed_keys 網羅性): option の `config` object 内も scope config と
/// 同じ 7 キーのみ受理 — 未知キーは decode-time reject (DR-014 の語彙を要素単位でも発明しない)。
test "dec_definition: an option's own config rejects an unknown key just like scope config does" {
  let src =
    #|{"options":[{"name":"a","type":"string","config":{"bogus_key":true}}]}
  let o = match @json.parse(src).j_obj() {
    Some(x) => x
    None => abort("test src is not an object")
  }
  let _ = dec_definition(o) catch { DecodeSkip(_) => return }
  fail("expected DecodeSkip (bogus_key is not a config vocabulary word)")
}

///|
/// 保証 (end-to-end, DR-049 §4 HOME motivating case の完全版): `HOME` (env_prefix opt-out) の値を
/// 実際の env lookup → parse → result まで通す。auto_env:true 下で `port` は自動導出
/// (`MYAPP_PORT`) された env 名で環境変数を読み、`home_dir` は opt-out した生の `HOME` を読む —
/// 同じスコープに両方の挙動が共存することを実行結果で固定する。
test "DR-049 §4 end-to-end: an element's env_prefix:\"\" opt-out reads the raw env var name, alongside a sibling's prefixed auto_env" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "port", "type": "number"},
    #|      {"name": "home_dir", "type": "string", "env": "HOME", "config": {"env_prefix": ""}}
    #|    ],
    #|    "config": {"env_prefix": "MYAPP", "auto_env": true}
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "opt-out-element-reads-raw-env-name",
    #|      "argv": [],
    #|      "env": {"MYAPP_PORT": "8080", "HOME": "/home/kawaz"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "sources": {"port": "env", "home_dir": "env"}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── codex 節目レビュー Minor: DR-092 §5 config 値源経路の実装証跡 ───────────────

///|
/// 保証 (codex 指摘 Minor, DR-092 §5「config ファイルの JSON 値位置に "Infinity"/"-Infinity" を
/// 文字列として書いた場合、float 要素への供給は DR-050 §4 の既存経路で自動的に成立する」の
/// 実装証跡): config_file 由来の値が float 要素へ渡り、結果が DR-092 §2 の canonical serialize
/// (`"Infinity"`) で戻ることを end-to-end で固定する。fixtures/value-sources/config/value-typing.json
/// と同型の config value source 表記 (`type: "config_file"` + `config_key`) に DR-092 の inf
/// sentinel を組み合わせるだけ — DR-050 §4 が「string element の型変換パイプラインは source を
/// 問わず同一」と規定する通り、config 値源専用の特別処理は一切追加しない (本 DR §5 の「確認的明記」
/// を裏づける)。
test "DR-092 §5 end-to-end: config-origin \"Infinity\" reaches a float element and serializes canonically" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "config", "type": "config_file", "long": true, "default": "/app.toml"},
    #|      {"name": "t", "type": "float", "long": true, "config_key": ["t"]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "config-inf-string-to-float-element",
    #|      "argv": [],
    #|      "config": {"t": "Infinity"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {"t": "Infinity"},
    #|        "sources": {"t": "config"}
    #|      }
    #|    },
    #|    {
    #|      "id": "config-neg-inf-string-to-float-element",
    #|      "argv": [],
    #|      "config": {"t": "-Infinity"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {"t": "-Infinity"},
    #|        "sources": {"t": "config"}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

// ── DR-094 §9 案A: kuu_ prefix factory 名のリネーム ──────────────────────────

///|
/// 保証 (DR-094 §3/§9 案A): `definitions.types` の factory 名は `int_parser` (builtin ns の bare
/// 糖衣) / `builtin/int_parser` (ns 明示) の 2 表記形が同一 TypeShadow 実体に解決される。2 つの
/// shadow を同じ `int_round: "floor"` config で並べ、同じ fractional 入力 `2.5` を横流しして全て
/// `2` (floor 方向) に解決されることで実体の同一性を固定する — 表記が違うだけで挙動が分岐しないこと
/// の end-to-end 証跡。旧 `kuu_int_parser` prefix の移行期間終了後の拒否確認は別 test を参照。
test "DR-094 §9: int_parser の 2 表記形 (bare / builtin/ ns) が同一 factory に解決される" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {
    #|      "types": {
    #|        "t_bare": {"name": "int_parser", "config": {"int_round": "floor"}},
    #|        "t_ns": {"name": "builtin/int_parser", "config": {"int_round": "floor"}}
    #|      }
    #|    },
    #|    "options": [
    #|      {"name": "bare", "type": "t_bare", "long": true},
    #|      {"name": "ns", "type": "t_ns", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "both-forms-floor-2p5-to-2",
    #|      "argv": ["--bare", "2.5", "--ns", "2.5"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "result": {"bare": 2, "ns": 2}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 保証 (DR-094 §3/§9 案A、number_parser 版): `number_parser` / `builtin/number_parser` の 2 表記形
/// が同一 TypeShadow 実体に解決される。`number_allow_base_prefix: true` を共有 config にして `0xff`
/// (hex int opt-in) を横流しし、全て `255` に解決されることを固定する。
test "DR-094 §9: number_parser の 2 表記形 (bare / builtin/ ns) が同一 factory に解決される" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {
    #|      "types": {
    #|        "t_bare": {"name": "number_parser", "config": {"number_allow_base_prefix": true}},
    #|        "t_ns": {"name": "builtin/number_parser", "config": {"number_allow_base_prefix": true}}
    #|      }
    #|    },
    #|    "options": [
    #|      {"name": "bare", "type": "t_bare", "long": true},
    #|      {"name": "ns", "type": "t_ns", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "both-forms-hex-prefix-accepted",
    #|      "argv": ["--bare", "0xff", "--ns", "0xff"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "result": {"bare": 255, "ns": 255}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 保証 (DR-094 §9 移行期間終了): 旧 ad-hoc prefix `kuu_int_parser` は fixture pin bump
/// (37aa3b3d、全 fixture が新名へ移行済み) を境に deprecated alias としての受理を終え、他の未知
/// 語彙と同じ unsupported factory DecodeSkip に落ちる。旧名の「受理されないこと」を positive に
/// 固定する — 語彙が spec の閉集合 (DR-094 §2 builtin は closed set) であることの unknown-vocab
/// 側の証跡 (DR-054)。multiple:true 等コンテナ側の他語彙と同じ寛容ハーネスの上で、旧 factory 名
/// だけが特別に生き残らないことを示す。
test "DR-094 §9 移行期間終了: 旧 kuu_int_parser prefix は unsupported factory として拒否される" {
  let int_src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"kuu_int_parser","config":{}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let int_j = @json.parse(int_src)
  let _ = dec_fixture(int_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("unsupported factory"))
      assert_true(r.contains("kuu_int_parser"))
      return
    }
  }
  abort(
    "kuu_int_parser: expected DecodeSkip (legacy alias retired), decode succeeded",
  )
}

///|
/// 保証 (DR-094 §9 移行期間終了、number_parser 版): 旧 ad-hoc prefix `kuu_number_parser` も同様に
/// unsupported factory DecodeSkip に落ちる (int_parser 版と対称)。
test "DR-094 §9 移行期間終了: 旧 kuu_number_parser prefix は unsupported factory として拒否される" {
  let number_src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"kuu_number_parser","config":{}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let number_j = @json.parse(number_src)
  let _ = dec_fixture(number_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("unsupported factory"))
      assert_true(r.contains("kuu_number_parser"))
      return
    }
  }
  abort(
    "kuu_number_parser: expected DecodeSkip (legacy alias retired), decode succeeded",
  )
}

///|
/// 対極確認 ([[self-written-rule-blind-spots]]): リネームで受理形が増えても、未知 factory 名 (typo) の
/// capability gate は不変 — `int_parser` の typo `int_parsr` は unknown-factory DecodeSkip に落ちる。
test "DR-094 §9 対極: factory 名の typo は 3 形式リネーム後も従来通り DecodeSkip される" {
  let typo_src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"int_parsr","config":{}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let typo_j = @json.parse(typo_src)
  let _ = dec_fixture(typo_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("unsupported factory"))
      assert_true(r.contains("int_parsr"))
      return
    }
  }
  abort("int_parsr: expected DecodeSkip, decode succeeded")
}

// ── issue bool-parser-factory-unimplemented: bool_parser configurable factory ──

///|
/// 保証 (DR-074 §3/§4, DR-094 §3/§9 案A): `definitions.types` の factory 名は `bool_parser`
/// (builtin ns の bare 糖衣) / `builtin/bool_parser` (ns 明示) の 2 表記形が同一 TypeShadow 実体に
/// 解決される (int_parser/number_parser の 2 形テストと対称)。`true_values` に `"yes"` を足した
/// opt-in config を両表記で共有し、canonical-外の `"yes"` が両方とも `true` に解決されることで
/// 実体の同一性と opt-in 語彙追加の両方を同時に固定する。
test "issue bool-parser-factory-unimplemented: bool_parser の 2 表記形 (bare / builtin/ ns) が同一 factory に解決される" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {
    #|      "types": {
    #|        "t_bare": {"name": "bool_parser", "config": {"true_values": ["true", "1", "yes"]}},
    #|        "t_ns": {"name": "builtin/bool_parser", "config": {"true_values": ["true", "1", "yes"]}}
    #|      }
    #|    },
    #|    "options": [
    #|      {"name": "bare", "type": "t_bare", "long": true},
    #|      {"name": "ns", "type": "t_ns", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "both-forms-yes-optin-to-true",
    #|      "argv": ["--bare", "yes", "--ns", "yes"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "result": {"bare": true, "ns": true}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 対極確認 (DR-074 §3): `bool_parser` の config を全く指定しない (`"config": {}`) と、canonical
/// default (`true_values: ["true","1"]` / `false_values: ["false","0",""]` / `case_insensitive:
/// true`) が適用される — factory 経由でも既存 `parse_bool` ハードコード実装と同じ挙動になることの
/// pin (config データ化が挙動を変えていないことの証跡)。
test "issue bool-parser-factory-unimplemented: bool_parser canonical default (config省略) は既存 parse_bool と同値" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"types": {"t": {"name": "bool_parser", "config": {}}}},
    #|    "options": [{"name": "v", "type": "t", "long": true}]
    #|  },
    #|  "cases": [
    #|    {"id": "true-word", "argv": ["--v", "True"], "expect": {"outcome": "success", "result": {"v": true}}},
    #|    {"id": "one", "argv": ["--v", "1"], "expect": {"outcome": "success", "result": {"v": true}}},
    #|    {"id": "false-word", "argv": ["--v", "FALSE"], "expect": {"outcome": "success", "result": {"v": false}}},
    #|    {"id": "zero", "argv": ["--v", "0"], "expect": {"outcome": "success", "result": {"v": false}}},
    #|    {"id": "empty", "argv": ["--v", ""], "expect": {"outcome": "success", "result": {"v": false}}},
    #|    {"id": "yes-still-rejected", "argv": ["--v", "yes"], "expect": {"outcome": "failure", "errors": [{"element": "v", "argv_pos": 1, "kind": "parse", "reason": "not_a_bool"}]}}
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 6)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

///|
/// 保証 (DR-074 §4 `case_insensitive` config キー): `case_insensitive: false` の opt-in 方言
/// (JSON/TOML 準拠) では canonical で通っていた大小混在の綴り (`"TRUE"` 等、`true_values` の
/// 完全一致文字列以外) が `not_a_bool` に落ちる — case_insensitive の既定 `true` から明示的に
/// 外れたときだけ厳密照合になることの pin。
test "issue bool-parser-factory-unimplemented: case_insensitive:false で大小厳密照合になる" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"types": {"t": {"name": "bool_parser", "config": {"case_insensitive": false}}}},
    #|    "options": [{"name": "v", "type": "t", "long": true}]
    #|  },
    #|  "cases": [
    #|    {"id": "exact-true-still-ok", "argv": ["--v", "true"], "expect": {"outcome": "success", "result": {"v": true}}},
    #|    {"id": "mixed-case-rejected", "argv": ["--v", "TRUE"], "expect": {"outcome": "failure", "errors": [{"element": "v", "argv_pos": 1, "kind": "parse", "reason": "not_a_bool"}]}}
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

///|
/// 対極確認 ([[self-written-rule-blind-spots]] / int_parser の未知キー扱いが手本): `bool_parser`
/// の config に宣言されていないキーを渡すと、他の configurable factory (int_parser/number_parser)
/// と同じ unknown-key decode reject に落ちる — bool_parser だけ特別に寛容になっていないことの pin。
test "issue bool-parser-factory-unimplemented: bool_parser config の未知キーは decode-time reject (int_parser/number_parser と同型)" {
  let src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"bool_parser","config":{"typo_key":true}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let j = @json.parse(src)
  let _ = dec_fixture(j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("bool_parser config"))
      assert_true(r.contains("typo_key"))
      return
    }
  }
  abort(
    "bool_parser config with unknown key: expected DecodeSkip, decode succeeded",
  )
}

///|
/// codex レビュー指摘 (2026-07-12) の回帰 pin: 異名の dd/none 要素の committed placeholder
/// binding は完全経路の dedup に混入しない (DESIGN §15.1「経路の同一性は実体への観測可能な
/// 効果列で判定する」/ DR-030「実体 = 値セル」/ DR-093 §6「none の発火事実は ParserContext 層」)。
/// 同一 pattern の 2 つの dd 要素 (trig_a / trig_b) が同じトークンに発火しうる 2 枝は、
/// observable な result/effects が同一 ({rest: ["x"]}) なので 1 経路に dedup され Success になる。
/// 修正前は placeholder の key 差 (trig_a vs trig_b) が strip_link 後の binding 配列比較に
/// 混入して偽 Ambiguous になっていた (eval.mbt の dedup キー側だけ strip_none_placeholders を
/// 通す修正で解消 — `eff` 本体は保持するので build_result / ParserContext 側は不変)。
/// 標準 comparator (run_case) を通すことで「result に dd 名が漏れない」も同時に固定する。
test "codex-20260712: differing dd placeholder keys do not split path dedup (DESIGN §15.1)" {
  let src =
    #|{
    #|  "why": "dedup regression pin (inline)",
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "trig_a", "type": "dd", "match": "^x$", "self": "keep"},
    #|      {"name": "trig_b", "type": "dd", "match": "^x$", "self": "keep"}
    #|    ],
    #|    "positionals": [
    #|      {"name": "rest", "type": "string", "repeat": {"min": 0}}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "same-observable-converges-to-success",
    #|      "why": "両 dd が同一トークン x に発火しうるが観測可能効果列は同一 → 1 経路 (Success)、rest に x (self: keep)",
    #|      "argv": ["x"],
    #|      "expect": {"outcome": "success", "result": {"rest": ["x"]}}
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}
