// phase28_wbtest.mbt — 第 18 弾: 補完クエリ (DR-060)。complete = カーソル前トークン列を消費できた全生存
// partial 経路 (dead end 除外) の、次の消費点で読めるものの和集合。全消費・一意性を課さない別クエリ
// (DR-038 の parse 契約は無傷)。素材 + メタのみ返し、絞り込み・置換・着地は生成器/shell の領分。実装は
// parse evaluator と別走査: parse は「トリガ消費・値 pending」状態を枝ゼロに畳むので pending 値の期待を
// 出せず、WithHeld は dead end 込み (補完は dead end 除外) — 共有せず境界収集の専用走査にした。

fn p28_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst, ConstraintInst, AliasInst, InheritableInst,
  ]
}

// ── 1. 基本の期待集合: greedy 面 (long/short/flag) + positional 値位置の和集合 ─────

test "DR-060 §1: before=[] unions the greedy triggers (long/short) and the positional value position" {
  // port (long+short, number) / verbose (long+short, flag) / files (positional string repeat). At the
  // cut with nothing typed, EVERY next-readable is a candidate: --port/-p/--verbose/-v (greedy 面) and
  // the files value position (型情報 <str>). No full-consumption / uniqueness (DR-038 契約は無傷).
  let def = def_(
    [opt("port", TNum, long=["port"], short=['p']), opt("verbose", TFlag, long=["verbose"], short=['v'])],
    [pos("files", TStr, repeat=rep(0))],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p28_order(), reg)
  inspect(
    cands_str(complete(ScopeNode(sc), [], defs=reg, meta=completion_meta(def))),
    content="--port,--verbose,-p,-v,<str>",
  )
}

// ── 2. 消費進行との連動: 値スロット待ち → 値位置のみ、埋まれば再び全候補 ──────────

test "DR-060 §1: a pending value slot yields ONLY that value position; filling it restores the union" {
  // before=["--port"] fired the greedy but its value is pending — 先食い (DR-041 §4) suppresses any
  // files=--port reading, so the ONLY surviving state is the pending port value (<num>). before=
  // ["--port","80"] completes the entry and the walk is back at the scope start → the full union again.
  let def = def_(
    [opt("port", TNum, long=["port"], short=['p']), opt("verbose", TFlag, long=["verbose"], short=['v'])],
    [pos("files", TStr, repeat=rep(0))],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p28_order(), reg)
  inspect(
    cands_str(complete(ScopeNode(sc), ["--port"], defs=reg, meta=completion_meta(def))),
    content="<num>", // 値スロット待ち → port の値位置のみ
  )
  inspect(
    cands_str(complete(ScopeNode(sc), ["--port", "80"], defs=reg, meta=completion_meta(def))),
    content="--port,--verbose,-p,-v,<str>", // 埋まれば再び全候補
  )
}

// ── 3. command スコープ切替: 子スコープの候補 + global コピー ─────────────────────

test "DR-060 §1: before=[<command>] switches to the subcommand scope; global copies surface there" {
  // `verbose` is global at the root; `sub` is a command with its own `--level`. before=["sub"] enters
  // sub's backbone (DR-041 §4), so the candidates are sub's own --level PLUS the global-copied --verbose
  // (the global copy lives in sub's own greedy face, DR-042). (Parent-backbone resume is approximated —
  // child-only here; see journal 設計 note.)
  let def = def_cmd(
    [opt("verbose", TFlag, long=["verbose"], global=true)],
    [],
    [cmd("sub", def_([opt("level", TNum, long=["level"])], []))],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p28_order(), reg)
  inspect(
    cands_str(complete(ScopeNode(sc), ["sub"], defs=reg, meta=completion_meta(def))),
    content="--level,--verbose", // 子の --level + global コピーの --verbose
  )
}

// ── 4. 生存経路の和集合 (複数解釈): 各解釈の期待集合が全部出る ─────────────────────

test "DR-060 §1: multiple live readings union their expectations (variable-arity --color)" {
  // --color has two readings (DESIGN §15.4): 3-number (r,g,b) OR 1-string (name), over a files 受け皿.
  // before=["--color","255"]: reading A (3-num) has consumed r=255 and PENDS the next number (<num>);
  // reading B (1-str) consumed name="255" and is back at the scope start (--color re-startable + files
  // <str>). BOTH survive → their expectation sets union.
  let color = Or([
    Seq([Exact("--color"), NumArg("r"), NumArg("g"), NumArg("b")]),
    Seq([Exact("--color"), StrArg("name")]),
  ])
  let sc : Scope = { greedy: [color], positional: [Many(StrArg("files"))], entities: [], constraints: [] }
  inspect(
    cands_str(complete(ScopeNode(sc), ["--color", "255"])),
    content="--color,<num>,<str>", // A の pending <num> + B の再開 (--color, files <str>)
  )
}

// ── 5. dead end 除外: 型不一致で死ぬ解釈の候補は出ない (生存解釈の候補は出る) ───────

test "DR-060 §1: a reading that dies on a type mismatch contributes no candidates (survivors do)" {
  // Same --color. before=["--color","abc"]: reading A (3-num) dies — "abc" is not a number, so its
  // pending <num> is GONE (dead end excluded). Only reading B (1-str) survives → --color + files <str>.
  // Contrast item 4 (same def, "255"): A is alive and <num> IS present. This is the dead-end exclusion.
  let color = Or([
    Seq([Exact("--color"), NumArg("r"), NumArg("g"), NumArg("b")]),
    Seq([Exact("--color"), StrArg("name")]),
  ])
  let sc : Scope = { greedy: [color], positional: [Many(StrArg("files"))], entities: [], constraints: [] }
  inspect(
    cands_str(complete(ScopeNode(sc), ["--color", "abc"])),
    content="--color,<str>", // A は dead → <num> は出ない、B の候補のみ
  )
}

// ── 6. word: kuu は prefix 絞りをしない (絞りは shell/生成器) ─────────────────────

test "DR-060 §3: kuu does NOT prefix-filter by the cursor word — it returns the full 素材 set" {
  // DR-060 §3: prefix 絞りは shell/生成器のポリシー、kuu は素材のみ返す。The PoC complete() has no `word`
  // parameter at all (word_suffix は v1 未使用可) — so a partial word like "--po" cannot narrow the
  // result. The candidate set is the SAME full union as before=[] (item 1); the generator filters.
  let def = def_(
    [opt("port", TNum, long=["port"], short=['p']), opt("verbose", TFlag, long=["verbose"], short=['v'])],
    [pos("files", TStr, repeat=rep(0))],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p28_order(), reg)
  // even though the user typed "--po", kuu returns everything (no narrowing to --port only)
  inspect(
    cands_str(complete(ScopeNode(sc), [], defs=reg, meta=completion_meta(def))),
    content="--port,--verbose,-p,-v,<str>",
  )
}

// ── 7. after 整合フィルタ (本命): 後続と矛盾する候補を落とす ───────────────────────

test "DR-060 §2: after filters out candidates that cannot reach a complete path with the後続 tokens" {
  // greedy --opt + two fixed positionals A, B. before=[], after=["x","y"] (which fill A,B). Without
  // `after`, both --opt and the A value position are candidates. WITH after=["x","y"]: adopting the A
  // value would make ["<probe>","x","y"] = 3 tokens for 2 positionals → over-consumes → no complete
  // path → DROPPED. --opt survives (["--opt","x","y"] → --opt fires, A=x, B=y → complete). This is the
  // 全解決モデルならではの精度 (逐次モデルには原理的にできない, §2).
  let def = def_([opt("opt", TFlag, long=["opt"])], [pos("a", TStr), pos("b", TStr)])
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p28_order(), reg)
  inspect(
    cands_str(complete(ScopeNode(sc), [], defs=reg, meta=completion_meta(def))),
    content="--opt,<str>", // after なし: --opt + A の値位置
  )
  inspect(
    cands_str(complete(ScopeNode(sc), [], after=["x", "y"], defs=reg, meta=completion_meta(def))),
    content="--opt", // after=["x","y"] 整合: A 値位置は落ちる (3 トークンで 2 positional は過消費)
  )
}

// ── 8. メタ: alias / deprecated / dd 発火後 (severed で greedy 候補なし) ────────────

test "DR-060 §3 / DR-057/058: candidates carry alias / deprecated meta; a fired dd severs the greedy" {
  // alias -n (canonical port の別入口) と deprecated alias -o。候補メタに alias / dep が乗る (canonical
  // -p は素)。メタは宣言層の参照読み (DR-056)。hidden は本 PoC 未実装 (DR-058 §1 表示層、flag)。
  let def = def_(
    [opt("port", TNum, long=["port"], short=['p'])],
    [],
    aliases=[alias("port", short=['n']), alias("port", short=['o'], deprecated=true)],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p28_order(), reg)
  let cs = complete(ScopeNode(sc), [], defs=reg, meta=completion_meta(def))
  inspect(cand_meta(cs, "-p"), content="-") // canonical: メタなし
  inspect(cand_meta(cs, "-n"), content="alias") // 別入口: alias メタ
  inspect(cand_meta(cs, "-o"), content="alias,dep") // deprecated alias: alias + dep
  // dd 発火後 (before に "--"): severed で greedy 候補が出ず raw positional のみ (内部一体則の帰結)
  let ddef = def_([opt("port", TNum, long=["port"])], [dd_marker(), pos("dir", TStr)])
  let reg2 : Map[String, Node] = Map::new()
  let dsc = build_reg(ddef, p28_order(), reg2)
  inspect(
    cands_str(complete(ScopeNode(dsc), [], defs=reg2, meta=completion_meta(ddef))),
    content="--port,<str>", // "--" 前: greedy + positional
  )
  inspect(
    cands_str(complete(ScopeNode(dsc), ["--"], defs=reg2, meta=completion_meta(ddef))),
    content="<str>", // "--" 後: severed → greedy 候補なし、positional のみ
  )
}

// ── 9. 終端ヒント: flag は word_end、値待ちの long は continue 相当 ─────────────────

test "DR-060 §3/§9: a flag candidate hints word_end; a value-taking long hints continue" {
  // The terminal hint distinguishes 確定 (space可) from 継続 (値が続く). A flag (--verbose) is word_end;
  // a value-taking long (--port) is continue — the entry is not done, a value must follow (§9).
  let def = def_(
    [opt("port", TNum, long=["port"]), opt("verbose", TFlag, long=["verbose"])],
    [],
  )
  let reg : Map[String, Node] = Map::new()
  let sc = build_reg(def, p28_order(), reg)
  let cs = complete(ScopeNode(sc), [], defs=reg, meta=completion_meta(def))
  inspect(cand_term(cs, "--verbose"), content="end") // flag → word_end
  inspect(cand_term(cs, "--port"), content="cont") // 値待ち long → continue
}
