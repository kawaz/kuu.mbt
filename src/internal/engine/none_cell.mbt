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
/// 1 スコープが直に持つ dd trigger の element 名 (`DdSatisfied` の trigger /
/// `DdMatchSatisfied` の element、DR-093 §2/§7)。値空間を持たない点で `type: "none"` と同じ
/// 扱いを受けるが、entity ではなく `greedy` 側のノードが運ぶので `Scope.entities` を見るだけ
/// では拾えない。呼び出し側 (kuu の内部セル収集) が自前で木を降りるため、`none_cells` の
/// ような再帰ではなく **この scope の直下だけ** を返す。
pub fn dd_element_names(scope : Scope) -> Array[String] {
  let out : Array[String] = []
  for node in scope.greedy {
    collect_dd_names(node, out)
  }
  out
}

///|
fn collect_dd_names(node : Node, out : Array[String]) -> Unit {
  match node {
    DdSatisfied(trigger) => out.push(trigger)
    DdMatchSatisfied(_, _, _, element) => out.push(element)
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
      CommandSatisfied(name, child) =>
        collect_nones(child, append_path(path, name), out)
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
