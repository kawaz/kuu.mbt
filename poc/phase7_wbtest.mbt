// phase7_wbtest.mbt — layer 3: the name-driven result builder + the shared
// accumulator (DR-016 / DR-025 / DR-034 / DR-043). A name/command scope nests; a
// repeat or `multiple` cell folds its several same-key bindings into a value list.
// This is where repeat's flattening accumulator meets the result builder.

fn order7plus() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst,
  ]
}

// ── Task 5: multiple folds repeated firings into a list (append) ───────────────

test "DR-034/043 multiple: repeated firings of a `multiple` option collect into a list" {
  // --tag fires twice; the cell accumulates [a, b] rather than last-wins. `multiple`
  // is the value-fold installer; the accumulator is a plain append (DR-036).
  let def = def_([opt("tag", TStr, long=["tag"], multiple=true)], [])
  let sc = build_or_fail(def, order7plus())
  inspect(result_str(sc, ["--tag", "a", "--tag", "b"]), content="{tag:[a,b]}")
  // one firing still yields a (single-element) list — the cell's shape is list
  inspect(result_str(sc, ["--tag", "a"]), content="{tag:[a]}")
}

test "DR-015 contrast: a non-accumulator option is scalar (last-wins), not a list" {
  // Without `multiple`, firing --name twice is last-wins (DR-015), a scalar — proving
  // the list shape comes from the accumulator, not from repetition per se.
  let def = def_([opt("name", TStr, long=["name"])], [])
  let sc = build_or_fail(def, order7plus())
  inspect(result_str(sc, ["--name", "a", "--name", "b"]), content="{name:b}")
}

// ── Task 7: name scope nests the result (DR-025) ───────────────────────────────

test "DR-025: a subcommand nests its result under the command name" {
  // `serve --port 80` produces a nested { serve: { port: 80 } }: the command scope is
  // a result scope, so port lands one level deep.
  let def = def_cmd([], [], [
    cmd("serve", def_([opt("port", TNum, long=["port"])], [])),
  ])
  let sc = build_or_fail(def, order7plus())
  inspect(result_str(sc, ["serve", "--port", "80"]), content="{serve:{port:80}}")
}

// ── Task 7: repeat's flattening accumulator, through the result builder ─────────

test "DR-043: repeat's several same-key bindings flatten into one list in the result" {
  // `cp a b c` binds src twice (a, b) and dst once; the src cell accumulates [a, b]
  // while dst stays scalar. This is the flattening accumulator meeting the builder.
  let def = def_([], [pos("src", TStr, repeat=rep(1)), pos("dst", TStr)])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, order7plus(), reg)
  inspect(result_str(sc, ["a", "b", "c"], defs=reg), content="{src:[a,b],dst:c}")
}

test "DR-025/043: a repeat inside a named command scope nests AND flattens" {
  // `serve --host h a b`: host is a scalar option, file is a repeat positional; both
  // nest under serve, and file flattens to a list => { serve: { host: h, file: [a,b] } }.
  let def = def_cmd([], [], [
    cmd(
      "serve",
      def_([opt("host", TStr, long=["host"])], [pos("file", TStr, repeat=rep(1))]),
    ),
  ])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, order7plus(), reg)
  inspect(
    result_str(sc, ["serve", "--host", "h", "a", "b"], defs=reg),
    content="{serve:{host:h,file:[a,b]}}",
  )
}

// ── Task 7: multiple × repeat compose (two accumulators, one result) ───────────

test "DR-034/043: a multiple option and a repeat positional both accumulate in one result" {
  // --tag is a multiple option; src is a repeat positional. Both fold to lists,
  // independently, in the same result object.
  let def = def_(
    [opt("tag", TStr, long=["tag"], multiple=true)],
    [pos("src", TStr, repeat=rep(1))],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, order7plus(), reg)
  inspect(
    result_str(sc, ["--tag", "x", "a", "--tag", "y", "b"], defs=reg),
    content="{tag:[x,y],src:[a,b]}",
  )
}
