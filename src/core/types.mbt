///|
pub(all) suberror ParseError {
  ParseError(String)
}

///|
pub(all) enum ReduceAction {
  Value(String?)
  Negate
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
  force_positional : Ref[Bool]
  parsed : Ref[Bool]
  children : Map[String, ParseResult]
}

///|
pub(all) struct Opt[T] {
  id : Int
  getter : () -> T
  parsed : Ref[Bool]
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
