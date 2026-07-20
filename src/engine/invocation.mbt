// invocation.mbt — shared universal-fn invocation carrier and wire-form parser.

///|
/// The canonical lowered carrier shared by filter and cell-fn invocation.
/// Wire decoders normalize colon strings and one-level string arrays into this
/// name-plus-args shape before registry lookup.
pub(all) struct FnInvocation {
  name : String
  args : Array[String]
} derive(Eq, Debug)

///|
/// One implementation argument. Wire invocations carry `StringArg`; typed
/// internal calls such as fixed `set(value)` carry `ValueArg` without
/// serializing the value through the string DSL.
pub(all) enum FnArg {
  StringArg(String)
  ValueArg(Value)
} derive(Eq, Debug)

///|
/// Registry lookup and implementation invocation carrier.
pub(all) struct FnCall {
  name : String
  args : Array[FnArg]
} derive(Eq, Debug)

///|
/// Default-seat placeholder. Fixed JSON defaults retain native values in a typed call; explicit
/// default_fn wire spellings retain their canonical string invocation until target-aware execution.
pub(all) enum DefaultFnCall {
  WireDefaultFn(FnInvocation)
  TypedDefaultFn(FnCall)
} derive(Eq, Debug)

///|
pub fn DefaultFnCall::to_call(self : DefaultFnCall) -> FnCall {
  match self {
    WireDefaultFn(invocation) => invocation.to_call()
    TypedDefaultFn(call) => call
  }
}

///|
pub fn DefaultFnCall::wire_invocation(self : DefaultFnCall) -> FnInvocation? {
  match self {
    WireDefaultFn(invocation) => Some(invocation)
    TypedDefaultFn(_) => None
  }
}

///|
pub fn FnInvocation::to_call(self : FnInvocation) -> FnCall {
  let args : Array[FnArg] = []
  for arg in self.args {
    args.push(StringArg(arg))
  }
  { name: self.name, args }
}

///|
pub fn typed_fn_call(name : String, values : Array[Value]) -> FnCall {
  let args : Array[FnArg] = []
  for value in values {
    args.push(ValueArg(value))
  }
  { name, args }
}

///|
/// Filter chains use the universal invocation carrier directly.
pub type FilterSpelling = FnInvocation

///|
/// The two equivalent universal-fn wire spellings. `ArrayParts` is already one
/// decoded array level; nested arrays never enter the engine parser.
pub(all) enum FnInvocationForm {
  ColonString(String)
  ArrayParts(Array[String])
} derive(Eq, Debug)

///|
fn split_invocation_colons(spelling : String) -> Array[String] {
  let parts : Array[String] = []
  let mut current = ""
  for char in spelling {
    if char == ':' {
      parts.push(current)
      current = ""
    } else {
      current = current + char.to_string()
    }
  }
  parts.push(current)
  parts
}

///|
/// Decode either wire form into its component sequence. Colon strings split at
/// every colon; array parts remain literal.
pub fn decode_fn_invocation_parts(
  form : FnInvocationForm,
) -> Result[Array[String], String] {
  let parts = match form {
    ColonString(spelling) => split_invocation_colons(spelling)
    ArrayParts(parts) => parts.copy()
  }
  if parts.length() == 0 {
    Err("fn invocation array must contain a name")
  } else {
    Ok(parts)
  }
}

///|
/// Decode either universal-fn wire form to the canonical carrier. Array args
/// are copied verbatim, so an arg containing `:` is never split.
pub fn parse_fn_invocation(
  form : FnInvocationForm,
) -> Result[FnInvocation, String] {
  let parts = match decode_fn_invocation_parts(form) {
    Ok(parts) => parts
    Err(message) => return Err(message)
  }
  let args : Array[String] = []
  let mut index = 1
  while index < parts.length() {
    args.push(parts[index])
    index = index + 1
  }
  Ok({ name: parts[0], args })
}
