// registry_wbtest.mbt — canonical kuu assembly inventory.

///|
test "canonical_registry installs every builtin node and type resident" {
  // Assembly owns the canonical set; consumers look up residents without importing builtin constructors.
  let registry = canonical_registry()
  for
    kind in [
      "builtin/string", "builtin/kv", "builtin/separated", "builtin/number", "builtin/float",
      "builtin/int", "builtin/bool", "builtin/typed", "builtin/effect", "builtin/deprecation",
      "builtin/failure",
    ] {
    match registry.lookup_node(kind) {
      Some(resident) => assert_eq(resident.kind(), kind)
      None => fail("canonical node resident is missing: " + kind)
    }
  }
  for kind in ["eq_split", "short_combine"] {
    match registry.lookup_matcher(kind) {
      Some(resident) => assert_eq(resident.kind(), kind)
      None => fail("canonical matcher resident is missing: " + kind)
    }
  }
  for
    name in [
      "string", "number", "int", "float", "bool", "flag", "count", "none",
    ] {
    match registry.lookup_type(name) {
      Some(resident) => assert_eq(resident.name(), name)
      None => fail("canonical type resident is missing: " + name)
    }
  }
  // Unknown identities remain observable as absent rather than producing a placeholder resident.
  assert_true(registry.lookup_matcher("missing") is None)
}

///|
priv struct CustomTypeExt {}

///|
impl @engine.TypeExt for CustomTypeExt with fn name(_self) {
  "custom"
}

///|
impl @engine.TypeExt for CustomTypeExt with fn encode(_self) {
  "v1".to_json()
}

///|
impl @engine.TypeExt for CustomTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @engine.TypeExt for CustomTypeExt with fn parse_token(_self, token) {
  Ok(@engine.VStr("custom:" + token))
}

///|
impl @engine.TypeExt for CustomTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
test "parse_definition resolves a custom type through the supplied Registry" {
  // The registry is a live lowering input: a third-party TypeExt can be selected by wire name
  // without adding a builtin switch arm.
  let registry = @engine.Registry::new()
  @builtins.install(registry)
  assert_true(registry.register_type(CustomTypeExt::{  } as &@engine.TypeExt))
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"custom\",\"long\":true}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Ok(ast) =>
      match parse(ast, ["--value", "x"]) {
        @engine.Success(bindings) => {
          assert_eq(bindings.length(), 1)
          assert_eq(bindings[0].value, @engine.VStr("custom:x"))
        }
        _ => fail("custom type input must parse through its TypeExt")
      }
    Err(_) => fail("registered custom type must lower")
  }
}

///|
test "parse_definition rejects an unregistered type as a definition error" {
  // A syntactically valid type name absent from the assembly is not malformed wire and never
  // silently degrades to the none resident.
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"missing\",\"long\":true}]}",
  )
  match parse_definition(definition) {
    Err(Rejected([error])) => {
      assert_eq(error.element, "value")
      assert_eq(error.kind, @engine.DUnknownVocab)
    }
    _ => fail("unregistered type must produce one definition error")
  }
}
