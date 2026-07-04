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
  fail_action : Bool // failure-action element (DR-048, e.g. type:"help"): fires on a FAILED parse
  is_config_file : Bool // type:"config_file" (DR-050): its resolved path feeds the config_provider
  config_key : Array[String]? // explicit config path (DR-050 §3); None = 同型. Owned by the config installer
  export_key : ExportKey // result-key axis (DR-052); a RESULT concern, orthogonal to the AtomicAST
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

/// A subcommand: a name + its own scope Definition (a fresh backbone, DR-041 §4). `export_key`
/// gives the command's result-scope key (DR-052): null = the scope key is dropped and children
/// promote to the parent scope; the command's structural role (a new backbone) is unchanged.
pub(all) struct CommandDef {
  name : String
  body : Definition
  export_key : ExportKey
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
  ConfigInst
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
    ConfigInst => "config" // owns both type:"config_file" and config_key (DR-050)
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
    // int is number-like at the CLI in this PoC; the integer constraint is enforced at config time
    // (config_to_value). Full CLI-side int validation is out of scope for the 11th installment.
    TNum | TInt => NumArg(name)
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
    fail_action: e.fail_action,
    is_config_file: e.is_config_file,
    config_key: e.config_key,
    export_key: e.export_key,
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
    cs.push({ name: c.name, body: clone_def(c.body), export_key: c.export_key })
  }
  { options: os, positionals: ps, commands: cs }
}

/// Build the result-key map (DR-052): every element / command name → its export_key. Used by the
/// post-parse result remap (apply_export_keys). export_key is a RESULT concern only, so it lives
/// outside the AtomicAST — the map is read straight off the Definition, not the built Scope.
pub fn build_export_map(def : Definition) -> Map[String, ExportKey] {
  let m : Map[String, ExportKey] = Map::new()
  collect_export(def, m)
  m
}

fn collect_export(def : Definition, m : Map[String, ExportKey]) -> Unit {
  for e in def.options {
    m.set(e.name, e.export_key)
  }
  for e in def.positionals {
    m.set(e.name, e.export_key)
  }
  for c in def.commands {
    m.set(c.name, c.export_key)
    collect_export(c.body, m)
  }
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
fn ensure_entities(sb : SB, has_cf : Bool) -> Unit {
  for e in sb.decl.options {
    ensure_entity(sb.build, e, has_cf)
  }
  for e in sb.decl.positionals {
    if not_dd(e) {
      ensure_entity(sb.build, e, has_cf)
    }
  }
}

fn ensure_entity(build : Build, e : ElemDef, has_cf : Bool) -> Unit {
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
  // Uniform array (DR-044 §1, kawaz 裁定): a repeat / multiple / separator element is ALWAYS an
  // array regardless of cardinality — `repeat:{min:0,max:1}` (= optional 糖衣) is [] / [x], NOT a
  // scalar. Declaring repetition means the result is the many-valued shape; scalar is opt-in via a
  // collector (unwrap_single, DR-034 縮退). So max no longer gates the accumulator.
  let accum : String? = if e.multiple {
    Some("append")
  } else {
    match elem_repeat(e) {
      Some(_) => Some("flatten") // any repeat (incl. optional/max=1) → the flatten accumulator
      None => if e.separator.is_some() { Some("append") } else { None }
    }
  }
  // config seat (DR-050 §3, 同型対応 default): when a config_file element exists, EVERY value cell
  // corresponds to config by 同型 — so declare a config seat on every entity except the config_file
  // element itself (循環禁止). `config_key` overrides the path; None = 同型 (scope path + name).
  let config_seat = has_cf && not(e.is_config_file)
  build.entities.push({
    name: e.name,
    ty: e.ty,
    env_key: None,
    config_seat,
    config_key: e.config_key,
    is_config_file: e.is_config_file,
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
          // A flag: fire the trigger and set name=true. A failure-action flag (DR-048, e.g. help)
          // additionally emits a FailMark so a FAILED parse can fire it. 先食い/内部一体 (DR-041)
          // means a dd-internal `--help` is raw-consumed and never runs this satellite.
          add_greedy(
            build,
            maybe_root(
              e.is_link,
              if e.fail_action {
                Seq([Exact(trigger), Bind(e.name, VBool(true)), FailMark(e.name)])
              } else {
                Seq([Exact(trigger), Bind(e.name, VBool(true))])
              },
            ),
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
    fail_action: copy.fail_action,
    is_config_file: copy.is_config_file,
    config_key: copy.config_key,
    export_key: copy.export_key,
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
    ConfigInst => () // config seat set deterministically in ensure_entity (席宣言型, DR-050/042 ④)
  }
}

/// One fixpoint pass over the whole tree: ensure entities (core), apply every
/// installer to this node, then recurse into subcommand scopes. Global copies into
/// children before the recursion, so a child sees the grown declaration in the same
/// pass regardless of global's position in `order`.
fn tree_pass(order : Array[Installer], sb : SB, has_cf : Bool) -> Unit {
  ensure_entities(sb, has_cf)
  for inst in order {
    apply_node(inst, sb)
  }
  for child in sb.children {
    tree_pass(order, child.body, has_cf)
  }
}

fn def_err(
  element : String,
  kind : DefErrKind,
  message : String,
  hint : String,
) -> DefError {
  { element, kind, message, hint }
}

/// Invariant ③ (DR-054): two installers owning the same vocab. Collects ALL intersections.
fn collect_vocab_intersection(
  order : Array[Installer],
  out : Array[DefError],
) -> Unit {
  let seen : Array[String] = []
  for inst in order {
    let v = owned_vocab(inst)
    for s in seen {
      if s == v {
        out.push(
          def_err(
            v,
            DVocabIntersection,
            "vocab '\{v}' is claimed by two installers",
            "remove the duplicate installer owning '\{v}' from the chain",
          ),
        )
      }
    }
    seen.push(v)
  }
}

/// Invariant ①' completeness (DR-054): every special vocab used by the tree but owned by no
/// installer in the chain is an Error. Collects ALL (per element + commands).
fn collect_unknown_vocab(
  def : Definition,
  order : Array[Installer],
  out : Array[DefError],
) -> Unit {
  let owned : Array[String] = []
  for inst in order {
    owned.push(owned_vocab(inst))
  }
  scan_unknown(def, owned, out)
}

fn scan_unknown(
  def : Definition,
  owned : Array[String],
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    push_elem_unknown(e, owned, out)
  }
  for e in def.positionals {
    push_elem_unknown(e, owned, out)
  }
  if def.commands.length() > 0 && !vocab_owned(owned, "command") {
    out.push(
      def_err(
        "(commands)",
        DUnknownVocab,
        "unknown special vocab 'command'",
        "add CommandInst to the installer chain",
      ),
    )
  }
  for c in def.commands {
    scan_unknown(c.body, owned, out)
  }
}

fn push_elem_unknown(
  e : ElemDef,
  owned : Array[String],
  out : Array[DefError],
) -> Unit {
  match scan_elem_vocab(e, owned) {
    Some(v) =>
      out.push(
        def_err(
          e.name,
          DUnknownVocab,
          "unknown special vocab '\{v}' — no installer claimed it",
          "register an installer owning '\{v}' in the chain (§13.5)",
        ),
      )
    None => ()
  }
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
  // config vocab (DR-050): type:"config_file" and config_key are both owned by the config installer.
  if e.is_config_file && !vocab_owned(owned, "config") {
    return Some("config:config_file")
  }
  match e.config_key {
    Some(_) => if !vocab_owned(owned, "config") { return Some("config:config_key") }
    None => ()
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
    StrArg(_)
    | SepArg(_, _)
    | NumArg(_)
    | FilterArg(_, _)
    | ReqArg(_)
    | Exact(_)
    | NativeMatch(_)
    | DdSat(_)
    | CmdSat(_, _) => true
    NoDashStr(_) => true // consumes one token (when not dash-rejected)
    IdxRepeat(_, _, _) => true // an indexed repeat consumes its head
    BoundedTail(_, budget, _) => budget >= 1 // consumes only if it may take >= 1 head
    Rooted(inner) => head_progresses(inner, registry, visiting)
    Bind(_, _) => false // binds without consuming
    EffMark(_, _) => false // applies an effect without consuming (DR-045, 0-token)
    FailMark(_) => false // records a failure-action without consuming (DR-048, 0-token)
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

/// The ref in HEAD position of a node (the first thing consumed), if any. A ref AFTER a consuming
/// head (like a repeat's cons tail `Seq([head, Opt(Ref(self))])`) is NOT in head position, so a
/// legitimate repeat self-ref returns None here — that is the distinction from a circular ref.
fn head_ref_of(node : Node) -> String? {
  match node {
    Ref(r) => Some(r)
    Seq(items) => if items.length() >= 1 { head_ref_of(items[0]) } else { None }
    Or(alts) => {
      for a in alts {
        match head_ref_of(a) {
          Some(r) => return Some(r)
          None => ()
        }
      }
      None
    }
    Rooted(inner) => head_ref_of(inner)
    _ => None // a consuming or 0-token node in head position
  }
}

/// Whether following head-position refs from `name` loops back (a circular ref, infinite structural
/// expansion, DR-054). A repeat's self-ref does NOT loop here (its head is a consuming node, not a ref).
fn head_cycles(name : String, registry : Map[String, Node], visiting : Array[String]) -> Bool {
  for v in visiting {
    if v == name {
      return true
    }
  }
  match registry.get(name) {
    Some(tpl) =>
      match head_ref_of(tpl) {
        Some(next) => {
          visiting.push(name)
          let r = head_cycles(next, registry, visiting)
          let _ = visiting.pop()
          r
        }
        None => false
      }
    None => false
  }
}

/// Whether a node's head-position ref reaches a cycle (used to keep a circular ref from also being
/// reported as zero-progress).
fn head_node_cycles(node : Node, registry : Map[String, Node]) -> Bool {
  match head_ref_of(node) {
    Some(r) => head_cycles(r, registry, [])
    None => false
  }
}

/// Zero-progress guard (DR-043 / DR-054): a repeat head must consume >= 1 token. Collects ALL such
/// repeats — but a NON-progress that is actually a ref CYCLE is a circular ref (reported by
/// collect_circular_ref), not zero-progress, so it is excluded here to keep the kinds distinct.
fn collect_zero_progress(
  def : Definition,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for e in def.positionals {
    match elem_repeat(e) {
      Some(_) => {
        let head = elem_head(e)
        if !head_progresses(head, registry, []) && not(head_node_cycles(head, registry)) {
          out.push(
            def_err(
              e.name,
              DZeroProgress,
              "repeat element '\{e.name}' has a zero-progress head",
              "give the repeat head a token-consuming element",
            ),
          )
        }
      }
      None => ()
    }
  }
  for c in def.commands {
    collect_zero_progress(c.body, registry, out)
  }
}

/// Circular ref (DR-054): a registry template whose head-position ref chain loops → infinite
/// structural expansion. Repeat-generated self-refs pass (their head is a consuming node). Collects all.
fn collect_circular_ref(
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for name, _ in registry {
    // skip the lazy-marker keys the repeat installer registers ("lazy:<name>").
    if name.length() >= 5 && name.substring(start=0, end=5) == "lazy:" {
      continue
    }
    if head_cycles(name, registry, []) {
      out.push(
        def_err(
          name,
          DCircularRef,
          "ref template '\{name}' is circular (infinite structural expansion)",
          "break the ref cycle or add a token-consuming head before the self-reference",
        ),
      )
    }
  }
}

/// Absent ref (DR-054 / DR-032): an element ref_target resolvable nowhere (registry has it after
/// init_sb's repeat lowering + any pre-registered templates). Collects all.
fn collect_absent_ref(
  def : Definition,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    check_elem_absent_ref(e, registry, out)
  }
  for e in def.positionals {
    check_elem_absent_ref(e, registry, out)
  }
  for c in def.commands {
    collect_absent_ref(c.body, registry, out)
  }
}

fn check_elem_absent_ref(
  e : ElemDef,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  match e.ref_target {
    Some(r) =>
      match registry.get(r) {
        Some(_) => ()
        None =>
          out.push(
            def_err(
              e.name,
              DAbsentRef,
              "ref target '\{r}' is not defined in scope or definitions",
              "define '\{r}' as a template (definitions) or in the scope",
            ),
          )
      }
    None => ()
  }
}

/// Invalid value range (DR-054 / DR-052): repeat min > max. Collects all. (export_key bool is not
/// representable in the PoC's ExportKey enum, so there is nothing to check for it — see journal.)
fn collect_invalid_range(def : Definition, out : Array[DefError]) -> Unit {
  for e in def.positionals {
    match e.repeat {
      Some(spec) =>
        match spec.max {
          Some(mx) =>
            if spec.min > mx {
              out.push(
                def_err(
                  e.name,
                  DInvalidRange,
                  "repeat min \{spec.min} > max \{mx}",
                  "set the repeat max >= min",
                ),
              )
            }
          None => ()
        }
      None => ()
    }
  }
  for c in def.commands {
    collect_invalid_range(c.body, out)
  }
}

/// Whether the definition tree has any `type:"config_file"` element (DR-050): if so, a config
/// object is available and the 同型 config seat is declared on every value cell.
fn has_config_file(def : Definition) -> Bool {
  for e in def.options {
    if e.is_config_file {
      return true
    }
  }
  for e in def.positionals {
    if e.is_config_file {
      return true
    }
  }
  for c in def.commands {
    if has_config_file(c.body) {
      return true
    }
  }
  false
}

/// config cycle (DR-050 §5 / DR-054): a config_file element cannot carry a config_key (it would take
/// its own path from the config it locates). Collects all.
fn collect_config_cycle(def : Definition, out : Array[DefError]) -> Unit {
  for e in def.options {
    if e.is_config_file && e.config_key.is_some() {
      out.push(
        def_err(
          e.name,
          DConfigCycle,
          "config_file element '\{e.name}' cannot have a config_key (循環禁止)",
          "remove config_key from the config_file element",
        ),
      )
    }
  }
  for e in def.positionals {
    if e.is_config_file && e.config_key.is_some() {
      out.push(
        def_err(
          e.name,
          DConfigCycle,
          "config_file element '\{e.name}' cannot have a config_key (循環禁止)",
          "remove config_key from the config_file element",
        ),
      )
    }
  }
  for c in def.commands {
    collect_config_cycle(c.body, out)
  }
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
/// Returns Ok(atomic scope) or Err(ALL definition-time errors) (DR-054 §4 の 2 値 union). Every
/// static check runs and appends to one list — no first-error 打ち切り (コンパイラの定石). Each
/// DefError carries {element, kind, message, hint}.
pub fn parse_definition(
  def0 : Definition,
  order : Array[Installer],
  registry~ : Map[String, Node] = Map::new(),
) -> Result[Scope, Array[DefError]] {
  let def = clone_def(def0)
  // init_sb populates `registry` with repeat-lowering templates, so the ref checks below see them.
  let sb = init_sb(def, registry)
  let errs : Array[DefError] = []
  collect_vocab_intersection(order, errs) // DR-042③
  collect_unknown_vocab(def, order, errs) // DR-042①
  collect_invalid_range(def, errs) // DR-052 (repeat min>max)
  collect_absent_ref(def, registry, errs) // DR-032
  collect_circular_ref(registry, errs) // DR-007/032
  collect_zero_progress(def, registry, errs) // DR-043
  collect_config_cycle(def, errs) // DR-050 §5
  if errs.length() > 0 {
    return Err(errs) // definition-error: ALL enumerated
  }
  // 同型 default (DR-050 §3): a config seat is declared on every value cell when a config_file
  // element exists (its resolved path feeds the provider). Computed once; threaded to ensure_entity.
  let has_cf = has_config_file(def)
  let mut iters = 0
  while true {
    let prev = tree_sig(sb)
    tree_pass(order, sb, has_cf)
    if tree_sig(sb) == prev {
      break
    }
    iters = iters + 1
    if iters > 100 {
      return Err([
        def_err(
          "(chain)",
          DUnknownVocab,
          "installer chain did not converge (> 100 iterations)",
          "check for a runaway global copy or a mis-registered installer",
        ),
      ])
    }
  }
  Ok(materialize(sb))
}

// ── layer 3: value-source ladder resolution (DR-031, invariant ④) ─────────────

fn env_value(ty : Ty, s : String) -> Value {
  match ty {
    TNum | TInt =>
      match parse_number(s) {
        Some(d) => VNum(d)
        None => VStr(s)
      }
    TFlag => VBool(s == "true" || s == "1")
    TStr => VStr(s)
  }
}

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

/// Resolve one entity down the fixed ladder: cli > env > config > inherit > default (DR-031 /
/// DR-050 #3). Returns the effect bindings (0/1, or many when a config array fills a `multiple`
/// cell) or an Err (a config type mismatch is a DR-037 Error). `config_obj` is the read config
/// object (None = no config); `config_path` is this entity's absolute lookup path (同型 or config_key).
fn resolve_entity(
  e : Entity,
  cli : Array[Binding],
  env_map : Map[String, String],
  config_obj : ConfigVal?,
  config_path : Array[String],
  inherited : Map[String, Value],
) -> Result[Array[Binding], String] {
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
        Some(v) => return Ok([mkb(e.name, env_value(e.ty, v), Env)])
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
                if e.accum.is_some() {
                  let bs : Array[Binding] = []
                  for it in items {
                    match config_to_value(it, e.ty) {
                      Ok(v) => bs.push(mkb(e.name, v, Config))
                      Err(msg) => return Err(msg)
                    }
                  }
                  return Ok(bs)
                } else {
                  return Err("config array for a scalar element (structural mismatch)")
                }
              _ =>
                match config_to_value(cv, e.ty) {
                  Ok(v) => return Ok([mkb(e.name, v, Config)])
                  Err(msg) => return Err(msg) // §4 型不一致 → DR-037 Error
                }
            }
          None => () // not present in config → fall through
        }
      None => () // no config object (no config_file, or default-path read failure) → fall through
    }
  }
  // inherit seat (DR-031 / DR-013)
  if e.inherit {
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

/// Resolve every entity in a built scope against CLI bindings + an env map (no config seat). For
/// the env / inherit tests; config-less, so it never errors.
pub fn resolve_scope(
  sc : Scope,
  cli : Array[Binding],
  env_map : Map[String, String],
  inherited~ : Map[String, Value] = Map::new(),
) -> Array[Binding] {
  let out : Array[Binding] = []
  for e in sc.entities {
    match resolve_entity(e, cli, env_map, None, [], inherited) {
      Ok(bs) => for b in bs { out.push(b) }
      Err(_) => () // config-less resolution cannot error
    }
  }
  out
}

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

/// Resolve a scope WITH a config-file value source (DR-050 §5 dependency order):
///   1. resolve the config_file element's path (cli > env > default; it has NO config seat, 循環禁止)
///   2. read the provider with that path → a config object (or None). A committed path (cli/env)
///      that reads None is a DR-037 Error (指定したのに読めない); a default path reading None is
///      silently tolerated (config seat stays empty)
///   3. resolve every (non config_file) entity down cli > env > config > inherit > default, using
///      the config object and each entity's absolute config path (config_key, else 同型 = scope path + name)
/// `provider` is the config_provider stub (path → config object | None). `path` is this scope's
/// result path (for 同型 correspondence). Returns Err on a read failure or a §4 type mismatch.
pub fn resolve_scope_config(
  sc : Scope,
  cli : Array[Binding],
  env_map : Map[String, String],
  provider : (String) -> ConfigVal?,
  path~ : Array[String] = [],
  inherited~ : Map[String, Value] = Map::new(),
) -> Result[Array[Binding], String] {
  // Phase 1: resolve the config_file element's path (cli > env > default), track committed-ness.
  let mut cf_path : String? = None
  let mut cf_committed = false
  for e in sc.entities {
    if e.is_config_file {
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
      if not(done) {
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
      if not(done) {
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
          None => return Err("config file \"\{p}\" could not be read")
          Some(_) => ()
        }
      }
    None => ()
  }
  // Phase 3: resolve every non config_file entity down the full ladder.
  let out : Array[Binding] = []
  for e in sc.entities {
    if not(e.is_config_file) {
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
      match resolve_entity(e, cli, env_map, config_obj, cpath, inherited) {
        Ok(bs) => for b in bs { out.push(b) }
        Err(msg) => return Err(msg)
      }
    }
  }
  Ok(out)
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
