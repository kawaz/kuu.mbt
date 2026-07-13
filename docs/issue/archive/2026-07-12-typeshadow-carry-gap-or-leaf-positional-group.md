---
title: dec_or_leaf の型 shadow 配線が int_round のみ — 未配線 config が 4 つに拡大
status: resolved
category: task
created: 2026-07-12T20:21:51+09:00
last_read:
open_entered: 2026-07-12T20:21:51+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-13T10:21:23+09:00
discard_reason:
pending_reason:
close_reason: ["implemented: dec_or_leaf を dec_positional と同じ TypeShadow 全 7 フィールド carry に一般化 (kuu.mbt commit 77dc81ad)。spec fixture value-typing/or-leaf-factory-config.json (case 1/2/4) が pin、green 確認済み。positional group 側は調査で配線済みと判明し scope から除外済み"]
blocked_by:
origin: 自リポ TODO
---

# dec_or_leaf の型 shadow 配線が int_round のみ — 未配線 config が 4 つに拡大

## 概要

or 分岐 (`dec_or_leaf`) の decode 経路は、`TypeShadow` から `base` と `int_round`
の 2 フィールドしか carry していない。configurable factory で作った型を or 枝に
置くと、その枝だけ config が黙って canonical default に落ちる (エラーは出ない)。

対象コード: `src/core/json_conformance_wbtest.mbt` の `dec_or_leaf` (L2759 付近)。

(参考: 同じ carry gap を疑われていた `dec_positional_group` (L3220 付近) は実地
確認により対象外と判明した — 内側要素は `dec_positional` に再帰委譲されており、
`dec_positional` 自身は TypeShadow の全フィールドを既に carry している。)

## 背景

もともと `allow_base_prefix` (base prefix 許可 int) と `bool_config`
(yes/no 方言 bool) の 2 config が未配線として把握されていた (2026-07-12 朝時点の
保留論点、session state 2026-07-12 §3)。

同日中に DR-099 実装 (kuu.mbt commit 1db55871 系) が入り、`is_tty` /
`tty_stream` / `tty_cygwin` (tty preset) も同じ経路で未配線のまま追加された。
DR-099 の実装 worker は「既存の狭いスコープに合わせた (要求も fixture も無し)」
と明示的に据え置いた、との報告あり。

結果として、この shadow 配線ギャップは未配線 config 2 種類 → 4 種類に拡大した
(base prefix 許可 int / yes-no 方言 bool / tty preset の 3 config、フィールド
単位では is_tty・tty_stream・tty_cygwin を含めて計 4 フィールド相当)。

## 受け入れ条件

- [ ] spec 側に「or 枝 × 方言型 (configurable factory で作った型)」の fixture を
      先行追加する (fixture 先行ルールに従う) —
      `fixtures/value-typing/or-leaf-factory-config.json` として既に追加済み
      (case: bool-dialect-or-leaf-carries-true/false, base-prefix-or-leaf-carries
      が carry gap を pin、bool-dialect-or-leaf-fallback-to-int-branch と
      bool-dialect-direct-option-baseline が対照ケース)
- [ ] `dec_or_leaf` の shadow carry を「base と int_round だけ」から
      「TypeShadow の全フィールド carry」へ一般化
- [ ] 一般化後、上記 fixture の全 case が green になることを確認
- [ ] `allow_base_prefix` / `bool_config` (yes/no 方言) / `is_tty` /
      `tty_stream` / `tty_cygwin` の全てが or 枝内でも config 通りに decode
      されることを確認

## TODO

- [ ] TypeShadow 全フィールド carry への一般化実装 (fixture は追加済みのため
      実装のみ残り)
