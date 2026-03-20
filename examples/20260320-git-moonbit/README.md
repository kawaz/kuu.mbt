# mygit — kuu MoonBit Example

kuu ライブラリを使って git CLI の引数パースを MoonBit で実装する example。

## 実行方法

```bash
cd examples/20260320-git-moonbit
moon run .           # デモ実行
moon test            # テスト実行（78件）
moon test -u         # スナップショット更新
```

## 概要

- git CLI のサブコマンド体系を kuu core API でパースするデモ
- 実際の git 機能は未実装。引数パースの検証のみ
- 独立した `moon.mod.json` で kuu を path 依存として参照

## 検証した kuu 機能

| kuu 機能 | git での検証箇所 |
|---|---|
| グローバルオプション (global) | `--git-dir`, `--work-tree`, `-C`, `--no-pager`, `--bare`, `--color`, `-v` |
| サブコマンド (sub) | commit, push, pull, checkout, switch, restore, branch, log, diff, add, status, merge, rebase, tag |
| ネストサブコマンド | `remote add/remove/rename/show`, `stash push/pop/list/drop/apply/show` |
| flag + variation_false | `--no-edit`, `--no-verify`, `--no-pager`, `--no-ff` |
| count + variation_reset | `-v`/`-vv`/`-vvv`, `--no-verbose` |
| custom (string with shorts) | `-m MSG`, `-b BRANCH`, `-c BRANCH`, `-s TREE` |
| custom (int with shorts) | `-n NUM` |
| exclusive | `--force` vs `--force-with-lease`, `--no-ff` vs `--ff-only` |
| serial | `push <remote> <branch>`, `remote add <name> <url>` |
| positional | `checkout <branch>`, `merge <branch>` |
| rest | `add <pathspec>...`, `restore <pathspec>...` |
| dashdash | `checkout main -- file.txt` |
| aliases | `checkout`/`co`, `branch`/`br`, `--cached`/`--staged` |
| choices | `--color`, `--format` |
| implicit_value | `--color` (値なしなら "always") |
| require_cmd | remote（サブコマンド必須） |

## 設計上の注意点

- `string()`/`int()` は `shorts`/`global` 未対応。必要時は `custom()` + identity filter を使用
- checkout の `--` は `dashdash=false` + 手動 `dashdash()` で実現
- serial の Opt をクロージャ外で参照するため `Opt[T]?` + `mut` パターンが必要
- 詳細は `docs/DR-001-git-mock-design.md` 参照

## ディレクトリ構成

```
README.md         # この文書
DESIGN.md         # 設計メモ
moon.mod.json     # 独立モジュール設定（kuu path 依存）
moon.pkg          # パッケージ設定
main.mbt          # パーサー定義 + ディスパッチ + デモ + テスト78件
justfile          # ビルド・テスト
docs/
  DR-001-*.md     # 設計判断記録
```
