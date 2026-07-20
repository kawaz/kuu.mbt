// resolve.mbt — the value-resolution layer (MDR-002 §3): the value-source ladder (env / config /
// inherit / default seat fill, DR-031 / DR-049 / DR-050), the name-driven result builder (flat
// bindings → nested @engine.RVal, DR-016 / DR-025 / DR-043), export-key application (DR-052), and
// export-key collision detection (DR-073). node/value 依存のみ; eval からは経路確定後の後処理
// として呼ばれる (MDR-002 §3 table).
//
// Ported from slice `poc/result.mbt` (full file) and the value-ladder portion of slice
// `poc/installer.mbt` (`resolve_scope` / `resolve_scope_config` / `@engine.value_str` — NOT the lowering,
// which stays installer.mbt's job). MDR-003: `e.inherit` → `e.inherit_` (node.mbt already applies
// the trailing-underscore convention).
//
// `@engine.value_str` used to live in eval.mbt for the CRequiresIf constraint comparison — this is its
// canonical home per the MDR-002 §3 module table; eval.mbt now calls this file's copy (single
// package, no import needed across files).
//
// DR-074/075 update over the slice: env's string→@engine.Value conversion goes through the canonical
// lexers (`@builtins.parse_number` / `parse_int_value` / `parse_bool`, value.mbt) instead of slice's
// `env_value` which silently fell back to `@engine.VStr(s)` on a parse failure — a badly-typed env value
// is now a DR-066 Error (reason `not_a_number` / `not_an_integer` / `not_a_bool`), never a
// wrong-typed cell. `resolve_scope` / `resolve_scope_config` return `Result[.., @engine.ParseError]`
// accordingly (slice's config-less `resolve_scope` could not error; it now can, from a bad env
// value).

// ── result value + builder (slice `poc/result.mbt`) ──────────────────────────────────────────

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
/// Whether `k` is a sentinel key that binds-level projections should skip. Covers the presence
/// markers (`[]` / `{}` / empty), the accumulate row separators (`#row` / `#fire`, DR-078), the
/// failure-action markers (`@act:...`, DR-048), and the deprecation-warning markers (`@depr:...`,
/// DR-058). 下流 (kuu-cli など) は本判定を直接使わず `output()` (OutputView) を通す — 内部
/// marker の除外は front_door の射影が担う。
fn is_sentinel(k : String) -> Bool {
  k == "[]" ||
  k == "{}" ||
  k == "" ||
  k == "#row" ||
  k == "#fire" ||
  (k.length() >= 5 && k[0:5].to_owned() == "@act:") ||
  (k.length() >= 6 && k[0:6].to_owned() == "@depr:")
}

///|
/// `resolve_scope_tree` が path 単位でしか sentinel を保存しない (each path=[] の here 抽出は
/// `path_eq(b.scope, path)` に限定) 制約を補うための merge。**accum entity scope**
/// (`@engine.Scoped(name, ...)` node、command でない = `resolve_scope_tree` の再帰対象外) 下の
/// sentinel (`#row`/`#fire`、`installer.mbt` の `ref_row_head` / `inst_long` が発火時に付与) は
/// `resolve_scope_tree` からは「path として枚挙されない」ため resolve 結果から落ちる — この
/// 落ちた sentinel を元の CLI 生 binds から拾って resolve 済み binds に merge する。同一
/// (key, scope) の sentinel が既に resolve 済み binds に居るなら skip (path=[] scope=[] の
/// sentinel は `resolve_scope_tree` が既に保存しているため、二重を避ける)。
///
/// 経緯 (issue 2026-07-16 K カテゴリ = front-door-repeat-rows-collapse): kuu-cli 経由の
/// `fixtures/multiple-parse/ref-rows-append.json::single-fire-list` が `result.hlcolors=[]`
/// (期待 `[{colorname:"red"}]`) に退化していた実バグ。原因は `resolve_scope_tree` が accum
/// entity scope 下の `#row` sentinel を落として `build_result` の ROW-GROUP 分岐 (`has_direct_
/// key(binds, "#row")`) が発火しなくなること。**resolve 相の意味論**: 値源ラダーを充填する
/// (値を最終化する) が、parse 相が付与した構造情報 (どこで累積境界を切るか) は保存する — sentinel
/// は「構造」に属し値ではないため。
///
/// 呼び出し規約: `front_door.resolve()` が `resolve_scope_tree` の直後にこれを 1 度だけ呼ぶ形
/// (再帰の中では呼ばない、二重防止)。resolve_scope_tree 自身を書き換える案は再帰と top-level の
/// 区別が必要でコストが大きい割に、呼び出し元 (`apply_requires_filter` は結果 binds を捨てる、
/// runner は use_resolve gate で経路分岐する) 全体で見ると front_door の 1 段で足りる。
fn merge_sentinels_from_origin(
  orig : Array[@engine.Binding],
  resolved : Array[@engine.Binding],
) -> Array[@engine.Binding] {
  let out : Array[@engine.Binding] = []
  for b in resolved {
    out.push(b)
  }
  for b in orig {
    if !is_sentinel(b.key) {
      continue
    }
    let mut dup = false
    for r in resolved {
      if is_sentinel(r.key) && r.key == b.key && path_eq(r.scope, b.scope) {
        dup = true
        break
      }
    }
    if !dup {
      out.push(b)
    }
  }
  out
}

///|
fn has_direct_key(binds : Array[@engine.Binding], key : String) -> Bool {
  for b in binds {
    if b.scope.length() == 0 && b.key == key {
      return true
    }
  }
  false
}

///|
/// The bindings under a scope segment `seg`, with the first path element dropped.
fn sub_under(
  binds : Array[@engine.Binding],
  seg : String,
) -> Array[@engine.Binding] {
  let out : Array[@engine.Binding] = []
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
fn row_groups(binds : Array[@engine.Binding]) -> Array[Array[@engine.Binding]] {
  let mut from = 0
  let mut i = 0
  for b in binds {
    if b.scope.length() == 0 && b.key == "#fire" {
      from = i + 1
    }
    i = i + 1
  }
  let groups : Array[Array[@engine.Binding]] = []
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
/// conditions hold, `inst_long`'s `@engine.Scoped(e.name, @engine.Bind("#fire", ...))` marker is unconditional so
/// the grammar itself doesn't need to change per DR-084 §2, only its consumer here). Each returned
/// chunk still carries its own "#row" sentinels untouched — the caller re-runs `row_groups` (which
/// sees no "#fire" inside a single chunk, so its "keep from last #fire" cutoff is a no-op) on each
/// chunk to get that firing's own row list.
fn fire_groups(binds : Array[@engine.Binding]) -> Array[Array[@engine.Binding]] {
  let groups : Array[Array[@engine.Binding]] = []
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
fn ordered_indices(binds : Array[@engine.Binding]) -> Array[String] {
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
///   - a value cell's key: @engine.EkKey(s) → s (override); @engine.EkNull → "" (nameless: kv 文脈で消え、seq/array
///     文脈では値が nameless 要素として残る); @engine.EkUnset → the name (unchanged).
///   - a scope label (command / name scope): @engine.EkKey(s) → s; @engine.EkNull → DROP the label (子が昇格露出);
///     @engine.EkUnset → unchanged. A "{}" presence marker whose only label was dropped floats to the root
///     scope where it is a harmless sentinel (a nameless command has no key — 子が昇格).
/// Sentinels ("[]" / "{}" / "" / "@act:" / "@depr:") and index segments ("#k") are not in the map
/// → kept.
fn apply_export_keys(
  binds : Array[@engine.Binding],
  ek : Map[String, @engine.ExportKey],
) -> Array[@engine.Binding] {
  let out : Array[@engine.Binding] = []
  for b in binds {
    let new_scope : Array[String] = []
    for seg in b.scope {
      if seg.length() >= 1 && seg[0:1].to_owned() == "#" {
        new_scope.push(seg) // an array index segment — never a name
      } else {
        match ek.get(seg) {
          Some(@engine.EkNull) => () // drop the label → children promote to the parent (DR-052 §2)
          Some(@engine.EkKey(s)) => new_scope.push(s)
          _ => new_scope.push(seg) // @engine.EkUnset or not a mapped name
        }
      }
    }
    let new_key = match ek.get(b.key) {
      Some(@engine.EkNull) => "" // nameless value axis
      Some(@engine.EkKey(s)) => s
      _ => b.key
    }
    out.push({ ..b, key: new_key, scope: new_scope })
  }
  out
}

///|
/// Apply the result-key axis (DR-052) to the injected default cells, mirroring apply_export_keys on
/// bindings: an @engine.EkNull cell is 透過 (dropped from the kv result), an @engine.EkKey renames it, and path
/// segments (command scope names) are renamed / promoted the same way. Keeps a flag's preset default
/// subject to the same export transform as its fired value (so `--verbose` with export null neither
/// appears as a value nor re-appears as an injected `false`).
fn apply_export_to_defaults(
  defaults : Array[DefaultCell],
  ek : Map[String, @engine.ExportKey],
) -> Array[DefaultCell] {
  let out : Array[DefaultCell] = []
  for d in defaults {
    match ek.get(d.name) {
      Some(@engine.EkNull) => () // 透過: the value has no result key → not injected
      _ => {
        let new_path : Array[String] = []
        for seg in d.path {
          if seg.length() >= 1 && seg[0:1].to_owned() == "#" {
            new_path.push(seg)
          } else {
            match ek.get(seg) {
              Some(@engine.EkNull) => () // dropped scope label → children promote
              Some(@engine.EkKey(s)) => new_path.push(s)
              _ => new_path.push(seg)
            }
          }
        }
        let new_name = match ek.get(d.name) {
          Some(@engine.EkKey(s)) => s
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
priv struct AccumCell {
  path : Array[String]
  name : String
  // DR-036 collector (@engine.Entity.collector's copy, threaded through so build_result — which only
  // sees AccumCell, never the @engine.Scope/@engine.Entity it came from — can apply it to the final accumulated
  // array without a second lookup pass). None = no collector (render the plain array).
  collector : &@engine.CollectorExt?
  // DR-009 段 7 / DR-102 §1 accum_filters (@engine.Entity.accum_filters's copy, issue
  // accum-post-filters-stage7): an accum cell's accum_filters is Acc→Acc (the WHOLE accumulated
  // array, the engine `ArrayFilterDescriptor` registry — DIFFERENT signature from a scalar
  // cell's final_filters, which `apply_entity_filters` already applies per-value T→T and never
  // reaches build_result at all). Applied BEFORE `collector` (DR-083 §2's literal order
  // "accumulator 畳み → accum_filters" has no collector step in it; the collector/accum_filters
  // interaction — issue's "未裁定の論点1" — stays open for whenever a fixture actually exercises
  // both on the same cell).
  accum_filters : Array[@engine.FilterSpelling]
  // DR-084 §2 (issue multiple-ref-accum-gap): the accumulator KIND (@engine.Entity.accum's copy — always
  // `Some(_)` for a cell that reaches `accum_cells` at all, so this is a plain `String` here, not
  // `String?`). Pre-DR-105 this alone told apart a ref+repeat cell's "flatten" (non-`multiple`,
  // last-wins-WHOLE-CELL discard) from "append" (`multiple`, firing-boundary-preserving) — DR-105 §3
  // collapsed both onto the SAME name ("append"), so `is_multiple_decl` below (not this field) is
  // what `build_result`'s `segs` loop now reads for that distinction (both shapes still emit the
  // SAME "#fire"/"#row" sentinels, `inst_long`'s repeat-bearing ref branch is unchanged by DR-105).
  accum : &@engine.AccumulatorExt
  // DR-105 §1 flatten dial (@engine.Entity.flatten's copy): whether an array-shaped fire value expands by
  // one level into the accumulated array (`build_result`'s SEGS-loop per-fire builder, the one
  // reachable consumer — DR-084 §2's ref+repeat+multiple row array).
  flatten : Bool
  // DR-084 §2 origin marker (@engine.Entity.is_multiple_decl's copy): true iff this cell's accumulator seat
  // came from a declared `multiple` (append-preserving-across-firings) as opposed to the repeat
  // installer's own cons-unfold cell (discard-earlier-firings/last-wins-whole-cell). Replaces the
  // pre-DR-105 `accum == "flatten"` test this struct's `accum` doc comment above describes.
  is_multiple_decl : Bool
}

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
) -> &@engine.CollectorExt? {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return c.collector
    }
  }
  None
}

///|
/// The DR-009 段 7 / DR-102 §1 accum_filters chain declared for the accum cell at `path`/`name`
/// (mirrors `collector_here`, same lookup shape). `[]` (no chain) is indistinguishable from "cell
/// not found" here — both callers already gate on `cell_here` first, same as `collector_here`.
fn accum_filters_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> Array[@engine.FilterSpelling] {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return c.accum_filters
    }
  }
  []
}

///|
/// The accumulator resident declared for the cell at `path`/`name`.
fn accumulator_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> &@engine.AccumulatorExt? {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return Some(c.accum)
    }
  }
  None
}

///|
/// The DR-105 §1 flatten dial declared for the accum cell at `path`/`name` (mirrors `collector_here`,
/// same lookup shape) — defaults false when the cell isn't found (same "not found = the inert
/// value" posture `accum_filters_here`'s `[]` default uses, since every real call site here already
/// gates on `cell_here`/`is_accum` first).
fn flatten_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> Bool {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return c.flatten
    }
  }
  false
}

///|
/// The DR-084 §2 origin marker declared for the accum cell at `path`/`name` (mirrors
/// `collector_here`, same lookup shape). It distinguishes a declared `multiple` cell from a
/// repeat-only cell even though both use the append resident. Defaults false when not found.
fn is_multiple_decl_here(
  cells : Array[AccumCell],
  path : Array[String],
  name : String,
) -> Bool {
  for c in cells {
    if c.name == name && path_eq(c.path, path) {
      return c.is_multiple_decl
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
fn build_result(
  binds : Array[@engine.Binding],
  cells : Array[AccumCell],
  defaults : Array[DefaultCell],
  path : Array[String],
  nones? : Array[@engine.NoneCell] = [],
  extensions? : @engine.Registry = canonical_registry(),
) -> @engine.RVal {
  // ARRAY: a "[]" sentinel at this level => build one element per "#k" child. Elements keep the
  // array's path (an indexed repeat element is not a named result-scope segment cells key on).
  if has_direct_key(binds, "[]") {
    let elems : Array[@engine.RVal] = []
    for idx in ordered_indices(binds) {
      elems.push(
        build_result(
          sub_under(binds, idx),
          cells,
          defaults,
          path,
          nones~,
          extensions~,
        ),
      )
    }
    return @engine.RArr(elems)
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
    let rows : Array[@engine.RVal] = []
    for row in row_groups(binds) {
      rows.push(build_result(row, cells, defaults, path, nones~, extensions~))
    }
    return @engine.RArr(rows)
  }
  // gather direct named keys (skip sentinels) and nested (named) scopes
  // DR-089 §3: a none-typed cell's value never appears in the result (値の結果には現れない) — same
  // exclusion mechanism as sentinel keys, keyed on (path, name) since `@engine.NoneCell` carries the same
  // per-scope shape `AccumCell`/`DefaultCell` do.
  let named : Array[String] = []
  for b in binds {
    if b.scope.length() == 0 &&
      !is_sentinel(b.key) &&
      !str_contains(named, b.key) {
      let mut excluded = false
      for nc in nones {
        if path_eq(nc.path(), path) && nc.name() == b.key {
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
    let mut v = @engine.VBool(false)
    for b in binds {
      if b.scope.length() == 0 && b.key == "" {
        v = b.value
      }
    }
    return @engine.RScalar(v)
  }
  // OBJECT: named leaves (folding accum keys into a list) + nested scopes.
  let obj : Array[(String, @engine.RVal)] = []
  for k in named {
    if cell_here(cells, path, k) {
      // ACCUMULATE (repeat-cons and multiple both use "append", DR-105 §3 / DR-043/034/036): fold same-key
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
      // binding's `source` to `@engine.Default` before it reached here, so the tag comes out right without
      // a default-specific branch on the source side). `update` never reaches this match —
      // `installer.mbt`'s `collect_unsupported_accum_update` rejects a `multiple` element's
      // `update` variant at `parse_definition` time (static definition-error, not a runtime fold
      // check), so no @engine.Scope carrying this combination is ever built for `resolve`/`build_result`
      // to see.
      let mut vals : Array[@engine.Value] = []
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          match b.op {
            @engine.Empty | @engine.Unset | @engine.Default => vals = []
            _ => vals.push(b.value)
          }
        }
      }
      // DR-009 段 7 / DR-102 §1 accum_filters (issue accum-post-filters-stage7): Acc→Acc self-map
      // over the WHOLE folded array, BEFORE the collector (DR-083 §2's order — see
      // AccumCell.accum_filters' doc comment for why collector comes after, not before).
      // DR-105 §4: `@engine.apply_accum_filter_chain` returns Result (ARRAY filter registry can
      // reject, e.g. `length_range`) — the REJECT itself is surfaced earlier, at `resolve_entity`
      // time (`apply_entity_filters`'s own accum_filters gate, same `at_pos`/`epath` machinery
      // `final_filters` already uses), so a binding set that reaches `build_result` at all is
      // guaranteed to already satisfy this cell's accum_filters. The `Err` arm here is therefore
      // unreachable in practice — defensive fallback to the pre-filter array, same posture
      // `apply_collector`'s "unrecognized name — identity" fallback uses.
      let filtered_vals = match accum_filters_here(cells, path, k) {
        [] => vals
        chain =>
          match @engine.apply_accum_filter_chain(extensions, chain, vals) {
            Ok(v) => v
            Err(_) => vals
          }
      }
      let accumulated = match accumulator_here(cells, path, k) {
        Some(resident) => resident.collect(filtered_vals)
        None => abort("unreachable: an accumulated cell has no resident")
      }
      let collected = match collector_here(cells, path, k) {
        Some(resident) => resident.collect(accumulated)
        None => accumulated
      }
      obj.push((k, collected))
    } else {
      // SCALAR last-wins (DR-015): the last value written to the cell.
      let mut v = @engine.VBool(false)
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          v = b.value
        }
      }
      obj.push((k, @engine.RScalar(v)))
    }
  }
  for seg in segs {
    // issue 2026-07-09-accum-fold-update-default-ops 追記 (2026-07-10): a ref+repeat option cell
    // registered as an accum entity (`ensure_entity_body`'s BCell arm) that fired 0 times has
    // ONLY its "#fire" marker under `scope=[e.name]` (`inst_long`'s `@engine.Scoped(e.name, @engine.Bind("#fire",
    // ...))`) — no "#row" sentinel (`ref_row_head`) at all, since `@engine.GreedyRepeat` never ran. Its
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
    // The origin marker (not just `is_accum`) is what gates this — `last-wins-repeat-rows.json`
    // (non-`multiple` ref+repeat) IS an accum cell too (`ensure_entity`'s repeat-cons branch — a
    // repeat-only element), and its "#fire" is the ORIGINAL discard-earlier-firings cutoff
    // (`row_groups`'s own contract) — only a genuinely `multiple`-declared cell wants the
    // firing-PRESERVING read. `is_multiple_decl_here` is the independent origin marker that tells
    // a declared multiple cell from a repeat-only cell; accumulator identity and the flatten dial
    // do not encode that distinction.
    let seg_is_multiple_ref = is_accum &&
      is_multiple_decl_here(cells, path, seg)
    if seg_is_multiple_ref &&
      has_direct_key(seg_binds, "#fire") &&
      has_direct_key(seg_binds, "#row") {
      // DR-105 §1 flatten dial: a `multiple`-declared ref+repeat cell's per-firing row array
      // (T[], DR-084 §2) is exactly the "発火値が配列" shape the dial targets — `flatten:true`
      // expands each firing's rows directly into the outer array (T[]) instead of nesting them
      // one level (T[][], the flatten:false/default shape `ref-repeat-rows-nested.json` pins).
      // A 0-row firing contributes 0 elements either way ("空配列 → 0要素"); this is the only
      // reachable manifestation of the dial in kuu.mbt today (`value.mbt`'s `@engine.Value` has no array
      // variant, so a plain scalar multiple cell's fire is never array-shaped — the dial is
      // observationally inert there, DR-105 §1's "非配列 → 丸ごと1要素" holds vacuously).
      let flat = flatten_here(cells, path, seg)
      let per_fire : Array[@engine.RVal] = []
      for chunk in fire_groups(seg_binds) {
        let rows : Array[@engine.RVal] = []
        for row in row_groups(chunk) {
          rows.push(
            build_result(
              row,
              cells,
              defaults,
              path_push(path, seg),
              nones~,
              extensions~,
            ),
          )
        }
        if flat {
          for r in rows {
            per_fire.push(r)
          }
        } else {
          per_fire.push(@engine.RArr(rows))
        }
      }
      obj.push((seg, @engine.RArr(per_fire)))
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
            extensions~,
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
  // for its accum cell, so `accum_cells` sees it too) needs a DIFFERENT double-render
  // guard than plain `!str_contains(named, c.name)` — its bindings never land in `named` at all
  // (`ref_row_head`'s `@engine.Scoped(e.name, ...)` wrap means every binding carries `scope=[e.name, ...]`,
  // never a bare top-level key), so `named` alone can't tell "fired >=1 time, ROW-GROUP already
  // built the real array" apart from "fired 0 times, needs [] injected here". A naive `segs`
  // membership check (± "is this cell's name a nested-scope segment at all") is WRONG in the other
  // direction: `resolve_scope`'s accum branch (this cell's `@engine.Entity.accum` seats no CLI binding, so
  // `resolve_entity` always resolves it to `Ok([])`) drops the raw eval-layer bindings entirely
  // before `build_result` ever runs, so THAT path never even reaches `segs` — but conformance's
  // no-resolve path (`run_case`'s `else` arm, `json_conformance_test.mbt`) feeds build_result the
  // RAW eval bindings, where a 0-rep firing still leaves the `"#fire"` marker
  // (`inst_long`'s `@engine.Scoped(e.name, @engine.Bind("#fire", ...))`) under `scope=[e.name]` — landing THIS in
  // `segs` too, indistinguishable from a real "#row"-bearing firing by name alone. The precise
  // test is whether this cell's OWN nested bindings actually contain a "#row" sentinel (only a
  // real repetition emits one, `ref_row_head`) — check that directly instead of trusting `segs`
  // membership as a proxy for it.
  for c in cells {
    if path_eq(c.path, path) &&
      !str_contains(named, c.name) &&
      !has_direct_key(sub_under(binds, c.name), "#row") {
      let empty = c.accum.collect([])
      let collected = match c.collector {
        Some(resident) => resident.collect(empty)
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
      obj.push((d.name, @engine.RScalar(d.value)))
    }
  }
  @engine.RObj(obj)
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
/// resolution `apply_export_to_defaults` uses: `@engine.EkKey(s)` → rename to `s`, `@engine.EkNull` → drop (透過,
/// DR-052 §2 — an accum cell whose OWN key is nulled carries no result-key axis, same posture a
/// scalar default's @engine.EkNull already gets), otherwise unchanged.
fn accum_cells(
  sc : @engine.Scope,
  ek : Map[String, @engine.ExportKey],
) -> Array[AccumCell] {
  let out : Array[AccumCell] = []
  collect_accum(sc, [], ek, out)
  out
}

///|
fn collect_accum(
  sc : @engine.Scope,
  path : Array[String],
  ek : Map[String, @engine.ExportKey],
  out : Array[AccumCell],
) -> Unit {
  for e in sc.entities {
    // any named accumulator (flatten / append / …) folds the cell into a list (DR-036).
    match e.accum {
      Some(a) =>
        match ek.get(e.name) {
          Some(@engine.EkNull) => () // 透過: this accum cell's own result-key axis is dropped
          _ => {
            let new_name = match ek.get(e.name) {
              Some(@engine.EkKey(s)) => s
              _ => e.name
            }
            out.push({
              path,
              name: new_name,
              collector: e.collector,
              accum_filters: e.accum_filters,
              accum: a,
              flatten: e.flatten,
              is_multiple_decl: e.is_multiple_decl,
            })
          }
        }
      None => ()
    }
  }
  for g in sc.greedy {
    match g {
      @engine.CmdSat(name, child) =>
        match ek.get(name) {
          Some(@engine.EkNull) => collect_accum(child, path, ek, out) // dropped label → children promote (DR-052 §2)
          Some(@engine.EkKey(s)) =>
            collect_accum(child, path_push(path, s), ek, out)
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
priv struct DefaultCell {
  path : Array[String]
  name : String
  value : @engine.Value
}

///|
fn default_cells(sc : @engine.Scope) -> Array[DefaultCell] {
  let out : Array[DefaultCell] = []
  collect_defaults(sc, [], out)
  out
}

///|
/// DR-083 §1: `@engine.Entity.default_values` is the uniform length-1-degenerate array (node.mbt's doc
/// comment) — every SCALAR-cell reader (a cell with `accum is None`, guaranteed length exactly 1
/// by `ensure_entity`'s only producer) wants just the one value. `resolve_ladder_below_cli`'s
/// default seat is the ONE reader that legitimately iterates the whole array (an accum cell's
/// default can carry N pieces) and does NOT use this helper.
fn default_scalar(e : @engine.Entity) -> @engine.Value? {
  match e.default_values {
    Some(vs) => if vs.length() > 0 { Some(vs[0]) } else { None }
    None => None
  }
}

///|
fn collect_defaults(
  sc : @engine.Scope,
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
    if (e.ty.name() == "flag" || e.ty.name() == "bool") && e.accum is None {
      match default_scalar(e) {
        Some(v) => out.push({ path, name: e.name, value: v })
        None => ()
      }
    }
  }
  for g in sc.greedy {
    match g {
      @engine.CmdSat(name, child) =>
        collect_defaults(child, path_push(path, name), out)
      _ => ()
    }
  }
}

///|
/// front_door 昇格 (issue 2026-07-16-result-projection-production-promotion、MDR-005「射程外」節
/// の解消、DR-109 §5 UX-Q5=a): `binds` → `result` オブジェクト (CONFORMANCE.md §2 の
/// `result: {...}`) を組み立てる 4 素材 (`apply_export_keys`/`accum_cells`/
/// `apply_export_to_defaults`/`@engine.none_cells`) の合成をここに一本化する。runner の
/// `proj_result_export` (json_conformance_test.mbt) と kuu-cli PoC の手組み `result_to_json`
/// (wire.mbt) が同一の 5 行組み立てを重複実装していた — 両者ともこの関数を呼ぶ形に揃える。
/// `binds` は `front_door.resolve()` の @engine.Success payload (解決済み binds、DR-109 §7「CLI は既定で
/// resolve 適用」) を渡すのが前提だが、型としては素の `Array[@engine.Binding]` を受けるだけなので未解決の
/// CLI binds を渡しても動く (runner が「default ladder 不要な fixture は resolve をスキップする」
/// 最適化で未解決 binds をそのまま渡す既存経路があり、それを壊さないための性質 — 呼び出し側の
/// 資格を型で強制することはしない)。
fn build_result_export(
  sc : @engine.Scope,
  binds : Array[@engine.Binding],
  ek : Map[String, @engine.ExportKey],
  extensions? : @engine.Registry = canonical_registry(),
) -> @engine.RVal {
  build_result(
    apply_export_keys(binds, ek),
    accum_cells(sc, ek),
    apply_export_to_defaults(default_cells(sc), ek),
    [],
    nones=@engine.none_cells(sc),
    extensions~,
  )
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
priv struct ExportCollision {
  path : Array[String]
  key : String
  claimants : Array[String]
}

///|
/// The result-key axis (DR-052 §1) resolved to its ACTUAL exposed key string for `raw` (an entity
/// name / binding key), or `None` when the axis carries no key at all (@engine.EkNull, DR-052 §2 透過).
/// Mirrors `apply_export_keys`'s own resolution exactly (same 3-way match, same `_` fallback to
/// `raw` for @engine.EkUnset AND for an unmapped name — sentinels `"[]"`/`"{}"`/`""`/`"@act:"`/`"@depr:"`
/// and `"#k"` index segments are never in `ek`, `apply_export_keys`'s doc comment) — this is the
/// SAME "未指定 → name 由来のキーで露出" resolution DR-052 §1's table specifies, just queried
/// instead of applied. issue export-key-collision-identity-exposure-gap: `find_export_collisions`
/// used to skip this `_` (@engine.EkUnset / unmapped) case entirely, treating "no `ek` entry" as "not
/// exposed" — but DR-052 §1 says @engine.EkUnset resolves to a REAL exposed key (the name), so an identity-
/// exposed element competing with another element's `@engine.EkKey`-mapped key for the same result-scope
/// key was invisible to collision detection. Spec precedent (DESIGN §15.5: "衝突の本質は結果キーの
/// provenance の曖昧さ") talks about "同じ export_key へ解決する" — export_key's own value-domain
/// (DR-052 §1) already includes "未指定 → name 由来のキー" as a resolved value, not a separate
/// "no key" state, so this is the axis's existing resolution reused for detection, not a new
/// collision-detection policy.
fn exposed_key_of(raw : String, ek : Map[String, @engine.ExportKey]) -> String? {
  match ek.get(raw) {
    Some(@engine.EkNull) => None
    Some(@engine.EkKey(s)) => Some(s)
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
/// exposed, @engine.EkNull excluded) — see that function's doc comment for why identity exposure is now
/// included (issue export-key-collision-identity-exposure-gap).
fn find_export_collisions(
  binds : Array[@engine.Binding],
  ek : Map[String, @engine.ExportKey],
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
/// Promote a `@engine.Success` outcome to `@engine.Ambiguous` when its bindings carry an export-key co-exposure
/// collision (DR-021 → DR-073). The collision detection runs against the actual parse (§15.5
/// runtime check), so a definition that DECLARES two elements with the same export_key is only
/// promoted when BOTH elements are present in the same result scope. `@engine.Failure` and already-
/// `@engine.Ambiguous` outcomes pass through unchanged (structurally-ambiguous outcomes have no export-key
/// collision by construction — they differ in parse structure, not provenance for a shared key).
/// Each promoted interpretation carries the DR-073 §1 claimants面 (exposed key → occupying entity
/// name) so degenerate views (e.g. two flags both `true`) remain distinct under (view, claimants)
/// pair comparison (CONFORMANCE §3, DR-073 §3).
fn promote_collision_ambiguous_from(
  o : @engine.Outcome,
  collision_binds : Array[@engine.Binding],
  ek : Map[String, @engine.ExportKey],
) -> @engine.Outcome {
  match o {
    @engine.Success(_) => {
      let collisions = find_export_collisions(collision_binds, ek)
      if collisions.length() == 0 {
        return o
      }
      // Cross product of claimant choices per collision group — each combo picks one claimant per
      // group and drops the rivals' bindings at that (path, mapped-key) from THIS view (DR-073 §2:
      // entity name is the sole cross-view-stable identifier; value/source can coincide).
      let interps : Array[@engine.AmbInterp] = []
      for combo in claimant_combinations(collisions) {
        let filtered : Array[@engine.Binding] = []
        for b in collision_binds {
          let mut drop = false
          let mut gi = 0
          while gi < collisions.length() {
            let c = collisions[gi]
            if path_eq(c.path, b.scope) &&
              c.key ==
              (match ek.get(b.key) {
                Some(@engine.EkKey(s)) => s
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
      @engine.Ambiguous({ interpretations: interps, help_entry: None })
    }
    _ => o
  }
}

///|
/// Promote collisions already present in the parse bindings. The front door additionally supplies
/// upper-seat resolved bindings through the private variant so env/config/inherit claims participate.
fn promote_collision_ambiguous(
  o : @engine.Outcome,
  ek : Map[String, @engine.ExportKey],
) -> @engine.Outcome {
  match o {
    @engine.Success(binds) => promote_collision_ambiguous_from(o, binds, ek)
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

// ── result/sources の production 射影 (DR-109 §3 sources 常時出力 / MDR-005「射程外」節の解消、
// issue 2026-07-16-result-projection-production-promotion) ───────────────────────────────────

///|
/// 1 つの export 済み result-key の値源タグ (DR-031)。`path` は結果スコープ木を降りる scope
/// segment 列 (root なら `[]`)、`key` は `apply_export_keys` と同じ resolve (DR-052 §1) を経た
/// 露出キー、`source` は値源 — `@engine.Source::@engine.Default` は「未発火 (default 相当)」または「accum セルの
/// `@engine.Unset` op で未触の default 状態へ再着席した」を表す (`collect_sources_flat` のコメント参照)。
/// `pub(all)` (MDR-005 §3 の「正面玄関の 3 関数が直接運ぶ型は pub(all) を維持」原則に準拠) —
/// 呼び出し側 (kuu-cli 等) が `.path`/`.key`/`.source` を読んで JSON を組み立てる、フィールド
/// 読み取りが本体の型なので `AccumCell`/`DefaultCell`/`@engine.NoneCell` (組み立て素材を build_result に
/// 素通しするだけの不透明トークン、pub 止まり) とは扱いが異なる。
pub(all) struct SourceEntry {
  path : Array[String]
  key : String
  source : @engine.Source
} derive(Eq, Debug)

///|
/// `sc.greedy` に `@engine.CmdSat` (サブコマンド確定ノード) が 1 つでもあるか — command 木を持つ scope か
/// どうかの判定。runner (json_conformance_test.mbt) の同名ヘルパーと同一実装で、production 側の
/// `result_sources` にも同じ分岐が要るためこちらへ昇格した (runner 側は重複定義を避けるため
/// 削除しこの private fn を直接呼ぶ、同一パッケージ内アクセスなので `pub` 化は不要)。
fn has_commands(sc : @engine.Scope) -> Bool {
  for g in sc.greedy {
    match g {
      @engine.CmdSat(_, _) => return true
      _ => ()
    }
  }
  false
}

///|
/// command 木を持たない単一 scope 向けの sources 収集 (旧 runner `proj_sources` の構造化版、
/// String 直書きの `"default"` を `@engine.Source::@engine.Default` に置き換えた以外は元実装のロジックを不変に
/// 保つ)。`sc.entities` を直接走査するので **root scope 単体のみ** (子 command scope は見ない) —
/// 単一 scope 前提だからこそ「未発火セルは default 相当を報告する」フォールバック (accum セルの
/// `[]` 既定 / flag・bool の preset default、DR-044 の uniform array 既定 / LOWERING §A.5) を
/// 安全に持てる。config_file / `@builtins.none_type()` 型のセルは除外 (DR-089 §3: none has no value なので
/// source も持たない)。
fn collect_sources_flat(
  sc : @engine.Scope,
  resolved : Array[@engine.Binding],
  ek : Map[String, @engine.ExportKey],
) -> Array[SourceEntry] {
  let out : Array[SourceEntry] = []
  let emitted : Array[String] = []
  for e in sc.entities {
    if e.is_config_file {
      continue
    }
    if e.ty.name() == "none" {
      continue
    }
    match exposed_key_of(e.name, ek) {
      None => ()
      Some(exposed) =>
        if !str_contains(emitted, exposed) {
          let mut src : @engine.Source? = None
          for b in resolved {
            if !is_sentinel(b.key) && exposed_key_of(b.key, ek) == Some(exposed) {
              src = match b.op {
                // issue 2026-07-09-accum-filters-non-set-op-semantics: `@engine.Unset` は CLI 発火済みだが
                // 未確定 (committed=false、DR-045「default 値へ戻す... committed=false」) なので、
                // 値源タグは発火トークン自身の `source` ではなくラダーの再着席結果
                // ("as if untouched") を反映して `@engine.Default` を報告する。
                @engine.Unset => Some(@engine.Default)
                _ => Some(b.source)
              }
            }
          }
          match src {
            Some(s) => {
              out.push({ path: [], key: exposed, source: s })
              emitted.push(exposed)
            }
            None =>
              if e.accum is Some(_) {
                out.push({ path: [], key: exposed, source: @engine.Default })
                emitted.push(exposed)
              } else if (e.ty.name() == "flag" || e.ty.name() == "bool") &&
                e.accum is None {
                match default_scalar(e) {
                  Some(_) => {
                    out.push({ path: [], key: exposed, source: @engine.Default })
                    emitted.push(exposed)
                  }
                  None => ()
                }
              }
          }
        }
    }
  }
  out
}

///|
/// command 木全体を持つ scope 向けの sources 収集 (旧 runner `proj_sources_tree` の構造化版)。
/// `resolved` (resolve 済み全 binds、子 scope 含む) をそのまま走査すれば木全体を一度に拾えるが、
/// `collect_sources_flat` が持つ「未発火セルの default フォールバック」と export_key rename は
/// 適用しない — `resolve_scope_tree` の出力は既に「実際に着席した binding」だけを運ぶため、この
/// 経路では素の entity 名・生 scope path をそのまま使う (proj_sources_tree の元実装を踏襲、
/// 意味論は無改変)。
fn collect_sources_tree(
  resolved : Array[@engine.Binding],
) -> Array[SourceEntry] {
  let out : Array[SourceEntry] = []
  for b in resolved {
    if is_sentinel(b.key) {
      continue
    }
    out.push({ path: b.scope, key: b.key, source: b.source })
  }
  out
}

///|
/// front_door 昇格 (issue 2026-07-16-result-projection-production-promotion): `resolved`
/// (resolve 済み binds) から DR-109 §3 の `sources` 射影 (「resolve 済み出力には常に sources を
/// 含める」) を組み立てる。command 木の有無 (`has_commands`) で内部実装が分かれる
/// (`collect_sources_flat` / `collect_sources_tree`、直上 2 関数のコメント参照) が、**呼び出し側
/// はその分岐を意識しない** — 1 本のシグネチャで両ケースを覆う (front_door 玄関の「利用者は内部
/// 構造を意識しない」原則、MDR-005 冒頭)。
///
/// **runner はこの関数を直接は呼ばない**: conformance fixture は `resolve: <bool>` という
/// production に存在しない対照実験用ノブを持ち (「常時 resolve」前提の production とは異なり、
/// fixture は resolve 有無を明示的に選べる)、`proj_sources_tree`/`proj_sources` の使い分けは
/// 現状 `dc.resolve && has_commands(sc)` という fixture 固有条件に従う (`has_commands(sc)`
/// 単独ではない — この差は既存 conformance の観測済み挙動で、本 promotion は数字不変を条件と
/// するため保持する)。runner 側は代わりに本関数が内部で使う `collect_sources_flat`/
/// `collect_sources_tree` を自身の `dc.resolve && has_commands` 分岐から直接呼び、射影ロジックの
/// 重複だけを解消する。
fn result_sources(
  sc : @engine.Scope,
  resolved : Array[@engine.Binding],
  ek : Map[String, @engine.ExportKey],
) -> Array[SourceEntry] {
  if has_commands(sc) {
    collect_sources_tree(resolved)
  } else {
    collect_sources_flat(sc, resolved, ek)
  }
}

// ── DR-047 §4/§5 (issue value-present-ladder-gap 裁定 2026-07-10、bool target 分は元 issue
// bool-requires-config-inherit-gap 裁定 2026-07-09): requires の後段 path filter ───────────────
//
// requires (CRequires) / value 依存 requires (CRequiresIf) の目的語の充足条件は「値源ラダー
// (env/config/inherit/default) 充填後の最終状態」で決まる — bool 型 (@builtins.flag_type()/@builtins.bool_type()) なら「解決後の
// 値が true であること」(値源不問)、非 bool なら「値の有無 (default 込み)」(DR-047 §5 表)。この
// 判定は値源ラダーが解ける後段でしか行えないため、KTop (eval.mbt, CLI 面のみで完結する完全経路
// 判定) では両方とも常に pass 扱いとしてスキップし (`is_bool_entity` が bool/非bool の分岐ゲート)、
// ここで `parse()` の @engine.Outcome を受け取って事後フィルタとして適用する — `promote_collision_ambiguous`
// (DR-073, 直上) と同じ「@engine.Outcome を受け取り @engine.Outcome を返す後処理」パターン。
//
// 非bool 分は元々 `value_present` (= committed OR has_default) として KTop で即時評価していたが、
// これは env/config/inherit 経由の供給を無視する実装ショートカットだった (DR-047 §4 の「値源ラダー
// 充填後の最終状態で評価する」規定と乖離、issue value-present-ladder-gap で発見・実機再現)。

///|
/// `name` (entities 内で探した @engine.Entity) が bool 型 (@builtins.flag_type()/@builtins.bool_type()) かどうか — DR-047 §5 の bool/非bool
/// 目的語判定ゲート。この後段フィルタが bool 判定式 (真理値) と非bool 判定式 (値の有無) のどちらを
/// 使うかを分ける。
fn is_bool_entity(entities : Array[@engine.Entity], name : String) -> Bool {
  for e in entities {
    if e.name == name {
      return e.ty.name() == "flag" || e.ty.name() == "bool"
    }
  }
  false
}

///|
/// `name` (entities 内で探した @engine.Entity) が値空間なし型 (`@builtins.none_type()`、dd 含む) かどうか — DR-093 §1/§2 の
/// 型委譲ゲート。値空間なし要素の充足 (required 自身 / requires 目的語) は committed で判定し、
/// 値空間あり要素は最終状態の値の有無で判定する (`is_bool_entity` と対になる、同じ形のゲート)。
/// 見つからない場合は `true` (= 値空間なし扱い) — `is_bool_entity` (見つからなければ `false`) と
/// 非対称に見えるが、dd 要素は DR-030「実体=値セル」/ LOWERING §B.4「dd は値を生まない」により
/// `ensure_entities` が最初から entity を作らない (`not_dd` ガード)。値空間の有無は entity の有無と
/// 一致するので、「entity が無い」は「値空間なし」の別表現であり、この既定側が正しい。
fn is_none_entity(entities : Array[@engine.Entity], name : String) -> Bool {
  for e in entities {
    if e.name == name {
      return e.ty.name() == "none"
    }
  }
  true
}

///|
/// `@engine.RequiredCandidate` 1 件の最終判定 (型委譲、codex レビュー M-2 修正): `CRequired`/
/// `CRequiredGroup` の resolve.mbt 側 (最終判定) 共有ヘルパー — `wrapper` が `None` なら宣言 scope
/// path そのもの (`@engine.is_committed`/`@engine.elem_value`)、`Some(w)` なら宣言元要素 `w` 自身の @engine.Scoped 部分木内
/// (`@engine.is_committed_in_subtree`/`@engine.elem_value_in_subtree`、eval.mbt 側の同名 subtree ヘルパーを resolve
/// 層でも再利用) で判定する。`is_none_entity` (値空間なし = committed 判定、値空間あり = 値の有無
/// 判定) のゲートは wrapper の有無と直交 — ref 経由の candidate は `@engine.Scope.entities` に登録されない
/// ため常に `is_none_entity` は `true` (committed 判定) に倒れる (`ensure_entity_body` の BCell
/// コメント参照、値空間はあるが entity が無いだけの縮退)。
fn candidate_satisfied(
  c : @engine.RequiredCandidate,
  entities : Array[@engine.Entity],
  bindings : Array[@engine.Binding],
  resolved : Array[@engine.Binding],
  path : Array[String],
) -> Bool {
  match c.wrapper {
    None =>
      if is_none_entity(entities, c.name) {
        @engine.is_committed(bindings, path, c.name)
      } else {
        @engine.elem_value(resolved, path, c.name) != None
      }
    Some(w) =>
      if is_none_entity(entities, c.name) {
        @engine.is_committed_in_subtree(bindings, path, w, c.name)
      } else {
        @engine.elem_value_in_subtree(resolved, path, w, c.name) != None
      }
  }
}

///|
/// One scope's `requires`/value 依存 requires violations, evaluated against a CANDIDATE path's
/// CLI-only bindings (trigger 判定、DR-047 §5 表「トリガ側 = committed」) AND the SAME candidate's
/// fully resolved bindings (目的語判定、「目的語側 = 値の有無/真理値」) — issue
/// resolve-first-constraint-pipeline (Phase 1) 裁定 2026-07-10: 目的語の充足判定は、もはやこの関数が
/// 自前のラダー (env/config/inherit) を再演するのではなく、呼び出し元が既に `resolve_scope_tree` で
/// 解決済みの `resolved` を渡してくるので `@engine.elem_value` の単純参照で済む (値源不問は「resolve 済み
/// なら値源を意識する必要がない」という形で自然に成立する)。issue value-present-ladder-gap 裁定
/// 2026-07-10 でこの読者化を非bool 目的語にも拡張した — bool は `@engine.elem_value(resolved,...) ==
/// Some("true")`、非bool は `@engine.elem_value(resolved,...) != None` (値の有無) の 2 分岐。
///
/// `@engine.constraint_err`'s `path` defaults to `[]` (KTop's contract: a @engine.Held rides the cont chain and
/// scope boundaries prepend the path on the way out) — that mechanism doesn't run here (the path
/// is already fully resolved), so `sc.path` (DR-066 §4 result-nesting path) is threaded in
/// directly via struct-update.
fn eval_requires(
  sc : @engine.ScopedCons,
  bindings : Array[@engine.Binding],
  resolved : Array[@engine.Binding],
  pos : Int,
) -> Array[@engine.ParseError] {
  let out : Array[@engine.ParseError] = []
  let path = sc.path
  // DR-093 §1/§3: 目的語の充足判定は型 (値空間) への委譲 — 値空間なし (none) は発火 (committed)、
  // bool は解決後値が true、それ以外 (通常の値空間あり型) は値の有無。none 分岐が先 (bool/非bool の
  // 判定は値空間があることが前提で、none には値そのものが無い)。
  let satisfied = fn(t : String) -> Bool {
    if is_none_entity(sc.entities, t) {
      @engine.is_committed(bindings, path, t)
    } else if is_bool_entity(sc.entities, t) {
      @engine.elem_value(resolved, path, t) == Some("true")
    } else {
      @engine.elem_value(resolved, path, t) != None
    }
  }
  for c in sc.constraints {
    match c {
      CRequires(elem, targets) =>
        if @engine.is_committed(bindings, path, elem) {
          for t in targets {
            if !satisfied(t) {
              out.push({
                ..@engine.constraint_err(
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
        let active = @engine.is_committed(bindings, path, entity) &&
          (match @engine.elem_value(bindings, path, entity) {
            Some(x) => x == v
            None => false
          })
        if active {
          for t in targets {
            if !satisfied(t) {
              out.push({
                ..@engine.constraint_err(
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
      CRequired(display, candidates) => {
        // DR-093 §1/§2: 自身の充足は型委譲。値空間なし (none) = 発火 (committed)、値空間あり =
        // 最終状態の値の有無 (default 込み、DR-047 §5 不変)。`satisfied` (上記 requires 目的語用) は
        // 再利用しない — bool の「解決後値 true」ルールは requires 目的語限定 (DR-047 §5 明確化) で
        // あり、required 自身の充足には持ち込まない (DESIGN §9.1 に bool 特例なし、bool は preset
        // default:false を常に持つため required 自身は「値の有無」で自明に充足する、それが spec の
        // 意図どおり)。
        //
        // issue 2026-07-13-structural-or-type-branch-required-missing /
        // codex-review-dr102-dr103-postland (M-2): `candidates` は structural or (直書き BOr /
        // ref 経由) の場合、各枝の leaf name の配列 (node.mbt の `@engine.RequiredCandidate`/`CRequired`
        // doc comment 参照、eval.mbt の同名 KTop 判定と対の最終判定)。`candidate_satisfied` が
        // wrapper (ref 経由なら宣言元要素の @engine.Scoped 部分木限定) を踏まえて判定する。いずれか 1 つ
        // でも型委譲で充足していれば OK。
        let mut ok = false
        for c in candidates {
          if candidate_satisfied(c, sc.entities, bindings, resolved, path) {
            ok = true
          }
        }
        if !ok {
          out.push({
            ..@engine.constraint_err(
              display,
              "required_violated",
              "required '\{display}' is missing",
              pos,
            ),
            path,
          })
        }
      }
      CRequiredGroup(group, members) => {
        // DR-103 §1/§7: member 充足は `CRequired` と完全に同一の型委譲 (値空間なし = committed、
        // 値空間あり = 値の有無、default 込み) — bool 特例 (`satisfied` の requires 目的語ルール)
        // は適用しない。member のいずれか 1 つでも充足すればグループ成立 (少なくとも1つ必須)。
        let mut ok = false
        for m in members {
          if candidate_satisfied(m, sc.entities, bindings, resolved, path) {
            ok = true
          }
        }
        if !ok {
          out.push({
            ..@engine.constraint_err(
              group,
              "required_group_violated",
              "required group '\{group}' has no satisfied member",
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
/// scope was actually entered in this candidate". Ported from `json_conformance_test.mbt`'s
/// `scope_entered` (production code can't reference a wbtest-only symbol; wbtest files aren't
/// linked into non-test builds) for `resolve_scope_tree`'s own use.
fn scope_entered_here(
  binds : Array[@engine.Binding],
  path : Array[String],
) -> Bool {
  for b in binds {
    if path_eq(b.scope, path) {
      return true
    }
  }
  false
}

///|
/// Whether `sc.greedy` enters a genuine command scope named `name` (a `@engine.CmdSat` node) — used by
/// `resolve_scope_tree`'s pass-through below to tell a real child COMMAND scope apart from a
/// ref-template accum entity's own one-level-deeper binding wrap (`ref_row_head`/`@engine.Scoped(e.name,
/// ...)`, installer.mbt DR-078 §1). Only a `@engine.CmdSat` name is a scope `resolve_scope_tree` should
/// recurse the ladder into; anything else sharing the same "one level deeper" shape is CLI-origin
/// material that must be passed through untouched instead.
fn is_cmdsat_child(sc : @engine.Scope, name : String) -> Bool {
  for g in sc.greedy {
    match g {
      @engine.CmdSat(n, _) => if n == name { return true }
      _ => ()
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
/// This is the production promotion of `json_conformance_test.mbt`'s `resolve_tree` (issue
/// resolve-first-constraint-pipeline, Phase 1): same recursive shape, generalized from the test
/// harness's `DCase`-specific `NoCfg`/`CfgObj`/`CfgFiles` dispatch to a plain `provider` closure
/// (`resolve_scope_config`'s own contract), so production callers — not just the conformance
/// harness — can resolve a whole tree, not just one scope. `apply_requires_filter` below is
/// the first such caller; `json_conformance_test.mbt`'s own `resolve_tree` is expected to become
/// a thin `dc.cfg`-to-`provider` adapter over this function (not duplicated here).
///
/// `binds` is the CLI-only raw bindings for ONE candidate path (`parse()`'s `@engine.Success`/`@engine.AmbInterp`
/// payload) — not yet split by scope; this function filters to `path`'s own direct bindings at
/// each recursion level. The returned `Array[@engine.Binding]` is flat with every binding's `scope` tagged
/// to its owning path (the same shape `build_result`/`proj_sources_tree` already consume) — a
/// caller wanting a value at a nested path uses the ordinary `@engine.elem_value`/`@engine.is_committed` lookups
/// with that path, no different from a single-scope `resolve_scope_config` caller.
fn resolve_scope_tree_with_export(
  sc : @engine.Scope,
  binds : Array[@engine.Binding],
  env_map : Map[String, String],
  provider : (String) -> @engine.ConfigVal?,
  path : Array[String],
  inherited : Map[String, @engine.Value],
  at_pos : Int,
  tty : Map[String, TtyObs],
  ek : Map[String, @engine.ExportKey],
  extensions : @engine.Registry,
  include_default : Bool,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  let here : Array[@engine.Binding] = []
  for b in binds {
    if path_eq(b.scope, path) {
      here.push(b)
    }
  }
  let resolved = match
    resolve_scope_config_with_export(
      sc, here, env_map, provider, path, inherited, at_pos, tty, ek, extensions,
      include_default,
    ) {
    Ok(rb) => rb
    Err(pe) => return Err(pe)
  }
  let out : Array[@engine.Binding] = []
  for b in here {
    if is_sentinel(b.key) {
      out.push(b)
    }
  }
  for b in resolved {
    out.push({ ..b, scope: path })
  }
  // DR-078 §1 pass-through (issue front-door-resolve-ref-repeat-row-drop, K カテゴリ: front_door
  // 経由の repeat rows 行集約欠落): a ref-template accum entity (e.g. an `or`/`seq` ref option
  // with `repeat`/`multiple`) wraps its OWN row/fire bindings one scope level deeper than its
  // declaring scope (`ref_row_head`/`@engine.Scoped(e.name, ...)`, installer.mbt) — `colorname`/`r`/`g`/
  // `b`/`#row`/`#fire` all land at `scope = path + [e.name]`, never at `scope == path` itself. The
  // `here` filter above (exact `path_eq` match) therefore never sees them, and they are NOT a
  // genuine command-scope child either (`is_cmdsat_child` below rules that out) — without this
  // pass-through they were silently dropped by every `resolve()` call (kuu-cli's front_door path
  // always resolves; the conformance runner only did for fixtures needing the default ladder,
  // which is why `moon test` stayed green while kuu-cli lost the row array entirely, rendering
  // `[]` instead of the fired rows). These bindings carry no ladder seat of their own (a ref
  // template field has no individual env/config/inherit/default seat, DR-078 §1) — they are pure
  // CLI-origin material `build_result`'s ROW-GROUP/SEGS branches (resolve.mbt) already know how to
  // fold via `sub_under`, so forwarding them unchanged (not through `resolve_scope_config`) is the
  // correct treatment, mirroring the sentinel-preservation loop just above.
  for b in binds {
    if b.scope.length() > path.length() {
      let mut is_prefix = true
      let mut i = 0
      while i < path.length() {
        if b.scope[i] != path[i] {
          is_prefix = false
        }
        i = i + 1
      }
      if is_prefix {
        let next = b.scope[path.length()]
        if !is_cmdsat_child(sc, next) {
          out.push(b)
        }
      }
    }
  }
  let child_inherited : Map[String, @engine.Value] = Map([])
  for k, v in inherited {
    child_inherited.set(k, v)
  }
  for b in resolved {
    child_inherited.set(b.key, b.value)
  }
  for g in sc.greedy {
    match g {
      @engine.CmdSat(name, child) => {
        let childpath = path_push(path, name)
        if scope_entered_here(binds, childpath) {
          match
            resolve_scope_tree_with_export(
              child, binds, env_map, provider, childpath, child_inherited, at_pos,
              tty, ek, extensions, include_default,
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
/// Apply the DR-047 §4/§5 requires path filter to a `parse()` @engine.Outcome (final_filters/accum_filters
/// と同じ側の後段処理、`promote_collision_ambiguous` と同型パターン — `parse()` 自体のシグネチャ・eval 層の
/// @engine.Ctx は無改修のまま、値源 (env/config/inherit) を後から与える)。bool 目的語 (真理値判定) と非bool
/// 目的語 (値の有無判定) の両方をここで扱う (issue value-present-ladder-gap 裁定 2026-07-10 で対象
/// 拡張、旧名 `apply_requires_filter` から改名)。生存経路数で outcome を再構成する: 0 →
/// `@engine.Failure` (violation を DR-053 §2 全保持で errors に、`fired_action`/`help_entry`/
/// `tried_triggers` は既存 KTop 発 @engine.Failure と同じ素材関数から構築 — 区別が付かない形にする、
/// DR-048 の「候補経路は dead end を含む」通り違反で落ちた経路の action も候補に数える)、1 → その
/// 経路で `@engine.Success`、2+ → 生存分だけの `@engine.Ambiguous`。`root`/`defs` は制約テーブル (`@engine.collect_scopes`)
/// と `@engine.find_help_entry`/`@engine.tried_triggers_of` の素材取得に使う。
///
/// issue resolve-first-constraint-pipeline (Phase 1、audit issue lazy-default-resolution-audit の
/// finding への根治): 候補ごとに `resolve_scope_tree` で実際に解決してから `@engine.elem_value` を読むだけの
/// 「読者」に再設計した (以前の `resolved_bool_value_ladder` 自前ミニラダー + `config_obj:
/// @engine.ConfigVal?` 単一オブジェクト契約 + `collect_all_scopes` 祖先探索テーブルは全廃)。
/// `provider~` は `resolve_scope_config` と同じ `(String) -> @engine.ConfigVal?` 契約 — スコープごとに
/// 異なる config_file を動的に指す CfgFiles ケースも、呼び出し元が対応する provider を渡すだけで
/// 均一に扱われる (単一 @engine.ConfigVal だった旧契約の既知の残存ギャップが解消)。省略時は常に `None` を
/// 返す no-op provider (config 未使用の既存呼び出し元は無改修)。
///
/// `table.length() == 0` (このスコープ木に requires 制約が一つも無い) なら resolve を試みずに
/// 即座に `[]` を返す — 制約が無い定義で resolve コストを払わない、かつ無関係な entity の env/config
/// 解決エラーを不要に持ち込まない (両立できる速い経路)。
fn apply_requires_filter_with_export(
  o : @engine.Outcome,
  root : @engine.Node,
  defs : Map[String, @engine.Node],
  env : Map[String, String],
  toks_len : Int,
  provider : (String) -> @engine.ConfigVal?,
  tty : Map[String, TtyObs],
  ek : Map[String, @engine.ExportKey],
  extensions : @engine.Registry,
) -> @engine.Outcome {
  let table = @engine.collect_scopes(root, defs)
  let violations_of = fn(
    binds : Array[@engine.Binding],
  ) -> Array[@engine.ParseError] {
    if table.length() == 0 {
      return []
    }
    match root {
      @engine.ScopeNode(sc) =>
        match
          resolve_scope_tree_with_export(
            sc,
            binds,
            env,
            provider,
            [],
            Map([]),
            toks_len,
            tty,
            ek,
            extensions,
            true,
          ) {
          Ok(resolved) => {
            let out : Array[@engine.ParseError] = []
            for sc2 in table {
              // SCB-Q1=a (kawaz 裁定 2026-07-17、docs/QUESTIONS.md の SCB batch): 未選択 (= 当該実行で
              // 未入場) command scope に宣言された遅延述語は評価に参加しない。原理は「グローバルオプション
              // 以外、サブコマンドは完全に別コマンドと見るべき」で、root scope (path=[]) は常に選択済み。
              // DR-103 §5 明確化 note が正本。engine 側 `eval_all_constraints` (KTop 相の粗判定) と同型
              // の gate をここ resolve 相 (後段の最終判定) にも掛ける — gate が 1 相にしか無いと未入場
              // child の CRequiredGroup/CRequired が resolve 相で偽陽性を出し、KTop の Success を Failure
              // に落としてしまう (issue required-group-scope-participation、実測: `--r1` のみで
              // child-a scope の g が違反として付随、path=[child-a] の error 生成)。gate の判定は engine
              // 側と完全に同じ `@engine.scope_selected` を共用 — 判定意味論のドリフト防止 (bindings 内の
              // `{}` scope_marker の存在で判定、CmdSat 入場時に cont.mbt KNest が prepend する)。
              if !@engine.scope_selected(binds, sc2.path) {
                continue
              }
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
    binds_for_actions : Array[Array[@engine.Binding]],
    errors : Array[@engine.ParseError],
  ) -> @engine.Outcome {
    let actions : Array[(String, Int)] = []
    for bs in binds_for_actions {
      @engine.collect_actions(bs, actions)
    }
    @engine.Failure({
      errors,
      fired_action: if actions.length() > 0 {
        Some(@engine.argmin_action(actions))
      } else {
        None
      },
      help_entry: @engine.find_help_entry(root, errors),
      tried_triggers: @engine.tried_triggers_of(root, errors),
    })
  }
  match o {
    @engine.Success(binds) =>
      match violations_of(binds) {
        [] => o
        viol => build_failure([binds], viol)
      }
    @engine.Ambiguous(d) => {
      let survivors : Array[@engine.AmbInterp] = []
      let all_violations : Array[@engine.ParseError] = []
      let all_binds : Array[Array[@engine.Binding]] = []
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
        1 => @engine.Success(survivors[0].binds)
        _ =>
          @engine.Ambiguous({
            interpretations: survivors,
            help_entry: d.help_entry,
          })
      }
    }
    @engine.Failure(_) => o
  }
}

// ── value-source ladder (slice `poc/installer.mbt`'s resolve_scope / resolve_scope_config) ───

///|
/// A @engine.Value rendered as its comparison string (constraint value matching: integers print without
/// the trailing `.0`). The resolve layer owns the result-object rendering; this is also the
/// CRequiresIf comparison form (moved here from eval.mbt, MDR-002 §3 table — this is resolve.mbt's
/// canonical home; eval.mbt's `@engine.elem_value` calls this file's copy, same package).

///|
/// A DR-066 ladder-fill Error: `element`/`args_pos` locate it like any @engine.ParseError; `at_pos` is the
/// caller-supplied final position (env/config seat errors are not read at a token position — they
/// surface after the path completed, the same conceptual point `eval_constraints` evaluates at, so
/// callers thread the same final `toks.length()`). kind is always `@engine.KParse` (a value-source failed
/// to parse into the entity's type — the same category as a bad CLI token, DR-053). `epath` is the
/// DR-066 §4 ancestor path (root-first, [] = root 直下): this ladder walk resolves ONE scope's
/// entities at a time and already carries the scope's own result-nesting path (the `resolve_tree`
/// caller threads it in), so — unlike eval.mbt's CPS @engine.Held (which starts at [] and picks up ancestors
/// crossing scope boundaries on the way out) — the ladder path is known statically and passed in
/// directly, no boundary-crossing accumulation needed.
fn ladder_err(
  element : String,
  at_pos : Int,
  reason : String,
  message : String,
  epath : Array[String],
) -> @engine.ParseError {
  {
    element,
    args_pos: at_pos,
    kind: @engine.KParse,
    reason,
    message,
    path: epath,
  }
}

///|
/// A DR-053 §2 filter-reject Error: `value_filters`/`final_filters`/`accum_filters` (DR-009 §7,
/// DR-102 §1) rejected an already-resolved value. Distinct from `ladder_err` (`kind: @engine.KParse`, a
/// value-source failed to parse) —
/// a filter reject is a validation/transform rejection over a value that parsed fine, so it gets
/// its own builder with `kind: @engine.KFilter` (DR-053 §2's 3-way `parse` | `filter` | `constraint` split;
/// `eval.mbt`'s `filter_arg_eval` already emits `@engine.KFilter` for the same conceptual failure at the
/// token-parsing layer, this is `apply_entity_filters`'s resolve-layer counterpart). Same
/// `at_pos`/`epath` threading contract as `ladder_err`.
fn filter_err(
  element : String,
  at_pos : Int,
  reason : String,
  message : String,
  epath : Array[String],
) -> @engine.ParseError {
  {
    element,
    args_pos: at_pos,
    kind: @engine.KFilter,
    reason,
    message,
    path: epath,
  }
}

///|
/// Parse an env string into a @engine.Value per the entity's type (DR-049 §2: env goes through the same
/// pipeline as CLI). Unlike slice's `env_value` (naive `@builtins.parse_number` with a silent `@engine.VStr` fallback
/// on failure), this reuses the canonical lexers (DR-074/075) and surfaces a parse failure as a
/// DR-066 Error — a badly-typed env value is never silently coerced to a wrong-typed string cell.
/// `piece_filters` (DR-034/DR-062, issue 2026-07-09-pre-split-filters-execution-wiring): DR-049 §2
/// says env goes through the SAME pipeline as CLI, which includes piece_filters — applied here BEFORE
/// the type-specific parse below (including the `@builtins.string_type()` arm, so `trim` etc. also affects a plain
/// string env value, not just numeric rescue). This is env's OWN application point, distinct from
/// the CLI seat's (eval.mbt/builtins/matcher_residents.mbt, applied at token-consumption time, before the value ever
/// reaches this @engine.Entity-based ladder).
fn env_value(
  element : String,
  ty : &@engine.TypeExt,
  s : String,
  piece_filters : Array[@engine.FilterSpelling],
  at_pos : Int,
  epath : Array[String],
  extensions : @engine.Registry,
) -> Result[@engine.Value, @engine.ParseError] {
  let s = match @engine.apply_piece_filters(extensions, piece_filters, s) {
    Ok(v) => v
    Err((reason, msg)) =>
      return Err(filter_err(element, at_pos, reason, msg, epath))
  }
  match ty.parse_token(s) {
    Ok(value) => Ok(value)
    Err(fail) =>
      Err(
        ladder_err(element, at_pos, fail.reason, "env " + fail.message, epath),
      )
  }
}

///|
/// Navigate a config object by an absolute path (DR-050 §3). Each segment indexes into a @engine.CObj;
/// a missing key or a non-object mid-path yields None (this cell is not supplied by config).
fn config_lookup(
  obj : @engine.ConfigVal,
  path : Array[String],
) -> @engine.ConfigVal? {
  let mut cur = obj
  for seg in path {
    match cur {
      @engine.CObj(kvs) => {
        let mut found : @engine.ConfigVal? = None
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
  e : @engine.Entity,
  cli : Array[@engine.Binding],
  env_map : Map[String, String],
  config_obj : @engine.ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, @engine.Value],
  at_pos : Int,
  epath : Array[String],
  tty_map : Map[String, TtyObs],
  extensions : @engine.Registry,
  include_default : Bool,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  match
    resolve_entity_raw(
      e, cli, env_map, config_obj, config_path, inherited, at_pos, epath, tty_map,
      extensions, include_default,
    ) {
    Ok(bs) =>
      if !include_default && bs.length() == 0 {
        Ok([])
      } else {
        apply_entity_filters(e, bs, at_pos, epath, extensions)
      }
    Err(pe) => Err(pe)
  }
}

///|
/// DR-009 §value_filters/final_filters (DR-102 §1 属性分割) applied to whatever `resolve_entity_raw`
/// resolved (any ladder seat: cli/env/config/inherit/default — DR-077 §1's whole point is that
/// `set` and `update` effects converge here indistinguishably). `value_filters` (each) applies to
/// every binding; `final_filters` (T→T、確定した最終値) applies ONLY to a scalar cell's (no accum)
/// single binding — an accum cell's TRUE "post accumulation" gate is `accum_filters`, applied at
/// build_result (resolve.mbt's caller) instead, which this function does not reach for that cell.
/// `@engine.Empty`'s binding carries a PLACEHOLDER value (DR-045 — the real "clear the collection" effect
/// has no value of its own), so it's exempt from both chains — running a number/string filter over
/// a bogus `@engine.VBool(false)` placeholder would be nonsensical.
fn apply_entity_filters(
  e : @engine.Entity,
  bs : Array[@engine.Binding],
  at_pos : Int,
  epath : Array[String],
  extensions : @engine.Registry,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  let out : Array[@engine.Binding] = []
  for b in bs {
    // value_filters(each、段5) applies only to a binding carrying a REAL value (kawaz 裁定
    // 2026-07-09、issue accum-filters-non-set-op-semantics): `@engine.Set` (a plain value bind) and
    // `@engine.Update`'s applied result. The scalar CLI-seat fold (resolve_entity_raw's non-accum branch)
    // already converts a committed `@engine.Update` to a `@engine.Set` binding via `@engine.mk_binding` before it ever reaches
    // here, so this function never special-cases `@engine.Update` itself — checking `op == @engine.Set` alone
    // covers both. `@engine.Unset`/`@engine.Default`/`@engine.Empty` are operations ON THE CELL, not a piece carrying a
    // value — their bindings carry no meaningful operand (placeholder values, `mk_effect`'s doc
    // comment) and must pass through untouched. This generalizes the old "only `@engine.Empty` is exempt"
    // rule: for a SCALAR cell the fold above already collapses everything else to `@engine.Set`/`@engine.Empty`
    // so the two rules were equivalent there, but an ACCUM cell's fold (resolve_entity_raw's
    // `e.accum is Some(_)` branch) preserves every op UNINTERPRETED — without this
    // generalization, a `@engine.Default`/`@engine.Unset` binding's placeholder value would wrongly run through
    // `e.value_filters` (issue's `--ports 5 --reset-ports` repro).
    if b.op != @engine.Set {
      out.push(b)
    } else {
      match @engine.apply_filter_chain(extensions, e.value_filters, b.value) {
        Err((reason, msg)) => {
          // value_filters(each、段5、DR-009): CONFORMANCE §3's piece-attribution rule — a reject here
          // is attributed to the SPECIFIC args token the rejected piece came from (`b.at_pos`,
          // issue 2026-07-09-accum-entity-filters-wiring), not the ladder's own `at_pos` (which
          // stays args.length — the "no specific token" fallback for env/config/inherit/default-
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
            match
              @engine.apply_filter_chain(extensions, e.final_filters, b2.value) {
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
  // DR-105 §4 (統括裁定, ArrayFilterDescriptor の Result 化): an accum cell's accum_filters (Acc→Acc,
  // ARRAY filter registry) can now reject (`length_range` etc, DR-105 §5) — the reject must surface
  // HERE, at resolve time, not silently inside `build_result` (which has no error channel and runs
  // for every fixture regardless of whether the ladder/`use_resolve` path was taken). `out` at this
  // point is exactly this entity's own value_filters-applied binding list, ops preserved
  // (`resolve_entity_raw`'s accum branch never folds an accum cell's bindings to last-wins) — the
  // SAME fold `build_result`'s ACCUMULATE branch performs (@engine.Empty/@engine.Unset/@engine.Default clears the running
  // array, everything else appends its value) is replicated here so the two stay in lockstep.
  // `args.length()` attribution (DR-102 §4, effectuated by DR-105 §4): reuses `at_pos`, the same
  // "no specific token" position `final_filters`'s own reject above already reports at.
  if e.accum is Some(_) && e.accum_filters.length() > 0 {
    let mut vals : Array[@engine.Value] = []
    for b in out {
      match b.op {
        @engine.Empty | @engine.Unset | @engine.Default => vals = []
        _ => vals.push(b.value)
      }
    }
    match @engine.apply_accum_filter_chain(extensions, e.accum_filters, vals) {
      Ok(_) => ()
      Err((reason, msg)) =>
        return Err(filter_err(e.name, at_pos, reason, msg, epath))
    }
  }
  Ok(out)
}

///|
/// The pre-DR-009-filters ladder resolution (cli > env > config > inherit > default) — unchanged
/// behavior from before this issue, just renamed so `resolve_entity` can wrap it with filter chain
/// application (`apply_entity_filters`) without duplicating the ladder logic.
fn resolve_entity_raw(
  e : @engine.Entity,
  cli : Array[@engine.Binding],
  env_map : Map[String, String],
  config_obj : @engine.ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, @engine.Value],
  at_pos : Int,
  epath : Array[String],
  tty_map : Map[String, TtyObs],
  extensions : @engine.Registry,
  include_default : Bool,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  // cli seat (DR-015 last-wins + DR-077 §1 update fold): fold every same-name CLI effect in args
  // order, not just peek at the last one. `update`'s result is OLD-DEPENDENT — a single "read the
  // last binding" can no longer resolve the seat once update effects are mixed with
  // set/default/empty/unset (`-vvv` needs old=0→1→2, each rep depending on the ONE before it). For
  // every definition that never uses `update`, this fold degenerates to EXACTLY the prior "last
  // committed op wins" read (each non-update op still just replaces `current` outright, same as
  // before) — DR-015's last-wins guarantee (fixture multiple-parse/last-wins-scalar.json) is a
  // special case of this fold, not a different algorithm.
  // `current` holds the FULL binding (not just its value) — @engine.Set/@engine.Default/@engine.Empty must be returned
  // VERBATIM downstream (@engine.Empty's `value` is a placeholder that a later result-builder interprets
  // by `op`, not by `value`; @engine.Default's `source` must read `@engine.Default`, not `@engine.Cli`) exactly as the
  // pre-fold code did (`return Ok([b])` / `return Ok([@engine.mk_binding(e.name, v, @engine.Default)])`). Only `update`
  // needs the running VALUE (as `old`) — `.value` is read off `current` at that point, never
  // reconstructed from scratch.
  // accum セル (multiple/repeat, DR-034/043): the CLI seat must preserve EVERY same-name @engine.Binding,
  // not fold to "last wins" — build_result's ACCUMULATE branch (resolve.mbt's caller,
  // `@engine.Empty`/`@engine.Unset`/`@engine.Default` = clear-point, else = append) is the layer that interprets the op
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
  //   earlier (`@builtins.classify_long_spelling`'s `@builtins.LInvalid`). The `@engine.Update` arm below is unreachable
  //   defensive code, not a live path.
  // - `default`: resets to `[]` (DR-051 §2's uniform-array default — an accum cell carries no
  //   declared default BY DESIGN, `AccumCell` has no such field) with committed=true (locks the
  //   ladder, mirrors scalar's `unset-ladder.json` default-commits-locked precedent). The op itself
  //   carries no operand, so there's no piece for value_filters/accum_filters to act on (DESIGN
  //   §8.3) — build_result's ACCUMULATE match folds `@engine.Default` exactly like `@engine.Empty`/`@engine.Unset` (a
  //   clear-point), so only the SOURCE TAG differs here: rewriting `source` to `@engine.Default` (mirrors
  //   scalar's `@engine.mk_binding(e.name, v, @engine.Default)`) keeps `proj_sources`/harness correct without a
  //   default-specific branch there.
  // - `unset`: stays uncommitted (committed=false, unchanged from before) — if every same-name CLI
  //   effect in this seat ends up uncommitted, the CLI seat falls through to the lower ladder rungs
  //   (env/config/inherit/default) below, exactly like the scalar branch already does
  //   (`unset-ladder.json`'s `unset-opens-ladder`) — this is the new `committed_now` gate replacing
  //   the old unconditional `bs.length() > 0` return.
  // DR-080 波及節: a merge-accumulator cell's CLI seat is NOT a per-binding fold — a "発火" is a
  // GROUP of same-`at_pos` @engine.Set/@engine.Remove/@engine.Splice pieces (one args token's separator-split), evaluated
  // together against the DR-080 §3 rule (old composition, remove/splice, implicit leading `@`).
  // That grouping cannot be expressed inside this function's per-binding `match b.op` loop (which
  // append/flatten's accumulators are correctly built around, one binding = one independent
  // effect) — factored into its own function.
  match e.accum {
    Some(resident) => {
      let lower : @engine.LowerSeat = fn(include_default_) {
        resolve_ladder_below_cli(
          e,
          env_map,
          config_obj,
          config_path,
          inherited,
          at_pos,
          epath,
          tty_map,
          extensions,
          include_default=include_default_,
        )
      }
      return resident.resolve_cli(e.name, cli, include_default, lower)
    }
    None => ()
  }
  let mut current : @engine.Binding? = None
  let mut committed_now = false
  for b in cli {
    if b.key == e.name {
      match b.op {
        @engine.Set => {
          current = Some(b)
          committed_now = true
        }
        @engine.Default =>
          // DR-081 §2: op=default sets the CURRENT (already-rewritten) default value — env/
          // config/inherit don't "win as a lower seat" here, they've already rewritten the
          // cell's default (§1's model) by the time this fires, so querying the SAME ladder
          // `resolve_ladder_below_cli` runs for a normal fall-through gets exactly that value.
          // `source` is ALWAYS `@engine.Cli` now (DR-081 §2 "確定させた主体"重視 — the default's own
          // provenance, even if it's env, doesn't change WHO committed it) — this is the one
          // behavior change from the pre-DR-081 code, which tagged `source: @engine.Default` here.
          match
            resolve_ladder_below_cli(
              e, env_map, config_obj, config_path, inherited, at_pos, epath, tty_map,
              extensions,
            ) {
            Ok(bs2) => {
              current = if bs2.length() > 0 {
                Some(
                  @engine.mk_binding(
                    e.name,
                    bs2[bs2.length() - 1].value,
                    @engine.Cli,
                  ),
                )
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
        @engine.Empty => {
          current = Some(b)
          committed_now = true
        }
        // NOT committed: resets the running value to default so a LATER update in the same
        // fold sees the right "old" — but this seat stays eligible to fall through to
        // env/config/inherit if nothing commits after it (unchanged pre-DR-077 contract).
        @engine.Unset => {
          current = match default_scalar(e) {
            Some(v) => Some(@engine.mk_binding(e.name, v, @engine.Default))
            None => None
          }
          committed_now = false
        }
        @engine.Invoke(invocation) => {
          let old : @engine.Value? = match current {
            Some(binding) => Some(binding.value)
            None => default_scalar(e)
          }
          let descriptor = match extensions.lookup_cell_fn(invocation.name) {
            Some(descriptor) => descriptor
            None =>
              return Err(
                ladder_err(
                  e.name,
                  at_pos,
                  "unknown-vocab",
                  "cell fn '" + invocation.name + "' is not registered",
                  epath,
                ),
              )
          }
          let observes = match descriptor.concrete_observes(invocation) {
            Ok(observes) => observes
            Err((reason, message)) =>
              return Err(ladder_err(e.name, at_pos, reason, message, epath))
          }
          let ctx = @engine.fn_ctx_effect(e.name, e.name, old~, observes~)
          match descriptor.invoke(invocation.to_call(), ctx) {
            Err((reason, message)) =>
              return Err(ladder_err(e.name, at_pos, reason, message, epath))
            Ok(@engine.FnValue(value)) => {
              current = Some({
                ..b,
                op: @engine.Set,
                value,
                source: @engine.Cli,
              })
              committed_now = true
            }
            Ok(@engine.FnSentinel(@engine.UseDefault)) =>
              match
                resolve_ladder_below_cli(
                  e, env_map, config_obj, config_path, inherited, at_pos, epath,
                  tty_map, extensions,
                ) {
                Ok(defaults) => {
                  current = if defaults.length() > 0 {
                    Some({
                      ..b,
                      op: @engine.Set,
                      value: defaults[defaults.length() - 1].value,
                      source: @engine.Cli,
                    })
                  } else {
                    Some({ ..b, op: @engine.Default })
                  }
                  committed_now = true
                }
                Err(error) => return Err(error)
              }
            Ok(@engine.FnSentinel(@engine.Unset)) => {
              current = match default_scalar(e) {
                Some(value) =>
                  Some(@engine.mk_binding(e.name, value, @engine.Default))
                None => None
              }
              committed_now = false
            }
            Ok(@engine.FnSentinel(@engine.Empty)) => {
              current = Some({ ..b, op: @engine.Empty })
              committed_now = true
            }
          }
        }
        @engine.Remove | @engine.Splice =>
          // DR-080 §2: a `@engine.Remove`/`@engine.Splice` piece only ever fires for a `multiple` element whose
          // `accumulator` is `"merge"` — a merge accumulator REQUIRES `multiple` (DR-080 §1), so
          // no scalar (non-multiple) entity's CLI seat can ever carry one. Unreachable in
          // practice; `abort` matches the sibling accum branch's own defensive arm.
          abort(
            "unreachable: a @engine.Remove/@engine.Splice piece only fires for a multiple(merge) entity (DR-080 §1) — this is the scalar (non-multiple) fold",
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
  resolve_ladder_below_cli(
    e,
    env_map,
    config_obj,
    config_path,
    inherited,
    at_pos,
    epath,
    tty_map,
    extensions,
    include_default~,
  )
}

///|
/// DR-099 §4: tty_provider が 1 stream について返す生観測 2 値。null (= このマップにキーが無い) は
/// 「提供なし」(DR-098 §1 の規定を継承)。`fold = terminal || (tty_cygwin && cygwin)` — fold の計算
/// 自体は `resolve_ladder_below_cli` 側 (spec 側の純データ計算、provider には委ねない、DR-099 §1
/// 「採用しなかった案」参照)。
pub struct TtyObs {
  terminal : Bool
  cygwin : Bool
} derive(Eq, Debug)

///|
/// DR-081 §1 の「default 席書き換え」モデルの実装的正体: env/config/inherit/宣言 default という
/// CLI 未満のラダー段。CLI seat がフォールスルーした場合の通常経路であると同時に、`resolve_entity_
/// raw` の CLI seat 内で `@engine.Default` effect (`:default` variant) が発火した瞬間の **「その時点の
/// (書き換え済み) default 値」を問い合わせる関数としても再利用する** (DR-081 §2 "op=default は
/// 現在の default をそのままセルへ書く")。CLI seat の外に切り出したのは、両方の呼び手が全く同じ
/// 「env が勝てば env、なければ config、なければ inherit、なければ宣言 default (無ければ accum は
/// `[]` / scalar は absent)」という 1 本のラダーを必要とするため — 重複実装すると DR-081 が
/// 「複数席が供給する場合は従来のラダー優先順」と明記する優先順位 (env が最終的に勝つ) を 2 箇所で
/// 保守する羽目になる。
///
/// 返り値は素の `resolve_entity_raw` の戻り値と同型 (Array[@engine.Binding], 0 件 = absent 相当 / 1 件以上)。
/// `@engine.Default` effect の呼び手はこれをそのまま bindings として使う (scalar は高々 1 件、accum は
/// env/config の複数 piece もそのまま乗る — DR-081 §2 の accum 節 "書き換え済み default があれば
/// それ" が要求する挙動そのもの)。
fn resolve_ladder_below_cli(
  e : @engine.Entity,
  env_map : Map[String, String],
  config_obj : @engine.ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, @engine.Value],
  at_pos : Int,
  epath : Array[String],
  tty_map : Map[String, TtyObs],
  extensions : @engine.Registry,
  include_default? : Bool = true,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
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
              let bs : Array[@engine.Binding] = []
              for part in @engine.split_on(v, sep) {
                match
                  env_value(
                    e.name,
                    e.ty,
                    part,
                    e.piece_filters,
                    at_pos,
                    epath,
                    extensions,
                  ) {
                  Ok(parsed) =>
                    bs.push(@engine.mk_binding(e.name, parsed, @engine.Env))
                  Err(pe) => return Err(pe)
                }
              }
              return Ok(bs)
            }
            None =>
              match
                env_value(
                  e.name,
                  e.ty,
                  v,
                  e.piece_filters,
                  at_pos,
                  epath,
                  extensions,
                ) {
                Ok(parsed) =>
                  return Ok([@engine.mk_binding(e.name, parsed, @engine.Env)])
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
              @engine.CNull => ()
              // array → a multiple cell's pieces (DR-050 §4); each item typed per §4 — including
              // §4's string pipeline (issue 2026-07-09-config-string-pieceprocessor-gap), so a
              // string array item ALSO runs `e.piece_filters` before its type parse.
              @engine.CArr(items) =>
                if e.accum is Some(_) {
                  let bs : Array[@engine.Binding] = []
                  for it in items {
                    match
                      @builtins.config_to_value(
                        it,
                        e.ty,
                        e.piece_filters,
                        extensions,
                      ) {
                      Ok(v) =>
                        bs.push(@engine.mk_binding(e.name, v, @engine.Config))
                      Err((@engine.KFilter, reason, msg)) =>
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
              // `@builtins.config_to_value` が `e.piece_filters` を先頭で適用してから型 parse する — CLI/env の
              // pieceProcessor と同じ窓口。
              _ =>
                match
                  @builtins.config_to_value(
                    cv,
                    e.ty,
                    e.piece_filters,
                    extensions,
                  ) {
                  Ok(v) =>
                    return Ok([@engine.mk_binding(e.name, v, @engine.Config)])
                  Err((@engine.KFilter, reason, msg)) =>
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
      Some(v) => return Ok([@engine.mk_binding(e.name, v, @engine.Inherit)])
      None => ()
    }
  }
  // UX-Q7R: the caller first resolves only seats above default for every entity in the scope. A
  // second pass enables this tail only for the first entity whose export-key-resolved result cell is
  // still empty. CLI `:default` effects call this helper with the default enabled because the CLI
  // effect itself is an upper-seat claim; only ordinary fall-through uses the scope-level gate.
  if !include_default {
    return Ok([])
  }
  // Provider-backed preset resolution is descriptor dispatch: the type resident owns
  // the opaque provider key and JSON schema, while this ladder only transports the
  // selected observation. tty currently supplies `[terminal, cygwin]`; the resident owns
  // `terminal || (tty_cygwin && cygwin)` and the declared-default fallback.
  match e.ty.default_seat_observation_key() {
    Some(key) => {
      let observed : Json? = match tty_map.get(key) {
        Some(obs) =>
          Some([obs.terminal.to_json(), obs.cygwin.to_json()].to_json())
        None => None
      }
      let declared : @engine.Value? = if e.accum is None {
        match e.default_values {
          Some([value]) => Some(value)
          _ => None
        }
      } else {
        None
      }
      match e.ty.default_seat_resolver(@engine.seat_ctx(declared, observed~)) {
        Some(value) =>
          match
            @builtins.config_to_value(
              @engine.value_to_configval(value),
              e.ty,
              e.piece_filters,
              extensions,
            ) {
            Ok(resolved) =>
              return Ok([
                @engine.mk_binding(
                  e.name,
                  resolved,
                  if observed is Some(_) {
                    @engine.Tty
                  } else {
                    @engine.Default
                  },
                ),
              ])
            Err((@engine.KFilter, reason, msg)) =>
              return Err(filter_err(e.name, at_pos, reason, msg, epath))
            Err((_, reason, msg)) =>
              return Err(ladder_err(e.name, at_pos, reason, msg, epath))
          }
        None => ()
      }
    }
    None => ()
  }
  // default seat (DR-083 §1/§2, DR-102 §5): an accum cell's declared default supplies its WHOLE
  // array as already-split pieces, config-array precedent (DR-050 §4) — each piece routed through
  // `@builtins.config_to_value` (via `@engine.value_to_configval`) for the same T-domain / string-pipeline parse the
  // @engine.CArr config branch above uses. A scalar cell wants just the one value (`default_scalar`), but
  // DR-102 §5 (DR-050 §4 / DR-083 §2 の対称性から導出) extends the SAME type-dependent pipeline to
  // it — a JSON string default runs piece_filters → parse (`@builtins.config_to_value`'s `@engine.CStr` arm), a JSON
  // native (number/bool) default matching the element's type skips piece_filters/parse entirely
  // (the type's own consequence, `@builtins.config_to_value`'s `other => other` passthrough before its
  // `(cv, ty)` match). This is NOT a special case for defaults — it's the same "値源の種別でなく
  // 値の型が決める" rule DR-050 §4 already establishes, reused verbatim for the scalar default seat
  // too (mirrors the accum branch immediately above; both call sites now share one type-parse code
  // path with the config-array branch).
  if e.accum is Some(_) {
    match e.default_values {
      Some(vs) => {
        let bs : Array[@engine.Binding] = []
        for v in vs {
          match
            @builtins.config_to_value(
              @engine.value_to_configval(v),
              e.ty,
              e.piece_filters,
              extensions,
            ) {
            Ok(vv) => bs.push(@engine.mk_binding(e.name, vv, @engine.Default))
            Err((@engine.KFilter, reason, msg)) =>
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
      Some(v) =>
        match
          @builtins.config_to_value(
            @engine.value_to_configval(v),
            e.ty,
            e.piece_filters,
            extensions,
          ) {
          Ok(vv) => Ok([@engine.mk_binding(e.name, vv, @engine.Default)])
          Err((@engine.KFilter, reason, msg)) =>
            Err(filter_err(e.name, at_pos, reason, msg, epath))
          Err((_, reason, msg)) =>
            Err(ladder_err(e.name, at_pos, reason, msg, epath))
        }
      None => Ok([])
    }
  }
}

///|
fn config_path_of(e : @engine.Entity, path : Array[String]) -> Array[String] {
  match e.config_key {
    Some(k) => k
    None => {
      let p : Array[String] = []
      for s in path {
        p.push(s)
      }
      p.push(e.name)
      p
    }
  }
}

///|
fn default_fills_cell(e : @engine.Entity, bs : Array[@engine.Binding]) -> Bool {
  if bs.length() > 0 || e.accum is Some(_) {
    return true
  }
  default_scalar(e) is Some(_)
}

///|
priv struct DefaultClaimGroup {
  key : String
  claims : Array[Array[@engine.Binding]]
}

///|
fn entity_named(
  entities : Array[@engine.Entity],
  name : String,
) -> @engine.Entity? {
  for entity in entities {
    if entity.name == name {
      return Some(entity)
    }
  }
  None
}

///|
fn default_fn_option_edges(
  entity : @engine.Entity,
  extensions : @engine.Registry,
) -> Array[String] {
  let edges : Array[String] = []
  match entity.default_fn {
    Some(@engine.WireDefaultFn(invocation)) =>
      match extensions.lookup_cell_fn(invocation.name) {
        Some(descriptor) =>
          match descriptor.concrete_observes(invocation) {
            Ok(observes) =>
              for edge in observes {
                if edge.has_prefix("option:") {
                  edges.push(edge[7:].to_owned())
                }
              }
            Err(_) => ()
          }
        None => ()
      }
    _ => ()
  }
  edges
}

///|
fn append_default_order(
  entity : @engine.Entity,
  entities : Array[@engine.Entity],
  extensions : @engine.Registry,
  visiting : Array[String],
  done : Array[String],
  ordered : Array[@engine.Entity],
) -> Unit {
  if str_contains(done, entity.name) || str_contains(visiting, entity.name) {
    return
  }
  let next_visiting = visiting.copy()
  next_visiting.push(entity.name)
  for dependency in default_fn_option_edges(entity, extensions) {
    match entity_named(entities, dependency) {
      Some(source) =>
        append_default_order(
          source, entities, extensions, next_visiting, done, ordered,
        )
      None => ()
    }
  }
  if !str_contains(done, entity.name) {
    done.push(entity.name)
    ordered.push(entity)
  }
}

///|
fn default_order(
  entities : Array[@engine.Entity],
  extensions : @engine.Registry,
) -> Array[@engine.Entity] {
  let ordered : Array[@engine.Entity] = []
  let done : Array[String] = []
  for entity in entities {
    append_default_order(entity, entities, extensions, [], done, ordered)
  }
  ordered
}

///|
fn resolve_default_fn(
  entity : @engine.Entity,
  option_values : Map[String, @engine.Value],
  inherited : Map[String, @engine.Value],
  env_map : Map[String, String],
  at_pos : Int,
  epath : Array[String],
  extensions : @engine.Registry,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  let call = match entity.default_fn {
    Some(call) => call
    None => return Ok([])
  }
  let fn_call = call.to_call()
  let descriptor = match extensions.lookup_cell_fn(fn_call.name) {
    Some(descriptor) => descriptor
    None =>
      return Err(
        ladder_err(
          entity.name,
          at_pos,
          "unknown-vocab",
          "default_fn '" + fn_call.name + "' is not registered",
          epath,
        ),
      )
  }
  let observes = match call.wire_invocation() {
    Some(invocation) =>
      match descriptor.concrete_observes(invocation) {
        Ok(observes) => observes
        Err((reason, message)) =>
          return Err(ladder_err(entity.name, at_pos, reason, message, epath))
      }
    None => []
  }
  let ctx = @engine.fn_ctx_default(
    entity.name,
    old=option_values.get(entity.name),
    observes~,
    option=fn(name) { inherited.get(name) },
    dependency=Some(fn(name) { option_values.get(name) }),
    env=fn(variable) {
      match env_map.get(variable) {
        Some(value) => Some(@engine.VStr(value))
        None => None
      }
    },
  )
  match descriptor.invoke(fn_call, ctx) {
    Err(("absent-source", _)) => Ok([])
    Err((reason, message)) =>
      Err(ladder_err(entity.name, at_pos, reason, message, epath))
    Ok(@engine.FnSentinel(_)) =>
      Err(
        ladder_err(
          entity.name,
          at_pos,
          "invalid-range",
          "default_fn returned a sentinel in the default seat",
          epath,
        ),
      )
    Ok(@engine.FnValue(value)) =>
      match
        @builtins.config_to_value(
          @engine.value_to_configval(value),
          entity.ty,
          entity.piece_filters,
          extensions,
        ) {
        Ok(decoded) =>
          apply_entity_filters(
            entity,
            [@engine.mk_binding(entity.name, decoded, @engine.Default)],
            at_pos,
            epath,
            extensions,
          )
        Err((@engine.KFilter, reason, message)) =>
          Err(filter_err(entity.name, at_pos, reason, message, epath))
        Err((_, reason, message)) =>
          Err(ladder_err(entity.name, at_pos, reason, message, epath))
      }
  }
}

///|
fn default_claim_values_equal(
  left : Array[@engine.Binding],
  right : Array[@engine.Binding],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut i = 0
  while i < left.length() {
    if left[i].op != right[i].op || left[i].value != right[i].value {
      return false
    }
    i = i + 1
  }
  true
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
fn resolve_scope_config_with_export(
  sc : @engine.Scope,
  cli : Array[@engine.Binding],
  env_map : Map[String, String],
  provider : (String) -> @engine.ConfigVal?,
  path : Array[String],
  inherited : Map[String, @engine.Value],
  at_pos : Int,
  tty : Map[String, TtyObs],
  ek : Map[String, @engine.ExportKey],
  extensions : @engine.Registry,
  include_default : Bool,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
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
            @engine.Set => {
              cf_path = Some(@engine.value_str(b.value))
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
          Some(v) => cf_path = Some(@engine.value_str(v)) // committed stays false (default path)
          None => ()
        }
      }
    }
  }
  // Phase 2: read the provider. committed path + None = Error; default path + None = silent.
  let config_obj : @engine.ConfigVal? = match cf_path {
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
  // Phase 3a: resolve CLI/env/config/inherit for every entity before considering any default. These
  // seats are actual claims even when another entity already occupies the same exported result cell.
  let out : Array[@engine.Binding] = []
  let supplied : Array[String] = []
  let occupied : Array[String] = []
  let option_values : Map[String, @engine.Value] = Map([])
  for e in sc.entities {
    if !e.is_config_file {
      let cpath = config_path_of(e, path)
      match
        resolve_entity(
          e, cli, env_map, config_obj, cpath, inherited, at_pos, path, tty, extensions,
          false,
        ) {
        Ok(bs) =>
          if bs.length() > 0 {
            supplied.push(e.name)
            for b in bs {
              out.push(b)
              if b.op is @engine.Set {
                option_values.set(e.name, b.value)
              }
            }
            match exposed_key_of(e.name, ek) {
              Some(key) =>
                if !str_contains(occupied, key) {
                  occupied.push(key)
                }
              None => ()
            }
          }
        Err(pe) => return Err(pe)
      }
    }
  }
  if !include_default {
    // EXP-Q1: parse-time collision probing normally excludes defaults because they are fallbacks,
    // not claims. The sole exception is an otherwise-empty exported cell with multiple default
    // candidates whose resolved values differ: choosing the first by declaration order would make
    // the result order-dependent, so all candidates become collision claims. Equal values remain
    // observationally one fallback and contribute no claim (collision.json's defaults-only pin).
    let groups : Array[DefaultClaimGroup] = []
    for e in sc.entities {
      if !e.is_config_file && !str_contains(supplied, e.name) {
        match exposed_key_of(e.name, ek) {
          Some(key) if !str_contains(occupied, key) => {
            let cpath = config_path_of(e, path)
            match
              resolve_entity(
                e, cli, env_map, config_obj, cpath, inherited, at_pos, path, tty,
                extensions, true,
              ) {
              Ok(bs) =>
                if default_fills_cell(e, bs) && bs.length() > 0 {
                  let mut found = false
                  for group in groups {
                    if group.key == key {
                      group.claims.push(bs)
                      found = true
                      break
                    }
                  }
                  if !found {
                    groups.push({ key, claims: [bs] })
                  }
                }
              Err(pe) => return Err(pe)
            }
          }
          _ => ()
        }
      }
    }
    for group in groups {
      if group.claims.length() > 1 {
        let mut divergent = false
        let mut i = 1
        while i < group.claims.length() {
          if !default_claim_values_equal(group.claims[0], group.claims[i]) {
            divergent = true
            break
          }
          i = i + 1
        }
        if divergent {
          for claim in group.claims {
            for binding in claim {
              out.push(binding)
            }
          }
        }
      }
    }
    return Ok(out)
  }
  // Phase 3b: defaults are fallbacks for the export-key-resolved result cell, not per-entity claims.
  // Only the first default that can actually fill an empty cell is admitted; later co-exported
  // defaults see the occupied cell and do not run their value pipeline at all.
  for e in default_order(sc.entities, extensions) {
    if !e.is_config_file && !str_contains(supplied, e.name) {
      let exposed = exposed_key_of(e.name, ek)
      let cell_empty = match exposed {
        Some(key) => !str_contains(occupied, key)
        None => true
      }
      if cell_empty {
        let resolved = if e.default_fn is Some(_) {
          resolve_default_fn(
            e, option_values, inherited, env_map, at_pos, path, extensions,
          )
        } else {
          let cpath = config_path_of(e, path)
          resolve_entity(
            e, cli, env_map, config_obj, cpath, inherited, at_pos, path, tty, extensions,
            true,
          )
        }
        match resolved {
          Ok(bs) => {
            for b in bs {
              out.push(b)
              if b.op is @engine.Set {
                option_values.set(e.name, b.value)
              }
            }
            if default_fills_cell(e, bs) {
              match exposed {
                Some(key) =>
                  if !str_contains(occupied, key) {
                    occupied.push(key)
                  }
                None => ()
              }
            }
          }
          Err(pe) => return Err(pe)
        }
      }
    }
  }
  Ok(out)
}
