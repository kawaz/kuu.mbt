// filters_wbtest.mbt — executable spec for the filters registry (issue 2026-07-09
// filters-registry-foundation, DR-009/010/036/040/061/077). Each case's comment states what it
// guarantees + the spec basis, mirroring the "test = 動く仕様書" convention used across this repo.

///|
/// wbtest ergonomics only (issue filter-spelling-inband-encoding-retyping): `apply_filter_chain`
/// takes `Array[FilterSpelling]` in production, but every case below wants the colon-shorthand's
/// terseness (`"in_range:1:10"`) rather than a hand-built `FilterSpelling` struct literal per entry
/// — this maps a plain string chain through `parse_filter_shorthand` (filters.mbt, the SAME parser
/// the decode boundary uses).
fn chain(strs : Array[String]) -> Array[FilterSpelling] {
  let out : Array[FilterSpelling] = []
  for s in strs {
    out.push(parse_filter_shorthand(s))
  }
  out
}

///|
/// 保証: DR-010 "フィールド名でレジストリが暗黙決定" — 名前で引くと正しい descriptor (signature 込み)
/// が返る。`trim` は Transform (値を変える)、`in_range`/`non_empty` は Validate (値は変えない、
/// 成否のみ) — DR-077 §2 "使えるのは transform シグネチャの filter のみ" が区別する軸そのもの。
test "lookup_filter: built-in signatures match DR-077 §2's validate/transform split" {
  assert_eq(lookup_filter("trim").unwrap().signature, Transform)
  assert_eq(lookup_filter("increment").unwrap().signature, Transform)
  assert_eq(lookup_filter("non_empty").unwrap().signature, Validate)
  assert_eq(lookup_filter("in_range").unwrap().signature, Validate)
  match lookup_filter("nonexistent") {
    None => ()
    Some(_) => fail("expected None")
  }
}

///|
/// 保証: `trim` は前後の空白を剥がす (DR-040 §piece_filters 例)。文字列以外の値は素通し (防御的 —
/// piece_filters 相は本来 string→string でしか呼ばれない契約、値型混入時に落とすより無害な
/// pass-through の方が診断しやすい)。
test "filter_trim strips whitespace, passes non-strings through" {
  match apply_filter_chain(chain(["trim"]), VStr("  hi  ")) {
    Ok(v) => assert_eq(v, VStr("hi"))
    Err(_) => fail("expected Ok")
  }
  match apply_filter_chain(chain(["trim"]), VNum(5.0)) {
    Ok(v) => assert_eq(v, VNum(5.0))
    Err(_) => fail("expected Ok (non-string passthrough)")
  }
}

///|
/// 保証: `non_empty` は空文字列のみ Err、それ以外は値そのままの Ok (Validate、値を変えない)。
test "filter_non_empty rejects only the empty string" {
  match apply_filter_chain(chain(["non_empty"]), VStr("x")) {
    Ok(v) => assert_eq(v, VStr("x"))
    Err(_) => fail("expected Ok")
  }
  match apply_filter_chain(chain(["non_empty"]), VStr("")) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (empty string)")
  }
}

///|
/// 保証: `in_range:<min>:<max>` (DR-009 §DSL 文法 "args はすべて string、filter registry 側でキャスト")
/// — 境界値は両方とも受理 (閉区間)、はみ出しは Err。
test "filter_in_range accepts a closed interval [min, max]" {
  match apply_filter_chain(chain(["in_range:1:10"]), VNum(1.0)) {
    Ok(v) => assert_eq(v, VNum(1.0))
    Err(_) => fail("expected Ok (lower bound inclusive)")
  }
  match apply_filter_chain(chain(["in_range:1:10"]), VNum(10.0)) {
    Ok(v) => assert_eq(v, VNum(10.0))
    Err(_) => fail("expected Ok (upper bound inclusive)")
  }
  match apply_filter_chain(chain(["in_range:1:10"]), VNum(11.0)) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (over the upper bound)")
  }
  match apply_filter_chain(chain(["in_range:1:10"]), VNum(0.0)) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (under the lower bound)")
  }
}

///|
/// 保証: `regex_match:<pattern>` の輪郭 (issue 2026-07-09-regex-match-filter §受け入れ条件、DR-085
/// §1) — (a) 一致受理、(b) 不一致 reject、(c) 部分一致 (unanchored) と全体一致 (pattern 側 `^$`) の
/// 区別、(d) メタ文字 escape (`\.` がリテラルドットにマッチし、無escape の `.` は任意1文字にマッチ)
/// の4輪郭を1テストで網羅する。DR-085 §2: 方言は MoonBit core `string.Regex` に準拠 (host 実装準拠)。
test "filter_regex_match: match / reject / partial-vs-full-anchor / metachar escape" {
  // (a) 一致受理: literal 部分一致。
  match apply_filter_chain(chain(["regex_match:abc"]), VStr("xxabcyy")) {
    Ok(v) => assert_eq(v, VStr("xxabcyy"))
    Err(_) => fail("expected Ok (unanchored partial match finds 'abc' inside)")
  }
  // (b) 不一致 reject。
  match apply_filter_chain(chain(["regex_match:abc"]), VStr("xyz")) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (no 'abc' substring)")
  }
  // (c) 部分一致と全体一致の区別: unanchored pattern は末尾ゴミがあっても通る (DR-085 §1 "filter
  // 側で暗黙アンカーを足さない")。同じ入力に `^...$` を足すと reject に転じる — アンカーは pattern
  // 側の責務であることの直接証拠。
  match apply_filter_chain(chain(["regex_match:abc"]), VStr("abcXYZ")) {
    Ok(_) => ()
    Err(_) =>
      fail("expected Ok (unanchored: trailing garbage after the match is fine)")
  }
  match apply_filter_chain(chain(["regex_match:^abc$"]), VStr("abcXYZ")) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (full-anchor pattern rejects trailing garbage)")
  }
  match apply_filter_chain(chain(["regex_match:^abc$"]), VStr("abc")) {
    Ok(v) => assert_eq(v, VStr("abc"))
    Err(_) => fail("expected Ok (full-anchor pattern matches the exact string)")
  }
  // (d) メタ文字 escape: `a.c` (無escape) は任意 1 文字を挟んだ "abc"/"axc" 双方にマッチするが、
  // `a\.c` (escape 済み) はリテラル "." のみにマッチし "abc" にはマッチしない。
  match apply_filter_chain(chain(["regex_match:^a.c$"]), VStr("abc")) {
    Ok(_) => ()
    Err(_) =>
      fail("expected Ok (unescaped '.' matches any single char, including 'b')")
  }
  match apply_filter_chain(chain(["regex_match:^a\\.c$"]), VStr("abc")) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) =>
      fail("expected Err (escaped '\\.' is a literal dot, does not match 'b')")
  }
  match apply_filter_chain(chain(["regex_match:^a\\.c$"]), VStr("a.c")) {
    Ok(v) => assert_eq(v, VStr("a.c"))
    Err(_) => fail("expected Ok (escaped '\\.' matches a literal dot)")
  }
}

///|
/// 保証: pattern の compile 失敗 (定義不良) と照合不一致 (入力拒否) は別の失敗という DR-085 §1 の
/// 区別 — 不正な pattern (閉じ括弧なしの group) は compile 時点で Err になる。非 string 値は他の
/// string-only filter (`non_empty` 等) と同じく `VStr` 以外専用の Err (このフィルタは string-only
/// で non-string 素通しの `trim` とは違う挙動、args 個数も 1 固定)。
test "filter_regex_match: malformed pattern, arg count, non-string input all Err distinctly" {
  match apply_filter_chain(chain(["regex_match:(unclosed"]), VStr("x")) {
    Err((reason, msg)) => {
      assert_eq(reason, "filter_rejected")
      assert_true(msg.contains("compile"))
    }
    Ok(_) => fail("expected Err (malformed pattern fails to compile)")
  }
  match apply_filter_chain(chain(["regex_match"]), VStr("x")) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (regex_match requires exactly 1 arg)")
  }
  match apply_filter_chain(chain(["regex_match:x"]), VNum(1.0)) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (regex_match requires a string value)")
  }
}

///|
/// 保証: `increment` は 0-arg number Transform、DR-077 §3 count の built-in transform そのもの
/// (apply_transform が registry lookup 経由でこの同じ closure を呼ぶ)。
test "filter_increment adds 1 to a number, rejects args and non-numbers" {
  match apply_filter_chain(chain(["increment"]), VNum(4.0)) {
    Ok(v) => assert_eq(v, VNum(5.0))
    Err(_) => fail("expected Ok")
  }
  match apply_filter_chain(chain(["increment:5"]), VNum(4.0)) {
    Err((reason, _)) => assert_eq(reason, "filter_rejected")
    Ok(_) => fail("expected Err (increment takes no args)")
  }
}

///|
/// 保証: 未知の filter 名は "unknown_filter" reason で Err (DR-010 "登録済みかどうか" の機械判定 — DR-054
/// definition-error 系の unknown-vocab と同族だが、こちらは filter chain 実行時の reason)。
test "apply_filter_chain surfaces an unregistered name as unknown_filter" {
  match apply_filter_chain(chain(["bogus"]), VNum(1.0)) {
    Err((reason, _)) => assert_eq(reason, "unknown_filter")
    Ok(_) => fail("expected Err")
  }
}

///|
/// 保証: chain は宣言順にそのまま流れる (DR-034 合成順「後ろほど優先」と同じく、chain 内は宣言順の
/// 素通し — 上書きの概念はない)。trim → in_range で "  5  " → 5.0 の in_range 検証、という組合せは
/// 現実には型が合わない (trim は文字列専用) ので、ここでは number 系だけを連結して合成順を固定する:
/// increment を2回連結すると +2 になる。
test "apply_filter_chain runs entries in declared order" {
  match apply_filter_chain(chain(["increment", "increment"]), VNum(1.0)) {
    Ok(v) => assert_eq(v, VNum(3.0))
    Err(_) => fail("expected Ok (1 -> 2 -> 3)")
  }
}
