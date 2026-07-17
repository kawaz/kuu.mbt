// lexicon_wbtest.mbt — the leaf value parsers as executable spec (DR-074 / DR-075).
//
// These tests freeze the canonical number/bool 字句 and the int 値空間判定 + int_round table.
// Each case states what it guarantees and the spec rationale in prose so the test survives as a
// spec even if the DR docs move (tdd-and-test-design: DR番号は補助 marker).

// ── DR-074 §1 canonical number 字句 ────────────────────────────────────────────

///|
/// The canonical number accepts the CLI-実務 forms that a portable, language-neutral lexicon should:
/// a leading `+`, a leading zero read as DECIMAL (not octal), a bare leading/trailing decimal point,
/// `_` thousands separators between digits, and an `e`/`E` exponent with an optional signed power.
/// Each accepted value below is exactly representable in binary64 so `==` is a faithful assertion.
test "parse_number accepts the canonical decimal forms" {
  // leading `+` is accepted and is a no-op on the magnitude (DR-074 §1 先頭符号).
  assert_eq(parse_number("+5"), Some(5.0))
  assert_eq(parse_number("-5"), Some(-5.0))
  // a leading zero is DECIMAL in canonical — `007` is 7, never octal 7≠… (the C/Go base0 罠 excluded).
  assert_eq(parse_number("007"), Some(7.0))
  // bare decimal points: `.5` (先頭省略) and `1.` (末尾省略) both parse, matching the float 多数派.
  assert_eq(parse_number(".5"), Some(0.5))
  assert_eq(parse_number("1."), Some(1.0))
  // `_` thousands separator is on by default; the value is the digits with `_` removed.
  assert_eq(parse_number("1_000"), Some(1000.0))
  assert_eq(parse_number("1_000.5"), Some(1000.5))
  // exponent, both cases, and an explicitly signed power (DR-074 §7 指数の符号任意).
  assert_eq(parse_number("1e3"), Some(1000.0))
  assert_eq(parse_number("1E3"), Some(1000.0))
  assert_eq(parse_number("1e+3"), Some(1000.0))
  assert_eq(parse_number("2500e-3"), Some(2.5))
}

///|
/// The canonical number REJECTS the forms DR-074 deliberately keeps out of the固定字句: base
/// prefixes (opt-in only, §2), the Java-特異 type suffix `1.0f` (§1 不採用), inf/nan (§1: number 型 is
/// inf-free, nan is Error in both types), locale-ambiguous comma separators, and every malformed `_`
/// placement (§7: `_` only between two digits). A rejection is None (the caller turns it into an Error).
test "parse_number rejects non-canonical forms" {
  // base prefixes are Error in canonical (only `number_allow_base_prefix` opt-in would accept them).
  assert_eq(parse_number("0x1f"), None)
  assert_eq(parse_number("0o17"), None)
  assert_eq(parse_number("0b101"), None)
  // type suffix `1.0f` is unsupported — type is decided by the element's `type`, not a value suffix.
  assert_eq(parse_number("1.0f"), None)
  // inf/nan are not number-型 lexemes (nan is Error even for float; inf is a float-only concern).
  assert_eq(parse_number("inf"), None)
  assert_eq(parse_number("infinity"), None)
  assert_eq(parse_number("nan"), None)
  // comma is NOT a default separator (locale ambiguity + multiple.separator 衝突, §1).
  assert_eq(parse_number("1,000"), None)
  // malformed `_`: leading, trailing, consecutive, and decimal-point-adjacent are all illegal (§7).
  assert_eq(parse_number("_1"), None)
  assert_eq(parse_number("1_"), None)
  assert_eq(parse_number("1__0"), None)
  assert_eq(parse_number("1_.5"), None)
  assert_eq(parse_number("1._5"), None)
  // structurally incomplete tokens: empty, sign-only, point-only, exponent-with-no-digits.
  assert_eq(parse_number(""), None)
  assert_eq(parse_number("+"), None)
  assert_eq(parse_number("."), None)
  assert_eq(parse_number("1e"), None)
  assert_eq(parse_number("abc"), None)
}

///|
/// `parse_float` (DR-074 §1/§7): the float accept域 = number (unchanged, delegates to
/// `parse_number`) PLUS the 2-word inf/infinity lexeme — case-insensitive (`Inf`/`INF`/`Infinity`
/// are case variants of the same 2 words, not separately enumerated), sign-合成可 (`-inf`/`+Infinity`
/// per §1's leading-sign rule). nan has NO lexeme in float either (§1: nan is Error for both types,
/// no opt-in) — `parse_float("nan")` must stay None, not silently fall through to inf.
test "parse_float accepts canonical number forms plus the inf lexicon" {
  // everything parse_number accepts, parse_float accepts identically (delegates first).
  assert_eq(parse_float("+5"), Some(5.0))
  assert_eq(parse_float("1_000.5"), Some(1000.5))
  // the 2-word inf lexicon, case-insensitive (Inf/INF/Infinity are case variants of these 2 words).
  assert_eq(parse_float("inf"), Some(1.0 / 0.0))
  assert_eq(parse_float("Inf"), Some(1.0 / 0.0))
  assert_eq(parse_float("INF"), Some(1.0 / 0.0))
  assert_eq(parse_float("infinity"), Some(1.0 / 0.0))
  assert_eq(parse_float("Infinity"), Some(1.0 / 0.0))
  // leading sign composes onto inf (§1 の符号規則を inf にも適用、§7 で確定).
  assert_eq(parse_float("-inf"), Some(-1.0 / 0.0))
  assert_eq(parse_float("+inf"), Some(1.0 / 0.0))
  assert_eq(parse_float("-Infinity"), Some(-1.0 / 0.0))
  // nan has NO lexeme in float (§1: nan is Error for both number and float, no opt-in ever).
  assert_eq(parse_float("nan"), None)
  assert_eq(parse_float("NaN"), None)
  // non-numeric junk and a malformed inf spelling both stay None (anchored 契約: no partial match).
  assert_eq(parse_float("infi"), None)
  assert_eq(parse_float("abc"), None)
}

// ── DR-075 int 値空間判定 + int_round ──────────────────────────────────────────

///|
fn ir(s : String, m : @engine.RoundMode) -> Result[Int64, @engine.ParseFail] {
  parse_int_value(s, m)
}

///|
/// An int element judges the VALUE, not the syntax (DR-075 §1 = DR-074 §2 M2): any token whose
/// value is integral is accepted under EVERY mode with no rounding — `3.0`, `1e3`, `1_000`, `007`,
/// `+5` are integers. A base-prefix token is `not_a_number` in canonical. `int_round` never fires
/// on these because there is no fractional part to resolve.
test "parse_int_value accepts integer VALUES regardless of syntax" {
  assert_eq(ir("3.0", @engine.RError), Ok(3L)) // "3.0" is the integer 3 — value空間, not 整数構文
  assert_eq(ir("1e3", @engine.RError), Ok(1000L)) // exponent-notation integer
  assert_eq(ir("1_000", @engine.RError), Ok(1000L)) // separators removed
  assert_eq(ir("007", @engine.RError), Ok(7L)) // decimal leading zero
  assert_eq(ir("+5", @engine.RError), Ok(5L)) // leading `+`
  assert_eq(ir("-4", @engine.RError), Ok(-4L))
  assert_eq(ir("2.50e1", @engine.RError), Ok(25L)) // 2.50e1 = 25, an integer value despite the fraction 字面
  // a non-number token is `not_a_number` (distinct from `not_an_integer`).
  assert_eq(ir("0x10", @engine.RError), Err(@engine.NotANumber))
  assert_eq(ir("abc", @engine.RError), Err(@engine.NotANumber))
}

///|
/// REGRESSION (issue 2026-07-07-parse-int-value-huge-exponent-overflow): a huge exponent (`"1e300"`)
/// used to silently WRAP through `digits_to_i64` instead of erroring — `Ok(0L)` rather than a range
/// Error. This pins the exact repro plus the `"1e19"`/`"1e18"` decade boundary (20 vs 19 significant
/// digits — Int64's max magnitude is 19 digits, so 20+ ALWAYS overflows regardless of digit values,
/// while 19 needs the exact-boundary comparison covered by the next test).
test "parse_int_value rejects huge-exponent overflow instead of silently wrapping" {
  assert_eq(ir("1e300", @engine.RError), Err(@engine.IntOutOfRange)) // the exact repro from the issue (was Ok(0L))
  assert_eq(ir("-1e300", @engine.RError), Err(@engine.IntOutOfRange))
  assert_eq(ir("1e19", @engine.RError), Err(@engine.IntOutOfRange)) // 20 significant digits — always out of range
  assert_eq(ir("1e18", @engine.RError), Ok(1000000000000000000L)) // 19 digits, well under max — in range
  // a huge exponent whose combined digits are ALL zero is still exactly 0 (padding zeros stay zero,
  // not "significant" — `int_part_significant_len`'s all_zero short-circuit).
  assert_eq(ir("0e300", @engine.RError), Ok(0L))
  assert_eq(ir("0.0e300", @engine.RError), Ok(0L))
}

///|
/// The exact Int64 boundary decade (both exactly 19 significant digits, so the digit-count shortcut
/// alone can't decide — DR-075 range check needs the precise string comparison here): max
/// (`9223372036854775807`) and one past it, min (`-9223372036854775808`, the two's-complement
/// asymmetry — its magnitude 9223372036854775808 is one MORE than max's) and one past it, plus the
/// adjacent in-range values (`±1` off each boundary) to pin the edge is exactly right, not off-by-one.
test "parse_int_value pins the exact Int64 boundary decade" {
  // positive max and its neighbors.
  assert_eq(ir("9223372036854775807", @engine.RError), Ok(9223372036854775807L)) // Int64::max exactly
  assert_eq(ir("9223372036854775806", @engine.RError), Ok(9223372036854775806L)) // max - 1, in range
  assert_eq(
    ir("9223372036854775808", @engine.RError),
    Err(@engine.IntOutOfRange),
  ) // max + 1, out of range
  // negative min and its neighbors — min's magnitude (9223372036854775808) is NOT representable as
  // a positive Int64 at all, so this is the case `digits_to_i64` + negate could never produce.
  assert_eq(
    ir("-9223372036854775808", @engine.RError),
    Ok(-9223372036854775808L),
  ) // Int64::min exactly
  assert_eq(
    ir("-9223372036854775807", @engine.RError),
    Ok(-9223372036854775807L),
  ) // min + 1, in range
  assert_eq(
    ir("-9223372036854775809", @engine.RError),
    Err(@engine.IntOutOfRange),
  ) // min - 1, out of range
  // a decimal form of the same boundary values (value空間判定, not just integer literal syntax).
  assert_eq(
    ir("9223372036854775807.0", @engine.RError),
    Ok(9223372036854775807L),
  )
  assert_eq(
    ir("9223372036854775808.0", @engine.RError),
    Err(@engine.IntOutOfRange),
  )
}

///|
/// The `int_out_of_range` reason surfaces through the ROUNDING branches too (non-`@engine.RError` modes),
/// not just the direct-integer-value path above — `magnitude_of`'s pre-rounding check uses the
/// POSITIVE boundary unconditionally (round_magnitude needs an unsigned magnitude to add `+1`), and
/// a SEPARATE post-rounding guard catches the narrower case where rounding pushes an in-range
/// truncated magnitude (exactly Int64::max, non-tie-round-up) past the boundary.
test "parse_int_value surfaces int_out_of_range through rounding modes too" {
  // truncated magnitude alone already exceeds Int64 range (huge exponent, genuinely fractional
  // literal digits so this exercises the rounding branch, not the direct-integer-value one).
  assert_eq(ir("1.5e300", @engine.RFloor), Err(@engine.IntOutOfRange))
  // truncated magnitude is exactly Int64::max and the fraction rounds UP past it (round_magnitude's
  // `m + 1` would silently wrap to Int64::min without the post-rounding `mag < 0L` guard).
  assert_eq(
    ir("9223372036854775807.5", @engine.RCeil),
    Err(@engine.IntOutOfRange),
  )
  assert_eq(
    ir("9223372036854775807.5", @engine.RHalfEven),
    Err(@engine.IntOutOfRange),
  ) // 807 is odd → banker's rounds up too
  // a rounding-mode value comfortably within range still rounds normally (no false-positive rejection).
  assert_eq(
    ir("9223372036854775806.5", @engine.RCeil),
    Ok(9223372036854775807L),
  )
}

///|
/// The canonical default `int_round: error` rejects a truly-fractional value as `not_an_integer`
/// (DR-075 §4: the CLI-parser 界 precedent is error-only; silent 精度落ち is a surprise). This is the
/// only mode that emits `not_an_integer`; every rounding mode below turns the same input into a value.
test "parse_int_value under error mode rejects fractional values" {
  assert_eq(ir("2.5", @engine.RError), Err(@engine.NotAnInteger))
  assert_eq(ir("-3.7", @engine.RError), Err(@engine.NotAnInteger))
  assert_eq(ir(".5", @engine.RError), Err(@engine.NotAnInteger))
}

///|
/// The int_round discriminator vector `-3.7 / -2.5 / 2.5 / 3.5` across all 10 modes is the fixture
/// 正本 (DR-075 §期待値表). `-3.7` is a non-tie (nearest is -4); the tie triple exercises the half-mode
/// judgement. Negative ties are REQUIRED to separate `half_ceil`/`half_away` and `half_floor`/`half_trunc`
/// (DR-075 §期待値表 読み方). The integer/tie decision is lexical — no binary64 transit (§5).
test "parse_int_value int_round table (DR-075 discriminator vector)" {
  // floor →−∞ : both non-tie and tie fall toward −∞.
  assert_eq(ir("-3.7", @engine.RFloor), Ok(-4L))
  assert_eq(ir("-2.5", @engine.RFloor), Ok(-3L))
  assert_eq(ir("2.5", @engine.RFloor), Ok(2L))
  assert_eq(ir("3.5", @engine.RFloor), Ok(3L))
  // ceil →+∞
  assert_eq(ir("-3.7", @engine.RCeil), Ok(-3L))
  assert_eq(ir("-2.5", @engine.RCeil), Ok(-2L))
  assert_eq(ir("2.5", @engine.RCeil), Ok(3L))
  assert_eq(ir("3.5", @engine.RCeil), Ok(4L))
  // trunc →0 (drop the fraction, sign kept)
  assert_eq(ir("-3.7", @engine.RTrunc), Ok(-3L))
  assert_eq(ir("-2.5", @engine.RTrunc), Ok(-2L))
  assert_eq(ir("2.5", @engine.RTrunc), Ok(2L))
  assert_eq(ir("3.5", @engine.RTrunc), Ok(3L))
  // away →0 の反対 (magnitude 切り上げ)
  assert_eq(ir("-3.7", @engine.RAway), Ok(-4L))
  assert_eq(ir("-2.5", @engine.RAway), Ok(-3L))
  assert_eq(ir("2.5", @engine.RAway), Ok(3L))
  assert_eq(ir("3.5", @engine.RAway), Ok(4L))
  // half_floor: nearest, tie→−∞
  assert_eq(ir("-3.7", @engine.RHalfFloor), Ok(-4L))
  assert_eq(ir("-2.5", @engine.RHalfFloor), Ok(-3L))
  assert_eq(ir("2.5", @engine.RHalfFloor), Ok(2L))
  assert_eq(ir("3.5", @engine.RHalfFloor), Ok(3L))
  // half_ceil: nearest, tie→+∞
  assert_eq(ir("-3.7", @engine.RHalfCeil), Ok(-4L))
  assert_eq(ir("-2.5", @engine.RHalfCeil), Ok(-2L))
  assert_eq(ir("2.5", @engine.RHalfCeil), Ok(3L))
  assert_eq(ir("3.5", @engine.RHalfCeil), Ok(4L))
  // half_trunc: nearest, tie→0
  assert_eq(ir("-3.7", @engine.RHalfTrunc), Ok(-4L))
  assert_eq(ir("-2.5", @engine.RHalfTrunc), Ok(-2L))
  assert_eq(ir("2.5", @engine.RHalfTrunc), Ok(2L))
  assert_eq(ir("3.5", @engine.RHalfTrunc), Ok(3L))
  // half_away: nearest, tie→0 の反対 (学校四捨五入)
  assert_eq(ir("-3.7", @engine.RHalfAway), Ok(-4L))
  assert_eq(ir("-2.5", @engine.RHalfAway), Ok(-3L))
  assert_eq(ir("2.5", @engine.RHalfAway), Ok(3L))
  assert_eq(ir("3.5", @engine.RHalfAway), Ok(4L))
  // half_even: nearest, tie→偶数 (banker's)
  assert_eq(ir("-3.7", @engine.RHalfEven), Ok(-4L))
  assert_eq(ir("-2.5", @engine.RHalfEven), Ok(-2L))
  assert_eq(ir("2.5", @engine.RHalfEven), Ok(2L))
  assert_eq(ir("3.5", @engine.RHalfEven), Ok(4L))
}

// ── DR-075 §5 binary64 非経由の厳密性 (偽 tie 回避) ─────────────────────────────

///|
/// The tie decision must be lexical, never via `parseFloat → round` (DR-075 §5). `0.4999999999999999999`
/// equals 0.5 in binary64 (a false tie), so a binary64-path `half_even` would wrongly round it to 0 as a
/// tie; the lexical scan sees a leading fractional digit 4 (< 5) and rounds DOWN to 0 correctly, while a
/// value just above (leading digit 5 with non-zero tail) rounds up. This is the guarantee §5 makes spec.
test "parse_int_value tie判定 is lexical, not binary64 (DR-075 §5)" {
  // 0.4999… < 0.5 lexically (first fractional digit is 4) → rounds to 0 under half_even, NOT a tie.
  assert_eq(ir("0.4999999999999999999", @engine.RHalfEven), Ok(0L))
  // 0.5000…001 > 0.5 (digit 5 then a non-zero tail) → strictly above half → rounds up to 1.
  assert_eq(ir("0.5000000000000000001", @engine.RHalfEven), Ok(1L))
  // an exact 0.5 tie under half_even goes to the even neighbour 0.
  assert_eq(ir("0.5", @engine.RHalfEven), Ok(0L))
  // and the same exact 0.5 under half_away (学校四捨五入) goes up to 1.
  assert_eq(ir("0.5", @engine.RHalfAway), Ok(1L))
}

// ── DR-074 §3 bool canonical 字句 ──────────────────────────────────────────────

///|
/// The canonical bool vocabulary is `true/1` and `false/0/""`, case-insensitive (DR-074 §3). The empty
/// string is false (env's `FLAG=` pattern). Anything outside the vocab — including the Norway-problem
/// words `yes/no/on/off` — is None (an Error at the call site; no silent bool化, DR-021 姿勢).
test "parse_bool canonical vocabulary" {
  assert_eq(parse_bool("true"), Some(true))
  assert_eq(parse_bool("TRUE"), Some(true)) // case-insensitive
  assert_eq(parse_bool("True"), Some(true))
  assert_eq(parse_bool("1"), Some(true))
  assert_eq(parse_bool("false"), Some(false))
  assert_eq(parse_bool("FALSE"), Some(false))
  assert_eq(parse_bool("0"), Some(false))
  assert_eq(parse_bool(""), Some(false)) // env `FLAG=` → false
  // canonical-外: yes/no/on/off and stray tokens are unrecognized (→ Error), never silently coerced.
  assert_eq(parse_bool("yes"), None)
  assert_eq(parse_bool("no"), None)
  assert_eq(parse_bool("on"), None)
  assert_eq(parse_bool("2"), None)
  assert_eq(parse_bool("t"), None)
}

///|
/// DR-074 §2 opt-in `number_allow_base_prefix` (統合 opt-in): allow=false は canonical (10 進のみ) を
/// 保つ (`0xff` / `0x1.8p3` / `0o777` / `0b1010` すべて Error)。allow=true で hex integer / hex float /
/// oct / bin 一括受理する。§7 pin (prefix 大文字 / `_` 配置文法 / `0o`・`0b` の小数点拒否 / 符号合成 /
/// p 任意) の境界を parse_number_ext の輪郭として固定する。
test "parse_number_ext: canonical (allow=false) は base prefix を全て Error" {
  // canonical = decimal のみ: base prefix は None
  assert_eq(parse_number_ext("0xff", false), None)
  assert_eq(parse_number_ext("0x1.8p3", false), None)
  assert_eq(parse_number_ext("0o777", false), None)
  assert_eq(parse_number_ext("0b1010", false), None)
  // canonical decimal は allow に関係なく通る
  assert_eq(parse_number_ext("1_000", false), Some(1000.0))
  assert_eq(parse_number_ext("1e3", false), Some(1000.0))
}

///|
/// hex integer: `0xff` = 255、`0xFF` (大文字桁) / `0Xff` (大文字 prefix) も同値 (§7 pin 「prefix / hex 桁
/// case-insensitive」)、`0xff_ff` は `_` 桁区切りで 65535、符号合成 `-0xff` = -255。
test "parse_number_ext: hex integer 基本と case / underscore / 符号合成" {
  assert_eq(parse_number_ext("0xff", true), Some(255.0))
  assert_eq(parse_number_ext("0xFF", true), Some(255.0))
  assert_eq(parse_number_ext("0Xff", true), Some(255.0)) // §7 pin 大文字 prefix
  assert_eq(parse_number_ext("0xff_ff", true), Some(65535.0))
  assert_eq(parse_number_ext("-0xff", true), Some(-255.0))
  assert_eq(parse_number_ext("+0xff", true), Some(255.0))
}

///|
/// hex float: `0x1.8p3` = (1 + 8/16) * 2^3 = 1.5 * 8 = 12、`0x1.8` = 1.5 (p 省略時 = 2^0、DR-074 §2 の
/// C strtod 流 「p 任意」)、`0x1.8p-1` = 0.75、大文字 P も受理 (§7 pin 「二進指数 p/P」)。
test "parse_number_ext: hex float mantissa / 指数 / P 大文字" {
  assert_eq(parse_number_ext("0x1.8p3", true), Some(12.0))
  assert_eq(parse_number_ext("0x1.8", true), Some(1.5)) // p 省略
  assert_eq(parse_number_ext("0x1.8p-1", true), Some(0.75)) // 指数負符号
  assert_eq(parse_number_ext("0x1.8P3", true), Some(12.0)) // 大文字 P
  assert_eq(parse_number_ext("0x1.8p+3", true), Some(12.0)) // 指数明示 +
}

///|
/// `_` 配置文法 (§7 pin): 両隣桁必須。prefix 隣接 (`0x_ff` = prefix 直後の `_` は先頭空 → 拒否)、
/// 末尾 (`0xff_`) / 連続 (`0xff__ff`) は Error。fraction の `_` も両隣 hex 桁。
test "parse_number_ext: `_` 配置文法 (prefix 隣接 / 末尾 / 連続すべて Error)" {
  assert_eq(parse_number_ext("0x_ff", true), None) // prefix 直後
  assert_eq(parse_number_ext("0xff_", true), None) // 末尾
  assert_eq(parse_number_ext("0xff__ff", true), None) // 連続
  assert_eq(parse_number_ext("0x1_.8", true), None) // 小数点隣接
  assert_eq(parse_number_ext("0x1._8", true), None) // 小数点隣接
  assert_eq(parse_number_ext("0x1.8p_3", true), None) // 指数記号隣接
}

///|
/// `0o` / `0b` は整数のみ (§7 pin 「小数部・二進指数は hex (0x) のみ」): `0o1.5` / `0b1.1` / `0o1p2` は
/// すべて Error。正常な整数値 (`0o777` = 511、`0b1010` = 10) は受理、`_` 桁区切りも同一規則。
test "parse_number_ext: oct/bin は整数のみ (小数点・指数不可、DR-074 §7 pin)" {
  assert_eq(parse_number_ext("0o777", true), Some(511.0))
  assert_eq(parse_number_ext("0o7_77", true), Some(511.0))
  assert_eq(parse_number_ext("0O777", true), Some(511.0)) // 大文字 prefix
  assert_eq(parse_number_ext("0b1010", true), Some(10.0))
  assert_eq(parse_number_ext("0B1010", true), Some(10.0))
  assert_eq(parse_number_ext("0b10_10", true), Some(10.0))
  // 小数点・指数付き 8/2 進はすべて Error
  assert_eq(parse_number_ext("0o1.5", true), None)
  assert_eq(parse_number_ext("0b1.1", true), None)
  assert_eq(parse_number_ext("0o1p2", true), None)
}

///|
/// `0x1e2` = hex 482 (0x1e2 全体が hex、10 進 e 指数と割れない、DR-074 §2 内部整合)。10 進の `e` と
/// hex の `p` は prefix (`0x` の有無) で一意に切り替わる。
test "parse_number_ext: `0x1e2` = hex 482 (e は hex 桁、p が二進指数)" {
  // 0x1e2 = 0x1 * 0x100 + 0xe * 0x10 + 0x2 = 256 + 224 + 2 = 482
  assert_eq(parse_number_ext("0x1e2", true), Some(482.0))
  // 10 進 e は canonical で 1e2 = 100
  assert_eq(parse_number_ext("1e2", true), Some(100.0))
}

///|
/// DR-075 §値空間判定 と DR-074 §2 の合成: `parse_int_value_ext` は hex 経路も値空間で判定する。
/// `0xff` は整数値なので @engine.RError でも Ok(255)、`0x1.8p3` = 12 は整数値なので Ok(12)、`0x1.8` = 1.5 は
/// 非整数なので @engine.RError で @engine.NotAnInteger、丸めモードで Ok(rounded)。opt-in off で hex は not_a_number。
test "parse_int_value_ext: hex 整数値は Ok、hex 非整数は int_round に従う (DR-075 §1 / §2)" {
  // hex integer は整数値なので全モードで Ok
  assert_eq(parse_int_value_ext("0xff", @engine.RError, true), Ok(255L))
  // hex float で整数値 (0x1.8p3 = 12) も全モードで Ok
  assert_eq(parse_int_value_ext("0x1.8p3", @engine.RError, true), Ok(12L))
  // hex float で非整数 (0x1.8 = 1.5) は @engine.RError で @engine.NotAnInteger
  assert_eq(
    parse_int_value_ext("0x1.8", @engine.RError, true),
    Err(@engine.NotAnInteger),
  )
  // 丸めモードなら Ok (1.5 を trunc → 1、floor → 1、ceil → 2)
  assert_eq(parse_int_value_ext("0x1.8", @engine.RTrunc, true), Ok(1L))
  assert_eq(parse_int_value_ext("0x1.8", @engine.RFloor, true), Ok(1L))
  assert_eq(parse_int_value_ext("0x1.8", @engine.RCeil, true), Ok(2L))
  // opt-in off なら hex は not_a_number
  assert_eq(
    parse_int_value_ext("0xff", @engine.RError, false),
    Err(@engine.NotANumber),
  )
}
