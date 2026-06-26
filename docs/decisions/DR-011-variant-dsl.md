# DR-011: variant の文字列 DSL とオブジェクト形式

## 決定

long の variant (`--no-X` のような同 opt の別入口) を以下で表現:

### 文字列 DSL (シンプルケース)

```
"<prefix>:<effect>[:<arg1>[:<arg2>...]]"
```

例:
- `"no:set:false"` — `--no-<name>` で false をセット
- `"no:set:none"` — `--no-<name>` で "none" をセット
- `"no:default"` — defaultValue に戻す (committed=true)
- `"no:unset"` — defaultValue に戻す (committed=false)
- `"reset:empty"` — 配列/Map を空に
- `"red:set:rgb:255:0:0"` — `--red-<name>` で複合値をセット

### オブジェクト形式 (複雑なケース)

```json
{
  "prefix": "red",
  "effect": "set",
  "args": ["rgb", "255", "0", "0"]
}
```

`args` はすべて **string** (CLI 引数パースと同じ手順を通す)。

## effect 語彙 (4種)

| effect | args | 意味 |
|---|---|---|
| `set` | 1個以上 (string[]) | 固定値をセット |
| `default` | なし | defaultValue に戻す (committed=true) |
| `unset` | なし | defaultValue に戻す (committed=false) |
| `empty` | なし | 配列/Map を空に |

## 経緯

### kuu 現状の Variation enum

```moonbit
pub enum Variation {
  Toggle(String)    // --{p}-{name}: !current
  True(String)      // --{p}-{name}: 常に true
  False(String)     // --{p}-{name}: 常に false
  Reset(String)     // committed=true で default に
  Unset(String)     // committed=false で default に
}
```

これを AST 仕様に落とすにあたって整理:

### Toggle の排除

「主名 (`--ssl`) を繰り返してトグル」のような挙動は CLI 慣習として薄い。kawaz:
> toggle:not とかでなく--ssl を重ねてトグルなんてある?まぁやるならpreconverter系フィルタで実現とか?

→ toggle は排除。

### True/False の統一

`Variation::True("force")` は `set:true` と等価、`Variation::False("no")` は `set:false` と等価。`set:<value>` で統一。

### Reset と Unset の差は committed

`default` (committed=true) と `unset` (committed=false) で残す。`required` 等の制約検査に影響する。

## "no" ショートハンドは入れない

kawaz:
> noショートハンドとかは要らない。アプリによってnoの挙動は結構まちまちでコンセンサスがあるとは思えないので明記が良い。

`"no"` 単独で「自動で何かする」ようなショートハンドは入れない。常に `"no:set:false"` のように明示書き。

## args は string[] (引数パースと同じ手順)

オブジェクト形式の `args` も文字列 DSL の `:` 区切り部分も、すべて **string** で渡す。

kawaz:
> オブジェクト形式はprefixやeffectは問題ないけどargsはstring[]であるべきかな。引数パースと同じパース（なんならフィルタなどもあるだろうし）手順を経る方が一貫性がある。nullとか入れられても逆にそれは引数だとなんなの?空文字とは違うよね?みたいなことなるよね。

これで:
- variant で `set:none` が `--<name> none` の入力と等価な経路を通る
- value 型のパース・filter チェーンが variant にも自然に効く
- AST の同型性 (variant も普通の CLI 入力もデータパスが同じ)

## variant は AtomicAST で消える

variant 構造は **AtomicAST には残らない**。parseDefinition() の時点で:

```json
// UsefulAST
{"name": "color", "long": ["no:set:none"]}

// AtomicAST 展開後
{
  "type": "or",
  "name": "color",
  "children": [
    { /* 主名 --color X の入口 */ },
    {
      /* --no-color の入口 */
      "type": "exact",
      "match": "--no-color",
      "value": {"type": "string", "value": "none"}
    }
  ]
}
```

variant は **exact + literal value 発生**に展開され、構造としては消える。

## 関連

- DR-009 (filter chain は同じ文法を使う)
