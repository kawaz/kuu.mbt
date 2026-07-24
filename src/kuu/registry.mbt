// registry.mbt — canonical kuu assembly of engine extension residents.

///|
fn register_node(registry : @node.Registry, node : @node.Node) -> Unit {
  guard node is @engine.Ext(resident) else {
    abort("builtin node factory did not return an Ext resident")
  }
  guard registry.register_node(resident) else {
    abort("duplicate builtin node resident kind: " + resident.kind())
  }
}

///|
fn register_type(
  registry : @node.Registry,
  resident : &@extension.TypeExt,
) -> Unit {
  guard registry.register_type(resident) else {
    abort("duplicate builtin type resident name: " + resident.name())
  }
}

///|
fn register_matcher(
  registry : @node.Registry,
  resident : &@extension.MatcherExt,
) -> Unit {
  guard registry.register_matcher(resident) else {
    abort("duplicate builtin matcher resident kind: " + resident.kind())
  }
}

///|
fn register_accumulator(
  registry : @node.Registry,
  resident : &@extension.AccumulatorExt,
) -> Unit {
  guard registry.register_accumulator(resident) else {
    abort("duplicate builtin accumulator resident kind: " + resident.kind())
  }
}

///|
fn register_collector(
  registry : @node.Registry,
  resident : &@extension.CollectorExt,
) -> Unit {
  guard registry.register_collector(resident) else {
    abort("duplicate builtin collector resident kind: " + resident.kind())
  }
}

///|
fn register_filter(
  registry : @node.Registry,
  resident : @extension.FilterDescriptor,
) -> Unit {
  guard registry.register_filter(resident) else {
    abort("duplicate builtin filter resident name: " + resident.name())
  }
}

///|
fn register_array_filter(
  registry : @node.Registry,
  resident : @extension.ArrayFilterDescriptor,
) -> Unit {
  guard registry.register_array_filter(resident) else {
    abort("duplicate builtin array filter resident name: " + resident.name())
  }
}

///|
fn register_cell_fn(
  registry : @node.Registry,
  resident : @extension.CellFnDescriptor,
) -> Unit {
  guard registry.register_cell_fn(resident) else {
    abort("duplicate builtin cell fn resident name: " + resident.name())
  }
}

///|
fn register_completer(
  registry : @node.Registry,
  resident : &@extension.CompleterExt,
) -> Unit {
  guard registry.register_completer(resident) else {
    abort("duplicate builtin completer resident name: " + resident.name())
  }
}

///|
/// Register only the canonical installer vocabulary (long / short / env / dd / ... — the
/// DR-042 table) into `registry`. A subset of `install_canonical`; call this directly when
/// composing a custom assembly that swaps residents but keeps the standard vocabulary.
pub fn install_vocabulary(registry : @node.Registry) -> Unit {
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
/// Register the canonical all-resident assembly (vocabulary + node / matcher / type /
/// filter / accumulator / collector / cell-fn residents + the help_query capability).
/// Builtins provides resident factories; the front-door package owns which residents
/// form the default product. `install_vocabulary` is the installer-only subset.
pub fn install_canonical(registry : @node.Registry) -> Unit {
  install_vocabulary(registry)

  register_node(registry, @builtins.string_arg("", []))
  register_node(registry, @builtins.kv_arg("", []))
  register_node(
    registry,
    @builtins.separated_arg(
      "",
      separator=None,
      ty=@builtins.string_type(),
      int_round=@abi.Error,
      bool_config=@builtins.bool_config_canonical(),
      filters=[],
    ),
  )
  register_node(registry, @builtins.number_arg("", filters=[]))
  register_node(registry, @builtins.float_arg("", []))
  register_node(registry, @builtins.int_arg("", round=@abi.Error, filters=[]))
  register_node(
    registry,
    @builtins.bool_arg("", config=@builtins.bool_config_canonical(), filters=[]),
  )
  register_node(
    registry,
    @builtins.typed_arg("", ty=@builtins.string_type(), filters=[]),
  )
  register_node(registry, @builtins.effect_mark("", @abi.Set))
  register_node(registry, @builtins.deprecation_mark(""))
  register_node(registry, @builtins.failure_mark(""))

  register_matcher(registry, @builtins.eq_split("", []))
  register_matcher(registry, @builtins.short_combine("", []))

  register_type(registry, @builtins.string_type())
  register_type(registry, @builtins.number_type())
  register_type(registry, @builtins.int_type())
  register_type(registry, @builtins.float_type())
  register_type(registry, @builtins.bool_type())
  register_type(registry, @builtins.flag_type())
  register_type(registry, @builtins.count_type())
  register_type(registry, @builtins.completion_script_type())
  register_type(registry, @builtins.none_type())

  register_accumulator(registry, @builtins.append_accumulator())
  register_accumulator(registry, @builtins.merge_accumulator())
  register_accumulator(registry, @builtins.kv_map_accumulator())

  register_collector(registry, @builtins.unwrap_single_collector())
  register_collector(
    registry,
    @builtins.from_entries_collector(@extension.Entries),
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

  register_completer(registry, @builtins.files_completer())
  register_completer(registry, @builtins.dirs_completer())

  // DR-113 §1: help_query capability の登録経路。M3c-B では器のみ (fixture runner の invoke
  // 経路への統合は M4 で切り替える)。重複名登録の戻り値は install_canonical() が単発呼びで無視して良い
  // (canonical assembly は 1 度だけ install される、cell_fn_descriptors 群と同じ扱い)。
  let _ = registry.register_capability(help_query_capability())
  let _ = registry.register_capability(completion_script_capability())
}

///|
fn canonical_registry() -> @node.Registry {
  let registry = @node.Registry::new()
  install_canonical(registry)
  registry
}
