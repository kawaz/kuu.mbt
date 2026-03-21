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
/// Captures all arguments after a separator (default `--`) as a raw string array.
/// The separator itself is consumed and not included in the result.
/// `stop_before` lists tokens that end collection early (e.g. a subsequent separator).
pub fn Parser::dashdash(
  self : Parser,
  separator? : String = "--",
  stop_before? : Array[String] = [],
) -> Opt[Array[String]] {
  let id = (self.next_id)()
  let (vc, acc) = make_value_cell_lazy(initial=Thunk(fn() { [] }))
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
    reset=fn() {  },
    stop_before=stop,
  )
  let dashdash_node = make_serial_node(sep, [exact_node, rest_node])
  self.register_dashdash_node(sep, dashdash_node)
  {
    id,
    name: separator,
    accessor: acc,
    parsed: self.parsed,
    used: fn() { vc.committed.val },
  }
}

///|
/// Like `dashdash`, but supports multiple separator occurrences.
/// Each `--` ... section is collected as a separate `Array[String]`,
/// producing `Array[Array[String]]`.
pub fn Parser::append_dashdash(
  self : Parser,
  separator? : String = "--",
  stop_before? : Array[String] = [],
) -> Opt[Array[Array[String]]] {
  let id = (self.next_id)()
  let (vc, acc) = make_value_cell_lazy(initial=Thunk(fn() { [] }))
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
    reset=fn() {  },
    stop_before=stop,
    stop_at_sep=true,
    separator=sep,
  )
  let node = make_serial_node(sep, [exact_node, rest_node])
  self.register_dashdash_node(sep, node)
  {
    id,
    name: separator,
    accessor: acc,
    parsed: self.parsed,
    used: fn() { vc.committed.val },
  }
}
