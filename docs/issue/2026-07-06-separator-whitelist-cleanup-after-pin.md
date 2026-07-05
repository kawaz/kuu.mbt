---
title: spec-gaps #10/#9 pin に伴う slice reader の separator whitelist 掃除
status: open
category: task
created: 2026-07-06T08:25:46+09:00
last_read:
open_entered: 2026-07-06T08:25:46+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (spec リポ)
---

# spec-gaps #10/#9 pin に伴う slice reader の separator whitelist 掃除

## 概要

kawaz/kuu の DESIGN §6.3 に「separator は multiple パイプライン成分のみ、standalone
wire フィールドは存在しない / bare separator は仕様概念として存在しない」が pin された
(2026-07-06, spec-gaps 第 1 バッチ ink)。これに伴い、slice 側の JSON reader / lowering に
残っている「蒸留期の暫定受理」を仕様に合わせて掃除する。

## 背景

`docs/DESIGN.md` §6.3 (kawaz/kuu 側):

> separator も §6.2 のパイプライン内にのみ存在する部品であり、multiple を宣言しない
> ノードには separator が無い — **bare separator は仕様概念として存在しない**
> (wire form も separator を multiple object の中にのみ持つ、DR-034/036 /
> schema/wire.schema.json の multiple 詳細形)。

現状の slice reader は、この pin より前の蒸留期の名残で「option/positional 直下に
standalone `"separator"` キーが来ても allowed_keys で弾かない」状態になっている
(= wire では絶対に来ない形を許容し続けている dead な受理)。

## 現状確認 (2026-07-06 時点の grep 結果、着手時に行番号再確認が必要)

1. `poc/json_conformance_wbtest.mbt:623` — `dec_option` の `allowed_keys` リストが
   option 直下の standalone `"separator"` を許容:
   ```
   allowed_keys(
     o,
     [
       "id", "name", "type", "long", "short", "env", "default", "global", "inherit",
       "inheritable", "multiple", "separator", "requires", "conflicts_with", "exclusive_group",
       "export_key", "config_key", "deprecated", "or",
     ],
     "option",
   )
   ```
2. `poc/json_conformance_wbtest.mbt:773` — `dec_positional` の `allowed_keys` リストも
   同様に positional 直下の standalone `"separator"` を許容:
   ```
   allowed_keys(
     o,
     [
       "id", "name", "type", "repeat", "optional", "multiple", "separator", "export_key",
       "config_key", "default",
     ],
     "positional",
   )
   ```
   (対比: `poc/json_conformance_wbtest.mbt:547` の `allowed_keys(o, ["accumulator", "separator"], "multiple")`
   は `multiple` オブジェクト内の詳細形なので pin に合致していて対象外)
3. `poc/installer.mbt:35` — `ElemDef.separator : String?` フィールド自体は lowering 後の
   internal 表現として引き続き必要 (multiple 要素の accumulator 種別選択に使う)。
   現状のコメントは `// the multiple pipeline's separator (DR-034); a value token splits on it`
   のみで、「wire 由来ではなく internal-only」である旨が near-code で明示されていない。
4. `poc/installer.mbt:522` (`ensure_entity` 内) — accumulator 選択の bare-separator 昇格経路:
   ```
   None => if e.separator.is_some() { Some("append") } else { None }
   ```
   これは「repeat 無し かつ e.separator が Some」というケースへの fallback。pin により
   wire 入力では `multiple` 宣言なしに `separator` が来ることはないので、reader 側 (1)(2) を
   仕様通りに閉じれば、この分岐は wire 由来では到達不能になる (dead code 化)。

## 受け入れ条件

- [ ] `poc/json_conformance_wbtest.mbt` の option 用 `allowed_keys` (現 623 行付近) から
      standalone `"separator"` を除去 (= option 直下では受理しない)
- [ ] `poc/json_conformance_wbtest.mbt` の positional 用 `allowed_keys` (現 773 行付近) から
      standalone `"separator"` を除去 (= positional 直下では受理しない)
- [ ] 上記除去後も既存 conformance fixture が全て通ることを確認 (= standalone separator を
      使う fixture が実在するなら、それ自体が spec-gaps 相当の別問題なので要精査)
- [ ] `poc/installer.mbt:35` の `ElemDef.separator` フィールドコメントに
      internal-only (= lowering 後の内部表現、wire の standalone フィールドではない) を明記
- [ ] `poc/installer.mbt:522` 付近の bare-separator accumulator 昇格経路について、
      (a) dead code として除去する、または (b) internal-only 経路として近傍コメントで
      明記する、のいずれかを当事者判断で選び反映

## 発見経緯

spec-gaps #9/#10 分析 + 第 1 バッチ反映レビュー (2026-07-06)。行番号は分析時点の grep
結果であり、着手時に再度 grep して現在位置を確認すること (2026-07-05〜06 に他の gap 修正が
連続して入っており行がずれている可能性が高い)。
