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
/// One scalar filter resident. Constructed exclusively through `filter_descriptor`,
/// which adapts a plain (Value, args) transformer to the universal args-plus-FnCtx
/// invocation ABI (`FilterCtx.input()` supplies the scalar value). Every failed invocation returns
/// `FnReason` with its DR-037 phase; piece-filter callers use that phase to choose Rejected or Held
/// without inspecting the open reason vocabulary. Private fields keep the two invocation shapes from
/// diverging (same posture as CellFnDescriptor).
pub struct FilterDescriptor {
  priv name_ : String
  priv signature_ : FilterSignature
  priv reasons_ : Array[String]
  priv observes_ : Array[String]
  priv run_ : (Array[String], FnCtx) -> Result[Value, FnReason]
}

///|
pub fn FilterDescriptor::name(self : Self) -> String {
  self.name_
}

///|
pub fn FilterDescriptor::signature(self : Self) -> FilterSignature {
  self.signature_
}

///|
pub fn FilterDescriptor::reasons(self : Self) -> Array[String] {
  self.reasons_
}

///|
pub fn FilterDescriptor::observes(self : Self) -> Array[String] {
  self.observes_
}

///|
/// Invoke through the universal ABI (chain runners build the FnCtx).
pub fn FilterDescriptor::invoke(
  self : Self,
  args : Array[String],
  ctx : FnCtx,
) -> Result[Value, FnReason] {
  (self.run_)(args, ctx)
}

///|
/// Adapt a scalar value transformer to the universal filter invocation ABI.
pub fn filter_descriptor(
  name : String,
  signature : FilterSignature,
  reasons : Array[String],
  run : (Value, Array[String]) -> Result[Value, FnReason],
  observes? : Array[String] = [],
) -> FilterDescriptor {
  {
    name_: name,
    signature_: signature,
    reasons_: reasons.copy(),
    observes_: observes.copy(),
    run_: fn(args, ctx) {
      match ctx.as_filter() {
        None =>
          Err({
            disposition: @abi.RecognizedButInvalid,
            reason: "filter_rejected",
            message: "filter invoked outside filter mode",
          })
        Some(filter_ctx) =>
          match filter_ctx.input() {
            Scalar(value) => run(value, args)
            Array(_) =>
              Err({
                disposition: @abi.RecognizedButInvalid,
                reason: "filter_rejected",
                message: "scalar filter received an array input",
              })
          }
      }
    },
  }
}

///|
/// One whole-array filter resident for the accumulated-value phase. Constructed
/// exclusively through `array_filter_descriptor` (same private-fields posture as
/// FilterDescriptor).
pub struct ArrayFilterDescriptor {
  priv name_ : String
  priv signature_ : FilterSignature
  priv reasons_ : Array[String]
  priv observes_ : Array[String]
  priv run_ : (Array[String], FnCtx) -> Result[Array[Value], FnReason]
}

///|
pub fn ArrayFilterDescriptor::name(self : Self) -> String {
  self.name_
}

///|
pub fn ArrayFilterDescriptor::signature(self : Self) -> FilterSignature {
  self.signature_
}

///|
pub fn ArrayFilterDescriptor::reasons(self : Self) -> Array[String] {
  self.reasons_
}

///|
pub fn ArrayFilterDescriptor::observes(self : Self) -> Array[String] {
  self.observes_
}

///|
/// Invoke through the universal ABI (chain runners build the FnCtx).
pub fn ArrayFilterDescriptor::invoke(
  self : Self,
  args : Array[String],
  ctx : FnCtx,
) -> Result[Array[Value], FnReason] {
  (self.run_)(args, ctx)
}

///|
/// Adapt an accumulated-array transformer to the universal filter invocation
/// ABI.
pub fn array_filter_descriptor(
  name : String,
  signature : FilterSignature,
  reasons : Array[String],
  run : (Array[Value], Array[String]) -> Result[Array[Value], FnReason],
  observes? : Array[String] = [],
) -> ArrayFilterDescriptor {
  {
    name_: name,
    signature_: signature,
    reasons_: reasons.copy(),
    observes_: observes.copy(),
    run_: fn(args, ctx) {
      match ctx.as_filter() {
        None =>
          Err({
            disposition: @abi.RecognizedButInvalid,
            reason: "filter_rejected",
            message: "filter invoked outside filter mode",
          })
        Some(filter_ctx) =>
          match filter_ctx.input() {
            Array(values) => run(values, args)
            Scalar(_) =>
              Err({
                disposition: @abi.RecognizedButInvalid,
                reason: "filter_rejected",
                message: "array filter received a scalar input",
              })
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
  chain : Array[FnInvocation],
  value : Value,
) -> Result[Value, FnReason] {
  if value is @abi.Null {
    return Ok(value)
  }
  let mut current = value
  for spelling in chain {
    match registry.lookup_filter(spelling.name) {
      None => ()
      Some(descriptor) => {
        let ctx = fn_ctx_filter(Scalar(current), observes=descriptor.observes())
        match descriptor.invoke(spelling.args, ctx) {
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
  chain : Array[FnInvocation],
  values : Array[Value],
) -> Result[Array[Value], FnReason] {
  let mut current = values
  for spelling in chain {
    match registry.lookup_array_filter(spelling.name) {
      None => ()
      Some(descriptor) => {
        let ctx = fn_ctx_filter(Array(current), observes=descriptor.observes())
        match descriptor.invoke(spelling.args, ctx) {
          Ok(next) => current = next
          Err(error) => return Err(error)
        }
      }
    }
  }
  Ok(current)
}

///|
/// Apply an accumulated-array filter chain while retaining the source of every surviving value.
/// Each output value is matched to the first unused equal input value, which preserves stable
/// duplicate elimination and arbitrary reordering. A filter that synthesizes a value has no source
/// seat in its input and is rejected instead of fabricating provenance.
pub fn apply_accum_filter_chain_with_sources(
  registry : Registry,
  chain : Array[FnInvocation],
  bindings : Array[Binding],
) -> Result[Array[Binding], FnReason] {
  let mut current = bindings
  for spelling in chain {
    let values : Array[Value] = []
    for binding in current {
      values.push(binding.value)
    }
    match registry.lookup_array_filter(spelling.name) {
      None => ()
      Some(descriptor) => {
        let ctx = fn_ctx_filter(Array(values), observes=descriptor.observes())
        let next_values = match descriptor.invoke(spelling.args, ctx) {
          Ok(next) => next
          Err(error) => return Err(error)
        }
        let used = Array::make(current.length(), false)
        let next : Array[Binding] = []
        for value in next_values {
          let mut found = -1
          for i in 0..<current.length() {
            if !used[i] && current[i].value == value {
              found = i
              break
            }
          }
          if found < 0 {
            return Err({
              disposition: @abi.RecognizedButInvalid,
              reason: "filter_rejected",
              message: "array filter synthesized a value without an input source seat",
            })
          }
          used[found] = true
          next.push(current[found])
        }
        current = next
      }
    }
  }
  Ok(current)
}

///|
/// Run the String-to-String piece phase through the scalar registry.
pub fn apply_piece_filters(
  registry : Registry,
  chain : Array[FnInvocation],
  raw : String,
) -> Result[String, FnReason] {
  match apply_filter_chain(registry, chain, String(raw)) {
    Ok(String(value)) => Ok(value)
    Ok(_) =>
      Err({
        disposition: @abi.RecognizedButInvalid,
        reason: "filter_rejected",
        message: "piece_filters chain returned a non-string value (String→String contract violation, filter-definition bug)",
      })
    Err(error) => Err(error)
  }
}
