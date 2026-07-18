---
title: named bundle による組成 API — 機能単位で複数 registry への登録を 1 名前に束ねる (TRI-Q8 の発展)
status: open
category: design
created: 2026-07-18T17:17:12+09:00
last_read:
open_entered: 2026-07-18T17:17:12+09:00
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

# named bundle による組成 API — 機能単位で複数 registry への登録を 1 名前に束ねる (TRI-Q8 の発展)

## 概要

TRI-Q8 (組成の暗黙 default 是正) の裁定で kawaz が示した bundle 構想の設計サイクル。単なる「組成プリセット」ではなく、**機能 (feature) 単位で複数 registry への登録をまとめる**のが第一目的。

## 背景

### kawaz の構想 (2026-07-18、原文の言語化)

> 「一つの機能を実現するためには type の登録も必要だし filter も必要だし語彙の追加も必要ってパターンは多い。そういうのを number とか help とか complete みたいな名前にまとめるのが一番の目的。レジストリにユーザが 1 個ずつ登録するよりは、その機能の実現に必要な複数レジストリへの登録までをまとめたものを bundle として一つの名前で完結させたい」

- **bundle は再帰的に合成できる** (LList のように単体でも複数まとめても良い): `"kuu_builtins" = ["kuu_number", "flag", "help", "long", "short"]` のようなイメージ
- **一般ユーザが registry を直接触るのは最小にしたい** — bundle 参照が主、registry 個別登録は拡張実装者の低レベル API
- **installer には順序が重要なものもある**ので考慮が必要 (kawaz 注記)
- 背景の懸念 (TRI-Q8 での言語化): 「未指定 = builtins 全部」は暗黙的すぎ、「明示指定」は 1 個足すだけで全量手動再定義の崖。lint ツールの extends (recommended 差分) と同型の解決

### 統括の初期整理

- 機能単位 bundle は textlint/ESLint の preset・plugin パターンと同型で、「number という機能 = number type_parser + in_range filter + 関連語彙」のような**縦割り**が registry 横割りより利用者のメンタルモデルに合う
- **順序問題は小さい可能性**: DR-042 の installer 合成は「順序非依存・冪等」が不変則 (不動点反復) なので、bundle の合成順は原理的には意味を持たないはず。順序が効く箇所 (matcher 優先度等) が実在するかは設計時に全数確認する
- 差分操作 (add / without / override) の語彙と、bundle 名の名前空間 (registry 語彙の ns (DR-094) と揃えるか) が主要設計点
- wire (definitions) に bundle 参照を持ち込むか (定義ファイルから bundle を要求できると capability 宣言と繋がる) は spec 波及の可能性あり — その場合 DR が必要

## 追加検討事項 (kawaz 2026-07-18、2〜3 信目)

1. **installer 順序の実態確認が前提** (kawaz 指摘「順序非依存の認識は古くないか」への実機確認の結果): DR 群 (DR-042/061/070 §1a・§3/DR-110 #7) の規範は一貫して順序非依存を維持しているが、**DR-070 §3 が規定する permutation test (順列検査) が現行 kuu.mbt に実装されていない** (MDR-006 §247 の実装計画に載ったまま未実装)。規範が実機で継続検証されていない状態。bundle 設計の前提タスクとして permutation test を復活させ、順序依存の実在有無を実測で白黒つける — 依存が実在したら bundle 側で吸収せず当該 installer を直す (DR-042「順序依存は不変則違反の徴候」)
2. **bundle はただの配列ではなく、bundle 間の依存関係を含めた構造にすべきか検討** (kawaz): 例えば「complete bundle は help bundle の語彙を前提にする」ような bundle 間依存を宣言できる形 (requires 的なメタ) にするか、フラットな和集合合成 (依存は暗黙、足りなければ unknown-vocab で顕在化) で済ませるか。依存宣言を入れる場合は解決順・循環検出・バージョン概念の要否まで設計範囲になる

## 受け入れ条件

- [ ] **前提: permutation test (DR-070 §3) を kuu.mbt に実装し、installer 順序非依存を実測確認** (依存が出たら当該 installer の修正を先行)
- [ ] bundle の設計プラン (findings) — 単位の粒度 / 再帰合成 / 差分操作 / bundle 間依存の宣言有無 (フラット和集合 vs requires メタ) / registry 低レベル API との 2 層関係 / wire への露出有無
- [ ] BND-Q バッチで裁定
- [ ] 組成 API の実装 (canonical_registry の bundle 化を含む)
- [ ] TRI-Q8 = a の実装 (lower_definition の default 外し) はこの設計と整合する形で行う

## 関連

- docs/findings/2026-07-18-api-surface-triage-table.md (TRI-Q8) / docs/issue/2026-07-18-api-surface-contract-triage.md (親サイクル)
- spec の DR-110 §2-3 (組成は assembly 所有) / DR-042 (installer 合成の順序非依存・冪等) / DR-094 (ns 語彙)
- DR-111 §6 (completer 収載は生成器層と同時 — help/complete bundle の住人設計と連動)
