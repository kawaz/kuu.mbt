///|
/// wbtest helper: a parse-mode Ctx over bare tokens (run_matcher takes Ctx
/// since the complete-mode boundary Pending was added to the cluster walk).
fn pctx(toks : Array[String]) -> Ctx {
  { toks, defs: Map([]), mode: ModeParse }
}

// matcher_wbtest.mbt — the native matcher interpreter as executable spec (DR-041 §3-4).
//
// These tests freeze the token→readings decomposition: an eq-split long option, and the short
// cluster walk (in-token value attachment, space form, deprecation marker). `Branch` derives only
// Show (not Eq), so cases match into the branch and compare primitive fields (pos / key / Value).

///|
fn acc_pos(b : Branch) -> Int {
  match b {
    Accept(p, _) => p
    Held(_, _) => -1
    Pending(_, _) => -1 // the matcher never produces Pending; guarded for exhaustiveness
  }
}

///|
fn acc_binds(b : Branch) -> Array[Binding] {
  match b {
    Accept(_, bs) => bs
    Held(_, _) => []
    Pending(_, _) => []
  }
}

///|
fn is_held(b : Branch) -> Bool {
  match b {
    Held(_, _) => true
    Accept(_, _) => false
    Pending(_, _) => false
  }
}

// ── DR-041 equal-separator matcher (`--key=value`) ────────────────────────────

///|
/// The eq-split matcher fires only on a token with `=` after the prefix, resolving the key to its
/// entry and parsing the value by the entry's type (DR-041 §equal separator). A defined key with a
/// bad number value is a held Error (not 素通し, DR-037); an undefined key produces no reading and
/// falls through to the positional face (素通し). A token without the prefix/`=` does not fire.
test "eq-split long option resolves, errors, and 素通し" {
  let long = EqSplit(prefix="--", entries=[
    {
      key: "port",
      name: "port",
      kind: TNum,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
  ])
  // a defined numeric key: one Accept consuming 1 token, binding port=8080 from the CLI seat.
  let r1 = run_matcher(long, pctx(["--port=8080"]), 0)
  assert_eq(r1.length(), 1)
  assert_eq(acc_pos(r1[0]), 1)
  let b1 = acc_binds(r1[0])
  assert_eq(b1.length(), 1)
  assert_eq(b1[0].key, "port")
  assert_eq(b1[0].value, VNum(8080.0))
  assert_eq(b1[0].source, Cli)
  // a defined key with a non-number value is a held Error (DR-037), NOT a silent 素通し.
  let r2 = run_matcher(long, pctx(["--port=abc"]), 0)
  assert_eq(r2.length(), 1)
  assert_eq(is_held(r2[0]), true)
  // an undefined key produces no reading (素通し to positional).
  assert_eq(run_matcher(long, pctx(["--host=x"]), 0).length(), 0)
  // a token without `=` (or without the prefix) does not fire this matcher.
  assert_eq(run_matcher(long, pctx(["--port"]), 0).length(), 0)
  assert_eq(run_matcher(long, pctx(["plain"]), 0).length(), 0)
}

///|
/// A `TBool` eq-split entry (DR-074 §3, value-typed canonical bool): `--enabled=true` parses the
/// value through the canonical bool vocab (true/false/1/0/""，case-insensitive). An unrecognized
/// token (`yes` etc., canonical-外) is a held Error with reason `not_a_bool` (DR-066 v1 has no bool
/// reason yet, docs/issue/2026-07-07-bool-invalid-reason-vocab-gap.md) — not a silent 素通し. A
/// PRESENCE-only `TFlag` entry never fires here at all (no eq-split registration, installer.mbt
/// `inst_long`; `TFlag`'s own arm in `run_eq_split` returns `[]` unconditionally).
test "eq-split long option: bool canonical vocab, ci, and unrecognized-token Error" {
  let long = EqSplit(prefix="--", entries=[
    {
      key: "enabled",
      name: "enabled",
      kind: TBool,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
  ])
  // `true` / `1` / mixed-case / all-caps all resolve to VBool(true).
  for
    tok in ["--enabled=true", "--enabled=1", "--enabled=True", "--enabled=TRUE"] {
    let r = run_matcher(long, pctx([tok]), 0)
    assert_eq(r.length(), 1)
    assert_eq(acc_pos(r[0]), 1)
    let b = acc_binds(r[0])
    assert_eq(b.length(), 1)
    assert_eq(b[0].key, "enabled")
    assert_eq(b[0].value, VBool(true))
    assert_eq(b[0].source, Cli)
  }
  // `false` / `0` / `""` all resolve to VBool(false) — the empty string is the env `FLAG=` pattern.
  for tok in ["--enabled=false", "--enabled=0", "--enabled="] {
    let r = run_matcher(long, pctx([tok]), 0)
    assert_eq(r.length(), 1)
    let b = acc_binds(r[0])
    assert_eq(b.length(), 1)
    assert_eq(b[0].value, VBool(false))
  }
  // `yes` is canonical-外 (Norway problem 回避, DR-074 §3): a held Error, not a silent 素通し.
  let ry = run_matcher(long, pctx(["--enabled=yes"]), 0)
  assert_eq(ry.length(), 1)
  assert_eq(is_held(ry[0]), true)
  match ry[0] {
    Held(pe, _) => {
      assert_eq(pe.element, "enabled")
      assert_eq(pe.argv_pos, 0)
      assert_eq(pe.kind, KParse)
      assert_eq(pe.reason, "not_a_bool")
    }
    _ => fail("expected Held")
  }
}

///|
/// A presence-only `TFlag` entry (e.g. `--help`/`--verbose`) has NO eq-split value pipeline at all
/// (DR-074 §3 only applies to `TBool`): `--verbose=true` finds the key defined but the type has no
/// value arm, so `run_eq_split` returns `[]` (素通し to positional), not a held Error.
test "eq-split long option: a TFlag entry never fires on =value" {
  let long = EqSplit(prefix="--", entries=[
    {
      key: "verbose",
      name: "verbose",
      kind: TFlag,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
  ])
  assert_eq(run_matcher(long, pctx(["--verbose=true"]), 0).length(), 0)
}

// ── DR-041 short cluster matcher (`-abc`, value attachment, space form) ─────────

///|
/// The short matcher walks the in-token cluster, emitting a reading per full interpretation. A run of
/// flag chars binds each true (`-ab` → a,b). A value char attaches an in-token value of every length
/// that both parses AND lets the remainder complete — for `-n1.0` only the whole `1.0` completes
/// (the `1`/`1.` prefixes leave undefined chars that kill their readings), so exactly one reading
/// results. This is DR-041 §3-4 "enumerate ALL readings" narrowed by the completion requirement.
test "short cluster: flag run and in-token numeric value" {
  let short = ShortCombine(prefix="-", entries=[
    {
      ch: 'a',
      name: "a",
      kind: TFlag,
      depr: false,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
    {
      ch: 'b',
      name: "b",
      kind: TFlag,
      depr: false,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
    {
      ch: 'n',
      name: "n",
      kind: TNum,
      depr: false,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
  ])
  // `-ab`: a run of two flags → one reading binding a=true, b=true, consuming the single token.
  let rf = run_matcher(short, pctx(["-ab"]), 0)
  assert_eq(rf.length(), 1)
  assert_eq(acc_pos(rf[0]), 1)
  let bf = acc_binds(rf[0])
  assert_eq(bf.length(), 2)
  assert_eq(bf[0].key, "a")
  assert_eq(bf[0].value, VBool(true))
  assert_eq(bf[1].key, "b")
  assert_eq(bf[1].value, VBool(true))
  // `-n1.0`: only the full value `1.0` completes the cluster → exactly one reading n=1.0.
  let rn = run_matcher(short, pctx(["-n1.0"]), 0)
  assert_eq(rn.length(), 1)
  assert_eq(acc_pos(rn[0]), 1)
  let bn = acc_binds(rn[0])
  assert_eq(bn.length(), 1)
  assert_eq(bn[0].key, "n")
  assert_eq(bn[0].value, VNum(1.0))
}

///|
/// A value char at the cluster tail may take the NEXT token as its value (space form, consuming 2
/// tokens) — `-n 5` → n=5 at position 2. This is the getopt-同型 tail consumption (DR-041 §4).
test "short cluster: space-form value takes the next token" {
  let short = ShortCombine(prefix="-", entries=[
    {
      ch: 'n',
      name: "n",
      kind: TNum,
      depr: false,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
  ])
  let r = run_matcher(short, pctx(["-n", "5"]), 0)
  assert_eq(r.length(), 1)
  assert_eq(acc_pos(r[0]), 2) // consumed BOTH the `-n` token and the `5` token
  let b = acc_binds(r[0])
  assert_eq(b.length(), 1)
  assert_eq(b[0].key, "n")
  assert_eq(b[0].value, VNum(5.0))
}

///|
/// A deprecated cluster entry (DR-057/058) rides a `@depr:<name>` marker binding alongside its value;
/// the value binding is unchanged (only a warning is later collected from the marker). This freezes
/// that firing a deprecated spelling does NOT alter the parsed value — it only adds bookkeeping.
test "short cluster: deprecated entry rides a @depr marker" {
  let short = ShortCombine(prefix="-", entries=[
    {
      ch: 'd',
      name: "d",
      kind: TFlag,
      depr: true,
      int_round: RError,
      allow_base_prefix: false,
      piece_filters: [],
      separator: None,
      merge: false,
    },
  ])
  let r = run_matcher(short, pctx(["-d"]), 0)
  assert_eq(r.length(), 1)
  let b = acc_binds(r[0])
  // two bindings: the flag value (d=true) plus the deprecation marker (@depr:d).
  assert_eq(b.length(), 2)
  assert_eq(b[0].key, "d")
  assert_eq(b[0].value, VBool(true))
  assert_eq(b[1].key, "@depr:d")
}
