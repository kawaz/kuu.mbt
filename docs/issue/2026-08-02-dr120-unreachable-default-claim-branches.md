---
title: DR-120 後に到達不能な default claim 比較分岐を整理する
status: open
category: task
created: 2026-08-02T17:31:31+09:00
last_read:
open_entered: 2026-08-02T17:31:31+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec repo) coverage-analysis 起票
---

# DR-120 後に到達不能な default claim 比較分岐を整理する

## 概要

`src/kuu/resolve.mbt` の `default_claim_values_equal` と、同一 export cell の
equal/unequal candidate 分岐は、DR-120 §1/§6 の「1 結果スコープ・1 露出キー・
1 値セル」制約と構造的 export-key collision 検査により、合法な定義からは
到達しない状態になっている。coverage artifact 30728489791 ではこれが高リスク
wbtest gap と分類されたが、task #127 の規範再照合の結果、test を追加すると
違法な定義を生かしてしまうことになるため見送られた経緯がある。

## 背景

- coverage artifact: 30728489791 (高リスク wbtest gap として検出)
- task #127: 規範再照合の結果、test 追加は違法定義を許容してしまうため見送り
- DR-120 §1/§6: 1 結果スコープ・1 露出キー・1 値セル制約、および構造的
  export-key collision 検査により、当該分岐への到達経路が閉じられている

現行の callers と defense value (= どのような不正入力・想定外状態に対する
防御として書かれたものか) を再確認していない状態。裏取りしてから、
dead code として削除するか、到達不能であることをコード上で invariant として
明示するかを採否判断する必要がある。

## 受け入れ条件

- [ ] `default_claim_values_equal` および同一 export cell の equal/unequal
      candidate 分岐について、現行 callers を洗い出す
- [ ] DR-120 §1/§6 の制約と export-key collision 検査により本当に到達不能か
      裏取りする (実装・型システム両面から確認)
- [ ] 到達不能が確認できた場合: dead code として削除する、または
      到達不能であることを invariant として明示する (assert / コメントでの
      構造説明等) のいずれかを選び適用する
- [ ] 判断の根拠 (削除 or 明示、その理由) を記録する

## TODO

<!-- wip 時のみ -->
