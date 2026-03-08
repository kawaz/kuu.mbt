# examples/20260308-mygit

2026-03-08 時点の kuu API で作成した git 風 CLI サンプル。

## ビルド・実行

```bash
moon build
moon run examples/20260308-mygit
```

## 使用している API 機能一覧

### Parser

- `Parser::new()` — パーサ生成
- `Parser::set_description()` — ヘルプ用説明文
- `Parser::parse()` — パース実行（`!` suffix で raise）
- `Parser::require_cmd()` — サブコマンド必須制約

### コンビネータ

| API              | 用途                                 | 使用箇所        |
| ---------------- | ------------------------------------ | --------------- |
| `flag`           | ブールフラグ                         | 多数            |
| `string_opt`     | 文字列オプション                     | commit -m, etc  |
| `int_opt`        | 整数オプション                       | clone --depth   |
| `count`          | カウンタ (-v, -vv, -vvv)            | verbose         |
| `append_string`  | 繰り返し文字列 (--author --author)   | log --author    |
| `positional`     | 位置引数                             | clone url, etc  |
| `rest`           | 残り全引数                           | add files, etc  |
| `serial`         | 位置引数の直列消費                   | remote add, etc |
| `never`          | 追加引数を拒否                       | remote add      |
| `dashdash`       | `--` 以降の引数キャプチャ            | checkout, stash |
| `sub`            | サブコマンド（Ref 不要の直接 API）   | 全サブコマンド  |
| `cmd`            | サブコマンド（setup コールバック型）  | (sub 経由で内部使用) |

### 制約

| API          | 用途                   | 使用箇所                    |
| ------------ | ---------------------- | --------------------------- |
| `exclusive`  | 排他制約               | verbose/quiet, push force等 |
| `required`   | 必須制約               | clone url, commit message   |

### Opt アクセス

- `Opt::get()` — パース後の値取得（`T?` を返す）
- `Opt::as_ref()` — 制約用の OptRef 変換

### Variation

- `variation_reset=Some("no")` — `--no-verbose` でカウントリセット
- `variation_false=Some("no")` — `--no-verify` で false に設定
- `variation_unset=Some("no")` — `--no-author-date-is-committer-date` でフラグ解除

### choices + implicit_value

- `--color` : choices=["always","never","auto"], implicit_value="always"
  - `--color` (値なし) -> "always"
  - `--color=never` -> "never"

### implicit_value (int)

- `diff --unified` : implicit_value=3
  - `--unified` -> 3
  - `--unified 5` -> 5
- `stash pop --index`, `stash drop --index` : implicit_value=0

### Filter (post)

- `Filter::trim().then(Filter::non_empty())` — commit message の空文字拒否

### hidden

- `--debug-internal` — help に表示されない隠しフラグ

### default=true フラグ

- `commit --verify` — デフォルト true、`--no-verify` で false

## サブコマンド構成

```
mygit
  clone     -- Clone a repository
  commit    -- Record changes
  log       -- Show commit logs
  add       -- Add file contents to the index
  push      -- Update remote refs
  pull      -- Fetch and merge
  branch    -- List, create, or delete branches
  checkout  -- Switch branches or restore files
  diff      -- Show changes between commits
  status    -- Show working tree status
  tag       -- Create, list, delete or verify tags
  remote    -- Manage tracked repositories
    add     -- Add a remote
    remove  -- Remove a remote
    rename  -- Rename a remote
  stash     -- Stash changes
    push    -- Save local modifications
    pop     -- Apply and remove stash
    list    -- List stash entries
    drop    -- Drop a stash entry
  config    -- Get and set options
```

## 前回 (20260307) からの API 変化点

- API 自体に変更なし（同一バージョン）
- 今回は以下の機能をより網羅的に使用:
  - `variation_reset`, `variation_false`, `variation_unset` のシュガーパラメータ
  - `choices` のみの string_opt（log --format）
  - `int_opt` の `implicit_value`（diff --unified, stash pop/drop --index）
  - `exclusive` の 3 択（config --global/--local/--system）
  - ネストサブコマンドの追加（remote rename, stash drop）
  - `dashdash` を checkout で使用
  - `rest` を log paths / diff paths で使用
