// kawaz/kuu/contrib/timespec — timespec integration filters for kuu FilterChain

///|
/// Parse a duration string (e.g. "30s", "1m30s", "1.5h") into a Duration.
///
/// Wraps `@timespec.parse_duration` as a kuu FilterChain.
///
/// Parameters:
///
/// * `default_sign` : How to interpret input without an explicit `+`/`-` sign.
///   Defaults to `Plus`.
pub fn parse_duration(
  default_sign? : @ts.Sign = Plus,
) -> @core.FilterChain[String, @ts.Duration] {
  @core.Filter::parse(fn(s) raise @core.ParseError {
    let result : Result[@ts.Duration, _] = try? @ts.parse_duration(
      s,
      default_sign~,
    )
    match result {
      Ok(d) => d
      Err(e) =>
        raise @core.ParseError(@core.ParseErrorInfo::{
          kind: InvalidValue,
          message: e.to_string(),
          error_context: "",
          opt_name: "",
          tip: "",
        })
    }
  })
}

///|
/// Parse a timespec string (e.g. "5m", "@5m", "2026-01-01T00:00:00Z")
/// into a TimeSpec.
///
/// Wraps `@timespec.parse_timespec` as a kuu FilterChain.
/// Returns `TimeSpec?` to support the "none"/"null"/"nil" reset keywords.
///
/// Parameters:
///
/// * `default_sign` : How to interpret unsigned durations. Defaults to `Minus`
///   (CLI convention: `--since 5m` means "5 minutes ago").
/// * `now` : Clock function returning the current time in ms.
///   Defaults to `@env.now`.
pub fn parse_timespec(
  default_sign? : @ts.Sign = Minus,
  now? : () -> UInt64 = fn() { @env.now() },
) -> @core.FilterChain[String, @ts.TimeSpec] {
  @core.Filter::parse(fn(s) raise @core.ParseError {
    let result : Result[@ts.TimeSpec?, _] = try? @ts.parse_timespec(
      s,
      default_sign~,
      now~,
    )
    match result {
      Ok(Some(ts)) => ts
      Ok(None) =>
        raise @core.ParseError(@core.ParseErrorInfo::{
          kind: InvalidValue,
          message: "timespec resolved to none: " + s,
          error_context: "",
          opt_name: "",
          tip: "",
        })
      Err(e) =>
        raise @core.ParseError(@core.ParseErrorInfo::{
          kind: InvalidValue,
          message: e.to_string(),
          error_context: "",
          opt_name: "",
          tip: "",
        })
    }
  })
}

///|
/// Like `parse_timespec` but returns `TimeSpec?`, allowing "none"/"null"/"nil"
/// to pass through as `None`.
pub fn parse_timespec_optional(
  default_sign? : @ts.Sign = Minus,
  now? : () -> UInt64 = fn() { @env.now() },
) -> @core.FilterChain[String, @ts.TimeSpec?] {
  @core.Filter::parse(fn(s) raise @core.ParseError {
    let result : Result[@ts.TimeSpec?, _] = try? @ts.parse_timespec(
      s,
      default_sign~,
      now~,
    )
    match result {
      Ok(v) => v
      Err(e) =>
        raise @core.ParseError(@core.ParseErrorInfo::{
          kind: InvalidValue,
          message: e.to_string(),
          error_context: "",
          opt_name: "",
          tip: "",
        })
    }
  })
}
