// phase21_wbtest.mbt — 第 11 弾: 結果の欠落表現 (DR-051 absent) + int 型 / config null (DR-050 §4)。
// 値源ラダーを回しても値の無い非反復要素は結果にキーが出ない (absent、null でもゼロ値でもない)。
// 反復系 (0回で []) / default 持ち / required (経路不成立) は absent にならない。null は kuu の値空間に
// 無く、config の JSON null は「供給なし」。int は整数制約付き数値 (非整数は Error)。

fn p21_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst,
  ]
}

// ── absent: 値源を持たない要素が未指定 → キーなし (DR-051 §1) ────────────────────

test "DR-051 §1: a value-source-less element unspecified is ABSENT — no key (not null, not zero)" {
  // `name` has NO value source (no default / env / config). With nothing supplied, the value-source
  // ladder is exhausted and the result omits the key entirely — absent, NOT an in-band null or a
  // type zero-value. Specifying it makes the key appear.
  let def = def_([opt("name", TStr, long=["name"])], [])
  let sc = build_or_fail(def, p21_order())
  inspect(render_binds_src(resolve_scope(sc, [], empty_env())), content="") // absent → no key
  inspect(
    render_binds_src(resolve_scope(sc, [mkb("name", VStr("x"), Cli)], empty_env())),
    content="name=x@cli", // specified → present
  )
}

// ── absent にならない 3 族 (DR-051 §2) ─────────────────────────────────────────

test "DR-051 §2a: a default-bearing element is never absent — it is always present (source=default)" {
  // A default is a value source, so the ladder always produces a value; the key is always present.
  let def = def_([opt("port", TNum, long=["port"], default=Some(VNum(5)))], [])
  let sc = build_or_fail(def, p21_order())
  inspect(render_binds_src(resolve_scope(sc, [], empty_env())), content="port=5@default")
}

test "DR-051 §2b: a repeat element is never absent — 0 firings is `[]` (uniform array, DR-044)" {
  // A repeat cell always has the many-valued shape: 0 firings is an empty list, not absent. (This is
  // the 6th-installment uniform-array result, re-pinned here as the DR-051 §2 contrast.)
  let def = def_([], [pos("xs", TStr, optional=true)]) // optional = repeat{min:0,max:1}
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p21_order(), reg)
  inspect(result_str(sc, [], defs=reg), content="{xs:[]}") // absent にならず []
}

test "DR-051 §2c: a required (mandatory) positional is never absent in a SUCCESS — no value ⇒ path fails" {
  // A mandatory positional must consume a token; if it cannot, no complete path exists (DR-047 値充足).
  // So a successful parse ALWAYS carries the positional — it is never absent in a success result.
  let def = def_([], [pos("file", TStr)])
  let sc = build_or_fail(def, p21_order())
  inspect(render_outcome(parse(ScopeNode(sc), [])), content="fail:no complete parse") // 未指定 → 経路不成立
  inspect(render_outcome(parse(ScopeNode(sc), ["x"])), content="ok{file=x}") // success は必ず値を持つ
}

// ── ParserContext のメタ保持 (DR-051 §5, 2 層分離) ─────────────────────────────

test "DR-051 §5: an absent element's meta is derivable from the roster + bindings (2-layer separation)" {
  // The result object omits an absent element, but the ParserContext (the entity roster + bindings)
  // still lets a consumer ask「なぜ無いのか」: `name` is absent (present=false, committed=false) yet the
  // roster knows it exists; `port` (from default) is present but NOT committed (not a CLI selection).
  let def = def_(
    [opt("name", TStr, long=["name"]), opt("port", TNum, long=["port"], default=Some(VNum(5)))],
    [],
  )
  let sc = build_or_fail(def, p21_order())
  let resolved = resolve_scope(sc, [], empty_env())
  // result object: absent `name` omitted, `port` present from default
  inspect(render_binds_src(resolved), content="port=5@default")
  // ParserContext roster still knows `name` (the detail side)
  inspect(entity_exists(sc, "name"), content="true")
  // absent meta: not present, not committed
  inspect(ctx_report(resolved, "name"), content="present=false,committed=false")
  // default-supplied meta: present but NOT committed (default is not a user selection)
  inspect(ctx_report(resolved, "port"), content="present=true,committed=false")
}

// ── config の JSON null = 供給なし (DR-050 §4 / DR-051 §4) ──────────────────────

test "DR-050 §4/DR-051: config JSON null is 供給なし — it falls through the ladder (default, else absent)" {
  // A `key: null` in config supplies NOTHING (null is not a value in kuu's space). port falls to its
  // default; name (no default) becomes absent. Contrast: a real config value supplies normally.
  let def = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("port", TNum, long=["port"], config_key=Some(["port"]), default=Some(VNum(9))),
      opt("name", TStr, long=["name"], config_key=Some(["name"])), // no default
    ],
    [],
  )
  let sc = build_or_fail(def, p21_order())
  // config {port: null, name: null} → port to default, name absent (null ≠ supply)
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("port", CNull), ("name", CNull)]))),
    content="port=9@default",
  )
  // contrast: a real value supplies from config
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("port", CNum(3000))]))),
    content="port=3000@config",
  )
}

// ── int 型 (DR-050 §4 int 行 / DESIGN §3.3 数値 3 種) ───────────────────────────

test "DR-050 §4 int: integer accepted, non-integer 1.5 Error, string parses integer-only" {
  // int is integer-constrained: a JSON number that is integral is accepted; a non-integer (1.5) is a
  // DR-037 Error; a JSON string parses ONLY if it is integer syntax ("42" ok, "1.5" Error).
  let def = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("n", TInt, long=["n"], config_key=Some(["n"])),
    ],
    [],
  )
  let sc = build_or_fail(def, p21_order())
  inspect(resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("n", CNum(42))]))), content="n=42@config")
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("n", CNum(1.5))]))),
    content="err:config value \"1.5\" is not an integer",
  )
  inspect(resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("n", CStr("42"))]))), content="n=42@config")
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("n", CStr("1.5"))]))),
    content="err:config value \"1.5\" is not an integer",
  )
}

test "DR-050 §4/§3.3 int vs number: number accepts 1.5, int rejects it (数値 3 種の対照)" {
  // number is the general numeric type (integer or float, JSON number 同型) — 1.5 is accepted. int is
  // integer-constrained — the same 1.5 is an Error. This is the 数値 3 種の関係 (float is a number alias).
  let head = opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml")))
  let sc_num = build_or_fail(def_([head, opt("v", TNum, long=["v"], config_key=Some(["v"]))], []), p21_order())
  let sc_int = build_or_fail(def_([head, opt("v", TInt, long=["v"], config_key=Some(["v"]))], []), p21_order())
  inspect(resolve_cfg(sc_num, [], empty_env(), provider_obj(CObj([("v", CNum(1.5))]))), content="v=1.5@config")
  inspect(
    resolve_cfg(sc_int, [], empty_env(), provider_obj(CObj([("v", CNum(1.5))]))),
    content="err:config value \"1.5\" is not an integer",
  )
}
