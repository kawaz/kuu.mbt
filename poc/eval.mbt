// eval.mbt — bounded path-search evaluator (DR-038 / DR-041 / DR-043).
//
// The core contract (DR-038): a parse succeeds iff exactly ONE complete path
// consumes all tokens. 0 => fail (show held Error), 1 => commit, 2+ => ambiguous.
// There is NO longest-match rule; "long wins" only emerges because short paths
// leave unconsumed tokens and drop out (DR-038 §「最長一致」).
//
// `defs` is the template registry (DR-020 / DR-043): it resolves `Ref` nodes so a
// repeat can be a recursive `Seq([head, Opt(Ref(self))])` rather than a closure
// primitive. It threads through every walk function unchanged.

///|
/// The outcome of trying a node against a token prefix.
/// A missing branch == Reject (silently dropped, DR-037). `Held` == Error
/// (retained for failure display). `Accept(new_pos, bindings)` == a reading.
enum Branch {
  Accept(Int, Array[Binding]) // (new position, accumulated bindings)
  Held(ParseError, Array[Binding]) // a DR-037 Error + the partial state (acc) at the error point.
  //                                   the partial state (F-039) carries a failure-action selected
  //                                   before the error; the ParseError has element/argv_pos/kind/message.
} derive(Show)

///|
/// Final parse outcome — a discriminated union of 3 values (DR-053 §1). Success carries the result
/// bindings; Failure carries ALL held errors (primary = max argv_pos) plus the failure-action / help
/// materials; Ambiguous carries every distinct interpretation (as result-object bindings).
pub(all) enum Outcome {
  Success(Array[Binding])
  Failure(FailureData)
  Ambiguous(AmbiguousData)
} derive(Eq, Show)

///|
/// DR-053 §2/§4: a failed parse. `errors` holds ALL held Errors (別候補経路の別 Error); primary is
/// the max-argv_pos subset (computed by the renderer). `fired_action` is the failure-action that
/// fired (help), if any — it and `errors` coexist (DR-053: 表示が置換されるだけ、構造は残る).
/// `help_entry` (誘導行の素材) / `tried_triggers` (Did you mean の素材) are fields; wording is the renderer's.
pub(all) struct FailureData {
  errors : Array[ParseError]
  fired_action : String?
  help_entry : String?
  tried_triggers : Array[String]
} derive(Eq, Show)

///|
/// DR-053 §3: an ambiguous parse. `interpretations` enumerates EVERY distinct complete path as a
/// result-object view (its bindings); `help_entry` is the same 誘導行 material as a failure.
pub(all) struct AmbiguousData {
  interpretations : Array[Array[Binding]]
  help_entry : String?
} derive(Eq, Show)

///|
/// A plain value bind = the SET degenerate form of an effect (DR-045 §1).
fn mkb(key : String, value : Value, source : Source) -> Binding {
  { key, op: Set, value, source, scope: [], link: 0 }
}

///|
/// A non-set effect binding (default / unset / empty). The operand is a placeholder
/// (VBool(false)) — default/unset/empty carry no operand (DR-045 table).
fn mk_eff(key : String, op : EffectOp, source : Source) -> Binding {
  { key, op, value: VBool(false), source, scope: [], link: 0 }
}

///|
/// A failure-action marker binding (DR-048): key `@act:<name>`, value = the argv position where
/// the action was selected (for argv-min tie-break). It rides in the effect column like any
/// binding, so it is captured by both surfaced Accepts and (via the extended Held) dead ends.
fn action_marker(name : String, pos : Int) -> Binding {
  {
    key: "@act:" + name,
    op: Set,
    value: VNum(pos.to_double()),
    source: Cli,
    scope: [],
    link: 0,
  }
}

///|
/// A deprecation marker binding (DR-058): key `@depr:<element>`, recording that a deprecated entry
/// (DR-057 alias) was used to reach the canonical cell. Rides in the effect column like an action
/// marker; the result builder skips it (bookkeeping, not a value), and `warnings_of` collects it.
fn depr_marker(element : String) -> Binding {
  {
    key: "@depr:" + element,
    op: Set,
    value: VBool(false),
    source: Cli,
    scope: [],
    link: 0,
  }
}

///|
/// Whether a result key is a deprecation marker (`@depr:...`).
pub fn is_depr_key(k : String) -> Bool {
  let p = "@depr:"
  k.length() >= p.length() && k.substring(start=0, end=p.length()) == p
}

///|
/// The deprecated canonical element names recorded on a Success outcome (DR-058 warnings). Each
/// `@depr:<element>` marker in the winning path's bindings yields one warning (deduped, sorted by
/// the renderer). A non-Success outcome carries no single path, so no warnings here (PoC scope).
pub fn warnings_of(o : Outcome) -> Array[String] {
  let out : Array[String] = []
  match o {
    Success(binds) =>
      for b in binds {
        if is_depr_key(b.key) {
          let name = b.key.substring(start=6, end=b.key.length()) // drop "@depr:" (6 chars)
          if not(str_mem(out, name)) {
            out.push(name)
          }
        }
      }
    _ => ()
  }
  out
}

///|
fn str_mem(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

///|
/// The action name if `b` is a failure-action marker, else None.
fn action_of(b : Binding) -> String? {
  if is_action_key(b.key) {
    Some(b.key.substring(start=5, end=b.key.length())) // drop the "@act:" prefix (5 chars)
  } else {
    None
  }
}

///|
/// Whether a result key is a failure-action marker (`@act:...`), which the result builder and
/// renderers skip (it is search bookkeeping, not a result value).
pub fn is_action_key(k : String) -> Bool {
  let p = "@act:"
  k.length() >= p.length() && k.substring(start=0, end=p.length()) == p
}

///|
/// Nest a set of bindings one level deeper under `label` (DR-025: a name / command
/// scope prepends its label to every binding produced inside it, outermost first).
/// A LINK binding (DR-042 global link-sync) with `link > 0` ESCAPES this level: it skips the
/// prepend and decrements its counter, climbing out of the scopes BELOW its declaration. Once
/// the counter reaches 0 it nests like any binding — so a global declared at an intermediate
/// scope (shadow, DR-042) settles at THAT declaring scope, not the absolute root (a root global
/// escapes all the way, its counter = firing depth).
fn nest(label : String, binds : Array[Binding]) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in binds {
    if b.link > 0 {
      // still below the declaring scope: escape this level, one fewer to climb.
      out.push({ ..b, link: b.link - 1 })
    } else {
      let sc2 : Array[String] = [label]
      for s in b.scope {
        sc2.push(s)
      }
      out.push({
        key: b.key,
        op: b.op,
        value: b.value,
        source: b.source,
        scope: sc2,
        link: b.link,
      })
    }
  }
  out
}

///|
/// Apply `nest` to every Accept branch's bindings (Held passes through).
fn nest_branches(label : String, brs : Array[Branch]) -> Array[Branch] {
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Accept(p, bs) => out.push(Accept(p, nest(label, bs)))
      Held(pe, bs) => out.push(Held(pe, bs))
    }
  }
  out
}

///|
fn cat(a : Array[Binding], b : Array[Binding]) -> Array[Binding] {
  let r : Array[Binding] = []
  for x in a {
    r.push(x)
  }
  for x in b {
    r.push(x)
  }
  r
}

///|
/// Evaluate a node at `pos`, returning every reading (Accept) and held Error.
fn eval(
  node : Node,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Array[Branch] {
  match node {
    Exact(s) =>
      if pos < toks.length() && toks[pos] == s {
        [Accept(pos + 1, [])]
      } else {
        []
      }
    StrArg(name) =>
      if pos < toks.length() {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else {
        []
      }
    SepArg(name, sep) =>
      // separator split (DR-034): consume 1 token, emit one Set effect per split piece.
      if pos < toks.length() {
        [Accept(pos + 1, sep_binds(name, toks[pos], sep))]
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() {
        match parse_number(toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, toks[pos], pos), [])]
        }
      } else {
        []
      }
    FilterArg(name, max) => filter_arg_eval(name, max, toks, pos, [])
    ReqArg(name) => req_arg_eval(name, toks, pos, [])
    Bind(name, v) => [Accept(pos, [mkb(name, v, Cli)])]
    EffMark(name, op) =>
      // A non-set effect (DR-045): consumes 0 tokens, applies `op` to the named cell.
      // The op becomes part of the effect-sequence identity (DR-038 精密化) via the
      // Binding's `op` field, so `--no-color` (unset) and `--color` (set) on the same
      // cell are distinct effects.
      [Accept(pos, [mk_eff(name, op, Cli)])]
    FailMark(name) =>
      // A failure-action mark (DR-048): 0-token, records `name` selected at this argv position.
      // The position rides in the marker's value so a multi-action failure fires the argv-min one.
      [Accept(pos, [action_marker(name, pos)])]
    DeprMark(name) =>
      // A deprecation mark (DR-058): 0-token, records that a deprecated entry (DR-057 alias) reached
      // the canonical cell `name`. The value binding sits alongside; only a warning is added.
      [Accept(pos, [depr_marker(name)])]
    Or(alts) => {
      let out : Array[Branch] = []
      for a in alts {
        for b in eval(a, toks, pos, defs) {
          out.push(b)
        }
      }
      out
    }
    Seq(items) => eval_seq(items, 0, toks, pos, [], defs)
    Many(inner) => eval_many(inner, toks, pos, [], defs)
    Scoped(label, body) =>
      // A name creates a result scope (DR-025): bindings produced inside nest under
      // `label`. Path counting is unaffected (nesting only tags the bindings).
      nest_branches(label, eval(body, toks, pos, defs))
    ScopeNode(sc) => eval_scope(sc, toks, pos, defs)
    NativeMatch(m) => run_matcher(m, toks, pos)
    Ref(name) =>
      // Plain resolution: recurse into the registered template. On the positional
      // spine `Ref` is instead unfolded porously (scope_consume). Here (inside an Or
      // head, a matcher-free context, etc.) it is the ordinary recursion, bounded by
      // the zero-progress guard baked into the template's head.
      match defs.get(name) {
        Some(tpl) => eval(tpl, toks, pos, defs)
        None => []
      }
    DdSat(trigger) =>
      // A dd satellite reads its trigger like any greedy exact matcher. This is
      // what makes greedy_reads/先食い suppress a raw-eat of `--`. The SEVER on
      // firing is applied by the spine walk (scope_step step A), not here.
      if pos < toks.length() && toks[pos] == trigger {
        [Accept(pos + 1, [])]
      } else {
        []
      }
    CmdSat(name, child) =>
      // A command satellite reads its name exactly, then the child scope (a fresh
      // backbone) consumes from pos+1. greedy_reads/先食い sees these accepts and
      // protects the command name from a positional raw-eat.
      if pos < toks.length() && toks[pos] == name {
        // the subcommand is a result scope: its bindings nest under the command name,
        // plus a presence marker so an invoked-but-empty command still appears as {}.
        mark_scope(
          name,
          nest_branches(name, eval_scope(child, toks, pos + 1, defs)),
        )
      } else {
        []
      }
    Rooted(inner, depth) => {
      // evaluate the inner node, but mark every binding as a link that escapes `depth` result-nesting
      // levels (= the scopes this satellite sits BELOW its declaration) so it lands on the declaring
      // scope's entity (DR-042 global link-sync). depth = firing depth for a root global (escapes all).
      let out : Array[Branch] = []
      for b in eval(inner, toks, pos, defs) {
        match b {
          Accept(p, bs) => {
            let marked : Array[Binding] = []
            for x in bs {
              marked.push({
                key: x.key,
                op: x.op,
                value: x.value,
                source: x.source,
                scope: x.scope,
                link: depth,
              })
            }
            out.push(Accept(p, marked))
          }
          Held(pe, bs) => out.push(Held(pe, bs))
        }
      }
      out
    }
    NoDashStr(name) =>
      // pre_filter (DR-037): consume the token only if it is NOT `-`-prefixed; a dashed
      // token REJECTS (no reading), which is what stops a permissive repeat from eating a
      // following `--socket` / `--upstream` trigger in a no-backbone region.
      if pos < toks.length() && !starts_dash(toks[pos]) {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else {
        []
      }
    IdxRepeat(label, head, min) =>
      idx_repeat_eval(label, head, min, toks, pos, defs)
    BoundedTail(head, budget, _) =>
      // Off-spine fallback (BoundedTail normally lives on the positional spine, handled
      // porously by scope_consume with 取り分選好). Here it degrades to the nested-Opt form
      // (0..budget heads) — correct token acceptance, minus the preference/先食い of the spine.
      eval(bounded_opt(head, budget), toks, pos, defs)
  }
}

///|
/// The nested-Opt equivalent of a bounded tail: 0..budget heads (LOWERING §B.8). Used for the
/// off-spine eval fallback; the spine path (scope_consume) instead threads the budget porously.
fn bounded_opt(head : Node, budget : Int) -> Node {
  if budget <= 0 {
    Seq([])
  } else {
    Or([Seq([head, bounded_opt(head, budget - 1)]), Seq([])])
  }
}

///|
/// A `kind: parse` held Error for a value that failed to parse as a number (DR-053 §2).
fn pe_parse(element : String, tok : String, pos : Int) -> ParseError {
  {
    element,
    argv_pos: pos,
    kind: KParse,
    message: "\"\{tok}\" is not a number",
  }
}

///|
/// A `kind: parse` held Error for a structurally-mandatory value that had NO token to consume
/// (構造的必須の不成立, DR-065 §3 / DR-053 全保持): the spine (or a repeat's mandatory head) needed a
/// token for `element` but the argv was exhausted. argv_pos = pos = argv.length (where the token was
/// requested). A layer apart from an explicit `required` constraint (ReqArg → KConstraint).
fn pe_missing(element : String, pos : Int) -> ParseError {
  { element, argv_pos: pos, kind: KParse, message: "missing operand for \{element}" }
}

///|
/// FilterArg (DR-053 kind demo): parse a number then apply a max post-filter. A parse failure is
/// `kind: parse`; a value above `max` is `kind: filter` (post_filter reject). `acc` is the partial
/// state carried on the held Error (F-039).
fn filter_arg_eval(
  name : String,
  max : Int,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  if pos < toks.length() {
    match parse_number(toks[pos]) {
      Some(d) =>
        if d > max.to_double() {
          [
            Held(
              {
                element: name,
                argv_pos: pos,
                kind: KFilter,
                message: "\{name} value \{toks[pos]} exceeds max \{max}",
              },
              acc,
            ),
          ]
        } else {
          [Accept(pos + 1, cat(acc, [mkb(name, VNum(d), Cli)]))]
        }
      None => [Held(pe_parse(name, toks[pos], pos), acc)]
    }
  } else {
    []
  }
}

///|
/// ReqArg (DR-047 値充足 / DR-053 kind: constraint): consume a token if present; NO token to consume
/// is a `kind: constraint` held Error (required 未充足) — a delayed-predicate violation as an Error,
/// not a silent Reject. `acc` is the partial state on the held Error.
fn req_arg_eval(
  name : String,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
) -> Array[Branch] {
  if pos < toks.length() {
    [Accept(pos + 1, cat(acc, [mkb(name, VStr(toks[pos]), Cli)]))]
  } else {
    [
      Held(
        {
          element: name,
          argv_pos: pos,
          kind: KConstraint,
          message: "required \{name} is missing",
        },
        acc,
      ),
    ]
  }
}

///|
fn starts_dash(s : String) -> Bool {
  for c in s {
    return c == '-'
  }
  false
}

///|
/// The first char of a string (String indexing yields a UTF-16 code unit, not a Char, so we
/// take the first char by iteration — matching how the split loop reads chars).
fn first_char(s : String) -> Char {
  for c in s {
    return c
  }
  ',' // unreachable for a non-empty separator
}

///|
/// Split `s` on the first char of `sep` (DR-034 single-char separator). `a,b,c` / "," → [a,b,c].
fn split_on(s : String, sep : String) -> Array[String] {
  let sepc = first_char(sep)
  let out : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == sepc {
      out.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  out.push(cur)
  out
}

///|
/// One Set-effect binding per split piece (DR-034 separator + DR-045 set 縮退形).
fn sep_binds(name : String, tok : String, sep : String) -> Array[Binding] {
  let out : Array[Binding] = []
  for part in split_on(tok, sep) {
    out.push(mkb(name, VStr(part), Cli))
  }
  out
}

///|
/// Array-presence marker: `{key:"[]"}` at the array's scope, so an empty array still
/// appears in the result. The renderers / result builder treat "[]" and "{}" as sentinels.
fn array_marker(label : String) -> Binding {
  {
    key: "[]",
    op: Set,
    value: VBool(false),
    source: Cli,
    scope: [label],
    link: 0,
  }
}

///|
/// Prepend an object-presence marker `{key:"{}"}` at scope `[name]` to each Accept, so an
/// invoked command scope appears (as at least `{}`) even when it produced no bindings.
fn mark_scope(name : String, brs : Array[Branch]) -> Array[Branch] {
  let marker : Binding = {
    key: "{}",
    op: Set,
    value: VBool(false),
    source: Cli,
    scope: [name],
    link: 0,
  }
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Accept(p, bs) => out.push(Accept(p, cat([marker], bs)))
      Held(pe, bs) => out.push(Held(pe, bs))
    }
  }
  out
}

///|
/// Tag a rep's bindings under `[label, "#k"]` (a result-array index). Link bindings escape.
fn nest_index(label : String, rep : Int, bs : Array[Binding]) -> Array[Binding] {
  let seg = "#" + rep.to_string()
  let out : Array[Binding] = []
  for b in bs {
    if b.link > 0 {
      out.push({ ..b, link: b.link - 1 }) // escape this rep level too (below declaration)
    } else {
      let sc2 : Array[String] = [label, seg]
      for s in b.scope {
        sc2.push(s)
      }
      out.push({
        key: b.key,
        op: b.op,
        value: b.value,
        source: b.source,
        scope: sc2,
        link: 0,
      })
    }
  }
  out
}

///|
/// Greedy-max named indexed-array repeat (DR-043 §取り分の選好, default greedy). Consumes as
/// many reps as the head allows (each rep tagged `[label, "#k"]`), deterministically. For
/// the authsock raw pattern the split is bounded by the head's Reject (NoDashStr) or exact
/// mismatch, so greedy-max lands the correct division with no downstream backtrack; without
/// the pre_filter it over-consumes and the wrong parse wins SILENTLY (DR-043 §auto-narrowing
/// 却下 — the user's pre_filter is the fix).
fn idx_repeat_eval(
  label : String,
  head : Node,
  min : Int,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Array[Branch] {
  let acc : Array[Binding] = [array_marker(label)]
  let mut cur = pos
  let mut rep = 0
  let mut go = true
  while go {
    let p2 = idx_one(head, label, rep, toks, cur, defs, acc)
    if p2 > cur {
      cur = p2
      rep = rep + 1
    } else {
      go = false
    }
  }
  if rep < min {
    []
  } else {
    [Accept(cur, acc)]
  }
}

///|
/// Consume one rep of `head` at `pos`, pushing its indexed bindings to `acc`. Returns the
/// new position, or `pos` unchanged if the head cannot advance (greedy-max stop).
fn idx_one(
  head : Node,
  label : String,
  rep : Int,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
  acc : Array[Binding],
) -> Int {
  for b in eval(head, toks, pos, defs) {
    match b {
      Accept(p2, bs) =>
        if p2 > pos {
          for x in nest_index(label, rep, bs) {
            acc.push(x)
          }
          return p2
        }
      Held(_, _) => ()
    }
  }
  pos
}

///|
/// Thread `pos` through a Seq; bindings accumulate; a Held dead-ends its branch.
fn eval_seq(
  items : Array[Node],
  idx : Int,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
  defs : Map[String, Node],
) -> Array[Branch] {
  if idx >= items.length() {
    return [Accept(pos, acc)]
  }
  let out : Array[Branch] = []
  for b in eval(items[idx], toks, pos, defs) {
    match b {
      Accept(p2, bs) =>
        for r in eval_seq(items, idx + 1, toks, p2, cat(acc, bs), defs) {
          out.push(r)
        }
      Held(pe, bs) => out.push(Held(pe, bs))
    }
  }
  out
}

///|
/// Unbounded repeat (>= 0). The `p2 > pos` guard prevents zero-progress loops.
fn eval_many(
  inner : Node,
  toks : Array[String],
  pos : Int,
  acc : Array[Binding],
  defs : Map[String, Node],
) -> Array[Branch] {
  let out : Array[Branch] = [Accept(pos, acc)] // 0 reps
  for b in eval(inner, toks, pos, defs) {
    match b {
      Accept(p2, bs) =>
        if p2 > pos {
          for r in eval_many(inner, toks, p2, cat(acc, bs), defs) {
            out.push(r)
          }
        }
      Held(pe, bs) => out.push(Held(pe, bs))
    }
  }
  out
}

// ── two-face scope (DR-041 §4) ──────────────────────────────────────────────
//
// `severed` is the dd mode (DR-042 ⑤): once `--` is consumed, the greedy face is
// off for the rest of the walk and everything falls raw into positionals.

///|
/// A greedy entry "reads" at `pos` iff it consumes >= 1 token there. This is the
/// exact 先食い predicate (DR-041 §4): when true, positional raw pass-through of
/// the current token is suppressed. (Only consulted when not severed.)
fn greedy_reads(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Bool {
  for g in sc.greedy {
    for b in eval(g, toks, pos, defs) {
      match b {
        Accept(p2, _) => if p2 > pos { return true }
        Held(_, _) => ()
      }
    }
  }
  false
}

///|
/// Whether raw pass-through of the token at `pos` is suppressed. 先食い is
/// greedy-ONLY (DR-041 §4, rev): a raw-eat is suppressed iff some greedy entry
/// reads the token. The dd `--` is covered because the dd satellite is itself a
/// greedy entry (DdSat) — no dd special case. Once severed, nothing is suppressed.
fn suppressed(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  severed : Bool,
  defs : Map[String, Node],
) -> Bool {
  if severed {
    return false // past `--`: everything falls raw, even a second `--`
  }
  greedy_reads(sc, toks, pos, defs)
}

///|
fn eval_scope(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  defs : Map[String, Node],
) -> Array[Branch] {
  scope_step(sc, toks, pos, 0, [], false, defs)
}

///|
/// Walk sc.positional[pidx..] from `pos`. Offers (A) a greedy interjection (only
/// when not severed) and (B) advancing the positional face.
fn scope_step(
  sc : Scope,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  let out : Array[Branch] = []
  // (A) greedy interjection — a fired greedy entry raw-consumes its own value
  // slots (getopt 同型); re-enter at the same pidx (positional face untouched).
  // Firing a dd or command satellite additionally severs the rest of the walk
  // (DR-041 §4: the fired greedy's continuation is its internal consumption).
  if !severed {
    for g in sc.greedy {
      // Only dd severs (its continuation is internal consumption, 一体). A command
      // (CmdSat) does NOT sever — after its subtree completes the parent backbone
      // RESUMES (DR-041 §4, rev). The command's uniqueness comes from 早閉じ抑制 below,
      // not from severing the parent.
      let fires_severed = match g {
        DdSat(_) => true
        _ => false
      }
      for b in eval(g, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              for
                r in scope_step(
                  sc,
                  toks,
                  p2,
                  pidx,
                  cat(acc, bs),
                  severed || fires_severed,
                  defs,
                ) {
                out.push(r)
              }
            }
          Held(pe, bs) => out.push(Held(pe, bs))
        }
      }
    }
  }
  // (B) advance the positional face
  if pidx >= sc.positional.length() {
    // 早閉じ抑制 (DR-041 §4, rev): a scope with a backbone cannot complete while one of
    // its own greedy entries can read the next token — "that which can be read here, is
    // read here". This makes "the innermost scope that can read wins" emerge without any
    // cross-path priority: a child cannot exit early leaving a token its greedy could
    // take, so the parent never gets a competing route. Severed scopes (past `--`) have
    // greedy off and always may close.
    if severed || !greedy_reads(sc, toks, pos, defs) {
      out.push(Accept(pos, acc)) // positional exhausted => acceptable scope end
    }
  } else {
    for
      r in scope_consume(
        sc,
        sc.positional[pidx],
        toks,
        pos,
        pidx,
        acc,
        severed,
        defs,
      ) {
      out.push(r)
    }
  }
  out
}

///|
/// Consume one positional item, then continue at pidx+1 (Many/Ref stay at pidx).
fn scope_consume(
  sc : Scope,
  item : Node,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  match item {
    StrArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx + 1,
          cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed,
          defs,
        )
      } else if pos >= toks.length() {
        // 構造的必須の不成立 (DR-065 §3): the spine needs a token for `name` but the argv is
        // exhausted. kind:parse (経路構築の失敗), argv_pos = argv.length. Held (not a silent Reject)
        // so the 0-path failure carries this Error (CONFORMANCE §2 / DR-053 全保持).
        [Held(pe_missing(name, pos), acc)]
      } else {
        [] // a greedy trigger sits here (先食い); let greedy take it, the spine stays pending
      }
    SepArg(name, sep) =>
      // plain separator positional (DR-034): 先食い-aware, splits the token into pieces.
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx + 1,
          cat(acc, sep_binds(name, toks[pos], sep)),
          severed,
          defs,
        )
      } else if pos >= toks.length() {
        // exhausted mandatory separator positional: same 構造的必須の不成立 shape as StrArg.
        [Held(pe_missing(name, pos), acc)]
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          // DR-041 §5: number positional rejecting a token is a held Error, not a
          // structural refusal — no prefix guard.
          Some(d) =>
            scope_step(
              sc,
              toks,
              pos + 1,
              pidx + 1,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              defs,
            )
          // partial state = the scope acc so far (a failure-action selected before this number
          // positional's parse error is captured here, DR-048 candidate defs / F-039).
          None => [Held(pe_parse(name, toks[pos], pos), acc)]
        }
      } else if pos >= toks.length() {
        // 構造的必須の不成立 (DR-065 §3): a number positional (e.g. complete-path-count's `b`) whose
        // token the argv never supplied. StrArg carried this Held; NumArg silently dropped it (empty
        // errors on a 0-path failure), so a missing 2nd positional produced no Error. Emit the same
        // missing_operand Held (kind:parse, argv_pos = argv.length) so `errors` is non-empty.
        [Held(pe_missing(name, pos), acc)]
      } else {
        []
      }
    FilterArg(name, max) =>
      // number + max post-filter positional (DR-053 kind demo): parse fail = kind parse, > max =
      // kind filter; either continues the spine on success. 先食い-aware.
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) =>
            if d > max.to_double() {
              [
                Held(
                  {
                    element: name,
                    argv_pos: pos,
                    kind: KFilter,
                    message: "\{name} value \{toks[pos]} exceeds max \{max}",
                  },
                  acc,
                ),
              ]
            } else {
              scope_step(
                sc,
                toks,
                pos + 1,
                pidx + 1,
                cat(acc, [mkb(name, VNum(d), Cli)]),
                severed,
                defs,
              )
            }
          None => [Held(pe_parse(name, toks[pos], pos), acc)]
        }
      } else {
        []
      }
    ReqArg(name) =>
      // required string positional (DR-047 / DR-053 kind constraint): no token to consume is a
      // kind:constraint held Error (required 未充足), not a silent Reject.
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx + 1,
          cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed,
          defs,
        )
      } else if pos >= toks.length() {
        [
          Held(
            {
              element: name,
              argv_pos: pos,
              kind: KConstraint,
              message: "required \{name} is missing",
            },
            acc,
          ),
        ]
      } else {
        [] // a greedy trigger sits here (先食い); let greedy take it, req stays pending
      }
    Exact(s) =>
      if pos < toks.length() && toks[pos] == s {
        scope_step(sc, toks, pos + 1, pidx + 1, acc, severed, defs)
      } else {
        []
      }
    // A repeat item (DR-043): >= 1 head, unfolded POROUSLY on the spine. Consume the
    // mandatory head, then offer either "stop" (advance to pidx+1, fewer reps) or "one
    // more rep" (re-enter at the SAME pidx). "more" goes through scope_step, so greedy
    // interjects between reps for free (背骨に留まる).
    //
    // 取り分の選好 (DR-043 §取り分の選好): the split between adjacent closures is not an
    // ambiguity — it is one interpretation's freedom of division. greedy (default) prefers
    // the LONGER share (try "more" first), lazy the shorter ("stop" first). We commit to
    // the FIRST preference whose continuation reaches a FULL parse and PRUNE the other —
    // it is a different share of the SAME closure, not a competing complete path. If
    // neither completes, both are kept (failure / genuinely-different completions surface
    // unchanged). The preference is applied PER head-reading, so structurally different
    // completions (or-branch / reading differences) remain distinct → still ambiguous.
    Ref(name) => {
      let head = ref_head(defs, name)
      let lazy = ref_is_lazy(defs, name)
      let target = toks.length()
      let out : Array[Branch] = []
      for b in consume_head(sc, head, toks, pos, severed, defs) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              let acc2 = cat(acc, bs)
              let stop = scope_step(sc, toks, p2, pidx + 1, acc2, severed, defs)
              // "more" = one more OPTIONAL rep of `name`; a missing_operand-for-name inside it is a
              // legitimate stop (this rep already succeeded), not a structural failure → drop it.
              let more = drop_optional_missing(
                scope_step(sc, toks, p2, pidx, acc2, severed, defs),
                head_name(head),
              )
              let chosen = if lazy {
                if has_full(stop, target) {
                  stop
                } else if has_full(more, target) {
                  more
                } else {
                  cat_branches(stop, more)
                }
              } else if has_full(more, target) {
                more
              } else if has_full(stop, target) {
                stop
              } else {
                cat_branches(stop, more)
              }
              for r in chosen {
                out.push(r)
              }
            }
          Held(pe, bs) => out.push(Held(pe, bs))
        }
      }
      out
    }
    BoundedTail(head, budget, lazy) =>
      // A bounded repeat tail (DR-043 max 有限 / LOWERING §B.8): consume 0..budget more heads
      // POROUSLY on the spine. Same 取り分選好 as the Ref path (greedy prefers "more", lazy
      // "stop"), and consume_head keeps 先食い — so a bounded repeat composes like an unbounded
      // one, but the recursion depth is the budget (no self-ref).
      bounded_tail_step(
        sc, head, budget, lazy, toks, pos, pidx, acc, severed, defs,
      )
    Many(inner) => {
      let out : Array[Branch] = []
      for r in scope_step(sc, toks, pos, pidx + 1, acc, severed, defs) { // 0 reps
        out.push(r)
      }
      for r in scope_consume_rep(sc, inner, toks, pos, pidx, acc, severed, defs) { // 1 rep
        out.push(r)
      }
      out
    }
    ScopeNode(child) => {
      // DR-042 ⑤: a child scope runs its own (fresh, unsevered) walk; the parent
      // greedy face does not interject during it.
      let out : Array[Branch] = []
      for b in eval_scope(child, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            for
              r in scope_step(
                sc,
                toks,
                p2,
                pidx + 1,
                cat(acc, bs),
                severed,
                defs,
              ) {
              out.push(r)
            }
          Held(pe, bs) => out.push(Held(pe, bs))
        }
      }
      out
    }
    other => {
      // any other node as a positional item: eval plainly, then continue.
      let out : Array[Branch] = []
      for b in eval(other, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            for
              r in scope_step(
                sc,
                toks,
                p2,
                pidx + 1,
                cat(acc, bs),
                severed,
                defs,
              ) {
              out.push(r)
            }
          Held(pe, bs) => out.push(Held(pe, bs))
        }
      }
      out
    }
  }
}

///|
/// A bounded repeat tail (DR-043 max 有限): consume 0..budget more heads porously, with the
/// 取り分選好 preference. `stop` advances the spine (take no more here); `more` consumes one
/// head (先食い-aware via consume_head) and recurses with budget-1. greedy (default) commits to
/// `more` first, lazy to `stop`; the first preference reaching a FULL parse is committed and
/// the other pruned (a different SHARE of the same closure, not a competing complete path,
/// DR-038 無傷). If neither completes, both are kept. `has_full` uses the whole-input length
/// (exact for a root/last-scope repeat, approximate under a non-final scope — same flag as the
/// Ref path, 3rd installment).
fn bounded_tail_step(
  sc : Scope,
  head : Node,
  budget : Int,
  lazy : Bool,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  let target = toks.length()
  let stop = scope_step(sc, toks, pos, pidx + 1, acc, severed, defs)
  let more : Array[Branch] = if budget >= 1 {
    let out : Array[Branch] = []
    for b in consume_head(sc, head, toks, pos, severed, defs) {
      match b {
        Accept(p2, bs) =>
          if p2 > pos {
            for
              r in bounded_tail_step(
                sc,
                head,
                budget - 1,
                lazy,
                toks,
                p2,
                pidx,
                cat(acc, bs),
                severed,
                defs,
              ) {
              out.push(r)
            }
          }
        Held(pe, bs) => out.push(Held(pe, bs))
      }
    }
    // The BoundedTail is the OPTIONAL portion (after `min` mandatory heads, LOWERING §B.8), so a
    // missing_operand-for-head inside it is a stop signal, not a failure — same filter as the Ref path.
    drop_optional_missing(out, head_name(head))
  } else {
    []
  }
  if lazy {
    if has_full(stop, target) {
      stop
    } else if has_full(more, target) {
      more
    } else {
      cat_branches(stop, more)
    }
  } else if has_full(more, target) {
    more
  } else if has_full(stop, target) {
    stop
  } else {
    cat_branches(stop, more)
  }
}

///|
/// Consume one repeat head on the spine. A value primitive respects 先食い (a greedy
/// trigger between reps is not raw-eaten as a value); a non-primitive head (a ref to
/// a template, e.g. `color`) is evaluated plainly (head-internal is not spine-porous,
/// but the rep boundary still is via scope_step).
///
/// TOKEN EXHAUSTION (DR-065 §3, held-error parity): when the argv is exhausted (not merely 先食い-
/// suppressed) the mandatory head cannot be satisfied — emit a missing_operand Held, exactly as
/// scope_consume does for a plain spine positional. An unbounded `repeat{min:N}` unrolls to N-1
/// mandatory StrArg heads (scope_consume, which already held) + a Ref tail whose head passes through
/// HERE; without this the Ref's min-th mandatory head dropped silently, so a min-unmet unbounded
/// repeat failed with EMPTY errors while the bounded (BoundedTail) form emitted the Held (min2-
/// standalone::case#1). The Held rides through the Ref/BoundedTail "more" branch too, but that branch
/// is a CHOICE against "stop": has_full(stop) prunes it whenever the closure can terminate, so a
/// satisfied repeat keeps its Accept and the exhaustion Held only surfaces on a genuine 0-path fail.
fn consume_head(
  sc : Scope,
  head : Node,
  toks : Array[String],
  pos : Int,
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  match head {
    StrArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        [Accept(pos + 1, [mkb(name, VStr(toks[pos]), Cli)])]
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), [])]
      } else {
        [] // 先食い: a greedy trigger sits here, let greedy take it (no Error)
      }
    SepArg(name, sep) =>
      // separator-splitting repeat head (DR-034 × DR-043): 先食い-aware, splits the token.
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        [Accept(pos + 1, sep_binds(name, toks[pos], sep))]
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), [])]
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) => [Accept(pos + 1, [mkb(name, VNum(d), Cli)])]
          None => [Held(pe_parse(name, toks[pos], pos), [])]
        }
      } else if pos >= toks.length() {
        [Held(pe_missing(name, pos), [])]
      } else {
        []
      }
    _ => eval(head, toks, pos, defs)
  }
}

///|
/// The value-primitive element name of a repeat head (StrArg/SepArg/NumArg), or "" for a
/// non-primitive head. Used to identify a repeat element's OWN missing_operand for the
/// optional-continuation filter (drop_optional_missing).
fn head_name(head : Node) -> String {
  match head {
    StrArg(n) => n
    SepArg(n, _) => n
    NumArg(n) => n
    _ => ""
  }
}

///|
/// Drop `missing_operand` Held Errors for `name` from an OPTIONAL repeat-continuation ("more")
/// branch set. Rationale: reaching "more" means a rep of `name` already succeeded here, so the
/// closure's minimum for `name` is met — "one more optional rep found no token" is a legitimate
/// STOP, not a structural failure of `name`. The mandatory min-th head is handled elsewhere (its
/// consume_head Held is pushed directly, never through "more"), so it is NOT filtered. Only the
/// exact missing_operand-for-name shape is dropped; a value-parse Error (pe_parse) or an Error for
/// a DIFFERENT element (e.g. a trailing positional's missing_operand) rides through untouched.
fn drop_optional_missing(brs : Array[Branch], name : String) -> Array[Branch] {
  if name == "" {
    return brs
  }
  let out : Array[Branch] = []
  for b in brs {
    match b {
      Held(pe, _) => if pe != pe_missing(name, pe.argv_pos) { out.push(b) }
      _ => out.push(b)
    }
  }
  out
}

///|
/// The head of a repeat template `Seq([head, Opt(Ref(name))])`. The repeat installer
/// always registers templates in this shape, so the head is the Seq's first item.
fn ref_head(defs : Map[String, Node], name : String) -> Node {
  match defs.get(name) {
    Some(Seq(items)) =>
      if items.length() >= 1 {
        items[0]
      } else {
        Exact("<bad-ref>")
      }
    _ => Exact("<bad-ref>")
  }
}

///|
/// Whether the repeat named `name` prefers the SHORTER share (lazy). The lazy flag is
/// stored under a mangled registry key by the repeat installer.
fn ref_is_lazy(defs : Map[String, Node], name : String) -> Bool {
  match defs.get("lazy:" + name) {
    Some(_) => true
    None => false
  }
}

///|
/// Whether any branch is a FULL parse (reaches the target length). Used as the split
/// preference's completion oracle. NB: `target` is the whole-input length, so this is
/// exact for a root-scope repeat; a repeat nested under a non-final scope is approximate
/// (the tests keep repeats at the root or in the last command scope).
fn has_full(brs : Array[Branch], target : Int) -> Bool {
  for b in brs {
    match b {
      Accept(p, _) => if p == target { return true }
      Held(_, _) => ()
    }
  }
  false
}

///|
fn cat_branches(a : Array[Branch], b : Array[Branch]) -> Array[Branch] {
  let r : Array[Branch] = []
  for x in a {
    r.push(x)
  }
  for x in b {
    r.push(x)
  }
  r
}

///|
/// One repetition of a Many's inner item (subject to 先食い), continuing at the
/// SAME pidx so the Many remains available (porous reps, DR-041 §4).
fn scope_consume_rep(
  sc : Scope,
  inner : Node,
  toks : Array[String],
  pos : Int,
  pidx : Int,
  acc : Array[Binding],
  severed : Bool,
  defs : Map[String, Node],
) -> Array[Branch] {
  match inner {
    StrArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        scope_step(
          sc,
          toks,
          pos + 1,
          pidx,
          cat(acc, [mkb(name, VStr(toks[pos]), Cli)]),
          severed,
          defs,
        )
      } else {
        []
      }
    NumArg(name) =>
      if pos < toks.length() && !suppressed(sc, toks, pos, severed, defs) {
        match parse_number(toks[pos]) {
          Some(d) =>
            scope_step(
              sc,
              toks,
              pos + 1,
              pidx,
              cat(acc, [mkb(name, VNum(d), Cli)]),
              severed,
              defs,
            )
          None => [Held(pe_parse(name, toks[pos], pos), acc)]
        }
      } else {
        []
      }
    _ => {
      let out : Array[Branch] = []
      for b in eval(inner, toks, pos, defs) {
        match b {
          Accept(p2, bs) =>
            if p2 > pos {
              for
                r in scope_step(sc, toks, p2, pidx, cat(acc, bs), severed, defs) {
                out.push(r)
              }
            }
          Held(pe, bs) => out.push(Held(pe, bs))
        }
      }
      out
    }
  }
}

///|
/// Drop the `link` nesting hint (set false) — it is resolved before path counting.
fn strip_link(bs : Array[Binding]) -> Array[Binding] {
  let out : Array[Binding] = []
  for b in bs {
    out.push({
      key: b.key,
      op: b.op,
      value: b.value,
      source: b.source,
      scope: b.scope,
      link: 0,
    })
  }
  out
}

// ── constraint evaluation (delayed predicates, DR-055 / DR-047) ──────────────

///|
fn scope_of(root : Node) -> Scope? {
  match root {
    ScopeNode(sc) => Some(sc)
    _ => None
  }
}

///|
/// Whether an element is committed on a path (DR-045): the LAST effect on the cell is not unset
/// (last-wins, DR-015). So `--foo ... --no-foo` (unset) leaves foo un-committed — it does not count
/// toward conflicts / exclusive (DR-055 §2 / DR-047).
fn is_committed(bindings : Array[Binding], name : String) -> Bool {
  let mut committed = false
  for b in bindings {
    if b.key == name {
      match b.op {
        Unset => committed = false
        _ => committed = true
      }
    }
  }
  committed
}

///|
/// The committed value of an element (last-wins), or None.
fn elem_value(bindings : Array[Binding], name : String) -> String? {
  let mut v : String? = None
  for b in bindings {
    if b.key == name {
      match b.op {
        Unset => ()
        _ => v = Some(value_str(b.value))
      }
    }
  }
  v
}

///|
fn has_default(entities : Array[Entity], name : String) -> Bool {
  for e in entities {
    if e.name == name {
      return e.default_value.is_some()
    }
  }
  false
}

///|
/// Value presence (DR-047 §5): committed on the path OR a default seat exists (default 込み).
fn value_present(
  name : String,
  bindings : Array[Binding],
  entities : Array[Entity],
) -> Bool {
  is_committed(bindings, name) || has_default(entities, name)
}

///|
fn constraint_err(element : String, message : String, pos : Int) -> ParseError {
  { element, argv_pos: pos, kind: KConstraint, message }
}

///|
/// Evaluate the scope's delayed predicates on a complete path's FINAL state (DR-055 / DR-047).
/// Returns the violations (each a kind:constraint ParseError). An empty result = the path satisfies
/// all constraints (a valid 完全解決経路); a non-empty result means the path is NOT complete.
fn eval_constraints(
  constraints : Array[Constraint],
  entities : Array[Entity],
  bindings : Array[Binding],
  pos : Int,
) -> Array[ParseError] {
  let out : Array[ParseError] = []
  for c in constraints {
    match c {
      // requires (正の依存): committed → every target must have a value (default 込み).
      CRequires(elem, targets) =>
        if is_committed(bindings, elem) {
          for t in targets {
            if not(value_present(t, bindings, entities)) {
              out.push(constraint_err(elem, "'\{elem}' requires '\{t}'", pos))
            }
          }
        }
      // value-dependent requires (DR-055 §1): active only when the element's committed value == v.
      CRequiresIf(elem, v, targets) => {
        let active = is_committed(bindings, elem) &&
          (match elem_value(bindings, elem) {
            Some(x) => x == v
            None => false
          })
        if active {
          for t in targets {
            if not(value_present(t, bindings, entities)) {
              out.push(
                constraint_err(elem, "'\{elem}'=\{v} requires '\{t}'", pos),
              )
            }
          }
        }
      }
      // conflicts_with (対称): committed elem + committed target → conflict.
      CConflicts(elem, targets) =>
        if is_committed(bindings, elem) {
          for t in targets {
            if is_committed(bindings, t) {
              out.push(
                constraint_err(elem, "'\{elem}' conflicts with '\{t}'", pos),
              )
            }
          }
        }
      // exclusive_group: > 1 committed member → conflict.
      CExclusive(group, members) => {
        let mut count = 0
        for m in members {
          if is_committed(bindings, m) {
            count = count + 1
          }
        }
        if count > 1 {
          out.push(
            constraint_err(
              group,
              "exclusive group '\{group}' allows at most one",
              pos,
            ),
          )
        }
      }
    }
  }
  out
}

// ── top level (DR-038 path counting) ────────────────────────────────────────

///|
/// Parse `toks` against `root`, counting DISTINCT complete paths.
///
/// Path identity is the **observable effect sequence** on entities (DR-038): which
/// entity (value cell, scope-qualified), which value, which source, in which order.
/// It is ENTRY-INDEPENDENT — a `Binding` carries no trace of which satellite / matcher
/// produced it, so two routes that write the same cell (a global copy reaching the same
/// entity, or an interleaving that lands the same effect two ways) are the SAME path and
/// merge. Genuinely different readings (an or-branch, a different value) produce different
/// effect sequences and stay distinct → ambiguous. Comparing the `Array[Binding]` by
/// structural equality IS this effect-sequence identity (entity=key+scope, value, source, order).
///
/// `defs` supplies the template registry for `Ref` resolution (empty by default;
/// only repeat/ref definitions need it).
///
/// `faildef` chooses WHICH candidate paths count a failure-action as "selected" (DR-048 §5, the
/// undetermined point tracked by issue `2026-07-03-failure-action-selected-scope`). See `FailDef`.
pub fn parse(
  root : Node,
  toks : Array[String],
  defs? : Map[String, Node] = Map::new(),
  faildef? : FailDef = WithHeld,
) -> Outcome {
  let branches = eval(root, toks, 0, defs)
  let full : Array[Array[Binding]] = [] // distinct complete paths → interpretations
  let errors : Array[ParseError] = [] // ALL held Errors, deduped (DR-053 §2 全保持)
  // the scope's delayed predicates + entities, for constraint evaluation (DR-055 / DR-047).
  let (constraints, sc_entities) = match scope_of(root) {
    Some(s) => (s.constraints, s.entities)
    None => ([], [])
  }
  // the deepest argv position any branch reached (for the DeepestOnly candidate set).
  let mut max_reach = -1
  for b in branches {
    match b {
      Accept(p, _) => if p > max_reach { max_reach = p }
      Held(pe, _) => if pe.argv_pos > max_reach { max_reach = pe.argv_pos }
    }
  }
  // failure-action markers gathered from the candidate paths selected by `faildef`.
  let actions : Array[(String, Int)] = []
  for b in branches {
    match b {
      Accept(p, bs) => {
        if p == toks.length() {
          // strip the `link` hint before comparing: nesting is resolved by now, so link is
          // vestigial and NOT part of the effect identity (DR-038). Two routes onto the same
          // root entity — one via a link satellite, one direct — merge to one path.
          let eff = strip_link(bs)
          // DR-055 / DR-047: a delayed-predicate violation makes this NOT a complete解決経路 — the
          // path is dropped from `full` (so a constraint can 経路選択に参加, DR-047 §6) and its
          // violations join the errors (kind:constraint). A satisfying path is a real interpretation.
          let viol = eval_constraints(
            constraints,
            sc_entities,
            eff,
            toks.length(),
          )
          if viol.length() > 0 {
            for v in viol {
              let mut vdup = false
              for e in errors {
                if e == v {
                  vdup = true
                  break
                }
              }
              if !vdup {
                errors.push(v)
              }
            }
          } else {
            let mut dup = false
            for existing in full {
              if existing == eff {
                dup = true
                break
              }
            }
            if !dup {
              full.push(eff)
            }
          }
        }
        let counts = match faildef {
          DeepestOnly => p == max_reach
          _ => true
        }
        if counts {
          collect_actions(bs, actions)
        }
      }
      Held(pe, bs) => {
        // DR-053 §2: keep ALL held Errors (別候補経路の別 Error), deduped by structural equality.
        let mut dup = false
        for e in errors {
          if e == pe {
            dup = true
            break
          }
        }
        if !dup {
          errors.push(pe)
        }
        // a Held (Error) partial path counts as a failure-action candidate only under WithHeld
        // (F-039 partial state) or DeepestOnly-when-maximal; AcceptsOnly ignores dead ends.
        let counts = match faildef {
          AcceptsOnly => false
          WithHeld => true
          DeepestOnly => pe.argv_pos == max_reach
        }
        if counts {
          collect_actions(bs, actions)
        }
      }
    }
  }
  let help = find_help_entry(root) // 誘導行の素材 (DR-053 §4)
  // Residual-token failure (DR-065 §3 / CONFORMANCE §2): a 0-complete-path failure with NO held
  // or constraint Error means every path reached a scope-end Accept but left tokens no consumer
  // could take (p < argv.length). The spine walk drops such a path silently (it is not a complete
  // reading, DR-038), so no Error is synthesized there.合成 it here at the residual head — the
  // deepest Accept position reached (max_reach; with errors empty there are no Held branches, so
  // max_reach is a residual Accept). element omitted = a scope-level stumble (not a single element's
  // fault); kind:parse. Token-exhaustion (missing_operand) is already carried as a held Error above,
  // so this fires ONLY for the residual shape.
  let errors = if errors.length() == 0 && max_reach >= 0 {
    [
      {
        element: "",
        argv_pos: max_reach,
        kind: KParse,
        message: "unexpected token",
      },
    ]
  } else {
    errors
  }
  match full.length() {
    0 =>
      // DR-053 §2: a failure. errors are ALL retained; a fired failure-action (DR-048) coexists
      // (fired_action set, errors still present). tried_triggers is the Did you mean material.
      Failure({
        errors,
        fired_action: if actions.length() > 0 {
          Some(argmin_action(actions))
        } else {
          None
        },
        help_entry: help,
        tried_triggers: tried_triggers_of(root),
      })
    1 => Success(full[0])
    _ =>
      // DR-053 §3: ambiguous — every distinct interpretation, plus the same help material.
      Ambiguous({ interpretations: full, help_entry: help })
  }
}

///|
/// The help entry's spelling (DR-053 §4 help_entry material): the exact trigger of the greedy
/// satellite that carries a failure-action FailMark (help). None if the definition has no help entry.
fn find_help_entry(root : Node) -> String? {
  match root {
    ScopeNode(sc) => {
      for g in sc.greedy {
        match g {
          Seq(items) => {
            let mut trig : String? = None
            let mut has_fail = false
            for it in items {
              match it {
                Exact(s) =>
                  match trig {
                    None => trig = Some(s)
                    _ => ()
                  }
                FailMark(_) => has_fail = true
                _ => ()
              }
            }
            if has_fail {
              match trig {
                Some(t) => return Some(t)
                None => ()
              }
            }
          }
          _ => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
/// The exact trigger literals available in the scope (DR-053 §4 tried_triggers material). PoC
/// approximation: the whole greedy face's exact triggers, not filtered to the failure position
/// (近接マッチ計算は DX 層の関心 — 素材のみ、AtomicAST にフックは持たない, F-016).
fn tried_triggers_of(root : Node) -> Array[String] {
  let out : Array[String] = []
  match root {
    ScopeNode(sc) =>
      for g in sc.greedy {
        match g {
          Seq(items) =>
            if items.length() >= 1 {
              match items[0] {
                Exact(s) => out.push(s)
                _ => ()
              }
            }
          DdSat(s) => out.push(s)
          CmdSat(name, _) => out.push(name)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// The candidate-path set that counts a failure-action as "selected" (DR-048 §5, undetermined).
/// The three realize the plausible readings of "候補経路のいずれかで selected":
pub(all) enum FailDef {
  AcceptsOnly // candidate = a path that reached a scope-end Accept (dead ends ignored)
  WithHeld // + a path that reached an Error-held point (its partial state, F-039)
  DeepestOnly // only the maximal-argv-consumption candidate path(s)
} derive(Eq, Show)

///|
/// Push every failure-action marker in `bs` as (action name, argv position) into `out`.
fn collect_actions(bs : Array[Binding], out : Array[(String, Int)]) -> Unit {
  for b in bs {
    match action_of(b) {
      Some(name) => {
        let pos = match b.value {
          VNum(d) => d.to_int()
          _ => 0
        }
        out.push((name, pos))
      }
      None => ()
    }
  }
}

///|
/// The action with the minimal argv position (先勝ち, DR-048 §4). Ties keep first-seen.
fn argmin_action(actions : Array[(String, Int)]) -> String {
  let mut best = actions[0]
  for a in actions {
    if a.1 < best.1 {
      best = a
    }
  }
  best.0
}
