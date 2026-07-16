// resolve_wbtest.mbt — executable spec for the value-resolution layer (MDR-002 §3): the result
// builder (DR-016/025/043/044), export-key application + collision (DR-052/073), and the
// value-source ladder (DR-031/049/050, with the DR-074/075 env-lexer update over the slice).

///|
/// A scalar cli/env/config/… `@engine.Set` binding at the root scope (the common case in these tests;
/// nested-scope cases build the `@engine.Binding` literal directly to show the scope path explicitly).
fn cb(
  key : String,
  value : @engine.Value,
  source : @engine.Source,
  at_pos? : Int? = None,
) -> @engine.Binding {
  { key, op: @engine.Set, value, source, scope: [], link: 0, at_pos }
}

///|
/// An @engine.Entity builder with every ladder seat off by default (labeled optional args mirror slice
/// `poc/helpers_wbtest.mbt`'s `opt()` — only the ladder seats a test actually exercises are named).
fn ent(
  name : String,
  ty : &@engine.TypeExt,
  env_key? : String? = None,
  config_seat? : Bool = false,
  config_key? : Array[String]? = None,
  is_config_file? : Bool = false,
  inherit_? : Bool = false,
  is_tty? : Bool = false,
  tty_stream? : String? = None,
  tty_cygwin? : Bool = true,
  accum? : String? = None,
  flatten? : Bool = false,
  is_multiple_decl? : Bool = false,
  collector? : String? = None,
  default_value? : @engine.Value? = None,
  separator? : String? = None,
  piece_filters? : Array[String] = [],
  value_filters? : Array[String] = [],
  final_filters? : Array[String] = [],
  accum_filters? : Array[String] = [],
) -> @engine.Entity {
  // DR-083 §1: the field is the length-1-degenerate array (node.mbt's doc comment); this builder
  // keeps its OWN param scalar (every existing call site passes a single value, the common scalar-
  // entity case) and wraps it here, one place, instead of touching every `default_value=Some(v)`
  // call site across the file.
  let default_values : Array[@engine.Value]? = match default_value {
    Some(v) => Some([v])
    None => None
  }
  {
    name,
    ty,
    env_key,
    config_seat,
    config_key,
    is_config_file,
    inherit_,
    is_tty,
    tty_stream,
    tty_cygwin,
    accum,
    flatten,
    is_multiple_decl,
    collector,
    default_values,
    separator,
    // `chain` (filters_wbtest.mbt, same package): colon-shorthand ergonomics over `@engine.Entity`'s
    // production `Array[@engine.FilterSpelling]` fields (issue filter-spelling-inband-encoding-retyping).
    piece_filters: chain(piece_filters),
    value_filters: chain(value_filters),
    final_filters: chain(final_filters),
    accum_filters: chain(accum_filters),
    hidden: false,
    completer: None,
  }
}

///|
test "Entity equality distinguishes same-name TypeExt residents with different configuration" {
  // Entity structure delegates type identity to TypeExt name + encode; two bool parsers with
  // different accepted spellings are not structurally interchangeable.
  let canonical = ent("enabled", @builtins.bool_type())
  let configured = ent(
    "enabled",
    @builtins.bool_type(config={
      true_values: ["yes"],
      false_values: ["no"],
      case_insensitive: false,
    }),
  )
  assert_false(canonical == configured)
}

// ── build_result (DR-016/025/043/044) ─────────────────────────────────────────

///|
/// Guarantees: a plain scalar cell renders last-wins (DR-015), an accumulate cell folds same-key
/// effects into an array (DR-043/034/036, `empty` clears prior items), and a scalar cell's preset
/// default seats when the cell has no winning binding at all (DR-031 default seat / DR-051 §2 flag
/// は absent にならない) — three of the builder's structural cases in one pass over a flat scope.
test "build_result folds scalar last-wins, accumulate array, and default seat" {
  let binds : Array[@engine.Binding] = [
    cb("port", @engine.VNum(8080.0), @engine.Cli),
    cb("port", @engine.VNum(9090.0), @engine.Cli), // last-wins: 9090 should win over 8080
    cb("tags", @engine.VStr("a"), @engine.Cli),
    cb("tags", @engine.VStr("b"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "tags",
      collector: None,
      accum_filters: [],
      accum: "append",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  let defaults : Array[DefaultCell] = [
    { path: [], name: "verbose", value: @engine.VBool(false) },
  ]
  let r = build_result(binds, cells, defaults, [])
  assert_eq(
    r,
    RObj([
      ("port", RScalar(@engine.VNum(9090.0))),
      ("tags", RArr([RScalar(@engine.VStr("a")), RScalar(@engine.VStr("b"))])),
      ("verbose", RScalar(@engine.VBool(false))),
    ]),
  )
}

///|
/// Guarantees: an `empty` effect on an accumulate cell CLEARS everything accumulated before it
/// (DR-045 empty op) — re-accumulation after `empty` starts fresh, not appended to the discard.
test "build_result: an empty op on an accumulate cell clears prior items" {
  let binds : Array[@engine.Binding] = [
    cb("tags", @engine.VStr("a"), @engine.Cli),
    {
      key: "tags",
      op: @engine.Empty,
      value: @engine.VBool(false), // placeholder — empty carries no operand
      source: @engine.Cli,
      scope: [],
      link: 0,
      at_pos: None,
    },
    cb("tags", @engine.VStr("c"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "tags",
      collector: None,
      accum_filters: [],
      accum: "append",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  let r = build_result(binds, cells, [], [])
  assert_eq(r, RObj([("tags", RArr([RScalar(@engine.VStr("c"))]))]))
}

///|
/// Guarantees: an accumulate cell that fired ZERO times still renders `[]` (DR-044 §1 uniform
/// array) instead of being absent from the result object.
test "build_result: an unfired accumulate cell renders [] (DR-044 uniform array)" {
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "tags",
      collector: None,
      accum_filters: [],
      accum: "append",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
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
  let binds : Array[@engine.Binding] = [
    cb("tag", @engine.VStr("solo"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "tag",
      collector: Some("unwrap_single"),
      accum_filters: [],
      accum: "append",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([("tag", RScalar(@engine.VStr("solo")))]),
  )
}

///|
/// 保証: unwrap_single は「唯一無二の縮退」だけを畳む — 2 要素以上の accumulation は集約結果の
/// ARRAY のまま残る (resolve.mbt `unwrap_single`'s doc comment: "Length 0 or >= 2 arrays are left
/// unchanged")。前ケース (length-1 → scalar) と対で unwrap_single の輪郭を固定する。
test "build_result: a collector (unwrap_single) leaves a 2+ element accumulation as an array" {
  let binds : Array[@engine.Binding] = [
    cb("tag", @engine.VStr("a"), @engine.Cli),
    cb("tag", @engine.VStr("b"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "tag",
      collector: Some("unwrap_single"),
      accum_filters: [],
      accum: "append",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([
      ("tag", RArr([RScalar(@engine.VStr("a")), RScalar(@engine.VStr("b"))])),
    ]),
  )
}

///|
/// 保証: 0 回発火の accum cell に collector が付いていても、DR-044 §1 の uniform array 契約 (未発火
/// でも `[]` を描画、absent にしない) は崩れない — unwrap_single([]) は空配列のまま (unchanged)
/// なので、collector 適用後も `[]` のまま描画される。uniform-array 注入経路 (build_result の
/// `UNIFORM ARRAY` 分岐) にも collector 適用を配線したことを固定する (ACCUMULATE 分岐だけでなく)。
test "build_result: a collector on an unfired accum cell still renders [] (DR-044 uniform array)" {
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "tag",
      collector: Some("unwrap_single"),
      accum_filters: [],
      accum: "append",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  assert_eq(build_result([], cells, [], []), RObj([("tag", RArr([]))]))
}

///|
/// Guarantees: an @engine.IdxRepeat's "[]"/"#k" sentinel encoding (DR-043 named indexed repeat) folds into
/// an ARRAY of one element per firing, each element itself built by recursing under its "#k" — the
/// nameless "" leaf at each index is the SCALAR case (a seq/array context nameless value, DR-052
/// §2), not promoted into a kv object.
test "build_result: [] + #k sentinels fold an indexed repeat into an array" {
  let binds : Array[@engine.Binding] = [
    {
      key: "[]",
      op: @engine.Set,
      value: @engine.VBool(true),
      source: @engine.Cli,
      scope: ["xs"],
      link: 0,
      at_pos: None,
    },
    {
      key: "",
      op: @engine.Set,
      value: @engine.VStr("a"),
      source: @engine.Cli,
      scope: ["xs", "#0"],
      link: 0,
      at_pos: None,
    },
    {
      key: "",
      op: @engine.Set,
      value: @engine.VStr("b"),
      source: @engine.Cli,
      scope: ["xs", "#1"],
      link: 0,
      at_pos: None,
    },
  ]
  let r = build_result(binds, [], [], [])
  assert_eq(
    r,
    RObj([
      ("xs", RArr([RScalar(@engine.VStr("a")), RScalar(@engine.VStr("b"))])),
    ]),
  )
}

// ── export-key application (DR-052) ───────────────────────────────────────────

///|
/// Guarantees: `apply_export_keys` overrides a value cell's key (@engine.EkKey) and drops a scope label
/// entirely (@engine.EkNull, DR-052 §2 透過 — children promote to the parent), leaving an unmapped
/// (@engine.EkUnset) name unchanged.
test "apply_export_keys renames a leaf key and drops a null-exported scope label" {
  let ek : Map[String, @engine.ExportKey] = Map::from_array([
    ("port", @engine.export_key("p")),
    ("wrapper", @engine.export_key_null()),
  ])
  let binds : Array[@engine.Binding] = [
    cb("port", @engine.VNum(80.0), @engine.Cli),
    {
      key: "verbose",
      op: @engine.Set,
      value: @engine.VBool(true),
      source: @engine.Cli,
      scope: ["wrapper"],
      link: 0,
      at_pos: None,
    },
  ]
  let mapped = apply_export_keys(binds, ek)
  assert_eq(mapped[0].key, "p")
  assert_eq(mapped[1].scope, []) // "wrapper" label dropped → child promotes to root
  assert_eq(mapped[1].key, "verbose") // unmapped name unchanged (@engine.EkUnset default)
}

///|
/// issue accum-export-key-rename-asymmetry: `accum_cells` used to ignore `ek` entirely, returning
/// AccumCells keyed by the RAW entity name while `build_result`'s `cells` argument is matched
/// against ALREADY export_key-mapped binding keys (`apply_export_keys` runs first) — a renamed
/// accum entity's AccumCell silently failed to match, so the accumulate fold never fired (the
/// entity's own bindings fell through to plain last-wins scalar rendering under the OLD name
/// instead of folding into `[]` under the renamed key, exactly the shape `build_result`'s "OBJECT"
/// branch's `cell_here` check exists to prevent). This pins the fix: `tags` (accum) has
/// `export_key: "t"` — the accumulated array must render under "t", not "tags", and the fold must
/// actually happen (2 elements, not a last-wins scalar).
test "accum_cells resolves export_key rename — the accumulate fold fires under the renamed key" {
  let ek : Map[String, @engine.ExportKey] = Map::from_array([
    ("tags", @engine.export_key("t")),
  ])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ent("tags", @builtins.string_type(), accum=Some("append"))],
    constraints: [],
  }
  let cells = accum_cells(sc, ek)
  assert_eq(cells.length(), 1)
  assert_eq(cells[0].name, "t")
  let binds : Array[@engine.Binding] = [
    cb("tags", @engine.VStr("a"), @engine.Cli),
    cb("tags", @engine.VStr("b"), @engine.Cli),
  ]
  let r = build_result(apply_export_keys(binds, ek), cells, [], [])
  assert_eq(
    r,
    RObj([("t", RArr([RScalar(@engine.VStr("a")), RScalar(@engine.VStr("b"))]))]),
  )
}

///|
/// 保証 (対極、上のテストの境界、[[self-written-rule-blind-spots]] の対極確認): export_key: null
/// を持つ accum セル自身は結果キー軸を失う (DR-052 §2 透過、スカラー default の @engine.EkNull と同じ posture)
/// — 変更が「常に何らかのキーで accum セルを出力してしまう」誤動作を生んでいないことを固定する。
test "accum_cells 対極: an @engine.EkNull accum cell carries no result-key axis (dropped)" {
  let ek : Map[String, @engine.ExportKey] = Map::from_array([
    ("tags", @engine.export_key_null()),
  ])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ent("tags", @builtins.string_type(), accum=Some("append"))],
    constraints: [],
  }
  assert_eq(accum_cells(sc, ek), [])
}

///|
/// 保証: command scope の export_key rename も path (accum セルのネスト先) に正しく反映される —
/// `apply_export_to_defaults` の scope-label 変換ロジック (233-243行) と同じ意味論を
/// `collect_accum` の @engine.CmdSat 再帰でも固定する。
test "accum_cells resolves export_key rename on a command scope label (nested path)" {
  let ek : Map[String, @engine.ExportKey] = Map::from_array([
    ("sub", @engine.export_key("s")),
  ])
  let child : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ent("tags", @builtins.string_type(), accum=Some("append"))],
    constraints: [],
  }
  let root : @engine.Scope = {
    greedy: [@engine.CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cells = accum_cells(root, ek)
  assert_eq(cells.length(), 1)
  assert_eq(cells[0].path, ["s"])
  assert_eq(cells[0].name, "tags")
}

///|
/// 保証 (fixture export-key/rename-multiple.json::renamed-key-zero-fire-empty-array の実機確認、
/// DR-051 §2「反復系は absent にならない、0 回発火でも [] を持つ」): rename された accum セル
/// (tags → export_key:"t") が 0 回発火でも `t` キーの下に `[]` が現れる — export_key rename は
/// DR-044 の一様配列規則を無効化しない (rename は「fold 済みの値をどこへ写像するか」だけを決める
/// 直交軸、issue accum-export-key-rename-asymmetry の一般原則そのもの)。同 fixture の 3件目 case
/// (`null-export-key-multiple-transparent`) が「未発火の renamed accum セルはキーごと消える」と
/// 期待しているのは、この DR-051 §2 の絶対規則 (反復系は type/export_key を問わず常に `[]`、
/// transparent-seq.json の zero-fire-empty-array と同型) と矛盾する — fixture 側の推定誤りと判断
/// し、修正せず report した (team-lead 裁定待ち)。
test "accum_cells + build_result: a renamed accum cell with zero fires still renders `[]` under the renamed key (DR-051 §2)" {
  let ek : Map[String, @engine.ExportKey] = Map::from_array([
    ("tags", @engine.export_key("t")),
  ])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ent("tags", @builtins.string_type(), accum=Some("append"))],
    constraints: [],
  }
  let cells = accum_cells(sc, ek)
  let r = build_result(apply_export_keys([], ek), cells, [], [])
  assert_eq(r, RObj([("t", RArr([]))]))
}

// ── export-key collision (DR-073) ─────────────────────────────────────────────
//
// Mirrors spec fixture `fixtures/export-key/collision.json` exactly: two flags `a`/`b` both
// export_key `x`.

///|
fn collision_ek() -> Map[String, @engine.ExportKey] {
  Map::from_array([
    ("a", @engine.export_key("x")),
    ("b", @engine.export_key("x")),
  ])
}

///|
/// co-exposure-collision (`--a --b`): both a and b fire in the SAME parse and both map to `x` —
/// a genuine runtime collision (DESIGN §15.5 / DR-021). `find_export_collisions` reports the
/// group; `build_interpretations` yields 2 interpretations (one claiming `x` per entity), both
/// degenerating to the SAME view `{x:true}` (both flags) — distinguished ONLY by claimants
/// (DR-073 §1/§2), exactly the fixture's expected shape.
test "DR-073 co-exposure-collision: degenerate views distinguished by claimants" {
  let ek = collision_ek()
  let binds : Array[@engine.Binding] = [
    cb("a", @engine.VBool(true), @engine.Cli),
    cb("b", @engine.VBool(true), @engine.Cli),
  ]
  let collisions = find_export_collisions(binds, ek)
  assert_eq(collisions.length(), 1)
  assert_eq(collisions[0].path, [])
  assert_eq(collisions[0].key, "x")
  assert_eq(collisions[0].claimants, ["a", "b"])
  let interps = build_interpretations(binds, ek, [], [])
  assert_eq(interps.length(), 2)
  assert_eq(interps[0].result, RObj([("x", RScalar(@engine.VBool(true)))]))
  assert_eq(interps[0].claimants, [("x", "a")])
  assert_eq(interps[1].result, RObj([("x", RScalar(@engine.VBool(true)))]))
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
  let binds : Array[@engine.Binding] = [
    cb("a", @engine.VBool(true), @engine.Cli),
  ]
  assert_eq(find_export_collisions(binds, ek), [])
  let defaults : Array[DefaultCell] = [
    { path: [], name: "b", value: @engine.VBool(false) },
  ]
  let interps = build_interpretations(
    binds,
    ek,
    [],
    apply_export_to_defaults(defaults, ek),
  )
  assert_eq(interps.length(), 1)
  assert_eq(interps[0].claimants, [])
  assert_eq(interps[0].result, RObj([("x", RScalar(@engine.VBool(true)))]))
}

///|
/// issue export-key-collision-identity-exposure-gap: an IDENTITY-exposed element (export_key
/// unset, DR-052 §1 "未指定 → name 由来のキーで露出" — `a`'s own name "a" IS its resolved exposed
/// key) competing with another element's `@engine.EkKey`-MAPPED key for the same result-scope key is a
/// genuine collision, same as the co-exposure-collision test above where both sides are mapped.
/// `find_export_collisions` used to only group `@engine.EkKey`-mapped bindings, silently excluding
/// identity-exposed ones (DR-052 §1's resolution table treats "未指定" as resolving to a real key,
/// not a separate "no key" state — same posture `apply_export_keys` already takes for the SAME `_`
/// fallback, this fix brings collision detection into parity with it).
test "DR-073 identity-exposure collision: @engine.EkUnset element vs @engine.EkKey-mapped element sharing a key" {
  // `a` has no ek entry at all (map doesn't even mention it — the common "declared without
  // export_key" shape) — resolves to identity exposure under "a" itself. `b` explicitly maps to
  // the SAME key "a".
  let ek : Map[String, @engine.ExportKey] = Map::from_array([
    ("b", @engine.export_key("a")),
  ])
  let binds : Array[@engine.Binding] = [
    cb("a", @engine.VBool(true), @engine.Cli),
    cb("b", @engine.VBool(true), @engine.Cli),
  ]
  let collisions = find_export_collisions(binds, ek)
  assert_eq(collisions.length(), 1)
  assert_eq(collisions[0].path, [])
  assert_eq(collisions[0].key, "a")
  assert_eq(collisions[0].claimants, ["a", "b"])
  // build_interpretations の drop 判定 (issue 受け入れ条件「promote_collision_ambiguous のドロップ
  // 判定も同様に拡張」) — 2 interpretations、各々が claimant 1 個ずつを残し他方を drop する。
  let interps = build_interpretations(binds, ek, [], [])
  assert_eq(interps.length(), 2)
  assert_eq(interps[0].result, RObj([("a", RScalar(@engine.VBool(true)))]))
  assert_eq(interps[0].claimants, [("a", "a")])
  assert_eq(interps[1].result, RObj([("a", RScalar(@engine.VBool(true)))]))
  assert_eq(interps[1].claimants, [("a", "b")])
}

///|
/// 保証 (対極、上のテストの境界、[[self-written-rule-blind-spots]] の対極確認): 2つの identity 露出
/// 要素は当然ながら別名 (別キー) を持つので衝突しない — identity 露出をグルーピング対象に含めた
/// 変更が「無関係な identity 要素同士まで誤って衝突と判定してしまう」誤動作を生んでいないことを
/// 固定する。
test "DR-073 identity-exposure 対極: two distinctly-named identity-exposed elements never collide" {
  let ek : Map[String, @engine.ExportKey] = Map([])
  let binds : Array[@engine.Binding] = [
    cb("a", @engine.VBool(true), @engine.Cli),
    cb("b", @engine.VBool(true), @engine.Cli),
  ]
  assert_eq(find_export_collisions(binds, ek), [])
}

// ── value-source ladder (DR-031/049/050) ──────────────────────────────────────

///|
/// Guarantees: the ladder picks cli > env > default in that order when multiple seats could supply
/// the same cell — this is the DR-031 invariant the whole layer exists to realize.
test "resolve_scope: cli wins over env, env wins over default" {
  let port = ent(
    "port",
    @builtins.number_type(),
    env_key=Some("PORT"),
    default_value=Some(@engine.VNum(1.0)),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [port],
    constraints: [],
  }
  // cli present → cli wins regardless of env/default.
  let cli_bound = resolve_scope(
    sc,
    [cb("port", @engine.VNum(8080.0), @engine.Cli)],
    Map::from_array([("PORT", "9999")]),
  )
  assert_eq(cli_bound, Ok([cb("port", @engine.VNum(8080.0), @engine.Cli)]))
  // no cli → env wins over default.
  let env_bound = resolve_scope(sc, [], Map::from_array([("PORT", "9999")]))
  assert_eq(env_bound, Ok([mkb_pub("port", @engine.VNum(9999.0), @engine.Env)]))
  // neither cli nor env → default seats.
  let default_bound = resolve_scope(sc, [], Map([]))
  assert_eq(
    default_bound,
    Ok([mkb_pub("port", @engine.VNum(1.0), @engine.Default)]),
  )
}

///|
/// A `@engine.Set` binding builder exposed for assertions (mirrors `@engine.mkb`'s shape without re-exporting it).
fn mkb_pub(
  key : String,
  value : @engine.Value,
  source : @engine.Source,
  at_pos? : Int? = None,
) -> @engine.Binding {
  { key, op: @engine.Set, value, source, scope: [], link: 0, at_pos }
}

///|
/// Guarantees: the inherit seat (DR-031 #4 / DR-013) supplies the nearest ancestor scope's
/// same-named value when no cli/env/config seat wins, and is itself out-ranked by a default seat
/// that would only apply when inherit has nothing (both absent here → default).
test "resolve_scope: inherit seat fills from the parent context map" {
  let ttl = ent(
    "ttl",
    @builtins.number_type(),
    inherit_=true,
    default_value=Some(@engine.VNum(30.0)),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ttl],
    constraints: [],
  }
  let inherited = Map::from_array([("ttl", @engine.VNum(60.0))])
  let bound = resolve_scope(sc, [], Map([]), inherited~)
  assert_eq(bound, Ok([mkb_pub("ttl", @engine.VNum(60.0), @engine.Inherit)]))
  // no inherited value present → falls through to default.
  let bound_no_parent = resolve_scope(sc, [], Map([]))
  assert_eq(
    bound_no_parent,
    Ok([mkb_pub("ttl", @engine.VNum(30.0), @engine.Default)]),
  )
}

///|
/// DR-099 §2: tty preset 型要素の default 席解決規則は inherit 席より後に評価される — 「明示
/// (CLI/env/config) > 継承 (inherit) > 観測 (tty) > 宣言既定 (default)」の序列そのものを固定する
/// (DR-098 §5 が確立した優先順位は、独立ラダー席からこの型の default 解決ロジックへ実装位置が
/// 移っただけで完全に維持される)。fixture 側 (`value-sources/tty-ladder.json`) は cli/env/tty/default
/// の 4 値源の相互比較を固定するが、inherit との直接対決は fixture に無い軸 (fixture の definition
/// は inherit を持たない) — ここで補う。
test "resolve_scope: tty 型 default 席は inherit 席の後で評価される (DR-099 §2)" {
  let use_color = ent(
    "use_color",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stdout"),
    tty_cygwin=false, // cygwin 分岐を無効化し fold=terminal に単純化 (cygwin dial は別テストで検証)
    inherit_=true,
    default_value=Some(@engine.VBool(true)),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [use_color],
    constraints: [],
  }
  // inherit と tty 観測が両方あり、値が食い違う場合 → inherit が勝つ (継承は観測より強い、DR-099 §2)。
  let inherited = Map::from_array([("use_color", @engine.VBool(false))])
  let inherit_wins = resolve_scope(
    sc,
    [],
    Map([]),
    inherited~,
    tty=Map::from_array([("stdout", { terminal: true, cygwin: false })]),
  )
  assert_eq(
    inherit_wins,
    Ok([mkb_pub("use_color", @engine.VBool(false), @engine.Inherit)]),
  )
  // inherit 供給なし、tty 観測あり → fold が宣言 default より勝つ。
  let tty_wins = resolve_scope(
    sc,
    [],
    Map([]),
    tty=Map::from_array([("stdout", { terminal: false, cygwin: false })]),
  )
  assert_eq(
    tty_wins,
    Ok([mkb_pub("use_color", @engine.VBool(false), @engine.Tty)]),
  )
  // どちらも供給なし → 宣言 default (最終フォールバック)。
  let default_wins = resolve_scope(sc, [], Map([]))
  assert_eq(
    default_wins,
    Ok([mkb_pub("use_color", @engine.VBool(true), @engine.Default)]),
  )
}

///|
/// DR-099 §4: tty_provider の応答は stream ごとに独立 ("null = 提供なし" は要素単位の stream
/// lookup — 他 stream に値があっても伝播しない)。複数の bool 要素がそれぞれ別 stream (stdin/stdout/
/// stderr) に紐付く場合、provider が一部 stream にのみ応答するケースで各要素が個別にフォールスルー
/// することを固定する — fixture (`tty-ladder.json`) は単一要素 (stdout 1 本) の相互比較のみなので、
/// 複数要素の stream 独立性は fixture から見えない軸。
test "resolve_scope: tty 型 default 席の解決は stream ごとに独立 (複数要素間で伝播しない)" {
  let stdin_tty = ent(
    "stdin_tty",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stdin"),
    default_value=Some(@engine.VBool(false)),
  )
  let stdout_tty = ent(
    "stdout_tty",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stdout"),
    default_value=Some(@engine.VBool(false)),
  )
  let stderr_tty = ent(
    "stderr_tty",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stderr"),
    default_value=Some(@engine.VBool(false)),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [stdin_tty, stdout_tty, stderr_tty],
    constraints: [],
  }
  // provider は stdout にのみ応答 (terminal:true)。stdin/stderr は tty map にキー自体が無い = 提供なし
  // (DR-099 §4「null = 提供なし」) — env_map の「未設定キー」と同じ縮退。
  let bound = resolve_scope(
    sc,
    [],
    Map([]),
    tty=Map::from_array([("stdout", { terminal: true, cygwin: false })]),
  )
  assert_eq(
    bound,
    Ok([
      mkb_pub("stdin_tty", @engine.VBool(false), @engine.Default),
      mkb_pub("stdout_tty", @engine.VBool(true), @engine.Tty),
      mkb_pub("stderr_tty", @engine.VBool(false), @engine.Default),
    ]),
  )
}

///|
/// DR-099 §3 の fold 計算式そのものの whitebox: `fold(観測) = terminal || (tty_cygwin && cygwin)`。
/// 同一の生観測 `{terminal:false, cygwin:true}` を 2 要素に供給し、`tty_cygwin` config だけを変えて
/// 結果が分岐することを @engine.Entity 直下で固定する (fixture `cygwin-dial-pair` の JSON 経由の対を
/// ラダー層で裏取り — options/definitions.types の decode を介さず fold 式そのものを検証する axis)。
test "resolve_scope: tty fold formula — tty_cygwin dial flips the result from the same raw observation (DR-099 §3)" {
  let cygwin_on = ent(
    "cygwin_on",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stderr"),
    tty_cygwin=true, // 既定
  )
  let cygwin_off = ent(
    "cygwin_off",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stderr"),
    tty_cygwin=false,
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [cygwin_on, cygwin_off],
    constraints: [],
  }
  let bound = resolve_scope(
    sc,
    [],
    Map([]),
    tty=Map::from_array([("stderr", { terminal: false, cygwin: true })]),
  )
  // fold(cygwin_on)  = false || (true  && true) = true
  // fold(cygwin_off) = false || (false && true) = false
  assert_eq(
    bound,
    Ok([
      mkb_pub("cygwin_on", @engine.VBool(true), @engine.Tty),
      mkb_pub("cygwin_off", @engine.VBool(false), @engine.Tty),
    ]),
  )
}

///|
/// DR-099 §2 の優先順位そのものの whitebox: 宣言 default と観測が異なる値を持つとき、観測が必ず
/// 勝つ (`resolved_default = fold(観測) ?? 宣言 default ?? absent` の `??` は「観測が得られる限り」
/// という意味であり、値の一致/不一致では条件分岐しない — fixture の fold-overrides-default と同じ
/// 主張をラダー層で直接固定する)。
test "resolve_scope: tty 型要素は宣言 default と異なる観測値でも観測が勝つ (DR-099 §2)" {
  let use_color = ent(
    "use_color",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stdout"),
    tty_cygwin=false,
    default_value=Some(@engine.VBool(true)), // 宣言 default = true
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [use_color],
    constraints: [],
  }
  // 観測 = false (宣言 default の true と食い違う)。
  let bound = resolve_scope(
    sc,
    [],
    Map([]),
    tty=Map::from_array([("stdout", { terminal: false, cygwin: false })]),
  )
  assert_eq(
    bound,
    Ok([mkb_pub("use_color", @engine.VBool(false), @engine.Tty)]),
  )
}

///|
/// DR-099 §2「両方とも得られなければ absent (素の bool の default 無し要素と同じ帰結、§2.6)」—
/// tty preset 要素は観測も宣言 default も無い場合、absent (result にキー自体が出ない) へ落ちること
/// を resolve.mbt の fold-fallthrough 経路で固定する (`@engine.Entity.default_values` が None のケース)。
/// どの fixture でも直接検証されていない軸: tty-ladder.json の null-observation-uses-default case は
/// 必ず明示 default (`use_color` の `default: true`) を宣言しているため、「宣言 default も無い」は
/// fixture から見えない。ElemDef→@engine.Entity 構築時に is_tty 要素へ @builtins.bool_type() の暗黙 default:false を注入
/// しないための `ensure_entity` 側の除外分岐 (installer.mbt) は installer_wbtest.mbt が別途固定する。
test "resolve_scope: tty 型要素は観測も宣言 default も無ければ absent (DR-099 §2)" {
  let use_color = ent(
    "use_color",
    @builtins.bool_type(),
    is_tty=true,
    tty_stream=Some("stdout"),
  )
  // default_value 省略 = 宣言 default 無し。
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [use_color],
    constraints: [],
  }
  let bound = resolve_scope(sc, [], Map([])) // tty 供給なし・観測なし
  assert_eq(bound, Ok([]))
}

///|
/// issue bool-requires-config-inherit-gap の diverge 調査で発見した非対称バグの固定:
/// `resolve_scope_config` の Phase 3 (`if !e.is_config_file`) は「config_file 要素は配線宣言で
/// あって結果 entity ではない」規則を守るが、config データを供給しない呼び出し (`resolve_scope`
/// 経由、config_obj=None) は元々このガードを持たず、config_file 要素の宣言 default がそのまま
/// 通常ラダーで解決されて result に漏れていた (`requires-bool-target-config-inherit.json` の
/// `inherit-true-satisfies-requires` case が config を一切供給しない中で config_file 要素を
/// 定義に持つ、という組合せで顕在化)。スコープが `config_file` 要素を宣言していても、config
/// オブジェクトを供給しない呼び出しでは無視 (bindings を生成しない) することを固定する。
test "resolve_scope: a config_file element is never resolved (skipped even when the caller supplies no config object)" {
  let cfg = ent(
    "config",
    @builtins.string_type(),
    is_config_file=true,
    default_value=Some(@engine.VStr("/app.toml")),
  )
  let port = ent(
    "port",
    @builtins.number_type(),
    default_value=Some(@engine.VNum(7.0)),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [cfg, port],
    constraints: [],
  }
  // config_file 要素の default は宣言されているが、resolve_scope の結果には一切現れない (port の
  // default だけが seat する)。
  assert_eq(
    resolve_scope(sc, [], Map([])),
    Ok([mkb_pub("port", @engine.VNum(7.0), @engine.Default)]),
  )
  // CLI で config_file 要素へ明示的にパスを与えても (通常 entity なら committed で勝つ場面) 同じく
  // 無視される — config_file 要素は「値セル」ではなく「配線先パスの宣言」であるという性質そのものが
  // resolve_scope 経路でも一貫することの確認 (対極: resolve_scope_config 側の既存挙動は本 wbtest
  // では触らない、Phase 3 の `if !e.is_config_file` が既にそれを保証している)。
  assert_eq(
    resolve_scope(
      sc,
      [cb("config", @engine.VStr("/cli.toml"), @engine.Cli)],
      Map([]),
    ),
    Ok([mkb_pub("port", @engine.VNum(7.0), @engine.Default)]),
  )
}

///|
/// Guarantees (DR-074/075 update over slice `env_value`): a badly-typed env string is a DR-066
/// Error with the canonical reason (`not_a_number` / `not_an_integer` / `not_a_bool`) — NOT a
/// silent `@engine.VStr` fallback into a wrong-typed cell (the slice's behaviour this port fixes).
test "resolve_scope: a badly-typed env value is a DR-066 Error, not a silent @engine.VStr fallback" {
  let num = ent("n", @builtins.number_type(), env_key=Some("N"))
  let sc_num : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [num],
    constraints: [],
  }
  match resolve_scope(sc_num, [], Map::from_array([("N", "abc")])) {
    Err(pe) => {
      assert_eq(pe.element, "n")
      assert_eq(pe.kind, @engine.KParse)
      assert_eq(pe.reason, "not_a_number")
    }
    Ok(_) => fail("expected an Err, env value \"abc\" is not a number")
  }
  let int_ = ent("i", @builtins.int_type(), env_key=Some("I"))
  let sc_int : @engine.Scope = {
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
  let sc_int_ok : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ent("i", @builtins.int_type(), env_key=Some("I"))],
    constraints: [],
  }
  assert_eq(
    resolve_scope(sc_int_ok, [], Map::from_array([("I", "3.0")])),
    Ok([mkb_pub("i", @engine.VNum(3.0), @engine.Env)]),
  )
  let flag = ent("f", @builtins.flag_type(), env_key=Some("F"))
  let sc_flag : @engine.Scope = {
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
    @builtins.string_type(),
    is_config_file=true,
    default_value=Some(@engine.VStr("app.json")),
  )
  let port = ent("port", @builtins.number_type(), config_seat=true)
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path, port],
    constraints: [],
  }
  let config = config_from_json(@json.parse("{\"port\":4321}"))
  let provider = fn(p : String) -> @engine.ConfigVal? {
    if p == "app.json" {
      Some(config)
    } else {
      None
    }
  }
  let bound = resolve_scope_config(sc, [], Map([]), provider)
  assert_eq(bound, Ok([mkb_pub("port", @engine.VNum(4321.0), @engine.Config)]))
}

///|
/// Guarantees: a COMMITTED config path (cli/env-explicit) that the provider fails to read is a
/// DR-066 Error (指定したのに読めない); a DEFAULT-only path reading `None` is silently tolerated
/// (the config seat stays empty and later seats/default apply) — DR-050 §2's asymmetry.
test "resolve_scope_config: a committed unreadable config path errors, a default one does not" {
  let never_reads = fn(_p : String) -> @engine.ConfigVal? { None }
  let committed = ent("config", @builtins.string_type(), is_config_file=true)
  let sc_committed : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [committed],
    constraints: [],
  }
  match
    resolve_scope_config(
      sc_committed,
      [cb("config", @engine.VStr("missing.json"), @engine.Cli)],
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
    @builtins.string_type(),
    is_config_file=true,
    default_value=Some(@engine.VStr("optional.json")),
  )
  let port = ent(
    "port",
    @builtins.number_type(),
    config_seat=true,
    default_value=Some(@engine.VNum(1.0)),
  )
  let sc_default : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [by_default, port],
    constraints: [],
  }
  assert_eq(
    resolve_scope_config(sc_default, [], Map([]), never_reads),
    Ok([mkb_pub("port", @engine.VNum(1.0), @engine.Default)]),
  )
}

///|
/// Guarantees (DR-066 reason derivation, `config_mismatch_reason`): a config value of the wrong
/// STRUCTURE for a scalar cell (a JSON array where a scalar is expected) is a DR-037/066 Error with
/// a config-specific extension reason (no v1 reason covers structural mismatch yet, DR-066 §3).
test "resolve_scope_config: a structural config mismatch is an Error" {
  let scalar_cfg = ent("port", @builtins.number_type(), config_seat=true)
  let cfg_path = ent(
    "config",
    @builtins.string_type(),
    is_config_file=true,
    default_value=Some(@engine.VStr("app.json")),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path, scalar_cfg],
    constraints: [],
  }
  let config = config_from_json(@json.parse("{\"port\":[1,2]}"))
  let provider = fn(_p : String) -> @engine.ConfigVal? { Some(config) }
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
/// Guarantees: `command_child` fetches a subcommand's built @engine.Scope by name from its parent's
/// `@engine.CmdSat` greedy entries; `inherited_of` turns a resolved-bindings array into the name→value
/// map the next scope's inherit seat reads (`resolve_scope`'s `inherited?` parameter).
test "command_child fetches a subcommand scope; inherited_of builds the parent context map" {
  let child : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : @engine.Scope = {
    greedy: [@engine.CmdSat("serve", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  assert_eq(command_child(root, "serve"), Some(child))
  assert_eq(command_child(root, "missing"), None)
  let ctx = inherited_of([cb("ttl", @engine.VNum(60.0), @engine.Cli)])
  assert_eq(ctx.get("ttl"), Some(@engine.VNum(60.0)))
  assert_eq(ctx.get("absent"), None)
}

// ── DR-066 §4: path/provenance on ladder-fill Errors ──────────────────────────

///|
/// Guarantees (DR-066 §4): `resolve_scope`'s `path?` argument is this scope's DR-066 §4
/// result-nesting path, threaded straight into a ladder-fill Error's `path` field — no boundary
/// crossing to accumulate (unlike eval.mbt's CPS @engine.Held), because resolving one scope's entities
/// already runs WITH that scope's own path known statically. Root (`path` omitted, default `[]`)
/// carries an empty path; a scope one command deep (`path: ["sub"]`, as `resolve_tree` would thread
/// for a `sub` command scope) carries that path unchanged.
test "resolve_scope: a ladder-fill Error's path is the caller-supplied scope path" {
  let num = ent("n", @builtins.number_type(), env_key=Some("N"))
  let sc : @engine.Scope = {
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
    @builtins.string_type(),
    is_config_file=true,
    default_value=Some(@engine.VStr("app.json")),
  )
  // Phase 2: a committed config path that fails to read.
  let sc1 : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path],
    constraints: [],
  }
  let never_reads = fn(_p : String) -> @engine.ConfigVal? { None }
  match
    resolve_scope_config(
      sc1,
      [cb("config", @engine.VStr("missing.json"), @engine.Cli)],
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
    @builtins.number_type(),
    config_seat=true,
    config_key=Some(["elsewhere", "port"]),
  )
  let sc2 : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [cfg_path, scalar_cfg],
    constraints: [],
  }
  let config = config_from_json(
    @json.parse("{\"elsewhere\":{\"port\":\"not-a-number\"}}"),
  )
  let provider = fn(_p : String) -> @engine.ConfigVal? { Some(config) }
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
/// A 0-token `update` effect binding (DR-077 §1) — mirrors `cb`'s @engine.Set-only shape but for the
/// old-dependent op; `value` is a placeholder (never read — resolve_entity's fold reads `old` off
/// the RUNNING state, not off this binding).
fn ceff(key : String, transform : String) -> @engine.Binding {
  {
    key,
    op: @engine.Update(transform, []),
    value: @engine.VBool(false),
    source: @engine.Cli,
    scope: [],
    link: 0,
    at_pos: None,
  }
}

///|
/// 保証: DR-077 §1 ledger 挙動 — 3 つの `update(increment)` effect が同じ key で連続すると、
/// resolve_entity の cli seat fold は old=default(0)→1→2→3 と連鎖計算する (`-vvv` の実機シナリオ)。
/// count の default:0 preset (installer.mbt ensure_entity, DR-077 §3) が fold の起点になることも
/// 同時に固定する。
test "resolve_scope: 3 chained update(increment) effects ledger old=0→1→2→3" {
  let verbose = ent(
    "verbose",
    @builtins.number_type(),
    default_value=Some(@engine.VNum(0.0)),
  )
  let sc : @engine.Scope = {
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
    Ok([mkb_pub("verbose", @engine.VNum(3.0), @engine.Cli)]),
  )
}

///|
/// 保証: DR-077 §1 — `update` effect が無指定の default (`e.default_value` が None) セルに対して
/// 発火すると、"old ?? default" (DR-077 §2) は default 不在時のフォールバック (bare zero) を使う。
/// count は常に default:0 を preset する (installer.mbt) ので実運用でこの分岐に落ちることは無いが、
/// 低レベル resolve_scope の契約としては独立に固定しておく (defensive のさらに一段防御)。
test "resolve_scope: update(increment) with no declared default falls back to a bare zero" {
  let n = ent("n", @builtins.number_type()) // no default_value
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  assert_eq(
    resolve_scope(sc, [ceff("n", "increment")], Map([])),
    Ok([mkb_pub("n", @engine.VNum(1.0), @engine.Cli)]),
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
    @builtins.number_type(),
    env_key=Some("VERBOSITY"),
    default_value=Some(@engine.VNum(0.0)),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [verbose],
    constraints: [],
  }
  // no cli fire at all → default seat (0).
  assert_eq(
    resolve_scope(sc, [], Map([])),
    Ok([mkb_pub("verbose", @engine.VNum(0.0), @engine.Default)]),
  )
  // env seat: a plain number set, never an increment (no `update` op anywhere in this path).
  assert_eq(
    resolve_scope(sc, [], Map::from_array([("VERBOSITY", "5")])),
    Ok([mkb_pub("verbose", @engine.VNum(5.0), @engine.Env)]),
  )
}

// ── DR-077 §1 / DR-102 §1 / issue 2026-07-09-filters-registry-foundation: final_filters が update 結果にも通る ──

///|
/// 保証 (issue の受け入れ条件そのもの — DR-040 「count の上限は final_filters (in_range 等) で書く」の
/// 実体化、DR-077 §1 「final_filters は update の結果にも通す」): count 要素 (update 効果で fold された
/// 値) に final_filters:["in_range:0:2"] を宣言すると、3 回連続 increment (-vvv 相当の ceff 3 個) の
/// 結果 3 が in_range の外に出て Err になる。2 回 (境界内) は通る。final_filters は set 経路・update
/// 経路を区別せず、resolve_entity が最終確定した値に対して一様に適用される (apply_entity_filters)。
test "resolve_scope: final_filters (in_range) rejects an update-folded count value over the limit" {
  let verbose = ent(
    "verbose",
    @builtins.number_type(),
    default_value=Some(@engine.VNum(0.0)),
    final_filters=["in_range:0:2"],
  )
  let sc : @engine.Scope = {
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
    Err(pe) => assert_eq(pe.reason, "too_large")
    Ok(_) => fail("expected Err (3 is out of range [0, 2])")
  }
  // 2 回 (境界内) は通る。
  let cli2 = [ceff("verbose", "increment"), ceff("verbose", "increment")]
  assert_eq(
    resolve_scope(sc, cli2, Map([])),
    Ok([mkb_pub("verbose", @engine.VNum(2.0), @engine.Cli)]),
  )
}

///|
/// 保証: final_filters は set 経路 (通常の value option) にも同じく効く — DR-077 §1 が強調するのは
/// 「update の結果にも」という追加であって、set 経路の final_filters 適用は元々の DR-009/040 契約
/// (update 導入前から成立すべき前提)。両経路が同じ apply_entity_filters を通ることを対で固定する。
test "resolve_scope: final_filters (in_range) also rejects a plain @engine.Set value over the limit" {
  let n = ent("n", @builtins.number_type(), final_filters=["in_range:0:100"])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  match
    resolve_scope(sc, [cb("n", @engine.VNum(101.0), @engine.Cli)], Map([])) {
    Err(pe) => assert_eq(pe.reason, "too_large")
    Ok(_) => fail("expected Err (101 is out of range [0, 100])")
  }
  assert_eq(
    resolve_scope(sc, [cb("n", @engine.VNum(50.0), @engine.Cli)], Map([])),
    Ok([cb("n", @engine.VNum(50.0), @engine.Cli)]),
  )
}

// ── accum (multiple) セルの CLI 座席 fold (issue 2026-07-09-accum-entity-filters-wiring) ───────

///|
/// 保証 (regression 再現、issue 2026-07-09-accum-entity-filters-wiring の "根" そのもの):
/// resolve_entity_raw の CLI 座席 fold は `e.accum is Some(_)` のとき同名 @engine.Binding を DR-015
/// last-wins に潰さない — accum 無し (scalar) の fold が last-wins のままであることとの対比を同じ
/// テストで固定する。修正前はこの assert が `Ok([cb("tags", @engine.VStr("b"), @engine.Cli)])` (最後の 1 個だけ) に
/// 潰れて RED だった。本テストは @engine.Set 効果のみを使うため、issue accum-fold-update-default-ops
/// (team-lead 裁定 2026-07-10) 以降 `resolve_entity_raw` の accum 分岐が default/unset の committed
/// 状態を追跡するようになった後も結果は変わらない (@engine.Set は常に `committed_now=true` で温存される) —
/// 「op 解釈しない」という記述は現在の実装を正確に表さないため削除し、「@engine.Set のみなら常に全件温存」
/// という不変条件として書き直した (op 解釈が入っても @engine.Set 効果自体の扱いは変わっていない、という
/// 意図)。
test "resolve_scope: an accum cell's CLI seat preserves EVERY same-name binding (not last-wins)" {
  let tags = ent("tags", @builtins.string_type(), accum=Some("append"))
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [tags],
    constraints: [],
  }
  let cli = [
    cb("tags", @engine.VStr("a"), @engine.Cli),
    cb("tags", @engine.VStr("b"), @engine.Cli),
  ]
  assert_eq(
    resolve_scope(sc, cli, Map([])),
    Ok([
      cb("tags", @engine.VStr("a"), @engine.Cli),
      cb("tags", @engine.VStr("b"), @engine.Cli),
    ]),
  )
}

///|
/// 保証 (対比、scalar は変わらず last-wins のまま): accum を持たない同名要素は DR-015 の
/// 「最後に committed した 1 個が勝つ」規約を保つ — accum 分岐がスカラー経路に漏れていないこと
/// を同じ fixture 形で固定する (multiple-parse/last-wins-scalar.json の resolve 版)。
test "resolve_scope: a scalar (no accum) cell's CLI seat still folds to last-wins" {
  let port = ent("port", @builtins.string_type())
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [port],
    constraints: [],
  }
  let cli = [
    cb("port", @engine.VStr("a"), @engine.Cli),
    cb("port", @engine.VStr("b"), @engine.Cli),
  ]
  assert_eq(
    resolve_scope(sc, cli, Map([])),
    Ok([cb("port", @engine.VStr("b"), @engine.Cli)]),
  )
}

///|
/// 保証: accum × value_filters(each、段5) — 全 piece が filter を通過すれば、resolve_entity 経由でも
/// 累積列がそのまま保たれる (multiple-parse/filters-each.json::all-pieces-pass-then-accumulate
/// の wbtest 版、conformance fixture 到達前に GREEN を固定する)。
test "resolve_scope: accum × value_filters(each) — all pieces passing preserves the accumulated list" {
  let ports = ent("ports", @builtins.number_type(), accum=Some("append"), value_filters=[
    "in_range:1:100",
  ])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ports],
    constraints: [],
  }
  let cli = [
    cb("ports", @engine.VNum(5.0), @engine.Cli),
    cb("ports", @engine.VNum(7.0), @engine.Cli),
  ]
  assert_eq(
    resolve_scope(sc, cli, Map([])),
    Ok([
      cb("ports", @engine.VNum(5.0), @engine.Cli),
      cb("ports", @engine.VNum(7.0), @engine.Cli),
    ]),
  )
}

///|
/// 保証 (issue 2026-07-09-accum-entity-filters-wiring 完了条件、CONFORMANCE §2/§3 の piece
/// 帰属規約): accum × value_filters(each) で 1 piece が reject すると全体が failure になり (「不正 piece
/// を静かに除外して残りを累積する」経路ではない)、その args_pos は reject した piece 自身が
/// 由来する CLI トークン位置 (`@engine.Binding.at_pos`、issue のスコープで追加) — ladder 呼び出し側が
/// 一律で渡す `at_pos` (env/config 由来の「トークン非帰属」フォールバック) には落ちない。
/// multiple-parse/filters-each.json::one-piece-rejects-whole-not-partial-accumulate の wbtest 版。
test "resolve_scope: accum × value_filters(each) — one piece rejecting fails whole at ITS OWN token position" {
  let ports = ent("ports", @builtins.number_type(), accum=Some("append"), value_filters=[
    "in_range:1:100",
  ])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ports],
    constraints: [],
  }
  // "5" は args トークン 1 由来、"500" は args トークン 3 由来 (`--ports 5 --ports 500` を模す)。
  // ladder 呼び出し側の at_pos=4 (仮に args.length() 相当) を渡しても、reject は 500 自身の
  // 位置 (3) に帰属することを固定する — env/config seat の args.length フォールバックとの対比。
  let cli = [
    cb("ports", @engine.VNum(5.0), @engine.Cli, at_pos=Some(1)),
    cb("ports", @engine.VNum(500.0), @engine.Cli, at_pos=Some(3)),
  ]
  match resolve_scope(sc, cli, Map([]), at_pos=4) {
    Err(pe) => {
      assert_eq(pe.kind, @engine.KFilter)
      assert_eq(pe.args_pos, 3)
      assert_eq(pe.reason, "too_large")
    }
    Ok(_) => fail("expected Err (500 is out of range [1, 100])")
  }
}

///|
/// 保証 (issue 2026-07-09-accum-fold-update-default-ops、team-lead 裁定 2026-07-10 — 前サイクル
/// (issue accum-filters-non-set-op-semantics) からの契約変更を明示する): このテストが検証する
/// 「何を」は変わっていない (@engine.Unset の placeholder 値 (`mk_eff` の doc comment: "The operand is a
/// placeholder — these ops carry no operand", ここでは @engine.VBool(false)) が number 用 `in_range`
/// value_filters に渡って型不一致で誤 reject しないこと) — この spec 面の正本は conformance fixture
/// `multiple-parse/filters-cell-ops.json` (unset-after-set-resets-to-empty-without-filter ケース、
/// green 維持確認済み) であり、本 wbtest はそれが conformance fixture に到達する前に GREEN を固定
/// する下働き。**変わったのは「どう検証するか」**: 旧契約 (accum-filters-non-set-op-semantics サイクル)
/// では `resolve_entity_raw` の accum 分岐は CLI 座席の op を一切解釈せず同名 @engine.Binding を生のまま列で
/// 温存していたため、本テストは「`resolve_scope` の戻り値が `[@engine.Set(5), @engine.Unset]` の2件そのまま」を
/// 直接 assert していた。今サイクルの裁定で `resolve_entity_raw` の accum 分岐は op を解釈するように
/// なった (default/unset の committed 状態を追跡し、CLI 座席全体が uncommitted なら下位ラダーへ
/// フォールスルーする、Q5) — `ports` は env/config/宣言 default を一切持たないため、@engine.Unset
/// (committed=false) 単独発火は CLI 座席全体を下位ラダーへ開放し、下位値源も無いので最終的に
/// `Ok([])` に確定する (`unset-env-fallback.json` の下位値源ありケースとの対比: 本テストは下位値源
/// なしの基準形、対になる下位値源ありケースは次のテストで押さえる)。@engine.Unset の placeholder が
/// `apply_entity_filters` の filter chain (in_range:1:100) を通っていたら型不一致で `Err` になるはず
/// なので、`Ok([])` (Err でないこと) 自体が「placeholder が filter を経由していない」証拠になる —
/// この検証ロジック自体 (Err にならないことで filter 非適用を証明する) は旧契約でも同じだった。
test "resolve_scope: accum × value_filters(each) — @engine.Unset placeholder is exempt from filters (only @engine.Set carries a real value)" {
  let ports = ent("ports", @builtins.number_type(), accum=Some("append"), value_filters=[
    "in_range:1:100",
  ])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ports],
    constraints: [],
  }
  // `--ports 5 --reset-ports` を模す: @engine.Set(5) の後に @engine.Unset (placeholder @engine.VBool(false)、値なし) が続く。
  let cli = [
    cb("ports", @engine.VNum(5.0), @engine.Cli, at_pos=Some(1)),
    {
      key: "ports",
      op: @engine.Unset,
      value: @engine.VBool(false), // placeholder — unset carries no operand
      source: @engine.Cli,
      scope: [],
      link: 0,
      at_pos: None,
    },
  ]
  match resolve_scope(sc, cli, Map([])) {
    Ok(bs) =>
      // @engine.Unset が CLI 座席をラダーへ開放し、下位値源 (env/config/宣言default) も無いので `[]` に確定
      // する — @engine.Set(5) は @engine.Unset で累積列がクリアされた後の座席には残らない (build_result 側の
      // ACCUMULATE fold が @engine.Set→@engine.Unset を「クリア点」として畳むのと同じ規約、`resolve_scope` 単体では
      // その畳みの手前の座席解決だけを見ている)。
      assert_eq(bs.length(), 0)
    Err(_) =>
      fail(
        "expected Ok([]) — @engine.Unset's placeholder must not run through e.value_filters (in_range would wrongly reject a non-number placeholder if it did)",
      )
  }
}

///|
/// 保証 (上記テストの対、下位値源ありケース — fall-through の両面を unit 層でも押さえる): `ports`
/// が env 席を持つ場合、@engine.Unset (committed=false) は CLI 座席を下位ラダーへ開放し、env が供給する
/// 値がそのまま最終値になる (`unset-env-fallback.json` の `unset-opens-ladder-to-env-separator-list`
/// と同型、本テストは separator 無しの単純形)。env から供給される値は `resolve_entity_raw` の
/// 独立した座席解決 (env seat、`@engine.config_to_value`/`env_value` の pieceProcessor) を通るため
/// value_filters も正しく適用される — @engine.Unset で CLI 座席の value_filters チェックを完全に迂回した
/// 上記テストとの対比 (下位値源の有無だけで fall-through の着地点が変わることを固定する)。
test "resolve_scope: accum × @engine.Unset opens the ladder to env when a lower source exists" {
  let ports = ent(
    "ports",
    @builtins.number_type(),
    accum=Some("append"),
    env_key=Some("PORTS"),
    value_filters=["in_range:1:100"],
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ports],
    constraints: [],
  }
  // `--reset-ports` のみ、env PORTS="42": CLI 座席は @engine.Unset 1 個のみ (committed=false) で下位の env
  // 席まで落ち、"42" が value_filters (in_range:1:100) を通って供給される。
  let cli : Array[@engine.Binding] = [
    {
      key: "ports",
      op: @engine.Unset,
      value: @engine.VBool(false),
      source: @engine.Cli,
      scope: [],
      link: 0,
      at_pos: None,
    },
  ]
  match resolve_scope(sc, cli, Map([("PORTS", "42")])) {
    Ok(bs) => {
      assert_eq(bs.length(), 1)
      assert_eq(bs[0].value, @engine.VNum(42.0))
      assert_eq(bs[0].source, @engine.Env)
    }
    Err(_) =>
      fail(
        "expected Ok — env supplies 42 after @engine.Unset opens the ladder",
      )
  }
}

///|
/// 保証 (対、上記テストの逆順): `--reset-ports --ports 7` を模す — @engine.Unset が先に発火しても、後続の
/// @engine.Set(7) には filter が正常に効き続ける (「@engine.Unset が filter chain 自体を壊す」ことがない)。
/// @engine.Set が filter を reject する場合も同様に機能することを固定 (@engine.Unset 混在下でも @engine.Set 側の
/// reject 輪郭 (既存の "one piece rejecting fails whole" テスト) が保たれることの対比)。
/// multiple-parse/filters-cell-ops.json::unset-then-set-reaccumulates-with-filter-intact の wbtest 版。
test "resolve_scope: accum × value_filters(each) — @engine.Unset does not disable filters for a LATER @engine.Set piece" {
  let ports = ent("ports", @builtins.number_type(), accum=Some("append"), value_filters=[
    "in_range:1:100",
  ])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [ports],
    constraints: [],
  }
  // 通過ケース: @engine.Unset の後の @engine.Set(7) は in_range:1:100 を通過する。
  let cli_pass : Array[@engine.Binding] = [
    {
      key: "ports",
      op: @engine.Unset,
      value: @engine.VBool(false),
      source: @engine.Cli,
      scope: [],
      link: 0,
      at_pos: None,
    },
    cb("ports", @engine.VNum(7.0), @engine.Cli, at_pos=Some(2)),
  ]
  match resolve_scope(sc, cli_pass, Map([])) {
    Ok(bs) => {
      assert_eq(bs.length(), 2)
      assert_eq(bs[0].op, @engine.Unset)
      assert_eq(bs[1].op, @engine.Set)
      assert_eq(bs[1].value, @engine.VNum(7.0))
    }
    Err(_) =>
      fail(
        "expected Ok — @engine.Set(7) is within range and @engine.Unset must not block it",
      )
  }
  // reject ケース: @engine.Unset の後の @engine.Set(500) は in_range:1:100 を reject する (@engine.Unset 混在でも @engine.Set の
  // filter 適用が生きていることの直接証拠)。
  let cli_reject : Array[@engine.Binding] = [
    {
      key: "ports",
      op: @engine.Unset,
      value: @engine.VBool(false),
      source: @engine.Cli,
      scope: [],
      link: 0,
      at_pos: None,
    },
    cb("ports", @engine.VNum(500.0), @engine.Cli, at_pos=Some(2)),
  ]
  match resolve_scope(sc, cli_reject, Map([])) {
    Err(pe) => {
      assert_eq(pe.kind, @engine.KFilter)
      assert_eq(pe.reason, "too_large")
    }
    Ok(_) =>
      fail(
        "expected Err — 500 is out of range [1, 100], @engine.Unset must not exempt it",
      )
  }
}

///|
/// 保証 (issue 2026-07-09-post-filter-error-attribution): `value_filters`/`final_filters` reject の
/// Error は `kind: @engine.KFilter` を持つ (DR-053 §2 の `parse` | `filter` | `constraint` 3 分類 — 値が
/// パースできなかった `@engine.KParse` とは別カテゴリ、既にパース済みの値を validate/transform した結果の
/// reject なので `filter` 分類に属する)。`args_pos` は呼び出し側が渡した最終位置をそのまま持つ
/// (env/config seat のエラーと同じ規約 — `ladder_err`/`filter_err` の doc comment 参照、値がどの
/// token でも読まれていないので位置は「args 走査が完了した地点」= 呼び出し側の `toks.length()`
/// 相当。本テストでは呼び出し側が明示的に `at_pos=3` を渡し、それがそのまま素通しされることを
/// 固定する — 実際の conformance harness 側の配線 (`dc.args.length()`) は
/// json_conformance_wbtest.mbt の `do_resolve_pe`/`resolve_tree` が担う)。
test "resolve_scope: a value_filters/final_filters reject carries kind=@engine.KFilter and the caller's at_pos" {
  let n = ent("n", @builtins.number_type(), final_filters=["in_range:0:100"])
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  match
    resolve_scope(
      sc,
      [cb("n", @engine.VNum(101.0), @engine.Cli)],
      Map([]),
      at_pos=3,
    ) {
    Err(pe) => {
      assert_eq(pe.kind, @engine.KFilter)
      assert_eq(pe.args_pos, 3)
      assert_eq(pe.reason, "too_large")
    }
    Ok(_) => fail("expected Err (101 is out of range [0, 100])")
  }
}

///|
/// 保証 (codex 指摘 2/3 の対、issue 2026-07-09-constraint-path-filtering-gap 節目レビュー、reason
/// は codex 指摘 2026-07-12 節目レビューで更新):
/// `:update:increment:5` (0-arg 組み込み `increment` への余分な args) は definition-time では
/// 通る (installer_wbtest.mbt の対テスト参照 — registry に存在し signature も Transform なので
/// gate を通過する) が、**RUNTIME** で `apply_transform` が `(d.run)(old, args)` を呼んだ時点で
/// `filter_increment` 自身が `args.length() != 0` を拒否し (`filters.mbt`)、`kind: @engine.KFilter` の
/// Error になることを固定する (codex 指摘 3: この Error の kind は `ladder_err` (@engine.KParse) から
/// `filter_err` (@engine.KFilter) へ置換済み — 値のパース失敗ではなく filter/transform 語彙の拒否なので
/// DR-053 §2 の分類上こちらが正しい)。`reason` は `filter_rejected` — `increment` は DR-095 §3
/// で `Transform` (失敗しない) と分類され `reasons: []`、かつこの arity 拒否は type-contract
/// violation (filter-definition bug) であって DR-095 が正しい定義の failure mode として宣言する
/// 対象ではない。「apply_transform が emit する reason は DR-095 の宣言集合の部分集合であるべき」
/// という subset invariant を守るため、宣言外の防御的失敗は全て DR-095 §5 の宣言済み fallback
/// `filter_rejected` に畳む (旧 `update_transform_type_mismatch` は spec 全体 grep 0 hit の
/// 実装発明だったため廃止)。
test "resolve_scope: an update transform's own arity rejection surfaces at runtime as kind=@engine.KFilter, reason=filter_rejected (DR-095 subset invariant — no declared reason for this defensive path)" {
  let n = ent(
    "n",
    @builtins.number_type(),
    default_value=Some(@engine.VNum(0.0)),
  )
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [n],
    constraints: [],
  }
  let cli : Array[@engine.Binding] = [
    {
      key: "n",
      op: @engine.Update("increment", ["5"]),
      value: @engine.VBool(false),
      source: @engine.Cli,
      scope: [],
      link: 0,
      at_pos: None,
    },
  ]
  match resolve_scope(sc, cli, Map([])) {
    Err(pe) => {
      assert_eq(pe.kind, @engine.KFilter)
      assert_eq(pe.reason, "filter_rejected")
    }
    Ok(_) => fail("expected Err (increment takes no args)")
  }
}

// ── DR-080 merge accumulator: 核アルゴリズムの先行 pin (§4 の 14 canonical 例) ──────────

///|
/// DR-080 §4 の canonical 表を検証する共通ヘルパー: 「マーカーを含まない発火」なら
/// `merge_pieces_has_no_marker` が true になり piece 列そのものが結果になる (§3 冒頭の上書き)、
/// マーカーを含むなら `merge_pieces_with_implicit_splice` (暗黙先頭 `@` 補完) を経て
/// `eval_merge_pieces` (old 合成) に渡す — 呼び出し側 (このヘルパー) が「上書き vs merge モード」
/// の分岐を担う想定は resolve_entity_raw の accum 分岐にそのまま持ち込める形。
fn merge_fire(
  pieces : Array[MergeMark],
  old : Array[@engine.Value],
) -> Array[@engine.Value] {
  if merge_pieces_has_no_marker(pieces) {
    let out : Array[@engine.Value] = []
    for p in pieces {
      match p {
        MAdd(v) => out.push(v)
        _ =>
          abort(
            "unreachable: merge_pieces_has_no_marker already filtered non-MAdd",
          )
      }
    }
    out
  } else {
    eval_merge_pieces(merge_pieces_with_implicit_splice(pieces), old)
  }
}

///|
fn vs(s : String) -> @engine.Value {
  @engine.VStr(s)
}

///|
/// 保証: DR-080 §4 canonical 表 (old = 直前発火の `[a,a,b,a,c]`) の1行目「マーカーなし = 上書き」。
/// `-f a,a,b,a,c` 単独発火は merge モードに入らず、piece 列そのものが結果になる。
test "DR-080 merge: no-marker fire overwrites the cell (canonical row 1)" {
  let pieces = [
    MAdd(vs("a")),
    MAdd(vs("a")),
    MAdd(vs("b")),
    MAdd(vs("a")),
    MAdd(vs("c")),
  ]
  assert_eq(merge_fire(pieces, []), [
    vs("a"),
    vs("a"),
    vs("b"),
    vs("a"),
    vs("c"),
  ])
}

///|
/// 保証 (canonical 表 2行目): 明示 `@` 単独発火は old をそのまま splice する (恒等)。
test "DR-080 merge: explicit @ alone splices old verbatim (canonical row 2)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MSplice], old), old)
}

///|
/// 保証 (canonical 表 3行目): remove のみの発火は暗黙先頭 `@` + 後方 remove として評価される。
test "DR-080 merge: remove-only fire is implicit-@ + trailing remove (canonical row 3)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a"))], old), [vs("b"), vs("c")])
}

///|
/// 保証 (canonical 表 4行目): 前置 remove が両方の `@` の splice 内容に効く — `seen_removes` が
/// 発火全体を通じて蓄積されることの直接証拠 (2 つの @ が同じフィルタ結果になる)。
test "DR-080 merge: a leading remove filters every subsequent splice (canonical row 4)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MSplice, MSplice], old), [
    vs("b"),
    vs("c"),
    vs("b"),
    vs("c"),
  ])
}

///|
/// 保証 (canonical 表 5行目): マーカーなし発火は何度でも単純上書き (old は完全に無視される)。
test "DR-080 merge: a second no-marker fire overwrites again, ignoring old (canonical row 5)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  let pieces = [MAdd(vs("d"))]
  assert_eq(merge_fire(pieces, old), [vs("d")])
}

///|
/// 保証 (canonical 表 6行目): `-a,@` (remove の後に明示 @) — remove 後の @ splice はフィルタ済み。
test "DR-080 merge: remove then explicit @ (canonical row 6)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MSplice], old), [vs("b"), vs("c")])
}

///|
/// 保証 (canonical 表 7行目): remove → @ → add — remove 後に追加された add は削除フィルタを
/// 受けない (「remove はそれ以後の add には効かない」の直接証拠)。
test "DR-080 merge: an add AFTER remove survives untouched (canonical row 7)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MSplice, MAdd(vs("a"))], old), [
    vs("b"),
    vs("c"),
    vs("a"),
  ])
}

///|
/// 保証 (canonical 表 8行目): remove → @ → add → remove — 後置 remove は「その時点までの
/// work_list」(add で加わった要素も含む) に効く。
test "DR-080 merge: a trailing remove strips a previously-surviving add (canonical row 8)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(
    merge_fire(
      [MRemove(vs("a")), MSplice, MAdd(vs("a")), MRemove(vs("a"))],
      old,
    ),
    [vs("b"), vs("c")],
  )
}

///|
/// 保証 (canonical 表 9行目): `-a,d` — 暗黙先頭 @ の後に remove、その後 add。
test "DR-080 merge: implicit @ + remove + add (canonical row 9)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MRemove(vs("a")), MAdd(vs("d"))], old), [
    vs("b"),
    vs("c"),
    vs("d"),
  ])
}

///|
/// 保証 (canonical 表 10行目): `@,-a,@` — remove が「それより前にある @」にも効く (splice
/// フィルタは remove の位置に関わらず、その @ の評価時点で `seen_removes` に入っているかで決まる)。
/// `-a,@,@` (canonical 表 4行目) と同値になることを固定する。
test "DR-080 merge: @,-a,@ equals -a,@,@ (canonical row 10)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MSplice, MRemove(vs("a")), MSplice], old), [
    vs("b"),
    vs("c"),
    vs("b"),
    vs("c"),
  ])
}

///|
/// 保証 (canonical 表 11行目): `@,-a,a` — `-a,@,a` (canonical 表 7行目) と同値。
test "DR-080 merge: @,-a,a equals -a,@,a (canonical row 11)" {
  let old = [vs("a"), vs("a"), vs("b"), vs("a"), vs("c")]
  assert_eq(merge_fire([MSplice, MRemove(vs("a")), MAdd(vs("a"))], old), [
    vs("b"),
    vs("c"),
    vs("a"),
  ])
}

///|
/// 保証 (canonical 表 12行目): 初回発火 (old = []) の `a,-a` — 暗黙 @ で old=[] を展開後、
/// add した "a" 自身を後続 remove が削除する。
test "DR-080 merge: first fire (old=[]) a,-a nets to empty (canonical row 12)" {
  assert_eq(merge_fire([MAdd(vs("a")), MRemove(vs("a"))], []), [])
}

///|
/// 保証 (canonical 表 13行目): 初回発火 (old = []) の `-a,a` — remove が先でも、その後の add は
/// 生き残る (remove はそれ以後の add に効かない)。
test "DR-080 merge: first fire (old=[]) -a,a keeps the trailing add (canonical row 13)" {
  assert_eq(merge_fire([MRemove(vs("a")), MAdd(vs("a"))], []), [vs("a")])
}

///|
/// 保証 (canonical 表 14行目、DR-080 §2 escape 規約): `+-a,+@,++` は piece 全体が `+` + (`-`|`@`|`+`)
/// で始まるので escape (先頭 `+` を 1 個剥がした literal) — マーカーを一切含まないので cell 上書き
/// になり、剥がした literal そのもの `["-a","@","+"]` が結果になる。`@engine.classify_merge_piece` の判定を
/// 直接検証する (eval 層のマーカー判定関数、`eval_merge_pieces` の入力である `MergeMark` 列を作る
/// 前段)。
test "DR-080 merge: +-a,+@,++ escapes to literal -a,@,+ (canonical row 14)" {
  assert_eq(@engine.classify_merge_piece("+-a"), PkAdd("-a"))
  assert_eq(@engine.classify_merge_piece("+@"), PkAdd("@"))
  assert_eq(@engine.classify_merge_piece("++"), PkAdd("+"))
  // 3 piece とも PkAdd (escape 後は marker を持たない) なので、cell 上書き経路に落ちる。
  let marks = [
    @engine.classify_merge_piece("+-a"),
    @engine.classify_merge_piece("+@"),
    @engine.classify_merge_piece("++"),
  ]
  for m in marks {
    match m {
      PkAdd(_) => ()
      _ => fail("expected all-PkAdd after escape, got a marker")
    }
  }
}

///|
/// 保証 (対極、DR-080 §2 「部分一致はマーカーにならない」/「`+` 単独は literal」): `a@b` は `@` を
/// 含むが piece 全体一致ではないので add。`+` 単独は 2 文字目が存在しないので escape にならず
/// literal `"+"`。`-` 単独は remove("") (operand が空文字列)。
test "DR-080 merge: partial matches and bare +/- are NOT markers (対極)" {
  assert_eq(@engine.classify_merge_piece("a@b"), PkAdd("a@b"))
  assert_eq(@engine.classify_merge_piece("+"), PkAdd("+"))
  assert_eq(@engine.classify_merge_piece("-"), PkRemove(""))
  assert_eq(@engine.classify_merge_piece("+x"), PkAdd("+x")) // +x (x は -/@/+ 以外) は literal のまま
}

///|
/// A @engine.Binding literal carrying a non-@engine.Set op (`resolve_wbtest.mbt`'s own `cb` always builds `@engine.Set` —
/// this helper is for hand-building the `@engine.Remove`/`@engine.Splice` piece bindings `resolve_merge_accum`'s
/// grouping loop needs, mirroring `sep_binds`'s own construction shape).
fn merge_piece_bind(
  key : String,
  op : @engine.EffectOp,
  value : @engine.Value,
  pos : Int,
) -> @engine.Binding {
  { key, op, value, source: @engine.Cli, scope: [], link: 0, at_pos: Some(pos) }
}

///|
/// 保証: `resolve_merge_accum` (resolve.mbt) が同一 at_pos の CLI piece 列を「1 発火」として正しく
/// グループ化し、DR-080 §3 の評価規則を `resolve_scope` 経由の CLI 席折込みとして正しく適用する。
/// `eval_merge_pieces` 自体の正しさは `merge_fire` 系の 15 wbtest (上記) が固定済みだが、それらは
/// resolve.mbt の CLI 席配線 (グルーピング境界 / 「マーカーなし発火=置換、累積ではない」/ old の
/// 引き渡し) を一切通らない — この wiring 自体の正しさは fixture (multiple-parse/merge-*.json、
/// conformance harness 経由) でしか検証されておらず、resolve.mbt 単体では未検証だった。
///
/// ケース1 (merge-basic.json::second-no-marker-fire-overwrites-again の cli 席を手組み): マーカー
/// を含まない 2 回目の発火が 1 回目の 5 要素を消して単独の結果になる (append 累積とは異なる、
/// DR-080 §3 冒頭の overwrite 規則)。
test "DR-080 resolve wiring: second no-marker fire REPLACES (not appends) the first, via resolve_scope" {
  let fields = ent("fields", @builtins.string_type(), accum=Some("merge"))
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [fields],
    constraints: [],
  }
  let cli : Array[@engine.Binding] = [
    cb("fields", @engine.VStr("a"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("a"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("b"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("a"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("c"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("d"), @engine.Cli, at_pos=Some(3)),
  ]
  match resolve_scope(sc, cli, Map([])) {
    Ok(bs) => {
      let vals : Array[@engine.Value] = []
      for b in bs {
        vals.push(b.value)
      }
      assert_eq(vals, [@engine.VStr("d")])
    }
    Err(_) => fail("expected Ok")
  }
}

///|
/// ケース2 (merge-splice-remove.json::implicit-at-then-remove-only の cli 席を手組み): 1 回目は
/// マーカーなし発火で `old` が確定 (`[a,a,b,a,c]`)、2 回目は同一 at_pos の `@engine.Remove(a)` 単独 piece —
/// 暗黙先頭 `@` が補われ old を splice した後 remove が効き `[b,c]` になる。`resolve_merge_accum`
/// が (a) @engine.Remove piece を正しく GFire にグループ化し、(b) 前の発火の結果を次発火の `old` として
/// 引き渡すことを固定する (どちらも `eval_merge_pieces` 単体テストでは検証できない、resolve.mbt
/// 固有の配線)。
test "DR-080 resolve wiring: a lone @engine.Remove piece merges against the PRIOR firing's old, via resolve_scope" {
  let fields = ent("fields", @builtins.string_type(), accum=Some("merge"))
  let sc : @engine.Scope = {
    greedy: [],
    positional: [],
    entities: [fields],
    constraints: [],
  }
  let cli : Array[@engine.Binding] = [
    cb("fields", @engine.VStr("a"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("a"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("b"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("a"), @engine.Cli, at_pos=Some(1)),
    cb("fields", @engine.VStr("c"), @engine.Cli, at_pos=Some(1)),
    merge_piece_bind("fields", @engine.Remove, @engine.VStr("a"), 3),
  ]
  match resolve_scope(sc, cli, Map([])) {
    Ok(bs) => {
      let vals : Array[@engine.Value] = []
      for b in bs {
        vals.push(b.value)
      }
      assert_eq(vals, [@engine.VStr("b"), @engine.VStr("c")])
    }
    Err(_) => fail("expected Ok")
  }
}

// ── DR-091 §2: kv_map accumulator fold (build_result) ────────────────────────

///|
/// Guarantees: a `kv_map` accum cell folds 2 fires (each already `=`-shaped, `KvArg`'s consume-
/// time gate guarantees this — `split_first_eq` never sees a piece without `=`) into an RObj, one
/// entry per DISTINCT key, in first-fire order — DR-091 §2's "piece `k=v` を最初の `=` で分割し...
/// Map (結果は kv オブジェクト) に畳む" core case, no repeated key involved yet (paired with the
/// last-wins case below).
test "build_result: kv_map folds 2 fires into an RObj (distinct keys)" {
  let binds : Array[@engine.Binding] = [
    cb("assigns", @engine.VStr("A=1"), @engine.Cli),
    cb("assigns", @engine.VStr("B=2"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "assigns",
      collector: None,
      accum_filters: [],
      accum: "kv_map",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([
      (
        "assigns",
        RObj([
          ("A", RScalar(@engine.VStr("1"))),
          ("B", RScalar(@engine.VStr("2"))),
        ]),
      ),
    ]),
  )
}

///|
/// Guarantees (DR-015 あと勝ち, DR-091 §2 "重複キーは last-wins"): re-firing the SAME key
/// overwrites its value but does NOT move its position — mirrors `Object.fromEntries` (a later
/// assignment updates in place, JS's `{a:1,b:2,a:3}` fromEntries stays `{a:3,b:2}`, `a` keeps its
/// FIRST-SEEN slot). 3 fires: A, B, A again — the fold must end up with `A` STILL FIRST (value 3),
/// `B` second (value 2), not `[B, A]`.
test "build_result: kv_map re-firing a key is last-wins on VALUE, first-seen on POSITION" {
  let binds : Array[@engine.Binding] = [
    cb("assigns", @engine.VStr("A=1"), @engine.Cli),
    cb("assigns", @engine.VStr("B=2"), @engine.Cli),
    cb("assigns", @engine.VStr("A=3"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "assigns",
      collector: None,
      accum_filters: [],
      accum: "kv_map",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([
      (
        "assigns",
        RObj([
          ("A", RScalar(@engine.VStr("3"))),
          ("B", RScalar(@engine.VStr("2"))),
        ]),
      ),
    ]),
  )
}

///|
/// Guarantees (DR-091 §2 "最初の `=` で分割"): a piece whose VALUE itself contains further `=`
/// characters splits ONLY at the first one — `"KEY=a=b"` → `("KEY", "a=b")`, never `("KEY", "a")`
/// with `=b` silently dropped or re-joined some other way.
test "build_result: kv_map splits a piece at the FIRST '=' only (value may itself contain '=')" {
  let binds : Array[@engine.Binding] = [
    cb("assigns", @engine.VStr("KEY=a=b"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "assigns",
      collector: None,
      accum_filters: [],
      accum: "kv_map",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([("assigns", RObj([("KEY", RScalar(@engine.VStr("a=b")))]))]),
  )
}

///|
/// 対極 (regression guard): a plain "append" accum cell is UNAFFECTED by the kv_map branch added
/// to `build_result`'s ACCUMULATE match — `accum_kind_here(...) == Some("kv_map")` is a targeted
/// dispatch, not a change to the default fold path. Same shape as this file's very first test
/// ("build_result folds scalar last-wins, accumulate array...") but written standalone here so
/// this file's kv_map section carries its own non-collision witness.
test "build_result: kv_map's RObj branch does not affect a sibling 'append' accum cell (対極)" {
  let binds : Array[@engine.Binding] = [
    cb("tags", @engine.VStr("a"), @engine.Cli),
    cb("tags", @engine.VStr("b"), @engine.Cli),
  ]
  let cells : Array[AccumCell] = [
    {
      path: [],
      name: "tags",
      collector: None,
      accum_filters: [],
      accum: "append",
      flatten: false,
      is_multiple_decl: false,
    },
  ]
  assert_eq(
    build_result(binds, cells, [], []),
    RObj([
      ("tags", RArr([RScalar(@engine.VStr("a")), RScalar(@engine.VStr("b"))])),
    ]),
  )
}

// ── DR-092: inf / 非整数 float の JSON serialize 規約 (@engine.value_str = "the resolve layer owns the
// result-object rendering") ─────────────────────────────────────────────────────

///|
/// 保証 (DR-092 §2「canonical 語彙は "Infinity"/"-Infinity" (protobuf3 準拠スペル)、先頭 + 無し」):
/// `@engine.value_str` の `@engine.VNum(d)` 分岐 (`d.to_int()` で整数値判定 → 非整数/範囲外なら `d.to_string()` に
/// フォールバック) は inf に対して自明に真 — inf は `Double::to_int()` が Int32 範囲外として
/// saturate する (`~/.moon/lib/core/builtin/double_to_int.mbt`) ため `i.to_double() != d` となり
/// 必ずフォールバック分岐へ落ち、MoonBit stdlib の `Double::to_string` (Ryu 実装、
/// `double_ryu_nonjs.mbt` の `copy_special_str` が exponent bit 全 1 かつ mantissa 0 を inf と
/// 判定して "Infinity"/"-Infinity" を返す、先頭 `+` は付かない) がそのまま DR-092 §2 の canonical
/// 語彙を生成する。**production コード変更なしで既に規約を満たしている**ことをここで固定する
/// (issue scope-config-object-gap 後続サイクル、DR-092 実装調査 2026-07-11 の実機確認結果)。
test "@engine.value_str: inf/-inf render as \"Infinity\"/\"-Infinity\" with no code change (DR-092 §2)" {
  let inf : Double = 1.0 / 0.0
  let ninf : Double = -1.0 / 0.0
  assert_eq(@engine.value_str(@engine.VNum(inf)), "Infinity")
  assert_eq(@engine.value_str(@engine.VNum(ninf)), "-Infinity")
}

///|
/// 保証 (DR-092 §4「非整数 float の canonical serialize = shortest round-trip」): `0.1 + 0.2` は
/// binary64 では厳密に 0.3 にならない (古典的な浮動小数点の実演) — shortest round-trip 実装
/// (Ryu/Grisu 系) はこの誤差を正直に最短表現で表す (`"0.30000000000000004"`)。ナイーブな固定桁
/// フォーマット (`%.17g` や `%.6f` 等) はこの丸めを再現しないため、この値は「shortest round-trip
/// を実際に使っているか」の判別に有効な probe (DR-092 の実装調査で main から明示された確認事項)。
test "@engine.value_str: a non-integer float renders via shortest round-trip, not naive fixed-precision (DR-092 §4)" {
  assert_eq(@engine.value_str(@engine.VNum(0.1 + 0.2)), "0.30000000000000004")
  assert_eq(@engine.value_str(@engine.VNum(3.14159)), "3.14159")
}

///|
/// 対極 (DR-092 §4「整数値の float は DR-050 §4 の最短表現規則 (1.0 → "1") と同じ扱い」):
/// 非整数 float との対比を同テストで固定 — `@engine.value_str` の `i.to_double() == d` 分岐が整数値
/// float を小数点なしの整数表記に倒す既存挙動 (DR-050 §4) は本 DR で変更しない。
test "@engine.value_str: an integer-valued float keeps DR-050 §4's no-decimal-point rendering (対極, DR-092 §4)" {
  assert_eq(@engine.value_str(@engine.VNum(3.0)), "3")
  assert_eq(@engine.value_str(@engine.VNum(-0.0)), "0") // -0.0 は int 0 と等価判定 (DR-050 §4 の既存挙動、inf 非該当)
}

///|
/// 保証 (DR-092 §3「適用範囲は一律 — result / effects / config 起因の値、いずれも同じ表現」):
/// `build_result` (RVal 構築、report の値位置の 1 つ = result) は inf 値を型・値ともに一切変更
/// せず通す — `@engine.VNum` の Eq 比較は IEEE754 の `Infinity == Infinity` (true, NaN と違い比較可能)
/// に従うため、`assert_eq` がそのまま構造等価を検証できる。value 位置の serialize 規約
/// (`@engine.value_str`) とは独立に、値そのものが report の "result" 経路で失われない (clamp/丸め等が
/// 起きない) ことを固定する。
test "build_result: an inf-valued cell passes through the result builder unchanged (DR-092 §3 result 位置)" {
  let inf : Double = 1.0 / 0.0
  let binds : Array[@engine.Binding] = [
    cb("threshold", @engine.VNum(inf), @engine.Cli),
  ]
  assert_eq(
    build_result(binds, [], [], []),
    RObj([("threshold", RScalar(@engine.VNum(inf)))]),
  )
}
