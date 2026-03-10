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
    registered_names: {},
    duplicate_errors: [],
    force_unclaimed: [],
    alias_sources: Map::new(),
  }
  if dashdash {
    p.install_separator_node()
  }
  p
}

///|
/// コンビネータの共通パイプライン: メインノード生成 → was_set ラップ → variation展開 → 登録 → OptMeta → Opt[T]
fn[T] Parser::register_option(
  self : Parser,
  name~ : String,
  aliases~ : Array[String],
  shorts~ : String,
  global~ : Bool,
  help~ : String,
  value_name~ : String,
  default_display~ : String,
  hidden~ : Bool,
  kind~ : OptKind,
  variations~ : Array[Variation],
  was_set~ : Ref[Bool],
  make_main_node~ : (String) -> ExactNode,
  make_node_for_variation~ : (String, Variation) -> ExactNode,
  getter~ : () -> T,
) -> Opt[T] {
  let id = (self.next_id)()
  self.expand_and_register(
    name, aliases, shorts, global,
    make_long_nodes=fn(opt_name) {
      let nodes : Array[ExactNode] = []
      nodes.push(wrap_node_with_set(make_main_node(opt_name), was_set))
      expand_variation_nodes(opt_name, variations, nodes, make_node_for_variation)
      nodes
    },
    make_short_nodes=fn(short_name) {
      [wrap_node_with_set(make_main_node(short_name), was_set)]
    },
  )
  let shorts_arr : Array[Char] = []
  for ch in shorts {
    shorts_arr.push(ch)
  }
  let var_names : Array[String] = []
  for v in variations {
    let prefix = match v {
      Toggle(p) | True(p) | False(p) | Reset(p) | Unset(p) => p
    }
    var_names.push("--" + prefix + "-" + name)
  }
  self.metas.push(OptMeta::{
    kind,
    name,
    help,
    value_name,
    default_display,
    global,
    shorts: shorts_arr,
    aliases,
    variation_names: var_names,
    hidden,
  })
  self.alias_sources[id] = AliasSource::{
    make_node: make_main_node,
    target_was_set: was_set,
  }
  { id, name: "--" + name, getter, parsed: self.parsed, is_set: fn() { was_set.val } }
}

///|
/// コンビネータの共通パターン: メイン名 → aliases → short の展開 + ノード登録
fn Parser::expand_and_register(
  self : Parser,
  name : String,
  aliases : Array[String],
  shorts : String,
  global : Bool,
  // long option 名（"--verbose" 等）に対して全ノード（メイン + variation）を返す
  make_long_nodes~ : (String) -> Array[ExactNode],
  // short option 名（"-v" 等）に対してメインノードのみ返す（variation なし）
  make_short_nodes~ : (String) -> Array[ExactNode],
) -> Unit {
  fn register(nodes : Array[ExactNode]) {
    for node in nodes {
      self.nodes.push(node)
      if global {
        self.global_nodes.push(node)
      }
    }
  }

  fn check_and_register_names(nodes : Array[ExactNode]) {
    // Check against previously registered names (cross-combinator duplicates)
    for node in nodes {
      if node.name != "" && self.registered_names.contains(node.name) {
        self.duplicate_errors.push(
          "duplicate option name: " + node.name,
        )
        break // report once per batch
      }
    }
    // Register all names from this batch
    for node in nodes {
      if node.name != "" {
        self.registered_names[node.name] = true
      }
    }
  }

  // Validate shorts characters
  for ch in shorts {
    if ch == '-' {
      self.duplicate_errors.push(
        "invalid short option character '-' in option --" + name,
      )
    } else if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      self.duplicate_errors.push(
        "invalid short option character (whitespace) in option --" + name,
      )
    } else if ch == '\u0000' {
      self.duplicate_errors.push(
        "invalid short option character (NUL) in option --" + name,
      )
    }
  }
  let long_nodes = make_long_nodes("--" + name)
  check_and_register_names(long_nodes)
  register(long_nodes)
  for alt in aliases {
    let alt_nodes = make_long_nodes("--" + alt)
    check_and_register_names(alt_nodes)
    register(alt_nodes)
  }
  for ch in shorts {
    let short_nodes = make_short_nodes("-" + ch.to_string())
    check_and_register_names(short_nodes)
    register(short_nodes)
  }
}
