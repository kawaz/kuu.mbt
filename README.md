# kuu 引数定義 AST (トップダウン再設計)

> 状態: 設計議論中、未確定事項あり (2026-06 時点)

kuu (https://github.com/kawaz/kuu.mbt) の引数定義 AST を、言語非依存な JSON 仕様としてゼロベースから設計し直す議論の場。

## 番号空間の注意

このツリーで使う DR 番号は **本体 kuu.mbt の `docs/decisions/` (DR-001〜) とは別系統**。
同じ番号でも別物 — 相互参照する場合は必ず系統を明示する (例: 本体側 DR-NNN、AST 側 DR-NNN)。

このツリーは `initial empty commit` から枝分かれした **独立した jj workspace** で、
本体実装とは別管理。後で合流させるかは要件次第 (現状: 合流の必要性は薄い)。

## 構成

```
ast-spec/
├── README.md
└── docs/
    ├── DESIGN.md            — AST 仕様の網羅ドキュメント (旧 AST-SPEC.md)
    ├── decisions/
    │   ├── INDEX.md         — DR 一覧
    │   └── DR-NNN-*.md      — 各決定の経緯と理由 (DR-001〜040)
    └── journal/
        ├── 2026-06-25-session1-context.md     — セッション1ハンドオフ (旧 CONTEXT.md)
        └── 2026-06-26-session2-dr038-040.md   — セッション2ハンドオフ (旧 SESSION-HANDOFF.md)
```

## 議論を再開する手順

1. `docs/journal/2026-06-25-session1-context.md` を読む (議論のスタンス、確定事項、未確定論点 A〜M)
2. `docs/journal/2026-06-26-session2-dr038-040.md` を読む (DR-038/039/040 までの到達点と次の一手)
3. `docs/DESIGN.md` を眺める (現状の整理)
4. 必要な DR を参照 (決定の理由)
5. 未確定論点から進めたいものを選ぶ
6. 進めながら新しい決定があれば DR を追加 (続きは DR-041〜)

## 主な決定の要点

### 第1セッション (DR-001〜037)

- **2層 AST**: UsefulAST (人間/各言語DXコード) と AtomicAST (パーサ正規形) の分離
- **全要素は同型**: CLI 慣習名 (フラグ/サブコマンド/positional) はシュガーへの愛称
- **name は3軸を兼任**: CLI起動/結果key/内部参照、必要なら exportKey で分離
- **options / positionals の2分割**: commands は positionals 内の or でラップ
- **type は要素単位**: 配列・map は multiple フィールドで表現
- **filter chain 3段**: preSplit / per-item / post
- **variant DSL**: 文字列 `"no:set:false"` または オブジェクト形式
- **外部レジストリ**: types / filters / accumulators / handlers / ...
- **階層継承**: inherit (defaultValue) / inheritable (祖先 scope での書き込み)

### トップダウン再設計の整理 (DR-017〜037)

- **command は定義時1級・パース時同型** (DR-017): DR-002 の同型は AtomicAST に限定
- **配置で区別・commands は or 糖衣** (DR-018): `positionals:[{or:[...commands,...positionals]}]`
- **repeat → multiple 統合・4プリミティブ** (DR-019): `rm path...` / `mv a b c dst` が書ける
- **復帰/途中分岐は構造で組む** (DR-020): 専用概念を持たない
- **最長一致パース・露出キー一意性は実行時** (DR-021): warn はする reject はしない
- **キー名 snake_case・case 変換 pluggable** (DR-022)
- **構造プリミティブ確定形** (DR-023): {exact, or, serial, primitive} + multiple + 糖衣

### 第2セッション (DR-038〜040)

- **DR-038 パース意味論の確定**: 完全経路の一意性 = 0/1/2+ → 失敗/成功/ambiguous。最長一致は規則として廃止し創発に降格
- **DR-039 合流テーゼ**: AtomicAST = 既存エンジンのノードグラフのシリアライズ形。垂直スライスで共設計
- **DR-040 type registry 方言運用**: 3層上書き、方言軸2分、寛容default + pre_filter制限が素の経路

詳細は `docs/DESIGN.md` と各 DR を参照。

## 議論の主要参加者

- kawaz: kuu の設計者、引数定義 AST の議論を主導
- Claude (AI): 議論相手、整理と提案を担当

議論のスタンス: 概念を勝手に膨らませない、暗黙ルールを増やさない、CLI 慣習にバイアスをかけない、忖度しない。
詳細は `docs/journal/2026-06-25-session1-context.md` を参照。
