// installer_residents.mbt — canonical builtin installer residents.

///|
fn resident_object(json : Json) -> Result[Map[String, Json], String] {
  match json {
    Object(object) => Ok(object)
    _ => Err("element is not an object")
  }
}

///|
fn resident_string(object : Map[String, Json], key : String) -> String? {
  match object.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn resident_number(
  object : Map[String, Json],
  key : String,
) -> Result[Double?, String] {
  match object.get(key) {
    None => Ok(None)
    Some(Number(value, ..)) => Ok(Some(value))
    Some(_) => Err(key + " is not a number")
  }
}

///|
fn resident_bool(
  object : Map[String, Json],
  key : String,
  default : Bool,
) -> Result[Bool, String] {
  match object.get(key) {
    None => Ok(default)
    Some(True) => Ok(true)
    Some(False) => Ok(false)
    Some(_) => Err(key + " is not a bool")
  }
}

///|
fn resident_strings(
  object : Map[String, Json],
  key : String,
) -> Result[Array[String], String] {
  match object.get(key) {
    None => Ok([])
    Some(String(value)) => Ok([value])
    Some(Array(values)) => {
      let output : Array[String] = []
      for value in values {
        match value {
          String(text) => output.push(text)
          _ => return Err(key + "[] element is not a string")
        }
      }
      Ok(output)
    }
    Some(_) => Err(key + " is not a string or string[]")
  }
}

///|
fn resident_long(json : Json) -> Result[@engine.LongDeclaration, String] {
  match json {
    True => Ok(Bool(true))
    False => Ok(Bool(false))
    Array(values) => {
      let strings : Array[String] = []
      let forms : Array[@engine.FnInvocationForm] = []
      let mut has_array = false
      for value in values {
        match value {
          String(text) => {
            strings.push(text)
            forms.push(@engine.ColonString(text))
          }
          Array(parts_json) => {
            has_array = true
            let parts : Array[String] = []
            for part_json in parts_json {
              match part_json {
                String(part) => parts.push(part)
                _ => return Err("long array-form element is not a string")
              }
            }
            forms.push(@engine.ArrayParts(parts))
          }
          _ => return Err("long[] element is not a string or string[]")
        }
      }
      if has_array {
        Ok(Forms(forms))
      } else {
        Ok(List(strings))
      }
    }
    _ => Err("long is not a bool/array")
  }
}

///|
fn resident_repeat(json : Json) -> Result[@engine.RepeatSpec, String] {
  let object = match resident_object(json) {
    Ok(value) => value
    Err(_) => return Err("repeat is not an object")
  }
  for key, _ in object {
    if key != "min" && key != "max" && key != "lazy" {
      return Err("repeat has unsupported key '" + key + "'")
    }
  }
  let min = match object.get("min") {
    None => 0
    Some(Number(value, ..)) => value.to_int()
    Some(_) => return Err("repeat.min is not a number")
  }
  let max = match object.get("max") {
    None => None
    Some(Number(value, ..)) => Some(value.to_int())
    Some(_) => return Err("repeat.max is not a number")
  }
  let is_lazy = match resident_bool(object, "lazy", false) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  Ok({ min, max, is_lazy })
}

///|
fn resident_multiple(
  json : Json,
) -> Result[
  (Bool, String?, @engine.CollectorDeclaration?, String?, Bool?),
  String,
] {
  match json {
    True => return Ok((true, None, None, None, None))
    False => return Ok((false, None, None, None, None))
    String("append") => return Ok((true, None, None, None, None))
    String(other) => return Err("multiple preset '" + other + "'")
    _ => ()
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(_) => return Err("multiple is not a bool/string/object")
  }
  for key, _ in object {
    if key != "accumulator" &&
      key != "separator" &&
      key != "collector" &&
      key != "flatten" {
      return Err("multiple has unsupported key '" + key + "'")
    }
  }
  let accumulator = match resident_string(object, "accumulator") {
    Some("append") | None => None
    Some(value) => Some(value)
  }
  let collector = match object.get("collector") {
    None => None
    Some(String(name)) => Some(@engine.CollectorDeclaration::named(name))
    Some(Object(call)) => {
      let mut decoded : @engine.CollectorDeclaration? = None
      for name, args in call {
        if decoded is Some(_) {
          return Err(
            "multiple.collector argument form has more than one resident",
          )
        }
        if name != "from_entries" {
          return Err(
            "multiple.collector argument form has unsupported resident '" +
            name +
            "'",
          )
        }
        if from_entries_spec_of(args) is None {
          return Err(
            "multiple.collector.from_entries must be \"entries\", a key string, or [key, value]",
          )
        }
        decoded = Some(@engine.CollectorDeclaration::configured(name, args))
      }
      match decoded {
        Some(value) => Some(value)
        None => return Err("multiple.collector argument form is empty")
      }
    }
    Some(_) => return Err("multiple.collector is not a string/object")
  }
  let flatten = match object.get("flatten") {
    None => None
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => return Err("multiple.flatten is not a bool")
  }
  Ok(
    (
      true,
      resident_string(object, "separator"),
      collector,
      accumulator,
      flatten,
    ),
  )
}

///|
fn resident_empty_help_meta() -> @engine.HelpMetaDeclaration {
  {
    help: None,
    help_long: None,
    help_epilog: None,
    display_name: None,
    value_name: None,
    help_group_name: None,
    help_group_title: None,
    help_group_description: None,
    help_order: None,
    help_group_order: None,
    help_after: None,
    help_on_failure: None,
    is_help_preset: false,
    type_name: None,
    preset_kind: None,
    value_structure_hint: None,
    type_ref: None,
    render_declared: None,
    render_effective: None,
    value_structure_style: None,
    completion_insert_form_declared: None,
  }
}

///|
fn resident_alias(json : Json) -> Result[@engine.AliasDef?, String] {
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  if object.get("alias") is None {
    return Ok(None)
  }
  let target = match resident_string(object, "alias") {
    Some(value) => value
    None => return Err("alias missing target")
  }
  let name = resident_string(object, "name")
  match name {
    Some(value) =>
      if value.contains("#") {
        return Err(
          "alias name/id '" +
          value +
          "' contains '#' (DR-067 §2: '#' はユーザ定義で禁止、内部予約名前空間)",
        )
      }
    None => ()
  }
  let short = match resident_strings(object, "short") {
    Ok(values) => {
      let chars : Array[Char] = []
      for value in values {
        for char in value.to_array() {
          chars.push(char)
        }
      }
      chars
    }
    Err(reason) => return Err(reason)
  }
  let long_override = match object.get("long") {
    Some(value) =>
      match resident_long(value) {
        Ok(declaration) => Some(declaration)
        Err(reason) => return Err(reason)
      }
    None => None
  }
  let deprecated = match resident_bool(object, "deprecated", false) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  Ok(
    Some({
      target,
      name,
      short,
      long_override,
      deprecated,
      help_meta: resident_empty_help_meta(),
    }),
  )
}

///|
priv struct LongInstaller {}

///|
impl @engine.InstallerExt for LongInstaller with fn vocab(_self) {
  ["long"]
}

///|
impl @engine.InstallerExt for LongInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option => ["long"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let declaration = match object.get("long") {
    Some(value) =>
      match resident_long(value) {
        Ok(decoded) => decoded
        Err(reason) => return Err(reason)
      }
    None => List([])
  }
  Ok({ vocab, declaration: Long(declaration) })
}

///|
impl @engine.InstallerExt for LongInstaller with fn apply(_self, builder) {
  inst_long(builder.definition(), builder.output(), builder.templates())
}

///|
impl @engine.InstallerExt for LongInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  collect_invalid_long_dsl(view.source_definition(), errors, view.extensions())
  collect_tty_stream_missing(view.definition(), errors)
  errors
}

///|
pub fn long_installer() -> &@engine.InstallerExt {
  LongInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct ShortInstaller {}

///|
impl @engine.InstallerExt for ShortInstaller with fn vocab(_self) {
  ["short"]
}

///|
impl @engine.InstallerExt for ShortInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option => ["short"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let values = match resident_strings(object, "short") {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let chars : Array[Char] = []
  for value in values {
    for char in value.to_array() {
      chars.push(char)
    }
  }
  Ok({ vocab, declaration: Short(chars) })
}

///|
impl @engine.InstallerExt for ShortInstaller with fn apply(_self, builder) {
  inst_short(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for ShortInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn short_installer() -> &@engine.InstallerExt {
  ShortInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct EnvInstaller {}

///|
impl @engine.InstallerExt for EnvInstaller with fn vocab(_self) {
  ["env"]
}

///|
impl @engine.InstallerExt for EnvInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option | Positional => ["env"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_strings(object, "env") {
    Ok(values) => Ok({ vocab, declaration: Env(values) })
    Err(reason) => Err(reason)
  }
}

///|
impl @engine.InstallerExt for EnvInstaller with fn apply(_self, builder) {
  inst_env(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for EnvInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  collect_none_value_source_decl(view.definition(), errors)
  errors
}

///|
pub fn env_installer() -> &@engine.InstallerExt {
  EnvInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct DdInstaller {}

///|
impl @engine.InstallerExt for DdInstaller with fn vocab(_self) {
  ["dd"]
}

///|
impl @engine.InstallerExt for DdInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option => ["match", "self"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let self_keep = match resident_string(object, "self") {
    Some("drop") | None => false
    Some("keep") => true
    Some(other) => return Err("dd 'self' has unknown value '" + other + "'")
  }
  Ok({ vocab, declaration: Dd(resident_string(object, "match"), self_keep) })
}

///|
impl @engine.InstallerExt for DdInstaller with fn apply(_self, builder) {
  inst_dd(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for DdInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  collect_invalid_dd_pattern(view.definition(), errors)
  errors
}

///|
pub fn dd_installer() -> &@engine.InstallerExt {
  DdInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct CommandInstaller {}

///|
impl @engine.InstallerExt for CommandInstaller with fn vocab(_self) {
  ["command"]
}

///|
impl @engine.InstallerExt for CommandInstaller with fn decode(
  _self,
  _json,
  _ctx,
) {
  Ok({ vocab: [], declaration: Command })
}

///|
impl @engine.InstallerExt for CommandInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for CommandInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn command_installer() -> &@engine.InstallerExt {
  CommandInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct GlobalInstaller {}

///|
impl @engine.InstallerExt for GlobalInstaller with fn vocab(_self) {
  ["global"]
}

///|
impl @engine.InstallerExt for GlobalInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option => ["global"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_bool(object, "global", false) {
    Ok(value) => Ok({ vocab, declaration: Global(value) })
    Err(reason) => Err(reason)
  }
}

///|
impl @engine.InstallerExt for GlobalInstaller with fn apply(_self, builder) {
  inst_global(builder)
}

///|
impl @engine.InstallerExt for GlobalInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn global_installer() -> &@engine.InstallerExt {
  GlobalInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct InheritInstaller {}

///|
impl @engine.InstallerExt for InheritInstaller with fn vocab(_self) {
  ["inherit"]
}

///|
impl @engine.InstallerExt for InheritInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option | Positional => ["inherit"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_bool(object, "inherit", false) {
    Ok(value) => Ok({ vocab, declaration: Inherit(value) })
    Err(reason) => Err(reason)
  }
}

///|
impl @engine.InstallerExt for InheritInstaller with fn apply(_self, builder) {
  inst_inherit(builder.definition(), builder.output())
}

///|
impl @engine.InstallerExt for InheritInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn inherit_installer() -> &@engine.InstallerExt {
  InheritInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct RepeatInstaller {}

///|
impl @engine.InstallerExt for RepeatInstaller with fn vocab(_self) {
  ["repeat"]
}

///|
impl @engine.InstallerExt for RepeatInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option => ["repeat"]
    Positional => ["repeat", "optional"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let repeat = match object.get("repeat") {
    Some(value) =>
      match resident_repeat(value) {
        Ok(decoded) => Some(decoded)
        Err(reason) => return Err(reason)
      }
    None => None
  }
  let optional = match resident_bool(object, "optional", false) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  Ok({ vocab, declaration: Repeat(repeat, optional) })
}

///|
impl @engine.InstallerExt for RepeatInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for RepeatInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  let definition = view.definition()
  let templates = view.templates()
  collect_invalid_range(definition, errors)
  collect_unsupported_option_ref_repeat(definition, errors)
  collect_absent_ref(definition, templates, errors)
  collect_circular_ref(templates, errors)
  collect_zero_progress(definition, templates, errors)
  errors
}

///|
pub fn repeat_installer() -> &@engine.InstallerExt {
  RepeatInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct MultipleInstaller {}

///|
impl @engine.InstallerExt for MultipleInstaller with fn vocab(_self) {
  ["multiple"]
}

///|
impl @engine.InstallerExt for MultipleInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option | Positional => ["multiple"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let decoded = match object.get("multiple") {
    Some(value) =>
      match resident_multiple(value) {
        Ok(result) => result
        Err(reason) => return Err(reason)
      }
    None => (false, None, None, None, None)
  }
  let (multiple, separator, collector, accumulator, flatten) = decoded
  Ok({
    vocab,
    declaration: Multiple(multiple, separator, collector, accumulator, flatten),
  })
}

///|
impl @engine.InstallerExt for MultipleInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for MultipleInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  let definition = view.definition()
  collect_unsupported_accum_update(definition, errors, view.extensions())
  collect_unsupported_count_multiple(definition, errors)
  collect_scalar_array_default(definition, errors)
  collect_unknown_filter(definition, errors, view.extensions())
  collect_invalid_filter_attribute_mismatch(definition, errors)
  collect_invalid_regex_pattern(definition, errors)
  collect_ref_merge_accum(definition, errors)
  collect_flatten_non_append(definition, errors)
  collect_invalid_numeric_filter_args(definition, errors)
  errors
}

///|
pub fn multiple_installer() -> &@engine.InstallerExt {
  MultipleInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct ConfigInstaller {}

///|
impl @engine.InstallerExt for ConfigInstaller with fn vocab(_self) {
  ["config"]
}

///|
impl @engine.InstallerExt for ConfigInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option | Positional => ["config_key"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let config_key = match object.get("config_key") {
    Some(_) =>
      match resident_strings(object, "config_key") {
        Ok(value) => Some(value)
        Err(reason) => return Err(reason)
      }
    None => None
  }
  Ok({
    vocab,
    declaration: Config(
      resident_string(object, "type") == Some("config_file"),
      config_key,
    ),
  })
}

///|
impl @engine.InstallerExt for ConfigInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for ConfigInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  collect_config_cycle(view.definition(), errors)
  errors
}

///|
pub fn config_installer() -> &@engine.InstallerExt {
  ConfigInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct ConstraintInstaller {}

///|
impl @engine.InstallerExt for ConstraintInstaller with fn vocab(_self) {
  ["constraint"]
}

///|
impl @engine.InstallerExt for ConstraintInstaller with fn decode(
  _self,
  json,
  ctx,
) {
  let vocab = match ctx {
    Option =>
      [
        "requires", "conflicts_with", "exclusive_group", "required_group", "required",
      ]
    // DR-012 / DR-055 / DR-103: constraint 系は「要素属性」であり positional にも同型に付与できる
    // (engine 側の Conflicts/Exclusive/Required/RequiredGroup は committed 判定を entity 名で
    // 行うため option/positional を区別しない)。option 版と同じ 5 語彙を positional にも許可する。
    // value_requires は positional では trigger 経路が仕様上ない (positional の `or` は structural
    // 専用、`values` キー未 allowed、DR-055 §5.3 の value-enum-or 誘導は option 限定 — 値の枝への
    // requires は positional では structural or の各枝内の positional 要素自身の requires で表現される)。
    Positional =>
      [
        "requires", "conflicts_with", "exclusive_group", "required_group", "required",
      ]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let requires = match resident_strings(object, "requires") {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let conflicts = match resident_strings(object, "conflicts_with") {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let exclusive = match resident_strings(object, "exclusive_group") {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let required_group = match resident_strings(object, "required_group") {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let required = match resident_bool(object, "required", false) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  Ok({
    vocab,
    declaration: Constraint(
      requires, conflicts, exclusive, required_group, required,
    ),
  })
}

///|
impl @engine.InstallerExt for ConstraintInstaller with fn apply(_self, builder) {
  inst_constraint(builder.definition(), builder.output(), builder.templates())
}

///|
impl @engine.InstallerExt for ConstraintInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn constraint_installer() -> &@engine.InstallerExt {
  ConstraintInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct AliasInstaller {}

///|
impl @engine.InstallerExt for AliasInstaller with fn vocab(_self) {
  ["alias"]
}

///|
impl @engine.InstallerExt for AliasInstaller with fn decode(_self, json, ctx) {
  let vocab = match ctx {
    Option | Command => ["alias"]
    _ => []
  }
  match resident_alias(json) {
    Ok(value) => Ok({ vocab, declaration: Alias(value) })
    Err(reason) => Err(reason)
  }
}

///|
impl @engine.InstallerExt for AliasInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @engine.InstallerExt for AliasInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  collect_invalid_alias_long_override(
    view.source_definition(),
    errors,
    view.extensions(),
  )
  errors
}

///|
pub fn alias_installer() -> &@engine.InstallerExt {
  AliasInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct InheritableInstaller {}

///|
impl @engine.InstallerExt for InheritableInstaller with fn vocab(_self) {
  ["inheritable"]
}

///|
impl @engine.InstallerExt for InheritableInstaller with fn decode(
  _self,
  json,
  ctx,
) {
  let vocab = match ctx {
    Option => ["inheritable"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_bool(object, "inheritable", false) {
    Ok(value) => Ok({ vocab, declaration: Inheritable(value) })
    Err(reason) => Err(reason)
  }
}

///|
impl @engine.InstallerExt for InheritableInstaller with fn apply(_self, builder) {
  inst_inheritable(builder)
}

///|
impl @engine.InstallerExt for InheritableInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn inheritable_installer() -> &@engine.InstallerExt {
  InheritableInstaller::{  } as &@engine.InstallerExt
}

///|
priv struct HelpMetaInstaller {}

///|
impl @engine.InstallerExt for HelpMetaInstaller with fn vocab(_self) {
  [
    "help", "help_long", "help_epilog", "display_name", "value_name", "help_group_name",
    "help_group_title", "help_group_description", "help_order", "help_group_order",
    "help_after", "help_on_failure",
    // DR-115 §1.1 / §1.2: 一括席 `help_render` (scope 単位、element 席は §1.1 で席違い =
    // invalid-range) と entry 個別席 `help_value_structure_style` (element 単位) を回収する。
    // 席違いの判定は collect_defs_errors 側で「render_declared が element 上に載っているか」
    // を見る (vocab に入れないと allowed_keys が unknown-vocab で先に弾き、意図した invalid-range
    // まで到達しないため、両席とも語彙として一旦受理する)。
     "help_render", "help_value_structure_style",
  ]
}

///|
impl @engine.InstallerExt for HelpMetaInstaller with fn decode(
  _self,
  json,
  _ctx,
) {
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let help_order = match resident_number(object, "help_order") {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  let help_group_order = match resident_number(object, "help_group_order") {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  // DR-113 §7.2: `help_on_failure` は help_installer 所有の糖衣。5 preset 判定は decode 層
  // (`dec_option` の tystr match) が上書きするため、ここでは wire 上の宣言値だけを写し取り
  // is_help_preset は false のまま渡す (dec_option 側で `is_help_preset: true` へ差し替える)。
  let help_on_failure : Bool? = match object.get("help_on_failure") {
    None => None
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(_) => return Err("help_on_failure is not a bool")
  }
  // DR-115 §1.1 / §1.4: element 側 (dec_option / dec_positional) の HelpMetaInstaller.decode 経路。
  // scope 側 (help_meta_from_object) と同じ 4 キー carrier を組む — decode-time は enum / template
  // 検査を行わず、席違い含めて collect_defs_errors の invalid-range に一本化する (M3a の
  // help_on_failure と同じ posture)。
  let render_declared : @engine.HelpRenderDecl? = match
    object.get("help_render") {
    None => None
    Some(rj) =>
      match rj {
        Object(ro) =>
          Some({
            template: resident_string(ro, "template"),
            value_structure_style: resident_string(ro, "value_structure_style"),
            types_style: resident_string(ro, "types_style"),
            origin_style: resident_string(ro, "origin_style"),
          })
        _ => return Err("help_render is not an object")
      }
  }
  let value_structure_style = resident_string(
    object, "help_value_structure_style",
  )
  Ok({
    vocab: [
      "help", "help_long", "help_epilog", "display_name", "value_name", "help_group_name",
      "help_group_title", "help_group_description", "help_order", "help_group_order",
      "help_after", "help_on_failure", "help_render", "help_value_structure_style",
    ],
    declaration: HelpMeta({
      help: resident_string(object, "help"),
      help_long: resident_string(object, "help_long"),
      help_epilog: resident_string(object, "help_epilog"),
      display_name: resident_string(object, "display_name"),
      value_name: resident_string(object, "value_name"),
      help_group_name: resident_string(object, "help_group_name"),
      help_group_title: resident_string(object, "help_group_title"),
      help_group_description: resident_string(object, "help_group_description"),
      help_order,
      help_group_order,
      help_after: resident_string(object, "help_after"),
      help_on_failure,
      is_help_preset: false,
      type_name: None,
      preset_kind: None,
      value_structure_hint: None,
      type_ref: None,
      render_declared,
      render_effective: None,
      value_structure_style,
      completion_insert_form_declared: None,
    }),
  })
}

///|
impl @engine.InstallerExt for HelpMetaInstaller with fn apply(_self, _builder) {
  ()
}

///|
fn help_group_declaration(e : @engine.ElementDef) -> Bool {
  e.name == "" && e.help_meta.help_group_name is Some(_)
}

///|
fn help_find_after(def : @engine.Definition, name : String) -> String? {
  for e in def.options {
    if e.name == name {
      return e.help_meta.help_after
    }
  }
  for c in def.commands {
    if c.name == name {
      return None
    }
  }
  None
}

///|
fn help_name_seen(names : Array[String], name : String) -> Bool {
  for item in names {
    if item == name {
      return true
    }
  }
  false
}

///|
fn help_after_returns_to(def : @engine.Definition, start : String) -> Bool {
  let seen : Array[String] = []
  let mut current = start
  while true {
    if help_name_seen(seen, current) {
      return current == start
    }
    seen.push(current)
    match help_find_after(def, current) {
      Some(next) => current = next
      None => return false
    }
  } nobreak {
    false
  }
}

///|
/// DR-115 §5.1: `value_structure_style` の enum 値域。
fn help_render_vss_ok(value : String) -> Bool {
  value == "auto" || value == "inline" || value == "detail"
}

///|
/// DR-115 §5.2: `types_style` の enum 値域。
fn help_render_types_style_ok(value : String) -> Bool {
  value == "auto" || value == "aggregate" || value == "inline"
}

///|
/// DR-115 §5.3: `origin_style` の enum 値域。
fn help_render_origin_style_ok(value : String) -> Bool {
  value == "merge" ||
  value == "separate_section" ||
  value == "reference" ||
  value == "omit"
}

///|
/// DR-115 §2.4: template 文字列の well-formedness 検査。
/// - 未閉の `{` (対応する `}` が無い)
/// - 空 `{}`
/// - 識別子規則違反: `[A-Za-z_][A-Za-z0-9_]*`
/// - `{{` は literal `{` のエスケープ、`}}` は literal `}` のエスケープ (通過)
/// 違反があれば true を返す (呼び出し側が invalid-range を emit)。
fn help_render_template_invalid(template : String) -> Bool {
  let chars = template.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    if c == '{' {
      // `{{` は literal `{` エスケープ
      if i + 1 < n && chars[i + 1] == '{' {
        i = i + 2
        continue
      }
      // `{...}` プレースホルダ: 対応する `}` を探し、中身の識別子規則を検査
      let start = i + 1
      let mut end = -1
      let mut j = start
      while j < n {
        if chars[j] == '}' {
          end = j
          break
        }
        j = j + 1
      }
      if end < 0 {
        return true // 未閉の `{`
      }
      if end == start {
        return true // 空 `{}`
      }
      // 識別子規則: 先頭は letter or '_'、以降は letter/digit/'_'
      let head = chars[start]
      if !ident_head_char(head) {
        return true
      }
      let mut k = start + 1
      while k < end {
        if !ident_tail_char(chars[k]) {
          return true
        }
        k = k + 1
      }
      i = end + 1
      continue
    }
    if c == '}' {
      // `}}` は literal `}` エスケープ (通過)。単独 `}` は他実装では error 扱いのケースもあるが、
      // DR-115 §2.4 は「未閉 `{` / 空 `{}` / 識別子規則違反」の 3 項目のみ列挙するため、単独 `}`
      // は本 DR の範囲外 (spec が emit を要求しない — 呼び出し側 fixture も対象にしていない)。
      if i + 1 < n && chars[i + 1] == '}' {
        i = i + 2
        continue
      }
      i = i + 1
      continue
    }
    i = i + 1
  }
  false
}

///|
fn ident_head_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn ident_tail_char(c : Char) -> Bool {
  ident_head_char(c) || (c >= '0' && c <= '9')
}

///|
/// DR-115 §1.1 / §2.4 / §5: scope 席 (root / command) の `help_render` を検査する。
/// enum 値域外・template 構文不正のいずれも invalid-range として積む — element は
/// element.name、scope 直付けは "" を使う (help group declaration 検査と同じ posture)。
fn collect_help_render_scope_errors(
  render : @engine.HelpRenderDecl,
  element_name : String,
  errors : Array[@engine.DefError],
) -> Unit {
  match render.value_structure_style {
    Some(v) =>
      if !help_render_vss_ok(v) {
        errors.push({
          element: element_name,
          kind: @engine.InvalidRange,
          message: "help_render.value_structure_style '" +
          v +
          "' is not one of auto/inline/detail",
          hint: "use one of the DR-115 §5.1 enum values",
        })
      }
    None => ()
  }
  match render.types_style {
    Some(v) =>
      if !help_render_types_style_ok(v) {
        errors.push({
          element: element_name,
          kind: @engine.InvalidRange,
          message: "help_render.types_style '" +
          v +
          "' is not one of auto/aggregate/inline",
          hint: "use one of the DR-115 §5.2 enum values",
        })
      }
    None => ()
  }
  match render.origin_style {
    Some(v) =>
      if !help_render_origin_style_ok(v) {
        errors.push({
          element: element_name,
          kind: @engine.InvalidRange,
          message: "help_render.origin_style '" +
          v +
          "' is not one of merge/separate_section/reference/omit",
          hint: "use one of the DR-115 §5.3 enum values",
        })
      }
    None => ()
  }
  match render.template {
    Some(t) =>
      if help_render_template_invalid(t) {
        errors.push({
          element: element_name,
          kind: @engine.InvalidRange,
          message: "help_render.template is not well-formed (unclosed '{' / empty '{}' / non-identifier body)",
          hint: "DR-115 §2.4: templates are strict — literal braces need '{{' / '}}' escape",
        })
      }
    None => ()
  }
}

///|
/// DR-115 §1.1 / §1.2: element 席の help_render / help_value_structure_style を検査する。
/// - `help_render` の宣言そのものが席違い (§1.1、option/positional 上は不可) → invalid-range
/// - `help_value_structure_style` の enum 値域外 (§1.2) → invalid-range
/// 席違いは値によらず 1 element 1 error に集約する (§1.4 の集合比較、fixture
/// help-render-invalid-range 期待どおり)。
fn collect_help_render_element_errors(
  element : @engine.ElementDef,
  errors : Array[@engine.DefError],
) -> Unit {
  match element.help_meta.render_declared {
    Some(_) =>
      errors.push({
        element: element.name,
        kind: @engine.InvalidRange,
        message: "help_render is not allowed on option/positional elements (scope-level seat only)",
        hint: "DR-115 §1.1: declare help_render on the root definition or a command scope; use help_value_structure_style for entry-level style overrides",
      })
    None => ()
  }
  match element.help_meta.value_structure_style {
    Some(v) =>
      if !help_render_vss_ok(v) {
        errors.push({
          element: element.name,
          kind: @engine.InvalidRange,
          message: "help_value_structure_style '" +
          v +
          "' is not one of auto/inline/detail",
          hint: "DR-115 §5.1 enum",
        })
      }
    None => ()
  }
}

///|
fn collect_help_meta_errors(
  def : @engine.Definition,
  errors : Array[@engine.DefError],
) -> Unit {
  // DR-115 §1.1 / §2.4 / §5: scope 直付け help_render の宣言 (継承値ではない) を検査。
  match def.scope.help_meta.render_declared {
    Some(render) => collect_help_render_scope_errors(render, "", errors)
    None => ()
  }
  let groups : Map[String, (String?, String?)] = Map([])
  for e in def.options {
    let meta = e.help_meta
    // DR-113 §7.2: `help_on_failure` は 5 help preset (help / help_all_category /
    // help_category / help_show_hidden / help_tree) が on_failure へ展開する糖衣であり、
    // 非 help preset (flag / string / help group declaration / positional 等) 上に宣言
    // した場合は definition-error `invalid-range`。help preset 上での糖衣展開
    // (fail_action override) は M3c 以降で HelpMetaInstaller.apply へ移送する。
    if meta.help_on_failure is Some(_) && !meta.is_help_preset {
      errors.push({
        element: e.name,
        kind: @engine.InvalidRange,
        message: "help_on_failure requires a help preset type",
        hint: "declare help_on_failure only on help / help_all_category / help_category / help_show_hidden / help_tree",
      })
    }
    if help_group_declaration(e) {
      if meta.help_order is Some(_) {
        errors.push({
          element: "",
          kind: @engine.InvalidRange,
          message: "help group declaration cannot use help_order",
          hint: "use help_group_order for a group declaration",
        })
      }
      match meta.help_group_name {
        Some(name) => {
          let setting = (meta.help_group_title, meta.help_group_description)
          // DR-113 §8.1: 同じ help_group_name の重複宣言は設定同一か否かを問わず
          // 無条件で definition-error `invalid-range` (グループ宣言箇所を一意にする
          // 先頭宣言スタイルを崩さない)。冪等受理しない存在ベース規則。
          match groups.get(name) {
            Some(_) =>
              errors.push({
                element: "",
                kind: @engine.InvalidRange,
                message: "help group '" + name + "' is declared more than once",
                hint: "keep exactly one declaration per help_group_name",
              })
            None => groups.set(name, setting)
          }
        }
        None => ()
      }
    } else if meta.help_group_order is Some(_) {
      errors.push({
        element: e.name,
        kind: @engine.InvalidRange,
        message: "normal help entry cannot use help_group_order",
        hint: "use help_order for a normal entry",
      })
    }
    if meta.help_after is Some(_) &&
      (meta.help_order is Some(_) || meta.help_group_order is Some(_)) {
      errors.push({
        element: e.name,
        kind: @engine.InvalidRange,
        message: "help order and help_after cannot be declared together",
        hint: "choose either absolute order or relative help_after placement",
      })
    }
  }
  for e in def.options {
    if e.name != "" &&
      e.help_meta.help_after is Some(_) &&
      help_after_returns_to(def, e.name) {
      errors.push({
        element: e.name,
        kind: @engine.CircularRef,
        message: "help_after placement for '" + e.name + "' is circular",
        hint: "break the help_after cycle",
      })
    }
  }
  // DR-115 §1.1 / §1.2: element 席の help_render / help_value_structure_style を検査。
  // options / positionals の両方 (help group declaration entry は name=="" だが render_declared
  // /value_structure_style を持ちうるので同じ検査を通す — 席違いは値によらず emit)。
  for e in def.options {
    collect_help_render_element_errors(e, errors)
  }
  for e in def.positionals {
    collect_help_render_element_errors(e, errors)
  }
  for c in def.commands {
    collect_help_meta_errors(c.body, errors)
  }
}

///|
impl @engine.InstallerExt for HelpMetaInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  let errors = []
  collect_help_meta_errors(view.source_definition(), errors)
  errors
}

///|
pub fn help_meta_installer() -> &@engine.InstallerExt {
  HelpMetaInstaller::{  } as &@engine.InstallerExt
}
