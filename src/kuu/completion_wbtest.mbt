// completion_wbtest.mbt — DR-117 preset orchestration connection tests.

///|
test "DR-117 §2.4: completion_script preset populates the internal capability cell" {
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"completions\",\"type\":\"completion_script\",\"long\":true}]}",
  )
  let ast = match parse_definition(definition) {
    Ok(ast) => ast
    Err(_) => fail("completion_script definition must lower")
  }
  let outcome = resolve(ast, parse(ast, ["--completions", "zsh"]), [
    "--completions", "zsh",
  ])
  assert_eq(
    dispatch_completion_script(canonical_registry(), outcome),
    Requested("zsh"),
  )
}

///|
test "DR-117 §2.3: a command positional entrance links to the definition-wide root cell" {
  let definition = @json.parse(
    "{\"commands\":[{\"name\":\"completion\",\"positionals\":[{\"name\":\"shell\",\"type\":\"completion_script\"}]}]}",
  )
  let ast = match parse_definition(definition) {
    Ok(ast) => ast
    Err(_) => fail("positional completion_script definition must lower")
  }
  let args = ["completion", "fish"]
  let outcome = resolve(ast, parse(ast, args), args)
  assert_eq(
    dispatch_completion_script(canonical_registry(), outcome),
    Requested("fish"),
  )
}

///|
test "DR-117 §2.1: an env entrance populates the same internal capability cell" {
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"completions\",\"type\":\"completion_script\",\"env\":\"APP_COMPLETION\"}]}",
  )
  let ast = match parse_definition(definition) {
    Ok(ast) => ast
    Err(_) => fail("completion_script env definition must lower")
  }
  let outcome = resolve(
    ast,
    parse(ast, []),
    [],
    env=Map([("APP_COMPLETION", "bash")]),
  )
  assert_eq(
    dispatch_completion_script(canonical_registry(), outcome),
    Requested("bash"),
  )
}

///|
test "DR-117 capability dispatch distinguishes unavailable and unfired seats" {
  let empty_registry = @engine.Registry::new()
  assert_eq(
    dispatch_completion_script(empty_registry, @engine.Success([])),
    Unavailable,
  )
  assert_eq(
    dispatch_completion_script(canonical_registry(), @engine.Success([])),
    NotRequested,
  )
}
