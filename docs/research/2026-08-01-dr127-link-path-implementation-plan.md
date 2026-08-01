# DR-127 (link 固定パス DSL) の kuu.mbt 実装計画

> 対象 DR: spec `docs/decisions/DR-127-link-fixed-path-dsl.md` (前提 DR-126)。
> 調査日: 2026-08-01。調査時点のベースライン: `just test` = 584 tests / 584 passed、
> conformance `decoded=389 ran_cases=878 skipped=0 mismatches=0`、
> `known_divergences()` / `expected_skips()` は**両方とも空** (完全適合)。
> 本ファイルは後続の実装作業の正本。段の着手前に該当節を読むこと。

## 1. 計画の形を決めた 2 つの事実

### 1.1 第 1 波には実行時解決が 1 つも無い (§4.2 の枝 fold は第 1 波では不要)

DR-127 §2.2 の value_type 遷移表を kuu.mbt の実在型語彙に当てると、**map/value 行 (= 実行時解決) に
落ちる型が存在しない**:

- `src/extension/type_residents.mbt` の `TypeExt` 実装は
  `string / number / int / float / bool / flag / count / tty / completion_script / none` の 10 種のみ。
  すべて primitive。
- fixture が使える `definitions.types` の factory 分岐も builtin をパラメタ化するだけで、
  任意のパーサを持ち込めない。

したがって第 1 波では、値空間残余は §2.2 の **primitive 行** (「残余 segment があれば恒真不成立なので
definition-error」) に一意に落ちる。実行時に解決可否が変わる経路が 1 つも生じないため、
**DR-127 §4.2 (裁定前の枝ローカル効果列 fold) は第 1 波では観測可能な効果を持たない**。

§4.2 は `parse_tree` の完全経路カウント (`src/internal/engine/eval.mbt:4638` 以降) に触る最高リスク項目。
それを第 2 波へ丸ごと繰り延べられるので、第 1 波は**全部が定義時静的**な変更になる。

### 1.2 第 2 波の真のボトルネックは DR-127 の「追随 3 点」に入っていない

DR-127 の波及節は kuu.mbt 追随を 3 点 (decode の path AST 化 / `LinkTarget` の
(cell, path_residual) + 観測アドレス拡張 / 枝成立判定へのパス解決可否組み込み) と書き、
introspection ABI 要求を「Value に対する get / set (field / index)」で尽きるとしている。
しかし実装側の前提が欠けている:

- `src/abi/value.mbt:17` — `pub(all) enum Value { String(String); Number(Double); Bool(Bool) }`。スカラのみ。
- `src/extension/node_traits.mbt:36` — `fn parse_token(Self, String) -> Result[Value, TypeParseFail]`。
  型パーサが複合値を返す口が無い。
- `ResultValue` (`src/abi/result_value.mbt`) に `Object` / `Array` はあるが、これは**結果射影**の
  再帰形であって、セルに座る値ではない。配列はアキュムレータが複数 binding を畳んで作る。

つまり「セルが複合値を持つ」という状態がエンジンに存在しない。DR-127 の値空間 (§2.2 の
record / array / union 行、§3 の vivify、§6 の sources 構造分解) は全部この**複合値モデル導入**待ちであり、
これが第 2 波の支配的コスト。DR-127 の「Value に対する get/set で尽きる」は、その Value が既に
複合であることを暗黙の前提にしている。

## 2. 現況 (調査結果)

### 2.1 link の decode

`src/kuu/wire_decode.mbt:2291` (options) / `:2661` (positionals) で `let link_ = jf_str(o, "link")` と
生文字列を取り、`ElementDef.link_target : String?` (`src/internal/engine/declaration.mbt:57`) へ
そのまま渡すだけ。**構文検査は無い**。`link: "a.b"` は decode を通り、後段の `collect_absent_link` が
「`a.b` という name の要素が無い」として `absent-ref` を出す。
issue `docs/issue/2026-07-27-link-fixed-path-dsl-unimplemented.md` の「decode で受理していない」は、
正確には「decode は素通しで、参照層が絶対に解決できないので実質塞がっている」状態。

### 2.2 LinkTarget の funnel

- ノード: `src/internal/engine/node.mbt:251` `LinkTarget(String, String, Int, &EntityExt, Node)`
  = (from, target, levels, ext, inner)
- 生成: `src/internal/engine/lowering.mbt:2211` `route_link_entry` が唯一の funnel。ただし native
  short/eq matcher は 1 matcher に複数要素が入るため wrap できず、
  `src/extension/matcher_residents.mbt:328` が同じ ABI ヘルパを直接呼ぶ 2 経路目になっている
- 効果適用: `src/abi/value.mbt:347` `bindings_through_link(bindings, from, target, levels_to_target)`。
  `binding.key == from` のものだけ `key: target` / `source: Link` /
  `levels_to_declaring_scope += levels` に書き換える (= キー書き換え + Source::Link + levels 段の
  lexical 脱出)
- eval 側の適用箇所は `src/internal/engine/eval.mbt:532` (通常経路) と `:3687` (`consume_compound` 経路)
  の 2 箇所。どちらも `Accept/Rejected/Held/Pending` の 4 アームで同じヘルパを呼ぶ

**DR-121 §4.2 が記録する「`Source` enum に `Link` が無い」乖離は既に解消済み**
(`src/abi/value.mbt:45` に `Link` がある)。DR-127 波及節の該当記述は現況とずれている。

### 2.3 root name の解決 (第 1 相の現行実装)

`src/internal/engine/lowering.mbt:2164` `link_target_depth(def, target)` が、**当該 Definition の
`options` / `positionals` を平坦に線形探索**するだけ。`element_is_link_target` (`:2149`) が対象を
「値の座を持つ実体」に絞り、`Or(_) | Group(_)` は `multiple` の時のみ true。

つまり現行の第 1 相は「同一スコープの平坦な name 探索 (+ global copy の `link_depth` 経由の脱出)」で
あって、DESIGN §2.7 の lexical スコープ chain 全体を辿ってはいない。DR-127 §2.1 の「現行どおり」は
字面より狭い射程を指している。スコープ内部への降下は当然ながら未実装。

### 2.4 scope の組み立て — 第 1 相降下がきれいに乗る理由

`src/internal/engine/eval.mbt:186` の `nest(label, binds)` は、`levels_to_declaring_scope == 0` の
binding について `scope` の**先頭にラベルを prepend** する (>0 なら prepend せずデクリメント =
global の脱出)。

したがって `link: "timerange.since"` (`timerange` がスコープ、`since` がその子セル) は、
routed binding を `key: "since", scope: ["timerange"], source: Link` に書き換えるだけで成立する。
外側スコープを抜けるたびに `nest` が prepend するので、最終的な席は
`[outer..., "timerange"] > #since` になり、`effect_cell_key` (`src/kuu/front_door.mbt:560`) の
席同一性ともそのまま噛み合う。

**セル空間降下は `levels_to_declaring_scope` (上向き脱出) の対称物 (下向き pre-seed) として
既存モデルに収まる。** これが第 1 波を安全にしている中核事実。

### 2.5 現行の gate (解除対象)

`src/internal/engine/lowering.mbt:3720` `collect_unsupported_link_shape` — link 要素の body が
`ref` / `or` / `Group` なら `Unsupported` で拒否。これは **link を張る側の body** についての gate なので、
DR-127 の第 1 相 (link 先が構造体) とは直交する。ただし `element_is_link_target` が `Or|Group` を
(`multiple` でない限り) link target 候補から外しているので、**降下の入口としてスコープを許すには
後者を変える必要がある**。関連 issue: `docs/issue/2026-07-27-ref-link-structural-body-gate.md`
(解除条件 a/b/c が明記されており、うち (c) の `accum_cell_fire_source` と `bindings_through_link` の
混在順序は DR-127 の観測面と重なる)。

### 2.6 effects / sources の現況

- effects: `src/kuu/front_door.mbt:583` `projected_effect` が binding から組む。`entity: binding.key`
  固定で、**`path` に相当するフィールドは無い** (`OutputEffect` は `{entity, op, operand, source}`)。
  `scope` は effects に出ない (DR-121 §5 の宣言名軸)。内部セル (`#` 接頭辞の nameless 合成 id 等) は
  `output_internal_cell` で effects から落ちる
- sources: `src/kuu/resolve.mbt:1671` `result_sources` が result の shadow tree を作る。
  **スカラ 1 個 = タグ 1 個**。複合値が無いので構造分解する対象がそもそも無い
- nameless 子: `src/internal/engine/declaration.mbt:279` のとおり `#{seq}` 形式の合成 id を持ち、
  射影で wrapper のアドレスへ畳まれる。DR-127 §6 の `pair[0]` → `entity: "pair", path: [0]` は、
  この合成 id を effects に漏らさずに観測アドレスへ翻訳する作業になる

### 2.7 Binding へのフィールド追加コスト

`Binding` を丸ごと構築している箇所 (`..b` 更新でなくフィールド全列挙) は 34 箇所 —
prod 18 (`abi/eval_constructors.mbt` 4、`abi/value.mbt` 3、`extension/separated.mbt` 2、
`internal/engine/eval.mbt` 9)、テスト 16 (`kuu/resolve_wbtest.mbt`)。MoonBit の struct には
デフォルト値が無いので全箇所に追記が要るが、コンパイラが漏れを全部指す機械作業。

### 2.8 DR-126 (record) の実装上の居場所

**kuu.mbt には `io_type` / `value_type` の表現が一切無い** (grep で 0 件。
`declaration_types.mbt:21` の `value_type : String?` は help 表示用の型名文字列)。
`CellFnDescriptor` / filter descriptor は `fallibility` / `observes` などの実行時属性だけを持ち、
descriptor envelope の JSON 型体系はモデル化されていない (それは spec 側
`scripts/lint-descriptors.py` の領分)。

したがって DR-126 の「descriptor の record decode / 乖離検査」は、**kuu.mbt に value_type 体系という
新サブシステムを導入する話**になる。DR-127 のために最小限必要なのは、`TypeExt` が自分の out の形を
名乗ること (primitive か / 構造を持つか / 何の構造か) であって、descriptor envelope 全体の decode では
ない。Stage C1 と Stage E で切り分けている。

### 2.9 fixture の注入経路 (ロックステップの根拠)

- ローカル `just test` は隣接 spec リポ (`../../kuu/main/fixtures`) を **live 参照**する
- CI (`.github/workflows/ci.yml:42`) は spec を **SHA-pin** して checkout する

両台帳が空 = 完全適合なので、実装が追いつく前に spec 側へ fixture を足すと、ローカルでは即
UNEXPECTED 落ち、CI では pin bump した瞬間に落ちる。**fixture 追加を伴う段は
「spec push → kuu.mbt pin bump + 実装 push」を 1 ウィンドウで**行う。

## 3. 段階分割表

「受け入れ条件」欄の wbtest は `src/kuu/front_door_wbtest.mbt` の
`result=... sources=... effects=...` 一行表明形式を想定。spec fixture 欄の番号は
DR-127 波及節の新設 8 種。

### 第 1 波 — 全部が定義時静的 (実行時解決なし)

| 段 | 内容 | 受け入れ条件 | リスク | 委譲先候補 |
|---|---|---|---|---|
| **0** | spec 側編集: DR-029 §7 追補 / DESIGN §10.2・§2.7 / CONFORMANCE §2 の `path` / `fixture.schema.json` の `$defs.effect.path` / config_key 分界注記 | spec リポの lint 通過。コード変更なしなので kuu.mbt は不変 | 低。ただし schema に `path` を足した時点で fixture 側が書けるようになるので、実装が追いつく前に fixture を書かない規律が要る | codex-sol-worker (文面は DR-127 に確定済み) |
| **A** | link 綴りを path AST へ decode。`link_target : String?` → `LinkPath?` (root name + segment 列)。bare は segment 列空の縮退。綴り不正は decode 時 definition-error `invalid-argument`。**この段では segment 非空を従来どおり塞いだままにする** (`Unsupported` へ倒す) ので挙動不変 | 既存 584 tests green + fixtures 878 cases 不変 (`link-parse/absent-target.json` が `absent-ref` のままであること込み)。新規 wbtest: `"a"` / `"a.b"` / `"a[0]"` / `"a[-1]"` / `"a..b"` / `"a["` / `"a.b].c"` のパース結果 | 低。純粋な内部表現変更 | codex-sol-worker (機械寄り、指示書を書き切れる) |
| **B1** | 第 1 相セル空間降下の `.name` 半分。`link_target_depth` を宣言木を降りる path resolver に置換、`element_is_link_target` をスコープ通過可に、`bindings_through_link` に scope pre-seed を追加。解決不能は `absent-ref` | wbtest (兄弟スコープ子への合流、global copy との併用、`export_key` 越し、未選択枝への着地 = DR-127 §4.1b) → 通過後に spec fixture **(1)** を同一 push ウィンドウで | **中〜高**。global copy の `levels_to_declaring_scope` と pre-seed scope の相互作用、`export_key` 透過セルへの着地、`none_cells` / 内部セル判定との交差 | opus5-worker-high または fable5-worker-high (意味論判断が残る) |
| **B2** | 第 1 相の `[int]` 半分 (nameless 透過子への位置指定) + 観測アドレス保持。`Binding` に観測アドレス (entity からの segment 列) を追加し、`projected_effect` が `entity` を最寄り named 祖先へ、`path` を段列へ翻訳。負 index / 範囲外は定義時判定で `absent-ref` | wbtest (`pair[0]` 着地の result/sources/effects、負 index の定義時エラー) → spec fixture **(8)** と **(7)** のセル空間分 | **高**。合成 id `#{seq}` を effects に漏らさない翻訳が肝。`output_internal_cell` の除外規則と正面から当たる | 設計は claude 系、`Binding` フィールドの 34 箇所伝播は sonnet5-worker-low / codex-luna-worker へ分離可 |
| **C1** | primitive 行の定義時エラー化。`TypeExt` に out の形を名乗る最小メソッド (`Primitive` / `Opaque` の 2 値で足りる) を足し、primitive セルへの値空間残余を `absent-ref` に | wbtest + 新規 spec fixture 1 本 (8 種の外。「primitive 型セルへの値残余は definition-error」)。これで第 1 波の値空間が全面的に塞がる | 低〜中。`TypeExt` は open trait なのでデフォルト実装を付ければ外部実装は壊れない | sonnet5-worker-medium |

第 1 波の完了状態: DR-029 用途 4 種のうち **「他スコープの子セルへの合流」と「nameless 子への
位置指定」の 2 つが実装完了**。残る 2 つ (不透明複合値の部分同期 / 配列要素への合流) は
「値空間残余は現状 definition-error」として仕様準拠に塞がる。
fixture は (1) / (7 のセル空間分) / (8) + primitive 1 本が pin される。

### 第 2 波 — 複合値モデルの導入と値空間

| 段 | 内容 | 受け入れ条件 | リスク | 委譲先候補 |
|---|---|---|---|---|
| **D1** | 複合セル値の器だけ導入。`Value` に `Object` / `Array` 相当を足し (または `CellValue` を新設し `Value` を包含)、`value_str` / filters / accumulators / config / help / result 射影 / effects operand encode の全 match を網羅。**産出者は作らない**ので挙動不変 | 既存 584 tests + 878 cases 完全不変。追加 wbtest は器の構築・射影の往復のみ | **中** (量は多いがコンパイラが漏れを全部指す)。設計判断は「`Value` を拡張するか別型にするか」の 1 点に集約される。ここだけは先に裁定が要る | 型の選択は claude 系で裁定 → 伝播は codex-sol-worker (大規模機械的波及に強い) |
| **D2** | 産出者を通す。`TypeExt::parse_token` の戻り型を複合対応へ、テスト用の複合産出型を wbtest 内に立てる。sources の構造分解 (DR-127 §6 / DR-122 §3 の複合値内部への一般適用) | wbtest (複合値セルの result / sources 構造分解) → spec fixture **(6)** の前提が立つ | 中。`parse_token` の signature 変更は extension ABI の破壊的変更 (`docs/issue/2026-07-18-api-surface-contract-triage.md` 系と当たる可能性) | opus5-worker-medium |
| **E** | DR-126 の kuu.mbt 側。`value_type` 体系 (record / array / map / union / primitive) のモデル化、type 参照の依存グラフ解決と `circular-ref`、§4 の乖離検査 (Error、wbtest 領分) | wbtest 群 (乖離 a/b が Error、c が正常)。conformance fixture は「壊れた builtin parser を注入できない」ので pin 不可 (DR-126 §4 が明記) | 中。**D1/D2 と独立に着手できるが、検査対象の値が無いので単独では意味を持たない**。独立サイクルに切り出すなら「型体系のモデル化と参照解決」まで (乖離検査は D2 後) | fable5-worker-high (体系設計) → 実装は codex-sol-worker |
| **C2** | §4.2 の枝ローカル効果列 fold。実行時解決が初めて発生するので、裁定前に枝内で解決可否を判定して Reject に倒す | wbtest (値残余の absent → 枝 Reject → 他枝が勝つ) → spec fixture **(4)** | **最高**。§4 参照 | fable5-worker-high 一択 |
| **F** | §3 の vivify + §4.1 の座への操作語彙 (set と Value 返し fn のみ、sentinel は発火時 Reject) + §3.2 のフィールド type による operand パース | spec fixture **(2)(3)(5)** | 中〜高。時系列適用 (§4 の表 5 行) が効果列 fold と噛み合うかがすべて | fable5-worker-high |
| **G** | 観測面の仕上げ。effects `path` の値空間分、sources の座 re-tag | spec fixture **(6)(7)** の値空間分 | 中 | opus5-worker-high |

### fixture 8 種と段の対応

| # | fixture | 段 |
|---|---|---|
| (1) | セル降下 (兄弟スコープの子への合流) | **B1** |
| (2) | 値残余 (不透明複合値のフィールド書き) | F |
| (3) | 負 index (値空間) | F |
| (4) | 値残余 absent → 枝 Reject → 他枝が勝つ | C2 |
| (5) | 時系列上書き (部分書き ⇄ parser 産出) | F |
| (6) | sources の座 re-tag | D2 + G |
| (7) | effects の `path` 表記 | セル空間分 **B2** / 値空間分 G |
| (8) | nameless 透過子への位置指定着地 | **B2** |

## 4. リスク順 — 怖い仮定から潰す順序

1. **(最恐・第 2 波) §4.2 の fold を置ける場所があるか。**
   `eval.mbt:532` の `LinkTarget` アームは `eval(inner, ctx, pos)` の**ノードローカルな binding しか
   見えない**。枝の先行効果列 (同じセルへの先行 set 等) は Seq/cont 側で積まれるので、発火時点で
   「今このセルに何が座っているか」を fold できない。取り得る形は 2 つ:

   - (a) `parse_tree` の Accept 処理 (`eval.mbt:4700` 付近、`strip_levels_to_declaring_scope` の直前) で
     枝ごとに効果列を順に fold し、解決不能な link binding があれば Accept を落とす。
     **「裁定の前」の要求は満たす** (裁定 = 完全経路カウント)。既存の枝機構に触らずに済むのが利点。
     欠点は Reject の `args_pos` 帰属 (DR-037) を binding 側に持たせておく必要があること
   - (b) LinkTarget を CPS 認識位置へ移して発火時に判定する。意味論的には理想だが
     `route_link_entry` の funnel 構造と matcher 側の 2 経路目を両方作り直すことになる

   **第 2 波の着手時に (a) の spike を最初に打つ** (捨てる前提の wbtest 1 本で「枝を後から落として
   兄弟枝が勝つ」ことと既存テスト不変を確認)。ここが崩れると第 2 波の段構成が全部変わる。

2. **(第 1 波の最恐) 観測アドレス保持のデータ構造変更の波及 = B2。**
   `Binding` へのフィールド追加自体は 34 箇所の機械作業だが、本当の難所は effects 側の翻訳。
   nameless 子は `#{seq}` 合成 id を持ち、`output_internal_cell` が effects から除外している。
   `pair[0]` への着地を `entity: "pair", path: [0]` として出すには、除外規則を「内部セルは落とす」から
   「内部セルは最寄り named 祖先 + path へ翻訳して出す」に変える必要があり、**既存の effects 出力に
   影響しないことの証明が要る** (現状 878 cases が全部この除外を前提に pin されている)。
   B2 に入る前に「合成 id を持つ席が effects に現れる既存 case が 0 件か」を先に確認すること。

3. **(第 1 波) B1 の scope pre-seed × global copy。**
   `levels_to_declaring_scope > 0` の binding は `nest` で prepend をスキップする。pre-seed した scope は
   脱出中も保持されるので理屈は合うが、**global link entry が別スコープへコピーされた先から兄弟
   スコープの子へ降りる**組み合わせは実機で確認が要る
   (`front_door_wbtest.mbt:1344` / `:1366` の既存 global link テストの拡張形)。

4. **(第 2 波) D1 の型選択。**
   `Value` を拡張すると、`Binding.value` / `FilterInput::Scalar` / `DefaultCtx::dependency` /
   config 変換 / help 既定値まで全部が複合を取りうる形になり、「ここには複合は来ない」不変条件が
   型で言えなくなる。別型 `CellValue` にすると変換境界が増える。
   **設計判断としてここは claude 系が裁定すべき唯一の点**で、機械的伝播はその後。

## 5. 確定済みの裁定 (definition-error kind)

統括裁定 2026-08-01:

- **path 綴りが DSL 構文として解釈不能な場合 = `invalid-argument`。**
  DR-085 の malformed DSL 引数と同系で、`fixtures/definition-error/*-invalid-argument` の先例に従う。
  kuu.mbt の kind 定義 (`src/abi/node_types.mbt:18`) が言う「単一の値それ自身の内部妥当性」に一致する
  (`regex_match` のパターンコンパイル失敗と同型)
- **primitive 型への残余 segment (恒真不成立) = `absent-ref`。**
  参照先が構造的に存在しない系そのものであり、DR-127 §2.1 (第 1 相の解決不能) と同系

## 6. 概算規模

| 段 | 主な変更ファイル | 行数オーダー |
|---|---|---|
| 0 | spec リポの DR-029 / DESIGN / CONFORMANCE / schema 2 本 | 100〜150 (spec 側) |
| A | `src/kuu/wire_decode.mbt`、`src/internal/engine/declaration.mbt`、`src/internal/engine/lowering.mbt` + path AST の新規小モジュール | 150〜250 |
| B1 | `src/internal/engine/lowering.mbt` (resolver 置換)、`src/abi/value.mbt` (`bindings_through_link`)、`src/kuu/front_door_wbtest.mbt` | 300〜400 |
| B2 | `src/abi/value.mbt` (Binding 34 箇所)、`src/kuu/front_door.mbt` (effects 翻訳)、`src/internal/engine/eval.mbt` | 400〜550 |
| C1 | `src/extension/node_traits.mbt`、`src/extension/type_residents.mbt`、`src/internal/engine/lowering.mbt` | 80〜120 |
| D1 | `src/abi/value.mbt` 起点に全域 (filters / accumulators / resolve / help / config) | **800〜1500** |
| D2 | `src/extension/node_traits.mbt` + 全 TypeExt 実装 + `src/kuu/resolve.mbt` (sources 分解) | 400〜600 |
| E | value_type 体系の新規モジュール + 参照解決 + 乖離検査 | 400〜700 |
| C2 | `src/internal/engine/eval.mbt` (parse_tree の fold) | 150〜250 |
| F | `src/kuu/front_door.mbt` (vivify / 座操作) + `src/internal/engine/eval.mbt` | 250〜400 |
| G | `src/kuu/front_door.mbt` / `src/kuu/resolve.mbt` | 150〜250 |

第 1 波合計 ≈ 1,000〜1,300 行。第 2 波 ≈ 2,200〜3,700 行。

**委譲の仕分け**: 機械寄りで指示書が書き切れるのは 0 / A / C1 / D1 の伝播部分 / B2 の Binding 伝播部分。
意味論判断が残るのは B1 / B2 の effects 翻訳 / D1 の型選択 / C2 / E の体系設計 / F。

## 7. 最初の 1 段 (Stage A) の詳細着手手順

**目的**: link 綴りを path AST に変え、綴り不正を definition-error で弾く。segment 非空は従来どおり
塞いだままにするので、**観測可能な挙動は 1 つも変わらない** (既存 878 cases と 584 tests が完全不変で
あることが受け入れ条件そのもの)。

1. **path AST 型を置く** — 置き場は `src/internal/engine/declaration.mbt` (`ElementDef` と同居。
   `abi` に出す必要はまだ無い)。

   ```
   pub(all) enum LinkSegment { Name(String); Index(Int) } derive(Eq, Debug)
   pub(all) struct LinkPath { root : String; segments : Array[LinkSegment] } derive(Eq, Debug)
   ```

   パーサは DR-127 §1 の文法 `path := name ('.' name | '[' int ']')*` をそのまま。§1 の表層規則
   3 点のうち **「`.` / `[` / `]` を含む name はパスに書けない」** がここで効く — escaping は
   導入しないので、区切り文字が name の中に現れたら綴り不正。

2. **`ElementDef.link_target : String?` を `link_path : LinkPath?` に置換** — 参照箇所は
   `lowering.mbt` の 9 箇所 (`:430` / `:1357` / `:2149` / `:2180` / `:2441` / `:2513` / `:3727` /
   `:3782` / `:5199`) と `wire_decode.mbt` の 4 箇所 (`:286` / `:405` / `:489` / `:564`)。
   この段では全部 `path.root` を見るだけにして、`link_target_depth` / `bindings_through_link` は無変更。

   **注意**: `link_additional_levels` (global copy が declaring scope で解決した target identity を
   保存する仕組み、`declaration.mbt:60`) は path 化の影響を受けない。root name 単位の話なので
   触らないこと。

3. **decode 時検査を足す** — `wire_decode.mbt:2291` / `:2661` の `jf_str(o, "link")` の直後でパースする。
   綴り不正は definition-error `invalid-argument` (§5 の裁定)。既存の `DecodeSkip` ではなく
   definition-time の gate へ流す形を取る — `ElementDef.accumulator` が「decode は生文字列を通し、
   definition-time の gate が弾く」形を取っているのが前例 (`declaration.mbt` の accumulator 註釈)。
   つまりパース自体は decode で行って `LinkPath?` に入れ、綴り不正は「不正だった」印を残して
   `lowering.mbt` の `collect_*` 系に新設した収集関数が definition-error を出す。

4. **segment 非空を塞ぐ** — `collect_unsupported_link_shape` (`lowering.mbt:3720`) の隣に、
   `link_path.segments` が非空なら `Unsupported` (「legal in the specification, but this
   implementation cannot lower it yet」= まさにこの用途の kind) を出す収集関数を足す。
   B1 でこの gate の `.name` 分を、B2 で `[int]` 分を外す。

5. **wbtest を書く** — `src/kuu/wire_decode_wbtest.mbt` に path パースの単体 (`"a"` → root のみ /
   `"a.b"` / `"a[0]"` / `"a[-1]"` / `"a.b[2].c"`、不正: `"a..b"` / `"a["` / `"a]"` / `".b"` / `""` /
   `"a[x]"`)。`src/kuu/front_door_wbtest.mbt` に「segment 非空の link は `Unsupported`
   definition-error」1 本、「綴り不正の link は `invalid-argument`」1 本。

6. **検証** — `just test`。**584 passed / 0 failed、conformance が
   `decoded=389 ran_cases=878 skipped=0 mismatches=0` のまま**であることを確認。
   台帳 (`known_divergences` / `expected_skips`) は空のまま触らない。

7. **push** — この段は spec 側の変更を伴わない (fixture も schema も動かさない) ので、
   kuu.mbt 単独 push で安全。ロックステップウィンドウが要るのは B1 以降 (fixture (1) を足す段) から。

## 8. spec 側へ差し戻したい確認点

- DR-127 波及節の「DR-121 §4.2 が記録する参照実装の乖離 (`Source` enum に `Link` が無い) は
  本 DR の追随でも解消対象になる」は、**既に解消済み** (`src/abi/value.mbt:45`)。
  DR-121 §4.2 側の記述が現況とずれている
- DR-127 §2.1 の「root name を lexical スコープ chain → `definitions` で解決する (現行どおり)」は、
  kuu.mbt の現行が「同一スコープの平坦探索 + global copy の脱出」であって chain 全体の走査ではない
  (§2.3)。B1 でここを path resolver に置き換える際、chain 走査まで広げるのか現行の射程を保つのかは
  実装判断の分岐点になる (DR-127 が「現行どおり」と書いている以上、現行の射程を保つ = 広げない、と
  読むのが素直)

## 関連

- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` (本計画の対象)
- spec `docs/decisions/DR-126-descriptor-record-value-type.md` (第 2 波 Stage E の前提)
- `docs/issue/2026-07-27-link-fixed-path-dsl-unimplemented.md` (起点 issue)
- `docs/issue/2026-07-27-ref-link-structural-body-gate.md` (§2.5 の gate、解除条件 a/b/c)
