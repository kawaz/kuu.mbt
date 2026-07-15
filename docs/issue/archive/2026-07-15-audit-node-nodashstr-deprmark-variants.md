---
title: Node enum の NoDashStr/DeprMark variant がどこからも構築されていない疑い
status: resolved
category: idea (要確認)
created: 2026-07-15T01:08:09+09:00
last_read:
open_entered: 2026-07-15T01:08:09+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-15T15:15:33+09:00
discard_reason:
pending_reason:
close_reason: ["dr/DR-041","dr/DR-058","dr/DR-085","implemented"]
blocked_by:
origin: kuu spec session (kuu-core API 整理作業中の副次発見, 2026-07-15)
---

# Node enum の NoDashStr/DeprMark variant がどこからも構築されていない疑い

## 概要

kuu-core API 整理作業 (可視性キュレーション後のコンパイラ到達可能性解析) 中の
副次発見として、Node enum の `NoDashStr` / `DeprMark` variant がどこからも
構築されていない疑いが浮上した。

`DeprMark` はコメントで「long installer が lowering する」旨の記載があるが、
`installer.mbt` に実際の構築コードが見当たらない。`NoDashStr` も同様に
構築箇所が未確認。

以下いずれかの裁定が必要:

1. **実装漏れ**: spec 側の対応規定 (DR-058 deprecated の lowering 断面 等)
   に fixture 要求があるにも関わらず未実装 → 実装するか、統括へ報告
2. **廃止済み概念の残骸**: spec の lowering fixture に該当断面が既に無い
   → variant を削除

## 背景

「設計済みなのに未実装」の双方向チェック案件。一般的な CLI 実装の常識で
判断せず、spec 正本 (kawaz/kuu リポの DR / LOWERING ドキュメント) から
導出して裁定すること。

- `DeprMark`: コメント上は long installer による lowering 対象と記載
  → `installer.mbt` を grep しても構築コードが見当たらない
- `NoDashStr`: spec 対応物の有無を未確認 (DR-058 deprecated 断面との
  突き合わせが必要)

## 受け入れ条件

- [ ] `NoDashStr` / `DeprMark` それぞれについて、kuu.mbt 全体 (installer.mbt
      含む) を grep して構築箇所の有無を確定する
- [ ] spec 側 (kawaz/kuu の DR-058 および関連 LOWERING ドキュメント) を読み、
      各 variant に対応する lowering fixture / 規定の有無を確認する
- [ ] 上記 2 点の突き合わせ結果から (1) 実装漏れ / (2) 廃止済み残骸 の
      いずれかを裁定する
- [ ] (1) の場合: fixture 要求の有無を確認した上で実装するか、統括へ報告する
- [ ] (2) の場合: 削除して良いことを spec 側の lowering fixture 不在で
      確認してから variant を削除する

## TODO

<!-- wip 時のみ -->
