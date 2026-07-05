// phase22_wbtest.mbt — 第 12 弾: 結果キー軸の一本化 (DR-052 export_key)。export (bool) は廃止、
// export_key: string | null の 1 フィールド。未指定 = name 由来 / string = キー名上書き / null (or
// "" → null 正規化) = 結果キー軸なし = nameless 同化の透過 (値の伝搬は止まらない、キーが無くなるだけ)。
// lexical スコープ・id (ref/link) は export_key と直交で不変。露出キー衝突は実行時 ambiguous (§15.5)。

///|
fn p22_order() -> Array[Installer] {
  [
    LongInst,
    ShortInst,
    EnvInst,
    DdInst,
    CommandInst,
    GlobalInst,
    InheritInst,
    RepeatInst,
    MultipleInst,
    ConfigInst,
  ]
}

// ── 1. キー上書き: export_key: "alias" ─────────────────────────────────────────

///|
test "DR-052 §1: an export_key string overrides the result key (the name key does not appear)" {
  // `port` exposes under "alias", not "port". export_key is the result-key axis; the name provides
  // the key only by default (DR-046). The parse / cell is unchanged — only the result key.
  let def = def_([opt("port", TNum, long=["port"], export=EkKey("alias"))], [])
  let sc = build_or_fail(def, p22_order())
  let ekm = build_export_map(def)
  inspect(export_result_str(sc, ekm, ["--port", "80"]), content="{alias:80}")
}

// ── 2. 透過 (kv 文脈): export_key: null → 値ごと消える ───────────────────────────

///|
test "DR-052 §2: export_key null on an option is 透過 — the value disappears from the kv result" {
  // `verbose` has null result-key axis: in a kv (options) context it does not appear at all (「kv には
  // 結果キー持ちだけ現れる」). `keep` (a normal key) appears. verbose still fires (the value propagates
  // to its cell / any link); only the result KEY is gone (DR-052: 「export しない」ではなく「名前が無い」).
  let def = def_(
    [
      opt("verbose", TFlag, long=["verbose"], export=EkNull),
      opt("keep", TFlag, long=["keep"]),
    ],
    [],
  )
  let sc = build_or_fail(def, p22_order())
  let ekm = build_export_map(def)
  inspect(
    export_result_str(sc, ekm, ["--verbose", "--keep"]),
    content="{keep:true}",
  )
}

// ── 3. 透過 (seq/array 文脈): 値は親の配列要素として残る (形は変わらない) ───────────

///|
test "DR-052 §2: export_key null in an array element KEEPS the value as a bare element (shape unchanged)" {
  // An IdxRepeat whose head is a named element `k`. Without export_key each array element is {k:v};
  // with export_key null on `k` the key drops and each element is the BARE value — the array shape
  // [.,.,.] is preserved (seq-context 透過 keeps the value, unlike the kv-context 消滅). This is why a
  // from_entries 2-要素 seq downstream is not broken by 透過 (the array does not lose elements).
  let sc : Scope = {
    greedy: [],
    positional: [IdxRepeat("xs", StrArg("k"), 0)],
    entities: [],
    constraints: [],
  }
  // no export_key → each element is an object {k:v}
  let none : Map[String, ExportKey] = Map::new()
  inspect(
    export_result_str(sc, none, ["a", "b", "c"]),
    content="{xs:[{k:a},{k:b},{k:c}]}",
  )
  // export_key null on `k` → the key drops, each element is the bare value (array shape preserved)
  let nullk : Map[String, ExportKey] = Map::new()
  nullk.set("k", EkNull)
  inspect(export_result_str(sc, nullk, ["a", "b", "c"]), content="{xs:[a,b,c]}")
}

// ── 4. 昇格露出: name スコープ (command) に export_key: null → 子が昇格 ─────────────

///|
test "DR-052 §2/§3: export_key null on a command drops its scope key — children promote to the parent" {
  // A null-export command is not counted as a result-key layer (露出規則 §2.4): its scope key is
  // dropped and its children promote to the parent scope. Contrast: a normal command nests its
  // children under its name.
  let def_null = def_cmd([], [], [
    cmd("serve", def_([opt("port", TNum, long=["port"])], []), export=EkNull),
  ])
  let sc_null = build_or_fail(def_null, p22_order())
  inspect(
    export_result_str(sc_null, build_export_map(def_null), [
      "serve", "--port", "80",
    ]),
    content="{port:80}", // serve キー無し、port が親へ昇格
  )
  let def_norm = def_cmd([], [], [
    cmd("serve", def_([opt("port", TNum, long=["port"])], [])),
  ])
  let sc_norm = build_or_fail(def_norm, p22_order())
  inspect(
    export_result_str(sc_norm, build_export_map(def_norm), [
      "serve", "--port", "80",
    ]),
    content="{serve:{port:80}}", // 対照: 通常は serve 下にネスト
  )
}

// ── 5. "" = null ───────────────────────────────────────────────────────────────

///|
test "DR-052 §1: export_key \"\" normalizes to null (same 透過 behavior as null)" {
  // An empty string is meaningless as a key name, so it normalizes to null (DR-052 §1 / §4) — a
  // JSON-format escape hatch for「null が書けない」. Same 透過 as EkNull.
  let def = def_(
    [
      opt("verbose", TFlag, long=["verbose"], export=ek("")), // "" → EkNull
      opt("keep", TFlag, long=["keep"]),
    ],
    [],
  )
  let sc = build_or_fail(def, p22_order())
  inspect(
    export_result_str(sc, build_export_map(def), ["--verbose", "--keep"]),
    content="{keep:true}",
  )
}

// ── 6. 直交性: export_key は link/id と直交 (値の伝搬は不変) ──────────────────────

///|
test "DR-052 §2: export_key is orthogonal to link/id — link 合流 is unchanged, only the key differs" {
  // `port` has long + short, both linking to the one `port` cell (by name). export_key renames the
  // RESULT key but the link 合流 (value sync) is a parse-time / id concern, unchanged: `--port 80 -p 90`
  // still merges to one cell (last-wins 90), now surfacing under the export_key. 値の伝搬は止まらない.
  let def = def_(
    [opt("port", TNum, long=["port"], short=['p'], export=EkKey("portnum"))],
    [],
  )
  let sc = build_or_fail(def, p22_order())
  let ekm = build_export_map(def)
  inspect(
    export_result_str(sc, ekm, ["--port", "80", "-p", "90"]),
    content="{portnum:90}",
  )
}

// ── 7. presence marker (DR-052 §3) ─────────────────────────────────────────────

///|
test "DR-052 §3 presence marker: a selected scope is `{}` even if empty; an unselected scope is absent" {
  // A result-key scope-生成要素 (command) that is SELECTED has the value `{}` even when its children
  // are all absent (スコープ生成 = 値の発生、反復系の [] と同型). Not selected → absent (DR-051).
  let def = def_cmd([], [], [
    cmd("serve", def_([opt("port", TNum, long=["port"])], [])),
  ])
  let sc = build_or_fail(def, p22_order())
  let ekm = build_export_map(def)
  inspect(export_result_str(sc, ekm, ["serve"]), content="{serve:{}}") // 選ばれた空 command → {}
  inspect(export_result_str(sc, ekm, []), content="{}") // 選ばれない → absent (root は空)
}

// ── 8. 露出キー衝突: 同じ export_key を 2 要素 → 実行時 ambiguous (DESIGN §15.5) ─────

///|
test "DR-052/DESIGN §15.5: two elements with the SAME export_key both exposed is a runtime collision" {
  // The exposure-key uniqueness check (DR-021, runtime) applies to export_key VALUES: two distinct
  // elements resolving to the same key, both present with the same input, collide (ambiguous). Only
  // one present → no collision (the check is on actual co-exposure, not static).
  let def = def_(
    [
      opt("a", TFlag, long=["a"], export=EkKey("x")),
      opt("b", TFlag, long=["b"], export=EkKey("x")), // same export_key "x"
    ],
    [],
  )
  let sc = build_or_fail(def, p22_order())
  let ekm = build_export_map(def)
  inspect(export_result_str(sc, ekm, ["--a", "--b"]), content="collision:x") // 両露出 → 衝突
  inspect(export_result_str(sc, ekm, ["--a"]), content="{x:true}") // 片方のみ → 衝突なし
}
