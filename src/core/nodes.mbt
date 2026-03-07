///|
fn make_flag_node(
  name : String,
  on_match : () -> () -> Unit,
  reset : () -> Unit,
) -> ExactNode {
  ExactNode::{
    name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() {
        Reject
      } else if args[pos] == name {
        let commit = on_match()
        Accept(consumed=1, commit~)
      } else {
        Reject
      }
    },
    reset,
  }
}

///|
fn make_value_node(
  name : String,
  on_match : (String) -> Result[() -> Unit, ParseError],
  reset : () -> Unit,
) -> ExactNode {
  ExactNode::{
    name,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() {
        Reject
      } else if args[pos] == name {
        if pos + 1 >= args.length() {
          Error(parse_error("missing value for " + name))
        } else {
          match on_match(args[pos + 1]) {
            Ok(commit) => Accept(consumed=2, commit~)
            Err(e) => Error(e)
          }
        }
      } else {
        Reject
      }
    },
    reset,
  }
}

///|
/// choices の各候補に対する consumed=2 の ExactNode（名前一致 + 値一致でのみ Accept）
fn make_choice_value_node(
  opt_name : String,
  choice : String,
  cell : Ref[String],
  initial_val : String,
) -> ExactNode {
  ExactNode::{
    name: opt_name,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_name {
        return Reject
      }
      if pos + 1 >= args.length() || args[pos + 1] != choice {
        return Reject
      }
      Accept(consumed=2, commit=fn() {
        cell.val = choice
      })
    },
    reset: fn() {
      cell.val = initial_val
    },
  }
}

///|
/// consumed=1 の implicit value ノード（名前マッチのみで Accept）
fn[T] make_implicit_flag_node(
  name : String,
  implicit : Lazy[T],
  cell : Ref[T],
  initial_val : T,
) -> ExactNode {
  ExactNode::{
    name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != name {
        return Reject
      }
      Accept(consumed=1, commit=fn() {
        cell.val = implicit.resolve()
      })
    },
    reset: fn() {
      cell.val = initial_val
    },
  }
}

///| implicit_value 共存時の any-string value node。

///|
/// 値が無い場合は Error ではなく Reject を返す（implicit node にフォールバックさせるため）
fn make_soft_value_node(
  name : String,
  cell : Ref[String],
  initial_val : String,
) -> ExactNode {
  ExactNode::{
    name,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != name {
        return Reject
      }
      if pos + 1 >= args.length() {
        return Reject // Error ではなく Reject（implicit にフォールバック）
      }
      let val = args[pos + 1]
      // 次の引数が -- で始まる場合もReject（implicit にフォールバック）
      // "-foo" や "-123" のような合法な値は通す
      if val.has_prefix("--") {
        return Reject
      }
      Accept(consumed=2, commit=fn() {
        cell.val = val
      })
    },
    reset: fn() {
      cell.val = initial_val
    },
  }
}

///|
/// 複数の子 ExactNode の最長一致で Accept を返すコンポジットノード
fn make_or_node(
  name : String,
  needs_value : Bool,
  children : Array[ExactNode],
) -> ExactNode {
  ExactNode::{
    name,
    needs_value,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      let mut best_consumed = 0
      let mut best_commit : (() -> Unit)? = None
      let mut ambiguous = false
      for child in children {
        match (child.try_reduce)(args, pos) {
          Accept(consumed~, commit~) =>
            if consumed > best_consumed {
              best_consumed = consumed
              best_commit = Some(commit)
              ambiguous = false
            } else if consumed == best_consumed && consumed > 0 {
              ambiguous = true
            }
          Error(e) => return Error(e)
          Reject => ()
        }
      }
      if ambiguous {
        return Error(
          parse_error(
            "ambiguous argument: " +
            (if pos < args.length() { args[pos] } else { "" }),
          ),
        )
      }
      match best_commit {
        Some(commit) => Accept(consumed=best_consumed, commit~)
        None => Reject
      }
    },
    reset: fn() {
      for child in children {
        (child.reset)()
      }
    },
  }
}

///|
/// reducer を ExactNode (値を受け取る) に変換するアダプタ
fn[T] make_reduced_value_node(
  name : String,
  reducer : (ReduceCtx[T]) -> T? raise ParseError,
  cell : Ref[T],
  pending : Ref[T],
  reset : () -> Unit,
) -> ExactNode {
  make_value_node(
    name,
    fn(s) {
      let ctx : ReduceCtx[T] = { current: cell.val, action: Value(Some(s)) }
      let r : Result[T?, ParseError] = try? reducer(ctx)
      match r {
        Ok(Some(v)) => {
          pending.val = v
          Ok(fn() { cell.val = pending.val })
        }
        Ok(None) =>
          Err(parse_error("unexpected: reducer returned None for Value"))
        Err(e) => Err(e)
      }
    },
    reset,
  )
}

