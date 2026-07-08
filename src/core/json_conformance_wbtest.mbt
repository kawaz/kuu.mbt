// json_conformance_wbtest.mbt — JSON-DIRECT conformance runner (query: "parse" + "lower").
//
// PORTED FROM: kawaz/kuu.mbt slice/poc/{json_conformance_wbtest,lower_runner_wbtest,helpers_wbtest,
// fixture_runner_wbtest}.mbt — verbatim structure with API adaptations for main src/core:
//   - ParseError is 5-tuple (element/argv_pos/kind/reason/message, DR-066): proj_errors and
//     exp_errors_str include `reason` when the fixture asserts it (per-error opt-in, CONFORMANCE §3).
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
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2 — Builders (mirror slice helpers: opt/pos/dd_marker/cmd/alias/rep/def_)
// ═══════════════════════════════════════════════════════════════════════════════

///|
fn opt(
  name : String,
  ty : Ty,
  long? : Array[String] = [],
  variants? : Array[Variant] = [],
  short? : Array[Char] = [],
  env? : Array[String] = [],
  global? : Bool = false,
  inherit_? : Bool = false,
  inheritable? : Bool = false,
  multiple? : Bool = false,
  fail_action? : Bool = false,
  config_file? : Bool = false,
  config_key? : Array[String]? = None,
  export_? : ExportKey = EkUnset,
  requires? : Array[String] = [],
  conflicts? : Array[String] = [],
  exclusive? : Array[String] = [],
  value_requires? : Array[(String, Array[String])] = [],
  default? : Value? = None,
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
    ref_target: None,
    repeat: None,
    optional: false,
    multiple,
    separator: None,
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
  separator? : String? = None,
  config_key? : Array[String]? = None,
  export_? : ExportKey = EkUnset,
  ref_? : String? = None,
  default? : Value? = None,
) -> ElemDef {
  {
    name,
    ty,
    long: [],
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
    separator,
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
  }
}

///|
fn dd_marker() -> ElemDef {
  {
    name: "--",
    ty: TStr,
    long: [],
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
  }
}

///|
/// Naive scalar coercion for the variant DSL operand (`no:set:false` → VBool). Matches slice's
/// env_value(ty, s) form. The main env_value in resolve.mbt requires (element, ty, s, at_pos)
/// and returns Result — but here the input is a static DSL literal (bool false / "0" / "readonly"),
/// so a strict Result is not needed. Fallback = VStr.
fn dsl_variant_value(ty : Ty, s : String) -> Value {
  match ty {
    TNum | TInt =>
      match parse_number(s) {
        Some(d) => VNum(d)
        None => VStr(s)
      }
    TFloat =>
      match parse_float(s) {
        Some(d) => VNum(d)
        None => VStr(s)
      }
    TFlag | TBool =>
      match parse_bool(s) {
        Some(b) => VBool(b)
        None => VBool(s == "true" || s == "1")
      }
    TStr => VStr(s)
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
    CRequiresIf(el, v, ts) =>
      "requires_if{element=" +
      el +
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
    StrArg(x) => Some(x)
    NumArg(x) => Some(x)
    SepArg(x, _) => Some(x)
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
      TNum => "number"
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
      Many(inner) => walk(inner)
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
/// §2 CLI effects, EXCLUDING config_file infra cells. `set` renders operand; other ops render bare.
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
      Set =>
        items.push(
          "\{b.key}:set(\{render_val(b.value)})@\{render_src(b.source)}",
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
/// §2 failure error set. Emits `element@pos/kind` per error; if the fixture asserted `reason` at all
/// (want_has_reason), the got side includes `/reason` too so a per-error opt-in comparison stays
/// aligned. sorted as a set.
fn proj_errors(errs : Array[ParseError], with_reason : Bool) -> String {
  let items : Array[String] = []
  for e in errs {
    if with_reason {
      items.push(
        "\{e.element}@\{e.argv_pos}/\{render_kind(e.kind)}/\{e.reason}",
      )
    } else {
      items.push("\{e.element}@\{e.argv_pos}/\{render_kind(e.kind)}")
    }
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
/// defaults report `default` when no other seat surfaced (LOWERING §A.5).
fn proj_sources(sc : Scope, resolved : Array[Binding]) -> String {
  let items : Array[String] = []
  for e in sc.entities {
    if e.is_config_file {
      continue
    }
    let mut src : String? = None
    for b in resolved {
      if b.key == e.name && !is_sentinel(b.key) {
        src = Some(render_src(b.source))
      }
    }
    match src {
      Some(s) => items.push(e.name + "=" + s)
      None =>
        if (e.ty == TFlag || e.ty == TBool) && e.accum is None {
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
  // errors face: (asserted-set-string, whether fixture provided reason on any error)
  exp_errors : String?
  exp_errors_with_reason : Bool
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

///|
fn split_colon(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == ':' {
      out.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  out.push(cur)
  out
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
    match eo.get("operand") {
      Some(j) =>
        items.push("\{entity}:\{op}(\{render_val(json_to_value(j))})@\{source}")
      None => items.push("\{entity}:\{op}@\{source}")
    }
  }
  join_comma(items)
}

///|
fn exp_result_str(res : Json) -> String raise DecodeSkip {
  render_rval_sorted(json_to_rval(res))
}

///|
/// Decode the fixture's errors[] and report both the sorted set-string and whether any error had
/// a `reason` field (DR-066): with_reason drives got-side inclusion so per-error opt-in comparison
/// stays aligned.
fn exp_errors_decode(errs : Json) -> (String, Bool) raise DecodeSkip {
  let a = match errs.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("errors is not an array")
  }
  // detect reason opt-in first (per fixture set, not per element)
  let mut with_reason = false
  for e in a {
    match e.j_obj() {
      Some(eo) => if has_key(eo, "reason") { with_reason = true }
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
    if with_reason {
      let reason = match jf_str(eo, "reason") {
        Some(s) => s
        None => "" // absent on a specific error — compare against empty reason on got side
      }
      items.push("\{element}@\{pos}/\{kind}/\{reason}")
    } else {
      items.push("\{element}@\{pos}/\{kind}")
    }
  }
  sort_items(items)
  ("{" + join_comma(items) + "}", with_reason)
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
    other => raise DecodeSkip("value type '" + other + "'")
  }
}

///|
fn dec_variant(
  elem : String,
  name : String,
  ty : Ty,
) -> Variant? raise DecodeSkip {
  if elem == ":set" {
    return None
  }
  let parts = split_colon(elem)
  if parts.length() == 1 {
    return None
  }
  let prefix = parts[0]
  let op : EffectOp = match parts[1] {
    "set" => Set
    "unset" => Unset
    "empty" => Empty
    "default" => Default
    other => raise DecodeSkip("variant op '" + other + "'")
  }
  let trigger = prefix + "-" + kebab(name)
  let operand : Value? = if parts.length() >= 3 {
    Some(dsl_variant_value(ty, parts[2]))
  } else {
    None
  }
  Some({ trigger, op, operand })
}

///|
fn dec_long(
  j : Json,
  name : String,
  ty : Ty,
) -> (Array[String], Array[Variant]) raise DecodeSkip {
  match j.j_bool() {
    Some(true) => ([":set"], [])
    Some(false) => ([], [])
    None =>
      match j.j_arr() {
        Some(a) => {
          let longs : Array[String] = []
          let vars : Array[Variant] = []
          for e in a {
            let s = match e.j_str() {
              Some(x) => x
              None => raise DecodeSkip("long[] element is not a string")
            }
            match dec_variant(s, name, ty) {
              Some(v) => vars.push(v)
              None => longs.push(s)
            }
          }
          (longs, vars)
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
fn dec_multiple(j : Json) -> (Bool, String?) raise DecodeSkip {
  match j.j_bool() {
    Some(b) => return (b, None)
    None => ()
  }
  match j.j_str() {
    Some("append") => return (true, None)
    Some(other) => raise DecodeSkip("multiple preset '" + other + "'")
    None => ()
  }
  match j.j_obj() {
    Some(o) => {
      allowed_keys(o, ["accumulator", "separator"], "multiple")
      match jf_str(o, "accumulator") {
        Some("append") => ()
        Some(a) => raise DecodeSkip("multiple.accumulator '" + a + "'")
        None => ()
      }
      (true, jf_str(o, "separator"))
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
  let short = dec_short(o)
  let long_override : Array[String]? = match o.get("long") {
    Some(lj) =>
      match lj.j_arr() {
        Some(a) => {
          let ls : Array[String] = []
          for e in a {
            match e.j_str() {
              Some(s) => ls.push(s)
              None => raise DecodeSkip("alias long[] element is not a string")
            }
          }
          Some(ls)
        }
        None =>
          match lj.j_bool() {
            Some(true) => Some([":set"])
            Some(false) => Some([])
            None => raise DecodeSkip("alias long is not a bool/array")
          }
      }
    None => None
  }
  let deprecated = bool_field(o, "deprecated", false)
  { target, name, short, long_override, deprecated }
}

///|
fn dec_or(j : Json) -> Array[(String, Array[String])] raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("or is not an array")
  }
  for e in a {
    match e.j_obj() {
      Some(bo) =>
        if has_key(bo, "seq") || has_key(bo, "type") {
          raise DecodeSkip(
            "variable-arity or-option (branches are consumption grammars — a seq of typed cells vs a single typed cell): slice ElemDef carries one value cell per option and dec_or models only value-enum exact-branches, so parse_definition has no builder for Or([Seq([NumArg,…]),StrArg]) at the §5 contract path",
          )
        }
      None => ()
    }
  }
  let vrs : Array[(String, Array[String])] = []
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
      vrs.push((exact, reqs))
    }
  }
  vrs
}

///|
fn dec_option(j : Json) -> DElem raise DecodeSkip {
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
      "export_key", "config_key", "deprecated", "or",
    ],
    "option",
  )
  let value_requires = match o.get("or") {
    Some(orj) => dec_or(orj)
    None => []
  }
  let tystr = match jf_str(o, "type") {
    Some(t) => t
    None =>
      if has_key(o, "or") {
        "string"
      } else {
        raise DecodeSkip("option missing 'type'")
      }
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("option missing 'name'")
  }
  if tystr == "dd" {
    return DOpt({ ..dd_marker(), name, })
  }
  let (ty, fail_action, config_file) = match tystr {
    "help" => (TFlag, true, false)
    "config_file" => (TStr, false, true)
    _ => (dec_ty(tystr), false, false)
  }
  let (longs, vars) = match o.get("long") {
    Some(lj) => dec_long(lj, name, ty)
    None => ([], [])
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
  let (multiple, sep) = match o.get("multiple") {
    Some(m) => dec_multiple(m)
    None => (false, None)
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
  DOpt({
    ..opt(
      name,
      ty,
      long=longs,
      variants=vars,
      short~,
      env~,
      global~,
      inherit_=inherit_flag,
      inheritable~,
      multiple~,
      fail_action~,
      config_file~,
      config_key~,
      export_~,
      requires~,
      conflicts~,
      exclusive~,
      value_requires~,
      default~,
    ),
    separator: sep,
    deprecated,
  })
}

///|
fn dec_positional(j : Json) -> ElemDef raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("positional is not an object")
  }
  if has_key(o, "positionals") {
    raise DecodeSkip(
      "nested-group positional (repeat over a named sub-sequence): slice ElemDef is flat, parse_definition builds no IdxRepeat with a distinct inner-element name/export_key",
    )
  }
  if has_key(o, "or") {
    raise DecodeSkip(
      "structural or-positional (branches are consumption grammars binding distinct named cells): slice ElemDef is flat with one value cell per element — lower_positional builds a single value_prim per positional, so parse_definition has no builder for Or([Seq([…]),…]) at the §5 contract path",
    )
  }
  allowed_keys(
    o,
    [
      "id", "name", "type", "repeat", "optional", "multiple", "separator", "export_key",
      "config_key", "default",
    ],
    "positional",
  )
  let ty = match jf_str(o, "type") {
    Some(t) => dec_ty(t)
    None => TStr
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("positional missing 'name'")
  }
  let repeat : RepeatSpec? = match o.get("repeat") {
    Some(r) => Some(dec_repeat(r))
    None => None
  }
  let optional = bool_field(o, "optional", false)
  let (multiple, sep) = match o.get("multiple") {
    Some(m) => dec_multiple(m)
    None => (false, None)
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
  pos(
    name,
    ty,
    repeat~,
    optional~,
    multiple~,
    separator=sep,
    config_key~,
    export_~,
    default~,
  )
}

///|
fn dec_command(j : Json) -> DCmd raise DecodeSkip {
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
  let body = dec_definition(o)
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  DCommand({ name, body, export_key: export_ })
}

///|
fn dec_definition(o : Map[String, Json]) -> Definition raise DecodeSkip {
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
        match dec_option(oj) {
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
        positionals.push(dec_positional(pj))
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
        match dec_command(cj) {
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
  let (exp_errors, exp_errors_with_reason) = match eo.get("errors") {
    Some(x) => {
      let (s, wr) = exp_errors_decode(x)
      (Some(s), wr)
    }
    None => (None, false)
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
  allowed_keys(defo, ["options", "positionals", "commands"], "definition")
  let def = dec_definition(defo)
  let registry : Map[String, Node] = Map([])
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
  allowed_keys(o, ["exact"], "golden greedy exact")
  GExact(req_field(o, "exact"))
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
      allowed_keys(
        o,
        ["kind", "element", "value", "targets"],
        "requires_if constraint",
      )
      CRequiresIf(
        req_field(o, "element"),
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
  allowed_keys(defo, ["options", "positionals", "commands"], "definition")
  let def = dec_definition(defo)
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
fn do_resolve(
  sc : Scope,
  cli : Array[Binding],
  dc : DCase,
) -> Result[Array[Binding], String] {
  match dc.cfg {
    NoCfg =>
      match resolve_scope(sc, cli, dc.env) {
        Ok(rb) => Ok(rb)
        Err(pe) => Err(pe_msg(pe))
      }
    CfgObj(obj) =>
      match resolve_scope_config(sc, cli, dc.env, fn(_p) { Some(obj) }) {
        Ok(rb) => Ok(rb)
        Err(pe) => Err(pe_msg(pe))
      }
    CfgFiles(files) =>
      match
        resolve_scope_config(sc, cli, dc.env, fn(p) { cfg_lookup(files, p) }) {
        Ok(rb) => Ok(rb)
        Err(pe) => Err(pe_msg(pe))
      }
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
  let resolved = match dc.cfg {
    NoCfg =>
      match resolve_scope(sc, here, dc.env, inherited~) {
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
  let outcome = parse(ScopeNode(sc), dc.argv, defs=df.registry)
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
              let ae = proj_errors(d.errors, dc.exp_errors_with_reason)
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
        other => problems.push("EXPECTED-FAILURE got=" + render_outcome(other))
      }
    _ =>
      match outcome {
        Ambiguous(d) =>
          match dc.exp_interps {
            Some(ei) => {
              let got : Array[String] = []
              for interp in d.interpretations {
                got.push(
                  render_rval_sorted(
                    build_result(
                      apply_export_keys(interp, df.ekmap),
                      accum_cells(sc),
                      [],
                      [],
                    ),
                  ),
                )
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
/// MDR-001 §6).
///
/// Initial population (2026-07-08 first run, journal 2026-07-08-conformance-first-run.md):
/// 17 slice-inherited entries. Additional 3 new-implementation delta entries are NOT ledgered
/// here — they are tracked as regressions to be fixed in eval/matcher core (see journal §
/// "新実装 delta 3 件"), so the divergence-ledger assertion stays red until they are addressed.
fn known_divergences() -> Array[String] {
  [
    // ── DR-052 §値枝 id 直交 / DR-055 §1 value-conditional requires: `or` 値枝の `id` (fmt_json) が
    //     属性する CRequiresIf の element 名を anonymous 枝 id に紐づけられず、親 element (format) に付く。
    //     main の ElemDef は slice と同じく flat で anonymous 枝 id を持たない。reason は fixture が
    //     opt-in で書いた requires_violated (DR-066 §3 v1 vocab)。追従は「value-branch id 属性の再設計」issue で。
    "constraints-parse/default-interaction.json::value-branch-cli-trigger :: errors got={format@2/constraint/requires_violated} want={fmt_json@2/constraint/requires_violated}",
    "constraints-parse/requires.json::value-requires-violated :: errors got={format@2/constraint/requires_violated} want={fmt_json@2/constraint/requires_violated}",
    // ── DESIGN §15.5 export-key collision: fixture は AMBIGUOUS 表現に (interpretations と claimants
    //     provenance で co-exposure を分節)、main は Success + collision 未検知。gap は 2 段 —
    //     (1) collision→Ambiguous を outcome level で surface、(2) AmbiguousData に claimants provenance。
    //     現行は (1) 未実装なので verdict は outcome level に落ちる。
     "export-key/collision.json::co-exposure-collision :: EXPECTED-AMBIGUOUS got=ok{a=true,b=true}",
    // ── DR-043 取り分の選好: adjacent min:0 receptacles (xs*, ys*) の左最長選好。slice と同じく main も
    //     min:0 repeat を「>=1 で lower」してしまうため、0 token 供給パスや偏った分割で失敗する。
    //     取り分方向 (左/右最長) が上流未決着 (kuu DR-043 「未決着 — 取り分の向き」) なので、実装後
    //     方向が決まると two-tokens 側の want が反転する可能性がある (verdict 文字列も変わる)。
     "path-search/ambiguous-receptacles.json::zero-tokens-unique-split :: EXPECTED-SUCCESS got=fail:missing operand for xs",
    "path-search/ambiguous-receptacles.json::one-token-greedy-left :: EXPECTED-SUCCESS got=fail:missing operand for ys",
    "path-search/ambiguous-receptacles.json::two-tokens-greedy-left :: effects got=xs:set(a)@cli,ys:set(b)@cli want= | result got={xs=[a],ys=[b]} want={xs=[a,b],ys=[]}",
    // ── DR-075 §2 int_round 未実装: main は int 型を CLI 相で number と同じ NumArg に落とし、値空間の
    //     整数判定・int_round も CLI 相では適用しない。`"2.5"` が VNum(2.5) で通ってしまうため failure に
    //     ならない。追従は「値空間の整数判定 + int_round 実装」issue で (parse_number の DR-074/075
    //     追従と同根の追跡)。
     "value-typing/int-value-space.json::fractional-value-rejected :: EXPECTED-FAILURE got=ok{v=2.5}",
  ]
}

///|
/// The FROZEN skip ledger — decode-time twin of `known_divergences`. Each entry is `(rel, reason)`:
/// a fixture the decoder cannot losslessly represent, so it raises DecodeSkip before any case runs.
/// UNEXPECTED / VANISHED / CHANGED SKIP REASON all fail the run (like divergences, MDR-001 §6).
///
/// Initial population (2026-07-08 first run, journal 2026-07-08-conformance-first-run.md):
/// 6 slice-inherited skips — nested-group positional (1) + structural or-position/-option (3) +
/// `definitions` factory-config key (2). Reason strings are byte-identical to the corresponding
/// `raise DecodeSkip(...)` messages in dec_positional / dec_or / allowed_keys(defo, ...).
fn expected_skips() -> Array[(String, String)] {
  [
    // nested-group positional (repeat over a named sub-sequence): fixture's positional carries an
    // inner `positionals` array (a named sub-sequence repeated as a unit). Main's ElemDef is flat —
    // parse_definition builds no IdxRepeat with a distinct inner-element name/export_key — so
    // dec_positional cannot represent it losslessly and skips up front (dec_positional, "positionals"
    // key guard). Main src vocabulary gap (inherited from slice).
    (
      "export-key/transparent-seq.json", "nested-group positional (repeat over a named sub-sequence): slice ElemDef is flat, parse_definition builds no IdxRepeat with a distinct inner-element name/export_key",
    ),
    // structural-or spine / -option: three fixtures encode an `or` of CONSUMPTION GRAMMARS — an
    // element whose value is Or([Seq([typed cells]),…]) binding DIFFERENT named cells per branch
    // (real-ambiguous / held-error-primary). Main's ElemDef is flat (one value cell per element);
    // parse_definition's §5 contract path has no builder for the multi-cell Or([Seq(…),…]) shape.
    // The engine's Node ADT supports it — the gap is the absence of a flat-ElemDef → structural-or
    // lowering. Inherited from slice.
    (
      "path-search/variable-arity-ambiguous.json", "variable-arity or-option (branches are consumption grammars — a seq of typed cells vs a single typed cell): slice ElemDef carries one value cell per option and dec_or models only value-enum exact-branches, so parse_definition has no builder for Or([Seq([NumArg,…]),StrArg]) at the §5 contract path",
    ),
    (
      "path-search/held-errors-distinct-depth.json", "structural or-positional (branches are consumption grammars binding distinct named cells): slice ElemDef is flat with one value cell per element — lower_positional builds a single value_prim per positional, so parse_definition has no builder for Or([Seq([…]),…]) at the §5 contract path",
    ),
    (
      "path-search/held-errors-same-depth.json", "structural or-positional (branches are consumption grammars binding distinct named cells): slice ElemDef is flat with one value cell per element — lower_positional builds a single value_prim per positional, so parse_definition has no builder for Or([Seq([…]),…]) at the §5 contract path",
    ),
    // DR-074 §2・§4 / DR-061 §3 `definitions` factory shadow: number_allow_base_prefix / int_round の
    // opt-in を definition top-level の `definitions` キーで factory config を差し替えて表現する断面。
    // main の parse_definition は top-level definition に options/positionals/commands しか許さず、
    // DR-061 の `definitions` (factory config 差し替え) キーを表現できないため decode 前に skip する。
    // reason は allowed_keys(defo, …, "definition") の DecodeSkip メッセージと byte 一致必須。
    (
      "value-typing/number-base-prefix-optin.json", "definition has unsupported key 'definitions'",
    ),
    (
      "value-typing/int-round-modes.json", "definition has unsupported key 'definitions'",
    ),
  ]
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
