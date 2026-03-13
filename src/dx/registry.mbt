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
  ignore(self.flag_ref(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    apply_fn=apply_fn,
  ))
}

///|
/// Bool フラグを登録し、OptRef を返す（制約登録用）。
/// env はヘルプ表示用メタデータのみ。環境変数からの値読み取りは行わない（DR-041 Phase 1）。
pub fn FieldRegistry::flag_ref(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  apply_fn~ : (Bool) -> Unit,
) -> @core.OptRef {
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
    if (opt.is_set)() {
      match opt.get() {
        Some(v) => apply_fn(v)
        None => ()
      }
    }
  })
  opt.as_ref()
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
  ignore(self.string_ref(
    name=name,
    default=default,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    apply_fn=apply_fn,
  ))
}

///|
/// String オプションを登録し、OptRef を返す（制約登録用）。
/// env はヘルプ表示用メタデータのみ。環境変数からの値読み取りは行わない（DR-041 Phase 1）。
pub fn FieldRegistry::string_ref(
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
) -> @core.OptRef {
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
    if (opt.is_set)() {
      match opt.get() {
        Some(v) => apply_fn(v)
        None => ()
      }
    }
  })
  opt.as_ref()
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
  ignore(self.count_ref(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    apply_fn=apply_fn,
  ))
}

///|
/// カウントオプションを登録し、OptRef を返す（制約登録用）。
pub fn FieldRegistry::count_ref(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  apply_fn~ : (Int) -> Unit,
) -> @core.OptRef {
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
    if (opt.is_set)() {
      match opt.get() {
        Some(v) => apply_fn(v)
        None => ()
      }
    }
  })
  opt.as_ref()
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
  ignore(self.append_string_ref(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    apply_fn=apply_fn,
  ))
}

///|
/// 複数値収集 String オプションを登録し、OptRef を返す（制約登録用）。
pub fn FieldRegistry::append_string_ref(
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
) -> @core.OptRef {
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
    if (opt.is_set)() {
      match opt.get() {
        Some(v) => apply_fn(v)
        None => ()
      }
    }
  })
  opt.as_ref()
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
  ignore(self.append_int_ref(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    apply_fn=apply_fn,
  ))
}

///|
/// 複数値収集 Int オプションを登録し、OptRef を返す（制約登録用）。
pub fn FieldRegistry::append_int_ref(
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
) -> @core.OptRef {
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
    if (opt.is_set)() {
      match opt.get() {
        Some(v) => apply_fn(v)
        None => ()
      }
    }
  })
  opt.as_ref()
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
  ignore(self.int_ref(
    name=name,
    default=default,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    apply_fn=apply_fn,
  ))
}

///|
/// Int オプションを登録し、OptRef を返す（制約登録用）。
pub fn FieldRegistry::int_ref(
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
) -> @core.OptRef {
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
    if (opt.is_set)() {
      match opt.get() {
        Some(v) => apply_fn(v)
        None => ()
      }
    }
  })
  opt.as_ref()
}
