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
}

///|
pub(all) struct Opt[T] {
  id : Int
  getter : () -> T
}
