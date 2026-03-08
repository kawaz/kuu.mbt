///|
fn inject_help_node(parser : Parser) -> Unit {
  // Idempotent: skip if already injected
  for meta in parser.metas {
    if meta.name == "help" {
      return
    }
  }
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
  parser.metas.push(OptMeta::{
    kind: Flag,
    name: "help",
    help: "Print help",
    value_name: "",
    default_display: "",
    global: false,
    shorts: ['h'],
    aliases: [],
    hidden: false,
  })
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
      _ => if meta.global { globals.push(meta) } else { options.push(meta) }
    }
  }
  // Helper: compute left column for a command entry
  let need_sections = (
    commands.length() > 0,
    options.length() > 0,
    globals.length() > 0,
  )
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
  if meta.shorts.length() > 0 {
    buf.write_string("  -")
    buf.write_char(meta.shorts[0])
    for i in 1..<meta.shorts.length() {
      buf.write_string(", -")
      buf.write_char(meta.shorts[i])
    }
    buf.write_string(", --")
    buf.write_string(meta.name)
  } else {
    buf.write_string("      --")
    buf.write_string(meta.name)
  }
  for alt in meta.aliases {
    buf.write_string(", --")
    buf.write_string(alt)
  }
  if not(meta.value_name.is_empty()) {
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
    if not(meta.default_display.is_empty()) {
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
