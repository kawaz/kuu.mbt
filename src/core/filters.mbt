// filters.mbt — the filters registry (DR-009/010/036/061/077): the pure-function chain that
// DR-009 threads through 3 phases (piece_filters / value_filters (each) / cell_filters). MDR-002 §3:
// depends on {node, value} only (no eval dependency — filters run over already-parsed `Value`s,
// not tokens).
//
// SCOPE (issue 2026-07-09-filters-registry-foundation): this is a MINIMAL kuu.mbt reference-
// implementation register, not the full multi-host DR-010 registry machinery (tree-shake / Level
// 0-3 dynamic injection / explicit opt-in extension tiers — those are language-DX concerns for
// OTHER host bindings, moot for a single MoonBit reference implementation: every built-in filter
// is simply always registered). DR-062's inheritance interface (`{prepend, append}` composition
// against a ref/type-registry base chain) is likewise OUT OF SCOPE: kuu.mbt has no `type` registry
// (a name → factory lookup for value parsers) to inherit FROM yet, so there is no base chain to
// compose against — `value_filters`/`piece_filters`/`cell_filters` are plain `Array[String]`
// (string-shorthand DSL only, DR-009's colon-DSL `"<name>:<arg>:<arg>..."`) with no inherit/
// prepend/append object form. Revisit when a type registry with per-type default chains exists.

///|
/// A filter's SIGNATURE (DR-061 §5 "factory config と filter の線引きは相で切る" + DR-077 §2 "使える
/// のは transform シグネチャ (T => T) の filter のみ"): `Validate` never changes its input (success =
/// input unchanged, failure = Err) — e.g. `non_empty`, `in_range`. `Transform` computes a NEW value
/// from the input — e.g. `trim`, `increment`. This distinction is what DR-077 §2 needs to reject a
/// validate-only filter as an `update` transform (a validator has nothing meaningful to "become").
pub(all) enum FilterSignature {
  Validate
  Transform
} derive(Eq, Debug)

///|
/// One filters-registry entry (DR-010 "filters" registry区分 + DR-061 descriptor 概念 applied to
/// filters, not just installers — signature is the descriptor axis DR-077 §2 needs; `reasons` is
/// deliberately NOT a separate declared list here, see the note on `apply_filter_chain`'s Err
/// arm). `run` is genuinely a closure (kuu.mbt is the single MoonBit reference host — DR-010's
/// wire-serializable `{name, config}` factory form is a multi-host concern this reference impl
/// does not need to round-trip through JSON) — `FilterDescriptor` therefore has no `derive(Eq)`
/// (closures aren't comparable); registry lookup is by `name` (String), never by descriptor
/// equality.
pub(all) struct FilterDescriptor {
  name : String
  signature : FilterSignature
  // DR-009 "args はすべて string、filter registry 側でキャスト": the closure owns its own arg
  // parsing/casting, uniformly for every filter (mirrors `dsl_operand_value`'s per-type casting,
  // just filter-side instead of variant-side).
  run : (Value, Array[String]) -> Result[Value, String]
}

///|
/// `trim` (DR-040 §piece_filters example, DR-009 §DSL 文法): string-only, strips ASCII whitespace
/// from both ends. A `Transform` (the value CHANGES). Non-string input is untouched (defensive —
/// every current call site only ever feeds `trim` a `VStr`, DR-009's piece_filters phase is
/// string→string by construction).
fn filter_trim(v : Value, _args : Array[String]) -> Result[Value, String] {
  match v {
    VStr(s) => Ok(VStr(s.trim(chars=" \t\n\r").to_owned()))
    other => Ok(other)
  }
}

///|
/// `non_empty` (DR-040 §filters 最小セット): string-only `Validate` — Err on the empty string,
/// value unchanged otherwise. Non-string input passes through untouched (defensive, same rationale
/// as `filter_trim`).
fn filter_non_empty(v : Value, _args : Array[String]) -> Result[Value, String] {
  match v {
    VStr(s) => if s == "" { Err("value is empty") } else { Ok(v) }
    other => Ok(other)
  }
}

///|
/// `in_range:<min>:<max>` (DR-040 §「count の上限は cell_filters (in_range 等) で書く」, DR-077 §1
/// "cell_filters が update の結果にも通る" の実証対象そのもの): number-only `Validate`. `min`/`max`
/// are the DSL args (DR-009 "args はすべて string、filter registry 側でキャスト") — parsed here via
/// `parse_number` (canonical DR-074 §1 lexicon, same parser the value primitives use). A malformed
/// arg is a filter-definition error surfaced as an Err (caught at filter-run time, same as any other
/// filter failure — no separate definition-time arg-arity check exists yet for filter DSL args, unlike
/// `update`'s transform-name check in installer.mbt's `classify_long_spelling`).
fn filter_in_range(v : Value, args : Array[String]) -> Result[Value, String] {
  match v {
    VNum(n) => {
      if args.length() != 2 {
        return Err("in_range requires exactly 2 args (min, max)")
      }
      let min = match parse_number(args[0]) {
        Some(d) => d
        None => return Err("in_range min '" + args[0] + "' is not a number")
      }
      let max = match parse_number(args[1]) {
        Some(d) => d
        None => return Err("in_range max '" + args[1] + "' is not a number")
      }
      if n < min || n > max {
        Err("value \{n} is out of range [\{min}, \{max}]")
      } else {
        Ok(v)
      }
    }
    _ => Err("in_range requires a number value")
  }
}

///|
/// `increment` (DR-077 §2/§3 built-in transform, count's `:update:increment`): number-only
/// `Transform`, `(old) => old + 1`. 0-arg (DR-077 §2 "0-arg"). This is the SAME closure
/// `apply_transform` (resolve.mbt) now looks up by name instead of hardcoding — the registry lookup
/// this issue exists to introduce.
fn filter_increment(v : Value, args : Array[String]) -> Result[Value, String] {
  if args.length() != 0 {
    return Err("increment takes no args")
  }
  match v {
    VNum(n) => Ok(VNum(n + 1.0))
    _ => Err("increment requires a number value")
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
    ("trim", { name: "trim", signature: Transform, run: filter_trim }),
    (
      "non_empty",
      { name: "non_empty", signature: Validate, run: filter_non_empty },
    ),
    (
      "in_range",
      { name: "in_range", signature: Validate, run: filter_in_range },
    ),
    (
      "increment",
      { name: "increment", signature: Transform, run: filter_increment },
    ),
  ])
}

///|
/// Look up one filter by name (registry lookup — DR-010 "フィールド名でレジストリが暗黙決定").
pub fn lookup_filter(name : String) -> FilterDescriptor? {
  filters_registry().get(name)
}

///|
/// Split one DSL entry (`"in_range:1:65535"`, DR-009 §DSL 文法) into (name, args) — same colon
/// convention `installer.mbt`'s `split_colon` uses for variant/update DSL, but filters have no
/// leading-empty-segment special case (`:set` sentinel) to worry about: `parts[0]` is ALWAYS the
/// filter name here.
fn split_filter_spelling(s : String) -> (String, Array[String]) {
  let parts = split_colon(s)
  let name = parts[0]
  let args : Array[String] = []
  let mut i = 1
  while i < parts.length() {
    args.push(parts[i])
    i = i + 1
  }
  (name, args)
}

///|
/// Run one filter chain (an `Array[String]` of DSL entries, DR-009's string-shorthand form) over a
/// value, in declared order (DR-034 合成順「後ろほど優先」と同じ — chain 内は宣言順そのまま素通し、
/// 上書きの概念はない). An unknown filter name or a filter's own Err both surface as `Err(reason,
/// message)` — `reason` is a machine-readable DR-066-style identifier the caller threads into a
/// ParseError (mirrors `apply_transform`'s existing `unknown_update_transform` /
/// `update_transform_type_mismatch` shape, generalized: `unknown_filter` for an unregistered name,
/// `filter_rejected` for a filter's own validation/transform failure — see this issue's "暫定 reason
/// の整理" acceptance criterion, resolved by folding apply_transform's 2 ad-hoc reasons into this
/// chain's 2 general ones).
pub fn apply_filter_chain(
  chain : Array[String],
  v : Value,
) -> Result[Value, (String, String)] {
  let mut current = v
  for spelling in chain {
    let (name, args) = split_filter_spelling(spelling)
    match lookup_filter(name) {
      None => return Err(("unknown_filter", "unknown filter '" + name + "'"))
      Some(d) =>
        match (d.run)(current, args) {
          Ok(v2) => current = v2
          Err(msg) => return Err(("filter_rejected", msg))
        }
    }
  }
  Ok(current)
}

///|
/// DR-034/DR-062 piece_filters: run a String→String chain over one raw token / piece, immediately
/// before that value reaches its type parser (eval.mbt's value-primitive arms, matcher.mbt's
/// `run_eq_split`/`short_val`, resolve.mbt's `env_value`). Thin wrapper over `apply_filter_chain`
/// specialized to the piece_filters contract (string in, string out) — every registered filter that
/// isn't string-aware already passes a non-`VStr` through untouched (`filter_trim`'s doc comment),
/// so the `Ok(VStr(s))` arm is the only reachable success shape today. A filter that returns a
/// non-string here is a filter-definition bug violating the String→String contract (DR-034's
/// `FilterChain[String, String]`); surfacing it as an Err keeps the bug visible instead of silently
/// discarding the chain's work (reuses the `filter_rejected` reason — no new vocabulary — with a
/// message naming the contract violation). Callers convert the `Err` tuple to a `ParseError`
/// themselves (eval.mbt/matcher.mbt build `kind: KFilter` inline per `filter_arg_eval`'s precedent;
/// resolve.mbt reuses its own `filter_err`) — this function stays value-source-agnostic (no
/// argv_pos/element to carry) so both the CLI-token-consumption callers and the ladder (env)
/// caller can share it.
pub fn apply_piece_filters(
  chain : Array[String],
  raw : String,
) -> Result[String, (String, String)] {
  match apply_filter_chain(chain, VStr(raw)) {
    Ok(VStr(s)) => Ok(s)
    Ok(_) =>
      Err(
        (
          "filter_rejected", "piece_filters chain returned a non-string value (String→String contract violation, filter-definition bug)",
        ),
      )
    Err(e) => Err(e)
  }
}
