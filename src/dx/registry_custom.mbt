///|
/// 汎用カスタムオプションを登録。pre フィルタで String → T に変換する。
pub fn[T : Show] FieldRegistry::custom(
  self : FieldRegistry,
  name~ : String,
  default~ : T,
  pre~ : @core.FilterChain[String, T],
  description? : String = "",
  global? : Bool = false,
  shorts? : String = "",
  aliases? : Array[String] = [],
  env? : String = "",
  hidden? : Bool = false,
  value_name? : String = "",
  set~ : (T) -> Unit,
) -> Unit {
  ignore(
    self.custom_ref(
      name~,
      default~,
      pre~,
      description~,
      global~,
      shorts~,
      aliases~,
      env~,
      hidden~,
      value_name~,
      set~,
    ),
  )
}

///|
/// 汎用カスタムオプションを登録し、OptRef を返す（制約登録用）。
pub fn[T : Show] FieldRegistry::custom_ref(
  self : FieldRegistry,
  name~ : String,
  default~ : T,
  pre~ : @core.FilterChain[String, T],
  description? : String = "",
  global? : Bool = false,
  shorts? : String = "",
  aliases? : Array[String] = [],
  env? : String = "",
  hidden? : Bool = false,
  value_name? : String = "",
  set~ : (T) -> Unit,
) -> @core.OptRef {
  let opt = self.parser.custom(
    name~,
    default~,
    pre~,
    description~,
    global~,
    shorts~,
    aliases~,
    env~,
    hidden~,
    value_name~,
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
/// 汎用カスタム append オプションを登録。
pub fn[T] FieldRegistry::custom_append(
  self : FieldRegistry,
  name~ : String,
  pre~ : @core.FilterChain[String, T],
  description? : String = "",
  global? : Bool = false,
  shorts? : String = "",
  aliases? : Array[String] = [],
  env? : String = "",
  hidden? : Bool = false,
  value_name? : String = "",
  set~ : (Array[T]) -> Unit,
) -> Unit {
  ignore(
    self.custom_append_ref(
      name~,
      pre~,
      description~,
      global~,
      shorts~,
      aliases~,
      env~,
      hidden~,
      value_name~,
      set~,
    ),
  )
}

///|
/// 汎用カスタム append オプションを登録し、OptRef を返す（制約登録用）。
pub fn[T] FieldRegistry::custom_append_ref(
  self : FieldRegistry,
  name~ : String,
  pre~ : @core.FilterChain[String, T],
  description? : String = "",
  global? : Bool = false,
  shorts? : String = "",
  aliases? : Array[String] = [],
  env? : String = "",
  hidden? : Bool = false,
  value_name? : String = "",
  set~ : (Array[T]) -> Unit,
) -> @core.OptRef {
  let opt = self.parser.custom_append(
    name~,
    pre~,
    description~,
    global~,
    shorts~,
    aliases~,
    env~,
    hidden~,
    value_name~,
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
