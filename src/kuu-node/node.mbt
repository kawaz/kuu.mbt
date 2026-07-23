///|
/// Opaque node handle. Nodes can be constructed but not decomposed outside the evaluator.
pub using @engine {type Node}

///|
pub fn exact(spelling : String) -> Node {
  @engine.Exact(spelling)
}

///|
pub fn bind(name : String, value : @abi.Value) -> Node {
  @engine.Bind(name, value)
}

///|
pub fn seq(nodes : Array[Node]) -> Node {
  @engine.Seq(nodes)
}

///|
pub fn or(nodes : Array[Node]) -> Node {
  @engine.Or(nodes)
}

///|
pub fn ext_node(extension : &@extension.NodeExt) -> Node {
  @engine.Ext(extension)
}

///|
pub fn string_arg(name : String, filters : Array[@abi.FnInvocation]) -> Node {
  @engine.string_arg(name, filters)
}

///|
pub fn kv_arg(name : String, filters : Array[@abi.FnInvocation]) -> Node {
  @engine.kv_arg(name, filters)
}

///|
pub fn separated_arg(
  name : String,
  separator : String?,
  ty : &@extension.TypeExt,
  int_round : @abi.RoundMode,
  bool_config : @abi.BoolConfig,
  filters : Array[@abi.FnInvocation],
  allow_base_prefix? : Bool = false,
  merge? : Bool = false,
) -> Node {
  @engine.separated_arg(
    name,
    separator,
    ty,
    int_round,
    bool_config,
    filters,
    allow_base_prefix~,
    merge~,
  )
}

///|
pub fn number_arg(
  name : String,
  filters : Array[@abi.FnInvocation],
  allow_base_prefix? : Bool = false,
) -> Node {
  @engine.number_arg(name, filters, allow_base_prefix~)
}

///|
pub fn filtered_number_arg(name : String, maximum : Int) -> Node {
  @engine.filtered_number_arg(name, maximum)
}

///|
pub fn float_arg(name : String, filters : Array[@abi.FnInvocation]) -> Node {
  @engine.float_arg(name, filters)
}

///|
pub fn int_arg(
  name : String,
  round : @abi.RoundMode,
  filters : Array[@abi.FnInvocation],
  allow_base_prefix? : Bool = false,
) -> Node {
  @engine.int_arg(name, round, filters, allow_base_prefix~)
}

///|
pub fn bool_arg(
  name : String,
  config : @abi.BoolConfig,
  filters : Array[@abi.FnInvocation],
) -> Node {
  @engine.bool_arg(name, config, filters)
}

///|
pub fn typed_arg(
  name : String,
  ty : &@extension.TypeExt,
  filters : Array[@abi.FnInvocation],
) -> Node {
  @engine.typed_arg(name, ty, filters)
}

///|
pub fn effect_mark(name : String, op : @abi.EffectOp) -> Node {
  @engine.effect_mark(name, op)
}

///|
pub fn deprecation_mark(name : String) -> Node {
  @engine.deprecation_mark(name)
}

///|
pub fn failure_mark(name : String) -> Node {
  @engine.failure_mark(name)
}

///|
pub fn enum_value_node(
  name : String,
  ty : &@extension.TypeExt,
  values : Array[String],
) -> Node {
  @engine.enum_value_node(name, ty, values)
}
