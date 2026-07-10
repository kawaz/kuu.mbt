# resolve フェーズの棚卸し audit — 「先詰め + 上書き」アンチパターンの有無、default_fns 未実装の影響、消費者側再解決の重複構造

2026-07-10、DR-087 の前提整理として resolve フェーズ全体を棚卸しした audit。コード変更なし、
読み取りのみ。

## 判明した事実

- **resolve フェーズに「先詰め + 上書き」アンチパターンは無い**。`resolve_ladder_below_cli`
  (`src/core/resolve.mbt:2125`) は env→config→inherit→default の短絡遅延ラダーで、default の
  計算は他の全席が不発だった場合にのみ行われる (先に default を詰めて後から上書きする構造ではない)。
  `collect_defaults` (`src/core/resolve.mbt:898`) は FLAG/BOOL セル限定で、doc comment
  (`resolve.mbt:903-910`) が「非 flag セルの default はフルラダーに依存するため、ここで注入すると
  誤った値を表出させる」というハザードを明記済み。`build_result` の DEFAULT SEAT 注入
  (`resolve.mbt:626-633`) は全 binding 収集後の gap-fill (未束縛の leaf のみ埋める) であり、
  「先詰め」ではない
- **`default_fns` は未実装**。`installer.mbt:1564` のコメントに言及があるのみで実体は無い
  (`grep` で `default_fn` の出現は当該コメント行 1 件のみ)。現状 default は静的リテラルのため、
  評価タイミングの観測差 (= 「いつ評価されたか」による値の違い) は原理的に発生しない。導入して
  現状のラダー構造を壊す要因も見当たらない
- **本命 finding**: `apply_bool_requires_filter` (`resolve.mbt:1450`) は `resolve_tree` より前に
  raw CLI-only Outcome に対して適用され、`resolved_bool_value_ladder` (`resolve.mbt:1252`) という
  自前のミニラダーで値源を再解決している。これは DR-087 の「採用しなかった案」#2 (消費者ごとの
  値源再解決) と同型の構造。優先順位ロジックが `resolve_ladder_below_cli` と 2 箇所に重複している
  (呼び出しは `resolve.mbt:1237` / `1328`)
- **CfgFiles×bool-requires に理論的観測差**: `config_obj` が単一注入のため `CfgFiles` を渡せず、
  `resolved_bool_value_ladder` からは常に `None` になる経路がある。該当する fixture が存在しない
  ため現行 conformance では顕在化していない (**未検証**であり、顕在化しないことの実証ではない)

## 実用的な示唆 / ベストプラクティス

- 根本対策は resolve の**パイプライン再構成**: resolve を無条件で先行させ、制約検査 (bool-requires
  含む) を解決済み bindings の読者として位置づける。issue `resolve-first-constraint-pipeline` が
  追跡。Ambiguous の解釈ごとに resolve を先出しする必要があり、設計規模の変更になる
- `default_fns` を導入する場合、`resolve_ladder_below_cli` と `resolved_bool_value_ladder` の
  ラダー重複が保守リスクとして先に効いてくる (優先順位変更が 2 箇所同期を要求する)。上記の
  パイプライン再構成で `resolved_bool_value_ladder` 自体を消せば、この重複リスクも同時に解消する

## 検証の詳細

### 手法

`resolve.mbt` / `installer.mbt` を対象に、default 計算・値源ラダー・requires フィルタ関連の
シンボルを `grep` で列挙し、各候補箇所を実装本体 + doc comment で読み込んで判定した。

### resolve_ladder_below_cli (resolve.mbt:2125)

env seat → config seat → inherit seat → 宣言 default の順に短絡評価する遅延ラダー。doc comment
(`resolve.mbt:2115-2123`) に「両方の呼び手 (Default effect と CLI seat 外の呼び出し) が同一の
優先順位ロジックを必要とするため 1 本の関数へ集約した」旨の設計意図が明記されている。返り値は
`resolve_entity_raw` と同型 (`Array[Binding]`)。

### collect_defaults (resolve.mbt:898) と build_result の DEFAULT SEAT (resolve.mbt:626-633)

`collect_defaults` は FLAG/BOOL セルのみを対象に default を先出しで収集する。doc comment
(`resolve.mbt:903-910`) が非 flag セルへの適用を明示的に禁じる理由 (フルラダー依存のため
誤表出のリスク) を記載済み。`build_result` 側の DEFAULT SEAT 注入は全 binding 収集の**後**に
未束縛 leaf のみを埋める gap-fill であり、両者とも「先詰め→上書き」の構造にはなっていない。

### default_fns (installer.mbt:1564)

`inst_env` の doc comment 内に「`default_fn` を wrap しない」という言及が 1 件あるのみ (実体
未実装)。`grep -n "default_fn" src/core/installer.mbt` の出力はこの 1 行のみ。

### apply_bool_requires_filter / resolved_bool_value_ladder (resolve.mbt:1237/1252/1328/1450)

`apply_bool_requires_filter` (`resolve.mbt:1450`) は `parse()` の後段、`resolve_tree` 実行前の
raw CLI-only Outcome に対して呼ばれる (呼び出し元コメント: `eval.mbt:2664`、
`json_conformance_wbtest.mbt:3939-3953`)。内部で `resolved_bool_value_ladder`
(`resolve.mbt:1252`、呼び出しは `1237` / `1328`) という自前のミニラダーを持ち、bool target の
値源を独自に再解決している。この構造は `resolve_ladder_below_cli` の優先順位ロジックと機能的に
重複しており、DR-087 が不採用とした「消費者ごとの値源再解決」パターンそのものに該当する。

`installer_wbtest.mbt:1377` の test (`DR-047 §5: requires targeting a FLAG`) が
`apply_bool_requires_filter` の挙動 (c=false 未解決・暗黙 default:false での requires 発火) を
pin している。

### CfgFiles×bool-requires の理論的ギャップ

`resolved_bool_value_ladder` へは `config_obj` が単一値として注入される経路のため、`CfgFiles`
(複数 config ファイルの重ね合わせ) を経由する値は渡せず常に `None` になる。該当する fixture
(config 複数ファイル × bool-requires の組み合わせ) は現行リポジトリに存在せず、実行時の
mismatch としては顕在化していない。

### 基準値

audit は 2026-07-10 実施、コード変更なし。conformance 基準: decoded=178 / ran_cases=464 /
mismatches=0。

## 関連

- issue `resolve-first-constraint-pipeline` (根本対策の追跡)
- DR-087 (本 audit の前提となる裁定文書)
- DR-081 (値源ラダー優先順位) / DR-031 (default seat) / DR-047 §5 (requires targeting a flag)
- `src/core/resolve.mbt` / `src/core/installer.mbt` / `src/core/eval.mbt`
