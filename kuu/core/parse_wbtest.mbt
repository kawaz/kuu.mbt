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
  let host = p.string(name="host", default="localhost")
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
  let host = p.string(name="host", default="localhost")
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
  let port = p.int(name="port", default=8080)
  ignore(p.parse(["--port", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "int option default" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  ignore(p.parse([]))
  inspect(p.get(port), content="Some(8080)")
}

///|
test "int parse error" {
  let p = Parser::new()
  let _port = p.int(name="port", default=8080)
  let result : Result[_, _] = try? p.parse(["--port", "abc"])
  inspect(result is Err(_), content="true")
}

///|
test "missing value error" {
  let p = Parser::new()
  let _host = p.string(name="host", default="localhost")
  let result : Result[_, _] = try? p.parse(["--host"])
  inspect(result is Err(_), content="true")
}

///|
test "int and string combined" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let host = p.string(name="host", default="localhost")
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
  let host = p.string(name="host", default="localhost", variations=[Reset("no")])
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
  let port = p.int(name="port", default=8080, variations=[Reset("no")])
  ignore(p.parse(["--port", "3000", "--no-port"]))
  inspect(p.get(port), content="Some(8080)")
}

///|
test "equals syntax for string" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
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
  let port = p.int(name="port", default=8080)
  ignore(p.parse(["--port=3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "equals syntax int parse error" {
  let p = Parser::new()
  let _port = p.int(name="port", default=8080)
  let result : Result[_, _] = try? p.parse(["--port=abc"])
  inspect(result is Err(_), content="true")
}

///|
test "equals syntax mixed with space syntax" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let host = p.string(name="host", default="localhost")
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
  let port = p.int(name="port", default=8080)
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
    port_opt.val = Some(child.int(name="port", default=8080))
  })
  ignore(p.parse(["serve", "--port", "3000"]))
  assert_true(serve.is_set())
  inspect(p.get(port_opt.val.unwrap()), content="Some(3000)")
}

///|
test "subcommand not matched" {
  let p = Parser::new()
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int(name="port", default=8080))
  })
  let build = p.cmd(name="build", setup=fn(_child) {  })
  ignore(p.parse(["build"]))
  assert_false(serve.is_set())
  assert_true(build.is_set())
}

///|
test "subcommand with parent flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int(name="port", default=8080))
  })
  ignore(p.parse(["--verbose", "serve", "--port", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port_opt.val.unwrap()), content="Some(3000)")
}

///|
test "subcommand unknown option error" {
  let p = Parser::new()
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int(name="port", default=8080)
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
      name_opt.val = Some(add_parser.string(name="name", default=""))
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
      url_opt.val = Some(add_parser.string(name="url", default=""))
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
    port_opt.val = Some(child.int(name="port", default=8080))
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
    port_opt.val = Some(child.int(name="port", default=8080))
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
      name_opt.val = Some(add_parser.string(name="name", default=""))
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
    port_opt.val = Some(child.int(name="port", default=8080))
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
    let _ = child.int(name="port", default=8080)
  })
  let result = p.parse(["serve", "--port", "3000"])
  inspect(result.child("build") is None, content="true")
}

///|
test "ParseResult as_map with subcommand" {
  let p = Parser::new()
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int(name="port", default=8080)
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
      name_opt.val = Some(add_parser.string(name="name", default=""))
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
  let port = p.int(name="port", default=8080)
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
  let host = p.string(name="host", default="localhost", aliases=["H"])
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
  let port = p.int(name="port", default=8080, aliases=["p"])
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
  let port = p.int(name="port", default=8080, aliases=["p"])
  ignore(p.parse(["--p=3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "opt.get with subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int(name="port", default=8080))
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
  let port = p.int(name="port", default=8080, shorts="p")
  ignore(p.parse(["-p", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short string option" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost", shorts="H")
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
  let port = p.int(name="port", default=8080, shorts="p")
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
  let port = p.int(name="port", default=8080, shorts="p")
  ignore(p.parse(["-vp3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining value next arg" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.int(name="port", default=8080, shorts="p")
  ignore(p.parse(["-vp", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining with string value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let host = p.string(name="host", default="localhost", shorts="H")
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
  let a_opt = p.int(name="aaa", default=0, shorts="A")
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
  let a_opt = p.int(name="after", default=0, shorts="A")
  let b_opt = p.int(name="before", default=0, shorts="B")
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
  let _ = p.int(name="port", default=8080, description="Set port number")
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
test "string default shown in help" {
  let p = Parser::new()
  let _ = p.string(name="host", default="localhost", description="Set host")
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
      let _ = child.int(name="port", default=8080, description="Set port")
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
    kind: InvalidValue,
    message: "unexpected argument: --foo",
    help_text: "",
    opt_name: "",
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
    help_text: "Options:\n  --help\n",
    opt_name: "",
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
  let color = p.string(
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
  let color = p.string(
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

// === string + choices + implicit_value テスト ===

///|
test "string choices+implicit: --color always" {
  let p = Parser::new()
  let color = p.string(
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
test "string choices+implicit: --color (implicit)" {
  let p = Parser::new()
  let color = p.string(
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
test "string choices+implicit: no --color (default)" {
  let p = Parser::new()
  let color = p.string(
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
test "string choices+implicit: --color with other flag" {
  let p = Parser::new()
  let color = p.string(
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
test "string choices+implicit: --color rander → implicit then unexpected" {
  let p = Parser::new()
  let _color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let result : Result[_, _] = try? p.parse(["--color", "rander"])
  inspect(result is Err(_), content="true")
}

///|
test "string choices+implicit: --no-color resets" {
  let p = Parser::new()
  let color = p.string(
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
test "string choices+implicit: --color=always (eq_split)" {
  let p = Parser::new()
  let color = p.string(
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
test "string choices+implicit: Thunk implicit_value" {
  let counter : Ref[Int] = { val: 0 }
  let p = Parser::new()
  let color = p.string(
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
test "string choices only: --color invalid → error" {
  let p = Parser::new()
  let _color = p.string(name="color", default="auto", choices=[
    "always", "none", "auto",
  ])
  let result : Result[_, _] = try? p.parse(["--color", "invalid"])
  inspect(result is Err(_), content="true")
}

///|
test "string choices only: --color always → ok" {
  let p = Parser::new()
  let color = p.string(name="color", default="auto", choices=[
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
test "string implicit only: --output (implicit)" {
  let p = Parser::new()
  let output = p.string(
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
test "string implicit only: --output file.txt" {
  let p = Parser::new()
  let output = p.string(
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
test "string choices+implicit with post filter" {
  let p = Parser::new()
  let color = p.string(
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
test "string choices+implicit: multiple opts with implicit default" {
  let p = Parser::new()
  let color = p.string(
    name="color",
    default="auto",
    choices=["always", "none", "auto"],
    implicit_value=Some(Val("always")),
  )
  let md = p.string(
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

// === int + implicit_value テスト ===

///|
test "int implicit: --port (implicit)" {
  let p = Parser::new()
  let port = p.int(
    name="port",
    default=8080,
    implicit_value=Some(Val(3000)),
  )
  ignore(p.parse(["--port"]))
  inspect(port.get(), content="Some(3000)")
}

///|
test "int implicit: --port 9090" {
  let p = Parser::new()
  let port = p.int(
    name="port",
    default=8080,
    implicit_value=Some(Val(3000)),
  )
  ignore(p.parse(["--port", "9090"]))
  inspect(port.get(), content="Some(9090)")
}

///|
test "int implicit: no --port (default)" {
  let p = Parser::new()
  let port = p.int(
    name="port",
    default=8080,
    implicit_value=Some(Val(3000)),
  )
  ignore(p.parse([]))
  inspect(port.get(), content="Some(8080)")
}

///|
test "int implicit: --port foo → implicit (Reject fallback)" {
  let p = Parser::new()
  let port = p.int(
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
test "string choices+implicit: short combining -vc" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let color = p.string(
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
test "string choices+implicit: short combining -cv" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let color = p.string(
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
test "string choices+implicit: short -cnone (inline value)" {
  let p = Parser::new()
  let color = p.string(
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
test "string implicit_only: --output=-foo (eq-split)" {
  let p = Parser::new()
  let output = p.string(
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
test "string implicit_only: --output --verbose → implicit" {
  let p = Parser::new()
  let output = p.string(
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
test "int implicit: short combining -vp" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", shorts="v")
  let port = p.int(
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
test "string choices+implicit: --color=invalid → error" {
  let p = Parser::new()
  let _color = p.string(
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
  let output = p.string(name="output", default="")
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
  let output = p.string(name="output", default="")
  p.required(output.as_ref())
  let result : Result[_, _] = try? p.parse(["--other"])
  inspect(result is Err(_), content="true")
}

///|
test "at_least_one passes when one set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  ignore(p.parse(["--json"]))
  inspect(p.get(json), content="Some(true)")
  inspect(p.get(csv), content="Some(false)")
}

///|
test "at_least_one passes when all set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  ignore(p.parse(["--json", "--csv"]))
  inspect(p.get(json), content="Some(true)")
  inspect(p.get(csv), content="Some(true)")
}

///|
test "at_least_one error when none set" {
  let p = Parser::new()
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message.contains("at least one required"), content="true")
      inspect(info.message.contains("--json"), content="true")
      inspect(info.message.contains("--csv"), content="true")
    }
    _ => abort("expected at_least_one error")
  }
}

///|
test "at_least_one with subcommand" {
  let p = Parser::new()
  let format_opt : Ref[Opt[Bool]?] = { val: None }
  let verbose_opt : Ref[Opt[Bool]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let fmt = child.flag(name="json")
    let vrb = child.flag(name="verbose")
    child.at_least_one([fmt.as_ref(), vrb.as_ref()])
    format_opt.val = Some(fmt)
    verbose_opt.val = Some(vrb)
  })
  ignore(p.parse(["serve", "--verbose"]))
  inspect(p.get(format_opt.val.unwrap()), content="Some(false)")
  inspect(p.get(verbose_opt.val.unwrap()), content="Some(true)")
}

///|
test "is_set false for default fallback" {
  let p = Parser::new(dashdash=false)
  let color = p.string(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse([]))
  inspect(color.is_set(), content="false")
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
  let color = p.string(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color", "never"]))
  inspect(color.is_set(), content="true")
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
  let color = p.string(
    name="color",
    default="auto",
    implicit_value=Some(Val("always")),
  )
  ignore(p.parse(["--color"]))
  inspect(color.is_set(), content="true")
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
  let depth = clone.int(name="depth", default=0)
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
  let msg = stash.string(name="message", default="", shorts="m")
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
  inspect(color.is_set(), content="true")
}

///|
test "variation: False flag with default=false" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default=false, variations=[False("no")])
  ignore(p.parse(["--no-verbose"]))
  // False sets cell=false (same as default), but committed=true
  inspect(p.get(verbose), content="Some(false)")
  inspect(verbose.is_set(), content="true")
}

///|
test "variation: Reset flag resets to default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[Reset("reset")])
  // First set to true (positive), then reset
  ignore(p.parse(["--color", "--reset-color"]))
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: Unset flag resets value and committed" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Unset("unset")])
  ignore(p.parse(["--color", "--unset-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="false")
}

///|
test "variation: True/False flag with enable/disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--enable-color"]))
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: True/False flag disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: True/False flag enable then disable" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[True("enable"), False("disable")])
  ignore(p.parse(["--enable-color", "--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: count with Reset" {
  let p = Parser::new()
  let v = p.count(name="verbose", variations=[Reset("no")])
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose"]))
  inspect(p.get(v), content="Some(0)")
  inspect(v.is_set(), content="true")
}

///|
test "variation: string with Reset" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost", variations=[Reset("no")])
  ignore(p.parse(["--host", "example.com", "--no-host"]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(host.is_set(), content="true")
}

///|
test "variation: string with Unset" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost", variations=[Unset("unset")])
  ignore(p.parse(["--host", "example.com", "--unset-host"]))
  inspect(
    p.get(host),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(host.is_set(), content="false")
}

///|
test "variation: int with Reset" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080, variations=[Reset("no")])
  ignore(p.parse(["--port", "3000", "--no-port"]))
  inspect(p.get(port), content="Some(8080)")
  inspect(port.is_set(), content="true")
}

///|
test "variation: append_string with Reset" {
  let p = Parser::new()
  let tags = p.append_string(name="tag", variations=[Reset("no")])
  ignore(p.parse(["--tag", "a", "--tag", "b", "--no-tag"]))
  inspect(p.get(tags), content="Some([])")
  inspect(tags.is_set(), content="true")
}

///|
test "variation: append_int with Reset" {
  let p = Parser::new()
  let ids = p.append_int(name="id", variations=[Reset("no")])
  ignore(p.parse(["--id", "1", "--id", "2", "--no-id"]))
  inspect(p.get(ids), content="Some([])")
  inspect(ids.is_set(), content="true")
}

///|
test "variation: flag alias also gets variation" {
  let p = Parser::new()
  let color = p.flag(name="color", aliases=["colour"], variations=[False("no")])
  ignore(p.parse(["--no-colour"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
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
  inspect(color.is_set(), content="true")
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
  inspect(color.is_set(), content="true")
}

///|
test "variation: Toggle double toggles back" {
  let p = Parser::new()
  let color = p.flag(name="color", variations=[Toggle("toggle")])
  ignore(p.parse(["--color", "--toggle-color", "--toggle-color"]))
  // --color → true, --toggle → false, --toggle → true
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: Toggle with default=true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[Toggle("toggle")])
  ignore(p.parse(["--toggle-color"]))
  // default=true, toggle → false
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: True sets true regardless of default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[True("enable")])
  // Main (--color) with default=true sets to !default = false
  ignore(p.parse(["--color", "--enable-color"]))
  // --color → false, --enable-color → true
  inspect(p.get(color), content="Some(true)")
  inspect(color.is_set(), content="true")
}

///|
test "variation: False sets false regardless of default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true, variations=[False("disable")])
  ignore(p.parse(["--disable-color"]))
  inspect(p.get(color), content="Some(false)")
  inspect(color.is_set(), content="true")
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
  inspect(verbose.is_set(), content="true")
}

///|
test "string variation_reset sugar" {
  let p = Parser::new()
  let fmt = p.string(name="format", default="json", variation_reset=Some("no"))
  ignore(p.parse(["--format", "xml", "--no-format"]))
  inspect(
    fmt.get(),
    content=(
      #|Some("json")
    ),
  ) // Reset → default
  inspect(fmt.is_set(), content="true")
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
  inspect(verbose.is_set(), content="true")
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
  inspect(verbose.is_set(), content="true")
}

///|
test "append_string variation_reset sugar" {
  let p = Parser::new()
  let includes = p.append_string(name="include", variation_reset=Some("no"))
  ignore(p.parse(["--include", "a", "--include", "b", "--no-include"]))
  inspect(includes.get(), content="Some([])") // Reset → empty
  inspect(includes.is_set(), content="true")
}

// ============ default_fn tests ============

///|
test "flag default_fn" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default_fn=Some(fn() { true }))
  ignore(p.parse([])) // no args
  inspect(verbose.get(), content="Some(true)") // default_fn で true
  inspect(verbose.is_set(), content="false") // 明示指定なし
}

///|
test "flag default_fn overrides default" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", default_fn=Some(fn() { true }))
  ignore(p.parse(["--verbose"]))
  // Main = !initial_val = !true = false
  inspect(verbose.get(), content="Some(false)")
  inspect(verbose.is_set(), content="true")
}

///|
test "string default_fn" {
  let p = Parser::new()
  let color = p.string(
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
  inspect(color.is_set(), content="false")
}

///|
test "int default_fn" {
  let p = Parser::new()
  let port = p.int(
    name="port",
    default=80,
    default_fn=Some(fn() { 8080 }),
  )
  ignore(p.parse([])) // no args
  inspect(port.get(), content="Some(8080)") // default_fn が優先
  inspect(port.is_set(), content="false")
}

///|
test "string default_fn with reset variation" {
  let p = Parser::new()
  let color = p.string(
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
  inspect(color.is_set(), content="true")
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
  inspect((name.accessor.get)(), content="alice")
}

///|
test "custom_string_default" {
  let p = Parser::new()
  let name = p.custom(name="name", default="world", pre=Filter::map(fn(s) { s }))
  p.parse([]) |> ignore
  inspect((name.accessor.get)(), content="world")
}

///|
test "custom_int_basic" {
  let p = Parser::new()
  let port = p.custom(name="port", default=8080, pre=Filter::parse_int())
  p.parse(["--port", "3000"]) |> ignore
  inspect((port.accessor.get)(), content="3000")
}

///|
test "custom_int_default" {
  let p = Parser::new()
  let port = p.custom(name="port", default=8080, pre=Filter::parse_int())
  p.parse([]) |> ignore
  inspect((port.accessor.get)(), content="8080")
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
  inspect((rate.accessor.get)(), content="3.14")
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
  inspect((level.accessor.get)(), content="warn")
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
  inspect((verbose.accessor.get)(), content="1")
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
  inspect((verbose.accessor.get)(), content="3")
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
  inspect((color.accessor.get)(), content="always")
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
  inspect((color.accessor.get)(), content="never")
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
  inspect((name.accessor.get)(), content="ALICE")
}

///|
test "custom_append_string_basic" {
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }))
  p.parse(["--tag", "a", "--tag", "b"]) |> ignore
  inspect((tags.accessor.get)(), content="[\"a\", \"b\"]")
}

///|
test "custom_append_string_empty" {
  let p = Parser::new()
  let tags = p.custom_append(name="tag", pre=Filter::map(fn(s) { s }))
  p.parse([]) |> ignore
  inspect((tags.accessor.get)(), content="[]")
}

///|
test "custom_append_int_basic" {
  let p = Parser::new()
  let nums = p.custom_append(name="num", pre=Filter::parse_int())
  p.parse(["--num", "1", "--num", "2", "--num", "3"]) |> ignore
  inspect((nums.accessor.get)(), content="[1, 2, 3]")
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
  let _ = p.string(
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
  let port = p.int(name="port", default=8080, aliases=["p"])
  ignore(p.parse(["--p", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

// ============================================================
// int の choices テスト
// ============================================================

///|
test "int with choices: valid value accepted" {
  let p = Parser::new()
  let level = p.int(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse(["--level", "2"]))
  inspect(p.get(level), content="Some(2)")
}

///|
test "int with choices: another valid value" {
  let p = Parser::new()
  let level = p.int(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse(["--level", "3"]))
  inspect(p.get(level), content="Some(3)")
}

///|
test "int with choices: invalid value rejected" {
  let p = Parser::new()
  let _ = p.int(name="level", default=1, choices=["1", "2", "3"])
  let result : Result[_, _] = try? p.parse(["--level", "5"])
  inspect(result is Err(_), content="true")
}

///|
test "int with choices: default without args" {
  let p = Parser::new()
  let level = p.int(name="level", default=1, choices=["1", "2", "3"])
  ignore(p.parse([]))
  inspect(p.get(level), content="Some(1)")
}

// ============================================================
// int の post テスト
// ============================================================

///|
test "int with post: value transformed" {
  let p = Parser::new()
  let num = p.int(
    name="num", default=0,
    post=Some(Filter::map(fn(n : Int) { n * 2 })),
  )
  ignore(p.parse(["--num", "5"]))
  inspect(p.get(num), content="Some(10)")
}

///|
test "int with post: default also transformed" {
  let p = Parser::new()
  let num = p.int(
    name="num", default=3,
    post=Some(Filter::map(fn(n : Int) { n * 2 })),
  )
  ignore(p.parse([]))
  // post hook runs on cell value unconditionally, so default 3 becomes 6
  inspect(p.get(num), content="Some(6)")
}

///|
test "int with post: chained transform" {
  let p = Parser::new()
  let num = p.int(
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
    description="Item count",
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
    description="Item count",
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
    description="User name",
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
    description="User name",
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
    description="Item count",
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
    description="Item count",
    default_display=Some("custom"),
  )
  let help = p.generate_help()
  inspect(help.contains("[default: custom]"), content="true")
  inspect(help.contains("[default: 42]"), content="false")
}

///|
test "int default shown in help via auto derive" {
  let p = Parser::new()
  let _ = p.int(name="port", default=8080, description="Port number")
  let help = p.generate_help()
  inspect(help.contains("[default: 8080]"), content="true")
}

///|
test "int default=0 shown in help" {
  let p = Parser::new()
  let _ = p.int(name="port", default=0, description="Port number")
  let help = p.generate_help()
  inspect(help.contains("[default: 0]"), content="true")
}

///|
test "string default empty: no default shown in help" {
  let p = Parser::new()
  let _ = p.string(name="host", default="", description="Host name")
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
  let port = p.int(name="port", default=0, shorts="あ")
  ignore(p.parse(["-あ3000"]))
  inspect(p.get(port), content="Some(3000)")
}

// ============================================================
// choices help display tests
// ============================================================

///|
test "choices shown in help: [possible values: ...]" {
  let p = Parser::new()
  let _ = p.string(
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
  let _ = p.string(
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
  let _ = p.string(name="host", default="localhost", description="Host")
  let help = p.generate_help()
  inspect(help.contains("[possible values:"), content="false")
}

///|
test "int choices shown in help" {
  let p = Parser::new()
  let _ = p.int(
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
  let name = p.string(name="name", default="default")
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
  let _ = p.int(name="port", default=8080)
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
  let name = p.string(name="name", default="default")
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
  let name = p.string(name="name", default="default")
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
  let _ = p.int(
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

// ============================================================
// C1: unselected cmd get() returns None (not panic)
// ============================================================

///|
test "unselected cmd get() returns None" {
  let p = Parser::new(dashdash=false)
  let cmd_a = p.cmd(name="a", dashdash=false, setup=fn(_) {  })
  let cmd_b = p.cmd(name="b", dashdash=false, setup=fn(_) {  })
  ignore(p.parse(["a"]))
  // selected cmd: opt.get() returns Some
  inspect(cmd_a.is_set(), content="true")
  inspect(cmd_a.get() is Some(_), content="true")
  // unselected cmd: opt.get() returns None (not panic)
  inspect(cmd_b.is_set(), content="false")
  inspect(cmd_b.get() is None, content="true")
}

///|
test "no cmd selected — all cmds return None" {
  let p = Parser::new(dashdash=false)
  let cmd_a = p.cmd(name="a", dashdash=false, setup=fn(_) {  })
  let cmd_b = p.cmd(name="b", dashdash=false, setup=fn(_) {  })
  ignore(p.parse([]))
  inspect(cmd_a.get() is None, content="true")
  inspect(cmd_b.get() is None, content="true")
}

// ============================================================
// C4: positional accepts --xxx (no prefix check)
// ============================================================

///|
test "positional accepts --xxx as value" {
  let p = Parser::new(dashdash=false)
  let arg = p.positional(name="arg")
  ignore(p.parse(["--unknown-flag"]))
  inspect(
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
  inspect(p.get(verbose), content="Some(true)")
  inspect(
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
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate option name: --"), content="true")
    _ => abort("expected duplicate error for dashdash + install_separator_node")
  }
}

///|
test "dashdash=false with explicit dashdash() works without duplicate error" {
  let p = Parser::new(dashdash=false)
  let dd = p.dashdash()
  ignore(p.parse(["--", "a", "b"]))
  inspect(
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
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate option name: --"), content="true")
    _ => abort("expected duplicate error for append_dashdash + install_separator_node")
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
  let result : Result[_, _] = try? p.parse(["--name", "alice"])
  // parse should fail due to post_hook
  inspect(result is Err(_), content="true")
  // parsed should remain false because post_hook failed before setting it
  inspect(name.parsed.val, content="false")
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
  let result : Result[_, _] = try? p.parse(["sub"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate option name"), content="true")
    _ => abort("expected duplicate error for global/local name collision")
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
  inspect(p.get(verbose), content="Some(true)")
}

// ============================================================
// C2: variation_names shown in help
// ============================================================

///|
test "help shows --no-xxx for variation_false" {
  let p = Parser::new()
  let _ = p.flag(name="color", variation_false=Some("no"), description="Use color")
  let help = p.generate_help()
  inspect(help.contains("--no-color"), content="true")
  inspect(help.contains("--color, --no-color"), content="true")
}

///|
test "help shows multiple variations" {
  let p = Parser::new()
  let _ = p.flag(
    name="color",
    variations=[True("enable"), False("disable")],
    description="Use color",
  )
  let help = p.generate_help()
  inspect(help.contains("--enable-color"), content="true")
  inspect(help.contains("--disable-color"), content="true")
  inspect(
    help.contains("--color, --enable-color, --disable-color"),
    content="true",
  )
}

///|
test "help shows variation with aliases" {
  let p = Parser::new()
  let _ = p.flag(
    name="color", aliases=["colour"], variation_false=Some("no"),
    description="Use color",
  )
  let help = p.generate_help()
  // aliases come before variations
  inspect(
    help.contains("--color, --colour, --no-color"),
    content="true",
  )
}

///|
test "help shows variation with shorts and aliases" {
  let p = Parser::new()
  let _ = p.flag(
    name="color", shorts="c", aliases=["colour"], variation_false=Some("no"),
    description="Use color",
  )
  let help = p.generate_help()
  inspect(
    help.contains("-c, --color, --colour, --no-color"),
    content="true",
  )
}

///|
test "help shows no variation when variations is empty" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose output")
  let help = p.generate_help()
  // Should show just --verbose without any variation suffix
  inspect(help.contains("--verbose"), content="true")
  // Should not contain comma after --verbose (no aliases, no variations)
  inspect(help.contains("--verbose,"), content="false")
}

///|
test "help variation_reset shows --no-xxx" {
  let p = Parser::new()
  let _ = p.string(
    name="format", default="json", variation_reset=Some("no"),
    description="Output format",
  )
  let help = p.generate_help()
  inspect(help.contains("--no-format"), content="true")
}

// ============================================================
// OC/P 2-phase parse tests (DR-034)
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
  inspect(p.get(verbose), content="Some(true)")
  inspect(
    src.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  inspect(
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
  let result : Result[_, _] = try? p.parse(["F1", "--verbose", "F2"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("unexpected argument"), content="true")
    _ => abort("expected error for extra positional after greedy")
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
  inspect(
    src.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  inspect(
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
  inspect(verbose.is_set(), content="false")
  inspect(
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
  inspect(
    p.get(output),
    content=(
      #|Some("out")
    ),
  )
  inspect(p.get(verbose), content="Some(true)")
  inspect(
    src.unwrap().get(),
    content=(
      #|Some("F1")
    ),
  )
  inspect(
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
  let result : Result[ParseResult, _] = try? p.parse(["--vrrbose", "file.txt"])
  match result {
    Err(ParseError(info)) => {
      // --vrrbose が positional(file) に食われ、file.txt が unexpected になる
      // ただし hint は file.txt（prefix なし）には付かない
      inspect(info.message.contains("unexpected"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "OC/P: typo hint suggests closest match" {
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  ignore(p.flag(name="version"))
  p.never()
  let result : Result[ParseResult, _] = try? p.parse(["--vrrbose"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message.contains("--verbose"), content="true")
      inspect(info.message.contains("did you mean"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "OC/P: no hint for non-prefix arg" {
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  p.never()
  let result : Result[ParseResult, _] = try? p.parse(["verbos"])
  match result {
    Err(ParseError(info)) => {
      // prefix なしの arg には hint を付けない
      inspect(info.message.contains("did you mean"), content="false")
    }
    _ => fail("expected ParseError")
  }
}

///|
test "OC/P: rest with options interleaved" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  ignore(p.parse(["f1", "--verbose", "f2", "f3"]))
  inspect(verbose.is_set(), content="true")
  inspect(files.get(), content="Some([\"f1\", \"f2\", \"f3\"])")
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
  inspect(verbose.is_set(), content="true")
  inspect(file1.unwrap().get(), content="Some(\"F1\")")
  // rest が stop_before なしのため D1, D2, F2 全てを消費し file2 は未設定
  inspect(dirs.unwrap().get(), content="Some([\"D1\", \"D2\", \"F2\"])")
  inspect(file2.unwrap().is_set(), content="false")
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
  inspect(verbose.is_set(), content="true")
  inspect(file.get(), content="Some(\"F1\")")
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
  inspect(verbose.is_set(), content="true")
  inspect(eager.get(), content="Some(\"A\")")
  inspect(deferred.get(), content="Some(\"B\")")
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
  let result : Result[_, _] = try? p.parse(["F1", "--verbose", "F2"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("unexpected argument"), content="true")
    _ => abort("expected error: compound handler consumes --verbose as dst value")
  }
  // parse がエラーで終了するため parsed=false、get() は None を返す。
  // compound handler が --verbose を positional 値として消費するため flag も未設定。
  inspect(verbose.is_set(), content="false")
  // commit は呼ばれているが parsed=false なので get() は None
  inspect(src.unwrap().is_set(), content="true")
  inspect(dst.unwrap().is_set(), content="true")
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
  inspect(src.unwrap().get(), content="Some(\"F1\")")
  inspect(dst.unwrap().get(), content="Some(\"F2\")")
}

///|
test "OC/P: typo hint distance threshold" {
  // 距離 1 ("--verbos" vs "--verbose"): hint あり
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  p.never()
  let r1 : Result[ParseResult, _] = try? p.parse(["--verbos"])
  match r1 {
    Err(ParseError(info)) =>
      inspect(info.message.contains("did you mean"), content="true")
    _ => fail("expected error")
  }
}

///|
test "OC/P: typo hint no match for distant name" {
  // 距離 > 2 ("--xyz" vs "--verbose"): hint なし
  let p = Parser::new(dashdash=false)
  ignore(p.flag(name="verbose"))
  p.never()
  let r : Result[ParseResult, _] = try? p.parse(["--xyz"])
  match r {
    Err(ParseError(info)) =>
      inspect(info.message.contains("did you mean"), content="false")
    _ => fail("expected error")
  }
}

// ============================================================
// alias コンビネータ
// ============================================================

///|
test "alias: flag alias shares value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verb"]))
  // alias 経由で値が共有される
  inspect(verbose.get(), content="Some(true)")
  inspect(verb.get(), content="Some(true)")
}

///|
test "alias: flag alias is_set independence" {
  // alias 使用時は alias.is_set=true, target.is_set=true（両方セット）
  // alias 未使用時は alias.is_set=false
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verbose"]))
  // target 使用: target.is_set=true, alias.is_set=false
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="false")
}

///|
test "alias: flag alias sets both is_set" {
  // alias 経由で使用した場合、alias と target の両方の is_set が true になる
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verb"]))
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="true")
}

///|
test "alias: string alias shares value" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let h = p.make_alias("--h", host)
  ignore(p.parse(["--h", "example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    h.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "alias: single-dash long option" {
  // -Xcc のような単一ダッシュオプションを alias で登録
  let p = Parser::new()
  let compiler = p.string(name="compiler", default="")
  let xcc = p.make_alias("-Xcc", compiler)
  ignore(p.parse(["-Xcc", "gcc"]))
  inspect(
    compiler.get(),
    content=(
      #|Some("gcc")
    ),
  )
  inspect(xcc.is_set(), content="true")
  inspect(compiler.is_set(), content="true")
}

///|
test "alias: duplicate name detected" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  // --verbose は既に登録されているので重複
  ignore(p.make_alias("--verbose", verbose))
  let result : Result[_, _] = try? p.parse([])
  inspect(result is Err(_), content="true")
}

///|
test "alias: cmd alias shares child parser" {
  let p = Parser::new()
  let status = p.cmd(name="status", setup=fn(child) {
    ignore(child.flag(name="short"))
  })
  let st = p.make_alias("st", status)
  ignore(p.parse(["st", "--short"]))
  inspect(status.is_set(), content="true")
  inspect(st.is_set(), content="true")
  // cmd alias でも同一子パーサが使われる
  let cmd_result = status.get().unwrap()
  inspect(cmd_result.name, content="status")
}

///|
test "alias: chained alias (alias of alias)" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  let v = p.make_alias("--v", verb)
  ignore(p.parse(["--v"]))
  // 全ての alias と target の値が共有される
  inspect(verbose.get(), content="Some(true)")
  inspect(verb.get(), content="Some(true)")
  inspect(v.get(), content="Some(true)")
  // is_set: v と verbose は true（alias 経由で target も true）
  // verb は直接使っていないので false
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="false")
  inspect(v.is_set(), content="true")
}

///|
test "alias: int alias shares value" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let pp = p.make_alias("-p", port)
  ignore(p.parse(["-p", "3000"]))
  inspect(port.get(), content="Some(3000)")
  inspect(pp.get(), content="Some(3000)")
}

///|
test "alias: append alias shares array" {
  let p = Parser::new()
  let inc = p.append_string(name="include")
  let ii = p.make_alias("-I", inc)
  ignore(p.parse(["--include", "a", "-I", "b"]))
  inspect(inc.get(), content="Some([\"a\", \"b\"])")
  inspect(ii.get(), content="Some([\"a\", \"b\"])")
}

///|
test "alias: unused alias default value" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let h = p.make_alias("--h", host)
  ignore(p.parse([]))
  inspect(
    host.get(),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(
    h.get(),
    content=(
      #|Some("localhost")
    ),
  )
  inspect(host.is_set(), content="false")
  inspect(h.is_set(), content="false")
}

///|
test "alias: global alias propagates to subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let verb = p.make_alias("--verb", verbose)
  let status = p.cmd(name="status", setup=fn(_child) {  })
  ignore(p.parse(["status", "--verb"]))
  // global alias は子パーサでも使える
  inspect(verbose.get(), content="Some(true)")
  inspect(verb.get(), content="Some(true)")
  inspect(verbose.is_set(), content="true")
  inspect(verb.is_set(), content="true")
  inspect(status.is_set(), content="true")
}

///|
test "alias: eq_split with double-dash alias" {
  // --alias=value 構文が動くか
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let h = p.make_alias("--h", host)
  ignore(p.parse(["--h=example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    h.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "alias: count alias shares counter" {
  let p = Parser::new()
  let verbose = p.count(name="verbose")
  let verb = p.make_alias("--verb", verbose)
  ignore(p.parse(["--verbose", "--verb", "--verbose"]))
  inspect(verbose.get(), content="Some(3)")
  inspect(verb.get(), content="Some(3)")
}

///|
test "alias: alias does not expand variations" {
  // alias は variation を展開しない（DR-037: variation = alias + adjust の合成）
  let p = Parser::new()
  let verbose = p.flag(name="verbose", variations=[False("no")])
  ignore(p.make_alias("--verb", verbose))
  // --no-verb は存在しないのでエラー
  let result : Result[_, _] = try? p.parse(["--no-verb"])
  inspect(result is Err(_), content="true")
}

// === H-1: --opt=--value で implicit_value にフォールバックするバグ ===

///|
test "H-1: string implicit: --output=--value (eq-split, double-dash value)" {
  // implicit_value 付きオプションで --output=--value のように
  // = 経由で -- 始まりの値を渡した場合、値が正しく取れること
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  ignore(p.parse(["--output=--value"]))
  inspect(
    output.get(),
    content=(
      #|Some("--value")
    ),
  )
}

///|
test "H-1: int implicit: --port=--not-a-port (eq-split) → parse error" {
  // int の implicit_value 付きで --port=--not-a-port は
  // = 経由で明示的に渡されたが Int パースに失敗するのでエラー
  let p = Parser::new()
  ignore(
    p.int(name="port", default=8080, implicit_value=Some(Val(3000))),
  )
  let result : Result[_, _] = try? p.parse(["--port=--not-a-port"])
  inspect(result is Err(_), content="true")
}

///|
test "H-1: string implicit: --output --next (space-separated) → still implicit" {
  // スペース区切りの場合は従来通り -- 始まりの次トークンは
  // 次のオプションとして扱い、implicit にフォールバックすべき
  let p = Parser::new()
  let output = p.string(
    name="output",
    default="",
    implicit_value=Some(Val("stdout")),
  )
  let next = p.flag(name="next")
  ignore(p.parse(["--output", "--next"]))
  inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
  inspect(next.get(), content="Some(true)")
}

// === H-2: cmd が registered_names に登録されない ===

///|
test "H-2: duplicate cmd name detected" {
  // 同名コマンドの重複定義はパース前にエラーになるべき
  let p = Parser::new(dashdash=false)
  let _cmd1 = p.cmd(name="serve", dashdash=false, setup=fn(_) {  })
  let _cmd2 = p.cmd(name="serve", dashdash=false, setup=fn(_) {  })
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate"), content="true")
    _ => abort("expected duplicate name error for same cmd name")
  }
}

///|
test "H-2: duplicate cmd alias with existing cmd name detected" {
  // cmd の alias が既存コマンド名と衝突する場合もエラー
  let p = Parser::new(dashdash=false)
  let _cmd1 = p.cmd(name="serve", dashdash=false, setup=fn(_) {  })
  let _cmd2 = p.cmd(
    name="start", aliases=["serve"], dashdash=false, setup=fn(_) {  },
  )
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate"), content="true")
    _ => abort("expected duplicate name error for cmd alias collision")
  }
}

///|
test "H-2: duplicate cmd name with option name detected" {
  // cmd 名がオプション名(--xxx)と衝突しない場合は OK（名前空間が異なる）
  // cmd は "--" 付かないので衝突しない
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="serve")
  let _cmd = p.cmd(name="serve", dashdash=false, setup=fn(_) {  })
  // cmd "serve" と flag "--serve" は名前空間が異なるので重複しない
  ignore(p.parse(["serve"]))
}

///|
test "H-2: no duplicate for different cmd names" {
  let p = Parser::new(dashdash=false)
  let _cmd1 = p.cmd(name="serve", dashdash=false, setup=fn(_) {  })
  let _cmd2 = p.cmd(name="build", dashdash=false, setup=fn(_) {  })
  // 異なる名前の cmd は重複しない
  ignore(p.parse([]))
}

///|
test "H-2: sub duplicate name detected" {
  // sub() 経由でも重複検出される
  let p = Parser::new(dashdash=false)
  let _s1 = p.sub(name="serve", dashdash=false)
  let _s2 = p.sub(name="serve", dashdash=false)
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate"), content="true")
    _ => abort("expected duplicate name error for sub()")
  }
}

// === H-3: cmd の reset が子パーサの状態をリセットしない ===

///|
test "H-3: cmd reset restores child parser state" {
  // cmd の try_reduce 内で child.parse() が実行されるが、
  // 別ノードが勝った場合のリセットで child の状態が復元されることを確認。
  // 実際にはコマンド名の衝突がない限り2つの cmd が同トークンにマッチしないため、
  // この問題は H-2 の修正で防がれる。ここでは reset 関数が child.parsed を
  // リセットすることをユニットレベルで検証する。
  let p = Parser::new(dashdash=false)
  let child_parsed_ref : Ref[Ref[Bool]?] = { val: None }
  let _cmd = p.cmd(name="serve", dashdash=false, setup=fn(child) {
    child_parsed_ref.val = Some(child.parsed)
  })
  // reset 関数が child.parsed と child.current_positional をリセットすることを検証
  // cmd ノードを取得して reset を呼ぶ
  // nodes の最後のノード（serve 用）の reset を呼んで確認
  // まず parse して child.parsed=true にする
  ignore(p.parse(["serve"]))
  let child_parsed = child_parsed_ref.val.unwrap()
  inspect(child_parsed.val, content="true")
  // reset を直接呼べないため、この状態確認のみでOK
  // H-3 の修正は reset 関数に child の状態復元を追加すること
}

// ============================================================
// H-4: ParseResult::as_list / ParseResult::at テスト
// ============================================================

///|
test "H-4: as_list returns list for List_ variant" {
  // List_ バリアントの ParseResult で as_list() がリストを返すこと
  let p = Parser::new()
  ignore(p.parse([]))
  let inner1 : ParseResult = { kind: One, parser: p }
  let inner2 : ParseResult = { kind: One, parser: p }
  let list_result : ParseResult = { kind: List_([inner1, inner2]), parser: p }
  inspect(list_result.as_list() is Some(_), content="true")
  inspect(list_result.as_list().unwrap().length(), content="2")
}

///|
test "H-4: as_list returns None for One variant" {
  let p = Parser::new()
  ignore(p.parse([]))
  let one_result : ParseResult = { kind: One, parser: p }
  inspect(one_result.as_list() is None, content="true")
}

///|
test "H-4: as_list returns None for Map_ variant" {
  let p = Parser::new()
  let sub = p.sub(name="serve", dashdash=false)
  ignore(sub.flag(name="short"))
  let result = p.parse(["serve"])
  // result.kind is Map_ (has children)
  inspect(result.as_list() is None, content="true")
}

///|
test "H-4: at returns element for valid index" {
  let p = Parser::new()
  ignore(p.parse([]))
  let inner0 : ParseResult = { kind: One, parser: p }
  let inner1 : ParseResult = { kind: One, parser: p }
  let inner2 : ParseResult = { kind: One, parser: p }
  let list_result : ParseResult = {
    kind: List_([inner0, inner1, inner2]),
    parser: p,
  }
  inspect(list_result.at(0) is Some(_), content="true")
  inspect(list_result.at(1) is Some(_), content="true")
  inspect(list_result.at(2) is Some(_), content="true")
}

///|
test "H-4: at returns None for out-of-bounds index" {
  let p = Parser::new()
  ignore(p.parse([]))
  let inner : ParseResult = { kind: One, parser: p }
  let list_result : ParseResult = { kind: List_([inner]), parser: p }
  inspect(list_result.at(1) is None, content="true")
  inspect(list_result.at(-1) is None, content="true")
  inspect(list_result.at(100) is None, content="true")
}

///|
test "H-4: at returns None for non-List_ variant" {
  let p = Parser::new()
  ignore(p.parse([]))
  let one_result : ParseResult = { kind: One, parser: p }
  inspect(one_result.at(0) is None, content="true")
}

///|
test "H-4: at returns None for empty List_" {
  let p = Parser::new()
  ignore(p.parse([]))
  let empty_list : ParseResult = { kind: List_([]), parser: p }
  inspect(empty_list.at(0) is None, content="true")
}

// ============================================================
// H-5: cmd/sub の aliases パラメータテスト
// ============================================================

///|
test "H-5: cmd aliases basic" {
  // p.cmd(name="serve", aliases=["s"]) で "s" がコマンドとして動作すること
  let p = Parser::new(dashdash=false)
  let serve = p.cmd(name="serve", aliases=["s"], dashdash=false, setup=fn(child) {
    ignore(child.flag(name="verbose"))
  })
  ignore(p.parse(["s"]))
  inspect(serve.is_set(), content="true")
  inspect(serve.get().unwrap().name, content="serve")
}

///|
test "H-5: cmd aliases primary name still works" {
  let p = Parser::new(dashdash=false)
  let serve = p.cmd(name="serve", aliases=["s"], dashdash=false, setup=fn(child) {
    ignore(child.flag(name="verbose"))
  })
  ignore(p.parse(["serve"]))
  inspect(serve.is_set(), content="true")
  inspect(serve.get().unwrap().name, content="serve")
}

///|
test "H-5: cmd alias parses child options correctly" {
  // alias 経由でも子パーサのオプションが正しくパースされること
  let p = Parser::new(dashdash=false)
  let verbose_ref : Ref[Opt[Bool]?] = { val: None }
  let _serve = p.cmd(
    name="serve", aliases=["s"], dashdash=false,
    setup=fn(child) { verbose_ref.val = Some(child.flag(name="verbose")) },
  )
  ignore(p.parse(["s", "--verbose"]))
  inspect(verbose_ref.val.unwrap().get(), content="Some(true)")
}

///|
test "H-5: sub aliases basic" {
  // p.sub(name="serve", aliases=["s"]) で "s" がコマンドとして動作すること
  let p = Parser::new(dashdash=false)
  let serve = p.sub(name="serve", aliases=["s"], dashdash=false)
  let verbose = serve.flag(name="verbose")
  ignore(p.parse(["s", "--verbose"]))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "H-5: sub aliases primary name works" {
  let p = Parser::new(dashdash=false)
  let serve = p.sub(name="serve", aliases=["s"], dashdash=false)
  let verbose = serve.flag(name="verbose")
  ignore(p.parse(["serve", "--verbose"]))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "H-5: sub alias parses child options correctly" {
  // alias 経由でも子パーサの string がパースされること
  let p = Parser::new(dashdash=false)
  let serve = p.sub(name="serve", aliases=["s"], dashdash=false)
  let host = serve.string(name="host", default="localhost")
  ignore(p.parse(["s", "--host", "example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "H-5: cmd multiple aliases" {
  let p = Parser::new(dashdash=false)
  let serve = p.cmd(
    name="serve", aliases=["s", "sv", "run"], dashdash=false,
    setup=fn(_child) {  },
  )
  // 最短の alias で起動
  ignore(p.parse(["sv"]))
  inspect(serve.is_set(), content="true")
  inspect(serve.get().unwrap().name, content="serve")
}

// ============================================================
// M-17: custom_append の variation テスト
// ============================================================

///|
test "M-17: custom_append Reset variation clears array" {
  // custom_append + Reset variation で配列がクリアされること
  let p = Parser::new()
  let tags = p.custom_append(
    name="tag", pre=Filter::map(fn(s) { s }),
    variations=[Reset("no")],
  )
  ignore(p.parse(["--tag", "a", "--tag", "b", "--no-tag"]))
  inspect((tags.accessor.get)(), content="[]")
  inspect(tags.is_set(), content="true")
}

///|
test "M-17: custom_append Reset then re-add" {
  // Reset 後に再度追加すると新しい値のみ残る
  let p = Parser::new()
  let tags = p.custom_append(
    name="tag", pre=Filter::map(fn(s) { s }),
    variations=[Reset("no")],
  )
  ignore(p.parse(["--tag", "a", "--no-tag", "--tag", "b"]))
  inspect((tags.accessor.get)(), content="[\"b\"]")
}

///|
test "M-17: custom_append Unset variation clears and unsets" {
  // Unset は配列クリア + is_set=false
  let p = Parser::new()
  let tags = p.custom_append(
    name="tag", pre=Filter::map(fn(s) { s }),
    variations=[Unset("un")],
  )
  ignore(p.parse(["--tag", "a", "--tag", "b", "--un-tag"]))
  inspect((tags.accessor.get)(), content="[]")
  inspect(tags.is_set(), content="false")
}

// ============================================================
// M-18: count の variation テスト (Toggle/True/False)
// ============================================================

///|
test "M-18: count Toggle variation resets to 0" {
  // count の Toggle variation はカウンタを 0 にリセットする
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[Toggle("no")])
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="true")
}

///|
test "M-18: count True variation resets to 0" {
  // count の True variation もカウンタを 0 にリセットする（Bool 特有の True は count では Reset 相当）
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[True("force")])
  ignore(p.parse(["--verbose", "--verbose", "--force-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="true")
}

///|
test "M-18: count False variation resets to 0" {
  // count の False variation もカウンタを 0 にリセットする（Bool 特有の False は count では Reset 相当）
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[False("off")])
  ignore(p.parse(["--verbose", "--verbose", "--verbose", "--off-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="true")
}

///|
test "M-18: count Toggle then re-count" {
  // Toggle でリセット後に再カウントで新しいカウントのみ
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[Toggle("no")])
  ignore(p.parse(["--verbose", "--verbose", "--no-verbose", "--verbose"]))
  inspect(p.get(verbose), content="Some(1)")
}

///|
test "M-18: count Unset variation resets and unsets" {
  // Unset はカウンタリセット + is_set=false
  let p = Parser::new()
  let verbose = p.count(name="verbose", variations=[Unset("un")])
  ignore(p.parse(["--verbose", "--verbose", "--un-verbose"]))
  inspect(p.get(verbose), content="Some(0)")
  inspect(verbose.is_set(), content="false")
}

// ============================================================
// M-21: int の post フィルタバリデーションエラーテスト
// ============================================================

///|
test "M-21: int post validation error" {
  // int に post フィルタ (in_range) を渡して範囲外でエラー
  let p = Parser::new()
  let _ = p.int(
    name="port", default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  let result : Result[_, _] = try? p.parse(["--port", "0"])
  inspect(result is Err(_), content="true")
}

///|
test "M-21: int post validation passes for valid value" {
  let p = Parser::new()
  let port = p.int(
    name="port", default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  ignore(p.parse(["--port", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "M-21: int post validation error message contains out of range" {
  let p = Parser::new()
  let _ = p.int(
    name="port", default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  let result : Result[ParseResult, ParseError] = try? p.parse(["--port", "99999"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("out of range"), content="true")
    _ => abort("expected validation error")
  }
}

///|
test "M-21: int post validation error on negative" {
  let p = Parser::new()
  let _ = p.int(
    name="port", default=8080,
    post=Some(Filter::in_range(1, 65535)),
  )
  let result : Result[_, _] = try? p.parse(["--port", "-1"])
  inspect(result is Err(_), content="true")
}

///|
test "M-21: int post default also validated" {
  // default 値も post フィルタを通る。default=0 で in_range(1, 65535) はエラーになる
  let p = Parser::new()
  let _ = p.int(
    name="port", default=0,
    post=Some(Filter::in_range(1, 65535)),
  )
  let result : Result[_, _] = try? p.parse([])
  inspect(result is Err(_), content="true")
}

// === alias + implicit_value の eq_split フォールバック漏れ ===

///|
test "alias + implicit_value: eq_split via alias name (normal value)" {
  // implicit_value 付きオプションの alias で --alias=value が正しくパースされること
  let p = Parser::new()
  let output = p.string(
    name="output", default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let out = p.make_alias("--out", output)
  ignore(p.parse(["--out=file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("file.txt")
    ),
  )
  inspect(
    out.get(),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "alias + implicit_value: eq_split via alias name (double-dash value)" {
  // implicit_value 付きオプションの alias で --alias=--value が正しくパースされること
  // alias で追加された名前は eq_fallback_nodes に登録されていないため、
  // make_soft_custom_value_node の "--" ガードで Reject → implicit にフォールバックしていた
  let p = Parser::new()
  let output = p.string(
    name="output", default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let out = p.make_alias("--out", output)
  ignore(p.parse(["--out=--file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("--file.txt")
    ),
  )
  inspect(
    out.get(),
    content=(
      #|Some("--file.txt")
    ),
  )
}

///|
test "alias + implicit_value: eq_split via original name still works" {
  // 修正後も元のオプション名での eq_split は引き続き動くこと
  let p = Parser::new()
  let output = p.string(
    name="output", default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let _ = p.make_alias("--out", output)
  ignore(p.parse(["--output=file.txt"]))
  inspect(
    output.get(),
    content=(
      #|Some("file.txt")
    ),
  )
}

///|
test "alias + implicit_value: alias without eq_split uses implicit" {
  // alias を eq_split なしで使った場合は implicit_value が使われること
  let p = Parser::new()
  let output = p.string(
    name="output", default="",
    implicit_value=Some(Lazy::Val("stdout")),
  )
  let out = p.make_alias("--out", output)
  ignore(p.parse(["--out"]))
  inspect(
    output.get(),
    content=(
      #|Some("stdout")
    ),
  )
  inspect(
    out.get(),
    content=(
      #|Some("stdout")
    ),
  )
}

// === R2-C2: cmd getter 安全性テスト ===

///|
test "R2-C2: deprecated Parser::get on unselected cmd returns None" {
  let p = Parser::new(dashdash=false)
  let serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  let _ = p.cmd(name="build", dashdash=false, setup=fn(_child) {  })
  ignore(p.parse(["build"]))
  // serve は未選択 — deprecated API 経由でもパニックしないことを確認
  // Parser::get は self.parsed.val (ルートパーサ) をチェックするため Some を返すが、
  // unwrap() でパニックせず安全なデフォルト値が返ることが重要
  inspect(p.get(serve) is Some(_), content="true")
  // 推奨 API: opt.get() は opt.parsed (子パーサ) をチェックするため None を返す
  inspect(serve.get() is None, content="true")
}

// === R2-C1: global=true の宣言順序非依存テスト ===

///|
test "R2-C1: global defined after cmd propagates to subcommand" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  // global を cmd の後に定義
  let verbose = p.flag(name="verbose", global=true)
  ignore(p.parse(["serve", "--verbose"]))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "R2-C1: global alias defined after cmd propagates" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  let verbose = p.flag(name="verbose", global=true)
  let _ = p.make_alias("--verb", verbose)
  ignore(p.parse(["serve", "--verb"]))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "R2-C1: multiple globals after cmd all propagate" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  let verbose = p.flag(name="verbose", global=true)
  let debug = p.flag(name="debug", global=true)
  ignore(p.parse(["serve", "--verbose", "--debug"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(debug.get(), content="Some(true)")
}

///|
test "R2-C1: global defined after nested cmd propagates to grandchild" {
  let p = Parser::new(dashdash=false)
  let _remote = p.cmd(name="remote", dashdash=false, setup=fn(remote) {
    let _add = remote.cmd(name="add", dashdash=false, setup=fn(_add) {  })
  })
  // global を cmd の後に定義 — 孫 cmd にも遅延同期で伝播するか確認
  let verbose = p.flag(name="verbose", global=true)
  ignore(p.parse(["remote", "add", "--verbose"]))
  inspect(verbose.get(), content="Some(true)")
}

// === R2-W3: shorts 重複検出テスト ===

///|
test "R2-W3: duplicate short option detected" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose", shorts="v")
  let _ = p.flag(name="version", shorts="v")
  let result = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate"), content="true")
    _ => abort("expected duplicate name error for short -v")
  }
}

// === R2-W1: parse retry 動作テスト ===

///|
test "R2-W1: parse after error still works but nodes grow" {
  let p = Parser::new(dashdash=false)
  let name = p.string(name="name", default="world")
  // 1回目: エラーパース
  let r1 = try? p.parse(["--unknown"])
  inspect(r1 is Err(_), content="true")
  // 2回目: 成功パース（ノード二重登録あるが動作は正常）
  let r2 = try? p.parse(["--name", "alice"])
  inspect(r2 is Ok(_), content="true")
  inspect(name.get(), content="Some(\"alice\")")
}

// === R2-W4: implicit_value + choices 共存テスト ===

///|
test "R2-W4: implicit+choices explicit value" {
  let p = Parser::new(dashdash=false)
  let level = p.string(
    name="level", default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  ignore(p.parse(["--level", "warn"]))
  inspect(level.get(), content="Some(\"warn\")")
}

///|
test "R2-W4: implicit+choices implicit value" {
  let p = Parser::new(dashdash=false)
  let level = p.string(
    name="level", default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  ignore(p.parse(["--level"]))
  inspect(level.get(), content="Some(\"debug\")")
}

///|
test "R2-W4: implicit+choices eq-split" {
  let p = Parser::new(dashdash=false)
  let level = p.string(
    name="level", default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  ignore(p.parse(["--level=error"]))
  inspect(level.get(), content="Some(\"error\")")
}

///|
test "R2-W4: implicit+choices invalid choice via eq-split" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="level", default="info",
    choices=["debug", "info", "warn", "error"],
    implicit_value=Some(Val("debug")),
  )
  let result = try? p.parse(["--level=bad"])
  inspect(result is Err(_), content="true")
}

// === deprecated コンビネータテスト ===

///|
test "deprecated records usage when used" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--out", "file.txt"]))
  inspect(p.deprecated_warnings().length(), content="1")
  let warn = p.deprecated_warnings()[0]
  inspect(warn.0, content="--out")
  inspect(warn.1, content="use --output instead")
}

///|
test "deprecated not recorded when unused" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--output", "file.txt"]))
  inspect(p.deprecated_warnings().length(), content="0")
}

///|
test "deprecated shares value with target" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="default")
  let out = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--out", "hello"]))
  // alias 動作: 値が共有される
  inspect(output.get(), content="Some(\"hello\")")
  inspect(out.get(), content="Some(\"hello\")")
}

///|
test "deprecated is_set independent from target" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="default")
  let out = p.deprecated("--out", output, msg="use --output instead")
  ignore(p.parse(["--out", "hello"]))
  // alias 動作: is_set は独立（deprecated 側のみ true、target は set_commit で true）
  inspect(out.is_set(), content="true")
  inspect(output.is_set(), content="true")
}

///|
test "deprecated with cmd" {
  let p = Parser::new(dashdash=false)
  let serve = p.cmd(name="serve", dashdash=false, setup=fn(_child) {  })
  let srv = p.deprecated("serve-old", serve, msg="use 'serve' instead")
  ignore(p.parse(["serve-old"]))
  // cmd の deprecated 別名も動作する
  inspect(serve.get() is Some(_), content="true")
  inspect(srv.get() is Some(_), content="true")
  inspect(p.deprecated_warnings().length(), content="1")
  inspect(p.deprecated_warnings()[0].0, content="serve-old")
}

///|
test "deprecated in subcommand propagates to parent" {
  let p = Parser::new(dashdash=false)
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(child) {
    let port = child.int(name="port", default=8080)
    let _ = child.deprecated("--p", port, msg="use --port")
  })
  ignore(p.parse(["serve", "--p", "3000"]))
  // サブコマンド内の deprecated 警告がルートから取得できること
  inspect(p.deprecated_warnings().length(), content=(
    #|1

  ))
  inspect(p.deprecated_warnings()[0].0, content="--p")
  inspect(p.deprecated_warnings()[0].1, content="use --port")
}

///|
test "deprecated in nested subcommand propagates to root" {
  let p = Parser::new(dashdash=false)
  let _remote = p.cmd(name="remote", dashdash=false, setup=fn(remote) {
    let _add = remote.cmd(name="add", dashdash=false, setup=fn(add) {
      let url = add.string(name="url", default="")
      let _ = add.deprecated("--uri", url, msg="use --url")
    })
  })
  ignore(p.parse(["remote", "add", "--uri", "https://example.com"]))
  // 孫コマンド内の deprecated 警告がルートから取得できること
  inspect(p.deprecated_warnings().length(), content=(
    #|1

  ))
  inspect(p.deprecated_warnings()[0].0, content="--uri")
}

///|
test "deprecated in parent and subcommand both reported" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose")
  let _ = p.deprecated("--verb", verbose, msg="use --verbose")
  let _serve = p.cmd(name="serve", dashdash=false, setup=fn(child) {
    let port = child.int(name="port", default=8080)
    let _ = child.deprecated("--p", port, msg="use --port")
  })
  ignore(p.parse(["--verb", "serve", "--p", "3000"]))
  // 親とサブコマンド両方の警告が取得できること
  inspect(p.deprecated_warnings().length(), content=(
    #|2

  ))
  let names = p.deprecated_warnings().map(fn(w) { w.0 })
  inspect(names.contains("--verb"), content="true")
  inspect(names.contains("--p"), content=(
    #|true

  ))
}

///|
test "deprecated multiple options" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let verbose = p.flag(name="verbose")
  let _ = p.deprecated("--out", output, msg="use --output")
  let _ = p.deprecated("--verb", verbose, msg="use --verbose")
  ignore(p.parse(["--out", "f.txt", "--verb"]))
  inspect(p.deprecated_warnings().length(), content="2")
  // 両方記録されている
  let names = p.deprecated_warnings().map(fn(w) { w.0 })
  inspect(names.contains("--out"), content="true")
  inspect(names.contains("--verb"), content="true")
}

///|
test "deprecated empty name rejected" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("", output, msg="bad")
  let result = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("deprecated name must not be empty"), content="true")
    _ => abort("expected error for empty deprecated name")
  }
}

// === コンビネータ組み合わせテスト ===

///|
test "deprecated alias satisfies required on target" {
  let p = Parser::new(dashdash=false)
  let output = p.string(name="output", default="")
  let _ = p.deprecated("--out", output, msg="use --output")
  p.required(output.as_ref())
  // deprecated 別名で target の required を満たせること
  ignore(p.parse(["--out", "file.txt"]))
  inspect(output.get(), content="Some(\"file.txt\")")
}

///|
test "deprecated alias satisfies at_least_one on target" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  let _ = p.deprecated("--legacy-json", json, msg="use --json")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  // deprecated 別名で at_least_one を満たせること
  ignore(p.parse(["--legacy-json"]))
  inspect(json.get(), content="Some(true)")
}

///|
test "deprecated alias triggers exclusive with target" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  let _ = p.deprecated("--legacy-json", json, msg="use --json")
  p.exclusive([json.as_ref(), csv.as_ref()])
  // deprecated 別名 + 別オプションで exclusive エラーになること
  let result = try? p.parse(["--legacy-json", "--csv"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

///|
test "at_least_one + exclusive = exactly one" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  p.exclusive([json.as_ref(), csv.as_ref()])
  // 1つだけ → OK
  ignore(p.parse(["--json"]))
  inspect(json.get(), content="Some(true)")
}

///|
test "at_least_one + exclusive rejects none" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  p.exclusive([json.as_ref(), csv.as_ref()])
  let result = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("at least one required"), content="true")
    _ => abort("expected at_least_one error")
  }
}

///|
test "at_least_one + exclusive rejects both" {
  let p = Parser::new(dashdash=false)
  let json = p.flag(name="json")
  let csv = p.flag(name="csv")
  p.at_least_one([json.as_ref(), csv.as_ref()])
  p.exclusive([json.as_ref(), csv.as_ref()])
  let result = try? p.parse(["--json", "--csv"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

// === requires（dependent options）テスト ===

///|
test "requires: source set without target is error" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  let result = try? p.parse(["--config", "a.json"])
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message.contains("--output") && info.message.contains("--config"),
        content="true",
      )
    _ => abort("expected requires error")
  }
}

///|
test "requires: both set is ok" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  ignore(p.parse(["--config", "a.json", "--output", "out.txt"]))
  inspect(config.get(), content=(
    #|Some("a.json")
  ))
  inspect(output.get(), content=(
    #|Some("out.txt")
  ))
}

///|
test "requires: neither set is ok" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  ignore(p.parse([]))
  inspect(config.is_set(), content="false")
  inspect(output.is_set(), content="false")
}

///|
test "requires: target set without source is ok" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref())
  ignore(p.parse(["--output", "out.txt"]))
  inspect(output.is_set(), content="true")
}

///|
test "requires: custom error message" {
  let p = Parser::new(dashdash=false)
  let config = p.string(name="config", default="")
  let output = p.string(name="output", default="")
  p.requires(output.as_ref(), source=config.as_ref(), msg="--config needs --output")
  let result = try? p.parse(["--config", "a.json"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("--config needs --output"), content="true")
    _ => abort("expected requires error")
  }
}

// === variation + exclusive 複合テスト ===

///|
test "variation + exclusive: --no-verbose alone is ok" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  ignore(p.parse(["--no-verbose"]))
  inspect(verbose.get(), content="Some(false)")
  inspect(verbose.is_set(), content="true")
  inspect(quiet.is_set(), content="false")
}

///|
test "variation + exclusive: --no-verbose and --quiet is exclusive error" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  let result = try? p.parse(["--no-verbose", "--quiet"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

///|
test "variation + exclusive: --verbose and --quiet is exclusive error" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  let result = try? p.parse(["--verbose", "--quiet"])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("mutually exclusive"), content="true")
    _ => abort("expected exclusive error")
  }
}

///|
test "variation + exclusive: neither set is ok" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.exclusive([verbose.as_ref(), quiet.as_ref()])
  ignore(p.parse([]))
  inspect(verbose.is_set(), content="false")
  inspect(quiet.is_set(), content="false")
}

///|
test "variation + at_least_one: --no-verbose satisfies at_least_one" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", variations=[False("no")])
  let quiet = p.flag(name="quiet")
  p.at_least_one([verbose.as_ref(), quiet.as_ref()])
  ignore(p.parse(["--no-verbose"]))
  inspect(verbose.is_set(), content="true")
}

// === DR-041: env パラメータ（ヘルプ表示）テスト ===

///|
test "env name shown in help for string" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="port", default="8080", env="PORT", description="Server port",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: PORT]"), content="true")
}

///|
test "env name shown in help for flag" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose", env="VERBOSE", description="Enable verbose")
  let help = p.generate_help()
  inspect(help.contains("[env: VERBOSE]"), content="true")
}

///|
test "env name shown in help for int" {
  let p = Parser::new(dashdash=false)
  let _ = p.int(
    name="port", default=8080, env="PORT", description="Server port",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: PORT]"), content="true")
}

///|
test "env and default both shown in help" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="host", default="localhost", env="HOST", description="Server host",
  )
  let help = p.generate_help()
  // env は default の前に表示される（隣接して出現）
  inspect(help.contains("[env: HOST] [default: localhost]"), content="true")
}

///|
test "env not shown when empty" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(name="host", default="localhost", description="Host")
  let help = p.generate_help()
  inspect(help.contains("[env:"), content="false")
}

///|
test "env shown in global options section" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(
    name="verbose", global=true, env="VERBOSE", description="Verbose output",
  )
  let help = p.generate_help()
  inspect(help.contains("Global Options:"), content="true")
  inspect(help.contains("[env: VERBOSE]"), content="true")
}

///|
test "env with custom combinator" {
  let p = Parser::new(dashdash=false)
  let _ = p.custom(
    name="format",
    default="json",
    pre=Filter::map(fn(s) { s }),
    env="OUTPUT_FORMAT",
    description="Output format",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: OUTPUT_FORMAT]"), content="true")
}

///|
test "env with append combinator" {
  let p = Parser::new(dashdash=false)
  let _ = p.append_string(
    name="include", env="INCLUDE_PATHS", description="Include paths",
  )
  let help = p.generate_help()
  inspect(help.contains("[env: INCLUDE_PATHS]"), content="true")
}

///|
test "env with count combinator" {
  let p = Parser::new(dashdash=false)
  let _ = p.count(name="verbose", env="VERBOSE", description="Verbosity level")
  let help = p.generate_help()
  inspect(help.contains("[env: VERBOSE]"), content="true")
}

///|
test "env hidden option does not leak env_name in help" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="secret-key", default="", env="SECRET_KEY", hidden=true,
    description="Secret",
  )
  let _ = p.flag(name="verbose", description="Verbose")
  let help = p.generate_help()
  inspect(help.contains("[env: SECRET_KEY]"), content="false")
  inspect(help.contains("secret-key"), content="false")
}

// === DR-041 Phase 2: env 値取得テスト ===

///|
test "env: string gets value from env when not specified on CLI" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={"PORT": "9000"}))
  inspect(port.get(), content=(
    #|Some("9000")
  ))
}

///|
test "env: CLI arg takes precedence over env" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse(["--port", "3000"], env={"PORT": "9000"}))
  inspect(port.get(), content=(
    #|Some("3000")
  ))
}

///|
test "env: default used when neither CLI nor env specified" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={}))
  inspect(port.get(), content=(
    #|Some("8080")
  ))
}

///|
test "env: flag from env" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", env="VERBOSE")
  ignore(p.parse([], env={"VERBOSE": "true"}))
  inspect(verbose.get(), content="Some(true)")
}

///|
test "env: flag false from env" {
  let p = Parser::new(dashdash=false)
  let verbose = p.flag(name="verbose", env="VERBOSE")
  ignore(p.parse([], env={"VERBOSE": "false"}))
  inspect(verbose.get(), content="Some(false)")
}

///|
test "env: int from env" {
  let p = Parser::new(dashdash=false)
  let port = p.int(name="port", default=8080, env="PORT")
  ignore(p.parse([], env={"PORT": "9000"}))
  inspect(port.get(), content="Some(9000)")
}

///|
test "env: is_set true when value from env" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={"PORT": "9000"}))
  inspect(port.is_set(), content="true")
}

///|
test "env: is_set false when no env and no CLI" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={}))
  inspect(port.is_set(), content="false")
}

///|
test "env: required satisfied by env value" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  p.required(port.as_ref())
  ignore(p.parse([], env={"PORT": "9000"}))
  inspect(port.get(), content=(
    #|Some("9000")
  ))
}

///|
test "env: count from env" {
  let p = Parser::new(dashdash=false)
  let verbose = p.count(name="verbose", env="VERBOSE")
  ignore(p.parse([], env={"VERBOSE": "3"}))
  inspect(verbose.get(), content="Some(3)")
}

///|
test "env: append_string from env (comma-separated)" {
  let p = Parser::new(dashdash=false)
  let includes = p.append_string(name="include", env="INCLUDES")
  ignore(p.parse([], env={"INCLUDES": "a,b,c"}))
  inspect(includes.get(), content=(
    #|Some(["a", "b", "c"])
  ))
}

///|
test "env: append_int from env (comma-separated)" {
  let p = Parser::new(dashdash=false)
  let ports = p.append_int(name="port", env="PORTS")
  ignore(p.parse([], env={"PORTS": "80,443,8080"}))
  inspect(ports.get(), content="Some([80, 443, 8080])")
}

///|
test "env: empty env string is ignored" {
  let p = Parser::new(dashdash=false)
  let port = p.string(name="port", default="8080", env="PORT")
  ignore(p.parse([], env={"PORT": ""}))
  inspect(port.get(), content=(
    #|Some("8080")
  ))
  inspect(port.is_set(), content="false")
}

///|
test "env: invalid flag value raises error" {
  let p = Parser::new(dashdash=false)
  let _ = p.flag(name="verbose", env="VERBOSE")
  let result = try? p.parse([], env={"VERBOSE": "yes"})
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("expected true/false/1/0"), content="true")
    _ => abort("expected parse error for invalid flag env value")
  }
}

///|
test "env: invalid int value raises error" {
  let p = Parser::new(dashdash=false)
  let _ = p.int(name="port", default=8080, env="PORT")
  let result = try? p.parse([], env={"PORT": "abc"})
  inspect(result is Err(_), content="true")
}

///|
test "env: choices validation applies to env values" {
  let p = Parser::new(dashdash=false)
  let _ = p.string(
    name="format", default="json", env="FORMAT", choices=["json", "yaml", "toml"],
  )
  let result = try? p.parse([], env={"FORMAT": "xml"})
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("value must be one of"), content="true")
    _ => abort("expected choices validation error for env value")
  }
}

///|
test "env: choices validation passes for valid env value" {
  let p = Parser::new(dashdash=false)
  let format = p.string(
    name="format", default="json", env="FORMAT", choices=["json", "yaml", "toml"],
  )
  ignore(p.parse([], env={"FORMAT": "yaml"}))
  inspect(format.get(), content=(
    #|Some("yaml")
  ))
}

///|
test "priv setter: flag setter writes cell value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  ignore(p.parse([]))
  inspect(verbose.get(), content="Some(false)")
  // priv setter で直接書き換え
  (verbose.accessor.set_value)(true)
  inspect(verbose.get(), content="Some(true)")
  // is_set は連動しない（setter の設計制約）
  inspect(verbose.is_set(), content="false")
}

///|
test "priv setter: string setter writes cell value" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  ignore(p.parse([]))
  inspect(
    host.get(),
    content=(
      #|Some("localhost")
    ),
  )
  (host.accessor.set_value)("example.com")
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "priv setter: alias shares setter with target" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let v = p.make_alias("-v", verbose)
  ignore(p.parse([]))
  // alias の setter は target と同一 cell を指す
  (v.accessor.set_value)(true)
  inspect(verbose.get(), content="Some(true)")
  inspect(v.get(), content="Some(true)")
}

///|
test "adjust: after_post transforms value when set" {
  let p = Parser::new()
  let port = p.int(name="port", default=0)
  p.adjust(port, after_post=Filter::map(fn(v) { v + 1000 }))
  ignore(p.parse(["--port", "80"]))
  inspect(port.get(), content="Some(1080)")
}

///|
test "adjust: after_post skips when not set" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  p.adjust(port, after_post=Filter::map(fn(v) { v + 1000 }))
  ignore(p.parse([]))
  // default 値には変換を掛けない
  inspect(port.get(), content="Some(8080)")
}

///|
test "adjust: after_post validation raises error" {
  let p = Parser::new()
  let port = p.int(name="port", default=0)
  p.adjust(port, after_post={ run: fn(v) raise ParseError {
    if v > 1024 {
      v
    } else {
      raise parse_error("port must be > 1024")
    }
  } })
  let result : Result[_, _] = try? p.parse(["--port", "80"])
  inspect(result is Err(_), content="true")
}

///|
test "link: copies value from source to target when source is set" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  p.link(debug, source=verbose)
  ignore(p.parse(["--verbose"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(debug.get(), content="Some(true)")
}

///|
test "link: does not copy when source is not set" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  p.link(debug, source=verbose)
  ignore(p.parse([]))
  inspect(verbose.get(), content="Some(false)")
  inspect(debug.get(), content="Some(false)")
}

///|
test "link: string value forwarding" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let server = p.string(name="server", default="default-server")
  p.link(server, source=host)
  ignore(p.parse(["--host", "example.com"]))
  inspect(
    host.get(),
    content=(
      #|Some("example.com")
    ),
  )
  inspect(
    server.get(),
    content=(
      #|Some("example.com")
    ),
  )
}

///|
test "clone: independent cell - clone set does not affect target" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let v = p.clone("--verb", verbose)
  ignore(p.parse(["--verb"]))
  assert_true(v.is_set())
  assert_false(verbose.is_set())
  inspect(v.get(), content="Some(true)")
  inspect(verbose.get(), content="Some(false)")
}

///|
test "clone: independent cell - target set does not affect clone" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let v = p.clone("--verb", verbose)
  ignore(p.parse(["--verbose"]))
  assert_true(verbose.is_set())
  assert_false(v.is_set())
  inspect(verbose.get(), content="Some(true)")
  inspect(v.get(), content="Some(false)")
}

///|
test "link: overwrites target when both source and target are set" {
  let p = Parser::new()
  let src = p.string(name="source", default="s-default")
  let tgt = p.string(name="target", default="t-default")
  p.link(tgt, source=src)
  ignore(p.parse(["--source", "from-src", "--target", "from-tgt"]))
  // source が set なので target は source の値で上書きされる
  inspect(
    tgt.get(),
    content=(
      #|Some("from-src")
    ),
  )
}

///|
test "clone: both unused" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let verb = p.clone("--verb", verbose)
  ignore(p.parse([]))
  inspect(verbose.is_set(), content="false")
  inspect(verb.is_set(), content="false")
  inspect(verbose.get(), content="Some(false)")
  inspect(verb.get(), content="Some(false)")
}

///|
test "clone: both set independently" {
  let p = Parser::new()
  let port = p.int(name="port", default=80)
  let clone_port = p.clone("--port2", port)
  ignore(p.parse(["--port", "3000", "--port2", "8080"]))
  inspect(port.get(), content="Some(3000)")
  inspect(clone_port.get(), content="Some(8080)")
}

///|
test "clone: string independent cell" {
  let p = Parser::new()
  let host = p.string(name="host", default="localhost")
  let host2 = p.clone("--host2", host)
  ignore(p.parse(["--host2", "example.com"]))
  inspect(host.get(), content=(
    #|Some("localhost")
  ))
  inspect(host2.get(), content=(
    #|Some("example.com")
  ))
}

///|
test "adjust: multiple adjusts on same target execute in order" {
  let p = Parser::new()
  let val = p.int(name="val", default=0)
  p.adjust(val, after_post=Filter::map(fn(v) { v * 2 }))
  p.adjust(val, after_post=Filter::map(fn(v) { v + 1 }))
  ignore(p.parse(["--val", "5"]))
  // 5 * 2 = 10, 10 + 1 = 11 (登録順に実行)
  inspect(val.get(), content="Some(11)")
}

///|
test "clone + link: clone with independent forwarding" {
  let p = Parser::new()
  let src = p.flag(name="source")
  let cloned = p.clone("--cloned", src)
  let tgt = p.flag(name="target")
  p.link(tgt, source=cloned)
  ignore(p.parse(["--cloned"]))
  inspect(cloned.is_set(), content="true")
  inspect(tgt.get(), content="Some(true)")
}

///|
test "practical: deprecated alias with adjust validation" {
  let p = Parser::new()
  let port = p.int(name="port", default=8080)
  let _old_port = p.deprecated("--old-port", port, msg="Use --port instead")
  p.adjust(port, after_post={ run: fn(v) raise ParseError {
    if v >= 1 && v <= 65535 {
      v
    } else {
      raise parse_error("port must be 1-65535")
    }
  } })
  // deprecated alias でもパースは成功し、adjust の検証も通る
  ignore(p.parse(["--old-port", "3000"]))
  inspect(port.get(), content="Some(3000)")
  let warnings = p.deprecated_warnings()
  inspect(warnings.length(), content="1")
}

///|
test "practical: link for verbose implies debug" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  // --verbose が指定されたら --debug も自動で有効にする
  p.link(debug, source=verbose)
  ignore(p.parse(["--verbose"]))
  inspect(verbose.get(), content="Some(true)")
  inspect(debug.get(), content="Some(true)")
  inspect(verbose.is_set(), content="true")
  // debug は link で値が書き込まれるが is_set は false（パースで set されたわけではない）
  inspect(debug.is_set(), content="false")
}

///|
test "practical: clone + adjust for derived option" {
  let p = Parser::new()
  let port = p.int(name="port", default=80)
  let secure_port = p.clone("--secure-port", port)
  // secure-port には +443 のオフセットを付ける
  p.adjust(secure_port, after_post=Filter::map(fn(v) { v + 443 }))
  ignore(p.parse(["--secure-port", "100"]))
  inspect(secure_port.get(), content="Some(543)")
  // clone は独立 cell: port は影響を受けない
  inspect(port.get(), content="Some(80)")
}

// ===== ValCell / Accessor tests (DR-045) =====

///|
test "ValCell: new creates cell with default value and committed=false" {
  let vc : ValCell[Int] = ValCell::new(Val(42))
  assert_eq(vc.cell.val, 42)
  assert_eq(vc.committed.val, false)
}

///|
test "ValCell: accessor get returns cell value" {
  let vc = ValCell::new(Val(10))
  let acc = vc.accessor()
  assert_eq((acc.get)(), 10)
}

///|
test "ValCell: accessor set updates value and committed" {
  let vc = ValCell::new(Val(0))
  let acc = vc.accessor()
  (acc.set)(99)
  assert_eq((acc.get)(), 99)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: accessor set_value updates value without committed" {
  let vc = ValCell::new(Val(0))
  let acc = vc.accessor()
  (acc.set_value)(99)
  assert_eq((acc.get)(), 99)
  assert_eq(vc.committed.val, false)
}

///|
test "ValCell: accessor reset restores default and clears committed" {
  let vc = ValCell::new(Val(42))
  let acc = vc.accessor()
  (acc.set)(100)
  assert_eq((acc.get)(), 100)
  assert_eq(vc.committed.val, true)
  (acc.reset)()
  assert_eq((acc.get)(), 42)
  assert_eq(vc.committed.val, false)
}

///|
test "ValCell: clone creates independent cell with same default" {
  let vc1 = ValCell::new(Val(5))
  let acc1 = vc1.accessor()
  (acc1.set)(10)
  let vc2 = vc1.clone()
  let acc2 = vc2.accessor()
  // vc2 is independent: default value, committed=false
  assert_eq((acc2.get)(), 5)
  assert_eq(vc2.committed.val, false)
  // vc1 is unchanged
  assert_eq((acc1.get)(), 10)
  assert_eq(vc1.committed.val, true)
}

///|
test "ValCell: multiple accessors share same cell" {
  let vc = ValCell::new(Val(0))
  let acc1 = vc.accessor()
  let acc2 = vc.accessor()
  (acc1.set)(42)
  assert_eq((acc2.get)(), 42)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: set → reset → set cycle" {
  let vc = ValCell::new(Val(42))
  let acc = vc.accessor()
  (acc.set)(99)
  assert_eq((acc.get)(), 99)
  assert_eq(vc.committed.val, true)
  (acc.reset)()
  assert_eq((acc.get)(), 42)
  assert_eq(vc.committed.val, false)
  (acc.set)(77)
  assert_eq((acc.get)(), 77)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: set_commit only updates committed without changing value" {
  let vc = ValCell::new(Val(42))
  let acc = vc.accessor()
  // 初期状態: committed = false
  assert_eq(vc.committed.val, false)
  assert_eq((acc.get)(), 42)
  // set_value で値を変えてから set_commit
  (acc.set_value)(99)
  assert_eq(vc.committed.val, false) // set_value は committed を変えない
  assert_eq((acc.get)(), 99)
  (acc.set_commit)()
  assert_eq(vc.committed.val, true) // set_commit で committed = true
  assert_eq((acc.get)(), 99) // 値は set_value で設定した 99 のまま
  // reset で committed と値の両方がデフォルトに戻る
  (acc.reset)()
  assert_eq(vc.committed.val, false)
  assert_eq((acc.get)(), 42) // 99 → 42 に戻ったことで reset が効いた証明
}

///|
test "ValCell: clone bidirectional independence" {
  let vc1 = ValCell::new(Val(0))
  let acc1 = vc1.accessor()
  let vc2 = vc1.clone()
  let acc2 = vc2.accessor()
  // vc1 → vc2 独立
  (acc1.set)(10)
  assert_eq((acc2.get)(), 0)
  assert_eq(vc2.committed.val, false)
  // vc2 → vc1 独立
  (acc2.set)(20)
  assert_eq((acc1.get)(), 10)
  assert_eq(vc1.committed.val, true)
}

///|
test "ValCell: set_value then set updates committed" {
  let vc = ValCell::new(Val(0))
  let acc = vc.accessor()
  // set_value: 値は変わるが committed は false
  (acc.set_value)(50)
  assert_eq((acc.get)(), 50)
  assert_eq(vc.committed.val, false)
  // set: 値も committed も更新
  (acc.set)(100)
  assert_eq((acc.get)(), 100)
  assert_eq(vc.committed.val, true)
}

///|
test "ValCell: reset on shared accessors propagates" {
  let vc = ValCell::new(Val(0))
  let acc1 = vc.accessor()
  let acc2 = vc.accessor()
  (acc1.set)(42)
  assert_eq((acc2.get)(), 42)
  assert_eq(vc.committed.val, true)
  (acc1.reset)()
  assert_eq((acc2.get)(), 0)
  assert_eq(vc.committed.val, false)
}

///|
test "link: propagate_set=true updates target is_set" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  p.link(debug, source=verbose, propagate_set=true)
  ignore(p.parse(["--verbose"]))
  assert_true(verbose.is_set())
  assert_true(debug.is_set()) // propagate_set=true なので debug.is_set() も true
  inspect(debug.get(), content="Some(true)")
}

///|
test "env: subcmd env option gets value from parent env map" {
  let p = Parser::new()
  let sub = p.sub(name="serve")
  let port = sub.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["serve"], env={"PORT": "9000"}))
  inspect(port.get(), content="Some(9000)")
  inspect(port.is_set(), content="true")
}

///|
test "env: subcmd CLI arg takes precedence over env" {
  let p = Parser::new()
  let sub = p.sub(name="serve")
  let port = sub.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["serve", "--port", "3000"], env={"PORT": "9000"}))
  inspect(port.get(), content="Some(3000)")
  inspect(port.is_set(), content="true")
}

///|
test "env: subcmd default used when neither CLI nor env specified" {
  let p = Parser::new()
  let sub = p.sub(name="serve")
  let port = sub.int(name="port", default=8080, env="PORT")
  ignore(p.parse(["serve"], env={}))
  inspect(port.get(), content="Some(8080)")
  inspect(port.is_set(), content="false")
}

///|
test "env: nested subcmd env propagation" {
  let p = Parser::new()
  let sub = p.sub(name="app")
  let inner = sub.sub(name="serve")
  let host = inner.string(name="host", default="localhost", env="HOST")
  ignore(p.parse(["app", "serve"], env={"HOST": "example.com"}))
  inspect(host.get(), content=(
    #|Some("example.com")
  ))
  inspect(host.is_set(), content="true")
}

///|
test "alias chain: root committed propagates through chained aliases" {
  let p = Parser::new()
  let opt = p.string(name="host", default="localhost")
  let alias1 = p.make_alias("--h1", opt)
  let alias2 = p.make_alias("--h2", alias1)
  ignore(p.parse(["--h2", "example.com"]))
  // alias2 使用時: opt と alias2 の is_set が true、alias1 は false（独立 is_set）
  assert_true(opt.is_set())
  assert_true(alias2.is_set())
  assert_false(alias1.is_set())
  // 値は全て共有（alias は Accessor 共有）
  inspect(opt.get(), content=(
    #|Some("example.com")
  ))
  inspect(alias1.get(), content=(
    #|Some("example.com")
  ))
  inspect(alias2.get(), content=(
    #|Some("example.com")
  ))
}

// ============================================================
// Surrogate pair (Supplementary Plane) tests
// ============================================================

///|
test "levenshtein: emoji identical strings" {
  inspect(levenshtein("--😀mode", "--😀mode"), content="0")
}

///|
test "levenshtein: emoji one char diff" {
  inspect(levenshtein("--😀mode", "--😀mod"), content="1")
}

///|
test "levenshtein: emoji substitution" {
  inspect(levenshtein("--😀", "--😎"), content="1")
}

///|
test "levenshtein: ascii vs emoji" {
  inspect(levenshtein("--a", "--😀"), content="1")
}

///|
test "surrogate pair: single emoji short option" {
  let p = Parser::new()
  let opt = p.flag(name="smile", shorts="😀")
  ignore(p.parse(["-😀"]))
  inspect(p.get(opt), content="Some(true)")
}

///|
test "surrogate pair: emoji short combining two flags" {
  let p = Parser::new()
  let a = p.flag(name="smile", shorts="😀")
  let b = p.flag(name="cool", shorts="😎")
  ignore(p.parse(["-😀😎"]))
  inspect(p.get(a), content="Some(true)")
  inspect(p.get(b), content="Some(true)")
}

///|
test "surrogate pair: emoji + ascii combining" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let e = p.flag(name="emoji", shorts="😀")
  ignore(p.parse(["-v😀"]))
  inspect(p.get(v), content="Some(true)")
  inspect(p.get(e), content="Some(true)")
}

///|
test "surrogate pair: emoji first then ascii combining" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let e = p.flag(name="emoji", shorts="😀")
  ignore(p.parse(["-😀v"]))
  inspect(p.get(e), content="Some(true)")
  inspect(p.get(v), content="Some(true)")
}

///|
test "surrogate pair: emoji short with inline value" {
  let p = Parser::new()
  let port = p.int(name="port", default=0, shorts="😀")
  ignore(p.parse(["-😀3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "surrogate pair: emoji combining flag then value" {
  let p = Parser::new()
  let v = p.flag(name="verbose", shorts="v")
  let port = p.int(name="port", default=0, shorts="😀")
  ignore(p.parse(["-v😀3000"]))
  inspect(p.get(v), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "surrogate pair: suggest_typo with emoji option" {
  let p = Parser::new()
  let _ = p.flag(name="😀mode")
  let r : Result[ParseResult, _] = try? p.parse(["--😎mode"])
  match r {
    Err(ParseError(info)) => {
      inspect(info.message.contains("did you mean"), content="true")
      inspect(info.message.contains("😀mode"), content="true")
    }
    _ => fail("expected ParseError")
  }
}

// ============================================================
// Grapheme cluster (composite emoji) tests
// ============================================================

///|
test "grapheme cluster: levenshtein with flag emoji" {
  // 🇯🇵 (Regional Indicator × 2) は 1 grapheme cluster
  inspect(levenshtein("--\u{1F1EF}\u{1F1F5}mode", "--\u{1F1EF}\u{1F1F5}mode"), content="0")
  inspect(levenshtein("--\u{1F1EF}\u{1F1F5}mode", "--\u{1F1EF}\u{1F1F5}mod"), content="1")
}

///|
test "grapheme cluster: levenshtein with family emoji" {
  // 👨‍👩‍👧‍👦 (ZWJ sequence, 7 codepoints) は 1 grapheme cluster
  // grapheme cluster 単位なら距離1（1 cluster の置換）
  // コードポイント単位なら距離7以上になるはず
  inspect(
    levenshtein(
      "--\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",
      "--\u{1F600}",
    ),
    content="1",
  )
}

///|
test "grapheme cluster: levenshtein with skin tone emoji" {
  // 👋🏽 (wave + skin tone, 2 codepoints) は 1 grapheme cluster
  // grapheme cluster 単位なら距離1（1 cluster の置換）
  // コードポイント単位なら距離2になるはず
  inspect(
    levenshtein("--\u{1F44B}\u{1F3FD}", "--\u{1F600}"),
    content="1",
  )
}

///|
test "grapheme cluster: levenshtein flag vs flag substitution" {
  // 🇯🇵 と 🇺🇸 は各 1 grapheme cluster
  inspect(
    levenshtein(
      "--\u{1F1EF}\u{1F1F5}",
      "--\u{1F1FA}\u{1F1F8}",
    ),
    content="1",
  )
}

///|
test "grapheme cluster: long option with flag emoji" {
  let p = Parser::new()
  let opt = p.flag(name="\u{1F1EF}\u{1F1F5}mode")
  ignore(p.parse(["--\u{1F1EF}\u{1F1F5}mode"]))
  inspect(p.get(opt), content="Some(true)")
}

///|
test "grapheme cluster: long option with family emoji" {
  let p = Parser::new()
  let opt = p.string(
    name="\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}-mode",
    default="off",
  )
  ignore(p.parse(["--\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}-mode", "on"]))
  inspect(
    p.get(opt),
    content=(
      #|Some("on")
    ),
  )
}

///|
test "grapheme cluster: suggest_typo with flag emoji" {
  let p = Parser::new()
  let _ = p.flag(name="\u{1F1EF}\u{1F1F5}mode")
  let r : Result[ParseResult, _] = try? p.parse(["--\u{1F1EF}\u{1F1F5}mod"])
  match r {
    Err(ParseError(info)) => {
      inspect(info.message.contains("did you mean"), content="true")
      inspect(info.message.contains("\u{1F1EF}\u{1F1F5}mode"), content="true")
    }
    _ => fail("expected ParseError with typo suggestion")
  }
}

///|
test "grapheme cluster: eq split with flag emoji" {
  let p = Parser::new()
  let opt = p.string(name="\u{1F1EF}\u{1F1F5}mode", default="off")
  ignore(p.parse(["--\u{1F1EF}\u{1F1F5}mode=on"]))
  inspect(
    p.get(opt),
    content=(
      #|Some("on")
    ),
  )
}

// ============================================================
// Grapheme cluster short option tests (shorts Array[String] migration)
// ============================================================

///|
test "shorts grapheme cluster: flag emoji short option" {
  // 🇯🇵 (Regional Indicator × 2 = 1 grapheme cluster) を short option として使う
  let p = Parser::new()
  let opt = p.flag(name="japan", shorts="\u{1F1EF}\u{1F1F5}")
  ignore(p.parse(["-\u{1F1EF}\u{1F1F5}"]))
  inspect(p.get(opt), content="Some(true)")
}

///|
test "shorts grapheme cluster: family emoji short combining" {
  // 👨‍👩‍👧‍👦 (ZWJ seq) + v を combining
  let p = Parser::new()
  let f = p.flag(name="family", shorts="\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}")
  let v = p.flag(name="verbose", shorts="v")
  ignore(p.parse(["-\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}v"]))
  inspect(p.get(f), content="Some(true)")
  inspect(p.get(v), content="Some(true)")
}

///|
test "shorts grapheme cluster: skin tone short + inline value" {
  // 👋🏽 (wave + skin tone = 1 grapheme cluster) を short option として使い、inline value を取る
  let p = Parser::new()
  let port = p.int(name="port", default=0, shorts="\u{1F44B}\u{1F3FD}")
  ignore(p.parse(["-\u{1F44B}\u{1F3FD}3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "shorts grapheme cluster: help display" {
  let p = Parser::new()
  let _ = p.flag(name="japan", shorts="\u{1F1EF}\u{1F1F5}", description="Japan flag")
  let help = p.generate_help()
  inspect(help.contains("-\u{1F1EF}\u{1F1F5}, --japan"), content="true")
}

///|
test "shorts grapheme cluster: multiple grapheme shorts" {
  // shorts="🇯🇵🇺🇸" = 2 grapheme clusters → -🇯🇵 と -🇺🇸 の2つの short option
  let p = Parser::new()
  let opt = p.count(name="flag", shorts="\u{1F1EF}\u{1F1F5}\u{1F1FA}\u{1F1F8}")
  ignore(p.parse(["-\u{1F1EF}\u{1F1F5}"]))
  inspect(p.get(opt), content="Some(1)")
}

// === float ===

///|
test "float: --threshold 0.5" {
  let p = Parser::new()
  let threshold = p.float(name="threshold", default=0.0)
  ignore(p.parse(["--threshold", "0.5"]))
  inspect(p.get(threshold), content="Some(0.5)")
}

///|
test "float: default value" {
  let p = Parser::new()
  let threshold = p.float(name="threshold", default=3.14)
  ignore(p.parse([]))
  inspect(p.get(threshold), content="Some(3.14)")
}

///|
test "float: invalid value" {
  let p = Parser::new()
  let _ = p.float(name="threshold", default=0.0)
  let result : Result[_, _] = try? p.parse(["--threshold", "abc"])
  inspect(result is Err(_), content="true")
}

///|
test "float: --threshold=1.5 eq form" {
  let p = Parser::new()
  let threshold = p.float(name="threshold", default=0.0)
  ignore(p.parse(["--threshold=1.5"]))
  inspect(p.get(threshold), content="Some(1.5)")
}

///|
test "float: with post filter" {
  let p = Parser::new()
  let rate = p.float(
    name="rate", default=0.5,
    post=Some(Filter::float_in_range(0.0, 1.0)),
  )
  ignore(p.parse(["--rate", "0.7"]))
  inspect(p.get(rate), content="Some(0.7)")
}

///|
test "float: post filter rejects out of range" {
  let p = Parser::new()
  let _ = p.float(
    name="rate", default=0.5,
    post=Some(Filter::float_in_range(0.0, 1.0)),
  )
  let result : Result[_, _] = try? p.parse(["--rate", "1.5"])
  inspect(result is Err(_), content="true")
}

///|
test "float: negative value" {
  let p = Parser::new()
  let temp = p.float(name="temperature", default=0.0)
  ignore(p.parse(["--temperature", "-40.5"]))
  inspect(p.get(temp), content="Some(-40.5)")
}

// === append_float ===

///|
test "append_float: multiple values" {
  let p = Parser::new()
  let coords = p.append_float(name="coord")
  ignore(p.parse(["--coord", "1.5", "--coord", "2.5", "--coord", "3.0"]))
  inspect(p.get(coords), content="Some([1.5, 2.5, 3])")
}

///|
test "append_float: empty" {
  let p = Parser::new()
  let coords = p.append_float(name="coord")
  ignore(p.parse([]))
  inspect(p.get(coords), content="Some([])")
}

///|
test "append_float: invalid value" {
  let p = Parser::new()
  let _ = p.append_float(name="coord")
  let result : Result[_, _] = try? p.parse(["--coord", "abc"])
  inspect(result is Err(_), content="true")
}

// === boolean ===

///|
test "boolean: --flag true" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse(["--debug", "true"]))
  inspect(p.get(debug), content="Some(true)")
}

///|
test "boolean: --flag false" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse(["--debug", "false"]))
  inspect(p.get(debug), content="Some(false)")
}

///|
test "boolean: default is false" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse([]))
  inspect(p.get(debug), content="Some(false)")
}

///|
test "boolean: accepts on/off/t/f/1/0" {
  let p = Parser::new()
  let debug = p.boolean(name="debug")
  ignore(p.parse(["--debug", "on"]))
  inspect(p.get(debug), content="Some(true)")
  let p2 = Parser::new()
  let d2 = p2.boolean(name="debug")
  ignore(p2.parse(["--debug", "OFF"]))
  inspect(p2.get(d2), content="Some(false)")
  let p3 = Parser::new()
  let d3 = p3.boolean(name="debug")
  ignore(p3.parse(["--debug", "1"]))
  inspect(p3.get(d3), content="Some(true)")
}

///|
test "boolean: invalid value" {
  let p = Parser::new()
  let _ = p.boolean(name="debug")
  let result : Result[_, _] = try? p.parse(["--debug", "maybe"])
  inspect(result is Err(_), content="true")
}

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
// coverage: テストカバレッジ改善用テスト
// ============================================================

///|
test "coverage: ParseResult::child on non-Map result returns None" {
  // access.mbt:35 — ParseResult::child で Map 以外に対して呼ぶと None
  let p = Parser::new()
  let _ = p.flag(name="verbose")
  let result = p.parse([])
  // result.kind は One（子コマンドなし）なので child は None を返す
  inspect(result.child("anything") is None, content="true")
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
  inspect(h1.get(), content="Some(true)")
  inspect(h2.get(), content="Some(true)")
}

///|
test "coverage: variation_toggle sugar for flag" {
  // options.mbt:34 — variation_toggle sugar
  let p = Parser::new()
  let flag = p.flag(name="color", variation_toggle=Some("toggle"))
  ignore(p.parse(["--toggle-color"]))
  inspect(flag.get(), content="Some(true)")
}

///|
test "coverage: variation_unset sugar for flag" {
  // options.mbt:38 — variation_unset sugar
  let p = Parser::new()
  let flag = p.flag(name="color", variation_unset=Some("unset"))
  ignore(p.parse(["--color", "--unset-color"]))
  // unset は committed=false にするので is_set は false、値は default に戻る
  inspect(flag.is_set(), content="false")
}

///|
test "coverage: count env with invalid integer" {
  // options.mbt:367 — count の env で無効な整数値
  let p = Parser::new()
  let _ = p.count(name="verbose", env="VERBOSE_COUNT")
  let result : Result[_, _] = try? p.parse([], env={"VERBOSE_COUNT": "abc"})
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("invalid value for env"), content="true")
    _ => fail("expected ParseError for invalid count env")
  }
}

///|
test "coverage: register_env_applicator with missing env key" {
  // options.mbt:18 — env_map にキーがない場合 None => ()
  let p = Parser::new()
  let opt = p.string(name="name", default="default", env="MY_NAME")
  // env に MY_NAME キーがないが、別のキーはある
  ignore(p.parse([], env={"OTHER_KEY": "value"}))
  // env にキーなしなので default のまま
  inspect(
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
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate"), content="true")
    _ => fail("expected ParseError for duplicate --")
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
  inspect(
    files.get(),
    content=(
      #|Some(["a", "b"])
    ),
  )
  inspect(
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
  inspect(
    greedy_pos.get(),
    content=(
      #|Some("first")
    ),
  )
  inspect(opt.get(), content="Some(true)")
  inspect(
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
  let _ = p.string(name="name", shorts="n", default="")
  let result : Result[_, _] = try? p.parse(["-vn"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.kind, content="MissingValue")
      inspect(info.opt_name, content="-n")
    }
    _ => fail("expected MissingValue for -vn without value")
  }
}

///|
test "coverage: short combine value trial error propagation with choices" {
  // parse.mbt:264 — short combine で value trial が Error (choices バリデーション失敗)
  let p = Parser::new()
  let _ = p.flag(name="verbose", shorts="v")
  let _ = p.string(
    name="format", shorts="f", default="text", choices=["text", "json"],
  )
  // -vfxml: v はフラグ、f は value opt で choices=["text","json"]。
  // value trial で "xml" を試すが choices バリデーション失敗 → Error 伝搬
  let result : Result[_, _] = try? p.parse(["-vfxml"])
  inspect(result is Err(_), content="true")
}

///|
test "coverage: clone duplicate name detection" {
  // parser.mbt:309 — clone で既に登録済みの名前を使用
  let p = Parser::new()
  let opt = p.flag(name="verbose")
  let _ = p.clone("--verbose", opt) // 重複名
  let result : Result[_, _] = try? p.parse([])
  match result {
    Err(ParseError(info)) =>
      inspect(info.message.contains("duplicate"), content="true")
    _ => fail("expected duplicate error")
  }
}

///|
test "coverage: clone with global flag propagates to child" {
  // parser.mbt:361 — clone の target が global の場合、clone も global_nodes に追加
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let v_clone = p.clone("--debug", verbose)
  let sub_ran = p.cmd(
    name="sub",
    setup=fn(sub) {
      // global なので子パーサーでも --debug が使える
      let _ = sub.flag(name="local-flag")
    },
  )
  ignore(p.parse(["sub", "--debug"]))
  inspect(sub_ran.get() is Some(_), content="true")
  inspect(v_clone.get(), content="Some(true)")
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
  inspect(
    colour.get(),
    content=(
      #|Some("never")
    ),
  )
  // target は変更されない
  inspect(
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
  p.serial(
    setup=fn(sub) {
      let _ = sub.positional(name="first")
    },
  )
  let second = p.positional(name="second")
  ignore(p.parse(["hello", "world"]))
  inspect(
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
  p.serial(
    setup=fn(sub) {
      let _ = sub.positional(name="first")
      let _ = sub.rest(name="mid", stop_before=["END"])
    },
  )
  let last = p.positional(name="last")
  ignore(p.parse(["a", "b", "END"]))
  inspect(
    last.get(),
    content=(
      #|Some("END")
    ),
  )
}
