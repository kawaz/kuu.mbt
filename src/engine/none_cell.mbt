// none_cell.mbt — opaque identity of committed cells with no value space.

///|
pub struct NoneCell {
  priv path_ : Array[String]
  priv name_ : String
} derive(Eq, Debug)

///|
fn none_cell(path : Array[String], name : String) -> NoneCell {
  { path_: path, name_: name }
}

///|
pub fn NoneCell::path(self : NoneCell) -> Array[String] {
  self.path_
}

///|
pub fn NoneCell::name(self : NoneCell) -> String {
  self.name_
}

///|
pub fn none_cells(scope : Scope) -> Array[NoneCell] {
  let out : Array[NoneCell] = []
  collect_nones(scope, [], out)
  out
}

///|
fn collect_dd_names(node : Node, out : Array[String]) -> Unit {
  match node {
    DdSat(trigger) => out.push(trigger)
    DdMatchSat(_, _, _, element) => out.push(element)
    Or(alternatives) =>
      for alternative in alternatives {
        collect_dd_names(alternative, out)
      }
    Rooted(inner, _) => collect_dd_names(inner, out)
    _ => ()
  }
}

///|
fn collect_nones(
  scope : Scope,
  path : Array[String],
  out : Array[NoneCell],
) -> Unit {
  for entity in scope.entities {
    if entity.ty.name() == "none" {
      out.push(none_cell(path, entity.name))
    }
  }
  let dd_names : Array[String] = []
  for node in scope.greedy {
    collect_dd_names(node, dd_names)
  }
  for name in dd_names {
    out.push(none_cell(path, name))
  }
  for node in scope.greedy {
    match node {
      CmdSat(name, child) => collect_nones(child, append_path(path, name), out)
      _ => ()
    }
  }
}

///|
fn append_path(path : Array[String], segment : String) -> Array[String] {
  let out : Array[String] = []
  for part in path {
    out.push(part)
  }
  out.push(segment)
  out
}
