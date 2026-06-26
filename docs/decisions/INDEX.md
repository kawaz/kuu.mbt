# Decision Records Index

## Active

| # | Title | Type | Status |
|---|---|---|---|
| DR-0006 | Phase 4: Reducer 大統一設計 (String-Based) | decision | superseded |
| DR-0007 | Opts enum + ResultMap + immutable Opt + greedy/never 設計 | decision | superseded |
| DR-0008 | ReduceCtx 統一 + フックアーキテクチャ | decision | active |
| DR-0009 | 実装計画の再構築 | decision | active |
| DR-0010 | 先食い最長一致 Reducer モデルとマルチペルソナレビュー修正 | decision | active |
| DR-0011 | プロジェクト名の検討 (kuu) | discussion | active |
| DR-0012 | ExactNode アーキテクチャへの設計転換 | decision | active |
| DR-0013 | ParseResult アクセスパターン設計 | decision | active |
| DR-0014 | 否定パターンとプレフィックスペアの2軸分解 | decision | superseded |
| DR-0016 | FilterChain による pre/post フィルタ設計 | decision | active |
| DR-0017 | parse_raw 特殊分岐の ExactNode 化 | decision | active |
| DR-0018 | dashdash / append_dashdash + stop_before 設計 | decision | active |
| DR-0019 | Optional Value Option 設計 | decision | superseded |
| DR-0020 | 汎用 or コンビネータ + Initial[T] 設計 | decision | active |
| DR-0021 | exclusive/required バリデーション + is_set 追跡設計 | decision | active |
| DR-0022 | never + serial コンビネータ設計 | decision | active |
| DR-0023 | マージ可能リストオプション (+/- 修飾子と ... 展開) | decision | active |
| DR-0024 | コンビネータパラメータ共通化 | decision | active |
| DR-0025 | コンビネータの Compositional 分解 | decision | active |
| DR-0026 | sub() API / require_cmd() / parse 単一呼び出し制約 | decision | active |
| DR-0027 | core 純粋関数主義 + 多言語 DX レイヤー構想 | decision | active |
| DR-0028 | cmd → Opt[CmdResult] 統合 | decision | active |
| DR-0029 | 言語境界を越える Serialize/Deserialize 設計構想 | decision | active |
| DR-0030 | opt AST の言語間ポータビリティ | decision | active |
| DR-0031 | kubectl example の設計 | implementation | active |
| DR-0034 | greedy/non-greedy による OC/P フェーズ分離の再導入 | decision | active |
| DR-0035 | WASM bridge 拡張 (JSON 表現可能な全機能の対応) | decision | active |
| DR-0036 | KuuCore 各言語向け統一低レベル API 設計 | decision | active |
| DR-0037 | alias プリミティブ設計 (clone/link/adjust 直交プリミティブ) | decision | active |
| DR-0038 | 多角的コードレビュー (5ペルソナ) の知見 | review | active |
| DR-0039 | サブパーサコンビネータの抽象化 | decision | active |
| DR-0040 | deprecated コンビネータ実装 + clone/adjust 設計分析 | decision | active |
| DR-0041 | 環境変数コンビネータ設計構想 | vision | active |
| DR-0042 | struct-first DX 層設計 (Parseable trait + set 方式、旧名 apply_fn) | decision | active |
| DR-0043 | Opt[T] に priv setter を追加 | decision | superseded |
| DR-0044 | clone / link / adjust コンビネータ実装 | decision | superseded |
| DR-0045 | ValCell / Accessor 分離 | decision | active |
| DR-0047 | kuu-cli embed+extract+exec パターン | decision | active |
| DR-0048 | Accessor.is_set を Opt.used に分離 | decision | active |
| DR-0049 | サロゲートペア対応 (grapheme 導入) | implementation | active |
| DR-0050 | Filter 充実 + Sugar コンビネータ追加 | implementation | active |
| DR-0051 | 20260318 Example レビュー知見 | review | active |
| DR-0052 | ErrorKind 構造化エラー | decision | active |
| DR-0053 | プリミティブ分解 (name/exact/serial/or) | decision | active |
| DR-0054 | float DX層・WASM bridge 対応 | implementation | active |
| DR-0055 | register_option の option/long/short 分解 | decision | active |
| DR-0056 | WASM bridge 機能ギャップ解消 | implementation | active |
| DR-0057 | kuu-cli 言語非依存の独立コマンド構想 | vision | active |
| DR-0058 | 構造化エラー表示 (clap v4 準拠4層フォーマット) | implementation | draft |
| DR-0059 | kuu-cli Native CLI 実装 | decision | draft |
| DR-0060 | 20260320 MoonBit Example レビュー知見 | review | active |
| DR-0061 | コンビネータの合成的分解設計 | decision | active |

### Superseded の経緯

| DR | 置き換え先 | 理由 |
|---|---|---|
| DR-0006 | DR-0007 | String ベース中間表現から Opts enum + ResultMap 方式に移行 |
| DR-0007 | DR-0012, DR-0013 | Opts enum を ExactNode ベースに、ResultMap を ParseResult + Ref[T] に置換 |
| DR-0014 | DR-0024 | 2軸分解 (negate x prefix_pair) を 1軸の Variation リストに統合 |
| DR-0019 | DR-0020 | choices: Array[String] が退化形。汎用 or コンビネータで再設計 |
| DR-0043 | DR-0045 | priv setter が ValCell/Accessor に発展的統合 |
| DR-0044 | DR-0045 | clone/link/adjust の v1 実装が ValCell/Accessor 分離で大幅に進化 |

## Archived

初期 PoC・議論ログ。設計コンテキストとしての参照用。

| # | Title | Type |
|---|---|---|
| DR-0001 | Phase 1-3 PoC 設計記録 | decision |
| DR-0002 | Phase 4 設計議論ログ | discussion |
| DR-0003 | Phase 4 設計議論 生チャットログ | discussion |
| DR-0005 | Phase 4 初期設計議論 | discussion |

## Moved to research/

調査レポートとして research/ に移動。

| 旧番号 | Title | 移動先 |
|---|---|---|
| DR-0015 | 投機実行モデルによる高度な引数パターン対応 | research/2026-03-05-speculative-execution-potential.md |
| DR-0032 | Go からの kuu WASM 利用 (Node.js ブリッジ方式) | research/2026-03-09-wasm-gc-go-bridge.md |
| DR-0033 | WASM bridge 制限事項と多言語ブリッジ戦略 | research/2026-03-09-wasm-bridge-limitations.md |
| DR-0046 | MoonBit LLVM backend ネイティブ FFI 実現可能性調査 | research/2026-03-10-llvm-backend-ffi-feasibility.md |

## Moved to journal/

DR の付随議論ログとして journal/ に降格。本体 DR は decisions/ に残る。

| 元ファイル名 | 移動先 | 関連 DR |
|---|---|---|
| DR-061-discussion-log.md | journal/2026-03-21-dr061-design-discussion.md | DR-0061 |

## 欠番

| # | 理由 |
|---|---|
| DR-0004 | 不明 (ファイルが存在しない) |
