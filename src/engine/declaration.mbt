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
} derive(Eq, Debug)

///|
/// UsefulAST element. Attribute arrays are READ-ONLY to installers (invariant ①': 宣言層 read-only).
/// The declaration layer is never emptied — help / diagnose / 再シリアライズが元の宣言を保持し、後段
/// installer (global 等) も引き続き参照できる。Idempotency は add-if-absent が担う。
pub(all) struct ElementDef {
  name : String
  ty : &TypeExt
  // long installer 所有: wire 二形 (DR-071 §1 — bool | array、"wire には二形とも載る、展開は long
  // installer の解釈"）。糖衣展開 (bool→リスト、DR-076 §2 flag 差し替え/補完) と colon DSL 分類
  // (DR-011/076、main-entry / variant / 構文エラー) は共に installer 層 (`normalize_option` が呼ぶ
  // `resolve_long`) が担う — decode 層は wire の形をそのまま `LongDeclaration` に写すだけ。normalize 前
  // (宣言直後) はこの二形のまま、normalize 後は `List([<kebab main entries>])`（`variants` フィール
  // ドへ分離済みの variant は含まない）に統一される。
  long : LongDeclaration
  variants : Array[Variant] // long installer 所有 (variant DSL, DR-011/045) — normalize_option が resolve_long の結果で埋める。宣言直後は常に []
  short : Array[Char] // short installer 所有
  env : Array[String] // env installer 所有
  help_meta : HelpMetaDeclaration // help_meta installer 所有 (表示専用、lowering 寄与ゼロ)
  // TRANSITIONAL(M5c): tty config remains on the declaration carrier until wire decode constructs
  // the configured TypeExt directly; Entity no longer copies or interprets these fields.
  // DR-099 §1/§3: `type:` が `builtin/tty` factory (bare "tty" 糖衣 / definitions.types 経由の
  // shadow) に解決されたことを示すマーカー。decode 層 (dec_option/dec_positional,
  // json_conformance_test.mbt) が `type:` 解決の一部として直接 set する — DR-098 の独立 wire
  // 属性 `tty:` は撤回され、installer は関与しない (int_round/bool_config と同じ「型 shadow から
  // carry するだけ」のフィールド、専用の Installer variant を持たない)。
  is_tty : Bool
  // DR-099 §3: `builtin/tty` factory の必須 config。値語彙は "stdin" | "stdout" | "stderr" の 3 値
  // enum (単一値 — env の複数候補配列 `Array[String]` とは違う形、tty_provider のシグネチャが単一
  // stream 引数を取るため)。None は「未設定」— `is_tty` かつ None は definition-error
  // (`collect_tty_stream_missing`、bare `type:"tty"` を含む — config を供給する経路が無いため常に
  // definition-error)。
  tty_stream : String?
  // DR-099 §3: `builtin/tty` factory の config `tty_cygwin` (既定 true)。`is_tty` が false の要素
  // では未使用 (int_round が @builtins.int_type() 以外で未使用なのと同じ冗長フィールド)。
  tty_cygwin : Bool
  is_dd : Bool // dd installer 所有 (type:"dd")
  // issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め (DR-063 A.1 裸文字列
  // → exact 正規化 / DR-018 配置で役割決定): a positional-face nameless exact-match leaf
  // (`{"exact": "init"}`) — DR-018 の「配置 (options[]/positionals[]) で役割決定」原理を、既に
  // greedy 面で確立済みの is_dd と同じ carrier パターンで positional 面へ適用したもの。`true` の
  // とき `name` はこの要素の trigger 綴りを運ぶ (is_dd の `name` 再利用と同じ理由付け、
  // `dd_marker`/`normalize_dd_name` 参照) — `element_head` が `Exact(e.name)` へ直接 lower し、
  // value_prim/entity 経路を一切通らない (`ensure_entities` が is_dd と同じガードでスキップする)。
  is_exact : Bool
  // DR-090 §2: dd installer 所有、is_dd 専用の軸拡張 — None/false なら従来の exact dd (§1「既存
  // dd」列) と完全に同じ。`dd_match` が Some のとき `name` はトリガ綴りに使われない (§2「match が
  // あるとき name はトリガ綴りに使われず、要素の同一性・表示軸のみに効く」)。
  dd_match : String? // regex パターン (host = MoonBit core Regex 準拠、DR-085 §2 と同じ dialect)
  dd_self_keep : Bool // false=drop (既定、消費1・捨てる) | true=keep (消費0・自身含め以降 raw)
  is_global : Bool // global installer 所有 (子孫 command scope へコピー伝播)
  is_inherit : Bool // inherit installer 所有 (inherit seat 宣言)
  is_inheritable : Bool // inheritable installer 所有 (DR-059)
  link_depth : Int // >0 なら global COPY が declaring scope 何段下に置かれたか (satellite が Rooted で escape する段数)
  ref_target : String? // DR-020: この要素は named template への ref
  repeat : RepeatSpec? // repeat installer 所有 (DR-043)
  optional : Bool // repeat:{min:0,max:1} の糖衣 (DR-043) — repeat 語彙が所有
  multiple : Bool // multiple installer 所有 (DR-034/043)
  // DR-036 accumulator 名 (multiple installer の decode 所有)。None = 未指定時のデフォルト ("append")、
  // Some("merge")/Some("kv_map") が DR-080/DR-091 §2 の accumulator を選ぶ。`ensure_entity` がそのまま
  // `Entity.accum` へ写す — 中間の installer 変換は無い (collector と同じ「宣言をそのまま Entity へ通す」
  // 経路)。「multiple:true なら常に append」という旧固定写像をこのフィールドで一般化する (DR-080 波及節)。
  // DR-105 §3/M-17 (統括裁定): decode 層は "append"/"merge"/"kv_map" 以外の任意の文字列も
  // (DecodeSkip せず) そのまま Some(生文字列) で通す — 未登録名 (廃止された旧 "flatten" 単独
  // accumulator を含む) は definition-error kind=unknown-vocab として `collect_unknown_accumulator`
  // が静的に弾く (decode-time の DecodeSkip ではなく definition-time の gate に一本化)。
  accumulator : String?
  separator : String? // multiple パイプラインの separator (DR-034)
  // DR-105 §1/§2 (統括裁定 M-16、multiple installer の decode 所有): `multiple: {..., flatten: <bool>}` の
  // 宣言有無そのもの (値ではなく KEY の存在) を保持する — None = キー未宣言、Some(b) = 宣言された値。
  // 存在ベースの gate (`collect_flatten_non_append`) が「値が false でも append 以外の accumulator に
  // flatten キーが宣言されていれば invalid-range」を判定するために「宣言したかどうか」自体が必要
  // (Bool 単体では false=未宣言と false=明示宣言を区別できない)。`ensure_entity` が `e.multiple` の
  // 枝でのみ読み、repeat-cons 専用の枝は自前で true を立てる (Entity.flatten の doc comment 参照)。
  flatten : Bool?

  // DR-036 collector: `multiple: {accumulator, collector}` の object 形が持つ collector 属性 (decode
  // 層の multiple installer decode 所有)。`ensure_entity` がそのまま `Entity.collector`
  // へ写す — 中間の installer 変換は無い (この属性を消費する唯一の installer は「宣言をそのまま Entity
  // へ通す」ensure_entity 自身)。None = collector 未指定 (accumulator 連動デフォルト、DR-036)。
  collector : String?
  fail_action : Bool // failure-action element (DR-048)
  is_config_file : Bool // type:"config_file" (DR-050)
  config_key : Array[String]? // 明示 config path (DR-050 §3); None = 同型
  export_key : ExportKey // 結果キー軸 (DR-052)
  requires : Array[String] // constraint installer (DR-055): 正の依存
  conflicts_with : Array[String] // constraint installer (DR-055): 対称ペア排他
  exclusive_group : Array[String] // constraint installer (DR-047): group labels
  // DR-103 §1: constraint installer 所有、exclusive_group と同型の group labels。グループ内 member
  // のいずれかが required 単項と同じ型委譲充足 (DR-093) を満たさなければ違反 (少なくとも1つ必須)。
  // exclusive_group とは独立した名前空間 (同名文字列を両属性に書いても 2 つの独立述語、DR-103 §3)。
  required_group : Array[String]
  // DR-093 §1/§2: constraint installer 所有。「解決後の充足」の保証であり、充足の定義は type (値空間)
  // が与える — 値空間を持つ要素 (通常 type) は最終状態の値の有無 (default 込み、DR-047 §5 不変)、
  // 値空間が空の要素 (`type: "none"`、dd 含む、DR-089) は発火したこと (committed)。option/positional
  // 両方が持てる (basename/ln の `{"name":"path","type":"string","required":true}` のような
  // positional required が corpus/real-cli に実在する)。
  required : Bool
  // DR-055 §1 + DR-052 §値枝 id 直交: 値の枝に付いた requires。tuple 各成分 =
  // (branch_id, value, targets)。branch_id は or 値枝の匿名要素に付いた識別子 (fixture の `id:
  // "fmt_json"`) で、RequiresIf 違反時の error.element として emit する (制約の宣言元 = 枝、
  // 値の帰属先 = 親 entity の非対称)。id 未指定時は parent entity name を branch_id にフォールバック
  // (parent 直属の value_requires と等価な挙動)。
  value_requires : Array[(String, String, Array[String])]
  // TRANSITIONAL(M5c): parser config also remains on ElementDef because builtin node/matcher
  // residents still encode their stable lowering form from these explicit values. TypeExt already
  // owns runtime parsing; removing this duplicate waits for those residents to accept one descriptor.
  // DR-075 §2 int_round factory config (DR-061 §4 平坦 config キー、`int_parser` の唯一 config)。
  // canonical default = `Error` (非整数値は Error)、opt-in で floor/trunc/half_even 等の丸めモード。
  // parse 相内部調整で、`value_prim` が int resident にこの値を埋め込む。@builtins.int_type() 以外の element は
  // 参照しない (installer が読み取らない冗長フィールド)。
  int_round : RoundMode
  // DR-074 §2 統合 opt-in `number_allow_base_prefix` (`number_parser` factory config)。canonical
  // default = false (基数 prefix / hex float は Error)、true で `0xff` / `0x1.8p3` / `0o777` / `0b1010`
  // を受理する。value_prim が number / int resident に埋め込み、eval / matcher
  // で parse_number_ext / parse_int_value_ext に流す。@builtins.number_type() / @builtins.int_type() 以外は参照しない。
  allow_base_prefix : Bool
  // DR-074 §3/§4 `bool_parser` factory config (DR-061 §4 平坦 config キー 3 つを 1 struct に束ねた
  // carrier — `true_values`/`false_values`/`case_insensitive` は常にセットで使われるため、
  // int_round/allow_base_prefix と違い個別フィールドに展開しない、`RepeatSpec` と同じ「複合 config を
  // 1 struct にまとめる」パターン)。canonical default = `@builtins.bool_config_canonical()`。value_prim が
  // bool resident に埋め込み、eval / matcher で parse_bool_ext に流す。@builtins.bool_type() 以外は
  // 参照しない (冗長フィールド、int_round/allow_base_prefix と同じ扱い)。
  bool_config : BoolConfig
  deprecated : Bool // DR-058: 使用時 `@depr:<name>` warning
  // DR-057 / DR-104 §2/§3: この entry-copy が alias 宣言由来か (canonical=false、`alias_entry` が
  // 常に true で構築する)。`inst_short`/`inst_long` が @builtins.ShortEntry/@builtins.EqEntry へそのまま carry し、
  // complete() の Candidate.is_alias 直訳元になる (deprecated と同じ carrier パターン)。
  is_alias : Bool
  // DR-058 §1 / DR-104 §2: help/補完の既定表示から除外される要素か (`Candidate.hidden`)。
  // `ensure_entity` が builtin の opaque EntityExt resident へ収める — 要素単位の属性
  // (spelling ごとに変わらない) なので alias entry-copy はこの値を持たない。
  hidden : Bool
  // DR-060 §4 / DR-104 §2(d): decode 層 (dec_option/dec_positional) 所有 — wire の
  // `completer: "<名前>"` 属性を opaque EntityExt resident へ収める。`None` = 未宣言。
  completer : String?
  // DR-083 §1/§波及: decode 層 (dec_option/dec_positional) 所有。JSON scalar → 長さ1へ持ち上げ、JSON
  // array → その piece 列そのまま (multiple/repeat/merge 要素のみ合法 — 非 accum 要素への配列は
  // `collect_scalar_array_default` が definition-error として静的に弾く)。`ensure_entity` がそのまま
  // `Entity.default_values` へ写す (§1 の decode-time 持ち上げに加え、FLAG/BOOL/COUNT の暗黙 preset
  // も同じ長さ1形へ揃える)。node.mbt の `Entity.default_values` の doc comment 参照。
  default_values : Array[Value]?
  // Canonical default-seat invocation. `default:` decodes to Typed(set(values)); explicit
  // `default_fn:` decodes to Wire and stays lazy until dependency-ordered resolution.
  default_fn : DefaultFnCall?
  default_declared : Bool // wire に default キーが明示されたか (help 素材と preset 暗黙値を区別)
  // DR-034 pieceProcessor の filter chain (DR-062: inheritance object 形は未実装 — filters.mbt
  // ヘッダ注記参照)。piece_filters: separator 分割後の各 piece 単位 (multiple 無しは長さ 1 に縮退、
  // 同じ管を通る) で type.parse の直前に適用 (String→String)。value_filters: 分割後の要素単位 (each
  // 暗黙、DR-009)。final_filters (DR-102 §1、T→T、scalar filter registry): non-accum 要素専用の
  // 確定した最終値ガード (DR-077 §1 の主対象、update の結果にもこれが通る)。accum_filters (DR-102 §1、
  // Acc→Acc、ARRAY filter registry): accum (multiple/repeat/separator) 要素専用の累積配列全体ガード。
  // 1 属性 1 registry の対応 (DR-102 §2)。要素は universal invocation carrier の
  // `FnInvocation` alias。colon shorthand / 1 段 array / object form は decode 境界で同じ
  // name + args 形になり、chain 消費側は wire 表現を扱わない。
  piece_filters : Array[FnInvocation]
  value_filters : Array[FnInvocation]
  final_filters : Array[FnInvocation]
  accum_filters : Array[FnInvocation]
  // DR-014 / DESIGN §7.2 / DR-096 §1 (issue scope-config-object-gap, 軸別再編): the FULL
  // hierarchical scope `config` object (long_prefix/long_eq_sep/short_prefix/short_attached_value/
  // short_combine/env_prefix/auto_env). Decode (`dec_definition`, json_conformance_test.mbt)
  // reads `config` at EACH Definition/command scope, merges it with the parent scope's resolved
  // config (child key present → override, absent → inherit — DESIGN §7.2「子要素は親の config を
  // 継承、上書き可能」), and bakes the resolved 7-key tuple onto every option/positional ElementDef
  // that scope owns (same "decode-time bake, no Definition-level config carrier" pattern DR-091 §3
  // established for the original 2-field minimal implementation — installer.mbt itself never reads
  // `config`, only these per-element fields). `long_prefix` (既定 `"--"`): the string `inst_long`
  // prepends to this element's own long spellings when building each trigger (`e.long_prefix + l`,
  // replacing the old hardcoded `"--" + l`) — every OTHER element in the same `Definition` keeps its
  // own resolved value unless it also overrides. `""` is unconditionally legal (DR-096 §3.3, kawaz
  // 裁定 2026-07-12 — 旧 DR-091 §3 の「`long_eq_sep: Require` 併用時のみ合法」制約は撤廃): a bare
  // long trigger colliding with a plain positional operand (`foo`) is an application-level concern,
  // not a definition-time error — the normal reading enumeration surfaces the collision as
  // `Ambiguous` (DR-053, `fixtures/matcher-readings/long-empty-prefix-operand-collision.json`), no
  // static rejection is imposed. An app that wants to eliminate the collision can opt into
  // `long_eq_sep: Require` (only `=`-bearing tokens become long candidates) or simply declare no
  // colliding positional — these are DESIGN choices, not prerequisites the parser enforces.
  long_prefix : String
  // DESIGN §7.2 / LOWERING §B.2「config `short_prefix`/`short_combine` がパラメータ」: the string
  // `inst_short` prepends when building the `@builtins.short_combine` matcher's `prefix` (replacing the old
  // hardcoded `"-"`). 既定 `"-"`. Positional 要素は short spelling を持たないため未使用のまま既定値
  // を持ち回る (`long_prefix` と同じ理由付け、opt/pos の doc comment 参照)。
  short_prefix : String
  // DESIGN §7.2 line 838/842 / DR-049 §3-4: `inst_env`/decode-time が env 席の最終 key に連結する
  // prefix。明示 `env:` にも auto_env 導出にも効く (DR-049 §4「明示 env: の値にも env_prefix は連結
  // される」) — decode (`dec_definition`) が両ケースとも解決済みの最終 key をこのフィールドではなく
  // `env` 配列そのものへ焼き込む (この `env_prefix` フィールドは階層継承の運搬用、installer 層は
  // 読まない)。既定 `""` = prefix 部を省く (DR-049 §3「env_prefix 未設定なら prefix 部を省く」)。
  env_prefix : String
  // DESIGN §7.2 line 842 / DR-049 §3: true なら `env:` 未指定の値セル (`Cell`) 持ち要素に
  // decode 時点で env 席を自動宣言する (`UPPER(env_prefix) + "_" + UPPER(scope_path 連結) + "_" +
  // UPPER(name)`、DR-049 §3 の名前導出規則そのまま — decode がこの計算を行い `env` 配列へ焼き込む)。
  // 明示 `env:` が優先 (DR-049 §4)。既定 `false`。
  auto_env : Bool
  // DESIGN §7.2 / DR-096 §1: 3 値 enum で `inst_long` の eq-split entry / SPACE-FORM main entry
  // (`Seq([Exact(trigger), value_prim(...)])`, the `ref_target is None` branch) の配線をダイヤルする。
  // `Require` = SPACE-FORM main entry を withhold、eq-split entry のみ配線 (DR-096 §3.3 — これを
  // `long_prefix: ""` と併用すると、space form が無いので生 token に一切マッチせず `@builtins.eq_split` は `=`
  // を含む token にのみ発火するため、素の operand (`foo`) との衝突をアプリ側で定義的に排除する
  // 選択手段になる。ただし空 prefix 自体はこの併用を要求しない — 併用しない場合の衝突は Ambiguous
  // として通常通り列挙される、`ElementDef.long_prefix` の doc comment 参照)。`Allow` (既定) = 両方
  //配線 (現行挙動そのまま)。`Deny` = eq-split entry を登録しない、SPACE-FORM のみ。3 値のため
  // 「両方 withhold」という旧矛盾状態は構文的に表現不能 (illegal states unrepresentable、DR-096 §1
  // — 旧 `collect_eq_separator_conflict` definition-error 規定は本 DR で不要化・削除)。
  long_eq_sep : EqSepMode
  // DR-014「-abc の結合許可」/ LOWERING §B.2: decode は受理・階層継承する。`short_combine: false` は
  // 複数 short の cluster 結合のみを禁止 (値付着は別軸 `short_attached_value` の管掌、DR-096 §2 で
  // 確定)。既定 `true`、消費側 (`inst_short`/`run_short`/`walk_short`) がこのフィールドの
  // `combine` param として直接参照する。
  short_combine : Bool
  // DESIGN §7.2 / DR-096 §2 (kawaz 裁定 2026-07-12 で `last_only` 追加、4 値): 値持ち short の付着形
  // (`-O2`) と space 分割形 (`-O 2`) の読み生成をダイヤルする新設 4 値 enum — ダイヤルが条件にするの
  // は読みの形だけで、単独発火かクラスタ内か・クラスタ内の位置は条件にならない (DR-096 §3.1)。
  // `Require` = 付着形のみ受理、space-form main entry を withhold (gcc/clang の `-O`/`-W` 型)。
  // `Allow` (既定) = 両方受理 (現行挙動そのまま、DR-041 §4 の値スロット一般規則)。`Deny` = 付着
  // 読みの枝を生成しない、space 分割形のみ受理。`LastOnly` = 付着読みを「残り全部の丸取り形」1 通り
  // だけに制限 (mid-token 分割点を列挙しない、GNU getopt 慣習)、space 形は `Allow` 同様に生きる。
  // 値スロットを持たない要素 (flag/count/none) には inert (DR-096 §3.2 — `walk_short` の該当 kind
  // 分岐はこのフィールドを参照しない)。`@builtins.ShortEntry.short_attached_value` (node.mbt) へそのまま乗せる、
  // `walk_short` (builtins/matcher_residents.mbt) が唯一の消費者。
  short_attached_value : AttachMode
  // MDR-004: 消費文法の軸。`Cell` (既定) = 従来の単一値セル (`ty` フィールドが型、既存全経路の
  // 縮退形、観測挙動不変)。`Or`/`Group` の要素では `ty` は未使用 — 枝/内部要素の leaf ElementDef が
  // 各自の `ty` を持つ。
  body : ElementBody
} derive(Eq, Debug)

///|
/// MDR-004: ElementDef の消費文法軸。`Cell` (単一値セル) 以外の3つは構造化された消費文法:
/// - `Or`: 構造 or (DR-038 / DESIGN §15.4) — 枝ごとに別の named cell を束縛する「消費文法の枝」。
///   DR-055 の値 enum 枝 (exact 照合、RequiresIf の素材) とは別物 — `Enum` (下記) と対になり、
///   value_requires (制約) は enum 枝の有無に関わらず `dec_or` が引き続き担う (§5.3 values 正規形)。
/// - `Group`: named group (DR-044 反復グループ) — repeat と組んで、発火ごとに内部 positionals を
///   1 セットずつ束ねる (transparent-seq の `xs{k}` がこの形)。
/// - `Enum` (issue values-decode-support, DESIGN §5.3 / DR-028 追記): 単一 named cell の消費構造が
///   exact 値の列のどれか一つ (Or と違い全枝が SAME name/cell に着地する — 「どの named cell を
///   選ぶか」ではなく「1つの cell にどの値が入るか」)。DESIGN §5.3 の `values` ショートハンド と
///   既存の `or` value-enum 正規形 (`{"or":[{"exact":...}]}`, DR-055) は同じ消費意味論に合流する
///   (糖衣と展開形で観測挙動を割らない、team-lead 裁定 2026-07-10) — `dec_option` が両方をこの
///   variant へ decode する。
pub(all) enum ElementBody {
  Cell
  Or(Array[OrBranch])
  Group(Array[ElementDef])
  Enum(Array[String])
} derive(Eq, Debug)

///|
/// MDR-004 §1: 構造 or の 1 枝。`id` はユーザ指定 (fixture の `"id"` キー) か、無指定なら自動採番
/// `"#{seq}"` (kawaz 裁定 2026-07-08: `#` は user namespace 外、一意なら採番方式は問わない)。この id
/// は現状の 4 fixture では表示面・照合面のどこにも現れない内部データ (§4: 自動 id は表示面に出さない
/// — wbtest で非露出を固定、実装順 §5 段目) — 枝の選択は Or ノードの構造そのもの (配列内の位置) で
/// 行われ、id 照合には現状どの lowering 経路も依存しない。`items` は 1 個 = 単一セル枝、複数 = seq 枝
/// (再帰可 — 枝の中に group/or を持てる、ただし本 MDR の対象 4 fixture は 1 階層のみ)。
pub(all) struct OrBranch {
  id : String
  items : Array[ElementDef]
} derive(Eq, Debug)

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
/// variant entry (DR-011 / DR-045). `--no-ssl` のような distinct trigger が cell に EFFECT を適用する。
/// long installer が `{exact, link (by name), effect}` に lowering する (LOWERING §B.1)。
pub(all) struct Variant {
  trigger : String
  op : EffectOp
  operand : Value? // set variant のみ操作数を持つ; default / unset / empty は None
} derive(Eq, Debug)

// ── long DSL 綴りの分類 (DR-011 / DR-071 / DR-076): wire 語彙の唯一の解釈器 ────────

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

///|
/// subcommand (DR-041 §4)。`export_key`: null = scope key drop, 子は親 scope へ promote (DR-052)。
pub(all) struct CommandDef {
  name : String
  body : Definition
  export_key : ExportKey
} derive(Eq, Debug)

///|
/// ルートまたは command のスコープ自身に属する宣言層メタデータ。
pub(all) struct ScopeDeclaration {
  name : String?
  help_meta : HelpMetaDeclaration
} derive(Eq, Debug)

///|
/// 1 つの command scope の UsefulAST。`commands` は DR-018 sugar; command installer が greedy 排他
/// trigger + 新 backbone (DR-041 §4) に展開する。
pub(all) struct Definition {
  scope : ScopeDeclaration
  options : Array[ElementDef]
  positionals : Array[ElementDef]
  commands : Array[CommandDef]
  aliases : Array[AliasDef] // DR-057
  // DR-113 §4.2 共有型定義。definitions.types に宣言された tree 形の型を定義出現順で保持する。
  // 現在の Definition は 1 scope 分だが、共有型は root scope から子孫まで有効 (dec_types が
  // 親子で shadows を継承しているため実装的にも root で完結)。help_installer は root Definition
  // の help_types だけを読んで types 集約 (used_as 逆収集を含む) を組む。root 以外の scope で
  // 追加宣言する用法は未サポート (fixture も root のみ)。
  help_types : Array[HelpTypeDeclaration]
} derive(Eq, Debug)
