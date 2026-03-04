///|
pub(all) enum Kind {
  Option
  Command
  Positional
} derive(Eq, Show, Debug)

///|
pub(all) enum Visibility {
  Visible
  Advanced
  Deprecated
  Hidden
} derive(Eq, Show, Debug)

///|
pub(all) enum ValueSource {
  Initial
  Default(String)
  Environment
  CommandLine
} derive(Eq, Show, Debug)

///|
pub(all) enum ReduceAction {
  Value(String?)
  Negate
} derive(Eq, Show, Debug)

///|
pub(all) enum InitialValue[T] {
  Val(T)
  Thunk(() -> T)
}

///|
pub(all) struct ShortEntry {
  char : Char
} derive(Eq, Show, Debug)

///|
pub(all) struct AliasEntry {
  name : String
  deprecated : Bool
} derive(Eq, Show, Debug)

///|
pub(all) enum FlagInversion {
  No
  EnableDisable
  Custom(String, String)
} derive(Eq, Show, Debug)

///|
pub(all) struct OptMeta {
  name : String
  kind : Kind
  help : String
  shorts : Array[ShortEntry]
  aliases : Array[AliasEntry]
  inversion : FlagInversion?
  env : String?
  auto_env : Bool?
  choices : Array[String]
  value_name : String
  required : Bool
  visibility : Visibility
  global : Bool
  greedy : Bool
} derive(Eq, Show, Debug)

///|
pub(all) enum ErrorKind {
  UnknownOption
  UnexpectedArgument
  MissingRequired
  InvalidValue
  ArgumentConflict
  AmbiguousMatch
  MissingValue
  TooManyValues
  MissingSubcommand
  PositionalAsFlag
  MultipleUse
} derive(Eq, Show, Debug)

///|
pub(all) struct ErrorContext {
  option_name : String
} derive(Eq, Show, Debug)

// Design rationale: ParseError は suberror として定義する。
// DESIGN.md では enum だが、MoonBit で raise に使うには suberror が必要。
// suberror には derive(Eq) が使えないため、手動で Eq を実装する。

///|
pub(all) suberror ParseError {
  Usage(ErrorKind, String, ErrorContext)
  Internal(String)
} derive(Show, Debug)

///|
pub(all) struct ReduceCtx[T] {
  current : T
  action : ReduceAction
}

///|
/// 型消去された確定値を運ぶ構造体
// Design rationale: try_reduce は投機実行（副作用なし）であるべき。
// reducer の結果を commit クロージャに封じ込め、commit_reduce 時に実際の書き込みを行う。
pub(all) struct ReduceResult {
  commit : () -> Unit
}

///|
pub(all) enum TryReduceResult {
  Accept(consumed~ : Int, result~ : ReduceResult)
  Reject
  Error(ParseError)
}

///|
pub(all) struct ErasedNode {
  meta : OptMeta
  try_reduce : (ReduceAction, ResultMap) -> TryReduceResult
  commit_reduce : (ReduceResult, ResultMap) -> Unit
  reset_to_initial : (ResultMap) -> Unit
  is_set : () -> Bool
  children : () -> Array[ErasedNode]
}

///|
pub(all) enum Opts {
  Node(ErasedNode)
  Array(Array[Opts])
}

///|
pub(all) struct Opt[T] {
  id : Int
  initial : InitialValue[T]
  reducer : (ReduceCtx[T]) -> T? raise
  meta : OptMeta
  // Design rationale: 現時点では単一 Ref[T] で instance_id=0 固定。
  // グループ機能（Step 11）実装時に Map[Int, Ref[T]] に変更し、
  // getter/setter が instance_id を使って正しい Ref を選択するようにする。
  getter : (Int) -> T
  setter : (Int, T) -> Unit
  children_opts : Opts
}

///|
impl[T] Hash for Opt[T] with hash(self) {
  self.id.hash()
}

///|
impl[T] Hash for Opt[T] with hash_combine(self, hasher) {
  hasher.combine_int(self.id)
}

///|
impl[T] Eq for Opt[T] with equal(self, other) {
  self.id == other.id
}

///|
pub(all) struct ResultMap {
  id : Int
  clone_fns : Map[Int, (Int, Int) -> Unit]
}

// Design rationale: Step 4 では最小限の構造。get/set メソッドは Step 5（Validate）/Step 6（Finalize）で追加する。

///|
pub(all) struct ValidateCtx {
  nodes : Array[ErasedNode]
}

///|
pub(all) struct FinalizeCtx {
  nodes : Array[ErasedNode]
}

///|
pub(all) struct Constraint {
  check : (ValidateCtx) -> Unit raise
  help_hint : String
}

///|
pub(all) struct Parser {
  mut seq : Int
  refs : Map[Int, RefV]
  clone_map : Map[Int, Int]
  // フック配列
  preprocessors : Array[(Array[String]) -> Array[String]]
  // Design rationale: Step 4 では Resolve フックの登録 API のみ提供し、実際の呼び出しは Step 8（did-you-mean サジェスト）で実装する。
  // 理由: Resolve フックの型シグネチャは名前解決の介入タイミング（解決前/解決失敗後）によって変わる可能性があり、
  // Step 8 の具体的なユースケース（did-you-mean、あいまいマッチ）実装時に確定させる。
  resolve_hooks : Array[(String, Array[ErasedNode]) -> Array[ErasedNode]?]
  constraints : Array[Constraint]
  finalizers : Array[(FinalizeCtx) -> Unit raise]
}

///|
pub(all) enum RefV {
  Value(ReduceResult)
  Array(Array[ReduceResult])
}

///|
pub fn Parser::new() -> Parser {
  {
    seq: 0,
    refs: {},
    clone_map: {},
    preprocessors: [],
    resolve_hooks: [],
    constraints: [],
    finalizers: [],
  }
}

///|
pub fn Parser::next_id(self : Parser) -> Int {
  self.seq = self.seq + 1
  self.seq
}
