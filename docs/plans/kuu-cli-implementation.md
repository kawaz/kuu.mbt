# kuu-cli 実装計画

## 概要

MoonBit native target で動作する kuu-cli バイナリを `src/cli/` に実装する。
既存 WASM bridge (`src/wasm/`) と同一の JSON protocol v1 を使い、stdin/stdout で通信する。

## 要件サマリ

- **入力**: stdin or ファイルから JSON スキーマ（version 1）
- **出力**: stdout に JSON パース結果
- **サブコマンド**: parse, completions, validate, help
- **ターゲット**: `moon build --target native` で単一バイナリ生成
- **プロトコル**: WASM bridge と完全互換の JSON protocol v1

### JSON protocol v1 の完全仕様（codex review #2 対応）

**opt kinds（14種）**: flag, string, int, float, boolean, count, append_string, append_int, append_float, positional, rest, serial, command, dashdash
**メタ kinds（2種）**: deprecated, clone
**top-level 制約・拡張**: exclusive, required, at_least_one, requires, links, adjusts, env_prefix, auto_env, env, require_cmd
**出力契約**: ok, values, command, deprecated_warnings, help_requested, help, error, tip, kind

## 技術的制約

1. **MoonBit に stdin 標準 API がない** — C FFI が必須
2. **`is-main: true` パッケージは他パッケージから import 不可** — WASM bridge のコードを直接 import できない
3. **`source: "src"` 設定** — `src/cli/` は自動的にビルド対象

## アーキテクチャ決定

### 採択: B. 直接実装パターン（WASM bridge ロジックを参考に cli に実装）

bridge 分析の結果、build_parser/extract_values は純粋関数で抽出可能（方針 A）だが、
本 example のスコープでは既存 WASM bridge への変更リスクを避け、直接実装を採択する。

**理由**:
- WASM bridge のリファクタは既存テスト 99 件の影響範囲が大きい
- kuu-cli は WASM bridge と同一 JSON protocol v1 を使うため、ロジックは機械的にコピー可能
- 将来的に bridge 共有化（方針 A）へのリファクタは別タスクで実施可能

### 将来構想: bridge 共有化

```
src/
  core/       # Layer 1: パースエンジン（既存）
  bridge/     # Layer 2 共通: JSON schema → Parser 構築 + 値抽出（将来抽出）
  wasm/       # Layer 2a: WASM transport（既存）
  cli/        # Layer 2b: Native CLI transport（★今回作成）
  dx/         # MoonBit DX 層（既存）
```

## ファイル構成

```
src/cli/
  moon.pkg          # is-main: true, native target, import core + json
  main.mbt          # エントリポイント、サブコマンド dispatch
  parse_cmd.mbt     # parse サブコマンド: JSON → Parser → parse → JSON
  completions_cmd.mbt  # completions サブコマンド
  validate_cmd.mbt  # validate サブコマンド
  bridge.mbt        # build_parser + extract_values（WASM bridge から移植）
  bridge_opts.mbt   # opt kind 別の build 処理
  bridge_filters.mbt # filter/post パーサ
  io_native.c       # C FFI: stdin 読み込み、ファイル読み込み
  io_native.mbt     # C FFI の MoonBit 側宣言
```

## 実装フェーズ

### Phase 1: C FFI + ビルド基盤

1. `src/cli/moon.pkg` 作成（`is-main: true`, native target）
2. `src/cli/io_native.c` — stdin 全読み、ファイル読み込み
3. `src/cli/io_native.mbt` — FFI 宣言
4. `src/cli/main.mbt` — 最小限の main（stdin echo で動作確認）
5. `moon build --target native` でビルド確認

### Phase 2: bridge ロジック移植

WASM bridge (`src/wasm/main.mbt`) から以下を移植:

1. 型定義: OptEntry, OptHandle, SchemaResult
2. build_parser() — 6パス走査（opt生成 → deprecated → clone → link → adjust → constraints）
3. extract_values() — 再帰的な値抽出
4. フィルタパーサ: parse_string_filter, parse_int_filter, parse_float_filter
5. ヘルパ: get_opt_string, extract_variations, has_dashdash_opt
6. JSON 出力: make_error_json, make_help_json

### Phase 3: parse サブコマンド（codex review #1 対応: env 経路含む）

1. stdin/ファイルから JSON 読み込み
2. JSON → `@core.Parser` 構築（Phase 2 の build_parser）
3. **`parser.parse(args, env~)` 実行** — env マップを JSON から抽出して渡す
4. 値抽出 → JSON 出力（extract_values）
5. エラーハンドリング:
   - parse error → `{ok: false, error, help, tip, kind}`
   - schema error → `{ok: false, error}`
   - help request → `{ok: false, help_requested: true, help}`
   - deprecated → `deprecated_warnings` 配列追記

### Phase 4: completions / validate サブコマンド

1. completions: schema JSON → Parser 構築 → `generate_completion_script(shell, command_name)`
2. validate: schema JSON → Parser 構築のみ（パースは実行しない）。成功なら `{ok: true}`

### Phase 5: kuu-cli 自身の引数パース（self-hosting）

kuu core を使って kuu-cli 自身の CLI をパースする:

```
kuu parse <schema> [-- <args>...]
kuu completions --shell <shell> --command <name> <schema>
kuu validate <schema>
kuu --help
kuu --version
```

### Phase 6: テスト + ドキュメント

1. **互換性テスト**: WASM bridge の test.mjs 全 99 件と同一入力で同一出力を検証（codex review #3 対応）
2. wbtest: MoonBit native テスト
3. DESIGN.md 更新
4. DR 記録

## 互換性ゲート（codex review #3 対応）

**必須**: 既存 `src/wasm/test.mjs` の全 99 テストケースの入力 JSON を kuu-cli に渡し、
WASM bridge と同一の出力 JSON が得られることを検証する。

検証方法:
```bash
# WASM bridge の出力
node src/wasm/test.mjs > expected.json

# kuu-cli の出力
echo "$input_json" | ./kuu-cli parse - > actual.json

# 差分比較
diff expected.json actual.json
```

## リスク

| リスク | 影響 | 対策 |
|---|---|---|
| C FFI の stdin 読み込みが MoonBit GC と相性悪い | メモリリーク | バッファサイズ制限 + テスト |
| WASM bridge のロジック複製でバグ混入 | 互換性喪失 | test.mjs 全件パスを必須ゲートに |
| native target のテストが moon test で動かない | テスト不能 | integration test をシェルスクリプトで代替 |
| build_parser の移植量が大きい（~1200行） | 工数増大 | 機械的コピー + 最小限の適応 |

## 成功基準

1. `echo '{"version":1,...}' | ./kuu-cli parse -` が正しい JSON を返す
2. **WASM bridge の test.mjs 全 99 件と同一出力**（互換性ゲート）
3. kuu-cli 自身の `--help` が kuu core で生成される（self-hosting）
4. `moon test --target native` でテスト通過
5. parse, completions, validate サブコマンドが全て動作
