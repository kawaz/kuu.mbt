// completer_ext.mbt — named completion residents registered independently from value types.

///|
/// Minimal builtin/custom completer identity. DR-117's files/dirs residents are shell actions rather
/// than host-language functions, so the core registry records their names without inventing an
/// input/output type contract. Runtime translation belongs to the completion product layer.
pub(open) trait CompleterExt {
  fn name(Self) -> String
}
