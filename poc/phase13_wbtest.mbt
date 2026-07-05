// phase13_wbtest.mbt — 効果記述子 (DR-045): a value-cell operation is PURE DATA {op, operand?}
// on the effect column, uniform as (entity, op, operand, source, order). The four ops (set /
// default / unset / empty) map 1:1 to DR-011's variant effect vocabulary. committed is DERIVED
// from the op (only unset is uncommitted), which is exactly what splits the value-source ladder.
// Variant entries lower to {exact, link, effect} (LOWERING §B.1, the gap DR-045 §由来 flags).

// ── committed is derived from the op (DR-045 §2) ───────────────────────────────

///|
test "DR-045 §2: committed is derived from the op — only unset is uncommitted" {
  // The committed flag is not stored; it is a pure function of the op. set/default/empty
  // commit (the value is the user's explicit choice / an explicit clear); only unset means
  // "not touched", so the later ladder seats may still fill the cell. This table IS the
  // difference that makes default lock but unset open (DR-045 §2 / DR-031).
  inspect(committed(Set), content="true")
  inspect(committed(Default), content="true")
  inspect(committed(Empty), content="true")
  inspect(committed(Unset), content="false")
}

// ── op is part of the effect identity (DR-045 §1 精密化 / DR-038) ───────────────

///|
test "DR-045/038 精密化: same cell + same value, only the OP differs => distinct (ambiguous)" {
  // Two entries fire on --x and BOTH write x=false; the ONLY difference is the op (set vs
  // unset). DR-045 §1 folds op/operand into the effect-sequence identity, so the two complete
  // paths are genuinely different effects => ambiguous:2. This isolates the op as an identity
  // component: without op in the key these would have merged (same key+value+source).
  let g = scope(
    [
      Seq([Exact("--x"), Bind("x", VBool(false))]), // set x=false
      Seq([Exact("--x"), EffMark("x", Unset)]), // unset x (placeholder value is also false)
    ],
    [],
  )
  inspect(render_outcome(parse(g, ["--x"])), content="ambiguous:2")
}

///|
test "DR-038 contrast: two IDENTICAL effects (same op+value) merge to one path" {
  // The partner of the test above: both entries are `set x=false`. Identical effect reached by
  // two search routes => effect identity merges them to ONE path (not ambiguous). Confirms the
  // split above is caused by the op, not merely by having two entries.
  let g = scope(
    [
      Seq([Exact("--x"), Bind("x", VBool(false))]),
      Seq([Exact("--x"), Bind("x", VBool(false))]),
    ],
    [],
  )
  inspect(render_outcome(parse(g, ["--x"])), content="ok{x=false}")
}

// ── variant lowering: {exact, link, effect} (LOWERING §B.1 / DR-045) ────────────

///|
test "DR-045/LOWERING §B.1: a variant entry lowers to {exact, link (by name), effect}" {
  // ssl is a bool option with a `--no-ssl` variant that UNSETs the cell. The long installer
  // lowers the variant to a greedy satellite Seq([Exact("--no-ssl"), EffMark("ssl", Unset)]):
  // the exact trigger, the link (by-name to the `ssl` cell), and the effect (the unset op).
  // This is the variant form of LOWERING §B.1 — the lowering DR-045 §由来 names as gap G-4/G-5.
  let def = def_(
    [
      opt("ssl", TFlag, long=["ssl"], variants=[
        { trigger: "no-ssl", op: Unset, operand: None },
      ]),
    ],
    [],
  )
  let sc = build_or_fail(def, [LongInst])
  let want = Seq([Exact("--no-ssl"), EffMark("ssl", Unset)])
  let mut found = false
  for g in sc.greedy {
    if g == want {
      found = true
    }
  }
  inspect(found, content="true")
  // and firing --no-ssl produces exactly the unset effect on ssl (0-token after the trigger)
  inspect(effects_str(ScopeNode(sc), ["--no-ssl"]), content="ssl=unset")
}

///|
test "DR-045 set-variant: a set variant carries its operand (the SET degenerate form)" {
  // --gzip is a SET variant of `compress` with operand "gzip": firing it commits compress=gzip.
  // The SET form carries the operand as the Binding value (a value bind IS set, DR-045 §1); this
  // is distinct from the operand-less default/unset/empty forms.
  let def = def_(
    [
      opt("compress", TStr, long=["compress"], variants=[
        { trigger: "gzip", op: Set, operand: Some(VStr("gzip")) },
      ]),
    ],
    [],
  )
  let sc = build_or_fail(def, [LongInst])
  inspect(effects_str(ScopeNode(sc), ["--gzip"]), content="compress=set(gzip)")
}

// ── unset opens the ladder, default locks it (DR-045 §2 / DR-031) ──────────────

///|
test "DR-045 §2: unset opens the ladder (env overrides), set/default commit (env ignored)" {
  // color has an env seat (COLOR) and a default "auto"; --no-color is an UNSET variant and
  // --color-default is a DEFAULT variant. The four cases pin the committed table's ladder
  // effect (DR-045 §2):
  //   --no-color (unset)      => uncommitted => the ladder falls through to env  => always@env
  //   --color red (set)       => committed   => cli wins, env ignored            => red@cli
  //   --color-default (default) => committed to the DEFAULT, LOCKED, env ignored => auto@default
  //   (no color arg)          => nothing on cli => env supplies (same as unset)  => always@env
  // The unset-vs-default contrast is the whole point: both "reset to default", but only unset
  // lets a later seat (env) win.
  let def = def_(
    [
      opt(
        "color",
        TStr,
        long=["color"],
        env=["COLOR"],
        default=Some(VStr("auto")),
        variants=[
          { trigger: "no-color", op: Unset, operand: None },
          { trigger: "color-default", op: Default, operand: None },
        ],
      ),
    ],
    [],
  )
  let sc = build_or_fail(def, [LongInst, EnvInst])
  let env : Map[String, String] = Map::new()
  env.set("COLOR", "always")
  inspect(
    resolve_after_parse(sc, ["--no-color"], env),
    content="color=always@env",
  )
  inspect(
    resolve_after_parse(sc, ["--color", "red"], env),
    content="color=red@cli",
  )
  inspect(
    resolve_after_parse(sc, ["--color-default"], env),
    content="color=auto@default",
  )
  inspect(resolve_after_parse(sc, [], env), content="color=always@env")
}

// ── empty clears a collection (DR-045 empty op) ────────────────────────────────

///|
test "DR-045 empty: an empty variant clears the accumulated collection" {
  // tag is a `multiple` (accumulate) option; --clear-tags is an EMPTY variant. Effects fold in
  // order in the result builder: set a, set b, then EMPTY resets the list to [] — so the result
  // is an empty list. A --tag AFTER the clear re-accumulates on the emptied collection. This is
  // the empty op operating on a collection cell (its committed=true clears deterministically).
  let def = def_(
    [
      opt("tag", TStr, long=["tag"], multiple=true, variants=[
        { trigger: "clear-tags", op: Empty, operand: None },
      ]),
    ],
    [],
  )
  let sc = build_or_fail(def, [LongInst, MultipleInst])
  inspect(
    result_str(sc, ["--tag", "a", "--tag", "b", "--clear-tags"]),
    content="{tag:[]}",
  )
  inspect(
    result_str(sc, ["--tag", "a", "--clear-tags", "--tag", "c"]),
    content="{tag:[c]}",
  )
}
