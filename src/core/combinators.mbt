///|
fn parse_error(message : String) -> ParseError {
  ParseError(ParseErrorInfo::{ message, help_text: "" })
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
pub fn Parser::new() -> Parser {
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
  }
  inject_help_node(p)
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
  for alt in aliases {
    let alt_node = make_flag_node(
      "--" + alt,
      fn() {
        pending.val = true
        fn() { cell.val = pending.val }
      },
      fn() { cell.val = initial_val },
    )
    let alt_no_node = make_flag_node(
      "--no-" + alt,
      fn() {
        pending.val = false
        fn() { cell.val = pending.val }
      },
      fn() { cell.val = initial_val },
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_node = make_flag_node(
      short_name,
      fn() {
        pending.val = true
        fn() { cell.val = pending.val }
      },
      fn() { cell.val = initial_val },
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
    short: if short != '\u0000' { Some(short) } else { None },
    aliases,
    hidden,
  })
  { id, getter: fn() -> Bool { cell.val }, parsed: self.parsed }
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
) -> Opt[String] {
  let id = (self.next_id)()
  let cell : Ref[String] = { val: default }
  let initial_val = default
  let pending : Ref[String] = { val: default }
  let reset = fn() { cell.val = initial_val }
  let accum : Accumulator[String, String] = fn(_current, piece) { piece }
  let identity_pre : FilterChain[String, String] = Filter::map(fn(s) { s })
  let reducer = make_reducer(identity_pre, accum, initial_val)
  let opt_name = "--" + name
  let node = make_reduced_value_node(opt_name, reducer, cell, pending, reset)
  let no_node = make_reduced_negate_node("--no-" + name, reducer, cell, pending, reset)
  self.register_option(node, no_node, global)
  for alt in aliases {
    let alt_opt_name = "--" + alt
    let alt_node = make_reduced_value_node(alt_opt_name, reducer, cell, pending, reset)
    let alt_no_node = make_reduced_negate_node("--no-" + alt, reducer, cell, pending, reset)
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_node = make_reduced_value_node(short_name, reducer, cell, pending, reset)
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  let display_value_name = if value_name == "" { to_upper(name) } else { value_name }
  let display_default = if default == "" { "" } else { default }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: display_default,
    global,
    short: if short != '\u0000' { Some(short) } else { None },
    aliases,
    hidden,
  })
  { id, getter: fn() -> String { cell.val }, parsed: self.parsed }
}

///| reducer を ExactNode (値を受け取る) に変換するアダプタ
fn[T] make_reduced_value_node(
  name : String,
  reducer : (ReduceCtx[T]) -> T? raise ParseError,
  cell : Ref[T],
  pending : Ref[T],
  reset : () -> Unit,
) -> ExactNode {
  make_value_node(name, fn(s) {
    let ctx : ReduceCtx[T] = { current: cell.val, action: Value(Some(s)) }
    let r : Result[T?, ParseError] = try? reducer(ctx)
    match r {
      Ok(Some(v)) => { pending.val = v; Ok(fn() { cell.val = pending.val }) }
      Ok(None) => Err(parse_error("unexpected: reducer returned None for Value"))
      Err(e) => Err(e)
    }
  }, reset)
}

///| reducer を ExactNode (negate) に変換するアダプタ
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
    name, needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != name { return Reject }
      let ctx : ReduceCtx[T] = { current: cell.val, action: Negate }
      let r : Result[T?, ParseError] = try? reducer(ctx)
      match r {
        Ok(Some(v)) => { pending.val = v; Accept(consumed=1, commit=fn() { cell.val = pending.val }) }
        Ok(None) => Error(parse_error("unexpected: negate reducer failed for " + name))
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
) -> Opt[Int] {
  let id = (self.next_id)()
  let cell : Ref[Int] = { val: default }
  let initial_val = default
  let pending : Ref[Int] = { val: default }
  let reset = fn() { cell.val = initial_val }
  let accum : Accumulator[Int, Int] = fn(_current, piece) { piece }
  // オプション名を含むエラーメッセージ用の FilterChain を生成するヘルパー
  fn make_int_pre(opt_name : String) -> FilterChain[String, Int] {
    Filter::parse(fn(s) raise ParseError {
      let r : Result[Int, _] = try? @strconv.parse_int(s.view())
      match r {
        Ok(v) => v
        Err(_) => raise parse_error("invalid integer value for " + opt_name + ": " + s)
      }
    })
  }
  let opt_name = "--" + name
  let reducer = make_reducer(make_int_pre(opt_name), accum, initial_val)
  let node = make_reduced_value_node(opt_name, reducer, cell, pending, reset)
  let no_node = make_reduced_negate_node("--no-" + name, reducer, cell, pending, reset)
  self.register_option(node, no_node, global)
  for alt in aliases {
    let alt_opt_name = "--" + alt
    let alt_reducer = make_reducer(make_int_pre(alt_opt_name), accum, initial_val)
    let alt_node = make_reduced_value_node(alt_opt_name, alt_reducer, cell, pending, reset)
    let alt_no_node = make_reduced_negate_node("--no-" + alt, alt_reducer, cell, pending, reset)
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_reducer = make_reducer(make_int_pre(short_name), accum, initial_val)
    let short_node = make_reduced_value_node(short_name, short_reducer, cell, pending, reset)
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  let display_value_name = if value_name == "" { to_upper(name) } else { value_name }
  let display_default = if default == 0 { "" } else { default.to_string() }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: display_default,
    global,
    short: if short != '\u0000' { Some(short) } else { None },
    aliases,
    hidden,
  })
  { id, getter: fn() -> Int { cell.val }, parsed: self.parsed }
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
  for alt in aliases {
    let alt_node = make_value_node(
      "--" + alt,
      fn(s) { Ok(fn() { cell.val.push(s) }) },
      fn() { cell.val = [] },
    )
    let alt_no_node = make_flag_node(
      "--no-" + alt,
      fn() { fn() { cell.val = [] } },
      fn() { cell.val = [] },
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_node = make_value_node(
      short_name,
      fn(s) { Ok(fn() { cell.val.push(s) }) },
      fn() { cell.val = [] },
    )
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  let display_value_name = if value_name == "" { to_upper(name) } else { value_name }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: "",
    global,
    short: if short != '\u0000' { Some(short) } else { None },
    aliases,
    hidden,
  })
  { id, getter: fn() -> Array[String] { cell.val }, parsed: self.parsed }
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
  let node = make_value_node(
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
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() { fn() { cell.val = [] } },
    fn() { cell.val = [] },
  )
  self.register_option(node, no_node, global)
  for alt in aliases {
    let alt_opt_name = "--" + alt
    let alt_node = make_value_node(
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
    )
    let alt_no_node = make_flag_node(
      "--no-" + alt,
      fn() { fn() { cell.val = [] } },
      fn() { cell.val = [] },
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_opt_name = short_name
    let short_node = make_value_node(
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
    )
    self.nodes.push(short_node)
    if global {
      self.global_nodes.push(short_node)
    }
  }
  let display_value_name = if value_name == "" { to_upper(name) } else { value_name }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: "",
    global,
    short: if short != '\u0000' { Some(short) } else { None },
    aliases,
    hidden,
  })
  { id, getter: fn() -> Array[Int] { cell.val }, parsed: self.parsed }
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
  let reset = fn() {
    cell.val = 0
    pending.val = 0
  }
  let node = make_flag_node(
    "--" + name,
    fn() {
      pending.val = pending.val + 1
      fn() { cell.val = pending.val }
    },
    reset,
  )
  let no_node = make_flag_node(
    "--no-" + name,
    fn() {
      pending.val = 0
      fn() { cell.val = pending.val }
    },
    reset,
  )
  self.register_option(node, no_node, global)
  // aliases
  for alt in aliases {
    let alt_node = make_flag_node(
      "--" + alt,
      fn() {
        pending.val = pending.val + 1
        fn() { cell.val = pending.val }
      },
      reset,
    )
    let alt_no_node = make_flag_node(
      "--no-" + alt,
      fn() {
        pending.val = 0
        fn() { cell.val = pending.val }
      },
      reset,
    )
    self.register_option(alt_node, alt_no_node, global)
  }
  // short option
  if short != '\u0000' {
    let short_name = "-" + short.to_string()
    let short_node = make_flag_node(
      short_name,
      fn() {
        pending.val = pending.val + 1
        fn() { cell.val = pending.val }
      },
      reset,
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
    short: if short != '\u0000' { Some(short) } else { None },
    aliases,
    hidden,
  })
  { id, getter: fn() -> Int { cell.val }, parsed: self.parsed }
}

///|
pub fn Parser::positional(self : Parser, name~ : String, description? : String = "") -> Opt[String] {
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
  { id, getter: fn() -> String { cell.val }, parsed: self.parsed }
}

///|
pub fn Parser::rest(self : Parser, name~ : String, description? : String = "") -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  ignore(name)
  let handler : (Array[String], Int) -> TryResult = fn(
    args : Array[String],
    pos : Int,
  ) -> TryResult {
    if pos >= args.length() {
      Reject
    } else {
      let value = args[pos]
      Accept(consumed=1, commit=fn() { cell.val.push(value) })
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
  { id, getter: fn() -> Array[String] { cell.val }, parsed: self.parsed }
}

///|
pub fn Parser::cmd(
  self : Parser,
  name~ : String,
  setup~ : (Parser) -> Unit,
  description? : String = "",
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
  }
  setup(child)
  inject_help_node(child)
  let cmd_name = name
  let node = ExactNode::{
    name: cmd_name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() {
        Reject
      } else if args[pos] == cmd_name {
        let rest_args = Array::from_iter(args.view(start=pos + 1).iter())
        let parse_result : Result[ParseResult, ParseError] = try? child.parse(rest_args)
        match parse_result {
          Ok(child_result) =>
            Accept(
              consumed=args.length() - pos,
              commit=fn() {
                cell.val = true
                self.children.set(cmd_name, child_result)
              },
            )
          Err(e) => Error(e)
        }
      } else {
        Reject
      }
    },
    reset: fn() { cell.val = false },
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
  { id, getter: fn() -> Bool { cell.val }, parsed: self.parsed }
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
