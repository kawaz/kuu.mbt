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
fn resident_long(json : Json) -> Result[@engine.LongDecl, String] {
  match json {
    True => Ok(LBool(true))
    False => Ok(LBool(false))
    Array(values) => {
      let output : Array[String] = []
      for value in values {
        match value {
          String(text) => output.push(text)
          _ => return Err("long[] element is not a string")
        }
      }
      Ok(LList(output))
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
  let lazy_ = match resident_bool(object, "lazy", false) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  Ok({ min, max, lazy_ })
}

///|
fn resident_multiple(
  json : Json,
) -> Result[(Bool, String?, String?, String?, Bool?), String] {
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
  let collector = match resident_string(object, "collector") {
    None => None
    Some("unwrap_single") => Some("unwrap_single")
    Some(value) =>
      return Err("multiple.collector '" + value + "' has no wired runtime yet")
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
fn resident_alias(json : Json) -> Result[@engine.AliasDef?, String] {
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  if object.get("alias") is None {
    return Ok(None)
  }
  for key, _ in object {
    if key != "alias" &&
      key != "name" &&
      key != "short" &&
      key != "long" &&
      key != "deprecated" &&
      key != "type" {
      return Err("alias has unsupported key '" + key + "'")
    }
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
        for char in @engine.to_chars(value) {
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
  Ok(Some({ target, name, short, long_override, deprecated }))
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
    DecodeOption => ["long"]
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
    None => LList([])
  }
  Ok({ vocab, declaration: ODLong(declaration) })
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
  collect_invalid_long_dsl(view.source_definition(), errors)
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
    DecodeOption => ["short"]
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
    for char in @engine.to_chars(value) {
      chars.push(char)
    }
  }
  Ok({ vocab, declaration: ODShort(chars) })
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
    DecodeOption | DecodePositional => ["env"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_strings(object, "env") {
    Ok(values) => Ok({ vocab, declaration: ODEnv(values) })
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
    DecodeOption => ["match", "self"]
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
  Ok({ vocab, declaration: ODDd(resident_string(object, "match"), self_keep) })
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
  Ok({ vocab: [], declaration: ODCommand })
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
    DecodeOption => ["global"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_bool(object, "global", false) {
    Ok(value) => Ok({ vocab, declaration: ODGlobal(value) })
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
    DecodeOption | DecodePositional => ["inherit"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_bool(object, "inherit", false) {
    Ok(value) => Ok({ vocab, declaration: ODInherit(value) })
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
    DecodeOption => ["repeat"]
    DecodePositional => ["repeat", "optional"]
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
  Ok({ vocab, declaration: ODRepeat(repeat, optional) })
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
    DecodeOption | DecodePositional => ["multiple"]
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
    declaration: ODMultiple(
      multiple, separator, collector, accumulator, flatten,
    ),
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
  collect_unsupported_accum_update(definition, errors)
  collect_unsupported_count_multiple(definition, errors)
  collect_scalar_array_default(definition, errors)
  collect_unknown_filter(definition, errors)
  collect_invalid_filter_attribute_mismatch(definition, errors)
  collect_invalid_regex_pattern(definition, errors)
  collect_ref_merge_accum(definition, errors)
  collect_flatten_non_append(definition, errors)
  collect_unknown_accumulator(definition, errors)
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
    DecodeOption | DecodePositional => ["config_key"]
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
    declaration: ODConfig(
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
    DecodeOption =>
      [
        "requires", "conflicts_with", "exclusive_group", "required_group", "required",
      ]
    DecodePositional => ["requires", "required"]
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
    declaration: ODConstraint(
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
    DecodeOption | DecodeCommand => ["alias"]
    _ => []
  }
  match resident_alias(json) {
    Ok(value) => Ok({ vocab, declaration: ODAlias(value) })
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
  collect_invalid_alias_long_override(view.source_definition(), errors)
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
    DecodeOption => ["inheritable"]
    _ => []
  }
  let object = match resident_object(json) {
    Ok(value) => value
    Err(reason) => return Err(reason)
  }
  match resident_bool(object, "inheritable", false) {
    Ok(value) => Ok({ vocab, declaration: ODInheritable(value) })
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
pub fn install_installers(registry : @engine.Registry) -> Unit {
  registry.register_installer(long_installer())
  registry.register_installer(short_installer())
  registry.register_installer(env_installer())
  registry.register_installer(dd_installer())
  registry.register_installer(command_installer())
  registry.register_installer(global_installer())
  registry.register_installer(inherit_installer())
  registry.register_installer(repeat_installer())
  registry.register_installer(multiple_installer())
  registry.register_installer(config_installer())
  registry.register_installer(constraint_installer())
  registry.register_installer(alias_installer())
  registry.register_installer(inheritable_installer())
}
