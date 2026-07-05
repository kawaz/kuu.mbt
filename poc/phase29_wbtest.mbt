// phase29_wbtest.mbt — DR-070 §1b 既知 gap 台帳の解消確認 (gap 2 / 4 / 5 + dd name default DR-064 §5).
// 各テストは「解消された挙動」を仕様の輪郭として固定する (= 真の仕様書、tdd-and-test-design)。
//   gap 2  主入口 `:set` → 名前由来 --<kebab(name)> 生成 (LOWERING §B.1 / DR-071) + snake→kebab (DR-022)
//   DR-064 §5  dd の name デフォルト "--" (省略時供給) + name はトリガ綴り軸 (方言 CLI で上書き可)
//   gap 4  dd を options[] に置いても余分な `--` 実体を生成しない (not_dd ガード、DR-064 §2 配置不問)
//   gap 5  global コピー要素は子スコープに自前 entity を作らない (Rooted link は root セルへ解決)

fn p29_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst,
  ]
}

// ── gap 2: 主入口 `:set` は --<name> を生成する (LOWERING §B.1 / DR-071) ──────────

test "gap2 LOWERING §B.1 / DR-071: the `:set` main-entry descriptor generates the name-derived --<name> trigger" {
  // DR-071 二形 long: 主入口は `long=[":set"]` で書く (= 仕様の `long: true` 糖衣、absent = false = [] は入口なし)。
  // normalize_surface が `:set` を kebab(name)=`v` へ展開し、long installer が --v を植える。
  // fires: --v → v=true。unfired: v は preset default false (LOWERING §A.5 / DR-051 §2、gap 1)。
  let sc = build_or_fail(def_([opt("v", TFlag, long=[":set"])], []), [LongInst])
  inspect(result_str(sc, ["--v"]), content="{v:true}")
  inspect(result_str(sc, []), content="{v:false}")
}

test "gap2 DR-022: a snake_case name lowers its long trigger to kebab-case (--dry-run, not --dry_run)" {
  // name は snake_case が正規形 (AST キー、DR-022)。主入口 `:set` の名前由来綴りは CLI 慣習の
  // kebab-case に変換される (`dry_run` → `--dry-run`)。結果キーは name のまま snake (dry_run)。
  let sc = build_or_fail(def_([opt("dry_run", TFlag, long=[":set"])], []), [LongInst])
  inspect(result_str(sc, ["--dry-run"]), content="{dry_run:true}") // kebab トリガが発火
  // snake 綴りの --dry_run は生成されていない → 消費できず失敗 (トリガは --dry-run のみ)
  inspect(render_outcome(parse(ScopeNode(sc), ["--dry_run"])), content="fail:unexpected token")
}

test "gap2 DR-071: an EXPLICIT long spelling passes through normalize as-is (only `:set` is name-derived)" {
  // 明示綴り long=["v"] は `:set` ではないので normalize は kebab 展開せずそのまま通す (--v)。二形 long の
  // 「`:set` = 名前由来、それ以外 = 明示綴り」の分岐を固定 (DR-071)。
  let sc = build_or_fail(def_([opt("verbose", TFlag, long=["v"])], []), [LongInst])
  inspect(result_str(sc, ["--v"]), content="{verbose:true}")
}

// ── DR-064 §5: dd の name デフォルト "--" + name = トリガ綴り軸 ─────────────────

test "DR-064 §5: a dd with an OMITTED name defaults its trigger spelling to `--`" {
  // 名前を省いた dd ({..dd_marker(), name:""}) は normalize_surface が name="--" を供給する。lowered 形
  // (G[DdSat(--)]) は明示 name="--" の dd_marker() と完全に同一 = 既定 canonical と同じ。
  let sc_omitted = build_or_fail(def_([{ ..dd_marker(), name: "" }], [pos("x", TStr)]), [DdInst])
  let sc_explicit = build_or_fail(def_([dd_marker()], [pos("x", TStr)]), [DdInst])
  inspect(canon_scope(sc_omitted) == canon_scope(sc_explicit), content="true")
}

test "DR-064 §5: an EXPLICIT dd name overrides the trigger spelling (方言 CLI 綴り差し替え)" {
  // name はトリガ綴り軸にのみ効く (DR-064 §5)。dd name="++" は DdSat("++") を植え、`++` が severs する。
  // `--` は普通の positional トークンとして x に食われる (dd トリガではない)。
  let sc = build_or_fail(def_([{ ..dd_marker(), name: "++" }, opt("a", TFlag, short=['a'])], [pos("x", TStr)]), [LongInst, ShortInst, DdInst])
  // ++ が severs: 以降の -b は raw で x に落ちる (basic case 1 と同型、綴りだけ ++)。a は発火し true、
  // 未発火なら preset default false。
  inspect(result_str(sc, ["-a", "++", "-b"]), content="{a:true,x:-b}")
}

// ── gap 4: dd を options[] に置いても余分な `--` 実体を生成しない (not_dd ガード) ──

test "gap4 DR-064 §2: dd in options[] mints NO `--` entity (placement-agnostic lowered form)" {
  // ensure_entities の options ループに not_dd ガードを追加。dd を options[] に置いても `--` 実体は
  // 生成されない (LOWERING §B.4「値なし」)。実体は positional x のみ。
  let sc_opt = build_or_fail(def_([dd_marker()], [pos("x", TStr)]), [DdInst])
  inspect(entity_exists(sc_opt, "--"), content="false") // dd は値セルを持たない
  inspect(entity_exists(sc_opt, "x"), content="true") // positional は実体を持つ
  // 対称性: positionals[] 配置でも同じく `--` 実体なし (旧: options 配置のみ余分に生成する非対称)
  let sc_pos = build_or_fail(def_([], [{ ..dd_marker() }, pos("x", TStr)]), [DdInst])
  inspect(entity_exists(sc_pos, "--"), content="false")
  inspect(canon_scope(sc_opt) == canon_scope(sc_pos), content="true") // 配置不問で lowered 形が同一
}

// ── gap 5: global コピー要素は子スコープに自前 entity を作らない ──────────────────

test "gap5: a global option's link COPY creates NO own entity in the child command scope" {
  // global verbose は build コマンド子スコープへ link コピー (is_link) される。子スコープの entity は
  // 作らない — Rooted 衛星が root の verbose セルへ解決するため (DR-042 link-sync)。値セルは root のみ。
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("build", def_([], []))],
  )
  let sc = build_or_fail(def, p29_order())
  inspect(entity_exists(sc, "verbose"), content="true") // root にセルが 1 個
  let child = match command_child(sc, "build") {
    Some(c) => c
    None => abort("no build child")
  }
  inspect(entity_exists(child, "verbose"), content="false") // 子スコープに自前セルは無い
  // 観測挙動は不変 (第 8 弾 2b): build --verbose も --verbose build も root セルへ同期 (build:{} = 子空)
  inspect(result_str(sc, ["build", "--verbose"]), content="{verbose:true,build:{}}")
  inspect(result_str(sc, ["--verbose", "build"]), content="{verbose:true,build:{}}")
}
