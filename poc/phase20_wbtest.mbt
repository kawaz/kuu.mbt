// phase20_wbtest.mbt — 第 9 弾: config ファイル値源 (DR-050) の垂直スライス。config installer は
// 席宣言型 (env と同型、不変則④): type:"config_file" / config_key を回収し config 席を宣言。値源
// ラダーは cli > env > config > inherit > default (DR-031 #3)。config は構造 (matcher/経路探索) に
// 影響しない — 完走後の resolve フェーズ (経路確定 → config_file 値確定 → provider 読込 → config 席
// 有効化 → 最終値確定) で効く。DR-042 検証マトリクスの「env × config_key (値源 2 つ)」を含む。

fn cfg_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst,
  ]
}

/// A config_provider stub that returns `obj` for ANY path.
fn provider_obj(obj : ConfigVal) -> (String) -> ConfigVal? {
  fn(_p : String) -> ConfigVal? { Some(obj) }
}

/// A config_provider stub that always fails (read failure / file absent).
fn provider_none() -> (String) -> ConfigVal? {
  fn(_p : String) -> ConfigVal? { None }
}

/// Resolve a scope WITH config and render the resolved effect bindings (key=value@source, sorted),
/// or the error string. The config_file element is infrastructure and is not in the output.
fn resolve_cfg(
  sc : Scope,
  cli : Array[Binding],
  env : Map[String, String],
  provider : (String) -> ConfigVal?,
) -> String {
  match resolve_scope_config(sc, cli, env, provider) {
    Ok(binds) => render_binds_src(binds)
    Err(msg) => "err:" + msg
  }
}

fn empty_env() -> Map[String, String] {
  Map::new()
}

// ── env × config_key: the 4-seat ladder cli > env > config > default (本命) ──────

test "DR-050/031 env × config_key: the ladder is cli > env > config > default, source tags preserved" {
  // port declares env (PORT), config_key (["port"]), and a default. The config_file element `config`
  // provides the config object. Each of the 4 value sources supplies port in turn, and the source
  // tag (@cli / @env / @config / @default) is preserved (DR-050 §5 config 席 = source:"config",
  // F-032). This is the DR-042 matrix item「env × config_key (値源 2 つ)」.
  let def = def_(
    [
      opt("config", TStr, long=["config"], env=["MYAPP_CONFIG"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("port", TNum, long=["port"], env=["PORT"], config_key=Some(["port"]), default=Some(VNum(1))),
    ],
    [],
  )
  let sc = build_or_fail(def, cfg_order())
  let obj = CObj([("port", CNum(3000))])
  let prov = provider_obj(obj)
  // cli present → cli wins
  inspect(
    resolve_cfg(sc, [mkb("port", VNum(9090), Cli)], empty_env(), prov),
    content="port=9090@cli",
  )
  // no cli, env present → env wins over config
  let env8080 : Map[String, String] = Map::new()
  env8080.set("PORT", "8080")
  inspect(resolve_cfg(sc, [], env8080, prov), content="port=8080@env")
  // no cli/env → config supplies (source:"config")
  inspect(resolve_cfg(sc, [], empty_env(), prov), content="port=3000@config")
  // no cli/env, config lacks port → default
  inspect(resolve_cfg(sc, [], empty_env(), provider_obj(CObj([]))), content="port=1@default")
}

test "DR-050/042 ④: env and config seat declarations are order-independent (permutation)" {
  // Both env and config are seat-declaration installers (invariant ④). Building with EnvInst before
  // ConfigInst vs after yields the SAME AtomicAST (entities carry both env_key and config_seat
  // regardless of order). Confirms the two seats compose order-independently.
  let def = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("port", TNum, long=["port"], env=["PORT"], config_key=Some(["port"])),
    ],
    [],
  )
  let a = canon_scope(
    build_or_fail(def, [LongInst, EnvInst, ConfigInst, ShortInst, DdInst, CommandInst, GlobalInst, InheritInst, RepeatInst, MultipleInst]),
  )
  let b = canon_scope(
    build_or_fail(def, [ConfigInst, EnvInst, LongInst, ShortInst, DdInst, CommandInst, GlobalInst, InheritInst, RepeatInst, MultipleInst]),
  )
  inspect(a == b, content="true")
}

test "DR-050 §3 同型 default: an element WITHOUT config_key looks up its 同型 path (scope path + name)" {
  // The default correspondence is 同型: an element that declares NO config_key looks itself up in
  // the config object by its result-scope path + name (here root → ["port"]). This is the「結果と
  // 同じ形」correspondence (DR-030 appconfig 統合ストア), distinct from an explicit absolute config_key.
  let def = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("port", TNum, long=["port"], default=Some(VNum(1))), // NO config_key → 同型
    ],
    [],
  )
  let sc = build_or_fail(def, cfg_order())
  // config has port at the top level → 同型 path ["port"] finds it
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("port", CNum(5000))]))),
    content="port=5000@config",
  )
  // a differently-nested config (server.port) is NOT found by the 同型 path ["port"] → default
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("server", CObj([("port", CNum(5000))]))]))),
    content="port=1@default",
  )
}

// ── 値の型 (DR-050 §4) ─────────────────────────────────────────────────────────

test "DR-050 §4 types: leniency is BIDIRECTIONALLY SYMMETRIC (kawaz 裁定 a); 意味の飛躍/構造不一致は Error" {
  // config value's expected type = the element's type, and leniency is symmetric in BOTH directions
  // (DR-040 canonical 最寛容): a string parses into any type, AND a JSON scalar stringifies into a
  // string element. A string element accepts anything in CLI/env, so config observes the same — the
  // presence/absence of quotes in the config file must not split behavior. The ONLY errors are the
  // 意味の飛躍 (bool ↔ number coercion) and 構造不一致 (array/object → a scalar element).
  let def = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("name", TStr, long=["name"], config_key=Some(["name"])),
      opt("port", TNum, long=["port"], config_key=Some(["port"])),
      opt("flag", TFlag, long=["flag"], config_key=Some(["flag"])),
    ],
    [],
  )
  let sc = build_or_fail(def, cfg_order())
  // matching types: string→VStr, number→VNum, bool→VBool
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("name", CStr("hi")), ("port", CNum(8080)), ("flag", CBool(true))]))),
    content="flag=true@config,name=hi@config,port=8080@config",
  )
  // string → number/bool: lenient parse (text → type). "8080" → 8080, "true" → true
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("port", CStr("8080")), ("flag", CStr("true"))]))),
    content="flag=true@config,port=8080@config",
  )
  // JSON scalar → string element: stringified (裁定 a の追加半分). 1.5 → "1.5", true → "true"
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("name", CNum(1.5))]))),
    content="name=1.5@config",
  )
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("name", CBool(true))]))),
    content="name=true@config",
  )
  // 意味の飛躍 (bool ↔ number) は Error — no coercion in either direction
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("flag", CNum(1))]))),
    content="err:config number for a bool element (no number↔bool coercion)",
  )
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("port", CBool(true))]))),
    content="err:config bool for a number element (no number↔bool coercion)",
  )
  // 構造不一致 (array → a scalar element) は Error
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("name", CArr([CStr("a")]))]))),
    content="err:config array for a scalar element (structural mismatch)",
  )
}

test "DR-050 §4 array → multiple pieces; object → 同型 navigation via config_key" {
  // An array config value feeds a `multiple` cell's pieces (each typed per §4). A nested object is
  // navigated by an absolute config_key path (server.port), the 同型対応 at the lookup level.
  let def = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("tag", TStr, long=["tag"], multiple=true, config_key=Some(["tags"])),
      opt("port", TNum, long=["port"], config_key=Some(["server", "port"])),
    ],
    [],
  )
  let sc = build_or_fail(def, cfg_order())
  let obj = CObj([
    ("tags", CArr([CStr("a"), CStr("b")])),
    ("server", CObj([("port", CNum(9000))])),
  ])
  // array → two pieces on the tag cell; nested object → port via server.port
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(obj)),
    content="port=9000@config,tag=a@config,tag=b@config",
  )
}

test "DR-050 §4 flag: integer-valued number → string drops the fractional part (1.0 → \"1\", serialize-dependent)" {
  // A JSON number 1.0 has no memory of "1" vs "1.0" (JSON has a single number type). The PoC renders
  // an integer-valued double WITHOUT a fractional part (1.0 → "1"); some JSON serializers instead emit
  // "1.0". DR-050 §4 says only「JSON serialize の標準表現」and does NOT pin this — so the integer-valued
  // case is a serialize-dependent detail (flag). A non-integer 1.5 → "1.5" is unambiguous. This LOCKS
  // the PoC's chosen representation so the divergence point is visible.
  let def = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("name", TStr, long=["name"], config_key=Some(["name"])),
    ],
    [],
  )
  let sc = build_or_fail(def, cfg_order())
  inspect(
    resolve_cfg(sc, [], empty_env(), provider_obj(CObj([("name", CNum(1.0))]))),
    content="name=1@config",
  )
}

// ── パス解決: --config (CLI) > MYAPP_CONFIG (env) > default ─────────────────────

test "DR-050 path ladder: the config_file path itself resolves cli > env > default" {
  // The config_file element `config` is an ordinary element; its PATH resolves down cli > env >
  // default. A provider that returns a different object per path lets us observe which path won.
  let def = def_(
    [
      opt("config", TStr, long=["config"], env=["MYAPP_CONFIG"], config_file=true, default=Some(VStr("/default.toml"))),
      opt("port", TNum, long=["port"], config_key=Some(["port"])),
    ],
    [],
  )
  let sc = build_or_fail(def, cfg_order())
  let prov = fn(p : String) -> ConfigVal? {
    if p == "/cli.toml" {
      Some(CObj([("port", CNum(11))]))
    } else if p == "/env.toml" {
      Some(CObj([("port", CNum(22))]))
    } else if p == "/default.toml" {
      Some(CObj([("port", CNum(33))]))
    } else {
      None
    }
  }
  // cli path wins
  inspect(resolve_cfg(sc, [mkb("config", VStr("/cli.toml"), Cli)], empty_env(), prov), content="port=11@config")
  // no cli, env path
  let envc : Map[String, String] = Map::new()
  envc.set("MYAPP_CONFIG", "/env.toml")
  inspect(resolve_cfg(sc, [], envc, prov), content="port=22@config")
  // no cli/env → default path
  inspect(resolve_cfg(sc, [], empty_env(), prov), content="port=33@config")
}

// ── null (読込失敗): committed パス → Error / default パス不在 → 黙認 ────────────

test "DR-050 null: committed path read failure is Error; default path absence is silent" {
  // A committed path (CLI/env explicit) that the provider cannot read is a DR-037 Error (指定した
  // のに読めない). A default-derived path that reads None is silently tolerated (設定ファイルは
  // オプショナル) — the config seat is empty and port falls to its default.
  let def = def_(
    [
      opt("config", TStr, long=["config"], env=["MYAPP_CONFIG"], config_file=true, default=Some(VStr("/default.toml"))),
      opt("port", TNum, long=["port"], config_key=Some(["port"]), default=Some(VNum(7))),
    ],
    [],
  )
  let sc = build_or_fail(def, cfg_order())
  // committed CLI path + provider None → Error
  inspect(
    resolve_cfg(sc, [mkb("config", VStr("/missing.toml"), Cli)], empty_env(), provider_none()),
    content="err:config file \"/missing.toml\" could not be read",
  )
  // default path + provider None → silent, port falls to default
  inspect(resolve_cfg(sc, [], empty_env(), provider_none()), content="port=7@default")
}

// ── 循環禁止: config_file 要素自身に config_key → 静的エラー ─────────────────────

test "DR-050 §5 循環禁止: a config_file element cannot carry a config_key (static error)" {
  // A config_file element taking its own path from config is a cycle (it needs the config it locates
  // to know where the config is). The static check rejects the definition.
  let def = def_(
    [opt("config", TStr, long=["config"], config_file=true, config_key=Some(["config"]))],
    [],
  )
  // DR-054: a config-cycle DefError.
  match parse_definition(def, cfg_order()) {
    Err(errs) => inspect(deferrs_str(errs), content="config/config-cycle")
    Ok(_) => abort("expected a 循環禁止 static error")
  }
}

// ── config は構造に影響しない (DR-050 §5 不変条件) ──────────────────────────────

test "DR-050 §5 invariant: config does not affect structure — parsing is identical with/without config" {
  // config is a value source only: it contributes NO matcher / trigger / path-search behavior. The
  // AtomicAST greedy/positional faces are identical whether or not a config_file element is present;
  // only the entities gain a config seat. So the same argv parses to the same structure — the
  // resolve phase (where config acts) is strictly after path-search completes.
  let with_cfg = def_(
    [
      opt("config", TStr, long=["config"], config_file=true, default=Some(VStr("/app.toml"))),
      opt("port", TNum, long=["port"], config_key=Some(["port"])),
    ],
    [],
  )
  let sc = build_or_fail(with_cfg, cfg_order())
  // parsing (structure) is unaffected by config: --port 80 binds normally, no config consulted
  inspect(render_outcome(parse(ScopeNode(sc), ["--port", "80"])), content="ok{port=80}")
  // the config seat exists on port but NOT on the config_file element (循環禁止)
  let mut port_seat = false
  let mut config_seat_on_cf = true
  for e in sc.entities {
    if e.name == "port" {
      port_seat = e.config_seat
    }
    if e.name == "config" {
      config_seat_on_cf = e.config_seat
    }
  }
  inspect(port_seat, content="true")
  inspect(config_seat_on_cf, content="false")
}
