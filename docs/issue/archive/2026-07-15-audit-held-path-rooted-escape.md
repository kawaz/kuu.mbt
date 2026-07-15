---
title: Held.path にも Rooted escape 未対応の疑い (Cand.path と同種の構造的欠落の可能性)
status: resolved
category: idea
created: 2026-07-15T11:37:35+09:00
last_read: 2026-07-15T13:45:03+09:00
open_entered: 2026-07-15T11:37:35+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-15T15:19:27+09:00
discard_reason:
pending_reason:
close_reason: ["not-applicable: DR-066 §4 は発火時の動的パス (walk 位置基準) を規範化しており、Held.path の無条件 prepend (nest_path、コピー先 scope 基準) は仕様通り。escape させるとむしろ DR-066 §4 に反する", "not-applicable: Cand.link の escape は complete_tree の (path, origin) キー lookup という complete() 固有の内部要請 (node.mbt:710 purely an implementation detail、DR-104 §2 で path は wire 非搭載)。ParseError.path (wire 上の仕様フィールド) とは意味論が別物で横展開の前提が成立しない", "not-applicable: 実機実証 2026-07-15、global option (number, global:true) を子 command a に持つ定義で [\"a\",\"--level\",\"notanumber\"] → path=[\"a\"] (コピー先 scope 基準) を KUU_FIXTURES 注入で確認、path=[] 期待の対照実験は不一致。構造の類似性からの疑いは実証の結果否定された", "note: 調査中に Pending→ParseError 変換経路の path 非対称を副次発見、本 issue のスコープ外のため別途 issue 起票で追跡"]
blocked_by:
origin: kuu.mbt completer 実装セッション (副次発見, 2026-07-15)
---

# Held.path にも Rooted escape 未対応の疑い (Cand.path と同種の構造的欠落の可能性)

## 概要

completer 実装中の副次発見として、`Held.path` (`ParseError.path`) にも
`Cand.path` で見つかったのと同種の Rooted escape 未対応が理論上残っている
可能性がある。未調査・未着手。

## 背景

`Cand.path` は `nest_cands` が無条件 prepend していたため、global option
(Rooted 衛星) の候補 path が「コピー先の子 scope」になり、宣言元 Entity と
食い違う潜在バグがあった。`Cand.link` (Rooted-escape カウンタ、`Binding.link`
と同ロジック) の新設で修正済み (completer 配線 commit 参照)。

同じ「無条件 prepend で子 scope に潜り込む」構造が `Held.path` にも存在する
なら、同じ escape 欠落バグが理論上起こりうる。ただし `Held.path` 側は
今回未調査・未変更 — 構造の類似性からの推測であって実証はしていない。

## 受け入れ条件

- [x] global option の値エラー (filter reject 等) が子 command scope 内で
      発生した場合の error path/element 帰属について、spec 期待
      (DR-066 §4) と実装の現状を突き合わせる
- [x] ズレが実証された場合: `Binding.link` / `Cand.link` と同じ Rooted-escape
      ロジックを `Held.path` 側にも配線する — **ズレなし、対象外**
- [x] 修正した場合: spec fixture でその挙動を pin する — **対象外 (修正なし)**
- [x] ズレが無いと確認できた場合: 「該当なし」の根拠 (= なぜ escape が
      不要か) を本 issue に追記して close する — 以下「調査結果」節に記載

## 調査結果 (裁定: ズレなし、escape 配線は不要)

1. **DR-066 §4 の規範は「発火時の動的パス」**: `docs/decisions/DR-066-error-reason-codes.md`
   §4 は「値は発火時の動的パス — link/ref 共有で 1 つの派生ノードが複数の
   ユーザパスに仕える場合も、エラーが立った瞬間の walk のパスを記録する」と
   規定する。Rooted (global option の ref/link 衛星) はまさにこのケースであり、
   `Held.path` の現実装 (`src/core/eval.mbt` の `nest_path` — 無条件 prepend =
   walk 位置 = コピー先 scope 基準) は仕様通り。ここに escape を配線すると
   むしろ DR-066 §4 に反する。

2. **`Cand.link` の escape は `complete()` 固有の内部要請**: `Cand.path` の
   escape (`nest_cands` の `link > 0` スキップ) は `complete_tree` が
   `(path, origin)` キーで宣言元 Entity を lookup するための実装要請であり、
   `src/core/node.mbt:710` のコメントが `purely an implementation detail`
   と明言する通り、wire にも候補同一性にも現れない中途半端な内部値
   (`docs/decisions/DR-104-completion-fixture-format.md` §2 「`Cand.path`
   は wire に含めない」)。`ParseError.path` (`Held.path`、DR-066 §4 の
   wire 上の仕様フィールド) とは意味論が別物であり、同じロジックを
   横展開する前提そのものが成立しない。

3. **実機実証 (2026-07-15)**: global option (`number`, `global:true`) を
   子 command `a` に持つ定義に対し `KUU_FIXTURES` 注入で
   `["a","--level","notanumber"]` を実行 → `path=["a"]` (コピー先 scope
   基準) を確認。`path=[]` (宣言元 scope 基準) を期待する対照実験は不一致。
   構造の類似性 (`nest_path` と `nest_cands` がどちらも「無条件 prepend で
   子 scope に潜り込む」形を持つこと) からの疑いは、実証の結果否定された。

**派生発見**: `Pending` → `ParseError` 変換経路 (`missing_operand` 変換、
DR-053 §2.3) の path 非対称は本 issue のスコープ外、別 issue で追跡する。

## TODO

<!-- wip 時のみ -->
