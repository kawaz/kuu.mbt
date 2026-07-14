// eval_wbtest.mbt — acceptance tests for the CPS evaluator core (MDR-002).
//
// These pin the TWO breakages the re-design exists to fix, on hand-built
// AtomicAST (no lowering involved — the installer layer lands separately, so
// these tests stay valid even if lowering changes shape).

///|
/// The repeat registry template `Seq([head, …])`: the spine walk (scope_consume
/// Ref arm) only reads items[0] as the head; the porous unfold is structural.
fn reg_repeat(defs : Map[String, Node], name : String, head : Node) -> Unit {
  defs.set(name, Seq([head]))
}

///|
test "MDR-002 §1.5 acceptance: greedy repeat in a child command yields the parent's trailing positional (phase16 fix)" {
  // Root R: one trailing positional `tail`, one greedy command `seq` whose
  // body is an unbounded greedy repeat `xs` (min 1). Input `seq a b c`.
  //
  // The slice's global-length oracle committed xs=[a,b,c] (it reaches the
  // global end) and starved `tail` → "fail:missing operand for tail" (the
  // phase16 frozen fail). The CPS oracle instead runs the continuation: the
  // xs=[a,b] split's `stop` resumes R, consumes `c` into tail, and reaches
  // KTop at the global end → Accept; the xs=[a,b,c] split's continuation
  // Helds on tail → pruned. Exactly one complete path remains.
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs", []))
  let child : Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("seq", child)],
    positional: [StrArg("tail", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["seq", "a", "b", "c"], defs~)
  match o {
    Success(bs) => {
      // xs reps nest under [seq]; tail lands at the root. The result-object
      // view {seq:{xs:[a,b]}, tail:c} is the resolve layer's fold of exactly
      // these bindings.
      let mut xs_count = 0
      let mut tail_ok = false
      let mut xs_in_seq = true
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
          if b.scope != ["seq"] {
            xs_in_seq = false
          }
        }
        if b.key == "tail" {
          match b.value {
            VStr(s) => if s == "c" && b.scope.length() == 0 { tail_ok = true }
            _ => ()
          }
        }
      }
      // xs took exactly 2 reps (a, b) — the [a,b,c] share was pruned by the
      // continuation oracle, the [a] share by greedy preference (more wins
      // when both complete? no: [a] leaves b unconsumable by tail+end, so it
      // never completes — only [a,b] survives).
      assert_eq(xs_count, 2)
      assert_true(xs_in_seq)
      assert_true(tail_ok)
    }
    _ => fail("expected Success")
  }
}

///|
test "MDR-002 §1.4 control: without the trailing positional, greedy xs takes everything" {
  // Same shape minus `tail`: xs correctly commits to [a,b,c] (greedy default
  // = the longer share, and that share completes).
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs", []))
  let child : Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("seq", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["seq", "a", "b", "c"], defs~)
  match o {
    Success(bs) => {
      let mut xs_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
      }
      assert_eq(xs_count, 3)
    }
    _ => fail("expected Success")
  }
}

///|
test "DR-097 (先食い述語の精密化): a value-less trigger at the end of input is 読みゼロ — the raw positional eats it, not a missing-operand failure" {
  // Root: permissive string positional `files` + greedy `--port <num>`.
  // Input ["--port"]: the trigger fires but the value slot is starved
  // (missing operand) — DR-097's precised 「読める」predicate ("トリガ発火
  // に加え、その entry 自身の値スロット消費が args から確保でき... 値空間
  // 照合を通ること") makes this reading NON-viable, so it counts as 読みゼロ
  // and the raw-eat is NOT suppressed: `files` consumes the literal string
  // "--port" and the parse succeeds. Supersedes the pre-DR-097 pin
  // (MDR-002 §2.6's "Pending counts as reads" posture, which made a
  // value-less trigger suppress 先食い even when its own value slot could
  // never be filled) — DR-097 distinguishes "trigger fired but the reading
  // itself cannot succeed" (読みゼロ) from "trigger fired and the reading
  // holds" (先食い holds).
  let root : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port", false, [])])],
    positional: [StrArg("files", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--port"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut files_raw = false
      for b in bs {
        if b.key == "files" {
          match b.value {
            VStr(s) => if s == "--port" { files_raw = true }
            _ => ()
          }
        }
      }
      assert_true(files_raw)
    }
    _ =>
      fail("expected Success (files raw-eats \"--port\", DR-097 読みゼロ)")
  }
}

///|
test "positional spine + greedy interjection sanity (order-free trigger between positionals)" {
  // prog a --v b : greedy flag --v interjects between two positionals.
  let root : Scope = {
    greedy: [Seq([Exact("--v"), Bind("v", VBool(true))])],
    positional: [StrArg("x", []), StrArg("y", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "--v", "b"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut got_v = false
      let mut got_x = false
      let mut got_y = false
      for b in bs {
        if b.key == "v" {
          got_v = true
        }
        if b.key == "x" {
          match b.value {
            VStr(s) => if s == "a" { got_x = true }
            _ => ()
          }
        }
        if b.key == "y" {
          match b.value {
            VStr(s) => if s == "b" { got_y = true }
            _ => ()
          }
        }
      }
      assert_true(got_v)
      assert_true(got_x)
      assert_true(got_y)
    }
    _ => fail("expected Success")
  }
}

///|
test "dd sever: past `--`, a trigger-looking token falls raw into the positional" {
  let root : Scope = {
    greedy: [Seq([Exact("--v"), Bind("v", VBool(true))]), DdSat("--")],
    positional: [StrArg("x", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--", "--v"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut x_is_trigger = false
      for b in bs {
        if b.key == "x" {
          match b.value {
            VStr(s) => if s == "--v" { x_is_trigger = true }
            _ => ()
          }
        }
      }
      assert_true(x_is_trigger)
    }
    _ => fail("expected Success")
  }
}

///|
test "residual token failure: an unconsumable trailing token is a KTop held error" {
  // No positionals, no greedy match for "zzz" → every path stops short of
  // the global end. The KTop continuation surfaces the residual head as a
  // held Error (element "", kind parse) — the slice synthesized this at the
  // top level from silently-dropped partial Accepts; under CPS it emerges
  // naturally where the residual is observed.
  let root : Scope = {
    greedy: [],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["zzz"], defs=Map([]))
  match o {
    Failure(fd) => {
      assert_true(fd.errors.length() >= 1)
      assert_eq(fd.errors[0].message, "unexpected token")
    }
    _ => fail("expected Failure")
  }
}

///|
test "REVIEW-H1 probe: repeat head = ScopeNode (off-spine KDone) with outer trailing positional" {
  // The reviewer's threat scenario: a repeat whose HEAD is itself a ScopeNode
  // containing an inner repeat. The head is evaluated through consume_head's
  // generic fallback -> plain eval() -> KDone, so the INNER repeat's 取り分
  // oracle cannot see the outer scope's trailing positional. If KDone
  // reintroduces breakage-1 here, the inner xs eats a,b,c and tail starves.
  // Correct outcome: xs=[a,b], tail=c (same shape as phase16, one level in).
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs", []))
  let inner : Scope = {
    greedy: [],
    positional: [Ref("xs")],
    entities: [],
    constraints: [],
  }
  reg_repeat(defs, "grp", ScopeNode(inner))
  let root : Scope = {
    greedy: [],
    positional: [Ref("grp"), StrArg("tail", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c"], defs~)
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut tail_ok = false
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "tail" {
          tail_ok = true
        }
      }
      assert_eq(xs_count, 2)
      assert_true(tail_ok)
    }
    _ => fail("expected Success")
  }
}

///|
test "DR-043 sequential repeats: xs ys over a b c d e — greedy xs takes the longer share, ys gets the rest" {
  // DR-043's own primary 取り分選好 example: two adjacent unbounded repeats
  // (both min 1, greedy default). The split is ONE interpretation's freedom
  // of division, not an ambiguity: greedy xs prefers the longest share whose
  // continuation still completes -> xs=[a,b,c,d], ys=[e]. Exactly one path.
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs", []))
  reg_repeat(defs, "ys", StrArg("ys", []))
  let root : Scope = {
    greedy: [],
    positional: [Ref("xs"), Ref("ys")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c", "d", "e"], defs~)
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut ys_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "ys" {
          ys_count = ys_count + 1
        }
      }
      assert_eq(xs_count, 4)
      assert_eq(ys_count, 1)
    }
    _ => fail("expected Success")
  }
}

///|
test "REVIEW-C1 fired_action survives a failing value slot in the same greedy entry" {
  // A failure-action entry that ALSO takes a value: Seq([--help, FailMark,
  // NumArg]). When the value fails to parse, the FailMark marker bound
  // earlier in the SAME Seq must still reach parse() on the Held's partial
  // state — fired_action and the held error coexist (spec DR-048/DR-053 §4).
  // The slice dropped the Seq-internal acc on Held, losing the action.
  let root : Scope = {
    greedy: [Seq([Exact("--help"), FailMark("help"), NumArg("n", false, [])])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--help", "abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      assert_eq(fd.fired_action, Some("help"))
      let mut saw_parse_err = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          saw_parse_err = true
        }
      }
      assert_true(saw_parse_err)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REVIEW-C2 eval_many: a Pending after successful reps carries the reps' bindings" {
  // Whitebox: one rep of StrArg("v", []) consumes the only token, the next rep
  // starves -> Pending. Its partial state must include v=x (the same
  // contract as eval_seq: Pending = starved branch WITH its state).
  let ctx : Ctx = { toks: ["x"], defs: Map([]), mode: ModeParse }
  let brs = eval_many(StrArg("v", []), ctx, 0, [])
  let mut pending_has_acc = false
  for b in brs {
    match b {
      Pending(_, bs) =>
        if bs.length() == 1 && bs[0].key == "v" {
          pending_has_acc = true
        }
      _ => ()
    }
  }
  assert_true(pending_has_acc)
}

///|
test "REVIEW-C3 head_name knows FilterArg: optional extra rep at EOF is a stop, not an error" {
  // Repeat of a FilterArg head followed by a mandatory positional z, input
  // exhausts after one rep. The genuine failure is "z missing"; the "one
  // more n" probe finding no token is a legitimate stop and must NOT add a
  // missing-operand-for-n error (drop_optional_missing needs the head's
  // name, which FilterArg supplies via head_name).
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "ns", FilterArg("n", 100))
  let root : Scope = {
    greedy: [],
    positional: [Ref("ns"), StrArg("z", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["5"], defs~)
  match o {
    Failure(fd) => {
      for e in fd.errors {
        // no error may blame the repeat element n for "missing operand"
        assert_false(e.element == "n" && e.reason == "missing_operand")
      }
      let mut z_missing = false
      for e in fd.errors {
        if e.element == "z" && e.reason == "missing_operand" {
          z_missing = true
        }
      }
      assert_true(z_missing)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REVIEW-C4 non-scope root: residual of a partial Accept surfaces even when another branch held an error" {
  // Or branch 1 accepts "a" leaving "xyz" residual (partial Accept);
  // branch 2 helds a not_a_number on "xyz". 0 complete paths -> failure.
  // Both failure reasons must be retained (DR-053 §2 全保持): gating the
  // residual synthesis on "errors empty" would mask the partial reading.
  let root = Or([Exact("a"), Seq([Exact("a"), NumArg("n", false, [])])])
  let o = parse(root, ["a", "xyz"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut saw_residual = false
      let mut saw_parse = false
      for e in fd.errors {
        if e.reason == "unexpected_token" && e.args_pos == 1 {
          saw_residual = true
        }
        if e.reason == "not_a_number" {
          saw_parse = true
        }
      }
      assert_true(saw_residual)
      assert_true(saw_parse)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REGRESSION dd sever transparent to positional inline ScopeNode child (DR-041 dashdash)" {
  // deep-review R4a: root's DdSat("--") fires; the positional walk then
  // enters a ScopeNode child; without the sever pass-through the child's
  // greedy face resurrects and reads "-x" as the child's -x option
  // (Success x=true, a="w"). Spec DR-041/042 ⑤: dd's continuation is raw
  // for the WHOLE spine, including any inline child scope reached via the
  // positional face — so "-x" must land as the child's positional a, and
  // "w" is a residual token → Failure.
  let child : Scope = {
    greedy: [Seq([Exact("-x"), Bind("x", VBool(true))])],
    positional: [StrArg("a", [])],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [DdSat("--")],
    positional: [ScopeNode(child)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--", "-x", "w"], defs=Map([]))
  match o {
    Failure(fd) => {
      // no x binding should exist (child greedy face is severed) and the
      // residual "w" surfaces as a KTop unexpected_token at args_pos 2.
      let mut saw_residual = false
      for e in fd.errors {
        if e.reason == "unexpected_token" && e.args_pos == 2 {
          saw_residual = true
        }
      }
      assert_true(saw_residual)
    }
    _ => fail("expected Failure (child greedy must be severed under dd)")
  }
}

///|
test "REGRESSION step_greedy Held carries acc so FailMark survives to DeepestOnly fired_action" {
  // deep-review "step_greedy acc": two greedy entries — a FailMark help
  // action, and a numeric option. Under faildef=DeepestOnly the ONLY
  // candidate path for fired_action collection is the deepest one:
  // consume --help (bind help + FailMark) → consume --num → NumArg("xyz", false, [])
  // parse fail @ args_pos 2. Without acc on the Held branch, the FailMark
  // binding accumulated before the Held is dropped and fired_action
  // becomes None. With it, fired_action = Some("help").
  let root : Scope = {
    greedy: [
      Seq([Exact("--help"), Bind("help", VBool(true)), FailMark("help")]),
      Seq([Exact("--num"), NumArg("n", false, [])]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(
    ScopeNode(root),
    ["--help", "--num", "xyz"],
    defs=Map([]),
    faildef=DeepestOnly,
  )
  match o {
    Failure(fd) => assert_eq(fd.fired_action, Some("help"))
    _ => fail("expected Failure")
  }
}

///|
test "REGRESSION consume_head ReqArg respects 先食い (raw-eat suppression)" {
  // deep-review LENS-T2b: `fs` is a Ref-repeat over ReqArg head. Without
  // the ReqArg arm in consume_head, the fallback eval() sees no scope and
  // cannot apply suppressed(), so the "more" rep of fs raw-eats the
  // greedy trigger "-v" as another f value. Correct: -v fires the greedy
  // entry (verbose=true), fs has ONE binding.
  let defs : Map[String, Node] = Map([])
  defs.set("fs", Seq([ReqArg("f")]))
  let root : Scope = {
    greedy: [Seq([Exact("-v"), Bind("verbose", VBool(true))])],
    positional: [Ref("fs")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "-v"], defs~)
  match o {
    Success(bs) => {
      let mut f_count = 0
      let mut verbose_ok = false
      for b in bs {
        if b.key == "f" {
          f_count = f_count + 1
        }
        if b.key == "verbose" {
          match b.value {
            VBool(v) => if v { verbose_ok = true }
            _ => ()
          }
        }
      }
      assert_eq(f_count, 1)
      assert_true(verbose_ok)
    }
    _ => fail("expected Success (verbose fires, fs=[a])")
  }
}

///|
test "REGRESSION Many spine takes preference (greedy default, no Ambiguous)" {
  // deep-review LENS-T6: two adjacent Many closures without preference
  // return Ambiguous (3-way split of ["a","b"] between xs and ys). DR-043
  // "取り分次元は代表 1 本に確定" — greedy default (Many has no lazy_
  // knob) picks the more-rep-first split: xs=[a,b], ys=[].
  let root : Scope = {
    greedy: [],
    positional: [Many(StrArg("xs", []), false), Many(StrArg("ys", []), false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut ys_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "ys" {
          ys_count = ys_count + 1
        }
      }
      assert_eq(xs_count, 2)
      assert_eq(ys_count, 0)
    }
    _ => fail("expected Success xs=2 ys=0 (no Ambiguous)")
  }
}

///|
/// DR-043 lazy on the min:0 UNBOUNDED spine form (issue 2026-07-08 min0-lazy-repeat-gap,
/// resolved): `Many`'s 2nd field mirrors this test's greedy-default sibling above, with the
/// tie-break flipped. `Many(xs, true)` adjacent to `Many(ys, false)` on ["a","b","c"] takes the
/// SHORTEST xs share (0 reps) instead of the longest — same shape as preference-lazy.json's
/// min:1 case (`xs=[a]` there, the mandatory minimum; here the mandatory minimum is 0).
test "DR-043: Many(lazy=true) prefers the shortest (0-rep) share, mirroring the greedy default" {
  let root : Scope = {
    greedy: [],
    positional: [Many(StrArg("xs", []), true), Many(StrArg("ys", []), false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut ys_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "ys" {
          ys_count = ys_count + 1
        }
      }
      assert_eq(xs_count, 0)
      assert_eq(ys_count, 3)
    }
    _ => fail("expected Success xs=0 ys=3 (lazy prefers shortest)")
  }
}

///|
test "REGRESSION scope-shaped Ref head: more-branch drops internal missing_operand only" {
  // deep-review LENS-T3: Ref("r")'s head is ScopeNode(inner) with a
  // single StrArg("f", []) positional. Input ["a"] consumes 1 rep (f=a);
  // the OPTIONAL "more" rep enters inner at EOF, producing Held(pe_missing
  // "f"). Before the fix, head_name(ScopeNode)="" left drop_optional_missing
  // inert, so "f missing" leaked into FailureData.errors alongside the
  // real downstream failure ("n missing"). With head_elem_names the
  // internal "f" is dropped, only the head-external "n" missing remains.
  let defs : Map[String, Node] = Map([])
  let inner : Scope = {
    greedy: [],
    positional: [StrArg("f", [])],
    entities: [],
    constraints: [],
  }
  defs.set("r", Seq([ScopeNode(inner)]))
  let root : Scope = {
    greedy: [],
    positional: [Ref("r"), NumArg("n", false, [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a"], defs~)
  match o {
    Failure(fd) => {
      let mut saw_n_missing = false
      let mut saw_f_missing = false
      for e in fd.errors {
        if e.reason == "missing_operand" && e.element == "n" {
          saw_n_missing = true
        }
        if e.reason == "missing_operand" && e.element == "f" {
          saw_f_missing = true
        }
      }
      assert_true(saw_n_missing)
      assert_false(saw_f_missing)
    }
    _ => fail("expected Failure")
  }
}

///|
test "REGRESSION Or-wrapped greedy: find_help_entry / tried_triggers walk Or arms" {
  // deep-review REVIEW-O4: help_entry / tried_triggers must reflect Or-
  // bundled greedy entries (step_greedy treats each alt as its own
  // interjection). Before the outcome.mbt fix, an Or-wrapped --help was
  // invisible to both materials. Input ["--typo"] fails — help_entry
  // should carry "--help" and tried_triggers should list both "--help"
  // and "--verbose".
  let root : Scope = {
    greedy: [
      Or([
        Seq([Exact("--help"), Bind("help", VBool(true)), FailMark("help")]),
        Seq([Exact("--verbose"), Bind("v", VBool(true))]),
      ]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--typo"], defs=Map([]))
  match o {
    Failure(fd) => {
      assert_eq(fd.help_entry, Some("--help"))
      let mut saw_help = false
      let mut saw_verbose = false
      for t in fd.tried_triggers {
        if t == "--help" {
          saw_help = true
        }
        if t == "--verbose" {
          saw_verbose = true
        }
      }
      assert_true(saw_help)
      assert_true(saw_verbose)
    }
    _ => fail("expected Failure")
  }
}

///|
/// DR-053 §4 (issue 2026-07-08 greedy-once-and-idxrepeat-premises §3, resolved): tried_triggers is
/// the triggers available AT THE FAILURE POSITION (§4 immediately follows §2's "primary の定義:
/// args 位置が最深の Error" in the same DR), not always root's — DR-041 §4 "読める最内スコープが勝つ"
/// means a failure INSIDE a subcommand's own scope should surface that scope's OWN greedy triggers.
/// `sub zzz` ("zzz" is an unconsumed residual inside "sub"'s scope, whose only positional-face
/// element is none — a bare unexpected_token) used to report only root's "sub" command name;
/// now it reports "sub"'s own `--port` trigger, the one actually offered at the failure site.
test "DR-053 §4: tried_triggers reflects the failure position's OWN scope, not root's" {
  let child : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port", false, [])])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "zzz"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut saw_port = false
      let mut saw_sub = false
      for t in fd.tried_triggers {
        if t == "--port" {
          saw_port = true
        }
        if t == "sub" {
          saw_sub = true
        }
      }
      assert_true(saw_port)
      assert_false(saw_sub) // root's "sub" is NOT the failure-position scope
    }
    _ => fail("expected Failure (residual 'zzz' inside sub's scope)")
  }
}

///|
/// spec issue conformance-tried-triggers-help-entry-fields (fixture failure-actions/tried-
/// triggers-scope.json の subcommand-scope-excludes-ancestor-spelling を実機確認して発覚):
/// `find_help_entry` は旧実装が root scope の greedy しか見ておらず、サブコマンドの子スコープに
/// 宣言された help 入口を見逃していた — `tried_triggers_of` と同じ「失敗位置のスコープ基準」
/// (DR-053 §4) に揃えて修正した、そのpin。root に help 入口は無く、sub 子スコープにのみ help が
/// ある構成で、sub 内での失敗が sub 自身の help_entry ("--help") を正しく報告することを固定する
/// (旧実装なら root scope に help entry が無いので None を返していたはず)。
test "DR-053 §4: help_entry reflects the failure position's OWN scope, not root's (find_help_entry fix)" {
  let child : Scope = {
    greedy: [
      Seq([Exact("--help"), Bind("help", VBool(true)), FailMark("help")]),
      Seq([Exact("--port"), NumArg("port", false, [])]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "zzz"], defs=Map([]))
  match o {
    Failure(fd) => assert_eq(fd.help_entry, Some("--help"))
    _ => fail("expected Failure (residual 'zzz' inside sub's scope)")
  }
}

///|
/// 保証 (対極、上のテストの境界、[[self-written-rule-blind-spots]] の対極確認): root scope に help
/// 入口が無く、失敗も root scope 自身で起きる (sub へ入場しない) 場合は、旧来どおり None を返す —
/// 「失敗位置スコープ基準」への変更が「常に何かの help_entry を拾ってしまう」誤動作を生んでいない
/// ことを固定する。
test "DR-053 §4: help_entry is None when the failure-position scope has no help entry (対極)" {
  let child : Scope = {
    greedy: [
      Seq([Exact("--help"), Bind("help", VBool(true)), FailMark("help")]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["zzz"], defs=Map([]))
  match o {
    Failure(fd) => assert_eq(fd.help_entry, None)
    _ =>
      fail(
        "expected Failure (residual 'zzz' in root scope, never entering sub)",
      )
  }
}

///|
test "REVIEW-D1 取り分選好オラクルは制約違反の全消費を「完全」と数えない (DR-047 §2 × DR-043)" {
  // more 側 (xs=[a,b]) は全消費だが CRequires(xs,[y]) に違反 = 完全解決経路
  // ではない。stop 側 (xs=[a], y=[b]) が唯一の完全解決経路なので Success。
  //
  // issue value-present-ladder-gap 裁定 2026-07-10 (更新): CRequires/CRequiresIf の目的語判定は
  // 全て KTop からスキップされ `resolve.mbt` の `apply_requires_filter` (post-parse) へ委譲される
  // ようになった (DR-047 §4「遅延述語は値源ラダー充填後の最終状態で評価する」の実装形)。よって
  // has_full_k (選好オラクル) はもう CRequires 違反を見分けられず、`parse()` 単体では stop/more
  // 両方が Accept (= Ambiguous 2 本) になる — 「完全経路」の絞り込みは `apply_requires_filter` の
  // 候補 drop (DR-047 §6「制約が ambiguous の解消に参加する」の実現箇所が KTop → post-filter へ
  // 移った、観測同値) が担う。本 wbtest は `apply_requires_filter` を通した最終結果を確認する。
  // `apply_requires_filter` の目的語判定は `resolve_scope_tree` が実際に解決した値を読むので
  // (自前ラダー無し)、`xs`/`y` は resolve が拾える `Entity` として宣言する必要がある (旧 KTop 直読み
  // 時代の `entities: []` のままでは、resolve が両セルとも存在しないものとして扱ってしまう)。
  let defs : Map[String, Node] = Map([])
  reg_repeat(defs, "xs", StrArg("xs", []))
  let root : Scope = {
    greedy: [],
    positional: [Ref("xs"), Many(StrArg("y", []), false)],
    entities: [
      ent("xs", TStr, accum=Some("append"), flatten=true),
      ent("y", TStr, accum=Some("append"), flatten=true),
    ],
    constraints: [CRequires("xs", ["y"])],
  }
  let root_node = ScopeNode(root)
  let o = apply_requires_filter(
    parse(root_node, ["a", "b"], defs~),
    root_node,
    defs,
    Map([]),
    2,
  )
  match o {
    Success(bs) => {
      let mut xs_count = 0
      let mut y_count = 0
      for b in bs {
        if b.key == "xs" {
          xs_count = xs_count + 1
        }
        if b.key == "y" {
          y_count = y_count + 1
        }
      }
      assert_eq(xs_count, 1)
      assert_eq(y_count, 1)
    }
    other =>
      fail("expected Success (xs=[a], y=[b]), got " + render_outcome(other))
  }
}

///|
test "REVIEW-D2 制約照合は scope-exact: 子スコープの同名 key は root 制約を発火させない (DR-055 §1 lexical)" {
  // 子スコープの x (scope=["c"]) だけが commit される入力。root 宣言の
  // CRequires("x",[...]) の対象は root の x セルなので不活性 = Success。
  let child : Scope = {
    greedy: [],
    positional: [StrArg("x", [])],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("c", child)],
    positional: [],
    entities: [],
    constraints: [CRequires("x", ["z"])],
  }
  let o = parse(ScopeNode(root), ["c", "v"], defs=Map([]))
  match o {
    Success(_) => ()
    _ => fail("expected Success (root x is uncommitted)")
  }
}

///|
test "REVIEW-D3 誤充足も塞ぐ: requires のターゲットは子スコープの同名 binding では満たされない" {
  // root の file が commit、requires ターゲット out は子スコープにしか
  // commit されない → root の out は不在なので requires_violated の Failure
  // が正 (旧実装は key 名一致で誤充足して Success にしていた)。
  //
  // issue value-present-ladder-gap 裁定 2026-07-10 (更新): CRequires 目的語判定は KTop から
  // apply_requires_filter (post-parse) へ委譲された — scope-exact 判定自体 (`elem_value` の
  // `scope_path_eq` フィルタ) は変わらないので、`apply_requires_filter` を通した結果で確認する。
  let child : Scope = {
    greedy: [Seq([Exact("--out"), Bind("out", VBool(true))])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [
      Seq([Exact("--file"), Bind("file", VBool(true))]),
      CmdSat("sub", child),
    ],
    positional: [],
    entities: [],
    constraints: [CRequires("file", ["out"])],
  }
  let root_node = ScopeNode(root)
  let o = apply_requires_filter(
    parse(root_node, ["--file", "sub", "--out"], defs=Map([])),
    root_node,
    Map([]),
    Map([]),
    3,
  )
  match o {
    Failure(fd) => {
      let mut viol = false
      for e in fd.errors {
        if e.element == "file" && e.reason == "requires_violated" {
          viol = true
        }
      }
      assert_true(viol)
    }
    _ => fail("expected Failure (root out is not committed)")
  }
}

///|
test "REVIEW-D4 入れ子スコープの constraints も完全経路の成立条件 (DR-047 §2 に宣言スコープ免除なし)" {
  // 子スコープ宣言の CConflicts(x,[y]) が sub 内の --x --y 同時 commit を
  // 弾く。旧実装は root 直下の constraints しか評価していなかった。
  let child : Scope = {
    greedy: [
      Seq([Exact("--x"), Bind("x", VBool(true))]),
      Seq([Exact("--y"), Bind("y", VBool(true))]),
    ],
    positional: [],
    entities: [],
    constraints: [CConflicts("x", ["y"])],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "--x", "--y"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut viol = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "conflicts_with_violated" {
          viol = true
        }
      }
      assert_true(viol)
    }
    _ => fail("expected Failure (child-scope conflicts)")
  }
}

///|
test "DR-097 (先食い述語の精密化, supersedes REVIEW-D5): 値不正の --port は読みゼロ扱いで positional に raw 落ちする" {
  // `--port xyz`: --port のトリガは一致するが値 "xyz" が number 照合に失敗し、
  // この読み自身は成立しない (DR-097「読める」= 読み自身の成立、値空間照合
  // (parse 相) を通ること)。成立する読みが無い消費点は読みゼロと同じ扱いに
  // なり、素通し枝が生きる — 寛容な positional 2 つが f="--port", g="xyz" を
  // raw 消費して Success になる (held Error の not_a_number は素通し側の
  // 完全経路が通るため DR-037「他ルートが通るならエラーは捨てる」で捨てられ
  // る)。REVIEW-D5 が固定していた「トリガ一致のみで先食い成立」という
  // 旧述語は DR-097 で置き換えられた (DR-041 §4 の Superseded 節)。
  let root : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port", false, [])])],
    positional: [StrArg("f", []), StrArg("g", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["--port", "xyz"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut f_raw = false
      let mut g_raw = false
      for b in bs {
        match (b.key, b.value) {
          ("f", VStr(s)) => if s == "--port" { f_raw = true }
          ("g", VStr(s)) => if s == "xyz" { g_raw = true }
          _ => ()
        }
      }
      assert_true(f_raw)
      assert_true(g_raw)
    }
    _ =>
      fail(
        "expected Success (f=\"--port\", g=\"xyz\" raw-eaten, DR-097 読みゼロ)",
      )
  }
}

///|
test "DR-097 述語 pin: 値スロットを持たない flag は常に成立し先食いを維持する (下流の失敗に関わらず)" {
  // greedy `-b` (flag, 値スロットなし) の直後に構造的必須 positional `x`
  // (string) を置く。args=["-a","-b"] は x の値トークンが尽きているので
  // x は missing_operand で失敗するが、これは -b 自身の読みとは無関係な
  // 下流の帰結 — DR-097 は「値スロットを持たない flag/count/dd/command は
  // 常に成立」と明記しており、下流で経路が死ぬ場合も先食いは維持される
  // (spec 決定節「下流で経路が死ぬ場合 (制約未充足・同スコープの他要素の
  // 欠落等) も維持され、その失敗は held Error 付きの failure として可視の
  // まま残る」)。つまり -b は x に raw 落ちせず、b=true が commit され、
  // x の missing_operand だけが可視 failure として残る。fixture の
  // matcher-readings/* 系は値持ち option の読み不成立 (値照合失敗) だけを
  // 対象にしており、値スロットなしエントリの「常に成立」側はこの wbtest が
  // 唯一の pin (fixture と重複しない軸)。
  let root : Scope = {
    greedy: [
      Seq([Exact("-a"), Bind("a", VBool(true))]),
      Seq([Exact("-b"), Bind("b", VBool(true))]),
    ],
    positional: [StrArg("x", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["-a", "-b"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut x_missing = false
      let mut b_raw_eaten = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "missing_operand" {
          x_missing = true
        }
        if e.element == "x" && e.reason == "not_a_number" {
          // would only happen if -b were raw-eaten into x (it never is: x is
          // string-typed, so a raw-eat would silently SUCCEED as x="-b" —
          // this branch exists only to document the shape a regression
          // would take, not because it is reachable via this Held path.
          b_raw_eaten = true
        }
      }
      assert_true(x_missing)
      assert_false(b_raw_eaten)
    }
    Success(_) =>
      fail(
        "expected Failure (missing operand for x; a silent x=\"-b\" Success would mean -b's ALWAYS-viable flag reading was wrongly suppressed)",
      )
    _ => fail("expected Failure")
  }
}

///|
test "DR-097 述語 pin: requires (遅延述語) 未充足は先食い判定に参加しない — 読み自身が成立していれば維持される" {
  // `--height <num>` (requires: weight) + 寛容な positional `rest` (repeat
  // min 0)。args=["--height","168.5"] は height の読み自身は成立する (値
  // 168.5 は number 照合を通る) — DR-097「下流の帰結 (同スコープの他要素の
  // 充足、遅延述語 §15.9、後続トークンの成否) は判定に参加しない」により、
  // weight の未充足 (遅延述語、requires) は先食い判定を一切左右しない:
  // height は正しく commit され、168.5 は rest に raw 落ちしない。
  // apply_requires_filter (DR-047 §4 の post-parse requires 評価) を通すと
  // requires_violated の可視 failure になる — これは「height が正しく
  // commit された」ことの間接証拠 (旧述語のように 168.5 が rest に格下げ
  // されていれば height 自体が commit されず requires のトリガも立たない)。
  // spec 不変ノート「制約 (遅延述語) の未充足は先食い・早閉じに影響しない」
  // の先食い側 pin — 早閉じ側は fixture
  // command-scope/early-close-viability.json::constraint-not-consulted-on-exit
  // が既に固定しているので、ここでは重複させず先食い側のみ固定する。
  let root : Scope = {
    greedy: [Seq([Exact("--height"), NumArg("height", false, [])])],
    positional: [Many(StrArg("rest", []), false)],
    entities: [ent("height", TNum), ent("weight", TStr)],
    constraints: [CRequires("height", ["weight"])],
  }
  let root_node = ScopeNode(root)
  let toks = ["--height", "168.5"]
  let o = apply_requires_filter(
    parse(root_node, toks, defs=Map([])),
    root_node,
    Map([]),
    Map([]),
    toks.length(),
  )
  match o {
    Failure(fd) => {
      let mut height_requires_violated = false
      for e in fd.errors {
        if e.element == "height" && e.reason == "requires_violated" {
          height_requires_violated = true
        }
      }
      assert_true(height_requires_violated)
    }
    _ =>
      fail(
        "expected Failure (height requires_violated; height's reading held despite the unmet requires)",
      )
  }
}

///|
test "REVIEW-D6 CmdSat トリガ一致も先食い: 子スコープ不成立でも command 名は raw 落ちしない" {
  // `build` が最終トークンで子スコープの必須 positional x が満たせない場合、
  // 旧実装は CmdSat の読みが立たず build が親 positional f に raw 落ちして
  // silent Success になっていた。トリガ (command 名) 一致で suppress し、
  // 結末は x の missing_operand を含む Failure。
  let child : Scope = {
    greedy: [],
    positional: [StrArg("x", [])],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("build", child)],
    positional: [StrArg("f", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["build"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut x_missing = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "missing_operand" {
          x_missing = true
        }
      }
      assert_true(x_missing)
    }
    _ => fail("expected Failure (missing operand for x)")
  }
}

///|
/// DR-074 §1: `FloatArg` accepts the wider float lexicon (number + inf, case-insensitive) that
/// `NumArg` (canonical `number`) rejects — the two node kinds are how the CLI-lowered AST carries
/// the type-dependent accept-域 once `Ty::TNum`/`Ty::TFloat` info is otherwise gone (fixtures
/// value-typing/number-inf-nan.json's `--t`(float)/`--n`(number) split).
test "DR-074 §1: FloatArg accepts inf (ci, signed), NumArg rejects it" {
  let root : Scope = {
    greedy: [
      Seq([Exact("--t"), FloatArg("t", [])]),
      Seq([Exact("--n"), NumArg("n", false, [])]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  // float accepts inf, case-insensitive, and a signed spelling.
  for tok in ["inf", "Infinity", "-inf", "+INF"] {
    match parse(ScopeNode(root), ["--t", tok], defs=Map([])) {
      Success(bs) => {
        let mut t_ok = false
        for b in bs {
          if b.key == "t" {
            match b.value {
              VNum(_) => t_ok = true
              _ => ()
            }
          }
        }
        assert_true(t_ok)
      }
      _ => fail("expected Success for --t \{tok}")
    }
  }
  // number rejects inf (type-dependent accept-域 boundary, DR-074 §1) — the SAME lexeme fails here.
  match parse(ScopeNode(root), ["--n", "inf"], defs=Map([])) {
    Failure(fd) => {
      let mut n_not_a_number = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          n_not_a_number = true
        }
      }
      assert_true(n_not_a_number)
    }
    _ => fail("expected Failure for --n inf")
  }
  // nan is Error for BOTH types (§1: no lexeme, no opt-in) — float does not treat nan as an inf variant.
  match parse(ScopeNode(root), ["--t", "nan"], defs=Map([])) {
    Failure(fd) => {
      let mut t_not_a_number = false
      for e in fd.errors {
        if e.element == "t" && e.reason == "not_a_number" {
          t_not_a_number = true
        }
      }
      assert_true(t_not_a_number)
    }
    _ => fail("expected Failure for --t nan")
  }
}

///|
/// REGRESSION scope_consume: a BARE positional `FloatArg` (not wrapped in a greedy
/// Seq/Exact satellite) must respect 先食い (suppressed) just like NumArg/IntArg/ReqArg do
/// (docs/issue/2026-07-08-floatarg-spine-arm-gap.md). Without a dedicated FloatArg arm in
/// `scope_consume`, the item falls to the generic `other => eval(other, ctx, pos)` catch-all,
/// which has no access to the parent scope and so cannot call `suppressed()` — it tries to
/// parse the token as a float regardless of a competing greedy trigger at that position. Here
/// the trigger text IS itself a valid float lexeme (DR-074 §1's `"inf"`), so the raw-eat does
/// NOT fail loudly — it silently SUCCEEDS as `x=inf`, stealing the token that should have fired
/// the greedy `verbose` trigger and leaving `x` never correctly re-evaluated as starved. Correct
/// behavior: 先食い means the greedy trigger wins at this position, `x`'s positional slot never
/// gets a token, and the parse ends in Failure (missing_operand for x) — NOT a silent Success.
test "REGRESSION scope_consume FloatArg respects 先食い (raw-eat suppression)" {
  let root : Scope = {
    greedy: [Seq([Exact("inf"), Bind("verbose", VBool(true))])],
    positional: [FloatArg("x", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["inf"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut x_missing = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "missing_operand" {
          x_missing = true
        }
      }
      assert_true(x_missing)
    }
    _ =>
      fail(
        "expected Failure (missing operand for x; the greedy 'inf' trigger wins 先食い — a raw-eaten x=inf is the bug)",
      )
  }
}

///|
/// REGRESSION consume_head: a Ref-repeat over a `FloatArg` head must respect 先食い, mirroring
/// the established ReqArg precedent above ("REGRESSION consume_head ReqArg respects 先食い").
/// Without the FloatArg arm in `consume_head`, the repeat's "one more rep" attempt raw-eats the
/// greedy trigger token "inf" as ANOTHER float value (again silently, since "inf" parses) instead
/// of stopping at 1 rep and letting the greedy `verbose` entry fire on it. Correct: `fs` = [1.5],
/// `verbose` = true.
test "REGRESSION consume_head FloatArg respects 先食い (raw-eat suppression)" {
  let defs : Map[String, Node] = Map([])
  defs.set("fs", Seq([FloatArg("f", [])]))
  let root : Scope = {
    greedy: [Seq([Exact("inf"), Bind("verbose", VBool(true))])],
    positional: [Ref("fs")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["1.5", "inf"], defs~)
  match o {
    Success(bs) => {
      let mut f_count = 0
      let mut verbose_ok = false
      for b in bs {
        if b.key == "f" {
          f_count = f_count + 1
        }
        if b.key == "verbose" {
          match b.value {
            VBool(v) => if v { verbose_ok = true }
            _ => ()
          }
        }
      }
      assert_eq(f_count, 1)
      assert_true(verbose_ok)
    }
    _ =>
      fail(
        "expected Success (verbose fires via 'inf' trigger, fs=[1.5] — raw-eating fs=[1.5,inf] with no verbose is the bug)",
      )
  }
}

///|
/// REGRESSION scope_consume_rep: `Many(FloatArg(...))` as a repeat head must respect 先食い
/// (DR-043 spec, same concern as the Ref-based case above but through the `Many` node instead of
/// a registry Ref). Without the FloatArg arm in `scope_consume_rep`, the catch-all `_ => eval(inner,
/// ...)` ignores `suppressed()` and the "more rep" branch raw-eats "inf" as f=[1.5, inf] — and since
/// `Many`'s greedy-only 取り分選好 (eval.mbt ~1231 `has_full_k(more) => more`) prefers the MORE-rep
/// branch whenever it reaches a full parse, this wrong reading wins OUTRIGHT (not merely Ambiguous).
/// Correct: f=[1.5], verbose=true (1 rep, then the greedy trigger fires on "inf").
test "REGRESSION scope_consume_rep Many(FloatArg) respects 先食い (raw-eat suppression)" {
  let root : Scope = {
    greedy: [Seq([Exact("inf"), Bind("verbose", VBool(true))])],
    positional: [Many(FloatArg("f", []), false)],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["1.5", "inf"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut f_count = 0
      let mut verbose_ok = false
      for b in bs {
        if b.key == "f" {
          f_count = f_count + 1
        }
        if b.key == "verbose" {
          match b.value {
            VBool(v) => if v { verbose_ok = true }
            _ => ()
          }
        }
      }
      assert_eq(f_count, 1)
      assert_true(verbose_ok)
    }
    _ =>
      fail(
        "expected Success (verbose fires via 'inf' trigger, f=[1.5] — raw-eating f=[1.5,inf] with no verbose is the bug)",
      )
  }
}

///|
/// REGRESSION (codex 節目レビュー指摘3, issue 2026-07-09-ref-template-result-shape): the SAME
/// suppression gap as the `Many(FloatArg(...))` test just above, but for a `ref` element's
/// UNBOUNDED `min:0` repeat — installer.mbt's `lower_repeat_head` lowers that shape to
/// `Many(head, lazy)` where `head` is `ref_row_head`'s wrap (`Scoped(name, Seq([Bind("#row",_),
/// Ref(target)]))`), a COMPOUND node, never a bare primitive. `scope_consume_rep`'s catch-all used
/// to degrade to plain off-spine `eval` for any non-primitive `inner` — which has no `Scope` and so
/// could never apply 先食い (DR-041 §4) to the leaf (`colorname`, reached through
/// Scoped→Seq→Ref→Or) — `consume_compound` now threads `sc`/`severed` down instead (same fix
/// applied to `scope_consume`'s "other" positional-item arm, mirrored `consume_head` catch-all
/// fix). No spec fixture exists for this shape yet (option/positional ref+repeat `min:0` — a
/// separate spec-side issue tracks fixture-izing this輪郭, per team-lead); this wbtest pins the
/// kuu.mbt-side regression fix directly, hand-building the lowered shape (mirrors the
/// `Many(FloatArg(...))` regression test's own style just above).
test "REGRESSION scope_consume_rep Many(compound ref-template head) respects 先食い (codex review #3)" {
  // `color := colorname:string` (単純化 — Or 分岐は本 regression の本質と無関係)。`hlcolors` は
  // `{"name":"hlcolors","ref":"color","repeat":{"min":0}}` の lowering そのもの。
  let head = Scoped("hlcolors", Seq([Bind("#row", VBool(false)), Ref("color")]))
  let root : Scope = {
    greedy: [Seq([Exact("--verbose"), Bind("verbose", VBool(true))])],
    positional: [Many(head, false)],
    entities: [],
    constraints: [],
  }
  let defs : Map[String, Node] = Map([("color", StrArg("colorname", []))])
  let o = parse(ScopeNode(root), ["red", "--verbose"], defs~)
  match o {
    Success(bs) => {
      let mut colorname_count = 0
      let mut verbose_ok = false
      for b in bs {
        if b.key == "colorname" {
          colorname_count = colorname_count + 1
        }
        if b.key == "verbose" {
          match b.value {
            VBool(v) => if v { verbose_ok = true }
            _ => ()
          }
        }
      }
      assert_eq(colorname_count, 1)
      assert_true(verbose_ok)
    }
    other =>
      fail(
        "expected Success (--verbose fires, hlcolors=[colorname:red] only — raw-eating '--verbose' as a 2nd colorname rep with no verbose fire is the bug), got " +
        render_outcome(other),
      )
  }
}

///|
/// REGRESSION head_elem_names_into: a `FloatArg` repeat head's name must be collected into the
/// DR-065 §3 held-error-parity name set (`drop_optional_missing` reads this to suppress a spurious
/// missing_operand for an optional repeat's "one more" phantom rep) — mirroring the existing
/// StrArg/NumArg/IntArg/ReqArg arms. This is a narrower, more direct probe of the same 4th function
/// named in the issue than the end-to-end parse() scenarios above.
test "REGRESSION head_elem_names_into collects a FloatArg head's name" {
  let out : Array[String] = []
  head_elem_names_into(FloatArg("f", []), out)
  assert_eq(out, ["f"])
}

// ── DR-066 §4: path/provenance on held Errors ────────────────────────────────

///|
/// A held Error at the ROOT scope carries `path: []` (root 直下, DR-066 §4):
/// no CmdSat/Scoped boundary was crossed on the way out, so there is no
/// ancestor to record.
test "DR-066 §4: a root-level held Error carries path: []" {
  let root : Scope = {
    greedy: [],
    positional: [NumArg("n", false, [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          found = true
          assert_eq(e.path, [])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (\"abc\" is not a number)")
  }
}

///|
/// A held Error one CmdSat deep carries `path: [<command name>]` (DR-066 §4
/// snoc form: `path` = ancestors, `element` = self). The error fires INSIDE
/// the child scope (a bare `NumArg` parse failure straight from `eval`,
/// `path: []` at construction) and crosses exactly one command boundary on
/// its way out through `step_greedy`'s CmdSat arm.
test "DR-066 §4: a held Error one command deep carries path: [\"sub\"]" {
  let child : Scope = {
    greedy: [],
    positional: [NumArg("n", false, [])],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          found = true
          assert_eq(e.path, ["sub"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (\"abc\" is not a number)")
  }
}

///|
/// A held Error two CmdSat levels deep carries `path: ["a", "b"]` (root-first,
/// DR-066 §4): the error crosses TWO command boundaries on its way out — "b"
/// prepends first (innermost, its own step_greedy loop), then "a" prepends in
/// front of that (its parent's), landing root-first as the CPS Held bubbles
/// out through both KNest/CmdSat crossings.
test "DR-066 §4: a held Error two commands deep carries path: [\"a\", \"b\"] (root-first)" {
  let grandchild : Scope = {
    greedy: [],
    positional: [NumArg("n", false, [])],
    entities: [],
    constraints: [],
  }
  let child : Scope = {
    greedy: [CmdSat("b", grandchild)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("a", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "abc"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "n" && e.reason == "not_a_number" {
          found = true
          assert_eq(e.path, ["a", "b"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (\"abc\" is not a number)")
  }
}

///|
/// A CRequires violation declared in a CHILD scope still carries the child's path (DR-066 §4).
///
/// issue value-present-ladder-gap 裁定 2026-07-10 (更新): CRequires 目的語判定は KTop から
/// `apply_requires_filter` (post-parse) へ委譲された — 評価点が移っても path 帰属は不変であること
/// を固定する。post-filter 側 (`resolve.mbt` `eval_requires`) は `ScopedCons.path` (= 制約の宣言
/// スコープの result-nesting path、`resolve_tree`/`collect_scopes` が組み立てる) を直接
/// struct-update で埋める方式 (KTop の「path: [] で始めて境界ごとに prepend」方式とは違う実装形だが
/// 同じ観測結果になる) — 旧来 KTop 経由で確認していたのと同じ `["sub"]` が出ることを確認する。
test "DR-066 §4: a constraint violation declared in a child scope carries the child's path" {
  let child : Scope = {
    greedy: [Seq([Exact("--x"), Bind("x", VBool(true))])],
    positional: [],
    entities: [],
    constraints: [CRequires("x", ["y"])],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root_node = ScopeNode(root)
  let o = apply_requires_filter(
    parse(root_node, ["sub", "--x"], defs=Map([])),
    root_node,
    Map([]),
    Map([]),
    2,
  )
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "x" && e.reason == "requires_violated" {
          found = true
          assert_eq(e.path, ["sub"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure ('x' requires 'y', unsatisfied)")
  }
}

///|
/// A residual-token Error (spec DR-065 §3: unconsumed trailing token at KTop)
/// carries `path: []` — it is inherently a root/global-position stumble (the
/// WHOLE parse, not any one scope, failed to consume the rest), so there is
/// no ancestor scope to attribute it to even when it surfaces after crossing
/// into a nested scope during the walk.
test "DR-066 §4: a residual-token Error carries path: []" {
  let root : Scope = {
    greedy: [],
    positional: [Exact("go")],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["go", "zzz"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.reason == "unexpected_token" {
          found = true
          assert_eq(e.path, [])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (residual token 'zzz')")
  }
}

///|
/// DR-066 §4 (issue 2026-07-08 pending-starvation-missing-operand-path): a Pending's
/// starved value slot converts to a `missing_operand` Error at parse()'s top level
/// (MDR-002 §2.3). That conversion point sat OUTSIDE the CPS scope-boundary prepend
/// (`nest_branches` / `step_greedy`'s CmdSat case) that a Held's `ParseError.path`
/// already rode through, so nested-scope starvation always surfaced `path: []` no
/// matter how deep the starved slot actually was. `sub --port` (no value token after
/// `--port`) starves the value slot at input end one command-scope deep.
test "DR-066 §4: a Pending-starvation missing_operand Error inside a nested command carries the ancestor path" {
  let child : Scope = {
    greedy: [Seq([Exact("--port"), NumArg("port", false, [])])],
    positional: [],
    entities: [],
    constraints: [],
  }
  let root : Scope = {
    greedy: [CmdSat("sub", child)],
    positional: [],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["sub", "--port"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "port" && e.reason == "missing_operand" {
          found = true
          assert_eq(e.path, ["sub"])
        }
      }
      assert_true(found)
    }
    _ => fail("expected Failure (missing operand for port)")
  }
}

///|
/// KNOWN GAP (issue 2026-07-08 greedy-once-and-idxrepeat-premises §2, kawaz 裁定待ち):
/// `idx_repeat_eval`'s greedy-max is deterministic with NO downstream backtrack (see its doc
/// comment) — unlike the normal Ref-repeat path, which `ref_choice` backs off one rep at a time on
/// downstream failure (fixture repeat-parse/backtrack.json fixes this for the common case). A
/// permissive head (bare `StrArg`, matches any token) followed by a mandatory positional starves
/// that positional: greedy-max consumes ALL 3 tokens into the repeat, leaving nothing for `tail`,
/// and there is no backtrack to try `g=[a,b], tail=c` instead. This test PINS the current (gap)
/// behavior so a future backtrack fix flips it to Success and this assertion catches the flip —
/// do NOT "fix" this test to make it pass differently without updating the issue. installer.mbt's
/// BGroup lowering comment documents the "bounded-head" workaround (give the head an explicit
/// leading trigger) until this is resolved one way or the other.
test "KNOWN GAP: IdxRepeat greedy-max has no downstream backtrack for a following mandatory positional" {
  let root : Scope = {
    greedy: [],
    positional: [IdxRepeat("g", StrArg("x", []), 1, None), StrArg("tail", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut tail_missing = false
      for e in fd.errors {
        if e.element == "tail" && e.reason == "missing_operand" {
          tail_missing = true
        }
      }
      assert_true(tail_missing)
    }
    _ =>
      fail(
        "gap behavior changed: expected Failure (tail starved, no backtrack) — if this now succeeds, the backtrack gap is fixed; update this test and the issue accordingly",
      )
  }
}

///|
/// 保証 (issue 2026-07-13-positional-group-trailing-missing-operand): `budget=Some(0)` (a bounded
/// `repeat:{min:1,max:1}` spec lowers to this, installer.mbt's BGroup case) does NOT hit the
/// KNOWN GAP above — it never over-consumes in the first place, so no backtrack is needed to
/// correct it. Same shape as the KNOWN GAP test (permissive head `StrArg("x")` immediately
/// followed by a mandatory `tail`) but with the budget field set and an args sized to exactly
/// `min + tail's own 1 token = 2`: exactly 1 rep is taken (not greedy-max over everything), so
/// `tail` gets the 2nd token instead of starving — mirrors the fixture's `["a","b"]` shape
/// exactly (`fixtures/repeat-parse/group-trailing-positional.json::group-then-scalar-consumed`).
test "IdxRepeat budget=Some(0): stops after min reps, does not starve a following mandatory positional" {
  let root : Scope = {
    greedy: [],
    positional: [
      IdxRepeat("g", StrArg("x", []), 1, Some(0)),
      StrArg("tail", []),
    ],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut g_count = 0
      let mut tail_val : String? = None
      for b in bs {
        if b.key == "x" {
          g_count = g_count + 1
        }
        if b.key == "tail" {
          tail_val = Some(value_str(b.value))
        }
      }
      // budget=0 → exactly 1 rep (min), NOT greedy-max over both tokens.
      assert_eq(g_count, 1)
      assert_eq(tail_val, Some("b"))
    }
    other =>
      fail(
        "expected Success (budget bounds the repeat so tail no longer starves), got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証: `budget=Some(1)` (a bounded `repeat:{min:1,max:2}` spec) allows up to `min+budget=2`
/// reps and stops there — confirms budget is a genuine upper bound (not just an on/off switch
/// at 0) by observing how much the repeat consumes before yielding to `tail`.
test "IdxRepeat budget=Some(1): consumes up to min+budget=2 reps, leaves the rest for tail" {
  let root : Scope = {
    greedy: [],
    positional: [
      IdxRepeat("g", StrArg("x", []), 1, Some(1)),
      StrArg("tail", []),
    ],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["a", "b", "c"], defs=Map([]))
  match o {
    Success(bs) => {
      let mut g_count = 0
      let mut tail_val : String? = None
      for b in bs {
        if b.key == "x" {
          g_count = g_count + 1
        }
        if b.key == "tail" {
          tail_val = Some(value_str(b.value))
        }
      }
      assert_eq(g_count, 2)
      assert_eq(tail_val, Some("c"))
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// 保証 (issue 2026-07-09-positional-or-repeat-lowering-gap の slice-equivalent 確認): 手組み
/// `Many(Or([Seq(rgb), StrArg(name)]))` は元々 (installer 経由の wire lowering ギャップとは独立に)
/// 両 or 枝が並列に反復できる — evaluator 自体 (Many の取り分選好、Or の全枝保持) には問題が無く、
/// ギャップは installer.mbt の `lower_positional` BOr ケースが `elem_repeat` を無視していたことに
/// 限定される (installer_wbtest.mbt の対応する wire テストと対で、evaluator 層 / installer 層のどちら
/// が壊れていたかを切り分ける)。
test "DR-043 × DR-038: hand-built Many(Or(seq-rgb, string-name)) lets both or-branches repeat" {
  let head = Or([
    Seq([NumArg("r", false, []), NumArg("g", false, []), NumArg("b", false, [])]),
    StrArg("name", []),
  ])
  let root : Scope = {
    greedy: [],
    positional: [Many(head, false)],
    entities: [],
    constraints: [],
  }
  // ["red", "blue"]: 2 non-numeric tokens — only the string branch can fire (twice) → success.
  match parse(ScopeNode(root), ["red", "blue"], defs=Map([])) {
    Success(bs) => {
      let mut names = 0
      for b in bs {
        if b.key == "name" {
          names = names + 1
        }
      }
      assert_eq(names, 2)
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
  // ["255", "0", "0"]: 3 numeric tokens — BOTH readings succeed (rgb once, OR name x3) → ambiguous.
  match parse(ScopeNode(root), ["255", "0", "0"], defs=Map([])) {
    Ambiguous(d) => assert_eq(d.interpretations.length(), 2)
    other => fail("expected Ambiguous, got " + render_outcome(other))
  }
}

// ── DR-047: 遅延述語は完全経路の成立条件 (KTop path filter) ──────────────────────
//
// issue 2026-07-09-constraint-path-filtering-gap の設計調査で得た pin。core engine
// (cont.mbt の KTop / eval_all_constraints) が DR-047 §2 「制約を満たさない経路は完全経路と
// 数えない」を正しく実装していることを、installer/decode を経由しない raw Node/Scope 構築で
// 直接検証する (一次資料)。issue の実測 (alias 経由の 2 経路 + 片方 requires 未充足で
// ambiguous:2) は、後続の調査で「requires の目的語がフラグ型セル (LOWERING §A.5 の暗黙
// default:false を必ず持つ) だったため、DR-047 §5 の「requires 目的語側=値の有無」判定が
// その暗黙 default で常に充足してしまう (vacuous satisfaction)」ことが原因と判明した — KTop
// 自体のフィルタは正しく動いている (下の 2 wbtest が実証)。フラグ target の vacuous
// satisfaction 自体は別途 3 本目の wbtest で固定する (installer_wbtest.mbt 参照)。

///|
/// 保証: slice `poc/phase25_wbtest.mbt:225` の直接移植。`x` の 2 通りの完全経路 (foo+bar を
/// 両方 commit する経路 / foo だけを commit する経路) のうち、`CConflicts("foo",["bar"])` が
/// 前者を完全経路から除外し、後者 1 本で success 確定する (DR-047 §2 の核)。制約なしの対照は
/// 同じ 2 経路が正しく ambiguous:2 になることも併せて固定する (= 経路構造そのものは変わらず、
/// filter の有無だけが結果を変えることの証明)。
test "DR-047 §2: a constraint filters one of two complete paths (Or-branch shape, slice phase25:225)" {
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
  match parse(ScopeNode(sc), ["x"], defs=Map([])) {
    Success(bs) => {
      assert_eq(bs.length(), 1)
      assert_eq(bs[0].key, "foo")
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
  let sc_noc : Scope = { ..sc, constraints: [] }
  match parse(ScopeNode(sc_noc), ["x"], defs=Map([])) {
    Ambiguous(d) => assert_eq(d.interpretations.length(), 2)
    other => fail("expected Ambiguous, got " + render_outcome(other))
  }
}

///|
/// 保証: DR-047 §2 の path filter は `Or` ノードで束ねた経路だけでなく、`sc.greedy` に
/// 独立した SIBLING エントリとして並ぶ経路 (同じ trigger `--v` を持つ 2 本の Seq) でも同様に効く
/// (= 経路がどの構文で作られたかに依存しない)。`a` が `requires:["c"]` を持ち、`c` を与えない
/// `--v` 単独では a 経路が requires 未充足で完全経路から除外され、b 1 本 (`ok{b=true}`) に確定
/// する。`c` を併せて与えると両経路とも完全経路になり ambiguous:2 (対照ケース)。`entities: []`
/// (target `c` に Entity が無い = LOWERING §A.5 のフラグ暗黙 default が乗らない) なので、この pin
/// では `installer_wbtest.mbt` 側で固定するフラグ target の vacuous-satisfaction 事象は起きない
/// (= 混ぜず、filter 機構そのものだけを検証する)。
///
/// issue value-present-ladder-gap 裁定 2026-07-10 (更新): 適用点が KTop → post-parse の
/// `apply_requires_filter` へ移った (DR-047 §4) — `parse()` 単体はもう filter しない (both 経路
/// とも Ambiguous:2 になる) ので、`apply_requires_filter` を通した結果で確認する。
test "DR-047 §2: a constraint filters one of two complete paths (sibling greedy shape)" {
  // `apply_requires_filter` の目的語判定は `resolve_scope_tree` が実際に解決した値を読むので、
  // requires のターゲット `c` は resolve が拾える `Entity` として宣言する必要がある (トリガ `a`/`b`
  // は `is_committed` が生の CLI bindings を直接見るだけなので Entity 不要)。`ent("c", TStr)` は
  // 意図的に非bool 型のまま (この pin は filter 機構そのものの検証が目的、フラグの暗黙 default に
  // よる vacuous-satisfaction は混ぜない、上のコメント通り)。
  let sc : Scope = {
    greedy: [
      Seq([Exact("--v"), Bind("a", VBool(true))]),
      Seq([Exact("--v"), Bind("b", VBool(true))]),
      Seq([Exact("--c"), Bind("c", VBool(true))]),
    ],
    positional: [],
    entities: [ent("c", TStr)],
    constraints: [CRequires("a", ["c"])],
  }
  let root_node = ScopeNode(sc)
  match
    apply_requires_filter(
      parse(root_node, ["--v"], defs=Map([])),
      root_node,
      Map([]),
      Map([]),
      1,
    ) {
    Success(bs) => {
      assert_eq(bs.length(), 1)
      assert_eq(bs[0].key, "b")
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
  match
    apply_requires_filter(
      parse(root_node, ["--v", "--c"], defs=Map([])),
      root_node,
      Map([]),
      Map([]),
      2,
    ) {
    Ambiguous(d) => assert_eq(d.interpretations.length(), 2)
    other => fail("expected Ambiguous, got " + render_outcome(other))
  }
}

// ── DR-091 §2: KvArg consume-time gate (kv_map accumulator) ─────────────────

///|
/// Guarantees: a `KvArg` piece that DOES contain `=` is a plain Accept — same shape as `StrArg`
/// (1 token consumed, `VStr` binding of the WHOLE token, `=` split deferred to `resolve.mbt`'s
/// `build_result` at fold time — this node only gates, it does not itself split).
test "DR-091 §2: KvArg accepts a piece containing '=' (whole token becomes the binding value)" {
  let root : Scope = {
    greedy: [],
    positional: [KvArg("kv", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["KEY=value"], defs=Map([]))
  match o {
    Success(bs) => {
      assert_eq(bs.length(), 1)
      assert_eq(bs[0].key, "kv")
      assert_eq(bs[0].value, VStr("KEY=value"))
    }
    other => fail("expected Success, got " + render_outcome(other))
  }
}

///|
/// Guarantees (DR-091 §2 "`=` を含まない piece は... reject"): a `KvArg` piece with NO `=` is a
/// Held `kind: parse` Error (`pe_parse_kv`, `reason: "not_a_kv_pair"`) — the same family as any
/// other value primitive's type-parse failure, NOT a silent Reject and NOT a `KFilter` reject.
/// This is the structural precondition `resolve.mbt`'s `split_first_eq` relies on: every piece
/// that ever becomes a Binding is guaranteed splittable.
test "DR-091 §2: KvArg rejects a piece with no '=' as a Held kind:parse Error (対極 of the accept case above)" {
  let root : Scope = {
    greedy: [],
    positional: [KvArg("kv", [])],
    entities: [],
    constraints: [],
  }
  let o = parse(ScopeNode(root), ["NOEQUALSIGN"], defs=Map([]))
  match o {
    Failure(fd) => {
      let mut found = false
      for e in fd.errors {
        if e.element == "kv" && e.reason == "not_a_kv_pair" {
          found = true
          assert_eq(render_kind(e.kind), "parse")
        }
      }
      assert_true(found)
    }
    other => fail("expected Failure, got " + render_outcome(other))
  }
}
