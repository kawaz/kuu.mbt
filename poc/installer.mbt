// installer.mbt — parse_definition as a chain of installers (DR-042).
//
// An installer owns a special vocabulary (long / short / env / dd), and on each
// application: (1) READS its vocab from the definition (never deletes it — the
// declaration layer is read-only, invariant ①'), (2) implants greedy satellites
// / matchers / re-scoping via add-if-absent, (3) declares runtime seats (env).
// The 5 invariants keep the chain order-independent and idempotent; idempotency
// now comes from add-if-absent (not from consuming the vocab), and completeness
// is a "special vocab not owned by any installer in the chain" check.

/// UsefulAST element. Attribute arrays are READ-ONLY to installers (invariant ①':
/// 宣言層は読み取り専用). The declaration layer is never emptied — it stays inert so
/// help / diagnose / re-serialization keep the original declaration, and so a later
/// installer (global) can still see it. Idempotency is provided by add-if-absent on
/// the lowered contributions instead.
pub(all) struct ElemDef {
  name : String
  ty : Ty
  long : Array[String] // owned by the long installer
  short : Array[Char] // owned by the short installer
  env : Array[String] // owned by the env installer
  is_dd : Bool // owned by the dd installer (type:"dd")
  is_global : Bool // owned by the global installer (copied into descendant command scopes)
  is_inherit : Bool // owned by the inherit installer (declares an inherit seat)
  ref_target : String? // core (DR-020): this element IS a ref to a named template
  repeat : RepeatSpec? // owned by the repeat installer (DR-043)
  multiple : Bool // owned by the multiple installer (DR-034/043)
  default_value : Value?
} derive(Eq, Show)

/// A repeat closure (DR-043). `min` is the required rep count. The PoC realizes the
/// unbounded tail (an upper bound / max is out of scope) and requires min >= 1 on the
/// porous spine; min is the mandatory-head unroll. `lazy` picks the split preference:
/// greedy (default, longest share first) vs lazy (shortest first).
pub(all) struct RepeatSpec {
  min : Int
  lazy : Bool
} derive(Eq, Show)

/// A subcommand: a name + its own scope Definition (a fresh backbone, DR-041 §4).
pub(all) struct CommandDef {
  name : String
  body : Definition
} derive(Eq, Show)

/// UsefulAST for one command scope: entry-bearing options + positional face +
/// subcommands. `commands` is the DR-018 sugar; the command installer expands each
/// into a greedy exact trigger whose subtree is a NEW backbone (DR-041 §4).
pub(all) struct Definition {
  options : Array[ElemDef]
  positionals : Array[ElemDef]
  commands : Array[CommandDef]
} derive(Eq, Show)

/// The canonical installers (DR-042 §canonical installer セット + DR-043 repeat/multiple).
pub(all) enum Installer {
  LongInst
  ShortInst
  EnvInst
  DdInst
  CommandInst
  GlobalInst
  InheritInst
  RepeatInst
  MultipleInst
} derive(Eq, Show)

fn owned_vocab(i : Installer) -> String {
  match i {
    LongInst => "long"
    ShortInst => "short"
    EnvInst => "env"
    DdInst => "dd"
    CommandInst => "command"
    GlobalInst => "global"
    InheritInst => "inherit"
    RepeatInst => "repeat"
    MultipleInst => "multiple"
  }
}

/// Mutable build accumulator for ONE scope: installers only ADD (add-if-absent) to
/// greedy / declare seats of an entity in place / (dd only) contribute a greedy
/// satellite (invariant ②③). The build layer grows monotonically; the fixpoint
/// stops when a full pass over the whole tree adds nothing.
priv struct Build {
  greedy : Array[Node] // installers add-if-absent satellites/matchers
  entities : Array[Entity] // ensured per pass; env/inherit installers declare seats in place
  positional : Array[Node] // core lowering builds it; dd's semantics live in the evaluator
}

/// A node of the scope-builder tree, mirroring the Definition tree. `decl` is the
/// declaration layer (read-only vocab, but its `options` array GROWS when the global
/// installer copies a global option in — invariant ②). `build` is this scope's
/// lowered layer. `children` are the subcommand scopes (a fresh backbone each).
priv struct SB {
  decl : Definition
  build : Build
  children : Array[SBChild]
}

priv struct SBChild {
  name : String
  body : SB
}

fn value_prim(ty : Ty, name : String) -> Node {
  match ty {
    TNum => NumArg(name)
    _ => StrArg(name)
  }
}

fn copy_strs(a : Array[String]) -> Array[String] {
  let r : Array[String] = []
  for x in a {
    r.push(x)
  }
  r
}

fn copy_chars(a : Array[Char]) -> Array[Char] {
  let r : Array[Char] = []
  for x in a {
    r.push(x)
  }
  r
}

fn clone_elem(e : ElemDef) -> ElemDef {
  {
    name: e.name,
    ty: e.ty,
    long: copy_strs(e.long),
    short: copy_chars(e.short),
    env: copy_strs(e.env),
    is_dd: e.is_dd,
    is_global: e.is_global,
    is_inherit: e.is_inherit,
    ref_target: e.ref_target,
    repeat: e.repeat,
    multiple: e.multiple,
    default_value: e.default_value,
  }
}

fn clone_def(d : Definition) -> Definition {
  let os : Array[ElemDef] = []
  for e in d.options {
    os.push(clone_elem(e))
  }
  let ps : Array[ElemDef] = []
  for e in d.positionals {
    ps.push(clone_elem(e))
  }
  let cs : Array[CommandDef] = []
  for c in d.commands {
    cs.push({ name: c.name, body: clone_def(c.body) })
  }
  { options: os, positionals: ps, commands: cs }
}

/// The lowered head node for an element: a value primitive, or a `Ref` when the
/// element points at a shared template (`ref_target`, DR-020).
fn elem_head(e : ElemDef) -> Node {
  match e.ref_target {
    Some(r) => Ref(r)
    None => value_prim(e.ty, e.name)
  }
}

/// `Opt(X)` = `Or([X, Seq([])])` — the empty Seq matches zero tokens.
fn opt_node(x : Node) -> Node {
  Or([x, Seq([])])
}

/// Lower the positional face. A repeat element (DR-043) is lowered to a ref-recursion:
/// the template `name = Seq([head, Opt(Ref(name))])` is registered, and the spine gets
/// `min-1` mandatory heads followed by `Ref(name)` (>= 1 porous). A ref element without
/// repeat lowers to a plain `Ref(target)`; a value positional to its primitive. dd
/// positionals are NOT on the spine (the dd installer adds a greedy DdSat).
fn lower_positional(def : Definition, registry : Map[String, Node]) -> Array[Node] {
  let out : Array[Node] = []
  for e in def.positionals {
    if not_dd(e) {
      let head = elem_head(e)
      match e.repeat {
        None => out.push(head)
        Some(spec) => {
          registry.set(e.name, Seq([head, opt_node(Ref(e.name))]))
          // lazy marker under a mangled key the evaluator consults for split preference
          // (kept out of the Ref node so plain ref-to-template stays lazy-agnostic).
          if spec.lazy {
            registry.set("lazy:" + e.name, Exact("lazy"))
          }
          let m = if spec.min < 1 { 1 } else { spec.min }
          let mut k = 0
          while k < m - 1 {
            out.push(head) // mandatory unrolled heads (DR-043 min)
            k = k + 1
          }
          out.push(Ref(e.name)) // >= 1 porous recursive tail
        }
      }
    }
  }
  out
}

/// Build the scope-builder tree from a (cloned) Definition tree. The positional face
/// is lowered once here (it does not grow — global copies go to greedy); the entities
/// and greedy layers are filled by the fixpoint passes. `registry` collects the
/// ref-recursion templates for repeat lowering (DR-043).
fn init_sb(def : Definition, registry : Map[String, Node]) -> SB {
  let positional = lower_positional(def, registry)
  let children : Array[SBChild] = []
  for c in def.commands {
    children.push({ name: c.name, body: init_sb(c.body, registry) })
  }
  { decl: def, build: { greedy: [], entities: [], positional }, children }
}

/// Core lowering (not an installer — deterministic, order-independent): ensure one
/// entity (value cell, DR-030) per option and per non-dd positional, keyed by name
/// (add-if-absent). Runs every pass so global-copied options gain an entity too.
fn ensure_entities(sb : SB) -> Unit {
  for e in sb.decl.options {
    ensure_entity(sb.build, e)
  }
  for e in sb.decl.positionals {
    if not_dd(e) {
      ensure_entity(sb.build, e)
    }
  }
}

fn ensure_entity(build : Build, e : ElemDef) -> Unit {
  for ent in build.entities {
    if ent.name == e.name {
      return
    }
  }
  // repeat and multiple both make the cell a value LIST (the shared accumulator,
  // DR-043/036). Deterministic core lowering; RepeatInst/MultipleInst own the vocab
  // for completeness but the accumulator setup is a pure function of the decl.
  let accumulate = e.multiple ||
    (match e.repeat {
      Some(_) => true
      None => false
    })
  build.entities.push({
    name: e.name,
    ty: e.ty,
    env_key: None,
    inherit: false,
    accumulate,
    default_value: e.default_value,
  })
}

fn not_dd(e : ElemDef) -> Bool {
  !e.is_dd
}

// ── the four installers ──────────────────────────────────────────────────────

/// long: read `long`, add a greedy exact satellite per name (space form) and, for
/// value options, one eq-split matcher (`--k=v`). All contributions are add-if-absent
/// (invariant ①' non-deletion: the vocab is read, never removed). Satellites link to
/// the entity by name (DR-042 §展開の標準パターン).
fn inst_long(def : Definition, build : Build) -> Unit {
  let eq_entries : Array[LongEntry] = []
  for e in def.options {
    for l in e.long {
      let trigger = "--" + l
      match e.ty {
        TFlag => add_greedy(build, Seq([Exact(trigger), Bind(e.name, VBool(true))]))
        _ => {
          add_greedy(build, Seq([Exact(trigger), value_prim(e.ty, e.name)]))
          eq_entries.push({ key: l, name: e.name, kind: e.ty })
        }
      }
    }
  }
  if eq_entries.length() > 0 {
    add_greedy(build, NativeMatch(EqSplit(prefix="--", entries=eq_entries)))
  }
}

/// short: read `short`, add ONE cluster/value-attach matcher over all entries
/// (add-if-absent). In this PoC the single-char case (`-v`, `-p 8080`) is subsumed
/// by the matcher, so short adds no separate exact satellite (a matcher-seat
/// finding, see journal).
fn inst_short(def : Definition, build : Build) -> Unit {
  let sh_entries : Array[ShortEntry] = []
  for e in def.options {
    for c in e.short {
      sh_entries.push({ ch: c, name: e.name, kind: e.ty })
    }
  }
  if sh_entries.length() > 0 {
    add_greedy(build, NativeMatch(ShortCombine(prefix="-", entries=sh_entries)))
  }
}

/// env: read `env`, declare a lookup at the entity's env SEAT (invariant ④). It
/// does NOT wrap default_fn; the ladder order is engine-owned (DR-031). Declaring
/// the same seat again is a no-op (idempotent in-place set).
fn inst_env(def : Definition, build : Build) -> Unit {
  for e in def.options {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
    }
  }
  for e in def.positionals {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
    }
  }
}

fn seat_env(build : Build, name : String, key : String) -> Unit {
  for ent in build.entities {
    if ent.name == name {
      ent.env_key = Some(key)
    }
  }
}

/// dd: read `type:"dd"` and add a greedy exact satellite (DR-041 rev). The
/// satellite (DdSat) is a plain exact matcher on `--` that fires anywhere on the
/// spine; the evaluator severs the rest of the walk when it fires (internal-一体).
/// A real structural installer (exact satellite), symmetric with the other
/// greedy-face installers. Non-deletion: `is_dd` is read, never cleared.
fn inst_dd(def : Definition, build : Build) -> Unit {
  for e in def.positionals {
    if e.is_dd {
      add_greedy(build, DdSat("--"))
    }
  }
}

/// add-if-absent (invariant ①', non-deletion protocol): a contribution is added
/// only if no structurally-equal entry exists. Makes re-application a no-op and
/// keeps the fixpoint iteration convergent.
fn add_greedy(build : Build, g : Node) -> Unit {
  for existing in build.greedy {
    if existing == g {
      return
    }
  }
  build.greedy.push(g)
}

/// inherit: read `inherit`, declare an inherit SEAT on the entity (invariant ④,
/// DR-031 ladder cli>env>inherit>default). The seat's lookup — "nearest ancestor's
/// same-named entity value" — is resolved at runtime (resolve_command_tree). Like
/// env, this is a seat/capability declaration, not a structural contribution.
fn inst_inherit(def : Definition, build : Build) -> Unit {
  for e in def.options {
    if e.is_inherit {
      seat_inherit(build, e.name)
    }
  }
  for e in def.positionals {
    if e.is_inherit {
      seat_inherit(build, e.name)
    }
  }
}

fn seat_inherit(build : Build, name : String) -> Unit {
  for ent in build.entities {
    if ent.name == name {
      ent.inherit = true
    }
  }
}

/// global: read `global`, copy the option's declaration into descendant command
/// scopes (invariant ②: an addition to the DECLARATION layer, later expanded by
/// long/short in the child). Shadowing (DR-032/033, minimal scope): a scope that
/// already declares an option of the same name does NOT receive the copy — its own
/// wins. The copy keeps `is_global` so it re-propagates further down via the
/// fixpoint (level-by-level, so an intermediate shadow blocks its whole subtree).
fn inst_global(sb : SB) -> Unit {
  for opt in sb.decl.options {
    if opt.is_global {
      for child in sb.children {
        copy_global_into(child.body, opt)
      }
    }
  }
}

fn copy_global_into(child : SB, opt : ElemDef) -> Unit {
  for existing in child.decl.options {
    if triggers_overlap(existing, opt) {
      return // self-declared same trigger (shadow) or already-copied (idempotent)
    }
  }
  child.decl.options.push(clone_elem(opt))
}

/// Two options collide on a trigger if they share any long or short form. Shadowing
/// is by TRIGGER (DR: 同名トリガ), so a child declaring `--v` blocks a global `--v`
/// copy even under a different name.
fn triggers_overlap(a : ElemDef, b : ElemDef) -> Bool {
  for la in a.long {
    for lb in b.long {
      if la == lb {
        return true
      }
    }
  }
  for ca in a.short {
    for cb in b.short {
      if ca == cb {
        return true
      }
    }
  }
  false
}

// ── driver + completeness ────────────────────────────────────────────────────

/// Apply one installer to one scope node. long/short/env/dd/inherit contribute to
/// this node's build; global copies into descendants' declaration layers; command
/// is wired at materialization (its expansion is deterministic — greedy exact
/// trigger + new-backbone subtree, DR-018 / DR-041 §4).
fn apply_node(inst : Installer, sb : SB) -> Unit {
  match inst {
    LongInst => inst_long(sb.decl, sb.build)
    ShortInst => inst_short(sb.decl, sb.build)
    EnvInst => inst_env(sb.decl, sb.build)
    DdInst => inst_dd(sb.decl, sb.build)
    InheritInst => inst_inherit(sb.decl, sb.build)
    GlobalInst => inst_global(sb)
    CommandInst => () // wired at materialize (see materialize)
    RepeatInst => () // lowered deterministically in init_sb (ref-recursion + template)
    MultipleInst => () // accumulator flag set deterministically in ensure_entity
  }
}

/// One fixpoint pass over the whole tree: ensure entities (core), apply every
/// installer to this node, then recurse into subcommand scopes. Global copies into
/// children before the recursion, so a child sees the grown declaration in the same
/// pass regardless of global's position in `order`.
fn tree_pass(order : Array[Installer], sb : SB) -> Unit {
  ensure_entities(sb)
  for inst in order {
    apply_node(inst, sb)
  }
  for child in sb.children {
    tree_pass(order, child.body)
  }
}

/// Invariant ③: two installers owning the same vocab is a registration error.
fn check_registration(order : Array[Installer]) -> String? {
  let seen : Array[String] = []
  for inst in order {
    let v = owned_vocab(inst)
    for s in seen {
      if s == v {
        return Some("vocab '\{v}' is claimed by two installers")
      }
    }
    seen.push(v)
  }
  None
}

/// Invariant ①' completeness: a special vocab USED by the definition tree but OWNED
/// by no installer in the chain is an error. With non-deletion the vocab always stays
/// in the def, so completeness is "used vocab ∉ owned set" (not "leftover after
/// consumption"). Scans the whole command subtree. `order` fixes the owned set.
fn unowned_vocab(def : Definition, order : Array[Installer]) -> String? {
  let owned : Array[String] = []
  for inst in order {
    owned.push(owned_vocab(inst))
  }
  scan_def_vocab(def, owned)
}

fn vocab_owned(owned : Array[String], v : String) -> Bool {
  for o in owned {
    if o == v {
      return true
    }
  }
  false
}

fn scan_elem_vocab(e : ElemDef, owned : Array[String]) -> String? {
  if e.long.length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:" + e.long[0])
  }
  if e.short.length() > 0 && !vocab_owned(owned, "short") {
    return Some("short")
  }
  if e.env.length() > 0 && !vocab_owned(owned, "env") {
    return Some("env:" + e.env[0])
  }
  if e.is_dd && !vocab_owned(owned, "dd") {
    return Some("dd")
  }
  if e.is_global && !vocab_owned(owned, "global") {
    return Some("global")
  }
  if e.is_inherit && !vocab_owned(owned, "inherit") {
    return Some("inherit")
  }
  match e.repeat {
    Some(_) => if !vocab_owned(owned, "repeat") { return Some("repeat") }
    None => ()
  }
  if e.multiple && !vocab_owned(owned, "multiple") {
    return Some("multiple")
  }
  None
}

fn scan_def_vocab(def : Definition, owned : Array[String]) -> String? {
  for e in def.options {
    match scan_elem_vocab(e, owned) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  for e in def.positionals {
    match scan_elem_vocab(e, owned) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  if def.commands.length() > 0 && !vocab_owned(owned, "command") {
    return Some("command")
  }
  for c in def.commands {
    match scan_def_vocab(c.body, owned) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  None
}

/// Zero-progress static guard (DR-043): a repeat head must consume >= 1 token, else
/// the recursive unfold loops forever. For a ref head the check reduces to "the ref
/// target consumes >= 1" (a cycle through refs without a consuming node is caught).
fn head_progresses(
  node : Node,
  registry : Map[String, Node],
  visiting : Array[String],
) -> Bool {
  match node {
    StrArg(_) | NumArg(_) | Exact(_) | NativeMatch(_) | DdSat(_) | CmdSat(_, _) =>
      true
    Bind(_, _) => false // binds without consuming
    Ref(r) => {
      for v in visiting {
        if v == r {
          return false // cycle with no consuming node => no progress
        }
      }
      match registry.get(r) {
        Some(tpl) => {
          visiting.push(r)
          let ok = head_progresses(tpl, registry, visiting)
          let _ = visiting.pop()
          ok
        }
        None => false // unresolved ref
      }
    }
    Or(alts) => {
      for a in alts {
        if !head_progresses(a, registry, visiting) {
          return false
        }
      }
      alts.length() > 0
    }
    Seq(items) => if items.length() >= 1 { head_progresses(items[0], registry, visiting) } else { false }
    Many(_) | Scoped(_, _) | ScopeNode(_) => true
  }
}

/// Scan the definition tree for a repeat element whose head makes no progress.
fn repeat_progress_error(def : Definition, registry : Map[String, Node]) -> String? {
  for e in def.positionals {
    match e.repeat {
      Some(_) =>
        if !head_progresses(elem_head(e), registry, []) {
          return Some("repeat element '\{e.name}' has a zero-progress head")
        }
      None => ()
    }
  }
  for c in def.commands {
    match repeat_progress_error(c.body, registry) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  None
}

/// A stable signature of one scope's build layer, for fixpoint detection. Node /
/// Entity both derive Show, so structural growth is visible as a string change.
fn build_sig(b : Build) -> String {
  let buf = StringBuilder::new()
  for g in b.greedy {
    buf.write_string("\{g};")
  }
  buf.write_string("|")
  for p in b.positional {
    buf.write_string("\{p};")
  }
  buf.write_string("|")
  for e in b.entities {
    buf.write_string("\{e};")
  }
  buf.to_string()
}

/// Signature of the whole scope-builder tree: each node's build plus its declared
/// option names (so global growing a child's declaration is detected) plus the
/// recursive child signatures.
fn tree_sig(sb : SB) -> String {
  let buf = StringBuilder::new()
  buf.write_string(build_sig(sb.build))
  buf.write_string("#opts:")
  for o in sb.decl.options {
    buf.write_string(o.name + ",")
  }
  for child in sb.children {
    buf.write_string("{" + child.name + ":")
    buf.write_string(tree_sig(child.body))
    buf.write_string("}")
  }
  buf.to_string()
}

/// Materialize the scope-builder tree into a Scope tree. Each subcommand becomes a
/// greedy `CmdSat(name, child)`: a greedy-face resident whose exact trigger 先食い
/// protects (the DR-018 "commands が先" priority), whose child is a NEW backbone
/// (DR-041 §4), and which SEVERS the parent on firing (the subcommand owns the rest).
fn materialize(sb : SB) -> Scope {
  let greedy : Array[Node] = []
  for g in sb.build.greedy {
    greedy.push(g)
  }
  for child in sb.children {
    let cs = materialize(child.body)
    greedy.push(CmdSat(child.name, cs))
  }
  { greedy, positional: sb.build.positional, entities: sb.build.entities }
}

/// UsefulAST -> AtomicAST as an installer chain (DR-042). `order` is the applied
/// installer sequence; the 5 invariants make the result order-independent.
///
/// The chain runs to a FIXPOINT over the whole command tree (invariant note:
/// apparent inter-installer deps — e.g. global places a declarative copy that long
/// later expands in a child scope — are resolved by repeating all installers until
/// contributions stop growing). Termination: the build layer grows monotonically via
/// add-if-absent and global copies over a finite element×scope space (a copy of a
/// copy is the same option by name, which add-if-absent stops), so a pass that
/// changes nothing is the fixpoint.
pub fn parse_definition(
  def0 : Definition,
  order : Array[Installer],
  registry~ : Map[String, Node] = Map::new(),
) -> Result[Scope, String] {
  match check_registration(order) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let def = clone_def(def0)
  match unowned_vocab(def, order) {
    Some(v) => return Err("unknown special vocab '\{v}' — no installer claimed it")
    None => ()
  }
  let sb = init_sb(def, registry)
  match repeat_progress_error(def, registry) {
    Some(v) => return Err(v)
    None => ()
  }
  let mut iters = 0
  while true {
    let prev = tree_sig(sb)
    tree_pass(order, sb)
    if tree_sig(sb) == prev {
      break
    }
    iters = iters + 1
    if iters > 100 {
      return Err("installer chain did not converge (fixpoint > 100 iterations)")
    }
  }
  Ok(materialize(sb))
}

// ── layer 3: value-source ladder resolution (DR-031, invariant ④) ─────────────

fn env_value(ty : Ty, s : String) -> Value {
  match ty {
    TNum =>
      match parse_number(s) {
        Some(d) => VNum(d)
        None => VStr(s)
      }
    TFlag => VBool(s == "true" || s == "1")
    TStr => VStr(s)
  }
}

/// Resolve one entity down the fixed ladder: cli > env > inherit > default (DR-031).
/// The returned Binding carries the SOURCE tag of the seat that supplied the value.
/// `inherited` maps a name to the nearest ancestor scope's resolved value; the
/// inherit seat consults it only when the entity declared an inherit seat.
fn resolve_entity(
  e : Entity,
  cli : Array[Binding],
  env_map : Map[String, String],
  inherited : Map[String, Value],
) -> Binding? {
  for b in cli {
    if b.key == e.name {
      return Some(b) // cli seat (highest)
    }
  }
  match e.env_key {
    Some(k) =>
      match env_map.get(k) {
        Some(v) => return Some(mkb(e.name, env_value(e.ty, v), Env))
        None => ()
      }
    None => ()
  }
  if e.inherit {
    match inherited.get(e.name) {
      Some(v) => return Some(mkb(e.name, v, Inherit))
      None => ()
    }
  }
  match e.default_value {
    Some(v) => Some(mkb(e.name, v, Default))
    None => None
  }
}

/// Resolve every entity in a built scope against CLI bindings + an env map, with an
/// optional inherited-context (nearest ancestor's resolved values, for inherit seats).
pub fn resolve_scope(
  sc : Scope,
  cli : Array[Binding],
  env_map : Map[String, String],
  inherited~ : Map[String, Value] = Map::new(),
) -> Array[Binding] {
  let out : Array[Binding] = []
  for e in sc.entities {
    match resolve_entity(e, cli, env_map, inherited) {
      Some(b) => out.push(b)
      None => ()
    }
  }
  out
}

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

/// Build an inherited-context map from a parent scope's resolved bindings.
pub fn inherited_of(binds : Array[Binding]) -> Map[String, Value] {
  let m : Map[String, Value] = Map::new()
  for b in binds {
    m.set(b.key, b.value)
  }
  m
}
