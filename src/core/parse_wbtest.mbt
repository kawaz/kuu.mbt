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
  let verbose = p.flag(name="verbose")
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
  let color = p.flag(name="color", default=true)
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
  let host = p.string_opt(name="host", default="localhost")
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
  let port = p.int_opt(name="port", default=8080)
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
  let tags = p.append_string(name="tag")
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
  inspect(p.get(serve), content="Some(true)")
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
  inspect(p.get(serve), content="Some(false)")
  inspect(p.get(build), content="Some(true)")
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
  let verbose = p.flag(name="verbose", aliases=["v"])
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
  let verbose = p.flag(name="verbose", short='v')
  ignore(p.parse(["-v"]))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "short int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse(["-p", "3000"]))
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", short='H')
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
  let verbose = p.flag(name="verbose", short='v')
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse(["-v", "--port", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short append" {
  let p = Parser::new()
  let tags = p.append_string(name="tag", short='t')
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
  let a = p.flag(name="aaa", short='a')
  let b = p.flag(name="bbb", short='b')
  let c = p.flag(name="ccc", short='c')
  ignore(p.parse(["-abc"]))
  inspect(p.get(a), content="Some(true)")
  inspect(p.get(b), content="Some(true)")
  inspect(p.get(c), content="Some(true)")
}

///|
test "short combining with value at end" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse(["-vp3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining value next arg" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse(["-vp", "3000"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(port), content="Some(3000)")
}

///|
test "short combining with string value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  let host = p.string_opt(name="host", default="localhost", short='H')
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
  let _a = p.flag(name="aaa", short='a')
  let result : Result[_, _] = try? p.parse(["-ax"])
  inspect(result is Err(_), content="true")
}

///|
test "short combining all flags" {
  let p = Parser::new()
  let e = p.flag(name="errexit", short='e')
  let u = p.flag(name="nounset", short='u')
  let o = p.flag(name="ooo", short='o')
  ignore(p.parse(["-euo"]))
  inspect(p.get(e), content="Some(true)")
  inspect(p.get(u), content="Some(true)")
  inspect(p.get(o), content="Some(true)")
}

///|
test "count basic" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse(["--verbose", "--verbose", "--verbose"]))
  inspect(p.get(verbose), content="Some(3)")
}

///|
test "count default zero" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse([]))
  inspect(p.get(verbose), content="Some(0)")
}

///|
test "count short" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse(["-v", "-v"]))
  inspect(p.get(verbose), content="Some(2)")
}

///|
test "count short combining -vvv" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse(["-vvv"]))
  inspect(p.get(verbose), content="Some(3)")
}

///|
test "count reset with no-prefix" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse(["-vvv", "--no-verbose", "-v"]))
  inspect(p.get(verbose), content="Some(1)")
}

///|
test "complex short combining: count + int + flag" {
  let p = Parser::new()
  let c = p.count(name="ccc", short='c')
  let a_opt = p.int_opt(name="aaa", default=0, short='A')
  let g = p.flag(name="ggg", short='g')
  // -cA1gcc → c(count) A(int=1) g(flag) c(count) c(count)
  ignore(p.parse(["-cA1gcc"]))
  inspect(p.get(c), content="Some(3)")
  inspect(p.get(a_opt), content="Some(1)")
  inspect(p.get(g), content="Some(true)")
}

///|
test "complex short combining: flags and int" {
  let p = Parser::new()
  let v = p.flag(name="verbose", short='v')
  let a_opt = p.int_opt(name="after", default=0, short='A')
  let b_opt = p.int_opt(name="before", default=0, short='B')
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
  let _ = p.flag(name="verbose", short='v', description="Enable verbose output")
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
  let _ = p.flag(name="verbose", short='v', description="Enable verbose output")
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
  let _ = p.flag(name="verbose", short='v', description="Verbose")
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
  let _ = p.flag(name="verbose", short='v', description="Enable verbose output")
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
  let nums = p.append_int(name="num", short='n')
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
  let v = p.flag(name="verbose", short='v')
  let nums = p.append_int(name="num", short='n')
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

// === consumed=0 + enum or パターン PoC ===

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
  committed : Ref[Bool],
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
        committed.val = true
      })
    },
    reset: fn() {
      cell.val = Auto
      committed.val = false
    },
  }
}

///|
/// ヘルパー: --color rgb R G B → RGB(r,g,b) (consumed=5) の ExactNode
fn make_color_rgb_node(
  opt_name : String,
  cell : Ref[TestColor],
  committed : Ref[Bool],
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
            committed.val = true
          })
        _ => Reject
      }
    },
    reset: fn() {
      cell.val = Auto
      committed.val = false
    },
  }
}

///|
/// ヘルパー: --color だけ (consumed=1) → implicit value
fn make_color_implicit_node(
  opt_name : String,
  implicit : TestColor,
  cell : Ref[TestColor],
  committed : Ref[Bool],
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
        committed.val = true
      })
    },
    reset: fn() {
      cell.val = Auto
      committed.val = false
    },
  }
}

///|
/// ヘルパー: consumed=0 の default fallback ノード
fn make_color_default_node(
  default_ : TestColor,
  cell : Ref[TestColor],
  committed : Ref[Bool],
) -> ExactNode {
  ExactNode::{
    name: "",
    needs_value: false,
    try_reduce: fn(_args : Array[String], _pos : Int) -> TryResult {
      // 既に consumed>0 で commit 済みなら Reject
      if committed.val {
        return Reject
      }
      Accept(consumed=0, commit=fn() { cell.val = default_ })
    },
    reset: fn() {
      cell.val = Auto
      committed.val = false
    },
  }
}

///|
/// 全ノードを Parser に登録するヘルパー
fn setup_color_opt(p : Parser) -> (Ref[TestColor], Ref[Bool]) {
  let cell : Ref[TestColor] = { val: Auto }
  let committed : Ref[Bool] = { val: false }
  let nodes : Array[ExactNode] = [
    make_color_exact("--color", "red", Red, cell, committed),
    make_color_exact("--color", "green", Green, cell, committed),
    make_color_exact("--color", "blue", Blue, cell, committed),
    make_color_rgb_node("--color", cell, committed),
    make_color_implicit_node("--color", Red, cell, committed),
    make_color_default_node(Auto, cell, committed),
  ]
  for node in nodes {
    p.nodes.push(node)
  }
  (cell, committed)
}

///|
test "enum or: --color red" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  ignore(p.parse(["--color", "red"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: --color green" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  ignore(p.parse(["--color", "green"]))
  inspect(cell.val, content="Green")
}

///|
test "enum or: --color rgb 255 128 0" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  ignore(p.parse(["--color", "rgb", "255", "128", "0"]))
  inspect(cell.val, content="RGB(255, 128, 0)")
}

///|
test "enum or: --color (implicit → Red)" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  ignore(p.parse(["--color"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: no --color (consumed=0 default → Auto)" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  ignore(p.parse([]))
  inspect(cell.val, content="Auto")
}

///|
test "enum or: --color red wins over implicit" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  ignore(p.parse(["--color", "red"]))
  inspect(cell.val, content="Red")
}

///|
test "enum or: --color with other flag → implicit" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "--verbose"]))
  inspect(cell.val, content="Red")
  inspect(verbose.get(), content="Some(true)")
}

///|
test "enum or: --color rgb with args then other opt" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--color", "rgb", "10", "20", "30", "--verbose"]))
  inspect(cell.val, content="RGB(10, 20, 30)")
  inspect(verbose.get(), content="Some(true)")
}

///|
test "enum or: consumed=0 default not used when --color specified" {
  let p = Parser::new()
  let (cell, _) = setup_color_opt(p)
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
test "string_opt choices+implicit: multiple opts with consumed=0" {
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
  let verbose = p.flag(name="verbose", short='v')
  let color = p.string_opt(
    name="color",
    default="auto",
    short='c',
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
  let verbose = p.flag(name="verbose", short='v')
  let color = p.string_opt(
    name="color",
    default="auto",
    short='c',
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
    short='c',
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
  let verbose = p.flag(name="verbose", short='v')
  let port = p.int_opt(
    name="port",
    default=8080,
    short='p',
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
