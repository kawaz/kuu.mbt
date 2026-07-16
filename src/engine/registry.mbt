// registry.mbt — explicit extension inventory assembled by the front-door package.

///|
/// Registered node, matcher, and type resident families. Each identity is unique
/// within its category; duplicate registration is rejected and never overwrites.
pub struct Registry {
  priv nodes : Map[String, &NodeExt]
  priv matchers : Map[String, &MatcherExt]
  priv types : Map[String, &TypeExt]
}

///|
pub fn Registry::new() -> Registry {
  { nodes: Map([]), matchers: Map([]), types: Map([]) }
}

///|
/// Register one node resident family. Returns false when the kind is already owned.
pub fn Registry::register_node(self : Registry, resident : &NodeExt) -> Bool {
  let kind = resident.kind()
  if self.nodes.get(kind) is Some(_) {
    false
  } else {
    self.nodes.set(kind, resident)
    true
  }
}

///|
pub fn Registry::lookup_node(self : Registry, kind : String) -> &NodeExt? {
  self.nodes.get(kind)
}

///|
/// Register one matcher resident family. Returns false when the kind is already owned.
pub fn Registry::register_matcher(
  self : Registry,
  resident : &MatcherExt,
) -> Bool {
  let kind = resident.kind()
  if self.matchers.get(kind) is Some(_) {
    false
  } else {
    self.matchers.set(kind, resident)
    true
  }
}

///|
pub fn Registry::lookup_matcher(self : Registry, kind : String) -> &MatcherExt? {
  self.matchers.get(kind)
}

///|
/// Register one type resident family. Returns false when the name is already owned.
pub fn Registry::register_type(self : Registry, resident : &TypeExt) -> Bool {
  let name = resident.name()
  if self.types.get(name) is Some(_) {
    false
  } else {
    self.types.set(name, resident)
    true
  }
}

///|
pub fn Registry::lookup_type(self : Registry, name : String) -> &TypeExt? {
  self.types.get(name)
}
