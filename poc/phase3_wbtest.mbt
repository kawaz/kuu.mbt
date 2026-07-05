// phase3_wbtest.mbt — command / global / inherit installers + the 7-installer
// order-independence (DR-018 / DR-041 §4 / DR-042). These pin the tree-shaped
// installer chain: subcommands become greedy exact triggers over a fresh backbone,
// global copies declarations down (shadowing by trigger), inherit declares a ladder
// seat, and the whole chain converges under every one of the 5040 installer orders.

fn all_installers() -> Array[Installer] {
  [LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst]
}

// ── command: a subcommand is a greedy exact trigger over a NEW backbone ────────

test "DR-018/041 §4: a subcommand fires as a greedy trigger and enters its own backbone" {
  // `build` is a command whose subtree defines `--release`. Typing `build --release`
  // enters build's fresh backbone (parent greedy does not interject inside it) and
  // fires --release there. The command name is a greedy-face exact trigger.
  let def = def_cmd([], [], [
    cmd("build", def_([opt("release", TFlag, long=["release"])], [])),
  ])
  let sc = build_or_fail(def, all_installers())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["build", "--release"])),
    content="ok{release=true}",
  )
  // The subcommand name itself is required to enter; a bare option at the root that
  // only the child declares does not resolve (the child's backbone is separate).
  // (旧値 fail:no complete parse は空 errors バグの凍結だった。構造的失敗が
  // ParseError を emit するようになった = spec DR-053/065 準拠)
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--release"])),
    content="fail:unexpected token",
  )
}

// ── global: a global option is available inside descendant command scopes ──────

test "DR-042 global: a global option is copied into a subcommand scope" {
  // --verbose is declared global at the root. Inside `build` (which declares no
  // verbose) the copy makes `build --verbose` fire verbose=true. This is the
  // structural copy (invariant ②) — the child's OWN greedy face carries it, not an
  // evaluator reach-up (DR-042 §採用しなかった案: 多重背骨).
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("build", def_([], []))],
  )
  let sc = build_or_fail(def, all_installers())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["build", "--verbose"])),
    content="ok{verbose=true}",
  )
}

test "DR-042 global shadowing: a child declaring the same TRIGGER blocks the copy" {
  // Root global option `gverb` and child-own option `lverb` BOTH trigger --verbose
  // but under different names. Shadowing is by trigger (同名トリガ), so the copy is
  // suppressed and the child's own wins: `build --verbose` binds lverb, unambiguously.
  // (If the copy had leaked in, both names would fire => ambiguous:2.)
  let def = def_cmd(
    [opt("gverb", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("build", def_([opt("lverb", TFlag, long=["verbose"])], []))],
  )
  let sc = build_or_fail(def, all_installers())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["build", "--verbose"])),
    content="ok{lverb=true}",
  )
}

// ── inherit: the value-source ladder gains an inherit seat (cli>env>inherit>default) ─

test "DR-031/013 inherit: a child inherits the nearest ancestor's value (cli>env>inherit>default)" {
  // Root declares `ttl` (default 30). The `up` subcommand declares its own `ttl`
  // with inherit=true (own default 99). At resolve time the child's inherit seat
  // consults the parent's resolved ttl; the ladder is cli > env > inherit > default.
  let def = def_cmd(
    [opt("ttl", TNum, long=["ttl"], default=Some(VNum(30)))],
    [],
    [
      cmd(
        "up",
        def_([opt("ttl", TNum, long=["ttl"], inherit=true, default=Some(VNum(99)))], []),
      ),
    ],
  )
  let sc = build_or_fail(def, all_installers())
  let child = match command_child(sc, "up") {
    Some(c) => c
    None => abort("no up child")
  }
  let empty : Map[String, String] = Map::new()

  // parent sets ttl=50 on CLI; child (no cli/env) inherits 50, tagged @inherit
  let parent_cli = resolve_scope(sc, [mkb("ttl", VNum(50), Cli)], empty)
  inspect(
    render_binds_src(
      resolve_scope(child, [], empty, inherited=inherited_of(parent_cli)),
    ),
    content="ttl=50@inherit",
  )

  // parent falls to its default 30; child inherits 30 (default flows through inherit)
  let parent_def = resolve_scope(sc, [], empty)
  inspect(
    render_binds_src(
      resolve_scope(child, [], empty, inherited=inherited_of(parent_def)),
    ),
    content="ttl=30@inherit",
  )

  // child's OWN cli beats inherit (cli is the top seat)
  inspect(
    render_binds_src(
      resolve_scope(child, [mkb("ttl", VNum(7), Cli)], empty, inherited=inherited_of(parent_cli)),
    ),
    content="ttl=7@cli",
  )
}

test "DR-031 inherit: with no ancestor value, the child falls to its own default" {
  // No inherited context => the inherit seat yields nothing and the ladder drops to
  // the child's own default (99). Proves inherit sits ABOVE default, not replacing it.
  let def = def_cmd(
    [opt("ttl", TNum, long=["ttl"], default=Some(VNum(30)))],
    [],
    [
      cmd(
        "up",
        def_([opt("ttl", TNum, long=["ttl"], inherit=true, default=Some(VNum(99)))], []),
      ),
    ],
  )
  let sc = build_or_fail(def, all_installers())
  let child = match command_child(sc, "up") {
    Some(c) => c
    None => abort("no up child")
  }
  let empty : Map[String, String] = Map::new()
  inspect(
    render_binds_src(resolve_scope(child, [], empty)),
    content="ttl=99@default",
  )
}

// ── completeness for the new vocabularies (invariant ①') ───────────────────────

test "DR-042 ①': command / global / inherit vocab with no installer is a completeness error" {
  // A def using a vocab whose installer is absent from the chain errors, naming the
  // unowned vocab (§13.5 型). Checked for each new installer.
  // DR-054: each is an unknown-vocab DefError (`(commands)` element for the command vocab).
  let cmd_def = def_cmd([], [], [cmd("x", def_([], []))])
  match parse_definition(cmd_def, [LongInst]) {
    Err(errs) => inspect(deferrs_str(errs), content="(commands)/unknown-vocab")
    Ok(_) => abort("expected command completeness error")
  }
  let global_def = def_cmd([opt("v", TFlag, long=["v"], global=true)], [], [])
  match parse_definition(global_def, [LongInst]) {
    Err(errs) => inspect(deferrs_str(errs), content="v/unknown-vocab")
    Ok(_) => abort("expected global completeness error")
  }
  let inherit_def = def_(
    [opt("t", TNum, long=["t"], inherit=true)],
    [],
  )
  match parse_definition(inherit_def, [LongInst]) {
    Err(errs) => inspect(deferrs_str(errs), content="t/unknown-vocab")
    Ok(_) => abort("expected inherit completeness error")
  }
}

// ── 順序非依存: all 5040 orders of the 7 installers converge ────────────────────

fn perm7_def() -> Definition {
  // A def that exercises every one of the 7 installers' vocab: long+short+env on
  // `port`, a global flag `verbose`, a dd marker + a positional, and a subcommand
  // `build` whose own option `level` is inherit. The interesting order-dependence is
  // global × long/short in the child (the copied --verbose must gain its satellite
  // regardless of when global ran); the fixpoint must make all 5040 orders agree.
  def_cmd(
    [
      opt("port", TNum, long=["port"], short=['p'], env=["PORT"]),
      opt("verbose", TFlag, long=["verbose"], global=true),
    ],
    [dd_marker(), pos("dir", TStr)],
    [cmd("build", def_([opt("level", TNum, long=["level"], inherit=true)], []))],
  )
}

test "DR-042: all 5040 orders of the 7 installers produce the identical AtomicAST tree" {
  // The 5 invariants + fixpoint make the tree-shaped chain order-independent. Build
  // under every permutation and confirm a single distinct canonical form. canon_scope
  // recurses through the command subtree (Show of the greedy ScopeNode), so the
  // global copy landing in the child scope is part of the compared form.
  let def = perm7_def()
  let perms = permutations(all_installers())
  let seen : Array[String] = []
  for p in perms {
    let c = canon_scope(build_or_fail(def, p))
    let mut dup = false
    for x in seen {
      if x == c {
        dup = true
        break
      }
    }
    if !dup {
      seen.push(c)
    }
  }
  inspect(perms.length(), content="5040") // sanity: really all 7! orders
  inspect(seen.length(), content="1") // they all converge to one AtomicAST
}
