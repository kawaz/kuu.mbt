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
/// One scalar filter resident. Invocation uses the universal args-plus-FnCtx
/// ABI; `FilterCtx.input()` supplies the scalar value.
pub(all) struct FilterDescriptor {
  name : String
  signature : FilterSignature
  reasons : Array[String]
  observes : Array[String]
  run : (Array[String], FnCtx) -> Result[Value, (String, String)]
}

///|
/// Adapt a scalar value transformer to the universal filter invocation ABI.
pub fn filter_descriptor(
  name : String,
  signature : FilterSignature,
  reasons : Array[String],
  run : (Value, Array[String]) -> Result[Value, (String, String)],
  observes? : Array[String] = [],
) -> FilterDescriptor {
  {
    name,
    signature,
    reasons: reasons.copy(),
    observes: observes.copy(),
    run: fn(args, ctx) {
      match ctx.as_filter() {
        None => Err(("filter_rejected", "filter invoked outside filter mode"))
        Some(filter_ctx) =>
          match filter_ctx.input() {
            ScalarInput(value) => run(value, args)
            ArrayInput(_) =>
              Err(("filter_rejected", "scalar filter received an array input"))
          }
      }
    },
  }
}

///|
/// One whole-array filter resident for the accumulated-value phase.
pub(all) struct ArrayFilterDescriptor {
  name : String
  signature : FilterSignature
  reasons : Array[String]
  observes : Array[String]
  run : (Array[String], FnCtx) -> Result[Array[Value], (String, String)]
}

///|
/// Adapt an accumulated-array transformer to the universal filter invocation
/// ABI.
pub fn array_filter_descriptor(
  name : String,
  signature : FilterSignature,
  reasons : Array[String],
  run : (Array[Value], Array[String]) -> Result[Array[Value], (String, String)],
  observes? : Array[String] = [],
) -> ArrayFilterDescriptor {
  {
    name,
    signature,
    reasons: reasons.copy(),
    observes: observes.copy(),
    run: fn(args, ctx) {
      match ctx.as_filter() {
        None => Err(("filter_rejected", "filter invoked outside filter mode"))
        Some(filter_ctx) =>
          match filter_ctx.input() {
            ArrayInput(values) => run(values, args)
            ScalarInput(_) =>
              Err(("filter_rejected", "array filter received a scalar input"))
          }
      }
    },
  }
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
      Some(descriptor) => {
        let ctx = fn_ctx_filter(
          ScalarInput(current),
          observes=descriptor.observes,
        )
        match (descriptor.run)(spelling.args, ctx) {
          Ok(next) => current = next
          Err(error) => return Err(error)
        }
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
      Some(descriptor) => {
        let ctx = fn_ctx_filter(
          ArrayInput(current),
          observes=descriptor.observes,
        )
        match (descriptor.run)(spelling.args, ctx) {
          Ok(next) => current = next
          Err(error) => return Err(error)
        }
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
  match apply_filter_chain(registry, chain, String(raw)) {
    Ok(String(value)) => Ok(value)
    Ok(_) =>
      Err(
        (
          "filter_rejected", "piece_filters chain returned a non-string value (String→String contract violation, filter-definition bug)",
        ),
      )
    Err(error) => Err(error)
  }
}
