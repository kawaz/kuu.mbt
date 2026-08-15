// fixture_residents.mbt — DR-132 `fixture/*` conformance residents (virtual pin types).
//
// The `fixture/*` namespace is conformance-only (DR-128 §12 / DR-132 §1): the normative
// obligation is resolvability in the conformance execution context, so these residents are
// registered by the conformance runners (`install_conformance_fixture_residents`) and stay
// out of `install_canonical`. They are pin vehicles, not practical types — their acceptance
// contours may change with fixture needs without the builtin stability promise.

///|
/// DR-132 §2 `fixture/int_range`: record-producing pin resident. `out` is
/// {start: int, end: int} (field types are registry references to canonical `int`,
/// DR-126 §1). The string form splits the token once at the FIRST `..` (no backtracking,
/// DR-132 §2.1) and accepts exactly `A..B` / `A..` / `..B`; partial forms produce partial
/// presence (`5..` → {"start": 5}, DR-127 §3.1). Every spelling that does not read as a
/// range — no `..`, bare `..`, or a constituent outside the canonical int contour — folds
/// into the single reason `not_an_int_range` as a Reject (ValueSpaceMiss), mirroring
/// `builtin/number_parser`'s not_a_number practice (DR-132 §2.2).
priv struct FixtureIntRangeType {}

///|
impl @extension.TypeExt for FixtureIntRangeType with fn name(_self) {
  "fixture/int_range"
}

///|
impl @extension.TypeExt for FixtureIntRangeType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for FixtureIntRangeType with fn output_type(_self) {
  Some(@abi.ValueType::Record([("start", "int"), ("end", "int")]))
}

///|
impl @extension.TypeExt for FixtureIntRangeType with fn parse_token(
  _self,
  token,
) {
  fn reject() -> Result[@abi.Value, @abi.TypeParseFail] {
    Err({
      disposition: @abi.ValueSpaceMiss,
      reason: "not_an_int_range",
      message: "value \"\{token}\" is not an int range (A..B / A.. / ..B)",
    })
  }

  let chars = token.to_array()
  let mut split = -1
  for index in 0..<chars.length() {
    if index + 1 < chars.length() &&
      chars[index] == '.' &&
      chars[index + 1] == '.' {
      split = index
      break
    }
  }
  if split < 0 {
    return reject()
  }
  let head = token[0:split].to_owned()
  let tail = token[split + 2:].to_owned()
  if head.length() == 0 && tail.length() == 0 {
    return reject()
  }
  let fields : Array[(String, @abi.Value)] = []
  if head.length() > 0 {
    match @extension.int_type().parse_token(head) {
      Ok(value) => fields.push(("start", value))
      Err(_) => return reject()
    }
  }
  if tail.length() > 0 {
    match @extension.int_type().parse_token(tail) {
      Ok(value) => fields.push(("end", value))
      Err(_) => return reject()
    }
  }
  Ok(@abi.Object(fields))
}

///|
impl @extension.TypeExt for FixtureIntRangeType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
pub fn fixture_int_range_type() -> &@extension.TypeExt {
  FixtureIntRangeType::{  } as &@extension.TypeExt
}

///|
/// DR-132 §3 `fixture/json`: `value`-producing pin resident carrying the runtime-resolution
/// family (DR-127 §2.2 map/value rows). Reads one token as an RFC 8259 JSON text and returns
/// the value verbatim; a spelling that is not JSON is a `not_json` Reject (ValueSpaceMiss).
priv struct FixtureJsonType {}

///|
impl @extension.TypeExt for FixtureJsonType with fn name(_self) {
  "fixture/json"
}

///|
impl @extension.TypeExt for FixtureJsonType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for FixtureJsonType with fn output_type(_self) {
  Some(@abi.ValueType::Value)
}

///|
fn value_from_json(json : Json) -> @abi.Value {
  match json {
    Object(object) => {
      let entries : Array[(String, @abi.Value)] = []
      for key, value in object {
        entries.push((key, value_from_json(value)))
      }
      @abi.Object(entries)
    }
    Array(items) => {
      let values : Array[@abi.Value] = []
      for value in items {
        values.push(value_from_json(value))
      }
      @abi.Array(values)
    }
    True => @abi.Bool(true)
    False => @abi.Bool(false)
    String(value) => @abi.String(value)
    Number(value, ..) => @abi.Number(value)
    _ => @abi.Null
  }
}

///|
impl @extension.TypeExt for FixtureJsonType with fn parse_token(_self, token) {
  let json = @json.parse(token) catch {
    _ =>
      return Err({
        disposition: @abi.ValueSpaceMiss,
        reason: "not_json",
        message: "value \"\{token}\" is not JSON",
      })
  }
  Ok(value_from_json(json))
}

///|
impl @extension.TypeExt for FixtureJsonType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
pub fn fixture_json_type() -> &@extension.TypeExt {
  FixtureJsonType::{  } as &@extension.TypeExt
}

///|
priv struct FixtureColorType {}

///|
impl @extension.TypeExt for FixtureColorType with fn name(_self) {
  "fixture/color"
}

///|
impl @extension.TypeExt for FixtureColorType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for FixtureColorType with fn output_type(_self) {
  Some(
    @abi.ValueType::Union([
      @abi.ValueType::Tuple(["int", "int", "int"]),
      @abi.ValueType::String,
    ]),
  )
}

///|
impl @extension.TypeExt for FixtureColorType with fn parse_token(_self, token) {
  Ok(@abi.String(token))
}

///|
impl @extension.TypeExt for FixtureColorType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
pub fn fixture_color_type() -> &@extension.TypeExt {
  FixtureColorType::{  } as &@extension.TypeExt
}

///|
priv struct FixtureShapeType {}

///|
impl @extension.TypeExt for FixtureShapeType with fn name(_self) {
  "fixture/shape"
}

///|
impl @extension.TypeExt for FixtureShapeType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for FixtureShapeType with fn output_type(_self) {
  Some(
    @abi.ValueType::Union([
      @abi.ValueType::Record([("a", "int")]),
      @abi.ValueType::Record([("a", "int"), ("b", "int")]),
    ]),
  )
}

///|
impl @extension.TypeExt for FixtureShapeType with fn parse_token(_self, token) {
  Err({
    disposition: @abi.ValueSpaceMiss,
    reason: "not_a_shape",
    message: "value \"\{token}\" is not a shape",
  })
}

///|
impl @extension.TypeExt for FixtureShapeType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
pub fn fixture_shape_type() -> &@extension.TypeExt {
  FixtureShapeType::{  } as &@extension.TypeExt
}

///|
priv struct FixturePairType {}

///|
impl @extension.TypeExt for FixturePairType with fn name(_self) {
  "fixture/pair"
}

///|
impl @extension.TypeExt for FixturePairType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for FixturePairType with fn output_type(_self) {
  Some(@abi.ValueType::Tuple(["int", "int"]))
}

///|
impl @extension.TypeExt for FixturePairType with fn parse_token(_self, token) {
  Err({
    disposition: @abi.ValueSpaceMiss,
    reason: "not_a_pair",
    message: "value \"\{token}\" is not a pair",
  })
}

///|
impl @extension.TypeExt for FixturePairType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
pub fn fixture_pair_type() -> &@extension.TypeExt {
  FixturePairType::{  } as &@extension.TypeExt
}

///|
/// Registers the `fixture/*` residents into a registry for a conformance run (DR-132 §1:
/// the runner contract requires `fixture/*` to resolve in the conformance execution
/// context only). Call after `install_canonical` when assembling a conformance registry.
pub fn install_conformance_fixture_residents(registry : @node.Registry) -> Unit {
  guard registry.register_type(fixture_int_range_type()) else {
    abort("duplicate fixture type resident name: fixture/int_range")
  }
  guard registry.register_type(fixture_json_type()) else {
    abort("duplicate fixture type resident name: fixture/json")
  }
  guard registry.register_type(fixture_color_type()) else {
    abort("duplicate fixture type resident name: fixture/color")
  }
  guard registry.register_type(fixture_shape_type()) else {
    abort("duplicate fixture type resident name: fixture/shape")
  }
  guard registry.register_type(fixture_pair_type()) else {
    abort("duplicate fixture type resident name: fixture/pair")
  }
}
