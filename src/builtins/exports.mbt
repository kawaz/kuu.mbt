// Canonical resident exports assembled from the public extension and node layers.

///|
pub fn owned_vocab(installer : &@node.InstallerExt) -> String {
  match installer.vocab() {
    [first, ..] => first
    [] => ""
  }
}

///|
pub using @extension {
  type FromEntriesSpec,
  type EqEntry,
  type ShortEntry,
  type ConfigValueError,
  bool_config_canonical,
  bool_type,
  cell_fn_descriptors,
  completion_script_type,
  config_to_value,
  configured_type,
  count_type,
  dirs_completer,
  entity_ext,
  eq_entry,
  eq_split,
  files_completer,
  flag_type,
  int_type,
  float_type,
  from_entries_collector,
  in_range_filter,
  increment_filter,
  kv_map_accumulator,
  length_range_array_filter,
  merge_accumulator,
  non_empty_filter,
  none_type,
  number_type,
  regex_match_filter,
  round_mode_of,
  short_combine,
  short_entry,
  string_type,
  trim_filter,
  tty_type,
  unique_array_filter,
  unwrap_single_collector,
  append_accumulator,
}

///|
pub using @node {
  type Node,
  string_arg,
  kv_arg,
  separated_arg,
  number_arg,
  filtered_number_arg,
  float_arg,
  int_arg,
  bool_arg,
  typed_arg,
  effect_mark,
  deprecation_mark,
  failure_mark,
  enum_value_node,
}
