// node_residents.mbt — concrete open-node residents for builtin value and marker semantics.

///|
fn filter_spellings_json(filters : Array[@abi.FnInvocation]) -> Json {
  let encoded : Array[Json] = []
  for filter in filters {
    encoded.push([filter.name.to_json(), filter.args.to_json()].to_json())
  }
  encoded.to_json()
}

///|
fn ty_json(ty : &@extension.TypeExt) -> Json {
  ty.name().to_json()
}

///|
fn round_mode_json(mode : @abi.RoundMode) -> Json {
  let name = match mode {
    @abi.Floor => "floor"
    @abi.Ceil => "ceil"
    @abi.Trunc => "trunc"
    @abi.Away => "away"
    @abi.HalfFloor => "half_floor"
    @abi.HalfCeil => "half_ceil"
    @abi.HalfTrunc => "half_trunc"
    @abi.HalfAway => "half_away"
    @abi.HalfEven => "half_even"
    @abi.Error => "error"
  }
  name.to_json()
}

///|
fn bool_config_json(config : @abi.BoolConfig) -> Json {
  [
    config.true_values.to_json(),
    config.false_values.to_json(),
    config.case_insensitive.to_json(),
  ].to_json()
}

///|
fn effect_op_json(op : @abi.EffectOp) -> Json {
  match op {
    @abi.Set => ["set".to_json()].to_json()
    @abi.Default => ["default".to_json()].to_json()
    @abi.Unset => ["unset".to_json()].to_json()
    @abi.Empty => ["empty".to_json()].to_json()
    @abi.Invoke(invocation) =>
      ["fn".to_json(), invocation.name.to_json(), invocation.args.to_json()].to_json()
    @abi.Remove => ["remove".to_json()].to_json()
    @abi.Splice => ["splice".to_json()].to_json()
  }
}

///|
priv struct StringArgExt {
  name : String
  piece_filters : Array[@abi.FnInvocation]
}

///|
impl NodeExt for StringArgExt with fn kind(_self) {
  "builtin/string"
}

///|
impl NodeExt for StringArgExt with fn element_name(self) {
  Some(self.name)
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
      match
        @extension.apply_piece_filters(
          ctx.extensions(),
          self.piece_filters,
          token,
        ) {
        Ok(value) =>
          next(
            ctx,
            pos + 1,
            acc +
            [
              @abi.Binding::new(
                self.name,
                @abi.String(value),
                @abi.Cli,
                at_pos=Some(pos),
              ),
            ],
          )
        Err({ reason, message }) =>
          [
            @abi.Held(
              @abi.ParseError::filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(string_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn string_arg(
  name : String,
  piece_filters : Array[@abi.FnInvocation],
) -> Node {
  Ext(StringArgExt::{ name, piece_filters } as &NodeExt)
}

///|
priv struct KvNodeExt {
  name : String
  piece_filters : Array[@abi.FnInvocation]
}

///|
impl NodeExt for KvNodeExt with fn kind(_self) {
  "builtin/kv"
}

///|
impl NodeExt for KvNodeExt with fn element_name(self) {
  Some(self.name)
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
      match
        @extension.apply_piece_filters(
          ctx.extensions(),
          self.piece_filters,
          token,
        ) {
        Ok(value) =>
          // DR-091 §2: piece filters run first, then the dedicated
          // contains-equals gate reports through the parse_error_not_a_kv_pair @abi.Held family.
          if value.contains("=") {
            next(
              ctx,
              pos + 1,
              acc +
              [
                @abi.Binding::new(
                  self.name,
                  @abi.String(value),
                  @abi.Cli,
                  at_pos=Some(pos),
                ),
              ],
            )
          } else {
            [@abi.Held(parse_error_not_a_kv_pair(self.name, value, pos), acc)]
          }
        Err({ reason, message }) =>
          [
            @abi.Held(
              @abi.ParseError::filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(string_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn kv_arg(name : String, piece_filters : Array[@abi.FnInvocation]) -> Node {
  Ext(KvNodeExt::{ name, piece_filters } as &NodeExt)
}

///|
priv struct SeparatedNodeExt {
  name : String
  separator : String?
  ty : &@extension.TypeExt
  int_round : @abi.RoundMode
  allow_base_prefix : Bool
  bool_config : @abi.BoolConfig
  piece_filters : Array[@abi.FnInvocation]
  merge : Bool
}

///|
impl NodeExt for SeparatedNodeExt with fn kind(_self) {
  "builtin/separated"
}

///|
impl NodeExt for SeparatedNodeExt with fn element_name(self) {
  Some(self.name)
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
          self.piece_filters,
          pos,
          self.merge,
          ctx.extensions(),
        ) {
        Ok(bindings) => next(ctx, pos + 1, acc + bindings)
        Err(error) => [@abi.Held(error, acc)]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(self.ty.name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn separated_arg(
  name : String,
  separator : String?,
  ty : &@extension.TypeExt,
  int_round : @abi.RoundMode,
  bool_config : @abi.BoolConfig,
  piece_filters : Array[@abi.FnInvocation],
  allow_base_prefix? : Bool = false,
  merge? : Bool = false,
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
  piece_filters : Array[@abi.FnInvocation]
}

///|
impl NodeExt for NumberArgExt with fn kind(_self) {
  "builtin/number"
}

///|
impl NodeExt for NumberArgExt with fn element_name(self) {
  Some(self.name)
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
      match
        @extension.apply_piece_filters(
          ctx.extensions(),
          self.piece_filters,
          token,
        ) {
        Ok(value) =>
          // Every number-lexicon rejection reports through parse_error_not_a_number.
          match parse_number(value, allow_base_prefix=self.allow_base_prefix) {
            Some(number) =>
              next(
                ctx,
                pos + 1,
                acc +
                [
                  @abi.Binding::new(
                    self.name,
                    @abi.Number(number),
                    @abi.Cli,
                    at_pos=Some(pos),
                  ),
                ],
              )
            None =>
              [@abi.Held(parse_error_not_a_number(self.name, value, pos), acc)]
          }
        Err({ reason, message }) =>
          [
            @abi.Held(
              @abi.ParseError::filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(number_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn number_arg(
  name : String,
  piece_filters : Array[@abi.FnInvocation],
  allow_base_prefix? : Bool = false,
) -> Node {
  Ext(NumberArgExt::{ name, allow_base_prefix, piece_filters } as &NodeExt)
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
impl NodeExt for FilteredNumberArgExt with fn kind(_self) {
  "builtin/filtered-number"
}

///|
impl NodeExt for FilteredNumberArgExt with fn element_name(self) {
  Some(self.name)
}

///|
impl NodeExt for FilteredNumberArgExt with fn encode(self) {
  [self.name.to_json(), self.max.to_json()].to_json()
}

///|
impl NodeExt for FilteredNumberArgExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for FilteredNumberArgExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match parse_number(token) {
        None =>
          [@abi.Held(parse_error_not_a_number(self.name, token, pos), acc)]
        Some(number) =>
          if number > self.max.to_double() {
            [
              @abi.Held(
                {
                  element: self.name,
                  args_pos: pos,
                  kind: @abi.Filter,
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
              acc +
              [
                @abi.Binding::new(
                  self.name,
                  @abi.Number(number),
                  @abi.Cli,
                  at_pos=Some(pos),
                ),
              ],
            )
          }
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(number_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn filtered_number_arg(name : String, max : Int) -> Node {
  Ext(FilteredNumberArgExt::{ name, max } as &NodeExt)
}

///|
priv struct FloatNodeExt {
  name : String
  piece_filters : Array[@abi.FnInvocation]
}

///|
impl NodeExt for FloatNodeExt with fn kind(_self) {
  "builtin/float"
}

///|
impl NodeExt for FloatNodeExt with fn element_name(self) {
  Some(self.name)
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
      match
        @extension.apply_piece_filters(
          ctx.extensions(),
          self.piece_filters,
          token,
        ) {
        Ok(value) =>
          // The wider float lexicon still reports lexical rejection through parse_error_not_a_number.
          match parse_float(value) {
            Some(number) =>
              next(
                ctx,
                pos + 1,
                acc +
                [
                  @abi.Binding::new(
                    self.name,
                    @abi.Number(number),
                    @abi.Cli,
                    at_pos=Some(pos),
                  ),
                ],
              )
            None =>
              [@abi.Held(parse_error_not_a_number(self.name, value, pos), acc)]
          }
        Err({ reason, message }) =>
          [
            @abi.Held(
              @abi.ParseError::filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(float_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn float_arg(
  name : String,
  piece_filters : Array[@abi.FnInvocation],
) -> Node {
  Ext(FloatNodeExt::{ name, piece_filters } as &NodeExt)
}

///|
priv struct IntNodeExt {
  name : String
  int_round : @abi.RoundMode
  allow_base_prefix : Bool
  piece_filters : Array[@abi.FnInvocation]
}

///|
impl NodeExt for IntNodeExt with fn kind(_self) {
  "builtin/int"
}

///|
impl NodeExt for IntNodeExt with fn element_name(self) {
  Some(self.name)
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
      match
        @extension.apply_piece_filters(
          ctx.extensions(),
          self.piece_filters,
          token,
        ) {
        Ok(value) =>
          // int resident has three distinct @abi.Held families; preserving this split is
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
                acc +
                [
                  @abi.Binding::new(
                    self.name,
                    @abi.Number(integer.to_double()),
                    @abi.Cli,
                    at_pos=Some(pos),
                  ),
                ],
              )
            Err(failure) =>
              [@abi.Held(type_parse_error(self.name, pos, failure), acc)]
          }
        Err({ reason, message }) =>
          [
            @abi.Held(
              @abi.ParseError::filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(int_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn int_arg(
  name : String,
  int_round : @abi.RoundMode,
  piece_filters : Array[@abi.FnInvocation],
  allow_base_prefix? : Bool = false,
) -> Node {
  Ext(
    IntNodeExt::{ name, int_round, allow_base_prefix, piece_filters }
    as &NodeExt,
  )
}

///|
priv struct BoolNodeExt {
  name : String
  bool_config : @abi.BoolConfig
  piece_filters : Array[@abi.FnInvocation]
}

///|
impl NodeExt for BoolNodeExt with fn kind(_self) {
  "builtin/bool"
}

///|
impl NodeExt for BoolNodeExt with fn element_name(self) {
  Some(self.name)
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
      match
        @extension.apply_piece_filters(
          ctx.extensions(),
          self.piece_filters,
          token,
        ) {
        Ok(value) =>
          // bool resident retains parse_error_not_a_bool rather than sharing number's parse_error_not_a_number.
          match parse_bool(value, config=self.bool_config) {
            Some(boolean) =>
              next(
                ctx,
                pos + 1,
                acc +
                [
                  @abi.Binding::new(
                    self.name,
                    @abi.Bool(boolean),
                    @abi.Cli,
                    at_pos=Some(pos),
                  ),
                ],
              )
            None =>
              [@abi.Held(parse_error_not_a_bool(self.name, value, pos), acc)]
          }
        Err({ reason, message }) =>
          [
            @abi.Held(
              @abi.ParseError::filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(bool_type().name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn bool_arg(
  name : String,
  bool_config : @abi.BoolConfig,
  piece_filters : Array[@abi.FnInvocation],
) -> Node {
  Ext(BoolNodeExt::{ name, bool_config, piece_filters } as &NodeExt)
}

///|
priv struct TypedNodeExt {
  name : String
  ty : &@extension.TypeExt
  piece_filters : Array[@abi.FnInvocation]
}

///|
impl NodeExt for TypedNodeExt with fn kind(_self) {
  "builtin/typed"
}

///|
impl NodeExt for TypedNodeExt with fn element_name(self) {
  Some(self.name)
}

///|
impl NodeExt for TypedNodeExt with fn encode(self) {
  [
    self.name.to_json(),
    self.ty.name().to_json(),
    self.ty.encode(),
    filter_spellings_json(self.piece_filters),
  ].to_json()
}

///|
impl NodeExt for TypedNodeExt with fn consumes_zero_tokens(_self) {
  false
}

///|
impl NodeExt for TypedNodeExt with fn eval(self, ctx, pos, acc, next) {
  match ctx.token_at(pos) {
    Some(token) =>
      match
        @extension.apply_piece_filters(
          ctx.extensions(),
          self.piece_filters,
          token,
        ) {
        Ok(value) =>
          match self.ty.parse_token(value) {
            Ok(parsed) =>
              next(
                ctx,
                pos + 1,
                acc +
                [
                  @abi.Binding::new(
                    self.name,
                    parsed,
                    @abi.Cli,
                    at_pos=Some(pos),
                  ),
                ],
              )
            Err(failure) =>
              [@abi.Held(type_parse_error(self.name, pos, failure), acc)]
          }
        Err({ reason, message }) =>
          [
            @abi.Held(
              @abi.ParseError::filter(self.name, pos, reason, message),
              acc,
            ),
          ]
      }
    None =>
      [
        @abi.Pending(
          [@abi.Candidate::pending_value(self.ty.name(), self.name)],
          acc,
        ),
      ]
  }
}

///|
pub fn typed_arg(
  name : String,
  ty : &@extension.TypeExt,
  piece_filters : Array[@abi.FnInvocation],
) -> Node {
  Ext(TypedNodeExt::{ name, ty, piece_filters } as &NodeExt)
}

///|
priv struct EffectMarkExt {
  name : String
  op : @abi.EffectOp
}

///|
impl NodeExt for EffectMarkExt with fn kind(_self) {
  "builtin/effect"
}

///|
impl NodeExt for EffectMarkExt with fn effect_mark(self) {
  Some((self.name, self.op))
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
  next(ctx, pos, acc + [@abi.Binding::effect(self.name, self.op, @abi.Cli)])
}

///|
pub fn effect_mark(name : String, op : @abi.EffectOp) -> Node {
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
  next(ctx, pos, acc + [@abi.Binding::deprecation_mark(self.name)])
}

///|
pub fn deprecation_mark(name : String) -> Node {
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
impl NodeExt for FailureMarkExt with fn is_failure_action(_self) {
  true
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
  next(ctx, pos, acc + [@abi.Binding::action_marker(self.name, pos)])
}

///|
pub fn failure_mark(name : String) -> Node {
  Ext(FailureMarkExt::{ name, } as &NodeExt)
}
