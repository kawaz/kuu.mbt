///|
/// dashdash ノードを登録し重複検出を行う共通ヘルパー
fn Parser::register_dashdash_node(
  self : Parser,
  sep : String,
  node : ExactNode,
) -> Unit {
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
  let vc : ValCell[Array[String]] = ValCell::new(Thunk(fn() { [] }))
  let sep = separator
  let stop = stop_before
  let exact_node = make_exact_node(
    sep,
    on_match=fn() { fn() { vc.committed.val = true } },
    reset=fn() {
      vc.cell.val = []
      vc.committed.val = false
    },
  )
  let rest_node = make_rest_node(
    on_commit=fn(collected) { vc.cell.val = collected },
    reset=fn() {},
    stop_before=stop,
  )
  let dashdash_node = make_serial_node(sep, [exact_node, rest_node])
  self.register_dashdash_node(sep, dashdash_node)
  {
    id,
    name: separator,
    accessor: vc.accessor(),
    parsed: self.parsed,
    used: fn() { vc.committed.val },
  }
}

///|
pub fn Parser::append_dashdash(
  self : Parser,
  separator? : String = "--",
  stop_before? : Array[String] = [],
) -> Opt[Array[Array[String]]] {
  let id = (self.next_id)()
  let vc : ValCell[Array[Array[String]]] = ValCell::new(Thunk(fn() { [] }))
  let sep = separator
  let stop = stop_before
  let exact_node = make_exact_node(
    sep,
    on_match=fn() { fn() { vc.committed.val = true } },
    reset=fn() {
      vc.cell.val = []
      vc.committed.val = false
    },
  )
  let rest_node = make_rest_node(
    on_commit=fn(collected) { vc.cell.val.push(collected) },
    reset=fn() {},
    stop_before=stop,
    stop_at_sep=true,
    separator=sep,
  )
  let node = make_serial_node(sep, [exact_node, rest_node])
  self.register_dashdash_node(sep, node)
  {
    id,
    name: separator,
    accessor: vc.accessor(),
    parsed: self.parsed,
    used: fn() { vc.committed.val },
  }
}
