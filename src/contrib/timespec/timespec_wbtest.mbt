// --- parse_duration filter tests ---

///|
test "parse_duration — 30s parses to 30000ms" {
  let chain = parse_duration()
  let result : Result[@ts.Duration, _] = try? (chain.run)("30s")
  match result {
    Ok(d) => inspect(d.to_ms(), content="30000")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_duration — 1m30s parses to 90000ms" {
  let chain = parse_duration()
  let result : Result[@ts.Duration, _] = try? (chain.run)("1m30s")
  match result {
    Ok(d) => inspect(d.to_ms(), content="90000")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_duration — invalid value raises error" {
  let chain = parse_duration()
  let result : Result[@ts.Duration, _] = try? (chain.run)("notaduration")
  inspect(result is Err(_), content="true")
}

///|
test "parse_duration — empty string raises error" {
  let chain = parse_duration()
  let result : Result[@ts.Duration, _] = try? (chain.run)("")
  inspect(result is Err(_), content="true")
}

///|
test "parse_duration — 1h2m3s compound" {
  let chain = parse_duration()
  let result : Result[@ts.Duration, _] = try? (chain.run)("1h2m3s")
  match result {
    Ok(d) => inspect(d.to_ms(), content="3723000")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_duration — default_sign Plus (default)" {
  let chain = parse_duration()
  let result : Result[@ts.Duration, _] = try? (chain.run)("5m")
  match result {
    Ok(d) => inspect(d.to_ms(), content="300000")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_duration — default_sign Minus" {
  let chain = parse_duration(default_sign=Minus)
  let result : Result[@ts.Duration, _] = try? (chain.run)("5m")
  match result {
    Ok(d) => inspect(d.to_ms(), content="-300000")
    Err(_) => fail("expected Ok")
  }
}

// --- parse_timespec filter tests ---

///|
test "parse_timespec — relative 5m with default_sign Minus" {
  let fixed_now : UInt64 = 1_000_000_000_000UL // 1e12 ms
  let chain = parse_timespec(default_sign=Minus, now=fn() { fixed_now })
  let result : Result[@ts.TimeSpec, _] = try? (chain.run)("5m")
  match result {
    Ok(ts) => {
      // 5m = 300000ms, now=1e12, so epoch = 1e12 - 300000 = 999999700000
      inspect(ts.to_epoch_ms(), content="999999700000")
      inspect(ts.is_absolute(), content="false")
    }
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_timespec — absolute with @ prefix" {
  let fixed_now : UInt64 = 1_000_000_000_000UL
  let chain = parse_timespec(default_sign=Minus, now=fn() { fixed_now })
  let result : Result[@ts.TimeSpec, _] = try? (chain.run)("@5m")
  match result {
    Ok(ts) => {
      inspect(ts.to_epoch_ms(), content="999999700000")
      inspect(ts.is_absolute(), content="true")
    }
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_timespec — invalid input raises error" {
  let chain = parse_timespec()
  let result : Result[@ts.TimeSpec, _] = try? (chain.run)("")
  inspect(result is Err(_), content="true")
}

// --- FilterChain composition test ---

///|
test "parse_duration — then chain with validate" {
  // parse_duration |> validate positive
  let chain = parse_duration().then(
    @core.Filter::validate(fn(d : @ts.Duration) raise @core.ParseError {
      if d.to_ms() <= 0L {
        raise @core.ParseError(@core.ParseErrorInfo::{
          kind: InvalidValue,
          message: "duration must be positive",
          error_context: "",
          opt_name: "",
          tip: "",
        })
      }
    }),
  )
  let ok_result : Result[@ts.Duration, _] = try? (chain.run)("30s")
  match ok_result {
    Ok(d) => inspect(d.to_ms(), content="30000")
    Err(_) => fail("expected Ok for 30s")
  }
  let err_result : Result[@ts.Duration, _] = try? (chain.run)("-30s")
  inspect(err_result is Err(_), content="true")
}
