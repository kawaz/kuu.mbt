// Stable front-door vocabulary. ABI types are re-exported without internal engine references.

///|
pub using @abi {
  type ParseError,
  type Candidate,
  type Warning,
  type WarningKind,
  type Value,
  type Source,
  type EffectOp,
  type ResultValue,
  type DefError,
  type DefErrorKind,
  type FnInvocation,
  type ErrorKind,
  type TermHint,
  type ConfigVal,
  type HelpValueStructure,
  type HelpSingleValue,
  type HelpRepeatSpec,
  type HelpTypeRef,
}

///|
/// CLI bindings produced by parse before value-source resolution.
pub struct ParsedBindings {
  priv raw : Array[@abi.Binding]
}

///|
/// Bindings after value-source resolution. The parse-phase effects are retained for output.
pub struct ResolvedBindings {
  priv raw : Array[@abi.Binding]
  priv effects_ : Array[@abi.Binding]
}

///|
/// One parse interpretation. It may only be combined with the AtomicAST that produced it.
pub struct Interpretation {
  priv raw : @engine.AmbiguousInterpretation
}

///|
pub fn Interpretation::claimants(
  self : Interpretation,
) -> Array[(String, String)] {
  self.raw.claimants.copy()
}

///|
/// An ambiguous parse and its parse-phase interpretations.
pub struct ParsedAmbiguity {
  interpretations : Array[Interpretation]
  help_entry : String?
}

///|
/// A parse or resolve failure.
pub struct ParseFailure {
  errors : Array[@abi.ParseError]
  fired_action : String?
  help_entry : String?
  tried_triggers : Array[String]
}

///|
pub(all) enum ParsedOutcome {
  Success(ParsedBindings)
  Failure(ParseFailure)
  Ambiguous(ParsedAmbiguity)
}

///|
pub(all) enum ResolvedOutcome {
  Success(ResolvedBindings)
  Failure(ParseFailure)
}

///|
/// Stable providers for the parse and resolve phases. A provider must return the same value for the
/// same key throughout both phases; behavior is undefined when that contract is violated.
pub struct ValueSources {
  priv env_ : (String) -> String?
  priv config_ : (String) -> @abi.ConfigVal?
  priv tty_ : (String) -> TtyObs?
}

///|
pub fn value_sources(
  env? : (String) -> String? = fn(_) { None },
  config? : (String) -> @abi.ConfigVal? = fn(_) { None },
  tty? : (String) -> TtyObs? = fn(_) { None },
) -> ValueSources {
  { env_: env, config_: config, tty_: tty }
}

///|
pub fn env_from_map(values : Map[String, String]) -> (String) -> String? {
  fn(key) { values.get(key) }
}

///|
fn parse_failure(data : @engine.FailureData) -> ParseFailure {
  {
    errors: data.errors,
    fired_action: data.fired_action,
    help_entry: data.help_entry,
    tried_triggers: data.tried_triggers,
  }
}

///|
fn warnings_from_bindings(
  bindings : Array[@abi.Binding],
) -> Array[@abi.Warning] {
  @engine.warnings_of(@engine.Success(bindings))
}

///|
pub fn ParsedOutcome::warnings(self : ParsedOutcome) -> Array[@abi.Warning] {
  match self {
    Success(bindings) => warnings_from_bindings(bindings.raw)
    Failure(_) | Ambiguous(_) => []
  }
}

///|
pub fn ResolvedOutcome::warnings(self : ResolvedOutcome) -> Array[@abi.Warning] {
  match self {
    Success(bindings) => warnings_from_bindings(bindings.raw)
    Failure(_) => []
  }
}
