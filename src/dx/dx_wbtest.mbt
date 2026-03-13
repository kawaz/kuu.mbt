///|
/// Phase 1: 基本型テスト — flag, string, int + parse_into

// ---- テスト用 struct ----

///|
struct SimpleConfig {
  mut verbose : Bool
  mut name : String
  mut count : Int
} derive(Show, Eq)

///|
fn SimpleConfig::default() -> SimpleConfig {
  { verbose: false, name: "", count: 0 }
}

///|
impl Parseable for SimpleConfig with register(self, reg) {
  reg.flag(name="verbose", apply_fn=fn(v) { self.verbose = v })
  reg.string(name="name", apply_fn=fn(v) { self.name = v })
  reg.int(name="count", apply_fn=fn(v) { self.count = v })
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

// ---- 複合テスト ----

///|
test "all options together" {
  let config = SimpleConfig::default()
  parse_into(["--verbose", "--name", "bob", "--count", "5"], config)
  assert_eq(config.verbose, true)
  assert_eq(config.name, "bob")
  assert_eq(config.count, 5)
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
}

// ---- default パラメータテスト ----

///|
struct WithDefaults {
  mut host : String
  mut port : Int
} derive(Show, Eq)

///|
fn WithDefaults::default() -> WithDefaults {
  { host: "localhost", port: 8080 }
}

///|
impl Parseable for WithDefaults with register(self, reg) {
  reg.string(
    name="host",
    default="localhost",
    apply_fn=fn(v) { self.host = v },
  )
  reg.int(name="port", default=8080, apply_fn=fn(v) { self.port = v })
}

///|
test "string/int with default: unset keeps struct default" {
  let config = WithDefaults::default()
  parse_into([], config)
  assert_eq(config.host, "localhost")
  assert_eq(config.port, 8080)
}

///|
test "string/int with default: explicit value overrides" {
  let config = WithDefaults::default()
  parse_into(["--host", "example.com", "--port", "3000"], config)
  assert_eq(config.host, "example.com")
  assert_eq(config.port, 3000)
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
  reg.count(name="verbose", apply_fn=fn(v) { self.verbosity = v })
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
} derive(Show, Eq)

///|
fn AppendConfig::default() -> AppendConfig {
  { tags: [], ports: [] }
}

///|
impl Parseable for AppendConfig with register(self, reg) {
  reg.append_string(name="tag", apply_fn=fn(v) { self.tags = v })
  reg.append_int(name="port", apply_fn=fn(v) { self.ports = v })
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
  reg.positional(name="FILE", apply_fn=fn(v) { self.file = v })
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
  reg.rest(name="ARGS", apply_fn=fn(v) { self.args = v })
}

///|
test "rest: collects remaining args" {
  let config = RestConfig::default()
  parse_into(["a", "b", "c"], config)
  assert_eq(config.args, ["a", "b", "c"])
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
  reg.flag(
    name="verbose",
    global=true,
    apply_fn=fn(v) { self.verbose = v },
  )
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
      r.string(
        name="tag",
        default="latest",
        apply_fn=fn(v) { self.build_tag = v },
      )
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
  reg.string(name="name", apply_fn=fn(v) { self.name = v })
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
  reg.flag(
    name="verbose",
    shorts="v",
    apply_fn=fn(v) { self.verbose = v },
  )
  reg.string(
    name="output",
    shorts="o",
    apply_fn=fn(v) { self.output = v },
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
  reg.string(
    name="color",
    aliases=["colour"],
    apply_fn=fn(v) { self.color = v },
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
  reg.string(
    name="host",
    env="APP_HOST",
    apply_fn=fn(v) { self.host = v },
  )
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
  reg.flag(
    name="debug",
    hidden=true,
    apply_fn=fn(v) { self.debug = v },
  )
  reg.string(name="name", apply_fn=fn(v) { self.name = v })
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
  reg.string(
    name="file",
    value_name="PATH",
    apply_fn=fn(v) { self.file = v },
  )
}

///|
test "value_name: does not affect parsing" {
  let config = ValueNameConfig::default()
  parse_into(["--file", "test.txt"], config)
  assert_eq(config.file, "test.txt")
}
