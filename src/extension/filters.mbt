// filters.mbt — builtin filter residents for piece/value/final/accum phases.
// Every chain entry uses the engine-owned universal invocation carrier and is
// executed over an already parsed `@abi.Value` through `FnCtx[filter]`.

///|
/// `trim` (DR-040 §piece_filters example, DR-009 §DSL 文法): string-only, strips ASCII whitespace
/// from both ends. A `Transform` (the value CHANGES). Non-string input is untouched (defensive —
/// every current call site only ever feeds `trim` a `@abi.String`, DR-009's piece_filters phase is
/// string→string by construction).
fn filter_trim(
  v : @abi.Value,
  _args : Array[String],
) -> Result[@abi.Value, FnReason] {
  match v {
    @abi.String(s) => Ok(@abi.String(s.trim(chars=" \t\n\r").to_owned()))
    other => Ok(other)
  }
}

///|
/// `non_empty` (DR-040 §filters 最小セット): string-only `Validate` — Err on the empty string,
/// value unchanged otherwise. Non-string input passes through untouched (defensive, same rationale
/// as `filter_trim`). Sole declared reason (DR-095 §3): `empty_value`.
fn filter_non_empty(
  v : @abi.Value,
  _args : Array[String],
) -> Result[@abi.Value, FnReason] {
  match v {
    @abi.String(s) =>
      if s == "" {
        Err({
          disposition: @abi.ValueSpaceMiss,
          reason: "empty_value",
          message: "value is empty",
        })
      } else {
        Ok(v)
      }
    other => Ok(other)
  }
}

///|
/// `in_range:<min>:<max>` (DR-040 §「count の上限は final_filters (in_range 等) で書く」, DR-077 §1
/// "final_filters が update の結果にも通る" の実証対象そのもの、DR-102 属性分割): number-only
/// `Validate`. `min`/`max`
/// are the DSL args (DR-009 "args はすべて string、filter registry 側でキャスト") — parsed here via
/// `parse_number` (canonical DR-074 §1 lexicon, same parser the value primitives use). A malformed
/// arg is a filter-definition error surfaced as an Err with the `filter_rejected` fallback reason
/// (caught at filter-run time, same as any other filter-definition-bug path — no separate
/// definition-time arg-arity check exists yet for filter DSL args, unlike `update`'s transform-name
/// check in lowering.mbt's `classify_long_spelling`). The two ordinary Validate rejects — below
/// `min` / above `max` — carry the descriptor's declared reasons (DR-095 §3): `too_small` /
/// `too_large` respectively.
fn filter_in_range(
  v : @abi.Value,
  args : Array[String],
) -> Result[@abi.Value, FnReason] {
  match v {
    @abi.Number(n) => {
      if args.length() != 2 {
        return Err({
          disposition: @abi.RecognizedButInvalid,
          reason: "filter_rejected",
          message: "in_range requires exactly 2 args (min, max)",
        })
      }
      let min = match parse_number(args[0]) {
        Some(d) => d
        None =>
          return Err({
            disposition: @abi.RecognizedButInvalid,
            reason: "filter_rejected",
            message: "in_range min '" + args[0] + "' is not a number",
          })
      }
      let max = match parse_number(args[1]) {
        Some(d) => d
        None =>
          return Err({
            disposition: @abi.RecognizedButInvalid,
            reason: "filter_rejected",
            message: "in_range max '" + args[1] + "' is not a number",
          })
      }
      if n < min {
        Err({
          disposition: @abi.RecognizedButInvalid,
          reason: "too_small",
          message: "value \{n} is less than min \{min}",
        })
      } else if n > max {
        Err({
          disposition: @abi.RecognizedButInvalid,
          reason: "too_large",
          message: "value \{n} is greater than max \{max}",
        })
      } else {
        Ok(v)
      }
    }
    _ =>
      Err({
        disposition: @abi.RecognizedButInvalid,
        reason: "filter_rejected",
        message: "in_range requires a number value",
      })
  }
}

///|
/// `increment` (DR-077 §2/§3 built-in transform, count's `:update:increment`): number-only
/// `Transform`, `(old) => old + 1`. 0-arg (DR-077 §2 "0-arg"). This is the SAME closure
/// `apply_transform` (resolve.mbt) now looks up by name instead of hardcoding — the registry lookup
/// this issue exists to introduce. Transform (never fails on a well-formed call, DR-095 §3:
/// `reasons: []`) — the arg-count / non-number Err arms below are filter-definition-bug paths
/// (`filter_rejected` fallback, see `FilterDescriptor`'s doc comment), not a declared failure mode.
fn filter_increment(
  v : @abi.Value,
  args : Array[String],
) -> Result[@abi.Value, FnReason] {
  if args.length() != 0 {
    return Err({
      disposition: @abi.RecognizedButInvalid,
      reason: "filter_rejected",
      message: "increment takes no args",
    })
  }
  match v {
    @abi.Number(n) => Ok(@abi.Number(n + 1.0))
    _ =>
      Err({
        disposition: @abi.RecognizedButInvalid,
        reason: "filter_rejected",
        message: "increment requires a number value",
      })
  }
}

///|
/// `regex_match:<pattern>` (DR-085 §1/§2): string-only `Validate`, a thin wrapper over MoonBit
/// core's first-class `string.Regex` (kuu.mbt has no `x` regex package — `~/.moon/lib/core`'s
/// `string` package's `Regex::Regex`/`execute` is the toolchain-standard engine, DR-085 §2's "host
/// 実装準拠" dialect declaration for this host is exactly this engine, no self-rolled subset engine
/// needed). Unanchored
/// = partial match (DR-085 §1 — this filter never injects an implicit `^`/`$`; a caller wanting a
/// full match writes the anchors into the pattern itself, matching general regex-engine convention).
/// Compile failure (malformed pattern — a filter-DEFINITION bug, DR-085 §1 / DR-082 §3 belongs to
/// definition-error's kind=invalid-argument, not this runtime reason vocabulary — `lowering.mbt`'s
/// `collect_invalid_regex_pattern` already gates it at definition time, so this arm is defensive/
/// unreachable in a correctly-defined filter chain) and match failure (a valid pattern simply not
/// matching this input — the ordinary Validate reject) are two DISTINCT `Err`s per DR-085 §1
/// ("pattern の compile 失敗と照合不一致は別の失敗"): compile failure falls back to
/// `filter_rejected` (outside this descriptor's declared reasons), match failure carries
/// `pattern_no_match` (DR-095 §3's sole declared reason for this descriptor).
fn filter_regex_match(
  v : @abi.Value,
  args : Array[String],
) -> Result[@abi.Value, FnReason] {
  match v {
    @abi.String(s) => {
      if args.length() != 1 {
        return Err({
          disposition: @abi.RecognizedButInvalid,
          reason: "filter_rejected",
          message: "regex_match requires exactly 1 arg (pattern)",
        })
      }
      let pattern = args[0]
      match compile_regex(pattern) {
        None =>
          Err({
            disposition: @abi.RecognizedButInvalid,
            reason: "filter_rejected",
            message: "regex_match pattern '" + pattern + "' failed to compile",
          })
        Some(re) =>
          match re.execute(s) {
            Some(_) => Ok(v)
            None =>
              Err({
                disposition: @abi.ValueSpaceMiss,
                reason: "pattern_no_match",
                message: "value '" +
                s +
                "' does not match pattern '" +
                pattern +
                "'",
              })
          }
      }
    }
    _ =>
      Err({
        disposition: @abi.RecognizedButInvalid,
        reason: "filter_rejected",
        message: "regex_match requires a string value",
      })
  }
}

///|
pub fn trim_filter() -> FilterDescriptor {
  filter_descriptor("trim", FilterSignature::Transform, [], filter_trim)
}

///|
pub fn non_empty_filter() -> FilterDescriptor {
  filter_descriptor(
    "non_empty",
    FilterSignature::Validate,
    ["empty_value"],
    filter_non_empty,
  )
}

///|
pub fn in_range_filter() -> FilterDescriptor {
  filter_descriptor(
    "in_range",
    FilterSignature::Validate,
    ["too_small", "too_large"],
    filter_in_range,
  )
}

///|
pub fn regex_match_filter() -> FilterDescriptor {
  filter_descriptor(
    "regex_match",
    FilterSignature::Validate,
    ["pattern_no_match"],
    filter_regex_match,
  )
}

///|
pub fn increment_filter() -> FilterDescriptor {
  filter_descriptor(
    "increment",
    FilterSignature::Transform,
    [],
    filter_increment,
  )
}

///|
/// `unique`: an accum cell's ARRAY-shaped accum_filters entry (DR-009 段 7 "post_filters"/Acc→Acc,
/// issue accum-post-filters-stage7 / DR-083 §2's "value_filters per piece → accumulator 畳み →
/// accum_filters" order, DR-102 属性分割) — dedupes by `@abi.Value` structural equality, first-occurrence
/// order preserved (stable, mirrors how a human reads "unique" — not sorted). 0-arg (same shape as
/// `increment`). A `Transform` (DR-105 §4's Validate/Transform split applied to the ARRAY registry
/// for the first time) — never rejects, so this always returns `Ok`.
fn array_filter_unique(
  vs : Array[@abi.Value],
  _args : Array[String],
) -> Result[Array[@abi.Value], FnReason] {
  let out : Array[@abi.Value] = []
  for v in vs {
    let mut dup = false
    for o in out {
      if o == v {
        dup = true
        break
      }
    }
    if !dup {
      out.push(v)
    }
  }
  Ok(out)
}

///|
/// `length_range:<min>:<max>` (DR-105 §5): ARRAY filter registry's first `Validate` — checks the
/// accumulated cell's array LENGTH (not its element values, unlike scalar `in_range`), never
/// transforms it. `min`/`max` parsed via `parse_number` (same canonical DR-074 §1 lexicon
/// `filter_in_range` uses) — a malformed arg is a filter-definition-bug path (`filter_rejected`
/// fallback, same posture `filter_in_range`'s own arg-parse arms use), NOT one of this descriptor's
/// declared reasons (`lowering.mbt`'s `collect_invalid_numeric_filter_args`, DR-082 §3, catches a
/// non-numeric/wrong-arity `length_range` at definition time — this runtime arm is defensive).
/// DR-105 §5 明確化 note (a) (codex #3 反映): `length_range`'s bound is non-negative-integer-only
/// (unlike `in_range`'s canonical number) — `collect_invalid_numeric_filter_args` gates this at
/// definition time too (`nonneg_int=true` for this filter's chain entries only), so a negative or
/// non-integer `min`/`max` never reaches this runtime arm in a correctly-defined chain; the `n <
/// min`/`n > max` comparisons below stay simple `Double` comparisons (no re-validation here) because
/// the gate already guarantees `min`/`max` are non-negative integers by the time parse_definition
/// succeeds — same "push structural validity to definition-error, keep runtime paths total" posture
/// `ArrayFilterDescriptor`'s own doc comment describes.
/// `too_short`/`too_long` mirror `in_range`'s `too_small`/`too_large` naming (DR-066 reason-code
/// symmetry, DR-105 §5).
fn array_filter_length_range(
  vs : Array[@abi.Value],
  args : Array[String],
) -> Result[Array[@abi.Value], FnReason] {
  if args.length() != 2 {
    return Err({
      disposition: @abi.RecognizedButInvalid,
      reason: "filter_rejected",
      message: "length_range requires exactly 2 args (min, max)",
    })
  }
  let min = match parse_number(args[0]) {
    Some(d) => d
    None =>
      return Err({
        disposition: @abi.RecognizedButInvalid,
        reason: "filter_rejected",
        message: "length_range min '" + args[0] + "' is not a number",
      })
  }
  let max = match parse_number(args[1]) {
    Some(d) => d
    None =>
      return Err({
        disposition: @abi.RecognizedButInvalid,
        reason: "filter_rejected",
        message: "length_range max '" + args[1] + "' is not a number",
      })
  }
  let n = vs.length().to_double()
  if n < min {
    Err({
      disposition: @abi.RecognizedButInvalid,
      reason: "too_short",
      message: "array length \{vs.length()} is less than min \{min}",
    })
  } else if n > max {
    Err({
      disposition: @abi.RecognizedButInvalid,
      reason: "too_long",
      message: "array length \{vs.length()} is greater than max \{max}",
    })
  } else {
    Ok(vs)
  }
}

///|
pub fn unique_array_filter() -> ArrayFilterDescriptor {
  array_filter_descriptor(
    "unique",
    FilterSignature::Transform,
    [],
    array_filter_unique,
  )
}

///|
pub fn length_range_array_filter() -> ArrayFilterDescriptor {
  array_filter_descriptor(
    "length_range",
    FilterSignature::Validate,
    ["too_short", "too_long"],
    array_filter_length_range,
  )
}

///|
/// Parse one filter colon shorthand (`"in_range:1:65535"`) through the
/// engine-owned universal invocation parser. Wire decoding and wbtests use this
/// wrapper for the plain-string form; one-level arrays call the same engine
/// parser with `ArrayParts`.
pub fn parse_filter_shorthand(s : String) -> @abi.FnInvocation {
  match @abi.parse_fn_invocation(@abi.ColonString(s)) {
    Ok(invocation) => invocation
    Err(message) => abort(message)
  }
}

///|
/// Compile a MoonBit core `string.Regex`, converting the raise signature into an Option —
/// the same host-dialect compile path the engine's dd `match` uses (DR-085/DR-090 §2
/// "照合方言は host 実装準拠"; definition-time validation in `lowering.mbt` and the runtime
/// `regex_match` filter share THIS compile so both see the same dialect).
fn compile_regex(pattern : String) -> @string.Regex? {
  Some(@string.Regex::Regex(pattern)) catch {
    _ => None
  }
}
