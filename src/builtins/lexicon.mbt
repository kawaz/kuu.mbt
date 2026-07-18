// lexicon.mbt — canonical builtin number, int, float, and bool lexicons.

///|
/// canonical default config (DR-074 §3)。TypeShadow/ElemDef の bool_config 既定値、および
/// `parse_bool`(configなし呼び出し) が委譲する先。
pub fn bool_config_canonical() -> @engine.BoolConfig {
  {
    true_values: ["true", "1"],
    false_values: ["false", "0", ""],
    case_insensitive: true,
  }
}

///|
/// Parse a String token as a bool through a configurable vocab (DR-074 §3/§4 `bool_parser` factory
/// config). `case_insensitive` gates whether the token is compared against `true_values`/
/// `false_values` case-insensitively (canonical `true`) or exactly (opt-in dialect, JSON/TOML 準拠
/// `false`). A token matching neither list is None (→ Error at the call site, same `not_a_bool`
/// posture). Without `config`, the canonical table is used (DR-061 §3 「クロージャをデータ化」).
fn parse_bool(
  s : String,
  config? : @engine.BoolConfig = bool_config_canonical(),
) -> Bool? {
  for t in config.true_values {
    if (config.case_insensitive && eq_ci(s, t)) ||
      (!config.case_insensitive && s == t) {
      return Some(true)
    }
  }
  for f in config.false_values {
    if (config.case_insensitive && eq_ci(s, f)) ||
      (!config.case_insensitive && s == f) {
      return Some(false)
    }
  }
  None
}

// ── canonical number 字句スキャン (DR-074 §1, §7) ──────────────────────────────

///|
/// String indexing (`s[i]`) yields a UTF-16 code unit, not a Char, so the number 字句スキャン works
/// on Array[Char] (iterating a String yields Char). Test tokens are ASCII.
fn chars_of(s : String) -> Array[Char] {
  @engine.to_chars(s)
}

///|
/// Scan a maximal digit group starting at `start`, writing the digits (WITHOUT the `_`
/// separators) into `buf`. DR-074 §7 `_` placement: a `_` is legal ONLY between two digits —
/// no leading (`_1`), trailing (`1_`), consecutive (`1__0`), or edge-adjacent `_`. Returns the
/// index just past the group, or None if a `_` is misplaced. An empty group is legal (returns
/// `start` unchanged) — the caller decides whether at least one mantissa digit was seen.
fn scan_digits(cs : Array[Char], start : Int, buf : StringBuilder) -> Int? {
  let n = cs.length()
  let mut i = start
  let mut last_digit = false
  while i < n {
    let c = cs[i]
    if c >= '0' && c <= '9' {
      buf.write_char(c)
      last_digit = true
      i = i + 1
    } else if c == '_' {
      // `_` must have a digit on BOTH sides (DR-074 §7)
      if !last_digit {
        return None
      }
      if i + 1 >= n {
        return None
      }
      let nx = cs[i + 1]
      if !(nx >= '0' && nx <= '9') {
        return None
      }
      last_digit = false
      i = i + 1 // skip `_`, do not write it
    } else {
      break
    }
  }
  Some(i)
}

///|
/// Split a token into canonical number parts: `(neg, int_digits, frac_digits, exp)`, or None if the
/// token is not a canonical number lexeme (DR-074 §1). Rejects base prefixes (`0x`/`0o`/`0b` — Error
/// in canonical, §2), type suffix (`1.0f`), inf/nan, and any trailing junk. `int_digits`/`frac_digits`
/// have their `_` separators stripped; a leading `.` gives empty `int_digits`, a trailing `.` gives
/// empty `frac_digits`. At least one mantissa digit is required (`.` / `+` alone → None).
fn scan_number_parts(s : String) -> (Bool, String, String, Int)? {
  let cs = chars_of(s)
  let n = cs.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  // leading sign (DR-074 §1: [+-] both accepted)
  if cs[i] == '+' || cs[i] == '-' {
    neg = cs[i] == '-'
    i = i + 1
  }
  // reject base prefix — canonical does not accept 0x/0o/0b (§2, opt-in only)
  if i + 1 < n && cs[i] == '0' {
    let c1 = cs[i + 1]
    if c1 == 'x' ||
      c1 == 'X' ||
      c1 == 'o' ||
      c1 == 'O' ||
      c1 == 'b' ||
      c1 == 'B' {
      return None
    }
  }
  // integer digit group (may be empty for a leading-`.` form like `.5`)
  let ibuf = StringBuilder::new()
  let after_int = match scan_digits(cs, i, ibuf) {
    None => return None
    Some(x) => x
  }
  i = after_int
  let int_digits = ibuf.to_string()
  let mut saw_digit = int_digits.length() > 0
  // fraction
  let fbuf = StringBuilder::new()
  if i < n && cs[i] == '.' {
    i = i + 1
    let after_frac = match scan_digits(cs, i, fbuf) {
      None => return None
      Some(x) => x
    }
    i = after_frac
  }
  let frac_digits = fbuf.to_string()
  if frac_digits.length() > 0 {
    saw_digit = true
  }
  // at least one mantissa digit required (`.` alone or `+` alone → None)
  if !saw_digit {
    return None
  }
  // exponent (e/E, optional [+-] sign, digits required — DR-074 §7)
  let mut exp = 0
  if i < n && (cs[i] == 'e' || cs[i] == 'E') {
    i = i + 1
    let mut esign = 1
    if i < n && (cs[i] == '+' || cs[i] == '-') {
      if cs[i] == '-' {
        esign = -1
      }
      i = i + 1
    }
    let ebuf = StringBuilder::new()
    let after_exp = match scan_digits(cs, i, ebuf) {
      None => return None
      Some(x) => x
    }
    i = after_exp
    let edigits = ebuf.to_string()
    if edigits.length() == 0 {
      return None // exponent marker with no digits
    }
    exp = esign * digits_to_int(edigits)
  }
  // any trailing character (incl. `f` suffix / inf / nan / stray char) rejects the whole token
  if i != n {
    return None
  }
  Some((neg, int_digits, frac_digits, exp))
}

// ── DR-074 §2 / §7 opt-in base prefix (0x / 0o / 0b) + hex float ──────────────

///|
/// hex digit value 0-15 (case-insensitive, DR-074 §7 「hex の桁 a-f / A-F は case-insensitive」),
/// or None for non-hex characters. Used by scan_hex_digits / parse_hex_body の値計算.
fn hex_val(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(10 + c.to_int() - 'a'.to_int())
  } else if c >= 'A' && c <= 'F' {
    Some(10 + c.to_int() - 'A'.to_int())
  } else {
    None
  }
}

///|
/// Scan a maximal hex digit group starting at `start`, writing the digits (WITHOUT the `_`
/// separators) into `buf`. DR-074 §7 `_` placement: 両隣が hex 桁のみ許容 — 連続 (`ff__ff`) 不可、
/// 先頭 (`_ff`) / 末尾 (`ff_`) / 非 hex 隣接不可。`0x_ff` は caller が拒否する (prefix 隣接 = 先頭に相当)。
/// 空 group は legal (0 を返す) — caller が「少なくとも 1 桁」を判定。
fn scan_hex_digits(cs : Array[Char], start : Int, buf : StringBuilder) -> Int? {
  let n = cs.length()
  let mut i = start
  let mut last_hex = false
  while i < n {
    let c = cs[i]
    match hex_val(c) {
      Some(_) => {
        buf.write_char(c)
        last_hex = true
        i = i + 1
      }
      None =>
        if c == '_' {
          if !last_hex {
            return None
          }
          if i + 1 >= n {
            return None
          }
          if hex_val(cs[i + 1]) is None {
            return None
          }
          last_hex = false
          i = i + 1
        } else {
          break
        }
    }
  }
  Some(i)
}

///|
/// Scan a maximal octal digit group [0-7] with `_` between digits (DR-074 §7 と同一規則の base=8 版)。
fn scan_oct_digits(cs : Array[Char], start : Int, buf : StringBuilder) -> Int? {
  let n = cs.length()
  let mut i = start
  let mut last_oct = false
  while i < n {
    let c = cs[i]
    if c >= '0' && c <= '7' {
      buf.write_char(c)
      last_oct = true
      i = i + 1
    } else if c == '_' {
      if !last_oct {
        return None
      }
      if i + 1 >= n {
        return None
      }
      let nx = cs[i + 1]
      if !(nx >= '0' && nx <= '7') {
        return None
      }
      last_oct = false
      i = i + 1
    } else {
      break
    }
  }
  Some(i)
}

///|
/// Scan a maximal binary digit group [01] with `_` between digits (base=2)。
fn scan_bin_digits(cs : Array[Char], start : Int, buf : StringBuilder) -> Int? {
  let n = cs.length()
  let mut i = start
  let mut last_bin = false
  while i < n {
    let c = cs[i]
    if c == '0' || c == '1' {
      buf.write_char(c)
      last_bin = true
      i = i + 1
    } else if c == '_' {
      if !last_bin {
        return None
      }
      if i + 1 >= n {
        return None
      }
      let nx = cs[i + 1]
      if !(nx == '0' || nx == '1') {
        return None
      }
      last_bin = false
      i = i + 1
    } else {
      break
    }
  }
  Some(i)
}

///|
/// 2^exp を Double で計算 (単純ループ、hex float 二進指数の適用に使う)。fixture が使う範囲 (|exp| < 20
/// 程度) では overflow なし。極端値では ±0 / ±inf に飽和する (spec は境界を規定しないので合理的既定)。
fn pow2_double(exp : Int) -> Double {
  if exp >= 0 {
    let mut r = 1.0
    let mut i = 0
    while i < exp {
      r = r * 2.0
      i = i + 1
    }
    r
  } else {
    let mut r = 1.0
    let mut i = 0
    while i < -exp {
      r = r * 2.0
      i = i + 1
    }
    1.0 / r
  }
}

///|
/// DR-074 §2 hex 整数 or hex float の body parse (`0x`/`0X` prefix は caller が既に消費)。至急要求 =
/// (mantissa hex 桁が int/frac に一つ以上) + optional `.frac_hex` + optional `p[+-]?dec`。fraction または
/// exponent がある場合は hex float、両方無ければ hex integer (同じロジックで value 化する — integer は
/// exp=0 かつ frac 空)。trailing junk (i != n) は None。DR-074 §7 pin: `_` 配置文法は 両隣桁のみ、
/// `0x_ff` (prefix 隣接) は先頭空 int_digits → 続く `_` が scan_hex_digits で NG (先頭 `_`) で拒否。
fn parse_hex_body(cs : Array[Char], i_start : Int, neg : Bool) -> Double? {
  let n = cs.length()
  let mut i = i_start
  // integer hex 桁群 (空 legal、fraction がある場合のみ)
  let ibuf = StringBuilder::new()
  let after_int = match scan_hex_digits(cs, i, ibuf) {
    None => return None
    Some(x) => x
  }
  i = after_int
  let int_digits = ibuf.to_string()
  let mut saw_digit = int_digits.length() > 0
  // fraction: 小数点あり時のみ、`_` 配置は同一規則
  let fbuf = StringBuilder::new()
  if i < n && cs[i] == '.' {
    i = i + 1
    let after_frac = match scan_hex_digits(cs, i, fbuf) {
      None => return None
      Some(x) => x
    }
    i = after_frac
  }
  let frac_digits = fbuf.to_string()
  if frac_digits.length() > 0 {
    saw_digit = true
  }
  // 少なくとも 1 mantissa 桁 (`0x.p3` / `0x` は空 mantissa で None、DR-074 §1 の scan_number_parts と同型)
  if !saw_digit {
    return None
  }
  // 二進指数 `p[+-]?dec+` (任意、DR-074 §2 「p 任意 = C strtod 流」)
  let mut exp = 0
  if i < n && (cs[i] == 'p' || cs[i] == 'P') {
    i = i + 1
    let mut esign = 1
    if i < n && (cs[i] == '+' || cs[i] == '-') {
      if cs[i] == '-' {
        esign = -1
      }
      i = i + 1
    }
    let ebuf = StringBuilder::new()
    let after_exp = match scan_digits(cs, i, ebuf) {
      None => return None
      Some(x) => x
    }
    i = after_exp
    let edigits = ebuf.to_string()
    if edigits.length() == 0 {
      return None
    }
    exp = esign * digits_to_int(edigits)
  }
  // trailing junk
  if i != n {
    return None
  }
  // value 計算: mantissa = Σ hex_val * 16^k (int) + Σ hex_val * 16^(-(k+1)) (frac)、scale = 2^exp
  let mut val = 0.0
  for c in int_digits {
    val = val * 16.0 + hex_val(c).unwrap().to_double()
  }
  let mut frac_mul = 1.0 / 16.0
  for c in frac_digits {
    val = val + hex_val(c).unwrap().to_double() * frac_mul
    frac_mul = frac_mul / 16.0
  }
  val = val * pow2_double(exp)
  Some(if neg { -val } else { val })
}

///|
/// DR-074 §2 opt-in `0o` 8 進整数 (`0o` prefix は caller が消費済み)。§7 pin: `0o1.5` / `0o1p3` は
/// 小数点・指数 hex float 限定なので、fraction / exponent は accept せず、trailing char で None。
fn parse_oct_body(cs : Array[Char], i_start : Int, neg : Bool) -> Double? {
  let n = cs.length()
  let mut i = i_start
  let ibuf = StringBuilder::new()
  let after_int = match scan_oct_digits(cs, i, ibuf) {
    None => return None
    Some(x) => x
  }
  i = after_int
  let int_digits = ibuf.to_string()
  if int_digits.length() == 0 {
    return None
  }
  if i != n {
    return None
  }
  let mut val = 0.0
  for c in int_digits {
    val = val * 8.0 + (c.to_int() - 48).to_double()
  }
  Some(if neg { -val } else { val })
}

///|
/// DR-074 §2 opt-in `0b` 2 進整数 (parse_oct_body の base=2 版、§7 pin により小数・指数不可)。
fn parse_bin_body(cs : Array[Char], i_start : Int, neg : Bool) -> Double? {
  let n = cs.length()
  let mut i = i_start
  let ibuf = StringBuilder::new()
  let after_int = match scan_bin_digits(cs, i, ibuf) {
    None => return None
    Some(x) => x
  }
  i = after_int
  let int_digits = ibuf.to_string()
  if int_digits.length() == 0 {
    return None
  }
  if i != n {
    return None
  }
  let mut val = 0.0
  for c in int_digits {
    val = val * 2.0 + (c.to_int() - 48).to_double()
  }
  Some(if neg { -val } else { val })
}

///|
/// DR-074 §2 opt-in base prefix (`0x` / `0X` / `0o` / `0O` / `0b` / `0B`) の総合 dispatcher。先頭符号
/// `[+-]` を合成可 (§7 pin、-0xff や +0x1.8p3 も受理)。prefix 判定後、body に応じて hex (float or int) /
/// oct / bin の各 parser に振り分ける。canonical (allow=false) からは呼ばれず、opt-in 時のみ試される。
fn parse_base_prefixed(s : String) -> Double? {
  let cs = chars_of(s)
  let n = cs.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if cs[i] == '+' || cs[i] == '-' {
    neg = cs[i] == '-'
    i = i + 1
  }
  if i + 1 >= n {
    return None
  }
  if cs[i] != '0' {
    return None
  }
  let c1 = cs[i + 1]
  i = i + 2
  match c1 {
    'x' | 'X' => parse_hex_body(cs, i, neg)
    'o' | 'O' => parse_oct_body(cs, i, neg)
    'b' | 'B' => parse_bin_body(cs, i, neg)
    _ => None
  }
}

///|
/// DR-074 §2 統合 number parser: `allow_base_prefix=false` は canonical な 10 進のみを受理し、
/// `true` では 10 進を先に試し、失敗時のみ base prefix を試す
/// (canonical と opt-in の受理域が排他なので順序に影響なし、DR-074 §2 「両方が一括で成功に転じる」)。
pub fn parse_number(s : String, allow_base_prefix? : Bool = false) -> Double? {
  match parse_decimal_number(s) {
    Some(d) => return Some(d)
    None => ()
  }
  if allow_base_prefix {
    parse_base_prefixed(s)
  } else {
    None
  }
}

///|
/// DR-075 § 値空間判定 + DR-074 §2 の int parser。canonical (allow=false) は 10 進のみを受理し、
/// opt-in 時は base prefix 経路も試す。hex integer (0xff=255) は整数値、hex float (0x1.8p3=12) は
/// binary64 の値が整数なら受理、非整数 (0x1.8=1.5) は int_round に従う (DR-074 §2 「10 進と同一規則を
/// hex にも適用」)。DR-075 §5 の binary64 非経由要件は 10 進 tie 判定に対する規定で、hex float は
/// base-2 aligned で binary64 に exactly 表現可能なので本経路の binary64 経由は spec 意図と整合。
/// NB: exact なのは mantissa 53 bit (hex ~13 桁) まで — それを超える hex mantissa は binary64 丸めが
/// 入り tie 判定が 10 進 false-tie と同型の問題を持ちうるが、その値域の挙動は DR-074 §2 が未規定
/// (fixture 未固定、病的入力域)。spec が規定したら追従する。
fn parse_int_value(
  s : String,
  mode : @engine.RoundMode,
  allow_base_prefix? : Bool = false,
) -> Result[Int64, @engine.ParseFail] {
  // 10 進経路を先に試す (canonical と opt-in で挙動同一)
  match parse_decimal_int_value(s, mode) {
    Ok(i) => return Ok(i)
    Err(@engine.NotANumber) => () // 10 進 lexer で not_a_number = base prefix 試行に落とす
    Err(e) => return Err(e) // @engine.NotAnInteger / @engine.IntOutOfRange は 10 進経路で確定した Error なので伝播
  }
  if !allow_base_prefix {
    return Err(@engine.NotANumber)
  }
  match parse_base_prefixed(s) {
    None => Err(@engine.NotANumber)
    Some(d) =>
      if @engine.is_integer(d) {
        // 整数値: mode 問わず受理。Int64 域内チェックは境界のみ (fixture は 0xff=255 レベル)
        let i = d.to_int64()
        if i.to_double() == d {
          Ok(i)
        } else {
          Err(@engine.IntOutOfRange)
        }
      } else {
        // fractional hex float: mode に従う
        match mode {
          @engine.RError => Err(@engine.NotAnInteger)
          _ => {
            // 単純化: binary64 上で is_integer 判定 + 丸め。DR-075 §5 の厳密判定は 10 進 tie のための
            // 規定 (findings 2026-07-06 の false-tie 域) で、hex float は base-2 aligned なので binary64
            // 上の丸めは exact。round-mode を Double に適用する簡易実装:
            let rounded = round_double_by_mode(d, mode)
            let i = rounded.to_int64()
            if i.to_double() == rounded {
              Ok(i)
            } else {
              Err(@engine.IntOutOfRange)
            }
          }
        }
      }
  }
}

///|
/// DR-075 §2 の 10 モードを Double 上で適用 (hex float 用の簡易実装)。base-2 aligned な hex float は
/// binary64 で exact なので、tie 判定・境界判定に false-tie の懸念なし。
fn round_double_by_mode(d : Double, mode : @engine.RoundMode) -> Double {
  // 整数値は素通し (呼び出し側で is_integer チェック済みだが防御的に)
  let floor_d = if d >= 0.0 {
    d.to_int64().to_double()
  } else {
    let f = d.to_int64().to_double()
    if f == d {
      f
    } else {
      f - 1.0
    }
  }
  let ceil_d = if d >= 0.0 {
    let f = d.to_int64().to_double()
    if f == d {
      f
    } else {
      f + 1.0
    }
  } else {
    d.to_int64().to_double()
  }
  let frac = d - floor_d // >= 0
  let is_tie = frac == 0.5
  let gt_half = frac > 0.5
  match mode {
    @engine.RFloor => floor_d
    @engine.RCeil => ceil_d
    @engine.RTrunc => if d >= 0.0 { floor_d } else { ceil_d }
    @engine.RAway => if d >= 0.0 { ceil_d } else { floor_d }
    @engine.RHalfFloor =>
      if is_tie {
        floor_d
      } else if gt_half {
        ceil_d
      } else {
        floor_d
      }
    @engine.RHalfCeil =>
      if is_tie {
        ceil_d
      } else if gt_half {
        ceil_d
      } else {
        floor_d
      }
    @engine.RHalfTrunc =>
      if is_tie {
        if d >= 0.0 {
          floor_d
        } else {
          ceil_d
        }
      } else if gt_half {
        ceil_d
      } else {
        floor_d
      }
    @engine.RHalfAway =>
      if is_tie {
        if d >= 0.0 {
          ceil_d
        } else {
          floor_d
        }
      } else if gt_half {
        ceil_d
      } else {
        floor_d
      }
    @engine.RHalfEven =>
      if is_tie {
        let fi = floor_d.to_int64()
        if fi % 2L == 0L {
          floor_d
        } else {
          ceil_d
        }
      } else if gt_half {
        ceil_d
      } else {
        floor_d
      }
    @engine.RError => d // caller の是非判定で拾われる
  }
}

///|
fn digits_to_int(s : String) -> Int {
  let mut acc = 0
  for c in s {
    acc = acc * 10 + (c.to_int() - 48)
  }
  acc
}

///|
fn digits_to_i64(s : String) -> Int64 {
  let mut acc : Int64 = 0
  for c in s {
    acc = acc * 10L + (c.to_int() - 48).to_int64()
  }
  acc
}

///|
/// Tolerant number parser (DR-074 §1 canonical): optional leading sign, decimal digits with an
/// optional single decimal point (`.5` / `1.` accepted), `_` thousands separators (default vocab),
/// and an optional `e`/`E` exponent with an optional sign. Base prefixes, type suffixes (`1.0f`),
/// inf/nan are NOT accepted (all → None). The value conversion delegates to the host's binary64
/// parser on a normalized, `_`-stripped lexeme (validating the 字句 is this leaf's job; DR-075's
/// binary64-非経由 requirement is on INT rounding only, handled in `parse_int_value`).
fn parse_decimal_number(s : String) -> Double? {
  match scan_number_parts(s) {
    None => None
    Some((neg, int_d, frac_d, exp)) => {
      let buf = StringBuilder::new()
      if neg {
        buf.write_char('-')
      }
      buf.write_string(if int_d.length() > 0 { int_d } else { "0" })
      if frac_d.length() > 0 {
        buf.write_char('.')
        buf.write_string(frac_d)
      }
      if exp != 0 {
        buf.write_char('e')
        buf.write_string(exp.to_string())
      }
      try_parse_double(buf.to_string())
    }
  }
}

///|
fn try_parse_double(clean : String) -> Double? {
  Some(@string.parse_double(clean)) catch {
    _ => None
  }
}

///|
/// Recognize the DR-074 §7 inf lexeme: an optional leading `[+-]` sign (the same rule as
/// `scan_number_parts`'s sign, §1) followed by a case-insensitive `inf` or `infinity` — the
/// confirmed 2-word set (`Inf`/`INF`/`Infinity` are case variants, not separately enumerated).
/// Returns the signed Double infinity, or None if `s` is not this exact lexeme (nan is NEVER
/// matched here — nan has no lexeme at all in canonical, DR-074 §1/§3 "採用しなかった案").
fn scan_inf(s : String) -> Double? {
  let cs = chars_of(s)
  let n = cs.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if cs[i] == '+' || cs[i] == '-' {
    neg = cs[i] == '-'
    i = i + 1
  }
  let rest = chars_to_str_from(cs, i)
  if !(eq_ci(rest, "inf") || eq_ci(rest, "infinity")) {
    return None
  }
  let inf : Double = 1.0 / 0.0
  Some(if neg { -inf } else { inf })
}

///|
fn chars_to_str_from(cs : Array[Char], start : Int) -> String {
  @engine.chars_to_str(cs, start, cs.length())
}

///|
/// Tolerant FLOAT parser (DR-074 §1/§7): the `float` type's accept域 is `parse_number`'s canonical
/// number lexicon PLUS the 2-word inf/infinity vocab (case-insensitive, sign-合成可) — nan is Error
/// for BOTH number and float (no lexeme accepted here, ever). A separate function from
/// `parse_number` because the accept-域 differs per resident (`number` rejects inf, `float`
/// accepts it, DR-074 §1) — `parse_number` itself stays number-canonical so every OTHER caller
/// (int's 値空間判定, config's number_type() path, matcher's number_type()/int_type() eq-split) is unaffected.
fn parse_float(s : String) -> Double? {
  match parse_number(s) {
    Some(d) => Some(d)
    None => scan_inf(s)
  }
}

// ── int 値空間判定 + int_round (DR-075) ────────────────────────────────────────

///|
fn repeat_zero(k : Int) -> String {
  let buf = StringBuilder::new()
  let mut j = 0
  while j < k {
    buf.write_char('0')
    j = j + 1
  }
  buf.to_string()
}

///|
fn all_zero(s : String) -> Bool {
  for c in s {
    if c != '0' {
      return false
    }
  }
  true
}

///|
fn has_nonzero(s : String, from : Int) -> Bool {
  let cs = chars_of(s)
  let mut i = from
  while i < cs.length() {
    if cs[i] != '0' {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// Fold the exponent into the digit列, yielding the plain `(integer_part_digits, frac_part_digits)`
/// with the decimal point materialized (no exponent left). e.g. int="1" frac="" exp=3 → ("1000","");
/// int="2" frac="5" exp=0 → ("2","5"); int="" frac="5" exp=0 → ("","5"). This is decimal 桁シフト,
/// done purely on digit strings so no binary64 rounding enters the integer/tie decision (DR-075 §5).
fn apply_exponent(
  int_d : String,
  frac_d : String,
  exp : Int,
) -> (String, String) {
  let combined = int_d + frac_d
  let point = int_d.length() + exp
  if point <= 0 {
    ("", repeat_zero(-point) + combined)
  } else if point >= combined.length() {
    (combined + repeat_zero(point - combined.length()), "")
  } else {
    (combined[0:point].to_owned(), combined[point:].to_owned())
  }
}

// ── Int64 range check (DR-075 §1-§2, issue 2026-07-07-parse-int-value-huge-exponent-overflow) ──

///|
/// Int64's two boundary magnitudes as canonical decimal digit strings, each exactly 19 digits: the
/// positive max `9223372036854775807`, and the negative min's ABSOLUTE magnitude `9223372036854775808`
/// (one more — two's-complement asymmetry). `digits_to_i64` cannot even REPRESENT
/// +9223372036854775808 as an intermediate positive value, so the min boundary needs its own
/// literal (`signed_magnitude_of` below), never "negate a would-be-overflowing positive".
let int64_max_mag : String = "9223372036854775807"

///|
let int64_min_mag : String = "9223372036854775808"

///|
fn count_leading_zeros(s : String) -> Int {
  let cs = chars_of(s)
  let n = cs.length()
  let mut i = 0
  while i < n && cs[i] == '0' {
    i = i + 1
  }
  i
}

///|
/// Lexicographic magnitude comparison for two EQUAL-LENGTH all-digit strings — valid without
/// numeric conversion because both operands have the same length (no leading-zero ambiguity):
/// `true` iff `a`'s magnitude is strictly greater than `b`'s.
fn digits_gt(a : String, b : String) -> Bool {
  let ca = chars_of(a)
  let cb = chars_of(b)
  let mut i = 0
  while i < ca.length() {
    if ca[i] != cb[i] {
      return ca[i] > cb[i]
    }
    i = i + 1
  }
  false
}

///|
/// The significant (leading-zeros-stripped) digit count the int-typed magnitude `int_d`/`frac_d`/
/// `exp` WOULD have after `apply_exponent`'s exponent shift — computed WITHOUT materializing that
/// shift, so a huge `exp` (`"1e300"`) never builds a giant digit string just to discover it
/// overflows. `int_d`/`frac_d` are never huge themselves (bounded by the literal input length —
/// only the exponent-driven zero-padding explodes), so this is O(len(int_d)+len(frac_d)) regardless
/// of `exp`'s magnitude. The caller rejects outright when this exceeds 19 (Int64's max digit count);
/// at exactly 19 it must still compare against the exact boundary (a value could be `1e18` = 19
/// digits `1000000000000000000`, well within range, or `1e19` = 20 digits, always out of range).
fn int_part_significant_len(int_d : String, frac_d : String, exp : Int) -> Int {
  let combined = int_d + frac_d
  let point = int_d.length() + exp
  if point <= 0 || all_zero(combined) {
    0
  } else {
    let lead = count_leading_zeros(combined)
    let capped_lead = if lead < point { lead } else { point }
    point - capped_lead
  }
}

///|
/// Convert an already-materialized `ipart` (the caller has verified, via
/// `int_part_significant_len`, that its significant digit count is <= 19 — so `ipart` itself is
/// bounded/small regardless of how huge the ORIGINAL exponent was) to its FINAL SIGNED Int64 value,
/// or `None` if the magnitude exceeds Int64's per-sign range. `neg` selects the boundary: a
/// positive value's magnitude tops out at `int64_max_mag`, a negative value's at the one-larger
/// `int64_min_mag` — and the `-9223372036854775808` case is returned directly as a literal, since
/// `digits_to_i64` cannot even represent its magnitude as an intermediate positive value to negate.
fn signed_magnitude_of(ipart : String, neg : Bool) -> Int64? {
  let lead = count_leading_zeros(ipart)
  let sig_len = ipart.length() - lead
  if sig_len < 19 {
    let m = digits_to_i64(ipart)
    return Some(if neg { -m } else { m })
  }
  // sig_len == 19 here (the caller already rejected > 19 before ipart was even materialized).
  let sig = ipart[lead:].to_owned()
  let boundary = if neg { int64_min_mag } else { int64_max_mag }
  if digits_gt(sig, boundary) {
    None
  } else if neg && sig == int64_min_mag {
    Some(-9223372036854775808L)
  } else {
    let m = digits_to_i64(ipart)
    Some(if neg { -m } else { m })
  }
}

///|
/// Convert `ipart` to its UNSIGNED (always non-negative) magnitude, checked ONLY against the
/// positive boundary `int64_max_mag` regardless of the value's actual sign — this is what
/// `round_magnitude` needs (DR-075 §2: it applies `+1`/the sign itself on this unsigned magnitude).
/// A truncated magnitude that sits exactly at Int64::min's boundary (9223372036854775808) can't be
/// represented unsigned at all, so it is (narrowly, conservatively) reported out-of-range here too
/// — an accepted residual gap: that exact magnitude, ALSO genuinely fractional, under a non-error
/// rounding mode is astronomically rare and outside this issue's test matrix.
fn unsigned_magnitude_of(ipart : String) -> Int64? {
  let lead = count_leading_zeros(ipart)
  let sig_len = ipart.length() - lead
  if sig_len < 19 {
    return Some(digits_to_i64(ipart))
  }
  let sig = ipart[lead:].to_owned()
  if digits_gt(sig, int64_max_mag) {
    None
  } else {
    Some(digits_to_i64(ipart))
  }
}

///|
/// Round a non-negative magnitude `m` (the integer部) given the first fractional digit `d0` and
/// whether any later fractional digit is non-zero, plus the sign and the mode (DR-075 §2 table).
/// The tie/half classification is lexical (d0<5 / d0=5&rest=0 / else) — no binary64 involved.
fn round_magnitude(
  m : Int64,
  d0 : Int,
  rest_nonzero : Bool,
  neg : Bool,
  mode : @engine.RoundMode,
) -> Int64 {
  let gt_half = d0 > 5 || (d0 == 5 && rest_nonzero)
  let is_tie = d0 == 5 && !rest_nonzero
  let up = m + 1L
  match mode {
    @engine.RFloor => if neg { up } else { m } // →−∞
    @engine.RCeil => if neg { m } else { up } // →+∞
    @engine.RTrunc => m // →0 (drop fraction)
    @engine.RAway => up // →0 の反対 (abs 切り上げ)
    @engine.RHalfFloor =>
      if is_tie {
        if neg {
          up
        } else {
          m
        }
      } else if gt_half {
        up
      } else {
        m
      }
    @engine.RHalfCeil =>
      if is_tie {
        if neg {
          m
        } else {
          up
        }
      } else if gt_half {
        up
      } else {
        m
      }
    @engine.RHalfTrunc => if is_tie { m } else if gt_half { up } else { m }
    @engine.RHalfAway => if is_tie { up } else if gt_half { up } else { m }
    @engine.RHalfEven =>
      if is_tie {
        if m % 2L == 0L {
          m
        } else {
          up
        }
      } else if gt_half {
        up
      } else {
        m
      }
    @engine.RError => m // caller handles @engine.RError before reaching here
  }
}

///|
/// Decode a canonical `int_round` config string (DR-061 §4 平坦 config キー、DR-075 §2 の 10 種語彙)
/// to its `@engine.RoundMode`. Returns None on an unknown token (typo / non-canonical vocab) — the caller
/// surfaces this as a `DecodeSkip` or a factory-config Error (DR-061 §4: config 値の検証は factory
/// 責務). The 10 tokens are byte-identical to DR-075's naming (no HALF_UP/HALF_DOWN aliases).
pub fn round_mode_of(s : String) -> @engine.RoundMode? {
  match s {
    "error" => Some(@engine.RError)
    "floor" => Some(@engine.RFloor)
    "ceil" => Some(@engine.RCeil)
    "trunc" => Some(@engine.RTrunc)
    "away" => Some(@engine.RAway)
    "half_floor" => Some(@engine.RHalfFloor)
    "half_ceil" => Some(@engine.RHalfCeil)
    "half_trunc" => Some(@engine.RHalfTrunc)
    "half_away" => Some(@engine.RHalfAway)
    "half_even" => Some(@engine.RHalfEven)
    _ => None
  }
}

///|
/// Parse a String token as an `int` element per DR-075: 値空間判定. Parse the token as a canonical
/// number, then judge its VALUE. An integer value (`"3.0"`→3 / `"1e3"`→1000 / `"1_000"`→1000) is
/// accepted directly under every mode. A truly-fractional value follows `mode`: `@engine.RError` (canonical
/// default) → `@engine.NotAnInteger`; any rounding mode → the rounded Int64. A non-number token → `@engine.NotANumber`.
/// The整数性 and tie decisions are lexical (binary64-非経由, DR-075 §5).
fn parse_decimal_int_value(
  s : String,
  mode : @engine.RoundMode,
) -> Result[Int64, @engine.ParseFail] {
  match scan_number_parts(s) {
    None => Err(@engine.NotANumber)
    Some((neg, int_d, frac_d, exp)) => {
      // Range guard BEFORE materializing apply_exponent's zero-padding (issue
      // 2026-07-07-parse-int-value-huge-exponent-overflow): reject up front when the significant
      // digit count already exceeds Int64's 19-digit max, so a huge `exp` (`"1e300"`) never builds
      // the giant digit string just to discover it overflows.
      if int_part_significant_len(int_d, frac_d, exp) > 19 {
        return Err(@engine.IntOutOfRange)
      }
      let (ipart, fpart) = apply_exponent(int_d, frac_d, exp)
      if all_zero(fpart) {
        // integer value — accepted under every mode, no rounding
        match signed_magnitude_of(ipart, neg) {
          None => Err(@engine.IntOutOfRange)
          Some(m) => Ok(m)
        }
      } else {
        match mode {
          @engine.RError => Err(@engine.NotAnInteger)
          _ =>
            // round_magnitude needs an UNSIGNED magnitude (it applies +1 / the sign itself, DR-075
            // §2), so the pre-rounding range check always uses the POSITIVE boundary regardless of
            // `neg` — see `unsigned_magnitude_of`'s doc for the narrow residual gap this implies.
            match unsigned_magnitude_of(ipart) {
              None => Err(@engine.IntOutOfRange)
              Some(m) => {
                let d0 = fpart[0].to_int() - 48
                let rest_nonzero = has_nonzero(fpart, 1)
                let mag = round_magnitude(m, d0, rest_nonzero, neg, mode)
                if mag < 0L {
                  // `m + 1` silently wrapped past Int64::max (m was already at the exact boundary
                  // and rounding pushed it over) — surface as out-of-range, not a wrapped sign.
                  Err(@engine.IntOutOfRange)
                } else {
                  Ok(if neg { -mag } else { mag })
                }
              }
            }
        }
      }
    }
  }
}

// ── bool canonical 字句 (DR-074 §3) ────────────────────────────────────────────

///|
fn eq_ci(s : String, target : String) -> Bool {
  let a = chars_of(s)
  let b = chars_of(target)
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if lower_code(a[i]) != lower_code(b[i]) {
      return false
    }
  }
  true
}

///|
fn lower_code(c : Char) -> Int {
  let x = c.to_int()
  if x >= 65 && x <= 90 {
    x + 32 // ASCII 'A'-'Z' → 'a'-'z'
  } else {
    x
  }
}
