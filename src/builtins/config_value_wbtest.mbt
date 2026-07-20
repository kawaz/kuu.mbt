// config_value_wbtest.mbt — builtin config conversion executable specification.

// ── DR-050 §4 config_to_value (DR-074/075 追従) ────────────────────────────────

///|
fn config(json : Json) -> @engine.ConfigVal {
  @engine.config_from_json(json)
}

///|
fn config_chain(names : Array[String]) -> Array[@engine.FilterSpelling] {
  names.map(name => { name, args: [] })
}

///|
fn cv_ok(
  r : Result[@engine.Value, (@engine.ErrKind, String, String)],
) -> @engine.Value? {
  match r {
    Ok(v) => Some(v)
    Err(_) => None
  }
}

///|
/// A config leaf converts to the element's type with bidirectionally-symmetric leniency (DR-050 §4):
/// a string parses into any type, and a JSON scalar stringifies into a string element. The int seat is
/// 値空間判定 with canonical `int_round: error` (DR-075): `"3.0"` → 3, `"2.5"` → Error. The bool seat
/// uses the canonical vocab. Semantic jumps (bool↔number) and structural mismatches stay Errors.
/// `piece_filters` is `[]` throughout — issue 2026-07-09-config-string-pieceprocessor-gap's own
/// piece_filters-application test lives separately (below), so these cases isolate the type-leniency
/// matrix from the filter chain.
test "config_to_value type conversions" {
  // string → number / int (lenient parse), and 値空間 int acceptance of "3.0".
  assert_eq(
    cv_ok(
      config_to_value(
        config("8080".to_json()),
        number_type(),
        [],
        test_filter_registry(),
      ),
    ),
    Some(@engine.Number(8080.0)),
  )
  assert_eq(
    cv_ok(
      config_to_value(
        config("3.0".to_json()),
        int_type(),
        [],
        test_filter_registry(),
      ),
    ),
    Some(@engine.Number(3.0)),
  )
  // "2.5" into int is Error under canonical error mode (no silent 精度落ち).
  assert_eq(
    cv_ok(
      config_to_value(
        config("2.5".to_json()),
        int_type(),
        [],
        test_filter_registry(),
      ),
    ),
    None,
  )
  // JSON scalar → string element stringifies (寛容の双方向対称): 1.5 → "1.5", true → "true".
  assert_eq(
    cv_ok(
      config_to_value(
        config(1.5.to_json()),
        string_type(),
        [],
        test_filter_registry(),
      ),
    ),
    Some(@engine.String("1.5")),
  )
  assert_eq(
    cv_ok(
      config_to_value(
        config(true.to_json()),
        string_type(),
        [],
        test_filter_registry(),
      ),
    ),
    Some(@engine.String("true")),
  )
  // string → bool via canonical vocab; an unknown word is an Error.
  assert_eq(
    cv_ok(
      config_to_value(
        config("1".to_json()),
        flag_type(),
        [],
        test_filter_registry(),
      ),
    ),
    Some(@engine.Bool(true)),
  )
  assert_eq(
    cv_ok(
      config_to_value(
        config("yes".to_json()),
        flag_type(),
        [],
        test_filter_registry(),
      ),
    ),
    None,
  )
  // native number → int: JSON-由来 binary64 seat; 1.0 is integral (accepted), 1.5 is not (Error).
  assert_eq(
    cv_ok(
      config_to_value(
        config(1.0.to_json()),
        int_type(),
        [],
        test_filter_registry(),
      ),
    ),
    Some(@engine.Number(1.0)),
  )
  assert_eq(
    cv_ok(
      config_to_value(
        config(1.5.to_json()),
        int_type(),
        [],
        test_filter_registry(),
      ),
    ),
    None,
  )
  // 意味の飛躍 (bool↔number) is always an Error — no coercion in either direction.
  assert_eq(
    cv_ok(
      config_to_value(
        config(1.0.to_json()),
        flag_type(),
        [],
        test_filter_registry(),
      ),
    ),
    None,
  )
  assert_eq(
    cv_ok(
      config_to_value(
        config(true.to_json()),
        number_type(),
        [],
        test_filter_registry(),
      ),
    ),
    None,
  )
  // 構造不一致 (array/object → scalar) is an Error.
  assert_eq(
    cv_ok(
      config_to_value(
        config([1.0].to_json()),
        number_type(),
        [],
        test_filter_registry(),
      ),
    ),
    None,
  )
}

///|
/// 保証 (codex 節目レビュー想定と同型の観点、issue 2026-07-09-config-string-pieceprocessor-gap): a
/// `String` config source runs `piece_filters` BEFORE its type parse — exactly like `resolve.mbt`'s
/// `env_value` does for the env seat (DR-049 §2), and `eval.mbt`'s CLI token-consumption path.
/// `trim` (DR-034 built-in piece_filter) rescues a config string with surrounding whitespace that
/// would otherwise fail `parse_number` outright — this is the concrete, previously-impossible
/// case the gap issue's TODO describes (`{"port": " 8080 "}`). A non-string source (Number/Bool
/// matching its type) has NO piece_filters step to skip past (§4's type-consequence, not tested by
/// omission here — the type-leniency matrix above already covers those arms with `[]`).
test "config_to_value: piece_filters runs on a String source before the type parse (DR-050 §4)" {
  assert_eq(
    cv_ok(
      config_to_value(
        config(" 8080 ".to_json()),
        number_type(),
        config_chain(["trim"]),
        test_filter_registry(),
      ),
    ),
    Some(@engine.Number(8080.0)),
  )
  // without the piece_filter, the same raw string fails to parse (proves `trim` is load-bearing,
  // not a no-op the type parser would have tolerated anyway).
  assert_eq(
    cv_ok(
      config_to_value(
        config(" 8080 ".to_json()),
        number_type(),
        [],
        test_filter_registry(),
      ),
    ),
    None,
  )
  // piece_filters ALSO runs for a string target (string_type() の「何でも受ける」型でも trim は素通りしない —
  // DR-050 §4 の全段 pipeline は target 型を問わない).
  assert_eq(
    cv_ok(
      config_to_value(
        config(" hi ".to_json()),
        string_type(),
        config_chain(["trim"]),
        test_filter_registry(),
      ),
    ),
    Some(@engine.String("hi")),
  )
  // a piece_filters REJECT (not just a parse failure) surfaces as KFilter, distinct from a KParse
  // type-mismatch — `resolve.mbt`'s caller picks the ParseError constructor by this tag.
  match
    config_to_value(
      config("".to_json()),
      number_type(),
      config_chain(["non_empty"]),
      test_filter_registry(),
    ) {
    Err((@engine.KFilter, _, _)) => ()
    Ok(_) => fail("expected Err(KFilter, ..), got Ok")
    Err((@engine.KParse, _, _)) =>
      fail("expected Err(KFilter, ..), got Err(KParse, ..)")
    Err((@engine.KConstraint, _, _)) =>
      fail("expected Err(KFilter, ..), got Err(KConstraint, ..)")
  }
}
