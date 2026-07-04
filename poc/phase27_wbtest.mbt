// phase27_wbtest.mbt — 第 17 弾: inheritable × long (DR-059) — DR-042 検証マトリクス最後の未実施組。
// inheritable 要素の祖先スコープ綴りは `<定義スコープ名>-<name>` の固定 prefix (socket 配下の ttl →
// --socket-ttl)、全祖先で同綴り (深さで変わらない)。lowering は inheritable installer が祖先スコープの
// 宣言層へ prefix 付き入口宣言をコピー (global の逆方向、祖先の自前トリガ優先)。値の意味論: 各スコープで
// 書かれた値がその配下インスタンスのデフォルトに (inherit 席 DR-031 と対) — チェーンの全 ttl セルに
// inherit 席を張り、任意レベルの書き込みが下流へ流れる。衝突は実行時 ambiguous、別綴りは alias。

fn p27_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst, ConstraintInst, AliasInst, InheritableInst,
  ]
}

// ── 1. 基本形: 自スコープ --ttl / 祖先スコープ --sub-ttl の両方が効く ─────────────

test "DR-059 §1: an inheritable element is --ttl in its own scope and --sub-ttl in the ancestor" {
  // `ttl` is inheritable in the `sub` command scope. Its own scope spelling is --ttl; the inheritable
  // installer copies a prefixed write-entry --sub-ttl (定義スコープ名 sub) into the root (ancestor)
  // scope, keyed by the `ttl` cell. Both `sub --ttl 30` and `--sub-ttl 30 sub` bind a ttl cell.
  let def = def_cmd(
    [],
    [],
    [cmd("sub", def_([opt("ttl", TNum, long=["ttl"], inheritable=true, default=Some(VNum(60)))], []))],
  )
  let sc = build_or_fail(def, p27_order())
  inspect(result_str(sc, ["sub", "--ttl", "30"]), content="{sub:{ttl:30}}") // 自スコープ --ttl
  inspect(result_str(sc, ["--sub-ttl", "30", "sub"]), content="{ttl:30,sub:{}}") // 祖先スコープ --sub-ttl
}

// ── 2. 全祖先同綴り: 3 段 (root > mid > sub) で root も mid も --sub-ttl ────────────

test "DR-059 §1: the ancestor spelling is the same --sub-ttl at every ancestor depth (no lengthening)" {
  // 3-level root > mid > sub, ttl inheritable in sub. The prefix is the DEFINING scope name (sub), so
  // BOTH root and mid spell it --sub-ttl (not --mid-sub-ttl at root — §採用しなかった案: 深さで延ばさない).
  let def = def_cmd(
    [],
    [],
    [
      cmd(
        "mid",
        def_cmd(
          [],
          [],
          [cmd("sub", def_([opt("ttl", TNum, long=["ttl"], inheritable=true, default=Some(VNum(60)))], []))],
        ),
      ),
    ],
  )
  let sc = build_or_fail(def, p27_order())
  inspect(result_str(sc, ["--sub-ttl", "30"]), content="{ttl:30}") // root レベルで --sub-ttl
  let mid = match command_child(sc, "mid") {
    Some(c) => c
    None => abort("no mid child")
  }
  inspect(result_str(mid, ["--sub-ttl", "30"]), content="{ttl:30}") // mid レベルでも同じ --sub-ttl
}

// ── 3. 値の意味論: 祖先書き込みが配下のデフォルト、自スコープ CLI が勝つ ────────────

test "DR-059 §3: an ancestor-written value is the descendant default; the descendant's own CLI wins" {
  // The value written at any level flows DOWN as the descendant instance's default (inherit 席 の対).
  // Resolve scope-by-scope (as DR-031 inherit tests do): the sub cell's ladder is cli > env > inherit
  // (ancestor-written) > default. Ancestor writes 30 → sub inherits 30; sub's own --ttl 10 beats it;
  // no write anywhere → sub's own default 60.
  let def = def_cmd(
    [],
    [],
    [cmd("sub", def_([opt("ttl", TNum, long=["ttl"], inheritable=true, default=Some(VNum(60)))], []))],
  )
  let sc = build_or_fail(def, p27_order())
  let sub = match command_child(sc, "sub") {
    Some(c) => c
    None => abort("no sub child")
  }
  let empty : Map[String, String] = Map::new()
  // ancestor writes ttl=30 (via --sub-ttl); sub unspecified → sub inherits 30
  let root_write = resolve_scope(sc, [mkb("ttl", VNum(30), Cli)], empty)
  inspect(
    render_binds_src(resolve_scope(sub, [], empty, inherited=inherited_of(root_write))),
    content="ttl=30@inherit",
  )
  // sub's own --ttl 10 beats the ancestor default
  inspect(
    render_binds_src(resolve_scope(sub, [mkb("ttl", VNum(10), Cli)], empty, inherited=inherited_of(root_write))),
    content="ttl=10@cli",
  )
  // no write anywhere → the ancestor write-target has NO default (absent), so sub falls to its own 60
  let root_none = resolve_scope(sc, [], empty)
  inspect(
    render_binds_src(resolve_scope(sub, [], empty, inherited=inherited_of(root_none))),
    content="ttl=60@default",
  )
}

// ── 4. 自前優先 shadow: 祖先が同 literal のトリガを自前で持つ → コピーされない ──────

test "DR-059 §3: an ancestor's own --sub-ttl trigger shadows the inheritable copy (自前優先)" {
  // The root declares its OWN option `other` triggering --sub-ttl. Symmetric to global shadowing: the
  // inheritable copy is NOT added, so --sub-ttl at the root binds `other`, not the ttl write-target.
  let def = def_cmd(
    [opt("other", TStr, long=["sub-ttl"])],
    [],
    [cmd("sub", def_([opt("ttl", TNum, long=["ttl"], inheritable=true, default=Some(VNum(60)))], []))],
  )
  let sc = build_or_fail(def, p27_order())
  inspect(result_str(sc, ["--sub-ttl", "hello"]), content="{other:hello}") // 祖先の自前が食う
}

// ── 5. installer 順列一致: inheritable の逆方向コピーが不動点反復に乗る ─────────────

test "DR-059/DR-042: the inheritable reverse-copy converges identically regardless of installer order" {
  // The descendant→ancestor copy is add-if-absent and expanded by long in the fixpoint (global の逆方向).
  // Building with InheritableInst early vs late yields the identical AtomicAST tree (canon_scope recurses
  // the command subtree, so both the ancestor copy and the sub scope are in the compared form).
  let def = def_cmd(
    [],
    [],
    [cmd("sub", def_([opt("ttl", TNum, long=["ttl"], inheritable=true, default=Some(VNum(60)))], []))],
  )
  let early = canon_scope(build_or_fail(def, [InheritableInst, LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst, RepeatInst, MultipleInst, ConfigInst, ConstraintInst, AliasInst]))
  let late = canon_scope(build_or_fail(def, p27_order()))
  inspect(early == late, content="true")
}

// ── 6. long installer との合成 (マトリクスの本命): eq-split も効く ─────────────────

test "DR-059/DR-042: the prefixed --sub-ttl composes with the long installer (space AND eq-split forms)" {
  // The ancestor copy is a plain long option, so the long installer gives it BOTH the space-form
  // satellite (--sub-ttl 30) AND the eq-split matcher (--sub-ttl=30) — the DR-042 matrix's本命 (long ×
  // inheritable). This is the whole point of "lowering は入口 installer が展開" (§3).
  let def = def_cmd(
    [],
    [],
    [cmd("sub", def_([opt("ttl", TNum, long=["ttl"], inheritable=true, default=Some(VNum(60)))], []))],
  )
  let sc = build_or_fail(def, p27_order())
  inspect(result_str(sc, ["--sub-ttl", "30"]), content="{ttl:30}") // space form
  inspect(result_str(sc, ["--sub-ttl=30"]), content="{ttl:30}") // eq-split form (long installer)
}
