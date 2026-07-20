// node.mbt — the AtomicAST node ADT and its two-face scope.
//
// DR-039: AtomicAST = a declarative serialization of the bottom-up engine's node
// graph. The core grammar is atomic (exact / or / seq / primitive + multiple)
// plus name (result scope). DR-041 §1: matchers add runtime reading capability
// without adding schema; `NativeMatch` carries an opaque resident whose
// `kind + encode` identity keeps the whole AST structurally comparable.
//
// MDR-002 §3: this file is the dependency-free leaf (behaviour-free ADTs only).
// MDR-003: reserved-word collisions (`alias` / `export` / `inherit` 単独) take a
// trailing underscore. Here only `Entity.inherit` collides → `is_inherit`; compound
// spellings (`export_key`, `ExportKey`, `is_config_file`) are already safe.

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

///|
/// The result-key axis of an element (DR-052). `export_key: string | null` unified: unspecified =
/// name-derived key, a string = key-name override, null (or "" — normalized to null) = NO result
/// key = nameless-同化 透過 (the value still propagates; only the key is gone). This is a RESULT
/// concern only — lexical scope (name, DR-033) and id (ref/link, DR-046) are orthogonal, unchanged.
pub enum ExportKey {
  Unset // unspecified → the name is the key (DR-046 default supply)
  Key(String) // a string override → that key name
  Null // null / "" → 結果キー軸なし → 透過 (kv: value gone; seq: value stays as an array element)
} derive(Eq, Debug)

///|
/// Construct the name-derived result-key posture across the package boundary.
pub fn ExportKey::unset() -> ExportKey {
  Unset
}

///|
/// Construct an explicit result-key override across the package boundary.
pub fn ExportKey::key(key : String) -> ExportKey {
  Key(key)
}

///|
/// Construct the result-key-free transparent posture across the package boundary.
pub fn ExportKey::null() -> ExportKey {
  Null
}

///|
/// Input to a type resident's default-seat resolver. `declared` is the explicit
/// scalar default, if any. `observed` is provider data selected by the resident's
/// opaque key; engine transports the JSON value without knowing its schema.
pub struct SeatCtx {
  priv declared : Value?
  priv observed : Json?
}

///|
pub fn SeatCtx::new(declared : Value?, observed? : Json? = None) -> SeatCtx {
  { declared, observed }
}

///|
pub fn SeatCtx::declared(self : SeatCtx) -> Value? {
  self.declared
}

///|
pub fn SeatCtx::observed(self : SeatCtx) -> Json? {
  self.observed
}

///|
/// Open type-category contract. Value lexicons and preset defaults belong to
/// residents; the evaluator sees only this capability surface. A resident may
/// request one provider observation by opaque key and interpret its JSON payload
/// inside `default_seat_resolver`.
pub(open) trait TypeExt {
  fn name(Self) -> String
  fn encode(Self) -> Json = _
  fn has_value_slot(Self) -> Bool
  fn parse_token(Self, String) -> Result[Value, TypeParseFail]
  fn default_seat_observation_key(Self) -> String? = _
  fn default_seat_resolver(Self, SeatCtx) -> Value?
}

///|
impl TypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl TypeExt with fn default_seat_observation_key(_self) {
  None
}

///|
/// Opaque declaration metadata attached to an Entity. Engine dispatches the
/// capability without inspecting builtin-owned fields; the resident projects
/// them onto the stable candidate wire structure.
pub(open) trait EntityExt {
  fn encode(Self) -> Json = _
  fn complete_candidate(Self, Candidate) -> Candidate
}

///|
impl EntityExt with fn encode(_self) {
  ().to_json()
}

///|
pub impl Eq for &EntityExt with fn equal(self, other) {
  self.encode() == other.encode()
}

///|
pub impl Debug for &EntityExt with fn to_repr(self) {
  Debug::to_repr(self.encode())
}

///|
/// A type resident's structural identity includes both its registry name and
/// parser configuration, matching NodeExt's kind-plus-encode contract.
pub impl Eq for &TypeExt with fn equal(self, other) {
  self.name() == other.name() && self.encode() == other.encode()
}

///|
pub impl Debug for &TypeExt with fn to_repr(self) {
  Debug::to_repr((self.name(), self.encode()))
}

///|
/// The evaluator continuation exposed to an open node resident. The private
/// defunctionalized `Cont` stays captured by the closure that implements this
/// function type, so extension code sees only the stable resume capability.
/// A Resume belongs to the current eval call. Retaining it and invoking it from
/// a later eval call replays a stale continuation; result consistency is not supported.
pub type Resume = (Ctx, Int, Array[Binding]) -> Array[Branch]

///|
/// An open AtomicAST leaf resident. `kind + encode` is its collision-free
/// structural identity; the default `equal` keeps every resident on that one
/// comparison contract. `consumes_zero_tokens` is evaluator contract data,
/// replacing central enumeration of builtin marker variants. `eval` may call
/// the supplied Resume only as the continuation of that invocation; retaining
/// it for a later invocation is unsupported.
pub(open) trait NodeExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &NodeExt) -> Bool = _
  fn element_name(Self) -> String? = _
  fn is_failure_action(Self) -> Bool = _
  fn effect_mark(Self) -> (String, EffectOp)? = _
  fn consumes_zero_tokens(Self) -> Bool
  fn eval(Self, Ctx, Int, Array[Binding], Resume) -> Array[Branch]
}

///|
impl NodeExt with fn equal(self, other) {
  self.kind() == other.kind() && self.encode() == other.encode()
}

///|
impl NodeExt with fn element_name(_self) {
  None
}

///|
impl NodeExt with fn is_failure_action(_self) {
  false
}

///|
impl NodeExt with fn effect_mark(_self) {
  None
}

///|
/// Open native-matcher contract. Concrete reading semantics and configuration
/// live in residents. `candidates` is required because every matcher owns its
/// boundary completion spellings; `interpret` may receive an exhausted position
/// and must treat it as no reading. The engine invokes both capability surfaces.
pub(open) trait MatcherExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &MatcherExt) -> Bool = _
  fn candidates(Self) -> Array[Candidate]
  fn interpret(Self, Ctx, Int, Array[Binding], Resume) -> Array[Branch]
}

///|
impl MatcherExt with fn equal(self, other) {
  self.kind() == other.kind() && self.encode() == other.encode()
}

///|
pub impl Eq for &MatcherExt with fn equal(self, other) {
  self.equal(other)
}

///|
pub impl Debug for &MatcherExt with fn to_repr(self) {
  Debug::to_repr((self.kind(), self.encode()))
}

///|
/// A node of the AtomicAST. Consumption is measured in whole args tokens.
pub(all) enum Node {
  /// literal token match; binds nothing, consumes 1.
  Exact(String)
  /// a REQUIRED string positional (DR-047 値充足 / DR-053 kind: constraint): consumes a token if
  /// present; if there is NO token to consume, it is a `kind: constraint` held Error (required
  /// 未充足) rather than a silent Reject — a delayed-predicate violation surfaced as an Error.
  RequiredArgument(String)
  /// 0-token binder: bind name=value. Used to set a flag after its Exact trigger fired.
  /// This is the SET degenerate form of an effect (DR-045 §1).
  Bind(String, Value)
  /// choice — every alternative's readings become branches (DR-037 / DR-041 §3).
  Or(Array[Node])
  /// ordered consumption; bindings accumulate across the sequence.
  Seq(Array[Node])
  /// unbounded repeat (>= 0). Guarded against zero-progress loops. The `Bool` is the DR-043 lazy
  /// knob (issue 2026-07-08 min0-lazy-repeat-gap): mirrors `BoundedTail`'s 3rd field — `Many` is
  /// the min:0 UNBOUNDED spine form the way `BoundedTail` is the bounded one, so it gets the SAME
  /// seat rather than a parallel mechanism (a min>=1 UNBOUNDED lazy repeat already threads its knob
  /// through the registry's `"lazy:" + name` marker, but `Many` re-enters the SAME node at the same
  /// `pidx` — no named template, so no registry key to carry it on). `false` (installer default when
  /// a repeat has no `lazy` spec) preserves the pre-existing greedy-only behavior exactly.
  Many(Node, Bool)
  /// result scope label (DR-025). Light layer-3 hook; does not change path count.
  Scoped(String, Node)
  /// the two-face scope: greedy (order-free triggers) over a positional face (DR-041 §4).
  ScopeNode(Scope)
  /// native matcher: data-driven token readings (DR-041 §3-4), installed by long/short (DR-042).
  NativeMatch(&MatcherExt)
  /// open leaf resident. Builtin value and marker semantics enter the evaluator
  /// only through this one dispatch point.
  Ext(&NodeExt)
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
  DdSatisfied(String)
  /// DR-090: the 2-axis generalization of `DdSatisfied` — a SEPARATE variant (not `DdSatisfied`'s own
  /// arity extended) to keep every existing `DdSatisfied("--")` hand-construction (wbtest files,
  /// installer's canonical exact-dd path) untouched; the installer only ever emits THIS
  /// variant when the definition actually declares `match` and/or `self:"keep"` (§2).
  /// Fields: `(spelling, is_pattern, self_keep, elem_name)`.
  /// - `spelling`: the exact trigger string (`is_pattern=false`, same matching as `DdSatisfied`)
  ///   OR a regex pattern source (`is_pattern=true`, compiled via `compile_regex` — the SAME
  ///   host-dialect compile path DR-085's `regex_match` filter uses, unanchored substring-vs-
  ///   whole-token semantics per DR-090 §2's "match" being a trigger test on the WHOLE token).
  /// - `self_keep`: `false` (drop, DR-090 §2 既定 — consume 1 token, discard it, same as `DdSatisfied`)
  ///   | `true` (keep — consume 0 tokens, Accept immediately; the triggering token itself
  ///   flows into the positional face along with everything after it, still severed).
  /// - `elem_name` (DR-093 §2/§5): the declaring element's `name`, independent of `spelling`
  ///   (§2's "match があるとき name はトリガ綴りに使われず、要素の同一性・表示軸のみに効く" —
  ///   this is that axis, made concrete). Used ONLY to key the committed-observation binding
  ///   the firing arm produces (mirrors `DdSatisfied`'s own trigger-string-as-name shortcut, which only
  ///   works there because `DdSatisfied` never decouples spelling from name). Never used for matching.
  DdMatchSatisfied(String, Bool, Bool, String)
  /// command satellite (DR-018 / DR-041 §4). A GREEDY-face resident whose matcher is
  /// a plain exact match on the command name. Firing enters the child scope as a NEW
  /// backbone (the parent greedy face does not interject inside it). 先食い protects the
  /// command name from a positional raw-eat, which is the DR-018 "commands が先" priority.
  CommandSatisfied(String, Scope)
  /// link/scope-targeted wrapper (DR-042 global link-sync / DR-007 link). Evaluates its inner
  /// node but marks every binding it produces as a link that escapes `Int` result-nesting levels
  /// (= the scopes this copied satellite sits BELOW its declaration). Those bindings climb out of
  /// the sub-scopes and land on the DECLARING scope's entity. The global installer copies an
  /// option's satellite into a descendant scope wrapped in `Rooted(node, depth)`, so the value
  /// syncs to the one declaring cell instead of a fresh child cell (depth 1 for a direct child,
  /// +1 per re-propagation level). A root global's depth = firing depth (escapes to the root).
  Rooted(Node, Int)
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
  /// no downstream backtrack is needed (DR-043 §取り分の選好, 大域完全経路) for the
  /// UNBOUNDED case. The 4th field `budget` (issue
  /// 2026-07-13-positional-group-trailing-missing-operand) caps the ADDITIONAL reps beyond
  /// `min` (same seat as `BoundedTail`'s 2nd field, `max - min`): `None` = unbounded (the
  /// original greedy-max-forever behavior, unchanged), `Some(b)` = stop once `rep >= min +
  /// b`, matching a bounded `repeat: {min, max}` spec exactly instead of silently degrading
  /// every Group repeat to unbounded regardless of a declared `max`. This does NOT add
  /// backtrack (the KNOWN GAP in `eval_wbtest.mbt`'s "IndexedRepeat greedy-max has no downstream
  /// backtrack" test is still open for the unbounded case) — a bounded head simply never
  /// over-consumes in the first place, so no backtrack is needed to correct it.
  IndexedRepeat(String, Node, Int, Int?)
  /// an OPTION's repeat value slot (DR-078 §1 option-level repeat, new capability): wraps ONLY
  /// the repeat TAIL (`Ref`/`Many`/`BoundedTail`, the same node `lower_repeat_head` builds for a
  /// positional) — the trigger/marker prefix ahead of it in the satellite's `Seq` stays plain. A
  /// bare greedy satellite is evaluated OFF-SPINE (`step_greedy`'s catch-all → plain `eval`, no
  /// `Scope`), which cannot apply 先食い (DR-041 §4) to stop the repeat before it swallows a
  /// sibling trigger (e.g. a second `--hlcolors`). `step_greedy` detects this wrapper and
  /// evaluates `tail` through a throwaway `Scope` that BORROWS the real scope's `greedy` face (so
  /// suppression sees every sibling trigger, including a refire of the SAME option) but has its
  /// OWN single-slot `positional` (so the tail's internal repeat loop — which re-enters at the
  /// same pidx for "more" — cannot walk into the real scope's unrelated positional slots).
  /// Off-spine `eval` (completion probes etc.) degrades to plain `eval(tail, ..)`, losing
  /// suppression — acceptable there (no sibling scope to suppress against).
  GreedyRepeat(Node)
}

///|
pub impl Eq for Node with fn equal(self, other) {
  match (self, other) {
    (Exact(a), Exact(b)) => a == b
    (RequiredArgument(a), RequiredArgument(b)) => a == b
    (Bind(an, av), Bind(bn, bv)) => an == bn && av == bv
    (Or(a), Or(b)) => a == b
    (Seq(a), Seq(b)) => a == b
    (Many(an, al), Many(bn, bl)) => an == bn && al == bl
    (Scoped(an, ab), Scoped(bn, bb)) => an == bn && ab == bb
    (ScopeNode(a), ScopeNode(b)) => a == b
    (NativeMatch(a), NativeMatch(b)) => a == b
    (Ext(a), Ext(b)) => a.equal(b)
    (Ref(a), Ref(b)) => a == b
    (DdSatisfied(a), DdSatisfied(b)) => a == b
    (DdMatchSatisfied(as_, ap, ak, an), DdMatchSatisfied(bs, bp, bk, bn)) =>
      as_ == bs && ap == bp && ak == bk && an == bn
    (CommandSatisfied(an, ac), CommandSatisfied(bn, bc)) => an == bn && ac == bc
    (Rooted(an, ad), Rooted(bn, bd)) => an == bn && ad == bd
    (BoundedTail(an, ab, al), BoundedTail(bn, bb, bl)) =>
      an == bn && ab == bb && al == bl
    (IndexedRepeat(an, ah, am, ab), IndexedRepeat(bn, bh, bm, bb)) =>
      an == bn && ah == bh && am == bm && ab == bb
    (GreedyRepeat(a), GreedyRepeat(b)) => a == b
    _ => false
  }
}

///|
pub impl Debug for Node with fn to_repr(self) {
  match self {
    Exact(a) => @debug.Repr::ctor("Exact", [(None, Debug::to_repr(a))])
    RequiredArgument(a) =>
      @debug.Repr::ctor("RequiredArgument", [(None, Debug::to_repr(a))])
    Bind(a, b) =>
      @debug.Repr::ctor("Bind", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
      ])
    Or(a) => @debug.Repr::ctor("Or", [(None, Debug::to_repr(a))])
    Seq(a) => @debug.Repr::ctor("Seq", [(None, Debug::to_repr(a))])
    Many(a, b) =>
      @debug.Repr::ctor("Many", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
      ])
    Scoped(a, b) =>
      @debug.Repr::ctor("Scoped", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
      ])
    ScopeNode(a) => @debug.Repr::ctor("ScopeNode", [(None, Debug::to_repr(a))])
    NativeMatch(a) =>
      @debug.Repr::ctor("NativeMatch", [(None, Debug::to_repr(a))])
    Ext(extension) =>
      @debug.Repr::ctor("Ext", [
        (None, Debug::to_repr(extension.kind())),
        (None, Debug::to_repr(extension.encode())),
      ])
    Ref(a) => @debug.Repr::ctor("Ref", [(None, Debug::to_repr(a))])
    DdSatisfied(a) =>
      @debug.Repr::ctor("DdSatisfied", [(None, Debug::to_repr(a))])
    DdMatchSatisfied(a, b, c, d) =>
      @debug.Repr::ctor("DdMatchSatisfied", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
        (None, Debug::to_repr(c)),
        (None, Debug::to_repr(d)),
      ])
    CommandSatisfied(a, b) =>
      @debug.Repr::ctor("CommandSatisfied", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
      ])
    Rooted(a, b) =>
      @debug.Repr::ctor("Rooted", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
      ])
    BoundedTail(a, b, c) =>
      @debug.Repr::ctor("BoundedTail", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
        (None, Debug::to_repr(c)),
      ])
    IndexedRepeat(a, b, c, d) =>
      @debug.Repr::ctor("IndexedRepeat", [
        (None, Debug::to_repr(a)),
        (None, Debug::to_repr(b)),
        (None, Debug::to_repr(c)),
        (None, Debug::to_repr(d)),
      ])
    GreedyRepeat(a) =>
      @debug.Repr::ctor("GreedyRepeat", [(None, Debug::to_repr(a))])
  }
}

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
} derive(Debug)

///|
pub impl Eq for Scope with fn equal(self, other) {
  self.greedy == other.greedy &&
  self.positional == other.positional &&
  self.entities == other.entities &&
  self.constraints == other.constraints
}

///|
/// One candidate cell that `Required`/`RequiredGroup` may look at (DR-093 の型委譲判定入力、
/// codex レビュー M-2 修正): `name` は値が実際に bind される cell 名 (Or 直書き structural or の
/// leaf name、ref 先 template の leaf name、または通常要素なら要素自身の name)。`wrapper` は
/// scope 判定の基準を切り替える — `None` なら宣言 scope path そのものと完全一致する scope を探す
/// (Or 直書きの leaf、または通常要素 — 値は親 scope に直接 bind される、`ensure_entity_body` の
/// Or コメント参照)。`Some(w)` なら宣言元要素自身 (ref 要素、`w` = ref 要素の name) の Scoped
/// 部分木内 (scope が 宣言 scope path ++ [w] で始まる) を探す — `inst_long`/`lower_positional` の
/// ref 分岐が `Scoped(e.name, ...)` で値をラップするため (DESIGN §2.4/2.5 の露出規則、
/// `ref-template-no-repeat-degenerate.json` が既に pin する挙動と同型)。無制限透過ではなく
/// **宣言元要素自身の部分木に限定** した探索 — 他要素・子 scope の値を誤って拾わないため。
pub(all) struct RequiredCandidate {
  name : String
  wrapper : String?
} derive(Eq, Debug)

///|
/// A delayed-predicate constraint (DR-055 / DR-047), evaluated on a complete path's FINAL state. A
/// violation makes the path NOT a complete解決経路 (DR-047 §2) — a DR-037 Error of kind:constraint.
pub(all) enum Constraint {
  /// element committed → each target must have a value (default 込み). requires = 正の依存 (DR-055 §3).
  Requires(String, Array[String])
  /// value-dependent requires (DR-055 §1 + DR-052 §値枝 id 直交): 4-tuple = (entity, branch_id,
  /// value, targets). Semantics: `entity` が committed AND その値 == `value` のとき、`targets` の値
  /// 充足を要求する。違反時の error.element は `branch_id` (= or 値枝の匿名要素に付いた id、fixture
  /// の `id: "fmt_json"` に相当) を emit する — 値の帰属先は親 entity (format) だが制約の宣言元は
  /// 枝 (fmt_json) なので、element 属性は宣言元を指す (DR-052 と直交)。`branch_id` == `entity` の
  /// ときは or 匿名枝に id が付いていない (parent 直属の value_requires を模したフォールバック)。
  RequiresIf(String, String, String, Array[String])
  /// conflicts_with (DR-055 §2, 対称): element committed + any target committed → conflict. Declaring
  /// on one side works both ways (the check is「両方 committed」regardless of who declared it).
  Conflicts(String, Array[String])
  /// exclusive_group: at most one member of the group may be committed (DR-047 指定述語).
  Exclusive(String, Array[String])
  /// required (DR-093 §1/§2): この entity 自身の「解決後の充足」。充足の定義は型 (値空間) への委譲 —
  /// 値空間を持つ要素 (通常の type) は最終状態の値の有無 (default / env 等の値源込み、DR-047 §5 不変)、
  /// 値空間が空の要素 (`type: "none"`、dd 含む、DR-089) は発火したこと (committed)。判定入力に
  /// committed を使う点は Requires と同じ線 (DR-047 §5 が selected を診断メタに留めた線を維持)。
  ///
  /// 2-tuple = (display, candidates)。issue
  /// 2026-07-13-structural-or-type-branch-required-missing / codex-review-dr102-dr103-postland
  /// (M-2): `display` は違反時の error.element (宣言元の name、DESIGN §9.1 のグループ的必須の宣言元、
  /// 通常要素では下記 candidates[0].name と同じ文字列)。`candidates` (`RequiredCandidate` 配列) は
  /// 型委譲判定を実際にどの cell に対して行うかの候補集合 — 通常要素は `[{name: display, wrapper:
  /// None}]` 自身 (単一候補、既存挙動どおり)。structural or (`Or`、型付き枝、直書き) が required を
  /// 持つ場合は各枝の leaf name (`wrapper: None`、値は親 scope に直接 bind される) の配列: Or
  /// wrapper 自身 (display) は "no own scalar/array value" (installer.mbt の Or entity 登録コメント
  /// 参照) で値が committed されることが無く、値は選ばれた枝の leaf entity (num/flag 等) にのみ
  /// commit される。`ref` 経由の structural or (テンプレート先が Or) も同様に leaf name を候補とする
  /// が、この場合は `wrapper: Some(宣言元 ref 要素の name)` — ref 展開が `Scoped(ref要素名, ...)` で
  /// 値をラップするため、判定は宣言元要素自身の Scoped 部分木内を探す必要がある
  /// (`RequiredCandidate` の doc comment 参照)。判定は candidates のいずれか 1 つでも型委譲で
  /// 充足していれば OK (DR-093 の「or 親の値充足 = どの枝であれ発火して値が確定していること」— 枝が
  /// exact (value-enum, Enum) なら全枝が同じ display 名の cell に着地するため候補は元々
  /// `[{name: display, wrapper: None}]` のままで足りる、対称性が崩れるのは structural or だけ)。
  Required(String, Array[RequiredCandidate])
  /// required_group (DR-103): グループ単位「少なくとも1つ必須」— `exclusive_group` (Exclusive) と
  /// 同型の 2-tuple = (group label, member candidates)。member の充足判定は `Required` と完全に
  /// 同一の型委譲 (DR-093: 値空間ありは値の有無・default 込み、値空間なしは発火 committed) をグループ
  /// の論理和に持ち上げたもの — bool 型の特殊化 (requires 目的語の truth-dispatch) は適用しない
  /// (DR-103 §7、kawaz 裁定 2026-07-14「値述語と依存述語は別」)。member が 1 つだけの場合は
  /// `Required` と観測上同じ結果になる (DR-103 §4 の縮退)。`required_group` と `exclusive_group` の
  /// group 名前空間は独立 (DR-103 §3) — 同名文字列を両属性に書いても 2 つの独立述語として評価される。
  /// candidates の候補セル解決 (`RequiredCandidate` の name/wrapper 双方) は `Required` と完全に
  /// 共有する (`installer.mbt` の `required_candidates` ヘルパー、codex M-2 の再発防止)。
  RequiredGroup(String, Array[RequiredCandidate])
} derive(Eq, Debug)

///|
/// A value cell (DR-030 "entity-only node"). Satellites/matchers with the same
/// `name` all write here = link 合流. Carries the reduced value-source ladder:
/// env seat (declared by the env installer), inherit seat (declared by the inherit
/// installer), and default seat. Ladder order is engine-owned (DR-031, invariant ④):
/// cli > env > config > inherit > default (5 段固定、DR-099 が DR-098 の tty 専用席
/// 挿入を撤回)。The inherit seat looks up the nearest ancestor scope's same-named
/// entity value.
pub(all) struct Entity {
  name : String
  ty : &TypeExt
  mut env_key : String? // env seat lookup; None = no env seat declared (env installer sets it)
  // MDR-005 §3: `pub(all)` → `pub` (公開面キュレーション) でフィールドの外部書き込みが無くなり、
  // 元々パッケージ内でも一度も再代入されていなかった (`ensure_entity` が構築時に決め打つだけ) 実装
  // 上のデッドな `mut` だったことが `unused_mut` 検査で顕在化した — 挙動には無関係、宣言を正す。
  config_seat : Bool // config seat declared (DR-050): fill from the config object by path
  config_key : Array[String]? // explicit absolute config path (DR-050 §3); None = 同型 (scope path + name)
  is_config_file : Bool // this cell's value is the config-file PATH (DR-050): resolves the provider, no config seat
  mut is_inherit : Bool // inherit seat declared (inherit installer sets it, DR-031 / DR-013). MDR-003: `inherit` 予約語回避
  // The registered accumulator resident that folds this cell's effect list, or None for a scalar
  // cell. Built-ins are append (multiple/repeat), merge, and kv_map; each resident owns both its
  // CLI-seat fold and final result projection, so the resolver dispatches without inspecting a name.
  accum : &AccumulatorExt? // None = scalar; Some(resident) = resident-owned fold/collect
  // TRANSITIONAL(M5c): flatten/is_multiple_decl stay on Entity until AccumulatorExt owns
  // the per-fire row-boundary policy used by build_result; moving only one would lose DR-084 semantics.
  // DR-105 §1 flatten dial (append accumulator only, `installer.mbt`'s `ensure_entity` enforces
  // this invariant — a non-append accum cell always carries false here, the definition-error gate
  // `collect_flatten_non_append` rejects any other declared combination before lowering runs):
  // whether an array-shaped fire value gets expanded by ONE level into the accumulated array
  // instead of pushed as a single nested element (`resolve.mbt`'s SEGS-loop per-fire builder is the
  // one reachable consumer today — DR-084 §2's ref+repeat+multiple row array is the only shape in
  // kuu.mbt where a single fire's value is itself array-shaped; `Value` (value.mbt) has no array
  // variant, so a plain scalar multiple cell's fire is never array-shaped and this dial is
  // observationally inert there, DR-105 §1's "非配列 → 丸ごと1要素" clause holds vacuously).
  // `ensure_entity`'s repeat-cons branch (no `multiple` declared) ALSO sets this true unconditionally
  // (DR-105 §3: the old standalone "flatten" accumulator's lowering output is now `append` +
  // `flatten:true`) — `is_multiple_decl` below is what still tells the two origins apart where the
  // distinction actually matters (DR-084 §2's firing-preserving-vs-discard gate).
  flatten : Bool
  // DR-084 §2 origin marker: whether this cell's accumulator seat came from a declared `multiple`
  // (append-preserving-across-firings) as opposed to the repeat installer's own cons-unfold cell
  // (no `multiple` declared, discard-earlier-firings/last-wins-whole-cell — `last-wins-repeat-
  // rows.json`). Before DR-105 this distinction rode on `accum == Some("flatten")` vs not; DR-105 §3
  // collapses both origins onto the SAME accum name ("append") + flatten dial, so `resolve.mbt`'s
  // SEGS-loop gate (`build_result`'s `seg_is_multiple_ref`) needs this independent copy of
  // `ElementDef.multiple` to keep telling them apart (`ensure_entity`'s doc comment / `AccumCell`'s own
  // copy in resolve.mbt).
  is_multiple_decl : Bool
  // DR-036 collector resident: the T[]→U transform applied after the accumulator's final result
  // projection. Only meaningful when `accum is Some(_)`; None renders the accumulator result as-is.
  // The configured resident carries its own kind + encode identity and collect implementation.
  collector : &CollectorExt?
  // DR-083 §1/§波及: default seat, stored as a length-1-degenerate UNIFORM array (`None` = no
  // declared default; a scalar cell's declared default is `Some([v])`, length exactly 1; a
  // `multiple`/repeat/merge (accum) cell's is `Some([v1, v2, ...])`, one piece per declared array
  // element — DR-050 §4's config-array precedent, "already split pieces" per DR-083 §2). Every
  // reader that KNOWS its cell is scalar (bool-target checks, the scalar CLI-seat fold's Unset/
  // Update "old ?? default" arms) takes `vs[0]` (a scalar's array is always length 1 by
  // construction, `ensure_entity`'s only producer). The accum-cell-aware readers (`resolve_ladder_
  // below_cli`'s default seat, `collect_scalar_array_default`'s definition-time gate) iterate the
  // whole array — this single field replaces the pre-DR-083 `default_value : Value?` (a design
  // taken up again after being shelved mid accum-fold-update-default-ops, now justified by DR-083).
  default_values : Array[Value]?
  // Canonical lazy default-seat cell-fn placeholder. Scalar fixed defaults carry typed set(value);
  // explicit default_fn declarations carry their wire invocation for observes binding.
  default_fn : DefaultFnCall?
  // TRANSITIONAL(M5c): separator remains because the env seat still performs pre-parse piece
  // splitting; no seat/piece descriptor currently owns this cross-seat policy.
  // DR-034 multiple の separator (issue 2026-07-09-env-separator-split-gap): the env seat's OWN
  // copy, mirroring `piece_filters` below — `resolve.mbt`'s `env_value` runs the pieceProcessor once
  // per piece exactly like `eval.mbt`'s `sep_binds` does for the CLI seat's raw token, but the CLI
  // seat's split already happened upstream (at token-consumption time); the env seat's raw string
  // hasn't been split at all until this field tells `resolve_entity_raw` to. `None` = no separator
  // declared (the common case, and every non-`multiple` cell) — env value stays a single piece.
  separator : String?
  // TRANSITIONAL(M5c): filter spellings remain until Entity can carry configured filter
  // residents for every phase; the registry currently resolves them at each runtime application.
  // DR-034/DR-062 piece_filters (String→String, per-piece / pre-parse 相): unlike `value_filters`/
  // `final_filters`/`accum_filters` below (which run AFTER a ladder seat's value is already
  // resolved, in `resolve.mbt`'s `apply_entity_filters`), piece_filters only ever runs BEFORE a
  // string→T parse — i.e. only for STRING-typed ladder inputs. The CLI seat's own piece_filters
  // application happens upstream in eval.mbt/builtins/matcher_residents.mbt (token consumption, before the value ever
  // reaches this Entity) — this copy exists so the ladder's OTHER string-sourced seats (env: DR-049
  // §2 "env 値も pieceProcessor を通る") can run the SAME chain via `resolve.mbt`'s `env_value`. A
  // non-string ladder source (config number/bool matching the type, default, inherit) has no parse
  // step to gate, so this field is simply unused there (DR-050 §4's "型一致なら value_filters のみ"
  // — piece_filters/parse は元々 String→T の関数なので、型一致で供給された非 string 値には適用対象
  // が無いという型の帰結、特別規則ではない).
  piece_filters : Array[FnInvocation]
  // DR-009 value_filters (each, T→T): applied to EVERY value this cell resolves from ANY ladder seat
  // (cli/env/config/inherit/default) right after that seat's own value is determined — same timing
  // "type.parse の後、accumulator の前" DR-009's [4]→[5] describes. For a scalar cell (no accum)
  // this collapses to "applied once, right before final_filters" since only one seat ever wins.
  value_filters : Array[FnInvocation]
  // DR-009 / DR-102 §1 final_filters (T→T、確定した最終値ガード、non-accum 専用): applied to the
  // FINAL resolved value, after the ladder has picked a winning seat — a scalar (non-accum) cell
  // only. This is the one place both `set` and `update` effects converge before the value leaves
  // resolve_entity (DR-077 §1 "final_filters は update の結果にも通す" の実証対象そのもの、the whole
  // point of this issue). An accum cell (multiple/repeat/separator) leaves this empty — its
  // ARRAY-shaped final gate is `accum_filters` below, applied at build_result instead
  // (`apply_entity_filters` never reaches this field for an accum cell).
  final_filters : Array[FnInvocation]
  // DR-009 段 7 / DR-102 §1 accum_filters (Acc→Acc、累積配列全体、accum 専用): applied to the WHOLE
  // accumulated array, AFTER accumulation completes (`resolve.mbt`'s `build_result`, via
  // `AccumCell.accum_filters`) — a scalar (non-accum) cell leaves this empty (its T→T final gate is
  // `final_filters` above). 1 属性 1 registry (ARRAY filter registry) の対応 — multiple 有無で
  // registry を切り替える位置依存判定 (DR-101 §3) は本分割で不要化した。
  accum_filters : Array[FnInvocation]
  // DR-110 §3-10 / §6 #20: builtin-owned completion metadata is an opaque resident.
  // Engine carries and dispatches this slot but does not inspect hidden/completer fields.
  extension : &EntityExt
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
