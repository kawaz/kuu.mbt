# W2-3 棚卸し: 複合 `Value` を追加したあと、`Value` を読む全箇所がどう振る舞うか

> 対象段: `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 の W2-3 行。
> 受け入れ条件は「コンパイル通過」ではなく **本表の全件確認**である (計画 §4 リスク 2)。
> 実測日: 2026-08-02。ベースライン `just test` = 635 tests / conformance
> `decoded=394 ran_cases=885 skipped=0 mismatches=0`、両台帳空。
> 本段適用後 = 639 tests (新規 4 本) / conformance は **同値のまま**。

## 0. 本段で `Value` に起きたこと

`src/abi/value.mbt`:

```
pub(all) enum Value { Null; String(String); Number(Double); Bool(Bool)
                      Array(Array[Value]); Object(Array[(String, Value)]) }
```

**産出者は 1 つも作っていない。** `parse_token` は依然スカラしか返さず、config 経路
(`config_to_value`) は複合を `config_structural_mismatch` で弾き、宣言 default リテラルの
decode (`wire_decode.mbt`) もスカラしか組まない。したがって本段の後も、**実行中の
`Binding.value` / セル値・`ResultValue::Scalar` の中身が `Array`/`Object` になる経路は存在しない**。
本表の「到達しない根拠」はすべてこの一点に帰着する。産出者が入るのは W2-5
(`TypeExt::parse_token` の複合対応) であり、その段で本表を再訪する義務がある。

`ConfigVal` は統合していない。理由 (DR-130 §9.1) は `Value` の doc comment に design rationale
として書いた — `ConfigVal::Null` は「その config 席は供給しない」(DR-050)、`Value::Null` は
「値が null」で層が違い、`config_to_value` が唯一守っている境界が型から消えるため。
`ResultValue` も触っていない (統合の是非は計画どおり W2-5 へ持ち越し)。

## 1. 計画 §1.1 の数字は 2 箇所で実測と食い違う

**報告事項。以降の段が §1.1 の数字を前提に見積もると外れる。**

| 主張 (計画 §1.1) | 実測 | 原因 |
|---|---|---|
| `value_str` の call site は 136 (prod 約 100)、うち宣言経路 約 102 | **全 28 (prod の実 call site は 6)** | 計画の grep が `value_str` でなく **`value_structure`** に当たっていた (`wire_decode.mbt` 35 / `help.mbt` 31 / `declaration_types.mbt` 14 はすべて `value_structure*` の別語彙)。単語境界付き `grep -rnE '\bvalue_str\b'` で 28 件 |
| `Value` を網羅 match している prod 箇所は 6 つ | **prod 4 つ** (+ test 側 5 つ) | 計画が挙げた 6 つのうち `extension/filter.mbt` は網羅 match ではなく `is @abi.Null` ガード、`extension/config_value.mbt` は `Value` ではなく **`ConfigVal`** の match。`internal/engine/eval.mbt` も `Value` ではなく `b.op` (`EffectOp`) の match で、`Value` は guard に出るだけ |

一方 **§1.1 の結論そのものは実測でも成立する**: 「実行時セル値経路の `value_str` は 5 箇所」は
正確 (下表 B-1〜B-5 がその 5 つ)。宣言経路の母数が約 102 でなく 1 だっただけで、
「宣言経路には複合が来ないことが構造的に言える」という論証は母数が小さくなった分むしろ強い。
**`value_str` を `Result` 返しに変える案 (影響 136 箇所) の前提だったコストも消える** —
実際の影響は 6 箇所しかない。それでも abort 維持を選ぶ理由は §4 に書く。

## 2. A 群 — 網羅 match (コンパイラが強制、arm 追加済み)

`moon check --deny-warn` が 1 件ずつ指した全件。ここは漏れが構造的に起きない。

| # | 箇所 | 何をする関数か | 複合の扱い |
|---|---|---|---|
| A-1 | `src/abi/value.mbt` `value_str` | 値のスカラ綴り | **abort 維持** (根拠は B 群) |
| A-2 | `src/abi/value.mbt` `value_to_configval` | 宣言 default piece を config array と同型に扱う橋 (DR-083 §2) | **再帰変換を追加**。`ConfigVal` は同じ形を持つので全域関数になる |
| A-3 | `src/extension/accumulator_residents.mbt` `result_value_json` の `Scalar` arm | `from_entries` のキー導出・merge collector の行描画 | **再帰 JSON 化を追加** (`scalar_value_json` に切り出し)。素の JSON (型タグなし) |
| A-4 | `src/internal/engine/node_residents.mbt` `value_json` | **node 同一性**の直列形 (`NodeExt::equal` が kind + encode で畳む) | **タグ付き再帰を追加** (`["array", [...]]` / `["object", [[k,v],...]]`)。object は field を**リストのまま**保つ — 順列違いを別 node にするため |
| A-5 | `src/kuu/installer_wbtest.mbt` `dd_value_to_str` | dd pattern operand の描画 | abort ("dd pattern operand は複合にならない") |
| A-6 | `src/kuu/json_conformance_test.mbt` `render_val` | **conformance の値比較綴り** | abort。複合の fixture 語彙は産出者と同時に決まる (W2-5 / W2-9)。ここで綴りを発明すると spec 先行になる |
| A-7 | `src/kuu/json_conformance_test.mbt` `help_value_json` | help の declared default 描画 | abort (DR-130 §3.1 で宣言側に複合リテラルの席がない) |
| A-8 | `src/kuu/lower_conformance_wbtest.mbt` `render_val` | lowering conformance の宣言定数描画 | abort |
| A-9 | `src/kuu/test_helpers_wbtest.mbt` `test_render_val` | wbtest 共用の値描画 | abort |

A-3 と A-4 が **別の綴りを持つ**のは意図的で、責務が違う (片方は利用者が読む値、もう片方は
node 同一性の鍵)。A-4 だけが型タグを持つ理由は既存 doc comment のとおり
(`String("1")` と `Number(1)` を畳ませない)。

## 3. B 群 — `value_str` の全 call site (コンパイラが守らない = 本段の主題)

prod の実 call site は 6。`src/extension/abi_aliases.mbt:45` と
`src/internal/engine/layer_aliases.mbt:48` は re-export であって call site ではない。

| # | 箇所 | 経路 | 複合が来ないと言える根拠 |
|---|---|---|---|
| B-1 | `src/kuu/resolve.mbt:3959` | 実行時セル値 — `config_file` 要素の CLI 束縛からパス文字列を取る | 当該要素は `is_config_file` で、その `TypeExt` の `parse_token` は `String` しか返さない。CLI 席に座る値は必ずその parse を通っている |
| B-2 | `src/kuu/resolve.mbt:3983` | 宣言 default — 同じ `config_file` 要素の `default_scalar(e)` | 関数名どおりスカラ席。宣言 default は `wire_decode` が JSON literal から `String`/`Number`/`Bool` として組む (DR-083 §2)。複合リテラルの席が無い (DR-130 §3.1) |
| B-3 | `src/internal/engine/eval.mbt:4300` (`element_value`) | 実行時セル値 — RequiresIf の値比較 | 束縛の `value` は CLI 席 = `parse_token` の出力か、`mk_binding` が置く宣言定数。どちらも現状スカラのみ。**W2-5 で複合産出が入った瞬間ここが最初に落ちる** |
| B-4 | `src/internal/engine/eval.mbt:4396` (`element_value_in_subtree`) | 同上 (`RequiredCandidate.wrapper` 対応版) | B-3 と同一 |
| B-5 | `src/extension/accumulator_residents.mbt:585` (`result_key`) | 実行時セル値 — `from_entries` のキー導出 | `ResultValue::Scalar` の中身。セル値なので B-3 と同じ根拠。なお `Array`/`Object` の **`ResultValue`** は既に `result_value_json` 経由で扱われている (A-3) — 落ちるのは「`Scalar` に複合 `Value` が入る」形だけ |
| B-6 | `src/internal/engine/lowering.mbt:920` (`child_default_seat_key`) | **宣言経路** — 構造 or/seq 子の default 席キーを組む | `e.default_values` は宣言 default。B-2 と同じ根拠 |

test 側の `value_str` call site (`resolve_wbtest.mbt` 13 / `eval_wbtest.mbt` 2 /
`json_conformance_test.mbt` 1) は、いずれも wbtest 自身が構築したスカラを読み戻す表明であり、
複合を渡す経路はテストコード内に存在しない。

**5 = B-1〜B-5 が計画 §1.1 の言う「実行時セル値経路の 5 箇所」**で、実測と一致した。

## 4. なぜ `Result` 化でなく abort を維持したか

計画 §4 リスク 2 は「棚卸し + abort 維持を推す」としつつ、根拠に「影響 136 箇所」を挙げていた。
§1 のとおりその数字は誤りで、実際は 6 箇所なので**コストは論拠にならない**。改めて設計上の
理由で abort を選ぶ:

- `value_str` は「この値のスカラ綴りをくれ」という要求であって、**複合はその要求自体が成り立たない
  文脈からしか呼ばれない**。B-1〜B-6 はどれも「ここに複合が座ったら上流の型判定が既に壊れている」
  位置であり、呼び出し側に `Result` を配っても書けるのは「起きえないはずの分岐」だけになる
  (= 到達不能コードを 6 箇所生やす)
- 逆に abort は、W2-5 で産出者が入った瞬間に **B-3/B-4 が最初に、はっきり落ちる**。silent hole を
  作らないという本段の目的に対しては abort の方が強い網である
- `Result` 化が正当になるのは「複合が来ることが正常で、呼び出し側に意味のある分岐がある」場合。
  それは W2-6 の値空間降下 (record のフィールド当たり判定など) の責務であって、
  スカラ綴り関数の責務ではない

## 5. C 群 — 網羅でない `Value` の読み (wildcard が複合を吸う箇所)

コンパイラが黙る箇所。**全件、abort せず定義済みの振る舞いに落ちる**ことを確認した。

| # | 箇所 | 複合が落ちる arm | その振る舞いは妥当か |
|---|---|---|---|
| C-1 | `src/extension/filters.mbt` `filter_trim` / `filter_non_empty` | `other => Ok(other)` | 妥当。string 専用フィルタの非 string 素通しは既存の防御的既定そのまま |
| C-2 | `src/extension/filters.mbt` `filter_in_range` / `filter_increment` | `_ => Err(filter_rejected)` | 妥当。number 専用フィルタが複合を受けたら拒否が正しい |
| C-3 | `src/extension/filters.mbt` `filter_regex_match` | `_ => Err(...)` | C-2 と同型 |
| C-4 | `src/extension/filter.mbt:185` `apply_filter_chain` | `Null` だけ早期 return、複合は chain へ流れ C-1〜C-3 に至る | 妥当 (C-1〜C-3 が受け止める) |
| C-5 | `src/extension/cell_fns.mbt:66` `incr_fn` | `Some(_) => Err("incr requires a number target")` | 妥当 |
| C-6 | `src/kuu/resolve.mbt:219` `fixed_tuple_arity` | `_ => ()` | 妥当。複合は `[]` の arity マーカーではないので「マーカーでない」判定が正しい |
| C-7 | `src/internal/engine/outcome.mbt:78` `collect_actions` | `_ => 0` | 妥当。失敗アクションマーカー束縛の値は構築時から `Number` 固定 |
| C-8 | `src/internal/engine/eval.mbt:4265/4374` (`is_committed*`) | `Set if value is Null` に当たらず `_ => committed = true` | 妥当。複合が座っていれば「値が確定している」= committed で正しい |
| C-9 | `src/extension/accumulator_residents.mbt:38/190/245` | 同様に `Set` の一般 arm | 妥当。accumulator は piece を不透明に運ぶだけ |
| C-10 | `src/kuu/resolve.mbt:3310` | `FnOutput::Value(v)` の `v is Null` ガード、複合は通常の `Set` 束縛になる | 妥当。cell fn の出力を不透明に運ぶ位置 |

## 6. D 群 — `Value` に見えて別型だった箇所 (誤検知の記録)

計画や素朴な grep が `Value` の match と取り違えやすい箇所。**本段の対象外**であることを確認した。

- `src/extension/config_value.mbt:53` — `ConfigVal` の match (境界の番人そのもの、`Array`/`Object` は
  既に `config_structural_mismatch` を返している)
- `src/kuu/resolve.mbt:3458` — `ConfigVal` の match
- `src/internal/engine/lowering.mbt:2203` `value_type_primitive_only` — `ValueType` (W2-2 で入った別体系) の match
- `src/internal/engine/node.mbt:50` `resolved_export_key` — `ExportKey` の match
- `src/kuu/front_door.mbt:484` / `src/kuu/resolve.mbt:1893` — `ResultValue` の match (`Scalar` の中身までは見ない)

## 7. 後続段への申し送り

1. **W2-5 (産出者を通す) は本表を再訪する義務がある。** 特に B-3 / B-4 (`element_value*`) が
   複合セルに対して最初に abort する位置であり、RequiresIf の値比較を複合に対してどう定義するかは
   W2-5 の設計判断として未決。
2. **A-6 (`render_val`) の abort は conformance 側の穴。** 複合値の fixture 綴りが決まるまで
   複合を含む case は書けない。fixture (2)(5)(6) を起こす段 (W2-7 / W2-9) と同じウィンドウで決める。
3. **A-3 と A-4 の綴りは今のところどの fixture にも pin されていない。** 産出者が入るまで観測不能なので、
   W2-5 で最初の複合産出型を立てたときに両方を fixture 側へ露出させること。
4. `ResultValue` と `Value` の統合是非は計画どおり W2-5。本段では両者の複合 arm が
   **独立に**書かれた状態になっている (A-3 が両方を跨ぐ唯一の関数)。

## 関連

- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §1.1 / §2 W2-3 行 / §4 リスク 2
- spec `docs/decisions/DR-130-null-result-projection.md` §9.1 (`ConfigVal` 非統合の根拠)
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §2.2 (複合値を要求する当の規範)
