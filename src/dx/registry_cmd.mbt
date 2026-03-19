///|
/// サブコマンドを登録。
/// setup: 子パーサの FieldRegistry を受け取り、子のフィールドを登録する。
/// on_match: 当該サブコマンドが選択された場合に呼ばれるコールバック（省略可）。
pub fn FieldRegistry::sub(
  self : FieldRegistry,
  name~ : String,
  description? : String = "",
  aliases? : Array[String] = [],
  setup~ : (FieldRegistry) -> Unit,
  on_match? : () -> Unit = fn() {  },
) -> Unit {
  let child_registry_ref : Ref[FieldRegistry?] = { val: None }
  let cmd = self.parser.cmd(name~, description~, aliases~, setup=fn(
    child_parser,
  ) {
    let child_reg = FieldRegistry::new(child_parser)
    setup(child_reg)
    child_registry_ref.val = Some(child_reg)
  })
  self.appliers.push(fn() {
    if cmd.is_set() {
      on_match()
      match child_registry_ref.val {
        Some(child_reg) => child_reg.apply_all()
        None => ()
      }
    }
  })
}

///|
/// サブコマンドを必須にする。
pub fn FieldRegistry::require_cmd(self : FieldRegistry) -> Unit {
  self.parser.require_cmd()
}

///|
/// パーサの説明文を設定する。
pub fn FieldRegistry::set_description(
  self : FieldRegistry,
  description : String,
) -> Unit {
  self.parser.set_description(description)
}
