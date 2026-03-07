///|
pub fn Parser::positional(
  self : Parser,
  name~ : String,
  description? : String = "",
) -> Opt[String] {
  let id = (self.next_id)()
  let cell : Ref[String] = { val: "" }
  let pending : Ref[String] = { val: "" }
  let was_set : Ref[Bool] = { val: false }
  ignore(name)
  let handler : (Array[String], Int) -> TryResult = fn(
    args : Array[String],
    pos : Int,
  ) -> TryResult {
    if pos >= args.length() {
      Reject
    } else if args[pos].has_prefix("--") {
      Reject
    } else {
      pending.val = args[pos]
      Accept(consumed=1, commit=fn() {
        cell.val = pending.val
        was_set.val = true
      })
    }
  }
  self.positionals.push((handler, false))
  self.metas.push(OptMeta::{
    kind: Positional,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global: false,
    short: None,
    aliases: [],
    hidden: false,
  })
  {
    id,
    name,
    getter: fn() -> String { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::rest(
  self : Parser,
  name~ : String,
  description? : String = "",
  stop_before? : Array[String] = [],
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  let was_set : Ref[Bool] = { val: false }
  ignore(name)
  let stop = stop_before
  let handler : (Array[String], Int) -> TryResult = fn(
    args : Array[String],
    pos : Int,
  ) -> TryResult {
    if pos >= args.length() {
      Reject
    } else {
      let value = args[pos]
      for token in stop {
        if value == token {
          return Reject
        }
      }
      Accept(consumed=1, commit=fn() {
        cell.val.push(value)
        was_set.val = true
      })
    }
  }
  self.positionals.push((handler, true))
  self.metas.push(OptMeta::{
    kind: Rest,
    name,
    help: description,
    value_name: "",
    default_display: "",
    global: false,
    short: None,
    aliases: [],
    hidden: false,
  })
  {
    id,
    name,
    getter: fn() -> Array[String] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::never(self : Parser) -> Unit {
  let handler : (Array[String], Int) -> TryResult = fn(args, pos) {
    if pos < args.length() {
      Error(parse_error("unexpected argument: " + args[pos]))
    } else {
      Reject
    }
  }
  self.positionals.push((handler, false))
}

///|
pub fn Parser::serial(self : Parser, setup~ : (Parser) -> Unit) -> Unit {
  // serial 用の軽量 sub-parser を直接構築（Parser::new は --help 等を登録してしまうため）
  let sub : Parser = {
    next_id: self.next_id, // 親と ID 空間共有
    nodes: [],
    global_nodes: [],
    positionals: [],
    current_positional: { val: 0 },
    parsed: self.parsed, // 親と parsed 共有
    children: Map::new(),
    metas: [],
    description: { val: "" },
    post_hooks: [],
  }
  setup(sub)
  // sub.positionals を greedy な compound handler にまとめる。
  // 1回の呼び出しで sub 内の全 positional を可能な限り消費する。
  let sub_positionals = sub.positionals
  let sub_current : Ref[Int] = { val: 0 }
  let handler : (Array[String], Int) -> TryResult = fn(args, pos) {
    if sub_current.val >= sub_positionals.length() {
      return Reject
    }
    let mut p = pos
    let commits : Array[() -> Unit] = []
    let mut next_pos_idx = sub_current.val
    while p < args.length() && next_pos_idx < sub_positionals.length() {
      let (sub_handler, is_rest) = sub_positionals[next_pos_idx]
      match sub_handler(args, p) {
        Accept(consumed~, commit~) => {
          commits.push(commit)
          if not(is_rest) {
            next_pos_idx += 1
          }
          p += consumed
        }
        Reject => break
        Error(e) => return Error(e)
      }
    }
    if p == pos {
      // 1つも消費できなかった
      return Reject
    }
    let final_pos_idx = next_pos_idx
    Accept(consumed=p - pos, commit=fn() {
      for c in commits {
        c()
      }
      sub_current.val = final_pos_idx
    })
  }
  // sub の中に rest がある場合、serial 全体を is_rest=true にする
  // （rest がなくても serial は greedy に全消費するので通常 is_rest=false でよい）
  let has_rest = sub_positionals.length() > 0 &&
    sub_positionals[sub_positionals.length() - 1].1
  self.positionals.push((handler, has_rest))
}
