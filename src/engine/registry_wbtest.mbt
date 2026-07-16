// registry_wbtest.mbt — extension inventory contract independent of builtin residents.

///|
priv struct RegistryNodeExt {
  encoded : String
}

///|
impl NodeExt for RegistryNodeExt with fn kind(_self) {
  "synthetic/node"
}

///|
impl NodeExt for RegistryNodeExt with fn encode(self) {
  self.encoded.to_json()
}

///|
impl NodeExt for RegistryNodeExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl NodeExt for RegistryNodeExt with fn eval(_self, ctx, pos, acc, next) {
  next(ctx, pos, acc)
}

///|
priv struct RegistryMatcherExt {}

///|
impl MatcherExt for RegistryMatcherExt with fn kind(_self) {
  "synthetic/matcher"
}

///|
impl MatcherExt for RegistryMatcherExt with fn encode(_self) {
  "matcher".to_json()
}

///|
impl MatcherExt for RegistryMatcherExt with fn candidates(_self) {
  []
}

///|
impl MatcherExt for RegistryMatcherExt with fn interpret(
  _self,
  ctx,
  pos,
  acc,
  next,
) {
  next(ctx, pos, acc)
}

///|
priv struct RegistryTypeExt {}

///|
impl TypeExt for RegistryTypeExt with fn name(_self) {
  "synthetic"
}

///|
impl TypeExt for RegistryTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for RegistryTypeExt with fn parse_token(_self, token) {
  Ok(VStr(token))
}

///|
impl TypeExt for RegistryTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
test "Registry registers and looks up each extension category in an independent namespace" {
  // Node, matcher, and type identities occupy separate maps, so registering one category cannot
  // displace another category's resident.
  let registry = Registry::new()
  assert_true(
    registry.register_node(RegistryNodeExt::{ encoded: "node" } as &NodeExt),
  )
  assert_true(
    registry.register_matcher(RegistryMatcherExt::{  } as &MatcherExt),
  )
  assert_true(registry.register_type(RegistryTypeExt::{  } as &TypeExt))

  match registry.lookup_node("synthetic/node") {
    Some(resident) => assert_eq(resident.encode(), "node".to_json())
    None => fail("registered node resident must be found")
  }
  match registry.lookup_matcher("synthetic/matcher") {
    Some(resident) => assert_eq(resident.encode(), "matcher".to_json())
    None => fail("registered matcher resident must be found")
  }
  match registry.lookup_type("synthetic") {
    Some(resident) => assert_eq(resident.name(), "synthetic")
    None => fail("registered type resident must be found")
  }
  assert_true(registry.lookup_node("missing") is None)
  assert_true(registry.lookup_matcher("missing") is None)
  assert_true(registry.lookup_type("missing") is None)
}

///|
test "Registry rejects duplicate identity without replacing the first resident" {
  // A canonical assembly is a one-owner composition table. A later resident with the same kind
  // reports false and the original representative remains observable.
  let registry = Registry::new()
  assert_true(
    registry.register_node(RegistryNodeExt::{ encoded: "first" } as &NodeExt),
  )
  assert_false(
    registry.register_node(RegistryNodeExt::{ encoded: "second" } as &NodeExt),
  )
  match registry.lookup_node("synthetic/node") {
    Some(resident) => assert_eq(resident.encode(), "first".to_json())
    None => fail("first resident must remain registered")
  }
}
