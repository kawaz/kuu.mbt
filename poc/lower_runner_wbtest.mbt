// lower_runner_wbtest.mbt — Phase 2-② lowering conformance fixture runner (query: "lower").
//
// PURPOSE: a *verification instrument* (not product code) for the `query: "lower"`
// fixtures of kawaz/kuu:fixtures/lowering/*. It feeds each fixture's wire-form
// definition through the slice's parse_definition (with the fixture's installer
// SUBSET, DR-070 §1 部分適用), projects the resulting canon Scope into the DR-063 §3
// 5-face 断面 (normal form), and loose-compares (DR-070 §2 / LOWERING §C.5) against
// the fixture's golden `expect`. Its job is to surface (a) fixture-authoring errors
// and (b) slice/spec divergences — the golden is the spec正本 (DR-070 §1b), NOT a
// mirror of the slice's current behavior, so a divergence is a KNOWN GAP to record.
//
// The definitions + expected 断面 are transcribed BY HAND from the JSON fixtures (a
// JSON decoder is out of scope for this PoC, CONFORMANCE §1 "definition は wire form";
// same convention as fixture_runner_wbtest.mbt).
//
// PROJECTION → NORMAL FORM (DR-063 §3):
//   greedy 面   — SET-compared (DR-070 §2): sorted item strings
//   positional 面 — ORDER-compared (消費順が意味論): item strings in spine order
//   entities 面 — object, key order non-normative: minimal projection, sorted
//   constraints 面 — SET-compared: sorted
//   templates 面 — object keyed by `#` 予約名前空間の内部名 (綴り非規範): sorted
//   consumption points collapse to the ref+link 宣言形 (slice の inline StrArg/NumArg
//     → {ref, link}); matcher → {matcher, entries} (entries as an OBJECT: unique keys,
//     so a duplicate re-derived entry — DR-070 §1b gap 6 — is masked here as it is in
//     the golden JSON object); nested command scope → {exact, scope: 5-face} recursively.
//
// LOOSE COMPARISON (DR-070 §2 / DR-063 §3): structural skeleton + matcher kind/entry
// table, IGNORING (a) internal id spelling (`#`-names normalized to `<prefix>#T`,
// masking the slice's `src` vs the golden's `src#cons`), (b) 席 (entity) 記載順.

// ── 断面 model (the DR-063 §3 normal form as comparable data) ──────────────────

///|
/// A value cell (entity) in the 断面, minimally projected (only meaningful fields).
struct LEnt {
  name : String
  typ : String // string | number | int | bool | config_file (仕様語彙, DR-063 §3)
  default_ : Value?
  env : String?
  inherit : Bool
  config_key : Array[String]?
  accum : String?
}

///|
/// A greedy-face 断面 item.
enum GItem {
  GExact(String) // {exact: "--"} — dd marker / bare trigger
  GSet(String, Value, String) // set descriptor 縮退形 {exact, value, link} (DR-045)
  GEff(String, String, EffectOp) // non-set effect {exact, link, effect:{op}} (unused in the 18, kept for completeness)
  GSeqSat(String, String) // value satellite {seq:[{exact}, {ref, link}]} — carries trigger + refname (link=refname)
  GMatch(String, Array[(String, String)]) // {matcher: kind, entries: {key -> name}} (entries deduped by key = object semantics)
  GCmd(String, LSec) // {exact: name, scope: 5-face} — command subtree
}

///|
/// A positional / template-body node (the ref+link / template-ref / seq shapes).
enum TNode {
  TSeq(Array[TNode]) // {seq: [...]} — ordered
  TRefEnt(String) // {ref: name, link: name} — a value cell consumption point (entity ref)
  TRefTmpl(String, Bool) // {ref: <canon #-id>, optional?} — a template ref (no link)
  TExact(String) // {exact: s}
}

///|
/// A scope 断面: the DR-063 §3 five faces. Empty faces are omitted at render (最小投影),
/// so an empty child scope renders as "" (= golden `scope: {}`).
struct LSec {
  greedy : Array[GItem]
  positionals : Array[TNode]
  entities : Array[LEnt]
  constraints : Array[Constraint] // reuse the slice's Constraint enum (same 4 値, DR-063 §3)
  templates : Array[(String, TNode)] // (canon #-id, body)
}

// ── canonical id normalization (DR-063 §3: `#` id 綴りは非規範) ─────────────────

///|
/// Normalize a template id to `<prefix-before-#>#T`. The slice keys the repeat cons
/// template by the ELEMENT name (`src`) — the ambiguous form DR-063 §3 warns against —
/// while the golden uses the `#`-qualified `src#cons`; both collapse here to `src#T`,
/// so the loose comparison ignores the spelling difference.
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

// ── renderers (produce the canonical comparison string) ───────────────────────

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
  if e.inherit {
    fs.push("inherit=true")
  }
  match e.config_key {
    Some(p) => fs.push("config_key=[" + join_comma(p) + "]")
    None => ()
  }
  match e.accum {
    Some(a) => fs.push("accumulator=" + a)
    None => ()
  }
  sort_items(fs)
  e.name + "{" + join_comma(fs) + "}"
}

///|
fn lcon_str(c : Constraint) -> String {
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
    CRequiresIf(el, v, ts) =>
      "requires_if{element=" +
      el +
      ",value=" +
      v +
      ",targets=[" +
      sorted(ts) +
      "]}"
    CExclusive(g, ms) =>
      "exclusive_group{group=" + g + ",members=[" + sorted(ms) + "]}"
  }
}

///|
fn gmatch_entries_str(entries : Array[(String, String)]) -> String {
  // Object semantics: unique keys. A duplicate re-derived entry (same key→name) is
  // masked (gap 6); a genuine key conflict (same key, different name) surfaces as
  // "name1!name2" so it is not silently swallowed.
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
    if not(found) {
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
fn lower_eff_op(op : EffectOp) -> String {
  match op {
    Set => "set"
    Default => "default"
    Unset => "unset"
    Empty => "empty"
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
      "seq[" + join_comma(items) + "]" // ordered (no sort)
    }
    TRefEnt(n) => "ref{" + n + ",link=" + n + "}"
    TRefTmpl(id, opt) =>
      "ref{" + id + (if opt { ",optional" } else { "" }) + "}"
    TExact(s) => "exact(" + s + ")"
  }
}

///|
/// Render a 5-face 断面 to its canonical comparison string. Empty faces are omitted
/// (最小投影) so an empty scope renders as "".
fn lsec_str(s : LSec) -> String {
  let parts : Array[String] = []
  if s.greedy.length() > 0 {
    let items : Array[String] = []
    for g in s.greedy {
      items.push(gitem_str(g))
    }
    sort_items(items) // greedy = SET (DR-070 §2)
    parts.push("G[" + join_comma(items) + "]")
  }
  if s.positionals.length() > 0 {
    let items : Array[String] = []
    for p in s.positionals {
      items.push(tnode_str(p)) // positional = ORDER (消費順)
    }
    parts.push("P[" + join_comma(items) + "]")
  }
  if s.entities.length() > 0 {
    let items : Array[String] = []
    for e in s.entities {
      items.push(lent_str(e))
    }
    sort_items(items) // entities object, key order non-normative
    parts.push("E[" + join_comma(items) + "]")
  }
  if s.constraints.length() > 0 {
    let items : Array[String] = []
    for c in s.constraints {
      items.push(lcon_str(c))
    }
    sort_items(items) // constraints = SET (DR-063 §3)
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

///|
fn join_pipe(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in items {
    if not(first) {
      buf.write_string("|")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

// ── projection: slice canon Scope → 断面 LSec ─────────────────────────────────

///|
/// The name a value primitive binds (its entity), for the ref+link collapse.
fn prim_name(n : Node) -> String? {
  match n {
    StrArg(x) => Some(x)
    NumArg(x) => Some(x)
    SepArg(x, _) => Some(x)
    FilterArg(x, _) => Some(x)
    ReqArg(x) => Some(x)
    NoDashStr(x) => Some(x)
    _ => None
  }
}

///|
fn proj_seq_sat(xs : Array[Node]) -> GItem {
  // A greedy value/flag/variant satellite: xs[0] = Exact(trigger). The tail decides the
  // descriptor form (DR-045): Bind → set 縮退形; EffMark → effect; a value primitive →
  // {seq:[exact, {ref, link}]}. FailMark/DeprMark riders are inert for the 断面.
  match xs {
    [Exact(t), Bind(n, v)] => GSet(t, v, n)
    [Exact(t), Bind(n, v), FailMark(_)] => GSet(t, v, n)
    [Exact(t), Bind(n, v), DeprMark(_)] => GSet(t, v, n)
    [Exact(t), EffMark(n, op)] => GEff(t, n, op)
    [Exact(t), tail] =>
      match prim_name(tail) {
        Some(n) => GSeqSat(t, n)
        None => GExact("?seq:" + "\{Seq(xs)}")
      }
    _ => GExact("?seq:" + "\{Seq(xs)}")
  }
}

///|
fn proj_greedy(node : Node, reg : Map[String, Node]) -> GItem {
  match node {
    DdSat(name) => GExact(name)
    Exact(s) => GExact(s)
    Rooted(inner) => proj_greedy(inner, reg) // link-sync wrapper is transparent in the 断面
    CmdSat(name, child) => GCmd(name, proj_scope(child, reg))
    NativeMatch(EqSplit(prefix~, entries~)) => {
      let es : Array[(String, String)] = []
      for e in entries {
        es.push((prefix + e.key, e.name)) // golden key = prefix + spelling (--port)
      }
      GMatch("eq_split", es)
    }
    NativeMatch(ShortCombine(prefix=_, entries~)) => {
      let es : Array[(String, String)] = []
      for e in entries {
        es.push(("\{e.ch}", e.name)) // golden key = the single char (p), no prefix
      }
      GMatch("short_combine", es)
    }
    Seq(xs) => proj_seq_sat(xs)
    other => GExact("?greedy:" + "\{other}")
  }
}

///|
fn proj_pos(node : Node) -> TNode {
  match node {
    Ref(k) => TRefTmpl(canon_tmpl(k), false) // spine template ref (repeat cons)
    Seq(xs) => {
      let items : Array[TNode] = []
      for x in xs {
        items.push(proj_tnode(x))
      }
      TSeq(items)
    }
    other =>
      match prim_name(other) {
        Some(n) => TRefEnt(n) // value positional → {ref, link}
        None => TExact("?pos:" + "\{other}")
      }
  }
}

///|
/// Project a template-body node (DR-063 §3 templates 面). `Or([x, Seq([])])` = opt_node =
/// the optional wrapper; its inner ref becomes an `optional` template ref.
fn proj_tnode(node : Node) -> TNode {
  match node {
    Seq(xs) => {
      let items : Array[TNode] = []
      for x in xs {
        items.push(proj_tnode(x))
      }
      TSeq(items)
    }
    Or([inner, Seq([])]) =>
      match inner {
        Ref(k) => TRefTmpl(canon_tmpl(k), true)
        other => proj_tnode(other) // best effort (no other optional shapes in the 18)
      }
    Ref(k) => TRefTmpl(canon_tmpl(k), false)
    Exact(s) => TExact(s)
    other =>
      match prim_name(other) {
        Some(n) => TRefEnt(n)
        None => TExact("?tnode:" + "\{other}")
      }
  }
}

///|
fn proj_entity(e : Entity) -> LEnt {
  let typ = if e.is_config_file {
    "config_file"
  } else {
    match e.ty {
      TStr => "string"
      TNum => "number"
      TInt => "int"
      TFlag => "bool" // §A.5: a flag cell is observationally a bool
    }
  }
  {
    name: e.name,
    typ,
    default_: e.default_value,
    env: e.env_key,
    inherit: e.inherit,
    config_key: e.config_key, // config_seat (同型 default) is internal — not projected
    accum: e.accum,
  }
}

///|
/// Collect the template ids referenced from a node list (transitive through bodies).
fn collect_reftmpls(
  nodes : Array[Node],
  reg : Map[String, Node],
  out : Array[String],
) -> Unit {
  fn is_tmpl_key(k : String) -> Bool {
    // a repeat cons template (registered under the element name); skip the "lazy:" markers.
    not(str_has_prefix(k, "lazy:")) && reg.get(k) is Some(_)
  }

  fn walk(n : Node) -> Unit {
    match n {
      Ref(k) =>
        if is_tmpl_key(k) && not(str_in(out, k)) {
          out.push(k)
          match reg.get(k) {
            Some(body) => walk(body)
            None => ()
          }
        }
      Seq(xs) =>
        for x in xs {
          walk(x)
        }
      Or(xs) =>
        for x in xs {
          walk(x)
        }
      Many(inner) => walk(inner)
      BoundedTail(inner, _, _) => walk(inner)
      Scoped(_, inner) => walk(inner)
      Rooted(inner) => walk(inner)
      _ => ()
    }
  }

  for n in nodes {
    walk(n)
  }
}

///|
fn str_has_prefix(s : String, pre : String) -> Bool {
  let cs = to_chars(s)
  let cp = to_chars(pre)
  if cp.length() > cs.length() {
    return false
  }
  let mut i = 0
  while i < cp.length() {
    if cs[i] != cp[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// Project a canon Scope into its 5-face 断面. `reg` is the parse_definition registry
/// (carries the repeat cons templates). Templates are attached to the scope that
/// references them on its spine (child scopes in the 18 reference none).
fn proj_scope(sc : Scope, reg : Map[String, Node]) -> LSec {
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
  let constraints : Array[Constraint] = []
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

// ── expected-断面 builders (hand-transcribed golden `expect`) ──────────────────

///|
fn le(
  name : String,
  typ : String,
  default_? : Value? = None,
  env? : String? = None,
  inherit? : Bool = false,
  config_key? : Array[String]? = None,
  accum? : String? = None,
) -> LEnt {
  { name, typ, default_, env, inherit, config_key, accum }
}

///|
/// The repeat cons template body (the only template shape in the 18): the golden
/// `{seq:[{ref:name,link:name},{ref:name#cons,optional:true}]}`.
fn cons_tmpl(name : String) -> (String, TNode) {
  (canon_tmpl(name), TSeq([TRefEnt(name), TRefTmpl(canon_tmpl(name), true)]))
}

///|
fn lsec(
  greedy? : Array[GItem] = [],
  positionals? : Array[TNode] = [],
  entities? : Array[LEnt] = [],
  constraints? : Array[Constraint] = [],
  templates? : Array[(String, TNode)] = [],
) -> LSec {
  { greedy, positionals, entities, constraints, templates }
}

// ── the runner (突合 + 順列検査) ───────────────────────────────────────────────

///|
let full_chain : Array[Installer] = [
  LongInst,
  ShortInst,
  EnvInst,
  DdInst,
  CommandInst,
  GlobalInst,
  InheritInst,
  RepeatInst,
  MultipleInst,
  ConfigInst,
  ConstraintInst,
  AliasInst,
  InheritableInst,
]

///|
/// The canonical 断面 string of one lowering, or "ERR:<sorted deferrs>" on a
/// definition-time failure (so an unowned-vocab abort is a comparable value, not a crash).
fn canon_of(def : Definition, order : Array[Installer]) -> String {
  let reg : Map[String, Node] = Map::new()
  match parse_definition(def, order, registry=reg) {
    Ok(sc) => lsec_str(proj_scope(sc, reg))
    Err(e) => "ERR:" + deferrs_str(e)
  }
}

///|
/// DR-070 §3 常時分: 3 deterministically-chosen permutations (identity / reverse /
/// rotate-by-1), deduped. Full-permutation opt-in (nightly) is out of scope — HOOK: a
/// `pick_all(order)` using `permutations()` would slot in here behind an explicit flag.
fn pick3(order : Array[Installer]) -> Array[Array[Installer]] {
  let ident : Array[Installer] = []
  for x in order {
    ident.push(x)
  }
  let rev : Array[Installer] = []
  let mut i = order.length() - 1
  while i >= 0 {
    rev.push(order[i])
    i = i - 1
  }
  let rot : Array[Installer] = []
  if order.length() > 0 {
    let mut j = 1
    while j < order.length() {
      rot.push(order[j])
      j = j + 1
    }
    rot.push(order[0])
  }
  // dedup by string signature
  let out : Array[Array[Installer]] = []
  let sigs : Array[String] = []
  for cand in [ident, rev, rot] {
    let sig = order_sig(cand)
    if not(str_in(sigs, sig)) {
      sigs.push(sig)
      out.push(cand)
    }
  }
  out
}

///|
fn order_sig(order : Array[Installer]) -> String {
  let buf = StringBuilder::new()
  for x in order {
    buf.write_string("\{x};")
  }
  buf.to_string()
}

///|
/// Run one fixture: project + loose-compare against `want`, and check DR-070 §3
/// permutation convergence (the projected canon must be identical under pick3). Returns
/// "PASS" or a divergence classification (frozen with inspect so drift is caught).
fn run_lower(def : Definition, order : Array[Installer], want : LSec) -> String {
  let got = canon_of(def, order)
  let wantS = lsec_str(want)
  // permutation convergence (order-independence, LOWERING §C.2 / DR-042): every pick3
  // permutation must project to the SAME canon (holds even when `got` diverges from the
  // golden — order-independence is a property of the slice's own output).
  let mut perm_ok = true
  for p in pick3(order) {
    if canon_of(def, p) != got {
      perm_ok = false
    }
  }
  if not(perm_ok) {
    "PERM-DIVERGE|got=" + got + "|want=" + wantS
  } else if got == wantS {
    "PASS"
  } else {
    "DIVERGE|got=" + got + "|want=" + wantS
  }
}

// ── the 18 fixtures ────────────────────────────────────────────────────────────
// Each `test` transcribes ONE fixtures/lowering/<area>/<name>.json: its wire-form
// definition + installer subset + golden 断面. The verdict is frozen with inspect
// (like fixture_runner_wbtest.mbt): "PASS" for a spec-conformant lowering, or a
// "DIVERGE|got=…|want=…" string that FREEZES an observed slice divergence so drift
// is caught. All 18 fixtures pass.
//
// ── long two-form (LOWERING §B.1 / DR-071) ─────────────────────────────────────
// `long : Array[String]` is the DR-071 two-form main-entry spelling list. The spec's
// `long: true` (最頻ケース) is the sugar `[":set"]`; a fixture transcribes it as `long=[":set"]`,
// which normalize_surface expands to the name-derived `--<kebab(name)>`. **absent = false = [] =
// 入口なし** (all同義, no presence distinction) — options that declare no long (env-only /
// short-only / inherit-only / multiple-only / config_key-only) simply omit it (default `[]`) and
// mint NO `--<name>` trigger, spec-correct per DR-070 §1b. A variant entry (`no:set:false`) is
// pre-parsed into `variants`; `:set` stays in `long`.

// baseline/no-installers.json — installers=[] (A群純構文正規化のみ, §C.4)。裸 positional x。

///|
test "lower baseline/no-installers: identity core lowering (installers=[])" {
  inspect(
    run_lower(
      def_([], [pos("x", TStr)]),
      [],
      lsec(positionals=[TRefEnt("x")], entities=[le("x", "string")]),
    ),
    content="PASS",
  )
}

// long/basic.json — installers=[long]。`long: true` 糖衣 = [":set"] → --port + eq_split。

///|
test "lower long/basic: long installer 主入口 (space form + eq-split, LOWERING §B.1)" {
  inspect(
    run_lower(
      def_([opt("port", TNum, long=[":set"])], []),
      [LongInst],
      lsec(
        greedy=[
          GSeqSat("--port", "port"),
          GMatch("eq_split", [("--port", "port")]),
        ],
        entities=[le("port", "number")],
      ),
    ),
    content="PASS",
  )
}

// long/variant.json — installers=[long]。`long: [":set", "no:set:false"]`: 主入口 :set + no:set:false variant (bool ssl, default true)。

///|
test "lower long/variant: variant DSL lowers to {exact, value, link} effect satellites" {
  inspect(
    run_lower(
      def_(
        [
          opt("ssl", TFlag, long=[":set"], default=Some(VBool(true)), variants=[
            { trigger: "no-ssl", op: Set, operand: Some(VBool(false)) },
          ]),
        ],
        [],
      ),
      [LongInst],
      lsec(
        greedy=[
          GSet("--ssl", VBool(true), "ssl"),
          GSet("--no-ssl", VBool(false), "ssl"),
        ],
        entities=[le("ssl", "bool", default_=Some(VBool(true)))],
      ),
    ),
    content="PASS",
  )
}

// short/basic.json — installers=[short]。port(short p) + verbose(flag short v)。
// port & verbose declare NO long (`long=[]`, DR-071 入口なし) → normalize invents NO --port / --verbose,
// so [ShortInst] alone owns all vocab: a pure short_combine matcher, no long satellites.

///|
test "lower short/basic: short_combine matcher subsumes single-char (matcher-seat, §B.2)" {
  inspect(
    run_lower(
      def_(
        [opt("port", TNum, short=['p']), opt("verbose", TFlag, short=['v'])],
        [],
      ),
      [ShortInst],
      lsec(
        greedy=[GMatch("short_combine", [("p", "port"), ("v", "verbose")])],
        entities=[
          le("port", "number"),
          le("verbose", "bool", default_=Some(VBool(false))),
        ],
      ),
    ),
    content="PASS",
  )
}

// env/basic.json — installers=[env]。port(env PORT のみ、long なし)。
// port declares NO long (`long=[]`) → normalize invents no --port, so [EnvInst] owns all
// vocab: an env seat only, no structural satellite (§B.3).

///|
test "lower env/basic: env installer seats PORT, no structural satellite (§B.3)" {
  inspect(
    run_lower(
      def_([opt("port", TNum, env=["PORT"])], []),
      [EnvInst],
      lsec(entities=[le("port", "number", env=Some("PORT"))]),
    ),
    content="PASS",
  )
}

// dd/basic.json — installers=[dd]。dd marker (options[]) + positional x。

///|
test "lower dd/basic: dd installer adds a greedy exact satellite; x on the spine (§B.4)" {
  inspect(
    run_lower(
      def_([dd_marker()], [pos("x", TStr)]),
      [DdInst],
      lsec(greedy=[GExact("--")], positionals=[TRefEnt("x")], entities=[
        le("x", "string"),
      ]),
    ),
    content="PASS",
  )
}

// command/basic.json — installers=[command, long]。serve コマンド (子に long host)。

///|
test "lower command/basic: command subtree as a greedy {exact, scope} (§B.5 / DR-041 §4)" {
  inspect(
    run_lower(
      def_cmd([], [], [
        cmd("serve", def_([opt("host", TStr, long=[":set"])], [])),
      ]),
      [CommandInst, LongInst],
      lsec(greedy=[
        GCmd(
          "serve",
          lsec(
            greedy=[
              GSeqSat("--host", "host"),
              GMatch("eq_split", [("--host", "host")]),
            ],
            entities=[le("host", "string")],
          ),
        ),
      ]),
    ),
    content="PASS",
  )
}

// config/basic.json — installers=[config, long]。config_file (long=[":set"] → --config)
// + port(config_key, NO long)。port's empty long (`long=[]`) means normalize invents no
// --port even with [LongInst] in the chain, so port is sourced only from config (no satellite).

///|
test "lower config/basic: config seats; config_file value cell (DR-050)" {
  inspect(
    run_lower(
      def_(
        [
          opt("config", TStr, config_file=true, long=[":set"]),
          opt("port", TNum, config_key=Some(["server", "port"])),
        ],
        [],
      ),
      [ConfigInst, LongInst],
      lsec(
        greedy=[
          GSeqSat("--config", "config"),
          GMatch("eq_split", [("--config", "config")]),
        ],
        entities=[
          le("config", "config_file"),
          le("port", "number", config_key=Some(["server", "port"])),
        ],
      ),
    ),
    content="PASS",
  )
}

// constraint/basic.json — installers=[constraint, long]。decrypt requires key_file。

///|
test "lower constraint/basic: requires 遅延述語 (DR-055) + long satellites" {
  inspect(
    run_lower(
      def_(
        [
          opt("decrypt", TFlag, long=[":set"], requires=["key_file"]),
          opt("key_file", TStr, long=[":set"]),
        ],
        [],
      ),
      [ConstraintInst, LongInst],
      lsec(
        greedy=[
          GSet("--decrypt", VBool(true), "decrypt"),
          GSeqSat("--key-file", "key_file"),
          GMatch("eq_split", [("--key-file", "key_file")]),
        ],
        entities=[
          le("decrypt", "bool", default_=Some(VBool(false))),
          le("key_file", "string"),
        ],
        constraints=[CRequires("decrypt", ["key_file"])],
      ),
    ),
    content="PASS",
  )
}

// constraint/exclusive.json — installers=[constraint, long]。json/yaml 排他グループ。

///|
test "lower constraint/exclusive: exclusive_group 指定述語 (DR-047)" {
  inspect(
    run_lower(
      def_(
        [
          opt("json", TFlag, long=[":set"], exclusive=["format"]),
          opt("yaml", TFlag, long=[":set"], exclusive=["format"]),
        ],
        [],
      ),
      [ConstraintInst, LongInst],
      lsec(
        greedy=[
          GSet("--json", VBool(true), "json"),
          GSet("--yaml", VBool(true), "yaml"),
        ],
        entities=[
          le("json", "bool", default_=Some(VBool(false))),
          le("yaml", "bool", default_=Some(VBool(false))),
        ],
        constraints=[CExclusive("format", ["json", "yaml"])],
      ),
    ),
    content="PASS",
  )
}

// global/with-long.json — installers=[global, long, command]。verbose(global) + build。

///|
test "lower global/with-long: global copy 不動点展開 into the child scope (§B.6)" {
  inspect(
    run_lower(
      def_cmd([opt("verbose", TFlag, long=[":set"], global=true)], [], [
        cmd("build", def_([], [])),
      ]),
      [GlobalInst, LongInst, CommandInst],
      lsec(
        greedy=[
          GSet("--verbose", VBool(true), "verbose"),
          GCmd(
            "build",
            lsec(greedy=[GSet("--verbose", VBool(true), "verbose")]),
          ),
        ],
        entities=[le("verbose", "bool", default_=Some(VBool(false)))],
      ),
    ),
    content="PASS",
  )
}

// inherit/basic.json — installers=[inherit]。ttl(inherit seat のみ, NO long)。
// ttl's empty long (`long=[]`) → normalize invents no --ttl, so [InheritInst] alone owns
// all vocab: just the inherit ladder rung, no long satellite.

///|
test "lower inherit/basic: inherit installer seats the inherit ladder rung (DR-031)" {
  inspect(
    run_lower(
      def_([opt("ttl", TNum, inherit=true)], []),
      [InheritInst],
      lsec(entities=[le("ttl", "number", inherit=true)]),
    ),
    content="PASS",
  )
}

// inheritable/with-long.json — installers=[inheritable, long, command]。子 ttl を祖先へ。

///|
test "lower inheritable/with-long: reverse-of-global 逆方向コピー (DR-059)" {
  inspect(
    run_lower(
      def_cmd([], [], [
        cmd(
          "sub",
          def_([opt("ttl", TNum, long=[":set"], inheritable=true)], []),
        ),
      ]),
      [InheritableInst, LongInst, CommandInst],
      lsec(
        greedy=[
          GSeqSat("--sub-ttl", "ttl"),
          GMatch("eq_split", [("--sub-ttl", "ttl")]),
          GCmd(
            "sub",
            lsec(
              greedy=[
                GSeqSat("--ttl", "ttl"),
                GMatch("eq_split", [("--ttl", "ttl")]),
              ],
              entities=[le("ttl", "number", inherit=true)],
            ),
          ),
        ],
        entities=[le("ttl", "number", inherit=true)],
      ),
    ),
    content="PASS",
  )
}

// multiple/basic.json — installers=[multiple]。tag(append accumulator, NO long)。
// tag's empty long (`long=[]`) → normalize invents no --tag, so [MultipleInst] alone owns
// all vocab: just the append accumulator, no long satellite.

///|
test "lower multiple/basic: multiple installs the append accumulator (DR-034)" {
  inspect(
    run_lower(
      def_([opt("tag", TStr, multiple=true)], []),
      [MultipleInst],
      lsec(entities=[le("tag", "string", accum=Some("append"))]),
    ),
    content="PASS",
  )
}

// repeat/basic.json — installers=[repeat]。src(repeat min:1) + dst。cons unfold。

///|
test "lower repeat/basic: repeat unfolds to a cons template + flatten (§B.8 / DR-043)" {
  inspect(
    run_lower(
      def_([], [pos("src", TStr, repeat=rep(1)), pos("dst", TStr)]),
      [RepeatInst],
      lsec(
        positionals=[TRefTmpl(canon_tmpl("src"), false), TRefEnt("dst")],
        entities=[
          le("src", "string", accum=Some("flatten")),
          le("dst", "string"),
        ],
        templates=[cons_tmpl("src")],
      ),
    ),
    content="PASS",
  )
}

// alias/basic.json — installers=[alias, long, short]。port + alias short n。

///|
test "lower alias/basic: alias entry-copy re-derives entries; long dup masked (gap 6)" {
  inspect(
    run_lower(
      def_([opt("port", TInt, long=[":set"], short=['p'])], [], aliases=[
        alias("port", short=['n']),
      ]),
      [AliasInst, LongInst, ShortInst],
      lsec(
        greedy=[
          GSeqSat("--port", "port"),
          GMatch("eq_split", [("--port", "port")]),
          GMatch("short_combine", [("p", "port"), ("n", "port")]),
        ],
        entities=[le("port", "int")],
      ),
    ),
    content="PASS",
  )
}

// alias/command.json — installers=[alias, command]。checkout + co alias。

///|
test "lower alias/command: command alias clones the subtree (empty scope) (DR-057 §2)" {
  inspect(
    run_lower(
      def_cmd([], [], [cmd("checkout", def_([], []))], aliases=[
        alias("checkout", name=Some("co")),
      ]),
      [AliasInst, CommandInst],
      lsec(greedy=[GCmd("checkout", lsec()), GCmd("co", lsec())]),
    ),
    content="PASS",
  )
}

// baseline/converged.json — installers 省略 (= 全登録)。8 installer の kitchen-sink。
// verbose declares NO long (short-only, `long=[]`): even with LongInst in the full chain, normalize
// invents no --verbose, so the golden carries only its short_combine seat. port declares
// `long=[":set"]` (--port) and host too (--host in the serve subtree). Projection of the
// command subtree, eq_split/short_combine, dd exact, repeat cons template src#T, and the
// minimal entities all agree — the whole kitchen-sink converges to the spec golden.

///|
test "lower baseline/converged: 全収束 kitchen-sink (installers 省略 = full chain)" {
  inspect(
    run_lower(
      def_cmd(
        [
          opt("port", TNum, long=[":set"], short=['p'], env=["PORT"]),
          opt("verbose", TFlag, short=['v']),
          dd_marker(),
        ],
        [pos("src", TStr, repeat=rep(1))],
        [cmd("serve", def_([opt("host", TStr, long=[":set"])], []))],
      ),
      full_chain,
      lsec(
        greedy=[
          GSeqSat("--port", "port"),
          GMatch("eq_split", [("--port", "port")]),
          GMatch("short_combine", [("p", "port"), ("v", "verbose")]),
          GExact("--"),
          GCmd(
            "serve",
            lsec(
              greedy=[
                GSeqSat("--host", "host"),
                GMatch("eq_split", [("--host", "host")]),
              ],
              entities=[le("host", "string")],
            ),
          ),
        ],
        positionals=[TRefTmpl(canon_tmpl("src"), false)],
        entities=[
          le("port", "number", env=Some("PORT")),
          le("verbose", "bool", default_=Some(VBool(false))),
          le("src", "string", accum=Some("flatten")),
        ],
        templates=[cons_tmpl("src")],
      ),
    ),
    content="PASS",
  )
}
