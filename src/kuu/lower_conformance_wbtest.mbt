// lower_conformance_wbtest.mbt — lower query の内部構造比較を同 package で実行する。
// AtomicAST は公開面では abstract だが、white-box test は lowering 済み scope と template
// snapshot を直接観測し、fixture の 5 面断面と installer 順序不変性を固定する。

///|
fn lower_str_less(a : String, b : String) -> Bool {
  let ca = a.to_array()
  let cb = b.to_array()
  let n = if ca.length() < cb.length() { ca.length() } else { cb.length() }
  let mut i = 0
  while i < n {
    let x = ca[i].to_int()
    let y = cb[i].to_int()
    if x < y {
      return true
    }
    if x > y {
      return false
    }
    i = i + 1
  }
  ca.length() < cb.length()
}

///|
fn sort_items(arr : Array[String]) -> Unit {
  let mut i = 1
  while i < arr.length() {
    let key = arr[i]
    let mut j = i - 1
    while j >= 0 && lower_str_less(key, arr[j]) {
      arr[j + 1] = arr[j]
      j = j - 1
    }
    arr[j + 1] = key
    i = i + 1
  }
}

///|
fn join_comma(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for item in items {
    if !first {
      buf.write_string(",")
    }
    buf.write_string(item)
    first = false
  }
  buf.to_string()
}

///|
fn join_pipe(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for item in items {
    if !first {
      buf.write_string("|")
    }
    buf.write_string(item)
    first = false
  }
  buf.to_string()
}

///|
fn str_has_prefix(value : String, prefix : String) -> Bool {
  let chars = value.to_array()
  let prefix_chars = prefix.to_array()
  if prefix_chars.length() > chars.length() {
    return false
  }
  let mut i = 0
  while i < prefix_chars.length() {
    if chars[i] != prefix_chars[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn render_val(value : @abi.Value) -> String {
  match value {
    @abi.Null => "null"
    @abi.String(text) => text
    @abi.Bool(flag) => if flag { "true" } else { "false" }
    @abi.Number(number) => {
      let integer = number.to_int()
      if integer.to_double() == number {
        integer.to_string()
      } else {
        number.to_string()
      }
    }
    @abi.Array(_) | @abi.Object(_) =>
      abort("a lowered declaration constant is never a composite value")
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — LSec 5-face 断面 model + renderers + projectors (mirrors slice/poc/lower_runner_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

///|
struct LEnt {
  name : String
  typ : String
  link : String?
  default : @abi.Value?
  env : String?
  config_key : Array[String]?
  accum : String?
  // DR-105 §1/§3: the append-only flatten dial — carried alongside `accum` so a "lower" fixture can
  // pin the repeat installer's cons-unfold output as `{"accumulator":"append","flatten":true}`
  // instead of the retired standalone "flatten" accumulator name (`@engine.Entity.flatten`'s doc comment).
  flatten : Bool
}

///|
enum GItem {
  GExact(String)
  GSet(String, @abi.Value, String)
  GEff(String, String, @abi.EffectOp)
  GSeqSat(String, String)
  GMatch(String, Array[(String, String)])
  GCmd(String, LSec)
}

///|
enum TNode {
  TSeq(Array[TNode])
  TRefEnt(String)
  TRefTmpl(String, Bool)
  TExact(String)
}

///|
struct LSec {
  greedy : Array[GItem]
  positionals : Array[TNode]
  entities : Array[LEnt]
  constraints : Array[@engine.Constraint]
  templates : Array[(String, TNode)]
}

///|
fn canon_tmpl(k : String) -> String {
  let buf = StringBuilder::new()
  for c in k {
    if c == '#' {
      break
    }
    buf.write_char(c)
  }
  buf.to_string() + "#T"
}

///|
fn lent_str(e : LEnt) -> String {
  let fs : Array[String] = ["type=" + e.typ]
  match e.link {
    Some(target) => fs.push("link=" + target)
    None => ()
  }
  match e.default {
    Some(v) => fs.push("default=" + render_val(v))
    None => ()
  }
  match e.env {
    Some(k) => fs.push("env=" + k)
    None => ()
  }
  match e.config_key {
    Some(p) => fs.push("config_key=[" + join_comma(p) + "]")
    None => ()
  }
  match e.accum {
    Some(a) => fs.push("accumulator=" + a)
    None => ()
  }
  // DR-105 §1: omit-if-false — the common (undeclared) case renders no `flatten` field at all so
  // "lower" fixtures without the key still compare equal.
  if e.flatten {
    fs.push("flatten=true")
  }
  sort_items(fs)
  e.name + "{" + join_comma(fs) + "}"
}

///|
fn lcon_str(c : @engine.Constraint) -> String {
  fn sorted(xs : Array[String]) -> String {
    let ss : Array[String] = []
    for x in xs {
      ss.push(x)
    }
    sort_items(ss)
    join_comma(ss)
  }

  match c {
    Requires(el, ts) =>
      "requires{element=" + el + ",targets=[" + sorted(ts) + "]}"
    Conflicts(el, ts) =>
      "conflicts_with{element=" + el + ",targets=[" + sorted(ts) + "]}"
    RequiresIf(entity, branch_id, v, ts) =>
      // DR-055 §1 + DR-052 §値枝 id 直交: entity は committed 判定対象、branch_id は違反時 element。
      // 断面には両方 emit する (entity と branch_id が別ならその非対称が読める; id なしの parent 直属
      // 値依存 requires では entity == branch_id となり冗長だが projection は fixture 側と対称に保つ)。
      "requires_if{entity=" +
      entity +
      ",element=" +
      branch_id +
      ",value=" +
      v +
      ",targets=[" +
      sorted(ts) +
      "]}"
    Exclusive(g, ms) =>
      "exclusive_group{group=" + g + ",members=[" + sorted(ms) + "]}"
    Required(el, cands) => {
      // @engine.RequiredCandidate.name のみ projection (codex M-2 修正で候補が wrapper 付きになったが、
      // lowering 断面はまだ Required/RequiredGroup を対象にした fixture が無い — wrapper 込みの
      // 表記が必要になったら拡張する)。
      let names : Array[String] = []
      for c in cands {
        names.push(c.name)
      }
      "required{element=" + el + ",candidates=[" + sorted(names) + "]}"
    }
    RequiredGroup(g, ms) => {
      let names : Array[String] = []
      for m in ms {
        names.push(m.name)
      }
      "required_group{group=" + g + ",members=[" + sorted(names) + "]}"
    }
  }
}

///|
fn gmatch_entries_str(entries : Array[(String, String)]) -> String {
  let keys : Array[String] = []
  let vals : Array[String] = []
  for kv in entries {
    let mut found = false
    let mut i = 0
    while i < keys.length() {
      if keys[i] == kv.0 {
        found = true
        if vals[i] != kv.1 {
          vals[i] = vals[i] + "!" + kv.1
        }
      }
      i = i + 1
    }
    if !found {
      keys.push(kv.0)
      vals.push(kv.1)
    }
  }
  let items : Array[String] = []
  let mut i = 0
  while i < keys.length() {
    items.push(keys[i] + "->" + vals[i])
    i = i + 1
  }
  sort_items(items)
  join_comma(items)
}

///|
fn lower_eff_op(op : @abi.EffectOp) -> String {
  match op {
    @abi.Set => "set"
    @abi.Default => "default"
    @abi.Unset => "unset"
    @abi.Empty => "empty"
    @abi.Invoke(invocation) =>
      if invocation.args.length() == 0 {
        "fn:" + invocation.name
      } else {
        "fn:" + invocation.name + ":" + join_comma(invocation.args)
      }
    // DR-080 §2 merge accumulator piece markers (eff_op と同じ語彙、lower path 用の並行実装)。
    @abi.Remove => "remove"
    @abi.Splice => "splice"
  }
}

///|
fn gitem_str(g : GItem) -> String {
  match g {
    GExact(s) => "exact(" + s + ")"
    GSet(ex, v, link) =>
      "set{exact=" + ex + ",value=" + render_val(v) + ",link=" + link + "}"
    GEff(ex, link, op) =>
      "eff{exact=" + ex + ",link=" + link + ",op=" + lower_eff_op(op) + "}"
    GSeqSat(trig, ref_) =>
      "seq{exact=" + trig + ",ref=" + ref_ + ",link=" + ref_ + "}"
    GMatch(kind, entries) =>
      "matcher(" + kind + "){" + gmatch_entries_str(entries) + "}"
    GCmd(name, child) =>
      "cmd{exact=" + name + ",scope=(" + lsec_str(child) + ")}"
  }
}

///|
fn tnode_str(t : TNode) -> String {
  match t {
    TSeq(xs) => {
      let items : Array[String] = []
      for x in xs {
        items.push(tnode_str(x))
      }
      "seq[" + join_comma(items) + "]"
    }
    TRefEnt(n) => "ref{" + n + ",link=" + n + "}"
    TRefTmpl(id, opt_) =>
      "ref{" + id + (if opt_ { ",optional" } else { "" }) + "}"
    TExact(s) => "exact(" + s + ")"
  }
}

///|
fn lsec_str(s : LSec) -> String {
  let parts : Array[String] = []
  if s.greedy.length() > 0 {
    let items : Array[String] = []
    for g in s.greedy {
      items.push(gitem_str(g))
    }
    sort_items(items)
    parts.push("G[" + join_comma(items) + "]")
  }
  if s.positionals.length() > 0 {
    let items : Array[String] = []
    for p in s.positionals {
      items.push(tnode_str(p))
    }
    parts.push("P[" + join_comma(items) + "]")
  }
  if s.entities.length() > 0 {
    let items : Array[String] = []
    for e in s.entities {
      items.push(lent_str(e))
    }
    sort_items(items)
    parts.push("E[" + join_comma(items) + "]")
  }
  if s.constraints.length() > 0 {
    let items : Array[String] = []
    for c in s.constraints {
      items.push(lcon_str(c))
    }
    sort_items(items)
    parts.push("C[" + join_comma(items) + "]")
  }
  if s.templates.length() > 0 {
    let items : Array[String] = []
    for kv in s.templates {
      items.push(kv.0 + "=" + tnode_str(kv.1))
    }
    sort_items(items)
    parts.push("T[" + join_comma(items) + "]")
  }
  join_pipe(parts)
}

// ── projection: canon @engine.Scope → 断面 LSec ────────────────────────────────────────

///|
fn prim_name(node : @engine.Node) -> String? {
  match @engine.node_resident_name(node) {
    Some(name) => Some(name)
    None =>
      match node {
        @engine.RequiredArgument(name) => Some(name)
        _ => None
      }
  }
}

///|
fn test_node_is_failure_mark(node : @engine.Node) -> Bool {
  node is @engine.Ext(extension) && extension.is_failure_action()
}

///|
fn test_node_effect_mark(node : @engine.Node) -> (String, @abi.EffectOp)? {
  guard node is @engine.Ext(extension) else { return None }
  extension.effect_mark()
}

///|
fn proj_seq_sat(xs : Array[@engine.Node]) -> GItem {
  match xs {
    [@engine.Exact(trigger), @engine.Bind(name, value), .. markers] => {
      let mut valid_markers = true
      for marker in markers {
        if !test_node_is_failure_mark(marker) &&
          !node_is_deprecation_mark(marker) {
          valid_markers = false
        }
      }
      if valid_markers {
        GSet(trigger, value, name)
      } else {
        GExact("?seq:" + trigger)
      }
    }
    [@engine.Exact(trigger), tail] =>
      match test_node_effect_mark(tail) {
        Some((name, op)) => GEff(trigger, name, op)
        None =>
          match prim_name(tail) {
            Some(name) => GSeqSat(trigger, name)
            None => GExact("?seq:" + trigger)
          }
      }
    _ => GExact("?seq:?")
  }
}

///|
fn proj_matcher_entries(
  matcher : &@extension.MatcherExt,
) -> Array[(String, String)] {
  let entries : Array[(String, String)] = []
  guard matcher.encode() is Array(parts) && parts.length() >= 2 else {
    return entries
  }
  guard parts[0] is String(prefix) else { return entries }
  guard parts[1] is Array(encoded_entries) else { return entries }
  for encoded_entry in encoded_entries {
    match encoded_entry {
      Array(fields) if fields.length() >= 2 =>
        match (fields[0], fields[1]) {
          (String(spelling), String(origin)) =>
            entries.push(
              (
                if matcher.kind() == "eq_split" {
                  prefix + spelling
                } else {
                  spelling
                },
                origin,
              ),
            )
          _ => ()
        }
      _ => ()
    }
  }
  entries
}

///|
test "lowering matcher projection reads encode, not completion candidate policy" {
  // A presence-only eq entry intentionally contributes no completion spelling, but LOWERING §C.5
  // compares the matcher entry table itself. Reading encode keeps the structural entry observable.
  let matcher = @builtins.eq_split("--", [
    @builtins.eq_entry(
      "verbose",
      "verbose",
      @builtins.flag_type(),
      [],
      None,
      merge=false,
      deprecated=false,
    ),
  ])
  assert_eq(matcher.candidates().length(), 0)
  assert_eq(proj_matcher_entries(matcher), [("--verbose", "verbose")])
}

///|
fn proj_greedy(node : @engine.Node, reg : Map[String, @engine.Node]) -> GItem {
  match node {
    @engine.DdSatisfied(name) => GExact(name)
    // DR-090: no golden lowering fixture exercises this yet (spec fixtures for DR-090 are
    // "query":"parse"輪郭, not lowering shape comparisons) — minimal, informative encoding via
    // the existing GMatch shape rather than inventing a new GItem variant for an untested path.
    @engine.DdMatchSatisfied(spelling, is_pattern, self_keep, _) =>
      GMatch("dd_match:" + (if self_keep { "keep" } else { "drop" }), [
        (spelling, if is_pattern { "pattern" } else { "exact" }),
      ])
    @engine.Exact(s) => GExact(s)
    @engine.Rooted(inner, _) => proj_greedy(inner, reg)
    @engine.CommandSatisfied(_, name, _, child) =>
      GCmd(name, proj_scope(child, reg))
    @engine.NativeMatch(matcher) =>
      GMatch(matcher.kind(), proj_matcher_entries(matcher))
    @engine.Seq(xs) => proj_seq_sat(xs)
    _ => GExact("?greedy")
  }
}

///|
fn proj_pos(node : @engine.Node) -> TNode {
  match node {
    Ref(k) => TRefTmpl(canon_tmpl(k), false)
    @engine.Seq(xs) => {
      let items : Array[TNode] = []
      for x in xs {
        items.push(proj_tnode(x))
      }
      TSeq(items)
    }
    other =>
      match prim_name(other) {
        Some(n) => TRefEnt(n)
        None => TExact("?pos")
      }
  }
}

///|
fn proj_tnode(node : @engine.Node) -> TNode {
  match node {
    @engine.Seq(xs) => {
      let items : Array[TNode] = []
      for x in xs {
        items.push(proj_tnode(x))
      }
      TSeq(items)
    }
    @engine.Or([inner, @engine.Seq([])]) =>
      match inner {
        Ref(k) => TRefTmpl(canon_tmpl(k), true)
        other => proj_tnode(other)
      }
    Ref(k) => TRefTmpl(canon_tmpl(k), false)
    @engine.Exact(s) => TExact(s)
    other =>
      match prim_name(other) {
        Some(n) => TRefEnt(n)
        None => TExact("?tnode")
      }
  }
}

///|
fn proj_entity(e : @engine.Entity) -> LEnt {
  let typ = if e.is_config_file {
    "config_file"
  } else {
    match e.ty.name() {
      "count" => "number"
      "flag" => "bool"
      name => name
    }
  }
  {
    name: e.name,
    typ,
    link: e.link,
    // DR-083 §1: LEnt is the golden-fixture "5-face" oracle format, which only knows a scalar
    // default (`dec_lent` below decodes `"default"` via a single `json_to_value`, no accum-array
    // shape) — project the scalar face of `@engine.Entity.default_values` for this cross-check.
    default: default_scalar(e),
    env: e.env_key,
    config_key: e.config_key,
    accum: match e.accum {
      Some(resident) => Some(resident.kind())
      None => None
    },
    flatten: e.flatten,
  }
}

///|
fn collect_reftmpls(
  nodes : Array[@engine.Node],
  reg : Map[String, @engine.Node],
  out : Array[String],
) -> Unit {
  fn is_tmpl_key(k : String) -> Bool {
    !str_has_prefix(k, "lazy:") && reg.get(k) is Some(_)
  }

  fn walk(n : @engine.Node) -> Unit {
    match n {
      Ref(k) =>
        if is_tmpl_key(k) && !conformance_str_in(out, k) {
          out.push(k)
          match reg.get(k) {
            Some(body) => walk(body)
            None => ()
          }
        }
      @engine.Seq(xs) =>
        for x in xs {
          walk(x)
        }
      @engine.Or(xs) =>
        for x in xs {
          walk(x)
        }
      @engine.Many(inner, _) => walk(inner)
      @engine.BoundedTail(inner, _, _) => walk(inner)
      @engine.Scoped(_, inner) => walk(inner)
      @engine.Rooted(inner, _) => walk(inner)
      _ => ()
    }
  }

  for n in nodes {
    walk(n)
  }
}

///|
fn proj_scope(sc : @engine.Scope, reg : Map[String, @engine.Node]) -> LSec {
  let greedy : Array[GItem] = []
  for g in sc.greedy {
    greedy.push(proj_greedy(g, reg))
  }
  let positionals : Array[TNode] = []
  for p in sc.positional {
    positionals.push(proj_pos(p))
  }
  let entities : Array[LEnt] = []
  for e in sc.entities {
    entities.push(proj_entity(e))
  }
  let constraints : Array[@engine.Constraint] = []
  for c in sc.constraints {
    constraints.push(c)
  }
  let ref_ids : Array[String] = []
  collect_reftmpls(sc.positional, reg, ref_ids)
  let templates : Array[(String, TNode)] = []
  for k in ref_ids {
    match reg.get(k) {
      Some(body) => templates.push((canon_tmpl(k), proj_tnode(body)))
      None => ()
    }
  }
  { greedy, positionals, entities, constraints, templates }
}

// ── lower runner (canon_of / pick3 / run_lower) ────────────────────────────────

///|
fn canonical_registry_for_test() -> @node.Registry {
  let registry = @node.Registry::new()
  install_canonical(registry)
  // DR-132 §1: the conformance execution context must resolve `fixture/*` residents.
  install_conformance_fixture_residents(registry)
  registry
}

///|
fn registry_with_installers(
  installers : Array[&@node.InstallerExt],
) -> @node.Registry {
  let registry = @node.Registry::new()
  for installer in installers {
    registry.register_installer(installer)
  }
  for
    node in [
      @builtins.string_arg("", []),
      @builtins.kv_arg("", []),
      @builtins.separated_arg(
        "",
        separator=None,
        ty=@builtins.string_type(),
        int_round=@abi.Error,
        bool_config=@builtins.bool_config_canonical(),
        filters=[],
      ),
      @builtins.number_arg("", filters=[]),
      @builtins.float_arg("", []),
      @builtins.int_arg("", round=@abi.Error, filters=[]),
      @builtins.bool_arg("", config=@builtins.bool_config_canonical(), filters=[]),
      @builtins.typed_arg("", ty=@builtins.string_type(), filters=[]),
      @builtins.effect_mark("", @abi.Set),
      @builtins.deprecation_mark(""),
      @builtins.failure_mark(""),
    ] {
    guard node is @engine.Ext(resident) else {
      abort("builtin node factory did not return an Ext resident")
    }
    ignore(registry.register_node(resident))
  }
  ignore(registry.register_matcher(@builtins.eq_split("", [])))
  ignore(registry.register_matcher(@builtins.short_combine("", [])))
  for
    resident in [
      @builtins.string_type(),
      @builtins.number_type(),
      @builtins.int_type(),
      @builtins.float_type(),
      @builtins.bool_type(),
      @builtins.flag_type(),
      @builtins.count_type(),
      @builtins.completion_script_type(),
      @builtins.none_type(),
    ] {
    ignore(registry.register_type(resident))
  }
  ignore(registry.register_accumulator(@builtins.append_accumulator()))
  ignore(registry.register_accumulator(@builtins.merge_accumulator()))
  ignore(registry.register_accumulator(@builtins.kv_map_accumulator()))
  ignore(registry.register_collector(@builtins.unwrap_single_collector()))
  ignore(
    registry.register_collector(
      @builtins.from_entries_collector(@extension.Entries),
    ),
  )
  for descriptor in @builtins.cell_fn_descriptors() {
    ignore(registry.register_cell_fn(descriptor))
  }
  // DR-132 §1: fixture corpus 横断の decode (順列不変検査) も conformance 実行文脈。
  install_conformance_fixture_residents(registry)
  registry
}

///|
fn canon_of(definition : Json, order : Array[&@node.InstallerExt]) -> String {
  match
    parse_definition(definition, extensions=registry_with_installers(order)) {
    Ok(ast) => lsec_str(proj_scope(ast.root, ast.templates))
    Err(Malformed(reason)) => "ERR:" + reason
    Err(Rejected(errors)) => "ERR:" + deferrs_str(errors)
  }
}

///|
fn order_sig(order : Array[&@node.InstallerExt]) -> String {
  let buf = StringBuilder::new()
  for x in order {
    buf.write_string(@builtins.owned_vocab(x))
    buf.write_string(";")
  }
  buf.to_string()
}

///|
fn pick3(
  order : Array[&@node.InstallerExt],
) -> Array[Array[&@node.InstallerExt]] {
  let ident : Array[&@node.InstallerExt] = []
  for x in order {
    ident.push(x)
  }
  let rev : Array[&@node.InstallerExt] = []
  let mut i = order.length() - 1
  while i >= 0 {
    rev.push(order[i])
    i = i - 1
  }
  let rot : Array[&@node.InstallerExt] = []
  if order.length() > 0 {
    let mut j = 1
    while j < order.length() {
      rot.push(order[j])
      j = j + 1
    }
    rot.push(order[0])
  }
  let out : Array[Array[&@node.InstallerExt]] = []
  let sigs : Array[String] = []
  for cand in [ident, rev, rot] {
    let sig = order_sig(cand)
    if !conformance_str_in(sigs, sig) {
      sigs.push(sig)
      out.push(cand)
    }
  }
  out
}

// ── 順列 property test (DR-042 §5 順序非依存 / DR-070 常時 = 決定的少数) ─────────
//
// DR-042 §5 の不変則は「installer の適用順が lowered 結果に影響しない」ことを契約にして
// いる (根拠: ①宣言層は読み取り専用・寄与は add-if-absent で冪等 ②他 installer の
// lowered 産物を読み書きしない → 合流性。見かけの依存は run_installer_fixpoint の不動点
// 反復が吸収する)。PoC 期は 7 installer = 5040 順列を全数検査できたが、canonical chain は
// 14 installer = 14! ≈ 871 億順列で全数検査は不可能。そこで DR-070 の「常時 = 決定的少数」
// (= pick3) を回帰網として残したまま、決定的 PRNG によるランダム順列サンプリングを足し、
// seed / サンプル数を環境変数で振れるようにする (実行のたびに別の順列を踏めるので、CI が
// 回るほどカバレッジが累積する)。反例は fixture 名 / seed / 順列署名 / got vs want を全て
// 出す — 再現できない property test には価値がないため。

///|
/// KUU_PERM_SEED 未指定時の seed。固定値なので既定実行 (開発者の手元 / CI) は常に同じ
/// 順列集合を踏む = 決定的な回帰網として振る舞う。振りたいときだけ env で上書きする。
fn perm_seed_default() -> UInt {
  0x6B75755FU // "kuu_"
}

///|
/// KUU_PERM_SAMPLES 未指定時の fixture あたりサンプル数。1 サンプルにつき fixture 1 件の
/// parse_definition が 1 回増えるため、既定は小さく取り、掘りたいときに env で上げる。
fn perm_samples_default() -> Int {
  4
}

///|
/// 10 進非負整数の最小 parser。環境変数由来の値だけを対象にし、不正入力は None を返して
/// 既定値に落とす (env の typo でテスト全体が abort するのは本末転倒)。
fn perm_parse_uint(raw : String) -> UInt? {
  let chars = raw.to_array()
  if chars.length() == 0 {
    return None
  }
  let mut acc : UInt = 0
  for c in chars {
    let digit = c.to_int() - '0'.to_int()
    if digit < 0 || digit > 9 {
      return None
    }
    acc = acc * 10 + digit.reinterpret_as_uint()
  }
  Some(acc)
}

///|
fn perm_env_uint(name : String, fallback : UInt) -> UInt {
  match @env.get_env_var(name) {
    Some(raw) =>
      match perm_parse_uint(raw) {
        Some(value) => value
        None => fallback
      }
    None => fallback
  }
}

///|
/// xorshift32。stdlib の乱数に依存せず自前で持つことで、toolchain / 実行環境が変わっても
/// 同じ seed から同じ順列列が再現できる (再現性が property test の生命線)。
struct PermRng {
  mut state : UInt
}

///|
fn PermRng::new(seed : UInt) -> PermRng {
  // 0 は xorshift の吸収状態 (以後ずっと 0) なので非零定数へ逃がす。
  { state: if seed == 0 { 0x9E3779B9U } else { seed } }
}

///|
fn PermRng::next(self : PermRng) -> UInt {
  let mut x = self.state
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  self.state = x
  x
}

///|
fn PermRng::below(self : PermRng, bound : Int) -> Int {
  if bound <= 1 {
    0
  } else {
    (self.next() % bound.reinterpret_as_uint()).reinterpret_as_int()
  }
}

///|
/// fixture ごとに独立した乱数列を作る (base seed ⊕ FNV-1a(fixture 相対パス))。fixture 集合
/// が増減しても各 fixture が踏む順列は変わらないので、失敗報告の seed と fixture 名だけで
/// その 1 件を単独再現できる。
fn perm_stream_seed(base : UInt, rel : String) -> UInt {
  let mut hash : UInt = 2166136261U
  for c in rel.to_array() {
    hash = (hash ^ c.to_int().reinterpret_as_uint()) * 16777619U
  }
  hash ^ base
}

///|
/// Fisher-Yates で一様ランダムな順列を作る (元 order は破壊しない)。
fn perm_shuffled(
  order : Array[&@node.InstallerExt],
  rng : PermRng,
) -> Array[&@node.InstallerExt] {
  let out : Array[&@node.InstallerExt] = []
  for x in order {
    out.push(x)
  }
  let mut i = out.length() - 1
  while i > 0 {
    let j = rng.below(i + 1)
    let tmp = out[i]
    out[i] = out[j]
    out[j] = tmp
    i = i - 1
  }
  out
}

///|
/// P1: ∀ ランダム順列 π. canon_of(definition, π) == baseline (= identity 順の結果)。
/// 食い違った順列だけを説明文字列で返す (空 = そのサンプル群では不変則を満たした)。
/// 説明には seed / サンプル番号 / 順列署名 / その順列の結果を載せる — 呼び出し側が fixture 名を
/// 前置すれば、報告だけで当該 1 件を単独再現できる。
fn perm_divergences(
  definition : Json,
  order : Array[&@node.InstallerExt],
  baseline : String,
  rel~ : String,
  perm_seed~ : UInt,
  perm_samples~ : Int,
) -> Array[String] {
  let diverged : Array[String] = []
  // installer 1 個以下は順列が 1 通りしかないのでサンプリングの意味がない。
  if order.length() < 2 || perm_samples <= 0 {
    return diverged
  }
  let rng = PermRng::new(perm_stream_seed(perm_seed, rel))
  let mut n = 0
  while n < perm_samples {
    let p = perm_shuffled(order, rng)
    let permuted = canon_of(definition, p)
    if permuted != baseline {
      diverged.push(
        "random|seed=" +
        perm_seed.to_string() +
        "|sample=" +
        n.to_string() +
        "|order=" +
        order_sig(p) +
        "|got=" +
        permuted,
      )
    }
    n = n + 1
  }
  diverged
}

///|
fn run_lower(
  definition : Json,
  order : Array[&@node.InstallerExt],
  want : LSec,
  rel~ : String,
  perm_seed~ : UInt,
  perm_samples~ : Int,
) -> String {
  let got = canon_of(definition, order)
  let wantS = lsec_str(want)
  let diverged : Array[String] = []
  // 決定的 3 順列 (identity / reverse / rotate-1): env に依存しない常時の回帰網。
  for p in pick3(order) {
    let permuted = canon_of(definition, p)
    if permuted != got {
      diverged.push("pick3|order=" + order_sig(p) + "|got=" + permuted)
    }
  }
  // ランダム順列サンプリング: 決定的 PRNG なので seed を報告すれば単独再現できる。
  for
    d in perm_divergences(
      definition,
      order,
      got,
      rel~,
      perm_seed~,
      perm_samples~,
    ) {
    diverged.push(d)
  }
  if diverged.length() > 0 {
    // identity 順の結果 (base) が順列不変の基準。各順列の got は上の要素に載せている。
    let buf = StringBuilder::new()
    buf.write_string("PERM-DIVERGE")
    for d in diverged {
      buf.write_string(" [" + d + "]")
    }
    buf.write_string("|base=" + got + "|want=" + wantS)
    buf.to_string()
  } else if got == wantS {
    "PASS"
  } else {
    "DIVERGE|got=" + got + "|want=" + wantS
  }
}

// ── lower path ────────────────────────────────────────────────────────────────

///|
struct DecodedLower {
  definition : Json
  order : Array[&@node.InstallerExt]
  want : LSec
}

///|
fn dec_installer(name : String) -> &@node.InstallerExt raise DecodeSkip {
  for i in canonical_registry_for_test().installers() {
    if @builtins.owned_vocab(i) == name {
      return i
    }
  }
  raise DecodeSkip("unknown installer '" + name + "'")
}

///|
fn dec_installers(
  top : Map[String, Json],
) -> Array[&@node.InstallerExt] raise DecodeSkip {
  match top.get("installers") {
    None => canonical_registry_for_test().installers()
    Some(j) =>
      match j.j_arr() {
        None => canonical_registry_for_test().installers()
        Some(a) => {
          let out : Array[&@node.InstallerExt] = []
          for e in a {
            match e.j_str() {
              Some(s) => out.push(dec_installer(s))
              None => raise DecodeSkip("installers[] element is not a string")
            }
          }
          out
        }
      }
  }
}

///|
fn req_field(o : Map[String, Json], key : String) -> String raise DecodeSkip {
  match jf_str(o, key) {
    Some(s) => s
    None => raise DecodeSkip("golden node missing string field '" + key + "'")
  }
}

///|
fn dec_ref_link(
  o : Map[String, Json],
  what : String,
) -> String raise DecodeSkip {
  allowed_keys(o, ["ref", "link"], what)
  let r = req_field(o, "ref")
  let l = req_field(o, "link")
  if l != r {
    raise DecodeSkip(
      what +
      " has ref≠link (unrepresentable in 断面: ref=" +
      r +
      " link=" +
      l +
      ")",
    )
  }
  r
}

///|
fn dec_gitem(j : Json) -> GItem raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("greedy item is not an object")
  }
  if has_key(o, "scope") {
    allowed_keys(o, ["exact", "scope"], "golden command subtree")
    let name = req_field(o, "exact")
    let so = match o.get("scope").unwrap().j_obj() {
      Some(x) => x
      None => raise DecodeSkip("command 'scope' is not an object")
    }
    return GCmd(name, dec_lsec(so))
  }
  if has_key(o, "matcher") {
    allowed_keys(o, ["matcher", "entries"], "golden matcher")
    let kind = req_field(o, "matcher")
    let entries : Array[(String, String)] = []
    match o.get("entries") {
      Some(ej) =>
        match ej.j_obj() {
          Some(eo) =>
            for k, v in eo {
              match v.j_str() {
                Some(nm) => entries.push((k, nm))
                None => raise DecodeSkip("matcher entry value is not a string")
              }
            }
          None => raise DecodeSkip("matcher 'entries' is not an object")
        }
      None => raise DecodeSkip("matcher missing 'entries'")
    }
    return GMatch(kind, entries)
  }
  if has_key(o, "seq") {
    allowed_keys(o, ["seq"], "golden seq satellite")
    let sa = match o.get("seq").unwrap().j_arr() {
      Some(x) => x
      None => raise DecodeSkip("greedy seq is not an array")
    }
    if sa.length() != 2 {
      raise DecodeSkip("greedy seq satellite is not [exact, ref]")
    }
    let trig = match sa[0].j_obj() {
      Some(x) => {
        allowed_keys(x, ["exact"], "golden seq trigger")
        req_field(x, "exact")
      }
      None => raise DecodeSkip("greedy seq[0] is not an object")
    }
    let refn = match sa[1].j_obj() {
      Some(x) => dec_ref_link(x, "golden seq value cell")
      None => raise DecodeSkip("greedy seq[1] is not an object")
    }
    return GSeqSat(trig, refn)
  }
  if has_key(o, "value") {
    allowed_keys(o, ["exact", "value", "link"], "golden set descriptor")
    return GSet(
      req_field(o, "exact"),
      json_to_value(o.get("value").unwrap()),
      req_field(o, "link"),
    )
  }
  // DR-045 effect descriptor (`{exact, link, effect: {op, transform?, args?}}`) — the non-@abi.Set ops
  // (default/unset/empty/update, DR-011/077) that lower to `@engine.Seq([@engine.Exact, effect resident])` (see the
  // `[@engine.Exact(t), effect resident] => GEff(t, n, op)` projection below). No `lower fixture` used this
  // shape before DR-077 (every prior lowering fixture only exercised @abi.Set), so this decode path is
  // new — added for count's `:update:increment` lowering fixtures, but generic over all 4 non-set
  // ops.
  if has_key(o, "effect") {
    allowed_keys(o, ["exact", "link", "effect"], "golden effect descriptor")
    let ex = req_field(o, "exact")
    let link = req_field(o, "link")
    let effo = match o.get("effect").unwrap().j_obj() {
      Some(x) => x
      None => raise DecodeSkip("effect is not an object")
    }
    return GEff(ex, link, dec_eff_op(effo))
  }
  allowed_keys(o, ["exact"], "golden greedy exact")
  GExact(req_field(o, "exact"))
}

///|
/// DR-045 op vocab (`set`/`default`/`unset`/`empty`) + DR-077 §1's 5th op (`update`, which additionally
/// carries a `transform` name + optional `args`). `set` is accepted for completeness even though
/// GSet's dedicated `{value, link}` shorthand is the normal spelling for it in a fixture.
fn dec_eff_op(o : Map[String, Json]) -> @abi.EffectOp raise DecodeSkip {
  match jf_str(o, "fn") {
    Some(name) => {
      allowed_keys(o, ["fn", "args"], "cell fn effect")
      let args : Array[String] = match o.get("args") {
        Some(aj) =>
          match aj.j_arr() {
            Some(values) => {
              let decoded : Array[String] = []
              for value in values {
                match value.j_str() {
                  Some(text) => decoded.push(text)
                  None =>
                    raise DecodeSkip(
                      "cell fn effect args element is not a string",
                    )
                }
              }
              decoded
            }
            None => raise DecodeSkip("cell fn effect 'args' is not an array")
          }
        None => []
      }
      return @abi.Invoke({ name, args })
    }
    None => ()
  }
  let opstr = match jf_str(o, "op") {
    Some(s) => s
    None => raise DecodeSkip("effect missing 'op' or 'fn'")
  }
  allowed_keys(o, ["op"], "direct effect")
  match opstr {
    "set" => @abi.Set
    "default" => @abi.Default
    "unset" => @abi.Unset
    "empty" => @abi.Empty
    other => raise DecodeSkip("unrecognized effect op '" + other + "'")
  }
}

///|
fn dec_pos_tnode(j : Json) -> TNode raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("positional node is not an object")
  }
  if has_key(o, "link") {
    return TRefEnt(dec_ref_link(o, "positional entity ref"))
  }
  match jf_str(o, "ref") {
    Some(k) => {
      allowed_keys(o, ["ref", "optional"], "positional template ref")
      TRefTmpl(canon_tmpl(k), bool_field(o, "optional", false))
    }
    None => raise DecodeSkip("unrecognized positional node")
  }
}

///|
fn dec_tmpl_body(j : Json) -> TNode raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("template body is not an object")
  }
  if has_key(o, "seq") {
    allowed_keys(o, ["seq"], "template seq")
    let sa = match o.get("seq").unwrap().j_arr() {
      Some(x) => x
      None => raise DecodeSkip("template seq is not an array")
    }
    let items : Array[TNode] = []
    for e in sa {
      items.push(dec_tmpl_body(e))
    }
    return TSeq(items)
  }
  if has_key(o, "link") {
    return TRefEnt(dec_ref_link(o, "template entity ref"))
  }
  if has_key(o, "ref") {
    allowed_keys(o, ["ref", "optional"], "template ref")
    return TRefTmpl(
      canon_tmpl(req_field(o, "ref")),
      bool_field(o, "optional", false),
    )
  }
  allowed_keys(o, ["exact"], "template literal")
  TExact(req_field(o, "exact"))
}

///|
fn dec_lent(name : String, j : Json) -> LEnt raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("entity is not an object")
  }
  allowed_keys(
    o,
    ["type", "link", "default", "env", "config_key", "accumulator", "flatten"],
    "golden entity",
  )
  let typ = req_field(o, "type")
  let default = match o.get("default") {
    Some(d) => Some(json_to_value(d))
    None => None
  }
  let config_key : Array[String]? = match o.get("config_key") {
    Some(c) => Some(dec_strs(Some(c)))
    None => None
  }
  {
    name,
    typ,
    link: jf_str(o, "link"),
    default,
    env: jf_str(o, "env"),
    config_key,
    accum: jf_str(o, "accumulator"),
    flatten: bool_field(o, "flatten", false),
  }
}

///|
fn dec_lcon(j : Json) -> @engine.Constraint raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("constraint is not an object")
  }
  match req_field(o, "kind") {
    "requires" => {
      allowed_keys(o, ["kind", "element", "targets"], "requires constraint")
      Requires(req_field(o, "element"), dec_strs(o.get("targets")))
    }
    "conflicts_with" => {
      allowed_keys(
        o,
        ["kind", "element", "targets"],
        "conflicts_with constraint",
      )
      Conflicts(req_field(o, "element"), dec_strs(o.get("targets")))
    }
    "requires_if" => {
      // DR-055 §1 + DR-052 §値枝 id 直交: fixture 側が constraints[] を直宣言する場面での decoder。
      // `entity` (committed 判定対象) と `element` (違反時 emit する branch_id) の両方を受け付ける。
      // `entity` 省略時は `element` にフォールバック (parent 直属 value_requires 相当の暗黙形)。
      allowed_keys(
        o,
        ["kind", "entity", "element", "value", "targets"],
        "requires_if constraint",
      )
      let element = req_field(o, "element")
      let entity = jf_str(o, "entity").unwrap_or(element)
      RequiresIf(
        entity,
        element,
        req_field(o, "value"),
        dec_strs(o.get("targets")),
      )
    }
    "exclusive_group" => {
      allowed_keys(
        o,
        ["kind", "group", "members"],
        "exclusive_group constraint",
      )
      Exclusive(req_field(o, "group"), dec_strs(o.get("members")))
    }
    other => raise DecodeSkip("unsupported constraint kind '" + other + "'")
  }
}

///|
fn dec_lsec(o : Map[String, Json]) -> LSec raise DecodeSkip {
  allowed_keys(
    o,
    ["greedy", "positionals", "entities", "constraints", "templates"],
    "golden 断面",
  )
  let greedy : Array[GItem] = []
  match o.get("greedy") {
    Some(gj) =>
      match gj.j_arr() {
        Some(a) =>
          for e in a {
            greedy.push(dec_gitem(e))
          }
        None => raise DecodeSkip("greedy is not an array")
      }
    None => ()
  }
  let positionals : Array[TNode] = []
  match o.get("positionals") {
    Some(pj) =>
      match pj.j_arr() {
        Some(a) =>
          for e in a {
            positionals.push(dec_pos_tnode(e))
          }
        None => raise DecodeSkip("positionals is not an array")
      }
    None => ()
  }
  let entities : Array[LEnt] = []
  match o.get("entities") {
    Some(en) =>
      match en.j_obj() {
        Some(eo) =>
          for k, v in eo {
            entities.push(dec_lent(k, v))
          }
        None => raise DecodeSkip("entities is not an object")
      }
    None => ()
  }
  let constraints : Array[@engine.Constraint] = []
  match o.get("constraints") {
    Some(cj) =>
      match cj.j_arr() {
        Some(a) =>
          for e in a {
            constraints.push(dec_lcon(e))
          }
        None => raise DecodeSkip("constraints is not an array")
      }
    None => ()
  }
  let templates : Array[(String, TNode)] = []
  match o.get("templates") {
    Some(tj) =>
      match tj.j_obj() {
        Some(to) =>
          for k, v in to {
            templates.push((canon_tmpl(k), dec_tmpl_body(v)))
          }
        None => raise DecodeSkip("templates is not an object")
      }
    None => ()
  }
  { greedy, positionals, entities, constraints, templates }
}

///|
fn dec_lower(j : Json) -> DecodedLower raise DecodeSkip {
  let top = match j.j_obj() {
    Some(o) => o
    None => raise DecodeSkip("fixture is not an object")
  }
  let definition = match top.get("definition") {
    Some(value) => value
    None => raise DecodeSkip("missing 'definition'")
  }
  let order = dec_installers(top)
  let expo = match top.get("expect") {
    Some(e) =>
      match e.j_obj() {
        Some(o) => o
        None => raise DecodeSkip("expect is not an object")
      }
    None => raise DecodeSkip("missing 'expect'")
  }
  { definition, order, want: dec_lsec(expo) }
}

///|
fn is_json_file(name : String) -> Bool {
  let cs = name.to_array()
  let n = cs.length()
  n >= 5 &&
  cs[n - 5] == '.' &&
  cs[n - 4] == 'j' &&
  cs[n - 3] == 's' &&
  cs[n - 2] == 'o' &&
  cs[n - 1] == 'n'
}

///|
fn fixtures_root() -> String {
  match @env.get_env_var("KUU_FIXTURES") {
    Some(p) => if p != "" && @fs.path_exists(p) { return p }
    None => ()
  }
  for
    cand in [
      "../../../kuu/main/fixtures", "../../kuu/main/fixtures", "../../../../kuu/main/fixtures",
    ] {
    if @fs.path_exists(cand) {
      return cand
    }
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "?"
  }
  abort(
    "fixtures root not found (set KUU_FIXTURES to kuu/main/fixtures); cwd=" +
    cwd,
  )
}

///|
fn collect_rel(root : String, rel : String, out : Array[String]) -> Unit raise {
  let dir = if rel == "" { root } else { root + "/" + rel }
  for name in @fs.read_dir(dir) {
    let r = if rel == "" { name } else { rel + "/" + name }
    let p = root + "/" + r
    if @fs.is_dir(p) {
      collect_rel(root, r, out)
    } else if is_json_file(name) {
      out.push(r)
    }
  }
}

///|
fn load_json(path : String) -> Json raise {
  @json.parse(@fs.read_file_to_string(path))
}

///|
/// lower query の fixture 全件を decode し、期待する 5 面断面と installer 順序 (決定的 3 種 +
/// ランダムサンプル) の結果を比較する。decode skip・断面差分・順序差分はいずれも失敗として返し、
/// blackbox conformance runner が result/outcome の公開面だけを扱っても lowering 内部構造の
/// 保証を失わないようにする。順列サンプリングは `KUU_PERM_SEED` / `KUU_PERM_SAMPLES` で振れる
/// (DR-042 §5 の順序非依存を全数検査できない 14! 規模への対応、既定値は上の perm_*_default)。
fn verify_lower_conformance_fixtures() -> Unit {
  let root = fixtures_root()
  let perm_seed = perm_env_uint("KUU_PERM_SEED", perm_seed_default())
  let perm_samples = perm_env_uint(
    "KUU_PERM_SAMPLES",
    perm_samples_default().reinterpret_as_uint(),
  ).reinterpret_as_int()
  let rels : Array[String] = []
  collect_rel(root, "", rels) catch {
    _ => abort("fixtures walk failed under " + root)
  }
  sort_items(rels)
  let skips : Array[String] = []
  let mismatches : Array[String] = []
  let mut decoded = 0
  for rel in rels {
    let full = root + "/" + rel
    let json = load_json(full) catch { _ => continue }
    let query = match json.j_obj() {
      Some(fields) => jf_str(fields, "query").unwrap_or("")
      None => ""
    }
    if query != "lower" {
      continue
    }
    let fixture = dec_lower(json) catch {
      DecodeSkip(reason) => {
        skips.push(rel + " :: " + reason)
        continue
      }
      UnknownType(element, type_name) => {
        skips.push(rel + " :: unknown type '" + type_name + "' for " + element)
        continue
      }
    }
    decoded = decoded + 1
    let verdict = run_lower(
      fixture.definition,
      fixture.order,
      fixture.want,
      rel~,
      perm_seed~,
      perm_samples~,
    )
    if verdict != "PASS" {
      mismatches.push(rel + "::lower :: " + verdict)
    }
  }
  if decoded == 0 || skips.length() > 0 || mismatches.length() > 0 {
    let report = StringBuilder::new()
    report.write_string(
      "lower conformance failed: decoded=" +
      decoded.to_string() +
      " perm_seed=" +
      perm_seed.to_string() +
      " perm_samples=" +
      perm_samples.to_string() +
      "\n",
    )
    for skip in skips {
      report.write_string("  SKIP " + skip + "\n")
    }
    for mismatch in mismatches {
      report.write_string("  DIVERGE " + mismatch + "\n")
    }
    abort(report.to_string())
  }
}

///|
/// 順列不変を fixture corpus 全体 (query 種別を問わず、`definition` を持つ全件) に対して
/// canonical chain (installer 14 個) のランダム順列で検査する。
///
/// `verify_lower_conformance_fixtures` の順列検査は fixture が `installers` で pin した鎖を振るため、
/// lower fixture 26 件のうち 14 個の完全鎖を踏むのは 1 件だけ (残りは 1〜3 個の subset) で、
/// 14! ≈ 871 億の順列空間はほとんど掘れない。ここは逆に **鎖を canonical 固定して definition 側を
/// corpus 全体に広げ**、identity 順の結果を基準に順列不変 (DR-042 §5) を確かめる。fixture の
/// `want` とは比較しない — 完全鎖の lowered 結果は subset 鎖の期待値と一致しないため、ここでの
/// 判定基準はあくまで「同じ definition・同じ鎖なら順序によらず同じ結果」の 1 点。
/// definition-error fixture も対象に含む (Reject された error 集合の順序非依存も同じ契約のうち)。
fn verify_installer_permutation_property() -> Unit {
  let root = fixtures_root()
  let perm_seed = perm_env_uint("KUU_PERM_SEED", perm_seed_default())
  let perm_samples = perm_env_uint(
    "KUU_PERM_SAMPLES",
    perm_samples_default().reinterpret_as_uint(),
  ).reinterpret_as_int()
  let canonical = canonical_registry_for_test().installers()
  let rels : Array[String] = []
  collect_rel(root, "", rels) catch {
    _ => abort("fixtures walk failed under " + root)
  }
  sort_items(rels)
  let mismatches : Array[String] = []
  let mut checked = 0
  for rel in rels {
    let json = load_json(root + "/" + rel) catch { _ => continue }
    let fields = match json.j_obj() {
      Some(o) => o
      None => continue
    }
    let definition = match fields.get("definition") {
      Some(d) => d
      None => continue
    }
    if definition.j_obj() is None {
      continue
    }
    checked = checked + 1
    let baseline = canon_of(definition, canonical)
    for
      d in perm_divergences(
        definition,
        canonical,
        baseline,
        rel~,
        perm_seed~,
        perm_samples~,
      ) {
      mismatches.push(rel + " :: " + d + "|base=" + baseline)
    }
  }
  if checked == 0 || mismatches.length() > 0 {
    let report = StringBuilder::new()
    report.write_string(
      "installer permutation property failed: checked=" +
      checked.to_string() +
      " installers=" +
      canonical.length().to_string() +
      " perm_seed=" +
      perm_seed.to_string() +
      " perm_samples=" +
      perm_samples.to_string() +
      "\n",
    )
    for mismatch in mismatches {
      report.write_string("  PERM-DIVERGE " + mismatch + "\n")
    }
    abort(report.to_string())
  }
}

///|
/// 保証: DR-042 §5 の順序非依存 (①宣言層は読み取り専用・寄与は add-if-absent ②他 installer の
/// lowered 産物を読み書きしない → 合流性) が、fixture corpus 全件 × canonical 14 installer の
/// ランダム順列で破れないこと。14! ≈ 871 億順列を全数検査できない以上、決定的 3 順列 (DR-070 の
/// 「常時 = 決定的少数」) だけでは薄いので、seed を振れるサンプリングで CI 実行のたびに別の順列を
/// 踏ませ、カバレッジを累積させる。
/// 再現: `KUU_PERM_SEED=<失敗報告の seed> KUU_PERM_SAMPLES=<同 samples> moon test --target native`。
test "installer order invariance over the fixture corpus (DR-042 §5)" {
  verify_installer_permutation_property()
}
