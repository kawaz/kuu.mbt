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
//     → dispatch_help_query(ast, path=active_scope)  … help model
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
  let raw = complete_sourced(ast, args_before, args_after~)
  // help model 取得: 候補ごとの帰属 scope (DR-066 §4 fire_path) で help carrier を引く。
  // help_query capability 未登録 or path 到達不能な scope は carrier 無し = 説明引き直しと
  // 整列を素材順で縮退。
  let help_by_scope = collect_scope_help(ast, raw)
  // policy 段
  let (rows, shell_actions) = apply_policy(
    raw,
    cursor_word,
    help_by_scope,
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

// ── scope 帰属 ───────────────────────────────────────────────────────────────

///|
/// 候補の帰属 scope を決める。複数 scope で読まれた候補 (DR-104 §3 の dedup が 1 件に畳んだもの)
/// は最も深い scope を採る — 深い scope の help model は継承した祖先 entry も収載する (root の
/// global option が child の model に現れる) ので、浅い側では引けない子孫由来の origin も含めて
/// 1 つの model で整列・説明引き直しができる。同深さは先読み順で先勝ち。
///
/// 返る path は help() の path 契約に合わせて root scope 名を含めない (help() 内部で
/// declaration.scope.name を先頭 append する)。
fn attributed_scope(sourced : SourcedCandidate) -> Array[String] {
  let mut best : Array[String] = []
  let mut best_depth = -1
  for path in sourced.scope_paths {
    if path.length() > best_depth {
      best = path
      best_depth = path.length()
    }
  }
  best
}

///|
/// 帰属 scope path を Map キーへ畳む。要素名に現れない U+001F を区切りに使う。
fn scope_key(path : Array[String]) -> String {
  let out = StringBuilder::new()
  for segment in path {
    out.write_string(segment)
    out.write_char('\u{001f}')
  }
  out.to_string()
}

///|
/// 候補が帰属する scope ごとに help carrier を 1 度だけ引く。値 None は「その scope では
/// help_query が応えない」= 説明引き直しと整列を素材順へ縮退させる印。
fn collect_scope_help(
  ast : AtomicAST,
  sourced : Array[SourcedCandidate],
) -> Map[String, Array[CompletionHelpEntry]?] {
  let out : Map[String, Array[CompletionHelpEntry]?] = Map([])
  for candidate in sourced {
    let path = attributed_scope(candidate)
    let key = scope_key(path)
    if out.get(key) is Some(_) {
      continue
    }
    out[key] = match dispatch_help_query(ast, path~) {
      Model(model) => Some(completion_help_entries(ast, path, model))
      QueryError(_) | Unavailable => None
    }
  }
  out
}

///|
/// 候補の帰属 scope の help carrier を返す (無ければ空列)。
fn scope_entries(
  sourced : SourcedCandidate,
  help_by_scope : Map[String, Array[CompletionHelpEntry]?],
) -> Array[CompletionHelpEntry] {
  match help_by_scope.get(scope_key(attributed_scope(sourced))) {
    Some(Some(entries)) => entries
    _ => []
  }
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
/// ものは emit 段で spelling に `"="` を付け + nospace を立てる (DR §2.6)。順序と説明は
/// candidate.origin で解決するため、挿入文字列への転写は emit 段でだけ行う。
priv struct PolicyCandidate {
  sourced : SourcedCandidate
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
  raw : Array[SourcedCandidate],
  cursor_word : String,
  help_by_scope : Map[String, Array[CompletionHelpEntry]?],
  insert_form : String,
) -> (Array[QueryRow], Array[String]) {
  // step 1: hidden 除外 (DR-116 §5) + 搬送不能除外 (DR-117 §4.3、spelling に tab/newline)
  let visible : Array[SourcedCandidate] = []
  for s in raw {
    if s.candidate.hidden {
      continue
    }
    if spelling_untransportable(s.candidate.spelling) {
      continue
    }
    visible.push(s)
  }
  // step 2: 値位置 marker を挿入候補から分離する。builtin completer marker は候補行でなく
  // shell_action directive へ翻訳し、形態 B の custom completer marker は候補提供なしへ縮退する。
  let shell_actions : Array[String] = []
  let insertion_candidates : Array[SourcedCandidate] = []
  for s in visible {
    if s.candidate.spelling.length() == 0 {
      match s.candidate.completer {
        Some(name) =>
          if name == "files" || name == "dirs" {
            push_unique_string(shell_actions, name)
          }
        None => ()
      }
    } else {
      insertion_candidates.push(s)
    }
  }
  // step 3: cursor_word による prefix 絞りは挿入文字列を持つ候補だけに適用する。
  // 候補ゼロになっても空リストのまま返す (DR-117 §5 kawaz 裁定 2026-07-23)。
  let candidates : Array[SourcedCandidate] = []
  for s in insertion_candidates {
    if spelling_has_prefix(s.candidate.spelling, cursor_word) {
      candidates.push(s)
    }
  }
  // step 4: insert_form merge (DR-117 §5 / COMPQ-Q1): 同一 spelling で word_end / cont の
  // 併存ペアを 1 件に畳む。片側しか無い場合は素材のまま (§5 の「単独候補の形を書き換えない」)。
  let merged = merge_insert_form(candidates, insert_form)
  // step 5: 帰属 scope ごとに、その scope の help model 適用済み列で整列 (DR-116 §2)。候補は
  // 表示綴りでなく candidate.origin を entry identity へ突き合わせる。同一 origin 内は素材順。
  let ordered = order_policy_candidates_by_origin(merged, help_by_scope)
  // step 6: 説明引き直し (DR-116 §4) + alias/deprecated 注記 (§5) + 説明の正規化 (§4.3) +
  //         nospace flag 翻訳 (candidate.term == Continue → nospace)。
  //         eq_form=true の PolicyCandidate は spelling に `"="` を付け nospace を強制立て。
  let rows : Array[QueryRow] = []
  for pc in ordered {
    let c = pc.sourced.candidate
    let base_help = lookup_help_by_origin(
      c.origin,
      scope_entries(pc.sourced, help_by_scope),
    )
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
/// ペア判定のキーは (origin, spelling) の組。eq-split の cont は元の option 綴りを同じ origin の
/// まま cont term で emit する (`fixtures/complete/eq-split-cont.json` の
/// `word-end-and-cont-coexist-same-origin`) ので、畳むべきペアは必ず origin も一致する。逆に
/// DR-104 §3 明確化が合法とする「同綴り別 origin」(DR-041 §4 の重複トリガ) は別 entry 由来の
/// 別候補であり、spelling 単独をキーにすると無関係な候補どうしがペア扱いされて片方が消える。
fn merge_insert_form(
  candidates : Array[SourcedCandidate],
  insert_form : String,
) -> Array[PolicyCandidate] {
  // origin と spelling の組ごとに word_end / cont の bit を集計する。同綴りでも由来 entry が
  // 異なる候補は別物であり、互いの term とペアを形成しない。
  let has_word_end : Map[String, Bool] = Map([])
  let has_cont : Map[String, Bool] = Map([])
  for s in candidates {
    let c = s.candidate
    if c.is_value {
      continue
    }
    let key = c.origin + "\u{001f}" + c.spelling
    if c.term == WordEnd {
      has_word_end[key] = true
    } else {
      has_cont[key] = true
    }
  }
  let out : Array[PolicyCandidate] = []
  for s in candidates {
    let c = s.candidate
    // 値位置候補・値候補は merge 対象外 (§5 は long option の word_end/cont 併存が唯一の対象)
    if c.is_value {
      out.push({ sourced: s, eq_form: false })
      continue
    }
    let key = c.origin + "\u{001f}" + c.spelling
    let pair_present = has_word_end.get(key) is Some(true) &&
      has_cont.get(key) is Some(true)
    if !pair_present {
      // 単独候補 — §5「insert_form は『ペアが併存した時どちらへ畳むか』だけを定め、単独候補
      // の形を書き換えない」
      out.push({ sourced: s, eq_form: false })
      continue
    }
    // ペア併存 — insert_form で残す side を決める
    if insert_form == "eq" {
      // cont を残す、word_end を落とす
      if c.term == WordEnd {
        continue
      }
      out.push({ sourced: s, eq_form: true })
    } else {
      // 既定 "space": word_end を残す、cont を落とす
      if c.term == Continue {
        continue
      }
      out.push({ sourced: s, eq_form: false })
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
/// 帰属 scope でまとめてから、その scope の help model 適用済み identity 列へ candidate.origin を
/// 突き合わせる (DR-116 §2)。scope は候補の初出順、scope 内で対応 entry を持たない候補 (匿名
/// exact 等) は同 scope 群の末尾へ素材順のまま残す。
///
/// scope でまとめるのは、help model 順が scope ごとに独立した列だから — 異なる scope の entry
/// 列を 1 本に混ぜる規範は無く (DR-116 §2 は単一 model の列を正本とする)、混ぜると浅い scope の
/// 順序が深い scope の候補を追い越す。
fn order_policy_candidates_by_origin(
  candidates : Array[PolicyCandidate],
  help_by_scope : Map[String, Array[CompletionHelpEntry]?],
) -> Array[PolicyCandidate] {
  let out : Array[PolicyCandidate] = []
  let used = Array::make(candidates.length(), false)
  for i = 0; i < candidates.length(); i = i + 1 {
    if used[i] {
      continue
    }
    let key = scope_key(attributed_scope(candidates[i].sourced))
    let entries = scope_entries(candidates[i].sourced, help_by_scope)
    for entry in entries {
      for j = i; j < candidates.length(); j = j + 1 {
        if used[j] {
          continue
        }
        if scope_key(attributed_scope(candidates[j].sourced)) != key {
          continue
        }
        if candidates[j].sourced.candidate.origin == entry.identity {
          out.push(candidates[j])
          used[j] = true
        }
      }
    }
    for j = i; j < candidates.length(); j = j + 1 {
      if used[j] {
        continue
      }
      if scope_key(attributed_scope(candidates[j].sourced)) != key {
        continue
      }
      out.push(candidates[j])
      used[j] = true
    }
  }
  out
}

///|
/// candidate.origin が指す canonical entry の help を引き直す。候補 spelling は alias や
/// completer 由来値で任意に異なり得るため、説明解決には使わない。
fn lookup_help_by_origin(
  origin : String,
  entries : Array[CompletionHelpEntry],
) -> String? {
  for entry in entries {
    if entry.identity == origin {
      return entry.help
    }
  }
  None
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
