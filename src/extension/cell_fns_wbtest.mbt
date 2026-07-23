// cell_fns_wbtest.mbt — builtin cell-fn descriptor contracts.

///|
fn builtin_cell_fn_registry() -> Registry {
  let registry = Registry::new()
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
    cell_fn_parameter(
      "value",
      kind=CellFnParameterKind::Value,
      repetition=CellFnRepetition::OneOrMore,
    ),
  ])
  assert_eq(set.arity(), CellFnArity::AtLeast(1))
  assert_eq(set.output(), CellFnOutput::Value)
  assert_eq(set.fallibility(), FnFallibility::Total)
  assert_eq(set.observes(), [])
  assert_eq(set.reasons(), [])

  let default_fn = registry.lookup_cell_fn("default").unwrap()
  assert_eq(default_fn.parameters(), [])
  assert_eq(
    default_fn.output(),
    CellFnOutput::Sentinel(CellSentinel::UseDefault),
  )
  let unset = registry.lookup_cell_fn("unset").unwrap()
  assert_eq(unset.parameters(), [])
  assert_eq(unset.output(), CellFnOutput::Sentinel(CellSentinel::Unset))
  let empty = registry.lookup_cell_fn("empty").unwrap()
  assert_eq(empty.parameters(), [])
  assert_eq(empty.output(), CellFnOutput::Sentinel(CellSentinel::Empty))
  for name in ["default", "unset", "empty"] {
    let descriptor = registry.lookup_cell_fn(name).unwrap()
    assert_eq(descriptor.arity(), CellFnArity::Exact(0))
    assert_eq(descriptor.fallibility(), FnFallibility::Total)
    assert_eq(descriptor.observes(), [])
    assert_eq(descriptor.reasons(), [])
  }

  let incr = registry.lookup_cell_fn("incr").unwrap()
  assert_eq(incr.parameters(), [])
  assert_eq(incr.arity(), CellFnArity::Exact(0))
  assert_eq(incr.output(), CellFnOutput::Number)
  assert_eq(incr.fallibility(), FnFallibility::Total)

  let borrow = registry.lookup_cell_fn("borrow").unwrap()
  assert_eq(borrow.parameters(), [cell_fn_parameter("source")])
  assert_eq(borrow.arity(), CellFnArity::Exact(1))
  assert_eq(borrow.output(), CellFnOutput::Value)
  assert_eq(borrow.fallibility(), FnFallibility::Reject)
  assert_eq(borrow.observes(), ["option:<source>"])
  assert_eq(borrow.reasons(), ["absent-source"])

  let env = registry.lookup_cell_fn("env").unwrap()
  assert_eq(env.parameters(), [cell_fn_parameter("var")])
  assert_eq(env.arity(), CellFnArity::Exact(1))
  assert_eq(env.output(), CellFnOutput::Value)
  assert_eq(env.fallibility(), FnFallibility::Reject)
  assert_eq(env.observes(), ["env:<var>"])
  assert_eq(env.reasons(), ["absent-source"])

  let inherit_descriptor = registry.lookup_cell_fn("inherit").unwrap()
  assert_eq(inherit_descriptor.parameters(), [cell_fn_parameter("source")])
  assert_eq(inherit_descriptor.arity(), CellFnArity::Exact(1))
  assert_eq(inherit_descriptor.output(), CellFnOutput::Value)
  assert_eq(inherit_descriptor.fallibility(), FnFallibility::Reject)
  assert_eq(inherit_descriptor.observes(), ["option:<source>"])
  assert_eq(inherit_descriptor.reasons(), ["absent-source"])

  let uuid = registry.lookup_cell_fn("uuid").unwrap()
  assert_eq(uuid.parameters(), [
    cell_fn_parameter("version", repetition=CellFnRepetition::ZeroOrOne),
  ])
  assert_eq(uuid.arity(), CellFnArity::Between(0, 1))
  assert_eq(uuid.output(), CellFnOutput::String)
  assert_eq(uuid.fallibility(), FnFallibility::Total)
  assert_eq(uuid.observes(), [])
  assert_eq(uuid.reasons(), [])

  let computed = registry.lookup_cell_fn("computed").unwrap()
  assert_eq(computed.parameters(), [cell_fn_parameter("key")])
  assert_eq(computed.arity(), CellFnArity::Exact(1))
  assert_eq(computed.output(), CellFnOutput::Value)
  assert_eq(computed.fallibility(), FnFallibility::Reject)
  assert_eq(computed.observes(), ["system:<key>"])
  assert_eq(computed.reasons(), ["absent-source"])
}

///|
test "cell fn parameter contracts validate arity and bind concrete observes" {
  let registry = builtin_cell_fn_registry()
  let set = registry.lookup_cell_fn("set").unwrap()
  assert_eq(set.validate_arity(1), Ok(()))
  assert_eq(set.validate_arity(2), Ok(()))
  let invocation = @abi.parse_fn_invocation(@abi.ArrayParts(["set", "a", "b"])).unwrap()
  assert_eq(set.validate_invocation(invocation), Ok(()))
  assert_eq(set.concrete_observes(invocation), Ok([]))
  let typed = @abi.FnCall::typed("set", [@abi.Bool(true)])
  assert_eq(set.validate_call(typed), Ok(()))
  assert_eq(typed.args, [@abi.Value(@abi.Bool(true))])
  assert_eq(
    set.validate_arity(0),
    Err({
      reason: "invalid-argument",
      message: "cell fn 'set' does not accept 0 args",
    }),
  )

  let borrow = registry.lookup_cell_fn("borrow").unwrap()
  let invocation = @abi.parse_fn_invocation(
    @abi.ArrayParts(["borrow", "help-full"]),
  ).unwrap()
  let concrete = borrow.concrete_observes(invocation).unwrap()
  assert_eq(concrete, ["option:help-full"])
  let ctx = FnCtx::for_effect("target", "--copy", observes=concrete, option=fn(
    name,
  ) {
    if name == "help-full" {
      Some(@abi.String("source"))
    } else {
      None
    }
  })
  assert_eq(ctx.option("help-full"), Some(@abi.String("source")))
  assert_true(ctx.option("other") is None)
  assert_eq(
    borrow.validate_call(
      @abi.FnCall::typed("borrow", [@abi.String("help-full")]),
    ),
    Err({
      reason: "invalid-argument",
      message: "cell fn 'borrow' argument 0 for parameter 'source' has an incompatible carrier",
    }),
  )
  assert_eq(
    borrow.validate_arity(0),
    Err({
      reason: "invalid-argument",
      message: "cell fn 'borrow' does not accept 0 args",
    }),
  )

  let env = registry.lookup_cell_fn("env").unwrap()
  let invocation = @abi.parse_fn_invocation(@abi.ColonString("env:HOME")).unwrap()
  assert_eq(env.concrete_observes(invocation), Ok(["env:HOME"]))

  let computed = registry.lookup_cell_fn("computed").unwrap()
  let invocation = @abi.parse_fn_invocation(
    @abi.ArrayParts(["computed", "clock:utc"]),
  ).unwrap()
  assert_eq(computed.concrete_observes(invocation), Ok(["system:clock:utc"]))
}

///|
test "builtin cell fn residents execute through their registered descriptors" {
  let registry = builtin_cell_fn_registry()
  let set = registry.lookup_cell_fn("set").unwrap()
  let ctx = FnCtx::for_effect("target", "--target")
  assert_eq(
    set.invoke(@abi.FnCall::typed("set", [@abi.Bool(true)]), ctx),
    Ok(FnOutput::Value(@abi.Value::Bool(true))),
  )
  assert_eq(
    set.invoke({ name: "set", args: [@abi.String("value")] }, ctx),
    Ok(FnOutput::Value(@abi.Value::String("value"))),
  )

  let incr = registry.lookup_cell_fn("incr").unwrap()
  assert_eq(
    incr.invoke({ name: "incr", args: [] }, ctx),
    Ok(FnOutput::Value(@abi.Value::Number(1.0))),
  )
  assert_eq(
    incr.invoke(
      { name: "incr", args: [] },
      FnCtx::for_effect("target", "--target", old=Some(@abi.Number(4.0))),
    ),
    Ok(FnOutput::Value(@abi.Value::Number(5.0))),
  )

  let borrow = registry.lookup_cell_fn("borrow").unwrap()
  let borrow_invocation = @abi.parse_fn_invocation(
    @abi.ColonString("borrow:source"),
  ).unwrap()
  let borrow_observes = borrow.concrete_observes(borrow_invocation).unwrap()
  let borrow_ctx = FnCtx::for_default(
    "target",
    observes=borrow_observes,
    dependency=Some(fn(name) {
      if name == "source" {
        Some(@abi.Number(7.0))
      } else {
        None
      }
    }),
  )
  assert_eq(
    borrow.invoke(borrow_invocation.to_call(), borrow_ctx),
    Ok(FnOutput::Value(@abi.Value::Number(7.0))),
  )

  for name in ["default", "unset", "empty"] {
    let descriptor = registry.lookup_cell_fn(name).unwrap()
    assert_true(
      descriptor.invoke({ name, args: [] }, ctx) is Ok(FnOutput::Sentinel(_)),
    )
  }

  let uuid = registry.lookup_cell_fn("uuid").unwrap()
  match uuid.invoke({ name: "uuid", args: [] }, ctx) {
    Ok(FnOutput::Value(@abi.Value::String(value))) =>
      assert_eq(value.length(), 36)
    _ => fail("uuid() must return a v4-shaped string")
  }
  assert_true(
    uuid.validate_call({ name: "uuid", args: [@abi.String("5")] }) is Err(_),
  )

  let env = registry.lookup_cell_fn("env").unwrap()
  let env_invocation = @abi.parse_fn_invocation(@abi.ColonString("env:MISSING")).unwrap()
  let env_ctx = FnCtx::for_default(
    "target",
    observes=env.concrete_observes(env_invocation).unwrap(),
  )
  assert_eq(
    env.invoke(env_invocation.to_call(), env_ctx),
    Err({ reason: "absent-source", message: "env source 'MISSING' is absent" }),
  )
}
