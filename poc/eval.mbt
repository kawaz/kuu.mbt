// eval.mbt — bounded path-search evaluator (DR-038 / DR-041 / DR-043).
//
// The core contract (DR-038): a parse succeeds iff exactly ONE complete path
// consumes all tokens. 0 => fail (show held Error), 1 => commit, 2+ => ambiguous.
// There is NO longest-match rule; "long wins" only emerges because short paths
// leave unconsumed tokens and drop out (DR-038 §「最長一致」).
//
// `defs` is the template registry (DR-020 / DR-043): it resolves `Ref` nodes so a
// repeat can be a recursive `Seq([head, Opt(Ref(self))])` rather than a closure
// primitive. It threads through every walk function unchanged.

/// The outcome of trying a node against a token prefix.
/// A missing branch == Reject (silently dropped, DR-037). `Held` == Error
/// (retained for failure display). `Accept(new_pos, bindings)` == a reading.
enum Branch {
  Accept(Int, Array[Binding]) // (new position, accumulated bindings)
  Held(String, Int) // (error message, depth reached) — DR-037 Error
} derive(Show)

/// Final parse outcome, counting DISTINCT complete paths (DR-038 table).
pub(all) enum Outcome {
  Success(Array[Binding])
  Fail(String)
  Ambiguous(Int) // number of distinct complete paths (>= 2)
} derive(Eq, Show)

fn mkb(key : String, value : Value, source : Source) -> Binding {
  { key, value, source, scope: [] }
}

/// Nest a set of bindings one level deeper under `label` (DR-025: a name / command
/// scope prepends its label to every binding produced inside it, outermost first).
fn nest(label : String, binds : Array[Binding]) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in binds {
    let sc2 : Array[String] = [label]
    for s in b.scope {
      sc2.push(s)
    }
    out.push({ key: b.key, value: b.value, source: b.source, scope: sc2 })
  }
  out
}

/// Apply `nest` to every Accept branch's bindings (Held passes through).
fn nest_branches(label : String, brs : Array[Branch]) -> Array[Branch] {
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Accept(p, bs) => out.push(Accept(p, nest(label, bs)))
      Held(m, d) => out.push(Held(m, d))
    }
  }
  out
}

fn cat(a : Array[Binding], b : Array[Binding]) -> Array[Binding] {
  let r : Array[Binding] = []
  for x in a {
    r.push(x)
  }
  for x in b {
    r.push(x)
  }
  r
}

/// Evaluate a node at `pos`, returning every reading (Accept) and held Error.
fn eval(
  node : Node,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Array[Branch] {
  match node {
    Exact(s) =>
      if pos < toks.length() && toks[pos] == s {
        [Accept(pos + 1, [])]
      } else {
        []
      }
    StrArg(name) =>
      if pos < toks.length() {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() {
        match parse_number(toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held("\"\{toks[pos]}\" is not a number", pos)]
        }
      } else {
        []
      }
    Bind(name, v) => [Accept(pos, [mkb(name, v, Cli)])]
    Or(alts) => {
      let out : Array[Branch] = []
      for a in alts {
        for b in eval(a, toks, pos, defs) {
          out.push(b)
        }
      }
      out
    }
    Seq(items) => eval_seq(items, 0, toks, pos, [], defs)
    Many(inner) => eval_many(inner, toks, pos, [], defs)
    Scoped(label, body) =>
      // A name creates a result scope (DR-025): bindings produced inside nest under
      // `label`. Path counting is unaffected (nesting only tags the bindings).
      nest_branches(label, eval(body, toks, pos, defs))
    ScopeNode(sc) => eval_scope(sc, toks, pos, defs)
    NativeMatch(m) => run_matcher(m, toks, pos)
    Ref(name) =>
      // Plain resolution: recurse into the registered template. On the positional
      // spine `Ref` is instead unfolded porously (scope_consume). Here (inside an Or
      // head, a matcher-free context, etc.) it is the ordinary recursion, bounded by
      // the zero-progress guard baked into the template's head.
      match defs.get(name) {
        Some(tpl) => eval(tpl, toks, pos, defs)
        None => []
      }
    DdSat(trigger) =>
      // A dd satellite reads its trigger like any greedy exact matcher. This is
      // what makes greedy_reads/先食い suppress a raw-eat of `--`. The SEVER on
      // firing is applied by the spine walk (scope_step step A), not here.
      if pos < toks.length() && toks[pos] == trigger {
        [Accept(pos + 1, [])]
      } else {
        []
      }
    CmdSat(name, child) =>
      // A command satellite reads its name exactly, then the child scope (a fresh
      // backbone) consumes from pos+1. greedy_reads/先食い sees these accepts and
      // protects the command name from a positional raw-eat. The SEVER of the parent
      // on firing is applied by the spine walk (scope_step step A), not here.
      if pos < toks.length() && toks[pos] == name {
        // the subcommand is a result scope: its bindings nest under the command name.
        nest_branches(name, eval_scope(child, toks, pos + 1, defs))
      } else {
        []
      }
  }
}

/// Thread `pos` through a Seq; bindings accumulate; a Held dead-ends its branch.
fn eval_seq(
  items : Array[Node],
  idx : Int,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
  defs : Map[String, Node],
) -> Array[Branch] {
  if idx >= items.length() {
    return [Accept(pos, acc)]
  }
  let out : Array[Branch] = []
  for b in eval(items[idx], toks, pos, defs) {
    match b {
      Accept(p2, bs) =>
        for r in eval_seq(items, idx + 1, toks, p2, cat(acc, bs), defs) {
          out.push(r)
        }
      Held(m, d) => out.push(Held(m, d))
    }
  }
  out
}

/// Unbounded repeat (>= 0). The `p2 > pos` guard prevents zero-progress loops.
fn eval_many(
  inner : Node,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
  defs : Map[String, Node],
) -> Array[Branch] {
  let out : Array[Branch] = [Accept(pos, acc)] // 0 reps
  for b in eval(inner, toks, pos, defs) {
    match b {
      Accept(p2, bs) =>
        if p2 > pos {
          for r in eval_many(inner, toks, p2, cat(acc, bs), defs) {
            out.push(r)
          }
        }
      Held(m, d) => out.push(Held(m, d))
    }
  }
  out
}

// ── two-face scope (DR-041 §4) ──────────────────────────────────────────────
//
// `severed` is the dd mode (DR-042 ⑤): once `--` is consumed, the greedy face is
// off for the rest of the walk and everything falls raw into positionals.

/// A greedy entry "reads" at `pos` iff it consumes >= 1 token there. This is the
/// exact 先食い predicate (DR-041 §4): when true, positional raw pass-through of
/// the current token is suppressed. (Only consulted when not severed.)
fn greedy_reads(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Bool {
  for g in sc.greedy {
    for b in eval(g, toks, pos, defs) {
      match b {
        Accept(p2, _) => if p2 > pos { return true }
        Held(_, _) => ()
      }
    }
  }
  false
}

/// Whether raw pass-through of the token at `pos` is suppressed. 先食い is
/// greedy-ONLY (DR-041 §4, rev): a raw-eat is suppressed iff some greedy entry
/// reads the token. The dd `--` is covered because the dd satellite is itself a
/// greedy entry (DdSat) — no dd special case. Once severed, nothing is suppressed.
fn suppressed(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  severed : Bool,
  defs : Map[String, Node],
) -> Bool {
  if severed {
    return false // past `--`: everything falls raw, even a second `--`
  }
  greedy_reads(sc, toks, pos, defs)
}

fn eval_scope(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Array[Branch] {
  scope_step(sc, toks, pos, 0, [], false, defs)
}

/// Walk sc.positional[pidx..] from `pos`. Offers (A) a greedy interjection (only
/// when not severed) and (B) advancing the positional face.
fn scope_step(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  let out : Array[Branch] = []
  // (A) greedy interjection — a fired greedy entry raw-consumes its own value
  // slots (getopt 同型); re-enter at the same pidx (positional face untouched).
  // Firing a dd or command satellite additionally severs the rest of the walk
  // (DR-041 §4: the fired greedy's continuation is its internal consumption).
  if !(severed) {
    for g in sc.greedy {
      // Only dd severs (its continuation is internal consumption, 一体). A command
      // (CmdSat) does NOT sever — after its subtree completes the parent backbone
      // RESUMES (DR-041 §4, rev). The command's uniqueness comes from 早閉じ抑制 below,
      // not from severing the parent.
      let fires_severed = match g {
        DdSat(_) => true
        _ => false
      }
      for b in eval(g, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              for r in scope_step(
                  sc, toks, p2, pidx, cat(acc, bs), severed || fires_severed, defs,
                ) {
                out.push(r)
              }
            }
          Held(m, d) => out.push(Held(m, d))
        }
      }
    }
  }
  // (B) advance the positional face
  if pidx >= sc.positional.length() {
    // 早閉じ抑制 (DR-041 §4, rev): a scope with a backbone cannot complete while one of
    // its own greedy entries can read the next token — "that which can be read here, is
    // read here". This makes "the innermost scope that can read wins" emerge without any
    // cross-path priority: a child cannot exit early leaving a token its greedy could
    // take, so the parent never gets a competing route. Severed scopes (past `--`) have
    // greedy off and always may close.
    if severed || !greedy_reads(sc, toks, pos, defs) {
      out.push(Accept(pos, acc)) // positional exhausted => acceptable scope end
    }
  } else {
    for r in scope_consume(
        sc, sc.positional[pidx], toks, pos, pidx, acc, severed, defs,
      ) {
      out.push(r)
    }
  }
  out
}

/// Consume one positional item, then continue at pidx+1 (Many/Ref stay at pidx).
fn scope_consume(
  sc : Scope,
  item : Node,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  match item {
    StrArg(name) =>
      if pos < toks.length() && !(suppressed(sc, toks, pos, severed, defs)) {
        scope_step(
          sc, toks, pos + 1, pidx + 1, cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed, defs,
        )
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !(suppressed(sc, toks, pos, severed, defs)) {
        match parse_number(toks[pos]) {
          // DR-041 §5: number positional rejecting a token is a held Error, not a
          // structural refusal — no prefix guard.
          Some(d) =>
            scope_step(
              sc, toks, pos + 1, pidx + 1, cat(acc, [mkb(name, VNum(d), Cli)]),
              severed, defs,
            )
          None => [Held("\"\{toks[pos]}\" is not a number", pos)]
        }
      } else {
        []
      }
    Exact(s) =>
      if pos < toks.length() && toks[pos] == s {
        scope_step(sc, toks, pos + 1, pidx + 1, acc, severed, defs)
      } else {
        []
      }
    Ref(name) =>
      // A repeat item (DR-043): >= 1 head, unfolded POROUSLY on the spine. Consume the
      // mandatory head, then offer either "stop" (advance to pidx+1) or "one more rep"
      // (re-enter scope_step at the SAME pidx). The "more" route goes through
      // scope_step, so greedy interjects between reps for free (背骨に留まる, 反復間
      // 割り込みが保たれる). ≥1 semantics: each visit consumes one mandatory head.
      {
        let head = ref_head(defs, name)
        let out : Array[Branch] = []
        for b in consume_head(sc, head, toks, pos, severed, defs) {
          match b {
            Accept(p2, bs) =>
              if p2 > pos {
                // stop: advance past the repeat
                for r in scope_step(sc, toks, p2, pidx + 1, cat(acc, bs), severed, defs) {
                  out.push(r)
                }
                // more reps: re-enter at the same pidx (porous — scope_step offers
                // a greedy interjection before the next mandatory head)
                for r in scope_step(sc, toks, p2, pidx, cat(acc, bs), severed, defs) {
                  out.push(r)
                }
              }
            Held(m, d) => out.push(Held(m, d))
          }
        }
        out
      }
    Many(inner) => {
      let out : Array[Branch] = []
      for r in scope_step(sc, toks, pos, pidx + 1, acc, severed, defs) { // 0 reps
        out.push(r)
      }
      for r in scope_consume_rep(sc, inner, toks, pos, pidx, acc, severed, defs) { // 1 rep
        out.push(r)
      }
      out
    }
    ScopeNode(child) => {
      // DR-042 ⑤: a child scope runs its own (fresh, unsevered) walk; the parent
      // greedy face does not interject during it.
      let out : Array[Branch] = []
      for b in eval_scope(child, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            for r in scope_step(sc, toks, p2, pidx + 1, cat(acc, bs), severed, defs) {
              out.push(r)
            }
          Held(m, d) => out.push(Held(m, d))
        }
      }
      out
    }
    other => {
      // any other node as a positional item: eval plainly, then continue.
      let out : Array[Branch] = []
      for b in eval(other, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            for r in scope_step(sc, toks, p2, pidx + 1, cat(acc, bs), severed, defs) {
              out.push(r)
            }
          Held(m, d) => out.push(Held(m, d))
        }
      }
      out
    }
  }
}

/// Consume one repeat head on the spine. A value primitive respects 先食い (a greedy
/// trigger between reps is not raw-eaten as a value); a non-primitive head (a ref to
/// a template, e.g. `color`) is evaluated plainly (head-internal is not spine-porous,
/// but the rep boundary still is via scope_step).
fn consume_head(
  sc : Scope,
  head : Node,
  toks : Array[String],
  pos : Int,
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  match head {
    StrArg(name) =>
      if pos < toks.length() && !(suppressed(sc, toks, pos, severed, defs)) {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !(suppressed(sc, toks, pos, severed, defs)) {
        match parse_number(toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held("\"\{toks[pos]}\" is not a number", pos)]
        }
      } else {
        []
      }
    _ => eval(head, toks, pos, defs)
  }
}

/// The head of a repeat template `Seq([head, Opt(Ref(name))])`. The repeat installer
/// always registers templates in this shape, so the head is the Seq's first item.
fn ref_head(defs : Map[String, Node], name : String) -> Node {
  match defs.get(name) {
    Some(Seq(items)) => if items.length() >= 1 { items[0] } else { Exact("<bad-ref>") }
    _ => Exact("<bad-ref>")
  }
}

/// One repetition of a Many's inner item (subject to 先食い), continuing at the
/// SAME pidx so the Many remains available (porous reps, DR-041 §4).
fn scope_consume_rep(
  sc : Scope,
  inner : Node,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  match inner {
    StrArg(name) =>
      if pos < toks.length() && !(suppressed(sc, toks, pos, severed, defs)) {
        scope_step(
          sc, toks, pos + 1, pidx, cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed, defs,
        )
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !(suppressed(sc, toks, pos, severed, defs)) {
        match parse_number(toks[pos]) {
          Some(d) =>
            scope_step(
              sc, toks, pos + 1, pidx, cat(acc, [mkb(name, VNum(d), Cli)]), severed,
              defs,
            )
          None => [Held("\"\{toks[pos]}\" is not a number", pos)]
        }
      } else {
        []
      }
    _ => {
      let out : Array[Branch] = []
      for b in eval(inner, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              for r in scope_step(sc, toks, p2, pidx, cat(acc, bs), severed, defs) {
                out.push(r)
              }
            }
          Held(m, d) => out.push(Held(m, d))
        }
      }
      out
    }
  }
}

// ── top level (DR-038 path counting) ────────────────────────────────────────

/// Parse `toks` against `root`, counting DISTINCT complete paths.
///
/// Distinctness is exact binding-sequence equality: two paths that reach the
/// same result via different interleavings are ONE interpretation (DR-038 "1本"
/// = one interpretation), so they are deduped. Genuinely different readings
/// produce different bindings and are preserved as separate paths.
///
/// `defs` supplies the template registry for `Ref` resolution (empty by default;
/// only repeat/ref definitions need it).
pub fn parse(
  root : Node,
  toks : Array[String],
  defs~ : Map[String, Node] = Map::new(),
) -> Outcome {
  let branches = eval(root, toks, 0, defs)
  let full : Array[Array[Binding]] = []
  let mut deepest_msg = ""
  let mut deepest_depth = -1
  for b in branches {
    match b {
      Accept(p, bs) =>
        if p == toks.length() {
          let mut dup = false
          for existing in full {
            if existing == bs {
              dup = true
              break
            }
          }
          if !dup {
            full.push(bs)
          }
        }
      Held(m, d) =>
        if d > deepest_depth {
          deepest_depth = d
          deepest_msg = m
        }
    }
  }
  match full.length() {
    0 => if deepest_depth >= 0 { Fail(deepest_msg) } else { Fail("no complete parse") }
    1 => Success(full[0])
    n => Ambiguous(n)
  }
}
