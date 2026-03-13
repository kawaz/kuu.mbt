///|
pub fn Parser::cmd(
  self : Parser,
  name~ : String,
  setup~ : (Parser) -> Unit,
  description? : String = "",
  dashdash? : Bool = true,
  aliases? : Array[String] = [],
) -> Opt[CmdResult] {
  let id = (self.next_id)()
  let cell : Ref[CmdResult?] = { val: None }
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
    force_unclaimed: [],
    alias_sources: Map::new(),
    eq_fallback_nodes: [],
    deprecated_usages: [],
  }
  // 親の global_nodes の名前を子の registered_names に登録（衝突検知のため）
  for gnode in self.global_nodes {
    if gnode.name != "" {
      child.registered_names[gnode.name] = true
    }
  }
  setup(child)
  if dashdash {
    child.install_separator_node()
  }
  // Lazy sync: 親の global_nodes への参照と同期済み位置を保持。
  // cmd() 時点以降に追加された global ノードを try_reduce 実行時に子へ伝播する。
  let parent_global = self.global_nodes
  let synced_count : Ref[Int] = { val: parent_global.length() }
  let cmd_name = name
  let was_set : Ref[Bool] = { val: false }
  // Build all command names (primary + aliases) for matching
  let all_names : Array[String] = [cmd_name]
  for a in aliases {
    all_names.push(a)
  }
  // Register command names in registered_names for duplicate detection (H-2 fix)
  for cn in all_names {
    if self.registered_names.contains(cn) {
      self.duplicate_errors.push("duplicate command name: " + cn)
    }
    self.registered_names[cn] = true
  }
  let make_cmd_node : (String) -> ExactNode = fn(match_name) {
    ExactNode::{
      name: match_name,
      needs_value: false,
      try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
        if pos >= args.length() {
          Reject
        } else if args[pos] == match_name {
          // 後から追加された親の global ノードを子に同期
          while synced_count.val < parent_global.length() {
            let gnode = parent_global[synced_count.val]
            child.nodes.push(gnode)
            child.global_nodes.push(gnode)
            if gnode.name != "" {
              child.registered_names[gnode.name] = true
            }
            synced_count.val += 1
          }
          let rest_args = args.view(start=pos + 1).to_array()
          let parse_result : Result[ParseResult, ParseError] = try? child.parse(
            rest_args,
          )
          match parse_result {
            Ok(child_result) =>
              Accept(consumed=args.length() - pos, commit=fn() {
                cell.val = Some(CmdResult::{ name: cmd_name, parser: child })
                was_set.val = true
                self.children.set(cmd_name, child_result)
                // 子パーサの deprecated_usages を親にマージ（再帰的に伝搬）
                for pair in child.deprecated_usages {
                  self.deprecated_usages.push(pair)
                }
              })
            Err(e) => Error(e)
          }
        } else {
          Reject
        }
      },
      reset: fn() {
        cell.val = None
        was_set.val = false
        // H-3 fix: reset child parser state when cmd loses OC competition
        child.parsed.val = false
        child.current_positional.val = 0
      },
    }
  }
  for cmd in all_names {
    self.nodes.push(make_cmd_node(cmd))
  }
  self.alias_sources[id] = AliasSource::{
    make_node: make_cmd_node,
    target_was_set: was_set,
    is_global: false,
    make_eq_fallback: None,
  }
  self.metas.push(OptMeta::{
    kind: Command,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global: false,
    shorts: [],
    aliases,
    variation_names: [],
    hidden: false,
  })
  {
    id,
    name,
    getter: fn() -> CmdResult {
      match cell.val {
        Some(v) => v
        None => CmdResult::{ name: "", parser: child }
      }
    },
    parsed: child.parsed,
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
  aliases? : Array[String] = [],
) -> Parser {
  let child_ref : Ref[Parser?] = { val: None }
  ignore(
    self.cmd(name~, description~, dashdash~, aliases~, setup=fn(child) {
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
