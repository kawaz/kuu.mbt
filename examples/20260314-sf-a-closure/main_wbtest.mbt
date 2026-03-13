// struct-first クロージャ Setter 方式の検証テスト

// ── Step 1: mut struct + クロージャキャプチャ ──

test "mut struct fields can be captured and mutated by closures" {
  let config = SimpleConfig::default()
  let set_verbose = fn() { config.verbose = true }
  let set_name = fn(v : String) { config.name = v }
  let set_count = fn(v : Int) { config.count = v }
  inspect(config.verbose, content="false")
  inspect(config.name, content="")
  inspect(config.count, content="0")
  set_verbose()
  set_name("hello")
  set_count(42)
  inspect(config.verbose, content="true")
  inspect(config.name, content="hello")
  inspect(config.count, content="42")
}

test "type-erased closures can modify different struct fields" {
  let config = SimpleConfig::default()
  let setters : Array[() -> Unit] = [
    fn() { config.verbose = true },
    fn() { config.name = "shared" },
    fn() { config.count = 99 },
  ]
  for setter in setters {
    setter()
  }
  inspect(config.verbose, content="true")
  inspect(config.name, content="shared")
  inspect(config.count, content="99")
}

// ── Step 2: StructFirst ラッパーでの kuu 統合 ──

test "StructFirst.flag sets struct field after parse" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.flag(name="verbose", setter=fn(v) { config.verbose = v })
  ignore(sf.parse(["--verbose"]))
  inspect(config.verbose, content="true")
}

test "StructFirst.string_opt sets struct field after parse" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.string_opt(name="name", default="", setter=fn(v) { config.name = v })
  ignore(sf.parse(["--name", "alice"]))
  inspect(config.name, content="alice")
}

test "StructFirst.int_opt sets struct field after parse" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.int_opt(name="count", default=0, setter=fn(v) { config.count = v })
  ignore(sf.parse(["--count", "42"]))
  inspect(config.count, content="42")
}

test "StructFirst with multiple opts" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.flag(name="verbose", setter=fn(v) { config.verbose = v })
  sf.string_opt(name="name", default="", setter=fn(v) { config.name = v })
  sf.int_opt(name="count", default=0, setter=fn(v) { config.count = v })
  ignore(sf.parse(["--verbose", "--name", "bob", "--count", "7"]))
  inspect(config.verbose, content="true")
  inspect(config.name, content="bob")
  inspect(config.count, content="7")
}

test "StructFirst preserves defaults when options not specified" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.flag(name="verbose", setter=fn(v) { config.verbose = v })
  sf.string_opt(
    name="name",
    default="default_name",
    setter=fn(v) { config.name = v },
  )
  sf.int_opt(name="count", default=5, setter=fn(v) { config.count = v })
  ignore(sf.parse([]))
  inspect(config.verbose, content="false")
  inspect(config.name, content="default_name")
  inspect(config.count, content="5")
}

test "StructFirst.count sets struct field after parse" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.count(name="verbose", shorts="v", setter=fn(v) { config.count = v })
  ignore(sf.parse(["-v", "-v", "-v"]))
  inspect(config.count, content="3")
}

test "StructFirst.positional sets struct field after parse" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.positional(name="name", setter=fn(v) { config.name = v })
  ignore(sf.parse(["hello"]))
  inspect(config.name, content="hello")
}

test "StructFirst.rest sets struct field after parse" {
  let result : Array[String] = []
  let sf = StructFirst::new()
  sf.rest(name="args", setter=fn(v) { for item in v { result.push(item) } })
  ignore(sf.parse(["a", "b", "c"]))
  inspect(result, content="[\"a\", \"b\", \"c\"]")
}

test "StructFirst.append_string sets struct field after parse" {
  let result : Array[String] = []
  let sf = StructFirst::new()
  sf.append_string(
    name="file",
    shorts="f",
    setter=fn(v) { for item in v { result.push(item) } },
  )
  ignore(sf.parse(["-f", "a.txt", "-f", "b.txt"]))
  inspect(result, content="[\"a.txt\", \"b.txt\"]")
}

// ── Step 3: サブコマンド + struct ネスト ──

test "Docker-style: run subcommand" {
  let config = DockerConfig::new()
  let sf = StructFirst::new()
  setup_docker_parser(sf, config)
  ignore(sf.parse(["--debug", "run", "-d", "-i", "-t", "ubuntu", "bash"]))
  inspect(config.global.debug, content="true")
  inspect(config.matched_cmd, content="run")
  inspect(config.run.detach, content="true")
  inspect(config.run.interactive, content="true")
  inspect(config.run.tty, content="true")
  inspect(config.run.image, content="ubuntu")
  inspect(config.run.command, content="[\"bash\"]")
}

test "Docker-style: compose up subcommand" {
  let config = DockerConfig::new()
  let sf = StructFirst::new()
  setup_docker_parser(sf, config)
  ignore(
    sf.parse([
      "compose", "-f", "prod.yml", "up", "-d", "--scale", "3", "web", "db",
    ]),
  )
  inspect(config.matched_cmd, content="compose")
  inspect(config.compose.files, content="[\"prod.yml\"]")
  inspect(config.matched_subcmd, content="up")
  inspect(config.compose.up.detach, content="true")
  inspect(config.compose.up.scale, content="3")
  inspect(config.compose.up.services, content="[\"web\", \"db\"]")
}

test "Docker-style: global option propagates to subcommand" {
  let config = DockerConfig::new()
  let sf = StructFirst::new()
  setup_docker_parser(sf, config)
  ignore(sf.parse(["run", "--debug", "ubuntu"]))
  inspect(config.global.debug, content="true")
  inspect(config.run.image, content="ubuntu")
}

// ── Step 4: エッジケース ──

test "nested struct fields can be mutated through closures" {
  let config = DockerConfig::new()
  let setters : Array[() -> Unit] = [
    fn() { config.global.debug = true },
    fn() { config.run.image = "alpine" },
    fn() { config.compose.up.scale = 10 },
  ]
  for setter in setters {
    setter()
  }
  inspect(config.global.debug, content="true")
  inspect(config.run.image, content="alpine")
  inspect(config.compose.up.scale, content="10")
}

test "Docker-style: run with no flags (minimal)" {
  let config = DockerConfig::new()
  let sf = StructFirst::new()
  setup_docker_parser(sf, config)
  ignore(sf.parse(["run", "ubuntu"]))
  inspect(config.matched_cmd, content="run")
  inspect(config.run.detach, content="false")
  inspect(config.run.interactive, content="false")
  inspect(config.run.tty, content="false")
  inspect(config.run.image, content="ubuntu")
  inspect(config.run.command, content="[]")
}

test "StructFirst does not apply setters on parse error" {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()
  sf.int_opt(name="count", default=0, setter=fn(v) { config.count = v })
  let result : Result[_, _] = try? sf.parse(["--count", "not-a-number"])
  inspect(result is Err(_), content="true")
  inspect(config.count, content="0")
}

test "Docker-style: compose up with minimal args" {
  let config = DockerConfig::new()
  let sf = StructFirst::new()
  setup_docker_parser(sf, config)
  ignore(sf.parse(["compose", "up", "web"]))
  inspect(config.matched_cmd, content="compose")
  inspect(config.matched_subcmd, content="up")
  inspect(config.compose.up.services, content="[\"web\"]")
  inspect(config.compose.files, content="[]")
}
