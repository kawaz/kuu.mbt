///| Registers a positional argument.
/// `greedy` — if true, consumed eagerly during OC phase (before option matching completes);
/// if false (default), deferred to P phase and receives unclaimed args.
pub fn Parser::positional(
  self : Parser,
  name~ : String,
  description? : String = "",
  greedy~ : Bool = false,
) -> Opt[String] {
  let id = (self.next_id)()
  let vc : ValCell[String] = ValCell::new(Val(""))
  let pending : Ref[String] = { val: "" }
  ignore(name)
  let handler : (Array[String], Int) -> TryResult = fn(
    args : Array[String],
    pos : Int,
  ) -> TryResult {
    if pos >= args.length() {
      Reject
    } else {
      pending.val = args[pos]
      Accept(consumed=1, commit=fn() {
        vc.cell.val = pending.val
        vc.committed.val = true
      })
    }
  }
  self.positionals.push(PositionalEntry::{ handler, is_rest: false, greedy })
  self.metas.push(OptMeta::{
    kind: Positional,
    name,
    help: description,
    value_name: "",
    default_display: "",
    env_name: "",
    global: false,
    shorts: [],
    aliases: [],
    variation_names: [],
    hidden: false,
  })
  { id, name, accessor: vc.accessor(), parsed: self.parsed, used: fn() { vc.committed.val } }
}

///|
pub fn Parser::rest(
  self : Parser,
  name~ : String,
  description? : String = "",
  stop_before? : Array[String] = [],
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let vc : ValCell[Array[String]] = ValCell::new(Thunk(fn() { [] }))
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
      if stop.contains(value) {
        return Reject
      }
      Accept(consumed=1, commit=fn() {
        vc.cell.val.push(value)
        vc.committed.val = true
      })
    }
  }
  self.positionals.push(PositionalEntry::{ handler, is_rest: true, greedy: false })
  self.metas.push(OptMeta::{
    kind: Rest,
    name,
    help: description,
    value_name: "",
    default_display: "",
    env_name: "",
    global: false,
    shorts: [],
    aliases: [],
    variation_names: [],
    hidden: false,
  })
  { id, name, accessor: vc.accessor(), parsed: self.parsed, used: fn() { vc.committed.val } }
}

///|
pub fn Parser::never(self : Parser) -> Unit {
  let registered_names = self.registered_names
  let handler : (Array[String], Int) -> TryResult = fn(args, pos) {
    if pos < args.length() {
      let arg = args[pos]
      Error(
        parse_error(
          format_unexpected_with_hint(arg, registered_names),
          kind=if arg.has_prefix("-") { UnknownOption } else { UnexpectedArgument },
          opt_name=arg,
        ),
      )
    } else {
      Reject
    }
  }
  self.positionals.push(PositionalEntry::{ handler, is_rest: false, greedy: false })
}

///| Groups multiple positionals into a compound handler that consumes them sequentially.
/// `greedy` — if true, the compound handler runs during OC phase; note that it consumes
/// args without considering ExactNode matching, so option-like args may be consumed as values.
pub fn Parser::serial(
  self : Parser,
  setup~ : (Parser) -> Unit,
  greedy~ : Bool = false,
) -> Unit {
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
    registered_names: {},
    duplicate_errors: [],
    force_unclaimed: [],
    node_templates: Map::new(),
    eq_fallback_nodes: [],
    deprecated_usages: [],
    env_applicators: [],
    env_map: { val: {} },
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
      let entry = sub_positionals[next_pos_idx]
      match (entry.handler)(args, p) {
        Accept(consumed~, commit~) => {
          commits.push(commit)
          if not(entry.is_rest) {
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
    sub_positionals[sub_positionals.length() - 1].is_rest
  self.positionals.push(PositionalEntry::{ handler, is_rest: has_rest, greedy })
}
