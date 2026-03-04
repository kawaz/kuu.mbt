///| 2つの文字列間の Levenshtein 距離を計算する
pub fn levenshtein_distance(a : String, b : String) -> Int {
  let a_chars = a.to_array()
  let b_chars = b.to_array()
  let m = a_chars.length()
  let n = b_chars.length()
  if m == 0 {
    return n
  }
  if n == 0 {
    return m
  }
  // 2行分の DP バッファで省メモリ化
  let mut prev = Array::make(n + 1, 0)
  let mut curr = Array::make(n + 1, 0)
  for j = 0; j <= n; j = j + 1 {
    prev[j] = j
  }
  for i = 1; i <= m; i = i + 1 {
    curr[0] = i
    for j = 1; j <= n; j = j + 1 {
      let cost = if a_chars[i - 1] == b_chars[j - 1] { 0 } else { 1 }
      let del = prev[j] + 1
      let ins = curr[j - 1] + 1
      let sub = prev[j - 1] + cost
      curr[j] = del
      if ins < curr[j] {
        curr[j] = ins
      }
      if sub < curr[j] {
        curr[j] = sub
      }
    }
    let tmp = prev
    prev = curr
    curr = tmp
  }
  prev[n]
}
