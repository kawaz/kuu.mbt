# DR-014: 階層継承可能な設定は config フィールドに集約

## 決定

「全要素横断の挙動設定」を `config` フィールドに集約する。子要素は親の config を継承、必要なら上書き可能。

```json
{
  "name": "mycli",
  "type": "command",
  "config": {
    "longPrefix": "--",         // デフォルト
    "shortPrefix": "-",          // デフォルト
    "envPrefix": "MYAPP",
    "autoEnv": false,
    "allowEqualSeparator": true,
    "shortCombine": true
  },
  "children": [...]
}
```

## 経緯

「longPrefix を設定する場所」の議論から発展。

### longPrefix だけの議論

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

`longPrefix`, `shortPrefix` 以外にも階層継承させるべき設定がいくつか:
- envPrefix / autoEnv
- allowEqualSeparator / shortCombine
- helpFlag / helpShort (注: 後で却下)

これらを要素属性とは別の `config` フィールドにまとめる。

### dashdash / help / version は config に含めない

- **dashdash**: 「greedy な exact で children に分岐するだけのシュガー」(kawaz) なので AST に直接書く
- **help / version**: 「help, version を特殊なものとするにしても、どんな引数でそれを起動するか?てのも関係するんだから typeあたりにするのが良いのだは?」(kawaz)
  - → `type: "help"` と `type: "version"` (実は version はただのフラグ) で扱う
  - → config に含めない

これで config は **「全要素横断、AST 構造として書けない設定」だけ**に絞られる。

## 含めるもの

- `longPrefix` / `shortPrefix`: 表記の慣習
- `envPrefix` / `autoEnv`: 環境変数の慣習
- `allowEqualSeparator`: `--name=value` の許可
- `shortCombine`: `-abc` の結合許可

## 含めないもの

- `dashdash`: AST 直接表現可能
- `helpFlag` / `versionFlag`: type で表現

## 効果

- 「設定もASTの一部」になり、JSON export/import で漏れない
- AST 1個で完結 (外付け設定が不要)
- 子 scope で独自の設定を持つこともできる (まれだが可能)
- AST 要素の属性 vs スコープ設定の区別が明確

## 関連

- DR-002 (要素属性とは別の枠)
- DR-005 (help / version は type)
