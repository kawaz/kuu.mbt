///|
/// main.mbt — Docker CLI subset demo using ValuePath (struct-first approach)
///
/// Demonstrates the same functionality as examples/20260308-mydocker
/// but using struct-first ValuePath pattern instead of kuu's builder API.

/// Docker CLI の設定を保持する構造体
struct DockerConfig {
  // Global options
  verbose : Ref[Int]
  debug : Ref[Bool]
  log_level : Ref[String]
  host : Ref[String]
  // compose options
  compose_file : Ref[Array[String]]
  // compose up options
  compose_detach : Ref[Bool]
  compose_scale : Ref[Int]
  compose_services : Ref[Array[String]]
  // matched command tracking
  matched_root_cmd : Ref[String?]
  matched_compose_cmd : Ref[String?]
}

fn DockerConfig::new() -> DockerConfig {
  DockerConfig::{
    verbose: { val: 0 },
    debug: { val: false },
    log_level: { val: "info" },
    host: { val: "" },
    compose_file: { val: [] },
    compose_detach: { val: false },
    compose_scale: { val: 1 },
    compose_services: { val: [] },
    matched_root_cmd: { val: None },
    matched_compose_cmd: { val: None },
  }
}

fn print_config(cfg : DockerConfig) -> Unit {
  println("=== Global Options ===")
  println("verbose: " + cfg.verbose.val.to_string())
  println("debug: " + cfg.debug.val.to_string())
  println("log-level: " + cfg.log_level.val)
  if cfg.host.val != "" {
    println("host: " + cfg.host.val)
  }
  println("")
  match cfg.matched_root_cmd.val {
    Some("compose") => {
      println("=== compose ===")
      let files = cfg.compose_file.val
      if files.length() > 0 {
        println("file: " + files.to_string())
      }
      match cfg.matched_compose_cmd.val {
        Some("up") => {
          println("  --- up ---")
          println("  detach: " + cfg.compose_detach.val.to_string())
          println("  scale: " + cfg.compose_scale.val.to_string())
          let svcs = cfg.compose_services.val
          if svcs.length() > 0 {
            println("  services: " + svcs.to_string())
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
}

fn main {
  // ─── Test case 1: compose up ───
  let args1 = [
    "--debug", "compose", "-f", "docker-compose.prod.yml",
    "-f", "docker-compose.override.yml", "up", "--detach", "--scale", "3",
    "web", "db",
  ]
  println("=== Test 1: compose up ===")
  println("Parsing: " + args1.to_string())
  println("")
  let cfg1 = DockerConfig::new()
  let result1 = parse_docker(cfg1, args1)
  match result1 {
    Ok(_) => print_config(cfg1)
    Err(msg) => println("Error: " + msg)
  }
  println("")

  // ─── Test case 2: global options only (no subcommand → error) ───
  let args2 : Array[String] = ["--debug", "--log-level", "warn"]
  println("=== Test 2: global options, no subcommand ===")
  println("Parsing: " + args2.to_string())
  println("")
  let cfg2 = DockerConfig::new()
  let result2 = parse_docker(cfg2, args2)
  match result2 {
    Ok(_) => print_config(cfg2)
    Err(msg) => println("Error: " + msg)
  }
  println("")

  // ─── Test case 3: --log-level=error with = syntax ───
  let args3 = [
    "--log-level=error", "compose", "-f", "docker-compose.yml",
    "up", "--scale=5", "api",
  ]
  println("=== Test 3: --key=value syntax ===")
  println("Parsing: " + args3.to_string())
  println("")
  let cfg3 = DockerConfig::new()
  let result3 = parse_docker(cfg3, args3)
  match result3 {
    Ok(_) => print_config(cfg3)
    Err(msg) => println("Error: " + msg)
  }
  println("")

  // ─── Test case 4: verbose count ───
  let args4 = ["-v", "-v", "-v", "compose", "up"]
  println("=== Test 4: verbose count ===")
  println("Parsing: " + args4.to_string())
  println("")
  let cfg4 = DockerConfig::new()
  let result4 = parse_docker(cfg4, args4)
  match result4 {
    Ok(_) => print_config(cfg4)
    Err(msg) => println("Error: " + msg)
  }
  println("")

  // ─── Test case 5: unknown option → error ───
  let args5 : Array[String] = ["--unknown-flag"]
  println("=== Test 5: unknown option ===")
  println("Parsing: " + args5.to_string())
  println("")
  let cfg5 = DockerConfig::new()
  let result5 = parse_docker(cfg5, args5)
  match result5 {
    Ok(_) => print_config(cfg5)
    Err(msg) => println("Error: " + msg)
  }

  println("")

  // ─── Test case 6: --debug=true → error (flag does not accept value) ───
  let args6 : Array[String] = ["--debug=true"]
  println("=== Test 6: flag with =value ===")
  println("Parsing: " + args6.to_string())
  println("")
  let cfg6 = DockerConfig::new()
  let result6 = parse_docker(cfg6, args6)
  match result6 {
    Ok(_) => print_config(cfg6)
    Err(msg) => println("Error: " + msg)
  }
  println("")

  // ─── Test case 7: --scale abc → abort (invalid integer) ───
  // PoC のため abort() で停止する。コメントのみ記載:
  // let args7 = ["compose", "up", "--scale", "abc"]
  // parse_docker(DockerConfig::new(), args7)  // → abort("Invalid integer: abc")

  // ─── Test case 8: -v --verbose -v → verbose=3 (short/long mixed count) ───
  let args8 = ["-v", "--verbose", "-v", "compose", "up"]
  println("=== Test 8: short/long mixed count ===")
  println("Parsing: " + args8.to_string())
  println("")
  let cfg8 = DockerConfig::new()
  let result8 = parse_docker(cfg8, args8)
  match result8 {
    Ok(_) => print_config(cfg8)
    Err(msg) => println("Error: " + msg)
  }

  // TODO: --help 表示は ValuePath では未実装
  // ヘルプ生成には PathEntry にメタデータ（description 等）を持たせる拡張が必要
}

/// Docker CLI のパースを構築・実行
fn parse_docker(cfg : DockerConfig, args : Array[String]) -> Result[Unit, String] {
  // ─── Global options ───
  let global_paths : Array[PathEntry] = [
    vp_count("-v", cfg.verbose),
    vp_count("--verbose", cfg.verbose),
    vp_flag("--debug", cfg.debug),
    vp_flag("-D", cfg.debug),
    vp_string("--log-level", cfg.log_level),
    vp_string("-l", cfg.log_level),
    vp_string("--host", cfg.host),
    vp_string("-H", cfg.host),
  ]

  // ─── compose up options ───
  let compose_up_paths : Array[PathEntry] = [
    vp_flag("--detach", cfg.compose_detach),
    vp_flag("-d", cfg.compose_detach),
    vp_int("--scale", cfg.compose_scale),
  ]

  // ─── compose subcommands ───
  let compose_subcmds : Array[
    (String, Array[PathEntry], Ref[Array[String]]?),
  ] = [("up", compose_up_paths, Some(cfg.compose_services))]

  // ─── compose options ───
  let compose_paths : Array[PathEntry] = [
    vp_append("-f", cfg.compose_file),
    vp_append("--file", cfg.compose_file),
  ]

  // 2段階パース:
  // 1. グローバルオプションを消費し、サブコマンドに分岐
  // 2. サブコマンド内でさらにサブコマンドに分岐

  // compose サブコマンド用の中間パーサ
  // compose は自身のオプション (-f) を持ち、さらに up/down 等のサブコマンドを持つ
  // これを表現するために、compose 用のカスタムパースを行う

  // compose 全体の引数を受け取るためのバッファ
  let compose_args : Ref[Array[String]] = { val: [] }

  // ルートレベルのサブコマンド
  // compose を検出したら残り引数を compose_args に格納
  let root_subcmds : Array[
    (String, Array[PathEntry], Ref[Array[String]]?),
  ] = [("compose", [], Some(compose_args))]

  // Step 1: ルートレベルをパース
  let r1 = vp_parse(
    args,
    global_paths,
    subcmds=Some(root_subcmds),
    matched_cmd=Some(cfg.matched_root_cmd),
  )
  match r1 {
    Err(e) => return Err(e)
    Ok(_) => ()
  }

  // Step 2: compose が選択されていたら、compose 引数をパース
  if cfg.matched_root_cmd.val == Some("compose") {
    let r2 = vp_parse(
      compose_args.val,
      compose_paths,
      subcmds=Some(compose_subcmds),
      matched_cmd=Some(cfg.matched_compose_cmd),
    )
    match r2 {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }

  Ok(())
}
