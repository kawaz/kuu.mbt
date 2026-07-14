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
/// DR-090 §2: whether `token` fires a `DdMatchSat` trigger — exact string equality
/// (`is_pattern=false`, same test `DdSat` itself uses) or a compiled-regex unanchored search
/// (`is_pattern=true`, `filters.mbt`'s `compile_regex`/`execute` — the SAME host-dialect compile
/// path DR-085's `regex_match` filter uses, per DR-090 §2 "照合方言は host 実装準拠"). A pattern
/// that fails to compile is treated as never-matching here (defensive — `installer.mbt`'s
/// `collect_invalid_dd_pattern` rejects an uncompilable `match` at definition time, so this arm
/// should not actually see one in practice).
fn dd_match_token(spelling : String, is_pattern : Bool, token : String) -> Bool {
  if is_pattern {
    match compile_regex(spelling) {
      Some(re) => re.execute(token) is Some(_)
      None => false
    }
  } else {
    token == spelling
  }
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
  { key, op, value: VBool(false), source, scope: [], link: 0, at_pos: None }
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
    at_pos: None,
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
      out.push({ ..b, scope: sc2 })
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
    at_pos: None,
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
    at_pos: None,
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
    StrArg(name, piece_filters) =>
      if pos < ctx.toks.length() {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            [Accept(pos + 1, [mkb(name, VStr(s), Cli, at_pos=Some(pos))])]
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
        }
      } else {
        // MDR-002 §2.1: the end of input at a value slot is an explicit
        // Pending, not a silent []. Reached mid-greedy-entry (after the
        // trigger consumed) this is the "--port with no value" state.
        [Pending([pend_value(TStr, name)], [])]
      }
    // DR-091 §2: kv_map's consume-time gate — same shape as StrArg (1 token, piece_filters, VStr
    // binding), plus one extra check AFTER piece_filters: the (filtered) token must contain `=`, or
    // this is a Held `kind: parse` error (`pe_parse_kv`, node.mbt's `KvArg` doc comment) — same
    // family as any other value primitive's type-parse failure, not a `KFilter` reject.
    KvArg(name, piece_filters) =>
      if pos < ctx.toks.length() {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            if contains_eq(s) {
              [Accept(pos + 1, [mkb(name, VStr(s), Cli, at_pos=Some(pos))])]
            } else {
              [Held(pe_parse_kv(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
        }
      } else {
        [Pending([pend_value(TStr, name)], [])]
      }
    SepArg(name, sep, ty, int_round, base, bool_config, piece_filters, merge) =>
      if pos < ctx.toks.length() {
        match
          sep_binds(
            name,
            ctx.toks[pos],
            sep,
            ty,
            int_round,
            base,
            bool_config,
            piece_filters,
            pos,
            merge,
          ) {
          Ok(bs) => [Accept(pos + 1, bs)]
          Err(pe) => [Held(pe, [])]
        }
      } else {
        [Pending([pend_value(ty, name)], [])]
      }
    NumArg(name, base, piece_filters) =>
      // DR-074 §1 + §2: canonical (base=false) は 10 進のみ、opt-in (base=true) で 0x/0o/0b + hex float
      // も受理。base は installer が ElemDef.allow_base_prefix から埋め込む。
      if pos < ctx.toks.length() {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_number_ext(s, base) {
              Some(d) =>
                [Accept(pos + 1, [mkb(name, VNum(d), Cli, at_pos=Some(pos))])]
              None => [Held(pe_parse(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
        }
      } else {
        [Pending([pend_value(TNum, name)], [])]
      }
    FloatArg(name, piece_filters) =>
      // DR-074 §1: the float accept域 = number + inf (parse_float), same reason vocab (not_a_number)
      // on failure as NumArg — only the parser function differs.
      if pos < ctx.toks.length() {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_float(s) {
              Some(d) =>
                [Accept(pos + 1, [mkb(name, VNum(d), Cli, at_pos=Some(pos))])]
              None => [Held(pe_parse(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
        }
      } else {
        [Pending([pend_value(TFloat, name)], [])]
      }
    IntArg(name, mode, base, piece_filters) =>
      // DR-075 §1-§2 + DR-074 §2: 値空間判定 + int_round + opt-in base prefix。base=false で 10 進のみ、
      // true で 0xff (整数値) / 0x1.8p3 (=12 整数値) / 0x1.8p0 (=1.5 非整数、mode に従う) も受理する。
      if pos < ctx.toks.length() {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_int_value_ext(s, mode, base) {
              Ok(i) =>
                [
                  Accept(pos + 1, [
                    mkb(name, VNum(i.to_double()), Cli, at_pos=Some(pos)),
                  ]),
                ]
              Err(NotAnInteger) => [Held(pe_parse_int(name, s, pos), [])]
              Err(IntOutOfRange) =>
                [Held(pe_int_out_of_range(name, s, pos), [])]
              Err(NotANumber) => [Held(pe_parse(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
        }
      } else {
        [Pending([pend_value(TInt, name)], [])]
      }
    BoolArg(name, bool_config, piece_filters) =>
      // DR-076 §1/§4: bool value slot (DR-074 §3/§4 canonical + bool_parser factory config) —
      // mirrors NumArg/FloatArg/IntArg.
      if pos < ctx.toks.length() {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_bool_ext(s, bool_config) {
              Some(b) =>
                [Accept(pos + 1, [mkb(name, VBool(b), Cli, at_pos=Some(pos))])]
              None => [Held(pe_parse_bool(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
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
        // DR-093 §2/§7: step_greedy の同アームと同じ committed placeholder binding (off-spine
        // evaluation はこの1本の Branch の bindings を返すだけ — 呼び出し元が outer acc と cat する)。
        [Accept(pos + 1, [mkb(trigger, VBool(true), Cli, at_pos=Some(pos))])]
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([cand_trigger(trigger, trigger, TFlag, WordEnd, false)], [])]
      } else {
        []
      }
    // DR-090: off-spine mirror of `DdSat`'s own arm above, generalized to pattern matching +
    // self_keep's 0-token Accept. Off-spine evaluation never threads `severed` (that's the SPINE
    // walk's job, `step_greedy`'s own DdMatchSat arm below) — this arm only answers "does this
    // node accept here", same degenerate scope `DdSat`'s off-spine arm already has.
    DdMatchSat(spelling, is_pattern, self_keep, elem_name) =>
      if pos < ctx.toks.length() &&
        dd_match_token(spelling, is_pattern, ctx.toks[pos]) {
        // DR-093 §2/§7: same committed placeholder as the DdSat arm above, keyed by `elem_name`.
        let b = mkb(elem_name, VBool(true), Cli, at_pos=Some(pos))
        if self_keep {
          [Accept(pos, [b])]
        } else {
          [Accept(pos + 1, [b])]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) && !is_pattern {
        // DR-060 §1 completion candidates only make sense for an EXACT spelling (a regex
        // pattern has no single "next token to type" to surface as a candidate).
        [Pending([cand_trigger(spelling, spelling, TFlag, WordEnd, false)], [])]
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
              marked.push({ ..x, link: depth })
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
        [
          Accept(pos + 1, [
            mkb(name, VStr(ctx.toks[pos]), Cli, at_pos=Some(pos)),
          ]),
        ]
      } else {
        []
      }
    IdxRepeat(label, head, min, budget) =>
      idx_repeat_eval(label, head, min, budget, ctx, pos)
    BoundedTail(head, budget, _) =>
      // off-spine fallback: degrade to the nested-Opt form (0..budget heads).
      eval(bounded_opt(head, budget), ctx, pos)
    GreedyRepeat(tail) =>
      // off-spine fallback: no sibling Scope to suppress against, so just evaluate the tail
      // plainly (loses 先食い, acceptable off-spine — see node.mbt's doc comment).
      eval(tail, ctx, pos)
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
          [
            Accept(
              pos + 1,
              cat(acc, [mkb(name, VNum(d), Cli, at_pos=Some(pos))]),
            ),
          ]
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
    [
      Accept(
        pos + 1,
        cat(acc, [mkb(name, VStr(ctx.toks[pos]), Cli, at_pos=Some(pos))]),
      ),
    ]
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
/// DR-091 §2: whether `s` contains at least one `=` — the `KvArg` consume-time gate's structural
/// precondition (a `kv_map` accumulator piece must be shaped `k=v`, checked BEFORE `build_result`
/// ever tries to split it — this function only answers "is there a split point at all", the actual
/// first-`=` split happens once in `resolve.mbt` at fold time, `split_first_eq`).
fn contains_eq(s : String) -> Bool {
  for c in s {
    if c == '=' {
      return true
    }
  }
  false
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
/// One Set-effect binding per split piece (spec DR-034 + DR-045). `piece_filters` runs per PIECE (not
/// once over the whole raw token) — DESIGN §6.2's pieceProcessor applies piece_filters AFTER the
/// separator split, one piece at a time (this is what distinguishes `per-piece-trim.json` from a
/// "trim the whole raw string first" misreading). AFTER piece_filters, each piece goes through its
/// OWN type parse (issue 2026-07-09-separator-non-string-type-parse-gap 段2 — DESIGN §6.2's
/// pieceProcessor: separator → piece_filters → parse → final_filters/accum_filters, one piece at a
/// time; a piece's
/// type is independent of whether it came via separator, `elem_head`'s pre-段2 "always VStr"
/// shortcut was the bug this closes). A piece_filters reject OR a type-parse failure on ANY piece
/// fails the WHOLE binding (`Err` short-circuits) — same all-or-nothing contract a single-piece
/// value primitive has; the two failure kinds stay distinct (`KFilter` vs `KParse`, mirrored from
/// the scalar value-primitive arms' own pe_filter/pe_parse split).
/// `pos` (issue 2026-07-09-accum-entity-filters-wiring): every split piece is attributed to the
/// SAME argv token position — a piece is not itself a token, so there is no finer-grained position
/// to give it (CONFORMANCE §3's piece-attribution regulation attributes per-piece failures to the
/// whole token they came from, per `multiple-parse/filters-each.json::separator-piece-rejects-whole`
/// and `separator-typed.json::option-separator-piece-parse-rejected`).
/// `merge` (DR-080 波及節): whether `name`'s element declared `accumulator: "merge"` — the marker
/// vocabulary (`classify_merge_piece`) only applies to a merge-declared element's pieces (DR-080
/// §1 "マーカー語彙は accumulator=merge を宣言した要素の CLI 発火 piece 列にのみ適用"). When false,
/// every piece is treated as a plain add (`PkAdd(part)`, no classification) — degenerates to the
/// pre-DR-080 behavior exactly (no piece is ever `-`/`@`-prefixed specially for append etc).
/// `sep` is `String?`, not `String` (codex Medium 追従): `None` = no declared separator, DR-034
/// §6.3's degenerate form — `tok` itself is the ONE piece (`[tok]`), never split. A non-merge
/// element with no separator never reaches this function at all (`value_prim`'s routing still
/// gates on `separator is Some(_) || merge`); a MERGE element with no separator DOES reach here
/// now, precisely so its single-piece operand still runs through `classify_merge_piece` (a bare
/// `--fields -a` needs to recognize `-a` as a remove marker even with no comma to split on).
fn sep_binds(
  name : String,
  tok : String,
  sep : String?,
  ty : Ty,
  int_round : RoundMode,
  allow_base_prefix : Bool,
  bool_config : BoolConfig,
  piece_filters : Array[FilterSpelling],
  pos : Int,
  merge : Bool,
) -> Result[Array[Binding], ParseError] {
  let out : Array[Binding] = []
  let parts = match sep {
    Some(s) => split_on(tok, s)
    None => [tok]
  }
  for part in parts {
    let mark : PieceMark = if merge {
      classify_merge_piece(part)
    } else {
      PkAdd(part)
    }
    match mark {
      // DR-080 §2 splice: no payload, no filters/parse — a pure cell-marker binding
      // (mirrors Default/Unset/Empty's placeholder-value convention).
      PkSplice =>
        out.push({
          key: name,
          op: Splice,
          value: VBool(false),
          source: Cli,
          scope: [],
          link: 0,
          at_pos: Some(pos),
        })
      PkRemove(payload) =>
        match
          sep_piece_value(
            name, payload, ty, int_round, allow_base_prefix, bool_config, piece_filters,
            pos,
          ) {
          Ok(v) =>
            out.push({
              key: name,
              op: Remove,
              value: v,
              source: Cli,
              scope: [],
              link: 0,
              at_pos: Some(pos),
            })
          Err(pe) => return Err(pe)
        }
      PkAdd(payload) =>
        match
          sep_piece_value(
            name, payload, ty, int_round, allow_base_prefix, bool_config, piece_filters,
            pos,
          ) {
          Ok(v) => out.push(mkb(name, v, Cli, at_pos=Some(pos)))
          Err(pe) => return Err(pe)
        }
    }
  }
  Ok(out)
}

///|
/// One split piece's payload → `piece_filters` → type parse (DESIGN §6.2's pieceProcessor,
/// shared by `sep_binds`'s add/remove piece kinds — DR-080 §2 "remove operand は payload として
/// 型 parse を通る", 同じ規約を add piece と共有する). Factored out of `sep_binds` so the
/// non-merge (plain add) and merge (add/remove) piece kinds run the EXACT same filter→parse
/// pipeline, never two copies drifting apart.
fn sep_piece_value(
  name : String,
  part : String,
  ty : Ty,
  int_round : RoundMode,
  allow_base_prefix : Bool,
  bool_config : BoolConfig,
  piece_filters : Array[FilterSpelling],
  pos : Int,
) -> Result[Value, ParseError] {
  match apply_piece_filters(piece_filters, part) {
    Err((reason, msg)) => Err(pe_filter(name, pos, reason, msg))
    Ok(s) =>
      match ty {
        TNum =>
          match parse_number_ext(s, allow_base_prefix) {
            Some(d) => Ok(VNum(d))
            None => Err(pe_parse(name, s, pos))
          }
        TInt =>
          match parse_int_value_ext(s, int_round, allow_base_prefix) {
            Ok(i) => Ok(VNum(i.to_double()))
            Err(NotAnInteger) => Err(pe_parse_int(name, s, pos))
            Err(IntOutOfRange) => Err(pe_int_out_of_range(name, s, pos))
            Err(NotANumber) => Err(pe_parse(name, s, pos))
          }
        TFloat =>
          match parse_float(s) {
            Some(d) => Ok(VNum(d))
            None => Err(pe_parse(name, s, pos))
          }
        TBool =>
          match parse_bool_ext(s, bool_config) {
            Some(b) => Ok(VBool(b))
            None => Err(pe_parse_bool(name, s, pos))
          }
        // TStr (and any other kind that structurally never reaches a SepArg, e.g. TFlag/TCount —
        // multiple/separator on a presence-only cell is not a real shape): identity parse, the
        // pre-段2 default behavior preserved exactly for string elements.
        _ => Ok(VStr(s))
      }
  }
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
      out.push({ ..b, scope: sc2, link: 0 })
    }
  }
  out
}

///|
/// Named indexed-array repeat (spec DR-043): consumes reps deterministically (the split is
/// bounded by the head's Reject / exact mismatch, no downstream backtrack — see node.mbt's
/// `IdxRepeat` doc comment for the still-open unbounded-case GAP).
///
/// `budget` (issue 2026-07-13-positional-group-trailing-missing-operand) caps reps beyond
/// `min`: `None` = unbounded greedy-max (consumes as many reps as the head allows, the
/// original behavior), `Some(b)` = stop once `rep >= min + b` (a bounded `repeat: {min,
/// max}` spec, `b = max - min`) so a trailing mandatory positional isn't starved by a
/// permissive head over-consuming past its declared upper bound.
fn idx_repeat_eval(
  label : String,
  head : Node,
  min : Int,
  budget : Int?,
  ctx : Ctx,
  pos : Int,
) -> Array[Branch] {
  let acc : Array[Binding] = [array_marker(label)]
  let mut cur = pos
  let mut rep = 0
  let mut go = true
  while go {
    let at_budget = match budget {
      Some(b) => rep >= min + b
      None => false
    }
    if at_budget {
      go = false
    } else {
      let p2 = idx_one(head, label, rep, ctx, cur, acc)
      if p2 > cur {
        cur = p2
        rep = rep + 1
      } else {
        go = false
      }
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
    let more_typable = match budget {
      Some(b) => rep < min + b
      None => true
    }
    if in_complete(ctx) && more_typable {
      // complete: min is met but one MORE rep is still typable (and budget allows it) —
      // union in the head's boundary candidates (DR-060 §1 全生存 partial の和集合).
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
/// DR-097: whether a SHALLOW (no-continuation) probe of `g` at `pos` yields a
/// VIABLE reading — Accept that advances position. Held (value-space match
/// failure, a dead end for THIS reading) does not count — that is exactly
/// "missing operand でない" 's negation. Pending is mode-dependent: `eval`'s
/// value-primitive arms (StrArg/NumArg/etc.) return an EXPLICIT Pending at
/// argv end REGARDLESS of mode (their own doc comment: "the end of input at
/// a value slot is an explicit Pending, not a silent []" — an off-spine/
/// completion-probe design predating DR-097). In parse mode that Pending IS
/// DR-097's "missing operand" (a value slot starved at argv end) and must
/// NOT count as viable, or a value-less trigger at the tail of argv would
/// wrongly suppress the pass-through fixture
/// matcher-readings/long-empty-prefix-typed.json pins against. In complete
/// mode the SAME Pending is the candidate carrier for completion (spec is
/// silent on complete-mode 早閉じ/先食い semantics; this preserves the
/// pre-DR-097 posture there via `eval_consumes`'s old `Pending(_, _) =>
/// return true`, unchanged since this predicate is a parse-phase one).
fn has_viable(brs : Array[Branch], pos : Int, ctx : Ctx) -> Bool {
  for b in brs {
    match b {
      Accept(p2, _) => if p2 > pos { return true }
      Held(_, _) => ()
      Pending(_, _) => if in_complete(ctx) { return true }
    }
  }
  false
}

///|
/// A greedy entry "reads" at `pos` iff the READING ITSELF IS VIABLE (spec
/// DR-097, precising DR-041 §4's 先食い/早閉じ抑制 predicate 「読める」):
/// trigger fires, AND — for entries that carry a value slot — that slot's
/// token is available (not missing_operand) and passes its OWN value-space
/// match (parse phase, factory config included). Downstream consequences
/// (sibling elements' fulfillment, deferred constraints §15.9, later
/// tokens' fate) play NO part — DR-097 rejected the continuation-based
/// "does the rest of the parse complete" formulation after a reference-impl
/// experiment broke 39 existing fixtures (unrelated downstream failures
/// leaking backward into an unrelated entry's suppression verdict, e.g. a
/// value-less flag's reading going "unviable" because a SIBLING required
/// positional starves at end-of-input).
///
/// Entries with NO value slot (flag/count/dd/command) are viable whenever
/// the trigger fires, UNCONDITIONALLY — this is why CmdSat/DdSat/DdMatchSat
/// stay a bare structural trigger test below rather than routing through
/// the shallow `eval` probe: a CmdSat's "value slot" is its entire child
/// scope, and evaluating that scope would pull in exactly the downstream
/// failures (child-scope-internal missing/constraint) the predicate must
/// not see.
///
/// Every other shape (Seq trigger+value-slot satellites, NativeMatch long/
/// short/eq-split matchers, bare value primitives) reduces to ONE shallow
/// `eval(g, ctx, pos)` probe with no continuation threaded — `eval_seq`
/// already evaluates "trigger, then value slot" as a single unit, so this
/// one probe naturally captures both trigger-match and value-space-match in
/// one pass without any continuation/CPS machinery (spec `停止性と有界性`:
/// the predicate is closed over the reading's own span, at most a handful
/// of tokens, and never recurses into downstream search).
fn greedy_engages(g : Node, ctx : Ctx, pos : Int) -> Bool {
  match g {
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
    DdMatchSat(spelling, is_pattern, _, _) =>
      dd_match_token(spelling, is_pattern, ctx.toks[pos])
    Rooted(inner, _) => greedy_engages(inner, ctx, pos)
    _ => has_viable(eval(g, ctx, pos), pos, ctx)
  }
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
/// DR-097 早閉じ裁定の補助 (STRUCTURAL trigger test only, no value-slot
/// evaluation — the pre-DR-097 predicate, kept ONLY for this narrow use):
/// whether `g`'s trigger fires at `pos`, independent of whether its reading
/// is viable. Used exclusively to distinguish, at an early-close decision
/// point, "no entry's trigger matched at all" (a genuine unattributed
/// residual token) from "some entry's trigger matched but its OWN reading
/// is unviable" (that entry's `step_greedy` call already deposited a more
/// specific Held into `out` — spec 不変ノート「受け皿の無い定義では held
/// Error が唯一の結末」extends to 早閉じ: the coarser unexpected_token
/// this early-close would ALSO produce is a strictly less informative
/// restatement of the SAME reading's failure, not an independent one).
fn greedy_trigger_matches(g : Node, ctx : Ctx, pos : Int) -> Bool {
  match g {
    Seq(items) =>
      if items.length() >= 1 {
        match items[0] {
          Exact(s) => ctx.toks[pos] == s
          NativeMatch(m) => run_matcher(m, ctx, pos).length() > 0
          _ => greedy_engages(g, ctx, pos)
        }
      } else {
        false
      }
    Or(alts) => {
      for a in alts {
        if greedy_trigger_matches(a, ctx, pos) {
          return true
        }
      }
      false
    }
    CmdSat(name, _) => ctx.toks[pos] == name
    DdSat(t) => ctx.toks[pos] == t
    DdMatchSat(spelling, is_pattern, _, _) =>
      dd_match_token(spelling, is_pattern, ctx.toks[pos])
    NativeMatch(m) => run_matcher(m, ctx, pos).length() > 0
    Rooted(inner, _) => greedy_trigger_matches(inner, ctx, pos)
    _ => greedy_engages(g, ctx, pos)
  }
}

///|
/// Whether ANY greedy entry's trigger fires at `pos` (see
/// `greedy_trigger_matches`'s doc comment for why this is a separate,
/// coarser probe than `greedy_reads`).
fn any_trigger_matches(sc : Scope, ctx : Ctx, pos : Int) -> Bool {
  if pos >= ctx.toks.length() {
    return false
  }
  for g in sc.greedy {
    if greedy_trigger_matches(g, ctx, pos) {
      return true
    }
  }
  false
}

///|
/// Whether raw pass-through of the token at `pos` is suppressed. 先食い is
/// greedy-ONLY (spec DR-041 §4): a raw-eat is suppressed iff some greedy
/// entry's reading here is VIABLE (spec DR-097, `greedy_reads` above). Once
/// severed, nothing is suppressed.
fn suppressed(sc : Scope, ctx : Ctx, pos : Int, severed : Bool) -> Bool {
  if severed {
    return false
  }
  greedy_reads(sc, ctx, pos)
}

///|
/// DR-086 cut 判定補助 (issue values-decode-support): 0-token マーカーかどうか — installer.mbt の
/// lowering が variant (Set/Default/Unset/Empty) satellite の「trigger 消費後、値を取らない」側に
/// 積む構成要素 (`Seq([Exact(trigger), ..これらのみ..])`、`inst_long`「Variant entries」ループ参照)。
/// この判定は lowering が生成する具体的な shape と同期が必要 — 新しい 0-token marker 種別が Node
/// に増えたらここにも追加すること。
fn is_zero_token_marker(n : Node) -> Bool {
  match n {
    Bind(_, _) => true
    EffMark(_, _) => true
    DeprMark(_) => true
    FailMark(_) => true
    _ => false
  }
}

///|
/// DR-086 cut (issue values-decode-support、team-lead 裁定 2026-07-10「性質ベースの判定、
/// lowering の生成 shape 追加で漏れないように」): greedy 衛星 `g` が「trigger を Exact 消費した
/// 直後、値を1つ以上消費しうる継続」を持つ main entry (installer.mbt の `value_prim`/
/// `enum_value_node` 由来) なら trigger 文字列を返す。具体的な値消費 shape
/// (StrArg/NumArg/FloatArg/IntArg/BoolArg/SepArg/Or/...) を列挙する代わりに「継続の先頭要素が
/// 0-token マーカーでない」という消極的な性質で判定する — lowering に新しい値消費 shape が
/// 増えても自動的に安全側 (cut 候補として拾う) に倒れ、このヘルパーの更新漏れを起こさない。
fn value_slot_trigger(g : Node) -> String? {
  match g {
    Seq([Exact(t), rest, ..]) =>
      if is_zero_token_marker(rest) {
        None
      } else {
        Some(t)
      }
    _ => None
  }
}

///|
/// DR-086 cut: `value_slot_trigger` の対極 (fallback 側候補) — greedy 衛星 `g` が「trigger を
/// Exact 消費した直後、0-token マーカーのみが (1個以上) 続く」形 (installer.mbt の
/// Set/Default/Unset/Empty variant lowering、fail_action 付き Set variant の
/// `Bind, FailMark` 2連続を含む) なら trigger 文字列を返す。
fn zero_arg_variant_trigger(g : Node) -> String? {
  match g {
    Seq([Exact(t), .. rest]) => {
      if rest.length() == 0 {
        return None
      }
      let mut all_zero = true
      for n in rest {
        if !is_zero_token_marker(n) {
          all_zero = false
        }
      }
      if all_zero {
        Some(t)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// `Branch` 配列に `Accept` が1つでも含まれるか (DR-086 cut の判定基準そのもの — 「照合消費
/// できる」)。
fn has_accept(brs : Array[Branch]) -> Bool {
  for b in brs {
    match b {
      Accept(_, _) => return true
      _ => ()
    }
  }
  false
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
  //
  // DR-086 cut (issue values-decode-support): 同一 trigger を持つ「値スロット main entry」と
  // 「0引数 Set variant」が競合する場合、値スロット側が現在トークンを照合消費できるなら cut で
  // そちらだけを採用し、0引数 variant へ backtrack しない (DR-086 §1)。lowering 構造
  // (`build.greedy` に積む Node の個数・形) は一切変えず、ここ (経路探索へ投入する直前) でのみ
  // 読みを間引く — DR-086 §3「経路空間に投入される読みの数を減らす局所規則」の位置づけそのもの、
  // node.mbt/installer.mbt には手を入れない (lowering query fixture への影響回避、team-lead
  // 裁定 2026-07-10)。
  //   1st pass: 値スロット候補を先に評価し、Accept があった trigger を cut_triggers に記録する
  //   (Reject = Accept 0 の場合は記録しない — DR-086 §1「食えない場合は従来どおり引数なし枝が
  //   生きる」)。cut 判定は「trigger + 値スロット自体」が消費できるかという**浅い**基準
  //   (`eval(g, ctx, pos)` — 継続 k を含まない) を使う。継続 k まで含めた深い評価
  //   (`step_greedy`、後続 positional の充足可否まで見てしまう) を判定に使うと DR-086 §1 の
  //   「後続文法の充足可能性を理由に引数なし枝へ再解釈しない」に反する誤判定になる (required
  //   positional が飢える経路も「値スロット自体は食えている」ので cut すべきところ、深い評価だと
  //   その経路全体が Held に落ちて Accept 0 と誤認識してしまう — 2026-07-10 実機で発覚)。cut が
  //   確定した後の実際の経路探索は、既存の `step_greedy` (継続 k 込み) にそのまま委ねる。
  if !severed {
    let cut_triggers : Array[String] = []
    let value_slot_nodes : Array[Node] = []
    for g in sc.greedy {
      match value_slot_trigger(g) {
        Some(trigger) => {
          value_slot_nodes.push(g)
          if has_accept(eval(g, ctx, pos)) {
            cut_triggers.push(trigger)
          }
          step_greedy(g, sc, ctx, pos, pidx, acc, severed, k, out)
        }
        None => ()
      }
    }
    for g in sc.greedy {
      let mut already = false
      for h in value_slot_nodes {
        if h == g {
          already = true
        }
      }
      if already {
        continue
      }
      match zero_arg_variant_trigger(g) {
        Some(trigger) => {
          let mut cut = false
          for t in cut_triggers {
            if t == trigger {
              cut = true
            }
          }
          if !cut {
            step_greedy(g, sc, ctx, pos, pidx, acc, severed, k, out)
          }
        }
        None => step_greedy(g, sc, ctx, pos, pidx, acc, severed, k, out)
      }
    }
  }
  // (B) advance the positional face
  if pidx >= sc.positional.length() {
    // 早閉じ抑制 (spec DR-041 §4 + DR-097): a scope with a backbone cannot
    // complete while one of its own greedy entries has a VIABLE reading of
    // the next token — "that which can be read here, is read here" now
    // means "that which reaches parse-phase viability here" (DR-097's
    // precising of 「読める」), not merely trigger-match.
    if severed {
      for r in run_cont(k, ctx, pos, acc) {
        out.push(r)
      }
    } else if !greedy_reads(sc, ctx, pos) {
      // DR-097 裁定側 (生成と裁定の層分離): if some entry's trigger DID
      // fire here but its reading is unviable, that entry's own `step_greedy`
      // call above already deposited a more specific Held into `out` (value-
      // space mismatch / missing operand). The early-close choice we are
      // about to run is then a strictly coarser restatement of the SAME
      // failure IF it too only reaches a dead end (a bare residual-token
      // Held at this exact `pos`) — drop only that shape, so a genuine
      // trigger-mismatch residual (no entry fired at all, e.g.
      // constraints-parse/requires-dd-target.json's Many-share dead end) and
      // any early-close outcome that reaches an Accept/Pending (e.g.
      // command-scope/early-close-viability.json's build→rest hand-off)
      // both still ride through untouched.
      let drop_redundant_residual = any_trigger_matches(sc, ctx, pos)
      for r in run_cont(k, ctx, pos, acc) {
        match r {
          Held(pe, _) =>
            if drop_redundant_residual &&
              pe.element == "" &&
              pe.reason == "unexpected_token" &&
              pe.argv_pos == pos {
              ()
            } else {
              out.push(r)
            }
          _ => out.push(r)
        }
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
        // DR-093 §2/§7: fire を committed として観測可能にする placeholder binding
        // (`flag_bare_true_variant` と同型の `Set VBool(true)`、`NoneCell`/`none_cells` が
        // build_result/effects から除外する — 値そのものは運ばない、DR-089 §3 不変)。DdSat の
        // trigger 文字列は要素名そのもの (dd_match 未使用の唯一のケースでのみ installer が
        // `DdSat(e.name)` を作る) なのでそのまま key に使える。
        let acc2 = cat(acc, [mkb(trigger, VBool(true), Cli, at_pos=Some(pos))])
        for r in scope_step(sc, ctx, pos + 1, pidx, acc2, true, k) {
          out.push(r)
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        out.push(
          Pending([cand_trigger(trigger, trigger, TFlag, WordEnd, false)], acc),
        )
      }
    // DR-090 §1/§2: generalized dd. `severed=true` is unconditional here exactly like `DdSat`
    // above (the sever is the "greedy internal consumption is 一体" rule, unaffected by which
    // axis fired). `self_keep` only changes the RESUMED position: `false` (drop) consumes the
    // triggering token (`pos + 1`, same as `DdSat`); `true` (keep) resumes at the SAME `pos` —
    // the triggering token itself is never consumed here, so it flows into the positional face
    // (now severed = raw) starting with itself, matching §2's "自身を含めて以降が positional 域".
    DdMatchSat(spelling, is_pattern, self_keep, elem_name) =>
      if pos < ctx.toks.length() &&
        dd_match_token(spelling, is_pattern, ctx.toks[pos]) {
        let resume_pos = if self_keep { pos } else { pos + 1 }
        // DR-093 §2/§7: DdSat と同じ committed placeholder binding。key は `elem_name` (要素の
        // 同一性軸、DR-090 §2) — `spelling` は match 使用時トリガ綴りやパターンで要素名と一致しない。
        let acc2 = cat(acc, [mkb(elem_name, VBool(true), Cli, at_pos=Some(pos))])
        for r in scope_step(sc, ctx, resume_pos, pidx, acc2, true, k) {
          out.push(r)
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) && !is_pattern {
        // completion candidates only for an exact spelling (see the off-spine `eval` arm's
        // identical rationale) — a pattern trigger has no single "next token to type".
        out.push(
          Pending(
            [cand_trigger(spelling, spelling, TFlag, WordEnd, false)],
            acc,
          ),
        )
      }
    Or(alts) =>
      for a in alts {
        step_greedy(a, sc, ctx, pos, pidx, acc, severed, k, out)
      }
    _ =>
      match greedy_repeat_split(g) {
        Some((prefix, tail)) =>
          step_greedy_repeat(
            prefix, tail, sc, ctx, pos, pidx, acc, severed, k, out,
          )
        None =>
          for b in eval(g, ctx, pos) {
            match b {
              Accept(p2, bs) =>
                if p2 > pos {
                  for
                    r in scope_step(sc, ctx, p2, pidx, cat(acc, bs), severed, k) {
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
}

///|
/// Detect a `Seq([..prefix.., GreedyRepeat(tail)])` satellite shape (installer.mbt's option
/// repeat lowering, DR-078 §1) — the prefix (trigger + any 0-token markers) evaluates plainly;
/// `tail` needs `step_greedy_repeat`'s `sc`-aware treatment instead.
fn greedy_repeat_split(g : Node) -> (Node, Node)? {
  match g {
    Seq(items) =>
      if items.length() >= 1 {
        match items[items.length() - 1] {
          GreedyRepeat(tail) => {
            let prefix : Array[Node] = []
            let mut i = 0
            while i < items.length() - 1 {
              prefix.push(items[i])
              i = i + 1
            }
            Some((Seq(prefix), tail))
          }
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}

///|
/// Evaluate an option satellite's `prefix` (plain, off-spine — just the trigger and any 0-token
/// markers) then hand `tail` (the repeat node) to a THROWAWAY single-slot `Scope` that borrows
/// `sc.greedy` (node.mbt's `GreedyRepeat` doc comment explains why this is needed: 先食い against
/// sibling triggers, including a refire of the SAME option, DR-041 §4).
fn step_greedy_repeat(
  prefix : Node,
  tail : Node,
  sc : Scope,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  k : Cont,
  out : Array[Branch],
) -> Unit {
  for b in eval(prefix, ctx, pos) {
    match b {
      Accept(p2, bs) => {
        let wrap_sc : Scope = {
          greedy: sc.greedy,
          positional: [tail],
          entities: [],
          constraints: [],
        }
        for r in scope_consume(wrap_sc, tail, ctx, p2, 0, [], severed, KDone) {
          match r {
            Accept(p3, bs2) =>
              for
                rr in scope_step(
                  sc,
                  ctx,
                  p3,
                  pidx,
                  cat(acc, cat(bs, bs2)),
                  severed,
                  k,
                ) {
                out.push(rr)
              }
            Held(pe, bs2) => out.push(Held(pe, cat(acc, cat(bs, bs2))))
            Pending(cs, bs2) => out.push(Pending(cs, cat(acc, cat(bs, bs2))))
          }
        }
      }
      Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
      Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
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
    StrArg(name, piece_filters) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx + 1,
              cat(acc, [mkb(name, VStr(s), Cli, at_pos=Some(pos))]),
              severed,
              k,
            )
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
        }
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
    // DR-091 §2: kv_map on a positional spine — same shape as the StrArg arm above, plus the `=`
    // containment gate (`eval`'s `KvArg` arm doc comment).
    KvArg(name, piece_filters) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            if contains_eq(s) {
              scope_step(
                sc,
                ctx,
                pos + 1,
                pidx + 1,
                cat(acc, [mkb(name, VStr(s), Cli, at_pos=Some(pos))]),
                severed,
                k,
              )
            } else {
              [Held(pe_parse_kv(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    SepArg(name, sep, ty, int_round, base, bool_config, piece_filters, merge) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match
          sep_binds(
            name,
            ctx.toks[pos],
            sep,
            ty,
            int_round,
            base,
            bool_config,
            piece_filters,
            pos,
            merge,
          ) {
          Ok(bs) =>
            scope_step(sc, ctx, pos + 1, pidx + 1, cat(acc, bs), severed, k)
          Err(pe) => [Held(pe, acc)]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(ty, name)], acc)]
        } else {
          [Held(pe_missing(name, pos), acc)]
        }
      } else {
        []
      }
    NumArg(name, base, piece_filters) =>
      // DR-074 §1 + §2 (scope_step 経路: parse_number_ext with base flag)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_number_ext(s, base) {
              Some(d) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx + 1,
                  cat(acc, [mkb(name, VNum(d), Cli, at_pos=Some(pos))]),
                  severed,
                  k,
                )
              None => [Held(pe_parse(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
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
    FloatArg(name, piece_filters) =>
      // DR-074 §1 CLI 値空間 (scope_step 経路: NumArg のミラー、parse_number→parse_float / TNum→TFloat)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_float(s) {
              Some(d) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx + 1,
                  cat(acc, [mkb(name, VNum(d), Cli, at_pos=Some(pos))]),
                  severed,
                  k,
                )
              None => [Held(pe_parse(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
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
    IntArg(name, mode, base, piece_filters) =>
      // DR-075 §1-§2 + DR-074 §2 CLI 値空間判定 + int_round + base prefix (scope_step 経路)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_int_value_ext(s, mode, base) {
              Ok(i) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx + 1,
                  cat(acc, [
                    mkb(name, VNum(i.to_double()), Cli, at_pos=Some(pos)),
                  ]),
                  severed,
                  k,
                )
              Err(NotAnInteger) => [Held(pe_parse_int(name, s, pos), acc)]
              Err(IntOutOfRange) =>
                [Held(pe_int_out_of_range(name, s, pos), acc)]
              Err(NotANumber) => [Held(pe_parse(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
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
    BoolArg(name, bool_config, piece_filters) =>
      // DR-076 §1/§4 CLI 値空間 (scope_step 経路: NumArg/IntArg/FloatArg のミラー)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_bool_ext(s, bool_config) {
              Some(b) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx + 1,
                  cat(acc, [mkb(name, VBool(b), Cli, at_pos=Some(pos))]),
                  severed,
                  k,
                )
              None => [Held(pe_parse_bool(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
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
                cat(acc, [mkb(name, VNum(d), Cli, at_pos=Some(pos))]),
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
          cat(acc, [mkb(name, VStr(ctx.toks[pos]), Cli, at_pos=Some(pos))]),
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
      // any other node as a positional item: consume it (codex 節目レビュー指摘3、issue
      // 2026-07-09-ref-template-result-shape: a ref element's mandatory-head-unrolled slot
      // (installer.mbt's `ref_row_head`, `min > 1` positional repeat) is a COMPOUND node
      // (Scoped/Seq/Or wrapping the referenced template's leaves) placed directly on the spine —
      // plain off-spine `eval` has no `Scope`, so it could never apply 先食い (DR-041 §4) to a
      // nested leaf. `consume_compound` (eval.mbt, shared with `consume_head`'s own catch-all)
      // threads `sc`/`severed` down to every leaf primitive it reaches instead), then continue.
      let out : Array[Branch] = []
      for b in consume_compound(sc, other, ctx, pos, severed) {
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
    StrArg(name, piece_filters) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            [Accept(pos + 1, [mkb(name, VStr(s), Cli, at_pos=Some(pos))])]
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
        }
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
    // DR-091 §2: kv_map as a repeat head — same shape as the StrArg arm above, plus the `=`
    // containment gate (`eval`'s `KvArg` arm doc comment).
    KvArg(name, piece_filters) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            if contains_eq(s) {
              [Accept(pos + 1, [mkb(name, VStr(s), Cli, at_pos=Some(pos))])]
            } else {
              [Held(pe_parse_kv(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(TStr, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    SepArg(name, sep, ty, int_round, base, bool_config, piece_filters, merge) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match
          sep_binds(
            name,
            ctx.toks[pos],
            sep,
            ty,
            int_round,
            base,
            bool_config,
            piece_filters,
            pos,
            merge,
          ) {
          Ok(bs) => [Accept(pos + 1, bs)]
          Err(pe) => [Held(pe, [])]
        }
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([pend_value(ty, name)], [])]
        } else {
          [Held(pe_missing(name, pos), [])]
        }
      } else {
        []
      }
    NumArg(name, base, piece_filters) =>
      // DR-074 §1 + §2 (先食い分岐: parse_number_ext with base flag)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_number_ext(s, base) {
              Some(d) =>
                [Accept(pos + 1, [mkb(name, VNum(d), Cli, at_pos=Some(pos))])]
              None => [Held(pe_parse(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
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
    FloatArg(name, piece_filters) =>
      // DR-074 §1 CLI 値空間 (先食い分岐: NumArg のミラー、parse_number→parse_float / TNum→TFloat)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_float(s) {
              Some(d) =>
                [Accept(pos + 1, [mkb(name, VNum(d), Cli, at_pos=Some(pos))])]
              None => [Held(pe_parse(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
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
    IntArg(name, mode, base, piece_filters) =>
      // DR-075 §1-§2 + DR-074 §2 (先食い分岐)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_int_value_ext(s, mode, base) {
              Ok(i) =>
                [
                  Accept(pos + 1, [
                    mkb(name, VNum(i.to_double()), Cli, at_pos=Some(pos)),
                  ]),
                ]
              Err(NotAnInteger) => [Held(pe_parse_int(name, s, pos), [])]
              Err(IntOutOfRange) =>
                [Held(pe_int_out_of_range(name, s, pos), [])]
              Err(NotANumber) => [Held(pe_parse(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
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
    BoolArg(name, bool_config, piece_filters) =>
      // DR-076 §1/§4 CLI 値空間 (先食い分岐: NumArg/IntArg/FloatArg のミラー)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_bool_ext(s, bool_config) {
              Some(b) =>
                [Accept(pos + 1, [mkb(name, VBool(b), Cli, at_pos=Some(pos))])]
              None => [Held(pe_parse_bool(name, s, pos), [])]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), [])]
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
        [
          Accept(pos + 1, [
            mkb(name, VStr(ctx.toks[pos]), Cli, at_pos=Some(pos)),
          ]),
        ]
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
              [Accept(pos + 1, [mkb(name, VNum(d), Cli, at_pos=Some(pos))])]
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
    // DR-078 §1 (issue 2026-07-09-ref-template-result-shape): a `ref` element's head is a
    // COMPOUND node (Or/Seq/Scoped wrapping a shared template's leaves, never a bare primitive)
    // — plain off-spine `eval` has no `Scope`, so it could never apply 先食い (DR-041 §4) to a
    // nested leaf (e.g. `colorname` swallowing a sibling `--hlcolors` refire trigger,
    // `multiple-parse/last-wins-repeat-rows.json`). `consume_compound` threads `sc`/`severed`
    // down to every leaf primitive it reaches instead.
    _ => consume_compound(sc, head, ctx, pos, severed)
  }
}

///|
/// Suppression-aware descent through the Or/Seq/Scoped/Ref/Bind shapes a `ref` element's
/// template is built from (installer.mbt's `dec_template_body`/`ref_row_head`) — mirrors `eval`'s
/// own Or/Seq combinators exactly, substituting `consume_head` (which DOES check `suppressed`)
/// for `eval` at every primitive leaf. Any OTHER node shape (not expected inside a template body)
/// falls back to plain `eval` — a terminal case, not mutual recursion with `consume_head`'s
/// catch-all above.
fn consume_compound(
  sc : Scope,
  node : Node,
  ctx : Ctx,
  pos : Int,
  severed : Bool,
) -> Array[Branch] {
  match node {
    StrArg(_, _)
    | SepArg(_, _, _, _, _, _, _, _)
    | KvArg(_, _)
    | NumArg(_, _, _)
    | FloatArg(_, _)
    | IntArg(_, _, _, _)
    | BoolArg(_, _, _)
    | ReqArg(_)
    | FilterArg(_, _) => consume_head(sc, node, ctx, pos, severed)
    Or(alts) => {
      let out : Array[Branch] = []
      for a in alts {
        for b in consume_compound(sc, a, ctx, pos, severed) {
          out.push(b)
        }
      }
      out
    }
    Seq(items) => consume_compound_seq(sc, items, 0, ctx, pos, [], severed)
    Scoped(label, body) =>
      nest_branches(label, consume_compound(sc, body, ctx, pos, severed))
    Ref(name) =>
      match ctx.defs.get(name) {
        Some(tpl) => consume_compound(sc, tpl, ctx, pos, severed)
        None => []
      }
    Bind(name, v) => [Accept(pos, [mkb(name, v, Cli)])]
    _ => eval(node, ctx, pos)
  }
}

///|
fn consume_compound_seq(
  sc : Scope,
  items : Array[Node],
  idx : Int,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  severed : Bool,
) -> Array[Branch] {
  if idx >= items.length() {
    return [Accept(pos, acc)]
  }
  let out : Array[Branch] = []
  for b in consume_compound(sc, items[idx], ctx, pos, severed) {
    match b {
      Accept(p2, bs) =>
        for
          r in consume_compound_seq(
            sc,
            items,
            idx + 1,
            ctx,
            p2,
            cat(acc, bs),
            severed,
          ) {
          out.push(r)
        }
      Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
      Pending(cs, bs) => out.push(Pending(cs, cat(acc, bs)))
    }
  }
  out
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
    StrArg(name, _) => if !str_mem(out, name) { out.push(name) }
    SepArg(name, _, _, _, _, _, _, _) =>
      if !str_mem(out, name) {
        out.push(name)
      }
    KvArg(name, _) => if !str_mem(out, name) { out.push(name) }
    NumArg(name, _, _) => if !str_mem(out, name) { out.push(name) }
    FloatArg(name, _) => if !str_mem(out, name) { out.push(name) }
    IntArg(name, _, _, _) => if !str_mem(out, name) { out.push(name) }
    BoolArg(name, _, _) => if !str_mem(out, name) { out.push(name) }
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
    StrArg(name, piece_filters) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            scope_step(
              sc,
              ctx,
              pos + 1,
              pidx,
              cat(acc, [mkb(name, VStr(s), Cli, at_pos=Some(pos))]),
              severed,
              k,
            )
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        // complete: "one more Many rep" starved at the boundary is a value
        // candidate (DR-060 §1) — in parse it is a legitimate silent stop
        // (the 0-more branch already covers the walk).
        [Pending([pend_value(TStr, name)], acc)]
      } else {
        []
      }
    NumArg(name, base, piece_filters) =>
      // DR-074 §1 + §2 (Many head 経路: parse_number_ext with base flag)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_number_ext(s, base) {
              Some(d) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx,
                  cat(acc, [mkb(name, VNum(d), Cli, at_pos=Some(pos))]),
                  severed,
                  k,
                )
              None => [Held(pe_parse(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TNum, name)], acc)]
      } else {
        []
      }
    FloatArg(name, piece_filters) =>
      // DR-074 §1 CLI 値空間 (Many head 経路: NumArg のミラー、parse_number→parse_float / TNum→TFloat)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_float(s) {
              Some(d) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx,
                  cat(acc, [mkb(name, VNum(d), Cli, at_pos=Some(pos))]),
                  severed,
                  k,
                )
              None => [Held(pe_parse(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TFloat, name)], acc)]
      } else {
        []
      }
    IntArg(name, mode, base, piece_filters) =>
      // DR-075 §1-§2 + DR-074 §2 (Many head 経路)
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_int_value_ext(s, mode, base) {
              Ok(i) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx,
                  cat(acc, [
                    mkb(name, VNum(i.to_double()), Cli, at_pos=Some(pos)),
                  ]),
                  severed,
                  k,
                )
              Err(NotAnInteger) => [Held(pe_parse_int(name, s, pos), acc)]
              Err(IntOutOfRange) =>
                [Held(pe_int_out_of_range(name, s, pos), acc)]
              Err(NotANumber) => [Held(pe_parse(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TInt, name)], acc)]
      } else {
        []
      }
    BoolArg(name, bool_config, piece_filters) =>
      // DR-076 §1/§4 CLI 値空間 (Many head 経路: NumArg/IntArg/FloatArg のミラー)。
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        match apply_piece_filters(piece_filters, ctx.toks[pos]) {
          Ok(s) =>
            match parse_bool_ext(s, bool_config) {
              Some(b) =>
                scope_step(
                  sc,
                  ctx,
                  pos + 1,
                  pidx,
                  cat(acc, [mkb(name, VBool(b), Cli, at_pos=Some(pos))]),
                  severed,
                  k,
                )
              None => [Held(pe_parse_bool(name, s, pos), acc)]
            }
          Err((reason, msg)) => [Held(pe_filter(name, pos, reason, msg), acc)]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([pend_value(TBool, name)], acc)]
      } else {
        []
      }
    // codex 節目レビュー指摘3 (issue 2026-07-09-ref-template-result-shape): a ref element's
    // UNBOUNDED min:0 repeat lowers to `Many(head, lazy)` (installer.mbt's `lower_repeat_head`) —
    // `head` here is a COMPOUND node (Scoped/Seq/Or, `ref_row_head`'s wrap), never a bare
    // primitive. This catch-all used to degrade to plain off-spine `eval`, which has no `Scope`
    // and so could never apply 先食い (DR-041 §4) to a nested leaf (e.g. a sibling trigger, or a
    // GreedyRepeat option's OWN refire, swallowed as one more "optional" rep instead of stopping).
    // `consume_compound` threads `sc`/`severed` down to every leaf primitive it reaches instead —
    // same substitution as `consume_head`'s catch-all and `scope_consume`'s "other" arm above.
    _ => {
      let out : Array[Branch] = []
      for b in consume_compound(sc, inner, ctx, pos, severed) {
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
    out.push({ ..b, link: 0 })
  }
  out
}

///|
/// codex 指摘 (2026-07-12): `parse()`'s dedup-only helper — drop any binding whose (scope, key)
/// matches a `NoneCell` (dd/none committed placeholder, DR-093 §2/§7 / DR-089 §3). These elements
/// carry no entity (DR-030 「実体=値セル」), so DESIGN §15.1's "実体への観測可能な効果列" path-
/// identity criterion does not see them — two branches whose only structural difference is WHICH
/// dd/none element fired (different `elem_name` key, same downstream positional/value effects)
/// must still dedup to one path. `scope_path_eq(nc.path, b.scope)` mirrors `is_committed`'s own
/// (path, name) matching (this same file) — `b.scope` already carries the binding's full declaring
/// path at this pre-`build_result` layer (nested scopes rewrite it on the way out, see the `{ ..b,
/// scope: sc2 }` call sites), same shape `NoneCell.path` uses.
fn strip_none_placeholders(
  bs : Array[Binding],
  nones : Array[NoneCell],
) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in bs {
    let mut is_none = false
    for n in nones {
      if n.name == b.key && scope_path_eq(n.path, b.scope) {
        is_none = true
        break
      }
    }
    if !is_none {
      out.push(b)
    }
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
/// DR-088 §1/§2: 「値源が宣言されている」= 「その値源から遅延解決する default_fn が設定されている
/// のと同型」= デフォルトの存在。経路探索 (選好・完全性) に参加する遅延述語の充足判定は、値の実解決
/// をせず**この静的宣言の有無だけ**を見る — committed か、または (default 属性 ∨ env 宣言 ∨
/// config 席 ∨ inherit 宣言) のいずれかがあれば「充足しうる」とみなす。bool/非bool を問わない
/// (真理値判定は最終判定 `resolve.mbt` の `apply_requires_filter` だけの仕事、探索中は「値が来る
/// 可能性があるか」だけを見る)。判定材料が定義の静的構造だけなので、経路選択は実行時の env/config
/// の中身に依存せず決定的になる (§2 の要求)。
fn value_declared(
  name : String,
  bindings : Array[Binding],
  path : Array[String],
  entities : Array[Entity],
) -> Bool {
  if is_committed(bindings, path, name) {
    return true
  }
  for e in entities {
    if e.name == name {
      return e.default_values is Some(_) ||
        e.env_key is Some(_) ||
        e.config_seat ||
        e.inherit_
    }
  }
  false
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
            if !value_declared(t, bindings, path, sc.entities) {
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
            if !value_declared(t, bindings, path, sc.entities) {
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
      CRequired(display, candidates) => {
        // DR-093 §1/§2: KTop の粗判定 (完全経路の成立条件、DR-047 §2) — `value_declared` を
        // そのまま再利用する (CRequires 目的語と同じゲート)。値空間なし (none) の要素は
        // default_values/env_key/config_seat/inherit_ をそもそも持てない (DR-089 §7) ため、
        // `value_declared` は committed のみで判定される形に自動的に縮退する — 型分岐を新設する
        // 必要はない。最終判定 (bool 特例なしの型委譲) は resolve.mbt の後段フィルタが行う。
        //
        // issue 2026-07-13-structural-or-type-branch-required-missing: `candidates` は
        // BOr (structural or) の場合、`display` 自身ではなく各枝の leaf name の配列 (node.mbt
        // の CRequired doc comment 参照)。いずれか 1 つでも充足していれば OK — 「どの枝であれ
        // 発火して値が確定していること」が or 親の required 充足 (DR-093)。通常要素は
        // `candidates == [display]` なので判定は従来どおり単一名のまま。
        let mut any_ok = false
        for c in candidates {
          if value_declared(c, bindings, path, sc.entities) {
            any_ok = true
          }
        }
        if !any_ok {
          out.push(
            constraint_err(
              display,
              "required_violated",
              "required '\{display}' is missing",
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
  // codex 指摘 (2026-07-12): dedup 判定 (下の `eff`/`dedup_key`) から dd/none の committed
  // placeholder binding を除外するための (path, name) 集合 — `none_cells` (resolve.mbt、
  // build_result が NoneCell として結果から除外する既存機構をそのまま再利用)。root が
  // `ScopeNode` でない場合 (dd/none は Scope 経由でのみ意味を持つ構造) は空集合のまま。
  let nones = match root {
    ScopeNode(sc) => none_cells(sc)
    _ => []
  }
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
          // codex 指摘 (2026-07-12, DESIGN §15.1「経路の同一性は実体への観測可能な効果列で判定
          // する」): dd/none 要素は entity (値セル) を持たない (DR-030) ため、そのプレースホルダ
          // binding は比較対象の「実体への効果」に含めない。`eff` 自体 (Success/Ambiguous が
          // 運ぶ binding 配列、build_result がそのまま NoneCell 除外に使う) は placeholder 込みの
          // ままにし、dedup 判定専用の `strip_none_placeholders` 済みキーだけを比較する — fixture
          // dd/duplicate-decl.json の「dd は値効果を持たないため同名複数宣言は同効果に落ちる」pin
          // は同名 (同一 key) の偶然の一致でしか成立せず、異名 (別 elem_name) の複数 dd/none 要素が
          // 同一トークンで競合する場合はこのキー抽出が無いと dedup できない (PoC wbtest で実測)。
          let dedup_key = strip_none_placeholders(eff, nones)
          let mut dup = false
          for existing in full {
            if strip_none_placeholders(existing, nones) == dedup_key {
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
        help_entry: find_help_entry(root, errors),
        tried_triggers: tried_triggers_of(root, errors),
      })
    1 => Success(full[0])
    _ =>
      // DR-073: structurally-distinct full paths have no export-key collision (they differ by
      // parse structure, not by provenance for a shared exposed key), so claimants stays empty.
      // Export-key co-exposure collisions are surfaced by a separate post-parse promotion step
      // (resolve.mbt `promote_collision_ambiguous`) which fills in claimants per interpretation.
      // help_entry: ambiguous には単一の「失敗位置」が無い (複数完全経路が成立している) ので、
      // `find_help_entry` へ空の errors を渡して root scope 全体を見る従来どおりの posture に
      // 留める (`find_help_entry`のフォールバック分岐、failure 側の失敗位置基準とは意図的に別)。
      Ambiguous({
        interpretations: {
          let a : Array[AmbInterp] = []
          for f in full {
            a.push({ binds: f, claimants: [] })
          }
          a
        },
        help_entry: find_help_entry(root, []),
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
