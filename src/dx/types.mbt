///|
/// CLI パース可能な struct が実装する trait。
/// register メソッドで FieldRegistry にフィールド登録を行う。
pub(open) trait Parseable {
  register(Self, FieldRegistry) -> Unit
}

///|
/// パース結果を struct フィールドに適用するクロージャを蓄積する。
/// kuu core の Parser をラップし、trait impl から呼ばれる登録メソッドを提供する。
///
/// applier は parse 成功後にのみ apply_all() で一括実行される。
/// parse がエラーを raise した場合、apply_all() は呼ばれず target は初期状態のまま。
pub(all) struct FieldRegistry {
  parser : @core.Parser
  appliers : Array[() -> Unit]
}

///|
fn FieldRegistry::new(parser : @core.Parser) -> FieldRegistry {
  { parser, appliers: [] }
}

///|
/// 蓄積された全 applier を実行。parse 成功後にのみ呼ぶこと。
fn FieldRegistry::apply_all(self : FieldRegistry) -> Unit {
  for applier in self.appliers {
    applier()
  }
}
