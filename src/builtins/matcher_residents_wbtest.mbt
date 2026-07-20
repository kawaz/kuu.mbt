///|
/// Test-only node resident that captures a matcher's raw branch stream while `parse_tree`
/// supplies the private engine context. This keeps direct matcher probes out of the public API.
priv struct MatcherProbeExt {
  matcher : &@engine.MatcherExt
  captured : Array[Array[@engine.Branch]]
}

///|
impl @engine.NodeExt for MatcherProbeExt with fn kind(_self) {
  "test/matcher-probe"
}

///|
impl @engine.NodeExt for MatcherProbeExt with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.NodeExt for MatcherProbeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for MatcherProbeExt with fn eval(
  self,
  ctx,
  pos,
  acc,
  _next,
) {
  self.captured.push(
    self.matcher.interpret(ctx, pos, acc, (_ctx, next_pos, next_acc) => {
      [@engine.Accept(next_pos, next_acc)]
    }),
  )
  []
}

///|
fn probe_matcher(
  matcher : &@engine.MatcherExt,
  toks : Array[String],
) -> Array[@engine.Branch] {
  let captured : Array[Array[@engine.Branch]] = []
  let probe = @engine.Ext(
    MatcherProbeExt::{ matcher, captured } as &@engine.NodeExt,
  )
  ignore(@engine.parse_tree(probe, toks))
  guard captured.length() == 1 else { return [] }
  captured[0]
}

// matcher_residents_wbtest.mbt — builtin matcher residents as executable spec (DR-041 §3-4).
//
// These tests freeze the token→readings decomposition: an eq-split long option, and the short
// cluster walk (in-token value attachment, space form, deprecation marker). `@engine.Branch` derives only
// Show (not Eq), so cases match into the branch and compare primitive fields (pos / key / Value).

///|
fn acc_pos(b : @engine.Branch) -> Int {
  match b {
    @engine.Accept(p, _) => p
    @engine.Held(_, _) => -1
    @engine.Pending(_, _) => -1 // the matcher never produces @engine.Pending; guarded for exhaustiveness
  }
}

///|
fn acc_binds(b : @engine.Branch) -> Array[@engine.Binding] {
  match b {
    @engine.Accept(_, bs) => bs
    @engine.Held(_, _) => []
    @engine.Pending(_, _) => []
  }
}

///|
fn is_held(b : @engine.Branch) -> Bool {
  match b {
    @engine.Held(_, _) => true
    @engine.Accept(_, _) => false
    @engine.Pending(_, _) => false
  }
}

// ── DR-041 equal-separator matcher (`--key=value`) ────────────────────────────

///|
/// The eq-split matcher fires only on a token with `=` after the prefix, resolving the key to its
/// entry and parsing the value by the entry's type (DR-041 §equal separator). A defined key with a
/// bad number value is a held Error (not 素通し, DR-037); an undefined key produces no reading and
/// falls through to the positional face (素通し). A token without the prefix/`=` does not fire.
test "eq-split long option resolves, errors, and 素通し" {
  let long = eq_split("--", [
    eq_entry("port", "port", number_type(), [], None, merge=false, depr=false),
  ])
  // a defined numeric key: one @engine.Accept consuming 1 token, binding port=8080 from the CLI seat.
  let r1 = probe_matcher(long, ["--port=8080"])
  assert_eq(r1.length(), 1)
  assert_eq(acc_pos(r1[0]), 1)
  let b1 = acc_binds(r1[0])
  assert_eq(b1.length(), 1)
  assert_eq(b1[0].key, "port")
  assert_eq(b1[0].value, @engine.Number(8080.0))
  assert_eq(b1[0].source, @engine.Cli)
  // a defined key with a non-number value is a held Error (DR-037), NOT a silent 素通し.
  let r2 = probe_matcher(long, ["--port=abc"])
  assert_eq(r2.length(), 1)
  assert_eq(is_held(r2[0]), true)
  // an undefined key produces no reading (素通し to positional).
  assert_eq(probe_matcher(long, ["--host=x"]).length(), 0)
  // a token without `=` (or without the prefix) does not fire this matcher.
  assert_eq(probe_matcher(long, ["--port"]).length(), 0)
  assert_eq(probe_matcher(long, ["plain"]).length(), 0)
}

///|
/// A `bool_type()` eq-split entry (DR-074 §3, value-typed canonical bool): `--enabled=true` parses the
/// value through the canonical bool vocab (true/false/1/0/""，case-insensitive). An unrecognized
/// token (`yes` etc., canonical-外) is a held Error with reason `not_a_bool` (DR-066 v1 has no bool
/// reason yet, docs/issue/2026-07-07-bool-invalid-reason-vocab-gap.md) — not a silent 素通し. A
/// PRESENCE-only `flag_type()` entry never fires here at all (no eq-split registration, installer.mbt
/// `inst_long`; `flag_type()`'s own arm in `run_eq_split` returns `[]` unconditionally).
test "eq-split long option: bool canonical vocab, ci, and unrecognized-token Error" {
  let long = eq_split("--", [
    eq_entry(
      "enabled",
      "enabled",
      bool_type(),
      [],
      None,
      merge=false,
      depr=false,
    ),
  ])
  // `true` / `1` / mixed-case / all-caps all resolve to @engine.Bool(true).
  for
    tok in ["--enabled=true", "--enabled=1", "--enabled=True", "--enabled=TRUE"] {
    let r = probe_matcher(long, [tok])
    assert_eq(r.length(), 1)
    assert_eq(acc_pos(r[0]), 1)
    let b = acc_binds(r[0])
    assert_eq(b.length(), 1)
    assert_eq(b[0].key, "enabled")
    assert_eq(b[0].value, @engine.Bool(true))
    assert_eq(b[0].source, @engine.Cli)
  }
  // `false` / `0` / `""` all resolve to @engine.Bool(false) — the empty string is the env `FLAG=` pattern.
  for tok in ["--enabled=false", "--enabled=0", "--enabled="] {
    let r = probe_matcher(long, [tok])
    assert_eq(r.length(), 1)
    let b = acc_binds(r[0])
    assert_eq(b.length(), 1)
    assert_eq(b[0].value, @engine.Bool(false))
  }
  // `yes` is canonical-外 (Norway problem 回避, DR-074 §3): a held Error, not a silent 素通し.
  let ry = probe_matcher(long, ["--enabled=yes"])
  assert_eq(ry.length(), 1)
  assert_eq(is_held(ry[0]), true)
  match ry[0] {
    @engine.Held(pe, _) => {
      assert_eq(pe.element, "enabled")
      assert_eq(pe.args_pos, 0)
      assert_eq(pe.kind, @engine.Parse)
      assert_eq(pe.reason, "not_a_bool")
    }
    _ => fail("expected @engine.Held")
  }
}

///|
/// A presence-only `flag_type()` entry (e.g. `--help`/`--verbose`) has NO eq-split value pipeline at all
/// (DR-074 §3 only applies to `bool_type()`): `--verbose=true` finds the key defined but the type has no
/// value arm, so `run_eq_split` returns `[]` (素通し to positional), not a held Error.
test "eq-split long option: a flag_type() entry never fires on =value" {
  let long = eq_split("--", [
    eq_entry(
      "verbose",
      "verbose",
      flag_type(),
      [],
      None,
      merge=false,
      depr=false,
    ),
  ])
  assert_eq(probe_matcher(long, ["--verbose=true"]).length(), 0)
}

///|
/// codex レビュー Major 1 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見) / DR-058
/// §2: a deprecated eq-split entry (`EqEntry.depr`) rides a `@depr:<name>` warning marker alongside
/// its value binding, symmetric with the short cluster deprecated test below ("short cluster:
/// deprecated entry rides a @depr marker") and the space-form main entry (`installer_wbtest.mbt`'s
/// deprecated main-entry tests) — DR-058 §2 draws no distinction between long入口形 (space form /
/// eq-split), only that the SAME element fired. This freezes that firing `--port=8080` via the
/// eq-split入口 does NOT alter the parsed value (still `port=8080`) — only a warning is added.
test "eq-split long option: deprecated entry rides a @depr marker" {
  let long = eq_split("--", [
    eq_entry("port", "port", number_type(), [], None, merge=false, depr=true),
  ])
  // Entry deprecation warns only after a successful fire; the unread boundary spelling keeps the
  // established neutral completion metadata until a separate completion policy specifies otherwise.
  let candidates = long.candidates()
  assert_eq(candidates.length(), 1)
  assert_false(candidates[0].meta.deprecated)
  let r = probe_matcher(long, ["--port=8080"])
  assert_eq(r.length(), 1)
  let b = acc_binds(r[0])
  // two bindings: the value (port=8080) plus the deprecation marker (@depr:port).
  assert_eq(b.length(), 2)
  assert_eq(b[0].key, "port")
  assert_eq(b[0].value, @engine.Number(8080.0))
  assert_eq(b[1].key, "@depr:port")
}

///|
/// codex レビュー Major 1 続き: the `sep_binds` success path (`separator`/`merge` 経路、
/// `run_eq_split` の別 return site) is a SEPARATE code path from the plain kind-match arm above — a
/// naive fix could patch one and miss the other (which is exactly what the ORIGINAL DeprMark fix did
/// to the 4 non-BCell `inst_long` main-entry arms, Major 2). This locks the separator-bearing entry's
/// eq-split form (`--tags=a,b`) also carries the marker.
test "eq-split long option: deprecated entry with separator (sep_binds path) also rides a @depr marker" {
  let long = eq_split("--", [
    eq_entry(
      "tags",
      "tags",
      string_type(),
      [],
      Some(","),
      merge=false,
      depr=true,
    ),
  ])
  let r = probe_matcher(long, ["--tags=a,b"])
  assert_eq(r.length(), 1)
  let b = acc_binds(r[0])
  let mut found_depr = false
  for bd in b {
    if bd.key == "@depr:tags" {
      found_depr = true
    }
  }
  assert_true(found_depr)
}

// ── DR-041 short cluster matcher (`-abc`, value attachment, space form) ─────────

///|
/// The short matcher walks the in-token cluster, emitting a reading per full interpretation. A run of
/// flag chars binds each true (`-ab` → a,b). A value char attaches an in-token value of every length
/// that both parses AND lets the remainder complete — for `-n1.0` only the whole `1.0` completes
/// (the `1`/`1.` prefixes leave undefined chars that kill their readings), so exactly one reading
/// results. This is DR-041 §3-4 "enumerate ALL readings" narrowed by the completion requirement.
test "short cluster: flag run and in-token numeric value" {
  let short = short_combine(
    "-",
    [
      short_entry(
        'a',
        "a",
        flag_type(),
        [],
        None,
        depr=false,
        merge=false,
        short_attached_value=@engine.Allow,
        is_alias=false,
      ),
      short_entry(
        'b',
        "b",
        flag_type(),
        [],
        None,
        depr=false,
        merge=false,
        short_attached_value=@engine.Allow,
        is_alias=false,
      ),
      short_entry(
        'n',
        "n",
        number_type(),
        [],
        None,
        depr=false,
        merge=false,
        short_attached_value=@engine.Allow,
        is_alias=false,
      ),
    ],
    true,
  )
  // `-ab`: a run of two flags → one reading binding a=true, b=true, consuming the single token.
  let rf = probe_matcher(short, ["-ab"])
  assert_eq(rf.length(), 1)
  assert_eq(acc_pos(rf[0]), 1)
  let bf = acc_binds(rf[0])
  assert_eq(bf.length(), 2)
  assert_eq(bf[0].key, "a")
  assert_eq(bf[0].value, @engine.Bool(true))
  assert_eq(bf[1].key, "b")
  assert_eq(bf[1].value, @engine.Bool(true))
  // `-n1.0`: only the full value `1.0` completes the cluster → exactly one reading n=1.0.
  let rn = probe_matcher(short, ["-n1.0"])
  assert_eq(rn.length(), 1)
  assert_eq(acc_pos(rn[0]), 1)
  let bn = acc_binds(rn[0])
  assert_eq(bn.length(), 1)
  assert_eq(bn[0].key, "n")
  assert_eq(bn[0].value, @engine.Number(1.0))
}

///|
/// A value char at the cluster tail may take the NEXT token as its value (space form, consuming 2
/// tokens) — `-n 5` → n=5 at position 2. This is the getopt-同型 tail consumption (DR-041 §4).
test "short cluster: space-form value takes the next token" {
  let short = short_combine(
    "-",
    [
      short_entry(
        'n',
        "n",
        number_type(),
        [],
        None,
        depr=false,
        merge=false,
        short_attached_value=@engine.Allow,
        is_alias=false,
      ),
    ],
    true,
  )
  let r = probe_matcher(short, ["-n", "5"])
  assert_eq(r.length(), 1)
  assert_eq(acc_pos(r[0]), 2) // consumed BOTH the `-n` token and the `5` token
  let b = acc_binds(r[0])
  assert_eq(b.length(), 1)
  assert_eq(b[0].key, "n")
  assert_eq(b[0].value, @engine.Number(5.0))
}

///|
/// A deprecated cluster entry (DR-057/058) rides a `@depr:<name>` marker binding alongside its value;
/// the value binding is unchanged (only a warning is later collected from the marker). This freezes
/// that firing a deprecated spelling does NOT alter the parsed value — it only adds bookkeeping.
test "short cluster: deprecated entry rides a @depr marker" {
  let short = short_combine(
    "-",
    [
      short_entry(
        'd',
        "d",
        flag_type(),
        [],
        None,
        depr=true,
        merge=false,
        short_attached_value=@engine.Allow,
        is_alias=false,
      ),
    ],
    true,
  )
  let r = probe_matcher(short, ["-d"])
  assert_eq(r.length(), 1)
  let b = acc_binds(r[0])
  // two bindings: the flag value (d=true) plus the deprecation marker (@depr:d).
  assert_eq(b.length(), 2)
  assert_eq(b[0].key, "d")
  assert_eq(b[0].value, @engine.Bool(true))
  assert_eq(b[1].key, "@depr:d")
}

// ── issue scope-config-object-gap: short_combine (解釈A, team-lead 裁定 2026-07-11) ──

///|
/// entries を共有する 3 テスト共通の fixture: a (flag) / b (flag) / n (number_type(), 値付着可)。
fn combine_entries() -> Array[ShortEntry] {
  [
    short_entry(
      'a',
      "a",
      flag_type(),
      [],
      None,
      depr=false,
      merge=false,
      short_attached_value=@engine.Allow,
      is_alias=false,
    ),
    short_entry(
      'b',
      "b",
      flag_type(),
      [],
      None,
      depr=false,
      merge=false,
      short_attached_value=@engine.Allow,
      is_alias=false,
    ),
    short_entry(
      'n',
      "n",
      number_type(),
      [],
      None,
      depr=false,
      merge=false,
      short_attached_value=@engine.Allow,
      is_alias=false,
    ),
  ]
}

///|
/// 保証 (DR-014「-abc の結合許可」解釈A: 複数 entry のクラスタ結合のみ禁止): `combine:false` の
/// matcher へ `-ab` (2 flag を 1 トークンに結合) を渡すと、`a` を処理した後 `i+1(=1) !=
/// body.length()(=2)` により 2 文字目への継続を打ち切り、読みが 0 本になる (素通し — 対極として
/// combine:true の既存テスト "flag run and in-token numeric value" の `-ab` 成功ケースと対で読む)。
test "short cluster: combine:false rejects a 2-flag cluster (-ab)" {
  let short = short_combine("-", combine_entries(), false)
  let r = probe_matcher(short, ["-ab"])
  assert_eq(r.length(), 0)
}

///|
/// 対極 (同上、単一 flag は combine の管轄外): `combine:false` でも `-a` 単独 (body.length()==1) は
/// 引き続き発火する — 「複数 entry の結合」だけが禁止される、単一 entry のトークン占有は禁止されない。
test "short cluster: combine:false still fires a LONE flag (-a)" {
  let short = short_combine("-", combine_entries(), false)
  let r = probe_matcher(short, ["-a"])
  assert_eq(r.length(), 1)
  assert_eq(acc_pos(r[0]), 1)
  let b = acc_binds(r[0])
  assert_eq(b.length(), 1)
  assert_eq(b[0].key, "a")
  assert_eq(b[0].value, @engine.Bool(true))
}

///|
/// 対極 (同上、値付着が残余を "全部" 消費するなら結合ではない): `combine:false` でも `-n1.0` (value
/// char が残余トークン全体を値として取る、後続 entry が存在しない) は引き続き発火する — DR-041
/// line 77 の「値付着は short_combine と独立パラメータ」という設計意図の直接の帰結。
test "short cluster: combine:false still fires a FULL-TAIL value-attach (-n1.0)" {
  let short = short_combine("-", combine_entries(), false)
  let r = probe_matcher(short, ["-n1.0"])
  assert_eq(r.length(), 1)
  assert_eq(acc_pos(r[0]), 1)
  let b = acc_binds(r[0])
  assert_eq(b.length(), 1)
  assert_eq(b[0].key, "n")
  assert_eq(b[0].value, @engine.Number(1.0))
}

///|
/// 保証 (同上、部分長の値付着 + 後続 entry も結合の一種): `combine:false` で `-n1a` の PARTIAL
/// attach 読み (n が "1" だけ値に取り、残った "a" を後続 flag として結合する読み) は禁止される —
/// `j != body.length()` の場合 `combine:false` はそもそも `short_val` を試さない。残るのは
/// FULL-TAIL attach 読み (n が "1a" を丸ごと値に取ろうとする、number_type() parse が失敗して @engine.Held) だけ 1 本
/// — full-tail 読みは combine の管轄外 (単一 entry) なので禁止されない。合計 1 本、かつ @engine.Held。
test "short cluster: combine:false rejects the PARTIAL value-attach reading, keeps the FULL-TAIL @engine.Held (-n1a)" {
  let short = short_combine("-", combine_entries(), false)
  let r = probe_matcher(short, ["-n1a"])
  assert_eq(r.length(), 1)
  assert_true(is_held(r[0])) // full-tail "1a" は number_type() として parse 失敗 → @engine.Held (DR-037)
}

///|
/// 対極 (同上、combine:true なら部分長 + 結合の読みも追加で生きる): 同じ `-n1a` を `combine:true` の
/// matcher に渡すと、上記の FULL-TAIL @engine.Held に加え、PARTIAL attach (n="1"消費 + 残り "a" を flag と
/// して結合、n=1.0/a=true) の読みも生成され、計 2 本になる — `combine:false` テストとの対比で「何が
/// 追加で許可されるか」を固定する。
test "short cluster: combine:true adds the PARTIAL-attach-then-combine reading on top of the FULL-TAIL @engine.Held (対極, -n1a)" {
  let short = short_combine("-", combine_entries(), true)
  let r = probe_matcher(short, ["-n1a"])
  assert_eq(r.length(), 2)
  let mut accept_found = false
  let mut held_found = false
  for br in r {
    if is_held(br) {
      held_found = true
    } else {
      accept_found = true
      assert_eq(acc_pos(br), 1)
      let b = acc_binds(br)
      assert_eq(b.length(), 2)
      assert_eq(b[0].key, "n")
      assert_eq(b[0].value, @engine.Number(1.0))
      assert_eq(b[1].key, "a")
      assert_eq(b[1].value, @engine.Bool(true))
    }
  }
  assert_true(accept_found)
  assert_true(held_found)
}

///|
/// 保証 (同上、space-form は combine の管轄外): `combine:false` でも `-n 5` (space-form, 値は次
/// トークン全体) は引き続き発火する — 値は「同じトークンを共有する別 entry」ではなく別トークンから
/// 来るため、combine の対象外 (node.mbt の `ShortCombine` doc comment、次トークン borrow は「同じ
/// トークンでの結合」に該当しない)。
test "short cluster: combine:false still fires the space-form (next-token) value (-n 5)" {
  let short = short_combine("-", combine_entries(), false)
  let r = probe_matcher(short, ["-n", "5"])
  assert_eq(r.length(), 1)
  assert_eq(acc_pos(r[0]), 2)
  let b = acc_binds(r[0])
  assert_eq(b.length(), 1)
  assert_eq(b[0].key, "n")
  assert_eq(b[0].value, @engine.Number(5.0))
}
