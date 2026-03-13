///|
/// 排他制約: 指定されたオプション群は同時に使用できない。
pub fn FieldRegistry::exclusive(
  self : FieldRegistry,
  refs : Array[@core.OptRef],
) -> Unit {
  self.parser.exclusive(refs)
}

///|
/// 必須制約: 指定されたオプションは必ず指定しなければならない。
pub fn FieldRegistry::required(
  self : FieldRegistry,
  ref_ : @core.OptRef,
) -> Unit {
  self.parser.required(ref_)
}

///|
/// 少なくとも1つ制約: 指定されたオプション群のうち少なくとも1つを指定しなければならない。
pub fn FieldRegistry::at_least_one(
  self : FieldRegistry,
  refs : Array[@core.OptRef],
) -> Unit {
  self.parser.at_least_one(refs)
}
