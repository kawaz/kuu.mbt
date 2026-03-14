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
  // network options
  net_create_driver : Ref[String]
  net_create_name : Ref[String?]
  // matched command tracking
  matched_root_cmd : Ref[String?]
  matched_compose_cmd : Ref[String?]
  matched_net_cmd : Ref[String?]
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
    net_create_driver: { val: "bridge" },
    net_create_name: { val: None },
    matched_root_cmd: { val: None },
    matched_compose_cmd: { val: None },
    matched_net_cmd: { val: None },
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
    Some("network") => {
      println("=== network ===")
      match cfg.matched_net_cmd.val {
        Some("create") => {
          println("  --- create ---")
          println("  driver: " + cfg.net_create_driver.val)
          match cfg.net_create_name.val {
            Some(name) => println("  name: " + name)
            None => ()
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
}

/// テスト結果の検証ヘルパー
/// is-main: true パッケージでは test ブロックが使えないため、
/// main 関数内で期待値と実際値を比較し結果を表示する
fn assert_eq_str(
  label : String,
  actual : String,
  expected : String
) -> Bool {
  if actual == expected {
    println("[PASS] " + label)
    true
  } else {
    println(
      "[FAIL] " + label + ": expected=" + expected + ", actual=" + actual,
    )
    false
  }
}

fn main {
  let mut all_pass = true

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
    Ok(_) => {
      print_config(cfg1)
      if not(
        assert_eq_str("debug", cfg1.debug.val.to_string(), "true"),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str("scale", cfg1.compose_scale.val.to_string(), "3"),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str(
          "matched_root_cmd",
          cfg1.matched_root_cmd.val.to_string(),
          "Some(compose)",
        ),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str(
          "matched_compose_cmd",
          cfg1.matched_compose_cmd.val.to_string(),
          "Some(up)",
        ),
      ) {
        all_pass = false
      }
    }
    Err(msg) => {
      println("Error: " + msg)
      all_pass = false
    }
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
    Ok(_) => {
      print_config(cfg2)
      if not(
        assert_eq_str("debug", cfg2.debug.val.to_string(), "true"),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str("log_level", cfg2.log_level.val, "warn"),
      ) {
        all_pass = false
      }
    }
    Err(msg) => {
      println("Error: " + msg)
      all_pass = false
    }
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
    Ok(_) => {
      print_config(cfg3)
      if not(
        assert_eq_str("log_level", cfg3.log_level.val, "error"),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str("scale", cfg3.compose_scale.val.to_string(), "5"),
      ) {
        all_pass = false
      }
    }
    Err(msg) => {
      println("Error: " + msg)
      all_pass = false
    }
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
    Ok(_) => {
      print_config(cfg4)
      if not(
        assert_eq_str("verbose", cfg4.verbose.val.to_string(), "3"),
      ) {
        all_pass = false
      }
    }
    Err(msg) => {
      println("Error: " + msg)
      all_pass = false
    }
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
    Ok(_) => {
      println("Expected error but got Ok")
      all_pass = false
    }
    Err(msg) => {
      println("Error (expected): " + msg)
      if not(
        assert_eq_str(
          "error_contains_unknown",
          (msg.contains("Unknown argument")).to_string(),
          "true",
        ),
      ) {
        all_pass = false
      }
    }
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
    Ok(_) => {
      println("Expected error but got Ok")
      all_pass = false
    }
    Err(msg) => {
      println("Error (expected): " + msg)
      if not(
        assert_eq_str(
          "error_contains_flag",
          (msg.contains("does not accept a value")).to_string(),
          "true",
        ),
      ) {
        all_pass = false
      }
    }
  }
  println("")

  // ─── Test case 7: --scale abc → error (invalid integer, no abort) ───
  let args7 = ["compose", "up", "--scale", "abc"]
  println("=== Test 7: integer parse error ===")
  println("Parsing: " + args7.to_string())
  println("")
  let cfg7 = DockerConfig::new()
  let result7 = parse_docker(cfg7, args7)
  match result7 {
    Ok(_) => {
      println("Expected error but got Ok")
      all_pass = false
    }
    Err(msg) => {
      println("Error (expected): " + msg)
      if not(
        assert_eq_str(
          "error_contains_invalid_integer",
          (msg.contains("Invalid integer")).to_string(),
          "true",
        ),
      ) {
        all_pass = false
      }
    }
  }
  println("")

  // ─── Test case 8: -v --verbose -v → verbose=3 (short/long mixed count) ───
  let args8 = ["-v", "--verbose", "-v", "compose", "up"]
  println("=== Test 8: short/long mixed count ===")
  println("Parsing: " + args8.to_string())
  println("")
  let cfg8 = DockerConfig::new()
  let result8 = parse_docker(cfg8, args8)
  match result8 {
    Ok(_) => {
      print_config(cfg8)
      if not(
        assert_eq_str("verbose", cfg8.verbose.val.to_string(), "3"),
      ) {
        all_pass = false
      }
    }
    Err(msg) => {
      println("Error: " + msg)
      all_pass = false
    }
  }
  println("")

  // ─── Test case 9: network create (3階層ネスト実証) ───
  let args9 = [
    "--debug", "network", "create", "--driver", "overlay", "my-network",
  ]
  println("=== Test 9: network create (3-level nesting) ===")
  println("Parsing: " + args9.to_string())
  println("")
  let cfg9 = DockerConfig::new()
  let result9 = parse_docker(cfg9, args9)
  match result9 {
    Ok(_) => {
      print_config(cfg9)
      if not(
        assert_eq_str("debug", cfg9.debug.val.to_string(), "true"),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str(
          "matched_root_cmd",
          cfg9.matched_root_cmd.val.to_string(),
          "Some(network)",
        ),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str(
          "matched_net_cmd",
          cfg9.matched_net_cmd.val.to_string(),
          "Some(create)",
        ),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str("net_create_driver", cfg9.net_create_driver.val, "overlay"),
      ) {
        all_pass = false
      }
      if not(
        assert_eq_str(
          "net_create_name",
          cfg9.net_create_name.val.to_string(),
          "Some(my-network)",
        ),
      ) {
        all_pass = false
      }
    }
    Err(msg) => {
      println("Error: " + msg)
      all_pass = false
    }
  }
  println("")

  // ─── Test case 10: compose --debug up → error ───
  // グローバルオプション --debug がサブコマンド内で認識されない制限の実証
  let args10 = ["compose", "--debug", "up"]
  println("=== Test 10: global option inside subcommand (limitation) ===")
  println("Parsing: " + args10.to_string())
  println("")
  let cfg10 = DockerConfig::new()
  let result10 = parse_docker(cfg10, args10)
  match result10 {
    Ok(_) => {
      println("Expected error but got Ok")
      all_pass = false
    }
    Err(msg) => {
      println("Error (expected): " + msg)
      // --debug はグローバルオプションだが compose レベルでは未定義なのでエラーになる
      // struct-first の制限: グローバルオプションを各レベルに手動追加する必要がある
      if not(
        assert_eq_str(
          "error_contains_unknown",
          (msg.contains("Unknown argument")).to_string(),
          "true",
        ),
      ) {
        all_pass = false
      }
    }
  }
  println("")

  // ─── Summary ───
  if all_pass {
    println("All tests passed.")
  } else {
    println("Some tests FAILED.")
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

  // ─── network create options ───
  let net_create_paths : Array[PathEntry] = [
    vp_string("--driver", cfg.net_create_driver),
    vp_string("-d", cfg.net_create_driver),
  ]

  // network create の name は rest で取得
  let net_create_rest : Ref[Array[String]] = { val: [] }

  // ─── network subcommands ───
  let net_subcmds : Array[
    (String, Array[PathEntry], Ref[Array[String]]?),
  ] = [("create", net_create_paths, Some(net_create_rest))]

  // ─── network options (現状なし) ───
  let net_paths : Array[PathEntry] = []

  // 多段階パース:
  // 1. グローバルオプションを消費し、サブコマンドに分岐
  // 2. サブコマンド内でさらにサブコマンドに分岐
  // 3. さらにネスト（network → create）

  // compose 全体の引数を受け取るためのバッファ
  let compose_args : Ref[Array[String]] = { val: [] }
  // network 全体の引数を受け取るためのバッファ
  let network_args : Ref[Array[String]] = { val: [] }

  // ルートレベルのサブコマンド
  let root_subcmds : Array[
    (String, Array[PathEntry], Ref[Array[String]]?),
  ] = [("compose", [], Some(compose_args)), ("network", [], Some(network_args))]

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

  // Step 3: network が選択されていたら、network 引数をパース
  // 3段階バッファリレー: root → network_args バッファ → network パース → create_rest バッファ
  // サブコマンドを追加するたびにバッファ変数とパース呼出が線形に増加する
  if cfg.matched_root_cmd.val == Some("network") {
    let r3 = vp_parse(
      network_args.val,
      net_paths,
      subcmds=Some(net_subcmds),
      matched_cmd=Some(cfg.matched_net_cmd),
    )
    match r3 {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    // network create の name を rest から取得
    if cfg.matched_net_cmd.val == Some("create") {
      let rest = net_create_rest.val
      if rest.length() > 0 {
        cfg.net_create_name.val = Some(rest[0])
      }
    }
  }

  Ok(())
}
