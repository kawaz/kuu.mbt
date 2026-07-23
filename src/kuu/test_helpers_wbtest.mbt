// test_helpers_wbtest.mbt — assembly whitebox helpers shared across test files.

///|
/// Test-only node resident that captures a matcher's raw branch stream while `parse_tree`
/// supplies the private engine context.
priv struct TestMatcherProbeExt {
  matcher : &@extension.MatcherExt
  captured : Array[Array[@abi.Branch]]
}

///|
impl @extension.NodeExt for TestMatcherProbeExt with fn kind(_self) {
  "test/matcher-probe"
}

///|
impl @extension.NodeExt for TestMatcherProbeExt with fn encode(_self) {
  ().to_json()
}

///|
impl @extension.NodeExt for TestMatcherProbeExt with fn consumes_zero_tokens(
  _self,
) {
  false
}

///|
impl @extension.NodeExt for TestMatcherProbeExt with fn eval(
  self,
  ctx,
  pos,
  acc,
  _next,
) {
  self.captured.push(
    self.matcher.interpret(ctx, pos, acc, (_ctx, next_pos, next_acc) => {
      [@abi.Accept(next_pos, next_acc)]
    }),
  )
  []
}

///|
fn test_resolve(
  ast : AtomicAST,
  args : Array[String],
  sources? : ValueSources = value_sources(),
) -> ResolvedOutcome {
  match parse(ast, args, sources~) {
    Success(bindings) => resolve(ast, bindings, args, sources~)
    Failure(failure) => Failure(failure)
    Ambiguous(_) => abort("test expected one complete parse path")
  }
}

///|
fn test_run_matcher(
  matcher : &@extension.MatcherExt,
  toks : Array[String],
) -> Array[@abi.Branch] {
  let captured : Array[Array[@abi.Branch]] = []
  let probe = @engine.Ext(
    TestMatcherProbeExt::{ matcher, captured } as &@extension.NodeExt,
  )
  ignore(@engine.parse_tree(probe, toks))
  guard captured.length() == 1 else { return [] }
  captured[0]
}

///|
fn chain(spellings : Array[String]) -> Array[@abi.FnInvocation] {
  let out : Array[@abi.FnInvocation] = []
  for spelling in spellings {
    out.push(@extension.parse_filter_shorthand(spelling))
  }
  out
}

///|
/// Test assembly convenience: every lowering test uses kuu's canonical resident set unless it
/// explicitly supplies a custom registry. The production builtins API itself has no implicit set.
fn test_lower_definition(
  definition : @engine.Definition,
  installers : Array[&@node.InstallerExt],
  registry? : Map[String, @engine.Node] = Map([], capacity=0),
  extensions? : @node.Registry = canonical_registry(),
) -> Result[@engine.Scope, Array[@abi.DefError]] {
  @node.lower_definition(
    definition,
    installers,
    extensions.extensions(),
    registry~,
  )
}

///|
fn node_is_deprecation_mark(node : @engine.Node) -> Bool {
  node is @engine.Ext(extension) && extension.kind() == "builtin/deprecation"
}

///|
/// Deterministic codepoint ordering for whitebox diagnostic renderers.
fn test_str_less(a : String, b : String) -> Bool {
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
fn test_sort_items(arr : Array[String]) -> Unit {
  let mut i = 1
  while i < arr.length() {
    let key = arr[i]
    let mut j = i - 1
    while j >= 0 && test_str_less(key, arr[j]) {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
    i = i + 1
  }
}

///|
fn test_join_comma(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for item in items {
    if !first {
      buf.write_string(",")
    }
    buf.write_string(item)
    first = false
  }
  buf.to_string()
}

///|
fn test_render_val(value : @abi.Value) -> String {
  match value {
    @abi.String(s) => s
    @abi.Bool(b) => if b { "true" } else { "false" }
    @abi.Number(d) => {
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
fn render_kind(kind : @abi.ErrorKind) -> String {
  match kind {
    @abi.Parse => "parse"
    @abi.Filter => "filter"
    @abi.Constraint => "constraint"
  }
}

///|
fn test_render_def_kind(kind : @abi.DefErrorKind) -> String {
  match kind {
    @abi.VocabIntersection => "vocab-intersection"
    @abi.UnknownVocab => "unknown-vocab"
    @abi.InvalidRange => "invalid-range"
    @abi.AbsentRef => "absent-ref"
    @abi.CircularRef => "circular-ref"
    @abi.ZeroProgress => "zero-progress"
    @abi.ConfigCycle => "config-cycle"
    @abi.InvalidArgument => "invalid-argument"
  }
}

///|
fn deferrs_str(errors : Array[@abi.DefError]) -> String {
  let items : Array[String] = []
  for error in errors {
    items.push("\{error.element}/\{test_render_def_kind(error.kind)}")
  }
  test_sort_items(items)
  test_join_comma(items)
}

///|
fn test_primary_message(errors : Array[@abi.ParseError]) -> String {
  let mut best = errors[0]
  for error in errors {
    if error.args_pos > best.args_pos {
      best = error
    }
  }
  best.message
}

///|
fn test_render_binds_result(binds : Array[@abi.Binding]) -> String {
  let items : Array[String] = []
  for binding in binds {
    if !is_sentinel(binding.key) {
      items.push("\{binding.key}=\{test_render_val(binding.value)}")
    }
  }
  test_sort_items(items)
  test_join_comma(items)
}

///|
fn render_outcome(outcome : @engine.Outcome) -> String {
  match outcome {
    @engine.Success(binds) => "ok{" + test_render_binds_result(binds) + "}"
    @engine.Failure(data) =>
      match data.fired_action {
        Some(name) => "action:" + name
        None =>
          if data.errors.length() > 0 {
            "fail:" + test_primary_message(data.errors)
          } else {
            "fail:no complete parse"
          }
      }
    @engine.Ambiguous(data) =>
      "ambiguous:" + data.interpretations.length().to_string()
  }
}

///|
fn render_rval_sorted(value : @abi.ResultValue) -> String {
  match value {
    @abi.Scalar(scalar) => test_render_val(scalar)
    @abi.Array(values) => {
      let items : Array[String] = []
      for item in values {
        items.push(render_rval_sorted(item))
      }
      "[" + test_join_comma(items) + "]"
    }
    @abi.Object(fields) => {
      let items : Array[String] = []
      for field in fields {
        items.push(field.0 + "=" + render_rval_sorted(field.1))
      }
      test_sort_items(items)
      "{" + test_join_comma(items) + "}"
    }
  }
}

// ── whitebox-only wrappers removed from the production interface ──────────

///|
/// One built interpretation for whitebox collision projection checks.
struct TestInterpretation {
  result : @abi.ResultValue
  claimants : Array[(String, String)]
} derive(Eq, Debug)

///|
/// Build every DR-073 interpretation of `binds`. With no collision this is a single interpretation
/// (empty claimants) — the ordinary export_result rendering. With N simultaneous collision groups,
/// every combination of "which claimant occupies which key" (cross product across groups) is a
/// distinct interpretation: each keeps only its chosen claimant's bindings for that (path, key)
/// group (the other claimants' bindings at that group are dropped from THIS view — DR-073 §2, the
/// entity name is the only cross-view-stable identifier since value/source can coincide) before
/// applying export keys and building the result. `cells`/`defaults` are passed through to
/// `build_result` unchanged (accum cells and defaults are keyed by raw entity name, matching the
/// caller's `accum_cells(sc)` / `apply_export_to_defaults(default_cells(sc), ek)` convention — see
/// slice `poc/helpers_wbtest.mbt`).
fn build_interpretations(
  binds : Array[@abi.Binding],
  ek : Map[String, @engine.ExportKey],
  cells : Array[AccumCell],
  defaults : Array[DefaultCell],
  nones? : Array[@engine.NoneCell] = [],
) -> Array[TestInterpretation] {
  let collisions = find_export_collisions(binds, ek)
  if collisions.length() == 0 {
    let mapped = apply_export_keys(binds, ek)
    return [
      {
        result: build_result(mapped, cells, defaults, [], nones~),
        claimants: [],
      },
    ]
  }
  let out : Array[TestInterpretation] = []
  for combo in claimant_combinations(collisions) {
    let filtered : Array[@abi.Binding] = []
    for b in binds {
      let mut drop = false
      let mut gi = 0
      while gi < collisions.length() {
        let c = collisions[gi]
        if path_eq(c.path, b.scope) &&
          exposed_key_of(b.key, ek) == Some(c.key) &&
          b.key != combo[gi] {
          drop = true
        }
        gi = gi + 1
      }
      if !drop {
        filtered.push(b)
      }
    }
    let mapped = apply_export_keys(filtered, ek)
    let claimants : Array[(String, String)] = []
    let mut gi = 0
    while gi < collisions.length() {
      claimants.push((collisions[gi].key, combo[gi]))
      gi = gi + 1
    }
    out.push({
      result: build_result(mapped, cells, defaults, [], nones~),
      claimants,
    })
  }
  out
}

///|
/// Apply requires with identity result keys. Front-door parsing uses the export-aware internal
/// variant so default filling and requires observe the same result-cell partition.
fn apply_requires_filter(
  o : @engine.Outcome,
  root : @engine.Node,
  defs : Map[String, @engine.Node],
  env : Map[String, String],
  toks_len : Int,
  provider? : (String) -> @abi.ConfigVal? = fn(_) { None },
  tty? : Map[String, TtyObs] = Map([]),
) -> @engine.Outcome {
  apply_requires_filter_with_export(
    o,
    root,
    defs,
    fn(key) { env.get(key) },
    toks_len,
    provider,
    fn(key) { tty.get(key) },
    Map([]),
    canonical_registry(),
  )
}

///|
/// Resolve every entity in a built scope against CLI bindings + an env map (no config seat). For
/// the env / inherit ladder path. Unlike slice (whose config-less path "never errors"), a
/// badly-typed env value now surfaces as an Err (DR-074/075 update above).
/// `path` is this scope's DR-066 §4 result-nesting path (root-first, [] = root 直下), threaded into
/// any ladder-fill Error the same way `resolve_scope_config`'s `path` is.
///
/// A scope MAY still declare a `config_file` element even on this no-config-object call path (a
/// caller can choose not to supply config data for a particular case/run — issue
/// bool-requires-config-inherit-gap の diverge 調査で顕在化: 元のドキュメント想定「no config_file
/// element in scope」は呼び出し元の都合を entity 宣言の事実と混同していた)。`resolve_scope_config`
/// の Phase 3 (`if !e.is_config_file`) と同じ規則 — config_file 要素は配線宣言であって結果 entity
/// ではない — をここでも守る。守らないと、config データを供給しない呼び出しのときだけ config_file
/// 要素の宣言 default が漏れて result に出現する非対称が起きる (config_seat を持つ通常 entity は
/// config_obj=None のときの通常 default フォールスルーで正しく処理されるので対象外、config_file
/// 自身だけがこの skip を必要とする)。
fn resolve_scope(
  sc : @engine.Scope,
  cli : Array[@abi.Binding],
  env_map : Map[String, String],
  inherited? : Map[String, @abi.Value] = Map([]),
  at_pos? : Int = -1,
  path? : Array[String] = [],
  tty? : Map[String, TtyObs] = Map([]),
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  let out : Array[@abi.Binding] = []
  for e in sc.entities {
    if !e.is_config_file {
      match
        resolve_entity(
          e,
          cli,
          fn(key) { env_map.get(key) },
          None,
          [],
          inherited,
          at_pos,
          path,
          fn(key) { tty.get(key) },
          canonical_registry(),
          true,
        ) {
        Ok(bs) =>
          for b in bs {
            out.push(b)
          }
        Err(pe) => return Err(pe)
      }
    }
  }
  Ok(out)
}

///|
/// Resolve one scope with identity result keys. Front-door callers use the export-aware tree helper;
/// this public low-level API keeps its existing signature for callers that only have a @engine.Scope.
fn resolve_scope_config(
  sc : @engine.Scope,
  cli : Array[@abi.Binding],
  env_map : Map[String, String],
  provider : (String) -> @abi.ConfigVal?,
  path? : Array[String] = [],
  inherited? : Map[String, @abi.Value] = Map([]),
  at_pos? : Int = -1,
  tty? : Map[String, TtyObs] = Map([]),
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  resolve_scope_config_with_export(
    sc,
    cli,
    fn(key) { env_map.get(key) },
    provider,
    path,
    inherited,
    at_pos,
    fn(key) { tty.get(key) },
    Map([]),
    canonical_registry(),
    true,
  )
}

///|
/// Fetch a subcommand's built @engine.Scope from a parent @engine.Scope by name. Subcommands are
/// materialized as greedy `@engine.CommandSatisfied(name, child)` entries.
fn command_child(sc : @engine.Scope, name : String) -> @engine.Scope? {
  for g in sc.greedy {
    match g {
      @engine.CommandSatisfied(n, child) => if n == name { return Some(child) }
      _ => ()
    }
  }
  None
}

///|
/// Build an inherited-context map from a parent scope's resolved bindings.
fn inherited_of(binds : Array[@abi.Binding]) -> Map[String, @abi.Value] {
  let m : Map[String, @abi.Value] = Map([])
  for b in binds {
    m.set(b.key, b.value)
  }
  m
}
