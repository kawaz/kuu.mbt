// cell_fns.mbt — builtin cell-fn residents and descriptor contracts (DR-114).

///|
fn fn_arg_value(arg : @abi.FnArg) -> @abi.Value {
  match arg {
    @abi.FnArg::Value(value) => value
    @abi.FnArg::String(value) => @abi.Value::String(value)
  }
}

///|
fn one_arg(args : Array[@abi.FnArg], name : String) -> @abi.FnArg {
  guard args is [arg] else {
    abort(
      "validated cell fn '" + name + "' reached its resident with wrong arity",
    )
  }
  arg
}

///|
fn fn_string_arg(args : Array[@abi.FnArg], name : String) -> String {
  match one_arg(args, name) {
    @abi.FnArg::String(value) => value
    @abi.FnArg::Value(_) =>
      abort(
        "validated cell fn '" + name + "' reached its resident with a typed arg",
      )
  }
}

///|
fn absent_source(kind : String, key : String) -> FnResult {
  Err({
    reason: "absent-source",
    message: kind + " source '" + key + "' is absent",
  })
}

///|
fn set_fn(args : Array[@abi.FnArg], _ctx : FnCtx) -> FnResult {
  // A scalar target admits one logical value. Definition checking rejects multiple string args for
  // scalar targets; seq/repeat aggregation needs the structured Value carrier that is not present in
  // the current engine Value ADT and is intentionally left visible to the next structural slice.
  match args {
    [arg] => Ok(FnOutput::Value(fn_arg_value(arg)))
    _ =>
      Err({
        reason: "invalid-argument",
        message: "set on a scalar target requires exactly one value",
      })
  }
}

///|
fn sentinel_fn(sentinel : CellSentinel) -> CellFn {
  fn(_, _) { Ok(FnOutput::Sentinel(sentinel)) }
}

///|
fn incr_fn(_args : Array[@abi.FnArg], ctx : FnCtx) -> FnResult {
  let old = match ctx.old() {
    None => 0.0
    Some(@abi.Value::Number(value)) => value
    Some(_) =>
      return Err({
        reason: "invalid-range",
        message: "incr requires a number target",
      })
  }
  Ok(FnOutput::Value(@abi.Value::Number(old + 1.0)))
}

///|
fn borrow_fn(args : Array[@abi.FnArg], ctx : FnCtx) -> FnResult {
  let source = fn_string_arg(args, "borrow")
  let value = match ctx.as_default() {
    Some(default_ctx) => default_ctx.dependency(source)
    None => ctx.option(source)
  }
  match value {
    Some(value) => Ok(FnOutput::Value(value))
    None => absent_source("option", source)
  }
}

///|
fn env_fn(args : Array[@abi.FnArg], ctx : FnCtx) -> FnResult {
  let variable = fn_string_arg(args, "env")
  match ctx.env(variable) {
    Some(value) => Ok(FnOutput::Value(value))
    None => absent_source("env", variable)
  }
}

///|
fn inherit_fn(args : Array[@abi.FnArg], ctx : FnCtx) -> FnResult {
  let source = fn_string_arg(args, "inherit")
  match ctx.option(source) {
    Some(value) => Ok(FnOutput::Value(value))
    None => absent_source("ancestor option", source)
  }
}

///|
let cell_fn_rng : @random.Rand = @random.Rand::new()

///|
fn uuid_v4() -> String {
  let bytes : Array[Int] = []
  let mut index = 0
  while index < 16 {
    bytes.push(cell_fn_rng.int(limit=256))
    index = index + 1
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40
  bytes[8] = (bytes[8] & 0x3f) | 0x80
  let out = StringBuilder::new()
  index = 0
  while index < bytes.length() {
    if index == 4 || index == 6 || index == 8 || index == 10 {
      out.write_char('-')
    }
    out.write_string(bytes[index].to_byte().to_hex())
    index = index + 1
  }
  out.to_string()
}

///|
fn validate_uuid(call : @abi.FnCall) -> Result[Unit, FnReason] {
  match call.args {
    [] | [@abi.FnArg::String("4")] => Ok(())
    [@abi.FnArg::String(_)] =>
      Err({
        reason: "invalid-argument",
        message: "cell fn 'uuid' version must be '4'",
      })
    _ =>
      Err({
        reason: "invalid-argument",
        message: "cell fn 'uuid' has an invalid version carrier",
      })
  }
}

///|
fn uuid_fn(args : Array[@abi.FnArg], _ctx : FnCtx) -> FnResult {
  let version = match args {
    [] => "4"
    [@abi.FnArg::String(value)] => value
    _ =>
      abort(
        "validated uuid invocation reached its resident with an invalid carrier",
      )
  }
  if version != "4" {
    Err({ reason: "invalid-argument", message: "uuid version must be '4'" })
  } else {
    Ok(FnOutput::Value(@abi.Value::String(uuid_v4())))
  }
}

///|
fn computed_fn(args : Array[@abi.FnArg], ctx : FnCtx) -> FnResult {
  let key = fn_string_arg(args, "computed")
  match ctx.system(key) {
    Some(value) => Ok(FnOutput::Value(value))
    None => absent_source("system", key)
  }
}

///|
/// Canonical builtin `cell_fns` residents: descriptor contract and executable body are registered
/// together, so lookup never falls through a builtin-name switch.
pub fn cell_fn_descriptors() -> Array[CellFnDescriptor] {
  [
    cell_fn_descriptor(
      "set",
      [
        cell_fn_parameter(
          "value",
          kind=CellFnParameterKind::Value,
          repetition=CellFnRepetition::OneOrMore,
        ),
      ],
      CellFnOutput::Value,
      FnFallibility::Total,
      run=set_fn,
    ),
    cell_fn_descriptor(
      "default",
      [],
      CellFnOutput::Sentinel(CellSentinel::UseDefault),
      FnFallibility::Total,
      run=sentinel_fn(CellSentinel::UseDefault),
    ),
    cell_fn_descriptor(
      "unset",
      [],
      CellFnOutput::Sentinel(CellSentinel::Unset),
      FnFallibility::Total,
      run=sentinel_fn(CellSentinel::Unset),
    ),
    cell_fn_descriptor(
      "empty",
      [],
      CellFnOutput::Sentinel(CellSentinel::Empty),
      FnFallibility::Total,
      run=sentinel_fn(CellSentinel::Empty),
    ),
    cell_fn_descriptor(
      "incr",
      [],
      CellFnOutput::Number,
      FnFallibility::Total,
      run=incr_fn,
    ),
    cell_fn_descriptor(
      "borrow",
      [cell_fn_parameter("source")],
      CellFnOutput::Value,
      FnFallibility::Reject,
      observes=["option:<source>"],
      reasons=["absent-source"],
      run=borrow_fn,
    ),
    cell_fn_descriptor(
      "env",
      [cell_fn_parameter("var")],
      CellFnOutput::Value,
      FnFallibility::Reject,
      observes=["env:<var>"],
      reasons=["absent-source"],
      run=env_fn,
    ),
    cell_fn_descriptor(
      "inherit",
      [cell_fn_parameter("source")],
      CellFnOutput::Value,
      FnFallibility::Reject,
      observes=["option:<source>"],
      reasons=["absent-source"],
      run=inherit_fn,
    ),
    cell_fn_descriptor(
      "uuid",
      [cell_fn_parameter("version", repetition=CellFnRepetition::ZeroOrOne)],
      CellFnOutput::String,
      FnFallibility::Total,
      validate=validate_uuid,
      run=uuid_fn,
    ),
    cell_fn_descriptor(
      "computed",
      [cell_fn_parameter("key")],
      CellFnOutput::Value,
      FnFallibility::Reject,
      observes=["system:<key>"],
      reasons=["absent-source"],
      run=computed_fn,
    ),
  ]
}
