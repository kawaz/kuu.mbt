# kuu-cli 実装計画

## 概要

MoonBit native target で動作する kuu-cli バイナリを `src/cli/` に実装する。
既存 WASM bridge (`src/wasm/`) と同一の JSON protocol v1 を使い、stdin/stdout で通信する。

## 要件サマリ

- **入力**: stdin or ファイルから JSON スキーマ（version 1）
- **出力**: stdout に JSON パース結果
- **サブコマンド**: parse, completions, validate, help
- **ターゲット**: `moon build --target native` で単一バイナリ生成
- **プロトコル**: WASM bridge と同一の JSON protocol v1（14+ opt kinds 対応）

## 技術的制約

1. **MoonBit に stdin 標準 API がない** — C FFI が必須
2. **`is-main: true` パッケージは他パッケージから import 不可** — WASM bridge のコードを直接 import できない
3. **`source: "src"` 設定** — `src/cli/` は自動的にビルド対象

## アーキテクチャ

### 方針: WASM bridge ロジックの共有化

WASM bridge (`src/wasm/main.mbt`) の JSON→Parser 構築ロジックを新パッケージ `src/bridge/` に抽出し、
`src/wasm/` と `src/cli/` の両方から import する。

```
src/
  core/       # Layer 1: パースエンジン（既存）
  bridge/     # Layer 2 共通: JSON schema → Parser 構築 + 値抽出（★新規）
  wasm/       # Layer 2a: WASM transport（既存、bridge を import に変更）
  cli/        # Layer 2b: Native CLI transport（★新規）
  dx/         # MoonBit DX 層（既存）
```

### 代替案: ロジック複製

bridge 抽出が大きすぎる場合、WASM bridge のロジックを `src/cli/` に複製して適応する。
PoC としては許容範囲だが、長期的にはメンテナンスコストが高い。

→ **判断基準**: WASM bridge の `build_parser()` / `extract_values()` が単純に切り出せるか調査し、
  困難なら複製方針に切り替える。

## ファイル構成

### src/cli/

```
src/cli/
  moon.pkg          # is-main: true, native target, import bridge + core
  main.mbt          # エントリポイント、サブコマンド dispatch
  io_native.c       # C FFI: stdin 読み込み、ファイル読み込み、コマンドライン引数取得
  io_native.mbt     # C FFI の MoonBit 側宣言
```

### src/bridge/ （共有ロジック抽出する場合）

```
src/bridge/
  moon.pkg          # import core + json
  schema.mbt        # JSON schema → Parser 構築
  extract.mbt       # Parser → JSON 値抽出
  types.mbt         # SchemaResult, OptEntry 等の型定義
```

## 実装フェーズ

### Phase 1: C FFI + ビルド基盤（TDD）

1. `src/cli/moon.pkg` 作成（`is-main: true`, native target）
2. `src/cli/io_native.c` — stdin 全読み、ファイル読み込み、argv 取得
3. `src/cli/io_native.mbt` — FFI 宣言
4. `src/cli/main.mbt` — 最小限の main（stdin echo）
5. `moon build --target native` でビルド確認

### Phase 2: JSON→Parser 構築ロジック

WASM bridge の `build_parser()` を分析し、以下のいずれかで実装:

**A. bridge 抽出パターン**:
- `src/bridge/` に共有ロジックを抽出
- `src/wasm/main.mbt` を bridge import に書き換え
- `src/cli/` から bridge を import

**B. 直接実装パターン**:
- WASM bridge のロジックを参考に `src/cli/` に直接実装
- JSON schema parsing → `@core.Parser` 構築
- opt kind ごとの処理関数

### Phase 3: parse サブコマンド

1. stdin/ファイルから JSON 読み込み
2. JSON → `@core.Parser` 構築（Phase 2 のロジック使用）
3. `parser.parse(args)` 実行
4. 値抽出 → JSON 出力
5. エラーハンドリング（parse error, schema error, help request）

### Phase 4: completions / validate サブコマンド

1. completions: `parser.generate_completion_script(shell, command_name)`
2. validate: schema のみ検証、パースは実行しない

### Phase 5: kuu-cli 自身の引数パース（self-hosting）

kuu core を使って kuu-cli 自身のサブコマンドとオプションをパースする:

```
kuu parse <schema> [-- <args>...]
kuu completions --shell <shell> --command <name> <schema>
kuu validate <schema>
kuu --help
kuu --version
```

### Phase 6: テスト + ドキュメント

1. wbtest: 主要パターン（flag/string/int/command/dashdash/error）
2. WASM bridge の test.mjs と同等のカバレッジ（99件相当）
3. DESIGN.md 更新
4. DR 記録

## リスク

| リスク | 影響 | 対策 |
|---|---|---|
| C FFI の stdin 読み込みが MoonBit GC と相性悪い | メモリリーク | バッファサイズ制限 + テスト |
| WASM bridge ロジック抽出が困難 | 工数増大 | 複製方針にフォールバック |
| native target のテストが moon test で動かない | テスト不能 | integration test をシェルスクリプトで代替 |
| 大きな JSON schema で性能問題 | 実用性低下 | PoC 段階では無視 |

## 成功基準

1. `echo '{"version":1,...}' | ./kuu-cli parse -` が正しい JSON を返す
2. WASM bridge の主要テストケースと同等の結果
3. kuu-cli 自身の `--help` が kuu core で生成される（self-hosting）
4. `moon test --target native` でテスト通過
