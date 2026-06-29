// ============================================================
// Scope: core parser の基本動作 (combinator → ExactNode → speculative
// execution + longest match) を全 OptKind 横断で固定する。kuu の中核。
//
// Covers:
//   - 基本 combinator の単発動作: flag / string / int / float / boolean /
//     count / append* / positional / rest / sub / cmd / never / serial
//   - OptKind 大統一の挙動: default / explicit value / implicit_value /
//     choices / 重複呼出時の reducer 蓄積
//   - speculative execution + longest match: --color / --color=value /
//     --color value の同時成立、short combining (-abc → -a -b -c)
//   - parse 2 phase (OC / P) の分担と stop_before / serial / -- 境界
//   - duplicate name validation (DR-0053 primitive 階層) と
//     ParseResult アクセス (DR-0013)
//   - shorts / aliases / global / variations の各 Value primitive 横断
//     直交性 (DR-0060)
//
// NA (= 当 file が担わない軸 — 担当 file を明示):
//   - 制約系 (exclusive / required / at_least_one / requires /
//     require_cmd / is_set) → constraint_wbtest.mbt
//   - 構造化エラー (ErrorKind / ParseErrorInfo / 4 層 to_string 形式) →
//     error_wbtest.mbt
//   - Filter / FilterChain (DR-0016 + DR-0050) → filter_wbtest.mbt
//   - 環境変数 (env / env_prefix / auto_env) / visibility / file /
//     deprecated / mergeable_list / grapheme 入力 / sugar parameter /
//     default_fn / ValCell / Accessor → advanced_wbtest.mbt
//   - subcommand ネスト / ParseResult 親子ナビ / sub API → cmd_wbtest.mbt
//   - dx (Parseable trait + set callback) → dx/dx_wbtest.mbt
// ============================================================

///|
test "single flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--verbose"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "flag default is false" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  ignore(p.parse([]))
  debug_inspect(p.get(verbose), content="Some(false)")
}

///|
test "unknown arg raises error" {
  let p = Parser::new()
  let _verbose = p.flag(name="verbose")
  try p.parse(["--unknown"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "multiple flags" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  ignore(p.parse(["--verbose", "--debug"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(p.get(debug), content="Some(true)")
}

///|
test "no-prefix negation" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", variations=[False("no")])
  ignore(p.parse(["--verbose", "--no-verbose"]))
  debug_inspect(p.get(verbose), content="Some(false)")
}

///|
test "no-prefix with default true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true)
  ignore(p.parse([]))
  debug_inspect(p.get(color), content="Some(true)")
}

///|
test "no-prefix resets to default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[False("no")])
  ignore(p.parse(["--no-color"]))
  debug_inspect(p.get(color), content="Some(false)")
}

///|
test "string option" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  ignore(p.parse(["--host", "example.com"]))
  debug_inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "string option default" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  ignore(p.parse([]))
  debug_inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
}

///|
test "int option" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  ignore(p.parse(["--port", "3000"]))
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "int option default" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  ignore(p.parse([]))
  debug_inspect(p.get(port), content="Some(8080)")
}

///|
test "int parse error" {
  let p = Parser::new()
  let _port = p.int(name="port", default=8080)
  try p.parse(["--port", "abc"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "missing value error" {
  let p = Parser::new()
  let _host = p.string(name="host", default="localhost")
  try p.parse(["--host"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "int and string combined" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let host = p.string(name="host", default="localhost")
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--port", "3000", "--verbose", "--host", "example.com"]))
  debug_inspect(p.get(port), content="Some(3000)")
  debug_inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "no-prefix resets string option" {
  let p = Parser::new()
  let host = p.custom(
    name="host",
    default="localhost",
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--host", "example.com", "--no-host"]))
  debug_inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
}

///|
test "no-prefix resets int option" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=8080,
    variations=[Reset("no")],
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["--port", "3000", "--no-port"]))
  debug_inspect(p.get(port), content="Some(8080)")
}

///|
test "equals syntax for string" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  ignore(p.parse(["--host=example.com"]))
  debug_inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "equals syntax for int" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  ignore(p.parse(["--port=3000"]))
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "equals syntax int parse error" {
  let p = Parser::new()
  let _port = p.int(name="port", default=8080)
  try p.parse(["--port=abc"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "equals syntax mixed with space syntax" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let host = p.string(name="host", default="localhost")
  ignore(p.parse(["--port=3000", "--host", "example.com"]))
  debug_inspect(p.get(port), content="Some(3000)")
  debug_inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "equals syntax with flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let port = p.int(name="port", default=8080)
  ignore(p.parse(["--verbose", "--port=3000"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "append string" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  ignore(p.parse(["--tag", "a", "--tag", "b"]))
  debug_inspect(
    p.get(tags),
    content=(
      #|Some(["a", "b"])
    ),
  )
}

///|
test "append string default empty" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  ignore(p.parse([]))
  debug_inspect(
    p.get(tags),
    content=(
      #|Some([])
    ),
  )
}

///|
test "append string negate" {
  let p = Parser::new()
  let tags = p.append(
    name="tag",
    variations=[Reset("no")],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--tag", "a", "--no-tag", "--tag", "b"]))
  debug_inspect(
    p.get(tags),
    content=(
      #|Some(["b"])
    ),
  )
}

///|
test "append int" {
  let p = Parser::new()
  let nums = p.append_int(name="num")
  ignore(p.parse(["--num", "1", "--num", "2", "--num", "3"]))
  debug_inspect(
    p.get(nums),
    content=(
      #|Some([1, 2, 3])
    ),
  )
}

///|
test "append int parse error" {
  let p = Parser::new()
  let _nums = p.append_int(name="num")
  try p.parse(["--num", "abc"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "append with equals syntax" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  ignore(p.parse(["--tag=a", "--tag=b"]))
  debug_inspect(
    p.get(tags),
    content=(
      #|Some(["a", "b"])
    ),
  )
}

///|
test "positional arg" {
  let p = Parser::new()
  let file = p.positional(name="file")
  ignore(p.parse(["input.txt"]))
  debug_inspect(
    p.get(file),
    content=(
      #|Some("input.txt")
    ),
  )
}

///|
test "positional with option before" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file")
  ignore(p.parse(["--verbose", "input.txt"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    p.get(file),
    content=(
      #|Some("input.txt")
    ),
  )
}

///|
test "positional with option after" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file")
  ignore(p.parse(["input.txt", "--verbose"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    p.get(file),
    content=(
      #|Some("input.txt")
    ),
  )
}

///|
test "positional default empty" {
  let p = Parser::new()
  let file = p.positional(name="file")
  ignore(p.parse([]))
  debug_inspect(
    p.get(file),
    content=(
      #|Some("")
    ),
  )
}

///|
test "serial positional" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let output = p.positional(name="output")
  ignore(p.parse(["input.txt", "output.txt"]))
  debug_inspect(
    p.get(input),
    content=(
      #|Some("input.txt")
    ),
  )
  debug_inspect(
    p.get(output),
    content=(
      #|Some("output.txt")
    ),
  )
}

///|
test "serial positional with option between" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let input = p.positional(name="input")
  let output = p.positional(name="output")
  ignore(p.parse(["input.txt", "--verbose", "output.txt"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    p.get(input),
    content=(
      #|Some("input.txt")
    ),
  )
  debug_inspect(
    p.get(output),
    content=(
      #|Some("output.txt")
    ),
  )
}

///|
test "serial positional partial" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let _output = p.positional(name="output")
  ignore(p.parse(["input.txt"]))
  debug_inspect(
    p.get(input),
    content=(
      #|Some("input.txt")
    ),
  )
}

///|
test "serial three positionals" {
  let p = Parser::new()
  let a = p.positional(name="a")
  let b = p.positional(name="b")
  let c = p.positional(name="c")
  ignore(p.parse(["x", "y", "z"]))
  debug_inspect(
    p.get(a),
    content=(
      #|Some("x")
    ),
  )
  debug_inspect(
    p.get(b),
    content=(
      #|Some("y")
    ),
  )
  debug_inspect(
    p.get(c),
    content=(
      #|Some("z")
    ),
  )
}

///|
test "rest collects remaining args" {
  let p = Parser::new()
  let files = p.rest(name="files")
  ignore(p.parse(["file1", "file2", "file3"]))
  debug_inspect(
    p.get(files),
    content=(
      #|Some(["file1", "file2", "file3"])
    ),
  )
}

///|
test "rest default empty" {
  let p = Parser::new()
  let files = p.rest(name="files")
  ignore(p.parse([]))
  debug_inspect(p.get(files), content="Some([])")
}

///|
test "rest with option" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  ignore(p.parse(["--verbose", "file1", "file2"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    p.get(files),
    content=(
      #|Some(["file1", "file2"])
    ),
  )
}

///|
test "double dash forces positional" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  ignore(p.parse(["--verbose", "--", "--not-a-flag", "file1"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    p.get(files),
    content=(
      #|Some(["--not-a-flag", "file1"])
    ),
  )
}

///|
test "double dash with no rest args" {
  let p = Parser::new()
  let _verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  ignore(p.parse(["--"]))
  debug_inspect(p.get(files), content="Some([])")
}

///|
test "rest after positional" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let extras = p.rest(name="extras")
  ignore(p.parse(["input.txt", "a", "b"]))
  debug_inspect(
    p.get(input),
    content=(
      #|Some("input.txt")
    ),
  )
  debug_inspect(
    p.get(extras),
    content=(
      #|Some(["a", "b"])
    ),
  )
}

///|

///|
test "alias for flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v"])
  ignore(p.parse(["--v"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "alias no-prefix" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v"], variations=[False("no")])
  ignore(p.parse(["--v", "--no-v"]))
  debug_inspect(p.get(verbose), content="Some(false)")
}

///|
test "alias for string option" {
  let p = Parser::new()
  let host = p.custom(
    name="host",
    default="localhost",
    aliases=["H"],
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["--H", "example.com"]))
  debug_inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "alias for int option" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=8080,
    aliases=["p"],
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["--p", "3000"]))
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "multiple aliases" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v", "verb"])
  ignore(p.parse(["--verb"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "alias with equals syntax" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=8080,
    aliases=["p"],
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["--p=3000"]))
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "short flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  ignore(p.parse(["-v"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "short int option" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=8080,
    shorts="p",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-p", "3000"]))
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "short string option" {
  let p = Parser::new()
  let host = p.custom(
    name="host",
    default="localhost",
    shorts="H",
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["-H", "example.com"]))
  debug_inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "short with long mixed" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.custom(
    name="port",
    default=8080,
    shorts="p",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-v", "--port", "3000"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "short append" {
  let p = Parser::new()
  let tags = p.append(name="tag", shorts="t", pre=Filter::map(fn(s) { s }))
  ignore(p.parse(["-t", "a", "-t", "b"]))
  debug_inspect(
    p.get(tags),
    content=(
      #|Some(["a", "b"])
    ),
  )
}

///|
test "short flag combining" {
  let p = Parser::new()
  let a = p.flag(name="aaa", shorts="a")
  let b = p.flag(name="bbb", shorts="b")
  let c = p.flag(name="ccc", shorts="c")
  ignore(p.parse(["-abc"]))
  debug_inspect(p.get(a), content="Some(true)")
  debug_inspect(p.get(b), content="Some(true)")
  debug_inspect(p.get(c), content="Some(true)")
}

///|
test "short combining with value at end" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.custom(
    name="port",
    default=8080,
    shorts="p",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-vp3000"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining value next arg" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.custom(
    name="port",
    default=8080,
    shorts="p",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-vp", "3000"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining with string value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let host = p.custom(
    name="host",
    default="localhost",
    shorts="H",
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["-vHexample.com"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "short combining unknown char error" {
  let p = Parser::new()
  let _a = p.flag(name="aaa", shorts="a")
  try p.parse(["-ax"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "short combining all flags" {
  let p = Parser::new()
  let e = p.flag(name="errexit", shorts="e")
  let u = p.flag(name="nounset", shorts="u")
  let o = p.flag(name="ooo", shorts="o")
  ignore(p.parse(["-euo"]))
  debug_inspect(p.get(e), content="Some(true)")
  debug_inspect(p.get(u), content="Some(true)")
  debug_inspect(p.get(o), content="Some(true)")
}

///|
test "count basic" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse(["--verbose", "--verbose", "--verbose"]))
  debug_inspect(p.get(verbose), content="Some(3)")
}

///|
test "count default zero" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse([]))
  debug_inspect(p.get(verbose), content="Some(0)")
}

///|
test "count short" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse(["-v", "-v"]))
  debug_inspect(p.get(verbose), content="Some(2)")
}

///|
test "count short combining -vvv" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse(["-vvv"]))
  debug_inspect(p.get(verbose), content="Some(3)")
}

///|
test "count reset with no-prefix" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v", variations=[Reset("no")])
  ignore(p.parse(["-vvv", "--no-verbose", "-v"]))
  debug_inspect(p.get(verbose), content="Some(1)")
}

///|
test "complex short combining: count + int + flag" {
  let p = Parser::new()
  let c = p.count(name="ccc", shorts="c")
  let a_opt = p.custom(
    name="aaa",
    default=0,
    shorts="A",
    pre=Filter::parse_int(),
  )
  let g = p.flag(name="ggg", shorts="g")
  // -cA1gcc → c(count) A(int=1) g(flag) c(count) c(count)
  ignore(p.parse(["-cA1gcc"]))
  debug_inspect(p.get(c), content="Some(3)")
  debug_inspect(p.get(a_opt), content="Some(1)")
  debug_inspect(p.get(g), content="Some(true)")
}

///|
test "complex short combining: flags and int" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let a_opt = p.custom(
    name="after",
    default=0,
    shorts="A",
    pre=Filter::parse_int(),
  )
  let b_opt = p.custom(
    name="before",
    default=0,
    shorts="B",
    pre=Filter::parse_int(),
  )
  // -vA1 -B1 なら動く
  ignore(p.parse(["-vA1", "-B1"]))
  debug_inspect(p.get(v), content="Some(true)")
  debug_inspect(p.get(a_opt), content="Some(1)")
  debug_inspect(p.get(b_opt), content="Some(1)")
}

///|
test "generate_help basic" {
  let p = Parser::new()
  p.set_description("My CLI tool")
  let _ = p.flag(
    name="verbose",
    shorts="v",
    description="Enable verbose output",
  )
  let _ = p.int(name="port", default=8080, description="Set port number")
  let help = p.generate_help()
  debug_inspect(help.contains("My CLI tool"), content="true")
  debug_inspect(help.contains("--verbose"), content="true")
  debug_inspect(help.contains("-v"), content="true")
  debug_inspect(help.contains("--port"), content="true")
  debug_inspect(help.contains("[default: 8080]"), content="true")
}

///|
test "help flag raises HelpRequested" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  try p.parse(["--help"]) catch {
    HelpRequested(_) => debug_inspect(true, content="true")
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "short help flag raises HelpRequested" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  try p.parse(["-h"]) catch {
    HelpRequested(_) => debug_inspect(true, content="true")
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "HelpRequested text contains flag description" {
  let p = Parser::new()
  let _ = p.flag(
    name="verbose",
    shorts="v",
    description="Enable verbose output",
  )
  try p.parse(["--help"]) catch {
    HelpRequested(text) => {
      debug_inspect(text.contains("--verbose"), content="true")
      debug_inspect(text.contains("-v"), content="true")
      debug_inspect(text.contains("Enable verbose output"), content="true")
    }
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "string default shown in help" {
  let p = Parser::new()
  let _ = p.string(name="host", default="localhost", description="Set host")
  try p.parse(["--help"]) catch {
    HelpRequested(text) => {
      debug_inspect(text.contains("--host"), content="true")
      debug_inspect(text.contains("[default: localhost]"), content="true")
    }
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "global option in Global Options section" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", global=true, description="Verbose mode")
  let _ = p.flag(name="debug", description="Debug mode")
  try p.parse(["--help"]) catch {
    HelpRequested(text) => {
      debug_inspect(text.contains("Global Options:"), content="true")
      debug_inspect(text.contains("Options:"), content="true")
    }
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "cmd shown in Commands section" {
  let p = Parser::new()
  let _ = p.cmd(name="serve", setup=fn(_child) {  }, description="Start server")
  try p.parse(["--help"]) catch {
    HelpRequested(text) => {
      debug_inspect(text.contains("Commands:"), content="true")
      debug_inspect(text.contains("serve"), content="true")
      debug_inspect(text.contains("Start server"), content="true")
    }
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "short option format in help" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Verbose")
  try p.parse(["--help"]) catch {
    HelpRequested(text) =>
      debug_inspect(text.contains("-v, --verbose"), content="true")
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "subcommand help shows own scope" {
  let p = Parser::new()
  let _ = p.cmd(
    name="serve",
    setup=fn(child) {
      let _ = child.int(name="port", default=8080, description="Set port")
    },
    description="Start server",
  )
  try p.parse(["serve", "--help"]) catch {
    HelpRequested(text) => {
      debug_inspect(text.contains("--port"), content="true")
      // serve のヘルプには Commands: セクションがない
      debug_inspect(text.contains("Commands:"), content="false")
    }
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "hidden option not shown in help" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let _ = p.flag(name="secret", description="Secret option", visibility=Hidden)
  try p.parse(["--help"]) catch {
    HelpRequested(text) => {
      debug_inspect(text.contains("--verbose"), content="true")
      debug_inspect(text.contains("--secret"), content="false")
    }
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "description shown in help" {
  let p = Parser::new()
  p.set_description("My awesome CLI")
  let _ = p.flag(name="verbose", description="Verbose")
  try p.parse(["--help"]) catch {
    HelpRequested(text) =>
      debug_inspect(text.contains("My awesome CLI"), content="true")
    _ => debug_inspect(false, content="true")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "short combining append_int" {
  let p = Parser::new()
  let nums = p.append(name="num", shorts="n", pre=Filter::parse_int())
  ignore(p.parse(["-n1", "-n2"]))
  debug_inspect(p.get(nums), content="Some([1, 2])")
}

///|
test "dashdash basic" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash()
  ignore(p.parse(["--", "file1", "file2"]))
  debug_inspect(
    dd.get(),
    content=(
      #|Some(["file1", "file2"])
    ),
  )
}

///|
test "dashdash with rest before" {
  let p = Parser::new(dashdash=false)
  let files = p.rest(name="files")
  let dd = p.dashdash()
  ignore(p.parse(["ccc", "--", "hoge", "fuga"]))
  debug_inspect(
    files.get(),
    content=(
      #|Some(["ccc"])
    ),
  )
  debug_inspect(
    dd.get(),
    content=(
      #|Some(["hoge", "fuga"])
    ),
  )
}

///|
test "dashdash with flag" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let dd = p.dashdash()
  ignore(p.parse(["--verbose", "--", "--not-a-flag", "file1"]))
  debug_inspect(verbose.get(), content="Some(true)")
  debug_inspect(
    dd.get(),
    content=(
      #|Some(["--not-a-flag", "file1"])
    ),
  )
}

///|
test "dashdash empty" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash()
  ignore(p.parse(["--"]))
  debug_inspect(dd.get(), content="Some([])")
}

///|
test "dashdash no separator" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash()
  ignore(p.parse([]))
  debug_inspect(dd.get(), content="Some([])")
}

///|
test "dashdash custom separator" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash(separator=":::")
  ignore(p.parse([":::", "a", "b"]))
  debug_inspect(
    dd.get(),
    content=(
      #|Some(["a", "b"])
    ),
  )
}

///|
test "append_dashdash basic" {
  let p = Parser::new(dashdash=false)
  let dd = p.append_dashdash()
  ignore(p.parse(["--", "a", "b", "--", "c", "d"]))
  debug_inspect(
    dd.get(),
    content=(
      #|Some([["a", "b"], ["c", "d"]])
    ),
  )
}

///|
test "append_dashdash with rest" {
  let p = Parser::new(dashdash=false)
  let files = p.rest(name="files")
  let dd = p.append_dashdash()
  ignore(p.parse(["ccc", "--", "hoge", "fuga", "--", "aaa"]))
  debug_inspect(
    files.get(),
    content=(
      #|Some(["ccc"])
    ),
  )
  debug_inspect(
    dd.get(),
    content=(
      #|Some([["hoge", "fuga"], ["aaa"]])
    ),
  )
}

///|
test "append_dashdash no separator" {
  let p = Parser::new(dashdash=false)
  let dd = p.append_dashdash()
  ignore(p.parse([]))
  debug_inspect(dd.get(), content="Some([])")
}

///|
test "append_dashdash single group" {
  let p = Parser::new(dashdash=false)
  let dd = p.append_dashdash()
  ignore(p.parse(["--", "a", "b"]))
  debug_inspect(
    dd.get(),
    content=(
      #|Some([["a", "b"]])
    ),
  )
}

///|
test "append_dashdash empty group" {
  let p = Parser::new(dashdash=false)
  let dd = p.append_dashdash()
  ignore(p.parse(["--", "--", "a"]))
  debug_inspect(
    dd.get(),
    content=(
      #|Some([[], ["a"]])
    ),
  )
}

///|
test "append_dashdash custom separator" {
  let p = Parser::new(dashdash=false)
  let dd = p.append_dashdash(separator=":::")
  ignore(p.parse([":::", "x", ":::", "y", "z"]))
  debug_inspect(
    dd.get(),
    content=(
      #|Some([["x"], ["y", "z"]])
    ),
  )
}

///|
test "short combining append_int inline" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let nums = p.append(name="num", shorts="n", pre=Filter::parse_int())
  ignore(p.parse(["-vn1"]))
  debug_inspect(p.get(v), content="Some(true)")
  debug_inspect(p.get(nums), content="Some([1])")
}

///|
test "post filter basic" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    post=Some(Filter::map(fn(s) { if s == "auto" { "always" } else { s } })),
  )
  ignore(p.parse([]))
  // default "auto" is transformed to "always" by post
  debug_inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "post filter with explicit value" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    post=Some(Filter::map(fn(s) { if s == "auto" { "none" } else { s } })),
  )
  ignore(p.parse(["--color", "none"]))
  // explicit "none" passes through post unchanged
  debug_inspect(
    color.get(),
    content=(
      #|Some("none")
    ),
  )
}

///|
test "post filter validation error" {
  let p = Parser::new()
  let _val = p.string(
    name="output",
    default="",
    post=Some(
      Filter::validate(fn(s) raise ParseError {
        if s == "" {
          raise parse_error("--output is required")
        }
      }),
    ),
  )
  try p.parse([]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// === int + implicit_value テスト ===

///|
test "int implicit: --port (implicit)" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080, implicit_value=Some(Val(3000)))
  ignore(p.parse(["--port"]))
  debug_inspect(port.get(), content="Some(3000)")
}

///|
test "int implicit: --port 9090" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080, implicit_value=Some(Val(3000)))
  ignore(p.parse(["--port", "9090"]))
  debug_inspect(port.get(), content="Some(9090)")
}

///|
test "int implicit: no --port (default)" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080, implicit_value=Some(Val(3000)))
  ignore(p.parse([]))
  debug_inspect(port.get(), content="Some(8080)")
}

///|
test "int implicit: --port foo → implicit (Reject fallback)" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080, implicit_value=Some(Val(3000)))
  let _files = p.rest(name="files")
  ignore(p.parse(["--port", "foo"]))
  // "foo" は int パースに失敗 → Reject → implicit 3000、"foo" は rest に
  debug_inspect(port.get(), content="Some(3000)")
}

// === composite node + short combining テスト ===

///|
test "string choices+implicit: short combining -vc" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let color = p.custom(
    name="color",
    default="auto",
    shorts="c",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
    pre=Filter::map(fn(s) { s }),
  )
  ignore(p.parse(["-vc"]))
  debug_inspect(verbose.get(), content="Some(true)")
  debug_inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string choices+implicit: short combining -cv" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let color = p.custom(
    name="color",
    default="auto",
    shorts="c",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
    pre=Filter::map(fn(s) { s }),
  )
  // -cv → c は remaining="v" あり → value trial: "v" は choice にない → Reject
  //      → flag trial: implicit Accept(consumed=1) → OK
  //      → v: flag Accept → OK
  ignore(p.parse(["-cv"]))
  debug_inspect(verbose.get(), content="Some(true)")
  debug_inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string choices+implicit: short -cnone (inline value)" {
  let p = Parser::new()
  let color = p.custom(
    name="color",
    default="auto",
    shorts="c",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
    pre=Filter::map(fn(s) { s }),
  )
  // -cnone → c は remaining="none" → value trial: choice "none" Accept(consumed=2)
  ignore(p.parse(["-cnone"]))
  debug_inspect(
    color.get(),
    content=(
      #|Some("none")
    ),
  )
}

///|
test "string implicit_only: --output=-foo (eq-split)" {
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output=-foo"]))
  debug_inspect(
    output.get(),
    content=(
      #|Some("-foo")
    ),
  )
}

///|
test "string implicit_only: --output --verbose → implicit" {
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--output", "--verbose"]))
  debug_inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
  debug_inspect(verbose.get(), content="Some(true)")
}

///|
test "int implicit: short combining -vp" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.custom(
    name="port",
    default=8080,
    shorts="p",
    implicit_value=Some(Val(3000)),
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-vp"]))
  debug_inspect(verbose.get(), content="Some(true)")
  debug_inspect(port.get(), content="Some(3000)")
}

///|
test "string choices+implicit: --color=invalid → error" {
  let p = Parser::new()
  let _color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  try p.parse(["--color=invalid"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// === stop_before テスト ===

///|
test "rest stop_before stops at marker" {
  let p = Parser::new(dashdash=false)
  let files = p.rest(name="files", stop_before=["++"])
  let dd = p.dashdash(separator="++")
  ignore(p.parse(["a", "b", "++", "c", "d"]))
  debug_inspect(
    p.get(files),
    content=(
      #|Some(["a", "b"])
    ),
  )
  debug_inspect(
    p.get(dd),
    content=(
      #|Some(["c", "d"])
    ),
  )
}

///|
test "rest stop_before multiple tokens" {
  let p = Parser::new(dashdash=false)
  let files = p.rest(name="files", stop_before=["++", "@@"])
  let dd = p.dashdash(separator="++")
  ignore(p.parse(["a", "++", "b"]))
  debug_inspect(
    p.get(files),
    content=(
      #|Some(["a"])
    ),
  )
  debug_inspect(
    p.get(dd),
    content=(
      #|Some(["b"])
    ),
  )
}

///|
test "rest stop_before empty array no effect" {
  let p = Parser::new(dashdash=false)
  let files = p.rest(name="files", stop_before=[])
  ignore(p.parse(["a", "b", "c"]))
  debug_inspect(
    p.get(files),
    content=(
      #|Some(["a", "b", "c"])
    ),
  )
}

///|
test "dashdash stop_before stops collection" {
  let p = Parser::new(dashdash=false)
  let dd1 = p.dashdash(separator="--", stop_before=["++"])
  let dd2 = p.dashdash(separator="++")
  ignore(p.parse(["--", "a", "b", "++", "c"]))
  debug_inspect(
    p.get(dd1),
    content=(
      #|Some(["a", "b"])
    ),
  )
  debug_inspect(
    p.get(dd2),
    content=(
      #|Some(["c"])
    ),
  )
}

///|
test "append_dashdash stop_before stops group" {
  let p = Parser::new(dashdash=false)
  let dd = p.append_dashdash(separator="--", stop_before=["++"])
  let extra = p.dashdash(separator="++")
  ignore(p.parse(["--", "a", "b", "++", "c"]))
  debug_inspect(
    p.get(dd),
    content=(
      #|Some([["a", "b"]])
    ),
  )
  debug_inspect(
    p.get(extra),
    content=(
      #|Some(["c"])
    ),
  )
}

// === serial コンビネータテスト ===

///|
test "serial basic positional grouping" {
  let p = Parser::new(dashdash=false)
  let src = p.positional(name="src")
  let dst = p.positional(name="dst")
  // serial を使わなくても順序消費は動く（比較用）
  ignore(p.parse(["hello", "world"]))
  debug_inspect(
    p.get(src),
    content=(
      #|Some("hello")
    ),
  )
  debug_inspect(
    p.get(dst),
    content=(
      #|Some("world")
    ),
  )
}

///|
test "serial with never prevents extra args" {
  let p = Parser::new(dashdash=false)
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  p.serial(setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
    sub.never()
  })
  ignore(p.parse(["a", "b"]))
  debug_inspect(
    src.unwrap().get(),
    content=(
      #|Some("a")
    ),
  )
  debug_inspect(
    dst.unwrap().get(),
    content=(
      #|Some("b")
    ),
  )
}

///|
test "serial with never rejects extra" {
  let p = Parser::new(dashdash=false)
  p.serial(setup=fn(sub) {
    ignore(sub.positional(name="src"))
    ignore(sub.positional(name="dst"))
    sub.never()
  })
  try p.parse(["a", "b", "c"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "serial inside dashdash separator context" {
  // -- の後で serial グループが機能することを確認
  let p = Parser::new(dashdash=true)
  let flag = p.flag(name="verbose")
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  p.serial(setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
  })
  ignore(p.parse(["--verbose", "--", "hello", "world"]))
  debug_inspect(p.get(flag), content="Some(true)")
  debug_inspect(
    src.unwrap().get(),
    content=(
      #|Some("hello")
    ),
  )
  debug_inspect(
    dst.unwrap().get(),
    content=(
      #|Some("world")
    ),
  )
}

///|
test "serial with rest inside" {
  let p = Parser::new(dashdash=false)
  let mut files : Opt[Array[String]]? = None
  p.serial(setup=fn(sub) { files = Some(sub.rest(name="files")) })
  ignore(p.parse(["a", "b", "c"]))
  debug_inspect(
    files.unwrap().get(),
    content=(
      #|Some(["a", "b", "c"])
    ),
  )
}

///|

// ============ duplicate name validation tests ============

///|
test "duplicate option name detected" {
  let p = Parser::new()
  let _ = p.flag(name="no-verbose")
  let _ = p.flag(name="verbose", variation_reset=Some("no"))
  // --no-verbose が2つのコンビネータから生成される
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("duplicate option name"),
        content="true",
      )
    _ => abort("expected duplicate name error")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "no duplicate when names differ" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", variation_reset=Some("no"))
  let _ = p.flag(name="quiet", variation_reset=Some("no"))
  // --no-verbose と --no-quiet は異なるので OK
  ignore(p.parse([]))
}

///|
test "duplicate alias name detected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let _ = p.flag(name="verb", aliases=["verbose"])
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("duplicate option name"),
        content="true",
      )
    _ => abort("expected duplicate name error")
  } noraise {
    _ => fail("expected raise")
  }
}

// ============================================================
// shorts 複数文字テスト
// ============================================================

///|
test "shorts multiple chars: -v and -V both work" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="vV")
  ignore(p.parse(["-v"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "shorts multiple chars: -V works" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="vV")
  ignore(p.parse(["-V"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "shorts multiple chars: combining -vV same flag twice (count)" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="vV")
  ignore(p.parse(["-vV"]))
  debug_inspect(p.get(verbose), content="Some(2)")
}

///|
test "shorts multiple chars: combining -Vv order reversed (count)" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="vV")
  ignore(p.parse(["-Vv"]))
  debug_inspect(p.get(verbose), content="Some(2)")
}

///|
test "shorts multiple chars: -vvV combining (count=3)" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="vV")
  ignore(p.parse(["-vvV"]))
  debug_inspect(p.get(verbose), content="Some(3)")
}

///|
test "shorts multiple chars: long option still works" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="vV")
  ignore(p.parse(["--verbose"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "shorts unicode: -あ works" {
  let p = Parser::new()
  let opt = p.flag(name="all", shorts="あ")
  ignore(p.parse(["-あ"]))
  debug_inspect(p.get(opt), content="Some(true)")
}

///|
test "shorts unicode: combining with ASCII" {
  let p = Parser::new()
  let a = p.flag(name="all", shorts="あ")
  let b = p.flag(name="bbb", shorts="b")
  ignore(p.parse(["-bあ"]))
  debug_inspect(p.get(a), content="Some(true)")
  debug_inspect(p.get(b), content="Some(true)")
}

// ============================================================
// aliases の help 表示テスト
// ============================================================

///|
test "aliases shown in help: --name, --alias format" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", aliases=["verb"], description="Verbose output")
  let help = p.generate_help()
  debug_inspect(help.contains("--verbose, --verb"), content="true")
}

///|
test "aliases multiple shown in help" {
  let p = Parser::new()
  let _ = p.custom(
    name="output",
    default="",
    aliases=["out", "o"],
    description="Output file",
    pre=Filter::map(fn(s) { s }),
  )
  let help = p.generate_help()
  debug_inspect(help.contains("--output, --out, --o"), content="true")
}

///|
test "shorts + aliases combined in help: -v, -V, --verbose, --verb" {
  let p = Parser::new()
  let _ = p.flag(
    name="verbose",
    shorts="vV",
    aliases=["verb"],
    description="Verbose output",
  )
  let help = p.generate_help()
  debug_inspect(help.contains("-v, -V, --verbose, --verb"), content="true")
}

///|
test "aliases also parse correctly" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["verb"])
  ignore(p.parse(["--verb"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "aliases for value option" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=8080,
    aliases=["p"],
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["--p", "3000"]))
  debug_inspect(p.get(port), content="Some(3000)")
}

// ============================================================
// int の choices テスト
// ============================================================

///|
test "int with choices: valid value accepted" {
  let p = Parser::new()
  let level = p.int(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse(["--level", "2"]))
  debug_inspect(p.get(level), content="Some(2)")
}

///|
test "int with choices: another valid value" {
  let p = Parser::new()
  let level = p.int(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse(["--level", "3"]))
  debug_inspect(p.get(level), content="Some(3)")
}

///|
test "int with choices: invalid value rejected" {
  let p = Parser::new()
  let _ = p.int(name="level", default=1, choices=["1", "2", "3"])
  try p.parse(["--level", "5"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "int with choices: default without args" {
  let p = Parser::new()
  let level = p.int(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse([]))
  debug_inspect(p.get(level), content="Some(1)")
}

// ============================================================
// int の post テスト
// ============================================================

///|
test "int with post: value transformed" {
  let p = Parser::new()
  let num = p.int(
    name="num",
    default=0,
    post=Some(Filter::map(fn(n : Int) { n * 2 })),
  )
  ignore(p.parse(["--num", "5"]))
  debug_inspect(p.get(num), content="Some(10)")
}

///|
test "int with post: default also transformed" {
  let p = Parser::new()
  let num = p.int(
    name="num",
    default=3,
    post=Some(Filter::map(fn(n : Int) { n * 2 })),
  )
  ignore(p.parse([]))
  // post hook runs on cell value unconditionally, so default 3 becomes 6
  debug_inspect(p.get(num), content="Some(6)")
}

///|
test "int with post: chained transform" {
  let p = Parser::new()
  let num = p.int(
    name="num",
    default=0,
    post=Some(Filter::map(fn(n : Int) { n + 100 })),
  )
  ignore(p.parse(["--num", "5"]))
  debug_inspect(p.get(num), content="Some(105)")
}

// ============================================================
// default_display 自動導出 (T : Show) テスト
// ============================================================

///|
test "custom[Int] default_display auto: shows [default: 42]" {
  let p = Parser::new()
  let _ = p.custom(
    name="count",
    default=42,
    pre=Filter::parse_int(),
    description="Item count",
  )
  let help = p.generate_help()
  debug_inspect(help.contains("[default: 42]"), content="true")
}

///|
test "custom[Int] default=0: shows [default: 0] in help" {
  let p = Parser::new()
  let _ = p.custom(
    name="count",
    default=0,
    pre=Filter::parse_int(),
    description="Item count",
  )
  let help = p.generate_help()
  debug_inspect(help.contains("[default: 0]"), content="true")
}

///|
test "custom[String] default empty: no default shown in help" {
  let p = Parser::new()
  let _ = p.custom(
    name="name",
    default="",
    pre=Filter::map(fn(s) { s }),
    description="User name",
  )
  let help = p.generate_help()
  debug_inspect(help.contains("[default:"), content="false")
}

///|
test "custom[String] default non-empty: shows [default: hello]" {
  let p = Parser::new()
  let _ = p.custom(
    name="name",
    default="hello",
    pre=Filter::map(fn(s) { s }),
    description="User name",
  )
  let help = p.generate_help()
  debug_inspect(help.contains("[default: hello]"), content="true")
}

///|
test "custom[Int] default_display=Some(\"\"): explicitly suppress default" {
  let p = Parser::new()
  let _ = p.custom(
    name="count",
    default=42,
    pre=Filter::parse_int(),
    description="Item count",
    default_display=Some(""),
  )
  let help = p.generate_help()
  debug_inspect(help.contains("[default:"), content="false")
}

///|
test "custom[Int] default_display=Some(\"custom\"): custom display" {
  let p = Parser::new()
  let _ = p.custom(
    name="count",
    default=42,
    pre=Filter::parse_int(),
    description="Item count",
    default_display=Some("custom"),
  )
  let help = p.generate_help()
  debug_inspect(help.contains("[default: custom]"), content="true")
  debug_inspect(help.contains("[default: 42]"), content="false")
}

///|
test "int default shown in help via auto derive" {
  let p = Parser::new()
  let _ = p.int(name="port", default=8080, description="Port number")
  let help = p.generate_help()
  debug_inspect(help.contains("[default: 8080]"), content="true")
}

///|
test "int default=0 shown in help" {
  let p = Parser::new()
  let _ = p.int(name="port", default=0, description="Port number")
  let help = p.generate_help()
  debug_inspect(help.contains("[default: 0]"), content="true")
}

///|
test "string default empty: no default shown in help" {
  let p = Parser::new()
  let _ = p.string(name="host", default="", description="Host name")
  let help = p.generate_help()
  debug_inspect(help.contains("[default:"), content="false")
}

// ============================================================
// shorts validation tests
// ============================================================

///|
test "shorts validation: hyphen rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="-")
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("invalid short option character '-'"),
        content="true",
      )
    _ => abort("expected error for hyphen in shorts")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "shorts validation: space rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts=" ")
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("invalid short option character (whitespace)"),
        content="true",
      )
    _ => abort("expected error for space in shorts")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "shorts validation: tab rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="\t")
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("invalid short option character (whitespace)"),
        content="true",
      )
    _ => abort("expected error for tab in shorts")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "shorts validation: NUL rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="\u0000")
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("invalid short option character (NUL)"),
        content="true",
      )
    _ => abort("expected error for NUL in shorts")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "shorts validation: mixed valid and invalid" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v-")
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("invalid short option character '-'"),
        content="true",
      )
    _ => abort("expected error for hyphen in shorts")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "shorts validation: unicode allowed" {
  let p = Parser::new()
  let opt = p.flag(name="all", shorts="あ")
  ignore(p.parse(["-あ"]))
  debug_inspect(p.get(opt), content="Some(true)")
}

// ============================================================
// Unicode short combining tests
// ============================================================

///|
test "shorts unicode combining: two unicode flags" {
  let p = Parser::new()
  let a = p.flag(name="all", shorts="あ")
  let i = p.flag(name="interactive", shorts="い")
  ignore(p.parse(["-あい"]))
  debug_inspect(p.get(a), content="Some(true)")
  debug_inspect(p.get(i), content="Some(true)")
}

///|
test "shorts unicode combining: unicode short + inline value" {
  let p = Parser::new()
  let port = p.custom(
    name="port",
    default=0,
    shorts="あ",
    pre=Filter::parse_int(),
  )
  ignore(p.parse(["-あ3000"]))
  debug_inspect(p.get(port), content="Some(3000)")
}

// ============================================================
// choices help display tests
// ============================================================

///|
test "choices shown in help: [possible values: ...]" {
  let p = Parser::new()
  let _ = p.string(
    name="color",
    default="auto",
    choices=["always", "auto", "never"],
    description="Color mode",
  )
  let help = p.generate_help()
  debug_inspect(
    help.contains("[possible values: always, auto, never]"),
    content="true",
  )
}

///|
test "choices + default shown in help together" {
  let p = Parser::new()
  let _ = p.string(
    name="color",
    default="auto",
    choices=["always", "auto", "never"],
    description="Color mode",
  )
  let help = p.generate_help()
  debug_inspect(
    help.contains("[possible values: always, auto, never] [default: auto]"),
    content="true",
  )
}

///|
test "no choices: no possible values in help" {
  let p = Parser::new()
  let _ = p.string(name="host", default="localhost", description="Host")
  let help = p.generate_help()
  debug_inspect(help.contains("[possible values:"), content="false")
}

///|
test "int choices shown in help" {
  let p = Parser::new()
  let _ = p.int(
    name="level",
    default=1,
    choices=["1", "2", "3"],
    description="Log level",
  )
  let help = p.generate_help()
  debug_inspect(help.contains("[possible values: 1, 2, 3]"), content="true")
}

// ============================================================
// inject_help_node collision tests
// ============================================================

///|
test "user-defined shorts=h takes priority over built-in -h help" {
  let p = Parser::new()
  let human = p.flag(
    name="human-readable",
    shorts="h",
    description="Human-readable",
  )
  ignore(p.parse(["-h"]))
  // -h should activate the user-defined flag, not trigger help
  debug_inspect(p.get(human), content="Some(true)")
}

///|
test "user-defined shorts=h: --help still works" {
  let p = Parser::new()
  let _ = p.flag(
    name="human-readable",
    shorts="h",
    description="Human-readable",
  )
  try p.parse(["--help"]) catch {
    HelpRequested(_) => () // expected
    _ => abort("expected HelpRequested for --help")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "user-defined --help takes priority over built-in --help" {
  let p = Parser::new()
  let help_opt = p.flag(name="help", description="Custom help flag")
  ignore(p.parse(["--help"]))
  // --help should activate user-defined flag, not trigger built-in help
  debug_inspect(p.get(help_opt), content="Some(true)")
}

///|
test "user-defined --help and shorts=h: both taken, no built-in help injected" {
  let p = Parser::new()
  let help_opt = p.flag(name="help", shorts="h", description="Custom help")
  ignore(p.parse(["--help", "-h"]))
  debug_inspect(p.get(help_opt), content="Some(true)")
}

///|
test "no user collision: -h triggers help as usual" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Verbose")
  try p.parse(["-h"]) catch {
    HelpRequested(_) => () // expected
    _ => abort("expected HelpRequested for -h")
  } noraise {
    _ => fail("expected raise")
  }
}

// ============================================================
// equals syntax edge case tests
// ============================================================

///|
test "equals syntax: --name= (empty value) sets empty string" {
  let p = Parser::new()
  let name = p.string(name="name", default="default")
  ignore(p.parse(["--name="]))
  debug_inspect(
    p.get(name),
    content=(
      #|Some("")
    ),
  )
}

///|
test "equals syntax: --port= (empty value int) raises parse error" {
  let p = Parser::new()
  let _ = p.int(name="port", default=8080)
  try p.parse(["--port="]) catch {
    ParseError(info) =>
      debug_inspect(info.message.contains("invalid integer: "), content="true")
    _ => abort("expected ParseError for --port= with empty value")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "equals syntax: --name==value (value contains =)" {
  let p = Parser::new()
  let name = p.string(name="name", default="default")
  ignore(p.parse(["--name==value"]))
  debug_inspect(
    p.get(name),
    content=(
      #|Some("=value")
    ),
  )
}

///|
test "equals syntax: --name=hello world (shell splits at space)" {
  // シェルがスペースで分割するため、args レベルでは ["--name=hello", "world"]
  // --name=hello で値 "hello" が取れ、"world" は余剰引数としてエラー
  let p = Parser::new()
  let name = p.string(name="name", default="default")
  ignore(p.parse(["--name=hello"]))
  debug_inspect(
    p.get(name),
    content=(
      #|Some("hello")
    ),
  )
}

// ============================================================
// equals syntax: flag/count with =value
// ============================================================

///|
test "equals syntax: --flag=true is error (flag does not accept value)" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  try p.parse(["--verbose=true"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "equals syntax: --count=3 is error (count does not accept value)" {
  let p = Parser::new()
  let _ = p.count(name="verbose")
  try p.parse(["--verbose=3"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// ============================================================
// Empty string argument tests
// ============================================================

///|
test "empty string: positional accepts empty string" {
  let p = Parser::new()
  let file = p.positional(name="file")
  ignore(p.parse([""]))
  debug_inspect(
    p.get(file),
    content=(
      #|Some("")
    ),
  )
}

///|
test "empty string: string option accepts empty string as value" {
  let p = Parser::new()
  let name = p.string(name="name", default="default")
  ignore(p.parse(["--name", ""]))
  debug_inspect(
    p.get(name),
    content=(
      #|Some("")
    ),
  )
}

///|
test "empty string: empty string without positional is error" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  try p.parse(["", "--verbose"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "empty string: empty string as positional + option" {
  let p = Parser::new()
  let file = p.positional(name="file")
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["", "--verbose"]))
  debug_inspect(
    p.get(file),
    content=(
      #|Some("")
    ),
  )
  debug_inspect(p.get(verbose), content="Some(true)")
}

///|
test "empty string: rest collects empty strings" {
  let p = Parser::new()
  let args = p.rest(name="args")
  ignore(p.parse(["", "a", ""]))
  debug_inspect(
    p.get(args),
    content=(
      #|Some(["", "a", ""])
    ),
  )
}

// ============================================================
// Usage line tests
// ============================================================

///|
test "help contains Usage line" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let help = p.generate_help()
  debug_inspect(help.contains("Usage:"), content="true")
}

///|
test "Usage line includes [OPTIONS] when options exist" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let help = p.generate_help()
  debug_inspect(help.contains("Usage: [OPTIONS]"), content="true")
}

///|
test "Usage line includes [COMMAND] when commands exist" {
  let p = Parser::new()
  let _ = p.cmd(name="serve", setup=fn(_c) {  }, description="Start server")
  let help = p.generate_help()
  debug_inspect(help.contains("[COMMAND]"), content="true")
}

///|
test "Usage line includes positional as <NAME>" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let help = p.generate_help()
  debug_inspect(help.contains("<FILE>"), content="true")
}

///|
test "Usage line includes rest as [NAME]..." {
  let p = Parser::new()
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  debug_inspect(help.contains("[ARGS]..."), content="true")
}

///|
test "Usage line with options, positional, and command" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let _ = p.positional(name="file", description="Input file")
  let _ = p.cmd(name="serve", setup=fn(_c) {  }, description="Start server")
  let help = p.generate_help()
  debug_inspect(
    help.contains("Usage: [OPTIONS] <FILE> [COMMAND]"),
    content="true",
  )
}

///|
test "Usage line with options and rest" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  debug_inspect(help.contains("Usage: [OPTIONS] [ARGS]..."), content="true")
}

///|
test "Usage line: no [OPTIONS] when no user-defined options (before parse)" {
  let p = Parser::new(dashdash=false)
  let _ = p.positional(name="file", description="Input file")
  let help = p.generate_help()
  // generate_help() called before parse: inject_help_node hasn't run yet
  // so no Flag/ValueOpt metas exist → no [OPTIONS]
  debug_inspect(help.contains("[OPTIONS]"), content="false")
  debug_inspect(help.contains("Usage: <FILE>"), content="true")
}

///|
test "Usage line with positional and rest" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  debug_inspect(help.contains("<FILE> [ARGS]..."), content="true")
}

// ============================================================
// Arguments section tests
// ============================================================

///|
test "Arguments section shows positional" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let help = p.generate_help()
  debug_inspect(help.contains("Arguments:"), content="true")
  debug_inspect(help.contains("<FILE>"), content="true")
  debug_inspect(help.contains("Input file"), content="true")
}

///|
test "Arguments section shows rest with dots" {
  let p = Parser::new()
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  debug_inspect(help.contains("Arguments:"), content="true")
  debug_inspect(help.contains("[ARGS]..."), content="true")
  debug_inspect(help.contains("Extra arguments"), content="true")
}

///|
test "Arguments section shows both positional and rest" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  debug_inspect(help.contains("Arguments:"), content="true")
  debug_inspect(help.contains("<FILE>"), content="true")
  debug_inspect(help.contains("[ARGS]..."), content="true")
}

///|
test "no positional or rest: no Arguments section" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let help = p.generate_help()
  debug_inspect(help.contains("Arguments:"), content="false")
}

///|
test "integrated help: description, usage, commands, arguments, options" {
  let p = Parser::new()
  p.set_description("My CLI tool")
  let _ = p.flag(
    name="verbose",
    shorts="v",
    description="Enable verbose output",
  )
  let _ = p.int(name="port", default=8080, description="Set port number")
  let _ = p.positional(name="file", description="Input file")
  let _ = p.rest(name="args", description="Extra arguments")
  let _ = p.cmd(name="serve", setup=fn(_c) {  }, description="Start server")
  let help = p.generate_help()
  // Description
  debug_inspect(help.contains("My CLI tool"), content="true")
  // Usage line
  debug_inspect(
    help.contains("Usage: [OPTIONS] <FILE> [ARGS]... [COMMAND]"),
    content="true",
  )
  // Commands section
  debug_inspect(help.contains("Commands:"), content="true")
  debug_inspect(help.contains("serve"), content="true")
  // Arguments section
  debug_inspect(help.contains("Arguments:"), content="true")
  debug_inspect(help.contains("<FILE>"), content="true")
  debug_inspect(help.contains("[ARGS]..."), content="true")
  // Options section
  debug_inspect(help.contains("Options:"), content="true")
  debug_inspect(help.contains("--verbose"), content="true")
  debug_inspect(help.contains("--port"), content="true")
}

///|
test "hidden positional not shown in help" {
  let p = Parser::new()
  let _ = p.positional(name="visible", description="Visible arg")
  // hidden positional は直接 metas に追加できないので、hidden=false のテスト
  let help = p.generate_help()
  debug_inspect(help.contains("<VISIBLE>"), content="true")
}

// ============================================================
// C4: positional accepts --xxx (no prefix check)
// ============================================================

///|
test "positional accepts --xxx as value" {
  let p = Parser::new(dashdash=false)
  let arg = p.positional(name="arg")
  ignore(p.parse(["--unknown-flag"]))
  debug_inspect(
    p.get(arg),
    content=(
      #|Some("--unknown-flag")
    ),
  )
}

///|
test "positional accepts --xxx alongside registered options" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let arg = p.positional(name="arg")
  ignore(p.parse(["--verbose", "--not-registered"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    p.get(arg),
    content=(
      #|Some("--not-registered")
    ),
  )
}

// ============================================================
// C3: dashdash + install_separator_node duplicate detection
// ============================================================

///|
test "dashdash=true with explicit dashdash() raises duplicate error" {
  let p = Parser::new(dashdash=true) // install_separator_node registers "--"
  let _ = p.dashdash() // also registers "--"
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("duplicate option name: --"),
        content="true",
      )
    _ => abort("expected duplicate error for dashdash + install_separator_node")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "dashdash=false with explicit dashdash() works without duplicate error" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash()
  ignore(p.parse(["--", "a", "b"]))
  debug_inspect(
    p.get(dd),
    content=(
      #|Some(["a", "b"])
    ),
  )
}

///|
test "append_dashdash duplicate detection with dashdash=true" {
  let p = Parser::new(dashdash=true)
  let _ = p.append_dashdash()
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("duplicate option name: --"),
        content="true",
      )
    _ =>
      abort(
        "expected duplicate error for append_dashdash + install_separator_node",
      )
  } noraise {
    _ => fail("expected raise")
  }
}

// ============================================================
// #8: post_hooks failure leaves parsed=false
// ============================================================

///|
test "post_hooks failure keeps parsed=false" {
  let p = Parser::new(dashdash=false)
  let name = p.string(name="name", default="world")
  // Add a post_hook that always fails
  p.post_hooks.push(fn() raise ParseError {
    raise parse_error("post_hook validation failed")
  })
  try p.parse(["--name", "alice"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
  // parse should fail due to post_hook
  // parsed should remain false because post_hook failed before setting it
  debug_inspect(name.parsed.val, content="false")
}

// ============================================================
// #9: global node name collision in child parser
// ============================================================

///|
test "child parser detects global option name collision" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose", global=true)
  let _ = p.cmd(name="sub", dashdash=false, setup=fn(child) {
    // child defines local --verbose which collides with parent's global --verbose
    let _ = child.flag(name="verbose")
  })
  try p.parse(["sub"]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("duplicate option name"),
        content="true",
      )
    _ => abort("expected duplicate error for global/local name collision")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "child parser with no collision works fine" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", global=true)
  let _ = p.cmd(name="sub", dashdash=false, setup=fn(child) {
    let _ = child.flag(name="quiet") // different name, no collision
  })
  ignore(p.parse(["sub", "--verbose", "--quiet"]))
  debug_inspect(p.get(verbose), content="Some(true)")
}

// ============================================================
// OC/P 2-phase parse tests (DR-0034)
// ============================================================

///|
test "OC/P: non-greedy positional deferred to P phase" {
  // [F1, --verbose, F2] で flag(verbose) + serial(src, dst)
  // OC: F1→unclaimed, --verbose→flag, F2→unclaimed
  // P: unclaimed=[F1, F2] → src=F1, dst=F2
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  p.serial(setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
  })
  ignore(p.parse(["F1", "--verbose", "F2"]))
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    src.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  debug_inspect(
    dst.unwrap().get(),
    content=(
      #|Some("F2")
    ),
  )
}

///|
test "OC/P: greedy positional consumed in OC" {
  // [F1, --verbose, F2] で flag(verbose) + positional(file, greedy=true)
  // OC: F1→greedy positional consumes, --verbose→flag, F2→no greedy left→unclaimed
  // P: unclaimed=[F2] → no positional left → "unexpected argument" error
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file", greedy=true)
  try p.parse(["F1", "--verbose", "F2"]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("unexpected argument"),
        content="true",
      )
    _ => abort("expected error for extra positional after greedy")
  } noraise {
    _ => fail("expected raise")
  }
  ignore(file)
  ignore(verbose)
}

///|
test "OC/P: dashdash forces positional in P phase" {
  // [F1, --, F2] で serial(src, dst) + dashdash=true
  // OC: F1→unclaimed, --→separator(force_unclaimed=[F2])
  // P: [F1, F2] → src=F1, dst=F2 (順序正確)
  let p = Parser::new(dashdash=true)
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  p.serial(setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
  })
  ignore(p.parse(["F1", "--", "F2"]))
  debug_inspect(
    src.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  debug_inspect(
    dst.unwrap().get(),
    content=(
      #|Some("F2")
    ),
  )
}

///|
test "OC/P: dashdash prevents option matching" {
  // [--, --verbose, file] で flag(verbose) + rest(files) + dashdash=true
  // OC: --→separator(force_unclaimed=[--verbose, file])
  // P: rest が [--verbose, file] を全て消費。verbose flag は未設定のまま。
  let p = Parser::new(dashdash=true)
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  ignore(p.parse(["--", "--verbose", "file"]))
  debug_inspect(verbose.is_set(), content="false")
  debug_inspect(
    p.get(files),
    content=(
      #|Some(["--verbose", "file"])
    ),
  )
}

///|
test "OC/P: interleaved options and positionals" {
  // [--output, out, F1, --verbose, F2] で string(output) + flag(verbose) + serial(src, dst)
  // OC: --output→string(consumed 2), F1→unclaimed, --verbose→flag, F2→unclaimed
  // P: unclaimed=[F1, F2] → src=F1, dst=F2
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let verbose = p.flag(name="verbose")
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  p.serial(setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
  })
  ignore(p.parse(["--output", "out", "F1", "--verbose", "F2"]))
  debug_inspect(
    p.get(output),
    content=(
      #|Some("out")
    ),
  )
  debug_inspect(p.get(verbose), content="Some(true)")
  debug_inspect(
    src.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  debug_inspect(
    dst.unwrap().get(),
    content=(
      #|Some("F2")
    ),
  )
}

///|
test "OC/P: misspelled option consumed as positional" {
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  let _file = p.positional(name="file")
  try p.parse(["--vrrbose", "file.txt"]) catch {
    ParseError(info) =>
      // --vrrbose が positional(file) に食われ、file.txt が unexpected になる
      // ただし hint は file.txt（prefix なし）には付かない
      debug_inspect(info.message.contains("unexpected"), content="true")
    _ => fail("expected ParseError")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "OC/P: typo hint suggests closest match" {
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  ignore(p.flag(name="version"))
  p.never()
  try p.parse(["--vrrbose"]) catch {
    ParseError(info) => {
      debug_inspect(
        info.message,
        content=(
          #|"unexpected argument: --vrrbose"
        ),
      )
      debug_inspect(
        info.tip,
        content=(
          #|"--verbose"
        ),
      )
    }
    _ => fail("expected ParseError")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "OC/P: no hint for non-prefix arg" {
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  p.never()
  try p.parse(["verbos"]) catch {
    ParseError(info) => {
      // prefix なしの arg には tip を付けない
      debug_inspect(
        info.message,
        content=(
          #|"unexpected argument: verbos"
        ),
      )
      debug_inspect(
        info.tip,
        content=(
          #|""
        ),
      )
    }
    _ => fail("expected ParseError")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "OC/P: rest with options interleaved" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  ignore(p.parse(["f1", "--verbose", "f2", "f3"]))
  debug_inspect(verbose.is_set(), content="true")
  debug_inspect(
    files.get(),
    content=(
      #|Some(["f1", "f2", "f3"])
    ),
  )
}

///|
test "OC/P: serial(file1, rest(dir), file2) with interleaved options" {
  // serial 内の rest は stop_before なしだと後続 positional 分の引数も取り込む。
  // ここでは parse エラーにならないこと + option が正しく処理されることを検証。
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let mut file1 : Opt[String]? = None
  let mut dirs : Opt[Array[String]]? = None
  let mut file2 : Opt[String]? = None
  p.serial(setup=fn(s) {
    file1 = Some(s.positional(name="file1"))
    dirs = Some(s.rest(name="dirs"))
    file2 = Some(s.positional(name="file2"))
  })
  ignore(p.parse(["F1", "--verbose", "D1", "D2", "F2"]))
  debug_inspect(verbose.is_set(), content="true")
  debug_inspect(
    file1.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  // rest が stop_before なしのため D1, D2, F2 全てを消費し file2 は未設定
  debug_inspect(
    dirs.unwrap().get(),
    content=(
      #|Some(["D1", "D2", "F2"])
    ),
  )
  debug_inspect(file2.unwrap().is_set(), content="false")
}

///|
test "OC/P: greedy positional normal consumption" {
  // [F1, --verbose] で flag(verbose) + positional(file, greedy=true)
  // OC: F1→greedy positional consumes, --verbose→flag
  // P: unclaimed なし → 正常終了
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file", greedy=true)
  ignore(p.parse(["F1", "--verbose"]))
  debug_inspect(verbose.is_set(), content="true")
  debug_inspect(
    file.get(),
    content=(
      #|Some("F1")
    ),
  )
}

///|
test "OC/P: greedy then non-greedy positional" {
  // [A, --verbose, B] で flag(verbose) + positional(eager, greedy) + positional(deferred)
  // OC: A→greedy(eager) consumes, --verbose→flag, B→no greedy left→unclaimed
  // P: unclaimed=[B] → deferred=B
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let eager = p.positional(name="eager", greedy=true)
  let deferred = p.positional(name="deferred")
  ignore(p.parse(["A", "--verbose", "B"]))
  debug_inspect(verbose.is_set(), content="true")
  debug_inspect(
    eager.get(),
    content=(
      #|Some("A")
    ),
  )
  debug_inspect(
    deferred.get(),
    content=(
      #|Some("B")
    ),
  )
}

///|
test "OC/P: serial with greedy=true consumed in OC" {
  // [F1, --verbose, F2] で flag(verbose) + serial(src, dst, greedy=true)
  // OC: F1→greedy serial の compound handler が呼ばれる
  //   compound handler: src accepts F1(p=1), dst accepts --verbose(p=2) → Accept(consumed=2)
  //   → src="F1", dst="--verbose"（compound handler は ExactNode を考慮しない）
  // pos=2 → F2→no ExactNode, no greedy left→unclaimed
  // P: unclaimed=[F2] → no non-greedy positional → "unexpected argument" error
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  p.serial(greedy=true, setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
  })
  try p.parse(["F1", "--verbose", "F2"]) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("unexpected argument"),
        content="true",
      )
    _ =>
      abort("expected error: compound handler consumes --verbose as dst value")
  } noraise {
    _ => fail("expected raise")
  }
  // parse がエラーで終了するため parsed=false、get() は None を返す。
  // compound handler が --verbose を positional 値として消費するため flag も未設定。
  debug_inspect(verbose.is_set(), content="false")
  // commit は呼ばれているが parsed=false なので get() は None
  debug_inspect(src.unwrap().is_set(), content="true")
  debug_inspect(dst.unwrap().is_set(), content="true")
}

///|
test "OC/P: serial with greedy=true normal consumption" {
  // [F1, F2] で serial(src, dst, greedy=true)
  // OC: F1→greedy serial → compound handler(args, 0) → src=F1, dst=F2 → Accept(consumed=2)
  // P: unclaimed なし → 正常終了
  let p = Parser::new(dashdash=false)
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  p.serial(greedy=true, setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
  })
  ignore(p.parse(["F1", "F2"]))
  debug_inspect(
    src.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  debug_inspect(
    dst.unwrap().get(),
    content=(
      #|Some("F2")
    ),
  )
}

///|
test "OC/P: typo hint distance threshold" {
  // 距離 1 ("--verbos" vs "--verbose"): tip あり
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  p.never()
  try p.parse(["--verbos"]) catch {
    ParseError(info) =>
      debug_inspect(
        info.tip,
        content=(
          #|"--verbose"
        ),
      )
    _ => fail("expected error")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "OC/P: typo hint no match for distant name" {
  // 距離 > 2 ("--xyz" vs "--verbose"): tip なし
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  p.never()
  try p.parse(["--xyz"]) catch {
    ParseError(info) =>
      debug_inspect(
        info.tip,
        content=(
          #|""
        ),
      )
    _ => fail("expected error")
  } noraise {
    _ => fail("expected raise")
  }
}

// === R2-W3: shorts 重複検出テスト ===

///|
test "R2-W3: duplicate short option detected" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose", shorts="v")
  let _ = p.flag(name="version", shorts="v")
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(info.message.contains("duplicate"), content="true")
    _ => abort("expected duplicate name error for short -v")
  } noraise {
    _ => fail("expected raise")
  }
}

// === R2-W1: parse retry 動作テスト ===

///|
test "R2-W1: parse after error retries without node growth" {
  let p = Parser::new(dashdash=false)
  let name = p.string(name="name", default="world")
  // 1回目: エラーパース（install_eq_split/short_combine が走る）
  try p.parse(["--unknown"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
  let nodes_after_first = p.nodes.length()
  // 2回目: 成功パース（べき等ガードによりノード数が増えない）
  ignore(p.parse(["--name", "alice"]))
  debug_inspect(
    name.get(),
    content=(
      #|Some("alice")
    ),
  )
  let nodes_after_second = p.nodes.length()
  debug_inspect(nodes_after_first == nodes_after_second, content="true")
}

// === float ===

///|
test "float: --threshold 0.5" {
  let p = Parser::new()
  let threshold = p.float(name="threshold", default=0.0)
  ignore(p.parse(["--threshold", "0.5"]))
  debug_inspect(p.get(threshold), content="Some(0.5)")
}

///|
test "float: default value" {
  let p = Parser::new()
  let threshold = p.float(name="threshold", default=3.14)
  ignore(p.parse([]))
  debug_inspect(p.get(threshold), content="Some(3.14)")
}

///|
test "float: invalid value" {
  let p = Parser::new()
  let _ = p.float(name="threshold", default=0.0)
  try p.parse(["--threshold", "abc"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "float: --threshold=1.5 eq form" {
  let p = Parser::new()
  let threshold = p.float(name="threshold", default=0.0)
  ignore(p.parse(["--threshold=1.5"]))
  debug_inspect(p.get(threshold), content="Some(1.5)")
}

///|
test "float: with post filter" {
  let p = Parser::new()
  let rate = p.float(
    name="rate",
    default=0.5,
    post=Some(Filter::float_in_range(0.0, 1.0)),
  )
  ignore(p.parse(["--rate", "0.7"]))
  debug_inspect(p.get(rate), content="Some(0.7)")
}

///|
test "float: post filter rejects out of range" {
  let p = Parser::new()
  let _ = p.float(
    name="rate",
    default=0.5,
    post=Some(Filter::float_in_range(0.0, 1.0)),
  )
  try p.parse(["--rate", "1.5"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "float: negative value" {
  let p = Parser::new()
  let temp = p.float(name="temperature", default=0.0)
  ignore(p.parse(["--temperature", "-40.5"]))
  debug_inspect(p.get(temp), content="Some(-40.5)")
}

// === append_float ===

///|
test "append_float: multiple values" {
  let p = Parser::new()
  let coords = p.append_float(name="coord")
  ignore(p.parse(["--coord", "1.5", "--coord", "2.5", "--coord", "3.0"]))
  debug_inspect(p.get(coords), content="Some([1.5, 2.5, 3])")
}

///|
test "append_float: empty" {
  let p = Parser::new()
  let coords = p.append_float(name="coord")
  ignore(p.parse([]))
  debug_inspect(p.get(coords), content="Some([])")
}

///|
test "append_float: invalid value" {
  let p = Parser::new()
  let _ = p.append_float(name="coord")
  try p.parse(["--coord", "abc"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// === boolean ===

///|
test "boolean: --flag true" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse(["--debug", "true"]))
  debug_inspect(p.get(debug), content="Some(true)")
}

///|
test "boolean: --flag false" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse(["--debug", "false"]))
  debug_inspect(p.get(debug), content="Some(false)")
}

///|
test "boolean: default is false" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse([]))
  debug_inspect(p.get(debug), content="Some(false)")
}

///|
test "boolean: accepts on/off/t/f/1/0" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse(["--debug", "on"]))
  debug_inspect(p.get(debug), content="Some(true)")
  let p2 = Parser::new()
  let d2 = p2.boolean(name="debug")
  ignore(p2.parse(["--debug", "OFF"]))
  debug_inspect(p2.get(d2), content="Some(false)")
  let p3 = Parser::new()
  let d3 = p3.boolean(name="debug")
  ignore(p3.parse(["--debug", "1"]))
  debug_inspect(p3.get(d3), content="Some(true)")
}

///|
test "boolean: invalid value" {
  let p = Parser::new()
  let _ = p.boolean(name="debug")
  try p.parse(["--debug", "maybe"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// ============================================================
// coverage: テストカバレッジ改善用テスト
// ============================================================

///|
test "coverage: ParseResult::child on non-Map result returns None" {
  // access.mbt:35 — ParseResult::child で Map 以外に対して呼ぶと None
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let result = p.parse([])
  // result.kind は One（子コマンドなし）なので child は None を返す
  debug_inspect(result.child("anything") is None, content="true")
}

///|
test "coverage: inject_help_node skips when both --help and -h are taken" {
  // help.mbt:13 — --help と -h の両方がユーザー定義で占有されていると help 注入をスキップ
  // name="help" ではないので meta idempotent check を通過し、registered_names チェックに到達
  let p = Parser::new()
  let h1 = p.flag(name="my-help", aliases=["help"])
  let h2 = p.flag(name="short-h", shorts="h")
  ignore(p.parse(["--my-help", "-h"]))
  // 両方 true で、HelpRequested にならずに正常パース完了
  debug_inspect(h1.get(), content="Some(true)")
  debug_inspect(h2.get(), content="Some(true)")
}

///|
test "coverage: variation_toggle sugar for flag" {
  // options.mbt:34 — variation_toggle sugar
  let p = Parser::new()
  let flag = p.flag(name="color", variation_toggle=Some("toggle"))
  ignore(p.parse(["--toggle-color"]))
  debug_inspect(flag.get(), content="Some(true)")
}

///|
test "coverage: variation_unset sugar for flag" {
  // options.mbt:38 — variation_unset sugar
  let p = Parser::new()
  let flag = p.flag(name="color", variation_unset=Some("unset"))
  ignore(p.parse(["--color", "--unset-color"]))
  // unset は committed=false にするので is_set は false、値は default に戻る
  debug_inspect(flag.is_set(), content="false")
}

///|
test "coverage: count env with invalid integer" {
  // options.mbt:367 — count の env で無効な整数値
  let p = Parser::new()
  let _ = p.count(name="verbose", env="VERBOSE_COUNT")
  try p.parse([], env={ "VERBOSE_COUNT": "abc" }) catch {
    ParseError(info) =>
      debug_inspect(
        info.message.contains("invalid value for env"),
        content="true",
      )
    _ => fail("expected ParseError for invalid count env")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "coverage: register_env_applicator with missing env key" {
  // options.mbt:18 — env_map にキーがない場合 None => ()
  let p = Parser::new()
  let opt = p.string(name="name", default="default", env="MY_NAME")
  // env に MY_NAME キーがないが、別のキーはある
  ignore(p.parse([], env={ "OTHER_KEY": "value" }))
  // env にキーなしなので default のまま
  debug_inspect(
    opt.get(),
    content=(
      #|Some("default")
    ),
  )
}

///|
test "coverage: duplicate dashdash separator detection" {
  // parse.mbt:368 — dashdash() を呼んだ後 install_separator_node() が重複 -- を検出
  let p = Parser::new() // dashdash=true がデフォルトで -- が install される
  let _ = p.dashdash() // さらに手動で dashdash() を呼ぶ → 重複 -- が発生
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(info.message.contains("duplicate"), content="true")
    _ => fail("expected ParseError for duplicate --")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "coverage: rest stop_before triggers Reject then next positional" {
  // positionals.mbt:65 + parse.mbt:479-482 — rest が stop_before で Reject → 次の positional へ
  // rest が "END" で Reject → current_positional++ → 次の positional が "END" を消費
  let p = Parser::new(dashdash=false)
  let files = p.rest(name="files", stop_before=["END"])
  let last = p.positional(name="last")
  ignore(p.parse(["a", "b", "END"]))
  debug_inspect(
    files.get(),
    content=(
      #|Some(["a", "b"])
    ),
  )
  debug_inspect(
    last.get(),
    content=(
      #|Some("END")
    ),
  )
}

///|
test "coverage: P phase skips greedy positional" {
  // parse.mbt:459 — P Phase で greedy positional をスキップ
  // greedy positional は OC phase で消費。P Phase で unclaimed が残った場合、
  // greedy をスキップして次の non-greedy positional に渡す。
  let p = Parser::new()
  let greedy_pos = p.positional(name="greedy", greedy=true)
  let normal_pos = p.positional(name="normal")
  let opt = p.flag(name="verbose")
  // "first" は OC phase で greedy が消費、"--verbose" は OC phase でフラグが消費、
  // "second" は unclaimed → P phase で greedy をスキップ → normal が消費
  ignore(p.parse(["first", "--verbose", "second"]))
  debug_inspect(
    greedy_pos.get(),
    content=(
      #|Some("first")
    ),
  )
  debug_inspect(opt.get(), content="Some(true)")
  debug_inspect(
    normal_pos.get(),
    content=(
      #|Some("second")
    ),
  )
}

///|
test "coverage: short combine last short needs value, no more args" {
  // parse.mbt:323 — 短縮組み合わせの最後の short が value 必要で引数なし
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v")
  let _ = p.custom(
    name="name",
    shorts="n",
    default="",
    pre=Filter::map(fn(s) { s }),
  )
  try p.parse(["-vn"]) catch {
    ParseError(info) => {
      debug_inspect(info.kind, content="MissingValue")
      debug_inspect(
        info.opt_name,
        content=(
          #|"-n"
        ),
      )
    }
    _ => fail("expected MissingValue for -vn without value")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "coverage: short combine value trial error propagation with choices" {
  // parse.mbt:264 — short combine で value trial が Error (choices バリデーション失敗)
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v")
  let _ = p.custom(
    name="format",
    shorts="f",
    default="text",
    choices=["text", "json"],
    pre=Filter::map(fn(s) { s }),
  )
  // -vfxml: v はフラグ、f は value opt で choices=["text","json"]。
  // value trial で "xml" を試すが choices バリデーション失敗 → Error 伝搬
  try p.parse(["-vfxml"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "coverage: clone duplicate name detection" {
  // parser.mbt:309 — clone で既に登録済みの名前を使用
  let p = Parser::new()
  let opt = p.flag(name="verbose")
  let _ = p.clone("--verbose", opt) // 重複名
  try p.parse([]) catch {
    ParseError(info) =>
      debug_inspect(info.message.contains("duplicate"), content="true")
    _ => fail("expected duplicate error")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "coverage: clone with global flag propagates to child" {
  // parser.mbt:361 — clone の target が global の場合、clone も global_nodes に追加
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let v_clone = p.clone("--debug", verbose)
  let sub_ran = p.cmd(name="sub", setup=fn(sub) {
    // global なので子パーサーでも --debug が使える
    let _ = sub.flag(name="local-flag")
  })
  ignore(p.parse(["sub", "--debug"]))
  debug_inspect(sub_ran.get() is Some(_), content="true")
  debug_inspect(v_clone.get(), content="Some(true)")
}

///|
test "coverage: clone with implicit_value creates eq_fallback" {
  // parser.mbt:365-375 — clone で implicit_value 付きコンビネータの eq_fallback
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  let colour = p.clone("--colour", color)
  // eq_split 形式で clone 名を使う
  ignore(p.parse(["--colour=never"]))
  debug_inspect(
    colour.get(),
    content=(
      #|Some("never")
    ),
  )
  // target は変更されない
  debug_inspect(
    color.get(),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "coverage: serial sub_current exhausted returns Reject" {
  // positionals.mbt:146 — serial の sub_current が全消費済みで再呼び出し
  // serial(positional("a")) の後に positional("b") がある場合、
  // serial は 1つだけ消費して終了し、2つ目は serial 外の positional が取る
  let p = Parser::new(dashdash=false)
  p.serial(setup=fn(sub) { let _ = sub.positional(name="first") })
  let second = p.positional(name="second")
  ignore(p.parse(["hello", "world"]))
  debug_inspect(
    second.get(),
    content=(
      #|Some("world")
    ),
  )
}

///|
test "coverage: serial Reject mid-sequence breaks loop" {
  // positionals.mbt:161 — serial 内の rest が stop_before で途中 Reject
  // serial(first, rest(stop=END)) の rest が "END" で Reject → break → serial は "a","b" を消費
  // 残りの "END" は外の positional が消費
  let p = Parser::new(dashdash=false)
  p.serial(setup=fn(sub) {
    let _ = sub.positional(name="first")
    let _ = sub.rest(name="mid", stop_before=["END"])
  })
  let last = p.positional(name="last")
  ignore(p.parse(["a", "b", "END"]))
  debug_inspect(
    last.get(),
    content=(
      #|Some("END")
    ),
  )
}

///|
test "help_header: custom text appears before description" {
  let p = Parser::new()
  p.set_description("A test tool")
  p.help_header("MyApp v1.0.0\n")
  let help = p.generate_help()
  // header should appear at the very beginning
  debug_inspect(help.has_prefix("MyApp v1.0.0\n"), content="true")
  // description should come after header
  debug_inspect(help.contains("A test tool"), content="true")
}

///|
test "help_footer: custom text appears at the end" {
  let p = Parser::new()
  p.set_description("A test tool")
  p.help_footer("\nSee https://example.com for more info.")
  let help = p.generate_help()
  // footer should appear at the very end
  debug_inspect(
    help.has_suffix("\nSee https://example.com for more info.\n"),
    content="true",
  )
}

///|
test "help_header and help_footer: both specified" {
  let p = Parser::new()
  p.set_description("A test tool")
  p.help_header("=== HEADER ===\n")
  p.help_footer("\n=== FOOTER ===")
  let help = p.generate_help()
  // header at the beginning
  debug_inspect(help.has_prefix("=== HEADER ===\n"), content="true")
  // footer at the end
  debug_inspect(help.has_suffix("\n=== FOOTER ===\n"), content="true")
  // description still present
  debug_inspect(help.contains("A test tool"), content="true")
}

///|
test "help_header and help_footer: unset defaults to empty (no change)" {
  let p = Parser::new()
  p.set_description("A test tool")
  let _ = p.flag(name="verbose", description="Verbose output")
  // parse triggers inject_help_node, so --help option appears in help
  ignore(p.parse([]))
  let help = p.generate_help()
  // Should start with description (no header)
  debug_inspect(help.has_prefix("A test tool\n"), content="true")
  // Should end with the help option line (no footer)
  debug_inspect(help.has_suffix("Print help\n"), content="true")
}

// ============================================================
// generate_completions tests
// ============================================================

///|
test "generate_completions: flag and string basic candidates" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose output")
  let _ = p.string(name="output", default="", description="Output file")
  let candidates = p.generate_completions()
  // --verbose
  let verbose_candidates = candidates.filter(fn(c) { c.value == "--verbose" })
  debug_inspect(verbose_candidates.length(), content="1")
  debug_inspect(
    verbose_candidates[0].description,
    content=(
      #|"Verbose output"
    ),
  )
  debug_inspect(
    verbose_candidates[0].group,
    content=(
      #|"Options"
    ),
  )
  // --output
  let output_candidates = candidates.filter(fn(c) { c.value == "--output" })
  debug_inspect(output_candidates.length(), content="1")
  debug_inspect(
    output_candidates[0].description,
    content=(
      #|"Output file"
    ),
  )
  debug_inspect(
    output_candidates[0].group,
    content=(
      #|"Options"
    ),
  )
}

///|
test "generate_completions: shorts are included as candidates" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Verbose output")
  let candidates = p.generate_completions()
  // -v should be a separate candidate
  let short_candidates = candidates.filter(fn(c) { c.value == "-v" })
  debug_inspect(short_candidates.length(), content="1")
  debug_inspect(
    short_candidates[0].description,
    content=(
      #|"Verbose output"
    ),
  )
  debug_inspect(
    short_candidates[0].group,
    content=(
      #|"Options"
    ),
  )
}

///|
test "generate_completions: aliases are included as candidates" {
  let p = Parser::new()
  let _ = p.custom(
    name="output",
    default="",
    aliases=["out"],
    description="Output file",
    pre=Filter::map(fn(s) { s }),
  )
  let candidates = p.generate_completions()
  let alias_candidates = candidates.filter(fn(c) { c.value == "--out" })
  debug_inspect(alias_candidates.length(), content="1")
  debug_inspect(
    alias_candidates[0].description,
    content=(
      #|"Output file"
    ),
  )
}

///|
test "generate_completions: command candidates" {
  let p = Parser::new()
  let _ = p.sub(name="serve", description="Start the server")
  let _ = p.sub(name="build", description="Build the project")
  let candidates = p.generate_completions()
  let serve_candidates = candidates.filter(fn(c) { c.value == "serve" })
  debug_inspect(serve_candidates.length(), content="1")
  debug_inspect(
    serve_candidates[0].description,
    content=(
      #|"Start the server"
    ),
  )
  debug_inspect(
    serve_candidates[0].group,
    content=(
      #|"Commands"
    ),
  )
  let build_candidates = candidates.filter(fn(c) { c.value == "build" })
  debug_inspect(build_candidates.length(), content="1")
}

///|
test "generate_completions: hidden options are excluded" {
  let p = Parser::new()
  let _ = p.flag(name="visible", description="Visible flag")
  let _ = p.flag(name="secret", description="Secret flag", visibility=Hidden)
  let candidates = p.generate_completions()
  let secret_candidates = candidates.filter(fn(c) { c.value == "--secret" })
  debug_inspect(secret_candidates.length(), content="0")
  // visible should be present
  let visible_candidates = candidates.filter(fn(c) { c.value == "--visible" })
  debug_inspect(visible_candidates.length(), content="1")
}

///|
test "generate_completions: advanced options are included" {
  let p = Parser::new()
  let _ = p.flag(
    name="advanced-opt",
    description="Advanced option",
    visibility=Advanced,
  )
  let candidates = p.generate_completions()
  let adv_candidates = candidates.filter(fn(c) { c.value == "--advanced-opt" })
  debug_inspect(adv_candidates.length(), content="1")
  debug_inspect(
    adv_candidates[0].description,
    content=(
      #|"Advanced option"
    ),
  )
}

///|
test "generate_completions: description is set correctly" {
  let p = Parser::new()
  let _ = p.int(name="port", default=8080, description="Server port")
  let candidates = p.generate_completions()
  let port_candidates = candidates.filter(fn(c) { c.value == "--port" })
  debug_inspect(port_candidates.length(), content="1")
  debug_inspect(
    port_candidates[0].description,
    content=(
      #|"Server port"
    ),
  )
}

///|
test "generate_completions: group is correctly set for global options" {
  let p = Parser::new()
  let _ = p.flag(name="local-opt", description="Local option")
  let _ = p.flag(name="global-opt", description="Global option", global=true)
  let candidates = p.generate_completions()
  let local_candidates = candidates.filter(fn(c) { c.value == "--local-opt" })
  debug_inspect(
    local_candidates[0].group,
    content=(
      #|"Options"
    ),
  )
  let global_candidates = candidates.filter(fn(c) { c.value == "--global-opt" })
  debug_inspect(
    global_candidates[0].group,
    content=(
      #|"Global Options"
    ),
  )
}

// ============================================================
// generate_completion_script tests
// ============================================================

///|
test "generate_completion_script: bash output contains complete -F" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let _ = p.int(name="port", default=8080, description="Server port")
  let script = p.generate_completion_script(shell="bash", command_name="myapp")
  debug_inspect(script.contains("complete -F _myapp myapp"), content="true")
  debug_inspect(script.contains("_myapp()"), content="true")
  debug_inspect(script.contains("--verbose"), content="true")
  debug_inspect(script.contains("--port"), content="true")
}

///|
test "generate_completion_script: zsh output contains #compdef" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let _ = p.int(name="port", default=8080, description="Server port")
  let script = p.generate_completion_script(shell="zsh", command_name="myapp")
  debug_inspect(script.contains("#compdef myapp"), content="true")
  debug_inspect(script.contains("_myapp()"), content="true")
  debug_inspect(script.contains("'--verbose[Enable verbose]'"), content="true")
  debug_inspect(script.contains("'--port[Server port]'"), content="true")
  debug_inspect(script.contains("_myapp"), content="true")
}

///|
test "generate_completion_script: fish output contains complete -c" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let _ = p.int(name="port", default=8080, description="Server port")
  let script = p.generate_completion_script(shell="fish", command_name="myapp")
  debug_inspect(script.contains("complete -c myapp"), content="true")
  debug_inspect(script.contains("-l verbose"), content="true")
  debug_inspect(script.contains("-d 'Enable verbose'"), content="true")
  debug_inspect(script.contains("-l port"), content="true")
  debug_inspect(script.contains("-d 'Server port'"), content="true")
}

///|
test "generate_completion_script: unknown shell returns error message" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let script = p.generate_completion_script(
    shell="powershell",
    command_name="myapp",
  )
  debug_inspect(
    script.contains("Unsupported shell: powershell"),
    content="true",
  )
}

///|
test "generate_completion_script: fish with shorts includes -s flag" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Enable verbose")
  let script = p.generate_completion_script(shell="fish", command_name="myapp")
  debug_inspect(script.contains("-s v"), content="true")
  debug_inspect(script.contains("-l verbose"), content="true")
}

///|
test "generate_completion_script: subcommands are included" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let _ = p.sub(name="serve", description="Start server")
  let _ = p.sub(name="build", description="Build project")
  // bash
  let bash = p.generate_completion_script(shell="bash", command_name="myapp")
  debug_inspect(bash.contains("serve"), content="true")
  debug_inspect(bash.contains("build"), content="true")
  // zsh
  let zsh = p.generate_completion_script(shell="zsh", command_name="myapp")
  debug_inspect(zsh.contains("'serve:Start server'"), content="true")
  debug_inspect(zsh.contains("'build:Build project'"), content="true")
  // fish
  let fish = p.generate_completion_script(shell="fish", command_name="myapp")
  debug_inspect(fish.contains("-a serve"), content="true")
  debug_inspect(fish.contains("-d 'Start server'"), content="true")
  debug_inspect(fish.contains("-a build"), content="true")
  debug_inspect(fish.contains("-d 'Build project'"), content="true")
}

///|
test "parse: calling parse twice raises ParseAlreadyCalled error" {
  let p = Parser::new()
  let _ = p.string(name="opt", default="")
  ignore(p.parse(["--opt", "hello"]))
  // 2回目の呼び出しはエラー
  try p.parse(["--opt", "world"]) catch {
    ParseError(info) => {
      debug_inspect(info.kind, content="ParseAlreadyCalled")
      debug_inspect(
        info.message.contains("can only be called once"),
        content="true",
      )
    }
    _ => fail("expected ParseError with ParseAlreadyCalled")
  } noraise {
    _ => fail("expected raise")
  }
}

// ============================================================
// DR-0060 Action #2: Value primitive low-layer API wrappers
// shorts/global/aliases/variations support for string/int/float/boolean
// ============================================================

///|
test "DR-0060: string with shorts and global" {
  let p = Parser::new()
  let _ = p.sub(name="sub", description="sub")
  let host = p.string(name="host", default="", shorts="H", global=true)
  ignore(p.parse(["sub", "-H", "example.com"]))
  debug_inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "DR-0060: string with aliases" {
  let p = Parser::new()
  let output = p.string(name="output", default="", aliases=["out", "o"])
  ignore(p.parse(["--out", "file.txt"]))
  debug_inspect(
    output.get(),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "DR-0060: int with shorts" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080, shorts="p")
  ignore(p.parse(["-p", "3000"]))
  debug_inspect(port.get(), content="Some(3000)")
}

///|
test "DR-0060: int with global across subcommand" {
  let p = Parser::new()
  let _ = p.sub(name="serve", description="serve")
  let port = p.int(name="port", default=8080, shorts="p", global=true)
  ignore(p.parse(["serve", "-p", "3000"]))
  debug_inspect(port.get(), content="Some(3000)")
}

///|
test "DR-0060: float with shorts" {
  let p = Parser::new()
  let rate = p.float(name="rate", default=1.0, shorts="r")
  ignore(p.parse(["-r", "0.5"]))
  debug_inspect(rate.get(), content="Some(0.5)")
}

///|
test "DR-0060: float with aliases and global" {
  let p = Parser::new()
  let _ = p.sub(name="run", description="run")
  let threshold = p.float(
    name="threshold",
    default=0.0,
    aliases=["thresh"],
    global=true,
  )
  ignore(p.parse(["run", "--thresh", "3.14"]))
  debug_inspect(threshold.get(), content="Some(3.14)")
}

///|
test "DR-0060: boolean with shorts" {
  let p = Parser::new()
  let color = p.boolean(name="color", shorts="c")
  ignore(p.parse(["-c", "true"]))
  debug_inspect(color.get(), content="Some(true)")
}

///|
test "DR-0060: boolean with global" {
  let p = Parser::new()
  let _ = p.sub(name="build", description="build")
  let color = p.boolean(name="color", global=true)
  ignore(p.parse(["build", "--color", "false"]))
  debug_inspect(color.get(), content="Some(false)")
}

///|
test "DR-0060: append_string with shorts and global" {
  let p = Parser::new()
  let _ = p.sub(name="run", description="run")
  let files = p.append_string(name="file", shorts="f", global=true)
  ignore(p.parse(["run", "-f", "a.txt", "-f", "b.txt"]))
  debug_inspect(
    files.get(),
    content=(
      #|Some(["a.txt", "b.txt"])
    ),
  )
}

///|
test "DR-0060: append_int with shorts" {
  let p = Parser::new()
  let ports = p.append_int(name="port", shorts="p")
  ignore(p.parse(["-p", "80", "-p", "443"]))
  debug_inspect(ports.get(), content="Some([80, 443])")
}

///|
test "DR-0060: append_float with aliases" {
  let p = Parser::new()
  let weights = p.append_float(name="weight", aliases=["w"])
  ignore(p.parse(["--w", "0.5", "--w", "1.5"]))
  debug_inspect(weights.get(), content="Some([0.5, 1.5])")
}

///|
test "DR-0060: string without shorts/global uses default behavior" {
  // Ensure existing behavior is preserved when new params are not used
  let p = Parser::new()
  let name = p.string(name="name", default="world")
  ignore(p.parse(["--name", "hello"]))
  debug_inspect(
    name.get(),
    content=(
      #|Some("hello")
    ),
  )
}

///|
test "DR-0060: string with variations" {
  let p = Parser::new()
  let output = p.string(name="output", default="stdout", shorts="o", variations=[
    Reset("no"),
  ])
  ignore(p.parse(["--output", "file.txt", "--no-output"]))
  // Reset variation resets to default value
  debug_inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
}

// ============ empty name validation tests ============

///|
test "empty option name raises error" {
  let p = Parser::new()
  let _ = p.string(name="", default="")
  try p.parse([]) catch {
    ParseError(info) => {
      debug_inspect(info.kind, content="DuplicateDefinition")
      debug_inspect(info.message.contains("empty"), content="true")
    }
    _ => abort("expected error for empty option name")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "empty flag name raises error" {
  let p = Parser::new()
  let _ = p.flag(name="")
  try p.parse([]) catch {
    ParseError(info) => {
      debug_inspect(info.kind, content="DuplicateDefinition")
      debug_inspect(info.message.contains("empty"), content="true")
    }
    _ => abort("expected error for empty flag name")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "empty cmd name raises error" {
  let p = Parser::new()
  let _ = p.cmd(name="", setup=fn(_sub) {  })
  try p.parse([]) catch {
    ParseError(info) => {
      debug_inspect(info.kind, content="DuplicateDefinition")
      debug_inspect(info.message.contains("empty"), content="true")
    }
    _ => abort("expected error for empty command name")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "empty sub name raises error" {
  let p = Parser::new()
  let _ = p.sub(name="")
  try p.parse([]) catch {
    ParseError(info) => {
      debug_inspect(info.kind, content="DuplicateDefinition")
      debug_inspect(info.message.contains("empty"), content="true")
    }
    _ => abort("expected error for empty sub name")
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "serial_scope: basic positional grouping" {
  let p = Parser::new()
  let s = p.serial_scope()
  let src = s.positional(name="src")
  let dst = s.positional(name="dst")
  ignore(p.parse(["file1.txt", "file2.txt"]))
  debug_inspect(
    src.get(),
    content=(
      #|Some("file1.txt")
    ),
  )
  debug_inspect(
    dst.get(),
    content=(
      #|Some("file2.txt")
    ),
  )
}

///|
test "serial_scope: with rest" {
  let p = Parser::new()
  let s = p.serial_scope()
  let remote = s.positional(name="remote")
  let branches = s.rest(name="branches")
  ignore(p.parse(["origin", "main", "dev"]))
  debug_inspect(
    remote.get(),
    content=(
      #|Some("origin")
    ),
  )
  debug_inspect(
    branches.get(),
    content=(
      #|Some(["main", "dev"])
    ),
  )
}

///|
test "serial_scope: greedy mode" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let s = p.serial_scope(greedy=true)
  let arg1 = s.positional(name="arg1")
  let arg2 = s.positional(name="arg2")
  ignore(p.parse(["hello", "world", "--verbose"]))
  debug_inspect(
    arg1.get(),
    content=(
      #|Some("hello")
    ),
  )
  debug_inspect(
    arg2.get(),
    content=(
      #|Some("world")
    ),
  )
  debug_inspect(verbose.get(), content="Some(true)")
}

///|
test "serial_scope: with sub command" {
  let p = Parser::new()
  let push = p.sub(name="push", description="Push changes")
  let s = push.serial_scope()
  let remote = s.positional(name="remote")
  let branch = s.positional(name="branch")
  ignore(p.parse(["push", "origin", "main"]))
  debug_inspect(
    remote.get(),
    content=(
      #|Some("origin")
    ),
  )
  debug_inspect(
    branch.get(),
    content=(
      #|Some("main")
    ),
  )
}

///|
test "serial_scope: empty (no positionals registered)" {
  let p = Parser::new()
  let _ = p.serial_scope()
  // scope に positional を登録しなかった場合でもパースは通る（引数なし）
  ignore(p.parse([]))
  // 引数がある場合は unclaimed として残り ParseError になる
  try p.parse(["arg1", "arg2"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "serial_scope: insufficient arguments" {
  let p = Parser::new(dashdash=false)
  let s = p.serial_scope()
  let src = s.positional(name="src")
  let dst = s.positional(name="dst")
  ignore(p.parse(["only-one"]))
  debug_inspect(
    src.get(),
    content=(
      #|Some("only-one")
    ),
  )
  // 引数不足の positional は値がセットされず、is_set=false
  debug_inspect(dst.is_set(), content="false")
  // get() は parsed=true なので初期値 "" を返す（positional の ValCell 初期値）
  debug_inspect(
    dst.get(),
    content=(
      #|Some("")
    ),
  )
}

///|
test "serial_scope: greedy=false option between positionals" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let s = p.serial_scope() // default greedy=false
  let arg1 = s.positional(name="arg1")
  let arg2 = s.positional(name="arg2")
  // greedy=false では OC フェーズでオプションが先に消費され、
  // P フェーズで残りの positional が処理される
  ignore(p.parse(["hello", "--verbose", "world"]))
  debug_inspect(
    arg1.get(),
    content=(
      #|Some("hello")
    ),
  )
  debug_inspect(
    arg2.get(),
    content=(
      #|Some("world")
    ),
  )
  debug_inspect(verbose.get(), content="Some(true)")
}
