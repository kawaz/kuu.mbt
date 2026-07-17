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
pub struct Ctx {
  priv toks : Array[String]
  priv defs : Map[String, Node]
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
/// Construct a parse-mode context for direct extension and matcher evaluation.
pub fn parse_context(toks : Array[String]) -> Ctx {
  { toks, defs: Map([]), mode: ModeParse }
}

///|
/// parse counts complete paths (DR-038); complete collects expectations
/// (DR-060). The walk is ONE implementation — mode switches the
/// collection-policy points below (MDR-002 §2.4):
/// - boundary trigger sites (Exact / CmdSat / DdSat / NativeMatch at args
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
/// (term = Cont, e.g. an eq-split `--key`); a plain trigger carries "flag".
pub fn cand_trigger(
  spelling : String,
  origin : String,
  ty : String,
  term : TermHint,
  is_alias : Bool,
  hidden : Bool,
  deprecated : Bool,
) -> Cand {
  {
    spelling,
    is_value: false,
    ty,
    origin,
    term,
    meta: { is_alias, hidden, deprecated },
    path: [], // DR-066 §4: prepended by scope boundaries on the way out (nest_branches / CmdSat)
    link: 0, // no pending Rooted-escape at construction (Rooted's own eval arm sets this)
    fire_path: [], // issue 2026-07-15-pending-parseerror-path-asymmetry: same "starts empty, scope
    // boundaries prepend unconditionally" posture as `path`/Held's own `ParseError.path` (`nest_path`
    // in `nest_cands`) — this is the exact-trigger sibling of `pend_value`'s same field, kept in sync.
    completer: None, // DR-060 §3: an exact-trigger candidate never carries a completer
  }
}

///|
/// A non-set effect binding (default / unset / empty). The operand is a
/// placeholder — these ops carry no operand (spec DR-045 table).
pub fn mk_eff(key : String, op : EffectOp, source : Source) -> Binding {
  { key, op, value: VBool(false), source, scope: [], link: 0, at_pos: None }
}

///|
/// A failure-action marker binding (spec DR-048): key `@act:<name>`, value =
/// the args position where the action was selected (args-min tie-break).
pub fn action_marker(name : String, pos : Int) -> Binding {
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
fn is_depr_key(k : String) -> Bool {
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
/// One `warnings[]` entry (spec CONFORMANCE §2 warnings 面: kuu-cli の JSON wire は
/// `{"element": <name>, "kind": <kind>}` のオブジェクト配列で返す)。`kind` は現状 `"deprecated"`
/// のみ (spec DR-058)、将来の warning 語彙 (`lint` 等の DR-021 系譜、DR-047 §7 診断モード)
/// が増えたときに variant を拡張しやすいよう、名前ペアを型として運ぶ (kuu-cli PoC codex レビュー
/// 2026-07-15 の M-1 解消 — 素の element name 配列だと kind 情報が落ちるため、下流の JSON
/// 射影に kind を持たせられない)。
pub(all) struct Warning {
  element : String
  kind : String
} derive(Eq, Debug)

///|
/// 構造化した warnings (spec CONFORMANCE §2 warnings 面素材)。現状 `@depr:` sentinel から
/// `kind: "deprecated"` を組み立てて返す (spec DR-058) — `warnings_of` の同機能で kind 情報を
/// 保持する版。element の重複は排除 (first-seen 順、`warnings_of` と同じ dedup 規約)。
pub fn warnings_structured(o : Outcome) -> Array[Warning] {
  let out : Array[Warning] = []
  match o {
    Success(binds) =>
      for b in binds {
        if is_depr_key(b.key) {
          let name = b.key[6:].to_owned()
          let mut seen = false
          for w in out {
            if w.element == name && w.kind == "deprecated" {
              seen = true
              break
            }
          }
          if !seen {
            out.push({ element: name, kind: "deprecated" })
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
///
/// Also mirrors `nest`'s `Binding.link` decrement (DR-060 §4 / issue
/// 2026-07-14-cand-completer-followup): a candidate with `link > 0` (set by `Rooted`'s eval arm)
/// is still escaping toward its declaring scope — this level's prepend is SKIPPED and the counter
/// decremented instead, exactly like a linked Binding's `scope` field. Without this, a global
/// option's value-slot candidate would accumulate the COPY-side scope path instead of the
/// DECLARING scope's, and `complete_tree`'s `(path, origin)`-keyed completer lookup would miss
/// the Entity (which lives only at the declaring scope).
///
/// `fire_path` (issue 2026-07-15-pending-parseerror-path-asymmetry) is prepended UNCONDITIONALLY,
/// every call, regardless of `link` — it tracks the actual walk position (same rule `nest_path`
/// applies to a Held's `ParseError.path`), never the Rooted-escape-adjusted `path`. This is what lets
/// `missing_operand`'s KTop conversion (below) read a path that matches across every duplicate
/// reading of the same starved slot (see `Cand.fire_path`'s doc comment for why `link`-gating the
/// KTop conversion instead doesn't work — `link` is always 0 by the time a candidate reaches KTop).
fn nest_cands(label : String, cs : Array[Cand]) -> Array[Cand] {
  let out : Array[Cand] = []
  for c in cs {
    if c.link > 0 {
      out.push({
        ..c,
        link: c.link - 1,
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
pub fn pend_value(ty : String, origin : String) -> Cand {
  {
    spelling: "",
    is_value: true,
    ty,
    origin,
    term: WordEnd,
    meta: { is_alias: false, hidden: false, deprecated: false },
    path: [], // DR-066 §4: prepended by scope boundaries on the way out (nest_branches / CmdSat)
    link: 0, // no pending Rooted-escape at construction (Rooted's own eval arm sets this)
    fire_path: [], // issue 2026-07-15-pending-parseerror-path-asymmetry: `Cand.fire_path`'s doc
    // comment — the fire-time walk-position path a `missing_operand` ParseError conversion needs,
    // tracked independently of `path`'s Rooted-escape (`link`) bookkeeping.
    // DR-060 §4 / DR-104 §2(d): filled in by `complete_tree`'s (path, origin)-keyed Entity-table
    // lookup (outcome.mbt) as candidates fold into the dedup loop, NOT here — `pend_value` has no
    // Entity table in scope at any of its 30+ call sites (see Cand.completer's doc comment).
    completer: None,
  }
}

///|
/// A mandatory spine slot maps a resident's value `Pending` to the same
/// missing-operand Held the closed primitive arms used in parse mode. Complete
/// mode preserves Pending as candidate material; off-spine eval bypasses this
/// helper and therefore preserves its existing Pending representation.
fn eval_required_ext(
  extension : &NodeExt,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
  next : Resume,
) -> Array[Branch] {
  let branches = extension.eval(ctx, pos, acc, next)
  // Only a non-zero-token resident invoked directly at EOF can have produced
  // its own local value Pending. If a token existed, any Pending in the return
  // may come from `next`; rewriting it here would move the downstream error to
  // this resident's start position and discard its fire_path.
  if in_complete(ctx) ||
    extension.consumes_zero_tokens() ||
    ctx.token_at(pos) is Some(_) {
    return branches
  }
  let out : Array[Branch] = []
  for branch in branches {
    match branch {
      Pending(cands, bs) => {
        let mut converted = false
        for cand in cands {
          if cand.is_value {
            out.push(Held(pe_missing(cand.origin, pos), bs))
            converted = true
          }
        }
        if !converted {
          out.push(Pending(cands, bs))
        }
      }
      other => out.push(other)
    }
  }
  out
}

///|
/// Resume every native matcher reading through one evaluator continuation. The
/// engine owns the common branch loop so all resident-produced readings keep
/// equal standing; residents own only token interpretation and configuration.
pub fn continue_matcher(
  readings : Array[Branch],
  ctx : Ctx,
  acc : Array[Binding],
  next : Resume,
) -> Array[Branch] {
  let out : Array[Branch] = []
  for reading in readings {
    match reading {
      Accept(next_pos, bindings) =>
        for branch in next(ctx, next_pos, cat(acc, bindings)) {
          out.push(branch)
        }
      Held(error, bindings) => out.push(Held(error, cat(acc, bindings)))
      Pending(candidates, bindings) =>
        out.push(Pending(candidates, cat(acc, bindings)))
    }
  }
  out
}

///|
/// Interpret one opaque matcher with an identity continuation for direct-style
/// probes and off-spine evaluation.
pub fn run_matcher(
  matcher : &MatcherExt,
  ctx : Ctx,
  pos : Int,
) -> Array[Branch] {
  if ctx.token_at(pos) is None {
    return []
  }
  matcher.interpret(ctx, pos, [], (_ctx, next_pos, next_acc) => {
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
        [
          Pending([cand_trigger(s, s, "flag", WordEnd, false, false, false)], []),
        ]
      } else {
        // an unmatched (or, in parse mode, exhausted) trigger is a silent
        // Reject (spec DR-037), NOT a Pending: no part of the entry was
        // consumed, so nothing is "half-read".
        []
      }
    ReqArg(name) => req_arg_eval(name, ctx, pos, [])
    Bind(name, v) => [Accept(pos, [mkb(name, v, Cli)])]
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
        [Pending(m.candidates(), [])]
      } else {
        run_matcher(m, ctx, pos)
      }
    Ext(extension) =>
      extension.eval(ctx, pos, [], (_ctx, next_pos, next_acc) => {
        [Accept(next_pos, next_acc)]
      })
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
        [
          Pending(
            [
              cand_trigger(
                trigger,
                trigger,
                "flag",
                WordEnd,
                false,
                false,
                false,
              ),
            ],
            [],
          ),
        ]
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
        // DR-104 §2 origin = 由来要素名: `elem_name` (DR-090 §2, spelling と独立の同一性軸), NOT
        // `spelling` (a `match` trigger's regex-derived literal is not the element's name).
        [
          Pending(
            [
              cand_trigger(
                spelling,
                elem_name,
                "flag",
                WordEnd,
                false,
                false,
                false,
              ),
            ],
            [],
          ),
        ]
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
        [
          Pending(
            [cand_trigger(name, name, "flag", WordEnd, false, false, false)],
            [],
          ),
        ]
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
          Pending(cs, bs) => {
            // Mirror the Accept arm's `link: depth` marking, but on Cand.link (DR-060 §4 /
            // issue 2026-07-14-cand-completer-followup): a global option's copied satellite
            // lives `depth` scopes below its OWN declaring scope, and its Entity (the one
            // `complete_tree`'s completer lookup needs) sits at that declaring scope, not
            // here — `nest_cands` (below) consumes this exactly like `nest` consumes
            // `Binding.link`, skipping `depth` CmdSat-boundary prepends on the way out.
            let marked : Array[Cand] = []
            for c in cs {
              marked.push({ ..c, link: depth })
            }
            out.push(Pending(marked, bs))
          }
        }
      }
      out
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
/// token to consume (構造的必須の不成立, spec DR-065 §3): args_pos = args
/// length (where the token was requested).
fn pe_missing(element : String, pos : Int) -> ParseError {
  {
    element,
    args_pos: pos,
    kind: KParse,
    reason: "missing_operand",
    message: "missing operand for \{element}",
    path: [],
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
    [Pending([pend_value("string", name)], acc)]
  } else {
    [
      Held(
        {
          element: name,
          args_pos: pos,
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
fn first_char(s : String) -> Char {
  for c in s {
    return c
  }
  ',' // unreachable for a non-empty separator
}

///|
/// DR-091 §2: whether `s` contains at least one `=` — the `kv resident` consume-time gate's structural
/// precondition (a `kv_map` accumulator piece must be shaped `k=v`, checked BEFORE `build_result`
/// ever tries to split it — this function only answers "is there a split point at all", the actual
/// first-`=` split happens once in `resolve.mbt` at fold time, `split_first_eq`).
pub fn contains_eq(s : String) -> Bool {
  for c in s {
    if c == '=' {
      return true
    }
  }
  false
}

///|
/// Split `s` on the first char of `sep` (spec DR-034 single-char separator).
pub fn split_on(s : String, sep : String) -> Array[String] {
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
/// pieceProcessor: separator → piece_filters → parse → value_filters (each piece) → once the value
/// is committed, final_filters (non-accum element) or, after accumulation, accum_filters (accum
/// element); a piece's
/// type is independent of whether it came via separator, `elem_head`'s pre-段2 "always VStr"
/// shortcut was the bug this closes). A piece_filters reject OR a type-parse failure on ANY piece
/// fails the WHOLE binding (`Err` short-circuits) — same all-or-nothing contract a single-piece
/// value primitive has; the two failure kinds stay distinct (`KFilter` vs `KParse`, mirrored from
/// the scalar value-primitive arms' own pe_filter/pe_parse split).
/// `pos` (issue 2026-07-09-accum-entity-filters-wiring): every split piece is attributed to the
/// SAME args token position — a piece is not itself a token, so there is no finer-grained position
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
pub fn parse_fail_error(
  name : String,
  token : String,
  pos : Int,
  fail : ParseFail,
) -> ParseError {
  match fail {
    NotAnInteger => pe_parse_int(name, token, pos)
    IntOutOfRange => pe_int_out_of_range(name, token, pos)
    NotABool => pe_parse_bool(name, token, pos)
    NotANumber | NoValueSpace => pe_parse(name, token, pos)
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
      // bound EARLIER in the same entry (e.g. `--help`'s failure resident before a
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
/// value-primitive arms (string resident/number resident/etc.) return an EXPLICIT Pending at
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
            ReqArg(name) | Bind(name, _) | Scoped(name, _) => Some(name)
            _ => None
          }
      }
  }
}

///|
/// Whether `g` is (possibly through a `Rooted` global-link wrap) an option satellite's head Seq —
/// and if so, the real origin name its tail carries. `None` for any other shape (CmdSat/DdSat/
/// DdMatchSat/NativeMatch already carry their own correct origin, no fixup needed there; a bare
/// `Exact` alone or an unrecognized tail shape is left as the spelling fallback, unchanged).
fn cand_boundary_origin(g : Node) -> String? {
  match g {
    Rooted(inner, _) => cand_boundary_origin(inner)
    Seq([Exact(_), rest, ..]) => seq_boundary_name(rest)
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
/// Apply `cand_boundary_origin`'s correction (+ the owning element's `hidden` declaration) to every
/// exact-trigger candidate (`is_value:false`) a satellite's Pending carries; a value-position
/// candidate (`is_value:true`, always built via `pend_value` with the correct origin already) is
/// left untouched. A `None` origin (not an option-satellite boundary shape) is a no-op passthrough.
fn fixup_boundary_cands(g : Node, sc : Scope, cs : Array[Cand]) -> Array[Cand] {
  match cand_boundary_origin(g) {
    None => cs
    Some(origin) => {
      let extension = entity_extension(sc, origin)
      let out : Array[Cand] = []
      for c in cs {
        if c.is_value {
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
          Pending(
            [cand_trigger(name, name, "flag", WordEnd, false, false, false)],
            acc,
          ),
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
          Pending(
            [
              cand_trigger(
                trigger,
                trigger,
                "flag",
                WordEnd,
                false,
                false,
                false,
              ),
            ],
            acc,
          ),
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
        // DR-104 §2 origin = 由来要素名: `elem_name`, mirroring the off-spine arm's fix above.
        out.push(
          Pending(
            [
              cand_trigger(
                spelling,
                elem_name,
                "flag",
                WordEnd,
                false,
                false,
                false,
              ),
            ],
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
              // acc must be carried on Held so an earlier failure resident (fired_action
              // material, eval_seq comment DR-048/DR-053 §4) survives to parse().
              Held(pe, bs) => out.push(Held(pe, cat(acc, bs)))
              Pending(cs, bs) =>
                out.push(Pending(fixup_boundary_cands(g, sc, cs), cat(acc, bs)))
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
          [Pending([pend_value("string", name)], acc)]
        } else {
          [
            Held(
              {
                element: name,
                args_pos: pos,
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
        // positional-spine literal (a structural or-branch's exact value, not an option
        // trigger) — origin IS the spelling here, there is no separate element name to
        // extract (none of our fixtures exercise this shape yet, kept as-is).
        [
          Pending(
            [cand_trigger(s, s, "flag", WordEnd, false, false, false)],
            acc,
          ),
        ]
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
            // scope_step / scope_consume family only. Revisit if a failure resident
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
    // ReqArg gets its own arm so 先食い (suppressed) applies —
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
          [Pending([pend_value("string", name)], [])]
        } else {
          [
            Held(
              {
                element: name,
                args_pos: pos,
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
    Ext(_) | ReqArg(_) => consume_head(sc, node, ctx, pos, severed)
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
fn head_elem_names_into(node : Node, out : Array[String]) -> Unit {
  match node_resident_name(node) {
    Some(name) => if !str_mem(out, name) { out.push(name) }
    None => ()
  }
  match node {
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
    Ext(extension) =>
      if extension.consumes_zero_tokens() ||
        (pos < ctx.toks.length() && !suppressed(sc, ctx, pos, severed)) {
        extension.eval(ctx, pos, acc, (ctx2, next_pos, next_acc) => {
          if next_pos > pos {
            scope_step(sc, ctx2, next_pos, pidx, next_acc, severed, k)
          } else {
            []
          }
        })
      } else if pos >= ctx.toks.length() && in_complete(ctx) {
        extension.eval(ctx, pos, acc, (_ctx, next_pos, next_acc) => {
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
        Unset => committed = false
        _ => committed = true
      }
    }
  }
  committed
}

///|
/// The committed value of the (path, name) cell (last-wins), or None.
pub fn elem_value(
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
pub fn constraint_err(
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
  { element, args_pos: pos, kind: KConstraint, reason, message, path: [] }
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
        Unset => committed = false
        _ => committed = true
      }
    }
  }
  committed
}

///|
/// `elem_value` の `RequiredCandidate.wrapper` 対応版 (codex レビュー M-2 修正、`is_committed_in_
/// subtree` と対)。
pub fn elem_value_in_subtree(
  bindings : Array[Binding],
  path : Array[String],
  wrapper : String,
  name : String,
) -> String? {
  let mut v : String? = None
  for b in bindings {
    if b.key == name && scope_in_wrapped_subtree(b.scope, path, wrapper) {
      match b.op {
        Unset => ()
        _ => v = Some(value_str(b.value))
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
/// 要素、`ensure_entity_body` の BCell コメント参照) ため、`value_declared` の entities フォール
/// バック検索 (default/env/config/inherit の宣言有無) は wrapper 付き candidate には意味を持たず、
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
        // DR-093 §1/§2: KTop の粗判定 (完全経路の成立条件、DR-047 §2) — `candidate_declared`
        // (`value_declared` の RequiredCandidate 対応版、codex M-2 修正) をそのまま再利用する
        // (CRequires 目的語と同じゲート)。値空間なし (none) の要素は default_values/env_key/
        // config_seat/inherit_ をそもそも持てない (DR-089 §7) ため、`value_declared` は committed
        // のみで判定される形に自動的に縮退する — 型分岐を新設する必要はない。最終判定 (bool 特例
        // なしの型委譲) は resolve.mbt の後段フィルタが行う。
        //
        // issue 2026-07-13-structural-or-type-branch-required-missing /
        // codex-review-dr102-dr103-postland (M-2): `candidates` は structural or (直書き BOr /
        // ref 経由) の場合、`display` 自身ではなく各枝の leaf name の配列 (node.mbt の
        // `RequiredCandidate`/`CRequired` doc comment 参照)。ref 経由の candidate は
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
            constraint_err(
              display,
              "required_violated",
              "required '\{display}' is missing",
              pos,
            ),
          )
        }
      }
      CRequiredGroup(group, members) => {
        // DR-103 §1: KTop の粗判定 — `CRequired` と全く同じゲート (`candidate_declared`、member の
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
            constraint_err(
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
/// 別コマンドと見るべき」で、root scope は常に選択済み。「選択」は当該実行で CmdSat がその scope
/// に入場したこと。判定は bindings 内の `scope_marker` (`cont.mbt` KNest の `is_cmd=true` 分岐が
/// CmdSat 入場時に prepend する `{key:"{}", scope:[label], ...}` binding、`nest` 展開でフル path に
/// 育つ) の存在で行う — 「入場したが何も発火しなかった」scope も scope_marker は自動で入るので、
/// 未入場 (絶対 absent) と区別できる。SCB-Q2=a (集約は scope 局所) は現実装通りで変更不要 —
/// `collect_scopes` が scope ごとに独立 ScopedCons を作り、`constraint installer` は宣言 scope 内で
/// 集約する。DR-103 §5 の「横断集約」は spec 側で誤記として note 訂正済み。
pub fn scope_selected(bindings : Array[Binding], path : Array[String]) -> Bool {
  if path.length() == 0 {
    return true
  }
  for b in bindings {
    if b.key == "{}" && b.scope.length() == path.length() {
      let mut eq = true
      let mut i = 0
      for s in b.scope {
        if s != path[i] {
          eq = false
        }
        i = i + 1
      }
      if eq {
        return true
      }
    }
  }
  false
}

///|
/// Evaluate every SELECTED scope's constraints (SCB-Q1=a、kawaz 裁定 2026-07-17): root scope
/// (path=[]) is always selected; a nested (CmdSat) scope is selected only when it was actually
/// entered during this run (its `scope_marker` is present in `bindings`). Unselected scopes have
/// their predicates skipped — a subcommand's predicates are the *entered* subcommand's business,
/// not a sibling command's. Called from KTop so that "complete解決経路 = full consumption AND all
/// SELECTED-scope constraints satisfied" is a single definition the 取り分選好 oracle
/// (`has_full_k`) automatically shares — the parse() layer and the preference layer can no
/// longer disagree about completeness. For指定述語 (`exclusive_group`/`conflicts_with`/`requires`
/// トリガ側) the skip is observation-equivalent to the previous vacuous-true evaluation (member
/// count 0, no committed target); for値述語 (`required`/`required_group`) it changes behaviour
/// exactly where the SCB-Q1 裁定 requires (未入場 scope の required は違反にしない).
fn eval_all_constraints(
  table : Array[ScopedCons],
  bindings : Array[Binding],
  pos : Int,
) -> Array[ParseError] {
  let out : Array[ParseError] = []
  for sc in table {
    if !scope_selected(bindings, sc.path) {
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
/// statically reachable nested scope: CmdSat children (path + [name], also
/// inside Or-bundled greedy entries), inline positional ScopeNodes and
/// scope-shaped repeat heads (transparent — same path, their bindings are
/// not nested). Scopes with no constraints are skipped (nothing to check).
///
/// Known limitation (documented, not enforced): a repeat-instantiated
/// transparent scope shares its path across reps, so its constraints see the
/// MERGED final state of all reps; per-rep predicate instances are not spec'd
/// (no DR defines them). IdxRepeat's indexed paths ("#k") are out of scope.
pub fn collect_scopes(
  root : Node,
  defs : Map[String, Node],
) -> Array[ScopedCons] {
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
pub fn parse_tree(
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
  // the deepest args position any branch reached (DeepestOnly candidate set).
  let mut max_reach = -1
  for b in branches {
    match b {
      Accept(p, _) => if p > max_reach { max_reach = p }
      Held(pe, _) => if pe.args_pos > max_reach { max_reach = pe.args_pos }
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
        // `path` carries the Rooted-escape adjustment (`link`) `complete_tree`'s completer lookup
        // needs, which is the WRONG path for this conversion — a global option's value-slot
        // candidate copied into a descendant command scope reports the DECLARING scope's path via
        // `path` (by design, for completion), but `missing_operand` needs the scope it was actually
        // READ under (DR-066 §4's "発火時の動的パス"). Using `path` here produced 2-3 duplicate
        // errors for the SAME starved slot (one per re-evaluation the CPS walk performs — root-copy,
        // any mid-nesting re-entry, and the innermost read), each with a DIFFERENT (and mostly wrong)
        // path, because `link`'s escape bookkeeping diverges per candidate while `fire_path` does
        // not. `fire_path` (`Cand.fire_path` doc comment) is prepended unconditionally by every scope
        // boundary regardless of `link`, so every duplicate reading of the SAME starved slot carries
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
      e.args_pos > deepest_resid {
      deepest_resid = e.args_pos
    }
  }
  let errors2 : Array[ParseError] = []
  for e in errors {
    if e.element == "" &&
      e.reason == "unexpected_token" &&
      e.args_pos < deepest_resid {
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
