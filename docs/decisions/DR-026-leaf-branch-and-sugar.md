# DR-026: 葉/枝の区別、exact は値プリミティブの一種、構造記法の糖衣

## 決定

### ノードは葉か枝

```
葉ノード (プリミティブ): 自分でトークンを消費する。children 無し。
  - 値プリミティブ: string / number / bool / ...  (トークン消費 → 値)
  - exact:                                        (綴り照合消費 → 値なし or literal)

枝ノード (構造): 子に消費を委ね、結果を畳む。children 必須。
  - or:  子から1つ選ぶ
  - seq: 子を順に消費 (DR-027 で serial から改名)
```

### exact は値プリミティブの一種

exact と値プリミティブの違いは「消費したトークンを値として残すか」だけ:

- `number` … `80` を消費 → 値 80 を残す
- `exact "--port"` … `--port` を照合消費 → 値を残さない (マッチした事実だけ)
- `exact` に value あり … `--no` を消費 → literal false を残す (DR-011 variant DSL)

exact = 「トークンを照合消費するプリミティブ。値は持っても持たなくてもよい」。値プリミティブの「値を残さない/literal を残す」変種。**葉側**。当初 structure 側に置こうとしたが kawaz が訂正:

> exact は引数消費する値を持たなくても良いプリミティブで、値プリミティブにかなり近いまたは値プリミティブの一種。

### 構造記法は形/キーで判別 (タグ不要)

`type: "or"` のようにタグで名乗らず、**キーの有無・形でノード種を判別**する:

```
"x"          → {exact: "x"}      裸文字列 = exact の糖衣 (綴り照合)
[...]         → {seq: [...]}      裸配列 = seq の糖衣
{or: [...]}    → 選択
{seq: [...]}   → 順次 (name 等を付けたい時の明示形)
{type: ...}    → 値プリミティブ (葉)
```

裸の値 → 一番自然な構造への糖衣、という統一原理:

| 裸の値 | 展開先 | 理由 |
|---|---|---|
| 文字列 `"x"` | `{exact: "x"}` | 文字列は「綴りを照合」が自然 |
| 配列 `[...]` | `{seq: [...]}` | 配列は「順に並べる」が自然 |

数値・真偽値リテラルが裸で来るケースは無い (CLI トークンは常に文字列、照合対象になる裸リテラルは文字列のみ)。

### or/seq キーは通常フィールドと同居可

`{or:[...]}` は「`or` フィールドを持つ通常ノード」。name/multiple/value_name 等と同居できる (C パターン `{name:"color", or:[...]}` のため必須)。裸配列 `[...]` は name 等を付けたくなったら `{seq:[...]}` に展開して修飾を足す。

## --port 80 の UsefulAST → AtomicAST

```
UsefulAST (ユーザが書く):
  options: [{name: "port", type: "number", default: "80"}]

  ↓ 展開

AtomicAST (パースループ):
  {seq: [
    {exact: "--port"},                          ← 照合専用、結果キーでない
    {type: "number", name: "port", default: "80"} ← 結果キー
  ]}
```

- UsefulAST では `name:"port"` 一つ。綴り (`--port`) も結果キー (`port`) も name から導出。
- AtomicAST で exact + 値ノードの seq に分離。exact は照合専用、結果キーは値ノード側。
- 「exact の照合文字列 vs name」問題は AtomicAST 内部に閉じ、UsefulAST ユーザは意識しない。
- `option` は `seq[exact, value]` への愛称 (DR-002)。exact を生で書くのは糖衣で表せない特殊照合時のみ。
- default は値を持つノード側に付く (exact には付かない)。

## 確定した UsefulAST 構造語彙

```
"x"                  → exact (綴り照合、値なし/literal)
[...]                 → seq (順に並ぶ)
{or:[...]}             → 選択 (いずれか1つ)
{seq:[...]}            → 順次 (name 付けたい時の明示)
{type:...}             → 値プリミティブ (葉: number/string/bool/exact)
multiple              → 反復の畳み込み (list/map) [DR-019]
name 持ち子が並ぶ      → 結果が kv (object は露出の帰結、独立構造なし) [DR-025]
```

## 関連

- DR-002 (同型・慣習名は愛称)
- DR-005 (type categories) — type=葉の値型に整理
- DR-011 (variant DSL) — exact の literal 値
- DR-019 (multiple/反復)
- DR-025 (name 露出・object は帰結)
- DR-027 (serial → seq 改名)
