// installer.mbt — builtin parse_definition as a chain of installers (DR-042).
//
// UsefulAST (@engine.ElemDef / @engine.Definition / …) → AtomicAST (@engine.Scope / @engine.Node / @engine.Entity / …) を組み立てる lowering 層。
// 各 installer は special vocab (long / short / env / dd / ...) を所有し、apply 時に (1) その vocab を
// READ (削除しない — 宣言層は read-only, invariant ①'), (2) greedy 衛星 / matcher / re-scoping を
// add-if-absent で implant する, (3) 実体 (@engine.Entity) の seat (env / inherit) を宣言する。5 invariants により
// chain の順序に依存せず、idempotent。完全性は「chain のどの installer にも所有されない special vocab」の検査。
//
// MDR-002 §3 準拠: installer は node / value / matcher / resolve に依存し、評価器 (eval) には依存しない。
// MDR-002 追記「CPS の射程」の installer 規約: repeat はスパイン形 (positional の Ref / @engine.BoundedTail /
// @engine.ScopeNode) にのみ正規化し、@engine.Or / @engine.Seq / @engine.Rooted 内部への埋め込みは生成しない (取り分選好の局所化を避けるため)。
// MDR-003 命名規約: bare 予約語は末尾 `_` 化 — @engine.RepeatSpec の bare `lazy` は `lazy_` に rename。
// @engine.Entity 側の `inherit_` は node.mbt が rename 済み。

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
pub(all) enum LongSpelling {
  LMain(String) // resolved main-entry spelling (`own_name`, verbatim — see `classify_long_spelling`)
  LVariant(@engine.Variant) // a fully-built variant (trigger/op/operand already resolved against own_name)
  LInvalid(String) // syntax error (colon-less, or unrecognized effect word) — the original string
} derive(Eq, Debug)

///|
/// Naive scalar coercion for a colon-DSL operand string (`no:set:false`'s `"false"`, `:set:true`'s
/// `"true"`, etc.) into the element's `@engine.Value` per its type — mirrors `@engine.config_to_value`'s per-type
/// parsers (DR-074/075/076 canonical lexicons) but with a permissive `@engine.VStr` fallback instead of an
/// Error: a DSL operand is a literal the DEFINITION author wrote (not untrusted CLI input), so an
/// unparseable operand degrading to a string is a defensive fallback, not a silent-coercion concern.
fn dsl_operand_value(ty : &@engine.TypeExt, s : String) -> @engine.Value {
  match ty.parse_token(s) {
    Ok(value) => value
    Err(_) =>
      if ty.name() == "flag" || ty.name() == "bool" {
        @engine.VBool(s == "true" || s == "1")
      } else {
        @engine.VStr(s)
      }
  }
}

///|
/// Classify one `long`/`long_override` DSL string against `own_name` (the caller decides WHICH name
/// applies — a canonical element's own kebab name for `resolve_long`/`normalize_option`, or an
/// alias's re-derived name for `@engine.AliasDef.long_override` desugaring, DR-057 §3) and the element's
/// type (for `LVariant`'s operand parsing, DR-074/075/076). This is the SOLE interpreter of the
/// colon DSL (DR-011/071/076 wire vocab) — both `resolve_long` (main `long` attribute) and
/// `desugar_aliases` (alias override desugaring) call this so the two paths can never drift apart
/// (issue 2026-07-08 alias `long_override` gap: aliases used to skip DSL classification entirely,
/// silently misinterpreting `":set:true"` as a literal `"--:set:true"` spelling).
pub fn classify_long_spelling(
  s : String,
  own_name : String,
  ty : &@engine.TypeExt,
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
  // @engine.DUnknownVocab collection wholesale instead of a parallel definition-error check
  // (design-priority: 既存の枠組みの組み合わせで解決). codex 指摘 (issue 2026-07-09, DR-047 の設計
  // 報告と同じ節目レビュー): 旧実装は `parts[2] == "increment"` のハードコード allowlist だった —
  // DR-077 §2 の契約通り filters registry を実際に引いて signature を検査する形に置換。不在
  // (registry に無い名前) と、存在するが `Validate` signature (transform として使えない、
  // DR-077 §2 "validate-only filters cannot be used as an update transform" と同じ判定) の 2 つを
  // 区別して弾く — どちらも現行 `@engine.DefErrKind` 列挙 (DR-054) に "invalid-signature" 相当の細分 kind が
  // 無いため、両方とも `@engine.DUnknownVocab` のまま kind は共通、メッセージ文言だけで理由を分ける
  // (実装の裁量、細分 kind 追加は spec 側の DR-054 拡張判断が要るため見送り — 報告に明記)。
  if parts[1] == "update" {
    if parts.length() >= 3 {
      let transform = parts[2]
      match lookup_filter(transform) {
        None => return LInvalid(s) // 不在: unknown-vocab (registry に無い名前)
        Some(d) =>
          if d.signature.is_transform() {
            let args : Array[String] = []
            let mut i = 3
            while i < parts.length() {
              args.push(parts[i])
              i = i + 1
            }
            return LVariant({
              trigger,
              op: @engine.Update(transform, args),
              operand: None,
            })
          } else {
            return LInvalid(s) // 存在するが Validate signature: transform として使えない
          }
      }
    }
    return LInvalid(s)
  }
  let op : @engine.EffectOp? = match parts[1] {
    "set" => Some(@engine.Set)
    "unset" => Some(@engine.Unset)
    "empty" => Some(@engine.Empty)
    "default" => Some(@engine.Default)
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
/// composes in — `classify_long_spelling(":set:true", kebab(name), flag_type())` would build the SAME
/// value (colon-DSL round-trip), this just skips the string-splitting for the one fixed shape.
fn flag_bare_true_variant(name : String) -> @engine.Variant {
  { trigger: kebab(name), op: @engine.Set, operand: Some(@engine.VBool(true)) }
}

///|
/// DR-077 §3: the `:update:increment` variant (bare-trigger fire → apply the `increment` transform
/// to the linked cell's old value) a count's long展開 composes in — mirrors `flag_bare_true_variant`
/// exactly, just with `@engine.Update("increment", [])` in place of `@engine.Set`/`true` (count has no operand to
/// carry; the fired value depends on the cell's running state, computed by resolve.mbt's fold).
fn count_increment_variant(name : String) -> @engine.Variant {
  { trigger: kebab(name), op: @engine.Update("increment", []), operand: None }
}

///|
/// `@engine.LongDecl` (wire 二形) → (main-entry spellings — kebab 展開済み, variants)。DR-071 §1's
/// type-independent `long: true` → `[":set"]` sugar is what every OTHER type gets; DR-076 §2 gives
/// `type:"flag"` a DIFFERENT sugar (規則1: 差し替え) and an explicit non-empty list gets `:set:true`
/// COMPOSED IN alongside whatever the author wrote (規則2: 補完、idempotent). DR-077 §3 gives
/// `type:"count"` the SAME two-rule treatment with `:update:increment` in place of `:set:true` —
/// count is the 2nd instance of this exact 糖衣差し替え+補完 machinery (not a parallel mechanism).
/// This is the ONLY place that needs the bool/array distinction `@engine.LongDecl` preserves — once
/// collapsed to `Array[String]` (the old design), `long:true` and `long:[":set"]` become
/// indistinguishable, yet DR-076/077 require different flag/count sugar for each (kawaz 裁定
/// 2026-07-08, spec DR-071 §1 "wire には二形とも載る、展開は long installer の解釈"). `LInvalid`
/// spellings (DR-011 明確化: colon-less / 語彙外 effect, DR-077 §2 unknown transform) are silently
/// skipped here — the caller (`normalize_option`) only reaches this AFTER
/// `collect_invalid_long_dsl` has already surfaced them as definition-errors and `parse_definition`
/// has returned early on any error, so none should be live at this point in practice.
fn resolve_long(
  decl : @engine.LongDecl,
  name : String,
  ty : &@engine.TypeExt,
) -> (Array[String], Array[@engine.Variant]) {
  match decl {
    LBool(false) => ([], [])
    LBool(true) =>
      if ty.name() == "flag" {
        ([], [flag_bare_true_variant(name)])
      } else if ty.name() == "count" {
        ([], [count_increment_variant(name)])
      } else if ty.name() == "none" {
        // DR-089 §2 の「消費 0 の純トリガ」canonical 例 (`{"name": "sep", "long": true}`) —
        // flag_type()/count_type() と同じ「main entry を持たず bare-true variant だけ」の 3 例目。none には
        // 運ぶ値が無いので `flag_bare_true_variant` のプレースホルダ (`@engine.Set @engine.VBool(true)`) をそのまま
        // 再利用してよい — この @engine.Binding は `build_result` 側で `@engine.NoneCell` により結果から除外される
        // (`resolve.mbt` 参照)、committed 参加 (conflicts/exclusive/requires トリガ側) だけが生きる。
        ([], [flag_bare_true_variant(name)])
      } else {
        ([kebab(name)], [])
      }
    LList(strs) => {
      let longs : Array[String] = []
      let vars : Array[@engine.Variant] = []
      for l in strs {
        match classify_long_spelling(l, kebab(name), ty) {
          LMain(n) => longs.push(n)
          LVariant(v) => vars.push(v)
          LInvalid(_) => ()
        }
      }
      if ty.name() == "flag" && (longs.length() > 0 || vars.length() > 0) {
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
      if ty.name() == "count" && (longs.length() > 0 || vars.length() > 0) {
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
pub fn owned_vocab(installer : &@engine.InstallerExt) -> String {
  match installer.vocab() {
    [first, ..] => first
    [] => ""
  }
}

///|
/// 値プリミティブの唯一の構築点 (positional / long / short いずれの value slot もここを通る,
/// issue 2026-07-09-separator-non-string-type-parse-gap 段1: 以前は `elem_head` だけが
/// `separator` を見て `separated resident` に分岐し、long/short main entry はこの関数を `separator` 抜きで
/// 直接呼んでいたため、long/short option で `multiple + separator` を宣言しても分割が一切効かない
/// 既存バグがあった — `separator` をこの関数自身の分岐に格上げし、呼び出し元 (positional の
/// `elem_head` / long の `inst_long` main entry) が同じ判断を共有するよう一元化した。`separator`
/// が `Some` なら `separated resident` を構築し、型情報 (ty/int_round/allow_base_prefix) をそのまま運搬する
/// (段2: separated resident 自身が piece ごとに型 parse を行う、`sep_binds` 参照) — 段1 (分割自体を配線) と
/// 段2 (分割後の型 parse) は同一サイクルで導入必須 (issue 追記2: 段1 単独では成功系が regress する
/// 実測確認済み)。
/// `merge` (DR-080 波及節): `@engine.ElemDef.accumulator == Some("merge")` の素通し。両呼び出し元
/// (`elem_head` / `inst_long` main entry) が同じ判断 (`e.accumulator` を見る) を共有する。
///
/// codex Medium 追従 (2026-07-10, issue merge-no-separator-marker-gap): 経路選択は
/// `separator is Some(_)` **単独**ではなく `separator is Some(_) || merge` — merge 宣言要素は
/// `separator` 未宣言でも `separated resident` (piece 処理) 側へ進む。`separator` は `separated resident` へそのまま
/// `String?` で運び (`sep_binds` が `None` を「1 piece = 全体」として扱う、DR-034 §6.3 の縮退)、
/// マーカー認識 (`@engine.classify_merge_piece`) は piece 数に関わらず同じ pipeline で効く — `--fields -a`
/// (separator 無し、コンマで割る余地が無い) でも `-a` が remove マーカーとして解釈される。
/// merge でない要素は従来通り `separator is Some(_)` のみが gate (この分岐は不変)。
///
/// `kv_map` (DR-091 §2): `@engine.ElemDef.accumulator == Some("kv_map")` は `merge`/`separator` の separated resident
/// 経路とは別枝 — kv_map は「1 token = 1 piece」で separator 分割を必要としない (`k=v` の `=` 分割は
/// この node の仕事ではなく `resolve.mbt`'s `build_result` が畳み時に行う、node.mbt の `kv resident` doc
/// comment参照)。`merge` より先に判定するのは两者が同時に真になることは無い (decode 層 `dec_multiple`
/// が `accumulator` を単一 `String?` としてしか運ばない、DR-080/DR-091 のどちらか一方の語彙) ため
/// 順序に意味は無いが、kv resident が separated resident の分岐に巻き込まれないよう最初に切り出す。
fn value_prim(
  ty : &@engine.TypeExt,
  name : String,
  int_round : @engine.RoundMode,
  allow_base_prefix : Bool,
  bool_config : @engine.BoolConfig,
  piece_filters : Array[@engine.FilterSpelling],
  separator? : String? = None,
  merge? : Bool = false,
  kv_map? : Bool = false,
) -> @engine.Node {
  let configured = configured_type(
    ty, int_round, allow_base_prefix, bool_config,
  )
  if kv_map {
    kv_arg(name, piece_filters)
  } else if separator is Some(_) || merge {
    separated_arg(
      name, separator, configured, int_round, allow_base_prefix, bool_config, piece_filters,
      merge,
    )
  } else {
    match ty.name() {
      "number" => number_arg(name, allow_base_prefix, piece_filters)
      "int" => int_arg(name, int_round, allow_base_prefix, piece_filters)
      "float" => float_arg(name, piece_filters)
      "bool" => bool_arg(name, bool_config, piece_filters)
      "string" => string_arg(name, piece_filters)
      _ =>
        // A value-less resident still consumes its positional token structurally; the
        // placeholder binding is removed through the element's NoneCell metadata.
        if configured.has_value_slot() {
          typed_arg(name, configured, piece_filters)
        } else {
          string_arg(name, piece_filters)
        }
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
/// Deep-copy an `Array[@engine.FilterSpelling]` — mirrors `copy_strs`'s discipline (global/alias desugaring
/// pushes COPIES into descendant scopes, `clone_elem`'s doc comment) but also copies each entry's
/// own `args : Array[String]` (a mutable nested array `copy_strs`-style aliasing would otherwise
/// share across scope copies).
fn copy_filter_spellings(
  a : Array[@engine.FilterSpelling],
) -> Array[@engine.FilterSpelling] {
  let r : Array[@engine.FilterSpelling] = []
  for fs in a {
    r.push({ name: fs.name, args: copy_strs(fs.args) })
  }
  r
}

///|
/// 有効 long 綴り一覧 (post-normalize; `:set` は既に kebab(name) に展開済み、`normalize_option` が
/// `@engine.LongDecl` を `LList([<kebab main entries>])` に確定させた後の形)。[] = main-entry なし (DR-071)。
/// pre-normalize な `LBool` はここに来ない前提 (呼び出しは全て normalize 後)。
fn long_of(e : @engine.ElemDef) -> Array[String] {
  match e.long {
    LList(strs) => strs
    LBool(_) => []
  }
}

///|
fn copy_long(l : @engine.LongDecl) -> @engine.LongDecl {
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
fn copy_variants(a : Array[@engine.Variant]) -> Array[@engine.Variant] {
  let r : Array[@engine.Variant] = []
  for x in a {
    r.push(x)
  }
  r
}

///|
fn clone_elem(e : @engine.ElemDef) -> @engine.ElemDef {
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
/// MDR-004: deep-clone `@engine.ElemBody`'s nested `@engine.ElemDef`s (mirrors the Array-field deep-copy discipline
/// `clone_elem` already applies to `long`/`variants`/`short`/`env` — global/alias desugaring pushes
/// COPIES into descendant scopes, so aliasing the same mutable nested arrays across scopes would be
/// a bug).
fn clone_body(b : @engine.ElemBody) -> @engine.ElemBody {
  match b {
    BCell => BCell
    BOr(branches) => {
      let out : Array[@engine.OrBranch] = []
      for br in branches {
        let items : Array[@engine.ElemDef] = []
        for it in br.items {
          items.push(clone_elem(it))
        }
        out.push({ id: br.id, items })
      }
      BOr(out)
    }
    BGroup(items) => {
      let out : Array[@engine.ElemDef] = []
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
///   Fix 2 (§B.1 / DR-071 / DR-076 §2, kawaz 裁定 2026-07-08): `resolve_long` が `@engine.LongDecl` (wire 二形)
///   を解釈し、main entry (kebab 展開済み) と variants に確定させる。糖衣展開・flag 差し替え/補完・
///   colon DSL 分類はここに集約 — decode 層 (dec_long) はもう wire の形を写すだけ (二形の区別は decode
///   後に潰さない、`resolve_long` のコメント参照)。
///   Fix 3 (DR-064 §5): dd 要素で name 未指定なら trigger 綴りを "--" に既定
///   Fix 4 (LOWERING §A.5 / DR-076 §2): flag_type() の値セルを bool_type() へ差し替え (flag = bool + default:false +
///   long 綴り合成)。これにより inst_long / eq_entries は flag_type() を特殊扱いする必要がなくなり、bool と
///   完全同一の lowering 経路に自然に乗る (flag 固有の lowering 分岐を「型差し替え + resolve_long」の
///   2 点だけに縮退させる、DR-076 §2 規則4)。
fn normalize_surface(def : @engine.Definition) -> Unit {
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
/// DR-076 §2: flag の展開後の値セルは bool (LOWERING §A.5) — resolve_long は元の型 (e.ty, まだ flag_type())
/// で判定する必要があるので、型差し替えより先に呼ぶ。`flag_type() → bool_type()` はここで確定してよい — `bool_type()`
/// 型の short/eq-split 挙動は "bool_type() 全般に画一的なルール" (非消費・固定 true) で閉じるので、変換後も
/// 「元 flag だったか」を覚えておく必要が無い (builtins/matcher_residents.mbt の `flag_type() | bool_type()` アームが両方 flag 型と
/// して扱うのはこの画一性のおかげ)。
///
/// DR-077 §3 (`count_type()`) は対称的な糖衣に見えて **ここでは number_type() に変換しない** — count 由来の short/
/// eq-split 挙動 (非消費・固定 increment) は「number_type() 全般」には適用できない (ordinary number の short
/// は値を消費するのが正しい挙動、`-n5` 等) ので、flag と違って「型変換後も元 count だったか」を覚えて
/// おく必要がある。@engine.ElemDef に専用マーカーを新設する代わりに、**count_type() というタグ自体を installer chain
/// の間ずっと保持し、値セルの実体型 (@engine.Entity.ty = number_type()) への収束を `ensure_entity` まで遅延させる**
/// (`ensure_entity` のコメント参照) — 既存の型そのものが情報を運ぶ設計は崩さず、collapse のタイミングだけ
/// 後ろにずらす。short/eq-split matcher (builtins/matcher_residents.mbt) は `count_type()` を `flag_type() | bool_type()` と並ぶ第 3 の
/// 非消費挙動として扱う。
fn normalize_option(e : @engine.ElemDef) -> @engine.ElemDef {
  if e.is_dd {
    normalize_dd_name(e)
  } else {
    let (longs, vars) = resolve_long(e.long, e.name, e.ty)
    // flag_type() は bool_type() へ書き換わり `ensure_entity` 到達時には元 flag_type() だったかを判別できなくなる
    // ため、flag preset の default:false (LOWERING §A.5) はこの型差し替えと同じ場所で確定させる
    // (issue group-inner-bool-default-false-duplicate-top-level: plain bool_type() は暗黙 default を
    // 持たないので `ensure_entity` 側の注入対象を絞る一方、flag 由来の bool_type() は preset を維持する
    // 必要がある — 明示 default があればそちらが勝つのは変わらない)。
    let default_values2 = if e.ty.name() == "flag" && e.default_values is None {
      Some([@engine.VBool(false)])
    } else {
      e.default_values
    }
    let ty2 = if e.ty.name() == "flag" { bool_type() } else { e.ty }
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
fn normalize_dd_name(e : @engine.ElemDef) -> @engine.ElemDef {
  if e.is_dd && e.name == "" {
    { ..e, name: "--" } // DR-064 §5
  } else {
    e
  }
}

///|
fn clone_def(d : @engine.Definition) -> @engine.Definition {
  let os : Array[@engine.ElemDef] = []
  for e in d.options {
    os.push(clone_elem(e))
  }
  let ps : Array[@engine.ElemDef] = []
  for e in d.positionals {
    ps.push(clone_elem(e))
  }
  let cs : Array[@engine.CommandDef] = []
  for c in d.commands {
    cs.push({ name: c.name, body: clone_def(c.body), export_key: c.export_key })
  }
  let als : Array[@engine.AliasDef] = []
  for a in d.aliases {
    als.push(a) // @engine.AliasDef は immutable value data (nested mutable array を持たない)
  }
  { options: os, positionals: ps, commands: cs, aliases: als }
}

///|
/// 結果キー map の構築 (DR-052)。要素/コマンド名 → export_key。post-parse の結果 remap 用。alias
/// を desugar 済みの clone に対して収集する — command alias の export_key = @engine.EkKey(canonical) が
/// 建った @engine.Scope の keying と一致するように。
pub fn build_export_map(
  def : @engine.Definition,
) -> Map[String, @engine.ExportKey] {
  let d = clone_def(def)
  // `d` は normalize_surface を経ていない生の (= pre-normalize) 複製なので、`orig` 引数にも
  // 同じ `d` を渡してよい (flag_type() 等の元の型はまだ書き換わっていない)。
  desugar_aliases(d, d)
  let m : Map[String, @engine.ExportKey] = Map([], capacity=0)
  collect_export(d, m)
  m
}

///|
fn collect_export(
  def : @engine.Definition,
  m : Map[String, @engine.ExportKey],
) -> Unit {
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
/// MDR-004 §3b: `collect_export` needs to recurse into `@engine.ElemBody` — a `BGroup`/`BOr` element's
/// nested leaves (e.g. transparent-seq's `k`, export_key:null) each have their OWN export_key that
/// must reach the map, or their `export_key:null` 裸値化 (DR-052 §2) never gets applied downstream
/// (resolve's export-key remap only consults this map). `BGroup` registers BOTH the wrapper (the
/// array cell itself) and its inner leaves; `BOr`'s wrapper has no export_key of its own concern
/// (structural dispatcher, no scalar/array value) — only its branch leaves register.
fn collect_export_body(
  e : @engine.ElemDef,
  m : Map[String, @engine.ExportKey],
) -> Unit {
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
/// 要素の lowered head: 値プリミティブ / Ref (ref_target) / separated resident (separator, `value_prim` 側に集約
/// 済み — このヘルパー自身の役目は ref_target の分岐のみ)。issue
/// 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見の穴埋め: `is_exact` (positional-face
/// nameless exact-match leaf, `@engine.ElemDef.is_exact` doc comment) は ref_target 分岐より先に判定する —
/// value_prim/Ref どちらの経路も通らず `@engine.Exact(name)` へ直接 lower する、bare `@engine.Exact` node は「literal
/// token match; binds nothing, consumes 1」(node.mbt) がそのまま欲しい挙動そのもの。この経路は
/// `BOr`/`BGroup` の内側リーフ (`or_branch_node`/`lower_positional` の BGroup 分岐が `elem_head` を
/// 共有する) にも自動的に及ぶ — DR-063 A.1 の裸文字列正規化が or 枝内でも成立する形と対称。
pub fn elem_head(e : @engine.ElemDef) -> @engine.Node {
  if e.is_exact {
    return @engine.Exact(e.name)
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
/// 未定義値は or 全枝の綴り不一致 (Reject)" — no held error, same posture bare `@engine.Exact` already has:
/// a non-matching token means every branch of the `@engine.Or` below fails to @engine.Accept, so the read simply
/// isn't there — no separate "reject" signal needed). Each matching branch's @engine.Bind value goes
/// through `dsl_operand_value` (the SAME type coercion `classify_long_spelling`'s DSL operand
/// parsing already uses for variant operands) so a non-string-typed enum would get a correctly-
/// typed value — moot for today's only callers (string-only `values`, this issue's scope) since
/// `dsl_operand_value(string_type(), s) = @engine.VStr(s)`.
pub fn enum_value_node(
  name : String,
  ty : &@engine.TypeExt,
  values : Array[String],
) -> @engine.Node {
  let branches : Array[@engine.Node] = []
  for v in values {
    branches.push(
      @engine.Seq([
        @engine.Exact(v),
        @engine.Bind(name, dsl_operand_value(ty, v)),
      ]),
    )
  }
  @engine.Or(branches)
}

///|
/// DR-078 §1 result 写像 (issue 2026-07-09-ref-template-result-shape): wrap ONE repeat rep's
/// `head` (a ref element's consumption unit) so its bindings land nested under `name` (the
/// result scope, DESIGN §2.3/§2.4) with a leading "#row" sentinel marking the row boundary
/// (`resolve.mbt`'s `build_result` ROW-GROUP branch groups same-scope bindings into one array
/// element per "#row"). `@engine.Bind`'s 0-token binding rides IN FRONT of `head`'s own bindings within
/// the SAME `@engine.Scoped` wrap, so both land at scope=[name] together in args order — this is safe to
/// apply per-rep (rather than wrapping the whole repeat spine once) because it changes only the
/// CONTENT of one head-consumption, never the spine shape that drives 取り分選好/先食い
/// (`lower_repeat_head` / `ref_choice` / `bounded_tail_step` remain untouched).
fn ref_row_head(name : String, head : @engine.Node) -> @engine.Node {
  @engine.Scoped(
    name,
    @engine.Seq([@engine.Bind("#row", @engine.VBool(false)), head]),
  )
}

///|
/// MDR-004 §3: one `@engine.OrBranch`'s consumption grammar node — a single node for a 1-item branch, a
/// `@engine.Seq` of value primitives (consumed in order) for a multi-item branch. Each item's own `name`
/// carries through `elem_head` unchanged, so held-Error / binding attribution lands on the LEAF
/// (e.g. `a`/`s`/`b`/`r`/`g`/`b`/`name`) with no extra provenance wiring needed (§4).
pub fn or_branch_node(br : @engine.OrBranch) -> @engine.Node {
  if br.items.length() == 1 {
    elem_head(br.items[0])
  } else {
    let nodes : Array[@engine.Node] = []
    for it in br.items {
      nodes.push(elem_head(it))
    }
    @engine.Seq(nodes)
  }
}

///|
/// 有効 repeat spec (DR-043)。`optional:true` は `{min:0,max:1}` の糖衣 (独立概念ではない)。
fn elem_repeat(e : @engine.ElemDef) -> @engine.RepeatSpec? {
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
/// `Opt(X)` = `@engine.Or([X, @engine.Seq([])])`。空 @engine.Seq が 0 トークン一致。
fn opt_node(x : @engine.Node) -> @engine.Node {
  @engine.Or([x, @engine.Seq([])])
}

///|
/// DR-088 §1: 「宣言された値源はデフォルトの存在」— `default_values` (明示 default) だけでなく
/// `env`/`config_key`/`inherit` の宣言も「遅延解決する default_fn が設定されているのと同型」。
/// `eval.mbt`'s `value_declared` (resolve-first-constraint-pipeline / value-present-ladder-gap の
/// 静的宣言述語) と同じ4要素判定を、installer 層 (lowering 時点、@engine.ElemDef ベース) で行う版。
fn has_declared_value_source(e : @engine.ElemDef) -> Bool {
  e.default_values is Some(_) ||
  e.env.length() > 0 ||
  e.config_key is Some(_) ||
  e.is_inherit
}

///|
/// positional face の lowering。repeat 要素 (DR-043) は Ref 再帰: template
/// `name = @engine.Seq([head, Opt(Ref(name))])` を registry に登録し、spine には `min-1` mandatory + Ref
/// (min >= 1 のみ — `Ref` 自体は必ず >= 1 head を消費する構造で「0 でもよい」を表現できない、
/// `consume_head` に「0 なら silent stop」の分岐が無いため)。`min:0` の UNBOUNDED は代わりに
/// `@engine.Many(head)` を直接積む (下記詳細)。bounded (max 有限) は Ref 再帰なしで @engine.BoundedTail に落ちる
/// (LOWERING §B.8、min:0 は budget=max の @engine.BoundedTail が最初から正しく扱う)。dd 要素は spine に
/// 載せない。
///
/// MDR-002 §CPS 規約: repeat はここでスパイン形 (positional の Ref / @engine.BoundedTail / @engine.ScopeNode /
/// **@engine.Many**) にのみ正規化し、@engine.Or/@engine.Seq/@engine.Rooted 内部への埋め込みは生成しない (取り分選好の局所化を避け
/// るため)。`@engine.Many` は `Ref`/`@engine.BoundedTail` と対称な取り分選好 (既定 greedy = 長い方から試す、
/// `lazy:true` で反転 = 短い方から試す、`has_full_k` で pruning) を scope_consume 側に持つ spine 形
/// (eval.mbt の `@engine.Many(inner, lazy_) =>` アーム、"parity with Ref/@engine.BoundedTail 取り分選好 spec
/// DR-043")。輪郭は fixtures/path-search/ambiguous-receptacles.json が固定する。

///|
/// DR-043 repeat lowering for a single positional `head` node, shared by `BCell` (head =
/// `elem_head(e)`) and `BOr` (head = `@engine.Or(branch_node...)`, issue
/// 2026-07-09-positional-or-repeat-lowering-gap: BOr used to push `@engine.Or(nodes)` directly and
/// silently ignore `elem_repeat(e)` entirely — a structural-or head is JUST a head like any other
/// for repeat's purposes, DR-043 §「repeat の対象要素は形を問わない」already says this for `ref`
/// heads, it applies identically to an `@engine.Or` head). When `elem_repeat(e)` is `None` the bare `head`
/// is pushed unchanged — the branches inside an `@engine.Or` head still each read one head via `@engine.Or`'s
/// existing multi-branch semantics (DR-038); `elem_repeat` only ever governs REPETITION count,
/// never branch structure.
fn lower_repeat_head(
  e : @engine.ElemDef,
  head : @engine.Node,
  registry : Map[String, @engine.Node],
  out : Array[@engine.Node],
) -> Unit {
  match elem_repeat(e) {
    None => out.push(head)
    Some(spec) =>
      match spec.max {
        None =>
          if spec.min == 0 {
            // UNBOUNDED min:0 (DR-043): a bare `Ref(e.name)` cannot express "0 is fine" (its
            // arm in scope_consume has no fallback for `consume_head` failing to progress), and
            // wrapping it in a plain `@engine.Or([Ref(name), @engine.Seq([])])` would lose the 取り分選好 (plain
            // `eval()`'s `@engine.Or` arm has no preference — both branches survive whenever they BOTH
            // reach a full parse, producing @engine.Ambiguous instead of the greedy-left-longest single
            // reading DR-043 requires — exactly this fixture's 3 divergences). `@engine.Many(head)` is
            // the existing spine form with the IDENTICAL preference algorithm already wired in
            // scope_consume, so no registry/self-ref is needed at all (each further rep re-enters
            // the SAME `@engine.Many` node at the same `pidx`, not a named template). `spec.lazy_` rides
            // straight into `@engine.Many`'s 2nd field (issue 2026-07-08 min0-lazy-repeat-gap resolved:
            // @engine.BoundedTail's 3rd field is the same seat for the bounded sibling, DR-043 lazy is
            // declarative preference regardless of min/max shape).
            out.push(@engine.Many(head, spec.lazy_))
          } else {
            // UNBOUNDED min>=1 (DR-043): `name#cons = @engine.Seq([head, Opt(Ref(name#cons))])` の porous
            // 自参照。`#cons` サフィックス (DR-046 §4 の自動 id 空間、`#` は user ns 外の既裁定) で
            // mangle する — DR-078 で `definitions.templates` がこの同じ `registry` を共有するように
            // なったため、プレーン `e.name` キーは「repeat 要素と同名のユーザ template」で衝突しうる
            // (spec `fixtures/lowering/repeat/basic.json` の golden も元々この mangled 形
            // `"src#cons"` を期待しており、`canon_tmpl` の緩比較 (先頭 `#` 区切りで正規化) がこれまで
            // 実装側のプレーン名との差を吸収して隠していただけ — 本 mangle で golden と実体が一致する)。
            let cons = e.name + "#cons"
            registry.set(cons, @engine.Seq([head, opt_node(Ref(cons))]))
            if spec.lazy_ {
              // lazy marker (evaluator が split 選好を引くための mangled key)
              registry.set("lazy:" + cons, @engine.Exact("lazy"))
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
          // BOUNDED (LOWERING §B.8): min mandatory heads + @engine.BoundedTail(head, max-min)
          let m = if spec.min < 0 { 0 } else { spec.min }
          let mut k = 0
          while k < m {
            out.push(head)
            k = k + 1
          }
          let budget = if mx - m < 0 { 0 } else { mx - m }
          out.push(@engine.BoundedTail(head, budget, spec.lazy_))
        }
      }
  }
}

///|
fn lower_positional(
  def : @engine.Definition,
  registry : Map[String, @engine.Node],
) -> Array[@engine.Node] {
  let out : Array[@engine.Node] = []
  for e in def.positionals {
    if not_dd(e) {
      match e.body {
        BOr(branches) => {
          // MDR-004 §3 "BOr (positional, 匿名)": spine に @engine.Or([branch_node...]) を直接積む。評価器の
          // 既存 @engine.Or 意味論 (全枝評価 + @engine.Held 全保持、DR-053 §2 / 完全経路 2 本以上で ambiguous 保存、
          // DR-038) がそのまま輪郭を満たす。DR-043 repeat との組合せ (issue
          // 2026-07-09-positional-or-repeat-lowering-gap で根治): `@engine.Or(nodes)` を head として
          // `lower_repeat_head` に渡す — repeat のレンズには「構造 or の 1 発火」も他の head と
          // 同じ 1 unit で、Ref/@engine.Many/@engine.BoundedTail のどれになるかは head の形 (@engine.Or か string resident か) に
          // 依存しない。
          let nodes : Array[@engine.Node] = []
          for br in branches {
            nodes.push(or_branch_node(br))
          }
          lower_repeat_head(e, @engine.Or(nodes), registry, out)
        }
        BGroup(items) => {
          // MDR-004 §3 "BGroup + repeat": @engine.IdxRepeat(label=name, head=@engine.Seq(inner cells), min,
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
          // 保証は @engine.IdxRepeat には及ばない。budget が Some (bounded) のときは over-consume 自体が
          // 起きないためこの GAP を踏まない。UNBOUNDED のまま末尾に必須 positional を続ける設計を
          // 書く際は head の先頭に明示的な trigger (@engine.Exact 等) を持たせること。
          let head = if items.length() == 1 {
            elem_head(items[0])
          } else {
            let nodes : Array[@engine.Node] = []
            for it in items {
              nodes.push(elem_head(it))
            }
            @engine.Seq(nodes)
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
          out.push(@engine.IdxRepeat(e.name, head, min, budget))
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
                None => out.push(@engine.Scoped(e.name, elem_head(e)))
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
              // `opt_node` (`@engine.Or([head, @engine.Seq([])])`, already used by `elem_repeat`'s min:0 paths)
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
/// (cloned) @engine.Definition tree から scope-builder tree を組む。positional は 1 度だけ lower (以後は成長
/// しない — global copy は greedy 側に入る)。entities / greedy は fixpoint pass で埋める。
fn init_sb(
  def : @engine.Definition,
  registry : Map[String, @engine.Node],
) -> @engine.InstallBuilder {
  let positional = lower_positional(def, registry)
  let children : Array[@engine.InstallChild] = []
  for c in def.commands {
    children.push(@engine.InstallChild::new(c.name, init_sb(c.body, registry)))
  }
  @engine.InstallBuilder::new(
    def,
    @engine.InstallBuild::new(positional),
    children,
    registry,
  )
}

///|
/// Core lowering (installer ではない — 決定的、順序無依存): option/positional ごとに entity 1 個を
/// name 割当で ensure (add-if-absent)。毎 pass 走る (global-copied option も entity を得るため)。
///
/// dd 要素は entity を持たない (LOWERING §B.4「値なし」/ DR-064 §1)。link_depth == 0 のみ ensure
/// (global link COPY は declaring cell へ link 同期するため子 scope 側 entity は不要 — DR-070 §1b gap 5)。
fn ensure_entities(sb : @engine.InstallBuilder, has_cf : Bool) -> Unit {
  for e in sb.definition().options {
    if not_dd(e) && e.link_depth == 0 {
      ensure_entity_body(sb.output(), e, has_cf)
    }
  }
  for e in sb.definition().positionals {
    if not_dd(e) {
      ensure_entity_body(sb.output(), e, has_cf)
    }
  }
}

///|
/// MDR-004 §3b: register `e` (and any `@engine.ElemBody`-nested leaves) as top-level entities — the
/// evaluator's `@engine.Or`/`@engine.Seq`/`@engine.IdxRepeat` nodes don't know about entities at all, so this recursive
/// walk is the ONLY registration point. `BOr`'s wrapper is a structural dispatcher with no
/// scalar/array value of its own (e.g. "color" never itself holds a value — only its branch leaves
/// r/g/b/name do), so ONLY the branch leaves register. `BGroup`'s wrapper DOES need its own entity
/// (the array cell — `elem_repeat` on it still drives the existing "flatten" accumulator path,
/// unaffected by `body`) in ADDITION to its inner leaves (e.g. transparent-seq's `k`, its own cell
/// with `entity=k` effects).
///
/// codex レビュー Major 4 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見): the
/// `is_exact` guard used to live ONLY at `ensure_entities`' top-level positionals loop (removed
/// above) — a `BOr`/`BGroup` RECURSIVE call into this same function (branch leaves / group inner
/// items, both below) bypassed it entirely, so an `is_exact` leaf nested inside a structural or /
/// named group would fall into the `BCell`/`ref_target is None` arm and get a phantom
/// `@engine.Entity{name: spelling, ty: none_type()}` — occupying the namespace and blocking a real same-named
/// entity's `ensure_entity` (add-if-absent already returns early once ANY entity with that name
/// exists). Guarding HERE (single entry point every recursive path funnels through) closes both the
/// top-level and the nested cases with one check, and any future `@engine.ElemBody` arm added to this match
/// inherits the guard automatically (installer.mbt's `@engine.ElemDef.is_exact` doc comment: "value_prim/
/// entity 経路を一切通らない" is the invariant this enforces).
fn ensure_entity_body(
  build : @engine.InstallBuild,
  e : @engine.ElemDef,
  has_cf : Bool,
) -> Unit {
  if e.is_exact {
    return
  }
  match e.body {
    BCell =>
      // DR-078 §1 result 写像 (issue 2026-07-09-ref-template-result-shape): a `ref` element is
      // ALSO a structural dispatcher with no scalar/array value of its own — its "value" is a
      // name-scoped projection of the REFERENCED template's own leaves (installer.mbt's
      // `ref_row_head` / `lower_positional`/`inst_long`'s `@engine.Scoped` wrap), never a flat binding on
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
      // The wrapper (e.g. "xs") lowers to @engine.IdxRepeat (MDR-004 §3): its array is built entirely by
      // eval.mbt's array_marker/nest_index scope mechanism, never via the accum-entity ladder. If
      // registered here, ensure_entity would set accum:flatten (elem_repeat(e) is Some for a
      // repeat group), making accum_cells double-count "xs" and inject a spurious extra `[]`
      // alongside the nested-scope array resolve.mbt already builds from the @engine.IdxRepeat bindings.
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
fn ensure_entity(
  build : @engine.InstallBuild,
  e : @engine.ElemDef,
  has_cf : Bool,
) -> Unit {
  for ent in build.entities() {
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
  // Preset defaults are resident-owned: flag supplies false and count supplies 0 only
  // when no explicit default exists. Ordinary bool/number residents remain absent.
  // DR-083 keeps every scalar default in the uniform length-1 array representation.
  // DR-099 §2: is_tty 要素は bool_type() の暗黙 default:false プリセットを受けない — 素の bool と違い、
  // is_tty 要素の default 席は `resolve.mbt`'s `resolve_ladder_below_cli` が `fold(観測) ?? 宣言
  // default ?? absent` という独自規則で解決する。ここで先回りに false を注入してしまうと「宣言
  // default 無し」という状態が失われ、fold が観測なしの場合に absent へ落ちる余地が無くなる
  // (常に false が浮かび上がってしまう) — is_tty 要素は default_values を宣言されたとおり (無指定
  // なら None) に持ち回り、fold の側で吸収させる。
  let default_values : Array[@engine.Value]? = match e.default_values {
    Some(vs) => Some(vs)
    None =>
      if e.is_tty {
        None
      } else {
        match e.ty.default_seat_resolver(@engine.seat_ctx(None)) {
          Some(value) => Some([value])
          None => None
        }
      }
  }
  let ty2 = if e.ty.name() == "count" { number_type() } else { e.ty }
  build
  .entities()
  .push({
    name: e.name,
    ty: ty2,
    env_key: None,
    config_seat,
    config_key: e.config_key,
    is_config_file: e.is_config_file,
    inherit_: false, // MDR-003: node.mbt 側 @engine.Entity.inherit_
    // DR-099 §1: is_tty/tty_stream/tty_cygwin は @engine.ElemDef からそのまま carry するだけ (int_round と
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
    // DR-036: collector only means anything alongside an accum cell (@engine.Entity.collector's doc
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
fn not_dd(e : @engine.ElemDef) -> Bool {
  !e.is_dd
}

// ── 各 installer ─────────────────────────────────────────────────────────────

///|
/// DR-091 §3: `eq_split` bundles every eq-split entry it carries under ONE `prefix` (`node.mbt`'s
/// `eq_split(prefix~, entries~)` — a single matcher instance, single prefix). Before this DR every
/// element shared the hardcoded `"--"`, so one `eq_split` per `@engine.Definition` was correct; now an
/// element MAY declare its own `long_prefix` (`if=`/`of=`'s `long_prefix: ""`), so `inst_long`
/// groups eq entries by their declaring element's `long_prefix` and emits one `eq_split` per
/// distinct value actually present — `prefixes`/`groups` are parallel arrays (insertion order),
/// mirroring this file's existing dedup-by-linear-scan style (`resolve.mbt`'s `named`/`segs`
/// arrays) rather than a `Map` (whose iteration order this codebase doesn't otherwise rely on).
fn eq_group(
  prefixes : Array[String],
  groups : Array[Array[EqEntry]],
  prefix : String,
) -> Array[EqEntry] {
  let mut i = 0
  while i < prefixes.length() {
    if prefixes[i] == prefix {
      return groups[i]
    }
    i = i + 1
  }
  let g : Array[EqEntry] = []
  prefixes.push(prefix)
  groups.push(g)
  g
}

///|
/// codex レビュー Major 2 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見) / DR-058
/// §2: append a trailing deprecation resident to a main-entry satellite's node array when `e.deprecated`
/// — shared by EVERY `inst_long` main-entry arm (BOr / BEnum / ref±repeat / BCell, all below) so a
/// deprecated element warns regardless of its value structure (DR-058 §2's contract is 値構造非依存;
/// the previous fix only wired the BCell arm, missing the other 4). Centralizing the append here (one
/// call site per arm, right before `@engine.Seq(...)`) means a FUTURE `e.body`/`ref_target` arm added to
/// `inst_long` inherits the warning automatically as long as it routes its satellite nodes through
/// this helper — the same "single funnel, no per-arm opt-in to forget" shape `ensure_entity_body`'s
/// `is_exact` guard (Major 4 fix) uses.
fn with_depr(
  e : @engine.ElemDef,
  nodes : Array[@engine.Node],
) -> Array[@engine.Node] {
  if e.deprecated {
    nodes.push(deprecation_mark(e.name))
  }
  nodes
}

///|
/// long: `long` を READ、name あたり greedy exact 衛星 (space form) と、value 系なら eq-split matcher
/// を add-if-absent で追加。衛星は name で entity に link (DR-042 §展開の標準パターン)。
fn inst_long(
  def : @engine.Definition,
  build : @engine.InstallBuild,
  registry : Map[String, @engine.Node],
) -> Unit {
  let eq_prefixes : Array[String] = []
  let eq_groups : Array[Array[EqEntry]] = []
  for e in def.options {
    for l in long_of(e) {
      // DR-091 §3: `e.long_prefix` replaces the old hardcoded `"--"` (既定値は `"--"` そのものなので
      // this element's own trigger is unchanged unless it explicitly overrides).
      let trigger = e.long_prefix + l
      match e.body {
        // MDR-004 §3: BOr option (variable-arity) — greedy satellite
        // @engine.Seq([@engine.Exact(trigger), @engine.Or([branch_node...])]). `e.ty` is unused (a BOr wrapper carries no
        // value of its own); each branch's own leaf name(s) flow through unchanged via
        // or_branch_node/elem_head, so held-Error / binding attribution lands on the leaf with no
        // extra provenance wiring (§4).
        BOr(branches) => {
          let branch_nodes : Array[@engine.Node] = []
          for br in branches {
            branch_nodes.push(or_branch_node(br))
          }
          add_greedy(
            build,
            maybe_root(
              e.link_depth,
              @engine.Seq(
                with_depr(e, [@engine.Exact(trigger), @engine.Or(branch_nodes)]),
              ),
            ),
          )
        }
        // BEnum (issue values-decode-support, DESIGN §5.3 / DR-028 追記): main entry の値スロット
        // 消費構造が `enum_value_node` (exact 値の or 展開) になる — BCell の `value_prim` に相当する
        // 差し替え。DR-086 §1 の cut (同一 trigger の 0引数 @engine.Set variant との競合解決) は lowering
        // 構造 (ここで積む greedy 衛星の個数・形) を変えず eval.mbt 側で扱う (lowering query fixture
        // への影響回避、team-lead 裁定 2026-07-10) — ここでは通常の main entry と同じ形で単独登録
        // するだけでよい。
        BEnum(values) =>
          add_greedy(
            build,
            maybe_root(
              e.link_depth,
              @engine.Seq(
                with_depr(e, [
                  @engine.Exact(trigger),
                  enum_value_node(e.name, e.ty, values),
                ]),
              ),
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
                      @engine.Seq(
                        with_depr(e, [
                          @engine.Exact(trigger),
                          // DR-084 §1 (issue multiple-ref-accum-gap): a `multiple` repeat-less ref
                          // element's row is the ACCUMULATOR's fold unit (one fire = one row) —
                          // tag it with "#row" (`ref_row_head`, same sentinel repeat-bearing ref
                          // uses) so `resolve.mbt`'s ROW-GROUP branch splits each firing into its
                          // own row-group instead of merging every firing's leaves flat into one
                          // object (the pre-DR-084 bug: 2 fires of an or-branch ref would land BOTH
                          // branches' leaves under the same bare `@engine.Scoped(e.name, ...)`, e.g.
                          // `{colorname:"red", r:0, g:128, b:255}` instead of 2 separate rows). No
                          // `multiple` (the `ref-template-no-repeat-degenerate.json` baseline) keeps
                          // the bare `@engine.Scoped` wrap — a single scalar row, never array-wrapped.
                          if e.multiple {
                            ref_row_head(e.name, elem_head(e))
                          } else {
                            @engine.Scoped(e.name, elem_head(e))
                          },
                        ]),
                      ),
                    ),
                  )
                Some(_) => {
                  // The repeat spine (mandatory heads + Ref/@engine.BoundedTail/@engine.Many tail) collapses to
                  // ONE node for `min <= 1` (no mandatory-head unrolling) — the only shape any
                  // fixture exercises today (`last-wins-repeat-rows.json`'s `{"min":1}`). A
                  // `min > 1` option repeat would need `@engine.GreedyRepeat` to carry multiple
                  // `sc'.positional` slots (eval.mbt's `step_greedy_repeat`), not yet wired.
                  let spine : Array[@engine.Node] = []
                  lower_repeat_head(
                    e,
                    ref_row_head(e.name, elem_head(e)),
                    registry,
                    spine,
                  )
                  let tail = if spine.length() == 1 {
                    spine[0]
                  } else {
                    @engine.Seq(spine)
                  }
                  add_greedy(
                    build,
                    maybe_root(
                      e.link_depth,
                      @engine.Seq(
                        with_depr(e, [
                          @engine.Exact(trigger),
                          // DR-034 last-wins-whole-cell (multiple 無しの再発火はセル丸ごと上書き):
                          // "#fire" marks this firing's start so `resolve.mbt`'s ROW-GROUP branch
                          // can discard every EARLIER firing's rows wholesale rather than merging
                          // leaf-by-leaf (which would wrongly keep a superseded rep whose position
                          // the later, shorter firing never touched).
                          @engine.Scoped(
                            e.name,
                            @engine.Bind("#fire", @engine.VBool(false)),
                          ),
                          @engine.GreedyRepeat(tail),
                        ]),
                      ),
                    ),
                  )
                }
              }
            None =>
              // DR-076 §1/§2/§4: every value-typed main entry (bool included, flag ALREADY
              // normalized to bool_type() by `normalize_option`, DR-076 §2) is a NORMAL value satellite
              // — `:set` always takes a value (space form here; eq form via eq_entries below). A
              // bare `--x` fire (the classic flag shape) needs the explicit `:set:true` variant
              // (decoded as a @engine.Set-op @engine.Variant with operand @engine.VBool(true), lowered by the "@engine.Variant
              // entries" loop below, which also carries the fail_action failure resident — flag's
              // presence-only lowering has fully collapsed into that generic variant path; this
              // arm no longer special-cases flag_type()/bool_type() bare-true at all).
              //
              // DESIGN §7.2 / DR-096 §1: `long_eq_sep == @engine.EsRequire` withholds THIS space-form main
              // entry — the only entry point left is the eq-split form registered below (`eq_group`
              // push). Paired with `long_prefix: ""` (DR-096 §3.3, node.mbt's `@engine.ElemDef.long_prefix`
              // doc comment), this is the mechanism an app can opt into to definitionally eliminate
              // the bare-operand collision: with no space-form trigger, `trigger` (== `l` when
              // `long_prefix` is `""`) never matches a bare token — only `eq_split`, which fires
              // exclusively on tokens containing `=`, can reach this element. Neither `long_prefix`
              // nor `long_eq_sep` requires this pairing — an unpaired empty prefix is legal and any
              // resulting collision surfaces as @engine.Ambiguous instead.
              if e.long_eq_sep != @engine.EsRequire {
                // DR-058 §2: a deprecated element's space-form main entry carries a `deprecation resident`
                // warning marker after its value slot (node.mbt's `deprecation resident` doc shape), mirroring
                // `inst_short`'s `depr: e.deprecated` on the SAME element (`e.deprecated` covers
                // both a directly-deprecated canonical entry and a deprecated alias entry-copy,
                // DR-057 §3 `alias_entry` — both fold into this ONE `@engine.ElemDef.deprecated` bool by
                // the time lowering runs, so no alias-specific branch is needed here). Routed
                // through `with_depr` (codex レビュー Major 2) so this arm shares the SAME funnel
                // as BOr/BEnum/ref±repeat above.
                add_greedy(
                  build,
                  maybe_root(
                    e.link_depth,
                    @engine.Seq(
                      with_depr(e, [
                        @engine.Exact(trigger),
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
                      ]),
                    ),
                  ),
                )
              }
          }
      }
      // eq-split value form (`--key=value`): every value-typed main entry gets this (bool included,
      // DR-076 §1) — a flag's default sugar carries NO main entry at all (`e.long` stays [], DR-076
      // §2), so this loop never runs for a bare classic flag; an explicit `long:[":set"]` flag DOES
      // register its value-slot form here, coexisting with the bare `:set:true` variant (DR-076 §2
      // "value形+裸の同居"). DR-076 §3: bool_type()'s variant-guard exclusion (eq-split withheld when the
      // element ALSO carries `--x`/`--no-x` variant spellings) is REPEALED — bool's eq-split and
      // variant triggers coexist (fixtures/lowering/long/variant.json's ssl: `--ssl=false` fires
      // alongside `--ssl`/`--no-ssl`).
      // DR-075 §2: int_type() の eq-split (`--v=2.5`) が factory config int_round を反映するよう、
      // @engine.ElemDef.int_round を EqEntry に持ち込む (int_type() 以外は entry 側で参照されない)。
      // MDR-004 §3: a BOr element's eq-split registers only for a single-value-cell branch (using
      // that leaf's own name/ty/int_round/allow_base_prefix, never the wrapper's) — a multi-cell
      // branch's `=` form is undefined (`--color=v` cannot supply 3 leaves).
      // DR-091 §2: a `kv_map`-accumulator leaf does NOT register an eq-split entry (unlike merge,
      // which shares the same `sep_binds` pipeline as the space form) — `run_eq_split` (builtins/matcher_residents.mbt)
      // builds its binding through `sep_binds`, which has no "the piece must contain `=`" gate (that
      // gate lives in the `kv resident` node, `value_prim`'s dedicated kv_map branch, which `EqEntry`
      // never routes through). Registering here would let `--define=NOEQUALSIGN` silently produce
      // `{NOEQUALSIGN: ""}` instead of DR-091 §2's required Reject — same deliberate-absence posture
      // as `BEnum`'s "OUT OF SCOPE" comment below, not an oversight.
      //
      // DR-014「--name=value の許可」/ DESIGN §7.2 / DR-096 §1: `e.long_eq_sep` (scope config,
      // decode-time baked — always the WRAPPING option's resolved value, never a BOr leaf's unbaked
      // default, same reasoning `eq_group(..., e.long_prefix)` already applies below) gates every
      // arm — `@engine.EsDeny` withholds the eq-split entry entirely, leaving only the space form registered
      // above.
      match e.body {
        BOr(branches) =>
          for br in branches {
            if br.items.length() == 1 {
              let leaf = br.items[0]
              if e.long_eq_sep != @engine.EsDeny &&
                leaf.accumulator != Some("kv_map") {
                eq_group(eq_prefixes, eq_groups, e.long_prefix).push(
                  eq_entry(
                    l,
                    leaf.name,
                    configured_type(
                      leaf.ty,
                      leaf.int_round,
                      leaf.allow_base_prefix,
                      leaf.bool_config,
                    ),
                    leaf.piece_filters,
                    leaf.separator,
                    merge=leaf.accumulator == Some("merge"),
                    depr=leaf.deprecated,
                  ),
                )
              }
            }
          }
        BGroup(_) => () // positional-only shape (MDR-004 §3 scope) — no long spelling applies
        BCell =>
          // DR-076 §2: no `e.ty.name() != "flag"` guard needed here anymore — a classic flag never reaches
          // this loop body at all (its `e.long` is empty, `long_of(e)` yields no `l` to iterate), so
          // the guard was always vacuous for it; an explicit `long:[":set"]` flag (now bool_type()) SHOULD
          // register its eq-split form, which this unconditional push now does correctly (the guard
          // used to wrongly suppress it while `e.ty` still read flag_type() pre-normalize_option).
          if e.long_eq_sep != @engine.EsDeny && e.accumulator != Some("kv_map") {
            eq_group(eq_prefixes, eq_groups, e.long_prefix).push(
              eq_entry(
                l,
                e.name,
                configured_type(
                  e.ty,
                  e.int_round,
                  e.allow_base_prefix,
                  e.bool_config,
                ),
                e.piece_filters,
                e.separator,
                merge=e.accumulator == Some("merge"),
                depr=e.deprecated,
              ),
            )
          }
        // BEnum (issue values-decode-support): eq-split (`--color=always`) for an enum-constrained
        // cell is OUT OF SCOPE for this issue (no target fixture exercises `--key=value` against a
        // `values`/`or` value-enum element) — the EqEntry type resident has no
        // enum-value set. Registering nothing avoids accepting an unvalidated value.
        BEnum(_) => ()
      }
    }
  }
  // DR-091 §3: emit one `eq_split` matcher PER DISTINCT `long_prefix` seen (was: a single
  // `eq_split(prefix="--", ...)` for the whole @engine.Definition — `eq_group`'s doc comment).
  let mut gi = 0
  while gi < eq_prefixes.length() {
    if eq_groups[gi].length() > 0 {
      add_greedy(
        build,
        @engine.NativeMatch(eq_split(eq_prefixes[gi], eq_groups[gi])),
      )
    }
    gi = gi + 1
  }
  // @engine.Variant entries (DR-011 / DR-045): `{exact, link (by name), effect}` に lowering。
  // `set` variant は @engine.Bind (SET degenerate); default/unset/empty は effect resident (0-token effect)。
  // DR-076 §2/§4: a flag's classic bare-fire trigger IS a @engine.Set variant now (`:set:true`, composed in
  // by dec_long) — it rides through here, not through the old flag_type()-only branch above. A fail_action
  // element (DR-048, e.g. help) additionally emits a failure resident alongside its @engine.Set variant's @engine.Bind, so
  // this loop must carry the SAME fail_action attachment the collapsed flag_type() branch used to (a
  // fail_action flag firing here — its ONLY main-entry shape post-DR-076 §2 — must still be able to
  // select as a failed-parse action).
  for e in def.options {
    for v in e.variants {
      // issue scope-config-object-gap codex 指摘 Major 2: main entry (inst_long 冒頭) と eq-split
      // (eq_group) は既に e.long_prefix を使う — variant だけ "--" 固定だと同一 option family の
      // 綴りが long_prefix 非既定時に分裂する (DR-091 §3 の一貫性を variant にも及ぼす)。既定
      // "--" なので既存挙動 (main entry と揃った "--" 綴り) は不変。
      let trigger = e.long_prefix + v.trigger
      // DR-058 §2: a deprecated element's variant satellite (@engine.Set's @engine.Bind OR a non-@engine.Set effect resident) also
      // carries a trailing `deprecation resident` — every long entry point this element owns fires the SAME
      // warning, symmetric with `inst_short`'s per-char `depr: e.deprecated` (a short cluster char
      // has no variant/main-entry split, so ONE application point covers it; long's split into
      // main-entry (above) + variant (here) needs both covered for parity).
      let nodes : Array[@engine.Node] = match v.op {
        @engine.Set => {
          let operand = match v.operand {
            Some(val) => val
            None => @engine.VBool(true)
          }
          if e.fail_action {
            [
              @engine.Exact(trigger),
              @engine.Bind(e.name, operand),
              failure_mark(e.name),
            ]
          } else {
            [@engine.Exact(trigger), @engine.Bind(e.name, operand)]
          }
        }
        _ => [@engine.Exact(trigger), effect_mark(e.name, v.op)]
      }
      add_greedy(
        build,
        maybe_root(e.link_depth, @engine.Seq(with_depr(e, nodes))),
      )
    }
  }
}

///|
/// global link COPY (link_depth > 0) を `@engine.Rooted(node, depth)` で包む — bindings が declaring scope の
/// entity に landing するよう escape する (DR-042 link-sync)。link_depth == 0 は自宣言で wrap しない。
fn maybe_root(link_depth : Int, node : @engine.Node) -> @engine.Node {
  if link_depth > 0 {
    @engine.Rooted(node, link_depth)
  } else {
    node
  }
}

///|
/// DESIGN §7.2 / LOWERING §B.2: mirrors `eq_group` (long installer, DR-091 §3) — bundles every
/// short-cluster entry under ONE `(short_prefix, short_combine)` PAIR per `short_combine` matcher
/// instance. Keying on the pair (not `short_prefix` alone) matters because a `@engine.Definition`'s
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
/// DESIGN §7.2: `e.short_prefix` replaces the old hardcoded `"-"` — one `short_combine` matcher PER
/// DISTINCT `(short_prefix, short_combine)` pair actually present (was: a single
/// `short_combine(prefix="-", ...)` for the whole `@engine.Definition`), same generalization DR-091 §3
/// already applied to `inst_long`/`eq_split`. `e.short_combine` (issue scope-config-object-gap
/// 解釈A, team-lead 裁定 2026-07-11) rides straight through to the matcher's `combine` param —
/// `run_short`/`walk_short` (builtins/matcher_residents.mbt) are the sole consumers of the flag's actual meaning.
fn inst_short(def : @engine.Definition, build : @engine.InstallBuild) -> Unit {
  let sh_prefixes : Array[String] = []
  let sh_combines : Array[Bool] = []
  let sh_groups : Array[Array[ShortEntry]] = []
  for e in def.options {
    for c in e.short {
      // DR-058: deprecated alias entry-copy は cluster entry でも警告する
      // DR-075 §2: short cluster / space-tail 経路の int_type() (`-n1.5` / `-n 1.5`) も factory config を反映
      short_group(
        sh_prefixes,
        sh_combines,
        sh_groups,
        e.short_prefix,
        e.short_combine,
      ).push(
        short_entry(
          c,
          e.name,
          configured_short_type(
            e.ty,
            e.int_round,
            e.allow_base_prefix,
            e.bool_config,
          ),
          e.piece_filters,
          e.separator,
          depr=e.deprecated,
          merge=e.accumulator == Some("merge"),
          short_attached_value=e.short_attached_value,
          is_alias=e.is_alias,
        ),
      )
    }
  }
  let mut gi = 0
  while gi < sh_prefixes.length() {
    if sh_groups[gi].length() > 0 {
      add_greedy(
        build,
        @engine.NativeMatch(
          short_combine(sh_prefixes[gi], sh_groups[gi], sh_combines[gi]),
        ),
      )
    }
    gi = gi + 1
  }
}

///|
/// env: `env` を READ、entity の env seat に登録 (invariant ④)。ladder 順序は engine 所有 (DR-031)、
/// default_fn を wrap しない。同 seat 再宣言は no-op (idempotent in-place set)。
fn inst_env(def : @engine.Definition, build : @engine.InstallBuild) -> Unit {
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
fn seat_env(build : @engine.InstallBuild, name : String, key : String) -> Unit {
  for ent in build.entities() {
    if ent.name == name {
      ent.env_key = Some(key)
    }
  }
}

///|
/// dd: `type:"dd"` を READ、greedy exact 衛星 (@engine.DdSat) を add-if-absent (DR-041 rev)。fire 時に spine
/// walk が「severed」モードに切り替わり以降 greedy off — greedy internal consumption 一体化ルール。
///
/// DR-064 §2 配置不問回収: dd は canonical には options[] だが positionals[] に置いても回収する
/// (env / inherit と同じく両 face を walk する対称形)。add-if-absent (add_greedy) が重複宣言を collapse。
fn inst_dd(def : @engine.Definition, build : @engine.InstallBuild) -> Unit {
  // DR-064 §5: dd の name は trigger 綴りに効く (normalize_surface が既定 "--" を供給、明示は上書き)。
  // DR-090 §2: `dd_match` が None かつ `dd_self_keep` が false (両軸とも既定) の要素だけ、既存
  // `@engine.DdSat` (exact/drop 専用ノード) をそのまま使う — 完全な後方互換 (既存 wbtest の `@engine.DdSat("--")`
  // 手組みと構造一致し続ける)。どちらかの軸が既定から外れたら一般化ノード `@engine.DdMatchSat` を積む
  // (`match` が Some のとき name はトリガ綴りに使われない、§2 の規定通り `e.name` の代わりに
  // `dd_match` の pattern を spelling に使う)。
  fn dd_node(e : @engine.ElemDef) -> @engine.Node {
    if e.dd_match is None && !e.dd_self_keep {
      @engine.DdSat(e.name)
    } else {
      match e.dd_match {
        Some(pattern) =>
          @engine.DdMatchSat(pattern, true, e.dd_self_keep, e.name)
        None => @engine.DdMatchSat(e.name, false, e.dd_self_keep, e.name)
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
fn add_greedy(build : @engine.InstallBuild, g : @engine.Node) -> Unit {
  for existing in build.greedy() {
    if existing == g {
      return
    }
  }
  build.greedy().push(g)
}

///|
/// inherit: `inherit` を READ、entity に inherit seat を宣言 (invariant ④, DR-031 cli>env>inherit>default)。
/// seat の実 lookup 「最近祖先の同名 entity 値」は runtime (resolve_scope) で解く。env と対称の seat 宣言型。
fn inst_inherit(def : @engine.Definition, build : @engine.InstallBuild) -> Unit {
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
fn seat_inherit(build : @engine.InstallBuild, name : String) -> Unit {
  for ent in build.entities() {
    if ent.name == name {
      ent.inherit_ = true // MDR-003
    }
  }
}

///|
/// global: `global` を READ、option 宣言を子孫 command scope の宣言層にコピー (invariant ②)。
/// long/short は次 pass 以降で子で展開する。shadowing (DR-032/033, 最小 scope): 子が同トリガを既に
/// 宣言していれば copy しない (自前が勝つ)。copy は `is_global` を保持し、fixpoint で更に下位へ再伝播。
fn inst_global(sb : @engine.InstallBuilder) -> Unit {
  for opt in sb.definition().options {
    if opt.is_global {
      for child in sb.children() {
        copy_global_into(child.body(), opt)
      }
    }
  }
}

///|
fn copy_global_into(
  child : @engine.InstallBuilder,
  opt : @engine.ElemDef,
) -> Unit {
  for existing in child.definition().options {
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
    // の @engine.Scope 構造 (@engine.Rooted 衛星の本数) を直接検査する wbtest で確認した)。トリガ集合が両方とも
    // 空集合の場合は「集合一致」も自明に成立するので、元の trigger-less canonical バグの修正は
    // このまま維持される。
    if existing.name == opt.name &&
      existing.link_depth > 0 &&
      trigger_sets_equal(existing, opt) {
      return
    }
  }
  // copy は link 衛星 (DR-042): declaring scope の entity を bind (子は自 cell を持たない)。
  // link_depth = declaring scope からの段数 (+1 per re-propagation)。long/short が @engine.Rooted(node, depth)
  // で wrap する。
  //
  // INVARIANT (install-time count ↔ eval-time decrement, 現制約): この +1 は SCOPE (name/command) copy
  // level のみ数える (copy_global_into 1 段につき 1)。eval 側の @engine.Rooted `link` counter は 2 種の nesting
  // (nest = scope 段 / nest_index = rep #k 段) で減算される。したがって「link_depth == 衛星と declaring
  // scope の間の eval nesting 段数」の不変条件は「@engine.Rooted 衛星が @engine.IdxRepeat の下に置かれない」条件下でのみ
  // 成立する — 現行 lowering は @engine.Rooted を scope spine で wrap し、repeat head 内には入れないので満たす。
  // 将来 nested-group が scope/global を repeat 群に許容するなら、この +1 に rep-nesting depth も加算する。
  let copy = clone_elem(opt)
  child.definition().options.push({
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
fn all_long_triggers(e : @engine.ElemDef) -> Array[String] {
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
fn trigger_sets_equal(a : @engine.ElemDef, b : @engine.ElemDef) -> Bool {
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
fn triggers_overlap(a : @engine.ElemDef, b : @engine.ElemDef) -> Bool {
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
/// inheritable installer (DR-059): global の REVERSE 方向。子孫の inheritable 要素を全祖先 scope に
/// `<定義スコープ名>-<name>` 綴りでコピー (§1)。祖先の `--socket-ttl` が祖先 `ttl` cell に bind。
/// 全 `ttl` cell (定義 + 祖先コピー) に inherit seat が立つので、任意層の値が子孫の default として流れ下る
/// (§3 値意味論 — inherit seat の対 DR-031)。祖先が同トリガを自宣言なら shadow で copy しない (global 対称)。
fn inst_inheritable(sb : @engine.InstallBuilder) -> Unit {
  // (1) 子孫の inheritable → THIS (祖先) scope の宣言層に prefixed write-entry を追加
  let entries : Array[(String, @engine.ElemDef)] = []
  gather_inheritable(sb.children(), entries)
  for de in entries {
    let defining_name = de.0
    let e = de.1
    let trigger = defining_name + "-" + e.name // 全祖先同綴り (§1)
    add_inheritable_copy(sb, e, trigger)
  }
  // (2) subtree の inheritable 対象名 (自宣言 + 祖先コピー) 全てに inherit seat を打つ (§3)
  let names : Array[String] = []
  for e in sb.definition().options {
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
    seat_inherit(sb.output(), name)
  }
}

///|
/// 子孫 scope の inheritable 要素を全て回収 (定義スコープ名で tag — §1 の prefix)。全 subtree を再帰。
fn gather_inheritable(
  children : Array[@engine.InstallChild],
  out : Array[(String, @engine.ElemDef)],
) -> Unit {
  for ch in children {
    for e in ch.body().definition().options {
      if e.is_inheritable {
        out.push((ch.name(), e))
      }
    }
    gather_inheritable(ch.body().children(), out)
  }
}

///|
/// 祖先 scope の宣言層に prefixed write-entry を追加 (add-if-absent, shadow-aware)。祖先が同トリガを
/// 既に宣言 (§3 global 対称 shadow) なら copy しない。DR-076 後は裸発火トリガが `variants` 側に入る
/// (例: alias `[":set:true"]` 由来) ため、`long_of` (main long のみ) ではなく `all_long_triggers`
/// (long + variants 横断) で判定する必要がある — codex 指摘、実機確認済み regression: alias が
/// variants 側で提供するトリガを `long_of` だけでは見落とし、同じ綴りの inheritable コピーを重複
/// 追加してしまう (materialize 後の @engine.Scope に同一トリガの greedy 衛星が 2 本立つ)。
fn add_inheritable_copy(
  sb : @engine.InstallBuilder,
  e : @engine.ElemDef,
  trigger : String,
) -> Unit {
  for existing in sb.definition().options {
    if str_in(all_long_triggers(existing), trigger) {
      return // 自前優先 (shadow) / 既 copy (idempotent)
    }
  }
  sb.definition().options.push({
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
      export_key: @engine.export_key_unset(),
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
      int_round: @engine.RError,
      allow_base_prefix: false, // canonical default (DR-075 §2): write-target は int_round を持たない
      // canonical default (DR-074 §2): write-target は base prefix opt-in を持たない
      bool_config: bool_config_canonical(), // canonical default (DR-074 §4): write-target は bool_parser opt-in を持たない
      piece_filters: [], // write-target は filter chain を持たない (源 e の value_filters は source 側で既に適用済み)
      value_filters: [],
      final_filters: [],
      accum_filters: [],
      long_prefix: "--", // 通常の long 綴り (kebab, 未 prefix) — inst_long が既定 "--" を前置する
      short_prefix: "-", // write-target copy は short spelling を持たない (canonical default 相当)
      env_prefix: "", // write-target copy は env 席を持たない (canonical default 相当)
      auto_env: false,
      long_eq_sep: @engine.EsAllow,
      short_combine: true,
      short_attached_value: @engine.AtAllow,
      body: BCell,
    }, // canonical default (§3 と同じ「通常挙動」)
    // canonical default
    // canonical default
  )
}

///|
/// `node` が値を束縛する全ての leaf name を再帰的に集める (DR-093 の or/ref 親充足判定の実体解決 —
/// `required_candidates` の `ref_target` 分岐が使う)。open value resident と `@engine.ReqArg` の name が
/// 対象。`@engine.Or`/`@engine.Seq`/`@engine.Many`/`@engine.BoundedTail`/`@engine.Rooted`/`@engine.Scoped`/`@engine.GreedyRepeat`/`@engine.IdxRepeat` は値
/// バインディングを持たない構造ラッパーなので内部を再帰的に辿る。`Ref` は registry を辿って参照先
/// テンプレートに再帰する (`visiting` は `head_cycles` と同じ「訪問済み template 名」防御 — 循環
/// ref は `collect_circular_ref` が別途 definition-error で弾く前提だが、防御的に無限再帰を避ける)。
fn collect_value_names(
  node : @engine.Node,
  registry : Map[String, @engine.Node],
  visiting : Array[String],
  out : Array[String],
) -> Unit {
  match node {
    Ext(_) =>
      match node_resident_name(node) {
        Some(name) => out.push(name)
        None => ()
      }
    @engine.ReqArg(name) => out.push(name)
    @engine.Or(alts) =>
      for a in alts {
        collect_value_names(a, registry, visiting, out)
      }
    @engine.Seq(items) =>
      for it in items {
        collect_value_names(it, registry, visiting, out)
      }
    @engine.Many(inner, _) =>
      collect_value_names(inner, registry, visiting, out)
    @engine.BoundedTail(inner, _, _) =>
      collect_value_names(inner, registry, visiting, out)
    @engine.Rooted(inner, _) =>
      collect_value_names(inner, registry, visiting, out)
    @engine.Scoped(_, inner) =>
      collect_value_names(inner, registry, visiting, out)
    @engine.GreedyRepeat(inner) =>
      collect_value_names(inner, registry, visiting, out)
    @engine.IdxRepeat(_, inner, _, _) =>
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
/// registry 上の `@engine.Node` として存在し、`@engine.ElemDef.body` には反映されない —
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
/// 戻り値は `@engine.RequiredCandidate` (name + wrapper) — ref 経由の場合、値は宣言元 `e` 自身の @engine.Scoped
/// 部分木 (`@engine.Scoped(e.name, ...)`、`inst_long`/`lower_positional` の ref 分岐が作る) に着地するため、
/// `wrapper: Some(e.name)` を付けて判定側 (`eval.mbt`/`resolve.mbt`) が「宣言元要素自身の部分木内」
/// だけを探すようにする (DESIGN §2.4/2.5 の露出規則、無制限透過ではなく要素自身の部分木に限定 —
/// `@engine.RequiredCandidate` の doc comment 参照)。直書き BOr の場合、値は親 scope に直接 bind されるため
/// `wrapper: None`。
fn required_candidates(
  e : @engine.ElemDef,
  registry : Map[String, @engine.Node],
) -> Array[@engine.RequiredCandidate] {
  match e.ref_target {
    Some(r) => {
      let names : Array[String] = []
      collect_value_names(Ref(r), registry, [], names)
      if names.length() > 0 {
        let out : Array[@engine.RequiredCandidate] = []
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
          let out : Array[@engine.RequiredCandidate] = []
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
  def : @engine.Definition,
  build : @engine.InstallBuild,
  registry : Map[String, @engine.Node],
) -> Unit {
  let all : Array[@engine.ElemDef] = []
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
    let members : Array[@engine.RequiredCandidate] = []
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
  let cs = @engine.to_chars(s)
  let cu = @engine.to_chars(sub)
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
  let cs = @engine.to_chars(s)
  let cf = @engine.to_chars(from)
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
      buf.write_string(@engine.chars_to_str(cs, 0, i))
      buf.write_string(to)
      buf.write_string(@engine.chars_to_str(cs, i + cf.length(), cs.length()))
      return buf.to_string()
    }
    i = i + 1
  }
  s
}

///|
/// canonical option / positional 要素を name で検索。
fn find_elem(def : @engine.Definition, name : String) -> @engine.ElemDef? {
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
fn find_command(def : @engine.Definition, name : String) -> @engine.CommandDef? {
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
  ty : &@engine.TypeExt,
  long : Array[String],
  variants : Array[@engine.Variant],
  short : Array[Char],
  deprecated : Bool,
) -> @engine.ElemDef {
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
    export_key: @engine.export_key_unset(),
    requires: [],
    conflicts_with: [],
    exclusive_group: [],
    required_group: [],
    required: false, // alias entry は @engine.AliasDef 自体に required 宣言経路を持たない (requires/exclusive_group と同じ理由)
    value_requires: [],
    deprecated,
    // DR-104 §2/§3: alias entry-copy は常に is_alias:true (この関数自体が alias 宣言由来 entry-copy
    // 専用のコンストラクタ)。hidden は @engine.AliasDef に独立宣言経路を持たない (deprecated と違い、現行
    // fixture に alias 側の独立 hidden を要求するものが無い) ので canonical と同じ false 既定。
    is_alias: true,
    hidden: false,
    completer: None,
    default_values: None,
    int_round: @engine.RError,
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
    long_eq_sep: @engine.EsAllow,
    short_combine: true,
    short_attached_value: @engine.AtAllow,
    body: BCell,
  }
}

///|
/// alias 宣言 (DR-057) を option entry-copies / command defs に desugar。完全性検査が the alias installer resident の
/// "alias" 所有を確認した後、init_sb 前に 1 度だけ走る決定的 pre-pass。各 entry-copy は canonical name
/// で keying (satellites が canonical cell を bind、結果キーも canonical)、再導出綴りを携行し、fixpoint
/// の long/short/command installer が展開する (DR-057 §4)。command subtree にも再帰。
///
/// `orig` は normalize_surface 適用前の複製 (issue 2026-07-08 dec-alias-long-override-flag-sugar-
/// gap): `def` 側の canonical 要素は既に flag_type()→bool_type() 変換済みなので、DR-076 §2 規則1 (flag の
/// `long:true` 糖衣は `:set:true` へ差し替え) を判定する材料 (元の型 flag_type()) が失われている。`orig`
/// から同じ target 要素の変換前の `ty`/`long` を引き、`resolve_long` を canonical 側と同じ形で
/// 通すことで、alias 側にも同じ規則1/2 を適用する。
fn desugar_aliases(def : @engine.Definition, orig : @engine.Definition) -> Unit {
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
        let variants : Array[@engine.Variant] = []
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
              export_key: @engine.export_key(a.target),
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
fn add_constraint(build : @engine.InstallBuild, c : @engine.Constraint) -> Unit {
  for existing in build.constraints() {
    if existing == c {
      return
    }
  }
  build.constraints().push(c)
}

///|
fn def_err(
  element : String,
  kind : @engine.DefErrKind,
  message : String,
  hint : String,
) -> @engine.DefError {
  { element, kind, message, hint }
}

///|
/// DR-011 明確化 (kawaz 裁定 2026-07-08): `long` の array 形の各要素は `classify_long_spelling` が
/// `LMain`/`LVariant` に分類できる形でなければならない — colon-less な文字列、または語彙外 effect
/// word を持つ文字列 (`LInvalid`) は文法エラーで `unknown-vocab` (DR-054) に落とす。`normalize_option`
/// (`resolve_long` 経由) の**前**に検査する必要がある — `resolve_long` は `LInvalid` を黙って捨てる
/// (呼び出し前提が「無効文字列は既に definition-error として検出済み」なので) ため、normalize 後の
/// `e.long` には無効な生文字列がもう残っていない。
fn collect_invalid_long_dsl(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
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
fn push_invalid_long(
  e : @engine.ElemDef,
  out : Array[@engine.DefError],
) -> Unit {
  match e.long {
    LBool(_) => () // bool 糖衣は常に妥当 (DR-071 §1 / DR-076 §2)
    LList(strs) =>
      for l in strs {
        match classify_long_spelling(l, kebab(e.name), e.ty) {
          LInvalid(s) =>
            out.push(
              def_err(
                e.name,
                @engine.DUnknownVocab,
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
/// の「自分の @engine.ElemDef を検査する」形と入力の形が違うため — dangling alias target (見つからない場合)
/// は absent-ref check が別途拾うのでここでは静かにスキップする。desugar_aliases (LInvalid を
/// rename-only で通す経路) より前、static check フェーズで検出する。
fn collect_invalid_alias_long_override(
  def : @engine.Definition,
  out : Array[@engine.DefError],
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
                          @engine.DUnknownVocab,
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
/// decode 時点で確定し normalize_surface の影響を受けないため (flag_type()→bool_type() 変換のような pre/post
/// 区別は不要)、他の post-normalize な collect_* 群と同じ並びで呼んでよい。
fn collect_tty_stream_missing(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn check(e : @engine.ElemDef) -> Unit {
    if e.is_tty && e.tty_stream is None {
      out.push(
        def_err(
          e.name,
          @engine.DInvalidRange,
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
/// zero-progress 静的 guard (DR-043): repeat head は >= 1 token 消費が必要 (再帰 unfold の loop を防止)。
/// ref head は「target が >= 1 消費」に還元 (消費 node のない ref cycle も捕捉)。
fn head_progresses(
  node : @engine.Node,
  registry : Map[String, @engine.Node],
  visiting : Array[String],
) -> Bool {
  match node {
    @engine.ReqArg(_)
    | @engine.Exact(_)
    | @engine.NativeMatch(_)
    | @engine.DdSat(_)
    | @engine.CmdSat(_, _) => true
    // DR-090: progress depends on `self_keep` — `drop` (false) consumes 1 token like `@engine.DdSat`,
    // `keep` (true) is a 0-token @engine.Accept (same standing as `@engine.Bind`/`effect resident` below).
    @engine.DdMatchSat(_, _, self_keep, _) => !self_keep
    Ext(extension) => !extension.consumes_zero_tokens()
    @engine.IdxRepeat(_, _, _, _) => true // 名前付き indexed repeat は head を消費
    @engine.BoundedTail(_, budget, _) => budget >= 1 // >= 1 head 取れる時のみ消費
    @engine.Rooted(inner, _) => head_progresses(inner, registry, visiting)
    @engine.Bind(_, _) => false // 0-token
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
    @engine.Or(alts) => {
      for a in alts {
        if !head_progresses(a, registry, visiting) {
          return false
        }
      }
      alts.length() > 0
    }
    @engine.Seq(items) =>
      if items.length() >= 1 {
        head_progresses(items[0], registry, visiting)
      } else {
        false
      }
    @engine.Many(_) | @engine.Scoped(_, _) | @engine.ScopeNode(_) => true
    @engine.GreedyRepeat(inner) => head_progresses(inner, registry, visiting)
  }
}

///|
/// HEAD position の ref (最初に消費される要素の ref), 無ければ None。消費 head の後の ref (repeat の
/// cons tail `@engine.Seq([head, Opt(Ref(self))])` 等) は head 位置ではないので、正当な repeat 自参照は None を返す。
fn head_ref_of(node : @engine.Node) -> String? {
  match node {
    Ref(r) => Some(r)
    @engine.Seq(items) =>
      if items.length() >= 1 {
        head_ref_of(items[0])
      } else {
        None
      }
    @engine.Or(alts) => {
      for a in alts {
        match head_ref_of(a) {
          Some(r) => return Some(r)
          None => ()
        }
      }
      None
    }
    @engine.Rooted(inner, _) => head_ref_of(inner)
    _ => None
  }
}

///|
/// `name` から head-position ref を辿ると loop するか (無限構造展開の circular ref, DR-054)。repeat
/// 自参照 (head が消費 node) はここで loop しない。
fn head_cycles(
  name : String,
  registry : Map[String, @engine.Node],
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
fn head_node_cycles(
  node : @engine.Node,
  registry : Map[String, @engine.Node],
) -> Bool {
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
  def : @engine.Definition,
  registry : Map[String, @engine.Node],
  out : Array[@engine.DefError],
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
              @engine.DZeroProgress,
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
  registry : Map[String, @engine.Node],
  out : Array[@engine.DefError],
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
          @engine.DCircularRef,
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
  def : @engine.Definition,
  registry : Map[String, @engine.Node],
  out : Array[@engine.DefError],
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
  e : @engine.ElemDef,
  registry : Map[String, @engine.Node],
  out : Array[@engine.DefError],
) -> Unit {
  match e.ref_target {
    Some(r) =>
      match registry.get(r) {
        Some(_) => ()
        None =>
          out.push(
            def_err(
              e.name,
              @engine.DAbsentRef,
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
fn collect_invalid_range(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  for e in def.positionals {
    match e.repeat {
      Some(spec) =>
        match spec.max {
          Some(mx) =>
            if spec.min > mx {
              out.push(
                def_err(
                  e.name,
                  @engine.DInvalidRange,
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
/// (`inst_long`'s `Some(_)` arm) only wires a SINGLE `@engine.GreedyRepeat` spine slot — correct for
/// `min <= 1` (no mandatory-head unrolling, `elem_repeat`'s `Some(spec) => spec.min - 1`
/// mandatory heads collapses to 0), but a `min > 1` spec WOULD unroll extra mandatory heads that
/// `inst_long` silently folds into the SAME single tail (`@engine.Seq(spine)`) — losing both 先食い
/// suppression and the greedy 取り分選好 for those extra reps while still parsing "successfully"
/// (issue 2026-07-09-ref-template-result-shape: 未対応構成は黙って誤動作させず definition error
/// で可視化する契約、[[retreat-is-last-resort]] 同型の「壊れたまま動かすより落とす」判断)。Reject at
/// definition time until `@engine.GreedyRepeat` carries multiple spine slots.
fn collect_unsupported_option_ref_repeat(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  for e in def.options {
    if e.ref_target is Some(_) {
      match elem_repeat(e) {
        Some(spec) =>
          if spec.min > 1 {
            out.push(
              def_err(
                e.name,
                @engine.DInvalidRange,
                "option repeat min \{spec.min} > 1 is not supported for a `ref` element (@engine.GreedyRepeat wires a single spine slot only)",
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
/// folded into `@engine.DUnknownVocab` there) — `multiple` + `update` is a third static-known-bad
/// combination, just discovered one step later (after `normalize_surface` has resolved `variants`,
/// unlike the two above which classify_long_spelling catches at DSL-parse time). `@engine.DInvalidRange` is
/// reused (not a new `@engine.DefErrKind`) for the same reason `classify_long_spelling`'s comment gives:
/// introducing a finer-grained kind is a spec-side DR-054 decision, not kuu.mbt's to make alone.
///
/// spec fixture pin 状況 (2026-07-10 team-lead 連絡): definition_error format 自体が DR-065 で予約の
/// みで未確定なため、spec 側のこの reject の fixture 化は保留 (issue 起票済み、format 実例化は kawaz
/// 裁定待ち) — この検査は kuu.mbt 側の wbtest でのみ pin する (`collect_unsupported_option_ref_repeat`
/// の min>1 reject も同型の wbtest-only pin の前例)。
fn collect_unsupported_accum_update(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  for e in def.options {
    if e.multiple {
      for v in e.variants {
        match v.op {
          @engine.Update(_, _) =>
            out.push(
              def_err(
                e.name,
                @engine.DInvalidRange,
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
          @engine.Update(_, _) =>
            out.push(
              def_err(
                e.name,
                @engine.DInvalidRange,
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
  // @engine.Update binding が届いて `resolve.mbt`'s accum 分岐の abort に到達する
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
                      @engine.Update(_, _) =>
                        out.push(
                          def_err(
                            canon.name,
                            @engine.DInvalidRange,
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
/// count_type() の **short** 発火 (`builtins/matcher_residents.mbt` の `walk_short`'s `count_type()` arm) は variant を一切経由せず
/// `mk_eff(e.name, @engine.Update("increment", []), @engine.Cli)` を直接生成する — variants を持たない firing なので
/// variant 走査ではそもそも見えない (repro: `{"name":"n","type":"count","short":["n"],
/// "multiple":true}` + args `["-n"]` で resolve.mbt の accum 分岐の abort に到達)。
///
/// DR-077 §3 で count は `number + default:0 + update:increment の綴り合成` と規定されている —
/// count という TYPE そのものが「update(increment) 効果を持つ」という契約を運ぶので、firing の綴り
/// (short/long/明示variant) を問わず、**count_type() 要素への `multiple` 宣言そのもの**が accum×update と
/// 構造的に同じ未対応構成 (T=>T transform vs 累積状態 T[]) になる。variant の有無に依存しない要素
/// レベルの検査として、`collect_unsupported_accum_update` とは別条件で実装する (variant 走査を
/// count_type() にも広げるのではなく、count_type()×multiple という組合せ自体を閉じる — short 経由はそもそも
/// variant を生成しないため、variant 走査を広げても捕まえられない)。
fn collect_unsupported_count_multiple(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  for e in def.options {
    if e.ty.name() == "count" && e.multiple {
      out.push(
        def_err(
          e.name,
          @engine.DInvalidRange,
          "a `count` element cannot declare `multiple` — count's type contract IS an update(increment) effect (DR-077 §3), and every filters-registry transform is T=>T (scalar) while a multiple (accum) cell's current value is an accumulated array (T[]), a structural type mismatch with no legal transform today",
          "remove `multiple` from this count element, or use a plain `number` element with an explicit `:update:<transform>` variant on a non-multiple cell",
        ),
      )
    }
  }
  for e in def.positionals {
    if e.ty.name() == "count" && e.multiple {
      out.push(
        def_err(
          e.name,
          @engine.DInvalidRange,
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
/// `@engine.ElemDef` fields directly, since this check runs before `@engine.Entity`/`@engine.Entity.accum` exist. Using
/// the narrower `e.multiple` alone would misfire on a `repeat`-only or bare-`separator` element
/// (both legitimately accum cells per `ensure_entity`, DR-043/034) declaring a multi-piece default
/// — this derivation must stay IN SYNC with `ensure_entity`'s if it ever changes.
fn collect_scalar_array_default(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn is_accum_elem(e : @engine.ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  fn check(e : @engine.ElemDef) -> Unit {
    if !is_accum_elem(e) {
      match e.default_values {
        Some(vs) =>
          if vs.length() != 1 {
            out.push(
              def_err(
                e.name,
                @engine.DInvalidRange,
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
/// (`env_value`/`@engine.config_to_value` の none_type() arm、resolve.mbt/value.mbt) は防御 (このチェックが
/// 先に落とすので unreachable 想定) として残す。config_key の明示宣言のみを対象とし、
/// `config_seat` (config_file 要素の存在で自動的に全 value cell へ同型付与される席、DR-050 §3)
/// はここでは対象外 — 著者が明示的に書いた宣言だけを検査する (config_seat は個々の要素の意図では
/// なくスコープ全体の自動帰結なので、同じ「著者の誤り」カテゴリに属さない)。
fn collect_none_value_source_decl(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn check(e : @engine.ElemDef) -> Unit {
    if e.ty.name() == "none" {
      if e.env.length() > 0 {
        out.push(
          def_err(
            e.name,
            @engine.DInvalidRange,
            "'\{e.name}' is type none (no value space) but declares env — a none element cannot have a value source (DR-089 §4)",
            "remove 'env' from '\{e.name}', or give it a real value type",
          ),
        )
      }
      if e.config_key is Some(_) {
        out.push(
          def_err(
            e.name,
            @engine.DInvalidRange,
            "'\{e.name}' is type none (no value space) but declares config_key — a none element cannot have a value source (DR-089 §4)",
            "remove 'config_key' from '\{e.name}', or give it a real value type",
          ),
        )
      }
      if e.is_inherit {
        out.push(
          def_err(
            e.name,
            @engine.DInvalidRange,
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
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn is_accum_elem(e : @engine.ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  fn check(e : @engine.ElemDef) -> Unit {
    let accum = is_accum_elem(e)
    let none_ty = e.ty.name() == "none"
    if e.final_filters.length() > 0 {
      if none_ty {
        out.push(
          def_err(
            e.name,
            @engine.DInvalidRange,
            "a type:\"none\" element has no value space (DR-089) — final_filters (T→T, DR-102 §1) requires a T to operate over, which does not exist here",
            "remove final_filters from this element, or give it a real value type",
          ),
        )
      } else if accum {
        out.push(
          def_err(
            e.name,
            @engine.DInvalidRange,
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
            @engine.DInvalidRange,
            "a non-accum (scalar) element cannot declare accum_filters (Acc→Acc, accum-only whole-array gate, DR-102 §1) — this element's final gate is final_filters (T→T, over the single resolved value)",
            "move this chain to final_filters, or declare multiple/repeat/separator on this element",
          ),
        )
      } else if none_ty {
        out.push(
          def_err(
            e.name,
            @engine.DInvalidRange,
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
fn collect_unknown_filter(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn is_accum_elem(e : @engine.ElemDef) -> Bool {
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
        @engine.DUnknownVocab,
        "filter '" +
        fs_name +
        "' in " +
        phase +
        " is not registered in the filters registry (DR-101)",
        "use a registered filter name (see DR-095 §3 canonical filter vocabulary) or remove this chain entry",
      ),
    )
  }

  fn check(e : @engine.ElemDef) -> Unit {
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
    if !is_accum_elem(e) && e.ty.name() != "none" {
      for fs in e.final_filters {
        if lookup_filter(fs.name) is None {
          push_unknown(e.name, "final_filters", fs.name)
        }
      }
    }
    // accum_filters (Acc→Acc, ARRAY filter registry, accum 専用、DR-102 §1): 正しい席 (accum かつ
    // 非 none) の場合のみ unknown-vocab 判定。
    if is_accum_elem(e) && e.ty.name() != "none" {
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
/// conflict). Uses `filters.mbt`'s `@engine.compile_regex` — the SAME compile path `filter_regex_match`
/// runs at match time, so a pattern that passes this gate is guaranteed compilable at runtime too.
/// A wrong arg count (not exactly 1) is left to the runtime "regex_match requires exactly 1 arg"
/// Err (`filter_regex_match`) rather than duplicated here as a second definition-time check — this
/// gate's sole job is "does the pattern compile", not general arity validation.
/// DR-090 §2: a dd element's `match` regex — compile failure is a definition-error, the same
/// treatment `collect_invalid_regex_pattern` gives `regex_match` filter-chain patterns (same
/// `@engine.compile_regex` compile path, same `@engine.DInvalidArgument` kind — "pattern compile failure is a
/// definition-time fact, known statically without I/O").
fn collect_invalid_dd_pattern(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn check(e : @engine.ElemDef) -> Unit {
    match e.dd_match {
      Some(pattern) =>
        if @engine.compile_regex(pattern) is None {
          out.push(
            def_err(
              e.name,
              @engine.DInvalidArgument,
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
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn is_accum_elem(e : @engine.ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  fn check_chain(name : String, chain : Array[@engine.FilterSpelling]) -> Unit {
    for fs in chain {
      if fs.name == "regex_match" &&
        fs.args.length() == 1 &&
        @engine.compile_regex(fs.args[0]) is None {
        out.push(
          def_err(
            name,
            @engine.DInvalidArgument,
            "regex_match pattern '" + fs.args[0] + "' failed to compile",
            "fix the pattern syntax for this host's regex dialect (DR-085 §2)",
          ),
        )
      }
    }
  }

  fn check(e : @engine.ElemDef) -> Unit {
    check_chain(e.name, e.piece_filters)
    check_chain(e.name, e.value_filters)
    // final_filters: 正しい席 (非 accum かつ 非 none) の場合のみ pattern compile 検査
    // (M-6 wrong-seat gate 先行)。
    if !is_accum_elem(e) && e.ty.name() != "none" {
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
fn collect_ref_merge_accum(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn check(e : @engine.ElemDef) -> Unit {
    if e.ref_target is Some(_) && e.accumulator is Some("merge") {
      out.push(
        def_err(
          e.name,
          @engine.DInvalidRange,
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
/// `dec_multiple` が「キーが JSON に存在したか」をそのまま運ぶ Option (`@engine.ElemDef.flatten`'s doc
/// comment) — `Some(false)` (明示 `flatten:false` 宣言) も違反として扱う。
fn collect_flatten_non_append(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn check(e : @engine.ElemDef) -> Unit {
    if e.multiple && e.flatten is Some(_) && e.accumulator is Some(_) {
      out.push(
        def_err(
          e.name,
          @engine.DInvalidRange,
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
fn collect_unknown_accumulator(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn check(e : @engine.ElemDef) -> Unit {
    match e.accumulator {
      Some(a) =>
        if a != "merge" && a != "kv_map" {
          out.push(
            def_err(
              e.name,
              @engine.DUnknownVocab,
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
/// min>max は kind=invalid-range (DR-082 §2 の「複数属性の組合せが値域外」、`@engine.DInvalidRange` の
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
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  fn is_accum_elem(e : @engine.ElemDef) -> Bool {
    e.multiple || elem_repeat(e) is Some(_) || e.separator is Some(_)
  }

  // DR-105 §5 明確化 note (a) (codex #3 反映): `length_range` の bound は非負整数限定 — 配列長という
  // 値域そのものの制約であり、`in_range` の canonical number (負数・小数も妥当) とは別の個別規則。
  // `n.to_int().to_double() == n` は整数性判定 (value.mbt の `@engine.value_str` の同型パターンを流用)。
  fn is_nonneg_int(n : Double) -> Bool {
    n >= 0.0 && n.to_int().to_double() == n
  }

  // `nonneg_int`: true なら `length_range` 専用の非負整数制約 (min/max それぞれ独立に
  // kind=invalid-argument、DR-082 §3「装置引数の値そのものが不正」) を追加で課す。`in_range` は
  // false のまま (canonical number、既存挙動を変えない)。
  fn check_two_arg(
    name : String,
    fs : @engine.FilterSpelling,
    nonneg_int : Bool,
  ) -> Unit {
    if fs.args.length() != 2 {
      out.push(
        def_err(
          name,
          @engine.DInvalidArgument,
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
            @engine.DInvalidArgument,
            "'\{fs.name}' min '" + fs.args[0] + "' is not a number",
            "provide a numeric min",
          ),
        )
      (_, None) =>
        out.push(
          def_err(
            name,
            @engine.DInvalidArgument,
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
                @engine.DInvalidArgument,
                "'\{fs.name}' min \{mn} is not a non-negative integer",
                "provide a non-negative integer min, e.g. '\{fs.name}:0:5'",
              ),
            )
          }
          if !is_nonneg_int(mx) {
            out.push(
              def_err(
                name,
                @engine.DInvalidArgument,
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
              @engine.DInvalidRange,
              "'\{fs.name}' min \{mn} is greater than max \{mx}",
              "swap min/max so min <= max",
            ),
          )
        }
      }
    }
  }

  fn check_scalar_chain(
    name : String,
    chain : Array[@engine.FilterSpelling],
  ) -> Unit {
    for fs in chain {
      if fs.name == "in_range" {
        check_two_arg(name, fs, false)
      }
    }
  }

  fn check_array_chain(
    name : String,
    chain : Array[@engine.FilterSpelling],
  ) -> Unit {
    for fs in chain {
      if fs.name == "length_range" {
        check_two_arg(name, fs, true)
      }
    }
  }

  fn check(e : @engine.ElemDef) -> Unit {
    check_scalar_chain(e.name, e.piece_filters)
    check_scalar_chain(e.name, e.value_filters)
    if !is_accum_elem(e) && e.ty.name() != "none" {
      check_scalar_chain(e.name, e.final_filters)
    }
    if is_accum_elem(e) && e.ty.name() != "none" {
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
fn has_config_file(def : @engine.Definition) -> Bool {
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
fn collect_config_cycle(
  def : @engine.Definition,
  out : Array[@engine.DefError],
) -> Unit {
  for e in def.options {
    if e.is_config_file && e.config_key is Some(_) {
      out.push(
        def_err(
          e.name,
          @engine.DConfigCycle,
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
          @engine.DConfigCycle,
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
/// UsefulAST → AtomicAST を installer chain として遂行 (DR-042)。`order` は適用 installer 列、5
/// invariants により結果は順序無依存。
///
/// chain は木全体で FIXPOINT まで回る (global が置いた宣言を後段 pass で long が展開する等の
/// inter-installer 依存を repeat で解決)。termination: add-if-absent と finite element×scope 空間
/// (copy of copy は name 同一で add-if-absent 止まる) により build 層が monotonically 成長し、変化なし
/// pass = fixpoint。
///
/// Returns Ok(atomic scope) or Err(全 definition-time errors)。static check は全て走って 1 list に append
/// (打ち切りなし)。各 @engine.DefError は {element, kind, message, hint} を持つ。
pub fn lower_definition(
  def0 : @engine.Definition,
  order : Array[&@engine.InstallerExt],
  registry? : Map[String, @engine.Node] = Map([], capacity=0),
) -> Result[@engine.Scope, Array[@engine.DefError]] {
  let def = clone_def(def0)
  // DR-076 §2 flag 差し替え/補完の alias 側適用 (issue 2026-07-08 dec-alias-long-override-flag-sugar-
  // gap): `desugar_aliases` は canonical 要素の「元の型」(flag_type() のまま、resolve_long の規則1判定に
  // 必須) を必要とするが、`normalize_surface` は canonical 要素を bool_type() へ書き換えてしまい、この情報
  // を post-normalize な `def` から取り戻せない。normalize 前の複製を別途保持し、alias 解決時だけ
  // そちらを参照する (def 自体には normalize を通常どおり適用する — 二重 pipeline にしない)。
  let orig = clone_def(def0)
  let errs : Array[@engine.DefError] = []
  // 純構文 pre-pass (LOWERING §A / §C.4): `:set` → kebab (Fix 2, DR-071) + dd name 既定 "--" (Fix 3, DR-064 §5)
  normalize_surface(def)
  // init_sb が registry に repeat-lowering template を植える (静的 ref check が見えるように)。
  // alias entry-copies は ref/repeat を持たず、command alias は check 済 body を clone するので、
  // static check は pre-desugar def で回す (この 1 本目の tree は registry 植え込みのみが目的)。
  let _ = init_sb(def, registry)
  for error in @engine.collect_installer_vocab_errors(def, order) {
    errs.push(error)
  }
  let view = @engine.DefsView::new(orig, def, registry)
  for installer in order {
    for error in installer.collect_defs_errors(view) {
      errs.push(error)
    }
  }
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
  @engine.run_installer_fixpoint(sb, order, fn(builder) {
    ensure_entities(builder, has_cf)
  })
}
