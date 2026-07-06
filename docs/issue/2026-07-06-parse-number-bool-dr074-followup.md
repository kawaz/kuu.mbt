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
(JSON 風 → 実用寛容へ改訂)。kawaz/kuu が新輪郭 fixture (`fixtures/value-typing/` 5 件 +
`matcher-readings/cluster-split*` の golden 整合更新) を追加した結果、slice 本体
(`poc/matcher.mbt` の parse_number / bool 解釈) が旧字句のままなので **14 件の RUN
divergence + 1 件の DECODE skip** が顕在化した。本フェーズは仕様確定が主で slice 本体は
無改変、divergence/skip はすべて `known_divergences()` / `expected_skips()` に凍結済み。
本 issue は slice 側の追従課題を追跡する。

実測 (moon test の diverge/skip 出力) に基づくフラグ + 一次資料 (DR-074 / 各 fixture の
`why`) の提示であり、真因特定と是正方針の判断は slice 当事者に委ねる (現象・仮説は
裏取り前提、鵜呑みにしない)。

## 何がズレるか (divergence 一覧、`known_divergences()` に凍結済み)

### (A) number value_parser: lenient/prefix 消費型 → anchored 契約 + 新字句 未追従

slice parse_number は「先頭の数値部分を読んで残りを捨てる」lenient/prefix 消費型。
canonical は anchored (DR-074 §5: token 全体一致、prefix 消費しない) + 新たな受理域。

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

### (B) anchored 契約未追従が short cluster の値付着読みに波及 (DR-074 §1・§5 / DR-041 §3)

canonical は `-n1.0f` の値付着読み `n="1.0f"` を、型 suffix `f` を含む token 全体が
number でないとして held Error に落とす。slice parse_number は `1.0f` から先頭
`1.0`(→1) を読んで trailing `f` を捨てる (= DR-074 §5 が非採用とした Model B の
prefix 消費) ため値付着読みも成功扱いになる。

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
- (A) の anchored 化を実装すれば (B) も同時に解消する見込み (同じ parse_number の
  prefix 消費が根)。

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

### DECODE skip: factory config shadow の `definitions` キー未対応 (`expected_skips()` に凍結)

- `value-typing/number-base-prefix-optin.json` — DR-074 §2・§4 / DR-061 §3 の
  `number_allow_base_prefix` opt-in を `definitions.types.number = {name, config}` の
  factory shadow で有効化する断面。slice の parse_definition は top-level definition に
  `options/positionals/commands` しか許さず `definitions` キーを表現できないため decode 前に
  skip する (`definition has unsupported key 'definitions'`)。
- 対の canonical 側 `number-base-prefix-rejected.json` (default false → `0x1F`/`0x1p4` を
  両方 Error) は slice も両方 Error で PASS 済み (整合)。base_prefix の受理は slice も
  未実装だが canonical では拒否が正なので偶然一致している。
- slice が factory config shadow (DR-061 の `definitions.types`) を decode + 配線できたら
  この skip は VANISH する。

## 是正方針 (当事者判断、フラグのみ)

1. **parse_number の anchored 化 + 新字句** ((A)+(B) を一度に解消しうる): token 全体一致に
   し、桁区切り `_` / 指数 `e` / inf (float のみ、ci) を受理域に足す。一次資料は DR-074
   §1・§4・§5 と各 fixture の `why`。inf の operand serialize は spec 未確定なので accept は
   outcome まで。
2. **String→bool value_parser の新設** ((C)): true_values/false_values の ci 照合。付着値
   `--enabled=<val>` の割り出しは既存の eq_split (entry-forms) を通す。
3. **factory config shadow (`definitions.types`) の decode + 配線** (skip 解消 +
   base_prefix opt-in): DR-061 §3 の `{name, config}` 参照形を parse_definition が受ける。
   これができると int 型 hex 値空間 fixture 等の report 送り事項も後続で載せられる。

## 参照

- 台帳: `poc/json_conformance_wbtest.mbt` の `known_divergences()` (「DR-074 canonical
  number/bool 字句改訂への slice parse_number / bool 未追従」コメント配下 14 件) と
  `expected_skips()` (`number-base-prefix-optin.json` 1 件)
- 一次資料: kawaz/kuu `docs/decisions/DR-074-canonical-number-bool-lexicon.md`、
  `docs/DESIGN.md` §3.3/§3.4、`fixtures/value-typing/*` と `matcher-readings/cluster-split*`
