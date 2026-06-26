# DR-014: 階層継承可能な設定は config フィールドに集約

## 決定

「全要素横断の挙動設定」を `config` フィールドに集約する。子要素は親の config を継承、必要なら上書き可能。

```json
{
  "name": "mycli",
  "type": "command",
  "config": {
    "long_prefix": "--",
    "short_prefix": "-",
    "env_prefix": "MYAPP",
    "auto_env": false,
    "allow_equal_separator": true,
    "short_combine": true
  },
  "children": [...]
}
```

(フィールド名は snake_case。DR-022 参照)

## 経緯

「long_prefix を設定する場所」の議論から発展。

### long_prefix だけの議論

```bash
# GNU/POSIX
--verbose -v

# Go flag
-version

# X11
xclock -bg blue
```

これを CLI 別に切り替えたい。最初の候補:
- 案A: パーサ全体の設定 (parser config 外付け)
- 案B: 要素ごとに指定可能
- 案C: 階層構造で継承

kawaz:
> 普通はパーサ単位で良いと思うんだけど、引数定義の筈なのに引数AST外の扱いになるのが微妙。なのでC案のみ（トップレベルで設定に含めれば良い）はどうだろ。

→ **AST 内の階層継承可能な設定** に統一。

### config フィールドで集約

`long_prefix`, `short_prefix` 以外にも階層継承させるべき設定がいくつか:
- env_prefix / auto_env
- allow_equal_separator / short_combine

これらを要素属性とは別の `config` フィールドにまとめる。

### dashdash / help / version は config に含めない

- **dashdash**: 「greedy な exact で children に分岐するだけのシュガー」(kawaz) なので AST に直接書く
- **help / version**: 「help, version を特殊なものとするにしても、どんな引数でそれを起動するか?てのも関係するんだから typeあたりにするのが良いのだは?」(kawaz)
  - → `type: "help"` と `type: "version"` (実は version はただのフラグ) で扱う
  - → config に含めない

これで config は **「全要素横断、AST 構造として書けない設定」だけ**に絞られる。

## 含めるもの

- `long_prefix` / `short_prefix`: 表記の慣習
- `env_prefix` / `auto_env`: 環境変数の慣習
- `allow_equal_separator`: `--name=value` の許可
- `short_combine`: `-abc` の結合許可

## 含めないもの

- `dashdash`: AST 直接表現可能
- `help` / `version`: type で表現

## 効果

- 「設定もASTの一部」になり、JSON export/import で漏れない
- AST 1個で完結 (外付け設定が不要)
- 子 scope で独自の設定を持つこともできる (まれだが可能)
- AST 要素の属性 vs スコープ設定の区別が明確

## 関連

- DR-002 (要素属性とは別の枠)
- DR-005 (help / version は type)
- DR-022 (フィールド名 snake_case 化)
- DR-031 (値源優先順位: config ファイル由来の値の扱い)

## Superseded (歴史)

> 以下の記述は後続 DR で覆された。現役仕様の理解には不要、判断経緯としてのみ残す。

### camelCase フィールド名 (DR-022 で更新)

> **更新: DR-022 によりフィールド命名が camelCase → snake_case に変更。本 DR の階層継承構造・含める/含めない判断は引き続き有効。**

制定当時、config フィールドは camelCase で表記されていた:

- `longPrefix` / `shortPrefix`
- `envPrefix` / `autoEnv`
- `allowEqualSeparator` / `shortCombine`
- `helpFlag` / `helpShort` (こちらは別途却下され、type へ移行)
- `dashdash` / `helpFlag` / `versionFlag` (NG リストの旧表記)

現役表記は本文上部の通り。

### config と値源優先順位の関係 (DR-031 で更新)

> **更新: DR-031 で値源優先順位 (CLI 引数 / 環境変数 / config ファイル / default) として整理。本 DR は config の AST 内集約と継承構造を規定する範囲で引き続き有効。**

本 DR は「config を AST 内に集約し、子で継承・上書き可能」までを規定。
config ファイル (外部 settings 由来) の値がどう適用されるかは当初未規定だった。
