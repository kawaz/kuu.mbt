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
  for kind in ["append", "merge", "kv_map"] {
    match registry.lookup_accumulator(kind) {
      Some(resident) => assert_eq(resident.kind(), kind)
      None => fail("canonical accumulator resident is missing: " + kind)
    }
  }
  for kind in ["unwrap_single", "from_entries"] {
    match registry.lookup_collector(kind) {
      Some(resident) => assert_eq(resident.kind(), kind)
      None => fail("canonical collector resident is missing: " + kind)
    }
  }
  // Unknown identities remain observable as absent rather than producing a placeholder resident.
  assert_true(registry.lookup_matcher("missing") is None)
  assert_true(registry.lookup_accumulator("missing") is None)
  assert_true(registry.lookup_collector("missing") is None)
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

///|
test "option and positional allowed keys exclude unregistered installer vocab" {
  // The wire key surface is assembled from the active installer residents. A type resident alone
  // does not authorize either long option spelling or repeat positional syntax.
  let registry = @engine.Registry::new()
  assert_true(registry.register_type(@builtins.string_type()))
  let option = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"string\",\"long\":true}]}",
  )
  match parse_definition(option, extensions=registry) {
    Err(Malformed(reason)) =>
      assert_true(reason.contains("unsupported key 'long'"))
    _ => fail("long must require a registered long installer")
  }
  let positional = @json.parse(
    "{\"positionals\":[{\"name\":\"value\",\"type\":\"string\",\"repeat\":{\"min\":0}}]}",
  )
  match parse_definition(positional, extensions=registry) {
    Err(Malformed(reason)) =>
      assert_true(reason.contains("unsupported key 'repeat'"))
    _ => fail("repeat must require a registered repeat installer")
  }
}

///|
test "repeat lowering rejects an assembly without its implicit append accumulator" {
  // repeat owns its wire vocabulary through the installer, but its value fold is a separate
  // descriptor dependency; an incomplete subset assembly returns a definition error, never aborts.
  let registry = @engine.Registry::new()
  assert_true(registry.register_type(@builtins.string_type()))
  registry.register_installer(@builtins.repeat_installer())
  let definition = @json.parse(
    "{\"positionals\":[{\"name\":\"rest\",\"type\":\"string\",\"repeat\":{\"min\":0}}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Err(Rejected([error])) => {
      assert_eq(error.kind, @engine.DUnknownVocab)
      assert_true(error.message.contains("accumulator 'append'"))
    }
    _ => fail("missing implicit append resident must be a definition error")
  }
}

///|
test "collector declarations reject an assembly without the named collector resident" {
  // The accumulator and multiple vocabulary are present, isolating the collector descriptor as the
  // only missing dependency; lookup failure is reported before lowering constructs the Entity.
  let registry = @engine.Registry::new()
  assert_true(registry.register_type(@builtins.string_type()))
  assert_true(registry.register_accumulator(@builtins.append_accumulator()))
  registry.register_installer(@builtins.long_installer())
  registry.register_installer(@builtins.multiple_installer())
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"string\",\"long\":true,\"multiple\":{\"collector\":\"unwrap_single\"}}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Err(Rejected([error])) => {
      assert_eq(error.kind, @engine.DUnknownVocab)
      assert_true(error.message.contains("collector 'unwrap_single'"))
    }
    _ => fail("missing collector resident must be a definition error")
  }
}

///|
test "registered installer vocab extends option and positional allowed keys" {
  // Registering the corresponding residents makes the same keys decodable; the repeat declaration
  // also needs its append accumulator because lowering resolves every descriptor through the same registry.
  let registry = @engine.Registry::new()
  assert_true(registry.register_type(@builtins.string_type()))
  assert_true(registry.register_accumulator(@builtins.append_accumulator()))
  registry.register_installer(@builtins.long_installer())
  registry.register_installer(@builtins.repeat_installer())
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"string\",\"long\":true}],\"positionals\":[{\"name\":\"rest\",\"type\":\"string\",\"repeat\":{\"min\":0}}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Ok(_) => ()
    Err(_) => fail("registered long/repeat vocab must decode")
  }
}
