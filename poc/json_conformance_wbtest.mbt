// json_conformance_wbtest.mbt — Phase 2-① JSON-DIRECT conformance runner (stage 1: dd domain).
//
// WHAT THIS IS (and how it differs from fixture_runner_wbtest.mbt):
//   fixture_runner_wbtest.mbt hand-transcribes two dd fixtures into MoonBit literals.
//   THIS file instead READS the fixture JSON files straight off disk, decodes the
//   `definition` into the slice's own builders (opt/pos/dd_marker/build via
//   parse_definition), projects each parsed Outcome with the SAME projectors the
//   hand runner uses (proj_effects/proj_result/proj_errors via run_success/run_failure),
//   and compares against the fixture's own `expect`. The fixture JSON is the single
//   source of truth (CONFORMANCE §1 "definition は wire form"), so it no longer drifts
//   from a hand copy.
//
// STAGE 1 SCOPE (deliberately narrow — see the team plan):
//   Only the vocabulary the `dd` fixtures need is decoded:
//     - definition: options[] (name/type/short) + positionals[] (name/type)
//     - option type ∈ {dd, flag, string}; dd trigger name fixed to "--"
//     - positional type == "string"; expect.outcome ∈ {success, failure}
//   Anything richer (long spellings, env/config/variants/commands/repeat/number/help,
//   custom dd trigger names, ambiguous outcomes, non-"parse" queries) is NOT decoded:
//   the fixture is SKIPPED with a reason and counted. As later stages teach the decoder
//   more vocabulary, the skip list shrinks — the skip reasons are the stage-2 TODO list.
//
// WHY DECODE-CAPABILITY GATES THE RUN (not a directory allowlist):
//   A fixture runs iff `dec_fixture` can losslessly decode it. Lossy constructs raise
//   DecodeSkip *before* any case executes, so we never silently mis-decode (e.g. a dd
//   marker whose trigger is "++" instead of "--" is skipped rather than parsed as "--").
//   This keeps the runnable set honest and self-describing.
//
// COMPARISON MODEL (CONFORMANCE §2/§3):
//   The expected effects/result/errors are rendered into the exact spec-string grammar
//   that proj_effects/proj_result/proj_errors emit for the actual Outcome, by reusing
//   render_val / render_rval_sorted / sort_items / join_comma. So "want" and "got" are
//   produced by one grammar and compared as strings inside run_success / run_failure.
//   Mismatches are COLLECTED (file + case# + got/want) and reported all at once at the
//   end — a single failing test lists every divergence, not just the first.
//
// FIXTURES ROOT: $KUU_FIXTURES if set & existing, else a relative fallback from the
//   moon-test cwd (= poc). The justfile `test` recipe resolves $KUU_FIXTURES to the
//   sibling repo's absolute path; running bare `moon test` uses the relative fallback.
//
// Imports (moon.pkg, `for "wbtest"`): moonbitlang/x/fs, moonbitlang/core/env,
//   moonbitlang/core/json.

// ── skip signal: a fixture the current (stage-1) decoder does not support ──────

///|
suberror DecodeSkip String

// ── a decoded, runnable case ───────────────────────────────────────────────────
// A case carries the argv, the asserted outcome, and every comparison the fixture
// makes. Each `exp_*` field is Some iff the fixture asserts it — the runner compares
// ONLY what the fixture states (missing keys = no assertion, not "must be empty").
// The value-source axis (env / config / config_files) drives a resolve pass whose
// resolved bindings feed the `result` + `sources` comparisons (effects always come
// from the CLI-only parse, DR-031 cli seat).

///|
/// Per-case config injection (the value-source ladder's config seat, DR-050).
enum CfgInj {
  NoCfg // no config object (env-only or CLI-only)
  CfgObj(ConfigVal) // case `config`: the provider returns this for ANY path
  CfgFiles(Array[(String, ConfigVal)]) // case `config_files`: path → object
}

///|
struct DCase {
  argv : Array[String]
  outcome : String // "success" | "failure" | "ambiguous"
  exp_effects : String? // §2 effects (CLI-only, ordered)
  exp_result : String? // §2 result (key-sorted; resolve-filled when in resolve mode)
  exp_errors : String? // §2 failure error set
  exp_interps : Array[String]? // §3 ambiguous: the SET of interpretation result-objects
  exp_warnings : String? // DR-058 deprecation warning element set
  exp_sources : String? // DR-031 value-source tags per cell (resolve mode)
  fired_cmp : Bool // compare fired_action (failure + the key is present)
  fired_exp : String? // the asserted fired_action (None = no action fired)
  resolve : Bool // run the resolve pass (env / config / sources asserted)
  env : Map[String, String]
  cfg : CfgInj
}

///|
struct DecodedFixture {
  scope : Scope
  registry : Map[String, Node] // repeat/ref lowering templates (parse `defs`, DR-043)
  ekmap : Map[String, ExportKey] // the result-key axis map (DR-052), applied at projection time
  cases : Array[DCase]
}

///|
/// An options[] / commands[] entry decodes to EITHER a real element/command or an
/// alias declaration (`{alias: ...}`), which is routed to the Definition's aliases[]
/// (DR-057: the entry form is decided by the alias's OWN declaration).
enum DElem {
  DOpt(ElemDef)
  DAlias(AliasDef)
}

///|
enum DCmd {
  DCommand(CommandDef)
  DCmdAlias(AliasDef)
}

// ── small JSON field helpers ──────────────────────────────────────────────────

///|
fn jf_str(o : Map[String, Json], key : String) -> String? {
  match o.get(key) {
    Some(j) => j.as_string()
    None => None
  }
}

///|
/// Reject any object key outside `allowed` — the tripwire that turns an unknown
/// (= stage-2) construct into a SKIP instead of a silent mis-decode.
/// (str_in is the package's existing membership helper, installer.mbt.)
fn allowed_keys(
  o : Map[String, Json],
  allowed : Array[String],
  what : String,
) -> Unit raise DecodeSkip {
  for k, _ in o {
    if !str_in(allowed, k) {
      raise DecodeSkip(what + " has unsupported key '" + k + "'")
    }
  }
}

// ── scalar / RVal conversion — reuse the actual side's renderers for parity ─────

///|
/// A JSON scalar → the slice's Value, so render_val produces byte-identical output
/// on the expected side and the actual side.
fn json_to_value(j : Json) -> Value raise DecodeSkip {
  match j.as_bool() {
    Some(b) => return VBool(b)
    None => ()
  }
  match j.as_string() {
    Some(s) => return VStr(s)
    None => ()
  }
  match j.as_number() {
    Some(d) => return VNum(d)
    None => ()
  }
  raise DecodeSkip("non-scalar value in effects/result")
}

///|
/// A JSON value → RVal (objects/arrays/scalars), so render_rval_sorted renders the
/// expected result exactly as proj_result renders the built one (keys sorted alike).
fn json_to_rval(j : Json) -> RVal raise DecodeSkip {
  match j.as_object() {
    Some(o) => {
      let kvs : Array[(String, RVal)] = []
      for k, v in o {
        kvs.push((k, json_to_rval(v)))
      }
      return RObj(kvs)
    }
    None => ()
  }
  match j.as_array() {
    Some(a) => {
      let vs : Array[RVal] = []
      for v in a {
        vs.push(json_to_rval(v))
      }
      return RArr(vs)
    }
    None => ()
  }
  RScalar(json_to_value(j))
}

// ── expected-string builders (mirror proj_effects/proj_result/proj_errors) ──────

///|
/// CONFORMANCE §2 effects, in consumption order (NOT sorted): "entity:op(operand)@source" for a
/// `set`, "entity:op@source" for an operand-less op (default / unset / empty carry no operand,
/// DR-045). op ("set"/…) and source ("cli"/…) are verbatim — they equal eff_op / render_src output.
fn exp_effects_str(eff : Json) -> String raise DecodeSkip {
  let a = match eff.as_array() {
    Some(x) => x
    None => raise DecodeSkip("effects is not an array")
  }
  let items : Array[String] = []
  for e in a {
    let eo = match e.as_object() {
      Some(x) => x
      None => raise DecodeSkip("effect is not an object")
    }
    let entity = match jf_str(eo, "entity") {
      Some(s) => s
      None => raise DecodeSkip("effect missing 'entity'")
    }
    let op = match jf_str(eo, "op") {
      Some(s) => s
      None => raise DecodeSkip("effect missing 'op'")
    }
    let source = match jf_str(eo, "source") {
      Some(s) => s
      None => raise DecodeSkip("effect missing 'source'")
    }
    match eo.get("operand") {
      Some(j) =>
        items.push("\{entity}:\{op}(\{render_val(json_to_value(j))})@\{source}")
      None => items.push("\{entity}:\{op}@\{source}")
    }
  }
  join_comma(items)
}

///|
/// CONFORMANCE §2 result: the final object, keys sorted (render_rval_sorted matches proj_result).
fn exp_result_str(res : Json) -> String raise DecodeSkip {
  render_rval_sorted(json_to_rval(res))
}

///|
/// CONFORMANCE §2 failure: the SET of "element@argv_pos/kind" (reason intentionally NOT
/// compared — slice-unimplemented, §2 optional), sorted (matches proj_errors).
fn exp_errors_str(errs : Json) -> String raise DecodeSkip {
  let a = match errs.as_array() {
    Some(x) => x
    None => raise DecodeSkip("errors is not an array")
  }
  let items : Array[String] = []
  for e in a {
    let eo = match e.as_object() {
      Some(x) => x
      None => raise DecodeSkip("error is not an object")
    }
    // element omitted == scope-level stumble (basic.json case 4 renders "@2/parse").
    let element = match jf_str(eo, "element") {
      Some(s) => s
      None => ""
    }
    let pos = match eo.get("argv_pos") {
      Some(j) =>
        match j.as_number() {
          Some(d) => d.to_int().to_string()
          None => raise DecodeSkip("error 'argv_pos' is not a number")
        }
      None => raise DecodeSkip("error missing 'argv_pos'")
    }
    let kind = match jf_str(eo, "kind") {
      Some(s) => s
      None => raise DecodeSkip("error missing 'kind'")
    }
    items.push("\{element}@\{pos}/\{kind}")
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

// ── definition decoding ───────────────────────────────────────────────────────

///|
/// A "short" spelling: JSON string "a" → ['a']; array of strings → their chars.
/// A bool ("short": true = derive) is a stage-2 construct → skip.
fn dec_short(o : Map[String, Json]) -> Array[Char] raise DecodeSkip {
  match o.get("short") {
    None => []
    Some(j) =>
      match j.as_string() {
        Some(s) => to_chars(s)
        None =>
          match j.as_array() {
            Some(a) => {
              let cs : Array[Char] = []
              for e in a {
                match e.as_string() {
                  Some(s) =>
                    for c in to_chars(s) {
                      cs.push(c)
                    }
                  None => raise DecodeSkip("short[] element is not a string")
                }
              }
              cs
            }
            None => raise DecodeSkip("short is a bool/other (stage 2)")
          }
      }
  }
}

// ── small typed-field helpers ───────────────────────────────────────────────────

///|
fn has_key(o : Map[String, Json], k : String) -> Bool {
  match o.get(k) {
    Some(_) => true
    None => false
  }
}

///|
fn bool_field(o : Map[String, Json], k : String, dflt : Bool) -> Bool raise DecodeSkip {
  match o.get(k) {
    None => dflt
    Some(j) =>
      match j.as_bool() {
        Some(b) => b
        None => raise DecodeSkip(k + " is not a bool")
      }
  }
}

///|
fn num_int(j : Json, ctx : String) -> Int raise DecodeSkip {
  match j.as_number() {
    Some(d) => d.to_int()
    None => raise DecodeSkip(ctx + " is not a number")
  }
}

///|
/// A string or a string[] → a flat string list (env keys are declared either way).
fn dec_strs(j : Json?) -> Array[String] raise DecodeSkip {
  match j {
    None => []
    Some(x) =>
      match x.as_string() {
        Some(s) => [s]
        None =>
          match x.as_array() {
            Some(a) => {
              let r : Array[String] = []
              for e in a {
                match e.as_string() {
                  Some(s) => r.push(s)
                  None => raise DecodeSkip("string-array element is not a string")
                }
              }
              r
            }
            None => raise DecodeSkip("expected a string or string[]")
          }
      }
  }
}

///|
/// Split on ':' (the variant DSL separator). Tiny inputs, so the O(n²) concat is fine.
fn split_colon(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == ':' {
      out.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  out.push(cur)
  out
}

///|
/// A JSON value → ConfigVal (DR-050 §2 JSON-同型): what a config_provider returns.
fn json_to_configval(j : Json) -> ConfigVal {
  match j.as_object() {
    Some(o) => {
      let kvs : Array[(String, ConfigVal)] = []
      for k, v in o {
        kvs.push((k, json_to_configval(v)))
      }
      return CObj(kvs)
    }
    None => ()
  }
  match j.as_array() {
    Some(a) => {
      let vs : Array[ConfigVal] = []
      for v in a {
        vs.push(json_to_configval(v))
      }
      return CArr(vs)
    }
    None => ()
  }
  match j.as_bool() {
    Some(b) => return CBool(b)
    None => ()
  }
  match j.as_string() {
    Some(s) => return CStr(s)
    None => ()
  }
  match j.as_number() {
    Some(d) => return CNum(d)
    None => ()
  }
  CNull // JSON null → 供給なし (DR-050 §4)
}

// ── field decoders ──────────────────────────────────────────────────────────────

///|
/// Value type category of a cell. `bool`≡flag (TFlag); `float`≡number (TNum); `int`=TInt.
fn dec_ty(t : String) -> Ty raise DecodeSkip {
  match t {
    "string" => TStr
    "number" | "float" => TNum
    "int" => TInt
    "flag" | "bool" => TFlag
    other => raise DecodeSkip("value type '" + other + "'")
  }
}

///|
/// A `long` array element is EITHER a plain spelling / the `:set` main-entry descriptor (kept in
/// `long`, returns None) OR a variant DSL entry `prefix:op[:operand]` (returns the Variant, DR-011).
/// The variant trigger word is `prefix-kebab(name)` (e.g. `no:set:false` on `ssl` → `--no-ssl`).
fn dec_variant(elem : String, name : String, ty : Ty) -> Variant? raise DecodeSkip {
  if elem == ":set" {
    return None // the main-entry descriptor — a spelling, not a variant
  }
  let parts = split_colon(elem)
  if parts.length() == 1 {
    return None // a plain explicit spelling (e.g. "verbose")
  }
  let prefix = parts[0]
  let op = match parts[1] {
    "set" => Set
    "unset" => Unset
    "empty" => Empty
    "default" => Default
    other => raise DecodeSkip("variant op '" + other + "'")
  }
  let trigger = prefix + "-" + kebab(name)
  let operand : Value? = if parts.length() >= 3 {
    // typed per the cell's ty: `no:set:false` on a flag → VBool(false); `safe:set:readonly` → VStr.
    Some(env_value(ty, parts[2]))
  } else {
    None
  }
  Some({ trigger, op, operand })
}

///|
/// Decode `long`: `true` → main entry via `:set` (DR-071); `false` → no main entry; an array →
/// split into plain spellings (+ `:set`) vs variant DSL entries. Returns (long spellings, variants).
fn dec_long(
  j : Json,
  name : String,
  ty : Ty,
) -> (Array[String], Array[Variant]) raise DecodeSkip {
  match j.as_bool() {
    Some(true) => ([":set"], [])
    Some(false) => ([], [])
    None =>
      match j.as_array() {
        Some(a) => {
          let longs : Array[String] = []
          let vars : Array[Variant] = []
          for e in a {
            let s = match e.as_string() {
              Some(x) => x
              None => raise DecodeSkip("long[] element is not a string")
            }
            match dec_variant(s, name, ty) {
              Some(v) => vars.push(v)
              None => longs.push(s)
            }
          }
          (longs, vars)
        }
        None => raise DecodeSkip("long is not a bool/array")
      }
  }
}

///|
fn dec_repeat(j : Json) -> RepeatSpec raise DecodeSkip {
  let o = match j.as_object() {
    Some(x) => x
    None => raise DecodeSkip("repeat is not an object")
  }
  allowed_keys(o, ["min", "max", "lazy"], "repeat")
  let min = match o.get("min") {
    Some(m) => num_int(m, "repeat.min")
    None => 0
  }
  let max = match o.get("max") {
    Some(m) => Some(num_int(m, "repeat.max"))
    None => None
  }
  let lazy = bool_field(o, "lazy", false)
  { min, max, lazy }
}

///|
/// `multiple`: "append" preset (last-wins fold), or `{accumulator:"append", separator}`, or bool.
/// Returns (multiple?, separator?).
fn dec_multiple(j : Json) -> (Bool, String?) raise DecodeSkip {
  match j.as_bool() {
    Some(b) => return (b, None)
    None => ()
  }
  match j.as_string() {
    Some("append") => return (true, None)
    Some(other) => raise DecodeSkip("multiple preset '" + other + "'")
    None => ()
  }
  match j.as_object() {
    Some(o) => {
      allowed_keys(o, ["accumulator", "separator"], "multiple")
      match jf_str(o, "accumulator") {
        Some("append") => ()
        Some(a) => raise DecodeSkip("multiple.accumulator '" + a + "'")
        None => ()
      }
      (true, jf_str(o, "separator"))
    }
    None => raise DecodeSkip("multiple is not a bool/string/object")
  }
}

///|
/// `export_key` (DR-052): null / "" → EkNull (no result key); a string → EkKey (rename).
fn dec_export(j : Json) -> ExportKey {
  match j.as_string() {
    Some("") => EkNull
    Some(s) => EkKey(s)
    None => EkNull // JSON null
  }
}

///|
/// An alias declaration (DR-057), from an options[]/commands[] entry carrying an `alias` key.
fn dec_alias(o : Map[String, Json]) -> AliasDef raise DecodeSkip {
  // `type` is allowed (a command alias carries type:"command"); it does not affect the decode.
  allowed_keys(o, ["alias", "name", "short", "long", "deprecated", "type"], "alias")
  let target = match jf_str(o, "alias") {
    Some(t) => t
    None => raise DecodeSkip("alias missing target")
  }
  let name = jf_str(o, "name")
  let short = dec_short(o)
  let long_override : Array[String]? = match o.get("long") {
    Some(lj) =>
      match lj.as_array() {
        Some(a) => {
          let ls : Array[String] = []
          for e in a {
            match e.as_string() {
              Some(s) => ls.push(s)
              None => raise DecodeSkip("alias long[] element is not a string")
            }
          }
          Some(ls)
        }
        None =>
          match lj.as_bool() {
            Some(true) => Some([":set"])
            Some(false) => Some([])
            None => raise DecodeSkip("alias long is not a bool/array")
          }
      }
    None => None
  }
  let deprecated = bool_field(o, "deprecated", false)
  { target, name, short, long_override, deprecated }
}

///|
fn dec_option(j : Json) -> DElem raise DecodeSkip {
  let o = match j.as_object() {
    Some(x) => x
    None => raise DecodeSkip("option is not an object")
  }
  if has_key(o, "alias") {
    return DAlias(dec_alias(o))
  }
  allowed_keys(
    o,
    [
      "id", "name", "type", "long", "short", "env", "default", "global", "inherit",
      "inheritable", "multiple", "separator", "requires", "conflicts_with",
      "exclusive_group", "export_key", "config_key", "deprecated", "or",
    ],
    "option",
  )
  // `or` (DR-055 §1 / §5.3 values-enum): the value枝 list. Its branches carry the value-conditional
  // requires (a `json`枝 with requires:[schema] → value_requires ("json", ["schema"])). A value option
  // written with `or` omits `type` (the exact枝 values are strings) → default to "string".
  let value_requires = match o.get("or") {
    Some(orj) => dec_or(orj)
    None => []
  }
  let tystr = match jf_str(o, "type") {
    Some(t) => t
    None =>
      if has_key(o, "or") {
        "string"
      } else {
        raise DecodeSkip("option missing 'type'")
      }
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("option missing 'name'")
  }
  // dd: the trigger spelling is the element's name (DR-064 §5); a dialect name ("++") is honored.
  if tystr == "dd" {
    return DOpt({ ..dd_marker(), name })
  }
  // help / version (DR-048): a failure-action FLAG. config_file (DR-050): a TStr path cell.
  let (ty, fail_action, config_file) = match tystr {
    "help" => (TFlag, true, false)
    "config_file" => (TStr, false, true)
    _ => (dec_ty(tystr), false, false)
  }
  let (longs, vars) = match o.get("long") {
    Some(lj) => dec_long(lj, name, ty)
    None => ([], [])
  }
  let short = dec_short(o)
  let env = dec_strs(o.get("env"))
  let default = match o.get("default") {
    Some(d) => Some(json_to_value(d))
    None => None
  }
  let global = bool_field(o, "global", false)
  let inherit = bool_field(o, "inherit", false)
  let inheritable = bool_field(o, "inheritable", false)
  let (multiple, sep) = match o.get("multiple") {
    Some(m) => dec_multiple(m)
    None => (false, None)
  }
  let requires = dec_strs(o.get("requires"))
  let conflicts = dec_strs(o.get("conflicts_with"))
  let exclusive = dec_strs(o.get("exclusive_group"))
  let export = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  let config_key : Array[String]? = match o.get("config_key") {
    Some(c) => Some(dec_strs(Some(c)))
    None => None
  }
  let deprecated = bool_field(o, "deprecated", false)
  // opt() has no separator/deprecated params; set them by struct update (DR-034 / DR-058).
  DOpt({
    ..opt(
      name,
      ty,
      long=longs,
      variants=vars,
      short=short,
      env~,
      global~,
      inherit~,
      inheritable~,
      multiple~,
      fail_action~,
      config_file~,
      config_key~,
      export=export,
      requires~,
      conflicts~,
      exclusive~,
      value_requires~,
      default~,
    ),
    separator: sep,
    deprecated,
  })
}

///|
/// Decode an option's `or` value枝 list (DR-055 §1 / DESIGN §9.3 / §5.3 values-enum) into the slice's
/// value_requires ((exact値 → required targets)). Each branch is `{exact, id?, requires?}`: `exact` is
/// the matched value, `requires` (if present) lowers to a value-conditional predicate the slice models
/// as CRequiresIf (phase25). A branch with no `requires` (e.g. a plain `yaml`枝) contributes nothing.
/// LOSSY NOTE: the枝 `id` (DR-052 orthogonal id naming the anonymous exact枝) is NOT representable — the
/// slice attributes the constraint element to the parent NAME, so an id-bearing requires枝 produces a
/// known element-name divergence (frozen in the ledger). The enum-membership restriction (only the
/// listed values accepted) is also not modeled — the slice keeps a permissive TStr cell; this is
/// lossless for the current fixtures because no case supplies an out-of-enum value.
fn dec_or(j : Json) -> Array[(String, Array[String])] raise DecodeSkip {
  let a = match j.as_array() {
    Some(x) => x
    None => raise DecodeSkip("or is not an array")
  }
  let vrs : Array[(String, Array[String])] = []
  for e in a {
    let bo = match e.as_object() {
      Some(x) => x
      None => raise DecodeSkip("or branch is not an object")
    }
    allowed_keys(bo, ["exact", "id", "requires"], "or branch")
    let exact = match jf_str(bo, "exact") {
      Some(s) => s
      None => raise DecodeSkip("or branch missing 'exact' (only exact value枝 supported)")
    }
    let reqs = dec_strs(bo.get("requires"))
    if reqs.length() > 0 {
      vrs.push((exact, reqs))
    }
  }
  vrs
}

///|
/// Decode a positional. A `positionals` sub-array is a NESTED-GROUP positional (DR-043 repeat over a
/// sub-sequence): the group `xs` repeats an inner element `k` whose name differs from the array label
/// and may carry its own export_key. The slice's Definition/ElemDef model is FLAT — lower_positional
/// lowers a repeat positional to a Ref-recursion whose head binds the positional's OWN name
/// (label == head), with no field for a distinctly-named inner element or its export_key. The
/// evaluator supports the shape as a MANUALLY built IdxRepeat(label, distinct-head, min) (phase22),
/// but parse_definition — the runner's §5 contract path — cannot construct it. No builder → skip.
fn dec_positional(j : Json) -> ElemDef raise DecodeSkip {
  let o = match j.as_object() {
    Some(x) => x
    None => raise DecodeSkip("positional is not an object")
  }
  if has_key(o, "positionals") {
    raise DecodeSkip(
      "nested-group positional (repeat over a named sub-sequence): slice ElemDef is flat, parse_definition builds no IdxRepeat with a distinct inner-element name/export_key",
    )
  }
  allowed_keys(
    o,
    [
      "id", "name", "type", "repeat", "optional", "multiple", "separator",
      "export_key", "config_key", "default",
    ],
    "positional",
  )
  // a positional's type defaults to string when omitted (export-key/transparent-seq spine).
  let ty = match jf_str(o, "type") {
    Some(t) => dec_ty(t)
    None => TStr
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("positional missing 'name'")
  }
  let repeat : RepeatSpec? = match o.get("repeat") {
    Some(r) => Some(dec_repeat(r))
    None => None
  }
  let optional = bool_field(o, "optional", false)
  let (multiple, sep) = match o.get("multiple") {
    Some(m) => dec_multiple(m)
    None => (false, None)
  }
  let export = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  let config_key : Array[String]? = match o.get("config_key") {
    Some(c) => Some(dec_strs(Some(c)))
    None => None
  }
  let default = match o.get("default") {
    Some(d) => Some(json_to_value(d))
    None => None
  }
  pos(
    name,
    ty,
    repeat=repeat,
    optional~,
    multiple~,
    separator=sep,
    config_key~,
    export=export,
    default~,
  )
}

///|
/// Decode a commands[] entry: EITHER a subcommand (a fresh backbone scope, DR-041 §4) or a command
/// alias (`{alias, type:"command", name}`). The command body's options/positionals/commands are
/// INLINED into the entry object (the fixture wire form), recursed via dec_definition.
fn dec_command(j : Json) -> DCmd raise DecodeSkip {
  let o = match j.as_object() {
    Some(x) => x
    None => raise DecodeSkip("command is not an object")
  }
  if has_key(o, "alias") {
    return DCmdAlias(dec_alias(o))
  }
  allowed_keys(
    o,
    ["type", "name", "options", "positionals", "commands", "export_key"],
    "command",
  )
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("command missing 'name'")
  }
  let body = dec_definition(o)
  let export = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => EkUnset
  }
  DCommand({ name, body, export_key: export })
}

///|
/// Build a Definition from an object's options[] / positionals[] / commands[]. Alias entries in
/// options[] or commands[] are ROUTED to aliases[] (DR-057: the entry decides its own form).
fn dec_definition(o : Map[String, Json]) -> Definition raise DecodeSkip {
  let options : Array[ElemDef] = []
  let positionals : Array[ElemDef] = []
  let commands : Array[CommandDef] = []
  let aliases : Array[AliasDef] = []
  match o.get("options") {
    Some(arr) => {
      let a = match arr.as_array() {
        Some(x) => x
        None => raise DecodeSkip("options is not an array")
      }
      for oj in a {
        match dec_option(oj) {
          DOpt(e) => options.push(e)
          DAlias(al) => aliases.push(al)
        }
      }
    }
    None => ()
  }
  match o.get("positionals") {
    Some(arr) => {
      let a = match arr.as_array() {
        Some(x) => x
        None => raise DecodeSkip("positionals is not an array")
      }
      for pj in a {
        positionals.push(dec_positional(pj))
      }
    }
    None => ()
  }
  match o.get("commands") {
    Some(arr) => {
      let a = match arr.as_array() {
        Some(x) => x
        None => raise DecodeSkip("commands is not an array")
      }
      for cj in a {
        match dec_command(cj) {
          DCommand(c) => commands.push(c)
          DCmdAlias(al) => aliases.push(al)
        }
      }
    }
    None => ()
  }
  { options, positionals, commands, aliases }
}

///|
fn dec_argv(cj : Map[String, Json]) -> Array[String] raise DecodeSkip {
  let aj = match cj.get("argv") {
    Some(x) => x
    None => raise DecodeSkip("case missing 'argv'")
  }
  let a = match aj.as_array() {
    Some(x) => x
    None => raise DecodeSkip("argv is not an array")
  }
  let out : Array[String] = []
  for t in a {
    match t.as_string() {
      Some(s) => out.push(s)
      None => raise DecodeSkip("argv element is not a string")
    }
  }
  out
}

// ── expect-side projections (mirror the slice's outcome renderers) ──────────────

///|
/// §3 ambiguous: the SET of interpretation result-objects, each rendered like proj_result
/// (key-sorted). Sorted so the comparison is order-independent (interpretation order non-normative).
fn dec_interps(j : Json) -> Array[String] raise DecodeSkip {
  let a = match j.as_array() {
    Some(x) => x
    None => raise DecodeSkip("interpretations is not an array")
  }
  let out : Array[String] = []
  for e in a {
    out.push(render_rval_sorted(json_to_rval(e)))
  }
  sort_items(out)
  out
}

///|
/// DR-058 warnings: the fixture lists `{element, kind:"deprecated"}`; the slice's warnings_of
/// yields the element NAME per deprecation. Compared as a sorted element set.
fn exp_warnings_str(j : Json) -> String raise DecodeSkip {
  let a = match j.as_array() {
    Some(x) => x
    None => raise DecodeSkip("warnings is not an array")
  }
  let items : Array[String] = []
  for e in a {
    let eo = match e.as_object() {
      Some(x) => x
      None => raise DecodeSkip("warning is not an object")
    }
    match jf_str(eo, "element") {
      Some(el) => items.push(el)
      None => raise DecodeSkip("warning missing 'element'")
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
/// DR-031 sources: the fixture maps `cell → value-source tag`. A key is scope-path-qualified — root
/// cells are bare (`ttl`), nested-scope cells are dotted (`sub.ttl`, CONFORMANCE §2). Rendered as a
/// sorted "cell=src" set; proj_sources_tree emits the matching qualified form from the resolve tree.
fn exp_sources_str(j : Json) -> String raise DecodeSkip {
  let o = match j.as_object() {
    Some(x) => x
    None => raise DecodeSkip("sources is not an object")
  }
  let items : Array[String] = []
  for k, v in o {
    let src = match v.as_string() {
      Some(s) => s
      None => raise DecodeSkip("source value is not a string")
    }
    items.push(k + "=" + src)
  }
  sort_items(items)
  join_comma(items)
}

///|
/// The resolved value-source tag per cell (DR-031), from a resolve pass's bindings. A cell present
/// in the resolved bindings takes that binding's source; a FLAG with only its preset default (not
/// run through the ladder, LOWERING §A.5) reports "default". config_file infra cells are excluded.
fn proj_sources(sc : Scope, resolved : Array[Binding]) -> String {
  let items : Array[String] = []
  for e in sc.entities {
    if e.is_config_file {
      continue
    }
    let mut src : String? = None
    for b in resolved {
      if b.key == e.name && not(is_sentinel(b.key)) {
        src = Some(render_src(b.source))
      }
    }
    match src {
      Some(s) => items.push(e.name + "=" + s)
      None =>
        if e.ty == TFlag && e.accum.is_none() {
          match e.default_value {
            Some(_) => items.push(e.name + "=default")
            None => ()
          }
        }
    }
  }
  sort_items(items)
  join_comma(items)
}

///|
fn proj_warnings(o : Outcome) -> String {
  let ws = warnings_of(o)
  sort_items(ws)
  join_comma(ws)
}

///|
fn is_config_file_cell(sc : Scope, name : String) -> Bool {
  for e in sc.entities {
    if e.name == name && e.is_config_file {
      return true
    }
  }
  false
}

///|
/// §2 CLI effects, EXCLUDING config_file infra cells — a config_file element's CLI path binding is
/// not a parse effect (it resolves the provider, DR-050), so the fixture omits it from `effects`.
fn proj_effects_ex(sc : Scope, binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if is_sentinel(b.key) {
      continue
    }
    if is_config_file_cell(sc, b.key) {
      continue
    }
    // operand belongs to `set` only; default/unset/empty render operand-less (DR-045, matches
    // the fixture's operand-less effect form — the placeholder VBool(false) is not surfaced).
    match b.op {
      Set =>
        items.push(
          "\{b.key}:set(\{render_val(b.value)})@\{render_src(b.source)}",
        )
      _ => items.push("\{b.key}:\{eff_op(b.op)}@\{render_src(b.source)}")
    }
  }
  join_comma(items)
}

///|
/// Result with the DR-052 result-key axis applied (rename / drop / scope-promote), key-sorted.
fn proj_result_export(
  sc : Scope,
  binds : Array[Binding],
  ekmap : Map[String, ExportKey],
) -> String {
  render_rval_sorted(
    build_result(
      apply_export_keys(binds, ekmap),
      accum_cells(sc),
      apply_export_to_defaults(default_cells(sc), ekmap),
      [],
    ),
  )
}

// ── resolve dispatch (value-source ladder, DR-031/050) ──────────────────────────

///|
fn cfg_lookup(files : Array[(String, ConfigVal)], p : String) -> ConfigVal? {
  for kv in files {
    if kv.0 == p {
      return Some(kv.1)
    }
  }
  None
}

///|
/// Run the resolve pass for a case: env-only (resolve_scope) or with a config seat
/// (resolve_scope_config). Returns the resolved ladder bindings, or a resolve error.
fn do_resolve(
  sc : Scope,
  cli : Array[Binding],
  dc : DCase,
) -> Result[Array[Binding], String] {
  match dc.cfg {
    NoCfg => Ok(resolve_scope(sc, cli, dc.env))
    CfgObj(obj) =>
      resolve_scope_config(sc, cli, dc.env, fn(_p) { Some(obj) })
    CfgFiles(files) =>
      resolve_scope_config(sc, cli, dc.env, fn(p) { cfg_lookup(files, p) })
  }
}

///|
/// Whether a scope owns any command sub-scope (a CmdSat greedy resident, DR-018/041 §4).
fn has_commands(sc : Scope) -> Bool {
  for g in sc.greedy {
    match g {
      CmdSat(_, _) => return true
      _ => ()
    }
  }
  false
}

///|
/// Resolve a scope TREE end-to-end, threading the value-source ladder across command scopes (DR-031
/// #4 inherit席 / DR-059 inheritable). The slice's resolve primitives are scope-local (resolve_scope
/// + inherited_of, composed manually per scope in phase3/27); this bridges them into the single-argv
/// conformance path. Each scope resolves down cli>env>config>inherit>default over the bindings that
/// landed in it (parse tags every binding with its scope path); the resolved values seat the inherit
/// lookup of its command children (nearest-ancestor wins). Returns every resolved binding re-tagged
/// with its scope path, so build_result nests the result and proj_sources_tree qualifies the sources.
fn resolve_tree(
  sc : Scope,
  binds : Array[Binding],
  dc : DCase,
  path : Array[String],
  inherited : Map[String, Value],
) -> Result[Array[Binding], String] {
  // bindings that landed in THIS scope (exact full-path match; resolve matches cells by name).
  let here : Array[Binding] = []
  for b in binds {
    if path_eq(b.scope, path) {
      here.push(b)
    }
  }
  let resolved = match dc.cfg {
    NoCfg => resolve_scope(sc, here, dc.env, inherited~)
    CfgObj(obj) =>
      match
        resolve_scope_config(
          sc, here, dc.env, fn(_p) { Some(obj) }, path~, inherited~,
        ) {
        Ok(rb) => rb
        Err(m) => return Err(m)
      }
    CfgFiles(files) =>
      match
        resolve_scope_config(
          sc, here, dc.env, fn(p) { cfg_lookup(files, p) }, path~, inherited~,
        ) {
        Ok(rb) => rb
        Err(m) => return Err(m)
      }
  }
  let out : Array[Binding] = []
  // carry the parse's presence markers ("{}" / "[]") for THIS scope forward, so an entered-but-empty
  // scope still renders (the marker sits at scope==path; resolve_scope drops it, so re-inject it).
  for b in here {
    if is_sentinel(b.key) {
      out.push(b)
    }
  }
  for b in resolved {
    out.push({ ..b, scope: path })
  }
  // child inherit context = ancestor context ∪ this scope's resolved values (nearer scope wins).
  let child_inherited : Map[String, Value] = Map::new()
  for k, v in inherited {
    child_inherited.set(k, v)
  }
  for b in resolved {
    child_inherited.set(b.key, b.value)
  }
  // recurse ONLY into command scopes the parse actually ENTERED (a "{}" marker sits at the child's
  // path). An un-entered scope is not resolved — its cells must not appear in the result / sources.
  for g in sc.greedy {
    match g {
      CmdSat(name, child) => {
        let childpath = path_push(path, name)
        if scope_entered(binds, childpath) {
          match resolve_tree(child, binds, dc, childpath, child_inherited) {
            Ok(rb) =>
              for b in rb {
                out.push(b)
              }
            Err(m) => return Err(m)
          }
        }
      }
      _ => ()
    }
  }
  Ok(out)
}

///|
/// Whether the parse ENTERED the scope at `path` — a presence marker (or any binding) sits exactly
/// at that path (mark_scope prepends a "{}" marker on every command entry, eval.mbt).
fn scope_entered(binds : Array[Binding], path : Array[String]) -> Bool {
  for b in binds {
    if path_eq(b.scope, path) {
      return true
    }
  }
  false
}

///|
/// Scope-path-qualified value-source tags from the resolve tree (DR-031, CONFORMANCE §2 dotted keys):
/// a root cell is bare (`ttl`), a nested-scope cell is dotted (`sub.ttl`). Mirrors proj_sources but
/// reads the re-tagged tree bindings directly (each carries its scope path). config_file infra cells
/// never appear here (resolve_scope_config drops them from its output; the flat resolve_scope path is
/// only reached for scopes without config, and the cross-scope fixtures declare no config_file cell).
fn proj_sources_tree(resolved : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in resolved {
    if is_sentinel(b.key) {
      continue
    }
    let mut key = ""
    for seg in b.scope {
      key = key + seg + "."
    }
    key = key + b.key
    items.push(key + "=" + render_src(b.source))
  }
  sort_items(items)
  join_comma(items)
}

// ── case + fixture decoding ─────────────────────────────────────────────────────

///|
/// Decode one case: its argv, asserted outcome, every comparison the fixture makes, and the
/// value-source injection (env / config). A cross-scope source key raises DecodeSkip (stage-3 gap).
fn dec_case(cj : Json) -> DCase raise DecodeSkip {
  let co = match cj.as_object() {
    Some(x) => x
    None => raise DecodeSkip("case is not an object")
  }
  let argv = dec_argv(co)
  let expect = match co.get("expect") {
    Some(e) => e
    None => raise DecodeSkip("case missing 'expect'")
  }
  let eo = match expect.as_object() {
    Some(x) => x
    None => raise DecodeSkip("expect is not an object")
  }
  let outcome = match jf_str(eo, "outcome") {
    Some(o) =>
      if o == "success" || o == "failure" || o == "ambiguous" {
        o
      } else {
        raise DecodeSkip("outcome '" + o + "'")
      }
    None => raise DecodeSkip("expect missing 'outcome'")
  }
  // value-source injection (case env / config / config_files).
  let env : Map[String, String] = Map::new()
  match co.get("env") {
    Some(ej) => {
      let eobj = match ej.as_object() {
        Some(x) => x
        None => raise DecodeSkip("case env is not an object")
      }
      for k, v in eobj {
        match v.as_string() {
          Some(s) => env.set(k, s)
          None => raise DecodeSkip("case env value is not a string")
        }
      }
    }
    None => ()
  }
  let cfg = match co.get("config") {
    Some(cjj) => CfgObj(json_to_configval(cjj))
    None =>
      match co.get("config_files") {
        Some(fj) =>
          match fj.as_object() {
            Some(fo) => {
              let files : Array[(String, ConfigVal)] = []
              for k, v in fo {
                files.push((k, json_to_configval(v)))
              }
              CfgFiles(files)
            }
            None => NoCfg // config_files: null
          }
        None => NoCfg
      }
  }
  let has_sources = has_key(eo, "sources")
  let resolve = has_sources ||
    has_key(co, "env") ||
    (match cfg {
      NoCfg => false
      _ => true
    })
  let exp_effects = match eo.get("effects") {
    Some(x) => Some(exp_effects_str(x))
    None => None
  }
  let exp_result = match eo.get("result") {
    Some(x) => Some(exp_result_str(x))
    None => None
  }
  let exp_errors = match eo.get("errors") {
    Some(x) => Some(exp_errors_str(x))
    None => None
  }
  let exp_interps = match eo.get("interpretations") {
    Some(x) => Some(dec_interps(x))
    None => None
  }
  let exp_warnings = match eo.get("warnings") {
    Some(x) => Some(exp_warnings_str(x))
    None => None
  }
  let exp_sources = if has_sources {
    Some(exp_sources_str(eo.get("sources").unwrap()))
  } else {
    None
  }
  // fired_action (DR-048) is a FailureData field — only asserted on a failure outcome.
  let (fired_cmp, fired_exp) = if outcome == "failure" && has_key(eo, "fired_action") {
    (true, jf_str(eo, "fired_action")) // string → Some; JSON null → None (no action)
  } else {
    (false, None)
  }
  {
    argv,
    outcome,
    exp_effects,
    exp_result,
    exp_errors,
    exp_interps,
    exp_warnings,
    exp_sources,
    fired_cmp,
    fired_exp,
    resolve,
    env,
    cfg,
  }
}

///|
/// Decode a whole fixture (definition + every case) up front. Any unsupported construct raises
/// DecodeSkip, so the fixture is skipped atomically — no case runs against a mis-decoded definition.
/// The FULL installer chain is applied; parse_definition is order-independent (DR-042), so passing
/// every installer just means each collects its own vocab (unused vocab installers add nothing).
fn dec_fixture(j : Json) -> DecodedFixture raise DecodeSkip {
  let top = match j.as_object() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  match jf_str(top, "query") {
    Some("parse") => ()
    Some(q) => raise DecodeSkip("query '" + q + "' (stage 2: 'parse' only)")
    None => raise DecodeSkip("missing 'query'")
  }
  let defj = match top.get("definition") {
    Some(d) => d
    None => raise DecodeSkip("missing 'definition'")
  }
  let defo = match defj.as_object() {
    Some(o) => o
    None => raise DecodeSkip("definition is not an object")
  }
  allowed_keys(defo, ["options", "positionals", "commands"], "definition")
  let def = dec_definition(defo)
  // parse_definition POPULATES `registry` with repeat/ref lowering templates; the same map is fed
  // to parse() as `defs` so Ref tails resolve (DR-043). build_export_map reads the result-key axis.
  let registry : Map[String, Node] = Map::new()
  let scope = match parse_definition(def, full_installers(), registry~) {
    Ok(sc) => sc
    Err(errs) => raise DecodeSkip("definition rejected: " + deferrs_str(errs))
  }
  let ekmap = build_export_map(def)
  let casesj = match top.get("cases") {
    Some(c) => c
    None => raise DecodeSkip("missing 'cases'")
  }
  let carr = match casesj.as_array() {
    Some(x) => x
    None => raise DecodeSkip("cases is not an array")
  }
  let cases : Array[DCase] = []
  for cj in carr {
    cases.push(dec_case(cj))
  }
  { scope, registry, ekmap, cases }
}

///|
/// The canonical full installer chain (DR-042 §canonical set + DR-043/050/055/057/059).
fn full_installers() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst, ConstraintInst, AliasInst, InheritableInst,
  ]
}

// ── fixtures discovery (fs walk) ──────────────────────────────────────────────

///|
fn is_json_file(name : String) -> Bool {
  let cs = to_chars(name)
  let n = cs.length()
  n >= 5 &&
  cs[n - 5] == '.' &&
  cs[n - 4] == 'j' &&
  cs[n - 3] == 's' &&
  cs[n - 2] == 'o' &&
  cs[n - 1] == 'n'
}

///|
/// Resolve the fixtures root: $KUU_FIXTURES (if set & existing) else a relative
/// fallback from the moon-test cwd (= poc). Aborts with guidance if none resolves.
fn fixtures_root() -> String {
  match @env.get_env_var("KUU_FIXTURES") {
    Some(p) => if p != "" && @fs.path_exists(p) { return p }
    None => ()
  }
  for cand in [
    "../../../kuu/main/fixtures", "../../kuu/main/fixtures",
    "../../../../kuu/main/fixtures",
  ] {
    if @fs.path_exists(cand) {
      return cand
    }
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "?"
  }
  abort(
    "fixtures root not found (set KUU_FIXTURES to kuu/main/fixtures); cwd=" + cwd,
  )
}

///|
/// Collect *.json paths (as root-relative strings) by recursive walk.
fn collect_rel(root : String, rel : String, out : Array[String]) -> Unit raise {
  let dir = if rel == "" { root } else { root + "/" + rel }
  for name in @fs.read_dir(dir) {
    let r = if rel == "" { name } else { rel + "/" + name }
    let p = root + "/" + r
    if @fs.is_dir(p) {
      collect_rel(root, r, out)
    } else if is_json_file(name) {
      out.push(r)
    }
  }
}

// ── the runner ────────────────────────────────────────────────────────────────

///|
/// Whether a FLAT scope carries a non-flag default that only the value-source ladder can surface.
/// collect_defaults injects flag presets (LOWERING §A.5) but leaves a non-flag default ladder-resolved
/// (result.mbt), so a scope like `{format default "json", key_file default "/id.key"}` needs the resolve
/// pass to render those defaults even with an empty CLI. Nested scopes (any CmdSat child) are excluded:
/// resolve_scope resolves only the ROOT scope's entities and would flatten the command nesting, so those
/// stay on the CLI-parse projection (cross-scope ladder threading is a separate gap).
fn scope_needs_default_ladder(sc : Scope) -> Bool {
  for g in sc.greedy {
    match g {
      CmdSat(_, _) => return false
      _ => ()
    }
  }
  for e in sc.entities {
    if e.ty != TFlag && e.default_value.is_some() {
      return true
    }
  }
  false
}

///|
/// Run one decoded case against the built scope. Compares ONLY the assertions the fixture makes
/// (effects/result/errors/sources/warnings/fired_action/interpretations). Returns "PASS" or a
/// "field got=… want=…" diff (all divergences for the case joined). effects come from the CLI-only
/// parse; result/sources come from the resolve pass when the case injects env/config (DR-031).
fn run_case(df : DecodedFixture, dc : DCase) -> String {
  let sc = df.scope
  let outcome = parse(ScopeNode(sc), dc.argv, defs=df.registry)
  let problems : Array[String] = []
  // A non-flag default surfaces in the result ONLY via the value-source ladder (collect_defaults
  // injects flag presets; a non-flag default is ladder-resolved, result.mbt). So a flat scope with a
  // non-flag default runs resolve even without env/config/sources — else the default is dropped.
  let use_resolve = dc.resolve || scope_needs_default_ladder(sc)
  match dc.outcome {
    "success" =>
      match outcome {
        Success(binds) => {
          match dc.exp_effects {
            Some(ee) => {
              let ae = proj_effects_ex(sc, binds)
              if ae != ee {
                problems.push("effects got=\{ae} want=\{ee}")
              }
            }
            None => ()
          }
          if dc.resolve && has_commands(sc) {
            // CROSS-SCOPE ladder (DR-031 #4 / DR-059): a command tree threads each scope's resolved
            // values down to its children as the inherit席 context. resolve_tree re-tags bindings with
            // their scope path so build_result nests the result and proj_sources_tree qualifies the
            // source keys (dotted `sub.ttl`). The flat resolve_scope alone cannot thread parent→child.
            match resolve_tree(sc, binds, dc, [], Map::new()) {
              Ok(rb) => {
                match dc.exp_result {
                  Some(er) => {
                    let ar = proj_result_export(sc, rb, df.ekmap)
                    if ar != er {
                      problems.push("result got=\{ar} want=\{er}")
                    }
                  }
                  None => ()
                }
                match dc.exp_sources {
                  Some(es) => {
                    let asr = proj_sources_tree(rb)
                    if asr != es {
                      problems.push("sources got=\{asr} want=\{es}")
                    }
                  }
                  None => ()
                }
              }
              Err(msg) => problems.push("resolve error: " + msg)
            }
          } else if use_resolve {
            match do_resolve(sc, binds, dc) {
              Ok(rb) => {
                match dc.exp_result {
                  Some(er) => {
                    let ar = proj_result_export(sc, rb, df.ekmap)
                    if ar != er {
                      problems.push("result got=\{ar} want=\{er}")
                    }
                  }
                  None => ()
                }
                match dc.exp_sources {
                  Some(es) => {
                    let asr = proj_sources(sc, rb)
                    if asr != es {
                      problems.push("sources got=\{asr} want=\{es}")
                    }
                  }
                  None => ()
                }
              }
              Err(msg) => problems.push("resolve error: " + msg)
            }
          } else {
            match dc.exp_result {
              Some(er) => {
                let ar = proj_result_export(sc, binds, df.ekmap)
                if ar != er {
                  problems.push("result got=\{ar} want=\{er}")
                }
              }
              None => ()
            }
          }
          match dc.exp_warnings {
            Some(ew) => {
              let aw = proj_warnings(outcome)
              if aw != ew {
                problems.push("warnings got=\{aw} want=\{ew}")
              }
            }
            None => ()
          }
        }
        other => problems.push("EXPECTED-SUCCESS got=" + render_outcome(other))
      }
    "failure" =>
      match outcome {
        Failure(d) => {
          match dc.exp_errors {
            Some(ex) => {
              let ae = proj_errors(d.errors)
              if ae != ex {
                problems.push("errors got=\{ae} want=\{ex}")
              }
            }
            None => ()
          }
          if dc.fired_cmp {
            let got = match d.fired_action {
              Some(s) => s
              None => "(none)"
            }
            let want = match dc.fired_exp {
              Some(s) => s
              None => "(none)"
            }
            if got != want {
              problems.push("fired_action got=\{got} want=\{want}")
            }
          }
        }
        other => problems.push("EXPECTED-FAILURE got=" + render_outcome(other))
      }
    _ =>
      // ambiguous — each interpretation is a raw complete-path result-object (NO flag preset
      // defaults injected: an unfired flag is simply absent in that interpretation, DR-053 §3).
      match outcome {
        Ambiguous(d) =>
          match dc.exp_interps {
            Some(ei) => {
              let got : Array[String] = []
              for interp in d.interpretations {
                got.push(
                  render_rval_sorted(
                    build_result(
                      apply_export_keys(interp, df.ekmap),
                      accum_cells(sc),
                      [],
                      [],
                    ),
                  ),
                )
              }
              sort_items(got)
              let ag = join_comma(got)
              let ew = join_comma(ei)
              if ag != ew {
                problems.push("interpretations got=[\{ag}] want=[\{ew}]")
              }
            }
            None => ()
          }
        other => problems.push("EXPECTED-AMBIGUOUS got=" + render_outcome(other))
      }
  }
  if problems.length() == 0 {
    "PASS"
  } else {
    let sb = StringBuilder::new()
    let mut first = true
    for p in problems {
      if not(first) {
        sb.write_string(" | ")
      }
      sb.write_string(p)
      first = false
    }
    sb.to_string()
  }
}

///|
/// The FROZEN divergence ledger (fixture = 正本, slice = 被検体). Each entry is a `rel::case#N`
/// key whose comparison currently diverges — a KNOWN gap (slice-unimplemented) or a suspected
/// fixture authoring issue. The runner asserts the observed divergence SET equals this ledger:
/// an UNEXPECTED divergence (regression / newly-decoded fixture that diverges) OR a VANISHED one
/// (a gap got closed but the ledger was not updated) both fail the test. Expected-value edits to
/// make the slice pass are禁止 — the fixture is authoritative; divergences stay visible here.
fn known_divergences() -> Array[String] {
  [
    // held-error gap (DR-053 §2): a min-unmet repeat / positional leaves no held ParseError, so the
    // failure error SET is empty where the fixture asserts a `kind:parse` held error. slice gap.
    "repeat-parse/min2-standalone.json::case#1",
    "path-search/complete-path-count.json::case#3",
    // double-receptacle 取り分 (DR-043): two adjacent min:0 repeats (xs*, ys*). The fixture now asserts
    // DR-043 greedy取り分 (left-longest → success 1本: 0/1 tokens fill xs and leave ys empty, 2 tokens
    // → xs=[a,b],ys=[]). The slice's phase10 model has NOT implemented DR-043取り分 preference for
    // adjacent min:0 repeats: case#1/#2 (0/1 token) yield `no complete parse` (a min:0 repeat is not
    // allowed to stay empty when another repeat is present), and case#3 (2 tokens) yields a balanced
    // split {xs=[a],ys=[b]} instead of the greedy-longest. slice gap (取り分 preference unimplemented).
    // NB: the fixture's greedy DIRECTION (left- vs right-longest) is itself unsettled upstream
    // (kuu DR-043「未決着 — 取り分の向き」); if it flips, case#3's want reverses but the gap persists.
    "path-search/ambiguous-receptacles.json::case#1",
    "path-search/ambiguous-receptacles.json::case#2",
    "path-search/ambiguous-receptacles.json::case#3",
    // export-key collision (DESIGN §15.5): two elements share export_key "x". The fixture models the
    // collision as an AMBIGUOUS outcome; the slice returns Success (collision is a separate check,
    // not surfaced as an outcome). slice gap.
    "export-key/collision.json::case#1",
    // transparent-kv sole-binding (DR-052 §2): an EkNull value that is the ONLY real binding promotes
    // to a scalar instead of dropping (the slice's phase22 only covers the co-fired-sibling case).
    // slice gap surfaced by the fixture.
    "export-key/transparent-kv.json::case#2",
    // value枝 id attribution (DR-052 直交 id / DR-055 §1): the `or` value枝 `{exact:json, id:fmt_json,
    // requires:[schema]}` lowers to a value_requires (json → [schema]) whose CRequiresIf carries the
    // PARENT element name `format`, not the枝 id `fmt_json` — the slice's ElemDef has no place to name
    // an anonymous exact枝, so a constraint violation reports element=format where the fixture asserts
    // element=fmt_json. slice gap (value-branch id attribution unmodeled). The outcome (failure,
    // kind:constraint, argv_pos) is correct — only the element name diverges.
    "constraints-parse/default-interaction.json::case#3",
    "constraints-parse/requires.json::case#4",
    // global shadow subtree (DR-042 global): a shadowed global's value nests under the child scope
    // AND appears at the root; the fixture asserts only the child placement. slice gap (shadow sync).
    "command-scope/shadowing-subtree.json::case#1",
  ]
}

///|
test "conformance: fixtures を JSON 直読みで実食 (stage 2: parse 語彙網羅)" {
  let root = fixtures_root()
  let rels : Array[String] = []
  collect_rel(root, "", rels) catch {
    _ => abort("fixtures walk failed under " + root)
  }
  sort_items(rels)
  let decoded : Array[String] = []
  let skips : Array[(String, String)] = [] // (rel, reason)
  let mismatches : Array[String] = [] // "rel::case#N :: verdict"
  let mismatch_keys : Array[String] = [] // "rel::case#N"
  let mut ran_cases = 0
  for rel in rels {
    let full = root + "/" + rel
    let j = load_json(full) catch {
      _ => {
        skips.push((rel, "load/parse error"))
        continue
      }
    }
    let df = dec_fixture(j) catch {
      DecodeSkip(reason) => {
        skips.push((rel, reason))
        continue
      }
    }
    decoded.push(rel)
    let mut ci = 0
    for c in df.cases {
      ci = ci + 1
      ran_cases = ran_cases + 1
      let verdict = run_case(df, c)
      if verdict != "PASS" {
        let key = rel + "::case#" + ci.to_string()
        mismatch_keys.push(key)
        mismatches.push(key + " :: " + verdict)
      }
    }
  }

  // Always-visible diagnostics: summary counts, the decoded set, and the skip-reason histogram
  // (= the remaining vocabulary TODO — shrinks as later stages teach the decoder more constructs).
  println(
    "[json-conformance] decoded=\{decoded.length()} ran_cases=\{ran_cases} skipped=\{skips.length()} mismatches=\{mismatches.length()}",
  )
  println("[json-conformance] decoded: " + join_comma(decoded))
  let hist : Map[String, Int] = Map::new()
  for pair in skips {
    let r = pair.1
    hist.set(r, (match hist.get(r) { Some(n) => n; None => 0 }) + 1)
  }
  let hitems : Array[String] = []
  for r, n in hist {
    hitems.push("\{n}× \{r}")
  }
  sort_items(hitems)
  for h in hitems {
    println("[json-conformance]   skip " + h)
  }
  for m in mismatches {
    println("[json-conformance]   diverge " + m)
  }

  // Tripwire: the stage-1 acceptance targets MUST still decode & run.
  if !str_in(decoded, "dd/basic.json") ||
    !str_in(decoded, "dd/duplicate-decl.json") {
    let sb = StringBuilder::new()
    sb.write_string("stage-1 target fixture was skipped (decoder regression):\n")
    for pair in skips {
      sb.write_string("  " + pair.0 + " :: " + pair.1 + "\n")
    }
    abort(sb.to_string())
  }

  // Ledger assertion: the observed divergence SET must equal known_divergences() exactly.
  // Unexpected divergences (not in the ledger) and vanished ones (in the ledger but no longer
  // observed) both fail — the ledger is a frozen contract, edited deliberately, never silently.
  let known = known_divergences()
  let unexpected : Array[String] = []
  for k in mismatch_keys {
    if !str_in(known, k) {
      unexpected.push(k)
    }
  }
  let vanished : Array[String] = []
  for k in known {
    if !str_in(mismatch_keys, k) {
      vanished.push(k)
    }
  }
  if unexpected.length() > 0 || vanished.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("divergence ledger mismatch:\n")
    if unexpected.length() > 0 {
      sb.write_string("  UNEXPECTED (add to ledger only after confirming fixture=正本):\n")
      for k in unexpected {
        for m in mismatches {
          if str_starts(m, k + " ::") {
            sb.write_string("    " + m + "\n")
          }
        }
      }
    }
    if vanished.length() > 0 {
      sb.write_string("  VANISHED (gap closed — remove from ledger):\n")
      for k in vanished {
        sb.write_string("    " + k + "\n")
      }
    }
    abort(sb.to_string())
  }
}

///|
/// Whether `s` starts with `prefix` (small helper for the ledger diff report).
fn str_starts(s : String, prefix : String) -> Bool {
  s.length() >= prefix.length() && s.substring(start=0, end=prefix.length()) == prefix
}

///|
/// Read + parse a fixture file. Raises on IO or JSON-syntax errors (caught at the
/// call site → counted as a skip).
fn load_json(path : String) -> Json raise {
  @json.parse(@fs.read_file_to_string(path))
}
