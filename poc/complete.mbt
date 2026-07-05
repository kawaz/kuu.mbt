// complete.mbt — the completion query (DR-060).
//
// complete = the UNION, over every SURVIVING partial path that consumed all of `before` (dead ends
// excluded), of what is readable at that path's next consumption point (DR-060 §1). It does NOT
// require full consumption or uniqueness — a DIFFERENT query from parse (DR-038 §15.1 untouched).
//
// This is a SEPARATE walk from the parse evaluator (design note, 第 18 弾): the parse `eval` collapses
// a "trigger consumed, value pending" state to no branch (its greedy Seq eval returns [] when the
// value token is absent), so it cannot surface a pending-value expectation — exactly what completion
// needs. And DR-048's WithHeld candidate set is dead-end-INCLUSIVE (its goal is the opposite: a failed
// action), whereas completion is dead-end-EXCLUSIVE. So neither is reused; the shared idea is only
// "collect the expected set at the cut position", realized here by a boundary-aware traversal.

///|
/// A terminal hint on an exact candidate (DR-060 §3): `WordEnd` = 確定, a space may follow; `Cont` =
/// 継続, no space (a value must follow — e.g. a value-taking --port, or a `--key=` / dir `/` in prod).
pub(all) enum TermHint {
  WordEnd
  Cont
} derive(Eq, Show)

///|
/// Declaration-layer meta a completion reads by reference (DR-056 / DR-057 / DR-058): whether a
/// spelling is an alias entry, hidden (excluded from candidates by default, kept in meta), deprecated.
pub(all) struct CandMeta {
  is_alias : Bool
  hidden : Bool
  deprecated : Bool
} derive(Eq, Show)

///|
/// A completion candidate (DR-060 §3): either an exact trigger spelling, or a value position (type +
/// completer名, PoC shows the type). Meta rides alongside; policy / replacement / landing is the
/// generator's & shell's (kuu returns素材 only).
pub(all) struct Cand {
  spelling : String // the exact spelling; "" for a value position
  is_value : Bool
  ty : Ty // for a value position
  origin : String // the element name it came from
  term : TermHint
  meta : CandMeta
} derive(Eq, Show)

///|
fn no_meta() -> CandMeta {
  { is_alias: false, hidden: false, deprecated: false }
}

///|
fn cexact(spelling : String, term : TermHint, origin : String) -> Cand {
  { spelling, is_value: false, ty: TFlag, origin, term, meta: no_meta() }
}

///|
fn cvalue(ty : Ty, origin : String) -> Cand {
  { spelling: "", is_value: true, ty, origin, term: WordEnd, meta: no_meta() }
}

// ── the surviving-partial-path traversal (DR-060 §1) ─────────────────────────

///|
/// Walk a scope over `before`, collecting the readable expectations at the cut position T =
/// before.length() across every surviving partial path. `pos` is the current argv position, `pidx`
/// the positional-face index, `severed` the post-`--` mode (greedy off, DR-042 ⑤).
fn comp_scope(
  sc : Scope,
  before : Array[String],
  t : Int,
  pos : Int,
  pidx : Int,
  severed : Bool,
  defs : Map[String, Node],
  out : Array[Cand],
) -> Unit {
  if pos >= t {
    // boundary: this path consumed all of `before` and is alive — collect the next-readable set.
    if not(severed) {
      for g in sc.greedy {
        emit_greedy_starts(g, out)
      }
    }
    comp_pos_head(sc.positional, pidx, defs, out, [])
    return
  }
  // pos < t: consume before[pos]. 先食い (DR-041 §4): if a greedy reads it, the positional raw-eat is
  // suppressed — so `--port` alone leaves ONLY the pending-value state (not a files=--port reading).
  // NB: the parse evaluator's `greedy_reads` requires the greedy to FULLY consume, so a value-pending
  // greedy (`--port` with no value token) would read as "not firing" there; completion instead uses a
  // TRIGGER-match check (comp_greedy_reads) so a pending trigger still suppresses the positional.
  let supp = not(severed) && comp_greedy_reads(sc, before[pos])
  if not(severed) {
    for g in sc.greedy {
      comp_consume_greedy(g, sc, before, t, pos, pidx, severed, defs, out)
    }
  }
  if not(supp) {
    comp_consume_pos(sc, before, t, pos, pidx, severed, defs, out)
  }
}

///|
/// Whether some greedy entry's FIRST token matches `tok` — the completion 先食い check. Unlike the
/// parse `greedy_reads` (which needs full consumption), this fires on a TRIGGER match even when the
/// entry's value is still pending, so `--port` suppresses the positional raw-eat during completion.
fn comp_greedy_reads(sc : Scope, tok : String) -> Bool {
  for g in sc.greedy {
    if greedy_first_matches(g, tok) {
      return true
    }
  }
  false
}

///|
fn greedy_first_matches(g : Node, tok : String) -> Bool {
  match g {
    Or(alts) => {
      for a in alts {
        if greedy_first_matches(a, tok) {
          return true
        }
      }
      false
    }
    Seq(items) =>
      if items.length() >= 1 {
        match items[0] {
          Exact(s) => s == tok
          _ => false
        }
      } else {
        false
      }
    NativeMatch(ShortCombine(prefix~, entries~)) => {
      // a `-<ch>` cluster start: tok = prefix + a known entry char (value pending is fine).
      let pfx = to_chars(prefix)
      let tc = to_chars(tok)
      if tc.length() <= pfx.length() || not(char_prefix(tc, pfx)) {
        false
      } else {
        let c = tc[pfx.length()]
        let mut hit = false
        for e in entries {
          if e.ch == c {
            hit = true
          }
        }
        hit
      }
    }
    NativeMatch(EqSplit(prefix=_, entries=_)) => false // the space-form Seq trigger covers the match
    CmdSat(name, _) => name == tok
    DdSat(trig) => trig == tok
    Rooted(inner, _) => greedy_first_matches(inner, tok)
    _ => false
  }
}

///|
/// Consume `before[pos]` through one greedy entry, then continue the scope walk (or, if the entry
/// reaches the cut mid-way, emit its pending expectation via comp_seq_entry).
fn comp_consume_greedy(
  g : Node,
  sc : Scope,
  before : Array[String],
  t : Int,
  pos : Int,
  pidx : Int,
  severed : Bool,
  defs : Map[String, Node],
  out : Array[Cand],
) -> Unit {
  match g {
    Or(alts) =>
      // a variable-arity greedy entry (DESIGN §15.4, e.g. --color with 3-num OR 1-str readings): each
      // alternative is a distinct surviving reading; their expectation sets union (DR-060 §1).
      for a in alts {
        comp_consume_greedy(a, sc, before, t, pos, pidx, severed, defs, out)
      }
    Seq(items) =>
      comp_seq_entry(items, 0, sc, before, t, pos, pidx, severed, defs, out)
    NativeMatch(m) =>
      for br in run_matcher(m, before, pos) {
        match br {
          Accept(p2, _) =>
            if p2 > pos {
              comp_scope(sc, before, t, p2, pidx, severed, defs, out)
            }
          Held(_, _) => () // a dead end inside the matcher (excluded, DR-060 §1)
        }
      }
    CmdSat(name, child) =>
      if pos < before.length() && before[pos] == name {
        // enter the subcommand's fresh backbone (DR-041 §4). The parent backbone RESUMES after the
        // child ends, but the PoC's completion collects the child scope's candidates (parent-resume
        // is approximated — see journal 設計 note); global copies live in the child's own greedy, so
        // they surface here naturally (item 3).
        comp_scope(child, before, t, pos + 1, 0, false, defs, out)
      }
    DdSat(trig) =>
      if pos < before.length() && before[pos] == trig {
        comp_scope(sc, before, t, pos + 1, pidx, true, defs, out) // severed: greedy off henceforth
      }
    Rooted(inner, _) =>
      comp_consume_greedy(inner, sc, before, t, pos, pidx, severed, defs, out)
    _ => ()
  }
}

///|
/// Walk a greedy entry's Seq from item `idx` at position `cur`. A value/exact reached AT the cut is a
/// pending expectation (the getopt-同型 value slot, DR-041 §4). 0-token items pass through. A consumed
/// value that type-mismatches is a dead end (no continuation, DR-060 §1).
fn comp_seq_entry(
  items : Array[Node],
  idx : Int,
  sc : Scope,
  before : Array[String],
  t : Int,
  cur : Int,
  pidx : Int,
  severed : Bool,
  defs : Map[String, Node],
  out : Array[Cand],
) -> Unit {
  if idx >= items.length() {
    comp_scope(sc, before, t, cur, pidx, severed, defs, out) // entry fully consumed → resume the scope
    return
  }
  match items[idx] {
    Exact(s) =>
      if cur >= t {
        out.push(cexact(s, WordEnd, s)) // a pending exact (e.g. a multi-exact entry mid-way)
      } else if cur < before.length() && before[cur] == s {
        comp_seq_entry(
          items,
          idx + 1,
          sc,
          before,
          t,
          cur + 1,
          pidx,
          severed,
          defs,
          out,
        )
      }
    // 0-token effect / marker items pass through without consuming.
    Bind(_, _) | EffMark(_, _) | FailMark(_) | DeprMark(_) =>
      comp_seq_entry(
        items,
        idx + 1,
        sc,
        before,
        t,
        cur,
        pidx,
        severed,
        defs,
        out,
      )
    StrArg(name) =>
      comp_seq_value(
        items,
        idx,
        name,
        TStr,
        sc,
        before,
        t,
        cur,
        pidx,
        severed,
        defs,
        out,
      )
    SepArg(name, _) =>
      comp_seq_value(
        items,
        idx,
        name,
        TStr,
        sc,
        before,
        t,
        cur,
        pidx,
        severed,
        defs,
        out,
      )
    NumArg(name) =>
      comp_seq_value(
        items,
        idx,
        name,
        TNum,
        sc,
        before,
        t,
        cur,
        pidx,
        severed,
        defs,
        out,
      )
    _ => ()
  }
}

///|
/// A value slot inside a greedy entry: at the cut it is a pending value candidate; before the cut it
/// raw-consumes the token (type-checked — a NumArg on a non-number is a dead end).
fn comp_seq_value(
  items : Array[Node],
  idx : Int,
  name : String,
  ty : Ty,
  sc : Scope,
  before : Array[String],
  t : Int,
  cur : Int,
  pidx : Int,
  severed : Bool,
  defs : Map[String, Node],
  out : Array[Cand],
) -> Unit {
  if cur >= t {
    out.push(cvalue(ty, name)) // pending value (e.g. before=["--port"] → the port value position)
  } else if cur < before.length() && value_consumable(ty, before[cur]) {
    comp_seq_entry(
      items,
      idx + 1,
      sc,
      before,
      t,
      cur + 1,
      pidx,
      severed,
      defs,
      out,
    )
  }
}

///|
/// Consume `before[pos]` through the positional face at `pidx`, then continue.
fn comp_consume_pos(
  sc : Scope,
  before : Array[String],
  t : Int,
  pos : Int,
  pidx : Int,
  severed : Bool,
  defs : Map[String, Node],
  out : Array[Cand],
) -> Unit {
  if pidx >= sc.positional.length() {
    return // no positional slot to consume this token
  }
  comp_consume_pos_node(
    sc.positional[pidx],
    sc,
    before,
    t,
    pos,
    pidx,
    severed,
    defs,
    out,
  )
}

///|
fn comp_consume_pos_node(
  node : Node,
  sc : Scope,
  before : Array[String],
  t : Int,
  pos : Int,
  pidx : Int,
  severed : Bool,
  defs : Map[String, Node],
  out : Array[Cand],
) -> Unit {
  match node {
    StrArg(_) =>
      comp_scope(sc, before, t, pos + 1, pidx + 1, severed, defs, out)
    SepArg(_, _) =>
      comp_scope(sc, before, t, pos + 1, pidx + 1, severed, defs, out)
    NumArg(_) =>
      if value_consumable(TNum, before[pos]) {
        comp_scope(sc, before, t, pos + 1, pidx + 1, severed, defs, out)
      }
    Exact(s) =>
      if before[pos] == s {
        comp_scope(sc, before, t, pos + 1, pidx + 1, severed, defs, out)
      }
    Ref(r) =>
      // a repeat positional (DR-043): consume one head, then either stop (pidx+1) or take another
      // rep (same pidx). Resolve the head from the registry template Seq([head, Opt(Ref)]).
      match ref_head_node(defs, r) {
        Some(h) =>
          comp_consume_rep_head(
            h, sc, before, t, pos, pidx, severed, defs, out, true,
          )
        None => ()
      }
    Many(inner) =>
      comp_consume_rep_head(
        inner, sc, before, t, pos, pidx, severed, defs, out, true,
      )
    IdxRepeat(_, h, _) =>
      comp_consume_rep_head(
        h, sc, before, t, pos, pidx, severed, defs, out, true,
      )
    BoundedTail(h, _, _) =>
      comp_consume_rep_head(
        h, sc, before, t, pos, pidx, severed, defs, out, true,
      )
    _ => ()
  }
}

///|
/// Consume one repeat head, then offer both "one more rep" (same pidx) and "stop" (pidx+1).
fn comp_consume_rep_head(
  head : Node,
  sc : Scope,
  before : Array[String],
  t : Int,
  pos : Int,
  pidx : Int,
  severed : Bool,
  defs : Map[String, Node],
  out : Array[Cand],
  stay : Bool,
) -> Unit {
  let consumed = match head {
    StrArg(_) | SepArg(_, _) => true
    NumArg(_) => value_consumable(TNum, before[pos])
    Exact(s) => before[pos] == s
    _ => false
  }
  if consumed {
    if stay {
      comp_scope(sc, before, t, pos + 1, pidx, severed, defs, out) // another rep (same pidx)
    }
    comp_scope(sc, before, t, pos + 1, pidx + 1, severed, defs, out) // stop, advance the face
  }
}

// ── boundary emission (the readable set at the cut) ──────────────────────────

///|
/// The trigger spellings a greedy entry offers as its FIRST readable token (DR-060 §1: greedy 面の
/// matcher トリガ綴り). A value-taking entry gets a `Cont` hint (a value must follow); a flag gets
/// `WordEnd` (§9). EqSplit is skipped — its spelling duplicates the space-form Seq satellite.
fn emit_greedy_starts(g : Node, out : Array[Cand]) -> Unit {
  match g {
    Or(alts) =>
      for a in alts {
        emit_greedy_starts(a, out)
      }
    Seq(items) =>
      if items.length() >= 1 {
        match items[0] {
          Exact(trig) => {
            let takes_val = seq_takes_value(items)
            let origin = seq_origin(items, trig)
            out.push(
              cexact(trig, if takes_val { Cont } else { WordEnd }, origin),
            )
          }
          _ => ()
        }
      }
    NativeMatch(m) =>
      match m {
        ShortCombine(prefix~, entries~) =>
          for e in entries {
            let takes = match e.kind {
              TFlag => false
              _ => true
            }
            out.push(
              cexact(
                prefix + e.ch.to_string(),
                if takes {
                  Cont
                } else {
                  WordEnd
                },
                e.name,
              ),
            )
          }
        EqSplit(prefix=_, entries=_) => () // dup of the space-form Seq spelling; skip
      }
    CmdSat(name, _) => out.push(cexact(name, WordEnd, name))
    DdSat(_) => () // the `--` mode-switch marker is not suggested as a completion candidate
    Rooted(inner, _) => emit_greedy_starts(inner, out)
    _ => ()
  }
}

///|
/// Whether a greedy entry Seq has a value slot after its trigger (→ a `Cont` terminal hint, §9).
fn seq_takes_value(items : Array[Node]) -> Bool {
  for it in items {
    match it {
      StrArg(_) | NumArg(_) | SepArg(_, _) => return true
      _ => ()
    }
  }
  false
}

///|
/// The origin element name of a greedy entry: the value / bind name, else the trigger.
fn seq_origin(items : Array[Node], trig : String) -> String {
  for it in items {
    match it {
      StrArg(n) | NumArg(n) | SepArg(n, _) | Bind(n, _) | EffMark(n, _) =>
        return n
      _ => ()
    }
  }
  trig
}

///|
/// The readable expectation of the positional face at `pidx` (value type / literal exact). A repeat /
/// Many can be zero reps, so the NEXT positional head is ALSO readable (both offered). `seen` guards
/// against a positional Ref cycle.
fn comp_pos_head(
  positional : Array[Node],
  pidx : Int,
  defs : Map[String, Node],
  out : Array[Cand],
  seen : Array[Int],
) -> Unit {
  if pidx >= positional.length() {
    return
  }
  comp_pos_head_node(positional[pidx], positional, pidx, defs, out, seen)
}

///|
fn comp_pos_head_node(
  node : Node,
  positional : Array[Node],
  pidx : Int,
  defs : Map[String, Node],
  out : Array[Cand],
  seen : Array[Int],
) -> Unit {
  match node {
    StrArg(name) => out.push(cvalue(TStr, name))
    SepArg(name, _) => out.push(cvalue(TStr, name))
    NumArg(name) => out.push(cvalue(TNum, name))
    Exact(s) => out.push(cexact(s, WordEnd, s))
    Ref(r) =>
      match ref_head_node(defs, r) {
        Some(h) => {
          comp_pos_head_node(h, positional, pidx, defs, out, seen)
          comp_pos_head(positional, pidx + 1, defs, out, seen) // a repeat may take 0 reps → next readable
        }
        None => ()
      }
    Many(inner) => {
      comp_pos_head_node(inner, positional, pidx, defs, out, seen)
      comp_pos_head(positional, pidx + 1, defs, out, seen)
    }
    IdxRepeat(_, h, _) => {
      comp_pos_head_node(h, positional, pidx, defs, out, seen)
      comp_pos_head(positional, pidx + 1, defs, out, seen)
    }
    BoundedTail(h, _, _) => {
      comp_pos_head_node(h, positional, pidx, defs, out, seen)
      comp_pos_head(positional, pidx + 1, defs, out, seen)
    }
    _ => ()
  }
}

///|
/// The head node of a repeat template `Seq([head, Opt(Ref(name))])` in the registry.
fn ref_head_node(defs : Map[String, Node], name : String) -> Node? {
  match defs.get(name) {
    Some(Seq(items)) => if items.length() >= 1 { Some(items[0]) } else { None }
    _ => None
  }
}

///|
fn value_consumable(ty : Ty, tok : String) -> Bool {
  match ty {
    TNum | TInt => parse_number(tok).is_some()
    _ => true // string / flag value slots raw-consume any token (DR-041 §5)
  }
}

// ── top-level complete API (DR-060 §2) ───────────────────────────────────────

///|
/// complete(atomic, {before, after?}) → candidate structure (DR-060). Enumerates the surviving-partial
/// expectation union, dedups, attaches declaration-layer meta (alias / hidden / deprecated), excludes
/// hidden by default (kept queryable via `keep_hidden`), and — when `after` is given — keeps only
/// candidates that can still reach a complete path once `after` is also consumed (after 整合フィルタ §2).
pub fn complete(
  root : Node,
  before : Array[String],
  after? : Array[String] = [],
  defs? : Map[String, Node] = Map::new(),
  meta? : Map[String, CandMeta] = Map::new(),
  keep_hidden? : Bool = false,
) -> Array[Cand] {
  let raw : Array[Cand] = []
  match root {
    ScopeNode(sc) =>
      comp_scope(sc, before, before.length(), 0, 0, false, defs, raw)
    _ => ()
  }
  // dedup (exact by spelling, value by origin+ty), attach meta, apply after-filter + hidden exclusion.
  let out : Array[Cand] = []
  for c0 in raw {
    let c = attach_meta(c0, meta)
    if c.meta.hidden && not(keep_hidden) {
      continue
    }
    if after.length() > 0 && not(after_consistent(root, before, c, after, defs)) {
      continue
    }
    if not(cand_dup(out, c)) {
      out.push(c)
    }
  }
  out
}

///|
fn attach_meta(c : Cand, meta : Map[String, CandMeta]) -> Cand {
  if c.is_value {
    return c
  }
  match meta.get(c.spelling) {
    Some(m) =>
      {
        spelling: c.spelling,
        is_value: c.is_value,
        ty: c.ty,
        origin: c.origin,
        term: c.term,
        meta: m,
      }
    None => c
  }
}

///|
fn cand_dup(out : Array[Cand], c : Cand) -> Bool {
  for x in out {
    if x.is_value && c.is_value {
      if x.origin == c.origin && x.ty == c.ty {
        return true
      }
    } else if not(x.is_value) && not(c.is_value) {
      if x.spelling == c.spelling {
        return true
      }
    }
  }
  false
}

///|
/// after 整合フィルタ (DR-060 §2): does adopting `c` still admit a complete parse of `before ++ c ++
/// after`? A value candidate is realized with a type-appropriate probe; an exact with its spelling.
fn after_consistent(
  root : Node,
  before : Array[String],
  c : Cand,
  after : Array[String],
  defs : Map[String, Node],
) -> Bool {
  let toks : Array[String] = []
  for b in before {
    toks.push(b)
  }
  if c.is_value {
    toks.push(probe_value(c.ty))
  } else {
    toks.push(c.spelling)
  }
  for a in after {
    toks.push(a)
  }
  match parse(root, toks, defs~) {
    Success(_) => true
    Ambiguous(_) => true // ≥1 complete path exists (DR-060 §2 asks for at least one)
    Failure(_) => false
  }
}

///|
fn probe_value(ty : Ty) -> String {
  match ty {
    TNum | TInt => "0"
    _ => "x"
  }
}

///|
/// Build the completion meta map (spelling → CandMeta) from the definition — the declaration-layer
/// reference read (DR-056). Options are canonical; alias declarations mark their spellings is_alias.
/// (hidden is not modeled in this PoC — DR-058 §1 hidden is a display-layer concern deferred here.)
pub fn completion_meta(def : Definition) -> Map[String, CandMeta] {
  let m : Map[String, CandMeta] = Map::new()
  for e in def.options {
    for l in long_of(e) {
      m.set("--" + l, {
        is_alias: false,
        hidden: false,
        deprecated: e.deprecated,
      })
    }
    for c in e.short {
      m.set("-" + c.to_string(), {
        is_alias: false,
        hidden: false,
        deprecated: e.deprecated,
      })
    }
  }
  for a in def.aliases {
    for c in a.short {
      m.set("-" + c.to_string(), {
        is_alias: true,
        hidden: false,
        deprecated: a.deprecated,
      })
    }
    // long alias base spelling (§16 の再導出と整合): the alias name is the base long, if the alias has a name.
    match a.name {
      Some(n) =>
        m.set("--" + n, {
          is_alias: true,
          hidden: false,
          deprecated: a.deprecated,
        })
      None => ()
    }
  }
  m
}
