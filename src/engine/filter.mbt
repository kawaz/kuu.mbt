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
/// invocation ABI (`FilterCtx.input()` supplies the scalar value) — private fields
/// keep the two shapes from diverging (same posture as CellFnDescriptor).
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
            reason: "filter_rejected",
            message: "filter invoked outside filter mode",
          })
        Some(filter_ctx) =>
          match filter_ctx.input() {
            Scalar(value) => run(value, args)
            Array(_) =>
              Err({
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
            reason: "filter_rejected",
            message: "filter invoked outside filter mode",
          })
        Some(filter_ctx) =>
          match filter_ctx.input() {
            Array(values) => run(values, args)
            Scalar(_) =>
              Err({
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
        reason: "filter_rejected",
        message: "piece_filters chain returned a non-string value (String→String contract violation, filter-definition bug)",
      })
    Err(error) => Err(error)
  }
}
