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

/// greedy number-value entry.
fn numv(trigger : String, name : String) -> Node {
  Seq([Exact(trigger), NumArg(name)])
}

fn scope(greedy : Array[Node], positional : Array[Node]) -> Node {
  ScopeNode({ greedy, positional, entities: [] })
}

fn scope_e(
  greedy : Array[Node],
  positional : Array[Node],
  entities : Array[Entity],
) -> Node {
  ScopeNode({ greedy, positional, entities })
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
