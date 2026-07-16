// type_residents_wbtest.mbt — @engine.TypeExt contract and builtin resident behavior.

///|
test "@engine.TypeExt names preserve the eight registry identities" {
  // Registry lookup and wire decode use these exact spellings; changing one would disconnect that resident.
  assert_eq(
    [
      string_type().name(),
      number_type().name(),
      int_type().name(),
      float_type().name(),
      flag_type().name(),
      bool_type().name(),
      count_type().name(),
      none_type().name(),
    ],
    ["string", "number", "int", "float", "flag", "bool", "count", "none"],
  )
}

///|
test "@engine.TypeExt value-slot capability separates value types from presence presets" {
  // The five value types may request an operand; flag/count/none never expose an operand slot.
  assert_eq(
    [
      string_type().has_value_slot(),
      number_type().has_value_slot(),
      int_type().has_value_slot(),
      float_type().has_value_slot(),
      bool_type().has_value_slot(),
      flag_type().has_value_slot(),
      count_type().has_value_slot(),
      none_type().has_value_slot(),
    ],
    [true, true, true, true, true, false, false, false],
  )
}

///|
test "@engine.TypeExt parse_token delegates to each resident lexicon and config" {
  // Configured number/int/bool residents must parse through their own construction data, not a central type switch.
  assert_eq(
    number_type(allow_base_prefix=true).parse_token("0xff"),
    Ok(@engine.VNum(255.0)),
  )
  assert_eq(
    int_type(round=@engine.RFloor).parse_token("2.9"),
    Ok(@engine.VNum(2.0)),
  )
  assert_eq(
    bool_type(config={
      true_values: ["yes"],
      false_values: ["no"],
      case_insensitive: false,
    }).parse_token("yes"),
    Ok(@engine.VBool(true)),
  )
  assert_eq(
    none_type().parse_token("x").unwrap_err().reason(),
    "config_type_mismatch",
  )
}

///|
test "@engine.TypeExt default resolver supplies only preset defaults" {
  // Explicit defaults win; otherwise flag/count supply their presets while ordinary and none types stay absent.
  assert_eq(
    flag_type().default_seat_resolver(@engine.seat_ctx(None)),
    Some(@engine.VBool(false)),
  )
  assert_eq(
    count_type().default_seat_resolver(@engine.seat_ctx(None)),
    Some(@engine.VNum(0.0)),
  )
  assert_eq(
    flag_type().default_seat_resolver(
      @engine.seat_ctx(Some(@engine.VBool(true))),
    ),
    Some(@engine.VBool(true)),
  )
  assert_eq(string_type().default_seat_resolver(@engine.seat_ctx(None)), None)
  assert_eq(
    none_type().default_seat_resolver(
      @engine.seat_ctx(Some(@engine.VStr("ignored"))),
    ),
    None,
  )
}
