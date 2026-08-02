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
//       @engine.Success(binds) => ... // binds : Array[@abi.Binding] (DR-045 の効果列)
//       @engine.Failure(data) => ... // data.errors : Array[@abi.ParseError] (DR-053 §2)
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
// // cands[i].spelling / .is_value / .type_name / .term / .is_alias / .hidden / .deprecated が候補の素材 (DR-060 §3)
// ```

///|
/// definition のロード結果 (`parse_definition` の戻り値、DR-054 §4 の `atomic: <AtomicAST>` に
/// 対応する abstract ハンドル)。型名だけを公開し、lowering 済み scope・template 解決空間・
/// resident 組成・export_key 写像・declaration は玄関内部に閉じる。利用者はフィールドを読まず、
/// `parse` / `resolve` / `complete` / `output` / `help` へ渡す。
/// `atomic` は MoonBit の予約語なので変数名には `ast` を使う。
struct AtomicAST {
  root : @engine.Scope
  templates : Map[String, @engine.Node]
  extensions : @node.Registry
  ekmap : @engine.ExportScopeMap
  declaration : @engine.Definition
  // DR-117 §2.6: definition-wide reconciled `insert_form` (canonical "space" / "eq")。
  // completion_script preset 入口の明示値が勝ち、全て省略 or 入口ゼロなら既定 `"space"`。
  // 応答 policy 段 (`completion_query`) が §5 の merge 規則で読む唯一の carrier。lowering 産物
  // (Scope / Entity) には搬送しない — declaration snapshot と対で運ぶ。
  completion_insert_form : String
}

///|
/// `parse_definition` の失敗 (spec DR-054 §4 の「definition-error」とは別に、wire JSON 自体が
/// 構文として崩れている場合を区別する、MDR-005 §1):
/// - `Malformed`: wire JSON が decode できない (未知キー・型不一致・必須キー欠如 — 旧 `DecodeSkip`
///   の写像。`schema/wire.schema.json` が additionalProperties を開けたまま残す語彙層の検査)
/// - `Rejected`: wire 形として正しいが `parse_definition` (DR-054 §1-§3) が構成不能と判定した
///   全 definition-error の列挙 (`Array[@abi.DefError]`)
pub(all) enum DefLoadError {
  Malformed(String)
  Rejected(Array[@abi.DefError])
} derive(Eq, Debug)

///|
/// 利用者へ公開する 1 件の effect。`@abi.Binding` が持つ sentinel・内部 placeholder・
/// parser bookkeeping (`levels_to_declaring_scope` / `at_pos`) は玄関で吸収し、wire の effects 列に
/// 必要な語彙だけを運ぶ。
/// `operand` は値を伴う `set` / `remove` のみ `Some`、それ以外の op は `None`。
pub struct OutputEffect {
  entity : String
  path : Array[@abi.ObservationSegment]
  op : @abi.EffectOp
  operand : @abi.Value?
  source : @abi.Source
} derive(Eq, Debug)

///|
/// `parse` / `resolve` の binds を利用者向け 3 射影へまとめた出力ビュー。`result` は repeat row
/// 境界を含む解決済み binds を既存 builder で集約し、`effects` は parse 相の発火列から sentinel と
/// config_file / none / dd の内部セルを除外し、`sources` は解決済み値の値源を返す。
pub struct OutputView {
  result : @abi.ResultValue
  effects : Array[OutputEffect]
  sources : @abi.ResultValue
} derive(Eq, Debug)

///|
/// 正面玄関 1: definition の wire JSON (`{options, positionals, commands, definitions?, config?}`)
/// を受けて AtomicAST を得る (DR-054)。`definitions.types`/`definitions.templates`
/// (DR-061 §3 / DR-078 §1) の decode、`@builtins.lower_definition` (旧 `parse_definition`、installer.mbt) の
/// 呼び出しまで一気通貫で行う。decode と lowering は同じ `extensions.installers()` を使うため、
/// 登録住人の所有語彙と実際に適用される installer chain は一致する。canonical assembly は
/// `canonical_registry()` を既定値として供給し、subset assembly も同じ玄関を利用できる。
pub fn parse_definition(
  json : Json,
  extensions? : @node.Registry = canonical_registry(),
) -> Result[AtomicAST, DefLoadError] {
  let outcome : Result[AtomicAST, DefLoadError] = try {
    let engine_extensions = extensions.extensions()
    let top = match json.j_obj() {
      Some(o) => o
      None => raise DecodeSkip("definition is not an object")
    }
    allowed_keys(
      top,
      [
        "$schema", "name", "options", "positionals", "commands", "definitions", "config",
        "help", "help_long", "help_epilog", "display_name", "value_name", "help_group_name",
        "help_group_title", "help_group_description", "help_order", "help_group_order",
        "help_after",
        // DR-115 §1.1: 一括席 `help_render` (root scope) と参考として entry 個別席
        // `help_value_structure_style` は installer 語彙で elements 側に受理されるため
        // definition top-level には出現しない (root scope 側は本 allowlist が受理)。
         "help_render",
      ],
      "definition",
    )
    match top.get("$schema") {
      Some(schema) =>
        if schema.j_str() is None {
          raise DecodeSkip("definition '$schema' is not a string")
        }
      None => ()
    }
    let templates : Map[String, @engine.Node] = Map([])
    // Design rationale: runtime parsing, completion, installer views, and AtomicAST all consume the
    // Node registry directly. Replacing that public/runtime registry with declaration nodes would
    // spread a phase conversion across those independent consumers. Keep the runtime registry and
    // carry the same decoded ElementDef tree alongside it only until lowering registers template
    // child entities; both maps are populated by the single dec_template_body traversal below.
    let template_declarations : Map[String, @engine.ElementDef] = Map([])
    let shadows = match top.get("definitions") {
      Some(dj) => {
        let d = match dj.j_obj() {
          Some(x) => x
          None => raise DecodeSkip("definitions is not an object")
        }
        allowed_keys(d, ["types", "templates"], "definitions")
        let (ts, hts) = match d.get("types") {
          Some(tj) => dec_types(tj)
          None => (Map([]), [])
        }
        match d.get("templates") {
          Some(tmplj) =>
            dec_templates(
              tmplj, ts, templates, template_declarations, extensions,
            )
          None => ()
        }
        (ts, hts)
      }
      None => (Map([]), [])
    }
    let (shadows, help_types) = shadows
    let def_raw = dec_definition(top, shadows~, extensions~)
    // DR-113 §4.2: root Definition に共有 type map (help_types) を stamp — 子孫 Definition は
    // 常に空 (dec_definition の default)。help_installer が root の help_types を読んで types
    // 集約射影を行う。
    let def = { ..def_raw, help_types, }
    match
      @node.lower_definition_snapshot(
        def,
        extensions.installers(),
        engine_extensions,
        registry=templates,
        template_declarations~,
      ) {
      Ok(lowered) =>
        Ok({
          root: lowered.scope,
          templates,
          extensions,
          ekmap: lowered.export_scopes,
          completion_insert_form: lowered.completion_insert_form,
          declaration: lowered.declaration,
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
            kind: @abi.UnknownVocab,
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
///    requires / RequiresIf は KTop (CLI 面のみ) では常に skip され、値源 (env/config)
///    が解ける後段でしか判定できない。ここで候補ごとに `resolve_scope_tree` を実際に呼んで
///    充足を確定し、生存経路数で outcome を再構成する (0 → @engine.Failure / 1 → @engine.Success / 2+ →
///    @engine.Ambiguous)。値源が空でも bool 目的語の充足条件 (「解決後値が true」) の判定は必要 —
///    `env` / `config` / `tty` が未指定なら default: false になり、requires が unfired を弾く
///    (仕様通り)
/// **相区分 (DR-104 §5)**: 値源ラダー (env/config/default seat fill) を binds に反映
/// する **resolve 相** は本関数の射程外 — 別関数 `resolve()` (下記) に切り出す。理由: parse 相
/// と resolve 相は spec の DR-104 §5 が「dead end 判定は parse 相、制約評価は resolve 相」で
/// 明示的に相区分しており、玄関 API もこれに従う (kawaz 裁定「迷ったら 2 段案 (相区分に忠実)
/// に倒す」)。したがって本関数の @engine.Success payload (`Array[@abi.Binding]`) は **CLI 由来の生 binds**
/// (`@engine.parse_tree` の直接出力、resolve 未適用) であり、`resolve()` に渡してから
/// `build_result` / `apply_export_keys` で最終 wire 表現を組み立てるのが呼び出し側の責務。
/// **なぜ 1 発 `parse_and_resolve` にしないか**: parse 相の outcome (@engine.Success/@engine.Failure/@engine.Ambiguous
/// 骨格) だけ欲しい場面 (dogfooding 用の debug、部分的な取扱、fuzz 等) と、完全 wire を組み立て
/// たい場面 (kuu-cli の JSON 出力) を型で区別する。呼び出し側便宜のラッパーが必要になれば別途足す
/// (現状は runner + kuu-cli が 2 発直列で書くだけで済む)。
///
/// 引数の値源:
///
/// - `env`: DR-050 の env provider に相当する `Map[String, String]` (キー = env var name)。
///   `apply_requires_filter` 内で `resolve_scope_tree` に渡される。未指定 = 空 Map
/// - `config`: DR-050 の config provider シグネチャ `(path: String) -> @abi.ConfigVal?`。scope ごとに
///   異なる config_file を動的に指す `CfgFiles` ケースも呼び出し元が対応する closure を渡すだけで
///   均一に扱われる (単一 @abi.ConfigVal だった旧契約の残存ギャップが解消)。未指定 = 常に `None`
///   を返す no-op provider
/// - `tty`: DR-129 §1 の tty provider (stream 名 → 端末か否かの bool の Map)。未指定 = 空 Map
///   (提供なし、CONFORMANCE §1)
fn parse_legacy(
  ast : AtomicAST,
  args : Array[String],
  env? : (String) -> String? = fn(_) { None },
  config? : (String) -> @abi.ConfigVal? = fn(_) { None },
  tty? : (String) -> Bool? = fn(_) { None },
) -> @engine.Outcome {
  let root = @engine.ScopeNode(ast.root)
  let checked = apply_requires_filter_with_export(
    @engine.parse_tree(
      root,
      args,
      defs=ast.templates,
      extensions=ast.extensions.extensions(),
    ),
    root,
    ast.templates,
    env,
    args.length(),
    config,
    tty,
    ast.ekmap,
    ast.extensions,
  )
  checked
}

///|
/// 正面玄関 2 の続き: `parse()` が返した @engine.Outcome の @engine.Success payload (CLI 生 binds) に**値源
/// ラダー**を適用し、解決済み binds に置き換えて @engine.Outcome を返す (spec DR-047 §4 / DR-104 §5 の
/// resolve 相)。`resolve_scope_tree` を root scope (path = []) から呼ぶ — command 木を持つ
/// scope でも単一 scope でも同一関数で扱える (子 command scope が無ければ再帰しないだけで、
/// 単一 scope の `resolve_scope_config` 呼び出しと等価な結果を返す)。
///
/// **転落**: resolve 相の失敗 (DR-066 の env/config seat parse 失敗 / DR-009 §7 の
/// value_filters/final_filters/accum_filters reject) は @engine.Outcome を `@engine.Failure` に転落させ、その
/// `@abi.ParseError` を errors に載せる (spec DR-053 §2 の failure ブランチが resolve 層失敗も含めて
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
fn resolve_legacy(
  ast : AtomicAST,
  outcome : @engine.Outcome,
  args : Array[String],
  env? : (String) -> String? = fn(_) { None },
  config? : (String) -> @abi.ConfigVal? = fn(_) { None },
  tty? : (String) -> Bool? = fn(_) { None },
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
          ast.extensions,
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
/// Parse CLI arguments without applying the value-source ladder.
/// Returned bindings and interpretations may only be combined with this `ast`; mixing another AST is undefined.
pub fn parse(
  ast : AtomicAST,
  args : Array[String],
  sources? : ValueSources = value_sources(),
) -> ParsedOutcome {
  match
    parse_legacy(
      ast,
      args,
      env=sources.env_,
      config=sources.config_,
      tty=sources.tty_,
    ) {
    @engine.Success(bindings) => Success({ raw: bindings })
    @engine.Failure(failure) => Failure(parse_failure(failure))
    @engine.Ambiguous(ambiguity) => {
      let interpretations : Array[Interpretation] = []
      for interpretation in ambiguity.interpretations {
        interpretations.push({ raw: interpretation })
      }
      Ambiguous({ interpretations, help_entry: ambiguity.help_entry })
    }
  }
}

///|
/// Apply the value-source ladder to parse-phase bindings.
/// `bindings` may only be combined with the `ast` whose parse produced them; mixing another AST is undefined.
pub fn resolve(
  ast : AtomicAST,
  bindings : ParsedBindings,
  args : Array[String],
  sources? : ValueSources = value_sources(),
) -> ResolvedOutcome {
  match
    resolve_legacy(
      ast,
      @engine.Success(bindings.raw),
      args,
      env=sources.env_,
      config=sources.config_,
      tty=sources.tty_,
    ) {
    @engine.Success(resolved) =>
      Success({ raw: resolved, effects_: bindings.raw })
    @engine.Failure(failure) => Failure(parse_failure(failure))
    @engine.Ambiguous(_) =>
      abort("resolve of one parsed binding path cannot be ambiguous")
  }
}

///|
/// Resolve one interpretation selected from an ambiguous parse.
/// `interpretation` may only be combined with the `ast` whose parse produced it; mixing another AST is undefined.
pub fn resolve_interpretation(
  ast : AtomicAST,
  interpretation : Interpretation,
  args : Array[String],
  sources? : ValueSources = value_sources(),
) -> ResolvedOutcome {
  resolve(ast, { raw: interpretation.raw.binds }, args, sources~)
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
) -> Array[Candidate] {
  let out : Array[Candidate] = []
  for
    candidate in @engine.complete_tree(
      @engine.ScopeNode(ast.root),
      args_before,
      defs=ast.templates,
      after=args_after,
      extensions=ast.extensions.extensions(),
    ) {
    out.push({
      spelling: candidate.spelling,
      is_value: candidate.is_value,
      type_name: candidate.ty,
      origin: candidate.origin,
      term: candidate.term,
      is_alias: candidate.is_alias,
      hidden: candidate.hidden,
      deprecated: candidate.deprecated,
      completer: candidate.completer,
    })
  }
  out
}

///|
/// package 内の white-box test が AtomicAST と result-key 軸の整合を検証するため、definition から
/// 静的に決定される export_key 写像 (DR-052) を返す。production の結果射影は `output` が担う。
fn export_map(ast : AtomicAST) -> @engine.ExportScopeMap {
  ast.ekmap
}

///|
priv struct ConfigFileCell {
  path : Array[String]
  name : String
}

///|
fn output_path_push(path : Array[String], segment : String) -> Array[String] {
  let out : Array[String] = []
  for part in path {
    out.push(part)
  }
  out.push(segment)
  out
}

///|
/// DR-118 §3 の「Default-source scalar 除外」で、result の field に対応する shadow tree 側の
/// field を引く。DR-122 により両者の object 構造とキー集合は一致する。
fn source_field(sources : @abi.ResultValue, key : String) -> @abi.ResultValue? {
  match sources {
    @abi.Object(fields) => {
      for field in fields {
        if field.0 == key {
          return Some(field.1)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn source_is_default(source : @abi.ResultValue) -> Bool {
  source == @abi.Scalar(@abi.String("default"))
}

///|
fn filter_interpretation_result(
  result : @abi.ResultValue,
  sources : @abi.ResultValue,
) -> @abi.ResultValue {
  match result {
    @abi.Object(fields) => {
      let kept : Array[(String, @abi.ResultValue)] = []
      for field in fields {
        let source = source_field(sources, field.0)
        match field.1 {
          @abi.Scalar(@abi.Null) => ()
          @abi.Scalar(_) =>
            match source {
              Some(value) if !source_is_default(value) => kept.push(field)
              _ => ()
            }
          @abi.Array(_) => kept.push(field)
          @abi.Object(_) => {
            let nested = filter_interpretation_result(
              field.1,
              source.unwrap_or(@abi.Object([])),
            )
            match nested {
              @abi.Object(items) =>
                if items.length() > 0 {
                  kept.push((field.0, nested))
                }
              _ => kept.push((field.0, nested))
            }
          }
        }
      }
      @abi.Object(kept)
    }
    _ => result
  }
}

///|
fn collect_config_file_cells(
  scope : @engine.Scope,
  path : Array[String],
  out : Array[ConfigFileCell],
) -> Unit {
  for entity in scope.entities {
    if entity.is_config_file {
      out.push({ path, name: entity.name })
    }
  }
  for node in scope.greedy {
    match node {
      @engine.CommandSatisfied(name, child) =>
        collect_config_file_cells(child, output_path_push(path, name), out)
      _ => ()
    }
  }
}

///|
/// `effects` 側の内部セル除外。effects は **宣言名軸** (DR-045: 効果は entity 単位 — entity は
/// 値セルであって露出パスではない) なので、席も宣言名のまま持つ engine の `@engine.NoneCell` /
/// `ConfigFileCell` と照合する。露出キー軸で除外する `result` / `sources` 側
/// (`internal_cells`) とは軸が違うので、両者を混ぜてはいけない。
///
/// 席の path に index segment (`#k`) が入らないのは `is_internal_cell` と同じ理由 (席は
/// 「どのセルか」であって「何番目の発火か」ではない) なので、照合前に落とす。
fn output_internal_cell(
  path : Array[String],
  name : String,
  none_cells : Array[@engine.NoneCell],
  config_file_cells : Array[ConfigFileCell],
) -> Bool {
  let seat = drop_index_segments(path)
  for cell in none_cells {
    if cell.name() == name && path_eq(cell.path(), seat) {
      return true
    }
  }
  for cell in config_file_cells {
    if cell.name == name && path_eq(cell.path, seat) {
      return true
    }
  }
  false
}

///|
fn effect_cell_key(binding : @abi.Binding) -> String {
  let out = StringBuilder::new()
  for segment in binding.scope {
    out.write_string(segment)
    out.write_char('>')
  }
  out.write_char('#')
  out.write_string(binding.key)
  out.to_string()
}

///|
/// 宣言 default を持つ座。effects 射影は resolve 相を持たないので値源ラダー (env / config) を
/// 引けないが、DR-114 §7 の `ctx.old`「発火直前の cell 値」は宣言 default までは静的に分かる。
/// `path` は宣言名軸 (`effect_cell_key` / `output_internal_cell` と同じ軸)。
priv struct DefaultSeat {
  path : Array[String]
  name : String
  value : @abi.Value
}

///|
/// `collect_config_file_cells` と同じ走査で宣言 default 席を集める。structural wrapper 配下の
/// セルは `Entity::declaring_path` が宣言名軸の相対パスを持つので、command path へ継ぎ足す。
fn collect_default_seats(
  scope : @engine.Scope,
  path : Array[String],
  out : Array[DefaultSeat],
) -> Unit {
  for entity in scope.entities {
    match default_scalar(entity) {
      Some(value) => {
        let seat = path.copy()
        for segment in entity.declaring_path {
          seat.push(segment)
        }
        out.push({ path: seat, name: entity.name, value })
      }
      None => ()
    }
  }
  for node in scope.greedy {
    match node {
      @engine.CommandSatisfied(name, child) =>
        collect_default_seats(child, output_path_push(path, name), out)
      _ => ()
    }
  }
}

///|
/// 当該 binding の座が持つ宣言 default。席は「どのセルか」なので、`output_internal_cell` と
/// 同じ理由で runtime index segment を落としてから照合する。
fn declared_default_seat(
  seats : Array[DefaultSeat],
  binding : @abi.Binding,
) -> @abi.Value? {
  let seat = drop_index_segments(binding.scope)
  for candidate in seats {
    if candidate.name == binding.key && path_eq(candidate.path, seat) {
      return Some(candidate.value)
    }
  }
  None
}

///|
/// 座 (cell) が宣言する出力 ValueType の台帳 (DR-126 §1)。値空間残余 (DR-127 §2.2) の効果適用が
/// vivify 判定・論理 null 読みに使う。`DefaultSeat` と同じ (path, name) 席の写像。
priv struct TypeSeat {
  path : Array[String]
  name : String
  value_type : @abi.ValueType
}

///|
fn collect_type_seats(
  scope : @engine.Scope,
  path : Array[String],
  out : Array[TypeSeat],
) -> Unit {
  for entity in scope.entities {
    match entity.ty.output_type() {
      Some(value_type) => {
        let seat = path.copy()
        for segment in entity.declaring_path {
          seat.push(segment)
        }
        out.push({ path: seat, name: entity.name, value_type })
      }
      None => ()
    }
  }
  for node in scope.greedy {
    match node {
      @engine.CommandSatisfied(name, child) =>
        collect_type_seats(child, output_path_push(path, name), out)
      _ => ()
    }
  }
}

///|
/// 当該 binding の座が宣言する出力 ValueType。`declared_default_seat` と同じ席合わせ。
fn declared_type_seat(
  seats : Array[TypeSeat],
  binding : @abi.Binding,
) -> @abi.ValueType? {
  let seat = drop_index_segments(binding.scope)
  for candidate in seats {
    if candidate.name == binding.key && path_eq(candidate.path, seat) {
      return Some(candidate.value_type)
    }
  }
  None
}

///|
/// 効果 1 件を「座の値状態の更新」と「観測される OutputEffect」の両方へ落とす。値状態の計算は
/// `fold_seat_effect` が唯一持ち (`resolve_entity_raw` の CLI seat と共有)、本関数に残るのは
/// 観測面の綴りだけである — cell fn を呼ぶのは `Invoke` だけなので、op が呼び出し結果で決まるのも
/// `Invoke` に限る (DR-114 §2)。
fn projected_effect(
  binding : @abi.Binding,
  seats : @fold.CellSeats,
  defaults : Array[DefaultSeat],
  types : Array[TypeSeat],
  extensions : @node.Registry,
) -> OutputEffect {
  let key = effect_cell_key(binding)
  let (entity, path) = match binding.observation {
    Some(address) => (address.entity, address.path)
    None => (binding.key, [])
  }
  let declared = declared_default_seat(defaults, binding)
  // DR-127 §6 統括裁定 3: effects の `path` の index segment は解決済みの非負値を載せる。
  // 解決は発火時点の座の現在長 (書き込み前 — 部分書きは要素を増減しない) で行い、解決でき
  // ない形 (器不在の負 index 等 = 勝ち枝では枝ローカル fold (DR-127 §4.2) が既に落とす形の、
  // 保守的スキップ経路の観測) は字面のままの best-effort に留める。
  let mut resolved_residual : Array[@abi.ObservationSegment]? = None
  let transition = if binding.value_residual.length() > 0 {
    // DR-127 §4.1 — 値空間残余の座への操作。old は座の内側の現在値 (record の宣言済み欠落は
    // 論理 null、DR-130 §4.1)。成立する書きだけ座へ反映する — Sentinel / 解決失敗で止まる
    // 判断は resolve 相 (と DR-127 §4.2 の枝ローカル fold = W2-8) の領分で、parse 相の観測は
    // 失敗で停止できないため effect の綴りをそのまま観測に落とす。
    let registry = extensions.extensions()
    let declared_ty = declared_type_seat(types, binding)
    resolved_residual = seats.resolved_residual(key, binding.value_residual)
    let container_present = seats.value_at(key, []) is Ok(_)
    let old : @abi.Value? = if container_present {
      match
        seats.value_at_declared(
          key,
          binding.value_residual,
          declared_ty,
          registry,
        ) {
        Ok(value) => Some(value)
        Err(_) => None
      }
    } else {
      None
    }
    let (transition, _) = @fold.fold_seat_effect(
      binding,
      old,
      binding.key,
      extensions.extensions(),
    )
    match transition {
      @fold.ToValue(value) =>
        // `unset` (null 返し) の空座適用は座を触らない no-op (DR-131 §7 / DR-127 §3)。
        if !(value is @abi.Null && !container_present) {
          match
            seats.set_at_declared(
              key,
              binding.value_residual,
              value,
              declared_ty,
              registry,
              vivify=binding.op is @abi.Set,
            ) {
            Ok(_) => ()
            Err(_) => ()
          }
        }
      _ => ()
    }
    transition
  } else {
    let old = seats.old(key, declared)
    let (transition, _) = @fold.fold_seat_effect(
      binding,
      old,
      binding.key,
      extensions.extensions(),
    )
    match @fold.seat_after(transition, declared) {
      Some(state) => seats.put(key, state)
      None => ()
    }
    transition
  }
  let (op, operand) = match binding.op {
    @abi.Invoke(_) =>
      match transition {
        @fold.ToValue(value) => (@abi.EffectOp::Set, Some(value))
        @fold.ToDefault => (@abi.EffectOp::Default, None)
        @fold.ToEmpty => (@abi.EffectOp::Empty, None)
        @fold.NoChange | @fold.FnMissing(_) | @fold.FnFailed(_) =>
          (binding.op, None)
      }
    @abi.Set | @abi.Remove => (binding.op, Some(binding.value))
    _ => (binding.op, None)
  }
  // 観測アドレスの末尾 (= 値空間残余ぶんの segment) を解決済み segment へ差し替える。
  // observation.path はセル空間の消費済み segment + 値空間残余の連結 (DR-127 §6) なので、
  // 差し替え対象は末尾の value_residual 長ぶんに限られる。
  let observed_path = path.copy()
  match resolved_residual {
    Some(resolved) if observed_path.length() >= resolved.length() => {
      let base = observed_path.length() - resolved.length()
      for offset in 0..<resolved.length() {
        observed_path[base + offset] = resolved[offset]
      }
    }
    _ => ()
  }
  { entity, path: observed_path, op, operand, source: binding.source }
}

///|
fn project_effects(
  ast : AtomicAST,
  binds : Array[@abi.Binding],
) -> Array[OutputEffect] {
  let none_cells = @engine.none_cells(ast.root, ast.templates)
  let config_file_cells : Array[ConfigFileCell] = []
  collect_config_file_cells(ast.root, [], config_file_cells)
  let effects : Array[OutputEffect] = []
  let seats = @fold.CellSeats::new()
  let default_seats : Array[DefaultSeat] = []
  collect_default_seats(ast.root, [], default_seats)
  let type_seats : Array[TypeSeat] = []
  collect_type_seats(ast.root, [], type_seats)
  for binding in binds {
    if (is_sentinel(binding.key) && binding.observation is None) ||
      output_internal_cell(
        binding.scope,
        binding.key,
        none_cells,
        config_file_cells,
      ) {
      continue
    }
    // CONFORMANCE §2「effects に載るのは cli / link 由来のパース時効果のみ」(DR-065): 値源ラダー
    // 充填 (env / config / default) は完走後の値確定で args 順の全順序を持たないため
    // effects には載せず、値は `result`、由来は `sources` が担う。パース相の binding は従来すべて
    // cli 由来だったのでこの gate は不要だったが、消費 0 literal (DESIGN §5.2、`literal_value`) が
    // **パース相に現れる非 cli 由来の binding** という初のケースになった — 宣言定数 (`@abi.Const`、
    // DR-031 の 8 語彙目) はユーザ操作ではないので、ラダー充填と同じくここで落とす。
    // (`unset` variant の効果はこの gate を通る: パース相での source は発火した入口の `cli` で、
    // `default` への読み替えは `result_sources` の射影が行う。)
    if binding.source is (@abi.Default | @abi.Const) {
      continue
    }
    effects.push(
      projected_effect(
        binding,
        seats,
        default_seats,
        type_seats,
        ast.extensions,
      ),
    )
  }
  effects
}

///|
/// `sources` は `result` と同一のキー体系 (CONFORMANCE.md §2) にあるので、内部セル (none /
/// config_file / dd trigger) の除外も **露出キー軸** の席 (`internal_cells`) で行う — `result`
/// 側 (`build_result_export`) が使うのと同じ席。`project_effects` が使う raw な
/// `@engine.none_cells` と照合してはいけない: `export_key` で rename された scope 配下では
/// 宣言名 path と露出 path が食い違い、除外が外れて内部セルが sources に漏れる。
fn project_sources(
  ast : AtomicAST,
  resolved : Array[@abi.Binding],
  result : @abi.ResultValue,
) -> @abi.ResultValue {
  align_sources_to_result(
    result,
    result_sources(
      ast.root,
      resolved,
      ast.ekmap,
      result,
      ast.extensions,
      templates=ast.templates,
    ),
  )
}

///|
/// 正面玄関の出力射影。`effects~` は `parse()` の Success payload、`resolved?` は
/// `resolve()` の Success payload を渡す (どちらも `Array[Binding]` なので取り違え防止に両方
/// labeled)。`resolved` 省略時は同じ binds を result/sources に使い、
/// 値源ラダーを要しない parse-only 利用も同じ OutputView 径路で表す。
/// repeat row の境界は `resolve()` が復元した `#row`/`#fire` を `build_result_export` が読む既存経路へ
/// そのまま渡し、本関数では sentinel の再 merge や row 集約を再実装しない。
fn output_legacy(
  ast : AtomicAST,
  effects~ : Array[@abi.Binding],
  resolved? : Array[@abi.Binding] = effects,
  complete_static? : Bool = true,
) -> OutputView {
  let result = build_result_export(
    ast.root,
    resolved,
    export_map(ast),
    extensions=ast.extensions,
    templates=ast.templates,
    complete_static~,
  )
  {
    result,
    effects: project_effects(ast, effects),
    sources: project_sources(ast, resolved, result),
  }
}

///|
/// DR-053 §3 の ambiguous interpretation を、resolve 相を適用しない result-object view として
/// 射影する。interpretation 自身の bindings が運ばない Default-source scalar は除外し、空
/// accumulator 配列は interpretation の構造として残す。この 2 規則により、呼び出し側は result と
/// sources を個別に組み合わせず、解釈 1 件の表示意味論を玄関から直接得られる。
/// `resolved` may only be combined with the `ast` whose parse produced it; mixing another AST is undefined.
pub fn output(ast : AtomicAST, resolved : ResolvedBindings) -> OutputView {
  output_legacy(ast, effects=resolved.effects_, resolved=resolved.raw)
}

///|
pub fn ParsedBindings::effects(
  self : ParsedBindings,
  ast : AtomicAST,
) -> Array[OutputEffect] {
  project_effects(ast, self.raw)
}

///|
/// `interp` may only be combined with the `ast` whose parse produced it; mixing another AST is undefined.
pub fn output_of_interpretation(
  ast : AtomicAST,
  interp : Interpretation,
) -> @abi.ResultValue {
  let view = output_legacy(ast, effects=interp.raw.binds, complete_static=false)
  filter_interpretation_result(view.result, view.sources)
}

///|
/// 正面玄関の補助 (issue 追加分「@abi.ConfigVal の入力構築 API」、統括裁定 (b)): `parse()`/
/// `resolve()` の `config?` 引数 (`(path: String) -> @abi.ConfigVal?`) を組み立てたい利用者向けの JSON
/// → `@abi.ConfigVal` 全域変換。`@abi.ConfigVal` は `pub` (フィールド/variant 非公開) のまま — `@abi.Object`/`@abi.Array`
/// を含む全 variant を外部から直接構築する経路が無く (moonc [4036] で拒否される)、`@extension.value_to_configval`
/// (value.mbt、既存 pub) はスカラ 3 種のみで木構造の config を組めなかった。DR-050 §2「kuu core は
/// TOML/YAML を見ず、この JSON-同型 hierarchical 形だけを見る」の JSON 側の入口を production
/// として塞ぐ。旧 conformance runner の `json_to_configval` (fixture `cases[].config`/
/// `config_files` の decode ヘルパー、MDR-005 §2 で「fixture 補助入力の decode なので runner に
/// 残す」と裁定されていた) と同一ロジック — 用途が「fixture 入力の decode」から「production
/// 呼び出し側の入力構築」まで広がったため、こちらへ昇格し runner 側は本関数へ委譲する形にした
/// (MDR-005 §2 の当該裁定を本関数の追加で上書き)。オブジェクト/配列は再帰的に変換、bool/string/
/// number 以外 (JSON null 含む) は `@abi.Null` (DR-050 §4 / DR-051「config seat が供給なしとして扱う」)
/// に落ちる — decode 失敗という概念を持たない全域関数 (`Result`/`raise` を返さない)。
pub fn config_from_json(j : Json) -> @abi.ConfigVal {
  @extension.config_from_json(j)
}
