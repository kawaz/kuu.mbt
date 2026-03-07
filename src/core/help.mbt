///|
fn inject_help_node(parser : Parser) -> Unit {
  let help_node = ExactNode::{
    name: "--help",
    needs_value: false,
    try_reduce: fn(_args : Array[String], pos : Int) -> TryResult {
      if pos >= _args.length() {
        Reject
      } else if _args[pos] == "--help" {
        Error(HelpRequested(parser.generate_help()))
      } else {
        Reject
      }
    },
    reset: fn() {  },
  }
  let short_help_node = ExactNode::{
    name: "-h",
    needs_value: false,
    try_reduce: fn(_args : Array[String], pos : Int) -> TryResult {
      if pos >= _args.length() {
        Reject
      } else if _args[pos] == "-h" {
        Error(HelpRequested(parser.generate_help()))
      } else {
        Reject
      }
    },
    reset: fn() {  },
  }
  parser.nodes.push(help_node)
  parser.nodes.push(short_help_node)
  parser.metas.push(
    OptMeta::{
      kind: Flag,
      name: "help",
      help: "Print help",
      value_name: "",
      default_display: "",
      global: false,
      short: Some('h'),
      aliases: [],
      hidden: false,
      choices: [],
      implicit_value_display: "",
    },
  )
}

///|
pub fn Parser::generate_help(self : Parser) -> String {
  let buf = StringBuilder::new()
  // 1. Description
  let desc = self.description.val
  if not(desc.is_empty()) {
    buf.write_string(desc)
    buf.write_char('\n')
    buf.write_char('\n')
  }
  // Collect metas into categories
  let commands : Array[OptMeta] = []
  let options : Array[OptMeta] = []
  let globals : Array[OptMeta] = []
  for meta in self.metas {
    if meta.hidden {
      continue
    }
    match meta.kind {
      Command => commands.push(meta)
      Positional | Rest => continue
      _ =>
        if meta.global {
          globals.push(meta)
        } else {
          options.push(meta)
        }
    }
  }
  // Helper: compute left column for a command entry
  let need_sections = (commands.length() > 0, options.length() > 0, globals.length() > 0)
  let is_first_section : Ref[Bool] = { val: true }
  // Commands section
  if commands.length() > 0 {
    if not(is_first_section.val) {
      buf.write_char('\n')
    }
    is_first_section.val = false
    buf.write_string("Commands:\n")
    // Calculate max left width for commands
    let max_left = {
      let m : Ref[Int] = { val: 0 }
      for cmd in commands {
        let w = 2 + cmd.name.char_length()
        if w > m.val {
          m.val = w
        }
      }
      m.val
    }
    for cmd in commands {
      let left = "  " + cmd.name
      buf.write_string(left)
      if not(cmd.help.is_empty()) {
        let padding = max_left - left.char_length() + 2
        let pad_str = String::make(padding, ' ')
        buf.write_string(pad_str)
        buf.write_string(cmd.help)
      }
      buf.write_char('\n')
    }
  }
  // Options section
  if options.length() > 0 {
    if not(is_first_section.val) {
      buf.write_char('\n')
    }
    is_first_section.val = false
    buf.write_string("Options:\n")
    write_opt_section(buf, options)
  }
  // Global Options section
  if globals.length() > 0 {
    if not(is_first_section.val) {
      buf.write_char('\n')
    }
    is_first_section.val = false
    buf.write_string("Global Options:\n")
    write_opt_section(buf, globals)
  }
  ignore(need_sections)
  buf.to_string()
}

///|
fn format_opt_left(meta : OptMeta) -> String {
  let buf = StringBuilder::new()
  match meta.short {
    Some(c) => {
      buf.write_string("  -")
      buf.write_char(c)
      buf.write_string(", --")
      buf.write_string(meta.name)
    }
    None => {
      buf.write_string("      --")
      buf.write_string(meta.name)
    }
  }
  if meta.choices.length() > 0 {
    let has_implicit = not(meta.implicit_value_display.is_empty())
    let default_val = meta.default_display
    if has_implicit {
      // implicit_value あり: [=iv|c1|c2|[=default]] 形式
      buf.write_string(" [")
      let mut first = true
      // implicit_value を先頭に = マーカー付きで
      buf.write_char('=')
      buf.write_string(meta.implicit_value_display)
      first = false
      for c in meta.choices {
        if c == meta.implicit_value_display {
          continue // implicit_value は既に出力済み
        }
        if c == default_val && not(default_val.is_empty()) {
          if not(first) {
            buf.write_char('|')
          }
          buf.write_string("[=")
          buf.write_string(c)
          buf.write_char(']')
          first = false
          continue
        }
        if not(first) {
          buf.write_char('|')
        }
        buf.write_string(c)
        first = false
      }
      buf.write_char(']')
    } else {
      // choices のみ: <c1|c2|=default> 形式
      buf.write_string(" <")
      for i, c in meta.choices {
        if i > 0 {
          buf.write_char('|')
        }
        if c == default_val && not(default_val.is_empty()) {
          buf.write_char('=')
        }
        buf.write_string(c)
      }
      buf.write_char('>')
    }
  } else if not(meta.value_name.is_empty()) {
    buf.write_string(" <")
    buf.write_string(meta.value_name)
    buf.write_char('>')
  }
  buf.to_string()
}

///|
fn write_opt_section(buf : StringBuilder, metas : Array[OptMeta]) -> Unit {
  // Calculate max left width
  let max_left = {
    let m : Ref[Int] = { val: 0 }
    for meta in metas {
      let left = format_opt_left(meta)
      let w = left.char_length()
      if w > m.val {
        m.val = w
      }
    }
    m.val
  }
  for meta in metas {
    let left = format_opt_left(meta)
    buf.write_string(left)
    let right_buf = StringBuilder::new()
    if not(meta.help.is_empty()) {
      right_buf.write_string(meta.help)
    }
    if not(meta.default_display.is_empty()) && meta.choices.length() == 0 {
      right_buf.write_string(" [default: ")
      right_buf.write_string(meta.default_display)
      right_buf.write_char(']')
    }
    let right = right_buf.to_string()
    if not(right.is_empty()) {
      let padding = max_left - left.char_length() + 2
      let pad_str = String::make(padding, ' ')
      buf.write_string(pad_str)
      buf.write_string(right)
    }
    buf.write_char('\n')
  }
}

///|
pub fn ParseErrorInfo::to_string(self : ParseErrorInfo) -> String {
  let buf = StringBuilder::new()
  buf.write_string("error: ")
  buf.write_string(self.message)
  if not(self.help_text.is_empty()) {
    buf.write_char('\n')
    buf.write_char('\n')
    buf.write_string(self.help_text)
  }
  buf.to_string()
}
