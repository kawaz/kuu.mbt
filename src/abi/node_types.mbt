// Public parser ABI data.

///|
/// A definition-time (parse_definition) Error category (DR-054 §1). All are "lowering が構成できない
/// / 全入力で壊れる" — Error, not warn. (warn 層 = 一部入力で驚きうるだけ, は lint の関心で PoC 射程外.)
pub(all) enum DefErrorKind {
  VocabIntersection // two installers own the same vocab (DR-042③)
  UnknownVocab // a special vocab owned by no installer in the chain (DR-042①)
  InvalidRange // an invalid value range (repeat min > max, etc., DR-052 ほか)
  AbsentRef // a ref target resolvable nowhere (scope + definitions, DR-032)
  CircularRef // a ref cycle with infinite structural expansion (DR-007/032)
  ZeroProgress // a repeat unfold whose 1 iteration consumes no token (DR-043)
  ConfigCycle // a config_file element taking its own path from config (DR-050 §5)
  // a single argument value itself is outside a registry device's acceptance range (DR-054 §4
  // 更新2 / DR-082 §3, DR-085 §1 訂正) — e.g. regex_match's pattern failing to compile. Distinct
  // from InvalidRange (a COMBINATION of attributes is out of range, e.g. repeat min > max):
  // InvalidArgument is about a single value's own internal validity.
  InvalidArgument
} derive(Eq, Debug)

///|
/// One definition-time Error (DR-054 §4): {element, kind, message, hint}. `hint` is the「次の手」
/// (DR-042 完全性検査の様式). parse_definition enumerates ALL of these (no first-error 打ち切り).
pub(all) struct DefError {
  element : String
  kind : DefErrorKind
  message : String
  hint : String
} derive(Eq, Debug)

// ── completion candidate 型 (DR-060 §3) — 型のみ移植 (slice complete.mbt 1-57) ─
// The completion走査 (comp_scope 等) is outcome.mbt's job (MDR-002 §3); only the DATA the
// evaluator's `Pending` branch carries lives here. `Candidate.ty` carries the DR-104 base spelling.

///|
/// A terminal hint on an exact candidate (DR-060 §3): `WordEnd` = 確定, a space may follow; `Continue` =
/// 継続, no space (a value must follow — e.g. a value-taking --port, or a `--key=` / dir `/` in prod).
pub(all) enum TermHint {
  WordEnd
  Continue
} derive(Eq, Debug)

///|
/// A completion candidate (DR-060 §3): either an exact trigger spelling, or a value position (type +
/// completer名, PoC shows the type). Meta rides alongside; policy / replacement / landing is the
/// generator's & shell's (kuu returns素材 only).
///
/// `path` (DR-066 §4, issue 2026-07-08 pending-starvation-missing-operand-path): root-first ancestor
/// scope names, mirroring `ParseError.path`'s snoc form ([] = root 直下). `origin` already answers
/// "which element" a candidate came from; `path` answers "under which ancestor scopes" — the same
/// pairing `ParseError` uses (`element` + `path`). Threaded the SAME way Held's path is (starts `[]`
/// at construction, `nest_branches`/CommandSatisfied prepend the traversed scope labels on the way out) so a
/// `Pending`'s value-slot candidate can be converted to a `missing_operand` `ParseError` (parse()
/// top-level, DR-053 §2.3) WITHOUT losing the ancestor path the way it used to (Held already worked;
/// Pending — parse mode's other failure carrier — did not, because prepend only touched Held). Also
/// carried by the exact-trigger (`is_value:false`) candidates for consistency, even though those
/// never feed `missing_operand` today — DR-060's completion consumers are free to ignore the field
/// (additive, not a breaking change to the §3 candidate structure).
pub(all) struct Candidate {
  spelling : String // the exact spelling; "" for a value position
  is_value : Bool
  ty : String // DR-104 §2 base spelling for a value position
  origin : String // the element name it came from
  term : TermHint
  // Declaration-layer meta a completion reads by reference (DR-056 / DR-057 / DR-058): whether a
  // spelling is an alias entry, hidden (excluded from candidates by default, kept here), deprecated.
  // The wire projection nests these three fields under `meta: {...}` (DR-104's wire contract); the
  // in-memory Candidate carries them flat.
  is_alias : Bool
  hidden : Bool
  deprecated : Bool
  path : Array[String] // DR-066 §4: root-first ancestor scope names (snoc form, [] = root 直下)
  // Rooted-escape counter for `path`, mirroring `Binding.link` (DR-042 global link-sync): a
  // global option's satellite is copied into a descendant command scope wrapped in
  // `Rooted(node, depth)`, and its Entity lives ONLY at the declaring (shallower) scope — a
  // value-slot Pending produced from inside that copy must therefore have `depth` levels of
  // CommandSatisfied-boundary prepend SKIPPED, or its `path` ends up pointing at the wrong (copy-side)
  // scope while the Entity it names sits at the declaring scope. Bare `Array[String]` path alone
  // cannot express "skip N prepends" — `nest_cands` (eval.mbt) consumes this exactly like
  // `nest`'s own `Binding.link` decrement, so the two stay in lockstep. `0` (the common case) =
  // no pending escape, prepend normally. NOT part of the 6-field dedup identity or the wire
  // projection (same posture as `path` itself, DR-104 §2/§3) — purely an implementation detail of
  // `complete_tree`'s completer lookup (outcome.mbt).
  link : Int
  // issue 2026-07-15-pending-parseerror-path-asymmetry (DR-066 §4): the FIRE-TIME walk-position
  // path — root-first ancestor scope names, prepended UNCONDITIONALLY as the branch rides out
  // through each CommandSatisfied boundary (`nest_path`, the SAME no-exception rule a Held's `ParseError.path`
  // already follows). Deliberately a SEPARATE field from `path` above: `path`'s Rooted-escape skip
  // (`link`) answers "where does complete_tree's completer lookup find this candidate's declaring
  // Entity" (a completion-only question), while `fire_path` answers "which scope was this candidate
  // actually read under" (the question `missing_operand`'s `ParseError.path` needs, DR-066 §4's own
  // "発火時の動的パス" wording). Adversarial verification (installer_wbtest.mbt debug probes, this
  // issue) found `link` is ALWAYS 0 by the time a Pending reaches KTop — a Rooted candidate's escape
  // counter is fully consumed by the SAME CommandSatisfied boundaries `path` needs prepended, so gating KTop's
  // conversion on `c.link > 0` (the originally proposed fix) is a no-op: nothing is ever excluded,
  // and the wrong-path duplicate survives with `link` already 0. `fire_path` sidesteps the escape
  // bookkeeping entirely by tracking the walk position directly, so KTop's missing_operand conversion
  // reads THIS field instead of `path` — every duplicate reading of the same starved slot (root-copy,
  // mid-scope re-evaluation, or the correct innermost one) ends up with the SAME `fire_path` (they
  // all fired at the same token position under the same walk), so `push_error`'s 5-field dedup
  // collapses them to one instead of leaving path-mismatched duplicates. NOT part of the 6-field dedup
  // identity or the wire projection (same posture as `path`/`link` — purely an internal routing aid).
  fire_path : Array[String]
  // DR-060 §3 "値位置: 型情報 + completer 名" / DR-104 §2/§3: the dynamic completer name for a
  // VALUE-position candidate (`is_value:true`); always `None` on an exact-trigger candidate (DR-060
  // §3 does not attach a completer to a spelling). Deliberately NOT part of the 6-field dedup
  // identity (DR-104 §3 "`completer` は同一性の成分ではない") — every `pending_value_candidate` call site keeps
  // constructing `None` here (no Entity table is in scope at any of those 30+ sites); `complete_tree`
  // (outcome.mbt) fills it in via a `(path, origin)`-keyed lookup into the tree's Entity table
  // (`collect_all_entities`) as each candidate is folded into the dedup loop — keyed by `path` (not
  // bare `origin`) because two structurally independent scopes can each declare their own Entity
  // under the SAME name with a DIFFERENT completer, and a bare-name lookup could not tell them
  // apart. When two candidates dedup-match on the 6-field identity but resolve to different
  // completers via their distinct paths, the merge rule (DR-104 §3 明確化 note) folds them to
  // `None` — see `complete_tree`'s dedup loop.
  completer : String?
} derive(Eq, Debug)

///|
/// The outcome of trying a node against a token prefix (MDR-002 §2.1). A missing branch == Reject
/// (silently dropped, DR-037); `Held` == Error (retained for failure display); `Accept(pos, binds)`
/// == a reading; `Pending(cands, binds)` == トリガ消費・値 pending (parse では Held 相当、complete では
/// 補完候補の源, MDR-002 §2 案B). The matcher only CONSTRUCTS Accept/Held; the evaluator produces and
/// consumes Pending. (Kept in node.mbt so both matcher and eval can return it; single package.)
pub(all) enum Branch {
  Accept(Int, Array[Binding]) // (new position, accumulated bindings)
  Held(ParseError, Array[Binding]) // a DR-037 Error + the partial state (acc) at the error point
  Pending(Array[Candidate], Array[Binding]) // trigger consumed, value slot's input absent
} derive(Debug)
