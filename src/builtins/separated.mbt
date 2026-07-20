// separated.mbt — builtin separator/filter/type pipeline.

///|
fn sep_binds(
  name : String,
  tok : String,
  sep : String?,
  ty : &@engine.TypeExt,
  piece_filters : Array[@engine.FilterSpelling],
  pos : Int,
  merge : Bool,
  extensions : @engine.Registry,
) -> Result[Array[@engine.Binding], @engine.ParseError] {
  let out : Array[@engine.Binding] = []
  let parts = match sep {
    Some(s) => @engine.split_on(tok, s)
    None => [tok]
  }
  for part in parts {
    let mark : @engine.PieceMark = if merge {
      @engine.classify_merge_piece(part)
    } else {
      @engine.PkAdd(part)
    }
    match mark {
      // DR-080 §2 splice: no payload, no filters/parse — a pure cell-marker binding
      // (mirrors Default/Unset/Empty's placeholder-value convention).
      @engine.PkSplice =>
        out.push({
          key: name,
          op: @engine.Splice,
          value: @engine.Bool(false),
          source: @engine.Cli,
          scope: [],
          link: 0,
          at_pos: Some(pos),
        })
      @engine.PkRemove(payload) =>
        match
          sep_piece_value(name, payload, ty, piece_filters, pos, extensions) {
          Ok(v) =>
            out.push({
              key: name,
              op: @engine.Remove,
              value: v,
              source: @engine.Cli,
              scope: [],
              link: 0,
              at_pos: Some(pos),
            })
          Err(pe) => return Err(pe)
        }
      @engine.PkAdd(payload) =>
        match
          sep_piece_value(name, payload, ty, piece_filters, pos, extensions) {
          Ok(v) =>
            out.push(@engine.mk_binding(name, v, @engine.Cli, at_pos=Some(pos)))
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
  ty : &@engine.TypeExt,
  piece_filters : Array[@engine.FilterSpelling],
  pos : Int,
  extensions : @engine.Registry,
) -> Result[@engine.Value, @engine.ParseError] {
  match @engine.apply_piece_filters(extensions, piece_filters, part) {
    Err((reason, msg)) => Err(@engine.pe_filter(name, pos, reason, msg))
    Ok(s) =>
      match ty.parse_token(s) {
        Ok(value) => Ok(value)
        Err(fail) => Err(type_parse_error(name, pos, fail))
      }
  }
}
