// result.mbt — layer 3: the name-driven result builder (DR-016 / DR-025 / DR-043).
//
// The evaluator produces flat bindings, each tagged with a result scope path. This folds
// them into a nested result: a name scope becomes an object, a `multiple` accumulator cell
// becomes a value list, and a named indexed repeat (IdxRepeat) becomes an ARRAY of one
// element per firing (multiple:"append"). Result-structure sentinels in the bindings:
//   - key "[]" at a scope  => that scope is an ARRAY; its "#k" child segments are elements
//   - key "{}" at a scope  => that scope is present as an object (even if otherwise empty)
//   - key ""   at a scope  => that scope's element is the SCALAR value (an unnamed leaf)

/// A built result value.
pub(all) enum RVal {
  RScalar(Value)
  RArr(Array[RVal]) // an accumulator list or an indexed-repeat array
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

fn is_sentinel(k : String) -> Bool {
  k == "[]" || k == "{}" || k == ""
}

fn has_direct_key(binds : Array[Binding], key : String) -> Bool {
  for b in binds {
    if b.scope.length() == 0 && b.key == key {
      return true
    }
  }
  false
}

/// The bindings under a scope segment `seg`, with the first path element dropped.
fn sub_under(binds : Array[Binding], seg : String) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in binds {
    if b.scope.length() > 0 && b.scope[0] == seg {
      let rest : Array[String] = []
      let mut i = 1
      while i < b.scope.length() {
        rest.push(b.scope[i])
        i = i + 1
      }
      out.push({
        key: b.key,
        value: b.value,
        source: b.source,
        scope: rest,
        link: b.link,
      })
    }
  }
  out
}

/// Index segments ("#k") among the direct children, ordered by k ascending.
fn ordered_indices(binds : Array[Binding]) -> Array[String] {
  let idxs : Array[String] = []
  for b in binds {
    if b.scope.length() > 0 {
      let seg = b.scope[0]
      if seg.length() >= 1 && seg.substring(start=0, end=1) == "#" && !str_contains(idxs, seg) {
        idxs.push(seg)
      }
    }
  }
  // insertion sort by the integer after '#'
  let mut i = 1
  while i < idxs.length() {
    let key = idxs[i]
    let kn = seg_num(key)
    let mut j = i - 1
    while j >= 0 && seg_num(idxs[j]) > kn {
      idxs[j + 1] = idxs[j]
      j = j - 1
    }
    idxs[j + 1] = key
    i = i + 1
  }
  idxs
}

fn seg_num(seg : String) -> Int {
  // parse the integer after '#'
  let mut n = 0
  let mut i = 0
  for c in seg {
    if i >= 1 {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
    i = i + 1
  }
  n
}

/// Build the nested result value from the winning flat bindings. `accum` is the set of
/// leaf names whose (non-indexed) cell folds into a list (multiple / positional repeat).
pub fn build_result(binds : Array[Binding], accum : Array[String]) -> RVal {
  // ARRAY: a "[]" sentinel at this level => build one element per "#k" child.
  if has_direct_key(binds, "[]") {
    let elems : Array[RVal] = []
    for idx in ordered_indices(binds) {
      elems.push(build_result(sub_under(binds, idx), accum))
    }
    return RArr(elems)
  }
  // gather direct named keys (skip sentinels) and nested (named) scopes
  let named : Array[String] = []
  for b in binds {
    if b.scope.length() == 0 && !is_sentinel(b.key) && !str_contains(named, b.key) {
      named.push(b.key)
    }
  }
  let segs : Array[String] = []
  for b in binds {
    if b.scope.length() > 0 && !str_contains(segs, b.scope[0]) {
      segs.push(b.scope[0])
    }
  }
  // SCALAR element: only an unnamed "" value here, no named keys / nested scopes.
  if has_direct_key(binds, "") && named.length() == 0 && segs.length() == 0 {
    let mut v = VBool(false)
    for b in binds {
      if b.scope.length() == 0 && b.key == "" {
        v = b.value
      }
    }
    return RScalar(v)
  }
  // OBJECT: named leaves (folding accum keys into a list) + nested scopes.
  let obj : Array[(String, RVal)] = []
  for k in named {
    let vals : Array[Value] = []
    for b in binds {
      if b.scope.length() == 0 && b.key == k {
        vals.push(b.value)
      }
    }
    if str_contains(accum, k) {
      let items : Array[RVal] = []
      for v in vals {
        items.push(RScalar(v))
      }
      obj.push((k, RArr(items)))
    } else {
      obj.push((k, RScalar(vals[vals.length() - 1]))) // last-wins (DR-015)
    }
  }
  for seg in segs {
    obj.push((seg, build_result(sub_under(binds, seg), accum)))
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
