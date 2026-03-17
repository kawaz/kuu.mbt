# 20260318-tar 設計書

## 目的

kuu の排他制約・variation・aliases 機能の実用的検証。
tar はサブコマンドを持たないため、既存 example とは異なるアーキテクチャパターンを実証する。

## tar → kuu マッピング

### 操作モード（排他・必須）

| tar option | kuu 実装 |
|---|---|
| `-c` / `--create` | `flag(name="create", shorts="c")` |
| `-x` / `--extract` / `--get` | `flag(name="extract", shorts="x", aliases=["get"])` |
| `-t` / `--list` | `flag(name="list", shorts="t")` |
| `-r` / `--append` | `flag(name="append", shorts="r")` |
| `-u` / `--update` | `flag(name="update", shorts="u")` |
| `-d` / `--diff` / `--compare` | `flag(name="diff", shorts="d", aliases=["compare"])` |
| `-A` / `--catenate` / `--concatenate` | `flag(name="catenate", shorts="A", aliases=["concatenate"])` |
| `--delete` | `flag(name="delete")` (short なし) |
| `--test-label` | `flag(name="test-label")` (short なし) |

制約: `exclusive` + `at_least_one` で「排他かつ必須」を実現。

### 圧縮方式（排他・任意）

| tar option | kuu 実装 |
|---|---|
| `-z` / `--gzip` / `--gunzip` / `--ungzip` | `flag(name="gzip", shorts="z", aliases=["gunzip", "ungzip"])` |
| `-j` / `--bzip2` | `flag(name="bzip2", shorts="j")` |
| `-J` / `--xz` | `flag(name="xz", shorts="J")` |
| `-Z` / `--compress` / `--uncompress` | `flag(name="compress", shorts="Z", aliases=["uncompress"])` |
| `--zstd` | `flag(name="zstd")` |
| `--lzip` | `flag(name="lzip")` |
| `--lzma` | `flag(name="lzma")` |
| `--lzop` | `flag(name="lzop")` |
| `-a` / `--auto-compress` | `flag(name="auto-compress", shorts="a")` |

制約: `exclusive` のみ（任意、選択しなくてもよい）。

### 値付きオプション

| tar option | kuu 実装 |
|---|---|
| `-f` / `--file` | `string_opt(name="file", shorts="f", value_name="ARCHIVE")` |
| `-C` / `--directory` | `append_string(name="directory", shorts="C", value_name="DIR")` |
| `--exclude` | `append_string(name="exclude", value_name="PATTERN")` |
| `-X` / `--exclude-from` | `string_opt(name="exclude-from", shorts="X", value_name="FILE")` |
| `-T` / `--files-from` | `string_opt(name="files-from", shorts="T", value_name="FILE")` |
| `--strip-components` | `int_opt(name="strip-components", post=in_range(0, 999))` |
| `-H` / `--format` | `string_opt(name="format", shorts="H", choices=[...])` |
| `-I` / `--use-compress-program` | `string_opt(name="use-compress-program", shorts="I", value_name="COMMAND")` |
| `--transform` / `--xform` | `append_string(name="transform", aliases=["xform"], value_name="EXPRESSION")` |
| `-V` / `--label` | `string_opt(name="label", shorts="V", value_name="TEXT")` |
| `-b` / `--blocking-factor` | `int_opt(name="blocking-factor", shorts="b", value_name="BLOCKS")` |
| `--owner` | `string_opt(name="owner", value_name="USER[:UID]")` |
| `--group` | `string_opt(name="group", value_name="NAME[:GID]")` |
| `--mode` | `string_opt(name="mode", value_name="CHANGES")` |

### フラグ

| tar option | kuu 実装 |
|---|---|
| `-v` / `--verbose` | `count(name="verbose", shorts="v")` |
| `-p` / `--preserve-permissions` | `flag(name="preserve-permissions", shorts="p", aliases=["same-permissions"])` |
| `-k` / `--keep-old-files` | `flag(name="keep-old-files", shorts="k")` |
| `-m` / `--touch` | `flag(name="touch", shorts="m")` |
| `-U` / `--unlink-first` | `flag(name="unlink-first", shorts="U")` |
| `-W` / `--verify` | `flag(name="verify", shorts="W")` |
| `-w` / `--interactive` / `--confirmation` | `flag(name="interactive", shorts="w", aliases=["confirmation"])` |
| `-P` / `--absolute-names` | `flag(name="absolute-names", shorts="P")` |
| `-S` / `--sparse` | `flag(name="sparse", shorts="S")` |
| `-h` / `--dereference` | `flag(name="dereference", shorts="h")` |
| `--numeric-owner` | `flag(name="numeric-owner")` |
| `--overwrite` | `flag(name="overwrite")` |
| `--no-recursion` | `flag(name="no-recursion")` |
| `--totals` | `flag(name="totals")` |
| `--full-time` | `flag(name="full-time")` |
| `--one-file-system` | `flag(name="one-file-system")` |

### variation パターン（対称フラグ）

| tar option pair | kuu 実装 |
|---|---|
| `--wildcards` / `--no-wildcards` | `flag(name="wildcards", variation_false=Some("no"))` |
| `--anchored` / `--no-anchored` | `flag(name="anchored", variation_false=Some("no"))` |
| `--acls` / `--no-acls` | `flag(name="acls", variation_false=Some("no"))` |
| `--selinux` / `--no-selinux` | `flag(name="selinux", variation_false=Some("no"))` |
| `--xattrs` / `--no-xattrs` | `flag(name="xattrs", variation_false=Some("no"))` |

### 位置引数

| 引数 | kuu 実装 |
|---|---|
| `FILES...` | `rest(name="files", description="Files or members to process")` |

### 環境変数

| 環境変数 | kuu 実装 |
|---|---|
| `TAR_OPTIONS` | 本来は env でデフォルトオプションを注入するが、今回は env メタデータ表示のみ |

## kuu 機能カバレッジ

本 example で検証する kuu 機能:

- [x] flag (単純 / default=true / hidden)
- [x] count (-v の複数回指定)
- [x] string_opt (値付き / choices / value_name)
- [x] int_opt (値付き / post filter)
- [x] append_string (複数回指定)
- [x] rest (残り引数収集)
- [x] exclusive (排他制約 — 2グループ)
- [x] at_least_one (必須制約)
- [x] aliases (同義オプション)
- [x] variation (--no-xxx 対称フラグ)
- [x] post filter (in_range)
- [x] env (メタデータ)
- [x] dashdash (-- セパレータ)
- [ ] sub (サブコマンド — 本 example では不使用)

## テストケース設計

1. **create**: `tar -cvzf archive.tar.gz --exclude='*.o' src/`
2. **extract**: `tar -xvf archive.tar --strip-components 1 -C /tmp/out`
3. **list**: `tar -tvf archive.tar`
4. **help**: `tar --help`
5. **排他エラー**: `tar -cx` (create と extract の同時指定)
6. **圧縮排他エラー**: `tar -czJ` (gzip と xz の同時指定)
7. **モード未指定エラー**: `tar -f archive.tar` (操作モードなし)
8. **variation**: `tar -cf archive.tar --no-wildcards --exclude='literal*' .`
9. **dashdash**: `tar -cf archive.tar -- --weird-filename`
10. **short bundling**: `tar -cvzf archive.tar.gz .`
