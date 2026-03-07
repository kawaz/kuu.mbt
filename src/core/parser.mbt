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
  if dashdash {
    p.install_separator_node()
  }
  p
}

///|
/// コンビネータの共通パターン: メイン名 → aliases → short の展開 + ノード登録
fn Parser::expand_and_register(
  self : Parser,
  name : String,
  aliases : Array[String],
  short : Char,
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

  register(make_long_nodes("--" + name))
  for alt in aliases {
    register(make_long_nodes("--" + alt))
  }
  if short != '\u0000' {
    register(make_short_nodes("-" + short.to_string()))
  }
}
