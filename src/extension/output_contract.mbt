// output_contract.mbt — DR-126 §4: a resident's produced value versus its own `output_type`
// declaration.

///|
/// One way a produced value contradicted its resident's own declaration. The variants map onto
/// DR-126 §4's table: `Undeclared`/`Duplicate` are the (a) row (a key the record cannot name),
/// `FieldType` is the (b) row, and `Shape` is the same contradiction one level up — the value as a
/// whole is not what the resident said it produces. Row (c) (a declared key the value omits) is
/// normal and never reaches here: DR-130 §4.1 puts the null補形 in the projection layer, so the raw
/// output is allowed to be short.
priv enum ContractBreach {
  Shape(String, String)
  FieldType(String, String)
  Undeclared(String, String)
  Duplicate(String, String)
}

///|
/// How a value would be spelled in wire JSON, for diagnostics.
fn value_shape_name(value : @abi.Value) -> String {
  match value {
    @abi.Null => "null"
    @abi.String(_) => "string"
    @abi.Number(_) => "number"
    @abi.Bool(_) => "bool"
    @abi.Array(_) => "array"
    @abi.Object(_) => "object"
  }
}

///|
fn value_type_name(value_type : @abi.ValueType) -> String {
  match value_type {
    String => "string"
    Number => "number"
    Bool => "bool"
    Null => "null"
    Value => "value"
    Array(_) => "array"
    Map(_) => "map"
    Record(_) => "record"
    Union(_) => "union"
  }
}

///|
fn breach_fail(breach : ContractBreach, owner : String) -> @abi.TypeParseFail {
  let (reason, message) = match breach {
    Shape(path, detail) =>
      (
        "output_shape_mismatch",
        "type '" + owner + "' produced " + detail + " at " + path,
      )
    FieldType(path, detail) =>
      (
        "field_type_mismatch",
        "type '" + owner + "' produced " + detail + " at " + path,
      )
    Undeclared(path, field) =>
      (
        "undeclared_field",
        "type '" +
        owner +
        "' produced key '" +
        field +
        "' that its record declaration does not name, at " +
        path,
      )
    Duplicate(path, field) =>
      (
        "duplicate_field",
        "type '" +
        owner +
        "' produced key '" +
        field +
        "' more than once at " +
        path,
      )
  }
  // DR-126 §4: a Reject would let the divergence disappear into backtracking, leaving a parse
  // failure with no cause. RecognizedButInvalid keeps it in the errors array as a held Error.
  { disposition: @abi.RecognizedButInvalid, reason, message }
}

///|
/// Compare a produced value against one declared value type. Returns the first breach found.
///
/// A `Null` value satisfies every declaration: DR-130 §1 makes null the universal "no value here",
/// and §7 derives every declared seat as `T | null`, so a null is never a contradiction of the
/// declaration itself.
///
/// Termination: crossing a record/array/map arm consumes one level of the *value*, and a union arm
/// consumes one level of the *type*. A cyclic type-reference graph therefore cannot spin here — it
/// can only be followed as deep as the finite value goes. (Cycles are separately a definition-error
/// `circular-ref` at lowering, DR-126 §1.)
fn value_type_breach(
  value : @abi.Value,
  declared : @abi.ValueType,
  path : String,
  extensions : Registry,
) -> ContractBreach? {
  if value is @abi.Null {
    return None
  }
  let mismatch = Some(
    ContractBreach::Shape(
      path,
      value_shape_name(value) +
      " where " +
      value_type_name(declared) +
      " is declared",
    ),
  )
  match declared {
    Value => None
    Null => mismatch
    String => if value is @abi.String(_) { None } else { mismatch }
    Number => if value is @abi.Number(_) { None } else { mismatch }
    Bool => if value is @abi.Bool(_) { None } else { mismatch }
    Array(item_type) =>
      match value {
        @abi.Array(items) => {
          for index, item in items {
            match
              value_type_breach(
                item,
                item_type,
                path + "[" + index.to_string() + "]",
                extensions,
              ) {
              Some(breach) => return Some(breach)
              None => ()
            }
          }
          None
        }
        _ => mismatch
      }
    Map(item_type) =>
      match value {
        @abi.Object(entries) => {
          for entry in entries {
            match
              value_type_breach(
                entry.1,
                item_type,
                path + "." + entry.0,
                extensions,
              ) {
              Some(breach) => return Some(breach)
              None => ()
            }
          }
          None
        }
        _ => mismatch
      }
    Record(fields) =>
      match value {
        @abi.Object(entries) => record_breach(entries, fields, path, extensions)
        _ => mismatch
      }
    Union(members) => {
      for variant in members {
        if value_type_breach(value, variant, path, extensions) is None {
          return None
        }
      }
      mismatch
    }
  }
}

///|
/// A wire JSON object cannot carry the same key twice, so a duplicate key is a value the declaration
/// can never denote — the (a) row of DR-126 §4's table reached by a different route than an
/// undeclared name (統括裁定 2026-08-02).
fn duplicate_key_breach(
  entries : Array[(String, @abi.Value)],
  path : String,
) -> ContractBreach? {
  for index, entry in entries {
    for previous in 0..<index {
      if entries[previous].0 == entry.0 {
        return Some(Duplicate(path, entry.0))
      }
    }
  }
  None
}

///|
/// The duplicate-key invariant walks the raw produced value independently of
/// the declared-type match (統括裁定 W2-5 事後監査): a `value` declaration, an
/// `Array(Value)` item, or a record field whose referenced `out` is `value`
/// would otherwise short-circuit before the object was ever inspected, and a
/// duplicate key is undeliverable wire JSON under every declaration.
fn value_duplicate_breach(value : @abi.Value, path : String) -> ContractBreach? {
  match value {
    @abi.Object(entries) => {
      match duplicate_key_breach(entries, path) {
        Some(breach) => return Some(breach)
        None => ()
      }
      for entry in entries {
        match value_duplicate_breach(entry.1, path + "." + entry.0) {
          Some(breach) => return Some(breach)
          None => ()
        }
      }
      None
    }
    @abi.Array(items) => {
      for index, item in items {
        match
          value_duplicate_breach(item, path + "[" + index.to_string() + "]") {
          Some(breach) => return Some(breach)
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
/// DR-126 §2/§4: the record's key vocabulary is closed, so every produced key must be named by the
/// declaration, and each named key's value must satisfy the `out` of the type it references.
/// An unresolvable field reference is not judged here — that is a lowering-time definition-error
/// (`unknown-vocab`, DR-126 §1), and re-reporting it as a runtime divergence would attribute an
/// author's mistake to the parser.
fn record_breach(
  entries : Array[(String, @abi.Value)],
  fields : Array[(String, String)],
  path : String,
  extensions : Registry,
) -> ContractBreach? {
  for entry in entries {
    let mut reference : String? = None
    for field in fields {
      if field.0 == entry.0 {
        reference = Some(field.1)
        break
      }
    }
    match reference {
      None => return Some(Undeclared(path, entry.0))
      Some(spelling) =>
        match extensions.resolve_type_reference(spelling) {
          None => ()
          Some(resident) =>
            match resident.output_type() {
              None => ()
              Some(nested) =>
                match
                  value_type_breach(
                    entry.1,
                    nested,
                    path + "." + entry.0,
                    extensions,
                  ) {
                  Some(Shape(where_, detail)) =>
                    return Some(FieldType(where_, detail))
                  Some(breach) => return Some(breach)
                  None => ()
                }
            }
        }
    }
  }
  None
}

///|
/// DR-126 §4 divergence check over a resident's raw output. Residents that decline to declare an
/// output type (`output_type() == None`, the trait default) make no claim to contradict.
pub fn output_contract_breach(
  value : @abi.Value,
  ty : &TypeExt,
  extensions : Registry,
) -> @abi.TypeParseFail? {
  match value_duplicate_breach(value, "$") {
    Some(breach) => return Some(breach_fail(breach, ty.name()))
    None => ()
  }
  match ty.output_type() {
    None => None
    Some(declared) =>
      match value_type_breach(value, declared, "$", extensions) {
        None => None
        Some(breach) => Some(breach_fail(breach, ty.name()))
      }
  }
}

///|
/// Whether a value satisfies one declared value type (no diagnostic). The projection layer's
/// record null補形 (DR-130 §4.1) uses this to pick the union variant a value structurally
/// matches before enumerating that variant's declared fields.
pub fn value_conforms(
  value : @abi.Value,
  declared : @abi.ValueType,
  extensions : Registry,
) -> Bool {
  value_type_breach(value, declared, "$", extensions) is None
}

///|
/// DR-127 §3.2 — the value a cell fn returns into a value-space seat must satisfy the seat's
/// field-type `out`, the same conformance a set operand gets by parsing through the field type.
/// Reuses the DR-126 §4 breach vocabulary (reason strings) with the fn as the producer.
/// Returns `(reason, message)` for the caller's ParseError, or None when the value conforms.
pub fn seat_fn_output_breach(
  value : @abi.Value,
  declared : @abi.ValueType,
  fn_name : String,
  extensions : Registry,
) -> (String, String)? {
  match value_type_breach(value, declared, "$", extensions) {
    None => None
    Some(Shape(path, detail)) =>
      Some(
        (
          "output_shape_mismatch",
          "cell fn '" + fn_name + "' returned " + detail + " at " + path,
        ),
      )
    Some(FieldType(path, detail)) =>
      Some(
        (
          "field_type_mismatch",
          "cell fn '" + fn_name + "' returned " + detail + " at " + path,
        ),
      )
    Some(Undeclared(path, field)) =>
      Some(
        (
          "undeclared_field",
          "cell fn '" +
          fn_name +
          "' returned key '" +
          field +
          "' that the seat's record declaration does not name, at " +
          path,
        ),
      )
    Some(Duplicate(path, field)) =>
      Some(
        (
          "duplicate_field",
          "cell fn '" +
          fn_name +
          "' returned key '" +
          field +
          "' more than once at " +
          path,
        ),
      )
  }
}

///|
/// `parse_token` with DR-126 §4 applied. Every runtime seat that turns a token into a cell value
/// goes through here, so a resident whose output contradicts its own declaration surfaces as a held
/// Error at the seat that produced it instead of flowing on as a cell value.
///
/// The check reads the parser's raw output, before the projection layer fills missing record fields
/// with null (DR-130 §4.1) — that ordering is what keeps a parser's omission (normal) distinct from
/// a parser's invention (Error).
pub fn parse_token_checked(
  ty : &TypeExt,
  token : String,
  extensions : Registry,
) -> Result[@abi.Value, @abi.TypeParseFail] {
  match ty.parse_token(token) {
    Err(fail) => Err(fail)
    Ok(value) =>
      match output_contract_breach(value, ty, extensions) {
        None => Ok(value)
        Some(fail) => Err(fail)
      }
  }
}
