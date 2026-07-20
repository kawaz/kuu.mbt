// cell_fn.mbt — cell-fn contracts and Value-or-Sentinel result ABI.

///|
pub(all) enum CellFnRepetition {
  Once
  ZeroOrOne
  OneOrMore
} derive(Eq, Debug)

///|
/// Descriptor parameter input kind. A `value` parameter accepts either a wire
/// string awaiting target-aware decode or a typed internal `Value`.
pub(all) enum CellFnParameterKind {
  String
  Value
} derive(Eq, Debug)

///|
pub(all) struct CellFnParameter {
  name : String
  kind : CellFnParameterKind
  repetition : CellFnRepetition
} derive(Eq, Debug)

///|
pub fn cell_fn_parameter(
  name : String,
  kind? : CellFnParameterKind = String,
  repetition? : CellFnRepetition = Once,
) -> CellFnParameter {
  { name, kind, repetition }
}

///|
pub(all) enum CellFnArity {
  Exact(Int)
  Between(Int, Int)
  AtLeast(Int)
} derive(Eq, Debug)

///|
pub fn CellFnArity::accepts(self : CellFnArity, count : Int) -> Bool {
  match self {
    Exact(expected) => count == expected
    Between(minimum, maximum) => count >= minimum && count <= maximum
    AtLeast(minimum) => count >= minimum
  }
}

///|
pub(all) enum FnFallibility {
  TotalFn
  RejectFn
} derive(Eq, Debug)

///|
pub(all) enum CellSentinel {
  UseDefault
  Unset
  Empty
} derive(Eq, Debug)

///|
/// Static output contract used to validate a call seat before execution.
pub(all) enum CellFnOutput {
  Value
  Number
  String
  Sentinel(CellSentinel)
} derive(Eq, Debug)

///|
/// Cell-fn output is either a value to send through the normal set path or a
/// sentinel cell operation.
pub(all) enum FnOutput {
  Value(Value)
  Sentinel(CellSentinel)
} derive(Eq, Debug)

///|
pub type FnReason = (String, String)

///|
pub type FnResult = Result[FnOutput, FnReason]

///|
/// Universal cell-fn implementation ABI. `FnArg` preserves the distinction
/// between wire strings and typed internal values.
pub type CellFn = (Array[FnArg], FnCtx) -> FnResult

///|
/// Definition-time contract retained by the `cell_fns` registry.
pub struct CellFnDescriptor {
  priv name_ : String
  priv parameters_ : Array[CellFnParameter]
  priv output_ : CellFnOutput
  priv fallibility_ : FnFallibility
  priv observes_ : Array[String]
  priv reasons_ : Array[String]
  priv validate_ : (FnCall) -> Result[Unit, FnReason]
  priv run_ : CellFn
}

///|
pub fn cell_fn_descriptor(
  name : String,
  parameters : Array[CellFnParameter],
  output : CellFnOutput,
  fallibility : FnFallibility,
  observes? : Array[String] = [],
  reasons? : Array[String] = [],
  validate? : (FnCall) -> Result[Unit, FnReason] = fn(_) { Ok(()) },
  run? : CellFn = fn(_, _) {
    Err(("absent-source", "cell fn implementation is not registered"))
  },
) -> CellFnDescriptor {
  {
    name_: name,
    parameters_: parameters.copy(),
    output_: output,
    fallibility_: fallibility,
    observes_: observes.copy(),
    reasons_: reasons.copy(),
    validate_: validate,
    run_: run,
  }
}

///|
pub fn CellFnDescriptor::name(self : CellFnDescriptor) -> String {
  self.name_
}

///|
pub fn CellFnDescriptor::parameters(
  self : CellFnDescriptor,
) -> Array[CellFnParameter] {
  self.parameters_.copy()
}

///|
pub fn CellFnDescriptor::output(self : CellFnDescriptor) -> CellFnOutput {
  self.output_
}

///|
pub fn CellFnDescriptor::arity(self : CellFnDescriptor) -> CellFnArity {
  let mut minimum = 0
  let mut maximum = 0
  let mut unbounded = false
  for parameter in self.parameters_ {
    match parameter.repetition {
      Once => {
        minimum = minimum + 1
        maximum = maximum + 1
      }
      ZeroOrOne => maximum = maximum + 1
      OneOrMore => {
        minimum = minimum + 1
        unbounded = true
      }
    }
  }
  if unbounded {
    AtLeast(minimum)
  } else if minimum == maximum {
    Exact(minimum)
  } else {
    Between(minimum, maximum)
  }
}

///|
pub fn CellFnDescriptor::fallibility(self : CellFnDescriptor) -> FnFallibility {
  self.fallibility_
}

///|
pub fn CellFnDescriptor::observes(self : CellFnDescriptor) -> Array[String] {
  self.observes_.copy()
}

///|
pub fn CellFnDescriptor::reasons(self : CellFnDescriptor) -> Array[String] {
  self.reasons_.copy()
}

///|
/// Validate the carrier before entering the resident implementation. Definition-time validation
/// should make the error branch unreachable for accepted wire definitions; keeping the same gate at
/// the registry boundary protects native typed calls and third-party callers.
pub fn CellFnDescriptor::invoke(
  self : CellFnDescriptor,
  call : FnCall,
  ctx : FnCtx,
) -> FnResult {
  match self.validate_call(call) {
    Err(reason) => Err(reason)
    Ok(_) => (self.run_)(call.args, ctx)
  }
}

///|
fn CellFnDescriptor::invalid_argument(
  self : CellFnDescriptor,
  message : String,
) -> FnReason {
  ("invalid-argument", "cell fn '" + self.name_ + "' " + message)
}

///|
fn CellFnDescriptor::has_valid_parameter_shape(self : CellFnDescriptor) -> Bool {
  let mut repeated = false
  let mut index = 0
  while index < self.parameters_.length() {
    let parameter = self.parameters_[index]
    if parameter.repetition is OneOrMore || parameter.repetition is ZeroOrOne {
      if repeated || index + 1 != self.parameters_.length() {
        return false
      }
      repeated = true
    }
    let mut earlier = 0
    while earlier < index {
      if self.parameters_[earlier].name == parameter.name {
        return false
      }
      earlier = earlier + 1
    }
    index = index + 1
  }
  true
}

///|
pub fn CellFnDescriptor::validate_arity(
  self : CellFnDescriptor,
  count : Int,
) -> Result[Unit, FnReason] {
  if !self.has_valid_parameter_shape() {
    return Err(
      self.invalid_argument(
        "has an invalid parameter contract: names must be unique and a repeated parameter must be last",
      ),
    )
  }
  if self.arity().accepts(count) {
    Ok(())
  } else {
    Err(self.invalid_argument("does not accept " + count.to_string() + " args"))
  }
}

///|
fn CellFnParameter::accepts(self : CellFnParameter, argument : FnArg) -> Bool {
  match self.kind {
    String => argument is String(_)
    Value => true
  }
}

///|
fn CellFnDescriptor::parameter_at_arg(
  self : CellFnDescriptor,
  index : Int,
) -> CellFnParameter {
  if index < self.parameters_.length() {
    self.parameters_[index]
  } else {
    self.parameters_[self.parameters_.length() - 1]
  }
}

///|
pub fn CellFnDescriptor::validate_call(
  self : CellFnDescriptor,
  call : FnCall,
) -> Result[Unit, FnReason] {
  if call.name != self.name_ {
    return Err(
      self.invalid_argument("cannot validate invocation '" + call.name + "'"),
    )
  }
  match self.validate_arity(call.args.length()) {
    Err(reason) => return Err(reason)
    Ok(_) => ()
  }
  let mut index = 0
  while index < call.args.length() {
    let parameter = self.parameter_at_arg(index)
    if !parameter.accepts(call.args[index]) {
      return Err(
        self.invalid_argument(
          "argument " +
          index.to_string() +
          " for parameter '" +
          parameter.name +
          "' has an incompatible carrier",
        ),
      )
    }
    index = index + 1
  }
  (self.validate_)(call)
}

///|
pub fn CellFnDescriptor::validate_invocation(
  self : CellFnDescriptor,
  invocation : FnInvocation,
) -> Result[Unit, FnReason] {
  self.validate_call(invocation.to_call())
}

///|
fn CellFnDescriptor::parameter_value(
  self : CellFnDescriptor,
  parameter : CellFnParameter,
  index : Int,
  args : Array[String],
) -> Result[String, FnReason] {
  match parameter.repetition {
    Once | ZeroOrOne => Ok(args[index])
    OneOrMore =>
      if args.length() - index == 1 {
        Ok(args[index])
      } else {
        Err(
          self.invalid_argument(
            "cannot bind repeated parameter '" +
            parameter.name +
            "' to one observes edge",
          ),
        )
      }
  }
}

///|
/// Validate one wire invocation and bind descriptor observation templates to
/// its positional string arguments. The result contains concrete `option:*`,
/// `env:*`, and `system:*` capability edges suitable for `FnCtx`.
pub fn CellFnDescriptor::concrete_observes(
  self : CellFnDescriptor,
  invocation : FnInvocation,
) -> Result[Array[String], FnReason] {
  match self.validate_invocation(invocation) {
    Err(reason) => return Err(reason)
    Ok(_) => ()
  }
  let concrete : Array[String] = []
  for template in self.observes_ {
    let mut edge = template
    let mut index = 0
    while index < self.parameters_.length() {
      let parameter = self.parameters_[index]
      let marker = "<" + parameter.name + ">"
      if edge.contains(marker) {
        let value = match
          self.parameter_value(parameter, index, invocation.args) {
          Ok(value) => value
          Err(reason) => return Err(reason)
        }
        edge = edge.replace(old=marker, new=value)
      }
      index = index + 1
    }
    if edge.contains("<") || edge.contains(">") {
      return Err(
        self.invalid_argument(
          "has an unbound observes template '" + template + "'",
        ),
      )
    }
    concrete.push(edge)
  }
  Ok(concrete)
}
