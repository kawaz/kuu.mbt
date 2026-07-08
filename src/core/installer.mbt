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
pub(all) struct ElemDef {
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
  is_dd : Bool // dd installer 所有 (type:"dd")
  is_global : Bool // global installer 所有 (子孫 command scope へコピー伝播)
  is_inherit : Bool // inherit installer 所有 (inherit seat 宣言)
  is_inheritable : Bool // inheritable installer 所有 (DR-059)
  link_depth : Int // >0 なら global COPY が declaring scope 何段下に置かれたか (satellite が Rooted で escape する段数)
  ref_target : String? // DR-020: この要素は named template への ref
  repeat : RepeatSpec? // repeat installer 所有 (DR-043)
  optional : Bool // repeat:{min:0,max:1} の糖衣 (DR-043) — repeat 語彙が所有
  multiple : Bool // multiple installer 所有 (DR-034/043)
  separator : String? // multiple パイプラインの separator (DR-034)
  fail_action : Bool // failure-action element (DR-048)
  is_config_file : Bool // type:"config_file" (DR-050)
  config_key : Array[String]? // 明示 config path (DR-050 §3); None = 同型
  export_key : ExportKey // 結果キー軸 (DR-052)
  requires : Array[String] // constraint installer (DR-055): 正の依存
  conflicts_with : Array[String] // constraint installer (DR-055): 対称ペア排他
  exclusive_group : Array[String] // constraint installer (DR-047): group labels
  // DR-055 §1 + DR-052 §値枝 id 直交: 値の枝に付いた requires。tuple 各成分 =
  // (branch_id, value, targets)。branch_id は or 値枝の匿名要素に付いた識別子 (fixture の `id:
  // "fmt_json"`) で、CRequiresIf 違反時の error.element として emit する (制約の宣言元 = 枝、
  // 値の帰属先 = 親 entity の非対称)。id 未指定時は parent entity name を branch_id にフォールバック
  // (parent 直属の value_requires と等価な挙動)。
  value_requires : Array[(String, String, Array[String])]
  // DR-075 §2 int_round factory config (DR-061 §4 平坦 config キー、`kuu_int_parser` の唯一 config)。
  // canonical default = `RError` (非整数値は Error)、opt-in で floor/trunc/half_even 等の丸めモード。
  // parse 相内部調整で、`value_prim` が IntArg(name, mode) にこの値を埋め込む。TInt 以外の element は
  // 参照しない (installer が読み取らない冗長フィールド)。
  int_round : RoundMode
  // DR-074 §2 統合 opt-in `number_allow_base_prefix` (kuu_number_parser factory config)。canonical
  // default = false (基数 prefix / hex float は Error)、true で `0xff` / `0x1.8p3` / `0o777` / `0b1010`
  // を受理する。value_prim が NumArg(name, flag) / IntArg(name, mode, flag) に埋め込み、eval / matcher
  // で parse_number_ext / parse_int_value_ext に流す。TNum / TInt 以外は参照しない。
  allow_base_prefix : Bool
  deprecated : Bool // DR-058: 使用時 `@depr:<name>` warning
  default_value : Value?
  // MDR-004: 消費文法の軸。`BCell` (既定) = 従来の単一値セル (`ty` フィールドが型、既存全経路の
  // 縮退形、観測挙動不変)。`BOr`/`BGroup` の要素では `ty` は未使用 — 枝/内部要素の leaf ElemDef が
  // 各自の `ty` を持つ。
  body : ElemBody
} derive(Eq, Debug)

///|
/// MDR-004: ElemDef の消費文法軸。`BCell` (単一値セル) 以外の2つは構造化された消費文法:
/// - `BOr`: 構造 or (DR-038 / DESIGN §15.4) — 枝ごとに別の named cell を束縛する「消費文法の枝」。
///   DR-055 の値 enum 枝 (exact 照合、CRequiresIf の素材) とは別物 — あちらは `value_requires` が
///   引き続き担う (§5.3 values 正規形)。
/// - `BGroup`: named group (DR-044 反復グループ) — repeat と組んで、発火ごとに内部 positionals を
///   1 セットずつ束ねる (transparent-seq の `xs{k}` がこの形)。
pub(all) enum ElemBody {
  BCell
  BOr(Array[OrBranch])
  BGroup(Array[ElemDef])
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
pub(all) struct AliasDef {
  target : String
  name : String?
  short : Array[Char]
  long_override : LongDecl?
  deprecated : Bool
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
/// DSL の配列) のどちらか。decode 層 (dec_long) はこの二形をそのまま写すだけ — 型依存の糖衣展開
/// (DR-076 §2 flag 差し替え/補完) や colon DSL 分類 (DR-011) は installer 層の `resolve_long` が担う
/// (二形の区別は wire 上でしか付かない情報なので、展開後の `Array[String]` 単独では復元できない —
/// decode 層で糖衣を潰すと installer 層がこの区別を必要とする場面で情報が失われる)。
pub(all) enum LongDecl {
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
    TNum | TInt =>
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
      let trigger = if prefix == "" {
        own_name
      } else {
        prefix + "-" + own_name
      }
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
/// `LongDecl` (wire 二形) → (main-entry spellings — kebab 展開済み, variants)。DR-071 §1's
/// type-independent `long: true` → `[":set"]` sugar is what every OTHER type gets; DR-076 §2 gives
/// `type:"flag"` a DIFFERENT sugar (規則1: 差し替え) and an explicit non-empty list gets `:set:true`
/// COMPOSED IN alongside whatever the author wrote (規則2: 補完、idempotent). This is the ONLY place
/// that needs the bool/array distinction `LongDecl` preserves — once collapsed to `Array[String]`
/// (the old design), `long:true` and `long:[":set"]` become indistinguishable, yet DR-076 §2 requires
/// different flag sugar for each (kawaz 裁定 2026-07-08, spec DR-071 §1 "wire には二形とも載る、展開は
/// long installer の解釈"). `LInvalid` spellings (DR-011 明確化: colon-less / 語彙外 effect) are
/// silently skipped here — the caller (`normalize_option`) only reaches this AFTER
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
      (longs, vars)
    }
  }
}

///|
/// repeat 閉包 (DR-043)。`min` は必須 rep 数 (mandatory-head unroll)。`max`: None = 無限 (Ref tail),
/// Some(M) = 有限 (M-min BoundedTail heads、Ref 再帰なし LOWERING §B.8)。`optional:true` は
/// `{min:0,max:Some(1)}` の糖衣 (ここで還元、独立概念ではない DR-043)。`lazy_` は取り分選好
/// (greedy default / lazy 最短優先) — MDR-003 で bare `lazy` → `lazy_`。
pub(all) struct RepeatSpec {
  min : Int
  max : Int? // None = unbounded (Ref tail), Some(M) = bounded (BoundedTail)
  lazy_ : Bool // MDR-003: bare `lazy` は予約語衝突 → `lazy_`
} derive(Eq, Debug)

///|
/// subcommand (DR-041 §4)。`export_key`: null = scope key drop, 子は親 scope へ promote (DR-052)。
pub(all) struct CommandDef {
  name : String
  body : Definition
  export_key : ExportKey
} derive(Eq, Debug)

///|
/// 1 つの command scope の UsefulAST。`commands` は DR-018 sugar; command installer が greedy 排他
/// trigger + 新 backbone (DR-041 §4) に展開する。
pub(all) struct Definition {
  options : Array[ElemDef]
  positionals : Array[ElemDef]
  commands : Array[CommandDef]
  aliases : Array[AliasDef] // DR-057
} derive(Eq, Debug)

///|
/// canonical installers (DR-042 §canonical installer セット + DR-043 repeat/multiple)。
pub(all) enum Installer {
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
fn value_prim(
  ty : Ty,
  name : String,
  int_round : RoundMode,
  allow_base_prefix : Bool,
) -> Node {
  match ty {
    // TNum は canonical (DR-074 §1) + opt-in base prefix (§2)。allow=true で hex/oct/bin 整数 + hex
    // float も受理する統合 opt-in (単一 flag、DR-074 §2)。
    TNum => NumArg(name, allow_base_prefix)
    // TInt は値空間判定 (DR-075 §1) + int_round (§2) + hex/oct/bin (DR-074 §2)。IntArg に mode / flag
    // を埋め込み、eval が parse_int_value_ext(_, mode, flag) で丸め + 基数 prefix を反映する。
    TInt => IntArg(name, int_round, allow_base_prefix)
    // TFloat は DR-074 §1 の広い受理域 (number + inf) を持つ別 lexicon (FloatArg / parse_float)
    TFloat => FloatArg(name)
    // TBool は DR-076 §1/§4 で string/number と同格の値型 — BoolArg / parse_bool を通す
    TBool => BoolArg(name)
    _ => StrArg(name)
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
    is_dd: e.is_dd,
    is_global: e.is_global,
    is_inherit: e.is_inherit,
    is_inheritable: e.is_inheritable,
    link_depth: e.link_depth,
    ref_target: e.ref_target,
    repeat: e.repeat,
    optional: e.optional,
    multiple: e.multiple,
    separator: e.separator,
    fail_action: e.fail_action,
    is_config_file: e.is_config_file,
    config_key: e.config_key,
    export_key: e.export_key,
    requires: e.requires,
    conflicts_with: e.conflicts_with,
    exclusive_group: e.exclusive_group,
    value_requires: e.value_requires,
    deprecated: e.deprecated,
    default_value: e.default_value,
    int_round: e.int_round,
    allow_base_prefix: e.allow_base_prefix,
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
fn normalize_option(e : ElemDef) -> ElemDef {
  if e.is_dd {
    normalize_dd_name(e)
  } else {
    // DR-076 §2: flag の展開後の値セルは bool (LOWERING §A.5) — resolve_long は元の型 (e.ty, まだ
    // TFlag) で判定する必要があるので、型差し替えより先に呼ぶ。
    let (longs, vars) = resolve_long(e.long, e.name, e.ty)
    let ty2 = if e.ty == TFlag { TBool } else { e.ty }
    { ..e, ty: ty2, long: LList(longs), variants: vars }
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
  }
}

///|
/// 要素の lowered head: 値プリミティブ / Ref (ref_target) / SepArg (separator)。
fn elem_head(e : ElemDef) -> Node {
  match e.ref_target {
    Some(r) => Ref(r)
    None =>
      match e.separator {
        Some(sep) => SepArg(e.name, sep)
        None => value_prim(e.ty, e.name, e.int_round, e.allow_base_prefix)
      }
  }
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
          // DR-038) がそのまま輪郭を満たす — repeat との組合せは対象 fixture に無いので未対応。
          let nodes : Array[Node] = []
          for br in branches {
            nodes.push(or_branch_node(br))
          }
          out.push(Or(nodes))
        }
        BGroup(items) => {
          // MDR-004 §3 "BGroup + repeat": IdxRepeat(label=name, head=Seq(inner cells), min) に lower。
          // スコープ限定: UNBOUNDED (max:null) のみ — IdxRepeat(String, Node, Int) は budget を
          // 持たず bounded を表現できない (bounded named-group が来たら budget 拡張が別途要る)。
          //
          // bounded-head 前提 (issue 2026-07-08 greedy-once-and-idxrepeat-premises §2, kawaz 裁定
          // 待ち — installer 規約としての明文化を選択、eval 側への backtrack 追加は見送り): `idx_repeat_eval`
          // (eval.mbt) は宣言上 deterministic な greedy-max で、下流失敗時の後退 (regex backtracking,
          // DR-043 の通常 repeat が `ref_choice` で持つ機構) を持たない。head が permissive (bare string
          // primitive 等、無制限にどんなトークンでも消費できる) だと、後続の必須 positional のぶんまで
          // greedy-max に食われて starve しうる (backtrack が無いので回復しない) — 通常 repeat の
          // backtrack.json fixture が固定する「縮小再分割」の保証は IdxRepeat には及ばない。この lowering
          // (named-group repeat) を書く際は head の先頭に明示的な trigger (Exact 等) を持たせる、または
          // 末尾に必須 positional を続けない設計にすること。現状 conformance fixture に BGroup+repeat の
          // ケースが無いため実害未確認 (再現は eval_wbtest.mbt の低レベル Node 直接構築テストのみ)。
          let head = if items.length() == 1 {
            elem_head(items[0])
          } else {
            let nodes : Array[Node] = []
            for it in items {
              nodes.push(elem_head(it))
            }
            Seq(nodes)
          }
          let min = match elem_repeat(e) {
            Some(spec) => spec.min
            None => 0
          }
          out.push(IdxRepeat(e.name, head, min))
        }
        BCell => {
          let head = elem_head(e)
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
                    // UNBOUNDED min>=1 (DR-043): `name = Seq([head, Opt(Ref(name))])` の porous 自参照
                    registry.set(e.name, Seq([head, opt_node(Ref(e.name))]))
                    if spec.lazy_ {
                      // lazy marker (evaluator が split 選好を引くための mangled key)
                      registry.set("lazy:" + e.name, Exact("lazy"))
                    }
                    let m = spec.min
                    let mut k = 0
                    while k < m - 1 {
                      out.push(head) // mandatory unrolled heads (DR-043 min)
                      k = k + 1
                    }
                    out.push(Ref(e.name)) // >= 1 porous recursive tail
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
    if not_dd(e) {
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
    BCell => ensure_entity(build, e, has_cf)
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
  //   repeat → "flatten" (cons [T,[T,…]] → T[], DR-043)
  //   multiple / separator → "append" (DR-034)
  // 両方立った場合は multiple の append が勝つ (値 fold が支配)。
  // DR-044 §1 (kawaz 裁定): repeat / multiple / separator は cardinality 不問で常に配列
  //   (`repeat:{min:0,max:1}` = optional 糖衣も [] / [x] — scalar 昇格は collector 側の責務)。
  let accum : String? = if e.multiple {
    Some("append")
  } else {
    match elem_repeat(e) {
      Some(_) => Some("flatten")
      None => if e.separator is Some(_) { Some("append") } else { None }
    }
  }
  // 同型 config seat (DR-050 §3): config_file 要素が存在すれば全 value cell に config seat を宣言
  // (自身が config_file の要素は循環禁止で除く)。config_key は path override; None = 同型。
  let config_seat = has_cf && !e.is_config_file
  // flag/bool preset default (LOWERING §A.5 / DR-051 §2): a TFlag or DR-074 TBool cell presets
  // default:false (未 fire でも false に落ちる)。明示 default があればそちらが勝つ (e.g. ssl の default:true)。
  let default_value : Value? = match e.default_value {
    Some(v) => Some(v)
    None =>
      if e.ty == TFlag || e.ty == TBool {
        Some(VBool(false))
      } else {
        None
      }
  }
  build.entities.push({
    name: e.name,
    ty: e.ty,
    env_key: None,
    config_seat,
    config_key: e.config_key,
    is_config_file: e.is_config_file,
    inherit_: false, // MDR-003: node.mbt 側 Entity.inherit_
    accum,
    default_value,
  })
}

///|
fn not_dd(e : ElemDef) -> Bool {
  !e.is_dd
}

// ── 各 installer ─────────────────────────────────────────────────────────────

///|
/// long: `long` を READ、name あたり greedy exact 衛星 (space form) と、value 系なら eq-split matcher
/// を add-if-absent で追加。衛星は name で entity に link (DR-042 §展開の標準パターン)。
fn inst_long(def : Definition, build : Build) -> Unit {
  let eq_entries : Array[LongEntry] = []
  for e in def.options {
    for l in long_of(e) {
      let trigger = "--" + l
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
        _ =>
          // DR-076 §1/§2/§4: every value-typed main entry (bool included, flag ALREADY normalized to
          // TBool by `normalize_option`, DR-076 §2) is a NORMAL value satellite — `:set` always takes
          // a value (space form here; eq form via eq_entries below). A bare `--x` fire (the classic
          // flag shape) needs the explicit `:set:true` variant (decoded as a Set-op Variant with
          // operand VBool(true), lowered by the "Variant entries" loop below, which also carries the
          // fail_action FailMark — flag's presence-only lowering has fully collapsed into that generic
          // variant path; this arm no longer special-cases TFlag/TBool bare-true at all).
          add_greedy(
            build,
            maybe_root(
              e.link_depth,
              Seq([
                Exact(trigger),
                value_prim(e.ty, e.name, e.int_round, e.allow_base_prefix),
              ]),
            ),
          )
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
      match e.body {
        BOr(branches) =>
          for br in branches {
            if br.items.length() == 1 {
              let leaf = br.items[0]
              eq_entries.push({
                key: l,
                name: leaf.name,
                kind: leaf.ty,
                int_round: leaf.int_round,
                allow_base_prefix: leaf.allow_base_prefix,
              })
            }
          }
        BGroup(_) => () // positional-only shape (MDR-004 §3 scope) — no long spelling applies
        BCell =>
          // DR-076 §2: no `e.ty != TFlag` guard needed here anymore — a classic flag never reaches
          // this loop body at all (its `e.long` is empty, `long_of(e)` yields no `l` to iterate), so
          // the guard was always vacuous for it; an explicit `long:[":set"]` flag (now TBool) SHOULD
          // register its eq-split form, which this unconditional push now does correctly (the guard
          // used to wrongly suppress it while `e.ty` still read TFlag pre-normalize_option).
          eq_entries.push({
            key: l,
            name: e.name,
            kind: e.ty,
            int_round: e.int_round,
            // DR-074 §2: TNum / TInt の eq-split (`--v=0xff`) も factory config を反映するよう
            // ElemDef から LongEntry に持ち込む (他 kind は entry 側で参照されない)。
            allow_base_prefix: e.allow_base_prefix,
          })
      }
    }
  }
  if eq_entries.length() > 0 {
    add_greedy(build, NativeMatch(EqSplit(prefix="--", entries=eq_entries)))
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
      let trigger = "--" + v.trigger
      let sat = match v.op {
        Set => {
          let operand = match v.operand {
            Some(val) => val
            None => VBool(true)
          }
          if e.fail_action {
            Seq([Exact(trigger), Bind(e.name, operand), FailMark(e.name)])
          } else {
            Seq([Exact(trigger), Bind(e.name, operand)])
          }
        }
        _ => Seq([Exact(trigger), EffMark(e.name, v.op)])
      }
      add_greedy(build, maybe_root(e.link_depth, sat))
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
/// short: `short` を READ、cluster/value-attach matcher を 1 本 add-if-absent。PoC では single-char
/// (`-v`, `-p 8080`) も matcher に集約するため、short は独立 exact 衛星を発しない (matcher-seat)。
fn inst_short(def : Definition, build : Build) -> Unit {
  let sh_entries : Array[ShortEntry] = []
  for e in def.options {
    for c in e.short {
      // DR-058: deprecated alias entry-copy は cluster entry でも警告する
      // DR-075 §2: short cluster / space-tail 経路の TInt (`-n1.5` / `-n 1.5`) も factory config を反映
      sh_entries.push({
        ch: c,
        name: e.name,
        kind: e.ty,
        depr: e.deprecated,
        int_round: e.int_round,
        // DR-074 §2: short cluster / space-tail の TNum / TInt も allow_base_prefix を反映
        allow_base_prefix: e.allow_base_prefix,
      })
    }
  }
  if sh_entries.length() > 0 {
    add_greedy(build, NativeMatch(ShortCombine(prefix="-", entries=sh_entries)))
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
  for e in def.options {
    if e.is_dd {
      add_greedy(build, DdSat(e.name))
    }
  }
  for e in def.positionals {
    if e.is_dd {
      add_greedy(build, DdSat(e.name))
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
    is_dd: copy.is_dd,
    is_global: copy.is_global,
    is_inherit: copy.is_inherit,
    is_inheritable: copy.is_inheritable,
    link_depth: copy.link_depth + 1,
    ref_target: copy.ref_target,
    repeat: copy.repeat,
    optional: copy.optional,
    multiple: copy.multiple,
    separator: copy.separator,
    fail_action: copy.fail_action,
    is_config_file: copy.is_config_file,
    config_key: copy.config_key,
    export_key: copy.export_key,
    requires: copy.requires,
    conflicts_with: copy.conflicts_with,
    exclusive_group: copy.exclusive_group,
    value_requires: copy.value_requires,
    deprecated: copy.deprecated,
    default_value: copy.default_value,
    int_round: copy.int_round,
    allow_base_prefix: copy.allow_base_prefix,
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
fn apply_node(inst : Installer, sb : SB) -> Unit {
  match inst {
    LongInst => inst_long(sb.decl, sb.build)
    ShortInst => inst_short(sb.decl, sb.build)
    EnvInst => inst_env(sb.decl, sb.build)
    DdInst => inst_dd(sb.decl, sb.build)
    InheritInst => inst_inherit(sb.decl, sb.build)
    GlobalInst => inst_global(sb)
    CommandInst => () // materialize で wire
    RepeatInst => () // init_sb で決定的に lower (Ref 再帰 + template)
    MultipleInst => () // ensure_entity で accumulator flag を決定的に set
    ConfigInst => () // ensure_entity で config seat を決定的に set (席宣言型 DR-050/042 ④)
    ConstraintInst => inst_constraint(sb.decl, sb.build)
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
    is_dd: false,
    is_global: false,
    is_inherit: false, // inherit seat は inst_inheritable step(2) が立てる
    is_inheritable: false, // copy 自体は plain entry (再伝播しない)
    link_depth: 0,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple: false,
    separator: None,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    value_requires: [],
    deprecated: false,
    default_value: None, // write-target に default を置かない (§3): 実書き込みのみが伝播する
    int_round: RError, // canonical default (DR-075 §2): write-target は int_round を持たない
    allow_base_prefix: false, // canonical default (DR-074 §2): write-target は base prefix opt-in を持たない
    body: BCell,
  })
}

///|
/// constraint installer (DR-055 / DR-042 席宣言型): requires / conflicts_with / exclusive_group /
/// value_requires を scope の遅延述語として登録。構造衛星は無し (DR-047 完全 path の最終状態で評価)。
fn inst_constraint(def : Definition, build : Build) -> Unit {
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
    is_dd: false,
    is_global: false,
    is_inherit: false,
    is_inheritable: false,
    link_depth: 0,
    ref_target: None,
    repeat: None,
    optional: false,
    multiple: false,
    separator: None,
    fail_action: false,
    is_config_file: false,
    config_key: None,
    export_key: EkUnset,
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    value_requires: [],
    deprecated,
    default_value: None,
    int_round: RError,
    allow_base_prefix: false,
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
fn tree_pass(order : Array[Installer], sb : SB, has_cf : Bool) -> Unit {
  ensure_entities(sb, has_cf)
  for inst in order {
    apply_node(inst, sb)
  }
  for child in sb.children {
    tree_pass(order, child.body, has_cf)
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
    StrArg(_)
    | SepArg(_, _)
    | NumArg(_, _)
    | FloatArg(_)
    | IntArg(_, _, _)
    | BoolArg(_)
    | FilterArg(_, _)
    | ReqArg(_)
    | Exact(_)
    | NativeMatch(_)
    | DdSat(_)
    | CmdSat(_, _) => true
    NoDashStr(_) => true // dash-reject でなければ 1 token 消費
    IdxRepeat(_, _, _) => true // 名前付き indexed repeat は head を消費
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
pub fn parse_definition(
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
    tree_pass(order, sb, has_cf)
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
