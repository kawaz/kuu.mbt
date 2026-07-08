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
/// The evaluator's ambient context, threaded through the whole walk.
/// Bundles what every walk function needs but never mutates: the token
/// stream, the template registry (DR-020/043), and the evaluation mode
/// (parse vs complete — the collection-policy switch MDR-002's TODO
/// anticipates). A future completes-memoization table also lives here.
priv struct Ctx {
  toks : Array[String]
  defs : Map[String, Node]
  mode : EvalMode
}

///|
/// parse counts complete paths (DR-038); complete collects expectations
/// (DR-060). The walk is ONE implementation — mode switches the
/// collection-policy points below (MDR-002 §2.4):
/// - boundary trigger sites (Exact / CmdSat / DdSat / NativeMatch at argv
///   end) emit `Pending` exact candidates instead of a silent Reject;
/// - spine value primitives starved at argv end emit `Pending` value
///   candidates instead of a missing-operand Held;
/// - 取り分選好 pruning is off (a losing share's Pending is still material).
priv enum EvalMode {
  ModeParse
  ModeComplete
} derive(Eq)

///|
fn in_complete(ctx : Ctx) -> Bool {
  ctx.mode == ModeComplete
}

///|
/// An exact-spelling candidate (the Pending payload at a trigger boundary,
/// DR-060 §3). `ty` is only meaningful when a value must follow the spelling
/// (term = Cont, e.g. an eq-split `--key`); a plain trigger carries TFlag.
fn cand_trigger(
  spelling : String,
  origin : String,
  ty : Ty,
  term : TermHint,
  deprecated : Bool,
) -> Cand {
  {
    spelling,
    is_value: false,
    ty,
    origin,
    term,
    meta: { is_alias: false, hidden: false, deprecated },
    path: [], // DR-066 §4: prepended by scope boundaries on the way out (nest_branches / CmdSat)
  }
}

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
/// Prepend `label` onto a held Error's `path` (DR-066 §4 snoc form, root-first
/// ancestor list). Mirrors `nest`'s scope-prepend on Binding, but for the
/// error's path instead of a binding's scope — the two are threaded through
/// the same scope-boundary crossings (Scoped / CmdSat) so a path built this
/// way lines up with the equivalent Binding.scope.
fn nest_path(label : String, path : Array[String]) -> Array[String] {
  let out : Array[String] = [label]
  for s in path {
    out.push(s)
  }
  out
}

///|
/// Prepend `label` onto every candidate's `path` in a Pending's candidate array (DR-066 §4, issue
/// 2026-07-08 pending-starvation-missing-operand-path). Mirrors `nest_path`'s Held prepend — a
/// Pending's value-slot candidate is parse mode's OTHER failure carrier (converted to a
/// `missing_operand` ParseError at parse()'s top level, DR-053 §2.3), so it needs the same ancestor
/// tracking Held already had, or the resulting Error's path is silently stuck at `[]`.
fn nest_cands(label : String, cs : Array[Cand]) -> Array[Cand] {
  let out : Array[Cand] = []
  for c in cs {
    out.push({ ..c, path: nest_path(label, c.path) })
  }
  out
}

///|
/// Apply `nest` to every Accept branch's bindings (Held / Pending pass
/// through unchanged on the binding side: their partial state is
/// failure/completion material, not a result object, so nesting is not
/// needed for it). A Held's ParseError.path and a Pending's candidate `path`s
/// DO get the same prepend (DR-066 §4): as the branch rides back out through
/// the scope this label declares, `label` becomes its innermost recorded
/// ancestor.
fn nest_branches(label : String, brs : Array[Branch]) -> Array[Branch] {
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Accept(p, bs) => out.push(Accept(p, nest(label, bs)))
      Held(pe, bs) =>
        out.push(Held({ ..pe, path: nest_path(label, pe.path) }, bs))
      Pending(cs, bs) => out.push(Pending(nest_cands(label, cs), bs))
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
    path: [], // DR-066 §4: prepended by scope boundaries on the way out (nest_branches / CmdSat)
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
fn eval(node : Node, ctx : Ctx, pos : Int) -> Array[Branch] {
  match node {
    Exact(s) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == s {
        [Accept(pos + 1, [])]
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        // complete (DR-060 §1): the argv boundary at a trigger position means
        // this spelling is exactly what could be typed next.
        [Pending([cand_trigger(s, s, TFlag, WordEnd, false)], [])]
      } else {
        // an unmatched (or, in parse mode, exhausted) trigger is a silent
        // Reject (spec DR-037), NOT a Pending: no part of the entry was
        // consumed, so nothing is "half-read".
        []
      }
    StrArg(name) =>
      if pos < ctx.toks.length() {
        [Accept(pos + 1, [mkb(name, VStr(ctx.toks[pos]), Cli)])]
      } else {
        // MDR-002 §2.1: the end of input at a value slot is an explicit
        // Pending, not a silent []. Reached mid-greedy-entry (after the
        // trigger consumed) this is the "--port with no value" state.
        [Pending([pend_value(TStr, name)], [])]
      }
    SepArg(name, sep) =>
      if pos < ctx.toks.length() {
        [Accept(pos + 1, sep_binds(name, ctx.toks[pos], sep))]
      } else {
        [Pending([pend_value(TStr, name)], [])]
      }
    NumArg(name, base) =>
      // DR-074 §1 + §2: canonical (base=false) は 10 進のみ、opt-in (base=true) で 0x/0o/0b + hex float
      // も受理。base は installer が ElemDef.allow_base_prefix から埋め込む。
      if pos < ctx.toks.length() {
        match parse_number_ext(ctx.toks[pos], base) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, ctx.toks[pos], pos), [])]
        }
      } else {
        [Pending([pend_value(TNum, name)], [])]
      }
    FloatArg(name) =>
      // DR-074 §1: the float accept域 = number + inf (parse_float), same reason vocab (not_a_number)
      // on failure as NumArg — only the parser function differs.
      if pos < ctx.toks.length() {
        match parse_float(ctx.toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, ctx.toks[pos], pos), [])]
        }
      } else {
        [Pending([pend_value(TFloat, name)], [])]
      }
    IntArg(name, mode, base) =>
      // DR-075 §1-§2 + DR-074 §2: 値空間判定 + int_round + opt-in base prefix。base=false で 10 進のみ、
      // true で 0xff (整数値) / 0x1.8p3 (=12 整数値) / 0x1.8p0 (=1.5 非整数、mode に従う) も受理する。
      if pos < ctx.toks.length() {
        match parse_int_value_ext(ctx.toks[pos], mode, base) {
          Ok(i) => [Accept(pos + 1, [mkb(name, VNum(i.to_double()), Cli)])]
          Err(NotAnInteger) =>
            [Held(pe_parse_int(name, ctx.toks[pos], pos), [])]
          Err(IntOutOfRange) =>
            [Held(pe_int_out_of_range(name, ctx.toks[pos], pos), [])]
          Err(NotANumber) => [Held(pe_parse(name, ctx.toks[pos], pos), [])]
        }
      } else {
        [Pending([pend_value(TInt, name)], [])]
      }
    BoolArg(name) =>
      // DR-076 §1/§4: bool value slot (canonical vocab, DR-074 §3) — mirrors NumArg/FloatArg/IntArg.
      if pos < ctx.toks.length() {
        match parse_bool(ctx.toks[pos]) {
          Some(b) => [Accept(pos + 1, [mkb(name, VBool(b), Cli)])]
          None => [Held(pe_parse_bool(name, ctx.toks[pos], pos), [])]
        }
      } else {
        [Pending([pend_value(TBool, name)], [])]
      }
    FilterArg(name, max) => filter_arg_eval(name, max, ctx, pos, [])
    ReqArg(name) => req_arg_eval(name, ctx, pos, [])
    Bind(name, v) => [Accept(pos, [mkb(name, v, Cli)])]
    EffMark(name, op) => [Accept(pos, [mk_eff(name, op, Cli)])]
    FailMark(name) => [Accept(pos, [action_marker(name, pos)])]
    DeprMark(name) => [Accept(pos, [depr_marker(name)])]
    Or(alts) => {
      let out : Array[Branch] = []
      for a in alts {
        for b in eval(a, ctx, pos) {
          out.push(b)
        }
      }
      out
    }
    Seq(items) => eval_seq(items, 0, ctx, pos, [])
    // off-spine Many (embedded in Or/Seq rather than a positional spine slot,
    // MDR-002 §CPS 規約: lowering never generates this shape today) has no
    // 取り分選好 to apply here — `eval_many` already returns every share
    // unfiltered, so the lazy knob has nothing to invert. Ignored, not lost:
    // the spine form (scope_consume's `Many` arm below) is where lazy_ acts.
    Many(inner, _) => eval_many(inner, ctx, pos, [])
    Scoped(label, body) => nest_branches(label, eval(body, ctx, pos))
    ScopeNode(sc) =>
      // off-spine scope: accept wherever the scope ends (KDone), mirroring
      // the slice's eval_scope. The SPINE path (scope_consume) instead
      // threads the real continuation.
      scope_step(sc, ctx, pos, 0, [], false, KDone)
    NativeMatch(m) =>
      if pos >= ctx.toks.length() && in_complete(ctx) {
        // complete: the matcher's own spellings (eq-split keys, cluster
        // chars) are the readable-next set at the boundary (DR-060 §1).
        [Pending(matcher_cands(m), [])]
      } else {
        run_matcher(m, ctx, pos)
      }
    Ref(name) =>
      match ctx.defs.get(name) {
        Some(tpl) => eval(tpl, ctx, pos)
        None => []
      }
    DdSat(trigger) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == trigger {
        [Accept(pos + 1, [])]
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([cand_trigger(trigger, trigger, TFlag, WordEnd, false)], [])]
      } else {
        []
      }
    CmdSat(name, child) =>
      // off-spine command (a probe or a nested context): child evaluated with
      // KDone; bindings nest under the name + presence marker. The greedy
      // face path (step_greedy) threads the real continuation instead.
      if pos < ctx.toks.length() && ctx.toks[pos] == name {
        mark_scope(
          name,
          nest_branches(
            name,
            scope_step(child, ctx, pos + 1, 0, [], false, KDone),
          ),
        )
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([cand_trigger(name, name, TFlag, WordEnd, false)], [])]
      } else {
        []
      }
    Rooted(inner, depth) => {
      let out : Array[Branch] = []
      for b in eval(inner, ctx, pos) {
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
      if pos < ctx.toks.length() && !starts_dash(ctx.toks[pos]) {
        [Accept(pos + 1, [mkb(name, VStr(ctx.toks[pos]), Cli)])]
      } else {
        []
      }
    IdxRepeat(label, head, min) => idx_repeat_eval(label, head, min, ctx, pos)
    BoundedTail(head, budget, _) =>
      // off-spine fallback: degrade to the nested-Opt form (0..budget heads).
      eval(bounded_opt(head, budget), ctx, pos)
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
    path: [],
  }
}

///|
/// FilterArg: parse a number then apply a max post-filter. A parse failure is
/// `kind: parse`; a value above `max` is `kind: filter`.
fn filter_arg_eval(
  name : String,
  max : Int,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  if pos < ctx.toks.length() {
    match parse_number(ctx.toks[pos]) {
      Some(d) =>
        if d > max.to_double() {
          [
            Held(
              {
                element: name,
                argv_pos: pos,
                kind: KFilter,
                reason: "too_large",
                message: "\{name} value \{ctx.toks[pos]} exceeds max \{max}",
                path: [],
              },
              acc,
            ),
          ]
        } else {
          [Accept(pos + 1, cat(acc, [mkb(name, VNum(d), Cli)]))]
        }
      None => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
    }
  } else if in_complete(ctx) {
    [Pending([pend_value(TNum, name)], acc)]
  } else {
    [Held(pe_missing(name, pos), acc)]
  }
}

///|
/// ReqArg (spec DR-047 / DR-053 kind: constraint): NO token to consume is a
/// `kind: constraint` held Error, not a silent Reject.
fn req_arg_eval(
  name : String,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  if pos < ctx.toks.length() {
    [Accept(pos + 1, cat(acc, [mkb(name, VStr(ctx.toks[pos]), Cli)]))]
  } else if in_complete(ctx) {
    [Pending([pend_value(TStr, name)], acc)]
  } else {
    [
      Held(
        {
          element: name,
          argv_pos: pos,
          kind: KConstraint,
          reason: "required_violated",
          message: "required \{name} is missing",
          path: [],
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
  ctx : Ctx,
  pos : Int,
) -> Array[Branch] {
  let acc : Array[Binding] = [array_marker(label)]
  let mut cur = pos
  let mut rep = 0
  let mut go = true
  while go {
    let p2 = idx_one(head, label, rep, ctx, cur, acc)
    if p2 > cur {
      cur = p2
      rep = rep + 1
    } else {
      go = false
    }
  }
  if rep < min {
    if in_complete(ctx) {
      // complete: the mandatory next rep starved (or its trigger sits at the
      // boundary) — surface the head's Pending candidates instead of the
      // parse-mode silent Reject.
      idx_head_pendings(head, ctx, cur, acc)
    } else {
      []
    }
  } else {
    let out : Array[Branch] = [Accept(cur, acc)]
    if in_complete(ctx) {
      // complete: min is met but one MORE rep is still typable — union in
      // the head's boundary candidates (DR-060 §1 全生存 partial の和集合).
      for b in idx_head_pendings(head, ctx, cur, acc) {
        out.push(b)
      }
    }
    out
  }
}

///|
/// The head's Pending branches at `pos` with the reps consumed so far as
/// partial state. A mismatch (no Pending) contributes nothing — only the
/// boundary starvation does.
fn idx_head_pendings(
  head : Node,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  let out : Array[Branch] = []
  for b in eval(head, ctx, pos) {
    match b {
      Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
      _ => ()
    }
  }
  out
}

///|
fn idx_one(
  head : Node,
  label : String,
  rep : Int,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Int {
  for b in eval(head, ctx, pos) {
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
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  if idx >= items.length() {
    return [Accept(pos, acc)]
  }
  let out : Array[Branch] = []
  for b in eval(items[idx], ctx, pos) {
    match b {
      Accept(p2, bs) =>
        for r in eval_seq(items, idx + 1, ctx, p2, cat(acc, bs)) {
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
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  let out : Array[Branch] = [Accept(pos, acc)] // 0 reps
  for b in eval(inner, ctx, pos) {
    match b {
      Accept(p2, bs) =>
        if p2 > pos {
          for r in eval_many(inner, ctx, p2, cat(acc, bs)) {
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
fn greedy_engages(g : Node, ctx : Ctx, pos : Int) -> Bool {
  match g {
    Seq(items) =>
      if items.length() >= 1 {
        match items[0] {
          Exact(s) => ctx.toks[pos] == s
          NativeMatch(m) => run_matcher(m, ctx, pos).length() > 0
          _ => eval_consumes(g, ctx, pos)
        }
      } else {
        false
      }
    Or(alts) => {
      for a in alts {
        if greedy_engages(a, ctx, pos) {
          return true
        }
      }
      false
    }
    CmdSat(name, _) => ctx.toks[pos] == name
    DdSat(t) => ctx.toks[pos] == t
    // a matcher engages iff it yields ANY reading or held Error ([] = 素通し,
    // e.g. an undefined --key= or a non-prefix token).
    NativeMatch(m) => run_matcher(m, ctx, pos).length() > 0
    Rooted(inner, _) => greedy_engages(inner, ctx, pos)
    _ => eval_consumes(g, ctx, pos)
  }
}

///|
/// Consumption-based fallback probe for trigger-less greedy shapes: reads iff
/// some branch consumes a token (or a Pending shows a trigger was consumed).
fn eval_consumes(g : Node, ctx : Ctx, pos : Int) -> Bool {
  for b in eval(g, ctx, pos) {
    match b {
      Accept(p2, _) => if p2 > pos { return true }
      Held(_, _) => ()
      Pending(_, _) => return true
    }
  }
  false
}

///|
fn greedy_reads(sc : Scope, ctx : Ctx, pos : Int) -> Bool {
  if pos >= ctx.toks.length() {
    return false // no token to read (早閉じ check at the end of input)
  }
  for g in sc.greedy {
    if greedy_engages(g, ctx, pos) {
      return true
    }
  }
  false
}

///|
/// Whether raw pass-through of the token at `pos` is suppressed. 先食い is
/// greedy-ONLY (spec DR-041 §4): a raw-eat is suppressed iff some greedy
/// entry reads the token. Once severed, nothing is suppressed.
fn suppressed(sc : Scope, ctx : Ctx, pos : Int, severed : Bool) -> Bool {
  if severed {
    return false
  }
  greedy_reads(sc, ctx, pos)
}

///|
/// Walk sc.positional[pidx..] from `pos` with continuation `k`. Offers (A) a
/// greedy interjection (only when not severed) and (B) advancing the
/// positional face; a finished face RUNS `k` (subject to 早閉じ抑制).
fn scope_step(
  sc : Scope,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  k : Cont,
) -> Array[Branch] {
  let out : Array[Branch] = []
  // (A) greedy interjection — re-enter at the same pidx (positional face
  // untouched). CmdSat / DdSat are dispatched structurally so their child
  // walk gets the REAL continuation (this is where phase16 is won: the
  // child's repeats must see that the parent still wants a token).
  if !severed {
    for g in sc.greedy {
      step_greedy(g, sc, ctx, pos, pidx, acc, severed, k, out)
    }
  }
  // (B) advance the positional face
  if pidx >= sc.positional.length() {
    // 早閉じ抑制 (spec DR-041 §4): a scope with a backbone cannot complete
    // while one of its own greedy entries can read the next token — "that
    // which can be read here, is read here".
    if severed || !greedy_reads(sc, ctx, pos) {
      for r in run_cont(k, ctx, pos, acc) {
        out.push(r)
      }
    }
  } else {
    for
      r in scope_consume(
        sc,
        sc.positional[pidx],
        ctx,
        pos,
        pidx,
        acc,
        severed,
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
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  k : Cont,
  out : Array[Branch],
) -> Unit {
  match g {
    CmdSat(name, child) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == name {
        let kk = KNest(
          name,
          true,
          acc.length(),
          KResumeScope(sc, pidx, severed, k),
        )
        // DR-066 §4: every Held riding out of the child scope crosses this
        // command boundary exactly once — whether it fired INSIDE the child
        // (a bare Held straight from `eval`, path still []) or arrived at
        // KTop after the child's own KNest completed (path already carries
        // deeper ancestors). Either way, `name` belongs on the front: this
        // is the boundary the child scope's `name` declares. A Pending's
        // candidate paths get the SAME prepend (issue 2026-07-08
        // pending-starvation-missing-operand-path) — a starved value slot is
        // parse mode's other failure carrier (DR-053 §2.3), so its eventual
        // missing_operand ParseError needs the same ancestor tracking.
        for r in scope_step(child, ctx, pos + 1, 0, acc, false, kk) {
          match r {
            Held(pe, bs) =>
              out.push(Held({ ..pe, path: nest_path(name, pe.path) }, bs))
            Pending(cs, bs) => out.push(Pending(nest_cands(name, cs), bs))
            _ => out.push(r)
          }
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        // complete: the command name is readable at the boundary (DR-060 §1).
        out.push(
          Pending([cand_trigger(name, name, TFlag, WordEnd, false)], acc),
        )
      }
    DdSat(trigger) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == trigger {
        for r in scope_step(sc, ctx, pos + 1, pidx, acc, true, k) {
          out.push(r)
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        out.push(
          Pending([cand_trigger(trigger, trigger, TFlag, WordEnd, false)], acc),
        )
      }
    Or(alts) =>
      for a in alts {
        step_greedy(a, sc, ctx, pos, pidx, acc, severed, k, out)
      }
    _ =>
      for b in eval(g, ctx, pos) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              for r in scope_step(sc, ctx, p2, pidx, cat(acc, bs), severed, k) {
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
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  k : Cont,
) -> Array[Branch] {
  match item {
    StrArg(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        scope_step(
          sc,
          ctx,
          pos + 1,
          pidx + 1,
          cat(acc, [mkb(name, VStr(ctx.toks[pos]), Cli)]),
          severed,
          k,
        )
      } else if pos >= ctx.toks.length() {
        // 構造的必須の不成立 (spec DR-065 §3): the spine needs a token for
        // `name` but the argv is exhausted. Held, not a silent Reject; in
        // complete mode the same boundary is the positional expectation
        // (DR-060 §1「positional 面の次の期待ノード」).
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        [] // 先食い: a greedy trigger sits here; the spine stays pending
      }
    SepArg(name, sep) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        scope_step(
          sc,
          ctx,
          pos + 1,
          pidx + 1,
          cat(acc, sep_binds(name, ctx.toks[pos], sep)),
          severed,
          k,
        )
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    NumArg(name, base) =>
      // DR-074 §1 + §2 (scope_step 経路: parse_number_ext with base flag)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_number_ext(ctx.toks[pos], base) {
          Some(d) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx + 1,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              k,
            )
          None => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TNum, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    FloatArg(name) =>
      // DR-074 §1 CLI 値空間 (scope_step 経路: NumArg のミラー、parse_number→parse_float / TNum→TFloat)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_float(ctx.toks[pos]) {
          Some(d) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx + 1,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              k,
            )
          None => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TFloat, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    IntArg(name, mode, base) =>
      // DR-075 §1-§2 + DR-074 §2 CLI 値空間判定 + int_round + base prefix (scope_step 経路)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_int_value_ext(ctx.toks[pos], mode, base) {
          Ok(i) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx + 1,
              cat(acc, [mkb(name, VNum(i.to_double()), Cli)]),
              severed,
              k,
            )
          Err(NotAnInteger) =>
            [Held(pe_parse_int(name, ctx.toks[pos], pos), acc)]
          Err(IntOutOfRange) =>
            [Held(pe_int_out_of_range(name, ctx.toks[pos], pos), acc)]
          Err(NotANumber) => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TInt, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    BoolArg(name) =>
      // DR-076 §1/§4 CLI 値空間 (scope_step 経路: NumArg/IntArg/FloatArg のミラー)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_bool(ctx.toks[pos]) {
          Some(b) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx + 1,
              cat(acc, [mkb(name, VBool(b), Cli)]),
              severed,
              k,
            )
          None => [Held(pe_parse_bool(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TBool, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    FilterArg(name, max) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_number(ctx.toks[pos]) {
          Some(d) =>
            if d > max.to_double() {
              [
                Held(
                  {
                    element: name,
                    argv_pos: pos,
                    kind: KFilter,
                    reason: "too_large",
                    message: "\{name} value \{ctx.toks[pos]} exceeds max \{max}",
                    path: [],
                  },
                  acc,
                ),
              ]
            } else {
              scope_step(
                sc,
                ctx,
                pos + 1,
                pidx + 1,
                cat(acc, [mkb(name, VNum(d), Cli)]),
                severed,
                k,
              )
            }
          None => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TNum, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    ReqArg(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        scope_step(
          sc,
          ctx,
          pos + 1,
          pidx + 1,
          cat(acc, [mkb(name, VStr(ctx.toks[pos]), Cli)]),
          severed,
          k,
        )
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], acc)]
        } else {
          [
            Held(
              {
                element: name,
                argv_pos: pos,
                kind: KConstraint,
                reason: "required_violated",
                message: "required \{name} is missing",
                path: [],
              },
              acc,
            ),
          ]
        }
      } else {
        []
      }
    Exact(s) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == s {
        scope_step(sc, ctx, pos + 1, pidx + 1, acc, severed, k)
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([cand_trigger(s, s, TFlag, WordEnd, false)], acc)]
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
      match ref_head(ctx.defs, name) {
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
            ctx,
            pos,
            0,
            acc,
            severed,
            KRefChoice(sc, name, pidx, severed, pos, k),
          )
        head => {
          let out : Array[Branch] = []
          for b in consume_head(sc, head, ctx, pos, severed) {
            match b {
              Accept(p2, bs) =>
                if p2 > pos {
                  for
                    r in ref_choice(
                      sc,
                      name,
                      ctx,
                      p2,
                      pidx,
                      cat(acc, bs),
                      severed,
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
        sc, head, budget, lazy_, ctx, pos, pidx, acc, severed, k,
      )
    Many(inner, lazy_) => {
      // Two closures on the spine — parity with Ref/BoundedTail 取り分選好
      // (spec DR-043). Without preference, `[Many(xs), Many(ys)]` on ["a","b"]
      // returns Ambiguous (3-way split) even though the greedy default fixes
      // xs=[a,b], ys=[] as the representative. `lazy_` (issue 2026-07-08
      // min0-lazy-repeat-gap) inverts which share wins EXACTLY the way
      // `bounded_tail_step` does below — same two closures, same tie-break
      // order flip, just no budget countdown (unbounded).
      let stop = scope_step(sc, ctx, pos, pidx + 1, acc, severed, k) // 0 reps
      let more = scope_consume_rep(sc, inner, ctx, pos, pidx, acc, severed, k) // 1 rep (which re-enters scope_step at same pidx)
      if in_complete(ctx) {
        // complete: no pruning — the losing share's Pending is candidate
        // material too (MDR-002 §2.4: union over ALL surviving partials).
        cat_branches(stop, more)
      } else if lazy_ {
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
    ScopeNode(child) =>
      // spec DR-042 ⑤: a child scope runs its own walk (the parent greedy
      // face does not interject during it). `severed` DOES pass through — dd
      // severs the greedy face for the whole rest of the spine, including
      // inline child scopes reached through the positional face (DR-041
      // dashdash: continuation is raw). The parent-resume continuation still
      // remembers the outer severed independently.
      scope_step(
        child,
        ctx,
        pos,
        0,
        acc,
        severed,
        KResumeScope(sc, pidx + 1, severed, k),
      )
    other => {
      // any other node as a positional item: eval plainly, then continue.
      let out : Array[Branch] = []
      for b in eval(other, ctx, pos) {
        match b {
          Accept(p2, bs) =>
            for r in scope_step(sc, ctx, p2, pidx + 1, cat(acc, bs), severed, k) {
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
  ctx : Ctx,
  p2 : Int,
  pidx : Int,
  acc2 : Array[Binding],
  severed : Bool,
  k : Cont,
) -> Array[Branch] {
  let head = ref_head(ctx.defs, name)
  let lazy_ = ref_is_lazy(ctx.defs, name)
  let stop = scope_step(sc, ctx, p2, pidx + 1, acc2, severed, k)
  // "more" = one more OPTIONAL rep; a missing-operand for ANY value
  // primitive reachable inside the repeat head (scope-shaped included) is a
  // legitimate stop, not a failure. head-external missing (a downstream
  // primitive fed by the parent continuation) stays.
  let more = drop_optional_missing(
    scope_step(sc, ctx, p2, pidx, acc2, severed, k),
    head_elem_names(head),
  )
  if in_complete(ctx) {
    // complete: no pruning (union over ALL surviving partials, MDR-002 §2.4).
    cat_branches(stop, more)
  } else if lazy_ {
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
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  k : Cont,
) -> Array[Branch] {
  let stop = scope_step(sc, ctx, pos, pidx + 1, acc, severed, k)
  let more_raw : Array[Branch] = if budget >= 1 {
    match head {
      // scope-shaped head: same KDone hazard as the Ref path (REVIEW-H1) —
      // the head's walk carries the tail's choice point as its continuation.
      ScopeNode(child) =>
        // same dd sever pass-through as the scope_consume ScopeNode arms.
        scope_step(
          child,
          ctx,
          pos,
          0,
          acc,
          severed,
          KTailChoice(sc, head, budget - 1, lazy_, pidx, severed, pos, k),
        )
      _ => {
        let out : Array[Branch] = []
        for b in consume_head(sc, head, ctx, pos, severed) {
          match b {
            Accept(p2, bs) =>
              if p2 > pos {
                for
                  r in bounded_tail_step(
                    sc,
                    head,
                    budget - 1,
                    lazy_,
                    ctx,
                    p2,
                    pidx,
                    cat(acc, bs),
                    severed,
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
  if in_complete(ctx) {
    cat_branches(stop, more)
  } else if lazy_ {
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
  ctx : Ctx,
  pos : Int,
  severed : Bool,
) -> Array[Branch] {
  match head {
    StrArg(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        [Accept(pos + 1, [mkb(name, VStr(ctx.toks[pos]), Cli)])]
      } else if pos >= ctx.toks.length() {
        // in complete mode the starved head is a repeat-continuation value
        // candidate (DR-060 §1), not a missing-operand Held.
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    SepArg(name, sep) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        [Accept(pos + 1, sep_binds(name, ctx.toks[pos], sep))]
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    NumArg(name, base) =>
      // DR-074 §1 + §2 (先食い分岐: parse_number_ext with base flag)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_number_ext(ctx.toks[pos], base) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, ctx.toks[pos], pos), [])]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TNum, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    FloatArg(name) =>
      // DR-074 §1 CLI 値空間 (先食い分岐: NumArg のミラー、parse_number→parse_float / TNum→TFloat)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_float(ctx.toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, ctx.toks[pos], pos), [])]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TFloat, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    IntArg(name, mode, base) =>
      // DR-075 §1-§2 + DR-074 §2 (先食い分岐)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_int_value_ext(ctx.toks[pos], mode, base) {
          Ok(i) => [Accept(pos + 1, [mkb(name, VNum(i.to_double()), Cli)])]
          Err(NotAnInteger) =>
            [Held(pe_parse_int(name, ctx.toks[pos], pos), [])]
          Err(IntOutOfRange) =>
            [Held(pe_int_out_of_range(name, ctx.toks[pos], pos), [])]
          Err(NotANumber) => [Held(pe_parse(name, ctx.toks[pos], pos), [])]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TInt, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    BoolArg(name) =>
      // DR-076 §1/§4 CLI 値空間 (先食い分岐: NumArg/IntArg/FloatArg のミラー)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_bool(ctx.toks[pos]) {
          Some(b) => [Accept(pos + 1, [mkb(name, VBool(b), Cli)])]
          None => [Held(pe_parse_bool(name, ctx.toks[pos], pos), [])]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TBool, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    // ReqArg / FilterArg get their own arms so 先食い (suppressed) applies —
    // eval() does not see the parent scope, so falling through would let a
    // greedy trigger token be raw-eaten as the repeat head's value. Held
    // shapes must match the primitive arms above so drop_optional_missing on
    // the OPTIONAL "more" branch can filter them uniformly.
    ReqArg(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        [Accept(pos + 1, [mkb(name, VStr(ctx.toks[pos]), Cli)])]
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], [])]
        } else {
          [
            Held(
              {
                element: name,
                argv_pos: pos,
                kind: KConstraint,
                reason: "required_violated",
                message: "required \{name} is missing",
                path: [],
              },
              [],
            ),
          ]
        }
      } else {
        []
      }
    FilterArg(name, max) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_number(ctx.toks[pos]) {
          Some(d) =>
            if d > max.to_double() {
              [
                Held(
                  {
                    element: name,
                    argv_pos: pos,
                    kind: KFilter,
                    reason: "too_large",
                    message: "\{name} value \{ctx.toks[pos]} exceeds max \{max}",
                    path: [],
                  },
                  [],
                ),
              ]
            } else {
              [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
            }
          None => [Held(pe_parse(name, ctx.toks[pos], pos), [])]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TNum, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    _ => eval(head, ctx, pos)
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
    NumArg(name, _) => if !str_mem(out, name) { out.push(name) }
    FloatArg(name) => if !str_mem(out, name) { out.push(name) }
    IntArg(name, _, _) => if !str_mem(out, name) { out.push(name) }
    BoolArg(name) => if !str_mem(out, name) { out.push(name) }
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
    Many(inner, _) => head_elem_names_into(inner, out)
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
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  k : Cont,
) -> Array[Branch] {
  match inner {
    StrArg(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        scope_step(
          sc,
          ctx,
          pos + 1,
          pidx,
          cat(acc, [mkb(name, VStr(ctx.toks[pos]), Cli)]),
          severed,
          k,
        )
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        // complete: "one more Many rep" starved at the boundary is a value
        // candidate (DR-060 §1) — in parse it is a legitimate silent stop
        // (the 0-more branch already covers the walk).
        [Pending([pend_value(TStr, name)], acc)]
      } else {
        []
      }
    NumArg(name, base) =>
      // DR-074 §1 + §2 (Many head 経路: parse_number_ext with base flag)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_number_ext(ctx.toks[pos], base) {
          Some(d) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              k,
            )
          None => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TNum, name)], acc)]
      } else {
        []
      }
    FloatArg(name) =>
      // DR-074 §1 CLI 値空間 (Many head 経路: NumArg のミラー、parse_number→parse_float / TNum→TFloat)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_float(ctx.toks[pos]) {
          Some(d) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              k,
            )
          None => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TFloat, name)], acc)]
      } else {
        []
      }
    IntArg(name, mode, base) =>
      // DR-075 §1-§2 + DR-074 §2 (Many head 経路)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_int_value_ext(ctx.toks[pos], mode, base) {
          Ok(i) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx,
              cat(acc, [mkb(name, VNum(i.to_double()), Cli)]),
              severed,
              k,
            )
          Err(NotAnInteger) =>
            [Held(pe_parse_int(name, ctx.toks[pos], pos), acc)]
          Err(IntOutOfRange) =>
            [Held(pe_int_out_of_range(name, ctx.toks[pos], pos), acc)]
          Err(NotANumber) => [Held(pe_parse(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TInt, name)], acc)]
      } else {
        []
      }
    BoolArg(name) =>
      // DR-076 §1/§4 CLI 値空間 (Many head 経路: NumArg/IntArg/FloatArg のミラー)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match parse_bool(ctx.toks[pos]) {
          Some(b) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx,
              cat(acc, [mkb(name, VBool(b), Cli)]),
              severed,
              k,
            )
          None => [Held(pe_parse_bool(name, ctx.toks[pos], pos), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TBool, name)], acc)]
      } else {
        []
      }
    _ => {
      let out : Array[Branch] = []
      for b in eval(inner, ctx, pos) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              for r in scope_step(sc, ctx, p2, pidx, cat(acc, bs), severed, k) {
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
  // DR-066 §4: path starts empty here and is prepended by scope boundaries
  // (nest_branches / CmdSat) as the Held rides KTop's result back out through
  // the continuation chain — NOT `sc.path` (ScopedCons's path is the
  // scope_path_eq lookup key, reusing it here would double the prefix once
  // the same Held crosses those same boundaries on its way out).
  { element, argv_pos: pos, kind: KConstraint, reason, message, path: [] }
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
      CRequiresIf(entity, branch_id, v, targets) => {
        // DR-055 §1 + DR-052 §値枝 id 直交: committed 判定 / 値照合は親 entity (format) を対象に、
        // 違反時の error.element は branch_id (fmt_json = 制約の宣言元 = 値枝の id) を emit する。
        // branch_id は installer で id 未指定時に entity 名にフォールバックされているので、id なしの
        // parent 直属 value_requires は従来通り entity 名で attribution される。
        let active = is_committed(bindings, path, entity) &&
          (match elem_value(bindings, path, entity) {
            Some(x) => x == v
            None => false
          })
        if active {
          for t in targets {
            if !value_present(t, bindings, path, sc.entities) {
              out.push(
                constraint_err(
                  branch_id,
                  "requires_violated",
                  "'\{entity}'=\{v} requires '\{t}'",
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
    Many(inner, _) => collect_pos_scopes(inner, path, defs, out, seen_refs)
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
  let ctx : Ctx = { toks, defs, mode: ModeParse }
  let branches = match root {
    ScopeNode(sc) =>
      scope_step(sc, ctx, 0, 0, [], false, KTop(collect_scopes(root, defs)))
    _ => eval(root, ctx, 0)
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
        // DR-066 §4 (issue 2026-07-08 pending-starvation-missing-operand-path):
        // the candidate's own `path` (already prepended by scope boundaries
        // on its way out to this top-level branches array, same as a Held's
        // ParseError.path) overrides `pe_missing`'s default `[]` — this is
        // the ONE conversion point where a Pending becomes a ParseError, so
        // it is also the one place that needs to carry the path across.
        for c in cands {
          if c.is_value {
            push_error(errors, {
              ..pe_missing(c.origin, toks.length()),
              path: c.path,
            })
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
        path: [], // NON-scope root: no ancestor scope to record
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
        tried_triggers: tried_triggers_of(root, errors),
      })
    1 => Success(full[0])
    _ =>
      // DR-073: structurally-distinct full paths have no export-key collision (they differ by
      // parse structure, not by provenance for a shared exposed key), so claimants stays empty.
      // Export-key co-exposure collisions are surfaced by a separate post-parse promotion step
      // (resolve.mbt `promote_collision_ambiguous`) which fills in claimants per interpretation.
      Ambiguous({
        interpretations: {
          let a : Array[AmbInterp] = []
          for f in full {
            a.push({ binds: f, claimants: [] })
          }
          a
        },
        help_entry: help,
      })
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
