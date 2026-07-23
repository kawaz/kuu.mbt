// type_residents.mbt — builtin type-category residents behind the open TypeExt contract.

///|
priv struct StringTypeExt {}

///|
impl TypeExt for StringTypeExt with fn name(_self) {
  "string"
}

///|
impl TypeExt for StringTypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl TypeExt for StringTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for StringTypeExt with fn parse_token(_self, token) {
  Ok(@abi.String(token))
}

///|
impl TypeExt for StringTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn string_type() -> &TypeExt {
  StringTypeExt::{  } as &TypeExt
}

///|
priv struct NumberTypeExt {
  allow_base_prefix : Bool
}

///|
impl TypeExt for NumberTypeExt with fn name(_self) {
  "number"
}

///|
impl TypeExt for NumberTypeExt with fn encode(self) {
  self.allow_base_prefix.to_json()
}

///|
impl TypeExt for NumberTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for NumberTypeExt with fn parse_token(self, token) {
  match parse_number(token, allow_base_prefix=self.allow_base_prefix) {
    Some(value) => Ok(@abi.Number(value))
    None => Err(type_parse_not_a_number(token))
  }
}

///|
impl TypeExt for NumberTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn number_type(allow_base_prefix? : Bool = false) -> &TypeExt {
  NumberTypeExt::{ allow_base_prefix, } as &TypeExt
}

///|
priv struct IntTypeExt {
  round : @abi.RoundMode
  allow_base_prefix : Bool
}

///|
impl TypeExt for IntTypeExt with fn name(_self) {
  "int"
}

///|
impl TypeExt for IntTypeExt with fn encode(self) {
  [round_mode_json(self.round), self.allow_base_prefix.to_json()].to_json()
}

///|
impl TypeExt for IntTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for IntTypeExt with fn parse_token(self, token) {
  match
    parse_int_value(token, self.round, allow_base_prefix=self.allow_base_prefix) {
    Ok(value) => Ok(@abi.Number(value.to_double()))
    Err(fail) => Err(fail)
  }
}

///|
impl TypeExt for IntTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn int_type(
  round? : @abi.RoundMode = @abi.Error,
  allow_base_prefix? : Bool = false,
) -> &TypeExt {
  IntTypeExt::{ round, allow_base_prefix } as &TypeExt
}

///|
priv struct FloatTypeExt {}

///|
impl TypeExt for FloatTypeExt with fn name(_self) {
  "float"
}

///|
impl TypeExt for FloatTypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl TypeExt for FloatTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for FloatTypeExt with fn parse_token(_self, token) {
  match parse_float(token) {
    Some(value) => Ok(@abi.Number(value))
    None => Err(type_parse_not_a_number(token))
  }
}

///|
impl TypeExt for FloatTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn float_type() -> &TypeExt {
  FloatTypeExt::{  } as &TypeExt
}

///|
priv struct BoolTypeExt {
  config : @abi.BoolConfig
  value_slot : Bool
}

///|
impl TypeExt for BoolTypeExt with fn name(_self) {
  "bool"
}

///|
impl TypeExt for BoolTypeExt with fn encode(self) {
  [bool_config_json(self.config), self.value_slot.to_json()].to_json()
}

///|
impl TypeExt for BoolTypeExt with fn has_value_slot(self) {
  self.value_slot
}

///|
impl TypeExt for BoolTypeExt with fn parse_token(self, token) {
  match parse_bool(token, config=self.config) {
    Some(value) => Ok(@abi.Bool(value))
    None => Err(type_parse_not_a_bool(token))
  }
}

///|
impl TypeExt for BoolTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn bool_type(
  config? : @abi.BoolConfig = bool_config_canonical(),
  value_slot? : Bool = true,
) -> &TypeExt {
  BoolTypeExt::{ config, value_slot } as &TypeExt
}

///|
priv struct FlagTypeExt {
  config : @abi.BoolConfig
}

///|
impl TypeExt for FlagTypeExt with fn name(_self) {
  "flag"
}

///|
impl TypeExt for FlagTypeExt with fn encode(self) {
  bool_config_json(self.config)
}

///|
impl TypeExt for FlagTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl TypeExt for FlagTypeExt with fn parse_token(self, token) {
  match parse_bool(token, config=self.config) {
    Some(value) => Ok(@abi.Bool(value))
    None => Err(type_parse_not_a_bool(token))
  }
}

///|
impl TypeExt for FlagTypeExt with fn default_seat_resolver(_self, ctx) {
  match ctx.declared() {
    Some(value) => Some(value)
    None => Some(@abi.Bool(false))
  }
}

///|
pub fn flag_type(
  config? : @abi.BoolConfig = bool_config_canonical(),
) -> &TypeExt {
  FlagTypeExt::{ config, } as &TypeExt
}

///|
priv struct CountTypeExt {
  allow_base_prefix : Bool
}

///|
impl TypeExt for CountTypeExt with fn name(_self) {
  "count"
}

///|
impl TypeExt for CountTypeExt with fn encode(self) {
  self.allow_base_prefix.to_json()
}

///|
impl TypeExt for CountTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl TypeExt for CountTypeExt with fn parse_token(self, token) {
  match parse_number(token, allow_base_prefix=self.allow_base_prefix) {
    Some(value) => Ok(@abi.Number(value))
    None => Err(type_parse_not_a_number(token))
  }
}

///|
impl TypeExt for CountTypeExt with fn default_seat_resolver(_self, ctx) {
  match ctx.declared() {
    Some(value) => Some(value)
    None => Some(@abi.Number(0.0))
  }
}

///|
pub fn count_type(allow_base_prefix? : Bool = false) -> &TypeExt {
  CountTypeExt::{ allow_base_prefix, } as &TypeExt
}

///|
priv struct TtyTypeExt {
  stream : String?
  cygwin : Bool
}

///|
impl TypeExt for TtyTypeExt with fn name(_self) {
  "bool"
}

///|
impl TypeExt for TtyTypeExt with fn encode(self) {
  ["tty".to_json(), self.stream.to_json(), self.cygwin.to_json()].to_json()
}

///|
impl TypeExt for TtyTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for TtyTypeExt with fn parse_token(_self, token) {
  match parse_bool(token, config=bool_config_canonical()) {
    Some(value) => Ok(@abi.Bool(value))
    None => Err(type_parse_not_a_bool(token))
  }
}

///|
impl TypeExt for TtyTypeExt with fn default_seat_observation_key(self) {
  self.stream
}

///|
impl TypeExt for TtyTypeExt with fn default_seat_resolver(self, ctx) {
  match ctx.observed() {
    Some(json) =>
      if json is Array(values) && values.length() == 2 {
        let terminal = if values[0] is True {
          Some(true)
        } else if values[0] is False {
          Some(false)
        } else {
          None
        }
        let cygwin = if values[1] is True {
          Some(true)
        } else if values[1] is False {
          Some(false)
        } else {
          None
        }
        match (terminal, cygwin) {
          (Some(terminal), Some(cygwin)) =>
            Some(@abi.Bool(terminal || (self.cygwin && cygwin)))
          _ => ctx.declared()
        }
      } else {
        ctx.declared()
      }
    None => ctx.declared()
  }
}

///|
pub fn tty_type(stream : String?, cygwin? : Bool = true) -> &TypeExt {
  TtyTypeExt::{ stream, cygwin } as &TypeExt
}

///|
/// DR-117 §2 string preset. The resident stays distinct through node construction so completion can
/// offer supported shell names, then lowering collapses the stored entity type to ordinary string.
priv struct CompletionScriptTypeExt {}

///|
impl TypeExt for CompletionScriptTypeExt with fn name(_self) {
  "completion_script"
}

///|
impl TypeExt for CompletionScriptTypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl TypeExt for CompletionScriptTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for CompletionScriptTypeExt with fn parse_token(_self, token) {
  Ok(@abi.String(token))
}

///|
impl TypeExt for CompletionScriptTypeExt with fn completion_values(_self) {
  ["zsh", "bash", "fish"]
}

///|
impl TypeExt for CompletionScriptTypeExt with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
pub fn completion_script_type() -> &TypeExt {
  CompletionScriptTypeExt::{  } as &TypeExt
}

///|
priv struct NoneTypeExt {}

///|
impl TypeExt for NoneTypeExt with fn name(_self) {
  "none"
}

///|
impl TypeExt for NoneTypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl TypeExt for NoneTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl TypeExt for NoneTypeExt with fn parse_token(_self, _token) {
  Err(type_parse_no_value_space())
}

///|
impl TypeExt for NoneTypeExt with fn default_seat_resolver(_self, _ctx) {
  None
}

///|
pub fn none_type() -> &TypeExt {
  NoneTypeExt::{  } as &TypeExt
}

///|
/// Rebuild a type resident with the parser configuration carried by a declaration.
/// Preset identities stay distinct even when their value parser matches a base type.
pub fn configured_type(
  ty : &TypeExt,
  round : @abi.RoundMode,
  bool_config : @abi.BoolConfig,
  allow_base_prefix? : Bool = false,
) -> &TypeExt {
  match ty.name() {
    "string" => string_type()
    "number" => number_type(allow_base_prefix~)
    "int" => int_type(round~, allow_base_prefix~)
    "float" => float_type()
    "flag" => flag_type(config=bool_config)
    "bool" => bool_type(config=bool_config)
    "count" => count_type(allow_base_prefix~)
    _ => ty
  }
}

///|
/// A short spelling for bool is presence-only even though the same bool resident
/// accepts a value on long eq-split and positional value paths.
pub fn configured_short_type(
  ty : &TypeExt,
  round : @abi.RoundMode,
  allow_base_prefix : Bool,
  bool_config : @abi.BoolConfig,
) -> &TypeExt {
  if ty.name() == "bool" {
    bool_type(config=bool_config, value_slot=false)
  } else {
    configured_type(ty, round, bool_config, allow_base_prefix~)
  }
}
