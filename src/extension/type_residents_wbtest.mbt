// type_residents_wbtest.mbt — TypeExt contract and builtin resident behavior.

///|
test "TypeExt names preserve the eight registry identities" {
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
test "TypeExt value-slot capability separates value types from presence presets" {
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
test "TypeExt parse_token delegates to each resident lexicon and config" {
  // Configured number/int/bool residents must parse through their own construction data, not a central type switch.
  assert_eq(
    number_type(allow_base_prefix=true).parse_token("0xff"),
    Ok(@abi.Number(255.0)),
  )
  assert_eq(int_type(round=@abi.Floor).parse_token("2.9"), Ok(@abi.Number(2.0)))
  assert_eq(
    bool_type(config={
      true_values: ["yes"],
      false_values: ["no"],
      case_insensitive: false,
    }).parse_token("yes"),
    Ok(@abi.Bool(true)),
  )
  assert_eq(
    none_type().parse_token("x").unwrap_err().reason,
    "config_type_mismatch",
  )
}

///|
test "TypeExt default resolver supplies only preset defaults" {
  // Explicit defaults win; otherwise flag/count supply their presets while ordinary and none types stay absent.
  assert_eq(
    flag_type().default_seat_resolver(SeatCtx::new(None)),
    Some(@abi.Bool(false)),
  )
  assert_eq(
    count_type().default_seat_resolver(SeatCtx::new(None)),
    Some(@abi.Number(0.0)),
  )
  assert_eq(
    flag_type().default_seat_resolver(SeatCtx::new(Some(@abi.Bool(true)))),
    Some(@abi.Bool(true)),
  )
  assert_eq(string_type().default_seat_resolver(SeatCtx::new(None)), None)
  assert_eq(
    none_type().default_seat_resolver(
      SeatCtx::new(Some(@abi.String("ignored"))),
    ),
    None,
  )
}

///|
test "tty TypeExt owns its provider key and default-seat fold" {
  // The resident, not Entity/resolve, owns stream selection and the terminal-or-Cygwin fold.
  let tty = tty_type(Some("stdout"), cygwin=true)
  assert_eq(tty.default_seat_observation_key(), Some("stdout"))
  assert_eq(
    tty.default_seat_resolver(
      SeatCtx::new(
        Some(@abi.Bool(false)),
        observed=Some([false.to_json(), true.to_json()].to_json()),
      ),
    ),
    Some(@abi.Bool(true)),
  )
  // Missing observation falls back to the declared default, then to absence.
  assert_eq(
    tty.default_seat_resolver(SeatCtx::new(Some(@abi.Bool(false)))),
    Some(@abi.Bool(false)),
  )
  assert_eq(
    tty_type(Some("stderr"), cygwin=false).default_seat_resolver(
      SeatCtx::new(None),
    ),
    None,
  )
}

///|
test "EntityExt carries completion metadata opaquely into Candidate" {
  // Engine dispatches one opaque decorator; the builtin resident owns hidden/completer contents.
  let extension = entity_ext(hidden=true, completer=Some("files"))
  let cand = extension.complete_candidate(
    @abi.Candidate::pending_value("string", "path"),
  )
  assert_eq(cand.hidden, true)
  assert_eq(cand.completer, Some("files"))
}
