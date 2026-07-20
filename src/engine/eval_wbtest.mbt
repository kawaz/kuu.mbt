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
        cat(acc, [mk_binding(self.name, String(token), Cli, at_pos=Some(pos))]),
      )
    None => [Pending([pending_value_candidate("string", self.name)], acc)]
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
