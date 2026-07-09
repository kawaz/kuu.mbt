---
title: filter chain が parse (fixture) 経路で発動しない — unit/resolve 層との統合ギャップ
status: resolved
category: bug
created: 2026-07-09T10:46:33+09:00
last_read:
open_entered: 2026-07-09T10:46:33+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-09T11:34:03+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:harness run_case の failure 分岐に resolve 層呼び出しが存在しなかったのが原因。commit fe59837d で do_resolve_pe 新設 + Success(binds) if use_resolve ケース追加により修正済み。-vv/-vvv の挙動差は fire 数ではなく期待 outcome (success/failure) による run_case 内分岐の非対称が原因だった","note:先行報告『fixture harness 実経路で確認済み』は decode 層 + resolve_scope 直接呼び出しの検証で run_case (判定本体) を通しておらず検証範囲の記述が過大だった。scope_needs_default_ladder / apply_entity_filters 自体は当初から正常。issue 記載の全再現構成が fixture 経路で期待どおり reject されることを再確認済み"]
blocked_by:
origin: kuu (spec リポ)
---

# filter chain が parse (fixture) 経路で発動しない — unit/resolve 層との統合ギャップ

## 概要

filters registry 基盤 (commit 7f1b0c96) の filter chain は unit test (filters_wbtest) と resolve_wbtest では動作するが、conformance fixture の実経路 (dec_fixture → parse → build_result) では発動しない。

## 背景

spec 側ワーカーの fixture 実測 (2026-07-09) で以下の現象を確認:

1. **scalar option**: `--port 99999` + `post_filters:["in_range:1:65535"]` → reject されず ok{port=99999}。`filters:` に付け替えても同じ。positional 版も同じ
2. **count 3-fire**: `-vvv` + `post_filters:["in_range:0:2"]` → reject どころか **fold もされず** ok{verbose=false ×3} (raw update binding 3 個が VBool placeholder のまま build_result に渡っている)。一方 `-vv` (2-fire) は fold + filter 通過で success 2 が出る — fire 数で経路が変わる不整合

### 仮説

conformance harness の `scope_needs_default_ladder` (use_resolve 判定) と apply_entity_filters の配線の隙間。resolve_entity を通らないバイパス経路 (use_resolve=false) では filter が一切走らない。判定に「filters/post_filters を持つ scalar entity は resolve 強制」を入れたはずだが、fixture decode が filters を判定対象へ届けていない、または count (update binding) の存在が判定を変える、等。**-vv と -vvv で挙動が割れる点は必ず説明を付けること** (「たまたま」で済ませない)。

### 影響

- DR-077 §1 の失敗側輪郭 (post_filter reject → kind=filter エラー) が fixture 化できない。spec fixtures/count-parse/post-filter-range.json は成功側 1 case に絞って提出済み (why に経緯明記)
- spec 側 audit 漏れ #7 (kind:filter 実例) のブロッカー (findings/2026-07-09-distill-1to1-coverage-audit.md 参照)
- 先行報告「fixture harness の実経路で -vvv 拒否を確認済み」(filters 基盤実装時) と矛盾 — 当時の検証経路 (resolve_scope 直接呼び出し?) と fixture 経路の差を特定すること

### 由来

fixture-batch worker の追補報告 (2026-07-09)。試作 fixture (value-typing/post-filter-reject.json) は削除済みで再現構成は本文から復元可能。

## 受け入れ条件

- [ ] `--port 99999` + `post_filters:["in_range:1:65535"]` が fixture 経路 (dec_fixture → parse → build_result) で reject される
- [ ] `-vvv` + `post_filters:["in_range:0:2"]` が fixture 経路で reject される (fold も正しく行われる)
- [ ] `-vv` と `-vvv` で経路が割れていた原因が特定・説明される (「たまたま」で終わらせない)
- [ ] `scope_needs_default_ladder` / `apply_entity_filters` の配線ギャップが修正される

## TODO

<!-- wip 時のみ -->
