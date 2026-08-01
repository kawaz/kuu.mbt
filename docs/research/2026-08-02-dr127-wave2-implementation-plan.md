# DR-127 第 2 波 (複合値モデル + 値空間残余 + vivify) の kuu.mbt 実装計画

> 対象 DR: spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §2.2 / §3 / §4.1 / §6。
> 前提 DR: DR-126 (record 型・型参照 registry)、DR-128 §7 (`io_type.input` の構造化)、
> DR-130 §4 / §4.1 / §9.1 (null 射影・record 補形・別軸 null)、DR-131 §2b / §3.1 / §7 (Sentinel 縮小)。
> 第 1 波計画: `docs/research/2026-08-01-dr127-link-path-implementation-plan.md` (本ファイルはその第 2 波節を置換する)。
> 調査日: 2026-08-02。ベースライン: `just test` = 609 tests / 609 passed、
> conformance `decoded=390 ran_cases=880 skipped=0 mismatches=0`、
> `known_divergences()` / `expected_skips()` は**両方とも空** (完全適合)。
> 本ファイルは後続の実装作業の正本。段の着手前に該当節を読むこと。

## 1. 計画の形を変えた 6 つの実測

第 1 波計画の第 2 波節は、いくつかの前提が実測と食い違っている。段構成を組み直した根拠が本節。

### 1.1 D1 の見積 800〜1500 行は過大 — ただしリスクの性質が逆転する

第 1 波計画は「`Value` に variant を足せばコンパイラが漏れを全部指す」ことを前提に D1 を 800〜1500 行と
見積もっていた。ところが **null 反転で実際に `Value` へ variant を 1 つ足した commit `a1038c923abd` は
10 ファイル / 40 行**である。理由は、`Value` を網羅 match している prod 箇所が 6 つしかないこと
(`abi/value.mbt` の `value_str`、`extension/filter.mbt`、`extension/accumulator_residents.mbt`、
`internal/engine/node_residents.mbt`、`internal/engine/eval.mbt`、`extension/config_value.mbt` 系)。
他は全部 `value_str` 経由か、値を不透明に運ぶだけである。

したがって Array/Object 追加の機械的コストは **150〜300 行**が現実的な線。しかし同時に、
**コンパイラは漏れを指してくれない**という結論が出る。`Value` を触る大半のコードは `value_str` を
呼んでおり、`value_str` は `Null` に対して `abort("null has no scalar string representation")` する。
複合値を足せば同じ形の arm を足すことになり、**「スカラを仮定した既存コードが複合を受け取ったら
実行時 abort する」経路が生まれる**。コンパイル通過は安全の証明にならない。

`value_str` の call site は 136 (prod 約 100)。ただし内訳が救いになる:

| 経路 | ファイル | 件数 | 複合が来るか |
|---|---|---|---|
| 宣言経路 (default リテラル・enum 値・help 表示) | `kuu/wire_decode.mbt` 35 / `kuu/help.mbt` 31 / `abi/declaration_types.mbt` 14 / `internal/engine/lowering.mbt` 12 / `builtins/installer_residents.mbt` 10 | 約 102 | 来ない (DR-130 §3.1 で定義側に複合リテラルの席が限られる) |
| **実行時セル値経路** | `kuu/resolve.mbt` 2 (`:3959` / `:3983`) / `internal/engine/eval.mbt` 2 (`:4300` / `:4396`、RequiresIf 比較) / `extension/accumulator_residents.mbt` 1 (`:564`) | **5** | **来る** |

D1 の本体は「150〜300 行の機械変更」ではなく「**この 5 箇所 + 網羅 match 6 箇所が複合を正しく扱うことの
証明**」である。段の受け入れ条件はそこに置く。

### 1.2 kuu.mbt には既に同型の複合値が 3 つある — うち 1 つは統合してはいけない

`src/abi/value.mbt` の中だけで:

```
pub enum ConfigVal { String; Number; Bool; Array(Array[ConfigVal]); Object(Array[(String, ConfigVal)]); Null }
pub(all) enum Value { Null; String; Number; Bool }
```

`src/abi/result_value.mbt`:

```
pub(all) enum ResultValue { Scalar(Value); Array(Array[ResultValue]); Object(Array[(String, ResultValue)]) }
```

**`Value` に Array/Object を足すと `ConfigVal` と綴りまで一致する。** 統合したくなるが、
DR-130 §9.1 が明示的に禁じている — `ConfigVal::Null` は「その config 席は供給しない」(DR-050) であって、
`Value::Null` の「値が無い」とは層が違い、**config の null が値空間へ `null` として流入することはない**。
型を畳むとこの非対称が型から消え、`config_to_value` (`src/extension/config_value.mbt:47`) が唯一守っている
境界が失われる。`ConfigVal` は同型でも別型のまま残し、非統合の理由を design rationale としてコード側に書く。

一方 **`ResultValue` と拡張後の `Value` は真に同型**になる (`Scalar` ラッパの有無だけ)。ここは統合候補だが、
統合すると「セルがスコープ kv を持つ」が型として表現可能になり、第 1 波計画がリスク #4 で挙げた不変条件が
失われる。**判断は W2-5 まで持ち越す** — accumulator ABI が `collect(Array[Value]) -> ResultValue` から
`-> Value` へ自然に縮む段で、統合の是非が具体的な選択として立つ。W2-3 では `ResultValue` を触らない。

### 1.3 §4.2 の fold を置く場所は実在する — ただし「枝を落とす」だけでは足りない

第 1 波計画が案 (a) として挙げた場所は実在を確認した。`src/internal/engine/eval.mbt:4816` 付近、
`parse_tree` の `Accept(p, bs)` アームで `p == toks.length()` を満たす枝が
`strip_levels_to_declaring_scope` を通り、dedup を経て `full` に push される。ここは
**裁定 (完全経路カウント) の直前**であり、DR-127 §4.2 の要求位置と一致する。

ただし第 1 波計画が書いていない問題がある。同じ `Accept` は `full` への push に加えて
`collect_actions(bs, actions)` と `max_reach` にも寄与している。**`full` から外すだけでは Reject と
同じにならない** — 全枝が解決不能で落ちた場合、`errors` が空のまま「完全経路 0 件」になり、
失敗レポートに原因が 1 つも載らない。DR-127 §4 は「無ければ全体パース失敗」と書くが、DR-037 の
args_pos 帰属を持つ理由を出す義務は消えない。fold は**枝を落とすと同時に `ParseError` を合成して
`push_error` へ渡す**必要がある (§6 の統括裁定 2 で確定)。

### 1.4 効果適用の fold が既に 2 つある — 3 つ目を足す前に一本化が要る

- `src/kuu/front_door.mbt:689` — `let current : Map[String, @abi.Value] = Map([])` を作り、
  `:711` の `projected_effect(ast, binding, current)` ループで畳む (effects 射影用)
- `src/kuu/resolve.mbt` のセル解決 — 値源ラダーを回す本体

§4.2 の枝ローカル fold はこれの 3 つ目になる。3 つが独立に「セルに今何が座っているか」を計算し、
**複合値と vivify が入った瞬間に 3 つの答えがずれうる**。しかも conformance は effects と result の
両方を pin しているので、**両方が同時に間違っていないと検出できない**組み合わせが生じる。

`current : Map[String, @abi.Value]` (`front_door.mbt:589`) は key → スカラの平坦 map であり、
`tr.until` への書きはこの map の値が複合を持ち、かつ部分更新できないと表現できない。
**この map が値空間の唯一の具体的アンカー**である。一本化は vivify (W2-7) と fold (W2-8) の共通前提なので、
両者より前に独立した段として置く。第 1 波計画は一本化を段として持っていない。

### 1.5 第 1 波の fixture 債務が 3 本残っている — 第 2 波が背負うのは 5 種でなく 8 種

`fixtures/link-parse/` は今も `absent-target.json` / `basic.json` / `export-key-address.json` の 3 本のままで、
DR-127 波及節の新設 8 種は **0 本**書かれていない。第 1 波は (1) セル降下 / (7) effects path のセル空間分 /
(8) nameless 位置指定を**実装して wbtest では pin した** (`src/kuu/front_door_wbtest.mbt:1514` / `:1599` /
`:1667` 等、link 関連 wbtest 計 25 本) が、conformance fixture へは落としていない。

wbtest は実装内部の表明であって、他実装が読む規範ではない。**第 1 波の成果は現在 conformance 上は
不可視**であり、第 2 波が値空間側を触ると回帰検出の網が無い状態で進むことになる。第 2 波の第 1 段は
この債務返済にする。

### 1.6 `TypeExt::output_shape` の既定が `Opaque` であることは、値型体系の導入を安全にする

`src/extension/node_traits.mbt:28` に第 1 波が置いた placeholder:

```
pub(all) enum TypeOutputShape { Primitive; Opaque }
impl TypeExt with fn output_shape(_self) { Opaque }   // 既定
```

`src/internal/engine/lowering.mbt:4062` で `Residual(Opaque)` は `Unsupported` definition-error、
`:4159` で `Residual(Primitive)` は `absent-ref`。つまり**外部の TypeExt 実装は既定で「値空間へは
降りられない」側に落ちる**。`TypeOutputShape` を value_type 体系へ置換するとき、`record` を名乗らない
住人は既定の `Opaque` = Unsupported のまま動き続ける。破壊的にならない置換点が既に用意されている。

加えて **DR-128 §7 が `io_type.input` の string 固定を撤廃**し、`input_structure` を持つ type の
value_parser は構造化 Value を受ける。value_type 体系のモデル化は DR-126 (record 宣言)・
DR-127 (値空間残余)・DR-128 (産出形の包含検査) の **3 DR に共通のインフラ**であり、第 1 波計画が
Stage E を後半に置いていたのは効きが悪い。前倒しする。

## 2. 段階分割表 (第 2 波)

各段は green 維持 (`just test` = 全 pass、conformance mismatches=0、両台帳空) を出口条件とする。

| 段 | 内容 | 受け入れ条件 | リスク | 委譲先 |
|---|---|---|---|---|
| **W2-0** | **§4.2 fold の spike (捨てる前提)**。`eval.mbt:4816` の `Accept` アームに「常に解決不能な link binding があれば枝を落とし ParseError を合成する」を仮実装し、(a) 兄弟枝が勝つこと (b) 既存 880 cases が不変であること (c) 全枝落ちの失敗レポートに原因が載ること を wbtest で確認して**捨てる** | spike wbtest が 3 点を示す。commit しない (findings に結果だけ残す) | 高だが捨てるので実害なし。**ここが崩れると W2-8 以降の段構成が変わる**ので最初に打つ | fable5-worker-high |
| **W2-1** | **第 1 波 fixture 債務の返済**。spec に (1) セル降下 / (7-cell) effects path のセル空間分 / (8) nameless 位置指定着地 を新設。実装変更は §6 の統括裁定 3 (負 index の観測アドレス正規化) のみ | 新 fixture が現行実装で pass (= 第 1 波の挙動がそのまま規範として立つ)。ran_cases が 880 → 883+ | 低。落ちたら第 1 波の実装か fixture の読みが誤っている signal であり、それ自体が価値 | codex-sol-worker (wbtest 25 本が期待値の出所として使える) |
| **W2-2** | **value_type 体系のモデル化** (DR-126 §1)。`value_type := primitive \| {array} \| {map} \| {record} \| union` を導入。type 参照 registry 解決 (registry 空間のみ、`definitions.types` に shadow されない — DR-126 §1)、依存グラフの循環検査 `circular-ref` (DR-067 の参照層に type edge を追加)。`TypeOutputShape` を value_type へ置換 (既定は名乗らない = 現 `Opaque` 相当) | wbtest: 参照解決 / 未登録参照 = `unknown-vocab` / 循環 = `circular-ref` / bare 名の builtin ns 糖衣。**既存 880 cases 不変** (record を名乗る住人がまだ居ないため) | 中。体系設計そのもの。DR-128 §7 と共有するので**入力側 (`io_type.input`) の席も同時に見込んだ形にする** | 体系設計 fable5-worker-high → 実装 codex-sol-worker |
| **W2-3** | **`Value` の複合化 (器のみ)**。`Array(Array[Value])` / `Object(Array[(String, Value)])` を追加。産出者は作らないので挙動不変。**`ConfigVal` は統合せず、非統合の理由 (DR-130 §9.1) を design rationale として明記**。`ResultValue` は触らない | 既存 609 tests + 880 cases 完全不変。§1.1 の「実行時 5 箇所 + 網羅 6 箇所」の全件に arm があることを棚卸し表で示す。追加 wbtest は器の構築 / JSON 往復 / Eq | **中**。量は小さいが**コンパイラが守ってくれない**。受け入れ条件を「コンパイル通過」でなく「棚卸し表の全件確認」にする | opus5-worker-medium (機械作業でなく監査が本体) |
| **W2-4** | **効果適用 fold の一本化**。`front_door.mbt:689` の `current` map と resolve のセル fold を 1 つの共有関数へ。map の値を複合対応にし、座への部分更新 API (segment 列での get / set) を 1 箇所に置く。挙動不変 | 既存 tests / cases 完全不変。wbtest: 部分更新 API の単体 (record 座 / array index / 負 index / 未 vivify) | 中〜高。既存 2 fold の微妙な差異 (default 値の扱い、`Invoke` の `ctx.old` 供給) を潰す作業が本体 | opus5-worker-high |
| **W2-5** | **産出者を通す + 乖離検査**。`TypeExt::parse_token` の戻り型を複合対応へ (extension ABI の破壊的変更)。DR-126 §4 の乖離検査を**射影で null 補形する前の生出力に対し** (DR-130 §4.1) — (a) 宣言外キー / (b) フィールド type の `out` 不一致 = Error、(c) 宣言済みキー不在 = 正常。sources の構造分解 (DR-127 §6 / DR-122 §3) | wbtest: 複合産出型を wbtest 内に立て、result / sources の構造分解、乖離 (a)(b) が held-error、(c) が正常。→ spec fixture **(6)** の前提が立つ | 中〜高。`parse_token` の signature 変更は `docs/issue/2026-07-18-api-surface-contract-triage.md` と当たる。**`ResultValue` 統合の是非をここで裁定**する | opus5-worker-medium |
| **W2-6** | **値空間残余の静的解決** (DR-127 §2.2 遷移表)。`resolve_link_path` の `Residual(shape)` を value_type ごとの降下へ。record = フィールド当たり判定 (外れは `absent-ref`)、array = `[int]` は構造静的続行 / `.name` は definition-error、map・value = 以降全部実行時、primitive = definition-error (現状維持)、union = 含有 variant 1 つ以上 + 型一致検査。**型の依存グラフを辿る**降下。§6 の統括裁定 1 により **accumulator セルへの値空間パスはここで `Unsupported` に倒す** | wbtest: 遷移表 6 行それぞれの静的判定 + accumulator セルの `Unsupported`。→ spec fixture **(3)** の静的部分 | 中。union 行 (含有 variant 間の型一致 = operand のパース型が定まるか) が唯一の設計判断 | fable5-worker-high |
| **W2-7** | **vivify + 座への操作語彙**。器 `{}` の auto-vivify (record 段まで、**`set` 専用**、DR-127 §3)。`map` / `value` / 宣言なしは枝 Reject。座への operand が**フィールド側の type** の pieceProcessor を通る (§3.2)。**DR-131 §7 の縮小を反映** — Reject する Sentinel は `default` 1 つ、空座 Reject は `ctx.old` を要する fn に限る、`set(null)` は座を `null` へ戻す通常の set (DR-131 §2b)。DR-130 §4.1 の「宣言済み座の欠落は論理的に `null`」を値降下側に統一 | wbtest: DR-127 §4 の時系列 5 行すべて。vivify 済み器と null 座の同居。→ spec fixture **(2)(5)** | **高**。時系列適用が W2-4 の一本化 fold と噛み合うかが全て。null 座との相互作用は DR-130/131 で規範が固まっているので**設計の不確定性はむしろ第 1 波計画時点より低い** | fable5-worker-high |
| **W2-8** | **§4.2 の枝ローカル効果列 fold** (W2-0 の spike を本実装へ)。実行時解決 (array index の現在長 / map キー / `value`) が初めて発生する。裁定前に枝内で解決可否を判定し Reject へ倒す。§6 の統括裁定 2 により **ParseError の合成は義務** (args_pos = 当該 binding の `at_pos`、無ければ消費位置) | wbtest: 値残余 absent → 枝 Reject → 他枝が勝つ。全枝落ちの失敗レポート。→ spec fixture **(4)** と **(3)** の負 index 実行時分 | **最高**。W2-0 で形が確定していれば実装は追随 | fable5-worker-high |
| **W2-9** | **観測面の仕上げ**。effects `path` の値空間 segment (セル空間 segment と混在、境界印は置かない — DR-127 §6)。**index segment は解決済みの非負値を載せる** (§6 の統括裁定 3、セル空間分は W2-1 で済み)。sources の座 re-tag (部分書きした座だけ `link`、他は産出発火のタグ) | → spec fixture **(6)(7)** の値空間分 | 中 | opus5-worker-high |

## 3. fixture 8 種と段の対応 (第 1 波債務込み)

| # | fixture | 段 | 状態 |
|---|---|---|---|
| (1) | セル降下 (兄弟スコープの子への合流) | **W2-1** | 実装済・未 pin (債務) |
| (2) | 値残余 (不透明複合値のフィールド書き) | W2-7 | 未着手 |
| (3) | 負 index | 静的分 W2-6 / 実行時分 W2-8 | 未着手 |
| (4) | 値残余 absent → 枝 Reject → 他枝が勝つ | W2-8 | 未着手 |
| (5) | 時系列上書き (部分書き ⇄ parser 産出、逆順両方) | W2-7 | 未着手 |
| (6) | sources の座 re-tag | W2-5 + W2-9 | 未着手 |
| (7) | effects の `path` 表記 | セル空間分 **W2-1** / 値空間分 W2-9 | セル空間分は実装済・未 pin (債務) |
| (8) | nameless 透過子への位置指定着地 | **W2-1** | 実装済・未 pin (債務) |

**ロックステップ規律**: `just test` はローカルで隣接 spec リポの `fixtures/` を live 参照し、CI は spec を
SHA-pin する (`.github/workflows/ci.yml`)。両台帳が空 = 完全適合なので、実装が追いつく前に spec へ
fixture を足すとローカルが即 UNEXPECTED 落ち、pin bump した瞬間に CI が落ちる。fixture を伴う段
(W2-1 / W2-5 / W2-6 / W2-7 / W2-8 / W2-9) は **spec push → kuu.mbt pin bump + 実装 push を 1 ウィンドウで**行う。

## 4. リスク順 — 怖い仮定から潰す順序

1. **§4.2 の fold が置けるか (W2-0)。** 場所は実在を確認したが、枝を落とすことが Reject と等価になるか
   (`actions` / `max_reach` / `errors` への寄与、全枝落ち時の失敗レポート) は未確認。**捨てる spike を
   最初に打つ。** ここが崩れると W2-8 が案 (b) (LinkTarget を CPS 認識位置へ移す = `route_link_entry`
   (`lowering.mbt:2211`) の funnel と `matcher_residents.mbt:328` の 2 経路目を両方作り直す) になり、
   段構成が変わる。

2. **複合 `Value` の silent hole (W2-3)。** §1.1 のとおりコンパイラが守らない。`value_str` が複合に対して
   `abort` する形を選ぶなら、**abort が到達しないことの根拠**を棚卸し表として残す必要がある。
   `value_str` を `Result` 返しへ変えて呼び出し側に判断を強いる案 (影響 136 箇所) もあるが、宣言経路
   約 102 箇所は複合が来ないことが構造的に言えるので、棚卸し + abort 維持を推す。

3. **3 つの fold の乖離 (W2-4)。** 一本化を先にやらずに W2-7 (vivify) へ進むと、「effects に出た値」と
   「result に出た値」が複合値について食い違う事故が起きる。しかも conformance は両方を pin しているので
   **両方が同時に間違っていないと検出できない**組み合わせが生じうる。一本化を W2-7 より前に置くのは
   設計由来の判断であってコスト由来ではない。

4. **accumulator セルへの値空間パス (§6 の統括裁定 1 で v1 は `Unsupported` に確定)。** W2-6 で明示的に
   塞ぐ。塞ぎ忘れると「規範が無い経路が黙って動く」ことになる。

5. **`parse_token` の ABI 破壊 (W2-5)。** 外部 TypeExt 実装が壊れる。`TypeOutputShape` の既定が `Opaque`
   だったのと同じ手 — 複合を返さない既存実装がそのまま動く既定を用意できるかが焦点。

## 5. 概算規模と委譲仕分け

| 段 | 主な変更ファイル | 行数オーダー |
|---|---|---|
| W2-0 | `src/internal/engine/eval.mbt` (spike、捨てる) | 80〜150 |
| W2-1 | spec `fixtures/link-parse/` 3 本 + pin bump + `lowering.mbt` の index 正規化 | 150〜250 (spec 側) + 20〜40 (実装側) |
| W2-2 | value_type の新規モジュール + `src/extension/node_traits.mbt` + 参照層 (DR-067) | 400〜700 |
| W2-3 | `src/abi/value.mbt` 起点、実行時 5 箇所 + 網羅 6 箇所 | **150〜300** (第 1 波見積 800〜1500 を下方修正) |
| W2-4 | `src/kuu/front_door.mbt` + `src/kuu/resolve.mbt` + 共有 fold の新設 | 350〜550 |
| W2-5 | `src/extension/node_traits.mbt` + 全 TypeExt 実装 + `src/kuu/resolve.mbt` (sources 分解) + 乖離検査 | 500〜750 |
| W2-6 | `src/internal/engine/lowering.mbt` (`resolve_link_path` の値空間降下) | 250〜400 |
| W2-7 | 共有 fold (vivify / 座操作) + `src/internal/engine/eval.mbt` | 300〜450 |
| W2-8 | `src/internal/engine/eval.mbt` (`parse_tree` の fold) | 150〜250 |
| W2-9 | `src/kuu/front_door.mbt` / `src/kuu/resolve.mbt` | 150〜250 |

**第 2 波合計 ≈ 2,400〜3,900 行** (第 1 波計画の 2,200〜3,700 とほぼ同じ。D1 が縮んだ分を W2-2 の前倒しと
W2-4 の新設が吸収)。

**委譲の仕分け**: 機械寄りで指示書が書き切れるのは W2-1 と W2-2 の実装部分 / W2-3 の arm 追加部分。
意味論判断が残るのは W2-0 / W2-2 の体系設計 / W2-3 の棚卸し監査 / W2-4 / W2-6 の union 行 / W2-7 / W2-8。
**W2-2 と W2-5 は DR-128 の実装とインフラを共有する**ので、DR-128 の実装サイクルと担当を揃えると重複が減る。

## 6. spec へ差し戻した確認点と統括裁定

調査で見つかった 4 点について、統括裁定 2026-08-02 で全件確定した。

### 6.1 accumulator セルへの値空間パス = v1 は `Unsupported` で塞ぐ

**裁定**: definition-error `Unsupported` で塞ぐ (W2-6 の提案どおり)。

`AccumulatorExt::collect(Array[Value]) -> ResultValue` (`src/extension/accumulator_ext.mbt:36`) は
resolve 相で走るため、**効果適用の時点でセルに複合値が座っていない**。DR-127 §4 の時系列表
(`--until X --timerange Z` で parser 産出が丸ごと置換) は value_parser 産の複合セルを前提にしており、
accumulator が畳んで作る複合には当てはまらない。規範不在に加え、効果時系列と resolve 相の畳みの
不整合が理由。`link: "tags.0"` のような綴りは W2-6 で `Unsupported` に落とす。

spec への issue 起票は統括側が行う。

### 6.2 §4.2 の枝落としには ParseError 合成義務がある

**裁定**: 義務あり。`args_pos` は当該 binding の `at_pos`、無ければ消費位置。

§1.3 のとおり `full` から外すだけでは全枝落ち時に `errors` が空になる。**無言の全枝落ちは DR-037 の
帰属原則違反**である。W2-8 の実装はこの合成を含む。DR-127 §4.2 への 1 文追補は統括側が spec 窓に積む。

### 6.3 「解決済み非負 index」はセル空間 segment にも及ぶ

**裁定**: 及ぶ。**観測アドレスに字面の負 index を漏らさない。**

DR-127 §6 の「index segment は解決済みの非負 index を載せる」はセル空間 / 値空間の両方に効く。
現実装は `resolve_link_path` (`src/internal/engine/lowering.mbt:2364`) で
`observation = Some({ entity: current.name, path: [ObservationIndex(target_index)] })` と
**字面の `target_index` を積んでいる**ため、セル空間の負 index が effects に `-1` のまま漏れる。
**W2-1 で正規化する** (fixture (7-cell) を書く時に露出する箇所であり、同じウィンドウで直す)。

### 6.4 §2.1 の root 解決は第 1 波の「現行射程維持」を追認

**裁定**: 追認。射程は広げない。

DR-127 §2.1 の「root name を lexical スコープ chain → `definitions` で解決する (現行どおり)」に対し、
kuu.mbt の現行は `resolve_link_path` が当該 Definition の `options` / `positionals` を平坦に線形探索し、
global copy は `link_depth` 経由で脱出する形であって、DESIGN §2.7 の chain 全体の走査ではない。
第 1 波はこの射程を保った。第 2 波でも広げない。

### 6.5 併せて確認された既解消事項

DR-127 波及節の「DR-121 §4.2 が記録する参照実装の乖離 (`Source` enum に `Link` が無い) は本 DR の追随でも
解消対象になる」は、**既に解消済み** (`src/abi/value.mbt:45` に `Link` がある)。DR-121 §4.2 側の記述が
現況とずれている。

## 7. 最初の 1 段 (W2-0 spike) の詳細着手手順

**目的**: DR-127 §4.2 の fold を `parse_tree` に置けるかを、捨てる前提のコードで確かめる。
**この段は commit しない。**

1. **仮の解決不能マーカーを用意する** — `Binding` にフィールドは足さない。spike では `binding.key` が
   特定の prefix (例 `"#spike-unresolvable:"`) で始まることを「解決不能な link binding」の代用とし、
   wbtest 側でその key を持つ binding を産む定義を組む。本実装では W2-6 の値空間解決結果がこの位置に入る。

2. **fold を差す** — `src/internal/engine/eval.mbt:4816` 付近、`Accept(p, bs)` アームの
   `if p == toks.length() {` の内側、`strip_levels_to_declaring_scope(bs)` の**直前**に、`bs` を出現順に
   走査して解決不能マーカーを検出する処理を置く。検出したら:

   - `full` へ push しない
   - `push_error(errors, <合成した ParseError>)` を呼ぶ (args_pos は当該 binding の `at_pos`、
     無ければ `p` — §6.2 の裁定どおり)
   - `collect_actions` / `max_reach` への寄与をどう扱うか **2 通り試す** (寄与させる / させない) —
     既存 880 cases がどちらで不変かを観測する

3. **確認する 3 点を wbtest 1 本ずつで書く**

   - (a) `or` の 2 枝のうち片方に解決不能マーカーが乗る定義で、**もう片方が勝つ** (ambiguous にならない)
   - (b) 全枝にマーカーが乗る定義で、**失敗レポートに原因が 1 件以上載る** (無言の失敗にならない)
   - (c) `just test` が **609 passed / conformance `ran_cases=880 mismatches=0`** のまま

4. **観測を記録する** — `docs/findings/` へ、(2) の 2 通りのどちらが既存不変だったか、(b) で合成した
   ParseError の形、`args_pos` の帰属元を書く。**これが W2-8 の設計入力になる。**

5. **spike を捨てる** — 作業コピーから spike の変更を落とし、baseline (609 / 880 / mismatches=0) に
   戻ったことを確認する。findings だけが残る。

6. **分岐判断** — (a)(b)(c) が揃えば表のとおり W2-1 へ進む。揃わなければ W2-8 は案 (b) (LinkTarget を
   CPS 認識位置へ移す) になり、`route_link_entry` の funnel と `matcher_residents.mbt:328` の 2 経路目を
   作り直すコスト (400〜700 行、リスク最高) を段表に反映し直す。この時点で統括へ差し戻す。

## 関連

- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` (本計画の対象)
- spec `docs/decisions/DR-126-descriptor-record-value-type.md` (W2-2 / W2-5 の前提)
- spec `docs/decisions/DR-128-type-input-structure-splice.md` §7 (W2-2 とインフラ共有)
- spec `docs/decisions/DR-130-null-result-projection.md` §4 / §4.1 / §9.1 (W2-3 の型分離根拠、W2-7 の null 座)
- spec `docs/decisions/DR-131-sentinel-reduction.md` §2b / §3.1 / §7 (W2-7 の操作語彙縮小)
- `docs/research/2026-08-01-dr127-link-path-implementation-plan.md` (第 1 波。本ファイルが第 2 波節を置換)
- `docs/issue/2026-07-27-link-fixed-path-dsl-unimplemented.md` (起点 issue)
- `docs/issue/2026-07-27-ref-link-structural-body-gate.md` (gate の解除条件 a/b/c)
- `docs/issue/2026-07-18-api-surface-contract-triage.md` (W2-5 の `parse_token` ABI 破壊と当たる)
