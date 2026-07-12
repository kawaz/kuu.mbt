# codex 総点検の指摘 3 件対応 + bool_parser configurable factory 新設

factory 名リネーム作業の節目で codex に総点検レビューを依頼し、出た指摘 3 件 (dd/none
placeholder の dedup 混入・apply_transform の未宣言 reason・bool_parser factory 未実装) を
順に修正した記録。3 件目は修正過程で issue 化してから実装した。main は `ed4ab81d` まで進み、
CI green。

## 指摘 1: dd/none の committed placeholder が経路 dedup キーに混入 (`39530e2e`)

異名の `dd` 要素 2 つ (例: `trig_a` / `trig_b`) が同一トークンに発火しうる定義で、observable な
result/effects が同一の 2 枝が、placeholder の key 差 (`elem_name` の違い) だけで偽 Ambiguous に
なっていた。dd/none 要素は entity (値セル) を持たない (DR-030「実体=値セル」) ため、DESIGN §15.1
の「経路の同一性は実体への観測可能な効果列で判定する」基準はこの key 差を見てはいけない、というのが
codex の指摘。

まず PoC (2 つの `dd` 要素が同一パターンで同一トークンに発火する定義) で偽 Ambiguous を再現してから
修正した。`eval.mbt` に `strip_none_placeholders` を新設し、**dedup 判定キー側だけ**このフィルタを
通す — `eff` 本体 (Success/Ambiguous が運ぶ binding 配列) は placeholder 込みのまま保持するので
`build_result` / `ParserContext` 側の挙動は不変。fixture `dd/duplicate-decl.json` の「同名複数宣言
は同効果に落ちる」pin は同名 (同一 key) の偶然の一致でしか成立せず、異名の複数 dd/none 要素の競合は
この抽出なしでは dedup できないことが今回判明した。回帰 pin として wbtest を 1 本追加し、標準
comparator (`run_case`) 経由で「result に dd 名が漏れない」も同時に固定した。

## 指摘 2: apply_transform の未宣言 reason を filter_rejected へ統一 (`388d8d56`)

`update_transform_type_mismatch` / `unknown_update_transform` という 2 つの reason 文字列が、
DR-095 の宣言済み vocabulary にも spec 全体 (docs/fixtures/schema grep) にも存在しない実装発明
だった。DR-095 §3 は型不一致 (非対象型が filter に渡る) を「filter-definition bug であり正しい
定義における failure mode ではない」として reasons 宣言から明示的に除外しており、この 2 reason は
その除外規定と整合しない宣言外の値だったことになる。

`resolve.mbt` の該当 3 箇所すべてを DR-095 §5 の宣言済み fallback `filter_rejected` に統一し、
message は詳細を保持したまま通す。「apply_transform が emit する reason は DR-095 の宣言集合の
部分集合であるべき」という subset invariant の違反として捉え直し、コメントと wbtest 名にその旨を
明記した (`resolve_wbtest.mbt` のテスト名を `reason=filter_rejected (DR-095 subset invariant —
no declared reason for this defensive path)` まで拡張)。

## 指摘 3: bool_parser configurable factory が未実装 (issue 化 → `6f5a5342`)

`dec_types` に bool 分岐が無く、`TypeShadow` にも bool 用 config フィールドが無いため、
configurable factory の config キー (`true_values` / `false_values` / `case_insensitive`,
DR-074 §3/§4) を wire 経由で decode できなかった。canonical default 挙動自体は `parse_bool` の
ハードコード語彙で動いていたが、方言 config (yes/no opt-in 等) を渡す経路が無い状態。factory 名
リネーム作業の調査中に発見し、issue `bool-parser-factory-unimplemented` として起票してから着手した。

実装は int_round / allow_base_prefix (DR-075 / DR-074 §2) の既存パターンを踏襲する対称設計:

- `BoolConfig` 構造体 (`true_values` / `false_values` / `case_insensitive` の 3 キー) を新設し、
  `bool_config_canonical()` が既存 `parse_bool` の暗黙語彙 (`true_values: ["true","1"]` /
  `false_values: ["false","0",""]` / `case_insensitive: true`) をデータとして再現
- `parse_bool_ext(s, config)` を新設、`parse_bool(s)` は `parse_bool_ext(s,
  bool_config_canonical())` への委譲に変わる (挙動不変、置き換えではなくデータ化)
- `BoolArg` / `SepArg` / `LongEntry` / `ElemDef` へ `bool_config` フィールドを配線し、
  `dec_types` に `bool_parser` 分岐を追加 (int/number と対称の bare/builtin ns 2 形解決)
- wbtest 4 本で 2 形解決・canonical default 不変・`case_insensitive: false` の厳密照合・未知
  config キーの reject を固定

spec 側は `value-typing/bool-dialect-config.json` (yes/no opt-in 方言 3 cases) を新規追加、spec
main は `d0b60798` まで進んだ。順序は「kuu.mbt 実装 (`6f5a5342`) → spec fixture push → pin bump」
(標準フロー通り) で、新規 fixture 追加のため既存 pin を壊さず、CI pin (`.github/workflows/ci.yml`)
を `ed4ab81d` で `37aa3b3d -> d0b60798` へ bump した。

## 最終検証値

conformance: decoded=195 / ran_cases=506 / skipped=0 / mismatches=0
moon test: 310 本、CI green
