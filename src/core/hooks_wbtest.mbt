///|
test "add_preprocessor: 登録したフックが preprocessors に追加される" {
  let p = Parser::new()
  assert_eq(p.preprocessors.length(), 0)
  p.add_preprocessor(fn(args) { args })
  assert_eq(p.preprocessors.length(), 1)
  p.add_preprocessor(fn(args) { args })
  assert_eq(p.preprocessors.length(), 2)
}

///|
test "add_resolve_hook: 登録したフックが resolve_hooks に追加される" {
  let p = Parser::new()
  assert_eq(p.resolve_hooks.length(), 0)
  p.add_resolve_hook(fn(_name, _nodes) { None })
  assert_eq(p.resolve_hooks.length(), 1)
}

///|
test "add_constraint: 登録した制約が constraints に追加される" {
  let p = Parser::new()
  assert_eq(p.constraints.length(), 0)
  p.add_constraint(check=fn(_ctx) {  }, help_hint="test hint")
  assert_eq(p.constraints.length(), 1)
  assert_eq(p.constraints[0].help_hint, "test hint")
}

///|
test "add_constraint: help_hint のデフォルトは空文字列" {
  let p = Parser::new()
  p.add_constraint(check=fn(_ctx) {  })
  assert_eq(p.constraints[0].help_hint, "")
}

///|
test "add_finalizer: 登録したフックが finalizers に追加される" {
  let p = Parser::new()
  assert_eq(p.finalizers.length(), 0)
  p.add_finalizer(fn(_ctx) {  })
  assert_eq(p.finalizers.length(), 1)
}

///|
test "複数フック登録: 登録順で保持される" {
  let p = Parser::new()
  let order : Array[Int] = []
  p.add_preprocessor(fn(args) { order.push(1); args })
  p.add_preprocessor(fn(args) { order.push(2); args })
  // preprocessors を順に実行して登録順を確認
  let mut args : Array[String] = []
  for hook in p.preprocessors {
    args = hook(args)
  }
  assert_eq(order, [1, 2])
}
