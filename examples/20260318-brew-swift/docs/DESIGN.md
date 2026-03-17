# brew-swift: Homebrew CLI パーサデモ設計書

## 概要

Homebrew `brew` コマンドの引数パースを Swift + kuu WASM bridge で実装するデモ。
kuu の多言語対応能力と、実用的な CLI の複雑な引数構造を扱えることを実証する。

## アーキテクチャ

```
Swift (main.swift)
  ↓ JSON スキーマ構築 (BrewSchema.swift)
  ↓ bun subprocess 経由 (KuuBridge.swift)
  ↓ kuu.wasm パース
  ↓ JSON 結果を型安全に取得
ParseResult / CommandResult
```

## 対象サブコマンド

### グローバルオプション

| オプション | 型 | 説明 |
|---|---|---|
| `--verbose` / `-v` | flag (global) | 詳細出力 |
| `--debug` / `-d` | flag (global) | デバッグ出力 |
| `--quiet` / `-q` | flag (global) | 出力抑制 |

### サブコマンド一覧

| コマンド | 特徴 | kuu 検証ポイント |
|---|---|---|
| `install` | 複雑なフラグ群、rest 引数 | exclusive (--formula/--cask), aliases, rest |
| `search` | 位置引数、フィルタフラグ | positional, exclusive |
| `tap` | オプショナル位置引数 | positional (optional) |
| `upgrade` | install 類似 + greedy 系 | flag variations, rest |
| `list` | 表示制御フラグ群 | 多数の flag, exclusive |

### install

```
brew install [options] formula|cask ...
```

- `--force` / `-f`: 強制インストール
- `--build-from-source` / `-s`: ソースからビルド
- `--dry-run` / `-n`: プレビュー
- `--formula` / `--formulae`: formula として扱う
- `--cask` / `--casks`: cask として扱う
- `--HEAD`: HEAD バージョン
- `--cc=<compiler>`: コンパイラ指定
- `--keep-tmp`: 一時ファイル保持
- `--ask`: 確認ダイアログ
- exclusive: `--formula` vs `--cask`

### search

```
brew search [options] text|/regex/
```

- `--formula` / `--formulae`: formula のみ
- `--cask` / `--casks`: cask のみ
- `--desc`: 説明文で検索

### tap

```
brew tap [user/repo] [URL]
```

- `--force`: 強制
- `--repair`: シンボリックリンク修復
- `--eval-all`: 全フォーミュラ評価
- `--custom-remote`: カスタムリモート

### upgrade

```
brew upgrade [options] [formula|cask ...]
```

- `--force` / `-f`: 強制
- `--dry-run` / `-n`: プレビュー
- `--formula` / `--formulae`: formula のみ
- `--cask` / `--casks`: cask のみ
- `--greedy` / `-g`: auto_updates 含む
- `--greedy-latest`: latest 版も更新
- `--greedy-auto-updates`: auto_updates のみ
- `--ask`: 確認ダイアログ
- `--display-times`: インストール時間表示
- exclusive: `--formula` vs `--cask`

### list

```
brew list [options] [formula|cask ...]
```

- `--formula` / `--formulae`: formula のみ
- `--cask` / `--casks`: cask のみ
- `--full-name`: 完全修飾名
- `--versions`: バージョン表示
- `--pinned`: ピン留めのみ
- `--installed-on-request`: 明示的インストールのみ
- `--installed-as-dependency`: 依存インストールのみ
- `-1`: 1行1エントリ
- `-l`: 長形式
- `-r`: 逆順
- `-t`: 更新日時ソート
- exclusive: `--formula` vs `--cask`

## kuu 検証ポイント

1. **グローバルオプション**: 全サブコマンドで `--verbose`, `--debug`, `--quiet` が使える
2. **exclusive 制約**: `--formula` と `--cask` の排他制御
3. **aliases**: `--formulae` → `--formula`, `--casks` → `--cask`
4. **コマンドエイリアス**: `ls` → `list`
5. **rest 引数**: `install`, `upgrade`, `list` で複数パッケージ名を受け取る
6. **位置引数**: `search` のクエリ、`tap` の user/repo
7. **短形式結合**: `-fs` = `-f -s`
8. **値付きオプション**: `--cc=gcc-9` 形式
9. **ネストなし**: brew は1階層のサブコマンドのみ（シンプル）

## ディレクトリ構成

```
examples/20260318-brew-swift/
  Package.swift       # Swift Package Manager 定義
  justfile            # ビルド・テスト・実行タスク
  README.md           # 概要・使い方
  Sources/
    main.swift        # エントリポイント + 結果表示
    KuuBridge.swift   # bun subprocess ブリッジ
    BrewSchema.swift  # brew CLI スキーマ定義
  wasm/
    bridge.mjs        # JS ブリッジスクリプト
    kuu.wasm          # kuu WASM モジュール
  docs/
    DESIGN.md         # 本ファイル
    decision-records/
```
