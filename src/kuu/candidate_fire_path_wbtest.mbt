// candidate_fire_path_wbtest.mbt — DR-066 §4 の fire_path 純度の pin
// (docs/issue/2026-08-12-completion-query-residual-minors.md の RE-3)。
//
// `nest_cands` (eval.mbt) は Pending 候補の fire_path を、枝が scope 境界を抜けるたびに
// **無条件 prepend** する規約になっている。conformance の
// `command-scope/global-missing-operand-path.json` は global option (Rooted-escape) の
// starve でこの規約を pin しているが、**seq / repeat の内部で値スロットが starve した候補**は
// 未 pin だった。破れると帰属 scope が浅い側へずれ、help model 照合が外れて説明が付かなく
// なる (fail-closed) — 実害は小さいが劣化を黙認する形なので、ここで固定する。
//
// 観測点は missing_operand の ParseError.path — starve した候補が `parse_tree` 境界で
// ParseError へ変換される唯一の場所で、その path は候補の fire_path そのもの。
// 期待値はすべて現行実装の実測値 (推測ではない)。

///|
fn starved_operand_path(
  ast : AtomicAST,
  argv : Array[String],
  element : String,
) -> Array[String]? {
  match parse_legacy(ast, argv) {
    @engine.Failure(failure) => {
      for error in failure.errors {
        if error.element == element && error.reason == "missing_operand" {
          return Some(error.path)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn assert_path_eq(
  actual : Array[String]?,
  want : Array[String],
  msg : String,
) -> Unit raise {
  match actual {
    Some(path) => {
      assert_eq(path.length(), want.length(), msg~)
      for i = 0; i < want.length(); i = i + 1 {
        assert_eq(path[i], want[i], msg~)
      }
    }
    None => fail(msg + " (missing_operand が出ていない)")
  }
}

///|
/// 保証 (DR-066 §4): コマンドスコープ配下の **名前付き seq 内部** で値スロットが starve した
/// 候補は、発火時の walk 位置を保つ — コマンド境界と、名前付き seq 自身の結果スコープの
/// 両方が path に積まれる。浅い側 ([a] だけ) へ潰れない。
test "fire_path: seq 内部の starve は seq スコープまで含む walk 位置を保つ (RE-3)" {
  let src =
    #|{"commands":[{"type":"command","name":"a","options":[
    #|  {"name":"pair","long":true,"seq":[
    #|    {"name":"k","type":"string"},
    #|    {"name":"v","type":"string"}]}]}]}
  let ast = load_definition(src)
  // `a --pair x` — seq の 2 つ目 `v` がトークンを得られず starve。
  assert_path_eq(
    starved_operand_path(ast, ["a", "--pair", "x"], "v"),
    ["a", "pair"],
    "seq 内部の starve は [a, pair] へ帰属する",
  )
}

///|
/// 保証: コマンド境界は 1 段ずつ積まれる — 孫スコープでも浅い側へ潰れない。
test "fire_path: 孫スコープの seq 内部 starve は境界ごとに 1 段積む (RE-3)" {
  let src =
    #|{"commands":[{"type":"command","name":"a","commands":[
    #|  {"type":"command","name":"b","options":[
    #|    {"name":"pair","long":true,"seq":[
    #|      {"name":"k","type":"string"},
    #|      {"name":"v","type":"string"}]}]}]}]}
  let ast = load_definition(src)
  assert_path_eq(
    starved_operand_path(ast, ["a", "b", "--pair", "x"], "v"),
    ["a", "b", "pair"],
    "孫スコープの seq 内部 starve は [a, b, pair] へ帰属する",
  )
}

///|
/// 保証: **repeat 内部** の starve も発火コマンドスコープを保つ。反復の包み自体は結果
/// スコープ段を作らないので、path はコマンド境界だけを積む。
test "fire_path: positional repeat の starve は発火コマンドスコープを保つ (RE-3)" {
  let src =
    #|{"commands":[{"type":"command","name":"a","positionals":[
    #|  {"name":"rep","type":"string","repeat":{"min":2}}]}]}
  let ast = load_definition(src)
  // `a x` — min 2 の 2 周目がトークンを得られず starve。
  assert_path_eq(
    starved_operand_path(ast, ["a", "x"], "rep"),
    ["a"],
    "positional repeat 内部の starve は [a] へ帰属する",
  )
}
