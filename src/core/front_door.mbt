// front_door.mbt — kuu-core の正面玄関 (MDR-005)。
//
// spec (kawaz/kuu VISION.md §2) が定める 3 契約 parse_definition (DR-054) / parse (DR-053) /
// complete (DR-060 + DR-104) を、命名・引数名とも spec 語彙に一致させて公開する。内部の
// Node/Scope 木を直接叩く低レベル実装 (parse_tree/complete_tree, eval.mbt/outcome.mbt) は
// このファイルからだけ呼ばれる — 利用者が Node の 80+ variant を意識する必要はない。
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
//       Success(binds) => ... // binds : Array[Binding] (DR-045 の効果列)
//       Failure(data) => ... // data.errors : Array[ParseError] (DR-053 §2)
//       Ambiguous(data) => ... // data.interpretations (DR-053 §3)
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
/// だけでよい。`root` は lowering 済みの AtomicAST (`Scope`)、`registry` は
/// `definitions.templates` 由来の ref 解決空間 (`lower_definition` が要求する第 3 引数と同じ)。
/// `ekmap` は definition から静的に決定される export_key 写像 (DR-052、`build_export_map` の
/// 結果) — `export_map` (下記) 経由で読める (issue 2026-07-15
/// front-door-export-key-map-access: `parse`/`complete` の結果を CONFORMANCE.md §2 の
/// `result: {...}` へ組み立てたい利用者が、AtomicAST から生 `Definition` を復元できず
/// `build_export_map` を自分で呼べなかった)。ekmap は definition が確定した時点で決定的に
/// 導出される静的情報なので、AtomicAST と生存期間が一致する — ここに同梱するのが自然。
/// `atomic` は MoonBit の予約語 (将来使用のため) なので変数名には `ast` を使う。
pub struct AtomicAST {
  root : Scope
  registry : Map[String, Node]
  ekmap : Map[String, ExportKey]
}

///|
/// `parse_definition` の失敗 (spec DR-054 §4 の「definition-error」とは別に、wire JSON 自体が
/// 構文として崩れている場合を区別する、MDR-005 §1):
/// - `Malformed`: wire JSON が decode できない (未知キー・型不一致・必須キー欠如 — 旧 `DecodeSkip`
///   の写像。`schema/wire.schema.json` が additionalProperties を開けたまま残す語彙層の検査)
/// - `Rejected`: wire 形として正しいが `parse_definition` (DR-054 §1-§3) が構成不能と判定した
///   全 definition-error の列挙 (`Array[DefError]`)
pub(all) enum DefLoadError {
  Malformed(String)
  Rejected(Array[DefError])
} derive(Eq, Debug)

///|
/// 正面玄関 1: definition の wire JSON (`{options, positionals, commands, definitions?, config?}`)
/// を受けて AtomicAST を得る (DR-054)。`definitions.types`/`definitions.templates`
/// (DR-061 §3 / DR-078 §1) の decode、`lower_definition` (旧 `parse_definition`、installer.mbt) の
/// 呼び出しまで一気通貫で行う — installer 順序は常に `full_installers()` (DR-042 §canonical set、
/// 5 invariants により順序無依存)、呼び出し側が installer 順序を選ぶ理由は無い (順序を選べるのは
/// conformance runner の lowering fixture だけの関心、DR-070)。
pub fn parse_definition(json : Json) -> Result[AtomicAST, DefLoadError] {
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
    let registry : Map[String, Node] = Map([])
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
          Some(tmplj) => dec_templates(tmplj, ts, registry)
          None => ()
        }
        ts
      }
      None => Map([])
    }
    let def = dec_definition(top, shadows~)
    match lower_definition(def, full_installers(), registry~) {
      Ok(root) => Ok({ root, registry, ekmap: build_export_map(def) })
      Err(errs) => Err(Rejected(errs))
    }
  } catch {
    DecodeSkip(reason) => Err(Malformed(reason))
  } noraise {
    r => r
  }
  outcome
}

///|
/// 正面玄関 2: `ast` に対し `args` を解決する (DR-053)。低レベル `parse_tree` (Node 直渡し、
/// eval.mbt) への薄いラッパー — `ast.registry` を ref 解決空間として thread する。
pub fn parse(ast : AtomicAST, args : Array[String]) -> Outcome {
  parse_tree(ScopeNode(ast.root), args, defs=ast.registry)
}

///|
/// 正面玄関 3: `ast` に対し `args_before` (+ optional `args_after`) の補完候補集合を得る
/// (DR-060 + DR-104)。低レベル `complete_tree` (Node 直渡し、outcome.mbt) への薄いラッパー。
/// `word_before`/`word_after` は DR-104 §1 が v1 未実装のまま予約する語彙で、参照実装は
/// パラメータを持たない (本関数も同様)。
pub fn complete(
  ast : AtomicAST,
  args_before : Array[String],
  args_after? : Array[String] = [],
) -> Array[Cand] {
  complete_tree(
    ScopeNode(ast.root),
    args_before,
    defs=ast.registry,
    after=args_after,
  )
}

///|
/// 正面玄関の補助: `ast` の definition から静的に決定される export_key 写像 (DR-052) を返す。
/// `parse` の結果 (`Outcome.Success` の `Array[Binding]`) を CONFORMANCE.md §2 の
/// `result: {...}` オブジェクトへ組み立てたい利用者向けの素材 —
/// `apply_export_keys(binds, export_map(ast))` (resolve.mbt、既に `pub`) にそのまま渡せる。
///
/// 経緯 (issue 2026-07-15 front-door-export-key-map-access): `AtomicAST` は生 `Definition` を
/// 保持しない不透明ハンドルなので (本ファイル冒頭の `AtomicAST` doc)、利用者が
/// `build_export_map` (installer.mbt、既に `pub`) を自分で呼ぶ経路が無かった。`Array[Binding]`
/// → `result` オブジェクトへの変換処理そのもの (conformance runner の `build_result` 相当) の
/// production 昇格は MDR-005 の射程外のまま — 本関数が運ぶのは「definition から決定的に導出
/// される静的写像へのアクセス」であって、encode 処理そのものではない (MDR-005 追記, 本 issue)。
pub fn export_map(ast : AtomicAST) -> Map[String, ExportKey] {
  ast.ekmap
}
