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
          Error(
            parse_error(
              "missing value for " + name,
              kind=MissingValue,
              opt_name=name,
            ),
          )
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
      Accept(consumed=1, commit=fn() { cell.val = implicit.resolve() })
    },
    reset: fn() { cell.val = initial_val },
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
            kind=AmbiguousMatch,
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
/// 各コンビネータに散在する variation 展開ロジックの統一関数。
/// opt_name から base を抽出し、各 Variation のプレフィックスと組み合わせて
/// "--{prefix}-{base}" の名前を生成し、コールバックで ExactNode を生成して push する。
fn expand_variation_nodes(
  opt_name : String,
  variations : Array[Variation],
  nodes : Array[ExactNode],
  make_node_for_variation : (String, Variation) -> ExactNode,
) -> Unit {
  let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
  for v in variations {
    let prefix = match v {
      Toggle(p) | True(p) | False(p) | Reset(p) | Unset(p) => p
    }
    let vn = "--" + prefix + "-" + base
    nodes.push(make_node_for_variation(vn, v))
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

///|
/// implicit_value 共存時の汎用 soft value node。
/// pre で String→T 変換を試み、失敗時は Reject（implicit にフォールバック）
fn[T] make_soft_custom_value_node(
  opt_n : String,
  pre : FilterChain[String, T],
  cell : Ref[T],
  initial_val : T,
) -> ExactNode {
  ExactNode::{
    name: opt_n,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_n {
        return Reject
      }
      if pos + 1 >= args.length() {
        return Reject
      }
      let s = args[pos + 1]
      if s.has_prefix("--") {
        return Reject
      }
      let r : Result[T, ParseError] = try? (pre.run)(s)
      match r {
        Ok(v) => Accept(consumed=2, commit=fn() { cell.val = v })
        Err(_) => Reject
      }
    },
    reset: fn() { cell.val = initial_val },
  }
}

///|
/// choices + implicit_value 共存時のノード。raw string の choice 値にマッチ → pre で T に変換
fn[T] make_custom_choice_value_node(
  opt_name : String,
  choice : String,
  pre : FilterChain[String, T],
  cell : Ref[T],
  initial_val : T,
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
      let r : Result[T, ParseError] = try? (pre.run)(choice)
      match r {
        Ok(v) => Accept(consumed=2, commit=fn() { cell.val = v })
        Err(e) => Error(e)
      }
    },
    reset: fn() { cell.val = initial_val },
  }
}
