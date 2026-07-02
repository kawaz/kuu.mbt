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

/// `key=value` pairs, sorted — the visible result of a parse.
fn render_binds(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    items.push("\{b.key}=\{render_val(b.value)}")
  }
  sort_items(items)
  join_comma(items)
}

/// `key=value@source` pairs, sorted — used where provenance is the point (env test).
fn render_binds_src(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    items.push("\{b.key}=\{render_val(b.value)}@\{render_src(b.source)}")
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

// ── Phase 2 helpers: definition builders + canonicalizer + permutations ───────

fn opt(
  name : String,
  ty : Ty,
  long~ : Array[String] = [],
  short~ : Array[Char] = [],
  env~ : Array[String] = [],
  global~ : Bool = false,
  inherit~ : Bool = false,
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
    default_value: default,
  }
}

fn pos(name : String, ty : Ty, inherit~ : Bool = false, default~ : Value? = None) -> ElemDef {
  {
    name,
    ty,
    long: [],
    short: [],
    env: [],
    is_dd: false,
    is_global: false,
    is_inherit: inherit,
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
    default_value: None,
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
