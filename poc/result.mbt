// result.mbt — layer 3: the name-driven result builder (DR-016 / DR-025 / DR-043).
//
// The evaluator produces flat bindings, each tagged with its result scope path (a
// command / name scope prepends its label). This folds them into a nested result
// object: a name scope becomes a nested object, and an accumulator cell (repeat
// flattening or a `multiple` option) becomes a value LIST. Everything else is a scalar
// with last-wins (DR-015). This is where repeat's "multiple same-key bindings" meet the
// accumulator (DR-043 §「平坦化 accumulator と name 駆動 result builder の噛み合わせ」).

/// A built result value.
pub(all) enum RVal {
  RScalar(Value)
  RList(Array[Value]) // an accumulator cell (repeat / multiple)
  RObj(Array[(String, RVal)]) // a name / command scope, keys in first-seen order
} derive(Eq, Show)

fn str_contains(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

/// Build the nested result object from the winning flat bindings. `accum` is the set
/// of leaf names whose cell collects a list (see `accum_names`).
pub fn build_result(binds : Array[Binding], accum : Array[String]) -> RVal {
  // direct leaves at this level (empty scope path), in first-seen key order
  let obj : Array[(String, RVal)] = []
  let keys : Array[String] = []
  for b in binds {
    if b.scope.length() == 0 && !str_contains(keys, b.key) {
      keys.push(b.key)
    }
  }
  for k in keys {
    let vals : Array[Value] = []
    for b in binds {
      if b.scope.length() == 0 && b.key == k {
        vals.push(b.value)
      }
    }
    if str_contains(accum, k) {
      obj.push((k, RList(vals)))
    } else {
      obj.push((k, RScalar(vals[vals.length() - 1]))) // last-wins (DR-015)
    }
  }
  // nested scopes: group by the first path segment, first-seen order
  let segs : Array[String] = []
  for b in binds {
    if b.scope.length() > 0 && !str_contains(segs, b.scope[0]) {
      segs.push(b.scope[0])
    }
  }
  for seg in segs {
    let sub : Array[Binding] = []
    for b in binds {
      if b.scope.length() > 0 && b.scope[0] == seg {
        let rest : Array[String] = []
        let mut i = 1
        while i < b.scope.length() {
          rest.push(b.scope[i])
          i = i + 1
        }
        sub.push({ key: b.key, value: b.value, source: b.source, scope: rest })
      }
    }
    obj.push((seg, build_result(sub, accum)))
  }
  RObj(obj)
}

/// Collect the accumulator leaf-names across a scope tree (repeat / multiple cells).
pub fn accum_names(sc : Scope) -> Array[String] {
  let out : Array[String] = []
  collect_accum(sc, out)
  out
}

fn collect_accum(sc : Scope, out : Array[String]) -> Unit {
  for e in sc.entities {
    if e.accumulate && !str_contains(out, e.name) {
      out.push(e.name)
    }
  }
  for g in sc.greedy {
    match g {
      CmdSat(_, child) => collect_accum(child, out)
      _ => ()
    }
  }
}
