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
  let result : Result[ParseResult, _] = try? p.parse(["--unknown"])
  inspect(result.is_err(), content="true")
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
  inspect(p.get(host), content=(
    #|Some("example.com")
  ))
}

///|
test "string option default" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  ignore(p.parse([]))
  inspect(p.get(host), content=(
    #|Some("localhost")
  ))
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
  let result : Result[ParseResult, _] = try? p.parse(["--port", "abc"])
  inspect(result.is_err(), content="true")
}

///|
test "missing value error" {
  let p = Parser::new()
  let _host = p.string_opt(name="host", default="localhost")
  let result : Result[ParseResult, _] = try? p.parse(["--host"])
  inspect(result.is_err(), content="true")
}

///|
test "int and string combined" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  let host = p.string_opt(name="host", default="localhost")
  let verbose = p.flag(name="verbose")
  ignore(p.parse(["--port", "3000", "--verbose", "--host", "example.com"]))
  inspect(p.get(port), content="Some(3000)")
  inspect(p.get(host), content=(
    #|Some("example.com")
  ))
  inspect(p.get(verbose), content="Some(true)")
}

///|
test "no-prefix resets string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  ignore(p.parse(["--host", "example.com", "--no-host"]))
  inspect(p.get(host), content=(
    #|Some("localhost")
  ))
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
  inspect(p.get(host), content=(
    #|Some("example.com")
  ))
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
  let result : Result[ParseResult, _] = try? p.parse(["--port=abc"])
  inspect(result.is_err(), content="true")
}

///|
test "equals syntax mixed with space syntax" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  let host = p.string_opt(name="host", default="localhost")
  ignore(p.parse(["--port=3000", "--host", "example.com"]))
  inspect(p.get(port), content="Some(3000)")
  inspect(p.get(host), content=(
    #|Some("example.com")
  ))
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
  let result : Result[ParseResult, _] = try? p.parse(["--num", "abc"])
  inspect(result.is_err(), content="true")
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
  inspect(p.get(file), content=(
    #|Some("input.txt")
  ))
}

///|
test "positional with option before" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file")
  ignore(p.parse(["--verbose", "input.txt"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(file), content=(
    #|Some("input.txt")
  ))
}

///|
test "positional with option after" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file")
  ignore(p.parse(["input.txt", "--verbose"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(file), content=(
    #|Some("input.txt")
  ))
}

///|
test "positional default empty" {
  let p = Parser::new()
  let file = p.positional(name="file")
  ignore(p.parse([]))
  inspect(p.get(file), content=(
    #|Some("")
  ))
}

///|
test "serial positional" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let output = p.positional(name="output")
  ignore(p.parse(["input.txt", "output.txt"]))
  inspect(p.get(input), content=(
    #|Some("input.txt")
  ))
  inspect(p.get(output), content=(
    #|Some("output.txt")
  ))
}

///|
test "serial positional with option between" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let input = p.positional(name="input")
  let output = p.positional(name="output")
  ignore(p.parse(["input.txt", "--verbose", "output.txt"]))
  inspect(p.get(verbose), content="Some(true)")
  inspect(p.get(input), content=(
    #|Some("input.txt")
  ))
  inspect(p.get(output), content=(
    #|Some("output.txt")
  ))
}

///|
test "serial positional partial" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let _output = p.positional(name="output")
  ignore(p.parse(["input.txt"]))
  inspect(p.get(input), content=(
    #|Some("input.txt")
  ))
}

///|
test "serial three positionals" {
  let p = Parser::new()
  let a = p.positional(name="a")
  let b = p.positional(name="b")
  let c = p.positional(name="c")
  ignore(p.parse(["x", "y", "z"]))
  inspect(p.get(a), content=(
    #|Some("x")
  ))
  inspect(p.get(b), content=(
    #|Some("y")
  ))
  inspect(p.get(c), content=(
    #|Some("z")
  ))
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
  inspect(p.get(input), content=(
    #|Some("input.txt")
  ))
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
  let result : Result[ParseResult, _] = try? p.parse(["serve", "--unknown"])
  inspect(result.is_err(), content="true")
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
    Some(opt) => inspect(p.get(opt), content=(
      #|Some("origin")
    ))
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
    Some(opt) => inspect(p.get(opt), content=(
      #|Some("https://example.com")
    ))
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
    Some(opt) => inspect(p.get(opt), content=(
      #|Some("origin")
    ))
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
    Some(serve_result) => {
      inspect(serve_result.get(port_opt.val.unwrap()), content="Some(3000)")
    }
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
  inspect(result.child("build").is_empty(), content="true")
}

///|
test "ParseResult as_map with subcommand" {
  let p = Parser::new()
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=8080)
  })
  let result = p.parse(["serve"])
  inspect(result.as_map().is_empty(), content="false")
}

///|
test "ParseResult as_map without subcommand" {
  let p = Parser::new()
  let _verbose = p.flag(name="verbose")
  let result = p.parse(["--verbose"])
  // cmd 登録がなければ One のまま
  inspect(result.as_map().is_empty(), content="true")
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
    Some(remote_result) => {
      match remote_result.child("add") {
        Some(add_result) => {
          inspect(add_result.get(name_opt.val.unwrap()), content=(
            #|Some("origin")
          ))
        }
        None => abort("add child should exist")
      }
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
  inspect!(verbose.get(), content="None")
  inspect!(port.get(), content="None")
  // parse 後は Some
  ignore(p.parse!(["--verbose", "--port", "3000"]))
  inspect!(verbose.get(), content="Some(true)")
  inspect!(port.get(), content="Some(3000)")
}

///|
test "alias for flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v"])
  ignore(p.parse!(["--v"]))
  inspect!(p.get(verbose), content="Some(true)")
}

///|
test "alias no-prefix" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v"])
  ignore(p.parse!(["--v", "--no-v"]))
  inspect!(p.get(verbose), content="Some(false)")
}

///|
test "alias for string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", aliases=["H"])
  ignore(p.parse!(["--H", "example.com"]))
  inspect!(p.get(host), content=(
    #|Some("example.com")
  ))
}

///|
test "alias for int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, aliases=["p"])
  ignore(p.parse!(["--p", "3000"]))
  inspect!(p.get(port), content="Some(3000)")
}

///|
test "multiple aliases" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", aliases=["v", "verb"])
  ignore(p.parse!(["--verb"]))
  inspect!(p.get(verbose), content="Some(true)")
}

///|
test "alias with equals syntax" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, aliases=["p"])
  ignore(p.parse!(["--p=3000"]))
  inspect!(p.get(port), content="Some(3000)")
}

///|
test "opt.get with subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  ignore(p.parse!(["serve", "--verbose", "--port", "3000"]))
  // global flag は親の parsed で判定
  inspect!(verbose.get(), content="Some(true)")
  // 子パーサの opt も子の parsed で判定
  inspect!(port_opt.val.unwrap().get(), content="Some(3000)")
}

///|
test "short flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  ignore(p.parse!(["-v"]))
  inspect!(p.get(verbose), content="Some(true)")
}

///|
test "short int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse!(["-p", "3000"]))
  inspect!(p.get(port), content="Some(3000)")
}

///|
test "short string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost", short='H')
  ignore(p.parse!(["-H", "example.com"]))
  inspect!(p.get(host), content=(
    #|Some("example.com")
  ))
}

///|
test "short with long mixed" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse!(["-v", "--port", "3000"]))
  inspect!(p.get(verbose), content="Some(true)")
  inspect!(p.get(port), content="Some(3000)")
}

///|
test "short append" {
  let p = Parser::new()
  let tags = p.append_string(name="tag", short='t')
  ignore(p.parse!(["-t", "a", "-t", "b"]))
  inspect!(p.get(tags), content=(
    #|Some(["a", "b"])
  ))
}

///|
test "short flag combining" {
  let p = Parser::new()
  let a = p.flag(name="aaa", short='a')
  let b = p.flag(name="bbb", short='b')
  let c = p.flag(name="ccc", short='c')
  ignore(p.parse!(["-abc"]))
  inspect!(p.get(a), content="Some(true)")
  inspect!(p.get(b), content="Some(true)")
  inspect!(p.get(c), content="Some(true)")
}

///|
test "short combining with value at end" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse!(["-vp3000"]))
  inspect!(p.get(verbose), content="Some(true)")
  inspect!(p.get(port), content="Some(3000)")
}

///|
test "short combining value next arg" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  let port = p.int_opt(name="port", default=8080, short='p')
  ignore(p.parse!(["-vp", "3000"]))
  inspect!(p.get(verbose), content="Some(true)")
  inspect!(p.get(port), content="Some(3000)")
}

///|
test "short combining with string value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", short='v')
  let host = p.string_opt(name="host", default="localhost", short='H')
  ignore(p.parse!(["-vHexample.com"]))
  inspect!(p.get(verbose), content="Some(true)")
  inspect!(p.get(host), content=(
    #|Some("example.com")
  ))
}

///|
test "short combining unknown char error" {
  let p = Parser::new()
  let _a = p.flag(name="aaa", short='a')
  let result : Result[ParseResult, _] = try? p.parse(["-ax"])
  inspect!(result.is_err(), content="true")
}

///|
test "short combining all flags" {
  let p = Parser::new()
  let e = p.flag(name="errexit", short='e')
  let u = p.flag(name="nounset", short='u')
  let o = p.flag(name="ooo", short='o')
  ignore(p.parse!(["-euo"]))
  inspect!(p.get(e), content="Some(true)")
  inspect!(p.get(u), content="Some(true)")
  inspect!(p.get(o), content="Some(true)")
}

///|
test "count basic" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse!(["--verbose", "--verbose", "--verbose"]))
  inspect!(p.get(verbose), content="Some(3)")
}

///|
test "count default zero" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse!([]))
  inspect!(p.get(verbose), content="Some(0)")
}

///|
test "count short" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse!(["-v", "-v"]))
  inspect!(p.get(verbose), content="Some(2)")
}

///|
test "count short combining -vvv" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse!(["-vvv"]))
  inspect!(p.get(verbose), content="Some(3)")
}

///|
test "count reset with no-prefix" {
  let p = Parser::new()
  let verbose = p.count(name="verbose", short='v')
  ignore(p.parse!(["-vvv", "--no-verbose", "-v"]))
  inspect!(p.get(verbose), content="Some(1)")
}

///|
test "complex short combining: count + int + flag" {
  let p = Parser::new()
  let c = p.count(name="ccc", short='c')
  let a_opt = p.int_opt(name="aaa", default=0, short='A')
  let g = p.flag(name="ggg", short='g')
  // -cA1gcc → c(count) A(int=1) g(flag) c(count) c(count)
  ignore(p.parse!(["-cA1gcc"]))
  inspect!(p.get(c), content="Some(3)")
  inspect!(p.get(a_opt), content="Some(1)")
  inspect!(p.get(g), content="Some(true)")
}

///|
test "complex short combining: flags and int" {
  let p = Parser::new()
  let v = p.flag(name="verbose", short='v')
  let a_opt = p.int_opt(name="after", default=0, short='A')
  let b_opt = p.int_opt(name="before", default=0, short='B')
  // -vA1 -B1 なら動く
  ignore(p.parse!(["-vA1", "-B1"]))
  inspect!(p.get(v), content="Some(true)")
  inspect!(p.get(a_opt), content="Some(1)")
  inspect!(p.get(b_opt), content="Some(1)")
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
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "short help flag raises HelpRequested" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Enable verbose")
  let result : Result[ParseResult, _] = try? p.parse(["-h"])
  match result {
    Err(HelpRequested(_)) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "HelpRequested text contains flag description" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", short='v', description="Enable verbose output")
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
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
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
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
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
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
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
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
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("-v, --verbose"), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "subcommand help shows own scope" {
  let p = Parser::new()
  let _ = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=8080, description="Set port")
  }, description="Start server")
  let result : Result[ParseResult, _] = try? p.parse(["serve", "--help"])
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
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
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
  let result : Result[ParseResult, _] = try? p.parse(["--help"])
  match result {
    Err(HelpRequested(text)) => {
      inspect(text.contains("My awesome CLI"), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "parse error includes help_text" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", short='v', description="Enable verbose output")
  let _ = p.int_opt(name="port", default=8080, description="Set port number")
  let result : Result[ParseResult, _] = try? p.parse(["--unknown"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message, content=(
        #|unexpected argument: --unknown
      ))
      // help_text が空でないことを確認
      inspect(info.help_text.is_empty(), content="false")
      // help_text にオプション情報が含まれること
      inspect(info.help_text.contains("--verbose"), content="true")
      inspect(info.help_text.contains("--port"), content="true")
    }
    _ => abort("expected ParseError")
  }
}

///|
test "ParseErrorInfo::to_string format" {
  let info = ParseErrorInfo::{ message: "unexpected argument: --foo", help_text: "" }
  inspect(info.to_string(), content=(
    #|error: unexpected argument: --foo
  ))
  let info2 = ParseErrorInfo::{ message: "unexpected argument: --foo", help_text: "Options:\n  --help\n" }
  let expected = "error: unexpected argument: --foo\n\nOptions:\n  --help\n"
  inspect(info2.to_string() == expected, content="true")
}

///|
test "subcommand error has child help_text" {
  let p = Parser::new()
  let _ = p.flag(name="verbose", description="Verbose mode")
  let _ = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=8080, description="Set port")
  }, description="Start server")
  let result : Result[ParseResult, _] = try? p.parse(["serve", "--unknown"])
  match result {
    Err(ParseError(info)) => {
      inspect(info.message, content=(
        #|unexpected argument: --unknown
      ))
      // 子パーサ (serve) の help_text が設定されている
      inspect(info.help_text.contains("--port"), content="true")
      // 親パーサのオプション (--verbose) は含まれない（子のヘルプが優先）
      inspect(info.help_text.contains("--verbose"), content="false")
    }
    _ => abort("expected ParseError")
  }
}
