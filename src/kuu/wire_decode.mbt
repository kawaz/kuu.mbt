// wire_decode.mbt — wire JSON (definition) の decode をプロダクションコードとして提供する層。
//
// MDR-005 (kuu-core 正面玄関 API): `json_conformance_test.mbt` に埋もれていた definition
// decode (`dec_definition` とその依存関数群) をここへ昇格する。conformance runner は本ファイル
// の decoder をそのまま呼ぶ (ドッグフーディング) — expect 面の decode / fixture 全体の decode /
// lowering 断面の decode はテストハーネス固有のまま `json_conformance_test.mbt` に残る。
//
// `DecodeSkip` は wire JSON が構文として崩れている場合の signal (未知キー・型不一致・必須キー
// 欠如)。DR-054 の definition-error (`Array[@engine.DefError]`、`parse_definition` が返す) とは別の層 —
// wire.schema.json が additionalProperties を開けたまま残す語彙層の検査をここが担う。

// ── deprecated-free Json accessors (moon nightly: as_* 系は deprecated) ───────

///|
fn Json::j_obj(self : Json) -> Map[String, Json]? {
  if self is Object(m) {
    Some(m)
  } else {
    None
  }
}

///|
fn Json::j_arr(self : Json) -> Array[Json]? {
  if self is Array(a) {
    Some(a)
  } else {
    None
  }
}

///|
fn Json::j_str(self : Json) -> String? {
  if self is String(x) {
    Some(x)
  } else {
    None
  }
}

///|
fn Json::j_bool(self : Json) -> Bool? {
  if self is True {
    Some(true)
  } else if self is False {
    Some(false)
  } else {
    None
  }
}

///|
fn Json::j_num(self : Json) -> Double? {
  if self is Number(n, ..) {
    Some(n)
  } else {
    None
  }
}

// ── generic set-membership helper for arrays of strings ────────────────────────

///|
fn conformance_str_in(xs : Array[String], v : String) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}
// ═══════════════════════════════════════════════════════════════════════════════
// SECTION 2 — Builders (mirror slice helpers: opt/pos/dd_marker/cmd/alias/rep/def_)
// ═══════════════════════════════════════════════════════════════════════════════

///|
fn empty_help_meta() -> @engine.HelpMetaDecl {
  {
    help: None,
    help_long: None,
    help_epilog: None,
    display_name: None,
    value_name: None,
    help_group_name: None,
    help_group_title: None,
    help_group_description: None,
    help_order: None,
    help_group_order: None,
    help_after: None,
  }
}

///|
fn help_meta_from_object(o : Map[String, Json]) -> @engine.HelpMetaDecl {
  {
    help: jf_str(o, "help"),
    help_long: jf_str(o, "help_long"),
    help_epilog: jf_str(o, "help_epilog"),
    display_name: jf_str(o, "display_name"),
    value_name: jf_str(o, "value_name"),
    help_group_name: jf_str(o, "help_group_name"),
    help_group_title: jf_str(o, "help_group_title"),
    help_group_description: jf_str(o, "help_group_description"),
    help_order: match o.get("help_order") {
      Some(value) => value.j_num()
      None => None
    },
    help_group_order: match o.get("help_group_order") {
      Some(value) => value.j_num()
      None => None
    },
    help_after: jf_str(o, "help_after"),
  }
}

///|
fn opt(
  name : String,
  ty : &@engine.TypeExt,
  long? : @engine.LongDecl = LList([]),
  variants? : Array[@engine.Variant] = [],
  short? : Array[Char] = [],
  env? : Array[String] = [],
  help_meta? : @engine.HelpMetaDecl = empty_help_meta(),
  is_tty? : Bool = false,
  tty_stream? : String? = None,
  tty_cygwin? : Bool = true,
  global? : Bool = false,
  inherit_? : Bool = false,
  inheritable? : Bool = false,
  repeat? : @engine.RepeatSpec? = None,
  multiple? : Bool = false,
  accumulator? : String? = None,
  flatten? : Bool? = None,
  collector? : String? = None,
  fail_action? : Bool = false,
  config_file? : Bool = false,
  config_key? : Array[String]? = None,
  export_? : @engine.ExportKey = @engine.export_key_unset(),
  requires? : Array[String] = [],
  conflicts? : Array[String] = [],
  exclusive? : Array[String] = [],
  required_group? : Array[String] = [],
  required? : Bool = false,
  value_requires? : Array[(String, String, Array[String])] = [],
  default? : Array[@engine.Value]? = None,
  default_fn? : @engine.DefaultFnCall? = None,
  default_declared? : Bool = false,
  int_round? : @engine.RoundMode = @engine.RError,
  allow_base_prefix? : Bool = false,
  bool_config? : @engine.BoolConfig = @builtins.bool_config_canonical(),
  piece_filters? : Array[@engine.FilterSpelling] = [],
  value_filters? : Array[@engine.FilterSpelling] = [],
  final_filters? : Array[@engine.FilterSpelling] = [],
  accum_filters? : Array[@engine.FilterSpelling] = [],
  ref_? : String? = None,
  long_prefix? : String = "--",
  short_prefix? : String = "-",
  env_prefix? : String = "",
  auto_env? : Bool = false,
  long_eq_sep? : @engine.EqSepMode = @engine.EsAllow,
  short_combine? : Bool = true,
  short_attached_value? : @engine.AttachMode = @engine.AtAllow,
  body? : @engine.ElemBody = BCell,
  // DR-104 §2/§4: option 専用の hidden 宣言 (meta.json fixture)。dec_option がここへ渡し、
  // ensure_entity 経由で @engine.Entity.hidden へ carry される。alias は @engine.AliasDef に独立宣言経路が無いので
  // is_alias は opt() の返す @engine.ElemDef 上では常に false (alias_entry が別途 true で構築する)。
  hidden? : Bool = false,
  // DR-060 §4 / DR-104 §2(d) / issue 2026-07-14-cand-completer-followup: the wire `completer:
  // "<名前>"` attribute. `dec_option` reads it and passes it here; `ensure_entity` carries it
  // through to `@engine.Entity.completer` (same carrier pattern as `hidden`).
  completer? : String? = None,
) -> @engine.ElemDef {
  {
    name,
    ty,
    long,
    variants,
    short,
    env,
    help_meta,
    is_tty,
    tty_stream,
    tty_cygwin,
    is_dd: false,
    is_exact: false,
    dd_match: None,
    dd_self_keep: false,
    is_global: global,
    is_inherit: inherit_,
    is_inheritable: inheritable,
    link_depth: 0,
    ref_target: ref_,
    repeat,
    optional: false,
    multiple,
    accumulator,
    flatten,
    separator: None,
    collector,
    fail_action,
    is_config_file: config_file,
    config_key,
    export_key: export_,
    requires,
    conflicts_with: conflicts,
    exclusive_group: exclusive,
    required_group,
    required,
    value_requires,
    deprecated: false,
    is_alias: false,
    hidden,
    completer,
    default_values: default,
    default_fn,
    default_declared,
    int_round,
    allow_base_prefix,
    bool_config,
    piece_filters,
    value_filters,
    final_filters,
    accum_filters,
    long_prefix,
    short_prefix,
    env_prefix,
    auto_env,
    long_eq_sep,
    short_combine,
    short_attached_value,
    body,
  }
}

///|
fn pos(
  name : String,
  ty : &@engine.TypeExt,
  inherit_? : Bool = false,
  repeat? : @engine.RepeatSpec? = None,
  optional? : Bool = false,
  multiple? : Bool = false,
  accumulator? : String? = None,
  flatten? : Bool? = None,
  separator? : String? = None,
  collector? : String? = None,
  config_key? : Array[String]? = None,
  export_? : @engine.ExportKey = @engine.export_key_unset(),
  ref_? : String? = None,
  default? : Array[@engine.Value]? = None,
  default_fn? : @engine.DefaultFnCall? = None,
  default_declared? : Bool = false,
  int_round? : @engine.RoundMode = @engine.RError,
  allow_base_prefix? : Bool = false,
  bool_config? : @engine.BoolConfig = @builtins.bool_config_canonical(),
  piece_filters? : Array[@engine.FilterSpelling] = [],
  value_filters? : Array[@engine.FilterSpelling] = [],
  final_filters? : Array[@engine.FilterSpelling] = [],
  accum_filters? : Array[@engine.FilterSpelling] = [],
  env? : Array[String] = [],
  help_meta? : @engine.HelpMetaDecl = empty_help_meta(),
  is_tty? : Bool = false,
  tty_stream? : String? = None,
  tty_cygwin? : Bool = true,
  required? : Bool = false,
  requires? : Array[String] = [],
  // DR-012 / DR-055 / DR-103: constraint 系は「要素属性」なので positional にも同型に付与できる。
  // engine の CConflicts/CExclusive/CRequired/CRequiredGroup は committed 判定を entity 名で行い
  // option/positional を区別しないため、decode 側で pos() に流し込むだけで検査が動く (opt() の
  // 同名フィールドと対称)。value_requires は positional では trigger 経路がない (positional の or は
  // structural 専用、`values` キー未 allowed) ため対称化せず既存の空配列固定のまま残す (下記
  // `value_requires: []` 参照)。
  conflicts? : Array[String] = [],
  exclusive? : Array[String] = [],
  required_group? : Array[String] = [],
  // DR-060 §4 / DR-104 §2(d): a positional's value slot can name a dynamic completer too (e.g. a
  // file-path positional) — unlike `hidden` (an option-only 補完 policy axis this file omits for
  // positionals), `completer` targets the VALUE position itself, which positionals have just as
  // much as options do.
  completer? : String? = None,
  body? : @engine.ElemBody = BCell,
) -> @engine.ElemDef {
  {
    name,
    ty,
    long: LList([]),
    variants: [],
    short: [],
    env,
    help_meta,
    is_tty,
    tty_stream,
    tty_cygwin,
    is_dd: false,
    is_exact: false,
    dd_match: None,
    dd_self_keep: false,
    is_global: false,
    is_inherit: inherit_,
    is_inheritable: false,
    link_depth: 0,
    ref_target: ref_,
    repeat,
    optional,
    multiple,
    accumulator,
    flatten,
    separator,
    collector,
    fail_action: false,
    is_config_file: false,
    config_key,
    export_key: export_,
    requires,
    conflicts_with: conflicts,
    exclusive_group: exclusive,
    required_group,
    required,
    // DR-055 §5.3 の value-enum-or は option 限定 (positional の or は structural 専用、`values` キー
    // 未 allowed) — positional 要素直属の value_requires を組む wire 経路が現時点で存在しないため
    // 空配列固定 (structural or の各枝は BOr(items) の 1 要素 = positional 要素自身なので、値依存
    // requires は各枝要素の requires 属性で表現される)。
    value_requires: [],
    deprecated: false,
    // DR-104 §2/§3: positional は alias/hidden 宣言経路を wire に持たない (現行 fixture が要求しない)
    // ので常に false — opt() の同フィールドと対称。
    is_alias: false,
    hidden: false,
    completer,
    default_values: default,
    default_fn,
    default_declared,
    int_round,
    allow_base_prefix,
    bool_config,
    piece_filters,
    value_filters,
    final_filters,
    accum_filters,
    // positional 要素は long/short spelling を持たない (`long: LList([])`/`short: []` 上、`long_of`
    // は常に [] を返す) — `long_prefix`/`long_eq_sep`/`short_prefix`/`short_attached_value`/
    // `short_combine` は long/short-only 語彙なので既定値のまま未使用フィールドとして持ち回るだけ
    // (`opt`/`inst_long`/`inst_short` 側の実際の消費経路と同じ理由付け)。`env_prefix`/`auto_env` は
    // env 席が positional にも効く (`inst_env` が def.positionals も走査) ため、`dec_definition` が
    // 呼び出し側でこの2つだけ scope config を焼き込む (下記コメント参照)。
    long_prefix: "--",
    short_prefix: "-",
    env_prefix: "",
    auto_env: false,
    long_eq_sep: @engine.EsAllow,
    short_combine: true,
    short_attached_value: @engine.AtAllow,
    body,
  }
}

///|
fn dd_marker(
  match_? : String? = None,
  self_keep? : Bool = false,
  required? : Bool = false,
) -> @engine.ElemDef {
  {
    name: "--",
    ty: @builtins.string_type(),
    long: LList([]),
    variants: [],
    short: [],
    env: [],
    help_meta: empty_help_meta(),
    // DR-099 §1: dd (type:"dd") と builtin/tty は `type:` の別選択なので同一要素に同時発生し得ない
    // (DR-098 §4 が必要とした dd-vs-tty definition-error は構文的に発生しなくなった) — dd_marker は
    // is_tty/tty_stream を常に canonical default のまま持ち回るだけの冗長フィールド。
    is_tty: false,
    tty_stream: None,
    tty_cygwin: true,
    is_dd: true,
    is_exact: false,
    dd_match: match_,
    dd_self_keep: self_keep,
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
    export_key: @engine.export_key_unset(),
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    required_group: [],
    required,
    value_requires: [],
    deprecated: false,
    is_alias: false,
    hidden: false,
    completer: None, // dd は値空間を持たない (DR-089) — completer が意味を持つ値位置スロットが無い
    default_values: None,
    default_fn: None,
    default_declared: false,
    int_round: @engine.RError,
    allow_base_prefix: false,
    bool_config: @builtins.bool_config_canonical(),
    piece_filters: [],
    value_filters: [],
    final_filters: [],
    accum_filters: [],
    // dd marker element も `long: LList([])` で long spelling を持たない — 同じ理由で既定値。
    long_prefix: "--",
    short_prefix: "-",
    env_prefix: "",
    auto_env: false,
    long_eq_sep: @engine.EsAllow,
    short_combine: true,
    short_attached_value: @engine.AtAllow,
    body: BCell,
  }
}

///|
/// issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め: a positional-face
/// nameless exact-match leaf (`{"exact": "init"}`, DR-063 A.1 裸文字列→exact 正規化 / DR-018 配置で
/// 役割決定 — dec_positional の裸 `"exact"` 分岐から作る)。`is_dd`/`dd_marker` と同じ carrier
/// パターン — `name` が trigger 綴りを運び (`is_exact` の doc comment 参照)、`@builtins.elem_head`
/// (installer.mbt) が `@engine.Exact(name)` へ直接 lower する (value_prim/entity 経路を通らない、
/// `ensure_entities` が is_dd と同じガードでスキップする)。`ty: @builtins.none_type()` は値空間を持たない照合消費
/// (dd_marker の `ty: @builtins.string_type()` と違うのは、dd が「捨てるが型タグは要る」旧経路の名残であるのに対し
/// exact literal は値スロット自体が最初から無いため — DR-089 §2「type 省略 = none の糖衣」と同じ既定
/// 型)。
fn exact_marker(spelling : String) -> @engine.ElemDef {
  {
    name: spelling,
    ty: @builtins.none_type(),
    long: LList([]),
    variants: [],
    short: [],
    env: [],
    help_meta: empty_help_meta(),
    is_tty: false,
    tty_stream: None,
    tty_cygwin: true,
    is_dd: false,
    is_exact: true,
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
    export_key: @engine.export_key_unset(),
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    required_group: [],
    required: false,
    value_requires: [],
    deprecated: false,
    is_alias: false,
    hidden: false,
    completer: None, // exact literal は値空間を持たない — dd_marker と同じ理由
    default_values: None,
    default_fn: None,
    default_declared: false,
    int_round: @engine.RError,
    allow_base_prefix: false,
    bool_config: @builtins.bool_config_canonical(),
    piece_filters: [],
    value_filters: [],
    final_filters: [],
    accum_filters: [],
    long_prefix: "--",
    short_prefix: "-",
    env_prefix: "",
    auto_env: false,
    long_eq_sep: @engine.EsAllow,
    short_combine: true,
    short_attached_value: @engine.AtAllow,
    body: BCell,
  }
}

// ── skip signal ────────────────────────────────────────────────────────────────

///|
/// wire JSON の構文検査 signal (MDR-005 §1)。`parse_definition` (front_door.mbt) がこれを
/// catch して `DefLoadError::Malformed` に写像する — 外部シグネチャには型として現れないので priv。
priv suberror DecodeSkip {
  DecodeSkip(String)
  /// A syntactically valid element naming a type resident absent from the active assembly.
  /// front_door maps this variant to DR-054's definition-error face rather than Malformed.
  UnknownType(String, String) // element, type name
}

///|
priv enum DElem {
  DOpt(@engine.ElemDef)
  DAlias(@engine.AliasDef)
}

///|
priv enum DCmd {
  DCommand(@engine.CommandDef)
  DCmdAlias(@engine.AliasDef)
}

///|
priv struct InstallerDecoded {
  vocab : Array[String]
  long : @engine.LongDecl
  short : Array[Char]
  env : Array[String]
  dd_match : String?
  dd_self_keep : Bool
  global_ : Bool
  inherit_ : Bool
  repeat : @engine.RepeatSpec?
  optional : Bool
  multiple : Bool
  separator : String?
  collector : String?
  accumulator : String?
  flatten : Bool?
  config_file : Bool
  config_key : Array[String]?
  requires : Array[String]
  conflicts : Array[String]
  exclusive : Array[String]
  required_group : Array[String]
  required : Bool
  alias_decl : @engine.AliasDef?
  inheritable : Bool
  help_meta : @engine.HelpMetaDecl
}

///|
fn decode_installer_owned(
  json : Json,
  context : @engine.DecodeCtx,
  extensions : @engine.Registry,
) -> InstallerDecoded raise DecodeSkip {
  let vocab : Array[String] = []
  let mut long : @engine.LongDecl = LList([])
  let mut short : Array[Char] = []
  let mut env : Array[String] = []
  let mut dd_match : String? = None
  let mut dd_self_keep = false
  let mut global_ = false
  let mut inherit_ = false
  let mut repeat : @engine.RepeatSpec? = None
  let mut optional = false
  let mut multiple = false
  let mut separator : String? = None
  let mut collector : String? = None
  let mut accumulator : String? = None
  let mut flatten : Bool? = None
  let mut config_file = false
  let mut config_key : Array[String]? = None
  let mut requires : Array[String] = []
  let mut conflicts : Array[String] = []
  let mut exclusive : Array[String] = []
  let mut required_group : Array[String] = []
  let mut required = false
  let mut alias_decl : @engine.AliasDef? = None
  let mut inheritable = false
  let mut help_meta = empty_help_meta()
  for installer in extensions.installers() {
    let decoded = match installer.decode(json, context) {
      Ok(value) => value
      Err(reason) => raise DecodeSkip(reason)
    }
    for key in decoded.vocab {
      if !conformance_str_in(vocab, key) {
        vocab.push(key)
      }
    }
    match decoded.declaration {
      ODLong(value) => long = value
      ODShort(value) => short = value
      ODEnv(value) => env = value
      ODDd(match_, self_keep) => {
        dd_match = match_
        dd_self_keep = self_keep
      }
      ODGlobal(value) => global_ = value
      ODInherit(value) => inherit_ = value
      ODRepeat(spec, option) => {
        repeat = spec
        optional = option
      }
      ODMultiple(enabled, sep, coll, accum, flat) => {
        multiple = enabled
        separator = sep
        collector = coll
        accumulator = accum
        flatten = flat
      }
      ODConfig(is_file, key) => {
        config_file = is_file
        config_key = key
      }
      ODConstraint(reqs, confs, groups, required_groups, is_required) => {
        requires = reqs
        conflicts = confs
        exclusive = groups
        required_group = required_groups
        required = is_required
      }
      ODAlias(value) => alias_decl = value
      ODInheritable(value) => inheritable = value
      ODHelpMeta(value) => help_meta = value
      ODCommand => ()
    }
  }
  {
    vocab,
    long,
    short,
    env,
    dd_match,
    dd_self_keep,
    global_,
    inherit_,
    repeat,
    optional,
    multiple,
    separator,
    collector,
    accumulator,
    flatten,
    config_file,
    config_key,
    requires,
    conflicts,
    exclusive,
    required_group,
    required,
    alias_decl,
    inheritable,
    help_meta,
  }
}
// ── JSON helpers ──────────────────────────────────────────────────────────────

///|
fn jf_str(o : Map[String, Json], key : String) -> String? {
  match o.get(key) {
    Some(j) => j.j_str()
    None => None
  }
}

///|
/// DR-067 §2 name/id 構文制約 (codex 節目レビュー指摘1, issue 2026-07-09-ref-template-result-shape):
/// `#` を含む name/id はユーザ定義で禁止 — repeat lowering の内部 template キー
/// (`e.name + "#cons"`, installer.mbt `lower_repeat_head`)・`next_or_branch_id`'s 自動採番
/// ("#0"/"#1"/…)・resolve.mbt の row/fire sentinel ("#row"/"#fire") が共有する予約名前空間
/// (DR-046 §4)。id 未指定なら name が id を兼ねる (DR-046 §2) ため name にも同じ制約が及ぶ — ここを
/// enforce しないと `{"name": "src#cons"}` のような wire がその内部キーと衝突しうる。既存の decode
/// error と同じ語彙 (`raise DecodeSkip`) で reject する。呼び出し側は name/id を読んだ「その場」で
/// これを通す (missing チェックの直後、他フィールドの decode より前 — 診断が name/id の妥当性で早期
/// に止まるようにする)。
fn check_reserved_name(name : String, what : String) -> Unit raise DecodeSkip {
  if name.contains("#") {
    raise DecodeSkip(
      what +
      " name/id '" +
      name +
      "' contains '#' (DR-067 §2: '#' はユーザ定義で禁止、内部予約名前空間)",
    )
  }
}

///|
fn has_key(o : Map[String, Json], k : String) -> Bool {
  match o.get(k) {
    Some(_) => true
    None => false
  }
}

///|
/// codex レビュー Major 3 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見):
/// whether `o` has EXACTLY `k` and no other key. `dec_positional`'s bare `{"exact": "..."}` shape
/// detector uses this instead of an explicit deny-list of "other keys with no defined meaning here"
/// (`repeat`/`optional`/`multiple`/`default`/`piece_filters`/... — the old form silently dropped
/// any key it forgot to list, e.g. `{"exact":"init","repeat":{...}}` decoded successfully with
/// `repeat` thrown away). Checking against the POSITIVE allow-set of 1 (rather than a growing
/// negative deny-list) means any key `dec_positional`'s `allowed_keys` call adds in the future is
/// automatically rejected here too when combined with `exact` — no separate list to keep in sync.
fn only_key(o : Map[String, Json], k : String) -> Bool {
  for key, _ in o {
    if key != k {
      return false
    }
  }
  true
}

///|
fn allowed_keys(
  o : Map[String, Json],
  allowed : Array[String],
  what : String,
) -> Unit raise DecodeSkip {
  for k, _ in o {
    if !conformance_str_in(allowed, k) {
      raise DecodeSkip(what + " has unsupported key '" + k + "'")
    }
  }
}

///|
fn bool_field(
  o : Map[String, Json],
  k : String,
  dflt : Bool,
) -> Bool raise DecodeSkip {
  match o.get(k) {
    None => dflt
    Some(j) =>
      match j.j_bool() {
        Some(b) => b
        None => raise DecodeSkip(k + " is not a bool")
      }
  }
}

///|
fn json_to_value(j : Json) -> @engine.Value raise DecodeSkip {
  match j.j_bool() {
    Some(b) => return @engine.VBool(b)
    None => ()
  }
  match j.j_str() {
    Some(s) => return @engine.VStr(s)
    None => ()
  }
  match j.j_num() {
    Some(d) => return @engine.VNum(d)
    None => ()
  }
  raise DecodeSkip("non-scalar value in effects/result")
}

///|
/// DR-083 §1: a declared `"default"` decodes to the length-1-degenerate array uniformly — a bare
/// JSON scalar lifts to a single-piece array (`[v]`), a JSON array decodes elementwise (one @engine.Value
/// per already-split piece, DR-083 §2). Which shape is STRUCTURALLY legal for a given element
/// (scalar element ⇒ length must end up 1) is a definition-time check, NOT a decode-time gate —
/// `collect_scalar_array_default` (installer.mbt) is the one that rejects a >1-length default on a
/// non-accum element; this decoder accepts either JSON shape unconditionally.
fn json_to_default_values(j : Json) -> Array[@engine.Value] raise DecodeSkip {
  match j.j_arr() {
    Some(a) => {
      let vs : Array[@engine.Value] = []
      for it in a {
        vs.push(json_to_value(it))
      }
      vs
    }
    None => [json_to_value(j)]
  }
}

///|
fn dec_default_fn(j : Json) -> @engine.DefaultFnCall raise DecodeSkip {
  match j.j_str() {
    Some(spelling) =>
      match @engine.parse_fn_invocation(@engine.ColonString(spelling)) {
        Ok(invocation) => @engine.WireDefaultFn(invocation)
        Err(message) => raise DecodeSkip(message)
      }
    None =>
      match j.j_arr() {
        Some(parts_json) => {
          let parts : Array[String] = []
          for part_json in parts_json {
            match part_json.j_str() {
              Some(part) => parts.push(part)
              None =>
                raise DecodeSkip("default_fn array element is not a string")
            }
          }
          match @engine.parse_fn_invocation(@engine.ArrayParts(parts)) {
            Ok(invocation) => @engine.WireDefaultFn(invocation)
            Err(message) => raise DecodeSkip(message)
          }
        }
        None => raise DecodeSkip("default_fn is not a string or string[]")
      }
  }
}

///|
fn dec_strs(j : Json?) -> Array[String] raise DecodeSkip {
  match j {
    None => []
    Some(x) =>
      match x.j_str() {
        Some(s) => [s]
        None =>
          match x.j_arr() {
            Some(a) => {
              let r : Array[String] = []
              for e in a {
                match e.j_str() {
                  Some(s) => r.push(s)
                  None =>
                    raise DecodeSkip("string-array element is not a string")
                }
              }
              r
            }
            None => raise DecodeSkip("expected a string or string[]")
          }
      }
  }
}

///|
/// Decode a filters-chain field (`piece_filters`/`value_filters`/`final_filters`/`accum_filters`)
/// into the engine-owned universal invocation carrier. Each chain entry accepts
/// a colon shorthand string, a DR-114 one-level string array, or the structured
/// object form. Array and object args remain literal, including embedded colons.
/// `dec_strs` is not reused because the other string-list attributes do not
/// carry nested invocation entries.
fn dec_filter_chain(
  j : Json?,
) -> Array[@engine.FilterSpelling] raise DecodeSkip {
  match j {
    None => []
    Some(x) =>
      match x.j_str() {
        Some(s) => [@builtins.parse_filter_shorthand(s)]
        None =>
          match x.j_arr() {
            Some(a) => {
              let r : Array[@engine.FilterSpelling] = []
              for e in a {
                match e.j_str() {
                  Some(s) => r.push(@builtins.parse_filter_shorthand(s))
                  None =>
                    match e.j_arr() {
                      Some(parts_json) => {
                        let parts : Array[String] = []
                        for part_json in parts_json {
                          match part_json.j_str() {
                            Some(part) => parts.push(part)
                            None =>
                              raise DecodeSkip(
                                "filter array-form element is not a string",
                              )
                          }
                        }
                        match
                          @engine.parse_fn_invocation(@engine.ArrayParts(parts)) {
                          Ok(invocation) => r.push(invocation)
                          Err(message) => raise DecodeSkip(message)
                        }
                      }
                      None =>
                        match e.j_obj() {
                          Some(o) => {
                            allowed_keys(
                              o,
                              ["name", "args"],
                              "filter (object form)",
                            )
                            let name = match jf_str(o, "name") {
                              Some(n) => n
                              None =>
                                raise DecodeSkip(
                                  "filter object form missing 'name'",
                                )
                            }
                            let args = match o.get("args") {
                              Some(aj) =>
                                match aj.j_arr() {
                                  Some(aa) => {
                                    let out : Array[String] = []
                                    for av in aa {
                                      match av.j_str() {
                                        Some(s) => out.push(s)
                                        None =>
                                          raise DecodeSkip(
                                            "filter object form 'args' element is not a string",
                                          )
                                      }
                                    }
                                    out
                                  }
                                  None =>
                                    raise DecodeSkip(
                                      "filter object form 'args' is not an array",
                                    )
                                }
                              None => []
                            }
                            r.push({ name, args })
                          }
                          None =>
                            raise DecodeSkip(
                              "filter chain element is not a string, string array, or object",
                            )
                        }
                    }
                }
              }
              r
            }
            None =>
              raise DecodeSkip(
                "expected a string or filter[] (string | string[] | object form)",
              )
          }
      }
  }
}
// ── definition decoders ───────────────────────────────────────────────────────

///|
/// Decode a wire type name through the active assembly's type-resident inventory.
fn dec_ty(
  type_name : String,
  element : String,
  extensions : @engine.Registry,
) -> &@engine.TypeExt raise DecodeSkip {
  match extensions.lookup_type(type_name) {
    Some(resident) => resident
    None => raise UnknownType(element, type_name)
  }
}

///|
/// DR-061 §3 configurable factory の type shadow: user 定義の型名を base type resident + parse 相 config に
/// 解決する。fixture の `definitions.types.<name>` → TypeShadow の map で保持し、dec_option /
/// dec_positional の `type: "<name>"` 解決で consultation する。canonical 型名 (string/number/int/...)
/// は shadow で override 可能だが本 fixture では未使用 (`int_parser`/`number_parser`/`bool_parser`/
/// `tty` factory のみ扱う)。
priv struct TypeShadow {
  base : &@engine.TypeExt
  int_round : @engine.RoundMode
  // DR-074 §2 `number_allow_base_prefix` (`number_parser` factory config)。canonical default = false。
  // TypeShadow が担う base 側の flag は canonical default が false なので、int_round と直交な平坦キー。
  allow_base_prefix : Bool
  // DR-074 §4 `bool_parser` factory config (`bool_true_values`/`bool_false_values`/`bool_case_insensitive` (DR-100 prefix 正準) を 1
  // struct に束ねた carrier、@engine.ElemDef.bool_config と同型)。canonical default = `@builtins.bool_config_canonical()`。
  bool_config : @engine.BoolConfig
  // DR-099 §1/§3 `builtin/tty` factory: base=@builtins.bool_type() + is_tty マーカー + tty_stream (必須 config、
  // 未指定は definition-error) + tty_cygwin (既定 true)。他 factory と同じ「平坦 config キーを
  // shadow に carry するだけ」パターン (@engine.ElemDef.is_tty/tty_stream/tty_cygwin と同型)。
  is_tty : Bool
  tty_stream : String?
  tty_cygwin : Bool
}

///|
/// Decode `definitions.types` (DR-061 §3 `{name: <factory>, config: {<key>: <value>, ...}}`) into
/// a shadow map. 各 shadow は base type resident (factory 名から導出) と平坦 config キーで構成される。
/// 現状サポート: `int_parser` (base = @builtins.int_type()、config = `int_round`)、`number_parser` (base = @builtins.number_type()、
/// config = `number_allow_base_prefix`)、`bool_parser` (base = @builtins.bool_type()、config = `bool_true_values` /
/// `false_values` / `case_insensitive`、DR-074 §3/§4)。他の factory 名は DecodeSkip で明示的に
/// unsupported 扱い (typo 検出、DR-061 §4 は factory 自身が config 値を検証する規定なので、
/// type/factory 認識のこの層は capability gate として振る舞う)。
///
/// DR-094 §3/§9 案A: factory 名は `<bare>` (builtin ns の糖衣) / `builtin/<bare>` (ns 明示) の
/// 2 形が同一実体に解決される。旧 ad-hoc prefix `kuu_<bare>` は fixture pin bump (37aa3b3d) 完了に
/// 伴い移行期間を終え、unsupported factory として明示的に拒否される (unknown-vocab の一部、
/// DR-054)。
fn dec_types(j : Json) -> Map[String, TypeShadow] raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("definitions.types is not an object")
  }
  let out : Map[String, TypeShadow] = Map([])
  for name, tj in o {
    let to = match tj.j_obj() {
      Some(x) => x
      None =>
        raise DecodeSkip(
          "definitions.types[" +
          name +
          "] is not an object (expected {name, config})",
        )
    }
    allowed_keys(to, ["name", "config"], "type shadow")
    let factory = match jf_str(to, "name") {
      Some(s) => s
      None =>
        raise DecodeSkip(
          "definitions.types[" + name + "] missing factory 'name'",
        )
    }
    match factory {
      "int_parser" | "builtin/int_parser" => {
        // DR-075 §2 int_round (10 モード語彙、@builtins.round_mode_of で解決) + DR-074 §2 の (int にも波及する)
        // `number_allow_base_prefix`。config 未指定は canonical default (@engine.RError + false)。
        let mut mode = @engine.RError
        let mut base_prefix = false
        match to.get("config") {
          Some(cj) => {
            let co = match cj.j_obj() {
              Some(x) => x
              None =>
                raise DecodeSkip(
                  "definitions.types[" + name + "].config is not an object",
                )
            }
            allowed_keys(
              co,
              ["int_round", "number_allow_base_prefix"],
              "int_parser config",
            )
            match co.get("int_round") {
              Some(vj) =>
                match vj.j_str() {
                  Some(s) =>
                    match @builtins.round_mode_of(s) {
                      Some(m) => mode = m
                      None =>
                        raise DecodeSkip(
                          "definitions.types[" +
                          name +
                          "].config.int_round '" +
                          s +
                          "' is not a canonical @engine.RoundMode",
                        )
                    }
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.int_round is not a string",
                    )
                }
              None => ()
            }
            match co.get("number_allow_base_prefix") {
              Some(vj) =>
                match vj.j_bool() {
                  Some(b) => base_prefix = b
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.number_allow_base_prefix is not a bool",
                    )
                }
              None => ()
            }
          }
          None => ()
        }
        out.set(name, {
          base: @builtins.int_type(),
          int_round: mode,
          allow_base_prefix: base_prefix,
          bool_config: @builtins.bool_config_canonical(),
          is_tty: false,
          tty_stream: None,
          tty_cygwin: true,
        })
      }
      "number_parser" | "builtin/number_parser" => {
        // DR-074 §2 `number_allow_base_prefix` = 統合 opt-in で 0x/0o/0b + hex float 一括有効化
        // (単一 flag、canonical default false)。他 config キー (`number_thousand_sep` /
        // `number_leading_zero`) は本 substrate 未サポート (fixture が使わないため)。
        let mut base_prefix = false
        match to.get("config") {
          Some(cj) => {
            let co = match cj.j_obj() {
              Some(x) => x
              None =>
                raise DecodeSkip(
                  "definitions.types[" + name + "].config is not an object",
                )
            }
            allowed_keys(
              co,
              ["number_allow_base_prefix"],
              "number_parser config",
            )
            match co.get("number_allow_base_prefix") {
              Some(vj) =>
                match vj.j_bool() {
                  Some(b) => base_prefix = b
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.number_allow_base_prefix is not a bool",
                    )
                }
              None => ()
            }
          }
          None => ()
        }
        out.set(name, {
          base: @builtins.number_type(),
          int_round: @engine.RError,
          allow_base_prefix: base_prefix,
          bool_config: @builtins.bool_config_canonical(),
          is_tty: false,
          tty_stream: None,
          tty_cygwin: true,
        })
      }
      "bool_parser" | "builtin/bool_parser" => {
        // DR-074 §3/§4 bool_parser factory config: `bool_true_values`/`bool_false_values`/`bool_case_insensitive` (DR-100)
        // の 3 平坦 config キー。canonical default は既存 parse_bool と同値
        // (@builtins.bool_config_canonical())、未指定キーはそれぞれの default を個別に維持する (3 キー独立
        // override — 1 キーだけ opt-in しても他の 2 キーは canonical のまま、DR-061 §4 の平坦
        // config キー原則と同じ「キー単位で独立」の扱い、int_parser/number_parser と同型)。
        let canon = @builtins.bool_config_canonical()
        let mut true_values = canon.true_values
        let mut false_values = canon.false_values
        let mut case_insensitive = canon.case_insensitive
        match to.get("config") {
          Some(cj) => {
            let co = match cj.j_obj() {
              Some(x) => x
              None =>
                raise DecodeSkip(
                  "definitions.types[" + name + "].config is not an object",
                )
            }
            allowed_keys(
              co,
              ["bool_true_values", "bool_false_values", "bool_case_insensitive"],
              "bool_parser config",
            )
            match co.get("bool_true_values") {
              Some(vj) =>
                true_values = dec_str_array(vj, name, "bool_true_values")
              None => ()
            }
            match co.get("bool_false_values") {
              Some(vj) =>
                false_values = dec_str_array(vj, name, "bool_false_values")
              None => ()
            }
            match co.get("bool_case_insensitive") {
              Some(vj) =>
                match vj.j_bool() {
                  Some(b) => case_insensitive = b
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.case_insensitive is not a bool",
                    )
                }
              None => ()
            }
          }
          None => ()
        }
        out.set(name, {
          base: @builtins.bool_type(),
          int_round: @engine.RError,
          allow_base_prefix: false,
          bool_config: { true_values, false_values, case_insensitive },
          is_tty: false,
          tty_stream: None,
          tty_cygwin: true,
        })
      }
      "tty" | "builtin/tty" => {
        // DR-099 §3: `tty_stream` は必須 (未指定は definition-error kind=invalid-range —
        // `collect_tty_stream_missing`, installer.mbt が別途検査する。decode 自体は DecodeSkip に
        // せず None のまま素通しする、definition-error という別チャンネルで表現する規約は
        // int_parser 等の decode-time DecodeSkip とは異なる、DR-098 の同型検査の踏襲)。
        // `tty_cygwin` は既定 true。
        let mut stream : String? = None
        let mut cygwin = true
        match to.get("config") {
          Some(cj) => {
            let co = match cj.j_obj() {
              Some(x) => x
              None =>
                raise DecodeSkip(
                  "definitions.types[" + name + "].config is not an object",
                )
            }
            allowed_keys(co, ["tty_stream", "tty_cygwin"], "tty config")
            match co.get("tty_stream") {
              Some(vj) =>
                match vj.j_str() {
                  Some("stdin") => stream = Some("stdin")
                  Some("stdout") => stream = Some("stdout")
                  Some("stderr") => stream = Some("stderr")
                  Some(other) =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.tty_stream '" +
                      other +
                      "' is not stdin/stdout/stderr",
                    )
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.tty_stream is not a string",
                    )
                }
              None => ()
            }
            match co.get("tty_cygwin") {
              Some(vj) =>
                match vj.j_bool() {
                  Some(b) => cygwin = b
                  None =>
                    raise DecodeSkip(
                      "definitions.types[" +
                      name +
                      "].config.tty_cygwin is not a bool",
                    )
                }
              None => ()
            }
          }
          None => ()
        }
        out.set(name, {
          base: @builtins.bool_type(),
          int_round: @engine.RError,
          allow_base_prefix: false,
          bool_config: @builtins.bool_config_canonical(),
          is_tty: true,
          tty_stream: stream,
          tty_cygwin: cygwin,
        })
      }
      other =>
        raise DecodeSkip(
          "definitions.types[" +
          name +
          "] unsupported factory '" +
          other +
          "' (only int_parser / number_parser / bool_parser / tty are wired in the current substrate)",
        )
    }
  }
  out
}

///|
/// DR-078 §1 `definitions.templates`: name → shared consumption-grammar `@engine.Node`, decoded straight
/// into the `registry` a `ref` element's head resolves against (`@engine.ElemDef.ref_target`/`@builtins.elem_head`,
/// installer.mbt — this decode is the ONLY missing piece, the runtime side was already complete).
/// Mutates `registry` in place (same map `dec_fixture` later threads into `parse_definition`) rather
/// than returning a fresh map — `registry` also receives `parse_definition`'s OWN repeat-recursion
/// entries later (`init_sb`), so it has to be the single shared mutable instance throughout, not a
/// value merged in afterward.
fn dec_templates(
  j : Json,
  shadows : Map[String, TypeShadow],
  template_registry : Map[String, @engine.Node],
  extensions : @engine.Registry,
) -> Unit raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("definitions.templates is not an object")
  }
  for name, tj in o {
    check_reserved_name(name, "definitions.templates")
    template_registry.set(name, dec_template_body(tj, shadows, extensions))
  }
}

///|
/// One `definitions.templates` entry's body (DR-078 §1 "値は要素定義と同じ構造記法 (or / seq /
/// 裸文字列等、LOWERING §A 群の糖衣がそのまま効く)"). Three shapes, mirroring `dec_or_structural`'s
/// own branch-shape handling (§1's example is literally an `or` of a `seq` branch + a bare-leaf
/// branch — this reuses that SAME decoder + `@builtins.or_branch_node`, installer.mbt, rather than
/// duplicating the or/seq/leaf grammar a second time):
///   `{"or": [...]}`   — structural or (DR-055 value-enum `or` form is rejected: a template's
///                       job is a shared CONSUMPTION grammar, not a constraint-declaration sugar)
///   `{"seq": [...]}`  — a bare sequence of leaf cells (no outer `or`)
///   `{"type":..,"name":..}` — a single bare leaf cell (no `seq` wrapper, DR-078 §1 "裸文字列等")
fn dec_template_body(
  j : Json,
  shadows : Map[String, TypeShadow],
  extensions : @engine.Registry,
) -> @engine.Node raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("definitions.templates entry is not an object")
  }
  match o.get("or") {
    Some(orj) => {
      allowed_keys(o, ["or"], "template body (or)")
      match dec_or_structural(orj, shadows, extensions) {
        Some(branches) => {
          let nodes : Array[@engine.Node] = []
          for br in branches {
            nodes.push(@builtins.or_branch_node(br))
          }
          @engine.Or(nodes)
        }
        None =>
          raise DecodeSkip(
            "definitions.templates 'or' has no structural branches (DR-055 value-enum form is option-only, not a shared consumption template)",
          )
      }
    }
    None =>
      match o.get("seq") {
        Some(sj) => {
          allowed_keys(o, ["seq"], "template body (seq)")
          let sa = match sj.j_arr() {
            Some(x) => x
            None => raise DecodeSkip("template body 'seq' is not an array")
          }
          let nodes : Array[@engine.Node] = []
          for e in sa {
            nodes.push(
              @builtins.elem_head(dec_or_leaf(e, shadows, extensions~)),
            )
          }
          @engine.Seq(nodes)
        }
        None => @builtins.elem_head(dec_or_leaf(j, shadows, extensions~)) // bare leaf {"type":..,"name":..}
      }
  }
}

///|
fn dec_export(j : Json) -> @engine.ExportKey {
  match j.j_str() {
    Some("") => @engine.export_key_null()
    Some(s) => @engine.export_key(s)
    None => @engine.export_key_null()
  }
}

///|
/// DR-055 value-enum 形式の or 枝を decode し、(1) enum 消費構造用の全 exact 値 (requires の有無を
/// 問わない — issue values-decode-support, BEnum の `dec_option` 呼び出しが使う) と (2) 制約用の
/// value_requires (requires を持つ枝だけ) の両方を1パスで返す。従来は (2) だけを返していたが、今回
/// values/or の消費意味論を合流させるにあたり同じ走査で (1) も一緒に収集するよう拡張した (二重
/// 実装を避ける)。
fn dec_or(
  j : Json,
  parent_name : String,
) -> (Array[String], Array[(String, String, Array[String])]) raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("or is not an array")
  }
  // MDR-004 §2: the capability gate that used to reject "seq"/"type" branches here is GONE — the
  // caller (`dec_option`) now shape-detects BEFORE calling `dec_or`, routing structural branches to
  // `dec_or_structural` instead. This function only ever sees the value-enum form now.
  // DR-055 §1 + DR-052 §値枝 id 直交: 各枝の tuple = (branch_id, exact_value, targets)。branch_id は
  // `id` フィールド (fixture の `id: "fmt_json"`) を採用、未指定なら parent_name にフォールバック
  // (parent 直属 value_requires と等価挙動)。
  let exacts : Array[String] = []
  let vrs : Array[(String, String, Array[String])] = []
  for e in a {
    let bo = match e.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("or branch is not an object")
    }
    allowed_keys(bo, ["exact", "id", "requires"], "or branch")
    let exact = match jf_str(bo, "exact") {
      Some(s) => s
      None =>
        raise DecodeSkip(
          "or branch missing 'exact' (only exact value枝 supported)",
        )
    }
    exacts.push(exact)
    let reqs = dec_strs(bo.get("requires"))
    if reqs.length() > 0 {
      let branch_id = jf_str(bo, "id").unwrap_or(parent_name)
      check_reserved_name(branch_id, "or branch")
      vrs.push((branch_id, exact, reqs))
    }
  }
  (exacts, vrs)
}

///|
/// MDR-004 kawaz 裁定 2026-07-08: auto `@engine.OrBranch.id` numbering for structural branches without an
/// explicit `"id"`. "採番 seq は decode 1 回のパーサ全体で単調増加... 一意なら何でもよい" — a single
/// monotonic counter for the whole decode run satisfies this; the `#` prefix keeps it out of user
/// namespace (fixture ids are plain strings like `"fmt_json"`, never `#`-prefixed).
let or_branch_seq : Array[Int] = [0]

///|
fn next_or_branch_id() -> String {
  let n = or_branch_seq[0]
  or_branch_seq[0] = n + 1
  "#" + n.to_string()
}

///|
/// DESIGN §5.3 `values` shorthand: a flat array of exact-match string literals (`["red","green",
/// "blue"]`). The seq-branch form (`"values": [..., [{"name":"r",...},...]]`, DESIGN §5.3 後半) is
/// OUT OF SCOPE for this issue (no target fixture exercises it) — a non-string element raises
/// DecodeSkip rather than silently degrading, so a future seq-branch fixture surfaces as a decode
/// gap instead of a wrong parse.
fn dec_values(j : Json) -> Array[String] raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("values is not an array")
  }
  let out : Array[String] = []
  for e in a {
    match e.j_str() {
      Some(s) => out.push(s)
      None =>
        raise DecodeSkip(
          "values element is not a string (seq-branch values form not supported)",
        )
    }
  }
  out
}

///|
/// Strict `Array[String]` decode for a factory config key that DR-061 §4 declares as `{"type":
/// "array", "items": "string"}` (e.g. `bool_parser`'s `true_values`/`false_values`, DR-074 §4) —
/// unlike `dec_strs`, no bare-string sugar (config schema says array, not `string | string[]`).
/// `type_name`/`field` are only for the DecodeSkip message.
fn dec_str_array(
  j : Json,
  type_name : String,
  field : String,
) -> Array[String] raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None =>
      raise DecodeSkip(
        "definitions.types[" +
        type_name +
        "].config." +
        field +
        " is not an array",
      )
  }
  let out : Array[String] = []
  for e in a {
    match e.j_str() {
      Some(s) => out.push(s)
      None =>
        raise DecodeSkip(
          "definitions.types[" +
          type_name +
          "].config." +
          field +
          " element is not a string",
        )
    }
  }
  out
}

///|
/// MDR-004 §2: shape-detect a JSON `"or"` array — `None` if it's the DR-055 value-enum form (every
/// branch has `"exact"`, handled by `dec_or` instead), `Some(branches)` if it's the STRUCTURAL
/// consumption-grammar form (any branch has `"seq"`/`"type"` — a multi-cell `{"seq":[...]}` branch
/// or a single-cell `{"type":..,"name":..}` branch, used verbatim as the branch object itself).
fn dec_or_structural(
  j : Json,
  shadows : Map[String, TypeShadow],
  extensions : @engine.Registry,
) -> Array[@engine.OrBranch]? raise DecodeSkip {
  let a = match j.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("or is not an array")
  }
  let mut structural = false
  for e in a {
    match e.j_obj() {
      Some(bo) =>
        if has_key(bo, "seq") || has_key(bo, "type") {
          structural = true
        }
      None => ()
    }
  }
  if !structural {
    return None
  }
  let branches : Array[@engine.OrBranch] = []
  for e in a {
    let bo = match e.j_obj() {
      Some(x) => x
      None => raise DecodeSkip("or branch is not an object")
    }
    let id = match jf_str(bo, "id") {
      Some(s) => {
        check_reserved_name(s, "or branch")
        s
      }
      None => next_or_branch_id()
    }
    let items : Array[@engine.ElemDef] = match bo.get("seq") {
      Some(sj) => {
        let sa = match sj.j_arr() {
          Some(x) => x
          None => raise DecodeSkip("or branch 'seq' is not an array")
        }
        let its : Array[@engine.ElemDef] = []
        for ij in sa {
          its.push(dec_or_leaf(ij, shadows, extensions~))
        }
        its
      }
      // a single-cell branch IS the leaf object itself (no "seq" wrapper, DESIGN §1.2 裸配列 seq 糖衣
      // — wire form already normalizes bare-seq sugar, so here a missing "seq" key on a branch that
      // has "type"/"name" directly is exactly the 1-item case).
      None => [dec_or_leaf(e, shadows, extensions~)]
    }
    branches.push({ id, items })
  }
  Some(branches)
}

///|
/// A leaf cell inside a structural `"or"` branch: `{"type":..,"name":..}`. Minimal — BCell only, no
/// long/short/env/etc (the shared trigger, if any, lives on the PARENT option's `long`, factored out
/// per the `variable-arity-ambiguous.json` wire form; an anonymous positional or-branch leaf has no
/// trigger at all).
fn dec_or_leaf(
  j : Json,
  shadows : Map[String, TypeShadow],
  extensions? : @engine.Registry = canonical_registry(),
) -> @engine.ElemDef raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("or branch leaf is not an object")
  }
  allowed_keys(o, ["type", "name"], "or branch leaf")
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("or branch leaf missing 'name'")
  }
  check_reserved_name(name, "or branch leaf")
  // DR-089 §2: type 省略 = none の糖衣 (or branch leaf も他の要素種と同じ規約)。
  // issue typeshadow-carry-gap-or-leaf-positional-group: TypeShadow の全フィールドを carry する
  // (dec_positional と同じ一般化パターン — base/int_round だけに絞る理由は無い、DESIGN §13.3
  // 「全区分一様」に or 枝の葉も従う)。
  let (
    ty,
    int_round_from_shadow,
    base_prefix_from_shadow,
    bool_config_from_shadow,
    is_tty_from_shadow,
    tty_stream_from_shadow,
    tty_cygwin_from_shadow,
  ) = match jf_str(o, "type") {
    Some(t) =>
      match shadows.get(t) {
        Some(sh) =>
          (
            sh.base,
            sh.int_round,
            sh.allow_base_prefix,
            sh.bool_config,
            sh.is_tty,
            sh.tty_stream,
            sh.tty_cygwin,
          )
        None =>
          (
            dec_ty(t, name, extensions),
            @engine.RError,
            false,
            @builtins.bool_config_canonical(),
            false,
            None,
            true,
          )
      }
    None =>
      (
        @builtins.none_type(),
        @engine.RError,
        false,
        @builtins.bool_config_canonical(),
        false,
        None,
        true,
      )
  }
  let ty = @builtins.configured_type(
    ty, int_round_from_shadow, base_prefix_from_shadow, bool_config_from_shadow,
  )
  pos(
    name,
    ty,
    int_round=int_round_from_shadow,
    allow_base_prefix=base_prefix_from_shadow,
    bool_config=bool_config_from_shadow,
    is_tty=is_tty_from_shadow,
    tty_stream=tty_stream_from_shadow,
    tty_cygwin=tty_cygwin_from_shadow,
  )
}

///|
fn is_help_group_declaration(o : Map[String, Json]) -> Bool {
  has_key(o, "help_group_name") &&
  !has_key(o, "name") &&
  !has_key(o, "id") &&
  !has_key(o, "type") &&
  !has_key(o, "long") &&
  !has_key(o, "short") &&
  !has_key(o, "env") &&
  !has_key(o, "alias") &&
  !has_key(o, "ref") &&
  !has_key(o, "or") &&
  !has_key(o, "values")
}

///|
fn dec_option(
  j : Json,
  shadows : Map[String, TypeShadow],
  extensions? : @engine.Registry = canonical_registry(),
) -> DElem raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("option is not an object")
  }
  let owned = decode_installer_owned(j, DecodeOption, extensions)
  match owned.alias_decl {
    Some(value) => {
      let allowed = ["alias", "name", "short", "long", "deprecated", "type"]
      for key in owned.vocab {
        allowed.push(key)
      }
      allowed_keys(o, allowed, "alias")
      return DAlias({ ..value, help_meta: owned.help_meta })
    }
    None => ()
  }
  if is_help_group_declaration(o) {
    allowed_keys(o, owned.vocab, "help group declaration")
    return DOpt(opt("", @builtins.none_type(), help_meta=owned.help_meta))
  }
  let allowed = [
    "id", "name", "type", "default", "default_fn", "export_key", "deprecated", "hidden",
    "or", "values", "piece_filters", "value_filters", "final_filters", "accum_filters",
    "ref", "completer", "config",
  ]
  for key in owned.vocab {
    allowed.push(key)
  }
  allowed_keys(o, allowed, "option")
  let tystr = match jf_str(o, "type") {
    Some(t) => t
    None =>
      if has_key(o, "or") || has_key(o, "ref") || has_key(o, "values") {
        // DR-078 §1: a `ref` element's own consumption is replaced by the referenced template
        // (`@builtins.elem_head`'s `Ref(r)` head, ty unused there) — same "type is moot" reasoning `or`
        // already gets. `values` gets the same default (DR-028 追記: values を持つ node は type
        // フィールドなしで enum 型を兼ねる) — DESIGN §5.3's `values` shorthand is string-literal-
        // only in this issue's scope (seq-branch values form not implemented), so the enum's own
        // values are always strings regardless of this default.
        "string"
      } else {
        // DR-089 §2: type 省略 = none の糖衣 (or/ref/values いずれも無い場合)。旧実装は
        // ここを DecodeSkip (type 必須) にしていたが、DR-089 で「無いものに勝手に値型をあてるのは
        // 手抜き」(kawaz) として default-typing 案が明示的に不採用になったのと対称に、旧
        // DecodeSkip も「無いものをエラー扱いする」誤りだった — 値空間が無いこと自体は正当な宣言。
        "none"
      }
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("option missing 'name'")
  }
  check_reserved_name(name, "option")
  // MDR-004 §2: "or" is shape-detected FIRST — the DR-055 value-enum form ({"exact":...} branches,
  // dec_or, parent name = branch-id フォールバック先) and the structural consumption-grammar form
  // (BOr, dec_or_structural) share the same JSON key but are otherwise unrelated (§5.3 values 正規形
  // vs §1 消費文法の枝)。
  let structural_or = match o.get("or") {
    Some(orj) => dec_or_structural(orj, shadows, extensions)
    None => None
  }
  // issue values-decode-support (DESIGN §5.3 "values は or のショートハンド" + team-lead 裁定
  // 2026-07-10「values と or (value-enum形式) の消費意味論を分岐させない」): `values` はここで
  // `or` value-enum 相当 (全 exact 値のリスト) へ正規化し、以降 `value_enum`/`value_requires` の
  // 決定を「values 由来」と「or 由来」で完全に同じ経路に流す — 糖衣と正規形で観測挙動が割れない
  // ようにする。`values` と `or` の同時指定は対象 fixture に無く未定義 (values を優先、無視した
  // `or` があれば下の `value_requires` 判定には現れない — 想定外の組合せなので検出はしない)。
  let (value_enum, value_requires) : (
    Array[String]?,
    Array[(String, String, Array[String])],
  ) = match structural_or {
    Some(_) => (None, [])
    None =>
      match o.get("values") {
        Some(vj) => (Some(dec_values(vj)), [])
        None =>
          match o.get("or") {
            Some(orj) => {
              let (exacts, vrs) = dec_or(orj, name)
              (Some(exacts), vrs)
            }
            None => (None, [])
          }
      }
  }
  if tystr == "dd" && conformance_str_in(owned.vocab, "match") {
    return DOpt({
      ..dd_marker(
        match_=owned.dd_match,
        self_keep=owned.dd_self_keep,
        required=owned.required,
      ),
      name,
    })
  }
  // DR-061 §3: type shadow lookup — user 定義の type 名なら base type resident + parse 相 config を採用、
  // canonical 型名 (string/int/...) にフォールバック。help/config_file は語彙 keyword で shadow の
  // 適用対象外 (installer 語彙、DR-042)。
  // DR-099 §1/§3: bare `type:"tty"` (builtin ns の糖衣, DR-094 §3) / 明示 `type:"builtin/tty"` も
  // help/config_file と同じ keyword 優先度で先に判定する — definitions.types を経由しない直接参照は
  // config (tty_stream) を一切供給できないので、tty_stream は常に None のまま
  // (`collect_tty_stream_missing` の definition-error に委ねる)。
  let (
    ty,
    fail_action,
    config_file,
    int_round_from_shadow,
    base_prefix_from_shadow,
    bool_config_from_shadow,
    is_tty_from_shadow,
    tty_stream_from_shadow,
    tty_cygwin_from_shadow,
  ) = match tystr {
    "help" =>
      (
        @builtins.flag_type(),
        true,
        false,
        @engine.RError,
        false,
        @builtins.bool_config_canonical(),
        false,
        None,
        true,
      )
    "config_file" =>
      if owned.config_file {
        (
          @builtins.string_type(),
          false,
          true,
          @engine.RError,
          false,
          @builtins.bool_config_canonical(),
          false,
          None,
          true,
        )
      } else {
        (
          dec_ty(tystr, name, extensions),
          false,
          false,
          @engine.RError,
          false,
          @builtins.bool_config_canonical(),
          false,
          None,
          true,
        )
      }
    "tty" | "builtin/tty" =>
      (
        @builtins.bool_type(),
        false,
        false,
        @engine.RError,
        false,
        @builtins.bool_config_canonical(),
        true,
        None,
        true,
      )
    _ =>
      match shadows.get(tystr) {
        Some(sh) =>
          (
            sh.base,
            false,
            false,
            sh.int_round,
            sh.allow_base_prefix,
            sh.bool_config,
            sh.is_tty,
            sh.tty_stream,
            sh.tty_cygwin,
          )
        None =>
          (
            dec_ty(tystr, name, extensions),
            false,
            false,
            @engine.RError,
            false,
            @builtins.bool_config_canonical(),
            false,
            None,
            true,
          )
      }
  }
  let ty = @builtins.configured_type(
    ty, int_round_from_shadow, base_prefix_from_shadow, bool_config_from_shadow,
  )
  // DR-071 §1 / kawaz 裁定 2026-07-08: decode は wire の bool|array 二形をそのまま `@engine.LongDecl` に写す
  // だけ — 糖衣展開・colon DSL 分類 (variants の分離を含む) は installer.mbt の `resolve_long` が
  // `normalize_option` から担う (下記 `opt(...)` は `variants` を渡さない = 常に [] のまま宣言層へ)。
  let long_decl = owned.long
  let short = owned.short
  let env = owned.env
  let default : Array[@engine.Value]? = match o.get("default") {
    Some(d) => Some(json_to_default_values(d))
    None => None
  }
  let default_fn : @engine.DefaultFnCall? = match o.get("default_fn") {
    Some(invocation) => Some(dec_default_fn(invocation))
    None => None
  }
  let global = owned.global_
  let inherit_flag = owned.inherit_
  let inheritable = owned.inheritable
  let multiple = owned.multiple
  let sep = owned.separator
  let coll = owned.collector
  let acc = owned.accumulator
  let flat = owned.flatten
  let requires = owned.requires
  let conflicts = owned.conflicts
  let exclusive = owned.exclusive
  let required_group = owned.required_group
  let required = owned.required
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => @engine.export_key_unset()
  }
  let config_key = owned.config_key
  let deprecated = bool_field(o, "deprecated", false)
  let hidden = bool_field(o, "hidden", false)
  // DR-060 §4 / DR-104 §2(d): `completer` names a `completers` registry entry — decode reads the
  // name verbatim, no lookup/validation against the registry happens here (same posture as
  // `accumulator`'s registry-name carry: unknown-vocab detection, if any, is parse_definition's job).
  let completer = jf_str(o, "completer")
  let piece_filters = dec_filter_chain(o.get("piece_filters"))
  let value_filters = dec_filter_chain(o.get("value_filters"))
  let final_filters = dec_filter_chain(o.get("final_filters"))
  let accum_filters = dec_filter_chain(o.get("accum_filters"))
  // DR-091 §3 (team-lead 裁定 2026-07-11 修正) / DR-096: `long_prefix`/`long_eq_sep` are NOT
  // element-level wire keys — the canonical source is `dec_definition`'s scope-level read (DESIGN
  // §7.2's sibling, "scope config" per DR-091 §3), which overrides every `@engine.ElemDef` this function
  // returns AFTER decode. An option JSON object carrying either key hits the `allowed_keys` reject
  // above (element-level override would be an un-specced vocabulary invention — the DEDICATED
  // per-element `config` object, a DIFFERENT key, IS the sanctioned override channel, DR-049 §4).
  // `opt(...)` below omits both — they keep `opt`'s defaults (`"--"`/`@engine.EsAllow`) here and get set for
  // real by the caller (`dec_definition`).
  let ref_ = jf_str(o, "ref")
  let repeat = owned.repeat
  DOpt({
    ..opt(
      name,
      ty,
      long=long_decl,
      short~,
      repeat~,
      env~,
      help_meta=owned.help_meta,
      is_tty=is_tty_from_shadow,
      tty_stream=tty_stream_from_shadow,
      tty_cygwin=tty_cygwin_from_shadow,
      global~,
      inherit_=inherit_flag,
      inheritable~,
      multiple~,
      accumulator=acc,
      flatten=flat,
      fail_action~,
      config_file~,
      config_key~,
      export_~,
      requires~,
      conflicts~,
      exclusive~,
      required_group~,
      required~,
      value_requires~,
      default~,
      default_fn~,
      default_declared=has_key(o, "default"),
      int_round=int_round_from_shadow,
      allow_base_prefix=base_prefix_from_shadow,
      bool_config=bool_config_from_shadow,
      piece_filters~,
      value_filters~,
      final_filters~,
      accum_filters~,
      ref_~,
      hidden~,
      completer~,
      body=match structural_or {
        Some(branches) => BOr(branches)
        None =>
          match value_enum {
            Some(values) => BEnum(values)
            None => BCell
          }
      },
    ),
    separator: sep,
    collector: coll,
    deprecated,
  })
}

///|
fn dec_positional(
  j : Json,
  shadows : Map[String, TypeShadow],
  extensions? : @engine.Registry = canonical_registry(),
) -> @engine.ElemDef raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("positional is not an object")
  }
  let owned = decode_installer_owned(j, DecodePositional, extensions)
  let allowed = [
    "id", "name", "type", "export_key", "default", "default_fn", "positionals", "or",
    "piece_filters", "value_filters", "final_filters", "accum_filters", "ref", "config",
    "completer", "exact",
  ]
  for key in owned.vocab {
    allowed.push(key)
  }
  allowed_keys(o, allowed, "positional")
  // MDR-004 §2: "positionals" (named nested group, BGroup) and "or" (anonymous structural or,
  // BOr) are decoded via @engine.ElemBody now — the gates that used to reject these keys are GONE. A
  // positional's "or" is ALWAYS structural (there is no DR-055 value-enum-or concept for
  // positionals — that's an option-only constraint-declaration sugar, §5.3).
  match o.get("positionals") {
    Some(pj) =>
      return dec_positional_group(o, pj, shadows, extensions, owned.repeat)
    None => ()
  }
  // issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め (DR-063 A.1 / DR-018 配置
  // で役割決定): shape-detect a bare `{"exact": "..."}` leaf BEFORE the "or"/type/name value-cell
  // dispatch below, same early-return style as "positionals" above. wire.schema.json's node $defs
  // forbid `exact`+`or` / `exact`+`seq` co-occurrence; this decoder goes further and requires
  // `exact` to be the ONLY key present (`only_key`, codex レビュー Major 3) — `repeat`/`optional`/
  // `multiple`/`default`/`piece_filters`/etc. co-occurring with `exact` has no target fixture and
  // no defined meaning here, so any of them DecodeSkips rather than being silently swallowed
  // (deliberately absent, not deliberately wrong — same posture as this function's `BEnum` note
  // below; the OLD 4-key deny-list here let `{"exact":"init","repeat":{...}}` decode successfully
  // with `repeat` thrown away — `only_key` closes that class of gap for every current AND future
  // `allowed_keys` entry, not just the 4 that were enumerated). Only the bare-string spelling form
  // is wired (DR-063 §3's bool/number literal-origin `exact` forms are OUT OF SCOPE — no target
  // fixture exercises them).
  match o.get("exact") {
    Some(ej) =>
      if !only_key(o, "exact") {
        raise DecodeSkip(
          "positional 'exact' combined with any other key is not supported (bare exact-literal leaf only, DR-063 A.1)",
        )
      } else {
        match ej.j_str() {
          Some(spelling) => return exact_marker(spelling)
          None =>
            raise DecodeSkip(
              "positional 'exact' is not a string (bool/number literal-origin exact forms not supported)",
            )
        }
      }
    None => ()
  }
  match o.get("or") {
    Some(orj) =>
      match dec_or_structural(orj, shadows, extensions) {
        Some(branches) =>
          return { ..pos("", @builtins.string_type()), body: BOr(branches) }
        None =>
          raise DecodeSkip(
            "positional 'or' has no structural branches (all-exact value-enum form is option-only, DR-055 §1 / §5.3)",
          )
      }
    None => ()
  }
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("positional missing 'name'")
  }
  check_reserved_name(name, "positional")
  // DR-061 §3: positional も type shadow を consultation (dec_option と同型)。
  // DR-089 §2: type 省略 = none の糖衣 (旧実装は @builtins.string_type() を勝手にあてる default-typing だった —
  // DR-089 の「採用しなかった案」が明示的に否定するパターン。`ref` 付きの場合はそもそも ty が
  // 未使用 (@builtins.elem_head の Ref(r) head、下の `dec_or_structural`/`positionals` 分岐同様) なので
  // @builtins.none_type() に変えても無害)。
  // DR-099 §1/§3: bare `type:"tty"` / `type:"builtin/tty"` は dec_option と同じ理由で shadow
  // lookup より先に判定する (config を供給する経路が無いので tty_stream は常に None のまま)。
  let (
    ty,
    int_round_from_shadow,
    base_prefix_from_shadow,
    bool_config_from_shadow,
    is_tty_from_shadow,
    tty_stream_from_shadow,
    tty_cygwin_from_shadow,
  ) = match jf_str(o, "type") {
    Some("tty") | Some("builtin/tty") =>
      (
        @builtins.bool_type(),
        @engine.RError,
        false,
        @builtins.bool_config_canonical(),
        true,
        None,
        true,
      )
    Some(t) =>
      match shadows.get(t) {
        Some(sh) =>
          (
            sh.base,
            sh.int_round,
            sh.allow_base_prefix,
            sh.bool_config,
            sh.is_tty,
            sh.tty_stream,
            sh.tty_cygwin,
          )
        None =>
          (
            dec_ty(t, name, extensions),
            @engine.RError,
            false,
            @builtins.bool_config_canonical(),
            false,
            None,
            true,
          )
      }
    None =>
      (
        @builtins.none_type(),
        @engine.RError,
        false,
        @builtins.bool_config_canonical(),
        false,
        None,
        true,
      )
  }
  let ty = @builtins.configured_type(
    ty, int_round_from_shadow, base_prefix_from_shadow, bool_config_from_shadow,
  )
  let repeat = owned.repeat
  let optional = owned.optional
  let multiple = owned.multiple
  let sep = owned.separator
  let coll = owned.collector
  let acc = owned.accumulator
  let flat = owned.flatten
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => @engine.export_key_unset()
  }
  let config_key = owned.config_key
  let default : Array[@engine.Value]? = match o.get("default") {
    Some(d) => Some(json_to_default_values(d))
    None => None
  }
  let default_fn : @engine.DefaultFnCall? = match o.get("default_fn") {
    Some(invocation) => Some(dec_default_fn(invocation))
    None => None
  }
  let piece_filters = dec_filter_chain(o.get("piece_filters"))
  let value_filters = dec_filter_chain(o.get("value_filters"))
  let final_filters = dec_filter_chain(o.get("final_filters"))
  let accum_filters = dec_filter_chain(o.get("accum_filters"))
  let ref_ = jf_str(o, "ref")
  // DR-088 (issue dr-088-positional-default-verification): positionals can declare `env` too
  // (@engine.Entity.env_key applies uniformly across options/positionals, `dec_option`'s same-named
  // field) — this was missing from the positional decoder entirely (`allowed_keys` rejected it
  // outright), a genuine decode gap surfaced by `positional-env-presence.json`.
  let env = owned.env
  let required = owned.required
  let requires = owned.requires
  // DR-012 / DR-055 / DR-103: constraint 系は要素属性で positional にも同型に付与できる
  // (`decode_installer_owned` が constraint installer 経由で 5 属性 = requires/conflicts/exclusive/
  // required_group/required を positional context でも集約する — installer_residents.mbt の
  // `ConstraintInstaller.decode` の DecodePositional 分岐参照)。engine 検査 (CConflicts / CExclusive /
  // CRequired / CRequiredGroup) は entity 名の committed 判定のみを行い option/positional を区別
  // しないので、decode 側で pos() に流し込むだけで動く (opt() の同名 owned 経路と対称)。
  let conflicts = owned.conflicts
  let exclusive = owned.exclusive
  let required_group = owned.required_group
  // DR-060 §4 / DR-104 §2(d): dec_option 側と対称の decode — completer 名の verbatim carry。
  let completer = jf_str(o, "completer")
  pos(
    name,
    ty,
    inherit_=owned.inherit_,
    repeat~,
    optional~,
    multiple~,
    accumulator=acc,
    flatten=flat,
    separator=sep,
    collector=coll,
    config_key~,
    export_~,
    ref_~,
    default~,
    default_fn~,
    default_declared=has_key(o, "default"),
    int_round=int_round_from_shadow,
    allow_base_prefix=base_prefix_from_shadow,
    bool_config=bool_config_from_shadow,
    piece_filters~,
    value_filters~,
    env~,
    help_meta=owned.help_meta,
    is_tty=is_tty_from_shadow,
    tty_stream=tty_stream_from_shadow,
    tty_cygwin=tty_cygwin_from_shadow,
    final_filters~,
    accum_filters~,
    required~,
    requires~,
    conflicts~,
    exclusive~,
    required_group~,
    completer~,
  )
}

///|
/// MDR-004 §1/§3: a named group positional (`{"name":"xs","repeat":{...},"positionals":[...]}`) —
/// `BGroup(items)`. Inner items are decoded via `dec_positional` itself (recursive — an inner leaf
/// like transparent-seq's `k` is just a normal positional decode, `export_key:null` included).
fn dec_positional_group(
  o : Map[String, Json],
  pj : Json,
  shadows : Map[String, TypeShadow],
  extensions : @engine.Registry,
  repeat : @engine.RepeatSpec?,
) -> @engine.ElemDef raise DecodeSkip {
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("positional (named group) missing 'name'")
  }
  check_reserved_name(name, "positional (named group)")
  let inner_arr = match pj.j_arr() {
    Some(x) => x
    None => raise DecodeSkip("positionals is not an array")
  }
  let items : Array[@engine.ElemDef] = []
  for ij in inner_arr {
    items.push(dec_positional(ij, shadows, extensions~))
  }
  { ..pos(name, @builtins.string_type(), repeat~), body: BGroup(items) }
}

///|
/// DR-014 / DESIGN §7.2 (issue scope-config-object-gap): the resolved (post-inheritance) value of
/// every scope `config` key, threaded top-down through `dec_definition`/`dec_command`'s recursion —
/// this IS the "子要素は親の config を継承、上書き可能" hierarchy (DESIGN §7.2), realized as
/// "each scope merges its own `config` object over the value it received from its parent" rather
/// than a stored-on-`@engine.Definition` carrier (installer.mbt never reads a `@engine.Definition`-level config; the
/// resolved tuple gets baked onto each `@engine.ElemDef` the scope owns, same pattern DR-091 §3 established
/// for the original 2-field minimal implementation).
priv struct ScopeConfig {
  long_prefix : String
  long_eq_sep : @engine.EqSepMode
  short_prefix : String
  short_attached_value : @engine.AttachMode
  short_combine : Bool
  env_prefix : String
  auto_env : Bool
}

///|
/// The canonical config, in effect at the root scope when no `config` object is ever written
/// (equivalent to every key's DESIGN §7.2 default, DR-096 §1/§2 の 3 値 enum 既定 `@engine.EsAllow`/`@engine.AtAllow`
/// を含む).
fn default_scope_config() -> ScopeConfig {
  {
    long_prefix: "--",
    long_eq_sep: @engine.EsAllow,
    short_prefix: "-",
    short_attached_value: @engine.AtAllow,
    short_combine: true,
    env_prefix: "",
    auto_env: false,
  }
}

///|
/// Merges THIS scope's own `config` object (JSON, may be partly or fully absent) over `parent`
/// (the already-resolved config the enclosing scope handed down) — a key ABSENT from `co` inherits
/// `parent`'s resolved value; a key PRESENT overrides it. This single merge step, applied once per
/// scope in the top-down recursion, is the entire "階層継承可能" mechanism DR-014 specifies — no
/// separate reconciliation pass is needed because each scope only ever sees its own JSON object and
/// the one already-merged value from above.
fn dec_scope_config(
  co : Map[String, Json],
  parent : ScopeConfig,
) -> ScopeConfig raise DecodeSkip {
  allowed_keys(
    co,
    [
      "long_prefix", "long_eq_sep", "short_prefix", "short_attached_value", "short_combine",
      "env_prefix", "env_auto",
    ],
    "definition.config",
  )
  let long_prefix = match jf_str(co, "long_prefix") {
    Some(s) => s
    None => parent.long_prefix
  }
  // DESIGN §7.2 / DR-096 §1: 3 値 enum decode — `int_round`/`@builtins.round_mode_of` と同じ前例パターン
  // (`value.mbt`'s `@engine.eq_sep_mode_of` doc comment)。不正値 (未知 token) は decode-time DecodeSkip。
  let long_eq_sep = match co.get("long_eq_sep") {
    Some(vj) =>
      match vj.j_str() {
        Some(s) =>
          match @engine.eq_sep_mode_of(s) {
            Some(m) => m
            None =>
              raise DecodeSkip(
                "config.long_eq_sep '" +
                s +
                "' is not a canonical @engine.EqSepMode",
              )
          }
        None => raise DecodeSkip("config.long_eq_sep is not a string")
      }
    None => parent.long_eq_sep
  }
  let short_prefix = match jf_str(co, "short_prefix") {
    Some(s) => s
    None => parent.short_prefix
  }
  let short_attached_value = match co.get("short_attached_value") {
    Some(vj) =>
      match vj.j_str() {
        Some(s) =>
          match @engine.attach_mode_of(s) {
            Some(m) => m
            None =>
              raise DecodeSkip(
                "config.short_attached_value '" +
                s +
                "' is not a canonical @engine.AttachMode",
              )
          }
        None => raise DecodeSkip("config.short_attached_value is not a string")
      }
    None => parent.short_attached_value
  }
  let short_combine = bool_field(co, "short_combine", parent.short_combine)
  let env_prefix = match jf_str(co, "env_prefix") {
    Some(s) => s
    None => parent.env_prefix
  }
  let auto_env = bool_field(co, "env_auto", parent.auto_env)
  {
    long_prefix,
    long_eq_sep,
    short_prefix,
    short_attached_value,
    short_combine,
    env_prefix,
    auto_env,
  }
}

///|
/// "_" 連結 (DR-049 §3 auto_env 名導出の連結セパレータ)。空 segment は呼び出し側が既に除外している
/// 前提 (`auto_env_name` — env_prefix 未設定時に prefix segment 自体を積まない、DR-049 §3
/// 「env_prefix 未設定なら prefix 部を省く」)。
fn join_us(items : Array[String]) -> String {
  let buf = StringBuilder::new()
  let mut first = true
  for s in items {
    if !first {
      buf.write_string("_")
    }
    buf.write_string(s)
    first = false
  }
  buf.to_string()
}

///|
/// DR-049 §3 auto_env 名導出: `UPPER(env_prefix) "_" UPPER(scope_path を "_" 連結) "_" UPPER(name)`。
/// `env_prefix` 未設定 (`""`) なら prefix segment を省く (§3 明記)。`name` は wire format の
/// snake_case (DR-022) なので変換は uppercase のみ (kebab/camel からの変換規則は定義しない、§3)。
fn auto_env_name(
  env_prefix : String,
  scope_path : Array[String],
  name : String,
) -> String {
  let segs : Array[String] = []
  if env_prefix != "" {
    segs.push(env_prefix.to_upper())
  }
  for s in scope_path {
    segs.push(s.to_upper())
  }
  segs.push(name.to_upper())
  join_us(segs)
}

///|
/// DR-049 §3/§4: applies THIS scope's resolved `env_prefix`/`auto_env` to one option/positional
/// element. Two independent effects (§4「明示 env: が auto_env に優先する」means these are mutually
/// exclusive per element, not layered):
/// - explicit `env:` (§4): env_prefix prepends to EVERY declared env key (`UPPER(env_prefix) + "_"
///   + <value>` — the value itself is left as the author wrote it, only the prefix segment is
///   uppercased per §3's "UPPER(env_prefix)"), UNLESS env_prefix is `""` (§3 "未設定なら prefix 部
///   を省く" — the element is left byte-for-byte unchanged, preserving every pre-issue fixture that
///   declares `env:` with no scope config at all).
/// - no explicit `env:` + `auto_env: true` (§3): derives the full name via `auto_env_name` — gated to
///   `BCell` bodies only ("値セル持ち要素", DESIGN §7.2 line 842 — a `BOr`/`BGroup`/`BEnum` wrapper
///   has no single value slot for a scalar env lookup to bind to, matcher/leaf-level auto_env is not
///   specified anywhere and would be an invented extension).
fn apply_env_config(
  e : @engine.ElemDef,
  env_prefix : String,
  auto_env : Bool,
  scope_path : Array[String],
) -> @engine.ElemDef {
  if e.env.length() > 0 {
    if env_prefix == "" {
      e
    } else {
      let prefixed : Array[String] = []
      for v in e.env {
        prefixed.push(env_prefix.to_upper() + "_" + v)
      }
      { ..e, env: prefixed }
    }
  } else if auto_env && e.body is BCell {
    { ..e, env: [auto_env_name(env_prefix, scope_path, e.name)] }
  } else {
    e
  }
}

///|
fn dec_command(
  j : Json,
  shadows : Map[String, TypeShadow],
  extensions : @engine.Registry,
  parent_config : ScopeConfig,
  scope_path : Array[String],
) -> DCmd raise DecodeSkip {
  let o = match j.j_obj() {
    Some(x) => x
    None => raise DecodeSkip("command is not an object")
  }
  let owned = decode_installer_owned(j, DecodeCommand, extensions)
  match owned.alias_decl {
    Some(value) => {
      let allowed = ["alias", "name", "deprecated", "type"]
      for key in owned.vocab {
        allowed.push(key)
      }
      allowed_keys(o, allowed, "command alias")
      return DCmdAlias({ ..value, help_meta: owned.help_meta })
    }
    None => ()
  }
  let allowed = [
    "type", "name", "options", "positionals", "commands", "export_key", "config",
  ]
  for key in owned.vocab {
    allowed.push(key)
  }
  allowed_keys(o, allowed, "command")
  let name = match jf_str(o, "name") {
    Some(s) => s
    None => raise DecodeSkip("command missing 'name'")
  }
  check_reserved_name(name, "command")
  // 子コマンドの definition は親の shadows を継承する (DR-061 は scope 継承を規定していないが、
  // slice実装は fixture が命令的に flat な type shadow を宣言するだけなので親→子への単純伝搬で足りる)
  //
  // DR-014 階層継承 / DR-049 §3 scope_path: この command 自身の name を scope_path に足して子へ
  // 渡す — auto_env のフル修飾名導出 (DR-049 §3「スコープパスはフル修飾」) が使う。
  let body = dec_definition(
    o,
    shadows~,
    extensions~,
    parent_config~,
    scope_path=scope_path + [name],
  )
  let export_ = match o.get("export_key") {
    Some(e) => dec_export(e)
    None => @engine.export_key_unset()
  }
  DCommand({ name, body, export_key: export_ })
}

///|
fn dec_definition(
  o : Map[String, Json],
  shadows? : Map[String, TypeShadow] = Map([]),
  extensions? : @engine.Registry = canonical_registry(),
  parent_config? : ScopeConfig = default_scope_config(),
  scope_path? : Array[String] = [],
) -> @engine.Definition raise DecodeSkip {
  let scope : @engine.ScopeDecl = {
    name: jf_str(o, "name"),
    help_meta: help_meta_from_object(o),
  }
  // DR-014 / DESIGN §7.2 (issue scope-config-object-gap; supersedes DR-091 §3's original 2-field-
  // only, non-inheriting scope config): この呼び出しの `o` (root definition object、または 1つの
  // command の own definition object — `dec_command` が自分の `o` をそのまま渡す) が持つ
  // `config: {long_prefix, long_eq_sep, short_prefix, short_attached_value, short_combine,
  // env_prefix, auto_env}` (DESIGN §7.2 の wire 形そのもの、DR-096 §1/§2 軸別再編後) を
  // `parent_config` (呼び出し元から
  // 継承した既解決値) の上に `dec_scope_config` でマージする — 明示したキーだけ上書き、省略した
  // キーは親の値をそのまま継承する (DESIGN §7.2「子要素は親の config を継承、上書き可能」)。
  // `config` 自体を省略したスコープは `parent_config` をそのまま使う (= 何も上書きしない、継承の
  // 恒等射)。ルートスコープの `parent_config` 既定は `default_scope_config()` (DR-091 §3 の
  // pre-issue 既定と同一値)。
  let config = match o.get("config") {
    Some(cj) => {
      let co = match cj.j_obj() {
        Some(x) => x
        None => raise DecodeSkip("config is not an object")
      }
      dec_scope_config(co, parent_config)
    }
    None => parent_config
  }
  let options : Array[@engine.ElemDef] = []
  let positionals : Array[@engine.ElemDef] = []
  let commands : Array[@engine.CommandDef] = []
  let aliases : Array[@engine.AliasDef] = []
  match o.get("options") {
    Some(arr) => {
      let a = match arr.j_arr() {
        Some(x) => x
        None => raise DecodeSkip("options is not an array")
      }
      for oj in a {
        match dec_option(oj, shadows, extensions~) {
          DOpt(e) => {
            // codex 節目レビュー Major 1 (DR-049 §4「その要素の config で env_prefix:"" を上書きする
            // (DR-014 の階層継承で要素単位の上書きが可能)」/ DESIGN §7.2「子要素は親の config を
            // 継承、上書き可能」の『子要素』は command scope に限らない): `dec_option` は要素の生
            // JSON を `allowed_keys` 済み `Map[String, Json]` として保持しないので、要素単位の
            // `config` はここ (呼び出し元) で `oj` を直接再読して取り出す — `dec_scope_config` を
            // このスコープの `config` を親として要素の `config` に適用すれば、既存の階層マージ
            // ロジックをそのまま要素レベルへ 1 段延長できる (別実装を持たない)。
            let elem_config = match oj.j_obj() {
              Some(oo) =>
                match oo.get("config") {
                  Some(ecj) => {
                    let eco = match ecj.j_obj() {
                      Some(x) => x
                      None => raise DecodeSkip("option config is not an object")
                    }
                    dec_scope_config(eco, config)
                  }
                  None => config
                }
              None => config // 到達不能 (dec_option が既に object であることを検証済み)
            }
            options.push(
              apply_env_config(
                {
                  ..e,
                  long_prefix: elem_config.long_prefix,
                  short_prefix: elem_config.short_prefix,
                  long_eq_sep: elem_config.long_eq_sep,
                  short_combine: elem_config.short_combine,
                  short_attached_value: elem_config.short_attached_value,
                },
                elem_config.env_prefix,
                elem_config.auto_env,
                scope_path,
              ),
            )
          }
          DAlias(al) => aliases.push(al)
        }
      }
    }
    None => ()
  }
  match o.get("positionals") {
    Some(arr) => {
      let a = match arr.j_arr() {
        Some(x) => x
        None => raise DecodeSkip("positionals is not an array")
      }
      for pj in a {
        let e = dec_positional(pj, shadows, extensions~)
        // Major 1 と同じ要素単位 override、positional 版 (DESIGN §7.2「子要素」の対称範囲)。
        let elem_config = match pj.j_obj() {
          Some(po) =>
            match po.get("config") {
              Some(ecj) => {
                let eco = match ecj.j_obj() {
                  Some(x) => x
                  None => raise DecodeSkip("positional config is not an object")
                }
                dec_scope_config(eco, config)
              }
              None => config
            }
          None => config // 到達不能 (dec_positional が既に object であることを検証済み)
        }
        positionals.push(
          apply_env_config(
            {
              ..e,
              long_prefix: elem_config.long_prefix,
              short_prefix: elem_config.short_prefix,
              long_eq_sep: elem_config.long_eq_sep,
              short_combine: elem_config.short_combine,
              short_attached_value: elem_config.short_attached_value,
            },
            elem_config.env_prefix,
            elem_config.auto_env,
            scope_path,
          ),
        )
      }
    }
    None => ()
  }
  match o.get("commands") {
    Some(arr) => {
      let a = match arr.j_arr() {
        Some(x) => x
        None => raise DecodeSkip("commands is not an array")
      }
      for cj in a {
        match dec_command(cj, shadows, extensions, config, scope_path) {
          DCommand(c) => commands.push(c)
          DCmdAlias(al) => aliases.push(al)
        }
      }
    }
    None => ()
  }
  { scope, options, positionals, commands, aliases }
}
