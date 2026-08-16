---
title: command 退出後に親 scope で立った Held/Pending の path へ退出済み command 名が prepend される
status: open
category: bug
created: 2026-08-16T14:46:17+09:00
last_read:
open_entered: 2026-08-16T14:46:17+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー A4 (R2-1) / 即修サイクルで着手・撤回
---

# command 退出後に親 scope で立った Held/Pending の path へ退出済み command 名が prepend される

## 概要

`step_greedy` の `CommandSatisfied` arm が、子 scope の評価から返る枝の path へ
`nest_path(name, ...)` を**無条件に**適用している。子の継続 (`KNest` → 親の
`KResumeScope`) は同じ呼び出しから返るため、**command を抜けた後に親 scope で立った**
Held / Pending にも退出済みの command 名が積まれ、帰属が 1 段深くずれる。

DR-066 §4 は候補・Held の path を「**発火時の動的パス**」と定めており、親 scope で発火した
診断に子の名前が付くのは規定違反。

## 再現 (実測)

```json
{"commands":[{"type":"command","name":"sub"}],
 "positionals":[{"name":"tail","type":"string"}]}
```
```
args: ["sub"]
  got  errors = {tail@1/parse/missing_operand, path=["sub"]}
  want errors = {tail@1/parse/missing_operand, path=[]}
```
`sub` は退出済みで、starve したのは root の `tail` なので path は `[]` が正。

## 試して外した判別 (撤回済み、回帰 10 件)

`KNest` が子の終わりで `{}` マーカーを積んでから親の継続へ進むことを使い、
「マーカーを持つ枝 = 既に子を出た後」と判別して prepend を抑止した。**これは誤り**で、
以下 10 件が回帰した:

- `command-scope/global-missing-operand-path` の 2 case (path が重複して `|` と `|a` の両方が出る)
- `constraints-parse/required-group-scope-boundary` の 3 case
  (`required_group_violated|child_a` が `|` になる)
- `failure-actions/tried-triggers-scope` ほか

**原因**: KTop で評価される **constraint 違反も子のマーカーを持つ**が、そちらは prepend が
必要である。「マーカーの有無」は「どこで発火したか」と一致しない。

## 難所

統合報告の方針「nest 適用を child 内発火 branch に限定」は正しいが、**判別手段が自明でない**:

- 子の内部で発火した枝は `KNest` に到達せずに `scope_step` から直接返る
- 親再開後の枝は `KNest` → `run_cont(outer, ...)` を経て返る
- どちらも同じ `scope_step(child, ..., kk)` の戻り値として混ざる
- 位置 (`pos`) でもマーカーでも区別できない (上記実測)

構造的な解決案は「子の評価と親の再開を 2 相に分ける」ことだが、`kk` (継続) が
取り分選好の oracle (`has_full_k`) を兼ねているため、CPS の組み替えは選好の意味論に
波及する。設計判断を伴うので即修から外す。

## 受け入れ条件

- [ ] 子 scope 内で発火した診断だけに command 名が積まれる (親再開後の診断には積まれない)
- [ ] 上記の再現ケースが `path=[]` になる
- [ ] 回帰した 10 件 (`global-missing-operand-path` / `required-group-scope-boundary` /
      `tried-triggers-scope` ほか) がすべて green のまま
- [ ] 判別手段が「マーカーの有無」以外の、発火位置に基づくものになっている

## 関連

- 統合報告 A4 (R2-1)。同報告の D7 (テスト網羅の死角) に「親再開後 path の fixture 不在」が
  挙がっており、本件が未検出だった直接原因として記録されている
