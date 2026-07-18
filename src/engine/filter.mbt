// filter.mbt — open filter descriptors and registry-driven invocation.

///|
/// Whether a filter only validates its input or may return a replacement value.
pub(all) enum FilterSignature {
  Validate
  Transform
} derive(Eq, Debug)

///|
pub fn FilterSignature::is_transform(self : FilterSignature) -> Bool {
  self is Transform
}

///|
/// One scalar filter resident. `name` is its registry identity, `signature`
/// declares whether update variants may invoke it, and `reasons` is its
/// machine-readable failure vocabulary.
pub(all) struct FilterDescriptor {
  name : String
  signature : FilterSignature
  reasons : Array[String]
  run : (Value, Array[String]) -> Result[Value, (String, String)]
}

///|
/// One whole-array filter resident for the accumulated-value phase.
pub(all) struct ArrayFilterDescriptor {
  name : String
  signature : FilterSignature
  reasons : Array[String]
  run : (Array[Value], Array[String]) -> Result[Array[Value], (String, String)]
}

///|
/// Run a scalar filter chain in declaration order. Definition checking rejects
/// unknown names; the missing-name branch remains a defensive identity fallback.
pub fn apply_filter_chain(
  registry : Registry,
  chain : Array[FilterSpelling],
  value : Value,
) -> Result[Value, (String, String)] {
  let mut current = value
  for spelling in chain {
    match registry.lookup_filter(spelling.name) {
      None => ()
      Some(descriptor) =>
        match (descriptor.run)(current, spelling.args) {
          Ok(next) => current = next
          Err(error) => return Err(error)
        }
    }
  }
  Ok(current)
}

///|
/// Run a whole-array filter chain in declaration order.
pub fn apply_accum_filter_chain(
  registry : Registry,
  chain : Array[FilterSpelling],
  values : Array[Value],
) -> Result[Array[Value], (String, String)] {
  let mut current = values
  for spelling in chain {
    match registry.lookup_array_filter(spelling.name) {
      None => ()
      Some(descriptor) =>
        match (descriptor.run)(current, spelling.args) {
          Ok(next) => current = next
          Err(error) => return Err(error)
        }
    }
  }
  Ok(current)
}

///|
/// Run the String-to-String piece phase through the scalar registry.
pub fn apply_piece_filters(
  registry : Registry,
  chain : Array[FilterSpelling],
  raw : String,
) -> Result[String, (String, String)] {
  match apply_filter_chain(registry, chain, VStr(raw)) {
    Ok(VStr(value)) => Ok(value)
    Ok(_) =>
      Err(
        (
          "filter_rejected", "piece_filters chain returned a non-string value (String→String contract violation, filter-definition bug)",
        ),
      )
    Err(error) => Err(error)
  }
}
