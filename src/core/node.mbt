// node.mbt — the AtomicAST node ADT and its two-face scope.
//
// DR-039: AtomicAST = a declarative serialization of the bottom-up engine's node
// graph. The core grammar is atomic (exact / or / seq / primitive + multiple)
// plus name (result scope). DR-041 §1: matchers add runtime reading capability
// WITHOUT adding schema — so `NativeMatch` carries matcher DATA (not an opaque
// closure), keeping the whole AST comparable (`derive(Eq, Debug)`) for the
// order-independence permutation test (DR-042).
//
// MDR-002 §3: this file is the dependency-free leaf (behaviour-free ADTs only).
// MDR-003: reserved-word collisions (`alias` / `export` / `inherit` 単独) take a
// trailing underscore. Here only `Entity.inherit` collides → `inherit_`; compound
// spellings (`export_key`, `ExportKey`, `is_config_file`) are already safe.

///|
/// A definition-time (parse_definition) Error category (DR-054 §1). All are "lowering が構成できない
/// / 全入力で壊れる" — Error, not warn. (warn 層 = 一部入力で驚きうるだけ, は lint の関心で PoC 射程外.)
pub(all) enum DefErrKind {
  DVocabIntersection // two installers own the same vocab (DR-042③)
  DUnknownVocab // a special vocab owned by no installer in the chain (DR-042①)
  DInvalidRange // an invalid value range (repeat min > max, etc., DR-052 ほか)
  DAbsentRef // a ref target resolvable nowhere (scope + definitions, DR-032)
  DCircularRef // a ref cycle with infinite structural expansion (DR-007/032)
  DZeroProgress // a repeat unfold whose 1 iteration consumes no token (DR-043)
  DConfigCycle // a config_file element taking its own path from config (DR-050 §5)
} derive(Eq, Debug)

///|
/// One definition-time Error (DR-054 §4): {element, kind, message, hint}. `hint` is the「次の手」
/// (DR-042 完全性検査の様式). parse_definition enumerates ALL of these (no first-error 打ち切り).
pub(all) struct DefError {
  element : String
  kind : DefErrKind
  message : String
  hint : String
} derive(Eq, Debug)

///|
/// The result-key axis of an element (DR-052). `export_key: string | null` unified: unspecified =
/// name-derived key, a string = key-name override, null (or "" — normalized to null) = NO result
/// key = nameless-同化 透過 (the value still propagates; only the key is gone). This is a RESULT
/// concern only — lexical scope (name, DR-033) and id (ref/link, DR-046) are orthogonal, unchanged.
pub(all) enum ExportKey {
  EkUnset // unspecified → the name is the key (DR-046 default supply)
  EkKey(String) // a string override → that key name
  EkNull // null / "" → 結果キー軸なし → 透過 (kv: value gone; seq: value stays as an array element)
} derive(Eq, Debug)

///|
/// Type category of a value cell / primitive. `number` (TNum) accepts integers and floats; `int`
/// (TInt) is integer-constrained by 値空間判定 — a non-integer VALUE follows `int_round`
/// (DR-075, canonical default `error`). `float` shares TNum's accept域 (number + inf, DR-074 §1);
/// no distinct float variant exists yet, so inf handling stays out of the number-型 lexicon here.
pub(all) enum Ty {
  TStr
  TNum
  TInt
  TFlag
} derive(Eq, Debug)

///|
/// A node of the AtomicAST. Consumption is measured in whole argv tokens.
pub(all) enum Node {
  /// literal token match; binds nothing, consumes 1.
  Exact(String)
  /// string value primitive: consume 1 token, bind name=VStr(token). Maximally permissive (DR-041 §5).
  StrArg(String)
  /// separator-splitting value primitive (DR-034 separator pipeline): consume 1 token, split it
  /// on the separator char, and bind ONE `name=part` per split piece. `SepArg("xs", ",")` on the
  /// token `a,b` binds xs=a and xs=b. Combined with repeat, each firing splits, and the flatten
  /// accumulator folds all pieces into one list (`prog a,b c,d` → xs=[a,b,c,d]).
  SepArg(String, String)
  /// number value primitive: consume 1 token; parse-fail is a held Error (DR-041 §5 / DR-037).
  /// The parse failure is `kind: parse` (DR-053).
  NumArg(String)
  /// a number value with a max post-filter (DR-034 filter / DR-053 kind demo): consume 1 token,
  /// parse a number; a parse failure is `kind: parse`, a value ABOVE `max` is a `kind: filter`
  /// held Error (a value that parsed but failed the filter — post_filter reject 相当).
  FilterArg(String, Int)
  /// a REQUIRED string positional (DR-047 値充足 / DR-053 kind: constraint): consumes a token if
  /// present; if there is NO token to consume, it is a `kind: constraint` held Error (required
  /// 未充足) rather than a silent Reject — a delayed-predicate violation surfaced as an Error.
  ReqArg(String)
  /// 0-token binder: bind name=value. Used to set a flag after its Exact trigger fired.
  /// This is the SET degenerate form of an effect (DR-045 §1).
  Bind(String, Value)
  /// 0-token EFFECT binder (DR-045): apply a non-set op (default / unset / empty) to the
  /// named cell after an Exact trigger fired. This is the lowering of a variant entry's
  /// effect: `--no-color` → `Seq([Exact("--no-color"), EffMark("color", Unset)])` — the
  /// `link` (to the color cell) is by-name, the `effect` is the op carried here.
  EffMark(String, EffectOp)
  /// 0-token deprecation mark (DR-058): records that a deprecated ENTRY (an alias with
  /// `deprecated: true`, DR-057) was used to reach the named canonical cell. Lowered by the long
  /// installer onto a deprecated element's satellite (`Seq([Exact("--old"), Bind("port", …),
  /// DeprMark("port")])`); the short installer sets `depr: true` on the cluster entry instead. It
  /// rides in the effect column as a `@depr:<name>` marker binding (like a FailMark), collected
  /// into ParserContext.warnings. The value propagates normally — only a warning is added.
  DeprMark(String)
  /// 0-token failure-action mark (DR-048): records that failure-action element `name` (e.g. help)
  /// was SELECTED at the current argv position. Lowered from a `fail_action` element's satellite
  /// (`Seq([Exact("--help"), Bind("help", true), FailMark("help")])`). On a FAILED parse (0
  /// complete paths) the recorded action fires in place of the held Error; 先食い/内部一体 keeps
  /// a dd-internal `--help` from being selected (its trigger is raw-consumed, so FailMark never runs).
  FailMark(String)
  /// choice — every alternative's readings become branches (DR-037 / DR-041 §3).
  Or(Array[Node])
  /// ordered consumption; bindings accumulate across the sequence.
  Seq(Array[Node])
  /// unbounded repeat (>= 0). Guarded against zero-progress loops.
  Many(Node)
  /// result scope label (DR-025). Light layer-3 hook; does not change path count.
  Scoped(String, Node)
  /// the two-face scope: greedy (order-free triggers) over a positional face (DR-041 §4).
  ScopeNode(Scope)
  /// native matcher: data-driven token readings (DR-041 §3-4), installed by long/short (DR-042).
  NativeMatch(Matcher)
  /// reference to a named template in the registry (DR-020 / DR-043). repeat lowers to
  /// a recursive `Seq([head, Opt(Ref(self))])`; a ref element (`{ref:"color"}`) points at
  /// a shared template. On the positional spine `Ref` unfolds POROUSLY (>= 1 head, greedy
  /// may interject between reps — the unfold stays on the current backbone, DR-043).
  Ref(String)
  /// dashdash satellite (DR-041 dashdash, rev). A GREEDY-face resident: its matcher
  /// is a plain exact match on the trigger (usually `--`). Because it is a greedy
  /// entry, 先食い (greedy-only) keeps `--` from being raw-eaten; when it fires the
  /// spine walk switches to "severed" mode (greedy off) for the rest — the sever is
  /// the "greedy internal consumption is 一体" rule, not a dd special case.
  DdSat(String)
  /// command satellite (DR-018 / DR-041 §4). A GREEDY-face resident whose matcher is
  /// a plain exact match on the command name. Firing enters the child scope as a NEW
  /// backbone (the parent greedy face does not interject inside it). 先食い protects the
  /// command name from a positional raw-eat, which is the DR-018 "commands が先" priority.
  CmdSat(String, Scope)
  /// link/scope-targeted wrapper (DR-042 global link-sync / DR-007 link). Evaluates its inner
  /// node but marks every binding it produces as a link that escapes `Int` result-nesting levels
  /// (= the scopes this copied satellite sits BELOW its declaration). Those bindings climb out of
  /// the sub-scopes and land on the DECLARING scope's entity. The global installer copies an
  /// option's satellite into a descendant scope wrapped in `Rooted(node, depth)`, so the value
  /// syncs to the one declaring cell instead of a fresh child cell (depth 1 for a direct child,
  /// +1 per re-propagation level). A root global's depth = firing depth (escapes to the root).
  Rooted(Node, Int)
  /// a filtered string value (DR-037 pre_filter): consumes a token ONLY if it does not
  /// start with `-`; otherwise it REJECTS (no reading, silently drops — not an Error).
  /// This is the structural stop that keeps a permissive repeat from eating a following
  /// `--socket` / `--upstream` trigger inside a no-backbone region (DR-041 §4).
  NoDashStr(String)
  /// a BOUNDED repeat tail (DR-043 max 有限 / LOWERING §B.8). Consumes 0..budget more heads
  /// on the spine, POROUSLY (via consume_head, so 先食い holds) and with the 取り分選好
  /// preference (greedy default / lazy). A bounded `repeat: {min, max}` lowers to `min`
  /// mandatory heads on the spine followed by `BoundedTail(head, max-min, lazy)` — NO Ref
  /// recursion (the bound is the recursion depth of the tail, not an unbounded self-ref).
  /// `optional: true` = `repeat: {min:0, max:1}` reduces to a lone `BoundedTail(head, 1, _)`.
  BoundedTail(Node, Int, Bool)
  /// a named indexed-array repeat (DR-043 repeat × DR-025 name scope). Consumes its head
  /// GREEDILY (as many reps as the head allows), tagging rep k under `[label, "#k"]` so
  /// the result builder yields an ARRAY of one element per firing (multiple:"append").
  /// `min` is the required rep count (0 = may be empty). Greedy-max is the 取り分選好
  /// default; for this raw pattern the split is bounded by the head's Reject / exact, so
  /// no downstream backtrack is needed (DR-043 §取り分の選好, 大域完全経路).
  IdxRepeat(String, Node, Int)
} derive(Eq, Debug)

///|
/// A scope carries two faces (DR-041 §4):
/// - `greedy`: order-independent trigger entries (long/short satellites + matchers).
///   Each fires as a bound unit; its internal value slots raw-consume (getopt 同型).
/// - `positional`: the ordered, porous token stream. Greedy may interject between items.
/// - `entities`: value cells with the source ladder (env/default seats, DR-030/031).
pub(all) struct Scope {
  greedy : Array[Node]
  positional : Array[Node]
  entities : Array[Entity]
  constraints : Array[Constraint] // delayed predicates (DR-055/047), declared by the constraint installer
} derive(Eq, Debug)

///|
/// A delayed-predicate constraint (DR-055 / DR-047), evaluated on a complete path's FINAL state. A
/// violation makes the path NOT a complete解決経路 (DR-047 §2) — a DR-037 Error of kind:constraint.
pub(all) enum Constraint {
  /// element committed → each target must have a value (default 込み). requires = 正の依存 (DR-055 §3).
  CRequires(String, Array[String])
  /// value-dependent requires (DR-055 §1): element committed AND its value == the given string →
  /// the targets are required. This is the「値の枝 (exact) に付いた requires」as a value-conditional.
  CRequiresIf(String, String, Array[String])
  /// conflicts_with (DR-055 §2, 対称): element committed + any target committed → conflict. Declaring
  /// on one side works both ways (the check is「両方 committed」regardless of who declared it).
  CConflicts(String, Array[String])
  /// exclusive_group: at most one member of the group may be committed (DR-047 指定述語).
  CExclusive(String, Array[String])
} derive(Eq, Debug)

///|
/// A value cell (DR-030 "entity-only node"). Satellites/matchers with the same
/// `name` all write here = link 合流. Carries the reduced value-source ladder:
/// env seat (declared by the env installer), inherit seat (declared by the inherit
/// installer), and default seat. Ladder order is engine-owned (DR-031, invariant ④):
/// cli > env > inherit > default. The inherit seat looks up the nearest ancestor
/// scope's same-named entity value (縮退ラダー: inherit → default for this PoC).
pub(all) struct Entity {
  name : String
  ty : Ty
  mut env_key : String? // env seat lookup; None = no env seat declared (env installer sets it)
  mut config_seat : Bool // config seat declared (DR-050): fill from the config object by path
  mut config_key : Array[String]? // explicit absolute config path (DR-050 §3); None = 同型 (scope path + name)
  is_config_file : Bool // this cell's value is the config-file PATH (DR-050): resolves the provider, no config seat
  mut inherit_ : Bool // inherit seat declared (inherit installer sets it, DR-031 / DR-013). MDR-003: `inherit` 予約語回避
  // The accumulators-registry name (DR-036) that folds this cell's effect list, or None for a
  // scalar cell. Built-ins: "flatten" (repeat's cons [T,[T,…]] → T[], DR-043) and "append"
  // (multiple's value fold, DR-034). Both realize a value LIST here; the name records WHICH
  // registry accumulator so the AST is self-describing (a scalar cell has None).
  accum : String? // None = scalar; Some("flatten"|"append"|...) = accumulate via that registry entry
  default_value : Value? // default seat
} derive(Eq, Debug)

///|
/// A long-option entry the eq-split matcher can resolve (`--key=value`).
pub(all) struct LongEntry {
  key : String
  name : String
  kind : Ty
} derive(Eq, Debug)

///|
/// A short-option entry the cluster matcher can resolve (`-abc`, `-n1.0`).
/// `depr` (DR-057/058): this entry is a deprecated alias spelling — firing it emits a `@depr:<name>`
/// warning marker (the value binding is unchanged). Only a deprecated ALIAS sets it; a canonical or
/// non-deprecated alias short has `depr: false`.
pub(all) struct ShortEntry {
  ch : Char
  name : String
  kind : Ty
  depr : Bool
} derive(Eq, Debug)

///|
/// A native matcher (DR-041): reified token-reading capability as DATA.
/// The evaluator interprets it (`run_matcher`); installers construct it from
/// the collected entry table (DR-042: "回収したエントリ表が matcher の構成データ").
pub(all) enum Matcher {
  /// `--key=value` split. Fires only on tokens containing `=`. Undefined key = no reading (素通し).
  EqSplit(prefix~ : String, entries~ : Array[LongEntry])
  /// `-abc` cluster + value attachment. Enumerates ALL readings (DR-041 §3-4); ambiguous defs
  /// (the `-cv` problem) surface as multiple readings that both complete.
  ShortCombine(prefix~ : String, entries~ : Array[ShortEntry])
} derive(Eq, Debug)

// ── completion candidate 型 (DR-060 §3) — 型のみ移植 (slice complete.mbt 1-57) ─
// The completion走査 (comp_scope 等) is outcome.mbt's job (MDR-002 §3); only the DATA the
// evaluator's `Pending` branch carries lives here. `Cand` uses `Ty`, so it sits beside it.

///|
/// A terminal hint on an exact candidate (DR-060 §3): `WordEnd` = 確定, a space may follow; `Cont` =
/// 継続, no space (a value must follow — e.g. a value-taking --port, or a `--key=` / dir `/` in prod).
pub(all) enum TermHint {
  WordEnd
  Cont
} derive(Eq, Debug)

///|
/// Declaration-layer meta a completion reads by reference (DR-056 / DR-057 / DR-058): whether a
/// spelling is an alias entry, hidden (excluded from candidates by default, kept in meta), deprecated.
pub(all) struct CandMeta {
  is_alias : Bool
  hidden : Bool
  deprecated : Bool
} derive(Eq, Debug)

///|
/// A completion candidate (DR-060 §3): either an exact trigger spelling, or a value position (type +
/// completer名, PoC shows the type). Meta rides alongside; policy / replacement / landing is the
/// generator's & shell's (kuu returns素材 only).
pub(all) struct Cand {
  spelling : String // the exact spelling; "" for a value position
  is_value : Bool
  ty : Ty // for a value position
  origin : String // the element name it came from
  term : TermHint
  meta : CandMeta
} derive(Eq, Debug)

///|
/// The outcome of trying a node against a token prefix (MDR-002 §2.1). A missing branch == Reject
/// (silently dropped, DR-037); `Held` == Error (retained for failure display); `Accept(pos, binds)`
/// == a reading; `Pending(cands, binds)` == トリガ消費・値 pending (parse では Held 相当、complete では
/// 補完候補の源, MDR-002 §2 案B). The matcher only CONSTRUCTS Accept/Held; the evaluator produces and
/// consumes Pending. (Kept in node.mbt so both matcher and eval can return it; single package.)
enum Branch {
  Accept(Int, Array[Binding]) // (new position, accumulated bindings)
  Held(ParseError, Array[Binding]) // a DR-037 Error + the partial state (acc) at the error point
  Pending(Array[Cand], Array[Binding]) // trigger consumed, value slot's input absent
} derive(Debug)
