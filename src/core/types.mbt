///|
pub(all) struct ParseErrorInfo {
  message : String
  help_text : String
}

///|
pub(all) suberror ParseError {
  ParseError(ParseErrorInfo)
  HelpRequested(String)
}

///|
pub(all) enum Variation {
  Toggle(String) // --{p}-{name}: !current（トグル）。Bool 専用。偶数回で元に戻る
  True(String) // --{p}-{name}: 常に true（Bool 専用、冪等）
  False(String) // --{p}-{name}: 常に false（Bool 専用、冪等）
  Reset(String) // --{p}-{name}: cell=default, was_set=true
  Unset(String) // --{p}-{name}: cell=default, was_set=false
} derive(Show, Eq)

///|
pub(all) enum ReduceAction {
  Value(String?)
} derive(Show, Eq)

///|
pub(all) enum TryResult {
  Accept(consumed~ : Int, commit~ : () -> Unit)
  Reject
  Error(ParseError)
}

///|
pub(all) struct ExactNode {
  name : String
  needs_value : Bool
  try_reduce : (Array[String], Int) -> TryResult
  reset : () -> Unit
}

///|
pub(all) struct Parser {
  next_id : () -> Int
  nodes : Array[ExactNode]
  global_nodes : Array[ExactNode]
  positionals : Array[((Array[String], Int) -> TryResult, Bool)]
  current_positional : Ref[Int]
  parsed : Ref[Bool]
  children : Map[String, ParseResult]
  metas : Array[OptMeta]
  description : Ref[String]
  post_hooks : Array[() -> Unit raise ParseError]
  registered_names : Map[String, Bool]
  duplicate_errors : Array[String]
}

///|
pub(all) struct Opt[T] {
  id : Int
  name : String
  getter : () -> T
  parsed : Ref[Bool]
  is_set : () -> Bool
}

///|
pub(all) struct CmdResult {
  name : String
  parser : Parser
}

///|
pub(all) struct OptRef {
  name : String
  is_set : () -> Bool
}

///|
pub fn[T] Opt::as_ref(self : Opt[T]) -> OptRef {
  { name: self.name, is_set: self.is_set }
}

///|
pub(all) enum ParseResultKind {
  One // 単一値（このスコープの opt 群の結果）
  Map_(Map[String, ParseResult]) // サブコマンド名 → 子の ParseResult
  List_(Array[ParseResult]) // serial/rest の位置別 ParseResult
}

///|
pub(all) struct ParseResult {
  kind : ParseResultKind
  // opt の getter を保持するため、このスコープの parser への参照が必要
  parser : Parser // このスコープの Parser（get(opt) で使う）
}

///|
pub(all) enum OptKind {
  Flag
  ValueOpt
  Command
  Positional
  Rest
} derive(Show, Eq)

///|
pub(all) struct OptMeta {
  kind : OptKind
  name : String
  help : String
  value_name : String
  default_display : String
  global : Bool
  shorts : Array[Char]
  aliases : Array[String]
  variation_names : Array[String]
  hidden : Bool
}

///|
/// A → B の変換ステップ（ParseError を伝搬できる）
pub(all) struct FilterChain[A, B] {
  run : (A) -> B raise ParseError
}

///|
/// 片 U を現在の累積値 T にマージする関数
pub type Accumulator[T, U] = (T, U) -> T

///|
/// reducer に渡すコンテキスト。将来メソッド追加してもシグネチャ不変（DR-008）
pub(all) struct ReduceCtx[T] {
  current : T
  action : ReduceAction
}

///|
/// Filter 名前空間用（コンストラクタの名前空間として使用）
pub(all) struct Filter {}

///|
/// 遅延評価可能な値。Val は即値、Thunk は遅延評価
pub(all) enum Lazy[T] {
  Val(T)
  Thunk(() -> T)
}

///|
/// Lazy[T] を評価して値を取得
pub fn[T] Lazy::resolve(self : Lazy[T]) -> T {
  match self {
    Val(v) => v
    Thunk(f) => f()
  }
}
