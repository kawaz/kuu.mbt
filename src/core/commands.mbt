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
    registered_names: {},
    duplicate_errors: [],
  }
  setup(child)
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
/// Returns the child Parser directly, eliminating the need for Ref wrappers.
/// Opts defined on the returned Parser are accessible without closure escaping.
///
/// Example:
///   let clone = p.sub(name="clone", description="Clone a repo")
///   let url = clone.positional(name="url")
///   let depth = clone.int_opt(name="depth", default=0)
///   // After parse: url.get(), depth.get() — no Ref needed
pub fn Parser::sub(
  self : Parser,
  name~ : String,
  description? : String = "",
  dashdash? : Bool = true,
) -> Parser {
  let child_ref : Ref[Parser?] = { val: None }
  ignore(
    self.cmd(name~, description~, dashdash~, setup=fn(child) {
      child_ref.val = Some(child)
    }),
  )
  child_ref.val.unwrap()
}

///|
/// Require that at least one subcommand is selected.
/// If no subcommand is chosen after parsing, raises ParseError with help text.
pub fn Parser::require_cmd(self : Parser) -> Unit {
  self.post_hooks.push(fn() raise ParseError {
    if self.children.length() == 0 {
      raise ParseError(
        ParseErrorInfo::{
          message: "subcommand required",
          help_text: self.generate_help(),
        },
      )
    }
  })
}
