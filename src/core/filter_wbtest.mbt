///|
test "Filter::map — pure transformation" {
  let chain = Filter::map(fn(s : String) { s.length() })
  let result : Result[Int, _] = try? (chain.run)("hello")
  match result {
    Ok(v) => inspect(v, content="5")
    Err(_) => fail("expected Ok")
  }
}

///|
test "Filter::validate — success passes value through" {
  let chain = Filter::validate(fn(s : String) raise ParseError {
    if s.is_empty() {
      raise parse_error("must not be empty")
    }
  })
  let result : Result[String, _] = try? (chain.run)("ok")
  match result {
    Ok(v) => inspect(v, content="ok")
    Err(_) => fail("expected Ok")
  }
}

///|
test "Filter::validate — failure raises ParseError" {
  let chain = Filter::validate(fn(s : String) raise ParseError {
    if s.is_empty() {
      raise parse_error("must not be empty")
    }
  })
  let result : Result[String, _] = try? (chain.run)("")
  inspect(result is Err(_), content="true")
}

///|
test "Filter::parse — successful conversion" {
  let chain = Filter::parse(fn(s : String) raise ParseError {
    let r : Result[Int, _] = try? @strconv.parse_int(s.view())
    match r {
      Ok(v) => v
      Err(_) => raise parse_error("not an int")
    }
  })
  let result : Result[Int, _] = try? (chain.run)("42")
  match result {
    Ok(v) => inspect(v, content="42")
    Err(_) => fail("expected Ok")
  }
}

///|
test "Filter::parse — failure raises ParseError" {
  let chain = Filter::parse(fn(s : String) raise ParseError {
    let r : Result[Int, _] = try? @strconv.parse_int(s.view())
    match r {
      Ok(v) => v
      Err(_) => raise parse_error("not an int")
    }
  })
  let result : Result[Int, _] = try? (chain.run)("abc")
  inspect(result is Err(_), content="true")
}

///|
test "then composition — trim then parse_int" {
  let chain = Filter::trim().then(Filter::parse_int())
  let result : Result[Int, _] = try? (chain.run)("  42  ")
  match result {
    Ok(v) => inspect(v, content="42")
    Err(_) => fail("expected Ok")
  }
}

///|
test "then type chain — trim then split then each(parse_int)" {
  let chain = Filter::trim().then(Filter::split(",")).then(
    Filter::each(Filter::parse_int()),
  )
  let result : Result[Array[Int], _] = try? (chain.run)(" 1,2,3 ")
  match result {
    Ok(v) => inspect(v, content="[1, 2, 3]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "trim — removes whitespace" {
  let chain = Filter::trim()
  let result : Result[String, _] = try? (chain.run)("  hello  ")
  match result {
    Ok(v) => inspect(v, content="hello")
    Err(_) => fail("expected Ok")
  }
}

///|
test "non_empty — passes non-empty string" {
  let chain = Filter::non_empty()
  let result : Result[String, _] = try? (chain.run)("ok")
  match result {
    Ok(v) => inspect(v, content="ok")
    Err(_) => fail("expected Ok")
  }
}

///|
test "non_empty — rejects empty string" {
  let chain = Filter::non_empty()
  let result : Result[String, _] = try? (chain.run)("")
  inspect(result is Err(_), content="true")
}

///|
test "split — splits string by separator" {
  let chain = Filter::split(",")
  let result : Result[Array[String], _] = try? (chain.run)("a,b,c")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_int — valid integer" {
  let chain = Filter::parse_int()
  let result : Result[Int, _] = try? (chain.run)("123")
  match result {
    Ok(v) => inspect(v, content="123")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_int — invalid integer" {
  let chain = Filter::parse_int()
  let result : Result[Int, _] = try? (chain.run)("abc")
  inspect(result is Err(_), content="true")
}

///|
test "parse_float — valid float" {
  let chain = Filter::parse_float()
  let result : Result[Double, _] = try? (chain.run)("3.14")
  match result {
    Ok(v) => inspect(v, content="3.14")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_float — invalid float" {
  let chain = Filter::parse_float()
  let result : Result[Double, _] = try? (chain.run)("abc")
  inspect(result is Err(_), content="true")
}

///|
test "in_range — within range" {
  let chain = Filter::in_range(1, 10)
  let result : Result[Int, _] = try? (chain.run)(5)
  match result {
    Ok(v) => inspect(v, content="5")
    Err(_) => fail("expected Ok")
  }
}

///|
test "in_range — below range" {
  let chain = Filter::in_range(1, 10)
  let result : Result[Int, _] = try? (chain.run)(0)
  inspect(result is Err(_), content="true")
}

///|
test "in_range — above range" {
  let chain = Filter::in_range(1, 10)
  let result : Result[Int, _] = try? (chain.run)(11)
  inspect(result is Err(_), content="true")
}

///|
test "one_of — valid value" {
  let chain = Filter::one_of(["red", "green", "blue"])
  let result : Result[String, _] = try? (chain.run)("green")
  match result {
    Ok(v) => inspect(v, content="green")
    Err(_) => fail("expected Ok")
  }
}

///|
test "one_of — invalid value" {
  let chain = Filter::one_of(["red", "green", "blue"])
  let result : Result[String, _] = try? (chain.run)("yellow")
  inspect(result is Err(_), content="true")
}

///|
test "each — applies filter to each element" {
  let chain = Filter::each(Filter::parse_int())
  let result : Result[Array[Int], _] = try? (chain.run)(["1", "2", "3"])
  match result {
    Ok(v) => inspect(v, content="[1, 2, 3]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "each — propagates error from element" {
  let chain = Filter::each(Filter::parse_int())
  let result : Result[Array[Int], _] = try? (chain.run)(["1", "abc", "3"])
  inspect(result is Err(_), content="true")
}

///|
test "error propagation — chain stops at first error" {
  let chain = Filter::non_empty().then(Filter::parse_int())
  let result : Result[Int, _] = try? (chain.run)("")
  inspect(result is Err(_), content="true")
}

///|
test "to_lower — converts to lowercase" {
  let chain = Filter::to_lower()
  let result : Result[String, _] = try? (chain.run)("HELLO")
  match result {
    Ok(v) => inspect(v, content="hello")
    Err(_) => fail("expected Ok")
  }
}

///|
test "make_reducer — Value(Some(s)) applies pre and accumulates" {
  let pre = Filter::trim().then(Filter::parse_int())
  let accum : Accumulator[Int, Int] = ((fn(cur, piece) { cur + piece }) : Accumulator[_, _])
  let reducer = make_reducer(pre, accum, 0)
  let ctx = ReduceCtx::{ current: 10, action: Value(Some("  5  ")) }
  let result : Result[Int?, _] = try? reducer(ctx)
  match result {
    Ok(Some(v)) => inspect(v, content="15")
    _ => fail("expected Ok(Some(15))")
  }
}

///|
test "make_reducer — Negate returns initial value" {
  let pre = Filter::parse_int()
  let accum : Accumulator[Int, Int] = ((fn(cur, piece) { cur + piece }) : Accumulator[_, _])
  let reducer = make_reducer(pre, accum, 0)
  let ctx = ReduceCtx::{ current: 42, action: Negate }
  let result : Result[Int?, _] = try? reducer(ctx)
  match result {
    Ok(Some(v)) => inspect(v, content="0")
    _ => fail("expected Ok(Some(0))")
  }
}

///|
test "make_reducer — Value(None) returns None" {
  let pre = Filter::parse_int()
  let accum : Accumulator[Int, Int] = ((fn(cur, piece) { cur + piece }) : Accumulator[_, _])
  let reducer = make_reducer(pre, accum, 0)
  let ctx = ReduceCtx::{ current: 10, action: Value(None) }
  let result : Result[Int?, _] = try? reducer(ctx)
  match result {
    Ok(None) => ()
    _ => fail("expected Ok(None)")
  }
}

///|
test "make_reducer — pre error propagation" {
  let pre = Filter::parse_int()
  let accum : Accumulator[Int, Int] = ((fn(cur, piece) { cur + piece }) : Accumulator[_, _])
  let reducer = make_reducer(pre, accum, 0)
  let ctx = ReduceCtx::{ current: 10, action: Value(Some("not_a_number")) }
  let result : Result[Int?, _] = try? reducer(ctx)
  inspect(result is Err(_), content="true")
}

///|
test "make_reducer — FilterChain composition: trim.then(parse_int).then(in_range)" {
  let pre = Filter::trim().then(Filter::parse_int()).then(
    Filter::in_range(1, 65535),
  )
  let accum : Accumulator[Int, Int] = ((fn(_cur, piece) { piece }) : Accumulator[_, _])
  let reducer = make_reducer(pre, accum, 0)
  // Valid value in range
  let ctx1 = ReduceCtx::{ current: 0, action: Value(Some("  8080  ")) }
  let r1 : Result[Int?, _] = try? reducer(ctx1)
  match r1 {
    Ok(Some(v)) => inspect(v, content="8080")
    _ => fail("expected Ok(Some(8080))")
  }
  // Value out of range should error
  let ctx2 = ReduceCtx::{ current: 0, action: Value(Some("  99999  ")) }
  let r2 : Result[Int?, _] = try? reducer(ctx2)
  inspect(r2 is Err(_), content="true")
}
