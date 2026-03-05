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
