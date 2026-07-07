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
