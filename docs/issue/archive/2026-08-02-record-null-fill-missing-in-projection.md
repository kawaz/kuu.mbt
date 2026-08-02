---
title: record 座の null 補形が結果射影層に無い (DR-130 §4 / DR-126 §3)
status: resolved
category: bug
created: 2026-08-02T11:38:36+09:00
last_read:
open_entered: 2026-08-02T11:38:36+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-02T13:44:22+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:W2-7 で build_result が TypeSeat 台帳 (collect_type_seats + apply_export_to_types) 経由で宣言 ValueType を参照し、null_fill_value が record 座の宣言済み欠落フィールドを射影層で null 補形 (multiple 要素の record 含む、parser 出力・Binding 値は不変)","done:sources は align_sources_to_result で result と同型を維持","pin:src/kuu/value_seat_wbtest.mbt","pin:src/kuu/output_contract_wbtest.mbt (期待値更新済み)"]
blocked_by:
origin: W2-5 実装中に露出
---

# record 座の null 補形が結果射影層に無い (DR-130 §4 / DR-126 §3)

## 概要

DR-130 §4 の射影表は record を「**内側も反転** — closed な語彙なので全フィールド列挙 + `null`」と規定し、
DR-126 §3 も「結果射影では宣言済みフィールドをすべて列挙し、値が確定しない座を `null` にする。type
パーサの生出力は宣言済みフィールドを省略してよく、**射影層が不足フィールドを `null` で補う**」と規定して
いる。この補形が kuu.mbt に実装されていない。

## 背景

**現象 (実測 2026-08-02、W2-5 実装中に露出)**

再現は `src/kuu/output_contract_wbtest.mbt` の test
`"宣言済みキーの欠落は正常 (DR-126 §4 (c), DR-130 §4.1)"`。`{"record": {"since": "number", "until":
"number"}}` を名乗る type resident が `{"since": 1}` だけを返したとき、現行の result は
`{span={since=1}}` で、宣言済みの `until` が `null` として現れない。規範どおりなら
`{span={since=1,until=null}}` になるはず。同 wbtest は**現状の挙動をそのまま pin している**ので、
補形を入れる際は期待値を更新すること。

**なぜ今まで見えなかったか**

record を名乗る住人が 1 つも存在しなかったため。DR-130 の実装段 (結果射影の全列挙化) は産出者が居ない
状態で行われており、表の record 行だけ実装機会が無かった。W2-5 で `TypeExt` の複合産出が通ったことで
初めて観測可能になった。

**実装上の障害 (これが本 issue の中身)**

補形の判定には「その座の**宣言された** ValueType」が要るが、結果射影 (`src/kuu/resolve.mbt` の
`build_result`) は宣言型を受け取っていない。`build_result` が持つのは `binds` (Binding — 値だけで型を
持たない) / `cells` (AccumCell) / `defaults` (DefaultCell) / `nones` (InternalCell) / `shape`
(ExportScopeMap) で、要素の `ElemDef.ty` へ辿る経路が無い。したがって「1 行足す」形の修正にはならず、
`(path, key) -> ValueType` を引ける第 5 のセル台帳を通すか、既存台帳のどれかに型を載せるかの設計判断が
要る。

## 受け入れ条件

- [ ] 結果射影層 (`src/kuu/resolve.mbt` の `build_result` 系) が record 座の宣言 ValueType を参照できる
      経路を持つ (新台帳追加 or 既存台帳への型付与、いずれかの設計判断込み)
- [ ] record を名乗る住人が宣言済みフィールドを省略して返したとき、射影後の result にそのフィールドが
      `null` として補われる (`src/kuu/output_contract_wbtest.mbt` の該当 test を新規範に更新)
- [ ] `{"array": {"record": ...}}` / `{"map": {"record": ...}}` / union 内の record など、宣言
      ValueType の中に現れる record 座すべてが対象になる (トップレベル record だけの対処にしない)
- [ ] type パーサの戻り値 / Binding の値そのものは書き換えない (DR-130 §4.1 の分離を守る、DR-126 §4 の
      乖離検査が生出力を見られる状態を保つ)
- [ ] 補形した座の sources (shadow tree) 側の扱いを決めて実装する (DR-122 §1 の「sources は result と
      同型」を保つ)

## 設計上の注意点 (先に潰すべき論点)

- 補形は**トップの record だけでは足りない**。宣言 ValueType の中に現れる record 座すべてが対象になる
  ため、補形は「値 × 宣言 ValueType × Registry」を歩く再帰関数になり、**W2-5 で入れた乖離検査
  (`src/extension/output_contract.mbt` の `value_type_breach`) と同じ形の走査**になる。両者を同じ walk
  の 2 つの用途として書くか、別々に書くかは実装時に判断すること
- DR-130 §4.1 は「**type パーサの出力そのものは書き換えない**」と明示している。補形は射影の段でのみ
  行い、`parse_token` の戻り値や Binding の値を書き換えてはならない (書き換えると DR-126 §4 の乖離検査が
  生出力を見られなくなる)
- 補形後の `null` の sources タグをどうするかも決める必要がある。W2-5 で入れた `value_source_shadow`
  (`src/kuu/resolve.mbt`) はセル値の構造をそのまま写すので、補形した座は shadow 側に対応する座を持たない。
  DR-122 §1 の「sources は result と同型」を保つなら shadow 側にも同じ座が要る

## 関連

- spec `docs/decisions/DR-130-null-result-projection.md` §4 の射影表 record 行 / §4.1
- spec `docs/decisions/DR-126-descriptor-record-value-type.md` §3
- kuu.mbt `src/kuu/output_contract_wbtest.mbt` (現状挙動の pin)
- kuu.mbt `src/extension/output_contract.mbt` (同型の走査)
- kuu.mbt `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 (W2-6 / W2-7 が値空間降下で
  同じ宣言型を要るので、台帳の通し方はそちらと揃えるのが自然)
