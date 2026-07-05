---
title: lowering の entity 生成が spec 乖離 (2 症状) — dd の options[] 配置で余分な entity 生成 / global 子スコープの verbose entity 誤生成
status: open
category: bug
created: 2026-07-05T15:51:45+09:00
last_read:
open_entered: 2026-07-05T15:51:45+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (fixtures/lowering golden fixture 量産, 2026-07-05)
---

# lowering の entity 生成が spec 乖離 (2 症状) — dd の options[] 配置で余分な entity 生成 / global 子スコープの verbose entity 誤生成

## 概要

`kawaz/kuu` の fixtures/lowering golden fixture 量産 (2026-07-05) での写像実測により、
lowering の entity 生成に spec 乖離が 2 件見つかった。

1. **dd の options[] 配置で余分な entity が生成される**: `ensure_entities`
   (`installer.mbt:372-380` 付近) の options ループには dd を除外する
   `not_dd` ガードが無い (positionals ループには存在する)。このため dd を
   `def.options[]` に配置すると `{name: "--", ty: TStr}` という余分な実体が
   生成される。LOWERING §B.4「dd は値なし」に違反し、かつ配置依存
   (positionals 配置では発生しない) という点で DR-064 §2 (dd は配置不問で
   扱われるべき) にも反する。
2. **global の子スコープに自前の verbose entity が生成される**: Rooted 衛星
   は root セルへ link 同期する設計のため、子スコープ側に独自の verbose
   entity は不要なはずだが、実際には子スコープに生成されてしまう。

## 背景

`kawaz/kuu` の fixtures/lowering golden fixture (2026-07-05 量産分) を slice
の lowering 実装と突き合わせた写像実測で検出。

症状 (1) は、既に修正済みの `inst_dd` 両面走査
(`docs/issue/2026-07-05-dd-placement-agnostic-collection.md`) と同族の
残骸。install 側 (`inst_dd`) は options/positionals 両方を走査するよう
直ったが、`ensure_entities` 側の options ループには dd 除外ガードが
反映されていない。

症状 (2) は `kawaz/kuu` の `fixtures/lowering/global/with-long.json` の
golden で「子 entities 空」が仕様準拠値として示されている
(= root セルへの link 同期で足りるため子側の entity 生成は不要)。

両症状とも `kawaz/kuu` の DR-070 §1b 既知 gap 台帳 (4/5 番目の項目) に
記録済みで、golden fixture 側の値は spec 準拠として確定している
(= fixture 側の記述ミスではなく slice 実装側の gap)。

修正時は fixture runner の lower 対応 (現状未実装) が揃えば、この 2 症状を
自動検証できる形になる見込み。

一次資料:

- `kawaz/kuu` の `fixtures/lowering/dd/basic.json` (why コメント)
- `kawaz/kuu` の `fixtures/lowering/global/with-long.json` (why コメント、
  子 entities 空が仕様準拠値であることの根拠)
- `kawaz/kuu` の `docs/decisions/DR-064` §2 (dd は配置不問で回収)
- `kawaz/kuu` の `LOWERING` 仕様 §B.4 (dd は値なし) / §B.6
- `kawaz/kuu` の `docs/decisions/DR-070` §1b (既知 gap 台帳、本件は 4/5 番目)
- slice の `installer.mbt:372-380` 付近 (`ensure_entities` の options ループ、
  not_dd ガード欠如箇所)

裏取りが前提: この issue は他プロジェクト (kawaz/kuu) 側からのフラグ提示で
あり、具体的な修正方針は slice 側で一次資料を確認した上で判断すること。

## 受け入れ条件

- [x] `ensure_entities` の options ループに `not_dd` ガードを追加し、dd の
      options[] 配置で余分な entity `{name: "--", ty: TStr}` が生成されない
      ことを確認する (installer.mbt `ensure_entities` + phase29
      "gap4 DR-064 §2" で options[]/positionals[] 両配置とも `--` 実体なし・
      lowered 形同一を固定)
- [x] global の子スコープで自前の verbose entity が生成されないことを確認する
      (`kawaz/kuu` の `fixtures/lowering/global/with-long.json` 相当の
      ケースで子 entities が空になる) — `!is_link` ガード + phase29 "gap5" で
      子スコープ entity 非生成・観測挙動 `build:{}` 不変を固定
- [x] fixture runner の lower 対応実装後、`kawaz/kuu` の
      `fixtures/lowering/dd/*.json` および `fixtures/lowering/global/*.json`
      で両症状が再発しないことを回帰確認する (lower モード runner
      `lower_runner_wbtest.mbt` が 18/18 全 PASS の green gate として成立。
      dd/basic fixture が options[] 配置の dd で `--` entity 非生成を、
      global/with-long fixture が子スコープ verbose entity 非生成を、それぞれ
      lower golden で回帰固定)

## TODO

<!-- wip 時のみ -->
