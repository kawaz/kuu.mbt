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
  default_value : Value?
} derive(Eq, Show)

/// UsefulAST for one command scope: entry-bearing options + positional face.
pub(all) struct Definition {
  options : Array[ElemDef]
  positionals : Array[ElemDef]
} derive(Eq, Show)

/// The canonical installers (DR-042 §canonical installer セット).
pub(all) enum Installer {
  LongInst
  ShortInst
  EnvInst
  DdInst
} derive(Eq, Show)

fn owned_vocab(i : Installer) -> String {
  match i {
    LongInst => "long"
    ShortInst => "short"
    EnvInst => "env"
    DdInst => "dd"
  }
}

/// Mutable build accumulator: installers only ADD (add-if-absent) to greedy /
/// declare the env seat of an entity in place / (dd only) contribute a greedy
/// satellite (invariant ②③). The build layer grows monotonically; the fixpoint
/// stops when a full pass adds nothing.
priv struct Build {
  greedy : Array[Node] // installers add-if-absent satellites/matchers
  entities : Array[Entity] // created once; env installer declares env_key seat in place
  positional : Array[Node] // core lowering builds it; dd's semantics live in the evaluator
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
  { options: os, positionals: ps }
}

/// Core lowering: one entity (value cell, DR-030) per element; a flat positional
/// face with a DdMark([]) placeholder wherever a dd marker sits.
fn init_build(def : Definition) -> Build {
  let entities : Array[Entity] = []
  for e in def.options {
    entities.push({
      name: e.name,
      ty: e.ty,
      env_key: None,
      default_value: e.default_value,
    })
  }
  for e in def.positionals {
    if not_dd(e) {
      entities.push({
        name: e.name,
        ty: e.ty,
        env_key: None,
        default_value: e.default_value,
      })
    }
  }
  let positional : Array[Node] = []
  for e in def.positionals {
    // A dd-typed positional is NOT lowered onto the spine: the dd installer adds a
    // greedy DdSat satellite instead (DR-041 rev). Only value positionals are spine
    // consumers. The dd's "continuation" is the remaining spine at its fire point.
    if not_dd(e) {
      positional.push(value_prim(e.ty, e.name))
    }
  }
  { greedy: [], entities, positional }
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

// ── driver + completeness ────────────────────────────────────────────────────

fn apply(inst : Installer, def : Definition, build : Build) -> Unit {
  match inst {
    LongInst => inst_long(def, build)
    ShortInst => inst_short(def, build)
    EnvInst => inst_env(def, build)
    DdInst => inst_dd(def, build)
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

/// Invariant ①' completeness: a special vocab USED by the definition but OWNED by
/// no installer in the chain is an error. With non-deletion the vocab always stays
/// in the def, so completeness is "used vocab ∉ owned set" (not "leftover after
/// consumption"). `order` fixes the owned set.
fn unowned_vocab(def : Definition, order : Array[Installer]) -> String? {
  let owned : Array[String] = []
  for inst in order {
    owned.push(owned_vocab(inst))
  }
  fn owns(v : String) -> Bool {
    for o in owned {
      if o == v {
        return true
      }
    }
    false
  }

  fn scan(e : ElemDef) -> String? {
    if e.long.length() > 0 && !owns("long") {
      return Some("long:" + e.long[0])
    }
    if e.short.length() > 0 && !owns("short") {
      return Some("short")
    }
    if e.env.length() > 0 && !owns("env") {
      return Some("env:" + e.env[0])
    }
    if e.is_dd && !owns("dd") {
      return Some("dd")
    }
    None
  }

  for e in def.options {
    match scan(e) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  for e in def.positionals {
    match scan(e) {
      Some(v) => return Some(v)
      None => ()
    }
  }
  None
}

/// A stable signature of the build layer, for fixpoint detection. Node / Entity
/// both derive Show, so structural growth is visible as a string change.
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

/// UsefulAST -> AtomicAST as an installer chain (DR-042). `order` is the applied
/// installer sequence; the 5 invariants make the result order-independent.
///
/// The chain runs to a FIXPOINT (invariant note: apparent inter-installer deps —
/// e.g. global places a declarative copy that long later expands — are resolved by
/// repeating all installers until contributions stop growing). Termination: the
/// build layer grows monotonically via add-if-absent over a finite element×scope
/// space, so a pass that adds nothing is the fixpoint. Without a growing declaration
/// layer (global) this converges in two passes (add, then no-op).
pub fn parse_definition(
  def0 : Definition,
  order : Array[Installer],
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
  let build = init_build(def)
  let mut iters = 0
  while true {
    let prev = build_sig(build)
    for inst in order {
      apply(inst, def, build)
    }
    if build_sig(build) == prev {
      break
    }
    iters = iters + 1
    if iters > 100 {
      return Err("installer chain did not converge (fixpoint > 100 iterations)")
    }
  }
  Ok({
    greedy: build.greedy,
    positional: build.positional,
    entities: build.entities,
  })
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

/// Resolve one entity down the fixed ladder: cli > env > default (DR-031). The
/// returned Binding carries the SOURCE tag of the seat that supplied the value.
fn resolve_entity(
  e : Entity,
  cli : Array[Binding],
  env_map : Map[String, String],
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
  match e.default_value {
    Some(v) => Some(mkb(e.name, v, Default))
    None => None
  }
}

/// Resolve every entity in a built scope against CLI bindings + an env map.
pub fn resolve_scope(
  sc : Scope,
  cli : Array[Binding],
  env_map : Map[String, String],
) -> Array[Binding] {
  let out : Array[Binding] = []
  for e in sc.entities {
    match resolve_entity(e, cli, env_map) {
      Some(b) => out.push(b)
      None => ()
    }
  }
  out
}
