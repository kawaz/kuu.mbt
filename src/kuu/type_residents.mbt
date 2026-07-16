// type_residents.mbt — builtin type-category residents behind the open TypeExt contract.

///|
priv struct StringTypeExt {}

///|
impl TypeExt for StringTypeExt with fn name(_self) {
  "string"
}

///|
impl TypeExt for StringTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for StringTypeExt with fn parse_token(_self, token) {
  Ok(VStr(token))
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
impl TypeExt for NumberTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for NumberTypeExt with fn parse_token(self, token) {
  match parse_number_ext(token, self.allow_base_prefix) {
    Some(value) => Ok(VNum(value))
    None => Err(NotANumber)
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
  round : RoundMode
  allow_base_prefix : Bool
}

///|
impl TypeExt for IntTypeExt with fn name(_self) {
  "int"
}

///|
impl TypeExt for IntTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for IntTypeExt with fn parse_token(self, token) {
  match parse_int_value_ext(token, self.round, self.allow_base_prefix) {
    Ok(value) => Ok(VNum(value.to_double()))
    Err(fail) => Err(fail)
  }
}

///|
impl TypeExt for IntTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn int_type(
  round? : RoundMode = RError,
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
impl TypeExt for FloatTypeExt with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for FloatTypeExt with fn parse_token(_self, token) {
  match parse_float(token) {
    Some(value) => Ok(VNum(value))
    None => Err(NotANumber)
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
  config : BoolConfig
  value_slot : Bool
}

///|
impl TypeExt for BoolTypeExt with fn name(_self) {
  "bool"
}

///|
impl TypeExt for BoolTypeExt with fn has_value_slot(self) {
  self.value_slot
}

///|
impl TypeExt for BoolTypeExt with fn parse_token(self, token) {
  match parse_bool_ext(token, self.config) {
    Some(value) => Ok(VBool(value))
    None => Err(NotABool)
  }
}

///|
impl TypeExt for BoolTypeExt with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
pub fn bool_type(
  config? : BoolConfig = bool_config_canonical(),
  value_slot? : Bool = true,
) -> &TypeExt {
  BoolTypeExt::{ config, value_slot } as &TypeExt
}

///|
priv struct FlagTypeExt {
  config : BoolConfig
}

///|
impl TypeExt for FlagTypeExt with fn name(_self) {
  "flag"
}

///|
impl TypeExt for FlagTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl TypeExt for FlagTypeExt with fn parse_token(self, token) {
  match parse_bool_ext(token, self.config) {
    Some(value) => Ok(VBool(value))
    None => Err(NotABool)
  }
}

///|
impl TypeExt for FlagTypeExt with fn default_seat_resolver(_self, ctx) {
  match ctx.declared() {
    Some(value) => Some(value)
    None => Some(VBool(false))
  }
}

///|
pub fn flag_type(config? : BoolConfig = bool_config_canonical()) -> &TypeExt {
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
impl TypeExt for CountTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl TypeExt for CountTypeExt with fn parse_token(self, token) {
  match parse_number_ext(token, self.allow_base_prefix) {
    Some(value) => Ok(VNum(value))
    None => Err(NotANumber)
  }
}

///|
impl TypeExt for CountTypeExt with fn default_seat_resolver(_self, ctx) {
  match ctx.declared() {
    Some(value) => Some(value)
    None => Some(VNum(0.0))
  }
}

///|
pub fn count_type(allow_base_prefix? : Bool = false) -> &TypeExt {
  CountTypeExt::{ allow_base_prefix, } as &TypeExt
}

///|
priv struct NoneTypeExt {}

///|
impl TypeExt for NoneTypeExt with fn name(_self) {
  "none"
}

///|
impl TypeExt for NoneTypeExt with fn has_value_slot(_self) {
  false
}

///|
impl TypeExt for NoneTypeExt with fn parse_token(_self, _token) {
  Err(NoValueSpace)
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
  round : RoundMode,
  allow_base_prefix : Bool,
  bool_config : BoolConfig,
) -> &TypeExt {
  match ty.name() {
    "string" => string_type()
    "number" => number_type(allow_base_prefix~)
    "int" => int_type(round~, allow_base_prefix~)
    "float" => float_type()
    "flag" => flag_type(config=bool_config)
    "bool" => bool_type(config=bool_config)
    "count" => count_type(allow_base_prefix~)
    _ => none_type()
  }
}

///|
/// A short spelling for bool is presence-only even though the same bool resident
/// accepts a value on long eq-split and positional value paths.
pub fn configured_short_type(
  ty : &TypeExt,
  round : RoundMode,
  allow_base_prefix : Bool,
  bool_config : BoolConfig,
) -> &TypeExt {
  if ty.name() == "bool" {
    bool_type(config=bool_config, value_slot=false)
  } else {
    configured_type(ty, round, allow_base_prefix, bool_config)
  }
}
