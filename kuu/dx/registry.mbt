///|
/// Bool フラグを登録。set はパース成功後に値を受け取る。
pub fn FieldRegistry::flag(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  set~ : (Bool) -> Unit,
) -> Unit {
  ignore(self.flag_ref(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    set=set,
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
  set~ : (Bool) -> Unit,
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
    if opt.is_set() {
      match opt.get() {
        Some(v) => set(v)
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
  set~ : (String) -> Unit,
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
    set=set,
  ))
}

///|
/// String オプションを登録し、OptRef を返す（制約登録用）。
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
  set~ : (String) -> Unit,
) -> @core.OptRef {
  self.custom_ref(
    name=name,
    default=default,
    pre=@core.Filter::map(fn(s) { s }),
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  )
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
  set~ : (Int) -> Unit,
) -> Unit {
  ignore(self.count_ref(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    set=set,
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
  set~ : (Int) -> Unit,
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
    if opt.is_set() {
      match opt.get() {
        Some(v) => set(v)
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
  set~ : (Array[String]) -> Unit,
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
    set=set,
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
  set~ : (Array[String]) -> Unit,
) -> @core.OptRef {
  self.custom_append_ref(
    name=name,
    pre=@core.Filter::map(fn(s) { s }),
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  )
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
  set~ : (Array[Int]) -> Unit,
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
    set=set,
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
  set~ : (Array[Int]) -> Unit,
) -> @core.OptRef {
  self.custom_append_ref(
    name=name,
    pre=@core.Filter::parse_int(),
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  )
}

///|
/// 複数値収集 Double オプションを登録。
pub fn FieldRegistry::append_float(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  set~ : (Array[Double]) -> Unit,
) -> Unit {
  ignore(self.append_float_ref(
    name=name,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  ))
}

///|
/// 複数値収集 Double オプションを登録し、OptRef を返す（制約登録用）。
pub fn FieldRegistry::append_float_ref(
  self : FieldRegistry,
  name~ : String,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  set~ : (Array[Double]) -> Unit,
) -> @core.OptRef {
  self.custom_append_ref(
    name=name,
    pre=@core.Filter::parse_float(),
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  )
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
  set~ : (Int) -> Unit,
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
    set=set,
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
  set~ : (Int) -> Unit,
) -> @core.OptRef {
  self.custom_ref(
    name=name,
    default=default,
    pre=@core.Filter::parse_int(),
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  )
}

///|
/// Double オプションを登録。
pub fn FieldRegistry::float(
  self : FieldRegistry,
  name~ : String,
  default~ : Double = 0.0,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  set~ : (Double) -> Unit,
) -> Unit {
  ignore(self.float_ref(
    name=name,
    default=default,
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  ))
}

///|
/// Double オプションを登録し、OptRef を返す（制約登録用）。
pub fn FieldRegistry::float_ref(
  self : FieldRegistry,
  name~ : String,
  default~ : Double = 0.0,
  description~ : String = "",
  global~ : Bool = false,
  shorts~ : String = "",
  aliases~ : Array[String] = [],
  env~ : String = "",
  hidden~ : Bool = false,
  value_name~ : String = "",
  set~ : (Double) -> Unit,
) -> @core.OptRef {
  self.custom_ref(
    name=name,
    default=default,
    pre=@core.Filter::parse_float(),
    description=description,
    global=global,
    shorts=shorts,
    aliases=aliases,
    env=env,
    hidden=hidden,
    value_name=value_name,
    set=set,
  )
}
