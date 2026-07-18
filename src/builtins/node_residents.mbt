// node_residents.mbt — concrete open-node residents for builtin value and marker semantics.

///|
fn filter_spellings_json(filters : Array[@engine.FilterSpelling]) -> Json {
  let encoded : Array[Json] = []
  for filter in filters {
    encoded.push([filter.name.to_json(), filter.args.to_json()].to_json())
  }
  encoded.to_json()
}

///|
fn ty_json(ty : &@engine.TypeExt) -> Json {
  ty.name().to_json()
}

///|
fn round_mode_json(mode : @engine.RoundMode) -> Json {
  let name = match mode {
    @engine.RFloor => "floor"
    @engine.RCeil => "ceil"
    @engine.RTrunc => "trunc"
    @engine.RAway => "away"
    @engine.RHalfFloor => "half_floor"
    @engine.RHalfCeil => "half_ceil"
    @engine.RHalfTrunc => "half_trunc"
    @engine.RHalfAway => "half_away"
    @engine.RHalfEven => "half_even"
    @engine.RError => "error"
  }
  name.to_json()
}

///|
fn bool_config_json(config : @engine.BoolConfig) -> Json {
  [
    config.true_values.to_json(),
    config.false_values.to_json(),
    config.case_insensitive.to_json(),
  ].to_json()
}

///|
fn effect_op_json(op : @engine.EffectOp) -> Json {
  match op {
    @engine.Set => ["set".to_json()].to_json()
    @engine.Default => ["default".to_json()].to_json()
    @engine.Unset => ["unset".to_json()].to_json()
    @engine.Empty => ["empty".to_json()].to_json()
    @engine.Update(name, args) =>
      ["update".to_json(), name.to_json(), args.to_json()].to_json()
    @engine.Remove => ["remove".to_json()].to_json()
    @engine.Splice => ["splice".to_json()].to_json()
  }
}

///|
priv struct StringArgExt {
  name : String
  piece_filters : Array[@engine.FilterSpelling]
}

///|
impl @engine.NodeExt for StringArgExt with fn kind(_self) {
  "builtin/string"
}

///|
impl @engine.NodeExt for StringArgExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for StringArgExt with fn encode(self) {
  [self.name.to_json(), filter_spellings_json(self.piece_filters)].to_json()
}

///|
impl @engine.NodeExt for StringArgExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for StringArgExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @engine.apply_piece_filters(ctx.extensions(), self.piece_filters, token) {
        Ok(value) =>
          next(
            ctx,
            pos + 1,
            @engine.cat(acc, [
              @engine.mkb(
                self.name,
                @engine.VStr(value),
                @engine.Cli,
                at_pos=Some(pos),
              ),
            ]),
          )
        Err((reason, message)) =>
          [
            @engine.Held(
              @engine.pe_filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @engine.Pending(
          [@engine.pend_value(string_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn string_arg(
  name : String,
  piece_filters : Array[@engine.FilterSpelling],
) -> @engine.Node {
  @engine.Ext(StringArgExt::{ name, piece_filters } as &@engine.NodeExt)
}

///|
priv struct KvNodeExt {
  name : String
  piece_filters : Array[@engine.FilterSpelling]
}

///|
impl @engine.NodeExt for KvNodeExt with fn kind(_self) {
  "builtin/kv"
}

///|
impl @engine.NodeExt for KvNodeExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for KvNodeExt with fn encode(self) {
  [self.name.to_json(), filter_spellings_json(self.piece_filters)].to_json()
}

///|
impl @engine.NodeExt for KvNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for KvNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @engine.apply_piece_filters(ctx.extensions(), self.piece_filters, token) {
        Ok(value) =>
          // DR-091 §2: piece filters run first, then the dedicated
          // contains-equals gate reports through the @engine.pe_parse_kv @engine.Held family.
          if @engine.contains_eq(value) {
            next(
              ctx,
              pos + 1,
              @engine.cat(acc, [
                @engine.mkb(
                  self.name,
                  @engine.VStr(value),
                  @engine.Cli,
                  at_pos=Some(pos),
                ),
              ]),
            )
          } else {
            [@engine.Held(@engine.pe_parse_kv(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [
            @engine.Held(
              @engine.pe_filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @engine.Pending(
          [@engine.pend_value(string_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn kv_arg(
  name : String,
  piece_filters : Array[@engine.FilterSpelling],
) -> @engine.Node {
  @engine.Ext(KvNodeExt::{ name, piece_filters } as &@engine.NodeExt)
}

///|
priv struct SeparatedNodeExt {
  name : String
  separator : String?
  ty : &@engine.TypeExt
  int_round : @engine.RoundMode
  allow_base_prefix : Bool
  bool_config : @engine.BoolConfig
  piece_filters : Array[@engine.FilterSpelling]
  merge : Bool
}

///|
impl @engine.NodeExt for SeparatedNodeExt with fn kind(_self) {
  "builtin/separated"
}

///|
impl @engine.NodeExt for SeparatedNodeExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for SeparatedNodeExt with fn encode(self) {
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
impl @engine.NodeExt for SeparatedNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for SeparatedNodeExt with fn eval(
  self,
  ctx,
  pos,
  acc,
  next,
) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        sep_binds(
          self.name,
          token,
          self.separator,
          self.ty,
          self.piece_filters,
          pos,
          self.merge,
          ctx.extensions(),
        ) {
        Ok(bindings) => next(ctx, pos + 1, @engine.cat(acc, bindings))
        Err(error) => [@engine.Held(error, acc)]
      }
    None =>
      [@engine.Pending([@engine.pend_value(self.ty.name(), self.name)], acc)]
  }
}

///|
pub fn separated_arg(
  name : String,
  separator : String?,
  ty : &@engine.TypeExt,
  int_round : @engine.RoundMode,
  allow_base_prefix : Bool,
  bool_config : @engine.BoolConfig,
  piece_filters : Array[@engine.FilterSpelling],
  merge : Bool,
) -> @engine.Node {
  @engine.Ext(
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
    as &@engine.NodeExt,
  )
}

///|
priv struct NumberArgExt {
  name : String
  allow_base_prefix : Bool
  piece_filters : Array[@engine.FilterSpelling]
}

///|
impl @engine.NodeExt for NumberArgExt with fn kind(_self) {
  "builtin/number"
}

///|
impl @engine.NodeExt for NumberArgExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for NumberArgExt with fn encode(self) {
  [
    self.name.to_json(),
    self.allow_base_prefix.to_json(),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl @engine.NodeExt for NumberArgExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for NumberArgExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @engine.apply_piece_filters(ctx.extensions(), self.piece_filters, token) {
        Ok(value) =>
          // Every number-lexicon rejection reports through @engine.pe_parse.
          match parse_number(value, allow_base_prefix=self.allow_base_prefix) {
            Some(number) =>
              next(
                ctx,
                pos + 1,
                @engine.cat(acc, [
                  @engine.mkb(
                    self.name,
                    @engine.VNum(number),
                    @engine.Cli,
                    at_pos=Some(pos),
                  ),
                ]),
              )
            None => [@engine.Held(@engine.pe_parse(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [
            @engine.Held(
              @engine.pe_filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @engine.Pending(
          [@engine.pend_value(number_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn number_arg(
  name : String,
  allow_base_prefix : Bool,
  piece_filters : Array[@engine.FilterSpelling],
) -> @engine.Node {
  @engine.Ext(
    NumberArgExt::{ name, allow_base_prefix, piece_filters } as &@engine.NodeExt,
  )
}

///|
/// Test-oriented number resident with a final maximum check. Production lowering
/// expresses the same concern through `final_filters`; this resident keeps the
/// engine contract tests independent of the closed Node enum.
priv struct FilteredNumberArgExt {
  name : String
  max : Int
}

///|
impl @engine.NodeExt for FilteredNumberArgExt with fn kind(_self) {
  "builtin/filtered-number"
}

///|
impl @engine.NodeExt for FilteredNumberArgExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for FilteredNumberArgExt with fn encode(self) {
  [self.name.to_json(), self.max.to_json()].to_json()
}

///|
impl @engine.NodeExt for FilteredNumberArgExt with fn consumes_zero_tokens(
  _self,
) {
  false
}

///|
impl @engine.NodeExt for FilteredNumberArgExt with fn eval(
  self,
  ctx,
  pos,
  acc,
  next,
) {
  match ctx.token_at(pos) {
    Some(token) =>
      match parse_number(token) {
        None => [@engine.Held(@engine.pe_parse(self.name, token, pos), acc)]
        Some(number) =>
          if number > self.max.to_double() {
            [
              @engine.Held(
                {
                  element: self.name,
                  args_pos: pos,
                  kind: @engine.KFilter,
                  reason: "too_large",
                  message: "\{self.name} value \{token} exceeds max \{self.max}",
                  path: [],
                },
                acc,
              ),
            ]
          } else {
            next(
              ctx,
              pos + 1,
              @engine.cat(acc, [
                @engine.mkb(
                  self.name,
                  @engine.VNum(number),
                  @engine.Cli,
                  at_pos=Some(pos),
                ),
              ]),
            )
          }
      }
    None =>
      [
        @engine.Pending(
          [@engine.pend_value(number_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn filtered_number_arg(name : String, max : Int) -> @engine.Node {
  @engine.Ext(FilteredNumberArgExt::{ name, max } as &@engine.NodeExt)
}

///|
priv struct FloatNodeExt {
  name : String
  piece_filters : Array[@engine.FilterSpelling]
}

///|
impl @engine.NodeExt for FloatNodeExt with fn kind(_self) {
  "builtin/float"
}

///|
impl @engine.NodeExt for FloatNodeExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for FloatNodeExt with fn encode(self) {
  [self.name.to_json(), filter_spellings_json(self.piece_filters)].to_json()
}

///|
impl @engine.NodeExt for FloatNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for FloatNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @engine.apply_piece_filters(ctx.extensions(), self.piece_filters, token) {
        Ok(value) =>
          // The wider float lexicon still reports lexical rejection through @engine.pe_parse.
          match parse_float(value) {
            Some(number) =>
              next(
                ctx,
                pos + 1,
                @engine.cat(acc, [
                  @engine.mkb(
                    self.name,
                    @engine.VNum(number),
                    @engine.Cli,
                    at_pos=Some(pos),
                  ),
                ]),
              )
            None => [@engine.Held(@engine.pe_parse(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [
            @engine.Held(
              @engine.pe_filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @engine.Pending(
          [@engine.pend_value(float_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn float_arg(
  name : String,
  piece_filters : Array[@engine.FilterSpelling],
) -> @engine.Node {
  @engine.Ext(FloatNodeExt::{ name, piece_filters } as &@engine.NodeExt)
}

///|
priv struct IntNodeExt {
  name : String
  int_round : @engine.RoundMode
  allow_base_prefix : Bool
  piece_filters : Array[@engine.FilterSpelling]
}

///|
impl @engine.NodeExt for IntNodeExt with fn kind(_self) {
  "builtin/int"
}

///|
impl @engine.NodeExt for IntNodeExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for IntNodeExt with fn encode(self) {
  [
    self.name.to_json(),
    round_mode_json(self.int_round),
    self.allow_base_prefix.to_json(),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl @engine.NodeExt for IntNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for IntNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @engine.apply_piece_filters(ctx.extensions(), self.piece_filters, token) {
        Ok(value) =>
          // int resident has three distinct @engine.Held families; preserving this split is
          // part of the resident contract, not a generic number error path.
          match
            parse_int_value(
              value,
              self.int_round,
              allow_base_prefix=self.allow_base_prefix,
            ) {
            Ok(integer) =>
              next(
                ctx,
                pos + 1,
                @engine.cat(acc, [
                  @engine.mkb(
                    self.name,
                    @engine.VNum(integer.to_double()),
                    @engine.Cli,
                    at_pos=Some(pos),
                  ),
                ]),
              )
            Err(@engine.NotAnInteger) =>
              [@engine.Held(@engine.pe_parse_int(self.name, value, pos), acc)]
            Err(@engine.IntOutOfRange) =>
              [
                @engine.Held(
                  @engine.pe_int_out_of_range(self.name, value, pos),
                  acc,
                ),
              ]
            Err(@engine.NotANumber)
            | Err(@engine.NotABool)
            | Err(@engine.NoValueSpace) =>
              [@engine.Held(@engine.pe_parse(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [
            @engine.Held(
              @engine.pe_filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [@engine.Pending([@engine.pend_value(int_type().name(), self.name)], acc)]
  }
}

///|
pub fn int_arg(
  name : String,
  int_round : @engine.RoundMode,
  allow_base_prefix : Bool,
  piece_filters : Array[@engine.FilterSpelling],
) -> @engine.Node {
  @engine.Ext(
    IntNodeExt::{ name, int_round, allow_base_prefix, piece_filters }
    as &@engine.NodeExt,
  )
}

///|
priv struct BoolNodeExt {
  name : String
  bool_config : @engine.BoolConfig
  piece_filters : Array[@engine.FilterSpelling]
}

///|
impl @engine.NodeExt for BoolNodeExt with fn kind(_self) {
  "builtin/bool"
}

///|
impl @engine.NodeExt for BoolNodeExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for BoolNodeExt with fn encode(self) {
  [
    self.name.to_json(),
    bool_config_json(self.bool_config),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl @engine.NodeExt for BoolNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for BoolNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @engine.apply_piece_filters(ctx.extensions(), self.piece_filters, token) {
        Ok(value) =>
          // bool resident retains @engine.pe_parse_bool rather than sharing number's @engine.pe_parse.
          match parse_bool(value, config=self.bool_config) {
            Some(boolean) =>
              next(
                ctx,
                pos + 1,
                @engine.cat(acc, [
                  @engine.mkb(
                    self.name,
                    @engine.VBool(boolean),
                    @engine.Cli,
                    at_pos=Some(pos),
                  ),
                ]),
              )
            None =>
              [@engine.Held(@engine.pe_parse_bool(self.name, value, pos), acc)]
          }
        Err((reason, message)) =>
          [
            @engine.Held(
              @engine.pe_filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @engine.Pending(
          [@engine.pend_value(bool_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn bool_arg(
  name : String,
  bool_config : @engine.BoolConfig,
  piece_filters : Array[@engine.FilterSpelling],
) -> @engine.Node {
  @engine.Ext(
    BoolNodeExt::{ name, bool_config, piece_filters } as &@engine.NodeExt,
  )
}

///|
priv struct TypedNodeExt {
  name : String
  ty : &@engine.TypeExt
  piece_filters : Array[@engine.FilterSpelling]
}

///|
impl @engine.NodeExt for TypedNodeExt with fn kind(_self) {
  "builtin/typed"
}

///|
impl @engine.NodeExt for TypedNodeExt with fn element_name(self) {
  Some(self.name)
}

///|
impl @engine.NodeExt for TypedNodeExt with fn encode(self) {
  [
    self.name.to_json(),
    self.ty.name().to_json(),
    self.ty.encode(),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl @engine.NodeExt for TypedNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl @engine.NodeExt for TypedNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @engine.apply_piece_filters(ctx.extensions(), self.piece_filters, token) {
        Ok(value) =>
          match self.ty.parse_token(value) {
            Ok(parsed) =>
              next(
                ctx,
                pos + 1,
                @engine.cat(acc, [
                  @engine.mkb(self.name, parsed, @engine.Cli, at_pos=Some(pos)),
                ]),
              )
            Err(failure) =>
              [
                @engine.Held(
                  @engine.pe_type_parse(self.name, value, pos, failure),
                  acc,
                ),
              ]
          }
        Err((reason, message)) =>
          [
            @engine.Held(
              @engine.pe_filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [@engine.Pending([@engine.pend_value(self.ty.name(), self.name)], acc)]
  }
}

///|
pub fn typed_arg(
  name : String,
  ty : &@engine.TypeExt,
  piece_filters : Array[@engine.FilterSpelling],
) -> @engine.Node {
  @engine.Ext(TypedNodeExt::{ name, ty, piece_filters } as &@engine.NodeExt)
}

///|
priv struct EffectMarkExt {
  name : String
  op : @engine.EffectOp
}

///|
impl @engine.NodeExt for EffectMarkExt with fn kind(_self) {
  "builtin/effect"
}

///|
impl @engine.NodeExt for EffectMarkExt with fn effect_mark(self) {
  Some((self.name, self.op))
}

///|
impl @engine.NodeExt for EffectMarkExt with fn encode(self) {
  [self.name.to_json(), effect_op_json(self.op)].to_json()
}

///|
impl @engine.NodeExt for EffectMarkExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl @engine.NodeExt for EffectMarkExt with fn eval(self, ctx, pos, acc, next) {
  next(
    ctx,
    pos,
    @engine.cat(acc, [@engine.mk_eff(self.name, self.op, @engine.Cli)]),
  )
}

///|
pub fn effect_mark(name : String, op : @engine.EffectOp) -> @engine.Node {
  @engine.Ext(EffectMarkExt::{ name, op } as &@engine.NodeExt)
}

///|
priv struct DeprecationMarkExt {
  name : String
}

///|
impl @engine.NodeExt for DeprecationMarkExt with fn kind(_self) {
  "builtin/deprecation"
}

///|
impl @engine.NodeExt for DeprecationMarkExt with fn encode(self) {
  [self.name.to_json()].to_json()
}

///|
impl @engine.NodeExt for DeprecationMarkExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl @engine.NodeExt for DeprecationMarkExt with fn eval(
  self,
  ctx,
  pos,
  acc,
  next,
) {
  next(ctx, pos, @engine.cat(acc, [@engine.depr_marker(self.name)]))
}

///|
pub fn deprecation_mark(name : String) -> @engine.Node {
  @engine.Ext(DeprecationMarkExt::{ name, } as &@engine.NodeExt)
}

///|
priv struct FailureMarkExt {
  name : String
}

///|
impl @engine.NodeExt for FailureMarkExt with fn kind(_self) {
  "builtin/failure"
}

///|
impl @engine.NodeExt for FailureMarkExt with fn is_failure_action(_self) {
  true
}

///|
impl @engine.NodeExt for FailureMarkExt with fn encode(self) {
  [self.name.to_json()].to_json()
}

///|
impl @engine.NodeExt for FailureMarkExt with fn consumes_zero_tokens(_self) {
  true
}

///|
impl @engine.NodeExt for FailureMarkExt with fn eval(self, ctx, pos, acc, next) {
  next(ctx, pos, @engine.cat(acc, [@engine.action_marker(self.name, pos)]))
}

///|
pub fn failure_mark(name : String) -> @engine.Node {
  @engine.Ext(FailureMarkExt::{ name, } as &@engine.NodeExt)
}

///|
pub fn node_resident_name(node : @engine.Node) -> String? {
  guard node is @engine.Ext(extension) else { return None }
  extension.element_name()
}
