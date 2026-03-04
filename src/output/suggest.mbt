///| 候補リストから最も近い名前を提案する
/// 距離が閾値（名前長の半分、最低2）以内の候補のみ返す
pub fn suggest(name : String, candidates : Array[String]) -> String? {
  let name_len = name.to_array().length()
  let threshold = if name_len / 2 > 2 { name_len / 2 } else { 2 }
  let mut best : String? = None
  let mut best_dist = threshold + 1
  for candidate in candidates {
    let dist = levenshtein_distance(name, candidate)
    if dist < best_dist {
      best_dist = dist
      best = Some(candidate)
    }
  }
  best
}
