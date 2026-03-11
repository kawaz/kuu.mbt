///| セパレータ以降の引数を収集するヘルパー。
/// stop_at_sep=true の場合、セパレータ自身でもループを停止する（append_dashdash 用）。
fn collect_after_separator(
  args : Array[String],
  pos : Int,
  sep : String,
  stop : Array[String],
  stop_at_sep~ : Bool = false,
) -> (Array[String], Int) {
  let collected : Array[String] = []
  let mut p = pos + 1
  while p < args.length() {
    if stop_at_sep && args[p] == sep {
      break
    }
    if stop.contains(args[p]) {
      break
    }
    collected.push(args[p])
    p += 1
  }
  (collected, p - pos)
}

///| dashdash ノードを登録し重複検出を行う共通ヘルパー
fn Parser::register_dashdash_node(self : Parser, sep : String, node : ExactNode) -> Unit {
  self.nodes.push(node)
  if self.registered_names.contains(sep) {
    self.duplicate_errors.push("duplicate option name: " + sep)
  }
  self.registered_names[sep] = true
}

///|
pub fn Parser::dashdash(
  self : Parser,
  separator? : String = "--",
  stop_before? : Array[String] = [],
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let cell : Ref[Array[String]] = { val: [] }
  let sep = separator
  let stop = stop_before
  let was_set : Ref[Bool] = { val: false }
  let dashdash_node = ExactNode::{
    name: sep,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != sep {
        return Reject
      }
      let (collected, consumed) = collect_after_separator(args, pos, sep, stop)
      Accept(consumed~, commit=fn() {
        for v in collected {
          cell.val.push(v)
        }
        was_set.val = true
      })
    },
    reset: fn() {
      cell.val = []
      was_set.val = false
    },
  }
  self.register_dashdash_node(sep, dashdash_node)
  {
    id,
    name: separator,
    getter: fn() -> Array[String] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}

///|
pub fn Parser::append_dashdash(
  self : Parser,
  separator? : String = "--",
  stop_before? : Array[String] = [],
) -> Opt[Array[Array[String]]] {
  let id = (self.next_id)()
  let cell : Ref[Array[Array[String]]] = { val: [] }
  let sep = separator
  let stop = stop_before
  let was_set : Ref[Bool] = { val: false }
  let node = ExactNode::{
    name: sep,
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != sep {
        return Reject
      }
      let (group, consumed) = collect_after_separator(
        args, pos, sep, stop, stop_at_sep=true,
      )
      Accept(consumed~, commit=fn() {
        cell.val.push(group)
        was_set.val = true
      })
    },
    reset: fn() {
      cell.val = []
      was_set.val = false
    },
  }
  self.register_dashdash_node(sep, node)
  {
    id,
    name: separator,
    getter: fn() -> Array[Array[String]] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}
