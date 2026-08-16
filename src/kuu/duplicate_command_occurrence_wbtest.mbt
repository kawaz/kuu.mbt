// duplicate_command_occurrence_wbtest.mbt — duplicate raw command の入場 occurrence 帰属
// (issue 2026-08-02-dup-raw-command-ordinal-marker-occurrence-gap)。
//
// 同じ綴り (`go`) を持つ 2 つの command 宣言は、id 軸で分離されていれば両方とも同じトークンで
// 入場できる (DR-136 §2: トークンは trigger 軸、ラベル以下は name 軸)。このとき各宣言は
// **1 読みにつき高々 1 回**しか入場できない — command scope の結果キーは 1 つの器であり、
// 同一宣言の 2 回目の入場は着地先を持たないからである。許すと同一 scope path・同一 ordinal の
// `{}` マーカーが並び、occurrence を区別できない読みが完全経路として数えられる。

///|
fn dup_command_ast() -> AtomicAST raise {
  load_definition(
    (
      #|{"commands":[
      #|  {"type":"command","name":"go","id":"go1","export_key":"g1",
      #|   "options":[{"name":"a","type":"string","long":true}]},
      #|  {"type":"command","name":"go","id":"go2","export_key":"g2",
      #|   "options":[{"name":"b","type":"string","long":true}]}]}
    ),
  )
}

///|
/// その読みで scope `label` に立った `{}` マーカーの数。同一宣言への複数入場は
/// ここが 2 以上になる形で現れる。
fn scope_marker_count(binds : Array[@abi.Binding], label : String) -> Int {
  let mut n = 0
  for b in binds {
    if b.key == "{}" && b.scope.length() == 1 && b.scope[0] == label {
      n = n + 1
    }
  }
  n
}

///|
/// 保証: 末尾の裸トークンは**まだ入場していない方**の宣言へ入る。同一宣言の再入場が
/// 起きると、同じ消費列に対して観測が同一の読みが 2 本立ち、偽の ambiguous になる。
test "duplicate raw command: 同一宣言は 1 読みにつき 1 回しか入場しない" {
  let ast = dup_command_ast()
  let args = ["go", "--a", "x", "go"]
  match parse_legacy(ast, args) {
    @engine.Success(binds) => {
      // go1 に `--a x` が入り、末尾の `go` は go2 へ。どちらのマーカーもちょうど 1 つ。
      assert_eq(scope_marker_count(binds, "go1"), 1)
      assert_eq(scope_marker_count(binds, "go2"), 1)
    }
    other =>
      fail(
        "同一宣言の再入場を許すと偽の ambiguous になる: " +
        render_outcome(other),
      )
  }
}

///|
/// 保証: 各 occurrence の binding はそれぞれの宣言へ帰属する (issue 受け入れ条件 1/2)。
test "duplicate raw command: 各入場の binding が宣言ごとに帰属する" {
  let ast = dup_command_ast()
  let args = ["go", "--a", "x", "go", "--b", "y"]
  match parse_legacy(ast, args) {
    @engine.Success(binds) => {
      let mut a_scope = ""
      let mut b_scope = ""
      for b in binds {
        if b.key == "a" && b.scope.length() == 1 {
          a_scope = b.scope[0]
        }
        if b.key == "b" && b.scope.length() == 1 {
          b_scope = b.scope[0]
        }
      }
      assert_eq(a_scope, "go1")
      assert_eq(b_scope, "go2")
      assert_eq(scope_marker_count(binds, "go1"), 1)
      assert_eq(scope_marker_count(binds, "go2"), 1)
    }
    other => fail("both occurrences must parse: " + render_outcome(other))
  }
}

///|
/// 保証 (対極): 宣言は 2 つしか無いので 3 つ目の `go` には受け手が無い — 再入場で
/// 吸収せず、完全経路なしとして落ちる。
test "duplicate raw command: 宣言数を超える入場は受け手が無く落ちる" {
  let ast = dup_command_ast()
  match parse_legacy(ast, ["go", "go", "go"]) {
    @engine.Success(_) =>
      fail(
        "3 回目の `go` は受け手が無いので成功してはならない",
      )
    _ => ()
  }
}
