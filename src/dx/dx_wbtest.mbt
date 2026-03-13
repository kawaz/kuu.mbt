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
