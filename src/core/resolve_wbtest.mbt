// resolve_wbtest.mbt — executable spec for the value-resolution layer (MDR-002 §3): the result
// builder (DR-016/025/043/044), export-key application + collision (DR-052/073), and the
// value-source ladder (DR-031/049/050, with the DR-074/075 env-lexer update over the slice).

///|
/// A scalar cli/env/config/… `Set` binding at the root scope (the common case in these tests;
/// nested-scope cases build the `Binding` literal directly to show the scope path explicitly).
fn cb(key : String, value : Value, source : Source) -> Binding {
  { key, op: Set, value, source, scope: [], link: 0 }
}

///|
/// An Entity builder with every ladder seat off by default (labeled optional args mirror slice
/// `poc/helpers_wbtest.mbt`'s `opt()` — only the ladder seats a test actually exercises are named).
fn ent(
  name : String,
  ty : Ty,
  env_key? : String? = None,
  config_seat? : Bool = false,
  config_key? : Array[String]? = None,
  is_config_file? : Bool = false,
  inherit_? : Bool = false,
  accum? : String? = None,
  collector? : String? = None,
  default_value? : Value? = None,
  pre_filters? : Array[String] = [],
  filters? : Array[String] = [],
  post_filters? : Array[String] = [],
) -> Entity {
  {
    name,
    ty,
    env_key,
    config_seat,
    config_key,
    is_config_file,
    inherit_,
    accum,
    collector,
    default_value,
    pre_filters,
    filters,
    post_filters,
  }
}

// ── build_result (DR-016/025/043/044) ─────────────────────────────────────────

///|
/// Guarantees: a plain scalar cell renders last-wins (DR-015), an accumulate cell folds same-key
/// effects into an array (DR-043/034/036, `empty` clears prior items), and a scalar cell's preset
/// default seats when the cell has no winning binding at all (DR-031 default seat / DR-051 §2 flag
/// は absent にならない) — three of the builder's structural cases in one pass over a flat scope.
test "build_result folds scalar last-wins, accumulate array, and default seat" {
  let binds : Array[Binding] = [
    cb("port", VNum(8080.0), Cli),
    cb("port", VNum(9090.0), Cli), // last-wins: 9090 should win over 8080
    cb("tags", VStr("a"), Cli),
    cb("tags", VStr("b"), Cli),
  ]
  let cells : Array[AccumCell] = [{ path: [], name: "tags", collector: None }]
  let defaults : Array[DefaultCell] = [
    { path: [], name: "verbose", value: VBool(false) },
  ]
  let r = build_result(binds, cells, defaults, [])
  assert_eq(
    r,
    RObj([
      ("port", RScalar(VNum(9090.0))),
      ("tags", RArr([RScalar(VStr("a")), RScalar(VStr("b"))])),
      ("verbose", RScalar(VBool(false))),
    ]),
  )
}

///|
/// Guarantees: an `empty` effect on an accumulate cell CLEARS everything accumulated before it
/// (DR-045 empty op) — re-accumulation after `empty` starts fresh, not appended to the discard.
test "build_result: an empty op on an accumulate cell clears prior items" {
  let binds : Array[Binding] = [
    { key: "tags", op: Set, value: VStr("a"), source: Cli, scope: [], link: 0 },
    {
      key: "tags",
      op: Empty,
      value: VBool(false), // placeholder — empty carries no operand
      source: Cli,
      scope: [],
      link: 0,
    },
    { key: "tags", op: Set, value: VStr("c"), source: Cli, scope: [], link: 0 },
  ]
  let cells : Array[AccumCell] = [{ path: [], name: "tags", collector: None }]
  let r = build_result(binds, cells, [], [])
  assert_eq(r, RObj([("tags", RArr([RScalar(VStr("c"))]))]))
}

///|
/// Guarantees: an accumulate cell that fired ZERO times still renders `[]` (DR-044 §1 uniform
/// array) instead of being absent from the result object.
test "build_result: an unfired accumulate cell renders [] (DR-044 uniform array)" {
  let cells : Array[AccumCell] = [{ path: [], name: "tags", collector: None }]
  assert_eq(build_result([], cells, [], []), RObj([("tags", RArr([]))]))
}

///|
/// 保証 (DR-036, issue 2026-07-09-dec-multiple-collector-decode): an accum cell whose AccumCell
/// carries `collector: Some("unwrap_single")` has the collector applied to the FINAL accumulated
/// array (after fold, same spot `apply_collector`/`unwrap_single`, resolve.mbt, sits) — a
/// length-1 accumulation collapses to a bare scalar (DR-034 縮退ケース: an app wants a SCALAR from
/// a multiple/repeat cell without the uniform-array default folding it). Paired with the next case
/// (2+ elements) to fix unwrap_single's actual boundary, not just "it does something".
test "build_result: a collector (unwrap_single) collapses a length-1 accumulation to a scalar" {
  let binds : Array[Binding] = [cb("tag", VStr("solo"), Cli)]
  let cells : Array[AccumCell] = [
    { path: [], name: "tag", collector: Some("unwrap_single") },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([("tag", RScalar(VStr("solo")))]),
  )
}

///|
/// 保証: unwrap_single は「唯一無二の縮退」だけを畳む — 2 要素以上の accumulation は集約結果の
/// ARRAY のまま残る (resolve.mbt `unwrap_single`'s doc comment: "Length 0 or >= 2 arrays are left
/// unchanged")。前ケース (length-1 → scalar) と対で unwrap_single の輪郭を固定する。
test "build_result: a collector (unwrap_single) leaves a 2+ element accumulation as an array" {
  let binds : Array[Binding] = [
    cb("tag", VStr("a"), Cli),
    cb("tag", VStr("b"), Cli),
  ]
  let cells : Array[AccumCell] = [
    { path: [], name: "tag", collector: Some("unwrap_single") },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([("tag", RArr([RScalar(VStr("a")), RScalar(VStr("b"))]))]),
  )
}

///|
/// 保証: 0 回発火の accum cell に collector が付いていても、DR-044 §1 の uniform array 契約 (未発火
/// でも `[]` を描画、absent にしない) は崩れない — unwrap_single([]) は空配列のまま (unchanged)
/// なので、collector 適用後も `[]` のまま描画される。uniform-array 注入経路 (build_result の
/// `UNIFORM ARRAY` 分岐) にも collector 適用を配線したことを固定する (ACCUMULATE 分岐だけでなく)。
test "build_result: a collector on an unfired accum cell still renders [] (DR-044 uniform array)" {
  let cells : Array[AccumCell] = [
    { path: [], name: "tag", collector: Some("unwrap_single") },
  ]
  assert_eq(build_result([], cells, [], []), RObj([("tag", RArr([]))]))
}

///|
/// Guarantees: an IdxRepeat's "[]"/"#k" sentinel encoding (DR-043 named indexed repeat) folds into
/// an ARRAY of one element per firing, each element itself built by recursing under its "#k" — the
/// nameless "" leaf at each index is the SCALAR case (a seq/array context nameless value, DR-052
/// §2), not promoted into a kv object.
test "build_result: [] + #k sentinels fold an indexed repeat into an array" {
  let binds : Array[Binding] = [
    {
      key: "[]",
      op: Set,
      value: VBool(true),
      source: Cli,
      scope: ["xs"],
      link: 0,
    },
    {
      key: "",
      op: Set,
      value: VStr("a"),
      source: Cli,
      scope: ["xs", "#0"],
      link: 0,
    },
    {
      key: "",
      op: Set,
      value: VStr("b"),
      source: Cli,
      scope: ["xs", "#1"],
      link: 0,
    },
  ]
  let r = build_result(binds, [], [], [])
  assert_eq(r, RObj([("xs", RArr([RScalar(VStr("a")), RScalar(VStr("b"))]))]))
}

// ── export-key application (DR-052) ───────────────────────────────────────────

///|
/// Guarantees: `apply_export_keys` overrides a value cell's key (EkKey) and drops a scope label
/// entirely (EkNull, DR-052 §2 透過 — children promote to the parent), leaving an unmapped
/// (EkUnset) name unchanged.
test "apply_export_keys renames a leaf key and drops a null-exported scope label" {
  let ek : Map[String, ExportKey] = Map::from_array([
    ("port", EkKey("p")),
    ("wrapper", EkNull),
  ])
  let binds : Array[Binding] = [
    cb("port", VNum(80.0), Cli),
    {
      key: "verbose",
      op: Set,
      value: VBool(true),
      source: Cli,
      scope: ["wrapper"],
      link: 0,
    },
  ]
  let mapped = apply_export_keys(binds, ek)
  assert_eq(mapped[0].key, "p")
  assert_eq(mapped[1].scope, []) // "wrapper" label dropped → child promotes to root
  assert_eq(mapped[1].key, "verbose") // unmapped name unchanged (EkUnset default)
}

// ── export-key collision (DR-073) ─────────────────────────────────────────────
//
// Mirrors spec fixture `fixtures/export-key/collision.json` exactly: two flags `a`/`b` both
// export_key `x`.

///|
fn collision_ek() -> Map[String, ExportKey] {
  Map::from_array([("a", EkKey("x")), ("b", EkKey("x"))])
}

///|
/// co-exposure-collision (`--a --b`): both a and b fire in the SAME parse and both map to `x` —
/// a genuine runtime collision (DESIGN §15.5 / DR-021). `find_export_collisions` reports the
/// group; `build_interpretations` yields 2 interpretations (one claiming `x` per entity), both
/// degenerating to the SAME view `{x:true}` (both flags) — distinguished ONLY by claimants
/// (DR-073 §1/§2), exactly the fixture's expected shape.
test "DR-073 co-exposure-collision: degenerate views distinguished by claimants" {
  let ek = collision_ek()
  let binds : Array[Binding] = [
    cb("a", VBool(true), Cli),
    cb("b", VBool(true), Cli),
  ]
  let collisions = find_export_collisions(binds, ek)
  assert_eq(collisions.length(), 1)
  assert_eq(collisions[0].path, [])
  assert_eq(collisions[0].key, "x")
  assert_eq(collisions[0].claimants, ["a", "b"])
  let interps = build_interpretations(binds, ek, [], [])
  assert_eq(interps.length(), 2)
  assert_eq(interps[0].result, RObj([("x", RScalar(VBool(true)))]))
  assert_eq(interps[0].claimants, [("x", "a")])
  assert_eq(interps[1].result, RObj([("x", RScalar(VBool(true)))]))
  assert_eq(interps[1].claimants, [("x", "b")])
}

///|
/// single-exposure-ok (`--a` only): only `a` actually fires — no collision (the check is on
/// ACTUAL co-exposure, not the static declaration, DR-021 §5 / DESIGN §15.5). `b`'s unfired flag
/// preset (`default: false`) must NOT resurface under the shared exported key `x` (it would wrongly
/// look like a second occupant) — `apply_export_to_defaults` maps it to the same key `x`, but
/// `build_result`'s default-seat injection skips it because `x` is already a bound leaf (from `a`).
test "DR-073 single-exposure-ok: no collision, and the unfired co-exported default does not resurface" {
  let ek = collision_ek()
  let binds : Array[Binding] = [cb("a", VBool(true), Cli)]
  assert_eq(find_export_collisions(binds, ek), [])
  let defaults : Array[DefaultCell] = [
    { path: [], name: "b", value: VBool(false) },
  ]
  let interps = build_interpretations(
    binds,
    ek,
    [],
    apply_export_to_defaults(defaults, ek),
  )
  assert_eq(interps.length(), 1)
  assert_eq(interps[0].claimants, [])
  assert_eq(interps[0].result, RObj([("x", RScalar(VBool(true)))]))
}

// ── value-source ladder (DR-031/049/050) ──────────────────────────────────────

///|
/// Guarantees: the ladder picks cli > env > default in that order when multiple seats could supply
/// the same cell — this is the DR-031 invariant the whole layer exists to realize.
test "resolve_scope: cli wins over env, env wins over default" {
  let port = ent(
    "port",
    TNum,
    env_key=Some("PORT"),
    default_value=Some(VNum(1.0)),
  )
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [port],
    constraints: [],
  }
  // cli present → cli wins regardless of env/default.
  let cli_bound = resolve_scope(
    sc,
    [cb("port", VNum(8080.0), Cli)],
    Map::from_array([("PORT", "9999")]),
  )
  assert_eq(cli_bound, Ok([cb("port", VNum(8080.0), Cli)]))
  // no cli → env wins over default.
  let env_bound = resolve_scope(sc, [], Map::from_array([("PORT", "9999")]))
  assert_eq(env_bound, Ok([mkb_pub("port", VNum(9999.0), Env)]))
  // neither cli nor env → default seats.
  let default_bound = resolve_scope(sc, [], Map([]))
  assert_eq(default_bound, Ok([mkb_pub("port", VNum(1.0), Default)]))
}

///|
/// A `Set` binding builder exposed for assertions (mirrors `mkb`'s shape without re-exporting it).
fn mkb_pub(key : String, value : Value, source : Source) -> Binding {
  { key, op: Set, value, source, scope: [], link: 0 }
}

///|
/// Guarantees: the inherit seat (DR-031 #4 / DR-013) supplies the nearest ancestor scope's
/// same-named value when no cli/env/config seat wins, and is itself out-ranked by a default seat
/// that would only apply when inherit has nothing (both absent here → default).
test "resolve_scope: inherit seat fills from the parent context map" {
  let ttl = ent("ttl", TNum, inherit_=true, default_value=Some(VNum(30.0)))
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [ttl],
    constraints: [],
  }
  let inherited = Map::from_array([("ttl", VNum(60.0))])
  let bound = resolve_scope(sc, [], Map([]), inherited~)
  assert_eq(bound, Ok([mkb_pub("ttl", VNum(60.0), Inherit)]))
  // no inherited value present → falls through to default.
  let bound_no_parent = resolve_scope(sc, [], Map([]))
  assert_eq(bound_no_parent, Ok([mkb_pub("ttl", VNum(30.0), Default)]))
}

///|
/// Guarantees (DR-074/075 update over slice `env_value`): a badly-typed env string is a DR-066
/// Error with the canonical reason (`not_a_number` / `not_an_integer` / `not_a_bool`) — NOT a
/// silent `VStr` fallback into a wrong-typed cell (the slice's behaviour this port fixes).
test "resolve_scope: a badly-typed env value is a DR-066 Error, not a silent VStr fallback" {
  let num = ent("n", TNum, env_key=Some("N"))
  let sc_num : Scope = {
    greedy: [],
    positional: [],
    entities: [num],
    constraints: [],
  }
  match resolve_scope(sc_num, [], Map::from_array([("N", "abc")])) {
    Err(pe) => {
      assert_eq(pe.element, "n")
      assert_eq(pe.kind, KParse)
      assert_eq(pe.reason, "not_a_number")
    }
    Ok(_) => fail("expected an Err, env value \"abc\" is not a number")
  }
  let int_ = ent("i", TInt, env_key=Some("I"))
  let sc_int : Scope = {
    greedy: [],
    positional: [],
    entities: [int_],
    constraints: [],
  }
  match resolve_scope(sc_int, [], Map::from_array([("I", "2.5")])) {
    Err(pe) => assert_eq(pe.reason, "not_an_integer") // readable as a number, not integer-valued
    Ok(_) => fail("expected an Err, env value \"2.5\" is not an integer")
  }
  // an integer-VALUED string is accepted under every mode (DR-075 値空間判定), incl. via env.
  let sc_int_ok : Scope = {
    greedy: [],
    positional: [],
    entities: [ent("i", TInt, env_key=Some("I"))],
    constraints: [],
  }
  assert_eq(
    resolve_scope(sc_int_ok, [], Map::from_array([("I", "3.0")])),
    Ok([mkb_pub("i", VNum(3.0), Env)]),
  )
  let flag = ent("f", TFlag, env_key=Some("F"))
  let sc_flag : Scope = {
    greedy: [],
    positional: [],
    entities: [flag],
    constraints: [],
  }
  match resolve_scope(sc_flag, [], Map::from_array([("F", "maybe")])) {
    Err(pe) => assert_eq(pe.reason, "not_a_bool")
    Ok(_) => fail("expected an Err, env value \"maybe\" is not a bool")
  }
}

///|
/// Guarantees (DR-050 §5 dependency order): the config_file element's OWN path resolves cli >
/// env > default first (no config seat, 循環禁止); the provider is then read with that path, and
/// every other entity resolves down cli > env > config > inherit > default using it.
test "resolve_scope_config: the config seat fills below env, above inherit/default" {
  let cfg_path = ent(
    "config",
    TStr,
    is_config_file=true,
    default_value=Some(VStr("app.json")),
  )
  let port = ent("port", TNum, config_seat=true)
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path, port],
    constraints: [],
  }
  let provider = fn(p : String) -> ConfigVal? {
    if p == "app.json" {
      Some(CObj([("port", CNum(4321.0))]))
    } else {
      None
    }
  }
  let bound = resolve_scope_config(sc, [], Map([]), provider)
  assert_eq(bound, Ok([mkb_pub("port", VNum(4321.0), Config)]))
}

///|
/// Guarantees: a COMMITTED config path (cli/env-explicit) that the provider fails to read is a
/// DR-066 Error (指定したのに読めない); a DEFAULT-only path reading `None` is silently tolerated
/// (the config seat stays empty and later seats/default apply) — DR-050 §2's asymmetry.
test "resolve_scope_config: a committed unreadable config path errors, a default one does not" {
  let never_reads = fn(_p : String) -> ConfigVal? { None }
  let committed = ent("config", TStr, is_config_file=true)
  let sc_committed : Scope = {
    greedy: [],
    positional: [],
    entities: [committed],
    constraints: [],
  }
  match
    resolve_scope_config(
      sc_committed,
      [cb("config", VStr("missing.json"), Cli)],
      Map([]),
      never_reads,
    ) {
    Err(pe) => {
      assert_eq(pe.element, "config")
      assert_eq(pe.reason, "config_read_failed")
    }
    Ok(_) =>
      fail("expected an Err, the committed config path could not be read")
  }
  // a default-only path (no cli/env) reading None is silently tolerated: no Error, the config seat
  // just supplies nothing (later entities fall through to inherit/default).
  let by_default = ent(
    "config",
    TStr,
    is_config_file=true,
    default_value=Some(VStr("optional.json")),
  )
  let port = ent("port", TNum, config_seat=true, default_value=Some(VNum(1.0)))
  let sc_default : Scope = {
    greedy: [],
    positional: [],
    entities: [by_default, port],
    constraints: [],
  }
  assert_eq(
    resolve_scope_config(sc_default, [], Map([]), never_reads),
    Ok([mkb_pub("port", VNum(1.0), Default)]),
  )
}

///|
/// Guarantees (DR-066 reason derivation, `config_mismatch_reason`): a config value of the wrong
/// STRUCTURE for a scalar cell (a JSON array where a scalar is expected) is a DR-037/066 Error with
/// a config-specific extension reason (no v1 reason covers structural mismatch yet, DR-066 §3).
test "resolve_scope_config: a structural config mismatch is an Error" {
  let scalar_cfg = ent("port", TNum, config_seat=true)
  let cfg_path = ent(
    "config",
    TStr,
    is_config_file=true,
    default_value=Some(VStr("app.json")),
  )
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path, scalar_cfg],
    constraints: [],
  }
  let provider = fn(_p : String) -> ConfigVal? {
    Some(CObj([("port", CArr([CNum(1.0), CNum(2.0)]))]))
  }
  match resolve_scope_config(sc, [], Map([]), provider) {
    Err(pe) => {
      assert_eq(pe.element, "port")
      assert_eq(pe.reason, "config_structural_mismatch")
    }
    Ok(_) => fail("expected an Err, a config array cannot fill a scalar cell")
  }
}

// ── command_child / inherited_of ──────────────────────────────────────────────

///|
/// Guarantees: `command_child` fetches a subcommand's built Scope by name from its parent's
/// `CmdSat` greedy entries; `inherited_of` turns a resolved-bindings array into the name→value
/// map the next scope's inherit seat reads (`resolve_scope`'s `inherited?` parameter).
test "command_child fetches a subcommand scope; inherited_of builds the parent context map" {
  let child : Scope = {
    greedy: [],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("serve", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  assert_eq(command_child(root, "serve"), Some(child))
  assert_eq(command_child(root, "missing"), None)
  let ctx = inherited_of([cb("ttl", VNum(60.0), Cli)])
  assert_eq(ctx.get("ttl"), Some(VNum(60.0)))
  assert_eq(ctx.get("absent"), None)
}

// ── DR-066 §4: path/provenance on ladder-fill Errors ──────────────────────────

///|
/// Guarantees (DR-066 §4): `resolve_scope`'s `path?` argument is this scope's DR-066 §4
/// result-nesting path, threaded straight into a ladder-fill Error's `path` field — no boundary
/// crossing to accumulate (unlike eval.mbt's CPS Held), because resolving one scope's entities
/// already runs WITH that scope's own path known statically. Root (`path` omitted, default `[]`)
/// carries an empty path; a scope one command deep (`path: ["sub"]`, as `resolve_tree` would thread
/// for a `sub` command scope) carries that path unchanged.
test "resolve_scope: a ladder-fill Error's path is the caller-supplied scope path" {
  let num = ent("n", TNum, env_key=Some("N"))
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [num],
    constraints: [],
  }
  // root (path omitted → default [])
  match resolve_scope(sc, [], Map::from_array([("N", "abc")])) {
    Err(pe) => assert_eq(pe.path, [])
    Ok(_) => fail("expected an Err, env value \"abc\" is not a number")
  }
  // one command scope deep
  match resolve_scope(sc, [], Map::from_array([("N", "abc")]), path=["sub"]) {
    Err(pe) => assert_eq(pe.path, ["sub"])
    Ok(_) => fail("expected an Err, env value \"abc\" is not a number")
  }
}

///|
/// Guarantees (DR-066 §4): `resolve_scope_config`'s `path?` argument likewise reaches BOTH ladder
/// Error sites — the config_read_failed Error (Phase 2, cf_element) and a per-entity config-seat
/// type-mismatch Error (Phase 3) — with the scope's own path, regardless of whether the entity uses
/// an explicit `config_key` (a DIFFERENT absolute path, used only for the config LOOKUP) or the
/// isomorphic default.
test "resolve_scope_config: a ladder-fill Error's path is the caller-supplied scope path, independent of config_key" {
  let cfg_path = ent(
    "config",
    TStr,
    is_config_file=true,
    default_value=Some(VStr("app.json")),
  )
  // Phase 2: a committed config path that fails to read.
  let sc1 : Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path],
    constraints: [],
  }
  let never_reads = fn(_p : String) -> ConfigVal? { None }
  match
    resolve_scope_config(
      sc1,
      [cb("config", VStr("missing.json"), Cli)],
      Map([]),
      never_reads,
      path=["sub"],
    ) {
    Err(pe) => {
      assert_eq(pe.reason, "config_read_failed")
      assert_eq(pe.path, ["sub"])
    }
    Ok(_) => fail("expected an Err, the committed config path cannot be read")
  }
  // Phase 3: a config-seat type mismatch, entity using an explicit config_key
  // (a config-tree lookup path distinct from the scope's own result path) —
  // the Error's `path` must still be the scope path, not the config_key.
  let scalar_cfg = ent(
    "port",
    TNum,
    config_seat=true,
    config_key=Some(["elsewhere", "port"]),
  )
  let sc2 : Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path, scalar_cfg],
    constraints: [],
  }
  let provider = fn(_p : String) -> ConfigVal? {
    Some(CObj([("elsewhere", CObj([("port", CStr("not-a-number"))]))]))
  }
  match resolve_scope_config(sc2, [], Map([]), provider, path=["sub"]) {
    Err(pe) => {
      assert_eq(pe.element, "port")
      assert_eq(pe.path, ["sub"]) // scope path, NOT ["elsewhere", "port"]
    }
    Ok(_) => fail("expected an Err, config \"port\" is not a number")
  }
}

// ── DR-077: update 効果 + count cli-seat fold ─────────────────────────────────

///|
/// A 0-token `update` effect binding (DR-077 §1) — mirrors `cb`'s Set-only shape but for the
/// old-dependent op; `value` is a placeholder (never read — resolve_entity's fold reads `old` off
/// the RUNNING state, not off this binding).
fn ceff(key : String, transform : String) -> Binding {
  {
    key,
    op: Update(transform, []),
    value: VBool(false),
    source: Cli,
    scope: [],
    link: 0,
  }
}

///|
/// 保証: DR-077 §1 ledger 挙動 — 3 つの `update(increment)` effect が同じ key で連続すると、
/// resolve_entity の cli seat fold は old=default(0)→1→2→3 と連鎖計算する (`-vvv` の実機シナリオ)。
/// count の default:0 preset (installer.mbt ensure_entity, DR-077 §3) が fold の起点になることも
/// 同時に固定する。
test "resolve_scope: 3 chained update(increment) effects ledger old=0→1→2→3" {
  let verbose = ent("verbose", TNum, default_value=Some(VNum(0.0)))
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [verbose],
    constraints: [],
  }
  let cli = [
    ceff("verbose", "increment"),
    ceff("verbose", "increment"),
    ceff("verbose", "increment"),
  ]
  assert_eq(
    resolve_scope(sc, cli, Map([])),
    Ok([mkb_pub("verbose", VNum(3.0), Cli)]),
  )
}

///|
/// 保証: DR-077 §1 — `update` effect が無指定の default (`e.default_value` が None) セルに対して
/// 発火すると、"old ?? default" (DR-077 §2) は default 不在時のフォールバック (bare zero) を使う。
/// count は常に default:0 を preset する (installer.mbt) ので実運用でこの分岐に落ちることは無いが、
/// 低レベル resolve_scope の契約としては独立に固定しておく (defensive のさらに一段防御)。
test "resolve_scope: update(increment) with no declared default falls back to a bare zero" {
  let n = ent("n", TNum) // no default_value
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  assert_eq(
    resolve_scope(sc, [ceff("n", "increment")], Map([])),
    Ok([mkb_pub("n", VNum(1.0), Cli)]),
  )
}

///|
/// 保証: DR-077 §3 — count が全く発火しない場合は default:0 のまま (flag の default:false と対称)、
/// かつ env 由来の文字列は number として普通に parse → SET される (`VERBOSITY=5` は 5 を set、
/// increment ではない) — count の CLI fold と env seat は完全に独立したラダー段であることを固定する
/// (cli 側が unset なら resolve_entity は env seat へそのまま fall through、DR-031 の既存契約通り)。
test "resolve_scope: count falls back to default:0 when unfired, and env SETS a plain number" {
  let verbose = ent(
    "verbose",
    TNum,
    env_key=Some("VERBOSITY"),
    default_value=Some(VNum(0.0)),
  )
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [verbose],
    constraints: [],
  }
  // no cli fire at all → default seat (0).
  assert_eq(
    resolve_scope(sc, [], Map([])),
    Ok([mkb_pub("verbose", VNum(0.0), Default)]),
  )
  // env seat: a plain number set, never an increment (no `update` op anywhere in this path).
  assert_eq(
    resolve_scope(sc, [], Map::from_array([("VERBOSITY", "5")])),
    Ok([mkb_pub("verbose", VNum(5.0), Env)]),
  )
}

// ── DR-077 §1 / issue 2026-07-09-filters-registry-foundation: post_filters が update 結果にも通る ──

///|
/// 保証 (issue の受け入れ条件そのもの — DR-040 「count の上限は post_filters (in_range 等) で書く」の
/// 実体化、DR-077 §1 「post_filters は update の結果にも通す」): count 要素 (update 効果で fold された
/// 値) に post_filters:["in_range:0:2"] を宣言すると、3 回連続 increment (-vvv 相当の ceff 3 個) の
/// 結果 3 が in_range の外に出て Err になる。2 回 (境界内) は通る。post_filters は set 経路・update
/// 経路を区別せず、resolve_entity が最終確定した値に対して一様に適用される (apply_entity_filters)。
test "resolve_scope: post_filters (in_range) rejects an update-folded count value over the limit" {
  let verbose = ent("verbose", TNum, default_value=Some(VNum(0.0)), post_filters=[
    "in_range:0:2",
  ])
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [verbose],
    constraints: [],
  }
  // 3 回 update(increment): old=0->1->2->3, 3 は in_range:0:2 の外。
  let cli3 = [
    ceff("verbose", "increment"),
    ceff("verbose", "increment"),
    ceff("verbose", "increment"),
  ]
  match resolve_scope(sc, cli3, Map([])) {
    Err(pe) => assert_eq(pe.reason, "filter_rejected")
    Ok(_) => fail("expected Err (3 is out of range [0, 2])")
  }
  // 2 回 (境界内) は通る。
  let cli2 = [ceff("verbose", "increment"), ceff("verbose", "increment")]
  assert_eq(
    resolve_scope(sc, cli2, Map([])),
    Ok([mkb_pub("verbose", VNum(2.0), Cli)]),
  )
}

///|
/// 保証: post_filters は set 経路 (通常の value option) にも同じく効く — DR-077 §1 が強調するのは
/// 「update の結果にも」という追加であって、set 経路の post_filters 適用は元々の DR-009/040 契約
/// (update 導入前から成立すべき前提)。両経路が同じ apply_entity_filters を通ることを対で固定する。
test "resolve_scope: post_filters (in_range) also rejects a plain Set value over the limit" {
  let n = ent("n", TNum, post_filters=["in_range:0:100"])
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  match resolve_scope(sc, [cb("n", VNum(101.0), Cli)], Map([])) {
    Err(pe) => assert_eq(pe.reason, "filter_rejected")
    Ok(_) => fail("expected Err (101 is out of range [0, 100])")
  }
  assert_eq(
    resolve_scope(sc, [cb("n", VNum(50.0), Cli)], Map([])),
    Ok([cb("n", VNum(50.0), Cli)]),
  )
}

///|
/// 保証 (issue 2026-07-09-post-filter-error-attribution): `filters`/`post_filters` reject の
/// Error は `kind: KFilter` を持つ (DR-053 §2 の `parse` | `filter` | `constraint` 3 分類 — 値が
/// パースできなかった `KParse` とは別カテゴリ、既にパース済みの値を validate/transform した結果の
/// reject なので `filter` 分類に属する)。`argv_pos` は呼び出し側が渡した最終位置をそのまま持つ
/// (env/config seat のエラーと同じ規約 — `ladder_err`/`filter_err` の doc comment 参照、値がどの
/// token でも読まれていないので位置は「argv 走査が完了した地点」= 呼び出し側の `toks.length()`
/// 相当。本テストでは呼び出し側が明示的に `at_pos=3` を渡し、それがそのまま素通しされることを
/// 固定する — 実際の conformance harness 側の配線 (`dc.argv.length()`) は
/// json_conformance_wbtest.mbt の `do_resolve_pe`/`resolve_tree` が担う)。
test "resolve_scope: a filters/post_filters reject carries kind=KFilter and the caller's at_pos" {
  let n = ent("n", TNum, post_filters=["in_range:0:100"])
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  match resolve_scope(sc, [cb("n", VNum(101.0), Cli)], Map([]), at_pos=3) {
    Err(pe) => {
      assert_eq(pe.kind, KFilter)
      assert_eq(pe.argv_pos, 3)
      assert_eq(pe.reason, "filter_rejected")
    }
    Ok(_) => fail("expected Err (101 is out of range [0, 100])")
  }
}

///|
/// 保証 (codex 指摘 2/3 の対、issue 2026-07-09-constraint-path-filtering-gap 節目レビュー):
/// `:update:increment:5` (0-arg 組み込み `increment` への余分な args) は definition-time では
/// 通る (installer_wbtest.mbt の対テスト参照 — registry に存在し signature も Transform なので
/// gate を通過する) が、**RUNTIME** で `apply_transform` が `(d.run)(old, args)` を呼んだ時点で
/// `filter_increment` 自身が `args.length() != 0` を拒否し (`filters.mbt`)、`kind: KFilter` /
/// `reason: "update_transform_type_mismatch"` の Error になることを固定する (codex 指摘 3:
/// この Error の kind は `ladder_err` (KParse) から `filter_err` (KFilter) へ置換済み — 値の
/// パース失敗ではなく filter/transform 語彙の拒否なので DR-053 §2 の分類上こちらが正しい)。
test "resolve_scope: an update transform's own arity rejection surfaces at runtime as kind=KFilter" {
  let n = ent("n", TNum, default_value=Some(VNum(0.0)))
  let sc : Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  let cli = [
    {
      key: "n",
      op: Update("increment", ["5"]),
      value: VBool(false),
      source: Cli,
      scope: [],
      link: 0,
    },
  ]
  match resolve_scope(sc, cli, Map([])) {
    Err(pe) => {
      assert_eq(pe.kind, KFilter)
      assert_eq(pe.reason, "update_transform_type_mismatch")
    }
    Ok(_) => fail("expected Err (increment takes no args)")
  }
}
