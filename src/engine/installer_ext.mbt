// installer_ext.mbt — open installer contract and opaque lowering capabilities.

///|
pub struct DefsView {
  priv source_definition : Definition
  priv definition : Definition
  priv templates : Map[String, Node]
  priv extensions_ : Registry
}

///|
pub fn DefsView::new(
  source_definition : Definition,
  definition : Definition,
  templates : Map[String, Node],
  extensions : Registry,
) -> DefsView {
  { source_definition, definition, templates, extensions_: extensions }
}

///|
pub fn DefsView::source_definition(self : DefsView) -> Definition {
  self.source_definition
}

///|
pub fn DefsView::definition(self : DefsView) -> Definition {
  self.definition
}

///|
pub fn DefsView::templates(self : DefsView) -> Map[String, Node] {
  self.templates
}

///|
pub fn DefsView::extensions(self : DefsView) -> Registry {
  self.extensions_
}

///|
pub struct InstallOutput {
  priv greedy : Array[Node]
  priv entities : Array[Entity]
  priv positional : Array[Node]
  priv constraints : Array[Constraint]
}

///|
pub fn InstallOutput::new(positional : Array[Node]) -> InstallOutput {
  { greedy: [], entities: [], positional, constraints: [] }
}

///|
pub fn InstallOutput::greedy(self : InstallOutput) -> Array[Node] {
  self.greedy
}

///|
pub fn InstallOutput::entities(self : InstallOutput) -> Array[Entity] {
  self.entities
}

///|
pub fn InstallOutput::positional(self : InstallOutput) -> Array[Node] {
  self.positional
}

///|
pub fn InstallOutput::constraints(self : InstallOutput) -> Array[Constraint] {
  self.constraints
}

///|
pub fn InstallOutput::push_greedy(self : InstallOutput, node : Node) -> Unit {
  self.greedy.push(node)
}

///|
pub fn InstallOutput::push_entity(
  self : InstallOutput,
  entity : Entity,
) -> Unit {
  self.entities.push(entity)
}

///|
pub fn InstallOutput::push_constraint(
  self : InstallOutput,
  constraint : Constraint,
) -> Unit {
  self.constraints.push(constraint)
}

///|
pub struct InstallChild {
  priv name : String
  priv body : InstallBuilder
}

///|
pub fn InstallChild::new(name : String, body : InstallBuilder) -> InstallChild {
  { name, body }
}

///|
pub fn InstallChild::name(self : InstallChild) -> String {
  self.name
}

///|
pub fn InstallChild::body(self : InstallChild) -> InstallBuilder {
  self.body
}

///|
pub struct InstallBuilder {
  priv definition : Definition
  priv output : InstallOutput
  priv children : Array[InstallChild]
  priv templates : Map[String, Node]
  priv extensions : Registry
}

///|
pub fn InstallBuilder::new(
  definition : Definition,
  output : InstallOutput,
  children : Array[InstallChild],
  templates : Map[String, Node],
  extensions : Registry,
) -> InstallBuilder {
  { definition, output, children, templates, extensions }
}

///|
pub fn InstallBuilder::definition(self : InstallBuilder) -> Definition {
  self.definition
}

///|
pub fn InstallBuilder::output(self : InstallBuilder) -> InstallOutput {
  self.output
}

///|
pub fn InstallBuilder::children(self : InstallBuilder) -> Array[InstallChild] {
  self.children
}

///|
pub fn InstallBuilder::templates(self : InstallBuilder) -> Map[String, Node] {
  self.templates
}

///|
pub fn InstallBuilder::extensions(self : InstallBuilder) -> Registry {
  self.extensions
}

///|
pub(all) enum DecodeCtx {
  Option
  Positional
  Command
} derive(Eq, Debug)

///|
pub(all) enum OwnedDeclaration {
  Long(LongDeclaration)
  Short(Array[Char])
  Env(Array[String])
  Dd(String?, Bool)
  Global(Bool)
  Inherit(Bool)
  Repeat(RepeatSpec?, Bool)
  Multiple(Bool, String?, CollectorDeclaration?, String?, Bool?)
  Config(Bool, Array[String]?)
  Constraint(Array[String], Array[String], Array[String], Array[String], Bool)
  Alias(AliasDef?)
  Inheritable(Bool)
  HelpMeta(HelpMetaDeclaration)
  Command
} derive(Eq, Debug)

///|
pub(all) struct DecodedOwnedDeclaration {
  vocab : Array[String]
  declaration : OwnedDeclaration
}

///|
pub(open) trait InstallerExt {
  fn vocab(Self) -> Array[String]
  fn decode(Self, Json, DecodeCtx) -> Result[DecodedOwnedDeclaration, String]
  fn apply(Self, InstallBuilder) -> Unit
  fn collect_defs_errors(Self, DefsView) -> Array[DefError]
}

///|
fn InstallOutput::size(self : InstallOutput) -> Int {
  self.greedy.length() + self.entities.length() + self.constraints.length()
}

///|
fn InstallBuilder::tree_size(self : InstallBuilder) -> Int {
  let mut size = self.output.size() + self.definition.options.length()
  for child in self.children {
    size = size + child.body.tree_size()
  }
  size
}

///|
fn installer_tree_pass(
  builder : InstallBuilder,
  installers : Array[&InstallerExt],
  prepare : (InstallBuilder) -> Unit,
) -> Unit {
  prepare(builder)
  for installer in installers {
    installer.apply(builder)
  }
  for child in builder.children {
    installer_tree_pass(child.body, installers, prepare)
  }
}

///|
fn InstallBuilder::materialize(self : InstallBuilder) -> Scope {
  let greedy : Array[Node] = []
  for node in self.output.greedy {
    greedy.push(node)
  }
  for child in self.children {
    greedy.push(CommandSatisfied(child.name, child.body.materialize()))
  }
  {
    greedy,
    positional: self.output.positional,
    entities: self.output.entities,
    constraints: self.output.constraints,
  }
}

///|
fn vocab_owned(vocab : Array[String], name : String) -> Bool {
  for item in vocab {
    if item == name {
      return true
    }
  }
  false
}

///|
fn effective_repeat(element : ElementDef) -> RepeatSpec? {
  match element.repeat {
    Some(spec) => Some(spec)
    None =>
      if element.optional {
        Some({ min: 0, max: Some(1), is_lazy: false })
      } else {
        None
      }
  }
}

///|
fn long_spellings(element : ElementDef) -> Array[String] {
  match element.long {
    List(spellings) => spellings
    Forms(forms) => if forms.length() == 0 { [] } else { ["<fn-invocation>"] }
    Bool(_) => []
  }
}

///|
fn first_unknown_vocab(element : ElementDef, owned : Array[String]) -> String? {
  if long_spellings(element).length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:" + long_spellings(element)[0])
  }
  if element.variants.length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:variant:" + element.variants[0].trigger)
  }
  if element.short.length() > 0 && !vocab_owned(owned, "short") {
    return Some("short")
  }
  if element.env.length() > 0 && !vocab_owned(owned, "env") {
    return Some("env:" + element.env[0])
  }
  if element.is_dd && !vocab_owned(owned, "dd") {
    return Some("dd")
  }
  if element.is_global && !vocab_owned(owned, "global") {
    return Some("global")
  }
  if element.is_inherit && !vocab_owned(owned, "inherit") {
    return Some("inherit")
  }
  if element.is_inheritable && !vocab_owned(owned, "inheritable") {
    return Some("inheritable")
  }
  if effective_repeat(element) is Some(_) && !vocab_owned(owned, "repeat") {
    return Some("repeat")
  }
  if element.multiple && !vocab_owned(owned, "multiple") {
    return Some("multiple")
  }
  if element.is_config_file && !vocab_owned(owned, "config") {
    return Some("config:config_file")
  }
  if element.config_key is Some(_) && !vocab_owned(owned, "config") {
    return Some("config:config_key")
  }
  if element.requires.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:requires")
  }
  if element.conflicts_with.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:conflicts_with")
  }
  if element.exclusive_group.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:exclusive_group")
  }
  if element.required_group.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:required_group")
  }
  if element.value_requires.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:value_requires")
  }
  None
}

///|
fn collect_unknown_vocab(
  definition : Definition,
  owned : Array[String],
  errors : Array[DefError],
) -> Unit {
  for element in definition.options {
    match first_unknown_vocab(element, owned) {
      Some(vocab) =>
        errors.push({
          element: element.name,
          kind: UnknownVocab,
          message: "unknown special vocab '\{vocab}' — no installer claimed it",
          hint: "register an installer owning '\{vocab}' in the chain (§13.5)",
        })
      None => ()
    }
  }
  for element in definition.positionals {
    match first_unknown_vocab(element, owned) {
      Some(vocab) =>
        errors.push({
          element: element.name,
          kind: UnknownVocab,
          message: "unknown special vocab '\{vocab}' — no installer claimed it",
          hint: "register an installer owning '\{vocab}' in the chain (§13.5)",
        })
      None => ()
    }
  }
  if definition.commands.length() > 0 && !vocab_owned(owned, "command") {
    errors.push({
      element: "(commands)",
      kind: UnknownVocab,
      message: "unknown special vocab 'command'",
      hint: "register an installer owning 'command'",
    })
  }
  if definition.aliases.length() > 0 && !vocab_owned(owned, "alias") {
    errors.push({
      element: "(aliases)",
      kind: UnknownVocab,
      message: "unknown special vocab 'alias'",
      hint: "register an installer owning 'alias'",
    })
  }
  for command in definition.commands {
    collect_unknown_vocab(command.body, owned, errors)
  }
}

///|
/// Generic DR-042 checks: installer vocabulary must be disjoint and complete.
pub fn collect_installer_vocab_errors(
  definition : Definition,
  installers : Array[&InstallerExt],
) -> Array[DefError] {
  let errors : Array[DefError] = []
  let owned : Array[String] = []
  for installer in installers {
    for vocab in installer.vocab() {
      if vocab_owned(owned, vocab) {
        errors.push({
          element: vocab,
          kind: VocabIntersection,
          message: "vocab '\{vocab}' is claimed by two installers",
          hint: "remove the duplicate installer owning '\{vocab}' from the chain",
        })
      }
      owned.push(vocab)
    }
  }
  collect_unknown_vocab(definition, owned, errors)
  errors
}

///|
/// Run the monotonic installer chain to a fixed point. The caller supplies only
/// the deterministic entity preparation hook; ordering, convergence, recursion,
/// and materialization remain engine mechanisms.
pub fn run_installer_fixpoint(
  root : InstallBuilder,
  installers : Array[&InstallerExt],
  prepare : (InstallBuilder) -> Unit,
) -> Result[Scope, Array[DefError]] {
  let mut iterations = 0
  while true {
    let before = root.tree_size()
    installer_tree_pass(root, installers, prepare)
    if root.tree_size() == before {
      break
    }
    iterations = iterations + 1
    if iterations > 100 {
      return Err([
        {
          element: "(chain)",
          kind: UnknownVocab,
          message: "installer chain did not converge (> 100 iterations)",
          hint: "check for a runaway global copy or a mis-registered installer",
        },
      ])
    }
  }
  Ok(root.materialize())
}
