// test_helpers_wbtest.mbt — assembly whitebox helpers shared across test files.

///|
fn chain(spellings : Array[String]) -> Array[@engine.FilterSpelling] {
  let out : Array[@engine.FilterSpelling] = []
  for spelling in spellings {
    out.push(@builtins.parse_filter_shorthand(spelling))
  }
  out
}

///|
fn node_is_deprecation_mark(node : @engine.Node) -> Bool {
  node is @engine.Ext(extension) && extension.kind() == "builtin/deprecation"
}
