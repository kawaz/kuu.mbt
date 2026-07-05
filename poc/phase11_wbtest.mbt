// phase11_wbtest.mbt — global as a LINK-SYNC satellite (DR-042 §展開の標準パターン: ref/link
// 衛星 + 実体だけノード). The global installer copies a `Rooted` satellite into the child
// scope, so a global option fired inside a subcommand binds the ONE root entity — its value
// syncs to the root cell, it does not fork a fresh per-scope cell.

///|
fn link_order() -> Array[Installer] {
  [LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst]
}

///|
test "DR-042 link-sync: a global option binds the ROOT entity, not a child cell" {
  // build --verbose: verbose lands at the ROOT (the link satellite escapes build's nesting),
  // so the result is { verbose:true, build:{} } — NOT { build:{verbose:true} } (the old
  // fresh-cell behavior). `--verbose build` (fired directly at root) writes the same cell.
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("build", def_([], []))],
  )
  let sc = build_or_fail(def, link_order())
  inspect(
    result_str(sc, ["build", "--verbose"]),
    content="{verbose:true,build:{}}",
  )
  inspect(
    result_str(sc, ["--verbose", "build"]),
    content="{verbose:true,build:{}}",
  )
}

///|
test "DR-042 link-sync: a global VALUE option syncs into the root cell from inside a child" {
  // Same, for a value option: `build --out X` puts out=X at the root (link), build stays {}.
  let def = def_cmd([opt("out", TStr, long=["out"], global=true)], [], [
    cmd("build", def_([], [])),
  ])
  let sc = build_or_fail(def, link_order())
  inspect(result_str(sc, ["build", "--out", "X"]), content="{out:X,build:{}}")
}

///|
test "DR-038 link-sync: two entries onto the SAME root entity merge to one path" {
  // A root --verbose AND a Rooted copy --verbose both target the ONE root `verbose` cell. On
  // the same token both fire, producing the SAME root effect via two routes — effect identity
  // (entry-independent, link-hint stripped) merges them to a single path, not ambiguous. This
  // is the DR-038 "同一実体への入口が複数スコープにある" merge, now realized by link-sync.
  let g = scope(
    [flag("--verbose", "verbose"), Rooted(flag("--verbose", "verbose"), 1)],
    [],
  )
  inspect(render_outcome(parse(g, ["--verbose"])), content="ok{verbose=true}")
}

///|
test "DR-038 link-sync: two link entries onto DIFFERENT root entities stay distinct" {
  // Same trigger, but the two link entries bind different root cells (a vs b) => different
  // effects => two distinct paths => ambiguous. Confirms the merge is by effect, not by link.
  let g = scope([Rooted(flag("--v", "a"), 1), Rooted(flag("--v", "b"), 1)], [])
  inspect(render_outcome(parse(g, ["--v"])), content="ambiguous:2")
}
