// matcher.mbt — the native matcher interpreter (DR-041 §3-4).
//
// A matcher turns ONE token into a set of readings (branches). Each reading is a
// full interpretation of that token: it never re-reads the fragments it produced
// (DR-041 §4 "読みが生成した断片は再度読解しない"). The path-search treats every
// reading as an equal branch (DR-041 §3, no matcher-internal priority).
//
// MDR-002 §3: matcher depends on {node, value} — it returns `Branch` (defined in node.mbt) and
// uses the Binding/ParseError helpers (mkb / pe_parse / depr_marker / cat, defined in value.mbt).
// The matcher only CONSTRUCTS Accept/Held; the evaluator produces/consumes the `Pending` variant.

// String indexing yields UTF-16 code units, so cluster/value work is done on
// Array[Char] (iterating a String yields Char). Test tokens are ASCII.

///|
fn to_chars(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

///|
fn chars_to_str(cs : Array[Char], a : Int, b : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = a
  while i < b {
    buf.write_char(cs[i])
    i = i + 1
  }
  buf.to_string()
}

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
/// Interpret a matcher against the token at `pos`. Takes the whole Ctx so the
/// cluster walk can emit a complete-mode Pending for a tail value char whose
/// next-token value is past the argv end (DR-060 §1 readable-next set).
fn run_matcher(m : Matcher, ctx : Ctx, pos : Int) -> Array[Branch] {
  if pos >= ctx.toks.length() {
    return []
  }
  match m {
    EqSplit(prefix~, entries~) => run_eq_split(prefix, entries, ctx.toks, pos)
    ShortCombine(prefix~, entries~, combine~) =>
      run_short(prefix, entries, combine, ctx, pos)
  }
}

///|
/// The matcher's own trigger spellings as complete candidates (DR-060 §3
/// 「eq-split / cluster の元綴り」). An eq-split key must be followed by
/// `=value` in the same word (term = Cont, ty = the value type); a TFlag
/// entry never fires through the eq face, so it contributes no spelling
/// here. A cluster char may end the word (flag) or take a space-form value
/// (term = WordEnd either way); a deprecated alias char keeps its meta.
fn matcher_cands(m : Matcher) -> Array[Cand] {
  let out : Array[Cand] = []
  match m {
    EqSplit(prefix~, entries~) =>
      for e in entries {
        // DR-077 §3: count (like flag) never fires through the eq face — see run_eq_split's
        // `TCount => return []` — so it contributes no completion candidate here either.
        if e.kind != TFlag && e.kind != TCount {
          out.push(cand_trigger(prefix + e.key, e.name, e.kind, Cont, false))
        }
      }
    ShortCombine(prefix~, entries~, ..) =>
      for e in entries {
        let buf = StringBuilder::new()
        buf.write_string(prefix)
        buf.write_char(e.ch)
        out.push(cand_trigger(buf.to_string(), e.name, e.kind, WordEnd, e.depr))
      }
  }
  out
}

///|
/// `--key=value` (DR-041 §「equal separator」). Fires only when the token has `=`.
/// Undefined key => no reading (素通し to positional). Space form is the satellite's job.
fn run_eq_split(
  prefix : String,
  entries : Array[LongEntry],
  toks : Array[String],
  pos : Int,
) -> Array[Branch] {
  let tok = to_chars(toks[pos])
  let pfx = to_chars(prefix)
  if !char_prefix(tok, pfx) {
    return []
  }
  let body = tok // slice via indices below
  let eq = index_of_char(body, '=')
  if eq < 0 || eq <= pfx.length() {
    return [] // no '=' (or nothing before it) => this matcher does not fire
  }
  let key = chars_to_str(body, pfx.length(), eq)
  let valstr = chars_to_str(body, eq + 1, body.length())
  for e in entries {
    if e.key == key {
      // TFlag/TCount take no eq-split value at all (no raw string to gate), so piece_filters is
      // skipped for them entirely — checked BEFORE running the chain to avoid filtering a value
      // slot that structurally doesn't exist for this kind.
      if e.kind == TFlag {
        return [] // presence-only trigger (DR-074 no eq-split): flags take no =value
      }
      if e.kind == TCount {
        return [] // DR-077 §3: count takes no =value either — the update effect has no operand
      }
      // DR-034 separator (issue 2026-07-09-separator-non-string-type-parse-gap 段1): `--key=a,b`
      // goes through the SAME pieceProcessor as the space form (`sep_binds`) — split FIRST, then
      // piece_filters/parse run per PIECE, not once over the whole `valstr` (same ordering concern
      // `sep_binds`'s own doc comment explains).
      // codex Medium 追従 (issue merge-no-separator-marker-gap): gate is `separator is Some(_) ||
      // e.merge`, not `separator` alone — a merge-declared entry with NO separator still needs
      // `sep_binds` (DR-034 §6.3 の縮退: `None` → 1 piece = `valstr` 全体) so `classify_merge_piece`
      // sees `--key=-a` as a remove marker instead of falling through to the plain literal-string
      // arm below.
      if e.separator is Some(_) || e.merge {
        return match
          sep_binds(
            e.name,
            valstr,
            e.separator,
            e.kind,
            e.int_round,
            e.allow_base_prefix,
            e.bool_config,
            e.piece_filters,
            pos,
            e.merge,
          ) {
          Ok(bs) => [Accept(pos + 1, bs)]
          Err(pe) => [Held(pe, [])]
        }
      }
      // DR-034/DR-062 piece_filters: run BEFORE the kind-specific parse, same timing eval.mbt's
      // value-primitive arms use (this is the eq-split entry's own copy of the element's chain,
      // LongEntry carries it the same way it carries int_round/allow_base_prefix).
      let filtered = match apply_piece_filters(e.piece_filters, valstr) {
        Ok(s) => s
        Err((reason, msg)) =>
          return [Held(pe_filter(e.name, pos, reason, msg), [])]
      }
      match e.kind {
        TStr =>
          return [
            Accept(pos + 1, [mkb(e.name, VStr(filtered), Cli, at_pos=Some(pos))]),
          ]
        TNum => // canonical number 字句 (DR-074 §1) + opt-in base prefix (§2)
          match parse_number_ext(filtered, e.allow_base_prefix) {
            Some(d) =>
              return [
                Accept(pos + 1, [mkb(e.name, VNum(d), Cli, at_pos=Some(pos))]),
              ]
            None => return [Held(pe_parse(e.name, filtered, pos), [])]
          }
        TInt =>
          // DR-075 §1-§2 + DR-074 §2: eq-split (`--v=2.5` / `--v=0xff`) の TInt も値空間判定 + int_round
          // + 基数 prefix を適用。int_round / allow_base_prefix は installer が LongEntry に埋め込む。
          match
            parse_int_value_ext(filtered, e.int_round, e.allow_base_prefix) {
            Ok(i) =>
              return [
                Accept(pos + 1, [
                  mkb(e.name, VNum(i.to_double()), Cli, at_pos=Some(pos)),
                ]),
              ]
            Err(NotAnInteger) =>
              return [Held(pe_parse_int(e.name, filtered, pos), [])]
            Err(IntOutOfRange) =>
              return [Held(pe_int_out_of_range(e.name, filtered, pos), [])]
            Err(NotANumber) =>
              return [Held(pe_parse(e.name, filtered, pos), [])]
          }
        TFloat => // DR-074 §1: float's wider accept域 (number + inf) via parse_float
          match parse_float(filtered) {
            Some(d) =>
              return [
                Accept(pos + 1, [mkb(e.name, VNum(d), Cli, at_pos=Some(pos))]),
              ]
            None => return [Held(pe_parse(e.name, filtered, pos), [])]
          }
        TFlag => return [] // unreachable (guarded above); kept for exhaustiveness
        TCount => return [] // unreachable (guarded above); kept for exhaustiveness
        // DR-089: none has no value space, so it takes no eq-split value form either — same
        // guarded-unreachable shape as TFlag/TCount (installer.mbt's `inst_long` never registers
        // an eq-split LongEntry for a none-typed element).
        TNone => return []
        TBool =>
          // DR-074 §3/§4: a value-typed bool DOES take an eq-split value (`--enabled=true`), unlike a
          // presence-only flag firing — the CLI vocab is `parse_bool_ext(_, e.bool_config)` (canonical
          // default `true/false/1/0/""`, case-insensitive; bool_parser factory config opt-in via
          // DR-061 §4). An unrecognized token is a held Error (DR-037), not 素通し. (installer.mbt
          // `inst_long` only registers this entry when the element has no variant spellings.)
          match parse_bool_ext(filtered, e.bool_config) {
            Some(b) =>
              return [
                Accept(pos + 1, [mkb(e.name, VBool(b), Cli, at_pos=Some(pos))]),
              ]
            None => return [Held(pe_parse_bool(e.name, filtered, pos), [])]
          }
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
  ctx : Ctx,
  pos : Int,
) -> Array[Branch] {
  let tok = to_chars(ctx.toks[pos])
  let pfx = to_chars(prefix)
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
/// `Ok` = the value char attached successfully (an `Array[Binding]` — usually length 1, but a
/// `separator` entry can split one attach into several pieces, same as the long-option space form's
/// `SepArg`/`sep_binds`, issue 2026-07-09-separator-non-string-type-parse-gap 段1). `Err` carries a
/// full `ParseError` (`kind: KFilter` for a piece_filters reject, `kind: KParse` for a type-parse
/// failure — both delegate straight to `sep_binds` when `e.separator` is `Some` OR `e.merge` is
/// `true`, codex Medium 追従: a merge entry needs the piece pipeline even with no separator).
/// `walk_short`'s
/// mid-token/full-tail split still governs whether an `Err` surfaces as a `Held` or is silently
/// dropped (see its call sites) — unlike the old `Binding?`-based 2-way split, this no longer needs
/// a kind guard at the call site: a `TStr` entry structurally never produces a type-parse `Err`
/// (its parse is the identity), so "every `Err` at full-tail becomes `Held`" is equivalent to the
/// old kind-gated condition, just simpler.
/// `pos` (issue 2026-07-09-accum-entity-filters-wiring): the argv token this value char's raw
/// string was read from — the CALLING token for an in-cluster attach, the NEXT token for a
/// space-form attach (`walk_short`'s two call sites pass `pos`/`pos + 1` respectively, mirroring
/// the `pe_parse(..., pos)` / `pe_parse(..., pos + 1)` split those same call sites already made
/// pre-existing for ordinary parse failures).
fn short_val(
  e : ShortEntry,
  s : String,
  pos : Int,
) -> Result[Array[Binding], ParseError] {
  // codex Medium 追従 (issue merge-no-separator-marker-gap): `run_eq_split` と同じ gate 拡張
  // (`separator is Some(_) || e.merge`) — `-f-a` (in-cluster attach) / `-f -a` (space-form) いずれ
  // も merge 宣言なら separator 未宣言でも `sep_binds` 経由でマーカー認識させる。
  if e.separator is Some(_) || e.merge {
    // `ShortEntry` carries no `bool_config` (TBool never reaches this attach path — node.mbt's
    // `ShortEntry.piece_filters` doc comment: "Ignored for TFlag/TBool/TCount, no in-cluster/
    // space-form VALUE attachment for those"), so `sep_binds`'s bool arm is structurally dead here;
    // pass the canonical default purely to satisfy the shared signature.
    sep_binds(
      e.name,
      s,
      e.separator,
      e.kind,
      e.int_round,
      e.allow_base_prefix,
      bool_config_canonical(),
      e.piece_filters,
      pos,
      e.merge,
    )
  } else {
    let filtered = match apply_piece_filters(e.piece_filters, s) {
      Ok(v) => v
      Err((reason, msg)) => return Err(pe_filter(e.name, pos, reason, msg))
    }
    match e.kind {
      TStr => Ok([mkb(e.name, VStr(filtered), Cli, at_pos=Some(pos))])
      TNum =>
        // DR-074 §1 + §2: short cluster / space-tail の TNum も opt-in base prefix を反映。
        match parse_number_ext(filtered, e.allow_base_prefix) {
          Some(d) => Ok([mkb(e.name, VNum(d), Cli, at_pos=Some(pos))])
          None => Err(pe_parse(e.name, filtered, pos))
        }
      TInt =>
        // DR-075 §1-§2 + DR-074 §2: short cluster / space-tail の TInt も値空間判定 + int_round +
        // base prefix を反映。
        match parse_int_value_ext(filtered, e.int_round, e.allow_base_prefix) {
          Ok(i) => Ok([mkb(e.name, VNum(i.to_double()), Cli, at_pos=Some(pos))])
          Err(NotAnInteger) => Err(pe_parse_int(e.name, filtered, pos))
          Err(IntOutOfRange) => Err(pe_int_out_of_range(e.name, filtered, pos))
          Err(NotANumber) => Err(pe_parse(e.name, filtered, pos))
        }
      TFloat =>
        match parse_float(filtered) {
          Some(d) => Ok([mkb(e.name, VNum(d), Cli, at_pos=Some(pos))])
          None => Err(pe_parse(e.name, filtered, pos))
        }
      // unreachable defensively: walk_short's TFlag/TBool/TCount/TNone arms never call short_val
      // (no in-cluster/space-form VALUE attachment for those kinds — DR-089: none has no value
      // space at all).
      TFlag | TBool | TCount | TNone => Err(pe_parse(e.name, filtered, pos))
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
/// next-token space-form value (`-p 80`) and the completion `Pending` branch consume no further
/// same-token chars at all, so neither needs a `combine` check.
fn walk_short(
  entries : Array[ShortEntry],
  combine : Bool,
  body : Array[Char],
  i : Int,
  acc : Array[Binding],
  ctx : Ctx,
  pos : Int,
) -> Array[Branch] {
  if i == body.length() {
    return [Accept(pos + 1, acc)] // whole cluster consumed within this one token
  }
  let c = body[i]
  match short_lookup(entries, c) {
    None => []
    Some(e) => {
      // DR-058: a deprecated cluster entry rides a `@depr:<name>` warning marker alongside its
      // value binding (the value is unchanged; only a warning is added). `dm` is [] for a normal entry.
      let dm : Array[Binding] = if e.depr { [depr_marker(e.name)] } else { [] }
      match e.kind {
        // DR-089: a none short cluster char is presence-only too — none carries no value space so
        // it has nothing to attach in-cluster/space-form (the "食って捨てる" repeat+filter shape
        // DR-089 §2 also allows operates at the value-slot/positional-consumption level, not
        // short-cluster attachment).
        TFlag | TBool | TNone =>
          // a bool short cluster char is presence-only, same as a plain flag (DR-074 §3 canonical
          // bool has no in-cluster/space-form `=value` short spelling, only the long eq-split form).
          // `combine:false` gate: only continue when this char is the token's last (nothing left
          // to combine with) — otherwise a 2nd entry would occupy the same token, disallowed.
          if combine || i + 1 == body.length() {
            walk_short(
              entries,
              combine,
              body,
              i + 1,
              cat(acc, cat([mkb(e.name, VBool(true), Cli)], dm)),
              ctx,
              pos,
            )
          } else {
            []
          }
        TCount =>
          // DR-077 §3: count short is non-consuming, firing a 0-token `update(increment)` effect
          // (same standing as a flag's fixed `true` supply above — the fired VALUE is resolved
          // later, by resolve.mbt's CLI-seat fold, not something the matcher can compute at
          // consume time). Same `combine:false` gate as the flag-like arm above.
          if combine || i + 1 == body.length() {
            walk_short(
              entries,
              combine,
              body,
              i + 1,
              cat(acc, cat([mk_eff(e.name, Update("increment", []), Cli)], dm)),
              ctx,
              pos,
            )
          } else {
            []
          }
        _ => {
          let out : Array[Branch] = []
          let vstart = i + 1
          // in-token value of every non-empty length; continue walking the rest.
          let mut j = vstart + 1
          while j <= body.length() {
            // `combine:false` gate: a PARTIAL-length value-attach (`j < body.length()`) would leave
            // chars for a 2nd entry to combine with — skip it entirely (no reading, no Held error)
            // when combine is off. The FULL-TAIL length (`j == body.length()`, this entry alone
            // consumes everything left) is a single entry, never disallowed by `combine:false`.
            // DESIGN §7.2 / DR-096 §2/§3.1: `short_attached_value:"deny"` withholds EVERY in-cluster
            // attach reading (mid-token AND full-tail, cluster-tail included) — the mechanism itself
            // is gated, not just a lone-entry case. `"require"` does NOT gate this loop (attach stays
            // allowed, incl. cluster-tail attach, DR-096 §3.1). `"last_only"` (kawaz 裁定 2026-07-12)
            // withholds every MID-token split (`j < body.length()`) — only the FULL-TAIL "丸取り"
            // reading remains, so this entry never contributes to a split-point ambiguity (GNU
            // getopt 慣習: 値オプションに達したら以降の文字列全部がその値、DR-096 §2)。
            if e.short_attached_value != AtDeny &&
              (e.short_attached_value != AtLastOnly || j == body.length()) &&
              (combine || j == body.length()) {
              let vstr = chars_to_str(body, vstart, j)
              match short_val(e, vstr, pos) {
                Ok(bs) =>
                  for
                    r in walk_short(
                      entries,
                      combine,
                      body,
                      j,
                      cat(acc, cat(bs, dm)),
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
                  // piece-filters/reject.json が輪郭を固定する。TStr が構造的に型 parse エラーを
                  // 起こさない (short_val の doc comment) ので、kind によるガードは不要。
                  if j == body.length() {
                    out.push(Held(pe, acc))
                  }
              }
            }
            j = j + 1
          }
          // next-token value (space form) only when this value char is the tail. Not gated by
          // `combine` (doc comment above): the value comes from the NEXT token entirely, no 2nd
          // entry shares THIS token.
          // DESIGN §7.2 / DR-096 §2: `short_attached_value:"require"` withholds this space-form
          // reading entirely (both the eager next-token Accept and the completion Pending branch) —
          // this is what makes a `"require"` entry's bare tail token (e.g. `-q` with 0 leftover
          // chars) have NO complete path at all (attach needs >=1 char, DR-096 §2「付着形は定義上
          // 1 文字以上の残り文字列を要求する」), falling through to positional per DR-041 §5.
          if e.short_attached_value != AtRequire &&
            vstart == body.length() &&
            pos + 1 < ctx.toks.length() {
            match short_val(e, ctx.toks[pos + 1], pos + 1) {
              Ok(bs) => out.push(Accept(pos + 2, cat(acc, cat(bs, dm))))
              Err(pe) => out.push(Held(pe, []))
            }
          } else if e.short_attached_value != AtRequire &&
            vstart == body.length() &&
            in_complete(ctx) {
            // complete: the cluster ends in a value char and the argv ends
            // here — the space-form value is exactly what could come next
            // (DR-060 §1). The flags already read stay as partial state.
            out.push(Pending([pend_value(e.kind, e.name)], cat(acc, dm)))
          }
          out
        }
      }
    }
  }
}
