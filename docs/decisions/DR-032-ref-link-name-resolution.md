# DR-032: ref/link が指すのは name、解決はスコープ内優先。type とは別物

## 決定

`ref` / `link` / `type` は **指す対象の種類が異なる**。統合する話ではない。

```
type: X   X は【型】。definitions(型) → registry で解決 (DR-028)
ref:  Y   Y は【name】。継承元ノードを指す
link: Z   Z は【name】。値セルの実体を指す
```

- `type` が指すのは型。
- `ref` / `link` が指すのは name (ノード)。

指す対象が違うので、解決順も別物 (並べて比較する必要すらない)。

## ref/link の name 解決スコープ

`ref` / `link` の name は:

1. **基本はスコープ内** (同じ command 配下の name)
2. **definitions からも取れる**

解決順: スコープ内 → definitions。

> refやlinkはnameだろ？typeはtypeだろ。これはdefinitionsからとっても良いですが基本はスコープ内から取るとこだろうね。(kawaz)

- link は値セルの実体を指すので「スコープ内セル → definitions プレースホルダ」。registry (型の関数置き場) は無関係。
- ref は継承元ノードを指すので「スコープ内ノード → definitions テンプレ」。

## DR-028 の訂正

DR-028 に「ref を type に統合する方向」という記述があるが、**これは誤り**。ref/link が指すのは name、type が指すのは型であり、指す対象が違うため統合という発想自体が成立しない。color の例は最初から `type:"color"` (definitions の型を type で参照) であり、ref を用いていない。

DR-028 の「ref→type 統合」関連の記述は本 DR で撤回する。DR-028 のうち有効なのは以下:

- type は definitions/registry への参照糖衣
- type の解決順: definitions → registry → warn+string (前方互換)
- value_parser は AST 外 (registry)
- flag/count/command/help は糖衣プリセット

「ref→type 統合」「ref/link の使い分けの分かりにくさを統合で解消」という方向性の記述のみ無効。

## 経緯

Claude が DR-028 で「ref と type は似ているので統合する方向」と提案していたが、これは「定義済みの何かを参照する」という表面的類似に引きずられた誤り。kawaz が「何を指すのか? ref や link は name だろ、type は type だろ」と二度指摘し、指す対象 (型 vs name) が違うという基本が確認された。統合は不要かつ不可能。

## 関連

- DR-007 (definitions, ref/link) — ref/link は name 参照、解決はスコープ内優先
- DR-028 (type=参照糖衣) — 「ref→type 統合」記述を本 DR で撤回、その他は有効
- DR-029 (link 値同期、固定パス DSL)
