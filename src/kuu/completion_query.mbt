// completion_query.mbt — DR-117 §5 completion_query パイプライン (M1)。
//
// 座席は findings 2026-07-23-completion-ux-layer-plan §1.2 UXL-Q1=a 裁定に従い kuu.mbt。
// 玄関判定 (env × argv[1] 二箇所一致、DR-117 §3.1) は M3 の completion_entry で別途組む —
// 本 pipeline は「query モード成立後、words/cword を受けて行応答テキストを返す」下請けに閉じる。
//
// Pipeline (DR-117 §5):
//   words, cword
//     → 分解 (args_before / cursor_word / args_after, §3.4)
//     → complete(ast, args_before, args_after)  … 素材 (DR-104 candidates)
//     → dispatch_help_query(registry, ast, path=active_scope)  … help model
//     → policy 段:
//         hidden 除外                                      (DR-116 §5)
//         cursor_word による prefix 絞り                    (DR-060 §3, DR-117 §5)
//         help model 順で整列 + origin 突き合わせ           (DR-116 §2)
//         説明引き直し (origin) + alias/deprecated 注記     (DR-116 §4/§5)
//         builtin completer 名 → :shell_action 翻訳         (DR-117 §4.2/§7)
//         搬送不能候補の除外 + 説明の tab/newline 正規化    (DR-117 §4.3)
//     → 行指向応答 emit (§4)

///|
/// DR-117 §5 の completion_query capability パイプライン。findings 2026-07-23 UXL-Q1=a に従い
/// kuu.mbt に住まわせ、行指向応答テキスト (String) を直接返す (構造化型は公開しない — findings
/// §1.2)。呼び出し側 (M3 の completion_entry 経由、または kuu-cli 形態 B の `kuu completion query`
/// サブコマンド) は返却された文字列を stdout に出して exit 0 する。
///
/// 引数:
/// - `words`: DR-117 §3.4 の全量トークン列。先頭 = 補完対象コマンド名 (shell の native 素材 —
///   bash `COMP_WORDS` / zsh `words` / fish `commandline -o` — がいずれも全量形なので、glue は
///   加工せず素通し。先頭トークンを落とす処理は本関数の分解段で 1 箇所に集約する)
/// - `cword`: `words` 内のカーソル単語 index (0-origin)。None (省略) / 負値 / `words.length()`
///   超過 → 行末補完扱いへ縮退 (§3.3、glue が正しく組めば発生しない入力への防御的縮退。
///   縮退時 stderr 警告は出さない — findings §3.2/§7 の悪い面参照)
///
/// 戻り値: DR-117 §4 の行指向応答テキスト。候補ゼロは空文字列または directive 行のみ。
pub fn completion_query(
  ast : AtomicAST,
  registry : @engine.Registry,
  words : Array[String],
  cword? : Int? = None,
) -> String {
  // §3.4: 空 words は玄関判定 (M3) が防ぐ想定だが、防御的に空応答へ倒す
  if words.length() == 0 {
    return ""
  }
  // §3.4: cword = 0 (コマンド名自身にカーソル) → 空応答。コマンド名の補完は shell 自身の
  // コマンド名補完の領分であり、definition に照合する対象が無い
  match cword {
    Some(n) => if n == 0 { return "" }
    None => ()
  }
  // §3.4 分解: words[1..cword] → args_before / words[cword] → cursor_word /
  // words[cword+1..] → args_after (先頭トークン落としを本関数内 1 箇所で行う)
  let (args_before, cursor_word, args_after) = decompose_words(words, cword)
  // 素材集め: DR-104 の候補 wire を complete() 経由で取得 (front_door.mbt の complete)。
  // 内部で @engine.complete_tree が subcommand を追いかけて active scope の候補を吐く。
  let raw = complete(ast, args_before, args_after~)
  // help model 取得: args_before の先頭連続 command 名から active scope path を計算し、
  // dispatch_help_query で HelpModel を得る。help_query capability 未登録 or path 到達不能なら
  // None (説明引き直しと整列は素材順で縮退)。
  let active_path = active_scope_path(ast, args_before)
  let help_model = match dispatch_help_query(registry, ast, path=active_path) {
    Model(model) => Some(model)
    QueryError(_) | Unavailable => None
  }
  // policy 段
  let (rows, shell_actions) = apply_policy(
    raw,
    cursor_word,
    help_model,
    ast.completion_insert_form,
  )
  // §4 の行指向応答テキスト emit
  emit_response(rows, shell_actions)
}

// ── §3.4 分解 ────────────────────────────────────────────────────────────────

///|
/// words / cword を (args_before, cursor_word, args_after) へ分解する (DR-117 §3.4 の写像)。
/// - cword が None / 負値 / len 超過 → 行末補完縮退 (§3.3)
/// - args_before = words[1..effective]
/// - cursor_word = effective < len ? words[effective] : ""
/// - args_after = words[effective+1..]
fn decompose_words(
  words : Array[String],
  cword : Int?,
) -> (Array[String], String, Array[String]) {
  let len = words.length()
  // §3.3: 数値として解釈できない値・負値・words 長を超える値は行末補完扱いに縮退する。
  // None (省略) も同じ縮退。effective が len に等しい場合、cursor は「末尾の次」 = 空文字。
  let effective : Int = match cword {
    None => len
    Some(n) => if n < 0 || n > len { len } else { n }
  }
  let args_before : Array[String] = []
  // 上限は min(effective, len) — effective==len でも 1..len の写しでよい
  let end_before = if effective > len { len } else { effective }
  for i = 1; i < end_before; i = i + 1 {
    args_before.push(words[i])
  }
  let cursor_word : String = if effective < len { words[effective] } else { "" }
  let args_after : Array[String] = []
  for i = effective + 1; i < len; i = i + 1 {
    args_after.push(words[i])
  }
  (args_before, cursor_word, args_after)
}

// ── active scope path 計算 ───────────────────────────────────────────────────

///|
/// args_before の先頭から連続する command 名を追い、active scope の root-first path を返す。
/// option / positional / 未定義 command が混ざった時点で追跡を止める素朴実装 — M1 のスコープ。
/// より正確には parse() を走らせて subcommand 遷移を追う手だが、resolve 相を要さない補完面では
/// この単純化で fixture の典型ケース (`app <sub> --flag <TAB>`) を捕らえる。option 挟み込み
/// (`app --verbose build <TAB>`) のような edge case は将来 M3 の completion_entry で回収余地。
///
/// 返る path は help() の path 契約に合わせて root scope 名を含めない (help() 内部で
/// declaration.scope.name を先頭 append する)。
fn active_scope_path(
  ast : AtomicAST,
  args_before : Array[String],
) -> Array[String] {
  let path : Array[String] = []
  let mut current = ast.declaration
  for arg in args_before {
    let mut next : @engine.Definition? = None
    for cmd in current.commands {
      if cmd.name == arg {
        next = Some(cmd.body)
        break
      }
    }
    match next {
      Some(body) => {
        path.push(arg)
        current = body
      }
      None => break
    }
  }
  path
}

// ── policy 段 ────────────────────────────────────────────────────────────────

///|
/// emit 直前の候補行 carrier (非公開)。spelling + description + nospace flag に閉じる。
/// candidate の identity 系 (path / link / origin) は emit 段では使わない。
priv struct QueryRow {
  spelling : String
  description : String
  nospace : Bool
}

///|
/// DR-117 §5 merge 規則の中間 carrier。candidate 実体をそのまま持ちつつ、`eq_form` = true の
/// ものは emit 段で spelling に `"="` を付け + nospace を立てる (DR §2.6)。lookup_help /
/// order_by_help_model は candidate.spelling をそのまま使うため、insert_form=="eq" の merge で
/// 生き残った cont 候補も **元の spelling** ("--port") のまま突き合わせる (help model の綴りも
/// eq を含まない) — 転写は emit 段でだけ行う。
priv struct PolicyCandidate {
  candidate : @engine.Candidate
  eq_form : Bool
}

///|
/// DR-116 / DR-117 §5 の policy 段全体。順序は emit 段の依存 (hidden 除外を先にすると
/// prefix 絞りの負荷が減る / shell_action 分離は整列前に済ませる) を優先。
///
/// `insert_form` は DR-117 §5 の merge 規則 (同一 spelling の word_end / cont 併存ペアの畳み込み)
/// に使う definition-wide 静的属性 (§2.6、AtomicAST が carry)。値域は "space" (既定) / "eq" — invalid
/// は parse_definition が弾き済みなので policy 段では self-defense しない。
fn apply_policy(
  raw : Array[@engine.Candidate],
  cursor_word : String,
  help_model : HelpModel?,
  insert_form : String,
) -> (Array[QueryRow], Array[String]) {
  // step 1: hidden 除外 (DR-116 §5) + 搬送不能除外 (DR-117 §4.3、spelling に tab/newline)
  let visible : Array[@engine.Candidate] = []
  for c in raw {
    if c.hidden {
      continue
    }
    if spelling_untransportable(c.spelling) {
      continue
    }
    visible.push(c)
  }
  // step 2: cursor_word による prefix 絞り (DR-117 §5、DR-060 §3 が生成器側の選択とした絞り)。
  // 候補ゼロになっても空リストのまま返す (DR-117 §5 kawaz 裁定 2026-07-23)。
  let prefixed : Array[@engine.Candidate] = []
  for c in visible {
    if spelling_has_prefix(c.spelling, cursor_word) {
      prefixed.push(c)
    }
  }
  // step 3: shell_action 翻訳 (DR-117 §4.2/§7): completer 名が "files" / "dirs" の候補は
  // 候補行として出さず :shell_action directive へ集約 (同名重複は 1 回)。他の completer 名は
  // v1 で shell_action 対応語彙外なので通常候補として通す (glue の未知 directive 無視の
  // 前方互換規則と対称)。
  let shell_actions : Array[String] = []
  let candidates : Array[@engine.Candidate] = []
  for c in prefixed {
    match c.completer {
      Some(name) =>
        if name == "files" || name == "dirs" {
          push_unique_string(shell_actions, name)
        } else {
          candidates.push(c)
        }
      None => candidates.push(c)
    }
  }
  // step 4: insert_form merge (DR-117 §5 / COMPQ-Q1): 同一 spelling で word_end / cont の
  // 併存ペアを 1 件に畳む。片側しか無い場合は素材のまま (§5 の「単独候補の形を書き換えない」)。
  let merged = merge_insert_form(candidates, insert_form)
  // step 5: help model 順で整列 (DR-116 §2)。PolicyCandidate.candidate.spelling を綴り突き合わせ
  // の鍵にする — eq_form=true でも spelling 自体はまだ原綴り ("--port")。
  let ordered = order_policy_candidates_by_help_model(merged, help_model)
  // step 6: 説明引き直し (DR-116 §4) + alias/deprecated 注記 (§5) + 説明の正規化 (§4.3) +
  //         nospace flag 翻訳 (candidate.term == Continue → nospace)。
  //         eq_form=true の PolicyCandidate は spelling に `"="` を付け nospace を強制立て。
  let rows : Array[QueryRow] = []
  for pc in ordered {
    let c = pc.candidate
    let base_help = lookup_help(c, help_model)
    let annotated = annotate_description(base_help, c.deprecated, c.is_alias)
    let description = normalize_description(annotated)
    let spelling = if pc.eq_form { c.spelling + "=" } else { c.spelling }
    let nospace = if pc.eq_form { true } else { c.term == Continue }
    rows.push({ spelling, description, nospace })
  }
  (rows, shell_actions)
}

///|
/// DR-117 §5 merge 規則 (COMPQ-Q1 裁定 2026-07-23): 同一 spelling で term だけが異なる候補ペア
/// (option の word_end + cont) を 1 行に統合する。ペア併存でないもの (単独 word_end、単独 cont、
/// 綴り違い候補、値位置候補、値候補) は素材のまま流す。
///
/// - insert_form == "space" (既定): word_end 側を残す、cont 側を除外。spelling そのまま、nospace 無し
/// - insert_form == "eq": cont 側を残す、word_end 側を除外。emit 段で `spelling + "="` + nospace 強制
///
/// アルゴリズム: candidates を素材出現順で走査しつつ「同一 spelling の別 term」を同時に持つか
/// で判定する。DR-104 §3 の 6 フィールド identity で同一 spelling は必ず origin と是本 spelling が
/// 一致するため、spelling 単独の突き合わせで正しい (原理: eq-split の cont は元の option 綴りを
/// そのまま cont term で emit する `fixtures/complete/eq-split-cont.json` の `word-end-and-cont-
/// coexist-same-origin` 案件と対称)。
fn merge_insert_form(
  candidates : Array[@engine.Candidate],
  insert_form : String,
) -> Array[PolicyCandidate] {
  // まず spelling ごとに word_end / cont の bit を集計 (is_value=false の option 綴り候補のみ対象)
  let has_word_end : Map[String, Bool] = Map([])
  let has_cont : Map[String, Bool] = Map([])
  for c in candidates {
    if c.is_value {
      continue
    }
    if c.term == WordEnd {
      has_word_end[c.spelling] = true
    } else {
      has_cont[c.spelling] = true
    }
  }
  let out : Array[PolicyCandidate] = []
  for c in candidates {
    // 値位置候補・値候補は merge 対象外 (§5 は long option の word_end/cont 併存が唯一の対象)
    if c.is_value {
      out.push({ candidate: c, eq_form: false })
      continue
    }
    let pair_present = has_word_end.get(c.spelling) is Some(true) &&
      has_cont.get(c.spelling) is Some(true)
    if !pair_present {
      // 単独候補 — §5「insert_form は『ペアが併存した時どちらへ畳むか』だけを定め、単独候補
      // の形を書き換えない」
      out.push({ candidate: c, eq_form: false })
      continue
    }
    // ペア併存 — insert_form で残す side を決める
    if insert_form == "eq" {
      // cont を残す、word_end を落とす
      if c.term == WordEnd {
        continue
      }
      out.push({ candidate: c, eq_form: true })
    } else {
      // 既定 "space": word_end を残す、cont を落とす
      if c.term == Continue {
        continue
      }
      out.push({ candidate: c, eq_form: false })
    }
  }
  out
}

///|
/// DR-117 §4.3: 挿入文字列に tab / newline を含む候補は shell の補完挿入機構でも実用に耐えず、
/// 応答から除外する。
fn spelling_untransportable(s : String) -> Bool {
  for ch in s.to_array() {
    if ch == '\t' || ch == '\n' {
      return true
    }
  }
  false
}

///|
fn spelling_has_prefix(s : String, prefix : String) -> Bool {
  let sc = s.to_array()
  let pc = prefix.to_array()
  if pc.length() > sc.length() {
    return false
  }
  for i = 0; i < pc.length(); i = i + 1 {
    if sc[i] != pc[i] {
      return false
    }
  }
  true
}

///|
fn push_unique_string(arr : Array[String], value : String) -> Unit {
  for existing in arr {
    if existing == value {
      return
    }
  }
  arr.push(value)
}

///|
/// PolicyCandidate 版の順序整列。merge_insert_form が生成した wrapper 列を
/// help model 順 (DR-116 §2) に並べる。突き合わせは wrapper 内 candidate.spelling を鍵にする。
fn order_policy_candidates_by_help_model(
  candidates : Array[PolicyCandidate],
  help_model : HelpModel?,
) -> Array[PolicyCandidate] {
  match help_model {
    None => candidates
    Some(model) => {
      let out : Array[PolicyCandidate] = []
      let used = Array::make(candidates.length(), false)
      for entry in model.options {
        match entry {
          Group(_) => ()
          Option(opt) =>
            take_matching_policy_spellings(
              candidates,
              used,
              opt.spellings,
              opt.alias_spellings,
              out,
            )
        }
      }
      for cmd in model.commands {
        take_matching_policy_spellings(
          candidates,
          used,
          [cmd.name],
          cmd.aliases,
          out,
        )
      }
      for i = 0; i < candidates.length(); i = i + 1 {
        if !used[i] {
          out.push(candidates[i])
        }
      }
      out
    }
  }
}

///|
/// canonical + alias 綴り集合に一致する未消費 PolicyCandidate を素材出現順で out に append。
/// 綴り突き合わせは wrapper 内 candidate.spelling を使う (原綴り、`take_matching_spellings` と対称)。
fn take_matching_policy_spellings(
  candidates : Array[PolicyCandidate],
  used : Array[Bool],
  canonical : Array[String],
  aliases : Array[String],
  out : Array[PolicyCandidate],
) -> Unit {
  for i = 0; i < candidates.length(); i = i + 1 {
    if used[i] {
      continue
    }
    let c = candidates[i].candidate
    if c.is_value {
      continue
    }
    for sp in canonical {
      if c.spelling == sp {
        out.push(candidates[i])
        used[i] = true
        break
      }
    }
  }
  for i = 0; i < candidates.length(); i = i + 1 {
    if used[i] {
      continue
    }
    let c = candidates[i].candidate
    if c.is_value {
      continue
    }
    for sp in aliases {
      if c.spelling == sp {
        out.push(candidates[i])
        used[i] = true
        break
      }
    }
  }
}

///|
/// DR-116 §4: candidate の origin を help model の entry に突き合わせ、entry の help を引く。
/// - option canonical / alias 綴り: candidate.spelling を options entry の spellings /
///   alias_spellings に照合し、canonical entry の help を返す (alias 候補も canonical の help を
///   継承 — DR-116 §4「alias 候補: canonical entry の `help` と alias であることを示す注記」)
/// - command 名 / alias: candidate.spelling を commands entry の name / aliases に照合
/// - 対応なし (value 候補 / 匿名 exact など): None を返す
fn lookup_help(c : @engine.Candidate, help_model : HelpModel?) -> String? {
  match help_model {
    None => None
    Some(model) => {
      for entry in model.options {
        match entry {
          Group(_) => ()
          Option(opt) => {
            for sp in opt.spellings {
              if c.spelling == sp {
                return opt.help
              }
            }
            for sp in opt.alias_spellings {
              if c.spelling == sp {
                return opt.help
              }
            }
          }
        }
      }
      for cmd in model.commands {
        if c.spelling == cmd.name {
          return cmd.help
        }
        for a in cmd.aliases {
          if c.spelling == a {
            return cmd.help
          }
        }
      }
      None
    }
  }
}

///|
/// DR-116 §5: alias 注記 (存在すれば) + deprecated 注記 (存在すれば) を本体 help の末尾に空白
/// 1 個で連結する。文言は DR-116 §5 で非規範だが、M1 では簡潔・視認容易な `(alias)` /
/// `(deprecated)` を採る。help が None / 空でも注記だけは残す (deprecated 綴りに help が無い
/// ケースでも「deprecated」であることを利用者に伝える意味を優先)。
fn annotate_description(
  base : String?,
  deprecated : Bool,
  is_alias : Bool,
) -> String {
  let parts : Array[String] = []
  match base {
    Some(s) => if s.length() > 0 { parts.push(s) }
    None => ()
  }
  if is_alias {
    parts.push("(alias)")
  }
  if deprecated {
    parts.push("(deprecated)")
  }
  let out = StringBuilder::new()
  let mut first = true
  for p in parts {
    if !first {
      out.write_char(' ')
    }
    out.write_string(p)
    first = false
  }
  out.to_string()
}

///|
/// DR-117 §4.3: 説明内の tab / newline を空白 1 個へ正規化する (行文法にエスケープ語彙を持たない
/// ため binary 側で正規化する)。
fn normalize_description(s : String) -> String {
  let out = StringBuilder::new()
  for ch in s.to_array() {
    if ch == '\t' || ch == '\n' {
      out.write_char(' ')
    } else {
      out.write_char(ch)
    }
  }
  out.to_string()
}

// ── §4 行 emit ───────────────────────────────────────────────────────────────

///|
/// DR-117 §4: 候補行 → :shell_action directive の順で行応答テキストを組む。空応答は空文字列
/// (§4.4: 候補ゼロは候補行ゼロで表す、directive のみでもよい)。
fn emit_response(
  rows : Array[QueryRow],
  shell_actions : Array[String],
) -> String {
  let out = StringBuilder::new()
  for row in rows {
    emit_row(out, row)
  }
  for name in shell_actions {
    out.write_string(":shell_action ")
    out.write_string(name)
    out.write_char('\n')
  }
  out.to_string()
}

///|
/// DR-117 §4.1 の行フォーマット:
/// - 説明無し + フラグ無し   → `spelling\n`
/// - 説明有り + フラグ無し   → `spelling\tdescription\n`
/// - 説明無し + フラグ有り   → `spelling\t\tnospace\n`  (末尾フィールドは省略できるが、間の
///                              フィールドは空フィールドで埋める、§4.1 の "フラグを持ち説明を
///                              持たない候補は説明位置に空フィールドを置く")
/// - 説明有り + フラグ有り   → `spelling\tdescription\tnospace\n`
fn emit_row(out : StringBuilder, row : QueryRow) -> Unit {
  out.write_string(row.spelling)
  if row.nospace {
    out.write_char('\t')
    out.write_string(row.description)
    out.write_char('\t')
    out.write_string("nospace")
  } else if row.description.length() > 0 {
    out.write_char('\t')
    out.write_string(row.description)
  }
  out.write_char('\n')
}
