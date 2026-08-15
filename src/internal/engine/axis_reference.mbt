// axis_reference.mbt — DR-136 §6: the ONE 2-stage lookup every id-axis / result-key-axis
// reference goes through.
//
// A reference string written by the author (`ref` / `link` / `borrow` / `requires` and the other
// constraint attributes / the key part of the link fixed-path DSL) may be spelled either the way
// the target's axis value actually reads, or the way the target's `name` reads — the two diverge
// whenever the axis was filled by the character map (`{"name": "--"}` has id `__`). To keep the
// referencing side ignorant of the map, each scope is searched twice:
//
//   1. the reference string as written (raw match)
//   2. the reference string with the axis's own character map applied
//
// and only then does the search move outward. Priority is therefore **scope proximity over match
// method**: an inner scope's mapped match beats an outer scope's raw match. The lexical chain
// itself (DR-006 / DR-032 / DR-033) is untouched — callers walk it and ask this function once per
// scope.
//
// Every reference-resolving site calls this instead of comparing strings itself: implementing the
// two stages per site is how the map application, the stage order, and the scope walk drift apart.

///|
/// 1 スコープぶんの候補列から参照先を引く (DR-136 §6)。`axis_of` は候補の当該軸の値を返す
/// (id 軸なら `reference_identifier()`、結果キー軸なら解決後の露出キー)。`map_axis` はその軸の
/// 文字写像 (`name_axis_id` / `name_axis_trigger`)。
///
/// 段 1 (raw) を候補列全体で試してから段 2 (写像後) に移る — 段を候補ごとに交互させると
/// 「後ろの候補の raw 一致より前の候補の写像一致が勝つ」ことになり、明示 `id` が厳密に当たる
/// 保証 (§6 帰結の 1 つ目) が崩れる。
pub fn[T] resolve_axis_reference(
  candidates : Array[T],
  reference : String,
  axis_of : (T) -> String,
  map_axis : (String) -> String,
) -> T? {
  for candidate in candidates {
    if axis_of(candidate) == reference {
      return Some(candidate)
    }
  }
  let mapped = map_axis(reference)
  if mapped == reference {
    return None // 段 2 は段 1 と同じ照合になるので試すまでもない
  }
  for candidate in candidates {
    if axis_of(candidate) == mapped {
      return Some(candidate)
    }
  }
  None
}

///|
/// 参照識別子軸 (`id`、無指定なら name の id 軸写像) を引く場合の `resolve_axis_reference`。
/// ref / link の root / borrow / 制約属性の要素名はすべてこの軸。
pub fn[T] resolve_id_reference(
  candidates : Array[T],
  reference : String,
  axis_of : (T) -> String,
) -> T? {
  resolve_axis_reference(candidates, reference, axis_of, name_axis_id)
}
