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
  ekmap : Map[String, @engine.ExportKey]
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
/// parser bookkeeping (`link` / `at_pos`) は玄関で吸収し、wire の effects 列に必要な語彙だけを運ぶ。
/// `operand` は値を伴う `set` / `remove` のみ `Some`、それ以外の op は `None`。
pub struct OutputEffect {
  entity : String
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
  sources : Array[SourceEntry]
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
          Some(tmplj) => dec_templates(tmplj, ts, templates, extensions)
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
      ) {
      Ok(lowered) =>
        Ok({
          root: lowered.scope,
          templates,
          extensions,
          ekmap: @engine.build_export_map(def, engine_extensions),
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
///    requires / RequiresIf は KTop (CLI 面のみ) では常に skip され、値源 (env/config/inherit)
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
/// に倒す」)。したがって本関数の @engine.Success payload (`Array[@abi.Binding]`) は **CLI 由来の生 binds**
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
/// - `config`: DR-050 の config provider シグネチャ `(path: String) -> @abi.ConfigVal?`。scope ごとに
///   異なる config_file を動的に指す `CfgFiles` ケースも呼び出し元が対応する closure を渡すだけで
///   均一に扱われる (単一 @abi.ConfigVal だった旧契約の残存ギャップが解消)。未指定 = 常に `None`
///   を返す no-op provider
/// - `tty`: DR-099 §4 の tty provider (stream 名 → 生観測 `TtyObs` の Map)。未指定 = 空 Map
///   (提供なし、CONFORMANCE §1)
fn parse_legacy(
  ast : AtomicAST,
  args : Array[String],
  env? : (String) -> String? = fn(_) { None },
  config? : (String) -> @abi.ConfigVal? = fn(_) { None },
  tty? : (String) -> TtyObs? = fn(_) { None },
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
          ast.extensions,
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
  tty? : (String) -> TtyObs? = fn(_) { None },
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
fn export_map(ast : AtomicAST) -> Map[String, @engine.ExportKey] {
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
fn interpretation_has_source(
  sources : Array[SourceEntry],
  path : Array[String],
  key : String,
) -> Bool {
  for source in sources {
    if source.key == key && source.path == path && source.source != @abi.Default {
      return true
    }
  }
  false
}

///|
fn interpretation_has_claimant(
  claimants : Array[(String, String)],
  key : String,
) -> Bool {
  for claimant in claimants {
    if claimant.0 == key {
      return true
    }
  }
  false
}

///|
fn filter_interpretation_result(
  result : @abi.ResultValue,
  sources : Array[SourceEntry],
  claimants : Array[(String, String)],
  path : Array[String],
) -> @abi.ResultValue {
  match result {
    @abi.Object(fields) => {
      let kept : Array[(String, @abi.ResultValue)] = []
      for field in fields {
        if interpretation_has_source(sources, path, field.0) ||
          interpretation_has_claimant(claimants, field.0) {
          kept.push(field)
        } else {
          match field.1 {
            @abi.Scalar(_) => ()
            @abi.Array(_) => kept.push(field)
            @abi.Object(_) => {
              let nested = filter_interpretation_result(
                field.1,
                sources,
                claimants,
                output_path_push(path, field.0),
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
fn output_internal_cell(
  path : Array[String],
  name : String,
  none_cells : Array[@engine.NoneCell],
  config_file_cells : Array[ConfigFileCell],
) -> Bool {
  for cell in none_cells {
    if cell.name() == name && path_eq(cell.path(), path) {
      return true
    }
  }
  for cell in config_file_cells {
    if cell.name == name && path_eq(cell.path, path) {
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
fn root_entity(ast : AtomicAST, binding : @abi.Binding) -> @engine.Entity? {
  if binding.scope.length() > 0 {
    return None
  }
  for entity in ast.root.entities {
    if entity.name == binding.key {
      return Some(entity)
    }
  }
  None
}

///|
fn projected_effect(
  ast : AtomicAST,
  binding : @abi.Binding,
  current : Map[String, @abi.Value],
) -> OutputEffect {
  let key = effect_cell_key(binding)
  match binding.op {
    @abi.Invoke(invocation) => {
      let old = match current.get(key) {
        Some(value) => Some(value)
        None =>
          match root_entity(ast, binding) {
            Some(entity) =>
              match entity.default_values {
                Some([value]) => Some(value)
                _ => None
              }
            None => None
          }
      }
      match ast.extensions.lookup_cell_fn(invocation.name) {
        Some(descriptor) => {
          let observes = match descriptor.concrete_observes(invocation) {
            Ok(edges) => edges
            Err(_) => []
          }
          let ctx = @extension.FnCtx::for_effect(
            binding.key,
            binding.key,
            old~,
            observes~,
          )
          match descriptor.invoke(invocation.to_call(), ctx) {
            Ok(@extension.FnOutput::Value(value)) => {
              current.set(key, value)
              return {
                entity: binding.key,
                op: @abi.Set,
                operand: Some(value),
                source: binding.source,
              }
            }
            Ok(@extension.FnOutput::Sentinel(sentinel)) => {
              let op = match sentinel {
                @extension.CellSentinel::UseDefault => @abi.EffectOp::Default
                @extension.CellSentinel::Unset => @abi.EffectOp::Unset
                @extension.CellSentinel::Empty => @abi.EffectOp::Empty
              }
              return {
                entity: binding.key,
                op,
                operand: None,
                source: binding.source,
              }
            }
            Err(_) => ()
          }
        }
        None => ()
      }
      {
        entity: binding.key,
        op: binding.op,
        operand: None,
        source: binding.source,
      }
    }
    @abi.Set | @abi.Remove => {
      current.set(key, binding.value)
      {
        entity: binding.key,
        op: binding.op,
        operand: Some(binding.value),
        source: binding.source,
      }
    }
    _ =>
      {
        entity: binding.key,
        op: binding.op,
        operand: None,
        source: binding.source,
      }
  }
}

///|
fn project_effects(
  ast : AtomicAST,
  binds : Array[@abi.Binding],
) -> Array[OutputEffect] {
  let none_cells = @engine.none_cells(ast.root)
  let config_file_cells : Array[ConfigFileCell] = []
  collect_config_file_cells(ast.root, [], config_file_cells)
  let effects : Array[OutputEffect] = []
  let current : Map[String, @abi.Value] = Map([])
  for binding in binds {
    if is_sentinel(binding.key) ||
      output_internal_cell(
        binding.scope,
        binding.key,
        none_cells,
        config_file_cells,
      ) {
      continue
    }
    effects.push(projected_effect(ast, binding, current))
  }
  effects
}

///|
fn project_sources(
  ast : AtomicAST,
  resolved : Array[@abi.Binding],
) -> Array[SourceEntry] {
  let none_cells = @engine.none_cells(ast.root)
  let config_file_cells : Array[ConfigFileCell] = []
  collect_config_file_cells(ast.root, [], config_file_cells)
  let projected : Array[SourceEntry] = []
  for entry in result_sources(ast.root, resolved, ast.ekmap) {
    if !output_internal_cell(
        entry.path,
        entry.key,
        none_cells,
        config_file_cells,
      ) {
      projected.push(entry)
    }
  }
  projected
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
) -> OutputView {
  {
    result: build_result_export(
      ast.root,
      resolved,
      export_map(ast),
      extensions=ast.extensions,
    ),
    effects: project_effects(ast, effects),
    sources: project_sources(ast, resolved),
  }
}

///|
/// DR-053 §3 の ambiguous interpretation を、resolve 相を適用しない result-object view として
/// 射影する。interpretation 自身の bindings が運ばない Default-source scalar は除外する一方、
/// DR-073 §1 の claimants に載る key の default は衝突 provenance を保つため残し、空 accumulator
/// 配列は interpretation の構造として残す。この 3 規則により、呼び出し側は result と sources を
/// 個別に組み合わせず、解釈 1 件の表示意味論を玄関から直接得られる。
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
  let view = output_legacy(ast, effects=interp.raw.binds)
  filter_interpretation_result(
    view.result,
    view.sources,
    interp.raw.claimants,
    [],
  )
}

///|
/// 正面玄関の補助 (issue 追加分「@abi.ConfigVal/TtyObs の入力構築 API」、統括裁定 (b)): `parse()`/
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

///|
/// 正面玄関の補助 (issue 追加分「@abi.ConfigVal/TtyObs の入力構築 API」、統括裁定 (b)): `parse()`/
/// `resolve()` の `tty?` 引数 (`Map[String, TtyObs]`、DR-099 §4 の stream 名 → 生観測) を組み立てたい
/// 利用者向けの構築関数。`TtyObs` は `pub` (フィールド非公開) のまま — 呼び出し側は自身で
/// `isatty(2)` 相当を観測して得た 2 つの bool (`terminal`: TTY か、`cygwin`: DR-099 §12b の
/// Cygwin/MSYS pty 判定) をここへ渡すだけでよい。config と異なり JSON 経由の入力を想定しない
/// (呼び出し側プロセスの実観測値をそのまま渡す性質のため) ので `_from_json` ではなく直接の値
/// コンストラクタとする。
pub fn tty_obs(terminal : Bool, cygwin : Bool) -> TtyObs {
  { terminal, cygwin }
}
