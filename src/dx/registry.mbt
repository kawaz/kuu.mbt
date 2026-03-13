///|
/// Bool フラグを登録。apply_fn はパース成功後に値を受け取る。
pub fn FieldRegistry::flag(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  apply_fn~ : (Bool) -> Unit,
) -> Unit {
  let opt = self.parser.flag(name=name, description=description, global=global)
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

///|
/// String オプションを登録。
pub fn FieldRegistry::string(
  self : FieldRegistry,
  name~ : String,
  default~ : String = "",
  description~ : String = "",
  global~ : Bool = false,
  apply_fn~ : (String) -> Unit,
) -> Unit {
  let opt = self.parser.string_opt(
    name=name,
    default=default,
    description=description,
    global=global,
  )
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

///|
/// Int オプションを登録。
pub fn FieldRegistry::int(
  self : FieldRegistry,
  name~ : String,
  default~ : Int = 0,
  description~ : String = "",
  global~ : Bool = false,
  apply_fn~ : (Int) -> Unit,
) -> Unit {
  let opt = self.parser.int_opt(
    name=name,
    default=default,
    description=description,
    global=global,
  )
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}
