///|
/// Parse a post filter for String from JSON.
fn parse_string_post(
  obj : Map[String, Json],
) -> @core.FilterChain[String, String]? {
  match obj.get("post") {
    Some(String("trim")) => Some(@core.Filter::trim())
    Some(String("non_empty")) => Some(@core.Filter::non_empty())
    _ => None
  }
}

///|
/// Parse a string filter from JSON spec.
/// Supports: "trim", "non_empty", "to_lower", "to_upper"
fn parse_string_filter(filter : Json) -> @core.FilterChain[String, String]? {
  match filter {
    String("trim") => Some(@core.Filter::trim())
    String("non_empty") => Some(@core.Filter::non_empty())
    String("to_lower") => Some(@core.Filter::to_lower())
    String("to_upper") => Some(@core.Filter::to_upper())
    _ => None
  }
}

///|
/// Parse an int filter from JSON spec.
/// Supports: { "in_range": [min, max] }, { "clamp": [min, max] }
fn parse_int_filter(filter : Json) -> @core.FilterChain[Int, Int]? {
  match filter {
    Object(obj) => {
      match obj.get("in_range") {
        Some(Array(arr)) =>
          if arr.length() == 2 {
            let min = match arr[0] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            let max = match arr[1] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            return Some(@core.Filter::in_range(min, max))
          }
        _ => ()
      }
      match obj.get("clamp") {
        Some(Array(arr)) =>
          if arr.length() == 2 {
            let min = match arr[0] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            let max = match arr[1] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            return Some(@core.Filter::clamp(min, max))
          }
        _ => ()
      }
      None
    }
    _ => None
  }
}

///|
/// Parse a float filter from JSON spec.
/// Supports: { "float_in_range": [min, max] }
fn parse_float_filter(filter : Json) -> @core.FilterChain[Double, Double]? {
  match filter {
    Object(obj) =>
      match obj.get("float_in_range") {
        Some(Array(arr)) =>
          if arr.length() == 2 {
            let min = match arr[0] {
              Number(n, ..) => n
              _ => return None
            }
            let max = match arr[1] {
              Number(n, ..) => n
              _ => return None
            }
            Some(@core.Filter::float_in_range(min, max))
          } else {
            None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// Parse a post filter for Int from JSON.
fn parse_int_post(obj : Map[String, Json]) -> @core.FilterChain[Int, Int]? {
  match obj.get("post") {
    Some(filter) => parse_int_filter(filter)
    _ => None
  }
}

///|
/// Parse a post filter for Double from JSON.
fn parse_float_post(
  obj : Map[String, Json],
) -> @core.FilterChain[Double, Double]? {
  match obj.get("post") {
    Some(filter) => parse_float_filter(filter)
    _ => None
  }
}
