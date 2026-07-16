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
priv struct SyntheticCapabilityExt {
  name : String
  failure_action : Bool
  effect : (String, EffectOp)?
}

///|
impl NodeExt for SyntheticCapabilityExt with fn kind(_self) {
  "synthetic/capability"
}

///|
impl NodeExt for SyntheticCapabilityExt with fn encode(_self) {
  ().to_json()
}

///|
impl NodeExt for SyntheticCapabilityExt with fn element_name(self) {
  Some(self.name)
}

///|
impl NodeExt for SyntheticCapabilityExt with fn is_failure_action(self) {
  self.failure_action
}

///|
impl NodeExt for SyntheticCapabilityExt with fn effect_mark(self) {
  self.effect
}

///|
impl NodeExt for SyntheticCapabilityExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl NodeExt for SyntheticCapabilityExt with fn eval(_self, ctx, pos, acc, next) {
  next(ctx, pos, acc)
}

///|
test "NodeExt semantic capabilities do not depend on builtin kind or encode layout" {
  // Third-party residents expose engine metadata through methods while keeping their own namespace
  // and arbitrary encoding shape.
  let node = Ext(
    SyntheticCapabilityExt::{
      name: "custom",
      failure_action: true,
      effect: Some(("custom", Unset)),
    }
    as &NodeExt,
  )
  assert_eq(node_resident_name(node), Some("custom"))
  assert_true(node_is_failure_mark(node))
  assert_eq(node_effect_mark(node), Some(("custom", Unset)))
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
