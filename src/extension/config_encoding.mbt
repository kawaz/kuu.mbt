///|
fn filter_spellings_json(filters : Array[@abi.FnInvocation]) -> Json {
  let encoded : Array[Json] = []
  for filter in filters {
    encoded.push([filter.name.to_json(), filter.args.to_json()].to_json())
  }
  encoded.to_json()
}

///|
fn round_mode_json(mode : @abi.RoundMode) -> Json {
  let name = match mode {
    @abi.Floor => "floor"
    @abi.Ceil => "ceil"
    @abi.Trunc => "trunc"
    @abi.Away => "away"
    @abi.HalfFloor => "half_floor"
    @abi.HalfCeil => "half_ceil"
    @abi.HalfTrunc => "half_trunc"
    @abi.HalfAway => "half_away"
    @abi.HalfEven => "half_even"
    @abi.Error => "error"
  }
  name.to_json()
}

///|
fn bool_config_json(config : @abi.BoolConfig) -> Json {
  [
    config.true_values.to_json(),
    config.false_values.to_json(),
    config.case_insensitive.to_json(),
  ].to_json()
}
