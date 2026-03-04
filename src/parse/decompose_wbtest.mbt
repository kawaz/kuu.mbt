///|
test "decompose_long: --port=8080 → (\"port\", Some(\"8080\"))" {
  let (name, value) = decompose_long("--port=8080")
  assert_eq(name, "port")
  assert_eq(value, Some("8080"))
}

///|
test "decompose_long: --verbose → (\"verbose\", None)" {
  let (name, value) = decompose_long("--verbose")
  assert_eq(name, "verbose")
  assert_eq(value, None)
}

///|
test "decompose_long: --port= → (\"port\", Some(\"\"))" {
  let (name, value) = decompose_long("--port=")
  assert_eq(name, "port")
  assert_eq(value, Some(""))
}

///|
test "decompose_long: --key=val=ue → (\"key\", Some(\"val=ue\"))" {
  let (name, value) = decompose_long("--key=val=ue")
  assert_eq(name, "key")
  assert_eq(value, Some("val=ue"))
}

///|
test "decompose_short: -abc → ['a', 'b', 'c']" {
  let chars = decompose_short("-abc")
  assert_eq(chars, ['a', 'b', 'c'])
}

///|
test "decompose_short: -v → ['v']" {
  let chars = decompose_short("-v")
  assert_eq(chars, ['v'])
}
