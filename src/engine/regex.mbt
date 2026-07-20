// regex.mbt — resident-neutral host regex compilation.

///|
/// Compile a MoonBit core `string.Regex` from a pattern, converting the raise-on-malformed-pattern
/// signature (`@string.Regex::Regex(StringView) -> Self raise`) into an `Option` — this repo's
/// filter closures return `Result[Value, FnReason]`, not a raise-effect signature, so the
/// raise is caught at the narrowest point (mirrors `value.mbt`'s `try_parse_double` wrapping
/// `@string.parse_double` the same way). `pub` (not just this file's `filter_regex_match`) because
/// `installer.mbt`'s `collect_invalid_regex_pattern` (DR-085 §1 訂正 — pattern compile failure is a
/// definition-error, kind=invalid-argument, DR-054 §4 更新2 / DR-082 §3) needs the SAME compile
/// check at definition time, not just at runtime inside the filter closure.
pub fn compile_regex(pattern : String) -> @string.Regex? {
  Some(@string.Regex::Regex(pattern)) catch {
    _ => None
  }
}
