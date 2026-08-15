---
title: ref/link/observes/borrow の解決が name 軸のまま — DR-046 §1 の id 軸へ載せ替える
status: open
category: task
created: 2026-08-14T21:29:15+09:00
last_read:
open_entered: 2026-08-14T21:29:15+09:00
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

# ref/link/observes/borrow の解決が name 軸のまま — DR-046 §1 の id 軸へ載せ替える

## 概要

DR-046 §1 は参照 (ref / link、および observes / borrow 系の参照解決) の同定軸を **id 軸** (明示 `id`、無ければ name が供給する = §2) と定めている。しかし現行実装の解決は **name 軸のまま**で、明示 `id` を見ていない。duplicate-name 実装 (commit 74610f73、DR-054 更新 5) で `@engine.ElementDef.id : String?` と `ElementDef::reference_identifier()` という carrier は入ったので、参照解決側をこれに載せ替える作業が残っている。

## 背景

現状の carrier (74610f73 で入った分):

- `src/internal/engine/declaration.mbt`: `ElementDef.id : String?` + `pub fn ElementDef::reference_identifier(Self) -> String` (明示 id > name)
- `src/kuu/wire_decode.mbt`: `dec_reference_id` が dec_option / dec_positional / dd 経路で wire の `"id"` を読む (DR-067 §2 の `#` 予約検査つき)。それ以前は allowed_keys で受理して捨てていた
- 読み手は現状 `collect_duplicate_names` (src/internal/engine/lowering.mbt) のみ

実測 (2026-08-14、上記 commit 時点の実装。probe fixture を KUU_FIXTURES で外挿して観測):

1. **明示 id を link のターゲットに書くと解決しない**
   定義: `{"name":"format","id":"fmt","type":"string","default":"text","long":true}` + `{"name":"json","long":[":set:json"],"link":"fmt"}`
   結果: `definition rejected: json/absent-ref` (id `fmt` は参照先として存在しない扱い)
2. **name で書けば従来どおり解決する**
   同じ定義で `link: "format"` にすると success (`format` へ set(json)@link)
3. **同名 + id 分離のペアへ name で link すると、報告なしに片方へ潰れる**
   定義: `{"name":"x","id":"x1",...,"export_key":"x1"}` + `{"name":"x","id":"x2",...,"export_key":"x2"}` + `{"name":"j","long":[":set:hit"],"link":"x"}`
   結果: success で `effects=[{entity:"x", payload:"set(string:hit)@link"}]` / `result={x2: "hit"}` — 2 つの宣言のうち後者の露出キーへ着地し、曖昧である旨の報告は無い。id で分離された 2 要素が参照解決の面では 1 identity に潰れている
   (この形は duplicate-name では**合法**。DR-054 更新 5 が `fixtures/dd/duplicate-decl.json` を id 分離の合法例として pin しているのと同じ形なので、「宣言としては分離できるのに参照は分離できない」ねじれがそのまま残っている)

## 受け入れ条件

- [ ] ref / link / observes / borrow (default_fn の `borrow:` を含む) の解決が `reference_identifier()` 軸へ載せ替わっている。関係しそうな既存関数: `collect_absent_ref` / `collect_circular_ref` / `collect_link_path_errors` / `collect_absent_link` / `default_fn_edges` (いずれも src/internal/engine/lowering.mbt)
- [ ] entity / binding の keying が宣言名のままでよいかの見極めがついている (現状 effects の `entity` は宣言名。id 軸へ寄せるなら射影側の影響範囲が広い — DR-046 / DR-120 §4 の 3 軸 (綴り / 結果キー / id) の分離をどう写すかの設計判断が要る)
- [ ] 上記実測 3 の「黙って片方へ潰れる」の扱いが決着している (id 軸へ載せ替えた後に正しく分離されるのか、name 参照が曖昧として definition-error になるのか)。spec 側の裁定が必要なら Q を上げる

## 追記 (2026-08-15)

- (a) CMDID-Q1=a により id 軸参加範囲が command まで拡大し、spec fixture 8609393d の command 明示 id 群は carrier/duplicate-id 検査には反映されたが、ref/link 等の解決側は引き続き未対応 (本 issue の対象範囲のまま)
- (b) command alias copy は canonical command と同じ id を保持するため、解決を id 軸へ移す際は alias-copy を `ElementDef.is_alias` 相当で解決候補から除外しないと canonical と copy が ambiguous 化する。載せ替え作業時の注意点として記録

## TODO

<!-- wip 時のみ -->

## 出所

duplicate-name 実装 (DR-054 更新 5) サイクルでの自己申告。統括承認済み (2026-08-14)。
