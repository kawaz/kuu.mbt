# DR Index

引数定義 AST 設計の決定記録 (Design Record) 一覧。

## 基盤
- [DR-001](DR-001-two-layer-ast.md): 2層 AST 構造 (UsefulAST / AtomicAST)
- [DR-002](DR-002-element-isomorphism.md): 全要素は同型、CLI 慣習名はシュガー
- [DR-015](DR-015-value-propagation.md): 値の発生と伝搬の構造的セマンティクス
- [DR-017](DR-017-command-first-class-at-definition.md): command は定義時1級、パース時同型
- [DR-023](DR-023-structural-primitives-finalized.md): 構造プリミティブ確定形 (4 + multiple + 糖衣)

## トップダウン再設計 (2026-06)
- [DR-018](DR-018-placement-and-commands-sugar.md): 配置で区別、commands は positionals 内 or 糖衣
- [DR-019](DR-019-repeat-merged-into-multiple.md): repeat を multiple に統合、可変長 positional
- [DR-020](DR-020-recursion-via-primitives.md): 復帰/途中分岐は専用概念を持たず構造で組む
- [DR-021](DR-021-longest-match-and-ambiguous.md): 最長一致パース、露出キー一意性は実行時検査
- [DR-022](DR-022-snake-case-naming.md): キー名 snake_case、case 変換 pluggable

## node 構造 (2026-06、トップダウン詰め直し)
- [DR-024](DR-024-three-name-layers.md): 名前は3層 (key name / def name / value_name)
- [DR-025](DR-025-name-creates-scope.md): name が結果スコープを作る、露出は最も浅い name 層、object は帰結
- [DR-026](DR-026-leaf-branch-and-sugar.md): 葉/枝、exact は値プリミティブの一種、構造記法の糖衣 (裸文字列=exact, 裸配列=seq)
- [DR-027](DR-027-serial-renamed-seq.md): serial → seq 改名 (or/seq/multiple = alternation/concatenation/closure)
- [DR-028](DR-028-type-as-reference.md): type は definitions/registry への参照糖衣、解決順 (definitions→registry→warn+string)、前方互換、flag等は糖衣プリセット

## link / 値源 (2026-06、ref/link 見直し)
- [DR-029](DR-029-link-revisited.md): link 見直し (値同期、1実体:N参照、固定パス DSL .name/[int]/[-1]、遅延解決、失敗=パース失敗)
- [DR-030](DR-030-entity-only-node.md): 実体だけノード (入口属性なしの値ノード、appconfig ストア用途)
- [DR-031](DR-031-value-source-precedence.md): 値源の優先順位 (CLI/link > env > config > inherit > default、固定)
- [DR-032](DR-032-ref-link-name-resolution.md): ref/link が指すのは name (解決はスコープ内→definitions)、type とは別物。DR-028 のref→type統合を撤回

## 識別とスコープ
- [DR-003](DR-003-name-three-axes.md): name は3軸 (CLI起動/結果key/内部参照) を兼任
- [DR-006](DR-006-scope-and-lexical-resolution.md): スコープは自動、lexical scope chain で解決

## 構造
- [DR-004](DR-004-options-positionals-split.md): options / positionals の2分割、commands は or でラップ
- [DR-007](DR-007-definitions-ref-link.md): definitions 領域、ref (構造継承) と link (値同期)

## 値と型
- [DR-005](DR-005-type-categories.md): type の3カテゴリと子からの値型推論
- [DR-008](DR-008-multiple-field.md): multiple フィールドに複数値関連を統合

## 処理パイプライン
- [DR-009](DR-009-filter-chain.md): filter chain の3段 (preSplit / per-item / post)
- [DR-011](DR-011-variant-dsl.md): variant の文字列 DSL と オブジェクト形式

## 制約と継承
- [DR-012](DR-012-constraints-as-attributes.md): 制約は要素属性で表現
- [DR-013](DR-013-inherit-inheritable.md): inherit / inheritable で階層継承
- [DR-014](DR-014-config-field.md): config フィールドで階層継承可能な設定

## 実装連携
- [DR-010](DR-010-external-registry.md): 外部レジストリの階層化と暗黙参照
- [DR-016](DR-016-result-and-context.md): 結果オブジェクトと ParserContext の2層

## 議論経緯

ここに記録された決定は、対話の中で何度か方向修正したものが多数。Claude が安易に提案した複雑化を kawaz が指摘して却下、というパターンが繰り返されている。

主な反省パターン (詳細は `journal/2026-06-25-session1-context.md`):
1. 概念を勝手に膨らませる
2. 新フィールドを安易に提案
3. CLI 慣習を当たり前に持ち込む
4. 暗黙ルールを増やしがち
5. 責務混在
- [DR-033](DR-033-lexical-scope-equals-name-scope.md): lexical スコープ = name が作るスコープ

## multiple / registry / エラー (2026-06、全体読み直し後)
- [DR-034](DR-034-multiple-structure.md): multiple の構造モデル (peaceProcessor/separator/mapper/collector、縮退ケース、type と multiple は同じ属性平面)
- [DR-035](DR-035-definitions-registry-symmetry.md): definitions は registry と同じ区分の名前空間、解決順の一様化
- [DR-036](DR-036-multiple-registry-and-accumulators.md): multiple registry 追加、accumulators の属性セット拡張、collectors は filters で代替
- [DR-037](DR-037-filter-reject-error-and-branch-resolution.md): filter の Reject/Error 区別、解けた枝の数による結末分類 (DR-021 補完)
