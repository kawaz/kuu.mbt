// helpers_wbtest.mbt — test-only builders and compact renderers.
//
// These constructors spell out the AtomicAST shapes by hand for Phase 1. In
// Phase 2 the installer chain produces the same shapes, so the two phases can be
// read against each other. Renderers give tests a compact, sorted "spec string"
// so each assertion reads as a fact, not a Show dump.

/// greedy flag entry: `Seq([Exact(trigger), Bind(name, true)])` — fires and sets a bool.
fn flag(trigger : String, name : String) -> Node {
  Seq([Exact(trigger), Bind(name, VBool(true))])
}

/// greedy string-value entry: trigger then a raw value slot (getopt-同型 raw consume).
fn strv(trigger : String, name : String) -> Node {
  Seq([Exact(trigger), StrArg(name)])
}

fn scope(greedy : Array[Node], positional : Array[Node]) -> Node {
  ScopeNode({ greedy, positional, entities: [] })
}

// Deterministic string ordering. MoonBit's builtin String sort orders by length
// first, which is wrong for stable canonicalization; this is plain codepoint order.

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

fn render_src(s : Source) -> String {
  match s {
    Cli => "cli"
    Env => "env"
    Inherit => "inherit"
    Default => "default"
  }
}

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

fn is_marker(k : String) -> Bool {
  k == "[]" || k == "{}"
}

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

/// Compact one-line rendering of an Outcome for spec-string assertions.
fn render_outcome(o : Outcome) -> String {
  match o {
    Success(binds) => "ok{" + render_binds(binds) + "}"
    Fail(msg) => "fail:" + msg
    Ambiguous(n) => "ambiguous:" + n.to_string()
  }
}

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

/// Parse, then build the nested result object (layer 3). On a non-unique parse the
/// outcome string is returned so tests can assert either shape.
fn result_str(
  sc : Scope,
  toks : Array[String],
  defs~ : Map[String, Node] = Map::new(),
) -> String {
  match parse(ScopeNode(sc), toks, defs~) {
    Success(binds) => render_rval(build_result(binds, accum_names(sc)))
    Fail(msg) => "fail:" + msg
    Ambiguous(n) => "ambiguous:" + n.to_string()
  }
}

// ── Phase 2 helpers: definition builders + canonicalizer + permutations ───────

fn opt(
  name : String,
  ty : Ty,
  long~ : Array[String] = [],
  short~ : Array[Char] = [],
  env~ : Array[String] = [],
  global~ : Bool = false,
  inherit~ : Bool = false,
  multiple~ : Bool = false,
  default~ : Value? = None,
) -> ElemDef {
  {
    name,
    ty,
    long,
    short,
    env,
    is_dd: false,
    is_global: global,
    is_inherit: inherit,
    is_link: false,
    ref_target: None,
    repeat: None,
    multiple,
    default_value: default,
  }
}

fn pos(
  name : String,
  ty : Ty,
  inherit~ : Bool = false,
  repeat~ : RepeatSpec? = None,
  multiple~ : Bool = false,
  ref_~ : String? = None,
  default~ : Value? = None,
) -> ElemDef {
  {
    name,
    ty,
    long: [],
    short: [],
    env: [],
    is_dd: false,
    is_global: false,
    is_inherit: inherit,
    is_link: false,
    ref_target: ref_,
    repeat,
    multiple,
    default_value: default,
  }
}

fn dd_marker() -> ElemDef {
  {
    name: "--",
    ty: TStr,
    long: [],
    short: [],
    env: [],
    is_dd: true,
    is_global: false,
    is_inherit: false,
    is_link: false,
    ref_target: None,
    repeat: None,
    multiple: false,
    default_value: None,
  }
}

fn rep(min : Int, lazy~ : Bool = false) -> RepeatSpec? {
  Some({ min, lazy })
}

/// Build a scope + return the ref-template registry (for repeat/ref tests). Any
/// pre-registered templates (e.g. a shared `color`) can be put in `registry` first.
fn build_reg(
  def : Definition,
  order : Array[Installer],
  registry : Map[String, Node],
) -> Scope {
  match parse_definition(def, order, registry~) {
    Ok(sc) => sc
    Err(msg) => abort("build failed: " + msg)
  }
}

/// Definition constructors — keep `commands` out of test literals so adding tree
/// support did not churn every def site.
fn def_(options : Array[ElemDef], positionals : Array[ElemDef]) -> Definition {
  { options, positionals, commands: [] }
}

fn def_cmd(
  options : Array[ElemDef],
  positionals : Array[ElemDef],
  commands : Array[CommandDef],
) -> Definition {
  { options, positionals, commands }
}

fn cmd(name : String, body : Definition) -> CommandDef {
  { name, body }
}

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
  "G[" + join_comma(gs) + "]|P[" + join_comma(ps) + "]|E[" + join_comma(es) + "]"
}

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
