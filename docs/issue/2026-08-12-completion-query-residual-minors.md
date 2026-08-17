---
title: completion_query の残 Minor — fire_path 純度 pin / emit 畳みキーの取りこぼし (RE-3・RE-6、RE-4 は解消済み)
status: open
category: design
created: 2026-08-12T11:35:28+09:00
last_read:
open_entered: 2026-08-12T11:35:28+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ)
---

# completion_query の残 Minor 3 件 — fire_path 純度 pin / merge ペアキーの scope 欠落 / emit 畳みキーの取りこぼし (RE-3・RE-4・RE-6)

## 概要

DR-116 実装サイクル (commit 041de8fd〜6c54a0ae) の fable レビューで挙がった Minor 3 件。総合判定は push 可で、3 件とも次サイクル送り。希少度が高いか fail-closed なので急がない。

## 背景

### RE-3: seq / repeat 内部で starve した候補の fire_path 純度に pin が無い

M4 (commit f6a6dc3d) は候補の帰属 scope を DR-066 §4 の fire_path に載せ替えたが、seq / repeat の内部で値スロットが starve した候補について「fire_path が walk 位置を正しく保つ」ことを固定する test が無い。破れた場合は帰属 scope が浅い側へずれ、help model 照合が外れて説明なし・素材順に落ちる = fail-closed (誤った説明が付くのではなく付かなくなる) なので実害は小さいが、劣化を黙認する状態。src/internal/engine/eval.mbt の nest_cands が fire_path を無条件 prepend する規約 (同ファイルの doc comment 参照) が seq / repeat 経路でも保たれるかを test で押さえたい。

### RE-4: merge_insert_form のペアキーに scope が無い

src/kuu/completion_query.mbt の merge_insert_form は word_end / cont のペア判定キーを (origin, spelling) の組にしている (M5、commit 18eedb0f)。ここに帰属 scope が入っていないため、曖昧読みで root と child に同名要素が併存し、かつ insert_form="eq" という極端ケースで、別 scope の候補どうしが誤ってペア扱いされ片方が畳み消される可能性がある。塞ぎ方は明快で、同ファイルに既にある scope_key(candidate.scope) をペアキーへ足すだけ。ただし誤畳みが実際に起きる definition を組めるかは未確認なので、再現 definition を作って RED を出してから直すのが正順。

## 更新 (2026-08-17、全コードレビュー棚卸し): RE-4 は解消済み

RE-4 が指定した塞ぎ方 (「同ファイルに既にある `scope_key(candidate.scope)` をペアキーへ足すだけ」)
は**現コードで実装済み** (2026-08-17 実測):

```
fn pair_identity_key(s : ScopedCandidate) -> String {
  scope_key(s.scope) + s.candidate.origin + "\u{001f}" + s.candidate.spelling
}
```
(`src/kuu/completion_query.mbt:460-462`)

帰属 scope がペアキーの先頭に入っているので、別 scope の同名候補が誤ってペア扱いされることは無い。
**RE-4 は受け入れ条件を満たしており、残るのは RE-3 と RE-6 の 2 件**。

### RE-6 の未記録の面 (2026-08-17 追記)

RE-6 には、当初の記述に無い**もう 1 つの壊れ方**がある。`collapse_duplicate_rows` の畳みは
`keys[found] + "="` を作る (`completion_query.mbt:439`) ので、`keys[found]` が既に `=` 終端
(literal exact `--x=` が先に来た場合) だと **`--x==` という存在しない綴り**を emit する。

また当初の記述は「畳み後の行に**後続**行が当たる」向きしか見ていないが、逆順 —
先に `--x=` 行 (§5 ペア成立由来) が入り、後から別 origin の `--x` word_end/cont が畳まれて
`--x=` になる — でも表示上同一の行が 2 本残る。塞ぐときは両向き + `=` 二重付与の 3 つを
まとめて見ること。

### RE-6: emit 畳みの突き合わせキーが「畳み前の挿入文字列」

collapse_duplicate_rows (commit 6c54a0ae) は元の挿入文字列を keys 配列で保持して突き合わせるが、畳みの結果 spelling が書き換わっても keys[found] を更新しない。このため insert_form="eq" で、DR-117 §5 のペア成立により最初から `--mode=` として emit された行 (key="--mode=") と、or ブランチ畳みで `--mode` から `--mode=` へ変わった行 (key="--mode") が併存すると、表示上同一の `--mode=` が 2 行残る。成立には同一綴りの別 option 2 本 (export_key リネームが要る) + insert_form="eq" が要るので希少度は RE-4 と同クラス。塞ぎ方の一案: collapse を最終表示綴りキーでもう 1 周する、または fold 後に keys[found] を更新する 1 行。どちらが素直かは実装時に判断。

fable が 6c54a0ae 自体は検証済みで「裁定・実装とも妥当」判定なので、RE-6 は既存実装の否定ではなく退化構成の取りこぼしの記録。

## 受け入れ条件

- [ ] RE-3: seq / repeat 内部で starve した候補の fire_path 純度を pin する test を追加
- [x] RE-4: merge_insert_form のペアキーに scope を追加 — **解消済み** (`pair_identity_key` が `scope_key` を含む、2026-08-17 実測)
- [ ] RE-6: emit 畳みキーの取りこぼし (畳み後 spelling 未更新 / 逆順 / `=` 二重付与の 3 面) を修正、または再現不能を確認

## TODO

<!-- wip 時のみ -->
