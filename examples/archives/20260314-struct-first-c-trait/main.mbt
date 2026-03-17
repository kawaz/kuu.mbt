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
///
/// applier は parse 成功後にのみ apply_all() で一括実行される。
/// parse がエラーを raise した場合、apply_all() は呼ばれず target の状態はデフォルトのまま。
struct FieldRegistry {
  parser : @core.Parser
  appliers : Array[() -> Unit]
}

fn FieldRegistry::new(parser : @core.Parser) -> FieldRegistry {
  { parser, appliers: [] }
}

/// Bool フラグを登録。apply_fn はパース成功後に値を受け取る。
/// apply_fn は struct フィールドへの代入のみに使用すること。
fn FieldRegistry::flag(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  apply_fn~ : (Bool) -> Unit
) -> Unit {
  let opt = self.parser.flag(name=name, description=description, global=global)
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

/// String オプションを登録。
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
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

/// Int オプションを登録。
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
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

/// 複数値収集オプションを登録。
fn FieldRegistry::append_string(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  apply_fn~ : (Array[String]) -> Unit
) -> Unit {
  let opt = self.parser.append_string(name=name, description=description)
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

/// 位置引数を登録。kuu の positional は default="" のため、
/// is_set で未指定を判別し、未指定時は apply_fn を呼ばない（struct のデフォルトを維持）。
fn FieldRegistry::positional(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  apply_fn~ : (String?) -> Unit
) -> Unit {
  let opt = self.parser.positional(name=name, description=description)
  self.appliers.push(fn() {
    if opt.is_set() {
      match opt.get() {
        Some(v) => apply_fn(Some(v))
        None => () // 防御的: is_set=true なら通常到達しない
      }
    }
  })
}

/// 残り全引数を収集。
fn FieldRegistry::rest(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  apply_fn~ : (Array[String]) -> Unit
) -> Unit {
  let opt = self.parser.rest(name=name, description=description)
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

/// サブコマンドを登録。
/// setup: 子パーサの FieldRegistry を受け取り、子のフィールドを登録する。
/// on_match: 当該サブコマンドが選択された場合に呼ばれる追加コールバック（省略可）。
///
/// 選択されたサブコマンドの applier のみが実行される（未選択サブコマンドの applier は実行されない）。
/// 子 FieldRegistry は Ref で保持し、apply_all 時に再帰的に処理する。
fn FieldRegistry::sub(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  setup~ : (FieldRegistry) -> Unit,
  on_match~ : () -> Unit = fn() {  }
) -> Unit {
  let child_registry_ref : Ref[FieldRegistry?] = { val: None }
  let cmd = self.parser.cmd(
    name=name,
    description=description,
    setup=fn(child_parser) {
      let child_reg = FieldRegistry::new(child_parser)
      setup(child_reg)
      child_registry_ref.val = Some(child_reg)
    },
  )
  self.appliers.push(fn() {
    if cmd.is_set() {
      on_match()
      match child_registry_ref.val {
        Some(child_reg) => child_reg.apply_all()
        None => ()
      }
    }
  })
}

fn FieldRegistry::require_cmd(self : FieldRegistry) -> Unit {
  self.parser.require_cmd()
}

/// 蓄積された全 applier を実行。parse 成功後にのみ呼ぶこと。
fn FieldRegistry::apply_all(self : FieldRegistry) -> Unit {
  for applier in self.appliers {
    applier()
  }
}

// ============================================================
// Parseable trait
// ============================================================

/// CLI パース可能な struct が実装する trait。
/// register メソッドで FieldRegistry にフィールド登録を行う。
trait Parseable {
  register(Self, FieldRegistry) -> Unit
}

/// struct を対象に CLI 引数をパースし、結果を直接注入する。
/// エラー時は target の状態はデフォルトのまま（apply_all は呼ばれない）。
fn[T : Parseable] parse_into(
  args : Array[String],
  target : T
) -> Unit raise @core.ParseError {
  let parser = @core.Parser::new()
  let registry = FieldRegistry::new(parser)
  target.register(registry)
  let _ = parser.parse(args)
  registry.apply_all()
}

// ============================================================
// docker-like CLI: struct 定義
// ============================================================

/// どのサブコマンドが選ばれたかを型安全に表現
enum Command {
  Run
  Build
  Ps
} derive(Eq, Show)

/// トップレベル: グローバルオプション + サブコマンド結果
struct DockerCli {
  mut verbose : Bool
  mut log_level : String
  mut command : Command?
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
    command: None,
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
    on_match=fn() { self.command = Some(Run) },
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
    on_match=fn() { self.command = Some(Build) },
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
    on_match=fn() { self.command = Some(Ps) },
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
// テスト
// ============================================================

/// パース成功を期待するテスト。check_fn で値の正しさを assert_eq で検証する。
/// check_fn 内の assert_eq が失敗した場合は [FAIL] として報告する。
fn assert_parse(
  label : String,
  args : Array[String],
  check_fn : (DockerCli) -> Unit raise
) -> Unit {
  let cli = DockerCli::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into(args, cli)
  match result {
    Ok(_) => {
      // check_fn 内の assert が失敗すると panic するので try で捕捉
      try {
        check_fn(cli)
        println("[PASS] \{label}")
      } catch {
        e => println("[FAIL] \{label}: assertion failed: \{e}")
      }
    }
    Err(@core.ParseError(info)) =>
      println("[FAIL] \{label}: unexpected error: \{info.message}")
    Err(@core.HelpRequested(_)) =>
      println("[FAIL] \{label}: unexpected help request")
  }
}

/// パースエラーを期待するテスト。
fn assert_parse_error(
  label : String,
  args : Array[String],
  expected_msg~ : String
) -> Unit {
  let cli = DockerCli::default()
  let result : Result[Unit, @core.ParseError] = try? parse_into(args, cli)
  match result {
    Ok(_) => println("[FAIL] \{label}: expected error but succeeded")
    Err(@core.ParseError(info)) =>
      if info.message.contains(expected_msg) {
        println("[PASS] \{label} (error: \{info.message})")
      } else {
        println(
          "[FAIL] \{label}: expected '\{expected_msg}' but got '\{info.message}'",
        )
      }
    Err(@core.HelpRequested(_)) =>
      println("[FAIL] \{label}: expected error but got help")
  }
}

fn main {
  println("=== struct-first CLI Parser PoC: Trait-based ===")
  println("=== docker-like CLI demo ===")
  println("")

  // Test 1: docker run with all options
  assert_parse(
    "docker run --detach --name web --publish 8080:80 --publish 443:443 nginx -- echo hello",
    [
      "run", "--detach", "--name", "web", "--publish", "8080:80", "--publish",
      "443:443", "nginx", "--", "echo", "hello",
    ],
    (cli) => {
      assert_eq(cli.command, Some(Run))
      assert_eq(cli.run.image, Some("nginx"))
      assert_eq(cli.run.detach, true)
      assert_eq(cli.run.name, "web")
      assert_eq(cli.run.publish, ["8080:80", "443:443"])
      assert_eq(cli.run.extra_args, ["echo", "hello"])
    },
  )

  // Test 2: docker build with tag
  assert_parse(
    "docker build --tag myapp:v1.0 --no-cache .",
    ["build", "--tag", "myapp:v1.0", "--no-cache", "."],
    (cli) => {
      assert_eq(cli.command, Some(Build))
      assert_eq(cli.build.tag, "myapp:v1.0")
      assert_eq(cli.build.no_cache, true)
      assert_eq(cli.build.path, Some("."))
    },
  )

  // Test 3: docker ps --all --quiet
  assert_parse(
    "docker ps --all --quiet",
    ["ps", "--all", "--quiet"],
    (cli) => {
      assert_eq(cli.command, Some(Ps))
      assert_eq(cli.ps.all, true)
      assert_eq(cli.ps.quiet, true)
    },
  )

  // Test 4: global option with subcommand
  assert_parse(
    "docker --verbose --log-level debug run nginx",
    ["--verbose", "--log-level", "debug", "run", "nginx"],
    (cli) => {
      assert_eq(cli.verbose, true)
      assert_eq(cli.log_level, "debug")
      assert_eq(cli.command, Some(Run))
      assert_eq(cli.run.image, Some("nginx"))
    },
  )

  // Test 5: docker build defaults (positional not provided)
  assert_parse(
    "docker build (defaults)",
    ["build"],
    (cli) => {
      assert_eq(cli.command, Some(Build))
      assert_eq(cli.build.tag, "latest")
      assert_eq(cli.build.no_cache, false)
      assert_eq(cli.build.path, None)
    },
  )

  // Test 6: missing subcommand (expect error)
  assert_parse_error(
    "docker (no subcommand - expect error)",
    [],
    expected_msg="subcommand required",
  )

  // Test 7: docker run minimal
  assert_parse(
    "docker run alpine",
    ["run", "alpine"],
    (cli) => {
      assert_eq(cli.command, Some(Run))
      assert_eq(cli.run.image, Some("alpine"))
      assert_eq(cli.run.detach, false)
      assert_eq(cli.run.name, "")
      assert_eq(cli.run.publish.length(), 0)
      assert_eq(cli.run.extra_args.length(), 0)
    },
  )

  // Test 8: docker ps defaults
  assert_parse(
    "docker ps (defaults)",
    ["ps"],
    (cli) => {
      assert_eq(cli.command, Some(Ps))
      assert_eq(cli.ps.all, false)
      assert_eq(cli.ps.quiet, false)
    },
  )

  // Test 9: unselected subcommand state untouched
  assert_parse(
    "docker run nginx (build/ps state untouched)",
    ["run", "nginx"],
    (cli) => {
      assert_eq(cli.command, Some(Run))
      // build/ps は初期値のまま
      assert_eq(cli.build.tag, "latest")
      assert_eq(cli.build.no_cache, false)
      assert_eq(cli.ps.all, false)
      assert_eq(cli.ps.quiet, false)
    },
  )

  // Test 10: unknown subcommand (expect error)
  assert_parse_error(
    "docker exec (unknown subcommand)",
    ["exec", "--interactive"],
    expected_msg="unexpected",
  )

  println("")
  println("=== PoC Complete ===")
}
