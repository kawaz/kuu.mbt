// completion_tiebreak_wbtest.mbt — DR-117 §2.1 multi-entry tie-break regression.
//
// When several public entries link to the internal `#completion_script` cell (option + option,
// option + positional, etc.), the winning shell string must be the CLI-order last-fire
// (DR-117 §2.1 "複数指定は string 全体セルの last-wins"; the `last` derives from DR-041 token
// reading semantics + DR-015 last-wins inheritance via DR-113 §2.3).
//
// Pre-fix (before dispatch consulted `at_pos`), `apply_entity_links` emitted linked copies in
// entity declaration order, so dispatch's forward-iterate-with-overwrite resolved to the last-
// DECLARED entity, not the last-FIRED one. These fixtures pin the reading-order winner and would
// have failed under the pre-fix behaviour (see docs/issue/2026-07-23-completion-script-multi-
// entry-tiebreak-undecided.md).

///|
test "DR-117 §2.1: two root options — CLI-order last-wins (forward argv)" {
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"a\",\"type\":\"completion_script\",\"long\":true},{\"name\":\"b\",\"type\":\"completion_script\",\"long\":true}]}",
  )
  let ast = match parse_definition(definition) {
    Ok(ast) => ast
    Err(_) => fail("definition must lower")
  }
  let args = ["--a", "zsh", "--b", "bash"]
  let outcome = test_resolve(ast, args)
  assert_eq(
    dispatch_completion_script(canonical_registry(), outcome),
    Requested("bash"),
  )
}

///|
test "DR-117 §2.1: two root options — CLI-order wins over declaration order (reversed argv)" {
  // `a` is declared first, `b` is declared second. Pre-fix would return `b`'s value regardless
  // of argv (declaration-order last-wins). Post-fix returns the CLI-latest fire.
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"a\",\"type\":\"completion_script\",\"long\":true},{\"name\":\"b\",\"type\":\"completion_script\",\"long\":true}]}",
  )
  let ast = match parse_definition(definition) {
    Ok(ast) => ast
    Err(_) => fail("definition must lower")
  }
  let args = ["--b", "bash", "--a", "zsh"]
  let outcome = test_resolve(ast, args)
  assert_eq(
    dispatch_completion_script(canonical_registry(), outcome),
    Requested("zsh"),
  )
}

///|
test "DR-117 §2.1: declaration order does not affect winner (decl [b,a], argv --a zsh --b bash)" {
  // With declaration reversed to [b,a], pre-fix would return `a`'s value (last-declared) —
  // "zsh". Post-fix returns the CLI-latest fire — "bash".
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"b\",\"type\":\"completion_script\",\"long\":true},{\"name\":\"a\",\"type\":\"completion_script\",\"long\":true}]}",
  )
  let ast = match parse_definition(definition) {
    Ok(ast) => ast
    Err(_) => fail("definition must lower")
  }
  let args = ["--a", "zsh", "--b", "bash"]
  let outcome = test_resolve(ast, args)
  assert_eq(
    dispatch_completion_script(canonical_registry(), outcome),
    Requested("bash"),
  )
}
