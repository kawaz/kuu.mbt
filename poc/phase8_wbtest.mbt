// phase8_wbtest.mbt — 早閉じ抑制 (DR-041 §4, rev): the command sever is gone. A scope
// cannot complete while its own greedy can read the next token, so "the innermost scope
// that can read wins" emerges, and after a subcommand completes the parent backbone
// RESUMES (a trailing parent option is still reachable). These pin the replacement of
// the second-弾 F-3 sever rule.

///|
fn ec_order() -> Array[Installer] {
  [LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst]
}

// ── 読める最内スコープが勝つ: app and build both declare --out (distinct entities) ──

///|
test "DR-041 §4 rev: `app build --out X` binds build's --out (innermost readable wins)" {
  // Both app and build declare --out. Inside build, --out is readable, so build cannot
  // close before consuming it (早閉じ抑制) — build's cell wins, uniquely. No sever needed.
  let def = def_cmd([opt("out", TStr, long=["out"])], [], [
    cmd("build", def_([opt("out", TStr, long=["out"])], [])),
  ])
  let sc = build_or_fail(def, ec_order())
  inspect(result_str(sc, ["build", "--out", "X"]), content="{build:{out:X}}")
}

///|
test "DR-041 §4 rev: `app --out X build` binds app's --out (readable at root first)" {
  // The same tokens before `build` are read by the root scope: --out must fire at root
  // (early-close forbids the root closing while it can read --out), then build enters empty
  // (so build produces no bindings and does not appear in the result — root's out wins).
  let def = def_cmd([opt("out", TStr, long=["out"])], [], [
    cmd("build", def_([opt("out", TStr, long=["out"])], [])),
  ])
  let sc = build_or_fail(def, ec_order())
  inspect(result_str(sc, ["--out", "X", "build"]), content="{out:X,build:{}}")
}

// ── 親背骨の再開: a trailing parent option is eaten after the child closes ──────

///|
test "DR-041 §4 rev: `app build x --rootopt` — build closes, parent resumes and eats --rootopt" {
  // build has no --rootopt trigger, so after consuming its positional `x` build CAN close
  // (nothing readable next) and the parent backbone RESUMES, letting app's --rootopt fire.
  // Under the old sever rule this would have failed (parent permanently off).
  let def = def_cmd([opt("rootopt", TFlag, long=["rootopt"])], [], [
    cmd("build", def_([], [pos("arg", TStr)])),
  ])
  let sc = build_or_fail(def, ec_order())
  inspect(
    result_str(sc, ["build", "x", "--rootopt"]),
    content="{rootopt:true,build:{arg:x}}",
  )
}

// ── recursive emergence: sub has no --out, so build (not app) eats it ───────────

///|
test "DR-041 §4 rev: `app build sub --out X` — sub can't read --out, so build eats it" {
  // Three levels: only app and build declare --out; sub does not. Inside sub, --out is not
  // readable, so sub closes; build's backbone resumes and build's --out fires (build is the
  // innermost scope that CAN read --out). Confirms the emergence is recursive.
  let def = def_cmd([opt("out", TStr, long=["out"])], [], [
    cmd(
      "build",
      def_cmd([opt("out", TStr, long=["out"])], [], [cmd("sub", def_([], []))]),
    ),
  ])
  let sc = build_or_fail(def, ec_order())
  inspect(
    result_str(sc, ["build", "sub", "--out", "X"]),
    content="{build:{out:X,sub:{}}}",
  )
}

// ── second-弾 F-3 global case: unique via early-close, not via sever ────────────

///|
test "DR-041 §4 rev: `build --verbose` (verbose is global) is unique via early-close" {
  // The global copy makes --verbose readable inside build; early-close forbids build from
  // closing before consuming it, so the parent never gets a competing route. This is the
  // former F-3 ambiguity, now resolved by the early-close rule rather than a command sever.
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("build", def_([], []))],
  )
  let sc = build_or_fail(def, ec_order())
  // verbose is now at the ROOT (global is link-sync since 第4弾 Task 1), and build shows as
  // an invoked-but-empty scope. Early-close still makes the parse unique.
  inspect(
    result_str(sc, ["build", "--verbose"]),
    content="{verbose:true,build:{}}",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["build", "--verbose"])),
    content="ok{verbose=true}",
  )
}
