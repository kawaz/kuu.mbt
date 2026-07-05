// phase15_wbtest.mbt — the from_entries collector (DR-044 / LOWERING §B.9), replacing the
// 4th-installment key_from 仮実装. It has the 3 usages of JS's Object.fromEntries — entries
// arrays, named {key,value} fields, and {key} promotion — and each nested repeat stage chooses
// array-or-map independently (DR-044 §2: from_entries is attached per group, so a level without
// the key stays an array).

// ── usage (a): from_entries() over an entries array [[k, v], ...] ───────────────

///|
test "DR-044 from_entries(): a 2-element entries array becomes an object" {
  // Usage (a): with no config, each element is a 2-element seq [k, v] (unnamed), used directly
  // as an entry. `[[a,1],[b,2]]` => {a:1, b:2}. This is the entries-array form.
  let data = RArr([
    RArr([RScalar(VStr("a")), RScalar(VNum(1))]),
    RArr([RScalar(VStr("b")), RScalar(VNum(2))]),
  ])
  inspect(render_rval(from_entries(data, Entries)), content="{a:1,b:2}")
}

// ── usage (b): from_entries({key, value}) over named-field objects ──────────────

///|
test "DR-044 from_entries({key,value}): two named fields become the key and value" {
  // Usage (b): each element is an object; the config names which field is the key and which is
  // the value. `[{k:x, v:10}, {k:y, v:20}]` with {key:k, value:v} => {x:10, y:20}. The other
  // fields (none here) are dropped — only the two named fields participate.
  let data = RArr([
    RObj([("k", RScalar(VStr("x"))), ("v", RScalar(VNum(10)))]),
    RObj([("k", RScalar(VStr("y"))), ("v", RScalar(VNum(20)))]),
  ])
  inspect(
    render_rval(from_entries(data, KeyValue("k", "v"))),
    content="{x:10,y:20}",
  )
}

// ── usage (c): from_entries({key}) promotes the key, the rest is the value ──────

///|
test "DR-044 from_entries({key}): the key field is promoted, the REST of the object is the value" {
  // Usage (c): each element is an object; the one named field is promoted to the map key and
  // REMOVED, and the whole remaining object becomes the value. `[{path:/u1, w:1}, {path:/u2, w:2}]`
  // with {key:path} => {/u1:{w:1}, /u2:{w:2}}. This is the form the authsock map uses.
  let data = RArr([
    RObj([("path", RScalar(VStr("/u1"))), ("w", RScalar(VNum(1)))]),
    RObj([("path", RScalar(VStr("/u2"))), ("w", RScalar(VNum(2)))]),
  ])
  inspect(
    render_rval(from_entries(data, KeyPromote("path"))),
    content="{/u1:{w:1},/u2:{w:2}}",
  )
}

// ── per-level independence: each nested stage chooses array or map on its own key ──

///|
test "DR-044 §2: nested stages choose array/map independently — the key present at a level selects it" {
  // A 2-level structure: the OUTER elements carry `path`, the INNER `conns` elements carry `id`
  // (not `path`). Applying from_entries by "path" maps the OUTER level and leaves conns an array
  // (conns have no `path`); applying by "id" instead leaves the outer an array and maps conns.
  // Same data, different key => a different level is mapped — the stages are independent (DR-044
  // §2: from_entries is attached per repeat group, so which level maps is the user's per-scope
  // choice, realized here by which key each level carries).
  let data = RArr([
    RObj([
      ("path", RScalar(VStr("/u1"))),
      (
        "conns",
        RArr([
          RObj([("id", RScalar(VStr("c1"))), ("w", RScalar(VNum(1)))]),
          RObj([("id", RScalar(VStr("c2"))), ("w", RScalar(VNum(2)))]),
        ]),
      ),
    ]),
  ])
  // by "path": outer maps, inner conns (no path) stay an array
  inspect(
    render_rval(from_entries(data, KeyPromote("path"))),
    content="{/u1:{conns:[{id:c1,w:1},{id:c2,w:2}]}}",
  )
  // by "id": outer (no id) stays an array, inner conns map
  inspect(
    render_rval(from_entries(data, KeyPromote("id"))),
    content=(
      #|[{path:/u1,conns:{c1:{w:1},c2:{w:2}}}]
    ),
  )
}
