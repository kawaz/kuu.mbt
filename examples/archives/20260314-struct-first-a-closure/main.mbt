///|
/// struct-first CLI パーサ PoC: A. クロージャ Setter 方式
///
/// 検証項目:
/// 1. MoonBit で mut struct + クロージャキャプチャが動くか
/// 2. kuu Parser に commit クロージャを渡すラッパーが作れるか
/// 3. サブコマンドのネスト（Docker 風）でも動くか
fn main {
  println("=== Step 1: mut struct + closure capture ===")
  test_closure_capture()
  println("")
  println("=== Step 2: struct-first wrapper with kuu ===")
  test_struct_first_simple()
  println("")
  println("=== Step 3: nested subcommands (Docker-style) ===")
  test_struct_first_docker()
}

// ─── Step 1: MoonBit closure capture verification ───

///|
struct SimpleConfig {
  mut verbose : Bool
  mut name : String
  mut count : Int
}

///|
fn SimpleConfig::default() -> SimpleConfig {
  { verbose: false, name: "", count: 0 }
}

///|
fn test_closure_capture() -> Unit {
  let config = SimpleConfig::default()

  let set_verbose = fn() { config.verbose = true }
  let set_name = fn(v : String) { config.name = v }
  let set_count = fn(v : Int) { config.count = v }

  println(
    "Before: verbose=\{config.verbose}, name=\"\{config.name}\", count=\{config.count}",
  )

  set_verbose()
  set_name("hello")
  set_count(42)

  println(
    "After:  verbose=\{config.verbose}, name=\"\{config.name}\", count=\{config.count}",
  )

  let setters : Array[() -> Unit] = [
    fn() { config.verbose = false },
    fn() { config.name = "erased" },
    fn() { config.count = 99 },
  ]
  for setter in setters {
    setter()
  }
  println(
    "Erased: verbose=\{config.verbose}, name=\"\{config.name}\", count=\{config.count}",
  )
}

// ─── Step 2: Struct-first wrapper ───

///|
fn[T] copy_opt(opt : @core.Opt[T], setter : (T) -> Unit) -> Unit {
  match opt.get() {
    Some(v) => setter(v)
    None => ()
  }
}

/// Thin wrapper: registers options on kuu Parser, copies values to user's struct after parse.
/// `copiers` holds type-erased closures `() -> Unit` that transfer parsed values to the user's struct.
/// Each copier reads from an `Opt[T]` and calls the user-provided setter. All copiers run after parse().
///|
struct StructFirst {
  parser : @core.Parser
  copiers : Array[() -> Unit]
}

///|
fn StructFirst::new(dashdash~ : Bool = true) -> StructFirst {
  { parser: @core.Parser::new(dashdash~), copiers: [] }
}

///|
fn StructFirst::flag(
  self : StructFirst,
  name~ : String,
  shorts~ : String = "",
  description~ : String = "",
  global~ : Bool = false,
  default~ : Bool = false,
  setter~ : (Bool) -> Unit
) -> Unit {
  let opt = self.parser.flag(name~, shorts~, description~, global~, default~)
  self.copiers.push(fn() { copy_opt(opt, setter) })
}

///|
fn StructFirst::string(
  self : StructFirst,
  name~ : String,
  shorts~ : String = "",
  description~ : String = "",
  global~ : Bool = false,
  default~ : String = "",
  value_name~ : String = "",
  setter~ : (String) -> Unit
) -> Unit {
  let opt = self.parser.string(
    name~, shorts~, description~, global~, default~, value_name~,
  )
  self.copiers.push(fn() { copy_opt(opt, setter) })
}

///|
fn StructFirst::int(
  self : StructFirst,
  name~ : String,
  shorts~ : String = "",
  description~ : String = "",
  global~ : Bool = false,
  default~ : Int = 0,
  value_name~ : String = "",
  setter~ : (Int) -> Unit
) -> Unit {
  let opt = self.parser.int(
    name~, shorts~, description~, global~, default~, value_name~,
  )
  self.copiers.push(fn() { copy_opt(opt, setter) })
}

///|
fn StructFirst::count(
  self : StructFirst,
  name~ : String,
  shorts~ : String = "",
  description~ : String = "",
  global~ : Bool = false,
  setter~ : (Int) -> Unit
) -> Unit {
  let opt = self.parser.count(name~, shorts~, description~, global~)
  self.copiers.push(fn() { copy_opt(opt, setter) })
}

///|
fn StructFirst::positional(
  self : StructFirst,
  name~ : String,
  description~ : String = "",
  required~ : Bool = false,
  setter~ : (String) -> Unit
) -> Unit {
  let opt = self.parser.positional(name~, description~)
  if required {
    self.parser.required(opt.as_ref())
  }
  self.copiers.push(fn() { copy_opt(opt, setter) })
}

///|
fn StructFirst::rest(
  self : StructFirst,
  name~ : String,
  description~ : String = "",
  setter~ : (Array[String]) -> Unit
) -> Unit {
  let opt = self.parser.rest(name~, description~)
  self.copiers.push(fn() { copy_opt(opt, setter) })
}

///|
fn StructFirst::append_string(
  self : StructFirst,
  name~ : String,
  shorts~ : String = "",
  description~ : String = "",
  value_name~ : String = "",
  setter~ : (Array[String]) -> Unit
) -> Unit {
  let opt = self.parser.append_string(
    name~, shorts~, description~, value_name~,
  )
  self.copiers.push(fn() { copy_opt(opt, setter) })
}

///|
fn StructFirst::add_copier(self : StructFirst, copier : () -> Unit) -> Unit {
  self.copiers.push(copier)
}

///|
fn StructFirst::require_cmd(self : StructFirst) -> Unit {
  self.parser.require_cmd()
}

///|
fn StructFirst::parse(
  self : StructFirst,
  args : Array[String]
) -> @core.ParseResult raise @core.ParseError {
  let result = self.parser.parse(args)
  for copier in self.copiers {
    copier()
  }
  result
}

// ─── Step 2 test ───

///|
fn test_struct_first_simple() -> Unit {
  let config = SimpleConfig::default()
  let sf = StructFirst::new()

  sf.flag(
    name="verbose",
    shorts="v",
    description="Enable verbose output",
    setter=fn(v) { config.verbose = v },
  )
  sf.string(
    name="name",
    shorts="n",
    default="world",
    description="Name to greet",
    setter=fn(v) { config.name = v },
  )
  sf.int(
    name="count",
    shorts="c",
    default=1,
    description="Repeat count",
    setter=fn(v) { config.count = v },
  )

  let args = ["--verbose", "--name", "kuu", "--count", "3"]
  println("Input: \{args}")

  let result : Result[@core.ParseResult, @core.ParseError] = try? sf.parse(args)
  match result {
    Err(@core.HelpRequested(text)) => println(text)
    Err(@core.ParseError(info)) => println("Error: " + info.to_string())
    Ok(_) => {
      println("config.verbose = \{config.verbose}")
      println("config.name    = \"\{config.name}\"")
      println("config.count   = \{config.count}")
    }
  }
}

// ─── Step 3: Docker-style nested subcommands ───

///|
struct DockerGlobal {
  mut debug : Bool
  mut verbose : Int
  mut log_level : String
}

///|
struct DockerRun {
  mut detach : Bool
  mut interactive : Bool
  mut tty : Bool
  mut image : String
  mut command : Array[String]
}

///|
struct ComposeUp {
  mut detach : Bool
  mut scale : Int
  mut services : Array[String]
}

///|
struct DockerCompose {
  mut files : Array[String]
  mut project_name : String
  up : ComposeUp
}

///|
struct DockerConfig {
  global : DockerGlobal
  run : DockerRun
  compose : DockerCompose
  mut matched_cmd : String
  mut matched_subcmd : String
}

///|
fn DockerConfig::new() -> DockerConfig {
  {
    global: { debug: false, verbose: 0, log_level: "info" },
    run: {
      detach: false,
      interactive: false,
      tty: false,
      image: "",
      command: [],
    },
    compose: {
      files: [],
      project_name: "",
      up: { detach: false, scale: 1, services: [] },
    },
    matched_cmd: "",
    matched_subcmd: "",
  }
}

///|
fn setup_docker_parser(sf : StructFirst, config : DockerConfig) -> Unit {
  // Global options
  sf.flag(
    name="debug",
    shorts="D",
    global=true,
    setter=fn(v) { config.global.debug = v },
  )
  sf.count(
    name="verbose",
    shorts="v",
    global=true,
    setter=fn(v) { config.global.verbose = v },
  )
  sf.string(
    name="log-level",
    default="info",
    global=true,
    setter=fn(v) { config.global.log_level = v },
  )

  // Subcommand: run
  // StructFirst ラッパーはサブコマンド内オプションの一括登録に未対応のため、
  // raw kuu API で Opt[T] を取得し、copiers に手動登録する混合スタイルを使用。
  let run_cmd = sf.parser.sub(name="run", description="Run a container")
  let run_detach = run_cmd.flag(name="detach", shorts="d")
  let run_interactive = run_cmd.flag(name="interactive", shorts="i")
  let run_tty = run_cmd.flag(name="tty", shorts="t")
  let run_image = run_cmd.positional(name="image")
  run_cmd.required(run_image.as_ref())
  let run_command = run_cmd.rest(name="command")

  sf.add_copier(fn() {
    // run subcommand が選択されたか判定（required な positional は必ず Some を返す）
    match run_image.get() {
      Some(_) => config.matched_cmd = "run"
      None => ()
    }
    copy_opt(run_detach, fn(v) { config.run.detach = v })
    copy_opt(run_interactive, fn(v) { config.run.interactive = v })
    copy_opt(run_tty, fn(v) { config.run.tty = v })
    copy_opt(run_image, fn(v) { config.run.image = v })
    copy_opt(run_command, fn(v) { config.run.command = v })
  })

  // Subcommand: compose (nested)
  let compose_cmd = sf.parser.sub(
    name="compose",
    description="Compose commands",
  )
  let compose_files = compose_cmd.append_string(name="file", shorts="f")
  let compose_project = compose_cmd.string(
    name="project-name",
    default="",
    shorts="p",
  )
  compose_cmd.require_cmd()

  // compose up
  let up_cmd = compose_cmd.sub(name="up", description="Start containers")
  let up_detach = up_cmd.flag(name="detach", shorts="d")
  let up_scale = up_cmd.int(name="scale", default=1)
  let up_services = up_cmd.rest(name="services")

  sf.add_copier(fn() {
    // compose パーサが未実行なら parsed=false により opt.get() は None を返す。compose 選択時のみ Some
    match compose_project.get() {
      Some(_) => config.matched_cmd = "compose"
      None => ()
    }
    copy_opt(compose_files, fn(v) { config.compose.files = v })
    copy_opt(compose_project, fn(v) { config.compose.project_name = v })
    // up パーサが未実行なら None、選択時のみ Some
    match up_scale.get() {
      Some(_) => config.matched_subcmd = "up"
      None => ()
    }
    copy_opt(up_detach, fn(v) { config.compose.up.detach = v })
    copy_opt(up_scale, fn(v) { config.compose.up.scale = v })
    copy_opt(up_services, fn(v) { config.compose.up.services = v })
  })

  sf.require_cmd()
}

///|
fn print_docker_result(config : DockerConfig) -> Unit {
  println("global.debug     = \{config.global.debug}")
  println("global.verbose   = \{config.global.verbose}")
  println("global.log_level = \"\{config.global.log_level}\"")
  println("matched_cmd      = \"\{config.matched_cmd}\"")
  match config.matched_cmd {
    "run" => {
      println("run.detach       = \{config.run.detach}")
      println("run.interactive  = \{config.run.interactive}")
      println("run.tty          = \{config.run.tty}")
      println("run.image        = \"\{config.run.image}\"")
      println("run.command      = \{config.run.command}")
    }
    "compose" => {
      println("compose.files        = \{config.compose.files}")
      println("compose.project_name = \"\{config.compose.project_name}\"")
      println("matched_subcmd       = \"\{config.matched_subcmd}\"")
      match config.matched_subcmd {
        "up" => {
          println("compose.up.detach   = \{config.compose.up.detach}")
          println("compose.up.scale    = \{config.compose.up.scale}")
          println("compose.up.services = \{config.compose.up.services}")
        }
        other => println("subcmd: \{other}")
      }
    }
    other => println("cmd: \{other}")
  }
}

///|
fn test_struct_first_docker() -> Unit {
  // Test 1: docker --debug run -dit ubuntu bash
  println("--- Test: docker --debug run -dit ubuntu bash ---")
  let config1 = DockerConfig::new()
  let sf1 = StructFirst::new()
  setup_docker_parser(sf1, config1)

  let args1 = ["--debug", "run", "-d", "-i", "-t", "ubuntu", "bash"]
  let result1 : Result[@core.ParseResult, @core.ParseError] = try? sf1.parse(
    args1,
  )
  match result1 {
    Err(@core.HelpRequested(text)) => println(text)
    Err(@core.ParseError(info)) => println("Error: " + info.to_string())
    Ok(_) => print_docker_result(config1)
  }

  println("")

  // Test 2: docker compose -f prod.yml up -d --scale 3 web db
  println("--- Test: docker compose -f prod.yml up -d --scale 3 web db ---")
  let config2 = DockerConfig::new()
  let sf2 = StructFirst::new()
  setup_docker_parser(sf2, config2)

  let args2 = [
    "compose", "-f", "prod.yml", "up", "-d", "--scale", "3", "web", "db",
  ]
  let result2 : Result[@core.ParseResult, @core.ParseError] = try? sf2.parse(
    args2,
  )
  match result2 {
    Err(@core.HelpRequested(text)) => println(text)
    Err(@core.ParseError(info)) => println("Error: " + info.to_string())
    Ok(_) => print_docker_result(config2)
  }
}
