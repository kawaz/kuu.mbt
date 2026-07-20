// cell_fns_wbtest.mbt — builtin cell-fn descriptor contracts.

///|
fn builtin_cell_fn_registry() -> @engine.Registry {
  let registry = @engine.Registry::new()
  for descriptor in cell_fn_descriptors() {
    guard registry.register_cell_fn(descriptor) else {
      abort("duplicate builtin cell fn: " + descriptor.name())
    }
  }
  registry
}

///|
test "builtin cell_fns inventory matches DR-114 descriptor contracts" {
  let registry = builtin_cell_fn_registry()
  let names = [
    "set", "default", "unset", "empty", "incr", "borrow", "env", "inherit", "uuid",
    "computed",
  ]
  for name in names {
    assert_true(registry.lookup_cell_fn(name) is Some(_))
  }
  assert_true(registry.lookup_cell_fn("missing") is None)

  let set = registry.lookup_cell_fn("set").unwrap()
  assert_eq(set.parameters(), [
    @engine.cell_fn_parameter(
      "value",
      kind=@engine.ValueParameter,
      repetition=@engine.OneOrMore,
    ),
  ])
  assert_eq(set.arity(), @engine.AtLeastArity(1))
  assert_eq(set.output(), @engine.ValueOutput)
  assert_eq(set.fallibility(), @engine.TotalFn)
  assert_eq(set.observes(), [])
  assert_eq(set.reasons(), [])

  let default_fn = registry.lookup_cell_fn("default").unwrap()
  assert_eq(default_fn.parameters(), [])
  assert_eq(default_fn.output(), @engine.SentinelOutput(@engine.UseDefault))
  let unset = registry.lookup_cell_fn("unset").unwrap()
  assert_eq(unset.parameters(), [])
  assert_eq(unset.output(), @engine.SentinelOutput(@engine.Unset))
  let empty = registry.lookup_cell_fn("empty").unwrap()
  assert_eq(empty.parameters(), [])
  assert_eq(empty.output(), @engine.SentinelOutput(@engine.Empty))
  for name in ["default", "unset", "empty"] {
    let descriptor = registry.lookup_cell_fn(name).unwrap()
    assert_eq(descriptor.arity(), @engine.ExactArity(0))
    assert_eq(descriptor.fallibility(), @engine.TotalFn)
    assert_eq(descriptor.observes(), [])
    assert_eq(descriptor.reasons(), [])
  }

  let incr = registry.lookup_cell_fn("incr").unwrap()
  assert_eq(incr.parameters(), [])
  assert_eq(incr.arity(), @engine.ExactArity(0))
  assert_eq(incr.output(), @engine.NumberOutput)
  assert_eq(incr.fallibility(), @engine.TotalFn)

  let borrow = registry.lookup_cell_fn("borrow").unwrap()
  assert_eq(borrow.parameters(), [@engine.cell_fn_parameter("source")])
  assert_eq(borrow.arity(), @engine.ExactArity(1))
  assert_eq(borrow.output(), @engine.ValueOutput)
  assert_eq(borrow.fallibility(), @engine.RejectFn)
  assert_eq(borrow.observes(), ["option:<source>"])
  assert_eq(borrow.reasons(), ["absent-source"])

  let env = registry.lookup_cell_fn("env").unwrap()
  assert_eq(env.parameters(), [@engine.cell_fn_parameter("var")])
  assert_eq(env.arity(), @engine.ExactArity(1))
  assert_eq(env.output(), @engine.ValueOutput)
  assert_eq(env.fallibility(), @engine.RejectFn)
  assert_eq(env.observes(), ["env:<var>"])
  assert_eq(env.reasons(), ["absent-source"])

  let inherit_descriptor = registry.lookup_cell_fn("inherit").unwrap()
  assert_eq(inherit_descriptor.parameters(), [
    @engine.cell_fn_parameter("source"),
  ])
  assert_eq(inherit_descriptor.arity(), @engine.ExactArity(1))
  assert_eq(inherit_descriptor.output(), @engine.ValueOutput)
  assert_eq(inherit_descriptor.fallibility(), @engine.RejectFn)
  assert_eq(inherit_descriptor.observes(), ["option:<source>"])
  assert_eq(inherit_descriptor.reasons(), ["absent-source"])

  let uuid = registry.lookup_cell_fn("uuid").unwrap()
  assert_eq(uuid.parameters(), [
    @engine.cell_fn_parameter("version", repetition=@engine.ZeroOrOne),
  ])
  assert_eq(uuid.arity(), @engine.BetweenArity(0, 1))
  assert_eq(uuid.output(), @engine.StringOutput)
  assert_eq(uuid.fallibility(), @engine.TotalFn)
  assert_eq(uuid.observes(), [])
  assert_eq(uuid.reasons(), [])

  let computed = registry.lookup_cell_fn("computed").unwrap()
  assert_eq(computed.parameters(), [@engine.cell_fn_parameter("key")])
  assert_eq(computed.arity(), @engine.ExactArity(1))
  assert_eq(computed.output(), @engine.ValueOutput)
  assert_eq(computed.fallibility(), @engine.RejectFn)
  assert_eq(computed.observes(), ["system:<key>"])
  assert_eq(computed.reasons(), ["absent-source"])
}

///|
test "cell fn parameter contracts validate arity and bind concrete observes" {
  let registry = builtin_cell_fn_registry()
  let set = registry.lookup_cell_fn("set").unwrap()
  assert_eq(set.validate_arity(1), Ok(()))
  assert_eq(set.validate_arity(2), Ok(()))
  let invocation = @engine.parse_fn_invocation(
    @engine.ArrayParts(["set", "a", "b"]),
  ).unwrap()
  assert_eq(set.validate_invocation(invocation), Ok(()))
  assert_eq(set.concrete_observes(invocation), Ok([]))
  let typed = @engine.typed_fn_call("set", [@engine.VBool(true)])
  assert_eq(set.validate_call(typed), Ok(()))
  assert_eq(typed.args, [@engine.ValueArg(@engine.VBool(true))])
  assert_eq(
    set.validate_arity(0),
    Err(("invalid-argument", "cell fn 'set' does not accept 0 args")),
  )

  let borrow = registry.lookup_cell_fn("borrow").unwrap()
  let invocation = @engine.parse_fn_invocation(
    @engine.ArrayParts(["borrow", "help-full"]),
  ).unwrap()
  let concrete = borrow.concrete_observes(invocation).unwrap()
  assert_eq(concrete, ["option:help-full"])
  let ctx = @engine.fn_ctx_effect("target", "--copy", observes=concrete, option=fn(
    name,
  ) {
    if name == "help-full" {
      Some(@engine.VStr("source"))
    } else {
      None
    }
  })
  assert_eq(ctx.option("help-full"), Some(@engine.VStr("source")))
  assert_true(ctx.option("other") is None)
  assert_eq(
    borrow.validate_call(
      @engine.typed_fn_call("borrow", [@engine.VStr("help-full")]),
    ),
    Err(
      (
        "invalid-argument", "cell fn 'borrow' argument 0 for parameter 'source' has an incompatible carrier",
      ),
    ),
  )
  assert_eq(
    borrow.validate_arity(0),
    Err(("invalid-argument", "cell fn 'borrow' does not accept 0 args")),
  )

  let env = registry.lookup_cell_fn("env").unwrap()
  let invocation = @engine.parse_fn_invocation(@engine.ColonString("env:HOME")).unwrap()
  assert_eq(env.concrete_observes(invocation), Ok(["env:HOME"]))

  let computed = registry.lookup_cell_fn("computed").unwrap()
  let invocation = @engine.parse_fn_invocation(
    @engine.ArrayParts(["computed", "clock:utc"]),
  ).unwrap()
  assert_eq(computed.concrete_observes(invocation), Ok(["system:clock:utc"]))
}

///|
test "builtin cell fn residents execute through their registered descriptors" {
  let registry = builtin_cell_fn_registry()
  let set = registry.lookup_cell_fn("set").unwrap()
  let ctx = @engine.fn_ctx_effect("target", "--target")
  assert_eq(
    set.invoke(@engine.typed_fn_call("set", [@engine.VBool(true)]), ctx),
    Ok(@engine.FnValue(@engine.VBool(true))),
  )
  assert_eq(
    set.invoke({ name: "set", args: [@engine.StringArg("value")] }, ctx),
    Ok(@engine.FnValue(@engine.VStr("value"))),
  )

  let incr = registry.lookup_cell_fn("incr").unwrap()
  assert_eq(
    incr.invoke({ name: "incr", args: [] }, ctx),
    Ok(@engine.FnValue(@engine.VNum(1.0))),
  )
  assert_eq(
    incr.invoke(
      { name: "incr", args: [] },
      @engine.fn_ctx_effect("target", "--target", old=Some(@engine.VNum(4.0))),
    ),
    Ok(@engine.FnValue(@engine.VNum(5.0))),
  )

  let borrow = registry.lookup_cell_fn("borrow").unwrap()
  let borrow_invocation = @engine.parse_fn_invocation(
    @engine.ColonString("borrow:source"),
  ).unwrap()
  let borrow_observes = borrow.concrete_observes(borrow_invocation).unwrap()
  let borrow_ctx = @engine.fn_ctx_default(
    "target",
    observes=borrow_observes,
    dependency=Some(fn(name) {
      if name == "source" { Some(@engine.VNum(7.0)) } else { None }
    }),
  )
  assert_eq(
    borrow.invoke(borrow_invocation.to_call(), borrow_ctx),
    Ok(@engine.FnValue(@engine.VNum(7.0))),
  )

  for name in ["default", "unset", "empty"] {
    let descriptor = registry.lookup_cell_fn(name).unwrap()
    assert_true(descriptor.invoke({ name, args: [] }, ctx) is Ok(@engine.FnSentinel(_)))
  }

  let uuid = registry.lookup_cell_fn("uuid").unwrap()
  match uuid.invoke({ name: "uuid", args: [] }, ctx) {
    Ok(@engine.FnValue(@engine.VStr(value))) => assert_eq(value.length(), 36)
    _ => fail("uuid() must return a v4-shaped string")
  }
  assert_true(
    uuid.validate_call({ name: "uuid", args: [@engine.StringArg("5")] }) is Err(_),
  )

  let env = registry.lookup_cell_fn("env").unwrap()
  let env_invocation = @engine.parse_fn_invocation(
    @engine.ColonString("env:MISSING"),
  ).unwrap()
  let env_ctx = @engine.fn_ctx_default(
    "target",
    observes=env.concrete_observes(env_invocation).unwrap(),
  )
  assert_eq(
    env.invoke(env_invocation.to_call(), env_ctx),
    Err(("absent-source", "env source 'MISSING' is absent")),
  )
}
