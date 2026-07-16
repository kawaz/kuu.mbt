// node_residents.mbt — concrete open-node residents for builtin value and marker semantics.

///|
fn filter_spellings_json(filters : Array[FilterSpelling]) -> Json {
  let encoded : Array[Json] = []
  for filter in filters {
    encoded.push([filter.name.to_json(), filter.args.to_json()].to_json())
  }
  encoded.to_json()
}

///|
fn ty_json(ty : Ty) -> Json {
  let name = match ty {
    TStr => "string"
    TNum => "number"
    TInt => "int"
    TFloat => "float"
    TFlag => "flag"
    TBool => "bool"
    TCount => "count"
    TNone => "none"
  }
  name.to_json()
}

///|
fn round_mode_json(mode : RoundMode) -> Json {
  let name = match mode {
    RFloor => "floor"
    RCeil => "ceil"
    RTrunc => "trunc"
    RAway => "away"
    RHalfFloor => "half_floor"
    RHalfCeil => "half_ceil"
    RHalfTrunc => "half_trunc"
    RHalfAway => "half_away"
    RHalfEven => "half_even"
    RError => "error"
  }
  name.to_json()
}

///|
fn bool_config_json(config : BoolConfig) -> Json {
  [
    config.true_values.to_json(),
    config.false_values.to_json(),
    config.case_insensitive.to_json(),
  ].to_json()
}

///|
fn effect_op_json(op : EffectOp) -> Json {
  match op {
    Set => ["set".to_json()].to_json()
    Default => ["default".to_json()].to_json()
    Unset => ["unset".to_json()].to_json()
    Empty => ["empty".to_json()].to_json()
    Update(name, args) =>
      ["update".to_json(), name.to_json(), args.to_json()].to_json()
    Remove => ["remove".to_json()].to_json()
    Splice => ["splice".to_json()].to_json()
  }
}

///|
priv struct StringArgExt {
  name : String
  piece_filters : Array[FilterSpelling]
}

///|
impl NodeExt for StringArgExt with fn kind(_self) {
  "builtin/string"
}

///|
impl NodeExt for StringArgExt with fn encode(self) {
  [self.name.to_json(), filter_spellings_json(self.piece_filters)].to_json()
}

///|
impl NodeExt for StringArgExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for StringArgExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match apply_piece_filters(self.piece_filters, token) {
        Ok(value) =>
          next(
            ctx,
            pos + 1,
            cat(acc, [mkb(self.name, VStr(value), Cli, at_pos=Some(pos))]),
          )
        Err((reason, message)) =>
          [Held(pe_filter(self.name, pos, reason, message), acc)]
      }
    None => [Pending([pend_value(TStr, self.name)], acc)]
  }
}

///|
fn string_arg(name : String, piece_filters : Array[FilterSpelling]) -> Node {
  Ext(StringArgExt::{ name, piece_filters } as &NodeExt)
}

///|
priv struct KvNodeExt {
  name : String
  piece_filters : Array[FilterSpelling]
}

///|
impl NodeExt for KvNodeExt with fn kind(_self) {
  "builtin/kv"
}

///|
impl NodeExt for KvNodeExt with fn encode(self) {
  [self.name.to_json(), filter_spellings_json(self.piece_filters)].to_json()
}

///|
impl NodeExt for KvNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for KvNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match apply_piece_filters(self.piece_filters, token) {
        Ok(value) =>
          // DR-091 §2: piece filters run first, then the dedicated
          // contains-equals gate reports through the pe_parse_kv Held family.
          if contains_eq(value) {
            next(
              ctx,
              pos + 1,
              cat(acc, [mkb(self.name, VStr(value), Cli, at_pos=Some(pos))]),
            )
          } else {
            [Held(pe_parse_kv(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [Held(pe_filter(self.name, pos, reason, message), acc)]
      }
    None => [Pending([pend_value(TStr, self.name)], acc)]
  }
}

///|
fn kv_arg(name : String, piece_filters : Array[FilterSpelling]) -> Node {
  Ext(KvNodeExt::{ name, piece_filters } as &NodeExt)
}

///|
priv struct SeparatedNodeExt {
  name : String
  separator : String?
  ty : Ty
  int_round : RoundMode
  allow_base_prefix : Bool
  bool_config : BoolConfig
  piece_filters : Array[FilterSpelling]
  merge : Bool
}

///|
impl NodeExt for SeparatedNodeExt with fn kind(_self) {
  "builtin/separated"
}

///|
impl NodeExt for SeparatedNodeExt with fn encode(self) {
  [
    self.name.to_json(),
    self.separator.to_json(),
    ty_json(self.ty),
    round_mode_json(self.int_round),
    self.allow_base_prefix.to_json(),
    bool_config_json(self.bool_config),
    filter_spellings_json(self.piece_filters),
    self.merge.to_json(),
  ].to_json()
}

///|
impl NodeExt for SeparatedNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for SeparatedNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        sep_binds(
          self.name,
          token,
          self.separator,
          self.ty,
          self.int_round,
          self.allow_base_prefix,
          self.bool_config,
          self.piece_filters,
          pos,
          self.merge,
        ) {
        Ok(bindings) => next(ctx, pos + 1, cat(acc, bindings))
        Err(error) => [Held(error, acc)]
      }
    None => [Pending([pend_value(self.ty, self.name)], acc)]
  }
}

///|
fn separated_arg(
  name : String,
  separator : String?,
  ty : Ty,
  int_round : RoundMode,
  allow_base_prefix : Bool,
  bool_config : BoolConfig,
  piece_filters : Array[FilterSpelling],
  merge : Bool,
) -> Node {
  Ext(
    SeparatedNodeExt::{
      name,
      separator,
      ty,
      int_round,
      allow_base_prefix,
      bool_config,
      piece_filters,
      merge,
    }
    as &NodeExt,
  )
}

///|
priv struct NumberArgExt {
  name : String
  allow_base_prefix : Bool
  piece_filters : Array[FilterSpelling]
}

///|
impl NodeExt for NumberArgExt with fn kind(_self) {
  "builtin/number"
}

///|
impl NodeExt for NumberArgExt with fn encode(self) {
  [
    self.name.to_json(),
    self.allow_base_prefix.to_json(),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl NodeExt for NumberArgExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for NumberArgExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match apply_piece_filters(self.piece_filters, token) {
        Ok(value) =>
          // Every number-lexicon rejection reports through pe_parse.
          match parse_number_ext(value, self.allow_base_prefix) {
            Some(number) =>
              next(
                ctx,
                pos + 1,
                cat(acc, [mkb(self.name, VNum(number), Cli, at_pos=Some(pos))]),
              )
            None => [Held(pe_parse(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [Held(pe_filter(self.name, pos, reason, message), acc)]
      }
    None => [Pending([pend_value(TNum, self.name)], acc)]
  }
}

///|
fn number_arg(
  name : String,
  allow_base_prefix : Bool,
  piece_filters : Array[FilterSpelling],
) -> Node {
  Ext(NumberArgExt::{ name, allow_base_prefix, piece_filters } as &NodeExt)
}

///|
priv struct FloatNodeExt {
  name : String
  piece_filters : Array[FilterSpelling]
}

///|
impl NodeExt for FloatNodeExt with fn kind(_self) {
  "builtin/float"
}

///|
impl NodeExt for FloatNodeExt with fn encode(self) {
  [self.name.to_json(), filter_spellings_json(self.piece_filters)].to_json()
}

///|
impl NodeExt for FloatNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for FloatNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match apply_piece_filters(self.piece_filters, token) {
        Ok(value) =>
          // The wider float lexicon still reports lexical rejection through pe_parse.
          match parse_float(value) {
            Some(number) =>
              next(
                ctx,
                pos + 1,
                cat(acc, [mkb(self.name, VNum(number), Cli, at_pos=Some(pos))]),
              )
            None => [Held(pe_parse(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [Held(pe_filter(self.name, pos, reason, message), acc)]
      }
    None => [Pending([pend_value(TFloat, self.name)], acc)]
  }
}

///|
fn float_arg(name : String, piece_filters : Array[FilterSpelling]) -> Node {
  Ext(FloatNodeExt::{ name, piece_filters } as &NodeExt)
}

///|
priv struct IntNodeExt {
  name : String
  int_round : RoundMode
  allow_base_prefix : Bool
  piece_filters : Array[FilterSpelling]
}

///|
impl NodeExt for IntNodeExt with fn kind(_self) {
  "builtin/int"
}

///|
impl NodeExt for IntNodeExt with fn encode(self) {
  [
    self.name.to_json(),
    round_mode_json(self.int_round),
    self.allow_base_prefix.to_json(),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl NodeExt for IntNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for IntNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match apply_piece_filters(self.piece_filters, token) {
        Ok(value) =>
          // int resident has three distinct Held families; preserving this split is
          // part of the resident contract, not a generic number error path.
          match
            parse_int_value_ext(value, self.int_round, self.allow_base_prefix) {
            Ok(integer) =>
              next(
                ctx,
                pos + 1,
                cat(acc, [
                  mkb(
                    self.name,
                    VNum(integer.to_double()),
                    Cli,
                    at_pos=Some(pos),
                  ),
                ]),
              )
            Err(NotAnInteger) =>
              [Held(pe_parse_int(self.name, value, pos), acc)]
            Err(IntOutOfRange) =>
              [Held(pe_int_out_of_range(self.name, value, pos), acc)]
            Err(NotANumber) => [Held(pe_parse(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [Held(pe_filter(self.name, pos, reason, message), acc)]
      }
    None => [Pending([pend_value(TInt, self.name)], acc)]
  }
}

///|
fn int_arg(
  name : String,
  int_round : RoundMode,
  allow_base_prefix : Bool,
  piece_filters : Array[FilterSpelling],
) -> Node {
  Ext(
    IntNodeExt::{ name, int_round, allow_base_prefix, piece_filters }
    as &NodeExt,
  )
}

///|
priv struct BoolNodeExt {
  name : String
  bool_config : BoolConfig
  piece_filters : Array[FilterSpelling]
}

///|
impl NodeExt for BoolNodeExt with fn kind(_self) {
  "builtin/bool"
}

///|
impl NodeExt for BoolNodeExt with fn encode(self) {
  [
    self.name.to_json(),
    bool_config_json(self.bool_config),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl NodeExt for BoolNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for BoolNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match apply_piece_filters(self.piece_filters, token) {
        Ok(value) =>
          // bool resident retains pe_parse_bool rather than sharing number's pe_parse.
          match parse_bool_ext(value, self.bool_config) {
            Some(boolean) =>
              next(
                ctx,
                pos + 1,
                cat(acc, [mkb(self.name, VBool(boolean), Cli, at_pos=Some(pos))]),
              )
            None => [Held(pe_parse_bool(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [Held(pe_filter(self.name, pos, reason, message), acc)]
      }
    None => [Pending([pend_value(TBool, self.name)], acc)]
  }
}

///|
fn bool_arg(
  name : String,
  bool_config : BoolConfig,
  piece_filters : Array[FilterSpelling],
) -> Node {
  Ext(BoolNodeExt::{ name, bool_config, piece_filters } as &NodeExt)
}

///|
priv struct EffectMarkExt {
  name : String
  op : EffectOp
}

///|
impl NodeExt for EffectMarkExt with fn kind(_self) {
  "builtin/effect"
}

///|
impl NodeExt for EffectMarkExt with fn encode(self) {
  [self.name.to_json(), effect_op_json(self.op)].to_json()
}

///|
impl NodeExt for EffectMarkExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl NodeExt for EffectMarkExt with fn eval(self, ctx, pos, acc, next) {
  next(ctx, pos, cat(acc, [mk_eff(self.name, self.op, Cli)]))
}

///|
fn effect_mark(name : String, op : EffectOp) -> Node {
  Ext(EffectMarkExt::{ name, op } as &NodeExt)
}

///|
priv struct DeprecationMarkExt {
  name : String
}

///|
impl NodeExt for DeprecationMarkExt with fn kind(_self) {
  "builtin/deprecation"
}

///|
impl NodeExt for DeprecationMarkExt with fn encode(self) {
  [self.name.to_json()].to_json()
}

///|
impl NodeExt for DeprecationMarkExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl NodeExt for DeprecationMarkExt with fn eval(self, ctx, pos, acc, next) {
  next(ctx, pos, cat(acc, [depr_marker(self.name)]))
}

///|
fn deprecation_mark(name : String) -> Node {
  Ext(DeprecationMarkExt::{ name, } as &NodeExt)
}

///|
priv struct FailureMarkExt {
  name : String
}

///|
impl NodeExt for FailureMarkExt with fn kind(_self) {
  "builtin/failure"
}

///|
impl NodeExt for FailureMarkExt with fn encode(self) {
  [self.name.to_json()].to_json()
}

///|
impl NodeExt for FailureMarkExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl NodeExt for FailureMarkExt with fn eval(self, ctx, pos, acc, next) {
  next(ctx, pos, cat(acc, [action_marker(self.name, pos)]))
}

///|
fn failure_mark(name : String) -> Node {
  Ext(FailureMarkExt::{ name, } as &NodeExt)
}

///|
fn node_resident_name(node : Node) -> String? {
  guard node is Ext(extension) else { return None }
  match extension.kind() {
    "builtin/string"
    | "builtin/kv"
    | "builtin/separated"
    | "builtin/number"
    | "builtin/float"
    | "builtin/int"
    | "builtin/bool" =>
      match extension.encode() {
        Array([String(name), ..]) => Some(name)
        _ => None
      }
    _ => None
  }
}

///|
fn node_is_failure_mark(node : Node) -> Bool {
  node is Ext(extension) && extension.kind() == "builtin/failure"
}

///|
fn strings_of_json(json : Json) -> Array[String]? {
  guard json is Array(items) else { return None }
  let out : Array[String] = []
  for item in items {
    guard item is String(value) else { return None }
    out.push(value)
  }
  Some(out)
}

///|
fn effect_op_of_json(json : Json) -> EffectOp? {
  guard json is Array(parts) else { return None }
  guard parts.get(0) is Some(String(tag)) else { return None }
  match tag {
    "set" => Some(Set)
    "default" => Some(Default)
    "unset" => Some(Unset)
    "empty" => Some(Empty)
    "remove" => Some(Remove)
    "splice" => Some(Splice)
    "update" => {
      guard parts.get(1) is Some(String(name)) else { return None }
      guard parts.get(2) is Some(args_json) else { return None }
      guard strings_of_json(args_json) is Some(args) else { return None }
      Some(Update(name, args))
    }
    _ => None
  }
}

///|
fn node_effect_mark(node : Node) -> (String, EffectOp)? {
  guard node is Ext(extension) else { return None }
  guard extension.kind() == "builtin/effect" else { return None }
  guard extension.encode() is Array(parts) else { return None }
  guard parts.get(0) is Some(String(name)) else { return None }
  guard parts.get(1) is Some(op_json) else { return None }
  guard effect_op_of_json(op_json) is Some(op) else { return None }
  Some((name, op))
}

///|
fn node_consumes_zero_tokens(node : Node) -> Bool {
  match node {
    Bind(_, _) => true
    Ext(extension) => extension.consumes_zero_tokens()
    _ => false
  }
}
