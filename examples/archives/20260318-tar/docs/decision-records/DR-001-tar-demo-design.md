# DR-001: tar デモ設計計画

## ステータス

承認済み

## コンテキスト

kuu ライブラリの多彩なコンビネータ・制約機能を示すデモとして、GNU tar コマンドの引数パースを実装する。tar の実機能（アーカイブ操作）は実装しない。パース結果を表示するのみ。

tar はサブコマンドを持たず、`-c`/`-x`/`-t` 等のモードフラグで動作を選択する伝統的な CLI 設計であり、kuu の `exclusive` + `at_least_one` による排他・必須制約のショーケースとして最適である。

## 決定

### アーキテクチャ

**フラット構造**（サブコマンドなし）。tar の動作モード選択は `flag` + `exclusive` + `at_least_one` で表現する。

### 実装するオプション

#### 動作モード（排他 + 最低1つ必須）

| short | long | 説明 |
|---|---|---|
| `-c` | `--create` | アーカイブ作成 |
| `-x` | `--extract` / `--get` | 抽出（`--get` は alias） |
| `-t` | `--list` | 内容一覧 |
| `-r` | `--append` | ファイル追加 |
| `-u` | `--update` | 更新 |

kuu 機能: `flag` x 5 + `exclusive` + `at_least_one` + `alias`（`--get`）

#### 圧縮方式（排他、省略可）

| short | long | 説明 |
|---|---|---|
| `-z` | `--gzip` | gzip |
| `-j` | `--bzip2` | bzip2 |
| `-J` | `--xz` | xz |
| — | `--zstd` | Zstandard |
| `-Z` | `--compress` | compress（deprecated） |
| `-a` | `--auto-compress` | 拡張子から自動判定 |

kuu 機能: `flag` x 5 + `exclusive` + `deprecated`（`-Z`、msg="use --gzip instead"）

#### ファイル指定

| short | long | 説明 |
|---|---|---|
| `-f` | `--file` | アーカイブファイル（必須、env: TAPE） |

kuu 機能: `string_opt` + `required` + `env="TAPE"` + `value_name="ARCHIVE"`

#### 詳細度

| short | long | 説明 |
|---|---|---|
| `-v` | `--verbose` | 重ね掛け可能（`-vv` でさらに詳細） |

kuu 機能: `count` + `variation_reset=Some("no")` -> `--no-verbose`

#### フィルタ・制御

| short | long | 説明 |
|---|---|---|
| — | `--exclude=PATTERN` | 除外パターン（複数回指定可） |
| — | `--strip-components=N` | パス先頭 N 個除去 |
| — | `--format=FMT` | アーカイブ形式（gnu/ustar/pax/oldgnu） |

kuu 機能: `append_string` + `int_opt` + `string_opt(choices=...)`

#### フラグ各種

| short | long | 説明 |
|---|---|---|
| `-p` | `--preserve-permissions` | パーミッション保持 |
| `-k` | `--keep-old-files` | 上書きしない |
| `-m` | `--touch` | タイムスタンプ更新しない |
| `-P` | `--absolute-names` | 絶対パス保持 |
| `-w` | `--interactive` | 確認プロンプト |
| — | `--totals` | 統計表示 |
| — | `--recursion` / `--no-recursion` | 再帰処理 |

kuu 機能: `flag` x 7、`--recursion` には `variation_false=Some("no")`

#### ディレクトリ変更

| short | long | 説明 |
|---|---|---|
| `-C` | `--directory=DIR` | ディレクトリ変更 |

kuu 機能: `append_string` + `value_name="DIR"`

注: 実際の tar では `-C` は位置依存（出現位置によって対象が変わる）だが、本デモでは `append_string` で収集しアプリ側で処理する方式で代替する。

#### 位置引数

- `[FILE]...` — アーカイブ対象/抽出対象ファイル

kuu 機能: `rest`

### kuu 機能カバレッジ

| kuu 機能 | tar での使用例 |
|---|---|
| `flag` | -c, -x, -t, -r, -u, -p, -k, -m, -P, -w, --totals, --recursion, -z, -j, -J, --zstd, -a |
| `count` | -v (verbose) |
| `string_opt` | -f (file) |
| `string_opt` + `choices` | --format |
| `int_opt` | --strip-components |
| `append_string` | --exclude, -C (directory) |
| `rest` | [FILE]... |
| `exclusive` | モード群、圧縮群 |
| `at_least_one` | モード群 |
| `required` | -f (file) |
| `env` | -f の TAPE 環境変数 |
| `alias` | --get (extract のエイリアス) |
| `deprecated` | -Z (compress) |
| `variation_false` | --no-recursion, --no-verbose |
| `shorts` | -c, -x, -t, -r, -u, -z, -j, -J, -Z, -f, -v, -C, -p, -k, -m, -P, -w, -a |
| `description` | 全オプションに説明文 |
| `value_name` | ARCHIVE, DIR, PATTERN, N, FMT |

### テスト計画

main.mbt 内で `test` ブロックを使い、各シナリオをテスト:

1. **基本モード**: `tar -cf archive.tar file1 file2`
2. **抽出**: `tar -xf archive.tar`
3. **一覧**: `tar -tf archive.tar`
4. **verbose count**: `tar -tvvf archive.tar`
5. **圧縮**: `tar -czf archive.tar.gz dir/`
6. **排他エラー**: `tar -cx -f archive.tar` -> エラー
7. **圧縮排他エラー**: `tar -czj -f archive.tar` -> エラー
8. **モード未指定エラー**: `tar -f archive.tar file` -> エラー
9. **-f 必須エラー**: `tar -c file` -> エラー
10. **--exclude 複数**: `tar -cf a.tar --exclude=*.log --exclude=*.tmp .`
11. **--strip-components**: `tar -xf a.tar --strip-components=1`
12. **--format choices**: `tar -cf a.tar --format=pax .`
13. **--format 不正値**: `tar -cf a.tar --format=zip .` -> エラー
14. **deprecated -Z**: `tar -cZf a.tar .` -> パース成功、deprecated_usages に記録
15. **alias --get**: `tar --get -f a.tar` -> extract と同値
16. **--no-recursion**: `tar -cf a.tar --no-recursion .`
17. **--no-verbose**: `tar -tvf a.tar --no-verbose`
18. **env TAPE**: `-c file` + env TAPE=backup.tar -> -f 不要
19. **ヘルプ表示**: `tar --help`
20. **ショートオプション結合**: `tar -czvf archive.tar.gz dir/`

## 理由

### tar を選んだ理由

1. **フラット構造で排他制約が自然**: サブコマンドなしの CLI で `exclusive` + `at_least_one` の組み合わせを自然に示せる
2. **オプション種別が豊富**: flag, count, string_opt, int_opt, append_string, rest を一つの example で網羅できる
3. **実世界の CLI**: 全開発者が知っているコマンドであり、デモの説得力が高い
4. **kuu 機能の高カバレッジ**: 1つの example で 18 種類の kuu 機能を使用

### 意図的に除外した kuu 機能

| 機能 | 除外理由 |
|---|---|
| `sub()` / `cmd()` | tar はサブコマンドを使わない |
| `custom[T]` / `custom_append[T]` | 汎用型は不要 |
| `serial()` | 直列位置引数は不要 |
| `dashdash()` | tar では `--` の特別な扱いなし（kuu デフォルトの `--` は有効） |
| `link()` / `adjust()` / `clone()` | 値転送は不要 |
| `requires()` | 依存制約は tar では不要（-r/-u は -f 必須だが、今回は全モードで -f 必須） |
| `implicit_value` | tar では使わない |
| `hidden` | 隠しオプションは不要 |

これらは別の example（git, docker 等）で示す方が自然である。

## 未実装・今後の検討事項

### Bundled flags（先頭 `-` なし）

実際の GNU tar は `tar xvf file.tar` のように先頭 `-` なしの旧形式（bundled flags）をサポートする。これは tar 固有の慣習であり、kuu のパーサスコープ外である。

対応が必要な場合は、kuu の `parse()` に渡す前の前処理で引数を変換する方式で実現可能:

```
"xvf" -> "-xvf"
```

kuu 本体への機能追加は不要。

### -C の位置依存セマンティクス

実際の tar では `-C dir1 file1 -C dir2 file2` のように `-C` の出現位置が後続のファイル引数に影響する。本デモでは `append_string` で収集しアプリ側で処理する方式で代替する。

位置依存パースは kuu の `post` フック等で部分的に再現可能だが、デモの焦点ではないため除外した。
