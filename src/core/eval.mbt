// eval.mbt — bounded path-search evaluator, CPS form (MDR-002 §1/§2).
//
// The core contract (spec DR-038): a parse succeeds iff exactly ONE complete
// path consumes all tokens. 0 => fail (show held Errors), 1 => commit,
// 2+ => ambiguous. There is NO longest-match rule; "long wins" only emerges
// because short paths leave unconsumed tokens and drop out.
//
// Two structural changes over the slice PoC (both MDR-002):
//
// 1. CPS (§1): the scope walk threads a continuation `k : Cont`. A scope that
//    finishes its positional face RUNS the continuation instead of returning
//    a scope-end Accept, so a repeat's 取り分選好 oracle (has_full_k) sees
//    "does the WHOLE rest of the parse — parent included — reach an Accept",
//    not "does this branch touch the global end". This is what fixes the
//    phase16 breakage (greedy repeat starving a parent's trailing positional).
//
// 2. Pending (§2): `Branch` is 3-valued. A greedy entry whose trigger was
//    consumed but whose value slot hits the end of input is a Pending — an
//    explicit value instead of the silent [] collapse — so (a) parse surfaces
//    it as a real error, (b) greedy_reads counts it as "reads" (先食い holds,
//    the trigger token cannot be raw-eaten by a positional), (c) complete
//    collects it as a candidate (outcome.mbt).
//
// `defs` is the template registry (spec DR-020/DR-043): it resolves `Ref`
// nodes so a repeat can be a recursive `Seq([head, Opt(Ref(self))])`.

///|
/// A non-set effect binding (default / unset / empty). The operand is a
/// placeholder — these ops carry no operand (spec DR-045 table).
fn mk_eff(key : String, op : EffectOp, source : Source) -> Binding {
  { key, op, value: VBool(false), source, scope: [], link: 0 }
}

///|
/// A failure-action marker binding (spec DR-048): key `@act:<name>`, value =
/// the argv position where the action was selected (argv-min tie-break).
fn action_marker(name : String, pos : Int) -> Binding {
  {
    key: "@act:" + name,
    op: Set,
    value: VNum(pos.to_double()),
    source: Cli,
    scope: [],
    link: 0,
  }
}

///|
/// Whether a result key is a deprecation marker (`@depr:...`).
pub fn is_depr_key(k : String) -> Bool {
  let p = "@depr:"
  k.length() >= p.length() && k[0:p.length()].to_owned() == p
}

///|
/// The deprecated canonical element names recorded on a Success outcome
/// (spec DR-058 warnings), deduped in first-seen order.
pub fn warnings_of(o : Outcome) -> Array[String] {
  let out : Array[String] = []
  match o {
    Success(binds) =>
      for b in binds {
        if is_depr_key(b.key) {
          let name = b.key[6:].to_owned()
          if !str_mem(out, name) {
            out.push(name)
          }
        }
      }
    _ => ()
  }
  out
}

///|
fn str_mem(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

///|
/// The action name if `b` is a failure-action marker, else None.
fn action_of(b : Binding) -> String? {
  if is_action_key(b.key) {
    Some(b.key[5:].to_owned())
  } else {
    None
  }
}

///|
/// Whether a result key is a failure-action marker (`@act:...`).
pub fn is_action_key(k : String) -> Bool {
  let p = "@act:"
  k.length() >= p.length() && k[0:p.length()].to_owned() == p
}

///|
/// Nest a set of bindings one level deeper under `label` (spec DR-025). A
/// LINK binding (spec DR-042 global link-sync) with `link > 0` ESCAPES this
/// level: it skips the prepend and decrements its counter, climbing out of
/// the scopes BELOW its declaration.
fn nest(label : String, binds : Array[Binding]) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in binds {
    if b.link > 0 {
      out.push({ ..b, link: b.link - 1 })
    } else {
      let sc2 : Array[String] = [label]
      for s in b.scope {
        sc2.push(s)
      }
      out.push({
        key: b.key,
        op: b.op,
        value: b.value,
        source: b.source,
        scope: sc2,
        link: b.link,
      })
    }
  }
  out
}

///|
/// Apply `nest` to every Accept branch's bindings (Held / Pending pass
/// through: their partial state is failure/completion material, not a
/// result object, so nesting is not needed for it).
fn nest_branches(label : String, brs : Array[Branch]) -> Array[Branch] {
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Accept(p, bs) => out.push(Accept(p, nest(label, bs)))
      Held(pe, bs) => out.push(Held(pe, bs))
      Pending(cs, bs) => out.push(Pending(cs, bs))
    }
  }
  out
}

///|
/// The `{}` object-presence marker at scope `[label]`: an invoked command
/// scope appears (as at least `{}`) even when it produced no bindings.
fn scope_marker(label : String) -> Binding {
  {
    key: "{}",
    op: Set,
    value: VBool(false),
    source: Cli,
    scope: [label],
    link: 0,
  }
}

///|
/// Array-presence marker: `{key:"[]"}` at the array's scope, so an empty
/// array still appears in the result.
fn array_marker(label : String) -> Binding {
  {
    key: "[]",
    op: Set,
    value: VBool(false),
    source: Cli,
    scope: [label],
    link: 0,
  }
}

///|
/// A pending-value candidate (the Pending payload): the value slot of
/// `origin`, of type `ty`, had no token left to consume.
fn pend_value(ty : Ty, origin : String) -> Cand {
  {
    spelling: "",
    is_value: true,
    ty,
    origin,
    term: WordEnd,
    meta: { is_alias: false, hidden: false, deprecated: false },
  }
}

// ── off-spine node evaluation (direct style) ─────────────────────────────────
//
// Plain `eval` stays direct (returns branches to its caller) — CPS threading
// is needed only where a choice must consult "the rest of the whole parse":
// the scope walk (scope_step / scope_consume) below. A greedy entry's
// internals, matcher readings, Or alternatives etc. are bounded and local.

///|
/// Evaluate a node at `pos`, returning every reading (Accept), held Error,
/// and pending-value state.
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
        // an unmatched / exhausted trigger is a silent Reject (spec DR-037),
        // NOT a Pending: no part of the entry was consumed, so nothing is
        // "half-read". (Boundary trigger candidates for complete are the
        // outcome layer's concern, collected separately.)
        []
      }
    StrArg(name) =>
      if pos < toks.length() {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else {
        // MDR-002 §2.1: the end of input at a value slot is an explicit
        // Pending, not a silent []. Reached mid-greedy-entry (after the
        // trigger consumed) this is the "--port with no value" state.
        [Pending([pend_value(TStr, name)], [])]
      }
    SepArg(name, sep) =>
      if pos < toks.length() {
        [Accept(pos + 1, sep_binds(name, toks[pos], sep))]
      } else {
        [Pending([pend_value(TStr, name)], [])]
      }
    NumArg(name) =>
      if pos < toks.length() {
        match parse_number(toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, toks[pos], pos), [])]
        }
      } else {
        [Pending([pend_value(TNum, name)], [])]
      }
    FilterArg(name, max) => filter_arg_eval(name, max, toks, pos, [])
    ReqArg(name) => req_arg_eval(name, toks, pos, [])
    Bind(name, v) => [Accept(pos, [mkb(name, v, Cli)])]
    EffMark(name, op) => [Accept(pos, [mk_eff(name, op, Cli)])]
    FailMark(name) => [Accept(pos, [action_marker(name, pos)])]
    DeprMark(name) => [Accept(pos, [depr_marker(name)])]
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
    Scoped(label, body) => nest_branches(label, eval(body, toks, pos, defs))
    ScopeNode(sc) =>
      // off-spine scope: accept wherever the scope ends (KDone), mirroring
      // the slice's eval_scope. The SPINE path (scope_consume) instead
      // threads the real continuation.
      scope_step(sc, toks, pos, 0, [], false, defs, KDone)
    NativeMatch(m) => run_matcher(m, toks, pos)
    Ref(name) =>
      match defs.get(name) {
        Some(tpl) => eval(tpl, toks, pos, defs)
        None => []
      }
    DdSat(trigger) =>
      if pos < toks.length() && toks[pos] == trigger {
        [Accept(pos + 1, [])]
      } else {
        []
      }
    CmdSat(name, child) =>
      // off-spine command (a probe or a nested context): child evaluated with
      // KDone; bindings nest under the name + presence marker. The greedy
      // face path (step_greedy) threads the real continuation instead.
      if pos < toks.length() && toks[pos] == name {
        mark_scope(
          name,
          nest_branches(
            name,
            scope_step(child, toks, pos + 1, 0, [], false, defs, KDone),
          ),
        )
      } else {
        []
      }
    Rooted(inner, depth) => {
      let out : Array[Branch] = []
      for b in eval(inner, toks, pos, defs) {
        match b {
          Accept(p, bs) => {
            let marked : Array[Binding] = []
            for x in bs {
              marked.push({
                key: x.key,
                op: x.op,
                value: x.value,
                source: x.source,
                scope: x.scope,
                link: depth,
              })
            }
            out.push(Accept(p, marked))
          }
          Held(pe, bs) => out.push(Held(pe, bs))
          Pending(cs, bs) => out.push(Pending(cs, bs))
        }
      }
      out
    }
    NoDashStr(name) =>
      // pre_filter (spec DR-037): a dashed token REJECTS silently. At the end
      // of input this stays a Reject too (the filter cannot promise a token
      // would be accepted), not a Pending.
      if pos < toks.length() && !starts_dash(toks[pos]) {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else {
        []
      }
    IdxRepeat(label, head, min) =>
      idx_repeat_eval(label, head, min, toks, pos, defs)
    BoundedTail(head, budget, _) =>
      // off-spine fallback: degrade to the nested-Opt form (0..budget heads).
      eval(bounded_opt(head, budget), toks, pos, defs)
  }
}

///|
/// The nested-Opt equivalent of a bounded tail: 0..budget heads.
fn bounded_opt(head : Node, budget : Int) -> Node {
  if budget <= 0 {
    Seq([])
  } else {
    Or([Seq([head, bounded_opt(head, budget - 1)]), Seq([])])
  }
}

///|
/// A `kind: parse` held Error for a structurally-mandatory value that had NO
/// token to consume (構造的必須の不成立, spec DR-065 §3): argv_pos = argv
/// length (where the token was requested).
fn pe_missing(element : String, pos : Int) -> ParseError {
  {
    element,
    argv_pos: pos,
    kind: KParse,
    reason: "missing_operand",
    message: "missing operand for \{element}",
  }
}

///|
/// FilterArg: parse a number then apply a max post-filter. A parse failure is
/// `kind: parse`; a value above `max` is `kind: filter`.
fn filter_arg_eval(
  name : String,
  max : Int,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  if pos < toks.length() {
    match parse_number(toks[pos]) {
      Some(d) =>
        if d > max.to_double() {
          [
            Held(
              {
                element: name,
                argv_pos: pos,
                kind: KFilter,
                reason: "too_large",
                message: "\{name} value \{toks[pos]} exceeds max \{max}",
              },
              acc,
            ),
          ]
        } else {
          [Accept(pos + 1, cat(acc, [mkb(name, VNum(d), Cli)]))]
        }
      None => [Held(pe_parse(name, toks[pos], pos), acc)]
    }
  } else {
    [Held(pe_missing(name, pos), acc)]
  }
}

///|
/// ReqArg (spec DR-047 / DR-053 kind: constraint): NO token to consume is a
/// `kind: constraint` held Error, not a silent Reject.
fn req_arg_eval(
  name : String,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  if pos < toks.length() {
    [Accept(pos + 1, cat(acc, [mkb(name, VStr(toks[pos]), Cli)]))]
  } else {
    [
      Held(
        {
          element: name,
          argv_pos: pos,
          kind: KConstraint,
          reason: "required_violated",
          message: "required \{name} is missing",
        },
        acc,
      ),
    ]
  }
}

///|
fn starts_dash(s : String) -> Bool {
  for c in s {
    return c == '-'
  }
  false
}

///|
fn first_char(s : String) -> Char {
  for c in s {
    return c
  }
  ',' // unreachable for a non-empty separator
}

///|
/// Split `s` on the first char of `sep` (spec DR-034 single-char separator).
fn split_on(s : String, sep : String) -> Array[String] {
  let sepc = first_char(sep)
  let out : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == sepc {
      out.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  out.push(cur)
  out
}

///|
/// One Set-effect binding per split piece (spec DR-034 + DR-045).
fn sep_binds(name : String, tok : String, sep : String) -> Array[Binding] {
  let out : Array[Binding] = []
  for part in split_on(tok, sep) {
    out.push(mkb(name, VStr(part), Cli))
  }
  out
}

///|
/// Prepend the `{}` presence marker to each Accept.
fn mark_scope(name : String, brs : Array[Branch]) -> Array[Branch] {
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Accept(p, bs) => out.push(Accept(p, cat([scope_marker(name)], bs)))
      Held(pe, bs) => out.push(Held(pe, bs))
      Pending(cs, bs) => out.push(Pending(cs, bs))
    }
  }
  out
}

///|
/// Tag a rep's bindings under `[label, "#k"]` (a result-array index).
fn nest_index(label : String, rep : Int, bs : Array[Binding]) -> Array[Binding] {
  let seg = "#" + rep.to_string()
  let out : Array[Binding] = []
  for b in bs {
    if b.link > 0 {
      out.push({ ..b, link: b.link - 1 })
    } else {
      let sc2 : Array[String] = [label, seg]
      for s in b.scope {
        sc2.push(s)
      }
      out.push({
        key: b.key,
        op: b.op,
        value: b.value,
        source: b.source,
        scope: sc2,
        link: 0,
      })
    }
  }
  out
}

///|
/// Greedy-max named indexed-array repeat (spec DR-043): consumes as many reps
/// as the head allows, deterministically (the split is bounded by the head's
/// Reject / exact mismatch, no downstream backtrack).
fn idx_repeat_eval(
  label : String,
  head : Node,
  min : Int,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Array[Branch] {
  let acc : Array[Binding] = [array_marker(label)]
  let mut cur = pos
  let mut rep = 0
  let mut go = true
  while go {
    let p2 = idx_one(head, label, rep, toks, cur, defs, acc)
    if p2 > cur {
      cur = p2
      rep = rep + 1
    } else {
      go = false
    }
  }
  if rep < min {
    []
  } else {
    [Accept(cur, acc)]
  }
}

///|
fn idx_one(
  head : Node,
  label : String,
  rep : Int,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
  acc : Array[Binding],
) -> Int {
  for b in eval(head, toks, pos, defs) {
    match b {
      Accept(p2, bs) =>
        if p2 > pos {
          for x in nest_index(label, rep, bs) {
            acc.push(x)
          }
          return p2
        }
      Held(_, _) => ()
      Pending(_, _) => ()
    }
  }
  pos
}

///|
/// Thread `pos` through a Seq; bindings accumulate; a Held dead-ends its
/// branch; a Pending is terminal (input exhausted) and carries the acc so
/// far — this is the "trigger consumed, value slot starved" state that the
/// slice silently collapsed to [] (MDR-002 §2.1).
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
      // the Held carries the Seq's accumulated partial state too: a marker
      // bound EARLIER in the same entry (e.g. `--help`'s FailMark before a
      // failing value slot) must reach parse() for fired_action selection
      // (DR-048 / DR-053 §4 共存). The slice dropped acc here — a defect the
      // adversarial review caught, not a parity to keep.
      Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
      Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
    }
  }
  out
}

///|
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
      Held(pe, bs) => out.push(Held(pe, bs))
      // a Pending after >= 1 successful reps still carries the reps' acc
      // (same contract as eval_seq: Pending = starved branch WITH its state).
      Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
    }
  }
  out
}

// ── two-face scope, CPS (spec DR-041 §4 + MDR-002 §1) ────────────────────────
//
// `severed` is the dd mode: once `--` is consumed, the greedy face is off for
// the rest of the walk and everything falls raw into positionals.

///|
/// A greedy entry "reads" at `pos` iff its TRIGGER engages the token there
/// (spec DR-041 §4: 素通しはトリガ不一致 = 読みゼロの時のみ). This is a
/// structural trigger-match, NOT "does the whole entry consume successfully":
/// an engaged trigger whose value slot then fails (bad number, starved slot,
/// unfulfillable child scope) still suppresses the raw-eat — the token is
/// read HERE and the entry's Held/Pending is the outcome, never a silent
/// positional fallback (deep review R1/R2: `--port xyz` and a value-less
/// `build` used to silently succeed as positionals). Entries without a
/// structural trigger (bare value primitives) keep the consumption-based
/// probe, so a degenerate bare NumArg greedy does not over-suppress.
fn greedy_engages(
  g : Node,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Bool {
  match g {
    Seq(items) =>
      if items.length() >= 1 {
        match items[0] {
          Exact(s) => toks[pos] == s
          NativeMatch(m) => run_matcher(m, toks, pos).length() > 0
          _ => eval_consumes(g, toks, pos, defs)
        }
      } else {
        false
      }
    Or(alts) => {
      for a in alts {
        if greedy_engages(a, toks, pos, defs) {
          return true
        }
      }
      false
    }
    CmdSat(name, _) => toks[pos] == name
    DdSat(t) => toks[pos] == t
    // a matcher engages iff it yields ANY reading or held Error ([] = 素通し,
    // e.g. an undefined --key= or a non-prefix token).
    NativeMatch(m) => run_matcher(m, toks, pos).length() > 0
    Rooted(inner, _) => greedy_engages(inner, toks, pos, defs)
    _ => eval_consumes(g, toks, pos, defs)
  }
}

///|
/// Consumption-based fallback probe for trigger-less greedy shapes: reads iff
/// some branch consumes a token (or a Pending shows a trigger was consumed).
fn eval_consumes(
  g : Node,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Bool {
  for b in eval(g, toks, pos, defs) {
    match b {
      Accept(p2, _) => if p2 > pos { return true }
      Held(_, _) => ()
      Pending(_, _) => return true
    }
  }
  false
}

///|
fn greedy_reads(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Bool {
  if pos >= toks.length() {
    return false // no token to read (早閉じ check at the end of input)
  }
  for g in sc.greedy {
    if greedy_engages(g, toks, pos, defs) {
      return true
    }
  }
  false
}

///|
/// Whether raw pass-through of the token at `pos` is suppressed. 先食い is
/// greedy-ONLY (spec DR-041 §4): a raw-eat is suppressed iff some greedy
/// entry reads the token. Once severed, nothing is suppressed.
fn suppressed(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  severed : Bool,
  defs : Map[String, Node],
) -> Bool {
  if severed {
    return false
  }
  greedy_reads(sc, toks, pos, defs)
}

///|
/// Walk sc.positional[pidx..] from `pos` with continuation `k`. Offers (A) a
/// greedy interjection (only when not severed) and (B) advancing the
/// positional face; a finished face RUNS `k` (subject to 早閉じ抑制).
fn scope_step(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
  k : Cont,
) -> Array[Branch] {
  let out : Array[Branch] = []
  // (A) greedy interjection — re-enter at the same pidx (positional face
  // untouched). CmdSat / DdSat are dispatched structurally so their child
  // walk gets the REAL continuation (this is where phase16 is won: the
  // child's repeats must see that the parent still wants a token).
  if !severed {
    for g in sc.greedy {
      step_greedy(g, sc, toks, pos, pidx, acc, severed, defs, k, out)
    }
  }
  // (B) advance the positional face
  if pidx >= sc.positional.length() {
    // 早閉じ抑制 (spec DR-041 §4): a scope with a backbone cannot complete
    // while one of its own greedy entries can read the next token — "that
    // which can be read here, is read here".
    if severed || !greedy_reads(sc, toks, pos, defs) {
      for r in run_cont(k, toks, pos, acc, defs) {
        out.push(r)
      }
    }
  } else {
    for
      r in scope_consume(
        sc,
        sc.positional[pidx],
        toks,
        pos,
        pidx,
        acc,
        severed,
        defs,
        k,
      ) {
      out.push(r)
    }
  }
  out
}

///|
/// One greedy entry's interjection at (pos, pidx). Structural dispatch:
/// - CmdSat: enter the child scope as a NEW backbone whose continuation is
///   "nest my bindings under the command name, then resume the parent at the
///   same pidx" — the child sees the whole outside world through `k`.
/// - DdSat: consume the trigger and sever the rest of the walk.
/// - Or: each alternative is its own interjection.
/// - anything else: plain eval, then re-enter the walk on each reading.
fn step_greedy(
  g : Node,
  sc : Scope,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
  k : Cont,
  out : Array[Branch],
) -> Unit {
  match g {
    CmdSat(name, child) =>
      if pos < toks.length() && toks[pos] == name {
        let kk = KNest(
          name,
          true,
          acc.length(),
          KResumeScope(sc, pidx, severed, k),
        )
        for r in scope_step(child, toks, pos + 1, 0, acc, false, defs, kk) {
          out.push(r)
        }
      }
    DdSat(trigger) =>
      if pos < toks.length() && toks[pos] == trigger {
        for r in scope_step(sc, toks, pos + 1, pidx, acc, true, defs, k) {
          out.push(r)
        }
      }
    Or(alts) =>
      for a in alts {
        step_greedy(a, sc, toks, pos, pidx, acc, severed, defs, k, out)
      }
    _ =>
      for b in eval(g, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              for
                r in scope_step(
                  sc,
                  toks,
                  p2,
                  pidx,
                  cat(acc, bs),
                  severed,
                  defs,
                  k,
                ) {
                out.push(r)
              }
            }
          // acc must be carried on Held so an earlier FailMark (fired_action
          // material, eval_seq comment DR-048/DR-053 §4) survives to parse().
          Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
          Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
        }
      }
  }
}

///|
/// Consume one positional item, then continue at pidx+1 (repeats stay at
/// pidx). Each arm that finishes its consumption re-enters scope_step with
/// the SAME `k` — the continuation is only ever RUN at a scope end.
fn scope_consume(
  sc : Scope,
  item : Node,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
  k : Cont,
) -> Array[Branch] {
  match item {
    StrArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx + 1,
          cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed,
          defs,
          k,
        )
      } else if pos >= toks.length() {
        // 構造的必須の不成立 (spec DR-065 §3): the spine needs a token for
        // `name` but the argv is exhausted. Held, not a silent Reject.
        [Held(pe_missing(name, pos), acc)]
      } else {
        [] // 先食い: a greedy trigger sits here; the spine stays pending
      }
    SepArg(name, sep) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx + 1,
          cat(acc, sep_binds(name, toks[pos], sep)),
          severed,
          defs,
          k,
        )
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), acc)]
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) =>
            scope_step(
              sc,
              toks,
              pos + 1,
              pidx + 1,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              defs,
              k,
            )
          None => [Held(pe_parse(name, toks[pos], pos), acc)]
        }
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), acc)]
      } else {
        []
      }
    FilterArg(name, max) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) =>
            if d > max.to_double() {
              [
                Held(
                  {
                    element: name,
                    argv_pos: pos,
                    kind: KFilter,
                    reason: "too_large",
                    message: "\{name} value \{toks[pos]} exceeds max \{max}",
                  },
                  acc,
                ),
              ]
            } else {
              scope_step(
                sc,
                toks,
                pos + 1,
                pidx + 1,
                cat(acc, [mkb(name, VNum(d), Cli)]),
                severed,
                defs,
                k,
              )
            }
          None => [Held(pe_parse(name, toks[pos], pos), acc)]
        }
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), acc)]
      } else {
        []
      }
    ReqArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx + 1,
          cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed,
          defs,
          k,
        )
      } else if pos >= toks.length() {
        [
          Held(
            {
              element: name,
              argv_pos: pos,
              kind: KConstraint,
              reason: "required_violated",
              message: "required \{name} is missing",
            },
            acc,
          ),
        ]
      } else {
        []
      }
    Exact(s) =>
      if pos < toks.length() && toks[pos] == s {
        scope_step(sc, toks, pos + 1, pidx + 1, acc, severed, defs, k)
      } else {
        []
      }
    // A repeat item (spec DR-043): >= 1 head, unfolded POROUSLY on the spine.
    //
    // 取り分の選好: the split between adjacent closures is ONE
    // interpretation's freedom of division, not an ambiguity. greedy
    // (default) prefers the LONGER share, lazy_ the shorter. We commit to the
    // FIRST preference whose continuation reaches a FULL parse and PRUNE the
    // other. Under CPS, `stop`/`more` are the results of running EVERYTHING
    // that follows (this scope's rest + the parent's rest + the global end
    // check), so has_full_k is exact at ANY nesting depth — this is the
    // phase16 fix (MDR-002 §1.4).
    Ref(name) =>
      match ref_head(defs, name) {
        // A scope-shaped head must NOT go through plain eval (KDone): its
        // internal repeats need the true continuation, or breakage-1 comes
        // back one nesting level in (REVIEW-H1 wbtest). The head's own walk
        // gets the choice point as its continuation frame instead.
        ScopeNode(child) =>
          // DR-041 dashdash: dd severs the greedy face for the REST of the
          // spine, including any child scope reached through the porous
          // unfold. The child's own walk inherits `severed` so a dd-continued
          // token cannot re-fire a greedy in the child scope.
          scope_step(
            child,
            toks,
            pos,
            0,
            acc,
            severed,
            defs,
            KRefChoice(sc, name, pidx, severed, pos, k),
          )
        head => {
          let out : Array[Branch] = []
          for b in consume_head(sc, head, toks, pos, severed, defs) {
            match b {
              Accept(p2, bs) =>
                if p2 > pos {
                  for
                    r in ref_choice(
                      sc,
                      name,
                      toks,
                      p2,
                      pidx,
                      cat(acc, bs),
                      severed,
                      defs,
                      k,
                    ) {
                    out.push(r)
                  }
                }
              // Carry acc on Held (fired_action material preservation).
              Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
              Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
            }
          }
          out
        }
      }
    BoundedTail(head, budget, lazy_) =>
      bounded_tail_step(
        sc, head, budget, lazy_, toks, pos, pidx, acc, severed, defs, k,
      )
    Many(inner) => {
      // Two closures on the spine — parity with Ref/BoundedTail 取り分選好
      // (spec DR-043). Without preference, `[Many(xs), Many(ys)]` on ["a","b"]
      // returns Ambiguous (3-way split) even though the greedy default fixes
      // xs=[a,b], ys=[] as the representative. `Many` is greedy-only (no lazy_
      // knob in the AST) — more-rep first, then stop.
      let stop = scope_step(sc, toks, pos, pidx + 1, acc, severed, defs, k) // 0 reps
      let more = scope_consume_rep(
        sc, inner, toks, pos, pidx, acc, severed, defs, k,
      ) // 1 rep (which re-enters scope_step at same pidx)
      if has_full_k(more) {
        more
      } else if has_full_k(stop) {
        stop
      } else {
        cat_branches(stop, more)
      }
    }
    ScopeNode(child) =>
      // spec DR-042 ⑤: a child scope runs its own walk (the parent greedy
      // face does not interject during it). `severed` DOES pass through — dd
      // severs the greedy face for the whole rest of the spine, including
      // inline child scopes reached through the positional face (DR-041
      // dashdash: continuation is raw). The parent-resume continuation still
      // remembers the outer severed independently.
      scope_step(
        child,
        toks,
        pos,
        0,
        acc,
        severed,
        defs,
        KResumeScope(sc, pidx + 1, severed, k),
      )
    other => {
      // any other node as a positional item: eval plainly, then continue.
      let out : Array[Branch] = []
      for b in eval(other, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            for
              r in scope_step(
                sc,
                toks,
                p2,
                pidx + 1,
                cat(acc, bs),
                severed,
                defs,
                k,
              ) {
              out.push(r)
            }
          // Carry acc on Held (fired_action material preservation).
          Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
          Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
        }
      }
      out
    }
  }
}

///|
/// The stop/more 取り分選好 of a Ref repeat, entered AFTER one head consumed
/// up to `p2` (bindings already in `acc2`). Shared by the inline primitive
/// path and the KRefChoice continuation frame (scope-shaped heads).
fn ref_choice(
  sc : Scope,
  name : String,
  toks : Array[String],
  p2 : Int,
  pidx : Int,
  acc2 : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
  k : Cont,
) -> Array[Branch] {
  let head = ref_head(defs, name)
  let lazy_ = ref_is_lazy(defs, name)
  let stop = scope_step(sc, toks, p2, pidx + 1, acc2, severed, defs, k)
  // "more" = one more OPTIONAL rep; a missing-operand for ANY value
  // primitive reachable inside the repeat head (scope-shaped included) is a
  // legitimate stop, not a failure. head-external missing (a downstream
  // primitive fed by the parent continuation) stays.
  let more = drop_optional_missing(
    scope_step(sc, toks, p2, pidx, acc2, severed, defs, k),
    head_elem_names(head),
  )
  if lazy_ {
    if has_full_k(stop) {
      stop
    } else if has_full_k(more) {
      more
    } else {
      cat_branches(stop, more)
    }
  } else if has_full_k(more) {
    more
  } else if has_full_k(stop) {
    stop
  } else {
    cat_branches(stop, more)
  }
}

///|
/// A bounded repeat tail (spec DR-043 max 有限): consume 0..budget more heads
/// porously, with the same 取り分選好 as the Ref path.
fn bounded_tail_step(
  sc : Scope,
  head : Node,
  budget : Int,
  lazy_ : Bool,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
  k : Cont,
) -> Array[Branch] {
  let stop = scope_step(sc, toks, pos, pidx + 1, acc, severed, defs, k)
  let more_raw : Array[Branch] = if budget >= 1 {
    match head {
      // scope-shaped head: same KDone hazard as the Ref path (REVIEW-H1) —
      // the head's walk carries the tail's choice point as its continuation.
      ScopeNode(child) =>
        // same dd sever pass-through as the scope_consume ScopeNode arms.
        scope_step(
          child,
          toks,
          pos,
          0,
          acc,
          severed,
          defs,
          KTailChoice(sc, head, budget - 1, lazy_, pidx, severed, pos, k),
        )
      _ => {
        let out : Array[Branch] = []
        for b in consume_head(sc, head, toks, pos, severed, defs) {
          match b {
            Accept(p2, bs) =>
              if p2 > pos {
                for
                  r in bounded_tail_step(
                    sc,
                    head,
                    budget - 1,
                    lazy_,
                    toks,
                    p2,
                    pidx,
                    cat(acc, bs),
                    severed,
                    defs,
                    k,
                  ) {
                  out.push(r)
                }
              }
            // NOTE: bounded_tail_step's Held acc handling is intentionally
            // left alone here — the 4-site scope-walk acc fix targeted the
            // scope_step / scope_consume family only. Revisit if a FailMark
            // preservation gap surfaces in the bounded tail path.
            Held(pe, bs) => out.push(Held(pe, bs))
            Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
          }
        }
        out
      }
    }
  } else {
    []
  }
  // Filter the OPTIONAL "more" branch's internal missing_operand@EOF for any
  // primitive reachable in the head (scope-shaped heads included, spec
  // DR-065 §3 held-error parity). head-external missing from the parent's
  // continuation is preserved.
  let more = drop_optional_missing(more_raw, head_elem_names(head))
  if lazy_ {
    if has_full_k(stop) {
      stop
    } else if has_full_k(more) {
      more
    } else {
      cat_branches(stop, more)
    }
  } else if has_full_k(more) {
    more
  } else if has_full_k(stop) {
    stop
  } else {
    cat_branches(stop, more)
  }
}

///|
/// Consume one repeat head on the spine. A value primitive respects 先食い; a
/// non-primitive head is evaluated plainly. Argv exhaustion on the mandatory
/// head is a missing-operand Held (held-error parity, spec DR-065 §3) — the
/// OPTIONAL "more" context filters it back out (drop_optional_missing).
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
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), [])]
      } else {
        []
      }
    SepArg(name, sep) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        [Accept(pos + 1, sep_binds(name, toks[pos], sep))]
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), [])]
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, toks[pos], pos), [])]
        }
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), [])]
      } else {
        []
      }
    // ReqArg / FilterArg get their own arms so 先食い (suppressed) applies —
    // eval() does not see the parent scope, so falling through would let a
    // greedy trigger token be raw-eaten as the repeat head's value. Held
    // shapes must match the primitive arms above so drop_optional_missing on
    // the OPTIONAL "more" branch can filter them uniformly.
    ReqArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else if pos >= toks.length() {
        [
          Held(
            {
              element: name,
              argv_pos: pos,
              kind: KConstraint,
              reason: "required_violated",
              message: "required \{name} is missing",
            },
            [],
          ),
        ]
      } else {
        []
      }
    FilterArg(name, max) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) =>
            if d > max.to_double() {
              [
                Held(
                  {
                    element: name,
                    argv_pos: pos,
                    kind: KFilter,
                    reason: "too_large",
                    message: "\{name} value \{toks[pos]} exceeds max \{max}",
                  },
                  [],
                ),
              ]
            } else {
              [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
            }
          None => [Held(pe_parse(name, toks[pos], pos), [])]
        }
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), [])]
      } else {
        []
      }
    _ => eval(head, toks, pos, defs)
  }
}

///|
/// The value-primitive element names reachable inside a repeat head (spec
/// DR-043 / DR-065 §3 held-error parity for scope-shaped heads). For a
/// primitive head this is [name]; for a ScopeNode head this recurses into the
/// child scope's greedy + positional structure so drop_optional_missing can
/// suppress the "one more OPTIONAL rep" internal missing_operand@EOF for
/// EVERY primitive the head might produce, while downstream (head-external)
/// missing_operand from the parent's continuation still surfaces.
fn head_elem_names(head : Node) -> Array[String] {
  let out : Array[String] = []
  head_elem_names_into(head, out)
  out
}

///|
fn head_elem_names_into(n : Node, out : Array[String]) -> Unit {
  match n {
    StrArg(name) => if !str_mem(out, name) { out.push(name) }
    SepArg(name, _) => if !str_mem(out, name) { out.push(name) }
    NumArg(name) => if !str_mem(out, name) { out.push(name) }
    FilterArg(name, _) => if !str_mem(out, name) { out.push(name) }
    ReqArg(name) => if !str_mem(out, name) { out.push(name) }
    Seq(items) =>
      for it in items {
        head_elem_names_into(it, out)
      }
    Or(alts) =>
      for a in alts {
        head_elem_names_into(a, out)
      }
    Many(inner) => head_elem_names_into(inner, out)
    BoundedTail(h, _, _) => head_elem_names_into(h, out)
    ScopeNode(sc) => {
      for g in sc.greedy {
        head_elem_names_into(g, out)
      }
      for p in sc.positional {
        head_elem_names_into(p, out)
      }
    }
    // Ref/CmdSat/DdSat/Rooted/etc.: opaque or heavy — do not recurse (Ref
    // could loop; command/dd satellites are not walked by the head reps).
    _ => ()
  }
}

///|
/// Drop `missing_operand` Held Errors whose element is in `names` from an
/// OPTIONAL repeat-continuation ("more") branch set: reaching "more" means a
/// rep of one of these primitives already succeeded, so "one more optional
/// rep found no token" is a legitimate STOP, not a structural failure. Only
/// the exact missing-operand-for-name shape is dropped; head-external missing
/// (a downstream primitive fed by the parent's continuation) stays.
fn drop_optional_missing(
  brs : Array[Branch],
  names : Array[String],
) -> Array[Branch] {
  if names.length() == 0 {
    return brs
  }
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Held(pe, _) =>
        if pe.reason == "missing_operand" && str_mem(names, pe.element) {
          () // dropped: internal "one more rep" EOF signal
        } else {
          out.push(b)
        }
      _ => out.push(b)
    }
  }
  out
}

///|
/// The head of a repeat template `Seq([head, Opt(Ref(name))])`.
fn ref_head(defs : Map[String, Node], name : String) -> Node {
  match defs.get(name) {
    Some(Seq(items)) =>
      if items.length() >= 1 {
        items[0]
      } else {
        Exact("<bad-ref>")
      }
    _ => Exact("<bad-ref>")
  }
}

///|
/// Whether the repeat named `name` prefers the SHORTER share (lazy). The flag
/// is stored under a mangled registry key by the repeat installer. NB: the
/// key is the wire-ish vocabulary string "lazy:" (paired with the installer) —
/// MDR-003's identifier rename (lazy → lazy_) does NOT apply to this string
/// (a blanket rename once broke lazy preference entirely; pinned by the
/// conformance fixture repeat-parse/preference-lazy).
fn ref_is_lazy(defs : Map[String, Node], name : String) -> Bool {
  match defs.get("lazy:" + name) {
    Some(_) => true
    None => false
  }
}

///|
fn cat_branches(a : Array[Branch], b : Array[Branch]) -> Array[Branch] {
  let r : Array[Branch] = []
  for x in a {
    r.push(x)
  }
  for x in b {
    r.push(x)
  }
  r
}

///|
/// One repetition of a Many's inner item (subject to 先食い), continuing at
/// the SAME pidx so the Many remains available (porous reps).
fn scope_consume_rep(
  sc : Scope,
  inner : Node,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
  k : Cont,
) -> Array[Branch] {
  match inner {
    StrArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx,
          cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed,
          defs,
          k,
        )
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) =>
            scope_step(
              sc,
              toks,
              pos + 1,
              pidx,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              defs,
              k,
            )
          None => [Held(pe_parse(name, toks[pos], pos), acc)]
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
              for
                r in scope_step(
                  sc,
                  toks,
                  p2,
                  pidx,
                  cat(acc, bs),
                  severed,
                  defs,
                  k,
                ) {
                out.push(r)
              }
            }
          // Carry acc on Held (fired_action material preservation).
          Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
          Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
        }
      }
      out
    }
  }
}

///|
/// Drop the `link` nesting hint — it is resolved before path counting.
fn strip_link(bs : Array[Binding]) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in bs {
    out.push({
      key: b.key,
      op: b.op,
      value: b.value,
      source: b.source,
      scope: b.scope,
      link: 0,
    })
  }
  out
}

// ── constraint evaluation (delayed predicates, spec DR-055 / DR-047) ─────────
//
// Constraints are predicates on the DECLARING scope's entities (spec DR-012 /
// DR-055 §1 lexical resolution), so binding lookups are scoped: a binding
// matches (path, name) iff its key AND its result-nesting path both match.
// Key-only matching leaked commits across scopes in both directions — a
// child's same-named cell falsely triggered / falsely satisfied a root
// constraint (deep review EXP-B/C/D, O2/O2b).

///|
fn scope_path_eq(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Whether the (path, name) cell is committed on a path (spec DR-045): the
/// LAST effect on the cell is not unset (last-wins).
fn is_committed(
  bindings : Array[Binding],
  path : Array[String],
  name : String,
) -> Bool {
  let mut committed = false
  for b in bindings {
    if b.key == name && scope_path_eq(b.scope, path) {
      match b.op {
        Unset => committed = false
        _ => committed = true
      }
    }
  }
  committed
}

///|
/// The committed value of the (path, name) cell (last-wins), or None.
fn elem_value(
  bindings : Array[Binding],
  path : Array[String],
  name : String,
) -> String? {
  let mut v : String? = None
  for b in bindings {
    if b.key == name && scope_path_eq(b.scope, path) {
      match b.op {
        Unset => ()
        _ => v = Some(value_str(b.value))
      }
    }
  }
  v
}

///|
fn has_default(entities : Array[Entity], name : String) -> Bool {
  for e in entities {
    if e.name == name {
      return e.default_value is Some(_)
    }
  }
  false
}

///|
/// Value presence (spec DR-047 §5): committed on the path OR a default seat
/// exists (default seats live on the declaring scope's own entities).
fn value_present(
  name : String,
  bindings : Array[Binding],
  path : Array[String],
  entities : Array[Entity],
) -> Bool {
  is_committed(bindings, path, name) || has_default(entities, name)
}

///|
fn constraint_err(
  element : String,
  reason : String,
  message : String,
  pos : Int,
) -> ParseError {
  { element, argv_pos: pos, kind: KConstraint, reason, message }
}

///|
/// Evaluate ONE scope's delayed predicates on a complete path's FINAL state.
/// A non-empty result means the path is NOT a complete解決経路.
fn eval_constraints(
  sc : ScopedCons,
  bindings : Array[Binding],
  pos : Int,
) -> Array[ParseError] {
  let out : Array[ParseError] = []
  let path = sc.path
  for c in sc.constraints {
    match c {
      CRequires(elem, targets) =>
        if is_committed(bindings, path, elem) {
          for t in targets {
            if !value_present(t, bindings, path, sc.entities) {
              out.push(
                constraint_err(
                  elem,
                  "requires_violated",
                  "'\{elem}' requires '\{t}'",
                  pos,
                ),
              )
            }
          }
        }
      CRequiresIf(elem, v, targets) => {
        let active = is_committed(bindings, path, elem) &&
          (match elem_value(bindings, path, elem) {
            Some(x) => x == v
            None => false
          })
        if active {
          for t in targets {
            if !value_present(t, bindings, path, sc.entities) {
              out.push(
                constraint_err(
                  elem,
                  "requires_violated",
                  "'\{elem}'=\{v} requires '\{t}'",
                  pos,
                ),
              )
            }
          }
        }
      }
      CConflicts(elem, targets) =>
        if is_committed(bindings, path, elem) {
          for t in targets {
            if is_committed(bindings, path, t) {
              out.push(
                constraint_err(
                  elem,
                  "conflicts_with_violated",
                  "'\{elem}' conflicts with '\{t}'",
                  pos,
                ),
              )
            }
          }
        }
      CExclusive(group, members) => {
        let mut count = 0
        for m in members {
          if is_committed(bindings, path, m) {
            count = count + 1
          }
        }
        if count > 1 {
          out.push(
            constraint_err(
              group,
              "exclusive_group_violated",
              "exclusive group '\{group}' allows at most one",
              pos,
            ),
          )
        }
      }
    }
  }
  out
}

///|
/// Evaluate EVERY collected scope's constraints (spec DR-047 §2 has no
/// declaring-scope exemption — a nested scope's predicates are completion
/// conditions too). Called from KTop: this makes "complete解決経路 = full
/// consumption AND all constraints satisfied" a single definition that the
/// 取り分選好 oracle (has_full_k) automatically shares — the parse() layer
/// and the preference layer can no longer disagree about completeness.
fn eval_all_constraints(
  table : Array[ScopedCons],
  bindings : Array[Binding],
  pos : Int,
) -> Array[ParseError] {
  let out : Array[ParseError] = []
  for sc in table {
    for v in eval_constraints(sc, bindings, pos) {
      out.push(v)
    }
  }
  out
}

// ── static scope collection (the KTop constraint table) ──────────────────────

///|
/// Collect (result-path, constraints, entities) for the root scope and every
/// statically reachable nested scope: CmdSat children (path + [name], also
/// inside Or-bundled greedy entries), inline positional ScopeNodes and
/// scope-shaped repeat heads (transparent — same path, their bindings are
/// not nested). Scopes with no constraints are skipped (nothing to check).
///
/// Known limitation (documented, not enforced): a repeat-instantiated
/// transparent scope shares its path across reps, so its constraints see the
/// MERGED final state of all reps; per-rep predicate instances are not spec'd
/// (no DR defines them). IdxRepeat's indexed paths ("#k") are out of scope.
fn collect_scopes(root : Node, defs : Map[String, Node]) -> Array[ScopedCons] {
  let out : Array[ScopedCons] = []
  match root {
    ScopeNode(sc) => collect_scope_into(sc, [], defs, out, [])
    _ => ()
  }
  out
}

///|
fn collect_scope_into(
  sc : Scope,
  path : Array[String],
  defs : Map[String, Node],
  out : Array[ScopedCons],
  seen_refs : Array[String],
) -> Unit {
  if sc.constraints.length() > 0 {
    out.push({ path, constraints: sc.constraints, entities: sc.entities })
  }
  for g in sc.greedy {
    collect_greedy_scopes(g, path, defs, out, seen_refs)
  }
  for p in sc.positional {
    collect_pos_scopes(p, path, defs, out, seen_refs)
  }
}

///|
fn collect_greedy_scopes(
  g : Node,
  path : Array[String],
  defs : Map[String, Node],
  out : Array[ScopedCons],
  seen_refs : Array[String],
) -> Unit {
  match g {
    CmdSat(name, child) => {
      let p2 : Array[String] = []
      for s in path {
        p2.push(s)
      }
      p2.push(name)
      collect_scope_into(child, p2, defs, out, seen_refs)
    }
    Or(alts) =>
      for a in alts {
        collect_greedy_scopes(a, path, defs, out, seen_refs)
      }
    Rooted(inner, _) => collect_greedy_scopes(inner, path, defs, out, seen_refs)
    _ => ()
  }
}

///|
fn collect_pos_scopes(
  n : Node,
  path : Array[String],
  defs : Map[String, Node],
  out : Array[ScopedCons],
  seen_refs : Array[String],
) -> Unit {
  match n {
    ScopeNode(child) => collect_scope_into(child, path, defs, out, seen_refs)
    Ref(name) =>
      if !str_mem(seen_refs, name) {
        let seen2 : Array[String] = []
        for s in seen_refs {
          seen2.push(s)
        }
        seen2.push(name)
        match ref_head(defs, name) {
          ScopeNode(child) => collect_scope_into(child, path, defs, out, seen2)
          _ => ()
        }
      }
    BoundedTail(head, _, _) =>
      match head {
        ScopeNode(child) =>
          collect_scope_into(child, path, defs, out, seen_refs)
        _ => ()
      }
    Many(inner) => collect_pos_scopes(inner, path, defs, out, seen_refs)
    _ => ()
  }
}

// ── top level (spec DR-038 path counting) ────────────────────────────────────

///|
/// Parse `toks` against `root`, counting DISTINCT complete paths.
///
/// Path identity is the observable effect sequence on entities (spec DR-038),
/// entry-independent: comparing the `Array[Binding]` by structural equality
/// IS this identity.
///
/// Branch policy (MDR-002 §2.3): a `Pending` whose candidates include a VALUE
/// slot means "a trigger was consumed but its value never arrived" — treated
/// like a Held with a missing-operand Error, so what the slice silently
/// dropped is now a visible failure reason. A Pending with only exact
/// (trigger-spelling) candidates is completion material, not an error.
pub fn parse(
  root : Node,
  toks : Array[String],
  defs? : Map[String, Node] = Map([]),
  faildef? : FailDef = WithHeld,
) -> Outcome {
  let branches = match root {
    ScopeNode(sc) =>
      scope_step(
        sc,
        toks,
        0,
        0,
        [],
        false,
        defs,
        KTop(collect_scopes(root, defs)),
      )
    _ => eval(root, toks, 0, defs)
  }
  let full : Array[Array[Binding]] = []
  let errors : Array[ParseError] = []
  // the deepest argv position any branch reached (DeepestOnly candidate set).
  let mut max_reach = -1
  for b in branches {
    match b {
      Accept(p, _) => if p > max_reach { max_reach = p }
      Held(pe, _) => if pe.argv_pos > max_reach { max_reach = pe.argv_pos }
      Pending(_, _) =>
        // a Pending consumed every token it saw (input exhausted).
        if toks.length() > max_reach {
          max_reach = toks.length()
        }
    }
  }
  let actions : Array[(String, Int)] = []
  for b in branches {
    match b {
      Accept(p, bs) => {
        // constraint satisfaction is already decided at KTop (a violating
        // full consumption arrives as Helds, never an Accept), so every
        // full-length Accept here IS a complete解決経路.
        if p == toks.length() {
          let eff = strip_link(bs)
          let mut dup = false
          for existing in full {
            if existing == eff {
              dup = true
              break
            }
          }
          if !dup {
            full.push(eff)
          }
        }
        let counts = match faildef {
          DeepestOnly => p == max_reach
          _ => true
        }
        if counts {
          collect_actions(bs, actions)
        }
      }
      Held(pe, bs) => {
        push_error(errors, pe)
        let counts = match faildef {
          AcceptsOnly => false
          WithHeld => true
          DeepestOnly => pe.argv_pos == max_reach
        }
        if counts {
          collect_actions(bs, actions)
        }
      }
      Pending(cands, bs) => {
        // MDR-002 §2.3: a starved value slot is an error the slice used to
        // swallow. One missing-operand Error per value candidate origin.
        for c in cands {
          if c.is_value {
            push_error(errors, pe_missing(c.origin, toks.length()))
          }
        }
        let counts = match faildef {
          AcceptsOnly => false
          WithHeld => true
          DeepestOnly => toks.length() == max_reach
        }
        if counts {
          collect_actions(bs, actions)
        }
      }
    }
  }
  let help = find_help_entry(root)
  // Residual-token synthesis for NON-scope roots (a ScopeNode root surfaces
  // residual tokens as KTop Helds already): a partial Accept (p < length)
  // on a 0-complete-path parse is a residual failure in its own right, and
  // must surface EVEN IF other branches contributed held Errors — gating on
  // "errors empty" would silently mask the deepest partial reading's stumble
  // (DR-053 §2 全保持; adversarial review finding). Deduped like any error.
  if full.length() == 0 {
    let mut max_partial = -1
    for b in branches {
      match b {
        Accept(p, _) =>
          if p < toks.length() && p > max_partial {
            max_partial = p
          }
        _ => ()
      }
    }
    if max_partial >= 0 {
      push_error(errors, {
        element: "",
        argv_pos: max_partial,
        kind: KParse,
        reason: "unexpected_token",
        message: "unexpected token",
      })
    }
  }
  // Residual collapse: KTop emits one scope-level unexpected_token PER
  // dead-end position, but the canonical errors set carries the residual
  // only at its DEEPEST head (spec fixture repeat-parse/max-finite pins
  // exactly one; the shallower stops of the same walk are the same stumble
  // observed earlier, not distinct failure reasons — element-attributed
  // errors are untouched, DR-053 §2 全保持 is about DISTINCT errors).
  let mut deepest_resid = -1
  for e in errors {
    if e.element == "" &&
      e.reason == "unexpected_token" &&
      e.argv_pos > deepest_resid {
      deepest_resid = e.argv_pos
    }
  }
  let errors2 : Array[ParseError] = []
  for e in errors {
    if e.element == "" &&
      e.reason == "unexpected_token" &&
      e.argv_pos < deepest_resid {
      continue
    }
    errors2.push(e)
  }
  let errors = errors2
  match full.length() {
    0 =>
      Failure({
        errors,
        fired_action: if actions.length() > 0 {
          Some(argmin_action(actions))
        } else {
          None
        },
        help_entry: help,
        tried_triggers: tried_triggers_of(root),
      })
    1 => Success(full[0])
    _ => Ambiguous({ interpretations: full, help_entry: help })
  }
}

///|
/// Push a ParseError deduped by structural equality (spec DR-053 §2 全保持).
fn push_error(errors : Array[ParseError], pe : ParseError) -> Unit {
  for e in errors {
    if e == pe {
      return
    }
  }
  errors.push(pe)
}
