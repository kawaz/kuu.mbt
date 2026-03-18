///|
/// 位置引数を登録。未指定時は set を呼ばない（struct のデフォルトを維持）。
pub fn FieldRegistry::positional(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  set~ : (String) -> Unit,
) -> Unit {
  let opt = self.parser.positional(name=name, description=description)
  self.appliers.push(fn() {
    if opt.is_set() {
      match opt.get() {
        Some(v) => set(v)
        None => ()
      }
    }
  })
}

///|
/// 残り全引数を収集。未指定時は set を呼ばない（struct のデフォルトを維持）。
pub fn FieldRegistry::rest(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  set~ : (Array[String]) -> Unit,
) -> Unit {
  let opt = self.parser.rest(name=name, description=description)
  self.appliers.push(fn() {
    if opt.is_set() {
      match opt.get() {
        Some(v) => set(v)
        None => ()
      }
    }
  })
}
