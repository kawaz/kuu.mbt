// cell_fns.mbt — builtin cell-fn residents and descriptor contracts (DR-114).

///|
fn fn_arg_value(arg : @engine.FnArg) -> @engine.Value {
  match arg {
    @engine.ValueArg(value) => value
    @engine.StringArg(value) => @engine.String(value)
  }
}

///|
fn one_arg(args : Array[@engine.FnArg], name : String) -> @engine.FnArg {
  guard args is [arg] else {
    abort(
      "validated cell fn '" + name + "' reached its resident with wrong arity",
    )
  }
  arg
}

///|
fn fn_string_arg(args : Array[@engine.FnArg], name : String) -> String {
  match one_arg(args, name) {
    @engine.StringArg(value) => value
    @engine.ValueArg(_) =>
      abort(
        "validated cell fn '" + name + "' reached its resident with a typed arg",
      )
  }
}

///|
fn absent_source(kind : String, key : String) -> @engine.FnResult {
  Err(("absent-source", kind + " source '" + key + "' is absent"))
}

///|
fn set_fn(
  args : Array[@engine.FnArg],
  _ctx : @engine.FnCtx,
) -> @engine.FnResult {
  // A scalar target admits one logical value. Definition checking rejects multiple string args for
  // scalar targets; seq/repeat aggregation needs the structured Value carrier that is not present in
  // the current engine Value ADT and is intentionally left visible to the next structural slice.
  match args {
    [arg] => Ok(@engine.FnValue(fn_arg_value(arg)))
    _ =>
      Err(
        (
          "invalid-argument", "set on a scalar target requires exactly one value",
        ),
      )
  }
}

///|
fn sentinel_fn(sentinel : @engine.CellSentinel) -> @engine.CellFn {
  fn(_, _) { Ok(@engine.FnSentinel(sentinel)) }
}

///|
fn incr_fn(
  _args : Array[@engine.FnArg],
  ctx : @engine.FnCtx,
) -> @engine.FnResult {
  let old = match ctx.old() {
    None => 0.0
    Some(@engine.Number(value)) => value
    Some(_) => return Err(("invalid-range", "incr requires a number target"))
  }
  Ok(@engine.FnValue(@engine.Number(old + 1.0)))
}

///|
fn borrow_fn(
  args : Array[@engine.FnArg],
  ctx : @engine.FnCtx,
) -> @engine.FnResult {
  let source = fn_string_arg(args, "borrow")
  let value = match ctx.as_default() {
    Some(default_ctx) => default_ctx.dependency(source)
    None => ctx.option(source)
  }
  match value {
    Some(value) => Ok(@engine.FnValue(value))
    None => absent_source("option", source)
  }
}

///|
fn env_fn(args : Array[@engine.FnArg], ctx : @engine.FnCtx) -> @engine.FnResult {
  let variable = fn_string_arg(args, "env")
  match ctx.env(variable) {
    Some(value) => Ok(@engine.FnValue(value))
    None => absent_source("env", variable)
  }
}

///|
fn inherit_fn(
  args : Array[@engine.FnArg],
  ctx : @engine.FnCtx,
) -> @engine.FnResult {
  let source = fn_string_arg(args, "inherit")
  match ctx.option(source) {
    Some(value) => Ok(@engine.FnValue(value))
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
fn validate_uuid(call : @engine.FnCall) -> Result[Unit, @engine.FnReason] {
  match call.args {
    [] | [@engine.StringArg("4")] => Ok(())
    [@engine.StringArg(_)] =>
      Err(("invalid-argument", "cell fn 'uuid' version must be '4'"))
    _ =>
      Err(("invalid-argument", "cell fn 'uuid' has an invalid version carrier"))
  }
}

///|
fn uuid_fn(
  args : Array[@engine.FnArg],
  _ctx : @engine.FnCtx,
) -> @engine.FnResult {
  let version = match args {
    [] => "4"
    [@engine.StringArg(value)] => value
    _ =>
      abort(
        "validated uuid invocation reached its resident with an invalid carrier",
      )
  }
  if version != "4" {
    Err(("invalid-argument", "uuid version must be '4'"))
  } else {
    Ok(@engine.FnValue(@engine.String(uuid_v4())))
  }
}

///|
fn computed_fn(
  args : Array[@engine.FnArg],
  ctx : @engine.FnCtx,
) -> @engine.FnResult {
  let key = fn_string_arg(args, "computed")
  match ctx.system(key) {
    Some(value) => Ok(@engine.FnValue(value))
    None => absent_source("system", key)
  }
}

///|
/// Canonical builtin `cell_fns` residents: descriptor contract and executable body are registered
/// together, so lookup never falls through a builtin-name switch.
pub fn cell_fn_descriptors() -> Array[@engine.CellFnDescriptor] {
  [
    @engine.cell_fn_descriptor(
      "set",
      [
        @engine.cell_fn_parameter(
          "value",
          kind=@engine.ValueParameter,
          repetition=@engine.OneOrMore,
        ),
      ],
      @engine.ValueOutput,
      @engine.TotalFn,
      run=set_fn,
    ),
    @engine.cell_fn_descriptor(
      "default",
      [],
      @engine.SentinelOutput(@engine.UseDefault),
      @engine.TotalFn,
      run=sentinel_fn(@engine.UseDefault),
    ),
    @engine.cell_fn_descriptor(
      "unset",
      [],
      @engine.SentinelOutput(@engine.Unset),
      @engine.TotalFn,
      run=sentinel_fn(@engine.Unset),
    ),
    @engine.cell_fn_descriptor(
      "empty",
      [],
      @engine.SentinelOutput(@engine.Empty),
      @engine.TotalFn,
      run=sentinel_fn(@engine.Empty),
    ),
    @engine.cell_fn_descriptor(
      "incr",
      [],
      @engine.NumberOutput,
      @engine.TotalFn,
      run=incr_fn,
    ),
    @engine.cell_fn_descriptor(
      "borrow",
      [@engine.cell_fn_parameter("source")],
      @engine.ValueOutput,
      @engine.RejectFn,
      observes=["option:<source>"],
      reasons=["absent-source"],
      run=borrow_fn,
    ),
    @engine.cell_fn_descriptor(
      "env",
      [@engine.cell_fn_parameter("var")],
      @engine.ValueOutput,
      @engine.RejectFn,
      observes=["env:<var>"],
      reasons=["absent-source"],
      run=env_fn,
    ),
    @engine.cell_fn_descriptor(
      "inherit",
      [@engine.cell_fn_parameter("source")],
      @engine.ValueOutput,
      @engine.RejectFn,
      observes=["option:<source>"],
      reasons=["absent-source"],
      run=inherit_fn,
    ),
    @engine.cell_fn_descriptor(
      "uuid",
      [@engine.cell_fn_parameter("version", repetition=@engine.ZeroOrOne)],
      @engine.StringOutput,
      @engine.TotalFn,
      validate=validate_uuid,
      run=uuid_fn,
    ),
    @engine.cell_fn_descriptor(
      "computed",
      [@engine.cell_fn_parameter("key")],
      @engine.ValueOutput,
      @engine.RejectFn,
      observes=["system:<key>"],
      reasons=["absent-source"],
      run=computed_fn,
    ),
  ]
}
