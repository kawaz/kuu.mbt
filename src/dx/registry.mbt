///|
/// Bool フラグを登録。apply_fn はパース成功後に値を受け取る。
pub fn FieldRegistry::flag(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  apply_fn~ : (Bool) -> Unit,
) -> Unit {
  let opt = self.parser.flag(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
  )
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
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  apply_fn~ : (String) -> Unit,
) -> Unit {
  let opt = self.parser.string_opt(
    name=name,
    default=default,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
  )
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

///|
/// カウントオプションを登録（--verbose --verbose → 2）。
pub fn FieldRegistry::count(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  apply_fn~ : (Int) -> Unit,
) -> Unit {
  let opt = self.parser.count(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
  )
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

///|
/// 複数値収集 String オプションを登録。
pub fn FieldRegistry::append_string(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  apply_fn~ : (Array[String]) -> Unit,
) -> Unit {
  let opt = self.parser.append_string(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
  )
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}

///|
/// 複数値収集 Int オプションを登録。
pub fn FieldRegistry::append_int(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  apply_fn~ : (Array[Int]) -> Unit,
) -> Unit {
  let opt = self.parser.append_int(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
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
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  apply_fn~ : (Int) -> Unit,
) -> Unit {
  let opt = self.parser.int_opt(
    name=name,
    default=default,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
  )
  self.appliers.push(fn() {
    match opt.get() {
      Some(v) => apply_fn(v)
      None => ()
    }
  })
}
