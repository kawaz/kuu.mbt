// fn_ctx.mbt — universal-fn context ABI shared by cell fns and filters.

///|
/// Default-phase target and its observes-gated option dependency capability.
pub struct DefaultCtx {
  priv target_ : String
  priv dependency_ : (String) -> Value?
}

///|
pub fn DefaultCtx::target(self : DefaultCtx) -> String {
  self.target_
}

///|
pub fn DefaultCtx::dependency(self : DefaultCtx, name : String) -> Value? {
  (self.dependency_)(name)
}

///|
/// Effect-phase target and the trigger that fired it.
pub struct EffectCtx {
  priv target_ : String
  priv trigger_ : String
}

///|
pub fn EffectCtx::target(self : EffectCtx) -> String {
  self.target_
}

///|
pub fn EffectCtx::trigger(self : EffectCtx) -> String {
  self.trigger_
}

///|
/// A filter specialization may carry either one scalar value or the accumulated
/// array consumed by an array-filter resident.
pub(all) enum FilterInput {
  Scalar(Value)
  Array(Array[Value])
} derive(Eq, Debug)

///|
pub struct FilterCtx {
  priv input_ : FilterInput
}

///|
pub fn FilterCtx::input(self : FilterCtx) -> FilterInput {
  self.input_
}

///|
priv enum FnPhase {
  DefaultPhase(DefaultCtx)
  EffectPhase(EffectCtx)
  FilterPhase(FilterCtx)
}

///|
/// Unified invocation context. Runtime lookups are capability-restricted by
/// the concrete `observes` edges supplied by the definition layer.
pub struct FnCtx {
  priv phase : FnPhase
  priv old_ : Value?
  // DR-127 §3 / DR-131 §7: 「ctx.old を要する fn」の判定素材。descriptor は old 依存を宣言しない
  // (io_type 席が無い) ので、実行時に `old()` が参照されたかを記録し、値残余の空座への適用を
  // 呼び手 (cell_fold の効果適用) が Reject へ倒せるようにする。
  priv mut old_consulted_ : Bool
  priv observes_ : Array[String]
  priv option_ : (String) -> Value?
  priv env_ : (String) -> Value?
  priv system_ : (String) -> Value?
}

///|
fn observation_allowed(observes : Array[String], edge : String) -> Bool {
  observes.contains(edge)
}

///|
fn observed_value(
  observes : Array[String],
  prefix : String,
  key : String,
  provider : (String) -> Value?,
) -> Value? {
  if observation_allowed(observes, prefix + key) {
    provider(key)
  } else {
    None
  }
}

///|
fn make_fn_ctx(
  phase : FnPhase,
  old : Value?,
  observes : Array[String],
  option : (String) -> Value?,
  env : (String) -> Value?,
  system : (String) -> Value?,
) -> FnCtx {
  {
    phase,
    old_: old,
    old_consulted_: false,
    observes_: observes.copy(),
    option_: option,
    env_: env,
    system_: system,
  }
}

///|
pub fn FnCtx::for_default(
  target : String,
  old? : Value? = None,
  observes? : Array[String] = [],
  option? : (String) -> Value? = fn(_) { None },
  dependency? : ((String) -> Value?)? = None,
  env? : (String) -> Value? = fn(_) { None },
  system? : (String) -> Value? = fn(_) { None },
) -> FnCtx {
  let concrete = observes.copy()
  let dependency_provider = match dependency {
    Some(provider) => provider
    None => option
  }
  let dependency = fn(name) {
    observed_value(concrete, "option:", name, dependency_provider)
  }
  make_fn_ctx(
    DefaultPhase(DefaultCtx::{ target_: target, dependency_: dependency }),
    old,
    concrete,
    option,
    env,
    system,
  )
}

///|
pub fn FnCtx::for_effect(
  target : String,
  trigger : String,
  old? : Value? = None,
  observes? : Array[String] = [],
  option? : (String) -> Value? = fn(_) { None },
  env? : (String) -> Value? = fn(_) { None },
  system? : (String) -> Value? = fn(_) { None },
) -> FnCtx {
  make_fn_ctx(
    EffectPhase(EffectCtx::{ target_: target, trigger_: trigger }),
    old,
    observes,
    option,
    env,
    system,
  )
}

///|
pub fn fn_ctx_filter(
  input : FilterInput,
  old? : Value? = None,
  observes? : Array[String] = [],
  option? : (String) -> Value? = fn(_) { None },
  env? : (String) -> Value? = fn(_) { None },
  system? : (String) -> Value? = fn(_) { None },
) -> FnCtx {
  make_fn_ctx(
    FilterPhase(FilterCtx::{ input_: input }),
    old,
    observes,
    option,
    env,
    system,
  )
}

///|
pub fn FnCtx::as_default(self : FnCtx) -> DefaultCtx? {
  match self.phase {
    DefaultPhase(ctx) => Some(ctx)
    _ => None
  }
}

///|
pub fn FnCtx::as_effect(self : FnCtx) -> EffectCtx? {
  match self.phase {
    EffectPhase(ctx) => Some(ctx)
    _ => None
  }
}

///|
pub fn FnCtx::as_filter(self : FnCtx) -> FilterCtx? {
  match self.phase {
    FilterPhase(ctx) => Some(ctx)
    _ => None
  }
}

///|
pub fn FnCtx::old(self : FnCtx) -> Value? {
  self.old_consulted_ = true
  self.old_
}

///|
/// Whether the fn consulted `old()` during its run (DR-127 §3: a Value fn that
/// requires the seat's current value cannot apply to an empty value-space seat).
pub fn FnCtx::old_consulted(self : FnCtx) -> Bool {
  self.old_consulted_
}

///|
pub fn FnCtx::observes(self : FnCtx) -> Array[String] {
  self.observes_.copy()
}

///|
pub fn FnCtx::option(self : FnCtx, name : String) -> Value? {
  observed_value(self.observes_, "option:", name, self.option_)
}

///|
pub fn FnCtx::env(self : FnCtx, variable : String) -> Value? {
  observed_value(self.observes_, "env:", variable, self.env_)
}

///|
pub fn FnCtx::system(self : FnCtx, key : String) -> Value? {
  observed_value(self.observes_, "system:", key, self.system_)
}
