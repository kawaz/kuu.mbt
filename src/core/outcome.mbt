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
/// spec DR-053 §3: an ambiguous parse — every distinct interpretation as a
/// result-object view.
pub(all) struct AmbiguousData {
  interpretations : Array[Array[Binding]]
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
/// The help entry's spelling (spec DR-053 §4 help_entry material): the exact
/// trigger of the greedy satellite that carries a help FailMark.
fn find_help_entry(root : Node) -> String? {
  match root {
    ScopeNode(sc) => {
      for g in sc.greedy {
        match find_help_entry_in_greedy(g) {
          Some(t) => return Some(t)
          None => ()
        }
      }
      None
    }
    _ => None
  }
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
/// The exact trigger literals available in the scope (spec DR-053 §4
/// tried_triggers material). 近接マッチ計算は DX 層の関心 — 素材のみ。
fn tried_triggers_of(root : Node) -> Array[String] {
  let out : Array[String] = []
  match root {
    ScopeNode(sc) =>
      for g in sc.greedy {
        tried_triggers_in_greedy(g, out)
      }
    _ => ()
  }
  out
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
            if e == c {
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
