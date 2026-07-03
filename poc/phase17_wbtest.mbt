// phase17_wbtest.mbt — 失敗時アクション (DR-048) の観測マトリクス。パースは常に完走し、完全経路
// 0 本の失敗時に「候補経路のいずれかで失敗時アクション持ち要素 (help) が selected」なら保持 Error
// に代えて発火する。「候補経路で selected」の精密定義 (DR-048 §5, 未確定 / issue) を 3 案実装し、
// 失敗形ごとの挙動差を観測する。3 案 (FailDef):
//   AcceptsOnly … 候補 = scope-end に到達した Accept のみ (dead end は数えない)
//   WithHeld    … + Error 保持点に到達した経路の partial state も (F-039 失敗時部分状態)
//   DeepestOnly … 最大 argv 消費に到達した候補経路のみ
// 発火は argv 消費位置が最小のもの (先勝ち、DR-048 §4)。dd 内部の --help は 先食い/内部一体で
// selected にならない (DR-041)。

fn fa_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst,
  ]
}

// help フラグ (失敗時アクション、type:"help" プリセット相当) を持つ root scope。
fn help_scope(positionals : Array[ElemDef]) -> Scope {
  let def = def_(
    [opt("help", TFlag, long=["help"], fail_action=true)],
    positionals,
  )
  build_or_fail(def, fa_order())
}

fn out3(sc : Scope, toks : Array[String]) -> (String, String, String) {
  (
    render_outcome(parse(ScopeNode(sc), toks, faildef=AcceptsOnly)),
    render_outcome(parse(ScopeNode(sc), toks, faildef=WithHeld)),
    render_outcome(parse(ScopeNode(sc), toks, faildef=DeepestOnly)),
  )
}

// ── A: help 先行、後方で失敗 → help 発火 (全案一致) ─────────────────────────────

test "DR-048 A: `--help --typo` (help first, fails later) fires help under every candidate def" {
  // help は pos0 で発火し、partial Accept (scope-end at pos1、--typo は消費不能で残る) に selected
  // として現れる。0 完全経路 → 候補経路 (この partial Accept) に help がいるので発火。3 案すべて一致
  // (help は surfaced Accept に載るので AcceptsOnly でも数える)。DR-048 §2 の逐次 exit 相当の観測挙動。
  let sc = help_scope([])
  let (a, b, c) = out3(sc, ["--help", "--typo"])
  inspect(a, content="action:help")
  inspect(b, content="action:help")
  inspect(c, content="action:help")
}

// ── B: 失敗トークンが先 → help 到達不能 → 発火しない (argv 順の効果) ────────────

test "DR-048 B: `--typo --help` (fail token first) does NOT fire — help is unreachable" {
  // 先頭 --typo は消費できる positional が無いので探索が pos0 で詰まり、--help に到達できない → help
  // satellite は一度も発火しない。どの候補定義でも marker が無い → 保持 Error (ここでは Error も無い
  // ので「no complete parse」)。A との対比で argv 順 (到達可能性) が効くことを示す。
  let sc = help_scope([])
  let (a, b, c) = out3(sc, ["--typo", "--help"])
  inspect(a, content="fail:no complete parse")
  inspect(b, content="fail:no complete parse")
  inspect(c, content="fail:no complete parse")
}

// ── C: dd 内部の --help は selected にならない (先食い/内部一体) ─────────────────

test "DR-048 C: `-- --help x` — the dd-internal --help is raw-consumed, so help does NOT fire" {
  // dd (`--`) が発火して以降を内部消費 (raw) にするので、--help は positional の値として食われ、help
  // satellite は発火しない (DR-041 §4 先食い/内部一体)。末尾 x が消費できず失敗するが、help marker は
  // 無いので発火しない。対照: dd 無しの `--help x y` は help が発火する。
  let sc = help_scope([dd_marker(), pos("p", TStr)])
  let (a, b, c) = out3(sc, ["--", "--help", "x"])
  inspect(a, content="fail:no complete parse")
  inspect(b, content="fail:no complete parse")
  inspect(c, content="fail:no complete parse")
  // 対照: 先食いが効く位置 (dd 前) で --help が来れば発火する
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--help", "x", "y"], faildef=WithHeld)),
    content="action:help",
  )
}

// ── D: 複数の失敗時アクション → argv 位置の先勝ち ──────────────────────────────

test "DR-048 D: two failure-actions at different argv positions — the argv-minimal one wins" {
  // help と version の両方が失敗時アクション。両方 selected されたら argv 消費位置が最小のものを発火
  // (先勝ち、DR-048 §4、効果列 = DR-045 の argv 順)。--help が先なら help、--version が先なら version。
  let def = def_(
    [
      opt("help", TFlag, long=["help"], fail_action=true),
      opt("version", TFlag, long=["version"], fail_action=true),
    ],
    [],
  )
  let sc = build_or_fail(def, fa_order())
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--help", "--version", "--typo"], faildef=WithHeld)),
    content="action:help",
  )
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--version", "--help", "--typo"], faildef=WithHeld)),
    content="action:version",
  )
}

// ── E: 深い dead end でのみ selected — 候補定義の分岐点 ────────────────────────

test "DR-048 E: `--help abc` (help fires, then a number positional errors) — the candidate defs DIVERGE" {
  // help は pos0 で発火するが、次の number positional `n` が "abc" のパースに失敗して Held (Error) に
  // なる — この経路は scope-end Accept に到達せず、Held の partial state に help marker が載る (F-039)。
  //   AcceptsOnly … Held は候補に数えない → help 発火せず、保持 Error を表示。
  //   WithHeld    … Held の partial state も候補 → help 発火。
  //   DeepestOnly … 最深 (この Held) が候補 → help 発火。
  // これが「どの partial 経路の selected を数えるか」の分岐点。help-last (`abc --help`) は abc が先に
  // 数値失敗して help に到達しないので、全案で Error (argv 順の対比)。
  let sc = help_scope([pos("n", TNum)])
  let (a, b, c) = out3(sc, ["--help", "abc"])
  inspect(a, content="fail:\"abc\" is not a number") // AcceptsOnly: 保持 Error
  inspect(b, content="action:help") // WithHeld: Held の partial state から発火
  inspect(c, content="action:help") // DeepestOnly: 最深候補から発火
  // help-last: abc が先に数値失敗、help 未到達 → 全案 Error
  let (a2, b2, c2) = out3(sc, ["abc", "--help"])
  inspect(a2, content="fail:\"abc\" is not a number")
  inspect(b2, content="fail:\"abc\" is not a number")
  inspect(c2, content="fail:\"abc\" is not a number")
}

// ── F: 存在量化 — 先食いにより WithHeld と DeepestOnly は実質一致 ────────────────

test "DR-048 F: WithHeld and DeepestOnly agree because 先食い forces help to fire on any deep path" {
  // 「候補経路のいずれかで selected」= 存在量化。help は --help を通過する全経路で必ず発火する (先食い
  // が --help の raw 消費を禁じるので、そこを消費した経路は必ず help satellite を撃つ)。ゆえに「最深候補
  // のみ数える」(DeepestOnly) と「Held 含む全候補」(WithHeld) は実質一致する — help を撃たずに深く進む
  // 候補が存在しないため。両者が割れるのは AcceptsOnly (surfaced Accept のみ、dead end を無視) との間だけ、
  // というのが本マトリクスの主要な観測。E で b==c、a のみ割れることがその実測。
  let sc = help_scope([pos("n", TNum)])
  let (a, b, c) = out3(sc, ["--help", "abc"])
  inspect(b == c, content="true") // WithHeld == DeepestOnly
  inspect(a == b, content="false") // AcceptsOnly は割れる
}
