// phase19_wbtest.mbt — 第 8 弾: 3 段以上の中間 shadowing の name-vs-trigger 微差 (DR-042 検証マトリクス
// 最終独立項目)。root global 要素が、中間 command で shadow された場合、孫 command にコピーが届くかを
// 3 ケース (別 name・同 literal / 同 name・同 literal / 同 name・別 literal) × 2 発火位置で観測し、
// DR-042 の shadowing 文言が読み A (各スコープ独立判定) / 読み B (伝播断ち) の両方を許すかを検出する。

///|
fn p19_order() -> Array[Installer] {
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

// root(global verbose) -> mid(中間宣言) -> sub(無宣言) の 3 段木を組む。

///|
fn tree3(mid_opts : Array[ElemDef]) -> Scope {
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("mid", def_cmd(mid_opts, [], [cmd("sub", def_([], []))]))],
  )
  build_or_fail(def, p19_order())
}

// ── ケース 1: 別 name・同 literal (中間 chatty=--verbose, 非 global) ─────────────

///|
test "DR-042 3段 case1: middle shadows with DIFFERENT name + SAME trigger (--verbose)" {
  // root global verbose (--verbose)、mid が chatty (別 name・同トリガ --verbose、非 global) を自前宣言、
  // sub は無宣言。DR-042 の shadow はトリガ literal 判定なので mid で root コピーが止まる。問題は孫 sub に
  // root コピーが届くか: 読み A (独立判定→届く) vs 読み B (伝播断ち→届かない)。PoC は is_global コピーの
  // level-by-level 伝播で、mid で止まったコピーは再伝播元にならない = **読み B**。よって sub は verbose 入口
  // を持たず、--verbose は sub 閉じ→mid 再開で mid の chatty に読まれる (最内 reader、早閉じ抑制)。
  let sc = tree3([opt("chatty", TFlag, long=["verbose"])])
  // 孫スコープで発火: sub は verbose を持たない → mid の chatty が拾う (root verbose でも sub コピーでもない)
  // root の global verbose は発火せず preset default false で現れる (LOWERING §A.5 / DR-051 §2)。
  // chatty:true が「root verbose ではなく mid の chatty が読んだ」ことを示す本質は不変 (旧値は preset
  // default 未実装時代の凍結で root verbose が absent だった)。
  inspect(
    result_str(sc, ["mid", "sub", "--verbose"]),
    content="{mid:{chatty:true,sub:{}},verbose:false}",
  )
  // 中間スコープで発火: mid の chatty が直接拾う
  inspect(
    result_str(sc, ["mid", "--verbose", "sub"]),
    content="{mid:{chatty:true,sub:{}},verbose:false}",
  )
}

// ── ケース 2: 同 name・同 literal (中間 verbose=--verbose, 非 global) = 通常 shadow の 3 段版 ──

///|
test "DR-042 3段 case2: middle shadows with SAME name + SAME trigger (normal shadow)" {
  // 第 2 弾の通常 shadow (同 name・同トリガ) の 3 段版。mid が verbose (--verbose、非 global) を自前宣言。
  // ケース 1 と構造は同型 (トリガ判定で mid が止める)、違いは mid の要素名が verbose なこと。孫 sub は
  // やはり verbose 入口を持たず、mid の verbose が拾う → shadow がトリガ判定 (名前非依存) であることの確認。
  let sc = tree3([opt("verbose", TFlag, long=["verbose"])])
  // root global verbose は未発火 → preset default false。mid の自前 verbose が --verbose を拾う (shadow)。
  inspect(
    result_str(sc, ["mid", "sub", "--verbose"]),
    content="{mid:{verbose:true,sub:{}},verbose:false}",
  )
  inspect(
    result_str(sc, ["mid", "--verbose", "sub"]),
    content="{mid:{verbose:true,sub:{}},verbose:false}",
  )
}

// ── ケース 3: 同 name・別 literal (中間 verbose=--chatty, 非 global) = トリガ非衝突 ──────

///|
test "DR-042 3段 case3: middle has SAME name but DIFFERENT trigger (--chatty) — no trigger collision" {
  // mid が verbose (名前は重なるがトリガは --chatty、非 global) を宣言。DR-042 の shadow 判定はトリガ
  // literal なので --chatty と --verbose は衝突しない → root の verbose コピー (--verbose) は mid に入り、
  // is_global を保って sub へも伝播する (通常伝播)。名前が重なるだけでは shadow しないことの確認。
  let sc = tree3([opt("verbose", TFlag, long=["chatty"])])
  // 孫で --verbose 発火: sub に届いた root コピー (Rooted link) が root verbose セルへ → root キーに現れる。
  // mid の自前 verbose (トリガ --chatty) は未発火 → mid スコープに preset default false (LOWERING §A.5)。
  inspect(
    result_str(sc, ["mid", "sub", "--verbose"]),
    content="{verbose:true,mid:{sub:{},verbose:false}}",
  )
  // 中間で --verbose 発火: mid のコピー (Rooted link) が root verbose セルへ
  inspect(
    result_str(sc, ["mid", "--verbose", "sub"]),
    content="{verbose:true,mid:{sub:{},verbose:false}}",
  )
  // mid の own トリガ --chatty は mid の verbose セル (別入口・別セル、link でない)。root verbose は未発火 → false。
  inspect(
    result_str(sc, ["mid", "--chatty", "sub"]),
    content="{mid:{verbose:true,sub:{}},verbose:false}",
  )
}
