///|
test "single flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  p.parse(["--verbose"])
  inspect(p.get(verbose), content="true")
}

///|
test "flag default is false" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  p.parse([])
  inspect(p.get(verbose), content="false")
}

///|
test "unknown arg raises error" {
  let p = Parser::new()
  let _verbose = p.flag(name="verbose")
  let result : Result[Unit, _] = try? p.parse(["--unknown"])
  inspect(result.is_err(), content="true")
}

///|
test "multiple flags" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let debug = p.flag(name="debug")
  p.parse(["--verbose", "--debug"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(debug), content="true")
}

///|
test "no-prefix negation" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  p.parse(["--verbose", "--no-verbose"])
  inspect(p.get(verbose), content="false")
}

///|
test "no-prefix with default true" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true)
  p.parse([])
  inspect(p.get(color), content="true")
}

///|
test "no-prefix resets to default" {
  let p = Parser::new()
  let color = p.flag(name="color", default=true)
  p.parse(["--no-color"])
  inspect(p.get(color), content="false")
}

///|
test "string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  p.parse(["--host", "example.com"])
  inspect(p.get(host), content="example.com")
}

///|
test "string option default" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  p.parse([])
  inspect(p.get(host), content="localhost")
}

///|
test "int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  p.parse(["--port", "3000"])
  inspect(p.get(port), content="3000")
}

///|
test "int option default" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  p.parse([])
  inspect(p.get(port), content="8080")
}

///|
test "int parse error" {
  let p = Parser::new()
  let _port = p.int_opt(name="port", default=8080)
  let result : Result[Unit, _] = try? p.parse(["--port", "abc"])
  inspect(result.is_err(), content="true")
}

///|
test "missing value error" {
  let p = Parser::new()
  let _host = p.string_opt(name="host", default="localhost")
  let result : Result[Unit, _] = try? p.parse(["--host"])
  inspect(result.is_err(), content="true")
}

///|
test "int and string combined" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  let host = p.string_opt(name="host", default="localhost")
  let verbose = p.flag(name="verbose")
  p.parse(["--port", "3000", "--verbose", "--host", "example.com"])
  inspect(p.get(port), content="3000")
  inspect(p.get(host), content="example.com")
  inspect(p.get(verbose), content="true")
}

///|
test "no-prefix resets string option" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  p.parse(["--host", "example.com", "--no-host"])
  inspect(p.get(host), content="localhost")
}

///|
test "no-prefix resets int option" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  p.parse(["--port", "3000", "--no-port"])
  inspect(p.get(port), content="8080")
}

///|
test "equals syntax for string" {
  let p = Parser::new()
  let host = p.string_opt(name="host", default="localhost")
  p.parse(["--host=example.com"])
  inspect(p.get(host), content="example.com")
}

///|
test "equals syntax for int" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  p.parse(["--port=3000"])
  inspect(p.get(port), content="3000")
}

///|
test "equals syntax int parse error" {
  let p = Parser::new()
  let _port = p.int_opt(name="port", default=8080)
  let result : Result[Unit, _] = try? p.parse(["--port=abc"])
  inspect(result.is_err(), content="true")
}

///|
test "equals syntax mixed with space syntax" {
  let p = Parser::new()
  let port = p.int_opt(name="port", default=8080)
  let host = p.string_opt(name="host", default="localhost")
  p.parse(["--port=3000", "--host", "example.com"])
  inspect(p.get(port), content="3000")
  inspect(p.get(host), content="example.com")
}

///|
test "equals syntax with flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let port = p.int_opt(name="port", default=8080)
  p.parse(["--verbose", "--port=3000"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(port), content="3000")
}

///|
test "append string" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  p.parse(["--tag", "a", "--tag", "b"])
  inspect(
    p.get(tags),
    content=(
      #|["a", "b"]
    ),
  )
}

///|
test "append string default empty" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  p.parse([])
  inspect(
    p.get(tags),
    content=(
      #|[]
    ),
  )
}

///|
test "append string negate" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  p.parse(["--tag", "a", "--no-tag", "--tag", "b"])
  inspect(
    p.get(tags),
    content=(
      #|["b"]
    ),
  )
}

///|
test "append int" {
  let p = Parser::new()
  let nums = p.append_int(name="num")
  p.parse(["--num", "1", "--num", "2", "--num", "3"])
  inspect(
    p.get(nums),
    content=(
      #|[1, 2, 3]
    ),
  )
}

///|
test "append int parse error" {
  let p = Parser::new()
  let _nums = p.append_int(name="num")
  let result : Result[Unit, _] = try? p.parse(["--num", "abc"])
  inspect(result.is_err(), content="true")
}

///|
test "append with equals syntax" {
  let p = Parser::new()
  let tags = p.append_string(name="tag")
  p.parse(["--tag=a", "--tag=b"])
  inspect(
    p.get(tags),
    content=(
      #|["a", "b"]
    ),
  )
}

///|
test "positional arg" {
  let p = Parser::new()
  let file = p.positional(name="file")
  p.parse(["input.txt"])
  inspect(p.get(file), content="input.txt")
}

///|
test "positional with option before" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file")
  p.parse(["--verbose", "input.txt"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(file), content="input.txt")
}

///|
test "positional with option after" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let file = p.positional(name="file")
  p.parse(["input.txt", "--verbose"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(file), content="input.txt")
}

///|
test "positional default empty" {
  let p = Parser::new()
  let file = p.positional(name="file")
  p.parse([])
  inspect(p.get(file), content="")
}

///|
test "serial positional" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let output = p.positional(name="output")
  p.parse(["input.txt", "output.txt"])
  inspect(p.get(input), content="input.txt")
  inspect(p.get(output), content="output.txt")
}

///|
test "serial positional with option between" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let input = p.positional(name="input")
  let output = p.positional(name="output")
  p.parse(["input.txt", "--verbose", "output.txt"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(input), content="input.txt")
  inspect(p.get(output), content="output.txt")
}

///|
test "serial positional partial" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let _output = p.positional(name="output")
  p.parse(["input.txt"])
  inspect(p.get(input), content="input.txt")
}

///|
test "serial three positionals" {
  let p = Parser::new()
  let a = p.positional(name="a")
  let b = p.positional(name="b")
  let c = p.positional(name="c")
  p.parse(["x", "y", "z"])
  inspect(p.get(a), content="x")
  inspect(p.get(b), content="y")
  inspect(p.get(c), content="z")
}

///|
test "rest collects remaining args" {
  let p = Parser::new()
  let files = p.rest(name="files")
  p.parse(["file1", "file2", "file3"])
  inspect(
    p.get(files),
    content=(
      #|["file1", "file2", "file3"]
    ),
  )
}

///|
test "rest default empty" {
  let p = Parser::new()
  let files = p.rest(name="files")
  p.parse([])
  inspect(p.get(files), content="[]")
}

///|
test "rest with option" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  p.parse(["--verbose", "file1", "file2"])
  inspect(p.get(verbose), content="true")
  inspect(
    p.get(files),
    content=(
      #|["file1", "file2"]
    ),
  )
}

///|
test "double dash forces positional" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  p.parse(["--verbose", "--", "--not-a-flag", "file1"])
  inspect(p.get(verbose), content="true")
  inspect(
    p.get(files),
    content=(
      #|["--not-a-flag", "file1"]
    ),
  )
}

///|
test "double dash with no rest args" {
  let p = Parser::new()
  let _verbose = p.flag(name="verbose")
  let files = p.rest(name="files")
  p.parse(["--"])
  inspect(p.get(files), content="[]")
}

///|
test "rest after positional" {
  let p = Parser::new()
  let input = p.positional(name="input")
  let extras = p.rest(name="extras")
  p.parse(["input.txt", "a", "b"])
  inspect(p.get(input), content="input.txt")
  inspect(
    p.get(extras),
    content=(
      #|["a", "b"]
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
  p.parse(["serve", "--port", "3000"])
  inspect(p.get(serve), content="true")
  inspect(p.get(port_opt.val.unwrap()), content="3000")
}

///|
test "subcommand not matched" {
  let p = Parser::new()
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  let build = p.cmd(name="build", setup=fn(_child) {  })
  p.parse(["build"])
  inspect(p.get(serve), content="false")
  inspect(p.get(build), content="true")
}

///|
test "subcommand with parent flag" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  p.parse(["--verbose", "serve", "--port", "3000"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(port_opt.val.unwrap()), content="3000")
}

///|
test "subcommand unknown option error" {
  let p = Parser::new()
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=8080)
  })
  let result : Result[Unit, _] = try? p.parse(["serve", "--unknown"])
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
  p.parse(["remote", "add", "--name", "origin"])
  match name_opt.val {
    Some(opt) => inspect(p.get(opt), content="origin")
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
  p.parse(["remote", "add", "--url", "https://example.com"])
  match url_opt.val {
    Some(opt) => inspect(p.get(opt), content="https://example.com")
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
  p.parse(["serve", "--verbose", "--port", "3000"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(port_opt.val.unwrap()), content="3000")
}

///|
test "global flag before subcommand" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", global=true)
  let port_opt : Ref[Opt[Int]?] = { val: None }
  let _serve = p.cmd(name="serve", setup=fn(child) {
    port_opt.val = Some(child.int_opt(name="port", default=8080))
  })
  p.parse(["--verbose", "serve", "--port", "3000"])
  inspect(p.get(verbose), content="true")
  inspect(p.get(port_opt.val.unwrap()), content="3000")
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
  p.parse(["remote", "add", "--verbose", "--name", "origin"])
  inspect(p.get(verbose), content="true")
  match name_opt.val {
    Some(opt) => inspect(p.get(opt), content="origin")
    None => abort("unreachable")
  }
}
