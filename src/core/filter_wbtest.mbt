///|
test "Filter::map — pure transformation" {
  let chain = Filter::map(fn(s : String) { s.length() })
  try (chain.run)("hello") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="5")
  }
}

///|
test "Filter::validate — success passes value through" {
  let chain = Filter::validate(fn(s : String) raise ParseError {
    if s.is_empty() {
      raise parse_error("must not be empty")
    }
  })
  try (chain.run)("ok") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"ok"
        ),
      )
  }
}

///|
test "Filter::validate — failure raises ParseError" {
  let chain = Filter::validate(fn(s : String) raise ParseError {
    if s.is_empty() {
      raise parse_error("must not be empty")
    }
  })
  try (chain.run)("") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "Filter::parse — successful conversion" {
  let chain = Filter::parse(fn(s : String) raise ParseError {
    try @string.parse_int(s.view()) catch {
      _ => raise parse_error("not an int")
    } noraise {
      v => v
    }
  })
  try (chain.run)("42") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="42")
  }
}

///|
test "Filter::parse — failure raises ParseError" {
  let chain = Filter::parse(fn(s : String) raise ParseError {
    try @string.parse_int(s.view()) catch {
      _ => raise parse_error("not an int")
    } noraise {
      v => v
    }
  })
  try (chain.run)("abc") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "then composition — trim then parse_int" {
  let chain = Filter::trim().then(Filter::parse_int())
  try (chain.run)("  42  ") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="42")
  }
}

///|
test "then type chain — trim then split then each(parse_int)" {
  let chain = Filter::trim()
    .then(Filter::split(","))
    .then(Filter::each(Filter::parse_int()))
  try (chain.run)(" 1,2,3 ") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="[1, 2, 3]")
  }
}

///|
test "trim — removes whitespace" {
  let chain = Filter::trim()
  try (chain.run)("  hello  ") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello"
        ),
      )
  }
}

///|
test "non_empty — passes non-empty string" {
  let chain = Filter::non_empty()
  try (chain.run)("ok") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"ok"
        ),
      )
  }
}

///|
test "non_empty — rejects empty string" {
  let chain = Filter::non_empty()
  try (chain.run)("") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "split — splits string by separator" {
  let chain = Filter::split(",")
  try (chain.run)("a,b,c") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|["a", "b", "c"]
        ),
      )
  }
}

///|
test "parse_int — valid integer" {
  let chain = Filter::parse_int()
  try (chain.run)("123") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="123")
  }
}

///|
test "parse_int — invalid integer" {
  let chain = Filter::parse_int()
  try (chain.run)("abc") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "parse_float — valid float" {
  let chain = Filter::parse_float()
  try (chain.run)("3.14") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="3.14")
  }
}

///|
test "parse_float — invalid float" {
  let chain = Filter::parse_float()
  try (chain.run)("abc") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "in_range — within range" {
  let chain = Filter::in_range(1, 10)
  try (chain.run)(5) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="5")
  }
}

///|
test "in_range — below range" {
  let chain = Filter::in_range(1, 10)
  try (chain.run)(0) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "in_range — above range" {
  let chain = Filter::in_range(1, 10)
  try (chain.run)(11) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "one_of — valid value" {
  let chain = Filter::one_of(["red", "green", "blue"])
  try (chain.run)("green") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"green"
        ),
      )
  }
}

///|
test "one_of — invalid value" {
  let chain = Filter::one_of(["red", "green", "blue"])
  try (chain.run)("yellow") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "one_of — error message uses join format" {
  let chain = Filter::one_of(["red", "green", "blue"])
  try (chain.run)("yellow") catch {
    ParseError(info) =>
      @debug.debug_inspect(
        info.message,
        content=(
          #|"value must be one of: red, green, blue"
        ),
      )
    _ => abort("expected ParseError")
  } noraise {
    _ => abort("expected ParseError")
  }
}

///|
test "each — applies filter to each element" {
  let chain = Filter::each(Filter::parse_int())
  try (chain.run)(["1", "2", "3"]) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="[1, 2, 3]")
  }
}

///|
test "each — propagates error from element" {
  let chain = Filter::each(Filter::parse_int())
  try (chain.run)(["1", "abc", "3"]) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "error propagation — chain stops at first error" {
  let chain = Filter::non_empty().then(Filter::parse_int())
  try (chain.run)("") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "to_lower — converts to lowercase" {
  let chain = Filter::to_lower()
  try (chain.run)("HELLO") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello"
        ),
      )
  }
}

///|
test "make_reducer — Value(Some(s)) applies pre and accumulates" {
  let pre = Filter::trim().then(Filter::parse_int())
  let accum : Accumulator[Int, Int] = (
    fn(cur, piece) { cur + piece } : Accumulator[_, _])
  let reducer = make_reducer(pre, accum)
  let ctx = ReduceCtx::{ current: 10, action: Value(Some("  5  ")) }
  try reducer(ctx) catch {
    _ => fail("expected Ok(Some(15))")
  } noraise {
    Some(v) => @debug.debug_inspect(v, content="15")
    None => fail("expected Ok(Some(15))")
  }
}

///|
test "make_reducer — Value(None) returns None" {
  let pre = Filter::parse_int()
  let accum : Accumulator[Int, Int] = (
    fn(cur, piece) { cur + piece } : Accumulator[_, _])
  let reducer = make_reducer(pre, accum)
  let ctx = ReduceCtx::{ current: 10, action: Value(None) }
  try reducer(ctx) catch {
    _ => fail("expected Ok(None)")
  } noraise {
    None => ()
    Some(_) => fail("expected Ok(None)")
  }
}

///|
test "make_reducer — pre error propagation" {
  let pre = Filter::parse_int()
  let accum : Accumulator[Int, Int] = (
    fn(cur, piece) { cur + piece } : Accumulator[_, _])
  let reducer = make_reducer(pre, accum)
  let ctx = ReduceCtx::{ current: 10, action: Value(Some("not_a_number")) }
  try reducer(ctx) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
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
  try reducer(ctx1) catch {
    _ => fail("expected Ok(Some(8080))")
  } noraise {
    Some(v) => @debug.debug_inspect(v, content="8080")
    None => fail("expected Ok(Some(8080))")
  }
  // Value out of range should error
  let ctx2 = ReduceCtx::{ current: 0, action: Value(Some("  99999  ")) }
  try reducer(ctx2) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "in_range at lower boundary" {
  let chain = Filter::in_range(1, 10)
  try (chain.run)(1) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="1")
  }
}

///|
test "in_range at upper boundary" {
  let chain = Filter::in_range(1, 10)
  try (chain.run)(10) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="10")
  }
}

// --- to_upper ---

///|
test "to_upper — converts to uppercase" {
  let chain = Filter::to_upper()
  try (chain.run)("hello") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"HELLO"
        ),
      )
  }
}

///|
test "to_upper — preserves non-alpha" {
  let chain = Filter::to_upper()
  try (chain.run)("abc-123") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"ABC-123"
        ),
      )
  }
}

// --- starts_with ---

///|
test "starts_with — passes matching prefix" {
  let chain = Filter::starts_with("http")
  try (chain.run)("https://example.com") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"https://example.com"
        ),
      )
  }
}

///|
test "starts_with — rejects non-matching prefix" {
  let chain = Filter::starts_with("http")
  try (chain.run)("ftp://example.com") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- ends_with ---

///|
test "ends_with — passes matching suffix" {
  let chain = Filter::ends_with(".json")
  try (chain.run)("config.json") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"config.json"
        ),
      )
  }
}

///|
test "ends_with — rejects non-matching suffix" {
  let chain = Filter::ends_with(".json")
  try (chain.run)("config.yaml") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- contains ---

///|
test "contains — passes when substring present" {
  let chain = Filter::contains("world")
  try (chain.run)("hello world") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello world"
        ),
      )
  }
}

///|
test "contains — rejects when substring absent" {
  let chain = Filter::contains("world")
  try (chain.run)("hello there") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- min_length ---

///|
test "min_length — passes when long enough" {
  let chain = Filter::min_length(3)
  try (chain.run)("abc") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"abc"
        ),
      )
  }
}

///|
test "min_length — rejects when too short" {
  let chain = Filter::min_length(3)
  try (chain.run)("ab") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- max_length ---

///|
test "max_length — passes when short enough" {
  let chain = Filter::max_length(5)
  try (chain.run)("hello") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello"
        ),
      )
  }
}

///|
test "max_length — rejects when too long" {
  let chain = Filter::max_length(5)
  try (chain.run)("hello!") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- trim_start ---

///|
test "trim_start — removes leading whitespace" {
  let chain = Filter::trim_start()
  try (chain.run)("  hello  ") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello  "
        ),
      )
  }
}

// --- trim_end ---

///|
test "trim_end — removes trailing whitespace" {
  let chain = Filter::trim_end()
  try (chain.run)("  hello  ") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"  hello"
        ),
      )
  }
}

// --- replace ---

///|
test "replace — replaces first occurrence" {
  let chain = Filter::replace("o", "0")
  try (chain.run)("foobar") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"f0obar"
        ),
      )
  }
}

// --- replace_all ---

///|
test "replace_all — replaces all occurrences" {
  let chain = Filter::replace_all("o", "0")
  try (chain.run)("foobar") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"f00bar"
        ),
      )
  }
}

// --- regex_match ---

///|
test "regex_match — passes when pattern matches" {
  let chain = Filter::regex_match("[[:digit:]]+")
  try (chain.run)("abc123def") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"abc123def"
        ),
      )
  }
}

///|
test "regex_match — rejects when pattern does not match" {
  let chain = Filter::regex_match("^[[:digit:]]+$")
  try (chain.run)("abc") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "regex_match — full match with anchors" {
  let chain = Filter::regex_match("^[[:alpha:]]+$")
  try (chain.run)("hello") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello"
        ),
      )
  }
}

// --- regex_replace ---

///|
test "regex_replace — replaces all matches" {
  let chain = Filter::regex_replace("[[:digit:]]+", "NUM")
  try (chain.run)("a12b3c") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"aNUMbNUMc"
        ),
      )
  }
}

///|
test "regex_replace — no match returns original" {
  let chain = Filter::regex_replace("[[:digit:]]+", "NUM")
  try (chain.run)("abc") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"abc"
        ),
      )
  }
}

// --- regex_split ---

///|
test "regex_split — splits by pattern" {
  let chain = Filter::regex_split("[,;]+")
  try (chain.run)("a,b;;c") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|["a", "b", "c"]
        ),
      )
  }
}

///|
test "regex_split — no match returns single element" {
  let chain = Filter::regex_split("[,;]+")
  try (chain.run)("abc") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|["abc"]
        ),
      )
  }
}

// --- parse_bool ---

///|
test "parse_bool — true" {
  let chain = Filter::parse_bool()
  try (chain.run)("true") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="true")
  }
}

///|
test "parse_bool — false" {
  let chain = Filter::parse_bool()
  try (chain.run)("false") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="false")
  }
}

///|
test "parse_bool — 1" {
  let chain = Filter::parse_bool()
  try (chain.run)("1") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="true")
  }
}

///|
test "parse_bool — 0" {
  let chain = Filter::parse_bool()
  try (chain.run)("0") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="false")
  }
}

///|
test "parse_bool — case insensitive" {
  let chain = Filter::parse_bool()
  try (chain.run)("TRUE") catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="true")
  }
}

///|
test "parse_bool — invalid" {
  let chain = Filter::parse_bool()
  try (chain.run)("maybe") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "parse_bool — t/on accepted as true" {
  let chain = Filter::parse_bool()
  try (chain.run)("t") catch {
    _ => fail("expected Ok for 't'")
  } noraise {
    v => @debug.debug_inspect(v, content="true")
  }
  try (chain.run)("on") catch {
    _ => fail("expected Ok for 'on'")
  } noraise {
    v => @debug.debug_inspect(v, content="true")
  }
}

///|
test "parse_bool — f/off accepted as false" {
  let chain = Filter::parse_bool()
  try (chain.run)("f") catch {
    _ => fail("expected Ok for 'f'")
  } noraise {
    v => @debug.debug_inspect(v, content="false")
  }
  try (chain.run)("off") catch {
    _ => fail("expected Ok for 'off'")
  } noraise {
    v => @debug.debug_inspect(v, content="false")
  }
}

// --- float_in_range ---

///|
test "float_in_range — within range" {
  let chain = Filter::float_in_range(0.0, 1.0)
  try (chain.run)(0.5) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="0.5")
  }
}

///|
test "float_in_range — at boundaries" {
  let chain = Filter::float_in_range(0.0, 1.0)
  try (chain.run)(0.0) catch {
    _ => fail("expected Ok at 0.0")
  } noraise {
    _ => ()
  }
  try (chain.run)(1.0) catch {
    _ => fail("expected Ok at 1.0")
  } noraise {
    _ => ()
  }
}

///|
test "float_in_range — out of range" {
  let chain = Filter::float_in_range(0.0, 1.0)
  try (chain.run)(1.5) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "float_in_range — rejects NaN" {
  let chain = Filter::float_in_range(0.0, 1.0)
  let nan = 0.0 / 0.0
  try (chain.run)(nan) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- positive ---

///|
test "positive — passes positive" {
  let chain = Filter::positive()
  try (chain.run)(1) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="1")
  }
}

///|
test "positive — rejects zero" {
  let chain = Filter::positive()
  try (chain.run)(0) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "positive — rejects negative" {
  let chain = Filter::positive()
  try (chain.run)(-1) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- non_negative ---

///|
test "non_negative — passes zero" {
  let chain = Filter::non_negative()
  try (chain.run)(0) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="0")
  }
}

///|
test "non_negative — passes positive" {
  let chain = Filter::non_negative()
  try (chain.run)(5) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="5")
  }
}

///|
test "non_negative — rejects negative" {
  let chain = Filter::non_negative()
  try (chain.run)(-1) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- clamp ---

///|
test "clamp — within range unchanged" {
  let chain = Filter::clamp(0, 10)
  try (chain.run)(5) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="5")
  }
}

///|
test "clamp — below min clamped" {
  let chain = Filter::clamp(0, 10)
  try (chain.run)(-5) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="0")
  }
}

///|
test "clamp — above max clamped" {
  let chain = Filter::clamp(0, 10)
  try (chain.run)(15) catch {
    _ => fail("expected Ok")
  } noraise {
    v => @debug.debug_inspect(v, content="10")
  }
}

// --- min_codepoints ---

///|
test "min_codepoints — passes ASCII" {
  let chain = Filter::min_codepoints(3)
  try (chain.run)("abc") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"abc"
        ),
      )
  }
}

///|
test "min_codepoints — rejects too short" {
  let chain = Filter::min_codepoints(3)
  try (chain.run)("ab") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "min_codepoints — counts emoji as 1 codepoint" {
  // 🎉 = 1 codepoint (U+1F389) but 2 UTF-16 code units
  let chain = Filter::min_codepoints(2)
  try (chain.run)("a\u{1F389}") catch {
    _ => fail("expected Ok: emoji is 1 codepoint + a = 2 codepoints")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"a🎉"
        ),
      )
  }
}

///|
test "min_codepoints — emoji counted correctly vs min_length" {
  // "🎉" has char_length()=1 but length()=2
  // min_codepoints(2) should reject single emoji
  let chain = Filter::min_codepoints(2)
  try (chain.run)("\u{1F389}") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- max_codepoints ---

///|
test "max_codepoints — passes short string" {
  let chain = Filter::max_codepoints(5)
  try (chain.run)("hello") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello"
        ),
      )
  }
}

///|
test "max_codepoints — rejects too long" {
  let chain = Filter::max_codepoints(5)
  try (chain.run)("hello!") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "max_codepoints — emoji counted as 1" {
  // "a🎉b" = 3 codepoints, but length()=4 (UTF-16)
  let chain = Filter::max_codepoints(3)
  try (chain.run)("a\u{1F389}b") catch {
    _ => fail("expected Ok: 3 codepoints should pass max_codepoints(3)")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"a🎉b"
        ),
      )
  }
}

// --- min_graphemes ---

///|
test "min_graphemes — passes ASCII" {
  let chain = Filter::min_graphemes(3)
  try (chain.run)("abc") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"abc"
        ),
      )
  }
}

///|
test "min_graphemes — rejects too short" {
  let chain = Filter::min_graphemes(3)
  try (chain.run)("ab") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "min_graphemes — ZWJ sequence counts as 1 grapheme" {
  // 👨‍👩‍👧 = U+1F468 U+200D U+1F469 U+200D U+1F467 = 1 grapheme cluster
  // but 5 codepoints and 11 UTF-16 code units
  let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
  let chain = Filter::min_graphemes(2)
  // "a" + family = 2 graphemes
  try (chain.run)("a" + family) catch {
    _ => fail("expected Ok: 'a' + family emoji = 2 graphemes")
  } noraise {
    _ => () // pass
  }
}

///|
test "min_graphemes — ZWJ emoji alone is 1 grapheme" {
  let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
  let chain = Filter::min_graphemes(2)
  try (chain.run)(family) catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

// --- max_graphemes ---

///|
test "max_graphemes — passes short string" {
  let chain = Filter::max_graphemes(5)
  try (chain.run)("hello") catch {
    _ => fail("expected Ok")
  } noraise {
    v =>
      @debug.debug_inspect(
        v,
        content=(
          #|"hello"
        ),
      )
  }
}

///|
test "max_graphemes — rejects too long" {
  let chain = Filter::max_graphemes(5)
  try (chain.run)("hello!") catch {
    _ => ()
  } noraise {
    _ => fail("expected raise")
  }
}

///|
test "max_graphemes — flag emoji is 1 grapheme" {
  // 🇯🇵 = U+1F1EF U+1F1F5 = 1 grapheme, 2 codepoints, 4 UTF-16
  let flag = "\u{1F1EF}\u{1F1F5}"
  let chain = Filter::max_graphemes(2)
  // "a" + 🇯🇵 = 2 graphemes
  try (chain.run)("a" + flag) catch {
    _ => fail("expected Ok: 'a' + flag = 2 graphemes")
  } noraise {
    _ => () // pass
  }
}

///|
test "max_graphemes — skin tone emoji is 1 grapheme" {
  // 👋🏽 = U+1F44B U+1F3FD = 1 grapheme, 2 codepoints
  let wave = "\u{1F44B}\u{1F3FD}"
  let chain = Filter::max_graphemes(1)
  try (chain.run)(wave) catch {
    _ => fail("expected Ok: skin tone emoji = 1 grapheme")
  } noraise {
    _ => () // pass
  }
}
