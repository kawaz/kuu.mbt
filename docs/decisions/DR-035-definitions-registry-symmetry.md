# DR-035: definitions は registry と同じ区分の名前空間、解決順の一様化

## 決定

### definitions は registry と同じ区分の名前空間を持つ

DR-007 で定義した `definitions` は当初フラットなマップ (`{color_template: {...}}`) だったが、本 DR で **registry と同じ区分の名前空間**を持つ構造に再定義する。

```json
{
  "definitions": {
    "types": {
      "color": {"type": "string", "values": [...]},
      "duration": {...}
    },
    "accumulators": {
      "my_merge": {...}
    },
    "filters": {
      "my_validator": {...}
    },
    "multiple": {
      "appendThenSet": {...}
    }
  }
}
```

参照側のフィールド名が、definitions と registry の両方で同じ区分を引く:

```
type: "color"        → definitions.types.color → registry.types.color → warn
multiple: "my_merge" → definitions.multiple.my_merge → registry.multiple.my_merge → warn
filters: ["..."]      → definitions.filters → registry.filters → warn
```

### 解決順は全区分で一様

DR-028 で `type` について確定した解決順 (definitions → registry → warn+string) を、**全 registry 区分に一様に適用**する。

```
解決順: definitions.X.name → registry.X.name → warn+フォールバック
```

ユーザのローカル定義 (definitions) > ライブラリのグローバル定義 (registry)。これは**前方互換性の保証** (DR-028) でもあり、レキシカルスコープの shadowing 原則と同じ。組み込みの拡張がユーザ定義を壊さない。

### 区分は必須 (糖衣で省略しない)

DR-007 のフラット形式 (`definitions: {color: {...}}`) のような「区分なしで書ける糖衣」は**設けない**。常に区分必須:

```
[OK]  definitions: {types: {color: {...}}}
[NG]  definitions: {color: {...}}  ← どの区分か曖昧、糖衣で展開しない
```

理由:
- 「区分=用途」が明示される (DR-018 「配置で役割が決まる」と一貫)
- 糖衣展開時に「どの区分に入れるか」を中身依存で判別する必要が出る (暗黙ルール増加)
- typo の早期検出 (`definitions.tyeps.color` は「未知の区分」として検出可能)

## 経緯

kawaz の整理:

> 何も考えずに構造に落とすと definitions{types:{}} とする?

→ これは DR-018 の「配置で役割が決まる」と DR-010 の「フィールド名で registry が暗黙決定」の両方を、definitions 側にも対称に適用する形。

DR-007 のフラット形式の問題:
- 同じ名前を別カテゴリで使えない (`color` が type と accumulator 両方で使えない)
- 中身を見ないと用途が分からない (processor を持つなら type、mapper を持つなら accumulator?)
- 解決順を明示しにくい (どの registry を引くか曖昧)

区分付き形式の利点:
- registry との対称性 (両側に同じ区分)
- 解決順が一様に書ける (`definitions.X.name → registry.X.name`)
- 配置で意図が明示される

## 関連

- DR-007 (definitions, ref/link) — 本 DR でフラット形式を区分付きに変更
- DR-010 (外部レジストリ、フィールド名で暗黙決定)
- DR-018 (配置で役割が決まる)
- DR-028 (type の解決順、前方互換) — 本 DR で全区分に一般化
