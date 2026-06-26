# DR-027: serial → seq に改名 (or / seq / multiple = alternation / concatenation / closure)

## 決定

順次連接の構造プリミティブを **`serial` から `seq` に改名**する。

```
or       選択 (いずれか1つ)
seq      順次 (順に並んだもの)
multiple 反復 (繰り返しの畳み込み)
```

**`serial` は廃止語であり、現役の語彙としては使用しない。canonical は `seq`。** 本 DR 本文中で歴史的経緯のため `serial` に言及している箇所は、すべて旧名としての参照である。

## 経緯

`or`(2文字) に対し `serial`(6文字) の非対称、および `serial` が引数パーサ文脈で慣習語でない点から再検討。

各分野での「順序付き連接」の呼称を調査:

- **形式言語・正規表現**: alternation ↔ **concatenation**。3演算 = alternation(`|`) / concatenation / closure(`*`)。
- **PEG**: ordered choice(`/`) ↔ **sequence**(`e1 e2`)。
- **型・スキーマ**: sum type / oneOf ↔ **tuple** / product type。
- **引数パーサ (clap/argparse/cobra)**: 順次連接に専用語彙が薄い。positional の順序として暗黙扱い。旧名 `serial` は通信/直列化を連想させ異質。

候補比較:

| 用語 | 出自 | 評価 |
|---|---|---|
| concatenation/concat | 正規表現 (alternation の正式な対) | 「連結・生成」の含意。引数パースは「順に意味を取り出す解析」で方向が逆 |
| tuple | 型・スキーマ (product) | 「固定長」の含意が強い。引数は省略可/repeat/可変長で固定長でない |
| **seq** (sequence) | PEG | 「順に並んだもの」だけを表し余計な含意が最小。短い |

kawaz の最終判断:

> seq で良いかもな。要は順番に並んだもの、を表現したいだけ。concatenation は連結的なイメージで、引数パースは連結ではなく順に意味を取り出していく感じでイメージと離れる。tuple は固定長の意味合いが強く、引数は複数ポジショナルでも省略可能やリピートなどあり固定長ではない。

**含意の少なさ** が seq の決め手。or/seq/multiple で選択・順序・反復という直交概念を、余計な意味を足さず名乗れる。正規表現の3演算 (alternation/concatenation/closure) にも対応。

## 補足: 明示頻度の非対称

- `or` … 裸の糖衣がなく毎回 `{or:[...]}` と書く → 頻出 → 短さが効く
- `seq` … 裸配列 `[...]` が糖衣 (DR-026) なので明示 `{seq:[...]}` は name 付け時のみ → 稀

`seq` キーを明示で書く場面は少ないが、書くなら短い方がよい。3文字で十分。

## 関連

- DR-019 (multiple = closure/反復)
- DR-026 (構造記法の糖衣、裸配列 = seq)
