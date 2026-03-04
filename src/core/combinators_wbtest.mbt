///|
test "flag creates Opt with correct meta" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose", help="Enable verbose output")
  assert_eq(verbose.meta.name, "verbose")
  assert_eq(verbose.meta.kind, Kind::Option)
  assert_eq(verbose.meta.help, "Enable verbose output")
  assert_eq(verbose.id, 1)
}

///|
test "flag reducer - Value(None) returns true" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let ctx = ReduceCtx::{ current: false, action: Value(None) }
  let result = (verbose.reducer)(ctx)
  assert_eq(result, Some(true))
}

///|
test "flag reducer - Negate returns false" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let ctx = ReduceCtx::{ current: true, action: Negate }
  let result = (verbose.reducer)(ctx)
  assert_eq(result, Some(false))
}

///|
test "flag reducer - Value(Some(_)) with invalid value raises ParseError" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let ctx = ReduceCtx::{ current: false, action: Value(Some("x")) }
  let result : Result[Bool?, _] = try { Ok((verbose.reducer)(ctx)) } catch {
    ParseError::Usage(kind, _, _) => Err(kind)
    _ => Err(ErrorKind::InvalidValue)
  }
  assert_eq(result, Err(ErrorKind::InvalidValue))
}

///|
test "string creates Opt with correct meta" {
  let p = Parser::new()
  let output = p.string(name="output", value_name="FILE")
  assert_eq(output.meta.name, "output")
  assert_eq(output.meta.kind, Kind::Option)
  assert_eq(output.meta.value_name, "FILE")
}

///|
test "string default value_name is STRING" {
  let p = Parser::new()
  let output = p.string(name="output")
  assert_eq(output.meta.value_name, "STRING")
}

///|
test "string reducer - Value(Some(s)) returns Some(Some(s))" {
  let p = Parser::new()
  let output = p.string(name="output")
  let ctx : ReduceCtx[String?] = {
    current: None,
    action: Value(Some("out.txt")),
  }
  let result = (output.reducer)(ctx)
  assert_eq(result, Some(Some("out.txt")))
}

///|
test "string reducer - Negate returns Some(None)" {
  let p = Parser::new()
  let output = p.string(name="output")
  let ctx : ReduceCtx[String?] = { current: Some("old"), action: Negate }
  let result = (output.reducer)(ctx)
  assert_eq(result, Some(None))
}

///|
test "string reducer - Value(None) returns None" {
  let p = Parser::new()
  let output = p.string(name="output")
  let ctx : ReduceCtx[String?] = { current: None, action: Value(None) }
  let result = (output.reducer)(ctx)
  assert_eq(result, None)
}

///|
test "int creates Opt with correct meta" {
  let p = Parser::new()
  let port = p.int(name="port")
  assert_eq(port.meta.name, "port")
  assert_eq(port.meta.value_name, "INT")
}

///|
test "int reducer - valid int" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = { current: None, action: Value(Some("8080")) }
  let result = (port.reducer)(ctx)
  assert_eq(result, Some(Some(8080)))
}

///|
test "int reducer - Negate returns Some(None)" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = { current: Some(80), action: Negate }
  let result = (port.reducer)(ctx)
  assert_eq(result, Some(None))
}

///|
test "int reducer - invalid int raises ParseError" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = { current: None, action: Value(Some("abc")) }
  let result : Result[Int??, _] = Ok((port.reducer)(ctx)) catch { _ => Err(()) }
  match result {
    Err(_) => ()
    Ok(_) => fail("expected ParseError")
  }
}

///|
test "int reducer - Value(None) returns None" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = { current: None, action: Value(None) }
  let result = (port.reducer)(ctx)
  assert_eq(result, None)
}

///|
test "positional creates Opt with Positional kind" {
  let p = Parser::new()
  let file = p.positional(name="file")
  assert_eq(file.meta.kind, Kind::Positional)
  assert_eq(file.meta.required, true)
}

///|
test "positional default value_name is uppercase name" {
  let p = Parser::new()
  let file = p.positional(name="file")
  assert_eq(file.meta.value_name, "FILE")
}

///|
test "positional reducer - Value(Some(s)) returns Some(Some(s))" {
  let p = Parser::new()
  let file = p.positional(name="file")
  let ctx : ReduceCtx[String?] = {
    current: None,
    action: Value(Some("test.txt")),
  }
  let result = (file.reducer)(ctx)
  assert_eq(result, Some(Some("test.txt")))
}

///|
test "positional reducer - Value(None) returns None" {
  let p = Parser::new()
  let file = p.positional(name="file")
  let ctx : ReduceCtx[String?] = { current: None, action: Value(None) }
  let result = (file.reducer)(ctx)
  assert_eq(result, None)
}

///|
test "positional reducer - Negate returns None" {
  let p = Parser::new()
  let file = p.positional(name="file")
  let ctx : ReduceCtx[String?] = { current: Some("old"), action: Negate }
  let result = (file.reducer)(ctx)
  assert_eq(result, None)
}

///|
test "cmd creates Opt with Command kind" {
  let p = Parser::new()
  let serve = p.cmd(name="serve", children=Opts::Array([]))
  assert_eq(serve.meta.kind, Kind::Command)
  assert_eq(serve.meta.name, "serve")
}

///|
test "cmd reducer - Value(None) returns Some(true)" {
  let p = Parser::new()
  let serve = p.cmd(name="serve", children=Opts::Array([]))
  let ctx = ReduceCtx::{ current: false, action: Value(None) }
  let result = (serve.reducer)(ctx)
  assert_eq(result, Some(true))
}

///|
test "cmd reducer - other returns None" {
  let p = Parser::new()
  let serve = p.cmd(name="serve", children=Opts::Array([]))
  let ctx = ReduceCtx::{ current: false, action: Value(Some("x")) }
  let result = (serve.reducer)(ctx)
  assert_eq(result, None)
}

///|
test "cmd reducer - Negate returns None" {
  let p = Parser::new()
  let serve = p.cmd(name="serve", children=Opts::Array([]))
  let ctx = ReduceCtx::{ current: false, action: Negate }
  let result = (serve.reducer)(ctx)
  assert_eq(result, None)
}

///|
test "Parser ID increments correctly" {
  let p = Parser::new()
  let _ = p.flag(name="a")
  let b = p.flag(name="b")
  assert_eq(b.id, 2)
}

///|
test "getter returns current value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  assert_eq((verbose.getter)(0), false)
}

///|
test "setter updates value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  (verbose.setter)(0, true)
  assert_eq((verbose.getter)(0), true)
}

///|
test "opts helper wraps in Array" {
  let p = Parser::new()
  let v = p.flag(name="verbose")
  let tree = opts([v.to_opts()])
  match tree {
    Array(items) => assert_eq(items.length(), 1)
    _ => fail("expected Array")
  }
}

///|
test "opts helper with multiple items" {
  let p = Parser::new()
  let v = p.flag(name="verbose")
  let o = p.string(name="output")
  let tree = opts([v.to_opts(), o.to_opts()])
  match tree {
    Array(items) => assert_eq(items.length(), 2)
    _ => fail("expected Array")
  }
}

///|
test "to_opts creates Node with correct meta" {
  let p = Parser::new()
  let v = p.flag(name="verbose")
  let node = v.to_opts()
  match node {
    Node(erased) => assert_eq(erased.meta.name, "verbose")
    _ => fail("expected Node")
  }
}

///|
test "flag with all options" {
  let p = Parser::new()
  let verbose = p.flag(
    name="verbose",
    help="Enable verbose",
    shorts=[{ char: 'v' }],
    aliases=[{ name: "verb", deprecated: false }],
    inversion=Some(FlagInversion::No),
    env=Some("VERBOSE"),
    auto_env=Some(true),
    visibility=Visibility::Advanced,
    global=true,
    greedy=true,
  )
  assert_eq(verbose.meta.shorts, [{ char: 'v' }])
  assert_eq(verbose.meta.aliases, [{ name: "verb", deprecated: false }])
  assert_eq(verbose.meta.inversion, Some(FlagInversion::No))
  assert_eq(verbose.meta.env, Some("VERBOSE"))
  assert_eq(verbose.meta.auto_env, Some(true))
  assert_eq(verbose.meta.visibility, Visibility::Advanced)
  assert_eq(verbose.meta.global, true)
  assert_eq(verbose.meta.greedy, true)
}

///|
test "string with choices" {
  let p = Parser::new()
  let format = p.string(name="format", choices=["json", "yaml", "toml"])
  assert_eq(format.meta.choices, ["json", "yaml", "toml"])
}

///|
test "int with required" {
  let p = Parser::new()
  let port = p.int(name="port", required=true)
  assert_eq(port.meta.required, true)
}

// --- C6: ErasedNode try_reduce / commit_reduce / reset_to_initial tests ---

///|
test "ErasedNode try_reduce returns Accept without side effects" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let node = verbose.to_opts()
  match node {
    Node(erased) => {
      let rm = ResultMap::{ id: 0, clone_fns: {} }
      let result = (erased.try_reduce)(Value(None), rm)
      match result {
        Accept(..) => {
          // try_reduce は投機実行なので store は変わっていないはず
          assert_eq((verbose.getter)(0), false)
        }
        _ => fail("expected Accept")
      }
    }
    _ => fail("expected Node")
  }
}

///|
test "ErasedNode commit_reduce applies the value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let node = verbose.to_opts()
  match node {
    Node(erased) => {
      let rm = ResultMap::{ id: 0, clone_fns: {} }
      let result = (erased.try_reduce)(Value(None), rm)
      match result {
        Accept(result~, ..) => {
          (erased.commit_reduce)(result, rm)
          assert_eq((verbose.getter)(0), true)
        }
        _ => fail("expected Accept")
      }
    }
    _ => fail("expected Node")
  }
}

///|
test "ErasedNode try_reduce returns Error for invalid flag value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let node = verbose.to_opts()
  match node {
    Node(erased) => {
      let rm = ResultMap::{ id: 0, clone_fns: {} }
      let result = (erased.try_reduce)(Value(Some("unexpected")), rm)
      match result {
        Error(_) => ()
        _ => fail("expected Error")
      }
    }
    _ => fail("expected Node")
  }
}

///|
test "ErasedNode reset_to_initial restores initial value" {
  let p = Parser::new()
  let verbose = p.flag(name="verbose")
  let node = verbose.to_opts()
  match node {
    Node(erased) => {
      let rm = ResultMap::{ id: 0, clone_fns: {} }
      // commit a value first
      let result = (erased.try_reduce)(Value(None), rm)
      match result {
        Accept(result~, ..) => (erased.commit_reduce)(result, rm)
        _ => fail("expected Accept")
      }
      assert_eq((verbose.getter)(0), true)
      // reset
      (erased.reset_to_initial)(rm)
      assert_eq((verbose.getter)(0), false)
    }
    _ => fail("expected Node")
  }
}

// --- C7: int boundary value tests ---

///|
test "int reducer - zero" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = { current: None, action: Value(Some("0")) }
  let result = (port.reducer)(ctx)
  assert_eq(result, Some(Some(0)))
}

///|
test "int reducer - negative value" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = { current: None, action: Value(Some("-1")) }
  let result = (port.reducer)(ctx)
  assert_eq(result, Some(Some(-1)))
}

///|
test "int reducer - max int" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = {
    current: None,
    action: Value(Some("2147483647")),
  }
  let result = (port.reducer)(ctx)
  assert_eq(result, Some(Some(2147483647)))
}

///|
test "int reducer - empty string raises ParseError" {
  let p = Parser::new()
  let port = p.int(name="port")
  let ctx : ReduceCtx[Int?] = { current: None, action: Value(Some("")) }
  let result : Result[Int??, _] = Ok((port.reducer)(ctx)) catch { _ => Err(()) }
  match result {
    Err(_) => ()
    Ok(_) => fail("expected ParseError for empty string")
  }
}

// --- C2: TryReduceResult::Error test via ErasedNode ---

///|
test "ErasedNode try_reduce returns Error for invalid int" {
  let p = Parser::new()
  let port = p.int(name="port")
  let node = port.to_opts()
  match node {
    Node(erased) => {
      let rm = ResultMap::{ id: 0, clone_fns: {} }
      let result = (erased.try_reduce)(Value(Some("abc")), rm)
      match result {
        Error(ParseError::Usage(ErrorKind::InvalidValue, msg, ctx)) => {
          assert_true(msg.contains("invalid integer"))
          assert_eq(ctx.option_name, "port")
        }
        _ => fail("expected Error(ParseError::Usage(InvalidValue, ...))")
      }
    }
    _ => fail("expected Node")
  }
}

// --- W8: string empty string test ---

///|
test "string reducer - empty string is accepted" {
  let p = Parser::new()
  let output = p.string(name="output")
  let ctx : ReduceCtx[String?] = { current: None, action: Value(Some("")) }
  let result = (output.reducer)(ctx)
  assert_eq(result, Some(Some("")))
}

// --- C3: cmd children test ---

///|
test "cmd children are preserved in ErasedNode" {
  let p = Parser::new()
  let port = p.int(name="port")
  let host = p.string(name="host")
  let serve = p.cmd(
    name="serve",
    children=opts([port.to_opts(), host.to_opts()]),
  )
  let node = serve.to_opts()
  match node {
    Node(erased) => {
      let children = (erased.children)()
      assert_eq(children.length(), 2)
      assert_eq(children[0].meta.name, "port")
      assert_eq(children[1].meta.name, "host")
    }
    _ => fail("expected Node")
  }
}

///|
test "cmd with empty children" {
  let p = Parser::new()
  let serve = p.cmd(name="serve", children=Opts::Array([]))
  let node = serve.to_opts()
  match node {
    Node(erased) => {
      let children = (erased.children)()
      assert_eq(children.length(), 0)
    }
    _ => fail("expected Node")
  }
}

///|
test "try_reduce is speculative - getter unchanged until commit" {
  let p = Parser::new()
  let port = p.int(name="port")
  // setter で初期値を 0 に設定
  (port.setter)(0, Some(0))
  let node = port.to_opts()
  match node {
    Node(erased) => {
      let rm = ResultMap::{ id: 0, clone_fns: {} }
      // 初期値を確認
      assert_eq((port.getter)(0), Some(0))
      // try_reduce で Value(Some("42")) を渡す
      let result = (erased.try_reduce)(Value(Some("42")), rm)
      match result {
        Accept(..) => {
          // try_reduce 後もまだ getter は初期値のまま
          assert_eq((port.getter)(0), Some(0))
        }
        _ => fail("expected Accept")
      }
      // commit して初めて値が変わる
      match result {
        Accept(result~, ..) => {
          (erased.commit_reduce)(result, rm)
          assert_eq((port.getter)(0), Some(42))
        }
        _ => fail("expected Accept")
      }
    }
    _ => fail("expected Node")
  }
}

///|
test "int reducer - min and max int boundary values" {
  let p = Parser::new()
  let port = p.int(name="port")
  // min value
  let min_str = @int.min_value.to_string()
  let ctx_min : ReduceCtx[Int?] = { current: None, action: Value(Some(min_str)) }
  let result_min = (port.reducer)(ctx_min)
  assert_eq(result_min, Some(Some(@int.min_value)))
  // max value
  let max_str = @int.max_value.to_string()
  let ctx_max : ReduceCtx[Int?] = { current: None, action: Value(Some(max_str)) }
  let result_max = (port.reducer)(ctx_max)
  assert_eq(result_max, Some(Some(@int.max_value)))
}

///|
test "Thunk initial - reset_to_initial restores thunk value" {
  let p = Parser::new()
  let base = p.int(name="port")
  // Thunk(fn() { 99 }) を initial とする Opt を構築
  let port : Opt[Int?] = { ..base, initial: Thunk(fn() { Some(99) }) }
  let node = port.to_opts()
  match node {
    Node(erased) => {
      let rm = ResultMap::{ id: 0, clone_fns: {} }
      // 初期値を確認（Thunk は to_opts 内で評価され setter で書き込まれる）
      // to_opts で initial_val が評価されるが、store への書き込みは reset_to_initial で行われる
      // まず reset_to_initial で Thunk 由来の値を設定
      (erased.reset_to_initial)(rm)
      assert_eq((port.getter)(0), Some(99))
      // try_reduce → commit で値を42に変更
      let result = (erased.try_reduce)(Value(Some("42")), rm)
      match result {
        Accept(result~, ..) => (erased.commit_reduce)(result, rm)
        _ => fail("expected Accept")
      }
      assert_eq((port.getter)(0), Some(42))
      // reset_to_initial で Thunk の値(99)に戻る
      (erased.reset_to_initial)(rm)
      assert_eq((port.getter)(0), Some(99))
    }
    _ => fail("expected Node")
  }
}

///|
test "opts_to_erased_nodes flattens nested Opts" {
  let p = Parser::new()
  let a = p.flag(name="a")
  let b = p.flag(name="b")
  let c = p.flag(name="c")
  let nested = opts([opts([a.to_opts(), b.to_opts()]), c.to_opts()])
  let nodes = opts_to_erased_nodes(nested)
  assert_eq(nodes.length(), 3)
  assert_eq(nodes[0].meta.name, "a")
  assert_eq(nodes[1].meta.name, "b")
  assert_eq(nodes[2].meta.name, "c")
}
