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
  let vc : ValCell[CmdResult?] = ValCell::new(Val(None))
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
    node_templates: Map::new(),
    eq_fallback_nodes: [],
    deprecated_usages: [],
    env_applicators: [],
    env_map: { val: {} },
    help_header_text: { val: "" },
    help_footer_text: { val: "" },
    env_prefix: { val: "" },
    auto_env_enabled: { val: self.auto_env_enabled.val },
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
          // env_prefix の継承: 親の prefix + "_" + uppercase(cmd_name)
          let parent_prefix = self.env_prefix.val
          if parent_prefix != "" {
            child.env_prefix.val = parent_prefix + "_" + cmd_name.to_upper()
          }
          let parse_result : Result[ParseResult, ParseError] = try? child.parse(
            rest_args,
            env=self.env_map.val,
          )
          match parse_result {
            Ok(child_result) =>
              Accept(consumed=args.length() - pos, commit=fn() {
                vc.cell.val = Some(CmdResult::{ name: cmd_name, parser: child })
                vc.committed.val = true
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
        vc.cell.val = None
        vc.committed.val = false
        // H-3 fix: reset child parser state when cmd loses OC competition
        child.parsed.val = false
        child.current_positional.val = 0
      },
    }
  }
  for cmd in all_names {
    self.nodes.push(make_cmd_node(cmd))
  }
  self.node_templates[id] = NodeTemplate::{
    make_node: make_cmd_node,
    is_global: false,
    make_eq_fallback: None,
  }
  self.metas.push(OptMeta::{
    kind: Command,
    name,
    help: description,
    value_name: "",
    default_display: "",
    env_name: "",
    global: false,
    shorts: [],
    aliases,
    variation_names: [],
    hidden: false,
  })
  let cmd_acc : Accessor[CmdResult] = {
    get: fn() -> CmdResult {
      match vc.cell.val {
        Some(v) => v
        None => CmdResult::{ name: "", parser: child }
      }
    },
    set: fn(v) {
      vc.cell.val = Some(v)
      vc.committed.val = true
    },
    set_value: fn(v) { vc.cell.val = Some(v) },
    set_commit: fn() { vc.committed.val = true },
    reset: fn() {
      vc.cell.val = None
      vc.committed.val = false
    },
  }
  {
    id,
    name,
    accessor: cmd_acc,
    parsed: child.parsed,
    used: fn() { vc.committed.val },
  }
}

///|
/// Returns the child Parser directly, eliminating the need for Ref wrappers.
/// Opts defined on the returned Parser are accessible without closure escaping.
///
/// Example:
///   let clone = p.sub(name="clone", description="Clone a repo")
///   let url = clone.positional(name="url")
///   let depth = clone.int(name="depth", default=0)
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
      raise parse_error("subcommand required", kind=MissingSubcommand)
    }
  })
}
