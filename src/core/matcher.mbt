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
        if e.kind != TFlag {
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
      match e.kind {
        TStr => return [Accept(pos + 1, [mkb(e.name, VStr(valstr), Cli)])]
        TNum => // canonical number 字句 (DR-074 §1) + opt-in base prefix (§2)
          match parse_number_ext(valstr, e.allow_base_prefix) {
            Some(d) => return [Accept(pos + 1, [mkb(e.name, VNum(d), Cli)])]
            None => return [Held(pe_parse(e.name, valstr, pos), [])]
          }
        TInt =>
          // DR-075 §1-§2 + DR-074 §2: eq-split (`--v=2.5` / `--v=0xff`) の TInt も値空間判定 + int_round
          // + 基数 prefix を適用。int_round / allow_base_prefix は installer が LongEntry に埋め込む。
          match parse_int_value_ext(valstr, e.int_round, e.allow_base_prefix) {
            Ok(i) =>
              return [Accept(pos + 1, [mkb(e.name, VNum(i.to_double()), Cli)])]
            Err(NotAnInteger) =>
              return [Held(pe_parse_int(e.name, valstr, pos), [])]
            Err(IntOutOfRange) =>
              return [Held(pe_int_out_of_range(e.name, valstr, pos), [])]
            Err(NotANumber) => return [Held(pe_parse(e.name, valstr, pos), [])]
          }
        TFloat => // DR-074 §1: float's wider accept域 (number + inf) via parse_float
          match parse_float(valstr) {
            Some(d) => return [Accept(pos + 1, [mkb(e.name, VNum(d), Cli)])]
            None => return [Held(pe_parse(e.name, valstr, pos), [])]
          }
        TFlag => return [] // presence-only trigger (DR-074 no eq-split): flags take no =value
        TBool =>
          // DR-074 §3: a value-typed bool DOES take an eq-split value (`--enabled=true`), unlike a
          // presence-only flag firing — the CLI vocab is canonical `parse_bool` (true/false/1/0/"",
          // case-insensitive). An unrecognized token is a held Error (DR-037), not 素通し. (installer.mbt
          // `inst_long` only registers this entry when the element has no variant spellings.)
          match parse_bool(valstr) {
            Some(b) => return [Accept(pos + 1, [mkb(e.name, VBool(b), Cli)])]
            None => return [Held(pe_parse_bool(e.name, valstr, pos), [])]
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
fn short_val(e : ShortEntry, s : String) -> Binding? {
  match e.kind {
    TStr => Some(mkb(e.name, VStr(s), Cli))
    TNum =>
      // DR-074 §1 + §2: short cluster / space-tail の TNum も opt-in base prefix を反映。
      match parse_number_ext(s, e.allow_base_prefix) {
        Some(d) => Some(mkb(e.name, VNum(d), Cli))
        None => None
      }
    TInt =>
      // DR-075 §1-§2 + DR-074 §2: short cluster / space-tail の TInt も値空間判定 + int_round +
      // base prefix を反映。丸めモード / 基数 prefix で Ok(...) は Some、それ以外は None を返し
      // caller (walk_short) が tail 位置で held Error を組む (既存の Binding? 契約範囲内)。
      match parse_int_value_ext(s, e.int_round, e.allow_base_prefix) {
        Ok(i) => Some(mkb(e.name, VNum(i.to_double()), Cli))
        Err(_) => None
      }
    TFloat =>
      match parse_float(s) {
        Some(d) => Some(mkb(e.name, VNum(d), Cli))
        None => None
      }
    TFlag | TBool => None // no in-cluster/space-form VALUE attachment for a bool short (no fixture needs `-e5`/`-e true`)
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
        _ => {
          let out : Array[Branch] = []
          let vstart = i + 1
          // in-token value of every non-empty length; continue walking the rest.
          let mut j = vstart + 1
          while j <= body.length() {
            let vstr = chars_to_str(body, vstart, j)
            match short_val(e, vstr) {
              Some(b) =>
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
              None =>
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
              Some(b) => out.push(Accept(pos + 2, cat(acc, cat([b], dm))))
              None =>
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
