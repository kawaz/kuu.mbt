///|
pub fn Parser::flag(
  self : Parser,
  name~ : String,
  default? : Bool = false,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
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
  let id = (self.next_id)()
  let cell : Ref[Bool] = { val: default }
  let initial_val = default
  let pending : Ref[Bool] = { val: default }
  let was_set : Ref[Bool] = { val: false }
  let reset_fn = fn() { cell.val = initial_val; pending.val = initial_val }
  let positive_match = fn() {
    pending.val = not(initial_val)
    fn() { cell.val = pending.val }
  }
  self.expand_and_register(
    name, aliases, short, global,
    make_long_nodes=fn(opt_name) {
      let nodes : Array[ExactNode] = []
      nodes.push(wrap_node_with_set(
        make_flag_node(opt_name, positive_match, reset_fn), was_set,
      ))
      let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
      for v in variations {
        match v {
          Toggle(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = not(cell.val); was_set.val = true }
            }, fn() { cell.val = initial_val; was_set.val = false }))
          }
          True(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = true; was_set.val = true }
            }, fn() { cell.val = initial_val; was_set.val = false }))
          }
          False(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = false; was_set.val = true }
            }, fn() { cell.val = initial_val; was_set.val = false }))
          }
          Reset(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = initial_val; was_set.val = true }
            }, fn() { cell.val = initial_val; was_set.val = false }))
          }
          Unset(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = initial_val; was_set.val = false }
            }, fn() { cell.val = initial_val; was_set.val = false }))
          }
        }
      }
      nodes
    },
    make_short_nodes=fn(short_name) {
      [wrap_node_with_set(
        make_flag_node(short_name, positive_match, reset_fn), was_set,
      )]
    },
  )
  self.metas.push(OptMeta::{
    kind: Flag,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Bool { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::string_opt(
  self : Parser,
  name~ : String,
  default~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
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
  let id = (self.next_id)()
  let cell : Ref[String] = { val: default }
  let initial_val = default
  let has_choices = choices.length() > 0
  let has_implicit = match implicit_value {
    Some(_) => true
    None => false
  }
  let was_set : Ref[Bool] = { val: false }

  // variation ノードを生成する共通ヘルパー
  fn make_variation_nodes(
    opt_name : String,
    nodes : Array[ExactNode],
  ) {
    let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
    for v in variations {
      match v {
        Reset(p) | Toggle(p) | True(p) | False(p) => {
          let vn = "--" + p + "-" + base
          nodes.push(wrap_node_with_set(
            make_flag_node(vn, fn() {
              fn() { cell.val = initial_val }
            }, fn() { cell.val = initial_val }),
            was_set,
          ))
        }
        Unset(p) => {
          let vn = "--" + p + "-" + base
          nodes.push(make_flag_node(vn, fn() {
            fn() { cell.val = initial_val; was_set.val = false }
          }, fn() { cell.val = initial_val; was_set.val = false }))
        }
      }
    }
  }

  // ケース1,3: choices+implicit or implicit only → implicit ベースの展開
  // ケース2: choices only → reducer + one_of バリデーション
  // ケース4: 既存パス (neither)
  if has_implicit {
    // ケース1 or ケース3
    let iv = match implicit_value {
      Some(v) => v
      None => Val(default) // unreachable だが型システムのため
    }
    self.expand_and_register(
      name, aliases, short, global,
      make_long_nodes=fn(opt_name) {
        let nodes : Array[ExactNode] = []
        let children : Array[ExactNode] = []
        if has_choices {
          for choice in choices {
            children.push(
              make_choice_value_node(opt_name, choice, cell, initial_val),
            )
          }
        } else {
          children.push(make_soft_value_node(opt_name, cell, initial_val))
        }
        children.push(
          make_implicit_flag_node(opt_name, iv, cell, initial_val),
        )
        let composite = make_or_node(opt_name, true, children)
        nodes.push(wrap_node_with_set(composite, was_set))
        make_variation_nodes(opt_name, nodes)
        nodes
      },
      make_short_nodes=fn(short_name) {
        let nodes : Array[ExactNode] = []
        if has_choices {
          for choice in choices {
            nodes.push(wrap_node_with_set(
              make_choice_value_node(short_name, choice, cell, initial_val),
              was_set,
            ))
          }
        } else {
          nodes.push(wrap_node_with_set(
            make_soft_value_node(short_name, cell, initial_val),
            was_set,
          ))
        }
        nodes.push(wrap_node_with_set(
          make_implicit_flag_node(short_name, iv, cell, initial_val),
          was_set,
        ))
        nodes
      },
    )
  } else if has_choices {
    // ケース2: choices only → 既存パス + one_of バリデーション
    let pending : Ref[String] = { val: default }
    let reset = fn() { cell.val = initial_val }
    let accum : Accumulator[String, String] = fn(_current, piece) { piece }
    let one_of_pre : FilterChain[String, String] = Filter::one_of(choices)
    let reducer = make_reducer(one_of_pre, accum, initial_val)
    self.expand_and_register(
      name, aliases, short, global,
      make_long_nodes=fn(opt_name) {
        let nodes : Array[ExactNode] = []
        nodes.push(wrap_node_with_set(
          make_reduced_value_node(opt_name, reducer, cell, pending, reset),
          was_set,
        ))
        make_variation_nodes(opt_name, nodes)
        nodes
      },
      make_short_nodes=fn(short_name) {
        [wrap_node_with_set(
          make_reduced_value_node(short_name, reducer, cell, pending, reset),
          was_set,
        )]
      },
    )
  } else {
    // ケース4: 既存パス (choices 空 + implicit_value なし)
    let pending : Ref[String] = { val: default }
    let reset = fn() { cell.val = initial_val }
    let accum : Accumulator[String, String] = fn(_current, piece) { piece }
    let identity_pre : FilterChain[String, String] = Filter::map(fn(s) { s })
    let reducer = make_reducer(identity_pre, accum, initial_val)
    self.expand_and_register(
      name, aliases, short, global,
      make_long_nodes=fn(opt_name) {
        let nodes : Array[ExactNode] = []
        nodes.push(wrap_node_with_set(
          make_reduced_value_node(opt_name, reducer, cell, pending, reset),
          was_set,
        ))
        make_variation_nodes(opt_name, nodes)
        nodes
      },
      make_short_nodes=fn(short_name) {
        [wrap_node_with_set(
          make_reduced_value_node(short_name, reducer, cell, pending, reset),
          was_set,
        )]
      },
    )
  }
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  let display_default = default
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: display_default,
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  match post {
    Some(filter) =>
      self.post_hooks.push(fn() raise ParseError {
        cell.val = (filter.run)(cell.val)
      })
    None => ()
  }
  {
    id,
    name: "--" + name,
    getter: fn() -> String { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::int_opt(
  self : Parser,
  name~ : String,
  default~ : Int,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
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
  let id = (self.next_id)()
  let cell : Ref[Int] = { val: default }
  let initial_val = default
  let has_implicit = match implicit_value {
    Some(_) => true
    None => false
  }
  let was_set : Ref[Bool] = { val: false }

  // variation ノードを生成する共通ヘルパー
  fn make_variation_nodes(
    opt_name : String,
    nodes : Array[ExactNode],
  ) {
    let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
    for v in variations {
      match v {
        Reset(p) | Toggle(p) | True(p) | False(p) => {
          let vn = "--" + p + "-" + base
          nodes.push(wrap_node_with_set(
            make_flag_node(vn, fn() {
              fn() { cell.val = initial_val }
            }, fn() { cell.val = initial_val }),
            was_set,
          ))
        }
        Unset(p) => {
          let vn = "--" + p + "-" + base
          nodes.push(make_flag_node(vn, fn() {
            fn() { cell.val = initial_val; was_set.val = false }
          }, fn() { cell.val = initial_val; was_set.val = false }))
        }
      }
    }
  }

  if has_implicit {
    // implicit_value あり
    let iv = match implicit_value {
      Some(v) => v
      None => Val(default) // unreachable
    }
    // int パースを試み、失敗時は Reject を返す soft value node
    fn make_soft_int_value_node(
      opt_n : String,
      cell : Ref[Int],
      initial_val : Int,
    ) -> ExactNode {
      ExactNode::{
        name: opt_n,
        needs_value: true,
        try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
          if pos >= args.length() || args[pos] != opt_n {
            return Reject
          }
          if pos + 1 >= args.length() {
            return Reject
          }
          let s = args[pos + 1]
          let r : Result[Int, _] = try? @strconv.parse_int(s.view())
          match r {
            Ok(v) =>
              Accept(consumed=2, commit=fn() {
                cell.val = v
              })
            Err(_) => Reject // int パース失敗 → Reject（implicit にフォールバック）
          }
        },
        reset: fn() {
          cell.val = initial_val
        },
      }
    }

    self.expand_and_register(
      name, aliases, short, global,
      make_long_nodes=fn(opt_name) {
        let nodes : Array[ExactNode] = []
        let children : Array[ExactNode] = []
        children.push(
          make_soft_int_value_node(opt_name, cell, initial_val),
        )
        children.push(
          make_implicit_flag_node(opt_name, iv, cell, initial_val),
        )
        let composite = make_or_node(opt_name, true, children)
        nodes.push(wrap_node_with_set(composite, was_set))
        make_variation_nodes(opt_name, nodes)
        nodes
      },
      make_short_nodes=fn(short_name) {
        let nodes : Array[ExactNode] = []
        nodes.push(wrap_node_with_set(
          make_soft_int_value_node(short_name, cell, initial_val),
          was_set,
        ))
        nodes.push(wrap_node_with_set(
          make_implicit_flag_node(short_name, iv, cell, initial_val),
          was_set,
        ))
        nodes
      },
    )
  } else {
    // implicit_value なし: 既存パス
    let pending : Ref[Int] = { val: default }
    let reset = fn() { cell.val = initial_val }
    let accum : Accumulator[Int, Int] = fn(_current, piece) { piece }
    fn make_int_pre(opt_n : String) -> FilterChain[String, Int] {
      Filter::parse(fn(s) raise ParseError {
        let r : Result[Int, _] = try? @strconv.parse_int(s.view())
        match r {
          Ok(v) => v
          Err(_) =>
            raise parse_error(
              "invalid integer value for " + opt_n + ": " + s,
            )
        }
      })
    }

    self.expand_and_register(
      name, aliases, short, global,
      make_long_nodes=fn(opt_name) {
        let nodes : Array[ExactNode] = []
        let this_reducer = make_reducer(
          make_int_pre(opt_name), accum, initial_val,
        )
        nodes.push(wrap_node_with_set(
          make_reduced_value_node(opt_name, this_reducer, cell, pending, reset),
          was_set,
        ))
        make_variation_nodes(opt_name, nodes)
        nodes
      },
      make_short_nodes=fn(short_name) {
        let short_reducer = make_reducer(
          make_int_pre(short_name), accum, initial_val,
        )
        [wrap_node_with_set(
          make_reduced_value_node(
            short_name, short_reducer, cell, pending, reset,
          ),
          was_set,
        )]
      },
    )
  }
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  let display_default = if default == 0 { "" } else { default.to_string() }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: display_default,
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Int { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::append_string(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
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
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  let was_set : Ref[Bool] = { val: false }
  let reset_fn = fn() { cell.val = [] }
  let make_main = fn(opt_n : String) -> ExactNode {
    make_value_node(opt_n, fn(s) { Ok(fn() { cell.val.push(s) }) }, reset_fn)
  }
  self.expand_and_register(
    name, aliases, short, global,
    make_long_nodes=fn(opt_name) {
      let nodes : Array[ExactNode] = []
      nodes.push(wrap_node_with_set(make_main(opt_name), was_set))
      let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
      for v in variations {
        match v {
          Reset(p) | Toggle(p) | True(p) | False(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = []; was_set.val = true }
            }, fn() { cell.val = []; was_set.val = false }))
          }
          Unset(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = []; was_set.val = false }
            }, fn() { cell.val = []; was_set.val = false }))
          }
        }
      }
      nodes
    },
    make_short_nodes=fn(short_name) {
      [wrap_node_with_set(make_main(short_name), was_set)]
    },
  )
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Array[String] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::append_int(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
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
  let id = (self.next_id)()
  let cell : Ref[Array[Int]] = { val: [] }
  let was_set : Ref[Bool] = { val: false }
  let reset_fn = fn() { cell.val = [] }
  let make_main = fn(opt_n : String) -> ExactNode {
    make_value_node(
      opt_n,
      fn(s) {
        let r : Result[Int, _] = try? @strconv.parse_int(s.view())
        match r {
          Ok(v) => Ok(fn() { cell.val.push(v) })
          Err(_) =>
            Err(parse_error("invalid integer value for " + opt_n + ": " + s))
        }
      },
      reset_fn,
    )
  }
  self.expand_and_register(
    name, aliases, short, global,
    make_long_nodes=fn(opt_name) {
      let nodes : Array[ExactNode] = []
      nodes.push(wrap_node_with_set(make_main(opt_name), was_set))
      let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
      for v in variations {
        match v {
          Reset(p) | Toggle(p) | True(p) | False(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = []; was_set.val = true }
            }, fn() { cell.val = []; was_set.val = false }))
          }
          Unset(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              fn() { cell.val = []; was_set.val = false }
            }, fn() { cell.val = []; was_set.val = false }))
          }
        }
      }
      nodes
    },
    make_short_nodes=fn(short_name) {
      [wrap_node_with_set(make_main(short_name), was_set)]
    },
  )
  let display_value_name = if value_name == "" {
    to_upper(name)
  } else {
    value_name
  }
  self.metas.push(OptMeta::{
    kind: ValueOpt,
    name,
    help: description,
    value_name: display_value_name,
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Array[Int] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::count(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  short? : Char = '\u0000',
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
  let id = (self.next_id)()
  let cell : Ref[Int] = { val: 0 }
  let pending : Ref[Int] = { val: 0 }
  let was_set : Ref[Bool] = { val: false }
  let reset_fn = fn() { cell.val = 0; pending.val = 0 }
  let positive_match = fn() {
    pending.val = pending.val + 1
    fn() { cell.val = pending.val }
  }
  self.expand_and_register(
    name, aliases, short, global,
    make_long_nodes=fn(opt_name) {
      let nodes : Array[ExactNode] = []
      nodes.push(wrap_node_with_set(
        make_flag_node(opt_name, positive_match, reset_fn), was_set,
      ))
      let base = opt_name.unsafe_substring(start=2, end=opt_name.length())
      for v in variations {
        match v {
          Reset(p) | Toggle(p) | True(p) | False(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              pending.val = 0
              fn() { cell.val = pending.val; was_set.val = true }
            }, fn() { cell.val = 0; pending.val = 0; was_set.val = false }))
          }
          Unset(p) => {
            let vn = "--" + p + "-" + base
            nodes.push(make_flag_node(vn, fn() {
              pending.val = 0
              fn() { cell.val = pending.val; was_set.val = false }
            }, fn() { cell.val = 0; pending.val = 0; was_set.val = false }))
          }
        }
      }
      nodes
    },
    make_short_nodes=fn(short_name) {
      [wrap_node_with_set(
        make_flag_node(short_name, positive_match, reset_fn), was_set,
      )]
    },
  )
  self.metas.push(OptMeta::{
    kind: Flag,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global,
    short: if short != '\u0000' {
      Some(short)
    } else {
      None
    },
    aliases,
    hidden,
  })
  {
    id,
    name: "--" + name,
    getter: fn() -> Int { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}
