///|
/// A synthetic resident keeps the engine contract test independent of builtin
/// node vocabulary. `encoded` is the complete structural descriptor used by
/// the default equality implementation.
priv struct SyntheticNodeExt {
  kind_ : String
  encoded : String
}

///|
impl NodeExt for SyntheticNodeExt with fn kind(self) {
  self.kind_
}

///|
impl NodeExt for SyntheticNodeExt with fn encode(self) {
  self.encoded.to_json()
}

///|
impl NodeExt for SyntheticNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for SyntheticNodeExt with fn eval(_self, ctx, pos, acc, next) {
  next(ctx, pos, acc)
}

///|
fn synthetic_ext(kind_ : String, encoded : String) -> Node {
  Ext(SyntheticNodeExt::{ kind_, encoded } as &NodeExt)
}

///|
test "NodeExt equality is reflexive through Node" {
  // Reflexivity is required for structural AST comparison even though Ext
  // carries a trait object that cannot derive Eq.
  let node = synthetic_ext("synthetic/value", "same")
  assert_true(node == node)
}

///|
test "NodeExt equality rejects different kinds" {
  // Equal encodings do not collapse residents from different descriptor
  // namespaces: kind is the registry identity axis.
  let left = synthetic_ext("synthetic/string", "same")
  let right = synthetic_ext("synthetic/number", "same")
  assert_false(left == right)
}

///|
test "NodeExt equality rejects different encodings" {
  // Equal kinds still differ when resident configuration differs; encode is
  // the complete configuration identity used by lowering comparisons.
  let left = synthetic_ext("synthetic/value", "left")
  let right = synthetic_ext("synthetic/value", "right")
  assert_false(left == right)
}
