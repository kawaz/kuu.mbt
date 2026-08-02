---
title: flat 側の Unset=>Default 読み替えが tree 側に無い
status: resolved
category: design
created: 2026-07-26T13:23:40+09:00
last_read:
open_entered: 2026-07-26T13:23:40+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-03T05:05:07+09:00
discard_reason:
pending_reason:
close_reason: ["done:commit f15f05 の sources 射影一本化で解消 — result_sources/source_seats の1経路に統合、Unset→Default arm も削除済み (v0.0.24 再実測、has_commands/collect_sources_flat/collect_sources_tree は rg 0 件)"]
blocked_by:
origin: 自リポ TODO
---

# flat 側の Unset=>Default 読み替えが tree 側に無い

## 概要

`collect_sources_flat` (`src/kuu/resolve.mbt`) は binding の `source` が
`@abi.Unset` の場合、`@abi.Default` に読み替えて `sources` へ出す。
`collect_sources_tree` は `b.source` を素通しするだけで、この読み替えを
行わない。両経路とも「未発火セル (default 由来)」の値源表示自体は一致する
(先行 issue `2026-07-25-sources-projection-skips-export-key-under-commands`
の修正で 0 回発火 accum セルの表示は揃えた) が、根拠となる読み替えロジックが
flat 側にしかないまま個別対応で数字を合わせている状態。

## 背景

`collect_sources_flat` と `collect_sources_tree` の分岐そのものの統廃合は
別 issue `2026-07-26-unify-flat-tree-sources-projection` で検討中だが、
そちらは「未発火セルの default フォールバック」(accum セル向けの個別対応) と
「path を常に `[]` にする挙動」を扱っており、本 issue が指す
`@abi.Unset => @abi.Default` の読み替えロジックそのものの有無の差分とは
別の切り口。

## 該当箇所

- `src/kuu/resolve.mbt` の `collect_sources_flat` (`@abi.Unset =>
  Some(@abi.Default)` の読み替え箇所)
- `src/kuu/resolve.mbt` の `collect_sources_tree` (`b.source` を素通しする箇所)

## 論点

この読み替えは spec DR-045 の「as if untouched」(未操作であるかのように
扱う) 意味論を `sources` にどう反映するかの設計判断であり、
「command 木経路でも export_key を適用する」というキー体系の話
(先行 issue の主題) とは軸が違う。tree 経路で `b.source` が実際に
`@abi.Unset` を持ちうるケースの洗い出しと、flat 側の読み替えロジックを
共通化すべきか個別に判断すべきかを検討する必要がある。

## 受け入れ条件

- [ ] tree 経路で `b.source == @abi.Unset` が実際に発生するケースを洗い出す
- [ ] DR-045「as if untouched」の意味論を sources にどう出すか方針を決める
- [ ] 方針に応じて flat/tree のロジックを統一する、または意図的差異として
      doc コメントに明記する

## 関連

- 先行 issue: `docs/issue/archive/2026-07-25-sources-projection-skips-export-key-under-commands.md`
  (sources 射影の export_key バグ修正元、本 issue はそこからの切り出し)
- 関連 issue: `docs/issue/2026-07-26-unify-flat-tree-sources-projection.md`
  (has_commands 分岐の統廃合を扱う別軸の issue)
- spec DR-045 (as if untouched の意味論)
