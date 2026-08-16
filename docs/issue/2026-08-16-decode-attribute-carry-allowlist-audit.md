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

## 対処方針

運ぶべき属性の正リストを確認し、allowlist に載せた属性の carry 先が無い形を洗い出す。allowed ⊆ carried の機械検査 (decode時 assert or lint) が再発防止として有効 (統合報告 P3 提案)。

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)

## 受け入れ条件

- [ ] wire_decode.mbt の `dec_positional` (or分岐) / `dec_or_leaf` / alias分岐 vocab で allowlist に載せた属性の carry 先を洗い出す
- [ ] allowed ⊆ carried を機械検査する仕組み (assert or lint) を導入する
