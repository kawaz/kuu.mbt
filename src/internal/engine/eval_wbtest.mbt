// eval_wbtest.mbt — engine-internal evaluator probes using a synthetic NodeExt resident.

///|
priv struct TestValueExt {
  name : String
  resident_kind : String
}

///|
impl NodeExt for TestValueExt with fn kind(self) {
  self.resident_kind
}

///|
impl NodeExt for TestValueExt with fn element_name(self) {
  Some(self.name)
}

///|
impl NodeExt for TestValueExt with fn encode(self) {
  [self.name.to_json()].to_json()
}

///|
impl NodeExt for TestValueExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for TestValueExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      next(
        ctx,
        pos + 1,
        acc + [Binding::new(self.name, String(token), Cli, at_pos=Some(pos))],
      )
    None => [Pending([Candidate::pending_value("string", self.name)], acc)]
  }
}

///|
fn test_value(name : String, resident_kind : String) -> Node {
  Ext(TestValueExt::{ name, resident_kind } as &NodeExt)
}

///|
test "REVIEW-C2 eval_many: a Pending after successful reps carries the reps' bindings" {
  // One synthetic value rep consumes the only token; the next rep starves and returns Pending.
  // Pending must retain v=x, matching eval_seq's starved-branch state contract.
  let ctx : Ctx = {
    toks: ["x"],
    defs: Map([]),
    extensions_: Registry::new(),
    mode: ModeParse,
  }
  let brs = eval_many(test_value("v", "synthetic/string"), ctx, 0, [])
  let mut pending_has_acc = false
  for branch in brs {
    match branch {
      Pending(_, bindings) =>
        if bindings.length() == 1 && bindings[0].key == "v" {
          pending_has_acc = true
        }
      _ => ()
    }
  }
  assert_true(pending_has_acc)
}

///|
test "REGRESSION head_elem_names_into collects a float resident head's name" {
  // A float-kind extension repeat head contributes its encoded element name to the optional-repeat
  // held-error parity set, preventing a phantom missing_operand on the probe for one more rep.
  let out : Array[String] = []
  head_elem_names_into(test_value("f", "synthetic/float"), out)
  assert_eq(out, ["f"])
}

///|
test "sever_cont marks every resumable spine across nesting and repeat choices" {
  let sc : Scope = { greedy: [], positional: [], entities: [], constraints: [] }
  let original = KNest(
    "cmd",
    true,
    0,
    KResumeScope(
      sc,
      1,
      false,
      KRefChoice(
        sc,
        "row",
        2,
        false,
        3,
        KTailChoice(sc, Exact("x"), 4, false, 5, false, 6, KTop([])),
      ),
    ),
  )
  let expected = KNest(
    "cmd",
    true,
    0,
    KResumeScope(
      sc,
      1,
      true,
      KRefChoice(
        sc,
        "row",
        2,
        true,
        3,
        KTailChoice(sc, Exact("x"), 4, false, 5, true, 6, KTop([])),
      ),
    ),
  )
  assert_eq(sever_cont(original), expected)
  assert_eq(sever_cont(KDone), KDone)
}

///|
fn downstream_test_ctx(
  toks : Array[String],
  mode : EvalMode,
  defs? : Map[String, Node] = Map([]),
) -> Ctx {
  { toks, defs, extensions_: Registry::new(), mode }
}

///|
/// The test downstream is one required tail followed by the real global-end check. An Accept from the
/// head therefore means the complete `head + tail + EOF` path succeeded, not merely that a local node
/// stopped somewhere before the end.
fn eval_before_required_tail(node : Node, ctx : Ctx) -> Array[Branch] {
  eval_with_downstream(
    node,
    ctx,
    0,
    (ctx2, pos, head_bindings) => {
      eval_with_downstream(
        RequiredArgument("tail"),
        ctx2,
        pos,
        (_ctx3, end_pos, tail_bindings) => {
          run_cont(KTop([]), ctx2, end_pos, head_bindings + tail_bindings)
        },
        (_ctx3, error, tail_bindings) => {
          [Rejected(error, head_bindings + tail_bindings)]
        },
        (_ctx3, error, tail_bindings) => {
          [Held(error, head_bindings + tail_bindings)]
        },
        (_ctx3, candidates, tail_bindings) => {
          [Pending(candidates, head_bindings + tail_bindings)]
        },
      )
    },
    (_ctx2, error, bindings) => [Rejected(error, bindings)],
    (_ctx2, error, bindings) => [Held(error, bindings)],
    (_ctx2, candidates, bindings) => [Pending(candidates, bindings)],
  )
}

///|
fn branch_has_binding(
  branches : Array[Branch],
  key : String,
  expected : Value,
) -> Bool {
  for branch in branches {
    match branch {
      Accept(_, bindings) =>
        for binding in bindings {
          if binding.key == key && binding.value == expected {
            return true
          }
        }
      Rejected(_, _) | Held(_, _) | Pending(_, _) => ()
    }
  }
  false
}

///|
fn accept_has_bindings(
  branches : Array[Branch],
  first_key : String,
  first_value : Value,
  second_key : String,
  second_value : Value,
) -> Bool {
  for branch in branches {
    match branch {
      Accept(_, bindings) => {
        let mut first = false
        let mut second = false
        for binding in bindings {
          if binding.key == first_key && binding.value == first_value {
            first = true
          }
          if binding.key == second_key && binding.value == second_value {
            second = true
          }
        }
        if first && second {
          return true
        }
      }
      Rejected(_, _) | Held(_, _) | Pending(_, _) => ()
    }
  }
  false
}

///|
fn branches_have_error_reason(
  branches : Array[Branch],
  reason : String,
) -> Bool {
  for branch in branches {
    match branch {
      Rejected(error, _) | Held(error, _) =>
        if error.reason == reason {
          return true
        }
      Accept(_, _) | Pending(_, _) => ()
    }
  }
  false
}

///|
fn error_has_binding(
  branches : Array[Branch],
  reason : String,
  key : String,
  expected : Value,
) -> Bool {
  for branch in branches {
    match branch {
      Rejected(error, bindings) | Held(error, bindings) =>
        if error.reason == reason {
          for binding in bindings {
            if binding.key == key && binding.value == expected {
              return true
            }
          }
        }
      Accept(_, _) | Pending(_, _) => ()
    }
  }
  false
}

///|
fn pending_has_origin(branches : Array[Branch], origin : String) -> Bool {
  for branch in branches {
    match branch {
      Pending(candidates, _) =>
        for candidate in candidates {
          if candidate.origin == origin {
            return true
          }
        }
      Accept(_, _) | Rejected(_, _) | Held(_, _) => ()
    }
  }
  false
}

///|
priv struct InvalidValueExt {
  name : String
}

///|
impl NodeExt for InvalidValueExt with fn kind(_self) {
  "synthetic/invalid"
}

///|
impl NodeExt for InvalidValueExt with fn element_name(self) {
  Some(self.name)
}

///|
impl NodeExt for InvalidValueExt with fn encode(self) {
  [self.name.to_json()].to_json()
}

///|
impl NodeExt for InvalidValueExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for InvalidValueExt with fn eval(self, ctx, pos, acc, _next) {
  match ctx.token_at(pos) {
    Some(_) =>
      [
        Held(
          {
            element: self.name,
            args_pos: pos,
            kind: Parse,
            reason: "synthetic_invalid",
            message: "synthetic recognized-invalid value",
            path: [],
          },
          acc,
        ),
      ]
    None => [Pending([Candidate::pending_value("string", self.name)], acc)]
  }
}

///|
fn invalid_value(name : String) -> Node {
  Ext(InvalidValueExt::{ name, } as &NodeExt)
}

///|
priv struct RejectingValueExt {
  name : String
}

///|
impl NodeExt for RejectingValueExt with fn kind(_self) {
  "synthetic/rejected"
}

///|
impl NodeExt for RejectingValueExt with fn element_name(self) {
  Some(self.name)
}

///|
impl NodeExt for RejectingValueExt with fn encode(self) {
  [self.name.to_json()].to_json()
}

///|
impl NodeExt for RejectingValueExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for RejectingValueExt with fn eval(self, _ctx, pos, acc, _next) {
  [
    Rejected(
      {
        element: self.name,
        args_pos: pos,
        kind: Parse,
        reason: "synthetic_rejected",
        message: "synthetic value-space rejection",
        path: [],
      },
      acc,
    ),
  ]
}

///|
fn rejecting_value(name : String) -> Node {
  Ext(RejectingValueExt::{ name, } as &NodeExt)
}

///|
fn accept_count(branches : Array[Branch]) -> Int {
  let mut count = 0
  for branch in branches {
    if branch is Accept(_, _) {
      count = count + 1
    }
  }
  count
}

///|
test "ChildDefault downstream: ScopeNode child sees the required outer tail" {
  // The child row may consume k=a, but consuming v=b would starve the outer tail. Its default seat
  // must therefore win while the same b token remains available to the real downstream continuation.
  let child : Scope = {
    greedy: [],
    positional: [
      test_value("k", "synthetic/string"),
      ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
    ],
    entities: [],
    constraints: [],
  }
  let branches = eval_before_required_tail(
    ScopeNode(child),
    downstream_test_ctx(["a", "b"], ModeParse),
  )
  assert_true(
    accept_has_bindings(branches, "#seat:v", String("v"), "tail", String("b")),
  )
}

///|
test "ChildDefault downstream: Many head leaves the required outer tail" {
  // One unbounded row consumes k=a; its child v falls back so tail=b remains. The zero-row reading
  // leaves a residual token and the v-consuming reading starves tail, so exactly the defaulted row is full.
  let head = Seq([
    test_value("k", "synthetic/string"),
    ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
  ])
  let branches = eval_before_required_tail(
    Many(head, false),
    downstream_test_ctx(["a", "b"], ModeParse),
  )
  assert_true(
    accept_has_bindings(branches, "#seat:v", String("v"), "tail", String("b")),
  )
}

///|
test "ChildDefault downstream: IndexedRepeat head leaves the required outer tail" {
  // The named row uses the same complete-path split as an ordinary repeat, while preserving the
  // runtime #0 nesting. v defaults inside the row and b belongs to the outer tail.
  let head = Seq([
    test_value("k", "synthetic/string"),
    ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
  ])
  let branches = eval_before_required_tail(
    IndexedRepeat("rows", head, 0, Some(1)),
    downstream_test_ctx(["a", "b"], ModeParse),
  )
  assert_true(
    accept_has_bindings(branches, "#seat:v", String("v"), "tail", String("b")),
  )
}

///|
test "ChildDefault downstream: BoundedTail head leaves the required outer tail" {
  // With budget one, the optional row must be tested against tail+EOF before its child default
  // decides whether b is the child's CLI value or the downstream positional's value.
  let head = Seq([
    test_value("k", "synthetic/string"),
    ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
  ])
  let branches = eval_before_required_tail(
    BoundedTail(head, 1, false),
    downstream_test_ctx(["a", "b"], ModeParse),
  )
  assert_true(
    accept_has_bindings(branches, "#seat:v", String("v"), "tail", String("b")),
  )
}

///|
test "ChildDefault downstream: recognized-invalid repeat value never falls back" {
  // The repeat head recognizes b as v's value and returns Held. That committed invalid reading must
  // not be reinterpreted as an empty child-default seat that hands b to the outer tail.
  let head = Seq([
    test_value("k", "synthetic/string"),
    ChildDefault(invalid_value("v"), "#seat:v", "v"),
  ])
  let branches = eval_before_required_tail(
    Many(head, false),
    downstream_test_ctx(["a", "b"], ModeParse),
  )
  assert_false(branch_has_binding(branches, "#seat:v", String("v")))
  assert_true(branches_have_error_reason(branches, "synthetic_invalid"))
}

///|
test "IndexedRepeat optional row retains recognized-invalid Held" {
  // Reaching min=0 makes stopping legal, but an existing token recognized by the optional row is a
  // committed invalid reading, not the structural EOF absence that may be omitted from the more branch.
  let ctx = downstream_test_ctx(["bad"], ModeParse)
  let branches = eval_with_downstream(
    IndexedRepeat("rows", invalid_value("v"), 0, Some(1)),
    ctx,
    0,
    (_ctx2, pos, bindings) => run_cont(KTop([]), ctx, pos, bindings),
    (_ctx2, error, bindings) => [Rejected(error, bindings)],
    (_ctx2, error, bindings) => [Held(error, bindings)],
    (_ctx2, candidates, bindings) => [Pending(candidates, bindings)],
  )
  assert_true(branches_have_error_reason(branches, "synthetic_invalid"))
}

///|
test "BoundedTail local Held preserves bindings from earlier repeat state" {
  // A later optional head can fail after prior state already exists. The diagnostic must retain that
  // state so fired-action and failure material are not detached from the path that produced them.
  let ctx = downstream_test_ctx(["bad"], ModeParse)
  let branches = eval_bounded_with_downstream(
    invalid_value("v"),
    1,
    false,
    ctx,
    0,
    [Binding::new("prior", String("kept"), Cli)],
    (_ctx2, pos, bindings) => run_cont(KTop([]), ctx, pos, bindings),
    (_ctx2, error, bindings) => [Rejected(error, bindings)],
    (_ctx2, error, bindings) => [Held(error, bindings)],
    (_ctx2, candidates, bindings) => [Pending(candidates, bindings)],
    (_ctx2, pos, bindings) => run_cont(KTop([]), ctx, pos, bindings),
    None,
    false,
  )
  assert_true(
    error_has_binding(branches, "synthetic_invalid", "prior", String("kept")),
  )
}

///|
test "ChildDefault downstream: complete mode keeps stop and more Pending union" {
  // At the boundary the zero-row stop contributes tail, while trying one bounded row contributes v.
  // Complete mode must retain both partials instead of applying parse-mode greedy pruning.
  let node = BoundedTail(
    ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
    1,
    false,
  )
  let branches = eval_before_required_tail(
    node,
    downstream_test_ctx([], ModeComplete),
  )
  assert_true(pending_has_origin(branches, "tail"))
  assert_true(pending_has_origin(branches, "v"))
}

///|
test "ChildDefault downstream: local Rejected crosses Scoped exactly once" {
  // A value-space miss is not Held, so the child default may fall back; the rejected diagnostic that
  // remains as a losing reading still crosses the structural wrapper and receives its path once.
  let branches = eval_with_downstream(
    Scoped("outer", ChildDefault(rejecting_value("v"), "#seat:v", "v")),
    downstream_test_ctx([], ModeParse),
    0,
    (_ctx, pos, bindings) => [Accept(pos, bindings)],
    (_ctx, error, bindings) => [Rejected(error, bindings)],
    (_ctx, error, bindings) => [Held(error, bindings)],
    (_ctx, candidates, bindings) => [Pending(candidates, bindings)],
  )
  let mut rejected_nested_once = false
  for branch in branches {
    match branch {
      Rejected(error, _) =>
        if error.reason == "synthetic_rejected" && error.path == ["outer"] {
          rejected_nested_once = true
        }
      _ => ()
    }
  }
  assert_true(rejected_nested_once)
}

///|
test "ChildDefault downstream: local Pending crosses Scoped exactly once" {
  // The consuming reading's boundary candidate remains part of complete-mode material even when the
  // default fallback also survives, and its path is transformed by the wrapper exactly once.
  let branches = eval_with_downstream(
    Scoped(
      "outer",
      ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
    ),
    downstream_test_ctx([], ModeComplete),
    0,
    (_ctx, pos, bindings) => [Accept(pos, bindings)],
    (_ctx, error, bindings) => [Rejected(error, bindings)],
    (_ctx, error, bindings) => [Held(error, bindings)],
    (_ctx, candidates, bindings) => [Pending(candidates, bindings)],
  )
  let mut pending_nested_once = false
  for branch in branches {
    match branch {
      Pending(candidates, _) =>
        for candidate in candidates {
          if candidate.origin == "v" && candidate.path == ["outer"] {
            pending_nested_once = true
          }
        }
      _ => ()
    }
  }
  assert_true(pending_nested_once)
}

///|
test "GreedyRepeat Ref tail preserves recursive greedy share preference" {
  // A min>=1 unbounded repeat lowers to a recursive Ref. With a following min:0 tail, both splits can
  // consume all tokens; the repeat's greedy preference must keep only the longer Ref share.
  let defs : Map[String, Node] = Map([])
  defs.set(
    "row#cons",
    Seq([test_value("row", "synthetic/string"), Or([Ref("row#cons"), Seq([])])]),
  )
  let ctx = downstream_test_ctx(["--rows", "a", "b"], ModeParse, defs~)
  let sc : Scope = {
    greedy: [],
    positional: [Many(test_value("tail", "synthetic/string"), false)],
    entities: [],
    constraints: [],
  }
  let out : Array[Branch] = []
  step_greedy_repeat(
    Seq([Exact("--rows")]),
    Ref("row#cons"),
    sc,
    ctx,
    0,
    0,
    [],
    false,
    KTop([]),
    out,
  )
  assert_eq(accept_count(out), 1)
  let mut two_rows = false
  for branch in out {
    match branch {
      Accept(_, bindings) => {
        let mut rows = 0
        for binding in bindings {
          if binding.key == "row" {
            rows = rows + 1
          }
        }
        if rows == 2 {
          two_rows = true
        }
      }
      _ => ()
    }
  }
  assert_true(two_rows)
}

///|
test "ScopeNode downstream: dd sever propagates into the outer scope" {
  // A dd fired in the inner companion scope raw-ifies the entire continuation. The outer -x spelling
  // must therefore be consumed as positional data rather than re-fired as a greedy flag.
  let child : Scope = {
    greedy: [DdSatisfied("--")],
    positional: [],
    entities: [],
    constraints: [],
  }
  let outer : Scope = {
    greedy: [Seq([Exact("-x"), Bind("x", Bool(true))])],
    positional: [RequiredArgument("tail")],
    entities: [],
    constraints: [],
  }
  let ctx = downstream_test_ctx(["--", "-x", "raw"], ModeParse)
  let branches = eval_with_downstream(
    ScopeNode(child),
    ctx,
    0,
    (ctx2, pos, bindings) => {
      eval_with_downstream(
        ScopeNode(outer),
        ctx2,
        pos,
        (_ctx3, end_pos, outer_bindings) => {
          run_cont(KTop([]), ctx2, end_pos, bindings + outer_bindings)
        },
        (_ctx3, error, outer_bindings) => {
          [Rejected(error, bindings + outer_bindings)]
        },
        (_ctx3, error, outer_bindings) => {
          [Held(error, bindings + outer_bindings)]
        },
        (_ctx3, candidates, outer_bindings) => {
          [Pending(candidates, bindings + outer_bindings)]
        },
      )
    },
    (_ctx2, error, bindings) => [Rejected(error, bindings)],
    (_ctx2, error, bindings) => [Held(error, bindings)],
    (_ctx2, candidates, bindings) => [Pending(candidates, bindings)],
    on_severed_accept=Some((ctx2, pos, bindings) => {
      eval_with_downstream(
        ScopeNode(outer),
        ctx2,
        pos,
        (_ctx3, end_pos, outer_bindings) => {
          run_cont(KTop([]), ctx2, end_pos, bindings + outer_bindings)
        },
        (_ctx3, error, outer_bindings) => {
          [Rejected(error, bindings + outer_bindings)]
        },
        (_ctx3, error, outer_bindings) => {
          [Held(error, bindings + outer_bindings)]
        },
        (_ctx3, candidates, outer_bindings) => {
          [Pending(candidates, bindings + outer_bindings)]
        },
        severed=true,
      )
    }),
  )
  assert_eq(accept_count(branches), 0)
}

///|
test "ChildDefault parse fallback drops the consuming Pending diagnostic" {
  let root : Scope = {
    greedy: [],
    positional: [
      ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
      RequiredArgument("tail"),
    ],
    entities: [],
    constraints: [],
  }
  match parse_tree(ScopeNode(root), [], defs=Map([])) {
    Failure(failure) => {
      assert_eq(failure.errors.length(), 1)
      assert_eq(failure.errors[0].element, "tail")
      assert_eq(failure.errors[0].reason, "required_violated")
    }
    _ => fail("the downstream required tail must fail")
  }
}

///|
test "non-scope root keeps Many ChildDefault downstream-aware" {
  let head = Seq([
    test_value("k", "synthetic/string"),
    ChildDefault(test_value("v", "synthetic/string"), "#seat:v", "v"),
  ])
  let root = Seq([Many(head, false), RequiredArgument("tail")])
  match parse_tree(root, ["a", "b"], defs=Map([])) {
    Success(bindings) => {
      assert_true(
        branch_has_binding([Accept(2, bindings)], "#seat:v", String("v")),
      )
      assert_true(
        branch_has_binding([Accept(2, bindings)], "tail", String("b")),
      )
    }
    _ => fail("the non-scope root must preserve the downstream tail")
  }
}

///|
test "eval_many failures preserve bindings from completed repetitions" {
  let inner = Node::Or([
    Seq([test_value("value", "synthetic/string"), Bind("prior", String("kept"))]),
    rejecting_value("value"),
  ])
  let branches = eval_many(
    inner,
    downstream_test_ctx(["ok", "bad"], ModeParse),
    0,
    [],
  )
  assert_true(
    error_has_binding(branches, "synthetic_rejected", "prior", String("kept")),
  )
}
