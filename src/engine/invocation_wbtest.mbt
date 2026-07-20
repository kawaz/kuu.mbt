// invocation_wbtest.mbt — universal invocation carrier parsing.

///|
test "colon-string and array forms decode to the same fn invocation" {
  let from_string = parse_fn_invocation(ColonString("in_range:1:10")).unwrap()
  let from_array = parse_fn_invocation(ArrayParts(["in_range", "1", "10"])).unwrap()
  assert_eq(from_string, from_array)
  assert_eq(from_string, { name: "in_range", args: ["1", "10"] })
  assert_eq(from_string.to_call(), {
    name: "in_range",
    args: [StringArg("1"), StringArg("10")],
  })
}

///|
test "typed internal calls preserve Value args without string serialization" {
  assert_eq(typed_fn_call("set", [Bool(true), Number(2.0)]), {
    name: "set",
    args: [ValueArg(Bool(true)), ValueArg(Number(2.0))],
  })
}

///|
test "array-form args preserve literal colons and reject a missing name part" {
  let invocation = parse_fn_invocation(
    ArrayParts(["regex_match", "https?://host:path"]),
  ).unwrap()
  assert_eq(invocation.name, "regex_match")
  assert_eq(invocation.args, ["https?://host:path"])
  assert_eq(
    parse_fn_invocation(ArrayParts([])),
    Err("fn invocation array must contain a name"),
  )
}
