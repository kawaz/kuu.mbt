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
pub fn parse(atomic : AtomicAST, args : Array[String]) -> Outcome
pub fn complete(
  atomic : AtomicAST,
  args_before : Array[String],
  args_after? : Array[String] = [],
) -> Array[Cand]
```

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

## 射程外

- `Outcome.Success` が運ぶ `Array[Binding]` を `result` オブジェクト (CONFORMANCE.md §2 の
  `result: {...}`) へ変換する処理 (conformance runner の `proj_result_export`/`build_result`
  相当) の production 昇格。今回の受け入れ条件は definition の decode (入力面) の昇格であり、
  結果の encode (出力面) は含まれない
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
