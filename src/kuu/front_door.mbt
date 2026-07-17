// front_door.mbt — kuu-core の正面玄関 (MDR-005)。
//
// spec (kawaz/kuu VISION.md §2) が定める 3 契約 parse_definition (DR-054) / parse (DR-053) /
// complete (DR-060 + DR-104) を、命名・引数名とも spec 語彙に一致させて公開する。内部の
// @engine.Node/@engine.Scope 木を直接叩く低レベル実装 (@engine.parse_tree/@engine.complete_tree, eval.mbt/outcome.mbt) は
// このファイルからだけ呼ばれる — 利用者が @engine.Node の 80+ variant を意識する必要はない。
//
// 典型的な使い方 (definition の wire JSON → parse → 結果):
//
// ```
// let json = @json.parse(
//   #|{"options": [{"name": "port", "type": "number", "long": true}]}
//   ,
// )
// match parse_definition(json) {
//   Ok(ast) =>
//     match parse(ast, ["--port", "8080"]) {
//       @engine.Success(binds) => ... // binds : Array[@engine.Binding] (DR-045 の効果列)
//       @engine.Failure(data) => ... // data.errors : Array[@engine.ParseError] (DR-053 §2)
//       @engine.Ambiguous(data) => ... // data.interpretations (DR-053 §3)
//     }
//   Err(Malformed(reason)) => ... // wire JSON 自体が構文として崩れている
//   Err(Rejected(errs)) => ... // definition-error (DR-054 §4) の全列挙
// }
// ```
//
// 補完 (シェル統合の素材集めは呼び出し側の責務、DR-060 §5 層 2):
//
// ```
// let cands = complete(ast, ["--po"]) // args_before のみ、行末補完
// // cands[i].spelling / .is_value / .ty / .term / .meta が候補の素材 (DR-060 §3)
// ```

///|
/// definition のロード結果 (`parse_definition` の戻り値、DR-054 §4 の `atomic: <AtomicAST>` に
/// 対応する不透明ハンドル)。フィールド非公開 — 利用者は中身を読まず `parse`/`complete` に渡す
/// だけでよい。`root` は lowering 済みの AtomicAST (`@engine.Scope`)、`templates` は
/// `definitions.templates` 由来の ref 解決空間、`extensions` は active assembly の resident
/// 組成表。`ekmap` は definition から静的に決定される export_key 写像 (DR-052、`@builtins.build_export_map` の
/// 結果) — `export_map` (下記) 経由で読める (issue 2026-07-15
/// front-door-export-key-map-access: `parse`/`complete` の結果を CONFORMANCE.md §2 の
/// `result: {...}` へ組み立てたい利用者が、AtomicAST から生 `@engine.Definition` を復元できず
/// `@builtins.build_export_map` を自分で呼べなかった)。ekmap は definition が確定した時点で決定的に
/// 導出される静的情報なので、AtomicAST と生存期間が一致する — ここに同梱するのが自然。
/// `atomic` は MoonBit の予約語 (将来使用のため) なので変数名には `ast` を使う。
pub struct AtomicAST {
  root : @engine.Scope
  templates : Map[String, @engine.Node]
  extensions : @engine.Registry
  ekmap : Map[String, @engine.ExportKey]
}

///|
/// `parse_definition` の失敗 (spec DR-054 §4 の「definition-error」とは別に、wire JSON 自体が
/// 構文として崩れている場合を区別する、MDR-005 §1):
/// - `Malformed`: wire JSON が decode できない (未知キー・型不一致・必須キー欠如 — 旧 `DecodeSkip`
///   の写像。`schema/wire.schema.json` が additionalProperties を開けたまま残す語彙層の検査)
/// - `Rejected`: wire 形として正しいが `parse_definition` (DR-054 §1-§3) が構成不能と判定した
///   全 definition-error の列挙 (`Array[@engine.DefError]`)
pub(all) enum DefLoadError {
  Malformed(String)
  Rejected(Array[@engine.DefError])
} derive(Eq, Debug)

///|
/// 正面玄関 1: definition の wire JSON (`{options, positionals, commands, definitions?, config?}`)
/// を受けて AtomicAST を得る (DR-054)。`definitions.types`/`definitions.templates`
/// (DR-061 §3 / DR-078 §1) の decode、`@builtins.lower_definition` (旧 `parse_definition`、installer.mbt) の
/// 呼び出しまで一気通貫で行う — installer 順序は常に `canonical_registry().installers()` (DR-042 §canonical set、
/// 5 invariants により順序無依存)、呼び出し側が installer 順序を選ぶ理由は無い (順序を選べるのは
/// conformance runner の lowering fixture だけの関心、DR-070)。
pub fn parse_definition(
  json : Json,
  extensions? : @engine.Registry = canonical_registry(),
) -> Result[AtomicAST, DefLoadError] {
  let outcome : Result[AtomicAST, DefLoadError] = try {
    let top = match json.j_obj() {
      Some(o) => o
      None => raise DecodeSkip("definition is not an object")
    }
    allowed_keys(
      top,
      ["options", "positionals", "commands", "definitions", "config"],
      "definition",
    )
    let templates : Map[String, @engine.Node] = Map([])
    let shadows = match top.get("definitions") {
      Some(dj) => {
        let d = match dj.j_obj() {
          Some(x) => x
          None => raise DecodeSkip("definitions is not an object")
        }
        allowed_keys(d, ["types", "templates"], "definitions")
        let ts = match d.get("types") {
          Some(tj) => dec_types(tj)
          None => Map([])
        }
        match d.get("templates") {
          Some(tmplj) => dec_templates(tmplj, ts, templates, extensions)
          None => ()
        }
        ts
      }
      None => Map([])
    }
    let def = dec_definition(top, shadows~, extensions~)
    match
      @builtins.lower_definition(
        def,
        canonical_registry().installers(),
        registry=templates,
      ) {
      Ok(root) =>
        Ok({
          root,
          templates,
          extensions,
          ekmap: @builtins.build_export_map(def),
        })
      Err(errs) => Err(Rejected(errs))
    }
  } catch {
    DecodeSkip(reason) => Err(Malformed(reason))
    UnknownType(element, type_name) =>
      Err(
        Rejected([
          {
            element,
            kind: @engine.DUnknownVocab,
            message: "value type '" + type_name + "' is not registered",
            hint: "register a TypeExt resident named '" + type_name + "'",
          },
        ]),
      )
  } noraise {
    result => result
  }
  outcome
}

///|
/// 正面玄関 2: `ast` に対し `args` を parse し、spec 準拠の @engine.Outcome (DR-053) を返す。
///
/// 内訳 (spec の parse 相の意味論として現われるもの、下 3 段は「相区分」表の parse 相に属する):
///
/// 1. **`@engine.parse_tree`** (eval.mbt): argv 消費 + eval 層の dead-end 判定 + 完全経路収集
/// 2. **`apply_requires_filter`** (DR-047 §5 明確化 = kawaz 裁定 2026-07-09): bool-target
///    requires / CRequiresIf は KTop (CLI 面のみ) では常に skip され、値源 (env/config/inherit)
///    が解ける後段でしか判定できない。ここで候補ごとに `resolve_scope_tree` を実際に呼んで
///    充足を確定し、生存経路数で outcome を再構成する (0 → @engine.Failure / 1 → @engine.Success / 2+ →
///    @engine.Ambiguous)。値源が空でも bool 目的語の充足条件 (「解決後値が true」) の判定は必要 —
///    `env` / `config` / `tty` が未指定なら default: false になり、requires が unfired を弾く
///    (仕様通り)
/// 3. **export-key collision promotion** (DR-021 → DR-073 / UX-Q7R): 同一入力で export_key に
///    共露出する発火 (cli/link) と default より上の席 (env/config/inherit) を解決して @engine.Success を
///    @engine.Ambiguous に昇格し、claimants 面 (露出キー → その解釈で当該キーを占める実体 entity name) を
///    添える。default 席は共露出 claim ではなく、射影後 result cell が空の時だけ注入される
///
/// **相区分 (DR-104 §5)**: 値源ラダー (env/config/inherit/default seat fill) を binds に反映
/// する **resolve 相** は本関数の射程外 — 別関数 `resolve()` (下記) に切り出す。理由: parse 相
/// と resolve 相は spec の DR-104 §5 が「dead end 判定は parse 相、制約評価は resolve 相」で
/// 明示的に相区分しており、玄関 API もこれに従う (kawaz 裁定「迷ったら 2 段案 (相区分に忠実)
/// に倒す」)。したがって本関数の @engine.Success payload (`Array[@engine.Binding]`) は **CLI 由来の生 binds**
/// (`@engine.parse_tree` の直接出力、resolve 未適用) であり、`resolve()` に渡してから
/// `build_result` / `apply_export_keys` で最終 wire 表現を組み立てるのが呼び出し側の責務。
/// ただし collision により @engine.Ambiguous へ昇格する解釈は、共露出した env/config/inherit の
/// bindings も運ぶ。claimants と対になる結果ビューを構成するための解釈データである。
///
/// **なぜ 1 発 `parse_and_resolve` にしないか**: parse 相の outcome (@engine.Success/@engine.Failure/@engine.Ambiguous
/// 骨格) だけ欲しい場面 (dogfooding 用の debug、部分的な取扱、fuzz 等) と、完全 wire を組み立て
/// たい場面 (kuu-cli の JSON 出力) を型で区別する。呼び出し側便宜のラッパーが必要になれば別途足す
/// (現状は runner + kuu-cli が 2 発直列で書くだけで済む)。
///
/// 引数の値源:
///
/// - `env`: DR-050 の env provider に相当する `Map[String, String]` (キー = env var name)。
///   `apply_requires_filter` 内で `resolve_scope_tree` に渡される。未指定 = 空 Map
/// - `config`: DR-050 の config provider シグネチャ `(path: String) -> @engine.ConfigVal?`。scope ごとに
///   異なる config_file を動的に指す `CfgFiles` ケースも呼び出し元が対応する closure を渡すだけで
///   均一に扱われる (単一 @engine.ConfigVal だった旧契約の残存ギャップが解消)。未指定 = 常に `None`
///   を返す no-op provider
/// - `tty`: DR-099 §4 の tty provider (stream 名 → 生観測 `TtyObs` の Map)。未指定 = 空 Map
///   (提供なし、CONFORMANCE §1)
pub fn parse(
  ast : AtomicAST,
  args : Array[String],
  env? : Map[String, String] = Map([]),
  config? : (String) -> @engine.ConfigVal? = fn(_p) { None },
  tty? : Map[String, TtyObs] = Map([]),
) -> @engine.Outcome {
  let root = @engine.ScopeNode(ast.root)
  let checked = apply_requires_filter_with_export(
    @engine.parse_tree(root, args, defs=ast.templates),
    root,
    ast.templates,
    env,
    args.length(),
    config,
    tty,
    ast.ekmap,
  )
  match checked {
    @engine.Success(binds) =>
      match
        resolve_scope_tree_with_export(
          ast.root,
          binds,
          env,
          config,
          [],
          Map([]),
          args.length(),
          tty,
          ast.ekmap,
          false,
        ) {
        Ok(claims) =>
          promote_collision_ambiguous_from(checked, claims, ast.ekmap)
        Err(_) => promote_collision_ambiguous(checked, ast.ekmap)
      }
    _ => checked
  }
}

///|
/// 正面玄関 2 の続き: `parse()` が返した @engine.Outcome の @engine.Success payload (CLI 生 binds) に**値源
/// ラダー**を適用し、解決済み binds に置き換えて @engine.Outcome を返す (spec DR-047 §4 / DR-104 §5 の
/// resolve 相)。`resolve_scope_tree` を root scope (path = []) から呼ぶ — command 木を持つ
/// scope でも単一 scope でも同一関数で扱える (`resolve_scope_tree` は has_commands が false なら
/// 再帰しないだけ、単一 scope の `resolve_scope_config` 呼び出しと等価な結果を返す)。
///
/// **転落**: resolve 相の失敗 (DR-066 の env/config seat parse 失敗 / DR-009 §7 の
/// value_filters/final_filters/accum_filters reject) は @engine.Outcome を `@engine.Failure` に転落させ、その
/// `@engine.ParseError` を errors に載せる (spec DR-053 §2 の failure ブランチが resolve 層失敗も含めて
/// 全保持、DR-047 §4「評価対象は値源ラダー充填後の最終状態」の直接の帰結)。`fired_action` /
/// `help_entry` / `tried_triggers` は None / None / [] (parse 段では発火しておらず、resolve
/// 相の failure でこれらを合成する材料は spec に規定がない — kawaz/kuu conformance の resolve
/// 系 failure fixture も同じ posture)。
///
/// `@engine.Ambiguous` / `@engine.Failure` は入力の @engine.Outcome をそのままパススルー (パース段で確定済みの意味論は
/// resolve 相で書き換えない)。**@engine.Ambiguous の各 interpretation の binds を resolve するかは
/// 現状の呼び出し規約では未定** — DR-053 §3 の interpretations は「結果オブジェクト形のビュー」
/// で並列にレンダリング要件を持つが、resolve は 1 経路ずつ呼ぶ形が自然なので、interpretation
/// ごとの解決は呼び出し側 (JSON 射影を組み立てるコード) に委ねる。現状 conformance runner も
/// interpretations の resolve は要求しない (`ambiguous` case は success 経路の binds を解決
/// するのみ、runner の `render_outcome` 参照)。
///
/// 引数は `parse()` と同じ値源 (env/config/tty)。同じ値を 2 発の関数呼び出しで渡す冗長さは
/// あるが、相区分の明示性を優先する。
pub fn resolve(
  ast : AtomicAST,
  outcome : @engine.Outcome,
  args : Array[String],
  env? : Map[String, String] = Map([]),
  config? : (String) -> @engine.ConfigVal? = fn(_p) { None },
  tty? : Map[String, TtyObs] = Map([]),
) -> @engine.Outcome {
  match outcome {
    @engine.Success(binds) =>
      match
        resolve_scope_tree_with_export(
          ast.root,
          binds,
          env,
          config,
          [],
          Map([]),
          args.length(),
          tty,
          ast.ekmap,
          true,
        ) {
        // `resolve_scope_tree` は accum entity scope (`@engine.Scoped(name, ...)` node、command でない)
        // 下の `#row`/`#fire` sentinel を path 単位の here フィルタで落とす — build_result の
        // ROW-GROUP / ACCUMULATE 分岐が発火するには sentinel が要るので、元の CLI 生 binds から
        // 拾って merge する (issue 2026-07-16 K カテゴリ、`merge_sentinels_from_origin` の
        // doc comment 参照)。
        Ok(rb) => @engine.Success(merge_sentinels_from_origin(binds, rb))
        Err(pe) =>
          @engine.Failure({
            errors: [pe],
            fired_action: None,
            help_entry: None,
            tried_triggers: [],
          })
      }
    _ => outcome
  }
}

///|
/// 正面玄関 3: `ast` に対し `args_before` (+ optional `args_after`) の補完候補集合を得る
/// (DR-060 + DR-104)。低レベル `@engine.complete_tree` (@engine.Node 直渡し、outcome.mbt) への薄いラッパー。
/// `word_before`/`word_after` は DR-104 §1 が v1 未実装のまま予約する語彙で、参照実装は
/// パラメータを持たない (本関数も同様)。
pub fn complete(
  ast : AtomicAST,
  args_before : Array[String],
  args_after? : Array[String] = [],
) -> Array[@engine.Cand] {
  @engine.complete_tree(
    @engine.ScopeNode(ast.root),
    args_before,
    defs=ast.templates,
    after=args_after,
  )
}

///|
/// 正面玄関の補助: `ast` の definition から静的に決定される export_key 写像 (DR-052) を返す。
/// `parse` の結果 (`@engine.Outcome.@engine.Success` の `Array[@engine.Binding]`) を CONFORMANCE.md §2 の
/// `result: {...}` オブジェクトへ組み立てたい利用者向けの素材 —
/// `apply_export_keys(binds, export_map(ast))` (resolve.mbt、既に `pub`) にそのまま渡せる。
///
/// 経緯 (issue 2026-07-15 front-door-export-key-map-access): `AtomicAST` は生 `@engine.Definition` を
/// 保持しない不透明ハンドルなので (本ファイル冒頭の `AtomicAST` doc)、利用者が
/// `@builtins.build_export_map` (installer.mbt、既に `pub`) を自分で呼ぶ経路が無かった。`Array[@engine.Binding]`
/// → `result` オブジェクトへの変換処理そのもの (conformance runner の `build_result` 相当) の
/// production 昇格は MDR-005 の射程外のまま — 本関数が運ぶのは「definition から決定的に導出
/// される静的写像へのアクセス」であって、encode 処理そのものではない (MDR-005 追記, 本 issue)。
pub fn export_map(ast : AtomicAST) -> Map[String, @engine.ExportKey] {
  ast.ekmap
}

///|
/// 正面玄関の補助: `resolve()` の @engine.Success payload から DR-052 result-key 軸を適用した `result`
/// オブジェクト (CONFORMANCE.md §2 の `result: {...}`) を組み立てる。runner の
/// `proj_result_export` (json_conformance_wbtest.mbt) と kuu-cli PoC の手組み `result_to_json`
/// (wire.mbt) が同一の 4 素材 (apply_export_keys/accum_cells/apply_export_to_defaults/
/// @engine.none_cells) を重複実装していた — production 昇格でその重複を解消する (issue
/// 2026-07-16-result-projection-production-promotion, MDR-005「射程外」節の解消、DR-109 §5
/// UX-Q5=a)。`binds` は `resolve()` の @engine.Success payload を渡すのが前提 (DR-109 §7「CLI は既定で
/// resolve 適用」)。実装は resolve.mbt の `build_result_export` (@engine.Scope 直渡し版) への薄い委譲 —
/// `AtomicAST` は生 `@engine.Scope` を保持しない不透明ハンドルなので、利用者が @engine.Scope を意識せず済むよう
/// ここで `ast.root`/`ast.ekmap` を代わりに渡す (`export_map` と同じ「AtomicAST から素材を引く」
/// 形、本ファイル冒頭 doc 参照)。
pub fn result(ast : AtomicAST, binds : Array[@engine.Binding]) -> RVal {
  build_result_export(ast.root, binds, ast.ekmap)
}

///|
/// 正面玄関の補助: `resolve()` の @engine.Success payload から DR-109 §3 の `sources` 射影 (「resolve 済み
/// 出力には常に sources を含める」) を組み立てる。実装は resolve.mbt の `result_sources` (command
/// 木の有無を内部で吸収する 1 本の関数、詳細はそのコメント参照) への薄い委譲 — 呼び出し側は
/// `ast`/`resolved` だけ渡せばよく、@engine.Scope の有無に関わる分岐を意識しない。
pub fn sources(
  ast : AtomicAST,
  resolved : Array[@engine.Binding],
) -> Array[SourceEntry] {
  result_sources(ast.root, resolved, ast.ekmap)
}

///|
/// 正面玄関の補助 (issue 追加分「@engine.ConfigVal/TtyObs の入力構築 API」、統括裁定 (b)): `parse()`/
/// `resolve()` の `config?` 引数 (`(path: String) -> @engine.ConfigVal?`) を組み立てたい利用者向けの JSON
/// → `@engine.ConfigVal` 全域変換。`@engine.ConfigVal` は `pub` (フィールド/variant 非公開) のまま — `@engine.CObj`/`@engine.CArr`
/// を含む全 variant を外部から直接構築する経路が無く (moonc [4036] で拒否される)、`@engine.value_to_configval`
/// (value.mbt、既存 pub) はスカラ 3 種のみで木構造の config を組めなかった。DR-050 §2「kuu core は
/// TOML/YAML を見ず、この JSON-同型 hierarchical 形だけを見る」の JSON 側の入口を production
/// として塞ぐ。旧 conformance runner の `json_to_configval` (fixture `cases[].config`/
/// `config_files` の decode ヘルパー、MDR-005 §2 で「fixture 補助入力の decode なので runner に
/// 残す」と裁定されていた) と同一ロジック — 用途が「fixture 入力の decode」から「production
/// 呼び出し側の入力構築」まで広がったため、こちらへ昇格し runner 側は本関数へ委譲する形にした
/// (MDR-005 §2 の当該裁定を本関数の追加で上書き)。オブジェクト/配列は再帰的に変換、bool/string/
/// number 以外 (JSON null 含む) は `@engine.CNull` (DR-050 §4 / DR-051「config seat が供給なしとして扱う」)
/// に落ちる — decode 失敗という概念を持たない全域関数 (`Result`/`raise` を返さない)。
pub fn config_from_json(j : Json) -> @engine.ConfigVal {
  @engine.config_from_json(j)
}

///|
/// 正面玄関の補助 (issue 追加分「@engine.ConfigVal/TtyObs の入力構築 API」、統括裁定 (b)): `parse()`/
/// `resolve()` の `tty?` 引数 (`Map[String, TtyObs]`、DR-099 §4 の stream 名 → 生観測) を組み立てたい
/// 利用者向けの構築関数。`TtyObs` は `pub` (フィールド非公開) のまま — 呼び出し側は自身で
/// `isatty(2)` 相当を観測して得た 2 つの bool (`terminal`: TTY か、`cygwin`: DR-099 §12b の
/// Cygwin/MSYS pty 判定) をここへ渡すだけでよい。config と異なり JSON 経由の入力を想定しない
/// (呼び出し側プロセスの実観測値をそのまま渡す性質のため) ので `_from_json` ではなく直接の値
/// コンストラクタとする。
pub fn tty_obs(terminal : Bool, cygwin : Bool) -> TtyObs {
  { terminal, cygwin }
}
