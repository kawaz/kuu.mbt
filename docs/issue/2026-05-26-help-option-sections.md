# `--help` のオプションをカテゴリ/セクション分けで表示する機能

- Status: Open
- Date: 2026-05-26
- Priority: Middle (CLI parser/help generator の UX 改善)
- 発見元: kawaz/hyoui の CLI 設計議論 (paste サブコマンドのオプション数が増えた時に、カテゴリ分けすると圧倒的に読みやすくなると判明)

## 背景

CLI のオプションが増えると、フラットな羅列は読みづらく、意味的に近いものをグループ化したくなる。
hyoui の `paste` サブコマンド設計で、オプションを「入力源 / spool / size / その他」に
カテゴリ分けして提示したところ非常に読みやすかった。

## アイデア

CLI parser / help generator (kuu-cli または将来の関連 module) に **オプションのセクション概念** を first-class でサポート。

### 想定する `--help` 出力イメージ

```
$ hyoui paste --help
USAGE
  hyoui paste <name> [options]

INPUT (mutually exclusive)
  --text TEXT          Inline text
  --file PATH          From file (- for stdin)
  (omitted)            stdin

SPOOL
  --spool=memory       Buffer in RAM (default)
  --spool=tmpfile      Buffer in temp file
  --spool=<path>       Buffer in specific file
  --spool=none         Stream without buffering

SIZE
  --max-size SIZE      Limit (default 16MB, 0 for unlimited)
                       For spool=memory|tmpfile|file: reject if exceeded
                       For spool=none: truncation point

FORMATTING
  --newline=preserve|lf|crlf  (default: preserve)
  --add-newline               Append newline at end

PASTE PROTOCOL
  --bracketed | --no-bracketed   (default: auto-detect)
  --chunk SIZE                   (default: 4096)
  --chunk-delay DUR              (default: 0)

LOCK
  --token T            Lock token (env HYOUI_LOCK_TOKEN auto-used)
```

フラット列挙だと一覧性が悪く、意味的グルーピングがあると視線移動が減る。
特に MUTUALLY EXCLUSIVE 系のオプション群を `INPUT` `SPOOL` のようにラベル化すると、
「同じグループ内は択一」が暗黙的に伝わる効果もある。

## 提案する API イメージ

例 (MoonBit、kuu-cli の builder pattern 想像):

```moonbit
let cmd = Cli::new("hyoui paste")
  .section("INPUT", _ =>
    _.option_text(...).option_file(...).group_exclusive())
  .section("SPOOL", _ =>
    _.option("--spool", ...))
  .section("SIZE", _ =>
    _.option("--max-size", ...))
  // ...
```

または attribute / metadata 形式:

```moonbit
@cli_option(section="SPOOL", default="memory")
let spool : String
```

## 考慮点

- セクション順序はユーザ指定 (定義順 or 明示)
- セクション無指定のオプションは `OPTIONS` 等の default セクションに集約
- `--help` 出力の幅 (terminal width) に応じた折り返し
- man page / completion 生成にもセクション情報を活かせる (zsh completion の `_arguments` の `*::group:` 等)

## 関連

- 関連プロジェクト: kawaz/hyoui の paste CLI 設計 (2026-05-26 設計議論)
- kuu-cli が既に merge されているので、その API に乗せる形が筋
