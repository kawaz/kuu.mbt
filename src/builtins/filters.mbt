// filters.mbt — builtin filter residents for piece/value/final/accum phases.
// Every chain entry uses the engine-owned universal invocation carrier and is
// executed over an already parsed `@engine.Value` through `FnCtx[filter]`.

///|
/// `trim` (DR-040 §piece_filters example, DR-009 §DSL 文法): string-only, strips ASCII whitespace
/// from both ends. A `Transform` (the value CHANGES). Non-string input is untouched (defensive —
/// every current call site only ever feeds `trim` a `@engine.VStr`, DR-009's piece_filters phase is
/// string→string by construction).
fn filter_trim(
  v : @engine.Value,
  _args : Array[String],
) -> Result[@engine.Value, (String, String)] {
  match v {
    @engine.VStr(s) => Ok(@engine.VStr(s.trim(chars=" \t\n\r").to_owned()))
    other => Ok(other)
  }
}

///|
/// `non_empty` (DR-040 §filters 最小セット): string-only `Validate` — Err on the empty string,
/// value unchanged otherwise. Non-string input passes through untouched (defensive, same rationale
/// as `filter_trim`). Sole declared reason (DR-095 §3): `empty_value`.
fn filter_non_empty(
  v : @engine.Value,
  _args : Array[String],
) -> Result[@engine.Value, (String, String)] {
  match v {
    @engine.VStr(s) =>
      if s == "" {
        Err(("empty_value", "value is empty"))
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
/// check in installer.mbt's `classify_long_spelling`). The two ordinary Validate rejects — below
/// `min` / above `max` — carry the descriptor's declared reasons (DR-095 §3): `too_small` /
/// `too_large` respectively.
fn filter_in_range(
  v : @engine.Value,
  args : Array[String],
) -> Result[@engine.Value, (String, String)] {
  match v {
    @engine.VNum(n) => {
      if args.length() != 2 {
        return Err(
          ("filter_rejected", "in_range requires exactly 2 args (min, max)"),
        )
      }
      let min = match parse_number(args[0]) {
        Some(d) => d
        None =>
          return Err(
            (
              "filter_rejected",
              "in_range min '" + args[0] + "' is not a number",
            ),
          )
      }
      let max = match parse_number(args[1]) {
        Some(d) => d
        None =>
          return Err(
            (
              "filter_rejected",
              "in_range max '" + args[1] + "' is not a number",
            ),
          )
      }
      if n < min {
        Err(("too_small", "value \{n} is less than min \{min}"))
      } else if n > max {
        Err(("too_large", "value \{n} is greater than max \{max}"))
      } else {
        Ok(v)
      }
    }
    _ => Err(("filter_rejected", "in_range requires a number value"))
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
  v : @engine.Value,
  args : Array[String],
) -> Result[@engine.Value, (String, String)] {
  if args.length() != 0 {
    return Err(("filter_rejected", "increment takes no args"))
  }
  match v {
    @engine.VNum(n) => Ok(@engine.VNum(n + 1.0))
    _ => Err(("filter_rejected", "increment requires a number value"))
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
/// definition-error's kind=invalid-argument, not this runtime reason vocabulary — `installer.mbt`'s
/// `collect_invalid_regex_pattern` already gates it at definition time, so this arm is defensive/
/// unreachable in a correctly-defined filter chain) and match failure (a valid pattern simply not
/// matching this input — the ordinary Validate reject) are two DISTINCT `Err`s per DR-085 §1
/// ("pattern の compile 失敗と照合不一致は別の失敗"): compile failure falls back to
/// `filter_rejected` (outside this descriptor's declared reasons), match failure carries
/// `pattern_no_match` (DR-095 §3's sole declared reason for this descriptor).
fn filter_regex_match(
  v : @engine.Value,
  args : Array[String],
) -> Result[@engine.Value, (String, String)] {
  match v {
    @engine.VStr(s) => {
      if args.length() != 1 {
        return Err(
          ("filter_rejected", "regex_match requires exactly 1 arg (pattern)"),
        )
      }
      let pattern = args[0]
      match @engine.compile_regex(pattern) {
        None =>
          Err(
            (
              "filter_rejected",
              "regex_match pattern '" + pattern + "' failed to compile",
            ),
          )
        Some(re) =>
          match re.execute(s) {
            Some(_) => Ok(v)
            None =>
              Err(
                (
                  "pattern_no_match",
                  "value '" + s + "' does not match pattern '" + pattern + "'",
                ),
              )
          }
      }
    }
    _ => Err(("filter_rejected", "regex_match requires a string value"))
  }
}

///|
pub fn trim_filter() -> @engine.FilterDescriptor {
  @engine.filter_descriptor("trim", @engine.Transform, [], filter_trim)
}

///|
pub fn non_empty_filter() -> @engine.FilterDescriptor {
  @engine.filter_descriptor(
    "non_empty",
    @engine.Validate,
    ["empty_value"],
    filter_non_empty,
  )
}

///|
pub fn in_range_filter() -> @engine.FilterDescriptor {
  @engine.filter_descriptor(
    "in_range",
    @engine.Validate,
    ["too_small", "too_large"],
    filter_in_range,
  )
}

///|
pub fn regex_match_filter() -> @engine.FilterDescriptor {
  @engine.filter_descriptor(
    "regex_match",
    @engine.Validate,
    ["pattern_no_match"],
    filter_regex_match,
  )
}

///|
pub fn increment_filter() -> @engine.FilterDescriptor {
  @engine.filter_descriptor(
    "increment",
    @engine.Transform,
    [],
    filter_increment,
  )
}

///|
/// `unique`: an accum cell's ARRAY-shaped accum_filters entry (DR-009 段 7 "post_filters"/Acc→Acc,
/// issue accum-post-filters-stage7 / DR-083 §2's "value_filters per piece → accumulator 畳み →
/// accum_filters" order, DR-102 属性分割) — dedupes by `@engine.Value` structural equality, first-occurrence
/// order preserved (stable, mirrors how a human reads "unique" — not sorted). 0-arg (same shape as
/// `increment`). A `Transform` (DR-105 §4's Validate/Transform split applied to the ARRAY registry
/// for the first time) — never rejects, so this always returns `Ok`.
fn array_filter_unique(
  vs : Array[@engine.Value],
  _args : Array[String],
) -> Result[Array[@engine.Value], (String, String)] {
  let out : Array[@engine.Value] = []
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
/// declared reasons (`installer.mbt`'s `collect_invalid_numeric_filter_args`, DR-082 §3, catches a
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
  vs : Array[@engine.Value],
  args : Array[String],
) -> Result[Array[@engine.Value], (String, String)] {
  if args.length() != 2 {
    return Err(
      ("filter_rejected", "length_range requires exactly 2 args (min, max)"),
    )
  }
  let min = match parse_number(args[0]) {
    Some(d) => d
    None =>
      return Err(
        (
          "filter_rejected",
          "length_range min '" + args[0] + "' is not a number",
        ),
      )
  }
  let max = match parse_number(args[1]) {
    Some(d) => d
    None =>
      return Err(
        (
          "filter_rejected",
          "length_range max '" + args[1] + "' is not a number",
        ),
      )
  }
  let n = vs.length().to_double()
  if n < min {
    Err(("too_short", "array length \{vs.length()} is less than min \{min}"))
  } else if n > max {
    Err(("too_long", "array length \{vs.length()} is greater than max \{max}"))
  } else {
    Ok(vs)
  }
}

///|
pub fn unique_array_filter() -> @engine.ArrayFilterDescriptor {
  @engine.array_filter_descriptor(
    "unique",
    @engine.Transform,
    [],
    array_filter_unique,
  )
}

///|
pub fn length_range_array_filter() -> @engine.ArrayFilterDescriptor {
  @engine.array_filter_descriptor(
    "length_range",
    @engine.Validate,
    ["too_short", "too_long"],
    array_filter_length_range,
  )
}

///|
/// Parse one filter colon shorthand (`"in_range:1:65535"`) through the
/// engine-owned universal invocation parser. Wire decoding and wbtests use this
/// wrapper for the plain-string form; one-level arrays call the same engine
/// parser with `ArrayParts`.
pub fn parse_filter_shorthand(s : String) -> @engine.FilterSpelling {
  match @engine.parse_fn_invocation(@engine.ColonString(s)) {
    Ok(invocation) => invocation
    Err(message) => abort(message)
  }
}
