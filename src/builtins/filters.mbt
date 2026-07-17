// filters.mbt — builtin the filters registry (DR-009/010/036/061/077): the pure-function chain that
// DR-009 threads through 4 phases (piece_filters / value_filters (each) / final_filters (non-accum
// final value) / accum_filters (累積配列, DR-102 attribute split)). MDR-002 §3: depends on {node,
// value} only (no eval dependency — filters run over already-parsed `@engine.Value`s, not tokens).
//
// SCOPE (issue 2026-07-09-filters-registry-foundation): this is a MINIMAL kuu.mbt reference-
// implementation register, not the full multi-host DR-010 registry machinery (tree-shake / Level
// 0-3 dynamic injection / explicit opt-in extension tiers — those are language-DX concerns for
// OTHER host bindings, moot for a single MoonBit reference implementation: every built-in filter
// is simply always registered). DR-062's inheritance interface (`{prepend, append}` composition
// against a ref/type-registry base chain) is likewise OUT OF SCOPE: kuu.mbt has no `type` registry
// (a name → factory lookup for value parsers) to inherit FROM yet, so there is no base chain to
// compose against — `value_filters`/`piece_filters`/`final_filters`/`accum_filters` are plain
// `Array[@engine.FilterSpelling]` (colon-shorthand DSL `"<name>:<arg>:<arg>..."` and DESIGN §8.4 object
// form, DR-009/DR-085 §3, both decoded to the same structured shape — node.mbt's `@engine.FilterSpelling`)
// with no inherit/prepend/append object form. Revisit when a type registry with per-type default
// chains exists.

///|
pub fn split_colon(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut current = ""
  for char in s {
    if char == ':' {
      out.push(current)
      current = ""
    } else {
      current = current + char.to_string()
    }
  }
  out.push(current)
  out
}

///|
/// A filter's SIGNATURE (DR-061 §5 "factory config と filter の線引きは相で切る" + DR-077 §2 "使える
/// のは transform シグネチャ (T => T) の filter のみ"): `Validate` never changes its input (success =
/// input unchanged, failure = Err) — e.g. `non_empty`, `in_range`. `Transform` computes a NEW value
/// from the input — e.g. `trim`, `increment`. This distinction is what DR-077 §2 needs to reject a
/// validate-only filter as an `update` transform (a validator has nothing meaningful to "become").
pub enum FilterSignature {
  Validate
  Transform
} derive(Eq, Debug)

///|
/// Whether this descriptor can produce a replacement value.
pub fn FilterSignature::is_transform(self : FilterSignature) -> Bool {
  self is Transform
}

///|
/// One filters-registry entry (DR-010 "filters" registry区分 + DR-061 descriptor 概念 applied to
/// filters, not just installers — signature is the descriptor axis DR-077 §2 needs). `reasons` is
/// this descriptor's declared failure-mode vocabulary (DR-095 §3's per-filter table; spec 正本 is
/// `schema/builtin-descriptors.json`) — `run`'s `Err` reason must be a member of this list for a
/// correctly-defined filter invocation, EXCEPT filter-definition-bug paths (arg-count mismatch, a
/// malformed regex pattern, a value whose type this filter doesn't handle), which fall back to
/// `"filter_rejected"` and sit outside the declared vocabulary (DR-095 §3: these are not a failure
/// mode of a *correctly defined* filter, so completeness/typo checking doesn't cover them — same
/// posture `apply_filter_chain` already uses for an unregistered filter NAME, generalized here to
/// an unregistered filter REASON). `run` is genuinely a closure (kuu.mbt is the single MoonBit
/// reference host — DR-010's wire-serializable `{name, config}` factory form is a multi-host
/// concern this reference impl does not need to round-trip through JSON) — `FilterDescriptor`
/// therefore has no `derive(Eq)` (closures aren't comparable); registry lookup is by `name`
/// (String), never by descriptor equality.
pub struct FilterDescriptor {
  name : String
  signature : FilterSignature
  reasons : Array[String]
  // DR-009 "args はすべて string、filter registry 側でキャスト": the closure owns its own arg
  // parsing/casting, uniformly for every filter (mirrors `dsl_operand_value`'s per-type casting,
  // just filter-side instead of variant-side). Err carries (reason, message) — reason is this
  // descriptor's DR-095 vocabulary (or `"filter_rejected"`, see this struct's doc comment).
  run : (@engine.Value, Array[String]) -> Result[
    @engine.Value,
    (String, String),
  ]
}

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
/// The filters registry (DR-010 §filters 区分). A minimal built-in set (DR-040 §「filters registry
/// の階層」canonical/標準 layer — no 拡張/opt-in tier exists in this single-host reference impl, see
/// this file's header note). Constructed fresh per lookup rather than held as a top-level `let`
/// (kuu.mbt has no existing top-level-registry pattern to follow; a fresh `Map` per call keeps this
/// symmetrical with the rest of the codebase's "build what you need, when you need it" style — the
/// map is tiny and lookups are not hot-path).
fn filters_registry() -> Map[String, FilterDescriptor] {
  Map::from_array([
    (
      "trim",
      { name: "trim", signature: Transform, reasons: [], run: filter_trim },
    ),
    (
      "non_empty",
      {
        name: "non_empty",
        signature: Validate,
        reasons: ["empty_value"],
        run: filter_non_empty,
      },
    ),
    (
      "in_range",
      {
        name: "in_range",
        signature: Validate,
        reasons: ["too_small", "too_large"],
        run: filter_in_range,
      },
    ),
    (
      "regex_match",
      {
        name: "regex_match",
        signature: Validate,
        reasons: ["pattern_no_match"],
        run: filter_regex_match,
      },
    ),
    (
      "increment",
      {
        name: "increment",
        signature: Transform,
        reasons: [],
        run: filter_increment,
      },
    ),
  ])
}

///|
/// Look up one filter by name (registry lookup — DR-010 "フィールド名でレジストリが暗黙決定").
pub fn lookup_filter(name : String) -> FilterDescriptor? {
  filters_registry().get(name)
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
/// One ARRAY accum_filters registry entry (DR-009 段 7, DR-102 属性分割): unlike `FilterDescriptor`
/// (`@engine.Value => @engine.Value`, piece/value_filters/final_filters phases), this phase's `run` is
/// `Array[@engine.Value] => Array[@engine.Value]` — the accumulated cell's WHOLE final array is the unit these
/// filters see (issue accum-post-filters-stage7's "未裁定の論点1" resolved: whole-array, not
/// per-element — a self-map over U, DR-083 §2's literal order "accumulator 畳み → accum_filters"
/// has no per-piece step left to run this at). A separate registry from `filters_registry()` (not a
/// variant/overload of it) because the two phases have genuinely different signatures — no name
/// collision risk since `installer.mbt`'s `collect_unknown_filter` rejects an accum entity's
/// accum_filters chain containing a name this registry doesn't know, at DEFINITION time.
/// DR-105 §4: the ARRAY filter registry now shares the SAME Validate/Transform signature split as
/// `FilterDescriptor` (`signature`/`reasons` fields, `run` returns `Result`) — `unique` stayed the
/// sole resident as a `Transform` (never rejects) until `length_range` (DR-105 §5) became the first
/// `Validate` resident able to reject. `resolve.mbt`'s `apply_entity_filters` is where the reject
/// actually surfaces as a `ParseError` (DR-102 §4's `args.length()` attribution) — by the time
/// `build_result` runs this chain again (to get the transformed array for rendering), every chain
/// has already been proven non-rejecting, so that call site's `Err` arm is defensive-only.
pub struct ArrayFilterDescriptor {
  name : String
  signature : FilterSignature
  reasons : Array[String]
  run : (Array[@engine.Value], Array[String]) -> Result[
    Array[@engine.Value],
    (String, String),
  ]
}

///|
fn array_filters_registry() -> Map[String, ArrayFilterDescriptor] {
  Map::from_array([
    (
      "unique",
      {
        name: "unique",
        signature: Transform,
        reasons: [],
        run: array_filter_unique,
      },
    ),
    (
      "length_range",
      {
        name: "length_range",
        signature: Validate,
        reasons: ["too_short", "too_long"],
        run: array_filter_length_range,
      },
    ),
  ])
}

///|
/// Look up one ARRAY accum_filters entry by name (DR-009 段7 registry, DR-102 属性分割, separate
/// from `lookup_filter`'s per-value registry — see `ArrayFilterDescriptor`'s doc comment for why).
pub fn lookup_array_filter(name : String) -> ArrayFilterDescriptor? {
  array_filters_registry().get(name)
}

///|
/// Run an accum cell's accum_filters chain (DR-009 段 7, DR-102 属性分割, DR-105 §4 Result-ified)
/// over its final accumulated array, in declared order — short-circuits on the first `Err`, mirroring
/// `apply_filter_chain`'s scalar-side chain walk. `installer.mbt`'s `collect_unknown_filter` already
/// guarantees every chain entry reaching here is a registered array filter name (definition-time
/// gate, `ArrayFilterDescriptor`'s doc comment); an unregistered name here is therefore unreachable
/// in practice and is skipped (same defensive posture as `apply_collector`'s "unrecognized name —
/// identity" fallback).
pub fn apply_accum_filter_chain(
  chain : Array[@engine.FilterSpelling],
  vs : Array[@engine.Value],
) -> Result[Array[@engine.Value], (String, String)] {
  let mut current = vs
  for fs in chain {
    match lookup_array_filter(fs.name) {
      None => ()
      Some(d) =>
        match (d.run)(current, fs.args) {
          Ok(v2) => current = v2
          Err(e) => return Err(e)
        }
    }
  }
  Ok(current)
}

///|
/// Parse the colon-shorthand DSL string (`"in_range:1:65535"`, DR-009 §DSL 文法) into a
/// `@engine.FilterSpelling` — the SOLE colon-splitting point for filter chains (mirrors `installer.mbt`'s
/// `classify_long_spelling` being the sole interpreter of the variant colon DSL). The decode
/// boundary (`json_conformance_wbtest.mbt`'s `dec_filter_chain`) calls this for every plain-string
/// chain element; wbtest call sites use it too, for the shorthand's ergonomics instead of hand-
/// building a `@engine.FilterSpelling` struct literal per case.
pub fn parse_filter_shorthand(s : String) -> @engine.FilterSpelling {
  let parts = split_colon(s)
  let name = parts[0]
  let args : Array[String] = []
  let mut i = 1
  while i < parts.length() {
    args.push(parts[i])
    i = i + 1
  }
  { name, args }
}

///|
/// Run one filter chain (an `Array[@engine.FilterSpelling]`, DR-009 §DSL 文法) over a value, in declared
/// order (DR-034 合成順「後ろほど優先」と同じ — chain 内は宣言順そのまま素通し、上書きの概念はない).
/// `@engine.FilterSpelling` (node.mbt) already carries `name`/`args` structured — colon-shorthand splitting
/// and DESIGN §8.4 / DR-085 §3 object-form decoding both happen ONCE at the decode boundary
/// (`json_conformance_wbtest.mbt`'s `dec_filter_chain`), so this function never re-parses a spelling
/// string (issue filter-spelling-inband-encoding-retyping — replaces the earlier U+E000 PUA-tag
/// single-string encoding that let an object-form arg containing that exact code point corrupt the
/// split; a structured `args : Array[String]` has no such in-band collision to begin with). A
/// filter's own Err surfaces as `Err(reason, message)` — `reason` is a machine-readable DR-066-style
/// identifier the caller threads into a ParseError (mirrors `apply_transform`'s `filter_rejected`
/// fallback shape for its own defensive/definition-error paths — DR-095 §5's SCH-Q4 sole fallback
/// for a reason not in its declared vocabulary); a filter's own Err already carries whatever reason
/// its `FilterDescriptor.run` chose (its DR-095 declared vocabulary for a correctly-defined failure,
/// `filter_rejected` fallback for a filter-definition-bug path — see `FilterDescriptor`'s doc
/// comment), so this loop threads it through unchanged.
///
/// DR-101: an unregistered filter name is unreachable — `installer.mbt`'s `collect_unknown_filter`
/// definition-time gate has already reject-ed it as `kind=unknown-vocab`. Falls back to a no-op
/// pass-through here (same defensive posture as `apply_cell_filter_chain`'s array-side counterpart,
/// both guarded by a decode-time vocab check that runs before this ever sees the name).
pub fn apply_filter_chain(
  chain : Array[@engine.FilterSpelling],
  v : @engine.Value,
) -> Result[@engine.Value, (String, String)] {
  let mut current = v
  for fs in chain {
    match lookup_filter(fs.name) {
      None => ()
      Some(d) =>
        match (d.run)(current, fs.args) {
          Ok(v2) => current = v2
          Err(e) => return Err(e)
        }
    }
  }
  Ok(current)
}

///|
/// DR-034/DR-062 piece_filters: run a String→String chain over one raw token / piece, immediately
/// before that value reaches its type parser (eval.mbt's value-primitive arms, builtins/matcher_residents.mbt's
/// `run_eq_split`/`short_val`, resolve.mbt's `env_value`). Thin wrapper over `apply_filter_chain`
/// specialized to the piece_filters contract (string in, string out) — every registered filter that
/// isn't string-aware already passes a non-`@engine.VStr` through untouched (`filter_trim`'s doc comment),
/// so the `Ok(@engine.VStr(s))` arm is the only reachable success shape today. A filter that returns a
/// non-string here is a filter-definition bug violating the String→String contract (DR-034's
/// `FilterChain[String, String]`); surfacing it as an Err keeps the bug visible instead of silently
/// discarding the chain's work (reuses the `filter_rejected` reason — no new vocabulary — with a
/// message naming the contract violation). Callers convert the `Err` tuple to a `ParseError`
/// themselves (eval.mbt/builtins/matcher_residents.mbt build `kind: KFilter` inline per `filter_arg_eval`'s precedent;
/// resolve.mbt reuses its own `filter_err`) — this function stays value-source-agnostic (no
/// args_pos/element to carry) so both the CLI-token-consumption callers and the ladder (env)
/// caller can share it.
pub fn apply_piece_filters(
  chain : Array[@engine.FilterSpelling],
  raw : String,
) -> Result[String, (String, String)] {
  match apply_filter_chain(chain, @engine.VStr(raw)) {
    Ok(@engine.VStr(s)) => Ok(s)
    Ok(_) =>
      Err(
        (
          "filter_rejected", "piece_filters chain returned a non-string value (String→String contract violation, filter-definition bug)",
        ),
      )
    Err(e) => Err(e)
  }
}
