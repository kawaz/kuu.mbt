# W2-3 棚卸し: 複合 `Value` を追加したあと、`Value` を読む全箇所がどう振る舞うか

> 対象段: `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 の W2-3 行。
> 受け入れ条件は「コンパイル通過」ではなく **本表の全件確認**である (計画 §4 リスク 2)。
> 実測日: 2026-08-02。ベースライン `just test` = 635 tests / conformance
> `decoded=394 ran_cases=885 skipped=0 mismatches=0`、両台帳空。
> 本段適用後 = 642 tests (新規 7 本) / conformance は **同値のまま**。

**分類の判断規則** (統括裁定 2026-08-02、全群共通):

- セル値経路上にあり、W2-5 以降の産出者が複合を届けうる位置 → **明示 arm で abort** (silent hole を潰す)
- 内部 marker 経路等で、産出者に関わらず複合が**構造的に到達不能**な位置 → **現挙動維持 + 本表に根拠を書く**

群の分け方: **A** = 網羅 match (コンパイラが強制)、**B** = 部分 match に明示 arm を足した箇所
(コンパイラは守らない、意図的に置いた)、**C** = `value_str` の call site、**D** = wildcard が複合を吸う箇所
(現挙動維持と判断)、**E** = `Value` に見えて別型だった箇所、**F** = test 側。
A〜E は **prod の全数**、F は分類サマリ。

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

## 1. 計画 §1.1 の数字は 3 箇所で実測と食い違う

**報告事項。以降の段が §1.1 の数字を前提に見積もると外れる。**
(計画正本 `2026-08-02-dr127-wave2-implementation-plan.md` §1.1 / §4 リスク 2 / §5 は実測へ修正済み。
本節は「何がどう違ったか」の記録として残す。)

| 主張 (計画 §1.1) | 実測 | 原因 |
|---|---|---|
| `value_str` の call site は 136 (prod 約 100)、うち宣言経路 約 102 | **全 28 (prod の実 call site は 6)** | 計画の grep が `value_str` でなく **`value_structure`** に当たっていた (`wire_decode.mbt` 35 / `help.mbt` 31 / `declaration_types.mbt` 14 はすべて `value_structure*` の別語彙)。単語境界付き `grep -rnE '\bvalue_str\b'` で 28 件 |
| `Value` を網羅 match している prod 箇所は 6 つ | **prod 4 つ** (+ test 側 5 つ) | 計画が挙げた 6 つのうち `extension/filter.mbt` は網羅 match ではなく `is @abi.Null` ガード、`extension/config_value.mbt` は `Value` ではなく **`ConfigVal`** の match。`internal/engine/eval.mbt` も `Value` ではなく `b.op` (`EffectOp`) の match で、`Value` は guard に出るだけ |
| 実行時セル値経路の `value_str` は 5 箇所 | **4 箇所** (宣言経路が 2 箇所) | 5 つの座標はすべて実在するが `resolve.mbt:3983` の分類が違う (次段落) |

§1.1 が実行時セル値経路として挙げた 5 つの座標 (`resolve.mbt:3959` / `:3983`、`eval.mbt:4300` /
`:4396`、`accumulator_residents.mbt:564`) は**すべて実在する** (末尾のものは現在 `:585`)。ただし
**分類が 1 件ずれている**: `resolve.mbt:3983` は `default_scalar(e)` を読む位置で、実行時セル値では
なく宣言 default である。したがって実行時セル値経路は **4**、宣言経路は **2** (下表 B 群)。

**§1.1 の結論そのものは実測でも成立する。** 宣言経路の母数が約 102 でなく 2 だっただけで、
「宣言経路には複合が来ないことが構造的に言える」という論証は母数が小さくなった分むしろ強い。
一方 **`value_str` を `Result` 返しに変える案の前提だったコスト (影響 136 箇所) は消える** —
実際の影響は 6 箇所しかない。それでも abort 維持を選ぶ理由は §4 に書く。

## 2. A 群 — 網羅 match (コンパイラが強制、arm 追加済み)

`moon check --deny-warn` が 1 件ずつ指した全件。ここは漏れが構造的に起きない。

| # | 箇所 | 何をする関数か | 複合の扱い |
|---|---|---|---|
| A-1 | `src/abi/value.mbt` `value_str` | 値のスカラ綴り | **abort 維持** (根拠は C 群) |
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
(`String("1")` と `Number(1)` を畳ませない)。両者の綴りは
`accumulator_residents_wbtest.mbt` / `node_residents_wbtest.mbt` の wbtest で pin 済み。

## 3. B 群 — 部分 match に明示 arm を足した箇所 (コンパイラは守らない)

`match` が wildcard を持つため**コンパイラは何も言わない**が、セル値経路上にあり産出者が複合を
届けうるので、判断規則に従って明示 arm で abort させた箇所。スカラの現挙動は 1 つも変えていない。

| # | 箇所 | wildcard の元挙動 | 複合を abort にした理由 |
|---|---|---|---|
| B-1 | `src/extension/accumulator_residents.mbt` `KvMapAccumulator::collect` | `_ => ""` (非 String を空文字へ) | **セル値経路** (accumulator の行供給)。複合には `key=value` の綴りが無く、`""` に潰すと**全ての複合 piece が同一の空キーに合流して silent に上書きし合う**。A-1 と同じ precedent で abort |
| B-2 | `src/extension/accumulator_residents.mbt` `KvMapAccumulator::collect_sources` | `_ => ""` | B-1 と対。同じセル値がキー導出に 2 度使われるので、片方だけ塞ぐと result と sources がずれる |
| B-3 | `src/kuu/completion.mbt` `#completion_script` セルの読み | `_ => ()` (非 String を黙って無視) | セル値経路。複合を無視すると「補完が要求されなかった」に化ける。**構造的到達不能とは言い切れない** — 到達不能性が `CompletionScriptTypeExt::parse_token` が `String` 固定であることに依存しており、D-11 のように lowering が値を直接構築する形ではないため、判断規則の「言い切れないなら abort」側に倒した |

**B-1 / B-2 は初版の棚卸しで完全に漏れていた** (D 群にも挙げていなかった)。`value_str` と
コンパイラエラーを軸に探したため、`match value { @abi.String(text) => text; _ => "" }` という
**`value_str` を経由しないスカラ取り出し**の形が視界に入っていなかった。本版は §10 の
機械走査で洗い直している。

## 4. C 群 — `value_str` の全 call site (コンパイラが守らない = 本段の主題)

prod の実 call site は 6。`src/extension/abi_aliases.mbt:45` と
`src/internal/engine/layer_aliases.mbt:48` は re-export であって call site ではない。

| # | 箇所 | 経路 | 複合が来ないと言える根拠 |
|---|---|---|---|
| C-1 | `src/kuu/resolve.mbt:3959` | 実行時セル値 — `config_file` 要素の CLI 束縛からパス文字列を取る | 当該要素は `is_config_file` で、その `TypeExt` の `parse_token` は `String` しか返さない。CLI 席に座る値は必ずその parse を通っている |
| C-2 | `src/kuu/resolve.mbt:3983` | 宣言 default — 同じ `config_file` 要素の `default_scalar(e)` | 関数名どおりスカラ席。宣言 default は `wire_decode` が JSON literal から `String`/`Number`/`Bool` として組む (DR-083 §2)。複合リテラルの席が無い (DR-130 §3.1) |
| C-3 | `src/internal/engine/eval.mbt:4300` (`element_value`) | 実行時セル値 — RequiresIf の値比較 | 束縛の `value` は CLI 席 = `parse_token` の出力か、`mk_binding` が置く宣言定数。どちらも現状スカラのみ。**W2-5 で複合産出が入った瞬間ここが最初に落ちる** |
| C-4 | `src/internal/engine/eval.mbt:4396` (`element_value_in_subtree`) | 同上 (`RequiredCandidate.wrapper` 対応版) | C-3 と同一 |
| C-5 | `src/extension/accumulator_residents.mbt:585` (`result_key`) | 実行時セル値 — `from_entries` のキー導出 | `ResultValue::Scalar` の中身。セル値なので C-3 と同じ根拠。なお `Array`/`Object` の **`ResultValue`** は既に `result_value_json` 経由で扱われている (A-3) — 落ちるのは「`Scalar` に複合 `Value` が入る」形だけ |
| C-6 | `src/internal/engine/lowering.mbt:920` (`child_default_seat_key`) | **宣言経路** — 構造 or/seq 子の default 席キーを組む | `e.default_values` は宣言 default。C-2 と同じ根拠 |

test 側の `value_str` call site (`resolve_wbtest.mbt` 13 / `eval_wbtest.mbt` 2 /
`json_conformance_test.mbt` 1) は、いずれも wbtest 自身が構築したスカラを読み戻す表明であり、
複合を渡す経路はテストコード内に存在しない。

実行時セル値経路は **C-1 / C-3 / C-4 / C-5 の 4 件**、宣言経路は **C-2 / C-6 の 2 件**。
計画 §1.1 は C-2 を実行時側に数えて「実行時 5」としていた (§1 参照)。

## 5. なぜ `Result` 化でなく abort を維持したか (統括裁定 2026-08-02 で確定)

計画 §4 リスク 2 は「棚卸し + abort 維持を推す」としつつ、根拠に「影響 136 箇所」を挙げていた。
§1 のとおりその数字は誤りで、実際は 6 箇所なので**コストは論拠にならない**。それでも abort 維持で
確定 (統括裁定)。効いているのは以下の構造上の理由:

- `value_str` は「この値のスカラ綴りをくれ」という要求であって、**複合はその要求自体が成り立たない
  文脈からしか呼ばれない**。C-1〜C-6 はどれも「ここに複合が座ったら上流の型判定が既に壊れている」
  位置であり、呼び出し側に `Result` を配っても書けるのは「起きえないはずの分岐」だけになる
  (= 到達不能コードを 6 箇所生やす)
- 逆に abort は、W2-5 で産出者が入った瞬間に **C-3/C-4 が最初に、はっきり落ちる**。silent hole を
  作らないという本段の目的に対しては abort の方が強い網である
- `Result` 化が正当になるのは「複合が来ることが正常で、呼び出し側に意味のある分岐がある」場合。
  それは W2-6 の値空間降下 (record のフィールド当たり判定など) の責務であって、
  スカラ綴り関数の責務ではない

## 6. D 群 — wildcard が複合を吸う箇所 (現挙動維持と判断した全件)

コンパイラが黙る箇所のうち、判断規則の**後段** (構造的に到達不能、または複合が落ちる arm の
振る舞いがそもそも正しい) に当たると判断したもの。**全件、abort せず定義済みの振る舞いに落ちる**。
判断規則の前段に当たったもの (= abort へ倒したもの) は B 群にある。

| # | 箇所 | 複合が落ちる arm | その振る舞いは妥当か |
|---|---|---|---|
| D-1 | `src/extension/filters.mbt` `filter_trim` / `filter_non_empty` | `other => Ok(other)` | 妥当。string 専用フィルタの非 string 素通しは既存の防御的既定そのまま |
| D-2 | `src/extension/filters.mbt` `filter_in_range` / `filter_increment` | `_ => Err(filter_rejected)` | 妥当。number 専用フィルタが複合を受けたら拒否が正しい |
| D-3 | `src/extension/filters.mbt` `filter_regex_match` | `_ => Err(...)` | D-2 と同型 |
| D-4 | `src/extension/filter.mbt:185` `apply_filter_chain` | `Null` だけ早期 return、複合は chain へ流れ D-1〜D-3 に至る | 妥当 (D-1〜D-3 が受け止める) |
| D-5 | `src/extension/cell_fns.mbt:66` `incr_fn` | `Some(_) => Err("incr requires a number target")` | 妥当 |
| D-6 | `src/kuu/resolve.mbt:219` `fixed_tuple_arity` | `_ => ()` | 妥当。複合は `[]` の arity マーカーではないので「マーカーでない」判定が正しい |
| D-7 | `src/internal/engine/outcome.mbt:78` `collect_actions` | `_ => 0` | 妥当。失敗アクションマーカー束縛の値は構築時から `Number` 固定 |
| D-8 | `src/internal/engine/eval.mbt:4265/4374` (`is_committed*`) | `Set if value is Null` に当たらず `_ => committed = true` | 妥当。複合が座っていれば「値が確定している」= committed で正しい |
| D-9 | `src/extension/accumulator_residents.mbt:38/190/245` | 同様に `Set` の一般 arm | 妥当。accumulator は piece を不透明に運ぶだけ |
| D-10 | `src/kuu/resolve.mbt:3310` | `FnOutput::Value(v)` の `v is Null` ガード、複合は通常の `Set` 束縛になる | 妥当。cell fn の出力を不透明に運ぶ位置 |
| D-11 | `src/kuu/resolve.mbt:2670` — `#seat:` 束縛から target 要素名を取る | `_ => ""` | **構造的に到達不能**。`#seat:` 束縛の value を作るのは lowering の `Bind(child_default_seat_key(e), String(e.name))` (`lowering.mbt:990` / `:1223`) の 2 箇所だけで、**`parse_token` を一切通らない**。産出者が何を返せるようになっても `String` のまま。同趣旨の不変条件をコードコメントにも置いた |

## 7. E 群 — `Value` に見えて別型だった箇所 (誤検知の記録)

計画や素朴な grep が `Value` の match と取り違えやすい箇所。**本段の対象外**であることを確認した。

- **`ConfigVal`**: `src/extension/config_value.mbt:53` (境界の番人そのもの、`Array`/`Object` は既に
  `config_structural_mismatch` を返している) / `src/kuu/resolve.mbt:3458` / `src/kuu/resolve.mbt:2964`
  (`config_lookup`)
- **`ResultValue`**: `src/kuu/front_door.mbt:455` / `:478` / `:483` / `:496` / `src/kuu/resolve.mbt:1725` /
  `:1745` / `:1893` / `src/extension/accumulator_residents.mbt:462` / `:570` / `:599` / `:618` / `:649` /
  `:664` / `:706` / `:757` / `:759` / `:801` (いずれも `Scalar` の**中身までは見ない** — 中身を見る
  `result_key` だけが C-5 として C 群にある)
- **`ValueType`** (W2-2 で入った別体系): `src/abi/value_type.mbt:63` /
  `src/internal/engine/lowering.mbt:2202` (`value_type_primitive_only`) / `:4144`
- **`Json`**: `src/abi/value.mbt:96` (`config_from_json`) /
  `src/extension/accumulator_residents.mbt:525` / `src/builtins/installer_residents.mbt` 7 箇所
- **`FilterInput`**: `src/extension/filter.mbt:83` / `:163` (`Scalar` / `Array` は filter 入力の別 enum)
- **`LongDeclaration`**: `src/internal/engine/installer_ext.mbt:248` /
  `src/internal/engine/lowering.mbt:193` / `:375` / `:3635` / `:3694` (`Bool` の綴りが `Value` と衝突する)
- **`ExportKey`**: `src/internal/engine/node.mbt:49` (`resolved_export_key`)
- **`FnKind`**: `src/extension/cell_fn.mbt:270` (`String` / `Value` の綴りが衝突する)

## 8. F 群 — test 側 (分類サマリ)

prod の A〜E は全数だが、test 側は件数が多く性質が一様なので分類でまとめる。**共通の根拠は
「テストが入力を自分で構築している」**こと — 複合を渡す経路がテストコード内に存在しない。

| 分類 | 例 | 複合の扱い |
|---|---|---|
| 網羅 match の描画関数 | `installer_wbtest.mbt` `dd_value_to_str` / `json_conformance_test.mbt` `render_val` `help_value_json` / `lower_conformance_wbtest.mbt` `render_val` / `test_helpers_wbtest.mbt` `test_render_val` | A-5〜A-9 として A 群に列挙済み (コンパイラが指した) |
| 部分 match の表明 | `internal/engine/eval_wbtest.mbt` の `@abi.String(s) => ...` 群 (約 14 箇所)、`kuu/registry_wbtest.mbt` の束縛値 assert 2 箇所 | wildcard か assert 失敗に落ちる。テストが構築したスカラを読み戻すだけ |
| 三者フィルタの pass-through | `registry_wbtest.mbt` の `ThirdPartyFilter` (`@abi.String(text) => ...; other => Ok(other)`) | D-1 と同型 (素通し) |
| `value_str` の呼び出し | `resolve_wbtest.mbt` 13 / `eval_wbtest.mbt` 2 / `json_conformance_test.mbt` 1 | 同上 |
| 複合を**構築する**新規 wbtest | `abi/value_wbtest.mbt` 3 本 / `accumulator_residents_wbtest.mbt` 3 本 / `node_residents_wbtest.mbt` 1 本 | 本段が足した器の表明そのもの |

## 9. 後続段への申し送り

1. **W2-5 (産出者を通す) は本表を再訪する義務がある。** 特に D-3 / D-4 (`element_value*`) が
   複合セルに対して最初に abort する位置であり、RequiresIf の値比較を複合に対してどう定義するかは
   W2-5 の設計判断として未決。
2. **A-6 (`render_val`) の abort は conformance 側の穴。** 複合値の fixture 綴りが決まるまで
   複合を含む case は書けない。fixture (2)(5)(6) を起こす段 (W2-7 / W2-9) と同じウィンドウで決める。
3. **A-3 と A-4 の綴りは今のところどの fixture にも pin されていない。** 産出者が入るまで観測不能なので、
   W2-5 で最初の複合産出型を立てたときに両方を fixture 側へ露出させること。
4. `ResultValue` と `Value` の統合是非は計画どおり W2-5。本段では両者の複合 arm が
   **独立に**書かれた状態になっている (A-3 が両方を跨ぐ唯一の関数)。

## 10. 全数性の担保 — 再走査の方法

初版が B-1 / B-2 を落としたのは、探し方が `value_str` の call site とコンパイラエラーの 2 経路
だけだったため。**どちらも「wildcard 付き match で Value からスカラを取り出す」形を拾わない。**
本版は 3 経路目として、prod 全 `.mbt` の `match` ブロックを機械走査して arm 集合を出し、
Value 型の match を目視分類した。再走査は下記で再現できる:

```
python3 - <<'PY'   # src/ の非 test .mbt から、arm に Value 構成子を含む match を全列挙
import re, pathlib
VC = re.compile(r'^\s*(?:@abi\.)?(String|Number|Bool|Null|Array|Object)\s*[\(_ =]')
for p in pathlib.Path('src').rglob('*.mbt'):
    if p.name.endswith(('_wbtest.mbt','_test.mbt')): continue
    lines = p.read_text(encoding='utf-8').split('\n')
    for i,l in enumerate(lines):
        m = re.search(r'\bmatch\b(.*)\{\s*$', l)
        if not m: continue
        indent = len(l)-len(l.lstrip()); arms=[]; j=i+1
        while j < len(lines) and j < i+80:
            cur = lines[j]
            if cur.strip() and (len(cur)-len(cur.lstrip()))<=indent and cur.strip().startswith('}'): break
            if (len(cur)-len(cur.lstrip()))==indent+2 and '=>' in cur:
                arms.append(cur.strip().split('=>')[0].strip())
            j+=1
        if any(VC.match(a+' ') for a in arms):
            print(f"{p}:{i+1} match {m.group(1).strip()} :: {arms}")
PY
```

2026-08-02 の実行結果は候補 **56 ブロック**。うち `Value` の match は **15** で、内訳は
A 群 4 (網羅) + B 群 3 (明示 arm) + D 群 8 (wildcard 維持)。残る 41 は E 群の別型
(`ConfigVal` / `ResultValue` / `Json` / `ValueType` / `FilterInput` / `LongDeclaration` /
`ExportKey` / `FnKind`) である。

**この走査でも拾えない形**が 2 つあり、そこは grep で補っている:

- `match` を使わない guard (`if value is @abi.Null`) — D-4
- 別型を剥がしてから Value を見る形 (`Some(@abi.Value::Number(v))` / `match b.op` の中で
  `b.value is Null` を見る) — D-5 / D-8 / D-9 / D-10

## 関連

- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §1.1 / §2 W2-3 行 / §4 リスク 2
- spec `docs/decisions/DR-130-null-result-projection.md` §9.1 (`ConfigVal` 非統合の根拠)
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §2.2 (複合値を要求する当の規範)
