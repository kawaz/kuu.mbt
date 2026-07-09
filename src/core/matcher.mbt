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
    ShortCombine(prefix~, entries~) => run_short(prefix, entries, ctx, pos)
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
    ShortCombine(prefix~, entries~) =>
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
      // TFlag/TCount take no eq-split value at all (no raw string to gate), so pre_filters is
      // skipped for them entirely — checked BEFORE running the chain to avoid filtering a value
      // slot that structurally doesn't exist for this kind.
      if e.kind == TFlag {
        return [] // presence-only trigger (DR-074 no eq-split): flags take no =value
      }
      if e.kind == TCount {
        return [] // DR-077 §3: count takes no =value either — the update effect has no operand
      }
      // DR-034/DR-062 pre_filters: run BEFORE the kind-specific parse, same timing eval.mbt's
      // value-primitive arms use (this is the eq-split entry's own copy of the element's chain,
      // LongEntry carries it the same way it carries int_round/allow_base_prefix).
      let filtered = match apply_pre_filters(e.pre_filters, valstr) {
        Ok(s) => s
        Err((reason, msg)) =>
          return [Held(pe_filter(e.name, pos, reason, msg), [])]
      }
      match e.kind {
        TStr => return [Accept(pos + 1, [mkb(e.name, VStr(filtered), Cli)])]
        TNum => // canonical number 字句 (DR-074 §1) + opt-in base prefix (§2)
          match parse_number_ext(filtered, e.allow_base_prefix) {
            Some(d) => return [Accept(pos + 1, [mkb(e.name, VNum(d), Cli)])]
            None => return [Held(pe_parse(e.name, filtered, pos), [])]
          }
        TInt =>
          // DR-075 §1-§2 + DR-074 §2: eq-split (`--v=2.5` / `--v=0xff`) の TInt も値空間判定 + int_round
          // + 基数 prefix を適用。int_round / allow_base_prefix は installer が LongEntry に埋め込む。
          match
            parse_int_value_ext(filtered, e.int_round, e.allow_base_prefix) {
            Ok(i) =>
              return [Accept(pos + 1, [mkb(e.name, VNum(i.to_double()), Cli)])]
            Err(NotAnInteger) =>
              return [Held(pe_parse_int(e.name, filtered, pos), [])]
            Err(IntOutOfRange) =>
              return [Held(pe_int_out_of_range(e.name, filtered, pos), [])]
            Err(NotANumber) =>
              return [Held(pe_parse(e.name, filtered, pos), [])]
          }
        TFloat => // DR-074 §1: float's wider accept域 (number + inf) via parse_float
          match parse_float(filtered) {
            Some(d) => return [Accept(pos + 1, [mkb(e.name, VNum(d), Cli)])]
            None => return [Held(pe_parse(e.name, filtered, pos), [])]
          }
        TFlag => return [] // unreachable (guarded above); kept for exhaustiveness
        TCount => return [] // unreachable (guarded above); kept for exhaustiveness
        TBool =>
          // DR-074 §3: a value-typed bool DOES take an eq-split value (`--enabled=true`), unlike a
          // presence-only flag firing — the CLI vocab is canonical `parse_bool` (true/false/1/0/"",
          // case-insensitive). An unrecognized token is a held Error (DR-037), not 素通し. (installer.mbt
          // `inst_long` only registers this entry when the element has no variant spellings.)
          match parse_bool(filtered) {
            Some(b) => return [Accept(pos + 1, [mkb(e.name, VBool(b), Cli)])]
            None => return [Held(pe_parse_bool(e.name, filtered, pos), [])]
          }
      }
    }
  }
  [] // undefined key => 素通し
}

///|
/// `-abc` cluster + value attachment (DR-041 §「short combine」). Enumerates ALL
/// readings; ambiguous defs (the `-cv` problem) yield multiple readings.
fn run_short(
  prefix : String,
  entries : Array[ShortEntry],
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
  walk_short(entries, body, 0, [], ctx, pos)
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
/// `Ok` = the value char attached successfully. `Err(None)` = an ORDINARY parse failure (the
/// pre-DR-034 contract: caller falls back to `pe_parse`/kind:KParse at the tail position, same as
/// a bare `Binding?`'s `None` always meant). `Err(Some((reason, message)))` = a DR-034/DR-062
/// pre_filters chain rejected the raw value BEFORE it ever reached the kind-specific parser — a
/// DISTINCT failure kind (KFilter) the old `Binding?` signature had no channel for, hence the
/// signature widening from `Binding?` to this `Result`. Both error shapes stay valid at every value
/// char length (`walk_short`'s mid-token/full-tail split still governs whether a failure surfaces
/// as a `Held` or is silently dropped — see its call sites).
fn short_val(e : ShortEntry, s : String) -> Result[Binding, (String, String)?] {
  match e.kind {
    TStr =>
      match apply_pre_filters(e.pre_filters, s) {
        Ok(v) => Ok(mkb(e.name, VStr(v), Cli))
        Err(fe) => Err(Some(fe))
      }
    TNum =>
      // DR-074 §1 + §2: short cluster / space-tail の TNum も opt-in base prefix を反映。
      match apply_pre_filters(e.pre_filters, s) {
        Ok(v) =>
          match parse_number_ext(v, e.allow_base_prefix) {
            Some(d) => Ok(mkb(e.name, VNum(d), Cli))
            None => Err(None)
          }
        Err(fe) => Err(Some(fe))
      }
    TInt =>
      // DR-075 §1-§2 + DR-074 §2: short cluster / space-tail の TInt も値空間判定 + int_round +
      // base prefix を反映。丸めモード / 基数 prefix で Ok(...) は Some、それ以外は None を返し
      // caller (walk_short) が tail 位置で held Error を組む (既存の Binding? 契約範囲内)。
      match apply_pre_filters(e.pre_filters, s) {
        Ok(v) =>
          match parse_int_value_ext(v, e.int_round, e.allow_base_prefix) {
            Ok(i) => Ok(mkb(e.name, VNum(i.to_double()), Cli))
            Err(_) => Err(None)
          }
        Err(fe) => Err(Some(fe))
      }
    TFloat =>
      match apply_pre_filters(e.pre_filters, s) {
        Ok(v) =>
          match parse_float(v) {
            Some(d) => Ok(mkb(e.name, VNum(d), Cli))
            None => Err(None)
          }
        Err(fe) => Err(Some(fe))
      }
    TFlag | TBool => Err(None) // no in-cluster/space-form VALUE attachment for a bool short (no fixture needs `-e5`/`-e true`)
    TCount => Err(None) // DR-077 §3: count short is non-consuming (fixed increment), same standing as a bool short
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
fn walk_short(
  entries : Array[ShortEntry],
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
        TFlag | TBool =>
          // a bool short cluster char is presence-only, same as a plain flag (DR-074 §3 canonical
          // bool has no in-cluster/space-form `=value` short spelling, only the long eq-split form).
          walk_short(
            entries,
            body,
            i + 1,
            cat(acc, cat([mkb(e.name, VBool(true), Cli)], dm)),
            ctx,
            pos,
          )
        TCount =>
          // DR-077 §3: count short is non-consuming, firing a 0-token `update(increment)` effect
          // (same standing as a flag's fixed `true` supply above — the fired VALUE is resolved
          // later, by resolve.mbt's CLI-seat fold, not something the matcher can compute at
          // consume time).
          walk_short(
            entries,
            body,
            i + 1,
            cat(acc, cat([mk_eff(e.name, Update("increment", []), Cli)], dm)),
            ctx,
            pos,
          )
        _ => {
          let out : Array[Branch] = []
          let vstart = i + 1
          // in-token value of every non-empty length; continue walking the rest.
          let mut j = vstart + 1
          while j <= body.length() {
            let vstr = chars_to_str(body, vstart, j)
            match short_val(e, vstr) {
              Ok(b) =>
                for
                  r in walk_short(
                    entries,
                    body,
                    j,
                    cat(acc, cat([b], dm)),
                    ctx,
                    pos,
                  ) {
                  out.push(r)
                }
              Err(Some((reason, msg))) =>
                // DR-034/DR-062 pre_filters rejected this length's raw value BEFORE it reached the
                // kind-specific parser — same mid-token/full-tail asymmetry as the ordinary parse-
                // fail arm below (a mid-token reject is a silent non-reading, only the FULL-TAIL
                // attach surfaces as a held Error), but UNGATED by kind (unlike parse failures,
                // pre_filters applies to every value-taking kind including TStr — fixture
                // pre-filters/reject.json's `name` is a plain string).
                if j == body.length() {
                  out.push(Held(pe_filter(e.name, pos, reason, msg), acc))
                }
              Err(None) =>
                // A typed value that fails to parse: a mid-token split is a
                // silent non-reading (its remainder would need OTHER defined
                // chars to progress, DR-041 §3), but the FULL-TAIL attach is
                // the「値 char が残余全体を値として取る」唯一形の読みなので、
                // its parse failure is a held Error (DR-041 §5 値不正 =
                // Error、DR-074 の suffix 拒否がここに落ちる)。fixture
                // matcher-readings/cluster-split-no-flag が輪郭を固定する。
                if j == body.length() &&
                  (e.kind == TNum || e.kind == TInt || e.kind == TFloat) {
                  out.push(Held(pe_parse(e.name, vstr, pos), acc))
                }
            }
            j = j + 1
          }
          // next-token value (space form) only when this value char is the tail.
          if vstart == body.length() && pos + 1 < ctx.toks.length() {
            match short_val(e, ctx.toks[pos + 1]) {
              Ok(b) => out.push(Accept(pos + 2, cat(acc, cat([b], dm))))
              Err(Some((reason, msg))) =>
                out.push(Held(pe_filter(e.name, pos + 1, reason, msg), []))
              Err(None) =>
                if e.kind == TNum || e.kind == TInt || e.kind == TFloat {
                  out.push(
                    Held(pe_parse(e.name, ctx.toks[pos + 1], pos + 1), []),
                  )
                }
            }
          } else if vstart == body.length() && in_complete(ctx) {
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
