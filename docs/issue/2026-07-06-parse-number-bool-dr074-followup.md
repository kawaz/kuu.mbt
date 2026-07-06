---
title: parse_number / bool 解釈の DR-074 canonical 字句追従 (桁区切り・指数・inf・anchored 契約・base_prefix / String→bool value_parser)
status: open
category: bug
created: 2026-07-06T15:35:28+09:00
last_read:
open_entered: 2026-07-06T15:35:28+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kawaz/kuu (spec-gaps #3 決着 / DR-074, fixtures 実食で顕在化)
---

# parse_number / bool 解釈の DR-074 canonical 字句追従

## 概要

spec-gaps #3 が決着し、DR-074 で number/bool の canonical value_parser 字句が確定した
(JSON 風 → 実用寛容へ改訂)。さらに spec-gaps M2 が DR-075 で決着し、int の String parse が
**値空間判定** (トークンを number として読み、値が整数なら受理) + **int_round** (default
`error`) と確定した。kawaz/kuu が新輪郭 fixture (`fixtures/value-typing/` 7 件 +
`matcher-readings/cluster-split*` の golden 整合更新) を追加した結果、slice 本体
(parse_number は `poc/value.mbt:198`、int lowering は `poc/installer.mbt:182`、bool 解釈は
`poc/matcher.mbt` 経路) が旧字句・旧 int 規則のままなので **17 件の RUN divergence + 2 件の
DECODE skip** が顕在化した。本フェーズは仕様確定が主で slice 本体は無改変、divergence/skip は
すべて `known_divergences()` / `expected_skips()` に凍結済み。本 issue は slice 側の追従課題を
追跡する (DR-074 number/bool 字句 + DR-075 int 値空間/int_round は同根の value_parser 追従)。

実測 (moon test の diverge/skip 出力) に基づくフラグ + 一次資料 (DR-074 / 各 fixture の
`why`) の提示であり、真因特定と是正方針の判断は slice 当事者に委ねる (現象・仮説は
裏取り前提、鵜呑みにしない)。

## 何がズレるか (divergence 一覧、`known_divergences()` に凍結済み)

### (A) number value_parser: f/F suffix 受理 (DR-074 不採用案) + 新字句 (_ / 指数 / inf) 未対応

slice parse_number (`poc/value.mbt:198`) は anchored (末尾で token 全体一致、`i != n` なら
`None`) だが、canonical が非採用とした型 suffix `f`/`F` を optional な float marker として
明示受理する (DR-074 §1 不採用案「型 suffix」)。「先頭を読んで残りを捨てる」prefix 消費
(Model B) ではないので canonical anchored 契約 (DR-074 §5) 自体は既に満たしており、差分は
(1) 除去すべき f/F suffix 受理、(2) 桁区切り `_` / 指数 `e` / inf の未実装。

- **桁区切り `_` 未実装** (DR-074 §1・§4, config `number_thousand_sep` default `["_"]`):
  `value-typing/number-decimal-lexicon.json::thousand-sep-underscore` — `1_000` が
  `EXPECTED-SUCCESS got=fail:"1_000" is not a number`。
- **指数 `e` 未実装**: 同 fixture `::exponent` — `1e3` が
  `EXPECTED-SUCCESS got=fail:"1e3" is not a number`。
- **inf 未実装** (DR-074 §1, float の受理域 = number + inf):
  `number-inf-nan.json::inf-on-float-accepted` (`inf`) /
  `::inf-case-insensitive-on-float` (`Infinity`) が
  `EXPECTED-SUCCESS got=fail:"..." is not a number`。
  - inf の operand/result JSON serialize 規約は spec 未確定 (JSON に inf リテラルなし)。
    fixture の accept 側は成功輪郭 (outcome + source) のみ固定なので、slice が inf を
    受けられるようになれば outcome だけで PASS する (operand 比較は走らない)。report 送り
    事項なので slice 追従はまず「inf を float で受理し失敗しない」ところまで。
- **整合済 (divergence に出ない)**: `+5` / `007` / `.5` / `1.` は slice が既に正しく受理。
  nan 両型 reject + inf-on-number reject の 3 case も slice が拒否するので整合。

### (B) f/F suffix 受理が short cluster の値付着読みに波及 (DR-074 §1 / DR-041 §3)

canonical は `-n1.0f` の値付着読み `n="1.0f"` を、型 suffix `f` を含む token 全体が
number でないとして held Error に落とす。slice parse_number は anchored だが `f`/`F` を
optional suffix として明示受理する (DR-074 §1 が非採用とした型 suffix) ため、`1.0f`→1 と
読めて値付着読みも成功扱いになる。

- `matcher-readings/cluster-split.json::suffix-rejected-split-only` (f 定義あり):
  値付着 + 分割の 2 読みが両方成功 → `EXPECTED-SUCCESS got=ambiguous:2`。canonical は
  値付着が Error なので分割 1 本の success。
- `matcher-readings/cluster-split-no-flag.json::no-flag-suffix-error` (f 未定義):
  唯一の値付着読みを canonical は Error → failure。slice は `1.0f`→1 と読んで
  `EXPECTED-FAILURE got=ok{n=1}`。
- この 2 fixture は spec 側で golden/case-id が整合更新された (旧: ambiguous 前提 →
  新: suffix 非採用前提)。純粋な multiple-Accept ambiguity 原則の被覆は suffix 非依存の
  `matcher-readings/cluster-split-string.json` (新設、`-sax`) が引き継いでおり、そちらは
  slice で PASS 済み (string 受理は canonical/lenient 同一)。
- (A) の f/F suffix 除去を実装すれば (B) も同時に解消する見込み (同じ parse_number の
  f/F 明示受理が根)。

### (C) bool String→bool value_parser 未実装 (DR-074 §3)

canonical は `--enabled=<val>` の付着値を true_values `["true","1"]` / false_values
`["false","0",""]` に case-insensitive 照合する。slice は bool を値なし flag 的に扱い、
付着値 `=<val>` を解釈できず `unexpected token` で落ちる。

- accept 7 case (`true` / `1` / `True` / `TRUE` / `false` / `0` / 空文字):
  `value-typing/bool-canonical.json::{true-word,one-numeric,true-mixedcase,true-upper,false-word,zero-numeric,empty-false}`
  がすべて `EXPECTED-SUCCESS got=fail:unexpected token`。
- `::yes-rejected`: canonical (Norway 回避で `yes` 非採用 → Error) と slice がどちらも
  失敗するが element 帰属が違う: canonical=`enabled`、slice は付着値を解釈できず element
  名を欠く (空文字) → `errors got={@0/parse} want={enabled@0/parse}`。
- **report 送り (spec 側 open)**: bool value_parser 失敗の reason 語彙が DR-066 v1 に無く、
  yes-rejected は kind まで検証。slice 実装時は kind=parse で足り、reason は後追い。

### (D) int 値空間判定 + int_round 未実装 (DR-075 / M2 決着)

DR-075 で int の String parse は **値空間判定** (トークンを number として読み、値が整数なら
受理 — 整数構文に限らない) + **int_round** (default `error`、fractional 値の丸めモード) と
確定した。slice は int を CLI で number と同一に扱う: `value_prim` (`poc/installer.mbt:182`) が
`TNum | TInt => NumArg(name)` で int を number と同じ `NumArg` ノードに落とし (同 180-181 の
コメント: 整数制約は config 相の `config_to_value` でのみ enforce)、`NumArg` eval
(`poc/eval.mbt:237`) は `parse_number` 一発で成功なら `VNum` を素通しする。よって CLI 相では
整数値判定も int_round も走らない。

- **fractional 値の拒否欠落**: `value-typing/int-value-space.json::fractional-value-rejected` —
  `2.5` は `parse_number` で 2.5 と読め、slice は整数値判定を持たないため `VNum(2.5)` を
  そのまま success で束縛 → `EXPECTED-FAILURE got=ok{v=2.5}`。DR-075 §2 / DR-066 §3 の
  default `int_round=error` では整数でない値は `not_an_integer` で failure になるべき。
- **整数「値」だが number 字句が parse_number 未対応**: 同 fixture `::exponent-integer-value`
  (`1e3`) / `::thousand-sep-integer-value` (`1_000`) はどちらも整数値 1000 なので DR-075 §1 では
  受理されるべきだが、`parse_number` が指数 `e` / 桁区切り `_` を未実装のため held not-a-number
  → `EXPECTED-SUCCESS got=fail:"1e3"/"1_000" is not a number`。これは (A) の
  `number-decimal-lexicon::exponent` / `::thousand-sep-underscore` と**同一の parse_number 字句
  gap** が int の値空間経由で顕れたもの ((A) を直せば同時に解消する見込み)。
- **整合済 (divergence に出ない)**: `fractional-syntax-integer-value` (`3.0`→3) は
  `parse_number` で 3.0 と読め `num_to_string` で 3 に、`non-number-rejected` (`abc`) は number
  不一致で both が `not_a_number` 拒否 (element=v も一致) するため PASS。
- **report 送り (spec 側)**: int_round の丸めモード期待値の正本は DR-075 期待値表。丸め挙動の
  fixture 網羅 (全 10 モード) は `value-typing-s7-fixtures` issue で追跡。String 源の丸めは
  binary64 非経由の厳密判定が必須要件 (DR-075 §5) — slice 実装時はここに注意。

### DECODE skip: factory config shadow の `definitions` キー未対応 (`expected_skips()` に凍結)

- `value-typing/number-base-prefix-optin.json` — DR-074 §2・§4 / DR-061 §3 の
  `number_allow_base_prefix` opt-in を `definitions.types.number = {name, config}` の
  factory shadow で有効化する断面。slice の parse_definition は top-level definition に
  `options/positionals/commands` しか許さず `definitions` キーを表現できないため decode 前に
  skip する (`definition has unsupported key 'definitions'`)。
- `value-typing/int-round-modes.json` — DR-075 §2 / DR-061 の int_round opt-in 丸めモード輪郭を
  `definitions.types` で `kuu_int_parser` を int_round 違いに 4 shadow して観測する断面。同じく
  `definitions` キー未対応で同一 reason (`definition has unsupported key 'definitions'`) で skip。
  base_prefix と同じ factory config shadow 追従で VANISH する。
- 対の canonical 側 `number-base-prefix-rejected.json` (default false → `0x1F`/`0x1p4` を
  両方 Error) は slice も両方 Error で PASS 済み (整合)。base_prefix の受理は slice も
  未実装だが canonical では拒否が正なので偶然一致している。
- slice が factory config shadow (DR-061 の `definitions.types`) を decode + 配線できたら
  この skip は VANISH する。

## 是正方針 (当事者判断、フラグのみ)

1. **parse_number の f/F marker 除去 + 新字句追加** ((A)+(B) を一度に解消しうる): canonical が
   非採用とした型 suffix `f`/`F` の受理を外し (anchored 契約は既に満たしているので変更不要)、
   桁区切り `_` / 指数 `e` / inf (float のみ、ci) を受理域に足す。一次資料は DR-074 §1・§4・§5
   と各 fixture の `why`。inf の operand serialize は spec 未確定なので accept は outcome まで。
2. **String→bool value_parser の新設** ((C)): true_values/false_values の ci 照合。付着値
   `--enabled=<val>` の割り出しは既存の eq_split (entry-forms) を通す。
3. **factory config shadow (`definitions.types`) の decode + 配線** (skip 解消 +
   base_prefix opt-in + int_round shadow): DR-061 §3 の `{name, config}` 参照形を
   parse_definition が受ける。これができると int 型 hex 値空間 fixture や int_round 丸めモード
   fixture (int-round-modes.json) 等の report 送り事項も後続で載せられる。
4. **int 値空間判定 + int_round の CLI 相実装** ((D)): `value_prim` で int を number と別扱いに
   し、CLI 相でも整数値判定を行う。整数でない値は `int_round` config に従って丸める / default
   `error` なら `not_an_integer` failure。丸めは binary64 非経由の厳密判定 (DR-075 §5)。一次資料は
   DR-075 §1・§2・§5 と期待値表、`int-value-space.json` / `int-round-modes.json` の `why`。
   (A) の parse_number 字句拡張 (指数 `e` / 桁区切り `_`) が入れば `1e3`/`1_000` の値空間受理も
   同時に通る。

## 参照

- 台帳: `poc/json_conformance_wbtest.mbt` の `known_divergences()` (「DR-074 canonical
  number/bool 字句改訂への slice parse_number / bool 未追従」コメント配下 14 件) と
  `expected_skips()` (`number-base-prefix-optin.json` 1 件)
- 一次資料: kawaz/kuu `docs/decisions/DR-074-canonical-number-bool-lexicon.md`、
  `docs/DESIGN.md` §3.3/§3.4、`fixtures/value-typing/*` と `matcher-readings/cluster-split*`
