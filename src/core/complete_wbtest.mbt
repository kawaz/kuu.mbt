// complete_wbtest.mbt — the completion query (DR-060 / MDR-002 §2.4).
//
// complete = カーソル前のトークン列を消費できた全生存 partial 経路について、
// 次の消費点で読めるものの和集合 (DR-060 §1)。これらのテストは「読めるもの」の
// 3 供給源 (greedy トリガ綴り / matcher の元綴り / positional 期待) と、
// dead end 除外・after 整合フィルタの輪郭を hand-built AtomicAST で固定する。
// word による prefix 絞り・alias/hidden ポリシーは層 2 (生成器) の関心で、
// ここでは検証しない (DR-060 §3: kuu は素材とメタのみ返す)。

///|
/// Cand 検索 helper: 綴り一致の exact 候補があるか。
fn has_exact(cs : Array[Cand], spelling : String) -> Bool {
  for c in cs {
    if !c.is_value && c.spelling == spelling {
      return true
    }
  }
  false
}

///|
/// Cand 検索 helper: origin 一致の値候補があるか。
fn has_value(cs : Array[Cand], origin : String) -> Bool {
  for c in cs {
    if c.is_value && c.origin == origin {
      return true
    }
  }
  false
}

///|
test "DR-060 §1: 単語頭の補完は greedy トリガ綴りを返す (satellite space form)" {
  // greedy 衛星 Seq([Exact("--port"), NumArg]) の先頭 Exact が境界に立つ。
  // parse では EOF の Exact は沈黙 Reject (DR-037) だが、complete では
  // 「次に打てる綴り」そのもの (DR-060 §1)。
  let root : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port")])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), [])
  assert_true(has_exact(cs, "--port"))
}

///|
test "DR-060 §1: トリガ消費済み・値待ちは値候補 (型 + 由来) を返す" {
  // before = ["--port"] は Exact を消費し NumArg が飢える = MDR-002 §2.1 の
  // Pending そのもの。complete ではこれが「値位置」候補 (型 TNum、由来 port、
  // completer 実行はしない — DR-060 §3/§4)。
  let root : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port")])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), ["--port"])
  assert_true(has_value(cs, "port"))
  // 値待ちの経路しか生き残らないので、--port 綴り自体は候補に出ない
  // (同じ綴りをもう一度打てる構造ではない)。
  assert_false(has_exact(cs, "--port"))
}

///|
test "DR-060 §1: コマンド名 (CmdSat) は境界で綴り候補になる" {
  // 子スコープの中身は入力が進むまで候補に混ざらない (build の綴りだけ)。
  let child : Scope = {
    greedy: [],
    positional: [StrArg("target")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("build", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), [])
  assert_true(has_exact(cs, "build"))
  assert_false(has_value(cs, "target"))
  // コマンドを消費した後は子の positional 期待が出る (経路が子に入った)。
  let cs2 = complete(ScopeNode(root), ["build"])
  assert_true(has_value(cs2, "target"))
}

///|
test "DR-060 §1: positional 面の次の期待ノードは値候補として出る" {
  // parse では EOF の StrArg spine は missing_operand Held (DR-065 §3) だが、
  // complete では「これから打つ値の位置」(DR-060 §1)。
  let root : Scope = {
    greedy: [],
    positional: [StrArg("file")],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), [])
  assert_true(has_value(cs, "file"))
}

///|
test "DR-060 §1: repeat の続きは選好で刈られず値候補に残る" {
  // before = ["a"] で xs は 1 rep 成立済み。parse の取り分選好なら stop
  // (完全経路) が勝ち more は捨てられるが、complete は全生存 partial の
  // 和集合 (MDR-002 §2.4) — 「もう 1 rep 打てる」ことが候補になる。
  let defs : Map[String, Node] = Map([])
  defs.set("xs", Seq([StrArg("xs")]))
  let root : Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), ["a"], defs~)
  assert_true(has_value(cs, "xs"))
}

///|
test "DR-060 §1: dead end (途中失敗の経路) は候補を出さない" {
  // before = ["--port", "abc"] は NumArg の値不正 Held (真の dead end)。
  // もう成立しない解釈の候補はノイズなので空 (DR-060 §1)。
  let root : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port")])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), ["--port", "abc"])
  assert_eq(cs.length(), 0)
}

///|
test "DR-060 §2: after 整合フィルタは後続と矛盾する WordEnd 綴りを落とす" {
  // カーソルが行中間 (`| 5`) にある補完。--a (フラグ) を採用すれば "5" は
  // file に落ちて完全経路に到達できるが、--b を採用すると "5" が port に
  // 食われ file が飢える → 完全経路なし → 候補から除外。値候補 (file) は
  // ユーザ入力を発明できないため無検査で通す (v1 制限、complete の doc 参照)。
  let root : Scope = {
    greedy: [Seq([Exact("--a")]), Seq([Exact("--b"), NumArg("port")])],
    positional: [StrArg("file")],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), [], after=["5"])
  assert_true(has_exact(cs, "--a"))
  assert_false(has_exact(cs, "--b"))
  assert_true(has_value(cs, "file"))
}

///|
test "DR-060 §1: cluster 末尾の値 char は space form の値候補を出す" {
  // before = ["-n"] — cluster が値 char で終わり argv も尽きた。次に打てる
  // のは -n の値 (space form)。matcher 内部 (walk_short) が complete モード
  // でだけ Pending を出す唯一の箇所。
  let root : Scope = {
    greedy: [
      NativeMatch(
        ShortCombine(prefix="-", entries=[
          { ch: 'n', name: "n", kind: TNum, depr: false },
        ]),
      ),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), ["-n"])
  assert_true(has_value(cs, "n"))
}

///|
test "DR-060 §3: matcher の元綴り (eq-split / cluster) が境界候補になる" {
  // 単語頭では matcher 自身の綴りが「読めるもの」。eq-split の --key は
  // 同一単語内に =value が続く必要があるので term = Cont (nospace ヒント)、
  // cluster の -n は語末で確定できるので WordEnd (DR-060 §3 終端ヒント)。
  let root : Scope = {
    greedy: [
      NativeMatch(
        EqSplit(prefix="--", entries=[
          { key: "port", name: "port", kind: TNum },
        ]),
      ),
      NativeMatch(
        ShortCombine(prefix="-", entries=[
          { ch: 'n', name: "n", kind: TNum, depr: false },
        ]),
      ),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), [])
  let mut eq_ok = false
  let mut cl_ok = false
  for c in cs {
    if !c.is_value && c.spelling == "--port" && c.term == Cont {
      eq_ok = true
    }
    if !c.is_value && c.spelling == "-n" && c.term == WordEnd {
      cl_ok = true
    }
  }
  assert_true(eq_ok)
  assert_true(cl_ok)
}

///|
test "DR-060 §1: 全消費も一意性も課さない — 既に完全でも続きの候補は出る" {
  // before = ["x"] は file を満たし KTop Accept に到達する (このまま実行
  // 可能) が、greedy の --v はまだ打てる。complete は DR-038 の全消費契約の
  // 別モードではなく期待集合の収集なので、Accept と併存する Pending が
  // そのまま候補になる。
  let root : Scope = {
    greedy: [Seq([Exact("--v"), Bind("v", VBool(true))])],
    positional: [StrArg("file")],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), ["x"])
  assert_true(has_exact(cs, "--v"))
}

///|
test "DR-060 §1: spine の Many も続きの値候補を出す (codex REVIEW-C1)" {
  // Ref repeat は consume_head 経由で修正済みだったが、spine の Many は
  // scope_consume_rep 経由で EOF が沈黙 [] のままだった (同型パターンの
  // 取りこぼし)。1 rep 消費後もこれから 0 rep 目でも、次の xs は打てる。
  let root : Scope = {
    greedy: [],
    positional: [Many(StrArg("xs"))],
    entities: [],
    constraints: [],
  }
  let cs = complete(ScopeNode(root), ["a"])
  assert_true(has_value(cs, "xs"))
  let cs0 = complete(ScopeNode(root), [])
  assert_true(has_value(cs0, "xs"))
}

///|
test "DR-060 §1: IdxRepeat も min 前後の両方で続きの値候補を出す (codex REVIEW-C2)" {
  // idx_one が Pending を明示的に捨てていた。min 未達 (最初の必須 rep が
  // 飢える) でも min 充足後 (もう 1 rep 打てる) でも、head の境界候補は
  // 和集合に入る (DR-060 §1)。
  let root : Scope = {
    greedy: [],
    positional: [IdxRepeat("xs", StrArg("xs"), 1)],
    entities: [],
    constraints: [],
  }
  // min=1 未達: 最初の rep の値位置が候補。
  let cs0 = complete(ScopeNode(root), [])
  assert_true(has_value(cs0, "xs"))
  // min 充足後: 次の rep も候補 (経路自体は Accept でもある)。
  let cs1 = complete(ScopeNode(root), ["a"])
  assert_true(has_value(cs1, "xs"))
}
