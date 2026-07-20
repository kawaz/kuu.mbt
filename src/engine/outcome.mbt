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
/// is the max-args_pos subset (computed by the renderer). `fired_action` and
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
  DeepestOnly // only the maximal-args-consumption candidate path(s)
} derive(Eq, Debug)

///|
/// The fired failure-action for a Failure built from these candidate binding sets (spec DR-048
/// §4/§5): every failure-action marker across `binds_groups` is collected as (name, args
/// position) and the minimal-position action wins (先勝ち; ties keep first-seen). None when no
/// action fired. This is the SAME material `parse_tree` uses for its own Failure, exposed so a
/// post-parse Success→Failure conversion (constraint violations found at resolve time) derives
/// `fired_action` under the identical rule.
pub fn fired_action_of(binds_groups : Array[Array[Binding]]) -> String? {
  let actions : Array[(String, Int)] = []
  for bs in binds_groups {
    collect_actions(bs, actions)
  }
  if actions.length() > 0 {
    Some(argmin_action(actions))
  } else {
    None
  }
}

///|
/// Push every failure-action marker in `bs` as (name, args position).
fn collect_actions(bs : Array[Binding], out : Array[(String, Int)]) -> Unit {
  for b in bs {
    match action_of(b) {
      Some(name) => {
        let pos = match b.value {
          Number(d) => d.to_int()
          _ => 0
        }
        out.push((name, pos))
      }
      None => ()
    }
  }
}

///|
/// The action with the minimal args position (先勝ち, spec DR-048 §4). Ties
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
/// satellite that carries a help failure resident, IN THE SCOPE AT THE FAILURE POSITION — same scope-
/// resolution rule `tried_triggers_of` uses (DR-053 §4 の失敗位置基準、issue conformance-tried-
/// triggers-help-entry-fields の実機確認で発覚: 旧実装は root scope の greedy しか見ておらず、
/// サブコマンドの子スコープに宣言された help 入口を見逃していた — fixtures/failure-actions/
/// tried-triggers-scope.json の subcommand-scope-excludes-ancestor-spelling が pin する)。`errors`
/// が空 (呼び出し元が ambiguous 用に意図的に渡す — 複数完全経路が成立した状態には単一の「失敗位置」
/// が無いので、root scope 全体を見る従来どおりの posture に留める) の場合は root scope のみを見る。
pub fn find_help_entry(root : Node, errors : Array[ParseError]) -> String? {
  let mut deepest = -1
  for e in errors {
    if e.args_pos > deepest {
      deepest = e.args_pos
    }
  }
  let mut any_primary = false
  for e in errors {
    if e.args_pos == deepest {
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
          Ext(_) => if node_is_failure_mark(it) { has_fail = true }
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
/// to §2's "primary の定義: args 位置が最深の Error" (both live in the same DR, §4 immediately
/// follows §2's primary rule) — the failure POSITION is the primary error's position, and DR-041
/// §4's "読める最内スコープが勝つ" means the triggers tried there are the scope the primary error
/// actually failed IN, not always root's. Each primary error's `path` (DR-066 §4) already threads
/// the ancestor scope names it crossed on the way out; walking root down that path reaches the
/// scope that offered the greedy entries at the failure site. 複数 primary (同深) なら全ての scope
/// を和集合 (重複除去はしない — 呼び出し元 push_error と同じ非-dedup 方針)。素材のみ、near-match は
/// DX 層の関心。
pub fn tried_triggers_of(
  root : Node,
  errors : Array[ParseError],
) -> Array[String] {
  let mut deepest = -1
  for e in errors {
    if e.args_pos > deepest {
      deepest = e.args_pos
    }
  }
  let out : Array[String] = []
  let mut any_primary = false
  for e in errors {
    if e.args_pos == deepest {
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
/// Walk `root` down `path` (root-first ancestor scope names, DR-066 §4) through CmdSatisfied children
/// ONLY — a `Scoped` label (DR-025 result scope label) wraps an arbitrary Node, not necessarily a
/// child Scope (MDR-002 "light layer-3 hook; does not change path count"), so a path segment that
/// doesn't match any CmdSatisfied name stops the walk short (returns `None`, tried_triggers_of falls back
/// to the root-scope material rather than guessing). `[]` resolves straight to `root`'s own scope.
fn scope_at_path(root : Node, path : Array[String]) -> Scope? {
  let mut cur = root
  for label in path {
    match cur {
      ScopeNode(sc) => {
        let mut next : Node? = None
        for g in sc.greedy {
          match g {
            CmdSatisfied(name, child) =>
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
    DdSatisfied(s) => out.push(s)
    // DR-090: only an EXACT dd trigger is a "tried spelling" a user could type (same rationale
    // as the eval.mbt Pending arms — a regex pattern has no single literal candidate to surface).
    DdMatchSatisfied(spelling, is_pattern, _, _) =>
      if !is_pattern {
        out.push(spelling)
      }
    CmdSatisfied(name, _) => out.push(name)
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
/// consume `after` to a complete parse. Value candidates and Continue-term
/// spellings (an eq-split `--key` needs `=value` typed in the same word)
/// cannot be checked without inventing the user's input, so they pass the
/// filter unexamined.
pub fn complete_tree(
  root : Node,
  before : Array[String],
  defs? : Map[String, Node] = Map([]),
  after? : Array[String] = [],
  extensions? : Registry = Registry::new(),
) -> Array[Candidate] {
  let ctx : Ctx = {
    toks: before,
    defs,
    extensions_: extensions,
    mode: ModeComplete,
  }
  let branches = match root {
    ScopeNode(sc) =>
      scope_step(sc, ctx, 0, 0, [], false, KTop(collect_scopes(root, defs)))
    _ => eval(root, ctx, 0)
  }
  // DR-060 §4 / DR-104 §2(d): value-position candidates' `completer` is resolved via a
  // (path, origin)-keyed Entity lookup — NOT a bare name-keyed one. `pending_value_candidate` (eval.mbt) has
  // no Entity table in scope at any of its 30+ call sites, so the completer cannot be threaded
  // through at construction time; it must be looked up here instead. Looking it up by `origin`
  // ALONE would be wrong: two structurally independent scopes (e.g. two separate `command`
  // definitions sharing the same child element name, DR-067 §1's "same-scope trigger duplication
  // is legal" extended across sibling command definitions) can each declare their OWN Entity
  // named `origin` with a DIFFERENT completer — a bare name lookup would silently pick
  // whichever one the tree walk happened to visit first. Keying by `(c.path, c.origin)` finds
  // the Entity belonging to the SAME scope that produced this specific candidate, exactly
  // mirroring how `nest_cands`/`nest_branches` built that candidate's `path` in the first place.
  let entities = collect_all_entities(root, defs)
  let cands : Array[Candidate] = []
  for b in branches {
    match b {
      Pending(cs, _) =>
        for c0 in cs {
          let decorated : Array[Candidate] = []
          if c0.is_value {
            match entities.get(entity_key(c0.path, c0.origin)) {
              Some(extensions) =>
                for extension in extensions {
                  decorated.push(extension.complete_candidate(c0))
                }
              // No Entity under this key should not occur for a well-formed tree, but
              // stays defensive rather than dropping the candidate.
              None => decorated.push(c0)
            }
          } else {
            decorated.push(c0)
          }
          for c in decorated {
            let mut dup_idx = -1
            for j = 0; j < cands.length(); j = j + 1 {
              let e = cands[j]
              // DR-060 §3's candidate structure is spelling/is_value/ty/origin/term/meta (wire
              // shape; `meta` bundles is_alias/hidden/deprecated, carried flat on the in-memory
              // Candidate) — `path` (DR-066 §4) is NOT part of it, so two candidates that differ
              // only by which ancestor scope produced them are the same candidate here: the
              // same spelling is readable either way, and DR-060 §1's "union of what's
              // readable" is a union over SPELLINGS, not over the scopes that offer them.
              // `completer` (DR-104 §3) is likewise NOT part of this identity.
              if e.spelling == c.spelling &&
                e.is_value == c.is_value &&
                e.ty == c.ty &&
                e.origin == c.origin &&
                e.term == c.term &&
                e.is_alias == c.is_alias &&
                e.hidden == c.hidden &&
                e.deprecated == c.deprecated {
                dup_idx = j
                break
              }
            }
            if dup_idx < 0 {
              cands.push(c)
            } else if cands[dup_idx].completer != c.completer {
              // DR-104 §3 明確化 note: two candidates that dedup-match on the 6-field identity
              // but resolve to DIFFERENT completers (via their distinct `path`s, per the doc
              // comment above) merge to "no completer" — neither producer's guess is privileged
              // over the other's, so the honest wire projection is `completer` absent (COMP-Q3's
              // opt-in convention already treats absence as "unknown/untested", which fits this
              // case exactly: which app-specific dynamic completer applies is genuinely
              // ambiguous when the 6 identity-bearing fields cannot tell the two scopes apart).
              cands[dup_idx] = { ..cands[dup_idx], completer: None }
            }
          }
        }
      _ => () // Accept: already complete, nothing to read; Held: dead end
    }
  }
  if after.length() == 0 {
    return cands
  }
  let out : Array[Candidate] = []
  for c in cands {
    if c.is_value || c.term == Continue {
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
      match parse_tree(root, toks2, defs~) {
        Success(_) | Ambiguous(_) => out.push(c)
        Failure(_) => ()
      }
    }
  }
  out
}

// ── Entity table for complete()'s completer lookup (DR-060 §4) ────────────────────────────

///|
/// Render a `(path, name)` pair into a single lookup key — root-first path segments joined
/// by a separator that cannot appear in an element name (`>`, same separator convention as
/// this file's other `render_path`-style joins), then `#name`. Two entities with the same
/// `name` but a DIFFERENT `path` (distinct scopes — e.g. two independent `command` definitions
/// that both happen to declare a child element called `target`) get DISTINCT keys here; a bare
/// name-only key would conflate them (see `complete_tree`'s doc comment on why that would be
/// wrong for the completer lookup specifically).
fn entity_key(path : Array[String], name : String) -> String {
  let buf = StringBuilder::new()
  for p in path {
    buf.write_string(p)
    buf.write_string(">")
  }
  buf.write_string("#")
  buf.write_string(name)
  buf.to_string()
}

///|
/// Collect every statically reachable Entity, keyed by `entity_key(path, name)`, over the WHOLE
/// tree — root scope plus every nested CmdSatisfied / inline positional ScopeNode / scope-shaped
/// repeat head. Unlike `collect_scopes` (eval.mbt), which serves ONLY the KTop constraint table
/// and therefore skips any scope with no constraints, this visits every scope unconditionally: a
/// `Candidate.origin` can name an Entity in a scope that has no constraints at all, and
/// `complete_tree`'s completer lookup needs to find it regardless. Mirrors
/// `collect_scopes`/`collect_scope_into`/`collect_greedy_scopes`/`collect_pos_scopes`'s traversal
/// shape (same Ref/CmdSatisfied/Or/Rooted/BoundedTail/Many cases and the SAME root-first path-building
/// convention — `path + [name]` on CmdSatisfied entry — so a `Candidate.path` built by `nest_cands`/
/// `nest_branches` lines up exactly with the path this collector attaches to that Entity).
///
/// A key maps to every distinct opaque EntityExt resident found there. DR-067 §1 allows
/// structurally independent command definitions to share the same path/name key; preserving
/// the resident list lets `complete_tree` project each candidate first, then apply the stable
/// Candidate identity and completer merge rules without inspecting or discarding opaque metadata.
fn collect_all_entities(
  root : Node,
  defs : Map[String, Node],
) -> Map[String, Array[&EntityExt]] {
  let out : Map[String, Array[&EntityExt]] = Map([])
  match root {
    ScopeNode(sc) => collect_entities_into(sc, [], defs, out, [])
    _ => ()
  }
  out
}

///|
fn collect_entities_into(
  sc : Scope,
  path : Array[String],
  defs : Map[String, Node],
  out : Map[String, Array[&EntityExt]],
  seen_refs : Array[String],
) -> Unit {
  for e in sc.entities {
    let k = entity_key(path, e.name)
    match out.get(k) {
      None => out.set(k, [e.extension])
      Some(extensions) => {
        let mut found = false
        for extension in extensions {
          if extension == e.extension {
            found = true
          }
        }
        if !found {
          extensions.push(e.extension)
        }
      }
    }
  }
  for g in sc.greedy {
    collect_entities_greedy(g, path, defs, out, seen_refs)
  }
  for p in sc.positional {
    collect_entities_pos(p, path, defs, out, seen_refs)
  }
}

///|
fn collect_entities_greedy(
  g : Node,
  path : Array[String],
  defs : Map[String, Node],
  out : Map[String, Array[&EntityExt]],
  seen_refs : Array[String],
) -> Unit {
  match g {
    CmdSatisfied(name, child) => {
      let p2 : Array[String] = []
      for s in path {
        p2.push(s)
      }
      p2.push(name)
      collect_entities_into(child, p2, defs, out, seen_refs)
    }
    Or(alts) =>
      for a in alts {
        collect_entities_greedy(a, path, defs, out, seen_refs)
      }
    Rooted(inner, _) =>
      collect_entities_greedy(inner, path, defs, out, seen_refs)
    _ => ()
  }
}

///|
fn collect_entities_pos(
  n : Node,
  path : Array[String],
  defs : Map[String, Node],
  out : Map[String, Array[&EntityExt]],
  seen_refs : Array[String],
) -> Unit {
  match n {
    ScopeNode(child) => collect_entities_into(child, path, defs, out, seen_refs)
    Ref(name) =>
      if !str_mem(seen_refs, name) {
        let seen2 : Array[String] = []
        for s in seen_refs {
          seen2.push(s)
        }
        seen2.push(name)
        match ref_head(defs, name) {
          ScopeNode(child) =>
            collect_entities_into(child, path, defs, out, seen2)
          _ => ()
        }
      }
    BoundedTail(head, _, _) =>
      match head {
        ScopeNode(child) =>
          collect_entities_into(child, path, defs, out, seen_refs)
        _ => ()
      }
    Many(inner, _) => collect_entities_pos(inner, path, defs, out, seen_refs)
    _ => ()
  }
}
