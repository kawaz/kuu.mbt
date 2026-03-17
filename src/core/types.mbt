///|
pub(all) enum ErrorKind {
  UnknownOption
  UnexpectedArgument
  MissingRequired
  InvalidValue
  ArgumentConflict
  AmbiguousMatch
  MissingValue
  MissingSubcommand
  DuplicateDefinition
  AtLeastOneRequired
  DependencyMissing
  ParseAlreadyCalled
} derive(Show, Eq)

///|
pub(all) struct ParseErrorInfo {
  kind : ErrorKind
  message : String
  help_text : String
  opt_name : String
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
  Reset(String) // --{p}-{name}: cell=default, committed=true
  Unset(String) // --{p}-{name}: cell=default, committed=false
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
pub(all) struct PositionalEntry {
  handler : (Array[String], Int) -> TryResult
  is_rest : Bool
  greedy : Bool
}

///|
pub(all) struct NodeTemplate {
  make_node : (String) -> ExactNode
  is_global : Bool
  // implicit_value 付きコンビネータの eq_fallback ノード生成ファクトリ。
  // alias 登録時に alias 名でも eq_fallback_nodes に登録するために使う。
  make_eq_fallback : ((String) -> ExactNode)?
}

///|
pub(all) struct Parser {
  next_id : () -> Int
  nodes : Array[ExactNode]
  global_nodes : Array[ExactNode]
  positionals : Array[PositionalEntry]
  current_positional : Ref[Int]
  parsed : Ref[Bool]
  children : Map[String, ParseResult]
  metas : Array[OptMeta]
  description : Ref[String]
  post_hooks : Array[() -> Unit raise ParseError]
  registered_names : Map[String, Bool]
  duplicate_errors : Array[String]
  force_unclaimed : Array[String]
  node_templates : Map[Int, NodeTemplate]
  // eq_split 専用フォールバックノード。implicit_value 付きコンビネータで
  // make_soft_custom_value_node の "--" ガードをバイパスする value ノードを保持。
  // OC フェーズでは使われず install_eq_split_node のみが参照する。
  eq_fallback_nodes : Array[ExactNode]
  // deprecated コンビネータで使用。deprecated な名前が使われた場合に (name, msg) を記録。
  deprecated_usages : Array[(String, String)]
  // env Phase 2: 型消去された env 適用クロージャ。
  // parse 時に env Map を受け取り、committed=false の opt に env 値を適用する。
  env_applicators : Array[(Map[String, String]) -> Unit raise ParseError]
  // parse_raw の冒頭で env パラメータをセットし、子パーサ（cmd）に伝搬するための共有ストア。
  // Ref にすることで parse_raw 実行時に後からセットできる。
  env_map : Ref[Map[String, String]]
}

///|
/// パーサに登録されたオプションへのハンドル。
/// - accessor: 値の読み書き（ValCell 経由）
/// - used: この Opt 名が CLI で使われたかを返す。
///   通常 Opt では committed と同値、alias/clone では独立して管理される。
pub(all) struct Opt[T] {
  id : Int
  name : String
  priv accessor : Accessor[T]
  parsed : Ref[Bool]
  priv used : () -> Bool
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
  { name: self.name, is_set: self.used }
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
  env_name : String
  global : Bool
  shorts : Array[String]
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

/// 値の格納・状態管理を担う最小単位。cell + committed + default を内包する。
/// core 内部専用（pub にしない）。
///
/// default_val は Lazy[T] で保持する。Thunk を使えば reset のたびに新しいインスタンスを
/// 生成できるため、Array 等の mutable T でも参照共有問題が起きない。
///|
priv struct ValCell[T] {
  cell : Ref[T]
  committed : Ref[Bool]
  default_val : Lazy[T]
}

///|
fn[T] ValCell::new(default : Lazy[T]) -> ValCell[T] {
  { cell: { val: default.resolve() }, committed: { val: false }, default_val: default }
}

///|
/// この ValCell に紐づいた操作インターフェースを返す。
fn[T] ValCell::accessor(self : ValCell[T]) -> Accessor[T] {
  let acc : Accessor[T] = {
    get: fn() { self.cell.val },
    set: fn(v) {
      self.cell.val = v
      self.committed.val = true
    },
    set_value: fn(v) { self.cell.val = v },
    set_commit: fn() { self.committed.val = true },
    reset: fn() {
      self.cell.val = self.default_val.resolve()
      self.committed.val = false
    },
  }
  // reset/clone はテスト API 向け。本体コードでは未使用だが whitebox テストで参照されるため残す。
  ignore(acc.reset)
  let _ : (ValCell[T]) -> ValCell[T] = ValCell::clone
  acc
}

/// default_val で新しい独立した ValCell を作る。現在の cell.val はコピーしない。
/// Lazy[T] により Thunk の場合は clone ごとに新しいインスタンスが生成される。
/// 本体コードでは未使用だが whitebox テストで検証されるため残す。
///|
fn[T] ValCell::clone(self : ValCell[T]) -> ValCell[T] {
  ValCell::new(self.default_val)
}

///|
/// ValCell への操作をクロージャ束として提供。Opt や post_hook から値を操作する統一 API。
/// core 内部専用。
///
/// - set(v)      : value と committed の両方を更新。set(v) = set_value(v) + set_commit()
/// - set_value(v): value のみセット。committed マークは変更しない
/// - set_commit(): committed マークのみセット。value は変更しない
/// - reset()     : value も committed もリセットする（value = default, committed = false）
priv struct Accessor[T] {
  get : () -> T
  set : (T) -> Unit
  set_value : (T) -> Unit
  set_commit : () -> Unit
  reset : () -> Unit
}

