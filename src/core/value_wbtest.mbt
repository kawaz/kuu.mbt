// value_wbtest.mbt — the leaf value parsers as executable spec (DR-074 / DR-075).
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
fn ir(s : String, m : RoundMode) -> Result[Int64, ParseFail] {
  parse_int_value(s, m)
}

///|
/// An int element judges the VALUE, not the syntax (DR-075 §1 = DR-074 §2 M2): any token whose
/// value is integral is accepted under EVERY mode with no rounding — `3.0`, `1e3`, `1_000`, `007`,
/// `+5` are integers. A base-prefix token is `not_a_number` in canonical. `int_round` never fires
/// on these because there is no fractional part to resolve.
test "parse_int_value accepts integer VALUES regardless of syntax" {
  assert_eq(ir("3.0", RError), Ok(3L)) // "3.0" is the integer 3 — value空間, not 整数構文
  assert_eq(ir("1e3", RError), Ok(1000L)) // exponent-notation integer
  assert_eq(ir("1_000", RError), Ok(1000L)) // separators removed
  assert_eq(ir("007", RError), Ok(7L)) // decimal leading zero
  assert_eq(ir("+5", RError), Ok(5L)) // leading `+`
  assert_eq(ir("-4", RError), Ok(-4L))
  assert_eq(ir("2.50e1", RError), Ok(25L)) // 2.50e1 = 25, an integer value despite the fraction 字面
  // a non-number token is `not_a_number` (distinct from `not_an_integer`).
  assert_eq(ir("0x10", RError), Err(NotANumber))
  assert_eq(ir("abc", RError), Err(NotANumber))
}

///|
/// REGRESSION (issue 2026-07-07-parse-int-value-huge-exponent-overflow): a huge exponent (`"1e300"`)
/// used to silently WRAP through `digits_to_i64` instead of erroring — `Ok(0L)` rather than a range
/// Error. This pins the exact repro plus the `"1e19"`/`"1e18"` decade boundary (20 vs 19 significant
/// digits — Int64's max magnitude is 19 digits, so 20+ ALWAYS overflows regardless of digit values,
/// while 19 needs the exact-boundary comparison covered by the next test).
test "parse_int_value rejects huge-exponent overflow instead of silently wrapping" {
  assert_eq(ir("1e300", RError), Err(IntOutOfRange)) // the exact repro from the issue (was Ok(0L))
  assert_eq(ir("-1e300", RError), Err(IntOutOfRange))
  assert_eq(ir("1e19", RError), Err(IntOutOfRange)) // 20 significant digits — always out of range
  assert_eq(ir("1e18", RError), Ok(1000000000000000000L)) // 19 digits, well under max — in range
  // a huge exponent whose combined digits are ALL zero is still exactly 0 (padding zeros stay zero,
  // not "significant" — `int_part_significant_len`'s all_zero short-circuit).
  assert_eq(ir("0e300", RError), Ok(0L))
  assert_eq(ir("0.0e300", RError), Ok(0L))
}

///|
/// The exact Int64 boundary decade (both exactly 19 significant digits, so the digit-count shortcut
/// alone can't decide — DR-075 range check needs the precise string comparison here): max
/// (`9223372036854775807`) and one past it, min (`-9223372036854775808`, the two's-complement
/// asymmetry — its magnitude 9223372036854775808 is one MORE than max's) and one past it, plus the
/// adjacent in-range values (`±1` off each boundary) to pin the edge is exactly right, not off-by-one.
test "parse_int_value pins the exact Int64 boundary decade" {
  // positive max and its neighbors.
  assert_eq(ir("9223372036854775807", RError), Ok(9223372036854775807L)) // Int64::max exactly
  assert_eq(ir("9223372036854775806", RError), Ok(9223372036854775806L)) // max - 1, in range
  assert_eq(ir("9223372036854775808", RError), Err(IntOutOfRange)) // max + 1, out of range
  // negative min and its neighbors — min's magnitude (9223372036854775808) is NOT representable as
  // a positive Int64 at all, so this is the case `digits_to_i64` + negate could never produce.
  assert_eq(ir("-9223372036854775808", RError), Ok(-9223372036854775808L)) // Int64::min exactly
  assert_eq(ir("-9223372036854775807", RError), Ok(-9223372036854775807L)) // min + 1, in range
  assert_eq(ir("-9223372036854775809", RError), Err(IntOutOfRange)) // min - 1, out of range
  // a decimal form of the same boundary values (value空間判定, not just integer literal syntax).
  assert_eq(ir("9223372036854775807.0", RError), Ok(9223372036854775807L))
  assert_eq(ir("9223372036854775808.0", RError), Err(IntOutOfRange))
}

///|
/// The `int_out_of_range` reason surfaces through the ROUNDING branches too (non-`RError` modes),
/// not just the direct-integer-value path above — `magnitude_of`'s pre-rounding check uses the
/// POSITIVE boundary unconditionally (round_magnitude needs an unsigned magnitude to add `+1`), and
/// a SEPARATE post-rounding guard catches the narrower case where rounding pushes an in-range
/// truncated magnitude (exactly Int64::max, non-tie-round-up) past the boundary.
test "parse_int_value surfaces int_out_of_range through rounding modes too" {
  // truncated magnitude alone already exceeds Int64 range (huge exponent, genuinely fractional
  // literal digits so this exercises the rounding branch, not the direct-integer-value one).
  assert_eq(ir("1.5e300", RFloor), Err(IntOutOfRange))
  // truncated magnitude is exactly Int64::max and the fraction rounds UP past it (round_magnitude's
  // `m + 1` would silently wrap to Int64::min without the post-rounding `mag < 0L` guard).
  assert_eq(ir("9223372036854775807.5", RCeil), Err(IntOutOfRange))
  assert_eq(ir("9223372036854775807.5", RHalfEven), Err(IntOutOfRange)) // 807 is odd → banker's rounds up too
  // a rounding-mode value comfortably within range still rounds normally (no false-positive rejection).
  assert_eq(ir("9223372036854775806.5", RCeil), Ok(9223372036854775807L))
}

///|
/// The canonical default `int_round: error` rejects a truly-fractional value as `not_an_integer`
/// (DR-075 §4: the CLI-parser 界 precedent is error-only; silent 精度落ち is a surprise). This is the
/// only mode that emits `not_an_integer`; every rounding mode below turns the same input into a value.
test "parse_int_value under error mode rejects fractional values" {
  assert_eq(ir("2.5", RError), Err(NotAnInteger))
  assert_eq(ir("-3.7", RError), Err(NotAnInteger))
  assert_eq(ir(".5", RError), Err(NotAnInteger))
}

///|
/// The int_round discriminator vector `-3.7 / -2.5 / 2.5 / 3.5` across all 10 modes is the fixture
/// 正本 (DR-075 §期待値表). `-3.7` is a non-tie (nearest is -4); the tie triple exercises the half-mode
/// judgement. Negative ties are REQUIRED to separate `half_ceil`/`half_away` and `half_floor`/`half_trunc`
/// (DR-075 §期待値表 読み方). The integer/tie decision is lexical — no binary64 transit (§5).
test "parse_int_value int_round table (DR-075 discriminator vector)" {
  // floor →−∞ : both non-tie and tie fall toward −∞.
  assert_eq(ir("-3.7", RFloor), Ok(-4L))
  assert_eq(ir("-2.5", RFloor), Ok(-3L))
  assert_eq(ir("2.5", RFloor), Ok(2L))
  assert_eq(ir("3.5", RFloor), Ok(3L))
  // ceil →+∞
  assert_eq(ir("-3.7", RCeil), Ok(-3L))
  assert_eq(ir("-2.5", RCeil), Ok(-2L))
  assert_eq(ir("2.5", RCeil), Ok(3L))
  assert_eq(ir("3.5", RCeil), Ok(4L))
  // trunc →0 (drop the fraction, sign kept)
  assert_eq(ir("-3.7", RTrunc), Ok(-3L))
  assert_eq(ir("-2.5", RTrunc), Ok(-2L))
  assert_eq(ir("2.5", RTrunc), Ok(2L))
  assert_eq(ir("3.5", RTrunc), Ok(3L))
  // away →0 の反対 (magnitude 切り上げ)
  assert_eq(ir("-3.7", RAway), Ok(-4L))
  assert_eq(ir("-2.5", RAway), Ok(-3L))
  assert_eq(ir("2.5", RAway), Ok(3L))
  assert_eq(ir("3.5", RAway), Ok(4L))
  // half_floor: nearest, tie→−∞
  assert_eq(ir("-3.7", RHalfFloor), Ok(-4L))
  assert_eq(ir("-2.5", RHalfFloor), Ok(-3L))
  assert_eq(ir("2.5", RHalfFloor), Ok(2L))
  assert_eq(ir("3.5", RHalfFloor), Ok(3L))
  // half_ceil: nearest, tie→+∞
  assert_eq(ir("-3.7", RHalfCeil), Ok(-4L))
  assert_eq(ir("-2.5", RHalfCeil), Ok(-2L))
  assert_eq(ir("2.5", RHalfCeil), Ok(3L))
  assert_eq(ir("3.5", RHalfCeil), Ok(4L))
  // half_trunc: nearest, tie→0
  assert_eq(ir("-3.7", RHalfTrunc), Ok(-4L))
  assert_eq(ir("-2.5", RHalfTrunc), Ok(-2L))
  assert_eq(ir("2.5", RHalfTrunc), Ok(2L))
  assert_eq(ir("3.5", RHalfTrunc), Ok(3L))
  // half_away: nearest, tie→0 の反対 (学校四捨五入)
  assert_eq(ir("-3.7", RHalfAway), Ok(-4L))
  assert_eq(ir("-2.5", RHalfAway), Ok(-3L))
  assert_eq(ir("2.5", RHalfAway), Ok(3L))
  assert_eq(ir("3.5", RHalfAway), Ok(4L))
  // half_even: nearest, tie→偶数 (banker's)
  assert_eq(ir("-3.7", RHalfEven), Ok(-4L))
  assert_eq(ir("-2.5", RHalfEven), Ok(-2L))
  assert_eq(ir("2.5", RHalfEven), Ok(2L))
  assert_eq(ir("3.5", RHalfEven), Ok(4L))
}

// ── DR-075 §5 binary64 非経由の厳密性 (偽 tie 回避) ─────────────────────────────

///|
/// The tie decision must be lexical, never via `parseFloat → round` (DR-075 §5). `0.4999999999999999999`
/// equals 0.5 in binary64 (a false tie), so a binary64-path `half_even` would wrongly round it to 0 as a
/// tie; the lexical scan sees a leading fractional digit 4 (< 5) and rounds DOWN to 0 correctly, while a
/// value just above (leading digit 5 with non-zero tail) rounds up. This is the guarantee §5 makes spec.
test "parse_int_value tie判定 is lexical, not binary64 (DR-075 §5)" {
  // 0.4999… < 0.5 lexically (first fractional digit is 4) → rounds to 0 under half_even, NOT a tie.
  assert_eq(ir("0.4999999999999999999", RHalfEven), Ok(0L))
  // 0.5000…001 > 0.5 (digit 5 then a non-zero tail) → strictly above half → rounds up to 1.
  assert_eq(ir("0.5000000000000000001", RHalfEven), Ok(1L))
  // an exact 0.5 tie under half_even goes to the even neighbour 0.
  assert_eq(ir("0.5", RHalfEven), Ok(0L))
  // and the same exact 0.5 under half_away (学校四捨五入) goes up to 1.
  assert_eq(ir("0.5", RHalfAway), Ok(1L))
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

// ── DR-050 §4 config_to_value (DR-074/075 追従) ────────────────────────────────

///|
fn cv_ok(r : Result[Value, String]) -> Value? {
  match r {
    Ok(v) => Some(v)
    Err(_) => None
  }
}

///|
/// A config leaf converts to the element's type with bidirectionally-symmetric leniency (DR-050 §4):
/// a string parses into any type, and a JSON scalar stringifies into a string element. The int seat is
/// 値空間判定 with canonical `int_round: error` (DR-075): `"3.0"` → 3, `"2.5"` → Error. The bool seat
/// uses the canonical vocab. Semantic jumps (bool↔number) and structural mismatches stay Errors.
test "config_to_value type conversions" {
  // string → number / int (lenient parse), and 値空間 int acceptance of "3.0".
  assert_eq(cv_ok(config_to_value(CStr("8080"), TNum)), Some(VNum(8080.0)))
  assert_eq(cv_ok(config_to_value(CStr("3.0"), TInt)), Some(VNum(3.0)))
  // "2.5" into int is Error under canonical error mode (no silent 精度落ち).
  assert_eq(cv_ok(config_to_value(CStr("2.5"), TInt)), None)
  // JSON scalar → string element stringifies (寛容の双方向対称): 1.5 → "1.5", true → "true".
  assert_eq(cv_ok(config_to_value(CNum(1.5), TStr)), Some(VStr("1.5")))
  assert_eq(cv_ok(config_to_value(CBool(true), TStr)), Some(VStr("true")))
  // string → bool via canonical vocab; an unknown word is an Error.
  assert_eq(cv_ok(config_to_value(CStr("1"), TFlag)), Some(VBool(true)))
  assert_eq(cv_ok(config_to_value(CStr("yes"), TFlag)), None)
  // native number → int: JSON-由来 binary64 seat; 1.0 is integral (accepted), 1.5 is not (Error).
  assert_eq(cv_ok(config_to_value(CNum(1.0), TInt)), Some(VNum(1.0)))
  assert_eq(cv_ok(config_to_value(CNum(1.5), TInt)), None)
  // 意味の飛躍 (bool↔number) is always an Error — no coercion in either direction.
  assert_eq(cv_ok(config_to_value(CNum(1.0), TFlag)), None)
  assert_eq(cv_ok(config_to_value(CBool(true), TNum)), None)
  // 構造不一致 (array/object → scalar) is an Error.
  assert_eq(cv_ok(config_to_value(CArr([CNum(1.0)]), TNum)), None)
}
