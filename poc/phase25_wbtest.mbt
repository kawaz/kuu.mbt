// phase25_wbtest.mbt — 第 15 弾: 制約語彙 (DR-055) の遅延述語。constraint installer が requires /
// conflicts_with / exclusive_group / value_requires を回収し、遅延述語 (DR-047) として宣言する
// (席宣言型、構造衛星なし)。違反 = 完全経路の不成立 = Error kind:constraint (DR-053)。committed 判定は
// DR-045 の最終効果 (unset で取り消せば非 committed)。値依存は「値の枝に付いた requires」の合成。

fn cstr_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst, ConstraintInst,
  ]
}

// ── 1. constraint installer + completeness + 順列 ──────────────────────────────

test "DR-055/DR-042: constraint vocab needs the constraint installer; seats are order-independent" {
  // requires without ConstraintInst → unknown-vocab (DR-054). With it, the delayed predicate is
  // declared, and building with two different installer orders yields the same constraint behavior.
  // The requires TARGET `b` is a VALUE option (not a flag): a flag carries a preset default:false
  // (LOWERING §A.5 / DR-051 §2) so it is never value-absent, which would make `--a requires b`
  // vacuously satisfied (DR-055「target default 充足」). A value `b` stays absent when unsupplied, so
  // `--a` still surfaces the order-independent requires VIOLATION this test exercises.
  let def = def_(
    [
      opt("a", TFlag, long=["a"], requires=["b"]),
      opt("b", TStr, long=["b"]),
    ],
    [],
  )
  match parse_definition(def, [LongInst]) {
    Err(errs) => inspect(deferrs_str(errs), content="a/unknown-vocab") // constraint vocab unowned
    Ok(_) => abort("expected unknown-vocab for requires")
  }
  // order-independence: ConstraintInst early vs late → same violation on `--a`
  let sc1 = build_or_fail(def, [ConstraintInst, LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst, RepeatInst, MultipleInst, ConfigInst])
  let sc2 = build_or_fail(def, cstr_order())
  inspect(errors_str(parse(ScopeNode(sc1), ["--a"])), content="a@1/constraint")
  inspect(errors_str(parse(ScopeNode(sc2), ["--a"])), content="a@1/constraint")
}

// ── 2. requires (正の依存) ─────────────────────────────────────────────────────

test "DR-055 requires: committed + target absent → violation; target default 充足; 目的語は値の有無" {
  // decrypt requires key_file. decrypt given + key_file no value → 経路不成立 (kind:constraint).
  let def = def_(
    [
      opt("decrypt", TFlag, long=["decrypt"], requires=["key_file"]),
      opt("key_file", TStr, long=["key-file"]),
    ],
    [],
  )
  let sc = build_or_fail(def, cstr_order())
  inspect(errors_str(parse(ScopeNode(sc), ["--decrypt"])), content="decrypt@1/constraint")
  // decrypt + key_file given → satisfied
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--decrypt", "--key-file", "k"])),
    content="ok{decrypt=true,key_file=k}",
  )
  // decrypt not given → vacuously satisfied (requires only fires on committed)
  inspect(render_outcome(parse(ScopeNode(sc), [])), content="ok{}")
  // 目的語は「値の有無」(DR-047): key_file with a DEFAULT satisfies requires even absent on CLI
  let def_d = def_(
    [
      opt("decrypt", TFlag, long=["decrypt"], requires=["key_file"]),
      opt("key_file", TStr, long=["key-file"], default=Some(VStr("/id.key"))),
    ],
    [],
  )
  let sc_d = build_or_fail(def_d, cstr_order())
  inspect(render_outcome(parse(ScopeNode(sc_d), ["--decrypt"])), content="ok{decrypt=true}")
}

// ── 3. conflicts_with (負の依存, 対称) ──────────────────────────────────────────

test "DR-055 conflicts_with: both committed → conflict (片側宣言で両方向); unset で取り消せば衝突しない" {
  // foo conflicts_with bar (declared on foo only). Both committed → conflict; declaring on one side
  // works both ways (the check is「両方 committed」regardless of who declared it).
  let def = def_(
    [
      opt("foo", TFlag, long=["foo"], conflicts=["bar"]),
      opt("bar", TFlag, long=["bar"]),
    ],
    [],
  )
  let sc = build_or_fail(def, cstr_order())
  inspect(errors_str(parse(ScopeNode(sc), ["--foo", "--bar"])), content="foo@2/constraint")
  inspect(errors_str(parse(ScopeNode(sc), ["--bar", "--foo"])), content="foo@2/constraint") // 両方向
  inspect(render_outcome(parse(ScopeNode(sc), ["--foo"])), content="ok{foo=true}") // only foo
  inspect(render_outcome(parse(ScopeNode(sc), ["--bar"])), content="ok{bar=true}") // only bar
  // unset で取り消せば衝突しない (committed 判定は最終効果, DR-045)
  let def_v = def_(
    [
      opt(
        "foo",
        TFlag,
        long=["foo"],
        variants=[{ trigger: "no-foo", op: Unset, operand: None }],
        conflicts=["bar"],
      ),
      opt("bar", TFlag, long=["bar"]),
    ],
    [],
  )
  let sc_v = build_or_fail(def_v, cstr_order())
  // --foo --bar --no-foo: foo's last effect is Unset → not committed → the conflict does NOT fire.
  // Asserted via errors_str = "not-failure" (= a Success): the crisp contract is「衝突が立たない」.
  // (render_outcome would show the raw effect log `foo=false,foo=true` — both effects are retained in
  //  the bindings array; last-wins collapse happens at is_committed / ladder time, not display time —
  //  which would misread as「foo が 2 値」, so the constraint absence is the honest assertion here.)
  inspect(errors_str(parse(ScopeNode(sc_v), ["--foo", "--bar", "--no-foo"])), content="not-failure")
}

// ── 4. exclusive_group と conflicts_with の重複宣言 → 両方評価 ────────────────────

test "DR-055: the SAME pair in both exclusive_group and conflicts_with is evaluated by BOTH (2 errors)" {
  // Redundant declaration: (a,b) in exclusive group `g` AND a conflicts_with b. Both committed → both
  // predicates fire (2 constraint errors). Correct but redundant — 冗長の指摘は lint (放置が仕様).
  let def = def_(
    [
      opt("a", TFlag, long=["a"], exclusive=["g"], conflicts=["b"]),
      opt("b", TFlag, long=["b"], exclusive=["g"]),
    ],
    [],
  )
  let sc = build_or_fail(def, cstr_order())
  inspect(
    errors_str(parse(ScopeNode(sc), ["--a", "--b"])),
    content="a@2/constraint,g@2/constraint", // conflicts (a) + exclusive (g)
  )
}

// ── 5. 値依存の合成 (F-028 の解): 値の枝に付いた requires ────────────────────────

test "DR-055 §1 値依存: format=json requires schema (exact 枝の committed 経路でのみ立つ)" {
  // value_requires json→[schema] models「json 枝に付いた requires」. It activates ONLY when format's
  // committed value == "json" (the json exact's committed path). yaml does not trigger it.
  let def = def_(
    [
      opt("format", TStr, long=["format"], value_requires=[("json", ["schema"])]),
      opt("schema", TStr, long=["schema"]),
    ],
    [],
  )
  let sc = build_or_fail(def, cstr_order())
  // format=json + no schema → violation
  inspect(errors_str(parse(ScopeNode(sc), ["--format", "json"])), content="format@2/constraint")
  // format=yaml + no schema → satisfied (requires not active for yaml)
  inspect(render_outcome(parse(ScopeNode(sc), ["--format", "yaml"])), content="ok{format=yaml}")
  // format=json + schema → satisfied
  inspect(
    render_outcome(parse(ScopeNode(sc), ["--format", "json", "--schema", "s"])),
    content="ok{format=json,schema=s}",
  )
  // committed-vs-default asymmetry (the one subtle judgment in 値依存): value_requires is a TRIGGER,
  // and a trigger is committed-keyed (DR-047: exclusive/requires trigger = committed), NOT value-present.
  // So a DEFAULTED json (user never selected it) does NOT activate the requires — no schema demanded.
  // Contrast: the requires TARGET (schema 充足) would count a default (値充足, DR-047). The asymmetry is
  // intentional and unambiguous — it falls straight out of DR-047's trigger=committed / target=値充足 split.
  let def_dj = def_(
    [
      opt("format", TStr, long=["format"], default=Some(VStr("json")), value_requires=[("json", ["schema"])]),
      opt("schema", TStr, long=["schema"]),
    ],
    [],
  )
  let sc_dj = build_or_fail(def_dj, cstr_order())
  inspect(errors_str(parse(ScopeNode(sc_dj), [])), content="not-failure") // defaulted json ⇒ no trigger
}

// ── 6. 制約が経路選択に参加 (DR-047 §6 帰結 1) ──────────────────────────────────

test "DR-055/DR-047 §6: a constraint filters one of two complete paths → the other 確定 (not ambiguous)" {
  // Two complete interpretations of `x`: one commits foo+bar (conflicts), the other only foo. The
  // conflict makes the foo+bar path NOT a 完全経路 (DR-047), leaving foo alone — Success, NOT ambiguous.
  let paths : Array[Node] = [
    Or([
      Seq([Exact("x"), Bind("foo", VBool(true)), Bind("bar", VBool(true))]),
      Seq([Exact("x"), Bind("foo", VBool(true))]),
    ]),
  ]
  let sc : Scope = {
    greedy: [],
    positional: paths,
    entities: [],
    constraints: [CConflicts("foo", ["bar"])],
  }
  inspect(render_outcome(parse(ScopeNode(sc), ["x"])), content="ok{foo=true}")
  // WITHOUT the constraint, the same two paths are genuinely ambiguous:2
  let sc_noc : Scope = { greedy: [], positional: paths, entities: [], constraints: [] }
  inspect(render_outcome(parse(ScopeNode(sc_noc), ["x"])), content="ambiguous:2")
}
