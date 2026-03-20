# mygit — kuu MoonBit Example 設計書

## 概要

kuu ライブラリを使って git CLI の引数パースを MoonBit で実装する example。
実際の git 機能は実装しない。引数パースと結果出力の検証のみ。

## 検証ポイント

| kuu 機能 | git での検証箇所 |
|---|---|
| グローバルオプション | `--git-dir`, `--work-tree`, `-C`, `--no-pager`, `--bare` |
| サブコマンド | commit, push, pull, checkout, switch, restore, branch, log, diff, add, status, merge, rebase, tag |
| ネストサブコマンド | `remote add/remove/rename/show`, `stash push/pop/list/drop/apply` |
| flag | `--amend`, `--force`, `--all`, `--graph` |
| flag (default=true) + variation_false | `--verify` (default true, `--no-verify` で false) |
| string | `-m MSG`, `--format FMT`, `--author AUTHOR` |
| int | `-n NUM` (log の表示件数) |
| count | `-v` (verbosity) |
| append_string | `--author PATTERN` (log の複数 author フィルタ) |
| positional | `checkout <branch>`, `push <remote> <branch>` |
| rest | `add <pathspec>...` |
| dashdash | `checkout -- file.txt` |
| serial | `remote add <name> <url>`, `push <remote> <branch>` |
| exclusive | `--force` vs `--force-with-lease` |
| required | `commit -m` 時のメッセージ |
| require_cmd | トップレベル（サブコマンド必須） |
| aliases | `checkout` / `co`, `branch` / `br` |
| choices | `--format` の選択肢 |
| implicit_value | `--color` (値なしなら "always") |
| deprecated | `checkout` → `switch`/`restore` への移行表示 |
| variation_false | `--no-edit`, `--no-verify`, `--no-pager` |
| variation_reset | `--no-verbose` |

## アーキテクチャ

### ファイル構成

```
examples/20260320-git-moonbit/
  README.md         # プロジェクト概要
  DESIGN.md         # この設計書
  moon.pkg          # パッケージ設定
  justfile          # ビルド・テスト
  main.mbt          # デモ実行 + パーサー構築
  docs/
    DR-001-*.md     # 設計判断記録
```

### 方針

- **core API 直接使用**: DX層(struct-first)ではなく core の Parser/Opt を直接使う
  - 理由: git CLI は大量のサブコマンドとオプションを持ち、core API の方がサブコマンドごとに独立したパーサーを組みやすい
  - DX層は struct に全フィールドを持つ必要があり、サブコマンド20個超の CLI には向かない
- **1ファイル構成**: 全てを main.mbt にまとめる（exampleの可読性重視）
- **snapshot テスト**: `inspect()` で出力を検証

### パーサー構造

```
Parser (top-level)
  ├── グローバルオプション (global=true)
  │   --git-dir, --work-tree, -C, --no-pager, --bare, --version, --color
  │
  ├── sub: commit
  │   -m, --amend, --no-edit, -a, --allow-empty, --no-verify, --author, --signoff
  │
  ├── sub: push
  │   serial: <remote> <branch>
  │   --force, --force-with-lease (exclusive), --set-upstream, --all, --tags, --delete
  │
  ├── sub: pull
  │   serial: <remote> <branch>
  │   --rebase, --no-rebase, --ff-only, --no-ff
  │
  ├── sub: checkout
  │   positional: <branch-or-path>
  │   -b (新ブランチ作成), --track, dashdash
  │
  ├── sub: switch
  │   positional: <branch>
  │   -c (新ブランチ作成), --detach, --track
  │
  ├── sub: restore
  │   rest: <pathspec>...
  │   --source, --staged, --worktree
  │
  ├── sub: branch
  │   positional: <branch-name>
  │   -d/-D (削除), -m/-M (リネーム), -a (全表示), -r (リモート), --list
  │
  ├── sub: log
  │   -n/--max-count, --oneline, --graph, --all, --format, --author (append)
  │   rest: <path>...
  │
  ├── sub: diff
  │   --cached/--staged (aliases), --name-only, --stat, --color
  │   rest: <path>...
  │
  ├── sub: add
  │   rest: <pathspec>...
  │   -A/--all, --force, --dry-run, --verbose
  │
  ├── sub: status
  │   --short/-s, --branch/-b, --porcelain
  │
  ├── sub: merge
  │   positional: <branch>
  │   --no-ff, --ff-only (exclusive), --squash, -m MSG, --abort
  │
  ├── sub: rebase
  │   positional: <upstream>
  │   --onto, --interactive, --continue, --abort, --skip
  │
  ├── sub: tag
  │   positional: <tagname>
  │   -a (annotated), -m MSG, -d (delete), --list, --force
  │
  ├── sub: remote (require_cmd)
  │   ├── sub: add — serial: <name> <url>, --fetch
  │   ├── sub: remove — positional: <name>
  │   ├── sub: rename — serial: <old> <new>
  │   └── sub: show — positional: <name>
  │
  └── sub: stash
      ├── sub: push — -m MSG, --include-untracked, rest: <pathspec>...
      ├── sub: pop — positional: <stash>
      ├── sub: apply — positional: <stash>
      ├── sub: drop — positional: <stash>
      ├── sub: list (引数なし)
      └── sub: show — positional: <stash>
```

## dispatch パターン

```moonbit
match result.child("commit") {
  Some(commit_result) => { /* commit の結果出力 */ }
  None => ()
}
match result.child("push") {
  Some(push_result) => { /* push の結果出力 */ }
  None => ()
}
// ...
```

## テスト戦略

- 各サブコマンドの基本動作テスト
- グローバルオプション + サブコマンドの組み合わせテスト
- exclusive/required のエラーテスト
- `--help` 表示テスト
- `--` セパレータのテスト
- deprecated 警告テスト
