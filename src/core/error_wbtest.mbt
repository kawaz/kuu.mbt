///|
test "parse error includes error_context" {
  let p = Parser::new()
  let _ = p.flag(
    name="verbose",
    shorts="v",
    description="Enable verbose output",
  )
  let _ = p.int(name="port", default=8080, description="Set port number")
  let result : Result[_, _] = try? p.parse(["--unknown"])
  match result {
    Err(ParseError(info)) => {
      inspect(
        info.message,
        content=(
          #|unexpected argument: --unknown
        ),
      )
      // error_context が空でないことを確認
      inspect(info.error_context == "", content="false")
      // error_context に Usage と footer が含まれること
      inspect(info.error_context.contains("Usage:"), content="true")
      inspect(
        info.error_context.contains("For more information, try '--help'."),
        content="true",
      )
    }
    _ => abort("expected ParseError")
  }
}

///|
test "ParseErrorInfo::to_string format" {
  let info = ParseErrorInfo::{
    kind: InvalidValue,
    message: "unexpected argument: --foo",
    error_context: "",
    opt_name: "",
    tip: "",
  }
  inspect(
    info.to_string(),
    content=(
      #|error: unexpected argument: --foo
    ),
  )
  let info2 = ParseErrorInfo::{
    kind: InvalidValue,
    message: "unexpected argument: --foo",
    error_context: "\nUsage: [OPTIONS]\n\nFor more information, try '--help'.",
    opt_name: "",
    tip: "",
  }
  let expected = "error: unexpected argument: --foo\n\nUsage: [OPTIONS]\n\nFor more information, try '--help'."
  inspect(info2.to_string() == expected, content="true")
}

///|
test "subcommand error has child error_context" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose mode")
  let _ = p.cmd(
    name="serve",
    setup=fn(child) {
      let _ = child.int(name="port", default=8080, description="Set port")
    },
    description="Start server",
  )
  let result : Result[_, _] = try? p.parse(["serve", "--unknown"])
  match result {
    Err(ParseError(info)) => {
      inspect(
        info.message,
        content=(
          #|unexpected argument: --unknown
        ),
      )
      // 子パーサ (serve) の error_context が設定されている（Usage と footer を含む）
      inspect(info.error_context.contains("Usage:"), content="true")
      inspect(
        info.error_context.contains("For more information, try '--help'."),
        content="true",
      )
      // 親パーサのオプション (--verbose) は含まれない（子のコンテキストが優先）
      inspect(info.error_context.contains("--verbose"), content="false")
    }
    _ => abort("expected ParseError")
  }
}

///|

// === ErrorKind tests ===

///|
test "ErrorKind: UnknownOption for unknown --option" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let result : Result[_, _] = try? p.parse(["--unknown"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="UnknownOption")
      inspect(info.opt_name, content="--unknown")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: UnexpectedArgument for extra positional" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let result : Result[_, _] = try? p.parse(["extra"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="UnexpectedArgument")
      inspect(info.opt_name, content="extra")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: MissingValue for option without value" {
  let p = Parser::new()
  let _ = p.string(name="output", default="")
  let result : Result[_, _] = try? p.parse(["--output"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="MissingValue")
      inspect(info.opt_name, content="--output")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: InvalidValue for bad integer" {
  let p = Parser::new()
  let _ = p.int(name="count", default=0)
  let result : Result[_, _] = try? p.parse(["--count", "abc"])
  match result {
    Err(ParseError(info)) => inspect(info.kind, content="InvalidValue")
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: MissingRequired for required option" {
  let p = Parser::new()
  let opt = p.string(name="output", default="")
  p.required(opt.as_ref())
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="MissingRequired")
      inspect(info.opt_name, content="--output")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: ArgumentConflict for exclusive options" {
  let p = Parser::new()
  let a = p.flag(name="json")
  let b = p.flag(name="yaml")
  p.exclusive([a.as_ref(), b.as_ref()])
  let result : Result[_, _] = try? p.parse(["--json", "--yaml"])
  match result {
    Err(ParseError(info)) => inspect(info.kind, content="ArgumentConflict")
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: DuplicateDefinition for duplicate option name" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let _ = p.flag(name="verbose")
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => inspect(info.kind, content="DuplicateDefinition")
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: MissingSubcommand for require_cmd" {
  let p = Parser::new()
  let _ = p.sub(name="init")
  p.require_cmd()
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => inspect(info.kind, content="MissingSubcommand")
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: AtLeastOneRequired for at_least_one" {
  let p = Parser::new()
  let a = p.flag(name="json")
  let b = p.flag(name="yaml")
  p.at_least_one([a.as_ref(), b.as_ref()])
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => inspect(info.kind, content="AtLeastOneRequired")
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: DependencyMissing for requires" {
  let p = Parser::new()
  let target = p.string(name="output", default="")
  let source = p.flag(name="verbose")
  p.requires(target.as_ref(), source=source.as_ref())
  let result : Result[_, _] = try? p.parse(["--verbose"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="DependencyMissing")
      inspect(info.opt_name, content="--output")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: ParseAlreadyCalled for double parse" {
  let p = Parser::new()
  ignore(p.parse([]))
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => inspect(info.kind, content="ParseAlreadyCalled")
    _ => fail("expected ParseError")
  }
}

///|
test "ErrorKind: AmbiguousMatch enum variant exists" {
  // AmbiguousMatch は make_or_node 内部の同率最長一致で発生するエッジケース。
  // 直接トリガーは困難なため、kind enum の構築可能性を確認。
  let kind : ErrorKind = AmbiguousMatch
  inspect(kind, content="AmbiguousMatch")
}

// ============================================================
// Structured error display (4-layer format)
// ============================================================

///|
test "structured error: UnknownOption with suggestion" {
  let p = Parser::new()
  let _ = p.int(
    name="port",
    default=8080,
    description="ポート番号を指定",
  )
  let result : Result[ParseResult, _] = try? p.parse(["--prot"])
  match result {
    Err(ParseError(info)) => {
      // message にはサジェストを含まない
      inspect(info.message, content="unexpected argument: --prot")
      // tip にサジェスト情報
      inspect(info.tip, content="--port")
      // to_string 出力を検証
      let display = info.to_string()
      inspect(
        display.contains("error: unexpected argument: --prot"),
        content="true",
      )
      inspect(display.contains("  help:"), content="true")
      inspect(display.contains("--port"), content="true")
      inspect(display.contains("ポート番号を指定"), content="true")
      inspect(display.contains("[default: 8080]"), content="true")
      inspect(
        display.contains("  tip: a similar option exists: '--port'"),
        content="true",
      )
      inspect(display.contains("Usage:"), content="true")
      inspect(
        display.contains("For more information, try '--help'."),
        content="true",
      )
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: UnknownOption without suggestion" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let result : Result[ParseResult, _] = try? p.parse(["--xyz"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message, content="unexpected argument: --xyz")
      inspect(info.tip, content="")
      let display = info.to_string()
      // tip 行がないこと
      inspect(display.contains("tip:"), content="false")
      // Usage と footer は表示される
      inspect(display.contains("Usage:"), content="true")
      inspect(display.contains("For more information"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: MissingRequired" {
  let p = Parser::new()
  let opt = p.string(name="config", default="", description="Config file path")
  p.required(opt.as_ref())
  let result : Result[ParseResult, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="MissingRequired")
      let display = info.to_string()
      inspect(display.contains("error:"), content="true")
      inspect(display.contains("Usage:"), content="true")
      inspect(display.contains("For more information"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: InvalidValue" {
  let p = Parser::new()
  let _ = p.int(name="port", default=8080, description="Set port")
  let result : Result[ParseResult, _] = try? p.parse(["--port", "abc"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="InvalidValue")
      let display = info.to_string()
      inspect(display.contains("error:"), content="true")
      inspect(display.contains("Usage:"), content="true")
      inspect(display.contains("For more information"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: MissingValue" {
  let p = Parser::new()
  let _ = p.string(name="output", default="", description="Output file")
  let result : Result[ParseResult, _] = try? p.parse(["--output"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="MissingValue")
      inspect(info.opt_name, content="--output")
      let display = info.to_string()
      inspect(display.contains("error:"), content="true")
      // opt_name が設定されているので help 行が表示される
      inspect(display.contains("  help:"), content="true")
      inspect(display.contains("--output"), content="true")
      inspect(display.contains("Output file"), content="true")
      inspect(display.contains("Usage:"), content="true")
      inspect(display.contains("For more information"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: ArgumentConflict" {
  let p = Parser::new()
  let a = p.flag(name="json", description="JSON output")
  let b = p.flag(name="yaml", description="YAML output")
  p.exclusive([a.as_ref(), b.as_ref()])
  let result : Result[ParseResult, _] = try? p.parse(["--json", "--yaml"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="ArgumentConflict")
      let display = info.to_string()
      inspect(display.contains("error:"), content="true")
      inspect(display.contains("Usage:"), content="true")
      inspect(display.contains("For more information"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: help line for short option" {
  let p = Parser::new()
  let _ = p.custom(
    name="output",
    default="out.txt",
    shorts="o",
    description="Output path",
    pre=Filter::map(fn(s) { s }),
  )
  let result : Result[ParseResult, _] = try? p.parse(["--otuput"])
  match result {
    Err(ParseError(info)) => {
      // tip にサジェスト先のオプション名
      inspect(info.tip, content="--output")
      let display = info.to_string()
      // help 行にサジェスト先オプションの詳細が表示される
      inspect(display.contains("-o, --output"), content="true")
      inspect(display.contains("Output path"), content="true")
      inspect(display.contains("[default: out.txt]"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: UnexpectedArgument (non-option)" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  p.never()
  let result : Result[ParseResult, _] = try? p.parse(["hello"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="UnexpectedArgument")
      inspect(info.message, content="unexpected argument: hello")
      inspect(info.tip, content="")
      let display = info.to_string()
      inspect(display.contains("error:"), content="true")
      inspect(display.contains("tip:"), content="false")
      inspect(display.contains("Usage:"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "structured error: generate_usage standalone" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let _ = p.positional(name="file")
  let _ = p.rest(name="args")
  let usage = p.generate_usage()
  inspect(usage, content="Usage: [OPTIONS] <FILE> [ARGS]...")
}

///|
test "structured error: find_meta_by_opt_name" {
  let p = Parser::new()
  let _ = p.custom(
    name="output",
    default="",
    shorts="o",
    aliases=["out"],
    description="Output file",
    pre=Filter::map(fn(s) { s }),
  )
  // --output で検索
  inspect(p.find_meta_by_opt_name("--output") is Some(_), content="true")
  // -o (short) で検索
  inspect(p.find_meta_by_opt_name("-o") is Some(_), content="true")
  // --out (alias) で検索
  inspect(p.find_meta_by_opt_name("--out") is Some(_), content="true")
  // 存在しない名前
  inspect(p.find_meta_by_opt_name("--xyz") is None, content="true")
}

///|
test "structured error: format_opt_help_line" {
  let p = Parser::new()
  let _ = p.custom(
    name="port",
    default=8080,
    shorts="p",
    description="Set port",
    env="PORT",
    pre=Filter::parse_int(),
  )
  match p.find_meta_by_opt_name("--port") {
    Some(meta) => {
      let line = format_opt_help_line(meta)
      inspect(line.contains("-p, --port"), content="true")
      inspect(line.contains("Set port"), content="true")
      inspect(line.contains("[env: PORT]"), content="true")
      inspect(line.contains("[default: 8080]"), content="true")
    }
    None => fail("meta not found")
  }
}

// ============================================================
// C-1/C-2/C-3/C-4 review fix tests
// ============================================================

///|
test "C-1: MissingSubcommand 4-layer display with Commands section" {
  let p = Parser::new()
  let _ = p.sub(name="init", description="Initialize project")
  let _ = p.sub(name="build", description="Build project")
  p.require_cmd()
  let result : Result[ParseResult, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="MissingSubcommand")
      let display = info.to_string()
      // Commands section が含まれる
      inspect(display.contains("Commands:"), content="true")
      inspect(display.contains("init"), content="true")
      inspect(display.contains("build"), content="true")
      inspect(display.contains("Initialize project"), content="true")
      inspect(display.contains("Build project"), content="true")
      // Usage + footer が含まれる
      inspect(display.contains("Usage:"), content="true")
      inspect(display.contains("[COMMAND]"), content="true")
      inspect(
        display.contains("For more information, try '--help'."),
        content="true",
      )
    }
    _ => fail("expected ParseError")
  }
}

///|
test "C-1: AtLeastOneRequired 4-layer display" {
  let p = Parser::new()
  let a = p.flag(name="json", description="JSON output")
  let b = p.flag(name="yaml", description="YAML output")
  p.at_least_one([a.as_ref(), b.as_ref()])
  let result : Result[ParseResult, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="AtLeastOneRequired")
      let display = info.to_string()
      inspect(display.contains("error:"), content="true")
      inspect(display.contains("Usage:"), content="true")
      inspect(
        display.contains("For more information, try '--help'."),
        content="true",
      )
    }
    _ => fail("expected ParseError")
  }
}

///|
test "C-1: DependencyMissing 4-layer display" {
  let p = Parser::new()
  let target = p.string(name="output", default="", description="Output path")
  let source = p.flag(name="verbose")
  p.requires(target.as_ref(), source=source.as_ref())
  let result : Result[ParseResult, _] = try? p.parse(["--verbose"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="DependencyMissing")
      inspect(info.opt_name, content="--output")
      let display = info.to_string()
      inspect(display.contains("error:"), content="true")
      // opt_name が設定されているので help 行が表示される
      inspect(display.contains("  help:"), content="true")
      inspect(display.contains("--output"), content="true")
      inspect(display.contains("Output path"), content="true")
      inspect(display.contains("Usage:"), content="true")
      inspect(
        display.contains("For more information, try '--help'."),
        content="true",
      )
    }
    _ => fail("expected ParseError")
  }
}

///|
test "C-1: MissingRequired help line display" {
  let p = Parser::new()
  let opt = p.string(name="config", default="", description="Config file path")
  p.required(opt.as_ref())
  let result : Result[ParseResult, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="MissingRequired")
      inspect(info.opt_name, content="--config")
      let display = info.to_string()
      // opt_name が設定されているので help 行が表示される
      inspect(display.contains("  help:"), content="true")
      inspect(display.contains("--config"), content="true")
      inspect(display.contains("Config file path"), content="true")
      inspect(display.contains("Usage:"), content="true")
      inspect(
        display.contains("For more information, try '--help'."),
        content="true",
      )
    }
    _ => fail("expected ParseError")
  }
}

///|
test "C-3: hidden option not shown in error help line" {
  let p = Parser::new()
  let _ = p.string(name="secret", default="", hidden=true)
  let result : Result[ParseResult, _] = try? p.parse(["--secrt"])
  match result {
    Err(ParseError(info)) => {
      // typo suggestion で --secret が tip に入る
      inspect(info.tip, content="--secret")
      let display = info.to_string()
      // hidden なので help 行は表示されない
      inspect(display.contains("  help:"), content="false")
      // tip 行は表示される（サジェスト自体は有用）
      inspect(display.contains("tip:"), content="true")
      inspect(display.contains("Usage:"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "C-4: find_meta_by_opt_name finds variation_names" {
  let p = Parser::new()
  let _ = p.flag(
    name="verbose",
    description="Enable verbose",
    variation_toggle=Some("no"),
  )
  // variation_names は "--no-verbose" の形で格納される
  inspect(p.find_meta_by_opt_name("--no-verbose") is Some(_), content="true")
  // 通常の名前検索も引き続き動作
  inspect(p.find_meta_by_opt_name("--verbose") is Some(_), content="true")
  // 存在しない名前
  inspect(p.find_meta_by_opt_name("--no-debug") is None, content="true")
}

///|
test "to_string layer order: error → help → tip → Usage → footer" {
  let p = Parser::new()
  let _ = p.int(name="port", default=8080, description="Server port")
  let result : Result[ParseResult, _] = try? p.parse(["--prot"])
  match result {
    Err(ParseError(info)) => {
      let display = info.to_string()
      // 各セクションの出現位置を確認（indexOf ベースで順序検証）
      let error_pos = display.find("error:")
      let help_pos = display.find("  help:")
      let tip_pos = display.find("  tip:")
      let usage_pos = display.find("Usage:")
      let footer_pos = display.find("For more information")
      // 全て存在する
      assert_true(error_pos is Some(_))
      assert_true(help_pos is Some(_))
      assert_true(tip_pos is Some(_))
      assert_true(usage_pos is Some(_))
      assert_true(footer_pos is Some(_))
      // 順序: error < help < tip < Usage < footer
      assert_true(error_pos.unwrap() < help_pos.unwrap())
      assert_true(help_pos.unwrap() < tip_pos.unwrap())
      assert_true(tip_pos.unwrap() < usage_pos.unwrap())
      assert_true(usage_pos.unwrap() < footer_pos.unwrap())
    }
    _ => fail("expected ParseError")
  }
}

///|
test "generate_usage includes [COMMAND] when commands exist" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let _ = p.sub(name="init")
  let _ = p.sub(name="build")
  let usage = p.generate_usage()
  inspect(usage.contains("[COMMAND]"), content="true")
  inspect(usage.contains("[OPTIONS]"), content="true")
}
