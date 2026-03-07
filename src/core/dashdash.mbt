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
      // セパレータ以降の全 args を収集
      let collected : Array[String] = []
      let mut p = pos + 1
      while p < args.length() {
        let mut should_stop = false
        for token in stop {
          if args[p] == token {
            should_stop = true
            break
          }
        }
        if should_stop {
          break
        }
        collected.push(args[p])
        p += 1
      }
      Accept(consumed=p - pos, commit=fn() {
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
  self.nodes.push(dashdash_node)
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
      let group : Array[String] = []
      let mut p = pos + 1
      while p < args.length() {
        if args[p] == sep {
          break
        }
        let mut should_stop = false
        for token in stop {
          if args[p] == token {
            should_stop = true
            break
          }
        }
        if should_stop {
          break
        }
        group.push(args[p])
        p += 1
      }
      Accept(consumed=p - pos, commit=fn() {
        cell.val.push(group)
        was_set.val = true
      })
    },
    reset: fn() {
      cell.val = []
      was_set.val = false
    },
  }
  self.nodes.push(node)
  {
    id,
    name: separator,
    getter: fn() -> Array[Array[String]] { cell.val },
    parsed: self.parsed,
    is_set: fn() { was_set.val },
  }
}
