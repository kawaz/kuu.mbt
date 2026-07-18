// type_residents.mbt — builtin type-category residents behind the open @engine.TypeExt contract.

///|
priv struct StringTypeExt {}

///|
impl @engine.TypeExt for StringTypeExt with fn name(_self) {
  "string"
}

///|
impl @engine.TypeExt for StringTypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.TypeExt for StringTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @engine.TypeExt for StringTypeExt with fn parse_token(_self, token) {
  Ok(@engine.VStr(token))
}

///|
impl @engine.TypeExt for StringTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn string_type() -> &@engine.TypeExt {
  StringTypeExt::{  } as &@engine.TypeExt
}

///|
priv struct NumberTypeExt {
  allow_base_prefix : Bool
}

///|
impl @engine.TypeExt for NumberTypeExt with fn name(_self) {
  "number"
}

///|
impl @engine.TypeExt for NumberTypeExt with fn encode(self) {
  self.allow_base_prefix.to_json()
}

///|
impl @engine.TypeExt for NumberTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @engine.TypeExt for NumberTypeExt with fn parse_token(self, token) {
  match parse_number(token, allow_base_prefix=self.allow_base_prefix) {
    Some(value) => Ok(@engine.VNum(value))
    None => Err(type_parse_not_a_number(token))
  }
}

///|
impl @engine.TypeExt for NumberTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn number_type(allow_base_prefix? : Bool = false) -> &@engine.TypeExt {
  NumberTypeExt::{ allow_base_prefix, } as &@engine.TypeExt
}

///|
priv struct IntTypeExt {
  round : @engine.RoundMode
  allow_base_prefix : Bool
}

///|
impl @engine.TypeExt for IntTypeExt with fn name(_self) {
  "int"
}

///|
impl @engine.TypeExt for IntTypeExt with fn encode(self) {
  [round_mode_json(self.round), self.allow_base_prefix.to_json()].to_json()
}

///|
impl @engine.TypeExt for IntTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @engine.TypeExt for IntTypeExt with fn parse_token(self, token) {
  match
    parse_int_value(token, self.round, allow_base_prefix=self.allow_base_prefix) {
    Ok(value) => Ok(@engine.VNum(value.to_double()))
    Err(fail) => Err(fail)
  }
}

///|
impl @engine.TypeExt for IntTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn int_type(
  round? : @engine.RoundMode = @engine.RError,
  allow_base_prefix? : Bool = false,
) -> &@engine.TypeExt {
  IntTypeExt::{ round, allow_base_prefix } as &@engine.TypeExt
}

///|
priv struct FloatTypeExt {}

///|
impl @engine.TypeExt for FloatTypeExt with fn name(_self) {
  "float"
}

///|
impl @engine.TypeExt for FloatTypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.TypeExt for FloatTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @engine.TypeExt for FloatTypeExt with fn parse_token(_self, token) {
  match parse_float(token) {
    Some(value) => Ok(@engine.VNum(value))
    None => Err(type_parse_not_a_number(token))
  }
}

///|
impl @engine.TypeExt for FloatTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn float_type() -> &@engine.TypeExt {
  FloatTypeExt::{  } as &@engine.TypeExt
}

///|
priv struct BoolTypeExt {
  config : @engine.BoolConfig
  value_slot : Bool
}

///|
impl @engine.TypeExt for BoolTypeExt with fn name(_self) {
  "bool"
}

///|
impl @engine.TypeExt for BoolTypeExt with fn encode(self) {
  [bool_config_json(self.config), self.value_slot.to_json()].to_json()
}

///|
impl @engine.TypeExt for BoolTypeExt with fn has_value_slot(self) {
  self.value_slot
}

///|
impl @engine.TypeExt for BoolTypeExt with fn parse_token(self, token) {
  match parse_bool(token, config=self.config) {
    Some(value) => Ok(@engine.VBool(value))
    None => Err(type_parse_not_a_bool(token))
  }
}

///|
impl @engine.TypeExt for BoolTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn bool_type(
  config? : @engine.BoolConfig = bool_config_canonical(),
  value_slot? : Bool = true,
) -> &@engine.TypeExt {
  BoolTypeExt::{ config, value_slot } as &@engine.TypeExt
}

///|
priv struct FlagTypeExt {
  config : @engine.BoolConfig
}

///|
impl @engine.TypeExt for FlagTypeExt with fn name(_self) {
  "flag"
}

///|
impl @engine.TypeExt for FlagTypeExt with fn encode(self) {
  bool_config_json(self.config)
}

///|
impl @engine.TypeExt for FlagTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl @engine.TypeExt for FlagTypeExt with fn parse_token(self, token) {
  match parse_bool(token, config=self.config) {
    Some(value) => Ok(@engine.VBool(value))
    None => Err(type_parse_not_a_bool(token))
  }
}

///|
impl @engine.TypeExt for FlagTypeExt with fn default_seat_resolver(_self, ctx) {
  match ctx.declared() {
    Some(value) => Some(value)
    None => Some(@engine.VBool(false))
  }
}

///|
pub fn flag_type(
  config? : @engine.BoolConfig = bool_config_canonical(),
) -> &@engine.TypeExt {
  FlagTypeExt::{ config, } as &@engine.TypeExt
}

///|
priv struct CountTypeExt {
  allow_base_prefix : Bool
}

///|
impl @engine.TypeExt for CountTypeExt with fn name(_self) {
  "count"
}

///|
impl @engine.TypeExt for CountTypeExt with fn encode(self) {
  self.allow_base_prefix.to_json()
}

///|
impl @engine.TypeExt for CountTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl @engine.TypeExt for CountTypeExt with fn parse_token(self, token) {
  match parse_number(token, allow_base_prefix=self.allow_base_prefix) {
    Some(value) => Ok(@engine.VNum(value))
    None => Err(type_parse_not_a_number(token))
  }
}

///|
impl @engine.TypeExt for CountTypeExt with fn default_seat_resolver(_self, ctx) {
  match ctx.declared() {
    Some(value) => Some(value)
    None => Some(@engine.VNum(0.0))
  }
}

///|
pub fn count_type(allow_base_prefix? : Bool = false) -> &@engine.TypeExt {
  CountTypeExt::{ allow_base_prefix, } as &@engine.TypeExt
}

///|
priv struct TtyTypeExt {
  stream : String?
  cygwin : Bool
}

///|
impl @engine.TypeExt for TtyTypeExt with fn name(_self) {
  "bool"
}

///|
impl @engine.TypeExt for TtyTypeExt with fn encode(self) {
  ["tty".to_json(), self.stream.to_json(), self.cygwin.to_json()].to_json()
}

///|
impl @engine.TypeExt for TtyTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl @engine.TypeExt for TtyTypeExt with fn parse_token(_self, token) {
  match parse_bool(token, config=bool_config_canonical()) {
    Some(value) => Ok(@engine.VBool(value))
    None => Err(type_parse_not_a_bool(token))
  }
}

///|
impl @engine.TypeExt for TtyTypeExt with fn default_seat_observation_key(self) {
  self.stream
}

///|
impl @engine.TypeExt for TtyTypeExt with fn default_seat_resolver(self, ctx) {
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
            Some(@engine.VBool(terminal || (self.cygwin && cygwin)))
          _ => ctx.declared()
        }
      } else {
        ctx.declared()
      }
    None => ctx.declared()
  }
}

///|
pub fn tty_type(stream : String?, cygwin? : Bool = true) -> &@engine.TypeExt {
  TtyTypeExt::{ stream, cygwin } as &@engine.TypeExt
}

///|
priv struct NoneTypeExt {}

///|
impl @engine.TypeExt for NoneTypeExt with fn name(_self) {
  "none"
}

///|
impl @engine.TypeExt for NoneTypeExt with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.TypeExt for NoneTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl @engine.TypeExt for NoneTypeExt with fn parse_token(_self, _token) {
  Err(type_parse_no_value_space())
}

///|
impl @engine.TypeExt for NoneTypeExt with fn default_seat_resolver(_self, _ctx) {
  None
}

///|
pub fn none_type() -> &@engine.TypeExt {
  NoneTypeExt::{  } as &@engine.TypeExt
}

///|
/// Rebuild a type resident with the parser configuration carried by a declaration.
/// Preset identities stay distinct even when their value parser matches a base type.
pub fn configured_type(
  ty : &@engine.TypeExt,
  round : @engine.RoundMode,
  allow_base_prefix : Bool,
  bool_config : @engine.BoolConfig,
) -> &@engine.TypeExt {
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
  ty : &@engine.TypeExt,
  round : @engine.RoundMode,
  allow_base_prefix : Bool,
  bool_config : @engine.BoolConfig,
) -> &@engine.TypeExt {
  if ty.name() == "bool" {
    bool_type(config=bool_config, value_slot=false)
  } else {
    configured_type(ty, round, allow_base_prefix, bool_config)
  }
}
