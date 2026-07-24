///|
test "DR-068 §4: top-level $schema string is accepted as an inert annotation" {
  let definition = @json.parse(
    "{\"$schema\":\"https://kuu.kawaz.org/schema/wire.schema.json\",\"positionals\":[{\"name\":\"x\",\"type\":\"string\"}]}",
  )
  match parse_definition(definition) {
    Ok(ast) => {
      assert_eq(ast.declaration.positionals.length(), 1)
      assert_eq(ast.declaration.positionals[0].name, "x")
    }
    Err(_) => fail("top-level $schema string must be accepted")
  }
}

///|
test "DR-068 §4: element-level $schema remains unknown vocabulary" {
  let definition = @json.parse(
    "{\"positionals\":[{\"name\":\"x\",\"type\":\"string\",\"$schema\":\"https://kuu.kawaz.org/schema/wire.schema.json\"}]}",
  )
  match parse_definition(definition) {
    Err(Malformed(reason)) =>
      assert_true(reason.contains("unsupported key '$schema'"))
    _ => fail("element-level $schema must remain unknown vocabulary")
  }
}

///|
test "DR-068 §4: top-level $schema must be a string" {
  let definition = @json.parse("{\"$schema\":true}")
  match parse_definition(definition) {
    Err(Malformed(reason)) =>
      assert_true(reason.contains("definition '$schema' is not a string"))
    _ => fail("non-string top-level $schema must be rejected")
  }
}
