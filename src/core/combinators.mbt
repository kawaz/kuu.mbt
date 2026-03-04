///|
/// flag コンビネータ: Bool フラグオプションを作成する
pub fn Parser::flag(
  self : Parser,
  name~ : String,
  help? : String = "",
  shorts? : Array[ShortEntry] = [],
  aliases? : Array[AliasEntry] = [],
  inversion? : FlagInversion? = None,
  env? : String? = None,
  auto_env? : Bool? = None,
  visibility? : Visibility = Visible,
  global? : Bool = false,
  greedy? : Bool = false,
) -> Opt[Bool] {
  let id = self.next_id()
  let store : Ref[Bool] = Ref::new(false)
  let meta = OptMeta::{
    name,
    kind: Kind::Option,
    help,
    shorts,
    aliases,
    inversion,
    env,
    auto_env,
    choices: [],
    value_name: "",
    required: false,
    visibility,
    global,
    greedy,
  }
  {
    id,
    initial: Val(false),
    reducer: fn(ctx) {
      match ctx.action {
        Value(None) => Some(true)
        Negate => Some(false)
        _ => None
      }
    },
    meta,
    getter: fn(_instance_id) { store.val },
    setter: fn(_instance_id, val) { store.val = val },
    children_opts: Opts::Array([]),
  }
}

///|
/// string コンビネータ: String オプションを作成する
pub fn Parser::string(
  self : Parser,
  name~ : String,
  help? : String = "",
  shorts? : Array[ShortEntry] = [],
  aliases? : Array[AliasEntry] = [],
  env? : String? = None,
  auto_env? : Bool? = None,
  choices? : Array[String] = [],
  value_name? : String = "STRING",
  required? : Bool = false,
  visibility? : Visibility = Visible,
  global? : Bool = false,
) -> Opt[String?] {
  let id = self.next_id()
  let store : Ref[String?] = Ref::new(None)
  let meta = OptMeta::{
    name,
    kind: Kind::Option,
    help,
    shorts,
    aliases,
    inversion: None,
    env,
    auto_env,
    choices,
    value_name,
    required,
    visibility,
    global,
    greedy: false,
  }
  {
    id,
    initial: Val(None),
    reducer: fn(ctx) {
      match ctx.action {
        Value(Some(s)) => Some(Some(s))
        Negate => Some(None)
        _ => None
      }
    },
    meta,
    getter: fn(_instance_id) { store.val },
    setter: fn(_instance_id, val) { store.val = val },
    children_opts: Opts::Array([]),
  }
}

///|
/// int コンビネータ: Int オプションを作成する
pub fn Parser::int(
  self : Parser,
  name~ : String,
  help? : String = "",
  shorts? : Array[ShortEntry] = [],
  aliases? : Array[AliasEntry] = [],
  env? : String? = None,
  auto_env? : Bool? = None,
  choices? : Array[String] = [],
  value_name? : String = "INT",
  required? : Bool = false,
  visibility? : Visibility = Visible,
  global? : Bool = false,
) -> Opt[Int?] {
  let id = self.next_id()
  let store : Ref[Int?] = Ref::new(None)
  let meta = OptMeta::{
    name,
    kind: Kind::Option,
    help,
    shorts,
    aliases,
    inversion: None,
    env,
    auto_env,
    choices,
    value_name,
    required,
    visibility,
    global,
    greedy: false,
  }
  {
    id,
    initial: Val(None),
    reducer: fn(ctx) raise {
      match ctx.action {
        Value(Some(s)) => {
          let n = @strconv.parse_int(s[:]) catch {
            _ =>
              raise ParseError::Usage(
                ErrorKind::InvalidValue,
                "invalid integer: " + s,
                ErrorContext::{ option_name: name },
              )
          }
          Some(Some(n))
        }
        Negate => Some(None)
        _ => None
      }
    },
    meta,
    getter: fn(_instance_id) { store.val },
    setter: fn(_instance_id, val) { store.val = val },
    children_opts: Opts::Array([]),
  }
}

///|
/// positional コンビネータ: 位置パラメータを作成する
pub fn Parser::positional(
  self : Parser,
  name~ : String,
  help? : String = "",
  value_name? : String = "",
  required? : Bool = true,
  visibility? : Visibility = Visible,
) -> Opt[String?] {
  let id = self.next_id()
  let store : Ref[String?] = Ref::new(None)
  let actual_value_name = if value_name == "" {
    name.to_upper()
  } else {
    value_name
  }
  let meta = OptMeta::{
    name,
    kind: Kind::Positional,
    help,
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: actual_value_name,
    required,
    visibility,
    global: false,
    greedy: false,
  }
  {
    id,
    initial: Val(None),
    reducer: fn(ctx) {
      match ctx.action {
        Value(Some(s)) => Some(Some(s))
        _ => None
      }
    },
    meta,
    getter: fn(_instance_id) { store.val },
    setter: fn(_instance_id, val) { store.val = val },
    children_opts: Opts::Array([]),
  }
}

///|
/// cmd コンビネータ: サブコマンドを作成する
pub fn Parser::cmd(
  self : Parser,
  name~ : String,
  help? : String = "",
  aliases? : Array[AliasEntry] = [],
  visibility? : Visibility = Visible,
  children~ : Opts,
) -> Opt[Bool] {
  let id = self.next_id()
  let store : Ref[Bool] = Ref::new(false)
  let meta = OptMeta::{
    name,
    kind: Kind::Command,
    help,
    shorts: [],
    aliases,
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "",
    required: false,
    visibility,
    global: false,
    greedy: false,
  }
  {
    id,
    initial: Val(false),
    reducer: fn(ctx) {
      match ctx.action {
        Value(None) => Some(true)
        _ => None
      }
    },
    meta,
    getter: fn(_instance_id) { store.val },
    setter: fn(_instance_id, val) { store.val = val },
    children_opts: children,
  }
}

///|
/// Opts を再帰的に展開して Array[ErasedNode] に変換する
pub fn opts_to_erased_nodes(o : Opts) -> Array[ErasedNode] {
  match o {
    Node(n) => [n]
    Array(items) => {
      let result : Array[ErasedNode] = []
      for item in items {
        for node in opts_to_erased_nodes(item) {
          result.push(node)
        }
      }
      result
    }
  }
}

///|
/// Opt[T] を Opts::Node に変換する
pub fn[T] Opt::to_opts(self : Opt[T]) -> Opts {
  let initial_val = match self.initial {
    Val(v) => v
    Thunk(f) => f()
  }
  let store_getter = self.getter
  let store_setter = self.setter
  let reducer = self.reducer
  let children_opts = self.children_opts
  let committed : Ref[Bool] = Ref::new(false)
  Opts::Node(ErasedNode::{
    meta: self.meta,
    try_reduce: fn(action, _result_map) {
      let current = store_getter(0)
      let ctx = ReduceCtx::{ current, action }
      try {
        match reducer(ctx) {
          Some(v) => {
            // 書き込まない。ReduceResult に封じ込める
            Accept(
              consumed=1,
              result=ReduceResult::{ commit: fn() { store_setter(0, v) } },
            )
          }
          None => Reject
        }
      } catch {
        ParseError::Usage(kind, msg, ctx) =>
          Error(ParseError::Usage(kind, msg, ctx))
        ParseError::Internal(msg) => Error(ParseError::Internal(msg))
        _ => Error(ParseError::Internal("unexpected error in reducer"))
      }
    },
    commit_reduce: fn(result, _result_map) {
      (result.commit)()
      committed.val = true
    },
    reset_to_initial: fn(_result_map) {
      store_setter(0, initial_val)
      committed.val = false
    },
    is_set: fn() { committed.val },
    children: fn() { opts_to_erased_nodes(children_opts) },
  })
}

///|
/// opts ヘルパー: Array[Opts] を Opts::Array にラップする
pub fn opts(items : Array[Opts]) -> Opts {
  Opts::Array(items)
}
