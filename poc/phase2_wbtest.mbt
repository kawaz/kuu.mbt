// phase2_wbtest.mbt — the installer chain contracts (DR-042).
//
// parse_definition is a chain of installers. These tests pin the 5 invariants,
// idempotency, order-independence (all 24 permutations), link 合流, and the dd
// re-scoping — end to end, by building a scope and then running the evaluator.

/// The DR-042 §展開の標準パターン example, exercising all four installers.
fn dr042_def() -> Definition {
  {
    options: [
      opt("port", TNum, long=["port"], short=['p'], env=["PORT"]),
      opt("version", TFlag, short=['v']),
    ],
    positionals: [dd_marker(), pos("dir", TStr)],
    commands: [],
  }
}

fn build_or_fail(def : Definition, order : Array[Installer]) -> Scope {
  match parse_definition(def, order) {
    Ok(sc) => sc
    Err(msg) => abort("build failed: " + msg)
  }
}

fn canonical_order() -> Array[Installer] {
  [LongInst, ShortInst, EnvInst, DdInst]
}

// ── invariant ①' 非削除 + add-if-absent => 冪等 ───────────────────────────────

test "DR-042 ①': re-applying an installer is a no-op (idempotent from add-if-absent)" {
  // Apply the four installers directly to one build, snapshot, then apply all
  // four AGAIN to the SAME def+build. The vocab is NOT removed (non-deletion,
  // invariant ①'); the second pass re-reads it and re-contributes, but every
  // contribution is add-if-absent, so nothing new lands => identical AtomicAST.
  // Idempotency now comes from add-if-absent, not from consuming the vocab.
  // (This is done below the registration guard, which separately forbids listing
  // the same installer twice in one chain.)
  let reg : Map[String, Node] = Map::new()
  let sb = init_sb(clone_def(dr042_def()), reg)
  ensure_entities(sb)
  inst_long(sb.decl, sb.build)
  inst_short(sb.decl, sb.build)
  inst_env(sb.decl, sb.build)
  inst_dd(sb.decl, sb.build)
  let once = canon_scope(materialize(sb))
  inst_long(sb.decl, sb.build)
  inst_short(sb.decl, sb.build)
  inst_env(sb.decl, sb.build)
  inst_dd(sb.decl, sb.build)
  let twice = canon_scope(materialize(sb))
  inspect(once == twice, content="true")
}

test "DR-042 ①': the declaration layer is inert — def0 is unchanged, re-runs converge" {
  // Non-deletion means parse_definition never mutates the caller's declaration
  // layer: the same def0 can be parsed repeatedly and always yields the identical
  // AtomicAST. This is the property that keeps help/diagnose/re-serialization able
  // to read the original declaration (invariant ①').
  let def = dr042_def()
  let a = canon_scope(build_or_fail(def, canonical_order()))
  let b = canon_scope(build_or_fail(def, canonical_order()))
  // def0 still carries its vocab (proof it was read-only, not consumed)
  inspect(def.options[0].long, content="[port]")
  inspect(def.options[0].short, content="[p]")
  inspect(a == b, content="true")
}

// ── invariant ③ 所有語彙の交差禁止 ────────────────────────────────────────────

test "DR-042 ③: two installers claiming the same vocab is a registration error" {
  // Registration rejects duplicate ownership before any building happens.
  match parse_definition(dr042_def(), [LongInst, LongInst]) {
    Err(msg) =>
      inspect(msg, content="vocab 'long' is claimed by two installers")
    Ok(_) => inspect("unexpected Ok", content="should have failed")
  }
}

// ── invariant ① completeness: leftover vocab => error ─────────────────────────

test "DR-042 ①: special vocab with no installer is a completeness error" {
  // The def carries env:PORT, but EnvInst is omitted from the chain. After all
  // installers run, the leftover env vocab is reported as unknown (§13.5 型).
  match parse_definition(dr042_def(), [LongInst, ShortInst, DdInst]) {
    Err(msg) =>
      inspect(
        msg,
        content="unknown special vocab 'env:PORT' — no installer claimed it",
      )
    Ok(_) => inspect("unexpected Ok", content="should have failed")
  }
}

// ── 順序非依存: all 24 permutations converge ──────────────────────────────────

test "DR-042: all 24 installer orders produce the identical AtomicAST" {
  // The 5 invariants make the chain order-independent. Build under every order
  // and confirm a single distinct canonical form.
  let def = dr042_def()
  let perms = permutations(canonical_order())
  let canons : Array[String] = []
  for p in perms {
    let c = canon_scope(build_or_fail(def, p))
    let mut seen = false
    for x in canons {
      if x == c {
        seen = true
      }
    }
    if !seen {
      canons.push(c)
    }
  }
  inspect(perms.length(), content="24") // sanity: really all orders
  inspect(canons.length(), content="1") // sanity: they all converge
}

// ── invariant ④ 値源はラダー席への宣言 (source タグ保存) ───────────────────────

test "DR-042 ④: env is a ladder-seat declaration; source tags follow cli>env>default" {
  // port declares an env seat (PORT) and a default. The engine-owned ladder
  // (DR-031) decides precedence; the env installer only declared the seat.
  let def = def_(
    [opt("port", TNum, long=["port"], env=["PORT"], default=Some(VNum(3000)))],
    [],
  )
  let sc = build_or_fail(def, canonical_order())
  let env8080 : Map[String, String] = Map::new()
  env8080.set("PORT", "8080")
  // cli present => cli wins, tagged @cli
  inspect(
    render_binds_src(resolve_scope(sc, [mkb("port", VNum(9090), Cli)], env8080)),
    content="port=9090@cli",
  )
  // no cli, env present => env seat supplies value, tagged @env
  inspect(
    render_binds_src(resolve_scope(sc, [], env8080)),
    content="port=8080@env",
  )
  // neither => default seat, tagged @default
  let empty : Map[String, String] = Map::new()
  inspect(
    render_binds_src(resolve_scope(sc, [], empty)),
    content="port=3000@default",
  )
}

// ── 意地悪: 1 要素全部盛り (long + short + env) => 衛星が 1 実体に合流 ──────────

test "DR-042 意地悪: long+short+env on one element merge onto a single entity" {
  // All three installers target the same name => one value cell, and every CLI
  // form (long space, eq-split, short attach) writes that one cell (link 合流).
  let def = def_(
    [opt("port", TNum, long=["port"], short=['p'], env=["PORT"])],
    [],
  )
  let sc = build_or_fail(def, canonical_order())
  // exactly one entity named "port", carrying the declared env seat
  let mut count = 0
  let mut env_ok = false
  for e in sc.entities {
    if e.name == "port" {
      count = count + 1
      match e.env_key {
        Some(k) => if k == "PORT" { env_ok = true }
        None => ()
      }
    }
  }
  inspect(count, content="1")
  inspect(env_ok, content="true")
  // three CLI entry forms, one cell
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--port", "8080"])),
    content="ok{port=8080}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--port=8080"])),
    content="ok{port=8080}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["-p8080"])),
    content="ok{port=8080}",
  )
}

// ── dd re-scoping end-to-end via the installer (DR-042 ⑤) ──────────────────────

test "DR-042 ⑤: dd installer re-scopes — `--` flips the reading of a following token" {
  // -a/-b are short flags; x is a positional. With `--`, the greedy face is
  // severed after it, so `-b` becomes the raw positional x. Without `--`, `-b`
  // fires as a flag and the next token is x. Same tokens, different meaning.
  let def = def_(
    [opt("a", TFlag, short=['a']), opt("b", TFlag, short=['b'])],
    [dd_marker(), pos("x", TStr)],
  )
  let sc = build_or_fail(def, canonical_order())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["-a", "--", "-b"])),
    content="ok{a=true,x=-b}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["-a", "-b", "c"])),
    content="ok{a=true,b=true,x=c}",
  )
}

// ── end-to-end: every matcher form hits the same cell ─────────────────────────

test "DR-041/042: long-space, eq-split, short-attach, short-next-token all agree" {
  let def = def_([opt("port", TNum, long=["port"], short=['p'])], [])
  let sc = build_or_fail(def, canonical_order())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--port", "8080"])),
    content="ok{port=8080}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--port=8080"])),
    content="ok{port=8080}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["-p8080"])),
    content="ok{port=8080}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["-p", "8080"])),
    content="ok{port=8080}",
  )
}
