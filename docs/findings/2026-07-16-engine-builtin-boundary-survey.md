# engine/builtins/kuu 分離: 境界争点の全列挙調査

- **調査日**: 2026-07-16
- **調査対象**: `src/core/*.mbt` (実装 12 ファイル / 33774 行) + `docs/decisions/DR-*.md` (spec 側 109 DR)
- **委譲元**: kuu-core 立て直し (engine/builtins/kuu の package 分離) の PKG-Q 裁定バッチ組成のための輪郭調査 (kawaz 裁定 2026-07-16 由来)
- **範囲**: 読み専 (ファイル編集禁止)、engine/builtins の境界線で設計判断が要る箇所の全列挙
- **成果物形式**: 争点リスト (番号付き、独立に裁定可能な粒度) + 自明帰属 + 依存関係

## 前提整理

現状は **1 core package** (`src/core/moon.pkg`) に 12 mbt が同居:

- 実装ファイル: node / value / matcher / eval / filters / installer / resolve / wire_decode / outcome / front_door / cont / core
- wbtest: `*_wbtest.mbt` (11 本、conformance runner 含む)

現行 `moon.pkg` は `moonbitlang/core/string` のみ import。MDR-002 §3 が「node/value → matcher → resolve → eval → installer → outcome → front_door」の module 依存順を明文化しているが、**package 分離はまだしていない** — 同一 package 内の soft convention。

分離目標 (kawaz 裁定 2026-07-16):

- **engine** = パース機構 + registry 機構 + descriptor 契約のみ、installer 語彙も builtin 型も知らない
- **builtins** = long/short/env installer 群、bool/number parser、trim/in_range filter 等 — engine の公開 extension interface **だけ**を使って 3rd と同じ目線で実装
- **kuu** = 電池入り assembly、front_door の顔

根拠: DR-028 (組み込み型 = 最初から登録済みのプリセット)、DR-094 (builtin = ただの ns)、DR-061 / DR-095 / DR-107 (全住人が descriptor を持つ)。spec 上 builtin に構造的特権は無いのに、参照実装だけがエンジン直書きの特権を与えている — これを正す。

---

## 自明な帰属 (議論不要)

### engine 残留が明白

| 対象 | 場所 | 根拠 |
|---|---|---|
| eval のパス探索 (scope_consume / scope_step / step_greedy / ref_choice / bounded_tail_step / scope_consume_rep) | eval.mbt:1432-3070 | DR-038 / DR-041 / DR-043 は engine 契約 (完全経路数で outcome、CPS) |
| Ctx / EvalMode / Branch (Accept/Held/Pending) 生成規則 | eval.mbt:33-51, node.mbt:761 | MDR-002 §2 の evaluator 契約 |
| nest / nest_path / nest_cands / nest_branches (scope 昇降 + Rooted escape) | eval.mbt:227-317 | DR-025 / DR-042 / DR-066 の scope 昇降は engine が担う |
| run_matcher の interpretation ループ (行き先 matcher に投げるだけ) | matcher.mbt:66-75 | DR-041 §3 の「全 reading 平等」 |
| RVal / build_result の一般 array/object 構築 | resolve.mbt:28-32, 516-848 | 結果 shape の一般構築 |
| apply_export_keys / apply_export_to_defaults (DR-052 一般写像) | resolve.mbt:267-331 | DR-052 は engine 契約 |
| export-key collision 検出 (DR-073) | resolve.mbt:1244-1481 | DR-073 は engine 契約 |
| complete_tree / Entity テーブル走査 (Cand の post-dedup) | outcome.mbt:303-540 | DR-060 §3 は engine 契約 |
| front_door の parse / resolve / complete 3 契約 | front_door.mbt:71-257 | DR-053 / DR-054 / DR-060 (VISION §2) は engine 顔 |
| config_from_json (JSON → ConfigVal 全域写像) | front_door.mbt:317-351 | 純データ変換 |

### builtins 帰属が明白

| 対象 | 場所 | 根拠 |
|---|---|---|
| 個別 installer 実装 (inst_long / inst_short / inst_env / inst_dd / inst_global / inst_inherit / inst_inheritable / inst_constraint) | installer.mbt:1665-2692 | 各 installer が special vocab を READ する具象実装 (DR-042) |
| normalize_surface / normalize_option / normalize_dd_name / resolve_long / classify_long_spelling / desugar_aliases | installer.mbt:881-2969 | wire 二形 / colon DSL 分類 / flag/count 糖衣 / alias 展開 = 全て builtin 語彙 (DR-011 / DR-057 / DR-071 / DR-076 / DR-077) |
| canonical 字句 parser (parse_number / parse_int_value / parse_float / parse_bool / parse_number_ext / parse_int_value_ext / parse_bool_ext) | value.mbt:685-1289 | DR-074 / DR-075 canonical lexicon = builtin 型の値空間仕様 |
| filter 実装 5 本 (filter_trim / filter_non_empty / filter_in_range / filter_regex_match / filter_increment) + array_filter (unique / length_range) | filters.mbt:61-373 | 個別 descriptor 実装 |
| accumulator 名 3 種の resolve 側実装 (append の fold, resolve_merge_accum, kv_map の RObj 分岐) | resolve.mbt:2959-3135, 662-741 | 個別住人の意味論 |
| TypeShadow decode (`int_parser` / `number_parser` / `bool_parser` / `tty` / `builtin/*` factory 名) | wire_decode.mbt:807-1084 | builtin 型 factory の decode 語彙 |

---

## 争点リスト (独立に裁定可能な粒度)

### PKG-#1: Node ADT の帰属モデル (根本判断)

**箇所**: node.mbt:110-335 (`enum Node` の 27 variant)

**直書き**: `Exact / StrArg / SepArg / KvArg / NumArg / FloatArg / IntArg / BoolArg / FilterArg / ReqArg / Bind / EffMark / DeprMark / FailMark / Or / Seq / Many / Scoped / ScopeNode / NativeMatch / Ref / DdSat / DdMatchSat / CmdSat / Rooted / BoundedTail / IdxRepeat / GreedyRepeat` — このうち engine 純粋 (Exact / Or / Seq / Ref / ScopeNode / Bind / Many / BoundedTail / Rooted / Scoped) と builtin lowering 産物 (StrArg / SepArg / KvArg / NumArg / FloatArg / IntArg / BoolArg / FilterArg / ReqArg / EffMark / DeprMark / FailMark / DdSat / DdMatchSat / CmdSat / NativeMatch / GreedyRepeat / IdxRepeat) が同居。

**spec 帰属**: DR-039 は「AtomicAST = declarative serialization of the bottom-up engine's node graph」→ Node ADT 自体は engine の関心と読める。ただし DR-041 §3-4 「matchers add reading capability WITHOUT adding schema」は matchers を engine 外に出せる示唆。

**分離案**:

- **A**. 全 Node variant を engine に残す (現状に近い、eval が全 variant を case 分岐)
- **B**. Node を open (trait / registry 化); engine は Ref / Or / Seq / ScopeNode / Bind / Many / BoundedTail / Scoped / Rooted のみ内蔵、値プリミティブ (StrArg…) と 0-token マーカー (EffMark / FailMark / DeprMark) と satellite (DdSat / CmdSat / NativeMatch) は builtin 拡張
- **C**. AtomicAST を JSON-同型 struct のみ engine に公開し、eval 実装は builtin に閉じ込める

**依存**: PKG-#3 / #4 / #5 / #8 / #14 の全てがこれで連動決定される。**先に裁定すべき争点**。

---

### PKG-#2: eval.mbt の値プリミティブ arm (7 種) の帰属

**箇所**: eval.mbt:402-524 (StrArg / KvArg / SepArg / NumArg / FloatArg / IntArg / BoolArg の match arm)

**直書き**: 各 arm で `apply_piece_filters` → 型別 parser (`parse_number_ext` / `parse_int_value_ext` / `parse_float` / `parse_bool_ext`) を直接呼ぶ。arm 内に「型ごとの Held Error 生成 (pe_parse / pe_parse_int / pe_int_out_of_range / pe_parse_bool)」も直書き。KvArg は eval.mbt:419 で `contains_eq` の gate を持つ (DR-091 §2)。

**spec 帰属**: 値の型解釈は DR-061 §4 「factory config は factory 自身が検証」の管掌 = builtin 側。engine は「値スロットに読む」機構だけ持つ想定。

**分離案**:

- **A**. Node variant を保ちつつ、eval の値 arm を「value_parser lookup」に還元 (Node は `TypedValueArg(kind_id, config)` 的な 1 variant に統合)
- **B**. 現行の型別 variant を保ち、arm 内の parser 呼び出しを "engine が知る parser interface" 経由に (Ty → parser の resolve は engine 内で hard-coded)
- **C**. 現状維持 (エンジンが全型を知る)

**依存**: PKG-#1 (Node open 化) と直結。PKG-#8 と PKG-#12 (value_parser registry) にも波及。

---

### PKG-#3: sentinel 綴りの帰属分割

**箇所**:

- installer が生成: `"#row"` (installer.mbt:1084 `ref_row_head`), `"#fire"` (installer.mbt:1780 `inst_long`), `"#cons"` (installer.mbt:1195 `lower_repeat_head`), `"lazy:" + name` (installer.mbt:1199)
- eval が生成: `"@depr:" + name` (value.mbt:1691 `depr_marker`), `"@act:" + name` (eval.mbt:118 `action_marker`), `"[]"` / `"{}"` (eval.mbt:322-346 array_marker / scope_marker), `"#" + k` (eval.mbt:1001 `nest_index`)
- resolve が消費: 全部 (resolve.mbt:74 `is_sentinel`)
- eval が消費: `is_depr_key` / `is_action_key` (eval.mbt:130-220)

**問題**: sentinel は「lowering の shape と evaluator が同期して知る」ペアだが、engine 側からは意味を持たない命名規約。ところが is_zero_token_marker (eval.mbt:1358) は EffMark / FailMark / DeprMark に自身で反応 — engine が builtin 語彙を暗黙に知る証拠。

**spec 帰属**: DR-078 §1 (`#row`), DR-058 (`@depr:`), DR-048 (`@act:`), DR-034 last-wins (`#fire`) は全て builtin 意味論。

**分離案**:

- **A**. sentinel を builtin 内部語彙に閉じ、engine は「特別キー」フラグ (Binding に `is_meta: bool` 追加) だけ持つ
- **B**. sentinel を engine の 1 等市民化 (別 Binding tag: MetaBinding として型分離)
- **C**. 現状維持 (engine が sentinel prefix を知る)

**依存**: PKG-#15 (`is_sentinel` pub 契約) と一体。

---

### PKG-#4: Ty enum の分割 — presence-only kind の帰属

**箇所**: node.mbt:65-88 (`enum Ty { TStr / TNum / TInt / TFloat / TFlag / TBool / TCount / TNone }`)

**直書き**:

- `TFlag`: normalize_option (installer.mbt:927) で TBool に collapse。matcher.mbt:157 / 447-464 で "presence-only" 特殊分岐
- `TCount`: ensure_entity (installer.mbt:1558) で TNum に collapse (「TCount タグは chain 中ずっと保持」がコメントで明言、installer.mbt:906-911)。matcher.mbt:161 / 465-482 で "非消費 + update(increment) 効果"
- `TNone`: DR-089 の「値空間なし」、複数の collect_* / eval / matcher / build_result で "値スロット無し" として case 分岐 (installer.mbt:3831, matcher.mbt:396 / 447, resolve.mbt:1132-1201)

**spec 帰属**: TFlag / TCount は完全に builtin 語彙 (DR-076 / DR-077 の糖衣)。TNone は DR-089 で「type 省略の糖衣」= builtin 型契約。

**分離案**:

- **A**. Ty を engine に残し、TFlag / TCount / TNone は "builtin 型カテゴリ" として engine が知る (現状)
- **B**. Ty を engine から追い出し、Node variant 側に `kind_config` として運ぶ (matcher / eval は直接 kind 名を case 分岐しない)
- **C**. 中間案: engine の Ty は TStr / TNum / TInt / TFloat / TBool の 5 種 (値空間のある型) のみ、presence-only や TNone は Node variant 側の bool フラグに

**依存**: PKG-#1 / #5 と直結。

---

### PKG-#5: matcher.mbt の型別特殊分岐 (walk_short / run_eq_split)

**箇所**:

- matcher.mbt:157 `run_eq_split`: `if e.kind == TFlag return []` / `if e.kind == TCount return []` / `TNone => return []`
- matcher.mbt:442-482 `walk_short`: TFlag / TBool / TNone → presence-only (mkb VBool(true))、TCount → `mk_eff(name, Update("increment", []), Cli)` を直接生成
- matcher.mbt:396 `short_val`: TFlag / TBool / TCount / TNone は unreachable として pe_parse で防御

**問題**: matcher が「値スロットを持たない kind」の意味論を **完全に knowledge として抱えている**。特に `mk_eff(Update("increment", []))` は count 型が update effect を運ぶ builtin 契約 (DR-077 §3) を engine 内 matcher が直書きする最悪の癒着。

**spec 帰属**: DR-076 / DR-077 の糖衣は完全 builtin 契約。DR-074 §3 の "TBool は value-typed" も builtin 型契約。

**分離案**:

- **A**. matcher を engine から追い出し、builtin 側の "short/long installer が Matcher の consumer を提供" (matcher = installer 内)
- **B**. matcher は engine 骨格として残し、"value slot 有無" だけ Node / ShortEntry / LongEntry 側の bool フラグに (kind ベース分岐を排除)
- **C**. 現状維持

**依存**: PKG-#4 と一体。分離案 A は PKG-#6 と一体。

---

### PKG-#6: LongEntry / ShortEntry / Matcher enum の帰属

**箇所**: node.mbt:570-662 (`struct LongEntry` 12 フィールド + `struct ShortEntry` 12 フィールド + `enum Matcher { EqSplit / ShortCombine }`)

**直書き**: LongEntry / ShortEntry は Ty (kind)、RoundMode / BoolConfig / AttachMode などの builtin 型 config を carrier として搭載。inst_long / inst_short が構築し、matcher.mbt が消費 (installer.mbt:1665-2083 / matcher.mbt:134-561)。

**spec 帰属**: DR-041 §3-4 「matchers add capability」は仕様側で matcher の抽象を規定する一方、具体的な "long eq-split" / "short combine" は builtin 語彙。

**分離案**:

- **A**. LongEntry / ShortEntry / Matcher enum を builtin 側に移し、engine は `NativeMatch(opaque)` の opaque data と `interpret: (opaque, tok, pos) → Array[Branch]` の pluggable callback を持つ
- **B**. Matcher の抽象を engine が固定 (EqSplit / ShortCombine の 2 種で spec 上足りるかは要検討)
- **C**. 現状維持 (engine が両 matcher を知る)

**依存**: PKG-#5 と一体。

---

### PKG-#7: value.mbt の scope config 型 (EqSepMode / AttachMode / BoolConfig / RoundMode) の帰属

**箇所**: value.mbt:57-150 (RoundMode 10 mode + EqSepMode 3 値 + AttachMode 4 値 + BoolConfig struct)

**直書き**: これらは全て ElemDef / Entity / LongEntry / ShortEntry / IntArg / NumArg / BoolArg の carrier フィールドとして運ばれる。engine 純粋なら Entity は「name / ty / seat 宣言」のみで、これらの config は builtin 型 descriptor が保持するはずのもの。

**spec 帰属**: 全て DR-096 (EqSepMode / AttachMode)、DR-074 / DR-075 (BoolConfig / RoundMode) の builtin 型契約。

**分離案**:

- **A**. 全 config 型を builtin に移し、engine は unknown-config を素通し
- **B**. engine に「builtin config type map」を持ち、外部から拡張可能に
- **C**. 現状維持

**依存**: PKG-#14 (Entity carrier フィールド) と一体。

---

### PKG-#8: 定義時検査 (collect_*) 20+ 群の帰属分割

**箇所**: installer.mbt:3016-4410 に 22 個の `collect_*` 関数:

- `collect_vocab_intersection` / `collect_unknown_vocab` — **真に generic** (installer chain の invariants)
- 残り 20 個 — 全て特定 installer / 特定型 / 特定 builtin 意味論:
  - `collect_invalid_long_dsl` / `collect_invalid_alias_long_override` (long DSL)
  - `collect_tty_stream_missing` (tty preset)
  - `collect_zero_progress` / `collect_circular_ref` / `collect_absent_ref` (repeat / ref)
  - `collect_config_cycle` (config_file)
  - `collect_invalid_range` (repeat min/max)
  - `collect_unsupported_option_ref_repeat` / `collect_unsupported_accum_update` / `collect_unsupported_count_multiple` (組合せ制約)
  - `collect_scalar_array_default` (DR-083)
  - `collect_none_value_source_decl` (TNone)
  - `collect_unknown_filter` / `collect_invalid_filter_attribute_mismatch` / `collect_invalid_regex_pattern` / `collect_invalid_numeric_filter_args` (filter registry)
  - `collect_invalid_dd_pattern` (dd 語彙)
  - `collect_ref_merge_accum` / `collect_flatten_non_append` / `collect_unknown_accumulator` (accumulator registry)

**spec 帰属**: DR-054 は「definition-error を列挙する」engine 契約を規定するが、**個々の検査規則の中身は builtin 意味論**。

**分離案**:

- **A**. 各検査を対応する installer に持たせ、engine は「chain の各 installer に `collect_defs_errors` を呼ぶ」インターフェースだけ持つ (真に generic な 2 個は engine 内)
- **B**. 全検査を builtin 側の 1 モジュールに集約、engine は Result 型だけ提供
- **C**. 現状維持

**依存**: PKG-#1 / #4 (Node / Ty の帰属) と一体。

---

### PKG-#9: full_installers() と canonical set 13 種の帰属

**箇所**:

- wire_decode.mbt:434-450 `full_installers()`: 13 種を hard-coded 順で返す
- installer.mbt:582-596 `enum Installer` に 13 値 (LongInst / ShortInst / EnvInst / DdInst / CommandInst / GlobalInst / InheritInst / RepeatInst / MultipleInst / ConfigInst / ConstraintInst / AliasInst / InheritableInst)
- installer.mbt:599-615 `owned_vocab` で 13 vocab 名の hard-coded 写像

**spec 帰属**: DR-042 は "canonical installer set" を仕様側で規定するが、chain 内容は application の選択 (registry pattern と対等)。

**分離案**:

- **A**. `Installer` enum を engine から追い出し、engine 側は「install 契約 (owned_vocab: String, apply: (SB) → Unit, collect_defs_errors: (Def) → Array[DefError])」の trait だけ持つ
- **B**. Installer enum を engine の骨格として残し、`full_installers()` は builtin 提供
- **C**. 現状維持

**依存**: PKG-#8 / #14 と一体。

---

### PKG-#10: entity ensure と登録 (ensure_entity_body / ensure_entity)

**箇所**: installer.mbt:1407-1609. 特に `ensure_entity` は「flag preset (default:false)、count preset (default:0)、accumulator の "append" / "merge" / "kv_map" 3 値写像、config_seat の同型注入、flatten dial、tty preset」を全て直書き。

**spec 帰属**: DR-105 §1 / §3 (flatten / accum name), DR-050 §3 (config_seat), DR-099 (tty), DR-076 / DR-077 (flag / count preset) — 全て builtin 意味論。

**分離案**:

- **A**. ensure_entity 相当を "installer chain 内の各住人が自 seat を宣言する" 分散型に (現状は installer が seat を宣言するが、Entity 自体は engine が構築)
- **B**. Entity struct を builtin 側の型にし、engine は "opaque entity" のみ扱う
- **C**. 現状維持 (engine が Entity 構造を知る)

**依存**: PKG-#14 (Entity carrier フィールド) と一体。

---

### PKG-#11: value-source ladder (resolve_ladder_below_cli) の 5-seat 固定 + tty 席の意味論埋込

**箇所**: resolve.mbt:2754-2932

**直書き**: env → config → inherit → tty → default の順序、および tty 席の "fold(観測) ?? 宣言 default ?? absent" 規則 (DR-099 §2)、TFlag / TCount の暗黙 preset (default:false / default:0) の解決規則。tty_provider の signature (`Map[String, TtyObs]`) と env_provider (`Map[String, String]`) と config_provider (`(path: String) → ConfigVal?`) の 3 種を engine が引数として受ける。

**spec 帰属**: DR-031 「ladder order is engine-owned」→ 5 段固定は engine 契約。ただし tty 席の特殊解決 (DR-099 §2) と flag / count preset (DR-076 / DR-077) は builtin 意味論。

**分離案**:

- **A**. 5-seat ladder を engine 骨格として残し、各席の provider は builtin (現状に近い)
- **B**. tty preset の "fold ?? default" 規則を Entity descriptor 側に移し、engine は "この Entity の default 席の解決子" を builtin descriptor から dispatch
- **C**. ladder 自体を pluggable に (spec の帰属を DR で改めて確認)

**依存**: PKG-#14 (Entity carrier)、PKG-#7 (config 型) と一体。

---

### PKG-#12: filter registry の pluggability

**箇所**: filters.mbt:240-289 (`filters_registry()` / `lookup_filter`) + filters.mbt:399-428 (`array_filters_registry()` / `lookup_array_filter`)

**直書き**:

- **fresh Map per call** で構築 (「registry」というより hard-coded 選択)
- filters.mbt:5-17 のヘッダーコメントに「full multi-host DR-010 registry machinery (tree-shake / Level 0-3 dynamic injection / explicit opt-in extension tiers — those are language-DX concerns for OTHER host bindings, moot for a single MoonBit reference implementation)」と明言、tree-shake も無い

**spec 帰属**: DR-010 (filter registry の 3 tier + inheritance)、DR-062 (`{prepend, append}` composition) — 現状は全て out of scope 宣言。

**分離案**:

- **A**. filters.mbt を丸ごと builtin 側へ (kuu.mbt/engine は "filter descriptor interface" だけ持ち、kuu.mbt/builtins が具体住人を提供、kuu.mbt/kuu が全部登録)
- **B**. lookup_filter は engine の pub 契約として残し、住人だけ builtin へ (`installer.mbt` の collect_* が engine から `lookup_filter` を呼ぶ)

**依存**: PKG-#13 (accumulator registry) と同型。

---

### PKG-#13: accumulator と collector の registry

**箇所**:

- accumulator: 名 "append" (デフォルト) / "merge" (DR-080) / "kv_map" (DR-091 §2)。ensure_entity で写像 (installer.mbt:1491-1511)、resolve.mbt:2570 で "merge" を `resolve_merge_accum` に dispatch、resolve.mbt:662 で "kv_map" を RObj に dispatch、resolve.mbt:616 で "append" の fold
- collector: 名 "unwrap_single" のみ実装。`known_collector` (wire_decode.mbt:1220) と `apply_collector` (resolve.mbt:495) に散在
- 未実装名 ("to_set" / "from_entries") は各所コメントで放置

**spec 帰属**: DR-036 (accumulator / collector registry) は complete registry pattern を規定。現状は engine 直書きで pluggability ゼロ。

**分離案**:

- **A**. accumulator / collector を builtin 側の descriptor 群に (`ArrayAccumulatorDescriptor` を新設)。engine は名前で lookup、住人が具体挙動を提供
- **B**. resolve.mbt の "merge" / "kv_map" 分岐を builtin 側の関数に切り出し、engine は "cell.accum descriptor.fold" を呼ぶ
- **C**. 現状維持 (kuu.mbt reference 単体で有限住人)

**依存**: PKG-#12 と同型。

---

### PKG-#14: Entity struct の carrier フィールド (30+ フィールド)

**箇所**: node.mbt:426-560 `struct Entity`

**直書き**: 30+ フィールドのうち大半が「特定 installer / 特定型でのみ意味を持つ冗長フィールド」の carrier pattern:

- `int_round` (TInt only), `allow_base_prefix` (TNum / TInt only), `bool_config` (TBool only), `is_tty` / `tty_stream` / `tty_cygwin` (builtin/tty only)
- `piece_filters` / `value_filters` / `final_filters` / `accum_filters` / `collector` / `flatten` / `is_multiple_decl` (accum registry / filter registry の住人 config)
- `hidden` / `completer` (DR-104 表示軸)
- `env_key` / `config_seat` / `config_key` / `is_config_file` / `inherit_` (seat 宣言)
- `default_values` / `separator` / `accum` (builtin lowering の carrier)

**spec 帰属**: 上記 30+ フィールドは全て builtin 語彙。engine 純粋なら Entity は `name / ty / seat 宣言 (env/config/inherit の Bool) / accum name` くらいの必要最小限。

**分離案**:

- **A**. Entity を engine の "opaque" 型にし、descriptor は builtin 側で管理
- **B**. engine の Entity は最小限 (name / ty / seat 5 flag + accum 名) にし、残りは "descriptor: Map[String, Any]" のような拡張 slot
- **C**. 現状維持

**依存**: PKG-#7 / #10 / #11 / #12 / #13 の全てと直結。

---

### PKG-#15: is_sentinel の pub 契約

**箇所**: resolve.mbt:74 `pub fn is_sentinel(k : String) -> Bool` — front_door.mbt の `merge_sentinels_from_origin` (resolve.mbt:106) と kuu-cli 側の post-processing が消費。

**問題**: sentinel は本来 builtin 内部語彙のはずが engine の外部 API に漏出。DR-104 §5 の相区分 (parse 相 / resolve 相 / 出力射影) が engine 契約なので、sentinel の pub 化は「相区分の合流点で必要」= engine 契約に混じっている。

**spec 帰属**: sentinel は builtin 語彙、pub 化は engine の相区分の副作用。

**分離案**:

- **A**. sentinel を Binding に `is_meta: bool` タグ化し、`is_sentinel` を廃止 (external API から builtin 語彙を排除)
- **B**. front_door が sentinel を吸収して external から見えない形に (post-processing を engine 内で完了)
- **C**. 現状維持

**依存**: PKG-#3 と一体。

---

### PKG-#16: conformance runner と wbtest の置き場

**箇所**:

- `src/core/json_conformance_wbtest.mbt` (spec fixture runner) — 現状は core package の wbtest。engine 純粋テスト (matcher_wbtest / eval_wbtest) と builtin 意味論テスト (installer_wbtest / filters_wbtest / resolve_wbtest / front_door_wbtest / value_wbtest / installer_wbtest / complete_wbtest / wire_decode_wbtest) が混在
- moon.pkg (src/core/moon.pkg:5-9): wbtest でのみ `moonbitlang/x/fs / core/env / core/json` を import

**spec 帰属**: conformance は DR-065 / DR-069 の spec 契約 (runner は spec fixture が正)。

**分離案**:

- **A**. conformance runner を kuu package (assembly) に置き、engine と builtins は各々の unit wbtest だけ持つ
- **B**. engine / builtins それぞれの wbtest を分離し、conformance runner は builtins に置く (engine wbtest は engine 契約のみを検証)
- **C**. 現状維持 (全部 core package)

**依存**: 各 package 分離後の CI 実行順に効く。

---

### PKG-#17: pub 依存の棚卸し (wbtest 都合の pub)

**箇所**:

- node.mbt:672 `pub(all) enum TermHint` / `pub(all) struct CandMeta` / `pub(all) struct Cand` — 完全公開 (wbtest からのハンドル構築)
- resolve.mbt:74 `pub fn is_sentinel` (前述、PKG-#15)
- resolve.mbt:106 `pub fn merge_sentinels_from_origin` — front_door 経由の後処理のため pub
- eval.mbt:130 `pub fn is_depr_key` / eval.mbt:217 `pub fn is_action_key` — 同上
- value.mbt:1256 `pub fn eq_ci` などの utility も pub
- installer.mbt の多くの `fn` は非 pub だが、`build_export_map` / `lower_definition` / `Installer` enum などが pub

**問題**: pub 依存は分離時に「どのシンボルが package 境界を跨ぐか」を規定する。特に wbtest 用に pub 化されたシンボル (moon.pkg のコメントで「MDR-005 §3: 公開面キュレーション (pub(all) → pub) で `Node` / `ConfigVal` 等が『外部から構築される前提』を失った」の記述あり) を分離時に整理する必要。

**分離案**: 各 pub シンボルを engine 契約 / builtin 契約 / assembly-only に分類。wbtest 都合の pub は wbtest package (or friend visibility) に閉じ込める。

---

### PKG-#18: eval.mbt の is_zero_token_marker と builtin variant 認識

**箇所**: eval.mbt:1358 `is_zero_token_marker` は Node の `Bind / EffMark / FailMark / DeprMark` の 4 variant を "0 token" として認識。同 fn は「lowering の shape と同期が必要」と自認するコメント。

**spec 帰属**: これら 4 variant は builtin lowering 産物 (EffMark / FailMark / DeprMark) と engine 一般 (Bind) の混在。

**分離案**:

- **A**. 4 variant を「0-token binder」の共通 marker として engine が知る (現状)
- **B**. 0-token 判定を Node variant 側の "consumes: Int" フィールドに置き換え、engine は data で判定
- **C**. Node open 化 (PKG-#1 案 B) に伴い、拡張 Node に "is_zero_token" 契約を持たせる

**依存**: PKG-#1 と一体。

---

### PKG-#19: wire_decode.mbt の帰属

**箇所**: wire_decode.mbt 全体 (~2100 行)

**直書き**:

- `dec_option` (wire_decode.mbt:1575-1875): allowed_keys で全 installer 語彙 (long / short / env / global / inherit / inheritable / multiple / config_key / required / required_group / hidden / completer / piece_filters / value_filters / final_filters / accum_filters / ref / repeat / match / self / config) をリスト
- `dec_positional` (wire_decode.mbt:1878-2100): 同様
- `dec_types`: `int_parser` / `number_parser` / `bool_parser` / `tty` / `builtin/*` factory の hard-coded 分岐
- `dec_multiple`: "append" / "merge" / "kv_map" の accumulator 名を認識
- `type: "help" / "config_file" / "tty" / "dd"` の特殊分岐

**spec 帰属**: wire 語彙は全て builtin。engine は AtomicAST の受け皿のみ持つのが理想。

**分離案**:

- **A**. wire_decode を **完全に builtin へ**。engine は Node / Scope / AtomicAST の型と `lower_definition(def, chain, registry)` の signature のみ提供
- **B**. wire_decode を builtin と共有 (installer 各住人が自 vocab の decode を提供、engine は集約 orchestrator)
- **C**. 現状維持

**依存**: PKG-#1 / #8 / #9 と一体。

---

### PKG-#20: complete_tree の Entity テーブル走査 (CandMeta と completer lookup)

**箇所**: outcome.mbt:303-540 (complete_tree / collect_all_entities / collect_entities_into / collect_entities_greedy / collect_entities_pos)

**直書き**: `Cand.origin` から `(path, origin)` キーで Entity テーブルを引き、`Entity.completer` / `Entity.hidden` を Cand.completer / meta.hidden に写す (DR-104 §2 / §3)。

**spec 帰属**: DR-060 §3 / §4 は completion 素材の engine 契約。ただし completer / hidden の中身は builtin 語彙。

**分離案**:

- **A**. complete_tree を engine 骨格として残し、meta 中身は "opaque Map[String, String]" で流す
- **B**. complete_tree を builtin 側に移し、engine は Pending 型と Cand 型だけ持つ
- **C**. 現状維持

**依存**: PKG-#14 と一体。

---

### PKG-#21: front_door.mbt の相区分と pub API 帰属

**箇所**: front_door.mbt:71-363

**直書き**:

- `parse_definition` (DR-054): AtomicAST を返す engine 契約 + 内部で `dec_definition` (builtin decode) を呼ぶ
- `parse` / `resolve` / `complete`: engine の 3 契約 (DR-053 / DR-054 / DR-060)
- 補助 `export_map` / `result` / `sources` / `config_from_json` / `tty_obs`: builtin 型 (ExportKey / RVal / TtyObs) を運ぶ pub API

**問題**: engine 純粋なら front_door は engine 契約だけを export し、builtin 型は builtin 側の pub API として別公開が理想。現状は engine と builtin が混じった "1 顔"。

**分離案**:

- **A**. front_door を assembly (kuu) 側に置き、engine は raw parse_tree / complete_tree、builtin は decode + lower_definition だけ提供
- **B**. front_door を engine に残し、builtin 型が engine を経由して透過的に外に出るようにする (現状に近い)
- **C**. front_door を engine と builtin に分離 (parse / complete は engine、resolve と補助は builtin / kuu)

**依存**: PKG-#19 (wire_decode の帰属) と一体。

---

## 依存関係 (どれを先に決めると他が従属的に決まるか)

### 最上流 (先に決めるべき)

- **PKG-#1 (Node ADT の帰属モデル)** — Node を open (拡張可能) にするか閉 ADT のままにするかで、全ての「値 primitive / matcher / sentinel / 定義時検査 / Entity carrier」の分離戦略が決まる
- **PKG-#14 (Entity struct 分割)** — Entity を engine 側の最小構造にするか builtin 側の descriptor 群に移すかで、resolve / installer / matcher / complete の全てが連動

### 中流 (上流の帰結を受けて決まる)

- PKG-#4 (Ty) → PKG-#5 (matcher 型分岐) → PKG-#6 (Long/ShortEntry)
- PKG-#7 (config 型) → PKG-#10 (ensure_entity) → PKG-#11 (ladder)
- PKG-#9 (Installer enum) → PKG-#8 (collect_*) → PKG-#19 (wire_decode)
- PKG-#12 / #13 (filter / accumulator registry) は同型で並行裁定可

### 下流 (仕組みが決まった後の配置決定)

- PKG-#3 / #15 (sentinel の帰属)
- PKG-#16 (conformance runner の置き場)
- PKG-#17 (pub 依存棚卸し)
- PKG-#20 (complete_tree)
- PKG-#21 (front_door)

### 独立 (機械的連動)

- PKG-#2 (eval 値 arm の帰属) は PKG-#1 の結果で機械的
- PKG-#18 (is_zero_token_marker) は PKG-#1 と機械的連動

---

## 特に裁定が重い争点 (トップ 3)

1. **PKG-#1 (Node ADT の帰属モデル)** — 現状の閉 ADT を保つか、trait / open enum で拡張可能にするか、JSON-同型 struct のみに縮退させるか。この 1 択で 12+ 争点が連動決定される。MoonBit の trait / open enum サポート状況の確認も裁定材料。
2. **PKG-#14 (Entity struct 30+ フィールド)** — engine の最小 Entity + builtin descriptor の分離モデル。PKG-#1 と直交する軸 (Node vs Entity で "engine の閉じた ADT" が 2 つある)。
3. **PKG-#5 (matcher.mbt の TCount → Update("increment", []) 直書き)** — 現行実装で **最も明白な癒着**。matcher が builtin 型 (count) の update effect 語彙 (DR-077 §3) を直書き。ここが解けないと "engine は builtin 語彙を知らない" 目標そのものが達成不能。

---

## 補足

### 絶対パス (依存関係先頭確認用)

- 実装: `/Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/{core,node,value,matcher,eval,filters,installer,resolve,wire_decode,outcome,front_door,cont}.mbt`
- moon.pkg: `/Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/moon.pkg`
- spec DR (関連): `/Users/kawaz/.local/share/repos/github.com/kawaz/kuu/main/docs/decisions/DR-{028,031,036,037,038,039,041,042,043,048,050,051,054,055,057,058,060,061,065,073,074,075,076,077,078,080,083,085,088,089,090,091,093,094,095,096,099,101,102,103,104,105,107,109}-*.md`

### 未確認事項 (今回スコープ外、統括の判断待ち)

- spec 側で「Installer は builtin」「Ty のうち presence-only 3 種は builtin」「filter / accumulator registry の住人は builtin」を明文化する DR が要るか (PKG-#1 / #4 / #9 / #12 / #13 の裁定の spec-側裏付け)
- kuu.mbt/engine の interface として "Node open" を選ぶ場合、MoonBit の trait / open enum サポート状況の確認 (実装可能性)
- wbtest 分離時に MoonBit の package 内可視性 (friend / test-only pub) がどこまで表現できるか (PKG-#17)
