// fixture_residents_wbtest.mbt — DR-132 §2.1/§3 acceptance-contour pins for the `fixture/*`
// conformance residents. The conformance fixtures pin the residents through whole parses;
// these tests pin the parse_token contour itself (split rule determinism, reason folding).

///|
fn pin_render_value(value : @abi.Value) -> String {
  match value {
    @abi.Null => "null"
    @abi.Bool(b) => if b { "true" } else { "false" }
    @abi.Number(d) => {
      let i = d.to_int()
      if i.to_double() == d {
        i.to_string()
      } else {
        d.to_string()
      }
    }
    @abi.String(s) => "\"" + s + "\""
    @abi.Array(vs) => {
      let items : Array[String] = []
      for v in vs {
        items.push(pin_render_value(v))
      }
      "[" + items.join(",") + "]"
    }
    @abi.Object(kvs) => {
      let items : Array[String] = []
      for kv in kvs {
        items.push(kv.0 + "=" + pin_render_value(kv.1))
      }
      "{" + items.join(",") + "}"
    }
  }
}

///|
fn range_parse(token : String) -> String {
  match fixture_int_range_type().parse_token(token) {
    Ok(value) => pin_render_value(value)
    Err(fail) => "reject:" + fail.reason
  }
}

///|
/// DR-132 §2.1: the three accepted forms. Partial forms keep partial presence — the missing
/// field is absent from the raw output (DR-127 §3.1), not null (null-fill is the projection
/// layer's job, DR-130 §4.1).
test "DR-132 §2.1: A..B / A.. / ..B の 3 形と部分 presence" {
  assert_eq(range_parse("5..9"), "{start=5,end=9}")
  assert_eq(range_parse("5.."), "{start=5}")
  assert_eq(range_parse("..9"), "{end=9}")
  assert_eq(range_parse("-5..-3"), "{start=-5,end=-3}")
}

///|
/// DR-132 §2.1: the split is a surface rule — first `..`, split once, no backtracking.
/// `1.0..2` splits after `1.0` (an integer-valued int spelling, DR-075); `1...2` splits to
/// A=`1` / B=`.2` and rejects without trying the A=`1.` / B=`2` alternative.
test "DR-132 §2.1: 最初の .. で 1 回だけ分割、バックトラックしない" {
  assert_eq(range_parse("1.0..2"), "{start=1,end=2}")
  assert_eq(range_parse("1...2"), "reject:not_an_int_range")
}

///|
/// DR-132 §2.1/§2.2: every non-range spelling — no `..` (including a bare int), `..` alone,
/// or a constituent outside the int contour — folds into the single reason
/// `not_an_int_range` (the number_parser not_a_number practice).
test "DR-132 §2.1: range 形に読めない綴りは全て not_an_int_range" {
  assert_eq(range_parse("5"), "reject:not_an_int_range")
  assert_eq(range_parse(".."), "reject:not_an_int_range")
  assert_eq(range_parse("1.5..2"), "reject:not_an_int_range")
  assert_eq(range_parse("x..2"), "reject:not_an_int_range")
  assert_eq(range_parse(""), "reject:not_an_int_range")
}

///|
fn json_parse_pin(token : String) -> String {
  match fixture_json_type().parse_token(token) {
    Ok(value) => pin_render_value(value)
    Err(fail) => "reject:" + fail.reason
  }
}

///|
/// DR-132 §3: one token read as RFC 8259 JSON, value returned verbatim; non-JSON is not_json.
test "DR-132 §3: fixture/json は JSON 値をそのまま返し、非 JSON は not_json" {
  assert_eq(json_parse_pin("{\"k\":1}"), "{k=1}")
  assert_eq(json_parse_pin("[1,\"a\",null]"), "[1,\"a\",null]")
  assert_eq(json_parse_pin("true"), "true")
  assert_eq(json_parse_pin("null"), "null")
  assert_eq(json_parse_pin("not json"), "reject:not_json")
}
