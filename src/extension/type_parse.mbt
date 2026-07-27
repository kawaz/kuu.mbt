// type_parse.mbt — builtin type failure vocabulary and ParseError adaptation.

///|
fn type_parse_fail(
  disposition : @abi.TypeParseDisposition,
  reason : String,
  message : String,
) -> @abi.TypeParseFail {
  { disposition, reason, message }
}

///|
fn type_parse_not_a_number(token : String) -> @abi.TypeParseFail {
  type_parse_fail(
    @abi.ValueSpaceMiss,
    "not_a_number",
    "value \"\{token}\" is not a number",
  )
}

///|
fn type_parse_not_an_integer(token : String) -> @abi.TypeParseFail {
  type_parse_fail(
    @abi.RecognizedButInvalid,
    "not_an_integer",
    "value \"\{token}\" is not an integer",
  )
}

///|
fn type_parse_int_out_of_range(token : String) -> @abi.TypeParseFail {
  type_parse_fail(
    @abi.RecognizedButInvalid,
    "int_out_of_range",
    "value \"\{token}\" is out of Int64 range",
  )
}

///|
fn type_parse_not_a_bool(token : String) -> @abi.TypeParseFail {
  type_parse_fail(
    @abi.ValueSpaceMiss,
    "not_a_bool",
    "value \"\{token}\" is not a bool",
  )
}

///|
fn type_parse_no_value_space() -> @abi.TypeParseFail {
  type_parse_fail(
    @abi.ValueSpaceMiss,
    "config_type_mismatch",
    "value for a none element (no value space)",
  )
}

///|
pub fn type_parse_error(
  element : String,
  pos : Int,
  failure : @abi.TypeParseFail,
) -> @abi.ParseError {
  {
    element,
    args_pos: pos,
    kind: @abi.Parse,
    reason: failure.reason,
    message: failure.message,
    path: [],
  }
}

///|
/// Convert a type resident's declared DR-037 phase into the evaluator branch channel without
/// inspecting its open reason vocabulary.
pub fn type_parse_branch(
  element : String,
  pos : Int,
  failure : @abi.TypeParseFail,
  bindings : Array[@abi.Binding],
) -> @abi.Branch {
  let error = type_parse_error(element, pos, failure)
  match failure.disposition {
    @abi.ValueSpaceMiss => @abi.Rejected(error, bindings)
    @abi.RecognizedButInvalid => @abi.Held(error, bindings)
  }
}

///|
pub fn parse_error_not_a_number(
  element : String,
  token : String,
  pos : Int,
) -> @abi.ParseError {
  type_parse_error(element, pos, type_parse_not_a_number(token))
}

///|
pub fn parse_error_not_a_bool(
  element : String,
  token : String,
  pos : Int,
) -> @abi.ParseError {
  type_parse_error(element, pos, type_parse_not_a_bool(token))
}

///|
pub fn parse_error_not_a_kv_pair(
  element : String,
  token : String,
  pos : Int,
) -> @abi.ParseError {
  type_parse_error(
    element,
    pos,
    type_parse_fail(
      @abi.ValueSpaceMiss,
      "not_a_kv_pair",
      "value \"\{token}\" does not contain '=' (expected key=value)",
    ),
  )
}
