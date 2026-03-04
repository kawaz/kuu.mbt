///|
test "Kind equality" {
  assert_eq(Kind::Option, Kind::Option)
  assert_not_eq(Kind::Option, Kind::Command)
}

///|
test "ReduceAction variants" {
  assert_eq(ReduceAction::Value(None), ReduceAction::Value(None))
  assert_eq(
    ReduceAction::Value(Some("test")),
    ReduceAction::Value(Some("test")),
  )
  assert_not_eq(ReduceAction::Value(None), ReduceAction::Negate)
}

///|
test "InitialValue Val" {
  let iv : InitialValue[Int] = Val(42)
  match iv {
    Val(v) => assert_eq(v, 42)
    Thunk(_) => fail("expected Val")
  }
}

///|
test "InitialValue Thunk" {
  let iv : InitialValue[Int] = Thunk(fn() { 42 })
  match iv {
    Val(_) => fail("expected Thunk")
    Thunk(f) => assert_eq(f(), 42)
  }
}

///|
test "Visibility variants" {
  assert_eq(Visibility::Visible, Visibility::Visible)
  assert_not_eq(Visibility::Visible, Visibility::Hidden)
}

///|
test "ValueSource variants" {
  assert_eq(ValueSource::Initial, ValueSource::Initial)
  assert_eq(ValueSource::Default("config"), ValueSource::Default("config"))
  assert_not_eq(ValueSource::Initial, ValueSource::CommandLine)
}

///|
test "ErrorKind variants" {
  assert_eq(ErrorKind::UnknownOption, ErrorKind::UnknownOption)
  assert_not_eq(ErrorKind::UnknownOption, ErrorKind::InvalidValue)
}

///|
test "ParseError Usage" {
  let err = ParseError::Usage(ErrorKind::UnknownOption, "--foo", ErrorContext::{ option_name: "" })
  match err {
    Usage(kind, msg, _) => {
      assert_eq(kind, ErrorKind::UnknownOption)
      assert_eq(msg, "--foo")
    }
    _ => fail("expected Usage")
  }
}

///|
test "Parser new" {
  let p = Parser::new()
  assert_eq(p.seq, 0)
}

///|
test "Parser next_id" {
  let p = Parser::new()
  assert_eq(p.next_id(), 1)
  assert_eq(p.next_id(), 2)
  assert_eq(p.next_id(), 3)
}

///|
test "FlagInversion variants" {
  assert_eq(FlagInversion::No, FlagInversion::No)
  assert_eq(
    FlagInversion::Custom("with", "without"),
    FlagInversion::Custom("with", "without"),
  )
}

///|
test "OptMeta default-like construction" {
  let meta = OptMeta::{
    name: "port",
    kind: Kind::Option,
    help: "Port number",
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "PORT",
    required: false,
    visibility: Visibility::Visible,
    global: false,
    greedy: false,
  }
  assert_eq(meta.name, "port")
  assert_eq(meta.kind, Kind::Option)
}
