// node.mbt — the AtomicAST node ADT and its two-face scope.
//
// DR-039: AtomicAST = a declarative serialization of the bottom-up engine's node
// graph. The core grammar is atomic (exact / or / seq / primitive + multiple)
// plus name (result scope). DR-041 §1: matchers add runtime reading capability
// WITHOUT adding schema — so `NativeMatch` carries matcher DATA (not an opaque
// closure), keeping the whole AST comparable (`derive(Eq, Show)`) for the
// order-independence permutation test (DR-042).

/// Type category of a value cell / primitive.
pub(all) enum Ty {
  TStr
  TNum
  TFlag
} derive(Eq, Show)

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
  NumArg(String)
  /// 0-token binder: bind name=value. Used to set a flag after its Exact trigger fired.
  /// This is the SET degenerate form of an effect (DR-045 §1).
  Bind(String, Value)
  /// 0-token EFFECT binder (DR-045): apply a non-set op (default / unset / empty) to the
  /// named cell after an Exact trigger fired. This is the lowering of a variant entry's
  /// effect: `--no-color` → `Seq([Exact("--no-color"), EffMark("color", Unset)])` — the
  /// `link` (to the color cell) is by-name, the `effect` is the op carried here.
  EffMark(String, EffectOp)
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
  /// link/root-targeted wrapper (DR-042 global link-sync / DR-007 link). Evaluates its
  /// inner node but marks every binding it produces as `link` — those bindings escape
  /// result nesting and land on the DECLARING (root) entity. The global installer copies
  /// an option's satellite into a child scope wrapped in `Rooted`, so the value syncs to
  /// the one root cell instead of a fresh child cell.
  Rooted(Node)
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
} derive(Eq, Show)

/// A scope carries two faces (DR-041 §4):
/// - `greedy`: order-independent trigger entries (long/short satellites + matchers).
///   Each fires as a bound unit; its internal value slots raw-consume (getopt 同型).
/// - `positional`: the ordered, porous token stream. Greedy may interject between items.
/// - `entities`: value cells with the source ladder (env/default seats, DR-030/031).
pub(all) struct Scope {
  greedy : Array[Node]
  positional : Array[Node]
  entities : Array[Entity]
} derive(Eq, Show)

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
  mut inherit : Bool // inherit seat declared (inherit installer sets it, DR-031 / DR-013)
  // The accumulators-registry name (DR-036) that folds this cell's effect list, or None for a
  // scalar cell. Built-ins: "flatten" (repeat's cons [T,[T,…]] → T[], DR-043) and "append"
  // (multiple's value fold, DR-034). Both realize a value LIST here; the name records WHICH
  // registry accumulator so the AST is self-describing (a scalar cell has None).
  accum : String? // None = scalar; Some("flatten"|"append"|...) = accumulate via that registry entry
  default_value : Value? // default seat
} derive(Eq, Show)

/// A long-option entry the eq-split matcher can resolve (`--key=value`).
pub(all) struct LongEntry {
  key : String
  name : String
  kind : Ty
} derive(Eq, Show)

/// A short-option entry the cluster matcher can resolve (`-abc`, `-n1.0`).
pub(all) struct ShortEntry {
  ch : Char
  name : String
  kind : Ty
} derive(Eq, Show)

/// A native matcher (DR-041): reified token-reading capability as DATA.
/// The evaluator interprets it (`run_matcher`); installers construct it from
/// the collected entry table (DR-042: "回収したエントリ表が matcher の構成データ").
pub(all) enum Matcher {
  /// `--key=value` split. Fires only on tokens containing `=`. Undefined key = no reading (素通し).
  EqSplit(prefix~ : String, entries~ : Array[LongEntry])
  /// `-abc` cluster + value attachment. Enumerates ALL readings (DR-041 §3-4); ambiguous defs
  /// (the `-cv` problem) surface as multiple readings that both complete.
  ShortCombine(prefix~ : String, entries~ : Array[ShortEntry])
} derive(Eq, Show)
