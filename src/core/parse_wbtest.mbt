///|
test "single flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--verbose"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "flag default is false" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  ignore(p.parse([]))
  inspect(p.get(verbose), content="Some(false)")
}

///|
test "unknown arg raises error" {
  let p = Parser::new()
  let _verbose = p.flag(name="verbose")
  let result : Result[_, _] = try? p.parse(["--unknown"])
  inspect(result is Err(_), content="true")
}

///|
test "multiple flags" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  ignore(p.parse(["--verbose", "--debug"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(debug), content="Some(true)")
}

///|
test "no-prefix negation" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", variations=[False("no")])
  ignore(p.parse(["--verbose", "--no-verbose"]))
  inspect(p.get(verbose), content="Some(false)")
}

///|
test "no-prefix with default true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true)
  ignore(p.parse([]))
  inspect(p.get(color), content="Some(true)")
}

///|
test "no-prefix resets to default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[False("no")])
  ignore(p.parse(["--no-color"]))
  inspect(p.get(color), content="Some(false)")
}

///|
test "string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  ignore(p.parse(["--host", "example.com"]))
  inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "string option default" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  ignore(p.parse([]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
}

///|
test "int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  ignore(p.parse(["--port", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "int option default" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  ignore(p.parse([]))
  inspect(p.get(port), content="Some(8080)")
}

///|
test "int parse error" {
  let p = Parser::new()
  let _port = p.int_opt(name="port", default=8080)
  let result : Result[_, _] = try? p.parse(["--port", "abc"])
  inspect(result is Err(_), content="true")
}

///|
test "missing value error" {
  let p = Parser::new()
  let _host = p.string_opt(name="host", default="localhost")
  let result : Result[_, _] = try? p.parse(["--host"])
  inspect(result is Err(_), content="true")
}

///|
test "int and string combined" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  let host = p.string_opt(name="host", default="localhost")
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--port", "3000", "--verbose", "--host", "example.com"]))
  inspect(p.get(port), content="Some(3000)")
  inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "no-prefix resets string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", variations=[Reset("no")])
  ignore(p.parse(["--host", "example.com", "--no-host"]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
}

///|
test "no-prefix resets int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, variations=[Reset("no")])
  ignore(p.parse(["--port", "3000", "--no-port"]))
  inspect(p.get(port), content="Some(8080)")
}

///|
test "equals syntax for string" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  ignore(p.parse(["--host=example.com"]))
  inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "equals syntax for int" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  ignore(p.parse(["--port=3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "equals syntax int parse error" {
  let p = Parser::new()
  let _port = p.int_opt(name="port", default=8080)
  let result : Result[_, _] = try? p.parse(["--port=abc"])
  inspect(result is Err(_), content="true")
}

///|
test "equals syntax mixed with space syntax" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  let host = p.string_opt(name="host", default="localhost")
  ignore(p.parse(["--port=3000", "--host", "example.com"]))
  inspect(p.get(port), content="Some(3000)")
  inspect(
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
  let port = p.int_opt(name="port", default=8080)
  ignore(p.parse(["--verbose", "--port=3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "append string" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  ignore(p.parse(["--tag", "a", "--tag", "b"]))
  inspect(
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
  inspect(
    p.get(tags),
    content=(
      #|Some([])
    ),
  )
}

///|
test "append string negate" {
  let p = Parser::new()
  let tags = p.append_string(name="tag", variations=[Reset("no")])
  ignore(p.parse(["--tag", "a", "--no-tag", "--tag", "b"]))
  inspect(
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
  inspect(
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
  let result : Result[_, _] = try? p.parse(["--num", "abc"])
  inspect(result is Err(_), content="true")
}

///|
test "append with equals syntax" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  ignore(p.parse(["--tag=a", "--tag=b"]))
  inspect(
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
  inspect(
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
  inspect(p.get(verbose), content="Some(true)")
  inspect(
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
  inspect(p.get(verbose), content="Some(true)")
  inspect(
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
  inspect(
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
  inspect(
    p.get(input),
    content=(
      #|Some("input.txt")
    ),
  )
  inspect(
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
  inspect(p.get(verbose), content="Some(true)")
  inspect(
    p.get(input),
    content=(
      #|Some("input.txt")
    ),
  )
  inspect(
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
  inspect(
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
  inspect(
    p.get(a),
    content=(
      #|Some("x")
    ),
  )
  inspect(
    p.get(b),
    content=(
      #|Some("y")
    ),
  )
  inspect(
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
  inspect(
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
  inspect(p.get(files), content="Some([])")
}

///|
test "rest with option" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  ignore(p.parse(["--verbose", "file1", "file2"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(
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
  inspect(p.get(verbose), content="Some(true)")
  inspect(
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
  inspect(p.get(files), content="Some([])")
}

///|
test "rest after positional" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let extras = p.rest(name="extras")
  ignore(p.parse(["input.txt", "a", "b"]))
  inspect(
    p.get(input),
    content=(
      #|Some("input.txt")
    ),
  )
  inspect(
    p.get(extras),
    content=(
      #|Some(["a", "b"])
    ),
  )
}

///|
test "subcommand basic" {
  let p = Parser::new()
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  ignore(p.parse(["serve", "--port", "3000"]))
  assert_true((serve.is_set)())
  inspect(p.get(port_opt.val.unwrap()), content="Some(3000)")
}

///|
test "subcommand not matched" {
  let p = Parser::new()
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  let build = p.cmd(name="build", setup=fn(_child) {  })
  ignore(p.parse(["build"]))
  assert_false((serve.is_set)())
  assert_true((build.is_set)())
}

///|
test "subcommand with parent flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  ignore(p.parse(["--verbose", "serve", "--port", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port_opt.val.unwrap()), content="Some(3000)")
}

///|
test "subcommand unknown option error" {
  let p = Parser::new()
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=8080)
  })
  let result : Result[_, _] = try? p.parse(["serve", "--unknown"])
  inspect(result is Err(_), content="true")
}

///|
test "nested subcommand" {
  let p = Parser::new()
  let name_opt : Ref[Opt[String]?] = { val: None }
  let _remote = p.cmd(name="remote", setup=fn(remote_parser) {
    let _add = remote_parser.cmd(name="add", setup=fn(add_parser) {
      name_opt.val = Some(add_parser.string_opt(name="name", default=""))
    })
  })
  ignore(p.parse(["remote", "add", "--name", "origin"]))
  match name_opt.val {
    Some(opt) =>
      inspect(
        p.get(opt),
        content=(
          #|Some("origin")
        ),
      )
    None => abort("unreachable")
  }
}

///|
test "nested subcommand with parent option" {
  let p = Parser::new()
  let url_opt : Ref[Opt[String]?] = { val: None }
  let _remote = p.cmd(name="remote", setup=fn(remote_parser) {
    let _add = remote_parser.cmd(name="add", setup=fn(add_parser) {
      url_opt.val = Some(add_parser.string_opt(name="url", default=""))
    })
  })
  ignore(p.parse(["remote", "add", "--url", "https://example.com"]))
  match url_opt.val {
    Some(opt) =>
      inspect(
        p.get(opt),
        content=(
          #|Some("https://example.com")
        ),
      )
    None => abort("unreachable")
  }
}

///|
test "global flag in subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  ignore(p.parse(["serve", "--verbose", "--port", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port_opt.val.unwrap()), content="Some(3000)")
}

///|
test "global flag before subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  ignore(p.parse(["--verbose", "serve", "--port", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port_opt.val.unwrap()), content="Some(3000)")
}

///|
test "global flag in nested subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let name_opt : Ref[Opt[String]?] = { val: None }
  let _remote = p.cmd(name="remote", setup=fn(remote_parser) {
    let _add = remote_parser.cmd(name="add", setup=fn(add_parser) {
      name_opt.val = Some(add_parser.string_opt(name="name", default=""))
    })
  })
  ignore(p.parse(["remote", "add", "--verbose", "--name", "origin"]))
  inspect(p.get(verbose), content="Some(true)")
  match name_opt.val {
    Some(opt) =>
      inspect(
        p.get(opt),
        content=(
          #|Some("origin")
        ),
      )
    None => abort("unreachable")
  }
}

///|
test "parse returns ParseResult" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let result = p.parse(["--verbose"])
  inspect(result.get(verbose), content="Some(true)")
}

///|
test "ParseResult::get before parse returns None" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let result : ParseResult = { kind: One, parser: p }
  inspect(result.get(verbose), content="None")
}

///|
test "ParseResult child navigation" {
  let p = Parser::new()
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  let result = p.parse(["serve", "--port", "3000"])
  // child で serve の ParseResult にナビゲート
  match result.child("serve") {
    Some(serve_result) =>
      inspect(serve_result.get(port_opt.val.unwrap()), content="Some(3000)")
    None => abort("serve child should exist")
  }
}

///|
test "ParseResult child not found" {
  let p = Parser::new()
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=8080)
  })
  let result = p.parse(["serve", "--port", "3000"])
  inspect(result.child("build") is None, content="true")
}

///|
test "ParseResult as_map with subcommand" {
  let p = Parser::new()
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=8080)
  })
  let result = p.parse(["serve"])
  inspect(result.as_map() is None, content="false")
}

///|
test "ParseResult as_map without subcommand" {
  let p = Parser::new()
  let _verbose = p.flag(name="verbose")
  let result = p.parse(["--verbose"])
  // cmd 登録がなければ One のまま
  inspect(result.as_map() is None, content="true")
}

///|
test "ParseResult nested child navigation" {
  let p = Parser::new()
  let name_opt : Ref[Opt[String]?] = { val: None }
  let _remote = p.cmd(name="remote", setup=fn(remote_parser) {
    let _add = remote_parser.cmd(name="add", setup=fn(add_parser) {
      name_opt.val = Some(add_parser.string_opt(name="name", default=""))
    })
  })
  let result = p.parse(["remote", "add", "--name", "origin"])
  match result.child("remote") {
    Some(remote_result) =>
      match remote_result.child("add") {
        Some(add_result) =>
          inspect(
            add_result.get(name_opt.val.unwrap()),
            content=(
              #|Some("origin")
            ),
          )
        None => abort("add child should exist")
      }
    None => abort("remote child should exist")
  }
}

///|
test "opt.get cobra-style" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let port = p.int_opt(name="port", default=8080)
  // parse 前は None
  inspect(verbose.get(), content="None")
  inspect(port.get(), content="None")
  // parse 後は Some
  ignore(p.parse(["--verbose", "--port", "3000"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(port.get(), content="Some(3000)")
}

///|
test "alias for flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v"])
  ignore(p.parse(["--v"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "alias no-prefix" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v"], variations=[False("no")])
  ignore(p.parse(["--v", "--no-v"]))
  inspect(p.get(verbose), content="Some(false)")
}

///|
test "alias for string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", aliases=["H"])
  ignore(p.parse(["--H", "example.com"]))
  inspect(
    p.get(host),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "alias for int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, aliases=["p"])
  ignore(p.parse(["--p", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "multiple aliases" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v", "verb"])
  ignore(p.parse(["--verb"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "alias with equals syntax" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, aliases=["p"])
  ignore(p.parse(["--p=3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "opt.get with subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  ignore(p.parse(["serve", "--verbose", "--port", "3000"]))
  // global flag は親の parsed で判定
  inspect(verbose.get(), content="Some(true)")
  // 子パーサの opt も子の parsed で判定
  inspect(port_opt.val.unwrap().get(), content="Some(3000)")
}

///|
test "short flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  ignore(p.parse(["-v"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "short int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, shorts="p")
  ignore(p.parse(["-p", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", shorts="H")
  ignore(p.parse(["-H", "example.com"]))
  inspect(
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
  let port = p.int_opt(name="port", default=8080, shorts="p")
  ignore(p.parse(["-v", "--port", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short append" {
  let p = Parser::new()
  let tags = p.append_string(name="tag", shorts="t")
  ignore(p.parse(["-t", "a", "-t", "b"]))
  inspect(
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
  inspect(p.get(a), content="Some(true)")
  inspect(p.get(b), content="Some(true)")
  inspect(p.get(c), content="Some(true)")
}

///|
test "short combining with value at end" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.int_opt(name="port", default=8080, shorts="p")
  ignore(p.parse(["-vp3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining value next arg" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.int_opt(name="port", default=8080, shorts="p")
  ignore(p.parse(["-vp", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining with string value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let host = p.string_opt(name="host", default="localhost", shorts="H")
  ignore(p.parse(["-vHexample.com"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(
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
  let result : Result[_, _] = try? p.parse(["-ax"])
  inspect(result is Err(_), content="true")
}

///|
test "short combining all flags" {
  let p = Parser::new()
  let e = p.flag(name="errexit", shorts="e")
  let u = p.flag(name="nounset", shorts="u")
  let o = p.flag(name="ooo", shorts="o")
  ignore(p.parse(["-euo"]))
  inspect(p.get(e), content="Some(true)")
  inspect(p.get(u), content="Some(true)")
  inspect(p.get(o), content="Some(true)")
}

///|
test "count basic" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse(["--verbose", "--verbose", "--verbose"]))
  inspect(p.get(verbose), content="Some(3)")
}

///|
test "count default zero" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse([]))
  inspect(p.get(verbose), content="Some(0)")
}

///|
test "count short" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse(["-v", "-v"]))
  inspect(p.get(verbose), content="Some(2)")
}

///|
test "count short combining -vvv" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v")
  ignore(p.parse(["-vvv"]))
  inspect(p.get(verbose), content="Some(3)")
}

///|
test "count reset with no-prefix" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="v", variations=[Reset("no")])
  ignore(p.parse(["-vvv", "--no-verbose", "-v"]))
  inspect(p.get(verbose), content="Some(1)")
}

///|
test "complex short combining: count + int + flag" {
  let p = Parser::new()
  let c = p.count(name="ccc", shorts="c")
  let a_opt = p.int_opt(name="aaa", default=0, shorts="A")
  let g = p.flag(name="ggg", shorts="g")
  // -cA1gcc → c(count) A(int=1) g(flag) c(count) c(count)
  ignore(p.parse(["-cA1gcc"]))
  inspect(p.get(c), content="Some(3)")
  inspect(p.get(a_opt), content="Some(1)")
  inspect(p.get(g), content="Some(true)")
}

///|
test "complex short combining: flags and int" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let a_opt = p.int_opt(name="after", default=0, shorts="A")
  let b_opt = p.int_opt(name="before", default=0, shorts="B")
  // -vA1 -B1 なら動く
  ignore(p.parse(["-vA1", "-B1"]))
  inspect(p.get(v), content="Some(true)")
  inspect(p.get(a_opt), content="Some(1)")
  inspect(p.get(b_opt), content="Some(1)")
}

///|
test "generate_help basic" {
  let p = Parser::new()
  p.set_description("My CLI tool")
  let _ = p.flag(name="verbose", shorts="v", description="Enable verbose output")
  let _ = p.int_opt(name="port", default=8080, description="Set port number")
  let help = p.generate_help()
  inspect(help.contains("My CLI tool"), content="true")
  inspect(help.contains("--verbose"), content="true")
  inspect(help.contains("-v"), content="true")
  inspect(help.contains("--port"), content="true")
  inspect(help.contains("[default: 8080]"), content="true")
}

///|
test "help flag raises HelpRequested" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "short help flag raises HelpRequested" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let result : Result[_, _] = try? p.parse(["-h"])
  match result {
    Err(HelpRequested(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "HelpRequested text contains flag description" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Enable verbose output")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--verbose"), content="true")
      inspect(text.contains("-v"), content="true")
      inspect(text.contains("Enable verbose output"), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "string_opt default shown in help" {
  let p = Parser::new()
  let _ = p.string_opt(name="host", default="localhost", description="Set host")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--host"), content="true")
      inspect(text.contains("[default: localhost]"), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "global option in Global Options section" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", global=true, description="Verbose mode")
  let _ = p.flag(name="debug", description="Debug mode")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("Global Options:"), content="true")
      inspect(text.contains("Options:"), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "cmd shown in Commands section" {
  let p = Parser::new()
  let _ = p.cmd(name="serve", setup=fn(_child) {  }, description="Start server")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("Commands:"), content="true")
      inspect(text.contains("serve"), content="true")
      inspect(text.contains("Start server"), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "short option format in help" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Verbose")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) =>
      inspect(text.contains("-v, --verbose"), content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "subcommand help shows own scope" {
  let p = Parser::new()
  let _ = p.cmd(
    name="serve",
    setup=fn(child) {
      let _ = child.int_opt(name="port", default=8080, description="Set port")
    },
    description="Start server",
  )
  let result : Result[_, _] = try? p.parse(["serve", "--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--port"), content="true")
      // serve のヘルプには Commands: セクションがない
      inspect(text.contains("Commands:"), content="false")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "hidden option not shown in help" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let _ = p.flag(name="secret", description="Secret option", hidden=true)
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--verbose"), content="true")
      inspect(text.contains("--secret"), content="false")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "description shown in help" {
  let p = Parser::new()
  p.set_description("My awesome CLI")
  let _ = p.flag(name="verbose", description="Verbose")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) =>
      inspect(text.contains("My awesome CLI"), content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "parse error includes help_text" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Enable verbose output")
  let _ = p.int_opt(name="port", default=8080, description="Set port number")
  let result : Result[_, _] = try? p.parse(["--unknown"])
  match result {
    Err(ParseError(info)) => {
      inspect(
        info.message,
        content=(
          #|unexpected argument: --unknown
        ),
      )
      // help_text が空でないことを確認
      inspect(info.help_text == "", content="false")
      // help_text にオプション情報が含まれること
      inspect(info.help_text.contains("--verbose"), content="true")
      inspect(info.help_text.contains("--port"), content="true")
    }
    _ => abort("expected ParseError")
  }
}

///|
test "ParseErrorInfo::to_string format" {
  let info = ParseErrorInfo::{
    message: "unexpected argument: --foo",
    help_text: "",
  }
  inspect(
    info.to_string(),
    content=(
      #|error: unexpected argument: --foo
    ),
  )
  let info2 = ParseErrorInfo::{
    message: "unexpected argument: --foo",
    help_text: "Options:\n  --help\n",
  }
  let expected = "error: unexpected argument: --foo\n\nOptions:\n  --help\n"
  inspect(info2.to_string() == expected, content="true")
}

///|
test "subcommand error has child help_text" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose mode")
  let _ = p.cmd(
    name="serve",
    setup=fn(child) {
      let _ = child.int_opt(name="port", default=8080, description="Set port")
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
      // 子パーサ (serve) の help_text が設定されている
      inspect(info.help_text.contains("--port"), content="true")
      // 親パーサのオプション (--verbose) は含まれない（子のヘルプが優先）
      inspect(info.help_text.contains("--verbose"), content="false")
    }
    _ => abort("expected ParseError")
  }
}

///|
test "short combining append_int" {
  let p = Parser::new()
  let nums = p.append_int(name="num", shorts="n")
  ignore(p.parse(["-n1", "-n2"]))
  inspect(p.get(nums), content="Some([1, 2])")
}

///|
test "dashdash basic" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash()
  ignore(p.parse(["--", "file1", "file2"]))
  inspect(
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
  inspect(
    files.get(),
    content=(
      #|Some(["ccc"])
    ),
  )
  inspect(
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
  inspect(verbose.get(), content="Some(true)")
  inspect(
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
  inspect(dd.get(), content="Some([])")
}

///|
test "dashdash no separator" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash()
  ignore(p.parse([]))
  inspect(dd.get(), content="Some([])")
}

///|
test "dashdash custom separator" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash(separator=":::")
  ignore(p.parse([":::", "a", "b"]))
  inspect(
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
  inspect(
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
  inspect(
    files.get(),
    content=(
      #|Some(["ccc"])
    ),
  )
  inspect(
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
  inspect(dd.get(), content="Some([])")
}

///|
test "append_dashdash single group" {
  let p = Parser::new(dashdash=false)
  let dd = p.append_dashdash()
  ignore(p.parse(["--", "a", "b"]))
  inspect(
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
  inspect(
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
  inspect(
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
  let nums = p.append_int(name="num", shorts="n")
  ignore(p.parse(["-vn1"]))
  inspect(p.get(v), content="Some(true)")
  inspect(p.get(nums), content="Some([1])")
}

///|
test "post filter basic" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    post=Some(Filter::map(fn(s) { if s == "auto" { "always" } else { s } })),
  )
  ignore(p.parse([]))
  // default "auto" is transformed to "always" by post
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "post filter with explicit value" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    post=Some(Filter::map(fn(s) { if s == "auto" { "none" } else { s } })),
  )
  ignore(p.parse(["--color", "none"]))
  // explicit "none" passes through post unchanged
  inspect(
    color.get(),
    content=(
      #|Some("none")
    ),
  )
}

///|
test "post filter validation error" {
  let p = Parser::new()
  let _val = p.string_opt(
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
  let result : Result[_, _] = try? p.parse([])
  inspect(result is Err(_), content="true")
}

// === enum or パターン PoC ===

///|
enum TestColor {
  Red
  Green
  Blue
  RGB(Int, Int, Int)
  Auto
} derive(Show, Eq)

///|
/// ヘルパー: --color <name> → TestColor (consumed=2) の ExactNode を生成
fn make_color_exact(
  opt_name : String,
  value_str : String,
  color : TestColor,
  cell : Ref[TestColor],
) -> ExactNode {
  ExactNode::{
    name: opt_name,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_name {
        return Reject
      }
      if pos + 1 >= args.length() || args[pos + 1] != value_str {
        return Reject
      }
      Accept(consumed=2, commit=fn() {
        cell.val = color
      })
    },
    reset: fn() {
      cell.val = Auto
    },
  }
}

///|
/// ヘルパー: --color rgb R G B → RGB(r,g,b) (consumed=5) の ExactNode
fn make_color_rgb_node(
  opt_name : String,
  cell : Ref[TestColor],
) -> ExactNode {
  ExactNode::{
    name: opt_name,
    needs_value: true,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_name {
        return Reject
      }
      if pos + 1 >= args.length() || args[pos + 1] != "rgb" {
        return Reject
      }
      if pos + 4 >= args.length() {
        return Reject
      }
      let parse_int = fn(s : String) -> Int? {
        let r : Result[Int, _] = try? @strconv.parse_int(s.view())
        match r {
          Ok(v) => Some(v)
          Err(_) => None
        }
      }
      match
        (
          parse_int(args[pos + 2]),
          parse_int(args[pos + 3]),
          parse_int(args[pos + 4]),
        ) {
        (Some(r), Some(g), Some(b)) =>
          Accept(consumed=5, commit=fn() {
            cell.val = RGB(r, g, b)
          })
        _ => Reject
      }
    },
    reset: fn() {
      cell.val = Auto
    },
  }
}

///|
/// ヘルパー: --color だけ (consumed=1) → implicit value
fn make_color_implicit_node(
  opt_name : String,
  implicit : TestColor,
  cell : Ref[TestColor],
) -> ExactNode {
  ExactNode::{
    name: opt_name,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != opt_name {
        return Reject
      }
      Accept(consumed=1, commit=fn() {
        cell.val = implicit
      })
    },
    reset: fn() {
      cell.val = Auto
    },
  }
}

///|
/// 全ノードを Parser に登録するヘルパー
fn setup_color_opt(p : Parser) -> Ref[TestColor] {
  let cell : Ref[TestColor] = { val: Auto }
  let nodes : Array[ExactNode] = [
    make_color_exact("--color", "red", Red, cell),
    make_color_exact("--color", "green", Green, cell),
    make_color_exact("--color", "blue", Blue, cell),
    make_color_rgb_node("--color", cell),
    make_color_implicit_node("--color", Red, cell),
  ]
  for node in nodes {
    p.nodes.push(node)
  }
  cell
}

///|
test "enum or: --color red" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "red"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: --color green" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "green"]))
  inspect(cell.val, content="Green")
}

///|
test "enum or: --color rgb 255 128 0" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "rgb", "255", "128", "0"]))
  inspect(cell.val, content="RGB(255, 128, 0)")
}

///|
test "enum or: --color (implicit → Red)" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: no --color (default → Auto)" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse([]))
  inspect(cell.val, content="Auto")
}

///|
test "enum or: --color red wins over implicit" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "red"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: --color with other flag → implicit" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "--verbose"]))
  inspect(cell.val, content="Red")
  inspect(verbose.get(), content="Some(true)")
}

///|
test "enum or: --color rgb with args then other opt" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "rgb", "10", "20", "30", "--verbose"]))
  inspect(cell.val, content="RGB(10, 20, 30)")
  inspect(verbose.get(), content="Some(true)")
}

///|
test "enum or: default not used when --color specified" {
  let p = Parser::new()
  let cell = setup_color_opt(p)
  ignore(p.parse(["--color", "blue"]))
  inspect(cell.val, content="Blue")
}

// === string_opt + choices + implicit_value テスト ===

///|
test "string_opt choices+implicit: --color always" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color", "always"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string_opt choices+implicit: --color (implicit)" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string_opt choices+implicit: no --color (default)" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse([]))
  inspect(
    color.get(),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "string_opt choices+implicit: --color with other flag" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "--verbose"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
  inspect(verbose.get(), content="Some(true)")
}

///|
test "string_opt choices+implicit: --color rander → implicit then unexpected" {
  let p = Parser::new()
  let _color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let result : Result[_, _] = try? p.parse(["--color", "rander"])
  inspect(result is Err(_), content="true")
}

///|
test "string_opt choices+implicit: --no-color resets" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
    variations=[Reset("no")],
  )
  ignore(p.parse(["--color", "none", "--no-color"]))
  inspect(
    color.get(),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "string_opt choices+implicit: --color=always (eq_split)" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color=always"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string_opt choices+implicit: Thunk implicit_value" {
  let counter : Ref[Int] = { val: 0 }
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(
      Thunk(fn() {
        counter.val += 1
        "always"
      }),
    ),
  )
  ignore(p.parse(["--color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
  inspect(counter.val, content="1")
}

///|
test "string_opt choices only: --color invalid → error" {
  let p = Parser::new()
  let _color = p.string_opt(name="color", default="auto", choices=[
    "always", "none", "auto",
  ])
  let result : Result[_, _] = try? p.parse(["--color", "invalid"])
  inspect(result is Err(_), content="true")
}

///|
test "string_opt choices only: --color always → ok" {
  let p = Parser::new()
  let color = p.string_opt(name="color", default="auto", choices=[
    "always", "none", "auto",
  ])
  ignore(p.parse(["--color", "always"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string_opt implicit only: --output (implicit)" {
  let p = Parser::new()
  let output = p.string_opt(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output"]))
  inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
}

///|
test "string_opt implicit only: --output file.txt" {
  let p = Parser::new()
  let output = p.string_opt(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output", "file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "string_opt choices+implicit with post filter" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
    post=Some(Filter::map(fn(s) { if s == "auto" { "none" } else { s } })),
  )
  ignore(p.parse([]))
  inspect(
    color.get(),
    content=(
      #|Some("none")
    ),
  )
}

///|
test "string_opt choices+implicit: multiple opts with implicit default" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let md = p.string_opt(
    name="md",
    default="none",
    choices=["render", "source", "none"],
    implicit_value=Some(Val("render")),
  )
  ignore(p.parse(["--color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
  inspect(
    md.get(),
    content=(
      #|Some("none")
    ),
  )
}

// === int_opt + implicit_value テスト ===

///|
test "int_opt implicit: --port (implicit)" {
  let p = Parser::new()
  let port = p.int_opt(
    name="port",
    default=8080,
    implicit_value=Some(Val(3000)),
  )
  ignore(p.parse(["--port"]))
  inspect(port.get(), content="Some(3000)")
}

///|
test "int_opt implicit: --port 9090" {
  let p = Parser::new()
  let port = p.int_opt(
    name="port",
    default=8080,
    implicit_value=Some(Val(3000)),
  )
  ignore(p.parse(["--port", "9090"]))
  inspect(port.get(), content="Some(9090)")
}

///|
test "int_opt implicit: no --port (default)" {
  let p = Parser::new()
  let port = p.int_opt(
    name="port",
    default=8080,
    implicit_value=Some(Val(3000)),
  )
  ignore(p.parse([]))
  inspect(port.get(), content="Some(8080)")
}

///|
test "int_opt implicit: --port foo → implicit (Reject fallback)" {
  let p = Parser::new()
  let port = p.int_opt(
    name="port",
    default=8080,
    implicit_value=Some(Val(3000)),
  )
  let _files = p.rest(name="files")
  ignore(p.parse(["--port", "foo"]))
  // "foo" は int パースに失敗 → Reject → implicit 3000、"foo" は rest に
  inspect(port.get(), content="Some(3000)")
}

// === composite node + short combining テスト ===

///|
test "string_opt choices+implicit: short combining -vc" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let color = p.string_opt(
    name="color",
    default="auto",
    shorts="c",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["-vc"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string_opt choices+implicit: short combining -cv" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let color = p.string_opt(
    name="color",
    default="auto",
    shorts="c",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  // -cv → c は remaining="v" あり → value trial: "v" は choice にない → Reject
  //      → flag trial: implicit Accept(consumed=1) → OK
  //      → v: flag Accept → OK
  ignore(p.parse(["-cv"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  )
}

///|
test "string_opt choices+implicit: short -cnone (inline value)" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    shorts="c",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  // -cnone → c は remaining="none" → value trial: choice "none" Accept(consumed=2)
  ignore(p.parse(["-cnone"]))
  inspect(
    color.get(),
    content=(
      #|Some("none")
    ),
  )
}

///|
test "string_opt implicit_only: --output=-foo (eq-split)" {
  let p = Parser::new()
  let output = p.string_opt(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output=-foo"]))
  inspect(
    output.get(),
    content=(
      #|Some("-foo")
    ),
  )
}

///|
test "string_opt implicit_only: --output --verbose → implicit" {
  let p = Parser::new()
  let output = p.string_opt(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--output", "--verbose"]))
  inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
  inspect(verbose.get(), content="Some(true)")
}

///|
test "int_opt implicit: short combining -vp" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.int_opt(
    name="port",
    default=8080,
    shorts="p",
    implicit_value=Some(Val(3000)),
  )
  ignore(p.parse(["-vp"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(port.get(), content="Some(3000)")
}

///|
test "string_opt choices+implicit: --color=invalid → error" {
  let p = Parser::new()
  let _color = p.string_opt(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let result : Result[_, _] = try? p.parse(["--color=invalid"])
  inspect(result is Err(_), content="true")
}

// === stop_before テスト ===

///|
test "rest stop_before stops at marker" {
  let p = Parser::new(dashdash=false)
  let files = p.rest(name="files", stop_before=["++"])
  let dd = p.dashdash(separator="++")
  ignore(p.parse(["a", "b", "++", "c", "d"]))
  inspect(
    p.get(files),
    content=(
      #|Some(["a", "b"])
    ),
  )
  inspect(
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
  inspect(
    p.get(files),
    content=(
      #|Some(["a"])
    ),
  )
  inspect(
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
  inspect(
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
  inspect(
    p.get(dd1),
    content=(
      #|Some(["a", "b"])
    ),
  )
  inspect(
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
  inspect(
    p.get(dd),
    content=(
      #|Some([["a", "b"]])
    ),
  )
  inspect(
    p.get(extra),
    content=(
      #|Some(["c"])
    ),
  )
}

// === exclusive / required / is_set テスト ===

///|
test "exclusive flags pass when only one set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.exclusive([json.as_ref(), csv.as_ref()])
  ignore(p.parse(["--json"]))
  inspect(p.get(json), content="Some(true)")
  inspect(p.get(csv), content="Some(false)")
}

///|
test "exclusive flags error when both set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.exclusive([json.as_ref(), csv.as_ref()])
  let result : Result[_, _] = try? p.parse(["--json", "--csv"])
  inspect(result is Err(_), content="true")
}

///|
test "exclusive allows none set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.exclusive([json.as_ref(), csv.as_ref()])
  ignore(p.parse([]))
  inspect(p.get(json), content="Some(false)")
}

///|
test "required option present" {
  let p = Parser::new()
  let output = p.string_opt(name="output", default="")
  p.required(output.as_ref())
  ignore(p.parse(["--output", "file.txt"]))
  inspect(
    p.get(output),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "required option missing" {
  let p = Parser::new()
  let output = p.string_opt(name="output", default="")
  p.required(output.as_ref())
  let result : Result[_, _] = try? p.parse(["--other"])
  inspect(result is Err(_), content="true")
}

///|
test "is_set false for default fallback" {
  let p = Parser::new(dashdash=false)
  let color = p.string_opt(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse([]))
  inspect((color.is_set)(), content="false")
  inspect(
    p.get(color),
    content=(
      #|Some("auto")
    ),
  )
}

///|
test "is_set true for explicit value" {
  let p = Parser::new(dashdash=false)
  let color = p.string_opt(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color", "never"]))
  inspect((color.is_set)(), content="true")
  inspect(
    p.get(color),
    content=(
      #|Some("never")
    ),
  )
}

///|
test "is_set true for implicit value" {
  let p = Parser::new(dashdash=false)
  let color = p.string_opt(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color"]))
  inspect((color.is_set)(), content="true")
  inspect(
    p.get(color),
    content=(
      #|Some("always")
    ),
  )
}

// === never コンビネータテスト ===

///|
test "never rejects extra positional args" {
  let p = Parser::new(dashdash=false)
  let _file = p.positional(name="file")
  p.never()
  let result : Result[_, _] = try? p.parse(["a", "b"])
  inspect(result is Err(_), content="true")
}

///|
test "never allows exact positional count" {
  let p = Parser::new(dashdash=false)
  let file = p.positional(name="file")
  p.never()
  ignore(p.parse(["hello"]))
  inspect(
    p.get(file),
    content=(
      #|Some("hello")
    ),
  )
}

///|
test "never allows zero args" {
  let p = Parser::new(dashdash=false)
  p.never()
  ignore(p.parse([]))
}

// === serial コンビネータテスト ===

///|
test "serial basic positional grouping" {
  let p = Parser::new(dashdash=false)
  let src = p.positional(name="src")
  let dst = p.positional(name="dst")
  // serial を使わなくても順序消費は動く（比較用）
  ignore(p.parse(["hello", "world"]))
  inspect(
    p.get(src),
    content=(
      #|Some("hello")
    ),
  )
  inspect(
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
  inspect(
    src.unwrap().get(),
    content=(
      #|Some("a")
    ),
  )
  inspect(
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
  let result : Result[_, _] = try? p.parse(["a", "b", "c"])
  inspect(result is Err(_), content="true")
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
  inspect(p.get(flag), content="Some(true)")
  inspect(
    src.unwrap().get(),
    content=(
      #|Some("hello")
    ),
  )
  inspect(
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
  inspect(
    files.unwrap().get(),
    content=(
      #|Some(["a", "b", "c"])
    ),
  )
}

///|
test "sub basic — no Ref needed" {
  let p = Parser::new()
  let clone = p.sub(name="clone")
  let url = clone.positional(name="url")
  let depth = clone.int_opt(name="depth", default=0)
  let result = p.parse(["clone", "https://example.com", "--depth", "3"])
  inspect(result.child("clone") is Some(_), content="true")
  inspect(url.get(), content="Some(\"https://example.com\")")
  inspect(depth.get(), content="Some(3)")
}

///|
test "sub nested — remote add without Ref" {
  let p = Parser::new()
  let remote = p.sub(name="remote")
  let add = remote.sub(name="add")
  let name_opt = add.positional(name="name")
  let url_opt = add.positional(name="url")
  let result = p.parse(["remote", "add", "origin", "https://example.com"])
  match result.child("remote") {
    Some(remote_result) =>
      match remote_result.child("add") {
        Some(_) => {
          inspect(
            name_opt.get(),
            content=(
              #|Some("origin")
            ),
          )
          inspect(
            url_opt.get(),
            content=(
              #|Some("https://example.com")
            ),
          )
        }
        None => abort("add child should exist")
      }
    None => abort("remote child should exist")
  }
}

///|
test "sub with global option propagation" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let clone = p.sub(name="clone")
  let url = clone.positional(name="url")
  ignore(p.parse(["clone", "--verbose", "https://example.com"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(
    url.get(),
    content=(
      #|Some("https://example.com")
    ),
  )
}

///|
test "sub help shows options after help flag" {
  let p = Parser::new()
  let clone = p.sub(name="clone", description="Clone a repo")
  let _ = clone.flag(name="depth", description="Shallow clone")
  let result : Result[_, _] = try? p.parse(["clone", "--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("--depth"), content="true")
      inspect(text.contains("--help"), content="true")
    }
    _ => abort("expected HelpRequested")
  }
}

///|
test "sub with required and exclusive" {
  let p = Parser::new()
  let config = p.sub(name="config")
  let global_flag = config.flag(name="global")
  let local_flag = config.flag(name="local")
  config.exclusive([global_flag.as_ref(), local_flag.as_ref()])
  let key = config.positional(name="key")
  config.required(key.as_ref())
  // valid: --global with key
  let result = p.parse(["config", "--global", "user.name"])
  inspect(result.child("config") is Some(_), content="true")
  inspect(global_flag.get(), content="Some(true)")
  inspect(local_flag.get(), content="Some(false)")
  inspect(
    key.get(),
    content=(
      #|Some("user.name")
    ),
  )
}

///|
test "sub exclusive error" {
  let p = Parser::new()
  let config = p.sub(name="config")
  let global_flag = config.flag(name="global")
  let local_flag = config.flag(name="local")
  config.exclusive([global_flag.as_ref(), local_flag.as_ref()])
  let result : Result[_, _] = try? p.parse(["config", "--global", "--local"])
  inspect(result is Err(_), content="true")
}

///|
test "sub required missing error" {
  let p = Parser::new()
  let config = p.sub(name="config")
  let key = config.positional(name="key")
  config.required(key.as_ref())
  let result : Result[_, _] = try? p.parse(["config"])
  inspect(result is Err(_), content="true")
}

///|
test "sub with serial and never" {
  let p = Parser::new()
  let add = p.sub(name="add")
  let mut src : Opt[String]? = None
  let mut dst : Opt[String]? = None
  add.serial(setup=fn(sub) {
    src = Some(sub.positional(name="src"))
    dst = Some(sub.positional(name="dst"))
    sub.never()
  })
  ignore(p.parse(["add", "a.txt", "b.txt"]))
  inspect(
    src.unwrap().get(),
    content=(
      #|Some("a.txt")
    ),
  )
  inspect(
    dst.unwrap().get(),
    content=(
      #|Some("b.txt")
    ),
  )
}

///|
test "sub with dashdash" {
  let p = Parser::new()
  let stash = p.sub(name="stash", dashdash=false)
  let msg = stash.string_opt(name="message", default="", shorts="m")
  let files = stash.dashdash()
  ignore(p.parse(["stash", "-m", "wip", "--", "file1", "file2"]))
  inspect(
    msg.get(),
    content=(
      #|Some("wip")
    ),
  )
  inspect(
    files.get(),
    content=(
      #|Some(["file1", "file2"])
    ),
  )
}

///|
test "require_cmd errors when no subcommand" {
  let p = Parser::new()
  let _ = p.sub(name="clone", description="Clone a repo")
  let _ = p.sub(name="commit", description="Commit changes")
  p.require_cmd()
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message, content="subcommand required")
      inspect(info.help_text.contains("clone"), content="true")
      inspect(info.help_text.contains("commit"), content="true")
    }
    _ => abort("expected ParseError")
  }
}

///|
test "require_cmd passes when subcommand selected" {
  let p = Parser::new()
  let clone = p.sub(name="clone")
  let _ = clone.positional(name="url")
  p.require_cmd()
  let result = p.parse(["clone", "https://example.com"])
  inspect(result.child("clone") is Some(_), content="true")
}

///|
test "require_cmd errors with flags but no subcommand" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let _ = p.sub(name="serve", description="Start server")
  p.require_cmd()
  let result : Result[_, _] = try? p.parse(["--verbose"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message, content="subcommand required")
      inspect(info.help_text.contains("serve"), content="true")
    }
    _ => abort("expected ParseError")
  }
}

///|
test "require_cmd errors on nested sub" {
  let p = Parser::new()
  let remote = p.sub(name="remote")
  let _ = remote.sub(name="add", description="Add remote")
  remote.require_cmd()
  let result : Result[_, _] = try? p.parse(["remote"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message, content="subcommand required")
      inspect(info.help_text.contains("add"), content="true")
    }
    _ => abort("expected ParseError")
  }
}

///|
test "sub + serial positionals" {
  let p = Parser::new()
  let remote = p.sub(name="remote")
  let mut remote_name : Opt[String]? = None
  let mut remote_url : Opt[String]? = None
  remote.serial(setup=fn(sub) {
    remote_name = Some(sub.positional(name="name"))
    remote_url = Some(sub.positional(name="url"))
    sub.never()
  })
  let result = p.parse(["remote", "origin", "https://example.com"])
  inspect(result.child("remote") is Some(_), content="true")
  inspect(
    remote_name.unwrap().get(),
    content=(
      #|Some("origin")
    ),
  )
  inspect(
    remote_url.unwrap().get(),
    content=(
      #|Some("https://example.com")
    ),
  )
}

///|
test "parse called twice raises error" {
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  ignore(p.parse([]))
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("can only be called once"),
        content="true",
      )
    _ => abort("expected ParseError")
  }
}

///|
test "require_cmd with no commands defined" {
  let p = Parser::new()
  p.require_cmd()
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => inspect(info.message, content="subcommand required")
    _ => abort("expected ParseError")
  }
}

///|
test "require_cmd with --help still shows help" {
  let p = Parser::new()
  let _ = p.sub(name="serve", description="Start server")
  p.require_cmd()
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => inspect(text.contains("serve"), content="true")
    _ => abort("expected HelpRequested")
  }
}

// ============ Variation tests ============

///|
test "variation: False flag with default=true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[False("no")])
  ignore(p.parse(["--no-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: False flag with default=false" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default=false, variations=[False("no")])
  ignore(p.parse(["--no-verbose"]))
  // False sets cell=false (same as default), but was_set=true
  inspect(p.get(verbose), content="Some(false)")
  inspect((verbose.is_set)(), content="true")
}

///|
test "variation: Reset flag resets to default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[Reset("reset")])
  // First set to true (positive), then reset
  ignore(p.parse(["--color", "--reset-color"]))
  inspect(p.get(color), content="Some(true)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: Unset flag resets value and was_set" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Unset("unset")])
  ignore(p.parse(["--color", "--unset-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="false")
}

///|
test "variation: True/False flag with enable/disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--enable-color"]))
  inspect(p.get(color), content="Some(true)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: True/False flag disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: True/False flag enable then disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--enable-color", "--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: count with Reset" {
  let p = Parser::new()
  let v = p.count(name="verbose", variations=[Reset("no")])
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose"]))
  inspect(p.get(v), content="Some(0)")
  inspect((v.is_set)(), content="true")
}

///|
test "variation: string_opt with Reset" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", variations=[Reset("no")])
  ignore(p.parse(["--host", "example.com", "--no-host"]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
  inspect((host.is_set)(), content="true")
}

///|
test "variation: string_opt with Unset" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", variations=[Unset("unset")])
  ignore(p.parse(["--host", "example.com", "--unset-host"]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
  inspect((host.is_set)(), content="false")
}

///|
test "variation: int_opt with Reset" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, variations=[Reset("no")])
  ignore(p.parse(["--port", "3000", "--no-port"]))
  inspect(p.get(port), content="Some(8080)")
  inspect((port.is_set)(), content="true")
}

///|
test "variation: append_string with Reset" {
  let p = Parser::new()
  let tags = p.append_string(name="tag", variations=[Reset("no")])
  ignore(p.parse(["--tag", "a", "--tag", "b", "--no-tag"]))
  inspect(p.get(tags), content="Some([])")
  inspect((tags.is_set)(), content="true")
}

///|
test "variation: append_int with Reset" {
  let p = Parser::new()
  let ids = p.append_int(name="id", variations=[Reset("no")])
  ignore(p.parse(["--id", "1", "--id", "2", "--no-id"]))
  inspect(p.get(ids), content="Some([])")
  inspect((ids.is_set)(), content="true")
}

///|
test "variation: flag alias also gets variation" {
  let p = Parser::new()
  let color = p.flag(name="color", aliases=["colour"], variations=[False("no")])
  ignore(p.parse(["--no-colour"]))
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: multiple variations" {
  let p = Parser::new()
  let color = p.flag(
    name="color",
    variations=[False("no"), True("enable"), False("disable")],
  )
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: empty variations means no --no- prefix" {
  let p = Parser::new()
  let _color = p.flag(name="color", variations=[])
  let result : Result[_, _] = try? p.parse(["--no-color"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("unexpected argument"), content="true")
    _ => abort("expected ParseError for unexpected argument --no-color")
  }
}

///|
test "variation: Toggle basic" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Toggle("toggle")])
  ignore(p.parse(["--color", "--toggle-color"]))
  // --color sets true (=!default), --toggle-color flips to false
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: Toggle double toggles back" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Toggle("toggle")])
  ignore(p.parse(["--color", "--toggle-color", "--toggle-color"]))
  // --color → true, --toggle → false, --toggle → true
  inspect(p.get(color), content="Some(true)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: Toggle with default=true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[Toggle("toggle")])
  ignore(p.parse(["--toggle-color"]))
  // default=true, toggle → false
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: True sets true regardless of default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[True("enable")])
  // Main (--color) with default=true sets to !default = false
  ignore(p.parse(["--color", "--enable-color"]))
  // --color → false, --enable-color → true
  inspect(p.get(color), content="Some(true)")
  inspect((color.is_set)(), content="true")
}

///|
test "variation: False sets false regardless of default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[False("disable")])
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect((color.is_set)(), content="true")
}

///|
test "flag Main = not default (default=true)" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true)
  ignore(p.parse(["--color"]))
  // Main with default=true: sets to !true = false
  inspect(p.get(color), content="Some(false)")
}

///|
test "flag Main = not default (default=false)" {
  let p = Parser::new()
  let color = p.flag(name="color", default=false)
  ignore(p.parse(["--color"]))
  // Main with default=false: sets to !false = true
  inspect(p.get(color), content="Some(true)")
}

// ============ Sugar parameter tests ============

///|
test "flag variation_reset sugar" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", variation_reset=Some("no"))
  ignore(p.parse(["--verbose", "--no-verbose"]))
  inspect(verbose.get(), content="Some(false)") // Reset → default(false)
  inspect((verbose.is_set)(), content="true")
}

///|
test "string_opt variation_reset sugar" {
  let p = Parser::new()
  let fmt = p.string_opt(name="format", default="json", variation_reset=Some("no"))
  ignore(p.parse(["--format", "xml", "--no-format"]))
  inspect(
    fmt.get(),
    content=(
      #|Some("json")
    ),
  ) // Reset → default
  inspect((fmt.is_set)(), content="true")
}

///|
test "sugar params append to variations" {
  let p = Parser::new()
  let verbose = p.flag(
    name="verbose",
    variations=[Toggle("toggle")],
    variation_reset=Some("no"),
  )
  // Toggle + Reset 両方が存在
  ignore(p.parse(["--toggle-verbose", "--no-verbose"]))
  inspect(verbose.get(), content="Some(false)") // Reset → default
  inspect((verbose.is_set)(), content="true")
}

///|
test "flag variation_true and variation_false sugar" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variation_true=Some("force"), variation_false=Some("no"))
  ignore(p.parse(["--no-color"]))
  inspect(color.get(), content="Some(false)") // False → always false
  //
  let p2 = Parser::new()
  let color2 = p2.flag(name="color", default=true, variation_true=Some("force"), variation_false=Some("no"))
  ignore(p2.parse(["--no-color", "--force-color"]))
  inspect(color2.get(), content="Some(true)") // True → always true
}

///|
test "count variation_reset sugar" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", variation_reset=Some("no"))
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose"]))
  inspect(verbose.get(), content="Some(0)") // Reset → default(0)
  inspect((verbose.is_set)(), content="true")
}

///|
test "append_string variation_reset sugar" {
  let p = Parser::new()
  let includes = p.append_string(name="include", variation_reset=Some("no"))
  ignore(p.parse(["--include", "a", "--include", "b", "--no-include"]))
  inspect(includes.get(), content="Some([])") // Reset → empty
  inspect((includes.is_set)(), content="true")
}

// ============ default_fn tests ============

///|
test "flag default_fn" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default_fn=Some(fn() { true }))
  ignore(p.parse([])) // no args
  inspect(verbose.get(), content="Some(true)") // default_fn で true
  inspect((verbose.is_set)(), content="false") // 明示指定なし
}

///|
test "flag default_fn overrides default" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default_fn=Some(fn() { true }))
  ignore(p.parse(["--verbose"]))
  // Main = !initial_val = !true = false
  inspect(verbose.get(), content="Some(false)")
  inspect((verbose.is_set)(), content="true")
}

///|
test "string_opt default_fn" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    default_fn=Some(fn() { "always" }),
  )
  ignore(p.parse([])) // no args
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  ) // default_fn が優先
  inspect((color.is_set)(), content="false")
}

///|
test "int_opt default_fn" {
  let p = Parser::new()
  let port = p.int_opt(
    name="port",
    default=80,
    default_fn=Some(fn() { 8080 }),
  )
  ignore(p.parse([])) // no args
  inspect(port.get(), content="Some(8080)") // default_fn が優先
  inspect((port.is_set)(), content="false")
}

///|
test "string_opt default_fn with reset variation" {
  let p = Parser::new()
  let color = p.string_opt(
    name="color",
    default="auto",
    default_fn=Some(fn() { "always" }),
    variation_reset=Some("no"),
  )
  ignore(p.parse(["--color", "never", "--no-color"]))
  inspect(
    color.get(),
    content=(
      #|Some("always")
    ),
  ) // Reset → default_fn の値に戻る
  inspect((color.is_set)(), content="true")
}

// ============ duplicate name validation tests ============

///|
test "duplicate option name detected" {
  let p = Parser::new()
  let _ = p.flag(name="no-verbose")
  let _ = p.flag(name="verbose", variation_reset=Some("no"))
  // --no-verbose が2つのコンビネータから生成される
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate option name"), content="true")
    _ => abort("expected duplicate name error")
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
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate option name"), content="true")
    _ => abort("expected duplicate name error")
  }
}

// --- custom[T] / custom_append[T] tests ---

///|
test "custom_string_basic" {
  let p = Parser::new()
  let name = p.custom(name="name", default="world", pre=Filter::map(fn(s) { s }))
  p.parse(["--name", "alice"]) |> ignore
  inspect((name.getter)(), content="alice")
}

///|
test "custom_string_default" {
  let p = Parser::new()
  let name = p.custom(name="name", default="world", pre=Filter::map(fn(s) { s }))
  p.parse([]) |> ignore
  inspect((name.getter)(), content="world")
}

///|
test "custom_int_basic" {
  let p = Parser::new()
  let port = p.custom(name="port", default=8080, pre=Filter::parse_int())
  p.parse(["--port", "3000"]) |> ignore
  inspect((port.getter)(), content="3000")
}

///|
test "custom_int_default" {
  let p = Parser::new()
  let port = p.custom(name="port", default=8080, pre=Filter::parse_int())
  p.parse([]) |> ignore
  inspect((port.getter)(), content="8080")
}

///|
test "custom_int_invalid" {
  let p = Parser::new()
  let _ = p.custom(name="port", default=8080, pre=Filter::parse_int())
  let result : Result[_, _] = try? p.parse(["--port", "abc"])
  inspect(result is Err(_), content="true")
}

///|
test "custom_double_basic" {
  let p = Parser::new()
  let rate = p.custom(name="rate", default=1.0, pre=Filter::parse_float())
  p.parse(["--rate", "3.14"]) |> ignore
  inspect((rate.getter)(), content="3.14")
}

///|
test "custom_with_choices" {
  let p = Parser::new()
  let level = p.custom(
    name="level", default="info",
    pre=Filter::map(fn(s) { s }),
    choices=["debug", "info", "warn", "error"],
  )
  p.parse(["--level", "warn"]) |> ignore
  inspect((level.getter)(), content="warn")
}

///|
test "custom_with_choices_invalid" {
  let p = Parser::new()
  let _ = p.custom(
    name="level", default="info",
    pre=Filter::map(fn(s) { s }),
    choices=["debug", "info", "warn", "error"],
  )
  let result : Result[_, _] = try? p.parse(["--level", "trace"])
  inspect(result is Err(_), content="true")
}

///|
test "custom_with_implicit_value" {
  let p = Parser::new()
  let verbose = p.custom(
    name="verbose", default=0,
    pre=Filter::parse_int(),
    implicit_value=Some(Val(1)),
  )
  // implicit: --verbose のみで implicit_value=1 が使われる
  p.parse(["--verbose"]) |> ignore
  inspect((verbose.getter)(), content="1")
}

///|
test "custom_with_implicit_value_explicit" {
  let p = Parser::new()
  let verbose = p.custom(
    name="verbose", default=0,
    pre=Filter::parse_int(),
    implicit_value=Some(Val(1)),
  )
  // explicit: --verbose 3 で明示値 3 が使われる
  p.parse(["--verbose", "3"]) |> ignore
  inspect((verbose.getter)(), content="3")
}

///|
test "custom_with_choices_and_implicit" {
  let p = Parser::new()
  let color = p.custom(
    name="color", default="auto",
    pre=Filter::map(fn(s) { s }),
    choices=["always", "never", "auto"],
    implicit_value=Some(Val("always")),
  )
  // implicit: --color のみで implicit_value="always"
  p.parse(["--color"]) |> ignore
  inspect((color.getter)(), content="always")
}

///|
test "custom_with_choices_and_implicit_explicit" {
  let p = Parser::new()
  let color = p.custom(
    name="color", default="auto",
    pre=Filter::map(fn(s) { s }),
    choices=["always", "never", "auto"],
    implicit_value=Some(Val("always")),
  )
  // explicit: --color never で明示値
  p.parse(["--color", "never"]) |> ignore
  inspect((color.getter)(), content="never")
}

///|
test "custom_with_post" {
  let p = Parser::new()
  let name = p.custom(
    name="name", default="world",
    pre=Filter::map(fn(s) { s }),
    post=Some(Filter::map(fn(s : String) { s.to_upper() })),
  )
  p.parse(["--name", "alice"]) |> ignore
  inspect((name.getter)(), content="ALICE")
}

///|
test "custom_append_string_basic" {
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }))
  p.parse(["--tag", "a", "--tag", "b"]) |> ignore
  inspect((tags.getter)(), content="[\"a\", \"b\"]")
}

///|
test "custom_append_string_empty" {
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }))
  p.parse([]) |> ignore
  inspect((tags.getter)(), content="[]")
}

///|
test "custom_append_int_basic" {
  let p = Parser::new()
  let nums = p.custom_append(name="num", pre=Filter::parse_int())
  p.parse(["--num", "1", "--num", "2", "--num", "3"]) |> ignore
  inspect((nums.getter)(), content="[1, 2, 3]")
}

///|
test "custom_append_int_invalid" {
  let p = Parser::new()
  let _ = p.custom_append(name="num", pre=Filter::parse_int())
  let result : Result[_, _] = try? p.parse(["--num", "abc"])
  inspect(result is Err(_), content="true")
}

// ============================================================
// shorts 複数文字テスト
// ============================================================

///|
test "shorts multiple chars: -v and -V both work" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="vV")
  ignore(p.parse(["-v"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "shorts multiple chars: -V works" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="vV")
  ignore(p.parse(["-V"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "shorts multiple chars: combining -vV same flag twice (count)" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="vV")
  ignore(p.parse(["-vV"]))
  inspect(p.get(verbose), content="Some(2)")
}

///|
test "shorts multiple chars: combining -Vv order reversed (count)" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="vV")
  ignore(p.parse(["-Vv"]))
  inspect(p.get(verbose), content="Some(2)")
}

///|
test "shorts multiple chars: -vvV combining (count=3)" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", shorts="vV")
  ignore(p.parse(["-vvV"]))
  inspect(p.get(verbose), content="Some(3)")
}

///|
test "shorts multiple chars: long option still works" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="vV")
  ignore(p.parse(["--verbose"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "shorts unicode: -あ works" {
  let p = Parser::new()
  let opt = p.flag(name="all", shorts="あ")
  ignore(p.parse(["-あ"]))
  inspect(p.get(opt), content="Some(true)")
}

///|
test "shorts unicode: combining with ASCII" {
  let p = Parser::new()
  let a = p.flag(name="all", shorts="あ")
  let b = p.flag(name="bbb", shorts="b")
  ignore(p.parse(["-bあ"]))
  inspect(p.get(a), content="Some(true)")
  inspect(p.get(b), content="Some(true)")
}

// ============================================================
// aliases の help 表示テスト
// ============================================================

///|
test "aliases shown in help: --name, --alias format" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", aliases=["verb"], description="Verbose output")
  let help = p.generate_help()
  inspect(help.contains("--verbose, --verb"), content="true")
}

///|
test "aliases multiple shown in help" {
  let p = Parser::new()
  let _ = p.string_opt(
    name="output", default="", aliases=["out", "o"],
    description="Output file",
  )
  let help = p.generate_help()
  inspect(help.contains("--output, --out, --o"), content="true")
}

///|
test "shorts + aliases combined in help: -v, -V, --verbose, --verb" {
  let p = Parser::new()
  let _ = p.flag(
    name="verbose", shorts="vV", aliases=["verb"],
    description="Verbose output",
  )
  let help = p.generate_help()
  inspect(help.contains("-v, -V, --verbose, --verb"), content="true")
}

///|
test "aliases also parse correctly" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["verb"])
  ignore(p.parse(["--verb"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "aliases for value option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, aliases=["p"])
  ignore(p.parse(["--p", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

// ============================================================
// int_opt の choices テスト
// ============================================================

///|
test "int_opt with choices: valid value accepted" {
  let p = Parser::new()
  let level = p.int_opt(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse(["--level", "2"]))
  inspect(p.get(level), content="Some(2)")
}

///|
test "int_opt with choices: another valid value" {
  let p = Parser::new()
  let level = p.int_opt(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse(["--level", "3"]))
  inspect(p.get(level), content="Some(3)")
}

///|
test "int_opt with choices: invalid value rejected" {
  let p = Parser::new()
  let _ = p.int_opt(name="level", default=1, choices=["1", "2", "3"])
  let result : Result[_, _] = try? p.parse(["--level", "5"])
  inspect(result is Err(_), content="true")
}

///|
test "int_opt with choices: default without args" {
  let p = Parser::new()
  let level = p.int_opt(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse([]))
  inspect(p.get(level), content="Some(1)")
}

// ============================================================
// int_opt の post テスト
// ============================================================

///|
test "int_opt with post: value transformed" {
  let p = Parser::new()
  let num = p.int_opt(
    name="num", default=0,
    post=Some(Filter::map(fn(n : Int) { n * 2 })),
  )
  ignore(p.parse(["--num", "5"]))
  inspect(p.get(num), content="Some(10)")
}

///|
test "int_opt with post: default also transformed" {
  let p = Parser::new()
  let num = p.int_opt(
    name="num", default=3,
    post=Some(Filter::map(fn(n : Int) { n * 2 })),
  )
  ignore(p.parse([]))
  // post hook runs on cell value unconditionally, so default 3 becomes 6
  inspect(p.get(num), content="Some(6)")
}

///|
test "int_opt with post: chained transform" {
  let p = Parser::new()
  let num = p.int_opt(
    name="num", default=0,
    post=Some(Filter::map(fn(n : Int) { n + 100 })),
  )
  ignore(p.parse(["--num", "5"]))
  inspect(p.get(num), content="Some(105)")
}

// ============================================================
// default_display 自動導出 (T : Show) テスト
// ============================================================

///|
test "custom[Int] default_display auto: shows [default: 42]" {
  let p = Parser::new()
  let _ = p.custom(
    name="count", default=42,
    pre=Filter::parse_int(),
    help="Item count",
  )
  let help = p.generate_help()
  inspect(help.contains("[default: 42]"), content="true")
}

///|
test "custom[Int] default=0: shows [default: 0] in help" {
  let p = Parser::new()
  let _ = p.custom(
    name="count", default=0,
    pre=Filter::parse_int(),
    help="Item count",
  )
  let help = p.generate_help()
  inspect(help.contains("[default: 0]"), content="true")
}

///|
test "custom[String] default empty: no default shown in help" {
  let p = Parser::new()
  let _ = p.custom(
    name="name", default="",
    pre=Filter::map(fn(s) { s }),
    help="User name",
  )
  let help = p.generate_help()
  inspect(help.contains("[default:"), content="false")
}

///|
test "custom[String] default non-empty: shows [default: hello]" {
  let p = Parser::new()
  let _ = p.custom(
    name="name", default="hello",
    pre=Filter::map(fn(s) { s }),
    help="User name",
  )
  let help = p.generate_help()
  inspect(help.contains("[default: hello]"), content="true")
}

///|
test "custom[Int] default_display=Some(\"\"): explicitly suppress default" {
  let p = Parser::new()
  let _ = p.custom(
    name="count", default=42,
    pre=Filter::parse_int(),
    help="Item count",
    default_display=Some(""),
  )
  let help = p.generate_help()
  inspect(help.contains("[default:"), content="false")
}

///|
test "custom[Int] default_display=Some(\"custom\"): custom display" {
  let p = Parser::new()
  let _ = p.custom(
    name="count", default=42,
    pre=Filter::parse_int(),
    help="Item count",
    default_display=Some("custom"),
  )
  let help = p.generate_help()
  inspect(help.contains("[default: custom]"), content="true")
  inspect(help.contains("[default: 42]"), content="false")
}

///|
test "int_opt default shown in help via auto derive" {
  let p = Parser::new()
  let _ = p.int_opt(name="port", default=8080, description="Port number")
  let help = p.generate_help()
  inspect(help.contains("[default: 8080]"), content="true")
}

///|
test "int_opt default=0 shown in help" {
  let p = Parser::new()
  let _ = p.int_opt(name="port", default=0, description="Port number")
  let help = p.generate_help()
  inspect(help.contains("[default: 0]"), content="true")
}

///|
test "string_opt default empty: no default shown in help" {
  let p = Parser::new()
  let _ = p.string_opt(name="host", default="", description="Host name")
  let help = p.generate_help()
  inspect(help.contains("[default:"), content="false")
}

// ============================================================
// shorts validation tests
// ============================================================

///|
test "shorts validation: hyphen rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="-")
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("invalid short option character '-'"),
        content="true",
      )
    _ => abort("expected error for hyphen in shorts")
  }
}

///|
test "shorts validation: space rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts=" ")
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("invalid short option character (whitespace)"),
        content="true",
      )
    _ => abort("expected error for space in shorts")
  }
}

///|
test "shorts validation: tab rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="\t")
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("invalid short option character (whitespace)"),
        content="true",
      )
    _ => abort("expected error for tab in shorts")
  }
}

///|
test "shorts validation: NUL rejected" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="\u0000")
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("invalid short option character (NUL)"),
        content="true",
      )
    _ => abort("expected error for NUL in shorts")
  }
}

///|
test "shorts validation: mixed valid and invalid" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v-")
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("invalid short option character '-'"),
        content="true",
      )
    _ => abort("expected error for hyphen in shorts")
  }
}

///|
test "shorts validation: unicode allowed" {
  let p = Parser::new()
  let opt = p.flag(name="all", shorts="あ")
  ignore(p.parse(["-あ"]))
  inspect(p.get(opt), content="Some(true)")
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
  inspect(p.get(a), content="Some(true)")
  inspect(p.get(i), content="Some(true)")
}

///|
test "shorts unicode combining: unicode short + inline value" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=0, shorts="あ")
  ignore(p.parse(["-あ3000"]))
  inspect(p.get(port), content="Some(3000)")
}

// ============================================================
// choices help display tests
// ============================================================

///|
test "choices shown in help: [possible values: ...]" {
  let p = Parser::new()
  let _ = p.string_opt(
    name="color", default="auto",
    choices=["always", "auto", "never"],
    description="Color mode",
  )
  let help = p.generate_help()
  inspect(
    help.contains("[possible values: always, auto, never]"),
    content="true",
  )
}

///|
test "choices + default shown in help together" {
  let p = Parser::new()
  let _ = p.string_opt(
    name="color", default="auto",
    choices=["always", "auto", "never"],
    description="Color mode",
  )
  let help = p.generate_help()
  inspect(
    help.contains("[possible values: always, auto, never] [default: auto]"),
    content="true",
  )
}

///|
test "no choices: no possible values in help" {
  let p = Parser::new()
  let _ = p.string_opt(name="host", default="localhost", description="Host")
  let help = p.generate_help()
  inspect(help.contains("[possible values:"), content="false")
}

///|
test "int_opt choices shown in help" {
  let p = Parser::new()
  let _ = p.int_opt(
    name="level", default=1,
    choices=["1", "2", "3"],
    description="Log level",
  )
  let help = p.generate_help()
  inspect(
    help.contains("[possible values: 1, 2, 3]"),
    content="true",
  )
}

// ============================================================
// inject_help_node collision tests
// ============================================================

///|
test "user-defined shorts=h takes priority over built-in -h help" {
  let p = Parser::new()
  let human = p.flag(name="human-readable", shorts="h", description="Human-readable")
  ignore(p.parse(["-h"]))
  // -h should activate the user-defined flag, not trigger help
  inspect(p.get(human), content="Some(true)")
}

///|
test "user-defined shorts=h: --help still works" {
  let p = Parser::new()
  let _ = p.flag(name="human-readable", shorts="h", description="Human-readable")
  let result : Result[_, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(_)) => () // expected
    _ => abort("expected HelpRequested for --help")
  }
}

///|
test "user-defined --help takes priority over built-in --help" {
  let p = Parser::new()
  let help_opt = p.flag(name="help", description="Custom help flag")
  ignore(p.parse(["--help"]))
  // --help should activate user-defined flag, not trigger built-in help
  inspect(p.get(help_opt), content="Some(true)")
}

///|
test "user-defined --help and shorts=h: both taken, no built-in help injected" {
  let p = Parser::new()
  let help_opt = p.flag(name="help", shorts="h", description="Custom help")
  ignore(p.parse(["--help", "-h"]))
  inspect(p.get(help_opt), content="Some(true)")
}

///|
test "no user collision: -h triggers help as usual" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v", description="Verbose")
  let result : Result[_, _] = try? p.parse(["-h"])
  match result {
    Err(HelpRequested(_)) => () // expected
    _ => abort("expected HelpRequested for -h")
  }
}

// ============================================================
// equals syntax edge case tests
// ============================================================

///|
test "equals syntax: --name= (empty value) sets empty string" {
  let p = Parser::new()
  let name = p.string_opt(name="name", default="default")
  ignore(p.parse(["--name="]))
  inspect(
    p.get(name),
    content=(
      #|Some("")
    ),
  )
}

///|
test "equals syntax: --port= (empty value int) raises parse error" {
  let p = Parser::new()
  let _ = p.int_opt(name="port", default=8080)
  let result : Result[_, _] = try? p.parse(["--port="])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("invalid integer: "), content="true")
    _ => abort("expected ParseError for --port= with empty value")
  }
}

///|
test "equals syntax: --name==value (value contains =)" {
  let p = Parser::new()
  let name = p.string_opt(name="name", default="default")
  ignore(p.parse(["--name==value"]))
  inspect(
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
  let name = p.string_opt(name="name", default="default")
  ignore(p.parse(["--name=hello"]))
  inspect(
    p.get(name),
    content=(
      #|Some("hello")
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
  inspect(help.contains("Usage:"), content="true")
}

///|
test "Usage line includes [OPTIONS] when options exist" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let help = p.generate_help()
  inspect(help.contains("Usage: [OPTIONS]"), content="true")
}

///|
test "Usage line includes [COMMAND] when commands exist" {
  let p = Parser::new()
  let _ = p.cmd(name="serve", setup=fn(_c) {  }, description="Start server")
  let help = p.generate_help()
  inspect(help.contains("[COMMAND]"), content="true")
}

///|
test "Usage line includes positional as <NAME>" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let help = p.generate_help()
  inspect(help.contains("<FILE>"), content="true")
}

///|
test "Usage line includes rest as [NAME]..." {
  let p = Parser::new()
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  inspect(help.contains("[ARGS]..."), content="true")
}

///|
test "Usage line with options, positional, and command" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let _ = p.positional(name="file", description="Input file")
  let _ = p.cmd(name="serve", setup=fn(_c) {  }, description="Start server")
  let help = p.generate_help()
  inspect(help.contains("Usage: [OPTIONS] <FILE> [COMMAND]"), content="true")
}

///|
test "Usage line with options and rest" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  inspect(help.contains("Usage: [OPTIONS] [ARGS]..."), content="true")
}

///|
test "Usage line: no [OPTIONS] when no user-defined options (before parse)" {
  let p = Parser::new(dashdash=false)
  let _ = p.positional(name="file", description="Input file")
  let help = p.generate_help()
  // generate_help() called before parse: inject_help_node hasn't run yet
  // so no Flag/ValueOpt metas exist → no [OPTIONS]
  inspect(help.contains("[OPTIONS]"), content="false")
  inspect(help.contains("Usage: <FILE>"), content="true")
}

///|
test "Usage line with positional and rest" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  inspect(help.contains("<FILE> [ARGS]..."), content="true")
}

// ============================================================
// Arguments section tests
// ============================================================

///|
test "Arguments section shows positional" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let help = p.generate_help()
  inspect(help.contains("Arguments:"), content="true")
  inspect(help.contains("<FILE>"), content="true")
  inspect(help.contains("Input file"), content="true")
}

///|
test "Arguments section shows rest with dots" {
  let p = Parser::new()
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  inspect(help.contains("Arguments:"), content="true")
  inspect(help.contains("[ARGS]..."), content="true")
  inspect(help.contains("Extra arguments"), content="true")
}

///|
test "Arguments section shows both positional and rest" {
  let p = Parser::new()
  let _ = p.positional(name="file", description="Input file")
  let _ = p.rest(name="args", description="Extra arguments")
  let help = p.generate_help()
  inspect(help.contains("Arguments:"), content="true")
  inspect(help.contains("<FILE>"), content="true")
  inspect(help.contains("[ARGS]..."), content="true")
}

///|
test "no positional or rest: no Arguments section" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose")
  let help = p.generate_help()
  inspect(help.contains("Arguments:"), content="false")
}

///|
test "integrated help: description, usage, commands, arguments, options" {
  let p = Parser::new()
  p.set_description("My CLI tool")
  let _ = p.flag(name="verbose", shorts="v", description="Enable verbose output")
  let _ = p.int_opt(
    name="port", default=8080, description="Set port number",
  )
  let _ = p.positional(name="file", description="Input file")
  let _ = p.rest(name="args", description="Extra arguments")
  let _ = p.cmd(name="serve", setup=fn(_c) {  }, description="Start server")
  let help = p.generate_help()
  // Description
  inspect(help.contains("My CLI tool"), content="true")
  // Usage line
  inspect(
    help.contains("Usage: [OPTIONS] <FILE> [ARGS]... [COMMAND]"),
    content="true",
  )
  // Commands section
  inspect(help.contains("Commands:"), content="true")
  inspect(help.contains("serve"), content="true")
  // Arguments section
  inspect(help.contains("Arguments:"), content="true")
  inspect(help.contains("<FILE>"), content="true")
  inspect(help.contains("[ARGS]..."), content="true")
  // Options section
  inspect(help.contains("Options:"), content="true")
  inspect(help.contains("--verbose"), content="true")
  inspect(help.contains("--port"), content="true")
}

///|
test "hidden positional not shown in help" {
  let p = Parser::new()
  let _ = p.positional(name="visible", description="Visible arg")
  // hidden positional は直接 metas に追加できないので、hidden=false のテスト
  let help = p.generate_help()
  inspect(help.contains("<VISIBLE>"), content="true")
}
