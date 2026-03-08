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
    for v in allowed {
      if v == s {
        return
      }
    }
    raise parse_error("value must be one of: " + allowed.to_string())
  })
}

///|
/// Apply a filter to each element of an array
pub fn[A, B] Filter::each(
  inner : FilterChain[A, B],
) -> FilterChain[Array[A], Array[B]] {
  Filter::parse(fn(arr) raise ParseError {
    let result : Array[B] = []
    for item in arr {
      result.push((inner.run)(item))
    }
    result
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
