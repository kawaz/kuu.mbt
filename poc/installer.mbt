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
  variants : Array[Variant] // owned by the long installer (variant DSL, DR-011/045)
  short : Array[Char] // owned by the short installer
  env : Array[String] // owned by the env installer
  is_dd : Bool // owned by the dd installer (type:"dd")
  is_global : Bool // owned by the global installer (copied into descendant command scopes)
  is_inherit : Bool // owned by the inherit installer (declares an inherit seat)
  is_link : Bool // a global COPY (link-sync): its satellite binds the root entity (Rooted)
  ref_target : String? // core (DR-020): this element IS a ref to a named template
  repeat : RepeatSpec? // owned by the repeat installer (DR-043)
  optional : Bool // sugar for repeat:{min:0,max:1} (DR-043), reduced by elem_repeat — repeat's vocab
  multiple : Bool // owned by the multiple installer (DR-034/043)
  separator : String? // the multiple pipeline's separator (DR-034); a value token splits on it
  default_value : Value?
} derive(Eq, Show)

/// A variant entry (DR-011 variant DSL / DR-045 effect descriptors). Declares a distinct
/// trigger that applies an EFFECT to this element's cell — e.g. `--no-ssl` unsetting `ssl`.
/// The variant DSL surface (`long: ["no:set:false"]`) is the long installer's internal
/// representation freedom (DR-042 §所有権の粒度); the PoC declares the PARSED form directly.
/// The long installer lowers each variant to `{exact, link (by name), effect}` (LOWERING §B.1).
pub(all) struct Variant {
  trigger : String // the full long trigger word, e.g. "no-ssl" → matches `--no-ssl`
  op : EffectOp // the effect applied to the cell when this trigger fires
  operand : Value? // for a `set` variant (e.g. `--compress=gzip`); None for default/unset/empty
} derive(Eq, Show)

/// A repeat closure (DR-043). `min` is the required rep count (mandatory-head unroll).
/// `max` is the unroll-段数 upper bound: `None` = unbounded (a recursive Ref tail), `Some(M)`
/// = bounded (M-min BoundedTail heads, NO Ref recursion — LOWERING §B.8). `optional: true`
/// is the `{min:0, max:Some(1)}` sugar (reduced here, not an independent concept, DR-043).
/// `lazy` picks the split preference: greedy (default, longest share first) vs lazy (shortest).
pub(all) struct RepeatSpec {
  min : Int
  max : Int? // None = unbounded (Ref tail); Some(M) = bounded to M reps (BoundedTail)
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

fn copy_variants(a : Array[Variant]) -> Array[Variant] {
  let r : Array[Variant] = []
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
    variants: copy_variants(e.variants),
    short: copy_chars(e.short),
    env: copy_strs(e.env),
    is_dd: e.is_dd,
    is_global: e.is_global,
    is_inherit: e.is_inherit,
    is_link: e.is_link,
    ref_target: e.ref_target,
    repeat: e.repeat,
    optional: e.optional,
    multiple: e.multiple,
    separator: e.separator,
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
    None =>
      // a separator element splits each token into pieces (DR-034); else a plain value primitive.
      match e.separator {
        Some(sep) => SepArg(e.name, sep)
        None => value_prim(e.ty, e.name)
      }
  }
}

/// The EFFECTIVE repeat spec of an element (DR-043). `optional: true` REDUCES to
/// `repeat: {min:0, max:1}` — it is sugar, not an independent concept — so an explicit
/// repeat wins, else optional becomes the 0/1 closure, else None (not a repeat).
fn elem_repeat(e : ElemDef) -> RepeatSpec? {
  match e.repeat {
    Some(s) => Some(s)
    None => if e.optional { Some({ min: 0, max: Some(1), lazy: false }) } else { None }
  }
}

/// Whether a repeat spec's cell ACCUMULATES into a list (DR-036 "flatten"): true iff the
/// closure can bind >= 2 values — unbounded, or bounded with max >= 2. A max-1 repeat
/// (including `optional`) binds a SCALAR cell (0-or-1), since flatten collapses a MULTI
/// cons and there is at most one value. (This max=1 boundary is the PoC's realization of the
/// DR-043/044 interaction — neither DR pins the 0/1 result shape; see journal.)
fn repeat_accumulates(s : RepeatSpec) -> Bool {
  match s.max {
    None => true
    Some(m) => m >= 2
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
      match elem_repeat(e) {
        None => out.push(head)
        Some(spec) =>
          match spec.max {
            None => {
              // UNBOUNDED (DR-043): min-1 mandatory heads + a recursive Ref(>=1) tail. The
              // template `name = Seq([head, Opt(Ref(name))])` is the porous self-ref.
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
            Some(mx) => {
              // BOUNDED (LOWERING §B.8): `min` mandatory heads + BoundedTail(head, max-min),
              // NO Ref recursion — the bound is the tail's recursion depth. `optional:true`
              // (min0/max1) is a lone BoundedTail(head, 1). The tail keeps 先食い (consume_head)
              // and 取り分選好 (greedy/lazy), so bounded repeats compose like unbounded ones.
              let m = if spec.min < 0 { 0 } else { spec.min }
              let mut k = 0
              while k < m {
                out.push(head) // mandatory heads (DR-043 min)
                k = k + 1
              }
              let budget = if mx - m < 0 { 0 } else { mx - m }
              out.push(BoundedTail(head, budget, spec.lazy))
            }
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
  // repeat and multiple both make the cell a value LIST via a NAMED accumulator (DR-036
  // registry). repeat installs the built-in "flatten" (cons [T,[T,…]] → T[], DR-043);
  // multiple installs "append" (DR-034). Deterministic core lowering — RepeatInst/MultipleInst
  // own the vocab for completeness, but which registry entry to install is a pure function of
  // the decl. If an element is both, multiple's append wins (the value-fold governs).
  let accum : String? = if e.multiple {
    Some("append")
  } else {
    match elem_repeat(e) {
      Some(s) => if repeat_accumulates(s) { Some("flatten") } else { None } // max=1 → scalar
      None =>
        // a separator element (no repeat) still collects >= 2 pieces from one token → append.
        if e.separator.is_some() {
          Some("append")
        } else {
          None
        }
    }
  }
  build.entities.push({
    name: e.name,
    ty: e.ty,
    env_key: None,
    inherit: false,
    accum,
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
        TFlag =>
          add_greedy(
            build,
            maybe_root(e.is_link, Seq([Exact(trigger), Bind(e.name, VBool(true))])),
          )
        _ => {
          add_greedy(
            build,
            maybe_root(e.is_link, Seq([Exact(trigger), value_prim(e.ty, e.name)])),
          )
          eq_entries.push({ key: l, name: e.name, kind: e.ty })
        }
      }
    }
  }
  if eq_entries.length() > 0 {
    add_greedy(build, NativeMatch(EqSplit(prefix="--", entries=eq_entries)))
  }
  // Variant entries (DR-011 / DR-045): each lowers to `{exact, link, effect}` — a greedy
  // exact satellite that applies the effect op to the element's cell (link is by-name).
  // A `set` variant carries an operand (Bind = SET degenerate form); default/unset/empty
  // apply their op via EffMark (0-token). LOWERING §B.1 (extended for the variant effect form).
  for e in def.options {
    for v in e.variants {
      let trigger = "--" + v.trigger
      let sat = match v.op {
        Set => {
          let operand = match v.operand {
            Some(val) => val
            None => VBool(true)
          }
          Seq([Exact(trigger), Bind(e.name, operand)])
        }
        _ => Seq([Exact(trigger), EffMark(e.name, v.op)])
      }
      add_greedy(build, maybe_root(e.is_link, sat))
    }
  }
}

/// Wrap a satellite in `Rooted` iff the element is a global link copy, so its bindings
/// target the root entity (DR-042 link-sync).
fn maybe_root(is_link : Bool, node : Node) -> Node {
  if is_link {
    Rooted(node)
  } else {
    node
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
  // The copy is a link satellite (DR-042): it binds the ROOT entity, not a fresh child
  // cell, so the value syncs to one place. `is_link` makes long/short wrap it in Rooted.
  let copy = clone_elem(opt)
  child.decl.options.push({
    name: copy.name,
    ty: copy.ty,
    long: copy.long,
    variants: copy.variants,
    short: copy.short,
    env: copy.env,
    is_dd: copy.is_dd,
    is_global: copy.is_global,
    is_inherit: copy.is_inherit,
    is_link: true,
    ref_target: copy.ref_target,
    repeat: copy.repeat,
    optional: copy.optional,
    multiple: copy.multiple,
    separator: copy.separator,
    default_value: copy.default_value,
  })
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
  // Variant DSL is part of the long attribute's value vocabulary (DR-042 §所有権の粒度),
  // so it is owned by the long installer.
  if e.variants.length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:variant:" + e.variants[0].trigger)
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
  // repeat and its `optional` sugar (DR-043) are both owned by the repeat installer.
  match elem_repeat(e) {
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
    StrArg(_) | SepArg(_, _) | NumArg(_) | Exact(_) | NativeMatch(_) | DdSat(_) | CmdSat(_, _) =>
      true
    NoDashStr(_) => true // consumes one token (when not dash-rejected)
    IdxRepeat(_, _, _) => true // an indexed repeat consumes its head
    BoundedTail(_, budget, _) => budget >= 1 // consumes only if it may take >= 1 head
    Rooted(inner) => head_progresses(inner, registry, visiting)
    Bind(_, _) => false // binds without consuming
    EffMark(_, _) => false // applies an effect without consuming (DR-045, 0-token)
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
    match elem_repeat(e) {
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
  // The cli seat's state is the LAST effect on this entity (last-wins, DR-015). The op
  // decides committed-ness (DR-045 §2 / DR-031): set/default/empty commit and STOP the
  // ladder here; unset does NOT commit, so control falls through to env / inherit / default.
  let mut seat : Binding? = None
  for b in cli {
    if b.key == e.name {
      seat = Some(b)
    }
  }
  match seat {
    Some(b) =>
      match b.op {
        Set => return Some(b) // committed cli value (the SET operand wins)
        Default =>
          // committed default: the value is the DEFAULT, but LOCKED — env/inherit cannot
          // override (this is the observable difference from unset, DR-045 §2).
          match e.default_value {
            Some(v) => return Some(mkb(e.name, v, Default))
            None => return Some(b)
          }
        Empty => return Some(b) // committed empty (collection op; scalar is an edge)
        Unset => () // NOT committed: fall through to the later ladder seats (env/inherit/default)
      }
    None => ()
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
