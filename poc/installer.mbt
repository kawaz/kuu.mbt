// installer.mbt — parse_definition as a chain of installers (DR-042).
//
// An installer owns a special vocabulary (long / short / env / dd), and on each
// application: (1) collects its vocab from the definition and REMOVES it, (2)
// implants greedy satellites / matchers / re-scoping, (3) declares runtime seats
// (env). The 5 invariants keep the chain order-independent and idempotent.

/// UsefulAST element. Attribute arrays are mutable so installers can empty them
/// on collection (invariant ①: 消費即除去 => idempotency falls out of the schema).
pub(all) struct ElemDef {
  name : String
  ty : Ty
  mut long : Array[String] // owned by the long installer
  mut short : Array[Char] // owned by the short installer
  mut env : Array[String] // owned by the env installer
  mut is_dd : Bool // owned by the dd installer (type:"dd")
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

/// Mutable build accumulator: installers only ADD to greedy / mutate the env seat
/// of an entity in place / (dd only) rewrite the positional face (invariant ②③).
priv struct Build {
  greedy : Array[Node] // installers push satellites/matchers (in-place)
  entities : Array[Entity] // created once; env installer mutates env_key in place
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
    if e.is_dd {
      // core lowering: a dd-typed positional lowers to the DdMark marker; the
      // continuation is simply the following positional items (DR-041 dashdash).
      positional.push(DdMark)
    } else {
      positional.push(value_prim(e.ty, e.name))
    }
  }
  { greedy: [], entities, positional }
}

fn not_dd(e : ElemDef) -> Bool {
  !e.is_dd
}

// ── the four installers ──────────────────────────────────────────────────────

/// long: collect `long`, add a greedy exact satellite per name (space form) and,
/// for value options, one eq-split matcher (`--k=v`). Satellites link to the
/// entity by name (DR-042 §展開の標準パターン).
fn inst_long(def : Definition, build : Build) -> Unit {
  let eq_entries : Array[LongEntry] = []
  for e in def.options {
    if e.long.length() > 0 {
      for l in e.long {
        let trigger = "--" + l
        match e.ty {
          TFlag => build.greedy.push(Seq([Exact(trigger), Bind(e.name, VBool(true))]))
          _ => {
            build.greedy.push(Seq([Exact(trigger), value_prim(e.ty, e.name)]))
            eq_entries.push({ key: l, name: e.name, kind: e.ty })
          }
        }
      }
      e.long = [] // 消費即除去
    }
  }
  if eq_entries.length() > 0 {
    build.greedy.push(NativeMatch(EqSplit(prefix="--", entries=eq_entries)))
  }
}

/// short: collect `short`, add ONE cluster/value-attach matcher over all entries.
/// In this PoC the single-char case (`-v`, `-p 8080`) is subsumed by the matcher,
/// so short adds no separate exact satellite (a matcher-seat finding, see journal).
fn inst_short(def : Definition, build : Build) -> Unit {
  let sh_entries : Array[ShortEntry] = []
  for e in def.options {
    if e.short.length() > 0 {
      for c in e.short {
        sh_entries.push({ ch: c, name: e.name, kind: e.ty })
      }
      e.short = []
    }
  }
  if sh_entries.length() > 0 {
    build.greedy.push(NativeMatch(ShortCombine(prefix="-", entries=sh_entries)))
  }
}

/// env: collect `env`, declare a lookup at the entity's env SEAT (invariant ④).
/// It does NOT wrap default_fn; the ladder order is engine-owned (DR-031).
fn inst_env(def : Definition, build : Build) -> Unit {
  for e in def.options {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
      e.env = []
    }
  }
  for e in def.positionals {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
      e.env = []
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

/// dd: collect (license) the `is_dd` vocab and remove it (invariant ①).
///
/// PoC finding on where dd's work lands: the re-scoping is NOT built here. Core
/// lowering places the DdMark marker (init_build), and the evaluator implements
/// the greedy-severing semantics on that marker. So — unlike long/short, whose
/// installers construct concrete satellite/matcher structure — the dd installer
/// reduces to VOCAB LICENSING (its presence lets the marker exist; its absence
/// makes the leftover `is_dd` a completeness error). It touches no build state,
/// which trivially satisfies order-independence and idempotency.
fn inst_dd(def : Definition, _build : Build) -> Unit {
  for e in def.positionals {
    if e.is_dd {
      e.is_dd = false // 消費即除去 (licensed by this installer's presence)
    }
  }
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

/// Invariant ①: any special vocab left after all installers => unknown vocab error.
fn leftover_vocab(def : Definition) -> String? {
  for e in def.options {
    if e.long.length() > 0 {
      return Some("long:" + e.long[0])
    }
    if e.short.length() > 0 {
      return Some("short")
    }
    if e.env.length() > 0 {
      return Some("env:" + e.env[0])
    }
  }
  for e in def.positionals {
    if e.long.length() > 0 {
      return Some("long")
    }
    if e.short.length() > 0 {
      return Some("short")
    }
    if e.env.length() > 0 {
      return Some("env:" + e.env[0])
    }
    if e.is_dd {
      return Some("dd")
    }
  }
  None
}

/// UsefulAST -> AtomicAST as an installer chain (DR-042). `order` is the applied
/// installer sequence; the 5 invariants make the result order-independent.
pub fn parse_definition(
  def0 : Definition,
  order : Array[Installer],
) -> Result[Scope, String] {
  match check_registration(order) {
    Some(msg) => return Err(msg)
    None => ()
  }
  let def = clone_def(def0)
  let build = init_build(def)
  for inst in order {
    apply(inst, def, build)
  }
  match leftover_vocab(def) {
    Some(v) => Err("unknown special vocab '\{v}' — no installer claimed it")
    None =>
      Ok({
        greedy: build.greedy,
        positional: build.positional,
        entities: build.entities,
      })
  }
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
