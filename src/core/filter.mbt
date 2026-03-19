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

///|
/// Validate minimum codepoint count (Unicode codepoints, handles surrogate pairs correctly)
pub fn Filter::min_codepoints(n : Int) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    let cp = s.char_length()
    if cp < n {
      raise parse_error(
        "value too short (got " +
        cp.to_string() +
        ", minimum " +
        n.to_string() +
        " codepoints)",
      )
    }
  })
}

///|
/// Validate maximum codepoint count (Unicode codepoints, handles surrogate pairs correctly)
pub fn Filter::max_codepoints(n : Int) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    let cp = s.char_length()
    if cp > n {
      raise parse_error(
        "value too long (got " +
        cp.to_string() +
        ", maximum " +
        n.to_string() +
        " codepoints)",
      )
    }
  })
}

///|
/// Validate minimum grapheme cluster count (visual characters, handles ZWJ/flags/skin tones)
pub fn Filter::min_graphemes(n : Int) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    let gc = @unicodegrapheme.graphemes(s).length()
    if gc < n {
      raise parse_error(
        "value too short (got " +
        gc.to_string() +
        ", minimum " +
        n.to_string() +
        " graphemes)",
      )
    }
  })
}

///|
/// Validate maximum grapheme cluster count (visual characters, handles ZWJ/flags/skin tones)
pub fn Filter::max_graphemes(n : Int) -> FilterChain[String, String] {
  Filter::validate(fn(s) raise ParseError {
    let gc = @unicodegrapheme.graphemes(s).length()
    if gc > n {
      raise parse_error(
        "value too long (got " +
        gc.to_string() +
        ", maximum " +
        n.to_string() +
        " graphemes)",
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
/// Parse string to Bool (true/t/on/1, false/f/off/0, case insensitive)
pub fn Filter::parse_bool() -> FilterChain[String, Bool] {
  Filter::parse(fn(s) raise ParseError {
    let lower = s.to_lower()
    if lower == "true" || lower == "t" || lower == "on" || lower == "1" {
      true
    } else if lower == "false" || lower == "f" || lower == "off" || lower == "0" {
      false
    } else {
      raise parse_error(
        "invalid boolean: " + s + " (expected true/false/t/f/on/off/1/0)",
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
  Filter::map(fn(v) { if v < min { min } else if v > max { max } else { v } })
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
  Filter::map(fn(s) {
    regex.replace_by(s[:], fn(_m) { replacement[:] }).to_string()
  })
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

// --- Mergeable list (DR-023) ---

///|
/// Parse a +/-/... prefixed list string into Array[String] by merging with base.
///
/// - Plain list (no +/- or ... in any element): full overwrite (base is ignored)
/// - `+item`: append to base (deduplicated)
/// - `-item`: remove from base
/// - `...`: expand remaining base items not yet listed
///
/// Elements are split by `separator` (default: ",").
pub fn Filter::mergeable_list(
  base? : Array[String] = [],
  separator? : String = ",",
) -> FilterChain[String, Array[String]] {
  Filter::map(fn(input) {
    let parts : Array[String] = input
      .split(separator.to_string_view())
      .map(fn(sv) { sv.to_string() })
      .collect()
    // Detect mode: if any element starts with +/- or is "...", it's merge mode
    let is_merge = parts
      .iter()
      .any(fn(p) { p.has_prefix("+") || p.has_prefix("-") || p == "..." })
    if not(is_merge) {
      // Full overwrite: return split parts as-is
      return parts
    }
    // Check if "..." is present
    let has_rest = parts.iter().any(fn(p) { p == "..." })
    if has_rest {
      // "..." mode: two-pass processing
      // First pass: collect all explicitly mentioned names and removals
      let mentioned : Array[String] = []
      let removals : Array[String] = []
      for part in parts {
        if part == "..." {
          continue
        } else if part.has_prefix("+") {
          mentioned.push(part[1:].to_string())
        } else if part.has_prefix("-") {
          let name = part[1:].to_string()
          mentioned.push(name)
          removals.push(name)
        } else {
          mentioned.push(part)
        }
      }
      // Second pass: build result in order
      let result : Array[String] = []
      for part in parts {
        if part == "..." {
          // Expand base items not explicitly mentioned
          for b in base {
            if not(mentioned.contains(b)) && not(result.contains(b)) {
              result.push(b)
            }
          }
        } else if part.has_prefix("+") {
          let name = part[1:].to_string()
          if not(removals.contains(name)) && not(result.contains(name)) {
            result.push(name)
          }
        } else if part.has_prefix("-") {
          // Removal: handled by final removals filter below
          ()
        } else if not(removals.contains(part)) && not(result.contains(part)) {
          result.push(part)
        }
      }
      // Apply removals to the final result
      result.filter(fn(item) { not(removals.contains(item)) })
    } else {
      // No "...", pure +/- mode: start from base, apply operations left-to-right
      let result : Array[String] = base.copy()
      for part in parts {
        if part.has_prefix("+") {
          let name = part[1:].to_string()
          if not(result.contains(name)) {
            result.push(name)
          }
        } else if part.has_prefix("-") {
          let name = part[1:].to_string()
          let filtered = result.filter(fn(item) { item != name })
          result.clear()
          for item in filtered {
            result.push(item)
          }
        }
      }
      result
    }
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
