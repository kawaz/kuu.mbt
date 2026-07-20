// help.mbt — DR-113 §1/§4 の宣言層 help query と構造化 help model 実装。

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
/// `pub fn help(...)` (このファイル内)。
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
/// DR-113 §4.3 origin 4 形。model の options / commands entry の由来を表す — Local 以外は
/// `declared_at` 相当情報を保持する。§4.4「alias は canonical entry の alias_spellings / aliases に
/// 併記し、独立一覧しない」により、HOAlias は現状の fixture 走査経路では独立 entry としては現れない
/// (spec 完備性のため carrier だけ持つ)。
pub(all) enum HelpOrigin {
  HOLocal
  HOGlobal(Array[String])
  HOInheritable(Array[String])
  HOAlias(String)
} derive(Eq, Debug)

///|
/// DR-113 §4.1 の value_structure tree。任意ネスト可 (single / seq / or / repeat / type_ref)。
pub(all) enum HelpValueStructure {
  HVSingle(HelpSingleValue)
  HVSeq(Array[HelpValueStructure])
  HVOr(Array[HelpValueStructure])
  HVRepeat(HelpRepeatSpec)
  HVTypeRef(String, String?)
} derive(Eq, Debug)

///|
pub(all) struct HelpSingleValue {
  value_name : String?
  type_ : String?
  values_enum : Array[String]?
} derive(Eq, Debug)

///|
pub(all) struct HelpRepeatSpec {
  min : Int?
  max : Int?
  node : HelpValueStructure
} derive(Eq, Debug)

///|
pub(all) struct HelpUsagePositional {
  value_structure : HelpValueStructure
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
  value_structure : HelpValueStructure?
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
  origin : HelpOrigin
} derive(Eq, Debug)

///|
pub(all) enum HelpOptionEntry {
  HGroup(HelpGroup)
  HOption(HelpOption)
} derive(Eq, Debug)

///|
pub(all) struct HelpPositional {
  value_structure : HelpValueStructure
  help : String?
  help_long : String?
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
  origin : HelpOrigin
  // DR-113 §4.4 depth="all" で子 help model を scope フィールドへ再帰埋め込みする。
  scope : HelpModel?
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

// ── sortable carriers ────────────────────────────────────────────────────────

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

// ── small helpers ────────────────────────────────────────────────────────────

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

// ── alias merging (DR-113 §4.4) ──────────────────────────────────────────────

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
/// command aliases (DR-113 §4.4): `def.aliases` 内の command 対象 alias の name (or target) を
/// 集める。canonical command 名 → aliases 名一覧 の Map を返す。alias 用の CommandDef が
/// installer によって `def.commands` に別 entry として追加されているので、この Map で
/// 「独立一覧しない」フィルタも兼ねる (下記 `alias_command_names`)。
fn command_alias_map(
  definition : @engine.Definition,
) -> Map[String, Array[String]] {
  let output : Map[String, Array[String]] = Map([])
  for a in definition.aliases {
    // command alias: target が def.commands にあり、`name` が明示されているもののみ。
    let mut is_command = false
    for c in definition.commands {
      if c.name == a.target {
        is_command = true
        break
      }
    }
    if !is_command {
      continue
    }
    let alias_name = match a.name {
      Some(n) => n
      None => a.target
    }
    if alias_name == a.target {
      continue
    }
    match output.get(a.target) {
      Some(existing) => push_unique(existing, alias_name)
      None => {
        let arr : Array[String] = []
        arr.push(alias_name)
        output.set(a.target, arr)
      }
    }
  }
  output
}

///|
/// installer が追加した command-alias 用の CommandDef (`clone_def` された副本) の name 一覧。
/// projected commands から除外する対象。
fn alias_command_names(definition : @engine.Definition) -> Array[String] {
  let output : Array[String] = []
  for a in definition.aliases {
    let mut is_command = false
    for c in definition.commands {
      if c.name == a.target {
        is_command = true
        break
      }
    }
    if !is_command {
      continue
    }
    let alias_name = match a.name {
      Some(n) => n
      None => a.target
    }
    if alias_name != a.target {
      push_unique(output, alias_name)
    }
  }
  output
}

// ── value_structure derivation (DR-113 §4.1) ─────────────────────────────────

///|
/// DR-113 §4.1 の value_structure `single{value_name, type, values_enum}` 素材を ElemDef から組む。
/// `type_name` が None の要素 (flag / count / help preset / none / dd / config_file / tty / etc — value-less
/// preset や structural node) は None を返す。help_category (preset_kind="help_category") のみ
/// or[bool, string] 特殊展開。将来 seq/repeat 拡張ポイントは HVRepeat / HVSeq を追加すれば良い。
fn value_structure_of(element : @engine.ElemDef) -> HelpValueStructure? {
  let meta = element.help_meta
  // help_category 特殊: or[bool, string] を展開 (DR-113 §2.3)。value_name は string 側の枝に付く。
  if meta.preset_kind == Some("help_category") {
    let bool_branch = HVSingle({
      value_name: None,
      type_: Some("bool"),
      values_enum: None,
    })
    // DR-113 §2.3: string 枝の value_name 明示なしなら preset canonical "CATEGORY" を当てる
    // (help_category の値スロット既定名)。M4 では help.mbt 側で defaulting、M5 で
    // HelpMetaInstaller.apply 移送時に wire 段で立てる (fixture 期待は "CATEGORY")。
    let str_value_name = match meta.value_name {
      Some(name) => Some(name)
      None => Some("CATEGORY")
    }
    let str_branch = HVSingle({
      value_name: str_value_name,
      type_: Some("string"),
      values_enum: None,
    })
    return Some(HVOr([bool_branch, str_branch]))
  }
  match meta.type_name {
    None => None
    Some(t) => {
      // BEnum の場合、values_enum を素材として拾う (fixture では enum 値の順序が定義順で pin)。
      let values_enum : Array[String]? = match element.body {
        BEnum(values) => Some(copy_strings(values))
        _ => None
      }
      Some(
        HVSingle({ value_name: meta.value_name, type_: Some(t), values_enum }),
      )
    }
  }
}

///|
/// positional 用: 常に何らかの value_structure を返す (schema required — positional は type "none" 相当でも
/// `{"single":{}}` の空箱を返す)。root-basic / subcommand-path 等で type "string" が typical。
fn positional_value_structure_of(
  element : @engine.ElemDef,
) -> HelpValueStructure {
  match value_structure_of(element) {
    Some(vs) => vs
    None =>
      HVSingle({
        value_name: element.help_meta.value_name,
        type_: None,
        values_enum: None,
      })
  }
}

// ── origin resolution (DR-113 §4.3) ──────────────────────────────────────────

///|
/// help.mbt が保持する scope tree の側テーブル: 各 scope の root-first path と Definition
/// への参照。origin (global copy / inheritable copy) の declared_at 逆引きに使う。
priv struct ScopeIndex {
  entries : Array[ScopeEntry]
}

///|
priv struct ScopeEntry {
  path : Array[String]
  definition : @engine.Definition
}

///|
fn build_scope_index(root : @engine.Definition) -> ScopeIndex {
  let entries : Array[ScopeEntry] = []
  let base_path : Array[String] = []
  match root.scope.name {
    Some(name) => base_path.push(name)
    None => ()
  }
  collect_scope_entries(root, base_path, entries)
  { entries, }
}

///|
fn collect_scope_entries(
  definition : @engine.Definition,
  path : Array[String],
  out : Array[ScopeEntry],
) -> Unit {
  out.push({ path: copy_strings(path), definition })
  for command in definition.commands {
    let child_path = copy_strings(path)
    child_path.push(command.name)
    collect_scope_entries(command.body, child_path, out)
  }
}

///|
/// current_path にある element の origin を逆推定。
/// - link_depth > 0 → global 由来。宣言 scope は現在から link_depth 段 (root 側へ) 遡った祖先。
///   ただし root scope の name は path[0] にあるので、declared_at は path[:len - link_depth] (先頭は保持)。
/// - name-derived prefix pattern + descendant scope に is_inheritable=true 同名要素 → inheritable 由来。
/// - 上記いずれでもなければ HOLocal。
fn resolve_origin(
  element : @engine.ElemDef,
  current_path : Array[String],
  index : ScopeIndex,
) -> HelpOrigin {
  if element.link_depth > 0 {
    let len = current_path.length()
    let anchor = len - element.link_depth
    let declared_at : Array[String] = []
    let bound = if anchor < 0 { 0 } else { anchor }
    for i = 0; i < bound; i = i + 1 {
      declared_at.push(current_path[i])
    }
    // root scope の name が current_path 先頭にあるとき (fixture の典型)、declared_at が空になる
    // ケースは無い (link_depth <= len が installer 不変)。念のため空なら root name を残す。
    if declared_at.length() == 0 && current_path.length() > 0 {
      declared_at.push(current_path[0])
    }
    return HOGlobal(declared_at)
  }
  // inheritable 逆推定: 名前が prefix 付きなら (`<child>-<name>` トリガ) descendant scope に
  // is_inheritable=true 同 element 名の option があるはず。Fixture: `--socket-timeout` の name は
  // "timeout" (add_inheritable_copy が e.name をそのまま name として set)、trigger は "socket-timeout"。
  // 検索方針: current_path 配下の全 scope を走査し、`is_inheritable=true` かつ name が element.name と
  // 一致し、かつ trigger 綴りが `<childname>-<element.name>` のパターンにマッチするものを探す。
  let triggers = option_spellings(element)
  for entry in index.entries {
    if !path_prefix(current_path, entry.path) ||
      entry.path.length() <= current_path.length() {
      continue
    }
    for opt in entry.definition.options {
      if !opt.is_inheritable || opt.name != element.name {
        continue
      }
      // 綴りマッチ検証: 現在 element の trigger のいずれかが child scope 名 + "-" + name を含む形。
      let child_name = entry.path[entry.path.length() - 1]
      let expected_trigger = child_name + "-" + element.name
      let mut matched = false
      for t in triggers {
        // t は long_prefix 付き (`--socket-timeout`)。expected_trigger は無し (`socket-timeout`)。
        if str_has_suffix(t, expected_trigger) {
          matched = true
          break
        }
      }
      if matched {
        return HOInheritable(copy_strings(entry.path))
      }
    }
  }
  HOLocal
}

///|
fn path_prefix(prefix : Array[String], full : Array[String]) -> Bool {
  if prefix.length() > full.length() {
    return false
  }
  for i = 0; i < prefix.length(); i = i + 1 {
    if prefix[i] != full[i] {
      return false
    }
  }
  true
}

///|
fn str_has_suffix(s : String, suffix : String) -> Bool {
  let sc = @engine.to_chars(s)
  let sfc = @engine.to_chars(suffix)
  if sfc.length() > sc.length() {
    return false
  }
  let off = sc.length() - sfc.length()
  for i = 0; i < sfc.length(); i = i + 1 {
    if sc[off + i] != sfc[i] {
      return false
    }
  }
  true
}

// ── option / command / positional projection ─────────────────────────────────

///|
fn help_option_from(
  element : @engine.ElemDef,
  meta : @engine.HelpMetaDecl,
  alias_spellings : Array[String],
  origin : HelpOrigin,
) -> HelpOption {
  {
    spellings: option_spellings(element),
    alias_spellings,
    value_structure: value_structure_of(element),
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
    origin,
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
fn ordered_options(
  definition : @engine.Definition,
  current_path : Array[String],
  index : ScopeIndex,
) -> Array[HelpOptionEntry] {
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
      let origin = resolve_origin(element, current_path, index)
      HOption(
        help_option_from(
          element,
          meta,
          alias_spellings_for(pairs, element.name, canonical_spellings),
          origin,
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
        let origin = resolve_origin(pair.1, current_path, index)
        insert_option_sorted(sorted, {
          entry: HOption(help_option_from(pair.1, meta, [], origin)),
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
fn ordered_commands(
  definition : @engine.Definition,
  current_path : Array[String],
  depth : HelpDepth,
  index : ScopeIndex,
) -> Array[HelpCommand] {
  let sorted : Array[SortableCommand] = []
  let alias_map = command_alias_map(definition)
  let alias_names = alias_command_names(definition)
  let mut declaration_index = 0
  for command in definition.commands {
    // installer 追加の alias-copy CommandDef は独立列挙しない (DR-113 §4.4)
    if str_in_arr(alias_names, command.name) {
      declaration_index = declaration_index + 1
      continue
    }
    let meta = command.body.scope.help_meta
    let aliases = match alias_map.get(command.name) {
      Some(list) => copy_strings(list)
      None => []
    }
    let child_path = copy_strings(current_path)
    child_path.push(command.name)
    let scope : HelpModel? = match depth {
      DAll => Some(build_help_model(command.body, child_path, depth, index))
      DScope => None
    }
    insert_command_sorted(sorted, {
      entry: {
        name: command.name,
        aliases,
        help: meta.help,
        help_long: meta.help_long,
        hidden: false,
        deprecated: false,
        origin: HOLocal,
        scope,
      },
      identity: command.name,
      order: meta.help_order.unwrap_or(declaration_index.to_double()),
      after: meta.help_after,
    })
    declaration_index = declaration_index + 1
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
fn str_in_arr(arr : Array[String], value : String) -> Bool {
  for x in arr {
    if x == value {
      return true
    }
  }
  false
}

///|
fn usage_positionals(
  definition : @engine.Definition,
) -> Array[HelpUsagePositional] {
  let output : Array[HelpUsagePositional] = []
  for positional in definition.positionals {
    output.push({ value_structure: positional_value_structure_of(positional) })
  }
  output
}

///|
fn help_positionals(definition : @engine.Definition) -> Array[HelpPositional] {
  let output : Array[HelpPositional] = []
  for positional in definition.positionals {
    output.push({
      value_structure: positional_value_structure_of(positional),
      help: positional.help_meta.help,
      help_long: positional.help_meta.help_long,
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
/// path (current scope path) と depth を伝搬しつつ 1 scope 分の HelpModel を組む。depth=DAll では
/// commands の scope フィールドへ子 HelpModel を再帰埋め込みする。
fn build_help_model(
  selected : @engine.Definition,
  command_path : Array[String],
  depth : HelpDepth,
  index : ScopeIndex,
) -> HelpModel {
  let options = ordered_options(selected, command_path, index)
  {
    command_path,
    usage: help_usage(selected),
    description: selected.scope.help_meta.help,
    description_long: selected.scope.help_meta.help_long,
    epilog: selected.scope.help_meta.help_epilog,
    commands: ordered_commands(selected, command_path, depth, index),
    options,
    positionals: help_positionals(selected),
    help_entry: help_entry(selected),
  }
}

///|
/// DR-113 §1 の help_query 正面玄関。installer fixpoint 後の宣言層 snapshot だけを読み、パースは
/// 実行しない。合法な definition に対する呼び出し側入力の失敗 (path / named category の不在) は
/// query-error envelope で返す。
///
/// - `path`: 選択スコープの root-first 相対 path。既定はルート
/// - `depth`: `DScope` (既定、選択 scope の 1 層のみ) / `DAll` (再帰 scope 埋め込み、DR-113 §4.4)
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
  let index = build_scope_index(ast.declaration)
  let command_path : Array[String] = []
  match ast.declaration.scope.name {
    Some(name) => command_path.push(name)
    None => ()
  }
  for segment in path {
    command_path.push(segment)
  }
  let mut model = build_help_model(selected, command_path, depth, index)
  match category_mode {
    HCMNamed(name) =>
      if category_exists(model.options, name) {
        model = { ..model, options: filter_category(model.options, name) }
      } else {
        return Err(HQAbsentCategory)
      }
    HCMDefault | HCMAll => ()
  }
  Ok(model)
}
