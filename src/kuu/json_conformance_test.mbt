// json_conformance_test.mbt — 公開 API を通す JSON-DIRECT conformance runner。
//
// PORTED FROM: kawaz/kuu.mbt slice/poc/{json_conformance_wbtest,lower_runner_wbtest,helpers_wbtest,
// fixture_runner_wbtest}.mbt — verbatim structure with API adaptations for main src/kuu:
//   - @engine.ParseError is a 6-tuple (element/args_pos/kind/reason/message/path, DR-066 §3/§4): proj_errors
//     and exp_errors_decode include `reason` when the fixture asserts it on ANY error in the set, and
//     `path` likewise on its own independent opt-in (per-field, per-fixture-set — DR-066 §4/§5:
//     message is never compared, reason/path are each optional and asserted independently).
//   - resolve_scope / resolve_scope_config return `Result[Array[@engine.Binding], @engine.ParseError]` in main
//     (slice returned Result[..., String] for the config variant and Array[@engine.Binding] for the flat
//     variant). Both sites in resolve_tree/do_resolve wrap the @engine.ParseError message.
//   - env_value in main takes (element, ty, s, at_pos)->Result; the variant-DSL operand still needs
//     the naive slice-form coercion → local `dsl_variant_value` helper.
//
// The two-ledger contract (expected_skips / known_divergences) starts EMPTY per MDR-001 §6: fixtures
// are re-fed against the new implementation, and every observed skip / divergence is reported by the
// test so we can classify them off-line. @engine.Empty ledger + failing test = the fixture-first mode.

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 1 — Local helpers (mirror slice/poc/helpers_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

///|
fn Json::j_obj(self : Json) -> Map[String, Json]? {
  if self is Object(fields) {
    Some(fields)
  } else {
    None
  }
}

///|
fn Json::j_arr(self : Json) -> Array[Json]? {
  if self is Array(items) {
    Some(items)
  } else {
    None
  }
}

///|
fn Json::j_str(self : Json) -> String? {
  if self is String(value) {
    Some(value)
  } else {
    None
  }
}

///|
fn Json::j_bool(self : Json) -> Bool? {
  if self is True {
    Some(true)
  } else if self is False {
    Some(false)
  } else {
    None
  }
}

///|
fn Json::j_num(self : Json) -> Double? {
  if self is Number(value, ..) {
    Some(value)
  } else {
    None
  }
}

///|
fn conformance_str_in(items : Array[String], value : String) -> Bool {
  for item in items {
    if item == value {
      return true
    }
  }
  false
}

///|
suberror DecodeSkip {
  DecodeSkip(String)
}

///|
fn jf_str(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(value) => value.j_str()
    None => None
  }
}

///|
fn has_key(fields : Map[String, Json], key : String) -> Bool {
  fields.get(key) is Some(_)
}

///|
fn allowed_keys(
  fields : Map[String, Json],
  allowed : Array[String],
  what : String,
) -> Unit raise DecodeSkip {
  for key, _ in fields {
    if !conformance_str_in(allowed, key) {
      raise DecodeSkip(what + " has unsupported key '" + key + "'")
    }
  }
}

///|
fn json_to_value(json : Json) -> @engine.Value raise DecodeSkip {
  match json.j_bool() {
    Some(value) => return @engine.Bool(value)
    None => ()
  }
  match json.j_str() {
    Some(value) => return @engine.String(value)
    None => ()
  }
  match json.j_num() {
    Some(value) => return @engine.Number(value)
    None => ()
  }
  raise DecodeSkip("non-scalar value in effects/result")
}

///|
fn dec_strs(json : Json?) -> Array[String] raise DecodeSkip {
  match json {
    None => []
    Some(value) =>
      match value.j_str() {
        Some(item) => [item]
        None =>
          match value.j_arr() {
            Some(items) => {
              let result : Array[String] = []
              for item in items {
                match item.j_str() {
                  Some(text) => result.push(text)
                  None =>
                    raise DecodeSkip("string-array element is not a string")
                }
              }
              result
            }
            None => raise DecodeSkip("expected a string or string[]")
          }
      }
  }
}

///|
/// Deterministic codepoint ordering (MoonBit's builtin sorts by length first).
fn str_less(a : String, b : String) -> Bool {
  let ca = a.to_array()
  let cb = b.to_array()
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  let mut i = 0
  while i < n {
    let x = ca[i].to_int()
    let y = cb[i].to_int()
    if x < y {
      return true
    }
    if x > y {
      return false
    }
    i = i + 1
  }
  ca.length() < cb.length()
}

///|
fn sort_items(arr : Array[String]) -> Unit {
  let mut i = 1
  while i < arr.length() {
    let key = arr[i]
    let mut j = i - 1
    while j >= 0 && str_less(key, arr[j]) {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
    i = i + 1
  }
}

///|
fn join_comma(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in items {
    if !first {
      buf.write_string(",")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

///|
fn render_val(v : @engine.Value) -> String {
  match v {
    @engine.String(s) => s
    @engine.Bool(b) => if b { "true" } else { "false" }
    @engine.Number(d) => {
      let i = d.to_int()
      if i.to_double() == d {
        i.to_string()
      } else {
        d.to_string()
      }
    }
  }
}

///|
fn render_src(s : @engine.Source) -> String {
  match s {
    @engine.Cli => "cli"
    @engine.Env => "env"
    @engine.Config => "config"
    @engine.Inherit => "inherit"
    @engine.Tty => "tty"
    @engine.Default => "default"
  }
}

///|
fn render_kind(k : @engine.ErrKind) -> String {
  match k {
    @engine.Parse => "parse"
    @engine.Filter => "filter"
    @engine.Constraint => "constraint"
  }
}

///|
fn render_def_kind(k : @engine.DefErrKind) -> String {
  match k {
    @engine.VocabIntersection => "vocab-intersection"
    @engine.UnknownVocab => "unknown-vocab"
    @engine.InvalidRange => "invalid-range"
    @engine.AbsentRef => "absent-ref"
    @engine.CircularRef => "circular-ref"
    @engine.ZeroProgress => "zero-progress"
    @engine.ConfigCycle => "config-cycle"
    @engine.InvalidArgument => "invalid-argument"
  }
}

///|
fn deferrs_str(errs : Array[@engine.DefError]) -> String {
  let items : Array[String] = []
  for e in errs {
    items.push("\{e.element}/\{render_def_kind(e.kind)}")
  }
  sort_items(items)
  join_comma(items)
}

///|
/// Compact one-line rendering of an @engine.Outcome for the runner's "EXPECTED-* got=" diagnostics.
fn render_outcome(o : @engine.Outcome) -> String {
  match o {
    @engine.Success(binds) => "ok{" + render_binds_result(binds) + "}"
    @engine.Failure(d) =>
      match d.fired_action {
        Some(n) => "action:" + n
        None =>
          if d.errors.length() > 0 {
            "fail:" + primary_message(d.errors)
          } else {
            "fail:no complete parse"
          }
      }
    @engine.Ambiguous(d) =>
      "ambiguous:" + d.interpretations.length().to_string()
  }
}

///|
fn primary_message(errors : Array[@engine.ParseError]) -> String {
  let mut best = errors[0]
  for e in errors {
    if e.args_pos > best.args_pos {
      best = e
    }
  }
  best.message
}

///|
fn runner_sentinel(key : String) -> Bool {
  key == "[]" ||
  key == "{}" ||
  key == "" ||
  key == "#row" ||
  key == "#fire" ||
  (key.length() >= 5 && key[0:5].to_owned() == "@act:") ||
  (key.length() >= 6 && key[0:6].to_owned() == "@depr:")
}

///|
/// Result-side binding renderer for render_outcome ("ok{k=v,…}"). Skips markers.
fn render_binds_result(binds : Array[@engine.Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if !runner_sentinel(b.key) {
      items.push("\{b.key}=\{render_val(b.value)}")
    }
  }
  sort_items(items)
  join_comma(items)
}

// ── @engine.EffectOp / @engine.ExportKey helpers ──────────────────────────────────────────────

///|
fn eff_op(op : @engine.EffectOp) -> String {
  match op {
    @engine.Set => "set"
    @engine.Default => "default"
    @engine.Unset => "unset"
    @engine.Empty => "empty"
    @engine.Invoke(invocation) =>
      if invocation.args.length() == 0 {
        "fn:" + invocation.name
      } else {
        "fn:" + invocation.name + ":" + join_comma(invocation.args)
      }
    // DR-080 §2 merge accumulator piece markers — fixture (merge-basic.json 等) の effects oracle
    // が pin する op 名そのもの ("set" は既存の add piece 表示と同じ、remove/splice がこの2値)。
    @engine.Remove => "remove"
    @engine.Splice => "splice"
  }
}

///|
fn canonical_registry_for_test() -> @engine.Registry {
  let registry = @engine.Registry::new()
  install(registry)
  registry
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 4 — Parse-path projections (mirror slice fixture_runner_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

///|
/// Key-sorted rendering of the built result object (CONFORMANCE §3: result is structural, key order
/// non-normative). Arrays keep order.
fn render_rval_sorted(r : @engine.RVal) -> String {
  match r {
    @engine.Scalar(v) => render_val(v)
    @engine.Array(vs) => {
      let items : Array[String] = []
      for v in vs {
        items.push(render_rval_sorted(v))
      }
      "[" + join_comma(items) + "]"
    }
    @engine.Object(kvs) => {
      let items : Array[String] = []
      for kv in kvs {
        items.push(kv.0 + "=" + render_rval_sorted(kv.1))
      }
      sort_items(items)
      "{" + join_comma(items) + "}"
    }
  }
}

///|
/// `OutputView.effects` の構造化射影を fixture 比較文字列へ変換する。sentinel・config_file・
/// none・dd の除外は玄関が完了済みであり、runner は内部 Scope/Node を走査しない。
fn render_effects(effects : Array[@kuu.OutputEffect]) -> String {
  let items : Array[String] = []
  for effect in effects {
    match effect.operand {
      Some(operand) =>
        items.push(
          "\{effect.entity}:\{eff_op(effect.op)}(\{render_val(operand)})@\{render_src(effect.source)}",
        )
      None =>
        items.push(
          "\{effect.entity}:\{eff_op(effect.op)}@\{render_src(effect.source)}",
        )
    }
  }
  join_comma(items)
}

///|
/// A `path` array rendered as a single comparable token (DR-066 §4 snoc form, root-first). `>` joins
/// segments — element/scope names are installer-derived identifiers (kuu source names), never
/// containing `>` — so this stays unambiguous the same way `/` separates the kind/reason fields.
fn render_path(path : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in path {
    if !first {
      buf.write_string(">")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

///|
/// §2 failure error set. Emits `element@pos/kind` per error; `reason` and `path` (DR-066 §4) each
/// ride along independently when the fixture asserted that field on ANY error in the set (per-field
/// opt-in, CONFORMANCE §3/§5) — `/reason` first (kept at its original position for fixtures already
/// asserting only reason), `|path` appended after (a separate delimiter so "no reason, but path
/// asserted" cannot collide with "reason asserted, no path"). sorted as a set.
fn proj_errors(
  errs : Array[@engine.ParseError],
  with_reason : Bool,
  with_path : Bool,
) -> String {
  let items : Array[String] = []
  for e in errs {
    let mut item = "\{e.element}@\{e.args_pos}/\{render_kind(e.kind)}"
    if with_reason {
      item = item + "/\{e.reason}"
    }
    if with_path {
      item = item + "|\{render_path(e.path)}"
    }
    items.push(item)
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

///|
fn proj_warnings(o : @engine.Outcome) -> String {
  let ws = @engine.warnings_of(o).map(w => w.element)
  sort_items(ws)
  join_comma(ws)
}

///|
/// spec issue conformance-tried-triggers-help-entry-fields (CONFORMANCE §2/§3): DR-053 §4's
/// tried_triggers material as a sorted set (順序非規範、`proj_errors`と同じ `{a,b,c}` 表記 — 空集合
/// は `{}` になり「exact trigger 0 個」を明示的に表現する、空文字列との取り違えを避ける)。
fn proj_tried_triggers(triggers : Array[String]) -> String {
  let items : Array[String] = []
  for t in triggers {
    items.push(t)
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

///|
/// `OutputView.sources` の構造化射影を fixture 比較文字列へ変換する。path が空なら root key、
/// command 木では `sub.key` の形にする。内部セル除外と tree/flat の分岐は玄関が完了済み。
fn render_sources(sources : Array[@kuu.SourceEntry]) -> String {
  let items : Array[String] = []
  for entry in sources {
    let mut key = ""
    for segment in entry.path {
      key = key + segment + "."
    }
    key = key + entry.key
    items.push(key + "=" + render_src(entry.source))
  }
  sort_items(items)
  join_comma(items)
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 5 — JSON conformance runner (mirror slice json_conformance_test.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

// ── decoded case & fixture ────────────────────────────────────────────────────

///|
enum CfgInj {
  NoCfg
  CfgObj(@engine.ConfigVal)
  CfgFiles(Array[(String, @engine.ConfigVal)])
}

///|
struct DCase {
  args : Array[String]
  id : String
  outcome : String
  exp_effects : String?
  exp_result : String?
  // errors face: (asserted-set-string, whether fixture provided reason/path on any error, DR-066 §4/§5)
  exp_errors : String?
  exp_errors_with_reason : Bool
  exp_errors_with_path : Bool
  exp_interps : Array[String]?
  exp_warnings : String?
  exp_sources : String?
  fired_cmp : Bool
  fired_exp : String?
  // spec issue conformance-tried-triggers-help-entry-fields (CONFORMANCE §2/§3): help_entry is
  // opt-in on failure OR ambiguous (structural equality — a plain String? compare like fired_action's).
  help_cmp : Bool
  help_exp : String?
  // tried_triggers is opt-in on failure only, set comparison (順序非規範) — held as the SAME
  // sorted `{a,b,c}` projection string `proj_tried_triggers` produces from the live @engine.Outcome, so
  // comparison is a plain String `!=` like every other set-compared face (errors/warnings/sources).
  tried_cmp : Bool
  tried_exp : String?
  resolve : Bool
  env : Map[String, String]
  // DR-099 §4: tty_provider の runner 注入 — case JSON の `tty` フィールド (env と同型の注入形式)
  // をそのまま Map[stream, TtyObs] として保持 (DR-098 の bool 単一値から生観測 2 値へ改訂)。
  // キー不在 = 提供なし (null、CONFORMANCE §1)。
  tty : Map[String, @kuu.TtyObs]
  cfg : CfgInj
}

///|
struct DecodedFixture {
  ast : @kuu.AtomicAST
  cases : Array[DCase]
}

// ── expected-string builders ──────────────────────────────────────────────────

///|
/// `@engine.RVal` の decode は definition の wire decode (`wire_decode.mbt`) ではなく、fixture の expect
/// (`result`/`interpretations`) を読む側のヘルパー — そのためここに残す (MDR-005 §2 の境界判定)。
/// `@engine.ConfigVal` 側の同種ヘルパー (旧 `json_to_configval`、`cases[].config`/`config_files` の decode)
/// は front_door の `config_from_json` へ昇格済み (MDR-005 追記、「@engine.ConfigVal/TtyObs の入力構築
/// API」issue) — 用途が「fixture 入力の decode」から「production 呼び出し側の入力構築」まで
/// 広がったため、runner 側もそちらを直接呼ぶ (下記 `cfg` 組み立て箇所参照)。
fn json_to_rval(j : Json) -> @engine.RVal raise DecodeSkip {
  match j.j_obj() {
    Some(o) => {
      let kvs : Array[(String, @engine.RVal)] = []
      for k, v in o {
        kvs.push((k, json_to_rval(v)))
      }
      return @engine.Object(kvs)
    }
    None => ()
  }
  match j.j_arr() {
    Some(a) => {
      let vs : Array[@engine.RVal] = []
      for v in a {
        vs.push(json_to_rval(v))
      }
      return @engine.Array(vs)
    }
    None => ()
  }
  @engine.Scalar(json_to_value(j))
}

///|
fn exp_effects_str(eff : Json) -> String raise DecodeSkip {
  let a = match eff.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("effects is not an array")
  }
  let items : Array[String] = []
  for e in a {
    let eo = match e.j_obj() {
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
    // DR-077 §1: an `update` effect's descriptor carries a `transform` name alongside `op` (mirrors
    // the wire effect descriptor `{op:"update", transform:"increment"}`) — folded into the SAME
    // op-string `eff_op`/`lower_eff_op` render for the 0-arg case ("update:increment"), so a fixture
    // needs no separate comparison branch. Absent for every other op (unaffected).
    let op_str = match jf_str(eo, "transform") {
      Some(t) => op + ":" + t
      None => op
    }
    match eo.get("operand") {
      Some(j) =>
        items.push(
          "\{entity}:\{op_str}(\{render_val(json_to_value(j))})@\{source}",
        )
      None => items.push("\{entity}:\{op_str}@\{source}")
    }
  }
  join_comma(items)
}

///|
fn exp_result_str(res : Json) -> String raise DecodeSkip {
  render_rval_sorted(json_to_rval(res))
}

///|
/// Decode a fixture error's `path` array (DR-066 §4, root-first) into the same `>`-joined token
/// `render_path` produces on the got side, so string comparison lines up.
fn exp_error_path(eo : Map[String, Json]) -> String raise DecodeSkip {
  match eo.get("path") {
    Some(j) =>
      match j.j_arr() {
        Some(segs) => {
          let parts : Array[String] = []
          for s in segs {
            match s.j_str() {
              Some(str) => parts.push(str)
              None => raise DecodeSkip("error 'path' element is not a string")
            }
          }
          render_path(parts)
        }
        None => raise DecodeSkip("error 'path' is not an array")
      }
    None => "" // absent on a specific error — compare against empty ([]) path on got side
  }
}

///|
/// Decode the fixture's errors[] and report the sorted set-string plus whether any error had a
/// `reason` and/or `path` field (DR-066 §4/§5, each an INDEPENDENT per-fixture-set opt-in):
/// with_reason / with_path drive got-side inclusion so the per-field opt-in comparison stays aligned.
fn exp_errors_decode(errs : Json) -> (String, Bool, Bool) raise DecodeSkip {
  let a = match errs.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("errors is not an array")
  }
  // detect reason/path opt-in first (per fixture set, not per element)
  let mut with_reason = false
  let mut with_path = false
  for e in a {
    match e.j_obj() {
      Some(eo) => {
        if has_key(eo, "reason") {
          with_reason = true
        }
        if has_key(eo, "path") {
          with_path = true
        }
      }
      None => raise DecodeSkip("error is not an object")
    }
  }
  let items : Array[String] = []
  for e in a {
    let eo = e.j_obj().unwrap()
    let element = match jf_str(eo, "element") {
      Some(s) => s
      None => ""
    }
    let pos = match eo.get("args_pos") {
      Some(j) =>
        match j.j_num() {
          Some(d) => d.to_int().to_string()
          None => raise DecodeSkip("error 'args_pos' is not a number")
        }
      None => raise DecodeSkip("error missing 'args_pos'")
    }
    let kind = match jf_str(eo, "kind") {
      Some(s) => s
      None => raise DecodeSkip("error missing 'kind'")
    }
    let mut item = "\{element}@\{pos}/\{kind}"
    if with_reason {
      let reason = match jf_str(eo, "reason") {
        Some(s) => s
        None => "" // absent on a specific error — compare against empty reason on got side
      }
      item = item + "/\{reason}"
    }
    if with_path {
      item = item + "|\{exp_error_path(eo)}"
    }
    items.push(item)
  }
  sort_items(items)
  ("{" + join_comma(items) + "}", with_reason, with_path)
}

///|
fn exp_warnings_str(j : Json) -> String raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("warnings is not an array")
  }
  let items : Array[String] = []
  for e in a {
    let eo = match e.j_obj() {
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
fn exp_sources_str(j : Json) -> String raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("sources is not an object")
  }
  let items : Array[String] = []
  for k, v in o {
    let src = match v.j_str() {
      Some(s) => s
      None => raise DecodeSkip("source value is not a string")
    }
    items.push(k + "=" + src)
  }
  sort_items(items)
  join_comma(items)
}

///|
fn exp_claimants_str(j : Json) -> String raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("claimants is not an object")
  }
  let items : Array[String] = []
  for k, v in o {
    let ent = match v.j_str() {
      Some(s) => s
      None =>
        raise DecodeSkip("claimant value (occupying entity) is not a string")
    }
    items.push(k + "=" + ent)
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

///|
fn exp_interp_str(e : Json) -> String raise DecodeSkip {
  match e.j_obj() {
    Some(o) =>
      if has_key(o, "claimants") {
        allowed_keys(o, ["result", "claimants"], "interpretation wrapper")
        let view = match o.get("result") {
          Some(r) => render_rval_sorted(json_to_rval(r))
          None => raise DecodeSkip("interpretation wrapper missing 'result'")
        }
        view + "#claimants" + exp_claimants_str(o.get("claimants").unwrap())
      } else {
        render_rval_sorted(json_to_rval(e))
      }
    None => render_rval_sorted(json_to_rval(e))
  }
}

///|
fn dec_interps(j : Json) -> Array[String] raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("interpretations is not an array")
  }
  let out : Array[String] = []
  for e in a {
    out.push(exp_interp_str(e))
  }
  sort_items(out)
  out
}

///|
fn dec_args(cj : Map[String, Json]) -> Array[String] raise DecodeSkip {
  let aj = match cj.get("args") {
    Some(x) => x
    None => raise DecodeSkip("case missing 'args'")
  }
  let a = match aj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("args is not an array")
  }
  let out : Array[String] = []
  for t in a {
    match t.j_str() {
      Some(s) => out.push(s)
      None => raise DecodeSkip("args element is not a string")
    }
  }
  out
}

///|
fn dec_case(cj : Json) -> DCase raise DecodeSkip {
  let co = match cj.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("case is not an object")
  }
  allowed_keys(
    co,
    ["id", "args", "expect", "env", "tty", "config", "config_files", "why"],
    "case",
  )
  let args = dec_args(co)
  let id = jf_str(co, "id").unwrap_or("")
  let expect = match co.get("expect") {
    Some(e) => e
    None => raise DecodeSkip("case missing 'expect'")
  }
  let eo = match expect.j_obj() {
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
  let env : Map[String, String] = Map([])
  match co.get("env") {
    Some(ej) => {
      let eobj = match ej.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("case env is not an object")
      }
      for k, v in eobj {
        match v.j_str() {
          Some(s) => env.set(k, s)
          None => raise DecodeSkip("case env value is not a string")
        }
      }
    }
    None => ()
  }
  // DR-099 §4: case の `tty` フィールド (env と同型の注入形式) — tty_provider の runner 実装。
  // 各 stream キーは `{terminal, cygwin}` の生観測 2 値 (DR-098 の bool 単一値から改訂、
  // schema/fixture.schema.json の `additionalProperties: false` に合わせ両キー必須で decode)。
  // キー不在 = 提供なし (CONFORMANCE §1「null = 未設定」の tty 版、DR-098 §1 の規定を継承)。
  let tty : Map[String, @kuu.TtyObs] = Map([])
  match co.get("tty") {
    Some(tj) => {
      let tobj = match tj.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("case tty is not an object")
      }
      for k, v in tobj {
        let vo = match v.j_obj() {
          Some(x) => x
          None => raise DecodeSkip("case tty[" + k + "] is not an object")
        }
        allowed_keys(vo, ["terminal", "cygwin"], "case tty[" + k + "]")
        let terminal = match vo.get("terminal") {
          Some(bj) =>
            match bj.j_bool() {
              Some(b) => b
              None =>
                raise DecodeSkip("case tty[" + k + "].terminal is not a bool")
            }
          None => raise DecodeSkip("case tty[" + k + "] missing 'terminal'")
        }
        let cygwin = match vo.get("cygwin") {
          Some(bj) =>
            match bj.j_bool() {
              Some(b) => b
              None =>
                raise DecodeSkip("case tty[" + k + "].cygwin is not a bool")
            }
          None => raise DecodeSkip("case tty[" + k + "] missing 'cygwin'")
        }
        tty.set(k, @kuu.tty_obs(terminal, cygwin))
      }
    }
    None => ()
  }
  let cfg = match co.get("config") {
    Some(cjj) => CfgObj(@kuu.config_from_json(cjj))
    None =>
      match co.get("config_files") {
        Some(fj) =>
          match fj.j_obj() {
            Some(fo) => {
              let files : Array[(String, @engine.ConfigVal)] = []
              for k, v in fo {
                files.push((k, @kuu.config_from_json(v)))
              }
              CfgFiles(files)
            }
            None => NoCfg
          }
        None => NoCfg
      }
  }
  let has_sources = has_key(eo, "sources")
  let resolve = outcome == "failure" ||
    has_sources ||
    has_key(eo, "result") ||
    has_key(co, "env") ||
    has_key(co, "tty") ||
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
  let (exp_errors, exp_errors_with_reason, exp_errors_with_path) = match
    eo.get("errors") {
    Some(x) => {
      let (s, wr, wp) = exp_errors_decode(x)
      (Some(s), wr, wp)
    }
    None => (None, false, false)
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
  let (fired_cmp, fired_exp) = if outcome == "failure" &&
    has_key(eo, "fired_action") {
    (true, jf_str(eo, "fired_action"))
  } else {
    (false, None)
  }
  // spec issue conformance-tried-triggers-help-entry-fields: help_entry is opt-in on failure OR
  // ambiguous (DR-053 §4 material — both outcomes can carry a selected/discoverable help entry).
  let (help_cmp, help_exp) = if (outcome == "failure" || outcome == "ambiguous") &&
    has_key(eo, "help_entry") {
    (true, jf_str(eo, "help_entry"))
  } else {
    (false, None)
  }
  // tried_triggers is opt-in on failure only (DR-053 §4 material tied to the failure position —
  // ambiguous has no single failure position to derive it from). Projected to the SAME sorted
  // `{a,b,c}` string the live @engine.Outcome comparison uses, at decode time — a plain String compare
  // at the comparison site, matching every other set-compared face.
  let (tried_cmp, tried_exp) = if outcome == "failure" &&
    has_key(eo, "tried_triggers") {
    (true, Some(proj_tried_triggers(dec_strs(eo.get("tried_triggers")))))
  } else {
    (false, None)
  }
  {
    args,
    id,
    outcome,
    exp_effects,
    exp_result,
    exp_errors,
    exp_errors_with_reason,
    exp_errors_with_path,
    exp_interps,
    exp_warnings,
    exp_sources,
    fired_cmp,
    fired_exp,
    help_cmp,
    help_exp,
    tried_cmp,
    tried_exp,
    resolve,
    env,
    tty,
    cfg,
  }
}

// ── definition_error path (DR-082) ─────────────────────────────────────────────

///|
/// DR-082 §1: `query: "definition_error"` fixture の 1 case — DR-054 §4 の `@builtins.lower_definition()`
/// 返値をそのまま転用する。`args` は無い (定義の静的検査であり実行しない)。比較対象は
/// element+kind の組の集合のみ (message/hint はレンダラ管轄なので比較しない、DR-082 §1 — parse
/// fixture の `errors` が message を比較しないのと同流儀)。`exp_errors` は `deferrs_str` と同じ
/// ソート済み "element/kind" 連結表現なので、実行時にそのまま文字列比較できる。
struct DExpectedDefError {
  element : String?
  kind : String
}

///|
struct DDefErrorCase {
  id : String
  exp_errors : Array[DExpectedDefError]
}

///|
struct DDefErrorFixture {
  definition : Json
  cases : Array[DDefErrorCase]
}

///|
fn dec_def_error_case(cj : Json) -> DDefErrorCase raise DecodeSkip {
  let co = match cj.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("case is not an object")
  }
  allowed_keys(co, ["id", "why", "expect"], "definition_error case")
  let id = match jf_str(co, "id") {
    Some(s) => s
    None => raise DecodeSkip("case missing 'id'")
  }
  let eo = match co.get("expect") {
    Some(x) =>
      match x.j_obj() {
        Some(o) => o
        None => raise DecodeSkip("expect is not an object")
      }
    None => raise DecodeSkip("case missing 'expect'")
  }
  allowed_keys(eo, ["outcome", "errors"], "definition_error case's expect")
  match jf_str(eo, "outcome") {
    Some("definition-error") => ()
    Some(o) =>
      raise DecodeSkip("expect.outcome '" + o + "' is not 'definition-error'")
    None => raise DecodeSkip("expect missing 'outcome'")
  }
  let errsj = match eo.get("errors") {
    Some(x) => x
    None => raise DecodeSkip("expect missing 'errors'")
  }
  let arr = match errsj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("expect.errors is not an array")
  }
  let items : Array[DExpectedDefError] = []
  for ej in arr {
    let ejo = match ej.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("expect.errors entry is not an object")
    }
    allowed_keys(
      ejo,
      ["element", "kind"],
      "definition_error case's expect.errors entry",
    )
    let kind = match jf_str(ejo, "kind") {
      Some(s) => s
      None => raise DecodeSkip("errors entry missing 'kind'")
    }
    items.push({ element: jf_str(ejo, "element"), kind })
  }
  { id, exp_errors: items }
}

///|
/// `dec_fixture` (query="parse") と対照的に、ここでは `parse_definition` を呼ばない — definition_
/// error fixture の主旨は「parse_definition が Err を返すこと」自体を検証することなので、
/// `dec_fixture` のように `Err` を即 `DecodeSkip` してしまうと本題を検証できなくなる
/// (`dec_fixture`'s `"definition rejected: ..."` 分岐と対照)。`definition`/`definitions` の decode
/// (dec_definition/dec_types/dec_templates) は "parse" と同じ経路を再利用する — 検証差分はこの後の
/// `parse_definition` 呼び出しタイミング (fixture decode 時ではなく case 実行時) だけ。
fn dec_definition_error_fixture(j : Json) -> DDefErrorFixture raise DecodeSkip {
  let top = match j.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  let defj = match top.get("definition") {
    Some(d) => d
    None => raise DecodeSkip("missing 'definition'")
  }
  let casesj = match top.get("cases") {
    Some(c) => c
    None => raise DecodeSkip("missing 'cases'")
  }
  let carr = match casesj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("cases is not an array")
  }
  let cases : Array[DDefErrorCase] = []
  for cj in carr {
    cases.push(dec_def_error_case(cj))
  }
  { definition: defj, cases }
}

///|
/// DR-082 §1: run `parse_definition` and compare its `Err` (element+kind set) against the fixture's
/// expectation. An unexpected `Ok` (the definition was NOT rejected) is itself a mismatch —
/// `render_outcome`-style "EXPECTED-*" convention mirrors the parse-path runner's diagnostics.
fn expected_def_errors_match(
  expected : Array[DExpectedDefError],
  actual : Array[@engine.DefError],
) -> Bool {
  if expected.length() != actual.length() {
    return false
  }
  let used = Array::make(actual.length(), false)
  for want in expected {
    let mut found = false
    for i = 0; i < actual.length(); i = i + 1 {
      if !used[i] &&
        render_def_kind(actual[i].kind) == want.kind &&
        (match want.element {
          Some(element) => actual[i].element == element
          None => true
        }) {
        used[i] = true
        found = true
        break
      }
    }
    if !found {
      return false
    }
  }
  true
}

///|
fn expected_def_errors_str(expected : Array[DExpectedDefError]) -> String {
  let items : Array[String] = []
  for item in expected {
    items.push(item.element.unwrap_or("*") + "/" + item.kind)
  }
  sort_items(items)
  join_comma(items)
}

///|
fn run_definition_error(fx : DDefErrorFixture, c : DDefErrorCase) -> String {
  match @kuu.parse_definition(fx.definition) {
    Ok(_) => "EXPECTED-DEFINITION-ERROR got=ok"
    Err(@kuu.Malformed(reason)) =>
      "EXPECTED-DEFINITION-ERROR got=malformed:" + reason
    Err(@kuu.Rejected(errors)) =>
      if expected_def_errors_match(c.exp_errors, errors) {
        "PASS"
      } else {
        "errors got=\{deferrs_str(errors)} want=\{expected_def_errors_str(c.exp_errors)}"
      }
  }
}

// ── complete path (DR-104, CONFORMANCE §4) ─────────────────────────────────────

///|
fn bool_str(b : Bool) -> String {
  if b {
    "true"
  } else {
    "false"
  }
}

///|
/// The canonical single-candidate projection BOTH the live `@engine.Cand` (`cand_str`) and the fixture's
/// decoded expectation (`exp_candidate_str`) reduce to — CONFORMANCE §3's 6-field structural
/// equality (spelling/is_value/type/origin/term/meta) PLUS an OPT-IN 7th field, `completer` (DR-104
/// §2/§3, CONFORMANCE §3 COMP-Q3): included in the string only when `with_completer` is true (a
/// per-fixture-set decision, mirroring `errors[].reason`'s own opt-in — see `exp_errors_decode`'s
/// `with_reason`). Wire `type` maps to the live candidate's `Cand.ty`; both `spelling` and `type` are
/// normalized to `""` on their "doesn't apply" side (DR-104 §2: `spelling` is meaningless when
/// `is_value:true`, `type` is meaningless when `is_value:false`) so a
/// fixture that omits the moot field and a live `@engine.Cand` that carries a leftover tag there (e.g.
/// `trigger_candidate`'s placeholder `@builtins.flag_type()`) still compare equal.
fn cand_fields_str(
  spelling : String,
  is_value : Bool,
  ty : String,
  origin : String,
  term : String,
  is_alias : Bool,
  hidden : Bool,
  deprecated : Bool,
  completer? : String? = None,
) -> String {
  let base = "spelling=" +
    spelling +
    "|is_value=" +
    bool_str(is_value) +
    "|ty=" +
    ty +
    "|origin=" +
    origin +
    "|term=" +
    term +
    "|is_alias=" +
    bool_str(is_alias) +
    "|hidden=" +
    bool_str(hidden) +
    "|deprecated=" +
    bool_str(deprecated)
  match completer {
    Some(c) => base + "|completer=" + c
    None => base
  }
}

///|
/// `with_completer` (DR-104 §2/§3 opt-in, per-fixture-set — see `exp_candidate_str`'s detection):
/// when true, `c.completer` (`None` normalized to `""`, mirroring `errors[].reason`'s absent-on-a-
/// specific-element convention) joins the 6-field identity string; the dedup identity itself
/// (`@engine.complete_tree`'s dedup loop, outcome.mbt) never looks at this field regardless.
fn cand_str(c : @engine.Cand, with_completer : Bool) -> String {
  let term_s = match c.term {
    WordEnd => "word_end"
    Cont => "cont"
  }
  let ty_s = if c.is_value { c.ty } else { "" }
  let spelling_s = if c.is_value { "" } else { c.spelling }
  let completer_arg = if with_completer {
    Some(c.completer.unwrap_or(""))
  } else {
    None
  }
  cand_fields_str(
    spelling_s,
    c.is_value,
    ty_s,
    c.origin,
    term_s,
    c.meta.is_alias,
    c.meta.hidden,
    c.meta.deprecated,
    completer=completer_arg,
  )
}

///|
/// `candidates` is a SET (CONFORMANCE §3/§4, DR-104 §4 — same treatment as `interpretations`):
/// sort + join, mirroring `deferrs_str`'s pattern in this same file.
fn cands_set_str(cs : Array[@engine.Cand], with_completer : Bool) -> String {
  let items : Array[String] = []
  for c in cs {
    items.push(cand_str(c, with_completer))
  }
  sort_items(items)
  join_comma(items)
}

///|
/// Decode ONE `expect.candidates[]` entry (DR-104 §2, schema `$defs/candidate`) straight into the
/// SAME canonical string `cand_str` produces from a live `@engine.Cand` — `run_complete` then compares with
/// a plain `==`, matching `deferrs_str`/`exp_errors_decode`'s decode-to-comparable-string pattern.
/// `with_completer` (COMP-Q3 opt-in, detected per-fixture-set by `dec_complete_case` — mirrors
/// `exp_errors_decode`'s `with_reason`) decides whether `completer` joins the comparison string;
/// an element that omits the key while its siblings declare it compares against `""` (absent).
fn exp_candidate_str(
  j : Json,
  with_completer : Bool,
) -> String raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("candidate is not an object")
  }
  allowed_keys(
    o,
    ["spelling", "is_value", "type", "origin", "term", "meta", "completer"],
    "candidate",
  )
  let is_value = match o.get("is_value") {
    Some(bj) =>
      match bj.j_bool() {
        Some(b) => b
        None => raise DecodeSkip("candidate.is_value is not a bool")
      }
    None => raise DecodeSkip("candidate missing 'is_value'")
  }
  // DR-104 §2: `spelling` は is_value:true では意味を持たず省略可 (省略 = "" と等価)。
  let spelling = if is_value { "" } else { jf_str(o, "spelling").unwrap_or("") }
  // DR-104 §2: wire `type` は is_value:true でのみ意味を持つ (実質必須)。
  let ty_s = if is_value {
    match jf_str(o, "type") {
      Some(t) => {
        // Candidate type vocabulary is validated against the same active assembly used by the front door.
        if canonical_registry_for_test().lookup_type(t) is None {
          raise DecodeSkip("candidate has unknown type '" + t + "'")
        }
        t
      }
      None => raise DecodeSkip("candidate.is_value:true missing 'type'")
    }
  } else {
    ""
  }
  let origin = match jf_str(o, "origin") {
    Some(s) => s
    None => raise DecodeSkip("candidate missing 'origin'")
  }
  let term = match jf_str(o, "term") {
    Some("word_end") => "word_end"
    Some("cont") => "cont"
    Some(t) => raise DecodeSkip("candidate.term '" + t + "'")
    None => raise DecodeSkip("candidate missing 'term'")
  }
  // CONFORMANCE §3 / DR-104 §2/§3 (COMP-Q2): meta は候補同一性の成分であり省略不可 — 他の
  // optional 検証フィールド (reason/help_entry 等) とは異なり default 値への読み替えをしない。
  let mo = match o.get("meta") {
    Some(mj) =>
      match mj.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("candidate.meta is not an object")
      }
    None =>
      raise DecodeSkip("candidate missing 'meta' (required, CONFORMANCE §3)")
  }
  allowed_keys(mo, ["is_alias", "hidden", "deprecated"], "candidate.meta")
  let is_alias = match mo.get("is_alias") {
    Some(bj) =>
      match bj.j_bool() {
        Some(b) => b
        None => raise DecodeSkip("candidate.meta.is_alias is not a bool")
      }
    None => raise DecodeSkip("candidate.meta missing 'is_alias'")
  }
  let hidden = match mo.get("hidden") {
    Some(bj) =>
      match bj.j_bool() {
        Some(b) => b
        None => raise DecodeSkip("candidate.meta.hidden is not a bool")
      }
    None => raise DecodeSkip("candidate.meta missing 'hidden'")
  }
  let deprecated = match mo.get("deprecated") {
    Some(bj) =>
      match bj.j_bool() {
        Some(b) => b
        None => raise DecodeSkip("candidate.meta.deprecated is not a bool")
      }
    None => raise DecodeSkip("candidate.meta missing 'deprecated'")
  }
  // DR-104 §2 (d) / COMP-Q3: opt-in — absent on THIS element compares as "" even when a sibling
  // candidate in the same fixture case turned with_completer on (same convention as
  // `errors[].reason`'s per-element absence, `exp_errors_decode`).
  let completer_arg = if with_completer {
    Some(jf_str(o, "completer").unwrap_or(""))
  } else {
    None
  }
  cand_fields_str(
    spelling,
    is_value,
    ty_s,
    origin,
    term,
    is_alias,
    hidden,
    deprecated,
    completer=completer_arg,
  )
}

///|
/// DR-104 §1: `query: "complete"` fixture の 1 case — `args_before` (必須) / `args_after`
/// (optional) を入力に `candidates` の期待集合 (ソート済み連結文字列) を持つ。`with_completer`
/// (COMP-Q3 opt-in, detected per-case over this case's own `candidates[]` — mirrors
/// `exp_errors_decode`'s per-errors-array `with_reason` detection) drives whether `run_complete`
/// projects the live side's `completer` into the comparison string too.
struct DCompleteCase {
  id : String
  args_before : Array[String]
  args_after : Array[String]
  exp_candidates : String
  with_completer : Bool
}

///|
struct DCompleteFixture {
  ast : @kuu.AtomicAST
  cases : Array[DCompleteCase]
}

///|
fn dec_complete_case(cj : Json) -> DCompleteCase raise DecodeSkip {
  let co = match cj.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("case is not an object")
  }
  allowed_keys(
    co,
    ["id", "why", "args_before", "args_after", "expect"],
    "complete case",
  )
  let id = match jf_str(co, "id") {
    Some(s) => s
    None => raise DecodeSkip("case missing 'id'")
  }
  // DR-104 §1: args_before は必須 (行末補完でも `[]` を明示する) — parse fixture の `args` と同じ
  // 「キー自体は必須、空配列は正当値」の扱い (`dec_args` と対称)。
  let args_before = match co.get("args_before") {
    Some(aj) => dec_strs(Some(aj))
    None => raise DecodeSkip("complete case missing 'args_before' (DR-104 §1)")
  }
  let args_after = dec_strs(co.get("args_after"))
  let eo = match co.get("expect") {
    Some(x) =>
      match x.j_obj() {
        Some(o) => o
        None => raise DecodeSkip("expect is not an object")
      }
    None => raise DecodeSkip("case missing 'expect'")
  }
  allowed_keys(eo, ["outcome", "candidates"], "complete case's expect")
  match jf_str(eo, "outcome") {
    Some("complete") => ()
    Some(o) => raise DecodeSkip("expect.outcome '" + o + "' is not 'complete'")
    None => raise DecodeSkip("expect missing 'outcome'")
  }
  let candsj = match eo.get("candidates") {
    Some(x) => x
    None => raise DecodeSkip("expect missing 'candidates'")
  }
  let arr = match candsj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("expect.candidates is not an array")
  }
  // detect completer opt-in first (per this case's candidates array, not per element — mirrors
  // `exp_errors_decode`'s with_reason detection over its errors array).
  let mut with_completer = false
  for cj2 in arr {
    match cj2.j_obj() {
      Some(co2) => if has_key(co2, "completer") { with_completer = true }
      None => raise DecodeSkip("candidate is not an object")
    }
  }
  let items : Array[String] = []
  for cj2 in arr {
    items.push(exp_candidate_str(cj2, with_completer))
  }
  sort_items(items)
  {
    id,
    args_before,
    args_after,
    exp_candidates: join_comma(items),
    with_completer,
  }
}

///|
/// `dec_fixture` (query="parse") と同じ definition-decode 経路の再利用 (`dec_definition_error_
/// fixture`と同型の重複 — 差分は query チェックと cases の decode だけ、同ファイル内の既定パターン)。
/// complete は result-export を使わないので `ekmap`は持たない。
fn dec_complete_fixture(j : Json) -> DCompleteFixture raise DecodeSkip {
  let top = match j.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  let defj = match top.get("definition") {
    Some(d) => d
    None => raise DecodeSkip("missing 'definition'")
  }
  let ast = match @kuu.parse_definition(defj) {
    Ok(value) => value
    Err(@kuu.Malformed(reason)) => raise DecodeSkip(reason)
    Err(@kuu.Rejected(errors)) =>
      raise DecodeSkip("definition rejected: " + deferrs_str(errors))
  }
  let casesj = match top.get("cases") {
    Some(c) => c
    None => raise DecodeSkip("missing 'cases'")
  }
  let carr = match casesj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("cases is not an array")
  }
  let cases : Array[DCompleteCase] = []
  for cj in carr {
    cases.push(dec_complete_case(cj))
  }
  { ast, cases }
}

///|
/// DR-104 §4/§6: run `complete()` with the case's `args_before`/`args_after` and compare the
/// projected candidate set against the fixture's expectation.
fn run_complete(fx : DCompleteFixture, c : DCompleteCase) -> String {
  let cs = @kuu.complete(fx.ast, c.args_before, args_after=c.args_after)
  let got = cands_set_str(cs, c.with_completer)
  if got == c.exp_candidates {
    "PASS"
  } else {
    "candidates got=\{got} want=\{c.exp_candidates}"
  }
}

// ── help path (DR-112, CONFORMANCE §5) ────────────────────────────────────────

///|
struct DHelpCase {
  id : String
  path : Array[String]
  depth : @kuu.HelpDepth
  category_mode : @kuu.HelpCategoryMode
  expect : Json
}

///|
struct DHelpFixture {
  ast : @kuu.AtomicAST
  cases : Array[DHelpCase]
}

///|
/// DR-113 §1 の category_mode: string "default" / "all"、または object `{"named": name}`。
/// 未指定は既定 `Default`。他の string / 形は decode skip。
fn dec_category_mode(cmj : Json) -> @kuu.HelpCategoryMode raise DecodeSkip {
  match cmj {
    String("default") => @kuu.Default
    String("all") => @kuu.All
    String(other) =>
      raise DecodeSkip(
        "category_mode string '" + other + "' is not default/all",
      )
    Object(obj) =>
      match obj.get("named") {
        Some(String(name)) => @kuu.Named(name)
        Some(_) => raise DecodeSkip("category_mode.named is not a string")
        None => raise DecodeSkip("category_mode object missing 'named'")
      }
    _ => raise DecodeSkip("category_mode is not a string or object")
  }
}

///|
fn dec_help_case(cj : Json) -> DHelpCase raise DecodeSkip {
  let co = match cj.j_obj() {
    Some(value) => value
    None => raise DecodeSkip("help case is not an object")
  }
  allowed_keys(
    co,
    ["id", "why", "path", "depth", "category_mode", "expect"],
    "help case",
  )
  let id = match jf_str(co, "id") {
    Some(value) => value
    None => raise DecodeSkip("help case missing 'id'")
  }
  let path = dec_strs(co.get("path"))
  let depth = match jf_str(co, "depth") {
    None | Some("scope") => @kuu.Scope
    Some("all") => @kuu.All
    Some(value) =>
      raise DecodeSkip("help depth '" + value + "' is not scope/all")
  }
  let category_mode = match co.get("category_mode") {
    None => @kuu.Default
    Some(cmj) => dec_category_mode(cmj)
  }
  let expect = match co.get("expect") {
    Some(value) => value
    None => raise DecodeSkip("help case missing 'expect'")
  }
  { id, path, depth, category_mode, expect }
}

///|
fn dec_help_fixture(j : Json) -> DHelpFixture raise DecodeSkip {
  let top = match j.j_obj() {
    Some(value) => value
    None => raise DecodeSkip("help fixture is not an object")
  }
  let definition = match top.get("definition") {
    Some(value) => value
    None => raise DecodeSkip("help fixture missing 'definition'")
  }
  let ast = match @kuu.parse_definition(definition) {
    Ok(value) => value
    Err(@kuu.Malformed(reason)) => raise DecodeSkip(reason)
    Err(@kuu.Rejected(errors)) =>
      raise DecodeSkip("definition rejected: " + deferrs_str(errors))
  }
  let cases_json = match top.get("cases") {
    Some(value) => value
    None => raise DecodeSkip("help fixture missing 'cases'")
  }
  let cases_array = match cases_json.j_arr() {
    Some(value) => value
    None => raise DecodeSkip("help fixture cases is not an array")
  }
  let cases : Array[DHelpCase] = []
  for case_json in cases_array {
    cases.push(dec_help_case(case_json))
  }
  { ast, cases }
}

///|
fn help_value_json(value : @engine.Value) -> Json {
  match value {
    @engine.String(text) => text.to_json()
    @engine.Number(number) => number.to_json()
    @engine.Bool(boolean) => boolean.to_json()
  }
}

///|
fn help_default_json(value : @kuu.HelpDefault) -> Json {
  match value {
    @kuu.Scalar(scalar) => help_value_json(scalar)
    @kuu.Array(values) => {
      let output : Array[Json] = []
      for item in values {
        output.push(help_value_json(item))
      }
      output.to_json()
    }
  }
}

///|
/// DR-113 §4.1 helpValueStructure oneOf 直訳。single / seq / or / repeat / type_ref それぞれの
/// object 形へ写す (schema $defs/helpValueStructure と対応)。
fn help_value_structure_json(vs : @engine.HelpValueStructure) -> Json {
  match vs {
    @engine.Single(single) => {
      let inner : Map[String, Json] = Map([])
      match single.value_name {
        Some(value) => inner.set("value_name", value.to_json())
        None => ()
      }
      match single.value_type {
        Some(t) => inner.set("type", t.to_json())
        None => ()
      }
      match single.values_enum {
        Some(values) => inner.set("values_enum", values.to_json())
        None => ()
      }
      let out : Map[String, Json] = Map([])
      out.set("single", inner.to_json())
      out.to_json()
    }
    @engine.Seq(nodes) => {
      let arr : Array[Json] = []
      for n in nodes {
        arr.push(help_value_structure_json(n))
      }
      let out : Map[String, Json] = Map([])
      out.set("seq", arr.to_json())
      out.to_json()
    }
    @engine.Or(nodes) => {
      let arr : Array[Json] = []
      for n in nodes {
        arr.push(help_value_structure_json(n))
      }
      let out : Map[String, Json] = Map([])
      out.set("or", arr.to_json())
      out.to_json()
    }
    @engine.Repeat(spec) => {
      let inner : Map[String, Json] = Map([])
      match spec.min {
        Some(m) => inner.set("min", m.to_json())
        None => ()
      }
      match spec.max {
        Some(m) => inner.set("max", m.to_json())
        None => ()
      }
      inner.set("node", help_value_structure_json(spec.node))
      let out : Map[String, Json] = Map([])
      out.set("repeat", inner.to_json())
      out.to_json()
    }
    @engine.TypeRef(ref_) => {
      let out : Map[String, Json] = Map([])
      out.set("type_ref", ref_.id.to_json())
      match ref_.value_name {
        Some(v) => out.set("value_name", v.to_json())
        None => ()
      }
      out.to_json()
    }
  }
}

///|
/// DR-113 §4.3 helpOrigin oneOf 直訳。Local は string "local"、Global/Inheritable は object、
/// Alias は object。
fn help_origin_json(origin : @kuu.HelpOrigin) -> Json {
  match origin {
    @kuu.Local => "local".to_json()
    @kuu.Global(declared_at) => {
      let out : Map[String, Json] = Map([])
      out.set("kind", "global".to_json())
      out.set("declared_at", declared_at.to_json())
      out.to_json()
    }
    @kuu.Inheritable(declared_at) => {
      let out : Map[String, Json] = Map([])
      out.set("kind", "inheritable".to_json())
      out.set("declared_at", declared_at.to_json())
      out.to_json()
    }
    @kuu.Alias(of) => {
      let out : Map[String, Json] = Map([])
      out.set("kind", "alias".to_json())
      out.set("of", of.to_json())
      out.to_json()
    }
  }
}

///|
fn help_usage_positional_json(positional : @kuu.HelpUsagePositional) -> Json {
  let object : Map[String, Json] = Map([])
  object.set(
    "value_structure",
    help_value_structure_json(positional.value_structure),
  )
  object.to_json()
}

///|
fn help_usage_json(usage : @kuu.HelpUsage) -> Json {
  let object : Map[String, Json] = Map([])
  if usage.has_options {
    object.set("has_options", true.to_json())
  }
  if usage.positionals.length() > 0 {
    let positionals : Array[Json] = []
    for positional in usage.positionals {
      positionals.push(help_usage_positional_json(positional))
    }
    object.set("positionals", positionals.to_json())
  }
  if usage.has_subcommands {
    object.set("has_subcommands", true.to_json())
  }
  if usage.has_dd {
    object.set("has_dd", true.to_json())
  }
  object.to_json()
}

///|
/// DR-113 §4/§4.4 helpOptionEntry の serialize。hidden / deprecated / origin は schema required
/// (常に emit)。value_structure は value-less preset (flag/count/help/none/dd/config_file/tty) では
/// 省略、value-bearing 要素 (string/number/int/bool)・help_category (or[bool,string]) では emit。
fn help_option_json(option : @kuu.HelpOption) -> Json {
  let object : Map[String, Json] = Map([])
  object.set("spellings", option.spellings.to_json())
  if option.alias_spellings.length() > 0 {
    object.set("alias_spellings", option.alias_spellings.to_json())
  }
  match option.value_structure {
    Some(vs) => object.set("value_structure", help_value_structure_json(vs))
    None => ()
  }
  match option.display_name {
    Some(value) => object.set("display_name", value.to_json())
    None => ()
  }
  match option.help {
    Some(value) => object.set("help", value.to_json())
    None => ()
  }
  match option.help_long {
    Some(value) => object.set("help_long", value.to_json())
    None => ()
  }
  match option.help_group_name {
    Some(value) => object.set("help_group_name", value.to_json())
    None => ()
  }
  match option.default {
    Some(value) => object.set("default", help_default_json(value))
    None => ()
  }
  if option.env.length() == 1 {
    object.set("env", option.env[0].to_json())
  } else if option.env.length() > 1 {
    object.set("env", option.env.to_json())
  }
  if option.required {
    object.set("required", true.to_json())
  }
  if option.multiple {
    object.set("multiple", true.to_json())
  }
  // hidden / deprecated / origin は schema required — false であっても常に emit。
  object.set("hidden", option.hidden.to_json())
  object.set("deprecated", option.deprecated.to_json())
  object.set("origin", help_origin_json(option.origin))
  object.to_json()
}

///|
fn help_option_entry_json(entry : @kuu.HelpOptionEntry) -> Json {
  match entry {
    @kuu.Group(group) => {
      let group_object : Map[String, Json] = Map([])
      group_object.set("name", group.name.to_json())
      match group.title {
        Some(value) => group_object.set("title", value.to_json())
        None => ()
      }
      match group.description {
        Some(value) => group_object.set("description", value.to_json())
        None => ()
      }
      let object : Map[String, Json] = Map([])
      object.set("group", group_object.to_json())
      object.to_json()
    }
    @kuu.Option(option) => help_option_json(option)
  }
}

///|
/// DR-113 §4/§4.4 helpCommandEntry の serialize。hidden / deprecated / origin は schema required
/// (常に emit)。scope フィールドは depth="all" 時にのみ Some(HelpModel) — その時だけ子 help model
/// を再帰埋め込みして emit。
fn help_command_json(command : @kuu.HelpCommand) -> Json {
  let object : Map[String, Json] = Map([])
  object.set("name", command.name.to_json())
  if command.aliases.length() > 0 {
    object.set("aliases", command.aliases.to_json())
  }
  match command.help {
    Some(value) => object.set("help", value.to_json())
    None => ()
  }
  match command.help_long {
    Some(value) => object.set("help_long", value.to_json())
    None => ()
  }
  object.set("hidden", command.hidden.to_json())
  object.set("deprecated", command.deprecated.to_json())
  object.set("origin", help_origin_json(command.origin))
  match command.scope {
    Some(sub) => object.set("scope", help_model_json(sub))
    None => ()
  }
  object.to_json()
}

///|
/// DR-113 §4 helpPositionalEntry の serialize。value_structure / hidden / deprecated は schema
/// required (常に emit)。
fn help_positional_json(positional : @kuu.HelpPositional) -> Json {
  let object : Map[String, Json] = Map([])
  object.set(
    "value_structure",
    help_value_structure_json(positional.value_structure),
  )
  match positional.help {
    Some(value) => object.set("help", value.to_json())
    None => ()
  }
  match positional.help_long {
    Some(value) => object.set("help_long", value.to_json())
    None => ()
  }
  object.set("hidden", positional.hidden.to_json())
  object.set("deprecated", positional.deprecated.to_json())
  object.to_json()
}

///|
/// DR-113 §4.2 helpTypeEntry の serialize (id / value_structure / help / used_as)。
fn help_type_entry_json(entry : @kuu.HelpTypeEntry) -> Json {
  let out : Map[String, Json] = Map([])
  out.set("id", entry.id.to_json())
  out.set("value_structure", help_value_structure_json(entry.value_structure))
  match entry.help {
    Some(value) => out.set("help", value.to_json())
    None => ()
  }
  out.set("used_as", entry.used_as.to_json())
  out.to_json()
}

///|
fn help_model_json(model : @kuu.HelpModel) -> Json {
  let object : Map[String, Json] = Map([])
  object.set("outcome", "help".to_json())
  object.set("command_path", model.command_path.to_json())
  object.set("usage", help_usage_json(model.usage))
  match model.description {
    Some(value) => object.set("description", value.to_json())
    None => ()
  }
  match model.description_long {
    Some(value) => object.set("description_long", value.to_json())
    None => ()
  }
  match model.epilog {
    Some(value) => object.set("epilog", value.to_json())
    None => ()
  }
  if model.types.length() > 0 {
    let types : Array[Json] = []
    for entry in model.types {
      types.push(help_type_entry_json(entry))
    }
    object.set("types", types.to_json())
  }
  if model.commands.length() > 0 {
    let commands : Array[Json] = []
    for command in model.commands {
      commands.push(help_command_json(command))
    }
    object.set("commands", commands.to_json())
  }
  if model.options.length() > 0 {
    let options : Array[Json] = []
    for option in model.options {
      options.push(help_option_entry_json(option))
    }
    object.set("options", options.to_json())
  }
  if model.positionals.length() > 0 {
    let positionals : Array[Json] = []
    for positional in model.positionals {
      positionals.push(help_positional_json(positional))
    }
    object.set("positionals", positionals.to_json())
  }
  match model.help_entry {
    Some(value) => object.set("help_entry", value.to_json())
    None => ()
  }
  object.to_json()
}

///|
/// DR-113 §1/§9 query-error envelope の serialize。help_query 固有の失敗 (合法な definition に対する
/// 呼び出し側入力の失敗) を definition-error と別 outcome で pin する。fixture 期待は
/// `{"outcome":"query-error","errors":[{"kind":"absent-path"}]}` の形式。
fn help_query_error_json(err : @kuu.HelpQueryError) -> Json {
  let kind = match err {
    @kuu.AbsentPath => "absent-path"
    @kuu.AbsentCategory => "absent-category"
  }
  let entry : Map[String, Json] = Map([])
  entry.set("kind", kind.to_json())
  let outcome : Map[String, Json] = Map([])
  outcome.set("outcome", "query-error".to_json())
  outcome.set("errors", [entry.to_json()].to_json())
  outcome.to_json()
}

///|
fn run_help(fixture : DHelpFixture, case : DHelpCase) -> String {
  // DR-113 §1/§9 (M5-2): runner は @kuu.help を直呼びせず、canonical registry の
  // help_query capability を lookup 経由で dispatch する。未登録なら
  // "capability not registered" を surface (kuu の canonical registry は必ず含むので
  // 通常の fixture 経路では発生しない — 登録忘れの実装 regression を検知するガード)。
  let registry = canonical_registry_for_test()
  let actual = match
    @kuu.dispatch_help_query(
      registry,
      fixture.ast,
      path=case.path,
      depth=case.depth,
      category_mode=case.category_mode,
    ) {
    @kuu.Unavailable =>
      return "help_query capability not registered in canonical registry"
    @kuu.Model(model) => help_model_json(model)
    @kuu.QueryError(err) => help_query_error_json(err)
  }
  if actual == case.expect {
    "PASS"
  } else {
    "help got=" + actual.stringify() + " want=" + case.expect.stringify()
  }
}

///|
fn dec_fixture(j : Json) -> DecodedFixture raise DecodeSkip {
  let top = match j.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  match jf_str(top, "query") {
    Some("parse") => ()
    Some(q) => raise DecodeSkip("query '" + q + "' (parse/lower only)")
    None => raise DecodeSkip("missing 'query'")
  }
  let defj = match top.get("definition") {
    Some(d) => d
    None => raise DecodeSkip("missing 'definition'")
  }
  // MDR-005 §2 ドッグフーディング: definition の wire decode + lowering は production の
  // parse_definition (front_door.mbt) をそのまま使う — decode の挙動が変われば conformance が
  // 即座に検出する。
  let ast = match @kuu.parse_definition(defj) {
    Ok(a) => a
    Err(@kuu.Malformed(reason)) => raise DecodeSkip(reason)
    Err(@kuu.Rejected(errs)) =>
      raise DecodeSkip("definition rejected: " + deferrs_str(errs))
  }
  let casesj = match top.get("cases") {
    Some(c) => c
    None => raise DecodeSkip("missing 'cases'")
  }
  let carr = match casesj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("cases is not an array")
  }
  let cases : Array[DCase] = []
  for cj in carr {
    cases.push(dec_case(cj))
  }
  { ast, cases }
}

// ── fixtures discovery ────────────────────────────────────────────────────────

///|
fn is_json_file(name : String) -> Bool {
  let cs = name.to_array()
  let n = cs.length()
  n >= 5 &&
  cs[n - 5] == '.' &&
  cs[n - 4] == 'j' &&
  cs[n - 3] == 's' &&
  cs[n - 2] == 'o' &&
  cs[n - 1] == 'n'
}

///|
fn fixtures_root() -> String {
  match @env.get_env_var("KUU_FIXTURES") {
    Some(p) => if p != "" && @fs.path_exists(p) { return p }
    None => ()
  }
  for
    cand in [
      "../../../kuu/main/fixtures", "../../kuu/main/fixtures", "../../../../kuu/main/fixtures",
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
    "fixtures root not found (set KUU_FIXTURES to kuu/main/fixtures); cwd=" +
    cwd,
  )
}

///|
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

// ── the case runner ───────────────────────────────────────────────────────────

///|
fn cfg_lookup(
  files : Array[(String, @engine.ConfigVal)],
  p : String,
) -> @engine.ConfigVal? {
  for kv in files {
    if kv.0 == p {
      return Some(kv.1)
    }
  }
  None
}

///|
fn run_case(df : DecodedFixture, dc : DCase) -> String {
  // MDR-005 追記 (issue front-door-parse-missing-postprocessing): 正面玄関 `parse` は spec 準拠の
  // @engine.Outcome (DR-053) を返す = 内部で `@engine.parse_tree` → `apply_requires_filter` (DR-047 §5) →
  // `promote_collision_ambiguous` (DR-021 → DR-073) を直列適用する。runner はこの 3 段を手組みで
  // 書かず、玄関経由で受ける (kuu-cli PoC が front_door.parse を薄い wrapper のまま使うと spec
  // 非準拠 outcome を返す実バグの根治 — 二重実装の解消)。`dc.cfg` (NoCfg/CfgObj/CfgFiles) →
  // `provider: (String) -> @engine.ConfigVal?` の変換は runner 固有 (fixture の JSON 形の解釈) なのでここに
  // 残す。
  let config_provider : (String) -> @engine.ConfigVal? = match dc.cfg {
    NoCfg => fn(_p) { None }
    CfgObj(obj) => fn(_p) { Some(obj) }
    CfgFiles(files) => fn(p) { cfg_lookup(files, p) }
  }
  let ast = df.ast
  let outcome = @kuu.parse(
    ast,
    dc.args,
    env=dc.env,
    config=config_provider,
    tty=dc.tty,
  )
  let problems : Array[String] = []
  let use_resolve = dc.resolve
  match dc.outcome {
    "success" =>
      match outcome {
        @engine.Success(binds) => {
          let parse_view = @kuu.output(ast, binds)
          match dc.exp_effects {
            Some(ee) => {
              let ae = render_effects(parse_view.effects)
              if ae != ee {
                problems.push("effects got=\{ae} want=\{ee}")
              }
            }
            None => ()
          }
          if use_resolve {
            // resolve は値源ラダーを充填し、parse 相が持つ repeat row sentinel を保存する。
            // OutputView は parse binds を effects、resolved binds を result/sources に使い分ける。
            match
              @kuu.resolve(
                ast,
                outcome,
                dc.args,
                env=dc.env,
                config=config_provider,
                tty=dc.tty,
              ) {
              @engine.Success(rb) => {
                let view = @kuu.output(ast, binds, resolved=rb)
                match dc.exp_result {
                  Some(er) => {
                    let ar = render_rval_sorted(view.result)
                    if ar != er {
                      problems.push("result got=\{ar} want=\{er}")
                    }
                  }
                  None => ()
                }
                match dc.exp_sources {
                  Some(es) => {
                    let asr = render_sources(view.sources)
                    if asr != es {
                      problems.push("sources got=\{asr} want=\{es}")
                    }
                  }
                  None => ()
                }
              }
              @engine.Failure(d) =>
                problems.push(
                  "resolve error: " +
                  (if d.errors.length() > 0 {
                    d.errors[0].message
                  } else {
                    "(no message)"
                  }),
                )
              _ => problems.push("resolve returned unexpected outcome")
            }
          } else {
            match dc.exp_result {
              Some(er) => {
                let ar = render_rval_sorted(parse_view.result)
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
        @engine.Failure(d) => {
          match dc.exp_errors {
            Some(ex) => {
              let ae = proj_errors(
                d.errors,
                dc.exp_errors_with_reason,
                dc.exp_errors_with_path,
              )
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
          if dc.help_cmp {
            let got = match d.help_entry {
              Some(s) => s
              None => "(none)"
            }
            let want = match dc.help_exp {
              Some(s) => s
              None => "(none)"
            }
            if got != want {
              problems.push("help_entry got=\{got} want=\{want}")
            }
          }
          if dc.tried_cmp {
            let got = proj_tried_triggers(d.tried_triggers)
            let want = match dc.tried_exp {
              Some(s) => s
              None => "{}"
            }
            if got != want {
              problems.push("tried_triggers got=\{got} want=\{want}")
            }
          }
        }
        // DR-009 §7 final_filters/accum_filters (and any other resolve-layer check, e.g. a future
        // constraint that only resolve sees): `parse()` itself can succeed while the VALUE
        // resolution layer (env/config/inherit/default ladder fill + filter chains,
        // resolve.mbt) still rejects — a "failure" fixture case exercising THAT path needs
        // the resolve check run here too, mirroring the "success" branch's
        // `use_resolve`-gated `do_resolve` call. Without this, a resolve-layer Err was
        // invisible to `"failure"` fixtures entirely (this function's `match outcome` never
        // called resolve at all before) — `@engine.Success` fell straight to the `other` catch-all
        // below and got mis-reported as EXPECTED-FAILURE got=ok{...}.
        @engine.Success(_) if use_resolve =>
          match
            @kuu.resolve(
              ast,
              outcome,
              dc.args,
              env=dc.env,
              config=config_provider,
              tty=dc.tty,
            ) {
            @engine.Failure(d) =>
              match dc.exp_errors {
                Some(ex) => {
                  let ae = proj_errors(
                    d.errors,
                    dc.exp_errors_with_reason,
                    dc.exp_errors_with_path,
                  )
                  if ae != ex {
                    problems.push("errors got=\{ae} want=\{ex}")
                  }
                }
                None => ()
              }
            @engine.Success(_) =>
              problems.push("EXPECTED-FAILURE got=ok (resolve also succeeded)")
            _ => ()
          }
        other => problems.push("EXPECTED-FAILURE got=" + render_outcome(other))
      }
    _ =>
      match outcome {
        @engine.Ambiguous(d) => {
          match dc.exp_interps {
            Some(ei) => {
              let got : Array[String] = []
              for interp in d.interpretations {
                // Result-object view is always rendered (DR-053 §3 骨格温存)。
                let view = render_rval_sorted(
                  @kuu.output_of_interpretation(ast, interp),
                )
                // DR-073 §1: append `#claimants{...}` suffix only when the interpretation carries
                // a non-empty claimants面 (matches exp_interp_str's `view + "#claimants" + ...`
                // encoding at line 1500). Non-collision interpretations render as bare view — the
                // renderer must not synthesize an empty `#claimants{}` for those (would fail the
                // structural or-position/repeat/prefix-guard ambiguous fixtures whose expected
                // form is view-only, not `view#claimants{}`).
                if interp.claimants.length() == 0 {
                  got.push(view)
                } else {
                  let items : Array[String] = []
                  for kv in interp.claimants {
                    items.push(kv.0 + "=" + kv.1)
                  }
                  sort_items(items)
                  got.push(view + "#claimants{" + join_comma(items) + "}")
                }
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
          if dc.help_cmp {
            let got = match d.help_entry {
              Some(s) => s
              None => "(none)"
            }
            let want = match dc.help_exp {
              Some(s) => s
              None => "(none)"
            }
            if got != want {
              problems.push("help_entry got=\{got} want=\{want}")
            }
          }
        }
        other =>
          problems.push("EXPECTED-AMBIGUOUS got=" + render_outcome(other))
      }
  }
  if problems.length() == 0 {
    "PASS"
  } else {
    let sb = StringBuilder::new()
    let mut first = true
    for p in problems {
      if !first {
        sb.write_string(" | ")
      }
      sb.write_string(p)
      first = false
    }
    sb.to_string()
  }
}

// ── ledgers (MDR-001 §6: start empty, populate as fixtures classify) ─────────

///|
/// The FROZEN divergence ledger (fixture = 正本, main src/kuu = 被検体).
///
/// Each entry is the FULL `rel::slug :: verdict` string of a comparison that currently diverges —
/// a KNOWN gap either INHERITED from slice/poc (未実装が正本仕様に追従していない) or a suspected
/// fixture-authoring issue frozen for later resolution. The runner asserts the observed divergence
/// SET equals this ledger: UNEXPECTED and VANISHED entries both fail (verdict-granularity freeze,
/// MDR-001 §6). @engine.Empty = full conformance (no known gaps against the fixture corpus).
fn known_divergences() -> Array[String] {
  // M4 (DR-113 §4): help model 構築を新 schema へ全面移行 (value_structure tree / origin 4 形 /
  // hidden・deprecated required emit / command aliases 併記 / depth=all 再帰 scope 埋め込み /
  // help_category の or[bool,string] 展開)。origin 逆推定 (link_depth → global declared_at /
  // 名前 prefix + descendant inheritable 検索 → inheritable declared_at) は help.mbt 側で
  // scope 側テーブルを組んで解決する — installer は変更していない (5 preset canonical 展開の
  // HelpMetaInstaller.apply 移送と capability dispatch は次 milestone、以下 「M5 残」)。
  //
  // M5 残 (本 milestone 未実装 — help.mbt 単独では埋められない箇所):
  //   - 5 preset canonical 展開の HelpMetaInstaller.apply 移送 (現在 wire_decode 暫定)。
  //     help_category の value_name "CATEGORY" default は現在 help.mbt 側で defaulting。
  //   - help_query capability の runner dispatch 化 (現在 @kuu.help 直呼び)。
  //   - types 集約射影 + type_ref + used_as (value-structure-and-types.json は decode skip 継続)。
  //   - fixed default_fn の default 席射影 (P2H-Q3 裁定に沿った dynamic default_fn は model 非搭載)。
  [
  // M4: help model 全面移行完了 — 全 help fixture case が green (以下 ledger は空)。
  ]
}

///|
/// The FROZEN skip ledger — decode-time twin of `known_divergences`. Each entry is `(rel, reason)`:
/// a fixture the decoder cannot losslessly represent, so it raises DecodeSkip before any case runs.
/// UNEXPECTED / VANISHED / CHANGED SKIP REASON all fail the run (like divergences, MDR-001 §6).
///
/// Every fixture in the corpus (including DR-099's `builtin/tty` preset-type fixtures — the
/// `definitions.types` factory branch and the case-level `{terminal, cygwin}` observation decode,
/// both `dec_types`/`dec_case` above) decodes and runs losslessly — full conformance, no known skip
/// gaps.
fn expected_skips() -> Array[(String, String)] {
  // M2 gap: help-category vocab / help annotation on value-structure are M3+ features. Fixtures
  // that carry these unsupported keys are skipped at decode time; entries pinned here so a decode
  // regression (unexpected new skip) or accidental fix (vanished skip) fails the run.
  // M5 (DR-113 §4.2): value-structure-and-types.json は dec_types tree-form + option
  // seq wire キー + type_ref carry を M5 で全て実装済み、skip 解消。expected_skips は空
  // (全 fixture 損失なく decode 可能)。
  []
}

///|
fn case_key(rel : String, id : String) -> String {
  rel + "::" + id
}

///|
fn is_kebab(s : String) -> Bool {
  if s == "" {
    return false
  }
  let mut prev_dash = true
  for c in s {
    if c == '-' {
      if prev_dash {
        return false
      }
      prev_dash = true
    } else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      prev_dash = false
    } else {
      return false
    }
  }
  !prev_dash
}

///|
fn raw_case_ids(j : Json) -> Array[String]? {
  let top = match j.j_obj() {
    Some(o) => o
    None => return None
  }
  let casesj = match top.get("cases") {
    Some(c) => c
    None => return None
  }
  let carr = match casesj.j_arr() {
    Some(x) => x
    None => return None
  }
  let ids : Array[String] = []
  for cj in carr {
    ids.push(
      match cj.j_obj() {
        Some(co) => jf_str(co, "id").unwrap_or("")
        None => ""
      },
    )
  }
  Some(ids)
}

///|
fn check_ids(rel : String, ids : Array[String]) -> Array[String] {
  let bad : Array[String] = []
  let seen : Map[String, Int] = Map([])
  let mut ci = 0
  for id in ids {
    ci = ci + 1
    if id == "" {
      bad.push(
        rel +
        "::case#" +
        ci.to_string() +
        " — id 欠落または非文字列 (DR-072: 各 case は required の kebab-case id を持つ)",
      )
    } else if !is_kebab(id) {
      bad.push(
        rel +
        "::case#" +
        ci.to_string() +
        " — id '" +
        id +
        "' が kebab-case ([a-z0-9-]) でない",
      )
    } else {
      match seen.get(id) {
        Some(first) =>
          bad.push(
            rel +
            "::case#" +
            ci.to_string() +
            " — id '" +
            id +
            "' が fixture 内で重複 (初出 case#" +
            first.to_string() +
            ")",
          )
        None => seen.set(id, ci)
      }
    }
  }
  bad
}

///|
fn load_json(path : String) -> Json raise {
  @json.parse(@fs.read_file_to_string(path))
}

///|
test "conformance: fixtures を JSON 直読みで実食 (parse 語彙網羅 + lower 5 面断面)" {
  let root = fixtures_root()
  let rels : Array[String] = []
  collect_rel(root, "", rels) catch {
    _ => abort("fixtures walk failed under " + root)
  }
  sort_items(rels)
  let decoded : Array[String] = []
  let skips : Array[(String, String)] = []
  let mismatches : Array[String] = []
  let malformed : Array[String] = []
  let mut ran_cases = 0
  for rel in rels {
    let full = root + "/" + rel
    let j = load_json(full) catch {
      _ => {
        skips.push((rel, "load/parse error"))
        continue
      }
    }
    let id_bad : Array[String] = match raw_case_ids(j) {
      Some(ids) => check_ids(rel, ids)
      None => []
    }
    for b in id_bad {
      malformed.push(b)
    }
    let q = match j.j_obj() {
      Some(o) => jf_str(o, "query").unwrap_or("")
      None => ""
    }
    if q == "lower" {
      // lower の内部構造比較は同 package の `verify_lower_conformance_fixtures` が担う。
      // ここでは corpus 全体の decoded/ran_cases 基準値を維持するため dispatch 件数だけを数える。
      decoded.push(rel)
      ran_cases = ran_cases + 1
      continue
    }
    if q == "definition_error" {
      let fx = dec_definition_error_fixture(j) catch {
        DecodeSkip(reason) => {
          skips.push((rel, reason))
          continue
        }
      }
      decoded.push(rel)
      for c in fx.cases {
        ran_cases = ran_cases + 1
        let verdict = run_definition_error(fx, c)
        if verdict != "PASS" {
          mismatches.push(case_key(rel, c.id) + " :: " + verdict)
        }
      }
      continue
    }
    if q == "help" {
      let fx = dec_help_fixture(j) catch {
        DecodeSkip(reason) => {
          skips.push((rel, reason))
          continue
        }
      }
      decoded.push(rel)
      for c in fx.cases {
        ran_cases = ran_cases + 1
        let verdict = run_help(fx, c)
        if verdict != "PASS" {
          mismatches.push(case_key(rel, c.id) + " :: " + verdict)
        }
      }
      continue
    }
    if q == "complete" {
      let fx = dec_complete_fixture(j) catch {
        DecodeSkip(reason) => {
          skips.push((rel, reason))
          continue
        }
      }
      decoded.push(rel)
      for c in fx.cases {
        ran_cases = ran_cases + 1
        let verdict = run_complete(fx, c)
        if verdict != "PASS" {
          mismatches.push(case_key(rel, c.id) + " :: " + verdict)
        }
      }
      continue
    }
    let df = dec_fixture(j) catch {
      DecodeSkip(reason) => {
        skips.push((rel, reason))
        continue
      }
    }
    decoded.push(rel)
    if id_bad.length() > 0 {
      continue
    }
    for c in df.cases {
      ran_cases = ran_cases + 1
      let verdict = run_case(df, c)
      if verdict != "PASS" {
        mismatches.push(case_key(rel, c.id) + " :: " + verdict)
      }
    }
  }
  let known = known_divergences()
  let unexpected : Array[String] = []
  for mismatch in mismatches {
    if !conformance_str_in(known, mismatch) {
      unexpected.push(mismatch)
    }
  }
  println(
    "[json-conformance] decoded=\{decoded.length()} ran_cases=\{ran_cases} skipped=\{skips.length()} mismatches=\{unexpected.length()}",
  )
  println("[json-conformance] decoded: " + join_comma(decoded))
  let hist : Map[String, Int] = Map([])
  for pair in skips {
    let r = pair.1
    hist.set(
      r,
      (match hist.get(r) {
        Some(n) => n
        None => 0
      }) +
      1,
    )
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
  for m in malformed {
    println("[json-conformance]   malformed " + m)
  }
  // Assert malformed-id list is empty.
  if malformed.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("fixture case-id well-formedness violation (DR-072):\n")
    for m in malformed {
      sb.write_string("  " + m + "\n")
    }
    println(sb.to_string())
    abort(sb.to_string())
  }
  // Skip ledger assertion (empty ledger; any observed skip is UNEXPECTED for now).
  let sk_ledger = expected_skips()
  let unexpected_skips : Array[String] = []
  let changed_skips : Array[String] = []
  for pair in skips {
    let rel = pair.0
    let reason = pair.1
    let mut found_reason : String? = None
    for e in sk_ledger {
      if e.0 == rel {
        found_reason = Some(e.1)
        break
      }
    }
    match found_reason {
      None => unexpected_skips.push(rel + " :: " + reason)
      Some(want) =>
        if want != reason {
          changed_skips.push(rel + " :: got=" + reason + " want=" + want)
        }
    }
  }
  let vanished_skips : Array[String] = []
  for e in sk_ledger {
    let mut still_skipped = false
    for pair in skips {
      if pair.0 == e.0 {
        still_skipped = true
        break
      }
    }
    if !still_skipped {
      vanished_skips.push(e.0)
    }
  }
  if unexpected_skips.length() > 0 ||
    vanished_skips.length() > 0 ||
    changed_skips.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("skip ledger mismatch:\n")
    if unexpected_skips.length() > 0 {
      sb.write_string("  UNEXPECTED SKIP:\n")
      for s in unexpected_skips {
        sb.write_string("    " + s + "\n")
      }
    }
    if vanished_skips.length() > 0 {
      sb.write_string("  VANISHED SKIP:\n")
      for s in vanished_skips {
        sb.write_string("    " + s + "\n")
      }
    }
    if changed_skips.length() > 0 {
      sb.write_string("  CHANGED SKIP REASON:\n")
      for s in changed_skips {
        sb.write_string("    " + s + "\n")
      }
    }
    println(sb.to_string())
    abort(sb.to_string())
  }
  // Divergence ledger assertion: unregistered or vanished entries fail the run.
  let vanished : Array[String] = []
  for k in known {
    if !conformance_str_in(mismatches, k) {
      vanished.push(k)
    }
  }
  if unexpected.length() > 0 || vanished.length() > 0 {
    let sb = StringBuilder::new()
    sb.write_string("divergence ledger mismatch:\n")
    if unexpected.length() > 0 {
      sb.write_string("  UNEXPECTED:\n")
      for m in unexpected {
        sb.write_string("    " + m + "\n")
      }
    }
    if vanished.length() > 0 {
      sb.write_string("  VANISHED:\n")
      for k in vanished {
        sb.write_string("    " + k + "\n")
      }
    }
    println(sb.to_string())
    abort(sb.to_string())
  }
}

///|
/// MDR-004 §4 / 実装順 5: @engine.OrBranch.id (無指定なら自動採番 `#{seq}`) は内部照合専用で、観測面
/// (held Error / ambiguous interpretations / success result) のどこにも漏れてはいけない。対象
/// 4 fixture はどれも "id" キー無指定 (= 自動採番のみ) なので、既にそれ自体が非漏出の状況証拠で
/// はある — が、fixture 任せだと「将来誰かが .id を表示経路に配線してしまう」退行を検出できない
/// (codex REVIEW-M5)。ここでは同じ定義形 (対称 or の 2 枝、held-errors-same-depth.json と同型) を
/// inline JSON で組み、failure (0 本成立) / ambiguous (2 本成立) / success (1 本のみ生存) の 3 outcome
/// すべてで、rendered text に自動 id パターン ("#0" / "#1") が一切現れないこと、かつ本来の leaf 名
/// (a/b) は現れることを同時に固定する。
test "conformance: @engine.OrBranch auto id (#{seq}) は held-error / ambiguous / success のどこにも漏れない (MDR-004 §4)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "positionals": [
    #|      {"or": [{"type": "number", "name": "a"}, {"type": "number", "name": "b"}]}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let j = @json.parse(src)
  let df = dec_fixture(j)
  let no_leak = fn(s : String) -> Unit {
    if s.contains("#0") || s.contains("#1") {
      abort("auto branch id leaked into observable text: \{s}")
    }
  }
  // failure (0 本成立): 非数値 1 token は両枝とも同位置で dead-end (same-depth 同型)。
  let fail_outcome = @kuu.parse(df.ast, ["x"])
  match fail_outcome {
    @engine.Failure(d) => {
      let texts : Array[String] = []
      for e in d.errors {
        texts.push(e.element + ":" + e.message)
      }
      let joined = join_comma(texts)
      no_leak(joined)
      if !joined.contains("a:") || !joined.contains("b:") {
        abort("expected both leaf names (a/b) in failure text, got: \{joined}")
      }
    }
    other => abort("expected @engine.Failure, got " + render_outcome(other))
  }
  // ambiguous (2 本成立): 数値 1 token は両枝が同位置で成立 → 2 完全経路。
  let amb_outcome = @kuu.parse(df.ast, ["5"])
  match amb_outcome {
    @engine.Ambiguous(d) => {
      let views : Array[String] = []
      for interp in d.interpretations {
        views.push(render_rval_sorted(@kuu.output(df.ast, interp.binds).result))
      }
      let joined = join_comma(views)
      no_leak(joined)
      if !joined.contains("a=5") || !joined.contains("b=5") {
        abort(
          "expected both interpretations (a=5/b=5) in ambiguous text, got: \{joined}",
        )
      }
    }
    other => abort("expected @engine.Ambiguous, got " + render_outcome(other))
  }
  // success (1 本のみ生存) は対称 2 枝 (a/b 共に number) では作れない — 両枝は常に対称に成立/
  // 不成立するため、単一トークン args では必ず failure か ambiguous になる。success 面の非漏出は
  // path-search/variable-arity-ambiguous.json::non-number-collapses-to-name (既存 conformance、
  // 非対称 2 枝で数値枝のみ死ぬケース) が別途固定済みなので、本 wbtest は failure/ambiguous の
  // 2 outcome をスコープとする。
}

// ── DR-078: definitions.templates + ref (蒸留 1:1 audit 漏れ #1/#2, slice phase4:114/phase10:64) ──

///|
/// 保証 (蒸留 1:1 audit 漏れ #1、slice `poc/phase4_wbtest.mbt:125-152` 相当、DR-078 §1 の decode
/// 配線疎通): `hlcolors := color+` (positional が `ref:"color"` + `repeat:{min:1}`、`color` は
/// `definitions.templates` に `or [ [r,g,b] な 3 数値 seq | 文字列 colorname ]` (DR-078 §1 の例
/// そのもの) として宣言された共有 template) が正しく decode → lowering → parse される。
/// 文字列名の繰り返し (`red blue`) は各発火が colorname 枝を辿るだけの一義的な parse。
/// `255 0 0` は「1 回発火・rgb 枝 (3 トークン消費)」と「3 回発火・colorname 枝 (1 トークンずつ)」の
/// 構造的に異なる完全経路が両立し、ambiguous:2 になる (or 枝の違いは DR-043 の取り分選好の対象外 —
/// 選好は「同じ closure の分け方」の中でしか効かない、次の wbtest で対で固定)。
test "DR-078: definitions.templates + ref — repeat over a shared or-template (hlcolors := color+)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"templates": {"color": {"or": [
    #|      {"seq": [{"type": "number", "name": "r"}, {"type": "number", "name": "g"}, {"type": "number", "name": "b"}]},
    #|      {"type": "string", "name": "colorname"}
    #|    ]}}},
    #|    "positionals": [
    #|      {"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let df = dec_fixture(@json.parse(src))
  // 純文字列の繰り返し: colorname 枝のみが成立する一義的な parse (rgb 枝は数値でないトークンで dead-end)。
  // render_outcome は binding を flat key=value (sort 済み) で描画する (slice の ok{name=blue,name=red}
  // と同じ形、色テンプレの leaf 名は "colorname")。
  assert_eq(
    render_outcome(@kuu.parse(df.ast, ["red", "blue"])),
    "ok{colorname=blue,colorname=red}",
  )
  // rgb 枝 (1 回発火, 3 トークン) vs colorname 枝 (3 回発火, 1 トークンずつ) — 構造的に異なる完全経路
  // が両立し ambiguous:2 (DR-038)。
  assert_eq(
    render_outcome(@kuu.parse(df.ast, ["255", "0", "0"])),
    "ambiguous:2",
  )
}

///|
/// 保証 (蒸留 1:1 audit 漏れ #2、slice `poc/phase10_wbtest.mbt:90-108` 相当): repeat の取り分選好
/// (preference、DR-043) は「同じ closure の分け方」次元にのみ効き、or 枝の違い (構造的に異なる完全
/// 経路) を侵食してかき消さない。`255 0 0` は前 wbtest と同じく ambiguous:2 のまま — 選好は「同点の
/// share だけ絞る」ものであって「or 枝の差を潰す」ものではないことを固定する。純文字列 args には
/// rgb 読みが無いので (すべて非数値) split は一意 — 選好の有無に関わらず成立するケースとして対比する。
test "DR-078: preference does not erode or-branch ambiguity (share-dimension only, DR-043)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"templates": {"color": {"or": [
    #|      {"seq": [{"type": "number", "name": "r"}, {"type": "number", "name": "g"}, {"type": "number", "name": "b"}]},
    #|      {"type": "string", "name": "colorname"}
    #|    ]}}},
    #|    "positionals": [
    #|      {"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(
    render_outcome(@kuu.parse(df.ast, ["255", "0", "0"])),
    "ambiguous:2",
  )
  assert_eq(
    render_outcome(@kuu.parse(df.ast, ["red", "green", "blue"])),
    "ok{colorname=blue,colorname=green,colorname=red}",
  )
}

///|
/// 保証 (codex 節目レビュー指摘1、issue 2026-07-09-ref-template-result-shape): wire schema の name/id
/// 制約 `^[^#]+$` (DR-067 §2「`#` を含む name/id はユーザ定義で禁止」、内部予約名前空間 = repeat
/// lowering の `<name>#cons` / `next_or_branch_id` の `#0`/`#1`/… / resolve.mbt の row/fire sentinel
/// "#row"/"#fire") を decode 層が enforce することを、`#` の出現しうる箇所ごとにマトリクスで固定する
/// — 1 箇所だけ確認すると「たまたま通ってた」を見逃す (empirical-verification のサンプル数原則)。
/// positional の name / option の name / definitions.templates の template key の 3 カテゴリで
/// decode が `DecodeSkip` (definition の decode error、既存語彙のまま) を投げることを確認する。
test "decode: a `#` in name/id is rejected at every user-facing name surface (codex review #1)" {
  // (1) positional の name。`@json.parse` (raise @engine.ParseError) を try の外で先に評価しておく —
  // `dec_fixture` 自身の `raise DecodeSkip` だけを catch で汲む。
  let pos_src =
    #|{"query":"parse","definition":{"positionals":[{"name":"src#cons","type":"string"}]},"cases":[]}
  let pos_j = @json.parse(pos_src)
  let _ = dec_fixture(pos_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("#"))
      return
    }
  }
  abort("positional name 'src#cons': expected DecodeSkip, decode succeeded")
}

///|
test "decode: a `#` in an option's name is rejected (codex review #1)" {
  let opt_src =
    #|{"query":"parse","definition":{"options":[{"name":"hl#colors","type":"string","long":true}]},"cases":[]}
  let opt_j = @json.parse(opt_src)
  let _ = dec_fixture(opt_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("#"))
      return
    }
  }
  abort("option name 'hl#colors': expected DecodeSkip, decode succeeded")
}

///|
/// definitions.templates の template key (DR-078 §1 の ref 対象名) も同じ予約名前空間 — `ref:` が
/// 指す先の key が `#` を含めば、repeat lowering の内部 template キー (`<name>#cons`) と衝突しうる。
test "decode: a `#` in a definitions.templates key is rejected (codex review #1)" {
  let tmpl_src =
    #|{"query":"parse","definition":{"definitions":{"templates":{"co#lor":{"type":"string","name":"c"}}},"positionals":[{"name":"hlcolor","ref":"co#lor"}]},"cases":[]}
  let tmpl_j = @json.parse(tmpl_src)
  let _ = dec_fixture(tmpl_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("#"))
      return
    }
  }
  abort("template key 'co#lor': expected DecodeSkip, decode succeeded")
}

///|
/// 対極確認 ([[self-written-rule-blind-spots]]): `#` を含まない普通の name は一切影響を受けない —
/// 上の 3 テストが「拒否すべき形を通さない」ことの確認なら、これは「拒否してはいけない形を誤って落と
/// さない」ことの確認。`hlcolors := color+` (このissueの本題そのもの) が今も decode + parse を通る
/// ことを固定する。
test "decode: an ordinary `#`-free name is unaffected by the reserved-name check (codex review #1 対極)" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"templates": {"color": {"or": [
    #|      {"seq": [{"type": "number", "name": "r"}, {"type": "number", "name": "g"}, {"type": "number", "name": "b"}]},
    #|      {"type": "string", "name": "colorname"}
    #|    ]}}},
    #|    "positionals": [
    #|      {"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}
    #|    ]
    #|  },
    #|  "cases": []
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(render_outcome(@kuu.parse(df.ast, ["red"])), "ok{colorname=red}")
}

///|
/// DR-066 §4 harness smoke test: `errors[].path` opt-in actually drives `run_case`'s comparison,
/// not just decodes without effect. A `--n` (number) value slot inside a `sub` command scope fails
/// to parse ("abc" is not a number) one command deep. The CORRECT-path case (`path: ["sub"]`) must
/// PASS; the WRONG-path case (`path: ["not-sub"]`, everything else identical) must FAIL — proving
/// `proj_errors`/`exp_errors_decode` round-trip the path into the comparison, mirroring how the
/// existing `reason` opt-in is exercised end-to-end by the real fixture corpus.
test "conformance harness: errors[].path opt-in is compared, not merely decoded (DR-066 §4)" {
  let src =
    #|{
    #|  "why": "DR-066 §4 harness smoke test for errors[].path opt-in",
    #|  "query": "parse",
    #|  "definition": {
    #|    "commands": [
    #|      {
    #|        "type": "command",
    #|        "name": "sub",
    #|        "options": [
    #|          {"name": "n", "type": "number", "long": true}
    #|        ]
    #|      }
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "correct-path",
    #|      "why": "path: [\"sub\"] matches the actual ancestor (n fails inside the sub command scope)",
    #|      "args": ["sub", "--n", "abc"],
    #|      "expect": {
    #|        "outcome": "failure",
    #|        "errors": [
    #|          {"element": "n", "args_pos": 2, "kind": "parse", "reason": "not_a_number", "path": ["sub"]}
    #|        ]
    #|      }
    #|    },
    #|    {
    #|      "id": "wrong-path",
    #|      "why": "path: [\"not-sub\"] is deliberately wrong — must be caught as a mismatch",
    #|      "args": ["sub", "--n", "abc"],
    #|      "expect": {
    #|        "outcome": "failure",
    #|        "errors": [
    #|          {"element": "n", "args_pos": 2, "kind": "parse", "reason": "not_a_number", "path": ["not-sub"]}
    #|        ]
    #|      }
    #|    }
    #|  ]
    #|}
  let j = @json.parse(src)
  let df = dec_fixture(j)
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if c.id == "correct-path" {
      if verdict != "PASS" {
        abort("expected PASS for correct-path, got: \{verdict}")
      }
    } else if verdict == "PASS" {
      abort("expected a path mismatch for wrong-path, got PASS")
    }
  }
}

///|
/// 保証 (issue 2026-07-09-constraint-path-filtering-gap の元 exact repro、DR-047 §5 明確化
/// kawaz 裁定 2026-07-09 後の end-to-end 確認): alias で同一トリガ `--v` を持つ 2 経路 (a に
/// `requires:["c"]`、c はフラグ) に対し、`run_case` (= `apply_requires_filter` →
/// `promote_collision_ambiguous` の直列適用込みの harness 本経路) が3ケースとも正しい outcome を
/// 返すことを固定する。`c` には `env:["C"]` を追加している (元 exact repro には無かったが、env
/// 救済ケースの検証に必要 — DR-047 §5 明確化「値源不問」の env 面カバー)。
test "DR-047 §5 end-to-end: exact issue repro (alias same trigger, requires) via run_case" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "a", "type": "flag", "requires": ["c"]},
    #|      {"alias": "a", "name": "v", "long": [":set:true"]},
    #|      {"name": "b", "type": "flag"},
    #|      {"alias": "b", "name": "v", "long": [":set:true"]},
    #|      {"name": "c", "type": "flag", "long": true, "env": ["C"]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "c-unset-a-excluded",
    #|      "args": ["--v"],
    #|      "expect": {"outcome": "success", "effects": [
    #|        {"entity": "b", "op": "set", "operand": true, "source": "cli"}
    #|      ]}
    #|    },
    #|    {
    #|      "id": "c-cli-both-survive",
    #|      "args": ["--v", "--c"],
    #|      "expect": {"outcome": "ambiguous"}
    #|    },
    #|    {
    #|      "id": "c-env-both-survive",
    #|      "args": ["--v"],
    #|      "env": {"C": "true"},
    #|      "expect": {"outcome": "ambiguous"}
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 3)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("case '" + c.id + "' expected PASS, got: " + verdict)
    }
  }
}

///|
/// 保証 (DR-088 更新、issue value-present-ladder-gap): target `c` が非フラグ (string、default
/// 無し、env 宣言あり) の場合、env 宣言は「その値源から遅延解決する default_fn が設定されている」
/// のと同型 (DR-088 §1) — 探索中は宣言の有無だけで経路完全性を判定し (§2)、最終判定は解決後の
/// 実値を見る (§3)。env に実値があれば requires は充足する — 旧実装は `committed` の定義に
/// env を含めない (DR-047 §5「committed の定義は本 DR で変更しない」) ことを根拠に env 供給の
/// non-bool target を一律未充足としていたが、これは committed (トリガ判定の基準) と目的語の値
/// 充足判定 (別の基準、DR-088 で env 宣言込みに拡張) を混同していた誤りだった (spec fixture
/// `constraints-parse/requires-bool-target-contrast.json::c-env-set-satisfies-requires` として
/// 修正済み、本 wbtest はその同型ケースを end-to-end で固定)。
test "DR-088 end-to-end: non-bool target requires is satisfied via the env rescue path" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "a", "type": "flag", "long": true, "requires": ["c"]},
    #|      {"name": "c", "type": "string", "long": true, "env": ["C"]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "c-env-set-satisfies-requires",
    #|      "args": ["--a"],
    #|      "env": {"C": "x"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "a", "op": "set", "operand": true, "source": "cli"}]
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 保証 (team-lead 指摘: 生存 0 → @engine.Failure の fired_action/help_entry/tried_triggers が既存
/// KTop 発 @engine.Failure と同じ素材関数 (`@engine.collect_actions`/`@engine.argmin_action`/`@engine.find_help_entry`/
/// `@engine.tried_triggers_of`) から構築され、整合が取れていることの end-to-end 確認): help
/// (`type:"help"`, DR-048 失敗時アクション) が selected な経路が、bool-target requires 違反で
/// `apply_requires_filter` により @engine.Failure に変換されても、`fired_action` が正しく "help"
/// になることを固定する。`--help --a` で help・a 共に発火 (help selected)、a は requires:[c]
/// 未充足 (c はフラグ、CLI/env どちらも未指定で false) → @engine.Success(1本) が @engine.Failure に変換される
/// 経路で、KTop 発 @engine.Failure (`failure-actions/help-basic.json`) と同じ fired_action 契約が
/// 保たれることを確認する (DR-053 §2 「fired_action と errors が 1 @engine.Failure に両立」)。
test "DR-047 §5 end-to-end: fired_action (help) survives the post-filter @engine.Success→@engine.Failure conversion" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "help", "type": "help", "long": true},
    #|      {"name": "a", "type": "flag", "long": true, "requires": ["c"]},
    #|      {"name": "c", "type": "flag", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "help-selected-survives-bool-requires-failure",
    #|      "args": ["--help", "--a"],
    #|      "expect": {
    #|        "outcome": "failure",
    #|        "errors": [{"element": "a", "args_pos": 2, "kind": "constraint", "reason": "requires_violated"}],
    #|        "fired_action": "help"
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── DR-096 §3.3 (kawaz 裁定 2026-07-12): long_prefix / long_eq_sep decode (scope-level, team-lead
// 裁定 2026-07-11: 正本は definition/scope の wire キー — 要素単位は未規定語彙のため不受理) ──────

// ── issue scope-config-object-gap: DR-014 full 7-key config object + 階層継承 ─────

///|
/// 保証 (issue type-none-support, DR-089 §2/§3): JSON fixture 上で `type` を省略した option が
/// none として decode され、消費 0 の純トリガとして発火・resolve を通り、シンプルモードの結果には
/// キーが一切現れない (`result: {}`) — DR-051 §1/§4 の「値の無さはフィールド不在」と同型。
/// effects にも現れない (team-lead 裁定 2026-07-11: 観測は ParserContext/explains 層の管掌、値
/// 空間なしの set エントリを発明しない — 内部表現は `flag_bare_true_variant` 再利用の @engine.Set +
/// @engine.Bool(true) placeholder のままだが、`OutputView.effects` が none cell を除外する)。

///|
test "DR-089 end-to-end: an omitted-type option decodes to none, fires as a pure trigger, absent from result" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "sep", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "sep-fires-pure-trigger",
    #|      "args": ["--sep"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 対極: `type: "none"` を明示しても同じ挙動 (DR-089 §2「省略 = none の糖衣」の end-to-end 対称確認)。
test "DR-089 end-to-end: an explicit type:none option behaves identically to omission" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "sep", "type": "none", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "sep-fires-pure-trigger-explicit",
    #|      "args": ["--sep"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── DR-092: inf / 非整数 float の JSON serialize 規約 (end-to-end via dec_fixture/run_case) ──

///|
/// 保証 (DR-092 §1/§2「inf は JSON string sentinel "Infinity"/"-Infinity" で表す」、実装調査
/// 2026-07-11 の実機確認結果): fixture の `result` 位置に JSON 文字列 `"Infinity"` を書いた期待値
/// (DR-092 §1 の wire 表現そのもの) が、実際の `--t inf` (float 型) 実行結果と一致する — 双方とも
/// `render_val` を経由し、GOT 側は `@engine.Number(inf)` → MoonBit Ryu 実装の "Infinity" 特殊形、EXPECT 側は
/// JSON string decode (`json_to_value` は文字列をそのまま `@engine.String` に写す) → `render_val(@engine.String(s)) =
/// s` の素通し、で同じ文字列 "Infinity" に収束する。**production コード変更なしで DR-092 の wire
/// 表現規約が conformance harness 上で既に成立する**ことを end-to-end で固定する
/// (fixtures/value-typing/number-inf-nan.json への実 pin は main が別段で行う予定、本テストは
/// spec fixture を一切変更せずインライン JSON で同じ輪郭を先に固定するもの)。
test "DR-092 end-to-end: --t inf round-trips through result as the JSON string sentinel \"Infinity\"" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "t", "type": "float", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "inf-result-serializes-as-json-string-sentinel",
    #|      "args": ["--t", "inf"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "t", "op": "set", "operand": "Infinity", "source": "cli"}],
    #|        "result": {"t": "Infinity"}
    #|      }
    #|    },
    #|    {
    #|      "id": "neg-inf-result-serializes-as-json-string-sentinel",
    #|      "args": ["--t", "-Infinity"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "t", "op": "set", "operand": "-Infinity", "source": "cli"}],
    #|        "result": {"t": "-Infinity"}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

///|
/// 保証 (DR-092 §4「非整数 float の canonical serialize = shortest round-trip」、end-to-end):
/// `--t 3.14159` の result が入力綴りそのまま (丸め/桁欠落なし) で戻る — shortest round-trip の
/// 「入力と同じ最短表現に落ち着く」性質を CLI 入力からの往復で確認する (`@engine.value_str`/`render_val`
/// 直接テストの resolve_wbtest.mbt 版と対で、こちらは実 args からの end-to-end)。
test "DR-092 end-to-end: a non-integer float CLI value round-trips via shortest round-trip in result" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "t", "type": "float", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "non-integer-float-shortest-round-trip",
    #|      "args": ["--t", "3.14159"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [{"entity": "t", "op": "set", "operand": 3.14159, "source": "cli"}],
    #|        "result": {"t": 3.14159}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── codex 節目レビュー Major 1: 要素単位 scope config override ─────────────────

///|
/// 保証 (end-to-end, DR-049 §4 HOME motivating case の完全版): `HOME` (env_prefix opt-out) の値を
/// 実際の env lookup → parse → result まで通す。auto_env:true 下で `port` は自動導出
/// (`MYAPP_PORT`) された env 名で環境変数を読み、`home_dir` は opt-out した生の `HOME` を読む —
/// 同じスコープに両方の挙動が共存することを実行結果で固定する。
test "DR-049 §4 end-to-end: an element's env_prefix:\"\" opt-out reads the raw env var name, alongside a sibling's prefixed auto_env" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "port", "type": "number"},
    #|      {"name": "home_dir", "type": "string", "env": "HOME", "config": {"env_prefix": ""}}
    #|    ],
    #|    "config": {"env_prefix": "MYAPP", "env_auto": true}
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "opt-out-element-reads-raw-env-name",
    #|      "args": [],
    #|      "env": {"MYAPP_PORT": "8080", "HOME": "/home/kawaz"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "sources": {"port": "env", "home_dir": "env"}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── codex 節目レビュー Minor: DR-092 §5 config 値源経路の実装証跡 ───────────────

///|
/// 保証 (codex 指摘 Minor, DR-092 §5「config ファイルの JSON 値位置に "Infinity"/"-Infinity" を
/// 文字列として書いた場合、float 要素への供給は DR-050 §4 の既存経路で自動的に成立する」の
/// 実装証跡): config_file 由来の値が float 要素へ渡り、結果が DR-092 §2 の canonical serialize
/// (`"Infinity"`) で戻ることを end-to-end で固定する。fixtures/value-sources/config/value-typing.json
/// と同型の config value source 表記 (`type: "config_file"` + `config_key`) に DR-092 の inf
/// sentinel を組み合わせるだけ — DR-050 §4 が「string element の型変換パイプラインは source を
/// 問わず同一」と規定する通り、config 値源専用の特別処理は一切追加しない (本 DR §5 の「確認的明記」
/// を裏づける)。
test "DR-092 §5 end-to-end: config-origin \"Infinity\" reaches a float element and serializes canonically" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "config", "type": "config_file", "long": true, "default": "/app.toml"},
    #|      {"name": "t", "type": "float", "long": true, "config_key": ["t"]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "config-inf-string-to-float-element",
    #|      "args": [],
    #|      "config": {"t": "Infinity"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {"t": "Infinity"},
    #|        "sources": {"t": "config"}
    #|      }
    #|    },
    #|    {
    #|      "id": "config-neg-inf-string-to-float-element",
    #|      "args": [],
    #|      "config": {"t": "-Infinity"},
    #|      "expect": {
    #|        "outcome": "success",
    #|        "effects": [],
    #|        "result": {"t": "-Infinity"},
    #|        "sources": {"t": "config"}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

// ── DR-094 §9 案A: kuu_ prefix factory 名のリネーム ──────────────────────────

///|
/// 保証 (DR-094 §3/§9 案A): `definitions.types` の factory 名は `int_parser` (builtin ns の bare
/// 糖衣) / `builtin/int_parser` (ns 明示) の 2 表記形が同一 TypeShadow 実体に解決される。2 つの
/// shadow を同じ `int_round: "floor"` config で並べ、同じ fractional 入力 `2.5` を横流しして全て
/// `2` (floor 方向) に解決されることで実体の同一性を固定する — 表記が違うだけで挙動が分岐しないこと
/// の end-to-end 証跡。旧 `kuu_int_parser` prefix の移行期間終了後の拒否確認は別 test を参照。
test "DR-094 §9: int_parser の 2 表記形 (bare / builtin/ ns) が同一 factory に解決される" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {
    #|      "types": {
    #|        "t_bare": {"name": "int_parser", "config": {"int_round": "floor"}},
    #|        "t_ns": {"name": "builtin/int_parser", "config": {"int_round": "floor"}}
    #|      }
    #|    },
    #|    "options": [
    #|      {"name": "bare", "type": "t_bare", "long": true},
    #|      {"name": "ns", "type": "t_ns", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "both-forms-floor-2p5-to-2",
    #|      "args": ["--bare", "2.5", "--ns", "2.5"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "result": {"bare": 2, "ns": 2}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 保証 (DR-094 §3/§9 案A、number_parser 版): `number_parser` / `builtin/number_parser` の 2 表記形
/// が同一 TypeShadow 実体に解決される。`number_allow_base_prefix: true` を共有 config にして `0xff`
/// (hex int opt-in) を横流しし、全て `255` に解決されることを固定する。
test "DR-094 §9: number_parser の 2 表記形 (bare / builtin/ ns) が同一 factory に解決される" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {
    #|      "types": {
    #|        "t_bare": {"name": "number_parser", "config": {"number_allow_base_prefix": true}},
    #|        "t_ns": {"name": "builtin/number_parser", "config": {"number_allow_base_prefix": true}}
    #|      }
    #|    },
    #|    "options": [
    #|      {"name": "bare", "type": "t_bare", "long": true},
    #|      {"name": "ns", "type": "t_ns", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "both-forms-hex-prefix-accepted",
    #|      "args": ["--bare", "0xff", "--ns", "0xff"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "result": {"bare": 255, "ns": 255}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 保証 (DR-094 §9 移行期間終了): 旧 ad-hoc prefix `kuu_int_parser` は fixture pin bump
/// (37aa3b3d、全 fixture が新名へ移行済み) を境に deprecated alias としての受理を終え、他の未知
/// 語彙と同じ unsupported factory DecodeSkip に落ちる。旧名の「受理されないこと」を positive に
/// 固定する — 語彙が spec の閉集合 (DR-094 §2 builtin は closed set) であることの unknown-vocab
/// 側の証跡 (DR-054)。multiple:true 等コンテナ側の他語彙と同じ寛容ハーネスの上で、旧 factory 名
/// だけが特別に生き残らないことを示す。
test "DR-094 §9 移行期間終了: 旧 kuu_int_parser prefix は unsupported factory として拒否される" {
  let int_src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"kuu_int_parser","config":{}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let int_j = @json.parse(int_src)
  let _ = dec_fixture(int_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("unsupported factory"))
      assert_true(r.contains("kuu_int_parser"))
      return
    }
  }
  abort(
    "kuu_int_parser: expected DecodeSkip (legacy alias retired), decode succeeded",
  )
}

///|
/// 保証 (DR-094 §9 移行期間終了、number_parser 版): 旧 ad-hoc prefix `kuu_number_parser` も同様に
/// unsupported factory DecodeSkip に落ちる (int_parser 版と対称)。
test "DR-094 §9 移行期間終了: 旧 kuu_number_parser prefix は unsupported factory として拒否される" {
  let number_src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"kuu_number_parser","config":{}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let number_j = @json.parse(number_src)
  let _ = dec_fixture(number_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("unsupported factory"))
      assert_true(r.contains("kuu_number_parser"))
      return
    }
  }
  abort(
    "kuu_number_parser: expected DecodeSkip (legacy alias retired), decode succeeded",
  )
}

///|
/// 対極確認 ([[self-written-rule-blind-spots]]): リネームで受理形が増えても、未知 factory 名 (typo) の
/// capability gate は不変 — `int_parser` の typo `int_parsr` は unknown-factory DecodeSkip に落ちる。
test "DR-094 §9 対極: factory 名の typo は 3 形式リネーム後も従来通り DecodeSkip される" {
  let typo_src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"int_parsr","config":{}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let typo_j = @json.parse(typo_src)
  let _ = dec_fixture(typo_j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("unsupported factory"))
      assert_true(r.contains("int_parsr"))
      return
    }
  }
  abort("int_parsr: expected DecodeSkip, decode succeeded")
}

// ── issue bool-parser-factory-unimplemented: bool_parser configurable factory ──

///|
/// 保証 (DR-074 §3/§4, DR-094 §3/§9 案A): `definitions.types` の factory 名は `bool_parser`
/// (builtin ns の bare 糖衣) / `builtin/bool_parser` (ns 明示) の 2 表記形が同一 TypeShadow 実体に
/// 解決される (int_parser/number_parser の 2 形テストと対称)。`true_values` に `"yes"` を足した
/// opt-in config を両表記で共有し、canonical-外の `"yes"` が両方とも `true` に解決されることで
/// 実体の同一性と opt-in 語彙追加の両方を同時に固定する。
test "issue bool-parser-factory-unimplemented: bool_parser の 2 表記形 (bare / builtin/ ns) が同一 factory に解決される" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {
    #|      "types": {
    #|        "t_bare": {"name": "bool_parser", "config": {"bool_true_values": ["true", "1", "yes"]}},
    #|        "t_ns": {"name": "builtin/bool_parser", "config": {"bool_true_values": ["true", "1", "yes"]}}
    #|      }
    #|    },
    #|    "options": [
    #|      {"name": "bare", "type": "t_bare", "long": true},
    #|      {"name": "ns", "type": "t_ns", "long": true}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "both-forms-yes-optin-to-true",
    #|      "args": ["--bare", "yes", "--ns", "yes"],
    #|      "expect": {
    #|        "outcome": "success",
    #|        "result": {"bare": true, "ns": true}
    #|      }
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// 対極確認 (DR-074 §3): `bool_parser` の config を全く指定しない (`"config": {}`) と、canonical
/// default (`true_values: ["true","1"]` / `false_values: ["false","0",""]` / `case_insensitive:
/// true`) が適用される — factory 経由でも既存 `parse_bool` ハードコード実装と同じ挙動になることの
/// pin (config データ化が挙動を変えていないことの証跡)。
test "issue bool-parser-factory-unimplemented: bool_parser canonical default (config省略) は既存 parse_bool と同値" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"types": {"t": {"name": "bool_parser", "config": {}}}},
    #|    "options": [{"name": "v", "type": "t", "long": true}]
    #|  },
    #|  "cases": [
    #|    {"id": "true-word", "args": ["--v", "True"], "expect": {"outcome": "success", "result": {"v": true}}},
    #|    {"id": "one", "args": ["--v", "1"], "expect": {"outcome": "success", "result": {"v": true}}},
    #|    {"id": "false-word", "args": ["--v", "FALSE"], "expect": {"outcome": "success", "result": {"v": false}}},
    #|    {"id": "zero", "args": ["--v", "0"], "expect": {"outcome": "success", "result": {"v": false}}},
    #|    {"id": "empty", "args": ["--v", ""], "expect": {"outcome": "success", "result": {"v": false}}},
    #|    {"id": "yes-still-rejected", "args": ["--v", "yes"], "expect": {"outcome": "failure", "errors": [{"element": "v", "args_pos": 1, "kind": "parse", "reason": "not_a_bool"}]}}
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 6)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

///|
/// 保証 (DR-074 §4 `case_insensitive` config キー): `case_insensitive: false` の opt-in 方言
/// (JSON/TOML 準拠) では canonical で通っていた大小混在の綴り (`"TRUE"` 等、`true_values` の
/// 完全一致文字列以外) が `not_a_bool` に落ちる — case_insensitive の既定 `true` から明示的に
/// 外れたときだけ厳密照合になることの pin。
test "issue bool-parser-factory-unimplemented: case_insensitive:false で大小厳密照合になる" {
  let src =
    #|{
    #|  "query": "parse",
    #|  "definition": {
    #|    "definitions": {"types": {"t": {"name": "bool_parser", "config": {"bool_case_insensitive": false}}}},
    #|    "options": [{"name": "v", "type": "t", "long": true}]
    #|  },
    #|  "cases": [
    #|    {"id": "exact-true-still-ok", "args": ["--v", "true"], "expect": {"outcome": "success", "result": {"v": true}}},
    #|    {"id": "mixed-case-rejected", "args": ["--v", "TRUE"], "expect": {"outcome": "failure", "errors": [{"element": "v", "args_pos": 1, "kind": "parse", "reason": "not_a_bool"}]}}
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 2)
  for c in df.cases {
    let verdict = run_case(df, c)
    if verdict != "PASS" {
      abort("expected PASS for case '" + c.id + "', got: " + verdict)
    }
  }
}

///|
/// 対極確認 ([[self-written-rule-blind-spots]] / int_parser の未知キー扱いが手本): `bool_parser`
/// の config に宣言されていないキーを渡すと、他の configurable factory (int_parser/number_parser)
/// と同じ unknown-key decode reject に落ちる — bool_parser だけ特別に寛容になっていないことの pin。
test "issue bool-parser-factory-unimplemented: bool_parser config の未知キーは decode-time reject (int_parser/number_parser と同型)" {
  let src =
    #|{"query":"parse","definition":{"definitions":{"types":{"t":{"name":"bool_parser","config":{"typo_key":true}}}},"options":[{"name":"v","type":"t","long":true}]},"cases":[]}
  let j = @json.parse(src)
  let _ = dec_fixture(j) catch {
    DecodeSkip(r) => {
      assert_true(r.contains("bool_parser config"))
      assert_true(r.contains("typo_key"))
      return
    }
  }
  abort(
    "bool_parser config with unknown key: expected DecodeSkip, decode succeeded",
  )
}

///|
/// codex レビュー指摘 (2026-07-12) の回帰 pin: 異名の dd/none 要素の committed placeholder
/// binding は完全経路の dedup に混入しない (DESIGN §15.1「経路の同一性は実体への観測可能な
/// 効果列で判定する」/ DR-030「実体 = 値セル」/ DR-093 §6「none の発火事実は ParserContext 層」)。
/// 同一 pattern の 2 つの dd 要素 (trig_a / trig_b) が同じトークンに発火しうる 2 枝は、
/// observable な result/effects が同一 ({rest: ["x"]}) なので 1 経路に dedup され @engine.Success になる。
/// 修正前は placeholder の key 差 (trig_a vs trig_b) が strip_link 後の binding 配列比較に
/// 混入して偽 @engine.Ambiguous になっていた (eval.mbt の dedup キー側だけ strip_none_placeholders を
/// 通す修正で解消 — `eff` 本体は保持するので build_result / ParserContext 側は不変)。
/// 標準 comparator (run_case) を通すことで「result に dd 名が漏れない」も同時に固定する。
test "codex-20260712: differing dd placeholder keys do not split path dedup (DESIGN §15.1)" {
  let src =
    #|{
    #|  "why": "dedup regression pin (inline)",
    #|  "query": "parse",
    #|  "definition": {
    #|    "options": [
    #|      {"name": "trig_a", "type": "dd", "match": "^x$", "self": "keep"},
    #|      {"name": "trig_b", "type": "dd", "match": "^x$", "self": "keep"}
    #|    ],
    #|    "positionals": [
    #|      {"name": "rest", "type": "string", "repeat": {"min": 0}}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "same-observable-converges-to-success",
    #|      "why": "両 dd が同一トークン x に発火しうるが観測可能効果列は同一 → 1 経路 (@engine.Success)、rest に x (self: keep)",
    #|      "args": ["x"],
    #|      "expect": {"outcome": "success", "result": {"rest": ["x"]}}
    #|    }
    #|  ]
    #|}
  let df = dec_fixture(@json.parse(src))
  assert_eq(df.cases.length(), 1)
  let verdict = run_case(df, df.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

// ── DR-060 §4 / DR-104 §2(d): completer 配線 (issue 2026-07-14-cand-completer-followup) ──────

///|
/// 配線の基本 + opt-in 比較 (CONFORMANCE §3 COMP-Q3): option の値位置候補に `completer:
/// "<名前>"` (wire) → `@engine.Entity.completer` → `@engine.Cand.completer` の carry が通ることを、同一
/// definition・同一 args_before に対して (a) completer を明記した case (opt-in 発火、値が
/// 一致することを要求) と (b) completer を書かない case (opt-in 不発火、実装が completer を
/// 持っていても比較対象外になり PASS する) の両方で pin する。
test "DR-060 §4 / DR-104 §2(d): option の値位置候補に completer が配線される (opt-in 比較の両面)" {
  let src =
    #|{
    #|  "why": "completer wiring pin (inline)",
    #|  "query": "complete",
    #|  "definition": {
    #|    "options": [{"name": "port", "type": "number", "long": true, "completer": "files"}]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "completer-opt-in-checked",
    #|      "why": "--port のトリガ消費後、値スロット候補 (number, origin=port) に completer=files が乗る (opt-in 発火、値まで比較)",
    #|      "args_before": ["--port"],
    #|      "expect": {"outcome": "complete", "candidates": [
    #|        {"is_value": true, "type": "number", "origin": "port", "term": "word_end", "meta": {"is_alias": false, "hidden": false, "deprecated": false}, "completer": "files"}
    #|      ]}
    #|    },
    #|    {
    #|      "id": "completer-opt-out-not-checked",
    #|      "why": "同じ定義・同じ入力で completer キーを書かない case — 実装が completer=files を返しても opt-in 不発火のため比較対象外、PASS する (COMP-Q3)",
    #|      "args_before": ["--port"],
    #|      "expect": {"outcome": "complete", "candidates": [
    #|        {"is_value": true, "type": "number", "origin": "port", "term": "word_end", "meta": {"is_alias": false, "hidden": false, "deprecated": false}}
    #|      ]}
    #|    }
    #|  ]
    #|}
  let fx = dec_complete_fixture(@json.parse(src))
  assert_eq(fx.cases.length(), 2)
  for c in fx.cases {
    let verdict = run_complete(fx, c)
    if verdict != "PASS" {
      abort("case " + c.id + ": expected PASS, got: " + verdict)
    }
  }
}

///|
/// positional の値スロットにも completer が配線されることの pin — DR-060 §4 は「アプリ固有の
/// 動的候補」を option 限定と規定していない (option 専用の `hidden` とは対照的、CandMeta.hidden
/// の doc comment 参照)。
test "DR-060 §4: positional の値位置候補にも completer が配線される" {
  let src =
    #|{
    #|  "why": "positional completer wiring pin (inline)",
    #|  "query": "complete",
    #|  "definition": {
    #|    "positionals": [{"name": "target", "type": "string", "completer": "hosts"}]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "positional-value-slot-gets-completer",
    #|      "why": "args_before 空: positional target がまだ何も消費していない先頭値スロット、completer=hosts が乗る",
    #|      "args_before": [],
    #|      "expect": {"outcome": "complete", "candidates": [
    #|        {"is_value": true, "type": "string", "origin": "target", "term": "word_end", "meta": {"is_alias": false, "hidden": false, "deprecated": false}, "completer": "hosts"}
    #|      ]}
    #|    }
    #|  ]
    #|}
  let fx = dec_complete_fixture(@json.parse(src))
  let verdict = run_complete(fx, fx.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// merge 規則: 6 フィールド一致・completer 一致 (2 つの独立 command 定義が同名 positional
/// `target` を持ち、両方とも同じ completer を宣言する) — dedup 後も completer=files が
/// 保持されることの pin (positive case)。
test "DR-104 §3 明確化: 6 フィールド一致 dedup で completer が一致する場合は保持される" {
  let src =
    #|{
    #|  "why": "merge rule positive pin (inline)",
    #|  "query": "complete",
    #|  "definition": {
    #|    "commands": [
    #|      {"type": "command", "name": "build", "positionals": [{"name": "target", "type": "string", "completer": "files"}]},
    #|      {"type": "command", "name": "build", "positionals": [{"name": "target", "type": "string", "completer": "files"}]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "matching-completer-across-sibling-command-defs-is-preserved",
    #|      "why": "\"build\" 消費後、両 command 定義の子 scope それぞれから origin=target の値スロット候補が生成される (DR-067 §1 の重複トリガ経路と同型、dedup.json の command-scope 版)。6 フィールド一致 + completer 一致 (files=files) → 1 件に畳まれ completer=files を保持する",
    #|      "args_before": ["build"],
    #|      "expect": {"outcome": "complete", "candidates": [
    #|        {"is_value": true, "type": "string", "origin": "target", "term": "word_end", "meta": {"is_alias": false, "hidden": false, "deprecated": false}, "completer": "files"}
    #|      ]}
    #|    }
    #|  ]
    #|}
  let fx = dec_complete_fixture(@json.parse(src))
  let verdict = run_complete(fx, fx.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// @engine.Rooted-escape (global option) の completer 解決 pin: global option の値スロットは
/// command 子 scope 内で消費されるが、その @engine.Entity は宣言元 (root) scope にしか存在しない
/// (issue 2026-07-14-cand-completer-followup、実装過程で発見した @engine.Cand.link 機構 — `@engine.Binding.link`
/// と同じ @engine.Rooted-escape カウンタが @engine.Cand にも必要だった)。子 scope 内の値スロット候補が正しく
/// root 側の completer を引けることを固定する。
test "DR-060 §4: global option の値スロット candidate は @engine.Rooted escape を跨いでも正しい completer を引く" {
  let src =
    #|{
    #|  "why": "global-option completer lookup across @engine.Rooted escape (inline)",
    #|  "query": "complete",
    #|  "definition": {
    #|    "options": [{"name": "verbose", "type": "number", "long": true, "completer": "levels", "global": true}],
    #|    "commands": [
    #|      {"type": "command", "name": "build", "options": []}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "global-value-slot-completer-survives-command-scope-copy",
    #|      "why": "\"build\" で子 scope に入り、global コピーされた --verbose のトリガを消費、値スロット (number, origin=verbose) の completer は宣言元 root の completer=levels を指す — 子 scope 側には --verbose の @engine.Entity 自体が存在しない (link 衛星、実体は root のまま)",
    #|      "args_before": ["build", "--verbose"],
    #|      "expect": {"outcome": "complete", "candidates": [
    #|        {"is_value": true, "type": "number", "origin": "verbose", "term": "word_end", "meta": {"is_alias": false, "hidden": false, "deprecated": false}, "completer": "levels"}
    #|      ]}
    #|    }
    #|  ]
    #|}
  let fx = dec_complete_fixture(@json.parse(src))
  let verdict = run_complete(fx, fx.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}

///|
/// merge 規則: 6 フィールド一致・completer 不一致 (2 つの独立 command 定義が同名 `target`
/// positional を持ち、異なる completer (files/urls) を宣言する) — DR-104 §3 明確化 note により
/// dedup 後の候補は completer なし (None) へ畳まれることの pin (negative case)。`build`/`build`
/// という同名の兄弟 command は path 表現 (scope 名の列) では区別できない (DR-067 §1 が合法化する
/// 同名重複の兄弟版) ため、`collect_all_entities` の収集時点で衝突検出する実装になっている
/// (positive case の一致 pin と対照させる)。opt-in は `target` 候補自身に `"completer": ""`
/// (省略と同値、CONFORMANCE §3) を明示することで発火させる — before=["build"] の時点では
/// `--verbose` 自体のトリガはまだ消費されておらず (exact 候補、completer は元々常に無意味) その
/// 値スロットは同居しないため、他の候補と同居させる正の一致確認は別 test (positive case) の役目。
test "DR-104 §3 明確化: 6 フィールド一致 dedup で completer が食い違う場合は completer なしへ畳まれる" {
  let src =
    #|{
    #|  "why": "merge rule negative pin (inline)",
    #|  "query": "complete",
    #|  "definition": {
    #|    "commands": [
    #|      {"type": "command", "name": "build", "positionals": [{"name": "target", "type": "string", "completer": "files"}]},
    #|      {"type": "command", "name": "build", "positionals": [{"name": "target", "type": "string", "completer": "urls"}]}
    #|    ]
    #|  },
    #|  "cases": [
    #|    {
    #|      "id": "conflicting-completer-across-sibling-command-defs-merges-to-none",
    #|      "why": "\"build\" 消費後、両 command 定義の子 scope それぞれから origin=target の値スロット候補 (completer=files / completer=urls) が生成される。6 フィールドは一致するが completer が食い違うため、DR-104 §3 明確化 note によりこの候補は completer なしへ畳まれる (completer:\"\" で opt-in を発火させつつ、実際の値が空であることを assert する)",
    #|      "args_before": ["build"],
    #|      "expect": {"outcome": "complete", "candidates": [
    #|        {"is_value": true, "type": "string", "origin": "target", "term": "word_end", "meta": {"is_alias": false, "hidden": false, "deprecated": false}, "completer": ""}
    #|      ]}
    #|    }
    #|  ]
    #|}
  let fx = dec_complete_fixture(@json.parse(src))
  let verdict = run_complete(fx, fx.cases[0])
  if verdict != "PASS" {
    abort("expected PASS, got: " + verdict)
  }
}
