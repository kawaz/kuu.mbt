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
        op: b.op,
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
    if str_contains(accum, k) {
      // ACCUMULATE (repeat "flatten" / multiple "append", DR-043/034/036): fold same-key
      // effects in order. A `set` effect appends; an `empty` effect CLEARS the collection
      // (DR-045 empty op), so anything before it is discarded and re-accumulation continues.
      let mut items : Array[RVal] = []
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          match b.op {
            Empty => items = []
            _ => items.push(RScalar(b.value))
          }
        }
      }
      obj.push((k, RArr(items)))
    } else {
      // SCALAR last-wins (DR-015): the last value written to the cell.
      let mut v = VBool(false)
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          v = b.value
        }
      }
      obj.push((k, RScalar(v)))
    }
  }
  for seg in segs {
    obj.push((seg, build_result(sub_under(binds, seg), accum)))
  }
  RObj(obj)
}

/// The `from_entries` collector (DR-044): turns an accumulated ARRAY into an OBJECT. It has the
/// 3 usages of JS's Object.fromEntries, distinguished by how each element supplies (key, value):
///
///   Entries          — `from_entries()`         : each element is a 2-element seq `[k, v]`
///   KeyValue(kf, vf) — `from_entries({key,value})`: each element is an object; kf/vf name the
///                                                    two fields to use as key / value
///   KeyPromote(kf)   — `from_entries({key})`     : each element is an object; kf is PROMOTED to
///                                                    the key and removed, the REST becomes the value
///
/// It recurses through the structure, converting every array whose elements match the spec's
/// shape and leaving the rest (e.g. scalar arrays) as arrays — so applying `KeyPromote("path")`
/// to a nested structure maps every object-array keyed by `path` while a `filters` scalar array
/// stays a list. A stage WITHOUT a matching key keeps its array (per-level independence, DR-044
/// §2: from_entries is attached per repeat group; the key present at a level selects that level).
pub(all) enum FromEntries {
  Entries // (a) no args: [[k, v], ...]
  KeyValue(String, String) // (b) {key, value}: two named fields
  KeyPromote(String) // (c) {key}: promote the key field, the rest is the value
} derive(Eq, Show)

pub fn from_entries(r : RVal, spec : FromEntries) -> RVal {
  match r {
    RScalar(v) => RScalar(v)
    RObj(kvs) => {
      // recurse into an object's field values (a nested array may still match the spec)
      let out : Array[(String, RVal)] = []
      for kv in kvs {
        out.push((kv.0, from_entries(kv.1, spec)))
      }
      RObj(out)
    }
    RArr(elems) =>
      match spec {
        Entries =>
          if all_pairs(elems) {
            let pairs : Array[(String, RVal)] = []
            for e in elems {
              match e {
                RArr(xs) => pairs.push((rval_key_str(xs[0]), from_entries(xs[1], spec)))
                _ => ()
              }
            }
            RObj(pairs)
          } else {
            recurse_arr(elems, spec)
          }
        KeyValue(kf, vf) =>
          if all_have_fields(elems, [kf, vf]) {
            let pairs : Array[(String, RVal)] = []
            for e in elems {
              let k = match rval_field(e, kf) {
                Some(x) => rval_key_str(x)
                None => "?"
              }
              let v = match rval_field(e, vf) {
                Some(x) => x
                None => RScalar(VBool(false))
              }
              pairs.push((k, from_entries(v, spec)))
            }
            RObj(pairs)
          } else {
            recurse_arr(elems, spec)
          }
        KeyPromote(kf) =>
          // map only if EVERY element is an object carrying kf; else this level stays an array
          // (this is the per-level selection: a level without kf is not mapped, DR-044 §2)
          if all_have_fields(elems, [kf]) {
            let pairs : Array[(String, RVal)] = []
            for e in elems {
              match e {
                RObj(fields) => {
                  let mut key = ""
                  let rest : Array[(String, RVal)] = []
                  for kv in fields {
                    if kv.0 == kf {
                      key = rval_key_str(kv.1)
                    } else {
                      rest.push((kv.0, from_entries(kv.1, spec)))
                    }
                  }
                  pairs.push((key, RObj(rest)))
                }
                _ => ()
              }
            }
            RObj(pairs)
          } else {
            recurse_arr(elems, spec)
          }
      }
  }
}

fn recurse_arr(elems : Array[RVal], spec : FromEntries) -> RVal {
  let items : Array[RVal] = []
  for e in elems {
    items.push(from_entries(e, spec))
  }
  RArr(items)
}

/// Look up an object field's value by name; None if absent or the RVal is not an object.
fn rval_field(r : RVal, name : String) -> RVal? {
  match r {
    RObj(kvs) => {
      for kv in kvs {
        if kv.0 == name {
          return Some(kv.1)
        }
      }
      None
    }
    _ => None
  }
}

/// Whether every element is a 2-element array (the `Entries` shape). Empty => false.
fn all_pairs(elems : Array[RVal]) -> Bool {
  if elems.length() == 0 {
    return false
  }
  for e in elems {
    match e {
      RArr(xs) => if xs.length() != 2 { return false }
      _ => return false
    }
  }
  true
}

/// Whether every element is an object carrying ALL the named fields. Empty => false.
fn all_have_fields(elems : Array[RVal], fields : Array[String]) -> Bool {
  if elems.length() == 0 {
    return false
  }
  for e in elems {
    for f in fields {
      match rval_field(e, f) {
        Some(_) => ()
        None => return false
      }
    }
  }
  true
}

fn rval_key_str(r : RVal) -> String {
  match r {
    RScalar(VStr(s)) => s
    RScalar(v) => "\{v}"
    _ => "?"
  }
}

/// Collect the accumulator leaf-names across a scope tree (repeat / multiple cells).
pub fn accum_names(sc : Scope) -> Array[String] {
  let out : Array[String] = []
  collect_accum(sc, out)
  out
}

fn collect_accum(sc : Scope, out : Array[String]) -> Unit {
  for e in sc.entities {
    // any named accumulator (flatten / append / …) folds the cell into a list (DR-036).
    if e.accum.is_some() && !str_contains(out, e.name) {
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
