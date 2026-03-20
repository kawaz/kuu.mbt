---
type: decision
status: draft
---

# DR-059: kuu-cli Native CLI 実装

## 日付

2026-03-20

## 背景

kuu の多言語展開において、WASM bridge (Layer 2a) はインプロセスで高速だが、ワンバイナリ化できない（ランタイム依存）という弱点がある。DR-047 で kuu-cli embed パターンを構想し、DR-057 で独立コマンドとしてのビジョンを描いた。本 DR はその実装に関する技術的判断を記録する。

## 決定

kuu-cli を MoonBit native target (C backend) で実装する。Layer 2b の Native CLI transport として、stdin/stdout の JSON protocol v1 で kuu core のパース機能を提供する単一バイナリ。

## アーキテクチャ選択

### 検討した選択肢

| 方式 | 概要 | メリット | デメリット |
|------|------|----------|------------|
| A. bridge 共有化 | wasm/ と cli/ で共通の bridge 層を抽出し、transport だけ差し替え | コード重複なし、一貫性保証 | 既存 WASM bridge への変更リスク、抽象化コスト |
| B. 直接実装 | cli/ で独自に JSON decode → core 呼び出し → JSON encode を実装 | WASM bridge に触らない、スコープが明確 | bridge ロジックの重複 |

### 採択: B（直接実装）

**理由**:

- 既存 WASM bridge は安定稼働中であり、変更リスクを避けたい
- PoC スコープとして独立して進めやすい
- 将来的に bridge 共有化 (A) へリファクタ可能。B → A は自然な進化パス
- cli/ 固有の関心事（argv 取得、ファイル読み込み等）が WASM bridge にはない

## C FFI 設計

MoonBit の native target には stdin、ファイル I/O、argv 取得の標準 API がないため、C FFI で実装する。

### 必要な C FFI

| 機能 | C 関数 | 用途 |
|------|--------|------|
| stdin 読み込み | `read_stdin_bytes()` | JSON schema のパイプ入力 |
| ファイル読み込み | `read_file_bytes(path)` | JSON schema ファイルの読み込み |
| argv 取得 | `get_argc()`, `get_argv(i)` | CLI 引数の取得 |
| stdout 書き込み | `write_stdout(bytes)` | JSON 結果の出力 |
| stderr 書き込み | `write_stderr(bytes)` | エラーメッセージの出力 |

### argv 取得 — macOS 固有

macOS では `main(argc, argv)` 経由ではなく `_NSGetArgc`/`_NSGetArgv` で取得する。これは MoonBit の C backend が main 関数を生成する仕組みに起因し、argc/argv が MoonBit 側に渡されないため。

```c
#include <crt_externs.h>

int get_argc(void) {
    return *_NSGetArgc();
}

const char* get_argv(int i) {
    return (*_NSGetArgv())[i];
}
```

Linux では `/proc/self/cmdline` からの読み取り、または `__libc_start_main` 経由で取得する方式を検討。クロスプラットフォーム対応は段階的に進める。

### UTF-8 ↔ UTF-16 変換

C FFI 境界で以下の変換が必要:

- **C → MoonBit**: UTF-8 バイト列 → MoonBit String (UTF-16 LE)
- **MoonBit → C**: MoonBit String → UTF-8 バイト列

MoonBit の `Bytes` 型は UTF-16 LE エンコーディング。C 側で UTF-8 として読み込んだデータを UTF-16 LE に変換して MoonBit に渡す。逆方向も同様。

## Self-hosting

kuu core で kuu-cli 自身の CLI 引数をパースする（dogfooding）。

### CLI 構造

```
kuu-cli [global options] <subcommand> [options] [--] [args...]

Subcommands:
  parse         JSON schema に基づいて引数をパース
  completions   シェル補完スクリプトを生成
  validate      JSON schema のバリデーション

Global Options:
  --help        ヘルプを表示
  --version     バージョンを表示
```

### parse サブコマンド

```
kuu-cli parse [--schema <file>] [--] [args...]

# ファイル指定
kuu-cli parse --schema schema.json -- --port 8080 --verbose

# stdin 入力
cat schema.json | kuu-cli parse -- --port 8080 --verbose
```

入力: JSON schema (ファイルまたは stdin) + パース対象の引数列
出力: JSON protocol v1 形式のパース結果 (stdout)

## JSON protocol v1 互換性

WASM bridge と同一のプロトコルを使用する。schema の JSON 形式、パース結果の JSON 形式ともに wasm/ の実装と互換。これにより、WASM bridge 用に書かれた DX レイヤーのテストケースがそのまま kuu-cli でも利用可能。

### 入力 (schema)

```json
{
  "options": [
    { "type": "flag", "name": "verbose", "description": "..." },
    { "type": "string", "name": "port", "default": "8080", ... }
  ],
  "subcommands": [...],
  "constraints": [...]
}
```

### 出力 (parse result)

```json
{
  "values": { "verbose": true, "port": "8080" },
  "positionals": [...],
  "subcommand": { "name": "serve", "values": {...} }
}
```

エラー時:

```json
{
  "error": {
    "kind": "UnknownOption",
    "message": "unexpected argument: --prot",
    "tip": "a similar option exists: '--port'"
  }
}
```

## 実装フェーズ

1. **Phase 1**: C FFI 基盤（stdin/stdout/stderr/argv/file I/O + UTF-8↔UTF-16 変換）
2. **Phase 2**: Self-hosting CLI パーサ（kuu core で parse/completions/validate サブコマンドを定義）
3. **Phase 3**: JSON protocol v1 の decode/encode（schema → core Parser 構築 → パース → 結果 JSON 出力）
4. **Phase 4**: end-to-end テスト（WASM bridge のテストケースを流用）

## 関連 DR

- DR-027: core 純粋関数主義 + 多言語 DX レイヤー構想
- DR-036: KuuCore 統一低レベル API（4層アーキテクチャ）
- DR-047: kuu-cli embed+extract+exec パターン
- DR-057: kuu-cli 独立コマンドとしてのビジョン
- DR-058: 構造化エラー表示（エラー JSON 出力に影響）
