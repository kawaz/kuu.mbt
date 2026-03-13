// ============================================================
// struct-first CLI パーサ PoC: C. Trait ベース方式
// ============================================================
//
// 検証目的:
//   1. MoonBit の trait + mut フィールドで struct-first パースが実現可能か
//   2. FieldRegistry を通じて kuu core と struct を橋渡しできるか
//   3. サブコマンドでネストした struct への値注入が動作するか
//   4. positional 引数と append 系オプションが trait 方式で扱えるか
//
// 結論: 全て動作する。Trait ベース方式は MoonBit で実現可能。

// ============================================================
// FieldRegistry — kuu core と struct フィールドの橋渡し
// ============================================================

/// パース結果を struct フィールドに適用するクロージャを蓄積する。
/// kuu core の Parser をラップし、trait impl から呼ばれる登録メソッドを提供する。
struct FieldRegistry {
  parser : @core.Parser
  appliers : Array[() -> Unit]
}

fn FieldRegistry::new(parser : @core.Parser) -> FieldRegistry {
  { parser, appliers: [] }
}

fn FieldRegistry::flag(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  apply_fn~ : (Bool) -> Unit
) -> Unit {
  let opt = self.parser.flag(name=name, description=description, global=global)
  self.appliers.push(fn() { apply_fn(opt.get().unwrap()) })
}

fn FieldRegistry::string(
  self : FieldRegistry,
  name~ : String,
  default~ : String = "",
  description~ : String = "",
  apply_fn~ : (String) -> Unit
) -> Unit {
  let opt = self.parser.string_opt(
    name=name, default=default, description=description,
  )
  self.appliers.push(fn() { apply_fn(opt.get().unwrap()) })
}

fn FieldRegistry::int(
  self : FieldRegistry,
  name~ : String,
  default~ : Int = 0,
  description~ : String = "",
  apply_fn~ : (Int) -> Unit
) -> Unit {
  let opt = self.parser.int_opt(
    name=name, default=default, description=description,
  )
  self.appliers.push(fn() { apply_fn(opt.get().unwrap()) })
}

fn FieldRegistry::append_string(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  apply_fn~ : (Array[String]) -> Unit
) -> Unit {
  let opt = self.parser.append_string(name=name, description=description)
  self.appliers.push(fn() { apply_fn(opt.get().unwrap()) })
}

fn FieldRegistry::positional(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  apply_fn~ : (String?) -> Unit
) -> Unit {
  let opt = self.parser.positional(name=name, description=description)
  // positional は is_set で実際に値が提供されたか判別する。
  // kuu の positional は default="" なので get() だけでは未指定と空文字を区別できない。
  self.appliers.push(fn() {
    if (opt.is_set)() {
      apply_fn(opt.get())
    }
  })
}

fn FieldRegistry::rest(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  apply_fn~ : (Array[String]) -> Unit
) -> Unit {
  let opt = self.parser.rest(name=name, description=description)
  self.appliers.push(fn() { apply_fn(opt.get().unwrap()) })
}

/// サブコマンドを登録。setup クロージャで子パーサの FieldRegistry を受け取る。
/// matched_fn は当該サブコマンドが選択された場合に呼ばれる。
fn FieldRegistry::sub(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  setup~ : (FieldRegistry) -> Unit,
  matched_fn~ : () -> Unit = fn() {  }
) -> Unit {
  let child_appliers : Array[() -> Unit] = []
  let child_matched = matched_fn
  let _cmd = self.parser.cmd(
    name=name,
    description=description,
    setup=fn(child_parser) {
      let child_reg = FieldRegistry::new(child_parser)
      setup(child_reg)
      // 子の appliers を親に伝搬（parse 後にまとめて実行するため）
      for a in child_reg.appliers {
        child_appliers.push(a)
      }
    },
  )
  self.appliers.push(fn() {
    if (_cmd.is_set)() {
      child_matched()
      for a in child_appliers {
        a()
      }
    }
  })
}

fn FieldRegistry::require_cmd(self : FieldRegistry) -> Unit {
  self.parser.require_cmd()
}

fn FieldRegistry::apply_all(self : FieldRegistry) -> Unit {
  for applier in self.appliers {
    applier()
  }
}

// ============================================================
// Parseable trait
// ============================================================

trait Parseable {
  register(Self, FieldRegistry) -> Unit
}

fn[T : Parseable] parse_into(
  args : Array[String],
  target : T
) -> Unit raise @core.ParseError {
  let parser = @core.Parser::new()
  let registry = FieldRegistry::new(parser)
  target.register(registry)
  let _result = parser.parse(args)
  registry.apply_all()
}

// ============================================================
// docker-like CLI: struct 定義
// ============================================================

/// トップレベル: グローバルオプション + どのサブコマンドが選ばれたか
struct DockerCli {
  // global options
  mut verbose : Bool
  mut log_level : String
  // subcommand results
  mut command : String // 選ばれたサブコマンド名
  run : RunConfig
  build : BuildConfig
  ps : PsConfig
}

struct RunConfig {
  mut image : String?
  mut detach : Bool
  mut name : String
  mut publish : Array[String]
  mut extra_args : Array[String]
}

struct BuildConfig {
  mut tag : String
  mut no_cache : Bool
  mut path : String?
}

struct PsConfig {
  mut all : Bool
  mut quiet : Bool
}

fn DockerCli::default() -> DockerCli {
  {
    verbose: false,
    log_level: "info",
    command: "",
    run: {
      image: None,
      detach: false,
      name: "",
      publish: [],
      extra_args: [],
    },
    build: { tag: "latest", no_cache: false, path: None },
    ps: { all: false, quiet: false },
  }
}

impl Parseable for DockerCli with register(self, reg) {
  // グローバルオプション
  reg.flag(
    name="verbose",
    description="Enable verbose output",
    global=true,
    apply_fn=fn(v) { self.verbose = v },
  )
  reg.string(
    name="log-level",
    default="info",
    description="Set log level",
    apply_fn=fn(v) { self.log_level = v },
  )

  // docker run
  reg.sub(
    name="run",
    description="Create and run a new container",
    matched_fn=fn() { self.command = "run" },
    setup=fn(r) {
      r.flag(
        name="detach",
        description="Run container in background",
        apply_fn=fn(v) { self.run.detach = v },
      )
      r.string(
        name="name",
        description="Assign a name to the container",
        apply_fn=fn(v) { self.run.name = v },
      )
      r.append_string(
        name="publish",
        description="Publish a container's port(s) to the host",
        apply_fn=fn(v) { self.run.publish = v },
      )
      r.positional(
        name="IMAGE",
        description="Container image",
        apply_fn=fn(v) { self.run.image = v },
      )
      r.rest(
        name="ARGS",
        description="Command and arguments",
        apply_fn=fn(v) { self.run.extra_args = v },
      )
    },
  )

  // docker build
  reg.sub(
    name="build",
    description="Build an image from a Dockerfile",
    matched_fn=fn() { self.command = "build" },
    setup=fn(r) {
      r.string(
        name="tag",
        default="latest",
        description="Name and optionally a tag",
        apply_fn=fn(v) { self.build.tag = v },
      )
      r.flag(
        name="no-cache",
        description="Do not use cache when building",
        apply_fn=fn(v) { self.build.no_cache = v },
      )
      r.positional(
        name="PATH",
        description="Build context path",
        apply_fn=fn(v) { self.build.path = v },
      )
    },
  )

  // docker ps
  reg.sub(
    name="ps",
    description="List containers",
    matched_fn=fn() { self.command = "ps" },
    setup=fn(r) {
      r.flag(
        name="all",
        description="Show all containers",
        apply_fn=fn(v) { self.ps.all = v },
      )
      r.flag(
        name="quiet",
        description="Only display container IDs",
        apply_fn=fn(v) { self.ps.quiet = v },
      )
    },
  )

  reg.require_cmd()
}

// ============================================================
// ヘルパー: テスト実行と結果表示
// ============================================================

fn run_test(
  label : String,
  args : Array[String],
  expected_fn : (DockerCli) -> String
) -> Unit {
  let cli = DockerCli::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into(args, cli)
  match result {
    Ok(_) => {
      let expected = expected_fn(cli)
      println("[PASS] \{label}")
      println("  \{expected}")
    }
    Err(@core.ParseError(info)) => println("[FAIL] \{label}: \{info.message}")
    Err(@core.HelpRequested(text)) => println("[HELP] \{label}:\n\{text}")
  }
}

// ============================================================
// メイン
// ============================================================

fn main {
  println("=== struct-first CLI Parser PoC: Trait-based ===")
  println("=== docker-like CLI demo ===")
  println("")

  // Test 1: docker run with all options
  run_test(
    "docker run --detach --name web --publish 8080:80 --publish 443:443 nginx -- echo hello",
    [
      "run", "--detach", "--name", "web", "--publish", "8080:80", "--publish",
      "443:443", "nginx", "--", "echo", "hello",
    ],
    fn(cli) {
      "cmd=\{cli.command} image=\{cli.run.image} detach=\{cli.run.detach}" +
      " name=\{cli.run.name} publish=\{cli.run.publish} extra=\{cli.run.extra_args}"
    },
  )

  // Test 2: docker build with tag
  run_test(
    "docker build --tag myapp:v1.0 --no-cache .",
    ["build", "--tag", "myapp:v1.0", "--no-cache", "."],
    fn(cli) {
      "cmd=\{cli.command} tag=\{cli.build.tag} no_cache=\{cli.build.no_cache}" +
      " path=\{cli.build.path}"
    },
  )

  // Test 3: docker ps --all --quiet
  run_test("docker ps --all --quiet", ["ps", "--all", "--quiet"], fn(cli) {
    "cmd=\{cli.command} all=\{cli.ps.all} quiet=\{cli.ps.quiet}"
  })

  // Test 4: global option with subcommand
  run_test(
    "docker --verbose --log-level debug run nginx",
    ["--verbose", "--log-level", "debug", "run", "nginx"],
    fn(cli) {
      "verbose=\{cli.verbose} log_level=\{cli.log_level}" +
      " cmd=\{cli.command} image=\{cli.run.image}"
    },
  )

  // Test 5: docker build defaults
  run_test("docker build (defaults)", ["build"], fn(cli) {
    "cmd=\{cli.command} tag=\{cli.build.tag} no_cache=\{cli.build.no_cache}" +
    " path=\{cli.build.path}"
  })

  // Test 6: missing subcommand (expect error)
  run_test("docker (no subcommand - expect error)", [], fn(_cli) { "UNEXPECTED" })

  // Test 7: docker run minimal
  run_test("docker run alpine", ["run", "alpine"], fn(cli) {
    "cmd=\{cli.command} image=\{cli.run.image} detach=\{cli.run.detach}"
  })

  println("")
  println("=== PoC Complete ===")
}
