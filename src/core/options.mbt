///|
/// env_applicator を登録する共通ヘルパー。
/// env が非空の場合のみ、committed=false なら env から値を取得して適用する。
/// env_prefix が設定されている場合は prefix + "_" + env をキーとして参照する。
fn[T] register_env_applicator(
  parser : Parser,
  env : String,
  vc : ValCell[T],
  converter : (String) -> T raise ParseError,
) -> Unit {
  if env != "" {
    let prefix_ref = parser.env_prefix
    parser.env_applicators.push(fn(env_map) raise ParseError {
      if not(vc.committed.val) {
        let key = if prefix_ref.val == "" {
          env
        } else {
          prefix_ref.val + "_" + env
        }
        match env_map.get(key) {
          Some(raw) =>
            if raw != "" {
              vc.cell.val = converter(raw)
              vc.committed.val = true
            }
          None => ()
        }
      }
    })
  }
}

///|
/// Variation sugar パラメータを variations 配列に展開するヘルパー
fn apply_variation_sugar(
  variations : Array[Variation],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Unit {
  if variation_toggle is Some(p) {
    variations.push(Toggle(p))
  }
  if variation_true is Some(p) {
    variations.push(True(p))
  }
  if variation_false is Some(p) {
    variations.push(False(p))
  }
  if variation_reset is Some(p) {
    variations.push(Reset(p))
  }
  if variation_unset is Some(p) {
    variations.push(Unset(p))
  }
}

///|
pub fn Parser::flag(
  self : Parser,
  name~ : String,
  default? : Bool = false,
  default_fn? : (() -> Bool)? = None,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  env? : String = "",
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Bool] {
  let env = self.effective_env_name(env, name, visibility)
  apply_variation_sugar(
    variations,
    variation_toggle~,
    variation_true~,
    variation_false~,
    variation_reset~,
    variation_unset~,
  )
  // default_fn があれば default を上書き
  let initial_val = match default_fn {
    Some(f) => f()
    None => default
  }
  let vc : ValCell[Bool] = ValCell::new(Val(initial_val))
  let pending : Ref[Bool] = { val: initial_val }
  let reset_fn = fn() {
    vc.cell.val = initial_val
    pending.val = initial_val
  }
  let positive_match = fn() {
    pending.val = not(initial_val)
    fn() { vc.cell.val = pending.val }
  }
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=description,
    value_name="",
    default_display="",
    env_name=env,
    kind=Flag,
    variations~,
    valcell=vc,
    make_main_node=fn(n) { make_flag_node(n, positive_match, reset_fn) },
    make_node_for_variation=fn(vn, v) {
      match v {
        Toggle(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                vc.cell.val = not(vc.cell.val)
                vc.committed.val = true
              }
            },
            fn() {
              vc.cell.val = initial_val
              vc.committed.val = false
            },
          )
        True(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                vc.cell.val = true
                vc.committed.val = true
              }
            },
            fn() {
              vc.cell.val = initial_val
              vc.committed.val = false
            },
          )
        False(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                vc.cell.val = false
                vc.committed.val = true
              }
            },
            fn() {
              vc.cell.val = initial_val
              vc.committed.val = false
            },
          )
        Reset(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                vc.cell.val = initial_val
                vc.committed.val = true
              }
            },
            fn() {
              vc.cell.val = initial_val
              vc.committed.val = false
            },
          )
        Unset(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                vc.cell.val = initial_val
                vc.committed.val = false
              }
            },
            fn() {
              vc.cell.val = initial_val
              vc.committed.val = false
            },
          )
      }
    },
  )
  register_env_applicator(self, env, vc, raw => {
    let lower = raw.to_lower()
    if lower == "true" || lower == "1" {
      true
    } else if lower == "false" || lower == "0" {
      false
    } else {
      raise parse_error(
        "invalid value for env " +
        env +
        ": " +
        raw +
        " (expected true/false/1/0)",
      )
    }
  })
  opt
}

///|
/// File path sugar combinator. Wraps `custom[String]` with `implicit_value`
/// to support a 3-state pattern: not specified → default, flag-only → default_path,
/// value specified → the given path.
pub fn Parser::file(
  self : Parser,
  name~ : String,
  default~ : String,
  default_path~ : String,
  default_fn? : (() -> String)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "PATH",
  visibility? : Visibility = Visible,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  post? : FilterChain[String, String]? = None,
  choices? : Array[String] = [],
) -> Opt[String] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    aliases~,
    shorts~,
    global~,
    post~,
    choices~,
    implicit_value=Some(Val(default_path)),
    pre=Filter::map(fn(s) { s }),
  )
}

///|
pub fn Parser::string(
  self : Parser,
  name~ : String,
  default~ : String,
  default_fn? : (() -> String)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  post? : FilterChain[String, String]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[String]? = None,
) -> Opt[String] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::map(fn(s) { s }),
  )
}

///|
pub fn Parser::int(
  self : Parser,
  name~ : String,
  default~ : Int,
  default_fn? : (() -> Int)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  post? : FilterChain[Int, Int]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[Int]? = None,
) -> Opt[Int] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::parse_int(),
  )
}

///|
pub fn Parser::float(
  self : Parser,
  name~ : String,
  default~ : Double,
  default_fn? : (() -> Double)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  post? : FilterChain[Double, Double]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[Double]? = None,
) -> Opt[Double] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::parse_float(),
  )
}

///|
pub fn Parser::boolean(
  self : Parser,
  name~ : String,
  default? : Bool = false,
  default_fn? : (() -> Bool)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  post? : FilterChain[Bool, Bool]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[Bool]? = None,
) -> Opt[Bool] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::parse_bool(),
  )
}

///|
pub fn Parser::append_string(
  self : Parser,
  name~ : String,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
) -> Opt[Array[String]] {
  self.custom_append(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    pre=Filter::map(fn(s) { s }),
  )
}

///|
pub fn Parser::append_int(
  self : Parser,
  name~ : String,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
) -> Opt[Array[Int]] {
  self.custom_append(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    pre=Filter::parse_int(),
  )
}

///|
pub fn Parser::append_float(
  self : Parser,
  name~ : String,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
) -> Opt[Array[Double]] {
  self.custom_append(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    pre=Filter::parse_float(),
  )
}

///|
pub fn Parser::count(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  env? : String = "",
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Int] {
  let env = self.effective_env_name(env, name, visibility)
  apply_variation_sugar(
    variations,
    variation_toggle~,
    variation_true~,
    variation_false~,
    variation_reset~,
    variation_unset~,
  )
  let vc : ValCell[Int] = ValCell::new(Val(0))
  let pending : Ref[Int] = { val: 0 }
  let reset_fn = fn() {
    vc.cell.val = 0
    pending.val = 0
  }
  let positive_match = fn() {
    pending.val = pending.val + 1
    fn() { vc.cell.val = pending.val }
  }
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=description,
    value_name="",
    default_display="",
    env_name=env,
    kind=Flag,
    variations~,
    valcell=vc,
    make_main_node=fn(n) { make_flag_node(n, positive_match, reset_fn) },
    make_node_for_variation=fn(vn, v) {
      match v {
        Reset(_) | Toggle(_) | True(_) | False(_) =>
          make_flag_node(
            vn,
            fn() {
              pending.val = 0
              fn() {
                vc.cell.val = pending.val
                vc.committed.val = true
              }
            },
            fn() {
              vc.cell.val = 0
              pending.val = 0
              vc.committed.val = false
            },
          )
        Unset(_) =>
          make_flag_node(
            vn,
            fn() {
              pending.val = 0
              fn() {
                vc.cell.val = pending.val
                vc.committed.val = false
              }
            },
            fn() {
              vc.cell.val = 0
              pending.val = 0
              vc.committed.val = false
            },
          )
      }
    },
  )
  register_env_applicator(self, env, vc, raw => {
    @strconv.parse_int(raw) catch {
      _ =>
        raise parse_error(
          "invalid value for env " + env + ": " + raw + " (expected integer)",
        )
    }
  })
  opt
}

///|
pub fn[T : Show] Parser::custom(
  self : Parser,
  name~ : String,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  default_display? : String? = None,
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  default~ : T,
  default_fn? : (() -> T)? = None,
  pre~ : FilterChain[String, T],
  post? : FilterChain[T, T]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[T]? = None,
) -> Opt[T] {
  let env = self.effective_env_name(env, name, visibility)
  let initial_val = match default_fn {
    Some(f) => f()
    None => default
  }
  let effective_display = match default_display {
    Some(s) => s
    None => initial_val.to_string()
  }
  // choices 情報を help 文字列に付加（OptMeta にフィールドを持たない設計）
  let effective_help : String = if choices.length() > 0 {
    description + " [possible values: " + choices.join(", ") + "]"
  } else {
    description
  }
  let vc : ValCell[T] = ValCell::new(Val(initial_val))
  let has_choices = choices.length() > 0
  let has_implicit = implicit_value is Some(_)

  // variation ノード: Toggle/True/False は Reset 相当にフォールバック（値コンビネータに Bool 反転の意味論なし）
  let make_var_node = fn(vn : String, v : Variation) -> ExactNode {
    match v {
      Reset(_) | Toggle(_) | True(_) | False(_) =>
        wrap_node_with_set(
          make_flag_node(vn, fn() { fn() { vc.cell.val = initial_val } }, fn() {
            vc.cell.val = initial_val
          }),
          vc.committed,
        )
      Unset(_) =>
        make_flag_node(
          vn,
          fn() {
            fn() {
              vc.cell.val = initial_val
              vc.committed.val = false
            }
          },
          fn() {
            vc.cell.val = initial_val
            vc.committed.val = false
          },
        )
    }
  }

  let make_main : (String) -> ExactNode = if has_implicit {
    let iv = match implicit_value {
      Some(v) => v
      None => Val(default) // unreachable
    }
    fn(opt_name : String) -> ExactNode {
      let children : Array[ExactNode] = []
      if has_choices {
        for choice in choices {
          children.push(
            make_custom_choice_value_node(
              opt_name,
              choice,
              pre,
              vc.cell,
              initial_val,
            ),
          )
        }
      } else {
        children.push(
          make_soft_custom_value_node(opt_name, pre, vc.cell, initial_val),
        )
      }
      children.push(make_implicit_flag_node(opt_name, iv, vc.cell, initial_val))
      make_or_node(opt_name, true, children)
    }
  } else {
    let pending : Ref[T] = { val: initial_val }
    let reset = fn() { vc.cell.val = initial_val }
    let accum : Accumulator[T, T] = fn(_current, piece) { piece }
    // choices がある場合は one_of → pre の合成。FilterChain::then で Kleisli composition
    let effective_pre : FilterChain[String, T] = if has_choices {
      Filter::one_of(choices).then(pre)
    } else {
      pre
    }
    let reducer = make_reducer(effective_pre, accum)
    fn(opt_name : String) -> ExactNode {
      make_reduced_value_node(opt_name, reducer, vc.cell, pending, reset)
    }
  }

  let display_value_name = if value_name == "" {
    name.to_upper()
  } else {
    value_name
  }
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=effective_help,
    value_name=display_value_name,
    default_display=effective_display,
    env_name=env,
    kind=ValueOpt,
    variations~,
    valcell=vc,
    make_main_node=make_main,
    make_node_for_variation=make_var_node,
  )
  // H-1 fix: implicit_value 付き (choices なし) の場合、eq_split 用に
  // "--" ガードなしの value ノードを追加。make_soft_custom_value_node の
  // "--" prefix ガードは通常パースで必要だが、eq_split 経由の明示的な値には不要。
  if has_implicit && not(has_choices) {
    let eq_on_match = fn(s : String) -> Result[() -> Unit, ParseError] {
      let r : Result[T, ParseError] = try? (pre.run)(s)
      match r {
        Ok(v) =>
          Ok(fn() {
            vc.cell.val = v
            vc.committed.val = true
          })
        Err(e) => Err(e)
      }
    }
    let eq_reset = fn() { () }
    let make_eq_fb : (String) -> ExactNode = fn(n) {
      make_value_node(n, eq_on_match, eq_reset)
    }
    self.eq_fallback_nodes.push(make_eq_fb("--" + name))
    for alt in aliases {
      self.eq_fallback_nodes.push(make_eq_fb("--" + alt))
    }
    // alias 登録時にも eq_fallback_nodes に追加できるようファクトリを保存
    match self.node_templates.get(opt.id) {
      Some(src) =>
        self.node_templates[opt.id] = NodeTemplate::{
          make_node: src.make_node,
          is_global: src.is_global,
          make_eq_fallback: Some(make_eq_fb),
        }
      None => ()
    }
  }
  match post {
    Some(filter) =>
      self.post_hooks.push(fn() raise ParseError {
        vc.cell.val = (filter.run)(vc.cell.val)
      })
    None => ()
  }
  // env applicator でも choices バリデーションを適用する
  let env_pre : FilterChain[String, T] = if has_choices {
    Filter::one_of(choices).then(pre)
  } else {
    pre
  }
  register_env_applicator(self, env, vc, raw => (env_pre.run)(raw))
  opt
}

///|
pub fn[T] Parser::custom_append(
  self : Parser,
  name~ : String,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  pre~ : FilterChain[String, T],
) -> Opt[Array[T]] {
  let env = self.effective_env_name(env, name, visibility)
  let vc : ValCell[Array[T]] = ValCell::new(Thunk(fn() { [] }))
  let reset_fn = fn() { vc.cell.val = [] }
  let display_value_name = if value_name == "" {
    name.to_upper()
  } else {
    value_name
  }
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=description,
    value_name=display_value_name,
    default_display="",
    env_name=env,
    kind=ValueOpt,
    variations~,
    valcell=vc,
    make_main_node=fn(opt_n) {
      make_value_node(
        opt_n,
        fn(s) {
          let r : Result[T, ParseError] = try? (pre.run)(s)
          match r {
            Ok(v) => Ok(fn() { vc.cell.val.push(v) })
            Err(e) => Err(e)
          }
        },
        reset_fn,
      )
    },
    make_node_for_variation=fn(vn, v) {
      match v {
        Reset(_) | Toggle(_) | True(_) | False(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                vc.cell.val = []
                vc.committed.val = true
              }
            },
            fn() {
              vc.cell.val = []
              vc.committed.val = false
            },
          )
        Unset(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                vc.cell.val = []
                vc.committed.val = false
              }
            },
            fn() {
              vc.cell.val = []
              vc.committed.val = false
            },
          )
      }
    },
  )
  register_env_applicator(self, env, vc, raw => {
    let arr : Array[T] = []
    for part in raw.split(",") {
      arr.push((pre.run)(part.to_string()))
    }
    arr
  })
  opt
}
