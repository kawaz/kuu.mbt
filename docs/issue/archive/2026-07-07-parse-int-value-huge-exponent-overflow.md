---
title: parse_int_value の巨大指数入力で Int64 silent wrap
status: resolved
category: bug
created: 2026-07-07T22:16:26+09:00
last_read:
open_entered: 2026-07-07T22:16:26+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-08T12:46:26+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:ParseFail に IntOutOfRange を追加し silent wrap を解消(commit zqzulqol / git b07bec0系列)","done:\"1e300\"→Ok(0) に加え \"9223372036854775808\"→Ok(Int64::MIN) の符号反転 wrap も実測 RED 化して修正","done:apply_exponent 前の有効桁数早期判定(19桁超即拒否)、Int64::min 絶対値の専用即値、rounding経路のsigned/unsigned分離","done:reasonはprovisional \"int_out_of_range\"(not_a_bool前例)、語彙確定はspec側issue 2026-07-08-int-value-domain-out-of-range で追跡","done:既知の残存ギャップ(rounding経路のInt64::min絶対値×真の小数×non-error modeの保守的誤拒否、負の巨大指数の性能)はコード内コメントに明記済み"]
blocked_by:
origin: 自リポ TODO
---

# parse_int_value の巨大指数入力で Int64 silent wrap

## 概要

`src/core/value.mbt` の `parse_int_value` は、`"1e300"` のような巨大指数入力を
`apply_exponent` で 300 桁の digit 列に展開し、`digits_to_i64` がその digit 列を
`Int64` へ変換する際に **overflow を検知せず silent wrap** する。結果、範囲外の
入力がエラーにならず、壊れた (無意味な) `Int64` 値で `Ok` を返す。

## 背景

葉モジュール移植 (commit `6a0db90d`) の監査中に机上で気づいた点。実測で再現を確認済み:

```
parse_int_value("1e300", RError) == Ok(0)
```

(`docs/issue/` 起票にあたり `moon test` に一時テストケースを追加して実行、
`Ok(0)` を確認後にテストは削除済み — repo 差分はクリーン)

`digits_to_i64` (value.mbt:267) は `acc = acc * 10L + digit` を単純ループするだけで、
`Int64` の範囲 (`±9223372036854775807`) を超えても検知しない。`apply_exponent`
(value.mbt:354) は指数をそのまま digit 列の桁シフトとして展開するため、`exp` が
大きいほど digit 列も比例して巨大化し、`digits_to_i64` に渡る前提 (「収まる範囲の
整数のみ」) が壊れる。

DR-075 (int の値空間判定 + int_round) は int の**値域** (= Int64 の範囲を超える
入力の扱い) を明示的に規定していない。`ParseFail` (value.mbt:69 enum) にも
`out_of_range` 相当の variant が無いため、reason 語彙をどう拡張するか (DR-066 の
reason 語彙体系との整合) も検討が要る。加えて、この「int の値域を超えた入力を
どう扱うか」という仕様自体が spec (kawaz/kuu 本体) 側で未規定の可能性があり、
spec 側 issue 化も検討対象。

## 受け入れ条件

- [ ] `parse_int_value` が Int64 範囲外の値を silent wrap せず、明示的な
      Error (reason 語彙は要検討) を返すようになっている
- [ ] 範囲外判定の境界 (Int64 min/max 付近) をテストで固定
- [ ] DR-066 の reason 語彙体系との整合を確認 (新規 reason が必要なら DR 追記 or 新 DR)
- [ ] spec 側 (kawaz/kuu) で int の値域が未規定なら、spec 側にも issue を起票するか
      判断する (起票不要と判断した場合はその理由をここに残す)

## TODO

<!-- wip 時のみ -->
