---
title: 不動点収束の判定が tree_size のみ — サイズ不変の in-place 書き換えを検出できない
status: open
category: design
created: 2026-07-25T16:53:44+09:00
last_read:
open_entered: 2026-07-25T16:53:44+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 自リポ TODO
---

# 不動点収束の判定が tree_size のみ — サイズ不変の in-place 書き換えを検出できない

## 概要

`src/internal/engine/installer_ext.mbt` の `run_installer_fixpoint` は

```
let before = root.tree_size()
installer_tree_pass(...)
if root.tree_size() == before { break }
```

という形で不動点収束を判定している (2026-07-25 実物確認)。この構造の帰結として:

- (良い面) 最後の 1 パスは必ず「収束済みツリーに全 installer を適用して何も増えない」ことを確認しており、全 fixture の全 lowering が毎回 add-if-absent (DR-042 不変則①) を踏んでいる
- (穴) 収束判定が件数のみなので、**ツリーのサイズを変えない in-place 書き換え**があっても検出できない。DR-042 不変則② は「他 installer の lowered 産物を書き換えない・読んで反応しない」を要求しているが、この検査ではサイズ不変の書き換えを取りこぼす

## 背景

installer 順列 property test (commit a809bed8 / push 済み f7e9f3d9) を入れる過程で判明した残存ギャップ。

外部からの冪等検査 (同じ installer を 2 回並べた鎖 `order ++ order` で結果不変を見る) は不変則③ の所有語彙交差禁止に阻まれて不可能であることを実測済み (`installer_ext.mbt:364` の `collect_installer_vocab_errors` が `VocabIntersection` を返す)。

塞ぐなら計装が要り、経路は 2 つ:

- (a) `vocab()` を空で返し apply/decode だけ内側 installer に委譲する shadow installer を鎖に足す — 不変則③ を侵さずに apply_steps だけ二重化できる
- (b) `@engine.InstallerPlan::new` を直接組んで apply_steps だけ二重化する — ただし parse_definition の decode 経路 (definitions/types/templates/help_types stamping) を wbtest 側に複製する必要があり drift 源になる

worker 推奨は (a)。

優先度は高くない (現時点で不変則② 違反の実例は未発見、8 seed × 320 fixture のランダム順列検査で反例ゼロ) が、順序非依存の保証を厚くするなら次の一手。

## 受け入れ条件

- [ ] (a)/(b) いずれかの計装方式を裁定
- [ ] サイズ不変 in-place 書き換えを検出する検査を追加
- [ ] 追加検査を既存 8 seed × 320 fixture の順列検査に組み込み green 確認

## 関連

- `src/internal/engine/installer_ext.mbt` (`run_installer_fixpoint`, `collect_installer_vocab_errors` @ 364)
- spec の DR-042 (installer 不変則①②③)
- commit a809bed8 (installer 順列 property test 導入, push 済み f7e9f3d9)
