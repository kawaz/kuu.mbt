// value.mbt — value cells, provenance tags, and the tolerant number/bool parsers.
//
// These are the leaf currency of the evaluator: a parsed CLI token becomes a
// `Value`, tagged with the `Source` seat it came from (DR-031 ladder), and
// collected as `Binding`s onto a result path.
//
// DR-074 fixes the canonical number/bool 字句; DR-075 fixes int's 値空間判定 and
// the `int_round` rounding modes (with the binary64-非経由 requirement realized by
// lexical scanning here). MDR-002 §3: value.mbt depends on node.mbt only.
//
// `Binding` / `ParseError` (DR-066 5-field with reason) live here; `Branch` and `Cand` live in
// node.mbt. The matcher builds bindings via the mkb / cat / pe_parse / depr_marker helpers at the
// end of this file.

///|
/// A resolved value that can land in the result object.
pub(all) enum Value {
  VStr(String)
  VNum(Double)
  VBool(Bool)
} derive(Eq, Debug)

///|
/// Provenance of a value cell (DR-031 / DR-016 source tag).
/// The evaluator preserves this so an appconfig store (DR-030) can ask
/// "where did this value come from" without the ladder order being movable.
pub(all) enum Source {
  Cli // CLI explicit / link — highest seat (DR-031 #1)
  Env // environment variable seat (DR-031 #2)
  Config // config-file seat (DR-050 #3) — below env, above inherit
  Inherit // nearest ancestor scope's same-named value (DR-031 #4 / DR-013)
  Default // fixed fallback (DR-031 #5)
} derive(Eq, Debug)

///|
/// A JSON-同型 hierarchical config value (DR-050 §2): what a config_provider returns. kuu core
/// never sees TOML/YAML — only this shape. Leaf values are typed (string / number / bool); arrays
/// feed a multiple element's pieces; objects mirror the name-scope hierarchy (同型対応).
pub(all) enum ConfigVal {
  CStr(String)
  CNum(Double)
  CBool(Bool)
  CArr(Array[ConfigVal])
  CObj(Array[(String, ConfigVal)])
  CNull // JSON null (DR-050 §4 / DR-051): treated as 供給なし — the config seat supplies nothing
} derive(Eq, Debug)

///|
/// The int rounding mode (DR-075 §2). Direction 4 (`floor`/`ceil`/`trunc`/`away`) × {plain, half}
/// + `half_even` + `error` = 10 modes, 体系完備. `error` is the canonical default (int silently
/// coerces nothing; a non-integer VALUE is rejected). Direction語 name 0-起点 (`trunc`/`away`) と
/// 無限-起点 (`floor`/`ceil`) を分け、Java/Python の "UP"/"DOWN" 多義を持ち込まない (DR-075 §3).
pub(all) enum RoundMode {
  RFloor // →−∞
  RCeil // →+∞
  RTrunc // →0 方向 (小数部を捨てる)
  RAway // →0 の反対方向 (絶対値切り上げ)
  RHalfFloor // tie→−∞
  RHalfCeil // tie→+∞
  RHalfTrunc // tie→0 方向
  RHalfAway // tie→0 の反対 (学校四捨五入)
  RHalfEven // banker's rounding
  RError // 非整数値は Error
} derive(Eq, Debug)

///|
/// DESIGN §7.2 / DR-096 §1: scope config `long_eq_sep` の 3 値。long の eq 分割形 (`key=value`) と
/// space 分割形 (`key value`) の入口をダイヤルする。`EsRequire` = eq 分割形のみ受理 (space-form main
/// entry を withhold、DR-091 §3 の eq 必須意味論)、`EsAllow` (既定) = 両方受理、
/// `EsDeny` = eq 分割 matcher を生成せず space 分割形のみ受理。
/// 3 値 enum のため「eq 必須かつ eq 禁止」のような組合せはそもそも構文的に表現できない (illegal
/// states unrepresentable、DR-096 §1)。
pub(all) enum EqSepMode {
  EsRequire
  EsAllow
  EsDeny
} derive(Eq, Debug)

///|
/// Decode a canonical `long_eq_sep` config string (DR-096 §1) to its `EqSepMode`. Returns None on an
/// unknown token — the caller surfaces this as a `DecodeSkip` (`int_round`/`round_mode_of` と同じ
/// 前例パターン、`json_conformance_wbtest.mbt` の呼び出し側)。
pub fn eq_sep_mode_of(s : String) -> EqSepMode? {
  match s {
    "require" => Some(EsRequire)
    "allow" => Some(EsAllow)
    "deny" => Some(EsDeny)
    _ => None
  }
}

///|
/// DESIGN §7.2 / DR-096 §2: scope config `short_attached_value` の 3 値。値持ち short の付着形
/// (`-O2`) と space 分割形 (`-O 2`) の入口をダイヤルする。`AtRequire` = 付着形のみ受理し space-form
/// の読み枝が立たない (gcc/clang の `-O`/`-W` 型)、`AtAllow` (既定) = 両方受理 (DR-041 §4 の値スロット
/// 一般規則そのまま)、`AtDeny` = 付着読みの枝を生成せず space 分割形のみ受理する。値スロットを持たない
/// 要素 (flag/count) にはダイヤルが届いても inert (DR-096 §3.2)。`long_eq_sep` (`EqSepMode`) とは
/// 軸そのものが異なる別型 — short に eq 分割形は存在しない (DR-096 §3.4)。
pub(all) enum AttachMode {
  AtRequire
  AtAllow
  AtDeny
} derive(Eq, Debug)

///|
/// Decode a canonical `short_attached_value` config string (DR-096 §2) to its `AttachMode`.
/// Returns None on an unknown token (`eq_sep_mode_of` と同型の前例パターン)。
pub fn attach_mode_of(s : String) -> AttachMode? {
  match s {
    "require" => Some(AtRequire)
    "allow" => Some(AtAllow)
    "deny" => Some(AtDeny)
    _ => None
  }
}

///|
/// bool の factory config (DR-074 §3/§4 `bool_parser`, DR-061 §3 configurable factory)。canonical
/// default (`bool_config_canonical`) は `true_values: ["true","1"]` / `false_values: ["false","0",""]`
/// / `case_insensitive: true` — 既存 `parse_bool` のハードコード語彙と同値 (置き換えではなく同じ表を
/// データ化しただけ、対極確認は wbtest 側)。opt-in で `true_values`/`false_values` に `yes`/`on` 等を
/// 追加する (DR-074 §4 の `+[...]` 表記は「default 配列に語彙を足した完成形をそのまま渡す」の意 — wire
/// 上は置換であって merge ではない、config は純データという DR-061 §4 の原則通り)。
pub(all) struct BoolConfig {
  true_values : Array[String]
  false_values : Array[String]
  case_insensitive : Bool
} derive(Eq, Debug)

///|
/// canonical default config (DR-074 §3)。TypeShadow/ElemDef の bool_config 既定値、および
/// `parse_bool`(configなし呼び出し) が委譲する先。
pub fn bool_config_canonical() -> BoolConfig {
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
/// posture as the canonical-only `parse_bool`). `parse_bool(s)` below is this function specialized to
/// `bool_config_canonical()` — the SAME canonical table, just expressed as data instead of literal
/// `if` branches (DR-061 §3 「クロージャをデータ化」).
pub fn parse_bool_ext(s : String, config : BoolConfig) -> Bool? {
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

///|
/// The reason an int/number parse failed (DR-066 語彙): `NotANumber` = not a number at all,
/// `NotAnInteger` = a non-integer value under `int_round: error`. `IntOutOfRange` = a readable
/// integer VALUE whose magnitude exceeds Int64's range (issue
/// 2026-07-07-parse-int-value-huge-exponent-overflow: `"1e300"` etc. used to silently wrap via
/// `digits_to_i64` instead of erroring). DR-066 v1 has no reason for this yet — `int_out_of_range`
/// is a provisional reason, the SAME kind of gap-fill as `pe_parse_bool`'s `not_a_bool`
/// (docs/issue/2026-07-07-bool-invalid-reason-vocab-gap.md); the spec-side vocab decision is
/// tracked separately (spec repo kawaz/kuu issue, filed by the team lead).
pub(all) enum ParseFail {
  NotANumber
  NotAnInteger
  IntOutOfRange
} derive(Eq, Debug)

///|
/// Whether a double is integer-valued (for the int type on a config NATIVE number, DR-075 §5:
/// a JSON-由来 native number is already binary64, so this seat判定 is binary64-based — the
/// non-transit requirement applies to String源 only, handled by `parse_int_value`).
pub fn is_integer(d : Double) -> Bool {
  d.to_int().to_double() == d
}

///|
/// The category of a held Error (DR-053 §2 / DR-037 / DR-047): `parse` = type parse failure,
/// `filter` = a piece/value/cell filter reject (a value that parsed but failed a filter), `constraint` = a
/// delayed-predicate violation (required 未充足 etc., DR-047). All three ride the errors array.
pub(all) enum ErrKind {
  KParse
  KFilter
  KConstraint
} derive(Eq, Debug)

///|
/// One held Error (DR-053 §2 + DR-066): which element, the argv position it failed at, its kind, a
/// machine-readable `reason` (snake_case, DR-066 §3 v1 vocab: missing_operand / unexpected_token /
/// not_a_number / not_an_integer / <attr>_violated), the human message, and `path` (DR-066 §4): the
/// root-first ancestor scope names the error fired under (snoc form — `path` = ancestors, `element` =
/// self; `path: []` = root 直下, no separate null case, Maybe ⊂ List). The errors array keeps ALL of
/// them (別候補経路の別 Error); primary = max argv_pos. Conformance compares errors by
/// (element, argv_pos, kind, reason) — message is always ignored (CONFORMANCE §3), path is optional
/// (DR-066 §4) — so every construction site emits a reason from the v1 vocabulary and a path (`[]`
/// when the error has no ancestor scope to record, which conformance treats identically to "no path
/// asserted" when the fixture opts out).
pub(all) struct ParseError {
  element : String
  argv_pos : Int
  kind : ErrKind
  reason : String // DR-066 §3: machine-readable failure identifier (snake_case v1 vocab)
  message : String
  path : Array[String] // DR-066 §4: root-first ancestor scope names (snoc form, [] = root 直下)
} derive(Eq, Debug)

///|
/// JSON-standard string form of a config number (DR-050 §4 stringification). An integer-valued
/// double renders without a fractional part (1.0 → "1"); otherwise the decimal form (1.5 → "1.5").
fn num_to_string(d : Double) -> String {
  let i = d.to_int()
  if i.to_double() == d {
    i.to_string()
  } else {
    d.to_string()
  }
}

// ── canonical number 字句スキャン (DR-074 §1, §7) ──────────────────────────────

///|
/// String indexing (`s[i]`) yields a UTF-16 code unit, not a Char, so the number 字句スキャン works
/// on Array[Char] (iterating a String yields Char). Test tokens are ASCII.
fn chars_of(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
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
/// DR-074 §2 統合 opt-in の number parser: `allow_base_prefix=false` は既存 canonical parse_number と
/// 等価 (10 進のみ、base prefix は None)。`true` では 10 進を先に試し、失敗時のみ base prefix を試す
/// (canonical と opt-in の受理域が排他なので順序に影響なし、DR-074 §2 「両方が一括で成功に転じる」)。
pub fn parse_number_ext(s : String, allow_base_prefix : Bool) -> Double? {
  match parse_number(s) {
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
/// DR-075 § 値空間判定 + DR-074 §2 opt-in の int parser。canonical (allow=false) は既存 parse_int_value
/// と等価。opt-in 時は base prefix 経路も試し、hex integer (0xff=255) は整数値、hex float (0x1.8p3=12) は
/// binary64 の値が整数なら受理、非整数 (0x1.8=1.5) は int_round に従う (DR-074 §2 「10 進と同一規則を
/// hex にも適用」)。DR-075 §5 の binary64 非経由要件は 10 進 tie 判定に対する規定で、hex float は
/// base-2 aligned で binary64 に exactly 表現可能なので本経路の binary64 経由は spec 意図と整合。
/// NB: exact なのは mantissa 53 bit (hex ~13 桁) まで — それを超える hex mantissa は binary64 丸めが
/// 入り tie 判定が 10 進 false-tie と同型の問題を持ちうるが、その値域の挙動は DR-074 §2 が未規定
/// (fixture 未固定、病的入力域)。spec が規定したら追従する。
pub fn parse_int_value_ext(
  s : String,
  mode : RoundMode,
  allow_base_prefix : Bool,
) -> Result[Int64, ParseFail] {
  // 10 進経路を先に試す (canonical と opt-in で挙動同一)
  match parse_int_value(s, mode) {
    Ok(i) => return Ok(i)
    Err(NotANumber) => () // 10 進 lexer で not_a_number = base prefix 試行に落とす
    Err(e) => return Err(e) // NotAnInteger / IntOutOfRange は 10 進経路で確定した Error なので伝播
  }
  if !allow_base_prefix {
    return Err(NotANumber)
  }
  match parse_base_prefixed(s) {
    None => Err(NotANumber)
    Some(d) =>
      if is_integer(d) {
        // 整数値: mode 問わず受理。Int64 域内チェックは境界のみ (fixture は 0xff=255 レベル)
        let i = d.to_int64()
        if i.to_double() == d {
          Ok(i)
        } else {
          Err(IntOutOfRange)
        }
      } else {
        // fractional hex float: mode に従う
        match mode {
          RError => Err(NotAnInteger)
          _ => {
            // 単純化: binary64 上で is_integer 判定 + 丸め。DR-075 §5 の厳密判定は 10 進 tie のための
            // 規定 (findings 2026-07-06 の false-tie 域) で、hex float は base-2 aligned なので binary64
            // 上の丸めは exact。round-mode を Double に適用する簡易実装:
            let rounded = round_double_by_mode(d, mode)
            let i = rounded.to_int64()
            if i.to_double() == rounded {
              Ok(i)
            } else {
              Err(IntOutOfRange)
            }
          }
        }
      }
  }
}

///|
/// DR-075 §2 の 10 モードを Double 上で適用 (hex float 用の簡易実装)。base-2 aligned な hex float は
/// binary64 で exact なので、tie 判定・境界判定に false-tie の懸念なし。
fn round_double_by_mode(d : Double, mode : RoundMode) -> Double {
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
    RFloor => floor_d
    RCeil => ceil_d
    RTrunc => if d >= 0.0 { floor_d } else { ceil_d }
    RAway => if d >= 0.0 { ceil_d } else { floor_d }
    RHalfFloor =>
      if is_tie {
        floor_d
      } else if gt_half {
        ceil_d
      } else {
        floor_d
      }
    RHalfCeil =>
      if is_tie {
        ceil_d
      } else if gt_half {
        ceil_d
      } else {
        floor_d
      }
    RHalfTrunc =>
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
    RHalfAway =>
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
    RHalfEven =>
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
    RError => d // caller の是非判定で拾われる
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
pub fn parse_number(s : String) -> Double? {
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
  let buf = StringBuilder::new()
  let mut i = start
  while i < cs.length() {
    buf.write_char(cs[i])
    i = i + 1
  }
  buf.to_string()
}

///|
/// Tolerant FLOAT parser (DR-074 §1/§7): the `float` type's accept域 is `parse_number`'s canonical
/// number lexicon PLUS the 2-word inf/infinity vocab (case-insensitive, sign-合成可) — nan is Error
/// for BOTH number and float (no lexeme accepted here, ever). A separate function from
/// `parse_number` because the accept-域 differs per TYPE (`Ty::TNum` rejects inf, `Ty::TFloat`
/// accepts it, DR-074 §1) — `parse_number` itself stays number-canonical so every OTHER caller
/// (int's 値空間判定, config's TNum path, matcher's TNum/TInt eq-split) is unaffected.
pub fn parse_float(s : String) -> Double? {
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
  mode : RoundMode,
) -> Int64 {
  let gt_half = d0 > 5 || (d0 == 5 && rest_nonzero)
  let is_tie = d0 == 5 && !rest_nonzero
  let up = m + 1L
  match mode {
    RFloor => if neg { up } else { m } // →−∞
    RCeil => if neg { m } else { up } // →+∞
    RTrunc => m // →0 (drop fraction)
    RAway => up // →0 の反対 (abs 切り上げ)
    RHalfFloor =>
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
    RHalfCeil =>
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
    RHalfTrunc => if is_tie { m } else if gt_half { up } else { m }
    RHalfAway => if is_tie { up } else if gt_half { up } else { m }
    RHalfEven =>
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
    RError => m // caller handles RError before reaching here
  }
}

///|
/// Decode a canonical `int_round` config string (DR-061 §4 平坦 config キー、DR-075 §2 の 10 種語彙)
/// to its `RoundMode`. Returns None on an unknown token (typo / non-canonical vocab) — the caller
/// surfaces this as a `DecodeSkip` or a factory-config Error (DR-061 §4: config 値の検証は factory
/// 責務). The 10 tokens are byte-identical to DR-075's naming (no HALF_UP/HALF_DOWN aliases).
pub fn round_mode_of(s : String) -> RoundMode? {
  match s {
    "error" => Some(RError)
    "floor" => Some(RFloor)
    "ceil" => Some(RCeil)
    "trunc" => Some(RTrunc)
    "away" => Some(RAway)
    "half_floor" => Some(RHalfFloor)
    "half_ceil" => Some(RHalfCeil)
    "half_trunc" => Some(RHalfTrunc)
    "half_away" => Some(RHalfAway)
    "half_even" => Some(RHalfEven)
    _ => None
  }
}

///|
/// Parse a String token as an `int` element per DR-075: 値空間判定. Parse the token as a canonical
/// number, then judge its VALUE. An integer value (`"3.0"`→3 / `"1e3"`→1000 / `"1_000"`→1000) is
/// accepted directly under every mode. A truly-fractional value follows `mode`: `RError` (canonical
/// default) → `NotAnInteger`; any rounding mode → the rounded Int64. A non-number token → `NotANumber`.
/// The整数性 and tie decisions are lexical (binary64-非経由, DR-075 §5).
pub fn parse_int_value(
  s : String,
  mode : RoundMode,
) -> Result[Int64, ParseFail] {
  match scan_number_parts(s) {
    None => Err(NotANumber)
    Some((neg, int_d, frac_d, exp)) => {
      // Range guard BEFORE materializing apply_exponent's zero-padding (issue
      // 2026-07-07-parse-int-value-huge-exponent-overflow): reject up front when the significant
      // digit count already exceeds Int64's 19-digit max, so a huge `exp` (`"1e300"`) never builds
      // the giant digit string just to discover it overflows.
      if int_part_significant_len(int_d, frac_d, exp) > 19 {
        return Err(IntOutOfRange)
      }
      let (ipart, fpart) = apply_exponent(int_d, frac_d, exp)
      if all_zero(fpart) {
        // integer value — accepted under every mode, no rounding
        match signed_magnitude_of(ipart, neg) {
          None => Err(IntOutOfRange)
          Some(m) => Ok(m)
        }
      } else {
        match mode {
          RError => Err(NotAnInteger)
          _ =>
            // round_magnitude needs an UNSIGNED magnitude (it applies +1 / the sign itself, DR-075
            // §2), so the pre-rounding range check always uses the POSITIVE boundary regardless of
            // `neg` — see `unsigned_magnitude_of`'s doc for the narrow residual gap this implies.
            match unsigned_magnitude_of(ipart) {
              None => Err(IntOutOfRange)
              Some(m) => {
                let d0 = fpart[0].to_int() - 48
                let rest_nonzero = has_nonzero(fpart, 1)
                let mag = round_magnitude(m, d0, rest_nonzero, neg, mode)
                if mag < 0L {
                  // `m + 1` silently wrapped past Int64::max (m was already at the exact boundary
                  // and rounding pushed it over) — surface as out-of-range, not a wrapped sign.
                  Err(IntOutOfRange)
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

///|
/// Parse a String token as a bool (DR-074 §3 canonical): `true_values = ["true","1"]`,
/// `false_values = ["false","0",""]`, `case_insensitive = true`. An unrecognized token is None
/// (→ Error at the call site — no silent bool化, DR-021 姿勢). The empty string is false (env's
/// `FLAG=` pattern); `yes`/`no`/`on`/`off` are canonical-外 (Norway problem 回避). Every call site
/// that has no `bool_parser` factory config to consult (config_to_value/env_value's canonical-only
/// arms) keeps calling this — it is `parse_bool_ext` specialized to `bool_config_canonical()`.
pub fn parse_bool(s : String) -> Bool? {
  parse_bool_ext(s, bool_config_canonical())
}

///|
/// Convert one leaf config value to the element's expected type (DR-050 §4). Leniency is
/// BIDIRECTIONALLY SYMMETRIC (DR-040 canonical): a string parses into any type (`"8080"` → number),
/// AND a JSON scalar stringifies into a string element (`1.5` → "1.5", `true` → "true"). The int
/// path is 値空間判定 with canonical `int_round: error` (DR-075): `"3.0"` → 3, `"2.5"` → Error. Bool
/// is the canonical vocab (DR-074 §3). Only the 意味の飛躍 (bool ↔ number) and 構造不一致
/// (array/object → scalar) are DR-037 Errors.
///
/// `piece_filters` (DR-050 §4 "string → CLI/env と完全に同一の全段 pipeline"、issue
/// 2026-07-09-config-string-pieceprocessor-gap): applied ONCE, up front, ONLY when the JSON source
/// is a string (`CStr`) — a non-string source matching its type (`CNum`/`CBool`) has no
/// String→String step to gate, per §4's "型一致なら piece_filters/parse はスキップ" (the type's own
/// consequence, not a special case here; mirrors `resolve.mbt`'s `env_value`, whose source is
/// ALWAYS a string so it always runs piece_filters — config's source varies, so this runs it exactly
/// when config's source happens to be a string). Every `(CStr(s), _)` arm below sees the
/// ALREADY-filtered string.
///
/// Error shape `(ErrKind, reason, message)`: `KFilter` for a piece_filters rejection (mirrors
/// `resolve.mbt`'s `filter_err`), `KParse` for every type-mismatch/parse-failure arm (mirrors
/// `ladder_err`) — the caller picks the matching `ParseError` constructor by this tag. `message`
/// is caller-facing text only (conformance ignores it, per this file's `ParseError` doc comment).
pub fn config_to_value(
  cv : ConfigVal,
  ty : Ty,
  piece_filters : Array[FilterSpelling],
) -> Result[Value, (ErrKind, String, String)] {
  let cv = match cv {
    CStr(raw) =>
      match apply_piece_filters(piece_filters, raw) {
        Ok(s) => CStr(s)
        Err((reason, msg)) => return Err((KFilter, reason, msg))
      }
    other => other
  }
  match (cv, ty) {
    // string element: accept anything — string / lenient parse / JSON stringification
    (CStr(s), TStr) => Ok(VStr(s))
    (CNum(d), TStr) => Ok(VStr(num_to_string(d))) // 1.5 → "1.5" (寛容の双方向対称)
    (CBool(b), TStr) => Ok(VStr(if b { "true" } else { "false" })) // true → "true"
    // string → number: lenient canonical parse (DR-074). `TCount` folded in defensively (DR-077
    // §3: count's config seat sets a plain number, never increments — `Entity.ty` is already
    // collapsed to TNum for every real count cell by `ensure_entity`, so this arm never actually
    // sees TCount in practice).
    (CStr(s), TNum) | (CStr(s), TCount) =>
      match parse_number(s) {
        Some(d) => Ok(VNum(d))
        None =>
          Err((KParse, "not_a_number", "config value \"\{s}\" is not a number"))
      }
    // string → float: wider accept域 (number + inf, DR-074 §1) via parse_float
    (CStr(s), TFloat) =>
      match parse_float(s) {
        Some(d) => Ok(VNum(d))
        None =>
          Err((KParse, "not_a_number", "config value \"\{s}\" is not a number"))
      }
    // string → int: 値空間判定, canonical int_round = error (DR-075 §1-§2)
    (CStr(s), TInt) =>
      match parse_int_value(s, RError) {
        Ok(i) => Ok(VNum(i.to_double()))
        Err(NotAnInteger) =>
          Err(
            (
              KParse,
              "not_an_integer",
              "config value \"\{s}\" is not an integer",
            ),
          )
        Err(IntOutOfRange) =>
          Err(
            (
              KParse,
              "int_out_of_range",
              "config value \"\{s}\" is out of Int64 range",
            ),
          )
        Err(NotANumber) =>
          Err((KParse, "not_a_number", "config value \"\{s}\" is not a number"))
      }
    // string → bool: canonical vocab (DR-074 §3), unrecognized → Error (no silent 変換). Applies
    // identically to a presence-only flag (TFlag) and a value-typed bool (TBool) — config's string
    // seat doesn't distinguish the CLI-side eq-split capability (installer.mbt), only the value type.
    (CStr(s), TFlag) | (CStr(s), TBool) =>
      match parse_bool(s) {
        Some(b) => Ok(VBool(b))
        None =>
          Err((KParse, "not_a_bool", "config value \"\{s}\" is not a bool"))
      }
    // typed number matching a number element (any) / a float element (a JSON-native number is
    // already a valid float value — inf has no JSON literal, so this arm never carries it) / an
    // int element (integer only)
    (CNum(d), TNum) | (CNum(d), TFloat) | (CNum(d), TCount) => Ok(VNum(d))
    // native number → int: JSON 由来 binary64 経由判定 (DR-075 §5 の非対称)
    (CNum(d), TInt) =>
      if is_integer(d) {
        Ok(VNum(d))
      } else {
        Err(
          (
            KParse,
            "not_an_integer",
            "config value \"\{num_to_string(d)}\" is not an integer",
          ),
        )
      }
    (CBool(b), TFlag) | (CBool(b), TBool) => Ok(VBool(b))
    // 意味の飛躍 (bool ↔ number) は Error — no coercion
    (CNum(_), TFlag) | (CNum(_), TBool) =>
      Err(
        (
          KParse,
          "config_type_mismatch",
          "config number for a bool element (no number↔bool coercion)",
        ),
      )
    (CBool(_), TNum) | (CBool(_), TFloat) | (CBool(_), TCount) =>
      Err(
        (
          KParse,
          "config_type_mismatch",
          "config bool for a number element (no number↔bool coercion)",
        ),
      )
    // DR-089: none has no value space at all, so a config seat is a structural mismatch regardless
    // of the JSON scalar kind supplied (same family as the CArr/CObj structural-mismatch arms
    // below, just against a scalarless element instead of a non-scalar JSON value).
    (CStr(_), TNone) | (CNum(_), TNone) | (CBool(_), TNone) =>
      Err(
        (
          KParse,
          "config_type_mismatch",
          "config value for a none element (no value space)",
        ),
      )
    (CBool(_), TInt) =>
      Err(
        (
          KParse,
          "config_type_mismatch",
          "config bool for an int element (no number↔bool coercion)",
        ),
      )
    // 構造不一致 (array / object → scalar element) は Error
    (CArr(_), _) =>
      Err(
        (
          KParse,
          "config_structural_mismatch",
          "config array for a scalar element (structural mismatch)",
        ),
      )
    (CObj(_), _) =>
      Err(
        (
          KParse,
          "config_structural_mismatch",
          "config object for a scalar element (structural mismatch)",
        ),
      )
    // null is 供給なし (handled before this by resolve; defensive arm for exhaustiveness, DR-050 §4)
    (CNull, _) =>
      Err(
        (
          KParse,
          "config_type_mismatch",
          "config null is 供給なし (should be handled as no-supply, not converted)",
        ),
      )
  }
}

///|
/// DR-083 §2: a declared default's stored piece is already a `Value` (decoded straight off the
/// JSON literal, `VStr`/`VNum`/`VBool` — never `VStr` coerced to the element's `Ty` at decode time,
/// mirroring how a config array's piece is stored as an untyped `ConfigVal` until READ). This is
/// the bridge that lets `resolve_ladder_below_cli`'s default seat reuse `config_to_value` VERBATIM
/// (DR-083 §2 "config array と同型に扱う") instead of re-deriving the same string/number/bool
/// leniency table a second time — `Value`'s 3 variants map 1:1 onto `ConfigVal`'s 3 scalar ones.
pub fn value_to_configval(v : Value) -> ConfigVal {
  match v {
    VStr(s) => CStr(s)
    VNum(d) => CNum(d)
    VBool(b) => CBool(b)
  }
}

///|
/// The effect an entry's firing applies to a value cell (DR-045). It is PURE DATA
/// `{op, operand?}`: the op names the operation, the operand is the Binding's `value`.
/// A normal value bind (a value slot consuming a token and writing it) is the SET
/// degenerate form, so every effect-column element is uniform (entity, op, operand,
/// source, order). `default`/`unset`/`empty` carry NO operand (the Binding's value is a
/// placeholder). The four ops correspond 1:1 to DR-011's variant effect vocabulary.
pub(all) enum EffectOp {
  Set // write the operand; committed (the degenerate form of a plain value bind)
  Default // reset to the default value; committed (the user explicitly wants default)
  Unset // reset to the default; NOT committed — later ladder seats (env/config/inherit) may override
  Empty // clear a collection (array / map) to empty; committed
  // DR-077 §1 (5th op): apply an old-dependent transform to the linked cell — `cell = f(old)`. No
  // operand (the Binding's value is a placeholder, same as default/unset/empty) — the RESULT
  // depends on the cell's running value at fire time, which resolve.mbt's CLI-seat fold computes,
  // not something the parser can precompute at consume time. `String` is the transform's filters-
  // registry name (DR-077 §2, e.g. "increment"); `Array[String]` are that transform's own args (the
  // registry name is arity-1 of the colon DSL, remaining segments are its args — same nesting
  // convention filters already use). committed = true (a user-explicit CLI op, like set).
  Update(String, Array[String])
  // DR-080 §2 (merge accumulator piece marker vocabulary): a `remove`/`splice` PIECE within one
  // CLI firing's separator-split value list, distinct in kind from the 5 CELL-level ops above (a
  // merge-accumulator cell's own effect is still `Set` — these two only ever appear on the
  // per-piece Bindings `resolve_entity_raw`'s accum fold groups by `at_pos`, DR-080 波及節 "1
  // 発火 = 同一 argv 位置の piece 列"). `Remove`'s operand (the Binding's `value`) is type-parsed
  // like any add piece (DR-080 §2 "operand は要素 type で parse される"); `Splice` (`@`) carries
  // no operand (the Binding's value is a placeholder, same convention as default/unset/empty).
  // committed = true for both (mirrors `Update`) — `resolve_entity_raw`'s accum branch (which
  // interprets the piece sequence) owns whether the OVERALL fire commits, not this per-piece tag
  // (the DR-045 `committed` helper below never sees these — they never reach the scalar branch,
  // only the accum one, which computes committed_now from its own marker-presence check).
  Remove
  Splice
} derive(Eq, Debug)

///|
/// committed is DERIVED from the op, never a separate field (DR-045 §2: selected and
/// committed are independent, and the effect explicitly controls committed). Only `unset`
/// is un-committed, which is exactly what opens the later value-source ladder seats.
pub fn committed(op : EffectOp) -> Bool {
  match op {
    Unset => false
    _ => true
  }
}

///|
/// One EFFECT written onto a result path: `key`'s cell gets operation `op` with operand
/// `value`, from `source` (DR-045). `key` is the leaf name; same-key bindings from
/// different entries (e.g. `--port` satellite and `-p` matcher) merge onto one cell =
/// link 合流. `scope` is the result nesting path (DR-025): a binding produced inside a
/// command / name scope carries that scope's labels, outermost first.
///
/// Path-counting (DR-038) treats the whole binding as identity, so op/operand are part of
/// the effect-sequence key (DR-045 §1 精密化): the same cell reset by `unset` vs written by
/// `set` are DIFFERENT effects even at the same position. A value in `serve` differs from
/// the same leaf at root (scope is in the key too).
pub(all) struct Binding {
  key : String
  op : EffectOp // the operation on the cell (DR-045); Set for a plain value bind
  value : Value // the operand (a placeholder for default/unset/empty, which carry none)
  source : Source
  scope : Array[String]
  link : Int // a link/global-copy binding (DR-042/007): the number of result-nesting levels it
  //           still ESCAPES before settling at its declaring scope. 0 = a normal binding (every
  //           CmdSat/Scoped level prepends its label). N>0 = a global copied N scopes BELOW its
  //           declaration; the next N nest levels skip prepending (decrementing), then it nests
  //           normally — so an intermediate-scope global (DR-042 shadow) lands at its declaring
  //           scope, not the absolute root. A root global (declared at depth 0) has N = its firing
  //           depth, which escapes all the way to the root (the original bool-`link` behaviour).
  // DR-034/DR-062 piece_filters + issue 2026-07-09-accum-entity-filters-wiring: the argv token
  // position this binding's VALUE was read from, when it has one. `Some(pos)` for a CLI-seat
  // binding built at token-consumption time (eval.mbt/matcher.mbt's `mkb` call sites — a separator
  // piece carries the position of the WHOLE token it split from, not a per-piece offset, since a
  // piece is not itself a token). `None` for every non-token-consumption source (env/config/
  // inherit/default seats, resolve.mbt) — those values were never read off an argv token, so there
  // is no position to attribute a later value_filters(each) reject to (`apply_entity_filters`'s
  // `filter_err` falls back to the ladder's own `at_pos`, unchanged behavior, when this is `None`).
  at_pos : Int?
} derive(Eq, Debug)

// ── Binding/ParseError helpers the matcher builds (Branch itself lives in node.mbt) ──

///|
/// A plain value bind = the SET degenerate form of an effect (DR-045 §1). `at_pos` (issue
/// 2026-07-09-accum-entity-filters-wiring): the CLI-seat call sites (eval.mbt/matcher.mbt) pass
/// `Some(pos)` — the token this binding's value was read from; every other caller (resolve.mbt's
/// env/config/inherit/default seats) omits it, defaulting to `None`.
fn mkb(
  key : String,
  value : Value,
  source : Source,
  at_pos? : Int? = None,
) -> Binding {
  { key, op: Set, value, source, scope: [], link: 0, at_pos }
}

///|
/// Concatenate two binding arrays (accumulate readings along a path).
fn cat(a : Array[Binding], b : Array[Binding]) -> Array[Binding] {
  let r : Array[Binding] = []
  for x in a {
    r.push(x)
  }
  for x in b {
    r.push(x)
  }
  r
}

///|
/// A `kind: parse` held Error for a value that failed to parse as a number (DR-053 §2). The reason is
/// `not_a_number` (DR-066 §3): a token that does not read as a number at all — an int element also
/// lands here for a non-number token (int judges via the number 字句), while `not_an_integer` is the
/// separate reason for a readable-but-fractional value under int_round=error.
fn pe_parse(element : String, tok : String, pos : Int) -> ParseError {
  {
    element,
    argv_pos: pos,
    kind: KParse,
    reason: "not_a_number",
    message: "\"\{tok}\" is not a number",
    path: [], // DR-066 §4: prepended by scope boundaries on the way out (nest_branches / CmdSat)
  }
}

///|
/// A `kind: parse` held Error for a value that read as a number but is not an integer value under
/// canonical `int_round: error` (DR-075 §2 / DR-066 §3). The reason `not_an_integer` is emitted ONLY
/// when `int_round=error` (any rounding mode rounds to Ok and never raises this); a token that does
/// not read as a number at all lands in `pe_parse` with reason `not_a_number`.
fn pe_parse_int(element : String, tok : String, pos : Int) -> ParseError {
  {
    element,
    argv_pos: pos,
    kind: KParse,
    reason: "not_an_integer",
    message: "\"\{tok}\" is not an integer",
    path: [],
  }
}

///|
/// A `kind: parse` held Error for a readable integer VALUE whose magnitude exceeds Int64's range
/// (issue 2026-07-07-parse-int-value-huge-exponent-overflow). The provisional reason
/// `int_out_of_range` follows the `pe_parse_bool`/`not_a_bool` precedent (DR-066 v1 has no reason
/// for this yet).
fn pe_int_out_of_range(element : String, tok : String, pos : Int) -> ParseError {
  {
    element,
    argv_pos: pos,
    kind: KParse,
    reason: "int_out_of_range",
    message: "\"\{tok}\" is out of Int64 range",
    path: [],
  }
}

///|
/// A `kind: parse` held Error for a value that failed to parse as a bool (DR-074 §3 canonical vocab:
/// unrecognized tokens like `yes`/`on` are canonical-外, Error not silent 変換). DR-066 v1's reason
/// vocab only lists `not_a_number`/`not_an_integer` (bool has no entry yet); this reason is the
/// provisional `not_a_bool` used by resolve.mbt's config-path bool Error (§952 of resolve.mbt),
/// kept until DR-066 v1 vocab is amended (docs/issue/2026-07-07-bool-invalid-reason-vocab-gap.md).
fn pe_parse_bool(element : String, tok : String, pos : Int) -> ParseError {
  {
    element,
    argv_pos: pos,
    kind: KParse,
    reason: "not_a_bool",
    message: "\"\{tok}\" is not a bool",
    path: [],
  }
}

///|
/// A `kind: parse` held Error for a `kv_map` accumulator piece with no `=` (DR-091 §2, team-lead
/// 裁定 2026-07-11: "= なし piece は reject、型 parse 失敗と同じ扱い" — same `KParse` kind /
/// error-vocab family as `pe_parse`/`pe_parse_bool`, this is kv_map's own structural-shape check).
fn pe_parse_kv(element : String, tok : String, pos : Int) -> ParseError {
  {
    element,
    argv_pos: pos,
    kind: KParse,
    reason: "not_a_kv_pair",
    message: "\"\{tok}\" does not contain '=' (expected key=value)",
    path: [],
  }
}

///|
/// A `kind: filter` held Error for a piece_filters chain that rejected a raw token/piece before it
/// ever reached its type parser (DR-034/DR-062, DR-037's Reject/Error distinction — see
/// `apply_piece_filters`'s doc comment for why a filter chain's `Err` always becomes a `Held`, never
/// a silent `[]`: the Or/path-search machinery already discards a `Held` branch whenever a sibling
/// branch `Accept`s, so a single `Held(kind: KFilter, ...)` return realizes BOTH DR-037 outcomes —
/// no separate silent-Reject channel is needed). Token-consumption callers (eval.mbt's value-
/// primitive arms, matcher.mbt's `run_eq_split`) pass `reason`/`message` straight from
/// `apply_piece_filters`'s `Err` tuple. Mirrors `resolve.mbt`'s `filter_err` (the ladder-layer
/// counterpart, used by `env_value`) — kept as a separate builder here because eval.mbt/value.mbt
/// sit below resolve.mbt in the dependency graph (MDR-002 §3) and cannot call it.
fn pe_filter(
  element : String,
  pos : Int,
  reason : String,
  message : String,
) -> ParseError {
  { element, argv_pos: pos, kind: KFilter, reason, message, path: [] }
}

///|
/// A deprecation marker binding (DR-058): key `@depr:<element>`, recording that a deprecated entry
/// (DR-057 alias) was used to reach the canonical cell. Rides in the effect column like any binding;
/// the result builder skips it (bookkeeping, not a value), and `warnings_of` collects it.
fn depr_marker(element : String) -> Binding {
  {
    key: "@depr:" + element,
    op: Set,
    value: VBool(false),
    source: Cli,
    scope: [],
    link: 0,
    at_pos: None,
  }
}
