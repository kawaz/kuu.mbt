// outcome.mbt — the exit layer (MDR-002 §3): outcome types, failure-action
// selection, help / tried-triggers materials. The complete (Pending
// collection) API also lives here once the value-resolution layer lands.

///|
/// Final parse outcome — a discriminated union of 3 values (spec DR-053 §1).
pub(all) enum Outcome {
  Success(Array[Binding])
  Failure(FailureData)
  Ambiguous(AmbiguousData)
} derive(Eq, Debug)

///|
/// spec DR-053 §2/§4: a failed parse. `errors` holds ALL held Errors; primary
/// is the max-argv_pos subset (computed by the renderer). `fired_action` and
/// `errors` coexist (表示が置換されるだけ、構造は残る).
pub(all) struct FailureData {
  errors : Array[ParseError]
  fired_action : String?
  help_entry : String?
  tried_triggers : Array[String]
} derive(Eq, Debug)

///|
/// One ambiguous interpretation (DR-053 §3 + DR-073 claimants provenance). `binds` are the
/// PRE-export-key Bindings for this interpretation (raw entity-name keys — downstream applies
/// the ExportKey map to render the result-object view). `claimants` is the DR-073 §1 optional
/// provenance面: for each exposed key that this interpretation contests with another, the entity
/// name that occupies it IN THIS VIEW. Empty when the interpretation carries no export-key
/// collision (the common case — structurally-distinct full paths need no claimants to be told
/// apart). Non-empty only for export-key co-exposure collisions where degenerate views (e.g.
/// two flags both `true`) share a result key but come from different entities (DR-073 §2:
/// entity name is the only cross-view-stable identifier since value/source can coincide).
pub(all) struct AmbInterp {
  binds : Array[Binding]
  claimants : Array[(String, String)]
} derive(Eq, Debug)

///|
/// spec DR-053 §3 + DR-073: an ambiguous parse — every distinct interpretation with an optional
/// claimants面 (DR-073 §1 の「解釈に claimants を束ねた組」= 並行配列ではなく組で保持し、集合
/// 比較 (CONFORMANCE §3) が (view, claimants) の対を単位として突き合わせられる)。
pub(all) struct AmbiguousData {
  interpretations : Array[AmbInterp]
  help_entry : String?
} derive(Eq, Debug)

///|
/// The candidate-path set that counts a failure-action as "selected"
/// (spec DR-048 §5): same Branch stream, different collection policies.
pub(all) enum FailDef {
  AcceptsOnly // candidate = a path that reached the global end (dead ends ignored)
  WithHeld // + a path that reached an Error-held / value-pending point
  DeepestOnly // only the maximal-argv-consumption candidate path(s)
} derive(Eq, Debug)

///|
/// Push every failure-action marker in `bs` as (name, argv position).
fn collect_actions(bs : Array[Binding], out : Array[(String, Int)]) -> Unit {
  for b in bs {
    match action_of(b) {
      Some(name) => {
        let pos = match b.value {
          VNum(d) => d.to_int()
          _ => 0
        }
        out.push((name, pos))
      }
      None => ()
    }
  }
}

///|
/// The action with the minimal argv position (先勝ち, spec DR-048 §4). Ties
/// keep first-seen.
fn argmin_action(actions : Array[(String, Int)]) -> String {
  let mut best = actions[0]
  for a in actions {
    if a.1 < best.1 {
      best = a
    }
  }
  best.0
}

///|
/// The help entry's spelling (spec DR-053 §4 help_entry material): the exact trigger of the greedy
/// satellite that carries a help FailMark, IN THE SCOPE AT THE FAILURE POSITION — same scope-
/// resolution rule `tried_triggers_of` uses (DR-053 §4 の失敗位置基準、issue conformance-tried-
/// triggers-help-entry-fields の実機確認で発覚: 旧実装は root scope の greedy しか見ておらず、
/// サブコマンドの子スコープに宣言された help 入口を見逃していた — fixtures/failure-actions/
/// tried-triggers-scope.json の subcommand-scope-excludes-ancestor-spelling が pin する)。`errors`
/// が空 (呼び出し元が ambiguous 用に意図的に渡す — 複数完全経路が成立した状態には単一の「失敗位置」
/// が無いので、root scope 全体を見る従来どおりの posture に留める) の場合は root scope のみを見る。
fn find_help_entry(root : Node, errors : Array[ParseError]) -> String? {
  let mut deepest = -1
  for e in errors {
    if e.argv_pos > deepest {
      deepest = e.argv_pos
    }
  }
  let mut any_primary = false
  for e in errors {
    if e.argv_pos == deepest {
      any_primary = true
      match scope_at_path(root, e.path) {
        Some(sc) =>
          for g in sc.greedy {
            match find_help_entry_in_greedy(g) {
              Some(t) => return Some(t)
              None => ()
            }
          }
        None => ()
      }
    }
  }
  if !any_primary {
    match root {
      ScopeNode(sc) =>
        for g in sc.greedy {
          match find_help_entry_in_greedy(g) {
            Some(t) => return Some(t)
            None => ()
          }
        }
      _ => ()
    }
  }
  None
}

///|
/// Search a single greedy entry (possibly Or-wrapped) for the help satellite's
/// exact trigger spelling. step_greedy/eval treat Or([alt1, alt2, …]) as a
/// bundle of interjections (each alt is its own greedy entry semantically);
/// find_help_entry mirrors that so an Or-wrapped help entry is discovered.
fn find_help_entry_in_greedy(g : Node) -> String? {
  match g {
    Or(alts) => {
      for a in alts {
        match find_help_entry_in_greedy(a) {
          Some(t) => return Some(t)
          None => ()
        }
      }
      None
    }
    Seq(items) => {
      let mut trig : String? = None
      let mut has_fail = false
      for it in items {
        match it {
          Exact(s) =>
            match trig {
              None => trig = Some(s)
              _ => ()
            }
          FailMark(_) => has_fail = true
          _ => ()
        }
      }
      if has_fail {
        trig
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// The exact trigger literals available AT THE FAILURE POSITION (spec DR-053 §4 tried_triggers
/// material, issue 2026-07-08 greedy-once-and-idxrepeat-premises §3). §4's "失敗位置" ties directly
/// to §2's "primary の定義: argv 位置が最深の Error" (both live in the same DR, §4 immediately
/// follows §2's primary rule) — the failure POSITION is the primary error's position, and DR-041
/// §4's "読める最内スコープが勝つ" means the triggers tried there are the scope the primary error
/// actually failed IN, not always root's. Each primary error's `path` (DR-066 §4) already threads
/// the ancestor scope names it crossed on the way out; walking root down that path reaches the
/// scope that offered the greedy entries at the failure site. 複数 primary (同深) なら全ての scope
/// を和集合 (重複除去はしない — 呼び出し元 push_error と同じ非-dedup 方針)。素材のみ、near-match は
/// DX 層の関心。
fn tried_triggers_of(root : Node, errors : Array[ParseError]) -> Array[String] {
  let mut deepest = -1
  for e in errors {
    if e.argv_pos > deepest {
      deepest = e.argv_pos
    }
  }
  let out : Array[String] = []
  let mut any_primary = false
  for e in errors {
    if e.argv_pos == deepest {
      any_primary = true
      match scope_at_path(root, e.path) {
        Some(sc) =>
          for g in sc.greedy {
            tried_triggers_in_greedy(g, out)
          }
        None => ()
      }
    }
  }
  if !any_primary {
    // no errors at all — root scope's own triggers are the best available
    // material (matches the pre-fix behavior exactly for this edge case).
    match root {
      ScopeNode(sc) =>
        for g in sc.greedy {
          tried_triggers_in_greedy(g, out)
        }
      _ => ()
    }
  }
  out
}

///|
/// Walk `root` down `path` (root-first ancestor scope names, DR-066 §4) through CmdSat children
/// ONLY — a `Scoped` label (DR-025 result scope label) wraps an arbitrary Node, not necessarily a
/// child Scope (MDR-002 "light layer-3 hook; does not change path count"), so a path segment that
/// doesn't match any CmdSat name stops the walk short (returns `None`, tried_triggers_of falls back
/// to the root-scope material rather than guessing). `[]` resolves straight to `root`'s own scope.
fn scope_at_path(root : Node, path : Array[String]) -> Scope? {
  let mut cur = root
  for label in path {
    match cur {
      ScopeNode(sc) => {
        let mut next : Node? = None
        for g in sc.greedy {
          match g {
            CmdSat(name, child) =>
              if name == label {
                next = Some(ScopeNode(child))
              }
            _ => ()
          }
        }
        match next {
          Some(n) => cur = n
          None => return None
        }
      }
      _ => return None
    }
  }
  match cur {
    ScopeNode(sc) => Some(sc)
    _ => None
  }
}

///|
/// Collect trigger spellings from a single greedy entry (possibly Or-wrapped)
/// into `out`. Or([alt1, alt2, …]) is a bundle of interjections in
/// step_greedy/eval; this walk must mirror that so an Or-wrapped `--help`
/// spelling shows up in tried_triggers.
fn tried_triggers_in_greedy(g : Node, out : Array[String]) -> Unit {
  match g {
    Or(alts) =>
      for a in alts {
        tried_triggers_in_greedy(a, out)
      }
    Seq(items) =>
      if items.length() >= 1 {
        match items[0] {
          Exact(s) => out.push(s)
          _ => ()
        }
      }
    DdSat(s) => out.push(s)
    CmdSat(name, _) => out.push(name)
    _ => ()
  }
}

// ── complete (DR-060 / MDR-002 §2.4: the ONE Pending-collection function) ─────

///|
/// Complete = the union of everything readable at the next consumption point
/// over every surviving partial path that consumed `before` (DR-060 §1). The
/// walk itself is parse's walk in ModeComplete — boundary trigger sites and
/// starved value slots come back as `Pending` branches; a `Held`-only path is
/// a true dead end and contributes nothing (DR-060: dead-end candidates are
/// noise). Candidates are raw material + meta (DR-060 §3); prefix filtering
/// by the cursor word, alias/hidden policy and insertion are the generator's
/// (層 2) and the shell's concern — kuu fixes no policy here.
///
/// `after` (DR-060 §2 整合フィルタ): when the cursor sits mid-line, a
/// WordEnd exact candidate survives only if adopting it still lets some path
/// consume `after` to a complete parse. Value candidates and Cont-term
/// spellings (an eq-split `--key` needs `=value` typed in the same word)
/// cannot be checked without inventing the user's input, so they pass the
/// filter unexamined.
pub fn complete(
  root : Node,
  before : Array[String],
  defs? : Map[String, Node] = Map([]),
  after? : Array[String] = [],
) -> Array[Cand] {
  let ctx : Ctx = { toks: before, defs, mode: ModeComplete }
  let branches = match root {
    ScopeNode(sc) =>
      scope_step(sc, ctx, 0, 0, [], false, KTop(collect_scopes(root, defs)))
    _ => eval(root, ctx, 0)
  }
  let cands : Array[Cand] = []
  for b in branches {
    match b {
      Pending(cs, _) =>
        for c in cs {
          let mut dup = false
          for e in cands {
            // DR-060 §3's candidate structure is spelling/is_value/ty/origin/term/meta —
            // `path` (DR-066 §4) is NOT part of it, so two candidates that differ only
            // by which ancestor scope produced them are the same candidate here: the
            // same spelling is readable either way, and DR-060 §1's "union of what's
            // readable" is a union over SPELLINGS, not over the scopes that offer them.
            if e.spelling == c.spelling &&
              e.is_value == c.is_value &&
              e.ty == c.ty &&
              e.origin == c.origin &&
              e.term == c.term &&
              e.meta == c.meta {
              dup = true
              break
            }
          }
          if !dup {
            cands.push(c)
          }
        }
      _ => () // Accept: already complete, nothing to read; Held: dead end
    }
  }
  if after.length() == 0 {
    return cands
  }
  let out : Array[Cand] = []
  for c in cands {
    if c.is_value || c.term == Cont {
      out.push(c)
    } else {
      let toks2 : Array[String] = []
      for t in before {
        toks2.push(t)
      }
      toks2.push(c.spelling)
      for t in after {
        toks2.push(t)
      }
      match parse(root, toks2, defs~) {
        Success(_) | Ambiguous(_) => out.push(c)
        Failure(_) => ()
      }
    }
  }
  out
}
