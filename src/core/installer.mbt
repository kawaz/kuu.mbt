// installer.mbt — parse_definition as a chain of installers (DR-042).
//
// UsefulAST (ElemDef / Definition / …) → AtomicAST (Scope / Node / Entity / …) を組み立てる lowering 層。
// 各 installer は special vocab (long / short / env / dd / ...) を所有し、apply 時に (1) その vocab を
// READ (削除しない — 宣言層は read-only, invariant ①'), (2) greedy 衛星 / matcher / re-scoping を
// add-if-absent で implant する, (3) 実体 (Entity) の seat (env / inherit) を宣言する。5 invariants により
// chain の順序に依存せず、idempotent。完全性は「chain のどの installer にも所有されない special vocab」の検査。
//
// MDR-002 §3 準拠: installer は node / value / matcher / resolve に依存し、評価器 (eval) には依存しない。
// MDR-002 追記「CPS の射程」の installer 規約: repeat はスパイン形 (positional の Ref / BoundedTail /
// ScopeNode) にのみ正規化し、Or / Seq / Rooted 内部への埋め込みは生成しない (取り分選好の局所化を避けるため)。
// MDR-003 命名規約: bare 予約語は末尾 `_` 化 — RepeatSpec の bare `lazy` は `lazy_` に rename。
// Entity 側の `inherit_` は node.mbt が rename 済み。

///|
/// UsefulAST element. Attribute arrays are READ-ONLY to installers (invariant ①': 宣言層 read-only).
/// The declaration layer is never emptied — help / diagnose / 再シリアライズが元の宣言を保持し、後段
/// installer (global 等) も引き続き参照できる。Idempotency は add-if-absent が担う。
pub struct ElemDef {
  name : String
  ty : Ty
  // long installer 所有: wire 二形 (DR-071 §1 — bool | array、"wire には二形とも載る、展開は long
  // installer の解釈"）。糖衣展開 (bool→リスト、DR-076 §2 flag 差し替え/補完) と colon DSL 分類
  // (DR-011/076、main-entry / variant / 構文エラー) は共に installer 層 (`normalize_option` が呼ぶ
  // `resolve_long`) が担う — decode 層は wire の形をそのまま `LongDecl` に写すだけ。normalize 前
  // (宣言直後) はこの二形のまま、normalize 後は `LList([<kebab main entries>])`（`variants` フィール
  // ドへ分離済みの variant は含まない）に統一される。
  long : LongDecl
  variants : Array[Variant] // long installer 所有 (variant DSL, DR-011/045) — normalize_option が resolve_long の結果で埋める。宣言直後は常に []
  short : Array[Char] // short installer 所有
  env : Array[String] // env installer 所有
  // DR-099 §1/§3: `type:` が `builtin/tty` factory (bare "tty" 糖衣 / definitions.types 経由の
  // shadow) に解決されたことを示すマーカー。decode 層 (dec_option/dec_positional,
  // json_conformance_wbtest.mbt) が `type:` 解決の一部として直接 set する — DR-098 の独立 wire
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
  // では未使用 (int_round が TInt 以外で未使用なのと同じ冗長フィールド)。
  tty_cygwin : Bool
  is_dd : Bool // dd installer 所有 (type:"dd")
  // issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め (DR-063 A.1 裸文字列
  // → exact 正規化 / DR-018 配置で役割決定): a positional-face nameless exact-match leaf
  // (`{"exact": "init"}`) — DR-018 の「配置 (options[]/positionals[]) で役割決定」原理を、既に
  // greedy 面で確立済みの is_dd と同じ carrier パターンで positional 面へ適用したもの。`true` の
  // とき `name` はこの要素の trigger 綴りを運ぶ (is_dd の `name` 再利用と同じ理由付け、
  // `dd_marker`/`normalize_dd_name` 参照) — `elem_head` が `Exact(e.name)` へ直接 lower し、
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
  // DR-036 accumulator 名 (decode 層 dec_multiple 所有)。None = 未指定時のデフォルト ("append")、
  // Some("merge")/Some("kv_map") が DR-080/DR-091 §2 の accumulator を選ぶ。`ensure_entity` がそのまま
  // `Entity.accum` へ写す — 中間の installer 変換は無い (collector と同じ「宣言をそのまま Entity へ通す」
  // 経路)。「multiple:true なら常に append」という旧固定写像をこのフィールドで一般化する (DR-080 波及節)。
  // DR-105 §3/M-17 (統括裁定): decode 層は "append"/"merge"/"kv_map" 以外の任意の文字列も
  // (DecodeSkip せず) そのまま Some(生文字列) で通す — 未登録名 (廃止された旧 "flatten" 単独
  // accumulator を含む) は definition-error kind=unknown-vocab として `collect_unknown_accumulator`
  // が静的に弾く (decode-time の DecodeSkip ではなく definition-time の gate に一本化)。
  accumulator : String?
  separator : String? // multiple パイプラインの separator (DR-034)
  // DR-105 §1/§2 (統括裁定 M-16、decode 層 dec_multiple 所有): `multiple: {..., flatten: <bool>}` の
  // 宣言有無そのもの (値ではなく KEY の存在) を保持する — None = キー未宣言、Some(b) = 宣言された値。
  // 存在ベースの gate (`collect_flatten_non_append`) が「値が false でも append 以外の accumulator に
  // flatten キーが宣言されていれば invalid-range」を判定するために「宣言したかどうか」自体が必要
  // (Bool 単体では false=未宣言と false=明示宣言を区別できない)。`ensure_entity` が `e.multiple` の
  // 枝でのみ読み、repeat-cons 専用の枝は自前で true を立てる (Entity.flatten の doc comment 参照)。
  flatten : Bool?

  // DR-036 collector: `multiple: {accumulator, collector}` の object 形が持つ collector 属性 (decode
  // 層 dec_multiple 所有、json_conformance_wbtest.mbt)。`ensure_entity` がそのまま `Entity.collector`
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
  // "fmt_json"`) で、CRequiresIf 違反時の error.element として emit する (制約の宣言元 = 枝、
  // 値の帰属先 = 親 entity の非対称)。id 未指定時は parent entity name を branch_id にフォールバック
  // (parent 直属の value_requires と等価な挙動)。
  value_requires : Array[(String, String, Array[String])]
  // DR-075 §2 int_round factory config (DR-061 §4 平坦 config キー、`int_parser` の唯一 config)。
  // canonical default = `RError` (非整数値は Error)、opt-in で floor/trunc/half_even 等の丸めモード。
  // parse 相内部調整で、`value_prim` が IntArg(name, mode) にこの値を埋め込む。TInt 以外の element は
  // 参照しない (installer が読み取らない冗長フィールド)。
  int_round : RoundMode
  // DR-074 §2 統合 opt-in `number_allow_base_prefix` (`number_parser` factory config)。canonical
  // default = false (基数 prefix / hex float は Error)、true で `0xff` / `0x1.8p3` / `0o777` / `0b1010`
  // を受理する。value_prim が NumArg(name, flag) / IntArg(name, mode, flag) に埋め込み、eval / matcher
  // で parse_number_ext / parse_int_value_ext に流す。TNum / TInt 以外は参照しない。
  allow_base_prefix : Bool
  // DR-074 §3/§4 `bool_parser` factory config (DR-061 §4 平坦 config キー 3 つを 1 struct に束ねた
  // carrier — `true_values`/`false_values`/`case_insensitive` は常にセットで使われるため、
  // int_round/allow_base_prefix と違い個別フィールドに展開しない、`RepeatSpec` と同じ「複合 config を
  // 1 struct にまとめる」パターン)。canonical default = `bool_config_canonical()`。value_prim が
  // BoolArg(name, config, ...) に埋め込み、eval / matcher で parse_bool_ext に流す。TBool 以外は
  // 参照しない (冗長フィールド、int_round/allow_base_prefix と同じ扱い)。
  bool_config : BoolConfig
  deprecated : Bool // DR-058: 使用時 `@depr:<name>` warning
  // DR-057 / DR-104 §2/§3: この entry-copy が alias 宣言由来か (canonical=false、`alias_entry` が
  // 常に true で構築する)。`inst_short`/`inst_long` が ShortEntry/LongEntry へそのまま carry し、
  // complete() の CandMeta.is_alias 直訳元になる (deprecated と同じ carrier パターン)。
  is_alias : Bool
  // DR-058 §1 / DR-104 §2: help/補完の既定表示から除外される要素か (`CandMeta.hidden`)。
  // `ensure_entity` が Entity へそのまま carry する — 要素単位の属性 (spelling ごとに変わらない)
  // なので alias entry-copy はこの値を持たない (`alias_entry` は常に false)。
  hidden : Bool
  // DR-060 §4 / DR-104 §2(d): decode 層 (dec_option/dec_positional) 所有 — wire の
  // `completer: "<名前>"` 属性をそのまま運ぶ。`ensure_entity` がそのまま `Entity.completer` へ写す
  // (`hidden` と同じ carrier パターン)。`None` = completer 未宣言。
  completer : String?
  // DR-083 §1/§波及: decode 層 (dec_option/dec_positional) 所有。JSON scalar → 長さ1へ持ち上げ、JSON
  // array → その piece 列そのまま (multiple/repeat/merge 要素のみ合法 — 非 accum 要素への配列は
  // `collect_scalar_array_default` が definition-error として静的に弾く)。`ensure_entity` がそのまま
  // `Entity.default_values` へ写す (§1 の decode-time 持ち上げに加え、FLAG/BOOL/COUNT の暗黙 preset
  // も同じ長さ1形へ揃える)。node.mbt の `Entity.default_values` の doc comment 参照。
  default_values : Array[Value]?
  // DR-034 pieceProcessor の filter chain (DR-062: inheritance object 形は未実装 — filters.mbt
  // ヘッダ注記参照)。piece_filters: separator 分割後の各 piece 単位 (multiple 無しは長さ 1 に縮退、
  // 同じ管を通る) で type.parse の直前に適用 (String→String)。value_filters: 分割後の要素単位 (each
  // 暗黙、DR-009)。final_filters (DR-102 §1、T→T、scalar filter registry): non-accum 要素専用の
  // 確定した最終値ガード (DR-077 §1 の主対象、update の結果にもこれが通る)。accum_filters (DR-102 §1、
  // Acc→Acc、ARRAY filter registry): accum (multiple/repeat/separator) 要素専用の累積配列全体ガード。
  // 1 属性 1 registry の対応 (DR-102 §2)。要素は `FilterSpelling` (node.mbt、issue
  // filter-spelling-inband-encoding-retyping) — colon shorthand も DESIGN §8.4 object form も同じ
  // 構造体に decode 済み、chain 消費側は colon 分割を一切気にしない。
  piece_filters : Array[FilterSpelling]
  value_filters : Array[FilterSpelling]
  final_filters : Array[FilterSpelling]
  accum_filters : Array[FilterSpelling]
  // DR-014 / DESIGN §7.2 / DR-096 §1 (issue scope-config-object-gap, 軸別再編): the FULL
  // hierarchical scope `config` object (long_prefix/long_eq_sep/short_prefix/short_attached_value/
  // short_combine/env_prefix/auto_env). Decode (`dec_definition`, json_conformance_wbtest.mbt)
  // reads `config` at EACH Definition/command scope, merges it with the parent scope's resolved
  // config (child key present → override, absent → inherit — DESIGN §7.2「子要素は親の config を
  // 継承、上書き可能」), and bakes the resolved 7-key tuple onto every option/positional ElemDef
  // that scope owns (same "decode-time bake, no Definition-level config carrier" pattern DR-091 §3
  // established for the original 2-field minimal implementation — installer.mbt itself never reads
  // `config`, only these per-element fields). `long_prefix` (既定 `"--"`): the string `inst_long`
  // prepends to this element's own long spellings when building each trigger (`e.long_prefix + l`,
  // replacing the old hardcoded `"--" + l`) — every OTHER element in the same `Definition` keeps its
  // own resolved value unless it also overrides. `""` is unconditionally legal (DR-096 §3.3, kawaz
  // 裁定 2026-07-12 — 旧 DR-091 §3 の「`long_eq_sep: EsRequire` 併用時のみ合法」制約は撤廃): a bare
  // long trigger colliding with a plain positional operand (`foo`) is an application-level concern,
  // not a definition-time error — the normal reading enumeration surfaces the collision as
  // `Ambiguous` (DR-053, `fixtures/matcher-readings/long-empty-prefix-operand-collision.json`), no
  // static rejection is imposed. An app that wants to eliminate the collision can opt into
  // `long_eq_sep: EsRequire` (only `=`-bearing tokens become long candidates) or simply declare no
  // colliding positional — these are DESIGN choices, not prerequisites the parser enforces.
  long_prefix : String
  // DESIGN §7.2 / LOWERING §B.2「config `short_prefix`/`short_combine` がパラメータ」: the string
  // `inst_short` prepends when building the `ShortCombine` matcher's `prefix` (replacing the old
  // hardcoded `"-"`). 既定 `"-"`. Positional 要素は short spelling を持たないため未使用のまま既定値
  // を持ち回る (`long_prefix` と同じ理由付け、opt/pos の doc comment 参照)。
  short_prefix : String
  // DESIGN §7.2 line 838/842 / DR-049 §3-4: `inst_env`/decode-time が env 席の最終 key に連結する
  // prefix。明示 `env:` にも auto_env 導出にも効く (DR-049 §4「明示 env: の値にも env_prefix は連結
  // される」) — decode (`dec_definition`) が両ケースとも解決済みの最終 key をこのフィールドではなく
  // `env` 配列そのものへ焼き込む (この `env_prefix` フィールドは階層継承の運搬用、installer 層は
  // 読まない)。既定 `""` = prefix 部を省く (DR-049 §3「env_prefix 未設定なら prefix 部を省く」)。
  env_prefix : String
  // DESIGN §7.2 line 842 / DR-049 §3: true なら `env:` 未指定の値セル (`BCell`) 持ち要素に
  // decode 時点で env 席を自動宣言する (`UPPER(env_prefix) + "_" + UPPER(scope_path 連結) + "_" +
  // UPPER(name)`、DR-049 §3 の名前導出規則そのまま — decode がこの計算を行い `env` 配列へ焼き込む)。
  // 明示 `env:` が優先 (DR-049 §4)。既定 `false`。
  auto_env : Bool
  // DESIGN §7.2 / DR-096 §1: 3 値 enum で `inst_long` の eq-split entry / SPACE-FORM main entry
  // (`Seq([Exact(trigger), value_prim(...)])`, the `ref_target is None` branch) の配線をダイヤルする。
  // `EsRequire` = SPACE-FORM main entry を withhold、eq-split entry のみ配線 (DR-096 §3.3 — これを
  // `long_prefix: ""` と併用すると、space form が無いので生 token に一切マッチせず `EqSplit` は `=`
  // を含む token にのみ発火するため、素の operand (`foo`) との衝突をアプリ側で定義的に排除する
  // 選択手段になる。ただし空 prefix 自体はこの併用を要求しない — 併用しない場合の衝突は Ambiguous
  // として通常通り列挙される、`ElemDef.long_prefix` の doc comment 参照)。`EsAllow` (既定) = 両方
  //配線 (現行挙動そのまま)。`EsDeny` = eq-split entry を登録しない、SPACE-FORM のみ。3 値のため
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
  // `AtRequire` = 付着形のみ受理、space-form main entry を withhold (gcc/clang の `-O`/`-W` 型)。
  // `AtAllow` (既定) = 両方受理 (現行挙動そのまま、DR-041 §4 の値スロット一般規則)。`AtDeny` = 付着
  // 読みの枝を生成しない、space 分割形のみ受理。`AtLastOnly` = 付着読みを「残り全部の丸取り形」1 通り
  // だけに制限 (mid-token 分割点を列挙しない、GNU getopt 慣習)、space 形は `AtAllow` 同様に生きる。
  // 値スロットを持たない要素 (flag/count/none) には inert (DR-096 §3.2 — `walk_short` の該当 kind
  // 分岐はこのフィールドを参照しない)。`ShortEntry.short_attached_value` (node.mbt) へそのまま乗せる、
  // `walk_short` (matcher.mbt) が唯一の消費者。
  short_attached_value : AttachMode
  // MDR-004: 消費文法の軸。`BCell` (既定) = 従来の単一値セル (`ty` フィールドが型、既存全経路の
  // 縮退形、観測挙動不変)。`BOr`/`BGroup` の要素では `ty` は未使用 — 枝/内部要素の leaf ElemDef が
  // 各自の `ty` を持つ。
  body : ElemBody
} derive(Eq, Debug)

///|
/// MDR-004: ElemDef の消費文法軸。`BCell` (単一値セル) 以外の3つは構造化された消費文法:
/// - `BOr`: 構造 or (DR-038 / DESIGN §15.4) — 枝ごとに別の named cell を束縛する「消費文法の枝」。
///   DR-055 の値 enum 枝 (exact 照合、CRequiresIf の素材) とは別物 — `BEnum` (下記) と対になり、
///   value_requires (制約) は enum 枝の有無に関わらず `dec_or` が引き続き担う (§5.3 values 正規形)。
/// - `BGroup`: named group (DR-044 反復グループ) — repeat と組んで、発火ごとに内部 positionals を
///   1 セットずつ束ねる (transparent-seq の `xs{k}` がこの形)。
/// - `BEnum` (issue values-decode-support, DESIGN §5.3 / DR-028 追記): 単一 named cell の消費構造が
///   exact 値の列のどれか一つ (BOr と違い全枝が SAME name/cell に着地する — 「どの named cell を
///   選ぶか」ではなく「1つの cell にどの値が入るか」)。DESIGN §5.3 の `values` ショートハンド と
///   既存の `or` value-enum 正規形 (`{"or":[{"exact":...}]}`, DR-055) は同じ消費意味論に合流する
///   (糖衣と展開形で観測挙動を割らない、team-lead 裁定 2026-07-10) — `dec_option` が両方をこの
///   variant へ decode する。
pub enum ElemBody {
  BCell
  BOr(Array[OrBranch])
  BGroup(Array[ElemDef])
  BEnum(Array[String])
} derive(Eq, Debug)

///|
/// MDR-004 §1: 構造 or の 1 枝。`id` はユーザ指定 (fixture の `"id"` キー) か、無指定なら自動採番
/// `"#{seq}"` (kawaz 裁定 2026-07-08: `#` は user namespace 外、一意なら採番方式は問わない)。この id
/// は現状の 4 fixture では表示面・照合面のどこにも現れない内部データ (§4: 自動 id は表示面に出さない
/// — wbtest で非露出を固定、実装順 §5 段目) — 枝の選択は Or ノードの構造そのもの (配列内の位置) で
/// 行われ、id 照合には現状どの lowering 経路も依存しない。`items` は 1 個 = 単一セル枝、複数 = seq 枝
/// (再帰可 — 枝の中に group/or を持てる、ただし本 MDR の対象 4 fixture は 1 階層のみ)。
pub struct OrBranch {
  id : String
  items : Array[ElemDef]
} derive(Eq, Debug)

///|
/// alias 宣言 (DR-057): 参照ファミリー third member (ref / link / **alias**). 独立 element として
/// `{alias:"port", short:"n"}` の形で書く。`target` = canonical, `name` = alias 自身の名 (None なら
/// canonical と同名), `short` = alias 明示 short (canonical の short は継承しない §3), `long_override`
/// (DR-007 差分上書き): None = alias 名で name-derived variants を再導出, Some(decl) = 明示置換。
/// `LongDecl` (wire 二形保持) を canonical の `long` と同じ型にする — bool/array の区別を decode 後も
/// 保持しないと、alias 側で DR-076 §2 の flag 差し替え/補完 (`resolve_long`) を適用できない (issue
/// 2026-07-08 dec-alias-long-override-flag-sugar-gap: 旧 `Array[String]?` は `long:true` を型非依存に
/// `[":set"]` へ潰しており、canonical が flag でも裸発火 `:set:true` へ差し替わらなかった)。
pub struct AliasDef {
  target : String
  name : String?
  short : Array[Char]
  long_override : LongDecl?
  deprecated : Bool
} derive(Eq, Debug)

///|
/// variant entry (DR-011 / DR-045). `--no-ssl` のような distinct trigger が cell に EFFECT を適用する。
/// long installer が `{exact, link (by name), effect}` に lowering する (LOWERING §B.1)。
pub struct Variant {
  trigger : String
  op : EffectOp
  operand : Value? // set variant のみ操作数を持つ; default / unset / empty は None
} derive(Eq, Debug)

// ── long DSL 綴りの分類 (DR-011 / DR-071 / DR-076): wire 語彙の唯一の解釈器 ────────

///|
/// `long` attribute の wire 二形 (DR-071 §1): JSON では `true`/`false` (bool 糖衣) か `[...]` (variant
/// DSL の配列) のどちらか。decode 層 (dec_long) はこの二形をそのまま写すだけ — 型依存の糖衣展開
/// (DR-076 §2 flag 差し替え/補完) や colon DSL 分類 (DR-011) は installer 層の `resolve_long` が担う
/// (二形の区別は wire 上でしか付かない情報なので、展開後の `Array[String]` 単独では復元できない —
/// decode 層で糖衣を潰すと installer 層がこの区別を必要とする場面で情報が失われる)。
pub enum LongDecl {
  LBool(Bool)
  LList(Array[String])
} derive(Eq, Debug)

///|
/// One `long` DSL string (DR-011/071/076), classified. `":set"` (bare sentinel) is `LMain`; any
/// OTHER colon form is `LVariant` (an empty prefix, e.g. `":set:true"`, is the element's own
/// bare-degenerate main entry — DR-076 §4 — a NON-empty prefix, e.g. `"no:set:false"`, is a
/// separately-triggered named variant — DR-011). DR-011 明確化 (kawaz 裁定 2026-07-08): a colon-less
/// string (e.g. `"verbose"`) and a colon-having string whose effect word is outside the vocabulary
/// (`set`/`default`/`unset`/`empty`) are BOTH a variant DSL syntax error, not a literal spelling
/// fallback — `LInvalid` carries the offending string for the caller to surface as a DR-054
/// definition-error `unknown-vocab`. An explicit-spelling entry point belongs to DR-057's alias
/// element, not to `long`'s DSL (there is no "colon-less = literal" escape hatch here anymore).
enum LongSpelling {
  LMain(String) // resolved main-entry spelling (`own_name`, verbatim — see `classify_long_spelling`)
  LVariant(Variant) // a fully-built variant (trigger/op/operand already resolved against own_name)
  LInvalid(String) // syntax error (colon-less, or unrecognized effect word) — the original string
} derive(Eq, Debug)

///|
/// Split on `:` (DR-011/071/076 colon DSL), keeping empty segments (`":set:true"` → `["", "set",
/// "true"]`) — a leading empty segment is exactly how an EMPTY prefix (the main entry's own
/// bare-degenerate form) is distinguished from a named prefix (`"no:set:false"` → `["no", "set",
/// "false"]`).
fn split_colon(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == ':' {
      out.push(cur)
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
  }
  out.push(cur)
  out
}

///|
/// Naive scalar coercion for a colon-DSL operand string (`no:set:false`'s `"false"`, `:set:true`'s
/// `"true"`, etc.) into the element's `Value` per its type — mirrors `config_to_value`'s per-type
/// parsers (DR-074/075/076 canonical lexicons) but with a permissive `VStr` fallback instead of an
/// Error: a DSL operand is a literal the DEFINITION author wrote (not untrusted CLI input), so an
/// unparseable operand degrading to a string is a defensive fallback, not a silent-coercion concern.
fn dsl_operand_value(ty : Ty, s : String) -> Value {
  match ty {
    TNum | TInt | TCount =>
      match parse_number(s) {
        Some(d) => VNum(d)
        None => VStr(s)
      }
    TFloat =>
      match parse_float(s) {
        Some(d) => VNum(d)
        None => VStr(s)
      }
    TFlag | TBool =>
      match parse_bool(s) {
        Some(b) => VBool(b)
        None => VBool(s == "true" || s == "1")
      }
    TStr => VStr(s)
    // DR-089: none has no value space — this defensive arm is not a live path (a none-typed
    // element carries no value-bearing DSL operand to reach here), same permissive VStr fallback
    // as the rest of this function.
    TNone => VStr(s)
  }
}

///|
/// Classify one `long`/`long_override` DSL string against `own_name` (the caller decides WHICH name
/// applies — a canonical element's own kebab name for `resolve_long`/`normalize_option`, or an
/// alias's re-derived name for `AliasDef.long_override` desugaring, DR-057 §3) and the element's
/// type (for `LVariant`'s operand parsing, DR-074/075/076). This is the SOLE interpreter of the
/// colon DSL (DR-011/071/076 wire vocab) — both `resolve_long` (main `long` attribute) and
/// `desugar_aliases` (alias override desugaring) call this so the two paths can never drift apart
/// (issue 2026-07-08 alias `long_override` gap: aliases used to skip DSL classification entirely,
/// silently misinterpreting `":set:true"` as a literal `"--:set:true"` spelling).
fn classify_long_spelling(
  s : String,
  own_name : String,
  ty : Ty,
) -> LongSpelling {
  if s == ":set" {
    return LMain(own_name)
  }
  let parts = split_colon(s)
  if parts.length() == 1 {
    // DR-011 明確化: colon-less は文法エラー (literal 綴りへの fallback は不採用)。
    return LInvalid(s)
  }
  let prefix = parts[0]
  let trigger = if prefix == "" { own_name } else { prefix + "-" + own_name }
  // DR-077 §2 `update` (5th effect word): a SEPARATE arity from set/unset/empty/default — parts[2]
  // is the filters-registry TRANSFORM NAME (not an operand to coerce via dsl_operand_value), and
  // any remaining segments (parts[3..]) are that transform's own args, threaded through unchecked
  // (arity is a RUNTIME concern — `apply_transform`, resolve.mbt — the same split DR-009's filter
  // chain already uses: definition-time only gates existence + signature, DR-077 §2 "シグネチャ不適合
  // → definition-error"). `unknown-vocab` (DR-054, §2 "不在 → unknown-vocab") is realized by folding
  // BOTH failure modes into `LInvalid` HERE — this reuses `push_invalid_long`'s existing
  // DUnknownVocab collection wholesale instead of a parallel definition-error check
  // (design-priority: 既存の枠組みの組み合わせで解決). codex 指摘 (issue 2026-07-09, DR-047 の設計
  // 報告と同じ節目レビュー): 旧実装は `parts[2] == "increment"` のハードコード allowlist だった —
  // DR-077 §2 の契約通り filters registry を実際に引いて signature を検査する形に置換。不在
  // (registry に無い名前) と、存在するが `Validate` signature (transform として使えない、
  // DR-077 §2 "validate-only filters cannot be used as an update transform" と同じ判定) の 2 つを
  // 区別して弾く — どちらも現行 `DefErrKind` 列挙 (DR-054) に "invalid-signature" 相当の細分 kind が
  // 無いため、両方とも `DUnknownVocab` のまま kind は共通、メッセージ文言だけで理由を分ける
  // (実装の裁量、細分 kind 追加は spec 側の DR-054 拡張判断が要るため見送り — 報告に明記)。
  if parts[1] == "update" {
    if parts.length() >= 3 {
      let transform = parts[2]
      match lookup_filter(transform) {
        None => return LInvalid(s) // 不在: unknown-vocab (registry に無い名前)
        Some(d) =>
          if d.signature == Transform {
            let args : Array[String] = []
            let mut i = 3
            while i < parts.length() {
              args.push(parts[i])
              i = i + 1
            }
            return LVariant({
              trigger,
              op: Update(transform, args),
              operand: None,
            })
          } else {
            return LInvalid(s) // 存在するが Validate signature: transform として使えない
          }
      }
    }
    return LInvalid(s)
  }
  let op : EffectOp? = match parts[1] {
    "set" => Some(Set)
    "unset" => Some(Unset)
    "empty" => Some(Empty)
    "default" => Some(Default)
    _ => None
  }
  match op {
    // DR-011 明確化: 語彙外の effect word も文法エラー (colon-less と同じ扱い — typo が「マッチしない
    // 入口」として黙って通るのを防ぐ、DR-054 の機械検出思想)。
    None => LInvalid(s)
    Some(o) => {
      let operand = if parts.length() >= 3 {
        Some(dsl_operand_value(ty, parts[2]))
      } else {
        None
      }
      LVariant({ trigger, op: o, operand })
    }
  }
}

///|
/// DR-076 §2: the `:set:true` variant (bare-trigger fire → literal `true`) a flag's long展開
/// composes in — `classify_long_spelling(":set:true", kebab(name), TFlag)` would build the SAME
/// value (colon-DSL round-trip), this just skips the string-splitting for the one fixed shape.
fn flag_bare_true_variant(name : String) -> Variant {
  { trigger: kebab(name), op: Set, operand: Some(VBool(true)) }
}

///|
/// DR-077 §3: the `:update:increment` variant (bare-trigger fire → apply the `increment` transform
/// to the linked cell's old value) a count's long展開 composes in — mirrors `flag_bare_true_variant`
/// exactly, just with `Update("increment", [])` in place of `Set`/`true` (count has no operand to
/// carry; the fired value depends on the cell's running state, computed by resolve.mbt's fold).
fn count_increment_variant(name : String) -> Variant {
  { trigger: kebab(name), op: Update("increment", []), operand: None }
}

///|
/// `LongDecl` (wire 二形) → (main-entry spellings — kebab 展開済み, variants)。DR-071 §1's
/// type-independent `long: true` → `[":set"]` sugar is what every OTHER type gets; DR-076 §2 gives
/// `type:"flag"` a DIFFERENT sugar (規則1: 差し替え) and an explicit non-empty list gets `:set:true`
/// COMPOSED IN alongside whatever the author wrote (規則2: 補完、idempotent). DR-077 §3 gives
/// `type:"count"` the SAME two-rule treatment with `:update:increment` in place of `:set:true` —
/// count is the 2nd instance of this exact 糖衣差し替え+補完 machinery (not a parallel mechanism).
/// This is the ONLY place that needs the bool/array distinction `LongDecl` preserves — once
/// collapsed to `Array[String]` (the old design), `long:true` and `long:[":set"]` become
/// indistinguishable, yet DR-076/077 require different flag/count sugar for each (kawaz 裁定
/// 2026-07-08, spec DR-071 §1 "wire には二形とも載る、展開は long installer の解釈"). `LInvalid`
/// spellings (DR-011 明確化: colon-less / 語彙外 effect, DR-077 §2 unknown transform) are silently
/// skipped here — the caller (`normalize_option`) only reaches this AFTER
/// `collect_invalid_long_dsl` has already surfaced them as definition-errors and `parse_definition`
/// has returned early on any error, so none should be live at this point in practice.
fn resolve_long(
  decl : LongDecl,
  name : String,
  ty : Ty,
) -> (Array[String], Array[Variant]) {
  match decl {
    LBool(false) => ([], [])
    LBool(true) =>
      if ty == TFlag {
        ([], [flag_bare_true_variant(name)])
      } else if ty == TCount {
        ([], [count_increment_variant(name)])
      } else if ty == TNone {
        // DR-089 §2 の「消費 0 の純トリガ」canonical 例 (`{"name": "sep", "long": true}`) —
        // TFlag/TCount と同じ「main entry を持たず bare-true variant だけ」の 3 例目。none には
        // 運ぶ値が無いので `flag_bare_true_variant` のプレースホルダ (`Set VBool(true)`) をそのまま
        // 再利用してよい — この Binding は `build_result` 側で `NoneCell` により結果から除外される
        // (`resolve.mbt` 参照)、committed 参加 (conflicts/exclusive/requires トリガ側) だけが生きる。
        ([], [flag_bare_true_variant(name)])
      } else {
        ([kebab(name)], [])
      }
    LList(strs) => {
      let longs : Array[String] = []
      let vars : Array[Variant] = []
      for l in strs {
        match classify_long_spelling(l, kebab(name), ty) {
          LMain(n) => longs.push(n)
          LVariant(v) => vars.push(v)
          LInvalid(_) => ()
        }
      }
      if ty == TFlag && (longs.length() > 0 || vars.length() > 0) {
        let bare_true = flag_bare_true_variant(name)
        let mut already = false
        for v in vars {
          if v == bare_true {
            already = true
          }
        }
        if !already {
          vars.push(bare_true)
        }
      }
      if ty == TCount && (longs.length() > 0 || vars.length() > 0) {
        let bare_inc = count_increment_variant(name)
        let mut already = false
        for v in vars {
          if v == bare_inc {
            already = true
          }
        }
        if !already {
          vars.push(bare_inc)
        }
      }
      (longs, vars)
    }
  }
}

///|
/// repeat 閉包 (DR-043)。`min` は必須 rep 数 (mandatory-head unroll)。`max`: None = 無限 (Ref tail),
/// Some(M) = 有限 (M-min BoundedTail heads、Ref 再帰なし LOWERING §B.8)。`optional:true` は
/// `{min:0,max:Some(1)}` の糖衣 (ここで還元、独立概念ではない DR-043)。`lazy_` は取り分選好
/// (greedy default / lazy 最短優先) — MDR-003 で bare `lazy` → `lazy_`。
pub struct RepeatSpec {
  min : Int
  max : Int? // None = unbounded (Ref tail), Some(M) = bounded (BoundedTail)
  lazy_ : Bool // MDR-003: bare `lazy` は予約語衝突 → `lazy_`
} derive(Eq, Debug)

///|
/// subcommand (DR-041 §4)。`export_key`: null = scope key drop, 子は親 scope へ promote (DR-052)。
pub struct CommandDef {
  name : String
  body : Definition
  export_key : ExportKey
} derive(Eq, Debug)

///|
/// 1 つの command scope の UsefulAST。`commands` は DR-018 sugar; command installer が greedy 排他
/// trigger + 新 backbone (DR-041 §4) に展開する。
pub struct Definition {
  options : Array[ElemDef]
  positionals : Array[ElemDef]
  commands : Array[CommandDef]
  aliases : Array[AliasDef] // DR-057
} derive(Eq, Debug)

///|
/// canonical installers (DR-042 §canonical installer セット + DR-043 repeat/multiple)。
pub enum Installer {
  LongInst
  ShortInst
  EnvInst
  DdInst
  CommandInst
  GlobalInst
  InheritInst
  RepeatInst
  MultipleInst
  ConfigInst
  ConstraintInst
  AliasInst
  InheritableInst
} derive(Eq, Debug)

///|
fn owned_vocab(i : Installer) -> String {
  match i {
    LongInst => "long"
    ShortInst => "short"
    EnvInst => "env"
    DdInst => "dd"
    CommandInst => "command"
    GlobalInst => "global"
    InheritInst => "inherit"
    RepeatInst => "repeat"
    MultipleInst => "multiple"
    ConfigInst => "config" // type:"config_file" と config_key 両方 (DR-050)
    ConstraintInst => "constraint" // requires / conflicts_with / exclusive_group (DR-055)
    AliasInst => "alias" // alias 宣言 (DR-057)
    InheritableInst => "inheritable" // inheritable (DR-059)
  }
}

///|
/// 1 scope 分の mutable build accumulator。installer は ADD だけ (add-if-absent)。build 層は
/// monotonically 成長し、全木の 1 pass が何も追加しなくなった時点で fixpoint。
priv struct Build {
  greedy : Array[Node]
  entities : Array[Entity]
  positional : Array[Node]
  constraints : Array[Constraint]
}

///|
/// scope-builder tree の 1 node。Definition tree を写す。`decl` は宣言層 (installer からは read-only
/// だが global installer が `options` に COPY を push する — invariant ②)。`build` は lowering 層。
priv struct SB {
  decl : Definition
  build : Build
  children : Array[SBChild]
}

///|
priv struct SBChild {
  name : String
  body : SB
}

///|
/// 値プリミティブの唯一の構築点 (positional / long / short いずれの value slot もここを通る,
/// issue 2026-07-09-separator-non-string-type-parse-gap 段1: 以前は `elem_head` だけが
/// `separator` を見て `SepArg` に分岐し、long/short main entry はこの関数を `separator` 抜きで
/// 直接呼んでいたため、long/short option で `multiple + separator` を宣言しても分割が一切効かない
/// 既存バグがあった — `separator` をこの関数自身の分岐に格上げし、呼び出し元 (positional の
/// `elem_head` / long の `inst_long` main entry) が同じ判断を共有するよう一元化した。`separator`
/// が `Some` なら `SepArg` を構築し、型情報 (ty/int_round/allow_base_prefix) をそのまま運搬する
/// (段2: SepArg 自身が piece ごとに型 parse を行う、`sep_binds` 参照) — 段1 (分割自体を配線) と
/// 段2 (分割後の型 parse) は同一サイクルで導入必須 (issue 追記2: 段1 単独では成功系が regress する
/// 実測確認済み)。
/// `merge` (DR-080 波及節): `ElemDef.accumulator == Some("merge")` の素通し。両呼び出し元
/// (`elem_head` / `inst_long` main entry) が同じ判断 (`e.accumulator` を見る) を共有する。
///
/// codex Medium 追従 (2026-07-10, issue merge-no-separator-marker-gap): 経路選択は
/// `separator is Some(_)` **単独**ではなく `separator is Some(_) || merge` — merge 宣言要素は
/// `separator` 未宣言でも `SepArg` (piece 処理) 側へ進む。`separator` は `SepArg` へそのまま
/// `String?` で運び (`sep_binds` が `None` を「1 piece = 全体」として扱う、DR-034 §6.3 の縮退)、
/// マーカー認識 (`classify_merge_piece`) は piece 数に関わらず同じ pipeline で効く — `--fields -a`
/// (separator 無し、コンマで割る余地が無い) でも `-a` が remove マーカーとして解釈される。
/// merge でない要素は従来通り `separator is Some(_)` のみが gate (この分岐は不変)。
///
/// `kv_map` (DR-091 §2): `ElemDef.accumulator == Some("kv_map")` は `merge`/`separator` の SepArg
/// 経路とは別枝 — kv_map は「1 token = 1 piece」で separator 分割を必要としない (`k=v` の `=` 分割は
/// この node の仕事ではなく `resolve.mbt`'s `build_result` が畳み時に行う、node.mbt の `KvArg` doc
/// comment参照)。`merge` より先に判定するのは两者が同時に真になることは無い (decode 層 `dec_multiple`
/// が `accumulator` を単一 `String?` としてしか運ばない、DR-080/DR-091 のどちらか一方の語彙) ため
/// 順序に意味は無いが、KvArg が SepArg の分岐に巻き込まれないよう最初に切り出す。
fn value_prim(
  ty : Ty,
  name : String,
  int_round : RoundMode,
  allow_base_prefix : Bool,
  bool_config : BoolConfig,
  piece_filters : Array[FilterSpelling],
  separator? : String? = None,
  merge? : Bool = false,
  kv_map? : Bool = false,
) -> Node {
  if kv_map {
    KvArg(name, piece_filters)
  } else if separator is Some(_) || merge {
    SepArg(
      name, separator, ty, int_round, allow_base_prefix, bool_config, piece_filters,
      merge,
    )
  } else {
    match ty {
      // TNum は canonical (DR-074 §1) + opt-in base prefix (§2)。allow=true で hex/oct/bin 整数 +
      // hex float も受理する統合 opt-in (単一 flag、DR-074 §2)。
      TNum => NumArg(name, allow_base_prefix, piece_filters)
      // TInt は値空間判定 (DR-075 §1) + int_round (§2) + hex/oct/bin (DR-074 §2)。IntArg に mode /
      // flag を埋め込み、eval が parse_int_value_ext(_, mode, flag) で丸め + 基数 prefix を反映する。
      TInt => IntArg(name, int_round, allow_base_prefix, piece_filters)
      // TFloat は DR-074 §1 の広い受理域 (number + inf) を持つ別 lexicon (FloatArg / parse_float)
      TFloat => FloatArg(name, piece_filters)
      // TBool は DR-076 §1/§4 で string/number と同格の値型 — BoolArg / parse_bool_ext を通す
      // (DR-074 §4 bool_parser factory config、canonical default は既存 parse_bool と同値)。
      TBool => BoolArg(name, bool_config, piece_filters)
      _ => StrArg(name, piece_filters)
    }
  }
}

///|
fn copy_strs(a : Array[String]) -> Array[String] {
  let r : Array[String] = []
  for x in a {
    r.push(x)
  }
  r
}

///|
/// Deep-copy an `Array[FilterSpelling]` — mirrors `copy_strs`'s discipline (global/alias desugaring
/// pushes COPIES into descendant scopes, `clone_elem`'s doc comment) but also copies each entry's
/// own `args : Array[String]` (a mutable nested array `copy_strs`-style aliasing would otherwise
/// share across scope copies).
fn copy_filter_spellings(a : Array[FilterSpelling]) -> Array[FilterSpelling] {
  let r : Array[FilterSpelling] = []
  for fs in a {
    r.push({ name: fs.name, args: copy_strs(fs.args) })
  }
  r
}

///|
/// 有効 long 綴り一覧 (post-normalize; `:set` は既に kebab(name) に展開済み、`normalize_option` が
/// `LongDecl` を `LList([<kebab main entries>])` に確定させた後の形)。[] = main-entry なし (DR-071)。
/// pre-normalize な `LBool` はここに来ない前提 (呼び出しは全て normalize 後)。
fn long_of(e : ElemDef) -> Array[String] {
  match e.long {
    LList(strs) => strs
    LBool(_) => []
  }
}

///|
fn copy_long(l : LongDecl) -> LongDecl {
  match l {
    LBool(b) => LBool(b)
    LList(strs) => LList(copy_strs(strs))
  }
}

///|
fn copy_chars(a : Array[Char]) -> Array[Char] {
  let r : Array[Char] = []
  for x in a {
    r.push(x)
  }
  r
}

///|
fn copy_variants(a : Array[Variant]) -> Array[Variant] {
  let r : Array[Variant] = []
  for x in a {
    r.push(x)
  }
  r
}

///|
fn clone_elem(e : ElemDef) -> ElemDef {
  {
    name: e.name,
    ty: e.ty,
    long: copy_long(e.long),
    variants: copy_variants(e.variants),
    short: copy_chars(e.short),
    env: copy_strs(e.env),
    is_tty: e.is_tty,
    tty_stream: e.tty_stream,
    tty_cygwin: e.tty_cygwin,
    is_dd: e.is_dd,
    is_exact: e.is_exact,
    dd_match: e.dd_match,
    dd_self_keep: e.dd_self_keep,
    is_global: e.is_global,
    is_inherit: e.is_inherit,
    is_inheritable: e.is_inheritable,
    link_depth: e.link_depth,
    ref_target: e.ref_target,
    repeat: e.repeat,
    optional: e.optional,
    multiple: e.multiple,
    accumulator: e.accumulator,
    flatten: e.flatten,
    separator: e.separator,
    collector: e.collector,
    fail_action: e.fail_action,
    is_config_file: e.is_config_file,
    config_key: e.config_key,
    export_key: e.export_key,
    requires: e.requires,
    conflicts_with: e.conflicts_with,
    exclusive_group: e.exclusive_group,
    required_group: e.required_group,
    required: e.required,
    value_requires: e.value_requires,
    deprecated: e.deprecated,
    is_alias: e.is_alias,
    hidden: e.hidden,
    completer: e.completer,
    default_values: e.default_values,
    int_round: e.int_round,
    allow_base_prefix: e.allow_base_prefix,
    bool_config: e.bool_config,
    piece_filters: copy_filter_spellings(e.piece_filters),
    value_filters: copy_filter_spellings(e.value_filters),
    final_filters: copy_filter_spellings(e.final_filters),
    accum_filters: copy_filter_spellings(e.accum_filters),
    long_prefix: e.long_prefix,
    short_prefix: e.short_prefix,
    env_prefix: e.env_prefix,
    auto_env: e.auto_env,
    long_eq_sep: e.long_eq_sep,
    short_combine: e.short_combine,
    short_attached_value: e.short_attached_value,
    body: clone_body(e.body),
  }
}

///|
/// MDR-004: deep-clone `ElemBody`'s nested `ElemDef`s (mirrors the Array-field deep-copy discipline
/// `clone_elem` already applies to `long`/`variants`/`short`/`env` — global/alias desugaring pushes
/// COPIES into descendant scopes, so aliasing the same mutable nested arrays across scopes would be
/// a bug).
fn clone_body(b : ElemBody) -> ElemBody {
  match b {
    BCell => BCell
    BOr(branches) => {
      let out : Array[OrBranch] = []
      for br in branches {
        let items : Array[ElemDef] = []
        for it in br.items {
          items.push(clone_elem(it))
        }
        out.push({ id: br.id, items })
      }
      BOr(out)
    }
    BGroup(items) => {
      let out : Array[ElemDef] = []
      for it in items {
        out.push(clone_elem(it))
      }
      BGroup(out)
    }
    BEnum(values) => BEnum(copy_strs(values))
  }
}

///|
/// snake_case → kebab-case (DR-022): AST key は snake, CLI long は kebab。ASCII のみ想定。
fn kebab(name : String) -> String {
  let buf = StringBuilder::new()
  for c in name {
    if c == '_' {
      buf.write_char('-')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// 純構文 pre-pass (LOWERING §A / §C.4)。static check と installer fixpoint の前に走る:
///   Fix 2 (§B.1 / DR-071 / DR-076 §2, kawaz 裁定 2026-07-08): `resolve_long` が `LongDecl` (wire 二形)
///   を解釈し、main entry (kebab 展開済み) と variants に確定させる。糖衣展開・flag 差し替え/補完・
///   colon DSL 分類はここに集約 — decode 層 (dec_long) はもう wire の形を写すだけ (二形の区別は decode
///   後に潰さない、`resolve_long` のコメント参照)。
///   Fix 3 (DR-064 §5): dd 要素で name 未指定なら trigger 綴りを "--" に既定
///   Fix 4 (LOWERING §A.5 / DR-076 §2): TFlag の値セルを TBool へ差し替え (flag = bool + default:false +
///   long 綴り合成)。これにより inst_long / eq_entries は TFlag を特殊扱いする必要がなくなり、bool と
///   完全同一の lowering 経路に自然に乗る (flag 固有の lowering 分岐を「型差し替え + resolve_long」の
///   2 点だけに縮退させる、DR-076 §2 規則4)。
fn normalize_surface(def : Definition) -> Unit {
  let mut i = 0
  while i < def.options.length() {
    def.options[i] = normalize_option(def.options[i])
    i = i + 1
  }
  i = 0
  while i < def.positionals.length() {
    def.positionals[i] = normalize_dd_name(def.positionals[i])
    i = i + 1
  }
  for c in def.commands {
    normalize_surface(c.body)
  }
}

///|
/// DR-076 §2: flag の展開後の値セルは bool (LOWERING §A.5) — resolve_long は元の型 (e.ty, まだ TFlag)
/// で判定する必要があるので、型差し替えより先に呼ぶ。`TFlag → TBool` はここで確定してよい — `TBool`
/// 型の short/eq-split 挙動は "TBool 全般に画一的なルール" (非消費・固定 true) で閉じるので、変換後も
/// 「元 flag だったか」を覚えておく必要が無い (matcher.mbt の `TFlag | TBool` アームが両方 flag 型と
/// して扱うのはこの画一性のおかげ)。
///
/// DR-077 §3 (`TCount`) は対称的な糖衣に見えて **ここでは TNum に変換しない** — count 由来の short/
/// eq-split 挙動 (非消費・固定 increment) は「TNum 全般」には適用できない (ordinary number の short
/// は値を消費するのが正しい挙動、`-n5` 等) ので、flag と違って「型変換後も元 count だったか」を覚えて
/// おく必要がある。ElemDef に専用マーカーを新設する代わりに、**TCount というタグ自体を installer chain
/// の間ずっと保持し、値セルの実体型 (Entity.ty = TNum) への収束を `ensure_entity` まで遅延させる**
/// (`ensure_entity` のコメント参照) — 既存の型そのものが情報を運ぶ設計は崩さず、collapse のタイミングだけ
/// 後ろにずらす。short/eq-split matcher (matcher.mbt) は `TCount` を `TFlag | TBool` と並ぶ第 3 の
/// 非消費挙動として扱う。
fn normalize_option(e : ElemDef) -> ElemDef {
  if e.is_dd {
    normalize_dd_name(e)
  } else {
    let (longs, vars) = resolve_long(e.long, e.name, e.ty)
    // TFlag は TBool へ書き換わり `ensure_entity` 到達時には元 TFlag だったかを判別できなくなる
    // ため、flag preset の default:false (LOWERING §A.5) はこの型差し替えと同じ場所で確定させる
    // (issue group-inner-bool-default-false-duplicate-top-level: plain TBool は暗黙 default を
    // 持たないので `ensure_entity` 側の注入対象を絞る一方、flag 由来の TBool は preset を維持する
    // 必要がある — 明示 default があればそちらが勝つのは変わらない)。
    let default_values2 = if e.ty == TFlag && e.default_values is None {
      Some([VBool(false)])
    } else {
      e.default_values
    }
    let ty2 = if e.ty == TFlag { TBool } else { e.ty }
    {
      ..e,
      ty: ty2,
      default_values: default_values2,
      long: LList(longs),
      variants: vars,
    }
  }
}

///|
fn normalize_dd_name(e : ElemDef) -> ElemDef {
  if e.is_dd && e.name == "" {
    { ..e, name: "--" } // DR-064 §5
  } else {
    e
  }
}

///|
fn clone_def(d : Definition) -> Definition {
  let os : Array[ElemDef] = []
  for e in d.options {
    os.push(clone_elem(e))
  }
  let ps : Array[ElemDef] = []
  for e in d.positionals {
    ps.push(clone_elem(e))
  }
  let cs : Array[CommandDef] = []
  for c in d.commands {
    cs.push({ name: c.name, body: clone_def(c.body), export_key: c.export_key })
  }
  let als : Array[AliasDef] = []
  for a in d.aliases {
    als.push(a) // AliasDef は immutable value data (nested mutable array を持たない)
  }
  { options: os, positionals: ps, commands: cs, aliases: als }
}

///|
/// 結果キー map の構築 (DR-052)。要素/コマンド名 → export_key。post-parse の結果 remap 用。alias
/// を desugar 済みの clone に対して収集する — command alias の export_key = EkKey(canonical) が
/// 建った Scope の keying と一致するように。
pub fn build_export_map(def : Definition) -> Map[String, ExportKey] {
  let d = clone_def(def)
  // `d` は normalize_surface を経ていない生の (= pre-normalize) 複製なので、`orig` 引数にも
  // 同じ `d` を渡してよい (TFlag 等の元の型はまだ書き換わっていない)。
  desugar_aliases(d, d)
  let m : Map[String, ExportKey] = Map([], capacity=0)
  collect_export(d, m)
  m
}

///|
fn collect_export(def : Definition, m : Map[String, ExportKey]) -> Unit {
  for e in def.options {
    collect_export_body(e, m)
  }
  for e in def.positionals {
    collect_export_body(e, m)
  }
  for c in def.commands {
    m.set(c.name, c.export_key)
    collect_export(c.body, m)
  }
}

///|
/// MDR-004 §3b: `collect_export` needs to recurse into `ElemBody` — a `BGroup`/`BOr` element's
/// nested leaves (e.g. transparent-seq's `k`, export_key:null) each have their OWN export_key that
/// must reach the map, or their `export_key:null` 裸値化 (DR-052 §2) never gets applied downstream
/// (resolve's export-key remap only consults this map). `BGroup` registers BOTH the wrapper (the
/// array cell itself) and its inner leaves; `BOr`'s wrapper has no export_key of its own concern
/// (structural dispatcher, no scalar/array value) — only its branch leaves register.
fn collect_export_body(e : ElemDef, m : Map[String, ExportKey]) -> Unit {
  match e.body {
    BCell => m.set(e.name, e.export_key)
    BOr(branches) =>
      for br in branches {
        for it in br.items {
          collect_export_body(it, m)
        }
      }
    BGroup(items) => {
      m.set(e.name, e.export_key)
      for it in items {
        collect_export_body(it, m)
      }
    }
    // BEnum (issue values-decode-support): same standing as BCell — a single named cell whose
    // consumption structure happens to be an exact-value enum (no nested leaves to recurse into).
    BEnum(_) => m.set(e.name, e.export_key)
  }
}

///|
/// 要素の lowered head: 値プリミティブ / Ref (ref_target) / SepArg (separator, `value_prim` 側に集約
/// 済み — このヘルパー自身の役目は ref_target の分岐のみ)。issue
/// 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め: `is_exact` (positional-face
/// nameless exact-match leaf, `ElemDef.is_exact` doc comment) は ref_target 分岐より先に判定する —
/// value_prim/Ref どちらの経路も通らず `Exact(name)` へ直接 lower する、bare `Exact` node は「literal
/// token match; binds nothing, consumes 1」(node.mbt) がそのまま欲しい挙動そのもの。この経路は
/// `BOr`/`BGroup` の内側リーフ (`or_branch_node`/`lower_positional` の BGroup 分岐が `elem_head` を
/// 共有する) にも自動的に及ぶ — DR-063 A.1 の裸文字列正規化が or 枝内でも成立する形と対称。
fn elem_head(e : ElemDef) -> Node {
  if e.is_exact {
    return Exact(e.name)
  }
  match e.ref_target {
    Some(r) => Ref(r)
    None =>
      value_prim(
        e.ty,
        e.name,
        e.int_round,
        e.allow_base_prefix,
        e.bool_config,
        e.piece_filters,
        separator=e.separator,
        merge=e.accumulator == Some("merge"),
        kv_map=e.accumulator == Some("kv_map"),
      )
  }
}

///|
/// DESIGN §5.3 (values は or のショートハンド) / DR-028 追記 (values を持つ node は type フィールド
/// なしで enum 型を兼ねる): the consumption structure for a `BEnum` cell — ONE token that must
/// match one of the exact values, or the whole read doesn't exist (DR-028 §3.1 "enum 的テンプレへの
/// 未定義値は or 全枝の綴り不一致 (Reject)" — no held error, same posture bare `Exact` already has:
/// a non-matching token means every branch of the `Or` below fails to Accept, so the read simply
/// isn't there — no separate "reject" signal needed). Each matching branch's Bind value goes
/// through `dsl_operand_value` (the SAME type coercion `classify_long_spelling`'s DSL operand
/// parsing already uses for variant operands) so a non-string-typed enum would get a correctly-
/// typed value — moot for today's only callers (string-only `values`, this issue's scope) since
/// `dsl_operand_value(TStr, s) = VStr(s)`.
fn enum_value_node(name : String, ty : Ty, values : Array[String]) -> Node {
  let branches : Array[Node] = []
  for v in values {
    branches.push(Seq([Exact(v), Bind(name, dsl_operand_value(ty, v))]))
  }
  Or(branches)
}

///|
/// DR-078 §1 result 写像 (issue 2026-07-09-ref-template-result-shape): wrap ONE repeat rep's
/// `head` (a ref element's consumption unit) so its bindings land nested under `name` (the
/// result scope, DESIGN §2.3/§2.4) with a leading "#row" sentinel marking the row boundary
/// (`resolve.mbt`'s `build_result` ROW-GROUP branch groups same-scope bindings into one array
/// element per "#row"). `Bind`'s 0-token binding rides IN FRONT of `head`'s own bindings within
/// the SAME `Scoped` wrap, so both land at scope=[name] together in args order — this is safe to
/// apply per-rep (rather than wrapping the whole repeat spine once) because it changes only the
/// CONTENT of one head-consumption, never the spine shape that drives 取り分選好/先食い
/// (`lower_repeat_head` / `ref_choice` / `bounded_tail_step` remain untouched).
fn ref_row_head(name : String, head : Node) -> Node {
  Scoped(name, Seq([Bind("#row", VBool(false)), head]))
}

///|
/// MDR-004 §3: one `OrBranch`'s consumption grammar node — a single node for a 1-item branch, a
/// `Seq` of value primitives (consumed in order) for a multi-item branch. Each item's own `name`
/// carries through `elem_head` unchanged, so held-Error / binding attribution lands on the LEAF
/// (e.g. `a`/`s`/`b`/`r`/`g`/`b`/`name`) with no extra provenance wiring needed (§4).
fn or_branch_node(br : OrBranch) -> Node {
  if br.items.length() == 1 {
    elem_head(br.items[0])
  } else {
    let nodes : Array[Node] = []
    for it in br.items {
      nodes.push(elem_head(it))
    }
    Seq(nodes)
  }
}

///|
/// 有効 repeat spec (DR-043)。`optional:true` は `{min:0,max:1}` の糖衣 (独立概念ではない)。
fn elem_repeat(e : ElemDef) -> RepeatSpec? {
  match e.repeat {
    Some(s) => Some(s)
    None =>
      if e.optional {
        Some({ min: 0, max: Some(1), lazy_: false })
      } else {
        None
      }
  }
}

///|
/// `Opt(X)` = `Or([X, Seq([])])`。空 Seq が 0 トークン一致。
fn opt_node(x : Node) -> Node {
  Or([x, Seq([])])
}

///|
/// DR-088 §1: 「宣言された値源はデフォルトの存在」— `default_values` (明示 default) だけでなく
/// `env`/`config_key`/`inherit` の宣言も「遅延解決する default_fn が設定されているのと同型」。
/// `eval.mbt`'s `value_declared` (resolve-first-constraint-pipeline / value-present-ladder-gap の
/// 静的宣言述語) と同じ4要素判定を、installer 層 (lowering 時点、ElemDef ベース) で行う版。
fn has_declared_value_source(e : ElemDef) -> Bool {
  e.default_values is Some(_) ||
  e.env.length() > 0 ||
  e.config_key is Some(_) ||
  e.is_inherit
}

///|
/// positional face の lowering。repeat 要素 (DR-043) は Ref 再帰: template
/// `name = Seq([head, Opt(Ref(name))])` を registry に登録し、spine には `min-1` mandatory + Ref
/// (min >= 1 のみ — `Ref` 自体は必ず >= 1 head を消費する構造で「0 でもよい」を表現できない、
/// `consume_head` に「0 なら silent stop」の分岐が無いため)。`min:0` の UNBOUNDED は代わりに
/// `Many(head)` を直接積む (下記詳細)。bounded (max 有限) は Ref 再帰なしで BoundedTail に落ちる
/// (LOWERING §B.8、min:0 は budget=max の BoundedTail が最初から正しく扱う)。dd 要素は spine に
/// 載せない。
///
/// MDR-002 §CPS 規約: repeat はここでスパイン形 (positional の Ref / BoundedTail / ScopeNode /
/// **Many**) にのみ正規化し、Or/Seq/Rooted 内部への埋め込みは生成しない (取り分選好の局所化を避け
/// るため)。`Many` は `Ref`/`BoundedTail` と対称な取り分選好 (既定 greedy = 長い方から試す、
/// `lazy:true` で反転 = 短い方から試す、`has_full_k` で pruning) を scope_consume 側に持つ spine 形
/// (eval.mbt の `Many(inner, lazy_) =>` アーム、"parity with Ref/BoundedTail 取り分選好 spec
/// DR-043")。輪郭は fixtures/path-search/ambiguous-receptacles.json が固定する。

///|
/// DR-043 repeat lowering for a single positional `head` node, shared by `BCell` (head =
/// `elem_head(e)`) and `BOr` (head = `Or(branch_node...)`, issue
/// 2026-07-09-positional-or-repeat-lowering-gap: BOr used to push `Or(nodes)` directly and
/// silently ignore `elem_repeat(e)` entirely — a structural-or head is JUST a head like any other
/// for repeat's purposes, DR-043 §「repeat の対象要素は形を問わない」already says this for `ref`
/// heads, it applies identically to an `Or` head). When `elem_repeat(e)` is `None` the bare `head`
/// is pushed unchanged — the branches inside an `Or` head still each read one head via `Or`'s
/// existing multi-branch semantics (DR-038); `elem_repeat` only ever governs REPETITION count,
/// never branch structure.
fn lower_repeat_head(
  e : ElemDef,
  head : Node,
  registry : Map[String, Node],
  out : Array[Node],
) -> Unit {
  match elem_repeat(e) {
    None => out.push(head)
    Some(spec) =>
      match spec.max {
        None =>
          if spec.min == 0 {
            // UNBOUNDED min:0 (DR-043): a bare `Ref(e.name)` cannot express "0 is fine" (its
            // arm in scope_consume has no fallback for `consume_head` failing to progress), and
            // wrapping it in a plain `Or([Ref(name), Seq([])])` would lose the 取り分選好 (plain
            // `eval()`'s `Or` arm has no preference — both branches survive whenever they BOTH
            // reach a full parse, producing Ambiguous instead of the greedy-left-longest single
            // reading DR-043 requires — exactly this fixture's 3 divergences). `Many(head)` is
            // the existing spine form with the IDENTICAL preference algorithm already wired in
            // scope_consume, so no registry/self-ref is needed at all (each further rep re-enters
            // the SAME `Many` node at the same `pidx`, not a named template). `spec.lazy_` rides
            // straight into `Many`'s 2nd field (issue 2026-07-08 min0-lazy-repeat-gap resolved:
            // BoundedTail's 3rd field is the same seat for the bounded sibling, DR-043 lazy is
            // declarative preference regardless of min/max shape).
            out.push(Many(head, spec.lazy_))
          } else {
            // UNBOUNDED min>=1 (DR-043): `name#cons = Seq([head, Opt(Ref(name#cons))])` の porous
            // 自参照。`#cons` サフィックス (DR-046 §4 の自動 id 空間、`#` は user ns 外の既裁定) で
            // mangle する — DR-078 で `definitions.templates` がこの同じ `registry` を共有するように
            // なったため、プレーン `e.name` キーは「repeat 要素と同名のユーザ template」で衝突しうる
            // (spec `fixtures/lowering/repeat/basic.json` の golden も元々この mangled 形
            // `"src#cons"` を期待しており、`canon_tmpl` の緩比較 (先頭 `#` 区切りで正規化) がこれまで
            // 実装側のプレーン名との差を吸収して隠していただけ — 本 mangle で golden と実体が一致する)。
            let cons = e.name + "#cons"
            registry.set(cons, Seq([head, opt_node(Ref(cons))]))
            if spec.lazy_ {
              // lazy marker (evaluator が split 選好を引くための mangled key)
              registry.set("lazy:" + cons, Exact("lazy"))
            }
            let m = spec.min
            let mut k = 0
            while k < m - 1 {
              out.push(head) // mandatory unrolled heads (DR-043 min)
              k = k + 1
            }
            out.push(Ref(cons)) // >= 1 porous recursive tail
          }
        Some(mx) => {
          // BOUNDED (LOWERING §B.8): min mandatory heads + BoundedTail(head, max-min)
          let m = if spec.min < 0 { 0 } else { spec.min }
          let mut k = 0
          while k < m {
            out.push(head)
            k = k + 1
          }
          let budget = if mx - m < 0 { 0 } else { mx - m }
          out.push(BoundedTail(head, budget, spec.lazy_))
        }
      }
  }
}

///|
fn lower_positional(
  def : Definition,
  registry : Map[String, Node],
) -> Array[Node] {
  let out : Array[Node] = []
  for e in def.positionals {
    if not_dd(e) {
      match e.body {
        BOr(branches) => {
          // MDR-004 §3 "BOr (positional, 匿名)": spine に Or([branch_node...]) を直接積む。評価器の
          // 既存 Or 意味論 (全枝評価 + Held 全保持、DR-053 §2 / 完全経路 2 本以上で ambiguous 保存、
          // DR-038) がそのまま輪郭を満たす。DR-043 repeat との組合せ (issue
          // 2026-07-09-positional-or-repeat-lowering-gap で根治): `Or(nodes)` を head として
          // `lower_repeat_head` に渡す — repeat のレンズには「構造 or の 1 発火」も他の head と
          // 同じ 1 unit で、Ref/Many/BoundedTail のどれになるかは head の形 (Or か StrArg か) に
          // 依存しない。
          let nodes : Array[Node] = []
          for br in branches {
            nodes.push(or_branch_node(br))
          }
          lower_repeat_head(e, Or(nodes), registry, out)
        }
        BGroup(items) => {
          // MDR-004 §3 "BGroup + repeat": IdxRepeat(label=name, head=Seq(inner cells), min,
          // budget) に lower。budget (issue
          // 2026-07-13-positional-group-trailing-missing-operand) = `max - min` (bounded の
          // とき) / `None` (max:null の UNBOUNDED、または repeat 属性自体が無い場合 —
          // どちらも従来どおり greedy-max-forever)。以前は `elem_repeat(e).max` を丸ごと無視
          // しており、`repeat:{min:1,max:1}` のような bounded named-group でも常に unbounded
          // として評価されてトークンを over-consume していた (`fixtures/repeat-parse/group-
          // trailing-positional.json` が pin する — group の直後に別 positional が続く形だけ
          // で顕在化する)。
          //
          // bounded-head 前提 (issue 2026-07-08 greedy-once-and-idxrepeat-premises §2, kawaz 裁定
          // 待ち — installer 規約としての明文化を選択、eval 側への backtrack 追加は見送り): `idx_repeat_eval`
          // (eval.mbt) は宣言上 deterministic な greedy-max で、下流失敗時の後退 (regex backtracking,
          // DR-043 の通常 repeat が `ref_choice` で持つ機構) を持たない。head が permissive (bare string
          // primitive 等、無制限にどんなトークンでも消費できる) だと、budget が None (UNBOUNDED) の
          // ときは後続の必須 positional のぶんまで greedy-max に食われて starve しうる (backtrack が
          // 無いので回復しない) — 通常 repeat の backtrack.json fixture が固定する「縮小再分割」の
          // 保証は IdxRepeat には及ばない。budget が Some (bounded) のときは over-consume 自体が
          // 起きないためこの GAP を踏まない。UNBOUNDED のまま末尾に必須 positional を続ける設計を
          // 書く際は head の先頭に明示的な trigger (Exact 等) を持たせること。
          let head = if items.length() == 1 {
            elem_head(items[0])
          } else {
            let nodes : Array[Node] = []
            for it in items {
              nodes.push(elem_head(it))
            }
            Seq(nodes)
          }
          let (min, budget) = match elem_repeat(e) {
            Some(spec) =>
              (
                spec.min,
                match spec.max {
                  Some(mx) =>
                    Some(if mx - spec.min < 0 { 0 } else { mx - spec.min })
                  None => None
                },
              )
            None => (0, None)
          }
          out.push(IdxRepeat(e.name, head, min, budget))
        }
        BCell =>
          match e.ref_target {
            // DR-078 §1 result 写像 (issue 2026-07-09-ref-template-result-shape): a `ref`
            // element's own `name` must create a result scope (DESIGN §2.3/§2.4) — `elem_head`
            // returns the bare `Ref(target)`, discarding `e.name` entirely, so without this the
            // referenced template's OWN leaf names (colorname/r/g/b) surface at the TOP level
            // instead of nested under `e.name`.
            Some(_) =>
              match elem_repeat(e) {
                // no repeat: single occurrence, degenerate row (DESIGN §6.1 の逆 — repeat が
                // 「配列に包む」操作を担う、外すと row がそのまま値になる) — no "#row" marker
                // needed, `sub_under(binds, e.name)` already yields the row's flat leaves.
                None => out.push(Scoped(e.name, elem_head(e)))
                Some(_) =>
                  lower_repeat_head(
                    e,
                    ref_row_head(e.name, elem_head(e)),
                    registry,
                    out,
                  )
              }
            None =>
              // DR-088 §2 (issue dr-088-positional-default-verification): a plain (no
              // repeat/optional) positional that declares a value source (default/env/
              // config_key/inherit) is structurally COMPLETE with 0 tokens too — the declared
              // source is "a default_fn scheduled to resolve later" (DR-088 §1), so the path
              // must not starve into `missing_operand` just because no token showed up here.
              // `opt_node` (`Or([head, Seq([])])`, already used by `elem_repeat`'s min:0 paths)
              // makes the ONE occurrence optional at the structural level WITHOUT touching
              // `elem_repeat`/`lower_repeat_head`'s array-producing repeat machinery — the
              // entity stays a genuine SCALAR cell (no `accum`), and an unconsumed occurrence
              // leaves it uncommitted, so `resolve.mbt`'s existing default-seat ladder
              // (`resolve_ladder_below_cli`) fills it in exactly as it already does for options.
              // Declared-but-unresolved-at-runtime (e.g. env var absent) still falls through to
              // the scalar's OWN default_values / lower ladder rungs as usual — this only fixes
              // the STRUCTURAL completeness gate, not the value resolution itself.
              if elem_repeat(e) is None && has_declared_value_source(e) {
                lower_repeat_head(e, opt_node(elem_head(e)), registry, out)
              } else {
                lower_repeat_head(e, elem_head(e), registry, out)
              }
          }
        // BEnum (issue values-decode-support): `dec_positional` never produces this shape today
        // (positionals only decode structural "or"/"positionals" — DESIGN §5.3's value-enum
        // shorthand is option-only, `dec_positional`'s own comment). Wired anyway (not aborted) so
        // a future positional-values fixture works without another round-trip here — same
        // `enum_value_node` consumption structure the option side (`inst_long`) uses.
        BEnum(values) =>
          lower_repeat_head(
            e,
            enum_value_node(e.name, e.ty, values),
            registry,
            out,
          )
      }
    }
  }
  out
}

///|
/// (cloned) Definition tree から scope-builder tree を組む。positional は 1 度だけ lower (以後は成長
/// しない — global copy は greedy 側に入る)。entities / greedy は fixpoint pass で埋める。
fn init_sb(def : Definition, registry : Map[String, Node]) -> SB {
  let positional = lower_positional(def, registry)
  let children : Array[SBChild] = []
  for c in def.commands {
    children.push({ name: c.name, body: init_sb(c.body, registry) })
  }
  {
    decl: def,
    build: { greedy: [], entities: [], positional, constraints: [] },
    children,
  }
}

///|
/// Core lowering (installer ではない — 決定的、順序無依存): option/positional ごとに entity 1 個を
/// name 割当で ensure (add-if-absent)。毎 pass 走る (global-copied option も entity を得るため)。
///
/// dd 要素は entity を持たない (LOWERING §B.4「値なし」/ DR-064 §1)。link_depth == 0 のみ ensure
/// (global link COPY は declaring cell へ link 同期するため子 scope 側 entity は不要 — DR-070 §1b gap 5)。
fn ensure_entities(sb : SB, has_cf : Bool) -> Unit {
  for e in sb.decl.options {
    if not_dd(e) && e.link_depth == 0 {
      ensure_entity_body(sb.build, e, has_cf)
    }
  }
  for e in sb.decl.positionals {
    // issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め: `is_exact` (positional
    // -face nameless exact-match leaf) has no value of its own (`ElemDef.is_exact` doc comment,
    // `elem_head` lowers it straight to a bare `Exact`) — same "no entity" standing as `is_dd`,
    // guarded the same way.
    if not_dd(e) && !e.is_exact {
      ensure_entity_body(sb.build, e, has_cf)
    }
  }
}

///|
/// MDR-004 §3b: register `e` (and any `ElemBody`-nested leaves) as top-level entities — the
/// evaluator's `Or`/`Seq`/`IdxRepeat` nodes don't know about entities at all, so this recursive
/// walk is the ONLY registration point. `BOr`'s wrapper is a structural dispatcher with no
/// scalar/array value of its own (e.g. "color" never itself holds a value — only its branch leaves
/// r/g/b/name do), so ONLY the branch leaves register. `BGroup`'s wrapper DOES need its own entity
/// (the array cell — `elem_repeat` on it still drives the existing "flatten" accumulator path,
/// unaffected by `body`) in ADDITION to its inner leaves (e.g. transparent-seq's `k`, its own cell
/// with `entity=k` effects).
fn ensure_entity_body(build : Build, e : ElemDef, has_cf : Bool) -> Unit {
  match e.body {
    BCell =>
      // DR-078 §1 result 写像 (issue 2026-07-09-ref-template-result-shape): a `ref` element is
      // ALSO a structural dispatcher with no scalar/array value of its own — its "value" is a
      // name-scoped projection of the REFERENCED template's own leaves (installer.mbt's
      // `ref_row_head` / `lower_positional`/`inst_long`'s `Scoped` wrap), never a flat binding on
      // `e.name` itself. Registering an entity here is (a) dead for the value-source-ladder side
      // (nothing ever binds flatly to `e.name`, so `resolve_entity` always seats `Ok([])` and
      // contributes no binding) — harmless, not "spurious".
      //
      // issue 2026-07-09-accum-fold-update-default-ops 追記 (2026-07-10, codex レビュー由来の
      // ref-repeat-sibling-trigger.json mismatch): a repeat-bearing ref element (`elem_repeat(e)
      // is Some(_)`) DOES need the entity now, specifically for its `accum: Some("flatten")` —
      // DR-051 §2b「反復系は 0 回発火でも `[]`」は ref+repeat セルにも及ぶが、0 回発火では "#row"
      // (`ref_row_head`) が一切生まれず、build_result の ROW-GROUP 分岐 (`has_direct_key(binds,
      // "#row")`) が素通りして誤って `{}` (OBJECT 経路) に落ちていた (repro:
      // `{"ref":"color","repeat":{"min":0}}` + 直後に sibling trigger で 0 反復)。`accum_cells`
      // (resolve.mbt) が `sc.entities` だけを見る前提を保ったまま、この entity 登録でその走査に
      // ref+repeat セルを乗せ、build_result の UNIFORM ARRAY 注入 (DR-044 §1) で `[]` を出す。
      // 1 回以上発火した場合の「double-renders」懸念 ("#row" 経由の行配列と UNIFORM ARRAY 注入の
      // 二重描画) は、build_result 側のガードを `named` だけでなく `segs` (nested scope 一覧) も
      // 見るよう拡張して閉じている (resolve.mbt のコメント参照) — ROW-GROUP が先に返した path は
      // `segs` 経由で obj に載るので、UNIFORM ARRAY 側は `segs` チェックで重複注入をスキップする。
      // repeat 無しの単発 ref (`elem_repeat(e) is None`) は元のコメントの懸念がそのまま有効
      // (accum が立たないので死んだ entity を増やすだけ) なので、対象を repeat 付きに限定する —
      // ただし DR-084 §1 (issue multiple-ref-accum-gap): `multiple` 付きの repeat 無し ref は
      // "dead" ではない。この場合の accum は "append" (ensure_entity のデフォルト写像) になり、
      // `inst_long`/`lower_positional` 側 (このファイル、`ref_row_head` 分岐の条件) が発火ごとに
      // "#row" を打つよう連動して変わる — 両者は同じ `e.multiple` ガードで揃える必要がある。
      if e.ref_target is None {
        ensure_entity(build, e, has_cf)
      } else if elem_repeat(e) is Some(_) || e.multiple {
        ensure_entity(build, e, has_cf)
      }
    BOr(branches) =>
      for br in branches {
        for it in br.items {
          ensure_entity_body(build, it, has_cf)
        }
      }
    BGroup(items) =>
      // The wrapper (e.g. "xs") lowers to IdxRepeat (MDR-004 §3): its array is built entirely by
      // eval.mbt's array_marker/nest_index scope mechanism, never via the accum-entity ladder. If
      // registered here, ensure_entity would set accum:flatten (elem_repeat(e) is Some for a
      // repeat group), making accum_cells double-count "xs" and inject a spurious extra `[]`
      // alongside the nested-scope array resolve.mbt already builds from the IdxRepeat bindings.
      // Only the inner leaf cells (value-source-ladder participants) need entities.
      for it in items {
        ensure_entity_body(build, it, has_cf)
      }
    // BEnum (issue values-decode-support): a single named cell like BCell (the enum's exact-value
    // branches all bind the SAME `e.name`, unlike BOr's per-branch leaves) — never has a
    // `ref_target` (values/or on a `ref` element is not a decodable shape today), so this always
    // registers unconditionally, simpler than BCell's ref_target-gated arm above.
    BEnum(_) => ensure_entity(build, e, has_cf)
  }
}

///|
fn ensure_entity(build : Build, e : ElemDef, has_cf : Bool) -> Unit {
  for ent in build.entities {
    if ent.name == e.name {
      return
    }
  }
  // repeat / multiple / separator は値 LIST — 名前付き accumulator registry に落とす (DR-036)。
  //   repeat (multiple 無し) → "append" + flatten:true (DR-105 §3: 旧独立 "flatten" accumulator の
  //     廃止、repeat installer の cons unfold [T,[T,…]] → T[] は append accumulator の flatten
  //     ダイヤルで表現する)
  //   multiple / separator → "append" (DR-034)、あるいは `e.accumulator` が明示指定していれば
  //     それ (DR-080 §1: `multiple: {accumulator: "merge", ...}` — 旧「multiple なら常に append」
  //     固定写像を、宣言された accumulator 名の一般写像に置き換える)。この時点で `e.accumulator` は
  //     definition-error gate (`collect_unknown_accumulator`) を通過済みなので "merge"/"kv_map" の
  //     いずれかのみ (M-17)。
  // 両方立った場合は multiple の (accumulator 指定 or) append が勝つ (値 fold が支配)。
  // DR-044 §1 (kawaz 裁定): repeat / multiple / separator は cardinality 不問で常に配列
  //   (`repeat:{min:0,max:1}` = optional 糖衣も [] / [x] — scalar 昇格は collector 側の責務)。
  // is_multiple_decl (DR-084 §2, DR-105 波及): `e.multiple` をそのまま carry する — resolve.mbt の
  // SEGS-loop 判定 (ref+repeat cons cell の discard-earlier-firings と ref+repeat+multiple の
  // firing-preserving を区別する) が、accum 名が両者とも "append" に揃った後もこの軸で判別する。
  let (accum, flatten, is_multiple_decl) : (String?, Bool, Bool) = if e.multiple {
    let acc_name = match e.accumulator {
      Some(a) => a
      None => "append"
    }
    let flat = match e.flatten {
      Some(b) => b
      None => false
    }
    (Some(acc_name), flat, true)
  } else {
    match elem_repeat(e) {
      Some(_) => (Some("append"), true, false)
      None =>
        if e.separator is Some(_) {
          (Some("append"), false, false)
        } else {
          (None, false, false)
        }
    }
  }
  // 同型 config seat (DR-050 §3): config_file 要素が存在すれば全 value cell に config seat を宣言
  // (自身が config_file の要素は循環禁止で除く)。config_key は path override; None = 同型。
  let config_seat = has_cf && !e.is_config_file
  // flag preset default (LOWERING §A.5 / DR-051 §2): a TFlag cell presets default:false (未 fire
  // でも false に落ちる)。ただし `normalize_option` (installer.mbt) が正規化の一環で TFlag を
  // TBool へ既に書き換え済みなので、`ensure_entity` 到達時点の `e.ty` が TFlag のままであることは
  // 実質無い (definitions.types にも flag factory は存在しないため shadow 経由でも生じない) —
  // 実際の flag preset 注入は `normalize_option` 側 (TFlag→TBool 書き換えと同じ場所) で確定済み。
  // ここに `e.ty == TFlag` を残すのは Ty::TFlag という型タグ自体の意味論 (「この型を持つセルは
  // default:false」) を明示するため — TCount が ensure_entity まで自分の意味論を保持するのと
  // 対称。plain TBool (definitions.types の `bool_parser` factory 由来含む) は暗黙 default を
  // 持たない — 未発火なら他の値型と同様に absent (issue
  // group-inner-bool-default-false-duplicate-top-level, DR-099 §2 の `?? absent` 終端と整合)。
  // 明示 default があればそちらが勝つのは変わらない (e.g. ssl の default:true)。
  //
  // count preset default (DR-077 §3): a TCount cell presets default:0, mirroring flag's
  // default:false — an ORDINARY TNum cell must NOT get an uninvited default:0 (a bare numeric
  // slot commonly has no sensible default). This is
  // exactly why `normalize_option` does NOT collapse `TCount → TNum` early (see its comment) — the
  // `TCount` tag survives the whole chain so THIS is the one place that can still tell a count cell
  // apart from an ordinary number cell. The `TNum` collapse itself happens right here too (`ty2`
  // below), at the entity's actual value-cell type (Entity.ty) — the LAST point where the
  // distinction still matters.
  // DR-083 §1: the FLAG/BOOL/COUNT implicit preset is ALSO a length-1 array (the uniform shape
  // every reader now expects) — a decl-less preset is scalar by construction (none of the three
  // kinds can be `multiple` and carry a >1-element preset), so `[v]` is the correct degenerate
  // form, never `[]`.
  // DR-099 §2: is_tty 要素は TBool の暗黙 default:false プリセットを受けない — 素の bool と違い、
  // is_tty 要素の default 席は `resolve.mbt`'s `resolve_ladder_below_cli` が `fold(観測) ?? 宣言
  // default ?? absent` という独自規則で解決する。ここで先回りに false を注入してしまうと「宣言
  // default 無し」という状態が失われ、fold が観測なしの場合に absent へ落ちる余地が無くなる
  // (常に false が浮かび上がってしまう) — is_tty 要素は default_values を宣言されたとおり (無指定
  // なら None) に持ち回り、fold の側で吸収させる。
  let default_values : Array[Value]? = match e.default_values {
    Some(vs) => Some(vs)
    None =>
      if e.is_tty {
        None
      } else if e.ty == TFlag {
        Some([VBool(false)])
      } else if e.ty == TCount {
        Some([VNum(0.0)])
      } else {
        None
      }
  }
  let ty2 = if e.ty == TCount { TNum } else { e.ty }
  build.entities.push({
    name: e.name,
    ty: ty2,
    env_key: None,
    config_seat,
    config_key: e.config_key,
    is_config_file: e.is_config_file,
    inherit_: false, // MDR-003: node.mbt 側 Entity.inherit_
    // DR-099 §1: is_tty/tty_stream/tty_cygwin は ElemDef からそのまま carry するだけ (int_round と
    // 同じパターン) — 専用 installer が後から埋める mutable seat ではない。
    is_tty: e.is_tty,
    tty_stream: e.tty_stream,
    tty_cygwin: e.tty_cygwin,
    accum,
    // DR-105 §1/§3: flatten (append-only dial) and is_multiple_decl (DR-084 §2 origin marker) —
    // both already false-by-construction whenever `accum` is None (the tuple above only ever
    // produces a non-false pair alongside `Some(_)`), mirroring `collector`'s "dead attribute never
    // rides a scalar cell" posture without a redundant guard here.
    flatten,
    is_multiple_decl,
    // DR-036: collector only means anything alongside an accum cell (Entity.collector's doc
    // comment, node.mbt) — a scalar cell (accum is None) drops any declared collector rather than
    // carrying a dead attribute forward.
    collector: if accum is Some(_) {
      e.collector
    } else {
      None
    },
    default_values,
    separator: e.separator,
    piece_filters: e.piece_filters,
    value_filters: e.value_filters,
    // DR-102 §1: final_filters (T→T) only means anything for a scalar (non-accum) cell, accum_filters
    // (Acc→Acc) only for an accum cell — same "drop the attribute that doesn't apply to this cell's
    // shape" posture `collector` above already uses. `collect_invalid_filter_attribute_mismatch`
    // (definition-error, kind=invalid-range) already rejects the OTHER combination at parse_definition
    // time, so in practice at most one side is ever non-empty here; this split is defense-in-depth.
    final_filters: if accum is Some(_) {
      []
    } else {
      e.final_filters
    },
    accum_filters: if accum is Some(_) {
      e.accum_filters
    } else {
      []
    },
    hidden: e.hidden,
    completer: e.completer,
  })
}

///|
fn not_dd(e : ElemDef) -> Bool {
  !e.is_dd
}

// ── 各 installer ─────────────────────────────────────────────────────────────

///|
/// DR-091 §3: `EqSplit` bundles every eq-split entry it carries under ONE `prefix` (`node.mbt`'s
/// `EqSplit(prefix~, entries~)` — a single matcher instance, single prefix). Before this DR every
/// element shared the hardcoded `"--"`, so one `EqSplit` per `Definition` was correct; now an
/// element MAY declare its own `long_prefix` (`if=`/`of=`'s `long_prefix: ""`), so `inst_long`
/// groups eq entries by their declaring element's `long_prefix` and emits one `EqSplit` per
/// distinct value actually present — `prefixes`/`groups` are parallel arrays (insertion order),
/// mirroring this file's existing dedup-by-linear-scan style (`resolve.mbt`'s `named`/`segs`
/// arrays) rather than a `Map` (whose iteration order this codebase doesn't otherwise rely on).
fn eq_group(
  prefixes : Array[String],
  groups : Array[Array[LongEntry]],
  prefix : String,
) -> Array[LongEntry] {
  let mut i = 0
  while i < prefixes.length() {
    if prefixes[i] == prefix {
      return groups[i]
    }
    i = i + 1
  }
  let g : Array[LongEntry] = []
  prefixes.push(prefix)
  groups.push(g)
  g
}

///|
/// long: `long` を READ、name あたり greedy exact 衛星 (space form) と、value 系なら eq-split matcher
/// を add-if-absent で追加。衛星は name で entity に link (DR-042 §展開の標準パターン)。
fn inst_long(
  def : Definition,
  build : Build,
  registry : Map[String, Node],
) -> Unit {
  let eq_prefixes : Array[String] = []
  let eq_groups : Array[Array[LongEntry]] = []
  for e in def.options {
    for l in long_of(e) {
      // DR-091 §3: `e.long_prefix` replaces the old hardcoded `"--"` (既定値は `"--"` そのものなので
      // this element's own trigger is unchanged unless it explicitly overrides).
      let trigger = e.long_prefix + l
      match e.body {
        // MDR-004 §3: BOr option (variable-arity) — greedy satellite
        // Seq([Exact(trigger), Or([branch_node...])]). `e.ty` is unused (a BOr wrapper carries no
        // value of its own); each branch's own leaf name(s) flow through unchanged via
        // or_branch_node/elem_head, so held-Error / binding attribution lands on the leaf with no
        // extra provenance wiring (§4).
        BOr(branches) => {
          let branch_nodes : Array[Node] = []
          for br in branches {
            branch_nodes.push(or_branch_node(br))
          }
          add_greedy(
            build,
            maybe_root(e.link_depth, Seq([Exact(trigger), Or(branch_nodes)])),
          )
        }
        // BEnum (issue values-decode-support, DESIGN §5.3 / DR-028 追記): main entry の値スロット
        // 消費構造が `enum_value_node` (exact 値の or 展開) になる — BCell の `value_prim` に相当する
        // 差し替え。DR-086 §1 の cut (同一 trigger の 0引数 Set variant との競合解決) は lowering
        // 構造 (ここで積む greedy 衛星の個数・形) を変えず eval.mbt 側で扱う (lowering query fixture
        // への影響回避、team-lead 裁定 2026-07-10) — ここでは通常の main entry と同じ形で単独登録
        // するだけでよい。
        BEnum(values) =>
          add_greedy(
            build,
            maybe_root(
              e.link_depth,
              Seq([Exact(trigger), enum_value_node(e.name, e.ty, values)]),
            ),
          )
        _ =>
          match e.ref_target {
            // DR-078 §1 option repeat (issue 2026-07-09-ref-template-result-shape, new
            // capability): mirrors `lower_positional`'s BCell/ref_target arm — a `ref` element's
            // own `name` creates a result scope, and (when repeated) each rep's row groups under
            // a "#row" sentinel (`ref_row_head`, `resolve.mbt`'s ROW-GROUP branch).
            Some(_) =>
              match elem_repeat(e) {
                None =>
                  add_greedy(
                    build,
                    maybe_root(
                      e.link_depth,
                      Seq([
                        Exact(trigger),
                        // DR-084 §1 (issue multiple-ref-accum-gap): a `multiple` repeat-less ref
                        // element's row is the ACCUMULATOR's fold unit (one fire = one row) —
                        // tag it with "#row" (`ref_row_head`, same sentinel repeat-bearing ref
                        // uses) so `resolve.mbt`'s ROW-GROUP branch splits each firing into its
                        // own row-group instead of merging every firing's leaves flat into one
                        // object (the pre-DR-084 bug: 2 fires of an or-branch ref would land BOTH
                        // branches' leaves under the same bare `Scoped(e.name, ...)`, e.g.
                        // `{colorname:"red", r:0, g:128, b:255}` instead of 2 separate rows). No
                        // `multiple` (the `ref-template-no-repeat-degenerate.json` baseline) keeps
                        // the bare `Scoped` wrap — a single scalar row, never array-wrapped.
                        if e.multiple {
                          ref_row_head(e.name, elem_head(e))
                        } else {
                          Scoped(e.name, elem_head(e))
                        },
                      ]),
                    ),
                  )
                Some(_) => {
                  // The repeat spine (mandatory heads + Ref/BoundedTail/Many tail) collapses to
                  // ONE node for `min <= 1` (no mandatory-head unrolling) — the only shape any
                  // fixture exercises today (`last-wins-repeat-rows.json`'s `{"min":1}`). A
                  // `min > 1` option repeat would need `GreedyRepeat` to carry multiple
                  // `sc'.positional` slots (eval.mbt's `step_greedy_repeat`), not yet wired.
                  let spine : Array[Node] = []
                  lower_repeat_head(
                    e,
                    ref_row_head(e.name, elem_head(e)),
                    registry,
                    spine,
                  )
                  let tail = if spine.length() == 1 {
                    spine[0]
                  } else {
                    Seq(spine)
                  }
                  add_greedy(
                    build,
                    maybe_root(
                      e.link_depth,
                      Seq([
                        Exact(trigger),
                        // DR-034 last-wins-whole-cell (multiple 無しの再発火はセル丸ごと上書き):
                        // "#fire" marks this firing's start so `resolve.mbt`'s ROW-GROUP branch
                        // can discard every EARLIER firing's rows wholesale rather than merging
                        // leaf-by-leaf (which would wrongly keep a superseded rep whose position
                        // the later, shorter firing never touched).
                        Scoped(e.name, Bind("#fire", VBool(false))),
                        GreedyRepeat(tail),
                      ]),
                    ),
                  )
                }
              }
            None =>
              // DR-076 §1/§2/§4: every value-typed main entry (bool included, flag ALREADY
              // normalized to TBool by `normalize_option`, DR-076 §2) is a NORMAL value satellite
              // — `:set` always takes a value (space form here; eq form via eq_entries below). A
              // bare `--x` fire (the classic flag shape) needs the explicit `:set:true` variant
              // (decoded as a Set-op Variant with operand VBool(true), lowered by the "Variant
              // entries" loop below, which also carries the fail_action FailMark — flag's
              // presence-only lowering has fully collapsed into that generic variant path; this
              // arm no longer special-cases TFlag/TBool bare-true at all).
              //
              // DESIGN §7.2 / DR-096 §1: `long_eq_sep == EsRequire` withholds THIS space-form main
              // entry — the only entry point left is the eq-split form registered below (`eq_group`
              // push). Paired with `long_prefix: ""` (DR-096 §3.3, node.mbt's `ElemDef.long_prefix`
              // doc comment), this is the mechanism an app can opt into to definitionally eliminate
              // the bare-operand collision: with no space-form trigger, `trigger` (== `l` when
              // `long_prefix` is `""`) never matches a bare token — only `EqSplit`, which fires
              // exclusively on tokens containing `=`, can reach this element. Neither `long_prefix`
              // nor `long_eq_sep` requires this pairing — an unpaired empty prefix is legal and any
              // resulting collision surfaces as Ambiguous instead.
              if e.long_eq_sep != EsRequire {
                // DR-058 §2: a deprecated element's space-form main entry carries a `DeprMark`
                // warning marker after its value slot (node.mbt's `DeprMark` doc shape), mirroring
                // `inst_short`'s `depr: e.deprecated` on the SAME element (`e.deprecated` covers
                // both a directly-deprecated canonical entry and a deprecated alias entry-copy,
                // DR-057 §3 `alias_entry` — both fold into this ONE `ElemDef.deprecated` bool by
                // the time lowering runs, so no alias-specific branch is needed here).
                let sat : Array[Node] = [
                  Exact(trigger),
                  value_prim(
                    e.ty,
                    e.name,
                    e.int_round,
                    e.allow_base_prefix,
                    e.bool_config,
                    e.piece_filters,
                    separator=e.separator,
                    merge=e.accumulator == Some("merge"),
                    kv_map=e.accumulator == Some("kv_map"),
                  ),
                ]
                if e.deprecated {
                  sat.push(DeprMark(e.name))
                }
                add_greedy(build, maybe_root(e.link_depth, Seq(sat)))
              }
          }
      }
      // eq-split value form (`--key=value`): every value-typed main entry gets this (bool included,
      // DR-076 §1) — a flag's default sugar carries NO main entry at all (`e.long` stays [], DR-076
      // §2), so this loop never runs for a bare classic flag; an explicit `long:[":set"]` flag DOES
      // register its value-slot form here, coexisting with the bare `:set:true` variant (DR-076 §2
      // "value形+裸の同居"). DR-076 §3: TBool's variant-guard exclusion (eq-split withheld when the
      // element ALSO carries `--x`/`--no-x` variant spellings) is REPEALED — bool's eq-split and
      // variant triggers coexist (fixtures/lowering/long/variant.json's ssl: `--ssl=false` fires
      // alongside `--ssl`/`--no-ssl`).
      // DR-075 §2: TInt の eq-split (`--v=2.5`) が factory config int_round を反映するよう、
      // ElemDef.int_round を LongEntry に持ち込む (TInt 以外は entry 側で参照されない)。
      // MDR-004 §3: a BOr element's eq-split registers only for a single-value-cell branch (using
      // that leaf's own name/ty/int_round/allow_base_prefix, never the wrapper's) — a multi-cell
      // branch's `=` form is undefined (`--color=v` cannot supply 3 leaves).
      // DR-091 §2: a `kv_map`-accumulator leaf does NOT register an eq-split entry (unlike merge,
      // which shares the same `sep_binds` pipeline as the space form) — `run_eq_split` (matcher.mbt)
      // builds its binding through `sep_binds`, which has no "the piece must contain `=`" gate (that
      // gate lives in the `KvArg` node, `value_prim`'s dedicated kv_map branch, which `LongEntry`
      // never routes through). Registering here would let `--define=NOEQUALSIGN` silently produce
      // `{NOEQUALSIGN: ""}` instead of DR-091 §2's required Reject — same deliberate-absence posture
      // as `BEnum`'s "OUT OF SCOPE" comment below, not an oversight.
      //
      // DR-014「--name=value の許可」/ DESIGN §7.2 / DR-096 §1: `e.long_eq_sep` (scope config,
      // decode-time baked — always the WRAPPING option's resolved value, never a BOr leaf's unbaked
      // default, same reasoning `eq_group(..., e.long_prefix)` already applies below) gates every
      // arm — `EsDeny` withholds the eq-split entry entirely, leaving only the space form registered
      // above.
      match e.body {
        BOr(branches) =>
          for br in branches {
            if br.items.length() == 1 {
              let leaf = br.items[0]
              if e.long_eq_sep != EsDeny && leaf.accumulator != Some("kv_map") {
                eq_group(eq_prefixes, eq_groups, e.long_prefix).push({
                  key: l,
                  name: leaf.name,
                  kind: leaf.ty,
                  int_round: leaf.int_round,
                  allow_base_prefix: leaf.allow_base_prefix,
                  bool_config: leaf.bool_config,
                  piece_filters: leaf.piece_filters,
                  separator: leaf.separator,
                  merge: leaf.accumulator == Some("merge"),
                })
              }
            }
          }
        BGroup(_) => () // positional-only shape (MDR-004 §3 scope) — no long spelling applies
        BCell =>
          // DR-076 §2: no `e.ty != TFlag` guard needed here anymore — a classic flag never reaches
          // this loop body at all (its `e.long` is empty, `long_of(e)` yields no `l` to iterate), so
          // the guard was always vacuous for it; an explicit `long:[":set"]` flag (now TBool) SHOULD
          // register its eq-split form, which this unconditional push now does correctly (the guard
          // used to wrongly suppress it while `e.ty` still read TFlag pre-normalize_option).
          if e.long_eq_sep != EsDeny && e.accumulator != Some("kv_map") {
            eq_group(eq_prefixes, eq_groups, e.long_prefix).push({
              key: l,
              name: e.name,
              kind: e.ty,
              int_round: e.int_round,
              // DR-074 §2: TNum / TInt の eq-split (`--v=0xff`) も factory config を反映するよう
              // ElemDef から LongEntry に持ち込む (他 kind は entry 側で参照されない)。
              allow_base_prefix: e.allow_base_prefix,
              // DR-074 §4: TBool の eq-split (`--enabled=yes`) も bool_parser factory config を反映
              // (DR-076 §3 でこの eq-split は variant 綴りと共存する — TFlag と違い抑制されない)。
              bool_config: e.bool_config,
              piece_filters: e.piece_filters,
              separator: e.separator,
              merge: e.accumulator == Some("merge"),
            })
          }
        // BEnum (issue values-decode-support): eq-split (`--color=always`) for an enum-constrained
        // cell is OUT OF SCOPE for this issue (no target fixture exercises `--key=value` against a
        // `values`/`or` value-enum element) — `EqSplit`'s `LongEntry.kind : Ty` carrier has no slot
        // for "enum of these strings", only a plain value-primitive type. Registering nothing here
        // means `--color=always` simply doesn't match this entry (falls through to whatever else
        // recognizes the raw token, most likely unexpected_token) rather than silently accepting an
        // UNvalidated value via a `Ty`-based fallback — deliberately absent, not deliberately wrong.
        BEnum(_) => ()
      }
    }
  }
  // DR-091 §3: emit one `EqSplit` matcher PER DISTINCT `long_prefix` seen (was: a single
  // `EqSplit(prefix="--", ...)` for the whole Definition — `eq_group`'s doc comment).
  let mut gi = 0
  while gi < eq_prefixes.length() {
    if eq_groups[gi].length() > 0 {
      add_greedy(
        build,
        NativeMatch(EqSplit(prefix=eq_prefixes[gi], entries=eq_groups[gi])),
      )
    }
    gi = gi + 1
  }
  // Variant entries (DR-011 / DR-045): `{exact, link (by name), effect}` に lowering。
  // `set` variant は Bind (SET degenerate); default/unset/empty は EffMark (0-token effect)。
  // DR-076 §2/§4: a flag's classic bare-fire trigger IS a Set variant now (`:set:true`, composed in
  // by dec_long) — it rides through here, not through the old TFlag-only branch above. A fail_action
  // element (DR-048, e.g. help) additionally emits a FailMark alongside its Set variant's Bind, so
  // this loop must carry the SAME fail_action attachment the collapsed TFlag branch used to (a
  // fail_action flag firing here — its ONLY main-entry shape post-DR-076 §2 — must still be able to
  // select as a failed-parse action).
  for e in def.options {
    for v in e.variants {
      // issue scope-config-object-gap codex 指摘 Major 2: main entry (inst_long 冒頭) と eq-split
      // (eq_group) は既に e.long_prefix を使う — variant だけ "--" 固定だと同一 option family の
      // 綴りが long_prefix 非既定時に分裂する (DR-091 §3 の一貫性を variant にも及ぼす)。既定
      // "--" なので既存挙動 (main entry と揃った "--" 綴り) は不変。
      let trigger = e.long_prefix + v.trigger
      // DR-058 §2: a deprecated element's variant satellite (Set's Bind OR a non-Set EffMark) also
      // carries a trailing `DeprMark` — every long entry point this element owns fires the SAME
      // warning, symmetric with `inst_short`'s per-char `depr: e.deprecated` (a short cluster char
      // has no variant/main-entry split, so ONE application point covers it; long's split into
      // main-entry (above) + variant (here) needs both covered for parity).
      let nodes : Array[Node] = match v.op {
        Set => {
          let operand = match v.operand {
            Some(val) => val
            None => VBool(true)
          }
          if e.fail_action {
            [Exact(trigger), Bind(e.name, operand), FailMark(e.name)]
          } else {
            [Exact(trigger), Bind(e.name, operand)]
          }
        }
        _ => [Exact(trigger), EffMark(e.name, v.op)]
      }
      if e.deprecated {
        nodes.push(DeprMark(e.name))
      }
      add_greedy(build, maybe_root(e.link_depth, Seq(nodes)))
    }
  }
}

///|
/// global link COPY (link_depth > 0) を `Rooted(node, depth)` で包む — bindings が declaring scope の
/// entity に landing するよう escape する (DR-042 link-sync)。link_depth == 0 は自宣言で wrap しない。
fn maybe_root(link_depth : Int, node : Node) -> Node {
  if link_depth > 0 {
    Rooted(node, link_depth)
  } else {
    node
  }
}

///|
/// DESIGN §7.2 / LOWERING §B.2: mirrors `eq_group` (long installer, DR-091 §3) — bundles every
/// short-cluster entry under ONE `(short_prefix, short_combine)` PAIR per `ShortCombine` matcher
/// instance. Keying on the pair (not `short_prefix` alone) matters because a `Definition`'s
/// `def.options` can mix elements from 2 sources with different defaults: elements decoded in THIS
/// scope (uniform `short_prefix`/`short_combine`, both baked from the SAME resolved `ScopeConfig`
/// by `dec_definition`) and elements COPIED in from elsewhere (`add_inheritable_copy`/`alias_entry`,
/// which hardcode the canonical defaults `"-"`/`true` regardless of the current scope's config,
/// mirroring `long_prefix`'s existing "--" hardcode at those same call sites). If 2 elements
/// disagreed on `short_combine` while sharing `short_prefix`, merging them into ONE matcher would
/// require inventing a tie-break policy (spec is silent) — keying on the pair instead routes each
/// distinct combination to its own matcher, so no policy is ever needed.
fn short_group(
  prefixes : Array[String],
  combines : Array[Bool],
  groups : Array[Array[ShortEntry]],
  prefix : String,
  combine : Bool,
) -> Array[ShortEntry] {
  let mut i = 0
  while i < prefixes.length() {
    if prefixes[i] == prefix && combines[i] == combine {
      return groups[i]
    }
    i = i + 1
  }
  let g : Array[ShortEntry] = []
  prefixes.push(prefix)
  combines.push(combine)
  groups.push(g)
  g
}

///|
/// short: `short` を READ、cluster/value-attach matcher を 1 本 add-if-absent。PoC では single-char
/// (`-v`, `-p 8080`) も matcher に集約するため、short は独立 exact 衛星を発しない (matcher-seat)。
/// DESIGN §7.2: `e.short_prefix` replaces the old hardcoded `"-"` — one `ShortCombine` matcher PER
/// DISTINCT `(short_prefix, short_combine)` pair actually present (was: a single
/// `ShortCombine(prefix="-", ...)` for the whole `Definition`), same generalization DR-091 §3
/// already applied to `inst_long`/`EqSplit`. `e.short_combine` (issue scope-config-object-gap
/// 解釈A, team-lead 裁定 2026-07-11) rides straight through to the matcher's `combine` param —
/// `run_short`/`walk_short` (matcher.mbt) are the sole consumers of the flag's actual meaning.
fn inst_short(def : Definition, build : Build) -> Unit {
  let sh_prefixes : Array[String] = []
  let sh_combines : Array[Bool] = []
  let sh_groups : Array[Array[ShortEntry]] = []
  for e in def.options {
    for c in e.short {
      // DR-058: deprecated alias entry-copy は cluster entry でも警告する
      // DR-075 §2: short cluster / space-tail 経路の TInt (`-n1.5` / `-n 1.5`) も factory config を反映
      short_group(
        sh_prefixes,
        sh_combines,
        sh_groups,
        e.short_prefix,
        e.short_combine,
      ).push({
        ch: c,
        name: e.name,
        kind: e.ty,
        depr: e.deprecated,
        int_round: e.int_round,
        // DR-074 §2: short cluster / space-tail の TNum / TInt も allow_base_prefix を反映
        allow_base_prefix: e.allow_base_prefix,
        piece_filters: e.piece_filters,
        separator: e.separator,
        merge: e.accumulator == Some("merge"),
        // DESIGN §7.2 / DR-096 §2: walk_short (matcher.mbt) の唯一の消費者
        short_attached_value: e.short_attached_value,
        // DR-104 §2/§3: complete() の CandMeta.is_alias 直訳元 (depr と同じ carrier パターン)。
        is_alias: e.is_alias,
      })
    }
  }
  let mut gi = 0
  while gi < sh_prefixes.length() {
    if sh_groups[gi].length() > 0 {
      add_greedy(
        build,
        NativeMatch(
          ShortCombine(
            prefix=sh_prefixes[gi],
            entries=sh_groups[gi],
            combine=sh_combines[gi],
          ),
        ),
      )
    }
    gi = gi + 1
  }
}

///|
/// env: `env` を READ、entity の env seat に登録 (invariant ④)。ladder 順序は engine 所有 (DR-031)、
/// default_fn を wrap しない。同 seat 再宣言は no-op (idempotent in-place set)。
fn inst_env(def : Definition, build : Build) -> Unit {
  for e in def.options {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
    }
  }
  for e in def.positionals {
    if e.env.length() > 0 {
      seat_env(build, e.name, e.env[0])
    }
  }
}

///|
fn seat_env(build : Build, name : String, key : String) -> Unit {
  for ent in build.entities {
    if ent.name == name {
      ent.env_key = Some(key)
    }
  }
}

///|
/// dd: `type:"dd"` を READ、greedy exact 衛星 (DdSat) を add-if-absent (DR-041 rev)。fire 時に spine
/// walk が「severed」モードに切り替わり以降 greedy off — greedy internal consumption 一体化ルール。
///
/// DR-064 §2 配置不問回収: dd は canonical には options[] だが positionals[] に置いても回収する
/// (env / inherit と同じく両 face を walk する対称形)。add-if-absent (add_greedy) が重複宣言を collapse。
fn inst_dd(def : Definition, build : Build) -> Unit {
  // DR-064 §5: dd の name は trigger 綴りに効く (normalize_surface が既定 "--" を供給、明示は上書き)。
  // DR-090 §2: `dd_match` が None かつ `dd_self_keep` が false (両軸とも既定) の要素だけ、既存
  // `DdSat` (exact/drop 専用ノード) をそのまま使う — 完全な後方互換 (既存 wbtest の `DdSat("--")`
  // 手組みと構造一致し続ける)。どちらかの軸が既定から外れたら一般化ノード `DdMatchSat` を積む
  // (`match` が Some のとき name はトリガ綴りに使われない、§2 の規定通り `e.name` の代わりに
  // `dd_match` の pattern を spelling に使う)。
  fn dd_node(e : ElemDef) -> Node {
    if e.dd_match is None && !e.dd_self_keep {
      DdSat(e.name)
    } else {
      match e.dd_match {
        Some(pattern) => DdMatchSat(pattern, true, e.dd_self_keep, e.name)
        None => DdMatchSat(e.name, false, e.dd_self_keep, e.name)
      }
    }
  }

  for e in def.options {
    if e.is_dd {
      add_greedy(build, dd_node(e))
    }
  }
  for e in def.positionals {
    if e.is_dd {
      add_greedy(build, dd_node(e))
    }
  }
}

///|
/// add-if-absent (invariant ①' 非削除): 構造等価な既存があれば追加しない。再適用を no-op に、fixpoint
/// を収束させる。
fn add_greedy(build : Build, g : Node) -> Unit {
  for existing in build.greedy {
    if existing == g {
      return
    }
  }
  build.greedy.push(g)
}

///|
/// inherit: `inherit` を READ、entity に inherit seat を宣言 (invariant ④, DR-031 cli>env>inherit>default)。
/// seat の実 lookup 「最近祖先の同名 entity 値」は runtime (resolve_scope) で解く。env と対称の seat 宣言型。
fn inst_inherit(def : Definition, build : Build) -> Unit {
  for e in def.options {
    if e.is_inherit {
      seat_inherit(build, e.name)
    }
  }
  for e in def.positionals {
    if e.is_inherit {
      seat_inherit(build, e.name)
    }
  }
}

///|
fn seat_inherit(build : Build, name : String) -> Unit {
  for ent in build.entities {
    if ent.name == name {
      ent.inherit_ = true // MDR-003
    }
  }
}

///|
/// global: `global` を READ、option 宣言を子孫 command scope の宣言層にコピー (invariant ②)。
/// long/short は次 pass 以降で子で展開する。shadowing (DR-032/033, 最小 scope): 子が同トリガを既に
/// 宣言していれば copy しない (自前が勝つ)。copy は `is_global` を保持し、fixpoint で更に下位へ再伝播。
fn inst_global(sb : SB) -> Unit {
  for opt in sb.decl.options {
    if opt.is_global {
      for child in sb.children {
        copy_global_into(child.body, opt)
      }
    }
  }
}

///|
fn copy_global_into(child : SB, opt : ElemDef) -> Unit {
  for existing in child.decl.options {
    if triggers_overlap(existing, opt) {
      return // shadow または既に copy 済 (idempotent, トリガ基準)
    }
    // DR-057 alias 併用パターン (canonical 側は global だがトリガを持たない = long/short/variants
    // 全て空で、alias 側だけが実際のトリガを別要素として持つ) で発見: `triggers_overlap` は両者とも
    // トリガ集合が空だと常に false を返すため、上のチェックだけでは「既にコピー済みの trigger-less
    // canonical」を検出できず、fixpoint のたびに同じ要素を再コピーし続けて収束しない
    // (installer chain did not converge)。同名 + link_depth>0 (= コピー由来) の既存要素があれば、
    // idempotent とみなす — ただし判定はトリガ集合も一致する場合に限る (codex 指摘、実機確認済み
    // regression: 同名だが**別トリガ**の 2 つの global が祖先チェーンの異なる段でそれぞれ独立に宣言
    // されている場合、`name` だけで判定すると先にコピーされた方が後続の別トリガ copy を誤って
    // 抑止し、孫スコープへ一方のトリガが伝播しなくなる — conformance の parse() 経由テストでは
    // DR-041 §4 早閉じ+porous が観測結果を偶然保存してしまい検出できなかったため、`materialize` 後
    // の Scope 構造 (Rooted 衛星の本数) を直接検査する wbtest で確認した)。トリガ集合が両方とも
    // 空集合の場合は「集合一致」も自明に成立するので、元の trigger-less canonical バグの修正は
    // このまま維持される。
    if existing.name == opt.name &&
      existing.link_depth > 0 &&
      trigger_sets_equal(existing, opt) {
      return
    }
  }
  // copy は link 衛星 (DR-042): declaring scope の entity を bind (子は自 cell を持たない)。
  // link_depth = declaring scope からの段数 (+1 per re-propagation)。long/short が Rooted(node, depth)
  // で wrap する。
  //
  // INVARIANT (install-time count ↔ eval-time decrement, 現制約): この +1 は SCOPE (name/command) copy
  // level のみ数える (copy_global_into 1 段につき 1)。eval 側の Rooted `link` counter は 2 種の nesting
  // (nest = scope 段 / nest_index = rep #k 段) で減算される。したがって「link_depth == 衛星と declaring
  // scope の間の eval nesting 段数」の不変条件は「Rooted 衛星が IdxRepeat の下に置かれない」条件下でのみ
  // 成立する — 現行 lowering は Rooted を scope spine で wrap し、repeat head 内には入れないので満たす。
  // 将来 nested-group が scope/global を repeat 群に許容するなら、この +1 に rep-nesting depth も加算する。
  let copy = clone_elem(opt)
  child.decl.options.push({
    name: copy.name,
    ty: copy.ty,
    long: copy.long,
    variants: copy.variants,
    short: copy.short,
    env: copy.env,
    is_tty: copy.is_tty,
    tty_stream: copy.tty_stream,
    tty_cygwin: copy.tty_cygwin,
    is_dd: copy.is_dd,
    is_exact: copy.is_exact,
    dd_match: copy.dd_match,
    dd_self_keep: copy.dd_self_keep,
    is_global: copy.is_global,
    is_inherit: copy.is_inherit,
    is_inheritable: copy.is_inheritable,
    link_depth: copy.link_depth + 1,
    ref_target: copy.ref_target,
    repeat: copy.repeat,
    optional: copy.optional,
    multiple: copy.multiple,
    accumulator: copy.accumulator,
    flatten: copy.flatten,
    separator: copy.separator,
    collector: copy.collector,
    fail_action: copy.fail_action,
    is_config_file: copy.is_config_file,
    config_key: copy.config_key,
    export_key: copy.export_key,
    requires: copy.requires,
    conflicts_with: copy.conflicts_with,
    exclusive_group: copy.exclusive_group,
    required_group: copy.required_group,
    required: copy.required,
    value_requires: copy.value_requires,
    deprecated: copy.deprecated,
    is_alias: copy.is_alias,
    hidden: copy.hidden,
    completer: copy.completer,
    default_values: copy.default_values,
    int_round: copy.int_round,
    allow_base_prefix: copy.allow_base_prefix,
    bool_config: copy.bool_config,
    piece_filters: copy.piece_filters,
    value_filters: copy.value_filters,
    final_filters: copy.final_filters,
    accum_filters: copy.accum_filters,
    long_prefix: copy.long_prefix,
    short_prefix: copy.short_prefix,
    env_prefix: copy.env_prefix,
    auto_env: copy.auto_env,
    long_eq_sep: copy.long_eq_sep,
    short_combine: copy.short_combine,
    short_attached_value: copy.short_attached_value,
    body: copy.body,
  })
}

///|
/// An element's every long CLI trigger spelling (kebab, sans `--` prefix) — `long_of` (the resolved
/// `:set` main entry, post `resolve_long`) AND `variants` (each colon-DSL variant's own trigger,
/// DR-011/076) combined. The two arrays are just WHERE a spelling landed post-`resolve_long`
/// (main-entry sentinel vs. colon-DSL variant); the actual `--xxx` wire spelling they produce is the
/// same kind of string either way, so any trigger-identity comparison (`triggers_overlap`) must look
/// at both together — otherwise the SAME spelling can hide in `long` on one element and `variants` on
/// the other (e.g. a flag's `:set:true` composed bare-fire trigger lands in `variants`, DR-076 §2,
/// while a plain `:set` main entry lands in `long`) and a real collision goes undetected.
fn all_long_triggers(e : ElemDef) -> Array[String] {
  let out : Array[String] = []
  for l in long_of(e) {
    out.push(l)
  }
  for v in e.variants {
    out.push(v.trigger)
  }
  out
}

///|
/// 2 要素のトリガ集合が完全一致するか (順序無視、`all_long_triggers` の集合として比較)。
/// `copy_global_into` の idempotent 判定 (同名 + コピー由来 + トリガ集合一致) 専用 — トリガ集合が
/// 両方とも空なら自明に一致する (trigger-less canonical の idempotent 判定を保つ)。
fn trigger_sets_equal(a : ElemDef, b : ElemDef) -> Bool {
  let ta = all_long_triggers(a)
  let tb = all_long_triggers(b)
  if ta.length() != tb.length() {
    return false
  }
  for t in ta {
    if !str_in(tb, t) {
      return false
    }
  }
  true
}

///|
/// トリガ衝突: 2 option が long / short / long variant いずれかを共有すれば衝突 (shadow はトリガ基準 =
/// 同名トリガ)。long の main entry と variant は格納場所が違うだけで同じ trigger 語彙 (`all_long_triggers`
/// 参照) なので、比較は両者を合わせた集合同士で行う。
fn triggers_overlap(a : ElemDef, b : ElemDef) -> Bool {
  for ta in all_long_triggers(a) {
    for tb in all_long_triggers(b) {
      if ta == tb {
        return true
      }
    }
  }
  for ca in a.short {
    for cb in b.short {
      if ca == cb {
        return true
      }
    }
  }
  false
}

// ── driver + completeness ────────────────────────────────────────────────────

///|
/// 1 scope node に 1 installer を適用。long/short/env/dd/inherit は当該 node の build に貢献。
/// global は子孫の宣言層にコピー。command は materialize 段で wire (展開は決定的 — DR-018 / DR-041 §4)。
fn apply_node(inst : Installer, sb : SB, registry : Map[String, Node]) -> Unit {
  match inst {
    LongInst => inst_long(sb.decl, sb.build, registry)
    ShortInst => inst_short(sb.decl, sb.build)
    EnvInst => inst_env(sb.decl, sb.build)
    DdInst => inst_dd(sb.decl, sb.build)
    InheritInst => inst_inherit(sb.decl, sb.build)
    GlobalInst => inst_global(sb)
    CommandInst => () // materialize で wire
    RepeatInst => () // init_sb で決定的に lower (Ref 再帰 + template)
    MultipleInst => () // ensure_entity で accumulator flag を決定的に set
    ConfigInst => () // ensure_entity で config seat を決定的に set (席宣言型 DR-050/042 ④)
    ConstraintInst => inst_constraint(sb.decl, sb.build, registry)
    AliasInst => () // desugar_aliases (init_sb 前) で決定的に展開 — entry-copies は fixpoint で long/short/command が展開
    InheritableInst => inst_inheritable(sb)
  }
}

///|
/// inheritable installer (DR-059): global の REVERSE 方向。子孫の inheritable 要素を全祖先 scope に
/// `<定義スコープ名>-<name>` 綴りでコピー (§1)。祖先の `--socket-ttl` が祖先 `ttl` cell に bind。
/// 全 `ttl` cell (定義 + 祖先コピー) に inherit seat が立つので、任意層の値が子孫の default として流れ下る
/// (§3 値意味論 — inherit seat の対 DR-031)。祖先が同トリガを自宣言なら shadow で copy しない (global 対称)。
fn inst_inheritable(sb : SB) -> Unit {
  // (1) 子孫の inheritable → THIS (祖先) scope の宣言層に prefixed write-entry を追加
  let entries : Array[(String, ElemDef)] = []
  gather_inheritable(sb.children, entries)
  for de in entries {
    let defining_name = de.0
    let e = de.1
    let trigger = defining_name + "-" + e.name // 全祖先同綴り (§1)
    add_inheritable_copy(sb, e, trigger)
  }
  // (2) subtree の inheritable 対象名 (自宣言 + 祖先コピー) 全てに inherit seat を打つ (§3)
  let names : Array[String] = []
  for e in sb.decl.options {
    if e.is_inheritable && !str_in(names, e.name) {
      names.push(e.name)
    }
  }
  for de in entries {
    if !str_in(names, de.1.name) {
      names.push(de.1.name)
    }
  }
  for name in names {
    seat_inherit(sb.build, name)
  }
}

///|
/// 子孫 scope の inheritable 要素を全て回収 (定義スコープ名で tag — §1 の prefix)。全 subtree を再帰。
fn gather_inheritable(
  children : Array[SBChild],
  out : Array[(String, ElemDef)],
) -> Unit {
  for ch in children {
    for e in ch.body.decl.options {
      if e.is_inheritable {
        out.push((ch.name, e))
      }
    }
    gather_inheritable(ch.body.children, out)
  }
}

///|
/// 祖先 scope の宣言層に prefixed write-entry を追加 (add-if-absent, shadow-aware)。祖先が同トリガを
/// 既に宣言 (§3 global 対称 shadow) なら copy しない。DR-076 後は裸発火トリガが `variants` 側に入る
/// (例: alias `[":set:true"]` 由来) ため、`long_of` (main long のみ) ではなく `all_long_triggers`
/// (long + variants 横断) で判定する必要がある — codex 指摘、実機確認済み regression: alias が
/// variants 側で提供するトリガを `long_of` だけでは見落とし、同じ綴りの inheritable コピーを重複
/// 追加してしまう (materialize 後の Scope に同一トリガの greedy 衛星が 2 本立つ)。
fn add_inheritable_copy(sb : SB, e : ElemDef, trigger : String) -> Unit {
  for existing in sb.decl.options {
    if str_in(all_long_triggers(existing), trigger) {
      return // 自前優先 (shadow) / 既 copy (idempotent)
    }
  }
  sb.decl.options.push({
    name: e.name, // 祖先 write-target cell は要素名共有 (inherit-by-name)
    ty: e.ty,
    long: LList([trigger]), // prefixed inheritable trigger (post-normalize 相当の確定形、resolve_long を経由しない)
    variants: [],
    short: [],
    env: [],
    is_tty: false, // write-target copy は tty preset を持たない (env_prefix と同じ「canonical default 相当」)
    tty_stream: None,
    tty_cygwin: true,
    is_dd: false,
    is_exact: false,
    dd_match: None,
    dd_self_keep: false,
    is_global: false,
    is_inherit: false, // inherit seat は inst_inheritable step(2) が立てる
    is_inheritable: false, // copy 自体は plain entry (再伝播しない)
    link_depth: 0,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple: false,
    accumulator: None,
    flatten: None,
    separator: None,
    collector: None,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    required_group: [],
    required: false, // write-target copy は required 制約を持たない (requires/exclusive_group と同じ理由)
    value_requires: [],
    deprecated: false,
    is_alias: false, // write-target copy は alias/hidden 宣言経路を持たない (canonical default 相当)
    hidden: false,
    completer: None, // write-target copy は completer 宣言経路を持たない (hidden と同じ理由)
    default_values: None, // write-target に default を置かない (§3): 実書き込みのみが伝播する
    int_round: RError, // canonical default (DR-075 §2): write-target は int_round を持たない
    allow_base_prefix: false, // canonical default (DR-074 §2): write-target は base prefix opt-in を持たない
    bool_config: bool_config_canonical(), // canonical default (DR-074 §4): write-target は bool_parser opt-in を持たない
    piece_filters: [], // write-target は filter chain を持たない (源 e の value_filters は source 側で既に適用済み)
    value_filters: [],
    final_filters: [],
    accum_filters: [],
    long_prefix: "--", // 通常の long 綴り (kebab, 未 prefix) — inst_long が既定 "--" を前置する
    short_prefix: "-", // write-target copy は short spelling を持たない (canonical default 相当)
    env_prefix: "", // write-target copy は env 席を持たない (canonical default 相当)
    auto_env: false,
    long_eq_sep: EsAllow, // canonical default (§3 と同じ「通常挙動」)
    short_combine: true, // canonical default
    short_attached_value: AtAllow, // canonical default
    body: BCell,
  })
}

///|
/// `node` が値を束縛する全ての leaf name を再帰的に集める (DR-093 の or/ref 親充足判定の実体解決 —
/// `required_candidates` の `ref_target` 分岐が使う)。値プリミティブ (`StrArg`/`SepArg`/`KvArg`/
/// `NumArg`/`FloatArg`/`IntArg`/`BoolArg`/`ReqArg`) の name フィールドが対象。`Or`/`Seq`/`Many`/
/// `BoundedTail`/`Rooted`/`Scoped`/`GreedyRepeat`/`IdxRepeat` は値バインディングを持たない構造
/// ラッパーなので内部を再帰的に辿る。`Ref` は registry を辿って参照先テンプレートに再帰する
/// (`visiting` は `head_cycles` と同じ「訪問済み template 名」防御 — 循環 ref は
/// `collect_circular_ref` が別途 definition-error で弾く前提だが、防御的に無限再帰を避ける)。
/// `Exact`/`Bind`/`EffMark`/`DeprMark`/`FailMark`/`DdSat`/`DdMatchSat`/`CmdSat`/`NativeMatch`/
/// `FilterArg`/`ScopeNode` は値を束縛しない (トリガ・0-token マーク・test-only node・ネストスコープ
/// 自体) ので無視する。
fn collect_value_names(
  node : Node,
  registry : Map[String, Node],
  visiting : Array[String],
  out : Array[String],
) -> Unit {
  match node {
    StrArg(n, _)
    | SepArg(n, _, _, _, _, _, _, _)
    | KvArg(n, _)
    | NumArg(n, _, _)
    | FloatArg(n, _)
    | IntArg(n, _, _, _)
    | BoolArg(n, _, _)
    | ReqArg(n) => out.push(n)
    Or(alts) =>
      for a in alts {
        collect_value_names(a, registry, visiting, out)
      }
    Seq(items) =>
      for it in items {
        collect_value_names(it, registry, visiting, out)
      }
    Many(inner, _) => collect_value_names(inner, registry, visiting, out)
    BoundedTail(inner, _, _) =>
      collect_value_names(inner, registry, visiting, out)
    Rooted(inner, _) => collect_value_names(inner, registry, visiting, out)
    Scoped(_, inner) => collect_value_names(inner, registry, visiting, out)
    GreedyRepeat(inner) => collect_value_names(inner, registry, visiting, out)
    IdxRepeat(_, inner, _, _) =>
      collect_value_names(inner, registry, visiting, out)
    Ref(r) =>
      if !str_in(visiting, r) {
        match registry.get(r) {
          Some(tpl) => {
            visiting.push(r)
            collect_value_names(tpl, registry, visiting, out)
            let _ = visiting.pop()
          }
          None => ()
        }
      }
    _ => ()
  }
}

///|
/// DR-093 §1/§2 の型委譲判定が「値が実際に着地する cell」を見るための候補セル解決 (codex レビュー
/// M-2 修正): 宣言要素 `e` そのものが値を持つとは限らない。
///
/// `e.ref_target` が `Some(_)` (ref 要素) のとき、`e.body` は常に `BCell` のまま (ref 展開は
/// registry 上の `Node` として存在し、`ElemDef.body` には反映されない —
/// `ensure_entity_body`/`elem_head` の doc comment 参照)。参照先テンプレートが structural or の
/// ような複合構造を持つ場合、`e.name` というセルは結果に存在せず (DR-025 の露出規則)、値は展開後の
/// 枝の leaf entity に着地する — `collect_value_names` で registry 上の実体を辿って候補集合を得る
/// (DR-007「ref は構造定義全てを引き継ぐ」の型委譲判定への反映)。
///
/// `e.ref_target` が `None` かつ `e.body` が `BOr` (直書き structural or、型付き枝) のときは、BOr
/// wrapper 自身 (`e.name`) は値を持たない構造ディスパッチャで (ensure_entity_body の BOr コメント
/// 参照)、値は選ばれた枝の leaf entity にのみ commit される。候補集合を各枝の leaf name に展開し、
/// 「どの枝であれ発火して値が確定していれば充足」(DR-093 の or 親充足の型委譲原理) を呼び出し側
/// (`CRequired`/`CRequiredGroup`) の判定に持ち込む。BEnum (value-enum 形) は全枝が SAME name/cell
/// (`e.name`) に着地するためこの展開は不要 (`[e.name]` のままで元々正しい — 対照 fixture
/// `required-value-enum-or-branch.json` が既に green なのはこのため)。
///
/// `CRequired` (required 単項) と `CRequiredGroup` (required_group, DR-103) の両方がこのヘルパーを
/// 共有することで、「required 単項と required_group で候補セル解決が食い違う」構造的な余地を無くす
/// (M-2 の再発防止、issue codex-review-dr102-dr103-postland)。
///
/// 戻り値は `RequiredCandidate` (name + wrapper) — ref 経由の場合、値は宣言元 `e` 自身の Scoped
/// 部分木 (`Scoped(e.name, ...)`、`inst_long`/`lower_positional` の ref 分岐が作る) に着地するため、
/// `wrapper: Some(e.name)` を付けて判定側 (`eval.mbt`/`resolve.mbt`) が「宣言元要素自身の部分木内」
/// だけを探すようにする (DESIGN §2.4/2.5 の露出規則、無制限透過ではなく要素自身の部分木に限定 —
/// `RequiredCandidate` の doc comment 参照)。直書き BOr の場合、値は親 scope に直接 bind されるため
/// `wrapper: None`。
fn required_candidates(
  e : ElemDef,
  registry : Map[String, Node],
) -> Array[RequiredCandidate] {
  match e.ref_target {
    Some(r) => {
      let names : Array[String] = []
      collect_value_names(Ref(r), registry, [], names)
      if names.length() > 0 {
        let out : Array[RequiredCandidate] = []
        for n in names {
          out.push({ name: n, wrapper: Some(e.name) })
        }
        out
      } else {
        [{ name: e.name, wrapper: None }]
      }
    }
    None =>
      match e.body {
        BOr(branches) => {
          let out : Array[RequiredCandidate] = []
          for br in branches {
            for it in br.items {
              out.push({ name: it.name, wrapper: None })
            }
          }
          out
        }
        _ => [{ name: e.name, wrapper: None }]
      }
  }
}

///|
/// constraint installer (DR-055 / DR-042 席宣言型): requires / conflicts_with / exclusive_group /
/// required / required_group (DR-103) / value_requires を scope の遅延述語として登録。構造衛星は
/// 無し (DR-047 完全 path の最終状態で評価)。
fn inst_constraint(
  def : Definition,
  build : Build,
  registry : Map[String, Node],
) -> Unit {
  let all : Array[ElemDef] = []
  for e in def.options {
    all.push(e)
  }
  for e in def.positionals {
    all.push(e)
  }
  for e in all {
    if e.requires.length() > 0 {
      add_constraint(build, CRequires(e.name, copy_strs(e.requires)))
    }
    if e.conflicts_with.length() > 0 {
      add_constraint(build, CConflicts(e.name, copy_strs(e.conflicts_with)))
    }
    if e.required {
      // DR-093 §1/§2: required:true の要素自身を対象にした CRequired を 1 個登録。候補セル解決は
      // `required_candidates` (CRequiredGroup と共有)。
      add_constraint(build, CRequired(e.name, required_candidates(e, registry)))
    }
    for vr in e.value_requires {
      // DR-055 §1 / DR-052 §値枝 id 直交: 4-tuple = (entity, branch_id, value, targets)。entity は
      // committed 判定 / 値照合の対象 (親 name)、branch_id は違反時の error.element (枝の id)。
      add_constraint(build, CRequiresIf(e.name, vr.0, vr.1, copy_strs(vr.2)))
    }
  }
  // exclusive_group: label per scope でメンバを集約 → 1 CExclusive per label
  let groups : Array[String] = []
  for e in all {
    for g in e.exclusive_group {
      if !str_in(groups, g) {
        groups.push(g)
      }
    }
  }
  for g in groups {
    let members : Array[String] = []
    for e in all {
      if str_in(e.exclusive_group, g) {
        members.push(e.name)
      }
    }
    add_constraint(build, CExclusive(g, members))
  }
  // required_group (DR-103 §1/§3/§7 修正、codex M-2): exclusive_group と同じ集約パターン、独立
  // した名前空間 (別の groups 配列)。member は宣言要素名でなく `required_candidates` の候補セル
  // (structural or なら各枝の leaf name) をそのまま集める — グループ充足は「いずれかの member の
  // いずれかの候補セルが型委譲充足していれば OK」という論理和で、候補セルをフラットに集約しても
  // 数学的に等価 (OR(member1_candidates) OR OR(member2_candidates) OR ... = OR(全 candidates))。
  // 1 CRequiredGroup per label。
  let rg_groups : Array[String] = []
  for e in all {
    for g in e.required_group {
      if !str_in(rg_groups, g) {
        rg_groups.push(g)
      }
    }
  }
  for g in rg_groups {
    let members : Array[RequiredCandidate] = []
    for e in all {
      if str_in(e.required_group, g) {
        for c in required_candidates(e, registry) {
          members.push(c)
        }
      }
    }
    add_constraint(build, CRequiredGroup(g, members))
  }
}

///|
fn str_in(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}

// ── alias desugaring (DR-057) ────────────────────────────────────────────────

///|
/// `s` に部分文字列 `sub` を含むか (name-derived variant 判定: variant.trigger が canonical.name を
/// 部分文字列に含むなら name-derived — DR-057 §3)。
fn str_has_sub(s : String, sub : String) -> Bool {
  if sub.length() == 0 {
    return true
  }
  let cs = to_chars(s)
  let cu = to_chars(sub)
  if cu.length() > cs.length() {
    return false
  }
  let mut i = 0
  while i + cu.length() <= cs.length() {
    let mut k = 0
    let mut ok = true
    while k < cu.length() {
      if cs[i + k] != cu[k] {
        ok = false
        break
      }
      k = k + 1
    }
    if ok {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// `s` の最初の `from` 出現を `to` に置換 (name-derived variant を alias 名で再導出: DR-057 §3
/// "--no-ssl" (canonical ssl) → alias tls で "--no-tls")。
fn str_replace_first(s : String, from : String, to : String) -> String {
  let cs = to_chars(s)
  let cf = to_chars(from)
  if cf.length() == 0 || cf.length() > cs.length() {
    return s
  }
  let mut i = 0
  while i + cf.length() <= cs.length() {
    let mut k = 0
    let mut ok = true
    while k < cf.length() {
      if cs[i + k] != cf[k] {
        ok = false
        break
      }
      k = k + 1
    }
    if ok {
      let buf = StringBuilder::new()
      buf.write_string(chars_to_str(cs, 0, i))
      buf.write_string(to)
      buf.write_string(chars_to_str(cs, i + cf.length(), cs.length()))
      return buf.to_string()
    }
    i = i + 1
  }
  s
}

///|
/// canonical option / positional 要素を name で検索。
fn find_elem(def : Definition, name : String) -> ElemDef? {
  for e in def.options {
    if e.name == name {
      return Some(e)
    }
  }
  for e in def.positionals {
    if e.name == name {
      return Some(e)
    }
  }
  None
}

///|
fn find_command(def : Definition, name : String) -> CommandDef? {
  for c in def.commands {
    if c.name == name {
      return Some(c)
    }
  }
  None
}

///|
/// alias entry-copy の空 body: entry 綴り + canonical name のみ携行、値源 / 結果キー / 制約は実体側の
/// まま (DR-057 §3)、それら field は set しない。
fn alias_entry(
  canonical_name : String,
  ty : Ty,
  long : Array[String],
  variants : Array[Variant],
  short : Array[Char],
  deprecated : Bool,
) -> ElemDef {
  {
    name: canonical_name, // effect / entity / result key は全て canonical name で keying (link 同型)
    ty,
    // 既に導出済み explicit 綴り列 (`:set` は含まない — normalize/resolve_long の対象外、post-normalize
    // 相当の確定形として直接 LList で持つ)。alias entry-copies は fixpoint installer (inst_long 等) が
    // そのまま処理する対象で、二度目の resolve_long は起きない。
    long: LList(long),
    variants,
    short,
    env: [],
    is_tty: false, // alias entry-copy も値源は実体側のまま (§3 と同じ理由、env と対称)
    tty_stream: None,
    tty_cygwin: true,
    is_dd: false,
    is_exact: false,
    dd_match: None,
    dd_self_keep: false,
    is_global: false,
    is_inherit: false,
    is_inheritable: false,
    link_depth: 0,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple: false,
    accumulator: None,
    flatten: None,
    separator: None,
    collector: None,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    required_group: [],
    required: false, // alias entry は AliasDef 自体に required 宣言経路を持たない (requires/exclusive_group と同じ理由)
    value_requires: [],
    deprecated,
    // DR-104 §2/§3: alias entry-copy は常に is_alias:true (この関数自体が alias 宣言由来 entry-copy
    // 専用のコンストラクタ)。hidden は AliasDef に独立宣言経路を持たない (deprecated と違い、現行
    // fixture に alias 側の独立 hidden を要求するものが無い) ので canonical と同じ false 既定。
    is_alias: true,
    hidden: false,
    completer: None,
    default_values: None,
    int_round: RError,
    allow_base_prefix: false,
    bool_config: bool_config_canonical(),
    piece_filters: [],
    value_filters: [],
    final_filters: [],
    accum_filters: [],
    long_prefix: "--",
    short_prefix: "-",
    env_prefix: "",
    auto_env: false,
    long_eq_sep: EsAllow,
    short_combine: true,
    short_attached_value: AtAllow,
    body: BCell,
  }
}

///|
/// alias 宣言 (DR-057) を option entry-copies / command defs に desugar。完全性検査が AliasInst の
/// "alias" 所有を確認した後、init_sb 前に 1 度だけ走る決定的 pre-pass。各 entry-copy は canonical name
/// で keying (satellites が canonical cell を bind、結果キーも canonical)、再導出綴りを携行し、fixpoint
/// の long/short/command installer が展開する (DR-057 §4)。command subtree にも再帰。
///
/// `orig` は normalize_surface 適用前の複製 (issue 2026-07-08 dec-alias-long-override-flag-sugar-
/// gap): `def` 側の canonical 要素は既に TFlag→TBool 変換済みなので、DR-076 §2 規則1 (flag の
/// `long:true` 糖衣は `:set:true` へ差し替え) を判定する材料 (元の型 TFlag) が失われている。`orig`
/// から同じ target 要素の変換前の `ty`/`long` を引き、`resolve_long` を canonical 側と同じ形で
/// 通すことで、alias 側にも同じ規則1/2 を適用する。
fn desugar_aliases(def : Definition, orig : Definition) -> Unit {
  for a in def.aliases {
    let alias_name = match a.name {
      Some(n) => n
      None => a.target // 明示 name 無し → canonical 名を流用 (e.g. short-only alias)
    }
    match find_elem(def, a.target) {
      Some(canon) => {
        let (orig_ty, orig_long) = match find_elem(orig, a.target) {
          Some(oc) => (oc.ty, oc.long)
          None => (canon.ty, canon.long) // 理論上起きない防御的フォールバック
        }
        // canonical 自身の (pre-normalize) long を canonical 名・元の型で解決する — 基底 long 綴り
        // (name-derived 主入口の有無) と、継承すべき NAME-DERIVED variants の両方をここから導く。
        // resolve_long を通すことで、canonical が flag なら規則1/2 (:set:true 差し替え/補完) を
        // 反映した形で `canon_vars` が手に入る。
        let (canon_longs, canon_vars) = resolve_long(
          orig_long,
          canon.name,
          orig_ty,
        )
        let long : Array[String] = []
        if str_in(canon_longs, kebab(canon.name)) {
          long.push(alias_name)
        }
        // 明示 `long` override (DR-007 差分上書き) は自綴りを add、継承 variants を cut。alias 自身の
        // long も canonical と同じ `resolve_long` (colon DSL 分類 + flag 規則1/2) を alias 名・
        // canonical の元の型で通す — 型依存の糖衣差し替えが alias 側でも canonical と揃う
        // (issue 2026-07-08 dec-alias-long-override-flag-sugar-gap の根治)。
        let variants : Array[Variant] = []
        match a.long_override {
          Some(decl) => {
            let (longs, vars) = resolve_long(decl, alias_name, orig_ty)
            for n in longs {
              if !str_in(long, n) {
                long.push(n)
              }
            }
            for v in vars {
              variants.push(v)
            }
          }
          None =>
            // canonical の NAME-DERIVED variants (上で resolve_long 済み) を alias 名で再導出。
            // variant.trigger が canonical.name を部分文字列に含めば name-derived (DR-057 §3);
            // 明示 trigger (e.g. compress の "gzip") は非継承 (明示綴り非継承)。
            for v in canon_vars {
              if str_has_sub(v.trigger, canon.name) {
                variants.push({
                  trigger: str_replace_first(v.trigger, canon.name, alias_name),
                  op: v.op,
                  operand: v.operand,
                })
              }
            }
        }
        def.options.push(
          alias_entry(
            canon.name,
            canon.ty,
            long,
            variants,
            copy_chars(a.short),
            a.deprecated,
          ),
        )
      }
      None =>
        // command alias: co → checkout 部分木, 結果キーは checkout に寄せる (DR-057 §2)
        match find_command(def, a.target) {
          Some(cmd) =>
            def.commands.push({
              name: alias_name,
              body: clone_def(cmd.body),
              export_key: EkKey(a.target),
            })
          None => () // dangling alias target — 将来の absent-ref check 用に残置
        }
    }
  }
  for c in def.commands {
    let orig_body = match find_command(orig, c.name) {
      Some(oc) => oc.body
      None => c.body // 理論上起きない防御的フォールバック (orig 側の対応 command が見つからない)
    }
    desugar_aliases(c.body, orig_body)
  }
}

///|
fn add_constraint(build : Build, c : Constraint) -> Unit {
  for existing in build.constraints {
    if existing == c {
      return
    }
  }
  build.constraints.push(c)
}

///|
/// 全木 1 pass の fixpoint: entities ensure (core) → installer 適用 → 子 scope 再帰。global は再帰前に
/// 子にコピーするので、`order` 内の global 位置に関わらず子は同 pass で成長した宣言層を見る。
fn tree_pass(
  order : Array[Installer],
  sb : SB,
  has_cf : Bool,
  registry : Map[String, Node],
) -> Unit {
  ensure_entities(sb, has_cf)
  for inst in order {
    apply_node(inst, sb, registry)
  }
  for child in sb.children {
    tree_pass(order, child.body, has_cf, registry)
  }
}

///|
fn def_err(
  element : String,
  kind : DefErrKind,
  message : String,
  hint : String,
) -> DefError {
  { element, kind, message, hint }
}

///|
/// DR-011 明確化 (kawaz 裁定 2026-07-08): `long` の array 形の各要素は `classify_long_spelling` が
/// `LMain`/`LVariant` に分類できる形でなければならない — colon-less な文字列、または語彙外 effect
/// word を持つ文字列 (`LInvalid`) は文法エラーで `unknown-vocab` (DR-054) に落とす。`normalize_option`
/// (`resolve_long` 経由) の**前**に検査する必要がある — `resolve_long` は `LInvalid` を黙って捨てる
/// (呼び出し前提が「無効文字列は既に definition-error として検出済み」なので) ため、normalize 後の
/// `e.long` には無効な生文字列がもう残っていない。
fn collect_invalid_long_dsl(def : Definition, out : Array[DefError]) -> Unit {
  for e in def.options {
    push_invalid_long(e, out)
  }
  for e in def.positionals {
    push_invalid_long(e, out)
  }
  for c in def.commands {
    collect_invalid_long_dsl(c.body, out)
  }
}

///|
fn push_invalid_long(e : ElemDef, out : Array[DefError]) -> Unit {
  match e.long {
    LBool(_) => () // bool 糖衣は常に妥当 (DR-071 §1 / DR-076 §2)
    LList(strs) =>
      for l in strs {
        match classify_long_spelling(l, kebab(e.name), e.ty) {
          LInvalid(s) =>
            out.push(
              def_err(
                e.name,
                DUnknownVocab,
                "long spelling '\{s}' is not valid variant DSL (colon-less, or an unrecognized effect word) — DR-011 明確化 2026-07-08",
                "use `:set` / a colon-DSL variant (e.g. `:set:true`, `no:set:false`), or a DR-057 alias element for an explicit spelling",
              ),
            )
          LMain(_) | LVariant(_) => ()
        }
      }
  }
}

///|
/// DR-011 明確化 (kawaz 裁定 2026-07-08): alias `long_override` (DR-057 §3 差分上書き) は canonical
/// 側の `long` と同じ colon DSL を共用する (`classify_long_spelling`、installer.mbt:1497 のコメント
/// 「二経路が drift しないよう分類器を共用」参照) — 明確化はこの DSL が現れる**全ての場所**に一様に効く
/// 規則なので、colon-less / 語彙外 effect は canonical 側 (`push_invalid_long`) と同じく `unknown-vocab`
/// (DR-054) に落とす。canonical 側と別関数にしているのは、target canonical 要素の `ty` を
/// `find_elem` で引く必要があり (`classify_long_spelling` の operand 解釈に使う)、`push_invalid_long`
/// の「自分の ElemDef を検査する」形と入力の形が違うため — dangling alias target (見つからない場合)
/// は absent-ref check が別途拾うのでここでは静かにスキップする。desugar_aliases (LInvalid を
/// rename-only で通す経路) より前、static check フェーズで検出する。
fn collect_invalid_alias_long_override(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  for a in def.aliases {
    match a.long_override {
      Some(decl) => {
        let alias_name = match a.name {
          Some(n) => n
          None => a.target
        }
        match find_elem(def, a.target) {
          Some(canon) =>
            match decl {
              LBool(_) => () // bool 糖衣は常に妥当 (DR-071 §1 / DR-076 §2)
              LList(strs) =>
                for l in strs {
                  match classify_long_spelling(l, alias_name, canon.ty) {
                    LInvalid(s) =>
                      out.push(
                        def_err(
                          alias_name,
                          DUnknownVocab,
                          "alias long_override spelling '\{s}' is not valid variant DSL (colon-less, or an unrecognized effect word) — DR-011 明確化 2026-07-08",
                          "use `:set` / a colon-DSL variant (e.g. `:set:true`, `no:set:false`) in long_override",
                        ),
                      )
                    LMain(_) | LVariant(_) => ()
                  }
                }
            }
          None => () // dangling alias target — absent-ref check が別途拾う
        }
      }
      None => ()
    }
  }
  for c in def.commands {
    collect_invalid_alias_long_override(c.body, out)
  }
}

///|
/// DR-099 §3/§7: `builtin/tty` preset の必須 config `tty_stream` が未指定な要素は definition-error
/// (kind=invalid-range)。bare `type:"tty"` / `type:"builtin/tty"` (config を供給する経路自体が無い —
/// 直接参照は常にこの形、decode 層が `is_tty=true, tty_stream=None` で通す) と、definitions.types
/// 経由で `tty_stream` を書き忘れた shadow の両方をこの一本で拾う。
///
/// DR-098 §4 が必要としていた 3 分類 (非 bool 型・値なし要素・flag/count プリセットへの `tty:`
/// 付与) は、`type:` が単一選択のフィールドである以上、preset 型への転換で構文的に発生しなくなった
/// (DR-099 §1「採用しなかった案」) — 残る唯一の definition-error はこの factory 自身の config 検証
/// だけ (DR-061 §4「config 値の検証は factory 自身の責務」)。is_tty/tty_stream は `type:` 解決の
/// decode 時点で確定し normalize_surface の影響を受けないため (TFlag→TBool 変換のような pre/post
/// 区別は不要)、他の post-normalize な collect_* 群と同じ並びで呼んでよい。
fn collect_tty_stream_missing(def : Definition, out : Array[DefError]) -> Unit {
  fn check(e : ElemDef) -> Unit {
    if e.is_tty && e.tty_stream is None {
      out.push(
        def_err(
          e.name,
          DInvalidRange,
          "'\{e.name}' selects the builtin/tty preset but its factory config is missing 'tty_stream' — bare type:\"tty\"/\"builtin/tty\" has no channel to supply it (DR-099 §3)",
          "declare a definitions.types entry with config.tty_stream set to \"stdin\"|\"stdout\"|\"stderr\", and reference that name from 'type'",
        ),
      )
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_tty_stream_missing(c.body, out)
  }
}

///|
/// invariant ③ (DR-054): 2 installer が同 vocab を所有。全 intersection を収集。
fn collect_vocab_intersection(
  order : Array[Installer],
  out : Array[DefError],
) -> Unit {
  let seen : Array[String] = []
  for inst in order {
    let v = owned_vocab(inst)
    for s in seen {
      if s == v {
        out.push(
          def_err(
            v,
            DVocabIntersection,
            "vocab '\{v}' is claimed by two installers",
            "remove the duplicate installer owning '\{v}' from the chain",
          ),
        )
      }
    }
    seen.push(v)
  }
}

///|
/// invariant ①' completeness (DR-054): 木で使われているが chain のどの installer にも所有されない
/// special vocab は Error。全 (element ごと + commands) 収集。
fn collect_unknown_vocab(
  def : Definition,
  order : Array[Installer],
  out : Array[DefError],
) -> Unit {
  let owned : Array[String] = []
  for inst in order {
    owned.push(owned_vocab(inst))
  }
  scan_unknown(def, owned, out)
}

///|
fn scan_unknown(
  def : Definition,
  owned : Array[String],
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    push_elem_unknown(e, owned, out)
  }
  for e in def.positionals {
    push_elem_unknown(e, owned, out)
  }
  if def.commands.length() > 0 && !vocab_owned(owned, "command") {
    out.push(
      def_err(
        "(commands)",
        DUnknownVocab,
        "unknown special vocab 'command'",
        "add CommandInst to the installer chain",
      ),
    )
  }
  // alias vocab (DR-057): scope-level (aliases は per-ElemDef ではない)、commands と対称形。
  if def.aliases.length() > 0 && !vocab_owned(owned, "alias") {
    out.push(
      def_err(
        "(aliases)",
        DUnknownVocab,
        "unknown special vocab 'alias'",
        "add AliasInst to the installer chain",
      ),
    )
  }
  for c in def.commands {
    scan_unknown(c.body, owned, out)
  }
}

///|
fn push_elem_unknown(
  e : ElemDef,
  owned : Array[String],
  out : Array[DefError],
) -> Unit {
  match scan_elem_vocab(e, owned) {
    Some(v) =>
      out.push(
        def_err(
          e.name,
          DUnknownVocab,
          "unknown special vocab '\{v}' — no installer claimed it",
          "register an installer owning '\{v}' in the chain (§13.5)",
        ),
      )
    None => ()
  }
}

///|
fn vocab_owned(owned : Array[String], v : String) -> Bool {
  for o in owned {
    if o == v {
      return true
    }
  }
  false
}

///|
fn scan_elem_vocab(e : ElemDef, owned : Array[String]) -> String? {
  if long_of(e).length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:" + long_of(e)[0])
  }
  // variant DSL は long 属性の値語彙 (DR-042 §所有権の粒度) — long installer が所有。
  if e.variants.length() > 0 && !vocab_owned(owned, "long") {
    return Some("long:variant:" + e.variants[0].trigger)
  }
  if e.short.length() > 0 && !vocab_owned(owned, "short") {
    return Some("short")
  }
  if e.env.length() > 0 && !vocab_owned(owned, "env") {
    return Some("env:" + e.env[0])
  }
  if e.is_dd && !vocab_owned(owned, "dd") {
    return Some("dd")
  }
  if e.is_global && !vocab_owned(owned, "global") {
    return Some("global")
  }
  if e.is_inherit && !vocab_owned(owned, "inherit") {
    return Some("inherit")
  }
  if e.is_inheritable && !vocab_owned(owned, "inheritable") {
    return Some("inheritable")
  }
  // repeat と optional 糖衣 (DR-043) は repeat installer 所有。
  match elem_repeat(e) {
    Some(_) => if !vocab_owned(owned, "repeat") { return Some("repeat") }
    None => ()
  }
  if e.multiple && !vocab_owned(owned, "multiple") {
    return Some("multiple")
  }
  // config vocab (DR-050): type:"config_file" と config_key 両方 config installer 所有。
  if e.is_config_file && !vocab_owned(owned, "config") {
    return Some("config:config_file")
  }
  match e.config_key {
    Some(_) =>
      if !vocab_owned(owned, "config") {
        return Some("config:config_key")
      }
    None => ()
  }
  // constraint vocab (DR-055)
  if e.requires.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:requires")
  }
  if e.conflicts_with.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:conflicts_with")
  }
  if e.exclusive_group.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:exclusive_group")
  }
  if e.required_group.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:required_group")
  }
  if e.value_requires.length() > 0 && !vocab_owned(owned, "constraint") {
    return Some("constraint:value_requires")
  }
  None
}

///|
/// zero-progress 静的 guard (DR-043): repeat head は >= 1 token 消費が必要 (再帰 unfold の loop を防止)。
/// ref head は「target が >= 1 消費」に還元 (消費 node のない ref cycle も捕捉)。
fn head_progresses(
  node : Node,
  registry : Map[String, Node],
  visiting : Array[String],
) -> Bool {
  match node {
    StrArg(_, _)
    | SepArg(_, _, _, _, _, _, _, _)
    | KvArg(_, _)
    | NumArg(_, _, _)
    | FloatArg(_, _)
    | IntArg(_, _, _, _)
    | BoolArg(_, _, _)
    | FilterArg(_, _)
    | ReqArg(_)
    | Exact(_)
    | NativeMatch(_)
    | DdSat(_)
    | CmdSat(_, _) => true
    // DR-090: progress depends on `self_keep` — `drop` (false) consumes 1 token like `DdSat`,
    // `keep` (true) is a 0-token Accept (same standing as `Bind`/`EffMark` below).
    DdMatchSat(_, _, self_keep, _) => !self_keep
    IdxRepeat(_, _, _, _) => true // 名前付き indexed repeat は head を消費
    BoundedTail(_, budget, _) => budget >= 1 // >= 1 head 取れる時のみ消費
    Rooted(inner, _) => head_progresses(inner, registry, visiting)
    Bind(_, _) => false // 0-token
    EffMark(_, _) => false // 0-token effect (DR-045)
    FailMark(_) => false // 0-token failure-action (DR-048)
    DeprMark(_) => false // 0-token deprecation (DR-058)
    Ref(r) => {
      for v in visiting {
        if v == r {
          return false // 消費 node なしの cycle → 無 progress
        }
      }
      match registry.get(r) {
        Some(tpl) => {
          visiting.push(r)
          let ok = head_progresses(tpl, registry, visiting)
          let _ = visiting.pop()
          ok
        }
        None => false // unresolved ref
      }
    }
    Or(alts) => {
      for a in alts {
        if !head_progresses(a, registry, visiting) {
          return false
        }
      }
      alts.length() > 0
    }
    Seq(items) =>
      if items.length() >= 1 {
        head_progresses(items[0], registry, visiting)
      } else {
        false
      }
    Many(_) | Scoped(_, _) | ScopeNode(_) => true
    GreedyRepeat(inner) => head_progresses(inner, registry, visiting)
  }
}

///|
/// HEAD position の ref (最初に消費される要素の ref), 無ければ None。消費 head の後の ref (repeat の
/// cons tail `Seq([head, Opt(Ref(self))])` 等) は head 位置ではないので、正当な repeat 自参照は None を返す。
fn head_ref_of(node : Node) -> String? {
  match node {
    Ref(r) => Some(r)
    Seq(items) => if items.length() >= 1 { head_ref_of(items[0]) } else { None }
    Or(alts) => {
      for a in alts {
        match head_ref_of(a) {
          Some(r) => return Some(r)
          None => ()
        }
      }
      None
    }
    Rooted(inner, _) => head_ref_of(inner)
    _ => None
  }
}

///|
/// `name` から head-position ref を辿ると loop するか (無限構造展開の circular ref, DR-054)。repeat
/// 自参照 (head が消費 node) はここで loop しない。
fn head_cycles(
  name : String,
  registry : Map[String, Node],
  visiting : Array[String],
) -> Bool {
  for v in visiting {
    if v == name {
      return true
    }
  }
  match registry.get(name) {
    Some(tpl) =>
      match head_ref_of(tpl) {
        Some(next) => {
          visiting.push(name)
          let r = head_cycles(next, registry, visiting)
          let _ = visiting.pop()
          r
        }
        None => false
      }
    None => false
  }
}

///|
/// node の head-position ref が cycle に到達するか (circular ref が同時に zero-progress として 2 重
/// 報告されないよう区別する用途)。
fn head_node_cycles(node : Node, registry : Map[String, Node]) -> Bool {
  match head_ref_of(node) {
    Some(r) => head_cycles(r, registry, [])
    None => false
  }
}

///|
/// zero-progress guard (DR-043 / DR-054): repeat head は >= 1 消費が必要。全件収集 — ただし ref
/// cycle による 非 progress は circular ref (collect_circular_ref) 側で報告するので、ここでは除外する
/// (kind を distinct に保つ)。
fn collect_zero_progress(
  def : Definition,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for e in def.positionals {
    match elem_repeat(e) {
      Some(_) => {
        let head = elem_head(e)
        if !head_progresses(head, registry, []) &&
          !head_node_cycles(head, registry) {
          out.push(
            def_err(
              e.name,
              DZeroProgress,
              "repeat element '\{e.name}' has a zero-progress head",
              "give the repeat head a token-consuming element",
            ),
          )
        }
      }
      None => ()
    }
  }
  for c in def.commands {
    collect_zero_progress(c.body, registry, out)
  }
}

///|
/// circular ref (DR-054): registry template の head-position ref chain が loop → 無限構造展開。
/// repeat 由来の自参照は pass (head が消費 node)。全件収集。
fn collect_circular_ref(
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for name, _ in registry {
    // repeat installer 登録の lazy-marker key ("lazy:<name>") はスキップ。
    if name.length() >= 5 && name[0:5] == "lazy:" {
      continue
    }
    if head_cycles(name, registry, []) {
      out.push(
        def_err(
          name,
          DCircularRef,
          "ref template '\{name}' is circular (infinite structural expansion)",
          "break the ref cycle or add a token-consuming head before the self-reference",
        ),
      )
    }
  }
}

///|
/// absent ref (DR-054 / DR-032): 要素 ref_target の解決先が無い (init_sb の repeat lowering + 事前
/// 登録済み template を含む registry で check)。全件収集。
fn collect_absent_ref(
  def : Definition,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    check_elem_absent_ref(e, registry, out)
  }
  for e in def.positionals {
    check_elem_absent_ref(e, registry, out)
  }
  for c in def.commands {
    collect_absent_ref(c.body, registry, out)
  }
}

///|
fn check_elem_absent_ref(
  e : ElemDef,
  registry : Map[String, Node],
  out : Array[DefError],
) -> Unit {
  match e.ref_target {
    Some(r) =>
      match registry.get(r) {
        Some(_) => ()
        None =>
          out.push(
            def_err(
              e.name,
              DAbsentRef,
              "ref target '\{r}' is not defined in scope or definitions",
              "define '\{r}' as a template (definitions) or in the scope",
            ),
          )
      }
    None => ()
  }
}

///|
/// invalid value range (DR-054 / DR-052): repeat min > max。全件収集。
fn collect_invalid_range(def : Definition, out : Array[DefError]) -> Unit {
  for e in def.positionals {
    match e.repeat {
      Some(spec) =>
        match spec.max {
          Some(mx) =>
            if spec.min > mx {
              out.push(
                def_err(
                  e.name,
                  DInvalidRange,
                  "repeat min \{spec.min} > max \{mx}",
                  "set the repeat max >= min",
                ),
              )
            }
          None => ()
        }
      None => ()
    }
  }
  for c in def.commands {
    collect_invalid_range(c.body, out)
  }
}

///|
/// codex レビュー指摘 4 (2026-07-09 節目レビュー): an option's `ref` + `repeat` lowering
/// (`inst_long`'s `Some(_)` arm) only wires a SINGLE `GreedyRepeat` spine slot — correct for
/// `min <= 1` (no mandatory-head unrolling, `elem_repeat`'s `Some(spec) => spec.min - 1`
/// mandatory heads collapses to 0), but a `min > 1` spec WOULD unroll extra mandatory heads that
/// `inst_long` silently folds into the SAME single tail (`Seq(spine)`) — losing both 先食い
/// suppression and the greedy 取り分選好 for those extra reps while still parsing "successfully"
/// (issue 2026-07-09-ref-template-result-shape: 未対応構成は黙って誤動作させず definition error
/// で可視化する契約、[[retreat-is-last-resort]] 同型の「壊れたまま動かすより落とす」判断)。Reject at
/// definition time until `GreedyRepeat` carries multiple spine slots.
fn collect_unsupported_option_ref_repeat(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    if e.ref_target is Some(_) {
      match elem_repeat(e) {
        Some(spec) =>
          if spec.min > 1 {
            out.push(
              def_err(
                e.name,
                DInvalidRange,
                "option repeat min \{spec.min} > 1 is not supported for a `ref` element (GreedyRepeat wires a single spine slot only)",
                "use repeat: {\"min\": 0} or {\"min\": 1} on this option, or move the mandatory reps to a positional",
              ),
            )
          }
        None => ()
      }
    }
  }
  for c in def.commands {
    collect_unsupported_option_ref_repeat(c.body, out)
  }
}

///|
/// issue 2026-07-09-accum-fold-update-default-ops (team-lead 裁定 2026-07-10、`collect_unsupported_
/// option_ref_repeat` の兄弟 — 同じ「構造的に宣言できるが実装が対応できない組合せを definition-error
/// で落とす」契約): an `update` variant (DR-077 §1's `:update:<transform>` DSL) targeting a `multiple`
/// (accum) element is REJECTED at definition time. DR-077's `update` semantics are `cell = f(old)`
/// where `old` is the CELL'S CURRENT VALUE — for an accum cell that value is the accumulated array
/// (T[]), but every filters-registry transform is T=>T (scalar, `filters.mbt`'s `FilterSignature`,
/// DR-077 §2 "使えるのは transform シグネチャ T=>T の filter のみ"). Applying a scalar transform to an
/// array is a STRUCTURAL type mismatch with no legal resolution today (no Acc=>Acc transform exists
/// in the registry) — rather than let it reach the ACCUMULATE fold and fail unpredictably there
/// (or silently coerce), this closes the gap at the SAME layer DR-077 §2 already closes "unknown
/// transform name" / "validate-only signature" (`classify_long_spelling`'s `LInvalid` path, both
/// folded into `DUnknownVocab` there) — `multiple` + `update` is a third static-known-bad
/// combination, just discovered one step later (after `normalize_surface` has resolved `variants`,
/// unlike the two above which classify_long_spelling catches at DSL-parse time). `DInvalidRange` is
/// reused (not a new `DefErrKind`) for the same reason `classify_long_spelling`'s comment gives:
/// introducing a finer-grained kind is a spec-side DR-054 decision, not kuu.mbt's to make alone.
///
/// spec fixture pin 状況 (2026-07-10 team-lead 連絡): definition_error format 自体が DR-065 で予約の
/// みで未確定なため、spec 側のこの reject の fixture 化は保留 (issue 起票済み、format 実例化は kawaz
/// 裁定待ち) — この検査は kuu.mbt 側の wbtest でのみ pin する (`collect_unsupported_option_ref_repeat`
/// の min>1 reject も同型の wbtest-only pin の前例)。
fn collect_unsupported_accum_update(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    if e.multiple {
      for v in e.variants {
        match v.op {
          Update(_, _) =>
            out.push(
              def_err(
                e.name,
                DInvalidRange,
                "update variant '\{v.trigger}' targets a multiple (accum) element — every filters-registry transform is T=>T (scalar) but this cell's current value is an accumulated array (T[]), a structural type mismatch with no legal transform today",
                "remove the update variant from this element, or move the transform to a non-multiple (scalar) element",
              ),
            )
          _ => ()
        }
      }
    }
  }
  for e in def.positionals {
    if e.multiple {
      for v in e.variants {
        match v.op {
          Update(_, _) =>
            out.push(
              def_err(
                e.name,
                DInvalidRange,
                "update variant '\{v.trigger}' targets a multiple (accum) element — every filters-registry transform is T=>T (scalar) but this cell's current value is an accumulated array (T[]), a structural type mismatch with no legal transform today",
                "remove the update variant from this element, or move the transform to a non-multiple (scalar) element",
              ),
            )
          _ => ()
        }
      }
    }
  }
  // codex レビュー High 1 (2026-07-10): alias の `long_override` (DR-057 §3 差分上書き) は canonical
  // 側の `variants` を経由せず独自に colon DSL を解釈する — 上の 2 ループは `def.options`/
  // `def.positionals` の (この時点の) variants しか見ないため、alias 経由の `:update:<transform>`
  // が同じ検査をすり抜けて `parse_definition` を通過し、発火時に canonical (multiple 要素) への
  // Update binding が届いて `resolve.mbt`'s accum 分岐の abort に到達する
  // (repro: canonical `{"name":"tags","multiple":true}` + alias `{"target":"tags",
  // "long_override":["bump:update:increment"]}` + args `["--bump-t"]`)。`desugar_aliases` (この
  // 検査より後に走る) が alias 用の entry-copy を作った後だと、そのcopy自身は `multiple: false`
  // 固定 (`alias_entry`) になり判定が別ロジックを要る — ここ (desugar 前、`def.aliases` を直接見る)
  // で `collect_invalid_alias_long_override` と同じパターン (colon DSL を `classify_long_spelling`
  // で分類 + `find_elem` で alias 先 canonical を引く) を再利用する方が既存規約と一貫し、
  // `parse_definition` 全体の実行順序も変えずに済む。
  for a in def.aliases {
    match a.long_override {
      Some(LList(strs)) =>
        match find_elem(def, a.target) {
          Some(canon) =>
            if canon.multiple {
              let alias_name = match a.name {
                Some(n) => n
                None => a.target
              }
              for l in strs {
                match classify_long_spelling(l, alias_name, canon.ty) {
                  LVariant(v) =>
                    match v.op {
                      Update(_, _) =>
                        out.push(
                          def_err(
                            canon.name,
                            DInvalidRange,
                            "alias long_override update variant '\{v.trigger}' targets '\{canon.name}', a multiple (accum) element — every filters-registry transform is T=>T (scalar) but this cell's current value is an accumulated array (T[]), a structural type mismatch with no legal transform today",
                            "remove the update variant from this alias's long_override, or move the transform to a non-multiple (scalar) element",
                          ),
                        )
                      _ => ()
                    }
                  LMain(_) | LInvalid(_) => () // not an update variant; other errors caught by collect_invalid_alias_long_override
                }
              }
            }
          None => () // dangling alias target — absent-ref check が別途拾う
        }
      Some(LBool(_)) => () // bool 糖衣 (:set/:set:true 相当) は update DSL を含まない
      None => ()
    }
  }
  for c in def.commands {
    collect_unsupported_accum_update(c.body, out)
  }
}

///|
/// codex レビュー High 2 (2026-07-10): `collect_unsupported_accum_update` の variant 走査 (上記) は
/// `count_increment_variant` 経由 (`long:true` 糖衣、DR-077 §3) の `:update:increment` は捕まえるが、
/// TCount の **short** 発火 (`matcher.mbt` の `walk_short`'s `TCount` arm) は variant を一切経由せず
/// `mk_eff(e.name, Update("increment", []), Cli)` を直接生成する — variants を持たない firing なので
/// variant 走査ではそもそも見えない (repro: `{"name":"n","type":"count","short":["n"],
/// "multiple":true}` + args `["-n"]` で resolve.mbt の accum 分岐の abort に到達)。
///
/// DR-077 §3 で count は `number + default:0 + update:increment の綴り合成` と規定されている —
/// count という TYPE そのものが「update(increment) 効果を持つ」という契約を運ぶので、firing の綴り
/// (short/long/明示variant) を問わず、**TCount 要素への `multiple` 宣言そのもの**が accum×update と
/// 構造的に同じ未対応構成 (T=>T transform vs 累積状態 T[]) になる。variant の有無に依存しない要素
/// レベルの検査として、`collect_unsupported_accum_update` とは別条件で実装する (variant 走査を
/// TCount にも広げるのではなく、TCount×multiple という組合せ自体を閉じる — short 経由はそもそも
/// variant を生成しないため、variant 走査を広げても捕まえられない)。
fn collect_unsupported_count_multiple(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  for e in def.options {
    if e.ty == TCount && e.multiple {
      out.push(
        def_err(
          e.name,
          DInvalidRange,
          "a `count` element cannot declare `multiple` — count's type contract IS an update(increment) effect (DR-077 §3), and every filters-registry transform is T=>T (scalar) while a multiple (accum) cell's current value is an accumulated array (T[]), a structural type mismatch with no legal transform today",
          "remove `multiple` from this count element, or use a plain `number` element with an explicit `:update:<transform>` variant on a non-multiple cell",
        ),
      )
    }
  }
  for e in def.positionals {
    if e.ty == TCount && e.multiple {
      out.push(
        def_err(
          e.name,
          DInvalidRange,
          "a `count` element cannot declare `multiple` — count's type contract IS an update(increment) effect (DR-077 §3), and every filters-registry transform is T=>T (scalar) while a multiple (accum) cell's current value is an accumulated array (T[]), a structural type mismatch with no legal transform today",
          "remove `multiple` from this count element, or use a plain `number` element with an explicit `:update:<transform>` variant on a non-multiple cell",
        ),
      )
    }
  }
  for c in def.commands {
    collect_unsupported_count_multiple(c.body, out)
  }
}

///|
/// DR-083 §5: a non-accum (truly scalar) element's declared default must decode to EXACTLY one
/// piece — an array-shaped JSON default (`length != 1`) for such an element is a STRUCTURAL
/// mismatch known entirely at definition time (no I/O needed, unlike DR-050's config array whose
/// structural mismatch IS a runtime Error precisely because config is read at runtime) —
/// `collect_unsupported_accum_update`'s sibling "構造的に宣言できるが実装が対応できない組合せを
/// definition-error で落とす" contract.
///
/// "non-accum" mirrors `ensure_entity`'s OWN accum-eligibility derivation exactly (`e.multiple ||
/// elem_repeat(e) is Some(_) || e.separator is Some(_)`) — computed here on the pre-`ensure_entity`
/// `ElemDef` fields directly, since this check runs before `Entity`/`Entity.accum` exist. Using
/// the narrower `e.multiple` alone would misfire on a `repeat`-only or bare-`separator` element
/// (both legitimately accum cells per `ensure_entity`, DR-043/034) declaring a multi-piece default
/// — this derivation must stay IN SYNC with `ensure_entity`'s if it ever changes.
fn collect_scalar_array_default(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  fn is_accum_elem(e : ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  fn check(e : ElemDef) -> Unit {
    if !is_accum_elem(e) {
      match e.default_values {
        Some(vs) =>
          if vs.length() != 1 {
            out.push(
              def_err(
                e.name,
                DInvalidRange,
                "a non-multiple (scalar) element's declared default must be exactly ONE piece, got \{vs.length()} — an array-shaped default is only legal for a multiple/repeat/separator (accum) element (DR-083 §1/§5)",
                "wrap this element's default in `multiple`/`repeat` if it should accumulate, or write a single scalar default value",
              ),
            )
          }
        None => ()
      }
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_scalar_array_default(c.body, out)
  }
}

///|
/// DR-089 §4: none には値空間が無いので、値源を宣言する `env`/`config_key`/`inherit` は静的に既知の不成立構成
/// — 「静的に既知は定義時に倒す」(DR-083 §5) の筋で definition-error にする。実行時側
/// (`env_value`/`config_to_value` の TNone arm、resolve.mbt/value.mbt) は防御 (このチェックが
/// 先に落とすので unreachable 想定) として残す。config_key の明示宣言のみを対象とし、
/// `config_seat` (config_file 要素の存在で自動的に全 value cell へ同型付与される席、DR-050 §3)
/// はここでは対象外 — 著者が明示的に書いた宣言だけを検査する (config_seat は個々の要素の意図では
/// なくスコープ全体の自動帰結なので、同じ「著者の誤り」カテゴリに属さない)。
fn collect_none_value_source_decl(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  fn check(e : ElemDef) -> Unit {
    if e.ty == TNone {
      if e.env.length() > 0 {
        out.push(
          def_err(
            e.name,
            DInvalidRange,
            "'\{e.name}' is type none (no value space) but declares env — a none element cannot have a value source (DR-089 §4)",
            "remove 'env' from '\{e.name}', or give it a real value type",
          ),
        )
      }
      if e.config_key is Some(_) {
        out.push(
          def_err(
            e.name,
            DInvalidRange,
            "'\{e.name}' is type none (no value space) but declares config_key — a none element cannot have a value source (DR-089 §4)",
            "remove 'config_key' from '\{e.name}', or give it a real value type",
          ),
        )
      }
      if e.is_inherit {
        out.push(
          def_err(
            e.name,
            DInvalidRange,
            "'\{e.name}' is type none (no value space) but declares inherit — a none element cannot have a value source (DR-089 §4)",
            "remove 'inherit' from '\{e.name}', or give it a real value type",
          ),
        )
      }
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_none_value_source_decl(c.body, out)
  }
}

///|
/// DR-102 §1/§3 (属性分割、issue accum-post-filters-stage7 の後継): `final_filters` (T→T, scalar
/// filter registry, non-accum 要素専用) と `accum_filters` (Acc→Acc, ARRAY filter registry, accum
/// 要素専用) は、要素の accum 適格性 (`multiple`/`repeat`/`separator` — `ensure_entity`/
/// `collect_scalar_array_default` と同じ `is_accum_elem` 導出) と排他的に対応する。要素にそもそも
/// 存在しない側の属性を書くのは構造不一致であり、`collect_scalar_array_default` (非 accum 要素への
/// 配列 default 宣言) と同型の "構造的に宣言できるが実装が対応できない組合せを definition-error で
/// 落とす" 契約で kind=invalid-range を reject する (fixtures/definition-error/
/// accum-filters-on-non-multiple-invalid-range.json / final-filters-on-multiple-invalid-range.json)。
/// 1 属性 1 registry の対応 (DR-102 §2) により、綴りの registry 未登録は `collect_unknown_filter` が
/// 単独で判定する — 本 gate は属性と要素の形の不一致 (layer 違いではなく構造違反) だけを見る。
///
/// DR-102 §3 の明確化 note (codex レビュー M-9): `type:"none"` 要素 (値空間なし、DR-089) への
/// `final_filters` 宣言も同じ invalid-range に属する — `final_filters` は T→T で値空間の型 T への
/// 変換/検証を前提とするが、none には値空間そのものが無く T が存在しないため構成不能
/// (DR-089 §4 と同型の帰結)。accum 適格な none 要素の `accum_filters` (Acc→Acc) 宣言も同じ理で
/// invalid-range — 非 accum な none 要素の `accum_filters` は既に上の wrong-seat 判定でカバーされる
/// ため、none 固有の追加判定は accum 要素の場合のみ必要。
fn collect_invalid_filter_attribute_mismatch(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  fn is_accum_elem(e : ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  fn check(e : ElemDef) -> Unit {
    let accum = is_accum_elem(e)
    let none_ty = e.ty == TNone
    if e.final_filters.length() > 0 {
      if none_ty {
        out.push(
          def_err(
            e.name,
            DInvalidRange,
            "a type:\"none\" element has no value space (DR-089) — final_filters (T→T, DR-102 §1) requires a T to operate over, which does not exist here",
            "remove final_filters from this element, or give it a real value type",
          ),
        )
      } else if accum {
        out.push(
          def_err(
            e.name,
            DInvalidRange,
            "an accum (multiple/repeat/separator) element cannot declare final_filters (T→T, non-accum-only final-value gate, DR-102 §1) — this element's final gate is accum_filters (Acc→Acc, over the whole accumulated array)",
            "move this chain to accum_filters, or remove multiple/repeat/separator from this element",
          ),
        )
      }
    }
    if e.accum_filters.length() > 0 {
      if !accum {
        out.push(
          def_err(
            e.name,
            DInvalidRange,
            "a non-accum (scalar) element cannot declare accum_filters (Acc→Acc, accum-only whole-array gate, DR-102 §1) — this element's final gate is final_filters (T→T, over the single resolved value)",
            "move this chain to final_filters, or declare multiple/repeat/separator on this element",
          ),
        )
      } else if none_ty {
        out.push(
          def_err(
            e.name,
            DInvalidRange,
            "a type:\"none\" element has no value space (DR-089) — accum_filters (Acc→Acc, DR-102 §1) requires a T domain to operate over, which does not exist here",
            "remove accum_filters from this element, or give it a real value type",
          ),
        )
      }
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_invalid_filter_attribute_mismatch(c.body, out)
  }
}

///|
/// DR-101 / DR-102 §1/§2: filter chain 4 属性 (`value_filters` / `piece_filters` / `final_filters` /
/// `accum_filters`) に指定された filter 名が、その属性が要求する registry の owns 集合に登録されて
/// いない場合は definition-error (kind=`unknown-vocab`)。DR-042 §5 の installer / filter registry
/// 同格原則により、long variant DSL の update transform 名検査 (`classify_long_spelling` の
/// DR-077 §2 適用) と同族の判定。
///
/// `value_filters`/`piece_filters`/`final_filters` は scalar filter registry (T→T, `lookup_filter`)
/// を、`accum_filters` は ARRAY filter registry (Acc→Acc, `lookup_array_filter`) を要求する — 1
/// 属性 1 registry の対応 (DR-102 §2) により、各属性は自分の registry の owns 集合のみを見て
/// unknown-vocab を一意判定する。他 registry との層違い比較 (DR-101 §3、Superseded) は発生しない。
///
/// この単純化により、`filters.mbt` の `apply_filter_chain`/`apply_accum_filter_chain` に到達する
/// 時点で全 filter 名が既に登録済み保証となり、runtime `unknown_filter` reason は wire から消滅する
/// (DR-101 §1)。
///
/// DR-102 §3 の明確化 note (codex レビュー M-6/M-9): `final_filters`/`accum_filters` が要素にとって
/// wrong-seat (`collect_invalid_filter_attribute_mismatch` が invalid-range を出す非 accum 要素の
/// accum_filters・accum 要素の final_filters・`type:"none"` 要素のいずれか) の場合、本 gate はその
/// 属性の中身を一切解釈しない (unknown-vocab 判定をスキップする) — wrong-seat 判定が構造ゲート先行
/// であり、綴りの登録有無を問わず invalid-range のみが報告される (definition_error の
/// `expect.errors` は全エラーの完全一致集合、二重報告を避ける)。
fn collect_unknown_filter(def : Definition, out : Array[DefError]) -> Unit {
  fn is_accum_elem(e : ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  fn push_unknown(
    elem_name : String,
    phase : String,
    fs_name : String,
  ) -> Unit {
    out.push(
      def_err(
        elem_name,
        DUnknownVocab,
        "filter '" +
        fs_name +
        "' in " +
        phase +
        " is not registered in the filters registry (DR-101)",
        "use a registered filter name (see DR-095 §3 canonical filter vocabulary) or remove this chain entry",
      ),
    )
  }

  fn check(e : ElemDef) -> Unit {
    // value_filters (T→T, scalar filter registry): 綴り不在は unknown-vocab (DR-101 §1)
    for fs in e.value_filters {
      if lookup_filter(fs.name) is None {
        push_unknown(e.name, "value_filters", fs.name)
      }
    }
    // piece_filters (String→String, scalar filter registry 内の string 域): 綴り不在は
    // unknown-vocab (value_filters と判定入力同一、DR-101 §1)
    for fs in e.piece_filters {
      if lookup_filter(fs.name) is None {
        push_unknown(e.name, "piece_filters", fs.name)
      }
    }
    // final_filters (T→T, scalar filter registry, non-accum 専用、DR-102 §1): 正しい席 (非 accum
    // かつ 非 none) の場合のみ unknown-vocab 判定。wrong-seat/none-type は
    // `collect_invalid_filter_attribute_mismatch` の invalid-range に一任 (M-6/M-9 構造ゲート先行)。
    if !is_accum_elem(e) && e.ty != TNone {
      for fs in e.final_filters {
        if lookup_filter(fs.name) is None {
          push_unknown(e.name, "final_filters", fs.name)
        }
      }
    }
    // accum_filters (Acc→Acc, ARRAY filter registry, accum 専用、DR-102 §1): 正しい席 (accum かつ
    // 非 none) の場合のみ unknown-vocab 判定。
    if is_accum_elem(e) && e.ty != TNone {
      for fs in e.accum_filters {
        if lookup_array_filter(fs.name) is None {
          push_unknown(e.name, "accum_filters", fs.name)
        }
      }
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_unknown_filter(c.body, out)
  }
}

///|
/// DR-085 §1 訂正 (kawaz 裁定 2026-07-10): a `regex_match` filter entry's pattern compile failure is
/// a definition-error (kind=invalid-argument, DR-054 §4 更新2 / DR-082 §3) — the pattern is part of
/// the definition and compile validity is statically knowable at definition time (same "静的に既知
/// は定義時に倒す" posture `collect_scalar_array_default` uses). Checked across all 4 filter-chain
/// phases (piece_filters/value_filters/final_filters/accum_filters, DR-034/DR-009/DR-102) — a
/// `regex_match` entry name-matches unconditionally regardless of which registry the declaring
/// phase actually requires (an `accum_filters` entry named `regex_match` is ALSO independently
/// rejected as unknown-vocab by `collect_unknown_filter`, since `regex_match` isn't a registered
/// ARRAY filter — DR-054's "enumerate ALL errors, no first-error 打ち切り" means both fire, not a
/// conflict). Uses `filters.mbt`'s `compile_regex` — the SAME compile path `filter_regex_match`
/// runs at match time, so a pattern that passes this gate is guaranteed compilable at runtime too.
/// A wrong arg count (not exactly 1) is left to the runtime "regex_match requires exactly 1 arg"
/// Err (`filter_regex_match`) rather than duplicated here as a second definition-time check — this
/// gate's sole job is "does the pattern compile", not general arity validation.
/// DR-090 §2: a dd element's `match` regex — compile failure is a definition-error, the same
/// treatment `collect_invalid_regex_pattern` gives `regex_match` filter-chain patterns (same
/// `compile_regex` compile path, same `DInvalidArgument` kind — "pattern compile failure is a
/// definition-time fact, known statically without I/O").
fn collect_invalid_dd_pattern(def : Definition, out : Array[DefError]) -> Unit {
  fn check(e : ElemDef) -> Unit {
    match e.dd_match {
      Some(pattern) =>
        if compile_regex(pattern) is None {
          out.push(
            def_err(
              e.name,
              DInvalidArgument,
              "dd match pattern '" + pattern + "' failed to compile",
              "fix the pattern syntax for this host's regex dialect (DR-085 §2 / DR-090 §2)",
            ),
          )
        }
      None => ()
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_invalid_dd_pattern(c.body, out)
  }
}

///|
/// DR-102 §2 の明確化 note (codex レビュー M-5): registry 所有ゲート — `regex_match` は scalar
/// filter registry のみが所有する descriptor (ARRAY filter registry は所有しない) なので、pattern
/// compile 検査は `regex_match` を実際に所有する registry を要求する属性 (`piece_filters`/
/// `value_filters`/`final_filters`) にのみ走る。`accum_filters` (ARRAY filter registry 専用) には
/// 一切走らない — 綴りが `regex_match` でも ARRAY registry の owns 集合に無いので
/// `collect_unknown_filter` が単純な unknown-vocab で reject するだけであり、layer 違いの副次検査は
/// 発生しない (DR-102 §2 の「自 registry のみを見る」単純化と矛盾しないための限定)。
///
/// DR-102 §3 の明確化 note (codex レビュー M-6): `final_filters` が wrong-seat (accum 要素または
/// `type:"none"` 要素、`collect_invalid_filter_attribute_mismatch` が invalid-range を出すケース)
/// の場合、本 gate はその中身 (pattern compile) を一切解釈しない — 構造ゲート先行で二重報告を避ける。
fn collect_invalid_regex_pattern(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  fn is_accum_elem(e : ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  fn check_chain(name : String, chain : Array[FilterSpelling]) -> Unit {
    for fs in chain {
      if fs.name == "regex_match" &&
        fs.args.length() == 1 &&
        compile_regex(fs.args[0]) is None {
        out.push(
          def_err(
            name,
            DInvalidArgument,
            "regex_match pattern '" + fs.args[0] + "' failed to compile",
            "fix the pattern syntax for this host's regex dialect (DR-085 §2)",
          ),
        )
      }
    }
  }

  fn check(e : ElemDef) -> Unit {
    check_chain(e.name, e.piece_filters)
    check_chain(e.name, e.value_filters)
    // final_filters: 正しい席 (非 accum かつ 非 none) の場合のみ pattern compile 検査
    // (M-6 wrong-seat gate 先行)。
    if !is_accum_elem(e) && e.ty != TNone {
      check_chain(e.name, e.final_filters)
    }
    // accum_filters: ARRAY filter registry は regex_match を所有しないため常にスキップ
    // (M-5 registry 所有ゲート)。
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_invalid_regex_pattern(c.body, out)
  }
}

///|
/// DR-084 §3 (issue multiple-ref-accum-gap): merge accumulator × ref is a definition-error. The
/// merge marker vocabulary (DR-080 §2) presupposes a separator-split STRING piece list (whole-
/// piece match against `@`/`-x`/`+`) — a `ref` element's firing value is a row (the referenced
/// template's or-branch consumption result, DR-078 §1), which never has a piece list at all, so
/// there is nothing for a marker to match against. Both `ref` and `multiple:{accumulator:"merge"}`
/// are declared, so the mismatch is known statically without I/O — same "構造的に宣言できるが実装
/// が対応できない組合せを definition-error で落とす" contract `collect_scalar_array_default`/
/// `collect_invalid_filter_attribute_mismatch` use.
fn collect_ref_merge_accum(def : Definition, out : Array[DefError]) -> Unit {
  fn check(e : ElemDef) -> Unit {
    if e.ref_target is Some(_) && e.accumulator is Some("merge") {
      out.push(
        def_err(
          e.name,
          DInvalidRange,
          "a `ref` element cannot use the merge accumulator — merge's marker vocabulary (DR-080 §2) requires a separator-split string piece list, but a ref element's firing value is a row (DR-078 §1), which has no piece list to match markers against",
          "use `multiple: \"append\"` (or omit `accumulator`, which defaults to append) instead of `accumulator: \"merge\"` on this ref element",
        ),
      )
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_ref_merge_accum(c.body, out)
  }
}

///|
/// DR-105 §2 (統括裁定 M-16, 存在ベース): `multiple.flatten` は `append` accumulator 専用のダイヤル
/// (DR-105 §1) — `merge`/`kv_map` 等それ以外の accumulator に `flatten` キーが宣言されていること
/// 自体 (true/false どちらの値でも) が構造不一致であり、`collect_ref_merge_accum`/
/// `collect_invalid_filter_attribute_mismatch` と同型の "構造的に宣言できるが実装が対応できない
/// 組合せを definition-error で落とす" 契約で kind=invalid-range を reject する (DR-102 §3 の
/// wrong-seat 判定と同型 — 中身の値は解釈しない、宣言の有無だけを見る)。`e.flatten is Some(_)` は
/// `dec_multiple` が「キーが JSON に存在したか」をそのまま運ぶ Option (`ElemDef.flatten`'s doc
/// comment) — `Some(false)` (明示 `flatten:false` 宣言) も違反として扱う。
fn collect_flatten_non_append(def : Definition, out : Array[DefError]) -> Unit {
  fn check(e : ElemDef) -> Unit {
    if e.multiple && e.flatten is Some(_) && e.accumulator is Some(_) {
      out.push(
        def_err(
          e.name,
          DInvalidRange,
          "'\{e.name}' declares multiple.flatten but its accumulator is not \"append\" (DR-105 §2) — flatten is an append-only dial, and this element's accumulator is \"" +
          e.accumulator.unwrap() +
          "\"",
          "remove 'flatten' from this element, or use accumulator:\"append\" (or omit accumulator, which defaults to append)",
        ),
      )
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_flatten_non_append(c.body, out)
  }
}

///|
/// DR-105 §3 (統括裁定 M-17): `multiple.accumulator` に宣言された名前が accumulators registry の
/// owns 集合 (`"append"`(既定, decode 層で None に写る) / `"merge"`(DR-080) / `"kv_map"`(DR-091 §2))
/// に無ければ definition-error kind=unknown-vocab — `collect_unknown_filter` (filter 4 属性の同型判定)
/// の accumulator 版。旧独立 "flatten" accumulator (DR-036/043、DR-105 で廃止) の綴りもここで弾かれる
/// — 廃止後は `{"accumulator":"append","flatten":true}` の組で表現する (DR-105 §1/§3)。
fn collect_unknown_accumulator(def : Definition, out : Array[DefError]) -> Unit {
  fn check(e : ElemDef) -> Unit {
    match e.accumulator {
      Some(a) =>
        if a != "merge" && a != "kv_map" {
          out.push(
            def_err(
              e.name,
              DUnknownVocab,
              "'\{e.name}' declares multiple.accumulator '" +
              a +
              "' which is not registered in the accumulators registry (DR-036/DR-105 §3) — the standalone \"flatten\" accumulator was retired by DR-105, use accumulator:\"append\" with flatten:true instead",
              "use a registered accumulator name (\"append\" [default, omit the key], \"merge\", \"kv_map\") or remove this declaration",
            ),
          )
        }
      None => ()
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_unknown_accumulator(c.body, out)
  }
}

///|
/// DR-105 §5/§8 (統括裁定 M-18): `in_range`(scalar filter registry) / `length_range`(ARRAY filter
/// registry, DR-105 §5 新設) の DSL 引数を definition time に静的検査する — `collect_invalid_regex_
/// pattern` の regex pattern compile 検査と同型 ("静的に既知は定義時に倒す", DR-083 §5 / DR-082 §3)。
/// 引数個数不一致・非数値は kind=invalid-argument (DR-082 §3 の「単一引数値そのものが装置の受理範囲外」)、
/// min>max は kind=invalid-range (DR-082 §2 の「複数属性の組合せが値域外」、`DInvalidRange` の
/// min>max 前例と同型)。filters.mbt の `filter_in_range`/`array_filter_length_range` 自身が持つ
/// runtime fallback (`filter_rejected`) を置換するのではなく、その手前で definition-error として
/// 確定させる — `regex_match` の pattern compile 検査と同じ「runtime 到達前に倒す」パターン。
/// 各 filter 名は自分の registry を要求する属性でのみ検査する (`in_range` は piece/value/final_filters、
/// `length_range` は accum_filters のみ) — cross-registry の綴り衝突 (`collect_unknown_filter` が
/// 別途 unknown-vocab で弾く) と二重報告しないための限定 (DR-102 §2 の「自 registry のみを見る」と
/// 同じ限定を踏襲)。wrong-seat (`collect_invalid_filter_attribute_mismatch` が invalid-range を出す
/// accum 要素の final_filters・非 accum 要素の accum_filters・`type:"none"` 要素) は
/// `collect_invalid_regex_pattern` と同じ構造ゲート先行で本 gate をスキップする (M-6/M-9 と同型)。
fn collect_invalid_numeric_filter_args(
  def : Definition,
  out : Array[DefError],
) -> Unit {
  fn is_accum_elem(e : ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  // DR-105 §5 明確化 note (a) (codex #3 反映): `length_range` の bound は非負整数限定 — 配列長という
  // 値域そのものの制約であり、`in_range` の canonical number (負数・小数も妥当) とは別の個別規則。
  // `n.to_int().to_double() == n` は整数性判定 (value.mbt の `value_str` の同型パターンを流用)。
  fn is_nonneg_int(n : Double) -> Bool {
    n >= 0.0 && n.to_int().to_double() == n
  }

  // `nonneg_int`: true なら `length_range` 専用の非負整数制約 (min/max それぞれ独立に
  // kind=invalid-argument、DR-082 §3「装置引数の値そのものが不正」) を追加で課す。`in_range` は
  // false のまま (canonical number、既存挙動を変えない)。
  fn check_two_arg(
    name : String,
    fs : FilterSpelling,
    nonneg_int : Bool,
  ) -> Unit {
    if fs.args.length() != 2 {
      out.push(
        def_err(
          name,
          DInvalidArgument,
          "'\{fs.name}' requires exactly 2 args (min, max), got \{fs.args.length()}",
          "provide exactly 2 numeric args, e.g. '\{fs.name}:1:5'",
        ),
      )
      return
    }
    let min = parse_number(fs.args[0])
    let max = parse_number(fs.args[1])
    match (min, max) {
      (None, _) =>
        out.push(
          def_err(
            name,
            DInvalidArgument,
            "'\{fs.name}' min '" + fs.args[0] + "' is not a number",
            "provide a numeric min",
          ),
        )
      (_, None) =>
        out.push(
          def_err(
            name,
            DInvalidArgument,
            "'\{fs.name}' max '" + fs.args[1] + "' is not a number",
            "provide a numeric max",
          ),
        )
      (Some(mn), Some(mx)) => {
        if nonneg_int {
          if !is_nonneg_int(mn) {
            out.push(
              def_err(
                name,
                DInvalidArgument,
                "'\{fs.name}' min \{mn} is not a non-negative integer",
                "provide a non-negative integer min, e.g. '\{fs.name}:0:5'",
              ),
            )
          }
          if !is_nonneg_int(mx) {
            out.push(
              def_err(
                name,
                DInvalidArgument,
                "'\{fs.name}' max \{mx} is not a non-negative integer",
                "provide a non-negative integer max, e.g. '\{fs.name}:0:5'",
              ),
            )
          }
        }
        if mn > mx {
          out.push(
            def_err(
              name,
              DInvalidRange,
              "'\{fs.name}' min \{mn} is greater than max \{mx}",
              "swap min/max so min <= max",
            ),
          )
        }
      }
    }
  }

  fn check_scalar_chain(name : String, chain : Array[FilterSpelling]) -> Unit {
    for fs in chain {
      if fs.name == "in_range" {
        check_two_arg(name, fs, false)
      }
    }
  }

  fn check_array_chain(name : String, chain : Array[FilterSpelling]) -> Unit {
    for fs in chain {
      if fs.name == "length_range" {
        check_two_arg(name, fs, true)
      }
    }
  }

  fn check(e : ElemDef) -> Unit {
    check_scalar_chain(e.name, e.piece_filters)
    check_scalar_chain(e.name, e.value_filters)
    if !is_accum_elem(e) && e.ty != TNone {
      check_scalar_chain(e.name, e.final_filters)
    }
    if is_accum_elem(e) && e.ty != TNone {
      check_array_chain(e.name, e.accum_filters)
    }
  }

  for e in def.options {
    check(e)
  }
  for e in def.positionals {
    check(e)
  }
  for c in def.commands {
    collect_invalid_numeric_filter_args(c.body, out)
  }
}

///|
/// 木のどこかに `type:"config_file"` 要素があるか (DR-050): あれば同型 config seat が全 value cell に立つ。
fn has_config_file(def : Definition) -> Bool {
  for e in def.options {
    if e.is_config_file {
      return true
    }
  }
  for e in def.positionals {
    if e.is_config_file {
      return true
    }
  }
  for c in def.commands {
    if has_config_file(c.body) {
      return true
    }
  }
  false
}

///|
/// config cycle (DR-050 §5 / DR-054): config_file 要素は config_key を持てない (自 path を config から
/// 引く循環)。全件収集。
fn collect_config_cycle(def : Definition, out : Array[DefError]) -> Unit {
  for e in def.options {
    if e.is_config_file && e.config_key is Some(_) {
      out.push(
        def_err(
          e.name,
          DConfigCycle,
          "config_file element '\{e.name}' cannot have a config_key (循環禁止)",
          "remove config_key from the config_file element",
        ),
      )
    }
  }
  for e in def.positionals {
    if e.is_config_file && e.config_key is Some(_) {
      out.push(
        def_err(
          e.name,
          DConfigCycle,
          "config_file element '\{e.name}' cannot have a config_key (循環禁止)",
          "remove config_key from the config_file element",
        ),
      )
    }
  }
  for c in def.commands {
    collect_config_cycle(c.body, out)
  }
}

///|
/// 1 scope 分の build 層の stable signature (fixpoint 検出用)。全て add-if-absent (monotonic 成長) で
/// 増えるので、build 層 (greedy / entities / positional / constraints) と宣言層 (decl.options) の要素数
/// 合計を Int で持てば十分。seat_env / seat_inherit は Entity 追加後に同 pass の apply_node で 1 回だけ
/// set され (idempotent)、以後の pass では既 set の値を上書きするだけなので、count-based sig で不動点に達する。
/// 注意: Node / Entity は Debug 派生のみで Show を持たないため、String 合成による sig は使えない (installer.mbt
/// から node.mbt を触らない制約下での回避策 — count-based で monotonic 成長を捕捉する)。
fn build_size(b : Build) -> Int {
  b.greedy.length() + b.entities.length() + b.constraints.length()
}

///|
fn tree_size(sb : SB) -> Int {
  let mut n = build_size(sb.build) + sb.decl.options.length()
  for child in sb.children {
    n = n + tree_size(child.body)
  }
  n
}

///|
/// scope-builder tree を Scope tree に materialize。subcommand は greedy `CmdSat(name, child)` に
/// (greedy-face resident; 排他 trigger が先食いで守り DR-018 priority、子は新 backbone DR-041 §4、fire
/// で親を sever)。
fn materialize(sb : SB) -> Scope {
  let greedy : Array[Node] = []
  for g in sb.build.greedy {
    greedy.push(g)
  }
  for child in sb.children {
    let cs = materialize(child.body)
    greedy.push(CmdSat(child.name, cs))
  }
  {
    greedy,
    positional: sb.build.positional,
    entities: sb.build.entities,
    constraints: sb.build.constraints,
  }
}

///|
/// UsefulAST → AtomicAST を installer chain として遂行 (DR-042)。`order` は適用 installer 列、5
/// invariants により結果は順序無依存。
///
/// chain は木全体で FIXPOINT まで回る (global が置いた宣言を後段 pass で long が展開する等の
/// inter-installer 依存を repeat で解決)。termination: add-if-absent と finite element×scope 空間
/// (copy of copy は name 同一で add-if-absent 止まる) により build 層が monotonically 成長し、変化なし
/// pass = fixpoint。
///
/// Returns Ok(atomic scope) or Err(全 definition-time errors)。static check は全て走って 1 list に append
/// (打ち切りなし)。各 DefError は {element, kind, message, hint} を持つ。
pub fn lower_definition(
  def0 : Definition,
  order : Array[Installer],
  registry? : Map[String, Node] = Map([], capacity=0),
) -> Result[Scope, Array[DefError]] {
  let def = clone_def(def0)
  // DR-076 §2 flag 差し替え/補完の alias 側適用 (issue 2026-07-08 dec-alias-long-override-flag-sugar-
  // gap): `desugar_aliases` は canonical 要素の「元の型」(TFlag のまま、resolve_long の規則1判定に
  // 必須) を必要とするが、`normalize_surface` は canonical 要素を TBool へ書き換えてしまい、この情報
  // を post-normalize な `def` から取り戻せない。normalize 前の複製を別途保持し、alias 解決時だけ
  // そちらを参照する (def 自体には normalize を通常どおり適用する — 二重 pipeline にしない)。
  let orig = clone_def(def0)
  let errs : Array[DefError] = []
  // DR-011 明確化 (2026-07-08): `:set` → kebab 展開 (normalize_surface) より前に検査する — 展開後は
  // sentinel `":set"` 自体が消え、有効な main entry と無効な残存文字列を区別できなくなる。
  collect_invalid_long_dsl(def, errs)
  // alias long_override も同じ colon DSL (DR-011 明確化は DSL が現れる全ての場所に効く)。desugar
  // (long_override → variants/long の展開) より前に検査する。
  collect_invalid_alias_long_override(def, errs)
  // 純構文 pre-pass (LOWERING §A / §C.4): `:set` → kebab (Fix 2, DR-071) + dd name 既定 "--" (Fix 3, DR-064 §5)
  normalize_surface(def)
  // init_sb が registry に repeat-lowering template を植える (静的 ref check が見えるように)。
  // alias entry-copies は ref/repeat を持たず、command alias は check 済 body を clone するので、
  // static check は pre-desugar def で回す (この 1 本目の tree は registry 植え込みのみが目的)。
  let _ = init_sb(def, registry)
  collect_vocab_intersection(order, errs) // DR-042③
  collect_unknown_vocab(def, order, errs) // DR-042① (alias vocab check 込み)
  collect_invalid_range(def, errs) // DR-052 (repeat min > max)
  collect_unsupported_option_ref_repeat(def, errs) // codex 指摘4 (option ref+repeat min>1 未配線)
  collect_unsupported_accum_update(def, errs) // issue accum-fold-update-default-ops (multiple + update variant)
  collect_unsupported_count_multiple(def, errs) // codex 指摘 High 2 (count 型 × multiple)
  collect_scalar_array_default(def, errs) // DR-083 §5 (非 accum 要素への配列 default)
  collect_tty_stream_missing(def, errs) // DR-099 §3/§7 (builtin/tty preset の tty_stream 必須違反)
  collect_none_value_source_decl(def, errs) // DR-089 §4 (none への env/config_key/inherit 宣言)
  collect_unknown_filter(def, errs) // DR-101 / DR-102 §1/§2 (filter 4 属性それぞれ自 registry のみで unknown-vocab)
  collect_invalid_filter_attribute_mismatch(def, errs) // DR-102 §1/§3 (final_filters/accum_filters と要素の accum 適格性の排他制約)
  collect_invalid_regex_pattern(def, errs) // DR-085 §1 訂正 (regex_match pattern compile 失敗)
  collect_invalid_dd_pattern(def, errs) // DR-090 §2 (dd match pattern compile 失敗)
  collect_ref_merge_accum(def, errs) // DR-084 §3 (merge accumulator × ref)
  collect_flatten_non_append(def, errs) // DR-105 §2 (M-16, flatten は append 専用ダイヤル)
  collect_unknown_accumulator(def, errs) // DR-105 §3 (M-17, multiple.accumulator の未登録名)
  collect_invalid_numeric_filter_args(def, errs) // DR-105 §5/§8 (M-18, in_range/length_range の DSL 引数)
  collect_absent_ref(def, registry, errs) // DR-032
  collect_circular_ref(registry, errs) // DR-007/032
  collect_zero_progress(def, registry, errs) // DR-043
  collect_config_cycle(def, errs) // DR-050 §5
  if errs.length() > 0 {
    return Err(errs) // ALL definition-error 列挙
  }
  // alias 宣言 desugar (DR-057): 完全性検査 pass 後、決定的 pre-pass。option entry-copies /
  // command defs を追加 — fixpoint installer が展開する。
  desugar_aliases(def, orig)
  let sb = init_sb(def, registry) // desugar 済 def で scope tree 再構築
  // 同型 default (DR-050 §3): config_file 要素があれば全 value cell に config seat を宣言。1 度計算、
  // ensure_entity に thread。
  let has_cf = has_config_file(def)
  let mut iters = 0
  while true {
    let prev = tree_size(sb)
    tree_pass(order, sb, has_cf, registry)
    if tree_size(sb) == prev {
      break
    }
    iters = iters + 1
    if iters > 100 {
      return Err([
        def_err(
          "(chain)",
          DUnknownVocab,
          "installer chain did not converge (> 100 iterations)",
          "check for a runaway global copy or a mis-registered installer",
        ),
      ])
    }
  }
  Ok(materialize(sb))
}
