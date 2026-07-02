// phase12_wbtest.mbt — the authsock-warden nested pattern, built as RAW structure (no
// installer sugar) and parsed with NO new evaluator rule. Exercises: raw exact structure
// matching (--socket/--upstream hitting the next rep with no backbone inside a fired
// element), the pre_filter (NoDashStr) that keeps a permissive repeat from swallowing a
// following trigger, greedy-max 取り分選好 bounded by the Reject, indexed name-scope repeats
// → arrays of objects, and a map-form collector (to_map + key_from).

/// The authsock-warden AtomicAST, hand-built. `with_filter=false` drops the pre_filter to
/// show why it is essential (the negative control). Structure (DR-042 raw):
///   upstreams := IdxRepeat[ --upstream <path> sockets ]   (required, min 1)
///   sockets   := IdxRepeat[ --socket   <path> filters ]   (min 0)
///   filters   := IdxRepeat[ <string, reject '-'-prefixed> ] (min 0)
fn authsock_scope(with_filter : Bool) -> Scope {
  let filter_head : Node = if with_filter { NoDashStr("") } else { StrArg("") }
  let socket_head = Seq([
    Exact("--socket"),
    StrArg("path"),
    IdxRepeat("filters", filter_head, 0),
  ])
  let upstream_head = Seq([
    Exact("--upstream"),
    StrArg("path"),
    IdxRepeat("sockets", socket_head, 0),
  ])
  { greedy: [], positional: [IdxRepeat("upstreams", upstream_head, 1)], entities: [] }
}

fn authsock_input() -> Array[String] {
  [
    "--upstream", "/path/to/up1", "--socket", "~/.ssh/up1-s1.sock", "filter1", "filter1",
    "--socket", "~/.ssh/up1-s2.sock", "f2,f3", "--upstream", "/tmp/foo.sock", "--socket",
    "/tmp/foo-bar.sock",
  ]
}

// ── Test 1: the array-shaped result comes out uniquely ─────────────────────────

test "authsock: nested indexed repeats parse to the expected array-of-objects, uniquely" {
  // --socket / --upstream are matched as raw exact triggers at the head of each rep, WITH NO
  // backbone inside the fired element — the greedy-max repeat lands the next trigger because
  // the pre_filter Rejects the dashed token so filters cannot swallow it. Each firing of a
  // name-scope repeat (multiple:"append") becomes one array element (indexed).
  let sc = authsock_scope(true)
  inspect(
    result_str(sc, authsock_input()),
    content=(
      #|{upstreams:[{path:/path/to/up1,sockets:[{path:~/.ssh/up1-s1.sock,filters:[filter1,filter1]},{path:~/.ssh/up1-s2.sock,filters:[f2,f3]}]},{path:/tmp/foo.sock,sockets:[{path:/tmp/foo-bar.sock,filters:[]}]}]}
    ),
  )
}

// ── Test 2: negative control — without the pre_filter, the wrong parse SILENTLY wins ──

test "authsock 負対照: without pre_filter, greedy over-consumes and the WRONG parse wins silently" {
  // Drop the pre_filter: the permissive `filters` string repeat greedily swallows `--socket`,
  // `--upstream` and every following token as filter values. greedy-max 取り分選好 commits to
  // the longest share, which reaches the end and completes — so a SINGLE (wrong) parse wins
  // with no ambiguity. This is why the pre_filter is essential (DR-043 §auto-narrowing 却下:
  // the fix is the user's explicit filter, not an implicit auto-injected one).
  let sc = authsock_scope(false)
  inspect(
    result_str(sc, authsock_input()),
    content=(
      #|{upstreams:[{path:/path/to/up1,sockets:[{path:~/.ssh/up1-s1.sock,filters:[filter1,filter1,--socket,~/.ssh/up1-s2.sock,f2,f3,--upstream,/tmp/foo.sock,--socket,/tmp/foo-bar.sock]}]}]}
    ),
  )
}

// ── Test 3: the pre_filter Reject bounds the greedy at the correct socket boundary ──

test "authsock: pre_filter Reject stops the greedy filters at the --socket boundary" {
  // A focused case: two sockets under one upstream. filters greedily extends but the dashed
  // --socket Rejects (NoDashStr), so socket0's filters stop at the boundary and socket1 is
  // matched. This is the 取り分選好 (greedy default) landing correctly because the head's
  // Reject bounds it — no downstream backtrack needed for this pattern.
  let sc = authsock_scope(true)
  inspect(
    result_str(sc, ["--upstream", "/u", "--socket", "/a", "x", "y", "--socket", "/b", "z"]),
    content=(
      #|{upstreams:[{path:/u,sockets:[{path:/a,filters:[x,y]},{path:/b,filters:[z]}]}]}
    ),
  )
}

// ── Test 4: map-form collector (to_map + key_from:"path") ───────────────────────

test "authsock map-form: to_map keys each object-array by its `path` field (arrays → maps)" {
  // The map collector (仮実装) turns every array-of-objects into an object keyed by the
  // element's `path` field; scalar arrays (filters) stay arrays. key 抽出のシグネチャ:
  // (RVal, key_from) -> RVal, reading the named scalar field out as the map key.
  let sc = authsock_scope(true)
  let arr = result_rval(sc, authsock_input())
  inspect(
    render_rval(to_map(arr, "path")),
    content=(
      #|{upstreams:{/path/to/up1:{sockets:{~/.ssh/up1-s1.sock:{filters:[filter1,filter1]},~/.ssh/up1-s2.sock:{filters:[f2,f3]}}},/tmp/foo.sock:{sockets:{/tmp/foo-bar.sock:{filters:[]}}}}}
    ),
  )
}
