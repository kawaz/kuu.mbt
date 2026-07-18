// registry.mbt — explicit extension inventory assembled by the front-door package.

///|
/// Registered node, matcher, and type resident families. Each identity is unique
/// within its category; duplicate registration is rejected and never overwrites.
pub struct Registry {
  priv nodes : Map[String, &NodeExt]
  priv matchers : Map[String, &MatcherExt]
  priv types : Map[String, &TypeExt]
  priv accumulators : Map[String, &AccumulatorExt]
  priv collectors : Map[String, &CollectorExt]
  priv filters : Map[String, FilterDescriptor]
  priv array_filters : Map[String, ArrayFilterDescriptor]
  priv installers : Array[&InstallerExt]
}

///|
pub fn Registry::new() -> Registry {
  {
    nodes: Map([]),
    matchers: Map([]),
    types: Map([]),
    accumulators: Map([]),
    collectors: Map([]),
    filters: Map([]),
    array_filters: Map([]),
    installers: [],
  }
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

///|
/// Register one accumulator resident. Returns false when the kind is already owned.
pub fn Registry::register_accumulator(
  self : Registry,
  resident : &AccumulatorExt,
) -> Bool {
  let kind = resident.kind()
  if self.accumulators.get(kind) is Some(_) {
    false
  } else {
    self.accumulators.set(kind, resident)
    true
  }
}

///|
pub fn Registry::lookup_accumulator(
  self : Registry,
  kind : String,
) -> &AccumulatorExt? {
  self.accumulators.get(kind)
}

///|
/// Register one collector resident. Returns false when the kind is already owned.
pub fn Registry::register_collector(
  self : Registry,
  resident : &CollectorExt,
) -> Bool {
  let kind = resident.kind()
  if self.collectors.get(kind) is Some(_) {
    false
  } else {
    self.collectors.set(kind, resident)
    true
  }
}

///|
pub fn Registry::lookup_collector(
  self : Registry,
  kind : String,
) -> &CollectorExt? {
  self.collectors.get(kind)
}

///|
/// Register one scalar filter resident. Returns false when the name is already owned.
pub fn Registry::register_filter(
  self : Registry,
  resident : FilterDescriptor,
) -> Bool {
  if self.filters.get(resident.name) is Some(_) {
    false
  } else {
    self.filters.set(resident.name, resident)
    true
  }
}

///|
pub fn Registry::lookup_filter(
  self : Registry,
  name : String,
) -> FilterDescriptor? {
  self.filters.get(name)
}

///|
/// Register one whole-array filter resident. Returns false when the name is already owned.
pub fn Registry::register_array_filter(
  self : Registry,
  resident : ArrayFilterDescriptor,
) -> Bool {
  if self.array_filters.get(resident.name) is Some(_) {
    false
  } else {
    self.array_filters.set(resident.name, resident)
    true
  }
}

///|
pub fn Registry::lookup_array_filter(
  self : Registry,
  name : String,
) -> ArrayFilterDescriptor? {
  self.array_filters.get(name)
}

///|
/// Register one installer resident. Overlapping vocabulary is retained so the
/// generic definition check can report every intersection instead of hiding it.
pub fn Registry::register_installer(
  self : Registry,
  resident : &InstallerExt,
) -> Unit {
  self.installers.push(resident)
}

///|
pub fn Registry::installers(self : Registry) -> Array[&InstallerExt] {
  self.installers
}
