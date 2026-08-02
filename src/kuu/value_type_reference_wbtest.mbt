// value_type_reference_wbtest.mbt — W2-2 registry-only type dependency validation.

///|
priv struct DeclaredTestType {
  name_ : String
  output_ : @abi.ValueType?
}

///|
impl @extension.TypeExt for DeclaredTestType with fn name(self) {
  self.name_
}

///|
impl @extension.TypeExt for DeclaredTestType with fn has_value_slot(_self) {
  true
}

///|
impl @extension.TypeExt for DeclaredTestType with fn output_type(self) {
  self.output_
}

///|
impl @extension.TypeExt for DeclaredTestType with fn parse_token(_self, token) {
  Ok(@abi.String(token))
}

///|
impl @extension.TypeExt for DeclaredTestType with fn default_seat_resolver(
  _self,
  ctx,
) {
  ctx.declared()
}

///|
fn declared_type(name : String, output : @abi.ValueType?) -> DeclaredTestType {
  { name_: name, output_: output }
}

///|
fn registry_with_declared_types(
  residents : Array[&@extension.TypeExt],
) -> @node.Registry {
  let registry = canonical_registry()
  for resident in residents {
    guard registry.register_type(resident) else {
      abort("duplicate test resident: " + resident.name())
    }
  }
  registry
}

///|
fn parse_with_declared_types(
  source : String,
  residents : Array[&@extension.TypeExt],
) -> Result[AtomicAST, DefLoadError] {
  let definition = @json.parse(source) catch {
    _ => abort("invalid test definition JSON")
  }
  parse_definition(
    definition,
    extensions=registry_with_declared_types(residents),
  )
}

///|
fn rejected_type_errors(
  source : String,
  residents : Array[&@extension.TypeExt],
) -> Array[@abi.DefError] {
  match parse_with_declared_types(source, residents) {
    Err(Rejected(errors)) => errors
    Err(Malformed(message)) =>
      abort("expected definition errors, got malformed: " + message)
    Ok(_) => abort("expected definition errors")
  }
}

///|
fn count_kind(errors : Array[@abi.DefError], kind : @abi.DefErrorKind) -> Int {
  let mut count = 0
  for error in errors {
    if error.kind == kind {
      count += 1
    }
  }
  count
}

///|
test "record type references resolve recursively through registered output types" {
  // Case a: timerange's two fields both resolve through the registered timestamp resident.
  let timestamp = declared_type("timestamp", Some(@abi.ValueType::Number))
  let timerange = declared_type(
    "timerange",
    Some(
      @abi.ValueType::Record([("since", "timestamp"), ("until", "timestamp")]),
    ),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"tr\",\"type\":\"timerange\",\"long\":true}]}",
      [timestamp as &@extension.TypeExt, timerange as &@extension.TypeExt],
    )
    is Ok(_),
  )
}

///|
test "an unregistered record field reference reports its owner field and spelling once" {
  // Case b: both fields target the same missing spelling, so diagnostic dedup emits one actionable error.
  let timerange = declared_type(
    "timerange",
    Some(
      @abi.ValueType::Record([("since", "timestamp"), ("until", "timestamp")]),
    ),
  )
  let errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"tr\",\"type\":\"timerange\",\"long\":true}]}",
    [timerange as &@extension.TypeExt],
  )
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].kind, @abi.UnknownVocab)
  let message = errors[0].message
  assert_true(message.contains("timerange"))
  assert_true(message.contains("since"))
  assert_true(message.contains("timestamp"))
}

///|
test "self and mutual type dependency cycles are rejected with cycle paths" {
  // Case c1: a direct self edge is a cycle even though the record could be finite at runtime.
  let selfnode = declared_type(
    "selfnode",
    Some(@abi.ValueType::Record([("next", "selfnode")])),
  )
  let self_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"node\",\"type\":\"selfnode\",\"long\":true}]}",
    [selfnode as &@extension.TypeExt],
  )
  assert_eq(count_kind(self_errors, @abi.CircularRef), 1)
  assert_true(self_errors[0].message.contains("selfnode -> selfnode"))
  // Case c2: cycles are also detected after crossing a second resident.
  let type_a = declared_type(
    "cycle_a",
    Some(@abi.ValueType::Record([("f", "cycle_b")])),
  )
  let type_b = declared_type(
    "cycle_b",
    Some(@abi.ValueType::Record([("g", "cycle_a")])),
  )
  let mutual_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"value\",\"type\":\"cycle_a\",\"long\":true}]}",
    [type_a as &@extension.TypeExt, type_b as &@extension.TypeExt],
  )
  assert_eq(count_kind(mutual_errors, @abi.CircularRef), 1)
  assert_true(
    mutual_errors[0].message.contains("cycle_a -> cycle_b -> cycle_a"),
  )
}

///|
test "type references use builtin qualification sugar but never definition shadows" {
  // Case d1: builtin/number canonicalizes to the bare builtin registry identity.
  let qualified = declared_type(
    "qualified",
    Some(@abi.ValueType::Record([("value", "builtin/number")])),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"value\",\"type\":\"qualified\",\"long\":true}]}",
      [qualified as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // Case d2: definitions.types is a use-site shadow namespace and cannot satisfy record references.
  let shadow_ref = declared_type(
    "shadow_ref",
    Some(@abi.ValueType::Record([("value", "shadowed")])),
  )
  let errors = rejected_type_errors(
    "{\"definitions\":{\"types\":{\"shadowed\":{\"name\":\"int_parser\",\"config\":{}}}},\"options\":[{\"name\":\"value\",\"type\":\"shadow_ref\",\"long\":true}]}",
    [shadow_ref as &@extension.TypeExt],
  )
  assert_eq(count_kind(errors, @abi.UnknownVocab), 1)
  assert_true(errors[0].message.contains("shadowed"))
}

///|
test "residual link validation preserves opaque primitive and structural W2-2 behavior" {
  // Case e1: silence about output structure keeps the exact existing opaque diagnostic.
  let undeclared_output = declared_type("opaque_test", None)
  let opaque_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"cell\",\"type\":\"opaque_test\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"cell.field\"}]}",
    [undeclared_output as &@extension.TypeExt],
  )
  assert_eq(opaque_errors.length(), 1)
  assert_eq(opaque_errors[0].kind, @abi.Unsupported)
  assert_eq(
    opaque_errors[0].message,
    "this link path reaches an opaque value structure",
  )
  // Case e2: a primitive output cannot contain any residual field.
  let primitive_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"cell\",\"type\":\"string\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"cell.field\"}]}",
    [],
  )
  assert_eq(primitive_errors.length(), 1)
  assert_eq(primitive_errors[0].kind, @abi.AbsentRef)
}

///|
test "record residual paths resolve statically along the type dependency graph" {
  // Case e3: a declared record field is a statically legal value-space seat.
  let timestamp = declared_type("timestamp", Some(@abi.ValueType::Number))
  let timerange = declared_type(
    "timerange",
    Some(
      @abi.ValueType::Record([("since", "timestamp"), ("until", "timestamp")]),
    ),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"tr\",\"type\":\"timerange\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"tr.since\"}]}",
      [timestamp as &@extension.TypeExt, timerange as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // Case e4: the descent crosses a second registry resident (DR-126 §1's
  // dependency graph), so a two-hop field path is equally static.
  let wrapper = declared_type(
    "wrapper",
    Some(@abi.ValueType::Record([("inner", "timerange")])),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"w\",\"type\":\"wrapper\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"w.inner.until\"}]}",
      [
        timestamp as &@extension.TypeExt,
        timerange as &@extension.TypeExt,
        wrapper as &@extension.TypeExt,
      ],
    )
    is Ok(_),
  )
  // Case e5: a field miss inside the record is the same absent-ref family as a
  // first-phase cell miss (DR-127 §2.2 record row).
  let miss_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"tr\",\"type\":\"timerange\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"tr.nope\"}]}",
    [timestamp as &@extension.TypeExt, timerange as &@extension.TypeExt],
  )
  assert_eq(miss_errors.length(), 1)
  assert_eq(miss_errors[0].kind, @abi.AbsentRef)
  // Case e6: an index segment addresses no record seat — records expose a
  // field vocabulary, never positions.
  let index_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"tr\",\"type\":\"timerange\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"tr[0]\"}]}",
    [timestamp as &@extension.TypeExt, timerange as &@extension.TypeExt],
  )
  assert_eq(index_errors.length(), 1)
  assert_eq(index_errors[0].kind, @abi.AbsentRef)
  // Case e7: a field whose type is silent about its output structure blocks a
  // deeper descent exactly like a silent leaf cell does.
  let opaque_field = declared_type("opaque_payload", None)
  let holder = declared_type(
    "holder",
    Some(@abi.ValueType::Record([("payload", "opaque_payload")])),
  )
  let opaque_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"h\",\"type\":\"holder\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"h.payload.x\"}]}",
    [opaque_field as &@extension.TypeExt, holder as &@extension.TypeExt],
  )
  assert_eq(opaque_errors.length(), 1)
  assert_eq(opaque_errors[0].kind, @abi.Unsupported)
  assert_eq(
    opaque_errors[0].message,
    "this link path reaches an opaque value structure",
  )
}

///|
test "array residual paths continue statically on [int] and reject .name" {
  // DR-127 §2.2 array row: the [int] STRUCTURE is static (index existence is a
  // runtime concern), while a name segment can never address an array.
  let matrix = declared_type(
    "int_matrix",
    Some(@abi.ValueType::Array(@abi.ValueType::Number)),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"m\",\"type\":\"int_matrix\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"m[0]\"}]}",
      [matrix as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // A negative index is the same static structure — its resolution against the
  // current length is runtime (DR-127 §1).
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"m\",\"type\":\"int_matrix\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"m[-1]\"}]}",
      [matrix as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // The element type is followed for deeper segments: array of records keeps
  // field checking static below the index.
  let timestamp = declared_type("timestamp", Some(@abi.ValueType::Number))
  let events = declared_type(
    "events",
    Some(@abi.ValueType::Array(@abi.ValueType::Record([("at", "timestamp")]))),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"e\",\"type\":\"events\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"e[2].at\"}]}",
      [timestamp as &@extension.TypeExt, events as &@extension.TypeExt],
    )
    is Ok(_),
  )
  let field_miss = rejected_type_errors(
    "{\"options\":[{\"name\":\"e\",\"type\":\"events\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"e[2].nope\"}]}",
    [timestamp as &@extension.TypeExt, events as &@extension.TypeExt],
  )
  assert_eq(field_miss.length(), 1)
  assert_eq(field_miss[0].kind, @abi.AbsentRef)
  let name_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"m\",\"type\":\"int_matrix\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"m.first\"}]}",
    [matrix as &@extension.TypeExt],
  )
  assert_eq(name_errors.length(), 1)
  assert_eq(name_errors[0].kind, @abi.AbsentRef)
}

///|
test "map and value residuals defer every remaining segment to runtime" {
  // DR-127 §2.2 map/value row: the static phase legitimately ends, so the
  // definition is accepted; key presence and structure resolve at runtime.
  let lookup = declared_type(
    "lookup",
    Some(@abi.ValueType::Map(@abi.ValueType::Number)),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"l\",\"type\":\"lookup\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"l.some.deep.key\"}]}",
      [lookup as &@extension.TypeExt],
    )
    is Ok(_),
  )
  let anything = declared_type("anything", Some(@abi.ValueType::Value))
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"a\",\"type\":\"anything\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"a.x[3]\"}]}",
      [anything as &@extension.TypeExt],
    )
    is Ok(_),
  )
}

///|
test "union residuals require an agreeing operand parse type across variants" {
  let timestamp = declared_type("timestamp", Some(@abi.ValueType::Number))
  // Agreeing variants: both contain `.at` with the same field type reference,
  // so the operand parser is pinned and the path is statically legal.
  let agree = declared_type(
    "agree_union",
    Some(
      @abi.ValueType::Union([
        @abi.ValueType::Record([("at", "timestamp")]),
        @abi.ValueType::Record([("at", "timestamp"), ("note", "string")]),
      ]),
    ),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"u\",\"type\":\"agree_union\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"u.at\"}]}",
      [timestamp as &@extension.TypeExt, agree as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // A variant that does not contain the path (Bool here) is simply dropped
  // from the agreement set (DR-127 §2.2 union row: 1+ containing variants).
  let partial = declared_type(
    "partial_union",
    Some(
      @abi.ValueType::Union([
        @abi.ValueType::Bool,
        @abi.ValueType::Record([("at", "timestamp")]),
      ]),
    ),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"u\",\"type\":\"partial_union\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"u.at\"}]}",
      [timestamp as &@extension.TypeExt, partial as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // Disagreeing field type references leave the operand parse type undecided
  // at definition time (DR-127 §3.2) — invalid-range.
  let disagree = declared_type(
    "disagree_union",
    Some(
      @abi.ValueType::Union([
        @abi.ValueType::Record([("at", "timestamp")]),
        @abi.ValueType::Record([("at", "number")]),
      ]),
    ),
  )
  let mismatch_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"u\",\"type\":\"disagree_union\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"u.at\"}]}",
    [timestamp as &@extension.TypeExt, disagree as &@extension.TypeExt],
  )
  assert_eq(mismatch_errors.length(), 1)
  assert_eq(mismatch_errors[0].kind, @abi.InvalidRange)
  // A runtime-deferred variant (map) cannot agree with a statically pinned
  // record field — the parse identity would depend on the runtime variant.
  let mixed = declared_type(
    "mixed_union",
    Some(
      @abi.ValueType::Union([
        @abi.ValueType::Record([("at", "timestamp")]),
        @abi.ValueType::Map(@abi.ValueType::Number),
      ]),
    ),
  )
  let mixed_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"u\",\"type\":\"mixed_union\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"u.at\"}]}",
    [timestamp as &@extension.TypeExt, mixed as &@extension.TypeExt],
  )
  assert_eq(mixed_errors.length(), 1)
  assert_eq(mixed_errors[0].kind, @abi.InvalidRange)
}

///|
test "value-space paths into accumulator cells are unsupported" {
  // DR-127 W2 統括裁定 (kuu.mbt 計画 §6.1): the accumulator's composite value
  // is folded in the resolve phase, after effect application, so the effect
  // timeline has no seat a value-space path could address.
  let by_index = rejected_type_errors(
    "{\"options\":[{\"name\":\"tags\",\"type\":\"string\",\"multiple\":true},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"tags[0]\"}]}",
    [],
  )
  assert_eq(by_index.length(), 1)
  assert_eq(by_index[0].kind, @abi.Unsupported)
  assert_true(by_index[0].message.contains("accumulator"))
  // The same closure applies to name segments — the ruling is about the cell
  // kind, not about which segment spelling reaches into it.
  let by_name = rejected_type_errors(
    "{\"options\":[{\"name\":\"tags\",\"type\":\"string\",\"multiple\":true},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"tags.first\"}]}",
    [],
  )
  assert_eq(by_name.length(), 1)
  assert_eq(by_name[0].kind, @abi.Unsupported)
  assert_true(by_name[0].message.contains("accumulator"))
  // A bare link to the accumulator cell itself stays the ordinary supported
  // cell synchronization.
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"tags\",\"type\":\"string\",\"multiple\":true},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"tags\"}]}",
      [],
    )
    is Ok(_),
  )
}

///|
test "cell fn empty requires a container-capable target" {
  // REFERENCE §7.3: empty clears array/map/record; a target whose declaration
  // statically excludes every container form is invalid-range.
  let scalar_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"v\",\"type\":\"string\",\"long\":[\":set\",\"clear:empty\"]}]}",
    [],
  )
  assert_eq(scalar_errors.length(), 1)
  assert_eq(scalar_errors[0].kind, @abi.InvalidRange)
  assert_eq(scalar_errors[0].element, "v")
  // Accumulator cells always carry an array (DR-044 §1), whatever their
  // element type declares.
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"v\",\"type\":\"string\",\"multiple\":true,\"long\":[\":set\",\"clear:empty\"]}]}",
      [],
    )
    is Ok(_),
  )
  // A declared record output is a container.
  let timestamp = declared_type("timestamp", Some(@abi.ValueType::Number))
  let timerange = declared_type(
    "timerange",
    Some(@abi.ValueType::Record([("since", "timestamp")])),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"tr\",\"type\":\"timerange\",\"long\":[\":set\",\"clear:empty\"]}]}",
      [timestamp as &@extension.TypeExt, timerange as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // A type that stays silent about its output structure cannot be shown to be
  // scalar for every input, so no definition-error is asserted.
  let silent = declared_type("silent", None)
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"s\",\"type\":\"silent\",\"long\":[\":set\",\"clear:empty\"]}]}",
      [silent as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // The check follows a bare link: the effect lands on the linked cell, and a
  // scalar link target is rejected with the error attributed to the entry.
  let linked_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"v\",\"type\":\"string\"},{\"name\":\"clear\",\"type\":\"string\",\"link\":\"v\",\"long\":[\"clear:empty\"]}]}",
    [],
  )
  assert_eq(linked_errors.length(), 1)
  assert_eq(linked_errors[0].kind, @abi.InvalidRange)
  assert_eq(linked_errors[0].element, "clear")
  // An alias long_override spelling empty against a scalar canonical target is
  // the same misconfiguration, attributed to the alias.
  let alias_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"v\",\"type\":\"string\",\"long\":true},{\"alias\":\"v\",\"name\":\"w\",\"long\":[\"clear:empty\"]}]}",
    [],
  )
  assert_eq(alias_errors.length(), 1)
  assert_eq(alias_errors[0].kind, @abi.InvalidRange)
  assert_eq(alias_errors[0].element, "w")
}

///|
test "primitive-only unions use absent-ref while malformed unions use only invalid-range" {
  // Case f: every union variant is primitive, so no variant can satisfy a residual field.
  let primitive_union = declared_type(
    "primitive_union",
    Some(@abi.ValueType::Union([@abi.ValueType::Bool, @abi.ValueType::Null])),
  )
  let residual_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"cell\",\"type\":\"primitive_union\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"cell.field\"}]}",
    [primitive_union as &@extension.TypeExt],
  )
  assert_eq(residual_errors.length(), 1)
  assert_eq(residual_errors[0].kind, @abi.AbsentRef)
  // Case g: malformed declarations are rejected before residual classification can add another error.
  let malformed = declared_type(
    "malformed_union",
    Some(@abi.ValueType::Union([@abi.ValueType::Bool])),
  )
  let malformed_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"cell\",\"type\":\"malformed_union\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"cell.field\"}]}",
    [malformed as &@extension.TypeExt],
  )
  assert_eq(count_kind(malformed_errors, @abi.InvalidRange), 1)
  assert_eq(malformed_errors.length(), 1)
}

///|
test "only declarations reachable from used element types are validated" {
  // Case h: registering a broken resident must not poison an unrelated string-only definition.
  let broken = declared_type(
    "brokenref",
    Some(@abi.ValueType::Record([("x", "nosuch")])),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"value\",\"type\":\"string\",\"long\":true}]}",
      [broken as &@extension.TypeExt],
    )
    is Ok(_),
  )
}

///|
test "array map and union nesting all expose record dependency edges" {
  // Cases i1-i3: every value_type container recursively exposes an inner record reference.
  let cases : Array[DeclaredTestType] = [
    declared_type(
      "array_ref",
      Some(@abi.ValueType::Array(@abi.ValueType::Record([("x", "nosuch")]))),
    ),
    declared_type(
      "map_ref",
      Some(@abi.ValueType::Map(@abi.ValueType::Record([("x", "nosuch")]))),
    ),
    declared_type(
      "union_ref",
      Some(
        @abi.ValueType::Union([
          @abi.ValueType::Bool,
          @abi.ValueType::Record([("x", "nosuch")]),
        ]),
      ),
    ),
  ]
  for resident in cases {
    let errors = rejected_type_errors(
      "{\"options\":[{\"name\":\"value\",\"type\":\"" +
      resident.name_ +
      "\",\"long\":true}]}",
      [resident as &@extension.TypeExt],
    )
    assert_eq(count_kind(errors, @abi.UnknownVocab), 1)
  }
}

///|
test "multi-hop errors name the declaration that owns the failing field" {
  // Case j: the missing edge belongs to hop_b, not the seed hop_a.
  let hop_a = declared_type(
    "hop_a",
    Some(@abi.ValueType::Record([("next", "hop_b")])),
  )
  let hop_b = declared_type(
    "hop_b",
    Some(@abi.ValueType::Record([("missing", "nosuch")])),
  )
  let errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"value\",\"type\":\"hop_a\",\"long\":true}]}",
    [hop_a as &@extension.TypeExt, hop_b as &@extension.TypeExt],
  )
  assert_eq(count_kind(errors, @abi.UnknownVocab), 1)
  assert_true(errors[0].message.contains("hop_b"))
  assert_true(errors[0].message.contains("missing"))
}

///|
test "cycles remain visible through nested value_type containers" {
  // Case k: cycle detection follows record edges even when a later edge is nested under array.
  let cycle_a = declared_type(
    "nested_cycle_a",
    Some(@abi.ValueType::Record([("f", "nested_cycle_b")])),
  )
  let cycle_b = declared_type(
    "nested_cycle_b",
    Some(
      @abi.ValueType::Array(@abi.ValueType::Record([("g", "nested_cycle_a")])),
    ),
  )
  let errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"value\",\"type\":\"nested_cycle_a\",\"long\":true}]}",
    [cycle_a as &@extension.TypeExt, cycle_b as &@extension.TypeExt],
  )
  assert_eq(count_kind(errors, @abi.CircularRef), 1)
}

///|
test "non-builtin namespaces are exact and empty records are valid" {
  // Case l: only builtin/ is sugar; extension-qualified spellings retain exact registry identity.
  let namespaced = declared_type("myapp/foo", Some(@abi.ValueType::String))
  let uses_namespaced = declared_type(
    "uses_namespaced",
    Some(@abi.ValueType::Record([("value", "myapp/foo")])),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"value\",\"type\":\"uses_namespaced\",\"long\":true}]}",
      [
        namespaced as &@extension.TypeExt,
        uses_namespaced as &@extension.TypeExt,
      ],
    )
    is Ok(_),
  )
  // Case m: an empty record precisely declares the singleton object value {}.
  let empty_record = declared_type(
    "empty_record",
    Some(@abi.ValueType::Record([])),
  )
  assert_true(
    parse_with_declared_types(
      "{\"options\":[{\"name\":\"value\",\"type\":\"empty_record\",\"long\":true}]}",
      [empty_record as &@extension.TypeExt],
    )
    is Ok(_),
  )
}

///|
test "code-side declarations enforce union uniqueness and reference lexical form" {
  // Case n: structural duplicate union members mirror schema uniqueItems.
  let duplicate = declared_type(
    "duplicate_union",
    Some(@abi.ValueType::Union([@abi.ValueType::Bool, @abi.ValueType::Bool])),
  )
  let duplicate_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"value\",\"type\":\"duplicate_union\",\"long\":true}]}",
    [duplicate as &@extension.TypeExt],
  )
  assert_eq(count_kind(duplicate_errors, @abi.InvalidRange), 1)
  // Case o: lexical invalidity is a declaration error, never an unknown registry lookup.
  let invalid_spelling = declared_type(
    "invalid_spelling",
    Some(@abi.ValueType::Record([("x", "Bad-Name")])),
  )
  let spelling_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"value\",\"type\":\"invalid_spelling\",\"long\":true}]}",
    [invalid_spelling as &@extension.TypeExt],
  )
  assert_eq(count_kind(spelling_errors, @abi.InvalidRange), 1)
  assert_eq(count_kind(spelling_errors, @abi.UnknownVocab), 0)
  // Case p: one definition error reports every declaration violation in discovery order.
  let multiple_violations = declared_type(
    "multiple_violations",
    Some(@abi.ValueType::Record([("x", "Bad"), ("x", "Worse")])),
  )
  let multiple_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"value\",\"type\":\"multiple_violations\",\"long\":true}]}",
    [multiple_violations as &@extension.TypeExt],
  )
  assert_eq(multiple_errors.length(), 1)
  assert_eq(
    multiple_errors[0].message,
    "type 'multiple_violations' has an invalid value_type declaration: record field 'x' has invalid type reference 'Bad' at $; record field 'x' is duplicated at $; record field 'x' has invalid type reference 'Worse' at $",
  )
}

///|
test "shared broken types report independently for every seed element" {
  // Case q: traversal state is seed-local, while diagnostic dedup includes the element identity.
  let broken = declared_type(
    "brokenref",
    Some(@abi.ValueType::Record([("x", "nosuch")])),
  )
  let errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"first\",\"type\":\"brokenref\",\"long\":true},{\"name\":\"second\",\"type\":\"brokenref\",\"long\":true}]}",
    [broken as &@extension.TypeExt],
  )
  assert_eq(count_kind(errors, @abi.UnknownVocab), 2)
  let mut first = false
  let mut second = false
  for error in errors {
    if error.element == "first" {
      first = true
    }
    if error.element == "second" {
      second = true
    }
  }
  assert_true(first)
  assert_true(second)
}

///|
test "structural group and or leaves contribute their actual types as seeds" {
  // A wrapper's own type is unused; each seq/or leaf owns the type that must be validated.
  let broken = declared_type(
    "brokenref",
    Some(@abi.ValueType::Record([("x", "nosuch")])),
  )
  let cases : Array[(String, String)] = [
    (
      "{\"options\":[{\"name\":\"group\",\"long\":true,\"seq\":[{\"type\":\"string\"},{\"name\":\"child\",\"type\":\"brokenref\"}]}]}",
      "child",
    ),
    (
      "{\"options\":[{\"name\":\"choice\",\"long\":true,\"or\":[{\"type\":\"string\"},{\"name\":\"branch\",\"type\":\"brokenref\"}]}]}",
      "branch",
    ),
  ]
  for entry in cases {
    let (source, expected_element) = entry
    let errors = rejected_type_errors(source, [broken as &@extension.TypeExt])
    assert_eq(errors.length(), 1)
    assert_eq(errors[0].kind, @abi.UnknownVocab)
    assert_eq(errors[0].element, expected_element)
  }
  // A malformed leaf is reported by itself and never reclassified by a wrapper.
  let malformed = declared_type(
    "malformed_union",
    Some(@abi.ValueType::Union([@abi.ValueType::Bool])),
  )
  let malformed_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"group\",\"long\":true,\"seq\":[{\"name\":\"child\",\"type\":\"malformed_union\"}]}]}",
    [malformed as &@extension.TypeExt],
  )
  assert_eq(malformed_errors.length(), 1)
  assert_eq(malformed_errors[0].kind, @abi.InvalidRange)
}

///|
test "same-named leaves under different elements retain separate diagnostics" {
  // Diagnostic dedup is seed-local in identity even when two structural leaves expose the same name.
  let broken = declared_type(
    "brokenref",
    Some(@abi.ValueType::Record([("x", "nosuch")])),
  )
  let errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"first_group\",\"long\":true,\"seq\":[{\"name\":\"child\",\"type\":\"brokenref\"}]},{\"name\":\"second_group\",\"long\":true,\"seq\":[{\"name\":\"child\",\"type\":\"brokenref\"}]}]}",
    [broken as &@extension.TypeExt],
  )
  assert_eq(errors.length(), 2)
  assert_eq(count_kind(errors, @abi.UnknownVocab), 2)
  assert_eq(errors[0].element, "child")
  assert_eq(errors[1].element, "child")
}

///|
test "only referenced templates contribute type seeds" {
  // A used template is part of the using element's type surface; an unused template remains inert.
  let broken = declared_type(
    "brokenref",
    Some(@abi.ValueType::Record([("x", "nosuch")])),
  )
  let used = rejected_type_errors(
    "{\"definitions\":{\"templates\":{\"payload\":{\"type\":\"brokenref\"}}},\"options\":[{\"name\":\"entry\",\"long\":true,\"ref\":\"payload\"}]}",
    [broken as &@extension.TypeExt],
  )
  assert_eq(used.length(), 1)
  assert_eq(used[0].kind, @abi.UnknownVocab)
  assert_eq(used[0].element, "entry")
  assert_true(
    parse_with_declared_types(
      "{\"definitions\":{\"templates\":{\"payload\":{\"type\":\"brokenref\"}}},\"options\":[{\"name\":\"entry\",\"type\":\"string\",\"long\":true}]}",
      [broken as &@extension.TypeExt],
    )
    is Ok(_),
  )
  // Traversal state is independent for each element that references the same broken template.
  let twice = rejected_type_errors(
    "{\"definitions\":{\"templates\":{\"payload\":{\"type\":\"brokenref\"}}},\"options\":[{\"name\":\"first\",\"long\":true,\"ref\":\"payload\"},{\"name\":\"second\",\"long\":true,\"ref\":\"payload\"}]}",
    [broken as &@extension.TypeExt],
  )
  assert_eq(twice.length(), 2)
  assert_eq(count_kind(twice, @abi.UnknownVocab), 2)
}

///|
test "referenced templates preserve cycle and malformed declaration diagnostics" {
  // Template indirection changes only the seed location, not type-graph cycle or range semantics.
  let selfnode = declared_type(
    "selfnode",
    Some(@abi.ValueType::Record([("next", "selfnode")])),
  )
  let cycle_errors = rejected_type_errors(
    "{\"definitions\":{\"templates\":{\"payload\":{\"type\":\"selfnode\"}}},\"options\":[{\"name\":\"entry\",\"long\":true,\"ref\":\"payload\"}]}",
    [selfnode as &@extension.TypeExt],
  )
  assert_eq(cycle_errors.length(), 1)
  assert_eq(cycle_errors[0].kind, @abi.CircularRef)
  let malformed = declared_type(
    "malformed_union",
    Some(@abi.ValueType::Union([@abi.ValueType::Bool])),
  )
  let malformed_errors = rejected_type_errors(
    "{\"definitions\":{\"templates\":{\"payload\":{\"type\":\"malformed_union\"}}},\"options\":[{\"name\":\"entry\",\"long\":true,\"ref\":\"payload\"}]}",
    [malformed as &@extension.TypeExt],
  )
  assert_eq(malformed_errors.length(), 1)
  assert_eq(malformed_errors[0].kind, @abi.InvalidRange)
}
