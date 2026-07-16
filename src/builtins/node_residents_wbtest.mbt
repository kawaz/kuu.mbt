///|
priv struct StuckNodeExt {}

///|
impl @engine.NodeExt for StuckNodeExt with fn kind(_self) {
  "synthetic/stuck"
}

///|
impl @engine.NodeExt for StuckNodeExt with fn encode(_self) {
  ().to_json()
}

///|
impl @engine.NodeExt for StuckNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for StuckNodeExt with fn eval(_self, ctx, pos, acc, next) {
  // Deliberately violates its non-zero-token declaration. The evaluator must
  // still enforce observed progress before re-entering a @engine.Many.
  next(ctx, pos, acc)
}

///|
fn stuck_node() -> @engine.Node {
  @engine.Ext(StuckNodeExt::{  } as &@engine.NodeExt)
}

///|
fn resident_failure_reason(node : @engine.Node, token : String) -> String {
  match @engine.parse_tree(node, [token]) {
    @engine.Failure(data) =>
      if data.errors.length() == 1 {
        data.errors[0].reason
      } else {
        "unexpected-error-count"
      }
    _ => "not-a-failure"
  }
}

///|
test "number resident preserves not_a_number" {
  // Every token outside the number lexicon maps to @engine.pe_parse's exact @engine.Held
  // reason through the @engine.NodeExt resident.
  assert_eq(
    resident_failure_reason(number_arg("n", false, []), "nope"),
    "not_a_number",
  )
}

///|
test "int resident preserves integer-specific failures" {
  // A readable fractional number under @engine.RError is not_an_integer, distinct from
  // the number resident's not_a_number and the magnitude overflow reason.
  assert_eq(
    resident_failure_reason(int_arg("n", @engine.RError, false, []), "1.5"),
    "not_an_integer",
  )
  // A readable integer outside Int64 reports its dedicated range reason rather
  // than being folded into either lexical failure family.
  assert_eq(
    resident_failure_reason(int_arg("n", @engine.RError, false, []), "1e300"),
    "int_out_of_range",
  )
}

///|
test "bool resident preserves not_a_bool" {
  // Bool parsing has its own canonical vocabulary and must not collapse an
  // unknown token onto number parsing's error family.
  assert_eq(
    resident_failure_reason(
      bool_arg("b", @engine.bool_config_canonical(), []),
      "yes",
    ),
    "not_a_bool",
  )
}

///|
test "kv resident keeps the contains-equals gate" {
  // DR-091 §2 requires a filtered kv_map token to contain '=' before it can be
  // committed; the resident retains the dedicated not_a_kv_pair @engine.Held reason.
  assert_eq(
    resident_failure_reason(kv_arg("entry", []), "missing-separator"),
    "not_a_kv_pair",
  )
}

///|
test "marker residents declare zero-token consumption" {
  // Marker progress is contract data on @engine.NodeExt; @engine.Bind remains the sole closed
  // structural zero-token binder and both paths must report the same property.
  assert_true(
    @engine.node_consumes_zero_tokens(effect_mark("x", @engine.Unset)),
  )
  assert_true(@engine.node_consumes_zero_tokens(deprecation_mark("x")))
  assert_true(@engine.node_consumes_zero_tokens(failure_mark("x")))
  assert_true(
    @engine.node_consumes_zero_tokens(@engine.Bind("x", @engine.VBool(true))),
  )
  assert_false(@engine.node_consumes_zero_tokens(string_arg("x", [])))
}

///|
test "@engine.Many rejects zero-progress residents without re-entry" {
  // A zero-token marker cannot count as one @engine.Many repetition: the 0-rep stop
  // branch succeeds, while the marker binding is not generated indefinitely.
  let marker_root = @engine.ScopeNode({
    greedy: [],
    positional: [@engine.Many(effect_mark("x", @engine.Unset), false)],
    entities: [],
    constraints: [],
  })
  match @engine.parse_tree(marker_root, []) {
    @engine.Success(bindings) => assert_eq(bindings, [])
    _ => fail("zero-token @engine.Many must terminate at its 0-rep branch")
  }
  // The evaluator also checks observed position progress, so a resident that
  // falsely declares token consumption cannot recurse at the same position.
  let stuck_root = @engine.ScopeNode({
    greedy: [],
    positional: [@engine.Many(stuck_node(), false)],
    entities: [],
    constraints: [],
  })
  match @engine.parse_tree(stuck_root, ["unconsumed"]) {
    @engine.Failure(data) =>
      assert_eq(data.errors[0].reason, "unexpected_token")
    _ => fail("same-position resident must leave the token as a finite failure")
  }
}

///|
test "mandatory resident preserves downstream @engine.Pending position" {
  // The positional resident consumes argv[0], then the greedy --port trigger
  // starves at argv end. Its downstream @engine.Pending belongs to position 2, not the
  // positional resident's start position 0.
  let root = @engine.ScopeNode({
    greedy: [
      @engine.Seq([@engine.Exact("--port"), number_arg("port", false, [])]),
    ],
    positional: [string_arg("file", [])],
    entities: [],
    constraints: [],
  })
  match @engine.parse_tree(root, ["a", "--port"]) {
    @engine.Failure(data) => {
      let mut found = false
      for error in data.errors {
        if error.element == "port" && error.reason == "missing_operand" {
          assert_eq(error.args_pos, 2)
          assert_eq(error.path, [])
          found = true
        }
      }
      assert_true(found)
    }
    _ => fail("starved downstream value must remain a failure")
  }
}

///|
test "mandatory resident preserves downstream @engine.Pending fire path" {
  // A nested downstream @engine.Pending already carries its complete dynamic fire path.
  // The outer positional resident must pass it through without rebuilding the
  // error at its own position or dropping the inner command boundary.
  let inner : @engine.Scope = {
    greedy: [
      @engine.Seq([@engine.Exact("--port"), number_arg("port", false, [])]),
    ],
    positional: [],
    entities: [],
    constraints: [],
  }
  let sub : @engine.Scope = {
    greedy: [@engine.CmdSat("inner", inner)],
    positional: [string_arg("file", [])],
    entities: [],
    constraints: [],
  }
  let root = @engine.ScopeNode({
    greedy: [@engine.CmdSat("sub", sub)],
    positional: [],
    entities: [],
    constraints: [],
  })
  match @engine.parse_tree(root, ["sub", "a", "inner", "--port"]) {
    @engine.Failure(data) => {
      let mut found = false
      for error in data.errors {
        if error.element == "port" && error.reason == "missing_operand" {
          assert_eq(error.args_pos, 4)
          assert_eq(error.path, ["sub", "inner"])
          found = true
        }
      }
      assert_true(found)
    }
    _ => fail("nested starved value must remain a failure")
  }
}
