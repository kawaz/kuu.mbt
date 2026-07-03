// matcher.mbt — the native matcher interpreter (DR-041 §3-4).
//
// A matcher turns ONE token into a set of readings (branches). Each reading is a
// full interpretation of that token: it never re-reads the fragments it produced
// (DR-041 §4 "読みが生成した断片は再度読解しない"). The path-search treats every
// reading as an equal branch (DR-041 §3, no matcher-internal priority).

// String indexing yields UTF-16 code units, so cluster/value work is done on
// Array[Char] (iterating a String yields Char). Test tokens are ASCII.

fn to_chars(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

fn chars_to_str(cs : Array[Char], a : Int, b : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = a
  while i < b {
    buf.write_char(cs[i])
    i = i + 1
  }
  buf.to_string()
}

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

/// Interpret a matcher against the token at `pos`.
fn run_matcher(m : Matcher, toks : Array[String], pos : Int) -> Array[Branch] {
  if pos >= toks.length() {
    return []
  }
  match m {
    EqSplit(prefix~, entries~) => run_eq_split(prefix, entries, toks, pos)
    ShortCombine(prefix~, entries~) => run_short(prefix, entries, toks, pos)
  }
}

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
        TNum =>
          match parse_number(valstr) {
            Some(d) => return [Accept(pos + 1, [mkb(e.name, VNum(d), Cli)])]
            // defined key, bad value => held Error (DR-037), not 素通し.
            None => return [Held("\"\{valstr}\" is not a number", pos, [])]
          }
        TFlag => return [] // flags take no =value
      }
    }
  }
  [] // undefined key => 素通し
}

/// `-abc` cluster + value attachment (DR-041 §「short combine」). Enumerates ALL
/// readings; ambiguous defs (the `-cv` problem) yield multiple readings.
fn run_short(
  prefix : String,
  entries : Array[ShortEntry],
  toks : Array[String],
  pos : Int,
) -> Array[Branch] {
  let tok = to_chars(toks[pos])
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
  walk_short(entries, body, 0, [], toks, pos)
}

fn short_lookup(entries : Array[ShortEntry], c : Char) -> ShortEntry? {
  for e in entries {
    if e.ch == c {
      return Some(e)
    }
  }
  None
}

fn short_val(e : ShortEntry, s : String) -> Binding? {
  match e.kind {
    TStr => Some(mkb(e.name, VStr(s), Cli))
    TNum =>
      match parse_number(s) {
        Some(d) => Some(mkb(e.name, VNum(d), Cli))
        None => None
      }
    TFlag => None
  }
}

/// Walk the in-token cluster body from index `i`, emitting readings.
/// - a flag char advances by one;
/// - a value char attaches an in-token value of every valid length, then keeps
///   walking the remainder (so `-n1.0f` yields both n="1.0f" and n="1.0"+`-f`);
/// - a value char at the cluster tail may instead take the NEXT token as its
///   value (space form, consuming 2 tokens).
/// An undefined char kills the reading (DR-041 §5: no prefix guard — the whole
/// token simply produces no reading and falls through to positional).
fn walk_short(
  entries : Array[ShortEntry],
  body : Array[Char],
  i : Int,
  acc : Array[Binding],
  toks : Array[String],
  pos : Int,
) -> Array[Branch] {
  if i == body.length() {
    return [Accept(pos + 1, acc)] // whole cluster consumed within this one token
  }
  let c = body[i]
  match short_lookup(entries, c) {
    None => []
    Some(e) =>
      match e.kind {
        TFlag =>
          walk_short(
            entries, body, i + 1, cat(acc, [mkb(e.name, VBool(true), Cli)]), toks,
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
                for r in walk_short(entries, body, j, cat(acc, [b]), toks, pos) {
                  out.push(r)
                }
              None => ()
            }
            j = j + 1
          }
          // next-token value (space form) only when this value char is the tail.
          if vstart == body.length() && pos + 1 < toks.length() {
            match short_val(e, toks[pos + 1]) {
              Some(b) => out.push(Accept(pos + 2, cat(acc, [b])))
              None =>
                if e.kind == TNum {
                  out.push(Held("\"\{toks[pos + 1]}\" is not a number", pos + 1, []))
                }
            }
          }
          out
        }
      }
  }
}
