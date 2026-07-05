// helpers_wbtest.mbt — test-only builders and compact renderers.
//
// These constructors spell out the AtomicAST shapes by hand for Phase 1. In
// Phase 2 the installer chain produces the same shapes, so the two phases can be
// read against each other. Renderers give tests a compact, sorted "spec string"
// so each assertion reads as a fact, not a Show dump.

///|
/// greedy flag entry: `Seq([Exact(trigger), Bind(name, true)])` — fires and sets a bool.
fn flag(trigger : String, name : String) -> Node {
  Seq([Exact(trigger), Bind(name, VBool(true))])
}

///|
/// greedy string-value entry: trigger then a raw value slot (getopt-同型 raw consume).
fn strv(trigger : String, name : String) -> Node {
  Seq([Exact(trigger), StrArg(name)])
}

///|
fn scope(greedy : Array[Node], positional : Array[Node]) -> Node {
  ScopeNode({ greedy, positional, entities: [], constraints: [] })
}

// Deterministic string ordering. MoonBit's builtin String sort orders by length
// first, which is wrong for stable canonicalization; this is plain codepoint order.

///|
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
fn is_marker(k : String) -> Bool {
  k == "[]" || k == "{}" || is_action_key(k) || is_depr_key(k)
}

///|
/// `key=value` pairs, sorted — the visible result of a parse. Result-structure markers
/// ("[]" / "{}") are skipped (they carry no value, only nesting shape).
fn render_binds(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if !is_marker(b.key) {
      items.push("\{b.key}=\{render_val(b.value)}")
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
/// `key=value` pairs in CONSUMPTION order (NOT sorted) — the effect column (DR-045). Used to
/// show that link 合流 preserves the argv order of effects onto one cell (last-wins is the tail).
fn render_binds_ordered(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if !is_marker(b.key) {
      items.push("\{b.key}=\{render_val(b.value)}")
    }
  }
  join_comma(items)
}

///|
/// `key=value@source` pairs, sorted — used where provenance is the point (env test).
fn render_binds_src(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if !is_marker(b.key) {
      items.push("\{b.key}=\{render_val(b.value)}@\{render_src(b.source)}")
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
/// op-aware rendering of the effect sequence (DR-045 tests): `key=set(value)` / `key=unset`
/// / `key=default` / `key=empty`, sorted. Makes the effect op visible where a plain value
/// render would only show the placeholder.
fn render_effects(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if !is_marker(b.key) {
      let tag = match b.op {
        Set => "\{b.key}=set(\{render_val(b.value)})"
        Default => "\{b.key}=default"
        Unset => "\{b.key}=unset"
        Empty => "\{b.key}=empty"
      }
      items.push(tag)
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
/// Parse and render the op-aware effect sequence of the unique winning path (DR-045).
fn effects_str(g : Node, toks : Array[String]) -> String {
  match parse(g, toks) {
    Success(binds) => render_effects(binds)
    Failure(d) => fail_str(d)
    Ambiguous(d) => ambig_str(d)
  }
}

///|
/// Parse and render the winning path's effect column in consumption order (DR-045). For link
/// 合流 tests: shows the ordered effects that merge onto one cell (last-wins is the tail, DR-015).
fn ordered_effects(g : Node, toks : Array[String]) -> String {
  match parse(g, toks) {
    Success(binds) => render_binds_ordered(binds)
    Failure(d) => fail_str(d)
    Ambiguous(d) => ambig_str(d)
  }
}

///|
/// Parse the CLI tokens, then resolve every cell down the value-source ladder with `env`
/// present (DR-031 / DR-045): shows how the parsed effects interact with env/default seats.
fn resolve_after_parse(
  sc : Scope,
  toks : Array[String],
  env : Map[String, String],
) -> String {
  match parse(ScopeNode(sc), toks) {
    Success(b) => render_binds_src(resolve_scope(sc, b, env))
    Failure(d) => fail_str(d)
    Ambiguous(d) => ambig_str(d)
  }
}

///|
/// The primary (deepest-argv) error's message (DR-053 §2 primary = max argv_pos).
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
/// Backward-compatible one-line rendering of a Failure (DR-053): a fired action → "action:<name>";
/// else the primary error message → "fail:<msg>"; else "fail:no complete parse". Keeps the pre-DR-053
/// spec-strings stable so existing tests read unchanged (the structure is richer underneath).
fn fail_str(d : FailureData) -> String {
  match d.fired_action {
    Some(n) => "action:" + n
    None =>
      if d.errors.length() > 0 {
        "fail:" + primary_message(d.errors)
      } else {
        "fail:no complete parse"
      }
  }
}

///|
fn ambig_str(d : AmbiguousData) -> String {
  "ambiguous:" + d.interpretations.length().to_string()
}

// ── DR-054 definition-error accessors ─────────────────────────────────────────

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
/// All definition errors as `element/kind`, sorted (DR-054 全列挙).
fn deferrs_str(errs : Array[DefError]) -> String {
  let items : Array[String] = []
  for e in errs {
    items.push("\{e.element}/\{render_def_kind(e.kind)}")
  }
  sort_items(items)
  join_comma(items)
}

///|
/// The hint of the first error whose element matches `element` (DR-054 §4 「次の手」).
fn hint_of(errs : Array[DefError], element : String) -> String {
  for e in errs {
    if e.element == element {
      return e.hint
    }
  }
  "none"
}

// ── DR-053 structure accessors (the rich failure / ambiguous data) ────────────

///|
fn render_kind(k : ErrKind) -> String {
  match k {
    KParse => "parse"
    KFilter => "filter"
    KConstraint => "constraint"
  }
}

///|
/// One error as `element@argv_pos/kind` (message dropped for a compact spec-string).
fn render_err(pe : ParseError) -> String {
  "\{pe.element}@\{pe.argv_pos}/\{render_kind(pe.kind)}"
}

// ── completion candidate renderers (DR-060) ──────────────────────────────────

///|
fn ty_str(t : Ty) -> String {
  match t {
    TStr => "str"
    TNum => "num"
    TInt => "int"
    TFlag => "flag"
  }
}

///|
/// A completion candidate set as sorted `spelling` (exact) / `<ty>` (value) tokens, comma-joined.
fn cands_str(cands : Array[Cand]) -> String {
  let items : Array[String] = []
  for c in cands {
    if c.is_value {
      items.push("<" + ty_str(c.ty) + ">")
    } else {
      items.push(c.spelling)
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
/// The terminal hint of a named exact candidate (DR-060 §9): "end" (word_end) / "cont" (continue) /
/// "none" if the spelling is not among the candidates.
fn cand_term(cands : Array[Cand], spelling : String) -> String {
  for c in cands {
    if not(c.is_value) && c.spelling == spelling {
      return match c.term {
        WordEnd => "end"
        Cont => "cont"
      }
    }
  }
  "none"
}

///|
/// The declaration-layer meta of a named exact candidate, as sorted flags (DR-057/058): any of
/// alias / hidden / dep, or "-" if none. "absent" if the spelling is not among the candidates.
fn cand_meta(cands : Array[Cand], spelling : String) -> String {
  for c in cands {
    if not(c.is_value) && c.spelling == spelling {
      let fs : Array[String] = []
      if c.meta.is_alias {
        fs.push("alias")
      }
      if c.meta.hidden {
        fs.push("hidden")
      }
      if c.meta.deprecated {
        fs.push("dep")
      }
      if fs.length() == 0 {
        return "-"
      }
      sort_items(fs)
      return join_comma(fs)
    }
  }
  "absent"
}

///|
/// The deprecation warnings on a Success outcome, sorted (DR-058 warnings). Each is the canonical
/// element name reached via a deprecated entry (DR-057 alias). Empty = no deprecated entry used.
fn warnings_str(o : Outcome) -> String {
  let ws = warnings_of(o)
  sort_items(ws)
  join_comma(ws)
}

///|
/// ALL held errors of a Failure, sorted (DR-053 §2 全保持).
fn errors_str(o : Outcome) -> String {
  match o {
    Failure(d) => {
      let items : Array[String] = []
      for e in d.errors {
        items.push(render_err(e))
      }
      sort_items(items)
      join_comma(items)
    }
    _ => "not-failure"
  }
}

///|
/// The PRIMARY errors (max argv_pos, all if tie), sorted (DR-053 §2 primary = 最深).
fn primary_str(o : Outcome) -> String {
  match o {
    Failure(d) => {
      if d.errors.length() == 0 {
        return ""
      }
      let mut maxp = -1
      for e in d.errors {
        if e.argv_pos > maxp {
          maxp = e.argv_pos
        }
      }
      let items : Array[String] = []
      for e in d.errors {
        if e.argv_pos == maxp {
          items.push(render_err(e))
        }
      }
      sort_items(items)
      join_comma(items)
    }
    _ => "not-failure"
  }
}

///|
/// Every interpretation of an Ambiguous outcome as a result-object view, sorted (DR-053 §3).
fn interps_str(o : Outcome) -> String {
  match o {
    Ambiguous(d) => {
      let items : Array[String] = []
      for interp in d.interpretations {
        items.push(render_rval(build_result(interp, [], [], [])))
      }
      sort_items(items)
      "[" + join_comma(items) + "]"
    }
    _ => "not-ambiguous"
  }
}

///|
/// The help_entry material (DR-053 §4), or "none".
fn help_of(o : Outcome) -> String {
  match o {
    Failure(d) =>
      match d.help_entry {
        Some(s) => s
        None => "none"
      }
    Ambiguous(d) =>
      match d.help_entry {
        Some(s) => s
        None => "none"
      }
    _ => "none"
  }
}

///|
/// The tried_triggers material (DR-053 §4), sorted.
fn tried_of(o : Outcome) -> String {
  match o {
    Failure(d) => {
      let items : Array[String] = []
      for t in d.tried_triggers {
        items.push(t)
      }
      sort_items(items)
      join_comma(items)
    }
    _ => ""
  }
}

///|
/// The fired_action (DR-053 §2), or "none".
fn fired_of(o : Outcome) -> String {
  match o {
    Failure(d) =>
      match d.fired_action {
        Some(s) => s
        None => "none"
      }
    _ => "none"
  }
}

///|
/// Compact one-line rendering of an Outcome for spec-string assertions (backward-compatible with
/// the pre-DR-053 "ok{}"/"fail:"/"ambiguous:N"/"action:" forms).
fn render_outcome(o : Outcome) -> String {
  match o {
    Success(binds) => "ok{" + render_binds(binds) + "}"
    Failure(d) => fail_str(d)
    Ambiguous(d) => ambig_str(d)
  }
}

///|
/// Compact rendering of a built result object (name order preserved, not sorted —
/// nesting and list order are the point of the result builder).
fn render_rval(r : RVal) -> String {
  match r {
    RScalar(v) => render_val(v)
    RArr(vs) => {
      let items : Array[String] = []
      for v in vs {
        items.push(render_rval(v))
      }
      "[" + join_comma(items) + "]"
    }
    RObj(kvs) => {
      let items : Array[String] = []
      for kv in kvs {
        items.push(kv.0 + ":" + render_rval(kv.1))
      }
      "{" + join_comma(items) + "}"
    }
  }
}

///|
/// Parse, then build the nested result object (layer 3). On a non-unique parse the
/// outcome string is returned so tests can assert either shape.
fn result_str(
  sc : Scope,
  toks : Array[String],
  defs? : Map[String, Node] = Map::new(),
) -> String {
  match parse(ScopeNode(sc), toks, defs~) {
    Success(binds) =>
      render_rval(build_result(binds, accum_cells(sc), default_cells(sc), []))
    Failure(d) => fail_str(d)
    Ambiguous(d) => ambig_str(d)
  }
}

///|
/// Parse, apply the result-key axis (DR-052), and render — with the exposure-key collision check
/// (DESIGN §15.5). `ek_map` = build_export_map(def). On collision → "collision:<key>".
fn export_result_str(
  sc : Scope,
  ek_map : Map[String, ExportKey],
  toks : Array[String],
  defs? : Map[String, Node] = Map::new(),
) -> String {
  match parse(ScopeNode(sc), toks, defs~) {
    Success(binds) =>
      match find_export_collision(binds, ek_map) {
        Some(k) => "collision:" + k
        None =>
          render_rval(
            build_result(
              apply_export_keys(binds, ek_map),
              accum_cells(sc),
              apply_export_to_defaults(default_cells(sc), ek_map),
              [],
            ),
          )
      }
    Failure(d) => fail_str(d)
    Ambiguous(d) => ambig_str(d)
  }
}

///|
/// Parse and return the built RVal (aborts on a non-unique parse) — for map-form tests.
fn result_rval(
  sc : Scope,
  toks : Array[String],
  defs? : Map[String, Node] = Map::new(),
) -> RVal {
  match parse(ScopeNode(sc), toks, defs~) {
    Success(binds) =>
      build_result(binds, accum_cells(sc), default_cells(sc), [])
    Failure(d) => abort("parse failed: " + fail_str(d))
    Ambiguous(d) => abort("ambiguous: " + ambig_str(d))
  }
}

// ── Phase 2 helpers: definition builders + canonicalizer + permutations ───────

///|
fn opt(
  name : String,
  ty : Ty,
  long? : Array[String] = [], // DR-071 two-form main-entry spellings: `[":set"]` = main entry via kebab(name), explicit spellings as-is, `[]` = no main entry (omitted default)
  variants? : Array[Variant] = [],
  short? : Array[Char] = [],
  env? : Array[String] = [],
  global? : Bool = false,
  inherit? : Bool = false,
  inheritable? : Bool = false,
  multiple? : Bool = false,
  fail_action? : Bool = false,
  config_file? : Bool = false,
  config_key? : Array[String]? = None,
  export? : ExportKey = EkUnset,
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
    is_inherit: inherit,
    is_inheritable: inheritable,
    is_link: false,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple,
    separator: None,
    fail_action,
    is_config_file: config_file,
    config_key,
    export_key: export,
    requires,
    conflicts_with: conflicts,
    exclusive_group: exclusive,
    value_requires,
    deprecated: false,
    default_value: default,
  }
}

///|
/// Normalize a config-supplied export_key string to `ExportKey`: "" → EkNull (DR-052 §1), else EkKey.
fn ek(s : String) -> ExportKey {
  if s == "" {
    EkNull
  } else {
    EkKey(s)
  }
}

///|
fn pos(
  name : String,
  ty : Ty,
  inherit? : Bool = false,
  repeat? : RepeatSpec? = None,
  optional? : Bool = false,
  multiple? : Bool = false,
  separator? : String? = None,
  config_key? : Array[String]? = None,
  export? : ExportKey = EkUnset,
  ref_? : String? = None,
  default? : Value? = None,
) -> ElemDef {
  {
    name,
    ty,
    long: [], // a positional never declares a long spelling (no main entry)
    variants: [],
    short: [],
    env: [],
    is_dd: false,
    is_global: false,
    is_inherit: inherit,
    is_inheritable: false,
    is_link: false,
    ref_target: ref_,
    repeat,
    optional,
    multiple,
    separator,
    fail_action: false,
    is_config_file: false,
    config_key,
    export_key: export,
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
    long: [], // a dd marker's trigger comes from its name ("--"), not a long spelling (no main entry)
    variants: [],
    short: [],
    env: [],
    is_dd: true,
    is_global: false,
    is_inherit: false,
    is_inheritable: false,
    is_link: false,
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
fn rep(min : Int, max? : Int? = None, lazy? : Bool = false) -> RepeatSpec? {
  Some({ min, max, lazy })
}

///|
/// Build a scope + return the ref-template registry (for repeat/ref tests). Any
/// pre-registered templates (e.g. a shared `color`) can be put in `registry` first.
fn build_reg(
  def : Definition,
  order : Array[Installer],
  registry : Map[String, Node],
) -> Scope {
  match parse_definition(def, order, registry~) {
    Ok(sc) => sc
    Err(errs) => abort("build failed: " + deferrs_str(errs))
  }
}

///|
/// Definition constructors — keep `commands` out of test literals so adding tree
/// support did not churn every def site.
fn def_(
  options : Array[ElemDef],
  positionals : Array[ElemDef],
  aliases? : Array[AliasDef] = [],
) -> Definition {
  { options, positionals, commands: [], aliases }
}

///|
fn def_cmd(
  options : Array[ElemDef],
  positionals : Array[ElemDef],
  commands : Array[CommandDef],
  aliases? : Array[AliasDef] = [],
) -> Definition {
  { options, positionals, commands, aliases }
}

///|
fn cmd(
  name : String,
  body : Definition,
  export? : ExportKey = EkUnset,
) -> CommandDef {
  { name, body, export_key: export }
}

///|
/// An alias declaration (DR-057). `name` None = reuse the canonical name (short-only alias); `long`
/// None = inherit name-derived variants, Some(xs) = explicit override (差分上書き, Some([]) cuts variants).
fn alias(
  target : String,
  name? : String? = None,
  short? : Array[Char] = [],
  long? : Array[String]? = None,
  deprecated? : Bool = false,
) -> AliasDef {
  { target, name, short, long_override: long, deprecated }
}

///|
/// Order-independent rendering of a built scope: greedy and entities sorted (the
/// invariants guarantee the SET is fixed; only array order varies), positional in
/// order (its structure is dd-owned and deterministic). Two scopes with the same
/// canon string are the same AtomicAST for permutation purposes.
fn canon_scope(sc : Scope) -> String {
  let gs : Array[String] = []
  for g in sc.greedy {
    gs.push("\{g}")
  }
  sort_items(gs)
  let es : Array[String] = []
  for e in sc.entities {
    es.push("\{e}")
  }
  sort_items(es)
  let ps : Array[String] = []
  for p in sc.positional {
    ps.push("\{p}")
  }
  "G[" +
  join_comma(gs) +
  "]|P[" +
  join_comma(ps) +
  "]|E[" +
  join_comma(es) +
  "]"
}

///|
/// Whether the scope's entity roster contains `name` (the ParserContext / detail side, DR-016). An
/// absent element (no result key) is still in the roster — this is the 2-layer separation (DR-051 §5).
fn entity_exists(sc : Scope, name : String) -> Bool {
  for e in sc.entities {
    if e.name == name {
      return true
    }
  }
  false
}

///|
/// The ParserContext meta of a result cell (DR-016 / DR-051 §5): `present` = it has a value in the
/// result; `committed` = the value came from a CLI selection (source=Cli). An absent element reports
/// present=false, committed=false; a default-supplied value is present but NOT committed.
fn ctx_report(binds : Array[Binding], name : String) -> String {
  let mut present = false
  let mut committed = false
  for b in binds {
    if b.key == name {
      present = true
      match b.source {
        Cli => committed = true
        _ => ()
      }
    }
  }
  "present=\{present},committed=\{committed}"
}

///|
/// The accumulators-registry name (DR-036) an entity's cell folds through: "flatten" (repeat),
/// "append" (multiple), or "scalar" for a non-accumulate cell. For the P3 naming tests.
fn entity_accum(sc : Scope, name : String) -> String {
  for e in sc.entities {
    if e.name == name {
      match e.accum {
        Some(a) => return a
        None => return "scalar"
      }
    }
  }
  "missing"
}

///|
fn permutations(items : Array[Installer]) -> Array[Array[Installer]] {
  if items.length() <= 1 {
    let only : Array[Installer] = []
    for x in items {
      only.push(x)
    }
    return [only]
  }
  let out : Array[Array[Installer]] = []
  let mut i = 0
  while i < items.length() {
    let rest : Array[Installer] = []
    let mut j = 0
    while j < items.length() {
      if j != i {
        rest.push(items[j])
      }
      j = j + 1
    }
    for p in permutations(rest) {
      let perm : Array[Installer] = [items[i]]
      for x in p {
        perm.push(x)
      }
      out.push(perm)
    }
    i = i + 1
  }
  out
}
