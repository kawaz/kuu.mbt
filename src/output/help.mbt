///| ヘルプテキストを生成する
pub fn format_help(
  nodes : Array[@core.ErasedNode],
  program_name~ : String = "",
  description~ : String = "",
) -> String {
  if nodes.length() == 0 {
    return ""
  }
  // ノードを分類
  let commands : Array[@core.ErasedNode] = []
  let positionals : Array[@core.ErasedNode] = []
  let options : Array[@core.ErasedNode] = []
  let advanced_options : Array[@core.ErasedNode] = []
  let global_options : Array[@core.ErasedNode] = []
  let env_entries : Array[(@core.ErasedNode, String)] = [] // (node, env_var_name)
  for node in nodes {
    if node.meta.visibility == @core.Visibility::Hidden {
      continue
    }
    match node.meta.kind {
      @core.Kind::Command => commands.push(node)
      @core.Kind::Positional => positionals.push(node)
      @core.Kind::Option =>
        if node.meta.visibility == @core.Visibility::Advanced {
          advanced_options.push(node)
        } else if node.meta.global {
          global_options.push(node)
        } else {
          options.push(node)
        }
    }
    // 環境変数の収集
    match node.meta.env {
      Some(env_name) => env_entries.push((node, env_name))
      None =>
        match node.meta.auto_env {
          Some(true) => {
            let env_name = name_to_env(node.meta.name)
            env_entries.push((node, env_name))
          }
          _ => ()
        }
    }
  }
  let buf = StringBuilder::new()
  let mut first_section = true
  // Usage 行
  if program_name.length() > 0 {
    buf.write_string("Usage: ")
    buf.write_string(program_name)
    if options.length() > 0 || advanced_options.length() > 0 || global_options.length() >
    0 {
      buf.write_string(" [OPTIONS]")
    }
    if commands.length() > 0 {
      buf.write_string(" [COMMAND]")
    }
    for pos in positionals {
      let vn = if pos.meta.value_name.length() > 0 {
        pos.meta.value_name
      } else {
        pos.meta.name
      }
      if pos.meta.required {
        buf.write_string(" <")
        buf.write_string(vn)
        buf.write_string(">")
      } else {
        buf.write_string(" [")
        buf.write_string(vn)
        buf.write_string("]")
      }
    }
    first_section = false
  }
  // description
  if description.length() > 0 {
    if first_section {
      // no separator before first section
    } else {
      buf.write_string("\n\n")
    }
    buf.write_string(description)
    first_section = false
  }
  // Commands セクション
  if commands.length() > 0 {
    if first_section {
      // no separator before first section
    } else {
      buf.write_string("\n\n")
    }
    buf.write_string("Commands:")
    let col = compute_command_column(commands)
    for cmd in commands {
      buf.write_string("\n  ")
      buf.write_string(cmd.meta.name)
      let cmd_help = if cmd.meta.visibility == @core.Visibility::Deprecated {
        if cmd.meta.help.length() > 0 {
          cmd.meta.help + " [deprecated]"
        } else {
          "[deprecated]"
        }
      } else {
        cmd.meta.help
      }
      if cmd_help.length() > 0 {
        let name_len = cmd.meta.name.length()
        let padding = col - name_len
        write_spaces(buf, padding)
        buf.write_string(cmd_help)
      }
    }
    first_section = false
  }
  // Arguments セクション
  if positionals.length() > 0 {
    if first_section {
      // no separator before first section
    } else {
      buf.write_string("\n\n")
    }
    buf.write_string("Arguments:")
    let col = compute_positional_column(positionals)
    for pos in positionals {
      buf.write_string("\n  ")
      let display = format_positional_display(pos)
      buf.write_string(display)
      let pos_help = if pos.meta.visibility == @core.Visibility::Deprecated {
        if pos.meta.help.length() > 0 {
          pos.meta.help + " [deprecated]"
        } else {
          "[deprecated]"
        }
      } else {
        pos.meta.help
      }
      if pos_help.length() > 0 {
        let padding = col - display.length()
        write_spaces(buf, padding)
        buf.write_string(pos_help)
      }
    }
    first_section = false
  }
  // Options セクション
  if options.length() > 0 {
    if first_section {
      // no separator before first section
    } else {
      buf.write_string("\n\n")
    }
    buf.write_string("Options:")
    let col = compute_option_column(options)
    for opt in options {
      write_option_line(buf, opt, col)
    }
    first_section = false
  }
  // Advanced Options セクション
  if advanced_options.length() > 0 {
    if first_section {
      // no separator before first section
    } else {
      buf.write_string("\n\n")
    }
    buf.write_string("Advanced Options:")
    let col = compute_option_column(advanced_options)
    for opt in advanced_options {
      write_option_line(buf, opt, col)
    }
    first_section = false
  }
  // Global Options セクション
  if global_options.length() > 0 {
    if first_section {
      // no separator before first section
    } else {
      buf.write_string("\n\n")
    }
    buf.write_string("Global Options:")
    let col = compute_option_column(global_options)
    for opt in global_options {
      write_option_line(buf, opt, col)
    }
    first_section = false
  }
  // Environment Variables セクション
  if env_entries.length() > 0 {
    if first_section {
      // no separator before first section
    } else {
      buf.write_string("\n\n")
    }
    buf.write_string("Environment Variables:")
    let col = compute_env_column(env_entries)
    for entry in env_entries {
      let node = entry.0
      let env_name = entry.1
      buf.write_string("\n  ")
      buf.write_string(env_name)
      let padding = col - env_name.length()
      write_spaces(buf, padding)
      buf.write_string("Sets --")
      buf.write_string(node.meta.name)
    }
    first_section = false
  }
  buf.to_string()
}

///| オプション名を環境変数名に変換（auto_env 用）
fn name_to_env(name : String) -> String {
  let buf = StringBuilder::new()
  for ch in name {
    if ch == '-' {
      buf.write_string("_")
    } else if ch >= 'a' && ch <= 'z' {
      let upper = Char::from_int(ch.to_int() - 32)
      buf.write_char(upper)
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

// Design rationale: パディング計算は String.length()（コードポイント数）を使用する。
// option name / value_name は ASCII 前提のため、ターミナル表示幅と一致する。
// 日本語等のマルチバイト文字が name/value_name に使われた場合は列が崩れるが、
// CLI オプション名にマルチバイトを使うユースケースは一般的でないため、
// 幅計算のi18n対応は将来課題とする。

///| オプションの表示文字列を生成（名前部分のみ）
fn format_option_display(node : @core.ErasedNode) -> String {
  let buf = StringBuilder::new()
  // ショートオプション
  if node.meta.shorts.length() > 0 {
    buf.write_string("-")
    buf.write_string(node.meta.shorts[0].char.to_string())
    buf.write_string(", ")
  }
  // inversion による名前表示
  match node.meta.inversion {
    Some(@core.FlagInversion::EnableDisable) => {
      buf.write_string("--enable-")
      buf.write_string(node.meta.name)
      buf.write_string(", --disable-")
      buf.write_string(node.meta.name)
    }
    Some(@core.FlagInversion::Custom(pos, neg)) => {
      buf.write_string("--")
      buf.write_string(pos)
      buf.write_string(", --")
      buf.write_string(neg)
    }
    _ => {
      buf.write_string("--")
      buf.write_string(node.meta.name)
    }
  }
  // aliases
  for alias in node.meta.aliases {
    buf.write_string(", --")
    buf.write_string(alias.name)
  }
  // value_name
  if node.meta.value_name.length() > 0 {
    buf.write_string(" <")
    buf.write_string(node.meta.value_name)
    buf.write_string(">")
  }
  buf.to_string()
}

///| Positional の表示文字列を生成
fn format_positional_display(node : @core.ErasedNode) -> String {
  let buf = StringBuilder::new()
  buf.write_string("<")
  if node.meta.value_name.length() > 0 {
    buf.write_string(node.meta.value_name)
  } else {
    buf.write_string(node.meta.name)
  }
  buf.write_string(">")
  buf.to_string()
}

///| オプションのヘルプテキスト部分を生成（修飾子含む）
fn format_option_help(node : @core.ErasedNode) -> String {
  let buf = StringBuilder::new()
  let mut has_content = false
  if node.meta.help.length() > 0 {
    buf.write_string(node.meta.help)
    has_content = true
  }
  if node.meta.choices.length() > 0 {
    if has_content {
      buf.write_string(" ")
    }
    buf.write_string("[possible values: ")
    for i, choice in node.meta.choices {
      if i > 0 {
        buf.write_string(", ")
      }
      buf.write_string(choice)
    }
    buf.write_string("]")
    has_content = true
  }
  if node.meta.required {
    if has_content {
      buf.write_string(" ")
    }
    buf.write_string("[required]")
    has_content = true
  }
  if node.meta.visibility == @core.Visibility::Deprecated {
    if has_content {
      buf.write_string(" ")
    }
    buf.write_string("[deprecated]")
    has_content = true
  }
  ignore(has_content)
  buf.to_string()
}

///| オプション行を書き込む
fn write_option_line(
  buf : StringBuilder,
  node : @core.ErasedNode,
  col : Int
) -> Unit {
  buf.write_string("\n  ")
  let display = format_option_display(node)
  buf.write_string(display)
  let help_text = format_option_help(node)
  if help_text.length() > 0 {
    let padding = col - display.length()
    write_spaces(buf, padding)
    buf.write_string(help_text)
  }
}

///| Options セクションの整列カラム幅を計算（最長表示幅 + 4）
fn compute_option_column(nodes : Array[@core.ErasedNode]) -> Int {
  let mut max_len = 0
  for node in nodes {
    let display = format_option_display(node)
    if display.length() > max_len {
      max_len = display.length()
    }
  }
  max_len + 4
}

///| Commands セクションの整列カラム幅を計算
fn compute_command_column(nodes : Array[@core.ErasedNode]) -> Int {
  let mut max_len = 0
  for node in nodes {
    if node.meta.name.length() > max_len {
      max_len = node.meta.name.length()
    }
  }
  max_len + 4
}

///| Positional セクションの整列カラム幅を計算
fn compute_positional_column(nodes : Array[@core.ErasedNode]) -> Int {
  let mut max_len = 0
  for node in nodes {
    let display = format_positional_display(node)
    if display.length() > max_len {
      max_len = display.length()
    }
  }
  max_len + 4
}

///| 環境変数セクションの整列カラム幅を計算
fn compute_env_column(entries : Array[(@core.ErasedNode, String)]) -> Int {
  let mut max_len = 0
  for entry in entries {
    let env_name = entry.1
    if env_name.length() > max_len {
      max_len = env_name.length()
    }
  }
  max_len + 4
}

///| スペースを書き込む
fn write_spaces(buf : StringBuilder, count : Int) -> Unit {
  for _ in 0..<count {
    buf.write_string(" ")
  }
}
