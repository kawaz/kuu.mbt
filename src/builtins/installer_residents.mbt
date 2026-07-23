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
        if @extension.from_entries_spec_of(args) is None {
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
impl @node.InstallerExt for LongInstaller with fn vocab(_self) {
  ["long"]
}

///|
impl @node.InstallerExt for LongInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for LongInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "long")
}

///|
impl @node.InstallerExt for LongInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  @node.defs_builtin_errors(view, "long")
}

///|
pub fn long_installer() -> &@node.InstallerExt {
  LongInstaller::{  } as &@node.InstallerExt
}

///|
priv struct ShortInstaller {}

///|
impl @node.InstallerExt for ShortInstaller with fn vocab(_self) {
  ["short"]
}

///|
impl @node.InstallerExt for ShortInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for ShortInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "short")
}

///|
impl @node.InstallerExt for ShortInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn short_installer() -> &@node.InstallerExt {
  ShortInstaller::{  } as &@node.InstallerExt
}

///|
priv struct EnvInstaller {}

///|
impl @node.InstallerExt for EnvInstaller with fn vocab(_self) {
  ["env"]
}

///|
impl @node.InstallerExt for EnvInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for EnvInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "env")
}

///|
impl @node.InstallerExt for EnvInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  @node.defs_builtin_errors(view, "env")
}

///|
pub fn env_installer() -> &@node.InstallerExt {
  EnvInstaller::{  } as &@node.InstallerExt
}

///|
priv struct DdInstaller {}

///|
impl @node.InstallerExt for DdInstaller with fn vocab(_self) {
  ["dd"]
}

///|
impl @node.InstallerExt for DdInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for DdInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "dd")
}

///|
impl @node.InstallerExt for DdInstaller with fn collect_defs_errors(_self, view) {
  @node.defs_builtin_errors(view, "dd")
}

///|
pub fn dd_installer() -> &@node.InstallerExt {
  DdInstaller::{  } as &@node.InstallerExt
}

///|
priv struct CommandInstaller {}

///|
impl @node.InstallerExt for CommandInstaller with fn vocab(_self) {
  ["command"]
}

///|
impl @node.InstallerExt for CommandInstaller with fn decode(_self, _json, _ctx) {
  Ok({ vocab: [], declaration: Command })
}

///|
impl @node.InstallerExt for CommandInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @node.InstallerExt for CommandInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn command_installer() -> &@node.InstallerExt {
  CommandInstaller::{  } as &@node.InstallerExt
}

///|
priv struct GlobalInstaller {}

///|
impl @node.InstallerExt for GlobalInstaller with fn vocab(_self) {
  ["global"]
}

///|
impl @node.InstallerExt for GlobalInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for GlobalInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "global")
}

///|
impl @node.InstallerExt for GlobalInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn global_installer() -> &@node.InstallerExt {
  GlobalInstaller::{  } as &@node.InstallerExt
}

///|
priv struct InheritInstaller {}

///|
impl @node.InstallerExt for InheritInstaller with fn vocab(_self) {
  ["inherit"]
}

///|
impl @node.InstallerExt for InheritInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for InheritInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "inherit")
}

///|
impl @node.InstallerExt for InheritInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn inherit_installer() -> &@node.InstallerExt {
  InheritInstaller::{  } as &@node.InstallerExt
}

///|
priv struct RepeatInstaller {}

///|
impl @node.InstallerExt for RepeatInstaller with fn vocab(_self) {
  ["repeat"]
}

///|
impl @node.InstallerExt for RepeatInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for RepeatInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @node.InstallerExt for RepeatInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  @node.defs_builtin_errors(view, "repeat")
}

///|
pub fn repeat_installer() -> &@node.InstallerExt {
  RepeatInstaller::{  } as &@node.InstallerExt
}

///|
priv struct MultipleInstaller {}

///|
impl @node.InstallerExt for MultipleInstaller with fn vocab(_self) {
  ["multiple"]
}

///|
impl @node.InstallerExt for MultipleInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for MultipleInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @node.InstallerExt for MultipleInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  @node.defs_builtin_errors(view, "multiple")
}

///|
pub fn multiple_installer() -> &@node.InstallerExt {
  MultipleInstaller::{  } as &@node.InstallerExt
}

///|
priv struct ConfigInstaller {}

///|
impl @node.InstallerExt for ConfigInstaller with fn vocab(_self) {
  ["config"]
}

///|
impl @node.InstallerExt for ConfigInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for ConfigInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @node.InstallerExt for ConfigInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  @node.defs_builtin_errors(view, "config")
}

///|
pub fn config_installer() -> &@node.InstallerExt {
  ConfigInstaller::{  } as &@node.InstallerExt
}

///|
priv struct ConstraintInstaller {}

///|
impl @node.InstallerExt for ConstraintInstaller with fn vocab(_self) {
  ["constraint"]
}

///|
impl @node.InstallerExt for ConstraintInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for ConstraintInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "constraint")
}

///|
impl @node.InstallerExt for ConstraintInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn constraint_installer() -> &@node.InstallerExt {
  ConstraintInstaller::{  } as &@node.InstallerExt
}

///|
priv struct AliasInstaller {}

///|
impl @node.InstallerExt for AliasInstaller with fn vocab(_self) {
  ["alias"]
}

///|
impl @node.InstallerExt for AliasInstaller with fn decode(_self, json, ctx) {
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
impl @node.InstallerExt for AliasInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @node.InstallerExt for AliasInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  @node.defs_builtin_errors(view, "alias")
}

///|
pub fn alias_installer() -> &@node.InstallerExt {
  AliasInstaller::{  } as &@node.InstallerExt
}

///|
priv struct InheritableInstaller {}

///|
impl @node.InstallerExt for InheritableInstaller with fn vocab(_self) {
  ["inheritable"]
}

///|
impl @node.InstallerExt for InheritableInstaller with fn decode(
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
impl @node.InstallerExt for InheritableInstaller with fn apply(_self, builder) {
  @node.builder_apply_builtin(builder, "inheritable")
}

///|
impl @node.InstallerExt for InheritableInstaller with fn collect_defs_errors(
  _self,
  _view,
) {
  []
}

///|
pub fn inheritable_installer() -> &@node.InstallerExt {
  InheritableInstaller::{  } as &@node.InstallerExt
}

///|
priv struct HelpMetaInstaller {}

///|
impl @node.InstallerExt for HelpMetaInstaller with fn vocab(_self) {
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
impl @node.InstallerExt for HelpMetaInstaller with fn decode(_self, json, _ctx) {
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
impl @node.InstallerExt for HelpMetaInstaller with fn apply(_self, _builder) {
  ()
}

///|
impl @node.InstallerExt for HelpMetaInstaller with fn collect_defs_errors(
  _self,
  view,
) {
  @node.defs_builtin_errors(view, "help_meta")
}

///|
pub fn help_meta_installer() -> &@node.InstallerExt {
  HelpMetaInstaller::{  } as &@node.InstallerExt
}
