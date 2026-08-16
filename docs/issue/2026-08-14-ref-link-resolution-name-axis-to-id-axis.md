---
title: ref/link/observes/borrow の解決が name 軸のまま — DR-046 §1 の id 軸へ載せ替える
status: open
category: task
created: 2026-08-14T21:29:15+09:00
last_read:
open_entered: 2026-08-14T21:29:15+09:00
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

# ref/link/observes/borrow の解決が name 軸のまま — DR-046 §1 の id 軸へ載せ替える

## 概要

DR-046 §1 は参照 (ref / link、および observes / borrow 系の参照解決) の同定軸を **id 軸** (明示 `id`、無ければ name が供給する = §2) と定めている。しかし現行実装の解決は **name 軸のまま**で、明示 `id` を見ていない。duplicate-name 実装 (commit 74610f73、DR-054 更新 5) で `@engine.ElementDef.id : String?` と `ElementDef::reference_identifier()` という carrier は入ったので、参照解決側をこれに載せ替える作業が残っている。

## 背景

現状の carrier (74610f73 で入った分):

- `src/internal/engine/declaration.mbt`: `ElementDef.id : String?` + `pub fn ElementDef::reference_identifier(Self) -> String` (明示 id > name)
- `src/kuu/wire_decode.mbt`: `dec_reference_id` が dec_option / dec_positional / dd 経路で wire の `"id"` を読む (DR-067 §2 の `#` 予約検査つき)。それ以前は allowed_keys で受理して捨てていた
- 読み手は現状 `collect_duplicate_names` (src/internal/engine/lowering.mbt) のみ

実測 (2026-08-14、上記 commit 時点の実装。probe fixture を KUU_FIXTURES で外挿して観測):

1. **明示 id を link のターゲットに書くと解決しない**
   定義: `{"name":"format","id":"fmt","type":"string","default":"text","long":true}` + `{"name":"json","long":[":set:json"],"link":"fmt"}`
   結果: `definition rejected: json/absent-ref` (id `fmt` は参照先として存在しない扱い)
2. **name で書けば従来どおり解決する**
   同じ定義で `link: "format"` にすると success (`format` へ set(json)@link)
3. **同名 + id 分離のペアへ name で link すると、報告なしに片方へ潰れる**
   定義: `{"name":"x","id":"x1",...,"export_key":"x1"}` + `{"name":"x","id":"x2",...,"export_key":"x2"}` + `{"name":"j","long":[":set:hit"],"link":"x"}`
   結果: success で `effects=[{entity:"x", payload:"set(string:hit)@link"}]` / `result={x2: "hit"}` — 2 つの宣言のうち後者の露出キーへ着地し、曖昧である旨の報告は無い。id で分離された 2 要素が参照解決の面では 1 identity に潰れている
   (この形は duplicate-name では**合法**。DR-054 更新 5 が `fixtures/dd/duplicate-decl.json` を id 分離の合法例として pin しているのと同じ形なので、「宣言としては分離できるのに参照は分離できない」ねじれがそのまま残っている)

## 受け入れ条件

- [ ] ref / link / observes / borrow (default_fn の `borrow:` を含む) の解決が `reference_identifier()` 軸へ載せ替わっている。関係しそうな既存関数: `collect_absent_ref` / `collect_circular_ref` / `collect_link_path_errors` / `collect_absent_link` / `default_fn_edges` (いずれも src/internal/engine/lowering.mbt)
- [ ] entity / binding の keying が宣言名のままでよいかの見極めがついている (現状 effects の `entity` は宣言名。id 軸へ寄せるなら射影側の影響範囲が広い — DR-046 / DR-120 §4 の 3 軸 (綴り / 結果キー / id) の分離をどう写すかの設計判断が要る)
- [ ] 上記実測 3 の「黙って片方へ潰れる」の扱いが決着している (id 軸へ載せ替えた後に正しく分離されるのか、name 参照が曖昧として definition-error になるのか)。spec 側の裁定が必要なら Q を上げる

## 追記 (2026-08-15)

- (a) CMDID-Q1=a により id 軸参加範囲が command まで拡大し、spec fixture 8609393d の command 明示 id 群は carrier/duplicate-id 検査には反映されたが、ref/link 等の解決側は引き続き未対応 (本 issue の対象範囲のまま)
- (b) command alias copy は canonical command と同じ id を保持するため、解決を id 軸へ移す際は alias-copy を `ElementDef.is_alias` 相当で解決候補から除外しないと canonical と copy が ambiguous 化する。載せ替え作業時の注意点として記録

## TODO

<!-- wip 時のみ -->

## 出所

duplicate-name 実装 (DR-054 更新 5) サイクルでの自己申告。統括承認済み (2026-08-14)。

## 追記 (2026-08-15 その2): 解決は共通 resolver に一元化する (kawaz 指示)

DR-136 §6 の 2 段ルックアップ (①raw 一致 → ②参照文字列に当該軸の文字写像を掛けて照合、スコープ近接 > 一致方式) は、id 軸を参照する全属性 (`ref` / `link` / `borrow` / `requires` / `conflicts_with` 等の制約属性 / link 固定パス DSL のキー部) が同じ規則を使う。**各呼び出し箇所で個別に実装せず、単一の共通 resolver 関数に一元化すること** (kawaz 2026-08-15: 「各所で実装するとアホなので共通化」)。個別実装は写像適用の有無・段の順序・スコープ辿りが箇所ごとにずれるバグの温床になる。

## 追記 (2026-08-16): 共通 resolver を新設、link 経路まで載せ替え済み

DR-136 実装追随サイクルで以下まで完了 (conformance 417/0 mismatch、全 738 tests green):

- `src/internal/engine/axis_reference.mbt` 新設 — `resolve_axis_reference` /
  `resolve_id_reference` が DR-136 §6 の 2 段ルックアップ (①raw → ②当該軸の写像後、
  段は候補列全体で切り替える) の唯一の実装
- `resolve_link_path` の root 解決と `named_structural_child` (固定パス DSL のキー部) を
  この resolver 経由へ。照合軸は宣言名から `reference_identifier()` (明示 id or name の
  id 軸写像後) に移った

### 未着手と、その理由 (spec 裁定待ち) — **2026-08-16 に統括裁定で解消済み、下記追記を参照**

`requires` / `conflicts_with` / `exclusive_group` / `required_group` / `borrow` / `ref` は
resolver へ載せていない。**`Constraint::Requires(elem, targets)` の第 1 フィールドが
「committed 判定の entity キー」と「errors[].element」を兼ねている**ためで、DR-136 裁定 4
(element = 参照識別子) と現行の entity keying (宣言名) を同時に満たすには、
`RequiresIf(entity, branch_id, ...)` と同じ形へ 2 軸に割る設計判断が要る。これは本 issue の
受け入れ条件 2 番目 (entity / binding の keying をどうするか) そのもので、
実測 3 の「同名 + id 分離へ name 参照すると黙って片方へ潰れる」の扱いと同じ裁定に属する。
現状 fixture の coverage も無いため、裁定前に実装を進めると発明になる。

## 追記 (2026-08-16 その2): 統括裁定を受けて制約属性まで載せ替え完了

統括判定 (2026-08-16): 下の「裁定待ち」2 点はいずれも既裁定からの導出で新裁定不要。
(1) 制約属性・borrow・ref も共通 resolver へ載せる — DR-136 §6 が対象属性に制約属性を
明記しており、`Requires` の 2 軸分離は裁定 4 の帰結 (RequiresIf の既存形と同じ)。
「同名 + id 分離へ name 参照で潰れる」懸念は 2 段 resolver 自体が解く (段 1 の raw 一致が
先で、同一スコープの raw 重複は duplicate-id が弾くので一意)。
(2) `definitions` のキーは明示 literal なので段 2 なし (raw 一致のみ) — 「明示値は無変換」
(§3) と同じ原則。

実装 (conformance 418 fixtures / 942 cases mismatch 0、全 738 tests green):

- **内部同一性を id 軸へ確定** — decode 境界の `settle_name_axes` (`src/kuu/wire_decode.mbt`)
  が trigger_name / export_key を name から供給し、`name` 自身を参照識別子へ寄せる。
  installer 相以降は `name` が唯一の同一性キーになり、受け入れ条件 2 番目 (entity / binding の
  keying) はこの形で決着した。綴りの担体として name を raw で持つ宣言 (exact の literal 直値、
  dd のトリガ) だけが除外される
- **制約属性の目的語を 2 段ルックアップで解決** — `inst_constraint` が requires /
  conflicts_with / value_requires の目的語を共通 resolver で引き当て、述語が読む entity 名軸へ
  落とす。alias entry-copy は候補から除外 (上記追記 (b) の注意点)
- **`Constraint::Requires` / `Conflicts` を (entity, element, targets) の 3 軸へ分割** —
  committed 判定は entity 名軸、`errors[].element` は参照識別子軸
- 実測 3 の「同名 + id 分離へ name 参照すると黙って片方へ潰れる」は、
  `fixtures/constraints-parse/requires-id-axis-lookup.json` が段 1 の厳密一致で指し分かれることを
  pin し、解消を確認した

### 残り

- `ref` (`definitions.templates` のキー) は raw 一致のみで既に要件どおり (裁定 (2))。
  スコープ内の要素を指す `ref` を 2 段にする経路は現状の corpus に無い
- `borrow:` (default_fn) は `default_fn_edges` が name で辺を張るが、境界で name が id 軸に
  なったため実質 id 軸で解決している。専用 fixture での pin は未

### 補足: link の root 候補列に command が入らない (2026-08-16、fable レビュー由来)

`resolve_link_path` (`src/internal/engine/lowering.mbt`) が組む root 候補列は
`def.options` + `def.positionals` だけで、**`def.commands` を含まない**。したがって
DR-134 の command 値担体 (`value:` / `default:` を持つ command) を link の root に
名指しする形は、2 段ルックアップの段に関わらず解決しない (`Missing` → absent-ref)。

共通 resolver へ載せ替えた際の設計判断ではなく、載せ替え前からの候補列の範囲がそのまま
残っている状態である。command を候補に加えるべきか (= command 値担体への link を
許すか) は spec 側の規定が要るので、ここでは現状を記録するに留める。

## 追記 (2026-08-16 その3): kuu.mbt 全コードレビュー由来の未記録の穴 3 件 (C4/C-3/B4)

統合レビュー報告 (kuu.mbt 全コードレビュー 2026-08-16、領域別8並列) の P1「id/name軸解決の一元化漏れ (DR-136 §6) — 3領域で同型」にて、本 issue の残タスク一覧に載っていない未記録の穴が3件見つかった。いずれも `resolve_id_reference` を通らない raw一致箇所が残存している例。

### C4 (Critical, help/completion + lowering): alias target の解決が raw 一致のみ

- 場所: src/kuu/help.mbt:311, 386, 421 + src/internal/engine/lowering.mbt:3883-3905
- alias target の解決が raw一致のみ (DR-136 §6の2段ルックアップ未適用)
- 記号入りnameの要素へのaliasがdefinition-errorも出さず無言消滅 (実測)
- id軸化のregression。`resolve_id_reference` を適用し、engine+help両面同時に直す必要がある

### C-3 (lowering): `link_path_crosses_multiple` の root 解決が raw 一致のみ

- 場所: src/internal/engine/lowering.mbt:2633
- `link_path_crosses_multiple` の root解決がraw一致のみ — raw綴りのlinkがmultiple横断Unsupportedガードを迂回 (実測)
- C4と同根 (resolve_id_reference未使用)。C4と同じ載せ替え作業に含めて対処するのが効率的

### B4 (wire_decode/front_door): templates への settle 未適用

- 場所: src/kuu/front_door.mbt:169
- `settle_name_axes` が `definitions.templates` に届かず、inline seq と ref template で結果キーが割れる (実測 `file_path` vs `file path`、DR-136 §4 / DR-078 §1 パリティ違反)
- 対処方針: templates にも settle を適用する

出典: kuu.mbt 全コードレビュー 2026-08-16 (領域別8並列)
