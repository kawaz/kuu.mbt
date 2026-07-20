// value.mbt — value cells, provenance tags, and the tolerant number/bool parsers.
//
// These are the leaf currency of the evaluator: a parsed CLI token becomes a
// `Value`, tagged with the `Source` seat it came from (DR-031 ladder), and
// collected as `Binding`s onto a result path.
//
// DR-074 fixes the canonical number/bool 字句; DR-075 fixes int's 値空間判定 and
// the `int_round` rounding modes (with the binary64-非経由 requirement realized by
// lexical scanning here). MDR-002 §3: value.mbt depends on node.mbt only.
//
// `Binding` / `ParseError` (DR-066 5-field with reason) live here; `Branch` and `Cand` live in
// node.mbt. The matcher builds bindings via the mk_binding / cat / pe_filter / depr_marker helpers at the
// end of this file.

///|
/// A resolved value that can land in the result object.
pub(all) enum Value {
  String(String)
  Number(Double)
  Bool(Bool)
} derive(Eq, Debug)

///|
pub fn value_str(value : Value) -> String {
  match value {
    String(string) => string
    Bool(boolean) => if boolean { "true" } else { "false" }
    Number(number) => {
      let integer = number.to_int()
      if integer.to_double() == number {
        integer.to_string()
      } else {
        number.to_string()
      }
    }
  }
}

///|
/// Provenance of a value cell (DR-031 / DR-016 source tag).
/// The evaluator preserves this so an appconfig store (DR-030) can ask
/// "where did this value come from" without the ladder order being movable.
pub(all) enum Source {
  Cli // CLI explicit / link — highest seat (DR-031 #1)
  Env // environment variable seat (DR-031 #2)
  Config // config-file seat (DR-050 #3) — below env, above inherit
  Inherit // nearest ancestor scope's same-named value (DR-031 #4 / DR-013)
  // tty-判定注入値 (DR-099 §2/§12b)。専用ラダー席は持たない — `builtin/tty` preset 型要素の
  // default 席の解決規則 (`fold(観測) ?? 宣言 default ?? absent`) が観測由来で確定したときのタグ。
  // 明示/継承より弱く宣言既定より強いという優先度は不変 (由来が独立席からこの型依存規則へ移っただけ)。
  Tty
  Default // fixed fallback (DR-031 #6)
} derive(Eq, Debug)

///|
/// A JSON-同型 hierarchical config value (DR-050 §2): what a config_provider returns. kuu core
/// never sees TOML/YAML — only this shape. Leaf values are typed (string / number / bool); arrays
/// feed a multiple element's pieces; objects mirror the name-scope hierarchy (同型対応).
pub enum ConfigVal {
  String(String)
  Number(Double)
  Bool(Bool)
  Array(Array[ConfigVal])
  Object(Array[(String, ConfigVal)])
  Null // JSON null (DR-050 §4 / DR-051): treated as 供給なし — the config seat supplies nothing
} derive(Eq, Debug)

///|
/// Convert the host-neutral JSON input tree into the engine's read-only config value.
pub fn config_from_json(json : Json) -> ConfigVal {
  match json {
    Object(object) => {
      let entries : Array[(String, ConfigVal)] = []
      for key, value in object {
        entries.push((key, config_from_json(value)))
      }
      Object(entries)
    }
    Array(items) => {
      let values : Array[ConfigVal] = []
      for value in items {
        values.push(config_from_json(value))
      }
      Array(values)
    }
    True => Bool(true)
    False => Bool(false)
    String(value) => String(value)
    Number(value, ..) => Number(value)
    _ => Null
  }
}

///|
/// The int rounding mode (DR-075 §2). Direction 4 (`floor`/`ceil`/`trunc`/`away`) × {plain, half}
/// + `half_even` + `error` = 10 modes, 体系完備. `error` is the canonical default (int silently
/// coerces nothing; a non-integer VALUE is rejected). Direction語 name 0-起点 (`trunc`/`away`) と
/// 無限-起点 (`floor`/`ceil`) を分け、Java/Python の "UP"/"DOWN" 多義を持ち込まない (DR-075 §3).
pub(all) enum RoundMode {
  Floor // →−∞
  Ceil // →+∞
  Trunc // →0 方向 (小数部を捨てる)
  Away // →0 の反対方向 (絶対値切り上げ)
  HalfFloor // tie→−∞
  HalfCeil // tie→+∞
  HalfTrunc // tie→0 方向
  HalfAway // tie→0 の反対 (学校四捨五入)
  HalfEven // banker's rounding
  Error // 非整数値は Error
} derive(Eq, Debug)

///|
/// DESIGN §7.2 / DR-096 §1: scope config `long_eq_sep` の 3 値。long の eq 分割形 (`key=value`) と
/// space 分割形 (`key value`) の入口をダイヤルする。`Require` = eq 分割形のみ受理 (space-form main
/// entry を withhold、DR-091 §3 の eq 必須意味論)、`Allow` (既定) = 両方受理、
/// `Deny` = eq 分割 matcher を生成せず space 分割形のみ受理。
/// 3 値 enum のため「eq 必須かつ eq 禁止」のような組合せはそもそも構文的に表現できない (illegal
/// states unrepresentable、DR-096 §1)。
pub(all) enum EqSepMode {
  Require
  Allow
  Deny
} derive(Eq, Debug)

///|
/// Decode a canonical `long_eq_sep` config string (DR-096 §1) to its `EqSepMode`. Returns None on an
/// unknown token — the caller surfaces this as a `DecodeSkip` (`int_round`/`round_mode_of` と同じ
/// 前例パターン、`json_conformance_test.mbt` の呼び出し側)。
pub fn eq_sep_mode_of(s : String) -> EqSepMode? {
  match s {
    "require" => Some(Require)
    "allow" => Some(Allow)
    "deny" => Some(Deny)
    _ => None
  }
}

///|
/// DESIGN §7.2 / DR-096 §2 (kawaz 裁定 2026-07-12 で `last_only` 追加、4 値): scope config
/// `short_attached_value` の 4 値。値持ち short の付着形 (`-O2`) と space 分割形 (`-O 2`) の**読み
/// 生成**を entry 単位でダイヤルする — ダイヤルが条件にするのは読みの形だけで、単独発火かクラスタ内
/// か・クラスタ内の位置は条件にならない (DR-096 §3.1、位置条件の除去)。`Require` = 付着形のみ受理
/// し space-form の読み枝が立たない (gcc/clang の `-O`/`-W` 型)、`Allow` (既定) = 両方受理 (DR-041
/// §4 の値スロット一般規則そのまま)、`Deny` = 付着読みの枝を生成せず space 分割形のみ受理する、
/// `LastOnly` = 付着読みを「残り全部の丸取り形」1 通りだけに制限 (mid-token の分割点を列挙しない、
/// GNU getopt 慣習 — `allow`/`require` だと同一トークン内の全分割点が ambiguous を生みうるところを
/// 一意化する)、space 形は `allow` 同様に生きる。値スロットを持たない要素 (flag/count) にはダイヤル
/// が届いても inert (DR-096 §3.2)。`long_eq_sep` (`EqSepMode`) とは軸そのものが異なる別型 — short
/// に eq 分割形は存在しない (DR-096 §3.4)。
pub(all) enum AttachMode {
  Require
  Allow
  Deny
  LastOnly
} derive(Eq, Debug)

///|
/// Decode a canonical `short_attached_value` config string (DR-096 §2) to its `AttachMode`.
/// Returns None on an unknown token (`eq_sep_mode_of` と同型の前例パターン)。
pub fn attach_mode_of(s : String) -> AttachMode? {
  match s {
    "require" => Some(Require)
    "allow" => Some(Allow)
    "deny" => Some(Deny)
    "last_only" => Some(LastOnly)
    _ => None
  }
}

///|
/// bool の factory config (DR-074 §3/§4 `bool_parser`, DR-061 §3 configurable factory)。canonical
/// default (`bool_config_canonical`) は `true_values: ["true","1"]` / `false_values: ["false","0",""]`
/// / `case_insensitive: true` — 既存 `parse_bool` のハードコード語彙と同値 (置き換えではなく同じ表を
/// データ化しただけ、対極確認は wbtest 側)。opt-in で `true_values`/`false_values` に `yes`/`on` 等を
/// 追加する (DR-074 §4 の `+[...]` 表記は「default 配列に語彙を足した完成形をそのまま渡す」の意 — wire
/// 上は置換であって merge ではない、config は純データという DR-061 §4 の原則通り)。
pub(all) struct BoolConfig {
  true_values : Array[String]
  false_values : Array[String]
  case_insensitive : Bool
} derive(Eq, Debug)

///|
/// A type resident's parse rejection. The resident owns both the machine-readable reason and
/// caller-facing message; engine transports them without closing the vocabulary over builtin cases.
pub(all) struct TypeParseFail {
  reason : String
  message : String
} derive(Eq, Debug)

///|
/// The category of a held Error (DR-053 §2 / DR-037 / DR-047): `parse` = type parse failure,
/// `filter` = a piece/value/cell filter reject (a value that parsed but failed a filter), `constraint` = a
/// delayed-predicate violation (required 未充足 etc., DR-047). All three ride the errors array.
pub(all) enum ErrKind {
  Parse
  Filter
  Constraint
} derive(Eq, Debug)

///|
/// One held Error (DR-053 §2 + DR-066): which element, the args position it failed at, its kind, a
/// machine-readable `reason` (snake_case, DR-066 §3 v1 vocab: missing_operand / unexpected_token /
/// not_a_number / not_an_integer / <attr>_violated), the human message, and `path` (DR-066 §4): the
/// root-first ancestor scope names the error fired under (snoc form — `path` = ancestors, `element` =
/// self; `path: []` = root 直下, no separate null case, Maybe ⊂ List). The errors array keeps ALL of
/// them (別候補経路の別 Error); primary = max args_pos. Conformance compares errors by
/// (element, args_pos, kind, reason) — message is always ignored (CONFORMANCE §3), path is optional
/// (DR-066 §4) — so every construction site emits a reason from the v1 vocabulary and a path (`[]`
/// when the error has no ancestor scope to record, which conformance treats identically to "no path
/// asserted" when the fixture opts out).
pub(all) struct ParseError {
  element : String
  args_pos : Int
  kind : ErrKind
  reason : String // DR-066 §3: machine-readable failure identifier (snake_case v1 vocab)
  message : String
  path : Array[String] // DR-066 §4: root-first ancestor scope names (snoc form, [] = root 直下)
} derive(Eq, Debug)

///|
/// DR-083 §2: a declared default's stored piece is already a `Value` (decoded straight off the
/// JSON literal, `String`/`Number`/`Bool` — never `String` coerced through the element's TypeExt resident at decode time,
/// mirroring how a config array's piece is stored as an untyped `ConfigVal` until READ). This is
/// the bridge that lets `resolve_ladder_below_cli`'s default seat reuse `config_to_value` VERBATIM
/// (DR-083 §2 "config array と同型に扱う") instead of re-deriving the same string/number/bool
/// leniency table a second time — `Value`'s 3 variants map 1:1 onto `ConfigVal`'s 3 scalar ones.
pub fn value_to_configval(v : Value) -> ConfigVal {
  match v {
    String(s) => String(s)
    Number(d) => Number(d)
    Bool(b) => Bool(b)
  }
}

///|
/// The effect an entry's firing applies to a value cell (DR-045). It is PURE DATA
/// `{op, operand?}`: the op names the operation, the operand is the Binding's `value`.
/// A normal value bind (a value slot consuming a token and writing it) is the SET
/// degenerate form, so every effect-column element is uniform (entity, op, operand,
/// source, order). `default`/`unset`/`empty` carry NO operand (the Binding's value is a
/// placeholder). The four ops correspond 1:1 to DR-011's variant effect vocabulary.
pub(all) enum EffectOp {
  Set // write the operand; committed (the degenerate form of a plain value bind)
  Default // reset to the default value; committed (the user explicitly wants default)
  Unset // reset to the default; NOT committed — later ladder seats (env/config/inherit) may override
  Empty // clear a collection (array / map) to empty; committed
  // DR-114 §6.1: a lowered cell-fn invocation. The name and string args remain pure data until
  // the CLI-seat fold invokes the registered resident with an effect-mode FnCtx and the current
  // cell value as ctx.old. Value output becomes an ordinary Set binding; Sentinel output becomes
  // the corresponding direct operation.
  Invoke(FnInvocation)
  // DR-080 §2 (merge accumulator piece marker vocabulary): a `remove`/`splice` PIECE within one
  // CLI firing's separator-split value list, distinct in kind from the 5 CELL-level ops above (a
  // merge-accumulator cell's own effect is still `Set` — these two only ever appear on the
  // per-piece Bindings `resolve_entity_raw`'s accum fold groups by `at_pos`, DR-080 波及節 "1
  // 発火 = 同一 args 位置の piece 列"). `Remove`'s operand (the Binding's `value`) is type-parsed
  // like any add piece (DR-080 §2 "operand は要素 type で parse される"); `Splice` (`@`) carries
  // no operand (the Binding's value is a placeholder, same convention as default/unset/empty).
  // committed = true for both (mirrors `Update`) — `resolve_entity_raw`'s accum branch (which
  // interprets the piece sequence) owns whether the OVERALL fire commits, not this per-piece tag
  // (the DR-045 `committed` helper below never sees these — they never reach the scalar branch,
  // only the accum one, which computes committed_now from its own marker-presence check).
  Remove
  Splice
} derive(Eq, Debug)

///|
/// One EFFECT written onto a result path: `key`'s cell gets operation `op` with operand
/// `value`, from `source` (DR-045). `key` is the leaf name; same-key bindings from
/// different entries (e.g. `--port` satellite and `-p` matcher) merge onto one cell =
/// link 合流. `scope` is the result nesting path (DR-025): a binding produced inside a
/// command / name scope carries that scope's labels, outermost first.
///
/// Path-counting (DR-038) treats the whole binding as identity, so op/operand are part of
/// the effect-sequence key (DR-045 §1 精密化): the same cell reset by `unset` vs written by
/// `set` are DIFFERENT effects even at the same position. A value in `serve` differs from
/// the same leaf at root (scope is in the key too).
pub(all) struct Binding {
  key : String
  op : EffectOp // the operation on the cell (DR-045); Set for a plain value bind
  value : Value // the operand (a placeholder for default/unset/empty, which carry none)
  source : Source
  scope : Array[String]
  link : Int // a link/global-copy binding (DR-042/007): the number of result-nesting levels it
  //           still ESCAPES before settling at its declaring scope. 0 = a normal binding (every
  //           CmdSat/Scoped level prepends its label). N>0 = a global copied N scopes BELOW its
  //           declaration; the next N nest levels skip prepending (decrementing), then it nests
  //           normally — so an intermediate-scope global (DR-042 shadow) lands at its declaring
  //           scope, not the absolute root. A root global (declared at depth 0) has N = its firing
  //           depth, which escapes all the way to the root (the original bool-`link` behaviour).
  // DR-034/DR-062 piece_filters + issue 2026-07-09-accum-entity-filters-wiring: the args token
  // position this binding's VALUE was read from, when it has one. `Some(pos)` for a CLI-seat
  // binding built at token-consumption time (eval.mbt/builtins/matcher_residents.mbt's `mk_binding` call sites — a separator
  // piece carries the position of the WHOLE token it split from, not a per-piece offset, since a
  // piece is not itself a token). `None` for every non-token-consumption source (env/config/
  // inherit/default seats, resolve.mbt) — those values were never read off an args token, so there
  // is no position to attribute a later value_filters(each) reject to (`apply_entity_filters`'s
  // `filter_err` falls back to the ladder's own `at_pos`, unchanged behavior, when this is `None`).
  at_pos : Int?
} derive(Eq, Debug)

// ── Binding/ParseError helpers the matcher builds (Branch itself lives in node.mbt) ──

///|
/// A plain value bind = the SET degenerate form of an effect (DR-045 §1). `at_pos` (issue
/// 2026-07-09-accum-entity-filters-wiring): the CLI-seat call sites (eval.mbt/builtins/matcher_residents.mbt) pass
/// `Some(pos)` — the token this binding's value was read from; every other caller (resolve.mbt's
/// env/config/inherit/default seats) omits it, defaulting to `None`.
pub fn mk_binding(
  key : String,
  value : Value,
  source : Source,
  at_pos? : Int? = None,
) -> Binding {
  { key, op: Set, value, source, scope: [], link: 0, at_pos }
}

///|
/// A `kind: filter` held Error for a piece_filters chain that rejected a raw token/piece before it
/// ever reached its type parser (DR-034/DR-062, DR-037's Reject/Error distinction — see
/// `apply_piece_filters`'s doc comment for why a filter chain's `Err` always becomes a `Held`, never
/// a silent `[]`: the Or/path-search machinery already discards a `Held` branch whenever a sibling
/// branch `Accept`s, so a single `Held(kind: Filter, ...)` return realizes BOTH DR-037 outcomes —
/// no separate silent-Reject channel is needed). Token-consumption callers (eval.mbt's value-
/// primitive arms, builtins/matcher_residents.mbt's `run_eq_split`) pass `reason`/`message` straight from
/// `apply_piece_filters`'s `Err` tuple. Mirrors `resolve.mbt`'s `filter_err` (the ladder-layer
/// counterpart, used by `env_value`) — kept as a separate builder here because eval.mbt/value.mbt
/// sit below resolve.mbt in the dependency graph (MDR-002 §3) and cannot call it.
pub fn pe_filter(
  element : String,
  pos : Int,
  reason : String,
  message : String,
) -> ParseError {
  { element, args_pos: pos, kind: Filter, reason, message, path: [] }
}

///|
/// A deprecation marker binding (DR-058): key `@depr:<element>`, recording that a deprecated entry
/// (DR-057 alias) was used to reach the canonical cell. Rides in the effect column like any binding;
/// the result builder skips it (bookkeeping, not a value), and `warnings_of` collects it.
pub fn depr_marker(element : String) -> Binding {
  {
    key: "@depr:" + element,
    op: Set,
    value: Bool(false),
    source: Cli,
    scope: [],
    link: 0,
    at_pos: None,
  }
}
