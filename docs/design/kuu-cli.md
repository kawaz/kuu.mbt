# kuu-cli: 言語非依存の引数パースコマンド

## 背景

DR-047 (embed+extract+exec パターン) と DR-057 (言語非依存の独立コマンド) に基づく実装。

## やること

`src/cli/` に kuu-cli の MoonBit ソースを作成する。

### kuu-cli とは

stdin から JSON スキーマ + CLI args を受け取り、パース結果を JSON で stdout に返す単一バイナリ。
既存の `src/wasm/` (WASM bridge) と同じ JSON プロトコル v1 を使う。

```bash
# 基本的な使い方
kuu parse schema.json -- --port 8080 --verbose

# stdin からスキーマを渡す
cat schema.json | kuu parse - -- --port 8080

# 補完スクリプト生成
kuu completions --shell bash --command myapp schema.json
```

### アーキテクチャ

```
src/
  core/     # Layer 1: パースエンジン（既存）
  wasm/     # Layer 2: WASM bridge — JSON transport（既存）
  cli/      # Layer 2: Native bridge — stdin/stdout transport（★今回作成）
  dx/       # MoonBit DX層（既存）
```

kuu-cli は `src/wasm/main.mbt` の native target 版。主な違い:

| 項目 | WASM bridge | kuu-cli |
|---|---|---|
| Transport | WASM export/import | stdin/stdout |
| Target | wasm-gc | native (C backend) |
| 入力 | 関数引数 (String) | stdin or ファイル |
| 出力 | 戻り値 (String) | stdout |
| JSON プロトコル | v1 | v1（同一） |

### 実装方針

1. `src/wasm/main.mbt` の `build_parser()` と `extract_values()` ロジックを流用
2. stdin/ファイルからの JSON 読み込み → `@core.Parser` 構築 → parse → JSON 出力
3. `moon.pkg.json` に `is-main: true` を設定
4. `moon build --target native` でバイナリ生成

### サブコマンド構成

```
kuu parse <schema> [-- <args>...]     # メイン機能: 引数パース
kuu completions <schema>              # 補完スクリプト生成
kuu validate <schema>                 # スキーマバリデーション
kuu help                              # ヘルプ表示
```

### JSON プロトコル v1（src/wasm/ と共通）

#### 入力スキーマ
```json
{
  "version": 1,
  "description": "CLI説明文",
  "opts": [
    { "kind": "flag", "name": "verbose", "shorts": "v", "description": "詳細出力" },
    { "kind": "string", "name": "output", "shorts": "o", "default": "out.txt" },
    { "kind": "command", "name": "serve", "opts": [
      { "kind": "int", "name": "port", "default": 8080 }
    ]}
  ],
  "args": ["serve", "--port", "3000", "--verbose"]
}
```

#### 出力（成功時）
```json
{
  "ok": true,
  "values": { "verbose": true, "output": "out.txt" },
  "command": { "name": "serve", "values": { "port": 3000 } }
}
```

#### 出力（エラー時）
```json
{
  "ok": false,
  "error": "Unknown option: --foo",
  "kind": "UnknownOption",
  "tip": "--verbose"
}
```

### 参照ファイル

- `src/wasm/main.mbt` — WASM bridge 実装（1,661行）。build_parser/extract_values を流用
- `src/wasm/moon.pkg` — パッケージ設定の参考
- `src/wasm/test.mjs` — テストケース 98件（期待動作の参考）
- `src/core/` — kuu core パースエンジン
- `docs/decisions/DR-047-*.md` — embed+extract+exec パターン設計
- `docs/decisions/DR-057-*.md` — 言語非依存コマンド構想

### テスト

- `moon test --target native` で実行可能な wbtest を作成
- 主要パターン: flag/string/int/float/boolean/count/append/positional/rest/command/dashdash
- エラーケース: unknown option, missing value, exclusive conflict 等
- WASM bridge のテスト (`test.mjs`) と同等のカバレッジを目指す

### ビルド・実行

```bash
# ビルド
moon build --target native

# 実行（ビルド後のバイナリパスは moon build の出力を確認）
echo '{"version":1,"opts":[{"kind":"flag","name":"verbose"}],"args":["--verbose"]}' | ./kuu-cli

# テスト
moon test --target native
```

## ディレクトリ構成

作業は `src/cli/` に対して行う。通常の example とは異なり、プロジェクトの `src/` 配下に配置する。

## /itumono-full-loop 手順でフルオートモードで行ってください。ループ数の上限は特に指示がなければ納得するまで。CVは不要です。
