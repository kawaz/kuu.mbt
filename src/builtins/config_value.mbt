// config_value.mbt — builtin config scalar conversion through TypeExt residents.

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
/// when config's source happens to be a string). Every `(@engine.CStr(s), _)` arm below sees the
/// ALREADY-filtered string.
///
/// Error shape `(ErrKind, reason, message)`: `@engine.KFilter` for a piece_filters rejection (mirrors
/// `resolve.mbt`'s `filter_err`), `@engine.KParse` for every type-mismatch/parse-failure arm (mirrors
/// `ladder_err`) — the caller picks the matching `ParseError` constructor by this tag. `message`
/// is caller-facing text only (conformance ignores it, per this file's `ParseError` doc comment).
pub fn config_to_value(
  cv : @engine.ConfigVal,
  ty : &@engine.TypeExt,
  piece_filters : Array[@engine.FilterSpelling],
  extensions : @engine.Registry,
) -> Result[@engine.Value, (@engine.ErrKind, String, String)] {
  match cv {
    // Every string source crosses the resident parser after piece filtering. Parser
    // configuration is therefore resident-owned for CLI, env, and config alike.
    @engine.CStr(raw) =>
      match @engine.apply_piece_filters(extensions, piece_filters, raw) {
        Err((reason, msg)) => Err((@engine.KFilter, reason, msg))
        Ok(s) =>
          match ty.parse_token(s) {
            Ok(value) => Ok(value)
            Err(fail) =>
              Err((@engine.KParse, fail.reason(), "config " + fail.message(s)))
          }
      }
    // JSON-native scalars do not need lexical parsing. The resident identity still
    // selects the permitted value space and preserves the symmetric string coercion.
    @engine.CNum(d) =>
      match ty.name() {
        "string" => Ok(@engine.VStr(num_to_string(d)))
        "number" | "float" | "count" => Ok(@engine.VNum(d))
        "int" =>
          if @engine.is_integer(d) {
            Ok(@engine.VNum(d))
          } else {
            Err(
              (
                @engine.KParse,
                "not_an_integer",
                "config value \"\{num_to_string(d)}\" is not an integer",
              ),
            )
          }
        "flag" | "bool" =>
          Err(
            (
              @engine.KParse,
              "config_type_mismatch",
              "config number for a bool element (no number↔bool coercion)",
            ),
          )
        _ =>
          Err(
            (
              @engine.KParse,
              "config_type_mismatch",
              "config value for a none element (no value space)",
            ),
          )
      }
    @engine.CBool(b) =>
      match ty.name() {
        "string" => Ok(@engine.VStr(if b { "true" } else { "false" }))
        "flag" | "bool" => Ok(@engine.VBool(b))
        "number" | "float" | "count" | "int" =>
          Err(
            (
              @engine.KParse,
              "config_type_mismatch",
              "config bool for a numeric element (no number↔bool coercion)",
            ),
          )
        _ =>
          Err(
            (
              @engine.KParse,
              "config_type_mismatch",
              "config value for a none element (no value space)",
            ),
          )
      }
    // Structured values cannot fill a scalar resident.
    @engine.CArr(_) =>
      Err(
        (
          @engine.KParse,
          "config_structural_mismatch",
          "config array for a scalar element (structural mismatch)",
        ),
      )
    @engine.CObj(_) =>
      Err(
        (
          @engine.KParse,
          "config_structural_mismatch",
          "config object for a scalar element (structural mismatch)",
        ),
      )
    @engine.CNull =>
      Err(
        (
          @engine.KParse,
          "config_type_mismatch",
          "config null is 供給なし (should be handled as no-supply, not converted)",
        ),
      )
  }
}
