///|
/// Core primitive: creates a node that matches an exact literal string.
/// Consumes 1 argument with no value. The on_match factory returns a commit
/// callback that is invoked when the match is accepted.
/// DR-0061: exact(str) matches a literal, consuming 1 argument.
fn make_exact_node(
  name : String,
  on_match~ : () -> () -> Unit,
  reset~ : () -> Unit,
) -> ExactNode {
  make_flag_node(name, on_match, reset)
}

///|
/// Core primitive: creates an on_match callback for flag/count patterns.
/// OC phase: pending.val = transform(pending.val)
/// P phase (commit): cell.val = pending.val
fn[T] make_flag_on_match(
  pending : Ref[T],
  cell : Ref[T],
  transform : (T) -> T,
) -> () -> () -> Unit {
  fn() {
    pending.val = transform(pending.val)
    fn() { cell.val = pending.val }
  }
}

///|
/// Variant with explicit committed flag management (for variation nodes).
fn[T] make_flag_on_match_with_committed(
  pending : Ref[T],
  cell : Ref[T],
  committed : Ref[Bool],
  transform : (T) -> T,
  commit_flag : Bool,
) -> () -> () -> Unit {
  fn() {
    pending.val = transform(pending.val)
    fn() {
      cell.val = pending.val
      committed.val = commit_flag
    }
  }
}

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
/// Core primitive: creates a serial node that tries children in sequence.
/// All children must Accept for the serial node to Accept.
/// If any child Rejects, the entire serial node Rejects.
/// If any child returns Error, the serial node returns that Error immediately.
/// Commits are collected and executed together only when all children Accept.
/// DR-0061: serial([...]) = scope creation, process children in order.
fn make_serial_node(name : String, children : Array[ExactNode]) -> ExactNode {
  ExactNode::{
    name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      let mut total_consumed = 0
      let commits : Array[() -> Unit] = []
      for child in children {
        match (child.try_reduce)(args, pos + total_consumed) {
          Accept(consumed~, commit~) => {
            total_consumed += consumed
            commits.push(commit)
          }
          Reject => return Reject
          Error(e) => return Error(e)
        }
      }
      Accept(consumed=total_consumed, commit=fn() {
        for c in commits {
          c()
        }
      })
    },
    reset: fn() {
      for child in children {
        (child.reset)()
      }
    },
  }
}

///|
/// Core primitive: creates a rest node that consumes remaining arguments.
/// DR-0061: rest within serial scope, consumes args from current pos.
fn make_rest_node(
  on_commit~ : (Array[String]) -> Unit,
  reset~ : () -> Unit,
  stop_before? : Array[String] = [],
  stop_at_sep? : Bool = false,
  separator? : String = "--",
) -> ExactNode {
  ExactNode::{
    name: "...",
    needs_value: true,
    try_reduce: fn(args, pos) {
      let collected : Array[String] = []
      let mut i = pos
      while i < args.length() {
        let arg = args[i]
        if stop_at_sep && arg == separator {
          break
        }
        if stop_before.contains(arg) {
          break
        }
        collected.push(arg)
        i += 1
      }
      // 0個収集も Accept（dashdash の空グループに対応）
      Accept(consumed=collected.length(), commit=fn() { on_commit(collected) })
    },
    reset,
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
      try reducer(ctx) catch {
        e => Err(e)
      } noraise {
        Some(v) => {
          pending.val = v
          Ok(fn() { cell.val = pending.val })
        }
        None => Err(parse_error("unexpected: reducer returned None for Value"))
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
      try (pre.run)(s) catch {
        _ => Reject
      } noraise {
        v => Accept(consumed=2, commit=fn() { cell.val = v })
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
      try (pre.run)(choice) catch {
        e => Error(e)
      } noraise {
        v => Accept(consumed=2, commit=fn() { cell.val = v })
      }
    },
    reset: fn() { cell.val = initial_val },
  }
}
