// Public open-node extension contract.

///|
/// An open AtomicAST leaf resident. `kind + encode` is its collision-free
/// structural identity; the default `equal` keeps every resident on that one
/// comparison contract. `consumes_zero_tokens` is evaluator contract data,
/// replacing central enumeration of builtin marker variants. `eval` may call
/// the supplied Resume only as the continuation of that invocation; retaining
/// it for a later invocation is unsupported.
pub(open) trait NodeExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &NodeExt) -> Bool = _
  fn element_name(Self) -> String? = _
  fn is_failure_action(Self) -> Bool = _
  fn effect_mark(Self) -> (String, EffectOp)? = _
  fn consumes_zero_tokens(Self) -> Bool
  fn eval(Self, Ctx, Int, Array[Binding], Resume) -> Array[Branch]
}

///|
impl NodeExt with fn equal(self, other) {
  self.kind() == other.kind() && self.encode() == other.encode()
}

///|
impl NodeExt with fn element_name(_self) {
  None
}

///|
impl NodeExt with fn is_failure_action(_self) {
  false
}

///|
impl NodeExt with fn effect_mark(_self) {
  None
}
