---
title: kuu-core API の整理 — conformance エンジンから正面玄関のあるライブラリへ
status: resolved
category: task
created: 2026-07-14T23:04:26+09:00
last_read:
open_entered: 2026-07-14T23:04:26+09:00
wip_entered: 2026-07-15T00:22:41+09:00
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-15T01:10:24+09:00
discard_reason:
pending_reason:
close_reason: ["dr/MDR-005","implemented","done: parse_definition(Json)->Result[AtomicAST,DefLoadError] / parse(ast,args)->Outcome / complete(ast,args_before,args_after?)->Array[Cand] の 3 関数を front_door.mbt に新設 (AtomicAST は不透明ハンドル、DefLoadError は Malformed/Rejected の 2 層)","done: wire decode を json_conformance_wbtest.mbt から wire_decode.mbt へ昇格、conformance runner が production decoder をドッグフーディング","done: 公開面キュレーション — 利用者向け 18 型は pub(all) 維持、内部 41 型は pub 格下げ (フィールド非公開)","done: パッケージ分割は不要と判明 (単一パッケージ + pub 調整で成立、MDR-005 に記録)","done: 観測不変確認 — conformance 263/644/0/0・moon test 327/327 がベースラインと完全一致、moon check --deny-warn クリーン","done: push 済み (main 24bbd18a)、CI run 29348271974 green","derived:audit-node-nodashstr-deprmark-variants"]
blocked_by:
origin: kuu spec session (kawaz 承認 2026-07-14 r14)
---

# kuu-core API の整理 — conformance エンジンから正面玄関のあるライブラリへ

## 概要

現状の kuu.mbt (`src/core/`) は conformance 駆動の参照エンジンで、公開面が
エンジン内部型の全開 `pub(all)` (Node/Scope/Entity/Matcher/LongEntry/
Constraint/RVal 等) + `parse_definition`/`parse`/`complete`/`build_result` に
なっている。wire JSON の decoder が `src/core/json_conformance_wbtest.mbt`
(テストファイル) 内に居り、「JSON 定義を読み込んで parse する」正面玄関が
プロダクションコードに存在しない。

この issue は、この状態を **エンジンとしては再設計せず (= fixture 263 本が
保証する挙動はそのまま)、正面玄関のあるライブラリとして再包装する** 作業を
まとめる。

## 背景

kuu.mbt は conformance corpus を通す実装として育ってきたため、内部型が
そのまま公開面に露出している。他パッケージ (kuu-ux 等) や外部利用者が
kuu-core を使う入口が明文化されておらず、wire decode もテストコードに
埋まっている。kawaz 承認 (2026-07-14 r14) により、以下 3 点を実施した上で
kuu-core/kuu-ux の別パッケージ分割を判断する運びとなった。

## 受け入れ条件

- [ ] wire decode (`json_conformance_wbtest.mbt` 内の JSON decoder) を
      wbtest からプロダクションモジュールへ昇格する (最大項目)
- [ ] 公開面のキュレーション: spec 語彙に対応する型だけ公開し、内部型
      (Node/Scope/Entity/Matcher/LongEntry/Constraint/RVal 等、外部利用に
      不要なもの) を private 化する
- [ ] 入口の正準化: `parse_definition` → `parse`/`complete` → outcome の
      経路を spec 語彙 (args/candidates/errors) で揃える
- [ ] 既存 fixture 263 本が再包装後も全て green (= エンジン挙動の再設計では
      ないことの確認)

## TODO

<!-- wip 時のみ -->
