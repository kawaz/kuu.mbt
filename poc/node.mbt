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
  /// number value primitive: consume 1 token; parse-fail is a held Error (DR-041 §5 / DR-037).
  NumArg(String)
  /// 0-token binder: bind name=value. Used to set a flag after its Exact trigger fired.
  Bind(String, Value)
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
  /// dashdash satellite (DR-041 dashdash, rev). A GREEDY-face resident: its matcher
  /// is a plain exact match on the trigger (usually `--`). Because it is a greedy
  /// entry, 先食い (greedy-only) keeps `--` from being raw-eaten; when it fires the
  /// spine walk switches to "severed" mode (greedy off) for the rest — the sever is
  /// the "greedy internal consumption is 一体" rule, not a dd special case.
  DdSat(String)
  /// command satellite (DR-018 / DR-041 §4). A GREEDY-face resident whose matcher is
  /// a plain exact match on the command name. Firing enters the child scope as a NEW
  /// backbone (the parent greedy face does not interject inside it) and SEVERS the
  /// parent for the rest — the subcommand owns everything after it (greedy internal
  /// consumption is 一体, exactly like dd). 先食い protects the command name from a
  /// positional raw-eat, which is the DR-018 "commands が先" priority.
  CmdSat(String, Scope)
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
