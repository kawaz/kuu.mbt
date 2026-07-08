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
  k == "[]" || k == "{}" || k == "" || is_action_key(k) || is_depr_key(k)
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
    out.push({
      key: new_key,
      op: b.op,
      value: b.value,
      source: b.source,
      scope: new_scope,
      link: b.link,
    })
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
  // UNIFORM ARRAY (DR-044 §1): an accumulate cell declared at THIS path that fired 0 times still
  // renders `[]` (not absent) — inject empties for cells not already present as named leaves.
  for c in cells {
    if path_eq(c.path, path) && !str_contains(named, c.name) {
      obj.push((c.name, RArr([])))
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
/// to a nested structure maps every object-array keyed by `path` while a `filters` scalar array
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
      out.push({ path, name: e.name })
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
/// to parse into the entity's type — the same category as a bad CLI token, DR-053).
fn ladder_err(
  element : String,
  at_pos : Int,
  reason : String,
  message : String,
) -> ParseError {
  { element, argv_pos: at_pos, kind: KParse, reason, message }
}

///|
/// The DR-066 reason for a `parse_int_value` failure.
fn int_fail_reason(f : ParseFail) -> String {
  match f {
    NotANumber => "not_a_number"
    NotAnInteger => "not_an_integer"
  }
}

///|
/// The human-readable (message field is never conformance-compared, DR-066 §4) phrase for a
/// `parse_int_value` failure.
fn int_fail_phrase(f : ParseFail) -> String {
  match f {
    NotANumber => "a number"
    NotAnInteger => "an integer"
  }
}

///|
/// Parse an env string into a Value per the entity's type (DR-049 §2: env goes through the same
/// pipeline as CLI). Unlike slice's `env_value` (naive `parse_number` with a silent `VStr` fallback
/// on failure), this reuses the canonical lexers (DR-074/075) and surfaces a parse failure as a
/// DR-066 Error — a badly-typed env value is never silently coerced to a wrong-typed string cell.
fn env_value(
  element : String,
  ty : Ty,
  s : String,
  at_pos : Int,
) -> Result[Value, ParseError] {
  match ty {
    TStr => Ok(VStr(s))
    TNum =>
      match parse_number(s) {
        Some(d) => Ok(VNum(d))
        None =>
          Err(
            ladder_err(
              element,
              at_pos,
              "not_a_number",
              "env value \"\{s}\" is not a number",
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
/// The DR-066 reason for a `config_to_value` (value.mbt, unchanged) rejection, derived from the
/// (cv, ty) pair IT rejected — not by string-matching its message (value.mbt predates DR-066 and
/// returns a plain String; re-deriving from the typed inputs stays exact instead of sniffing text).
/// The two value-parser reasons (`not_a_number` / `not_an_integer`) are DR-066 v1 vocab; the
/// remaining config-specific mismatches (structural / bool↔number 意味の飛躍) have no v1 reason yet
/// so they carry a resolve-local extension name (DR-066 §3: the v1 vocab is an explicitly open set).
fn config_mismatch_reason(cv : ConfigVal, ty : Ty) -> String {
  match (cv, ty) {
    (CStr(_), TNum) => "not_a_number"
    (CStr(_), TFloat) => "not_a_number"
    (CStr(s), TInt) =>
      match parse_int_value(s, RError) {
        Err(NotAnInteger) => "not_an_integer"
        _ => "not_a_number"
      }
    (CStr(_), TFlag) => "not_a_bool"
    (CStr(_), TBool) => "not_a_bool"
    (CArr(_), _) => "config_structural_mismatch"
    (CObj(_), _) => "config_structural_mismatch"
    _ => "config_type_mismatch" // CNum/CBool 意味の飛躍 (bool↔number); CNull is 供給なし (defensive)
  }
}

///|
/// Resolve one entity down the fixed ladder: cli > env > config > inherit > default (DR-031 /
/// DR-050 #3). Returns the effect bindings (0/1, or many when a config array fills a `multiple`
/// cell) or an Err (a value-source type mismatch is a DR-037/DR-066 Error). `config_obj` is the
/// read config object (None = no config); `config_path` is this entity's absolute lookup path
/// (同型 or config_key). `at_pos` is the position an Error is reported at (see `ladder_err`).
fn resolve_entity(
  e : Entity,
  cli : Array[Binding],
  env_map : Map[String, String],
  config_obj : ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, Value],
  at_pos : Int,
) -> Result[Array[Binding], ParseError] {
  // cli seat — the LAST effect (last-wins, DR-015); set/default/empty commit, unset falls through.
  let mut seat : Binding? = None
  for b in cli {
    if b.key == e.name {
      seat = Some(b)
    }
  }
  match seat {
    Some(b) =>
      match b.op {
        Set => return Ok([b])
        Default =>
          match e.default_value {
            Some(v) => return Ok([mkb(e.name, v, Default)])
            None => return Ok([b])
          }
        Empty => return Ok([b])
        Unset => () // NOT committed: fall through
      }
    None => ()
  }
  // env seat (DR-049)
  match e.env_key {
    Some(k) =>
      match env_map.get(k) {
        Some(v) =>
          match env_value(e.name, e.ty, v, at_pos) {
            Ok(parsed) => return Ok([mkb(e.name, parsed, Env)])
            Err(pe) => return Err(pe)
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
              // array → a multiple cell's pieces (DR-050 §4); each item typed per §4.
              CArr(items) =>
                if e.accum is Some(_) {
                  let bs : Array[Binding] = []
                  for it in items {
                    match config_to_value(it, e.ty) {
                      Ok(v) => bs.push(mkb(e.name, v, Config))
                      Err(_) =>
                        return Err(
                          ladder_err(
                            e.name,
                            at_pos,
                            config_mismatch_reason(it, e.ty),
                            "config array element for \"\{e.name}\" has the wrong type",
                          ),
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
                    ),
                  )
                }
              _ =>
                match config_to_value(cv, e.ty) {
                  Ok(v) => return Ok([mkb(e.name, v, Config)])
                  Err(_) =>
                    return Err(
                      ladder_err(
                        e.name,
                        at_pos,
                        config_mismatch_reason(cv, e.ty),
                        "config value for \"\{e.name}\" has the wrong type",
                      ),
                    ) // §4 型不一致 → DR-037/DR-066 Error
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
pub fn resolve_scope(
  sc : Scope,
  cli : Array[Binding],
  env_map : Map[String, String],
  inherited? : Map[String, Value] = Map([]),
  at_pos? : Int = -1,
) -> Result[Array[Binding], ParseError] {
  let out : Array[Binding] = []
  for e in sc.entities {
    match resolve_entity(e, cli, env_map, None, [], inherited, at_pos) {
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
        resolve_entity(e, cli, env_map, config_obj, cpath, inherited, at_pos) {
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
