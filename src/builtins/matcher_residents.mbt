// matcher_residents.mbt — builtin native matcher residents (DR-041 §3-4).
//
// A matcher turns ONE token into a set of readings (branches). Each reading is a
// full interpretation of that token: it never re-reads the fragments it produced
// (DR-041 §4 "読みが生成した断片は再度読解しない"). The path-search treats every
// reading as an equal branch (DR-041 §3, no matcher-internal priority).
//
// MDR-002 §3: matcher depends on {node, value} — it returns `@engine.Branch` (defined in node.mbt) and
// uses the @engine.Binding/@engine.ParseError helpers (@engine.mkb / pe_parse / @engine.depr_marker / @engine.cat, defined in value.mbt).
// The matcher only CONSTRUCTS @engine.Accept/@engine.Held; the evaluator produces/consumes the `@engine.Pending` variant.

// String indexing yields UTF-16 code units, so cluster/value work is done on
// Array[Char] (iterating a String yields Char). Test tokens are ASCII.

///|
fn char_prefix(cs : Array[Char], p : Array[Char]) -> Bool {
  if p.length() > cs.length() {
    return false
  }
  let mut i = 0
  while i < p.length() {
    if cs[i] != p[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
fn index_of_char(cs : Array[Char], c : Char) -> Int {
  let mut i = 0
  while i < cs.length() {
    if cs[i] == c {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// Read-only construction data for one `--key=value` matcher entry.
pub struct EqEntry {
  priv key : String
  priv name : String
  priv kind : &@engine.TypeExt
  priv piece_filters : Array[@engine.FilterSpelling]
  priv separator : String?
  priv merge : Bool
  priv depr : Bool
}

///|
pub fn eq_entry(
  key : String,
  name : String,
  kind : &@engine.TypeExt,
  piece_filters : Array[@engine.FilterSpelling],
  separator : String?,
  merge? : Bool = false,
  depr? : Bool = false,
) -> EqEntry {
  { key, name, kind, piece_filters, separator, merge, depr }
}

///|
/// Read-only construction data for one short-cluster matcher entry.
pub struct ShortEntry {
  priv ch : Char
  priv name : String
  priv kind : &@engine.TypeExt
  priv depr : Bool
  priv piece_filters : Array[@engine.FilterSpelling]
  priv separator : String?
  priv merge : Bool
  priv short_attached_value : @engine.AttachMode
  priv is_alias : Bool
}

///|
pub fn short_entry(
  ch : Char,
  name : String,
  kind : &@engine.TypeExt,
  piece_filters : Array[@engine.FilterSpelling],
  separator : String?,
  depr? : Bool = false,
  merge? : Bool = false,
  short_attached_value? : @engine.AttachMode = @engine.AtAllow,
  is_alias? : Bool = false,
) -> ShortEntry {
  {
    ch,
    name,
    kind,
    depr,
    piece_filters,
    separator,
    merge,
    short_attached_value,
    is_alias,
  }
}

///|
fn eq_candidates(
  prefix : String,
  entries : Array[EqEntry],
) -> Array[@engine.Cand] {
  let out : Array[@engine.Cand] = []
  for entry in entries {
    if entry.kind.has_value_slot() {
      out.push(
        @engine.cand_trigger(
          prefix + entry.key,
          entry.name,
          entry.kind.name(),
          @engine.Cont,
          false,
          false,
          false,
        ),
      )
    }
  }
  out
}

///|
fn short_candidates(
  prefix : String,
  entries : Array[ShortEntry],
) -> Array[@engine.Cand] {
  let out : Array[@engine.Cand] = []
  for entry in entries {
    let spelling = StringBuilder::new()
    spelling.write_string(prefix)
    spelling.write_char(entry.ch)
    out.push(
      @engine.cand_trigger(
        spelling.to_string(),
        entry.name,
        entry.kind.name(),
        @engine.WordEnd,
        entry.is_alias,
        false,
        entry.depr,
      ),
    )
  }
  out
}

///|
fn type_json(kind : &@engine.TypeExt) -> Json {
  [kind.name().to_json(), kind.encode()].to_json()
}

///|
fn attach_mode_json(mode : @engine.AttachMode) -> Json {
  match mode {
    @engine.AtAllow => "allow".to_json()
    @engine.AtRequire => "require".to_json()
    @engine.AtDeny => "deny".to_json()
    @engine.AtLastOnly => "last_only".to_json()
  }
}

///|
fn eq_entry_json(entry : EqEntry) -> Json {
  [
    entry.key.to_json(),
    entry.name.to_json(),
    type_json(entry.kind),
    filter_spellings_json(entry.piece_filters),
    entry.separator.to_json(),
    entry.merge.to_json(),
    entry.depr.to_json(),
  ].to_json()
}

///|
fn short_entry_json(entry : ShortEntry) -> Json {
  [
    "\{entry.ch}".to_json(),
    entry.name.to_json(),
    type_json(entry.kind),
    entry.depr.to_json(),
    filter_spellings_json(entry.piece_filters),
    entry.separator.to_json(),
    entry.merge.to_json(),
    attach_mode_json(entry.short_attached_value),
    entry.is_alias.to_json(),
  ].to_json()
}

///|
priv struct EqSplitExt {
  prefix : String
  entries : Array[EqEntry]
}

///|
impl @engine.MatcherExt for EqSplitExt with fn kind(_self) {
  "eq_split"
}

///|
impl @engine.MatcherExt for EqSplitExt with fn encode(self) {
  let entries : Array[Json] = []
  for entry in self.entries {
    entries.push(eq_entry_json(entry))
  }
  [self.prefix.to_json(), entries.to_json()].to_json()
}

///|
impl @engine.MatcherExt for EqSplitExt with fn candidates(self) {
  eq_candidates(self.prefix, self.entries)
}

///|
impl @engine.MatcherExt for EqSplitExt with fn interpret(
  self,
  ctx,
  pos,
  acc,
  next,
) {
  let readings = run_eq_split(self.prefix, self.entries, ctx, pos)
  @engine.continue_matcher(readings, ctx, acc, next)
}

///|
pub fn eq_split(
  prefix : String,
  entries : Array[EqEntry],
) -> &@engine.MatcherExt {
  EqSplitExt::{ prefix, entries } as &@engine.MatcherExt
}

///|
priv struct ShortCombineExt {
  prefix : String
  entries : Array[ShortEntry]
  combine : Bool
}

///|
impl @engine.MatcherExt for ShortCombineExt with fn kind(_self) {
  "short_combine"
}

///|
impl @engine.MatcherExt for ShortCombineExt with fn encode(self) {
  let entries : Array[Json] = []
  for entry in self.entries {
    entries.push(short_entry_json(entry))
  }
  [self.prefix.to_json(), entries.to_json(), self.combine.to_json()].to_json()
}

///|
impl @engine.MatcherExt for ShortCombineExt with fn candidates(self) {
  short_candidates(self.prefix, self.entries)
}

///|
impl @engine.MatcherExt for ShortCombineExt with fn interpret(
  self,
  ctx,
  pos,
  acc,
  next,
) {
  let readings = run_short(self.prefix, self.entries, self.combine, ctx, pos)
  @engine.continue_matcher(readings, ctx, acc, next)
}

///|
pub fn short_combine(
  prefix : String,
  entries : Array[ShortEntry],
  combine : Bool,
) -> &@engine.MatcherExt {
  ShortCombineExt::{ prefix, entries, combine } as &@engine.MatcherExt
}

///|
/// `--key=value` (DR-041 §「equal separator」). Fires only when the token has `=`.
/// Undefined key => no reading (素通し to positional). Space form is the satellite's job.
fn run_eq_split(
  prefix : String,
  entries : Array[EqEntry],
  ctx : @engine.Ctx,
  pos : Int,
) -> Array[@engine.Branch] {
  guard ctx.token_at(pos) is Some(token) else { return [] }
  let tok = @engine.to_chars(token)
  let pfx = @engine.to_chars(prefix)
  if !char_prefix(tok, pfx) {
    return []
  }
  let body = tok // slice via indices below
  let eq = index_of_char(body, '=')
  if eq < 0 || eq <= pfx.length() {
    return [] // no '=' (or nothing before it) => this matcher does not fire
  }
  let key = @engine.chars_to_str(body, pfx.length(), eq)
  let valstr = @engine.chars_to_str(body, eq + 1, body.length())
  for e in entries {
    if e.key == key {
      // A matcher asks the resident whether a value slot exists; it does not enumerate
      // flag/count/none categories itself.
      if !e.kind.has_value_slot() {
        return []
      }
      // codex レビュー Major 1 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見) /
      // DR-058 §2: eq-split の deprecated warning marker — `walk_short` の `dm` と同じ carrier
      // パターン (builtins/matcher_residents.mbt 上の `dm` 定義コメント参照)。成功パス (@engine.Accept) だけに合成する — 値が
      // 確定して初めて「受理された deprecated 入口」なので、@engine.Held (parse/filter 失敗) には積まない。
      let dm : Array[@engine.Binding] = if e.depr {
        [@engine.depr_marker(e.name)]
      } else {
        []
      }
      // DR-034 separator (issue 2026-07-09-separator-non-string-type-parse-gap 段1): `--key=a,b`
      // goes through the SAME pieceProcessor as the space form (`@engine.sep_binds`) — split FIRST, then
      // piece_filters/parse run per PIECE, not once over the whole `valstr` (same ordering concern
      // `@engine.sep_binds`'s own doc comment explains).
      // codex Medium 追従 (issue merge-no-separator-marker-gap): gate is `separator is Some(_) ||
      // e.merge`, not `separator` alone — a merge-declared entry with NO separator still needs
      // `@engine.sep_binds` (DR-034 §6.3 の縮退: `None` → 1 piece = `valstr` 全体) so `classify_merge_piece`
      // sees `--key=-a` as a remove marker instead of falling through to the plain literal-string
      // arm below.
      if e.separator is Some(_) || e.merge {
        return match
          @engine.sep_binds(
            e.name,
            valstr,
            e.separator,
            e.kind,
            e.piece_filters,
            pos,
            e.merge,
          ) {
          Ok(bs) => [@engine.Accept(pos + 1, @engine.cat(bs, dm))]
          Err(pe) => [@engine.Held(pe, [])]
        }
      }
      // DR-034/DR-062 piece_filters: run BEFORE the kind-specific parse, same timing eval.mbt's
      // value-primitive arms use (this is the eq-split entry's own copy of the element's chain,
      // EqEntry carries it the same way it carries int_round/allow_base_prefix).
      let filtered = match
        @engine.apply_piece_filters(e.piece_filters, valstr) {
        Ok(s) => s
        Err((reason, msg)) =>
          return [@engine.Held(@engine.pe_filter(e.name, pos, reason, msg), [])]
      }
      match e.kind.parse_token(filtered) {
        Ok(value) =>
          return [
            @engine.Accept(
              pos + 1,
              @engine.cat(
                [@engine.mkb(e.name, value, @engine.Cli, at_pos=Some(pos))],
                dm,
              ),
            ),
          ]
        Err(fail) =>
          return [
            @engine.Held(
              @engine.parse_fail_error(e.name, filtered, pos, fail),
              [],
            ),
          ]
      }
    }
  }
  [] // undefined key => 素通し
}

///|
/// `-abc` cluster + value attachment (DR-041 §「short combine」). Enumerates ALL
/// readings; ambiguous defs (the `-cv` problem) yield multiple readings. `combine`
/// (DESIGN §7.2 scope config, node.mbt's `ShortCombine` doc comment) gates whether
/// `walk_short` may let a SECOND entry occupy the same token.
fn run_short(
  prefix : String,
  entries : Array[ShortEntry],
  combine : Bool,
  ctx : @engine.Ctx,
  pos : Int,
) -> Array[@engine.Branch] {
  guard ctx.token_at(pos) is Some(token) else { return [] }
  let tok = @engine.to_chars(token)
  let pfx = @engine.to_chars(prefix)
  if !char_prefix(tok, pfx) {
    return []
  }
  // body = cluster chars after the prefix
  let body : Array[Char] = []
  let mut k = pfx.length()
  while k < tok.length() {
    body.push(tok[k])
    k = k + 1
  }
  if body.length() == 0 {
    return [] // bare prefix, e.g. "-"
  }
  walk_short(entries, combine, body, 0, [], ctx, pos)
}

///|
fn short_lookup(entries : Array[ShortEntry], c : Char) -> ShortEntry? {
  for e in entries {
    if e.ch == c {
      return Some(e)
    }
  }
  None
}

///|
/// `Ok` = the value char attached successfully (an `Array[@engine.Binding]` — usually length 1, but a
/// `separator` entry can split one attach into several pieces, same as the long-option space form's
/// `SepArg`/`@engine.sep_binds`, issue 2026-07-09-separator-non-string-type-parse-gap 段1). `Err` carries a
/// full `@engine.ParseError` (`kind: KFilter` for a piece_filters reject, `kind: KParse` for a type-parse
/// failure — both delegate straight to `@engine.sep_binds` when `e.separator` is `Some` OR `e.merge` is
/// `true`, codex Medium 追従: a merge entry needs the piece pipeline even with no separator).
/// `walk_short`'s
/// mid-token/full-tail split still governs whether an `Err` surfaces as a `@engine.Held` or is silently
/// dropped (see its call sites) — unlike the old `@engine.Binding?`-based 2-way split, this no longer needs
/// a kind guard at the call site: a `string_type()` entry structurally never produces a type-parse `Err`
/// (its parse is the identity), so "every `Err` at full-tail becomes `@engine.Held`" is equivalent to the
/// old kind-gated condition, just simpler.
/// `pos` (issue 2026-07-09-accum-entity-filters-wiring): the args token this value char's raw
/// string was read from — the CALLING token for an in-cluster attach, the NEXT token for a
/// space-form attach (`walk_short`'s two call sites pass `pos`/`pos + 1` respectively, mirroring
/// the `pe_parse(..., pos)` / `pe_parse(..., pos + 1)` split those same call sites already made
/// pre-existing for ordinary parse failures).
fn short_val(
  e : ShortEntry,
  s : String,
  pos : Int,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  // codex Medium 追従 (issue merge-no-separator-marker-gap): `run_eq_split` と同じ gate 拡張
  // (`separator is Some(_) || e.merge`) — `-f-a` (in-cluster attach) / `-f -a` (space-form) いずれ
  // も merge 宣言なら separator 未宣言でも `@engine.sep_binds` 経由でマーカー認識させる。
  if e.separator is Some(_) || e.merge {
    // `ShortEntry` carries no `bool_config` (bool_type() never reaches this attach path — node.mbt's
    // `ShortEntry.piece_filters` doc comment: "Ignored for flag_type()/bool_type()/count_type(), no in-cluster/
    // space-form VALUE attachment for those"), so `@engine.sep_binds`'s bool arm is structurally dead here;
    // pass the canonical default purely to satisfy the shared signature.
    @engine.sep_binds(
      e.name,
      s,
      e.separator,
      e.kind,
      e.piece_filters,
      pos,
      e.merge,
    )
  } else {
    let filtered = match @engine.apply_piece_filters(e.piece_filters, s) {
      Ok(v) => v
      Err((reason, msg)) =>
        return Err(@engine.pe_filter(e.name, pos, reason, msg))
    }
    match e.kind.parse_token(filtered) {
      Ok(value) =>
        Ok([@engine.mkb(e.name, value, @engine.Cli, at_pos=Some(pos))])
      Err(fail) => Err(@engine.parse_fail_error(e.name, filtered, pos, fail))
    }
  }
}

///|
/// Walk the in-token cluster body from index `i`, emitting readings.
/// - a flag char advances by one;
/// - a value char attaches an in-token value of every valid length, then keeps
///   walking the remainder (so `-n1.0` yields n="1.0", and with an `-f` flag also n="1"+`-f`);
/// - a value char at the cluster tail may instead take the NEXT token as its
///   value (space form, consuming 2 tokens).
/// An undefined char kills the reading (DR-041 §5: no prefix guard — the whole
/// token simply produces no reading and falls through to positional).
///
/// `combine` (issue scope-config-object-gap 解釈A, team-lead 裁定 2026-07-11 — DR-014「-abc の
/// 結合許可」は複数 short オプションを 1 トークンへ束ねる行為のみを指し、値付着は別パラメータの
/// 管轄, DR-041 line 77): when `false`, a SECOND entry may never occupy the same token as the
/// first. This walk only ever advances `i` past 0 to reach a genuine second entry in 2 places —
/// the flag/bool/count/none recursive continuation (`i + 1`) and the in-token value-attach
/// continuation (`j`) — so gating exactly those 2 continuations (only recurse when the
/// continuation is TERMINAL, i.e. nothing is left to combine with) is sufficient: a lone flag fire
/// (`-p`, `i == 0`, `body.length() == 1`) and a value-attach consuming the ENTIRE remaining tail
/// (`-p80`, `j == body.length()`, nothing left over) both still terminate immediately and are
/// therefore unaffected — only a reading that would need a THIRD+ char to combine gets pruned. The
/// next-token space-form value (`-p 80`) and the completion `@engine.Pending` branch consume no further
/// same-token chars at all, so neither needs a `combine` check.
fn walk_short(
  entries : Array[ShortEntry],
  combine : Bool,
  body : Array[Char],
  i : Int,
  acc : Array[@engine.Binding],
  ctx : @engine.Ctx,
  pos : Int,
) -> Array[@engine.Branch] {
  if i == body.length() {
    return [@engine.Accept(pos + 1, acc)] // whole cluster consumed within this one token
  }
  let c = body[i]
  match short_lookup(entries, c) {
    None => []
    Some(e) => {
      // DR-058: a deprecated cluster entry rides a `@depr:<name>` warning marker alongside its
      // value binding (the value is unchanged; only a warning is added). `dm` is [] for a normal entry.
      let dm : Array[@engine.Binding] = if e.depr {
        [@engine.depr_marker(e.name)]
      } else {
        []
      }
      if !e.kind.has_value_slot() {
        // Presence-only residents share the same reading shape. Count owns a distinct
        // effect payload; the matcher no longer enumerates type categories to find the shape.
        let presence = if e.kind.name() == "count" {
          @engine.mk_eff(e.name, @engine.Update("increment", []), @engine.Cli)
        } else {
          @engine.mkb(e.name, @engine.VBool(true), @engine.Cli)
        }
        if combine || i + 1 == body.length() {
          walk_short(
            entries,
            combine,
            body,
            i + 1,
            @engine.cat(acc, @engine.cat([presence], dm)),
            ctx,
            pos,
          )
        } else {
          []
        }
      } else {
        let out : Array[@engine.Branch] = []
        let vstart = i + 1
        // in-token value of every non-empty length; continue walking the rest.
        let mut j = vstart + 1
        while j <= body.length() {
          // `combine:false` gate: a PARTIAL-length value-attach (`j < body.length()`) would leave
          // chars for a 2nd entry to combine with — skip it entirely (no reading, no @engine.Held error)
          // when combine is off. The FULL-TAIL length (`j == body.length()`, this entry alone
          // consumes everything left) is a single entry, never disallowed by `combine:false`.
          // DESIGN §7.2 / DR-096 §2/§3.1: `short_attached_value:"deny"` withholds EVERY in-cluster
          // attach reading (mid-token AND full-tail, cluster-tail included) — the mechanism itself
          // is gated, not just a lone-entry case. `"require"` does NOT gate this loop (attach stays
          // allowed, incl. cluster-tail attach, DR-096 §3.1). `"last_only"` (kawaz 裁定 2026-07-12)
          // withholds every MID-token split (`j < body.length()`) — only the FULL-TAIL "丸取り"
          // reading remains, so this entry never contributes to a split-point ambiguity (GNU
          // getopt 慣習: 値オプションに達したら以降の文字列全部がその値、DR-096 §2)。
          if e.short_attached_value != @engine.AtDeny &&
            (e.short_attached_value != @engine.AtLastOnly || j == body.length()) &&
            (combine || j == body.length()) {
            let vstr = @engine.chars_to_str(body, vstart, j)
            match short_val(e, vstr, pos) {
              Ok(bs) =>
                for
                  r in walk_short(
                    entries,
                    combine,
                    body,
                    j,
                    @engine.cat(acc, @engine.cat(bs, dm)),
                    ctx,
                    pos,
                  ) {
                  out.push(r)
                }
              Err(pe) =>
                // A mid-token split's failure (piece_filters reject OR type-parse failure) is a
                // silent non-reading (its remainder would need OTHER defined chars to progress,
                // DR-041 §3); only the FULL-TAIL attach — the「値 char が残余全体を値として取る」
                //唯一形の読み — surfaces as a held Error (DR-041 §5 値不正 = Error、DR-074 の
                // suffix 拒否がここに落ちる)。fixture matcher-readings/cluster-split-no-flag /
                // piece-filters/reject.json が輪郭を固定する。string_type() が構造的に型 parse エラーを
                // 起こさない (short_val の doc comment) ので、kind によるガードは不要。
                if j == body.length() {
                  out.push(@engine.Held(pe, acc))
                }
            }
          }
          j = j + 1
        }
        // next-token value (space form) only when this value char is the tail. Not gated by
        // `combine` (doc comment above): the value comes from the NEXT token entirely, no 2nd
        // entry shares THIS token.
        // DESIGN §7.2 / DR-096 §2: `short_attached_value:"require"` withholds this space-form
        // reading entirely (both the eager next-token @engine.Accept and the completion @engine.Pending branch) —
        // this is what makes a `"require"` entry's bare tail token (e.g. `-q` with 0 leftover
        // chars) have NO complete path at all (attach needs >=1 char, DR-096 §2「付着形は定義上
        // 1 文字以上の残り文字列を要求する」), falling through to positional per DR-041 §5.
        if e.short_attached_value != @engine.AtRequire &&
          vstart == body.length() &&
          ctx.token_at(pos + 1) is Some(next_token) {
          match short_val(e, next_token, pos + 1) {
            Ok(bs) =>
              out.push(
                @engine.Accept(pos + 2, @engine.cat(acc, @engine.cat(bs, dm))),
              )
            Err(pe) => out.push(@engine.Held(pe, []))
          }
        } else if e.short_attached_value != @engine.AtRequire &&
          vstart == body.length() &&
          ctx.is_complete_mode() {
          // complete: the cluster ends in a value char and the args ends
          // here — the space-form value is exactly what could come next
          // (DR-060 §1). The flags already read stay as partial state.
          out.push(
            @engine.Pending(
              [@engine.pend_value(e.kind.name(), e.name)],
              @engine.cat(acc, dm),
            ),
          )
        }
        out
      }
    }
  }
}
