# MDR-005: kuu-core 正面玄関 API — AtomicAST ハンドル + wire decode 昇格 + 公開面キュレーション

Status: Accepted

> 由来: issue `2026-07-14-kuu-core-front-door-api.md` (kawaz 承認 2026-07-14 r14)。現状の
> `src/core` は conformance 駆動の参照エンジンで、公開面がエンジン内部型の全開
> (`pub(all)` の Node/Scope/Entity/Matcher/LongEntry/Constraint/RVal 等) になっており、
> wire JSON decoder が `json_conformance_wbtest.mbt` (テストファイル) 内に居る。本 MDR は
> **エンジンとしては再設計せず (観測挙動不変・fixture 263 本は不変)**、正面玄関のある
> ライブラリとして再包装する設計を確定する。

## 決定

### 1. 正面玄関 3 関数と `AtomicAST` ハンドル

spec (VISION.md §2, DR-054/DR-053/DR-060+DR-104) が定める 3 契約をそのまま関数名にする:

```moonbit
pub fn parse_definition(json : Json) -> Result[AtomicAST, DefLoadError]
pub fn parse(
  atomic : AtomicAST,
  args : Array[String],
  env? : Map[String, String] = Map([]),
  config? : (String) -> ConfigVal? = fn(_p) { None },
  tty? : Map[String, TtyObs] = Map([]),
) -> Outcome
pub fn resolve(
  atomic : AtomicAST,
  outcome : Outcome,
  args : Array[String],
  env? : Map[String, String] = Map([]),
  config? : (String) -> ConfigVal? = fn(_p) { None },
  tty? : Map[String, TtyObs] = Map([]),
) -> Outcome
pub fn complete(
  atomic : AtomicAST,
  args_before : Array[String],
  args_after? : Array[String] = [],
) -> Array[Cand]
```

> **追記 (issue `2026-07-15-front-door-parse-missing-postprocessing`)**: 初版の `parse` は
> `parse_tree` の薄い wrapper で、spec DR-053 の Outcome 意味論として現われる 2 段の後段処理
> (`apply_requires_filter` = DR-047 §5 明確化 = kawaz 裁定 2026-07-09 の bool-target requires
> の値源解決後判定 / `promote_collision_ambiguous` = DR-021 → DR-073 の export-key 共露出昇格)
> を通していなかった。kuu-cli PoC の dogfooding (2026-07-15) で spec 非準拠 outcome (fixtures
> `export-key/collision.json` が Success、`inheritable-parse/basic.json` の子 scope が空) を
> 返す実バグとして顕在化。以下 2 点を追加:
>
> 1. **`parse` が後段 2 段を内包する**: 内訳は `parse_tree` → `apply_requires_filter` →
>    `promote_collision_ambiguous`。`env` / `config` / `tty` を optional 引数で受け、
>    `apply_requires_filter` が候補ごとに `resolve_scope_tree` を実際に呼ぶ (値源が要る)。
>    conformance runner の手組み後段はこれで解消 = 二重実装の解消 (kuu-cli も同じ玄関を叩けば
>    spec 準拠 outcome を得る)
> 2. **`resolve` を追加する**: DR-104 §5 の相区分「dead end 判定 = parse 相、制約評価 =
>    resolve 相」に忠実に、値源ラダー (env/config/inherit/default seat fill、DR-047 §4) を
>    `parse` の Success payload に適用して解決済み binds を返す独立関数。`Failure` / `Ambiguous`
>    はパススルー、resolve 相の失敗 (DR-066 env/config seat parse 失敗、DR-009 §7 filter
>    reject) は `Failure` に転落。`resolve_scope_tree(path=[])` 一本で command 木 / 単一 scope
>    の両ケースを扱う。**採用理由**: kawaz 裁定「迷ったら 2 段案 (相区分に忠実な方) に倒す」
>    と DR-104 §5 の明文の相区分。`parse` に含める案 (= 1 段)、`parse_and_resolve` 単発ラッパー
>    の即時提供、は現状要件がないため見送り (呼び出し側便宜のラッパーは後で追加できる)
>
> **kuu-cli 側の追随**: `wire.mbt` は `front_door.parse` → `front_door.resolve` の 2 段呼び出し
> に乗り換える。sentinel 除外は `pub fn is_sentinel(k : String) -> Bool` (resolve.mbt) を利用、
> warnings 構造化は `pub fn warnings_structured(o : Outcome) -> Array[Warning]` (eval.mbt) を
> 利用する — runner にしか要らない fixture 射影 (`proj_*`) は runner 側に残す一方、下流が
> `{element, kind}` 形の JSON を組めるための production 面はここで整えた。

- **`AtomicAST`**: 新設の不透明ハンドル型 `pub struct AtomicAST { root : Scope; registry : Map[String, Node] }`。
  フィールド非公開 (`pub`、`pub(all)` ではない) — 利用者は中身を読まず `parse`/`complete` に
  渡すだけでよい。既存の lowering 結果 `Scope` と ref 解決用 `registry`
  (`definitions.templates` 由来) を 1 つに束ねる — spec の「`atomic: <AtomicAST>`」語彙
  (DR-054 §4) にそのまま対応する
- **`DefLoadError`**: 新設 `pub(all) enum DefLoadError { Malformed(String); Rejected(Array[DefError]) }`。
  `Malformed` は wire JSON の構文検査失敗 (旧 `DecodeSkip` — 未知キー・型不一致・必須キー欠如等、
  JSON Schema (`schema/wire.schema.json`) が additionalProperties を開けたまま残す語彙層の
  検査、DR-054 の `DefErrKind` 一覧には対応しない層)。`Rejected` は DR-054 §4 の
  definition-error (`Array[DefError]`、7 kind + `invalid-argument`)。2 値を分けるのは
  **層が違う失敗を同じ配列に混ぜない**ため — Malformed は「JSON がそもそも wire 形になって
  いない」、Rejected は「wire 形として正しいが仕様上不成立」
- **命名・引数名を spec 語彙に統一**: `args` (旧 `toks`)、`args_before`/`args_after` (旧
  `before`/`after`)、`candidates`(戻り値の意味論、型は `Array[Cand]` のまま)
- **既存の低レベル関数は温存・改名**: `Node` を直接受け取る現行実装 (`eval.mbt` の
  `parse(root: Node, toks, defs?, faildef?)`、`outcome.mbt` の
  `complete(root: Node, before, defs?, after?)`) は、単体テスト
  (`eval_wbtest.mbt`/`installer_wbtest.mbt`/`complete_wbtest.mbt`、手組み `Node` ツリーを
  直接叩く) が大量に依存しているため、ロジック無改変のまま `parse_tree`/`complete_tree`
  に改名して残す。正面玄関の `parse`/`complete` はこれを呼ぶ薄いラッパー
  (`parse_tree(ScopeNode(atomic.root), args, defs=atomic.registry)` 等)

### 2. wire decode の昇格

`json_conformance_wbtest.mbt` 内の definition (wire JSON) decode 関数群を新設
`src/core/wire_decode.mbt` (プロダクションモジュール) へ移動する:

- **昇格対象**: `dec_definition`/`dec_command`/`dec_option`/`dec_positional`/
  `dec_positional_group`/`dec_or`・`dec_or_structural`・`dec_or_leaf`/`dec_long`/
  `dec_repeat`/`dec_multiple`/`dec_export`/`dec_alias`/`dec_values`/`dec_str_array`/
  `dec_short`/`dec_ty`/`dec_types`/`dec_templates`・`dec_template_body`/
  `dec_scope_config`・`default_scope_config`/`dec_strs`/`dec_filter_chain`/
  `json_to_value`・`json_to_default_values`・`json_to_rval`・`json_to_configval`、および
  ヘルパー `jf_str`/`check_reserved_name`/`has_key`/`allowed_keys`/`bool_field`/`num_int`/
  `known_collector`/`auto_env_name`・`apply_env_config`。`DecodeSkip` suberror もここへ昇格し
  `pub` 化する
- **fixture ハーネス固有のまま残す**: `expect` 面の decode (`exp_*` 系一式)、`dec_case`/
  `dec_args`/`dec_def_error_case`/`dec_complete_case`、fixture 全体の decode
  (`dec_fixture`/`dec_definition_error_fixture`/`dec_complete_fixture`)、lowering fixture
  の installer 列指定 decode (`dec_installer`/`dec_installers`)、lowering 断面の decode
  (`dec_gitem`/`dec_eff_op`/`dec_pos_tnode`/`dec_tmpl_body`/`dec_lent`/`dec_lcon`/
  `dec_lsec`/`dec_lower`) — これらは definition の decode ではなく、fixture の
  「期待値 (expect)」側の decode、またはテストハーネス固有の付随入力 (installers 選択) の
  decode であり、正面玄関には現れない
- **境界判定の根拠**: `dec_fixture` (旧実装) は「definition (wire) を decode → `parse_definition`
  に通す → cases (expect 含む) を decode」の 3 段構成だった。1 段目だけが spec の
  `parse_definition` 契約に対応し、3 段目は conformance runner 固有 (fixture という
  テストデータ形式の解釈)
- **ドッグフーディング**: `dec_fixture` は昇格後の production `parse_definition(json)` を呼ぶ
  よう書き換える。decode の挙動が変われば conformance が即座に検出する

### 3. 公開面のキュレーション

**正面玄関の 3 関数が直接運ぶ型は `pub(all)` を維持** (利用者がフィールドを読む必要がある):
`Outcome`/`FailureData`/`AmbiguousData`/`AmbInterp`/`ParseError`/`ErrKind`/`Value`/`Source`/
`EffectOp`/`Binding`/`DefError`/`DefErrKind`/`Cand`/`TermHint`/`CandMeta`/`Ty`/`DefLoadError`。

**エンジン内部型は `pub` (フィールド非公開) または `priv` に格下げ**する: `Node`/`Scope`/
`Entity`/`Matcher`/`LongEntry`/`ShortEntry`/`Constraint`/`RequiredCandidate`/
`FilterSpelling`/`ElemDef`/`ElemBody`/`OrBranch`/`AliasDef`/`Variant`/`LongDecl`/
`RepeatSpec`/`CommandDef`/`Definition`/`Installer`/`ScopedCons`/`ConfigVal`/`RoundMode`/
`EqSepMode`/`AttachMode`/`BoolConfig`/`ParseFail`/`FilterSignature`/`FilterDescriptor`/
`ArrayFilterDescriptor` 等。

**MoonBit の可視性の実機確認 (2026-07-15)**: `pub(all)` は型名+全フィールド/variant を完全
公開 (構築・パターンマッチ可)。`pub` (無指定の struct/enum 修飾) は型名のみ公開しフィールド/
variant は非公開 (abstract type、外部からの直接構築・フィールドアクセス不可)。`priv` は型名も
非公開。**推移的制約**: `pub`/`pub(all)` な型のフィールド型は最低 `pub` でなければならない
(`priv` 型を `pub` struct のフィールドに使うとコンパイルエラー `[4046] A public definition
cannot depend on private type`) — この制約はフィールド自体が非公開 (`pub`) でも働く。結果、
`Scope` (`pub` 予定) が `entities: Array[Entity]` を持つ限り `Entity` も最低 `pub` が要る。
`priv` に落とせるのはどの public 型からも参照されない純粋な葉ヘルパー型のみ。

**同一パッケージ内 wbtest への影響**: 可視性はパッケージ境界に対して効く。`pub`/`priv` いずれの
関数・型も同一パッケージ (`src/core`) 内であれば構築・フィールドアクセス・呼び出しが従来通り
可能 (実機確認済み)。既存 wbtest (`Node` を手組みして `parse_tree`/`complete_tree` を直接叩く
単体テスト) は無改変で動く。

**副作用**: `pub` 化でフィールド非公開にすると、外部からの書き込みが無くなる分、コンパイラの
`unused_mut` 検査が「パッケージ内の実際の使用」だけを見るようになり、`pub(all)` 時代は
検査対象外だった不要な `mut` 修飾子 (`Entity.config_seat`/`config_key` — 代入箇所が
どこにも存在しない) が新たに `--deny-warn` エラーとして顕在化した。実装バグではなく
可視性変更の副作用として `mut` を削除する。

### 4. パッケージ構成 = 単一パッケージのまま (MDR-001 の既定路線を継続)

MoonBit の可視性 (`pub`/`priv`) だけで「型は見えるがフィールドは見えない」水準のキュレーション
が実機で成立するため、公開面キュレーションの目的は単一パッケージのままで達成できる。再輸出用
パッケージへの分割は行わない。MDR-001 §4「パッケージは `src/core` 単一から開始。公開 API が
固まってから分割する」との整合を維持し、分割判断はこの MDR (= 正面玄関の出来) を見た kawaz の
判断に委ねる (issue 由来の運び)。

## 採用しなかった案

### 低レベル `parse`/`complete` を関数名として維持し、正面玄関を別名にする

`parse_atomic`/`complete_atomic` 等の別名にすれば低レベル関数の改名が不要になり変更範囲が
縮む。しかし spec 語彙 (VISION.md §2「正面玄関 API は `parse_definition`/`parse`/`complete`」)
に `parse`/`complete` という名前そのものが規定されており、正面玄関側にこの名前を割り当てる方が
利用者から見て自然。低レベル版側を改名するコストは機械的な一括置換 (呼び出し引数は不変、関数名
のみ) で吸収でき、「観測挙動不変」の原則にも反しない

### `parse`/`complete` に `root: Node`/`registry: Map[String, Node]` を素の引数で残す (AtomicAST を作らない)

`Node` (エンジン内部の AtomicAST 表現、80+ variant) をそのまま利用者に渡すことになり、
issue が要求する「内部型 (Node 含む) の非公開化」を満たせない。`AtomicAST` でラップする追加
コストは小さく (1 struct)、正面玄関としての体裁を保つ効果が大きい

### 再輸出用パッケージ (`src/kuu_core` 等) を新設し `src/core` を完全非公開にする

MoonBit の `pub` (フィールド非公開) だけで型のカプセル化は同一パッケージ内で実現できることが
実機確認で判明したため、パッケージ分割による追加の隔離効果は薄い。パッケージ分割は import
パスの変更・moon.pkg の依存追加・ビルド構成の複雑化を伴うコストに見合わない。MDR-001 の
「最小開始」方針とも整合しない

### `Cand.path` を正面玄関の `Cand` から除いた別型を用意する

DR-104/CONFORMANCE.md §3 は `Cand` の wire 表現に `path` を含めない (同一性判定の 6
フィールドに含まれない) と規定している。理想は wire 忠実な公開専用 `Cand` 型を分離することだが、
今回は `Cand` 型自体は変更せず (観測挙動不変の原則を優先)、doc comment で「`path` は内部診断
用、spec wire 射影には含まれない」と明記するに留める。精密化は別 issue の射程

## 追記 (issue `2026-07-16-result-projection-production-promotion`、DR-109 §5 UX-Q5=a)

> 下の「射程外」節が除外していた `Outcome.Success` → `result`/`sources` の encode 処理を
> production 昇格した。DR-109 §3 (「sources は resolve 済み出力に常に含める」) の実装土台。

- **`resolve.mbt` に 2 本のヘルパーを追加**:
  - `build_result_export(sc: Scope, binds: Array[Binding], ek: Map[String, ExportKey]) -> RVal`
    — 4 素材 (`apply_export_keys`/`accum_cells`/`apply_export_to_defaults`/`none_cells`) の合成を
    一本化。runner の `proj_result_export` と kuu-cli PoC の手組み `result_to_json` (wire.mbt) が
    同一の 5 行を重複実装していたのを解消
  - `result_sources(sc: Scope, resolved: Array[Binding], ek: Map[String, ExportKey]) -> Array[SourceEntry]`
    (新設 `pub(all) struct SourceEntry { path; key; source }`) — DR-031 値源タグの sources 射影。
    command 木の有無 (`has_commands`、runner から昇格した private fn) で内部実装が
    `collect_sources_flat`/`collect_sources_tree` に分かれる (前者は export_key rename + 未発火
    セルの default フォールバックを持つ root-scope 専用、後者は resolve 済み全 binds を素の
    entity 名で木ごと拾う) が、**呼び出し側はこの分岐を意識しない** — 1 本のシグネチャで両ケースを
    覆う
- **`front_door.mbt` に薄いラッパー 2 本を追加**: `result(ast: AtomicAST, binds) -> RVal` /
  `sources(ast: AtomicAST, resolved) -> Array[SourceEntry]`。`export_map` と同じ「AtomicAST から
  素材を引く」形で `ast.root`/`ast.ekmap` を上記 2 関数に渡すだけ
- **runner (`json_conformance_wbtest.mbt`) の乗り換え**: `proj_result_export` は
  `build_result_export` + `render_rval_sorted` の薄い委譲に、`proj_sources`/`proj_sources_tree`
  は `collect_sources_flat`/`collect_sources_tree` + 文字列レンダリングの薄い委譲に書き換えた。
  **runner 自身の呼び出し箇所は `dc.resolve && has_commands(sc)` という fixture 固有の分岐
  (`resolve: <bool>` という production に存在しない対照実験ノブが絡む) を保持したまま** —
  production 向けの `result_sources` (has_commands のみで分岐) を runner が直接呼ぶことはしない。
  乗り換え後も conformance は `decoded=272 ran_cases=661 skipped=0 mismatches=0` で不変
  (moon test 352/352 green)
- **kuu-cli 側の追随は別セッション**: `wire.mbt` の `result_to_json`/`rval_to_json` は
  `@core.result(ast, rbinds)` 1 呼び出しに縮み、`sources` フィールド (現状 wire.mbt 未実装) は
  `@core.sources(ast, rbinds)` を同様に walk して追加できる

## 追記 (統括裁定「ConfigVal/TtyObs の入力構築 API」、issue 追加分 (b))

> kuu-cli (外部利用者) が `front_door.parse`/`resolve` の `env?`/`config?`/`tty?` 入力を構築
> できない不具合の解消。`ConfigVal`/`TtyObs` は `pub` (variant/フィールド非公開) のままで公開面を
> 最小に保ち、代わりに構築専用の pub 関数を front_door.mbt に追加する (§3 の可視性方針は変更なし)。

- **`front_door.mbt` に 2 本のコンストラクタ関数を追加**:
  - `config_from_json(j: Json) -> ConfigVal` — JSON → `ConfigVal` の全域変換 (CObj/CArr 再帰、
    bool/string/number 以外は `CNull`)。旧 runner `json_to_configval`
    (`json_conformance_wbtest.mbt`、fixture `cases[].config`/`config_files` の decode ヘルパー、
    本 MDR 冒頭「wire decode の昇格」節が「fixture 補助入力の decode なのでここに残す」と
    裁定していた対象) と同一ロジック — 用途が「fixture 入力の decode」から「production 呼び出し側
    の入力構築」まで広がったため、こちらへ昇格し runner 側は本関数へ委譲する形に書き換えた
    (当該裁定を本関数の追加で上書き)。`value_to_configval` (value.mbt、既存 pub) はスカラ 3 種
    のみで木構造の config を組めなかった gap の解消でもある
  - `tty_obs(terminal: Bool, cygwin: Bool) -> TtyObs` — DR-099 §4 の生観測 2 値からの直接構築。
    config と異なり JSON 経由を想定しない (呼び出し側プロセスの実観測値を直接渡す性質) ため
    `_from_json` ではない
- **runner の乗り換え**: `json_to_configval` (旧定義) を削除し `config_from_json` への直接呼び出し
  に統一。fixture の `{terminal, cygwin}` struct literal 構築も `tty_obs(terminal, cygwin)` へ
  ドッグフーディング (`dec_fixture` が `parse_definition` を呼ぶのと同じ精神)。乗り換え後も
  conformance は `decoded=272 ran_cases=661 skipped=0 mismatches=0` で不変 (moon test 354/354
  green、直前の result/sources 昇格分 352 + 本追加分の e2e wbtest 2 本)
- **e2e wbtest 2 本を追加** (`front_door_wbtest.mbt`): `config_from_json` で組んだ値が
  `config_key` 経由で result/sources (`source=config`) に反映されること、`tty_obs` で組んだ値が
  `builtin/tty` preset 型の default 席解決規則 (`fold(観測) ?? 宣言 default ?? absent`) に反映
  され観測が宣言 default に優先すること (`source=tty`) を、production API のみを叩いて固定

## 射程外 (本追記より前の記述、definition decode 昇格時点のもの)

- ~~`Outcome.Success` が運ぶ `Array[Binding]` を `result` オブジェクト (CONFORMANCE.md §2 の
  `result: {...}`) へ変換する処理 (conformance runner の `proj_result_export`/`build_result`
  相当) の production 昇格。~~ 上記追記で解消。今回の受け入れ条件は definition の decode (入力面)
  の昇格であり、結果の encode (出力面) は含まれない。**ただし** 「definition から静的に導出される
  export_key 写像 (`ekmap`) への到達経路」はこの除外の対象外 — `build_export_map`
  (installer.mbt) / `apply_export_keys` (resolve.mbt) は元々 `pub` で変換処理自体は利用者
  から既に呼べており、`AtomicAST` が生 `Definition` を保持しない不透明ハンドルであるために
  ekmap だけ到達できない穴が残っていた。issue `2026-07-15-front-door-export-key-map-access`
  (kuu-cli PoC dogfooding で発見) を受け `AtomicAST.ekmap` + `pub fn export_map(ast)` を
  追加した — encode 処理そのものの昇格ではなく、静的写像への到達経路の追加。**類似の除外
  対象外** (`2026-07-15-front-door-parse-missing-postprocessing`, 上記 §1 追記): sentinel
  判定 (`is_sentinel`, resolve.mbt) と構造化 warnings (`warnings_structured` + `Warning`,
  eval.mbt) の pub 化。前者は呼び出し側 (kuu-cli) が effects 列を組むために sentinel を除外
  する必要があり、後者は spec CONFORMANCE §2 の `warnings: [{element, kind}]` 形の JSON を
  組み立てるための production 面 (旧 `warnings_of` は element 名の配列で kind を失う)。両者
  とも「Outcome を素材として消費するときの共通判定」であって encode 処理そのものではない
- `Ambiguous` の各 interpretation の binds に対する resolve は現時点で未提供 (`resolve` は
  `Ambiguous` をパススルー)。DR-053 §3 の interpretations は「結果オブジェクト形のビュー」で
  並列レンダリング要件を持つが、interpretation ごとの解決は呼び出し側 (JSON 射影を組み立てる
  コード) の責務とする。conformance runner も現状 `ambiguous` case で interpretations の
  resolve を要求しない (`build_interpretations` が build_result を回すのは export-key 面の
  ビュー生成であって値源ラダーの解決ではない)
- kuu-core/kuu-ux のパッケージ分割の実施可否そのもの (本 MDR の成果を見て kawaz が判断)
- `word_before`/`word_after` (DR-104 が v1 未実装のまま予約) の実装

## 関連

- MDR-001 (立ち上げ方針 — 単一パッケージ最小開始の既定路線)
- MDR-002 (評価器コア設計 — `Node`/`Scope`/`Entity` 等内部型の出自)
- kawaz/kuu VISION.md §2 (正面玄関 API = `parse_definition`/`parse`/`complete` の 3 契約)
- kawaz/kuu DR-054 (`parse_definition` 契約) / DR-053 (`parse` 契約) / DR-060 + DR-104
  (`complete` 契約)
- kawaz/kuu CONFORMANCE.md §1-§4 (wire/query 語彙、`Cand`/`ParseError` の比較規約)
- issue `2026-07-14-kuu-core-front-door-api.md` (本 MDR の発端)
