///|
test "UnknownOption の基本フォーマット" {
  let err = @core.ParseError::Usage(
    @core.ErrorKind::UnknownOption,
    "unknown option '--foo'",
    { option_name: "foo" },
  )
  let result = @output.format_error(err)
  assert_eq!(result, "error: unknown option '--foo'")
}

///|
test "did-you-mean サジェスト（--prot → --port）" {
  let node = make_option_node("port", [])
  let err = @core.ParseError::Usage(
    @core.ErrorKind::UnknownOption,
    "unknown option '--prot'",
    { option_name: "prot" },
  )
  let result = @output.format_error(err, nodes=[node])
  assert_eq!(
    result,
    "error: unknown option '--prot'\n  tip: a similar option exists: '--port'",
  )
}

///|
test "サジェスト候補なし（距離が遠すぎる）" {
  let node = make_option_node("verbose", [])
  let err = @core.ParseError::Usage(
    @core.ErrorKind::UnknownOption,
    "unknown option '--xyz'",
    { option_name: "xyz" },
  )
  let result = @output.format_error(err, nodes=[node])
  assert_eq!(result, "error: unknown option '--xyz'")
}

///|
test "MissingRequired のフォーマット" {
  let err = @core.ParseError::Usage(
    @core.ErrorKind::MissingRequired,
    "missing required option '--config'",
    { option_name: "config" },
  )
  let result = @output.format_error(err)
  assert_eq!(result, "error: missing required option '--config'")
}

///|
test "InvalidValue のフォーマット" {
  let err = @core.ParseError::Usage(
    @core.ErrorKind::InvalidValue,
    "invalid value 'abc' for '--port': expected integer",
    { option_name: "port" },
  )
  let result = @output.format_error(err)
  assert_eq!(
    result,
    "error: invalid value 'abc' for '--port': expected integer",
  )
}

///|
test "Internal エラーのフォーマット" {
  let err = @core.ParseError::Internal("unexpected state")
  let result = @output.format_error(err)
  assert_eq!(result, "internal error: unexpected state")
}

///|
test "program_name 付きの Usage 行表示" {
  let err = @core.ParseError::Usage(
    @core.ErrorKind::UnknownOption,
    "unknown option '--foo'",
    { option_name: "foo" },
  )
  let result = @output.format_error(err, program_name="myapp serve")
  assert_eq!(
    result,
    "error: unknown option '--foo'\nUsage: myapp serve [OPTIONS]",
  )
}

///|
test "AmbiguousMatch では did-you-mean は表示しない" {
  let node = make_option_node("verbose", [])
  let err = @core.ParseError::Usage(
    @core.ErrorKind::AmbiguousMatch,
    "ambiguous option '--verb'",
    { option_name: "verb" },
  )
  let result = @output.format_error(err, nodes=[node])
  // AmbiguousMatch はプレフィックス一致の問題であり、did-you-mean は不適切
  assert_eq!(result, "error: ambiguous option '--verb'")
}

///| テスト用ヘルパー: 最小限の ErasedNode を作成
fn make_option_node(
  name : String,
  aliases : Array[String]
) -> @core.ErasedNode {
  let alias_entries : Array[@core.AliasEntry] = aliases.map(
    fn(a) { { name: a, deprecated: false } },
  )
  let meta : @core.OptMeta = {
    name,
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: alias_entries,
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  let dummy_result_map : @core.ResultMap = { id: 0, clone_fns: {} }
  ignore(dummy_result_map)
  {
    meta,
    try_reduce: fn(_action, _rm) { @core.TryReduceResult::Reject },
    commit_reduce: fn(_result, _rm) {  },
    reset_to_initial: fn(_rm) {  },
    is_set: fn() { false },
    children: fn() { [] },
  }
}
