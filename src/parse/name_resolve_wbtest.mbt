// --- resolve_long テスト ---

///|
test "resolve_long: 完全一致（meta.name と一致）" {
  let meta : @core.OptMeta = {
    name: "port",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "PORT",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(resolve_long("port", meta), ExactMatch)
}

///|
test "resolve_long: エイリアス一致" {
  let meta : @core.OptMeta = {
    name: "port",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [{ name: "p", deprecated: false }, { name: "listen-port", deprecated: false }],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "PORT",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(resolve_long("listen-port", meta), ExactMatch)
}

///|
test "resolve_long: No 反転一致" {
  let meta : @core.OptMeta = {
    name: "verbose",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: Some(@core.FlagInversion::No),
    env: None,
    auto_env: None,
    choices: [],
    value_name: "",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(resolve_long("no-verbose", meta), NegateMatch)
}

///|
test "resolve_long: EnableDisable 反転 - enable は ExactMatch" {
  let meta : @core.OptMeta = {
    name: "color",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: Some(@core.FlagInversion::EnableDisable),
    env: None,
    auto_env: None,
    choices: [],
    value_name: "",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(resolve_long("enable-color", meta), ExactMatch)
  assert_eq(resolve_long("disable-color", meta), NegateMatch)
}

///|
test "resolve_long: Custom 反転" {
  let meta : @core.OptMeta = {
    name: "feature",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: Some(@core.FlagInversion::Custom("with", "without")),
    env: None,
    auto_env: None,
    choices: [],
    value_name: "",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(resolve_long("with-feature", meta), ExactMatch)
  assert_eq(resolve_long("without-feature", meta), NegateMatch)
}

///|
test "resolve_long: プレフィックス一致" {
  let meta : @core.OptMeta = {
    name: "verbose",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
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
  assert_eq(resolve_long("verb", meta), PrefixMatch)
  assert_eq(resolve_long("v", meta), PrefixMatch)
}

///|
test "resolve_long: プレフィックス一致 - エイリアスに対しても" {
  let meta : @core.OptMeta = {
    name: "port",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [{ name: "listen-port", deprecated: false }],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "PORT",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(resolve_long("listen", meta), PrefixMatch)
}

///|
test "resolve_long: 完全一致の長さではプレフィックスにならない" {
  let meta : @core.OptMeta = {
    name: "port",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "PORT",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  // "port" は完全一致であり PrefixMatch ではない
  assert_eq(resolve_long("port", meta), ExactMatch)
}

///|
test "resolve_long: 不一致" {
  let meta : @core.OptMeta = {
    name: "port",
    kind: @core.Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "PORT",
    required: false,
    visibility: @core.Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(resolve_long("host", meta), NoMatch)
  assert_eq(resolve_long("porty", meta), NoMatch)
}

// --- resolve_short テスト ---

///|
test "resolve_short: 一致" {
  let meta : @core.OptMeta = {
    name: "verbose",
    kind: @core.Kind::Option,
    help: "",
    shorts: [{ char: 'v' }, { char: 'V' }],
    aliases: [],
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
  assert_true(resolve_short('v', meta))
  assert_true(resolve_short('V', meta))
}

///|
test "resolve_short: 不一致" {
  let meta : @core.OptMeta = {
    name: "verbose",
    kind: @core.Kind::Option,
    help: "",
    shorts: [{ char: 'v' }],
    aliases: [],
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
  assert_false(resolve_short('x', meta))
}
