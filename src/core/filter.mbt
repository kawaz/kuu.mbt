///|
/// Kleisli composition: chain A->B and B->C into A->C
pub fn[A, B, C] FilterChain::then(
  self : FilterChain[A, B],
  next : FilterChain[B, C],
) -> FilterChain[A, C] {
  { run: fn(a) raise ParseError { (next.run)((self.run)(a)) } }
}

// --- 3 constructors ---

///|
/// Pure transformation (never fails)
pub fn[A, B] Filter::map(f : (A) -> B) -> FilterChain[A, B] {
  { run: fn(a) { f(a) } }
}

///|
/// Validation (type-preserving, raises ParseError on failure)
pub fn[A] Filter::validate(
  f : (A) -> Unit raise ParseError,
) -> FilterChain[A, A] {
  {
    run: fn(a) raise ParseError {
      f(a)
      a
    },
  }
}

///|
/// Parse transformation (conversion that can fail)
pub fn[A, B] Filter::parse(f : (A) -> B raise ParseError) -> FilterChain[A, B] {
  { run: f }
}

// --- Built-in parts ---

///|
/// Trim whitespace from both ends
pub fn Filter::trim() -> FilterChain[String, String] {
  Filter::map(fn(s) { s.trim().to_string() })
}

///|
/// Convert to lowercase
pub fn Filter::to_lower() -> FilterChain[String, String] {
  Filter::map(fn(s) { s.to_lower() })
}

///|
/// Reject empty strings
pub fn Filter::non_empty() -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    if s.is_empty() {
      raise parse_error("value must not be empty")
    }
  })
}

///|
/// Split string by separator into Array[String]
pub fn Filter::split(sep : String) -> FilterChain[String, Array[String]] {
  Filter::map(fn(s) {
    s.split(sep.to_string_view()).map(fn(sv) { sv.to_string() }).collect()
  })
}

///|
/// Parse string to Int
pub fn Filter::parse_int() -> FilterChain[String, Int] {
  Filter::parse(fn(s) raise ParseError {
    let r : Result[Int, _] = try? @strconv.parse_int(s.view())
    match r {
      Ok(v) => v
      Err(_) => raise parse_error("invalid integer: " + s)
    }
  })
}

///|
/// Parse string to Double
pub fn Filter::parse_float() -> FilterChain[String, Double] {
  Filter::parse(fn(s) raise ParseError {
    let r : Result[Double, _] = try? @strconv.parse_double(s.view())
    match r {
      Ok(v) => v
      Err(_) => raise parse_error("invalid float: " + s)
    }
  })
}

///|
/// Validate that Int is within [min, max] inclusive
pub fn Filter::in_range(min : Int, max : Int) -> FilterChain[Int, Int] {
  Filter::validate(fn(v) raise ParseError {
    if v < min || v > max {
      raise parse_error(
        "value " +
        v.to_string() +
        " out of range [" +
        min.to_string() +
        ", " +
        max.to_string() +
        "]",
      )
    }
  })
}

///|
/// Validate that String is one of the allowed values
pub fn Filter::one_of(allowed : Array[String]) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    if allowed.contains(s) {
      return
    }
    raise parse_error("value must be one of: " + allowed.join(", "))
  })
}

///|
/// Apply a filter to each element of an array
pub fn[A, B] Filter::each(
  inner : FilterChain[A, B],
) -> FilterChain[Array[A], Array[B]] {
  Filter::parse(fn(arr) raise ParseError {
    arr.map(fn(item) raise ParseError { (inner.run)(item) })
  })
}

// --- String validation ---

///|
/// Convert to uppercase
pub fn Filter::to_upper() -> FilterChain[String, String] {
  Filter::map(fn(s) { s.to_upper() })
}

///|
/// Validate that string starts with prefix
pub fn Filter::starts_with(prefix : String) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    if not(s.has_prefix(prefix)) {
      raise parse_error("value must start with: " + prefix)
    }
  })
}

///|
/// Validate that string ends with suffix
pub fn Filter::ends_with(suffix : String) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    if not(s.has_suffix(suffix)) {
      raise parse_error("value must end with: " + suffix)
    }
  })
}

///|
/// Validate that string contains substring
pub fn Filter::contains(substr : String) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    if not(s.contains(substr)) {
      raise parse_error("value must contain: " + substr)
    }
  })
}

///|
/// Validate minimum string length (UTF-16 code units, not grapheme clusters)
pub fn Filter::min_length(n : Int) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    if s.length() < n {
      raise parse_error(
        "value too short (got " +
        s.length().to_string() +
        ", minimum " +
        n.to_string() +
        " characters)",
      )
    }
  })
}

///|
/// Validate maximum string length (UTF-16 code units, not grapheme clusters)
pub fn Filter::max_length(n : Int) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    if s.length() > n {
      raise parse_error(
        "value too long (got " +
        s.length().to_string() +
        ", maximum " +
        n.to_string() +
        " characters)",
      )
    }
  })
}

// --- String transformation ---

///|
/// Trim leading whitespace
pub fn Filter::trim_start() -> FilterChain[String, String] {
  Filter::map(fn(s) { s.trim_start().to_string() })
}

///|
/// Trim trailing whitespace
pub fn Filter::trim_end() -> FilterChain[String, String] {
  Filter::map(fn(s) { s.trim_end().to_string() })
}

///|
/// Replace first occurrence of old with new
pub fn Filter::replace(
  old : String,
  new : String,
) -> FilterChain[String, String] {
  Filter::map(fn(s) { s.replace(old~, new~) })
}

///|
/// Replace all occurrences of old with new
pub fn Filter::replace_all(
  old : String,
  new : String,
) -> FilterChain[String, String] {
  Filter::map(fn(s) { s.replace_all(old~, new~) })
}

// --- Type parsing ---

///|
/// Parse string to Bool (true/false/1/0, case insensitive)
pub fn Filter::parse_bool() -> FilterChain[String, Bool] {
  Filter::parse(fn(s) raise ParseError {
    let lower = s.to_lower()
    if lower == "true" || lower == "1" {
      true
    } else if lower == "false" || lower == "0" {
      false
    } else {
      raise parse_error(
        "invalid boolean: " + s + " (expected true/false/1/0)",
      )
    }
  })
}

// --- Numeric validation ---

///|
/// Validate that Double is within [min, max] inclusive.
/// NaN is rejected (IEEE 754 NaN comparisons are all false).
pub fn Filter::float_in_range(
  min : Double,
  max : Double,
) -> FilterChain[Double, Double] {
  Filter::validate(fn(v) raise ParseError {
    // NaN guard: NaN comparisons are always false in IEEE 754
    if v.is_nan() || v < min || v > max {
      raise parse_error(
        "value " +
        v.to_string() +
        " out of range [" +
        min.to_string() +
        ", " +
        max.to_string() +
        "]",
      )
    }
  })
}

///|
/// Validate that Int is positive (> 0)
pub fn Filter::positive() -> FilterChain[Int, Int] {
  Filter::validate(fn(v) raise ParseError {
    if v <= 0 {
      raise parse_error("value must be positive, got " + v.to_string())
    }
  })
}

///|
/// Validate that Int is non-negative (>= 0)
pub fn Filter::non_negative() -> FilterChain[Int, Int] {
  Filter::validate(fn(v) raise ParseError {
    if v < 0 {
      raise parse_error("value must be non-negative, got " + v.to_string())
    }
  })
}

///|
/// Clamp Int to [min, max] range (transformation, not validation).
/// Requires min <= max; behavior is undefined otherwise.
pub fn Filter::clamp(min : Int, max : Int) -> FilterChain[Int, Int] {
  Filter::map(fn(v) {
    if v < min {
      min
    } else if v > max {
      max
    } else {
      v
    }
  })
}

// --- Regex filters ---

///|
/// Validate that string matches regex pattern (partial match; use `^...$` for full-string).
/// Panics if pattern is invalid (programming error, not user error).
pub fn Filter::regex_match(pattern : String) -> FilterChain[String, String] {
  let regex = @string.Regex::unsafe_from_string(pattern)
  Filter::validate(fn(s) raise ParseError {
    if regex.execute(s[:]) is None {
      raise parse_error("value does not match pattern: " + pattern)
    }
  })
}

///|
/// Replace all regex matches with a literal replacement string (no capture group refs).
/// Panics if pattern is invalid (programming error, not user error).
pub fn Filter::regex_replace(
  pattern : String,
  replacement : String,
) -> FilterChain[String, String] {
  let regex = @string.Regex::unsafe_from_string(pattern)
  Filter::map(fn(s) { regex.replace_by(s[:], fn(_m) { replacement[:] }).to_string() })
}

///|
/// Split string by regex pattern.
/// Panics if pattern is invalid (programming error, not user error).
pub fn Filter::regex_split(
  pattern : String,
) -> FilterChain[String, Array[String]] {
  let regex = @string.Regex::unsafe_from_string(pattern)
  Filter::map(fn(s) {
    regex.split(s[:]).map(fn(sv) { sv.to_string() }).collect()
  })
}

///|
/// FilterChain + Accumulator → reducer 関数を自動生成
pub fn[T, U] make_reducer(
  pre : FilterChain[String, U],
  accum : Accumulator[T, U],
) -> (ReduceCtx[T]) -> T? raise ParseError {
  fn(ctx : ReduceCtx[T]) -> T? raise ParseError {
    match ctx.action {
      Value(Some(s)) => {
        let piece = (pre.run)(s)
        let f : (T, U) -> T = (accum : (T, U) -> T)
        Some(f(ctx.current, piece))
      }
      _ => None
    }
  }
}
