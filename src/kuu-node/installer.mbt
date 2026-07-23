///|
pub using @engine {
  type InstallBuilder,
  type InstallOutput,
  type InstallChild,
  type DefsView,
  type Definition,
  type Scope,
  type LoweredDefinition,
}

///|
pub(open) trait InstallerExt {
  fn vocab(Self) -> Array[String]
  fn decode(Self, Json, @abi.DecodeCtx) -> Result[
    @abi.DecodedOwnedDeclaration,
    String,
  ]
  fn apply(Self, InstallBuilder) -> Unit
  fn collect_defs_errors(Self, DefsView) -> Array[@abi.DefError]
}

///|
/// Registerable installer collection paired with the evaluator extension registry.
pub struct Registry {
  priv extensions_ : @extension.Registry
  priv installers_ : Array[&InstallerExt]
}

///|
pub fn Registry::new() -> Registry {
  { extensions_: @extension.Registry::new(), installers_: [] }
}

///|
pub fn Registry::extensions(self : Registry) -> @extension.Registry {
  self.extensions_
}

///|
pub fn Registry::register_installer(
  self : Registry,
  installer : &InstallerExt,
) -> Unit {
  self.installers_.push(installer)
}

///|
pub fn Registry::installers(self : Registry) -> Array[&InstallerExt] {
  self.installers_.copy()
}

///|
pub fn Registry::register_node(
  self : Registry,
  value : &@extension.NodeExt,
) -> Bool {
  self.extensions_.register_node(value)
}

///|
pub fn Registry::lookup_node(
  self : Registry,
  name : String,
) -> &@extension.NodeExt? {
  self.extensions_.lookup_node(name)
}

///|
pub fn Registry::register_matcher(
  self : Registry,
  value : &@extension.MatcherExt,
) -> Bool {
  self.extensions_.register_matcher(value)
}

///|
pub fn Registry::lookup_matcher(
  self : Registry,
  name : String,
) -> &@extension.MatcherExt? {
  self.extensions_.lookup_matcher(name)
}

///|
pub fn Registry::register_type(
  self : Registry,
  value : &@extension.TypeExt,
) -> Bool {
  self.extensions_.register_type(value)
}

///|
pub fn Registry::lookup_type(
  self : Registry,
  name : String,
) -> &@extension.TypeExt? {
  self.extensions_.lookup_type(name)
}

///|
pub fn Registry::register_accumulator(
  self : Registry,
  value : &@extension.AccumulatorExt,
) -> Bool {
  self.extensions_.register_accumulator(value)
}

///|
pub fn Registry::lookup_accumulator(
  self : Registry,
  name : String,
) -> &@extension.AccumulatorExt? {
  self.extensions_.lookup_accumulator(name)
}

///|
pub fn Registry::register_collector(
  self : Registry,
  value : &@extension.CollectorExt,
) -> Bool {
  self.extensions_.register_collector(value)
}

///|
pub fn Registry::lookup_collector(
  self : Registry,
  name : String,
) -> &@extension.CollectorExt? {
  self.extensions_.lookup_collector(name)
}

///|
pub fn Registry::register_filter(
  self : Registry,
  value : @extension.FilterDescriptor,
) -> Bool {
  self.extensions_.register_filter(value)
}

///|
pub fn Registry::lookup_filter(
  self : Registry,
  name : String,
) -> @extension.FilterDescriptor? {
  self.extensions_.lookup_filter(name)
}

///|
pub fn Registry::register_array_filter(
  self : Registry,
  value : @extension.ArrayFilterDescriptor,
) -> Bool {
  self.extensions_.register_array_filter(value)
}

///|
pub fn Registry::lookup_array_filter(
  self : Registry,
  name : String,
) -> @extension.ArrayFilterDescriptor? {
  self.extensions_.lookup_array_filter(name)
}

///|
pub fn Registry::register_cell_fn(
  self : Registry,
  value : @extension.CellFnDescriptor,
) -> Bool {
  self.extensions_.register_cell_fn(value)
}

///|
pub fn Registry::lookup_cell_fn(
  self : Registry,
  name : String,
) -> @extension.CellFnDescriptor? {
  self.extensions_.lookup_cell_fn(name)
}

///|
pub fn Registry::register_completer(
  self : Registry,
  value : &@extension.CompleterExt,
) -> Bool {
  self.extensions_.register_completer(value)
}

///|
pub fn Registry::lookup_completer(
  self : Registry,
  name : String,
) -> &@extension.CompleterExt? {
  self.extensions_.lookup_completer(name)
}

///|
pub fn Registry::register_capability(
  self : Registry,
  value : &@extension.CapabilityExt,
) -> Bool {
  self.extensions_.register_capability(value)
}

///|
pub fn Registry::lookup_capability(
  self : Registry,
  name : String,
) -> &@extension.CapabilityExt? {
  self.extensions_.lookup_capability(name)
}

///|
pub fn builder_apply_builtin(builder : InstallBuilder, kind : String) -> Unit {
  @engine.apply_builtin_installer(kind, builder)
}

///|
pub fn defs_builtin_errors(
  view : DefsView,
  kind : String,
) -> Array[@abi.DefError] {
  @engine.collect_builtin_installer_errors(kind, view)
}

///|
pub fn builder_definition_names(builder : InstallBuilder) -> Array[String] {
  let names : Array[String] = []
  for element in builder.definition().options {
    names.push(element.name)
  }
  for element in builder.definition().positionals {
    names.push(element.name)
  }
  names
}

///|
pub fn builder_plant(builder : InstallBuilder, node : Node) -> Unit {
  builder.output().push_greedy(node)
}

///|
pub fn output_new(positional : Array[Node]) -> InstallOutput {
  @engine.InstallOutput::new(positional)
}

///|
pub fn output_push_greedy(output : InstallOutput, node : Node) -> Unit {
  output.push_greedy(node)
}

///|
fn installer_plan(installers : Array[&InstallerExt]) -> @engine.InstallerPlan {
  let vocabularies : Array[Array[String]] = []
  let apply_steps : Array[(InstallBuilder) -> Unit] = []
  let check_steps : Array[(DefsView) -> Array[@abi.DefError]] = []
  for installer in installers {
    let resident = installer
    vocabularies.push(resident.vocab())
    apply_steps.push(fn(builder) { resident.apply(builder) })
    check_steps.push(fn(view) { resident.collect_defs_errors(view) })
  }
  @engine.InstallerPlan::new(vocabularies, apply_steps, check_steps)
}

///|
pub fn lower_definition(
  definition : Definition,
  installers : Array[&InstallerExt],
  extensions : @extension.Registry,
  registry? : Map[String, Node] = Map([]),
) -> Result[Scope, Array[@abi.DefError]] {
  @engine.lower_definition(
    definition,
    installer_plan(installers),
    extensions,
    registry~,
  )
}

///|
pub fn lower_definition_snapshot(
  definition : Definition,
  installers : Array[&InstallerExt],
  extensions : @extension.Registry,
  registry? : Map[String, Node] = Map([]),
) -> Result[LoweredDefinition, Array[@abi.DefError]] {
  @engine.lower_definition_snapshot(
    definition,
    installer_plan(installers),
    extensions,
    registry~,
  )
}
