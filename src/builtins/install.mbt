// install.mbt — canonical builtin resident registration.

///|
fn register_node(registry : @engine.Registry, node : @engine.Node) -> Unit {
  guard node is @engine.Ext(resident) else {
    abort("builtin node factory did not return an Ext resident")
  }
  guard registry.register_node(resident) else {
    abort("duplicate builtin node resident kind: " + resident.kind())
  }
}

///|
fn register_type(
  registry : @engine.Registry,
  resident : &@engine.TypeExt,
) -> Unit {
  guard registry.register_type(resident) else {
    abort("duplicate builtin type resident name: " + resident.name())
  }
}

///|
/// Register the canonical resident families. Node entries are identity-bearing
/// prototypes; lowering constructs configured instances of the same resident kinds.
pub fn install(registry : @engine.Registry) -> Unit {
  register_node(registry, string_arg("", []))
  register_node(registry, kv_arg("", []))
  register_node(
    registry,
    separated_arg(
      "",
      None,
      string_type(),
      @engine.RError,
      false,
      @engine.bool_config_canonical(),
      [],
      false,
    ),
  )
  register_node(registry, number_arg("", false, []))
  register_node(registry, float_arg("", []))
  register_node(registry, int_arg("", @engine.RError, false, []))
  register_node(registry, bool_arg("", @engine.bool_config_canonical(), []))
  register_node(registry, typed_arg("", string_type(), []))
  register_node(registry, effect_mark("", @engine.Set))
  register_node(registry, deprecation_mark(""))
  register_node(registry, failure_mark(""))

  register_type(registry, string_type())
  register_type(registry, number_type())
  register_type(registry, int_type())
  register_type(registry, float_type())
  register_type(registry, bool_type())
  register_type(registry, flag_type())
  register_type(registry, count_type())
  register_type(registry, none_type())
}
