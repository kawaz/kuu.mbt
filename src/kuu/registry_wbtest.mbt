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
      "string", "number", "int", "float", "bool", "flag", "count", "completion_script",
      "none",
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
  for
    name in [
      "set", "default", "unset", "empty", "incr", "borrow", "env", "inherit", "uuid",
      "computed",
    ] {
    match registry.lookup_cell_fn(name) {
      Some(resident) => assert_eq(resident.name(), name)
      None => fail("canonical cell fn resident is missing: " + name)
    }
  }
  for name in ["files", "dirs"] {
    match registry.lookup_completer(name) {
      Some(resident) => assert_eq(resident.name(), name)
      None => fail("canonical completer resident is missing: " + name)
    }
  }
  for name in ["help_query", "completion_script"] {
    match registry.lookup_capability(name) {
      Some(resident) => assert_eq(resident.name(), name)
      None => fail("canonical capability is missing: " + name)
    }
  }
  // Unknown identities remain observable as absent rather than producing a placeholder resident.
  assert_true(registry.lookup_matcher("missing") is None)
  assert_true(registry.lookup_accumulator("missing") is None)
  assert_true(registry.lookup_collector("missing") is None)
  assert_true(registry.lookup_completer("missing") is None)
}

///|
priv struct CustomTypeExt {}

///|
impl @extension.TypeExt for CustomTypeExt with fn name(_self) {
  "custom"
}

///|
impl @extension.TypeExt for CustomTypeExt with fn encode(_self) {
  "v1".to_json()
}

///|
impl @extension.TypeExt for CustomTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for CustomTypeExt with fn parse_token(_self, token) {
  if token == "rejected" {
    Err(@abi.TypeParseFail::{
      disposition: @abi.ValueSpaceMiss,
      reason: "custom_rejected",
      message: "custom parser rejected the token",
    })
  } else if token == "invalid" {
    Err(@abi.TypeParseFail::{
      disposition: @abi.RecognizedButInvalid,
      reason: "custom_invalid",
      message: "custom parser recognized an invalid value",
    })
  } else {
    Ok(@abi.String("custom:" + token))
  }
}

///|
impl @extension.TypeExt for CustomTypeExt with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
test "parse_definition resolves a custom type through the supplied Registry" {
  // The registry is a live lowering input: a third-party TypeExt can be selected by wire name
  // without adding a builtin switch arm.
  let registry = canonical_registry()
  assert_true(
    registry.register_type(CustomTypeExt::{  } as &@extension.TypeExt),
  )
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"custom\",\"long\":true}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Ok(ast) =>
      match parse_legacy(ast, ["--value", "x"]) {
        @engine.Success(bindings) => {
          assert_eq(bindings.length(), 1)
          assert_eq(bindings[0].value, @abi.String("custom:x"))
        }
        _ => fail("custom type input must parse through its TypeExt")
      }
    Err(_) => fail("registered custom type must lower")
  }
}

///|
test "a third-party type controls its Reject/Error phase and diagnostic vocabulary" {
  // The resident declares both phase and open vocabulary. Reject stays silent even when no complete
  // reading survives; Error transports the resident-owned diagnostic as Held.
  let registry = canonical_registry()
  assert_true(
    registry.register_type(CustomTypeExt::{  } as &@extension.TypeExt),
  )
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"custom\",\"long\":true}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Ok(ast) => {
      match parse_legacy(ast, ["--value", "rejected"]) {
        @engine.Failure(data) =>
          for error in data.errors {
            assert_false(error.reason == "custom_rejected")
          }
        _ => fail("a value-space miss must not produce a complete reading")
      }
      match parse_legacy(ast, ["--value", "invalid"]) {
        @engine.Failure(data) => {
          assert_eq(data.errors.length(), 1)
          assert_eq(data.errors[0].reason, "custom_invalid")
          assert_eq(
            data.errors[0].message,
            "custom parser recognized an invalid value",
          )
        }
        _ => fail("a recognized-invalid value must remain a visible Error")
      }
    }
    Err(_) => fail("registered custom type must lower")
  }
}

///|
fn third_party_prefix_filter() -> @extension.FilterDescriptor {
  @extension.filter_descriptor("third_party_prefix", @extension.Transform, [], fn(
    value,
    _args,
  ) {
    match value {
      @abi.String(text) => Ok(@abi.String("third-party:" + text))
      other => Ok(other)
    }
  })
}

///|
test "a third-party filter parses through the engine contract without a builtin filter API" {
  // The custom resident is expressed only with engine-owned descriptor/value types. Registering it
  // into the active assembly makes definition checking and resolve-time execution observe the same
  // name, proving that builtin filter tables are not required for extension filters.
  let registry = canonical_registry()
  assert_true(registry.register_filter(third_party_prefix_filter()))
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"string\",\"long\":true,\"value_filters\":[\"third_party_prefix\"]}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Ok(ast) => {
      let parsed = parse_legacy(ast, ["--value", "x"])
      match resolve_legacy(ast, parsed, ["--value", "x"]) {
        @engine.Success([binding]) =>
          assert_eq(binding.value, @abi.String("third-party:x"))
        _ =>
          fail(
            "registered third-party filter must transform the resolved value",
          )
      }
    }
    Err(_) =>
      fail("registered third-party filter must pass definition checking")
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
      assert_eq(error.kind, @abi.UnknownVocab)
    }
    _ => fail("unregistered type must produce one definition error")
  }
}

///|
test "option and positional allowed keys exclude unregistered installer vocab" {
  // The wire key surface is assembled from the active installer residents. A type resident alone
  // does not authorize either long option spelling or repeat positional syntax.
  let registry = @node.Registry::new()
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
  let registry = @node.Registry::new()
  assert_true(registry.register_type(@builtins.string_type()))
  registry.register_installer(@builtins.repeat_installer())
  let definition = @json.parse(
    "{\"positionals\":[{\"name\":\"rest\",\"type\":\"string\",\"repeat\":{\"min\":0}}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Err(Rejected([error])) => {
      assert_eq(error.kind, @abi.UnknownVocab)
      assert_true(error.message.contains("accumulator 'append'"))
    }
    _ => fail("missing implicit append resident must be a definition error")
  }
}

///|
test "collector declarations reject an assembly without the named collector resident" {
  // The accumulator and multiple vocabulary are present, isolating the collector descriptor as the
  // only missing dependency; lookup failure is reported before lowering constructs the Entity.
  let registry = @node.Registry::new()
  assert_true(registry.register_type(@builtins.string_type()))
  assert_true(registry.register_accumulator(@builtins.append_accumulator()))
  registry.register_installer(@builtins.long_installer())
  registry.register_installer(@builtins.multiple_installer())
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"value\",\"type\":\"string\",\"long\":true,\"multiple\":{\"collector\":\"unwrap_single\"}}]}",
  )
  match parse_definition(definition, extensions=registry) {
    Err(Rejected([error])) => {
      assert_eq(error.kind, @abi.UnknownVocab)
      assert_true(error.message.contains("collector 'unwrap_single'"))
    }
    _ => fail("missing collector resident must be a definition error")
  }
}

///|
test "custom type controls child-default Reject/Error phase without reason matching" {
  let custom = CustomTypeExt::{  } as &@extension.TypeExt
  let registry = @extension.Registry::new()
  let root : @engine.Scope = {
    greedy: [],
    positional: [
      @engine.ChildDefault(
        @builtins.typed_arg("value", ty=custom, filters=[]),
        "#seat:value",
        "value",
      ),
      @builtins.string_arg("rest", []),
    ],
    entities: [],
    constraints: [],
  }
  match
    @engine.parse_tree(
      @engine.ScopeNode(root),
      ["rejected"],
      defs=Map([]),
      extensions=registry,
    ) {
    @engine.Success(bindings) => {
      let mut fallback = false
      let mut rest = false
      for binding in bindings {
        if binding.key == "#seat:value" {
          fallback = true
        } else if binding.key == "rest" &&
          binding.value == @abi.String("rejected") {
          rest = true
        }
      }
      assert_true(fallback)
      assert_true(rest)
    }
    _ => fail("ValueSpaceMiss must fall back to the child default seat")
  }
  match
    @engine.parse_tree(
      @engine.ScopeNode(root),
      ["invalid"],
      defs=Map([]),
      extensions=registry,
    ) {
    @engine.Failure(failure) => {
      let mut held = false
      for error in failure.errors {
        if error.reason == "custom_invalid" {
          held = true
        }
      }
      assert_true(held)
    }
    _ => fail("RecognizedButInvalid must stay Held and suppress fallback")
  }
}

///|
test "registered installer vocab extends option and positional allowed keys" {
  // Registering the corresponding residents makes the same keys decodable; the repeat declaration
  // also needs its append accumulator because lowering resolves every descriptor through the same registry.
  let registry = @node.Registry::new()
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
