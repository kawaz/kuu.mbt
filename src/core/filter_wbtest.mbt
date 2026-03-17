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
  let chain = Filter::trim()
    .then(Filter::split(","))
    .then(Filter::each(Filter::parse_int()))
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
test "one_of — error message uses join format" {
  let chain = Filter::one_of(["red", "green", "blue"])
  let result : Result[String, _] = try? (chain.run)("yellow")
  match result {
    Err(ParseError(info)) =>
      inspect(
        info.message,
        content="value must be one of: red, green, blue",
      )
    _ => abort("expected ParseError")
  }
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
  let accum : Accumulator[Int, Int] = (
    fn(cur, piece) { cur + piece } : Accumulator[_, _])
  let reducer = make_reducer(pre, accum)
  let ctx = ReduceCtx::{ current: 10, action: Value(Some("  5  ")) }
  let result : Result[Int?, _] = try? reducer(ctx)
  match result {
    Ok(Some(v)) => inspect(v, content="15")
    _ => fail("expected Ok(Some(15))")
  }
}

///|
test "make_reducer — Value(None) returns None" {
  let pre = Filter::parse_int()
  let accum : Accumulator[Int, Int] = (
    fn(cur, piece) { cur + piece } : Accumulator[_, _])
  let reducer = make_reducer(pre, accum)
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
  let accum : Accumulator[Int, Int] = (
    fn(cur, piece) { cur + piece } : Accumulator[_, _])
  let reducer = make_reducer(pre, accum)
  let ctx = ReduceCtx::{ current: 10, action: Value(Some("not_a_number")) }
  let result : Result[Int?, _] = try? reducer(ctx)
  inspect(result is Err(_), content="true")
}

///|
test "make_reducer — FilterChain composition: trim.then(parse_int).then(in_range)" {
  let pre = Filter::trim()
    .then(Filter::parse_int())
    .then(Filter::in_range(1, 65535))
  let accum : Accumulator[Int, Int] = (
    fn(_cur, piece) { piece } : Accumulator[_, _])
  let reducer = make_reducer(pre, accum)
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

///|
test "in_range at lower boundary" {
  let chain = Filter::in_range(1, 10)
  let result : Result[Int, _] = try? (chain.run)(1)
  match result {
    Ok(v) => inspect(v, content="1")
    Err(_) => fail("expected Ok")
  }
}

///|
test "in_range at upper boundary" {
  let chain = Filter::in_range(1, 10)
  let result : Result[Int, _] = try? (chain.run)(10)
  match result {
    Ok(v) => inspect(v, content="10")
    Err(_) => fail("expected Ok")
  }
}

// --- to_upper ---

///|
test "to_upper — converts to uppercase" {
  let chain = Filter::to_upper()
  let result : Result[String, _] = try? (chain.run)("hello")
  match result {
    Ok(v) => inspect(v, content="HELLO")
    Err(_) => fail("expected Ok")
  }
}

///|
test "to_upper — preserves non-alpha" {
  let chain = Filter::to_upper()
  let result : Result[String, _] = try? (chain.run)("abc-123")
  match result {
    Ok(v) => inspect(v, content="ABC-123")
    Err(_) => fail("expected Ok")
  }
}

// --- starts_with ---

///|
test "starts_with — passes matching prefix" {
  let chain = Filter::starts_with("http")
  let result : Result[String, _] = try? (chain.run)("https://example.com")
  match result {
    Ok(v) => inspect(v, content="https://example.com")
    Err(_) => fail("expected Ok")
  }
}

///|
test "starts_with — rejects non-matching prefix" {
  let chain = Filter::starts_with("http")
  let result : Result[String, _] = try? (chain.run)("ftp://example.com")
  inspect(result is Err(_), content="true")
}

// --- ends_with ---

///|
test "ends_with — passes matching suffix" {
  let chain = Filter::ends_with(".json")
  let result : Result[String, _] = try? (chain.run)("config.json")
  match result {
    Ok(v) => inspect(v, content="config.json")
    Err(_) => fail("expected Ok")
  }
}

///|
test "ends_with — rejects non-matching suffix" {
  let chain = Filter::ends_with(".json")
  let result : Result[String, _] = try? (chain.run)("config.yaml")
  inspect(result is Err(_), content="true")
}

// --- contains ---

///|
test "contains — passes when substring present" {
  let chain = Filter::contains("world")
  let result : Result[String, _] = try? (chain.run)("hello world")
  match result {
    Ok(v) => inspect(v, content="hello world")
    Err(_) => fail("expected Ok")
  }
}

///|
test "contains — rejects when substring absent" {
  let chain = Filter::contains("world")
  let result : Result[String, _] = try? (chain.run)("hello there")
  inspect(result is Err(_), content="true")
}

// --- min_length ---

///|
test "min_length — passes when long enough" {
  let chain = Filter::min_length(3)
  let result : Result[String, _] = try? (chain.run)("abc")
  match result {
    Ok(v) => inspect(v, content="abc")
    Err(_) => fail("expected Ok")
  }
}

///|
test "min_length — rejects when too short" {
  let chain = Filter::min_length(3)
  let result : Result[String, _] = try? (chain.run)("ab")
  inspect(result is Err(_), content="true")
}

// --- max_length ---

///|
test "max_length — passes when short enough" {
  let chain = Filter::max_length(5)
  let result : Result[String, _] = try? (chain.run)("hello")
  match result {
    Ok(v) => inspect(v, content="hello")
    Err(_) => fail("expected Ok")
  }
}

///|
test "max_length — rejects when too long" {
  let chain = Filter::max_length(5)
  let result : Result[String, _] = try? (chain.run)("hello!")
  inspect(result is Err(_), content="true")
}

// --- trim_start ---

///|
test "trim_start — removes leading whitespace" {
  let chain = Filter::trim_start()
  let result : Result[String, _] = try? (chain.run)("  hello  ")
  match result {
    Ok(v) => inspect(v, content="hello  ")
    Err(_) => fail("expected Ok")
  }
}

// --- trim_end ---

///|
test "trim_end — removes trailing whitespace" {
  let chain = Filter::trim_end()
  let result : Result[String, _] = try? (chain.run)("  hello  ")
  match result {
    Ok(v) => inspect(v, content="  hello")
    Err(_) => fail("expected Ok")
  }
}

// --- replace ---

///|
test "replace — replaces first occurrence" {
  let chain = Filter::replace("o", "0")
  let result : Result[String, _] = try? (chain.run)("foobar")
  match result {
    Ok(v) => inspect(v, content="f0obar")
    Err(_) => fail("expected Ok")
  }
}

// --- replace_all ---

///|
test "replace_all — replaces all occurrences" {
  let chain = Filter::replace_all("o", "0")
  let result : Result[String, _] = try? (chain.run)("foobar")
  match result {
    Ok(v) => inspect(v, content="f00bar")
    Err(_) => fail("expected Ok")
  }
}

// --- regex_match ---

///|
test "regex_match — passes when pattern matches" {
  let chain = Filter::regex_match("[[:digit:]]+")
  let result : Result[String, _] = try? (chain.run)("abc123def")
  match result {
    Ok(v) => inspect(v, content="abc123def")
    Err(_) => fail("expected Ok")
  }
}

///|
test "regex_match — rejects when pattern does not match" {
  let chain = Filter::regex_match("^[[:digit:]]+$")
  let result : Result[String, _] = try? (chain.run)("abc")
  inspect(result is Err(_), content="true")
}

///|
test "regex_match — full match with anchors" {
  let chain = Filter::regex_match("^[[:alpha:]]+$")
  let result : Result[String, _] = try? (chain.run)("hello")
  match result {
    Ok(v) => inspect(v, content="hello")
    Err(_) => fail("expected Ok")
  }
}

// --- regex_replace ---

///|
test "regex_replace — replaces all matches" {
  let chain = Filter::regex_replace("[[:digit:]]+", "NUM")
  let result : Result[String, _] = try? (chain.run)("a12b3c")
  match result {
    Ok(v) => inspect(v, content="aNUMbNUMc")
    Err(_) => fail("expected Ok")
  }
}

///|
test "regex_replace — no match returns original" {
  let chain = Filter::regex_replace("[[:digit:]]+", "NUM")
  let result : Result[String, _] = try? (chain.run)("abc")
  match result {
    Ok(v) => inspect(v, content="abc")
    Err(_) => fail("expected Ok")
  }
}

// --- regex_split ---

///|
test "regex_split — splits by pattern" {
  let chain = Filter::regex_split("[,;]+")
  let result : Result[Array[String], _] = try? (chain.run)("a,b;;c")
  match result {
    Ok(v) => inspect(v, content="[\"a\", \"b\", \"c\"]")
    Err(_) => fail("expected Ok")
  }
}

///|
test "regex_split — no match returns single element" {
  let chain = Filter::regex_split("[,;]+")
  let result : Result[Array[String], _] = try? (chain.run)("abc")
  match result {
    Ok(v) => inspect(v, content="[\"abc\"]")
    Err(_) => fail("expected Ok")
  }
}

// --- parse_bool ---

///|
test "parse_bool — true" {
  let chain = Filter::parse_bool()
  let result : Result[Bool, _] = try? (chain.run)("true")
  match result {
    Ok(v) => inspect(v, content="true")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_bool — false" {
  let chain = Filter::parse_bool()
  let result : Result[Bool, _] = try? (chain.run)("false")
  match result {
    Ok(v) => inspect(v, content="false")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_bool — 1" {
  let chain = Filter::parse_bool()
  let result : Result[Bool, _] = try? (chain.run)("1")
  match result {
    Ok(v) => inspect(v, content="true")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_bool — 0" {
  let chain = Filter::parse_bool()
  let result : Result[Bool, _] = try? (chain.run)("0")
  match result {
    Ok(v) => inspect(v, content="false")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_bool — case insensitive" {
  let chain = Filter::parse_bool()
  let result : Result[Bool, _] = try? (chain.run)("TRUE")
  match result {
    Ok(v) => inspect(v, content="true")
    Err(_) => fail("expected Ok")
  }
}

///|
test "parse_bool — invalid" {
  let chain = Filter::parse_bool()
  let result : Result[Bool, _] = try? (chain.run)("maybe")
  inspect(result is Err(_), content="true")
}

// --- float_in_range ---

///|
test "float_in_range — within range" {
  let chain = Filter::float_in_range(0.0, 1.0)
  let result : Result[Double, _] = try? (chain.run)(0.5)
  match result {
    Ok(v) => inspect(v, content="0.5")
    Err(_) => fail("expected Ok")
  }
}

///|
test "float_in_range — at boundaries" {
  let chain = Filter::float_in_range(0.0, 1.0)
  let r1 : Result[Double, _] = try? (chain.run)(0.0)
  inspect(r1 is Ok(_), content="true")
  let r2 : Result[Double, _] = try? (chain.run)(1.0)
  inspect(r2 is Ok(_), content="true")
}

///|
test "float_in_range — out of range" {
  let chain = Filter::float_in_range(0.0, 1.0)
  let result : Result[Double, _] = try? (chain.run)(1.5)
  inspect(result is Err(_), content="true")
}

///|
test "float_in_range — rejects NaN" {
  let chain = Filter::float_in_range(0.0, 1.0)
  let nan = 0.0 / 0.0
  let result : Result[Double, _] = try? (chain.run)(nan)
  inspect(result is Err(_), content="true")
}

// --- positive ---

///|
test "positive — passes positive" {
  let chain = Filter::positive()
  let result : Result[Int, _] = try? (chain.run)(1)
  match result {
    Ok(v) => inspect(v, content="1")
    Err(_) => fail("expected Ok")
  }
}

///|
test "positive — rejects zero" {
  let chain = Filter::positive()
  let result : Result[Int, _] = try? (chain.run)(0)
  inspect(result is Err(_), content="true")
}

///|
test "positive — rejects negative" {
  let chain = Filter::positive()
  let result : Result[Int, _] = try? (chain.run)(-1)
  inspect(result is Err(_), content="true")
}

// --- non_negative ---

///|
test "non_negative — passes zero" {
  let chain = Filter::non_negative()
  let result : Result[Int, _] = try? (chain.run)(0)
  match result {
    Ok(v) => inspect(v, content="0")
    Err(_) => fail("expected Ok")
  }
}

///|
test "non_negative — passes positive" {
  let chain = Filter::non_negative()
  let result : Result[Int, _] = try? (chain.run)(5)
  match result {
    Ok(v) => inspect(v, content="5")
    Err(_) => fail("expected Ok")
  }
}

///|
test "non_negative — rejects negative" {
  let chain = Filter::non_negative()
  let result : Result[Int, _] = try? (chain.run)(-1)
  inspect(result is Err(_), content="true")
}

// --- clamp ---

///|
test "clamp — within range unchanged" {
  let chain = Filter::clamp(0, 10)
  let result : Result[Int, _] = try? (chain.run)(5)
  match result {
    Ok(v) => inspect(v, content="5")
    Err(_) => fail("expected Ok")
  }
}

///|
test "clamp — below min clamped" {
  let chain = Filter::clamp(0, 10)
  let result : Result[Int, _] = try? (chain.run)(-5)
  match result {
    Ok(v) => inspect(v, content="0")
    Err(_) => fail("expected Ok")
  }
}

///|
test "clamp — above max clamped" {
  let chain = Filter::clamp(0, 10)
  let result : Result[Int, _] = try? (chain.run)(15)
  match result {
    Ok(v) => inspect(v, content="10")
    Err(_) => fail("expected Ok")
  }
}

// --- min_codepoints ---

///|
test "min_codepoints — passes ASCII" {
  let chain = Filter::min_codepoints(3)
  let result : Result[String, _] = try? (chain.run)("abc")
  match result {
    Ok(v) => inspect(v, content="abc")
    Err(_) => fail("expected Ok")
  }
}

///|
test "min_codepoints — rejects too short" {
  let chain = Filter::min_codepoints(3)
  let result : Result[String, _] = try? (chain.run)("ab")
  inspect(result is Err(_), content="true")
}

///|
test "min_codepoints — counts emoji as 1 codepoint" {
  // 🎉 = 1 codepoint (U+1F389) but 2 UTF-16 code units
  let chain = Filter::min_codepoints(2)
  let result : Result[String, _] = try? (chain.run)("a\u{1F389}")
  match result {
    Ok(v) => inspect(v, content="a\u{1F389}")
    Err(_) => fail("expected Ok: emoji is 1 codepoint + a = 2 codepoints")
  }
}

///|
test "min_codepoints — emoji counted correctly vs min_length" {
  // "🎉" has char_length()=1 but length()=2
  // min_codepoints(2) should reject single emoji
  let chain = Filter::min_codepoints(2)
  let result : Result[String, _] = try? (chain.run)("\u{1F389}")
  inspect(result is Err(_), content="true")
}

// --- max_codepoints ---

///|
test "max_codepoints — passes short string" {
  let chain = Filter::max_codepoints(5)
  let result : Result[String, _] = try? (chain.run)("hello")
  match result {
    Ok(v) => inspect(v, content="hello")
    Err(_) => fail("expected Ok")
  }
}

///|
test "max_codepoints — rejects too long" {
  let chain = Filter::max_codepoints(5)
  let result : Result[String, _] = try? (chain.run)("hello!")
  inspect(result is Err(_), content="true")
}

///|
test "max_codepoints — emoji counted as 1" {
  // "a🎉b" = 3 codepoints, but length()=4 (UTF-16)
  let chain = Filter::max_codepoints(3)
  let result : Result[String, _] = try? (chain.run)("a\u{1F389}b")
  match result {
    Ok(v) => inspect(v, content="a\u{1F389}b")
    Err(_) => fail("expected Ok: 3 codepoints should pass max_codepoints(3)")
  }
}

// --- min_graphemes ---

///|
test "min_graphemes — passes ASCII" {
  let chain = Filter::min_graphemes(3)
  let result : Result[String, _] = try? (chain.run)("abc")
  match result {
    Ok(v) => inspect(v, content="abc")
    Err(_) => fail("expected Ok")
  }
}

///|
test "min_graphemes — rejects too short" {
  let chain = Filter::min_graphemes(3)
  let result : Result[String, _] = try? (chain.run)("ab")
  inspect(result is Err(_), content="true")
}

///|
test "min_graphemes — ZWJ sequence counts as 1 grapheme" {
  // 👨‍👩‍👧 = U+1F468 U+200D U+1F469 U+200D U+1F467 = 1 grapheme cluster
  // but 5 codepoints and 11 UTF-16 code units
  let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
  let chain = Filter::min_graphemes(2)
  // "a" + family = 2 graphemes
  let result : Result[String, _] = try? (chain.run)("a" + family)
  match result {
    Ok(_) => () // pass
    Err(_) => fail("expected Ok: 'a' + family emoji = 2 graphemes")
  }
}

///|
test "min_graphemes — ZWJ emoji alone is 1 grapheme" {
  let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
  let chain = Filter::min_graphemes(2)
  let result : Result[String, _] = try? (chain.run)(family)
  inspect(result is Err(_), content="true")
}

// --- max_graphemes ---

///|
test "max_graphemes — passes short string" {
  let chain = Filter::max_graphemes(5)
  let result : Result[String, _] = try? (chain.run)("hello")
  match result {
    Ok(v) => inspect(v, content="hello")
    Err(_) => fail("expected Ok")
  }
}

///|
test "max_graphemes — rejects too long" {
  let chain = Filter::max_graphemes(5)
  let result : Result[String, _] = try? (chain.run)("hello!")
  inspect(result is Err(_), content="true")
}

///|
test "max_graphemes — flag emoji is 1 grapheme" {
  // 🇯🇵 = U+1F1EF U+1F1F5 = 1 grapheme, 2 codepoints, 4 UTF-16
  let flag = "\u{1F1EF}\u{1F1F5}"
  let chain = Filter::max_graphemes(2)
  // "a" + 🇯🇵 = 2 graphemes
  let result : Result[String, _] = try? (chain.run)("a" + flag)
  match result {
    Ok(_) => () // pass
    Err(_) => fail("expected Ok: 'a' + flag = 2 graphemes")
  }
}

///|
test "max_graphemes — skin tone emoji is 1 grapheme" {
  // 👋🏽 = U+1F44B U+1F3FD = 1 grapheme, 2 codepoints
  let wave = "\u{1F44B}\u{1F3FD}"
  let chain = Filter::max_graphemes(1)
  let result : Result[String, _] = try? (chain.run)(wave)
  match result {
    Ok(_) => () // pass
    Err(_) => fail("expected Ok: skin tone emoji = 1 grapheme")
  }
}
