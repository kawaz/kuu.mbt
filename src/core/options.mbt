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
  hidden? : Bool = false,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Bool] {
  // Sugar params → variations に追加
  if variation_toggle is Some(p) { variations.push(Toggle(p)) }
  if variation_true is Some(p) { variations.push(True(p)) }
  if variation_false is Some(p) { variations.push(False(p)) }
  if variation_reset is Some(p) { variations.push(Reset(p)) }
  if variation_unset is Some(p) { variations.push(Unset(p)) }
  // default_fn があれば default を上書き
  let initial_val = match default_fn {
    Some(f) => f()
    None => default
  }
  let cell : Ref[Bool] = { val: initial_val }
  let pending : Ref[Bool] = { val: initial_val }
  let was_set : Ref[Bool] = { val: false }
  let reset_fn = fn() { cell.val = initial_val; pending.val = initial_val }
  let positive_match = fn() {
    pending.val = not(initial_val)
    fn() { cell.val = pending.val }
  }
  self.register_option(
    name~, aliases~, shorts~, global~, hidden~,
    help=description, value_name="", default_display="",
    kind=Flag, variations~, was_set~,
    make_main_node=fn(n) { make_flag_node(n, positive_match, reset_fn) },
    make_node_for_variation=fn(vn, v) {
      match v {
        Toggle(_) =>
          make_flag_node(vn, fn() {
            fn() { cell.val = not(cell.val); was_set.val = true }
          }, fn() { cell.val = initial_val; was_set.val = false })
        True(_) =>
          make_flag_node(vn, fn() {
            fn() { cell.val = true; was_set.val = true }
          }, fn() { cell.val = initial_val; was_set.val = false })
        False(_) =>
          make_flag_node(vn, fn() {
            fn() { cell.val = false; was_set.val = true }
          }, fn() { cell.val = initial_val; was_set.val = false })
        Reset(_) =>
          make_flag_node(vn, fn() {
            fn() { cell.val = initial_val; was_set.val = true }
          }, fn() { cell.val = initial_val; was_set.val = false })
        Unset(_) =>
          make_flag_node(vn, fn() {
            fn() { cell.val = initial_val; was_set.val = false }
          }, fn() { cell.val = initial_val; was_set.val = false })
      }
    },
    getter=fn() { cell.val },
  )
}

///|
pub fn Parser::string_opt(
  self : Parser,
  name~ : String,
  default~ : String,
  default_fn? : (() -> String)? = None,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
  post? : FilterChain[String, String]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[String]? = None,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[String] {
  // Sugar params → variations に追加
  if variation_toggle is Some(p) { variations.push(Toggle(p)) }
  if variation_true is Some(p) { variations.push(True(p)) }
  if variation_false is Some(p) { variations.push(False(p)) }
  if variation_reset is Some(p) { variations.push(Reset(p)) }
  if variation_unset is Some(p) { variations.push(Unset(p)) }
  self.custom(
    name~, aliases~, shorts~, global~, hidden~, variations~,
    help=description, value_name~,
    default~, default_fn~, post~, choices~, implicit_value~,
    pre=Filter::map(fn(s) { s }),
  )
}

///|
pub fn Parser::int_opt(
  self : Parser,
  name~ : String,
  default~ : Int,
  default_fn? : (() -> Int)? = None,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
  implicit_value? : Lazy[Int]? = None,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Int] {
  // Sugar params → variations に追加
  if variation_toggle is Some(p) { variations.push(Toggle(p)) }
  if variation_true is Some(p) { variations.push(True(p)) }
  if variation_false is Some(p) { variations.push(False(p)) }
  if variation_reset is Some(p) { variations.push(Reset(p)) }
  if variation_unset is Some(p) { variations.push(Unset(p)) }
  self.custom(
    name~, aliases~, shorts~, global~, hidden~, variations~,
    help=description, value_name~,
    default~, default_fn~, implicit_value~,
    pre=Filter::parse_int(),
  )
}

///|
pub fn Parser::append_string(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Array[String]] {
  // Sugar params → variations に追加
  if variation_toggle is Some(p) { variations.push(Toggle(p)) }
  if variation_true is Some(p) { variations.push(True(p)) }
  if variation_false is Some(p) { variations.push(False(p)) }
  if variation_reset is Some(p) { variations.push(Reset(p)) }
  if variation_unset is Some(p) { variations.push(Unset(p)) }
  self.custom_append(
    name~, aliases~, shorts~, global~, hidden~, variations~,
    help=description, value_name~,
    pre=Filter::map(fn(s) { s }),
  )
}

///|
pub fn Parser::append_int(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Array[Int]] {
  // Sugar params → variations に追加
  if variation_toggle is Some(p) { variations.push(Toggle(p)) }
  if variation_true is Some(p) { variations.push(True(p)) }
  if variation_false is Some(p) { variations.push(False(p)) }
  if variation_reset is Some(p) { variations.push(Reset(p)) }
  if variation_unset is Some(p) { variations.push(Unset(p)) }
  self.custom_append(
    name~, aliases~, shorts~, global~, hidden~, variations~,
    help=description, value_name~,
    pre=Filter::parse_int(),
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
  hidden? : Bool = false,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Int] {
  // Sugar params → variations に追加
  if variation_toggle is Some(p) { variations.push(Toggle(p)) }
  if variation_true is Some(p) { variations.push(True(p)) }
  if variation_false is Some(p) { variations.push(False(p)) }
  if variation_reset is Some(p) { variations.push(Reset(p)) }
  if variation_unset is Some(p) { variations.push(Unset(p)) }
  let cell : Ref[Int] = { val: 0 }
  let pending : Ref[Int] = { val: 0 }
  let was_set : Ref[Bool] = { val: false }
  let reset_fn = fn() { cell.val = 0; pending.val = 0 }
  let positive_match = fn() {
    pending.val = pending.val + 1
    fn() { cell.val = pending.val }
  }
  self.register_option(
    name~, aliases~, shorts~, global~, hidden~,
    help=description, value_name="", default_display="",
    kind=Flag, variations~, was_set~,
    make_main_node=fn(n) { make_flag_node(n, positive_match, reset_fn) },
    make_node_for_variation=fn(vn, v) {
      match v {
        Reset(_) | Toggle(_) | True(_) | False(_) =>
          make_flag_node(vn, fn() {
            pending.val = 0
            fn() { cell.val = pending.val; was_set.val = true }
          }, fn() { cell.val = 0; pending.val = 0; was_set.val = false })
        Unset(_) =>
          make_flag_node(vn, fn() {
            pending.val = 0
            fn() { cell.val = pending.val; was_set.val = false }
          }, fn() { cell.val = 0; pending.val = 0; was_set.val = false })
      }
    },
    getter=fn() { cell.val },
  )
}

///|
pub fn[T : Show] Parser::custom(
  self : Parser,
  name~ : String,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  help? : String = "",
  value_name? : String = "",
  default_display? : String? = None,
  hidden? : Bool = false,
  variations? : Array[Variation] = [],
  default~ : T,
  default_fn? : (() -> T)? = None,
  pre~ : FilterChain[String, T],
  post? : FilterChain[T, T]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[T]? = None,
) -> Opt[T] {
  let initial_val = match default_fn {
    Some(f) => f()
    None => default
  }
  let effective_display = match default_display {
    Some(s) => s
    None => initial_val.to_string()
  }
  let cell : Ref[T] = { val: initial_val }
  let was_set : Ref[Bool] = { val: false }
  let has_choices = choices.length() > 0
  let has_implicit = match implicit_value {
    Some(_) => true
    None => false
  }

  // variation ノード: Toggle/True/False は Reset 相当にフォールバック（値コンビネータに Bool 反転の意味論なし）
  let make_var_node = fn(vn : String, v : Variation) -> ExactNode {
    match v {
      Reset(_) | Toggle(_) | True(_) | False(_) =>
        wrap_node_with_set(
          make_flag_node(vn, fn() {
            fn() { cell.val = initial_val }
          }, fn() { cell.val = initial_val }),
          was_set,
        )
      Unset(_) =>
        make_flag_node(vn, fn() {
          fn() { cell.val = initial_val; was_set.val = false }
        }, fn() { cell.val = initial_val; was_set.val = false })
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
            make_custom_choice_value_node(opt_name, choice, pre, cell, initial_val),
          )
        }
      } else {
        children.push(make_soft_custom_value_node(opt_name, pre, cell, initial_val))
      }
      children.push(make_implicit_flag_node(opt_name, iv, cell, initial_val))
      make_or_node(opt_name, true, children)
    }
  } else {
    let pending : Ref[T] = { val: initial_val }
    let reset = fn() { cell.val = initial_val }
    let accum : Accumulator[T, T] = fn(_current, piece) { piece }
    // choices がある場合は one_of → pre の合成。FilterChain::then で Kleisli composition
    let effective_pre : FilterChain[String, T] = if has_choices {
      Filter::one_of(choices).then(pre)
    } else {
      pre
    }
    let reducer = make_reducer(effective_pre, accum, initial_val)
    fn(opt_name : String) -> ExactNode {
      make_reduced_value_node(opt_name, reducer, cell, pending, reset)
    }
  }

  let display_value_name = if value_name == "" { to_upper(name) } else { value_name }
  let opt = self.register_option(
    name~, aliases~, shorts~, global~, hidden~,
    help~, value_name=display_value_name, default_display=effective_display,
    kind=ValueOpt, variations~, was_set~,
    make_main_node=make_main,
    make_node_for_variation=make_var_node,
    getter=fn() { cell.val },
  )
  match post {
    Some(filter) =>
      self.post_hooks.push(fn() raise ParseError {
        cell.val = (filter.run)(cell.val)
      })
    None => ()
  }
  opt
}

///|
pub fn[T] Parser::custom_append(
  self : Parser,
  name~ : String,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  help? : String = "",
  value_name? : String = "",
  hidden? : Bool = false,
  variations? : Array[Variation] = [],
  pre~ : FilterChain[String, T],
) -> Opt[Array[T]] {
  let cell : Ref[Array[T]] = { val: [] }
  let was_set : Ref[Bool] = { val: false }
  let reset_fn = fn() { cell.val = [] }
  let display_value_name = if value_name == "" { to_upper(name) } else { value_name }
  self.register_option(
    name~, aliases~, shorts~, global~, hidden~,
    help~, value_name=display_value_name, default_display="",
    kind=ValueOpt, variations~, was_set~,
    make_main_node=fn(opt_n) {
      make_value_node(
        opt_n,
        fn(s) {
          let r : Result[T, ParseError] = try? (pre.run)(s)
          match r {
            Ok(v) => Ok(fn() { cell.val.push(v) })
            Err(e) => Err(e)
          }
        },
        reset_fn,
      )
    },
    make_node_for_variation=fn(vn, v) {
      match v {
        Reset(_) | Toggle(_) | True(_) | False(_) =>
          make_flag_node(vn, fn() {
            fn() { cell.val = []; was_set.val = true }
          }, fn() { cell.val = []; was_set.val = false })
        Unset(_) =>
          make_flag_node(vn, fn() {
            fn() { cell.val = []; was_set.val = false }
          }, fn() { cell.val = []; was_set.val = false })
      }
    },
    getter=fn() { cell.val },
  )
}
