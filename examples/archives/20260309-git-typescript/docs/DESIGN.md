# 設計ドキュメント

## 概要

このプロジェクトは、kuu の WASM bridge を使って TypeScript から git CLI の引数パーサを実装するデモです。kuu コアは MoonBit で実装されており、WebAssembly を介して JSON ベースのインターフェースで TypeScript から利用します。

## アーキテクチャ

### データフロー

```
TypeScript 側                        WASM 側 (MoonBit)
─────────────                        ────────────────
1. KuuOpt[] スキーマ定義
2. process.argv から引数取得
3. KuuInput を JSON にシリアライズ
                    ─── JSON string ──→
                                        4. JSON をパース
                                        5. スキーマから Parser を構築
                                        6. 引数をパース
                                        7. 結果を JSON にシリアライズ
                    ←── JSON string ───
8. KuuResult としてデシリアライズ
9. 結果に応じた表示処理
```

### WASM bridge のインターフェース

WASM モジュールは `kuu_parse(input: string) -> string` を export します。

- **入力**: `KuuInput` を JSON シリアライズした文字列
- **出力**: `KuuResult` を JSON シリアライズした文字列

Node.js v25 の `WebAssembly.instantiate` で `builtins: ["js-string"]` を使い、MoonBit の文字列と JavaScript の文字列を直接相互運用します。

### 型の対応

| kuu (MoonBit) | WASM bridge JSON | TypeScript |
|---|---|---|
| `flag` | `boolean` | `boolean` |
| `string_opt` | `string` | `string` |
| `int_opt` | `number` | `number` |
| `count` | `number` | `number` |
| `append_string` | `string[]` | `string[]` |
| `append_int` | `number[]` | `number[]` |
| `positional` | `string \| null` | `string \| null` |
| `rest` | `string[]` | `string[]` |
| `command` | ネストされたオブジェクト | `KuuCommandResult` |

## WASM bridge でサポートされる機能

- `flag`: ブール値フラグ (`--verbose`, `-v`)
- `string`: 文字列オプション (`--host localhost`)
- `int`: 整数オプション (`--port 8080`)
- `count`: カウンタ (`-vvv` → 3)
- `append_string`: 繰り返し文字列 (`--author a --author b`)
- `append_int`: 繰り返し整数
- `positional`: 位置引数
- `rest`: 残り引数の収集
- `command`: サブコマンド（ネスト可）
- `shorts`: ショートオプション
- `global`: グローバルオプション
- `hidden`: ヘルプ非表示オプション
- `aliases`: 別名
- `choices`: 選択肢制約
- `default`: デフォルト値

## WASM bridge でサポートされない機能

| 機能 | 説明 | 代替策 |
|---|---|---|
| `serial` | 複数 positional の順序付き消費 | `positional` + `rest` で代用 |
| `exclusive` | 排他的オプション | TypeScript 側でバリデーション |
| `required` | 必須オプション | TypeScript 側でバリデーション |
| `require_cmd` | サブコマンド必須 | TypeScript 側でハンドリング |
| `dashdash` | `--` 以降の引数取得 | `rest` で全引数を収集 |
| `variations` | `--no-xxx` パターン | 対応不可 |
| `implicit_value` | 値省略時のデフォルト | 常に値の指定が必要 |
| `post` フィルタ | パース後バリデーション | TypeScript 側で実装 |
| `value_name` | ヘルプの値名表示 | 対応不可（ヘルプに影響のみ） |

## git CLI スキーマの設計判断

### positional + rest による serial 代用

`git push <remote> <branch>` のように複数の位置引数が必要なケースでは、serial が使えないため `positional` (1つ目) + `rest` (残り全部) で代用しています。

例: `push` コマンド
- `positional("remote")`: 最初の位置引数をリモート名として取得
- `rest("refspecs")`: 残りの位置引数をリファレンス指定として取得

### ネストしたサブコマンド

`remote` と `stash` は WASM bridge のコマンドネスト機能を使い、子サブコマンドを定義しています。

- `remote add/remove/rename`
- `stash push/pop/list/drop`

### グローバルオプション

`-v` (verbose) と `--color` はグローバルオプションとして定義し、どのサブコマンドの前後でも使用可能にしています。

### aliases による互換性

`diff --staged` と `diff --cached` は同じ意味です。aliases 機能を使って `staged` に `cached` というエイリアスを設定しています。
