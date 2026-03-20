///|
fn inject_help_node(parser : Parser) -> Unit {
  // Idempotent: skip if already injected
  for meta in parser.metas {
    if meta.name == "help" {
      return
    }
  }
  let added_long = not(parser.registered_names.contains("--help"))
  let added_short = not(parser.registered_names.contains("-h"))
  // Skip entirely if both names are already taken by user-defined options
  if not(added_long) && not(added_short) {
    return
  }
  if added_long {
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
    parser.nodes.push(help_node)
    parser.registered_names["--help"] = true
  }
  if added_short {
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
    parser.nodes.push(short_help_node)
    parser.registered_names["-h"] = true
  }
  let shorts : Array[String] = if added_short { ["h"] } else { [] }
  parser.metas.push(OptMeta::{
    kind: Flag,
    name: "help",
    help: "Print help",
    value_name: "",
    default_display: "",
    env_name: "",
    global: false,
    shorts,
    aliases: [],
    variation_names: [],
    visibility: Visible,
  })
}

///|
fn Parser::split_metas(
  self : Parser,
) -> (Array[OptMeta], Array[OptMeta], Array[OptMeta], Array[OptMeta]) {
  let commands : Array[OptMeta] = []
  let options : Array[OptMeta] = []
  let globals : Array[OptMeta] = []
  let arguments : Array[OptMeta] = []
  for meta in self.metas {
    if meta.visibility != Visible {
      continue
    }
    match meta.kind {
      Command => commands.push(meta)
      Positional => arguments.push(meta)
      Rest => arguments.push(meta)
      _ => if meta.global { globals.push(meta) } else { options.push(meta) }
    }
  }
  (commands, options, globals, arguments)
}

///|
pub fn Parser::generate_usage(self : Parser) -> String {
  let (commands, options, globals, arguments) = self.split_metas()
  let buf = StringBuilder::new()
  buf.write_string("Usage:")
  if options.length() > 0 || globals.length() > 0 {
    buf.write_string(" [OPTIONS]")
  }
  for arg in arguments {
    buf.write_char(' ')
    match arg.kind {
      Positional => {
        buf.write_char('<')
        buf.write_string(arg.name.to_upper())
        buf.write_char('>')
      }
      Rest => {
        buf.write_char('[')
        buf.write_string(arg.name.to_upper())
        buf.write_string("]...")
      }
      _ => ()
    }
  }
  if commands.length() > 0 {
    buf.write_string(" [COMMAND]")
  }
  buf.to_string()
}

///|
pub fn Parser::help_header(self : Parser, text : String) -> Unit {
  self.help_header_text.val = text
}

///|
pub fn Parser::help_footer(self : Parser, text : String) -> Unit {
  self.help_footer_text.val = text
}

///|
pub fn Parser::generate_help(self : Parser) -> String {
  let buf = StringBuilder::new()
  // 0. Header (Level 1 customization)
  let header = self.help_header_text.val
  if not(header.is_empty()) {
    buf.write_string(header)
  }
  // 1. Description
  let desc = self.description.val
  if not(desc.is_empty()) {
    buf.write_string(desc)
    buf.write_char('\n')
    buf.write_char('\n')
  }
  let (commands, options, globals, arguments) = self.split_metas()
  // 2. Usage line
  buf.write_string(self.generate_usage())
  buf.write_char('\n')
  // Commands section
  if commands.length() > 0 {
    buf.write_char('\n')
    buf.write_string("Commands:\n")
    let max_left = calculate_max_width(commands, format_cmd_left)
    for cmd in commands {
      let left = format_cmd_left(cmd)
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
  // Arguments section
  if arguments.length() > 0 {
    buf.write_char('\n')
    buf.write_string("Arguments:\n")
    let max_left = calculate_max_width(arguments, format_arg_left)
    for arg in arguments {
      let left = format_arg_left(arg)
      buf.write_string(left)
      if not(arg.help.is_empty()) {
        let padding = max_left - left.char_length() + 2
        let pad_str = String::make(padding, ' ')
        buf.write_string(pad_str)
        buf.write_string(arg.help)
      }
      buf.write_char('\n')
    }
  }
  // Options section
  if options.length() > 0 {
    buf.write_char('\n')
    buf.write_string("Options:\n")
    write_opt_section(buf, options, env_prefix=self.env_prefix.val)
  }
  // Global Options section
  if globals.length() > 0 {
    buf.write_char('\n')
    buf.write_string("Global Options:\n")
    write_opt_section(buf, globals, env_prefix=self.env_prefix.val)
  }
  // Footer (Level 1 customization)
  let footer = self.help_footer_text.val
  if not(footer.is_empty()) {
    buf.write_string(footer)
    buf.write_char('\n')
  }
  buf.to_string()
}

///|
fn calculate_max_width(
  metas : Array[OptMeta],
  format_left : (OptMeta) -> String,
) -> Int {
  let max = Ref::new(0)
  for meta in metas {
    let w = format_left(meta).char_length()
    if w > max.val {
      max.val = w
    }
  }
  max.val
}

///|
fn format_cmd_left(meta : OptMeta) -> String {
  "  " + meta.name
}

///|
fn format_opt_left(meta : OptMeta) -> String {
  let buf = StringBuilder::new()
  if meta.shorts.length() > 0 {
    buf.write_string("  -")
    buf.write_string(meta.shorts[0])
    for i in 1..<meta.shorts.length() {
      buf.write_string(", -")
      buf.write_string(meta.shorts[i])
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
  for vname in meta.variation_names {
    buf.write_string(", ")
    buf.write_string(vname)
  }
  if not(meta.value_name.is_empty()) {
    buf.write_string(" <")
    buf.write_string(meta.value_name)
    buf.write_char('>')
  }
  buf.to_string()
}

///|
fn format_opt_right(meta : OptMeta, env_prefix? : String = "") -> String {
  let buf = StringBuilder::new()
  if not(meta.help.is_empty()) {
    buf.write_string(meta.help)
  }
  if not(meta.env_name.is_empty()) {
    buf.write_string(" [env: ")
    if env_prefix != "" {
      buf.write_string(env_prefix)
      buf.write_char('_')
    }
    buf.write_string(meta.env_name)
    buf.write_char(']')
  }
  if not(meta.default_display.is_empty()) {
    buf.write_string(" [default: ")
    buf.write_string(meta.default_display)
    buf.write_char(']')
  }
  buf.to_string()
}

///|
fn format_arg_left(meta : OptMeta) -> String {
  let buf = StringBuilder::new()
  buf.write_string("  ")
  match meta.kind {
    Positional => {
      buf.write_char('<')
      buf.write_string(meta.name.to_upper())
      buf.write_char('>')
    }
    Rest => {
      buf.write_char('[')
      buf.write_string(meta.name.to_upper())
      buf.write_string("]...")
    }
    _ => ()
  }
  buf.to_string()
}

///|
fn write_opt_section(
  buf : StringBuilder,
  metas : Array[OptMeta],
  env_prefix? : String = "",
) -> Unit {
  let max_left = calculate_max_width(metas, format_opt_left)
  for meta in metas {
    let left = format_opt_left(meta)
    buf.write_string(left)
    let right = format_opt_right(meta, env_prefix~)
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
fn Parser::find_meta_by_opt_name(self : Parser, opt_name : String) -> OptMeta? {
  let name = if opt_name.has_prefix("--") {
    opt_name[2:].to_string()
  } else if opt_name.has_prefix("-") {
    opt_name[1:].to_string()
  } else {
    opt_name
  }
  for meta in self.metas {
    if meta.name == name {
      return Some(meta)
    }
    for s in meta.shorts {
      if s == name {
        return Some(meta)
      }
    }
    for a in meta.aliases {
      if a == name {
        return Some(meta)
      }
    }
    for v in meta.variation_names {
      if v == opt_name {
        return Some(meta)
      }
    }
  }
  None
}

///|
fn format_opt_help_line(meta : OptMeta, env_prefix? : String = "") -> String {
  let left = format_opt_left(meta)
  let right = format_opt_right(meta, env_prefix~)
  if right.is_empty() {
    left
  } else {
    left + "  " + right
  }
}

///|
fn Parser::format_error_context(self : Parser, info : ParseErrorInfo) -> String {
  let buf = StringBuilder::new()
  // 1. Contextual help line (opt_name から OptMeta を検索)
  if not(info.opt_name.is_empty()) {
    // tip があればサジェスト先のオプションを表示、なければエラー対象自体を表示
    let search_name = if not(info.tip.is_empty()) {
      info.tip
    } else {
      info.opt_name
    }
    match self.find_meta_by_opt_name(search_name) {
      Some(meta) =>
        // C-2: Flag/ValueOpt のみ help 行を表示（Command/Positional/Rest は除外）
        // C-3: 非 Visible オプションは help 行を表示しない
        if meta.visibility == Visible &&
          (meta.kind == Flag || meta.kind == ValueOpt) {
          buf.write_string("  help: ")
          buf.write_string(
            format_opt_help_line(meta, env_prefix=self.env_prefix.val),
          )
          buf.write_char('\n')
        }
      None => ()
    }
  }
  // 1b. MissingSubcommand の場合はコマンド一覧を表示
  if info.kind == MissingSubcommand {
    let (commands, _, _, _) = self.split_metas()
    if commands.length() > 0 {
      buf.write_char('\n')
      buf.write_string("Commands:\n")
      let max_left = calculate_max_width(commands, format_cmd_left)
      for cmd in commands {
        let left = format_cmd_left(cmd)
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
  }
  // 2. tip line
  if not(info.tip.is_empty()) {
    buf.write_string("  tip: a similar option exists: '")
    buf.write_string(info.tip)
    buf.write_string("'\n")
  }
  // 3. Usage line
  buf.write_char('\n')
  buf.write_string(self.generate_usage())
  buf.write_char('\n')
  // 4. Footer
  buf.write_string("\nFor more information, try '--help'.")
  buf.to_string()
}

///|
pub fn ParseErrorInfo::to_string(self : ParseErrorInfo) -> String {
  let buf = StringBuilder::new()
  buf.write_string("error: ")
  buf.write_string(self.message)
  if not(self.error_context.is_empty()) {
    buf.write_char('\n')
    buf.write_string(self.error_context)
  }
  buf.to_string()
}
