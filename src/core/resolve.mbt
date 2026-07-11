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
/// DR-091 §2: split a `kv_map` piece at its FIRST `=` (the value may itself contain further `=`
/// chars — `KEY=a=b` splits to `("KEY", "a=b")`, not `("KEY", "a")`). Every piece reaching this
/// function is already guaranteed to contain `=` (`KvArg`'s consume-time gate, `eval.mbt`'s
/// `contains_eq`) — a piece with no `=` never becomes a Binding in the first place (Held Error at
/// consume time), so this function has no "no `=` found" case to handle.
fn split_first_eq(s : String) -> (String, String) {
  let mut key = ""
  let mut value = ""
  let mut seen_eq = false
  for c in s {
    if seen_eq {
      value = value + c.to_string()
    } else if c == '=' {
      seen_eq = true
    } else {
      key = key + c.to_string()
    }
  }
  (key, value)
}

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
/// DR-084 §2 (issue multiple-ref-accum-gap): split a "#fire"-marked binding list into per-FIRING
/// chunks — the firing-boundary-PRESERVING sibling of `row_groups`' firing-boundary-DISCARDING cut
/// (`row_groups` keeps only the bindings after the LAST "#fire", `last-wins-repeat-rows.json`'s
/// last-wins-whole-cell contract; this keeps EVERY firing as its own chunk, for a ref+repeat
/// element that is ALSO `multiple` — `build_result`'s `segs` loop calls this only when both
/// conditions hold, `inst_long`'s `Scoped(e.name, Bind("#fire", ...))` marker is unconditional so
/// the grammar itself doesn't need to change per DR-084 §2, only its consumer here). Each returned
/// chunk still carries its own "#row" sentinels untouched — the caller re-runs `row_groups` (which
/// sees no "#fire" inside a single chunk, so its "keep from last #fire" cutoff is a no-op) on each
/// chunk to get that firing's own row list.
fn fire_groups(binds : Array[Binding]) -> Array[Array[Binding]] {
  let groups : Array[Array[Binding]] = []
  for b in binds {
    if b.scope.length() == 0 && b.key == "#fire" {
      groups.push([])
    } else if groups.length() > 0 {
      groups[groups.length() - 1].push(b)
    }
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
  // DR-009 段 7 post_filters (Entity.cell_filters's copy, issue accum-post-filters-stage7): an
  // accum cell's cell_filters is Acc→Acc (the WHOLE accumulated array, `filters.mbt`'s
  // `ArrayFilterDescriptor` registry — DIFFERENT signature from a scalar cell's cell_filters,
  // which `apply_entity_filters` already applies per-value T→T and never reaches build_result at
  // all). Applied BEFORE `collector` (DR-083 §2's literal order "accumulator 畳み → cell_filters"
  // has no collector step in it; the collector/post_filters interaction — issue's "未裁定の論点1"
  // — stays open for whenever a fixture actually exercises both on the same cell).
  cell_filters : Array[FilterSpelling]
  // DR-084 §2 (issue multiple-ref-accum-gap): the accumulator KIND (Entity.accum's copy — always
  // `Some(_)` for a cell that reaches `accum_cells` at all, so this is a plain `String` here, not
  // `String?`). `build_result`'s `segs` loop needs to tell apart a ref+repeat cell's "flatten"
  // (non-`multiple`, last-wins-WHOLE-CELL discard — `last-wins-repeat-rows.json`, "#fire" is a
  // CUTOFF) from "append" (`multiple`, firing-boundary-PRESERVING — `ref-repeat-rows-nested.json`,
  // "#fire" is a GROUPING boundary instead) — both shapes emit the SAME "#fire"/"#row" sentinels
  // (`inst_long`'s repeat-bearing ref branch doesn't itself change per DR-084 §2), so only the
  // accumulator kind distinguishes which interpretation applies.
  accum : String
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
/// The DR-009 段 7 cell_filters chain declared for the accum cell at `path`/`name` (mirrors
/// `collector_here`, same lookup shape). `[]` (no chain) is indistinguishable from "cell not
/// found" here — both callers already gate on `cell_here` first, same as `collector_here`.
fn cell_filters_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> Array[FilterSpelling] {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return c.cell_filters
    }
  }
  []
}

///|
/// The accumulator KIND declared for the accum cell at `path`/`name` (mirrors `collector_here`,
/// same lookup shape) — DR-084 §2's `build_result` needs to tell "flatten" (ref+repeat WITHOUT
/// `multiple`, last-wins-WHOLE-CELL discard) apart from any other kind (`multiple`'s "append" etc,
/// firing-boundary-PRESERVING), see `AccumCell.accum`'s doc comment.
fn accum_kind_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> String? {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return Some(c.accum)
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
  nones? : Array[NoneCell] = [],
) -> RVal {
  // ARRAY: a "[]" sentinel at this level => build one element per "#k" child. Elements keep the
  // array's path (an indexed repeat element is not a named result-scope segment cells key on).
  if has_direct_key(binds, "[]") {
    let elems : Array[RVal] = []
    for idx in ordered_indices(binds) {
      elems.push(
        build_result(sub_under(binds, idx), cells, defaults, path, nones~),
      )
    }
    return RArr(elems)
  }
  // ROW-GROUP (DR-078 §1 ref テンプレ result 写像, issue 2026-07-09-ref-template-result-shape):
  // a "#row" sentinel at this level (installer.mbt's `ref_row_head`) marks one repetition's row
  // boundary for a ref-template repeat cell — build one row (recursive build_result over that
  // row's own flat leaf bindings) per "#row"-delimited run。"#fire" (installer.mbt's `inst_long`,
  // option repeat only) marks the start of ONE firing's contribution; multiple 無しの再発火は
  // セル丸ごと上書きなので (DR-034 の axis 分離、last-wins-repeat-rows.json), only the bindings
  // AFTER THE LAST "#fire" survive — with no "#fire" at all (a positional fires its repeat
  // exactly once) the whole list is one firing.
  if has_direct_key(binds, "#row") {
    let rows : Array[RVal] = []
    for row in row_groups(binds) {
      rows.push(build_result(row, cells, defaults, path, nones~))
    }
    return RArr(rows)
  }
  // gather direct named keys (skip sentinels) and nested (named) scopes
  // DR-089 §3: a none-typed cell's value never appears in the result (値の結果には現れない) — same
  // exclusion mechanism as sentinel keys, keyed on (path, name) since `NoneCell` carries the same
  // per-scope shape `AccumCell`/`DefaultCell` do.
  let named : Array[String] = []
  for b in binds {
    if b.scope.length() == 0 &&
      !is_sentinel(b.key) &&
      !str_contains(named, b.key) {
      let mut excluded = false
      for nc in nones {
        if path_eq(nc.path, path) && nc.name == b.key {
          excluded = true
        }
      }
      if !excluded {
        named.push(b.key)
      }
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
      let mut vals : Array[Value] = []
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          match b.op {
            Empty | Unset | Default => vals = []
            _ => vals.push(b.value)
          }
        }
      }
      // DR-009 段 7 cell_filters (issue accum-post-filters-stage7): Acc→Acc self-map over the
      // WHOLE folded array, BEFORE the collector (DR-083 §2's order — see AccumCell.cell_filters'
      // doc comment for why collector comes after, not before).
      let filtered_vals = match cell_filters_here(cells, path, k) {
        [] => vals
        chain => apply_cell_filter_chain(chain, vals)
      }
      let collected = if accum_kind_here(cells, path, k) == Some("kv_map") {
        // DR-091 §2: a kv_map cell folds to an OBJECT, not the uniform array every other
        // accumulator kind produces — each piece is guaranteed `k=v`-shaped (`KvArg`'s consume-time
        // gate, no piece without `=` ever reaches here as a Binding). Re-firing the same key is
        // last-wins (DR-015's あと勝ち — same rule as scalar cell mutation) while the key's
        // POSITION stays at its first occurrence (`Object.fromEntries` convention: a later
        // assignment updates the value in place, it does not move the key to the end). No
        // `collector` application here (DR-036's `collector` vocab — `unwrap_single` etc. — targets
        // an ARRAY shape; kv_map's minimal implementation, team-lead 裁定 2026-07-11, does not wire
        // collector/kv_map interaction, no fixture requires it yet).
        let pairs : Array[(String, RVal)] = []
        let seen : Map[String, Int] = Map([])
        for v in filtered_vals {
          let raw = match v {
            VStr(s) => s
            _ => "" // unreachable: KvArg only ever binds VStr (eval.mbt's KvArg arm)
          }
          let (key, value) = split_first_eq(raw)
          match seen.get(key) {
            Some(i) => pairs[i] = (key, RScalar(VStr(value)))
            None => {
              seen.set(key, pairs.length())
              pairs.push((key, RScalar(VStr(value))))
            }
          }
        }
        RObj(pairs)
      } else {
        let items : Array[RVal] = []
        for v in filtered_vals {
          items.push(RScalar(v))
        }
        let arr = RArr(items)
        match collector_here(cells, path, k) {
          Some(cn) => apply_collector(cn, arr)
          None => arr
        }
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
    let seg_binds = sub_under(binds, seg)
    let is_accum = cell_here(cells, path, seg)
    let unfired_ref_accum_seg = is_accum && !has_direct_key(seg_binds, "#row")
    // DR-084 §2 (issue multiple-ref-accum-gap): a ref+repeat element that is ALSO `multiple`
    // fires "#fire" per firing (`inst_long`'s repeat-bearing ref branch — unconditional, a
    // non-`multiple` ref+repeat cell emits the SAME "#fire"/"#row" sentinels) AND "#row" per rep
    // within each firing (`ref_row_head`) — the two-level nesting `row_groups` alone can't express
    // (it only ever returns ONE flat row list, either "everything since the last #fire" or, with
    // none present, "everything"). `fire_groups` splits by "#fire" first; `row_groups` on each
    // resulting chunk then sees no "#fire" of its own (a no-op cutoff) and returns that firing's
    // own rows — giving the DR-084 §2 shape directly: an outer element per firing (`T[]`), never
    // flattened, "two-fires-preserve-firing-boundary" fixture's contract.
    //
    // The accumulator KIND (not just `is_accum`) is what gates this — `last-wins-repeat-rows.json`
    // (non-`multiple` ref+repeat) IS an accum cell too (`ensure_entity`'s "flatten" fallback for a
    // repeat-only element), and its "#fire" is the ORIGINAL discard-earlier-firings cutoff
    // (`row_groups`'s own contract) — only a `multiple` cell's "append"/other accumulator (never
    // "flatten") wants the firing-PRESERVING read.
    let seg_is_multiple_ref = is_accum &&
      accum_kind_here(cells, path, seg) != Some("flatten")
    if seg_is_multiple_ref &&
      has_direct_key(seg_binds, "#fire") &&
      has_direct_key(seg_binds, "#row") {
      let per_fire : Array[RVal] = []
      for chunk in fire_groups(seg_binds) {
        let rows : Array[RVal] = []
        for row in row_groups(chunk) {
          rows.push(
            build_result(row, cells, defaults, path_push(path, seg), nones~),
          )
        }
        per_fire.push(RArr(rows))
      }
      obj.push((seg, RArr(per_fire)))
    } else if !unfired_ref_accum_seg {
      obj.push(
        (
          seg,
          build_result(
            sub_under(binds, seg),
            cells,
            defaults,
            path_push(path, seg),
            nones~,
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
///
/// `ek` (DR-052 §1 result-key axis) is applied here — issue accum-export-key-rename-asymmetry:
/// this used to omit `ek` entirely and return raw entity names / scope-label paths, while its
/// sibling `default_cells` (via `apply_export_to_defaults`) and the winning `binds` (via
/// `apply_export_keys`) both already resolve through `ek` before reaching `build_result`. Since
/// `build_result`'s `cell_here` match compares an AccumCell's `(path, name)` against the ALREADY-
/// mapped binding keys, an unmapped AccumCell for a renamed accum entity silently failed to
/// match — the accumulate fold never fired (the entity's bindings fell through to plain last-wins
/// scalar rendering under its OLD name instead of `[]`-folding under the renamed key). Same 3-way
/// resolution `apply_export_to_defaults` uses: `EkKey(s)` → rename to `s`, `EkNull` → drop (透過,
/// DR-052 §2 — an accum cell whose OWN key is nulled carries no result-key axis, same posture a
/// scalar default's EkNull already gets), otherwise unchanged.
pub fn accum_cells(sc : Scope, ek : Map[String, ExportKey]) -> Array[AccumCell] {
  let out : Array[AccumCell] = []
  collect_accum(sc, [], ek, out)
  out
}

///|
fn collect_accum(
  sc : Scope,
  path : Array[String],
  ek : Map[String, ExportKey],
  out : Array[AccumCell],
) -> Unit {
  for e in sc.entities {
    // any named accumulator (flatten / append / …) folds the cell into a list (DR-036).
    match e.accum {
      Some(a) =>
        match ek.get(e.name) {
          Some(EkNull) => () // 透過: this accum cell's own result-key axis is dropped
          _ => {
            let new_name = match ek.get(e.name) {
              Some(EkKey(s)) => s
              _ => e.name
            }
            out.push({
              path,
              name: new_name,
              collector: e.collector,
              cell_filters: e.cell_filters,
              accum: a,
            })
          }
        }
      None => ()
    }
  }
  for g in sc.greedy {
    match g {
      CmdSat(name, child) =>
        match ek.get(name) {
          Some(EkNull) => collect_accum(child, path, ek, out) // dropped label → children promote (DR-052 §2)
          Some(EkKey(s)) => collect_accum(child, path_push(path, s), ek, out)
          _ => collect_accum(child, path_push(path, name), ek, out)
        }
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
/// DR-083 §1: `Entity.default_values` is the uniform length-1-degenerate array (node.mbt's doc
/// comment) — every SCALAR-cell reader (a cell with `accum is None`, guaranteed length exactly 1
/// by `ensure_entity`'s only producer) wants just the one value. `resolve_ladder_below_cli`'s
/// default seat is the ONE reader that legitimately iterates the whole array (an accum cell's
/// default can carry N pieces) and does NOT use this helper.
fn default_scalar(e : Entity) -> Value? {
  match e.default_values {
    Some(vs) => if vs.length() > 0 { Some(vs[0]) } else { None }
    None => None
  }
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
      match default_scalar(e) {
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
/// DR-089 §3: a none-typed cell's committed marker (`is_committed`/committed 基準の制約は通常どおり
/// 参加する) still rides the same `Array[Binding]` channel `build_result` renders from — there is
/// no separate ParserContext-shaped channel wired up in this layer yet. `NoneCell` names the
/// (path, name) pairs `build_result` must exclude from `named` so a none cell's presence never
/// surfaces in the result object (§3「値の結果には現れない」), mirroring `AccumCell`/`DefaultCell`'s
/// own per-scope shape.
pub(all) struct NoneCell {
  path : Array[String]
  name : String
} derive(Eq, Debug)

///|
pub fn none_cells(sc : Scope) -> Array[NoneCell] {
  let out : Array[NoneCell] = []
  collect_nones(sc, [], out)
  out
}

///|
/// DR-093 §2/§7 波及: dd 要素 (`DdSat`/`DdMatchSat`) は entity を持たない (DR-030「実体=値セル」/
/// LOWERING §B.4、`ensure_entities` の `not_dd` ガード) が、DR-093 の committed 観測用 binding は
/// 他の none 型セルと同じ `binds` 配列に乗る (`flag_bare_true_variant` 同型 placeholder)。entity
/// 走査だけでは dd 要素を `NoneCell` として拾えないので、greedy 面も合わせて見る (`Or`/`Rooted` の
/// 中に置かれた dd も同じ scope の一員として拾う — `outcome.mbt`/`json_conformance_wbtest.mbt` の
/// dd 探索ヘルパーと同型の再帰形)。
fn collect_dd_names(g : Node, out : Array[String]) -> Unit {
  match g {
    DdSat(trigger) => out.push(trigger)
    DdMatchSat(_, _, _, elem_name) => out.push(elem_name)
    Or(alts) =>
      for a in alts {
        collect_dd_names(a, out)
      }
    Rooted(inner, _) => collect_dd_names(inner, out)
    _ => ()
  }
}

///|
fn collect_nones(
  sc : Scope,
  path : Array[String],
  out : Array[NoneCell],
) -> Unit {
  for e in sc.entities {
    if e.ty == TNone {
      out.push({ path, name: e.name })
    }
  }
  let dd_names : Array[String] = []
  for g in sc.greedy {
    collect_dd_names(g, dd_names)
  }
  for name in dd_names {
    out.push({ path, name })
  }
  for g in sc.greedy {
    match g {
      CmdSat(name, child) => collect_nones(child, path_push(path, name), out)
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
/// The result-key axis (DR-052 §1) resolved to its ACTUAL exposed key string for `raw` (an entity
/// name / binding key), or `None` when the axis carries no key at all (EkNull, DR-052 §2 透過).
/// Mirrors `apply_export_keys`'s own resolution exactly (same 3-way match, same `_` fallback to
/// `raw` for EkUnset AND for an unmapped name — sentinels `"[]"`/`"{}"`/`""`/`"@act:"`/`"@depr:"`
/// and `"#k"` index segments are never in `ek`, `apply_export_keys`'s doc comment) — this is the
/// SAME "未指定 → name 由来のキーで露出" resolution DR-052 §1's table specifies, just queried
/// instead of applied. issue export-key-collision-identity-exposure-gap: `find_export_collisions`
/// used to skip this `_` (EkUnset / unmapped) case entirely, treating "no `ek` entry" as "not
/// exposed" — but DR-052 §1 says EkUnset resolves to a REAL exposed key (the name), so an identity-
/// exposed element competing with another element's `EkKey`-mapped key for the same result-scope
/// key was invisible to collision detection. Spec precedent (DESIGN §15.5: "衝突の本質は結果キーの
/// provenance の曖昧さ") talks about "同じ export_key へ解決する" — export_key's own value-domain
/// (DR-052 §1) already includes "未指定 → name 由来のキー" as a resolved value, not a separate
/// "no key" state, so this is the axis's existing resolution reused for detection, not a new
/// collision-detection policy.
fn exposed_key_of(raw : String, ek : Map[String, ExportKey]) -> String? {
  match ek.get(raw) {
    Some(EkNull) => None
    Some(EkKey(s)) => Some(s)
    _ => Some(raw)
  }
}

///|
/// Detect every export-key collision in `binds` (DESIGN §15.5, DR-021 → DR-052 → DR-073). Runtime
/// check on the actual co-exposure of a parse, not a static declaration scan (§15.6 stays warn-only
/// at definition time). `binds` are PRE-export-key bindings (raw entity names in `key`); grouping
/// compares the raw `scope` path directly (two bindings at the identical remaining nesting are
/// candidates regardless of depth — no per-level recursion needed, mirroring the original
/// `find_export_collision`'s flat O(n²) scan). Groups by `exposed_key_of` (mapped OR identity-
/// exposed, EkNull excluded) — see that function's doc comment for why identity exposure is now
/// included (issue export-key-collision-identity-exposure-gap).
pub fn find_export_collisions(
  binds : Array[Binding],
  ek : Map[String, ExportKey],
) -> Array[ExportCollision] {
  // (path, exposed key) → claimants, built incrementally; a linear scan over few groups is fine at
  // this scale (definitions have small option counts).
  let groups : Array[ExportCollision] = []
  for b in binds {
    match exposed_key_of(b.key, ek) {
      Some(key) => {
        let mut found = false
        for g in groups {
          if path_eq(g.path, b.scope) && g.key == key {
            if !str_contains(g.claimants, b.key) {
              g.claimants.push(b.key)
            }
            found = true
            break
          }
        }
        if !found {
          groups.push({ path: b.scope, key, claimants: [b.key] })
        }
      }
      None => ()
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
  nones? : Array[NoneCell] = [],
) -> Array[Interpretation] {
  let collisions = find_export_collisions(binds, ek)
  if collisions.length() == 0 {
    let mapped = apply_export_keys(binds, ek)
    return [
      {
        result: build_result(mapped, cells, defaults, [], nones~),
        claimants: [],
      },
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
          exposed_key_of(b.key, ek) == Some(c.key) &&
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
    out.push({
      result: build_result(mapped, cells, defaults, [], nones~),
      claimants,
    })
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

// ── DR-047 §4/§5 (issue value-present-ladder-gap 裁定 2026-07-10、bool target 分は元 issue
// bool-requires-config-inherit-gap 裁定 2026-07-09): requires の後段 path filter ───────────────
//
// requires (CRequires) / value 依存 requires (CRequiresIf) の目的語の充足条件は「値源ラダー
// (env/config/inherit/default) 充填後の最終状態」で決まる — bool 型 (TFlag/TBool) なら「解決後の
// 値が true であること」(値源不問)、非 bool なら「値の有無 (default 込み)」(DR-047 §5 表)。この
// 判定は値源ラダーが解ける後段でしか行えないため、KTop (eval.mbt, CLI 面のみで完結する完全経路
// 判定) では両方とも常に pass 扱いとしてスキップし (`is_bool_entity` が bool/非bool の分岐ゲート)、
// ここで `parse()` の Outcome を受け取って事後フィルタとして適用する — `promote_collision_ambiguous`
// (DR-073, 直上) と同じ「Outcome を受け取り Outcome を返す後処理」パターン。
//
// 非bool 分は元々 `value_present` (= committed OR has_default) として KTop で即時評価していたが、
// これは env/config/inherit 経由の供給を無視する実装ショートカットだった (DR-047 §4 の「値源ラダー
// 充填後の最終状態で評価する」規定と乖離、issue value-present-ladder-gap で発見・実機再現)。

///|
/// `name` (entities 内で探した Entity) が bool 型 (TFlag/TBool) かどうか — DR-047 §5 の bool/非bool
/// 目的語判定ゲート。この後段フィルタが bool 判定式 (真理値) と非bool 判定式 (値の有無) のどちらを
/// 使うかを分ける。
pub fn is_bool_entity(entities : Array[Entity], name : String) -> Bool {
  for e in entities {
    if e.name == name {
      return e.ty == TFlag || e.ty == TBool
    }
  }
  false
}

///|
/// `name` (entities 内で探した Entity) が値空間なし型 (`TNone`、dd 含む) かどうか — DR-093 §1/§2 の
/// 型委譲ゲート。値空間なし要素の充足 (required 自身 / requires 目的語) は committed で判定し、
/// 値空間あり要素は最終状態の値の有無で判定する (`is_bool_entity` と対になる、同じ形のゲート)。
/// 見つからない場合は `true` (= 値空間なし扱い) — `is_bool_entity` (見つからなければ `false`) と
/// 非対称に見えるが、dd 要素は DR-030「実体=値セル」/ LOWERING §B.4「dd は値を生まない」により
/// `ensure_entities` が最初から entity を作らない (`not_dd` ガード)。値空間の有無は entity の有無と
/// 一致するので、「entity が無い」は「値空間なし」の別表現であり、この既定側が正しい。
pub fn is_none_entity(entities : Array[Entity], name : String) -> Bool {
  for e in entities {
    if e.name == name {
      return e.ty == TNone
    }
  }
  true
}

///|
/// One scope's `requires`/value 依存 requires violations, evaluated against a CANDIDATE path's
/// CLI-only bindings (trigger 判定、DR-047 §5 表「トリガ側 = committed」) AND the SAME candidate's
/// fully resolved bindings (目的語判定、「目的語側 = 値の有無/真理値」) — issue
/// resolve-first-constraint-pipeline (Phase 1) 裁定 2026-07-10: 目的語の充足判定は、もはやこの関数が
/// 自前のラダー (env/config/inherit) を再演するのではなく、呼び出し元が既に `resolve_scope_tree` で
/// 解決済みの `resolved` を渡してくるので `elem_value` の単純参照で済む (値源不問は「resolve 済み
/// なら値源を意識する必要がない」という形で自然に成立する)。issue value-present-ladder-gap 裁定
/// 2026-07-10 でこの読者化を非bool 目的語にも拡張した — bool は `elem_value(resolved,...) ==
/// Some("true")`、非bool は `elem_value(resolved,...) != None` (値の有無) の 2 分岐。
///
/// `constraint_err`'s `path` defaults to `[]` (KTop's contract: a Held rides the cont chain and
/// scope boundaries prepend the path on the way out) — that mechanism doesn't run here (the path
/// is already fully resolved), so `sc.path` (DR-066 §4 result-nesting path) is threaded in
/// directly via struct-update.
fn eval_requires(
  sc : ScopedCons,
  bindings : Array[Binding],
  resolved : Array[Binding],
  pos : Int,
) -> Array[ParseError] {
  let out : Array[ParseError] = []
  let path = sc.path
  // DR-093 §1/§3: 目的語の充足判定は型 (値空間) への委譲 — 値空間なし (none) は発火 (committed)、
  // bool は解決後値が true、それ以外 (通常の値空間あり型) は値の有無。none 分岐が先 (bool/非bool の
  // 判定は値空間があることが前提で、none には値そのものが無い)。
  let satisfied = fn(t : String) -> Bool {
    if is_none_entity(sc.entities, t) {
      is_committed(bindings, path, t)
    } else if is_bool_entity(sc.entities, t) {
      elem_value(resolved, path, t) == Some("true")
    } else {
      elem_value(resolved, path, t) != None
    }
  }
  for c in sc.constraints {
    match c {
      CRequires(elem, targets) =>
        if is_committed(bindings, path, elem) {
          for t in targets {
            if !satisfied(t) {
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
            if !satisfied(t) {
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
      CRequired(elem) => {
        // DR-093 §1/§2: 自身の充足は型委譲。値空間なし (none) = 発火 (committed)、値空間あり =
        // 最終状態の値の有無 (default 込み、DR-047 §5 不変)。`satisfied` (上記 requires 目的語用) は
        // 再利用しない — bool の「解決後値 true」ルールは requires 目的語限定 (DR-047 §5 明確化) で
        // あり、required 自身の充足には持ち込まない (DESIGN §9.1 に bool 特例なし、bool は preset
        // default:false を常に持つため required 自身は「値の有無」で自明に充足する、それが spec の
        // 意図どおり)。
        let ok = if is_none_entity(sc.entities, elem) {
          is_committed(bindings, path, elem)
        } else {
          elem_value(resolved, path, elem) != None
        }
        if !ok {
          out.push({
            ..constraint_err(
              elem,
              "required_violated",
              "required '\{elem}' is missing",
              pos,
            ),
            path,
          })
        }
      }
    }
  }
  out
}

///|
/// Whether ANY binding in `binds` was recorded at exactly this scope path — "this nested command
/// scope was actually entered in this candidate". Ported from `json_conformance_wbtest.mbt`'s
/// `scope_entered` (production code can't reference a wbtest-only symbol; wbtest files aren't
/// linked into non-test builds) for `resolve_scope_tree`'s own use.
fn scope_entered_here(binds : Array[Binding], path : Array[String]) -> Bool {
  for b in binds {
    if path_eq(b.scope, path) {
      return true
    }
  }
  false
}

///|
/// Resolve a WHOLE scope tree (root scope + every entered nested command scope) down the full
/// value-source ladder (`resolve_scope_config`), threading `inherited` top-down so a child scope's
/// inherit seat always sees its ANCESTOR's already-resolved values (DR-087 §3 dependency order —
/// the parent must be fully resolved before the child's inherit lookup runs, never reversed).
///
/// This is the production promotion of `json_conformance_wbtest.mbt`'s `resolve_tree` (issue
/// resolve-first-constraint-pipeline, Phase 1): same recursive shape, generalized from the test
/// harness's `DCase`-specific `NoCfg`/`CfgObj`/`CfgFiles` dispatch to a plain `provider` closure
/// (`resolve_scope_config`'s own contract), so production callers — not just the conformance
/// harness — can resolve a whole tree, not just one scope. `apply_requires_filter` below is
/// the first such caller; `json_conformance_wbtest.mbt`'s own `resolve_tree` is expected to become
/// a thin `dc.cfg`-to-`provider` adapter over this function (not duplicated here).
///
/// `binds` is the CLI-only raw bindings for ONE candidate path (`parse()`'s `Success`/`AmbInterp`
/// payload) — not yet split by scope; this function filters to `path`'s own direct bindings at
/// each recursion level. The returned `Array[Binding]` is flat with every binding's `scope` tagged
/// to its owning path (the same shape `build_result`/`proj_sources_tree` already consume) — a
/// caller wanting a value at a nested path uses the ordinary `elem_value`/`is_committed` lookups
/// with that path, no different from a single-scope `resolve_scope_config` caller.
pub fn resolve_scope_tree(
  sc : Scope,
  binds : Array[Binding],
  env_map : Map[String, String],
  provider : (String) -> ConfigVal?,
  path? : Array[String] = [],
  inherited? : Map[String, Value] = Map([]),
  at_pos? : Int = -1,
) -> Result[Array[Binding], ParseError] {
  let here : Array[Binding] = []
  for b in binds {
    if path_eq(b.scope, path) {
      here.push(b)
    }
  }
  let resolved = match
    resolve_scope_config(
      sc,
      here,
      env_map,
      provider,
      path~,
      inherited~,
      at_pos~,
    ) {
    Ok(rb) => rb
    Err(pe) => return Err(pe)
  }
  let out : Array[Binding] = []
  for b in here {
    if is_sentinel(b.key) {
      out.push(b)
    }
  }
  for b in resolved {
    out.push({ ..b, scope: path })
  }
  let child_inherited : Map[String, Value] = Map([])
  for k, v in inherited {
    child_inherited.set(k, v)
  }
  for b in resolved {
    child_inherited.set(b.key, b.value)
  }
  for g in sc.greedy {
    match g {
      CmdSat(name, child) => {
        let childpath = path_push(path, name)
        if scope_entered_here(binds, childpath) {
          match
            resolve_scope_tree(
              child,
              binds,
              env_map,
              provider,
              path=childpath,
              inherited=child_inherited,
              at_pos~,
            ) {
            Ok(cb) =>
              for b in cb {
                out.push(b)
              }
            Err(pe) => return Err(pe)
          }
        }
      }
      _ => ()
    }
  }
  Ok(out)
}

///|
/// Apply the DR-047 §4/§5 requires path filter to a `parse()` Outcome (cell_filters と同じ側の
/// 後段処理、`promote_collision_ambiguous` と同型パターン — `parse()` 自体のシグネチャ・eval 層の
/// Ctx は無改修のまま、値源 (env/config/inherit) を後から与える)。bool 目的語 (真理値判定) と非bool
/// 目的語 (値の有無判定) の両方をここで扱う (issue value-present-ladder-gap 裁定 2026-07-10 で対象
/// 拡張、旧名 `apply_requires_filter` から改名)。生存経路数で outcome を再構成する: 0 →
/// `Failure` (violation を DR-053 §2 全保持で errors に、`fired_action`/`help_entry`/
/// `tried_triggers` は既存 KTop 発 Failure と同じ素材関数から構築 — 区別が付かない形にする、
/// DR-048 の「候補経路は dead end を含む」通り違反で落ちた経路の action も候補に数える)、1 → その
/// 経路で `Success`、2+ → 生存分だけの `Ambiguous`。`root`/`defs` は制約テーブル (`collect_scopes`)
/// と `find_help_entry`/`tried_triggers_of` の素材取得に使う。
///
/// issue resolve-first-constraint-pipeline (Phase 1、audit issue lazy-default-resolution-audit の
/// finding への根治): 候補ごとに `resolve_scope_tree` で実際に解決してから `elem_value` を読むだけの
/// 「読者」に再設計した (以前の `resolved_bool_value_ladder` 自前ミニラダー + `config_obj:
/// ConfigVal?` 単一オブジェクト契約 + `collect_all_scopes` 祖先探索テーブルは全廃)。
/// `provider~` は `resolve_scope_config` と同じ `(String) -> ConfigVal?` 契約 — スコープごとに
/// 異なる config_file を動的に指す CfgFiles ケースも、呼び出し元が対応する provider を渡すだけで
/// 均一に扱われる (単一 ConfigVal だった旧契約の既知の残存ギャップが解消)。省略時は常に `None` を
/// 返す no-op provider (config 未使用の既存呼び出し元は無改修)。
///
/// `table.length() == 0` (このスコープ木に requires 制約が一つも無い) なら resolve を試みずに
/// 即座に `[]` を返す — 制約が無い定義で resolve コストを払わない、かつ無関係な entity の env/config
/// 解決エラーを不要に持ち込まない (両立できる速い経路)。
pub fn apply_requires_filter(
  o : Outcome,
  root : Node,
  defs : Map[String, Node],
  env : Map[String, String],
  toks_len : Int,
  provider? : (String) -> ConfigVal? = fn(_) { None },
) -> Outcome {
  let table = collect_scopes(root, defs)
  let violations_of = fn(binds : Array[Binding]) -> Array[ParseError] {
    if table.length() == 0 {
      return []
    }
    match root {
      ScopeNode(sc) =>
        match resolve_scope_tree(sc, binds, env, provider, at_pos=toks_len) {
          Ok(resolved) => {
            let out : Array[ParseError] = []
            for sc2 in table {
              for v in eval_requires(sc2, binds, resolved, toks_len) {
                out.push(v)
              }
            }
            out
          }
          // A resolve-layer failure (e.g. a badly-typed env value on some OTHER entity in the
          // same scope tree) makes this candidate non-viable, same conceptual bucket as a
          // constraint violation (DR-047 §2/§3: 述語失敗は Error, 経路の成立条件) — it is folded
          // into this candidate's violations rather than aborting the whole filter.
          Err(pe) => [pe]
        }
      _ => []
    }
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
      help_entry: find_help_entry(root, errors),
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
  piece_filters : Array[FilterSpelling],
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
    // DR-089: none has no value space, so an env seat on a none-typed entity is a structural
    // mismatch (same family as `config_to_value`'s TNone arms in value.mbt — no defined DR-089
    // seat semantics, consistent error treatment across the value-source ladder's runtime-input
    // parsers).
    TNone =>
      Err(
        ladder_err(
          element, at_pos, "config_type_mismatch", "env value for a none element (no value space)",
          epath,
        ),
      )
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
  // DR-080 波及節: a merge-accumulator cell's CLI seat is NOT a per-binding fold — a "発火" is a
  // GROUP of same-`at_pos` Set/Remove/Splice pieces (one argv token's separator-split), evaluated
  // together against the DR-080 §3 rule (old composition, remove/splice, implicit leading `@`).
  // That grouping cannot be expressed inside this function's per-binding `match b.op` loop (which
  // append/flatten's accumulators are correctly built around, one binding = one independent
  // effect) — factored into its own function.
  if e.accum is Some("merge") {
    return resolve_merge_accum(
      e, cli, env_map, config_obj, config_path, inherited, at_pos, epath,
    )
  }
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
          Remove | Splice =>
            // DR-080 §2: `sep_binds` only ever emits a `Remove`/`Splice` piece for an entity whose
            // `accumulator` is `"merge"` (the `merge` flag gate on `classify_merge_piece`) — this
            // branch is append/flatten's fold, reached only when `e.accum` is NOT `Some("merge")`
            // (the `if` above already returned for that case). Unreachable in practice.
            abort(
              "unreachable: a Remove/Splice piece only fires for a merge-accumulator entity (DR-080 §1) — this is the non-merge (append/flatten) accum fold",
            )
          Default =>
            // DR-081 §2: accum セルでも op=default は「その時点の (書き換え済み) default 値」を
            // set する — 宣言 default が無ければ DR-051 §2 一様形 `[]` のまま (env/config 供給も
            // 無ければ `resolve_ladder_below_cli` は `Ok([])` を返すので、何も push しない = 累積
            // 列が空のまま = `[]`)、供給があればその配列 (複数 piece もそのまま) が書き換え済み
            // default になる。build_result の ACCUMULATE match は `b.op` だけを見て
            // `Default => items = []` とクリアするので、この Default 効果 binding 自身 (`b`) は
            // そのままクリア点として残し、書き換え済み default の各要素は別の `Set` binding として
            // 追加する (2 段構成: クリア点 1 個 + 書き換え済み default の要素 N 個、N=0 なら `[]`
            // のまま)。`source` は両方 `Cli` に統一 (DR-081 §2 の確定主体読み — `proj_sources` は
            // 累積列内 SAME KEY の最後の binding の source/op を見るので、途中の要素が env 由来の
            // 値であっても Set 側の source を Cli に上書きしないと sources=env に誤読される)。
            match
              resolve_ladder_below_cli(
                e, env_map, config_obj, config_path, inherited, at_pos, epath,
              ) {
              Ok(bs2) => {
                bs.push({ ..b, source: Cli })
                for nb in bs2 {
                  bs.push({ ..nb, op: Set, source: Cli })
                }
                committed_now = true
              }
              Err(pe) => return Err(pe)
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
            // DR-081 §2: op=default sets the CURRENT (already-rewritten) default value — env/
            // config/inherit don't "win as a lower seat" here, they've already rewritten the
            // cell's default (§1's model) by the time this fires, so querying the SAME ladder
            // `resolve_ladder_below_cli` runs for a normal fall-through gets exactly that value.
            // `source` is ALWAYS `Cli` now (DR-081 §2 "確定させた主体"重視 — the default's own
            // provenance, even if it's env, doesn't change WHO committed it) — this is the one
            // behavior change from the pre-DR-081 code, which tagged `source: Default` here.
            match
              resolve_ladder_below_cli(
                e, env_map, config_obj, config_path, inherited, at_pos, epath,
              ) {
              Ok(bs2) => {
                current = if bs2.length() > 0 {
                  Some(mkb(e.name, bs2[bs2.length() - 1].value, Cli))
                } else {
                  // no declared default AND no env/config/inherit supply — nothing to rewrite to,
                  // same degenerate fallback the pre-DR-081 code used (the placeholder binding
                  // itself, committed as-is; this element simply has no meaningful default here).
                  Some(b)
                }
                committed_now = true
              }
              Err(pe) => return Err(pe)
            }
          Empty => {
            current = Some(b)
            committed_now = true
          }
          // NOT committed: resets the running value to default so a LATER update in the same
          // fold sees the right "old" — but this seat stays eligible to fall through to
          // env/config/inherit if nothing commits after it (unchanged pre-DR-077 contract).
          Unset => {
            current = match default_scalar(e) {
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
                match default_scalar(e) {
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
          Remove | Splice =>
            // DR-080 §2: a `Remove`/`Splice` piece only ever fires for a `multiple` element whose
            // `accumulator` is `"merge"` — a merge accumulator REQUIRES `multiple` (DR-080 §1), so
            // no scalar (non-multiple) entity's CLI seat can ever carry one. Unreachable in
            // practice; `abort` matches the sibling accum branch's own defensive arm.
            abort(
              "unreachable: a Remove/Splice piece only fires for a multiple(merge) entity (DR-080 §1) — this is the scalar (non-multiple) fold",
            )
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
  resolve_ladder_below_cli(
    e, env_map, config_obj, config_path, inherited, at_pos, epath,
  )
}

///|
/// DR-081 §1 の「default 席書き換え」モデルの実装的正体: env/config/inherit/宣言 default という
/// CLI 未満のラダー段。CLI seat がフォールスルーした場合の通常経路であると同時に、`resolve_entity_
/// raw` の CLI seat 内で `Default` effect (`:default` variant) が発火した瞬間の **「その時点の
/// (書き換え済み) default 値」を問い合わせる関数としても再利用する** (DR-081 §2 "op=default は
/// 現在の default をそのままセルへ書く")。CLI seat の外に切り出したのは、両方の呼び手が全く同じ
/// 「env が勝てば env、なければ config、なければ inherit、なければ宣言 default (無ければ accum は
/// `[]` / scalar は absent)」という 1 本のラダーを必要とするため — 重複実装すると DR-081 が
/// 「複数席が供給する場合は従来のラダー優先順」と明記する優先順位 (env が最終的に勝つ) を 2 箇所で
/// 保守する羽目になる。
///
/// 返り値は素の `resolve_entity_raw` の戻り値と同型 (Array[Binding], 0 件 = absent 相当 / 1 件以上)。
/// `Default` effect の呼び手はこれをそのまま bindings として使う (scalar は高々 1 件、accum は
/// env/config の複数 piece もそのまま乗る — DR-081 §2 の accum 節 "書き換え済み default があれば
/// それ" が要求する挙動そのもの)。
fn resolve_ladder_below_cli(
  e : Entity,
  env_map : Map[String, String],
  config_obj : ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, Value],
  at_pos : Int,
  epath : Array[String],
) -> Result[Array[Binding], ParseError] {
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
  // default seat (DR-083 §1/§2): a scalar cell wants just the one value (`default_scalar`); an
  // accum cell's declared default supplies its WHOLE array as already-split pieces, config-array
  // precedent (DR-050 §4) — each piece routed through `config_to_value` (via `value_to_configval`)
  // for the same T-domain / string-pipeline parse the CArr config branch above uses, so declared-
  // default pieces and config-array pieces share one type-parse code path.
  if e.accum is Some(_) {
    match e.default_values {
      Some(vs) => {
        let bs : Array[Binding] = []
        for v in vs {
          match config_to_value(value_to_configval(v), e.ty, e.piece_filters) {
            Ok(vv) => bs.push(mkb(e.name, vv, Default))
            Err((KFilter, reason, msg)) =>
              return Err(filter_err(e.name, at_pos, reason, msg, epath))
            Err((_, reason, msg)) =>
              return Err(ladder_err(e.name, at_pos, reason, msg, epath))
          }
        }
        Ok(bs)
      }
      None => Ok([])
    }
  } else {
    match default_scalar(e) {
      Some(v) => Ok([mkb(e.name, v, Default)])
      None => Ok([])
    }
  }
}

///|
/// A merge accumulator's CLI-seat unit of work (DR-080 波及節「1 発火 = 同一 argv 位置の piece
/// 列」): either one cell-level op (`default`/`unset`/`empty`, 0-token `EffMark` bindings, `at_pos`
/// always `None`) or a run of `Set`/`Remove`/`Splice` PIECE bindings sharing the SAME `at_pos`
/// (`sep_binds`'s split of one separator token). `resolve_merge_accum` groups the CLI seat into
/// this shape before applying DR-080 §3's evaluation rule.
priv enum MergeGroup {
  GCell(Binding)
  GFire(Array[Binding])
}

///|
/// DR-080 の merge accumulator 専用 CLI 席折込み。append/flatten (`resolve_entity_raw`'s own accum
/// loop) は「1 binding = 1 独立効果」の fold で済むが、merge は「同じ at_pos の Set/Remove/Splice
/// piece 列 = 1 発火」という粒度で DR-080 §3 の規則 (old 合成、remove/splice、暗黙先頭 `@`) を適用
/// する必要があり、その fold には収まらない — 独立関数として切り出した。
///
/// 各グループの処理は前段の結果を **完全に置き換える** (累積しない): DR-080 §3 冒頭「マーカーを
/// 1 つも含まない発火 = cell 上書き」("second-no-marker-fire-overwrites-again" fixture — 2 回目の
/// マーカーなし発火は 1 回目の 5 要素を消して単独の結果になる、append 累積とは異なる) — append の
/// ような「毎発火の効果を保存して build_result に畳ませる」contract ではなく、merge 自身が「現在の
/// 確定状態」を都度再計算し、その時点の状態だけを返り値 (`build_result` が解釈する素の binding 列)
/// として持つ。次の発火の "old" は別途 `old_values` で運ぶ (返り値の binding 列そのものからは
/// 再構成しない — `Default`/`Empty` の 2 段構成 binding 列から values を逆算するのは重複ロジックに
/// なる)。
fn resolve_merge_accum(
  e : Entity,
  cli : Array[Binding],
  env_map : Map[String, String],
  config_obj : ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, Value],
  at_pos : Int,
  epath : Array[String],
) -> Result[Array[Binding], ParseError] {
  // グループ化: 同名 binding のうち、Set/Remove/Splice は「連続する同一 at_pos」の連なりを 1 発火
  // (GFire) として束ね、Update/Default/Unset/Empty は単独グループ (GCell) とする。
  let groups : Array[MergeGroup] = []
  let mut fire_buf : Array[Binding] = []
  let mut fire_pos : Int? = None
  for b in cli {
    if b.key == e.name {
      match b.op {
        Set | Remove | Splice => {
          if fire_buf.length() > 0 && fire_pos != b.at_pos {
            groups.push(GFire(fire_buf))
            fire_buf = []
          }
          fire_pos = b.at_pos
          fire_buf.push(b)
        }
        Update(_, _) | Default | Unset | Empty => {
          if fire_buf.length() > 0 {
            groups.push(GFire(fire_buf))
            fire_buf = []
            fire_pos = None
          }
          groups.push(GCell(b))
        }
      }
    }
  }
  if fire_buf.length() > 0 {
    groups.push(GFire(fire_buf))
  }
  let mut result_bs : Array[Binding] = []
  let mut committed_now = false
  let mut old_values : Array[Value]? = None
  for g in groups {
    match g {
      GCell(b) =>
        match b.op {
          Update(_, _) =>
            // team-lead 裁定 2026-07-10: accum×update は静的 definition-error (installer.mbt の
            // collect_unsupported_accum_update) — merge accumulator も `multiple` の一種なので
            // 同じ gate に掛かる。この arm に実際に来ることはない。
            abort(
              "unreachable: an accum (multiple) entity's `update` variant is rejected at definition time (installer.mbt's collect_unsupported_accum_update) — resolve_merge_accum should never see one",
            )
          Default =>
            // DR-081 §2 の accum 節と同じ二段構成 (クリア点 1 個 + 書き換え済み default の要素
            // N 個)。old_values はこの発火の結果 (書き換え済み default の値列) に更新する —
            // 後続の merge 発火があれば、それが「その時点の old」になる (DR-080 §3 の old はセル
            // 現在値、default 発火直後ならその値)。
            match
              resolve_ladder_below_cli(
                e, env_map, config_obj, config_path, inherited, at_pos, epath,
              ) {
              Ok(bs2) => {
                let nb : Array[Binding] = [{ ..b, source: Cli }]
                let vals : Array[Value] = []
                for x in bs2 {
                  nb.push({ ..x, op: Set, source: Cli })
                  vals.push(x.value)
                }
                result_bs = nb
                old_values = Some(vals)
                committed_now = true
              }
              Err(pe) => return Err(pe)
            }
          Unset => {
            // DR-045: uncommitted — the ladder re-opens. A LATER merge firing in this same CLI
            // seat must re-query it fresh (mirrors "初回発火" — `old_values = None` signals that).
            result_bs = [b]
            old_values = None
            committed_now = false
          }
          Empty => {
            result_bs = [b]
            old_values = Some([])
            committed_now = true
          }
          Set | Remove | Splice =>
            abort(
              "unreachable: GCell only ever holds Update/Default/Unset/Empty (the grouping loop routes Set/Remove/Splice into GFire)",
            )
        }
      GFire(pieces) => {
        let marks : Array[MergeMark] = []
        for p in pieces {
          match p.op {
            Set => marks.push(MAdd(p.value))
            Remove => marks.push(MRemove(p.value))
            Splice => marks.push(MSplice)
            _ =>
              abort(
                "unreachable: a GFire piece is always Set/Remove/Splice (the grouping loop's own invariant)",
              )
          }
        }
        if merge_pieces_has_no_marker(marks) {
          // DR-080 §3 冒頭: マーカーを1つも含まない発火 = cell 上書き。`pieces` は既に
          // Set/Cli/at_pos 形 (`sep_binds` が組んだ通り) なので、そのまま採用する — old は
          // 一切参照しない。
          let vals : Array[Value] = []
          for p in pieces {
            vals.push(p.value)
          }
          result_bs = pieces
          old_values = Some(vals)
          committed_now = true
        } else {
          // DR-080 §3: old = セルの現在値 (直前発火の結果)、初回発火なら値源ラダーの下位席の勝者。
          let old = match old_values {
            Some(vs) => vs
            None =>
              match
                resolve_ladder_below_cli(
                  e, env_map, config_obj, config_path, inherited, at_pos, epath,
                ) {
                Ok(bs2) => {
                  let vs : Array[Value] = []
                  for x in bs2 {
                    vs.push(x.value)
                  }
                  vs
                }
                Err(pe) => return Err(pe)
              }
          }
          let result_vals = eval_merge_pieces(
            merge_pieces_with_implicit_splice(marks),
            old,
          )
          let nb : Array[Binding] = []
          for v in result_vals {
            nb.push(mkb(e.name, v, Cli))
          }
          result_bs = nb
          old_values = Some(result_vals)
          committed_now = true
        }
      }
    }
  }
  if committed_now {
    return Ok(result_bs)
  }
  resolve_ladder_below_cli(
    e, env_map, config_obj, config_path, inherited, at_pos, epath,
  )
}

///|
/// Resolve every entity in a built scope against CLI bindings + an env map (no config seat). For
/// the env / inherit ladder path. Unlike slice (whose config-less path "never errors"), a
/// badly-typed env value now surfaces as an Err (DR-074/075 update above).
/// `path` is this scope's DR-066 §4 result-nesting path (root-first, [] = root 直下), threaded into
/// any ladder-fill Error the same way `resolve_scope_config`'s `path` is.
///
/// A scope MAY still declare a `config_file` element even on this no-config-object call path (a
/// caller can choose not to supply config data for a particular case/run — issue
/// bool-requires-config-inherit-gap の diverge 調査で顕在化: 元のドキュメント想定「no config_file
/// element in scope」は呼び出し元の都合を entity 宣言の事実と混同していた)。`resolve_scope_config`
/// の Phase 3 (`if !e.is_config_file`) と同じ規則 — config_file 要素は配線宣言であって結果 entity
/// ではない — をここでも守る。守らないと、config データを供給しない呼び出しのときだけ config_file
/// 要素の宣言 default が漏れて result に出現する非対称が起きる (config_seat を持つ通常 entity は
/// config_obj=None のときの通常 default フォールスルーで正しく処理されるので対象外、config_file
/// 自身だけがこの skip を必要とする)。
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
    if !e.is_config_file {
      match resolve_entity(e, cli, env_map, None, [], inherited, at_pos, path) {
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
        match default_scalar(e) {
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

// ── DR-080: merge accumulator — piece マーカー語彙と old 合成 ──────────────────

///|
/// DR-080 §2 のマーカー判定結果 (1 piece 分)。マーカー認識は piece 全体一致・separator 分割直後・
/// 型 parse 前 (DR-080 波及節) — この enum はその判定が終わった後の形で、`MRemove`/`MAdd` の
/// payload は既に型 parse 済みの `Value` (remove の operand も要素 type で parse される、DR-080 §2)。
/// `MSplice` (`@`) は operand を持たない (old をその位置に展開するだけ)。
pub(all) enum MergeMark {
  MAdd(Value)
  MRemove(Value)
  MSplice
} derive(Eq, Debug)

///|
/// DR-080 §3 の評価規則 (左→右の一回走査)。呼び出し側の責務: (a) 「マーカーを 1 つも含まない発火」
/// の判定 (この関数はマーカーが渡された前提で動く — マーカーなし発火は「cell 上書き」であり、この
/// 合成規則を経由しない、DR-080 §3 冒頭)。(b) 明示 `@` が無い場合の暗黙先頭 `@` 補完 (DR-080 §3
/// 「明示 `@` が無ければ先頭に暗黙の `@` が補われる」) — `pieces` はこの補完が既に済んだ列を渡す。
///
/// アルゴリズム (DR-080 §4 の 14 例全てで検証済み、kuu.mbt issue の逆算):
/// - `seen_removes`: これまでに出現した remove の operand 集合 (発火全体を通じて蓄積、削除も
///   splice フィルタも兼ねる)
/// - `MAdd(v)`: work_list の末尾に追加 (それ以前/以後の remove からは影響を受けない自分自身の
///   追加だが、後続の remove がこの要素を削除しうる — 削除は「その時点までの work_list 全体」に
///   効くため)
/// - `MRemove(v)`: `seen_removes` に `v` を追加した後、work_list 全体 (その時点までに構築された
///   もの) から `v` と等しい要素を全削除 (DR-080 §3 (a) 後置 remove)
/// - `MSplice`: `old` から「その時点で `seen_removes` に含まれる」要素を除いたコピーを work_list
///   の末尾に連結 (DR-080 §3 (b) 前置 remove — old 展開時点の `seen_removes` を使うので、remove が
///   splice より後にあっても、splice の時点でまだ出現していなければ及ばない。ただし同じ発火内で
///   remove が先行していれば当然反映される)
pub fn eval_merge_pieces(
  pieces : Array[MergeMark],
  old : Array[Value],
) -> Array[Value] {
  let work_list : Array[Value] = []
  let seen_removes : Array[Value] = []
  for p in pieces {
    match p {
      MAdd(v) => work_list.push(v)
      MRemove(v) => {
        if !array_contains_value(seen_removes, v) {
          seen_removes.push(v)
        }
        let kept : Array[Value] = []
        for x in work_list {
          if x != v {
            kept.push(x)
          }
        }
        work_list.clear()
        for x in kept {
          work_list.push(x)
        }
      }
      MSplice =>
        for x in old {
          if !array_contains_value(seen_removes, x) {
            work_list.push(x)
          }
        }
    }
  }
  work_list
}

///|
fn array_contains_value(arr : Array[Value], v : Value) -> Bool {
  for x in arr {
    if x == v {
      return true
    }
  }
  false
}

///|
/// `pieces` が 1 つも `MRemove`/`MSplice` を含まないか (= DR-080 §3 冒頭「マーカーを 1 つも含まない
/// 発火」の判定)。全て `MAdd` なら true。
pub fn merge_pieces_has_no_marker(pieces : Array[MergeMark]) -> Bool {
  for p in pieces {
    match p {
      MAdd(_) => ()
      _ => return false
    }
  }
  true
}

///|
/// DR-080 §3 「明示 `@` が無ければ先頭に暗黙の `@` が補われる」。`pieces` にマーカーが含まれる
/// (merge モード) 前提で呼ぶ — マーカーなし発火 (cell 上書き) には適用しない。
pub fn merge_pieces_with_implicit_splice(
  pieces : Array[MergeMark],
) -> Array[MergeMark] {
  let mut has_explicit_splice = false
  for p in pieces {
    match p {
      MSplice => has_explicit_splice = true
      _ => ()
    }
  }
  if has_explicit_splice {
    pieces
  } else {
    let out : Array[MergeMark] = [MSplice]
    for p in pieces {
      out.push(p)
    }
    out
  }
}

///|
/// DR-080 §2 の piece 全体一致マーカー判定結果 (型 parse 前 — operand はまだ生の文字列)。
/// `PkRemove`/`PkAdd` の文字列は `piece_filters` → 型 parse を通す payload (DR-080 波及節)、
/// `PkSplice` は operand を持たない。
pub(all) enum PieceMark {
  PkAdd(String)
  PkRemove(String)
  PkSplice
} derive(Eq, Debug)

///|
/// DR-080 §2 のマーカー語彙判定 (piece 全体一致のみ、separator 分割直後・型 parse 前):
/// - `"@"` (完全一致) → splice
/// - 先頭が `-` → remove、operand は残り (空文字列も含む — `-` 単独は remove(""))
/// - 先頭が `+` かつ 2 文字目が `-`/`@`/`+` → escape、先頭の `+` を 1 個剥がした literal (add)
/// - 上記以外 → add (通常値、`+` 単独や `+x` (x が `-`/`@`/`+` 以外) もここに落ちる = literal)
///
/// 部分一致はマーカーにならない (`a@b` は `@` を含むが先頭一致ではないので add)。
pub fn classify_merge_piece(s : String) -> PieceMark {
  if s == "@" {
    return PkSplice
  }
  let cs = to_chars(s)
  if cs.length() > 0 && cs[0] == '-' {
    return PkRemove(chars_to_str_from(cs, 1))
  }
  if cs.length() >= 2 &&
    cs[0] == '+' &&
    (cs[1] == '-' || cs[1] == '@' || cs[1] == '+') {
    return PkAdd(chars_to_str_from(cs, 1))
  }
  PkAdd(s)
}
