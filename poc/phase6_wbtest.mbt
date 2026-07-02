// phase6_wbtest.mbt — the cross-installer stress cases (DR-042 §検証マトリクス):
// global × dd (scope-crossing copy × greedy-sever) and multi-level global propagation
// through the fixpoint. These are the "next to break" combinations the DR flagged.

fn all7() -> Array[Installer] {
  [LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst]
}

// ── global × dd: the copied global option obeys the child's dd sever ───────────

test "DR-042 ⑤ × global: inside a child, dd severs the copied global option too" {
  // --verbose is a root global; the `run` subcommand has a dd marker and a positional
  // x. The global copy lands on run's greedy face, so it obeys run's OWN sever: after
  // `--`, --verbose is not fired, it is a raw positional value. This is ⑤ (sever) and
  // ② (structural copy) holding together — the copy is an ordinary greedy resident, so
  // no extra rule is needed for it.
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("run", def_([], [dd_marker(), pos("x", TStr)]))],
  )
  let sc = build_or_fail(def, all7())
  // no dd: the copied --verbose fires inside run, x takes the trailing token
  inspect(
    render_outcome(parse(ScopeNode(sc), ["run", "--verbose", "y"])),
    content="ok{verbose=true,x=y}",
  )
  // dd present: after `--`, the copied --verbose is severed and falls raw into x
  inspect(
    render_outcome(parse(ScopeNode(sc), ["run", "--", "--verbose"])),
    content="ok{x=--verbose}",
  )
}

test "DR-042 ⑤ × global: the global option still works BEFORE the child's dd" {
  // Ordering within the child: `run --verbose -- z` fires the global copy, then `--`
  // severs, then z is the raw positional. Confirms the sever boundary is the child's
  // `--`, not the subcommand entry.
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("run", def_([], [dd_marker(), pos("x", TStr)]))],
  )
  let sc = build_or_fail(def, all7())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["run", "--verbose", "--", "z"])),
    content="ok{verbose=true,x=z}",
  )
}

// ── multi-level: a global option propagates to a grandchild via the fixpoint ────

test "DR-042 global: a global option reaches a grandchild command (fixpoint propagation)" {
  // verbose is global at the root; `a` and `a b` are nested subcommands that declare
  // no verbose. The global copy must propagate root -> a -> b through the fixpoint
  // (each level re-copies the retained-global copy into its children). `a b --verbose`
  // fires verbose two levels deep.
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("a", def_cmd([], [], [cmd("b", def_([], []))]))],
  )
  let sc = build_or_fail(def, all7())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "--verbose"])),
    content="ok{verbose=true}",
  )
}

test "DR-042 global shadowing blocks a whole subtree: an intermediate scope's own wins" {
  // `a` self-declares its own `--verbose` (name averb). Shadowing is level-by-level, so
  // root's global does NOT overwrite a's, and — because the copy propagates from a's own
  // declaration — b inside a inherits A's verbose, not root's. Here b declares nothing,
  // so `a b --verbose` binds averb (a's), proving the intermediate shadow governs its subtree.
  let def = def_cmd(
    [opt("rverb", TFlag, long=["verbose"], global=true)],
    [],
    [
      cmd(
        "a",
        def_cmd(
          [opt("averb", TFlag, long=["verbose"], global=true)],
          [],
          [cmd("b", def_([], []))],
        ),
      ),
    ],
  )
  let sc = build_or_fail(def, all7())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["a", "b", "--verbose"])),
    content="ok{averb=true}",
  )
}
