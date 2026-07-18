// lower_conformance_wbtest.mbt — lower query の内部構造比較を同 package で実行する。
// AtomicAST は公開面では abstract だが、white-box test は lowering 済み scope と template
// snapshot を直接観測し、fixture の 5 面断面と installer 順序不変性を固定する。

///|
fn lower_str_less(a : String, b : String) -> Bool {
  let ca = @engine.to_chars(a)
  let cb = @engine.to_chars(b)
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
  let chars = @engine.to_chars(value)
  let prefix_chars = @engine.to_chars(prefix)
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
fn render_val(value : @engine.Value) -> String {
  match value {
    @engine.VStr(text) => text
    @engine.VBool(flag) => if flag { "true" } else { "false" }
    @engine.VNum(number) => {
      let integer = number.to_int()
      if integer.to_double() == number {
        integer.to_string()
      } else {
        number.to_string()
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 3 — LSec 5-face 断面 model + renderers + projectors (mirrors slice/poc/lower_runner_wbtest.mbt)
// ═══════════════════════════════════════════════════════════════════════════════

///|
struct LEnt {
  name : String
  typ : String
  default_ : @engine.Value?
  env : String?
  inherit_ : Bool
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
  GSet(String, @engine.Value, String)
  GEff(String, String, @engine.EffectOp)
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
  match e.default_ {
    Some(v) => fs.push("default=" + render_val(v))
    None => ()
  }
  match e.env {
    Some(k) => fs.push("env=" + k)
    None => ()
  }
  if e.inherit_ {
    fs.push("inherit_=true")
  }
  match e.config_key {
    Some(p) => fs.push("config_key=[" + join_comma(p) + "]")
    None => ()
  }
  match e.accum {
    Some(a) => fs.push("accumulator=" + a)
    None => ()
  }
  // DR-105 §1: omit-if-false, mirrors `inherit_=true` above — the common (undeclared) case renders
  // no `flatten` field at all so pre-DR-105 "lower" fixtures without the key still compare equal.
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
    CRequires(el, ts) =>
      "requires{element=" + el + ",targets=[" + sorted(ts) + "]}"
    CConflicts(el, ts) =>
      "conflicts_with{element=" + el + ",targets=[" + sorted(ts) + "]}"
    CRequiresIf(entity, branch_id, v, ts) =>
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
    CExclusive(g, ms) =>
      "exclusive_group{group=" + g + ",members=[" + sorted(ms) + "]}"
    CRequired(el, cands) => {
      // @engine.RequiredCandidate.name のみ projection (codex M-2 修正で候補が wrapper 付きになったが、
      // lowering 断面はまだ CRequired/CRequiredGroup を対象にした fixture が無い — wrapper 込みの
      // 表記が必要になったら拡張する)。
      let names : Array[String] = []
      for c in cands {
        names.push(c.name)
      }
      "required{element=" + el + ",candidates=[" + sorted(names) + "]}"
    }
    CRequiredGroup(g, ms) => {
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
fn lower_eff_op(op : @engine.EffectOp) -> String {
  match op {
    @engine.Set => "set"
    @engine.Default => "default"
    @engine.Unset => "unset"
    @engine.Empty => "empty"
    @engine.Update(transform, args) =>
      if args.length() == 0 {
        "update:" + transform
      } else {
        "update:" + transform + ":" + join_comma(args)
      }
    // DR-080 §2 merge accumulator piece markers (eff_op と同じ語彙、lower path 用の並行実装)。
    @engine.Remove => "remove"
    @engine.Splice => "splice"
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
  match @builtins.node_resident_name(node) {
    Some(name) => Some(name)
    None =>
      match node {
        @engine.ReqArg(name) => Some(name)
        _ => None
      }
  }
}

///|
fn test_node_is_failure_mark(node : @engine.Node) -> Bool {
  node is @engine.Ext(extension) && extension.is_failure_action()
}

///|
fn test_node_effect_mark(node : @engine.Node) -> (String, @engine.EffectOp)? {
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
  matcher : &@engine.MatcherExt,
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
      depr=false,
    ),
  ])
  assert_eq(matcher.candidates().length(), 0)
  assert_eq(proj_matcher_entries(matcher), [("--verbose", "verbose")])
}

///|
fn proj_greedy(node : @engine.Node, reg : Map[String, @engine.Node]) -> GItem {
  match node {
    @engine.DdSat(name) => GExact(name)
    // DR-090: no golden lowering fixture exercises this yet (spec fixtures for DR-090 are
    // "query":"parse"輪郭, not lowering shape comparisons) — minimal, informative encoding via
    // the existing GMatch shape rather than inventing a new GItem variant for an untested path.
    @engine.DdMatchSat(spelling, is_pattern, self_keep, _) =>
      GMatch("dd_match:" + (if self_keep { "keep" } else { "drop" }), [
        (spelling, if is_pattern { "pattern" } else { "exact" }),
      ])
    @engine.Exact(s) => GExact(s)
    @engine.Rooted(inner, _) => proj_greedy(inner, reg)
    @engine.CmdSat(name, child) => GCmd(name, proj_scope(child, reg))
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
    // DR-083 §1: LEnt is the golden-fixture "5-face" oracle format, which only knows a scalar
    // default (`dec_lent` below decodes `"default"` via a single `json_to_value`, no accum-array
    // shape) — project the scalar face of `@engine.Entity.default_values` for this cross-check.
    default_: default_scalar(e),
    env: e.env_key,
    inherit_: e.inherit_,
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
fn canonical_registry_for_test() -> @engine.Registry {
  let registry = @engine.Registry::new()
  install(registry)
  registry
}

///|
fn registry_with_installers(
  installers : Array[&@engine.InstallerExt],
) -> @engine.Registry {
  let registry = @engine.Registry::new()
  for installer in installers {
    registry.register_installer(installer)
  }
  for
    node in [
      @builtins.string_arg("", []),
      @builtins.kv_arg("", []),
      @builtins.separated_arg(
        "",
        None,
        @builtins.string_type(),
        @engine.RError,
        false,
        @builtins.bool_config_canonical(),
        [],
        false,
      ),
      @builtins.number_arg("", false, []),
      @builtins.float_arg("", []),
      @builtins.int_arg("", @engine.RError, false, []),
      @builtins.bool_arg("", @builtins.bool_config_canonical(), []),
      @builtins.typed_arg("", @builtins.string_type(), []),
      @builtins.effect_mark("", @engine.Set),
      @builtins.deprecation_mark(""),
      @builtins.failure_mark(""),
    ] {
    guard node is @engine.Ext(resident) else {
      abort("builtin node factory did not return an Ext resident")
    }
    ignore(registry.register_node(resident))
  }
  ignore(registry.register_matcher(@builtins.eq_split("", [])))
  ignore(registry.register_matcher(@builtins.short_combine("", [], true)))
  for
    resident in [
      @builtins.string_type(),
      @builtins.number_type(),
      @builtins.int_type(),
      @builtins.float_type(),
      @builtins.bool_type(),
      @builtins.flag_type(),
      @builtins.count_type(),
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
      @builtins.from_entries_collector(@builtins.Entries),
    ),
  )
  registry
}

///|
fn canon_of(definition : Json, order : Array[&@engine.InstallerExt]) -> String {
  match
    parse_definition(definition, extensions=registry_with_installers(order)) {
    Ok(ast) => lsec_str(proj_scope(ast.root, ast.templates))
    Err(Malformed(reason)) => "ERR:" + reason
    Err(Rejected(errors)) => "ERR:" + deferrs_str(errors)
  }
}

///|
fn order_sig(order : Array[&@engine.InstallerExt]) -> String {
  let buf = StringBuilder::new()
  for x in order {
    buf.write_string(@builtins.owned_vocab(x))
    buf.write_string(";")
  }
  buf.to_string()
}

///|
fn pick3(
  order : Array[&@engine.InstallerExt],
) -> Array[Array[&@engine.InstallerExt]] {
  let ident : Array[&@engine.InstallerExt] = []
  for x in order {
    ident.push(x)
  }
  let rev : Array[&@engine.InstallerExt] = []
  let mut i = order.length() - 1
  while i >= 0 {
    rev.push(order[i])
    i = i - 1
  }
  let rot : Array[&@engine.InstallerExt] = []
  if order.length() > 0 {
    let mut j = 1
    while j < order.length() {
      rot.push(order[j])
      j = j + 1
    }
    rot.push(order[0])
  }
  let out : Array[Array[&@engine.InstallerExt]] = []
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

///|
fn run_lower(
  definition : Json,
  order : Array[&@engine.InstallerExt],
  want : LSec,
) -> String {
  let got = canon_of(definition, order)
  let wantS = lsec_str(want)
  let mut perm_ok = true
  for p in pick3(order) {
    if canon_of(definition, p) != got {
      perm_ok = false
    }
  }
  if !perm_ok {
    "PERM-DIVERGE|got=" + got + "|want=" + wantS
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
  order : Array[&@engine.InstallerExt]
  want : LSec
}

///|
fn dec_installer(name : String) -> &@engine.InstallerExt raise DecodeSkip {
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
) -> Array[&@engine.InstallerExt] raise DecodeSkip {
  match top.get("installers") {
    None => canonical_registry_for_test().installers()
    Some(j) =>
      match j.j_arr() {
        None => canonical_registry_for_test().installers()
        Some(a) => {
          let out : Array[&@engine.InstallerExt] = []
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
  // DR-045 effect descriptor (`{exact, link, effect: {op, transform?, args?}}`) — the non-@engine.Set ops
  // (default/unset/empty/update, DR-011/077) that lower to `@engine.Seq([@engine.Exact, effect resident])` (see the
  // `[@engine.Exact(t), effect resident] => GEff(t, n, op)` projection below). No `lower fixture` used this
  // shape before DR-077 (every prior lowering fixture only exercised @engine.Set), so this decode path is
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
fn dec_eff_op(o : Map[String, Json]) -> @engine.EffectOp raise DecodeSkip {
  let opstr = match jf_str(o, "op") {
    Some(s) => s
    None => raise DecodeSkip("effect missing 'op'")
  }
  match opstr {
    "set" => @engine.Set
    "default" => @engine.Default
    "unset" => @engine.Unset
    "empty" => @engine.Empty
    "update" => {
      let transform = match jf_str(o, "transform") {
        Some(t) => t
        None => raise DecodeSkip("update effect missing 'transform'")
      }
      let args : Array[String] = match o.get("args") {
        Some(aj) =>
          match aj.j_arr() {
            Some(a) => {
              let r : Array[String] = []
              for e in a {
                match e.j_str() {
                  Some(s) => r.push(s)
                  None =>
                    raise DecodeSkip(
                      "update effect args element is not a string",
                    )
                }
              }
              r
            }
            None => raise DecodeSkip("update effect 'args' is not an array")
          }
        None => []
      }
      @engine.Update(transform, args)
    }
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
    [
      "type", "default", "env", "inherit", "config_key", "accumulator", "flatten",
    ],
    "golden entity",
  )
  let typ = req_field(o, "type")
  let default_ = match o.get("default") {
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
    default_,
    env: jf_str(o, "env"),
    inherit_: bool_field(o, "inherit", false),
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
      CRequires(req_field(o, "element"), dec_strs(o.get("targets")))
    }
    "conflicts_with" => {
      allowed_keys(
        o,
        ["kind", "element", "targets"],
        "conflicts_with constraint",
      )
      CConflicts(req_field(o, "element"), dec_strs(o.get("targets")))
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
      CRequiresIf(
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
      CExclusive(req_field(o, "group"), dec_strs(o.get("members")))
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
  let cs = @engine.to_chars(name)
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
/// lower query の fixture 全件を decode し、期待する 5 面断面と installer 順序 3 種の結果を比較する。
/// decode skip・断面差分・順序差分はいずれも失敗として返し、blackbox conformance runner が
/// result/outcome の公開面だけを扱っても lowering 内部構造の保証を失わないようにする。
fn verify_lower_conformance_fixtures() -> Unit {
  let root = fixtures_root()
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
    let verdict = run_lower(fixture.definition, fixture.order, fixture.want)
    if verdict != "PASS" {
      mismatches.push(rel + "::lower :: " + verdict)
    }
  }
  if decoded == 0 || skips.length() > 0 || mismatches.length() > 0 {
    let report = StringBuilder::new()
    report.write_string(
      "lower conformance failed: decoded=" + decoded.to_string() + "\n",
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
