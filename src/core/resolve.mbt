// resolve.mbt — the value-resolution layer (MDR-002 §3): the value-source ladder (env / config /
// inherit / default seat fill, DR-031 / DR-049 / DR-050), the name-driven result builder (flat
// bindings → nested RVal, DR-016 / DR-025 / DR-043), export-key application (DR-052), and
// export-key collision detection (DR-073). node/value 依存のみ; eval からは経路確定後の後処理
// として呼ばれる (MDR-002 §3 table).
//
// Ported from slice `poc/result.mbt` (full file) and the value-ladder portion of slice
// `poc/installer.mbt` (`resolve_scope` / `resolve_scope_config` / `value_str` — NOT the lowering,
// which stays installer.mbt's job). MDR-003: `e.inherit` → `e.inherit_` (node.mbt already applies
// the trailing-underscore convention).
//
// `value_str` used to live in eval.mbt for the CRequiresIf constraint comparison — this is its
// canonical home per the MDR-002 §3 module table; eval.mbt now calls this file's copy (single
// package, no import needed across files).
//
// DR-074/075 update over the slice: env's string→Value conversion goes through the canonical
// lexers (`parse_number` / `parse_int_value` / `parse_bool`, value.mbt) instead of slice's
// `env_value` which silently fell back to `VStr(s)` on a parse failure — a badly-typed env value
// is now a DR-066 Error (reason `not_a_number` / `not_an_integer` / `not_a_bool`), never a
// wrong-typed cell. `resolve_scope` / `resolve_scope_config` return `Result[.., ParseError]`
// accordingly (slice's config-less `resolve_scope` could not error; it now can, from a bad env
// value).

// ── result value + builder (slice `poc/result.mbt`) ──────────────────────────────────────────

///|
/// A built result value.
pub(all) enum RVal {
  RScalar(Value)
  RArr(Array[RVal]) // an accumulator list or an indexed-repeat array
  RObj(Array[(String, RVal)]) // a name / command scope, keys in first-seen order
} derive(Eq, Debug)

///|
fn str_contains(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

///|
fn is_sentinel(k : String) -> Bool {
  k == "[]" ||
  k == "{}" ||
  k == "" ||
  k == "#row" ||
  k == "#fire" ||
  is_action_key(k) ||
  is_depr_key(k)
}

///|
fn has_direct_key(binds : Array[Binding], key : String) -> Bool {
  for b in binds {
    if b.scope.length() == 0 && b.key == key {
      return true
    }
  }
  false
}

///|
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
      out.push({ ..b, scope: rest })
    }
  }
  out
}

///|
/// Split a flat "#row"-marked binding list (DR-078 §1) into per-row groups, keeping only the
/// bindings after the LAST "#fire" marker (option refire discard, see `build_result`'s ROW-GROUP
/// comment). "#row"/"#fire" sentinels themselves are dropped — each returned group is a row's own
/// flat leaf bindings, ready for a recursive `build_result` call.
fn row_groups(binds : Array[Binding]) -> Array[Array[Binding]] {
  let mut from = 0
  let mut i = 0
  for b in binds {
    if b.scope.length() == 0 && b.key == "#fire" {
      from = i + 1
    }
    i = i + 1
  }
  let groups : Array[Array[Binding]] = []
  i = 0
  for b in binds {
    if i >= from {
      if b.scope.length() == 0 && b.key == "#row" {
        groups.push([])
      } else if !(b.scope.length() == 0 && b.key == "#fire") &&
        groups.length() > 0 {
        groups[groups.length() - 1].push(b)
      }
    }
    i = i + 1
  }
  groups
}

///|
/// Index segments ("#k") among the direct children, ordered by k ascending.
fn ordered_indices(binds : Array[Binding]) -> Array[String] {
  let idxs : Array[String] = []
  for b in binds {
    if b.scope.length() > 0 {
      let seg = b.scope[0]
      if seg.length() >= 1 &&
        seg[0:1].to_owned() == "#" &&
        !str_contains(idxs, seg) {
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

///|
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

///|
/// Apply the result-key axis (DR-052) to the winning bindings, BEFORE build_result. This is a
/// pure result-shape remap — the AtomicAST / parse are untouched (export_key is orthogonal):
///   - a value cell's key: EkKey(s) → s (override); EkNull → "" (nameless: kv 文脈で消え、seq/array
///     文脈では値が nameless 要素として残る); EkUnset → the name (unchanged).
///   - a scope label (command / name scope): EkKey(s) → s; EkNull → DROP the label (子が昇格露出);
///     EkUnset → unchanged. A "{}" presence marker whose only label was dropped floats to the root
///     scope where it is a harmless sentinel (a nameless command has no key — 子が昇格).
/// Sentinels ("[]" / "{}" / "" / "@act:" / "@depr:") and index segments ("#k") are not in the map
/// → kept.
pub fn apply_export_keys(
  binds : Array[Binding],
  ek : Map[String, ExportKey],
) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in binds {
    let new_scope : Array[String] = []
    for seg in b.scope {
      if seg.length() >= 1 && seg[0:1].to_owned() == "#" {
        new_scope.push(seg) // an array index segment — never a name
      } else {
        match ek.get(seg) {
          Some(EkNull) => () // drop the label → children promote to the parent (DR-052 §2)
          Some(EkKey(s)) => new_scope.push(s)
          _ => new_scope.push(seg) // EkUnset or not a mapped name
        }
      }
    }
    let new_key = match ek.get(b.key) {
      Some(EkNull) => "" // nameless value axis
      Some(EkKey(s)) => s
      _ => b.key
    }
    out.push({ ..b, key: new_key, scope: new_scope })
  }
  out
}

///|
/// Apply the result-key axis (DR-052) to the injected default cells, mirroring apply_export_keys on
/// bindings: an EkNull cell is 透過 (dropped from the kv result), an EkKey renames it, and path
/// segments (command scope names) are renamed / promoted the same way. Keeps a flag's preset default
/// subject to the same export transform as its fired value (so `--verbose` with export null neither
/// appears as a value nor re-appears as an injected `false`).
pub fn apply_export_to_defaults(
  defaults : Array[DefaultCell],
  ek : Map[String, ExportKey],
) -> Array[DefaultCell] {
  let out : Array[DefaultCell] = []
  for d in defaults {
    match ek.get(d.name) {
      Some(EkNull) => () // 透過: the value has no result key → not injected
      _ => {
        let new_path : Array[String] = []
        for seg in d.path {
          if seg.length() >= 1 && seg[0:1].to_owned() == "#" {
            new_path.push(seg)
          } else {
            match ek.get(seg) {
              Some(EkNull) => () // dropped scope label → children promote
              Some(EkKey(s)) => new_path.push(s)
              _ => new_path.push(seg)
            }
          }
        }
        let new_name = match ek.get(d.name) {
          Some(EkKey(s)) => s
          _ => d.name
        }
        out.push({ path: new_path, name: new_name, value: d.value })
      }
    }
  }
  out
}

///|
/// An accumulate cell located at a result-scope path (DR-044 uniform array). `path` is the
/// command/name nesting where the cell lives; `name` is its key. The builder needs this so an
/// accumulate cell that fired 0 times still renders `[]` at its home level (not absent).
pub(all) struct AccumCell {
  path : Array[String]
  name : String
  // DR-036 collector (Entity.collector's copy, threaded through so build_result — which only
  // sees AccumCell, never the Scope/Entity it came from — can apply it to the final accumulated
  // array without a second lookup pass). None = no collector (render the plain array).
  collector : String?
} derive(Eq, Debug)

///|
fn path_eq(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    if a[i] != b[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Whether `name` is an accumulate cell declared at result path `path`.
fn cell_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> Bool {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return true
    }
  }
  false
}

///|
/// The DR-036 collector declared for the accum cell at `path`/`name`, or None (`cell_here` already
/// established the cell exists — this is the same lookup, returning the payload instead of a Bool).
fn collector_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> String? {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return c.collector
    }
  }
  None
}

///|
/// DR-036 collector dispatch by name: applies the named collector to an accum cell's final
/// accumulated `RArr`. Only `unwrap_single` is wired end-to-end today (`Entity.collector`'s doc
/// comment, node.mbt) — an unrecognized name is unreachable in practice (decode validates against
/// this same vocab before ever setting `Entity.collector`, `dec_multiple` in
/// json_conformance_wbtest.mbt), so this defensively falls back to identity rather than aborting.
fn apply_collector(name : String, r : RVal) -> RVal {
  match name {
    "unwrap_single" => unwrap_single(r)
    _ => r
  }
}

///|
fn path_push(path : Array[String], seg : String) -> Array[String] {
  let out : Array[String] = []
  for s in path {
    out.push(s)
  }
  out.push(seg)
  out
}

///|
/// Build the nested result value from the winning flat bindings. `cells` locates every
/// accumulate cell by result path (so an empty cell still renders `[]`, DR-044 uniform array);
/// `path` is the current result-scope path.
pub fn build_result(
  binds : Array[Binding],
  cells : Array[AccumCell],
  defaults : Array[DefaultCell],
  path : Array[String],
) -> RVal {
  // ARRAY: a "[]" sentinel at this level => build one element per "#k" child. Elements keep the
  // array's path (an indexed repeat element is not a named result-scope segment cells key on).
  if has_direct_key(binds, "[]") {
    let elems : Array[RVal] = []
    for idx in ordered_indices(binds) {
      elems.push(build_result(sub_under(binds, idx), cells, defaults, path))
    }
    return RArr(elems)
  }
  // ROW-GROUP (DR-078 §1 ref テンプレ result 写像, issue 2026-07-09-ref-template-result-shape):
  // a "#row" sentinel at this level (installer.mbt's `ref_row_head`) marks one repetition's row
  // boundary for a ref-template repeat cell — build one row (recursive build_result over that
  // row's own flat leaf bindings) per "#row"-delimited run. "#fire" (installer.mbt's `inst_long`,
  // option repeat only) marks the start of ONE firing's contribution; multiple 無しの再発火は
  // セル丸ごと上書きなので (DR-034 の axis 分離、last-wins-repeat-rows.json), only the bindings
  // AFTER THE LAST "#fire" survive — with no "#fire" at all (a positional fires its repeat
  // exactly once) the whole list is one firing.
  if has_direct_key(binds, "#row") {
    let rows : Array[RVal] = []
    for row in row_groups(binds) {
      rows.push(build_result(row, cells, defaults, path))
    }
    return RArr(rows)
  }
  // gather direct named keys (skip sentinels) and nested (named) scopes
  let named : Array[String] = []
  for b in binds {
    if b.scope.length() == 0 &&
      !is_sentinel(b.key) &&
      !str_contains(named, b.key) {
      named.push(b.key)
    }
  }
  let segs : Array[String] = []
  for b in binds {
    if b.scope.length() > 0 && !str_contains(segs, b.scope[0]) {
      segs.push(b.scope[0])
    }
  }
  // SCALAR element (seq/array context, DR-052 §2): a lone unnamed "" value at this level — no named
  // keys, no nested scopes, AND no object-forming cell here (an accum cell or a scalar default at this
  // path). The nameless value survives as a scalar ONLY when it is genuinely alone (e.g. a transparent
  // seq element via the "[]" recursion). In kv context — where a sibling cell exists, even as an
  // unfired preset default (transparent-kv sole-binding: `--verbose` null + keep preset false) — the
  // "" value is 透過 and DROPS: control falls through to OBJECT building, where the "" sentinel key is
  // skipped and the sibling default seats, yielding {keep:false} rather than a promoted scalar true.
  let has_object_cell_here = {
    let mut f = false
    for c in cells {
      if path_eq(c.path, path) {
        f = true
        break
      }
    }
    if !f {
      for d in defaults {
        if path_eq(d.path, path) {
          f = true
          break
        }
      }
    }
    f
  }
  if has_direct_key(binds, "") &&
    named.length() == 0 &&
    segs.length() == 0 &&
    !has_object_cell_here {
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
    if cell_here(cells, path, k) {
      // ACCUMULATE (repeat "flatten" / multiple "append", DR-043/034/036): fold same-key
      // effects in order. A `set` effect appends; an `empty` effect CLEARS the collection
      // (DR-045 empty op, committed=true — a deliberate "make it empty"), so anything before
      // it is discarded and re-accumulation continues. An `unset` effect ALSO clears (issue
      // 2026-07-09-accum-filters-non-set-op-semantics: DR-045 "default 値へ戻す" + DR-044/051's
      // accum default=[] compose to "unset resets the accumulated list to []", same as an unfired
      // cell's uniform-array default) but is DISTINCT from `empty` in committed-ness — `empty`
      // commits (source stays `cli`, the fixed-point of a deliberate clear-to-empty), `unset`
      // does NOT commit (source becomes `default`, "as if untouched" — `proj_sources`'s own
      // matching branch reads the same op to report this). `default` clears THE SAME WAY (issue
      // 2026-07-09-accum-fold-update-default-ops, team-lead 裁定 2026-07-10: accum の default 席は
      // DR-051 §2 の一様配列 `[]` — 宣言 default という概念自体を持たない) but stays committed=true
      // like `empty` (locks the ladder, `resolve_entity_raw`'s accum branch already rewrote this
      // binding's `source` to `Default` before it reached here, so the tag comes out right without
      // a default-specific branch on the source side). `update` never reaches this match —
      // `installer.mbt`'s `collect_unsupported_accum_update` rejects a `multiple` element's
      // `update` variant at `parse_definition` time (static definition-error, not a runtime fold
      // check), so no Scope carrying this combination is ever built for `resolve`/`build_result`
      // to see.
      let mut items : Array[RVal] = []
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          match b.op {
            Empty | Unset | Default => items = []
            _ => items.push(RScalar(b.value))
          }
        }
      }
      let arr = RArr(items)
      let collected = match collector_here(cells, path, k) {
        Some(cn) => apply_collector(cn, arr)
        None => arr
      }
      obj.push((k, collected))
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
    // issue 2026-07-09-accum-fold-update-default-ops 追記 (2026-07-10): a ref+repeat option cell
    // registered as an accum entity (`ensure_entity_body`'s BCell arm) that fired 0 times has
    // ONLY its "#fire" marker under `scope=[e.name]` (`inst_long`'s `Scoped(e.name, Bind("#fire",
    // ...))`) — no "#row" sentinel (`ref_row_head`) at all, since `GreedyRepeat` never ran. Its
    // `scope[0]` still lands in `segs` (any `scope.length()>0` binding does, sentinel or not), so
    // recursing here would build an EMPTY OBJECT `{}` from that lone "#fire" and push it — the
    // wrong shape (DR-044 §1 wants `[]` for a 0-fired accum cell, from the UNIFORM ARRAY injection
    // below, not an object built from a stray marker). Skip the recursion for this seg (defer
    // entirely to the injection below) when it names a THIS-path accum cell with no "#row" —
    // fired >=1 time (a real "#row" present) still recurses normally, unaffected.
    let unfired_ref_accum_seg = {
      let mut is_accum = false
      for c in cells {
        if c.name == seg && path_eq(c.path, path) {
          is_accum = true
        }
      }
      is_accum && !has_direct_key(sub_under(binds, seg), "#row")
    }
    if !unfired_ref_accum_seg {
      obj.push(
        (
          seg,
          build_result(
            sub_under(binds, seg),
            cells,
            defaults,
            path_push(path, seg),
          ),
        ),
      )
    }
  }
  // UNIFORM ARRAY (DR-044 §1): an accumulate cell declared at THIS path that fired 0 times still
  // renders `[]` (not absent) — inject empties for cells not already present as named leaves.
  //
  // issue 2026-07-09-accum-fold-update-default-ops 追記 (2026-07-10, ref-repeat-sibling-trigger.json
  // mismatch の修正): a ref+repeat option cell (`ensure_entity_body`'s BCell arm now registers one
  // for its `accum: Some("flatten")`, so `accum_cells` sees it too) needs a DIFFERENT double-render
  // guard than plain `!str_contains(named, c.name)` — its bindings never land in `named` at all
  // (`ref_row_head`'s `Scoped(e.name, ...)` wrap means every binding carries `scope=[e.name, ...]`,
  // never a bare top-level key), so `named` alone can't tell "fired >=1 time, ROW-GROUP already
  // built the real array" apart from "fired 0 times, needs [] injected here". A naive `segs`
  // membership check (± "is this cell's name a nested-scope segment at all") is WRONG in the other
  // direction: `resolve_scope`'s accum branch (this cell's `Entity.accum` seats no CLI binding, so
  // `resolve_entity` always resolves it to `Ok([])`) drops the raw eval-layer bindings entirely
  // before `build_result` ever runs, so THAT path never even reaches `segs` — but conformance's
  // no-resolve path (`run_case`'s `else` arm, `json_conformance_wbtest.mbt`) feeds build_result the
  // RAW eval bindings, where a 0-rep firing still leaves the `"#fire"` marker
  // (`inst_long`'s `Scoped(e.name, Bind("#fire", ...))`) under `scope=[e.name]` — landing THIS in
  // `segs` too, indistinguishable from a real "#row"-bearing firing by name alone. The precise
  // test is whether this cell's OWN nested bindings actually contain a "#row" sentinel (only a
  // real repetition emits one, `ref_row_head`) — check that directly instead of trusting `segs`
  // membership as a proxy for it.
  for c in cells {
    if path_eq(c.path, path) &&
      !str_contains(named, c.name) &&
      !has_direct_key(sub_under(binds, c.name), "#row") {
      let empty : RVal = RArr([])
      let collected = match c.collector {
        Some(cn) => apply_collector(cn, empty)
        None => empty
      }
      obj.push((c.name, collected))
    }
  }
  // DEFAULT SEAT (DR-031 default seat / DR-051 §2): a scalar cell with a default declared at THIS
  // path that received no winning binding renders its default (the flag preset default:false rides
  // here — an unfired flag shows `false`, never absent). Skip names already present as a bound leaf.
  for d in defaults {
    if path_eq(d.path, path) && !str_contains(named, d.name) {
      obj.push((d.name, RScalar(d.value)))
    }
  }
  RObj(obj)
}

///|
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
/// to a nested structure maps every object-array keyed by `path` while a `value_filters` scalar array
/// stays a list. A stage WITHOUT a matching key keeps its array (per-level independence, DR-044
/// §2: from_entries is attached per repeat group; the key present at a level selects that level).
pub(all) enum FromEntries {
  Entries // (a) no args: [[k, v], ...]
  KeyValue(String, String) // (b) {key, value}: two named fields
  KeyPromote(String) // (c) {key}: promote the key field, the rest is the value
} derive(Eq, Debug)

///|
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
                RArr(xs) =>
                  pairs.push((rval_key_str(xs[0]), from_entries(xs[1], spec)))
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

///|
fn recurse_arr(elems : Array[RVal], spec : FromEntries) -> RVal {
  let items : Array[RVal] = []
  for e in elems {
    items.push(from_entries(e, spec))
  }
  RArr(items)
}

///|
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

///|
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

///|
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

///|
fn rval_key_str(r : RVal) -> String {
  match r {
    RScalar(v) => value_str(v)
    _ => "?"
  }
}

///|
/// Locate every accumulate cell (repeat / multiple / separator) by its result-scope path, so
/// the builder can render an empty cell as `[]` (DR-044 uniform array). A command scope nests
/// its cells under the command name; the root scope is path `[]`.
pub fn accum_cells(sc : Scope) -> Array[AccumCell] {
  let out : Array[AccumCell] = []
  collect_accum(sc, [], out)
  out
}

///|
fn collect_accum(
  sc : Scope,
  path : Array[String],
  out : Array[AccumCell],
) -> Unit {
  for e in sc.entities {
    // any named accumulator (flatten / append / …) folds the cell into a list (DR-036).
    if e.accum is Some(_) {
      out.push({ path, name: e.name, collector: e.collector })
    }
  }
  for g in sc.greedy {
    match g {
      CmdSat(name, child) => collect_accum(child, path_push(path, name), out)
      _ => ()
    }
  }
}

///|
/// A scalar cell carrying a default value, located by its result-scope path. The result builder
/// renders this default when the cell is otherwise absent from the winning bindings — realizing the
/// value-source ladder's default seat in the result-object projection (DR-031 default seat). The
/// flag preset (LOWERING §A.5 default:false) rides on this: an unfired flag renders `false` rather
/// than dropping out (DR-051 §2 flag は absent にならない). Accum cells are excluded (they render
/// `[]` via the AccumCell path, DR-044) so a cell has AT MOST one injection source.
pub(all) struct DefaultCell {
  path : Array[String]
  name : String
  value : Value
} derive(Eq, Debug)

///|
pub fn default_cells(sc : Scope) -> Array[DefaultCell] {
  let out : Array[DefaultCell] = []
  collect_defaults(sc, [], out)
  out
}

///|
fn collect_defaults(
  sc : Scope,
  path : Array[String],
  out : Array[DefaultCell],
) -> Unit {
  for e in sc.entities {
    // FLAG/BOOL cells only (LOWERING §A.5 / DR-051 §2): a flag (or DR-074 value-typed bool) carries
    // the preset default:false (or an explicit bool default) and is never absent, so it renders in
    // the result-object projection even where the value-source ladder is not run. A NON-flag cell's
    // default is deliberately NOT injected here — its true value depends on the full ladder (env /
    // config / inherit seats can override the default, e.g. an inheritable ttl resolves via its
    // inherit seat), which this projection does not run; injecting the raw default would surface a
    // wrong value. Those cells stay ladder-resolved.
    if (e.ty == TFlag || e.ty == TBool) && e.accum is None {
      match e.default_value {
        Some(v) => out.push({ path, name: e.name, value: v })
        None => ()
      }
    }
  }
  for g in sc.greedy {
    match g {
      CmdSat(name, child) => collect_defaults(child, path_push(path, name), out)
      _ => ()
    }
  }
}

///|
/// The `unwrap_single` collector (DR-034 縮退ケース, opt-in scalar): unwrap a length-1 array to
/// its element, recursively. This is how an app gets a SCALAR from a repeat/optional cell without
/// the uniform-array default folding it (`optional: true` yields `[x]`; unwrap_single gives `x`).
/// Length 0 or >= 2 arrays are left unchanged (unwrap only applies to the unambiguous single case).
pub fn unwrap_single(r : RVal) -> RVal {
  match r {
    RScalar(v) => RScalar(v)
    RArr(elems) =>
      if elems.length() == 1 {
        unwrap_single(elems[0])
      } else {
        let items : Array[RVal] = []
        for e in elems {
          items.push(unwrap_single(e))
        }
        RArr(items)
      }
    RObj(kvs) => {
      let out : Array[(String, RVal)] = []
      for kv in kvs {
        out.push((kv.0, unwrap_single(kv.1)))
      }
      RObj(out)
    }
  }
}

// ── export-key collision (DR-073: ambiguous 維持 + 解釈ごとの optional claimants 面) ─────────
//
// Superseding slice's `find_export_collision` (single Some(key) — pre-DR-073, the "collision:<key>"
// harness string). DR-021/DESIGN §15.5's runtime check stays (two DIFFERENT elements' export_key
// resolving to the SAME key, both present at the same result scope, in the SAME actual parse — not
// a static declaration check); DR-073 replaces the single-key signal with the interpretations +
// claimants shape so a degenerate collision (both elements same value, e.g. two flags → true) still
// yields distinct (result, claimants) pairs.

///|
/// One export-key collision (DR-073): at result scope `path`, 2+ distinct elements' bindings map
/// (via `ek`) to the same result key `key`. `claimants` lists the distinct entity (pre-export-key)
/// names competing for it, first-seen order.
pub(all) struct ExportCollision {
  path : Array[String]
  key : String
  claimants : Array[String]
} derive(Eq, Debug)

///|
/// Detect every export-key collision in `binds` (DESIGN §15.5, DR-021 → DR-052 → DR-073). Runtime
/// check on the actual co-exposure of a parse, not a static declaration scan (§15.6 stays warn-only
/// at definition time). `binds` are PRE-export-key bindings (raw entity names in `key`); grouping
/// compares the raw `scope` path directly (two bindings at the identical remaining nesting are
/// candidates regardless of depth — no per-level recursion needed, mirroring the original
/// `find_export_collision`'s flat O(n²) scan).
pub fn find_export_collisions(
  binds : Array[Binding],
  ek : Map[String, ExportKey],
) -> Array[ExportCollision] {
  // (path, mapped key) → claimants, built incrementally; a linear scan over few groups is fine at
  // this scale (definitions have small option counts).
  let groups : Array[ExportCollision] = []
  for b in binds {
    match ek.get(b.key) {
      Some(EkKey(mapped)) => {
        let mut found = false
        for g in groups {
          if path_eq(g.path, b.scope) && g.key == mapped {
            if !str_contains(g.claimants, b.key) {
              g.claimants.push(b.key)
            }
            found = true
            break
          }
        }
        if !found {
          groups.push({ path: b.scope, key: mapped, claimants: [b.key] })
        }
      }
      _ => ()
    }
  }
  let out : Array[ExportCollision] = []
  for g in groups {
    if g.claimants.length() > 1 {
      out.push(g)
    }
  }
  out
}

///|
/// One built interpretation (DR-053 §3 result-object view), with the optional DR-073 claimants
/// face: `claimants` maps an exposed key to the entity name that occupies it IN THIS VIEW. Empty
/// when the interpretation carries no export-key collision (the common case).
pub(all) struct Interpretation {
  result : RVal
  claimants : Array[(String, String)]
} derive(Eq, Debug)

///|
/// Build every DR-073 interpretation of `binds`. With no collision this is a single interpretation
/// (empty claimants) — the ordinary export_result rendering. With N simultaneous collision groups,
/// every combination of "which claimant occupies which key" (cross product across groups) is a
/// distinct interpretation: each keeps only its chosen claimant's bindings for that (path, key)
/// group (the other claimants' bindings at that group are dropped from THIS view — DR-073 §2, the
/// entity name is the only cross-view-stable identifier since value/source can coincide) before
/// applying export keys and building the result. `cells`/`defaults` are passed through to
/// `build_result` unchanged (accum cells and defaults are keyed by raw entity name, matching the
/// caller's `accum_cells(sc)` / `apply_export_to_defaults(default_cells(sc), ek)` convention — see
/// slice `poc/helpers_wbtest.mbt`).
pub fn build_interpretations(
  binds : Array[Binding],
  ek : Map[String, ExportKey],
  cells : Array[AccumCell],
  defaults : Array[DefaultCell],
) -> Array[Interpretation] {
  let collisions = find_export_collisions(binds, ek)
  if collisions.length() == 0 {
    let mapped = apply_export_keys(binds, ek)
    return [
      { result: build_result(mapped, cells, defaults, []), claimants: [] },
    ]
  }
  let out : Array[Interpretation] = []
  for combo in claimant_combinations(collisions) {
    let filtered : Array[Binding] = []
    for b in binds {
      let mut drop = false
      let mut gi = 0
      while gi < collisions.length() {
        let c = collisions[gi]
        if path_eq(c.path, b.scope) &&
          c.key ==
          (match ek.get(b.key) {
            Some(EkKey(s)) => s
            _ => ""
          }) &&
          b.key != combo[gi] {
          drop = true
        }
        gi = gi + 1
      }
      if !drop {
        filtered.push(b)
      }
    }
    let mapped = apply_export_keys(filtered, ek)
    let claimants : Array[(String, String)] = []
    let mut gi = 0
    while gi < collisions.length() {
      claimants.push((collisions[gi].key, combo[gi]))
      gi = gi + 1
    }
    out.push({ result: build_result(mapped, cells, defaults, []), claimants })
  }
  out
}

///|
/// Promote a `Success` outcome to `Ambiguous` when its bindings carry an export-key co-exposure
/// collision (DR-021 → DR-073). The collision detection runs against the actual parse (§15.5
/// runtime check), so a definition that DECLARES two elements with the same export_key is only
/// promoted when BOTH elements are present in the same result scope. `Failure` and already-
/// `Ambiguous` outcomes pass through unchanged (structurally-ambiguous outcomes have no export-key
/// collision by construction — they differ in parse structure, not provenance for a shared key).
/// Each promoted interpretation carries the DR-073 §1 claimants面 (exposed key → occupying entity
/// name) so degenerate views (e.g. two flags both `true`) remain distinct under (view, claimants)
/// pair comparison (CONFORMANCE §3, DR-073 §3).
pub fn promote_collision_ambiguous(
  o : Outcome,
  ek : Map[String, ExportKey],
) -> Outcome {
  match o {
    Success(binds) => {
      let collisions = find_export_collisions(binds, ek)
      if collisions.length() == 0 {
        return o
      }
      // Cross product of claimant choices per collision group — each combo picks one claimant per
      // group and drops the rivals' bindings at that (path, mapped-key) from THIS view (DR-073 §2:
      // entity name is the sole cross-view-stable identifier; value/source can coincide).
      let interps : Array[AmbInterp] = []
      for combo in claimant_combinations(collisions) {
        let filtered : Array[Binding] = []
        for b in binds {
          let mut drop = false
          let mut gi = 0
          while gi < collisions.length() {
            let c = collisions[gi]
            if path_eq(c.path, b.scope) &&
              c.key ==
              (match ek.get(b.key) {
                Some(EkKey(s)) => s
                _ => ""
              }) &&
              b.key != combo[gi] {
              drop = true
            }
            gi = gi + 1
          }
          if !drop {
            filtered.push(b)
          }
        }
        let claimants : Array[(String, String)] = []
        let mut gi = 0
        while gi < collisions.length() {
          claimants.push((collisions[gi].key, combo[gi]))
          gi = gi + 1
        }
        interps.push({ binds: filtered, claimants })
      }
      Ambiguous({ interpretations: interps, help_entry: None })
    }
    _ => o
  }
}

///|
/// The cross product of each collision group's claimant choices, e.g. 2 groups of 2 claimants each
/// → 4 combinations, `combo[i]` is the chosen claimant for `collisions[i]`.
fn claimant_combinations(
  collisions : Array[ExportCollision],
) -> Array[Array[String]] {
  let mut combos : Array[Array[String]] = [[]]
  for c in collisions {
    let next : Array[Array[String]] = []
    for combo in combos {
      for claimant in c.claimants {
        next.push(path_push(combo, claimant))
      }
    }
    combos = next
  }
  combos
}

// ── DR-047 §5 明確化 (kawaz 裁定 2026-07-09): bool target requires の後段 path filter ───────────
//
// requires (CRequires) / value 依存 requires (CRequiresIf) の目的語が bool 型 (TFlag/TBool) の
// 場合、充足条件は「値の有無」ではなく「解決後の値が true であること」(値源不問)。この判定は
// 値源ラダー (cli/env/…) が解ける後段でしか行えないため、KTop (eval.mbt, CLI 面のみで完結する
// 完全経路判定) では常に pass 扱いとしてスキップし (`is_bool_entity` が両者の共有ゲート)、ここで
// `parse()` の Outcome を受け取って事後フィルタとして適用する — `promote_collision_ambiguous`
// (DR-073, 直上) と同じ「Outcome を受け取り Outcome を返す後処理」パターン。

///|
/// `name` (entities 内で探した Entity) が bool 型 (TFlag/TBool) かどうか — DR-047 §5 明確化の
/// bool target 判定ゲート。KTop 側の早期スキップ (eval.mbt `eval_constraints`) と、この後段
/// フィルタの両方が参照する共有関数 (2 箇所で判定がズレないようにする)。
pub fn is_bool_entity(entities : Array[Entity], name : String) -> Bool {
  for e in entities {
    if e.name == name {
      return e.ty == TFlag || e.ty == TBool
    }
  }
  false
}

///|
/// bool target `name` の「解決後の値」(DR-047 §5 明確化、値源不問): committed (CLI) が最終
/// (true/false どちらでも CLI 面が勝つ、DR-031 ラダー通り)、非 committed なら env
/// (`entity.env_key` があれば `parse_bool` を試みる)、それも無ければ default_value (bool は
/// LOWERING §A.5 の暗黙 default:false を含め常に何らかの値を持つ)。**config / inherit は対象外**
/// (既知の限界 — 元 issue の 3 ケースが CLI + env で表現できるため、config provider / 親スコープ
/// 探索を持ち込むコストに見合わないと判断。config/inherit 経由でのみ true になる bool target は
/// 現状この判定に反映されない、後続 issue 候補)。
fn resolved_bool_value(
  name : String,
  bindings : Array[Binding],
  path : Array[String],
  entities : Array[Entity],
  env : Map[String, String],
) -> Bool {
  if is_committed(bindings, path, name) {
    return match elem_value(bindings, path, name) {
      Some("true") => true
      _ => false
    }
  }
  for e in entities {
    if e.name == name {
      match e.env_key {
        Some(k) =>
          match env.get(k) {
            Some(s) =>
              match parse_bool(s) {
                Some(b) => return b
                None => ()
              }
            None => ()
          }
        None => ()
      }
      return match e.default_value {
        Some(VBool(b)) => b
        _ => false
      }
    }
  }
  false
}

///|
/// One scope's bool-target `requires`/value 依存 requires violations, evaluated against a
/// CANDIDATE path's bindings (mirrors `eval.mbt`'s `eval_constraints` shape, but restricted to
/// the bool-target predicates KTop skipped). `constraint_err`'s `path` defaults to `[]` (KTop's
/// contract: a Held rides the cont chain and scope boundaries prepend the path on the way out) —
/// that mechanism doesn't run here (the path is already fully resolved), so `sc.path` (DR-066 §4
/// result-nesting path) is threaded in directly via struct-update.
fn eval_bool_requires(
  sc : ScopedCons,
  bindings : Array[Binding],
  pos : Int,
  env : Map[String, String],
) -> Array[ParseError] {
  let out : Array[ParseError] = []
  let path = sc.path
  for c in sc.constraints {
    match c {
      CRequires(elem, targets) =>
        if is_committed(bindings, path, elem) {
          for t in targets {
            if is_bool_entity(sc.entities, t) &&
              !resolved_bool_value(t, bindings, path, sc.entities, env) {
              out.push({
                ..constraint_err(
                  elem,
                  "requires_violated",
                  "'\{elem}' requires '\{t}'",
                  pos,
                ),
                path,
              })
            }
          }
        }
      CRequiresIf(entity, branch_id, v, targets) => {
        let active = is_committed(bindings, path, entity) &&
          (match elem_value(bindings, path, entity) {
            Some(x) => x == v
            None => false
          })
        if active {
          for t in targets {
            if is_bool_entity(sc.entities, t) &&
              !resolved_bool_value(t, bindings, path, sc.entities, env) {
              out.push({
                ..constraint_err(
                  branch_id,
                  "requires_violated",
                  "'\{entity}'=\{v} requires '\{t}'",
                  pos,
                ),
                path,
              })
            }
          }
        }
      }
      CConflicts(_, _) | CExclusive(_, _) => () // committed 基準、値源不問なので KTop で確定済み
    }
  }
  out
}

///|
/// Apply the DR-047 §5 bool-target requires path filter to a `parse()` Outcome (cell_filters と
/// 同じ側の後段処理、`promote_collision_ambiguous` と同型パターン — `parse()` 自体のシグネチャ・
/// eval 層の Ctx は無改修のまま、値源 (env) を後から与える)。生存経路数で outcome を再構成する:
/// 0 → `Failure` (violation を DR-053 §2 全保持で errors に、`fired_action`/`help_entry`/
/// `tried_triggers` は既存 KTop 発 Failure と同じ素材関数から構築 — 区別が付かない形にする、
/// DR-048 の「候補経路は dead end を含む」通り違反で落ちた経路の action も候補に数える)、
/// 1 → その経路で `Success`、2+ → 生存分だけの `Ambiguous`。`root`/`defs` は制約テーブル
/// (`collect_scopes`) と `find_help_entry`/`tried_triggers_of` の素材取得に使う。
pub fn apply_bool_requires_filter(
  o : Outcome,
  root : Node,
  defs : Map[String, Node],
  env : Map[String, String],
  toks_len : Int,
) -> Outcome {
  let table = collect_scopes(root, defs)
  let violations_of = fn(binds : Array[Binding]) -> Array[ParseError] {
    let out : Array[ParseError] = []
    for sc in table {
      for v in eval_bool_requires(sc, binds, toks_len, env) {
        out.push(v)
      }
    }
    out
  }
  let build_failure = fn(
    binds_for_actions : Array[Array[Binding]],
    errors : Array[ParseError],
  ) -> Outcome {
    let actions : Array[(String, Int)] = []
    for bs in binds_for_actions {
      collect_actions(bs, actions)
    }
    Failure({
      errors,
      fired_action: if actions.length() > 0 {
        Some(argmin_action(actions))
      } else {
        None
      },
      help_entry: find_help_entry(root),
      tried_triggers: tried_triggers_of(root, errors),
    })
  }
  match o {
    Success(binds) =>
      match violations_of(binds) {
        [] => o
        viol => build_failure([binds], viol)
      }
    Ambiguous(d) => {
      let survivors : Array[AmbInterp] = []
      let all_violations : Array[ParseError] = []
      let all_binds : Array[Array[Binding]] = []
      for interp in d.interpretations {
        all_binds.push(interp.binds) // DR-048: dead-end (違反除外) 経路も action 候補に数える
        match violations_of(interp.binds) {
          [] => survivors.push(interp)
          viol =>
            for v in viol {
              all_violations.push(v)
            }
        }
      }
      match survivors.length() {
        0 => build_failure(all_binds, all_violations)
        1 => Success(survivors[0].binds)
        _ => Ambiguous({ interpretations: survivors, help_entry: d.help_entry })
      }
    }
    Failure(_) => o
  }
}

// ── value-source ladder (slice `poc/installer.mbt`'s resolve_scope / resolve_scope_config) ───

///|
/// A Value rendered as its comparison string (constraint value matching: integers print without
/// the trailing `.0`). The resolve layer owns the result-object rendering; this is also the
/// CRequiresIf comparison form (moved here from eval.mbt, MDR-002 §3 table — this is resolve.mbt's
/// canonical home; eval.mbt's `elem_value` calls this file's copy, same package).
fn value_str(v : Value) -> String {
  match v {
    VStr(s) => s
    VBool(b) => if b { "true" } else { "false" }
    VNum(d) => {
      let i = d.to_int()
      if i.to_double() == d {
        i.to_string()
      } else {
        d.to_string()
      }
    }
  }
}

///|
/// A DR-066 ladder-fill Error: `element`/`argv_pos` locate it like any ParseError; `at_pos` is the
/// caller-supplied final position (env/config seat errors are not read at a token position — they
/// surface after the path completed, the same conceptual point `eval_constraints` evaluates at, so
/// callers thread the same final `toks.length()`). kind is always `KParse` (a value-source failed
/// to parse into the entity's type — the same category as a bad CLI token, DR-053). `epath` is the
/// DR-066 §4 ancestor path (root-first, [] = root 直下): this ladder walk resolves ONE scope's
/// entities at a time and already carries the scope's own result-nesting path (the `resolve_tree`
/// caller threads it in), so — unlike eval.mbt's CPS Held (which starts at [] and picks up ancestors
/// crossing scope boundaries on the way out) — the ladder path is known statically and passed in
/// directly, no boundary-crossing accumulation needed.
fn ladder_err(
  element : String,
  at_pos : Int,
  reason : String,
  message : String,
  epath : Array[String],
) -> ParseError {
  { element, argv_pos: at_pos, kind: KParse, reason, message, path: epath }
}

///|
/// A DR-053 §2 filter-reject Error: `value_filters`/`cell_filters` (DR-009 §7) rejected an already-
/// resolved value. Distinct from `ladder_err` (`kind: KParse`, a value-source failed to parse) —
/// a filter reject is a validation/transform rejection over a value that parsed fine, so it gets
/// its own builder with `kind: KFilter` (DR-053 §2's 3-way `parse` | `filter` | `constraint` split;
/// `eval.mbt`'s `filter_arg_eval` already emits `KFilter` for the same conceptual failure at the
/// token-parsing layer, this is `apply_entity_filters`'s resolve-layer counterpart). Same
/// `at_pos`/`epath` threading contract as `ladder_err`.
fn filter_err(
  element : String,
  at_pos : Int,
  reason : String,
  message : String,
  epath : Array[String],
) -> ParseError {
  { element, argv_pos: at_pos, kind: KFilter, reason, message, path: epath }
}

///|
/// The DR-066 reason for a `parse_int_value` failure.
fn int_fail_reason(f : ParseFail) -> String {
  match f {
    NotANumber => "not_a_number"
    NotAnInteger => "not_an_integer"
    IntOutOfRange => "int_out_of_range"
  }
}

///|
/// The human-readable (message field is never conformance-compared, DR-066 §4) phrase for a
/// `parse_int_value` failure.
fn int_fail_phrase(f : ParseFail) -> String {
  match f {
    NotANumber => "a number"
    NotAnInteger => "an integer"
    IntOutOfRange => "within Int64 range"
  }
}

///|
/// Apply an `update` effect's transform to the running `old` value (DR-077 §1/§2: `cell = f(old)`).
/// `transform` is looked up in the filters registry (DR-077 §2 "transform の実体は filters registry
/// の名前参照") — `installer.mbt`'s `classify_long_spelling` (definition-time gate, codex 指摘 2 /
/// DR-077 §2 の裁定で `parts[2] == "increment"` のハードコード allowlist から registry lookup +
/// signature チェックへ置換済み) already rejects an unregistered name or a non-`Transform`-signature
/// name as `unknown-vocab` (DR-054) at DEFINITION time, so `apply_transform` seeing either here
/// should never actually happen in practice — the `None` / non-`Transform` branches are defensive,
/// not a live path. `args` (DR-077 §2's `:update:<name>:arg...` nesting convention) is threaded
/// straight through to the registered closure unchecked — arity is a RUNTIME concern the closure
/// itself enforces (mirrors `apply_filter_chain`'s split), so the 3rd branch (`d.run` itself
/// rejecting, e.g. a genuine arity mismatch) IS a live path even after the definition-time gate.
fn apply_transform(
  transform : String,
  old : Value,
  args : Array[String],
  name : String,
  at_pos : Int,
  epath : Array[String],
) -> Result[Value, ParseError] {
  match lookup_filter(transform) {
    None =>
      // codex 指摘 3 (issue 2026-07-09, 節目レビュー): defensive kind を KParse (ladder_err) から
      // KFilter (filter_err) へ — 「値がパースできなかった」ではなく「filter/transform 語彙の拒否」
      // なので DR-053 §2 の 3 分類上 filter が正しい (filter_err の doc comment 参照)。
      Err(
        filter_err(
          name,
          at_pos,
          "unknown_update_transform",
          "unknown update transform '\{transform}'",
          epath,
        ),
      )
    Some(d) =>
      if d.signature != Transform {
        // DR-077 §2 「シグネチャ不適合 → definition-error」: reached here only if the filters
        // registry later grows a name whose signature is Validate but installer.mbt's
        // classify_long_spelling (definition-time gate) ever let it through — defensive, not a
        // live path today. kind: KFilter (codex 指摘 3、上と同じ理由)。
        Err(
          filter_err(
            name,
            at_pos,
            "update_transform_type_mismatch",
            "filter '\{transform}' is not a transform (validate-only filters cannot be used as an update transform)",
            epath,
          ),
        )
      } else {
        match (d.run)(old, args) {
          Ok(v) => Ok(v)
          Err(msg) =>
            // live path (arity mismatch 等、closure 自身の拒否) — defensive な上 2 分岐と同じ理由で
            // kind: KFilter に揃える (team-lead 指摘は上 2 分岐限定だったが、同一関数内の同じ
            // reason-family を KParse のまま残すのは内部不整合なので合わせて修正、報告に明記)。
            Err(
              filter_err(
                name, at_pos, "update_transform_type_mismatch", msg, epath,
              ),
            )
        }
      }
  }
}

///|
/// Parse an env string into a Value per the entity's type (DR-049 §2: env goes through the same
/// pipeline as CLI). Unlike slice's `env_value` (naive `parse_number` with a silent `VStr` fallback
/// on failure), this reuses the canonical lexers (DR-074/075) and surfaces a parse failure as a
/// DR-066 Error — a badly-typed env value is never silently coerced to a wrong-typed string cell.
/// `piece_filters` (DR-034/DR-062, issue 2026-07-09-pre-split-filters-execution-wiring): DR-049 §2
/// says env goes through the SAME pipeline as CLI, which includes piece_filters — applied here BEFORE
/// the type-specific parse below (including the `TStr` arm, so `trim` etc. also affects a plain
/// string env value, not just numeric rescue). This is env's OWN application point, distinct from
/// the CLI seat's (eval.mbt/matcher.mbt, applied at token-consumption time, before the value ever
/// reaches this Entity-based ladder).
fn env_value(
  element : String,
  ty : Ty,
  s : String,
  piece_filters : Array[String],
  at_pos : Int,
  epath : Array[String],
) -> Result[Value, ParseError] {
  let s = match apply_piece_filters(piece_filters, s) {
    Ok(v) => v
    Err((reason, msg)) =>
      return Err(filter_err(element, at_pos, reason, msg, epath))
  }
  match ty {
    TStr => Ok(VStr(s))
    // DR-077 §3: count's env/config seat parses a plain number and SETs it (never increments) —
    // the same lexicon TNum uses. `Entity.ty` is already collapsed to TNum by `ensure_entity` for
    // every real count cell, so `TCount` never actually arrives here in practice; folded into the
    // same arm defensively (this function's job is purely "how does this Ty parse", independent of
    // which effect op eventually carries the result — DR-077 §3's `VERBOSITY=5` sets 5, it never
    // increments, and this arm is exactly that: a plain env-string → number parse, no old/update
    // involved at all).
    TNum | TCount =>
      match parse_number(s) {
        Some(d) => Ok(VNum(d))
        None =>
          Err(
            ladder_err(
              element,
              at_pos,
              "not_a_number",
              "env value \"\{s}\" is not a number",
              epath,
            ),
          )
      }
    TInt =>
      match parse_int_value(s, RError) {
        Ok(i) => Ok(VNum(i.to_double()))
        Err(f) =>
          Err(
            ladder_err(
              element,
              at_pos,
              int_fail_reason(f),
              "env value \"\{s}\" is not \{int_fail_phrase(f)}",
              epath,
            ),
          )
      }
    TFloat =>
      match parse_float(s) {
        Some(d) => Ok(VNum(d))
        None =>
          Err(
            ladder_err(
              element,
              at_pos,
              "not_a_number",
              "env value \"\{s}\" is not a number",
              epath,
            ),
          )
      }
    TFlag | TBool =>
      match parse_bool(s) {
        Some(b) => Ok(VBool(b))
        None =>
          Err(
            ladder_err(
              element,
              at_pos,
              "not_a_bool",
              "env value \"\{s}\" is not a bool",
              epath,
            ),
          )
      }
  }
}

///|
/// Navigate a config object by an absolute path (DR-050 §3). Each segment indexes into a CObj;
/// a missing key or a non-object mid-path yields None (this cell is not supplied by config).
fn config_lookup(obj : ConfigVal, path : Array[String]) -> ConfigVal? {
  let mut cur = obj
  for seg in path {
    match cur {
      CObj(kvs) => {
        let mut found : ConfigVal? = None
        for kv in kvs {
          if kv.0 == seg {
            found = Some(kv.1)
          }
        }
        match found {
          Some(v) => cur = v
          None => return None
        }
      }
      _ => return None
    }
  }
  Some(cur)
}

///|
/// Resolve one entity down the fixed ladder: cli > env > config > inherit > default (DR-031 /
/// DR-050 #3). Returns the effect bindings (0/1, or many when a config array fills a `multiple`
/// cell) or an Err (a value-source type mismatch is a DR-037/DR-066 Error). `config_obj` is the
/// read config object (None = no config); `config_path` is this entity's absolute lookup path
/// (同型 or config_key, used for the config LOOKUP — may diverge from `epath` under an explicit
/// `config_key`). `at_pos` is the position an Error is reported at (see `ladder_err`). `epath` is
/// this entity's DR-066 §4 error path: the DECLARING scope's result-nesting path (root-first,
/// [] = root 直下) — always the scope path, never `config_path`, so a config_key override does not
/// leak an unrelated config-tree location into the error's ancestor scope list.
fn resolve_entity(
  e : Entity,
  cli : Array[Binding],
  env_map : Map[String, String],
  config_obj : ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, Value],
  at_pos : Int,
  epath : Array[String],
) -> Result[Array[Binding], ParseError] {
  match
    resolve_entity_raw(
      e, cli, env_map, config_obj, config_path, inherited, at_pos, epath,
    ) {
    Ok(bs) => apply_entity_filters(e, bs, at_pos, epath)
    Err(pe) => Err(pe)
  }
}

///|
/// DR-009 §value_filters/cell_filters applied to whatever `resolve_entity_raw` resolved (any ladder
/// seat: cli/env/config/inherit/default — DR-077 §1's whole point is that `set` and `update`
/// effects converge here indistinguishably). `value_filters` (each) applies to every binding; `cell_filters`
/// (累積後の最終値) applies ONLY to a scalar cell's (no accum) single binding — a `multiple`/accum
/// cell's TRUE "post accumulation" point is build_result (resolve.mbt's caller), which this function
/// does not reach; extending cell_filters to the accumulated array is a follow-up (this issue's
/// scope is the count/update scalar case DR-077 §1 needed proven, not the general multiple case).
/// `Empty`'s binding carries a PLACEHOLDER value (DR-045 — the real "clear the collection" effect
/// has no value of its own), so it's exempt from both chains — running a number/string filter over
/// a bogus `VBool(false)` placeholder would be nonsensical.
fn apply_entity_filters(
  e : Entity,
  bs : Array[Binding],
  at_pos : Int,
  epath : Array[String],
) -> Result[Array[Binding], ParseError] {
  let out : Array[Binding] = []
  for b in bs {
    // value_filters(each、段5) applies only to a binding carrying a REAL value (kawaz 裁定
    // 2026-07-09、issue accum-filters-non-set-op-semantics): `Set` (a plain value bind) and
    // `Update`'s applied result. The scalar CLI-seat fold (resolve_entity_raw's non-accum branch)
    // already converts a committed `Update` to a `Set` binding via `mkb` before it ever reaches
    // here, so this function never special-cases `Update` itself — checking `op == Set` alone
    // covers both. `Unset`/`Default`/`Empty` are operations ON THE CELL, not a piece carrying a
    // value — their bindings carry no meaningful operand (placeholder values, `mk_eff`'s doc
    // comment) and must pass through untouched. This generalizes the old "only `Empty` is exempt"
    // rule: for a SCALAR cell the fold above already collapses everything else to `Set`/`Empty`
    // so the two rules were equivalent there, but an ACCUM cell's fold (resolve_entity_raw's
    // `e.accum is Some(_)` branch) preserves every op UNINTERPRETED — without this
    // generalization, a `Default`/`Unset` binding's placeholder value would wrongly run through
    // `e.value_filters` (issue's `--ports 5 --reset-ports` repro).
    if b.op != Set {
      out.push(b)
    } else {
      match apply_filter_chain(e.value_filters, b.value) {
        Err((reason, msg)) => {
          // value_filters(each、段5、DR-009): CONFORMANCE §3's piece-attribution rule — a reject here
          // is attributed to the SPECIFIC argv token the rejected piece came from (`b.at_pos`,
          // issue 2026-07-09-accum-entity-filters-wiring), not the ladder's own `at_pos` (which
          // stays argv.length — the "no specific token" fallback for env/config/inherit/default-
          // sourced bindings, where `b.at_pos` is always `None`).
          let pos = match b.at_pos {
            Some(p) => p
            None => at_pos
          }
          return Err(filter_err(e.name, pos, reason, msg, epath))
        }
        Ok(v) => {
          let b2 = { ..b, value: v }
          if e.accum is None {
            match apply_filter_chain(e.cell_filters, b2.value) {
              Err((reason, msg)) =>
                return Err(filter_err(e.name, at_pos, reason, msg, epath))
              Ok(v2) => out.push({ ..b2, value: v2 })
            }
          } else {
            out.push(b2)
          }
        }
      }
    }
  }
  Ok(out)
}

///|
/// The pre-DR-009-filters ladder resolution (cli > env > config > inherit > default) — unchanged
/// behavior from before this issue, just renamed so `resolve_entity` can wrap it with filter chain
/// application (`apply_entity_filters`) without duplicating the ladder logic.
fn resolve_entity_raw(
  e : Entity,
  cli : Array[Binding],
  env_map : Map[String, String],
  config_obj : ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, Value],
  at_pos : Int,
  epath : Array[String],
) -> Result[Array[Binding], ParseError] {
  // cli seat (DR-015 last-wins + DR-077 §1 update fold): fold every same-name CLI effect in argv
  // order, not just peek at the last one. `update`'s result is OLD-DEPENDENT — a single "read the
  // last binding" can no longer resolve the seat once update effects are mixed with
  // set/default/empty/unset (`-vvv` needs old=0→1→2, each rep depending on the ONE before it). For
  // every definition that never uses `update`, this fold degenerates to EXACTLY the prior "last
  // committed op wins" read (each non-update op still just replaces `current` outright, same as
  // before) — DR-015's last-wins guarantee (fixture multiple-parse/last-wins-scalar.json) is a
  // special case of this fold, not a different algorithm.
  // `current` holds the FULL binding (not just its value) — Set/Default/Empty must be returned
  // VERBATIM downstream (Empty's `value` is a placeholder that a later result-builder interprets
  // by `op`, not by `value`; Default's `source` must read `Default`, not `Cli`) exactly as the
  // pre-fold code did (`return Ok([b])` / `return Ok([mkb(e.name, v, Default)])`). Only `update`
  // needs the running VALUE (as `old`) — `.value` is read off `current` at that point, never
  // reconstructed from scratch.
  // accum セル (multiple/repeat, DR-034/043): the CLI seat must preserve EVERY same-name Binding,
  // not fold to "last wins" — build_result's ACCUMULATE branch (resolve.mbt's caller,
  // `Empty`/`Unset`/`Default` = clear-point, else = append) is the layer that interprets the op
  // sequence, exactly as it already does for the raw-bind bypass path this issue is replacing.
  // apply_entity_filters (this function's caller) then runs value_filters(each) over each
  // preserved piece.
  //
  // issue 2026-07-09-accum-fold-update-default-ops (team-lead 裁定 2026-07-10、その後の再裁定込み):
  // `default`/`unset` need CLI-seat-level interpretation here (this loop), unlike the scalar
  // branch's full fold this stays a THIN pass — only `committed` tracking + 1 rewrite, the actual
  // clear-and-reaccumulate logic stays in build_result:
  // - `update`: NEVER reaches this loop — `installer.mbt`'s `collect_unsupported_accum_update`
  //   rejects a `multiple` element's `update` variant at `parse_definition` time (静的
  //   definition-error, DR-077 §2 の「transform でない・存在しない → definition-error」ファミリの
  //   3例目)。old = the cell's current value, which for an accum cell is the accumulated array
  //   (T[]) while every filters-registry transform is T=>T (scalar) — a structural mismatch with
  //   no legal resolution, so closing it statically (rather than at fold time) matches how
  //   DR-077 §2 already closes "unknown transform name" / "validate-only signature" one layer
  //   earlier (`classify_long_spelling`'s `LInvalid`). The `Update` arm below is unreachable
  //   defensive code, not a live path.
  // - `default`: resets to `[]` (DR-051 §2's uniform-array default — an accum cell carries no
  //   declared default BY DESIGN, `AccumCell` has no such field) with committed=true (locks the
  //   ladder, mirrors scalar's `unset-ladder.json` default-commits-locked precedent). The op itself
  //   carries no operand, so there's no piece for value_filters/cell_filters to act on (DESIGN
  //   §8.3) — build_result's ACCUMULATE match folds `Default` exactly like `Empty`/`Unset` (a
  //   clear-point), so only the SOURCE TAG differs here: rewriting `source` to `Default` (mirrors
  //   scalar's `mkb(e.name, v, Default)`) keeps `proj_sources`/harness correct without a
  //   default-specific branch there.
  // - `unset`: stays uncommitted (committed=false, unchanged from before) — if every same-name CLI
  //   effect in this seat ends up uncommitted, the CLI seat falls through to the lower ladder rungs
  //   (env/config/inherit/default) below, exactly like the scalar branch already does
  //   (`unset-ladder.json`'s `unset-opens-ladder`) — this is the new `committed_now` gate replacing
  //   the old unconditional `bs.length() > 0` return.
  if e.accum is Some(_) {
    let bs : Array[Binding] = []
    let mut committed_now = false
    for b in cli {
      if b.key == e.name {
        match b.op {
          Update(_, _) =>
            // team-lead 裁定 2026-07-10 (更新): accum×update は実行時 Err ではなく静的
            // definition-error (`installer.mbt`'s `collect_unsupported_accum_update`) — a
            // `multiple` element carrying an `update` variant is rejected at `parse_definition`
            // time, before a Scope (and this function) ever exists. This arm is therefore
            // unreachable in practice; `abort` makes that contract visible instead of silently
            // mis-handling a binding that should never arrive.
            abort(
              "unreachable: an accum (multiple) entity's `update` variant is rejected at definition time (installer.mbt's collect_unsupported_accum_update) — resolve_entity_raw should never see one",
            )
          Default => {
            bs.push({ ..b, source: Default })
            committed_now = true
          }
          Unset => {
            bs.push(b)
            committed_now = false
          }
          Set | Empty => {
            bs.push(b)
            committed_now = true
          }
        }
      }
    }
    if committed_now {
      return Ok(bs)
    }
  } else {
    let mut current : Binding? = None
    let mut committed_now = false
    for b in cli {
      if b.key == e.name {
        match b.op {
          Set => {
            current = Some(b)
            committed_now = true
          }
          Default =>
            match e.default_value {
              Some(v) => {
                current = Some(mkb(e.name, v, Default))
                committed_now = true
              }
              None => {
                current = Some(b)
                committed_now = true
              }
            }
          Empty => {
            current = Some(b)
            committed_now = true
          }
          // NOT committed: resets the running value to default so a LATER update in the same
          // fold sees the right "old" — but this seat stays eligible to fall through to
          // env/config/inherit if nothing commits after it (unchanged pre-DR-077 contract).
          Unset => {
            current = match e.default_value {
              Some(v) => Some(mkb(e.name, v, Default))
              None => None
            }
            committed_now = false
          }
          Update(transform, args) => {
            // DR-077 §2 "old ?? default": no prior commit in THIS fold falls back to the entity's
            // own default (which count presets to 0, LOWERING §A.5) — never a bare literal zero.
            let old = match current {
              Some(cb) => cb.value
              None =>
                match e.default_value {
                  Some(v) => v
                  None => VNum(0.0)
                }
            }
            match apply_transform(transform, old, args, e.name, at_pos, epath) {
              Ok(v) => {
                current = Some(mkb(e.name, v, Cli))
                committed_now = true
              }
              Err(pe) => return Err(pe)
            }
          }
        }
      }
    }
    if committed_now {
      match current {
        Some(b) => return Ok([b])
        None => ()
      }
    }
  }
  // env seat (DR-049 §2): the raw env string is ONE firing's argument (同 §2 「発火 1 回の 1 引数と
  // 同じ扱い」) — a `multiple` + `separator` cell splits it exactly like `eval.mbt`'s `sep_binds`
  // splits the CLI seat's own raw token (issue 2026-07-09-env-separator-split-gap): each piece
  // runs the SAME pieceProcessor (`env_value`'s piece_filters → parse) independently, and any
  // piece's failure fails the whole seat (all-or-nothing, mirrors `sep_binds`'s contract). No
  // `separator` (the common case) stays exactly the prior single-binding behavior.
  match e.env_key {
    Some(k) =>
      match env_map.get(k) {
        Some(v) =>
          match e.separator {
            Some(sep) => {
              let bs : Array[Binding] = []
              for part in split_on(v, sep) {
                match
                  env_value(e.name, e.ty, part, e.piece_filters, at_pos, epath) {
                  Ok(parsed) => bs.push(mkb(e.name, parsed, Env))
                  Err(pe) => return Err(pe)
                }
              }
              return Ok(bs)
            }
            None =>
              match env_value(e.name, e.ty, v, e.piece_filters, at_pos, epath) {
                Ok(parsed) => return Ok([mkb(e.name, parsed, Env)])
                Err(pe) => return Err(pe)
              }
          }
        None => ()
      }
    None => ()
  }
  // config seat (DR-050 #3): look up this cell in the config object; type per §4.
  if e.config_seat {
    match config_obj {
      Some(obj) =>
        match config_lookup(obj, config_path) {
          Some(cv) =>
            match cv {
              // JSON null = 供給なし (DR-050 §4 / DR-051): the config seat supplies nothing; fall
              // through to inherit / default (null is NOT a value in kuu's value space).
              CNull => ()
              // array → a multiple cell's pieces (DR-050 §4); each item typed per §4 — including
              // §4's string pipeline (issue 2026-07-09-config-string-pieceprocessor-gap), so a
              // string array item ALSO runs `e.piece_filters` before its type parse.
              CArr(items) =>
                if e.accum is Some(_) {
                  let bs : Array[Binding] = []
                  for it in items {
                    match config_to_value(it, e.ty, e.piece_filters) {
                      Ok(v) => bs.push(mkb(e.name, v, Config))
                      Err((KFilter, reason, msg)) =>
                        return Err(
                          filter_err(e.name, at_pos, reason, msg, epath),
                        )
                      Err((_, reason, msg)) =>
                        return Err(
                          ladder_err(e.name, at_pos, reason, msg, epath),
                        )
                    }
                  }
                  return Ok(bs)
                } else {
                  return Err(
                    ladder_err(
                      e.name,
                      at_pos,
                      "config_structural_mismatch",
                      "config array for a scalar element (structural mismatch)",
                      epath,
                    ),
                  )
                }
              // DR-050 §4 の string 全段 pipeline (issue 2026-07-09-config-string-pieceprocessor-gap):
              // `config_to_value` が `e.piece_filters` を先頭で適用してから型 parse する — CLI/env の
              // pieceProcessor と同じ窓口。
              _ =>
                match config_to_value(cv, e.ty, e.piece_filters) {
                  Ok(v) => return Ok([mkb(e.name, v, Config)])
                  Err((KFilter, reason, msg)) =>
                    return Err(filter_err(e.name, at_pos, reason, msg, epath))
                  Err((_, reason, msg)) =>
                    return Err(ladder_err(e.name, at_pos, reason, msg, epath)) // §4 型不一致 → DR-037/DR-066 Error
                }
            }
          None => () // not present in config → fall through
        }
      None => () // no config object (no config_file, or default-path read failure) → fall through
    }
  }
  // inherit seat (DR-031 / DR-013). MDR-003: `inherit` 予約語回避 → `inherit_`.
  if e.inherit_ {
    match inherited.get(e.name) {
      Some(v) => return Ok([mkb(e.name, v, Inherit)])
      None => ()
    }
  }
  // default seat
  match e.default_value {
    Some(v) => Ok([mkb(e.name, v, Default)])
    None => Ok([])
  }
}

///|
/// Resolve every entity in a built scope against CLI bindings + an env map (no config seat). For
/// the env / inherit ladder path (no config_file element in scope). Unlike slice (whose config-less
/// path "never errors"), a badly-typed env value now surfaces as an Err (DR-074/075 update above).
/// `path` is this scope's DR-066 §4 result-nesting path (root-first, [] = root 直下), threaded into
/// any ladder-fill Error the same way `resolve_scope_config`'s `path` is.
pub fn resolve_scope(
  sc : Scope,
  cli : Array[Binding],
  env_map : Map[String, String],
  inherited? : Map[String, Value] = Map([]),
  at_pos? : Int = -1,
  path? : Array[String] = [],
) -> Result[Array[Binding], ParseError] {
  let out : Array[Binding] = []
  for e in sc.entities {
    match resolve_entity(e, cli, env_map, None, [], inherited, at_pos, path) {
      Ok(bs) =>
        for b in bs {
          out.push(b)
        }
      Err(pe) => return Err(pe)
    }
  }
  Ok(out)
}

///|
/// Resolve a scope WITH a config-file value source (DR-050 §5 dependency order):
///   1. resolve the config_file element's path (cli > env > default; it has NO config seat, 循環禁止)
///   2. read the provider with that path → a config object (or None). A committed path (cli/env)
///      that reads None is a DR-037/DR-066 Error (指定したのに読めない); a default path reading
///      None is silently tolerated (config seat stays empty)
///   3. resolve every (non config_file) entity down cli > env > config > inherit > default, using
///      the config object and each entity's absolute config path (config_key, else 同型 = scope path + name)
/// `provider` is the config_provider stub (path → config object | None). `path` is this scope's
/// result path (for 同型 correspondence). `at_pos` is the position an Error is reported at.
pub fn resolve_scope_config(
  sc : Scope,
  cli : Array[Binding],
  env_map : Map[String, String],
  provider : (String) -> ConfigVal?,
  path? : Array[String] = [],
  inherited? : Map[String, Value] = Map([]),
  at_pos? : Int = -1,
) -> Result[Array[Binding], ParseError] {
  // Phase 1: resolve the config_file element's path (cli > env > default), track committed-ness.
  let mut cf_path : String? = None
  let mut cf_committed = false
  let mut cf_element = ""
  for e in sc.entities {
    if e.is_config_file {
      cf_element = e.name
      let mut done = false
      for b in cli {
        if b.key == e.name {
          match b.op {
            Set => {
              cf_path = Some(value_str(b.value))
              cf_committed = true
              done = true
            }
            _ => ()
          }
        }
      }
      if !done {
        match e.env_key {
          Some(k) =>
            match env_map.get(k) {
              Some(v) => {
                cf_path = Some(v)
                cf_committed = true
                done = true
              }
              None => ()
            }
          None => ()
        }
      }
      if !done {
        match e.default_value {
          Some(v) => cf_path = Some(value_str(v)) // committed stays false (default path)
          None => ()
        }
      }
    }
  }
  // Phase 2: read the provider. committed path + None = Error; default path + None = silent.
  let config_obj : ConfigVal? = match cf_path {
    Some(p) => provider(p)
    None => None
  }
  match cf_path {
    Some(p) =>
      if cf_committed {
        match config_obj {
          None =>
            return Err(
              ladder_err(
                cf_element,
                at_pos,
                "config_read_failed",
                "config file \"\{p}\" could not be read",
                path,
              ),
            )
          Some(_) => ()
        }
      }
    None => ()
  }
  // Phase 3: resolve every non config_file entity down the full ladder.
  let out : Array[Binding] = []
  for e in sc.entities {
    if !e.is_config_file {
      let cpath = match e.config_key {
        Some(k) => k // explicit absolute path
        None => { // 同型: scope path + name
          let p : Array[String] = []
          for s in path {
            p.push(s)
          }
          p.push(e.name)
          p
        }
      }
      match
        resolve_entity(
          e, cli, env_map, config_obj, cpath, inherited, at_pos, path,
        ) {
        Ok(bs) =>
          for b in bs {
            out.push(b)
          }
        Err(pe) => return Err(pe)
      }
    }
  }
  Ok(out)
}

///|
/// Fetch a subcommand's built Scope from a parent Scope by name. Subcommands are
/// materialized as greedy `CmdSat(name, child)` entries.
pub fn command_child(sc : Scope, name : String) -> Scope? {
  for g in sc.greedy {
    match g {
      CmdSat(n, child) => if n == name { return Some(child) }
      _ => ()
    }
  }
  None
}

///|
/// Build an inherited-context map from a parent scope's resolved bindings.
pub fn inherited_of(binds : Array[Binding]) -> Map[String, Value] {
  let m : Map[String, Value] = Map([])
  for b in binds {
    m.set(b.key, b.value)
  }
  m
}
