// separated.mbt — builtin separator/filter/type pipeline.

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
) -> Result[Array[@abi.Binding], @abi.ParseError] {
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
          link: 0,
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
              link: 0,
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
) -> Result[@abi.Value, @abi.ParseError] {
  match apply_piece_filters(extensions, piece_filters, part) {
    Err({ reason, message: msg }) =>
      Err(@abi.ParseError::filter(name, pos, reason, msg))
    Ok(s) =>
      match ty.parse_token(s) {
        Ok(value) => Ok(value)
        Err(fail) => Err(type_parse_error(name, pos, fail))
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
