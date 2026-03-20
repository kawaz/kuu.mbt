# Decision Records Index

## Active

| # | Title | Type | Status |
|---|---|---|---|
| DR-006 | Phase 4: Reducer 大統一設計 (String-Based) | decision | superseded |
| DR-007 | Opts enum + ResultMap + immutable Opt + greedy/never 設計 | decision | superseded |
| DR-008 | ReduceCtx 統一 + フックアーキテクチャ | decision | active |
| DR-009 | 実装計画の再構築 | decision | active |
| DR-010 | 先食い最長一致 Reducer モデルとマルチペルソナレビュー修正 | decision | active |
| DR-011 | プロジェクト名の検討 (kuu) | discussion | active |
| DR-012 | ExactNode アーキテクチャへの設計転換 | decision | active |
| DR-013 | ParseResult アクセスパターン設計 | decision | active |
| DR-014 | 否定パターンとプレフィックスペアの2軸分解 | decision | superseded |
| DR-016 | FilterChain による pre/post フィルタ設計 | decision | active |
| DR-017 | parse_raw 特殊分岐の ExactNode 化 | decision | active |
| DR-018 | dashdash / append_dashdash + stop_before 設計 | decision | active |
| DR-019 | Optional Value Option 設計 | decision | superseded |
| DR-020 | 汎用 or コンビネータ + Initial[T] 設計 | decision | active |
| DR-021 | exclusive/required バリデーション + is_set 追跡設計 | decision | active |
| DR-022 | never + serial コンビネータ設計 | decision | active |
| DR-023 | マージ可能リストオプション (+/- 修飾子と ... 展開) | decision | active |
| DR-024 | コンビネータパラメータ共通化 | decision | active |
| DR-025 | コンビネータの Compositional 分解 | decision | active |
| DR-026 | sub() API / require_cmd() / parse 単一呼び出し制約 | decision | active |
| DR-027 | core 純粋関数主義 + 多言語 DX レイヤー構想 | decision | active |
| DR-028 | cmd → Opt[CmdResult] 統合 | decision | active |
| DR-029 | 言語境界を越える Serialize/Deserialize 設計構想 | decision | active |
| DR-030 | opt AST の言語間ポータビリティ | decision | active |
| DR-031 | kubectl example の設計 | implementation | active |
| DR-034 | greedy/non-greedy による OC/P フェーズ分離の再導入 | decision | active |
| DR-035 | WASM bridge 拡張 (JSON 表現可能な全機能の対応) | decision | active |
| DR-036 | KuuCore 各言語向け統一低レベル API 設計 | decision | active |
| DR-037 | alias プリミティブ設計 (clone/link/adjust 直交プリミティブ) | decision | active |
| DR-038 | 多角的コードレビュー (5ペルソナ) の知見 | review | active |
| DR-039 | サブパーサコンビネータの抽象化 | decision | active |
| DR-040 | deprecated コンビネータ実装 + clone/adjust 設計分析 | decision | active |
| DR-041 | 環境変数コンビネータ設計構想 | vision | active |
| DR-042 | struct-first DX 層設計 (Parseable trait + apply_fn 方式) | decision | active |
| DR-043 | Opt[T] に priv setter を追加 | decision | superseded |
| DR-044 | clone / link / adjust コンビネータ実装 | decision | superseded |
| DR-045 | ValCell / Accessor 分離 | decision | active |
| DR-047 | kuu-cli embed+extract+exec パターン | decision | active |
| DR-048 | Accessor.is_set を Opt.used に分離 | decision | active |
| DR-049 | サロゲートペア対応 (unicodegrapheme 導入) | implementation | active |
| DR-050 | Filter 充実 + Sugar コンビネータ追加 | implementation | active |
| DR-051 | 20260318 Example レビュー知見 | review | active |
| DR-052 | ErrorKind 構造化エラー | decision | active |
| DR-053 | プリミティブ分解 (name/exact/serial/or) | decision | active |
| DR-054 | float DX層・WASM bridge 対応 | implementation | active |
| DR-055 | register_option の option/long/short 分解 | decision | active |
| DR-056 | WASM bridge 機能ギャップ解消 | implementation | active |
| DR-057 | kuu-cli 言語非依存の独立コマンド構想 | vision | active |
| DR-058 | 構造化エラー表示 (clap v4 準拠4層フォーマット) | implementation | draft |
| DR-059 | kuu-cli Native CLI 実装 | decision | draft |

### Superseded の経緯

| DR | 置き換え先 | 理由 |
|---|---|---|
| DR-006 | DR-007 | String ベース中間表現から Opts enum + ResultMap 方式に移行 |
| DR-007 | DR-012, DR-013 | Opts enum を ExactNode ベースに、ResultMap を ParseResult + Ref[T] に置換 |
| DR-014 | DR-024 | 2軸分解 (negate x prefix_pair) を 1軸の Variation リストに統合 |
| DR-019 | DR-020 | choices: Array[String] が退化形。汎用 or コンビネータで再設計 |
| DR-043 | DR-045 | priv setter が ValCell/Accessor に発展的統合 |
| DR-044 | DR-045 | clone/link/adjust の v1 実装が ValCell/Accessor 分離で大幅に進化 |

## Archived

初期 PoC・議論ログ。設計コンテキストとしての参照用。

| # | Title | Type |
|---|---|---|
| DR-001 | Phase 1-3 PoC 設計記録 | decision |
| DR-002 | Phase 4 設計議論ログ | discussion |
| DR-003 | Phase 4 設計議論 生チャットログ | discussion |
| DR-005 | Phase 4 初期設計議論 | discussion |

## Moved to research/

調査レポートとして research/ に移動。

| 旧番号 | Title | 移動先 |
|---|---|---|
| DR-015 | 投機実行モデルによる高度な引数パターン対応 | research/2026-03-05-speculative-execution-potential.md |
| DR-032 | Go からの kuu WASM 利用 (Node.js ブリッジ方式) | research/2026-03-09-wasm-gc-go-bridge.md |
| DR-033 | WASM bridge 制限事項と多言語ブリッジ戦略 | research/2026-03-09-wasm-bridge-limitations.md |
| DR-046 | MoonBit LLVM backend ネイティブ FFI 実現可能性調査 | research/2026-03-10-llvm-backend-ffi-feasibility.md |

## 欠番

| # | 理由 |
|---|---|
| DR-004 | 不明 (ファイルが存在しない) |
