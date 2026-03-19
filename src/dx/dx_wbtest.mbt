///|
/// Phase 1: 基本型テスト — flag, string, int + parse_into

// ---- テスト用 struct ----

///|
struct SimpleConfig {
  mut verbose : Bool
  mut name : String
  mut count : Int
  mut rate : Double
} derive(Show, Eq)

///|
fn SimpleConfig::default() -> SimpleConfig {
  { verbose: false, name: "", count: 0, rate: 0.0 }
}

///|
impl Parseable for SimpleConfig with register(self, reg) {
  reg.flag(name="verbose", set=fn(v) { self.verbose = v })
  reg.string(name="name", set=fn(v) { self.name = v })
  reg.int(name="count", set=fn(v) { self.count = v })
  reg.float(name="rate", set=fn(v) { self.rate = v })
}

// ---- flag テスト ----

///|
test "flag: --verbose sets true" {
  let config = SimpleConfig::default()
  parse_into(["--verbose"], config)
  assert_eq(config.verbose, true)
}

///|
test "flag: default is false" {
  let config = SimpleConfig::default()
  parse_into([], config)
  assert_eq(config.verbose, false)
}

// ---- string テスト ----

///|
test "string: --name sets value" {
  let config = SimpleConfig::default()
  parse_into(["--name", "alice"], config)
  assert_eq(config.name, "alice")
}

///|
test "string: default is empty" {
  let config = SimpleConfig::default()
  parse_into([], config)
  assert_eq(config.name, "")
}

// ---- int テスト ----

///|
test "int: --count sets value" {
  let config = SimpleConfig::default()
  parse_into(["--count", "42"], config)
  assert_eq(config.count, 42)
}

///|
test "int: default is 0" {
  let config = SimpleConfig::default()
  parse_into([], config)
  assert_eq(config.count, 0)
}

// ---- boolean テスト ----

///|
struct BoolConfig {
  mut debug : Bool
} derive(Show, Eq)

///|
fn BoolConfig::default() -> BoolConfig {
  { debug: false }
}

///|
impl Parseable for BoolConfig with register(self, reg) {
  reg.boolean(name="debug", set=fn(v) { self.debug = v })
}

///|
test "boolean: --debug true" {
  let config = BoolConfig::default()
  parse_into(["--debug", "true"], config)
  assert_eq(config.debug, true)
}

///|
test "boolean: --debug off" {
  let config = BoolConfig::default()
  parse_into(["--debug", "off"], config)
  assert_eq(config.debug, false)
}

///|
test "boolean: default is false" {
  let config = BoolConfig::default()
  parse_into([], config)
  assert_eq(config.debug, false)
}

// ---- float テスト ----

///|
test "float: --rate sets value" {
  let config = SimpleConfig::default()
  parse_into(["--rate", "3.14"], config)
  assert_eq(config.rate, 3.14)
}

///|
test "float: default is 0.0" {
  let config = SimpleConfig::default()
  parse_into([], config)
  assert_eq(config.rate, 0.0)
}

// ---- 複合テスト ----

///|
test "all options together" {
  let config = SimpleConfig::default()
  parse_into(
    ["--verbose", "--name", "bob", "--count", "5", "--rate", "2.5"],
    config,
  )
  assert_eq(config.verbose, true)
  assert_eq(config.name, "bob")
  assert_eq(config.count, 5)
  assert_eq(config.rate, 2.5)
}

// ---- エラー安全性テスト ----

///|
test "parse error leaves struct at default" {
  let config = SimpleConfig::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into(
    ["--unknown"],
    config,
  )
  // パースエラーなので struct は初期値のまま
  assert_true(result is Err(_))
  assert_eq(config.verbose, false)
  assert_eq(config.name, "")
  assert_eq(config.count, 0)
  assert_eq(config.rate, 0.0)
}

// ---- default パラメータテスト ----

///|
struct WithDefaults {
  mut host : String
  mut port : Int
  mut timeout : Double
} derive(Show, Eq)

///|
fn WithDefaults::default() -> WithDefaults {
  { host: "localhost", port: 8080, timeout: 30.0 }
}

///|
impl Parseable for WithDefaults with register(self, reg) {
  reg.string(name="host", default="localhost", set=fn(v) { self.host = v })
  reg.int(name="port", default=8080, set=fn(v) { self.port = v })
  reg.float(name="timeout", default=30.0, set=fn(v) { self.timeout = v })
}

///|
test "string/int/float with default: unset keeps struct default" {
  let config = WithDefaults::default()
  parse_into([], config)
  assert_eq(config.host, "localhost")
  assert_eq(config.port, 8080)
  assert_eq(config.timeout, 30.0)
}

///|
test "string/int/float with default: explicit value overrides" {
  let config = WithDefaults::default()
  parse_into(
    ["--host", "example.com", "--port", "3000", "--timeout", "5.5"],
    config,
  )
  assert_eq(config.host, "example.com")
  assert_eq(config.port, 3000)
  assert_eq(config.timeout, 5.5)
}

// ============================================================
// Phase 2: count, append, positional, rest, sub, require_cmd
// ============================================================

// ---- count テスト ----

///|
struct CountConfig {
  mut verbosity : Int
} derive(Show, Eq)

///|
fn CountConfig::default() -> CountConfig {
  { verbosity: 0 }
}

///|
impl Parseable for CountConfig with register(self, reg) {
  reg.count(name="verbose", set=fn(v) { self.verbosity = v })
}

///|
test "count: multiple --verbose increments" {
  let config = CountConfig::default()
  parse_into(["--verbose", "--verbose", "--verbose"], config)
  assert_eq(config.verbosity, 3)
}

///|
test "count: default is 0" {
  let config = CountConfig::default()
  parse_into([], config)
  assert_eq(config.verbosity, 0)
}

// ---- append テスト ----

///|
struct AppendConfig {
  mut tags : Array[String]
  mut ports : Array[Int]
  mut scores : Array[Double]
} derive(Show, Eq)

///|
fn AppendConfig::default() -> AppendConfig {
  { tags: [], ports: [], scores: [] }
}

///|
impl Parseable for AppendConfig with register(self, reg) {
  reg.append_string(name="tag", set=fn(v) { self.tags = v })
  reg.append_int(name="port", set=fn(v) { self.ports = v })
  reg.append_float(name="score", set=fn(v) { self.scores = v })
}

///|
test "append_string: multiple --tag collects values" {
  let config = AppendConfig::default()
  parse_into(["--tag", "a", "--tag", "b"], config)
  assert_eq(config.tags, ["a", "b"])
}

///|
test "append_int: multiple --port collects values" {
  let config = AppendConfig::default()
  parse_into(["--port", "80", "--port", "443"], config)
  assert_eq(config.ports, [80, 443])
}

///|
test "append_float: multiple --score collects values" {
  let config = AppendConfig::default()
  parse_into(["--score", "1.5", "--score", "2.7"], config)
  assert_eq(config.scores, [1.5, 2.7])
}

// ---- positional テスト ----

///|
struct PosConfig {
  mut file : String?
} derive(Show, Eq)

///|
fn PosConfig::default() -> PosConfig {
  { file: None }
}

///|
impl Parseable for PosConfig with register(self, reg) {
  reg.positional(name="FILE", set=fn(v) { self.file = Some(v) })
}

///|
test "positional: captures first arg" {
  let config = PosConfig::default()
  parse_into(["hello.txt"], config)
  assert_eq(config.file, Some("hello.txt"))
}

///|
test "positional: unset keeps None" {
  let config = PosConfig::default()
  parse_into([], config)
  assert_eq(config.file, None)
}

// ---- rest テスト ----

///|
struct RestConfig {
  mut args : Array[String]
} derive(Show, Eq)

///|
fn RestConfig::default() -> RestConfig {
  { args: [] }
}

///|
impl Parseable for RestConfig with register(self, reg) {
  reg.rest(name="ARGS", set=fn(v) { self.args = v })
}

///|
test "rest: collects remaining args" {
  let config = RestConfig::default()
  parse_into(["a", "b", "c"], config)
  assert_eq(config.args, ["a", "b", "c"])
}

///|
test "rest: unset preserves struct default" {
  let config : RestConfig = { args: ["pre-populated"] }
  parse_into([], config)
  // rest 未指定時は set を呼ばず、struct のデフォルトを維持する
  assert_eq(config.args, ["pre-populated"])
}

// ---- sub + require_cmd テスト ----

///|
enum SubCommand {
  Init
  Build
  None
} derive(Show, Eq)

///|
struct SubConfig {
  mut verbose : Bool
  mut command : SubCommand
  mut build_tag : String
} derive(Show, Eq)

///|
fn SubConfig::default() -> SubConfig {
  { verbose: false, command: None, build_tag: "latest" }
}

///|
impl Parseable for SubConfig with register(self, reg) {
  reg.flag(name="verbose", global=true, set=fn(v) { self.verbose = v })
  reg.sub(
    name="init",
    description="Initialize project",
    on_match=fn() { self.command = Init },
    setup=fn(_r) {  },
  )
  reg.sub(
    name="build",
    description="Build project",
    on_match=fn() { self.command = Build },
    setup=fn(r) {
      r.string(name="tag", default="latest", set=fn(v) { self.build_tag = v })
    },
  )
  reg.require_cmd()
}

///|
test "sub: init subcommand" {
  let config = SubConfig::default()
  parse_into(["init"], config)
  assert_eq(config.command, Init)
}

///|
test "sub: build with option" {
  let config = SubConfig::default()
  parse_into(["build", "--tag", "v1.0"], config)
  assert_eq(config.command, Build)
  assert_eq(config.build_tag, "v1.0")
}

///|
test "sub: global flag with subcommand" {
  let config = SubConfig::default()
  parse_into(["--verbose", "build"], config)
  assert_eq(config.verbose, true)
  assert_eq(config.command, Build)
}

///|
test "sub: require_cmd errors without subcommand" {
  let config = SubConfig::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into([], config)
  assert_true(result is Err(_))
}

///|
test "sub: unselected subcommand state untouched" {
  let config = SubConfig::default()
  parse_into(["init"], config)
  assert_eq(config.command, Init)
  assert_eq(config.build_tag, "latest") // build は未選択なのでデフォルト
}

// ---- set_description テスト ----

///|
struct DescConfig {
  mut name : String
} derive(Show, Eq)

///|
fn DescConfig::default() -> DescConfig {
  { name: "" }
}

///|
impl Parseable for DescConfig with register(self, reg) {
  reg.set_description("A test CLI tool")
  reg.string(name="name", set=fn(v) { self.name = v })
}

///|
test "set_description: does not affect parsing" {
  let config = DescConfig::default()
  parse_into(["--name", "test"], config)
  assert_eq(config.name, "test")
}

// ============================================================
// Phase 3: パラメータ拡充テスト (shorts, aliases, env, hidden)
// ============================================================

///|
struct ShortsConfig {
  mut verbose : Bool
  mut output : String
} derive(Show, Eq)

///|
fn ShortsConfig::default() -> ShortsConfig {
  { verbose: false, output: "" }
}

///|
impl Parseable for ShortsConfig with register(self, reg) {
  reg.flag(name="verbose", shorts="v", set=fn(v) { self.verbose = v })
  reg.custom(
    name="output",
    default="",
    shorts="o",
    pre=@core.Filter::map(fn(s) { s }),
    set=fn(v) { self.output = v },
  )
}

///|
test "shorts: -v sets verbose" {
  let config = ShortsConfig::default()
  parse_into(["-v"], config)
  assert_eq(config.verbose, true)
}

///|
test "shorts: -o sets output" {
  let config = ShortsConfig::default()
  parse_into(["-o", "file.txt"], config)
  assert_eq(config.output, "file.txt")
}

// ---- aliases テスト ----

///|
struct AliasConfig {
  mut color : String
} derive(Show, Eq)

///|
fn AliasConfig::default() -> AliasConfig {
  { color: "" }
}

///|
impl Parseable for AliasConfig with register(self, reg) {
  reg.custom(
    name="color",
    default="",
    aliases=["colour"],
    pre=@core.Filter::map(fn(s) { s }),
    set=fn(v) { self.color = v },
  )
}

///|
test "aliases: --colour works as alias for --color" {
  let config = AliasConfig::default()
  parse_into(["--colour", "red"], config)
  assert_eq(config.color, "red")
}

// ---- env テスト ----

///|
struct EnvConfig {
  mut host : String
} derive(Show, Eq)

///|
fn EnvConfig::default() -> EnvConfig {
  { host: "" }
}

///|
impl Parseable for EnvConfig with register(self, reg) {
  reg.string(name="host", env="APP_HOST", set=fn(v) { self.host = v })
}

///|
test "env: env parameter does not affect parsing" {
  // env はヘルプ表示用メタデータのみ（Phase 1 DR-041）。パース動作には影響しない。
  let config = EnvConfig::default()
  parse_into(["--host", "example.com"], config)
  assert_eq(config.host, "example.com")
}

// ---- hidden テスト ----

///|
struct HiddenConfig {
  mut debug : Bool
  mut name : String
} derive(Show, Eq)

///|
fn HiddenConfig::default() -> HiddenConfig {
  { debug: false, name: "" }
}

///|
impl Parseable for HiddenConfig with register(self, reg) {
  reg.flag(name="debug", hidden=true, set=fn(v) { self.debug = v })
  reg.string(name="name", set=fn(v) { self.name = v })
}

///|
test "hidden: hidden flag still works for parsing" {
  let config = HiddenConfig::default()
  parse_into(["--debug"], config)
  assert_eq(config.debug, true)
}

// ---- sub aliases テスト ----

///|
struct SubAliasConfig {
  mut command : String
} derive(Show, Eq)

///|
fn SubAliasConfig::default() -> SubAliasConfig {
  { command: "" }
}

///|
impl Parseable for SubAliasConfig with register(self, reg) {
  reg.sub(
    name="install",
    aliases=["i"],
    on_match=fn() { self.command = "install" },
    setup=fn(_r) {  },
  )
  reg.require_cmd()
}

///|
test "sub aliases: alias 'i' matches install" {
  let config = SubAliasConfig::default()
  parse_into(["i"], config)
  assert_eq(config.command, "install")
}

// ---- value_name テスト ----

///|
struct ValueNameConfig {
  mut file : String
} derive(Show, Eq)

///|
fn ValueNameConfig::default() -> ValueNameConfig {
  { file: "" }
}

///|
impl Parseable for ValueNameConfig with register(self, reg) {
  reg.string(name="file", value_name="PATH", set=fn(v) { self.file = v })
}

///|
test "value_name: does not affect parsing" {
  let config = ValueNameConfig::default()
  parse_into(["--file", "test.txt"], config)
  assert_eq(config.file, "test.txt")
}

// ============================================================
// Phase 4: 高度機能テスト (custom, constraints)
// ============================================================

// ---- exclusive 制約テスト ----

///|
struct ExclusiveConfig {
  mut json : Bool
  mut yaml : Bool
} derive(Show, Eq)

///|
fn ExclusiveConfig::default() -> ExclusiveConfig {
  { json: false, yaml: false }
}

///|
impl Parseable for ExclusiveConfig with register(self, reg) {
  let json_ref = reg.flag_ref(name="json", set=fn(v) { self.json = v })
  let yaml_ref = reg.flag_ref(name="yaml", set=fn(v) { self.yaml = v })
  reg.exclusive([json_ref, yaml_ref])
}

///|
test "exclusive: single option is ok" {
  let config = ExclusiveConfig::default()
  parse_into(["--json"], config)
  assert_eq(config.json, true)
  assert_eq(config.yaml, false)
}

///|
test "exclusive: both options is error" {
  let config = ExclusiveConfig::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into(
    ["--json", "--yaml"],
    config,
  )
  assert_true(result is Err(_))
}

// ---- required 制約テスト ----

///|
struct RequiredConfig {
  mut output : String
} derive(Show, Eq)

///|
fn RequiredConfig::default() -> RequiredConfig {
  { output: "" }
}

///|
impl Parseable for RequiredConfig with register(self, reg) {
  let output_ref = reg.string_ref(name="output", set=fn(v) { self.output = v })
  reg.required(output_ref)
}

///|
test "required: provided is ok" {
  let config = RequiredConfig::default()
  parse_into(["--output", "file.txt"], config)
  assert_eq(config.output, "file.txt")
}

///|
test "required: missing is error" {
  let config = RequiredConfig::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into([], config)
  assert_true(result is Err(_))
}

// ---- at_least_one 制約テスト ----

///|
struct AtLeastOneConfig {
  mut input : String
  mut stdin : Bool
} derive(Show, Eq)

///|
fn AtLeastOneConfig::default() -> AtLeastOneConfig {
  { input: "", stdin: false }
}

///|
impl Parseable for AtLeastOneConfig with register(self, reg) {
  let input_ref = reg.string_ref(name="input", set=fn(v) { self.input = v })
  let stdin_ref = reg.flag_ref(name="stdin", set=fn(v) { self.stdin = v })
  reg.at_least_one([input_ref, stdin_ref])
}

///|
test "at_least_one: one provided is ok" {
  let config = AtLeastOneConfig::default()
  parse_into(["--stdin"], config)
  assert_eq(config.stdin, true)
}

///|
test "at_least_one: none is error" {
  let config = AtLeastOneConfig::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into([], config)
  assert_true(result is Err(_))
}

// ---- custom[T] テスト ----

///|
enum LogLevel {
  Debug
  Info
  Warn
  Error_
} derive(Show, Eq)

///|
fn LogLevel::from_string(s : String) -> LogLevel raise @core.ParseError {
  match s {
    "debug" => Debug
    "info" => Info
    "warn" => Warn
    "error" => Error_
    _ =>
      raise @core.ParseError(@core.ParseErrorInfo::{
        kind: InvalidValue,
        message: "invalid log level: \{s}",
        help_text: "",
        opt_name: "",
        tip: "",
      })
  }
}

///|
struct CustomConfig {
  mut level : LogLevel
} derive(Show, Eq)

///|
fn CustomConfig::default() -> CustomConfig {
  { level: Info }
}

///|
impl Parseable for CustomConfig with register(self, reg) {
  reg.custom(
    name="level",
    default=LogLevel::Info,
    pre={ run: LogLevel::from_string },
    set=fn(v) { self.level = v },
  )
}

///|
test "custom: parses custom type" {
  let config = CustomConfig::default()
  parse_into(["--level", "debug"], config)
  assert_eq(config.level, Debug)
}

///|
test "custom: invalid value is error" {
  let config = CustomConfig::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into(
    ["--level", "invalid"],
    config,
  )
  assert_true(result is Err(_))
}

// ============================================================
// Phase 4 追加テスト
// ============================================================

// ---- custom_append テスト ----

///|
struct CustomAppendConfig {
  mut values : Array[Int]
} derive(Show, Eq)

///|
fn CustomAppendConfig::default() -> CustomAppendConfig {
  { values: [] }
}

///|
impl Parseable for CustomAppendConfig with register(self, reg) {
  reg.custom_append(name="value", pre=@core.Filter::parse_int(), set=fn(v) {
    self.values = v
  })
}

///|
test "custom_append: collects parsed values" {
  let config = CustomAppendConfig::default()
  parse_into(["--value", "1", "--value", "2", "--value", "3"], config)
  assert_eq(config.values, [1, 2, 3])
}

// ---- default 二重管理の修正検証テスト ----

///|
struct DefaultMismatchConfig {
  mut host : String
} derive(Show, Eq)

///|
fn DefaultMismatchConfig::default() -> DefaultMismatchConfig {
  { host: "my-default" }
}

///|
impl Parseable for DefaultMismatchConfig with register(self, reg) {
  // registry の default と struct の default が異なる
  // struct の default が source of truth であるべき
  reg.string(name="host", default="registry-default", set=fn(v) {
    self.host = v
  })
}

///|
test "default: struct default preserved when option not specified" {
  let config = DefaultMismatchConfig::default()
  parse_into([], config)
  // struct の default "my-default" が維持される（registry の "registry-default" で上書きされない）
  assert_eq(config.host, "my-default")
}

///|
test "default: explicit value overrides struct default" {
  let config = DefaultMismatchConfig::default()
  parse_into(["--host", "explicit"], config)
  assert_eq(config.host, "explicit")
}

// ---- ネストサブコマンドテスト ----

///|
struct NestedConfig {
  mut cmd1 : String
  mut cmd2 : String
  mut value : String
} derive(Show, Eq)

///|
fn NestedConfig::default() -> NestedConfig {
  { cmd1: "", cmd2: "", value: "" }
}

///|
impl Parseable for NestedConfig with register(self, reg) {
  reg.sub(name="parent", on_match=fn() { self.cmd1 = "parent" }, setup=fn(r) {
    r.sub(name="child", on_match=fn() { self.cmd2 = "child" }, setup=fn(r2) {
      r2.string(name="value", set=fn(v) { self.value = v })
    })
    r.require_cmd()
  })
  reg.require_cmd()
}

///|
test "nested sub: grandchild subcommand works" {
  let config = NestedConfig::default()
  parse_into(["parent", "child", "--value", "hello"], config)
  assert_eq(config.cmd1, "parent")
  assert_eq(config.cmd2, "child")
  assert_eq(config.value, "hello")
}

// ---- エラーメッセージ内容テスト ----

///|
test "error message: exclusive violation mentions option names" {
  let config = ExclusiveConfig::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into(
    ["--json", "--yaml"],
    config,
  )
  match result {
    Err(@core.ParseError(info)) =>
      assert_true(
        info.message.contains("exclusive") ||
        info.message.contains("--json") ||
        info.message.contains("--yaml"),
      )
    _ => fail("expected ParseError")
  }
}
