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

// ── a decoded, runnable case: expected values already projected to spec-strings ─

///|
enum DecodedCase {
  DSuccess(Array[String], String, String) // argv, exp_effects, exp_result
  DFailure(Array[String], String) // argv, exp_errors
}

///|
struct DecodedFixture {
  scope : Scope
  cases : Array[DecodedCase]
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
/// CONFORMANCE §2 effects, in consumption order (NOT sorted): "entity:op(operand)@source".
/// op ("set"/…) and source ("cli"/…) are taken verbatim — they equal eff_op / render_src output.
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
    let operand = match eo.get("operand") {
      Some(j) => render_val(json_to_value(j))
      None => raise DecodeSkip("effect missing 'operand'")
    }
    items.push("\{entity}:\{op}(\{operand})@\{source}")
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

///|
fn dec_option(j : Json) -> ElemDef raise DecodeSkip {
  let o = match j.as_object() {
    Some(x) => x
    None => raise DecodeSkip("option is not an object")
  }
  // 'long' absent from the allowlist → any long-spelling option is skipped (stage 2).
  allowed_keys(o, ["id", "name", "type", "short"], "option")
  let ty = match jf_str(o, "type") {
    Some(t) => t
    None => raise DecodeSkip("option missing 'type'")
  }
  match ty {
    "dd" => {
      let name = match jf_str(o, "name") {
        Some(s) => s
        None => raise DecodeSkip("dd option missing 'name'")
      }
      // dd_marker() hardwires the "--" trigger; a dialect trigger ("++") is stage 2.
      if name != "--" {
        raise DecodeSkip("dd with custom trigger name '" + name + "' (stage 2)")
      }
      dd_marker()
    }
    "flag" => {
      let name = match jf_str(o, "name") {
        Some(s) => s
        None => raise DecodeSkip("flag missing 'name'")
      }
      opt(name, TFlag, short=dec_short(o))
    }
    "string" => {
      let name = match jf_str(o, "name") {
        Some(s) => s
        None => raise DecodeSkip("string option missing 'name'")
      }
      opt(name, TStr, short=dec_short(o))
    }
    other => raise DecodeSkip("option type '" + other + "' (stage 2)")
  }
}

///|
fn dec_positional(j : Json) -> ElemDef raise DecodeSkip {
  let o = match j.as_object() {
    Some(x) => x
    None => raise DecodeSkip("positional is not an object")
  }
  allowed_keys(o, ["id", "name", "type"], "positional")
  let ty = match jf_str(o, "type") {
    Some(t) => t
    None => raise DecodeSkip("positional missing 'type'")
  }
  if ty != "string" {
    raise DecodeSkip("positional type '" + ty + "' (stage 2)")
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("positional missing 'name'")
  }
  pos(name, TStr)
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

///|
/// Decode a whole fixture (definition + every case) up front. Any unsupported
/// construct raises DecodeSkip, so the fixture is skipped atomically — no case runs
/// against a partially/mis-decoded definition.
fn dec_fixture(j : Json) -> DecodedFixture raise DecodeSkip {
  let top = match j.as_object() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  match jf_str(top, "query") {
    Some("parse") => ()
    Some(q) => raise DecodeSkip("query '" + q + "' (stage 1: 'parse' only)")
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
  allowed_keys(defo, ["options", "positionals"], "definition")
  let options : Array[ElemDef] = []
  match defo.get("options") {
    Some(arr) => {
      let a = match arr.as_array() {
        Some(x) => x
        None => raise DecodeSkip("options is not an array")
      }
      for oj in a {
        options.push(dec_option(oj))
      }
    }
    None => ()
  }
  let positionals : Array[ElemDef] = []
  match defo.get("positionals") {
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
  let def = def_(options, positionals)
  // Use parse_definition directly (not build_reg) so a rejected definition SKIPS
  // instead of aborting. Installer order mirrors the hand runner's dd basis.
  let scope = match parse_definition(def, [LongInst, ShortInst, DdInst]) {
    Ok(sc) => sc
    Err(errs) => raise DecodeSkip("definition rejected: " + deferrs_str(errs))
  }
  let casesj = match top.get("cases") {
    Some(c) => c
    None => raise DecodeSkip("missing 'cases'")
  }
  let carr = match casesj.as_array() {
    Some(x) => x
    None => raise DecodeSkip("cases is not an array")
  }
  let cases : Array[DecodedCase] = []
  for cj in carr {
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
    match jf_str(eo, "outcome") {
      Some("success") => {
        let eff = match eo.get("effects") {
          Some(x) => x
          None => raise DecodeSkip("success expect missing 'effects'")
        }
        let res = match eo.get("result") {
          Some(x) => x
          None => raise DecodeSkip("success expect missing 'result'")
        }
        cases.push(DSuccess(argv, exp_effects_str(eff), exp_result_str(res)))
      }
      Some("failure") => {
        let errs = match eo.get("errors") {
          Some(x) => x
          None => raise DecodeSkip("failure expect missing 'errors'")
        }
        cases.push(DFailure(argv, exp_errors_str(errs)))
      }
      Some(other) =>
        raise DecodeSkip("outcome '" + other + "' (stage 1: success/failure only)")
      None => raise DecodeSkip("expect missing 'outcome'")
    }
  }
  { scope, cases }
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
test "conformance: fixtures を JSON 直読みで実食 (stage 1: dd 領域)" {
  let root = fixtures_root()
  let rels : Array[String] = []
  collect_rel(root, "", rels) catch {
    _ => abort("fixtures walk failed under " + root)
  }
  sort_items(rels)
  let decoded : Array[String] = []
  let skips : Array[(String, String)] = [] // (rel, reason)
  let mismatches : Array[String] = []
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
      let verdict = match c {
        DSuccess(argv, ee, er) => run_success(df.scope, argv, ee, er)
        DFailure(argv, ex) => run_failure(df.scope, argv, ex)
      }
      if verdict != "PASS" {
        mismatches.push(rel + " case#" + ci.to_string() + " :: " + verdict)
      }
    }
  }

  // Always-visible diagnostics: the summary counts, the decoded set, and a
  // skip-reason histogram (= the stage-2 vocabulary TODO — grows shorter as later
  // stages teach the decoder more constructs).
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

  // Tripwire: the stage-1 acceptance target MUST have decoded & run. If the decoder
  // regresses and skips them, fail loudly with the skip reason (not a silent green).
  if !str_in(decoded, "dd/basic.json") ||
    !str_in(decoded, "dd/duplicate-decl.json") {
    let sb = StringBuilder::new()
    sb.write_string("stage-1 target fixture was skipped (decoder regression):\n")
    for pair in skips {
      sb.write_string("  " + pair.0 + " :: " + pair.1 + "\n")
    }
    abort(sb.to_string())
  }

  // Aggregated assertion: one failure lists EVERY divergence (not first-only).
  if mismatches.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("conformance mismatches (\{mismatches.length()}):\n")
    for m in mismatches {
      sb.write_string("  " + m + "\n")
    }
    abort(sb.to_string())
  }
}

///|
/// Read + parse a fixture file. Raises on IO or JSON-syntax errors (caught at the
/// call site → counted as a skip).
fn load_json(path : String) -> Json raise {
  @json.parse(@fs.read_file_to_string(path))
}
