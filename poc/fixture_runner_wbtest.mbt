// fixture_runner_wbtest.mbt — Phase 2-① minimal conformance fixture runner.
//
// PURPOSE: a *verification instrument*, not product code. It feeds the canonical
// wire-form definitions of two conformance fixtures through the slice's
// parse_definition + parse, projects each Outcome into the CONFORMANCE §2 shape,
// and compares against the fixture's expected values under the §3 rules. Its job
// is to surface (a) fixture authoring errors and (b) slice/spec divergences.
//
// SOURCE OF THE FIXTURE DATA (transcribed by hand — a JSON decoder is out of scope
// for this PoC, see CONFORMANCE §1 "definition は wire form"):
//   - kawaz/kuu:fixtures/dd/basic.json           (7 cases)
//   - kawaz/kuu:fixtures/dd/duplicate-decl.json  (1 case)
// The wire form places `type:"dd"` under `options[]` (DR-064: canonical home is
// options[], and §2 says the dd installer collects it "配置不問"). This runner
// transcribes that placement faithfully so the comparison tests exactly what a
// conformant engine must accept.
//
// PROJECTION (CONFORMANCE §2):
//   success  => effects (cli-derived parse effects, ordered; sentinels excluded)
//               + result (final object, ladder-filled)
//   failure  => errors as the set of (element, argv_pos, kind); reason unimplemented
//               in the slice so it is NOT compared (§2 optional reason检证)
//   ambiguous=> interpretation count / views
//
// COMPARISON (CONFORMANCE §3): effects = ordered full match; result = structural
// (keys sorted here); errors = set (sorted). The verdict string per case is
// "PASS" or a "got= / want=" diff, fixed with inspect so the observed slice
// behavior is frozen and any drift is caught.

// ── projections ───────────────────────────────────────────────────────────────

fn eff_op(op : EffectOp) -> String {
  match op {
    Set => "set"
    Default => "default"
    Unset => "unset"
    Empty => "empty"
  }
}

/// CONFORMANCE §2 effects: ordered "entity:op(operand)@source", consumption order
/// preserved (order is an identity component, DR-038/045). Sentinel bindings
/// ("[]" / "{}" / "" / @act: / @depr:) are excluded via is_sentinel (result.mbt).
fn proj_effects(binds : Array[Binding]) -> String {
  let items : Array[String] = []
  for b in binds {
    if not(is_sentinel(b.key)) {
      items.push(
        "\{b.key}:\{eff_op(b.op)}(\{render_val(b.value)})@\{render_src(b.source)}",
      )
    }
  }
  join_comma(items)
}

/// A key-sorted rendering of the built result object (CONFORMANCE §3: result is
/// compared for structural equivalence, key order non-normative). Arrays keep
/// order (list order is meaningful).
fn render_rval_sorted(r : RVal) -> String {
  match r {
    RScalar(v) => render_val(v)
    RArr(vs) => {
      let items : Array[String] = []
      for v in vs {
        items.push(render_rval_sorted(v))
      }
      "[" + join_comma(items) + "]"
    }
    RObj(kvs) => {
      let items : Array[String] = []
      for kv in kvs {
        items.push(kv.0 + "=" + render_rval_sorted(kv.1))
      }
      sort_items(items)
      "{" + join_comma(items) + "}"
    }
  }
}

/// CONFORMANCE §2 result: the final result object (ladder-filled). accum_cells +
/// build_result is the slice's own §5 projection path.
fn proj_result(sc : Scope, binds : Array[Binding]) -> String {
  render_rval_sorted(build_result(binds, accum_cells(sc), []))
}

/// CONFORMANCE §2 failure: the SET of (element, argv_pos, kind) — reason omitted
/// (slice-unimplemented, §2 optional). Sorted for set comparison (§3).
fn proj_errors(errs : Array[ParseError]) -> String {
  let items : Array[String] = []
  for e in errs {
    items.push("\{e.element}@\{e.argv_pos}/\{render_kind(e.kind)}")
  }
  sort_items(items)
  "{" + join_comma(items) + "}"
}

// ── case drivers (the 突合: fixture-expected values are the arguments) ─────────

/// Run a success case: compare projected effects + result against the fixture's
/// expected. Returns "PASS" or a diff string classifying the mismatch.
fn run_success(
  sc : Scope,
  argv : Array[String],
  exp_effects : String,
  exp_result : String,
) -> String {
  match parse(ScopeNode(sc), argv) {
    Success(binds) => {
      let ae = proj_effects(binds)
      let ar = proj_result(sc, binds)
      let e_ok = ae == exp_effects
      let r_ok = ar == exp_result
      if e_ok && r_ok {
        "PASS"
      } else {
        let ep = if e_ok { "effects ok" } else { "effects got=\{ae} want=\{exp_effects}" }
        let rp = if r_ok { "result ok" } else { "result got=\{ar} want=\{exp_result}" }
        ep + " | " + rp
      }
    }
    other => "EXPECTED-SUCCESS got=" + render_outcome(other)
  }
}

/// Run a failure case: compare the projected error set against the fixture's
/// expected set. Returns "PASS" or a diff string.
fn run_failure(sc : Scope, argv : Array[String], exp_errors : String) -> String {
  match parse(ScopeNode(sc), argv) {
    Failure(d) => {
      let a = proj_errors(d.errors)
      if a == exp_errors {
        "PASS"
      } else {
        "errors got=\{a} want=\{exp_errors}"
      }
    }
    other => "EXPECTED-FAILURE got=" + render_outcome(other)
  }
}

// ── fixture definitions (transcribed wire form) ───────────────────────────────

/// fixtures/dd/basic.json definition. dd (`--`) transcribed into options[] as the
/// wire form declares it (DR-064 canonical placement).
fn basic_def() -> Scope {
  let def = def_(
    [opt("a", TFlag, short=['a']), opt("b", TFlag, short=['b']), dd_marker()],
    [pos("x", TStr)],
  )
  build_reg(def, [LongInst, ShortInst, DdInst], Map::new())
}

/// fixtures/dd/duplicate-decl.json definition: two dd declarations in options[].
fn dup_def() -> Scope {
  let def = def_([dd_marker(), dd_marker()], [pos("x", TStr)])
  build_reg(def, [DdInst], Map::new())
}

// ── basic.json: 7 cases ───────────────────────────────────────────────────────

test "conformance dd/basic case 1: -- severs greedy face; -b falls raw into x (DR-041/042)" {
  // fixture expect: effects [a set true, x set "-b"] ; result {a:true, b:false, x:"-b"}.
  // effects now match the fixture exactly (dd sever + raw -b into x); the ONLY residual is
  // KNOWN GAP (preset default): fixture expects b=false but the slice leaves unfired flags
  // absent from the result (b missing), so result stays got={a=true,x=-b} want={...,b=false}.
  inspect(
    run_success(basic_def(), ["-a", "--", "-b"], "a:set(true)@cli,x:set(-b)@cli", "{a=true,b=false,x=-b}"),
    content="effects ok | result got={a=true,x=-b} want={a=true,b=false,x=-b}",
  )
}

test "conformance dd/basic case 2: no --; -b fires as flag, c -> x (DR-042 dd purpose)" {
  // fixture expect: effects [a set true, b set true, x set "c"] ; result {a:true,b:true,x:"c"}.
  // All three flags fire so no preset-default gap on the result here.
  inspect(
    run_success(basic_def(), ["-a", "-b", "c"], "a:set(true)@cli,b:set(true)@cli,x:set(c)@cli", "{a=true,b=true,x=c}"),
    content="PASS",
  )
}

test "conformance dd/basic case 3: structural-required x unmet, argv_pos=token-exhaust (DR-065 §3)" {
  // fixture expect: failure errors {element:x, argv_pos:2, kind:parse} (reason missing_operand
  // not compared). argv_pos = argv.length = 2 (token ran out at the position x requested).
  // errors now match the fixture exactly (structural failure emits the held ParseError).
  inspect(run_failure(basic_def(), ["-a", "-b"], "{x@2/parse}"), content="PASS")
}

test "conformance dd/basic case 4: residual token after sever, element-less scope stumble (DR-065 §3)" {
  // fixture expect: failure errors {element:"" (omitted), argv_pos:2, kind:parse} (reason
  // unexpected_token). argv_pos = residual head (the -b at index 2 with no consumer).
  // errors now match the fixture exactly (residual-token failure synthesizes the parse error).
  inspect(run_failure(basic_def(), ["--", "-a", "-b"], "{@2/parse}"), content="PASS")
}

test "conformance dd/basic case 5: marker consumed but yields no value; x empty (DR-038)" {
  // fixture expect: failure errors {element:x, argv_pos:3, kind:parse} (reason missing_operand).
  // argv_pos = 3 = argv.length (all consumed but x got no value => not a complete path).
  // errors now match the fixture exactly (dd consumes the marker, x stays unmet => held error).
  inspect(run_failure(basic_def(), ["-a", "-b", "--"], "{x@3/parse}"), content="PASS")
}

test "conformance dd/basic case 6: 2nd -- is literal (sever is emergent, not a count rule) (DR-064 §4)" {
  // fixture expect: effects [a set true, b set true, x set "--"] ; result {a:true,b:true,x:"--"}.
  // effects + result now match the fixture exactly (dd position-free回収 lets the 2nd -- reach x).
  inspect(
    run_success(basic_def(), ["-a", "-b", "--", "--"], "a:set(true)@cli,b:set(true)@cli,x:set(--)@cli", "{a=true,b=true,x=--}"),
    content="PASS",
  )
}

test "conformance dd/basic case 7: dd position-free; -- after operand still succeeds (DR-041 §4)" {
  // fixture expect: effects [x set "hello"] ; result {a:false, b:false, x:"hello"}.
  // effects now match the fixture exactly (dd after the operand still succeeds). The ONLY residual is
  // KNOWN GAP (preset default): fixture expects a=false,b=false but unfired flags are absent from the
  // slice result, so result stays got={x=hello} want={a=false,b=false,x=hello}.
  inspect(
    run_success(basic_def(), ["hello", "--"], "x:set(hello)@cli", "{a=false,b=false,x=hello}"),
    content="effects ok | result got={x=hello} want={a=false,b=false,x=hello}",
  )
}

// ── duplicate-decl.json: 1 case ───────────────────────────────────────────────

test "conformance dd/duplicate-decl case 1: two dd decls merge to one reading (DR-064 §4 / DR-038)" {
  // fixture expect: success (NOT ambiguous) effects [x set "-v"] ; result {x:"-v"}.
  // Both dd readings have the same effect (sever + consume 1, no value) so path-identity
  // dedup collapses them to a single interpretation.
  // effects + result now match the fixture exactly (two dd decls merge to one reading).
  inspect(
    run_success(dup_def(), ["--", "-v"], "x:set(-v)@cli", "{x=-v}"),
    content="PASS",
  )
}
