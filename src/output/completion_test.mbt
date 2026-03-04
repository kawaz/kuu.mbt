///| テスト用ヘルパー: 補完テスト用の ErasedNode を作成
fn make_completion_node(
  name~ : String,
  kind~ : @core.Kind = Option,
  help~ : String = "",
  shorts~ : Array[@core.ShortEntry] = [],
  aliases~ : Array[@core.AliasEntry] = [],
  inversion~ : @core.FlagInversion? = None,
  visibility~ : @core.Visibility = Visible,
  choices~ : Array[String] = [],
) -> @core.ErasedNode {
  let meta : @core.OptMeta = {
    name,
    kind,
    help,
    shorts,
    aliases,
    inversion,
    env: None,
    auto_env: None,
    choices,
    value_name: "",
    required: false,
    visibility,
    global: false,
    greedy: false,
  }
  {
    meta,
    try_reduce: fn(_action, _rm) { @core.TryReduceResult::Reject },
    commit_reduce: fn(_result, _rm) {  },
    reset_to_initial: fn(_rm) {  },
    is_set: fn() { false },
    children: fn() { [] },
  }
}

///|
test "1. 空ノードリスト -> 空の候補" {
  let result = @output.collect_completions([])
  assert_eq!(result, [])
}

///|
test "2. 基本的な Option -> --name 候補" {
  let node = make_completion_node(name="port", help="Port number")
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [{ value: "--port", description: "Port number" }],
  )
}

///|
test "3. shorts 付き Option -> -v と --verbose 両方" {
  let node = make_completion_node(
    name="verbose",
    help="Enable verbose output",
    shorts=[{ char: 'v' }],
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [
      { value: "--verbose", description: "Enable verbose output" },
      { value: "-v", description: "Enable verbose output" },
    ],
  )
}

///|
test "4. aliases 付き Option -> deprecated は除外" {
  let node = make_completion_node(
    name="output",
    help="Output file",
    aliases=[
      { name: "out", deprecated: false },
      { name: "dest", deprecated: true },
    ],
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [
      { value: "--output", description: "Output file" },
      { value: "--out", description: "Output file" },
    ],
  )
}

///|
test "5. inversion (No) -> --name と --no-name" {
  let node = make_completion_node(
    name="color",
    help="Enable color",
    inversion=Some(@core.FlagInversion::No),
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [
      { value: "--color", description: "Enable color" },
      { value: "--no-color", description: "Enable color" },
    ],
  )
}

///|
test "6. inversion (EnableDisable) -> --enable-name と --disable-name" {
  let node = make_completion_node(
    name="color",
    help="Enable color output",
    inversion=Some(@core.FlagInversion::EnableDisable),
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [
      { value: "--color", description: "Enable color output" },
      { value: "--enable-color", description: "Enable color output" },
      { value: "--disable-color", description: "Enable color output" },
    ],
  )
}

///|
test "7. Command -> サブコマンド名" {
  let node = make_completion_node(
    name="serve",
    kind=@core.Kind::Command,
    help="Start the server",
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [{ value: "serve", description: "Start the server" }],
  )
}

///|
test "8. Positional -> 候補なし" {
  let node = make_completion_node(
    name="file",
    kind=@core.Kind::Positional,
    help="Input file",
  )
  let result = @output.collect_completions([node])
  assert_eq!(result, [])
}

///|
test "9. Hidden -> 除外" {
  let node = make_completion_node(
    name="secret",
    help="Secret option",
    visibility=@core.Visibility::Hidden,
  )
  let result = @output.collect_completions([node])
  assert_eq!(result, [])
}

///|
test "10. Deprecated -> 候補に含む" {
  let node = make_completion_node(
    name="old-flag",
    help="Old flag",
    visibility=@core.Visibility::Deprecated,
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [{ value: "--old-flag", description: "Old flag" }],
  )
}

///|
test "11. Bash format" {
  let candidates : Array[@output.CompletionCandidate] = [
    { value: "--port", description: "Port number" },
    { value: "serve", description: "Start the server" },
  ]
  let result = @output.format_completions(candidates, @output.Shell::Bash)
  assert_eq!(result, "--port\nserve")
}

///|
test "12. Zsh format" {
  let candidates : Array[@output.CompletionCandidate] = [
    { value: "--port", description: "Port number" },
    { value: "serve", description: "Start the server" },
  ]
  let result = @output.format_completions(candidates, @output.Shell::Zsh)
  assert_eq!(result, "--port:Port number\nserve:Start the server")
}

///|
test "13. Fish format" {
  let candidates : Array[@output.CompletionCandidate] = [
    { value: "--port", description: "Port number" },
    { value: "serve", description: "Start the server" },
  ]
  let result = @output.format_completions(candidates, @output.Shell::Fish)
  assert_eq!(result, "--port\tPort number\nserve\tStart the server")
}

///|
test "14. 複合テスト: Options + Commands 混在" {
  let nodes = [
    make_completion_node(
      name="serve",
      kind=@core.Kind::Command,
      help="Start the server",
      aliases=[{ name: "s", deprecated: false }],
    ),
    make_completion_node(
      name="port",
      help="Port number",
      shorts=[{ char: 'p' }],
    ),
    make_completion_node(
      name="verbose",
      help="Enable verbose output",
      inversion=Some(@core.FlagInversion::No),
    ),
    make_completion_node(
      name="file",
      kind=@core.Kind::Positional,
      help="Input file",
    ),
    make_completion_node(
      name="secret",
      help="Hidden",
      visibility=@core.Visibility::Hidden,
    ),
  ]
  let result = @output.collect_completions(nodes)
  assert_eq!(
    result,
    [
      { value: "serve", description: "Start the server" },
      { value: "s", description: "Start the server" },
      { value: "--port", description: "Port number" },
      { value: "-p", description: "Port number" },
      { value: "--verbose", description: "Enable verbose output" },
      { value: "--no-verbose", description: "Enable verbose output" },
    ],
  )
}

///|
test "inversion (Custom) -> --{pos}-{name} と --{neg}-{name}" {
  let node = make_completion_node(
    name="color",
    help="Color output",
    inversion=Some(@core.FlagInversion::Custom("with", "without")),
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [
      { value: "--color", description: "Color output" },
      { value: "--with-color", description: "Color output" },
      { value: "--without-color", description: "Color output" },
    ],
  )
}

///|
test "C-01: Zsh format - description 内の : をエスケープ" {
  let candidates : Array[@output.CompletionCandidate] = [
    { value: "--addr", description: "Address (host:port)" },
  ]
  let result = @output.format_completions(candidates, @output.Shell::Zsh)
  assert_eq!(result, "--addr:Address (host\\:port)")
}

///|
test "C-02: Fish format - description 内のタブと改行をサニタイズ" {
  let candidates : Array[@output.CompletionCandidate] = [
    { value: "--mode", description: "Mode:\tfast\nor slow" },
  ]
  let result = @output.format_completions(candidates, @output.Shell::Fish)
  assert_eq!(result, "--mode\tMode: fastor slow")
}

///|
test "C-03: collect_value_completions - choices がある場合" {
  let node = make_completion_node(
    name="format",
    help="Output format",
    choices=["json", "yaml", "toml"],
  )
  let result = @output.collect_value_completions(node)
  assert_eq!(
    result,
    [
      { value: "json", description: "" },
      { value: "yaml", description: "" },
      { value: "toml", description: "" },
    ],
  )
}

///|
test "C-03b: collect_value_completions - choices が空の場合" {
  let node = make_completion_node(name="port", help="Port number")
  let result = @output.collect_value_completions(node)
  assert_eq!(result, [])
}

///|
test "W-01: deprecated エイリアスは補完候補から除外" {
  let node = make_completion_node(
    name="output",
    help="Output file",
    aliases=[
      { name: "out", deprecated: false },
      { name: "dest", deprecated: true },
      { name: "target", deprecated: false },
    ],
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [
      { value: "--output", description: "Output file" },
      { value: "--out", description: "Output file" },
      { value: "--target", description: "Output file" },
    ],
  )
}

///|
test "W-01: Command の deprecated エイリアスも除外" {
  let node = make_completion_node(
    name="serve",
    kind=@core.Kind::Command,
    help="Start the server",
    aliases=[
      { name: "s", deprecated: false },
      { name: "server", deprecated: true },
    ],
  )
  let result = @output.collect_completions([node])
  assert_eq!(
    result,
    [
      { value: "serve", description: "Start the server" },
      { value: "s", description: "Start the server" },
    ],
  )
}
