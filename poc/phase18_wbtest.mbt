// phase18_wbtest.mbt — 第 7 弾 (小粒 2 件):
//  (1) 失敗時アクションの発火条件は完全経路 0 本のみ、ambiguous では発火しない (DR-048 確定文言)
//  (2) link-to-same-cell の複数入口が別トークンで同時発火した効果合流 (DR-042 検証マトリクス、
//      DR-015 あと勝ち + DR-045 効果列順序保存)

///|
fn p18_order() -> Array[Installer] {
  [
    LongInst,
    ShortInst,
    EnvInst,
    DdInst,
    CommandInst,
    GlobalInst,
    InheritInst,
    RepeatInst,
    MultipleInst,
  ]
}

// ── タスク 1: ambiguous 非発火の輪郭固定 (DR-048 §2) ────────────────────────────

///|
test "DR-048: ambiguous does NOT fire the failure-action even though help is selected on both paths" {
  // help (fail_action) の後に、同一トリガ --v が別実体 a / b を束縛する 2 エントリを並べる。`--help --v`
  // は help を撃った後 --v で 2 本の完全経路 ({help,a} と {help,b}) に分岐する = ambiguous:2。help は
  // 両経路で selected だが、DR-048 の発火条件は「完全経路 0 本のみ」なので発火せず ambiguous のまま。
  // 判断本質: ambiguous の本体は競合解釈の提示であり、大きな help でエラー内容を画面から流さない
  // (0 本失敗 = 使い方不明 → help が有益 / ambiguous = どの解釈か明確化したい → エラーが本体、DR-048)。
  let g = scope(
    [
      Seq([Exact("--help"), Bind("help", VBool(true)), FailMark("help")]),
      flag("--v", "a"),
      flag("--v", "b"),
    ],
    [],
  )
  // help selected + 2 完全経路 → ambiguous (NOT action:help)
  inspect(render_outcome(parse(g, ["--help", "--v"])), content="ambiguous:2")
  // 対照: 同じ定義で 0 本失敗 (--x は未定義で消費不能) → 完全経路 0 本 → help 発火
  inspect(render_outcome(parse(g, ["--help", "--x"])), content="action:help")
}

// ── タスク 2: link 合流 — 別トークン同時発火 (DR-042 / DR-015 / DR-045) ─────────

///|
test "DR-042/015 link 合流: long と short が同一セルへ別トークンで発火 — あと勝ち + 効果列順序保存" {
  // port は long=--port と short=-p の 2 入口が同一実体セルへ link する (link 合流 = 同名実体)。
  // `--port 80 -p 90` は両入口が別トークンでそれぞれ発火し、効果 [port=80, port=90] が 1 セルへ積まれる。
  // scalar なので結果はあと勝ち (DR-015、argv 順で最後 = 90)。ambiguous でない正常系の合流 (1 完全経路)。
  let def = def_([opt("port", TNum, long=["port"], short=['p'])], [])
  let sc = build_or_fail(def, p18_order())
  // 効果列は消費順に保存される (port=80 が先、port=90 が後)
  inspect(
    ordered_effects(ScopeNode(sc), ["--port", "80", "-p", "90"]),
    content="port=80,port=90",
  )
  // 結果セルはあと勝ち (最後の効果 90)
  inspect(result_str(sc, ["--port", "80", "-p", "90"]), content="{port:90}")
  // 順序を反転すれば あと勝ちも反転 (効果列順序が最終値を決める)
  inspect(
    ordered_effects(ScopeNode(sc), ["-p", "90", "--port", "80"]),
    content="port=90,port=80",
  )
  inspect(result_str(sc, ["-p", "90", "--port", "80"]), content="{port:80}")
}

///|
test "DR-042 link-sync 合流: global の root 入口と command 内コピーが別トークンで発火 — あと勝ち" {
  // out は global。root の入口と build command 内へ link コピーされた入口の 2 つが、同一 argv 内の別
  // トークンで発火する。両方 root の out セルへ link 同期 (Rooted) するので、effect [out=A, out=B] が
  // root セルへ合流し あと勝ち (B)。build は起動された空スコープ {} として現れる (第 4 弾 link-sync)。
  // これは DR-042 検証マトリクスの「link 合流の別トークン同時発火」= 複数スコープからの合流の実測。
  let def = def_cmd([opt("out", TStr, long=["out"], global=true)], [], [
    cmd("build", def_([], [])),
  ])
  let sc = build_or_fail(def, p18_order())
  // root で out=A、build 内で out=B → root セルへ合流、あと勝ち B
  inspect(
    result_str(sc, ["--out", "A", "build", "--out", "B"]),
    content="{out:B,build:{}}",
  )
  // 順序反転: root で out=B、build 内で out=A → あと勝ち A (効果列順序が効く)
  inspect(
    result_str(sc, ["--out", "B", "build", "--out", "A"]),
    content="{out:A,build:{}}",
  )
}
