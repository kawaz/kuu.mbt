// phase23_wbtest.mbt — 第 13 弾: パース結末の構造 (DR-053)。outcome 3 値の discriminated union。
// failure の errors は全保持配列 {element, argv_pos, kind: parse|filter|constraint, message}、primary =
// argv 位置最深 (同深は全て)。ambiguous は全解釈列挙 (各解釈は結果オブジェクト形ビュー)。help_entry /
// tried_triggers はフィールド (文言はレンダラ)。fired_action と errors は両立 (発火しても errors は残る)。

fn p23_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst,
  ]
}

// ── 1. errors 全保持 + primary = argv 最深 ─────────────────────────────────────

test "DR-053 §2: multiple candidate paths fail at different positions — ALL kept, deepest is primary" {
  // Two interpretations of `x y`: (A) `a` (number) fails on `x` at pos 0; (B) `s` (string) eats `x`,
  // then `b` (number) fails on `y` at pos 1. Both held Errors are retained (別候補経路の別 Error);
  // primary = the max-argv_pos error (pos 1, the furthest-progressed interpretation's stumble).
  let sc : Scope = {
    greedy: [],
    positional: [Or([Seq([NumArg("a")]), Seq([StrArg("s"), NumArg("b")])])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(sc), ["x", "y"])
  inspect(errors_str(o), content="a@0/parse,b@1/parse") // 全保持
  inspect(primary_str(o), content="b@1/parse") // primary = argv 最深
}

test "DR-053 §2: two errors at the SAME argv position are BOTH primary (同深タイ)" {
  // Two number interpretations both fail on `x` at pos 0. Same depth → both are primary.
  let sc : Scope = {
    greedy: [],
    positional: [Or([NumArg("a"), NumArg("b")])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(sc), ["x"])
  inspect(errors_str(o), content="a@0/parse,b@0/parse")
  inspect(primary_str(o), content="a@0/parse,b@0/parse") // 同深は全て primary
}

// ── 2. kind 3 値: parse / filter / constraint ──────────────────────────────────

test "DR-053 §2 kind 3値: parse (型不一致) / filter (post_filter reject) / constraint (required 未充足)" {
  // parse: a number positional on a non-number token → kind:parse.
  let sc_p : Scope = { greedy: [], positional: [NumArg("n")], entities: [], constraints: [] }
  inspect(errors_str(parse(ScopeNode(sc_p), ["x"])), content="n@0/parse")
  // filter: a value that PARSES but exceeds a max post-filter → kind:filter (DR-034 filter reject).
  let sc_f : Scope = { greedy: [], positional: [FilterArg("port", 1000)], entities: [], constraints: [] }
  inspect(errors_str(parse(ScopeNode(sc_f), ["5000"])), content="port@0/filter")
  // constraint: a required positional with no token → kind:constraint (DR-047 値充足 違反).
  let sc_c : Scope = { greedy: [], positional: [ReqArg("file")], entities: [], constraints: [] }
  inspect(errors_str(parse(ScopeNode(sc_c), [])), content="file@0/constraint")
}

// ── 3. ambiguous interpretations (結果オブジェクト形ビュー) ──────────────────────

test "DR-053 §3: an ambiguous parse enumerates every interpretation as a result-object view" {
  // `-n1.0f`: value-attach n="1.0f" (n=1) vs split n="1.0" (n=1) + `-f` flag. Two structurally
  // different interpretations, each a result view — the f-marker makes both parse (DR-038 例).
  let short = NativeMatch(
    ShortCombine(prefix="-", entries=[
      { ch: 'n', name: "n", kind: TNum, depr: false },
      { ch: 'f', name: "f", kind: TFlag, depr: false },
    ]),
  )
  let g = scope([short], [])
  let o = parse(g, ["-n1.0f"])
  inspect(render_outcome(o), content="ambiguous:2")
  inspect(interps_str(o), content="[{n:1,f:true},{n:1}]")
}

// ── 4. fired_action と errors の両立 + primary(最深) vs action(最小) の共存 ──────

test "DR-053 §2: a fired failure-action coexists with retained errors; primary(最深) vs action(最小)" {
  // `--help abc`: help fires (fired_action, the argv-MINIMAL intent — DR-048), AND the number
  // positional `n` fails on `abc` at pos 1 (the retained error, primary = argv-MAXIMAL stumble). The
  // opposite argv directions (action = 最初の意図, primary = 最深の躓き) coexist in one Failure — 表示が
  // アクションに置換されても errors は構造として残る (DR-053 §2).
  let sc = help_scope([pos("n", TNum)])
  let o = parse(ScopeNode(sc), ["--help", "abc"], faildef=WithHeld)
  inspect(fired_of(o), content="help") // fired_action = help (argv 最小)
  inspect(errors_str(o), content="n@1/parse") // errors は残る
  inspect(primary_str(o), content="n@1/parse") // primary = argv 最深 (pos 1)
}

// ── 5. help_entry / tried_triggers (誘導行 / Did you mean の素材) ────────────────

test "DR-053 §4: help_entry (綴り) and tried_triggers (試行 exact 群) ride the failure" {
  // A def with a help entry (--help) and another trigger (--verbose), plus a number positional. On a
  // failure, help_entry carries the help spelling (誘導行の素材) and tried_triggers carries the exact
  // triggers (Did you mean の素材 — 近接マッチ計算は DX 層、素材のみ、F-016).
  let def = def_(
    [
      opt("help", TFlag, long=["help"], fail_action=true),
      opt("verbose", TFlag, long=["verbose"]),
    ],
    [pos("n", TNum)],
  )
  let sc = build_or_fail(def, p23_order())
  let o = parse(ScopeNode(sc), ["--typo"], faildef=WithHeld)
  inspect(help_of(o), content="--help") // help_entry の綴り
  inspect(tried_of(o), content="--help,--verbose") // 試行された exact 綴り群
}
