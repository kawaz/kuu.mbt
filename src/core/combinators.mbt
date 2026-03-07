///|
fn parse_error(message : String) -> ParseError {
  ParseError(ParseErrorInfo::{ message, help_text: "" })
}

///|
/// ExactNode の commit (consumed > 0) を was_set フラグでラップする。
/// consumed=0 (デフォルトフォールバック) では was_set を true にしない。
fn wrap_node_with_set(node : ExactNode, was_set : Ref[Bool]) -> ExactNode {
  let orig_try_reduce = node.try_reduce
  let orig_reset = node.reset
  ExactNode::{
    name: node.name,
    needs_value: node.needs_value,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      match orig_try_reduce(args, pos) {
        Accept(consumed~, commit~) =>
          if consumed > 0 {
            Accept(consumed~, commit=fn() {
              commit()
              was_set.val = true
            })
          } else {
            Accept(consumed~, commit~)
          }
        other => other
      }
    },
    reset: fn() {
      orig_reset()
      was_set.val = false
    },
  }
}

///|
fn to_upper(s : String) -> String {
  let buf = StringBuilder::new()
  for c in s {
    if c >= 'a' && c <= 'z' {
      buf.write_char((c.to_int() - 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
pub fn Parser::set_description(self : Parser, desc : String) -> Unit {
  self.description.val = desc
}

///|
pub fn Parser::new(dashdash? : Bool = true) -> Parser {
  let seq : Ref[Int] = { val: 0 }
  let p : Parser = {
    next_id: fn() -> Int {
      let id = seq.val
      seq.val = id + 1
      id
    },
    nodes: [],
    global_nodes: [],
    positionals: [],
    current_positional: { val: 0 },
    parsed: { val: false },
    children: Map::new(),
    metas: [],
    description: { val: "" },
    post_hooks: [],
  }
  inject_help_node(p)
  if dashdash {
    p.install_separator_node()
  }
  p
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
  committed : Ref[Bool],
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
        committed.val = true
      })
    },
    reset: fn() {
      cell.val = initial_val
      committed.val = false
    },
  }
}

///|
/// consumed=1 の implicit value ノード（名前マッチのみで Accept）
fn[T] make_implicit_flag_node(
  name : String,
  implicit : Initial[T],
  cell : Ref[T],
  committed : Ref[Bool],
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
        committed.val = true
      })
    },
    reset: fn() {
      cell.val = initial_val
      committed.val = false
    },
  }
}

///| implicit_value 共存時の any-string value node。

///|
/// 値が無い場合は Error ではなく Reject を返す（implicit node にフォールバックさせるため）
fn make_soft_value_node(
  name : String,
  cell : Ref[String],
  committed : Ref[Bool],
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
        committed.val = true
      })
    },
    reset: fn() {
      cell.val = initial_val
      committed.val = false
    },
  }
}

///|
/// consumed=0 の default fallback ノード（finalize パスで commit）
fn[T] make_default_fallback_node(
  default_val : T,
  cell : Ref[T],
  committed : Ref[Bool],
  initial_val : T,
) -> ExactNode {
  ExactNode::{
    name: "",
    needs_value: false,
    try_reduce: fn(_args : Array[String], _pos : Int) -> TryResult {
      if committed.val {
        return Reject
      }
      Accept(consumed=0, commit=fn() { cell.val = default_val })
    },
    reset: fn() {
      cell.val = initial_val
      committed.val = false
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
fn Parser::register_option(
  self : Parser,
  node : ExactNode,
  no_node : ExactNode,
  global : Bool,
) -> Unit {
  self.nodes.push(node)
  self.nodes.push(no_node)
  if global {
    self.global_nodes.push(node)
    self.global_nodes.push(no_node)
  }
}

///|
pub fn Parser::flag(
  self : Parser,
  name~ : String,
  default? : Bool = false,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
  description? : String = "",
  hidden? : Bool = false,
) -> Opt[Bool] {
  let id = (self.next_id)()
  let cell : Ref[Bool] = { val: default }
  let initial_val = default
  let pending : Ref[Bool] = { val: default }
  let was_set : Ref[Bool] = { val: false }
  let node = make_flag_node(
    "--" + name,
    fn() {
      pending.val = true
      fn() {
        cell.val = pending.val
        was_set.val = true
      }
    },
    fn() {
      cell.val = initial_val
      was_set.val = false
    },
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() {
      pending.val = false
      fn() {
        cell.val = pending.val
        was_set.val = true
      }
    },
    fn() {
      cell.val = initial_val
      was_set.val = false
    },
  )
  self.register_option(node, no_node, global)
  for alt in aliases {
    let alt_node = make_flag_node(
      "--" + alt,
      fn() {
        pending.val = true
        fn() {
          cell.val = pending.val
          was_set.val = true
        }
      },
      fn() {
        cell.val = initial_val
        was_set.val = false
      },
    )
    let alt_no_node = make_flag_node(
      "--no-" + alt,
      fn() {
        pending.val = false
        fn() {
          cell.val = pending.val
          was_set.val = true
        }
      },
      fn() {
        cell.val = initial_val
        was_set.val = false
      },
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_node = make_flag_node(
      short_name,
      fn() {
        pending.val = true
        fn() {
          cell.val = pending.val
          was_set.val = true
        }
      },
      fn() {
        cell.val = initial_val
        was_set.val = false
      },
    )
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  self.metas.push(OptMeta::{
    kind: Flag,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Bool { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn[T] Opt::get(self : Opt[T]) -> T? {
  if self.parsed.val {
    Some((self.getter)())
  } else {
    None
  }
}

///|
pub fn Parser::string_opt(
  self : Parser,
  name~ : String,
  default~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
  post? : FilterChain[String, String]? = None,
  choices? : Array[String] = [],
  implicit_value? : Initial[String]? = None,
) -> Opt[String] {
  let id = (self.next_id)()
  let cell : Ref[String] = { val: default }
  let initial_val = default
  let opt_name = "--" + name
  let has_choices = choices.length() > 0
  let has_implicit = match implicit_value {
    Some(_) => true
    None => false
  }
  let was_set : Ref[Bool] = { val: false }
  // ノードを self.nodes (と global_nodes) に登録するヘルパー。was_set ラップ付き。
  fn push_node(node : ExactNode, is_global : Bool) {
    let wrapped = wrap_node_with_set(node, was_set)
    self.nodes.push(wrapped)
    if is_global {
      self.global_nodes.push(wrapped)
    }
  }

  // ケース1,3: choices+implicit or implicit only → committed ベースの展開
  // ケース2: choices only → reducer + one_of バリデーション
  // ケース4: 既存パス (neither)
  if has_implicit {
    // ケース1 or ケース3: committed ベース
    let committed : Ref[Bool] = { val: false }
    let iv = match implicit_value {
      Some(v) => v
      None => Val(default) // unreachable だが型システムのため
    }
    // ノード登録用ヘルパー（長オプション名ごとに composite node を作って push）
    // is_main: メインの opt_name の場合 true（default fallback を含める）
    fn register_long(opt_n : String, is_main : Bool) {
      let children : Array[ExactNode] = []
      if has_choices {
        for choice in choices {
          children.push(
            make_choice_value_node(opt_n, choice, cell, committed, initial_val),
          )
        }
      } else {
        children.push(make_soft_value_node(opt_n, cell, committed, initial_val))
      }
      children.push(
        make_implicit_flag_node(opt_n, iv, cell, committed, initial_val),
      )
      if is_main {
        children.push(
          make_default_fallback_node(default, cell, committed, initial_val),
        )
      }
      let composite = make_or_node(opt_n, true, children)
      push_node(composite, global)
      // negate node: --no-{name} は composite の外（名前が異なるため）
      let no_name = if opt_n.has_prefix("--") {
        "--no-" + opt_n.unsafe_substring(start=2, end=opt_n.length())
      } else {
        "--no-" + opt_n
      }
      let no_node = make_flag_node(
        no_name,
        fn() {
          fn() {
            cell.val = initial_val
            committed.val = true
          }
        },
        fn() {
          cell.val = initial_val
          committed.val = false
        },
      )
      push_node(no_node, global)
    }

    // メインの opt_name（default fallback を含む）
    register_long(opt_name, true)
    // aliases（default fallback は含めない）
    for alt in aliases {
      register_long("--" + alt, false)
    }
    // short option: 個別ノードをそのまま登録（composite にしない）
    if short != '\u0000' {
      let short_name = "-" + short.to_string()
      if has_choices {
        for choice in choices {
          let node = make_choice_value_node(
            short_name, choice, cell, committed, initial_val,
          )
          push_node(node, global)
        }
      } else {
        let node = make_soft_value_node(
          short_name, cell, committed, initial_val,
        )
        push_node(node, global)
      }
      let imp_node = make_implicit_flag_node(
        short_name, iv, cell, committed, initial_val,
      )
      push_node(imp_node, global)
    }
  } else if has_choices {
    // ケース2: choices only → 既存パス + one_of バリデーション
    let pending : Ref[String] = { val: default }
    let reset = fn() { cell.val = initial_val }
    let accum : Accumulator[String, String] = fn(_current, piece) { piece }
    let one_of_pre : FilterChain[String, String] = Filter::one_of(choices)
    let reducer = make_reducer(one_of_pre, accum, initial_val)
    let node = wrap_node_with_set(
      make_reduced_value_node(opt_name, reducer, cell, pending, reset),
      was_set,
    )
    let no_node = wrap_node_with_set(
      make_reduced_negate_node("--no-" + name, reducer, cell, pending, reset),
      was_set,
    )
    self.register_option(node, no_node, global)
    for alt in aliases {
      let alt_opt_name = "--" + alt
      let alt_node = wrap_node_with_set(
        make_reduced_value_node(alt_opt_name, reducer, cell, pending, reset),
        was_set,
      )
      let alt_no_node = wrap_node_with_set(
        make_reduced_negate_node("--no-" + alt, reducer, cell, pending, reset),
        was_set,
      )
      self.register_option(alt_node, alt_no_node, global)
    }
    if short != '\u0000' {
      let short_name = "-" + short.to_string()
      let short_node = wrap_node_with_set(
        make_reduced_value_node(short_name, reducer, cell, pending, reset),
        was_set,
      )
      self.nodes.push(short_node)
      if global {
        self.global_nodes.push(short_node)
      }
    }
  } else {
    // ケース4: 既存パス (choices 空 + implicit_value なし)
    let pending : Ref[String] = { val: default }
    let reset = fn() { cell.val = initial_val }
    let accum : Accumulator[String, String] = fn(_current, piece) { piece }
    let identity_pre : FilterChain[String, String] = Filter::map(fn(s) { s })
    let reducer = make_reducer(identity_pre, accum, initial_val)
    let node = wrap_node_with_set(
      make_reduced_value_node(opt_name, reducer, cell, pending, reset),
      was_set,
    )
    let no_node = wrap_node_with_set(
      make_reduced_negate_node("--no-" + name, reducer, cell, pending, reset),
      was_set,
    )
    self.register_option(node, no_node, global)
    for alt in aliases {
      let alt_opt_name = "--" + alt
      let alt_node = wrap_node_with_set(
        make_reduced_value_node(alt_opt_name, reducer, cell, pending, reset),
        was_set,
      )
      let alt_no_node = wrap_node_with_set(
        make_reduced_negate_node("--no-" + alt, reducer, cell, pending, reset),
        was_set,
      )
      self.register_option(alt_node, alt_no_node, global)
    }
    if short != '\u0000' {
      let short_name = "-" + short.to_string()
      let short_node = wrap_node_with_set(
        make_reduced_value_node(short_name, reducer, cell, pending, reset),
        was_set,
      )
      self.nodes.push(short_node)
      if global {
        self.global_nodes.push(short_node)
      }
    }
  }
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  let display_default = if default == "" { "" } else { default }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: display_default,
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  match post {
    Some(filter) =>
      self.post_hooks.push(fn() raise ParseError {
        cell.val = (filter.run)(cell.val)
      })
    None => ()
  }
  {
    id,
    name: "--" + name,
    getter: fn() -> String { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
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
/// reducer を ExactNode (negate) に変換するアダプタ
fn[T] make_reduced_negate_node(
  name : String,
  reducer : (ReduceCtx[T]) -> T? raise ParseError,
  cell : Ref[T],
  pending : Ref[T],
  reset : () -> Unit,
) -> ExactNode {
  // make_flag_node は commit を返す () -> () -> Unit 型だが、
  // reducer は raise ParseError を含むため直接 ExactNode を構築する
  ExactNode::{
    name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != name {
        return Reject
      }
      let ctx : ReduceCtx[T] = { current: cell.val, action: Negate }
      let r : Result[T?, ParseError] = try? reducer(ctx)
      match r {
        Ok(Some(v)) => {
          pending.val = v
          Accept(consumed=1, commit=fn() { cell.val = pending.val })
        }
        Ok(None) =>
          Error(parse_error("unexpected: negate reducer failed for " + name))
        Err(e) => Error(e)
      }
    },
    reset,
  }
}

///|
pub fn Parser::int_opt(
  self : Parser,
  name~ : String,
  default~ : Int,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
  implicit_value? : Initial[Int]? = None,
) -> Opt[Int] {
  let id = (self.next_id)()
  let cell : Ref[Int] = { val: default }
  let initial_val = default
  let opt_name = "--" + name
  let has_implicit = match implicit_value {
    Some(_) => true
    None => false
  }
  let was_set : Ref[Bool] = { val: false }
  fn push_node(node : ExactNode, is_global : Bool) {
    let wrapped = wrap_node_with_set(node, was_set)
    self.nodes.push(wrapped)
    if is_global {
      self.global_nodes.push(wrapped)
    }
  }

  if has_implicit {
    // implicit_value あり: committed ベースの展開
    let committed : Ref[Bool] = { val: false }
    let iv = match implicit_value {
      Some(v) => v
      None => Val(default) // unreachable
    }
    // int パースを試み、失敗時は Reject を返す soft value node
    fn make_soft_int_value_node(
      opt_n : String,
      cell : Ref[Int],
      committed : Ref[Bool],
      initial_val : Int,
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
          let r : Result[Int, _] = try? @strconv.parse_int(s.view())
          match r {
            Ok(v) =>
              Accept(consumed=2, commit=fn() {
                cell.val = v
                committed.val = true
              })
            Err(_) => Reject // int パース失敗 → Reject（implicit にフォールバック）
          }
        },
        reset: fn() {
          cell.val = initial_val
          committed.val = false
        },
      }
    }

    // is_main: メインの opt_name の場合 true（default fallback を含める）
    fn register_long_int(opt_n : String, is_main : Bool) {
      let children : Array[ExactNode] = []
      children.push(
        make_soft_int_value_node(opt_n, cell, committed, initial_val),
      )
      children.push(
        make_implicit_flag_node(opt_n, iv, cell, committed, initial_val),
      )
      if is_main {
        children.push(
          make_default_fallback_node(default, cell, committed, initial_val),
        )
      }
      let composite = make_or_node(opt_n, true, children)
      push_node(composite, global)
      // negate node: composite の外
      let no_name = if opt_n.has_prefix("--") {
        "--no-" + opt_n.unsafe_substring(start=2, end=opt_n.length())
      } else {
        "--no-" + opt_n
      }
      let no_node = make_flag_node(
        no_name,
        fn() {
          fn() {
            cell.val = initial_val
            committed.val = true
          }
        },
        fn() {
          cell.val = initial_val
          committed.val = false
        },
      )
      push_node(no_node, global)
    }

    register_long_int(opt_name, true)
    for alt in aliases {
      register_long_int("--" + alt, false)
    }
    // short option: 個別ノードをそのまま登録（composite にしない）
    if short != '\u0000' {
      let short_name = "-" + short.to_string()
      let node = make_soft_int_value_node(
        short_name, cell, committed, initial_val,
      )
      push_node(node, global)
      let imp_node = make_implicit_flag_node(
        short_name, iv, cell, committed, initial_val,
      )
      push_node(imp_node, global)
    }
  } else {
    // implicit_value なし: 既存パス
    let pending : Ref[Int] = { val: default }
    let reset = fn() { cell.val = initial_val }
    let accum : Accumulator[Int, Int] = fn(_current, piece) { piece }
    fn make_int_pre(opt_name : String) -> FilterChain[String, Int] {
      Filter::parse(fn(s) raise ParseError {
        let r : Result[Int, _] = try? @strconv.parse_int(s.view())
        match r {
          Ok(v) => v
          Err(_) =>
            raise parse_error(
              "invalid integer value for " + opt_name + ": " + s,
            )
        }
      })
    }

    let reducer = make_reducer(make_int_pre(opt_name), accum, initial_val)
    let node = wrap_node_with_set(
      make_reduced_value_node(opt_name, reducer, cell, pending, reset),
      was_set,
    )
    let no_node = wrap_node_with_set(
      make_reduced_negate_node("--no-" + name, reducer, cell, pending, reset),
      was_set,
    )
    self.register_option(node, no_node, global)
    for alt in aliases {
      let alt_opt_name = "--" + alt
      let alt_reducer = make_reducer(
        make_int_pre(alt_opt_name),
        accum,
        initial_val,
      )
      let alt_node = wrap_node_with_set(
        make_reduced_value_node(alt_opt_name, alt_reducer, cell, pending, reset),
        was_set,
      )
      let alt_no_node = wrap_node_with_set(
        make_reduced_negate_node(
          "--no-" + alt,
          alt_reducer,
          cell,
          pending,
          reset,
        ),
        was_set,
      )
      self.register_option(alt_node, alt_no_node, global)
    }
    if short != '\u0000' {
      let short_name = "-" + short.to_string()
      let short_reducer = make_reducer(
        make_int_pre(short_name),
        accum,
        initial_val,
      )
      let short_node = wrap_node_with_set(
        make_reduced_value_node(short_name, short_reducer, cell, pending, reset),
        was_set,
      )
      self.nodes.push(short_node)
      if global {
        self.global_nodes.push(short_node)
      }
    }
  }
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  let display_default = if default == 0 { "" } else { default.to_string() }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: display_default,
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Int { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::append_string(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  let was_set : Ref[Bool] = { val: false }
  let node = wrap_node_with_set(
    make_value_node("--" + name, fn(s) { Ok(fn() { cell.val.push(s) }) }, fn() {
      cell.val = []
    }),
    was_set,
  )
  let no_node = wrap_node_with_set(
    make_flag_node("--no-" + name, fn() { fn() { cell.val = [] } }, fn() {
      cell.val = []
    }),
    was_set,
  )
  self.register_option(node, no_node, global)
  for alt in aliases {
    let alt_node = wrap_node_with_set(
      make_value_node("--" + alt, fn(s) { Ok(fn() { cell.val.push(s) }) }, fn() {
        cell.val = []
      }),
      was_set,
    )
    let alt_no_node = wrap_node_with_set(
      make_flag_node("--no-" + alt, fn() { fn() { cell.val = [] } }, fn() {
        cell.val = []
      }),
      was_set,
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_node = wrap_node_with_set(
      make_value_node(short_name, fn(s) { Ok(fn() { cell.val.push(s) }) }, fn() {
        cell.val = []
      }),
      was_set,
    )
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Array[String] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::append_int(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
) -> Opt[Array[Int]] {
  let id = (self.next_id)()
  let cell : Ref[Array[Int]] = { val: [] }
  let opt_name = "--" + name
  let was_set : Ref[Bool] = { val: false }
  let node = wrap_node_with_set(
    make_value_node(
      opt_name,
      fn(s) {
        let r : Result[Int, _] = try? @strconv.parse_int(s.view())
        match r {
          Ok(v) => Ok(fn() { cell.val.push(v) })
          Err(_) =>
            Err(parse_error("invalid integer value for " + opt_name + ": " + s))
        }
      },
      fn() { cell.val = [] },
    ),
    was_set,
  )
  let no_node = wrap_node_with_set(
    make_flag_node("--no-" + name, fn() { fn() { cell.val = [] } }, fn() {
      cell.val = []
    }),
    was_set,
  )
  self.register_option(node, no_node, global)
  for alt in aliases {
    let alt_opt_name = "--" + alt
    let alt_node = wrap_node_with_set(
      make_value_node(
        alt_opt_name,
        fn(s) {
          let r : Result[Int, _] = try? @strconv.parse_int(s.view())
          match r {
            Ok(v) => Ok(fn() { cell.val.push(v) })
            Err(_) =>
              Err(
                parse_error(
                  "invalid integer value for " + alt_opt_name + ": " + s,
                ),
              )
          }
        },
        fn() { cell.val = [] },
      ),
      was_set,
    )
    let alt_no_node = wrap_node_with_set(
      make_flag_node("--no-" + alt, fn() { fn() { cell.val = [] } }, fn() {
        cell.val = []
      }),
      was_set,
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_opt_name = short_name
    let short_node = wrap_node_with_set(
      make_value_node(
        short_name,
        fn(s) {
          let r : Result[Int, _] = try? @strconv.parse_int(s.view())
          match r {
            Ok(v) => Ok(fn() { cell.val.push(v) })
            Err(_) =>
              Err(
                parse_error(
                  "invalid integer value for " + short_opt_name + ": " + s,
                ),
              )
          }
        },
        fn() { cell.val = [] },
      ),
      was_set,
    )
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Array[Int] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::count(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
  description? : String = "",
  hidden? : Bool = false,
) -> Opt[Int] {
  let id = (self.next_id)()
  let cell : Ref[Int] = { val: 0 }
  let pending : Ref[Int] = { val: 0 }
  let was_set : Ref[Bool] = { val: false }
  let reset = fn() {
    cell.val = 0
    pending.val = 0
  }
  let node = wrap_node_with_set(
    make_flag_node(
      "--" + name,
      fn() {
        pending.val = pending.val + 1
        fn() { cell.val = pending.val }
      },
      reset,
    ),
    was_set,
  )
  let no_node = wrap_node_with_set(
    make_flag_node(
      "--no-" + name,
      fn() {
        pending.val = 0
        fn() { cell.val = pending.val }
      },
      reset,
    ),
    was_set,
  )
  self.register_option(node, no_node, global)
  // aliases
  for alt in aliases {
    let alt_node = wrap_node_with_set(
      make_flag_node(
        "--" + alt,
        fn() {
          pending.val = pending.val + 1
          fn() { cell.val = pending.val }
        },
        reset,
      ),
      was_set,
    )
    let alt_no_node = wrap_node_with_set(
      make_flag_node(
        "--no-" + alt,
        fn() {
          pending.val = 0
          fn() { cell.val = pending.val }
        },
        reset,
      ),
      was_set,
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  // short option
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_node = wrap_node_with_set(
      make_flag_node(
        short_name,
        fn() {
          pending.val = pending.val + 1
          fn() { cell.val = pending.val }
        },
        reset,
      ),
      was_set,
    )
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  self.metas.push(OptMeta::{
    kind: Flag,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Int { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::positional(
  self : Parser,
  name~ : String,
  description? : String = "",
) -> Opt[String] {
  let id = (self.next_id)()
  let cell : Ref[String] = { val: "" }
  let pending : Ref[String] = { val: "" }
  let was_set : Ref[Bool] = { val: false }
  ignore(name)
  let handler : (Array[String], Int) -> TryResult = fn(
    args : Array[String],
    pos : Int,
  ) -> TryResult {
    if pos >= args.length() {
      Reject
    } else if args[pos].has_prefix("--") {
      Reject
    } else {
      pending.val = args[pos]
      Accept(consumed=1, commit=fn() {
        cell.val = pending.val
        was_set.val = true
      })
    }
  }
  self.positionals.push((handler, false))
  self.metas.push(OptMeta::{
    kind: Positional,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global: false,
    short: None,
    aliases: [],
    hidden: false,
  })
  {
    id,
    name,
    getter: fn() -> String { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::rest(
  self : Parser,
  name~ : String,
  description? : String = "",
  stop_before? : Array[String] = [],
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  let was_set : Ref[Bool] = { val: false }
  ignore(name)
  let stop = stop_before
  let handler : (Array[String], Int) -> TryResult = fn(
    args : Array[String],
    pos : Int,
  ) -> TryResult {
    if pos >= args.length() {
      Reject
    } else {
      let value = args[pos]
      for token in stop {
        if value == token {
          return Reject
        }
      }
      Accept(consumed=1, commit=fn() {
        cell.val.push(value)
        was_set.val = true
      })
    }
  }
  self.positionals.push((handler, true))
  self.metas.push(OptMeta::{
    kind: Rest,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global: false,
    short: None,
    aliases: [],
    hidden: false,
  })
  {
    id,
    name,
    getter: fn() -> Array[String] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::never(self : Parser) -> Unit {
  let handler : (Array[String], Int) -> TryResult = fn(args, pos) {
    if pos < args.length() {
      Error(parse_error("unexpected argument: " + args[pos]))
    } else {
      Reject
    }
  }
  self.positionals.push((handler, false))
}

///|
pub fn Parser::serial(self : Parser, setup~ : (Parser) -> Unit) -> Unit {
  // serial 用の軽量 sub-parser を直接構築（Parser::new は --help 等を登録してしまうため）
  let sub : Parser = {
    next_id: self.next_id, // 親と ID 空間共有
    nodes: [],
    global_nodes: [],
    positionals: [],
    current_positional: { val: 0 },
    parsed: self.parsed, // 親と parsed 共有
    children: Map::new(),
    metas: [],
    description: { val: "" },
    post_hooks: [],
  }
  setup(sub)
  // sub.positionals を greedy な compound handler にまとめる。
  // 1回の呼び出しで sub 内の全 positional を可能な限り消費する。
  let sub_positionals = sub.positionals
  let sub_current : Ref[Int] = { val: 0 }
  let handler : (Array[String], Int) -> TryResult = fn(args, pos) {
    if sub_current.val >= sub_positionals.length() {
      return Reject
    }
    let mut p = pos
    let commits : Array[() -> Unit] = []
    let mut next_pos_idx = sub_current.val
    while p < args.length() && next_pos_idx < sub_positionals.length() {
      let (sub_handler, is_rest) = sub_positionals[next_pos_idx]
      match sub_handler(args, p) {
        Accept(consumed~, commit~) => {
          commits.push(commit)
          if not(is_rest) {
            next_pos_idx += 1
          }
          p += consumed
        }
        Reject => break
        Error(e) => return Error(e)
      }
    }
    if p == pos {
      // 1つも消費できなかった
      return Reject
    }
    let final_pos_idx = next_pos_idx
    Accept(consumed=p - pos, commit=fn() {
      for c in commits {
        c()
      }
      sub_current.val = final_pos_idx
    })
  }
  // sub の中に rest がある場合、serial 全体を is_rest=true にする
  // （rest がなくても serial は greedy に全消費するので通常 is_rest=false でよい）
  let has_rest = sub_positionals.length() > 0 &&
    sub_positionals[sub_positionals.length() - 1].1
  self.positionals.push((handler, has_rest))
}

///|
pub fn Parser::cmd(
  self : Parser,
  name~ : String,
  setup~ : (Parser) -> Unit,
  description? : String = "",
  dashdash? : Bool = true,
) -> Opt[Bool] {
  let id = (self.next_id)()
  let cell : Ref[Bool] = { val: false }
  let child_nodes : Array[ExactNode] = []
  let child_global_nodes : Array[ExactNode] = []
  for gnode in self.global_nodes {
    child_nodes.push(gnode)
    child_global_nodes.push(gnode)
  }
  let child : Parser = {
    next_id: self.next_id,
    nodes: child_nodes,
    global_nodes: child_global_nodes,
    positionals: [],
    current_positional: { val: 0 },
    parsed: { val: false },
    children: Map::new(),
    metas: [],
    description: { val: "" },
    post_hooks: [],
  }
  setup(child)
  inject_help_node(child)
  if dashdash {
    child.install_separator_node()
  }
  let cmd_name = name
  let was_set : Ref[Bool] = { val: false }
  let node = ExactNode::{
    name: cmd_name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() {
        Reject
      } else if args[pos] == cmd_name {
        let rest_args = Array::from_iter(args.view(start=pos + 1).iter())
        let parse_result : Result[ParseResult, ParseError] = try? child.parse(
          rest_args,
        )
        match parse_result {
          Ok(child_result) =>
            Accept(consumed=args.length() - pos, commit=fn() {
              cell.val = true
              was_set.val = true
              self.children.set(cmd_name, child_result)
            })
          Err(e) => Error(e)
        }
      } else {
        Reject
      }
    },
    reset: fn() {
      cell.val = false
      was_set.val = false
    },
  }
  self.nodes.push(node)
  self.metas.push(OptMeta::{
    kind: Command,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global: false,
    short: None,
    aliases: [],
    hidden: false,
  })
  {
    id,
    name,
    getter: fn() -> Bool { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::dashdash(
  self : Parser,
  separator? : String = "--",
  stop_before? : Array[String] = [],
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  let sep = separator
  let stop = stop_before
  let was_set : Ref[Bool] = { val: false }
  let dashdash_node = ExactNode::{
    name: sep,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != sep {
        return Reject
      }
      // セパレータ以降の全 args を収集
      let collected : Array[String] = []
      let mut p = pos + 1
      while p < args.length() {
        let mut should_stop = false
        for token in stop {
          if args[p] == token {
            should_stop = true
            break
          }
        }
        if should_stop {
          break
        }
        collected.push(args[p])
        p += 1
      }
      Accept(consumed=p - pos, commit=fn() {
        for v in collected {
          cell.val.push(v)
        }
        was_set.val = true
      })
    },
    reset: fn() {
      cell.val = []
      was_set.val = false
    },
  }
  self.nodes.push(dashdash_node)
  {
    id,
    name: separator,
    getter: fn() -> Array[String] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::append_dashdash(
  self : Parser,
  separator? : String = "--",
  stop_before? : Array[String] = [],
) -> Opt[Array[Array[String]]] {
  let id = (self.next_id)()
  let cell : Ref[Array[Array[String]]] = { val: [] }
  let sep = separator
  let stop = stop_before
  let was_set : Ref[Bool] = { val: false }
  let node = ExactNode::{
    name: sep,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != sep {
        return Reject
      }
      let group : Array[String] = []
      let mut p = pos + 1
      while p < args.length() {
        if args[p] == sep {
          break
        }
        let mut should_stop = false
        for token in stop {
          if args[p] == token {
            should_stop = true
            break
          }
        }
        if should_stop {
          break
        }
        group.push(args[p])
        p += 1
      }
      Accept(consumed=p - pos, commit=fn() {
        cell.val.push(group)
        was_set.val = true
      })
    },
    reset: fn() {
      cell.val = []
      was_set.val = false
    },
  }
  self.nodes.push(node)
  {
    id,
    name: separator,
    getter: fn() -> Array[Array[String]] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::exclusive(self : Parser, opts : Array[OptRef]) -> Unit {
  let refs = opts
  self.post_hooks.push(fn() raise ParseError {
    let set_names : Array[String] = []
    for opt_ref in refs {
      if (opt_ref.is_set)() {
        set_names.push(opt_ref.name)
      }
    }
    if set_names.length() > 1 {
      raise parse_error("mutually exclusive options: " + set_names.join(", "))
    }
  })
}

///|
pub fn Parser::required(self : Parser, opt : OptRef) -> Unit {
  let opt_ref = opt
  self.post_hooks.push(fn() raise ParseError {
    if not((opt_ref.is_set)()) {
      raise parse_error("required option missing: " + opt_ref.name)
    }
  })
}

///|
pub fn ParseResult::as_map(self : ParseResult) -> Map[String, ParseResult]? {
  match self.kind {
    Map_(m) => Some(m)
    _ => None
  }
}

///|
pub fn ParseResult::as_list(self : ParseResult) -> Array[ParseResult]? {
  match self.kind {
    List_(l) => Some(l)
    _ => None
  }
}

///|
pub fn ParseResult::child(self : ParseResult, key : String) -> ParseResult? {
  match self.kind {
    Map_(m) => m.get(key)
    _ => None
  }
}

///|
pub fn ParseResult::at(self : ParseResult, index : Int) -> ParseResult? {
  match self.kind {
    List_(l) =>
      if index >= 0 && index < l.length() {
        Some(l[index])
      } else {
        None
      }
    _ => None
  }
}

///|
pub fn[T] ParseResult::get(self : ParseResult, opt : Opt[T]) -> T? {
  self.parser.get(opt)
}

///|
pub fn[T] Parser::get(self : Parser, opt : Opt[T]) -> T? {
  if not(self.parsed.val) {
    None
  } else {
    Some((opt.getter)())
  }
}
