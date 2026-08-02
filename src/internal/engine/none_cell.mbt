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
/// 値空間を持たないセル (`type: "none"` / dd trigger、DR-089 §3 / DR-093 §2) の席を
/// **結果スコープ path 込み** で全て集める。結果 (`result`) / 由来 (`sources`) / 効果
/// (`effects`) の各射影が、これらを出力から落とすのに使う。
///
/// path は binding の `scope` と同じ体系 (宣言名の列)。結果スコープを作る 3 経路すべてを降りる:
///
/// - **command scope** (`CommandSatisfied`): 子 `Scope` を再帰
/// - **name 付き `seq` / `or`** (`Scoped`、DESIGN §2.3/§2.4): Node 木の中でラベルを積む。
///   これらの値セルは `Scope.entities` には**親スコープに平坦に**住み、結果スコープの段は
///   Node 木の `Scoped` だけが持つ — entity 走査だけでは path が付かない
/// - **`repeat`** (`IndexedRepeat`): ラベル段を積む。eval が更に `#k` の添字段を挟むが、
///   添字は席の同定に使わない (どの回の発火でも同じセルなので、ラベルまでで一意)
///
/// 同じセルが entity 走査と Node walk の両方から挙がる場合は 1 件に畳む (root 直下に住む
/// `none` は entity 側だけ、`Scoped` 配下のものは Node 側だけが拾うが、将来の lowering 変更で
/// 両方に現れても呼び出し側の照合は (path, name) の一致だけを見るので実害はない)。
/// `templates` は spine の `Ref(name)` が指す解決空間 (`AtomicAST.templates`)。unbounded な
/// `repeat` は head を `name#cons` テンプレへ退避して spine には `Ref` しか残さない
/// (`lower_repeat_shape`) ため、これを辿らないと反復配下のセルが 1 つも見えない。
/// `definitions.templates` (DR-078) の本体も同じ解決空間なので、`ref` 要素の参照先に住む
/// `none` も同時に拾える。同じテンプレを複数箇所から参照しても、参照元ごとの `path` で降りるので
/// 席は参照位置ごとに正しく付く。
pub fn none_cells(
  scope : Scope,
  templates : Map[String, Node],
) -> Array[NoneCell] {
  let out : Array[NoneCell] = []
  collect_nones(scope, [], templates, [], false, out)
  out
}

///|
pub fn selected_none_cells(
  scope : Scope,
  templates : Map[String, Node],
  bindings : Array[Binding],
) -> Array[NoneCell] {
  let out : Array[NoneCell] = []
  collect_nones(scope, [], templates, bindings, true, out)
  out
}

///|
fn push_none_cell(
  out : Array[NoneCell],
  path : Array[String],
  name : String,
) -> Unit {
  for existing in out {
    if existing.name_ == name && path_equal(existing.path_, path) {
      return
    }
  }
  out.push(none_cell(path, name))
}

///|
fn path_equal(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Node 木を降りて、結果スコープラベル (`Scoped` / `IndexedRepeat`) を path に積みながら
/// 値空間の無いセルを拾う。`names` は現在の `Scope` が宣言する `none` 型 entity 名 — `Ext`
/// 住人は自分が none 型かを知らない (型は `Entity` 側が持つ) ので、名前で突き合わせる。
fn collect_nones_in_node(
  node : Node,
  path : Array[String],
  names : Array[String],
  templates : Map[String, Node],
  visiting : Array[String],
  bindings : Array[Binding],
  selected_only : Bool,
  out : Array[NoneCell],
) -> Unit {
  match node {
    Scoped(label, body) =>
      collect_nones_in_node(
        body,
        append_path(path, label),
        names,
        templates,
        visiting,
        bindings,
        selected_only,
        out,
      )
    IndexedRepeat(label, body, _, _) =>
      collect_nones_in_node(
        body,
        append_path(path, label),
        names,
        templates,
        visiting,
        bindings,
        selected_only,
        out,
      )
    Seq(children) =>
      for child in children {
        collect_nones_in_node(
          child, path, names, templates, visiting, bindings, selected_only, out,
        )
      }
    Or(children) =>
      for child in children {
        collect_nones_in_node(
          child, path, names, templates, visiting, bindings, selected_only, out,
        )
      }
    Many(inner, _) =>
      collect_nones_in_node(
        inner, path, names, templates, visiting, bindings, selected_only, out,
      )
    GreedyRepeat(inner) =>
      collect_nones_in_node(
        inner, path, names, templates, visiting, bindings, selected_only, out,
      )
    Rooted(inner, _) =>
      collect_nones_in_node(
        inner, path, names, templates, visiting, bindings, selected_only, out,
      )
    BoundedTail(inner, _, _) =>
      collect_nones_in_node(
        inner, path, names, templates, visiting, bindings, selected_only, out,
      )
    // `name#cons` の自参照 (`lower_repeat_shape`) や相互参照するテンプレで無限降下しないよう、
    // 降下中のテンプレ名を stack で持って再入を止める。兄弟位置からの再参照は stack に無いので
    // 通常どおり降りる (同じテンプレでも参照位置ごとに path が違うため席は別々に要る)。
    Ref(target) => {
      for name in visiting {
        if name == target {
          return
        }
      }
      match templates.get(target) {
        Some(body) => {
          visiting.push(target)
          collect_nones_in_node(
            body, path, names, templates, visiting, bindings, selected_only, out,
          )
          let _ = visiting.pop()
        }
        None => ()
      }
    }
    DdSatisfied(trigger) => push_none_cell(out, path, trigger)
    DdMatchSatisfied(_, _, _, element) => push_none_cell(out, path, element)
    Ext(resident) =>
      match resident.element_name() {
        Some(name) =>
          for declared in names {
            if declared == name {
              push_none_cell(out, path, name)
              break
            }
          }
        None => ()
      }
    CommandSatisfied(name, ordinal, child) => {
      let child_path = append_path(path, name)
      if !selected_only || command_scope_selected(bindings, child_path, ordinal) {
        collect_nones(
          child, child_path, templates, bindings, selected_only, out,
        )
      }
    }
    ScopeNode(inner) =>
      collect_nones(inner, path, templates, bindings, selected_only, out)
    _ => ()
  }
}

///|
fn collect_nones(
  scope : Scope,
  path : Array[String],
  templates : Map[String, Node],
  bindings : Array[Binding],
  selected_only : Bool,
  out : Array[NoneCell],
) -> Unit {
  let names : Array[String] = []
  for entity in scope.entities {
    if entity.ty.name() == "none" {
      names.push(entity.name)
      // root 直下に住むセル (結果スコープを跨がない) はここで席が確定する。`Scoped` 配下に
      // 実体を持つものは Node walk 側が本来の path 付きで拾う。
      push_none_cell(out, path, entity.name)
    }
  }
  for node in scope.greedy {
    collect_nones_in_node(
      node,
      path,
      names,
      templates,
      [],
      bindings,
      selected_only,
      out,
    )
  }
  for node in scope.positional {
    collect_nones_in_node(
      node,
      path,
      names,
      templates,
      [],
      bindings,
      selected_only,
      out,
    )
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
