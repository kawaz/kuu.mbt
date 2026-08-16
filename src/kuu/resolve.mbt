// resolve.mbt — the value-resolution layer (MDR-002 §3): the value-source ladder (env / config /
// default seat fill, DR-031 / DR-049 / DR-050), the name-driven result builder (flat
// bindings → nested @abi.ResultValue, DR-016 / DR-025 / DR-043), export-key application (DR-052), and
// export-key collision detection (DR-073). node/value 依存のみ; eval からは経路確定後の後処理
// として呼ばれる (MDR-002 §3 table).
//
// Ported from slice `poc/result.mbt` (full file) and the value-ladder portion of slice
// `poc/installer.mbt` (`resolve_scope` / `resolve_scope_config` / `@extension.value_str` — NOT the lowering,
// which stays installer.mbt's job).
//
// `@extension.value_str` used to live in eval.mbt for the RequiresIf constraint comparison — this is its
// canonical home per the MDR-002 §3 module table; eval.mbt now calls this file's copy (single
// package, no import needed across files).
//
// DR-074/075 update over the slice: env's string→@abi.Value conversion goes through the canonical
// lexers (`@builtins.parse_number` / `parse_int_value` / `parse_bool`, value.mbt) instead of slice's
// `env_value` which silently fell back to `@abi.String(s)` on a parse failure — a badly-typed env value
// is now a DR-066 Error (reason `not_a_number` / `not_an_integer` / `not_a_bool`), never a
// wrong-typed cell. `resolve_scope` / `resolve_scope_config` return `Result[.., @abi.ParseError]`
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
  (k.length() > 0 && k[0:1].to_owned() == "#") ||
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
  orig : Array[@abi.Binding],
  resolved : Array[@abi.Binding],
) -> Array[@abi.Binding] {
  let out : Array[@abi.Binding] = []
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
fn has_direct_key(binds : Array[@abi.Binding], key : String) -> Bool {
  for b in binds {
    if b.scope.length() == 0 && b.key == key {
      return true
    }
  }
  false
}

///|
/// The bindings under a scope segment `seg`, with the first path element dropped.
fn sub_under(binds : Array[@abi.Binding], seg : String) -> Array[@abi.Binding] {
  let out : Array[@abi.Binding] = []
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
fn row_groups(binds : Array[@abi.Binding]) -> Array[Array[@abi.Binding]] {
  let mut from = 0
  let mut i = 0
  for b in binds {
    if b.scope.length() == 0 && b.key == "#fire" {
      from = i + 1
    }
    i = i + 1
  }
  let groups : Array[Array[@abi.Binding]] = []
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
fn fire_groups(binds : Array[@abi.Binding]) -> Array[Array[@abi.Binding]] {
  let groups : Array[Array[@abi.Binding]] = []
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
/// Index segments ("#k") among the direct children, ordered by k ascending. A link-routed fixed
/// tuple also carries its declared value-seat count on the direct `[]` marker; callers compare that
/// count with this coordinate-preserving index set before projecting an array.
fn ordered_indices(binds : Array[@abi.Binding]) -> Array[String] {
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
/// `bindings_through_link` writes a numeric `[]` marker only for fixed nameless tuples. Ordinary
/// seq/repeat array markers remain Bool(false), so their established projection is not cardinality-
/// gated. Multiple link writes may repeat the same marker; the declared arity is identical.
fn fixed_tuple_arity(binds : Array[@abi.Binding]) -> Int? {
  for binding in binds {
    if binding.scope.length() == 0 && binding.key == "[]" {
      match binding.value {
        @abi.Number(arity) => return Some(arity.to_int())
        _ => ()
      }
    }
  }
  None
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
///   - a value cell's key: @engine.Key(s) → s (override); @abi.Null → "" (nameless: kv 文脈で消え、seq/array
///     文脈では値が nameless 要素として残る); @abi.Unset → the name (unchanged).
///   - a scope label (command / name scope): @engine.Key(s) → s; @abi.Null → DROP the label (子が昇格露出);
///     @abi.Unset → unchanged. A "{}" presence marker whose only label was dropped floats to the root
///     scope where it is a harmless sentinel (a nameless command has no key — 子が昇格).
/// Sentinels ("[]" / "{}" / "" / "@act:" / "@depr:") and index segments ("#k") are not in the map
/// → kept.
fn apply_export_keys(
  binds : Array[@abi.Binding],
  ek : @engine.ExportScopeMap,
) -> Array[@abi.Binding] {
  let out : Array[@abi.Binding] = []
  for b in binds {
    let (new_scope, node) = walk_export_path(b.scope, ek, binds)
    let new_key = match node.exposed_cell(b.key) {
      Some(s) => s
      None => "" // nameless value axis
    }
    out.push({ ..b, key: new_key, scope: new_scope })
  }
  out
}

///|
/// 宣言名の path (binding の `scope` / DefaultCell・AccumCell の `path`) を露出キーの path へ写し、
/// 同時に着地した結果スコープのノードを返す。名前は**そのスコープの中でしか**意味を持たないので、
/// 末端の値セル名はここで返るノードから引く必要がある。
///
/// - ラベルが透過 (`export_key: null` / name 無し) なら segment を落とす — 子が親スコープへ昇格
///   する (DR-052 §2)。落ちるのは結果側の path だけで、宣言名の列は変わらないのでノードは進む
/// - `#k` index segment は結果スコープを作らない (配列添字) のでノードを進めずそのまま通す
fn command_ordinal_at_path(
  bindings : Array[@abi.Binding],
  path : Array[String],
) -> Int? {
  for binding in bindings {
    if binding.key == "{}" && path_eq(binding.scope, path) {
      match binding.value {
        @abi.Number(value) => return Some(value.to_int())
        _ => ()
      }
    }
  }
  None
}

///|
fn walk_export_path(
  path : Array[String],
  ek : @engine.ExportScopeMap,
  bindings : Array[@abi.Binding],
) -> (Array[String], @engine.ExportScopeMap) {
  let out : Array[String] = []
  let declaration_path : Array[String] = []
  let mut node = ek
  for seg in path {
    if seg.length() >= 1 && seg[0:1].to_owned() == "#" {
      out.push(seg)
    } else {
      declaration_path.push(seg)
      match command_ordinal_at_path(bindings, declaration_path) {
        Some(ordinal) => {
          match node.exposed_command_scope(seg, ordinal) {
            Some(s) => out.push(s)
            None => ()
          }
          node = node.command_child(seg, ordinal)
        }
        None => {
          match node.exposed_scope(seg) {
            Some(s) => out.push(s)
            None => ()
          }
          node = node.child(seg)
        }
      }
    }
  }
  (out, node)
}

///|
/// Apply the result-key axis (DR-052) to the injected default cells, mirroring apply_export_keys on
/// bindings: an @abi.Null cell is 透過 (dropped from the kv result), an @engine.Key renames it, and path
/// segments (command scope names) are renamed / promoted the same way. Keeps a flag's preset default
/// subject to the same export transform as its fired value (so `--verbose` with export null neither
/// appears as a value nor re-appears as an injected `false`).
/// `apply_export_to_defaults` の TypeSeat 版 — 宣言名軸で集めた「座の宣言 ValueType」台帳を
/// 露出キー軸へ写す (result / sources の record null 補形 (DR-130 §4.1) が露出軸で座を引くため)。
fn apply_export_to_types(
  types : Array[TypeSeat],
  ek : @engine.ExportScopeMap,
  bindings : Array[@abi.Binding],
) -> Array[TypeSeat] {
  let out : Array[TypeSeat] = []
  for t in types {
    let (new_path, node) = walk_export_path(t.path, ek, bindings)
    if !node.has_occupancy() || node.cell_is_occupied(t.name) {
      match node.exposed_cell(t.name) {
        None | Some("") => ()
        Some(new_name) =>
          out.push({
            path: new_path,
            name: new_name,
            value_type: t.value_type,
            is_accumulator: t.is_accumulator,
            default_value: t.default_value,
          })
      }
    } else if node.scope_is_occupied(t.name) {
      match node.exposed_scope(t.name) {
        None | Some("") => ()
        Some(new_name) =>
          out.push({
            path: new_path,
            name: new_name,
            value_type: t.value_type,
            is_accumulator: t.is_accumulator,
            default_value: t.default_value,
          })
      }
    }
  }
  out
}

///|
/// 露出軸台帳から (path, key) の座の宣言 ValueType を引く。
fn declared_cell_type(
  types : Array[TypeSeat],
  path : Array[String],
  key : String,
) -> @abi.ValueType? {
  for candidate in types {
    if candidate.name == key && path_eq(candidate.path, path) {
      return Some(candidate.value_type)
    }
  }
  None
}

///|
fn apply_export_to_defaults(
  defaults : Array[DefaultCell],
  ek : @engine.ExportScopeMap,
  bindings : Array[@abi.Binding],
) -> Array[DefaultCell] {
  let out : Array[DefaultCell] = []
  for d in defaults {
    let (new_path, node) = walk_export_path(d.path, ek, bindings)
    if !node.has_occupancy() || node.cell_is_occupied(d.name) {
      match node.exposed_cell(d.name) {
        None | Some("") => ()
        Some(new_name) =>
          out.push({ path: new_path, name: new_name, value: d.value })
      }
    } else if node.scope_is_occupied(d.name) {
      match node.exposed_scope(d.name) {
        None | Some("") => ()
        Some(new_name) =>
          out.push({ path: new_path, name: new_name, value: d.value })
      }
    }
  }
  out
}

///|
priv struct AccumCell {
  path : Array[String]
  name : String
  // DR-036 collector (@engine.Entity.collector's copy, threaded through so build_result — which only
  // sees AccumCell, never the @engine.Scope/@engine.Entity it came from — can apply it to the final accumulated
  // array without a second lookup pass). None = no collector (render the plain array).
  collector : &@extension.CollectorExt?
  // DR-009 段 7 / DR-102 §1 accum_filters (@engine.Entity.accum_filters's copy, issue
  // accum-post-filters-stage7): an accum cell's accum_filters is Acc→Acc (the WHOLE accumulated
  // array, the engine `ArrayFilterDescriptor` registry — DIFFERENT signature from a scalar
  // cell's final_filters, which `apply_entity_filters` already applies per-value T→T and never
  // reaches build_result at all). Applied BEFORE `collector` (DR-083 §2's literal order
  // "accumulator 畳み → accum_filters" has no collector step in it; the collector/accum_filters
  // interaction — issue's "未裁定の論点1" — stays open for whenever a fixture actually exercises
  // both on the same cell).
  accum_filters : Array[@abi.FnInvocation]
  // DR-084 §2 (issue multiple-ref-accum-gap): the accumulator KIND (@engine.Entity.accum's copy — always
  // `Some(_)` for a cell that reaches `accum_cells` at all, so this is a plain `String` here, not
  // `String?`). Pre-DR-105 this alone told apart a ref+repeat cell's "flatten" (non-`multiple`,
  // last-wins-WHOLE-CELL discard) from "append" (`multiple`, firing-boundary-preserving) — DR-105 §3
  // collapsed both onto the SAME name ("append"), so `is_multiple_decl` below (not this field) is
  // what `build_result`'s `segs` loop now reads for that distinction (both shapes still emit the
  // SAME "#fire"/"#row" sentinels, `inst_long`'s repeat-bearing ref branch is unchanged by DR-105).
  accum : &@extension.AccumulatorExt
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
/// 1 行 (`#row` 区切りの binding 群) の中で **席を持つ** accum セルだけに絞る。
///
/// `collect_accum` の structural-child 分岐は席を「その名前の binding が実在する runtime scope
/// path」から起こすが、粒度は scope path までで **行より粗い**。`multiple` wrapper の下の `or` では
/// 全ての行が同じ scope path を共有するので、ある行で選ばれた枝の binding が wrapper 全体に席を作り、
/// 別の枝を選んだ行にも UNIFORM ARRAY 注入で `[]` が生える (DR-051 / DR-122 §2: 未選択枝は成立
/// しなかった構造なので result にも sources にも席が無い)。行の binding 集合で席を起こし直すことで、
/// scope 粒度で既に成立している「席は binding の実在から起こす」原則を行粒度へそのまま延長する。
///
/// 絞るのは **この行の直下に住むセル** (`c.path == path`) だけ — より深い path のセルは行内の
/// 入れ子スコープを組み立てる再帰が自分の粒度で判断する。
fn row_seated_cells(
  cells : Array[AccumCell],
  path : Array[String],
  row : Array[@abi.Binding],
) -> Array[AccumCell] {
  let out : Array[AccumCell] = []
  for c in cells {
    if !path_eq(c.path, path) || row_seats_cell(row, c.name) {
      out.push(c)
    }
  }
  out
}

///|
/// 行の中にこのセルの席がある証拠 — 値 binding (`name`)、accum セルの席 marker
/// (`#accum:name`、`lowering.child_head` が反復子に打つ)、または入れ子スコープの segment。
fn row_seats_cell(row : Array[@abi.Binding], name : String) -> Bool {
  for b in row {
    if b.scope.length() == 0 {
      if b.key == name || b.key == "#accum:" + name {
        return true
      }
    } else if b.scope[0] == name {
      return true
    }
  }
  false
}

///|
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
) -> &@extension.CollectorExt? {
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
) -> Array[@abi.FnInvocation] {
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
) -> &@extension.AccumulatorExt? {
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
fn path_ends_with(path : Array[String], suffix : Array[String]) -> Bool {
  if suffix.length() > path.length() {
    return false
  }
  let offset = path.length() - suffix.length()
  let mut index = 0
  while index < suffix.length() {
    if path[offset + index] != suffix[index] {
      return false
    }
    index += 1
  }
  true
}

///|
fn link_binding_active(
  all : Array[@abi.Binding],
  binding : @abi.Binding,
) -> Bool {
  for selection in binding.link_selections {
    let mut selected = false
    for candidate in all {
      if candidate.key == selection.marker &&
        path_ends_with(candidate.scope, selection.scope) &&
        path_starts_with(binding.scope, candidate.scope) {
        selected = true
        break
      }
    }
    if !selected {
      return false
    }
  }
  true
}

///|
fn active_link_bindings(binds : Array[@abi.Binding]) -> Array[@abi.Binding] {
  let out : Array[@abi.Binding] = []
  for binding in binds {
    if link_binding_active(binds, binding) {
      out.push(binding)
    }
  }
  out
}

///|
fn projection_child(
  shape : @engine.ExportScopeMap?,
  key : String,
) -> @engine.ExportScopeMap? {
  match shape {
    Some(node) => node.projection_child(key)
    None => None
  }
}

///|
fn result_object_has_key(
  fields : Array[(String, @abi.ResultValue)],
  key : String,
) -> Bool {
  for field in fields {
    if field.0 == key {
      return true
    }
  }
  false
}

///|
/// Lift a cell value into the projection tree. A composite value (W2-3's `Array`/`Object`) becomes
/// the projection's own composite arms rather than staying inside a `Scalar`.
///
/// Design rationale: `Scalar(Object([...]))` and `Object([...])` would otherwise be two spellings of
/// the same JSON, and the choice is not free. DR-122 §1 requires `sources` to be a shadow tree of
/// the same shape as `result`, and DR-127 §6 requires a value_parser's composite to be decomposed
/// seat by seat rather than collapsed onto one leaf tag. Keeping the composite inside `Scalar` makes
/// both impossible at once, because `source_shadow`'s scalar arm has exactly one tag to give. So the
/// invariant is: after projection, no `Scalar` holds a composite. `Value` stays the type of one
/// cell's value and `ResultValue` stays the type of a projection-tree node (a scope's kv, a repeat
/// row, a source tag) — the wrapper is where a cell value enters the tree, which is why the two
/// types are not merged.
/// DR-130 §4.1 — record の補形は射影層で行い、parser の出力は書き換えない。宣言 ValueType を
/// 併走させて、record 座の宣言済み欠落フィールドを `null` で埋めた**新しい値**を作る (元の
/// Binding の値には触れない)。record は宣言 ValueType のどの深さに現れても対象 (array 要素 /
/// map 値 / union variant の中も再帰する)。`null` の中は埋めない (値が無い座に内側は無い)。
fn null_fill_value(
  value : @abi.Value,
  declared : @abi.ValueType?,
  registry : @extension.Registry,
) -> @abi.Value {
  match (declared, value) {
    (Some(@abi.ValueType::Record(fields)), @abi.Object(entries)) => {
      let out : Array[(String, @abi.Value)] = []
      for entry in entries {
        let mut field_declared : @abi.ValueType? = None
        for field in fields {
          if field.0 == entry.0 {
            field_declared = match registry.resolve_type_reference(field.1) {
              Some(resident) => resident.output_type()
              None => None
            }
            break
          }
        }
        out.push((entry.0, null_fill_value(entry.1, field_declared, registry)))
      }
      for field in fields {
        let mut present = false
        for entry in entries {
          if entry.0 == field.0 {
            present = true
            break
          }
        }
        if !present {
          out.push((field.0, @abi.Null))
        }
      }
      @abi.Object(out)
    }
    (Some(@abi.ValueType::Array(item)), @abi.Array(items)) =>
      @abi.Array(items.map(v => null_fill_value(v, Some(item), registry)))
    (Some(@abi.ValueType::Map(value_type)), @abi.Object(entries)) =>
      @abi.Object(
        entries.map(entry => {
          (entry.0, null_fill_value(entry.1, Some(value_type), registry))
        }),
      )
    // tuple 座も補形の通り道 (DR-130 §4.1) — 座の型が record 産出型なら座の内側の
    // 欠落フィールドまで補形が届く。座数は宣言アリティで固定 (DR-137 §2)。
    (Some(@abi.ValueType::Tuple(references)), @abi.Array(items)) => {
      let out : Array[@abi.Value] = []
      for index, item in items {
        let seat_declared : @abi.ValueType? = if index < references.length() {
          match registry.resolve_type_reference(references[index]) {
            Some(resident) => resident.output_type()
            None => None
          }
        } else {
          None
        }
        out.push(null_fill_value(item, seat_declared, registry))
      }
      @abi.Array(out)
    }
    (Some(@abi.ValueType::Union(members)), _) => {
      // 入れ子 union は葉集合へ平坦化して読む (DR-138 §1)。
      for variant_member in @fold.union_leaf_variants(members) {
        if @extension.value_conforms(value, variant_member, registry) {
          return null_fill_value(value, Some(variant_member), registry)
        }
      }
      value
    }
    _ => value
  }
}

///|
/// DR-130 §5 / DR-122 §1 — sources は result の shadow tree でキー集合が完全一致する。record の
/// null 補形 (DR-130 §4.1) は result 側だけで座を増やすので、射影の最後に result と zip して
/// 補形分の座を sources 側へ `null` として写す (補形で増えた座に産出発火は無い — タグではなく
/// null が正しい)。物理的に present な座のタグには触れない。
fn align_sources_to_result(
  result : @abi.ResultValue,
  shadow : @abi.ResultValue,
) -> @abi.ResultValue {
  match (result, shadow) {
    // DR-130 §5: result で null の座は sources でも null。物理的な書き (set(null) = unset) が
    // あっても同じ — 座に値が無い以上タグを付ける対象が無く、操作の provenance は effects 側が
    // 担う (DR-131 §2b の観測順序)。
    (@abi.Scalar(@abi.Null), _) => @abi.Scalar(@abi.Null)
    (@abi.Object(result_fields), @abi.Object(shadow_fields)) => {
      let out : Array[(String, @abi.ResultValue)] = []
      for field in result_fields {
        let mut matched : @abi.ResultValue? = None
        for candidate in shadow_fields {
          if candidate.0 == field.0 {
            matched = Some(candidate.1)
            break
          }
        }
        match matched {
          Some(nested) =>
            out.push((field.0, align_sources_to_result(field.1, nested)))
          None => out.push((field.0, @abi.Scalar(@abi.Null)))
        }
      }
      @abi.Object(out)
    }
    (@abi.Array(result_items), @abi.Array(shadow_items)) => {
      let out : Array[@abi.ResultValue] = []
      for index, item in result_items {
        if index < shadow_items.length() {
          out.push(align_sources_to_result(item, shadow_items[index]))
        } else {
          out.push(@abi.Scalar(@abi.Null))
        }
      }
      @abi.Array(out)
    }
    _ => shadow
  }
}

///|
fn result_of_value(value : @abi.Value) -> @abi.ResultValue {
  match value {
    @abi.Array(items) => @abi.Array(items.map(result_of_value))
    @abi.Object(entries) =>
      @abi.Object(entries.map(entry => (entry.0, result_of_value(entry.1))))
    _ => @abi.Scalar(value)
  }
}

///|
/// The provenance shadow of one cell value (DR-122 §3 / DR-127 §6): the value's own structure, with
/// the producing firing's tag at every seat. Per-seat re-tagging (a `link` partial write leaving its
/// siblings on the producer's tag) rides the same shape and lands with the value-space writes.
fn value_source_shadow(
  value : @abi.Value,
  source : @abi.Source,
) -> @abi.ResultValue {
  match value {
    @abi.Array(items) =>
      @abi.Array(items.map(item => value_source_shadow(item, source)))
    @abi.Object(entries) =>
      @abi.Object(
        entries.map(entry => (entry.0, value_source_shadow(entry.1, source))),
      )
    _ => source_tag(source)
  }
}

///|
/// 部分書き 1 件を provenance shadow へ写す (DR-127 §6 / DR-122 §3 の座単位 re-tag)。書き込み後の
/// 複合値 `value` の構造を mirror し、`path` (解決済み非負 index の segment 列) の座とその内側
/// だけを書いた発火の `source` で tag し直す。他の座は `prior` (直前までの shadow) のタグを保つ。
/// 今回の書きが vivify で作った中間器は path 上にしか現れないため、prior に対応の無い座が
/// path 外に出るのは構造変形 filter 等の防御ケースのみ — そこは書いた発火の tag へ落とす。
fn reshadow_at(
  value : @abi.Value,
  prior : @abi.ResultValue?,
  path : ArrayView[@abi.ObservationSegment],
  source : @abi.Source,
) -> @abi.ResultValue {
  match path {
    [] => value_source_shadow(value, source)
    [segment, .. rest] =>
      match (segment, value) {
        (@abi.ObservationName(field), @abi.Object(fields)) => {
          let prior_fields : Array[(String, @abi.ResultValue)] = match prior {
            Some(@abi.Object(entries)) => entries
            _ => []
          }
          let out : Array[(String, @abi.ResultValue)] = []
          for entry in fields {
            let mut prior_child : @abi.ResultValue? = None
            for candidate in prior_fields {
              if candidate.0 == entry.0 {
                prior_child = Some(candidate.1)
                break
              }
            }
            if entry.0 == field {
              out.push(
                (entry.0, reshadow_at(entry.1, prior_child, rest, source)),
              )
            } else {
              out.push(
                (
                  entry.0,
                  match prior_child {
                    Some(kept) => kept
                    None => value_source_shadow(entry.1, source)
                  },
                ),
              )
            }
          }
          @abi.Object(out)
        }
        (@abi.ObservationIndex(index), @abi.Array(items)) => {
          let prior_items : Array[@abi.ResultValue] = match prior {
            Some(@abi.Array(entries)) => entries
            _ => []
          }
          let out : Array[@abi.ResultValue] = []
          for offset in 0..<items.length() {
            let prior_child : @abi.ResultValue? = if offset <
              prior_items.length() {
              Some(prior_items[offset])
            } else {
              None
            }
            if offset == index {
              out.push(reshadow_at(items[offset], prior_child, rest, source))
            } else {
              out.push(
                match prior_child {
                  Some(kept) => kept
                  None => value_source_shadow(items[offset], source)
                },
              )
            }
          }
          @abi.Array(out)
        }
        // 書けた座と複合値の構造は一致する (set_at_declared 成功後にしか呼ばれない) — 防御。
        _ => value_source_shadow(value, source)
      }
  }
}

///|
/// filter (value_filters / final_filters) が carrier の複合値を変形した後の shadow 再整列
/// (DR-122 §1/§2 — sources は result と同型で、null は result null の座だけ)。変形後の値の
/// 構造を正として walk し、prior に同じ座があればそのタグを保ち、**filter が新たに作った
/// 非 null 座には当該 carrier の `source` を与える** (その座の値を確定させた主体は filter を
/// 走らせた発火 — DR-122 §3)。座が消えた分は値主導の walk で自然に落ちる。
fn realign_source_shadow(
  value : @abi.Value,
  prior : @abi.ResultValue,
  source : @abi.Source,
) -> @abi.ResultValue {
  match (value, prior) {
    (@abi.Object(fields), @abi.Object(prior_fields)) =>
      @abi.Object(
        fields.map(entry => {
          let mut prior_child : @abi.ResultValue? = None
          for candidate in prior_fields {
            if candidate.0 == entry.0 {
              prior_child = Some(candidate.1)
              break
            }
          }
          match prior_child {
            Some(kept) =>
              (entry.0, realign_source_shadow(entry.1, kept, source))
            None => (entry.0, value_source_shadow(entry.1, source))
          }
        }),
      )
    (@abi.Array(items), @abi.Array(prior_items)) => {
      let out : Array[@abi.ResultValue] = []
      for offset, item in items {
        if offset < prior_items.length() {
          out.push(realign_source_shadow(item, prior_items[offset], source))
        } else {
          out.push(value_source_shadow(item, source))
        }
      }
      @abi.Array(out)
    }
    // 構造の種類が変わった座 (scalar ⇄ composite) は変形後の値が正 — carrier source で張り直す。
    (@abi.Object(_) | @abi.Array(_), _) => value_source_shadow(value, source)
    // scalar 座は prior のタグを保つ (composite 由来の prior なら値主導で張り直す)。
    (_, @abi.Object(_) | @abi.Array(_)) => value_source_shadow(value, source)
    (_, kept) => kept
  }
}

///|
/// Build the nested result value from the winning flat bindings. `cells` locates every
/// accumulate cell by result path (so an empty cell still renders `[]`, DR-044 uniform array);
/// `path` is the current result-scope path. `shape` is the DR-120 declaration occupancy tree;
/// when present, every statically declared seat missing from this realized scope is completed
/// with `null` (DR-130 §1/§4).
fn build_result(
  binds : Array[@abi.Binding],
  cells : Array[AccumCell],
  defaults : Array[DefaultCell],
  path : Array[String],
  extensions? : @node.Registry = canonical_registry(),
  shape? : @engine.ExportScopeMap? = None,
  complete_static? : Bool = false,
  types? : Array[TypeSeat] = [],
) -> @abi.ResultValue {
  // ROW-GROUP (DR-078 §1 ref テンプレ result 写像, issue 2026-07-09-ref-template-result-shape):
  // a "#row" sentinel at this level (installer.mbt's `ref_row_head`) marks one repetition's row
  // boundary for a ref-template repeat cell — build one row (recursive build_result over that
  // row's own flat leaf bindings) per "#row"-delimited run。"#fire" (installer.mbt's `inst_long`,
  // option repeat only) marks the start of ONE firing's contribution; multiple 無しの再発火は
  // セル丸ごと上書きなので (DR-034 の axis 分離、last-wins-repeat-rows.json), only the bindings
  // AFTER THE LAST "#fire" survive — with no "#fire" at all (a positional fires its repeat
  // exactly once) the whole list is one firing.
  if has_direct_key(binds, "#row") {
    let rows : Array[@abi.ResultValue] = []
    for row in row_groups(binds) {
      rows.push(
        build_result(
          row,
          row_seated_cells(cells, path, row),
          defaults,
          path,
          extensions~,
          shape~,
          complete_static~,
          types~,
        ),
      )
    }
    return @abi.Array(rows)
  }
  // ARRAY: a "[]" sentinel at this level => build one element per "#k" child. Elements keep the
  // array's path (an indexed repeat element is not a named result-scope segment cells key on).
  if has_direct_key(binds, "[]") {
    let elems : Array[@abi.ResultValue] = []
    match fixed_tuple_arity(binds) {
      Some(arity) => {
        let indices = ordered_indices(binds)
        let compact = indices.length() > 0 &&
          seg_num(indices[indices.length() - 1]) >= arity
        for index in 0..<arity {
          let indexed = if compact && index < indices.length() {
            sub_under(binds, indices[index])
          } else {
            sub_under(binds, "#" + index.to_string())
          }
          if indexed.length() == 0 {
            elems.push(@abi.Scalar(@abi.Null))
          } else {
            elems.push(
              build_result(
                indexed,
                cells,
                defaults,
                path,
                extensions~,
                shape~,
                complete_static~,
                types~,
              ),
            )
          }
        }
      }
      None =>
        for idx in ordered_indices(binds) {
          elems.push(
            build_result(
              sub_under(binds, idx),
              cells,
              defaults,
              path,
              extensions~,
              shape~,
              complete_static~,
              types~,
            ),
          )
        }
    }
    return @abi.Array(elems)
  }
  // gather direct named keys (skip sentinels) and nested (named) scopes
  // DR-089 §3 / DR-050: 内部セル (none / config_file) の値は result に現れない — その binding は
  // 射影前に宣言名軸で落としてある (`drop_internal_bindings`) ので、ここには届かない。
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
    let mut v = @abi.Value::Bool(false)
    for b in binds {
      if b.scope.length() == 0 && b.key == "" {
        v = b.value
      }
    }
    return result_of_value(v)
  }
  // OBJECT: named leaves (folding accum keys into a list) + nested scopes.
  let obj : Array[(String, @abi.ResultValue)] = []
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
      // binding's `source` to `@abi.Default` before it reached here, so the tag comes out right without
      // a default-specific branch on the source side). `update` never reaches this match —
      // `installer.mbt`'s `collect_unsupported_accum_update` rejects a `multiple` element's
      // `update` variant at `parse_definition` time (static definition-error, not a runtime fold
      // check), so no @engine.Scope carrying this combination is ever built for `resolve`/`build_result`
      // to see.
      let mut vals : Array[@abi.Value] = []
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          match b.op {
            @abi.Empty | @abi.Unset | @abi.Default => vals = []
            _ => vals.push(b.value)
          }
        }
      }
      // DR-009 段 7 / DR-102 §1 accum_filters (issue accum-post-filters-stage7): Acc→Acc self-map
      // over the WHOLE folded array, BEFORE the collector (DR-083 §2's order — see
      // AccumCell.accum_filters' doc comment for why collector comes after, not before).
      // DR-105 §4: `@extension.apply_accum_filter_chain` returns Result (ARRAY filter registry can
      // reject, e.g. `length_range`) — the REJECT itself is surfaced earlier, at `resolve_entity`
      // time (`apply_entity_filters`'s own accum_filters gate, same `at_pos`/`epath` machinery
      // `final_filters` already uses), so a binding set that reaches `build_result` at all is
      // guaranteed to already satisfy this cell's accum_filters. The `Err` arm here is therefore
      // unreachable in practice — defensive fallback to the pre-filter array, same posture
      // `apply_collector`'s "unrecognized name — identity" fallback uses.
      let filtered_vals = match accum_filters_here(cells, path, k) {
        [] => vals
        chain =>
          match
            @extension.apply_accum_filter_chain(
              extensions.extensions(),
              chain,
              vals,
            ) {
            Ok(v) => v
            Err(_) => vals
          }
      }
      // DR-130 §4.1 の補形は accumulator の要素にも効く (要素 type が record を名乗る場合)。
      // accum_filters は生の値を見る (補形前)、collector と射影は補形後を見る。
      let filled_vals = match declared_cell_type(types, path, k) {
        Some(element_type) =>
          filtered_vals.map(v => {
            null_fill_value(v, Some(element_type), extensions.extensions())
          })
        None => filtered_vals
      }
      let accumulated = match accumulator_here(cells, path, k) {
        Some(resident) => resident.collect(filled_vals)
        None => abort("unreachable: an accumulated cell has no resident")
      }
      let collected = match collector_here(cells, path, k) {
        Some(resident) => resident.collect(accumulated)
        None => accumulated
      }
      obj.push((k, collected))
    } else {
      // SCALAR last-wins (DR-015): the last value written to the cell.
      let mut v = @abi.Value::Bool(false)
      for b in binds {
        if b.scope.length() == 0 && b.key == k {
          v = b.value
        }
      }
      // DR-130 §4.1: record 座の宣言済み欠落フィールドは射影層で null 補形する (値そのものは
      // 書き換えず、射影に入るこの点で埋めた新しい値を作る)。
      obj.push(
        (
          k,
          result_of_value(
            null_fill_value(
              v,
              declared_cell_type(types, path, k),
              extensions.extensions(),
            ),
          ),
        ),
      )
    }
  }
  for seg in segs {
    // issue 2026-07-09-accum-fold-update-default-ops 追記 (2026-07-10): a ref+repeat option cell
    // registered as an accum entity (`ensure_entity_body`'s Cell arm) that fired 0 times has
    // ONLY its "#fire" marker under `scope=[e.name]` (`inst_long`'s `@engine.Scoped(e.name, @engine.Bind("#fire",
    // ...))`) — no "#row" sentinel (`ref_row_head`) at all, since `@engine.GreedyRepeat` never ran. Its
    // `scope[0]` still lands in `segs` (any `scope.length()>0` binding does, sentinel or not), so
    // recursing here would build an EMPTY OBJECT `{}` from that lone "#fire" and push it — the
    // wrong shape (DR-044 §1 wants `[]` for a 0-fired accum cell, from the UNIFORM ARRAY injection
    // below, not an object built from a stray marker). Skip the recursion for this seg (defer
    // entirely to the injection below) when it names a THIS-path accum cell with no "#row" —
    // fired >=1 time (a real "#row" present) still recurses normally, unaffected.
    let seg_binds = sub_under(binds, seg)
    let child_shape = projection_child(shape, seg)
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
      // reachable manifestation of the dial in kuu.mbt today (`value.mbt`'s `@abi.Value` has no array
      // variant, so a plain scalar multiple cell's fire is never array-shaped — the dial is
      // observationally inert there, DR-105 §1's "非配列 → 丸ごと1要素" holds vacuously).
      let flat = flatten_here(cells, path, seg)
      let per_fire : Array[@abi.ResultValue] = []
      for chunk in fire_groups(seg_binds) {
        let rows : Array[@abi.ResultValue] = []
        for row in row_groups(chunk) {
          rows.push(
            build_result(
              row,
              cells,
              defaults,
              path_push(path, seg),
              extensions~,
              shape=child_shape,
              complete_static~,
              types~,
            ),
          )
        }
        if flat {
          for r in rows {
            per_fire.push(r)
          }
        } else {
          per_fire.push(@abi.Array(rows))
        }
      }
      let accumulated : @abi.ResultValue = @abi.Array(per_fire)
      let collected = match collector_here(cells, path, seg) {
        Some(resident) => resident.collect(accumulated)
        None => accumulated
      }
      obj.push((seg, collected))
    } else if !unfired_ref_accum_seg {
      let accumulated = build_result(
        sub_under(binds, seg),
        cells,
        defaults,
        path_push(path, seg),
        extensions~,
        shape=child_shape,
        complete_static~,
        types~,
      )
      let collected = if is_accum {
        match collector_here(cells, path, seg) {
          Some(resident) => resident.collect(accumulated)
          None => accumulated
        }
      } else {
        accumulated
      }
      obj.push((seg, collected))
    }
  }
  // UNIFORM ARRAY (DR-044 §1): an accumulate cell declared at THIS path that fired 0 times still
  // renders `[]` (not absent) — inject empties for cells not already present as named leaves.
  //
  // issue 2026-07-09-accum-fold-update-default-ops 追記 (2026-07-10, ref-repeat-sibling-trigger.json
  // mismatch の修正): a ref+repeat option cell (`ensure_entity_body`'s Cell arm now registers one
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
  //
  // 内部セル (config_file、DR-121 §2 / DR-050) はこの注入からも外れる — 値空間は持つが結果に
  // 現れない席なので 0 発火の `[]` も出してはいけない。席自体を作らないのが除外の実装で、
  // `push_accum_cell` が宣言名軸の entity identity で弾く (`collect_defaults` と同型)。
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
    if path_eq(d.path, path) &&
      !str_contains(named, d.name) &&
      !str_contains(segs, d.name) {
      let value = match d.value {
        Some(value) => value
        None => @abi.Null
      }
      obj.push((d.name, result_of_value(value)))
    }
  }
  // DR-130 §4: realized structural scopes/rows enumerate their statically declared seats. This
  // runs after bound values, accumulators, and defaults so a missing seat alone receives null;
  // an unselected branch's default is intentionally not evaluated.
  if complete_static {
    match shape {
      Some(node) =>
        for key in node.projection_keys() {
          if !result_object_has_key(obj, key) {
            obj.push((key, @abi.Scalar(@abi.Null)))
          }
        }
      None => ()
    }
  }
  @abi.Object(obj)
}

///|
fn accum_cells(
  sc : @engine.Scope,
  ek : @engine.ExportScopeMap,
  binds : Array[@abi.Binding],
) -> Array[AccumCell] {
  let out : Array[AccumCell] = []
  collect_accum(sc, [], [], ek, binds, out)
  out
}

///|
fn push_accum_cell(
  entity : @engine.Entity,
  path : Array[String],
  ek : @engine.ExportScopeMap,
  out : Array[AccumCell],
) -> Unit {
  // 内部セル (`none`) は結果に現れないので席も作らない — 作ると 0 発火の `[]` が注入される。
  // `collect_defaults` の同型ガードと揃える (除外は宣言名軸の entity identity で行う)。
  if entity.ty.name() == "none" {
    return
  }
  match entity.accum {
    Some(accum) =>
      match ek.exposed_cell(entity.name) {
        None => ()
        Some(name) =>
          out.push({
            path,
            name,
            collector: entity.collector,
            accum_filters: entity.accum_filters,
            accum,
            flatten: entity.flatten,
            is_multiple_decl: entity.is_multiple_decl,
          })
      }
    None => ()
  }
}

///|
/// `path` は **露出キー軸** (`exposed_scope` の rename / 透過昇格を適用済み) — AccumCell は
/// `build_result` が射影済み binding key と直接突き合わせる素材なので、`collect_defaults` と違い
/// ここで射影を済ませる。一方 `decl_path` は **宣言名軸** で、選択判定 (`@engine.scope_selected`)
/// 専用に並走させる — 判定が見る `{}` scope_marker の scope は `cont.mbt` KNest が宣言ラベルで
/// 積むので、露出キー軸の `path` で照会すると rename / 透過のある scope で判定が外れる。
fn collect_accum(
  sc : @engine.Scope,
  path : Array[String],
  decl_path : Array[String],
  ek : @engine.ExportScopeMap,
  binds : Array[@abi.Binding],
  out : Array[AccumCell],
) -> Unit {
  for e in sc.entities {
    // Root cells are collected only at the root declaration path. Structural children are materialized
    // at each runtime wrapper/index path below, never promoted to this scope merely because Entity is
    // stored in the enclosing engine Scope.
    if e.declaring_path.length() == 0 {
      push_accum_cell(e, path, ek, out)
    } else {
      let runtime_paths : Array[Array[String]] = []
      for binding in binds {
        if binding.scope.length() >= decl_path.length() &&
          path_eq(
            structural_declaring_path(binding.scope, decl_path),
            e.declaring_path,
          ) &&
          (binding.key == e.name || binding.key == "#accum:" + e.name) &&
          !contains_path(runtime_paths, binding.scope) {
          runtime_paths.push(binding.scope)
        }
      }
      for runtime_path in runtime_paths {
        let nested_ek = export_map_at_structural_path(
          ek, runtime_path, decl_path,
        )
        let exposed_path = exposed_structural_path(
          ek, runtime_path, decl_path, path,
        )
        push_accum_cell(e, exposed_path, nested_ek, out)
      }
    }
  }
  for g in sc.greedy {
    match g {
      @engine.CommandSatisfied(_, name, ordinal, child) => {
        // 未選択 (当該実行で未入場) の command scope は降りない — `collect_defaults` と同一の
        // gate (issue unselected-transparent-command-flag-leak)。DR-044 の「反復系は 0 回発火でも
        // `[]`」は **その cell が結果に現れる場合** の形の規定で、未選択 command 配下のセルは
        // そもそも結果に現れない (DR-051 absent) ので `[]` を出す前提が成立しない。
        //
        // 透過 (`export_key: null`) 側は `[]` が root に着地して result にも sources にも現れ
        // (両方に出るので対称に見えるが、値源を持たないセルの席なので absent 違反)、identity 側は
        // result には出ない一方 `result_sources` が `accum_cells` の席をそのまま `@abi.Default`
        // entry にするので **sources にだけ残る** (`{"path":["c"],"key":"tags"}`) — result から
        // 引けない由来 = DR-121 §2 違反。根は同じ「未選択スコープを無条件に降りる」。
        let child_decl = path_push(decl_path, name)
        if @engine.command_scope_selected(binds, child_decl, ordinal) {
          let child_ek = ek.command_child(name, ordinal)
          match ek.exposed_command_scope(name, ordinal) {
            // dropped label → children promote (DR-052 §2)
            None => collect_accum(child, path, child_decl, child_ek, binds, out)
            Some(s) =>
              collect_accum(
                child,
                path_push(path, s),
                child_decl,
                child_ek,
                binds,
                out,
              )
          }
        }
      }
      _ => ()
    }
  }
}

///|
/// 結果にも由来にも現れない **内部セル** の席 (宣言名軸で同定したもの)。ここに入るのは値セルを
/// 持たない構造マーカーだけ — `type: "none"` (DR-089 §3「none has no value」— 値空間が無いので
/// result にも sources にも出ない) と dd trigger (`DdSatisfied` / `DdMatchSatisfied` の element、
/// DR-093 §2/§7、engine 側で none 扱い)。`type: "config_file"` は string のパス値を自分のラダーで
/// 確定させる通常の値セル (DR-050 §1) なので内部セルではなく、他の値要素と同じ規則で射影される
/// (DR-135 §1)。結果に出したくない config_file は `export_key: null` か nameless で書く (DR-135 §5)。
///
/// **キー軸**: `path` / `name` とも **宣言名** (`@engine.NoneCell` / `@engine.Entity.name` の
/// ままの軸、binding の生の `scope` / `key` と同じ)。`effects` 側の除外
/// (`front_door.output_internal_cell`) と同一の軸で、内部セルの除外はすべてここに揃える。
///
/// **露出キー軸で同定してはいけない**: 内部セルは DR-120 §4 の「露出キーを占有しない要素」で、
/// 露出キー衝突検査に参加しない。したがって内部セルの露出キーは、同じスコープに実在する
/// 別セルの露出キーと合法に一致しうる (`{name:"cfg", type:"config_file", export_key:"user"}`
/// + `{name:"user", multiple:true}` は definition-error にならない)。露出キー軸の negative list
/// で照合すると、この構成で実セル `user` の値が result / sources から巻き添えで消える (実測)。
/// 宣言名はスコープ内で一意 (DR-006 / DR-003「重複ルール」) なので、宣言名軸なら同定が割れない。
priv struct InternalCell {
  path : Array[String]
  name : String
}

///|
/// 内部セルの席を **宣言名軸** で集める。`none` / dd trigger の席は `@engine.selected_none_cells`
/// がそのまま宣言名軸で返す。`binds` は解決済み binding — 未選択 command scope 配下へ降りない
/// ための選択判定に使う (`collect_defaults` と同じ gate)。
fn internal_cells(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  templates? : Map[String, @engine.Node] = Map([]),
) -> Array[InternalCell] {
  let out : Array[InternalCell] = []
  for cell in @engine.selected_none_cells(sc, templates, binds) {
    out.push({ path: cell.path(), name: cell.name() })
  }
  out
}

///|
/// 内部セルの binding を落とす — 射影 (`apply_export_keys`) の **前** に、宣言名軸で行う。
/// result / sources はこの後段だけを素材にするので、内部セルは射影側に一度も現れない。
fn drop_internal_bindings(
  binds : Array[@abi.Binding],
  cells : Array[InternalCell],
) -> Array[@abi.Binding] {
  if cells.length() == 0 {
    return binds
  }
  let out : Array[@abi.Binding] = []
  for b in binds {
    if !is_internal_cell(cells, b.scope, b.key) {
      out.push(b)
    }
  }
  out
}

///|
/// `internal_cells` の席と (path, name) が一致するか — 宣言名軸の照合。
///
/// 照合前に **index segment (`#k`) を落とす**。セルの席は「どのセルか」であって「配列の何番目の
/// 発火か」ではない — `repeat` 配下の同じセルは発火ごとに `grp/#0`, `grp/#1` … と別 path を
/// 持つが、席は `grp` の 1 つしかない (`@engine.none_cells` も `IndexedRepeat` のラベル段までしか
/// 積まない)。添字込みで比べると repeat 配下の内部セルが毎回除外を外れる。
fn is_internal_cell(
  cells : Array[InternalCell],
  path : Array[String],
  name : String,
) -> Bool {
  let seat = drop_index_segments(path)
  for c in cells {
    if c.name == name && path_eq(c.path, seat) {
      return true
    }
  }
  false
}

///|
/// 結果 path から index segment (`#k`、`walk_export_path` が結果スコープを作らないものとして
/// 素通しする配列添字) を除いた「席の path」。
fn drop_index_segments(path : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for seg in path {
    if !(seg.length() >= 1 && seg[0:1].to_owned() == "#") {
      out.push(seg)
    }
  }
  out
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
  value : @abi.Value?
}

///|
/// `binds` は **未射影** (`apply_export_keys` 前) の解決済み binding — `collect_defaults` の
/// 選択判定が `@engine.scope_selected` を使う以上、判定軸は engine と同じ **宣言名軸** で
/// なければならない (下記 `collect_defaults` のコメント参照)。
fn default_cells(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
) -> Array[DefaultCell] {
  let out : Array[DefaultCell] = []
  collect_defaults(sc, [], binds, out)
  out
}

///|
/// DR-083 §1: `@engine.Entity.default_values` is the uniform length-1-degenerate array (node.mbt's doc
/// comment) — every SCALAR-cell reader (a cell with `accum is None`, guaranteed length exactly 1
/// by `ensure_entity`'s only producer) wants just the one value. `resolve_ladder_below_cli`'s
/// default seat is the ONE reader that legitimately iterates the whole array (an accum cell's
/// default can carry N pieces) and does NOT use this helper.
fn default_scalar(e : @engine.Entity) -> @abi.Value? {
  match e.default_values {
    Some(vs) => if vs.length() > 0 { Some(vs[0]) } else { None }
    None => None
  }
}

///|
/// `path` は **宣言名軸** (`export_key` 適用前) で積む — 射影は呼び出し側の
/// `apply_export_to_defaults` が `walk_export_path` で後から行う。選択判定 (`scope_selected`) が
/// 見る `{}` scope_marker の scope も宣言名軸 (`cont.mbt` KNest が宣言ラベルで prepend する) なので、
/// 両者の軸が揃う。
fn collect_defaults(
  sc : @engine.Scope,
  path : Array[String],
  binds : Array[@abi.Binding],
  out : Array[DefaultCell],
) -> Unit {
  for e in sc.entities {
    if e.declaring_path.length() == 0 &&
      e.ty.name() != "none" &&
      e.accum is None {
      out.push({ path, name: e.name, value: default_scalar(e) })
    }
  }
  for g in sc.greedy {
    match g {
      @engine.CommandSatisfied(_, name, ordinal, child) => {
        // 未選択 (当該実行で未入場) の command scope は降りない (issue
        // unselected-transparent-command-flag-leak)。上の「flag は絶対 absent にならない」は
        // **選ばれた** scope の中の話 (DR-051 §2) で、選ばれなかった sibling command の配下は
        // 値源を一切持たないので absent が正。identity command なら path が `["c"]` に育って
        // 未選択スコープごと result から消えるため漏れは見えないが、透過 command (`export_key:
        // null`, DR-052 §2) は `apply_export_to_defaults` の `walk_export_path` が segment を
        // 落とすので **root に着地して露出**していた (`sources` は resolve 済み binding だけを
        // 見るので席を作らず、result と sources が非対称になる — DR-121 §2 違反)。
        //
        // 判定は engine の遅延述語 gate (`eval_all_constraints` / `violations_of`) と同じ
        // `@engine.scope_selected` を共用する (SCB-Q1=a と同じ「選択」の定義: `{}` scope_marker
        // の存在)。marker は `cont.mbt` KNest の `is_cmd=true` 分岐が **export_key に関係なく**
        // 宣言ラベルで prepend するので、透過 command でも選ばれていれば判定が通る (透過が
        // 落とすのは結果キー軸だけ、DR-052 §2)。
        let child_path = path_push(path, name)
        if @engine.command_scope_selected(binds, child_path, ordinal) {
          collect_defaults(child, child_path, binds, out)
        }
      }
      _ => ()
    }
  }
}

///|
fn projected_command_key_selected(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  declaration_path : Array[String],
  export_map : @engine.ExportScopeMap,
  key : String,
) -> Bool {
  for greedy in sc.greedy {
    match greedy {
      @engine.CommandSatisfied(_, name, ordinal, _) =>
        if export_map.exposed_command_scope(name, ordinal) == Some(key) &&
          @engine.command_scope_selected(
            binds,
            path_push(declaration_path, name),
            ordinal,
          ) {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
/// front_door 昇格 (issue 2026-07-16-result-projection-production-promotion、MDR-005「射程外」節
/// の解消、DR-109 §5 UX-Q5=a): `binds` → `result` オブジェクト (CONFORMANCE.md §2 の
/// `result: {...}`) を組み立てる 4 素材 (`apply_export_keys`/`accum_cells`/
/// `apply_export_to_defaults`/`internal_cells`) の合成をここに一本化する。runner の
/// `proj_result_export` (json_conformance_test.mbt) と kuu-cli PoC の手組み `result_to_json`
/// (wire.mbt) が同一の 5 行組み立てを重複実装していた — 両者ともこの関数を呼ぶ形に揃える。
/// `binds` は `front_door.resolve()` の @engine.Success payload (解決済み binds、DR-109 §7「CLI は既定で
/// resolve 適用」) を渡すのが前提だが、型としては素の `Array[@abi.Binding]` を受けるだけなので未解決の
/// CLI binds を渡しても動く (runner が「default ladder 不要な fixture は resolve をスキップする」
/// 最適化で未解決 binds をそのまま渡す既存経路があり、それを壊さないための性質 — 呼び出し側の
/// 資格を型で強制することはしない)。
/// DR-134 §3: 選択された value 持ち command の値セル (`#command_value`、その command 自身の scope の
/// 内部セル) が解決した binding。`None` = スコープを名乗る command、または未選択。
fn command_value_binding(
  binds : Array[@abi.Binding],
  child_declaration_path : Array[String],
) -> @abi.Binding? {
  for b in binds {
    if b.key == @engine.command_value_cell() &&
      path_eq(b.scope, child_declaration_path) &&
      b.op is @abi.Set {
      return Some(b)
    }
  }
  None
}

///|
/// DR-134 §3: 選択された value 持ち command は、親スコープのキーに**値そのもの**を座らせる (kv では
/// ない)。値を確定させた席のタグ (`value:` 由来なら const) はセルの binding からそのまま運ぶ
/// (DR-122 の shadow tree)。露出キーは command の scope キー軸で引く — `export_key` による改名は
/// スコープを名乗る command と同じ経路 (DR-134 §6)。
///
/// 出力は**露出キー軸**の binding なので、呼び手は `apply_export_keys` を通した列へ足す。
fn command_value_bindings(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  declaration_path : Array[String],
  result_path : Array[String],
  export_map : @engine.ExportScopeMap,
  out : Array[@abi.Binding],
) -> Unit {
  for greedy in sc.greedy {
    match greedy {
      @engine.CommandSatisfied(_, name, ordinal, child) => {
        let child_declaration_path = path_push(declaration_path, name)
        if !@engine.command_scope_selected(
            binds, child_declaration_path, ordinal,
          ) {
          continue
        }
        let exposed = export_map.exposed_command_scope(name, ordinal)
        match (command_value_binding(binds, child_declaration_path), exposed) {
          (Some(cell), Some(key)) =>
            out.push({
              ..cell,
              key,
              scope: result_path.copy(),
              source_shadow: None,
            })
          _ =>
            command_value_bindings(
              child,
              binds,
              child_declaration_path,
              match exposed {
                Some(key) => path_push(result_path, key)
                None => result_path
              },
              export_map.command_child(name, ordinal),
              out,
            )
        }
      }
      _ => ()
    }
  }
}

///|
/// DR-134 §3: 値を名乗った command の scope が結果へ寄与しないよう、その部分木の binding を落とす。
/// 消えるのは**結果への kv 射影**だけ (スコープ自体は消えず、非占有子は従来どおりそのスコープで
/// 働く) — 値持ち command の内側に占有子は居ない (§2 の definition-error) ので、落ちるのは
/// scope marker と内部セルだけである。宣言名軸で判定するので `apply_export_keys` の前に掛ける。
fn drop_value_command_subtrees(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
) -> Array[@abi.Binding] {
  let dropped : Array[Array[String]] = []
  collect_value_command_paths(sc, binds, [], dropped)
  if dropped.length() == 0 {
    return binds
  }
  let kept : Array[@abi.Binding] = []
  for b in binds {
    let mut under = false
    for p in dropped {
      if path_starts_with(b.scope, p) {
        under = true
        break
      }
    }
    if !under {
      kept.push(b)
    }
  }
  kept
}

///|
fn collect_value_command_paths(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  declaration_path : Array[String],
  out : Array[Array[String]],
) -> Unit {
  for greedy in sc.greedy {
    match greedy {
      @engine.CommandSatisfied(_, name, ordinal, child) => {
        let child_declaration_path = path_push(declaration_path, name)
        if !@engine.command_scope_selected(
            binds, child_declaration_path, ordinal,
          ) {
          continue
        }
        if command_value_binding(binds, child_declaration_path) is Some(_) {
          out.push(child_declaration_path)
        } else {
          collect_value_command_paths(child, binds, child_declaration_path, out)
        }
      }
      _ => ()
    }
  }
}

///|
fn command_projection_bindings(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  declaration_path : Array[String],
  result_path : Array[String],
  export_map : @engine.ExportScopeMap,
  out : Array[@abi.Binding],
) -> Unit {
  for greedy in sc.greedy {
    match greedy {
      @engine.CommandSatisfied(_, name, ordinal, child) => {
        let child_declaration_path = path_push(declaration_path, name)
        let child_export_map = export_map.command_child(name, ordinal)
        let exposed = export_map.exposed_command_scope(name, ordinal)
        if @engine.command_scope_selected(
            binds, child_declaration_path, ordinal,
          ) {
          // 値を名乗った command の内側は結果へ射影しない (DR-134 §3) — 親キーには
          // `command_value_bindings` が値そのものを置く。
          if command_value_binding(binds, child_declaration_path) is Some(_) {
            continue
          }
          let child_result_path = match exposed {
            Some(key) => path_push(result_path, key)
            None => result_path
          }
          command_projection_bindings(
            child, binds, child_declaration_path, child_result_path, child_export_map,
            out,
          )
        } else {
          match exposed {
            Some(key) =>
              if !projected_command_key_selected(
                  sc, binds, declaration_path, export_map, key,
                ) {
                out.push({
                  key,
                  op: @abi.Set,
                  value: @abi.Null,
                  source: @abi.Default,
                  scope: result_path.copy(),
                  link_selections: [],
                  observation: None,
                  source_shadow: None,
                  value_residual: [],
                  levels_to_declaring_scope: 0,
                  at_pos: None,
                })
              }
            None => ()
          }
        }
      }
      _ => ()
    }
  }
}

///|
fn build_result_export(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  ek : @engine.ExportScopeMap,
  extensions? : @node.Registry = canonical_registry(),
  templates? : Map[String, @engine.Node] = Map([]),
  complete_static? : Bool = true,
) -> @abi.ResultValue {
  let internal = internal_cells(sc, binds, templates~)
  let projected = apply_export_keys(
    active_link_bindings(
      drop_internal_bindings(drop_value_command_subtrees(sc, binds), internal),
    ),
    ek,
  )
  command_value_bindings(sc, binds, [], [], ek, projected)
  command_projection_bindings(sc, binds, [], [], ek, projected)
  let declared_types : Array[TypeSeat] = []
  collect_type_seats(sc, [], binds, declared_types)
  let types = apply_export_to_types(declared_types, ek, binds)
  build_result(
    projected,
    accum_cells(sc, ek, binds),
    apply_export_to_defaults(default_cells(sc, binds), ek, binds),
    [],
    extensions~,
    shape=Some(ek),
    complete_static~,
    types~,
  )
}

// ── result/sources の production 射影 ────────────────────────────────────────────────

///|
/// One exposed result seat and the bindings that survive the cell fold. The final `shadow` is built
/// through the accumulator/filter/collector provenance transformations before public projection.
priv struct SourceSeat {
  path : Array[String]
  key : String
  bindings : Array[@abi.Binding]
  mut shadow : @abi.ResultValue?
} derive(Debug)

///|
fn source_tag(source : @abi.Source) -> @abi.ResultValue {
  let tag = match source {
    @abi.Cli => "cli"
    @abi.Link => "link"
    @abi.Env => "env"
    @abi.Config => "config"
    @abi.Tty => "tty"
    @abi.Const => "const"
    @abi.Default => "default"
  }
  @abi.Scalar(@abi.String(tag))
}

///|
fn source_seat(
  seats : Array[SourceSeat],
  path : Array[String],
  key : String,
) -> SourceSeat? {
  for seat in seats {
    if seat.key == key && path_eq(seat.path, path) {
      return Some(seat)
    }
  }
  None
}

///|
fn accum_cell_at(
  cells : Array[AccumCell],
  path : Array[String],
  key : String,
) -> AccumCell? {
  for cell in cells {
    if cell.name == key && path_eq(cell.path, path) {
      return Some(cell)
    }
  }
  None
}

///|
fn source_index(path : Array[String]) -> Int? {
  for i = path.length() - 1; i >= 0; i = i - 1 {
    let segment = path[i]
    if segment.length() > 1 && segment[0:1].to_owned() == "#" {
      return Some(seg_num(segment))
    }
  }
  None
}

///|
fn indexed_source(
  seats : Array[SourceSeat],
  path : Array[String],
  key : String,
) -> @abi.Source? {
  let index = match source_index(path) {
    Some(value) => value
    None => return None
  }
  match source_seat(seats, drop_index_segments(path), key) {
    Some(seat) if index < seat.bindings.length() =>
      Some(seat.bindings[index].source)
    _ => None
  }
}

///|
fn source_default_here(
  defaults : Array[DefaultCell],
  path : Array[String],
  key : String,
) -> Bool {
  for cell in defaults {
    if cell.name == key && path_eq(cell.path, path) && cell.value is Some(_) {
      return true
    }
  }
  false
}

///|
fn source_seats(
  sc : @engine.Scope,
  resolved : Array[@abi.Binding],
  ek : @engine.ExportScopeMap,
  extensions : @node.Registry,
  templates : Map[String, @engine.Node],
) -> (Array[SourceSeat], Array[AccumCell], Array[DefaultCell]) {
  let seats : Array[SourceSeat] = []
  let cells = accum_cells(sc, ek, resolved)
  let internal = internal_cells(sc, resolved, templates~)
  let defaults = apply_export_to_defaults(
    default_cells(sc, resolved),
    ek,
    resolved,
  )
  // DR-134 §3: 値を名乗った command は親スコープのキーに値が座る — sources もその座のタグを
  // 持つ (DR-122 の shadow tree) ので、result と同じ射影を席の素材にも掛ける。
  let exposed = apply_export_keys(
    drop_internal_bindings(drop_value_command_subtrees(sc, resolved), internal),
    ek,
  )
  command_value_bindings(sc, resolved, [], [], ek, exposed)
  for binding in exposed {
    if binding.key != "" && is_sentinel(binding.key) {
      continue
    }
    let binding = match binding.op {
      @abi.Unset => { ..binding, source: @abi.Source::Default }
      _ => binding
    }
    let mut index = -1
    for i in 0..<seats.length() {
      if seats[i].key == binding.key && path_eq(seats[i].path, binding.scope) {
        index = i
        break
      }
    }
    let accumulated = cell_here(cells, binding.scope, binding.key)
    if index < 0 {
      let bindings : Array[@abi.Binding] = []
      if !(accumulated && binding.op is (@abi.Empty | @abi.Unset | @abi.Default)) {
        bindings.push(binding)
      }
      seats.push({
        path: binding.scope,
        key: binding.key,
        bindings,
        shadow: None,
      })
    } else if accumulated {
      match binding.op {
        @abi.Empty | @abi.Unset | @abi.Default => seats[index].bindings.clear()
        _ => seats[index].bindings.push(binding)
      }
    } else {
      seats[index].bindings.push(binding)
    }
  }
  for i in 0..<seats.length() {
    match accum_cell_at(cells, seats[i].path, seats[i].key) {
      Some(cell) => {
        let filtered = match
          @extension.apply_accum_filter_chain_with_sources(
            extensions.extensions(),
            cell.accum_filters,
            seats[i].bindings,
          ) {
          Ok(bindings) => bindings
          Err(error) => abort("source projection failed: " + error.message)
        }
        let values : Array[@abi.Value] = []
        let sourced : Array[(@abi.Value, @abi.Source)] = []
        for binding in filtered {
          values.push(binding.value)
          sourced.push((binding.value, binding.source))
        }
        let accumulated = cell.accum.collect(values)
        let accumulated_sources = cell.accum.collect_sources(sourced)
        seats[i].shadow = Some(
          match cell.collector {
            Some(collector) =>
              collector.collect_sources(accumulated, accumulated_sources)
            None => accumulated_sources
          },
        )
      }
      None => {
        guard seats[i].bindings.length() > 0 else {
          abort("source projection failed: scalar seat has no binding")
        }
        let winner = seats[i].bindings[seats[i].bindings.length() - 1]
        // DR-127 §6: 値残余の部分書きを畳んだ carrier は座単位の shadow を持ち込む — link で
        // 書いた座だけ link、他は産出発火のタグ。shadow の無い carrier は従来どおり単一 source。
        seats[i].shadow = Some(
          match winner.source_shadow {
            Some(shadow) => shadow
            None => value_source_shadow(winner.value, winner.source)
          },
        )
      }
    }
  }
  (seats, cells, defaults)
}

///|
fn direct_accum_source_shadow(
  cell : AccumCell,
  binds : Array[@abi.Binding],
  key : String,
  allow_empty : Bool,
  extensions : @node.Registry,
) -> @abi.ResultValue? {
  let direct : Array[@abi.Binding] = []
  for binding in binds {
    if binding.scope.length() == 0 && binding.key == key {
      match binding.op {
        @abi.Empty | @abi.Unset | @abi.Default => direct.clear()
        _ => direct.push(binding)
      }
    }
  }
  if direct.length() == 0 && !allow_empty {
    return None
  }
  let filtered = match
    @extension.apply_accum_filter_chain_with_sources(
      extensions.extensions(),
      cell.accum_filters,
      direct,
    ) {
    Ok(bindings) => bindings
    Err(error) => abort("source projection failed: " + error.message)
  }
  let values : Array[@abi.Value] = []
  let sourced : Array[(@abi.Value, @abi.Source)] = []
  for binding in filtered {
    values.push(binding.value)
    sourced.push((binding.value, binding.source))
  }
  let accumulated = cell.accum.collect(values)
  let shadow = cell.accum.collect_sources(sourced)
  Some(
    match cell.collector {
      Some(collector) => collector.collect_sources(accumulated, shadow)
      None => shadow
    },
  )
}

///|
/// Build DR-122's shadow tree by walking the completed result structure. Structural arrays and
/// scopes recurse through the same row/index grouping as `build_result`. Shape-changing collectors
/// receive the pre-collector value and source trees together so key promotion and tuple conversion
/// retain the provenance of the value seat that survives.
fn source_shadow(
  result : @abi.ResultValue,
  binds : Array[@abi.Binding],
  seats : Array[SourceSeat],
  cells : Array[AccumCell],
  defaults : Array[DefaultCell],
  extensions : @node.Registry,
  path : Array[String],
) -> @abi.ResultValue {
  // A nameless cell holding a composite value projects that value's own structure as this node
  // (build_result's nameless-seat arm), so the structural walk below would descend into seats that
  // no declaration stands behind and find no provenance for them. The seat already carries the
  // decomposed shadow; hand it over whole. Matching on the projected shape is what keeps this
  // precise — a nameless seat that build_result passed over (because named children occupy this
  // node) cannot match it.
  if !(result is @abi.Scalar(_)) {
    match source_seat(seats, path, "") {
      Some(seat) =>
        if seat.bindings.length() > 0 {
          let winner = seat.bindings[seat.bindings.length() - 1]
          if result_of_value(winner.value) == result {
            match seat.shadow {
              Some(shadow) => return shadow
              None => ()
            }
          }
        }
      None => ()
    }
  }
  match result {
    @abi.Object(fields) => {
      let out : Array[(String, @abi.ResultValue)] = []
      for field in fields {
        // A null result seat has no supplying subject. Check the completed result before consulting
        // global source seats, because another repeat row may have a binding for the same declaration.
        if field.1 is @abi.Scalar(@abi.Null) {
          out.push((field.0, @abi.Scalar(@abi.Null)))
          continue
        }
        // Accum source projection must use this recursive row's bindings before the global SourceSeat:
        // nested structural rows share one declaration path, while each row owns a different binding
        // slice. Root cells are equivalent here; if no direct slice exists, fall back to SourceSeat or
        // the collector-aware structural recursion below.
        let direct_accum = match accum_cell_at(cells, path, field.0) {
          Some(cell) =>
            direct_accum_source_shadow(
              cell,
              binds,
              field.0,
              match field.1 {
                @abi.Array([]) => true
                _ => false
              },
              extensions,
            )
          None => None
        }
        match direct_accum {
          Some(shadow) => out.push((field.0, shadow))
          None =>
            match source_seat(seats, path, field.0) {
              Some(seat) => {
                let shadow = seat.shadow.unwrap_or_else(() => {
                  abort("source projection failed: unfinished seat")
                })
                out.push((field.0, shadow))
              }
              None => {
                let child_binds = sub_under(binds, field.0)
                match accum_cell_at(cells, path, field.0) {
                  Some(cell) if cell.collector is Some(_) => {
                    let child_path = path_push(path, field.0)
                    let accumulated = build_result(
                      child_binds,
                      cells,
                      defaults,
                      child_path,
                      extensions~,
                    )
                    let accumulated_sources = source_shadow(
                      accumulated, child_binds, seats, cells, defaults, extensions,
                      child_path,
                    )
                    let collector = cell.collector.unwrap()
                    out.push(
                      (
                        field.0,
                        collector.collect_sources(
                          accumulated, accumulated_sources,
                        ),
                      ),
                    )
                  }
                  _ => {
                    let mut direct : @abi.Source? = None
                    for binding in binds {
                      if binding.scope.length() == 0 && binding.key == field.0 {
                        direct = Some(
                          match binding.op {
                            @abi.Unset => @abi.Source::Default
                            _ => binding.source
                          },
                        )
                      }
                    }
                    let source = match direct {
                      Some(value) => Some(value)
                      None => indexed_source(seats, path, field.0)
                    }
                    match source {
                      Some(value) => out.push((field.0, source_tag(value)))
                      None if source_default_here(defaults, path, field.0) =>
                        out.push((field.0, source_tag(@abi.Default)))
                      None => {
                        let nested = source_shadow(
                          field.1,
                          child_binds,
                          seats,
                          cells,
                          defaults,
                          extensions,
                          path_push(path, field.0),
                        )
                        out.push((field.0, nested))
                      }
                    }
                  }
                }
              }
            }
        }
      }
      @abi.Object(out)
    }
    @abi.Array(values) => {
      let out : Array[@abi.ResultValue] = []
      if has_direct_key(binds, "#row") {
        let rows = row_groups(binds)
        for i, value in values {
          let row = if i < rows.length() { rows[i] } else { [] }
          out.push(
            source_shadow(value, row, seats, cells, defaults, extensions, path),
          )
        }
      } else if has_direct_key(binds, "[]") {
        let indices = ordered_indices(binds)
        let arity = fixed_tuple_arity(binds)
        let compact = match arity {
          Some(count) =>
            indices.length() > 0 &&
            seg_num(indices[indices.length() - 1]) >= count
          None => false
        }
        for i, value in values {
          let child = match arity {
            Some(_) =>
              if compact && i < indices.length() {
                sub_under(binds, indices[i])
              } else {
                sub_under(binds, "#" + i.to_string())
              }
            None =>
              if i < indices.length() {
                sub_under(binds, indices[i])
              } else {
                []
              }
          }
          out.push(
            source_shadow(
              value, child, seats, cells, defaults, extensions, path,
            ),
          )
        }
      } else {
        for i, value in values {
          let index = "#" + i.to_string()
          out.push(
            source_shadow(
              value,
              sub_under(binds, index),
              seats,
              cells,
              defaults,
              extensions,
              path_push(path, index),
            ),
          )
        }
      }
      @abi.Array(out)
    }
    @abi.Scalar(@abi.Null) => @abi.Scalar(@abi.Null)
    @abi.Scalar(_) =>
      match source_seat(seats, path, "") {
        Some(seat) =>
          seat.shadow.unwrap_or_else(() => {
            abort("source projection failed: unfinished nameless seat")
          })
        None => {
          let mut source : @abi.Source? = None
          for binding in binds {
            if binding.scope.length() == 0 && binding.key == "" {
              source = Some(binding.source)
            }
          }
          match source {
            Some(value) => source_tag(value)
            None =>
              abort(
                "source projection failed: scalar result has no source seat at " +
                Debug::to_repr((path, binds, seats)).to_string(),
              )
          }
        }
      }
  }
}

///|
/// `sources` is the `result` shadow tree (DR-122): identical objects/arrays, with every scalar value
/// replaced by its final source tag. Empty arrays and objects remain empty because they have no value
/// seats to label.
fn result_sources(
  sc : @engine.Scope,
  resolved : Array[@abi.Binding],
  ek : @engine.ExportScopeMap,
  result : @abi.ResultValue,
  extensions : @node.Registry,
  templates? : Map[String, @engine.Node] = Map([]),
) -> @abi.ResultValue {
  let projected = apply_export_keys(
    drop_internal_bindings(resolved, internal_cells(sc, resolved, templates~)),
    ek,
  )
  let (seats, cells, defaults) = source_seats(
    sc, resolved, ek, extensions, templates,
  )
  source_shadow(result, projected, seats, cells, defaults, extensions, [])
}

///|
fn path_starts_with(path : Array[String], prefix : Array[String]) -> Bool {
  if path.length() < prefix.length() {
    return false
  }
  for i in 0..<prefix.length() {
    if path[i] != prefix[i] {
      return false
    }
  }
  true
}

// ── DR-047 §4/§5 (issue value-present-ladder-gap 裁定 2026-07-10、bool target 分は
// 2026-07-09 裁定): requires の後段 path filter ───────────────
//
// requires (Requires) / value 依存 requires (RequiresIf) の目的語の充足条件は「値源ラダー
// (env/config/default) 充填後の最終状態」で決まる — bool 型 (@builtins.flag_type()/@builtins.bool_type()) なら「解決後の
// 値が true であること」(値源不問)、非 bool なら「値の有無 (default 込み)」(DR-047 §5 表)。この
// 判定は値源ラダーが解ける後段でしか行えないため、KTop (eval.mbt, CLI 面のみで完結する完全経路
// 判定) では両方とも常に pass 扱いとしてスキップし (`is_bool_entity` が bool/非bool の分岐ゲート)、
// ここで `parse()` の @engine.Outcome を受け取って事後フィルタとして適用する — `promote_collision_ambiguous`
// (DR-073, 直上) と同じ「@engine.Outcome を受け取り @engine.Outcome を返す後処理」パターン。
//
// 非bool 分は元々 `value_present` (= committed OR has_default) として KTop で即時評価していたが、
// これは env/config 経由の供給を無視する実装ショートカットだった (DR-047 §4 の「値源ラダー
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
/// `@engine.RequiredCandidate` 1 件の最終判定 (型委譲、codex レビュー M-2 修正): `Required`/
/// `RequiredGroup` の resolve.mbt 側 (最終判定) 共有ヘルパー — `wrapper` が `None` なら宣言 scope
/// path そのもの (`@engine.is_committed`/`@engine.element_value`)、`Some(w)` なら宣言元要素 `w` 自身の @engine.Scoped 部分木内
/// (`@engine.is_committed_in_subtree`/`@engine.element_value_in_subtree`、eval.mbt 側の同名 subtree ヘルパーを resolve
/// 層でも再利用) で判定する。`is_none_entity` (値空間なし = committed 判定、値空間あり = 値の有無
/// 判定) のゲートは wrapper の有無と直交 — ref 経由の candidate は `@engine.Scope.entities` に登録されない
/// ため常に `is_none_entity` は `true` (committed 判定) に倒れる (`ensure_entity_body` の Cell
/// コメント参照、値空間はあるが entity が無いだけの縮退)。
fn candidate_satisfied(
  c : @engine.RequiredCandidate,
  entities : Array[@engine.Entity],
  bindings : Array[@abi.Binding],
  resolved : Array[@abi.Binding],
  path : Array[String],
) -> Bool {
  match c.wrapper {
    None =>
      if is_none_entity(entities, c.name) {
        @engine.is_committed(bindings, path, c.name)
      } else {
        @engine.element_value(resolved, path, c.name) != None
      }
    Some(w) =>
      if is_none_entity(entities, c.name) {
        @engine.is_committed_in_subtree(bindings, path, w, c.name)
      } else {
        @engine.element_value_in_subtree(resolved, path, w, c.name) != None
      }
  }
}

///|
/// One scope's `requires`/value 依存 requires violations, evaluated against a CANDIDATE path's
/// CLI-only bindings (trigger 判定、DR-047 §5 表「トリガ側 = committed」) AND the SAME candidate's
/// fully resolved bindings (目的語判定、「目的語側 = 値の有無/真理値」) — issue
/// resolve-first-constraint-pipeline (Phase 1) 裁定 2026-07-10: 目的語の充足判定は、もはやこの関数が
/// 自前のラダー (env/config) を再演するのではなく、呼び出し元が既に `resolve_scope_tree` で
/// 解決済みの `resolved` を渡してくるので `@engine.element_value` の単純参照で済む (値源不問は「resolve 済み
/// なら値源を意識する必要がない」という形で自然に成立する)。issue value-present-ladder-gap 裁定
/// 2026-07-10 でこの読者化を非bool 目的語にも拡張した — bool は `@engine.element_value(resolved,...) ==
/// Some("true")`、非bool は `@engine.element_value(resolved,...) != None` (値の有無) の 2 分岐。
///
/// `@engine.constraint_err`'s `path` defaults to `[]` (KTop's contract: a @abi.Held rides the cont chain and
/// scope boundaries prepend the path on the way out) — that mechanism doesn't run here (the path
/// is already fully resolved), so `sc.path` (DR-066 §4 result-nesting path) is threaded in
/// directly via struct-update.
fn constraint_pending_invoke(
  bindings : Array[@abi.Binding],
  path : Array[String],
  name : String,
) -> @abi.FnInvocation? {
  let mut pending : @abi.FnInvocation? = None
  for binding in bindings {
    if binding.key == name && path_eq(binding.scope, path) {
      pending = match binding.op {
        @abi.Invoke(invocation) => Some(invocation)
        _ => None
      }
    }
  }
  pending
}

///|
fn constraint_has_pending_invoke(
  bindings : Array[@abi.Binding],
  path : Array[String],
  name : String,
) -> Bool {
  constraint_pending_invoke(bindings, path, name) is Some(_)
}

///|
fn eval_requires(
  sc : @engine.ScopedCons,
  bindings : Array[@abi.Binding],
  resolved : Array[@abi.Binding],
  pos : Int,
) -> Array[@abi.ParseError] {
  let out : Array[@abi.ParseError] = []
  let path = sc.path
  // DR-093 §1/§3: 目的語の充足判定は型 (値空間) への委譲 — 値空間なし (none) は発火 (committed)、
  // bool は解決後値が true、それ以外 (通常の値空間あり型) は値の有無。none 分岐が先 (bool/非bool の
  // 判定は値空間があることが前提で、none には値そのものが無い)。
  let committed = fn(t : String) -> Bool {
    if is_none_entity(sc.entities, t) {
      @engine.is_committed(bindings, path, t)
    } else {
      match constraint_pending_invoke(bindings, path, t) {
        Some(invocation) if invocation.name == "unset" => false
        Some(_) => @engine.is_committed(resolved, path, t)
        None => @engine.is_committed(bindings, path, t)
      }
    }
  }
  let satisfied = fn(t : String) -> Bool {
    if is_none_entity(sc.entities, t) {
      @engine.is_committed(bindings, path, t)
    } else if is_bool_entity(sc.entities, t) {
      match @engine.element_value(resolved, path, t) {
        Some(value) => @engine.value_matches_literal(value, "true")
        None => false
      }
    } else {
      @engine.element_value(resolved, path, t) != None
    }
  }
  for c in sc.constraints {
    match c {
      // DR-136 裁定 4: committed 判定は entity 名軸、errors[].element は参照識別子軸。
      Requires(entity, element, targets) =>
        if committed(entity) {
          for t in targets {
            if !satisfied(t) {
              out.push({
                ..@abi.ParseError::constraint(
                  element,
                  "requires_violated",
                  "'\{element}' requires '\{t}'",
                  pos,
                ),
                path,
              })
            }
          }
        }
      RequiresIf(entity, branch_id, v, targets) => {
        let active = committed(entity) &&
          (match @engine.element_value(bindings, path, entity) {
            Some(x) => @engine.value_matches_literal(x, v)
            None => false
          })
        if active {
          for t in targets {
            if !satisfied(t) {
              out.push({
                ..@abi.ParseError::constraint(
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
      Conflicts(entity, element, targets) =>
        if committed(entity) {
          for target in targets {
            if (
                constraint_has_pending_invoke(bindings, path, entity) ||
                constraint_has_pending_invoke(bindings, path, target)
              ) &&
              committed(target) {
              out.push({
                ..@abi.ParseError::constraint(
                  element,
                  "conflicts_with_violated",
                  "'\{element}' conflicts with '\{target}'",
                  pos,
                ),
                path,
              })
            }
          }
        }
      Exclusive(group, members) => {
        let mut count = 0
        let mut pending = false
        for candidate in members {
          if constraint_has_pending_invoke(bindings, path, candidate) {
            pending = true
          }
          if committed(candidate) {
            count = count + 1
          }
        }
        if pending && count > 1 {
          out.push({
            ..@abi.ParseError::constraint(
              group,
              "exclusive_group_violated",
              "exclusive group '\{group}' allows at most one",
              pos,
            ),
            path,
          })
        }
      }
      Required(display, candidates) => {
        // DR-093 §1/§2: 自身の充足は型委譲。値空間なし (none) = 発火 (committed)、値空間あり =
        // 最終状態の値の有無 (default 込み、DR-047 §5 不変)。`satisfied` (上記 requires 目的語用) は
        // 再利用しない — bool の「解決後値 true」ルールは requires 目的語限定 (DR-047 §5 明確化) で
        // あり、required 自身の充足には持ち込まない (DESIGN §9.1 に bool 特例なし、bool は preset
        // default:false を常に持つため required 自身は「値の有無」で自明に充足する、それが spec の
        // 意図どおり)。
        //
        // issue 2026-07-13-structural-or-type-branch-required-missing /
        // codex-review-dr102-dr103-postland (M-2): `candidates` は structural or (直書き Or /
        // ref 経由) の場合、各枝の leaf name の配列 (node.mbt の `@engine.RequiredCandidate`/`Required`
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
            ..@abi.ParseError::constraint(
              display,
              "required_violated",
              "required '\{display}' is missing",
              pos,
            ),
            path,
          })
        }
      }
      RequiredGroup(group, members) => {
        // DR-103 §1/§7: member 充足は `Required` と完全に同一の型委譲 (値空間なし = committed、
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
            ..@abi.ParseError::constraint(
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
/// Whether `sc.greedy` enters a genuine command scope named `name` (a `@engine.CommandSatisfied` node) — used by
/// `resolve_scope_tree`'s pass-through below to tell a real child COMMAND scope apart from a
/// ref-template accum entity's own one-level-deeper binding wrap (`ref_row_head`/`@engine.Scoped(e.name,
/// ...)`, installer.mbt DR-078 §1). Only a `@engine.CommandSatisfied` name is a scope `resolve_scope_tree` should
/// recurse the ladder into; anything else sharing the same "one level deeper" shape is CLI-origin
/// material that must be passed through untouched instead.
fn is_cmdsat_child(sc : @engine.Scope, name : String) -> Bool {
  for g in sc.greedy {
    match g {
      @engine.CommandSatisfied(_, n, _, _) => if n == name { return true }
      _ => ()
    }
  }
  false
}

///|
/// Internal cells are definition-wide and rooted at the scope that declares their Entity. A linked
/// binding may be produced while resolving a descendant command; when recursion reaches the owning
/// scope, relocate the reserved key to that scope path.
fn relocate_internal_bindings(
  bindings : Array[@abi.Binding],
  entities : Array[@engine.Entity],
  path : Array[String],
) -> Array[@abi.Binding] {
  let out : Array[@abi.Binding] = []
  for binding in bindings {
    if binding.key.length() > 0 &&
      binding.key[0:1].to_owned() == "#" &&
      entity_named(entities, binding.key) is Some(_) {
      out.push({ ..binding, scope: path })
    } else {
      out.push(binding)
    }
  }
  out
}

///|
fn entities_at_declaring_path(
  entities : Array[@engine.Entity],
  declaring_path : Array[String],
) -> Array[@engine.Entity] {
  let out : Array[@engine.Entity] = []
  for entity in entities {
    if path_eq(entity.declaring_path, declaring_path) {
      out.push(entity)
    }
  }
  out
}

///|
fn scope_with_entities(
  scope : @engine.Scope,
  entities : Array[@engine.Entity],
) -> @engine.Scope {
  { ..scope, entities, }
}

///|
fn entities_contain_name(
  entities : Array[@engine.Entity],
  name : String,
) -> Bool {
  for entity in entities {
    if entity.name == name {
      return true
    }
  }
  false
}

///|
fn is_runtime_index_segment(segment : String) -> Bool {
  if segment.length() < 2 || segment[0:1].to_owned() != "#" {
    return false
  }
  let mut first = true
  for char in segment {
    if first {
      first = false
    } else if !(char >= '0' && char <= '9') {
      return false
    }
  }
  true
}

///|
/// Convert a runtime structural path (`xs/#0`) to the declaration path carried by Entity (`xs`).
/// Command scope segments are removed by the caller-provided base path; repeat indexes are runtime
/// instances and therefore do not participate in declaration ownership.
fn structural_declaring_path(
  runtime_path : Array[String],
  base_path : Array[String],
) -> Array[String] {
  let out : Array[String] = []
  let mut i = base_path.length()
  while i < runtime_path.length() {
    if !is_runtime_index_segment(runtime_path[i]) {
      out.push(runtime_path[i])
    }
    i = i + 1
  }
  out
}

///|
fn runtime_path_has_index(
  runtime_path : Array[String],
  base_path : Array[String],
) -> Bool {
  let mut i = base_path.length()
  while i < runtime_path.length() {
    if is_runtime_index_segment(runtime_path[i]) {
      return true
    }
    i = i + 1
  }
  false
}

///|
fn exposed_structural_path(
  root : @engine.ExportScopeMap,
  runtime_path : Array[String],
  base_path : Array[String],
  exposed_base : Array[String],
) -> Array[String] {
  let out = exposed_base.copy()
  let mut node = root
  let mut i = base_path.length()
  while i < runtime_path.length() {
    let segment = runtime_path[i]
    if is_runtime_index_segment(segment) {
      ()
    } else {
      match node.exposed_scope(segment) {
        Some(name) => out.push(name)
        None => ()
      }
      node = node.child(segment)
    }
    i = i + 1
  }
  out
}

///|
fn export_map_at_structural_path(
  root : @engine.ExportScopeMap,
  runtime_path : Array[String],
  base_path : Array[String],
) -> @engine.ExportScopeMap {
  let mut node = root
  let mut i = base_path.length()
  while i < runtime_path.length() {
    if !is_runtime_index_segment(runtime_path[i]) {
      node = node.child(runtime_path[i])
    }
    i = i + 1
  }
  node
}

///|
fn contains_path(
  paths : Array[Array[String]],
  candidate : Array[String],
) -> Bool {
  for path in paths {
    if path_eq(path, candidate) {
      return true
    }
  }
  false
}

///|
/// Resolve a WHOLE scope tree (root scope + every entered nested command scope) down the full
/// value-source ladder (`resolve_scope_config`), threading `outer_values` top-down so a child scope's
/// `borrow` default_fn always sees its ANCESTOR's already-resolved values (DR-087 §3 dependency
/// order — the parent must be fully resolved before the child's borrow lookup runs, never
/// reversed; DR-125 §4's lexical scope chain walks this map outward).
///
/// This is the production promotion of `json_conformance_test.mbt`'s `resolve_tree` (issue
/// resolve-first-constraint-pipeline, Phase 1): same recursive shape, generalized from the test
/// harness's `DCase`-specific `NoCfg`/`CfgObj`/`CfgFiles` dispatch to a plain `provider` closure
/// (`resolve_scope_config`'s own contract), so production callers — not just the conformance
/// harness — can resolve a whole tree, not just one scope. `apply_requires_filter` below is
/// the first such caller; `json_conformance_test.mbt`'s own `resolve_tree` is expected to become
/// a thin `dc.cfg`-to-`provider` adapter over this function (not duplicated here).
///
/// `binds` is the CLI-only raw bindings for ONE candidate path (`parse()`'s `@engine.Success`/`@engine.AmbiguousInterpretation`
/// payload) — not yet split by scope; this function filters to `path`'s own direct bindings at
/// each recursion level. The returned `Array[@abi.Binding]` is flat with every binding's `scope` tagged
/// to its owning path (the same shape `build_result`/`proj_sources_tree` already consume) — a
/// caller wanting a value at a nested path uses the ordinary `@engine.element_value`/`@engine.is_committed` lookups
/// with that path, no different from a single-scope `resolve_scope_config` caller.
fn resolve_scope_tree_with_export_impl(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  env_map : (String) -> String?,
  provider : (String) -> @abi.ConfigVal?,
  path : Array[String],
  outer_values : Map[String, @abi.Value],
  at_pos : Int,
  tty : (String) -> Bool?,
  ek : @engine.ExportScopeMap,
  extensions : @node.Registry,
  include_default : Bool,
  firings? : @fold.FiringLedger,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  let here : Array[@abi.Binding] = []
  for b in binds {
    if path_eq(b.scope, path) {
      here.push(b)
    }
  }
  let direct_entities = entities_at_declaring_path(sc.entities, [])
  let resolved = match
    resolve_scope_config_with_export(
      scope_with_entities(sc, direct_entities),
      here,
      env_map,
      provider,
      path,
      outer_values,
      at_pos,
      tty,
      ek,
      extensions,
      include_default,
      firings?,
    ) {
    Ok(rb) => rb
    Err(pe) => return Err(pe)
  }
  let out : Array[@abi.Binding] = []
  for b in here {
    if is_sentinel(b.key) {
      out.push(b)
    }
  }
  for b in resolved {
    out.push({ ..b, scope: path })
  }
  let child_outer_values : Map[String, @abi.Value] = Map([])
  for k, v in outer_values {
    child_outer_values.set(k, v)
  }
  for b in resolved {
    child_outer_values.set(b.key, b.value)
  }

  // Structural result scopes are instantiated by Scoped/IndexedRepeat rather than CommandSatisfied,
  // so they share the enclosing engine Scope while owning different ladder seats. Resolve each fired
  // runtime path with only the entities declared at its normalized structural path. A 0-fire wrapper
  // has no runtime path and therefore cannot materialize child defaults outside the wrapper.
  let structural_paths : Array[Array[String]] = []
  for b in binds {
    if b.scope.length() > path.length() {
      let declaring_path = structural_declaring_path(b.scope, path)
      if declaring_path.length() > 0 &&
        runtime_path_has_index(b.scope, path) &&
        entities_at_declaring_path(sc.entities, declaring_path).length() > 0 &&
        !contains_path(structural_paths, b.scope) {
        structural_paths.push(b.scope)
      }
    }
  }
  for runtime_path in structural_paths {
    let declaring_path = structural_declaring_path(runtime_path, path)
    let nested_entities = entities_at_declaring_path(
      sc.entities,
      declaring_path,
    )
    let nested_here : Array[@abi.Binding] = []
    for b in binds {
      if path_eq(b.scope, runtime_path) {
        nested_here.push(b)
      }
    }
    let nested_scope = scope_with_entities(sc, nested_entities)
    let nested_ek = export_map_at_structural_path(ek, runtime_path, path)
    let nested_resolved = match
      resolve_scope_config_with_export(
        nested_scope,
        nested_here,
        env_map,
        provider,
        runtime_path,
        child_outer_values,
        at_pos,
        tty,
        nested_ek,
        extensions,
        include_default,
        firings?,
      ) {
      Ok(rb) => rb
      Err(pe) => return Err(pe)
    }
    for b in nested_here {
      if is_sentinel(b.key) || !entities_contain_name(nested_entities, b.key) {
        out.push(b)
      }
    }
    for b in nested_resolved {
      out.push({ ..b, scope: runtime_path })
    }
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
  // template field has no individual env/config/default seat, DR-078 §1) — they are pure
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
        if !is_cmdsat_child(sc, next) &&
          !contains_path(structural_paths, b.scope) {
          out.push(b)
        }
      }
    }
  }
  for g in sc.greedy {
    match g {
      @engine.CommandSatisfied(_, name, ordinal, child) => {
        let childpath = path_push(path, name)
        if @engine.command_scope_selected(binds, childpath, ordinal) {
          match
            resolve_scope_tree_with_export(
              child,
              binds,
              env_map,
              provider,
              childpath,
              child_outer_values,
              at_pos,
              tty,
              ek.command_child(name, ordinal),
              extensions,
              include_default,
              firings?,
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
  Ok(relocate_internal_bindings(out, sc.entities, path))
}

///|
/// Structural child defaults are emitted by evaluation as sentinel bindings at the selected seat
/// occurrence. Resolve turns each occurrence into a real default binding in place, preserving or-branch
/// selection and repeated-row order without materializing seats from unselected declarations.
fn resolve_child_default_seats(
  sc : @engine.Scope,
  bindings : Array[@abi.Binding],
  env_map : (String) -> String?,
  provider : (String) -> @abi.ConfigVal?,
  outer_values : Map[String, @abi.Value],
  at_pos : Int,
  tty : (String) -> Bool?,
  ek : @engine.ExportScopeMap,
  extensions : @node.Registry,
  include_default : Bool,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  let prefix = "#seat:"
  let out : Array[@abi.Binding] = []
  for binding in bindings {
    if binding.key.length() >= prefix.length() &&
      binding.key[0:prefix.length()].to_owned() == prefix {
      let entities : Array[@engine.Entity] = []
      for entity in sc.entities {
        if entity.name == binding.key &&
          path_eq(entity.declaring_path, [binding.key]) {
          entities.push(entity)
        }
      }
      if entities.length() == 0 {
        out.push(binding)
        continue
      }
      // A `#seat:` binding's value is the target element name, built directly by lowering
      // (`Bind(child_default_seat_key(e), String(e.name))`) and never routed through a
      // `parse_token`, so it stays a String no matter what value shapes producers gain.
      let target = match binding.value {
        @abi.String(name) => name
        _ => ""
      }
      let resolved = match
        resolve_scope_config_with_export(
          scope_with_entities(sc, entities),
          [],
          env_map,
          provider,
          binding.scope,
          outer_values,
          at_pos,
          tty,
          ek,
          extensions,
          include_default,
        ) {
        Ok(values) => values
        Err(error) => return Err({ ..error, element: target })
      }
      for value in resolved {
        out.push({ ..value, key: target, scope: binding.scope })
      }
      let mut repeated = false
      for entity in entities {
        if entity.accum is Some(_) {
          repeated = true
        }
      }
      if repeated {
        out.push({ ..binding, key: "#accum:" + target, value: @abi.Bool(false) })
      }
    } else {
      out.push(binding)
    }
  }
  Ok(out)
}

///|
fn resolve_scope_tree_with_export(
  sc : @engine.Scope,
  binds : Array[@abi.Binding],
  env_map : (String) -> String?,
  provider : (String) -> @abi.ConfigVal?,
  path : Array[String],
  outer_values : Map[String, @abi.Value],
  at_pos : Int,
  tty : (String) -> Bool?,
  ek : @engine.ExportScopeMap,
  extensions : @node.Registry,
  include_default : Bool,
  firings? : @fold.FiringLedger,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  let bindings = match
    resolve_child_default_seats(
      sc, binds, env_map, provider, outer_values, at_pos, tty, ek, extensions, include_default,
    ) {
    Ok(values) => values
    Err(error) => return Err(error)
  }
  resolve_scope_tree_with_export_impl(
    sc,
    bindings,
    env_map,
    provider,
    path,
    outer_values,
    at_pos,
    tty,
    ek,
    extensions,
    include_default,
    firings?,
  )
}

///|
/// Apply the DR-047 §4/§5 requires path filter to a `parse()` @engine.Outcome (final_filters/accum_filters
/// と同じ側の後段処理、`promote_collision_ambiguous` と同型パターン — `parse()` 自体のシグネチャ・eval 層の
/// @engine.Ctx は無改修のまま、値源 (env/config) を後から与える)。bool 目的語 (真理値判定) と非bool
/// 目的語 (値の有無判定) の両方をここで扱う (issue value-present-ladder-gap 裁定 2026-07-10 で対象
/// 拡張、旧名 `apply_requires_filter` から改名)。生存経路数で outcome を再構成する: 0 →
/// `@engine.Failure` (violation を DR-053 §2 全保持で errors に、`fired_action`/`help_entry`/
/// `tried_triggers` は既存 KTop 発 @engine.Failure と同じ素材関数から構築 — 区別が付かない形にする、
/// DR-048 の「候補経路は dead end を含む」通り違反で落ちた経路の action も候補に数える)、1 → その
/// 経路で `@engine.Success`、2+ → 生存分だけの `@engine.Ambiguous`。`root`/`defs` は制約テーブル (`@engine.collect_scopes`)
/// と `@engine.find_help_entry`/`@engine.tried_triggers_of` の素材取得に使う。
///
/// issue resolve-first-constraint-pipeline (Phase 1、audit issue lazy-default-resolution-audit の
/// finding への根治): 候補ごとに `resolve_scope_tree` で実際に解決してから `@engine.element_value` を読むだけの
/// 「読者」に再設計した (以前の `resolved_bool_value_ladder` 自前ミニラダー + `config_obj:
/// @abi.ConfigVal?` 単一オブジェクト契約 + `collect_all_scopes` 祖先探索テーブルは全廃)。
/// `provider~` は `resolve_scope_config` と同じ `(String) -> @abi.ConfigVal?` 契約 — スコープごとに
/// 異なる config_file を動的に指す CfgFiles ケースも、呼び出し元が対応する provider を渡すだけで
/// 均一に扱われる (単一 @abi.ConfigVal だった旧契約の既知の残存ギャップが解消)。省略時は常に `None` を
/// 返す no-op provider (config 未使用の既存呼び出し元は無改修)。
///
/// `table.length() == 0` (このスコープ木に requires 制約が一つも無い) なら resolve を試みずに
/// 即座に `[]` を返す — 制約が無い定義で resolve コストを払わない、かつ無関係な entity の env/config
/// 解決エラーを不要に持ち込まない (両立できる速い経路)。
fn apply_requires_filter_with_export(
  o : @engine.Outcome,
  root : @engine.Node,
  defs : Map[String, @engine.Node],
  env : (String) -> String?,
  toks_len : Int,
  provider : (String) -> @abi.ConfigVal?,
  tty : (String) -> Bool?,
  ek : @engine.ExportScopeMap,
  extensions : @node.Registry,
  // DR-114 §6.1: parse_tree が配達した経路ごとの FiringRecord 台帳。候補経路の resolve も
  // record を消費して cell fn を再実行しない (経路の binds 構造等価で自分の ledger を引く)。
  firings? : @fold.FiringDeliveries,
) -> @engine.Outcome {
  let table = @engine.collect_scopes(root, defs)
  let violations_of = fn(
    binds : Array[@abi.Binding],
  ) -> Array[@abi.ParseError] {
    if table.length() == 0 {
      return []
    }
    let path_firings : @fold.FiringLedger? = match firings {
      Some(deliveries) => deliveries.ledger_for(binds)
      None => None
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
            firings?=path_firings,
          ) {
          Ok(resolved) => {
            let out : Array[@abi.ParseError] = []
            for sc2 in table {
              // SCB-Q1=a (kawaz 裁定 2026-07-17、docs/QUESTIONS.md の SCB batch): 未選択 (= 当該実行で
              // 未入場) command scope に宣言された遅延述語は評価に参加しない。原理は「グローバルオプション
              // 以外、サブコマンドは完全に別コマンドと見るべき」で、root scope (path=[]) は常に選択済み。
              // DR-103 §5 明確化 note が正本。engine 側 `eval_all_constraints` (KTop 相の粗判定) と同型
              // の gate をここ resolve 相 (後段の最終判定) にも掛ける — gate が 1 相にしか無いと未入場
              // child の RequiredGroup/Required が resolve 相で偽陽性を出し、KTop の Success を Failure
              // に落としてしまう (issue required-group-scope-participation、実測: `--r1` のみで
              // child-a scope の g が違反として付随、path=[child-a] の error 生成)。gate の判定は engine
              // 側と完全に同じ `@engine.scoped_constraints_selected` を共用 — raw path と同名 command
              // 宣言 ordinal の両方を `{}` scope_marker と照合し、非選択 sibling の述語を混ぜない。
              if !@engine.scoped_constraints_selected(binds, sc2) {
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
    binds_for_actions : Array[Array[@abi.Binding]],
    errors : Array[@abi.ParseError],
  ) -> @engine.Outcome {
    @engine.Failure({
      errors,
      fired_action: @engine.fired_action_of(binds_for_actions),
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
      let survivors : Array[@engine.AmbiguousInterpretation] = []
      let all_violations : Array[@abi.ParseError] = []
      let all_binds : Array[Array[@abi.Binding]] = []
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
/// A @abi.Value rendered as its comparison string (constraint value matching: integers print without
/// the trailing `.0`). The resolve layer owns the result-object rendering; this is also the
/// RequiresIf comparison form (moved here from eval.mbt, MDR-002 §3 table — this is resolve.mbt's
/// canonical home; eval.mbt's `@engine.element_value` calls this file's copy, same package).

///|
/// A DR-066 ladder-fill Error: `element`/`args_pos` locate it like any @abi.ParseError; `at_pos` is the
/// caller-supplied final position (env/config seat errors are not read at a token position — they
/// surface after the path completed, the same conceptual point `eval_constraints` evaluates at, so
/// callers thread the same final `toks.length()`). kind is always `@abi.Parse` (a value-source failed
/// to parse into the entity's type — the same category as a bad CLI token, DR-053). `epath` is the
/// DR-066 §4 ancestor path (root-first, [] = root 直下): this ladder walk resolves ONE scope's
/// entities at a time and already carries the scope's own result-nesting path (the `resolve_tree`
/// caller threads it in), so — unlike eval.mbt's CPS @abi.Held (which starts at [] and picks up ancestors
/// crossing scope boundaries on the way out) — the ladder path is known statically and passed in
/// directly, no boundary-crossing accumulation needed.
fn ladder_err(
  element : String,
  at_pos : Int,
  reason : String,
  message : String,
  epath : Array[String],
) -> @abi.ParseError {
  { element, args_pos: at_pos, kind: @abi.Parse, reason, message, path: epath }
}

///|
/// A DR-053 §2 filter-reject Error: `value_filters`/`final_filters`/`accum_filters` (DR-009 §7,
/// DR-102 §1) rejected an already-resolved value. Distinct from `ladder_err` (`kind: @abi.Parse`, a
/// value-source failed to parse) —
/// a filter reject is a validation/transform rejection over a value that parsed fine, so it gets
/// its own builder with `kind: @abi.Filter` (DR-053 §2's 3-way `parse` | `filter` | `constraint` split;
/// `eval.mbt`'s `filter_arg_eval` already emits `@abi.Filter` for the same conceptual failure at the
/// token-parsing layer, this is `apply_entity_filters`'s resolve-layer counterpart). Same
/// `at_pos`/`epath` threading contract as `ladder_err`.
fn filter_err(
  element : String,
  at_pos : Int,
  reason : String,
  message : String,
  epath : Array[String],
) -> @abi.ParseError {
  { element, args_pos: at_pos, kind: @abi.Filter, reason, message, path: epath }
}

///|
/// Parse an env string into a @abi.Value per the entity's type (DR-049 §2: env goes through the same
/// pipeline as CLI). Unlike slice's `env_value` (naive `@builtins.parse_number` with a silent `@abi.String` fallback
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
  ty : &@extension.TypeExt,
  s : String,
  piece_filters : Array[@abi.FnInvocation],
  at_pos : Int,
  epath : Array[String],
  extensions : @node.Registry,
) -> Result[@abi.Value, @abi.ParseError] {
  let s = match
    @extension.apply_piece_filters(extensions.extensions(), piece_filters, s) {
    Ok(v) => v
    Err({ reason, message: msg, .. }) =>
      return Err(filter_err(element, at_pos, reason, msg, epath))
  }
  match @extension.parse_token_checked(ty, s, extensions.extensions()) {
    Ok(value) => Ok(value)
    Err(fail) =>
      Err(
        ladder_err(element, at_pos, fail.reason, "env " + fail.message, epath),
      )
  }
}

///|
/// Navigate a config object by an absolute path (DR-050 §3). Each segment indexes into a @abi.Object;
/// a missing key or a non-object mid-path yields None (this cell is not supplied by config).
fn config_lookup(obj : @abi.ConfigVal, path : Array[String]) -> @abi.ConfigVal? {
  let mut cur = obj
  for seg in path {
    match cur {
      @abi.Object(kvs) => {
        let mut found : @abi.ConfigVal? = None
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
/// Resolve one entity down the fixed ladder: cli > env > config > default (DR-031 /
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
  cli : Array[@abi.Binding],
  env_map : (String) -> String?,
  config_obj : @abi.ConfigVal?,
  config_path : Array[String],
  at_pos : Int,
  epath : Array[String],
  tty_map : (String) -> Bool?,
  extensions : @node.Registry,
  include_default : Bool,
  firings? : @fold.FiringLedger,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  match
    resolve_entity_raw(
      e,
      cli,
      env_map,
      config_obj,
      config_path,
      at_pos,
      epath,
      tty_map,
      extensions,
      include_default,
      firings?,
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
/// resolved (any ladder seat: cli/env/config/default — DR-077 §1's whole point is that
/// `set` and `update` effects converge here indistinguishably). `value_filters` (each) applies to
/// every binding; `final_filters` (T→T、確定した最終値) applies ONLY to a scalar cell's (no accum)
/// single binding — an accum cell's TRUE "post accumulation" gate is `accum_filters`, applied at
/// build_result (resolve.mbt's caller) instead, which this function does not reach for that cell.
/// `@abi.Empty`'s binding carries a PLACEHOLDER value (DR-045 — the real "clear the collection" effect
/// has no value of its own), so it's exempt from both chains — running a number/string filter over
/// a bogus `@abi.Bool(false)` placeholder would be nonsensical.
fn apply_entity_filters(
  e : @engine.Entity,
  bs : Array[@abi.Binding],
  at_pos : Int,
  epath : Array[String],
  extensions : @node.Registry,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  let out : Array[@abi.Binding] = []
  for b in bs {
    // value_filters(each、段5) applies only to a binding carrying a REAL value (kawaz 裁定
    // 2026-07-09、issue accum-filters-non-set-op-semantics): `@abi.Set` (a plain value bind) and
    // `@engine.Update`'s applied result. The scalar CLI-seat fold (resolve_entity_raw's non-accum branch)
    // already converts a committed `@engine.Update` to a `@abi.Set` binding via `@engine.mk_binding` before it ever reaches
    // here, so this function never special-cases `@engine.Update` itself — checking `op == @abi.Set` alone
    // covers both. `@abi.Unset`/`@abi.Default`/`@abi.Empty` are operations ON THE CELL, not a piece carrying a
    // value — their bindings carry no meaningful operand (placeholder values, `mk_effect`'s doc
    // comment) and must pass through untouched. This generalizes the old "only `@abi.Empty` is exempt"
    // rule: for a SCALAR cell the fold above already collapses everything else to `@abi.Set`/`@abi.Empty`
    // so the two rules were equivalent there, but an ACCUM cell's fold (resolve_entity_raw's
    // `e.accum is Some(_)` branch) preserves every op UNINTERPRETED — without this
    // generalization, a `@abi.Default`/`@abi.Unset` binding's placeholder value would wrongly run through
    // `e.value_filters` (issue's `--ports 5 --reset-ports` repro).
    if b.op != @abi.Set {
      out.push(b)
    } else {
      match
        @extension.apply_filter_chain(
          extensions.extensions(),
          e.value_filters,
          b.value,
        ) {
        Err({ reason, message: msg, .. }) => {
          // value_filters(each、段5、DR-009): CONFORMANCE §3's piece-attribution rule — a reject here
          // is attributed to the SPECIFIC args token the rejected piece came from (`b.at_pos`,
          // issue 2026-07-09-accum-entity-filters-wiring), not the ladder's own `at_pos` (which
          // stays args.length — the "no specific token" fallback for env/config/default-
          // sourced bindings, where `b.at_pos` is always `None`).
          let pos = match b.at_pos {
            Some(p) => p
            None => at_pos
          }
          return Err(filter_err(e.name, pos, reason, msg, epath))
        }
        Ok(v) => {
          // 座単位 shadow を持つ carrier (DR-127 §6) は、filter の構造変形後に shadow を
          // 変形後の値と再整列する — 追加された非 null 座に align_sources_to_result が
          // null を置く (DR-122 §1/§2 違反) のを防ぐ。
          let shadow_after = fn(next : @abi.Value) -> @abi.ResultValue? {
            match b.source_shadow {
              Some(shadow) =>
                Some(realign_source_shadow(next, shadow, b.source))
              None => None
            }
          }
          let b2 = { ..b, value: v, source_shadow: shadow_after(v) }
          if e.accum is None {
            match
              @extension.apply_filter_chain(
                extensions.extensions(),
                e.final_filters,
                b2.value,
              ) {
              Err({ reason, message: msg, .. }) =>
                return Err(filter_err(e.name, at_pos, reason, msg, epath))
              Ok(v2) =>
                out.push({ ..b2, value: v2, source_shadow: shadow_after(v2) })
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
  // SAME fold `build_result`'s ACCUMULATE branch performs (@abi.Empty/@abi.Unset/@abi.Default clears the running
  // array, everything else appends its value) is replicated here so the two stay in lockstep.
  // `args.length()` attribution (DR-102 §4, effectuated by DR-105 §4): reuses `at_pos`, the same
  // "no specific token" position `final_filters`'s own reject above already reports at.
  if e.accum is Some(_) && e.accum_filters.length() > 0 {
    let mut vals : Array[@abi.Value] = []
    for b in out {
      match b.op {
        @abi.Empty | @abi.Unset | @abi.Default => vals = []
        _ => vals.push(b.value)
      }
    }
    match
      @extension.apply_accum_filter_chain(
        extensions.extensions(),
        e.accum_filters,
        vals,
      ) {
      Ok(_) => ()
      Err({ reason, message: msg, .. }) =>
        return Err(filter_err(e.name, at_pos, reason, msg, epath))
    }
  }
  Ok(out)
}

///|
/// The pre-DR-009-filters ladder resolution (cli > env > config > default) — unchanged
/// behavior from before this issue, just renamed so `resolve_entity` can wrap it with filter chain
/// application (`apply_entity_filters`) without duplicating the ladder logic.
fn resolve_entity_raw(
  e : @engine.Entity,
  cli : Array[@abi.Binding],
  env_map : (String) -> String?,
  config_obj : @abi.ConfigVal?,
  config_path : Array[String],
  at_pos : Int,
  epath : Array[String],
  tty_map : (String) -> Bool?,
  extensions : @node.Registry,
  include_default : Bool,
  firings? : @fold.FiringLedger,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  // cli seat (DR-015 last-wins + DR-077 §1 update fold): fold every same-name CLI effect in args
  // order, not just peek at the last one. `update`'s result is OLD-DEPENDENT — a single "read the
  // last binding" can no longer resolve the seat once update effects are mixed with
  // set/default/empty/unset (`-vvv` needs old=0→1→2, each rep depending on the ONE before it). For
  // every definition that never uses `update`, this fold degenerates to EXACTLY the prior "last
  // committed op wins" read (each non-update op still just replaces `current` outright, same as
  // before) — DR-015's last-wins guarantee (fixture multiple-parse/last-wins-scalar.json) is a
  // special case of this fold, not a different algorithm.
  // `current` holds the FULL binding (not just its value) — @abi.Set/@abi.Default/@abi.Empty must be returned
  // VERBATIM downstream (@abi.Empty's `value` is a placeholder that a later result-builder interprets
  // by `op`, not by `value`; @abi.Default's `source` must read `@abi.Default`, not `@abi.Cli`) exactly as the
  // pre-fold code did (`return Ok([b])` / `return Ok([@abi.Binding::new(e.name, v, @abi.Default)])`). Only `update`
  // needs the running VALUE (as `old`) — `.value` is read off `current` at that point, never
  // reconstructed from scratch.
  // accum セル (multiple/repeat, DR-034/043): the CLI seat must preserve EVERY same-name @abi.Binding,
  // not fold to "last wins" — build_result's ACCUMULATE branch (resolve.mbt's caller,
  // `@abi.Empty`/`@abi.Unset`/`@abi.Default` = clear-point, else = append) is the layer that interprets the op
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
  //   earlier (`@engine.classify_long_spelling`'s `@engine.Invalid`). The `@engine.Update` arm below is unreachable
  //   defensive code, not a live path.
  // - `default`: resets to `[]` (DR-051 §2's uniform-array default — an accum cell carries no
  //   declared default BY DESIGN, `AccumCell` has no such field) with committed=true (locks the
  //   ladder, mirrors scalar's `unset-ladder.json` default-commits-locked precedent). The op itself
  //   carries no operand, so there's no piece for value_filters/accum_filters to act on (DESIGN
  //   §8.3) — build_result's ACCUMULATE match folds `@abi.Default` exactly like `@abi.Empty`/`@abi.Unset` (a
  //   clear-point), so only the SOURCE TAG differs here: rewriting `source` to `@abi.Default` (mirrors
  //   scalar's `@abi.Binding::new(e.name, v, @abi.Default)`) keeps `proj_sources`/harness correct without a
  //   default-specific branch there.
  // - `unset`: stays uncommitted (committed=false, unchanged from before) — if every same-name CLI
  //   effect in this seat ends up uncommitted, the CLI seat falls through to the lower ladder rungs
  //   (env/config/default) below, exactly like the scalar branch already does
  //   (`unset-ladder.json`'s `unset-opens-ladder`) — this is the new `committed_now` gate replacing
  //   the old unconditional `bs.length() > 0` return.
  // DR-080 波及節: a merge-accumulator cell's CLI seat is NOT a per-binding fold — a "発火" is a
  // GROUP of same-`at_pos` @abi.Set/@abi.Remove/@abi.Splice pieces (one args token's separator-split), evaluated
  // together against the DR-080 §3 rule (old composition, remove/splice, implicit leading `@`).
  // That grouping cannot be expressed inside this function's per-binding `match b.op` loop (which
  // append/flatten's accumulators are correctly built around, one binding = one independent
  // effect) — factored into its own function.
  match e.accum {
    Some(resident) => {
      let normalized_cli : Array[@abi.Binding] = []
      for binding in cli {
        match binding.op {
          @abi.Invoke(invocation) if invocation.name == "unset" =>
            normalized_cli.push({ ..binding, op: @abi.Set, value: @abi.Null })
          _ => normalized_cli.push(binding)
        }
      }
      let lower : @extension.LowerSeat = fn(include_default_) {
        resolve_ladder_below_cli(
          e,
          env_map,
          config_obj,
          config_path,
          at_pos,
          epath,
          tty_map,
          extensions,
          include_default=include_default_,
        )
      }
      return resident.resolve_cli(
        e.name,
        normalized_cli,
        include_default,
        lower,
      )
    }
    None => ()
  }
  // 値状態 (`seats`) と、下流へ返す binding (`current`) は別物として持つ。前者は DR-114 §7 の
  // `ctx.old` を決め、後者は下流 (`build_result` / `proj_sources`) が op と source をそのまま
  // 読む carrier である。両者を 1 個の `current : Binding?` に兼ねさせない理由は実装上の
  // 不変条件で、`@abi.Default` の binding の `value` が **op で解釈される placeholder** であり
  // 値ではないこと (DR-045 が効果を `{op, operand?}` の純データと定めた帰結) — 兼ねさせると
  // placeholder が `old` として漏れる。値状態の遷移計算そのものは `cell_fold.mbt` の
  // `fold_seat_effect` が持ち、effects 射影 (`projected_effect`) と共有する。
  let mut current : @abi.Binding? = None
  let seats = @fold.CellSeats::new()
  // 座単位の provenance shadow (DR-127 §6 / DR-122 §3)。値残余の部分書きが起きた時だけ Some に
  // なり、carrier の `source_shadow` として下流 (`source_seats`) へ出る。全セル書きは従来どおり
  // last-winner (carrier の単一 `source` タグ) なので shadow を張らない (= None へ戻す)。
  let mut seat_shadow : @abi.ResultValue? = None
  let mut committed_now = false
  // DR-114 §6.1: parse 相 fold の実行記録 (FiringRecord) の出現順カーソル。record 対象 binding
  // (`records_firing`) をこのセルの効果列順にカウントし、対応する record を引く。
  let firing_cursor = @fold.FiringCursor::new()
  for b in cli {
    if b.key == e.name {
      let firing_record = firing_cursor.next(firings, b)
      // DR-080 §2: a `@abi.Remove`/`@abi.Splice` piece only ever fires for a `multiple` element
      // whose `accumulator` is `"merge"` — a merge accumulator REQUIRES `multiple` (DR-080 §1), so
      // no scalar (non-multiple) entity's CLI seat can ever carry one. Unreachable in practice;
      // `abort` matches the sibling accum branch's own defensive arm.
      if b.op is (@abi.Remove | @abi.Splice) {
        abort(
          "unreachable: a @abi.Remove/@abi.Splice piece only fires for a multiple(merge) entity (DR-080 §1) — this is the scalar (non-multiple) fold",
        )
      }
      // DR-127 §4.1 — 値空間残余の座への操作。共有 fold の座の中を segment 列で部分更新し、
      // 下流 carrier はセル全体の複合値で作り直す。裁定前の枝ローカル fold (DR-127 §4.2、
      // eval.mbt の branch_fold) が、経路解決の失敗 (Reject 位相) も fold 実行で判明した失敗
      // (Error 位相 = fn 未登録 / 実行失敗 / out 乖離) も枝ごと除外するので、勝ち残った解釈が
      // ここへ来る限り再発しない。本分岐は最終防衛線として同じ判定を保持する — CLI 以外の
      // 供給経路や fold の保守的スキップ (宣言を特定できない / 候補が食い違う形) がここへ
      // 届くため。
      if b.value_residual.length() > 0 {
        let registry = extensions.extensions()
        let declared = e.ty.output_type()
        let container_present = seats.value_at(e.name, []) is Ok(_)
        // re-tag の素材は書き込み前に取る: 部分書きは要素を増減しないが、prior shadow の基準は
        // 「この発火の前」の複合値であり、負 index の解決 (DR-127 §6) も発火時点の現在長で行う。
        let seat_before : @abi.Value? = if container_present {
          match seats.value_at(e.name, []) {
            Ok(seated) => Some(seated)
            Err(_) => None
          }
        } else {
          None
        }
        let residual_resolved = seats.resolved_residual(
          e.name,
          b.value_residual,
        )
        let residual_pos = match b.at_pos {
          Some(pos) => pos
          None => at_pos
        }
        // DR-114 §7 の ctx.old を座の現在値から供給する。record の宣言済み欠落座は論理 null
        // (DR-130 §4.1)、器そのものが無い座 (未 vivify) は absent。
        let old : @abi.Value? = if container_present {
          match
            seats.value_at_declared(
              e.name,
              b.value_residual,
              declared,
              registry,
            ) {
            Ok(value) => Some(value)
            Err(_) => None
          }
        } else {
          None
        }
        // DR-114 §6.1: parse 相 fold の実行記録があり、自席で計算した old と一致するなら fn を
        // 再実行しない (record の消費)。不一致 (parse/resolve に別の値源を渡した契約違反、または
        // ladder closure の縮退) は従来どおり再実行する — 未供給・不整合経路の現行挙動を
        // この値比較 gate が構造的に保つ。
        let (transition, old_consulted) = match firing_record {
          Some(record) if record.old_used == old =>
            (record.transition, record.old_consulted)
          _ => @fold.fold_seat_effect(b, old, e.name, extensions.extensions())
        }
        match transition {
          @fold.NoChange => ()
          @fold.FnMissing(name) =>
            return Err(
              ladder_err(
                e.name,
                residual_pos,
                "unknown-vocab",
                "cell fn '" + name + "' is not registered",
                epath,
              ),
            )
          @fold.FnFailed({ reason, message, .. }) =>
            return Err(ladder_err(e.name, residual_pos, reason, message, epath))
          // DR-127 §4.1 / DR-131 §7: Sentinel 返し (default / empty) と op=default/empty の
          // 値残余座への適用は発火時 Reject。座は退化セル — set と Value 返し fn だけを受ける。
          @fold.ToDefault | @fold.ToEmpty =>
            return Err(
              ladder_err(
                e.name,
                residual_pos,
                "invalid-range",
                "a sentinel operation cannot apply to a value-space seat of '" +
                e.name +
                "' (DR-127 §4.1: the seat accepts set and Value-returning fns only)",
                epath,
              ),
            )
          @fold.ToValue(value) => {
            // DR-127 §3: 空の座 (未 vivify) で `ctx.old()` を読んだ Value fn は、戻り値に
            // 依らず解決失敗 — 「ctx.old を要する fn」の判定は参照事実であって、返した値が
            // 偶然 null (成立形と同綴り) でも Reject の理由は消えない。
            if !container_present && old_consulted {
              return Err(
                ladder_err(
                  e.name,
                  residual_pos,
                  "invalid-range",
                  "a Value fn that reads ctx.old cannot apply to an empty value-space seat of '" +
                  e.name +
                  "' (DR-127 §3)",
                  epath,
                ),
              )
            }
            // DR-127 §3.2: 座に座る値の宣言適合は値を運んだ経路で変わらない — fn 戻り値も
            // set の operand も、フィールド type の out への適合検査を通る。main entry の
            // operand はフィールド type のパーサを通過済みで恒真だが、`:set:VALUE` variant の
            // dsl literal は entry 自身の型で decode されるため、ここが唯一の防衛線になる。
            if !(value is @abi.Null) {
              match
                @fold.residual_terminal_out(
                  declared,
                  b.value_residual,
                  registry,
                ) {
                Some(out) => {
                  let producer = match b.op {
                    @abi.Invoke(invocation) => invocation.name
                    _ => "set"
                  }
                  match
                    @extension.seat_fn_output_breach(
                      value, out, producer, registry,
                    ) {
                    Some((reason, message)) =>
                      return Err(
                        ladder_err(e.name, residual_pos, reason, message, epath),
                      )
                    None => ()
                  }
                }
                None => ()
              }
            }
            if value is @abi.Null && !container_present {
              // DR-131 §7: `unset` (null 返し) は ctx.old を要さず空座でも成立する。座は
              // 論理 null のまま (DR-130 §4.1)、器は作らない (vivify は set 専用、DR-127 §3)
              // — セルは未 commit のままラダーへ落ちる。
              ()
            } else {
              match
                seats.set_at_declared(
                  e.name,
                  b.value_residual,
                  value,
                  declared,
                  registry,
                  // DR-127 §3: vivify (器 `{}` の生成) は set (部分書き) 専用の op gate。
                  vivify=b.op is @abi.Set,
                ) {
                Ok(_) => {
                  committed_now = true
                  let composite = match seats.value_at(e.name, []) {
                    Ok(current_value) => current_value
                    Err(_) =>
                      abort(
                        "unreachable: set_at_declared succeeded so the seat holds a value",
                      )
                  }
                  // DR-127 §6: 部分書きした座だけを本発火の source (link 等) で re-tag し、
                  // 他の座は産出発火のタグ (prior shadow、無ければ直前 carrier の source で
                  // 起こした shadow) を保つ。
                  let placed = match residual_resolved {
                    Some(resolved) => resolved
                    None => b.value_residual
                  }
                  let prior : @abi.ResultValue = match seat_shadow {
                    Some(shadow) => shadow
                    None => {
                      let base_source = match current {
                        Some(previous) => previous.source
                        None => b.source
                      }
                      match seat_before {
                        Some(seated) => value_source_shadow(seated, base_source)
                        None => value_source_shadow(composite, b.source)
                      }
                    }
                  }
                  seat_shadow = Some(
                    reshadow_at(composite, Some(prior), placed[:], b.source),
                  )
                  current = Some({
                    ..b,
                    op: @abi.Set,
                    value: composite,
                    value_residual: [],
                    source_shadow: seat_shadow,
                  })
                }
                Err(fault) => {
                  // ctx.old を読んだ fn の空座適用はこの上の早期 Reject が既に受けている。
                  let hint = if !container_present {
                    " (the seat's container is absent and vivify is set-only — DR-127 §3)"
                  } else {
                    ""
                  }
                  return Err(
                    ladder_err(
                      e.name,
                      residual_pos,
                      "invalid-range",
                      "the value-space seat of '" +
                      e.name +
                      "' did not resolve: " +
                      @fold.seat_fault_message(fault) +
                      hint,
                      epath,
                    ),
                  )
                }
              }
            }
          }
        }
        continue
      }
      // 席が開いた座の `old` は **宣言 default** であって、ラダー解決済みの値ではない。
      // DR-077 §1: 「old は CLI 席内の畳みの現在値 (初回は default 起点)。値源ラダー (DR-031) は
      // 『席の独立解決 + 選択』であって合成ではないので、他席 (env / config) の値は old に
      // 参加しない — 例: `VERBOSITY=5` + CLI 1 発火は 6 ではなく 1」。逐語 pin は
      // fixture `count-parse/env-coexistence.json::cli-fire-overrides-env`。
      // `resolve_ladder_below_cli` を引きたくなるが、それは DR-114 §7 の **default mode** の規定
      // (「上位ラダー席まで解決した現在値」) であり、ここは effect mode (「発火直前の cell 値」)。
      // 下の `default_seat` が ladder を引くのは `default` 効果が明示発火した場合に限る (DR-081 §2)。
      let old = seats.old(e.name, default_scalar(e))
      // DR-114 §6.1: record 消費 gate は値残余分岐と同じ (old 一致時のみ fn を再実行しない)。
      let (transition, _) = match firing_record {
        Some(record) if record.old_used == old =>
          (record.transition, record.old_consulted)
        _ => @fold.fold_seat_effect(b, old, e.name, extensions.extensions())
      }
      // REFERENCE の `cell_fns` 表 (`empty` 行): `Sentinel(Empty)` は **array / map / record を
      // committed=true で空にする** fn であり、scalar 等を target にした定義は definition-error
      // `invalid-range` である。collection セルはこの関数の冒頭で `resident.resolve_cli` へ抜けて
      // いるので、scalar seat の fold へ `@fold.ToEmpty` が届くのは `empty` の target 型検査を lowering が
      // 持っていない場合に限る (docs/issue/2026-08-02-cell-fn-empty-target-type-check-missing.md)。合法な定義からは
      // 到達しないので、ここで scalar の空セル意味論を発明せず落とす。
      if transition is @fold.ToEmpty {
        abort(
          "unreachable: `empty` は array / map / record 専用 (REFERENCE の cell_fns 表) — scalar (非 collection) セルの fold には合法な定義から届かない",
        )
      }
      // `@abi.Default` / Sentinel(use_default) の落ち先は値源ラダー (DR-081 §2: op=default は
      // 「その時点の書き換え済み default」をセルへ書く — env/config が下位席として後から勝つのでは
      // なく、発火時点で既にセルの default を書き換えている)。
      let default_seat : @abi.Value? = if transition is @fold.ToDefault {
        match
          resolve_ladder_below_cli(
            e, env_map, config_obj, config_path, at_pos, epath, tty_map, extensions,
          ) {
          Ok(bs2) =>
            if bs2.length() > 0 {
              Some(bs2[bs2.length() - 1].value)
            } else {
              None
            }
          Err(pe) => return Err(pe)
        }
      } else {
        None
      }
      match transition {
        @fold.FnMissing(name) =>
          return Err(
            ladder_err(
              e.name,
              at_pos,
              "unknown-vocab",
              "cell fn '" + name + "' is not registered",
              epath,
            ),
          )
        @fold.FnFailed({ reason, message, .. }) =>
          return Err(ladder_err(e.name, at_pos, reason, message, epath))
        @fold.NoChange => ()
        _ => {
          match @fold.seat_after(transition, default_seat) {
            Some(state) => seats.put(e.name, state)
            None => ()
          }
          // 全セル書きは座単位の由来を単一タグへ畳み直す (last-winner) — 以降の部分書きは
          // この書きの carrier source を prior として shadow を起こし直す。
          seat_shadow = None
          committed_now = !(transition is @fold.ToValue(@abi.Null))
          current = match (b.op, transition) {
            // 値を運ぶ効果 (@abi.Set) は VERBATIM。
            (@abi.Set, _) => Some(b)
            // `unset` は席を開けるだけ — commit しないので、この carrier が下流へ出ることはない
            // (後続が commit すれば上書きされ、しなければラダーへ落ちる)。DR-077 以前と同じ契約。
            (@abi.Unset, _) => None
            // `@abi.Default` は DR-081 §2 の「WHO committed the default」を記録する新しい binding
            // (`source` は発火した入口のまま = 自入口なら cli、routed なら link、DR-121 §4)。
            // ラダーが何も供給しなければ書き換え先が無いので placeholder のまま commit する
            // (DR-081 以前と同じ degenerate fallback)。
            (@abi.EffectOp::Default, _) =>
              match default_seat {
                Some(value) => Some(@abi.Binding::new(e.name, value, b.source))
                None => Some(b)
              }
            // cell fn の出力は、Value なら通常の set 束縛、Sentinel なら対応する直接操作の
            // 束縛へ (DR-114 §2)。
            (@abi.Invoke(_), @fold.ToValue(@abi.Null)) => None
            (@abi.Invoke(_), @fold.ToValue(value)) =>
              Some({ ..b, op: @abi.Set, value })
            (@abi.Invoke(_), @fold.ToDefault) =>
              match default_seat {
                Some(value) => Some({ ..b, op: @abi.Set, value })
                None => Some({ ..b, op: @abi.Default })
              }
            _ => current
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
  resolve_ladder_below_cli(
    e,
    env_map,
    config_obj,
    config_path,
    at_pos,
    epath,
    tty_map,
    extensions,
    include_default~,
  )
}

///|
/// DR-081 §1 の「default 席書き換え」モデルの実装的正体: env/config/宣言 default という
/// CLI 未満のラダー段。CLI seat がフォールスルーした場合の通常経路であると同時に、`resolve_entity_
/// raw` の CLI seat 内で `@abi.Default` effect (`:default` variant) が発火した瞬間の **「その時点の
/// (書き換え済み) default 値」を問い合わせる関数としても再利用する** (DR-081 §2 "op=default は
/// 現在の default をそのままセルへ書く")。CLI seat の外に切り出したのは、両方の呼び手が全く同じ
/// 「env が勝てば env、なければ config、なければ宣言 default (無ければ accum は
/// `[]` / scalar は absent)」という 1 本のラダーを必要とするため — 重複実装すると DR-081 が
/// 「複数席が供給する場合は従来のラダー優先順」と明記する優先順位 (env が最終的に勝つ) を 2 箇所で
/// 保守する羽目になる。
///
/// 返り値は素の `resolve_entity_raw` の戻り値と同型 (Array[@abi.Binding], 0 件 = absent 相当 / 1 件以上)。
/// `@abi.Default` effect の呼び手はこれをそのまま bindings として使う (scalar は高々 1 件、accum は
/// env/config の複数 piece もそのまま乗る — DR-081 §2 の accum 節 "書き換え済み default があれば
/// それ" が要求する挙動そのもの)。
fn resolve_ladder_below_cli(
  e : @engine.Entity,
  env_map : (String) -> String?,
  config_obj : @abi.ConfigVal?,
  config_path : Array[String],
  at_pos : Int,
  epath : Array[String],
  tty_map : (String) -> Bool?,
  extensions : @node.Registry,
  include_default? : Bool = true,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  // env seat (DR-049 §2): the raw env string is ONE firing's argument (同 §2 「発火 1 回の 1 引数と
  // 同じ扱い」) — a `multiple` + `separator` cell splits it exactly like `eval.mbt`'s `sep_binds`
  // splits the CLI seat's own raw token (issue 2026-07-09-env-separator-split-gap): each piece
  // runs the SAME pieceProcessor (`env_value`'s piece_filters → parse) independently, and any
  // piece's failure fails the whole seat (all-or-nothing, mirrors `sep_binds`'s contract). No
  // `separator` (the common case) stays exactly the prior single-binding behavior.
  match e.env_key {
    Some(k) =>
      match env_map(k) {
        Some(v) =>
          match e.separator {
            Some(sep) => {
              let bs : Array[@abi.Binding] = []
              for part in split_on_sep(v, sep) {
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
                    bs.push(@abi.Binding::new(e.name, parsed, @abi.Env))
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
                  return Ok([@abi.Binding::new(e.name, parsed, @abi.Env)])
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
              // through to the default seat (null is NOT a value in kuu's value space).
              @abi.Null => ()
              // array → a multiple cell's pieces (DR-050 §4); each item typed per §4 — including
              // §4's string pipeline (issue 2026-07-09-config-string-pieceprocessor-gap), so a
              // string array item ALSO runs `e.piece_filters` before its type parse.
              @abi.Array(items) =>
                if e.accum is Some(_) {
                  let bs : Array[@abi.Binding] = []
                  for it in items {
                    match
                      @builtins.config_to_value(
                        it,
                        e.ty,
                        e.piece_filters,
                        extensions.extensions(),
                      ) {
                      Ok(v) =>
                        bs.push(@abi.Binding::new(e.name, v, @abi.Config))
                      Err({ kind: @abi.Filter, reason, message: msg }) =>
                        return Err(
                          filter_err(e.name, at_pos, reason, msg, epath),
                        )
                      Err({ reason, message: msg, .. }) =>
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
                    extensions.extensions(),
                  ) {
                  Ok(v) =>
                    return Ok([@abi.Binding::new(e.name, v, @abi.Config)])
                  Err({ kind: @abi.Filter, reason, message: msg }) =>
                    return Err(filter_err(e.name, at_pos, reason, msg, epath))
                  Err({ reason, message: msg, .. }) =>
                    return Err(ladder_err(e.name, at_pos, reason, msg, epath)) // §4 型不一致 → DR-037/DR-066 Error
                }
            }
          None => () // not present in config → fall through
        }
      None => () // no config object (no config_file, or default-path read failure) → fall through
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
  // selected observation. tty supplies a single `bool` (DR-129 §1: 端末か否かだけ); the resident
  // owns the declared-default fallback.
  match e.ty.default_seat_observation_key() {
    Some(key) => {
      let observed : Json? = match tty_map(key) {
        Some(terminal) => Some(terminal.to_json())
        None => None
      }
      let declared : @abi.Value? = if e.accum is None {
        match e.default_values {
          Some([value]) => Some(value)
          _ => None
        }
      } else {
        None
      }
      match
        e.ty.default_seat_resolver(@extension.SeatCtx::new(declared, observed~)) {
        Some(value) =>
          match
            @builtins.config_to_value(
              @extension.value_to_configval(value),
              e.ty,
              e.piece_filters,
              extensions.extensions(),
            ) {
            Ok(resolved) =>
              return Ok([
                @abi.Binding::new(
                  e.name,
                  resolved,
                  if observed is Some(_) {
                    @abi.Tty
                  } else {
                    @abi.Default
                  },
                ),
              ])
            Err({ kind: @abi.Filter, reason, message: msg }) =>
              return Err(filter_err(e.name, at_pos, reason, msg, epath))
            Err({ reason, message: msg, .. }) =>
              return Err(ladder_err(e.name, at_pos, reason, msg, epath))
          }
        None => ()
      }
    }
    None => ()
  }
  // const 初期値 (DESIGN §11.4 / DR-031 CONST-Q1=a): root 位置の `value:` はラダーの**席ではない**が、
  // 実効的にはここ — 上位席 (env / config) の供給は上の分岐で既に return 済みなので通常規則
  // どおり const を上書きし、const が値を出せば「無い時に埋める」default 席には到達しない。序列に
  // 参加しないまま cli > env > config > const > default の位置に挟まる形。
  // 値の型付けは default 席と同じパイプライン (`@builtins.config_to_value`) を通す — DR-102 §5 の
  // 「値源の種別でなく値の型が決める」がそのまま適用される (const 専用の型規則は作らない)。
  match e.const_values {
    Some(vs) if vs.length() > 0 => {
      let bs : Array[@abi.Binding] = []
      for v in vs {
        match
          @builtins.config_to_value(
            @extension.value_to_configval(v),
            e.ty,
            e.piece_filters,
            extensions.extensions(),
          ) {
          Ok(vv) => bs.push(@abi.Binding::new(e.name, vv, @abi.Const))
          Err({ kind: @abi.Filter, reason, message: msg }) =>
            return Err(filter_err(e.name, at_pos, reason, msg, epath))
          Err({ reason, message: msg, .. }) =>
            return Err(ladder_err(e.name, at_pos, reason, msg, epath))
        }
      }
      // scalar セルは高々 1 値 (`collect_scalar_array_const` が >1 を definition-error で弾く)。
      return Ok(bs)
    }
    _ => ()
  }
  // default seat (DR-083 §1/§2, DR-102 §5): an accum cell's declared default supplies its WHOLE
  // array as already-split pieces, config-array precedent (DR-050 §4) — each piece routed through
  // `@builtins.config_to_value` (via `@extension.value_to_configval`) for the same T-domain / string-pipeline parse the
  // @abi.Array config branch above uses. A scalar cell wants just the one value (`default_scalar`), but
  // DR-102 §5 (DR-050 §4 / DR-083 §2 の対称性から導出) extends the SAME type-dependent pipeline to
  // it — a JSON string default runs piece_filters → parse (`@builtins.config_to_value`'s `@abi.String` arm), a JSON
  // native (number/bool) default matching the element's type skips piece_filters/parse entirely
  // (the type's own consequence, `@builtins.config_to_value`'s `other => other` passthrough before its
  // `(cv, ty)` match). This is NOT a special case for defaults — it's the same "値源の種別でなく
  // 値の型が決める" rule DR-050 §4 already establishes, reused verbatim for the scalar default seat
  // too (mirrors the accum branch immediately above; both call sites now share one type-parse code
  // path with the config-array branch).
  if e.accum is Some(_) {
    match e.default_values {
      Some(vs) => {
        let bs : Array[@abi.Binding] = []
        for v in vs {
          match
            @builtins.config_to_value(
              @extension.value_to_configval(v),
              e.ty,
              e.piece_filters,
              extensions.extensions(),
            ) {
            Ok(vv) => bs.push(@abi.Binding::new(e.name, vv, @abi.Default))
            Err({ kind: @abi.Filter, reason, message: msg }) =>
              return Err(filter_err(e.name, at_pos, reason, msg, epath))
            Err({ reason, message: msg, .. }) =>
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
        // DR-137/138: scalar セルの tuple/union 複合 default は array 自体が 1 値である。
        // config array の「accumulator pieces」解釈へ通さず、宣言型への供給時適合を直接見る。
        match (v, e.ty.output_type()) {
          (@abi.Array(_), Some(declared)) =>
            if @extension.value_conforms(v, declared, extensions.extensions()) {
              Ok([@abi.Binding::new(e.name, v, @abi.Default)])
            } else {
              Err(
                ladder_err(
                  e.name,
                  at_pos,
                  "default_type_mismatch",
                  "the declared composite default does not conform to the cell output type",
                  epath,
                ),
              )
            }
          _ =>
            match
              @builtins.config_to_value(
                @extension.value_to_configval(v),
                e.ty,
                e.piece_filters,
                extensions.extensions(),
              ) {
              Ok(vv) => Ok([@abi.Binding::new(e.name, vv, @abi.Default)])
              Err({ kind: @abi.Filter, reason, message: msg }) =>
                Err(filter_err(e.name, at_pos, reason, msg, epath))
              Err({ reason, message: msg, .. }) =>
                Err(ladder_err(e.name, at_pos, reason, msg, epath))
            }
        }
      None => Ok([])
    }
  }
}

///|
/// parse 相 fold (DR-127 §4.2 の枝ローカル fold / 裁定後の 1 回 fold) が明示 `default` 効果の
/// 落ち先 (DR-081 §2 の書き換え済み default) を引くための ladder closure
/// (`@engine.parse_tree` の `ladder?`、DR-114 §6.1 の一本化)。resolve 相の
/// `resolve_scope_config_with_export` と同じ素材 — config_file セルの cli > env > default 解決 →
/// provider 読み → `resolve_ladder_below_cli` — を対象セルの scope についてだけ再現する。
/// parse と resolve に同じ `ValueSources` を渡す契約 (facade doc) の下で両相の落ち先が一致する。
///
/// scope が引けない / ladder が Err になる形は宣言 default へ縮退する — その場合 FiringRecord の
/// `old_used` が resolve 相の old と一致しなくなり record は消費されない (resolve 相が従来どおり
/// 自分で解決し、Err も従来どおり resolve 相が報告する) ので、縮退が観測を変えることはない。
fn parse_fold_ladder(
  ast : AtomicAST,
  env : (String) -> String?,
  provider : (String) -> @abi.ConfigVal?,
  tty : (String) -> Bool?,
  args_len : Int,
) -> (@engine.Entity, Array[String], Array[@abi.Binding]) -> @abi.Value? {
  fn(entity, scope_path, eff) {
    // 対象 scope へ command 名で降下する (scope_path は branch fold の宣言 index 由来の
    // command path — index segment を含まない)。
    let mut sc = ast.root
    for segment in scope_path {
      let mut child_scope : @engine.Scope? = None
      for node in sc.greedy {
        match node {
          @engine.CommandSatisfied(_, name, _, child) if name == segment => {
            child_scope = Some(child)
            break
          }
          _ => ()
        }
      }
      match child_scope {
        Some(child) => sc = child
        None => return default_scalar(entity)
      }
    }
    // config_file セルの path 列 (`resolve_scope_config_with_export` Phase 1/2 と同素材、DR-133 §2)。
    // committed path の読み失敗 Error はここでは合成しない — その入力では resolve 相自身が
    // 同じ Err を出すので、ここは供給なしとして縮退すれば十分。
    let scoped_eff : Array[@abi.Binding] = []
    for b in eff {
      if path_eq(b.scope, scope_path) {
        scoped_eff.push(b)
      }
    }
    let config_obj : @abi.ConfigVal? = match
      config_path_list(
        sc,
        scoped_eff,
        env,
        args_len,
        scope_path,
        tty,
        ast.extensions,
      ) {
      Ok(supplies) =>
        match read_config_path_list(supplies, provider, args_len, scope_path) {
          Ok(obj) => obj
          Err(_) => None
        }
      Err(_) => None
    }
    match
      resolve_ladder_below_cli(
        entity,
        env,
        config_obj,
        config_path_of(entity, scope_path),
        args_len,
        scope_path,
        tty,
        ast.extensions,
      ) {
      Ok(bs) =>
        if bs.length() > 0 {
          Some(bs[bs.length() - 1].value)
        } else {
          None
        }
      Err(_) => default_scalar(entity)
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
fn default_fills_cell(e : @engine.Entity, bs : Array[@abi.Binding]) -> Bool {
  if bs.length() > 0 || e.accum is Some(_) {
    return true
  }
  // const (root `value:`) を持つセルも「埋まる」— 席ではないが値はセルに最初からいる (DR-031)。
  e.const_values is Some(_) || default_scalar(e) is Some(_)
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
/// Mirror each resolved public cell into its canonical internal target. The source binding remains
/// present for ordinary result exposure; the copied key is filtered from OutputView by the reserved
/// `#` namespace and is consumed by capability dispatch instead.
fn apply_entity_links(
  entities : Array[@engine.Entity],
  bindings : Array[@abi.Binding],
) -> Array[@abi.Binding] {
  let out = bindings.copy()
  for binding in bindings {
    match entity_named(entities, binding.key) {
      Some(entity) =>
        match entity.link {
          Some(target) => out.push({ ..binding, key: target })
          None => ()
        }
      None => ()
    }
  }
  out
}

///|
fn default_fn_option_edges(
  entity : @engine.Entity,
  extensions : @node.Registry,
) -> Array[String] {
  let edges : Array[String] = []
  match entity.default_fn {
    Some(@abi.Wire(invocation)) =>
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
  extensions : @node.Registry,
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
  extensions : @node.Registry,
) -> Array[@engine.Entity] {
  let ordered : Array[@engine.Entity] = []
  let done : Array[String] = []
  for entity in entities {
    append_default_order(entity, entities, extensions, [], done, ordered)
  }
  ordered
}

///|
/// `siblings` is this scope's own directly-declared entities — the innermost link of the lexical
/// scope chain the `dependency` closure below walks (DR-125 §4, DESIGN §2.7).
fn resolve_default_fn(
  entity : @engine.Entity,
  siblings : Array[@engine.Entity],
  option_values : Map[String, @abi.Value],
  outer_values : Map[String, @abi.Value],
  env_map : (String) -> String?,
  at_pos : Int,
  epath : Array[String],
  extensions : @node.Registry,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
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
        Err({ reason, message, .. }) =>
          return Err(ladder_err(entity.name, at_pos, reason, message, epath))
      }
    None => []
  }
  let ctx = @extension.FnCtx::for_default(
    entity.name,
    old=option_values.get(entity.name),
    observes~,
    // Design rationale: `option=` は外側スコープの解決値のみ (DR-125 前からの視野)、
    // `dependency=` は lexical scope chain (現在スコープ → 外側)。今日の唯一の消費者
    // borrow_fn は default 相で dependency を通るため挙動差は無いが、default 相で
    // ctx.option を読む fn を足すときは視野差に注意 (統一するなら dependency 側へ)。
    option=fn(name) { outer_values.get(name) },
    // Lexical scope chain (DR-125 §4 / DESIGN §2.7): this scope first, then outward. A name the
    // scope declares itself shadows every outer binding, so an entity that resolves to null stops
    // lookup here; borrow returns that absence as null instead of picking up an ancestor's value.
    dependency=Some(fn(name) {
      match option_values.get(name) {
        Some(value) => Some(value)
        None =>
          if entities_contain_name(siblings, name) {
            None
          } else {
            outer_values.get(name)
          }
      }
    }),
    env=fn(variable) {
      match env_map(variable) {
        Some(value) => Some(@abi.String(value))
        None => None
      }
    },
  )
  match descriptor.invoke(fn_call, ctx) {
    Err({ reason, message, .. }) =>
      Err(ladder_err(entity.name, at_pos, reason, message, epath))
    Ok(@extension.FnOutput::Sentinel(_)) =>
      Err(
        ladder_err(
          entity.name,
          at_pos,
          "invalid-range",
          "default_fn returned a sentinel in the default seat",
          epath,
        ),
      )
    Ok(@extension.FnOutput::Value(@abi.Null)) => Ok([])
    Ok(@extension.FnOutput::Value(value)) => {
      // DR-137/138: typed set default が返す**複合値**は既に値空間の値なので、
      // configval 経由の再構成を通さずそのまま座る。primitive はこの限りではない —
      // 下位席は通常の値 pipeline で読む (DR-138 §3) ため、型 parser と piece filter を
      // 通す。value_conforms は粗い ValueType しか見ず int / number を区別しないので、
      // primitive まで direct にすると default_fn の 1.5 が int セルへ素通りする。
      let direct = if value is (@abi.Array(_) | @abi.Object(_)) {
        match entity.ty.output_type() {
          Some(declared) =>
            @extension.value_conforms(value, declared, extensions.extensions())
          None => false
        }
      } else {
        false
      }
      if direct {
        apply_entity_filters(
          entity,
          [@abi.Binding::new(entity.name, value, @abi.Default)],
          at_pos,
          epath,
          extensions,
        )
      } else {
        match
          @builtins.config_to_value(
            @extension.value_to_configval(value),
            entity.ty,
            entity.piece_filters,
            extensions.extensions(),
          ) {
          Ok(decoded) =>
            apply_entity_filters(
              entity,
              [@abi.Binding::new(entity.name, decoded, @abi.Default)],
              at_pos,
              epath,
              extensions,
            )
          Err({ kind: @abi.Filter, reason, message }) =>
            Err(filter_err(entity.name, at_pos, reason, message, epath))
          Err({ reason, message, .. }) =>
            Err(ladder_err(entity.name, at_pos, reason, message, epath))
        }
      }
    }
  }
}

///|
/// DR-050 §5 の循環禁止: config_file 要素のラダーは config 席を持たない — 自分のパスを config
/// ファイルから引くことはできない。それ以外の要素は畳んだ config オブジェクトを見る。config_file が
/// 通常の値セルとして同じ解決ループに乗る (DR-135 §1) 一方で席の非対称だけが残る、その差分をここが持つ。
fn config_seat_for(
  e : @engine.Entity,
  config_obj : @abi.ConfigVal?,
) -> @abi.ConfigVal? {
  if e.is_config_file {
    None
  } else {
    config_obj
  }
}

///|
/// DR-133 §2 のパス列の 1 本。`committed` は源席が cli / env 明示のパス (§4 — 読込失敗が Error になる)、
/// `element` はその Error の帰属先になる config_file 要素の宣言名。
priv struct ConfigPathSupply {
  path : String
  committed : Bool
  element : String
}

///|
/// DR-133 §2 step 1: このスコープの config_file 要素が自分のラダー (cli > env > default、DR-050 §1)
/// で供給したパスを**供給順**に並べて列にする。`multiple` なら供給順の列、単値は列長 1 の縮退形で、
/// どの席からも供給されなければ列は空になる (§2.1 — エラーではない)。スコープの config_file が
/// 1 つであることは `collect_config_file_siblings` が定義時に保証する (§1)。
///
/// パス解決そのものは要素のラダーを `resolve_entity` にそのまま解かせる — config_file 要素も普通の
/// 値セルであり、単体 / `multiple` / filters の違いは要素側の意味論が持つ。config 席だけは循環禁止
/// (DR-050 §5) で `config_obj = None` を渡して塞ぐ。accum セルの効果列は build_result と同じ規則で
/// 畳む (`Empty` / `Unset` / `Default` は clear-point、それ以外は末尾へ追加)。
fn config_path_list(
  sc : @engine.Scope,
  cli : Array[@abi.Binding],
  env_map : (String) -> String?,
  at_pos : Int,
  path : Array[String],
  tty : (String) -> Bool?,
  extensions : @node.Registry,
) -> Result[Array[ConfigPathSupply], @abi.ParseError] {
  let supplies : Array[ConfigPathSupply] = []
  for e in sc.entities {
    if !e.is_config_file {
      continue
    }
    let bs = match
      resolve_entity(
        e,
        cli,
        env_map,
        None,
        config_path_of(e, path),
        at_pos,
        path,
        tty,
        extensions,
        true,
      ) {
      Ok(bs) => bs
      Err(pe) => return Err(pe)
    }
    let own : Array[ConfigPathSupply] = []
    for b in bs {
      match b.op {
        @abi.Empty | @abi.Unset | @abi.Default => own.clear()
        _ =>
          own.push({
            path: @extension.value_str(b.value),
            // DR-133 §4: committed なのは cli / env 明示のパスだけ。default / const 由来の不在は
            // 黙認される。判定はパスごとに閉じており、前のパスの committed 性を後段へ持ち越さない。
            //
            // DR-133 §4.1: **link は透過する** — committed かどうかは値を運んだ経路ではなく値の
            // 源席の cli / env 性で決まる。`@abi.Link` はパース相の `LinkTarget` が argv 発火の
            // 効果を target の key へ書き換えるときに立てるタグ (`@engine.Node::LinkTarget`) なので、
            // 源席は argv = cli である (env / config / default 席はパース相を持たず、resolve 相で
            // link を辿った copy は元の source タグを保つ)。したがって明示供給として扱う。
            // 観測面の `sources` タグは link のまま (DR-121 §4) — 内部判定と観測面は別軸。
            committed: b.source is (@abi.Cli | @abi.Env | @abi.Link),
            element: e.name,
          })
      }
    }
    for s in own {
      supplies.push(s)
    }
  }
  Ok(supplies)
}

///|
/// DR-133 §2 のトップレベルキー置換: `next` が持つトップキーは `prev` のものを置き換え、`next` に
/// 無いトップキーは `prev` の値がそのまま残る。キーの並びは前のオブジェクトの宣言順を保ち、新しい
/// キーだけが後ろへ足される。値の中身は検査しない — ネストした object の内側を再帰的に混ぜること
/// はしない (深いマージ無し)。
fn fold_top_keys(
  prev : Array[(String, @abi.ConfigVal)],
  next : Array[(String, @abi.ConfigVal)],
) -> @abi.ConfigVal {
  let out : Array[(String, @abi.ConfigVal)] = []
  for kv in prev {
    let mut replacement : @abi.ConfigVal? = None
    for nkv in next {
      if nkv.0 == kv.0 {
        replacement = Some(nkv.1)
      }
    }
    match replacement {
      Some(v) => out.push((kv.0, v))
      None => out.push(kv)
    }
  }
  for nkv in next {
    let mut in_prev = false
    for kv in prev {
      if kv.0 == nkv.0 {
        in_prev = true
      }
    }
    if !in_prev {
      out.push(nkv)
    }
  }
  @abi.config_object(out)
}

///|
/// DR-133 §2 step 2/3: パス列の各パスを provider へ渡し (契約は 1 パス → 1 オブジェクトのまま、
/// 列の長さだけ呼ぶ)、読めたオブジェクトを**トップレベルキー置換**で畳んだ 1 個を返す。後のキーが
/// 前を置き換え、後に無いトップキーは前の値が残る。深いマージはしない (§3) — 値の中身は検査せず、
/// キーに対応する値をそのまま置く。
///
/// JSON `null` の読みは「供給なし」(DR-050 §4 / DR-051) なので **fold に参加しない** — 空の
/// オブジェクトでも値でもなく、前段までに畳んだ結果を置き換える権利を持たない (Null だけの列は
/// config 席を空のまま残す)。それ以外の非 object の読み (provider 契約違反の入力) は畳む単位を
/// 持たないので、それ自体が前を置き換える縮退にする。
///
/// 読込失敗の判定は各パス独立 (§4): committed なパスが読めなければその要素に帰属する Error、
/// default 由来のパスの不在は黙認して列の残りを読み続ける。
fn read_config_path_list(
  supplies : Array[ConfigPathSupply],
  provider : (String) -> @abi.ConfigVal?,
  at_pos : Int,
  path : Array[String],
) -> Result[@abi.ConfigVal?, @abi.ParseError] {
  let mut folded : @abi.ConfigVal? = None
  for s in supplies {
    match provider(s.path) {
      None =>
        if s.committed {
          return Err(
            ladder_err(
              s.element,
              at_pos,
              "config_read_failed",
              "config file \"\{s.path}\" could not be read",
              path,
            ),
          )
        }
      // JSON `null` の読みは「供給なし」(DR-050 §4 / DR-051) であって空オブジェクトでも値でも
      // ないので、fold に参加しない — 前段までに畳んだ結果を置き換える権利を持たない。
      Some(@abi.Null) => ()
      Some(obj) =>
        folded = Some(
          match (folded, obj) {
            (Some(@abi.Object(prev)), @abi.Object(next)) =>
              fold_top_keys(prev, next)
            _ => obj
          },
        )
    }
  }
  Ok(folded)
}

///|
/// Resolve a scope WITH a config-file value source (DR-050 §5 dependency order):
///   1. build the DR-133 §2 path list this scope's config_file element supplies (it resolves its own
///      path down cli > env > default; it has NO config seat, 循環禁止)
///   2. read the provider once per path and fold the readable objects by top-level key replacement
///      into the ONE object that sits in the config seat. A committed path (cli/env) that reads None
///      is a DR-037/DR-066 Error (指定したのに読めない); a default path reading None is silently
///      tolerated — the judgement is per path (DR-133 §4), never carried over between paths
///   3. resolve every entity down cli > env > config > default, using the config object and each
///      entity's absolute config path (config_key, else 同型 = scope path + name). config_file
///      elements take part as ordinary value cells here too (DR-135 §1 — their path lands in
///      `result` / `sources`), only their own config seat stays closed (`config_seat_for`)
/// `provider` is the config_provider stub (path → config object | None). `path` is this scope's
/// result path (for 同型 correspondence). `at_pos` is the position an Error is reported at.
fn resolve_scope_config_with_export(
  sc : @engine.Scope,
  cli : Array[@abi.Binding],
  env_map : (String) -> String?,
  provider : (String) -> @abi.ConfigVal?,
  path : Array[String],
  outer_values : Map[String, @abi.Value],
  at_pos : Int,
  tty : (String) -> Bool?,
  ek : @engine.ExportScopeMap,
  extensions : @node.Registry,
  include_default : Bool,
  firings? : @fold.FiringLedger,
) -> Result[Array[@abi.Binding], @abi.ParseError] {
  // Phase 1 (DR-133 §2): build the path list this scope's config_file element supplies.
  let supplies = match
    config_path_list(sc, cli, env_map, at_pos, path, tty, extensions) {
    Ok(ps) => ps
    Err(pe) => return Err(pe)
  }
  // Phase 2 (DR-133 §2/§3/§4): read each path and fold by top-level key replacement.
  let config_obj = match
    read_config_path_list(supplies, provider, at_pos, path) {
    Ok(obj) => obj
    Err(pe) => return Err(pe)
  }
  // Phase 3a: resolve CLI/env/config for every entity before considering any default. These
  // seats are actual claims even when another entity already occupies the same exported result cell.
  let out : Array[@abi.Binding] = []
  let supplied : Array[String] = []
  let occupied : Array[String] = []
  let option_values : Map[String, @abi.Value] = Map([])
  for e in sc.entities {
    let cpath = config_path_of(e, path)
    match
      resolve_entity(
        e,
        cli,
        env_map,
        config_seat_for(e, config_obj),
        cpath,
        at_pos,
        path,
        tty,
        extensions,
        false,
        firings?,
      ) {
      Ok(bs) =>
        if bs.length() > 0 {
          supplied.push(e.name)
          for b in bs {
            out.push(b)
            if b.op is @abi.Set {
              option_values.set(e.name, b.value)
            }
          }
          match ek.exposed_cell(e.name) {
            Some(key) => if !str_contains(occupied, key) { occupied.push(key) }
            None => ()
          }
        }
      Err(pe) => return Err(pe)
    }
  }
  if !include_default {
    // DR-120 §7/§10: distinct cells sharing an export key are rejected before resolution;
    // fixtures/export-key/collision-default-divergent.json pins the definition-error boundary.
    return Ok(apply_entity_links(sc.entities, out))
  }
  // Phase 3b: defaults are fallbacks for the export-key-resolved result cell, not per-entity claims.
  // Only the first default that can actually fill an empty cell is admitted; later co-exported
  // defaults see the occupied cell and do not run their value pipeline at all.
  for e in default_order(sc.entities, extensions) {
    if !str_contains(supplied, e.name) {
      let exposed = ek.exposed_cell(e.name)
      let cell_empty = match exposed {
        Some(key) => !str_contains(occupied, key)
        None => true
      }
      if cell_empty {
        // DESIGN §11.4 / DR-031 (CONST-Q1=a): const (root `value:`) を宣言したセルは default 席へ
        // 行かせない — const は「値セルに最初からいる」初期値なので、`default` / `default_fn`
        // どちらの綴りで default 席が供給されようとセルは既に空でなく、充填は発火しない。
        // `default_fn` 分岐を先に取ると `resolve_ladder_below_cli` を丸ごと迂回して const を
        // 素通りするので、const の有無をこの分岐の条件に含める (両者を宣言できるのは合法 —
        // default 側が死に宣言になるだけ、`required` の vacuous 充足と同じ lint 領分)。
        let resolved = if e.default_fn is Some(_) && e.const_values is None {
          resolve_default_fn(
            e,
            sc.entities,
            option_values,
            outer_values,
            env_map,
            at_pos,
            path,
            extensions,
          )
        } else {
          let cpath = config_path_of(e, path)
          resolve_entity(
            e,
            cli,
            env_map,
            config_seat_for(e, config_obj),
            cpath,
            at_pos,
            path,
            tty,
            extensions,
            true,
            firings?,
          )
        }
        match resolved {
          Ok(bs) => {
            for b in bs {
              out.push(b)
              if b.op is @abi.Set {
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
  Ok(apply_entity_links(sc.entities, out))
}

///|
/// Split `s` on the first char of `sep` (spec DR-034 single-char separator).
fn split_on_sep(s : String, sep : String) -> Array[String] {
  let mut sepc = ','
  for c in sep {
    sepc = c
    break
  }
  let out : Array[String] = []
  let cur = StringBuilder::new()
  for c in s {
    if c == sepc {
      out.push(cur.to_string())
      cur.reset()
    } else {
      cur.write_char(c)
    }
  }
  out.push(cur.to_string())
  out
}

///|
/// DR-138 のセル確定結果。parse 相では `Ambiguous` の interpretation 生成、resolve 相では
/// 勝ち枝 carrier の構築に同じ裁定を使う。
priv enum UnionBindingCulling {
  UnionBindings(Array[@abi.Binding])
  UnionInterpretations(Array[Array[@abi.Binding]])
  UnionIncomplete(Array[@abi.ParseError])
}

///|
fn union_candidate_shadow(
  candidate : @fold.UnionCandidate,
  variant : @abi.ValueType,
  cell : Array[@abi.Binding],
  registry : @extension.Registry,
) -> @abi.ResultValue? {
  let mut shadow : @abi.ResultValue? = None
  for binding in cell {
    if binding.value_residual.length() == 0 {
      if @extension.value_conforms(binding.value, variant, registry) {
        shadow = Some(value_source_shadow(candidate.value, binding.source))
      }
    } else {
      // cull_union_cell と同じ variant 固有の降下で、非適合枝への書き込みを除外する。
      let probe = @fold.CellSeats::new()
      match
        probe.set_at_declared(
          binding.key,
          binding.value_residual,
          binding.value,
          Some(variant),
          registry,
          vivify=binding.op is @abi.Set,
        ) {
        Ok(_) =>
          shadow = Some(
            reshadow_at(
              candidate.value,
              shadow,
              binding.value_residual[:],
              binding.source,
            ),
          )
        Err(_) => ()
      }
    }
  }
  shadow
}

///|
fn union_winner_bindings(
  bindings : Array[@abi.Binding],
  seat : TypeSeat,
  variants : Array[@abi.ValueType],
  candidate : @fold.UnionCandidate,
  registry : @extension.Registry,
) -> Array[@abi.Binding] {
  let out : Array[@abi.Binding] = []
  let cell : Array[@abi.Binding] = []
  for binding in bindings {
    if binding.key == seat.name &&
      path_eq(drop_index_segments(binding.scope), seat.path) {
      cell.push(binding)
    } else {
      out.push(binding)
    }
  }
  if cell.length() == 0 {
    return bindings
  }
  let template_index = if candidate.last_seq >= 0 &&
    candidate.last_seq < cell.length() {
    candidate.last_seq
  } else {
    cell.length() - 1
  }
  let template = cell[template_index]
  let variant = variants[candidate.variant_index]
  out.push({
    ..template,
    op: @abi.Set,
    value: candidate.value,
    value_residual: [],
    source_shadow: union_candidate_shadow(candidate, variant, cell, registry),
  })
  out
}

///|
/// 選択済み宣言セルをセル単位で一度だけ裁定する。セルに書き込みが無い場合は bindings を
/// 変更せず、通常の値源ラダーへ委ねる。
/// DR-138 §4: 生存ゼロの読みは完全経路に数えない。args_pos は当該セル (accum なら当該 row)
/// に着地した書き込みのうち argv 位置最深のもの、argv 位置を持たない書き込みしか無い場合は
/// 消費位置 (DR-127 §4.2 の既存規則)。
fn union_incomplete_error(
  seat : TypeSeat,
  pos : Int,
  consumed_pos : Int,
) -> @abi.ParseError {
  {
    element: seat.name,
    args_pos: if pos >= 0 {
      pos
    } else {
      consumed_pos
    },
    kind: @abi.Parse,
    reason: "incomplete_value",
    message: "the values supplied for \{seat.name} do not add up to a complete value",
    path: seat.path,
  }
}

///|
fn cull_union_bindings(
  ast : AtomicAST,
  bindings : Array[@abi.Binding],
  at_pos : Int,
) -> UnionBindingCulling {
  let seats : Array[TypeSeat] = []
  collect_type_seats(ast.root, [], bindings, seats)
  let registry = ast.extensions.extensions()
  let mut alternatives : Array[Array[@abi.Binding]] = [bindings]
  for seat in seats {
    let variants : Array[@abi.ValueType]? = match seat.value_type {
      @abi.ValueType::Union(members) => Some(@fold.union_leaf_variants(members))
      @abi.ValueType::Tuple(references) =>
        Some([@abi.ValueType::Tuple(references)])
      _ => None
    }
    let variants = match variants {
      Some(value) => value
      None => continue
    }
    let next : Array[Array[@abi.Binding]] = []
    for alternative in alternatives {
      let cell : Array[@abi.Binding] = []
      for binding in alternative {
        if binding.key == seat.name &&
          path_eq(drop_index_segments(binding.scope), seat.path) {
          cell.push(binding)
        }
      }
      // accum セル (multiple / repeat) の row は、それぞれが別の値である (DR-034 /
      // DR-084 §1)。完成判定は値への述語 (DR-138 §1) なので row ごとに独立に回し、
      // 部分値の row が兄弟 row の座を借りて完成することはない。link パスに row 添字は
      // 無い (DR-029 文法) ため、1 binding = 1 row として扱える。
      if seat.is_accumulator {
        let row_errors : Array[@abi.ParseError] = []
        for row in cell {
          match
            @fold.cull_union_cell(
              seat.name,
              variants,
              [row],
              registry,
              default_fall=seat.default_value,
            ) {
            @fold.Incomplete(pos) =>
              row_errors.push(union_incomplete_error(seat, pos, at_pos))
            _ => ()
          }
        }
        // 違反 row は全保持する (DR-053 — args_pos が違うので dedupe されない)。
        if row_errors.length() > 0 {
          return UnionIncomplete(row_errors)
        }
        // 全 row が独立に完成している。行の積み上げは accumulator の管轄なので
        // 勝ち枝 carrier への差し替えはせず、binding 列をそのまま通す。
        next.push(alternative)
        continue
      }
      match
        @fold.cull_union_cell(
          seat.name,
          variants,
          cell,
          registry,
          default_fall=seat.default_value,
        ) {
        @fold.NoWrites => next.push(alternative)
        @fold.Winner(candidate) =>
          next.push(
            union_winner_bindings(
              alternative, seat, variants, candidate, registry,
            ),
          )
        @fold.Tie(candidates) =>
          for candidate in candidates {
            next.push(
              union_winner_bindings(
                alternative, seat, variants, candidate, registry,
              ),
            )
          }
        @fold.Incomplete(pos) =>
          return UnionIncomplete([union_incomplete_error(seat, pos, at_pos)])
      }
    }
    alternatives = next
  }
  if alternatives.length() == 1 {
    UnionBindings(alternatives[0])
  } else {
    UnionInterpretations(alternatives)
  }
}
