///|
pub fn Parser::new() -> Parser {
  let seq : Ref[Int] = { val: 0 }
  {
    next_id: fn() -> Int {
      let id = seq.val
      seq.val = id + 1
      id
    },
    nodes: [],
    global_nodes: [],
    positionals: [],
    current_positional: { val: 0 },
    force_positional: { val: false },
    parsed: { val: false },
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
          Error(ParseError("missing value for " + name))
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
) -> Opt[Bool] {
  let id = (self.next_id)()
  let cell : Ref[Bool] = { val: default }
  let initial_val = default
  let pending : Ref[Bool] = { val: default }
  let node = make_flag_node(
    "--" + name,
    fn() {
      pending.val = true
      fn() { cell.val = pending.val }
    },
    fn() { cell.val = initial_val },
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() {
      pending.val = false
      fn() { cell.val = pending.val }
    },
    fn() { cell.val = initial_val },
  )
  self.register_option(node, no_node, global)
  { id, getter: fn() -> Bool { cell.val } }
}

///|
pub fn Parser::string_opt(
  self : Parser,
  name~ : String,
  default~ : String,
  global? : Bool = false,
) -> Opt[String] {
  let id = (self.next_id)()
  let cell : Ref[String] = { val: default }
  let initial_val = default
  let pending : Ref[String] = { val: default }
  let node = make_value_node(
    "--" + name,
    fn(s) {
      pending.val = s
      Ok(fn() { cell.val = pending.val })
    },
    fn() { cell.val = initial_val },
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() {
      pending.val = initial_val
      fn() { cell.val = pending.val }
    },
    fn() { cell.val = initial_val },
  )
  self.register_option(node, no_node, global)
  { id, getter: fn() -> String { cell.val } }
}

///|
pub fn Parser::int_opt(
  self : Parser,
  name~ : String,
  default~ : Int,
  global? : Bool = false,
) -> Opt[Int] {
  let id = (self.next_id)()
  let cell : Ref[Int] = { val: default }
  let initial_val = default
  let opt_name = "--" + name
  let pending : Ref[Int] = { val: default }
  let node = make_value_node(
    opt_name,
    fn(s) {
      let r : Result[Int, _] = try? @strconv.parse_int(s.view())
      match r {
        Ok(v) => {
          pending.val = v
          Ok(fn() { cell.val = pending.val })
        }
        Err(_) =>
          Err(ParseError("invalid integer value for " + opt_name + ": " + s))
      }
    },
    fn() { cell.val = initial_val },
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() {
      pending.val = initial_val
      fn() { cell.val = pending.val }
    },
    fn() { cell.val = initial_val },
  )
  self.register_option(node, no_node, global)
  { id, getter: fn() -> Int { cell.val } }
}

///|
pub fn Parser::append_string(
  self : Parser,
  name~ : String,
  global? : Bool = false,
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  let node = make_value_node(
    "--" + name,
    fn(s) { Ok(fn() { cell.val.push(s) }) },
    fn() { cell.val = [] },
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() { fn() { cell.val = [] } },
    fn() { cell.val = [] },
  )
  self.register_option(node, no_node, global)
  { id, getter: fn() -> Array[String] { cell.val } }
}

///|
pub fn Parser::append_int(
  self : Parser,
  name~ : String,
  global? : Bool = false,
) -> Opt[Array[Int]] {
  let id = (self.next_id)()
  let cell : Ref[Array[Int]] = { val: [] }
  let opt_name = "--" + name
  let node = make_value_node(
    opt_name,
    fn(s) {
      let r : Result[Int, _] = try? @strconv.parse_int(s.view())
      match r {
        Ok(v) => Ok(fn() { cell.val.push(v) })
        Err(_) =>
          Err(ParseError("invalid integer value for " + opt_name + ": " + s))
      }
    },
    fn() { cell.val = [] },
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() { fn() { cell.val = [] } },
    fn() { cell.val = [] },
  )
  self.register_option(node, no_node, global)
  { id, getter: fn() -> Array[Int] { cell.val } }
}

///|
pub fn Parser::positional(self : Parser, name~ : String) -> Opt[String] {
  let id = (self.next_id)()
  let cell : Ref[String] = { val: "" }
  let pending : Ref[String] = { val: "" }
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
      Accept(consumed=1, commit=fn() { cell.val = pending.val })
    }
  }
  self.positionals.push((handler, false))
  { id, getter: fn() -> String { cell.val } }
}

///|
pub fn Parser::rest(self : Parser, name~ : String) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  ignore(name)
  let handler : (Array[String], Int) -> TryResult = fn(
    args : Array[String],
    pos : Int,
  ) -> TryResult {
    if pos >= args.length() {
      Reject
    } else if args[pos].has_prefix("--") && not(self.force_positional.val) {
      Reject
    } else {
      let value = args[pos]
      Accept(consumed=1, commit=fn() { cell.val.push(value) })
    }
  }
  self.positionals.push((handler, true))
  { id, getter: fn() -> Array[String] { cell.val } }
}

///|
pub fn Parser::cmd(
  self : Parser,
  name~ : String,
  setup~ : (Parser) -> Unit,
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
    force_positional: { val: false },
    parsed: { val: false },
  }
  setup(child)
  let cmd_name = name
  let node = ExactNode::{
    name: cmd_name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() {
        Reject
      } else if args[pos] == cmd_name {
        let rest_args = Array::from_iter(args.view(start=pos + 1).iter())
        let parse_result : Result[Unit, _] = try? child.parse(rest_args)
        match parse_result {
          Ok(_) =>
            Accept(consumed=args.length() - pos, commit=fn() { cell.val = true })
          Err(e) => Error(e)
        }
      } else {
        Reject
      }
    },
    reset: fn() { cell.val = false },
  }
  self.nodes.push(node)
  { id, getter: fn() -> Bool { cell.val } }
}

///|
pub fn[T] Parser::get(self : Parser, opt : Opt[T]) -> T? {
  if not(self.parsed.val) {
    None
  } else {
    Some((opt.getter)())
  }
}
