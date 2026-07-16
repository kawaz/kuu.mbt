// node.mbt — the AtomicAST node ADT and its two-face scope.
//
// DR-039: AtomicAST = a declarative serialization of the bottom-up engine's node
// graph. The core grammar is atomic (exact / or / seq / primitive + multiple)
// plus name (result scope). DR-041 §1: matchers add runtime reading capability
// WITHOUT adding schema — so `NativeMatch` carries matcher DATA (not an opaque
// closure), keeping the whole AST comparable (`derive(Eq, Debug)`) for the
// order-independence permutation test (DR-042).
//
// MDR-002 §3: this file is the dependency-free leaf (behaviour-free ADTs only).
// MDR-003: reserved-word collisions (`alias` / `export` / `inherit` 単独) take a
// trailing underscore. Here only `Entity.inherit` collides → `inherit_`; compound
// spellings (`export_key`, `ExportKey`, `is_config_file`) are already safe.

///|
/// A definition-time (parse_definition) Error category (DR-054 §1). All are "lowering が構成できない
/// / 全入力で壊れる" — Error, not warn. (warn 層 = 一部入力で驚きうるだけ, は lint の関心で PoC 射程外.)
pub(all) enum DefErrKind {
  DVocabIntersection // two installers own the same vocab (DR-042③)
  DUnknownVocab // a special vocab owned by no installer in the chain (DR-042①)
  DInvalidRange // an invalid value range (repeat min > max, etc., DR-052 ほか)
  DAbsentRef // a ref target resolvable nowhere (scope + definitions, DR-032)
  DCircularRef // a ref cycle with infinite structural expansion (DR-007/032)
  DZeroProgress // a repeat unfold whose 1 iteration consumes no token (DR-043)
  DConfigCycle // a config_file element taking its own path from config (DR-050 §5)
  // a single argument value itself is outside a registry device's acceptance range (DR-054 §4
  // 更新2 / DR-082 §3, DR-085 §1 訂正) — e.g. regex_match's pattern failing to compile. Distinct
  // from DInvalidRange (a COMBINATION of attributes is out of range, e.g. repeat min > max):
  // DInvalidArgument is about a single value's own internal validity.
  DInvalidArgument
} derive(Eq, Debug)

///|
/// One definition-time Error (DR-054 §4): {element, kind, message, hint}. `hint` is the「次の手」
/// (DR-042 完全性検査の様式). parse_definition enumerates ALL of these (no first-error 打ち切り).
pub(all) struct DefError {
  element : String
  kind : DefErrKind
  message : String
  hint : String
} derive(Eq, Debug)

///|
/// The result-key axis of an element (DR-052). `export_key: string | null` unified: unspecified =
/// name-derived key, a string = key-name override, null (or "" — normalized to null) = NO result
/// key = nameless-同化 透過 (the value still propagates; only the key is gone). This is a RESULT
/// concern only — lexical scope (name, DR-033) and id (ref/link, DR-046) are orthogonal, unchanged.
pub enum ExportKey {
  EkUnset // unspecified → the name is the key (DR-046 default supply)
  EkKey(String) // a string override → that key name
  EkNull // null / "" → 結果キー軸なし → 透過 (kv: value gone; seq: value stays as an array element)
} derive(Eq, Debug)

///|
/// Type category of a value cell / primitive. `number` (TNum) accepts integers and floats but
/// rejects inf/nan (DR-074 §1); `int` (TInt) is integer-constrained by 値空間判定 — a non-integer
/// VALUE follows `int_round` (DR-075, canonical default `error`). `float` (TFloat) shares TNum's
/// accept域 PLUS inf (case-insensitive `inf`/`infinity`, sign-合成可) — nan stays Error for both
/// (DR-074 §1/§7). `TFlag` is a PRESENCE-only trigger (bare `--x` fires name=true, no value token
/// ever — e.g. `--help`/`--verbose`). `TBool` is DR-074 §3's value-typed canonical bool: the bare
/// trigger ALSO fires true (same degenerate as TFlag), but it additionally takes an eq-split value
/// (`--enabled=true`, parsed through the canonical bool vocab) UNLESS the element carries variant
/// spellings (`--x`/`--no-x`) — a variant-bearing bool already has a dedicated true/false pair of
/// triggers, so no separate `=value` form is registered for it (installer.mbt `inst_long`).
pub(all) enum Ty {
  TStr
  TNum
  TInt
  TFloat
  TFlag
  TBool
  /// count 糖衣の PRE-normalize marker (DR-077 §3, LOWERING §A.5): mirrors `TFlag`'s standing to
  /// `TBool` — a bare `--x` fire applies the `increment` update effect (0-token, no value ever,
  /// same presence-only shape as `TFlag`'s bare-true). `normalize_option` differentiates
  /// `long:true` sugar (`[":update:increment"]` vs bool's `[":set:true"]`) and default-presets
  /// (0 vs false) by this
  /// tag BEFORE collapsing it to `TNum` — once lowered there is no other channel to tell a count
  /// cell apart from an ordinary number cell (installer.mbt `normalize_option`).
  TCount
  /// DR-089: 値空間が空の型 — type 省略の糖衣先 (§2「type 省略 = none」)。type が規定するのは値
  /// 空間だけで消費は構造 (repeat/値スロット/exact/filter の Accept 報告) の関心という直交 (§1) の
  /// 帰結として、none は「発火しても値を運ばない」ことだけを意味し、消費数そのものは制約しない —
  /// 消費 0 の純トリガ (long のみ) にも、repeat+filter で「食って捨てる」構造にも使える。値充足を
  /// 要求する席 (requires の目的語) には立てない (静的 definition-error、§4)。結果には現れない
  /// (フィールド非掲載、DR-051 §1/§4) — 発火の観測は ParserContext/explains 層の管掌で、この型は
  /// 関与しない。
  TNone
} derive(Eq, Debug)

///|
/// One filter-chain DSL entry (DR-009 §DSL 文法, `piece_filters`/`value_filters`/`final_filters`/
/// `accum_filters`, DR-102 属性分割):
/// name + args, structured — either from the colon shorthand (`"in_range:1:65535"` decodes to
/// `{name:"in_range", args:["1","65535"]}`) or the DESIGN §8.4 / DR-085 §3 object form
/// (`{"name":"regex_match","args":["^https?://"]}`, needed when an arg itself contains a colon,
/// e.g. `regex_match`'s `^https?://` pattern). Both forms decode to the SAME `FilterSpelling` shape
/// (issue filter-spelling-inband-encoding-retyping) — no in-band string encoding / magic-tag scheme
/// is needed since `args` carries the object form's values verbatim in a real `Array[String]` field
/// rather than a single joined string. Colon-splitting for the shorthand happens ONCE at the decode
/// boundary (`json_conformance_wbtest.mbt`'s `dec_filter_chain`); every downstream consumer
/// (filters.mbt/installer.mbt/eval.mbt/matcher.mbt/resolve.mbt/value.mbt) reads `name`/`args`
/// directly, never re-parses a spelling string.
pub struct FilterSpelling {
  name : String
  args : Array[String]
} derive(Eq, Debug)

///|
/// A node of the AtomicAST. Consumption is measured in whole args tokens.
pub enum Node {
  /// literal token match; binds nothing, consumes 1.
  Exact(String)
  /// string value primitive: consume 1 token, bind name=VStr(token). Maximally permissive (DR-041 §5).
  /// 2nd field is DR-034's piece_filters (String→String FilterChain, DR-062 二形のうち kuu.mbt が実装
  /// する `FilterSpelling` 配列のみ — filters.mbt ヘッダ注記参照): applied to the raw token BEFORE
  /// this node's own (identity, for TStr) parse step. installer.mbt `value_prim` embeds it from
  /// `ElemDef.piece_filters` (same carrier pattern as `IntArg`'s `int_round` / `allow_base_prefix`);
  /// eval.mbt's consumption arms run it via `apply_piece_filters` immediately after reading
  /// `ctx.toks[pos]`, before the value ever reaches its type parser.
  StrArg(String, Array[FilterSpelling])
  /// separator-splitting value primitive (DR-034 separator pipeline): consume 1 token, split it
  /// on the separator char, and bind ONE `name=part` per split piece, EACH piece parsed through
  /// its own type (issue 2026-07-09-separator-non-string-type-parse-gap §段4 — a piece's type is
  /// independent of whether it came via separator or not, DR-034 §6.2's pieceProcessor). Fields:
  /// name, sep, ty (the element's declared type — TStr is the historical identity-parse default),
  /// int_round (TInt only, mirrors `IntArg`'s carrier), allow_base_prefix (TNum/TInt), bool_config
  /// (TBool only, mirrors `BoolArg`'s carrier — DR-074 §4 `bool_parser` factory config), piece_filters
  /// (applied to EACH split piece — not the whole raw token — right before that piece's own parse
  /// step, DESIGN §6.2: separator → piece_filters → parse → value_filters (each piece) → once the
  /// value is committed, final_filters (non-accum element) or, after accumulation, accum_filters
  /// (accum element), one piece at a time).
  /// `sep_binds` (eval.mbt) threads all of this through the split loop; a piece that fails its
  /// type parse is `kind: KParse` (same reason vocab as the scalar value primitives), NOT a
  /// piece_filters-style `KFilter` reject — these are distinct pipeline stages (段3 vs 段4).
  /// 2nd field is `String?`, not `String` (codex Medium 追従, 2026-07-10): a merge-declared element
  /// with NO `separator` still needs piece semantics (DR-034 §6.3's degenerate form — no separator
  /// IS a 1-piece split, `sep_binds` treats `None` as `[tok]` rather than calling `split_on`). This
  /// is what lets `--fields -a` (no separator declared) recognize `-a` as a merge remove marker
  /// instead of silently degrading to a literal add — without this, marker vocabulary was INERT for
  /// any merge element that omitted `separator` (issue: markers only worked when a comma actually
  /// split the token into ≥1 piece via the OLD mandatory-separator SepArg gate).
  /// 8th field (DR-080 波及節): `merge` — whether the declaring element's `multiple.accumulator`
  /// is `"merge"`. Threaded from `ElemDef.accumulator` via `installer.mbt`'s `value_prim` so
  /// `sep_binds` (eval.mbt) knows whether to run `classify_merge_piece` on each split piece
  /// (merge-declared elements only, DR-080 §1) or treat every piece as a plain add (everyone else,
  /// unchanged pre-DR-080 behavior).
  SepArg(
    String,
    String?,
    Ty,
    RoundMode,
    Bool,
    BoolConfig,
    Array[FilterSpelling],
    Bool
  )
  /// DR-091 §2: kv_map accumulator の consume-time gate — consume 1 token, apply piece_filters,
  /// then require the (filtered) token to contain `=` (the structural precondition "piece `k=v`
  /// を最初の `=` で分割" needs). A token with no `=` is a Held Error (kind=KParse, same family as
  /// any other type-parse failure per team-lead 裁定 2026-07-11 — 「piece の型 parse 失敗と同じ
  /// 扱い」) — this node does NOT split at `=` itself (that's `resolve.mbt`'s `build_result` job,
  /// once every accepted binding is guaranteed to contain `=`); it only gates malformed pieces
  /// out at the same layer every other type mismatch surfaces at. Installer.mbt's `value_prim`
  /// emits this instead of `StrArg` when `ElemDef.accumulator == Some("kv_map")`.
  KvArg(String, Array[FilterSpelling])
  /// number value primitive (DR-074 §1 canonical + §2 opt-in `number_allow_base_prefix`)。consume 1
  /// token, parse via `parse_number_ext(_, allow_base_prefix)`。allow=false は canonical (10 進のみ、
  /// base prefix Error)、allow=true で `0xff` / `0x1.8p3` / `0o777` / `0b1010` も受理する統合 opt-in。
  /// flag は installer が ElemDef.allow_base_prefix から埋め込む (`number_parser` factory config、
  /// DR-061 §4)。parse-fail は `kind: parse` (DR-053)。4th field is DR-034's piece_filters (same
  /// carrier pattern as `StrArg`'s 2nd field) — applied to the raw token before `parse_number_ext`.
  NumArg(String, Bool, Array[FilterSpelling])
  /// float value primitive (DR-074 §1/§7): consume 1 token, parsed through the WIDER float lexicon
  /// (canonical number + the 2-word inf/infinity vocab, case-insensitive, sign-合成可 — nan stays
  /// Error for both number and float). A separate node from `NumArg` because the accept-域 differs
  /// per TYPE (`number` rejects inf, `float` accepts it) and `Ty::TNum`/`Ty::TFloat` is the only
  /// place that distinction is known (installer.mbt `value_prim`); once lowered to a bare value node
  /// there is no other channel to carry it. Parse-fail is `kind: parse`, same reason vocab as NumArg.
  /// 2nd field is DR-034's piece_filters (same carrier pattern as `StrArg`).
  FloatArg(String, Array[FilterSpelling])
  /// int value primitive (DR-075 §1 値空間判定 + §2 int_round factory config). Consume 1 token, parse
  /// via `parse_int_value(_, mode)` where `mode` is the element's `int_round` (canonical default
  /// `RError`, opt-in via `int_parser` factory config, DR-061 §4). RError: fractional は
  /// `not_an_integer`、それ以外 (RFloor/RCeil/RTrunc/RAway/RHalf{Floor,Ceil,Trunc,Away,Even}) では
  /// fractional 値を丸めて Ok。整数値 (`"3.0"` / `"1e3"` / `"1_000"`) は全モードで丸めなし。番号として
  /// 全く読めない token (`"abc"`) は全モードで `not_a_number`。mode は installer で ElemDef.int_round
  /// から埋め込まれる (parse 相内部調整、DR-061 §5); 一度 lowered value node になると他の carrier は
  /// 無いため mode は node 自身が持つ。DR-074 §2 `allow_base_prefix` を第 3 引数で追加運搬 —
  /// opt-in 時は `0xff` (整数値) / `0x1.8p3=12` (整数値) / `0x1.8p0=1.5` (非整数、mode に従う) の
  /// 値空間判定を hex にも一般化する。canonical default は `false`。parse-fail は `kind: parse`。
  /// 5th field is DR-034's piece_filters (same carrier pattern as the other value primitives).
  IntArg(String, RoundMode, Bool, Array[FilterSpelling])
  /// bool value primitive (DR-076 §1/§4: bool is a normal value type, same standing as
  /// string/number). Consume 1 token, parsed via `parse_bool_ext(_, config)` where `config` is the
  /// element's `bool_config` (canonical default = `bool_config_canonical()`, opt-in via `bool_parser`
  /// factory config, DR-061 §4/DR-074 §4); an unrecognized token fails with reason `not_a_bool`
  /// (`pe_parse_bool`). A separate node from `NumArg`/`FloatArg`/`IntArg` for the same reason as
  /// those: `Ty::TBool` is the only place the value-typed-vs-presence-only (`Ty::TFlag`)
  /// distinction is known (installer.mbt `value_prim`); once lowered to a bare value node there is
  /// no other channel to carry it. A bare `--x` (presence-only) fire is `TFlag`'s job, not this
  /// node's — `BoolArg` only appears where a definition's `:set` explicitly wants a value slot.
  /// 2nd field is the bool_config carrier (mirrors `IntArg`'s `RoundMode` field — config is bundled
  /// into one struct here, rather than 3 flat fields, since the 3 keys always travel together and
  /// `RepeatSpec` already establishes the "bundle a multi-key factory config into one struct" pattern
  /// in this same file). 3rd field is DR-034's piece_filters (same carrier pattern as `StrArg`).
  BoolArg(String, BoolConfig, Array[FilterSpelling])
  /// a number value with a max post-filter (DR-034 filter / DR-053 kind demo): consume 1 token,
  /// parse a number; a parse failure is `kind: parse`, a value ABOVE `max` is a `kind: filter`
  /// held Error (a value that parsed but failed the filter — final_filters reject 相当). Test-only
  /// (eval_wbtest.mbt): production lowering (`installer.mbt` の `elem_head`/`value_prim`) never
  /// constructs this node, so it carries no `piece_filters` field (DR-034 配線対象外、issue
  /// 2026-07-09-pre-split-filters-execution-wiring).
  FilterArg(String, Int)
  /// a REQUIRED string positional (DR-047 値充足 / DR-053 kind: constraint): consumes a token if
  /// present; if there is NO token to consume, it is a `kind: constraint` held Error (required
  /// 未充足) rather than a silent Reject — a delayed-predicate violation surfaced as an Error.
  ReqArg(String)
  /// 0-token binder: bind name=value. Used to set a flag after its Exact trigger fired.
  /// This is the SET degenerate form of an effect (DR-045 §1).
  Bind(String, Value)
  /// 0-token EFFECT binder (DR-045): apply a non-set op (default / unset / empty) to the
  /// named cell after an Exact trigger fired. This is the lowering of a variant entry's
  /// effect: `--no-color` → `Seq([Exact("--no-color"), EffMark("color", Unset)])` — the
  /// `link` (to the color cell) is by-name, the `effect` is the op carried here.
  EffMark(String, EffectOp)
  /// 0-token deprecation mark (DR-058): records that a deprecated ENTRY (an alias with
  /// `deprecated: true`, DR-057) was used to reach the named canonical cell. Lowered by the long
  /// installer onto a deprecated element's satellite (`Seq([Exact("--old"), Bind("port", …),
  /// DeprMark("port")])`); the short installer sets `depr: true` on the cluster entry instead. It
  /// rides in the effect column as a `@depr:<name>` marker binding (like a FailMark), collected
  /// into ParserContext.warnings. The value propagates normally — only a warning is added.
  DeprMark(String)
  /// 0-token failure-action mark (DR-048): records that failure-action element `name` (e.g. help)
  /// was SELECTED at the current args position. Lowered from a `fail_action` element's satellite
  /// (`Seq([Exact("--help"), Bind("help", true), FailMark("help")])`). On a FAILED parse (0
  /// complete paths) the recorded action fires in place of the held Error; 先食い/内部一体 keeps
  /// a dd-internal `--help` from being selected (its trigger is raw-consumed, so FailMark never runs).
  FailMark(String)
  /// choice — every alternative's readings become branches (DR-037 / DR-041 §3).
  Or(Array[Node])
  /// ordered consumption; bindings accumulate across the sequence.
  Seq(Array[Node])
  /// unbounded repeat (>= 0). Guarded against zero-progress loops. The `Bool` is the DR-043 lazy
  /// knob (issue 2026-07-08 min0-lazy-repeat-gap): mirrors `BoundedTail`'s 3rd field — `Many` is
  /// the min:0 UNBOUNDED spine form the way `BoundedTail` is the bounded one, so it gets the SAME
  /// seat rather than a parallel mechanism (a min>=1 UNBOUNDED lazy repeat already threads its knob
  /// through the registry's `"lazy:" + name` marker, but `Many` re-enters the SAME node at the same
  /// `pidx` — no named template, so no registry key to carry it on). `false` (installer default when
  /// a repeat has no `lazy` spec) preserves the pre-existing greedy-only behavior exactly.
  Many(Node, Bool)
  /// result scope label (DR-025). Light layer-3 hook; does not change path count.
  Scoped(String, Node)
  /// the two-face scope: greedy (order-free triggers) over a positional face (DR-041 §4).
  ScopeNode(Scope)
  /// native matcher: data-driven token readings (DR-041 §3-4), installed by long/short (DR-042).
  NativeMatch(Matcher)
  /// reference to a named template in the registry (DR-020 / DR-043). repeat lowers to
  /// a recursive `Seq([head, Opt(Ref(self))])`; a ref element (`{ref:"color"}`) points at
  /// a shared template. On the positional spine `Ref` unfolds POROUSLY (>= 1 head, greedy
  /// may interject between reps — the unfold stays on the current backbone, DR-043).
  Ref(String)
  /// dashdash satellite (DR-041 dashdash, rev). A GREEDY-face resident: its matcher
  /// is a plain exact match on the trigger (usually `--`). Because it is a greedy
  /// entry, 先食い (greedy-only) keeps `--` from being raw-eaten; when it fires the
  /// spine walk switches to "severed" mode (greedy off) for the rest — the sever is
  /// the "greedy internal consumption is 一体" rule, not a dd special case.
  DdSat(String)
  /// DR-090: the 2-axis generalization of `DdSat` — a SEPARATE variant (not `DdSat`'s own
  /// arity extended) to keep every existing `DdSat("--")` hand-construction (wbtest files,
  /// installer's canonical exact-dd path) untouched; the installer only ever emits THIS
  /// variant when the definition actually declares `match` and/or `self:"keep"` (§2).
  /// Fields: `(spelling, is_pattern, self_keep, elem_name)`.
  /// - `spelling`: the exact trigger string (`is_pattern=false`, same matching as `DdSat`)
  ///   OR a regex pattern source (`is_pattern=true`, compiled via `compile_regex` — the SAME
  ///   host-dialect compile path DR-085's `regex_match` filter uses, unanchored substring-vs-
  ///   whole-token semantics per DR-090 §2's "match" being a trigger test on the WHOLE token).
  /// - `self_keep`: `false` (drop, DR-090 §2 既定 — consume 1 token, discard it, same as `DdSat`)
  ///   | `true` (keep — consume 0 tokens, Accept immediately; the triggering token itself
  ///   flows into the positional face along with everything after it, still severed).
  /// - `elem_name` (DR-093 §2/§5): the declaring element's `name`, independent of `spelling`
  ///   (§2's "match があるとき name はトリガ綴りに使われず、要素の同一性・表示軸のみに効く" —
  ///   this is that axis, made concrete). Used ONLY to key the committed-observation binding
  ///   the firing arm produces (mirrors `DdSat`'s own trigger-string-as-name shortcut, which only
  ///   works there because `DdSat` never decouples spelling from name). Never used for matching.
  DdMatchSat(String, Bool, Bool, String)
  /// command satellite (DR-018 / DR-041 §4). A GREEDY-face resident whose matcher is
  /// a plain exact match on the command name. Firing enters the child scope as a NEW
  /// backbone (the parent greedy face does not interject inside it). 先食い protects the
  /// command name from a positional raw-eat, which is the DR-018 "commands が先" priority.
  CmdSat(String, Scope)
  /// link/scope-targeted wrapper (DR-042 global link-sync / DR-007 link). Evaluates its inner
  /// node but marks every binding it produces as a link that escapes `Int` result-nesting levels
  /// (= the scopes this copied satellite sits BELOW its declaration). Those bindings climb out of
  /// the sub-scopes and land on the DECLARING scope's entity. The global installer copies an
  /// option's satellite into a descendant scope wrapped in `Rooted(node, depth)`, so the value
  /// syncs to the one declaring cell instead of a fresh child cell (depth 1 for a direct child,
  /// +1 per re-propagation level). A root global's depth = firing depth (escapes to the root).
  Rooted(Node, Int)
  /// a BOUNDED repeat tail (DR-043 max 有限 / LOWERING §B.8). Consumes 0..budget more heads
  /// on the spine, POROUSLY (via consume_head, so 先食い holds) and with the 取り分選好
  /// preference (greedy default / lazy). A bounded `repeat: {min, max}` lowers to `min`
  /// mandatory heads on the spine followed by `BoundedTail(head, max-min, lazy)` — NO Ref
  /// recursion (the bound is the recursion depth of the tail, not an unbounded self-ref).
  /// `optional: true` = `repeat: {min:0, max:1}` reduces to a lone `BoundedTail(head, 1, _)`.
  BoundedTail(Node, Int, Bool)
  /// a named indexed-array repeat (DR-043 repeat × DR-025 name scope). Consumes its head
  /// GREEDILY (as many reps as the head allows), tagging rep k under `[label, "#k"]` so
  /// the result builder yields an ARRAY of one element per firing (multiple:"append").
  /// `min` is the required rep count (0 = may be empty). Greedy-max is the 取り分選好
  /// default; for this raw pattern the split is bounded by the head's Reject / exact, so
  /// no downstream backtrack is needed (DR-043 §取り分の選好, 大域完全経路) for the
  /// UNBOUNDED case. The 4th field `budget` (issue
  /// 2026-07-13-positional-group-trailing-missing-operand) caps the ADDITIONAL reps beyond
  /// `min` (same seat as `BoundedTail`'s 2nd field, `max - min`): `None` = unbounded (the
  /// original greedy-max-forever behavior, unchanged), `Some(b)` = stop once `rep >= min +
  /// b`, matching a bounded `repeat: {min, max}` spec exactly instead of silently degrading
  /// every BGroup repeat to unbounded regardless of a declared `max`. This does NOT add
  /// backtrack (the KNOWN GAP in `eval_wbtest.mbt`'s "IdxRepeat greedy-max has no downstream
  /// backtrack" test is still open for the unbounded case) — a bounded head simply never
  /// over-consumes in the first place, so no backtrack is needed to correct it.
  IdxRepeat(String, Node, Int, Int?)
  /// an OPTION's repeat value slot (DR-078 §1 option-level repeat, new capability): wraps ONLY
  /// the repeat TAIL (`Ref`/`Many`/`BoundedTail`, the same node `lower_repeat_head` builds for a
  /// positional) — the trigger/marker prefix ahead of it in the satellite's `Seq` stays plain. A
  /// bare greedy satellite is evaluated OFF-SPINE (`step_greedy`'s catch-all → plain `eval`, no
  /// `Scope`), which cannot apply 先食い (DR-041 §4) to stop the repeat before it swallows a
  /// sibling trigger (e.g. a second `--hlcolors`). `step_greedy` detects this wrapper and
  /// evaluates `tail` through a throwaway `Scope` that BORROWS the real scope's `greedy` face (so
  /// suppression sees every sibling trigger, including a refire of the SAME option) but has its
  /// OWN single-slot `positional` (so the tail's internal repeat loop — which re-enters at the
  /// same pidx for "more" — cannot walk into the real scope's unrelated positional slots).
  /// Off-spine `eval` (completion probes etc.) degrades to plain `eval(tail, ..)`, losing
  /// suppression — acceptable there (no sibling scope to suppress against).
  GreedyRepeat(Node)
} derive(Eq, Debug)

///|
/// A scope carries two faces (DR-041 §4):
/// - `greedy`: order-independent trigger entries (long/short satellites + matchers).
///   Each fires as a bound unit; its internal value slots raw-consume (getopt 同型).
/// - `positional`: the ordered, porous token stream. Greedy may interject between items.
/// - `entities`: value cells with the source ladder (env/default seats, DR-030/031).
pub struct Scope {
  greedy : Array[Node]
  positional : Array[Node]
  entities : Array[Entity]
  constraints : Array[Constraint] // delayed predicates (DR-055/047), declared by the constraint installer
} derive(Eq, Debug)

///|
/// One candidate cell that `CRequired`/`CRequiredGroup` may look at (DR-093 の型委譲判定入力、
/// codex レビュー M-2 修正): `name` は値が実際に bind される cell 名 (BOr 直書き structural or の
/// leaf name、ref 先 template の leaf name、または通常要素なら要素自身の name)。`wrapper` は
/// scope 判定の基準を切り替える — `None` なら宣言 scope path そのものと完全一致する scope を探す
/// (BOr 直書きの leaf、または通常要素 — 値は親 scope に直接 bind される、`ensure_entity_body` の
/// BOr コメント参照)。`Some(w)` なら宣言元要素自身 (ref 要素、`w` = ref 要素の name) の Scoped
/// 部分木内 (scope が 宣言 scope path ++ [w] で始まる) を探す — `inst_long`/`lower_positional` の
/// ref 分岐が `Scoped(e.name, ...)` で値をラップするため (DESIGN §2.4/2.5 の露出規則、
/// `ref-template-no-repeat-degenerate.json` が既に pin する挙動と同型)。無制限透過ではなく
/// **宣言元要素自身の部分木に限定** した探索 — 他要素・子 scope の値を誤って拾わないため。
pub struct RequiredCandidate {
  name : String
  wrapper : String?
} derive(Eq, Debug)

///|
/// A delayed-predicate constraint (DR-055 / DR-047), evaluated on a complete path's FINAL state. A
/// violation makes the path NOT a complete解決経路 (DR-047 §2) — a DR-037 Error of kind:constraint.
pub enum Constraint {
  /// element committed → each target must have a value (default 込み). requires = 正の依存 (DR-055 §3).
  CRequires(String, Array[String])
  /// value-dependent requires (DR-055 §1 + DR-052 §値枝 id 直交): 4-tuple = (entity, branch_id,
  /// value, targets). Semantics: `entity` が committed AND その値 == `value` のとき、`targets` の値
  /// 充足を要求する。違反時の error.element は `branch_id` (= or 値枝の匿名要素に付いた id、fixture
  /// の `id: "fmt_json"` に相当) を emit する — 値の帰属先は親 entity (format) だが制約の宣言元は
  /// 枝 (fmt_json) なので、element 属性は宣言元を指す (DR-052 と直交)。`branch_id` == `entity` の
  /// ときは or 匿名枝に id が付いていない (parent 直属の value_requires を模したフォールバック)。
  CRequiresIf(String, String, String, Array[String])
  /// conflicts_with (DR-055 §2, 対称): element committed + any target committed → conflict. Declaring
  /// on one side works both ways (the check is「両方 committed」regardless of who declared it).
  CConflicts(String, Array[String])
  /// exclusive_group: at most one member of the group may be committed (DR-047 指定述語).
  CExclusive(String, Array[String])
  /// required (DR-093 §1/§2): この entity 自身の「解決後の充足」。充足の定義は型 (値空間) への委譲 —
  /// 値空間を持つ要素 (通常の type) は最終状態の値の有無 (default / env 等の値源込み、DR-047 §5 不変)、
  /// 値空間が空の要素 (`type: "none"`、dd 含む、DR-089) は発火したこと (committed)。判定入力に
  /// committed を使う点は CRequires と同じ線 (DR-047 §5 が selected を診断メタに留めた線を維持)。
  ///
  /// 2-tuple = (display, candidates)。issue
  /// 2026-07-13-structural-or-type-branch-required-missing / codex-review-dr102-dr103-postland
  /// (M-2): `display` は違反時の error.element (宣言元の name、DESIGN §9.1 のグループ的必須の宣言元、
  /// 通常要素では下記 candidates[0].name と同じ文字列)。`candidates` (`RequiredCandidate` 配列) は
  /// 型委譲判定を実際にどの cell に対して行うかの候補集合 — 通常要素は `[{name: display, wrapper:
  /// None}]` 自身 (単一候補、既存挙動どおり)。structural or (`BOr`、型付き枝、直書き) が required を
  /// 持つ場合は各枝の leaf name (`wrapper: None`、値は親 scope に直接 bind される) の配列: BOr
  /// wrapper 自身 (display) は "no own scalar/array value" (installer.mbt の BOr entity 登録コメント
  /// 参照) で値が committed されることが無く、値は選ばれた枝の leaf entity (num/flag 等) にのみ
  /// commit される。`ref` 経由の structural or (テンプレート先が Or) も同様に leaf name を候補とする
  /// が、この場合は `wrapper: Some(宣言元 ref 要素の name)` — ref 展開が `Scoped(ref要素名, ...)` で
  /// 値をラップするため、判定は宣言元要素自身の Scoped 部分木内を探す必要がある
  /// (`RequiredCandidate` の doc comment 参照)。判定は candidates のいずれか 1 つでも型委譲で
  /// 充足していれば OK (DR-093 の「or 親の値充足 = どの枝であれ発火して値が確定していること」— 枝が
  /// exact (value-enum, BEnum) なら全枝が同じ display 名の cell に着地するため候補は元々
  /// `[{name: display, wrapper: None}]` のままで足りる、対称性が崩れるのは structural or だけ)。
  CRequired(String, Array[RequiredCandidate])
  /// required_group (DR-103): グループ単位「少なくとも1つ必須」— `exclusive_group` (CExclusive) と
  /// 同型の 2-tuple = (group label, member candidates)。member の充足判定は `CRequired` と完全に
  /// 同一の型委譲 (DR-093: 値空間ありは値の有無・default 込み、値空間なしは発火 committed) をグループ
  /// の論理和に持ち上げたもの — bool 型の特殊化 (requires 目的語の truth-dispatch) は適用しない
  /// (DR-103 §7、kawaz 裁定 2026-07-14「値述語と依存述語は別」)。member が 1 つだけの場合は
  /// `CRequired` と観測上同じ結果になる (DR-103 §4 の縮退)。`required_group` と `exclusive_group` の
  /// group 名前空間は独立 (DR-103 §3) — 同名文字列を両属性に書いても 2 つの独立述語として評価される。
  /// candidates の候補セル解決 (`RequiredCandidate` の name/wrapper 双方) は `CRequired` と完全に
  /// 共有する (`installer.mbt` の `required_candidates` ヘルパー、codex M-2 の再発防止)。
  CRequiredGroup(String, Array[RequiredCandidate])
} derive(Eq, Debug)

///|
/// A value cell (DR-030 "entity-only node"). Satellites/matchers with the same
/// `name` all write here = link 合流. Carries the reduced value-source ladder:
/// env seat (declared by the env installer), inherit seat (declared by the inherit
/// installer), and default seat. Ladder order is engine-owned (DR-031, invariant ④):
/// cli > env > config > inherit > default (5 段固定、DR-099 が DR-098 の tty 専用席
/// 挿入を撤回)。The inherit seat looks up the nearest ancestor scope's same-named
/// entity value.
pub struct Entity {
  name : String
  ty : Ty
  mut env_key : String? // env seat lookup; None = no env seat declared (env installer sets it)
  // MDR-005 §3: `pub(all)` → `pub` (公開面キュレーション) でフィールドの外部書き込みが無くなり、
  // 元々パッケージ内でも一度も再代入されていなかった (`ensure_entity` が構築時に決め打つだけ) 実装
  // 上のデッドな `mut` だったことが `unused_mut` 検査で顕在化した — 挙動には無関係、宣言を正す。
  config_seat : Bool // config seat declared (DR-050): fill from the config object by path
  config_key : Array[String]? // explicit absolute config path (DR-050 §3); None = 同型 (scope path + name)
  is_config_file : Bool // this cell's value is the config-file PATH (DR-050): resolves the provider, no config seat
  mut inherit_ : Bool // inherit seat declared (inherit installer sets it, DR-031 / DR-013). MDR-003: `inherit` 予約語回避
  // DR-099 §1/§2/§12b: この cell の型が `builtin/tty` preset (`type:` 経由) から来たかのマーカー。
  // true のときだけ `default` 席の解決規則が差し替わる (`resolve.mbt`'s `resolve_ladder_below_cli`) —
  // ラダー自体に tty 専用席は無い (DR-098 §5 の独立席モデルは撤回済み)。`ensure_entity` が
  // `ElemDef.is_tty` からそのまま carry する (installer.mbt、int_round/bool_config と同じ「型
  // shadow から carry するだけの冗長フィールド」パターン)。
  is_tty : Bool
  // DR-099 §3: `builtin/tty` factory の必須 config `tty_stream` — tty_provider へ渡すストリーム識別子
  // ("stdin"|"stdout"|"stderr")。`is_tty` が false の cell では未使用 (冗長フィールド、int_round が
  // TInt 以外で未使用なのと同じ扱い)。`is_tty` かつ None は definition-error で事前に弾かれている
  // はずの防御的状態 (`collect_tty_stream_missing`)。
  tty_stream : String?
  // DR-099 §3: `builtin/tty` factory の config `tty_cygwin` — fold `terminal || (tty_cygwin &&
  // cygwin)` のダイヤル。既定 true。`is_tty` が false の cell では未使用。
  tty_cygwin : Bool
  // The accumulators-registry name (DR-036) that folds this cell's effect list, or None for a
  // scalar cell. Built-ins today: "append" (multiple's value fold, DR-034 — also the repeat
  // installer's own cons-unfold cell as of DR-105 §3, `flatten` field below carries the dial that
  // used to be the standalone "flatten" accumulator name), "merge" (DR-080), "kv_map" (DR-091 §2).
  // Realizes a value LIST here; the name records WHICH registry accumulator so the AST is
  // self-describing (a scalar cell has None).
  accum : String? // None = scalar; Some("append"|"merge"|"kv_map") = accumulate via that registry entry
  // DR-105 §1 flatten dial (append accumulator only, `installer.mbt`'s `ensure_entity` enforces
  // this invariant — a non-append accum cell always carries false here, the definition-error gate
  // `collect_flatten_non_append` rejects any other declared combination before lowering runs):
  // whether an array-shaped fire value gets expanded by ONE level into the accumulated array
  // instead of pushed as a single nested element (`resolve.mbt`'s SEGS-loop per-fire builder is the
  // one reachable consumer today — DR-084 §2's ref+repeat+multiple row array is the only shape in
  // kuu.mbt where a single fire's value is itself array-shaped; `Value` (value.mbt) has no array
  // variant, so a plain scalar multiple cell's fire is never array-shaped and this dial is
  // observationally inert there, DR-105 §1's "非配列 → 丸ごと1要素" clause holds vacuously).
  // `ensure_entity`'s repeat-cons branch (no `multiple` declared) ALSO sets this true unconditionally
  // (DR-105 §3: the old standalone "flatten" accumulator's lowering output is now `append` +
  // `flatten:true`) — `is_multiple_decl` below is what still tells the two origins apart where the
  // distinction actually matters (DR-084 §2's firing-preserving-vs-discard gate).
  flatten : Bool
  // DR-084 §2 origin marker: whether this cell's accumulator seat came from a declared `multiple`
  // (append-preserving-across-firings) as opposed to the repeat installer's own cons-unfold cell
  // (no `multiple` declared, discard-earlier-firings/last-wins-whole-cell — `last-wins-repeat-
  // rows.json`). Before DR-105 this distinction rode on `accum == Some("flatten")` vs not; DR-105 §3
  // collapses both origins onto the SAME accum name ("append") + flatten dial, so `resolve.mbt`'s
  // SEGS-loop gate (`build_result`'s `seg_is_multiple_ref`) needs this independent copy of
  // `ElemDef.multiple` to keep telling them apart (`ensure_entity`'s doc comment / `AccumCell`'s own
  // copy in resolve.mbt).
  is_multiple_decl : Bool
  // DR-036 collector: the T[]→U transform applied to an `accum` cell's FINAL accumulated array
  // (build_result's ACCUMULATE branch, `resolve.mbt`'s `apply_collector`). Only meaningful when
  // `accum is Some(_)` — a scalar cell has no accumulated array to collect from, so this stays
  // None there. `None` here (the common case) means "no collector, render the plain accumulated
  // array" — the multiple registry's `append` preset's `collector: なし` (DR-036 "省略時 accumulator
  // 連動デフォルト"). Only `unwrap_single` is wired end-to-end today (issue
  // 2026-07-09-dec-multiple-collector-decode); `to_set`/`from_entries` are DR-036 registry
  // presets but not reachable through this simple by-name field yet.
  collector : String?
  // DR-083 §1/§波及: default seat, stored as a length-1-degenerate UNIFORM array (`None` = no
  // declared default; a scalar cell's declared default is `Some([v])`, length exactly 1; a
  // `multiple`/repeat/merge (accum) cell's is `Some([v1, v2, ...])`, one piece per declared array
  // element — DR-050 §4's config-array precedent, "already split pieces" per DR-083 §2). Every
  // reader that KNOWS its cell is scalar (bool-target checks, the scalar CLI-seat fold's Unset/
  // Update "old ?? default" arms) takes `vs[0]` (a scalar's array is always length 1 by
  // construction, `ensure_entity`'s only producer). The accum-cell-aware readers (`resolve_ladder_
  // below_cli`'s default seat, `collect_scalar_array_default`'s definition-time gate) iterate the
  // whole array — this single field replaces the pre-DR-083 `default_value : Value?` (a design
  // taken up again after being shelved mid accum-fold-update-default-ops, now justified by DR-083).
  default_values : Array[Value]?
  // DR-034 multiple の separator (issue 2026-07-09-env-separator-split-gap): the env seat's OWN
  // copy, mirroring `piece_filters` below — `resolve.mbt`'s `env_value` runs the pieceProcessor once
  // per piece exactly like `eval.mbt`'s `sep_binds` does for the CLI seat's raw token, but the CLI
  // seat's split already happened upstream (at token-consumption time); the env seat's raw string
  // hasn't been split at all until this field tells `resolve_entity_raw` to. `None` = no separator
  // declared (the common case, and every non-`multiple` cell) — env value stays a single piece.
  separator : String?
  // DR-034/DR-062 piece_filters (String→String, per-piece / pre-parse 相): unlike `value_filters`/
  // `final_filters`/`accum_filters` below (which run AFTER a ladder seat's value is already
  // resolved, in `resolve.mbt`'s `apply_entity_filters`), piece_filters only ever runs BEFORE a
  // string→T parse — i.e. only for STRING-typed ladder inputs. The CLI seat's own piece_filters
  // application happens upstream in eval.mbt/matcher.mbt (token consumption, before the value ever
  // reaches this Entity) — this copy exists so the ladder's OTHER string-sourced seats (env: DR-049
  // §2 "env 値も pieceProcessor を通る") can run the SAME chain via `resolve.mbt`'s `env_value`. A
  // non-string ladder source (config number/bool matching the type, default, inherit) has no parse
  // step to gate, so this field is simply unused there (DR-050 §4's "型一致なら value_filters のみ"
  // — piece_filters/parse は元々 String→T の関数なので、型一致で供給された非 string 値には適用対象
  // が無いという型の帰結、特別規則ではない).
  piece_filters : Array[FilterSpelling]
  // DR-009 value_filters (each, T→T): applied to EVERY value this cell resolves from ANY ladder seat
  // (cli/env/config/inherit/default) right after that seat's own value is determined — same timing
  // "type.parse の後、accumulator の前" DR-009's [4]→[5] describes. For a scalar cell (no accum)
  // this collapses to "applied once, right before final_filters" since only one seat ever wins.
  value_filters : Array[FilterSpelling]
  // DR-009 / DR-102 §1 final_filters (T→T、確定した最終値ガード、non-accum 専用): applied to the
  // FINAL resolved value, after the ladder has picked a winning seat — a scalar (non-accum) cell
  // only. This is the one place both `set` and `update` effects converge before the value leaves
  // resolve_entity (DR-077 §1 "final_filters は update の結果にも通す" の実証対象そのもの、the whole
  // point of this issue). An accum cell (multiple/repeat/separator) leaves this empty — its
  // ARRAY-shaped final gate is `accum_filters` below, applied at build_result instead
  // (`apply_entity_filters` never reaches this field for an accum cell).
  final_filters : Array[FilterSpelling]
  // DR-009 段 7 / DR-102 §1 accum_filters (Acc→Acc、累積配列全体、accum 専用): applied to the WHOLE
  // accumulated array, AFTER accumulation completes (`resolve.mbt`'s `build_result`, via
  // `AccumCell.accum_filters`) — a scalar (non-accum) cell leaves this empty (its T→T final gate is
  // `final_filters` above). 1 属性 1 registry (ARRAY filter registry) の対応 — multiple 有無で
  // registry を切り替える位置依存判定 (DR-101 §3) は本分割で不要化した。
  accum_filters : Array[FilterSpelling]
  // DR-058 §1 / DR-104 §2: whether this element is excluded from help/補完 の既定表示
  // (`CandMeta.hidden`, `ElemDef.hidden` からそのまま carry — `is_tty`/`int_round` と同じ
  // 「冗長フィールドをそのまま運ぶだけ」パターン)。complete() 自身はこの値に関わらず候補を返す
  // (DR-060 §3「素材とポリシーの分離」、既定除外は生成器の関心)。name-keyed lookup で足りる —
  // alias と違い、hidden は要素そのものの属性であって spelling ごとに変わらない前提 (現行 fixture
  // に alias 側の独立 hidden を要求するものは無い)。
  hidden : Bool
  // DR-060 §4 / DR-104 §2(d) / issue 2026-07-14-cand-completer-followup: the registry name of the
  // dynamic completer this cell's value slot delegates to (`completer: "<名前>"` wire attribute,
  // `ElemDef.completer` からそのまま carry — `hidden` と同じ「冗長フィールドをそのまま運ぶだけ」
  // パターン)。`None` = no completer declared. Read by `complete_tree`'s post-dedup pass
  // (outcome.mbt) via a name-keyed Entity lookup — NOT threaded through the value-primitive Node
  // constructors (StrArg/NumArg/…) themselves, because every value-primitive call site would
  // otherwise need its own completer plumbing (30+ sites across eval.mbt/matcher.mbt) for a value
  // that is always determined by `origin` alone (same Entity, same completer, by construction —
  // `ensure_entity` only ever creates ONE Entity per name). This is the structural reason DR-104
  // §3's "merge rule for a completer-only divergent duplicate" never actually fires under this
  // implementation: two candidates that dedup-match on the existing 6 fields always share the same
  // `origin`, hence the same Entity, hence the same completer — there is no live path that produces
  // a genuine conflict to merge.
  completer : String?
} derive(Eq, Debug)

///|
/// A long-option entry the eq-split matcher can resolve (`--key=value`). `int_round` /
/// `allow_base_prefix` / `bool_config` carry the element's DR-075 / DR-074 §2/§4 factory config into
/// the eq-split path (space form runs the greedy Num/IntArg/BoolArg node which already carries this
/// config; eq-split needs its own copy since the entry table is the only channel run_eq_split reads).
/// `int_round` は TInt のみ、`allow_base_prefix` は TNum / TInt、`bool_config` は TBool のみが参照する
/// (DR-076 §1/§3: bool の eq-split `--enabled=true` は variant 綴りと共存する — TFlag と違い抑制
/// されない)。他 kind は無視。
pub struct LongEntry {
  key : String
  name : String
  kind : Ty
  int_round : RoundMode
  allow_base_prefix : Bool
  bool_config : BoolConfig
  // DR-034/DR-062 piece_filters (same carrier pattern as `int_round`/`allow_base_prefix`): run_eq_split
  // (matcher.mbt) applies it to `valstr` before the kind-specific parse. Ignored for TFlag/TCount
  // (no eq-split value slot to gate — a presence-only fire has no raw string to filter).
  piece_filters : Array[FilterSpelling]
  // DR-034 separator (issue 2026-07-09-separator-non-string-type-parse-gap 段1): `--key=a,b` eq-split
  // form goes through the SAME pieceProcessor as the space form — separator splitting is a value-
  // axis concern independent of which entry point supplied the raw string (DR-034, matcher-readings/
  // entry-forms.json's "入口形に関わらず同じ pieceProcessor 管を通る" precedent for piece_filters
  // applies identically here). `None` = no split (single-piece degenerate, DR-034 §6.3).
  separator : String?
  // DR-080 波及節: `ElemDef.accumulator == Some("merge")` — the eq-split form (`--key=a,-a`) shares
  // the SAME `sep_binds` pieceProcessor as the space form, so it needs the same merge-marker flag
  // (same rationale as `separator` above: the entry point doesn't change the value-axis pipeline).
  merge : Bool
  // codex レビュー Major 1 (issue 2026-07-15-audit-node-nodashstr-deprmark-variants 副次発見) / DR-058
  // §2: this entry-copy is a deprecated (canonical or alias, DR-057 §3) entry — firing the eq-split
  // form emits a `@depr:<name>` warning marker, same standing as `ShortEntry.depr` (this field's doc
  // comment). DR-058 §2 draws no入口形 distinction (space form / eq-split / short cluster all warn
  // alike) — `run_eq_split` (matcher.mbt) was the one entry point missing this carrier before this
  // fix (the space form already threads it via `installer.mbt`'s `DeprMark` satellite append, short
  // via this field's `ShortEntry` sibling).
  depr : Bool
} derive(Eq, Debug)

///|
/// A short-option entry the cluster matcher can resolve (`-abc`, `-n1.0`).
/// `depr` (DR-057/058): this entry is a deprecated alias spelling — firing it emits a `@depr:<name>`
/// warning marker (the value binding is unchanged). Only a deprecated ALIAS sets it; a canonical or
/// non-deprecated alias short has `depr: false`.
pub struct ShortEntry {
  ch : Char
  name : String
  kind : Ty
  depr : Bool
  // DR-075 int_round + DR-074 §2 allow_base_prefix: short cluster / space-tail の値 parse に運ぶ
  // (LongEntry と同型)。int_round は TInt のみ、allow_base_prefix は TNum/TInt が参照。
  int_round : RoundMode
  allow_base_prefix : Bool
  // DR-034/DR-062 piece_filters (same carrier pattern as LongEntry): `short_val` (matcher.mbt) applies
  // it to the in-cluster/space-form value string before the kind-specific parse. Ignored for
  // TFlag/TBool/TCount (no in-cluster/space-form VALUE attachment for those — `short_val` already
  // returns None unconditionally for them).
  piece_filters : Array[FilterSpelling]
  // DR-034 separator (issue 2026-07-09-separator-non-string-type-parse-gap 段1, same rationale as
  // LongEntry's field): in-cluster (`-p5,7`) and space-form (`-p 5,7`) both go through the same
  // pieceProcessor as the long-option space form. `None` = no split.
  separator : String?
  // DR-080 波及節 (same rationale as LongEntry's field): `ElemDef.accumulator == Some("merge")`.
  merge : Bool
  // DESIGN §7.2 / DR-096 §2 (kawaz 裁定 2026-07-12 で `AtLastOnly` 追加): gates whether `walk_short`
  // may read this entry's value via in-cluster attach (`-O2`) vs. next-token space form (`-O 2`).
  // `AtRequire` withholds the space-form reading, `AtDeny` withholds the attach reading (both the
  // mid-token AND full-tail-length attach, plus the cluster-tail attach — DR-096 §3.1「付着という
  // 機構自体をダイヤルしているのであって、単独発火時に限る規定ではない」), `AtLastOnly` withholds
  // every MID-token split attach (only the full-tail "丸取り" reading remains — GNU getopt 慣習の
  // 分割 ambiguity 抑制), `AtAllow` (既定) withholds neither (`walk_short`, matcher.mbt, is the sole
  // consumer). Ignored for TFlag/TBool/TCount/TNone entries (DR-096 §3.2 inert — those kinds never
  // reach `short_val`'s in-cluster/space-form value attachment in the first place).
  short_attached_value : AttachMode
  // DR-057 / DR-104 §2/§3: this entry is an alias入口 (canonical と別 spelling で同じ origin name
  // へ束縛される、`CandMeta.is_alias`)。dedup 規則 (DR-104 §3) は spelling を含む組の完全一致なので、
  // is_alias は spelling ごとに独立して立つ (canonical -p は false、alias -n/-o は true) — `depr` と
  // 同じ carrier パターン。
  is_alias : Bool
} derive(Eq, Debug)

///|
/// A native matcher (DR-041): reified token-reading capability as DATA.
/// The evaluator interprets it (`run_matcher`); installers construct it from
/// the collected entry table (DR-042: "回収したエントリ表が matcher の構成データ").
pub enum Matcher {
  /// `--key=value` split. Fires only on tokens containing `=`. Undefined key = no reading (素通し).
  EqSplit(prefix~ : String, entries~ : Array[LongEntry])
  /// `-abc` cluster + value attachment. Enumerates ALL readings (DR-041 §3-4); ambiguous defs
  /// (the `-cv` problem) surface as multiple readings that both complete. `combine` (DR-014「-abc
  /// の結合許可」, DESIGN §7.2 scope config `short_combine`, issue scope-config-object-gap 解釈A
  /// team-lead 裁定 2026-07-11): when `false`, only a SINGLE short entry may occupy a token —
  /// multi-entry clustering (`-ab` → 2 entries in 1 token) is withheld, while a lone flag fire
  /// (`-p`) and a value-attach that consumes the ENTIRE token tail (`-p80`, no leftover chars for a
  /// further entry to combine with) remain unaffected (`run_short`/`walk_short`, matcher.mbt, is the
  /// sole consumer). Internal-only parameter — never projected into a lowering fixture's golden
  ///断面 (`proj_greedy`'s `NativeMatch(ShortCombine(prefix=_, entries~))` arm in
  /// json_conformance_wbtest.mbt already discards `prefix` too, DR-070 §2 loose compare: matcher
  /// kind + entry table only). 既定 `true` (現行の cluster/値付着 全読み挙動は不変)。
  ShortCombine(prefix~ : String, entries~ : Array[ShortEntry], combine~ : Bool)
} derive(Eq, Debug)

// ── completion candidate 型 (DR-060 §3) — 型のみ移植 (slice complete.mbt 1-57) ─
// The completion走査 (comp_scope 等) is outcome.mbt's job (MDR-002 §3); only the DATA the
// evaluator's `Pending` branch carries lives here. `Cand` uses `Ty`, so it sits beside it.

///|
/// A terminal hint on an exact candidate (DR-060 §3): `WordEnd` = 確定, a space may follow; `Cont` =
/// 継続, no space (a value must follow — e.g. a value-taking --port, or a `--key=` / dir `/` in prod).
pub(all) enum TermHint {
  WordEnd
  Cont
} derive(Eq, Debug)

///|
/// Declaration-layer meta a completion reads by reference (DR-056 / DR-057 / DR-058): whether a
/// spelling is an alias entry, hidden (excluded from candidates by default, kept in meta), deprecated.
pub(all) struct CandMeta {
  is_alias : Bool
  hidden : Bool
  deprecated : Bool
} derive(Eq, Debug)

///|
/// A completion candidate (DR-060 §3): either an exact trigger spelling, or a value position (type +
/// completer名, PoC shows the type). Meta rides alongside; policy / replacement / landing is the
/// generator's & shell's (kuu returns素材 only).
///
/// `path` (DR-066 §4, issue 2026-07-08 pending-starvation-missing-operand-path): root-first ancestor
/// scope names, mirroring `ParseError.path`'s snoc form ([] = root 直下). `origin` already answers
/// "which element" a candidate came from; `path` answers "under which ancestor scopes" — the same
/// pairing `ParseError` uses (`element` + `path`). Threaded the SAME way Held's path is (starts `[]`
/// at construction, `nest_branches`/CmdSat prepend the traversed scope labels on the way out) so a
/// `Pending`'s value-slot candidate can be converted to a `missing_operand` `ParseError` (parse()
/// top-level, DR-053 §2.3) WITHOUT losing the ancestor path the way it used to (Held already worked;
/// Pending — parse mode's other failure carrier — did not, because prepend only touched Held). Also
/// carried by the exact-trigger (`is_value:false`) candidates for consistency, even though those
/// never feed `missing_operand` today — DR-060's completion consumers are free to ignore the field
/// (additive, not a breaking change to the §3 candidate structure).
pub(all) struct Cand {
  spelling : String // the exact spelling; "" for a value position
  is_value : Bool
  ty : Ty // for a value position
  origin : String // the element name it came from
  term : TermHint
  meta : CandMeta
  path : Array[String] // DR-066 §4: root-first ancestor scope names (snoc form, [] = root 直下)
  // Rooted-escape counter for `path`, mirroring `Binding.link` (DR-042 global link-sync): a
  // global option's satellite is copied into a descendant command scope wrapped in
  // `Rooted(node, depth)`, and its Entity lives ONLY at the declaring (shallower) scope — a
  // value-slot Pending produced from inside that copy must therefore have `depth` levels of
  // CmdSat-boundary prepend SKIPPED, or its `path` ends up pointing at the wrong (copy-side)
  // scope while the Entity it names sits at the declaring scope. Bare `Array[String]` path alone
  // cannot express "skip N prepends" — `nest_cands` (eval.mbt) consumes this exactly like
  // `nest`'s own `Binding.link` decrement, so the two stay in lockstep. `0` (the common case) =
  // no pending escape, prepend normally. NOT part of the 6-field dedup identity or the wire
  // projection (same posture as `path` itself, DR-104 §2/§3) — purely an implementation detail of
  // `complete_tree`'s completer lookup (outcome.mbt).
  link : Int
  // issue 2026-07-15-pending-parseerror-path-asymmetry (DR-066 §4): the FIRE-TIME walk-position
  // path — root-first ancestor scope names, prepended UNCONDITIONALLY as the branch rides out
  // through each CmdSat boundary (`nest_path`, the SAME no-exception rule a Held's `ParseError.path`
  // already follows). Deliberately a SEPARATE field from `path` above: `path`'s Rooted-escape skip
  // (`link`) answers "where does complete_tree's completer lookup find this candidate's declaring
  // Entity" (a completion-only question), while `fire_path` answers "which scope was this candidate
  // actually read under" (the question `missing_operand`'s `ParseError.path` needs, DR-066 §4's own
  // "発火時の動的パス" wording). Adversarial verification (installer_wbtest.mbt debug probes, this
  // issue) found `link` is ALWAYS 0 by the time a Pending reaches KTop — a Rooted candidate's escape
  // counter is fully consumed by the SAME CmdSat boundaries `path` needs prepended, so gating KTop's
  // conversion on `c.link > 0` (the originally proposed fix) is a no-op: nothing is ever excluded,
  // and the wrong-path duplicate survives with `link` already 0. `fire_path` sidesteps the escape
  // bookkeeping entirely by tracking the walk position directly, so KTop's missing_operand conversion
  // reads THIS field instead of `path` — every duplicate reading of the same starved slot (root-copy,
  // mid-scope re-evaluation, or the correct innermost one) ends up with the SAME `fire_path` (they
  // all fired at the same token position under the same walk), so `push_error`'s 5-field dedup
  // collapses them to one instead of leaving path-mismatched duplicates. NOT part of the 6-field dedup
  // identity or the wire projection (same posture as `path`/`link` — purely an internal routing aid).
  fire_path : Array[String]
  // DR-060 §3 "値位置: 型情報 + completer 名" / DR-104 §2/§3: the dynamic completer name for a
  // VALUE-position candidate (`is_value:true`); always `None` on an exact-trigger candidate (DR-060
  // §3 does not attach a completer to a spelling). Deliberately NOT part of the 6-field dedup
  // identity (DR-104 §3 "`completer` は同一性の成分ではない") — every `pend_value` call site keeps
  // constructing `None` here (no Entity table is in scope at any of those 30+ sites); `complete_tree`
  // (outcome.mbt) fills it in via a `(path, origin)`-keyed lookup into the tree's Entity table
  // (`collect_all_entities`) as each candidate is folded into the dedup loop — keyed by `path` (not
  // bare `origin`) because two structurally independent scopes can each declare their own Entity
  // under the SAME name with a DIFFERENT completer, and a bare-name lookup could not tell them
  // apart. When two candidates dedup-match on the 6-field identity but resolve to different
  // completers via their distinct paths, the merge rule (DR-104 §3 明確化 note) folds them to
  // `None` — see `complete_tree`'s dedup loop.
  completer : String?
} derive(Eq, Debug)

///|
/// The outcome of trying a node against a token prefix (MDR-002 §2.1). A missing branch == Reject
/// (silently dropped, DR-037); `Held` == Error (retained for failure display); `Accept(pos, binds)`
/// == a reading; `Pending(cands, binds)` == トリガ消費・値 pending (parse では Held 相当、complete では
/// 補完候補の源, MDR-002 §2 案B). The matcher only CONSTRUCTS Accept/Held; the evaluator produces and
/// consumes Pending. (Kept in node.mbt so both matcher and eval can return it; single package.)
enum Branch {
  Accept(Int, Array[Binding]) // (new position, accumulated bindings)
  Held(ParseError, Array[Binding]) // a DR-037 Error + the partial state (acc) at the error point
  Pending(Array[Cand], Array[Binding]) // trigger consumed, value slot's input absent
} derive(Debug)
