// cont.mbt — the defunctionalized continuation (MDR-002 §1).
//
// The 取り分選好 completion oracle (has_full) cannot be a scope-local number:
// a repeat's correct share depends on what the PARENT consumes after this
// scope, recursively (MDR-002 §1.1). So the oracle is the continuation
// itself: "run everything that follows this choice — the rest of this scope,
// the parent's rest, …, the final pos == toks.length() check — and see
// whether an Accept comes out."
//
// `Cont` is a defunctionalized ADT (not a raw closure) so a completes-cache
// keyed by (continuation shape, args position) stays possible (MDR-002 §1.3).
// Every payload derives Eq, keeping the whole Cont structurally comparable.

///|
/// One scope's delayed predicates + their scope: the constraint table entry
/// KTop evaluates at the global completion point. `path` is the result
/// nesting path of the declaring scope (root = []); bindings are matched
/// scope-exactly against it.
pub struct ScopedCons {
  path : Array[String]
  constraints : Array[Constraint]
  entities : Array[Entity]
} derive(Debug)

///|
impl Eq for ScopedCons with fn equal(self, other) {
  self.path == other.path &&
  self.constraints == other.constraints &&
  self.entities == other.entities
}

///|
/// The continuation of a scope walk: what happens after the current scope
/// finishes at some position.
priv enum Cont {
  /// the top of the whole parse, carrying the static constraint table
  /// (collect_scopes). "complete解決経路" is decided HERE and only here:
  /// pos == toks.length() (MDR-002 §1.2) AND every scope's delayed
  /// predicates satisfied (DR-047 §2). A constraint-violating full
  /// consumption returns Helds (one per violation) instead of an Accept, so
  /// the 取り分選好 oracle (has_full_k) shares the same completeness
  /// definition as parse() — a violating share can no longer prune the
  /// satisfying one (deep review EXP-A). A position short of the end is a
  /// residual-token failure (DR-065 §3), also a Held.
  KTop(Array[ScopedCons])
  /// accept wherever the scope ends (no global check). Used for OFF-SPINE
  /// scope evaluation (a probe, or a ScopeNode reached through plain `eval`),
  /// which mirrors the slice's eval_scope returning scope-end Accepts as-is.
  KDone
  /// resume the parent scope walk: (scope, pidx, severed, outer). The child
  /// scope finished; continue the parent's scope_step from this state.
  KResumeScope(Scope, Int, Bool, Cont)
  /// nest the bindings accumulated SINCE `start` (an index into acc) under
  /// `label`, then continue. The Bool adds the `{}` presence marker (a
  /// command scope appears as at least {} even when empty, DR-025). This
  /// frame is what lets a child scope's repeats consult the parent's
  /// continuation (phase16) while the child's bindings still nest under the
  /// command name — nesting happens when the frame RUNS, on the acc slice.
  KNest(String, Bool, Int, Cont)
  /// a Ref-repeat head that is itself a ScopeNode just finished consuming:
  /// (sc, ref name, pidx, severed, entry_pos, outer). Runs the stop/more
  /// 取り分選好 (ref_choice) from the head's end position. Without this
  /// frame a scope-shaped head would be evaluated off-spine under KDone and
  /// its INTERNAL repeats would lose sight of the outer scope's remaining
  /// consumption — reintroducing breakage-1 one nesting level in (found by
  /// design review, pinned by the REVIEW-H1 wbtest). entry_pos guards
  /// zero-progress heads (a scope accepting 0 tokens cannot be a rep).
  KRefChoice(Scope, String, Int, Bool, Int, Cont)
  /// same for a BoundedTail whose head is a ScopeNode: (sc, head, remaining
  /// budget, lazy_, pidx, severed, entry_pos, outer). Runs bounded_tail_step
  /// from the head's end position with the decremented budget.
  KTailChoice(Scope, Node, Int, Bool, Int, Bool, Int, Cont)
} derive(Debug)

///|
impl Eq for Cont with fn equal(self, other) {
  match (self, other) {
    (KTop(a), KTop(b)) => a == b
    (KDone, KDone) => true
    (KResumeScope(as_, ap, av, ao), KResumeScope(bs, bp, bv, bo)) =>
      as_ == bs && ap == bp && av == bv && ao == bo
    (KNest(al, ac, ai, ao), KNest(bl, bc, bi, bo)) =>
      al == bl && ac == bc && ai == bi && ao == bo
    (KRefChoice(as_, an, ap, av, ae, ao), KRefChoice(bs, bn, bp, bv, be, bo)) =>
      as_ == bs && an == bn && ap == bp && av == bv && ae == be && ao == bo
    (
      KTailChoice(as_, ah, ab, al, ap, av, ae, ao),
      KTailChoice(bs, bh, bb, bl, bp, bv, be, bo),
    ) =>
      as_ == bs &&
      ah == bh &&
      ab == bb &&
      al == bl &&
      ap == bp &&
      av == bv &&
      ae == be &&
      ao == bo
    _ => false
  }
}

///|
/// Run a continuation from (pos, acc). This is the oracle's engine: the
/// caller inspects the resulting branches (has_full_k) to decide a repeat
/// split, and the SAME call produces the real branches when chosen.
fn run_cont(
  k : Cont,
  ctx : Ctx,
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  match k {
    KTop(table) =>
      if pos == ctx.toks.length() {
        let viol = eval_all_constraints(table, acc, pos)
        if viol.length() == 0 {
          [Accept(pos, acc)]
        } else {
          // DR-047: not a complete解決経路 — each violation is a held Error
          // (DR-053 全保持), the partial state rides for fired_action.
          let out : Array[Branch] = []
          for v in viol {
            out.push(Held(v, acc))
          }
          out
        }
      } else {
        // residual tokens (DR-065 §3): every consumer passed but toks[pos..]
        // remain. element "" = a scope-level stumble, kind:parse.
        [
          Held(
            {
              element: "",
              args_pos: pos,
              kind: KParse,
              reason: "unexpected_token",
              message: "unexpected token",
              // DR-066 §4: starts empty, prepended by scope boundaries
              // (nest_branches / CmdSat) as this Held rides back out.
              path: [],
            },
            acc,
          ),
        ]
      }
    KDone => [Accept(pos, acc)]
    KResumeScope(sc, pidx, severed, outer) =>
      scope_step(sc, ctx, pos, pidx, acc, severed, outer)
    KNest(label, is_cmd, start, outer) => {
      // nest acc[start..] one level under `label` (link bindings escape,
      // DR-042); acc[..start] predates the scope and passes through.
      let before : Array[Binding] = []
      let inside : Array[Binding] = []
      let mut i = 0
      for b in acc {
        if i < start {
          before.push(b)
        } else {
          inside.push(b)
        }
        i = i + 1
      }
      let out : Array[Binding] = []
      for b in before {
        out.push(b)
      }
      if is_cmd {
        out.push(scope_marker(label))
      }
      for b in nest(label, inside) {
        out.push(b)
      }
      run_cont(outer, ctx, pos, out)
    }
    KRefChoice(sc, name, pidx, severed, entry_pos, outer) =>
      if pos <= entry_pos {
        [] // zero-progress head: not a rep (same guard as the inline path)
      } else {
        ref_choice(sc, name, ctx, pos, pidx, acc, severed, outer)
      }
    KTailChoice(sc, head, budget, lazy_, pidx, severed, entry_pos, outer) =>
      if pos <= entry_pos {
        []
      } else {
        bounded_tail_step(
          sc, head, budget, lazy_, ctx, pos, pidx, acc, severed, outer,
        )
      }
  }
}

///|
/// Whether any branch is a FULL parse. Under CPS an `Accept` only exists if
/// the continuation chain reached KTop at toks.length() (or KDone for an
/// off-spine probe), so no target comparison is needed here (MDR-002 §1.2).
fn has_full_k(brs : Array[Branch]) -> Bool {
  for b in brs {
    match b {
      Accept(_, _) => return true
      Held(_, _) => ()
      Pending(_, _) => ()
    }
  }
  false
}
