// cell_fn_execution_wbtest.mbt — DR-114 cell-fn execution, default placeholders, and observes order.

///|
fn def_error_kinds(
  errors : Array[@abi.DefError],
) -> Map[String, @abi.DefErrorKind] {
  let kinds : Map[String, @abi.DefErrorKind] = Map([])
  for error in errors {
    kinds.set(error.element, error.kind)
  }
  kinds
}

///|
test "default value normalizes to a typed internal set call" {
  let json = @json.parse(
    "{\"options\":[{\"name\":\"enabled\",\"type\":\"bool\",\"default\":true}]}",
  )
  match parse_definition(json) {
    Ok(ast) => {
      guard ast.root.entities is [entity] else { fail("expected one entity") }
      match entity.default_fn {
        Some(@abi.Typed(call)) => {
          assert_eq(call.name, "set")
          assert_eq(call.args, [@abi.Value(@abi.Bool(true))])
        }
        _ => fail("fixed default must lower to typed set(value)")
      }
    }
    Err(_) => fail("fixed default definition must lower")
  }
}

///|
test "default_fn observes dependency evaluates before its declaration-order predecessor" {
  let json = @json.parse(
    "{\"options\":[{\"name\":\"target\",\"type\":\"bool\",\"default_fn\":\"borrow:source\"},{\"name\":\"source\",\"type\":\"bool\",\"default\":true}]}",
  )
  match parse_definition(json) {
    Ok(ast) => {
      let parsed = parse_legacy(ast, [])
      match resolve_legacy(ast, parsed, []) {
        @engine.Success(bindings) => {
          assert_eq(@engine.element_value(bindings, [], "source"), Some("true"))
          assert_eq(@engine.element_value(bindings, [], "target"), Some("true"))
        }
        _ => fail("borrow default must resolve in dependency order")
      }
    }
    Err(_) => fail("borrow default definition must lower")
  }
}

///|
test "default_fn static failures classify unknown arity and sentinel output" {
  let json = @json.parse(
    "{\"options\":[{\"name\":\"unknown\",\"type\":\"bool\",\"default_fn\":\"no_such_fn\"},{\"name\":\"arity\",\"type\":\"bool\",\"default_fn\":\"borrow\"},{\"name\":\"sentinel\",\"type\":\"bool\",\"default_fn\":\"unset\"}]}",
  )
  match parse_definition(json) {
    Err(Rejected(errors)) => {
      let kinds = def_error_kinds(errors)
      assert_eq(kinds.get("unknown"), Some(@abi.UnknownVocab))
      assert_eq(kinds.get("arity"), Some(@abi.InvalidArgument))
      assert_eq(kinds.get("sentinel"), Some(@abi.InvalidRange))
    }
    _ => fail("invalid default_fn declarations must be definition errors")
  }
}

///|
test "default_fn observes cycle reports every participant as circular-ref" {
  let json = @json.parse(
    "{\"options\":[{\"name\":\"a\",\"type\":\"bool\",\"default_fn\":\"borrow:b\"},{\"name\":\"b\",\"type\":\"bool\",\"default_fn\":\"borrow:a\"}]}",
  )
  match parse_definition(json) {
    Err(Rejected(errors)) => {
      let kinds = def_error_kinds(errors)
      assert_eq(kinds.get("a"), Some(@abi.CircularRef))
      assert_eq(kinds.get("b"), Some(@abi.CircularRef))
    }
    _ => fail("cyclic default_fn dependencies must be rejected")
  }
}
