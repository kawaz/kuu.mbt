// registry.mbt — canonical kuu assembly of engine extension residents.

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
fn register_matcher(
  registry : @engine.Registry,
  resident : &@engine.MatcherExt,
) -> Unit {
  guard registry.register_matcher(resident) else {
    abort("duplicate builtin matcher resident kind: " + resident.kind())
  }
}

///|
fn register_accumulator(
  registry : @engine.Registry,
  resident : &@engine.AccumulatorExt,
) -> Unit {
  guard registry.register_accumulator(resident) else {
    abort("duplicate builtin accumulator resident kind: " + resident.kind())
  }
}

///|
fn register_collector(
  registry : @engine.Registry,
  resident : &@engine.CollectorExt,
) -> Unit {
  guard registry.register_collector(resident) else {
    abort("duplicate builtin collector resident kind: " + resident.kind())
  }
}

///|
fn register_filter(
  registry : @engine.Registry,
  resident : @engine.FilterDescriptor,
) -> Unit {
  guard registry.register_filter(resident) else {
    abort("duplicate builtin filter resident name: " + resident.name)
  }
}

///|
fn register_array_filter(
  registry : @engine.Registry,
  resident : @engine.ArrayFilterDescriptor,
) -> Unit {
  guard registry.register_array_filter(resident) else {
    abort("duplicate builtin array filter resident name: " + resident.name)
  }
}

///|
fn register_cell_fn(
  registry : @engine.Registry,
  resident : @engine.CellFnDescriptor,
) -> Unit {
  guard registry.register_cell_fn(resident) else {
    abort("duplicate builtin cell fn resident name: " + resident.name())
  }
}

///|
pub fn install_installers(registry : @engine.Registry) -> Unit {
  registry.register_installer(@builtins.long_installer())
  registry.register_installer(@builtins.short_installer())
  registry.register_installer(@builtins.env_installer())
  registry.register_installer(@builtins.dd_installer())
  registry.register_installer(@builtins.global_installer())
  registry.register_installer(@builtins.inherit_installer())
  registry.register_installer(@builtins.repeat_installer())
  registry.register_installer(@builtins.multiple_installer())
  registry.register_installer(@builtins.config_installer())
  registry.register_installer(@builtins.constraint_installer())
  registry.register_installer(@builtins.alias_installer())
  registry.register_installer(@builtins.inheritable_installer())
  registry.register_installer(@builtins.command_installer())
  registry.register_installer(@builtins.help_meta_installer())
}

///|
/// Register the canonical all-resident assembly. Builtins provides resident factories;
/// the front-door package owns which residents form the default product.
pub fn install(registry : @engine.Registry) -> Unit {
  install_installers(registry)

  register_node(registry, @builtins.string_arg("", []))
  register_node(registry, @builtins.kv_arg("", []))
  register_node(
    registry,
    @builtins.separated_arg(
      "",
      None,
      @builtins.string_type(),
      @engine.RError,
      false,
      @builtins.bool_config_canonical(),
      [],
      false,
    ),
  )
  register_node(registry, @builtins.number_arg("", false, []))
  register_node(registry, @builtins.float_arg("", []))
  register_node(registry, @builtins.int_arg("", @engine.RError, false, []))
  register_node(
    registry,
    @builtins.bool_arg("", @builtins.bool_config_canonical(), []),
  )
  register_node(registry, @builtins.typed_arg("", @builtins.string_type(), []))
  register_node(registry, @builtins.effect_mark("", @engine.Set))
  register_node(registry, @builtins.deprecation_mark(""))
  register_node(registry, @builtins.failure_mark(""))

  register_matcher(registry, @builtins.eq_split("", []))
  register_matcher(registry, @builtins.short_combine("", [], true))

  register_type(registry, @builtins.string_type())
  register_type(registry, @builtins.number_type())
  register_type(registry, @builtins.int_type())
  register_type(registry, @builtins.float_type())
  register_type(registry, @builtins.bool_type())
  register_type(registry, @builtins.flag_type())
  register_type(registry, @builtins.count_type())
  register_type(registry, @builtins.none_type())

  register_accumulator(registry, @builtins.append_accumulator())
  register_accumulator(registry, @builtins.merge_accumulator())
  register_accumulator(registry, @builtins.kv_map_accumulator())

  register_collector(registry, @builtins.unwrap_single_collector())
  register_collector(
    registry,
    @builtins.from_entries_collector(@builtins.Entries),
  )

  register_filter(registry, @builtins.trim_filter())
  register_filter(registry, @builtins.non_empty_filter())
  register_filter(registry, @builtins.in_range_filter())
  register_filter(registry, @builtins.regex_match_filter())
  register_filter(registry, @builtins.increment_filter())
  register_array_filter(registry, @builtins.unique_array_filter())
  register_array_filter(registry, @builtins.length_range_array_filter())

  for descriptor in @builtins.cell_fn_descriptors() {
    register_cell_fn(registry, descriptor)
  }

  // DR-113 §1: help_query capability の登録経路。M3c-B では器のみ (fixture runner の invoke
  // 経路への統合は M4 で切り替える)。重複名登録の戻り値は install() が単発呼びで無視して良い
  // (canonical assembly は 1 度だけ install される、cell_fn_descriptors 群と同じ扱い)。
  let _ = registry.register_capability(help_query_capability())
}

///|
fn canonical_registry() -> @engine.Registry {
  let registry = @engine.Registry::new()
  install(registry)
  registry
}
