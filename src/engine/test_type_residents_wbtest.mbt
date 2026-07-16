// test_type_residents_wbtest.mbt — synthetic TypeExt residents for engine whitebox tests.

///|
priv struct TestStringType {}

///|
impl TypeExt for TestStringType with fn name(_self) {
  "string"
}

///|
impl TypeExt for TestStringType with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for TestStringType with fn parse_token(_self, token) {
  Ok(VStr(token))
}

///|
impl TypeExt for TestStringType with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
fn string_type() -> &TypeExt {
  TestStringType::{  } as &TypeExt
}

///|
priv struct TestNumberType {
  allow_base_prefix : Bool
}

///|
impl TypeExt for TestNumberType with fn name(_self) {
  "number"
}

///|
impl TypeExt for TestNumberType with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for TestNumberType with fn parse_token(self, token) {
  match parse_number_ext(token, self.allow_base_prefix) {
    Some(value) => Ok(VNum(value))
    None => Err(NotANumber)
  }
}

///|
impl TypeExt for TestNumberType with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
fn number_type(allow_base_prefix? : Bool = false) -> &TypeExt {
  TestNumberType::{ allow_base_prefix, } as &TypeExt
}

///|
priv struct TestIntType {
  round : RoundMode
  allow_base_prefix : Bool
}

///|
impl TypeExt for TestIntType with fn name(_self) {
  "int"
}

///|
impl TypeExt for TestIntType with fn has_value_slot(_self) {
  true
}

///|
impl TypeExt for TestIntType with fn parse_token(self, token) {
  match parse_int_value_ext(token, self.round, self.allow_base_prefix) {
    Ok(value) => Ok(VNum(value.to_double()))
    Err(fail) => Err(fail)
  }
}

///|
impl TypeExt for TestIntType with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
fn int_type(
  round? : RoundMode = RError,
  allow_base_prefix? : Bool = false,
) -> &TypeExt {
  TestIntType::{ round, allow_base_prefix } as &TypeExt
}

///|
priv struct TestBoolType {
  value_slot : Bool
}

///|
impl TypeExt for TestBoolType with fn name(_self) {
  "bool"
}

///|
impl TypeExt for TestBoolType with fn has_value_slot(self) {
  self.value_slot
}

///|
impl TypeExt for TestBoolType with fn parse_token(_self, token) {
  match parse_bool(token) {
    Some(value) => Ok(VBool(value))
    None => Err(NotABool)
  }
}

///|
impl TypeExt for TestBoolType with fn default_seat_resolver(_self, ctx) {
  ctx.declared()
}

///|
fn bool_type(value_slot? : Bool = true) -> &TypeExt {
  TestBoolType::{ value_slot, } as &TypeExt
}

///|
priv struct TestFlagType {}

///|
impl TypeExt for TestFlagType with fn name(_self) {
  "flag"
}

///|
impl TypeExt for TestFlagType with fn has_value_slot(_self) {
  false
}

///|
impl TypeExt for TestFlagType with fn parse_token(_self, token) {
  match parse_bool(token) {
    Some(value) => Ok(VBool(value))
    None => Err(NotABool)
  }
}

///|
impl TypeExt for TestFlagType with fn default_seat_resolver(_self, ctx) {
  match ctx.declared() {
    Some(value) => Some(value)
    None => Some(VBool(false))
  }
}

///|
fn flag_type() -> &TypeExt {
  TestFlagType::{  } as &TypeExt
}
