# W2-5 記録: 産出者を通した結果と、W2-3 が残した 5 件の申し送りの決着

> 対象段: `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 の W2-5 行。
> 実測日: 2026-08-02。ベースライン `just test` = 646 tests / conformance
> `decoded=394 ran_cases=885 skipped=0 mismatches=0`、両台帳空。
> 本段適用後 = **656 tests** (新規 10 本) / `decoded=395 ran_cases=888 mismatches=0`
> (増分 3 case はすべて同乗物 A の `variant-effects/` 由来で、乖離検査由来ではない)。

## 1. `parse_token` の ABI 破壊は起きなかった

計画は当初「`TypeExt::parse_token` の戻り型を複合対応へ (extension ABI の破壊的変更)」を段の第 1 項に
置き、「複合を返さない既存実装がそのまま動く既定を用意できるかが焦点」としていた。**焦点そのものが
存在しない。**

現行 signature は `src/extension/node_traits.mbt:38` の

```
fn parse_token(Self, String) -> Result[Value, TypeParseFail]
```

で、W2-3 が `Value` に `Array`/`Object` を足した時点で戻り型は複合対応済みだった。加えて W2-2 が
`TypeOutputShape` を `output_type(Self) -> ValueType?` (既定 `None`) へ置換済みで、産出形の宣言口も
既にある。したがって本段で `TypeExt` の signature は 1 行も変えていない。既存 TypeExt 実装は
無改変で動き、`docs/issue/2026-07-18-api-surface-contract-triage.md` と当たる懸念も生じない
(同 issue の残作業は命名揺れと TRI-Q4 であって `parse_token` の signature ではない)。

計画の見立てが外れたのは、W2-2 と W2-3 が「器」と「宣言口」を先に入れる順序だったため。**ABI 破壊の
リスクは段構成そのものによって消化されていた。**

## 2. 非統合を選ぶには canonical 化規則が 1 本要る (§9-4 の決着)

`ResultValue` と `Value` の統合是非は **非統合**で確定 (統括裁定 2026-08-02)。理由は 3 つ、いずれも
コストではなく構造:

1. **層が違う。** `Value` は 1 つのセルに座る値 (`Binding.value`、parse / effect 相)。`ResultValue` は
   射影相の tree ノードで、result だけでなく **sources shadow tree 自体**にも使われている
   (`src/kuu/resolve.mbt` の `source_tag(source) -> ResultValue`)。scope の kv・repeat の行・source
   タグはどれもセル値ではない。統合すると「Binding の値が result tree 丸ごとでもよい」が型として
   表現可能になる
2. **`Scalar(Value)` ラッパは境界の番人である。** `config_to_value` が `ConfigVal → Value` を守るのと
   同じ位置に `Scalar` が `Value → ResultValue` を守る。DR-130 §9.1 が `ConfigVal` 非統合に与えた
   論証がそのまま効く
3. **重複コストが実測で小さい。** 両者を跨ぐ関数は `result_value_json` (W2-3 表の A-3) 1 本だけ

ただし非統合には代償がある。複合値がセルに座ると `Scalar(Object([...]))` と `Object([...])` が
同じ JSON の 2 表現になり、**選択は自由ではない**:

> **射影時に複合 `Value` は必ず `ResultValue` の複合アームへ持ち上げる。射影後の `Scalar` は複合を
> 保持しない。**

`Scalar(複合)` のまま射影すると `source_shadow` の `Scalar(_)` アームが leaf 1 タグに潰すため、
**DR-122 §1 (sources は result と同型の shadow tree) と DR-127 §6 (複合値を leaf 1 タグに潰さない)
が同時に破れる**。規則の実装は `result_of_value` (持ち上げ) と `value_source_shadow` (同じ構造を
産出発火のタグで写す) の 2 関数で、`build_result` の 3 つの `Scalar` 構築点と scalar seat の shadow
構築点が着地点である。

この規則は W2-3 の申し送り §9-4 (「両者の複合 arm が独立に書かれた状態」) を、統合ではなく
**到達可能性の制限**で閉じている。射影後の `Scalar` に複合が入らないので、`result_key` (W2-3 の
C-5、`Scalar` の中身を読む唯一の位置) にも複合は届かない。

### 2.1 nameless セルだけ追加の手当てが要った

named セルの複合は `source_shadow` の Object アームが seat 単位で shadow を引き渡すので、構造の
内側へ降りない。**nameless セル (key `""`) は違う** — `build_result` の nameless-seat アームは値の
構造をそのまま scope の形として返すため、`source_shadow` はその Object を「named 子の集まり」と
読んで宣言の無い座へ降り、`source projection failed: scalar result has no source seat` で abort する。

`source_shadow` の入口で「この path の nameless seat が持つ値を持ち上げた形が、今見ている result と
一致するか」を照合し、一致したら seat の shadow をそのまま返す形で塞いだ。**形の一致で判定するのが
肝**で、`build_result` が見送った nameless seat (named 子がこのノードを占めている場合) は一致しない。

## 3. 乖離検査 (DR-126 §4) の着地点と語彙

`src/extension/output_contract.mbt` に置いた。入口は `parse_token_checked(ty, token, extensions)` で、
`parse_token` の生出力を resident 自身の `output_type()` と照合し、乖離があれば
`TypeParseFail { disposition: RecognizedButInvalid, ... }` を返す。既存の全呼び出し側が
`Err(fail)` を Held へ流す形になっているので、**乖離は自動的に held Error になる** (DR-126 §4 が
Reject でなく Error を要求する理由は同 §の分界文)。

### 3.1 通した席と、通さなかった 1 席

| 席 | 箇所 | 検査 |
|---|---|---|
| CLI (matcher 経由 2 経路) | `src/extension/matcher_residents.mbt` | 通す |
| CLI (typed node) | `src/internal/engine/node_residents.mbt` | 通す |
| separator piece | `src/extension/separated.mbt` | 通す |
| config | `src/extension/config_value.mbt` | 通す |
| env | `src/kuu/resolve.mbt` の `env_value` | 通す |
| **変数 DSL operand** | `src/internal/engine/lowering.mbt` の `dsl_operand_value` | **通さない** |

最後の 1 席を外した理由はコード側に design rationale として書いた。検査が問うのは「産出値が resident の
自己宣言と矛盾するか」で、答えは args 位置に帰属する実行時の held Error である。DSL operand には
args 位置も実行時席も無く、DR-130 §3.1 が宣言側に複合リテラルの席を与えていないので、捕まえるべき
ものが構造的に存在しない。

### 3.2 reason 語彙は新設 4 綴り

エンジン発生源なので DR-066 §3 / REFERENCE §7.3 の系列だが、該当する v1 綴りが無い。kind は `parse`
(REFERENCE §7.2 の「value_parser の型照合失敗」) で、reason は:

| reason | DR-126 §4 の行 | 意味 |
|---|---|---|
| `undeclared_field` | (a) | record が名乗っていないキーを産んだ |
| `duplicate_field` | (a) 系 | 同じキーを 2 度産んだ (下記 §3.3) |
| `field_type_mismatch` | (b) | 宣言済みキーの値がフィールドの type の `out` と合わない |
| `output_shape_mismatch` | — | 産出値そのものが自己宣言の形と違う ((b) の 1 段上) |

**conformance 面には出ない。** DR-126 §4 自身が「conformance fixture は壊れた builtin parser を
注入できないため、この Error の pin は実装側テスト (wbtest 等) の領分になる」と書いており、
実際に record を名乗る builtin type factory は存在しない (§5)。REFERENCE §7.3 への追補が要るかは
spec 側の判断。

### 3.3 重複キーは (a) 系 (§9-5 の決着)

W2-3 の申し送り §9-5 は「`parse_token` が重複キーを返せる設計にするのか、返せない不変条件を置くのかを
決める必要がある」としていた。**返せない**で確定 (統括裁定 2026-08-02)。wire JSON object は重複キーを
表現できず、conformance の result 射影にも乗らない。通せば result と sources で座の数が食い違う
(W2-3 の実測: 素の JSON 綴りは後勝ちに潰れる一方 `value_to_configval` は両方の entry を保つ)。
検査は宣言型照合から独立した**生 Value 全構造走査**として先に走る (W2-5 事後監査の裁定) —
重複キーはどの宣言の下でも wire 非表現なので、`value` 宣言・`Array(Value)` の要素・record フィールドの
out=`value` のような「宣言型照合が Object の中を見ない」経路でも同じ `duplicate_field` になる。

### 3.4 `Null` はあらゆる宣言を満たす

DR-130 §1 が null を「値が無い」の普遍表現とし、§7 が型導出を全座 `T | null` とするので、
`null` の産出は宣言との矛盾ではない。検査はこれを最初に返す。

### 3.5 適用範囲は type resident の `parse_token` まで — resident 一般は W2-7 送り (段階実装)

DR-126 §4 は乖離検査を type パーサに限らず **io_type を名乗る resident 一般** (provider / filter /
cell_fns / collector) に適用すると規定するが、現実装が通しているのは `parse_token_checked` の席だけで
ある。resident 一般への配線は W2-7 の「値残余座への fn 戻り値がフィールド type の `out` への適合検査を
通る」(DR-127 §3.2) と同じ共通インフラになるため、そちらへ合流させる (issue:
`docs/issue/2026-08-02-resident-output-contract-generalization.md`)。

## 4. `element_value` の複合対応 (§9-1 の決着)

W2-3 の C-3 / C-4 は「複合セルに対して最初に abort する位置」で、RequiresIf の値比較を複合に対して
どう定義するかが W2-5 の設計判断として未決だった。

`element_value` / `element_value_in_subtree` の戻り型を **`String?` から `Value?` へ**変え、比較を
`value_matches_literal(value, literal)` に切り出した。消費者は 3 種しかなく、どれも「値の有無」か
「宣言が綴ったリテラルと一致するか」しか訊いていない:

- `!= None` — 目的語に値があるか (非 bool の `requires`)
- `== "true"` — bool 目的語
- `== v` — `value_requires` の operand

`value_requires` の operand は **wire の string** なので、綴れるのはスカラだけである。複合セル値は
「一致しない」と答えるのが正しく、スカラ綴りへ押し込む必要がない。`value_str` の abort が構造的に
到達しなくなった。

## 5. 複合値は conformance からまだ見えない — fixture (6) の前提が spec 側に無い

計画 §3 は fixture **(6)** (sources の座 re-tag) を W2-5 + W2-9 に割り当てているが、**W2-5 の分は
書けない。**

conformance の定義が使える type は builtin factory だけである。`definitions.types` は builtin factory の
config を差し替えるだけの機構で (`fixtures/value-typing/int-hex-value-space.json` が実例、
`{"name": "int_parser", "config": {...}}`)、新しいパース挙動を wire から作ることはできない。そして
`schema/builtin-descriptors.json` の `types` は `number_parser` / `int_parser` / `bool_parser` / `tty` の
4 つで、**output はすべて number か bool** — record を名乗る builtin は 1 つも無い。

つまり複合を産む住人が conformance 面に存在しない。本段が立てられた「前提」は実装側の機構と wbtest
までで、(6) を conformance へ出すには **spec に record 産出 builtin を 1 つ入れる裁定**が要る。
これは W2-3 の申し送り §9-2 (「A-6 `render_val` の abort は conformance 側の穴。複合値の fixture 綴りが
決まるまで複合を含む case は書けない」) と §9-3 (「A-3 と A-4 の綴りを fixture 側へ露出させること」) を
**綴りの問題ではなく住人の問題として**言い直したことになる。綴りを決めても書けない。

なお wbtest 側では `render_rval_sorted` の Object / Array アームが複合を扱えており、§2 の持ち上げ規則の
おかげで `test_render_val` / `render_val` の abort には到達しない。

## 6. 新たに見えた欠落 — record 座の null 補形

産出者を通したことで、**DR-130 §4 の射影表の record 行が未実装**であることが観測可能になった。
宣言 `{"record": {"since": "number", "until": "number"}}` の resident が `{"since": 1}` だけを返したとき、
規範では射影層が `until` を `null` で補うはずだが、現行の result は `{span={since=1}}` である。

本段の wbtest は**現状の挙動をそのまま pin している**。補形の実装には「その座の宣言 ValueType」を
結果射影へ通す必要があり (`build_result` は Binding / AccumCell / DefaultCell / InternalCell /
ExportScopeMap しか持たず、`ElemDef.ty` へ辿る経路が無い)、W2-6 / W2-7 の値空間降下が要求する
台帳と同じものになる。`docs/issue/2026-08-02-record-null-fill-missing-in-projection.md` へ起票した。

## 7. 同乗物 — W2-4 の不可視乖離 3 件を conformance へ出した

`fixtures/variant-effects/old-value-across-default-and-unset.json` (3 case)。W2-4 findings §1 の
F-1 / F-2 / F-4 に対応し、宣言 default を非ゼロにすることで `incr` の old が観測面に出る。
**3 件とも effects の期待値は初回実行で一致した** — 外したのは result / sources 側で、DR-130 の
全列挙 (未発火の兄弟セル `n` の default 5、未選択 scope `sub` の null) を書き落としていた分である。

F-3 (`empty` の不正 target) は見送った。検査に必要な「target が array / map / record か scalar か」の
判定が W2-6 の value_type 遷移表そのもので、ここで書くと `output_type()` が `None` を返す第三者 type や
`value` / union の扱いという W2-6 の判断を先食いする。
`docs/issue/2026-08-02-cell-fn-empty-target-type-check-missing.md` は open のまま W2-6 へ渡す。

## 8. 関連

- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-5 行 / §3 fixture (6)
- `docs/findings/2026-08-02-w2-3-value-composite-inventory.md` §9 (本段が消化した申し送り 5 件)
- `docs/findings/2026-08-02-w2-4-fold-unification.md` §1 / §5-2 (同乗物の出所)
- `docs/issue/2026-08-02-record-null-fill-missing-in-projection.md` (§6 で起票)
- `docs/issue/2026-08-02-cell-fn-empty-target-type-check-missing.md` (§7 で W2-6 へ送った)
- spec `docs/decisions/DR-126-descriptor-record-value-type.md` §2 / §4
- spec `docs/decisions/DR-130-null-result-projection.md` §4 / §4.1 / §9.1
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §6
- spec `docs/decisions/DR-122-sources-shadow-tree.md` §1 / §3
