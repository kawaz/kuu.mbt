///| テスト用ヘルパー: フル機能版の ErasedNode を作成
fn make_test_node(
  name~ : String,
  kind~ : @core.Kind = Option,
  help~ : String = "",
  shorts~ : Array[@core.ShortEntry] = [],
  aliases~ : Array[@core.AliasEntry] = [],
  inversion~ : @core.FlagInversion? = None,
  env~ : String? = None,
  auto_env~ : Bool? = None,
  choices~ : Array[String] = [],
  value_name~ : String = "",
  required~ : Bool = false,
  visibility~ : @core.Visibility = Visible,
  global~ : Bool = false,
  children~ : Array[@core.ErasedNode] = [],
) -> @core.ErasedNode {
  let meta : @core.OptMeta = {
    name,
    kind,
    help,
    shorts,
    aliases,
    inversion,
    env,
    auto_env,
    choices,
    value_name,
    required,
    visibility,
    global,
    greedy: false,
  }
  {
    meta,
    try_reduce: fn(_action, _rm) { @core.TryReduceResult::Reject },
    commit_reduce: fn(_result, _rm) {  },
    reset_to_initial: fn(_rm) {  },
    is_set: fn() { false },
    children: fn() { children },
  }
}

///|
test "空のノードリストでは空文字列" {
  let result = @output.format_help([])
  assert_eq!(result, "")
}

///|
test "program_name 付きの Usage 行" {
  let node = make_test_node(name="verbose", help="Enable verbose output")
  let result = @output.format_help([node], program_name="myapp")
  assert_true!(result.starts_with("Usage: myapp [OPTIONS]"))
}

///|
test "description の表示" {
  let node = make_test_node(name="verbose", help="Enable verbose output")
  let result = @output.format_help(
    [node],
    program_name="myapp",
    description="A great CLI tool",
  )
  assert_true!(result.contains("A great CLI tool"))
}

///|
test "基本的な Option の表示" {
  let node = make_test_node(
    name="port",
    help="Port number",
    value_name="PORT",
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --port <PORT>    Port number
  assert_eq!(result, expected)
}

///|
test "ショートオプション付きの表示" {
  let node = make_test_node(
    name="verbose",
    help="Enable verbose output",
    shorts=[{ char: 'v' }],
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  -v, --verbose    Enable verbose output
  assert_eq!(result, expected)
}

///|
test "フラグ（value_name なし）の表示" {
  let node = make_test_node(name="verbose", help="Enable verbose output")
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --verbose    Enable verbose output
  assert_eq!(result, expected)
}

///|
test "required マーク表示" {
  let node = make_test_node(
    name="config",
    help="Config file path",
    value_name="FILE",
    required=true,
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --config <FILE>    Config file path [required]
  assert_eq!(result, expected)
}

///|
test "choices 表示" {
  let node = make_test_node(
    name="format",
    help="Output format",
    value_name="FMT",
    choices=["json", "yaml", "toml"],
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --format <FMT>    Output format [possible values: json, yaml, toml]
  assert_eq!(result, expected)
}

///|
test "inversion (No) はそのまま表示" {
  let node = make_test_node(
    name="color",
    help="Enable color",
    inversion=Some(@core.FlagInversion::No),
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --color    Enable color
  assert_eq!(result, expected)
}

///|
test "inversion (EnableDisable) の表示" {
  let node = make_test_node(
    name="color",
    help="Enable color output",
    inversion=Some(@core.FlagInversion::EnableDisable),
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --enable-color, --disable-color    Enable color output
  assert_eq!(result, expected)
}

///|
test "inversion (Custom) の表示" {
  let node = make_test_node(
    name="color",
    help="Enable color output",
    inversion=Some(@core.FlagInversion::Custom("color", "no-color")),
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --color, --no-color    Enable color output
  assert_eq!(result, expected)
}

///|
test "Hidden は非表示" {
  let nodes = [
    make_test_node(name="verbose", help="Enable verbose output"),
    make_test_node(
      name="secret",
      help="Secret option",
      visibility=@core.Visibility::Hidden,
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  assert_true!(result.contains("--verbose"))
  assert_true!(not(result.contains("--secret")))
}

///|
test "Deprecated マーク付き表示" {
  let node = make_test_node(
    name="old-flag",
    help="Old flag",
    visibility=@core.Visibility::Deprecated,
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --old-flag    Old flag [deprecated]
  assert_eq!(result, expected)
}

///|
test "Advanced は別セクションに表示" {
  let nodes = [
    make_test_node(name="verbose", help="Enable verbose output"),
    make_test_node(
      name="debug-level",
      help="Debug level",
      value_name="LEVEL",
      visibility=@core.Visibility::Advanced,
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --verbose    Enable verbose output
    #|
    #|Advanced Options:
    #|  --debug-level <LEVEL>    Debug level
  assert_eq!(result, expected)
}

///|
test "Global Options セクション" {
  let nodes = [
    make_test_node(name="port", help="Port number", value_name="PORT"),
    make_test_node(name="verbose", help="Enable verbose output", global=true),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --port <PORT>    Port number
    #|
    #|Global Options:
    #|  --verbose    Enable verbose output
  assert_eq!(result, expected)
}

///|
test "Commands セクション" {
  let nodes = [
    make_test_node(
      name="serve",
      kind=@core.Kind::Command,
      help="Start the server",
    ),
    make_test_node(
      name="build",
      kind=@core.Kind::Command,
      help="Build the project",
    ),
    make_test_node(name="verbose", help="Enable verbose output"),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS] [COMMAND]
    #|
    #|Commands:
    #|  serve    Start the server
    #|  build    Build the project
    #|
    #|Options:
    #|  --verbose    Enable verbose output
  assert_eq!(result, expected)
}

///|
test "Arguments セクション" {
  let nodes = [
    make_test_node(
      name="file",
      kind=@core.Kind::Positional,
      help="Input file",
      value_name="FILE",
    ),
    make_test_node(name="verbose", help="Enable verbose output"),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS] [FILE]
    #|
    #|Arguments:
    #|  <FILE>    Input file
    #|
    #|Options:
    #|  --verbose    Enable verbose output
  assert_eq!(result, expected)
}

///|
test "環境変数セクション" {
  let nodes = [
    make_test_node(
      name="port",
      help="Port number",
      value_name="PORT",
      env=Some("PORT"),
    ),
    make_test_node(
      name="verbose",
      help="Enable verbose output",
      auto_env=Some(true),
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --port <PORT>    Port number
    #|  --verbose        Enable verbose output
    #|
    #|Environment Variables:
    #|  PORT       Sets --port
    #|  VERBOSE    Sets --verbose
  assert_eq!(result, expected)
}

///|
test "整列: 異なる長さのオプション名で揃う" {
  let nodes = [
    make_test_node(name="p", help="Port", value_name="PORT"),
    make_test_node(
      name="very-long-option",
      help="Long opt",
      value_name="VALUE",
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  // --very-long-option <VALUE> is 26 chars, col = 26 + 4 = 30
  // --p <PORT> is 10 chars, padding = 20 spaces
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --p <PORT>                    Port
    #|  --very-long-option <VALUE>    Long opt
  assert_eq!(result, expected)
}

///|
test "全セクション統合テスト" {
  let nodes = [
    make_test_node(
      name="serve",
      kind=@core.Kind::Command,
      help="Start the server",
    ),
    make_test_node(
      name="file",
      kind=@core.Kind::Positional,
      help="Input file",
      value_name="FILE",
    ),
    make_test_node(
      name="port",
      help="Port number",
      value_name="PORT",
      shorts=[{ char: 'p' }],
      env=Some("PORT"),
    ),
    make_test_node(
      name="verbose",
      help="Enable verbose output",
      shorts=[{ char: 'v' }],
      global=true,
    ),
    make_test_node(
      name="secret",
      help="Hidden",
      visibility=@core.Visibility::Hidden,
    ),
    make_test_node(
      name="old",
      help="Old option",
      visibility=@core.Visibility::Deprecated,
    ),
    make_test_node(
      name="trace",
      help="Trace mode",
      visibility=@core.Visibility::Advanced,
    ),
  ]
  let result = @output.format_help(
    nodes,
    program_name="myapp",
    description="A multi-purpose CLI tool",
  )
  let expected =
    #|Usage: myapp [OPTIONS] [COMMAND] [FILE]
    #|
    #|A multi-purpose CLI tool
    #|
    #|Commands:
    #|  serve    Start the server
    #|
    #|Arguments:
    #|  <FILE>    Input file
    #|
    #|Options:
    #|  -p, --port <PORT>    Port number
    #|  --old                Old option [deprecated]
    #|
    #|Advanced Options:
    #|  --trace    Trace mode
    #|
    #|Global Options:
    #|  -v, --verbose    Enable verbose output
    #|
    #|Environment Variables:
    #|  PORT    Sets --port
  assert_eq!(result, expected)
}

///|
test "C-01: required positional は <FILE> で表示" {
  let nodes = [
    make_test_node(
      name="input",
      kind=@core.Kind::Positional,
      help="Input file",
      value_name="FILE",
      required=true,
    ),
    make_test_node(
      name="output",
      kind=@core.Kind::Positional,
      help="Output file",
      value_name="OUT",
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp <FILE> [OUT]
    #|
    #|Arguments:
    #|  <FILE>    Input file
    #|  <OUT>     Output file
  assert_eq!(result, expected)
}

///|
test "C-02: aliases のヘルプ表示" {
  let node = make_test_node(
    name="output",
    help="Output file",
    value_name="FILE",
    aliases=[{ name: "out", deprecated: false }, { name: "dest", deprecated: true }],
  )
  let result = @output.format_help([node], program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --output, --out, --dest <FILE>    Output file
  assert_eq!(result, expected)
}

///|
test "C-03: Advanced + global は Advanced Options セクションに表示" {
  let nodes = [
    make_test_node(name="port", help="Port number", value_name="PORT"),
    make_test_node(name="verbose", help="Verbose output", global=true),
    make_test_node(
      name="trace",
      help="Trace mode",
      visibility=@core.Visibility::Advanced,
      global=true,
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [OPTIONS]
    #|
    #|Options:
    #|  --port <PORT>    Port number
    #|
    #|Advanced Options:
    #|  --trace    Trace mode
    #|
    #|Global Options:
    #|  --verbose    Verbose output
  assert_eq!(result, expected)
}

///|
test "C-04: Command の Deprecated 注記" {
  let nodes = [
    make_test_node(
      name="serve",
      kind=@core.Kind::Command,
      help="Start the server",
    ),
    make_test_node(
      name="run",
      kind=@core.Kind::Command,
      help="Old run command",
      visibility=@core.Visibility::Deprecated,
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [COMMAND]
    #|
    #|Commands:
    #|  serve    Start the server
    #|  run      Old run command [deprecated]
  assert_eq!(result, expected)
}

///|
test "C-04: Positional の Deprecated 注記" {
  let nodes = [
    make_test_node(
      name="file",
      kind=@core.Kind::Positional,
      help="Input file",
      value_name="FILE",
    ),
    make_test_node(
      name="old-arg",
      kind=@core.Kind::Positional,
      help="Old argument",
      value_name="OLD",
      visibility=@core.Visibility::Deprecated,
    ),
  ]
  let result = @output.format_help(nodes, program_name="myapp")
  let expected =
    #|Usage: myapp [FILE] [OLD]
    #|
    #|Arguments:
    #|  <FILE>    Input file
    #|  <OLD>     Old argument [deprecated]
  assert_eq!(result, expected)
}

///|
test "program_name なしでは Usage 行を省略" {
  let node = make_test_node(name="verbose", help="Enable verbose output")
  let result = @output.format_help([node])
  let expected =
    #|Options:
    #|  --verbose    Enable verbose output
  assert_eq!(result, expected)
}
