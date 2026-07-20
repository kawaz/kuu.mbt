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
fn resident_long(json : Json) -> Result[@engine.LongDecl, String] {
  match json {
    True => Ok(LBool(true))
    False => Ok(LBool(false))
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
        Ok(LForms(forms))
      } else {
        Ok(LList(strings))
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
fn resident_empty_help_meta() -> @engine.HelpMetaDecl {
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
    // DR-012 / DR-055 / DR-103: constraint 系は「要素属性」であり positional にも同型に付与できる
    // (engine 側の CConflicts/CExclusive/CRequired/CRequiredGroup は committed 判定を entity 名で
    // 行うため option/positional を区別しない)。option 版と同じ 5 語彙を positional にも許可する。
    // value_requires は positional では trigger 経路が仕様上ない (positional の `or` は structural
    // 専用、`values` キー未 allowed、DR-055 §5.3 の value-enum-or 誘導は option 限定 — 値の枝への
    // requires は positional では structural or の各枝内の positional 要素自身の requires で表現される)。
    DecodePositional =>
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
priv struct HelpMetaInstaller {}

///|
impl @engine.InstallerExt for HelpMetaInstaller with fn vocab(_self) {
  [
    "help", "help_long", "help_epilog", "display_name", "value_name", "help_group_name",
    "help_group_title", "help_group_description", "help_order", "help_group_order",
    "help_after", "help_on_failure",
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
  Ok({
    vocab: [
      "help", "help_long", "help_epilog", "display_name", "value_name", "help_group_name",
      "help_group_title", "help_group_description", "help_order", "help_group_order",
      "help_after", "help_on_failure",
    ],
    declaration: ODHelpMeta({
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
    }),
  })
}

///|
impl @engine.InstallerExt for HelpMetaInstaller with fn apply(_self, _builder) {
  ()
}

///|
fn help_group_declaration(e : @engine.ElemDef) -> Bool {
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
fn collect_help_meta_errors(
  def : @engine.Definition,
  errors : Array[@engine.DefError],
) -> Unit {
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
        kind: @engine.DInvalidRange,
        message: "help_on_failure requires a help preset type",
        hint: "declare help_on_failure only on help / help_all_category / help_category / help_show_hidden / help_tree",
      })
    }
    if help_group_declaration(e) {
      if meta.help_order is Some(_) {
        errors.push({
          element: "",
          kind: @engine.DInvalidRange,
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
                kind: @engine.DInvalidRange,
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
        kind: @engine.DInvalidRange,
        message: "normal help entry cannot use help_group_order",
        hint: "use help_order for a normal entry",
      })
    }
    if meta.help_after is Some(_) &&
      (meta.help_order is Some(_) || meta.help_group_order is Some(_)) {
      errors.push({
        element: e.name,
        kind: @engine.DInvalidRange,
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
        kind: @engine.DCircularRef,
        message: "help_after placement for '" + e.name + "' is circular",
        hint: "break the help_after cycle",
      })
    }
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
