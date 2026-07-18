// node_ext_helpers.mbt — engine-side interpretation of the NodeExt contract.

///|
fn node_resident_name(node : Node) -> String? {
  guard node is Ext(extension) else { return None }
  extension.element_name()
}

///|
fn node_is_failure_mark(node : Node) -> Bool {
  node is Ext(extension) && extension.is_failure_action()
}

///|
fn node_effect_mark(node : Node) -> (String, EffectOp)? {
  guard node is Ext(extension) else { return None }
  extension.effect_mark()
}

///|
fn node_consumes_zero_tokens(node : Node) -> Bool {
  match node {
    Bind(_, _) => true
    Ext(extension) => extension.consumes_zero_tokens()
    _ => false
  }
}
