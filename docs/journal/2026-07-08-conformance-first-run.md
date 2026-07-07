# 2026-07-08 conformance harness 初回実食

Task 5 (conformance harness 移植) の初回 fixture 実食記録。

## 前提

- 移植先: `src/core/json_conformance_wbtest.mbt` (約 3200 行)
- 移植元: `kawaz/kuu.mbt` slice/poc の `json_conformance_wbtest.mbt` + `lower_runner_wbtest.mbt` + `helpers_wbtest.mbt` + `fixture_runner_wbtest.mbt` (必要部分のみ 1 ファイル集約)
- 台帳 (`expected_skips` / `known_divergences`) は空で開始 (MDR-001 §6)
- fixture 正本: `~/.local/share/repos/github.com/kawaz/kuu/main/fixtures` (兄弟リポ)

再現コマンド:

```
cd ~/.local/share/repos/github.com/kawaz/kuu.mbt/main
KUU_FIXTURES=$HOME/.local/share/repos/github.com/kawaz/kuu/main/fixtures moon test --target native
```

fmt / check ベースライン:

```
moon fmt      # ok
moon check    # 0 errors, 123 warnings (deprecated Map::new / Option.or / Json.as_object 由来、大半は既存コード)
```

## 実食結果 (概数)

- decoded=**109** (parse 82 fixture + lower 20 fixture + それ以外 7 相当)
- ran_cases=**267**
- skipped=**6**
- mismatches=**20**

## skip 6 件 (histogram)

| 件数 | 理由 |
|:---:|:---|
| 1 | `nested-group positional (repeat over a named sub-sequence): slice ElemDef is flat, parse_definition builds no IdxRepeat with a distinct inner-element name/export_key` |
| 1 | `variable-arity or-option (branches are consumption grammars — a seq of typed cells vs a single typed cell): slice ElemDef carries one value cell per option and dec_or models only value-enum exact-branches, so parse_definition has no builder for Or([Seq([NumArg,…]),StrArg]) at the §5 contract path` |
| 2 | `structural or-positional (branches are consumption grammars binding distinct named cells): slice ElemDef is flat with one value cell per element — lower_positional builds a single value_prim per positional, so parse_definition has no builder for Or([Seq([…]),…]) at the §5 contract path` |
| 2 | `definition has unsupported key 'definitions'` |

### fixture 対応

| rel | 理由分類 |
|:---|:---|
| `export-key/transparent-seq.json` | nested-group positional |
| `path-search/variable-arity-ambiguous.json` | variable-arity or-option |
| `path-search/held-errors-distinct-depth.json` | structural or-positional |
| `path-search/held-errors-same-depth.json` | structural or-positional |
| `value-typing/int-round-modes.json` | definitions key |
| `value-typing/number-base-prefix-optin.json` | definitions key |

いずれも slice 側の `expected_skips` と同一の未対応語彙 (dec_positional / dec_or の capability gate に引っかかる)。理由文字列を新実装側の DecodeSkip メッセージと byte-identical に維持済み。

## divergence 20 件全文

以下、runner が出力した `rel::slug :: verdict` の byte-identical な観測全リスト。

```
constraints-parse/default-interaction.json::value-branch-cli-trigger :: errors got={format@2/constraint/requires_violated} want={fmt_json@2/constraint/requires_violated}
constraints-parse/requires.json::value-requires-violated :: errors got={format@2/constraint/requires_violated} want={fmt_json@2/constraint/requires_violated}
export-key/collision.json::co-exposure-collision :: EXPECTED-AMBIGUOUS got=ok{a=true,b=true}
matcher-readings/cluster-split-no-flag.json::no-flag-suffix-error :: errors got={@0/parse/unexpected_token} want={n@0/parse/not_a_number}
path-search/ambiguous-receptacles.json::zero-tokens-unique-split :: EXPECTED-SUCCESS got=fail:missing operand for xs
path-search/ambiguous-receptacles.json::one-token-greedy-left :: EXPECTED-SUCCESS got=fail:missing operand for ys
path-search/ambiguous-receptacles.json::two-tokens-greedy-left :: effects got=xs:set(a)@cli,ys:set(b)@cli want= | result got={xs=[a],ys=[b]} want={xs=[a,b],ys=[]}
repeat-parse/max-finite.json::over-max-four :: errors got={@1/parse/unexpected_token,@2/parse/unexpected_token,@3/parse/unexpected_token} want={@3/parse/unexpected_token}
repeat-parse/preference-lazy.json::lazy-shortest-left :: effects got=xs:set(a)@cli,xs:set(b)@cli,xs:set(c)@cli,xs:set(d)@cli,ys:set(e)@cli want=xs:set(a)@cli,ys:set(b)@cli,ys:set(c)@cli,ys:set(d)@cli,ys:set(e)@cli | result got={xs=[a,b,c,d],ys=[e]} want={xs=[a],ys=[b,c,d,e]}
value-typing/bool-canonical.json::true-word :: EXPECTED-SUCCESS got=fail:unexpected token
value-typing/bool-canonical.json::one-numeric :: EXPECTED-SUCCESS got=fail:unexpected token
value-typing/bool-canonical.json::true-mixedcase :: EXPECTED-SUCCESS got=fail:unexpected token
value-typing/bool-canonical.json::true-upper :: EXPECTED-SUCCESS got=fail:unexpected token
value-typing/bool-canonical.json::false-word :: EXPECTED-SUCCESS got=fail:unexpected token
value-typing/bool-canonical.json::zero-numeric :: EXPECTED-SUCCESS got=fail:unexpected token
value-typing/bool-canonical.json::empty-false :: EXPECTED-SUCCESS got=fail:unexpected token
value-typing/bool-canonical.json::yes-rejected :: errors got={@0/parse} want={enabled@0/parse}
value-typing/int-value-space.json::fractional-value-rejected :: EXPECTED-FAILURE got=ok{v=2.5}
value-typing/number-inf-nan.json::inf-on-float-accepted :: EXPECTED-SUCCESS got=fail:"inf" is not a number
value-typing/number-inf-nan.json::inf-case-insensitive-on-float :: EXPECTED-SUCCESS got=fail:"Infinity" is not a number
```

## 分類 (slice-inherited 17 / 新実装 delta 3)

### 分類根拠

slice の `known_divergences` (git blame 起点は slice/poc/json_conformance_wbtest.mbt) と一件ずつ突合:

- **slice-inherited** = slice ledger にも同種の verdict が積まれていた (slice の実装ギャップと同根、fixture-first で「引き継がれた」もの)
- **新実装 delta** = slice ledger に**該当 case が無い**、または slice が別 verdict で ledger 済で今回は verdict が変化 (現行 kuu.mbt/main で新たに顕現した挙動差)

### slice-inherited 17 件 — `known_divergences()` に投入する

| # | rel::slug | 分類根拠 (slice ledger との対応) |
|:---:|:---|:---|
| 1 | `constraints-parse/default-interaction.json::value-branch-cli-trigger` | slice 同 verdict (value-branch id attribution DR-052/055; reason opt-in で `/requires_violated` 追加) |
| 2 | `constraints-parse/requires.json::value-requires-violated` | 同上 |
| 3 | `export-key/collision.json::co-exposure-collision` | slice 同 verdict (EXPECTED-AMBIGUOUS: collision→Ambiguous 未実装 / claimants provenance 未実装) |
| 4 | `path-search/ambiguous-receptacles.json::zero-tokens-unique-split` | slice 同 verdict (DR-043 取り分未実装、min:0 repeat を >=1 で lower) |
| 5 | `path-search/ambiguous-receptacles.json::one-token-greedy-left` | 同上 |
| 6 | `path-search/ambiguous-receptacles.json::two-tokens-greedy-left` | 同上 |
| 7 | `value-typing/bool-canonical.json::true-word` | slice 同 verdict (DR-074 §3 bool value_parser 未実装) |
| 8 | `value-typing/bool-canonical.json::one-numeric` | 同上 |
| 9 | `value-typing/bool-canonical.json::true-mixedcase` | 同上 |
| 10 | `value-typing/bool-canonical.json::true-upper` | 同上 |
| 11 | `value-typing/bool-canonical.json::false-word` | 同上 |
| 12 | `value-typing/bool-canonical.json::zero-numeric` | 同上 |
| 13 | `value-typing/bool-canonical.json::empty-false` | 同上 |
| 14 | `value-typing/bool-canonical.json::yes-rejected` | slice 同 verdict (element 帰属欠落) |
| 15 | `value-typing/int-value-space.json::fractional-value-rejected` | slice 同 verdict (DR-075 int_round 未実装、値空間の整数判定なし) |
| 16 | `value-typing/number-inf-nan.json::inf-on-float-accepted` | slice 同 verdict (DR-074 §1 inf/Infinity 未実装) |
| 17 | `value-typing/number-inf-nan.json::inf-case-insensitive-on-float` | 同上 |

補足 (slice ledger には有ったが今回 VANISH した case、= 実装で追従済で分類外):

- `value-typing/number-decimal-lexicon.json::{thousand-sep-underscore, exponent}` — 現行 `parse_number` が DR-074 §1・§4 の `_` / `e` 追従済
- `value-typing/int-value-space.json::{exponent-integer-value, thousand-sep-integer-value}` — 上記の間接効果 (number 字句が通ることで int の値空間経由も通る)
- `matcher-readings/cluster-split.json::suffix-rejected-split-only` / `matcher-readings/cluster-split-no-flag.json::no-flag-suffix-error` — slice は `f` suffix 受理由来の ambiguous / ok で ledger 済、現行は矯正済み (failure) だが verdict の中身は別 → 後述の delta 側で 1 件だけ発現

### 新実装 delta 3 件 — `known_divergences()` に入れない (メイン側で修正)

#### delta-1: matcher-readings/cluster-split-no-flag.json::no-flag-suffix-error

```
errors got={@0/parse/unexpected_token} want={n@0/parse/not_a_number}
```

- **性質**: `f` suffix 受理は矯正済 (slice の `got=ok{n=1}` → 現行 failure)、ただし failure の内訳が期待と違う
- **got element=""**: matcher が cluster-split の失敗を「値付着 1 token 消費で reject」経路で扱い、element を紐づけていない
- **got reason=`unexpected_token`**: 期待 `not_a_number` (DR-066 §3 v1 vocab)、canonical は「値付着した `1.0f` が number でない → held error, element=n, reason=not_a_number」
- **仮説**: `matcher.mbt` の ShortCombine 経由の値付着で NumArg が parse 失敗した際、`pe_parse` を経由せず scope-level の unexpected_token に落ちている
- **再現**:
  ```
  KUU_FIXTURES=$HOME/.local/share/repos/github.com/kawaz/kuu/main/fixtures/matcher-readings \
    moon test --target native
  ```
  → cluster-split-no-flag の `no-flag-suffix-error` のみが該当

#### delta-2: repeat-parse/max-finite.json::over-max-four

```
errors got={@1/parse/unexpected_token,@2/parse/unexpected_token,@3/parse/unexpected_token} want={@3/parse/unexpected_token}
```

- **性質**: `xs` は max=3 の bounded repeat、argv 4 token 目が unexpected。canonical は「最深 (argv_pos=3) の held Error 1 個だけを primary として吐く」が、現行は 3 個 (pos 1/2/3) を吐いている
- **仮説**: `eval.mbt` の `parse()` の primary 選択 (DR-053 §2 max argv_pos) が正しく絞れず、途中経過の held error まで errors[] に残っている。あるいは Task #6 で修正した residual 合成 (codex 指摘の一つ) の副作用で pos 1〜3 まで全部 residual を吐いている
- **再現**:
  ```
  KUU_FIXTURES=$HOME/.local/share/repos/github.com/kawaz/kuu/main/fixtures/repeat-parse \
    moon test --target native
  ```
  → max-finite.json の `over-max-four` のみ該当 (同 fixture の他 case は PASS)

#### delta-3: repeat-parse/preference-lazy.json::lazy-shortest-left

```
effects got=xs:set(a)@cli,xs:set(b)@cli,xs:set(c)@cli,xs:set(d)@cli,ys:set(e)@cli
       want=xs:set(a)@cli,ys:set(b)@cli,ys:set(c)@cli,ys:set(d)@cli,ys:set(e)@cli
result got={xs=[a,b,c,d],ys=[e]}
      want={xs=[a],ys=[b,c,d,e]}
```

- **性質**: `xs`+`ys` が両方 min:1 の repeat、`xs` は `lazy` 指定。5 token の分割を canonical は `xs=[a],ys=[b,c,d,e]` (lazy=最短) だが、現行は `xs=[a,b,c,d],ys=[e]` (greedy と同じ、`ys` に最短だけ渡す)
- **仮説**: `eval.mbt` の bounded / porous repeat の取り分選好 (DR-043 §取り分の選好) で lazy フラグを見ておらず、常に greedy-longest-left 選好で分岐している。`RepeatSpec.lazy_` の分岐が eval_many / consume_head 側で未参照の可能性
- **再現**:
  ```
  KUU_FIXTURES=$HOME/.local/share/repos/github.com/kawaz/kuu/main/fixtures/repeat-parse \
    moon test --target native
  ```
  → preference-lazy.json の `lazy-shortest-left` のみ該当 (同 fixture の他 case は PASS)

### 単体 fixture 実行の一般形

```
# 特定サブディレクトリだけ (推奨 = 二分探索用)
KUU_FIXTURES=$HOME/.local/share/repos/github.com/kawaz/kuu/main/fixtures/<subdir> \
  moon test --target native

# 特定 fixture 1 件だけ実行したい場合は、fixtures を tmp にコピーして 1 file だけ残す:
mkdir -p /tmp/kuu-single && cp $HOME/.local/share/repos/github.com/kawaz/kuu/main/fixtures/repeat-parse/preference-lazy.json /tmp/kuu-single/
KUU_FIXTURES=/tmp/kuu-single moon test --target native
```

## ハマり所 → 解決策のペア

### API 適応 (slice → main 差分)

- **ParseError が 5 要素 (`reason` 追加)** — `proj_errors` / `exp_errors_decode` を per-fixture opt-in にし、fixture が reason を書いている case のみ got 側にも `/reason` を追加する形にした (CONFORMANCE §3 optional 準拠)。ledger 文字列の byte-identical 契約は現行の観測に合わせる
- **`resolve_scope` / `resolve_scope_config` が `Result[..., ParseError]`** — slice は `Result[..., String]` (config 版) と `Array[Binding]` (flat 版) だった。`do_resolve` / `resolve_tree` で `ParseError.message` を string 化して橋渡し
- **`RepeatSpec.lazy_` / `Entity.inherit_`** — MDR-003 予約語回避で `_` サフィックス。struct literal 側もこれに合わせる (単純 rename)
- **`env_value(ty, s) -> Value`** (slice) → **`env_value(element, ty, s, at_pos) -> Result[Value, ParseError]`** (main) — variant DSL operand 用に naive `dsl_variant_value(ty : Ty, s : String) -> Value` をローカル定義 (parts[2] は DSL リテラルなので Error path 不要)
- **Node / Installer が `Show` 未実装** — `\{node}` interpolation は使えないので、debug 用のワイルドカード分岐は固定文字列 (`?greedy` / `?tnode`) にし、Installer の順序シグネチャは `owned_vocab(i)` を join

### moon.pkg の wbtest 用 import 記法

- 正解: `import { ... } for "wbtest"` の `for` 表記 (slice の poc/moon.pkg と同じ)
- 誤: `import(wbtest) { ... }` (最初これで書いて認識されず、slice を見て修正)

### moon.mod への依存追加

- `moonbitlang/x@0.4.46` を `import` セクションに追加。`moon install` で mooncakes キャッシュから解決
- `@fs.read_dir` / `@fs.path_exists` / `@fs.is_dir` / `@fs.read_file_to_string` / `@env.get_env_var` / `@env.current_dir` / `@json.parse` を使用

## 次のフェーズ

1. **本 journal の完了報告 → team-lead 引き継ぎ** (この worker の担当分)
2. **eval / matcher コア修正** (team-lead 担当): 上記 delta 3 件を修正 → divergence を 20 → 17 に減らして known_divergences と一致
3. **将来の slice-inherited ledger 更新** (追跡 issue 側): DR-074/075 未追従 (bool_canonical, inf/nan)、DR-055 value-branch id attribution、DR-043 取り分未実装、collision→Ambiguous 未実装は残タスク

## 関連

- 移植先ファイル: `src/core/json_conformance_wbtest.mbt`
- 前段タスク: Task 1-4 (葉 → 評価器 → 値確定 + 出口 → installer 移植)
- fixture 正本: 兄弟リポ `github.com/kawaz/kuu/main/fixtures/`
