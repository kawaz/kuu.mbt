---
title: array filter の公開契約に provenance が無く、同値 duplicate 並べ替え・値合成で source 復元が破綻する
status: open
category: design
created: 2026-07-27T08:25:02+09:00
last_read:
open_entered: 2026-07-27T08:25:02+09:00
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

# array filter の公開契約に provenance が無く、同値 duplicate 並べ替え・値合成で source 復元が破綻する

## 概要

DR-122 shadow tree 実装 (2026-07-27) のレビュー残件 (codex-sol-reviewer Major)。
`ArrayFilterDescriptor` の公開契約は任意の `Array[Value] -> Array[Value]` 変換だが、
source 付き経路は出力値を「最初の未使用な同値入力」に対応付けて source を復元している
(`filter.mbt:94-169`, `filter.mbt:219-265`)。この対応付けが以下のケースで破綻する。

1. **同値 duplicate の並べ替え**: 入力 `a(link), a(cli)` を reverse すると、値等価に
   基づく復元では `[link, cli]` と誤報する (実際の座順は `[cli, link]` のはず)。
2. **新しい値を合成する filter**: 通常の result 経路は受理するのに、source 付き経路
   だけ `filter_rejected` として `resolve.mbt:1316` で abort する。
   `output()` は `Result` を返さない設計のため、利用者に回復経路が無い
   (parse/resolve 成功後に突然 abort する最悪の形)。

## 背景

`ArrayFilterDescriptor` の現在のコメントは「arbitrary reordering」を許容する契約を
謳っているが、実装 (値等価ベースの source 復元) はこの契約を満たせていない。
契約と実装が食い違ったまま公開されている状態。

## 受け入れ条件

- [ ] 以下いずれかの方向で契約と実装を一致させる
  - (a) filter が `(Value, Source)` 列を直接変換する契約に変更する
  - (b) filter が出力値と入力 index の対応を返す契約に変更する
  - (c) `AccumulatorExt.collect_sources` と同様の必須 provenance callback を
        `ArrayFilterDescriptor` に持たせる
  - (d) array filter を「安定した部分列抽出・重複除去のみ」に制限して公開契約に明記し、
        登録/実行時検証を追加する (現状の「arbitrary reordering」コメントは撤回)
- [ ] 選んだ方向に応じて `filter.mbt:94-169`, `filter.mbt:219-265`,
      `resolve.mbt:1316` 周辺の実装・コメントを更新
- [ ] 新しい値を合成する filter が source 経路でも abort せず動作する (または、
      そのような filter を許容しない契約であることが登録/実行時に検証される)

## 関連 Minor (同 commit で扱ってよい)

- `registry_wbtest.mbt:107-121` — custom accumulator のダミー実装が
  `collect_sources` で常に `[]` を返しており、新契約に違反する (模範実装として不正)。
- `accumulator_residents_wbtest.mbt:343-418` — DR-080 canonical 表テストが
  テスト内再実装 (`eval_merge_pieces_for_test`) を検証しており、production 経路
  (`merge_accumulator().resolve_cli`) と drift しうる。

## 関連

- `src/extension/filter.mbt`, `src/extension/accumulator_ext.mbt`
- DR-122
- commit `4fdd6abc` のレビュー記録 (codex-sol-reviewer Major)
