---
title: decode面の属性 silent discard 監査 (allowlist ⊆ carry 検査)
status: open
category: task
created: 2026-08-16T14:12:58+09:00
last_read:
open_entered: 2026-08-16T14:12:58+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ)
---

# decode面の属性 silent discard 監査 (allowlist ⊆ carry 検査)

## 概要 (A7 + R5 m1 統合)

構造分岐の属性が silent discard される問題群。「受理して黙って捨てる」パターンが decode 面の複数箇所に見られる (統合報告 P3 参照)。既知 issue 2026-07-26-dec-or-leaf-remaining-node-keys の拡張として扱う (exact 個別の対処は当該既知issueへ別途追記済み)。

## A7 (wire_decode): 構造分岐の属性 silent discard (2件マージ)

場所: src/kuu/wire_decode.mbt:2594, 2537, 2844 + 1923

- `dec_positional` の or分岐が multiple/accumulator/help 等を捨て、seq/group と三者非対称 (2569行の自己宣言 posture に反する)
- `dec_or_leaf` は `trigger_name` を allowed に載せて捨てる (DR-136 §2 綴り軸消失)
- いずれも実測

## 関連: R5 m1 (alias分岐の vocab)

alias分岐の vocab も同種の carry 欠落が確認されている (統合報告 P3「decode面の受理して黙って捨てる — 3領域」参照)。

## 追記 (2026-08-17、即修サイクル B5 の副産物): `dec_or_leaf` は `env` を allowlist に載せてすらいない

上の A7 は「allowlist に載せたのに carry 先が無い」形だが、**その逆** — 運ぶべき属性が allowlist に載っていない形 — も同じ経路で見つかった。

`dec_or_leaf` の `allowed` は
`["type","name","id","trigger_name","long","value_name","value","default","export_key"]`
+ installer 所有語彙のみで、**`env` を含まない**。したがって or / seq の leaf には明示 `env` すら書けない:

```
{"options":[{"name":"o","long":true,"seq":[
  {"name":"a","type":"string"},
  {"name":"b","type":"string","env":["O_B"]}]}]}
→ MALFORMED: or branch leaf has unsupported key 'env'   (実測)
```

leaf は値セルを持つ要素なので、DR-049 §1 の env 席を持てないのは非対称 (同型の宣言を positional 群の子に書くと decode は通る)。

**注意**: 仮に allowlist へ `env` を足しても、値源ラダー側が構造子配下の env 席を見ていないため値は入らない — そちらは [nested-env-seat-not-consulted-by-ladder](./2026-08-17-nested-env-seat-not-consulted-by-ladder.md) が扱う。本 issue の射程は decode 面の語彙 (allowlist) の是正まで。

なお B5 の auto_env 修正 (commit `9a3929d3`) は、この allowlist を通さず**プログラム的に**構造子配下の leaf へ env 席を注入している (DR-049 §3 の導出は「値セル持ち要素」に一律で効くため)。宣言経路と導出経路で受理面が食い違っている状態なので、正リスト確認の対象に `env` を明示的に含めること。

## 対処方針

運ぶべき属性の正リストを確認し、allowlist に載せた属性の carry 先が無い形を洗い出す。allowed ⊆ carried の機械検査 (decode時 assert or lint) が再発防止として有効 (統合報告 P3 提案)。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] wire_decode.mbt の `dec_positional` (or分岐) / `dec_or_leaf` / alias分岐 vocab で allowlist に載せた属性の carry 先を洗い出す
- [ ] allowed ⊆ carried を機械検査する仕組み (assert or lint) を導入する
- [ ] `dec_or_leaf` の allowlist に `env` を含めるかを裁定し、宣言経路と auto_env 導出経路の受理面を揃える
