// --- parse_duration filter tests ---

///|
test "parse_duration — 30s parses to 30000ms" {
  let chain = parse_duration()
  try (chain.run)("30s") catch {
    _ => fail("expected Ok")
  } noraise {
    d => inspect(d.to_ms(), content="30000")
  }
}

///|
test "parse_duration — 1m30s parses to 90000ms" {
  let chain = parse_duration()
  try (chain.run)("1m30s") catch {
    _ => fail("expected Ok")
  } noraise {
    d => inspect(d.to_ms(), content="90000")
  }
}

///|
test "parse_duration — invalid value raises error" {
  let chain = parse_duration()
  try {
    let _ = (chain.run)("notaduration")
  } catch {
    _ => ()
  } noraise {
    _ => fail("expected parse_duration to raise")
  }
}

///|
test "parse_duration — empty string raises error" {
  let chain = parse_duration()
  try {
    let _ = (chain.run)("")
  } catch {
    _ => ()
  } noraise {
    _ => fail("expected parse_duration to raise")
  }
}

///|
test "parse_duration — 1h2m3s compound" {
  let chain = parse_duration()
  try (chain.run)("1h2m3s") catch {
    _ => fail("expected Ok")
  } noraise {
    d => inspect(d.to_ms(), content="3723000")
  }
}

///|
test "parse_duration — default_sign Plus (default)" {
  let chain = parse_duration()
  try (chain.run)("5m") catch {
    _ => fail("expected Ok")
  } noraise {
    d => inspect(d.to_ms(), content="300000")
  }
}

///|
test "parse_duration — default_sign Minus" {
  let chain = parse_duration(default_sign=Minus)
  try (chain.run)("5m") catch {
    _ => fail("expected Ok")
  } noraise {
    d => inspect(d.to_ms(), content="-300000")
  }
}

// --- parse_timespec filter tests ---

///|
test "parse_timespec — relative 5m with default_sign Minus" {
  let fixed_now : UInt64 = 1_000_000_000_000UL // 1e12 ms
  let chain = parse_timespec(default_sign=Minus, now=fn() { fixed_now })
  try (chain.run)("5m") catch {
    _ => fail("expected Ok")
  } noraise {
    ts => {
      // 5m = 300000ms, now=1e12, so epoch = 1e12 - 300000 = 999999700000
      inspect(ts.to_epoch_ms(), content="999999700000")
      inspect(ts.is_absolute(), content="false")
    }
  }
}

///|
test "parse_timespec — absolute with @ prefix" {
  let fixed_now : UInt64 = 1_000_000_000_000UL
  let chain = parse_timespec(default_sign=Minus, now=fn() { fixed_now })
  try (chain.run)("@5m") catch {
    _ => fail("expected Ok")
  } noraise {
    ts => {
      inspect(ts.to_epoch_ms(), content="999999700000")
      inspect(ts.is_absolute(), content="true")
    }
  }
}

///|
test "parse_timespec — invalid input raises error" {
  let chain = parse_timespec()
  try {
    let _ = (chain.run)("")
  } catch {
    _ => ()
  } noraise {
    _ => fail("expected parse_timespec to raise")
  }
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
  try (chain.run)("30s") catch {
    _ => fail("expected Ok for 30s")
  } noraise {
    d => inspect(d.to_ms(), content="30000")
  }
  try {
    let _ = (chain.run)("-30s")
  } catch {
    _ => ()
  } noraise {
    _ => fail("expected chain.run to raise for -30s")
  }
}
