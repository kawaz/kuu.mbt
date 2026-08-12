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
          assert_eq(
            @engine.element_value(bindings, [], "source"),
            Some(@abi.Bool(true)),
          )
          assert_eq(
            @engine.element_value(bindings, [], "target"),
            Some(@abi.Bool(true)),
          )
        }
        _ => fail("borrow default must resolve in dependency order")
      }
    }
    Err(_) => fail("borrow default definition must lower")
  }
}

///|
test "default_fn static failures classify unknown names and invalid arity" {
  let json = @json.parse(
    "{\"options\":[{\"name\":\"unknown\",\"type\":\"bool\",\"default_fn\":\"no_such_fn\"},{\"name\":\"arity\",\"type\":\"bool\",\"default_fn\":\"borrow\"}]}",
  )
  match parse_definition(json) {
    Err(Rejected(errors)) => {
      let kinds = def_error_kinds(errors)
      assert_eq(kinds.get("unknown"), Some(@abi.UnknownVocab))
      assert_eq(kinds.get("arity"), Some(@abi.InvalidArgument))
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

///|
/// DR-134 §5: command 担体の `default_fn` も element と同じ observes グラフに乗る。担体セルは
/// `init_sb` が command 自身の scope へ内部セルとして降ろす (§1/§4) ので、グラフ上の名前は
/// `@engine.command_value_cell()` (= `#command_value`) — `borrow` の観測辺 `option:<source>` が
/// resolve 相で担体 entity に届く綴りと同じにしてある。エラーの帰属だけは DR-134 §2 のとおり
/// command 名。
///
/// 閉路は担体の**自己借用**で作る。担体を巻き込む閉路はこの形しか無い: 相手役になれるのは
/// 担体と同じ scope に居て `default_fn` を持てる要素だけだが、値セルを持つ子は結果キー占有子
/// なので DR-134 §2 が先に invalid-range で落とす (共存できる非占有子は `type: "none"` と `dd`
/// = 値セルを持たない、`command-scope/value-command-non-occupying-children.json`)。
///
/// fixture が無い面なのでここで pin する (spec 側の definition-error/ には担体の default 席検査
/// しか無い)。
test "command carrier default_fn joins the observes cycle graph as its own cell" {
  let json = @json.parse(
    "{\"commands\":[{\"type\":\"command\",\"name\":\"c\",\"default_fn\":\"borrow:#command_value\"}]}",
  )
  match parse_definition(json) {
    Err(Rejected(errors)) => {
      assert_eq(errors.length(), 1)
      assert_eq(errors[0].element, "c")
      assert_eq(errors[0].kind, @abi.CircularRef)
    }
    _ =>
      fail(
        "a cycle through the command value carrier must be a definition error",
      )
  }
}
