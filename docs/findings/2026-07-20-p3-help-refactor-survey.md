# P3 help refactor 事前調査 (spec DR-113/DR-114 追随)

調査 revision: kuu.mbt main = 79b54cf7、spec main = a034aa40。実施 2026-07-20、調査 agent = p3-survey (codex-sol-worker)。

## 判明した事実

1. help query 3 commit (ece25364 / 0ba8feb8 / 23a2f002) の導入量は 14 files / +1777 -52。後続 rename/refactor 4 commit は help 部分に semantic change を与えておらず、旧設計コードはほぼそのまま現行 main に残存 (判別可能なまま)。
2. 撤回対象: 独立 help() query (src/kuu/help.mbt:535-641)、旧公開 Help* model (help.mbt:4-90)、runner の旧 help block (json_conformance_test.mbt:1512-1869)、decode-time type:"help" 特殊分岐 (wire_decode.mbt:1696-1725)、Update effect + count 特殊 (engine/value.mbt:251-263 + builtins/installer.mbt:146-152 + resolve.mbt:2244-2270)。
3. 残す (新設計でも有効): 宣言層 snapshot 経路 (installer.mbt:4017-4107 + front_door.mbt:40-46,127-143 — DR-113 §1 が要求する断面そのもの)、HelpMetaDecl 11 語彙 carrier (declaration.mbt:6-18 — DR-113 の表示メタと一致)、installer-owned decode 経路、group declaration の non-entity 扱い (installer.mbt:1016-1024)、stable order/after アルゴリズム (help.mbt:255-470 — 新 fixture でも順序一致を実測確認)、spelling/alias merge (help.mbt:128-226)、filter registry / Reject-Error pipeline。
4. 現行 main に spec 新 fixture を注入した実測: help 19 cases 中 17 mismatch + 3 skip (category_mode 未対応 / help_category unknown-vocab / type shadow help key 未対応)、count profile 5 mismatch (update:increment vs 新 set(N) 期待)。旧 order/after/spelling 系は新 fixture でも順序一致。
5. inheritable copy は is_inheritable=false + link_depth=0 リセットで origin declared_at を復元不能 (installer.mbt:2080-2139)。command alias は clone で独立 command 化し alias marker 消失 (installer.mbt:2609-2617)。origin/provenance は ElemDef への field 追加でなく help_installer の provenance side table / capability snapshot が責務上自然 (実装前の設計判断が要る)。
6. cell_fns / FnCtx / default_fn は現行 source に実装シンボルなし。resolver は declaration-order 2 pass で observes/topological 評価なし (resolve.mbt:2103-2846)。
7. 現行の仕様ズレ: 同名 group declaration が同一設定なら受理 (installer_residents.mbt:1022-1038) — DR-113 §8.1 は無条件 invalid-range で変更対象。

## 実用的な示唆

撤去戦略 = 全削除でなく責務境界で切除 (旧設計の誤りは「query を installer から独立させた」点のみで、宣言層/回収/順序は正しかった)。

マイルストーン (直列必須、M2 が最大):

- M1: universal invocation carrier + cell_fns registry + FnCtx ABI + builtin 10 住人登録 + filter adapter (gate: 既存 filter fixture 不変)
- M2: variant effect {fn,args} 化 + count→incr + default_fn + observes 依存 graph + topological 評価 + 失敗 reason 4 種 + absent-source (gate: count 5 mismatch 解消) — 要 Q14 裁定 (count wire 糖衣)
- M3: help_installer 3 役昇格 (HelpMetaInstaller 拡張、5 preset 植え付け、内部セル、help_on_failure→on_failure、capability 面新設 — InstallerExt/Registry に capability 面が現存しないため trait 拡張要)
- M4: 構造化 help model capability (value_structure/type_ref/types/origin/category_mode/query-error、TypeShadow を表示 tree 保持 carrier へ拡張要 wire_decode.mbt:915-1221)
- M5: runner 追随 + 公開面 mbti + 全 profile lockstep (gate: help 19 fixture 25 case green + 全 regression ゼロ)

## 検証の詳細

上記実測の fresh 出力: `KUU_FIXTURES=spec` の fixtures を注入した `moon test` 結果 = decoded=295 ran_cases=704 skipped=3 mismatches=22、Total tests: 312, passed: 310, failed: 2。mismatch 内訳 = help 17 + count 5。
