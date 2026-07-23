// Public declaration ABI data.

// declaration.mbt — read/write declaration carriers crossing decode and installer residents.

///|
/// DR-113 §4.1 の value_structure tree carrier。single / seq / or / repeat / type_ref を任意
/// ネストで表す。wire_decode が option/positional の値形 (type/or/seq/repeat 系 wire キー) と
/// definitions.types 内の共有型定義 tree を decode 時点で組み立て、HelpMetaDeclaration と Definition の
/// 側テーブルへ carry する — help_installer は projection 時に読むだけ (計算しない)。
pub(all) enum HelpValueStructure {
  Single(HelpSingleValue)
  Seq(Array[HelpValueStructure])
  Or(Array[HelpValueStructure])
  Repeat(HelpRepeatSpec)
  TypeRef(HelpTypeRef)
} derive(Eq, Debug)

///|
pub(all) struct HelpSingleValue {
  value_name : String?
  value_type : String?
  values_enum : Array[String]?
} derive(Eq, Debug)

///|
pub(all) struct HelpRepeatSpec {
  min : Int?
  max : Int?
  node : HelpValueStructure
} derive(Eq, Debug)

///|
pub(all) struct HelpTypeRef {
  id : String
  value_name : String?
} derive(Eq, Debug)

///|
/// DR-113 §4.2 共有型定義の carrier。Definition.help_types に定義出現順で並ぶ。
/// used_as は wire 上の直接情報でなく参照側からの逆向き収集なので、ここでは carry しない
/// (help_installer が projection 時に options/positionals を走査して補う)。
pub(all) struct HelpTypeDeclaration {
  id : String
  help : String?
  value_structure : HelpValueStructure
} derive(Eq, Debug)

///|
/// help_meta installer が所有する宣言層の inert 表示属性。lowering 産物へは搬送せず、
/// definition-time 検査と help query が宣言層から参照する。
pub(all) struct HelpMetaDeclaration {
  help : String?
  help_long : String?
  help_epilog : String?
  display_name : String?
  value_name : String?
  help_group_name : String?
  help_group_title : String?
  help_group_description : String?
  help_order : Double?
  help_group_order : Double?
  help_after : String?
  // DR-113 §7.2: help_installer が所有する糖衣属性。5 help preset (help / help_all_category /
  // help_category / help_show_hidden / help_tree) 上でのみ on_failure へ展開され、非 help
  // preset 上の宣言は definition-error `invalid-range` (`collect_help_meta_errors` が判定)。
  // None = wire に宣言なし、Some(bool) = 明示宣言。M3b では糖衣展開自体は先送り (5 preset の
  // fail_action 既定は wire_decode 側で先食い、明示 help_on_failure による override は M3c 以降)。
  help_on_failure : Bool?
  // DR-113 §7.2 / §8.1 の非 help preset 判定に必要な構造情報 carry — `type:` が 5 help
  // preset のいずれかに解決したかどうかを wire_decode 側で立てて HelpMetaInstaller へ渡す。
  // HelpMetaDeclaration は本来 inert な表示メタだが、help_on_failure 糖衣の invalid-range 判定は
  // 「help preset か否か」を必要とし、この判定を実施する installer もこの carrier の唯一の
  // 読者である (M3a 申し送り: preset 由来 type 名は構造情報なので HelpMetaDeclaration carry を許容
  // する統括判断)。help preset 展開後は wire 側で flag_type + fail_action に落ちて元の type
  // 名が消えるため、is_help_preset で bool 化して carry する方が installer 側の分岐を単純化
  // できる。help group declaration entry (name == "") や positional は常に false。
  is_help_preset : Bool
  // DR-113 §4/§4.1 の value_structure `single{type}` フィールド素材。wire_decode 側で
  // `type: "<name>"` の元文字列を canonical (string/number/int/bool) に正規化して保持する。
  // help/help_all_category/help_tree/help_show_hidden など value-less な preset や flag/count/
  // none/dd/config_file/tty は None。help_installer が help model 射影で value_structure を
  // 組み立てるとき、None → value_structure 出力なし、Some(t) → `{"single":{"type":t}}` 系素材。
  // user 定義の type shadow 経由の場合は shadow 解決後の base 名 (string/number/int/bool) を
  // 保持する — type_ref (共有型参照) の集約射影は M5+ で別途 (types map と併走で解決)。
  type_name : String?
  // DR-113 §2 の 5 直交 help preset のうち、value_structure 射影で特殊形が要るものだけを
  // 明示的に carry する。現状は `help_category` の or[bool,string] 展開のみが該当
  // (`Some("help_category")`)、他 4 種 (help / help_all_category / help_show_hidden / help_tree)
  // と非 help preset は None。is_help_preset (bool) と併存: is_help_preset は definition-time
  // 検査 (help_on_failure の invalid-range 判定) が読む、preset_kind は help model 射影が
  // 読む — 別の関心事の carry。
  preset_kind : String?
  // DR-113 §4.1 の value_structure 完全形 carrier。wire_decode 時点で option/positional の
  // 値形 (type/or/seq/repeat 系 wire キー) を tree に組み立てて保持する。type_name は
  // single leaf の simple 形 (`{"single":{"type":"..."}}`) のためのショートカットで維持され、
  // value_structure_hint は seq/or/repeat/type_ref など任意 tree に対応する上位互換。
  // help_installer は projection 時に hint を優先して読み、None 時は type_name の simple 形へ
  // フォールバック。help_category preset の or[bool,string] 展開は現状 help.mbt 側で defaulting
  // する — hint に立てる場合は preset_kind 由来なので特殊分岐は残る。
  value_structure_hint : HelpValueStructure?
  // DR-113 §4.2 型参照マーカー: wire の `type: "<shadow_name>"` が definitions.types の
  // ユーザ定義型を指すとき、その shadow 名を保持する。None = builtin type 直接指定 or 参照なし。
  // help_installer の value_structure 射影で type_ref (TypeRef) 素材を組む鍵になる。
  type_ref : String?
  // DR-115 §1.1 / §1.4: 一括席 `help_render` (scope 単位、root / command のみ合法)。
  // 本 scope で明示された値のみ保持し、階層継承は適用しない (定義-time 検査は「宣言そのもの」を
  // 対象にするため — 継承値まで検査すると同じ違反を親と子の両方で二重 emit する)。element の
  // help_meta にこのフィールドが Some(_) で載れば席違い (invalid-range) の判定素材になる。
  render_declared : HelpRenderDecl?
  // DR-115 §1.1 の階層継承を適用した実効値。dec_definition が親 scope の実効値と本 scope の
  // 宣言値をキー単位マージして格納する。help model 射影の唯一の読者。element では常に None。
  render_effective : HelpRenderDecl?
  // DR-115 §1.2 / §1.4: entry 個別席 `help_value_structure_style`。当該 entry の
  // value_structure 表記だけを一括席の実効値から上書きする素材。scope 側では未使用 (scope に
  // 宣言しても vacuous、DR-115 は席違いにしない — 実装は installer が enum 検査だけ行い、
  // scope 位置の宣言は搬送しない扱い)。value 空間: §5.1 の enum ("auto" / "inline" / "detail")。
  value_structure_style : String?
  // DR-117 §2.6 の `insert_form` 宣言 carry。preset_kind と同じく preset 固有の静的属性を
  // 宣言層 inert として運ぶ。None = wire に宣言なし、Some(v) = wire 上の生値 (未検証)。
  // enum 検査 (`"space"` / `"eq"` 以外は invalid-range)、非 completion_script type への宣言
  // (invalid-range)、複数入口間の明示値食い違い (invalid-range) は `collect_completion_script_errors`
  // (builtins/installer.mbt) が判定する — decode-time は生文字列を運ぶだけ。help_on_failure と
  // 同型の「宣言そのものを保持して installer 検査に委ねる」pattern。lowering 産物 (Entity / Scope) には
  // 搬送しない — 応答 policy 段 (completion_query) が declaration snapshot から `completion_insert_form`
  // (definition-wide reconciled value、LoweredDefinition / AtomicAST に carry) を読む。
  completion_insert_form_declared : String?
} derive(Eq, Debug)

///|
/// DR-115 §1.1 / §5: `help_render` 席 (scope 単位) の 4 キー carrier。全キー optional で「宣言なし」を
/// None、宣言あり (階層継承の source) を Some で持つ — 未宣言キーは階層継承で親の実効値をそのまま
/// 受け継ぐため、既定値の baking はしない (spec §1.1「キー単位継承」の恒等射)。
pub(all) struct HelpRenderDecl {
  template : String?
  value_structure_style : String?
  types_style : String?
  origin_style : String?
} derive(Eq, Debug)

///|
/// Collector declaration carried from wire decode to lowering. `args: None`
/// names a static registry resident; `args: Some(json)` carries the configured
/// argument payload whose shape is owned by that resident.
pub(all) struct CollectorDeclaration {
  name : String
  args : Json?
} derive(Eq, Debug)

///|
pub fn CollectorDeclaration::named(name : String) -> CollectorDeclaration {
  { name, args: None }
}

///|
pub fn CollectorDeclaration::configured(
  name : String,
  args : Json,
) -> CollectorDeclaration {
  { name, args: Some(args) }
}

///|
/// alias 宣言 (DR-057): 参照ファミリー third member (ref / link / **alias**). 独立 element として
/// `{alias:"port", short:"n"}` の形で書く。`target` = canonical, `name` = alias 自身の名 (None なら
/// canonical と同名), `short` = alias 明示 short (canonical の short は継承しない §3), `long_override`
/// (DR-007 差分上書き): None = alias 名で name-derived variants を再導出, Some(decl) = 明示置換。
/// `LongDeclaration` (wire 二形保持) を canonical の `long` と同じ型にする — bool/array の区別を decode 後も
/// 保持しないと、alias 側で DR-076 §2 の flag 差し替え/補完 (`resolve_long`) を適用できない (issue
/// 2026-07-08 dec-alias-long-override-flag-sugar-gap: 旧 `Array[String]?` は `long:true` を型非依存に
/// `[":set"]` へ潰しており、canonical が flag でも裸発火 `:set:true` へ差し替わらなかった)。
pub(all) struct AliasDef {
  target : String
  name : String?
  short : Array[Char]
  long_override : LongDeclaration?
  deprecated : Bool
  help_meta : HelpMetaDeclaration
} derive(Eq, Debug)

///|
/// `long` attribute の wire 二形 (DR-071 §1): JSON では `true`/`false` (bool 糖衣) か `[...]` (variant
/// DSL の配列) のどちらか。long installer の decode はこの二形をそのまま写すだけ — 型依存の糖衣展開
/// (DR-076 §2 flag 差し替え/補完) や colon DSL 分類 (DR-011) は installer 層の `resolve_long` が担う
/// (二形の区別は wire 上でしか付かない情報なので、展開後の `Array[String]` 単独では復元できない —
/// decode 層で糖衣を潰すと installer 層がこの区別を必要とする場面で情報が失われる)。
pub(all) enum LongDeclaration {
  Bool(Bool)
  // String-only wire arrays and the post-normalize trigger list retain the compact legacy carrier.
  List(Array[String])
  // A wire array containing at least one one-level array invocation preserves every entry as the
  // universal-fn form until normalize_surface classifies it. Post-normalize declarations always
  // converge to List(trigger spellings).
  Forms(Array[FnInvocationForm])
} derive(Eq, Debug)

///|
/// repeat 閉包 (DR-043)。`min` は必須 rep 数 (mandatory-head unroll)。`max`: None = 無限 (Ref tail),
/// Some(M) = 有限 (M-min BoundedTail heads、Ref 再帰なし LOWERING §B.8)。`optional:true` は
/// `{min:0,max:Some(1)}` の糖衣 (ここで還元、独立概念ではない DR-043)。`is_lazy` は取り分選好
/// (greedy default / lazy 最短優先) — MDR-003 で bare `lazy` → `is_lazy`。
pub(all) struct RepeatSpec {
  min : Int
  max : Int? // None = unbounded (Ref tail), Some(M) = bounded (BoundedTail)
  is_lazy : Bool // MDR-003: bare `lazy` は予約語衝突 → `is_lazy`
} derive(Eq, Debug)
