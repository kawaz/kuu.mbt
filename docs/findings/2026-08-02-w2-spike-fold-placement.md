# W2-0 spike: DR-127 §4.2 の枝ローカル fold の置き場所検証

> 対象: `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §7 (W2-0)。
> spike コードは捨て済み (この findings のみが成果物)。W2-8 の設計入力。
> 検証日: 2026-08-02。baseline: 609 tests / conformance ran_cases=880 mismatches=0。

## 判明した事実

1. **fold は計画どおりの位置に置ける。** `src/internal/engine/eval.mbt` の `parse_tree`、
   `Accept(p, bs)` アームの `if p == toks.length()` 内側 (`strip_levels_to_declaring_scope`
   の前) で `bs` を走査し、解決不能マーカー検出時に (i) `full` へ push しない
   (ii) `ParseError` を合成して `push_error` する形が成立する。3 確認点はすべて成立:
   - (a) `or` 2 枝の片方がマーカーでも、もう片方が勝つ (ambiguous にならない) — A/B 両 variant で成立
   - (b) 全枝マーカーで `Failure.errors` に `unresolvable_link_path` が 1 件以上載る (無言の失敗にならない)
   - (c) spike 込みで `just test` = 613/613 passed (609 + spike wbtest 4 本)、
     conformance `ran_cases=880 mismatches=0` 不変
2. **`max_reach` / `collect_actions` への寄与 2 通り (A=させる / B=させない) は、既存 880 cases
   についてはどちらも不変。** ただしこの不変は自明な不変である — マーカー prefix を持つ binding を
   産む定義が既存 fixture / tests に存在せず、fold は既存経路で一度も発火しない。
   「fold の差し込みコード自体が既存経路を壊さない」ことの確認であって、2 通りの優劣は
   既存 cases からは決まらない。
3. **A/B の意味論差は全枝落ち時の `fired_action` に現れる** (wbtest で観測)。マーカー枝に
   failure-action marker (`@act:help`) を同乗させて全枝落ちさせると:
   - A (寄与させる): `fired_action = Some("help")` — 落とした枝の action が発火する
   - B (Reject 等価): `fired_action = None` — 落とした枝は action 選定からも消える
4. **合成 ParseError の args_pos 帰属は §6.2 裁定どおり動く。**
   - マーカー binding が `at_pos` を持つ場合 (トークン消費で built): その位置に帰属。
     実測: `toks=["go","v"]` で値を位置 1 から読んだマーカー → `args_pos=1` (消費位置 2 ではない)
   - `at_pos` 無し (`Bind` 等の 0-token binder): 消費位置 `p` (= 完全経路なので `toks.length()`)

## 実用的な示唆 (W2-8 の設計入力)

- **「Reject と同じ」は 2 値でなく 3 択である。** spike で試した A/B に加え、**Held 等価**
  (= 合成 ParseError の `args_pos` で `max_reach` に寄与し、faildef 判定で `collect_actions`
  にも寄与する) が本命候補になりうる。W2-8 の枝落としは「合成 ParseError を持つ」点で
  純 Reject (エラー無寄与) より Held (`push_error` + args_pos 寄与) に構造が近い。
  DR-127 §4.2 / DR-037 の帰属原則とどれが整合するかは W2-8 着手時に spec 側で裁定するのが良い。
  spike の実装では B は「push_error はするが max_reach へ args_pos 寄与しない」形であり、
  Held の扱い (`Held(pe, _) => if pe.args_pos > max_reach`) と非対称になっている。
- **fold の検出は complete 枝 (`p == toks.length()`) だけで足りるかは未決。** spike は
  full push 直前のみで合成した。partial Accept (`p < toks.length()`) にマーカーが乗る場合、
  `full.length() == 0` 時の residual 合成ループ (`max_partial`) へは spike では手を入れて
  いない — マーカー付き partial が residual の `unexpected_token` を「深く」見せる余地が残る。
  W2-8 では実行時解決の失敗が partial 枝にも乗りうるかを先に確認すること。
- **合成 ParseError の形** (spike で使い、conformance 語彙とは未調整):
  `element` = 対象 binding の名前 / `args_pos` = 上記帰属 / `kind: Parse` /
  `reason: "unresolvable_link_path"` / `path` = binding の `scope` をそのまま流用。
  `path` の正しさ (Binding.scope は result nesting path、ParseError.path は ancestor scope
  names — 単純ケースでは一致するが global copy / `levels_to_declaring_scope` 絡みで
  ずれうる) は W2-8 で `fire_path` 相当の扱いを検討すること (Pending→ParseError 変換が
  `c.fire_path` を使う先例: `eval.mbt` の Pending アームのコメント参照)。
- **dedup との相互作用は自然に消える。** fold は dedup (`strip_none_placeholders` キー比較)
  より前に枝を落とすので、マーカー枝が dedup の比較対象に入ることはない。
- **`push_error` の dedup が全枝落ち時の重複を畳む。** 同一 (element, args_pos, kind, reason,
  path) の合成エラーは 1 件に集約される — 同じ解決不能 binding を含む複数枝が落ちても
  エラーは 1 件で済む (wbtest (b) は異なる element 2 枝で errors >= 1 を確認)。

## 検証の詳細

### spike の構成 (捨て済み)

- マーカー: `binding.key` の prefix `"#spikeA-unresolvable:"` / `"#spikeB-unresolvable:"`
  (Binding にフィールドは足していない。本実装では W2-6 の値空間解決結果がこの位置に入る)
- 差し込み位置: `parse_tree` の 2 箇所
  1. `max_reach` 集計ループの `Accept` アーム — B variant のみ寄与除外
  2. 効果集計ループの `Accept` アーム先頭 — マーカー検出で full push を skip、
     `p == toks.length()` なら ParseError 合成、A variant のみ `collect_actions` へ寄与、`continue`
- wbtest 4 本 (`src/internal/engine/eval_wbtest.mbt` に追記、捨て済み):
  (a) or 片枝マーカー A/B → Success / (b) 全枝マーカー → Failure + reason 確認 + args_pos=消費位置 /
  (b2) at_pos 持ちマーカー → args_pos=at_pos / (A/B 差) `@act:` 同乗で fired_action の有無

### 結果マトリクス

| 確認点 | variant A (寄与させる) | variant B (Reject 等価) |
|---|---|---|
| (a) 兄弟枝が勝つ | ✓ Success | ✓ Success |
| (b) 全枝落ちで原因が載る | ✓ errors >= 1 | ✓ (push_error は両 variant 共通) |
| (c) 既存 880 cases | ✓ 不変 (自明 — 発火なし) | ✓ 不変 (自明 — 発火なし) |
| 全枝落ち時の fired_action | Some (落ちた枝の action が発火) | None |
| max_reach への寄与 | p で寄与 | 寄与しない (Held 等価なら args_pos 寄与が筋) |

### 分岐判断

(a)(b)(c) の 3 点が揃った → 計画 §7 step 6 のとおり **W2-1 へ進める** (W2-8 は案 (a) のまま、
段表の変更不要)。
