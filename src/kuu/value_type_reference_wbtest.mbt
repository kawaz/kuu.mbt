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
  // Case e3: W2-6 で record 降下 (静的成功) へ置換される暫定 pin。
  let timestamp = declared_type("timestamp", Some(@abi.ValueType::Number))
  let timerange = declared_type(
    "timerange",
    Some(@abi.ValueType::Record([("since", "timestamp")])),
  )
  let record_errors = rejected_type_errors(
    "{\"options\":[{\"name\":\"tr\",\"type\":\"timerange\"},{\"name\":\"entry\",\"type\":\"string\",\"long\":true,\"link\":\"tr.since\"}]}",
    [timestamp as &@extension.TypeExt, timerange as &@extension.TypeExt],
  )
  assert_eq(record_errors.length(), 1)
  assert_eq(record_errors[0].kind, @abi.Unsupported)
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
}

///|
test "shared broken types report independently for every seed element" {
  // Case p: traversal state is seed-local, while diagnostic dedup includes the element identity.
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
