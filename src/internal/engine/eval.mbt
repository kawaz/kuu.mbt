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
/// stream, the template registry (DR-020/043), the active extension registry,
/// and the evaluation mode (parse vs complete — the collection-policy switch).
pub struct Ctx {
  priv toks : Array[String]
  priv defs : Map[String, Node]
  priv extensions_ : Registry
  priv mode : EvalMode
}

///|
pub fn Ctx::token_at(self : Ctx, pos : Int) -> String? {
  if pos < self.toks.length() {
    Some(self.toks[pos])
  } else {
    None
  }
}

///|
pub fn Ctx::is_complete_mode(self : Ctx) -> Bool {
  self.mode == ModeComplete
}

///|
/// The active extension assembly for registry-driven resident invocation.
pub fn Ctx::extensions(self : Ctx) -> Registry {
  self.extensions_
}

///|
fn Ctx::extension_context(self : Ctx) -> @extension.Ctx {
  @extension.Ctx::new(self.toks, self.extensions_, self.mode == ModeComplete)
}

///|
type InternalResume = (Ctx, Int, Array[Binding]) -> Array[Branch]

///|
/// Scope companions additionally report whether dd severed the continuation while walking the child.
type InternalScopeResume = (Ctx, Int, Array[Binding], Bool) -> Array[Branch]

///|
type InternalRejectedResume = (Ctx, ParseError, Array[Binding]) -> Array[Branch]

///|
type InternalHeldResume = (Ctx, ParseError, Array[Binding]) -> Array[Branch]

///|
type InternalPendingResume = (Ctx, Array[Candidate], Array[Binding]) -> Array[
  Branch,
]

///|
/// parse counts complete paths (DR-038); complete collects expectations
/// (DR-060). The walk is ONE implementation — mode switches the
/// collection-policy points below (MDR-002 §2.4):
/// - boundary trigger sites (Exact / CommandSatisfied / DdSatisfied / NativeMatch at args
///   end) emit `Pending` exact candidates instead of a silent Reject;
/// - spine value primitives starved at args end emit `Pending` value
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
/// DR-090 §2: whether `token` fires a `DdMatchSatisfied` trigger — exact string equality
/// (`is_pattern=false`, same test `DdSatisfied` itself uses) or a compiled-regex unanchored search
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
/// Whether a result key is a deprecation marker (`@depr:...`).
fn is_depr_key(k : String) -> Bool {
  let p = "@depr:"
  k.length() >= p.length() && k[0:p.length()].to_owned() == p
}

///|
/// 構造化した warnings (spec CONFORMANCE §2 warnings 面素材)。現状 `@depr:` sentinel から
/// `kind: "deprecated"` を組み立てて返す (spec DR-058)。element の重複は排除 (first-seen 順)。
pub fn warnings_of(o : Outcome) -> Array[Warning] {
  let out : Array[Warning] = []
  match o {
    Success(binds) =>
      for b in binds {
        if is_depr_key(b.key) {
          let name = b.key[6:].to_owned()
          let mut seen = false
          for w in out {
            if w.element == name && w.kind == Deprecated {
              seen = true
              break
            }
          }
          if !seen {
            out.push({ element: name, kind: Deprecated })
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
fn is_action_key(k : String) -> Bool {
  let p = "@act:"
  k.length() >= p.length() && k[0:p.length()].to_owned() == p
}

///|
/// Nest a set of bindings one level deeper under `label` (spec DR-025). A
/// LINK binding (spec DR-042 global link-sync) with `levels_to_declaring_scope > 0` ESCAPES this
/// level: it skips the prepend and decrements its counter, climbing out of
/// the scopes BELOW its declaration.
fn nest(label : String, binds : Array[Binding]) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in binds {
    if b.levels_to_declaring_scope > 0 {
      out.push({
        ..b,
        levels_to_declaring_scope: b.levels_to_declaring_scope - 1,
      })
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
/// the same scope-boundary crossings (Scoped / CommandSatisfied) so a path built this
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
///
/// Also mirrors `nest`'s `Binding.levels_to_declaring_scope` decrement (DR-060 §4 / issue
/// 2026-07-14-cand-completer-followup): a candidate with `levels_to_declaring_scope > 0` (set by
/// `Rooted`'s eval arm) is still escaping toward its declaring scope — this level's prepend is
/// SKIPPED and the counter decremented instead, exactly like a linked Binding's `scope` field.
/// Without this, a global option's value-slot candidate would accumulate the COPY-side scope path
/// instead of the DECLARING scope's, and `complete_tree`'s `(path, origin)`-keyed completer lookup
/// would miss the Entity (which lives only at the declaring scope).
///
/// `fire_path` (issue 2026-07-15-pending-parseerror-path-asymmetry) is prepended UNCONDITIONALLY,
/// every call, regardless of `levels_to_declaring_scope` — it tracks the actual walk position (same
/// rule `nest_path` applies to a Held's `ParseError.path`), never the Rooted-escape-adjusted `path`.
/// This is what lets `missing_operand`'s KTop conversion (below) read a path that matches across
/// every duplicate reading of the same starved slot (see `Candidate.fire_path`'s doc comment for why
/// `levels_to_declaring_scope`-gating the KTop conversion instead doesn't work —
/// `levels_to_declaring_scope` is always 0 by the time a candidate reaches KTop).
fn nest_cands(label : String, cs : Array[Candidate]) -> Array[Candidate] {
  let out : Array[Candidate] = []
  for c in cs {
    if c.levels_to_declaring_scope > 0 {
      out.push({
        ..c,
        levels_to_declaring_scope: c.levels_to_declaring_scope - 1,
        fire_path: nest_path(label, c.fire_path),
      })
    } else {
      out.push({
        ..c,
        path: nest_path(label, c.path),
        fire_path: nest_path(label, c.fire_path),
      })
    }
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
      Rejected(pe, bs) =>
        out.push(Rejected({ ..pe, path: nest_path(label, pe.path) }, bs))
      Held(pe, bs) =>
        out.push(Held({ ..pe, path: nest_path(label, pe.path) }, bs))
      Pending(cs, bs) => out.push(Pending(nest_cands(label, cs), bs))
    }
  }
  out
}

///|
/// The `{}` object-presence marker at scope `[label]`. Its numeric value is the same-name command
/// declaration ordinal: presence keeps an invoked empty scope observable, and the ordinal selects
/// the exact declaration during resolve and result projection.
fn scope_marker(label : String, ordinal : Int) -> Binding {
  {
    key: "{}",
    op: Set,
    value: Number(ordinal.to_double()),
    source: Cli,
    scope: [label],
    link_selections: [],
    observation: None,
    source_shadow: None,
    value_residual: [],
    levels_to_declaring_scope: 0,
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
    value: Bool(false),
    source: Cli,
    scope: [label],
    link_selections: [],
    observation: None,
    source_shadow: None,
    value_residual: [],
    levels_to_declaring_scope: 0,
    at_pos: None,
  }
}

///|
/// Evaluate a mandatory resident while preserving value starvation as structural `Pending`.
/// `parse_tree` is the single boundary that converts remaining value candidates to missing-operand
/// diagnostics; intermediate evaluators can therefore distinguish absence from an invalid Held.
fn eval_required_ext(
  extension : &NodeExt,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  next : InternalResume,
) -> Array[Branch] {
  let branches = extension.eval(ctx.extension_context(), pos, acc, fn(
    _,
    next_pos,
    next_acc,
  ) {
    next(ctx, next_pos, next_acc)
  })
  let committed : Array[Branch] = []
  for branch in branches {
    match branch {
      Rejected(error, bindings) => committed.push(Held(error, bindings))
      _ => committed.push(branch)
    }
  }
  committed
}

///|
/// Resume every native matcher reading through one evaluator continuation. The
/// engine owns the common branch loop so all resident-produced readings keep
/// equal standing; residents own only token interpretation and configuration.
pub fn continue_matcher(
  readings : Array[Branch],
  ctx : Ctx,
  acc : Array[Binding],
  next : InternalResume,
) -> Array[Branch] {
  let out : Array[Branch] = []
  for reading in readings {
    match reading {
      Accept(next_pos, bindings) =>
        for branch in next(ctx, next_pos, acc + bindings) {
          out.push(branch)
        }
      Rejected(error, bindings) => out.push(Rejected(error, acc + bindings))
      Held(error, bindings) => out.push(Held(error, acc + bindings))
      Pending(candidates, bindings) =>
        out.push(Pending(candidates, acc + bindings))
    }
  }
  out
}

///|
/// Interpret one opaque matcher with an identity continuation for direct-style
/// probes and off-spine evaluation.
fn run_matcher(matcher : &MatcherExt, ctx : Ctx, pos : Int) -> Array[Branch] {
  if ctx.token_at(pos) is None {
    return []
  }
  matcher.interpret(ctx.extension_context(), pos, [], (_ctx, next_pos, next_acc) => {
    [Accept(next_pos, next_acc)]
  })
}

// ── off-spine node evaluation (direct style) ─────────────────────────────────
//
// Plain `eval` stays direct (returns branches to its caller) — CPS threading
// is needed only where a choice must consult "the rest of the whole parse":
// the scope walk (scope_step / scope_consume) below. A greedy entry's
// internals, matcher readings, Or alternatives etc. are bounded and local.

///|
fn decorate_link_candidates(
  candidates : Array[Candidate],
  origin : String,
  extension : &EntityExt,
) -> Array[Candidate] {
  let decorated : Array[Candidate] = []
  for candidate in candidates {
    decorated.push(extension.complete_candidate({ ..candidate, origin, }))
  }
  decorated
}

///|
/// Evaluate a node at `pos`, returning every reading (Accept), held Error,
/// and pending-value state.
fn eval(node : Node, ctx : Ctx, pos : Int) -> Array[Branch] {
  match node {
    Exact(s) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == s {
        [Accept(pos + 1, [])]
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        // complete (DR-060 §1): the args boundary at a trigger position means
        // this spelling is exactly what could be typed next. `origin` here is
        // just `s` (this bare Exact has no further context of its own) — when
        // this Node sits at the head of an option satellite's Seq, `step_greedy`'s
        // catch-all arm (below) patches origin/hidden up from the satellite's tail
        // (`fixup_boundary_cands`, DR-104 §2/§3); this fallback is what a truly
        // standalone Exact (outside that shape) keeps.
        [Pending([Candidate::trigger(s, s, "flag", WordEnd)], [])]
      } else {
        // an unmatched (or, in parse mode, exhausted) trigger is a silent
        // Reject (spec DR-037), NOT a Pending: no part of the entry was
        // consumed, so nothing is "half-read".
        []
      }
    RequiredArgument(name) => req_arg_eval(name, ctx, pos, [])
    Bind(name, v) => [Accept(pos, [Binding::new(name, v, Cli)])]
    ChildDefault(_, _, _) =>
      eval_with_downstream(
        node,
        ctx,
        pos,
        (_ctx, next_pos, bindings) => [Accept(next_pos, bindings)],
        (_ctx, error, bindings) => [Rejected(error, bindings)],
        (_ctx, error, bindings) => [Held(error, bindings)],
        (_ctx, candidates, bindings) => [Pending(candidates, bindings)],
      )
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
    // the spine form (scope_consume's `Many` arm below) is where is_lazy acts.
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
        [Pending(m.candidates(), [])]
      } else {
        run_matcher(m, ctx, pos)
      }
    Ext(extension) =>
      extension.eval(ctx.extension_context(), pos, [], (
        _ctx,
        next_pos,
        next_acc,
      ) => [Accept(next_pos, next_acc)])
    Ref(name) =>
      match ctx.defs.get(name) {
        Some(tpl) => eval(tpl, ctx, pos)
        None => []
      }
    DdSatisfied(trigger, origin) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == trigger {
        // DR-093 §2/§7: step_greedy の同アームと同じ committed placeholder binding (off-spine
        // evaluation はこの1本の Branch の bindings を返すだけ — 呼び出し元が outer acc と cat する)。
        [
          Accept(pos + 1, [
            Binding::new(origin, Bool(true), Cli, at_pos=Some(pos)),
          ]),
        ]
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([Candidate::trigger(trigger, origin, "flag", WordEnd)], [])]
      } else {
        []
      }
    // DR-090: off-spine mirror of `DdSatisfied`'s own arm above, generalized to pattern matching +
    // self_keep's 0-token Accept. Off-spine evaluation never threads `severed` (that's the SPINE
    // walk's job, `step_greedy`'s own DdMatchSatisfied arm below) — this arm only answers "does this
    // node accept here", same degenerate scope `DdSatisfied`'s off-spine arm already has.
    DdMatchSatisfied(spelling, is_pattern, self_keep, elem_name, origin) =>
      if pos < ctx.toks.length() &&
        dd_match_token(spelling, is_pattern, ctx.toks[pos]) {
        // DR-093 §2/§7: same committed placeholder as the DdSatisfied arm above, keyed by `elem_name`.
        let b = Binding::new(elem_name, Bool(true), Cli, at_pos=Some(pos))
        if self_keep {
          [Accept(pos, [b])]
        } else {
          [Accept(pos + 1, [b])]
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) && !is_pattern {
        // DR-060 §1 completion candidates only make sense for an EXACT spelling (a regex
        // pattern has no single "next token to type" to surface as a candidate).
        // DR-104 §2 origin = 由来要素名: `elem_name` (DR-090 §2, spelling と独立の同一性軸), NOT
        // `spelling` (a `match` trigger's regex-derived literal is not the element's name).
        [Pending([Candidate::trigger(spelling, origin, "flag", WordEnd)], [])]
      } else {
        []
      }
    CommandSatisfied(trigger, name, ordinal, child) =>
      // off-spine command (a probe or a nested context): child evaluated with
      // KDone; bindings nest under the name + presence marker. The greedy
      // face path (step_greedy) threads the real continuation instead.
      // DR-136 §2: the token is matched against the trigger axis; every label
      // below (scope mark / KNest / binding path) stays on the name axis.
      if pos < ctx.toks.length() && ctx.toks[pos] == trigger {
        mark_scope(
          name,
          ordinal,
          nest_branches(
            name,
            scope_step(child, ctx, pos + 1, 0, [], false, KDone),
          ),
        )
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        [Pending([Candidate::trigger(trigger, name, "flag", WordEnd)], [])]
      } else {
        []
      }
    LinkTarget(
      from,
      target,
      target_scope,
      target_tuple_arities,
      target_selections,
      target_observation,
      target_residual,
      levels,
      extension,
      inner
    ) => {
      let out : Array[Branch] = []
      for branch in eval(inner, ctx, pos) {
        match branch {
          Accept(next_pos, bindings) =>
            out.push(
              Accept(
                next_pos,
                bindings_through_link(
                  bindings,
                  from,
                  target,
                  target_scope,
                  target_tuple_arities,
                  target_selections,
                  target_observation,
                  levels,
                  target_residual~,
                ),
              ),
            )
          Rejected(error, bindings) => {
            let linked = bindings_through_link(
              bindings,
              from,
              target,
              target_scope,
              target_tuple_arities,
              target_selections,
              target_observation,
              levels,
              target_residual~,
            )
            // DR-138 §6 (a): 値空間 link の operand は着地座の type のパーサを通り、
            // その失敗は「読みの成立に効く」Error である (淘汰で沈黙させない)。
            // 値残余を持たない link の Reject は従来どおり静かに脱落 (DR-037)。
            if target_residual.length() > 0 {
              out.push(Held(error, linked))
            } else {
              out.push(Rejected(error, linked))
            }
          }
          Held(error, bindings) =>
            out.push(
              Held(
                error,
                bindings_through_link(
                  bindings,
                  from,
                  target,
                  target_scope,
                  target_tuple_arities,
                  target_selections,
                  target_observation,
                  levels,
                  target_residual~,
                ),
              ),
            )
          Pending(candidates, bindings) =>
            out.push(
              Pending(
                decorate_link_candidates(candidates, from, extension),
                bindings_through_link(
                  bindings,
                  from,
                  target,
                  target_scope,
                  target_tuple_arities,
                  target_selections,
                  target_observation,
                  levels,
                  target_residual~,
                ),
              ),
            )
        }
      }
      out
    }
    Rooted(inner, depth) => {
      let out : Array[Branch] = []
      for b in eval(inner, ctx, pos) {
        match b {
          Accept(p, bs) => {
            let marked : Array[Binding] = []
            for x in bs {
              marked.push({
                ..x,
                levels_to_declaring_scope: x.levels_to_declaring_scope + depth,
              })
            }
            out.push(Accept(p, marked))
          }
          Rejected(pe, bs) => out.push(Rejected(pe, bs))
          Held(pe, bs) => out.push(Held(pe, bs))
          Pending(cs, bs) => {
            // Mirror the Accept arm's `levels_to_declaring_scope: depth` marking, but on
            // `Candidate.levels_to_declaring_scope` (DR-060 §4 / issue
            // 2026-07-14-cand-completer-followup): a global option's copied satellite
            // lives `depth` scopes below its OWN declaring scope, and its Entity (the one
            // `complete_tree`'s completer lookup needs) sits at that declaring scope, not
            // here — `nest_cands` (below) consumes this exactly like `nest` consumes
            // `Binding.levels_to_declaring_scope`, skipping `depth` CommandSatisfied-boundary
            // prepends on the way out.
            let marked : Array[Candidate] = []
            for c in cs {
              marked.push({ ..c, levels_to_declaring_scope: depth })
            }
            out.push(Pending(marked, bs))
          }
        }
      }
      out
    }
    IndexedRepeat(label, head, min, budget) =>
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
fn has_rejected(branches : Array[Branch]) -> Bool {
  for branch in branches {
    if branch is Rejected(_, _) {
      return true
    }
  }
  false
}

///|
/// Evaluate the structural wrappers that may contain `ChildDefault` while threading the real
/// downstream continuation. Ordinary leaves retain `eval` semantics; only the default-seat choice
/// needs to inspect whether its consuming reading reaches a complete path.
fn eval_with_downstream(
  node : Node,
  ctx : Ctx,
  pos : Int,
  on_accept : InternalResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
  on_severed_accept? : InternalResume? = None,
  consume_scope? : Scope? = None,
  severed? : Bool = false,
) -> Array[Branch] {
  let resume_severed = match on_severed_accept {
    Some(callback) => callback
    None => on_accept
  }
  match node {
    ChildDefault(head, seat_key, element_name) => {
      let direct_held : Array[(ParseError, Array[Binding])] = []
      let consuming = eval_with_downstream(
        head,
        ctx,
        pos,
        on_accept,
        on_rejected,
        (_ctx, error, bindings) => {
          direct_held.push((error, bindings))
          []
        },
        (ctx2, candidates, bindings) => {
          if in_complete(ctx2) {
            on_pending(ctx2, candidates, bindings)
          } else {
            []
          }
        },
        on_severed_accept=Some(resume_severed),
        consume_scope~,
        severed~,
      )
      if has_full_k(consuming) {
        consuming
      } else if direct_held.length() > 0 {
        let held : Array[Branch] = []
        for item in direct_held {
          for branch in on_held(ctx, item.0, item.1) {
            held.push(branch)
          }
        }
        if has_rejected(eval(head, ctx, pos)) {
          cat_branches(
            on_accept(ctx, pos, [
              Binding::new(seat_key, String(element_name), Cli),
            ]),
            held,
          )
        } else {
          held
        }
      } else {
        cat_branches(
          on_accept(ctx, pos, [
            Binding::new(seat_key, String(element_name), Cli),
          ]),
          consuming,
        )
      }
    }
    Seq(items) =>
      eval_seq_with_downstream(
        items,
        0,
        ctx,
        pos,
        [],
        on_accept,
        on_rejected,
        on_held,
        on_pending,
        resume_severed,
        consume_scope,
        severed,
      )
    Or(alternatives) => {
      let out : Array[Branch] = []
      for alternative in alternatives {
        for
          branch in eval_with_downstream(
            alternative,
            ctx,
            pos,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
            on_severed_accept=Some(resume_severed),
            consume_scope~,
            severed~,
          ) {
          out.push(branch)
        }
      }
      out
    }
    Ref(name) =>
      match ctx.defs.get(name) {
        Some(template) =>
          eval_with_downstream(
            template,
            ctx,
            pos,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
            on_severed_accept=Some(resume_severed),
            consume_scope~,
            severed~,
          )
        None => []
      }
    Scoped(label, body) =>
      eval_with_downstream(
        body,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          on_accept(ctx2, next_pos, nest(label, bindings))
        },
        (ctx2, error, bindings) => {
          on_rejected(
            ctx2,
            { ..error, path: nest_path(label, error.path) },
            bindings,
          )
        },
        (ctx2, error, bindings) => {
          on_held(
            ctx2,
            { ..error, path: nest_path(label, error.path) },
            bindings,
          )
        },
        (ctx2, candidates, bindings) => {
          on_pending(ctx2, nest_cands(label, candidates), bindings)
        },
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          resume_severed(ctx2, next_pos, nest(label, bindings))
        }),
        consume_scope~,
        severed~,
      )
    LinkTarget(
      from,
      target,
      target_scope,
      target_tuple_arities,
      target_selections,
      target_observation,
      target_residual,
      levels,
      extension,
      inner
    ) =>
      eval_with_downstream(
        inner,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          on_accept(
            ctx2,
            next_pos,
            bindings_through_link(
              bindings,
              from,
              target,
              target_scope,
              target_tuple_arities,
              target_selections,
              target_observation,
              levels,
              target_residual~,
            ),
          )
        },
        (ctx2, error, bindings) => {
          let linked = bindings_through_link(
            bindings,
            from,
            target,
            target_scope,
            target_tuple_arities,
            target_selections,
            target_observation,
            levels,
            target_residual~,
          )
          // DR-138 §6 (a): 値空間 link の operand 失敗は Error 位相 (上記 2 箇所と同規則)。
          // ここは CPS 版の downstream 経路で、変換が抜けていると同じ失敗が読みによって
          // Reject / Error に割れる。
          if target_residual.length() > 0 {
            on_held(ctx2, error, linked)
          } else {
            on_rejected(ctx2, error, linked)
          }
        },
        (ctx2, error, bindings) => {
          on_held(
            ctx2,
            error,
            bindings_through_link(
              bindings,
              from,
              target,
              target_scope,
              target_tuple_arities,
              target_selections,
              target_observation,
              levels,
              target_residual~,
            ),
          )
        },
        (ctx2, candidates, bindings) => {
          on_pending(
            ctx2,
            decorate_link_candidates(candidates, from, extension),
            bindings_through_link(
              bindings,
              from,
              target,
              target_scope,
              target_tuple_arities,
              target_selections,
              target_observation,
              levels,
              target_residual~,
            ),
          )
        },
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          resume_severed(
            ctx2,
            next_pos,
            bindings_through_link(
              bindings,
              from,
              target,
              target_scope,
              target_tuple_arities,
              target_selections,
              target_observation,
              levels,
              target_residual~,
            ),
          )
        }),
        consume_scope~,
        severed~,
      )
    Rooted(inner, depth) =>
      eval_with_downstream(
        inner,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          let marked : Array[Binding] = []
          for binding in bindings {
            marked.push({
              ..binding,
              levels_to_declaring_scope: binding.levels_to_declaring_scope +
              depth,
            })
          }
          on_accept(ctx2, next_pos, marked)
        },
        on_rejected,
        on_held,
        (ctx2, candidates, bindings) => {
          let marked : Array[Candidate] = []
          for candidate in candidates {
            marked.push({ ..candidate, levels_to_declaring_scope: depth })
          }
          on_pending(ctx2, marked, bindings)
        },
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          let marked : Array[Binding] = []
          for binding in bindings {
            marked.push({
              ..binding,
              levels_to_declaring_scope: binding.levels_to_declaring_scope +
              depth,
            })
          }
          resume_severed(ctx2, next_pos, marked)
        }),
        consume_scope~,
        severed~,
      )
    ScopeNode(sc) =>
      eval_scope_with_downstream(
        sc,
        ctx,
        pos,
        0,
        [],
        severed,
        (ctx2, next_pos, bindings, was_severed) => {
          if was_severed {
            resume_severed(ctx2, next_pos, bindings)
          } else {
            on_accept(ctx2, next_pos, bindings)
          }
        },
        on_rejected,
        on_held,
        on_pending,
      )
    Many(inner, is_lazy) =>
      eval_many_with_downstream(
        inner,
        ctx,
        pos,
        [],
        is_lazy,
        on_accept,
        on_rejected,
        on_held,
        on_pending,
        resume_severed,
        consume_scope,
        severed,
      )
    IndexedRepeat(label, head, min, budget) =>
      eval_indexed_with_downstream(
        label,
        head,
        min,
        budget,
        ctx,
        pos,
        [],
        0,
        on_accept,
        on_rejected,
        on_held,
        on_pending,
        resume_severed,
        consume_scope,
        severed,
      )
    BoundedTail(head, budget, is_lazy) =>
      eval_bounded_with_downstream(
        head,
        budget,
        is_lazy,
        ctx,
        pos,
        [],
        on_accept,
        on_rejected,
        on_held,
        on_pending,
        resume_severed,
        consume_scope,
        severed,
      )
    GreedyRepeat(tail) =>
      eval_with_downstream(
        tail,
        ctx,
        pos,
        on_accept,
        on_rejected,
        on_held,
        on_pending,
        on_severed_accept=Some(resume_severed),
        consume_scope~,
        severed~,
      )
    other => {
      let out : Array[Branch] = []
      let branches = match consume_scope {
        Some(scope) => consume_compound(scope, other, ctx, pos, severed)
        None => eval(other, ctx, pos)
      }
      for branch in branches {
        let resumed = match branch {
          Accept(next_pos, bindings) => on_accept(ctx, next_pos, bindings)
          Rejected(error, bindings) => on_rejected(ctx, error, bindings)
          Held(error, bindings) => on_held(ctx, error, bindings)
          Pending(candidates, bindings) => on_pending(ctx, candidates, bindings)
        }
        for result in resumed {
          out.push(result)
        }
      }
      out
    }
  }
}

///|
fn eval_seq_with_downstream(
  items : Array[Node],
  index : Int,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  on_accept : InternalResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
  on_severed_accept : InternalResume,
  consume_scope : Scope?,
  severed : Bool,
) -> Array[Branch] {
  if index >= items.length() {
    return on_accept(ctx, pos, acc)
  }
  eval_with_downstream(
    items[index],
    ctx,
    pos,
    (ctx2, next_pos, bindings) => {
      eval_seq_with_downstream(
        items,
        index + 1,
        ctx2,
        next_pos,
        acc + bindings,
        on_accept,
        on_rejected,
        on_held,
        on_pending,
        on_severed_accept,
        consume_scope,
        severed,
      )
    },
    (ctx2, error, bindings) => on_rejected(ctx2, error, acc + bindings),
    (ctx2, error, bindings) => on_held(ctx2, error, acc + bindings),
    (ctx2, candidates, bindings) => on_pending(ctx2, candidates, acc + bindings),
    on_severed_accept=Some((ctx2, next_pos, bindings) => {
      eval_seq_with_downstream(
        items,
        index + 1,
        ctx2,
        next_pos,
        acc + bindings,
        on_severed_accept,
        on_rejected,
        on_held,
        on_pending,
        on_severed_accept,
        consume_scope,
        true,
      )
    }),
    consume_scope~,
    severed~,
  )
}

///|
/// Apply the shared repeat split policy. Parse mode commits to the preferred first complete share;
/// complete mode keeps every surviving partial because each Pending contributes candidate material.
fn choose_repeat_share(
  ctx : Ctx,
  stop : Array[Branch],
  more : Array[Branch],
  is_lazy : Bool,
) -> Array[Branch] {
  if in_complete(ctx) {
    cat_branches(stop, more)
  } else if is_lazy {
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
/// Downstream-aware unbounded repeat used when `Many` appears below a structural wrapper rather than
/// directly as a scope spine slot. Every repetition re-enters this helper, so a nested ChildDefault
/// tests its consuming reading against the same final continuation as the enclosing node.
fn eval_many_with_downstream(
  inner : Node,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  is_lazy : Bool,
  on_accept : InternalResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
  on_severed_accept : InternalResume,
  consume_scope : Scope?,
  severed : Bool,
) -> Array[Branch] {
  let stop = if severed {
    on_severed_accept(ctx, pos, acc)
  } else {
    on_accept(ctx, pos, acc)
  }
  let more_raw = eval_with_downstream(
    inner,
    ctx,
    pos,
    (ctx2, next_pos, bindings) => {
      if next_pos > pos {
        eval_many_with_downstream(
          inner,
          ctx2,
          next_pos,
          acc + bindings,
          is_lazy,
          on_accept,
          on_rejected,
          on_held,
          on_pending,
          on_severed_accept,
          consume_scope,
          severed,
        )
      } else {
        []
      }
    },
    (ctx2, error, bindings) => on_rejected(ctx2, error, acc + bindings),
    (ctx2, error, bindings) => on_held(ctx2, error, acc + bindings),
    (ctx2, candidates, bindings) => on_pending(ctx2, candidates, acc + bindings),
    on_severed_accept=Some((ctx2, next_pos, bindings) => {
      eval_many_with_downstream(
        inner,
        ctx2,
        next_pos,
        acc + bindings,
        is_lazy,
        on_severed_accept,
        on_rejected,
        on_held,
        on_pending,
        on_severed_accept,
        consume_scope,
        true,
      )
    }),
    consume_scope~,
    severed~,
  )
  let more = drop_optional_missing(ctx, more_raw, head_elem_names(inner))
  choose_repeat_share(ctx, stop, more, is_lazy)
}

///|
/// Downstream-aware bounded repeat. The optional-more branch filters only missing operands belonging
/// to its own head; failures from the outer continuation remain observable.
fn eval_bounded_with_downstream(
  head : Node,
  budget : Int,
  is_lazy : Bool,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  on_accept : InternalResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
  on_severed_accept : InternalResume,
  consume_scope : Scope?,
  severed : Bool,
) -> Array[Branch] {
  let stop = if severed {
    on_severed_accept(ctx, pos, acc)
  } else {
    on_accept(ctx, pos, acc)
  }
  let more_raw = if budget >= 1 {
    eval_with_downstream(
      head,
      ctx,
      pos,
      (ctx2, next_pos, bindings) => {
        if next_pos > pos {
          eval_bounded_with_downstream(
            head,
            budget - 1,
            is_lazy,
            ctx2,
            next_pos,
            acc + bindings,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
            on_severed_accept,
            consume_scope,
            severed,
          )
        } else {
          []
        }
      },
      (ctx2, error, bindings) => on_rejected(ctx2, error, acc + bindings),
      (ctx2, error, bindings) => on_held(ctx2, error, acc + bindings),
      (ctx2, candidates, bindings) => {
        on_pending(ctx2, candidates, acc + bindings)
      },
      on_severed_accept=Some((ctx2, next_pos, bindings) => {
        eval_bounded_with_downstream(
          head,
          budget - 1,
          is_lazy,
          ctx2,
          next_pos,
          acc + bindings,
          on_severed_accept,
          on_rejected,
          on_held,
          on_pending,
          on_severed_accept,
          consume_scope,
          true,
        )
      }),
      consume_scope~,
      severed~,
    )
  } else {
    []
  }
  let more = drop_optional_missing(ctx, more_raw, head_elem_names(head))
  choose_repeat_share(ctx, stop, more, is_lazy)
}

///|
/// Downstream-aware named row repeat. The row marker and `#index` nesting are accumulated before the
/// outer continuation runs, while each stop/more decision still sees the whole remaining parse.
fn eval_indexed_with_downstream(
  label : String,
  head : Node,
  min : Int,
  budget : Int?,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  rep : Int,
  on_accept : InternalResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
  on_severed_accept : InternalResume,
  consume_scope : Scope?,
  severed : Bool,
) -> Array[Branch] {
  let acc2 = if rep == 0 { acc + [array_marker(label)] } else { acc }
  let stop = if rep >= min {
    if severed {
      on_severed_accept(ctx, pos, acc2)
    } else {
      on_accept(ctx, pos, acc2)
    }
  } else {
    []
  }
  let at_budget = match budget {
    Some(extra) => rep >= min + extra
    None => false
  }
  let more = if at_budget {
    []
  } else {
    eval_with_downstream(
      head,
      ctx,
      pos,
      (ctx2, next_pos, bindings) => {
        if next_pos > pos {
          eval_indexed_with_downstream(
            label,
            head,
            min,
            budget,
            ctx2,
            next_pos,
            acc2 + nest_index(label, rep, bindings),
            rep + 1,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
            on_severed_accept,
            consume_scope,
            severed,
          )
        } else {
          []
        }
      },
      (ctx2, error, bindings) => on_rejected(ctx2, error, acc2 + bindings),
      (ctx2, error, bindings) => {
        if rep < min || error.args_pos < ctx2.toks.length() {
          on_held(ctx2, error, acc2 + bindings)
        } else {
          []
        }
      },
      (ctx2, candidates, bindings) => {
        on_pending(ctx2, candidates, acc2 + bindings)
      },
      on_severed_accept=Some((ctx2, next_pos, bindings) => {
        eval_indexed_with_downstream(
          label,
          head,
          min,
          budget,
          ctx2,
          next_pos,
          acc2 + nest_index(label, rep, bindings),
          rep + 1,
          on_severed_accept,
          on_rejected,
          on_held,
          on_pending,
          on_severed_accept,
          consume_scope,
          true,
        )
      }),
      consume_scope~,
      severed~,
    )
  }
  choose_repeat_share(ctx, stop, more, false)
}

///|
/// Nest only bindings produced since `start`, matching the KNest continuation frame without placing
/// a closure inside Cont.
fn nest_since(
  label : String,
  command_ordinal : Int,
  is_command : Bool,
  start : Int,
  acc : Array[Binding],
) -> Array[Binding] {
  let before : Array[Binding] = []
  let inside : Array[Binding] = []
  let mut index = 0
  for binding in acc {
    if index < start {
      before.push(binding)
    } else {
      inside.push(binding)
    }
    index = index + 1
  }
  let out : Array[Binding] = []
  for binding in before {
    out.push(binding)
  }
  if is_command {
    out.push(scope_marker(label, command_ordinal))
  }
  for binding in nest(label, inside) {
    out.push(binding)
  }
  out
}

///|
/// Companion scope walk for a ScopeNode reached inside `eval_with_downstream`. It mirrors the normal
/// two-face walk, but its scope-end action is the caller's downstream callback instead of KDone. This
/// is deliberately separate from Cont: the ordinary scope path remains fully defunctionalized and
/// structurally Eq/Debug/cacheable.
fn eval_scope_with_downstream(
  sc : Scope,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  on_accept : InternalScopeResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
) -> Array[Branch] {
  let out : Array[Branch] = []
  if !severed {
    let cut_triggers : Array[String] = []
    let value_slot_nodes : Array[Node] = []
    for greedy in sc.greedy {
      match value_slot_trigger(greedy) {
        Some(trigger) => {
          value_slot_nodes.push(greedy)
          if has_accept(eval(greedy, ctx, pos)) {
            cut_triggers.push(trigger)
          }
          eval_greedy_with_downstream(
            greedy, sc, ctx, pos, pidx, acc, severed, on_accept, on_rejected, on_held,
            on_pending, out,
          )
        }
        None => ()
      }
    }
    for greedy in sc.greedy {
      let mut already = false
      for value_slot in value_slot_nodes {
        if value_slot == greedy {
          already = true
        }
      }
      if already {
        continue
      }
      match zero_arg_variant_trigger(greedy) {
        Some(trigger) => {
          let mut cut = false
          for candidate in cut_triggers {
            if candidate == trigger {
              cut = true
            }
          }
          if !cut {
            eval_greedy_with_downstream(
              greedy, sc, ctx, pos, pidx, acc, severed, on_accept, on_rejected, on_held,
              on_pending, out,
            )
          }
        }
        None =>
          eval_greedy_with_downstream(
            greedy, sc, ctx, pos, pidx, acc, severed, on_accept, on_rejected, on_held,
            on_pending, out,
          )
      }
    }
  }
  if pidx >= sc.positional.length() {
    if severed {
      for branch in on_accept(ctx, pos, acc, severed) {
        out.push(branch)
      }
    } else if !greedy_reads(sc, ctx, pos, acc) {
      let drop_redundant_residual = any_trigger_matches(sc, ctx, pos, acc)
      for branch in on_accept(ctx, pos, acc, severed) {
        match branch {
          Held(error, _) =>
            if drop_redundant_residual &&
              is_scope_residual(error) &&
              error.args_pos == pos {
              ()
            } else {
              out.push(branch)
            }
          _ => out.push(branch)
        }
      }
    }
  } else {
    for
      branch in eval_scope_item_with_downstream(
        sc,
        sc.positional[pidx],
        ctx,
        pos,
        pidx,
        acc,
        severed,
        on_accept,
        on_rejected,
        on_held,
        on_pending,
      ) {
      out.push(branch)
    }
  }
  out
}

///|
fn eval_greedy_with_downstream(
  node : Node,
  sc : Scope,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  on_accept : InternalScopeResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
  out : Array[Branch],
) -> Unit {
  match node {
    CommandSatisfied(trigger, name, ordinal, child) =>
      // 一度この scope から入場した宣言のトリガは、同じ読みの中で**再び材料にならない**
      // (同ファイル完了面の同条件と同じ規則 — KNest が選択済み宣言を記録するので
      // `command_scope_selected` で判定できる)。command scope の結果キーは 1 つの器で
      // あり、同一宣言の 2 回目の入場は着地先を持たない — 許すと同一 scope path・
      // 同一 ordinal のマーカーが並び、occurrence を区別できない読みが完全経路として
      // 数えられてしまう (issue dup-raw-command-ordinal-marker-occurrence-gap)。
      if pos < ctx.toks.length() &&
        ctx.toks[pos] == trigger &&
        !command_scope_selected(acc, [name], ordinal) {
        let start = acc.length()
        for
          branch in eval_scope_with_downstream(
            child,
            ctx,
            pos + 1,
            0,
            acc,
            false,
            (ctx2, next_pos, bindings, child_severed) => {
              eval_scope_with_downstream(
                sc,
                ctx2,
                next_pos,
                pidx,
                nest_since(name, ordinal, true, start, bindings),
                severed || child_severed,
                on_accept,
                on_rejected,
                on_held,
                on_pending,
              )
            },
            on_rejected,
            on_held,
            on_pending,
          ) {
          match branch {
            Rejected(error, bindings) =>
              out.push(
                Rejected(
                  { ..error, path: nest_path(name, error.path) },
                  bindings,
                ),
              )
            Held(error, bindings) =>
              out.push(
                Held({ ..error, path: nest_path(name, error.path) }, bindings),
              )
            Pending(candidates, bindings) =>
              out.push(Pending(nest_cands(name, candidates), bindings))
            Accept(_, _) => out.push(branch)
          }
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        out.push(
          Pending([Candidate::trigger(trigger, name, "flag", WordEnd)], acc),
        )
      }
    DdSatisfied(trigger, origin) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == trigger {
        let acc2 = acc +
          [Binding::new(origin, Bool(true), Cli, at_pos=Some(pos))]
        for
          branch in eval_scope_with_downstream(
            sc,
            ctx,
            pos + 1,
            pidx,
            acc2,
            true,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          ) {
          out.push(branch)
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        out.push(
          Pending([Candidate::trigger(trigger, origin, "flag", WordEnd)], acc),
        )
      }
    DdMatchSatisfied(spelling, is_pattern, self_keep, elem_name, origin) =>
      if pos < ctx.toks.length() &&
        dd_match_token(spelling, is_pattern, ctx.toks[pos]) {
        let resume_pos = if self_keep { pos } else { pos + 1 }
        let acc2 = acc +
          [Binding::new(elem_name, Bool(true), Cli, at_pos=Some(pos))]
        for
          branch in eval_scope_with_downstream(
            sc, ctx, resume_pos, pidx, acc2, true, on_accept, on_rejected, on_held,
            on_pending,
          ) {
          out.push(branch)
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) && !is_pattern {
        out.push(
          Pending([Candidate::trigger(spelling, origin, "flag", WordEnd)], acc),
        )
      }
    Or(alternatives) =>
      for alternative in alternatives {
        eval_greedy_with_downstream(
          alternative, sc, ctx, pos, pidx, acc, severed, on_accept, on_rejected,
          on_held, on_pending, out,
        )
      }
    _ =>
      match greedy_repeat_split(node) {
        Some((prefix, tail)) =>
          eval_greedy_repeat_with_downstream(
            prefix, tail, sc, ctx, pos, pidx, acc, severed, on_accept, on_rejected,
            on_held, on_pending, out,
          )
        None =>
          for
            branch in eval_with_downstream(
              node,
              ctx,
              pos,
              (ctx2, next_pos, bindings) => {
                if next_pos > pos {
                  eval_scope_with_downstream(
                    sc,
                    ctx2,
                    next_pos,
                    pidx,
                    acc + bindings,
                    severed,
                    on_accept,
                    on_rejected,
                    on_held,
                    on_pending,
                  )
                } else {
                  []
                }
              },
              (ctx2, error, bindings) => {
                on_rejected(ctx2, error, acc + bindings)
              },
              (ctx2, error, bindings) => on_held(ctx2, error, acc + bindings),
              (ctx2, candidates, bindings) => {
                on_pending(
                  ctx2,
                  fixup_boundary_cands(node, sc, candidates),
                  acc + bindings,
                )
              },
              on_severed_accept=Some((ctx2, next_pos, bindings) => {
                if next_pos > pos {
                  eval_scope_with_downstream(
                    sc,
                    ctx2,
                    next_pos,
                    pidx,
                    acc + bindings,
                    true,
                    on_accept,
                    on_rejected,
                    on_held,
                    on_pending,
                  )
                } else {
                  []
                }
              }),
              severed~,
            ) {
            out.push(branch)
          }
      }
  }
}

///|
fn eval_greedy_repeat_with_downstream(
  prefix : Node,
  tail : Node,
  sc : Scope,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  on_accept : InternalScopeResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
  out : Array[Branch],
) -> Unit {
  for branch in eval(prefix, ctx, pos) {
    match branch {
      Accept(next_pos, prefix_bindings) => {
        let wrap_sc : Scope = {
          greedy: sc.greedy,
          positional: [tail],
          entities: [],
          constraints: [],
        }
        for
          result in eval_scope_with_downstream(
            wrap_sc,
            ctx,
            next_pos,
            0,
            [],
            severed,
            (ctx2, tail_pos, tail_bindings, tail_severed) => {
              eval_scope_with_downstream(
                sc,
                ctx2,
                tail_pos,
                pidx,
                acc + (prefix_bindings + tail_bindings),
                severed || tail_severed,
                on_accept,
                on_rejected,
                on_held,
                on_pending,
              )
            },
            (ctx2, error, tail_bindings) => {
              on_rejected(ctx2, error, acc + (prefix_bindings + tail_bindings))
            },
            (ctx2, error, tail_bindings) => {
              on_held(ctx2, error, acc + (prefix_bindings + tail_bindings))
            },
            (ctx2, candidates, tail_bindings) => {
              on_pending(
                ctx2,
                candidates,
                acc + (prefix_bindings + tail_bindings),
              )
            },
          ) {
          out.push(result)
        }
      }
      Rejected(error, bindings) =>
        for result in on_rejected(ctx, error, acc + bindings) {
          out.push(result)
        }
      Held(error, bindings) =>
        for result in on_held(ctx, error, acc + bindings) {
          out.push(result)
        }
      Pending(candidates, bindings) =>
        for result in on_pending(ctx, candidates, acc + bindings) {
          out.push(result)
        }
    }
  }
}

///|
fn eval_scope_item_with_downstream(
  sc : Scope,
  item : Node,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  on_accept : InternalScopeResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
) -> Array[Branch] {
  match item {
    Ext(extension) =>
      if extension.consumes_zero_tokens() ||
        pos >= ctx.toks.length() ||
        !suppressed(sc, ctx, pos, severed) {
        eval_required_ext(extension, ctx, pos, acc, (ctx2, next_pos, next_acc) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            next_acc,
            severed,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        })
      } else {
        []
      }
    RequiredArgument(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        eval_scope_with_downstream(
          sc,
          ctx,
          pos + 1,
          pidx + 1,
          acc +
          [Binding::new(name, String(ctx.toks[pos]), Cli, at_pos=Some(pos))],
          severed,
          on_accept,
          on_rejected,
          on_held,
          on_pending,
        )
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          on_pending(ctx, [Candidate::pending_value("string", name)], acc)
        } else {
          on_held(
            ctx,
            {
              element: name,
              args_pos: pos,
              kind: Constraint,
              reason: "required_violated",
              message: "required \{name} is missing",
              path: [],
            },
            acc,
          )
        }
      } else {
        []
      }
    Exact(spelling) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == spelling {
        eval_scope_with_downstream(
          sc,
          ctx,
          pos + 1,
          pidx + 1,
          acc,
          severed,
          on_accept,
          on_rejected,
          on_held,
          on_pending,
        )
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        on_pending(
          ctx,
          [Candidate::trigger(spelling, spelling, "flag", WordEnd)],
          acc,
        )
      } else {
        []
      }
    Ref(name) =>
      match ref_head(ctx.defs, name) {
        head =>
          eval_with_downstream(
            head,
            ctx,
            pos,
            (ctx2, next_pos, bindings) => {
              if next_pos > pos {
                eval_ref_choice_with_downstream(
                  sc,
                  name,
                  ctx2,
                  next_pos,
                  pidx,
                  acc + bindings,
                  severed,
                  on_accept,
                  on_rejected,
                  on_held,
                  on_pending,
                )
              } else {
                []
              }
            },
            (ctx2, error, bindings) => on_rejected(ctx2, error, acc + bindings),
            (ctx2, error, bindings) => on_held(ctx2, error, acc + bindings),
            (ctx2, candidates, bindings) => {
              on_pending(ctx2, candidates, acc + bindings)
            },
            on_severed_accept=Some((ctx2, next_pos, bindings) => {
              if next_pos > pos {
                eval_ref_choice_with_downstream(
                  sc,
                  name,
                  ctx2,
                  next_pos,
                  pidx,
                  acc + bindings,
                  true,
                  on_accept,
                  on_rejected,
                  on_held,
                  on_pending,
                )
              } else {
                []
              }
            }),
            consume_scope=Some(sc),
            severed~,
          )
      }
    IndexedRepeat(label, head, min, budget) =>
      eval_indexed_with_downstream(
        label,
        head,
        min,
        budget,
        ctx,
        pos,
        acc,
        0,
        (ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            bindings,
            severed,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        on_rejected,
        on_held,
        on_pending,
        (ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            bindings,
            true,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        Some(sc),
        severed,
      )
    BoundedTail(head, budget, is_lazy) =>
      eval_bounded_with_downstream(
        head,
        budget,
        is_lazy,
        ctx,
        pos,
        acc,
        (ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            bindings,
            severed,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        on_rejected,
        on_held,
        on_pending,
        (ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            bindings,
            true,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        Some(sc),
        severed,
      )
    Many(inner, is_lazy) =>
      eval_many_with_downstream(
        inner,
        ctx,
        pos,
        acc,
        is_lazy,
        (ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            bindings,
            severed,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        on_rejected,
        on_held,
        on_pending,
        (ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            bindings,
            true,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        Some(sc),
        severed,
      )
    ScopeNode(child) =>
      eval_scope_with_downstream(
        child,
        ctx,
        pos,
        0,
        acc,
        severed,
        (ctx2, next_pos, bindings, child_severed) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            bindings,
            severed || child_severed,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        on_rejected,
        on_held,
        on_pending,
      )
    other =>
      eval_with_downstream(
        other,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            acc + bindings,
            severed,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        },
        (ctx2, error, bindings) => on_rejected(ctx2, error, acc + bindings),
        (ctx2, error, bindings) => on_held(ctx2, error, acc + bindings),
        (ctx2, candidates, bindings) => {
          on_pending(ctx2, candidates, acc + bindings)
        },
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          eval_scope_with_downstream(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            acc + bindings,
            true,
            on_accept,
            on_rejected,
            on_held,
            on_pending,
          )
        }),
        consume_scope=Some(sc),
        severed~,
      )
  }
}

///|
fn eval_ref_choice_with_downstream(
  sc : Scope,
  name : String,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  on_accept : InternalScopeResume,
  on_rejected : InternalRejectedResume,
  on_held : InternalHeldResume,
  on_pending : InternalPendingResume,
) -> Array[Branch] {
  let head = ref_head(ctx.defs, name)
  let stop = eval_scope_with_downstream(
    sc,
    ctx,
    pos,
    pidx + 1,
    acc,
    severed,
    on_accept,
    on_rejected,
    on_held,
    on_pending,
  )
  let more = drop_optional_missing(
    ctx,
    eval_scope_with_downstream(
      sc, ctx, pos, pidx, acc, severed, on_accept, on_rejected, on_held, on_pending,
    ),
    head_elem_names(head),
  )
  choose_repeat_share(ctx, stop, more, ref_is_lazy(ctx.defs, name))
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
/// token to consume (構造的必須の不成立, spec DR-065 §3): args_pos = args
/// length (where the token was requested).
fn pe_missing(element : String, pos : Int) -> ParseError {
  {
    element,
    args_pos: pos,
    kind: Parse,
    reason: "missing_operand",
    message: "missing operand for \{element}",
    path: [],
  }
}

///|
/// A scope-level residual has no element owner. This structural sentinel is distinct from every
/// resident error and lets evaluator control flow avoid inspecting the open reason vocabulary.
fn is_scope_residual(error : ParseError) -> Bool {
  error.element == "" && error.kind is Parse
}

///|
/// RequiredArgument (spec DR-047 / DR-053 kind: constraint): NO token to consume is a
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
        acc + [Binding::new(name, String(ctx.toks[pos]), Cli, at_pos=Some(pos))],
      ),
    ]
  } else if in_complete(ctx) {
    [Pending([Candidate::pending_value("string", name)], acc)]
  } else {
    [
      Held(
        {
          element: name,
          args_pos: pos,
          kind: Constraint,
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
/// Prepend the `{}` presence marker to each Accept.
fn mark_scope(
  name : String,
  ordinal : Int,
  brs : Array[Branch],
) -> Array[Branch] {
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Accept(p, bs) => out.push(Accept(p, [scope_marker(name, ordinal)] + bs))
      Rejected(pe, bs) => out.push(Rejected(pe, bs))
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
    if b.levels_to_declaring_scope > 0 {
      out.push({
        ..b,
        levels_to_declaring_scope: b.levels_to_declaring_scope - 1,
      })
    } else {
      let sc2 : Array[String] = [label, seg]
      for s in b.scope {
        sc2.push(s)
      }
      out.push({ ..b, scope: sc2, levels_to_declaring_scope: 0 })
    }
  }
  out
}

///|
/// Off-spine fallback for a named indexed-array repeat. The positional spine uses
/// `indexed_repeat_step` below so stop/more preference sees the full continuation.
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
      Pending(cs, bs) => out.push(Pending(cs, acc + bs))
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
      Rejected(_, _) | Held(_, _) => ()
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
        for r in eval_seq(items, idx + 1, ctx, p2, acc + bs) {
          out.push(r)
        }
      // the Held carries the Seq's accumulated partial state too: a marker
      // bound EARLIER in the same entry (e.g. `--help`'s failure resident before a
      // failing value slot) must reach parse() for fired_action selection
      // (DR-048 / DR-053 §4 共存). The slice dropped acc here — a defect the
      // adversarial review caught, not a parity to keep.
      Rejected(pe, bs) => out.push(Rejected(pe, acc + bs))
      Held(pe, bs) => out.push(Held(pe, acc + bs))
      Pending(cs, bs) => out.push(Pending(cs, acc + bs))
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
          for r in eval_many(inner, ctx, p2, acc + bs) {
            out.push(r)
          }
        }
      Rejected(pe, bs) => out.push(Rejected(pe, acc + bs))
      Held(pe, bs) => out.push(Held(pe, acc + bs))
      // a Pending after >= 1 successful reps still carries the reps' acc
      // (same contract as eval_seq: Pending = starved branch WITH its state).
      Pending(cs, bs) => out.push(Pending(cs, acc + bs))
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
/// VIABLE reading. An advancing Accept is viable. Rejected is never viable. A Held on the first
/// value slot after a trigger has not established the reading, while a later Held means an earlier
/// slot already consumed input and the compound reading remains engaged. Pending is mode-dependent:
/// `eval`'s value-primitive arms
/// (string resident/number resident/etc.) return an EXPLICIT Pending at
/// args end REGARDLESS of mode (their own doc comment: "the end of input at
/// a value slot is an explicit Pending, not a silent []" — an off-spine/
/// completion-probe design predating DR-097). In parse mode that Pending IS
/// DR-097's "missing operand" (a value slot starved at args end) and must
/// NOT count as viable, or a value-less trigger at the tail of args would
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
      Rejected(_, _) => ()
      Held(error, _) => if error.args_pos > pos + 1 { return true }
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
/// the trigger fires, UNCONDITIONALLY — this is why CommandSatisfied/DdSatisfied/DdMatchSatisfied
/// stay a bare structural trigger test below rather than routing through
/// the shallow `eval` probe: a CommandSatisfied's "value slot" is its entire child
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
fn greedy_engages(g : Node, ctx : Ctx, pos : Int, acc : Array[Binding]) -> Bool {
  match g {
    Or(alts) => {
      for a in alts {
        if greedy_engages(a, ctx, pos, acc) {
          return true
        }
      }
      false
    }
    // 入場済みの宣言は、この読みではもう受け手ではない (同ファイルの CommandSatisfied
    // 入場条件と同じ規則)。ここを true のままにすると、早閉じ判定が「親が読める」と
    // 誤答し、かつ入場側は空を返すので、**診断を 1 件も伴わない失敗**になる
    // (`greedy_trigger_matches` の doc が言う「より具体的な Held が既に積まれている」
    // という前提が崩れる)。
    CommandSatisfied(trigger, name, ordinal, _) =>
      ctx.toks[pos] == trigger && !command_scope_selected(acc, [name], ordinal)
    DdSatisfied(t, _) => ctx.toks[pos] == t
    DdMatchSatisfied(spelling, is_pattern, _, _, _) =>
      dd_match_token(spelling, is_pattern, ctx.toks[pos])
    LinkTarget(_, _, _, _, _, _, _, _, _, inner) =>
      greedy_engages(inner, ctx, pos, acc)
    Rooted(inner, _) => greedy_engages(inner, ctx, pos, acc)
    _ => has_viable(eval(g, ctx, pos), pos, ctx)
  }
}

///|
fn greedy_reads(sc : Scope, ctx : Ctx, pos : Int, acc : Array[Binding]) -> Bool {
  if pos >= ctx.toks.length() {
    return false // no token to read (早閉じ check at the end of input)
  }
  for g in sc.greedy {
    if greedy_engages(g, ctx, pos, acc) {
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
fn greedy_trigger_matches(
  g : Node,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Bool {
  match g {
    Seq(items) =>
      if items.length() >= 1 {
        match items[0] {
          Exact(s) => ctx.toks[pos] == s
          NativeMatch(m) => run_matcher(m, ctx, pos).length() > 0
          _ => greedy_engages(g, ctx, pos, acc)
        }
      } else {
        false
      }
    Or(alts) => {
      for a in alts {
        if greedy_trigger_matches(a, ctx, pos, acc) {
          return true
        }
      }
      false
    }
    // 入場済みの宣言は、この読みではもう受け手ではない (同ファイルの CommandSatisfied
    // 入場条件と同じ規則)。ここを true のままにすると、早閉じ判定が「親が読める」と
    // 誤答し、かつ入場側は空を返すので、**診断を 1 件も伴わない失敗**になる
    // (`greedy_trigger_matches` の doc が言う「より具体的な Held が既に積まれている」
    // という前提が崩れる)。
    CommandSatisfied(trigger, name, ordinal, _) =>
      ctx.toks[pos] == trigger && !command_scope_selected(acc, [name], ordinal)
    DdSatisfied(t, _) => ctx.toks[pos] == t
    DdMatchSatisfied(spelling, is_pattern, _, _, _) =>
      dd_match_token(spelling, is_pattern, ctx.toks[pos])
    NativeMatch(m) => run_matcher(m, ctx, pos).length() > 0
    LinkTarget(_, _, _, _, _, _, _, _, _, inner) =>
      greedy_trigger_matches(inner, ctx, pos, acc)
    Rooted(inner, _) => greedy_trigger_matches(inner, ctx, pos, acc)
    _ => greedy_engages(g, ctx, pos, acc)
  }
}

///|
/// Whether ANY greedy entry's trigger fires at `pos` (see
/// `greedy_trigger_matches`'s doc comment for why this is a separate,
/// coarser probe than `greedy_reads`).
fn any_trigger_matches(
  sc : Scope,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Bool {
  if pos >= ctx.toks.length() {
    return false
  }
  for g in sc.greedy {
    if greedy_trigger_matches(g, ctx, pos, acc) {
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
  // 先食い抑止は「この位置で greedy の読みが成立しうるか」だけを見る構造判定で、
  // その読みまでに**どの宣言へ入場済みか**は問わない。空 acc を渡すのは現状維持の
  // 明示 (入場履歴を効かせるなら早閉じ判定とは別の根拠が要る)。
  greedy_reads(sc, ctx, pos, [])
}

///|
/// DR-086 cut 判定補助: consumption is contract data. Closed `Bind` and
/// open marker residents answer through the same Node-level query, so adding a
/// resident cannot require a central builtin-variant list update.
fn is_zero_token_marker(node : Node) -> Bool {
  node_consumes_zero_tokens(node)
}

///|
/// DR-086 cut (issue values-decode-support、team-lead 裁定 2026-07-10「性質ベースの判定、
/// lowering の生成 shape 追加で漏れないように」): greedy 衛星 `g` が「trigger を Exact 消費した
/// 直後、値を1つ以上消費しうる継続」を持つ main entry (installer.mbt の `value_prim`/
/// `enum_value_node` 由来) なら trigger 文字列を返す。具体的な値消費 shape
/// (string resident/number resident/float resident/int resident/bool resident/separated resident/Or/...) を列挙する代わりに「継続の先頭要素が
/// 0-token マーカーでない」という消極的な性質で判定する — lowering に新しい値消費 shape が
/// 増えても自動的に安全側 (cut 候補として拾う) に倒れ、このヘルパーの更新漏れを起こさない。
fn value_slot_trigger(g : Node) -> String? {
  match g {
    LinkTarget(_, _, _, _, _, _, _, _, _, inner) | Rooted(inner, _) =>
      value_slot_trigger(inner)
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
/// `Bind, failure resident` 2連続を含む) なら trigger 文字列を返す。
fn zero_arg_variant_trigger(g : Node) -> String? {
  match g {
    LinkTarget(_, _, _, _, _, _, _, _, _, inner) | Rooted(inner, _) =>
      zero_arg_variant_trigger(inner)
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
  // untouched). CommandSatisfied / DdSatisfied are dispatched structurally so their child
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
    } else if !greedy_reads(sc, ctx, pos, acc) {
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
      let drop_redundant_residual = any_trigger_matches(sc, ctx, pos, acc)
      for r in run_cont(k, ctx, pos, acc) {
        match r {
          Held(pe, _) =>
            if drop_redundant_residual &&
              is_scope_residual(pe) &&
              pe.args_pos == pos {
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
/// DR-104 §2/§3 origin fixup (complete 専用): the boundary Pending a bare `Exact` node builds
/// (eval's `Exact` arm) has no way to see what follows it in the OWNING Seq, so it falls back to
/// `origin = spelling` (e.g. `--port`). When that `Exact` is actually an option satellite's head
/// (`Seq([Exact(trigger), tail, ..])`, installer.mbt's `inst_long` main-entry / variant-entry
/// shapes), the real origin is the element name `tail` carries — `number resident`/`string resident`/etc.'s own
/// name field for a value-typed main entry, `Bind`/`effect resident`'s name field for a variant entry
/// (`--secret`/`--no-color`-style), or a `Scoped` wrap's label for a ref/repeat entry. Mirrors
/// `value_slot_trigger`/`prim_name`'s existing "peek at the Seq's tail node" style in this same
/// file / json_conformance_test.mbt.
fn seq_boundary_name(node : Node) -> String? {
  match node_resident_name(node) {
    Some(name) => Some(name)
    None =>
      match node_effect_mark(node) {
        Some((name, _)) => Some(name)
        None =>
          match node {
            RequiredArgument(name) | Bind(name, _) | Scoped(name, _) =>
              Some(name)
            // `values` 糖衣 / value-enum 形の `or` (DESIGN §5.3, wire_decode の `Enum` body) が
            // 積む `enum_value_node`: 名前包みのない `Or([Seq([Exact(v), Bind(name, ...)]), ..])`。
            // 枝はどれも同じ要素名で `Bind` するので先頭枝から読めばよい。MDR-004 §3 の消費文法
            // としての `or` は `Scoped(e.name, Or(..))` なので上の `Scoped` アームが拾う。
            Or([Seq([Exact(_), Bind(name, _), ..]), ..]) => Some(name)
            _ => None
          }
      }
  }
}

///|
/// Whether `g` is (possibly through a `Rooted` global-link wrap) an option satellite's head Seq —
/// and if so, `(trigger spelling, the real origin name its tail carries)`. `None` for any other shape
/// (CommandSatisfied/DdSatisfied/DdMatchSatisfied/NativeMatch already carry their own correct origin,
/// no fixup needed there; a bare `Exact` alone or an unrecognized tail shape is left as the spelling
/// fallback, unchanged). The trigger spelling comes back with the name because the fixup targets the
/// head `Exact`'s OWN candidate only — see `fixup_boundary_cands`.
fn cand_boundary_origin(g : Node) -> (String, String)? {
  match g {
    LinkTarget(_, _, _, _, _, _, _, _, _, inner) => cand_boundary_origin(inner)
    Rooted(inner, _) => cand_boundary_origin(inner)
    Seq([Exact(trigger), rest, ..]) =>
      match seq_boundary_name(rest) {
        Some(name) => Some((trigger, name))
        None => None
      }
    _ => None
  }
}

///|
/// Find the opaque declaration metadata resident for one element. Command/dd origins
/// have no Entity and therefore no decorator.
fn entity_extension(sc : Scope, name : String) -> &EntityExt? {
  for e in sc.entities {
    if e.name == name {
      return Some(e.extension)
    }
  }
  None
}

///|
/// Apply `cand_boundary_origin`'s correction (+ the owning element's `hidden` declaration) to the
/// satellite's HEAD `Exact` candidate — the one whose `spelling` is the trigger itself, which the
/// `Exact` arm could only name after its own spelling. Every other candidate in the same Pending is
/// left untouched: a value-position candidate (`is_value:true`) is built via `pending_value_candidate`
/// with the correct origin already, and an exact candidate coming from DEEPER in the satellite (the
/// `or`/`values` enum branches, DR-063 §A.1 anonymous exacts) is a nameless element whose origin IS
/// its own spelling (DR-104 §2 note (iii)) — the entry name must not overwrite it. A `None` origin
/// (not an option-satellite boundary shape) is a no-op passthrough.
fn fixup_boundary_cands(
  g : Node,
  sc : Scope,
  cs : Array[Candidate],
) -> Array[Candidate] {
  match cand_boundary_origin(g) {
    None => cs
    Some((trigger, origin)) => {
      let extension = entity_extension(sc, origin)
      let out : Array[Candidate] = []
      for c in cs {
        if c.is_value || c.spelling != trigger {
          out.push(c)
        } else {
          let candidate = { ..c, origin, }
          match extension {
            Some(resident) => out.push(resident.complete_candidate(candidate))
            None => out.push(candidate)
          }
        }
      }
      out
    }
  }
}

///|
/// One greedy entry's interjection at (pos, pidx). Structural dispatch:
/// - CommandSatisfied: enter the child scope as a NEW backbone whose continuation is
///   "nest my bindings under the command name, then resume the parent at the
///   same pidx" — the child sees the whole outside world through `k`.
/// - DdSatisfied: consume the trigger and sever the rest of the walk.
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
    CommandSatisfied(trigger, name, ordinal, child) =>
      // 一度この scope から入場した宣言のトリガは、同じ読みの中で**再び材料にならない**
      // (同ファイル完了面の同条件と同じ規則 — KNest が選択済み宣言を記録するので
      // `command_scope_selected` で判定できる)。command scope の結果キーは 1 つの器で
      // あり、同一宣言の 2 回目の入場は着地先を持たない — 許すと同一 scope path・
      // 同一 ordinal のマーカーが並び、occurrence を区別できない読みが完全経路として
      // 数えられてしまう (issue dup-raw-command-ordinal-marker-occurrence-gap)。
      if pos < ctx.toks.length() &&
        ctx.toks[pos] == trigger &&
        !command_scope_selected(acc, [name], ordinal) {
        let kk = KNest(
          name,
          ordinal,
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
            Rejected(pe, bs) =>
              out.push(Rejected({ ..pe, path: nest_path(name, pe.path) }, bs))
            Held(pe, bs) =>
              out.push(Held({ ..pe, path: nest_path(name, pe.path) }, bs))
            Pending(cs, bs) => out.push(Pending(nest_cands(name, cs), bs))
            _ => out.push(r)
          }
        }
      } else if pos >= ctx.toks.length() &&
        in_complete(ctx) &&
        !command_scope_selected(acc, [name], ordinal) {
        // A command trigger is completion material only before that declaration
        // has entered from this scope. KNest records the selected declaration
        // before resuming the parent, so an empty child backbone cannot expose
        // its consumed trigger again; another same-name ordinal remains eligible.
        out.push(
          Pending([Candidate::trigger(trigger, name, "flag", WordEnd)], acc),
        )
      }
    DdSatisfied(trigger, origin) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == trigger {
        // DR-093 §2/§7: fire を committed として観測可能にする placeholder binding
        // (`flag_bare_true_variant` と同型の `Set Bool(true)`、`NoneCell`/`none_cells` が
        // build_result/effects から除外する — 値そのものは運ばない、DR-089 §3 不変)。DdSatisfied の
        // trigger 文字列は要素名そのもの (dd_match 未使用の唯一のケースでのみ installer が
        // `DdSatisfied(e.name)` を作る) なのでそのまま key に使える。
        let acc2 = acc +
          [Binding::new(origin, Bool(true), Cli, at_pos=Some(pos))]
        for r in scope_step(sc, ctx, pos + 1, pidx, acc2, true, sever_cont(k)) {
          out.push(r)
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        out.push(
          Pending([Candidate::trigger(trigger, origin, "flag", WordEnd)], acc),
        )
      }
    // DR-090 §1/§2: generalized dd. `severed=true` is unconditional here exactly like `DdSatisfied`
    // above (the sever is the "greedy internal consumption is 一体" rule, unaffected by which
    // axis fired). `self_keep` only changes the RESUMED position: `false` (drop) consumes the
    // triggering token (`pos + 1`, same as `DdSatisfied`); `true` (keep) resumes at the SAME `pos` —
    // the triggering token itself is never consumed here, so it flows into the positional face
    // (now severed = raw) starting with itself, matching §2's "自身を含めて以降が positional 域".
    DdMatchSatisfied(spelling, is_pattern, self_keep, elem_name, origin) =>
      if pos < ctx.toks.length() &&
        dd_match_token(spelling, is_pattern, ctx.toks[pos]) {
        let resume_pos = if self_keep { pos } else { pos + 1 }
        // DR-093 §2/§7: DdSatisfied と同じ committed placeholder binding。key は `elem_name` (要素の
        // 同一性軸、DR-090 §2) — `spelling` は match 使用時トリガ綴りやパターンで要素名と一致しない。
        let acc2 = acc +
          [Binding::new(elem_name, Bool(true), Cli, at_pos=Some(pos))]
        for
          r in scope_step(sc, ctx, resume_pos, pidx, acc2, true, sever_cont(k)) {
          out.push(r)
        }
      } else if pos >= ctx.toks.length() && in_complete(ctx) && !is_pattern {
        // completion candidates only for an exact spelling (see the off-spine `eval` arm's
        // identical rationale) — a pattern trigger has no single "next token to type".
        // DR-104 §2 origin = 由来要素名: `elem_name`, mirroring the off-spine arm's fix above.
        out.push(
          Pending([Candidate::trigger(spelling, origin, "flag", WordEnd)], acc),
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
          for
            branch in eval_with_downstream(
              g,
              ctx,
              pos,
              (ctx2, next_pos, bindings) => {
                if next_pos > pos {
                  scope_step(
                    sc,
                    ctx2,
                    next_pos,
                    pidx,
                    acc + bindings,
                    severed,
                    k,
                  )
                } else {
                  []
                }
              },
              (_ctx, error, bindings) => [Rejected(error, acc + bindings)],
              (_ctx, error, bindings) => [Held(error, acc + bindings)],
              (_ctx, candidates, bindings) => {
                [
                  Pending(
                    fixup_boundary_cands(g, sc, candidates),
                    acc + bindings,
                  ),
                ]
              },
              on_severed_accept=Some((ctx2, next_pos, bindings) => {
                if next_pos > pos {
                  scope_step(
                    sc,
                    ctx2,
                    next_pos,
                    pidx,
                    acc + bindings,
                    true,
                    sever_cont(k),
                  )
                } else {
                  []
                }
              }),
            ) {
            out.push(branch)
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
        for
          r in eval_scope_with_downstream(
            wrap_sc,
            ctx,
            p2,
            0,
            [],
            severed,
            (ctx2, next_pos, tail_bindings, tail_severed) => {
              scope_step(
                sc,
                ctx2,
                next_pos,
                pidx,
                acc + (bs + tail_bindings),
                severed || tail_severed,
                if tail_severed {
                  sever_cont(k)
                } else {
                  k
                },
              )
            },
            (_ctx2, error, tail_bindings) => {
              [Rejected(error, acc + (bs + tail_bindings))]
            },
            (_ctx2, error, tail_bindings) => {
              [Held(error, acc + (bs + tail_bindings))]
            },
            (_ctx2, candidates, tail_bindings) => {
              [Pending(candidates, acc + (bs + tail_bindings))]
            },
          ) {
          out.push(r)
        }
      }
      Rejected(pe, bs) => out.push(Rejected(pe, acc + bs))
      Held(pe, bs) => out.push(Held(pe, acc + bs))
      Pending(cs, bs) => out.push(Pending(cs, acc + bs))
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
    ChildDefault(_, _, _) =>
      eval_with_downstream(
        item,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          scope_step(sc, ctx2, next_pos, pidx + 1, acc + bindings, severed, k)
        },
        (_ctx, error, bindings) => [Rejected(error, acc + bindings)],
        (_ctx, error, bindings) => [Held(error, acc + bindings)],
        (_ctx, candidates, bindings) => [Pending(candidates, acc + bindings)],
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          scope_step(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            acc + bindings,
            true,
            sever_cont(k),
          )
        }),
        consume_scope=Some(sc),
        severed~,
      )
    Ext(extension) =>
      if extension.consumes_zero_tokens() ||
        pos >= ctx.toks.length() ||
        !suppressed(sc, ctx, pos, severed) {
        eval_required_ext(extension, ctx, pos, acc, (ctx2, next_pos, next_acc) => {
          scope_step(sc, ctx2, next_pos, pidx + 1, next_acc, severed, k)
        })
      } else {
        []
      }
    RequiredArgument(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        scope_step(
          sc,
          ctx,
          pos + 1,
          pidx + 1,
          acc +
          [Binding::new(name, String(ctx.toks[pos]), Cli, at_pos=Some(pos))],
          severed,
          k,
        )
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([Candidate::pending_value("string", name)], acc)]
        } else {
          [
            Held(
              {
                element: name,
                args_pos: pos,
                kind: Constraint,
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
        // positional-spine literal (a structural or-branch's exact value, not an option
        // trigger) — origin IS the spelling here, there is no separate element name to
        // extract (none of our fixtures exercise this shape yet, kept as-is).
        [Pending([Candidate::trigger(s, s, "flag", WordEnd)], acc)]
      } else {
        []
      }
    // A repeat item (spec DR-043): >= 1 head, unfolded POROUSLY on the spine.
    //
    // 取り分の選好: the split between adjacent closures is ONE
    // interpretation's freedom of division, not an ambiguity. greedy
    // (default) prefers the LONGER share, is_lazy the shorter. We commit to the
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
          // unfold. The child's own walk carries `severed` so a dd-continued
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
        head =>
          eval_with_downstream(
            head,
            ctx,
            pos,
            (ctx2, next_pos, bindings) => {
              if next_pos > pos {
                ref_choice(
                  sc,
                  name,
                  ctx2,
                  next_pos,
                  pidx,
                  acc + bindings,
                  severed,
                  k,
                )
              } else {
                []
              }
            },
            (_ctx, error, bindings) => [Rejected(error, acc + bindings)],
            (_ctx, error, bindings) => [Held(error, acc + bindings)],
            (_ctx, candidates, bindings) => {
              [Pending(candidates, acc + bindings)]
            },
            on_severed_accept=Some((ctx2, next_pos, bindings) => {
              if next_pos > pos {
                ref_choice(
                  sc,
                  name,
                  ctx2,
                  next_pos,
                  pidx,
                  acc + bindings,
                  true,
                  sever_cont(k),
                )
              } else {
                []
              }
            }),
            consume_scope=Some(sc),
            severed~,
          )
      }
    IndexedRepeat(label, head, min, budget) =>
      indexed_repeat_step(
        sc, label, head, min, budget, ctx, pos, pidx, acc, severed, k, 0,
      )
    BoundedTail(head, budget, is_lazy) =>
      bounded_tail_step(
        sc, head, budget, is_lazy, ctx, pos, pidx, acc, severed, k,
      )
    Many(inner, is_lazy) => {
      // Two closures on the spine — parity with Ref/BoundedTail 取り分選好
      // (spec DR-043). Without preference, `[Many(xs), Many(ys)]` on ["a","b"]
      // returns Ambiguous (3-way split) even though the greedy default fixes
      // xs=[a,b], ys=[] as the representative. `is_lazy` (issue 2026-07-08
      // min0-lazy-repeat-gap) inverts which share wins EXACTLY the way
      // `bounded_tail_step` does below — same two closures, same tie-break
      // order flip, just no budget countdown (unbounded).
      let stop = scope_step(sc, ctx, pos, pidx + 1, acc, severed, k) // 0 reps
      let more = scope_consume_rep(sc, inner, ctx, pos, pidx, acc, severed, k) // 1 rep (which re-enters scope_step at same pidx)
      choose_repeat_share(ctx, stop, more, is_lazy)
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
    other =>
      // any other node as a positional item: consume it (codex 節目レビュー指摘3、issue
      // 2026-07-09-ref-template-result-shape: a ref element's mandatory-head-unrolled slot
      // (installer.mbt's `ref_row_head`, `min > 1` positional repeat) is a COMPOUND node
      // (Scoped/Seq/Or wrapping the referenced template's leaves) placed directly on the spine —
      // plain off-spine `eval` has no `Scope`, so it could never apply 先食い (DR-041 §4) to a
      // nested leaf. `consume_compound` (eval.mbt, shared with `consume_head`'s own catch-all)
      // threads `sc`/`severed` down to every leaf primitive it reaches instead), then continue.
      eval_with_downstream(
        other,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          scope_step(sc, ctx2, next_pos, pidx + 1, acc + bindings, severed, k)
        },
        (_ctx, error, bindings) => [Rejected(error, acc + bindings)],
        (_ctx, error, bindings) => [Held(error, acc + bindings)],
        (_ctx, candidates, bindings) => [Pending(candidates, acc + bindings)],
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          scope_step(
            sc,
            ctx2,
            next_pos,
            pidx + 1,
            acc + bindings,
            true,
            sever_cont(k),
          )
        }),
        consume_scope=Some(sc),
        severed~,
      )
  }
}

///|
/// CPS-aware indexed repeat. Each accepted prefix is tested against the full downstream continuation;
/// greedy preference selects the longest prefix that reaches a complete path, while `nest_index` keeps
/// every firing's child seats under an independent runtime row.
fn indexed_repeat_step(
  sc : Scope,
  label : String,
  head : Node,
  min : Int,
  budget : Int?,
  ctx : Ctx,
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  k : Cont,
  rep : Int,
) -> Array[Branch] {
  let acc2 = if rep == 0 { acc + [array_marker(label)] } else { acc }
  let stop = if rep >= min {
    scope_step(sc, ctx, pos, pidx + 1, acc2, severed, k)
  } else {
    []
  }
  let at_budget = match budget {
    Some(extra) => rep >= min + extra
    None => false
  }
  let more : Array[Branch] = []
  if !at_budget {
    for
      branch in eval_with_downstream(
        head,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          if next_pos > pos {
            indexed_repeat_step(
              sc,
              label,
              head,
              min,
              budget,
              ctx2,
              next_pos,
              pidx,
              acc2 + nest_index(label, rep, bindings),
              severed,
              k,
              rep + 1,
            )
          } else {
            []
          }
        },
        (_ctx, error, bindings) => [Rejected(error, acc2 + bindings)],
        (_ctx, error, bindings) => {
          if rep < min || error.args_pos < ctx.toks.length() {
            [Held(error, acc2 + bindings)]
          } else {
            []
          }
        },
        (_ctx, candidates, bindings) => [Pending(candidates, acc2 + bindings)],
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          if next_pos > pos {
            indexed_repeat_step(
              sc,
              label,
              head,
              min,
              budget,
              ctx2,
              next_pos,
              pidx,
              acc2 + nest_index(label, rep, bindings),
              true,
              sever_cont(k),
              rep + 1,
            )
          } else {
            []
          }
        }),
        consume_scope=Some(sc),
        severed~,
      ) {
      more.push(branch)
    }
  }
  choose_repeat_share(ctx, stop, more, false)
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
  let is_lazy = ref_is_lazy(ctx.defs, name)
  let stop = scope_step(sc, ctx, p2, pidx + 1, acc2, severed, k)
  // "more" = one more OPTIONAL rep; a missing-operand for ANY value
  // primitive reachable inside the repeat head (scope-shaped included) is a
  // legitimate stop, not a failure. head-external missing (a downstream
  // primitive fed by the parent continuation) stays.
  let more = drop_optional_missing(
    ctx,
    scope_step(sc, ctx, p2, pidx, acc2, severed, k),
    head_elem_names(head),
  )
  choose_repeat_share(ctx, stop, more, is_lazy)
}

///|
/// A bounded repeat tail (spec DR-043 max 有限): consume 0..budget more heads
/// porously, with the same 取り分選好 as the Ref path.
fn bounded_tail_step(
  sc : Scope,
  head : Node,
  budget : Int,
  is_lazy : Bool,
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
          KTailChoice(sc, head, budget - 1, is_lazy, pidx, severed, pos, k),
        )
      _ =>
        eval_with_downstream(
          head,
          ctx,
          pos,
          (ctx2, next_pos, bindings) => {
            if next_pos > pos {
              bounded_tail_step(
                sc,
                head,
                budget - 1,
                is_lazy,
                ctx2,
                next_pos,
                pidx,
                acc + bindings,
                severed,
                k,
              )
            } else {
              []
            }
          },
          (_ctx, error, bindings) => [Rejected(error, acc + bindings)],
          (_ctx, error, bindings) => [Held(error, acc + bindings)],
          (_ctx, candidates, bindings) => [Pending(candidates, acc + bindings)],
          on_severed_accept=Some((ctx2, next_pos, bindings) => {
            if next_pos > pos {
              bounded_tail_step(
                sc,
                head,
                budget - 1,
                is_lazy,
                ctx2,
                next_pos,
                pidx,
                acc + bindings,
                true,
                sever_cont(k),
              )
            } else {
              []
            }
          }),
          consume_scope=Some(sc),
          severed~,
        )
    }
  } else {
    []
  }
  // Filter the OPTIONAL "more" branch's internal missing_operand@EOF for any
  // primitive reachable in the head (scope-shaped heads included, spec
  // DR-065 §3 held-error parity). head-external missing from the parent's
  // continuation is preserved.
  let more = drop_optional_missing(ctx, more_raw, head_elem_names(head))
  choose_repeat_share(ctx, stop, more, is_lazy)
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
    Ext(extension) =>
      if extension.consumes_zero_tokens() ||
        pos >= ctx.toks.length() ||
        !suppressed(sc, ctx, pos, severed) {
        eval_required_ext(extension, ctx, pos, [], (_ctx, next_pos, next_acc) => {
          [Accept(next_pos, next_acc)]
        })
      } else {
        []
      }
    // RequiredArgument gets its own arm so 先食い (suppressed) applies —
    // eval() does not see the parent scope, so falling through would let a
    // greedy trigger token be raw-eaten as the repeat head's value. Held
    // shapes must match the primitive arms above so drop_optional_missing on
    // the OPTIONAL "more" branch can filter them uniformly.
    RequiredArgument(name) =>
      if pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed) {
        [
          Accept(pos + 1, [
            Binding::new(name, String(ctx.toks[pos]), Cli, at_pos=Some(pos)),
          ]),
        ]
      } else if pos >= ctx.toks.length() {
        if in_complete(ctx) {
          [Pending([Candidate::pending_value("string", name)], [])]
        } else {
          [
            Held(
              {
                element: name,
                args_pos: pos,
                kind: Constraint,
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
    Ext(_) | RequiredArgument(_) => consume_head(sc, node, ctx, pos, severed)
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
    Many(inner, is_lazy) =>
      consume_compound_many(sc, inner, is_lazy, ctx, pos, [], severed)
    BoundedTail(head, budget, is_lazy) =>
      consume_compound_bounded(sc, head, budget, is_lazy, ctx, pos, [], severed)
    IndexedRepeat(label, head, min, budget) =>
      consume_compound_indexed(
        sc,
        label,
        head,
        min,
        budget,
        ctx,
        pos,
        [],
        severed,
        0,
      )
    Scoped(label, body) =>
      nest_branches(label, consume_compound(sc, body, ctx, pos, severed))
    LinkTarget(
      from,
      target,
      target_scope,
      target_tuple_arities,
      target_selections,
      target_observation,
      target_residual,
      levels,
      extension,
      inner
    ) => {
      let out : Array[Branch] = []
      for branch in consume_compound(sc, inner, ctx, pos, severed) {
        match branch {
          Accept(next_pos, bindings) =>
            out.push(
              Accept(
                next_pos,
                bindings_through_link(
                  bindings,
                  from,
                  target,
                  target_scope,
                  target_tuple_arities,
                  target_selections,
                  target_observation,
                  levels,
                  target_residual~,
                ),
              ),
            )
          Rejected(error, bindings) => {
            let linked = bindings_through_link(
              bindings,
              from,
              target,
              target_scope,
              target_tuple_arities,
              target_selections,
              target_observation,
              levels,
              target_residual~,
            )
            // DR-138 §6 (a): 値空間 link の operand は着地座の type のパーサを通り、
            // その失敗は「読みの成立に効く」Error である (淘汰で沈黙させない)。
            // 値残余を持たない link の Reject は従来どおり静かに脱落 (DR-037)。
            if target_residual.length() > 0 {
              out.push(Held(error, linked))
            } else {
              out.push(Rejected(error, linked))
            }
          }
          Held(error, bindings) =>
            out.push(
              Held(
                error,
                bindings_through_link(
                  bindings,
                  from,
                  target,
                  target_scope,
                  target_tuple_arities,
                  target_selections,
                  target_observation,
                  levels,
                  target_residual~,
                ),
              ),
            )
          Pending(candidates, bindings) =>
            out.push(
              Pending(
                decorate_link_candidates(candidates, from, extension),
                bindings_through_link(
                  bindings,
                  from,
                  target,
                  target_scope,
                  target_tuple_arities,
                  target_selections,
                  target_observation,
                  levels,
                  target_residual~,
                ),
              ),
            )
        }
      }
      out
    }
    Ref(name) =>
      match ctx.defs.get(name) {
        Some(tpl) => consume_compound(sc, tpl, ctx, pos, severed)
        None => []
      }
    Bind(name, v) => [Accept(pos, [Binding::new(name, v, Cli)])]
    _ => eval(node, ctx, pos)
  }
}

///|
fn consume_compound_many(
  sc : Scope,
  inner : Node,
  is_lazy : Bool,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  severed : Bool,
) -> Array[Branch] {
  let stop : Array[Branch] = [Accept(pos, acc)]
  let more_raw : Array[Branch] = []
  for branch in consume_compound(sc, inner, ctx, pos, severed) {
    match branch {
      Accept(next_pos, bindings) =>
        if next_pos > pos {
          for
            result in consume_compound_many(
              sc,
              inner,
              is_lazy,
              ctx,
              next_pos,
              acc + bindings,
              severed,
            ) {
            more_raw.push(result)
          }
        }
      Rejected(error, bindings) =>
        more_raw.push(Rejected(error, acc + bindings))
      Held(error, bindings) => more_raw.push(Held(error, acc + bindings))
      Pending(candidates, bindings) =>
        more_raw.push(Pending(candidates, acc + bindings))
    }
  }
  let more = drop_optional_missing(ctx, more_raw, head_elem_names(inner))
  if is_lazy {
    cat_branches(stop, more)
  } else {
    cat_branches(more, stop)
  }
}

///|
fn consume_compound_bounded(
  sc : Scope,
  head : Node,
  budget : Int,
  is_lazy : Bool,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  severed : Bool,
) -> Array[Branch] {
  let stop : Array[Branch] = [Accept(pos, acc)]
  if budget <= 0 {
    return stop
  }
  let more_raw : Array[Branch] = []
  for branch in consume_compound(sc, head, ctx, pos, severed) {
    match branch {
      Accept(next_pos, bindings) =>
        if next_pos > pos {
          for
            result in consume_compound_bounded(
              sc,
              head,
              budget - 1,
              is_lazy,
              ctx,
              next_pos,
              acc + bindings,
              severed,
            ) {
            more_raw.push(result)
          }
        }
      Rejected(error, bindings) =>
        more_raw.push(Rejected(error, acc + bindings))
      Held(error, bindings) => more_raw.push(Held(error, acc + bindings))
      Pending(candidates, bindings) =>
        more_raw.push(Pending(candidates, acc + bindings))
    }
  }
  let more = drop_optional_missing(ctx, more_raw, head_elem_names(head))
  if is_lazy {
    cat_branches(stop, more)
  } else {
    cat_branches(more, stop)
  }
}

///|
fn consume_compound_indexed(
  sc : Scope,
  label : String,
  head : Node,
  min : Int,
  budget : Int?,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  severed : Bool,
  rep : Int,
) -> Array[Branch] {
  let acc2 = if rep == 0 { acc + [array_marker(label)] } else { acc }
  let stop : Array[Branch] = if rep >= min { [Accept(pos, acc2)] } else { [] }
  let at_budget = match budget {
    Some(extra) => rep >= min + extra
    None => false
  }
  if at_budget {
    return stop
  }
  let more_raw : Array[Branch] = []
  for branch in consume_compound(sc, head, ctx, pos, severed) {
    match branch {
      Accept(next_pos, bindings) =>
        if next_pos > pos {
          for
            result in consume_compound_indexed(
              sc,
              label,
              head,
              min,
              budget,
              ctx,
              next_pos,
              acc2 + nest_index(label, rep, bindings),
              severed,
              rep + 1,
            ) {
            more_raw.push(result)
          }
        }
      Rejected(error, bindings) =>
        more_raw.push(Rejected(error, acc2 + bindings))
      Held(error, bindings) => more_raw.push(Held(error, acc2 + bindings))
      Pending(candidates, bindings) =>
        more_raw.push(Pending(candidates, acc2 + bindings))
    }
  }
  let more = if rep >= min {
    drop_optional_missing(ctx, more_raw, head_elem_names(head))
  } else {
    more_raw
  }
  cat_branches(more, stop)
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
            acc + bs,
            severed,
          ) {
          out.push(r)
        }
      Rejected(pe, bs) => out.push(Rejected(pe, acc + bs))
      Held(pe, bs) => out.push(Held(pe, acc + bs))
      Pending(cs, bs) => out.push(Pending(cs, acc + bs))
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
fn head_elem_names_into(node : Node, out : Array[String]) -> Unit {
  match node_resident_name(node) {
    Some(name) => if !str_mem(out, name) { out.push(name) }
    None => ()
  }
  match node {
    RequiredArgument(name) => if !str_mem(out, name) { out.push(name) }
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
    // 結果スコープの包み。中身は同じ head の住人なので `ScopeNode` と同じく辿る
    // (option 自身が structural or / seq のとき head は `Scoped(name, ...)` になる)。
    Scoped(_, inner) => head_elem_names_into(inner, out)
    ScopeNode(sc) => {
      for g in sc.greedy {
        head_elem_names_into(g, out)
      }
      for p in sc.positional {
        head_elem_names_into(p, out)
      }
    }
    // Ref/CommandSatisfied/DdSatisfied/Rooted/etc.: opaque or heavy — do not recurse (Ref
    // could loop; command/dd satellites are not walked by the head reps).
    _ => ()
  }
}

///|
/// Drop value-starvation candidates belonging to an OPTIONAL repeat head in parse mode. Reaching
/// "more" means a prior rep succeeded, so an absent value for one more head is a legitimate stop.
/// Candidates from the outer continuation remain, and complete mode keeps every candidate.
fn drop_optional_missing(
  ctx : Ctx,
  brs : Array[Branch],
  names : Array[String],
) -> Array[Branch] {
  if in_complete(ctx) || names.length() == 0 {
    return brs
  }
  let out : Array[Branch] = []
  for branch in brs {
    match branch {
      Pending(candidates, bindings) => {
        let remaining : Array[Candidate] = []
        for candidate in candidates {
          if !(candidate.is_value && str_mem(names, candidate.origin)) {
            remaining.push(candidate)
          }
        }
        if remaining.length() > 0 {
          out.push(Pending(remaining, bindings))
        }
      }
      _ => out.push(branch)
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
/// MDR-003's identifier rename (lazy → is_lazy) does NOT apply to this string
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
    Ext(extension) =>
      if extension.consumes_zero_tokens() ||
        (pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed)) {
        eval_required_ext(extension, ctx, pos, acc, (_ctx2, next_pos, next_acc) => {
          if next_pos > pos {
            scope_step(sc, ctx, next_pos, pidx, next_acc, severed, k)
          } else {
            []
          }
        })
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        eval_required_ext(extension, ctx, pos, acc, (_ctx, next_pos, next_acc) => {
          [Accept(next_pos, next_acc)]
        })
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
    _ =>
      eval_with_downstream(
        inner,
        ctx,
        pos,
        (ctx2, next_pos, bindings) => {
          if next_pos > pos {
            scope_step(sc, ctx2, next_pos, pidx, acc + bindings, severed, k)
          } else {
            []
          }
        },
        (_ctx, error, bindings) => [Rejected(error, acc + bindings)],
        (_ctx, error, bindings) => [Held(error, acc + bindings)],
        (_ctx, candidates, bindings) => [Pending(candidates, acc + bindings)],
        on_severed_accept=Some((ctx2, next_pos, bindings) => {
          if next_pos > pos {
            scope_step(
              sc,
              ctx2,
              next_pos,
              pidx,
              acc + bindings,
              true,
              sever_cont(k),
            )
          } else {
            []
          }
        }),
        consume_scope=Some(sc),
        severed~,
      )
  }
}

///|
/// Drop the `levels_to_declaring_scope` nesting hint — it is resolved before path counting.
fn strip_levels_to_declaring_scope(bs : Array[Binding]) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in bs {
    out.push({ ..b, levels_to_declaring_scope: 0 })
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
      if n.name() == b.key && scope_path_eq(n.path(), b.scope) {
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
pub fn is_committed(
  bindings : Array[Binding],
  path : Array[String],
  name : String,
) -> Bool {
  let mut committed = false
  for b in bindings {
    if b.key == name && scope_path_eq(b.scope, path) {
      match b.op {
        Set if b.value is Null => committed = false
        _ => committed = true
      }
    }
  }
  committed
}

///|
fn has_pending_invoke(
  bindings : Array[Binding],
  path : Array[String],
  name : String,
) -> Bool {
  let mut pending = false
  for b in bindings {
    if b.key == name && scope_path_eq(b.scope, path) {
      pending = b.op is Invoke(_)
    }
  }
  pending
}

///|
/// The committed value of the (path, name) cell (last-wins), or None.
pub fn element_value(
  bindings : Array[Binding],
  path : Array[String],
  name : String,
) -> Value? {
  let mut v : Value? = None
  for b in bindings {
    if b.key == name && scope_path_eq(b.scope, path) {
      match b.op {
        Set if b.value is Null => v = None
        _ => v = Some(b.value)
      }
    }
  }
  v
}

///|
/// Does a cell value equal the literal a declaration spelled? `value_requires` (DR-055) writes its
/// operand as a wire string, so the literal can only ever denote a scalar; a composite cell value
/// answers "no" instead of being pushed through a scalar spelling it does not have.
pub fn value_matches_literal(value : Value, literal : String) -> Bool {
  match value {
    Null | Array(_) | Object(_) => false
    _ => value_str(value) == literal
  }
}

///|
/// DR-088 §1/§2: 「値源が宣言されている」= 「その値源から遅延解決する default_fn が設定されている
/// のと同型」= デフォルトの存在。経路探索 (選好・完全性) に参加する遅延述語の充足判定は、値の実解決
/// をせず**この静的宣言の有無だけ**を見る — committed か、または (default 属性 ∨ env 宣言 ∨
/// config 席) のいずれかがあれば「充足しうる」とみなす。bool/非bool を問わない
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
      // DR-088 §1 の統一述語 (default_fn を含む全値源)。lowering 側の
      // ElementDef::has_declared_value_source と対で、判定のズレを作らない。
      return e.has_declared_value_source()
    }
  }
  false
}

///|
/// `scope` が「宣言 scope `path` の直下に `wrapper` という 1 段だけネストした部分木」に属するか
/// (`RequiredCandidate.wrapper` 判定、codex レビュー M-2 修正): ref 展開 (`inst_long`/
/// `lower_positional` の ref 分岐) は値を `Scoped(ref要素名, ...)` で 1 段だけラップするため
/// (`Scoped` の nest 動作は `eval.mbt` の `nest` 関数参照)、`scope` の `path.length()` 番目の要素が
/// `wrapper` と一致すればよい — それ以降にさらに深い要素 (repeat 付き ref の row 等) があっても
/// 構わない (`scope.length() >= path.length() + 1` のみ要求、それ以上の深さは無条件で許容)。
/// 無制限透過 (`scope` が `path` を prefix に持つだけで OK) ではなく、`wrapper` という 1 段を
/// 明示的に要求する — これにより他要素・別の子 scope の値を誤って拾わない
/// (`RequiredCandidate` の doc comment 参照)。
fn scope_in_wrapped_subtree(
  scope : Array[String],
  path : Array[String],
  wrapper : String,
) -> Bool {
  if scope.length() < path.length() + 1 {
    return false
  }
  for i in 0..<path.length() {
    if scope[i] != path[i] {
      return false
    }
  }
  scope[path.length()] == wrapper
}

///|
/// `is_committed` の `RequiredCandidate.wrapper` 対応版 (codex レビュー M-2 修正): `scope` の完全
/// 一致 (`scope_path_eq`) の代わりに `scope_in_wrapped_subtree` で「宣言元 ref 要素の部分木内」を
/// 探す。
pub fn is_committed_in_subtree(
  bindings : Array[Binding],
  path : Array[String],
  wrapper : String,
  name : String,
) -> Bool {
  let mut committed = false
  for b in bindings {
    if b.key == name && scope_in_wrapped_subtree(b.scope, path, wrapper) {
      match b.op {
        Set if b.value is Null => committed = false
        _ => committed = true
      }
    }
  }
  committed
}

///|
/// `element_value` の `RequiredCandidate.wrapper` 対応版 (codex レビュー M-2 修正、`is_committed_in_
/// subtree` と対)。
pub fn element_value_in_subtree(
  bindings : Array[Binding],
  path : Array[String],
  wrapper : String,
  name : String,
) -> Value? {
  let mut v : Value? = None
  for b in bindings {
    if b.key == name && scope_in_wrapped_subtree(b.scope, path, wrapper) {
      match b.op {
        Set if b.value is Null => v = None
        _ => v = Some(b.value)
      }
    }
  }
  v
}

///|
/// `value_declared` の `RequiredCandidate` 対応版 (KTop 粗判定、codex レビュー M-2 修正):
/// `wrapper` が `None` なら宣言 scope path そのものを見る従来どおりの `value_declared`。
/// `Some(w)` なら宣言元要素 `w` 自身の Scoped 部分木内を `is_committed_in_subtree` で探す — ref
/// 経由の candidate (num/flag 等) は `Scope.entities` に登録されない (repeat/multiple 無しの ref
/// 要素、`ensure_entity_body` の Cell コメント参照) ため、`value_declared` の entities フォール
/// バック検索 (default/env/config の宣言有無) は wrapper 付き candidate には意味を持たず、
/// committed 判定のみで足りる。
fn candidate_declared(
  c : RequiredCandidate,
  bindings : Array[Binding],
  path : Array[String],
  entities : Array[Entity],
) -> Bool {
  match c.wrapper {
    None => value_declared(c.name, bindings, path, entities)
    Some(w) => is_committed_in_subtree(bindings, path, w, c.name)
  }
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
      // DR-136 裁定 4: committed 判定は entity 名軸、errors[].element は参照識別子軸。
      Requires(entity, element, targets) =>
        if is_committed(bindings, path, entity) &&
          !has_pending_invoke(bindings, path, entity) {
          for t in targets {
            if !value_declared(t, bindings, path, sc.entities) {
              out.push(
                ParseError::constraint(
                  element,
                  "requires_violated",
                  "'\{element}' requires '\{t}'",
                  pos,
                ),
              )
            }
          }
        }
      RequiresIf(entity, branch_id, v, targets) => {
        // DR-055 §1 + DR-052 §値枝 id 直交: committed 判定 / 値照合は親 entity (format) を対象に、
        // 違反時の error.element は branch_id (fmt_json = 制約の宣言元 = 値枝の id) を emit する。
        // branch_id は installer で id 未指定時に entity 名にフォールバックされているので、id なしの
        // parent 直属 value_requires は従来通り entity 名で attribution される。
        let active = is_committed(bindings, path, entity) &&
          !has_pending_invoke(bindings, path, entity) &&
          (match element_value(bindings, path, entity) {
            Some(x) => value_matches_literal(x, v)
            None => false
          })
        if active {
          for t in targets {
            if !value_declared(t, bindings, path, sc.entities) {
              out.push(
                ParseError::constraint(
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
      Conflicts(entity, element, targets) =>
        if is_committed(bindings, path, entity) &&
          !has_pending_invoke(bindings, path, entity) {
          for t in targets {
            if is_committed(bindings, path, t) &&
              !has_pending_invoke(bindings, path, t) {
              out.push(
                ParseError::constraint(
                  element,
                  "conflicts_with_violated",
                  "'\{element}' conflicts with '\{t}'",
                  pos,
                ),
              )
            }
          }
        }
      Exclusive(group, members) => {
        let mut count = 0
        let mut pending = false
        for m in members {
          if has_pending_invoke(bindings, path, m) {
            pending = true
          } else if is_committed(bindings, path, m) {
            count = count + 1
          }
        }
        if !pending && count > 1 {
          out.push(
            ParseError::constraint(
              group,
              "exclusive_group_violated",
              "exclusive group '\{group}' allows at most one",
              pos,
            ),
          )
        }
      }
      Required(display, candidates) => {
        // DR-093 §1/§2: KTop の粗判定 (完全経路の成立条件、DR-047 §2) — `candidate_declared`
        // (`value_declared` の RequiredCandidate 対応版、codex M-2 修正) をそのまま再利用する
        // (Requires 目的語と同じゲート)。値空間なし (none) の要素は default_values/env_key/
        // config_seat をそもそも持てない (DR-089 §7) ため、`value_declared` は committed
        // のみで判定される形に自動的に縮退する — 型分岐を新設する必要はない。最終判定 (bool 特例
        // なしの型委譲) は resolve.mbt の後段フィルタが行う。
        //
        // issue 2026-07-13-structural-or-type-branch-required-missing /
        // codex-review-dr102-dr103-postland (M-2): `candidates` は structural or (直書き Or /
        // ref 経由) の場合、`display` 自身ではなく各枝の leaf name の配列 (node.mbt の
        // `RequiredCandidate`/`Required` doc comment 参照)。ref 経由の candidate は
        // `wrapper: Some(宣言元要素名)` を持ち、`candidate_declared` が宣言元要素自身の Scoped
        // 部分木内を探す。いずれか 1 つでも充足していれば OK — 「どの枝であれ発火して値が確定して
        // いること」が or 親の required 充足 (DR-093)。通常要素は `candidates ==
        // [{name: display, wrapper: None}]` なので判定は従来どおり単一名のまま。
        let mut any_ok = false
        for c in candidates {
          if candidate_declared(c, bindings, path, sc.entities) {
            any_ok = true
          }
        }
        if !any_ok {
          out.push(
            ParseError::constraint(
              display,
              "required_violated",
              "required '\{display}' is missing",
              pos,
            ),
          )
        }
      }
      RequiredGroup(group, members) => {
        // DR-103 §1: KTop の粗判定 — `Required` と全く同じゲート (`candidate_declared`、member の
        // いずれか 1 つでも「値が来る可能性がある」なら OK)。最終判定 (型委譲の実値、bool 特例
        // なし) は resolve.mbt の後段フィルタが行う。
        let mut any_ok = false
        for m in members {
          if candidate_declared(m, bindings, path, sc.entities) {
            any_ok = true
          }
        }
        if !any_ok {
          out.push(
            ParseError::constraint(
              group,
              "required_group_violated",
              "required group '\{group}' has no satisfied member",
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
/// SCB-Q1=a (docs/QUESTIONS.md、kawaz 裁定 2026-07-17): 未選択 (未入場) command scope に
/// 宣言された遅延述語は評価に参加しない。原理は「グローバルオプション以外、サブコマンドは完全に
/// 別コマンドと見るべき」で、root scope は常に選択済み。「選択」は当該実行で CommandSatisfied がその scope
/// に入場したこと。判定は bindings 内の `scope_marker` (`cont.mbt` KNest の `is_cmd=true` 分岐が
/// CommandSatisfied 入場時に prepend する `{key:"{}", scope:[label], ...}` binding、`nest` 展開でフル path に
/// 育つ) の存在で行う — 「入場したが何も発火しなかった」scope も scope_marker は自動で入るので、
/// 未入場 (絶対 absent) と区別できる。SCB-Q2=a (集約は scope 局所) は現実装通りで変更不要 —
/// `collect_scopes` が scope ごとに独立 ScopedCons を作り、`constraint installer` は宣言 scope 内で
/// 集約する。DR-103 §5 の「横断集約」は spec 側で誤記として note 訂正済み。
pub fn scope_selected(bindings : Array[Binding], path : Array[String]) -> Bool {
  if path.length() == 0 {
    return true
  }
  for b in bindings {
    if b.key == "{}" && b.scope == path {
      return true
    }
  }
  false
}

///|
pub fn command_scope_selected(
  bindings : Array[Binding],
  path : Array[String],
  ordinal : Int,
) -> Bool {
  for binding in bindings {
    if binding.key == "{}" && scope_path_eq(binding.scope, path) {
      match binding.value {
        Number(value) => if value.to_int() == ordinal { return true }
        _ => ()
      }
    }
  }
  false
}

///|
/// Evaluate every SELECTED scope's constraints (SCB-Q1=a、kawaz 裁定 2026-07-17): root scope
/// (path=[]) is always selected; a nested (CommandSatisfied) scope is selected only when it was actually
/// entered during this run (its `scope_marker` is present in `bindings`). Unselected scopes have
/// their predicates skipped — a subcommand's predicates are the *entered* subcommand's business,
/// not a sibling command's. Called from KTop so that "complete解決経路 = full consumption AND all
/// SELECTED-scope constraints satisfied" is a single definition the 取り分選好 oracle
/// (`has_full_k`) automatically shares — the parse() layer and the preference layer can no
/// longer disagree about completeness. For指定述語 (`exclusive_group`/`conflicts_with`/`requires`
/// トリガ側) the skip is observation-equivalent to the previous vacuous-true evaluation (member
/// count 0, no committed target); for値述語 (`required`/`required_group`) it changes behaviour
/// exactly where the SCB-Q1 裁定 requires (未入場 scope の required は違反にしない).
pub fn scoped_constraints_selected(
  bindings : Array[Binding],
  scoped : ScopedCons,
) -> Bool {
  if scoped.path.length() != scoped.command_ordinals.length() {
    return false
  }
  let prefix : Array[String] = []
  for index in 0..<scoped.path.length() {
    prefix.push(scoped.path[index])
    if !command_scope_selected(bindings, prefix, scoped.command_ordinals[index]) {
      return false
    }
  }
  true
}

///|
fn eval_all_constraints(
  table : Array[ScopedCons],
  bindings : Array[Binding],
  pos : Int,
) -> Array[ParseError] {
  let out : Array[ParseError] = []
  for sc in table {
    if !scoped_constraints_selected(bindings, sc) {
      continue
    }
    for v in eval_constraints(sc, bindings, pos) {
      out.push(v)
    }
  }
  out
}

// ── static scope collection (the KTop constraint table) ──────────────────────

///|
/// Collect (result-path, constraints, entities) for the root scope and every
/// statically reachable nested scope: CommandSatisfied children (path + [name], also
/// inside Or-bundled greedy entries), inline positional ScopeNodes and
/// scope-shaped repeat heads (transparent — same path, their bindings are
/// not nested). Scopes with no constraints are skipped (nothing to check).
///
/// Known limitation (documented, not enforced): a repeat-instantiated
/// transparent scope shares its path across reps, so its constraints see the
/// MERGED final state of all reps; per-rep predicate instances are not spec'd
/// (no DR defines them). IndexedRepeat's indexed paths ("#k") are out of scope.
pub fn collect_scopes(
  root : Node,
  defs : Map[String, Node],
) -> Array[ScopedCons] {
  let out : Array[ScopedCons] = []
  match root {
    ScopeNode(sc) => collect_scope_into(sc, [], [], defs, out, [])
    _ => ()
  }
  out
}

///|
fn collect_scope_into(
  sc : Scope,
  path : Array[String],
  command_ordinals : Array[Int],
  defs : Map[String, Node],
  out : Array[ScopedCons],
  seen_refs : Array[String],
) -> Unit {
  if sc.constraints.length() > 0 {
    out.push({
      path,
      command_ordinals,
      constraints: sc.constraints,
      entities: sc.entities,
    })
  }
  for g in sc.greedy {
    collect_greedy_scopes(g, path, command_ordinals, defs, out, seen_refs)
  }
  for p in sc.positional {
    collect_pos_scopes(p, path, command_ordinals, defs, out, seen_refs)
  }
}

///|
fn collect_greedy_scopes(
  g : Node,
  path : Array[String],
  command_ordinals : Array[Int],
  defs : Map[String, Node],
  out : Array[ScopedCons],
  seen_refs : Array[String],
) -> Unit {
  match g {
    CommandSatisfied(_, name, ordinal, child) => {
      let p2 = path.copy()
      p2.push(name)
      let ordinals = command_ordinals.copy()
      ordinals.push(ordinal)
      collect_scope_into(child, p2, ordinals, defs, out, seen_refs)
    }
    Or(alts) =>
      for a in alts {
        collect_greedy_scopes(a, path, command_ordinals, defs, out, seen_refs)
      }
    LinkTarget(_, _, _, _, _, _, _, _, _, inner) =>
      collect_greedy_scopes(inner, path, command_ordinals, defs, out, seen_refs)
    Rooted(inner, _) =>
      collect_greedy_scopes(inner, path, command_ordinals, defs, out, seen_refs)
    _ => ()
  }
}

///|
fn collect_pos_scopes(
  n : Node,
  path : Array[String],
  command_ordinals : Array[Int],
  defs : Map[String, Node],
  out : Array[ScopedCons],
  seen_refs : Array[String],
) -> Unit {
  match n {
    ScopeNode(child) =>
      collect_scope_into(child, path, command_ordinals, defs, out, seen_refs)
    Ref(name) =>
      if !str_mem(seen_refs, name) {
        let seen2 : Array[String] = []
        for s in seen_refs {
          seen2.push(s)
        }
        seen2.push(name)
        match ref_head(defs, name) {
          ScopeNode(child) =>
            collect_scope_into(child, path, command_ordinals, defs, out, seen2)
          _ => ()
        }
      }
    BoundedTail(head, _, _) =>
      match head {
        ScopeNode(child) =>
          collect_scope_into(
            child, path, command_ordinals, defs, out, seen_refs,
          )
        _ => ()
      }
    Many(inner, _) =>
      collect_pos_scopes(inner, path, command_ordinals, defs, out, seen_refs)
    _ => ()
  }
}

// ── top level (spec DR-038 path counting) ────────────────────────────────────

///|
fn int_contains(values : Array[Int], target : Int) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

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
pub fn parse_tree(
  root : Node,
  toks : Array[String],
  defs? : Map[String, Node] = Map([]),
  faildef? : FailDef = WithHeld,
  extensions? : Registry = Registry::new(),
  // DR-114 §6.1 の一本化 (W2-9 findings「実行一本化の設計」): `ladder` は明示 `default` 効果の
  // 落ち先 (DR-081 §2 の書き換え済み default) を parse 相 fold へ供給する closure (呼び手 =
  // front_door が値源 provider で実装する)。`firings` は勝ち経路 (dedup 後の完全経路) ごとの
  // FiringRecord 台帳の配達口 — 値残余セル分は枝ローカル fold の枝内実行結果を引き継ぎ、
  // 値残余の無い Invoke セルは裁定後に 1 回だけ実行して記録する。未供給 (None) は record を
  // 作らない従来経路 (fold は枝選別のためだけに走る)。
  ladder? : (Entity, Array[String], Array[Binding]) -> Value?,
  firings? : @fold.FiringDeliveries,
) -> Outcome {
  let ctx : Ctx = { toks, defs, extensions_: extensions, mode: ModeParse }
  // codex 指摘 (2026-07-12): dedup 判定 (下の `eff`/`dedup_key`) から dd/none の committed
  // placeholder binding を除外するための (path, name) 集合 — `none_cells` (resolve.mbt、
  // build_result が NoneCell として結果から除外する既存機構をそのまま再利用)。root が
  // `ScopeNode` でない場合 (dd/none は Scope 経由でのみ意味を持つ構造) は空集合のまま。
  let nones = match root {
    ScopeNode(sc) => none_cells(sc, defs)
    _ => []
  }
  let branches = match root {
    ScopeNode(sc) =>
      scope_step(sc, ctx, 0, 0, [], false, KTop(collect_scopes(root, defs)))
    _ =>
      eval_with_downstream(
        root,
        ctx,
        0,
        (ctx2, next_pos, bindings) => {
          run_cont(KTop([]), ctx2, next_pos, bindings)
        },
        (_ctx, error, bindings) => [Rejected(error, bindings)],
        (_ctx, error, bindings) => [Held(error, bindings)],
        (_ctx, candidates, bindings) => [Pending(candidates, bindings)],
      )
  }
  // DR-127 §4.2: 裁定 (完全経路カウント) の前に、完全枝ごとの効果列を畳んで値空間残余の
  // 解決可否を判定する。解決不能な完全枝は Held 等価へ写す — 合成 ParseError が args_pos で
  // max_reach / push_error / faildef に寄与するので、全枝落ちでも失敗レポートに原因が載る
  // (DR-037 の帰属原則)。値残余を持たない枝 (= 既存の全経路) は素通しで、fold は走らない。
  // partial Accept (p < toks.length()) は裁定に参加しない (完全経路の系の外) ため畳まない —
  // 落ちる理由は token 残余として既に観測されている。
  let mut seat_decls : Map[String, Array[SeatDecl]]? = None
  // 完全枝ごとの枝ローカル fold の実行記録 (folded と並走)。勝ち枝の ledger は裁定後に
  // firings へ配達され、値残余セルの fn を再実行しない (DR-114 §6.1)。
  let branch_ledgers : Array[@fold.FiringLedger?] = []
  let branches = {
    let folded : Array[Branch] = []
    for b in branches {
      match b {
        Accept(p, bs) if p == toks.length() && binding_has_value_residual(bs) => {
          let decls = match seat_decls {
            Some(decls) => decls
            None => {
              let decls = collect_seat_decls(root, defs)
              seat_decls = Some(decls)
              decls
            }
          }
          let eff = strip_levels_to_declaring_scope(bs)
          let ledger : @fold.FiringLedger? = match firings {
            Some(_) => Some(@fold.FiringLedger::new())
            None => None
          }
          // 値残余セルは独立に裁かれるので複数の失敗が同時に返りうる (DR-138 §4 —
          // 1 読みの中に union セルが 2 個あれば両方の incomplete_value が観測される)。
          // Held は 1 件 1 error なので、error ごとに Held 枝を立てる。いずれも
          // 完全経路ではないため経路数には影響せず、最終 errors 集合で合流する。
          let cell_errors = branch_fold_reject(
            eff, p, decls, extensions, ladder, ledger,
          )
          if cell_errors.length() == 0 {
            folded.push(b)
            branch_ledgers.push(ledger)
          } else {
            for pe in cell_errors {
              folded.push(Held(pe, bs))
              branch_ledgers.push(None)
            }
          }
        }
        _ => {
          folded.push(b)
          branch_ledgers.push(None)
        }
      }
    }
    folded
  }
  let full : Array[Array[Binding]] = []
  // full と並走する勝ち候補ごとの ledger (dedup で残った枝のもの。値残余の無い枝は None)。
  let full_ledgers : Array[@fold.FiringLedger?] = []
  let errors : Array[ParseError] = []
  let structural_repeat_residuals : Array[Int] = []
  // the deepest args position any branch reached (DeepestOnly candidate set).
  let mut max_reach = -1
  for b in branches {
    match b {
      Accept(p, _) => if p > max_reach { max_reach = p }
      Rejected(_, _) => ()
      Held(pe, _) => if pe.args_pos > max_reach { max_reach = pe.args_pos }
      Pending(_, _) =>
        // a Pending consumed every token it saw (input exhausted).
        if toks.length() > max_reach {
          max_reach = toks.length()
        }
    }
  }
  let actions : Array[(String, Int)] = []
  for branch_index in 0..<branches.length() {
    let b = branches[branch_index]
    match b {
      Accept(p, bs) => {
        // constraint satisfaction is already decided at KTop (a violating
        // full consumption arrives as Helds, never an Accept), so every
        // full-length Accept here IS a complete解決経路.
        if p == toks.length() {
          let eff = strip_levels_to_declaring_scope(bs)
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
            full_ledgers.push(branch_ledgers[branch_index])
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
      Rejected(_, _) => ()
      Held(pe, bs) => {
        if is_scope_residual(pe) {
          for binding in bs {
            if binding.key.length() >= 7 && binding.key[0:7] == "#accum:" {
              let mut seen = false
              for pos in structural_repeat_residuals {
                if pos == pe.args_pos {
                  seen = true
                  break
                }
              }
              if !seen {
                structural_repeat_residuals.push(pe.args_pos)
              }
              break
            }
          }
        }
        push_error(errors, pe)
        let counts = match faildef {
          AcceptsOnly => false
          WithHeld => true
          DeepestOnly => pe.args_pos == max_reach
        }
        if counts {
          collect_actions(bs, actions)
        }
      }
      Pending(cands, bs) => {
        // MDR-002 §2.3: a starved value slot is an error the slice used to
        // swallow. One missing-operand Error per value candidate origin.
        // DR-066 §4 (issue 2026-07-08 pending-starvation-missing-operand-path):
        // the candidate's own path (already prepended by scope boundaries
        // on its way out to this top-level branches array, same as a Held's
        // ParseError.path) overrides `pe_missing`'s default `[]` — this is
        // the ONE conversion point where a Pending becomes a ParseError, so
        // it is also the one place that needs to carry the path across.
        //
        // issue 2026-07-15-pending-parseerror-path-asymmetry: uses `c.fire_path`, NOT `c.path`.
        // `path` carries the Rooted-escape adjustment (`levels_to_declaring_scope`)
        // `complete_tree`'s completer lookup needs, which is the WRONG path for this conversion — a
        // global option's value-slot candidate copied into a descendant command scope reports the
        // DECLARING scope's path via `path` (by design, for completion), but `missing_operand` needs
        // the scope it was actually READ under (DR-066 §4's "発火時の動的パス"). Using `path` here
        // produced 2-3 duplicate errors for the SAME starved slot (one per re-evaluation the CPS walk
        // performs — root-copy, any mid-nesting re-entry, and the innermost read), each with a
        // DIFFERENT (and mostly wrong) path, because `levels_to_declaring_scope`'s escape bookkeeping
        // diverges per candidate while `fire_path` does not. `fire_path` (`Candidate.fire_path` doc
        // comment) is prepended unconditionally by every scope boundary regardless of
        // `levels_to_declaring_scope`, so every duplicate reading of the SAME starved slot carries
        // the SAME `fire_path` — `push_error`'s dedup (element, args_pos, kind, reason, path) then
        // collapses them to the single correct entry instead of leaving path-mismatched duplicates.
        for c in cands {
          if c.is_value {
            push_error(errors, {
              ..pe_missing(c.origin, toks.length()),
              path: c.fire_path,
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
        args_pos: max_partial,
        kind: Parse,
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
    if is_scope_residual(e) && e.args_pos > deepest_resid {
      deepest_resid = e.args_pos
    }
  }
  let errors2 : Array[ParseError] = []
  for e in errors {
    if is_scope_residual(e) &&
      e.args_pos < deepest_resid &&
      !int_contains(structural_repeat_residuals, e.args_pos) {
      continue
    }
    // 同じ位置の scope 残余は、どの読みがそこで止まったかに依らず**同じ躓き 1 つ**である。
    // 複数の読みが同一トークンで止まると path (どのスコープを歩いていたか) だけが違う複製が
    // 並ぶが、element は "" (スコープレベルの躓き) で利用者に見える内容は同一なので 1 件へ畳む。
    // path が残余に対して規範を持たないことは corpus 側でも裏取り済み — `unexpected_token` を
    // 期待する 32 case のうち `path` を pin するものは 0 件。
    if is_scope_residual(e) {
      let mut seen = false
      for kept in errors2 {
        if is_scope_residual(kept) && kept.args_pos == e.args_pos {
          seen = true
          break
        }
      }
      if seen {
        continue
      }
    }
    errors2.push(e)
  }
  let errors = errors2
  // DR-114 §6.1: 勝ち候補ごとの FiringRecord 台帳を配達する。値残余セル分は枝ローカル fold の
  // 枝内実行結果 (branch_ledgers) を引き継ぎ、値残余の無い Invoke セルは裁定後のこの 1 回の
  // fold (`branch_fold_plain_records`) で実行・記録する。
  match firings {
    Some(deliveries) =>
      for path_index in 0..<full.length() {
        let eff = full[path_index]
        let ledger = match full_ledgers[path_index] {
          Some(ledger) => ledger
          None => @fold.FiringLedger::new()
        }
        if binding_has_plain_invoke(eff) {
          let decls = match seat_decls {
            Some(decls) => decls
            None => {
              let decls = collect_seat_decls(root, defs)
              seat_decls = Some(decls)
              decls
            }
          }
          branch_fold_plain_records(eff, decls, extensions, ladder, ledger)
        }
        deliveries.deliver(eff, ledger)
      }
    None => ()
  }
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
      // DR-038: ambiguity is structural — 2 本以上の完全経路がそのまま解釈になる。各解釈は
      // 経路構造 (= binds) で互いに区別できる。
      // help_entry: ambiguous には単一の「失敗位置」が無い (複数完全経路が成立している) ので、
      // `find_help_entry` へ空の errors を渡して root scope 全体を見る従来どおりの posture に
      // 留める (`find_help_entry`のフォールバック分岐、failure 側の失敗位置基準とは意図的に別)。
      Ambiguous({
        interpretations: {
          let a : Array[AmbiguousInterpretation] = []
          for f in full {
            a.push({ binds: f })
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
