# DR-007: definitions 領域、ref (構造継承) と link (値同期) の分離

## 決定

各 scope に `definitions` フィールドを設け、テンプレート/値プレースホルダ専用領域として使う:

```json
{
  "definitions": {
    "color_template": {"type": "string", "values": ["red", "green", "blue"]}
  },
  "options": [
    {"ref": "color_template", "name": "fg"}
  ]
}
```

参照は2種類:
- **ref**: 構造継承 (プロトタイプ的)
- **link**: 値同期 (書いた側が参照、書かれた側が実体)

## 経緯

最初は ref/link で参照対象を children の中に混ぜていたが、kawaz の整理:

> colorみたいな再利用可能な構造をrefで参照する用とか、timerangeみたいな複数オプションからlinkで実態参照される値のプレースホルダ的な要素とかを定義する場所も欲しいか？
> childrenの中に混ぜれもするけど分けれた方が見通しが良くなって嬉しい気もする。

定義領域を `definitions` フィールドで分離することで:
- 「テンプレートとして使う要素」と「CLI で起動する入口」が視覚的に区別される
- definitions 内の要素はデフォルトで結果オブジェクトに出ない (CLI 上で直接消費されない)
- スコープ階層的に書ける (各 command で独自の definitions)

## ref vs link

| | ref | link |
|---|---|---|
| 引き継ぐもの | 構造定義全て (型/children/filters/...) | 値の書き込み先のみ |
| 用途 | テンプレート再利用、alias、deprecated 別名 | 別経路での値供給 |
| 比喩 | プロトタイプ継承 | 参照渡し |

ref で構造を継承、必要なら差分フィールドだけ上書き:
```json
{
  "ref": "run",
  "name": "exec",
  "deprecated": true
}
```

link は「値の流入先のワイヤー」:
```json
{"name": "since", "link": "since_value"}
```

## link の方向性

kawaz の整理:
> linkに関して値の主従は特になくてどっちでも良いのでは?

から、議論の中で:
> linkは基本linkを書いた側が参照でlinkされた方が実体て方が素直と思う。

**書いた側 = 参照、書かれた側 = 実体**、という方向性を持たせる。これで:
- 入口 (参照側) から実体への書き込み一方向で動作
- 双方向同期の複雑さがなくなる
- 「実体は1つ」が明確

## 構造化タイプへの link (セレクタ言語) は採用しない

```json
{"link": "tr.since"}  // ←セレクタ言語的なネスト link
```

これは便利だが:
- 言語実装が複雑 (Go/MoonBit でリフレクションなし)
- セレクタ言語の設計負担

初期スコープでは入れない。primitive な値セルに分解して構造で表現する。

## 関連

- DR-006 (lexical scope chain)
- DR-008 (multiple, keyFrom)
