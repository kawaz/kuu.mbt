// complete_wbtest.mbt — the completion query (DR-060 / MDR-002 §2.4).
//
// complete = カーソル前のトークン列を消費できた全生存 partial 経路について、
// 次の消費点で読めるものの和集合 (DR-060 §1)。これらのテストは「読めるもの」の
// 3 供給源 (greedy トリガ綴り / matcher の元綴り / positional 期待) と、
// dead end 除外・after 整合フィルタの輪郭を hand-built AtomicAST で固定する。
// word による prefix 絞り・alias/hidden ポリシーは層 2 (生成器) の関心で、
// ここでは検証しない (DR-060 §3: kuu は素材とメタのみ返す)。

///|
/// Candidate 検索 helper: 綴り一致の exact 候補があるか。
fn has_exact(cs : Array[@abi.Candidate], spelling : String) -> Bool {
  for c in cs {
    if !c.is_value && c.spelling == spelling {
      return true
    }
  }
  false
}

///|
/// Candidate 検索 helper: origin 一致の値候補があるか。
fn has_value(cs : Array[@abi.Candidate], origin : String) -> Bool {
  for c in cs {
    if c.is_value && c.origin == origin {
      return true
    }
  }
  false
}

///|
fn has_exact_public(cs : Array[Candidate], spelling : String) -> Bool {
  for c in cs {
    if !c.is_value && c.spelling == spelling {
      return true
    }
  }
  false
}

///|
fn has_value_public(cs : Array[Candidate], origin : String) -> Bool {
  for c in cs {
    if c.is_value && c.origin == origin {
      return true
    }
  }
  false
}

///|
test "DR-060 §1: 単語頭の補完は greedy トリガ綴りを返す (satellite space form)" {
  // greedy 衛星 @engine.Seq([@engine.Exact("--port"), number resident]) の先頭 @engine.Exact が境界に立つ。
  // parse では EOF の @engine.Exact は沈黙 Reject (DR-037) だが、complete では
  // 「次に打てる綴り」そのもの (DR-060 §1)。
  let root : @engine.Scope = {
    greedy: [
      @engine.Seq([@engine.Exact("--port"), @builtins.number_arg("port", [])]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), [])
  assert_true(has_exact(cs, "--port"))
}

///|
test "DR-060 §1: トリガ消費済み・値待ちは値候補 (型 + 由来) を返す" {
  // before = ["--port"] は @engine.Exact を消費し number resident が飢える = MDR-002 §2.1 の
  // @abi.Pending そのもの。complete ではこれが「値位置」候補 (型 @builtins.number_type()、由来 port、
  // completer 実行はしない — DR-060 §3/§4)。
  let root : @engine.Scope = {
    greedy: [
      @engine.Seq([@engine.Exact("--port"), @builtins.number_arg("port", [])]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), ["--port"])
  assert_true(has_value(cs, "port"))
  // 値待ちの経路しか生き残らないので、--port 綴り自体は候補に出ない
  // (同じ綴りをもう一度打てる構造ではない)。
  assert_false(has_exact(cs, "--port"))
}

///|
test "DR-060 §1: コマンド名 (@engine.CommandSatisfied) は境界で綴り候補になる" {
  // 子スコープの中身は入力が進むまで候補に混ざらない (build の綴りだけ)。
  let child : @engine.Scope = {
    greedy: [],
    positional: [@builtins.string_arg("target", [])],
    entities: [],
    constraints: [],
  }
  let root : @engine.Scope = {
    greedy: [@engine.CommandSatisfied("build", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), [])
  assert_true(has_exact(cs, "build"))
  assert_false(has_value(cs, "target"))
  // コマンドを消費した後は子の positional 期待が出る (経路が子に入った)。
  let cs2 = @engine.complete_tree(@engine.ScopeNode(root), ["build"])
  assert_true(has_value(cs2, "target"))
}

///|
test "DR-060 §1: positional 面の次の期待ノードは値候補として出る" {
  // parse では EOF の string resident spine は missing_operand @abi.Held (DR-065 §3) だが、
  // complete では「これから打つ値の位置」(DR-060 §1)。
  let root : @engine.Scope = {
    greedy: [],
    positional: [@builtins.string_arg("file", [])],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), [])
  assert_true(has_value(cs, "file"))
}

///|
test "DR-060 §1: repeat の続きは選好で刈られず値候補に残る" {
  // before = ["a"] で xs は 1 rep 成立済み。parse の取り分選好なら stop
  // (完全経路) が勝ち more は捨てられるが、complete は全生存 partial の
  // 和集合 (MDR-002 §2.4) — 「もう 1 rep 打てる」ことが候補になる。
  let defs : Map[String, @engine.Node] = Map([])
  defs.set("xs", @engine.Seq([@builtins.string_arg("xs", [])]))
  let root : @engine.Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), ["a"], defs~)
  assert_true(has_value(cs, "xs"))
}

///|
test "DR-060 §1: dead end (途中失敗の経路) は候補を出さない" {
  // before = ["--port", "abc"] は number resident の値不正 @abi.Held (真の dead end)。
  // もう成立しない解釈の候補はノイズなので空 (DR-060 §1)。
  let root : @engine.Scope = {
    greedy: [
      @engine.Seq([@engine.Exact("--port"), @builtins.number_arg("port", [])]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), ["--port", "abc"])
  assert_eq(cs.length(), 0)
}

///|
test "DR-060 §2: after 整合フィルタは後続と矛盾する WordEnd 綴りを落とす" {
  // カーソルが行中間 (`| 5`) にある補完。--a (フラグ) を採用すれば "5" は
  // file に落ちて完全経路に到達できるが、--b を採用すると "5" が port に
  // 食われ file が飢える → 完全経路なし → 候補から除外。値候補 (file) は
  // ユーザ入力を発明できないため無検査で通す (v1 制限、complete の doc 参照)。
  let root : @engine.Scope = {
    greedy: [
      @engine.Seq([@engine.Exact("--a")]),
      @engine.Seq([@engine.Exact("--b"), @builtins.number_arg("port", [])]),
    ],
    positional: [@builtins.string_arg("file", [])],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), [], after=["5"])
  assert_true(has_exact(cs, "--a"))
  assert_false(has_exact(cs, "--b"))
  assert_true(has_value(cs, "file"))
}

///|
test "DR-060 §1: cluster 末尾の値 char は space form の値候補を出す" {
  // before = ["-n"] — cluster が値 char で終わり args も尽きた。次に打てる
  // のは -n の値 (space form)。matcher 内部 (walk_short) が complete モード
  // でだけ @abi.Pending を出す唯一の箇所。
  let root : @engine.Scope = {
    greedy: [
      @engine.NativeMatch(
        @builtins.short_combine("-", [
          @builtins.short_entry(
            'n',
            "n",
            @builtins.number_type(),
            [],
            None,
            deprecated=false,
            merge=false,
            short_attached_value=@abi.Allow,
            is_alias=false,
          ),
        ]),
      ),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), ["-n"])
  assert_true(has_value(cs, "n"))
}

///|
test "DR-060 §3: matcher の元綴り (eq-split / cluster) が境界候補になる" {
  // 単語頭では matcher 自身の綴りが「読めるもの」。eq-split の --key は
  // 同一単語内に =value が続く必要があるので term = Continue (nospace ヒント)、
  // cluster の -n は語末で確定できるので WordEnd (DR-060 §3 終端ヒント)。
  let root : @engine.Scope = {
    greedy: [
      @engine.NativeMatch(
        @builtins.eq_split("--", [
          @builtins.eq_entry(
            "port",
            "port",
            @builtins.number_type(),
            [],
            None,
            merge=false,
            deprecated=false,
          ),
        ]),
      ),
      @engine.NativeMatch(
        @builtins.short_combine("-", [
          @builtins.short_entry(
            'n',
            "n",
            @builtins.number_type(),
            [],
            None,
            deprecated=false,
            merge=false,
            short_attached_value=@abi.Allow,
            is_alias=false,
          ),
        ]),
      ),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), [])
  let mut eq_ok = false
  let mut cl_ok = false
  for c in cs {
    if !c.is_value && c.spelling == "--port" && c.term == Continue {
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
  // before = ["x"] は file を満たし KTop @abi.Accept に到達する (このまま実行
  // 可能) が、greedy の --v はまだ打てる。complete は DR-038 の全消費契約の
  // 別モードではなく期待集合の収集なので、@abi.Accept と併存する @abi.Pending が
  // そのまま候補になる。
  let root : @engine.Scope = {
    greedy: [
      @engine.Seq([@engine.Exact("--v"), @engine.Bind("v", @abi.Bool(true))]),
    ],
    positional: [@builtins.string_arg("file", [])],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), ["x"])
  assert_true(has_exact(cs, "--v"))
}

///|
test "DR-060 §1: spine の @engine.Many も続きの値候補を出す (codex REVIEW-C1)" {
  // Ref repeat は consume_head 経由で修正済みだったが、spine の @engine.Many は
  // scope_consume_rep 経由で EOF が沈黙 [] のままだった (同型パターンの
  // 取りこぼし)。1 rep 消費後もこれから 0 rep 目でも、次の xs は打てる。
  let root : @engine.Scope = {
    greedy: [],
    positional: [@engine.Many(@builtins.string_arg("xs", []), false)],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), ["a"])
  assert_true(has_value(cs, "xs"))
  let cs0 = @engine.complete_tree(@engine.ScopeNode(root), [])
  assert_true(has_value(cs0, "xs"))
}

///|
test "DR-060 §1: @engine.IndexedRepeat も min 前後の両方で続きの値候補を出す (codex REVIEW-C2)" {
  // idx_one が @abi.Pending を明示的に捨てていた。min 未達 (最初の必須 rep が
  // 飢える) でも min 充足後 (もう 1 rep 打てる) でも、head の境界候補は
  // 和集合に入る (DR-060 §1)。
  let root : @engine.Scope = {
    greedy: [],
    positional: [
      @engine.IndexedRepeat("xs", @builtins.string_arg("xs", []), 1, None),
    ],
    entities: [],
    constraints: [],
  }
  // min=1 未達: 最初の rep の値位置が候補。
  let cs0 = @engine.complete_tree(@engine.ScopeNode(root), [])
  assert_true(has_value(cs0, "xs"))
  // min 充足後: 次の rep も候補 (経路自体は @abi.Accept でもある)。
  let cs1 = @engine.complete_tree(@engine.ScopeNode(root), ["a"])
  assert_true(has_value(cs1, "xs"))
}

///|
/// DR-060 §3 の候補構造 (綴り + 由来要素 + 型 + term + meta) は `Candidate.path`
/// (DR-066 §4, issue 2026-07-08 pending-starvation-missing-operand-path) を含まない
/// — path はどの祖先 scope 経由で候補に届いたかの情報で、DR-060 §1 の和集合が
/// 束ねる単位 (「打てる綴り」) の一部ではない。2 つの異なる scope
/// (`@engine.Or([@engine.Scoped("a", ...), @engine.Scoped("b", ...)])`) が同じ `--x` を候補に出しても、
/// dedup は path 差を無視して 1 件に畳む — 畳まなければ「同じ綴りが 2 回出る」
/// という DR-060 §3 の契約破りになる。
test "DR-060 §3: candidate dedup ignores path — same spelling from two different ancestor scopes collapses to one" {
  let root : @engine.Scope = {
    greedy: [
      @engine.Or([
        @engine.Scoped("a", @engine.Exact("--x")),
        @engine.Scoped("b", @engine.Exact("--x")),
      ]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let cs = @engine.complete_tree(@engine.ScopeNode(root), [])
  let matches = []
  for c in cs {
    if !c.is_value && c.spelling == "--x" {
      matches.push(c)
    }
  }
  assert_eq(matches.length(), 1)
}

///|
test "DR-117 §2.2: completion_script offers shell names without closing string acceptance" {
  let definition = @json.parse(
    "{\"options\":[{\"name\":\"completions\",\"type\":\"completion_script\",\"long\":true}]}",
  )
  let ast = match parse_definition(definition) {
    Ok(ast) => ast
    Err(_) => fail("completion_script definition must lower")
  }
  let candidates = complete(ast, ["--completions"])
  assert_true(has_exact_public(candidates, "zsh"))
  assert_true(has_exact_public(candidates, "bash"))
  assert_true(has_exact_public(candidates, "fish"))
  assert_false(has_value_public(candidates, "completions"))
  match parse_legacy(ast, ["--completions", "nu"]) {
    @engine.Success(_) => ()
    _ => fail("shell suggestions must not become a closed values enum")
  }
}
