# kuu WASM bridge × git CLI パーサデモ

kuu の WASM bridge を使って、TypeScript から git CLI の引数パーサを実装するデモプロジェクトですの。

## 概要

MoonBit で書かれた kuu パーサを WebAssembly にコンパイルし、Node.js の TypeScript コードから JSON schema 経由でパースを実行します。実際の git 操作は行わず、パース結果を表示するだけの引数パーサデモです。

## アーキテクチャ

```
TypeScript (git-schema.ts)     TypeScript (main.ts)
        |                            |
        v                            v
   KuuOpt[] スキーマ定義      process.argv を取得
        |                            |
        +----------+  +--------------+
                   |  |
                   v  v
            KuuInput (JSON)
                   |
                   v
          kuu WASM (kuu_parse)
                   |
                   v
            KuuResult (JSON)
                   |
                   v
           結果の整形表示
```

## 前提条件

- **Node.js v25+** (WebAssembly js-string builtins サポート)
- **moon** (MoonBit コンパイラ、WASM ビルド用)
- **just** (タスクランナー、任意)

## ビルド・実行

### WASM ビルド

```bash
just build-wasm
# または
cd ../.. && moon build --target wasm-gc --release
```

### 実行

```bash
# ヘルプ表示
just help

# サブコマンド実行
just run clone https://github.com/foo/bar --depth 5 -b main
just run commit -m "fix bug" -a
just run log --oneline -n 10 --graph
just run status -sb
just run remote add origin https://github.com/foo/bar
just run stash push -m "wip"

# デモ（複数コマンドをまとめて実行）
just demo
```

### テスト

```bash
just test
# または
node --experimental-strip-types --test src/main.test.ts
```

### 出力例

#### ヘルプ表示

```
$ node --experimental-strip-types src/main.ts --help
mygit - A sample git-like CLI built with kuu

Usage: [OPTIONS] [COMMAND]

Commands:
  clone     リポジトリをクローンする
  commit    変更を記録する
  log       コミットログを表示する
  add       ファイルをインデックスに追加する
  push      リモート参照を更新する
  pull      フェッチしてマージする
  branch    ブランチの一覧・作成・削除
  checkout  ブランチを切り替える
  diff      差分を表示する
  status    作業ツリーの状態を表示する
  tag       タグの作成・一覧・削除
  remote    リモートリポジトリを管理する
  stash     変更を一時退避する
  config    設定を管理する

Options:
  -h, --help  Print help

Global Options:
  -v, --verbose        冗長出力を増やす (-v, -vv, -vvv)
      --color <COLOR>  カラー出力の制御 [possible values: always, never, auto] [default: auto]
```

#### clone サブコマンド

```
$ node --experimental-strip-types src/main.ts clone https://github.com/foo/bar --depth 5 -b main
command: clone
  url: https://github.com/foo/bar
  branch: main
  depth: 5
```

#### グローバルオプション + サブコマンド

```
$ node --experimental-strip-types src/main.ts -vv status -sb
Global options:
  verbose: 2

command: status
  short: true
  branch: true
```

## 実装されているサブコマンド

| サブコマンド | 説明 | 主なオプション |
|---|---|---|
| `clone` | リポジトリをクローン | `<url>`, `-b`, `--depth`, `--bare` |
| `commit` | 変更を記録 | `-m`, `-a`, `--amend` |
| `log` | コミットログ表示 | `--oneline`, `-n`, `--author`, `--format`, `--graph` |
| `add` | ファイルをステージ | `-f`, `--dry-run`, `-p`, `<files...>` |
| `push` | リモートに送信 | `<remote>`, `<refspecs...>`, `-f`, `-u`, `-d`, `--tags` |
| `pull` | リモートから取得 | `<remote>`, `<refspecs...>`, `-r`, `--ff-only` |
| `branch` | ブランチ管理 | `<name>`, `-d`, `-l`, `-a`, `-m` |
| `checkout` | ブランチ切り替え | `<branch>`, `-b`, `-f` |
| `diff` | 差分表示 | `--staged`, `--stat`, `-U`, `--name-only` |
| `status` | 状態表示 | `-s`, `-b`, `--porcelain` |
| `tag` | タグ管理 | `-l`, `-d`, `-a`, `-m`, `<tagname>` |
| `remote` | リモート管理 | `add`, `remove`, `rename` (ネストしたサブコマンド) |
| `stash` | 変更の一時退避 | `push`, `pop`, `list`, `drop` (ネストしたサブコマンド) |
| `config` | 設定管理 | `<key>`, `<remaining...>` |

### グローバルオプション

| オプション | 説明 |
|---|---|
| `-v` / `-vv` / `-vvv` | 冗長出力レベル |
| `--color` | カラー出力制御 (`always`, `never`, `auto`) |

## WASM bridge の制限事項

WASM bridge は kuu の全機能をサポートしているわけではありません。詳細は `docs/decision-records/DR-001-wasm-bridge-limitations.md` を参照してください。

主な制限:
- `serial` 非対応 → `positional` + `rest` で代用
- `exclusive` 非対応 → TypeScript 側でのバリデーションが必要
- `required` 非対応 → TypeScript 側でのバリデーションが必要
- `variations` 非対応 → `--no-xxx` パターンは使えない
- `implicit_value` 非対応 → 値の省略パターンは使えない

## ファイル構成

```
src/
  kuu-wasm.ts      WASM ローダー・型定義
  git-schema.ts    git CLI スキーマ定義
  main.ts          メインエントリポイント
  main.test.ts     テスト
docs/
  DESIGN.md        設計ドキュメント
  decision-records/
    DR-001-*.md    設計判断の記録
```
