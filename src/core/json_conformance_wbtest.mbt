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
  value_requires? : Array[(String, String, Array[String])] = [],
  default? : Value? = None,
  int_round? : RoundMode = RError,
  allow_base_prefix? : Bool = false,
  piece_filters? : Array[String] = [],
  value_filters? : Array[String] = [],
  cell_filters? : Array[String] = [],
  ref_? : String? = None,
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
    value_requires,
    deprecated: false,
    default_value: default,
    int_round,
    allow_base_prefix,
    piece_filters,
    value_filters,
    cell_filters,
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
  default? : Value? = None,
  int_round? : RoundMode = RError,
  allow_base_prefix? : Bool = false,
  piece_filters? : Array[String] = [],
  value_filters? : Array[String] = [],
  cell_filters? : Array[String] = [],
  body? : ElemBody = BCell,
) -> ElemDef {
  {
    name,
    ty,
    long: LList([]),
    variants: [],
    short: [],
    env: [],
    is_dd: false,
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
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    value_requires: [],
    deprecated: false,
    default_value: default,
    int_round,
    allow_base_prefix,
    piece_filters,
    value_filters,
    cell_filters,
    body,
  }
}

///|
fn dd_marker() -> ElemDef {
  {
    name: "--",
    ty: TStr,
    long: LList([]),
    variants: [],
    short: [],
    env: [],
    is_dd: true,
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
    value_requires: [],
    deprecated: false,
    default_value: None,
    int_round: RError,
    allow_base_prefix: false,
    piece_filters: [],
    value_filters: [],
    cell_filters: [],
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
    BoolArg(x, _) => Some(x)
    SepArg(x, _, _, _, _, _, _) => Some(x)
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
    NativeMatch(ShortCombine(prefix=_, entries~)) => {
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
    }
  }
  {
    name: e.name,
    typ,
    default_: e.default_value,
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
/// Result with the DR-052 result-key axis applied.
fn proj_result_export(
  sc : Scope,
  binds : Array[Binding],
  ekmap : Map[String, ExportKey],
) -> String {
  render_rval_sorted(
    build_result(
      apply_export_keys(binds, ekmap),
      accum_cells(sc),
      apply_export_to_defaults(default_cells(sc), ekmap),
      [],
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
fn proj_sources(sc : Scope, resolved : Array[Binding]) -> String {
  let items : Array[String] = []
  for e in sc.entities {
    if e.is_config_file {
      continue
    }
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
      Some(s) => items.push(e.name + "=" + s)
      None =>
        // DR-044 uniform array (issue 2026-07-09-env-separator-split-gap's env-separator-
        // split.json, `sources` check): an unfired multiple/repeat cell decays to `[]` (never
        // absent, same guarantee flag/bool's default preset gets below) — regardless of type,
        // and regardless of whether the element ALSO declared an explicit `default:` (accum
        // cells usually don't; the empty array IS the implicit default here, unconditionally).
        if e.accum is Some(_) {
          items.push(e.name + "=default")
        } else if (e.ty == TFlag || e.ty == TBool) && e.accum is None {
          match e.default_value {
            Some(_) => items.push(e.name + "=default")
            None => ()
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
    other => raise DecodeSkip("value type '" + other + "'")
  }
}

///|
/// DR-061 §3 configurable factory の type shadow: user 定義の型名を base Ty + parse 相 config
/// (現状 int_round のみ) に解決する。fixture の `definitions.types.<name>` → TypeShadow の map で
/// 保持し、dec_option / dec_positional の `type: "<name>"` 解決で consultation する。canonical 型名
/// (string/number/int/...) は shadow で override 可能だが本 fixture では未使用 (`kuu_int_parser` factory
/// のみ扱う; `kuu_number_parser` = number_allow_base_prefix は次タスク)。
struct TypeShadow {
  base : Ty
  int_round : RoundMode
  // DR-074 §2 `number_allow_base_prefix` (kuu_number_parser factory config)。canonical default = false。
  // TypeShadow が担う base 側の flag は canonical default が false なので、int_round と直交な平坦キー。
  allow_base_prefix : Bool
} derive(Eq, Debug)

///|
/// Decode `definitions.types` (DR-061 §3 `{name: <factory>, config: {<key>: <value>, ...}}`) into
/// a shadow map. 各 shadow は base Ty (factory 名から導出) と平坦 config キーで構成される。
/// 現状サポート: `kuu_int_parser` (base = TInt、config = `int_round`)。他の factory 名は
/// DecodeSkip で明示的に unsupported 扱い (typo 検出、DR-061 §4 は factory 自身が config 値を検証
/// する規定なので、type/factory 認識のこの層は capability gate として振る舞う)。
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
      "kuu_int_parser" => {
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
              "kuu_int_parser config",
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
        })
      }
      "kuu_number_parser" => {
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
              "kuu_number_parser config",
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
        })
      }
      other =>
        raise DecodeSkip(
          "definitions.types[" +
          name +
          "] unsupported factory '" +
          other +
          "' (only kuu_int_parser / kuu_number_parser are wired in the current substrate)",
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
fn dec_or(
  j : Json,
  parent_name : String,
) -> Array[(String, String, Array[String])] raise DecodeSkip {
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
    let reqs = dec_strs(bo.get("requires"))
    if reqs.length() > 0 {
      let branch_id = jf_str(bo, "id").unwrap_or(parent_name)
      check_reserved_name(branch_id, "or branch")
      vrs.push((branch_id, exact, reqs))
    }
  }
  vrs
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
  let (ty, int_round_from_shadow) = match jf_str(o, "type") {
    Some(t) =>
      match shadows.get(t) {
        Some(sh) => (sh.base, sh.int_round)
        None => (dec_ty(t), RError)
      }
    None => raise DecodeSkip("or branch leaf missing 'type'")
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
      "export_key", "config_key", "deprecated", "or", "piece_filters", "value_filters",
      "cell_filters", "ref", "repeat",
    ],
    "option",
  )
  let tystr = match jf_str(o, "type") {
    Some(t) => t
    None =>
      if has_key(o, "or") || has_key(o, "ref") {
        // DR-078 §1: a `ref` element's own consumption is replaced by the referenced template
        // (`elem_head`'s `Ref(r)` head, ty unused there) — same "type is moot" reasoning `or`
        // already gets. `dec_positional` already defaults ty to TStr when absent for the same
        // shape reason; this mirrors that on the option side.
        "string"
      } else {
        raise DecodeSkip("option missing 'type'")
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
  let value_requires = match structural_or {
    Some(_) => []
    None =>
      match o.get("or") {
        Some(orj) => dec_or(orj, name)
        None => []
      }
  }
  if tystr == "dd" {
    return DOpt({ ..dd_marker(), name, })
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
  ) = match tystr {
    "help" => (TFlag, true, false, RError, false)
    "config_file" => (TStr, false, true, RError, false)
    _ =>
      match shadows.get(tystr) {
        Some(sh) => (sh.base, false, false, sh.int_round, sh.allow_base_prefix)
        None => (dec_ty(tystr), false, false, RError, false)
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
  let default = match o.get("default") {
    Some(d) => Some(json_to_value(d))
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
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  let config_key : Array[String]? = match o.get("config_key") {
    Some(c) => Some(dec_strs(Some(c)))
    None => None
  }
  let deprecated = bool_field(o, "deprecated", false)
  let piece_filters = dec_strs(o.get("piece_filters"))
  let value_filters = dec_strs(o.get("value_filters"))
  let cell_filters = dec_strs(o.get("cell_filters"))
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
      value_requires~,
      default~,
      int_round=int_round_from_shadow,
      allow_base_prefix=base_prefix_from_shadow,
      piece_filters~,
      value_filters~,
      cell_filters~,
      ref_~,
      body=match structural_or {
        Some(branches) => BOr(branches)
        None => BCell
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
      "cell_filters", "ref",
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
  let (ty, int_round_from_shadow, base_prefix_from_shadow) = match
    jf_str(o, "type") {
    Some(t) =>
      match shadows.get(t) {
        Some(sh) => (sh.base, sh.int_round, sh.allow_base_prefix)
        None => (dec_ty(t), RError, false)
      }
    None => (TStr, RError, false)
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
  let default = match o.get("default") {
    Some(d) => Some(json_to_value(d))
    None => None
  }
  let piece_filters = dec_strs(o.get("piece_filters"))
  let value_filters = dec_strs(o.get("value_filters"))
  let cell_filters = dec_strs(o.get("cell_filters"))
  let ref_ = jf_str(o, "ref")
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
    piece_filters~,
    value_filters~,
    cell_filters~,
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
fn dec_command(
  j : Json,
  shadows : Map[String, TypeShadow],
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
    ["type", "name", "options", "positionals", "commands", "export_key"],
    "command",
  )
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("command missing 'name'")
  }
  check_reserved_name(name, "command")
  // 子コマンドの definition は親の shadows を継承する (DR-061 は scope 継承を規定していないが、
  // slice実装は fixture が命令的に flat な type shadow を宣言するだけなので親→子への単純伝搬で足りる)
  let body = dec_definition(o, shadows~)
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
) -> Definition raise DecodeSkip {
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
          DOpt(e) => options.push(e)
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
        positionals.push(dec_positional(pj, shadows))
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
        match dec_command(cj, shadows) {
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
    ["options", "positionals", "commands", "definitions"],
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
    ["options", "positionals", "commands", "definitions"],
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
    ["options", "positionals", "commands", "definitions"],
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
    if e.ty != TFlag && e.ty != TBool && e.default_value is Some(_) {
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
fn resolve_tree(
  sc : Scope,
  binds : Array[Binding],
  dc : DCase,
  path : Array[String],
  inherited : Map[String, Value],
) -> Result[Array[Binding], String] {
  let here : Array[Binding] = []
  for b in binds {
    if path_eq(b.scope, path) {
      here.push(b)
    }
  }
  // See `do_resolve_pe`'s comment: real final argv position, not the `-1` default.
  let at_pos = dc.argv.length()
  let resolved = match dc.cfg {
    NoCfg =>
      match resolve_scope(sc, here, dc.env, inherited~, at_pos~) {
        Ok(rb) => rb
        Err(pe) => return Err(pe_msg(pe))
      }
    CfgObj(obj) =>
      match
        resolve_scope_config(
          sc,
          here,
          dc.env,
          fn(_p) { Some(obj) },
          path~,
          inherited~,
          at_pos~,
        ) {
        Ok(rb) => rb
        Err(pe) => return Err(pe_msg(pe))
      }
    CfgFiles(files) =>
      match
        resolve_scope_config(
          sc,
          here,
          dc.env,
          fn(p) { cfg_lookup(files, p) },
          path~,
          inherited~,
          at_pos~,
        ) {
        Ok(rb) => rb
        Err(pe) => return Err(pe_msg(pe))
      }
  }
  let out : Array[Binding] = []
  for b in here {
    if is_sentinel(b.key) {
      out.push(b)
    }
  }
  for b in resolved {
    out.push({ ..b, scope: path })
  }
  let child_inherited : Map[String, Value] = Map([])
  for k, v in inherited {
    child_inherited.set(k, v)
  }
  for b in resolved {
    child_inherited.set(b.key, b.value)
  }
  for g in sc.greedy {
    match g {
      CmdSat(name, child) => {
        let childpath = path_push(path, name)
        if scope_entered(binds, childpath) {
          match resolve_tree(child, binds, dc, childpath, child_inherited) {
            Ok(rb) =>
              for b in rb {
                out.push(b)
              }
            Err(m) => return Err(m)
          }
        }
      }
      _ => ()
    }
  }
  Ok(out)
}

///|
fn scope_entered(binds : Array[Binding], path : Array[String]) -> Bool {
  for b in binds {
    if path_eq(b.scope, path) {
      return true
    }
  }
  false
}

///|
fn run_case(df : DecodedFixture, dc : DCase) -> String {
  let sc = df.scope
  let root = ScopeNode(sc)
  // DR-047 §5 明確化 (kawaz 裁定 2026-07-09): bool-target requires/CRequiresIf は KTop (CLI 面
  // のみ) では常にスキップされているので、値源 (env) が解ける後段でここでフィルタする
  // (cell_filters と同じ側、`resolve.mbt` の `apply_bool_requires_filter` — 経路数に応じて
  // success/ambiguous/failure を再確定)。DR-021 → DR-073 の export-key collision 昇格
  // (`promote_collision_ambiguous`) より先に適用する — 責務が異なる2つの後処理 (「経路の成立
  //自体」と「export-key 衝突による Success→Ambiguous 昇格」) を素直に直列に並べる。
  let outcome = promote_collision_ambiguous(
    apply_bool_requires_filter(
      parse(root, dc.argv, defs=df.registry),
      root,
      df.registry,
      dc.env,
      dc.argv.length(),
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
                    let asr = proj_sources(sc, rb)
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
        Ambiguous(d) =>
          match dc.exp_interps {
            Some(ei) => {
              let got : Array[String] = []
              for interp in d.interpretations {
                // Result-object view is always rendered (DR-053 §3 骨格温存)
                let view = render_rval_sorted(
                  build_result(
                    apply_export_keys(interp.binds, df.ekmap),
                    accum_cells(sc),
                    [],
                    [],
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
              accum_cells(df.scope),
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
/// `requires:["c"]`、c はフラグ) に対し、`run_case` (= `apply_bool_requires_filter` →
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
/// 保証: 前 wbtest との対 — target `c` が非フラグ (string、default 無し) なら DR-047 §5 明確化の
/// 対象外 (bool でない) なので、KTop の既存 CLI-only 判定がそのまま効く。env で値を与えても
/// (env は committed を立てない、DR-047 §5「committed の定義は本 DR で変更しない」) requires は
/// 充足しない — bool target 限定の新挙動が non-bool target まで漏れ出していないことを固定する。
test "DR-047 §5 end-to-end: non-bool target requires is unaffected by the env rescue path" {
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
    #|      "id": "c-env-set-still-fails",
    #|      "argv": ["--a"],
    #|      "env": {"C": "x"},
    #|      "expect": {
    #|        "outcome": "failure",
    #|        "errors": [{"element": "a", "argv_pos": 1, "kind": "constraint", "reason": "requires_violated"}]
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
/// `apply_bool_requires_filter` により Failure に変換されても、`fired_action` が正しく "help"
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
