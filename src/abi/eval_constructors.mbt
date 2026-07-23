// Evaluation protocol constructors.

///|
/// An exact-spelling candidate (the Pending payload at a trigger boundary,
/// DR-060 §3). `ty` is only meaningful when a value must follow the spelling
/// (term = Continue, e.g. an eq-split `--key`); a plain trigger carries "flag".
pub fn Candidate::trigger(
  spelling : String,
  origin : String,
  ty : String,
  term : TermHint,
  is_alias? : Bool = false,
  hidden? : Bool = false,
  deprecated? : Bool = false,
) -> Candidate {
  {
    spelling,
    is_value: false,
    ty,
    origin,
    term,
    is_alias,
    hidden,
    deprecated,
    path: [], // DR-066 §4: prepended by scope boundaries on the way out (nest_branches / CommandSatisfied)
    link: 0, // no pending Rooted-escape at construction (Rooted's own eval arm sets this)
    fire_path: [], // issue 2026-07-15-pending-parseerror-path-asymmetry: same "starts empty, scope
    // boundaries prepend unconditionally" posture as `path`/Held's own `ParseError.path` (`nest_path`
    // in `nest_cands`) — this is the exact-trigger sibling of `pending_value_candidate`'s same field, kept in sync.
    completer: None, // DR-060 §3: an exact-trigger candidate never carries a completer
  }
}

///|
/// A non-set effect binding (default / unset / empty). The operand is a
/// placeholder — these ops carry no operand (spec DR-045 table).
pub fn Binding::effect(key : String, op : EffectOp, source : Source) -> Binding {
  { key, op, value: Bool(false), source, scope: [], link: 0, at_pos: None }
}

///|
/// A failure-action marker binding (spec DR-048): key `@act:<name>`, value =
/// the args position where the action was selected (args-min tie-break).
pub fn Binding::action_marker(name : String, pos : Int) -> Binding {
  {
    key: "@act:" + name,
    op: Set,
    value: Number(pos.to_double()),
    source: Cli,
    scope: [],
    link: 0,
    at_pos: None,
  }
}

///|
/// A pending-value candidate (the Pending payload): the value slot of
/// `origin`, of type `ty`, had no token left to consume.
pub fn Candidate::pending_value(ty : String, origin : String) -> Candidate {
  {
    spelling: "",
    is_value: true,
    ty,
    origin,
    term: WordEnd,
    is_alias: false,
    hidden: false,
    deprecated: false,
    path: [], // DR-066 §4: prepended by scope boundaries on the way out (nest_branches / CommandSatisfied)
    link: 0, // no pending Rooted-escape at construction (Rooted's own eval arm sets this)
    fire_path: [], // issue 2026-07-15-pending-parseerror-path-asymmetry: `Candidate.fire_path`'s doc
    // comment — the fire-time walk-position path a `missing_operand` ParseError conversion needs,
    // tracked independently of `path`'s Rooted-escape (`link`) bookkeeping.
    // DR-060 §4 / DR-104 §2(d): filled in by `complete_tree`'s (path, origin)-keyed Entity-table
    // lookup (outcome.mbt) as candidates fold into the dedup loop, NOT here — `pending_value_candidate` has no
    // Entity table in scope at any of its 30+ call sites (see Candidate.completer's doc comment).
    completer: None,
  }
}

///|
pub fn ParseError::constraint(
  element : String,
  reason : String,
  message : String,
  pos : Int,
) -> ParseError {
  // DR-066 §4: path starts empty here and is prepended by scope boundaries
  // (nest_branches / CommandSatisfied) as the Held rides KTop's result back out through
  // the continuation chain — NOT `sc.path` (ScopedCons's path is the
  // scope_path_eq lookup key, reusing it here would double the prefix once
  // the same Held crosses those same boundaries on its way out).
  { element, args_pos: pos, kind: Constraint, reason, message, path: [] }
}
