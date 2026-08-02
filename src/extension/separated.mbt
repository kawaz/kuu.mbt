// separated.mbt — builtin separator/filter/type pipeline.

///|
/// A separated piece failure keeps the parser/filter's DR-037 phase next to its wire-facing error.
pub struct ReadingFail {
  disposition : @abi.TypeParseDisposition
  error : @abi.ParseError
}

///|
pub fn ReadingFail::branch(
  self : ReadingFail,
  bindings : Array[@abi.Binding],
) -> @abi.Branch {
  match self.disposition {
    @abi.ValueSpaceMiss => @abi.Rejected(self.error, bindings)
    @abi.RecognizedButInvalid => @abi.Held(self.error, bindings)
  }
}

///|
/// A committed reading has no sibling branch for `ValueSpaceMiss` to select, so every failure is a
/// held diagnostic. Choice contexts use `branch` and retain the disposition distinction.
pub fn ReadingFail::committed_branch(
  self : ReadingFail,
  bindings : Array[@abi.Binding],
) -> @abi.Branch {
  @abi.Held(self.error, bindings)
}

///|
pub fn sep_binds(
  name : String,
  tok : String,
  sep : String?,
  ty : &TypeExt,
  piece_filters : Array[@abi.FnInvocation],
  pos : Int,
  merge : Bool,
  extensions : Registry,
) -> Result[Array[@abi.Binding], ReadingFail] {
  let out : Array[@abi.Binding] = []
  let parts = match sep {
    Some(s) => split_on_sep(tok, s)
    None => [tok]
  }
  for part in parts {
    let mark : PieceMark = if merge {
      classify_merge_piece(part)
    } else {
      PieceMark::Add(part)
    }
    match mark {
      // DR-080 §2 splice: no payload, no filters/parse — a pure cell-marker binding
      // (mirrors Default/Unset/Empty's placeholder-value convention).
      PieceMark::Splice =>
        out.push({
          key: name,
          op: @abi.Splice,
          value: @abi.Bool(false),
          source: @abi.Cli,
          scope: [],
          link_selections: [],
          observation: None,
          levels_to_declaring_scope: 0,
          at_pos: Some(pos),
        })
      PieceMark::Remove(payload) =>
        match
          sep_piece_value(name, payload, ty, piece_filters, pos, extensions) {
          Ok(v) =>
            out.push({
              key: name,
              op: @abi.Remove,
              value: v,
              source: @abi.Cli,
              scope: [],
              link_selections: [],
              observation: None,
              levels_to_declaring_scope: 0,
              at_pos: Some(pos),
            })
          Err(pe) => return Err(pe)
        }
      PieceMark::Add(payload) =>
        match
          sep_piece_value(name, payload, ty, piece_filters, pos, extensions) {
          Ok(v) =>
            out.push(@abi.Binding::new(name, v, @abi.Cli, at_pos=Some(pos)))
          Err(pe) => return Err(pe)
        }
    }
  }
  Ok(out)
}

///|
/// One split piece's payload → `piece_filters` → type parse (DESIGN §6.2's pieceProcessor,
/// shared by `sep_binds`'s add/remove piece kinds — DR-080 §2 "remove operand は payload として
/// 型 parse を通る", 同じ規約を add piece と共有する). Factored out of `sep_binds` so the
/// non-merge (plain add) and merge (add/remove) piece kinds run the EXACT same filter→parse
/// pipeline, never two copies drifting apart.
fn sep_piece_value(
  name : String,
  part : String,
  ty : &TypeExt,
  piece_filters : Array[@abi.FnInvocation],
  pos : Int,
  extensions : Registry,
) -> Result[@abi.Value, ReadingFail] {
  match apply_piece_filters(extensions, piece_filters, part) {
    Err({ disposition, reason, message: msg }) =>
      Err({
        disposition,
        error: @abi.ParseError::filter(name, pos, reason, msg),
      })
    Ok(s) =>
      match parse_token_checked(ty, s, extensions) {
        Ok(value) => Ok(value)
        Err(fail) =>
          Err({
            disposition: fail.disposition,
            error: type_parse_error(name, pos, fail),
          })
      }
  }
}

///|
/// Split `s` on the first char of `sep` (spec DR-034 single-char separator).
fn split_on_sep(s : String, sep : String) -> Array[String] {
  let mut sepc = ','
  for c in sep {
    sepc = c
    break
  }
  let out : Array[String] = []
  let cur = StringBuilder::new()
  for c in s {
    if c == sepc {
      out.push(cur.to_string())
      cur.reset()
    } else {
      cur.write_char(c)
    }
  }
  out.push(cur.to_string())
  out
}
