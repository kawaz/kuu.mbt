///|
/// Registers a positional argument (unnamed, position-based).
///
/// Positional arguments are consumed in the order they are registered.
/// By default they are collected in the P (Positional) phase after all
/// named options have been processed.
///
/// Parameters:
/// - `name` - Identifier for this positional (used in help text and error messages)
/// - `description` - Help text shown in `--help` output
/// - `greedy` - If true, consumed eagerly during OC phase (before option
///   matching completes); if false (default), deferred to P phase
///
/// Returns an `Opt[String]` with the captured positional value.
///
/// Example:
/// ```
/// let input = parser.positional(name="input", description="Input file")
/// parser.parse!(["myfile.txt"])
/// assert_eq!(input.get(), Some("myfile.txt"))
/// ```
pub fn Parser::positional(
  self : Parser,
  name~ : String,
  description? : String = "",
  greedy? : Bool = false,
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
    visibility: Visible,
  })
  {
    id,
    name,
    accessor: vc.accessor(),
    parsed: self.parsed,
    used: fn() { vc.committed.val },
  }
}

///|
/// Registers a rest-args collector that captures all remaining positional arguments.
///
/// Unlike `positional` which captures a single value, `rest` greedily
/// consumes all remaining unclaimed arguments into an array.
///
/// Parameters:
/// - `name` - Identifier for this rest collector (used in help/errors)
/// - `description` - Help text shown in `--help` output
/// - `stop_before` - Stop collecting when one of these values is encountered
///
/// Returns an `Opt[Array[String]]` containing all collected values.
///
/// Example:
/// ```
/// let files = parser.rest(name="files", description="Input files")
/// parser.parse!(["a.txt", "b.txt", "c.txt"])
/// assert_eq!(files.get(), Some(["a.txt", "b.txt", "c.txt"]))
/// ```
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
  self.positionals.push(PositionalEntry::{
    handler,
    is_rest: true,
    greedy: false,
  })
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
    visibility: Visible,
  })
  {
    id,
    name,
    accessor: vc.accessor(),
    parsed: self.parsed,
    used: fn() { vc.committed.val },
  }
}

///|
pub fn Parser::never(self : Parser) -> Unit {
  let registered_names = self.registered_names
  let handler : (Array[String], Int) -> TryResult = fn(args, pos) {
    if pos < args.length() {
      let arg = args[pos]
      let (msg, tip) = format_unexpected_with_hint(arg, registered_names)
      Error(
        parse_error(
          msg,
          kind=if arg.has_prefix("-") {
            UnknownOption
          } else {
            UnexpectedArgument
          },
          opt_name=arg,
          tip~,
        ),
      )
    } else {
      Reject
    }
  }
  self.positionals.push(PositionalEntry::{
    handler,
    is_rest: false,
    greedy: false,
  })
}

///|
/// Returns a scope parser for positional grouping, eliminating the need
/// for `Ref` wrappers. This is the serial equivalent of `sub` for commands.
///
/// Parameters:
/// - `greedy` - If true, the compound handler runs during OC phase
///
/// Example:
/// ```
/// let s = parser.serial_scope()
/// let src = s.positional(name="src")
/// let dst = s.positional(name="dst")
/// parser.parse!(["file1.txt", "file2.txt"])
/// let source = src.get!()  // "file1.txt"
/// ```
pub fn Parser::serial_scope(
  self : Parser,
  greedy? : Bool = false,
) -> Parser {
  let scope_ref : Ref[Parser?] = { val: None }
  self.serial(setup=fn(scope) {
    scope_ref.val = Some(scope)
  }, greedy~)
  // Design rationale: setup callback is always invoked synchronously by serial(),
  // but match is safer than unwrap() against future refactoring.
  match scope_ref.val {
    Some(parser) => parser
    None => abort("Parser::serial_scope: setup callback was not executed by serial()")
  }
}

///|
/// Groups multiple positional arguments into a compound handler consumed sequentially.
///
/// The `setup` callback receives a lightweight sub-parser where multiple
/// `positional` and `rest` entries can be registered. They are consumed
/// as a single compound unit in order.
///
/// Parameters:
/// - `setup` - Callback to register the positional sequence on a sub-parser
/// - `greedy` - If true, the compound handler runs during OC phase. Note that
///   greedy serial consumes args without considering option matching, so
///   option-like arguments may be consumed as positional values.
///
/// Example:
/// ```
/// let src = Ref::new("")
/// let dst = Ref::new("")
/// parser.serial(setup=fn(s) {
///   let s_opt = s.positional(name="src")
///   let d_opt = s.positional(name="dst")
///   // ... use s_opt, d_opt after parse
/// })
/// parser.parse!(["file1.txt", "file2.txt"])
/// ```
pub fn Parser::serial(
  self : Parser,
  setup~ : (Parser) -> Unit,
  greedy? : Bool = false,
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
    before_post_hooks: [],
    post_hooks: [],
    registered_names: {},
    duplicate_errors: [],
    force_unclaimed: [],
    node_templates: Map::new(),
    eq_fallback_nodes: [],
    deprecated_usages: [],
    env_applicators: [],
    env_map: { val: {} },
    help_header_text: { val: "" },
    help_footer_text: { val: "" },
    env_prefix: { val: "" },
    auto_env_enabled: { val: self.auto_env_enabled.val },
    before_pre_refs: {},
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
