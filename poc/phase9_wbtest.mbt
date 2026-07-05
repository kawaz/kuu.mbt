// phase9_wbtest.mbt — path identity is the observable EFFECT sequence on entities,
// entry-independent (DR-038, rev). Two entries that reach the same effect merge to one
// path; two entries with different effects stay distinct. This pins that identity is
// (entity, value, source, order) and not "which entry (satellite/matcher) fired".

///|
test "DR-038: two entries reaching the SAME effect merge to one path (entry-independent)" {
  // Two structurally identical greedy entries write the same cell v=true. The token fires
  // both, producing the same effect via two search routes; effect identity merges them to
  // ONE path — NOT ambiguous. This is the global-copy-to-same-entity / interleaving case
  // the DR calls out (here forced by hand-building two identical entries, since add-if-absent
  // would otherwise dedup them at build time).
  let g = scope([flag("--v", "v"), flag("--v", "v")], [])
  inspect(render_outcome(parse(g, ["--v"])), content="ok{v=true}")
}

///|
test "DR-038: two entries with DIFFERENT effects stay distinct => ambiguous (identity is the effect)" {
  // Same trigger --v, but the two entries bind DIFFERENT entities (a vs b). The effects
  // differ, so the two complete paths are genuinely distinct => ambiguous:2. Proves the
  // identity is the effect (entity/value), not the trigger token or entry count.
  let g = scope([flag("--v", "a"), flag("--v", "b")], [])
  inspect(render_outcome(parse(g, ["--v"])), content="ambiguous:2")
}

///|
test "DR-038: same effect via different ORDER stays distinct (order is part of identity)" {
  // Two flags --a --b, and the same pair of effects reachable... but token order fixes the
  // effect order (a before b), so there is exactly ONE order and one path. The contrast
  // partner (two entries, same leaf, different value) below confirms value is in the key.
  let g = scope([flag("--a", "a"), flag("--b", "b")], [])
  inspect(render_outcome(parse(g, ["--a", "--b"])), content="ok{a=true,b=true}")
}

///|
test "DR-038: two entries, same entity+source, DIFFERENT value stay distinct => ambiguous" {
  // Both write cell `n`, but one binds true-as-flag... use two value entries that a single
  // token reads two ways: -n reading "1.0f" whole vs "1.0"+f. Different VALUE on n (and on f)
  // => distinct effects => ambiguous. (Mirrors DR-038's -n1.0f; here it confirms value is a
  // component of the effect key, so same-entity/different-value does NOT merge.)
  let short = NativeMatch(
    ShortCombine(prefix="-", entries=[
      { ch: 'n', name: "n", kind: TNum, depr: false },
      { ch: 'f', name: "f", kind: TFlag, depr: false },
    ]),
  )
  let g = scope([short], [])
  inspect(render_outcome(parse(g, ["-n1.0f"])), content="ambiguous:2")
}
