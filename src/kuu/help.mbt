// help.mbt — DR-112 の宣言層 help query と semantic help model。

///|
pub(all) enum HelpDepth {
  DScope
  DAll
} derive(Eq, Debug)

///|
/// DR-113 §1 の category_mode 3 分岐 (HIP-META-Q13=a): default と all は model 素材 (entry 集合)
/// が完全に同一で、値の差は renderer への表示 policy 指示にすぎない — model 側は entry を絞らない。
/// named だけが `help_group_name` が name に一致する entry と当該グループ宣言 entry に model 素材を
/// 絞る唯一の分岐。
pub(all) enum HelpCategoryMode {
  HCMDefault
  HCMAll
  HCMNamed(String)
} derive(Eq, Debug)

///|
/// DR-113 §1/§9 の query-error envelope。合法な definition に対する呼び出し側入力の失敗を
/// definition-error と別位相で返す (query-error は definition-error でなく、逆もまた然り)。
/// - `HQAbsentPath`: help_query に不在の command path を渡した
/// - `HQAbsentCategory`: help_query の category_mode `{"named": name}` に不在の名前を渡した
pub(all) enum HelpQueryError {
  HQAbsentPath
  HQAbsentCategory
} derive(Eq, Debug)

///|
/// DR-113 §1 の help_query capability carrier struct。CapabilityExt.name() で "help_query" を
/// 返し、`Registry.register_capability` 経由で engine registry へ載せる。実際の invoke ABI は
/// `pub fn help(...)` (このファイル内) で、capability 抽象は名前空間 discriminator と登録経路の
/// ためだけの薄い皮 — help_query 以外の capability が入る時のシグネチャ差を吸収するため
/// engine/capability.mbt の trait は `name()` のみを持つ (§9 の「kuu.mbt runner が capability
/// を直接呼ぶ」経路の下地)。M3c-B 段階では登録経路のみ整え、fixture runner からの invoke は
/// M4 で `Registry.lookup_capability("help_query")` 経由 dispatch へ切り替える差し替え点。
pub struct HelpQueryCapability {}

///|
pub impl @engine.CapabilityExt for HelpQueryCapability with fn name(_self) {
  "help_query"
}

///|
pub fn help_query_capability() -> &@engine.CapabilityExt {
  HelpQueryCapability::{  } as &@engine.CapabilityExt
}

///|
pub(all) enum HelpDefault {
  HDefaultScalar(@engine.Value)
  HDefaultArray(Array[@engine.Value])
} derive(Eq, Debug)

///|
pub(all) struct HelpUsagePositional {
  value_name : String?
  repeat : @engine.RepeatSpec?
  optional : Bool
} derive(Eq, Debug)

///|
pub(all) struct HelpUsage {
  has_options : Bool
  positionals : Array[HelpUsagePositional]
  has_subcommands : Bool
  has_dd : Bool
} derive(Eq, Debug)

///|
pub(all) struct HelpGroup {
  name : String
  title : String?
  description : String?
} derive(Eq, Debug)

///|
pub(all) struct HelpOption {
  spellings : Array[String]
  alias_spellings : Array[String]
  value_name : String?
  display_name : String?
  help : String?
  help_long : String?
  help_group_name : String?
  default_ : HelpDefault?
  env : Array[String]
  required : Bool
  multiple : Bool
  hidden : Bool
  deprecated : Bool
} derive(Eq, Debug)

///|
pub(all) enum HelpOptionEntry {
  HGroup(HelpGroup)
  HOption(HelpOption)
} derive(Eq, Debug)

///|
pub(all) struct HelpPositional {
  value_name : String?
  help : String?
  repeat : @engine.RepeatSpec?
  hidden : Bool
  deprecated : Bool
} derive(Eq, Debug)

///|
pub(all) struct HelpCommand {
  name : String
  aliases : Array[String]
  help : String?
  help_long : String?
  hidden : Bool
  deprecated : Bool
} derive(Eq, Debug)

///|
pub(all) struct HelpModel {
  command_path : Array[String]
  usage : HelpUsage
  description : String?
  description_long : String?
  epilog : String?
  commands : Array[HelpCommand]
  options : Array[HelpOptionEntry]
  positionals : Array[HelpPositional]
  help_entry : String?
} derive(Eq, Debug)

///|
priv struct SortableOption {
  entry : HelpOptionEntry
  identity : String?
  order : Double
  after : String?
}

///|
priv struct SortableCommand {
  entry : HelpCommand
  identity : String
  order : Double
  after : String?
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  let output : Array[String] = []
  for value in values {
    output.push(value)
  }
  output
}

///|
fn push_unique(values : Array[String], value : String) -> Unit {
  for existing in values {
    if existing == value {
      return
    }
  }
  values.push(value)
}

///|
fn option_spellings(element : @engine.ElemDef) -> Array[String] {
  let spellings : Array[String] = []
  match element.long {
    LList(values) =>
      for value in values {
        push_unique(spellings, element.long_prefix + value)
      }
    LForms(_) | LBool(_) => ()
  }
  for variant in element.variants {
    push_unique(spellings, element.long_prefix + variant.trigger)
  }
  for short in element.short {
    push_unique(spellings, element.short_prefix + short.to_string())
  }
  spellings
}

///|
fn help_default(values : Array[@engine.Value]?) -> HelpDefault? {
  match values {
    None => None
    Some(items) =>
      if items.length() == 1 {
        Some(HDefaultScalar(items[0]))
      } else {
        Some(HDefaultArray(items))
      }
  }
}

///|
fn is_group_declaration(element : @engine.ElemDef) -> Bool {
  element.name == "" && element.help_meta.help_group_name is Some(_)
}

///|
fn find_option(definition : @engine.Definition, name : String) -> Bool {
  for element in definition.options {
    if !element.is_alias && element.name == name {
      return true
    }
  }
  false
}

///|
fn option_alias_pairs(
  definition : @engine.Definition,
) -> Array[(@engine.AliasDef, @engine.ElemDef)] {
  let aliases : Array[@engine.AliasDef] = []
  for alias_def in definition.aliases {
    if find_option(definition, alias_def.target) {
      aliases.push(alias_def)
    }
  }
  let entries : Array[@engine.ElemDef] = []
  for element in definition.options {
    if element.is_alias {
      entries.push(element)
    }
  }
  let output : Array[(@engine.AliasDef, @engine.ElemDef)] = []
  let count = if aliases.length() < entries.length() {
    aliases.length()
  } else {
    entries.length()
  }
  for i = 0; i < count; i = i + 1 {
    output.push((aliases[i], entries[i]))
  }
  output
}

///|
fn alias_spellings_for(
  pairs : Array[(@engine.AliasDef, @engine.ElemDef)],
  target : String,
  canonical_spellings : Array[String],
) -> Array[String] {
  let output : Array[String] = []
  for pair in pairs {
    if pair.0.target == target && pair.0.name is None {
      for spelling in option_spellings(pair.1) {
        let mut canonical = false
        for existing in canonical_spellings {
          if existing == spelling {
            canonical = true
            break
          }
        }
        if !canonical {
          push_unique(output, spelling)
        }
      }
    }
  }
  output
}

///|
fn help_option_from(
  element : @engine.ElemDef,
  meta : @engine.HelpMetaDecl,
  alias_spellings : Array[String],
) -> HelpOption {
  {
    spellings: option_spellings(element),
    alias_spellings,
    value_name: meta.value_name,
    display_name: meta.display_name,
    help: meta.help,
    help_long: meta.help_long,
    help_group_name: meta.help_group_name,
    default_: if element.default_declared {
      help_default(element.default_values)
    } else {
      None
    },
    env: copy_strings(element.env),
    required: element.required,
    multiple: element.multiple || element.repeat is Some(_),
    hidden: element.hidden,
    deprecated: element.deprecated,
  }
}

///|
fn insert_option_sorted(
  output : Array[SortableOption],
  entry : SortableOption,
) -> Unit {
  let mut index = output.length()
  for i = 0; i < output.length(); i = i + 1 {
    if entry.order < output[i].order {
      index = i
      break
    }
  }
  output.insert(index, entry)
}

///|
fn option_identity_exists(
  entries : Array[SortableOption],
  name : String,
) -> Bool {
  for entry in entries {
    if entry.identity == Some(name) {
      return true
    }
  }
  false
}

///|
fn option_is_movable(entries : Array[SortableOption], index : Int) -> Bool {
  match entries[index].after {
    Some(target) => option_identity_exists(entries, target)
    None => false
  }
}

///|
fn emit_option_after_tree(
  entries : Array[SortableOption],
  index : Int,
  emitted : Array[Bool],
  output : Array[HelpOptionEntry],
) -> Unit {
  if emitted[index] {
    return
  }
  emitted[index] = true
  output.push(entries[index].entry)
  match entries[index].identity {
    Some(target) =>
      for child = 0; child < entries.length(); child = child + 1 {
        if !emitted[child] && entries[child].after == Some(target) {
          emit_option_after_tree(entries, child, emitted, output)
        }
      }
    None => ()
  }
}

///|
fn ordered_options(definition : @engine.Definition) -> Array[HelpOptionEntry] {
  let pairs = option_alias_pairs(definition)
  let sorted : Array[SortableOption] = []
  let mut declaration_index = 0
  for element in definition.options {
    if element.is_alias {
      continue
    }
    let meta = element.help_meta
    let entry : HelpOptionEntry = if is_group_declaration(element) {
      let name = meta.help_group_name.unwrap()
      HGroup({
        name,
        title: meta.help_group_title,
        description: meta.help_group_description,
      })
    } else {
      let canonical_spellings = option_spellings(element)
      HOption(
        help_option_from(
          element,
          meta,
          alias_spellings_for(pairs, element.name, canonical_spellings),
        ),
      )
    }
    let declared_order = if is_group_declaration(element) {
      meta.help_group_order
    } else {
      meta.help_order
    }
    let order = match declared_order {
      Some(value) => value
      None => declaration_index.to_double()
    }
    insert_option_sorted(sorted, {
      entry,
      identity: if is_group_declaration(element) {
        None
      } else {
        Some(element.name)
      },
      order,
      after: meta.help_after,
    })
    declaration_index = declaration_index + 1
  }
  for pair in pairs {
    match pair.0.name {
      Some(name) => {
        let meta = pair.0.help_meta
        insert_option_sorted(sorted, {
          entry: HOption(help_option_from(pair.1, meta, [])),
          identity: Some(name),
          order: match meta.help_order {
            Some(value) => value
            None => declaration_index.to_double()
          },
          after: meta.help_after,
        })
        declaration_index = declaration_index + 1
      }
      None => ()
    }
  }
  let emitted = Array::make(sorted.length(), false)
  let output : Array[HelpOptionEntry] = []
  for i = 0; i < sorted.length(); i = i + 1 {
    if !option_is_movable(sorted, i) {
      emit_option_after_tree(sorted, i, emitted, output)
    }
  }
  output
}

///|
fn insert_command_sorted(
  output : Array[SortableCommand],
  entry : SortableCommand,
) -> Unit {
  let mut index = output.length()
  for i = 0; i < output.length(); i = i + 1 {
    if entry.order < output[i].order {
      index = i
      break
    }
  }
  output.insert(index, entry)
}

///|
fn command_identity_exists(
  entries : Array[SortableCommand],
  name : String,
) -> Bool {
  for entry in entries {
    if entry.identity == name {
      return true
    }
  }
  false
}

///|
fn emit_command_after_tree(
  entries : Array[SortableCommand],
  index : Int,
  emitted : Array[Bool],
  output : Array[HelpCommand],
) -> Unit {
  if emitted[index] {
    return
  }
  emitted[index] = true
  output.push(entries[index].entry)
  let target = entries[index].identity
  for child = 0; child < entries.length(); child = child + 1 {
    if !emitted[child] && entries[child].after == Some(target) {
      emit_command_after_tree(entries, child, emitted, output)
    }
  }
}

///|
fn ordered_commands(definition : @engine.Definition) -> Array[HelpCommand] {
  let sorted : Array[SortableCommand] = []
  for i = 0; i < definition.commands.length(); i = i + 1 {
    let command = definition.commands[i]
    let meta = command.body.scope.help_meta
    insert_command_sorted(sorted, {
      entry: {
        name: command.name,
        aliases: [],
        help: meta.help,
        help_long: meta.help_long,
        hidden: false,
        deprecated: false,
      },
      identity: command.name,
      order: meta.help_order.unwrap_or(i.to_double()),
      after: meta.help_after,
    })
  }
  let emitted = Array::make(sorted.length(), false)
  let output : Array[HelpCommand] = []
  for i = 0; i < sorted.length(); i = i + 1 {
    let movable = match sorted[i].after {
      Some(target) => command_identity_exists(sorted, target)
      None => false
    }
    if !movable {
      emit_command_after_tree(sorted, i, emitted, output)
    }
  }
  output
}

///|
fn usage_positionals(
  definition : @engine.Definition,
) -> Array[HelpUsagePositional] {
  let output : Array[HelpUsagePositional] = []
  for positional in definition.positionals {
    output.push({
      value_name: positional.help_meta.value_name,
      repeat: positional.repeat,
      optional: positional.optional,
    })
  }
  output
}

///|
fn help_positionals(definition : @engine.Definition) -> Array[HelpPositional] {
  let output : Array[HelpPositional] = []
  for positional in definition.positionals {
    output.push({
      value_name: positional.help_meta.value_name,
      help: positional.help_meta.help,
      repeat: positional.repeat,
      hidden: positional.hidden,
      deprecated: positional.deprecated,
    })
  }
  output
}

///|
fn help_usage(definition : @engine.Definition) -> HelpUsage {
  let mut has_options = false
  let mut has_dd = false
  for option in definition.options {
    if option.is_dd {
      has_dd = true
    } else if !is_group_declaration(option) &&
      option_spellings(option).length() > 0 {
      has_options = true
    }
  }
  {
    has_options,
    positionals: usage_positionals(definition),
    has_subcommands: definition.commands.length() > 0,
    has_dd,
  }
}

///|
fn help_entry(definition : @engine.Definition) -> String? {
  for option in definition.options {
    if option.fail_action {
      let spellings = option_spellings(option)
      if spellings.length() > 0 {
        return Some(spellings[0])
      }
    }
  }
  None
}

///|
fn select_definition(
  root : @engine.Definition,
  path : Array[String],
) -> @engine.Definition? {
  let mut selected = root
  for segment in path {
    let mut found : @engine.Definition? = None
    for command in selected.commands {
      if command.name == segment {
        found = Some(command.body)
        break
      }
    }
    match found {
      Some(next) => selected = next
      None => return None
    }
  }
  Some(selected)
}

///|
fn category_exists(options : Array[HelpOptionEntry], category : String) -> Bool {
  for entry in options {
    match entry {
      HGroup(group) => if group.name == category { return true }
      HOption(_) => ()
    }
  }
  false
}

///|
fn filter_category(
  options : Array[HelpOptionEntry],
  category : String,
) -> Array[HelpOptionEntry] {
  let output : Array[HelpOptionEntry] = []
  for entry in options {
    match entry {
      HGroup(group) => if group.name == category { output.push(entry) }
      HOption(option) =>
        if option.help_group_name == Some(category) {
          output.push(entry)
        }
    }
  }
  output
}

///|
/// DR-113 §1 の help_query 正面玄関。installer fixpoint 後の宣言層 snapshot だけを読み、パースは
/// 実行しない。合法な definition に対する呼び出し側入力の失敗 (path / named category の不在) は
/// query-error envelope で返す — definition-error とは別位相 (definition_error profile は installer
/// が担う、DR-113 §1)。
///
/// - `path`: 選択スコープの root-first 相対 path。既定はルート
/// - `depth`: `DScope` (既定、選択 scope の 1 層のみ) / `DAll` (再帰 scope 埋め込み)。M3c 時点では
///   DAll の再帰埋め込みは未実装、fixture の subcommand-path.json::depth-all-embeds-recursive-scopes
///   の diverge 継続 (M4 で model 側実装)
/// - `category_mode`: DR-113 §1 の 3 分岐。default / all は model 素材を絞らず (renderer への
///   policy 指示だけ、HIP-META-Q13=a)、named 分岐だけが素材を絞る
pub fn help(
  ast : AtomicAST,
  path? : Array[String] = [],
  depth? : HelpDepth = DScope,
  category_mode? : HelpCategoryMode = HCMDefault,
) -> Result[HelpModel, HelpQueryError] {
  let selected = match select_definition(ast.declaration, path) {
    Some(definition) => definition
    None => return Err(HQAbsentPath)
  }
  let mut options = ordered_options(selected)
  match category_mode {
    HCMNamed(name) =>
      if category_exists(options, name) {
        options = filter_category(options, name)
      } else {
        return Err(HQAbsentCategory)
      }
    // HCMDefault / HCMAll: model 素材は同一 (HIP-META-Q13=a)、絞りをかけない。
    HCMDefault | HCMAll => ()
  }
  let command_path : Array[String] = []
  match ast.declaration.scope.name {
    Some(name) => command_path.push(name)
    None => ()
  }
  for segment in path {
    command_path.push(segment)
  }
  let _ = depth
  Ok({
    command_path,
    usage: help_usage(selected),
    description: selected.scope.help_meta.help,
    description_long: selected.scope.help_meta.help_long,
    epilog: selected.scope.help_meta.help_epilog,
    commands: ordered_commands(selected),
    options,
    positionals: help_positionals(selected),
    help_entry: help_entry(selected),
  })
}
