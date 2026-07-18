# API 公開面の全数分類表 — mbti 3 本の契約/実装仕分け (Phase 1)

> 対象: `src/engine/pkg.generated.mbti` (685 行) / `src/builtins/pkg.generated.mbti` (208 行) /
> `src/kuu/pkg.generated.mbti` (102 行) の全 pub identifier。根拠は spec の DR-110
> (3 層規範 + 境界裁定表、kuu リポ `docs/decisions/DR-110-kuu-core-standard-packaging.md`) と、
> 実使用の grep 観測 (builtins→engine / kuu→engine,builtins / kuu-cli `impl/mbt/cli/src/lib/wire.mbt`)。
> コールドレビュー (docs/findings/2026-07-18-api-cold-review-zero-knowledge.md) の指摘は
> 1 件ずつ「意図的設計 (擁護可能)」か「真の改善点」かを判定して表に反映した。
> 発注 issue: docs/issue/2026-07-18-api-surface-contract-triage.md (Phase 1 成果物)。

## 分類コードの定義

発注の 4 区分を、DR-110 #17 の三分類 ((a) engine 契約 / (b) builtins 契約 / (c) 玄関) に
合わせて次のコードで運用する:

| コード | 意味 | 発注区分との対応 |
|---|---|---|
| **A-e** | engine 層の拡張契約 (3rd party 拡張実装者向け、DR-110 #17(a))。現配置 (engine) が正 | A |
| **A-b** | builtins 層の契約 (住人の再利用・差し替え・subset assembly 材料、DR-110 #17(b) / §5「builtins が公開するのは住人」)。現配置 (builtins) が正 | A (層が builtins なだけで「契約」) |
| **B** | 玄関契約面 (アプリ開発者が触れる、DR-110 #17(c))。kuu の API と、その入出力に必然的に現れる型。engine 定義の型でも依存方向上 engine 物理配置が必然のものは「B (物理 engine)」と注記 | B |
| **C** | 実装詳細。pub 降格・削除・priv 明示化が層内で完結する | C |
| **C†** | 実装詳細だが**層跨ぎの消費がある** (builtins/kuu/kuu-cli が使用)。MoonBit の pkg 間可視性の制約上、単純降格では壊れる — internal 化 / 複製 / 径路整理の裁定が必要 (→ §裁定 TRI-Q3/Q4/Q6) | C (降格に前提作業あり) |
| **D** | 帰属間違い。DR-110 の規範に反する配置で、移動 (または移動を伴う再設計) の対象 | D |

判定の優先順位: (1) DR-110 の境界裁定表・禁止事項に明文の根拠があるもの → その裁定に従う
(擁護しない)。(2) 明文がないもの → 実使用の観測 (誰が消費しているか) で #17 の分類基準に写像。
(3) 機械的に決まらないもの → 分類欄に「/Q」を付け §裁定が必要な境界ケース に登録。

## 判明した事実

### 全数集計 (top-level identifier、メソッドは所属型の行に含めて別掲)

| pkg | top-level | A-e | A-b | B | C | C† | D | メソッド |
|---|---|---|---|---|---|---|---|---|
| engine | 121 | 40 | — | 20 | 9 | 15 | 37 | 42 |
| builtins | 83 | — | 58 | 0 | 11 | 4 | 10 | 1 |
| kuu | 25 | — | — | 15 | 4 | 6 | 0 | 0 |
| **計** | **229** | **40** | **58** | **35** | **24** | **25** | **47** | 43 |

- 総 identifier 数 (メソッド込み) = 272。mbti 3 本 (685+208+102 行) の pub 面を全数網羅、サンプリングなし。
- **D (帰属間違い) は 47 件**。確定例の Filter descriptor 3 型 (+ lookup/apply 系 5 fn + 組成 2 fn)
  に加え、engine 側に **installer 語彙 carrier (ElemDef/Definition 系 10 型 + 閉じた列挙 2 型)**、**builtin 型/matcher
  config (RoundMode/BoolConfig/AttachMode/EqSepMode + 変換 fn 2 本)**、**builtin 型の失敗語彙
  (ParseFail + pe_* 7 本)**、**sentinel 綴り依存の関数群 (`@depr:`/`@act:` を engine が直書き)**、
  **merge/kv 意味論の断片 (PieceMark/classify_merge_piece/contains_eq)** が見つかった。
- **完全 UNUSED の pub が engine に 12 件** (committed / none_cell / rval_* 3 本 / AmbiguousData※ /
  CandMeta※ / DecodedOwnedDecl※ / FailDef※ / OwnedDecl※ / SeatCtx※ / Resume。※はシグネチャ経由で
  契約に現れるため削除不可 = 分類維持、名前直参照がゼロなだけ)、builtins に 15 件
  (うち configured_short_type は全域 dead)。
- **filter 契約が engine の Registry に存在しない**: `Registry` は accumulator/collector/matcher/
  node/type の 5 系統の register/lookup を持つが filter が無い。filter だけ builtins 内の static
  表 (`lookup_filter`/`lookup_array_filter`) で解決されており、DR-110 #12「engine は名前 lookup と
  呼び出し契約 (io_type / fallibility) のみ」の受け皿ごと欠けている。descriptor 型の移動だけでなく
  registry 機構の増設が必要。
- **DR-110 #15 (is_sentinel 公開廃止) は実装済み**: `is_sentinel` は kuu の priv fn
  (src/kuu/resolve.mbt:42) に降格済みで mbti に無い。kuu-cli も直接使用を解消済み
  (wire.mbt:186 のコメントが解消を記録)。ただし engine 内部には `@depr:`/`@act:` の綴り判定が
  残存 (src/engine/eval.mbt:149,236) — §2-1 違反は D として継続 (TRI-Q9)。
- **kuu-cli の玄関迂回が 2 系統残る**: (1) `@engine.warnings_structured`/`@engine.none_cells` の
  直呼び、(2) Ambiguous 解釈の描画で `@kuu.build_result`/`accum_cells`/`apply_export_keys`/
  `export_map` + `ast.root` フィールド直触り (wire.mbt:176-235)。径路整理 (TRI-Q4) をしないと
  kuu 玄関部品 (C†) の降格ができない。

### 消費観測の方法 (再現コマンド)

```bash
cd /Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main
# 非テスト実装からの cross-pkg 参照 (builtins→engine の例)
grep -ohE '@engine\.[A-Za-z_][A-Za-z0-9_]*' $(ls src/builtins/*.mbt | grep -v wbtest) | sort -u
# kuu-cli (唯一の外部消費者)
grep -oE '@(engine|builtins|kuu)\.[A-Za-z_][A-Za-z0-9_]*' \
  /Users/kawaz/.local/share/repos/github.com/kawaz/kuu-cli/main/impl/mbt/cli/src/lib/wire.mbt | sort -u
```

enum variant の参照 (`@engine.VStr` 等) は所属型 (`Value`) の使用として正規化した。
名前直参照が 0 でも trait メソッドのシグネチャ経由で使われる型 (SeatCtx 等) は impl 側の
使用を目視確認した (src/builtins/type_residents.mbt の `default_seat_resolver` impl 群)。

---

## 分類表

凡例: 消費列は b = builtins 非テスト / k = kuu 非テスト / cli = kuu-cli wire.mbt /
T = テストのみ / — = どこからも参照なし。

### kuu (25 identifier)

| identifier | 種別 | 分類 | 消費 | 根拠 | 措置 |
|---|---|---|---|---|---|
| `parse_definition` | fn | B | cli | DR-054 契約、front_door 3 契約の 1 (DR-110 §5) | 維持 |
| `parse` | fn | B | cli | DR-053 契約、同上 | 維持 |
| `resolve` | fn | B | cli | resolve 込み完全経路 (DR-110 §5) | 維持。parse との契約差が型から読めない件はコールドレビュー指摘の真の改善分 → doc comment 強化 (Phase 3) |
| `complete` | fn | B | cli | DR-060 契約 | 維持 |
| `output` | fn | B | cli | OutputView 玄関 (MDR-005 追記) | 維持。径路多重の解消は TRI-Q4 |
| `result` | fn | B/Q | T | output と径路重複。kuu-cli は不使用、wbtest のみが使用 | TRI-Q4 (output 一本化なら deprecated → 削除) |
| `sources` | fn | B/Q | — | provenance 照会。OutputView.sources と重複 | TRI-Q4 (同上) |
| `config_from_json` | fn | B | — | 玄関補助 (統括裁定 (b)、src/kuu/front_door.mbt:518 の意図コメント)。engine 版との重複はコールドレビュー指摘だが、玄関ラッパとして意図的 — 擁護 | 維持 |
| `tty_obs` | fn | B | — | TtyObs 構築の玄関補助 (統括裁定 (b)) | 維持 |
| `spec_repo` | let | C | — | 「port の定義 = conformance fixture を pass」の正本名表示 (src/kuu/core.mbt:11)。機能 API ではなく docs の関心 | 降格 (README/docs へ移す)。残す場合も doc 定数と明記 |
| `build_result` | fn | C† | cli | 内部組み立ての露出 (コールドレビュー指摘は真の改善分)。ただし kuu-cli の Ambiguous 解釈描画が使用 (wire.mbt:233) | TRI-Q4 の玄関 API 補強後に降格 |
| `accum_cells` | fn | C† | cli | 同上 (wire.mbt:235、`ast.root` 直触りとセット) | 同上 |
| `apply_export_keys` | fn | C† | cli | 同上 (wire.mbt:234) | 同上 |
| `export_map` | fn | C† | cli | 同上 (wire.mbt:176) | 同上 |
| `AccumCell` | struct | C† | — | build_result 径路の部品型 (シグネチャ経由で cli に露出) | 同上 |
| `DefaultCell` | struct | C† | — | 同上 (build_result 引数型) | 同上 |
| `AtomicAST` | struct | B/Q | cli | 玄関ハンドル (DR-054 の産物)。ただし root/templates/extensions/ekmap の 4 フィールドが pub で内部表現を露出 — コールドレビュー指摘は真の改善分 (cli が `ast.root` を直接触っている、wire.mbt:235) | 型は B 維持、フィールドは opaque 化 (TRI-Q4 の径路整理とセット) |
| `DefLoadError` | enum | B | cli | parse_definition の出力 (Malformed/Rejected、DR-054) | 維持 |
| `OutputView` | struct | B | cli | output の出力 (result/effects/sources) | 維持 |
| `OutputEffect` | struct | B | cli | OutputView.effects の要素型 | 維持 |
| `SourceEntry` | struct | B | cli | provenance 出力 (DR-087 系)。pub(all) だが出力専用型 — 外部構築の必要はないので pub(readonly) 相当へ絞る余地 | 維持 (可視性微調整は Phase 3 の任意項目) |
| `TtyObs` | struct | B | cli | parse/resolve の tty? 入力 (DR-099 §4) | 維持 |
| `ExportCollision` | 型 (非 pub) | C | — | priv 未明示の abstract 型が mbti に名前だけ漏れている (コールドレビュー指摘の「裸の opaque 型ノイズ」は真の改善分) | `priv` 明示化で mbti から消す |
| `ScopeConfig` | 型 (非 pub) | C | — | 同上 | 同上 |
| `TypeShadow` | 型 (非 pub) | C | — | 同上 (src/kuu/wire_decode.mbt:859) | 同上 |

kuu 小計: B 15 / C 4 / C† 6 / D 0。

### builtins (83 identifier + 1 メソッド)

DR-110 §5「builtins が公開するのは住人 (decode + lowering + 各 descriptor)」と §7 の
subset assembly (組成表を差し替えるだけで縮小組立が作れる) を A-b の判定基準にした:
**subset assembly / 3rd party が住人を選んで組む時に必要な factory・decode 部品は A-b**、
それ以外の内部部品は C。

#### canonical installer 群 (13 件、全て A-b)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `long_installer` `short_installer` `env_installer` `dd_installer` `command_installer` `global_installer` `inherit_installer` `repeat_installer` `multiple_installer` `config_installer` `constraint_installer` `alias_installer` `inheritable_installer` | fn ×13 | A-b | k は long/short/env/repeat/multiple/inherit/inheritable/global/dd/config/command/constraint/alias を wire decode・組成で使用 (残りは T) | DR-042 の表の 13 種そのもの。住人 factory は builtins 契約の中核 (DR-110 §4)。subset assembly の選択単位 |

#### 型住人 factory (11 件、全て A-b)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `string_type` `number_type` `int_type` `float_type` `bool_type` `none_type` | fn | A-b | k | 値プリミティブ型住人 (DR-074/075、DR-110 §4)。config? 引数付き factory は DR-061 §3 の構築枠 |
| `flag_type` `count_type` `tty_type` | fn | A-b | k (flag/count)、T (tty) | preset 型住人 (DR-076/077/099) |
| `configured_type` | fn | A-b | k | 型 config (round/base/bool 語彙) を適用した configurable factory (DR-061 §3) |
| `configured_short_type` | fn | **C** | — | **全域 dead** (builtins 内部からも参照ゼロ)。削除 |

#### accumulator / collector / matcher / entity 住人 (12 件)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `append_accumulator` `kv_map_accumulator` `merge_accumulator` | fn | A-b | k (append/kv_map/merge) | DR-036/105 の住人 factory |
| `unwrap_single_collector` `from_entries_collector` | fn | A-b | k | DR-105 §4 収集住人 |
| `FromEntriesSpec` | enum (all) | A-b | T | from_entries の構成データ (Entries/KeyValue/KeyPromote)。descriptor config |
| `eq_split` `short_combine` | fn | A-b | k | matcher 具象住人 (DR-110 #6: eq-split / short-combine は builtins) |
| `eq_entry` `short_entry` / `EqEntry` `ShortEntry` | fn / struct | A-b | k (eq_entry/short_entry)、T (型は間接) | matcher 構成データの構築 (DR-042「matcher = 名前付きデータ」)。型はフィールド非公開で opaque — 良い形 |
| `entity_ext` | fn | A-b | T | EntityExt 住人 factory (hidden/completer の候補メタ写像、DR-104) |

#### 値 node factory / lowering 部品 (16 件)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `string_arg` `number_arg` `int_arg` `float_arg` `bool_arg` `kv_arg` `typed_arg` `separated_arg` `filtered_number_arg` `enum_value_node` | fn | A-b | k (string/number/float/int/kv/typed/separated/bool)、T (他) | open node 契約 (DR-110 §3-2) に乗る値 node 住人の factory。install の prototype 登録材料 |
| `deprecation_mark` `effect_mark` `failure_mark` `or_branch_node` | fn | A-b | k | sentinel / effect / or-branch node の factory。sentinel 綴りは builtins 内部語彙 (DR-110 #3) なので factory が builtins に居るのは正 |
| `elem_head` | fn | C† | k | ElemDef → trigger node の lowering 内部部品。住人 factory ではなく installer 実装の断片。kuu (front_door/wire) が使うため単純降格不可 — TRI-Q1 (carrier 移動) と連動 |
| `node_resident_name` | fn | C† | k | Node → 住人名の逆照会。NodeExt::kind (engine 契約) の Node ラッパで、kuu の走査便宜。降格には kuu 側の照会を NodeExt 経由へ |
| `node_effect_mark` `node_is_failure_mark` | fn | C | T | 同上の逆照会だがテストのみが消費。NodeExt::effect_mark / is_failure_action (engine 契約メソッド) と重複 — 降格 |

#### 語彙 decode / 字句 (12 件)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `classify_long_spelling` / `LongSpelling` | fn / enum (all) | A-b | k | long DSL (LMain/LVariant/LInvalid) の decode。long installer の所有語彙 decode 部品 (DR-110 #19: decode は住人所有) |
| `bool_config_canonical` | fn | A-b | k | canonical bool 語彙 (DR-075) の正本 |
| `round_mode_of` | fn | A-b | k | round 語彙 → RoundMode (DR-074)。型 config decode |
| `parse_filter_shorthand` | fn | A-b | k | filter 綴り shorthand の decode (DR-062 系) |
| `config_to_value` | fn | A-b | k | config 席の同型注入 (ConfigVal → 型 parse + filter、DR-110 #10: config 席は住人宣言) |
| `parse_number` | fn | C† | k | canonical 字句の生 parse。契約面は TypeExt::parse_token であり、素の字句 fn は実装詳細。kuu が使うため単純降格不可 |
| `parse_bool` `parse_bool_ext` `parse_int_value` `parse_int_value_ext` `parse_number_ext` `parse_float` | fn | C | —/T | 同上、かつ層外消費ゼロ。`_ext` 二重化 (コールドレビュー指摘は真の改善分 — 同 pkg の `bool_type(config?)` が optional 引数を使えている) は optional 引数 1 本化で解消し、pub は落とす |

#### filter 系 (10 件、発注確定の D) と組成 (2 件、D)

| identifier | 種別 | 分類 | 消費 | 根拠 | 移動先 |
|---|---|---|---|---|---|
| `FilterDescriptor` `ArrayFilterDescriptor` | struct | **D** | T (lookup 経由) | 拡張契約型が builtins にのみ定義され、3rd party filter 実装が builtins 依存を強制される。DR-110 §2-2 (builtins は extension interface の一住人) 違反、AccumulatorExt 等と非対称 | engine (descriptor 契約、DR-061/095/107) |
| `FilterSignature` (+ `is_transform`) | enum + method | **D** | — | 同上 (io_type/fallibility 宣言は engine の呼び出し契約、DR-110 #12) | engine |
| `lookup_filter` `lookup_array_filter` | fn | **D** | k (lookup_filter)、T | filter だけ Registry に系統が無く builtins の static 表で解決している。DR-110 #12「住人は builtins、登録は assembly。engine は名前 lookup と呼び出し契約のみ」— **engine Registry に filter 系統を増設**し、住人登録は assembly へ | engine (lookup 機構) + kuu (組成) |
| `apply_filter_chain` `apply_accum_filter_chain` `apply_piece_filters` | fn | **D** | k | filter chain の適用機構 (resolve/eval 段の呼び出し側)。住人でなく機構なので engine 帰属 (DR-110 #12) | engine |
| `install` | fn | **D** | k | **全部入り組成表そのもの**。DR-110 §2-3「canonical set の組成は assembly が所有…builtins は自分たちを engine へ登録する主体にならない」に明文違反 (現に kuu 側 `canonical_registry` (src/kuu/registry.mbt:6) は @builtins.install を呼ぶだけ) | kuu (assembly) |
| `install_installers` | fn | **D** | — (install 内部) | 同上 (installer 部分の組成表) | kuu |

#### 玄関/組成の中間部品 (3 件)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `lower_definition` | fn | A-b/Q | k | installer chain の遂行 (DR-042 fixpoint 前後の正規化 + 静的検査)。builtins 語彙の pre-pass (`:set`→kebab 等) を含むので builtins 帰属は擁護可能。ただし **`extensions?` の default 値が `default_extensions()` (= install() 全部入り) で、組成表を builtins が暗黙所有** — DR-110 §2-3 に抵触 → TRI-Q8 |
| `build_export_map` | fn | A-b | k | Definition → export map。export_key 写像機構 (DR-052) は engine だが、Definition (installer 語彙 carrier) の走査は definition 側の関心。carrier 移動 (TRI-Q1) 後も builtins で整合 |
| `owned_vocab` | fn | C† | k | InstallerExt の所有語彙の表示用文字列化。エラー文言部品で契約ではない。kuu 使用のため単純降格不可 |
| `sep_binds` | fn | C | — (builtins 内部のみ) | separated 住人の piece 処理内部。builtins 内の matcher_residents/node_residents だけが使う — pub 不要、降格 |
| `split_colon` | fn | C | — (builtins 内部のみ) | 汎用 split ヘルパ (コールドレビュー指摘どおり)。降格 |

builtins 小計: A-b 58 / C 11 / C† 4 / D 10 (メソッド is_transform は D の型に随伴)。

### engine (121 identifier + 42 メソッド)

DR-110 §2-1 の禁止事項 (engine は builtin 語彙 — installer 属性名・型名・filter 名・sentinel
綴り・preset 意味論 — を識別子・分岐条件として含まない) を D の判定基準にした。玄関入出力に
必然的に現れる型は「B (物理 engine)」— 依存方向 (kuu→engine) 上、定義の物理配置は engine が
必然で、移動対象ではない。

#### 玄関入出力型 (20 件、B (物理 engine))

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `Outcome` | enum (all) | B | b,k,cli | DR-053 結末 3 値 union。拡張契約 (Branch→Outcome) でもある |
| `FailureData` `AmbiguousData` `AmbInterp` | struct (all) | B | cli / — / k | DR-053 §3/§4 の結末構造。AmbiguousData は名前直参照ゼロだが Outcome::Ambiguous の payload (削除不可) |
| `ParseError` `ErrKind` | struct/enum (all) | B | b,k,cli | DR-053 エラー面 (kind 3 値は KParse/KFilter/KConstraint) |
| `DefError` `DefErrKind` | struct/enum (all) | B | b,k,cli | DR-054 §4 定義時エラー面 |
| `Binding` | struct (all) | B | b,k,cli | Success payload (玄関) かつ読み枝の運搬 (A-e 両属) |
| `Value` `Source` `EffectOp` `RVal` `ConfigVal` | enum | B | b,k,cli | 値・出所・効果・結果木・config 入力 — DR-031/052/053 の仕様語彙。ConfigVal のみ非 pub(all) (良い形) |
| `ExportKey` | enum | B | b,k | DR-052 写像。opaque enum + fn コンストラクタ (良い形) |
| `Cand` `CandMeta` `TermHint` | struct/enum (all) | B | b,k,cli / — / b,cli | DR-060 §3 / DR-104 候補構造 (仕様規範化済み、DR-110 §3-10) |
| `Warning` | struct (all) | B | cli | CONFORMANCE §2 warnings 面素材。中身 stringly (element/kind) はコールドレビュー指摘の真の改善分 — kind の enum 化は warnings 径路整理 (TRI-Q9) とセット |
| `NoneCell` | struct | B | b,k,cli | none 宣言 cell の照会 (kuu build_result の nones?)。**ただし `none_cells` の実装が `entity.ty.name() == "none"` の型名直書き判定 (src/engine/none_cell.mbt:50) — §2-1 違反、判定は descriptor dispatch へ (TRI-Q9 系)** |

#### 拡張契約 — trait と registry (A-e、22 件 + メソッド 26)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `TypeExt` `MatcherExt` `NodeExt` `AccumulatorExt` `CollectorExt` `InstallerExt` `EntityExt` | trait (open) | A-e | b (全て)、k (Type/Accum/Coll) | DR-110 §3-2/-4/-6/-7 の拡張契約そのもの。kind+encode+equal の統一は擁護可能な意図的設計。**ただし TypeExt::parse_token の戻りが `Result[Value, ParseFail]` で closed な builtin 失敗列挙に縛られる — TRI-Q2** |
| `Registry` (+ methods 13) | struct | A-e | b,k | §3-6 registry 機構。**filter 系統が欠落 (D 側で増設)**。register_* が Bool 返し / register_installer だけ Unit の不整合はコールドレビュー指摘の真の改善分 |
| `Ctx` (+ is_complete_mode / token_at) | struct | A-e | b,k | matcher/node 契約の実行文脈。opaque + 最小メソッド (良い形) |
| `Branch` | enum (all) | A-e | b,k | 読みの枝 (Accept/Held/Pending、DR-041) |
| `SeatCtx` (+ declared / observed) | struct | A-e | impl 経由 (type_residents の default_seat_resolver 実装) | §3-5 席内解決の契約入力。名前直参照ゼロだが TypeExt 契約シグネチャの一部 |
| `DefsView` (+ methods 4) | struct | A-e | b | InstallerExt::collect_defs_errors の契約入力 |
| `InstallBuilder` (+ methods 6) `InstallBuild` (+ methods 8) `InstallChild` (+ methods 3) | struct | A-e | b | §3-7 install 契約の作業面。InstallBuild/InstallBuilder の取り違えペアはリネーム対象 |
| `DecodeCtx` | enum (all) | A-e | k | InstallerExt::decode の文脈 (option/positional/command の 3 相) |
| `DecodedOwnedDecl` | struct (all) | A-e | シグネチャ経由 (InstallerExt::decode 戻り) | #19 decode 契約の戻り。名前直参照ゼロ |
| `Scope` | struct (all) | A-e | b,k | AtomicAST 構造骨格 (§3-1)。pub(all) の妥当性は Node open 化 (TRI-Q5) と連動 |
| `Node` | enum (all) | A-e/Q | b,k | §3-1 構造骨格。**ただし 18 バリアント中 DdSat/DdMatchSat/CmdSat は installer 由来 satellite、pub(all) パターンマッチ可は IR 凍結 — PKG-Q1=a (open node 化) の残作業。公開範囲は TRI-Q5** |
| `FailDef` | enum (all) | A-e | T | parse_tree の faildef? (AcceptsOnly/WithHeld/DeepestOnly)。raw 契約の一部 |
| `Entity` | struct (all) | A-e/Q | b,k | 結果セル骨格。**型の engine 帰属は PKG-Q2=a で裁定済み** (opaque 化も現状維持も非採用、中間が正)。ただし現フィールド (config_seat/is_config_file/inherit_/flatten/piece_filters ×4…) は builtin 固有宣言を含み、descriptor 側へ絞る残作業 — TRI-Q7 |
| `FilterSpelling` | struct (all) | A-e | b,k | filter 綴り {name, args}。filter 機構の engine 移動 (D) 後は呼び出し契約の入力型として engine 帰属が正 |
| `LowerSeat` | type alias | A-e | b,k | accumulator resolve_cli の席 lowering 型。**alias を定義しながら契約シグネチャ (AccumulatorExt::resolve_cli) は生関数型 — コールドレビュー指摘の真の改善分、シグネチャに適用** |

#### raw 契約 fn (A-e、17 件)

| identifier | 種別 | 分類 | 消費 | 根拠 |
|---|---|---|---|---|
| `parse_tree` | fn | A-e | k | path 探索 raw 契約 (DR-110 §5「engine が公開するのは raw 契約」) |
| `complete_tree` | fn | A-e | k | complete 走査骨格 (§3-10) |
| `run_installer_fixpoint` | fn | A-e | b | install 合成 (§3-7、DR-042 不動点) |
| `collect_installer_vocab_errors` | fn | A-e | b | generic 2 検査の片翼 (§3-8) |
| `continue_matcher` | fn | A-e | b | matcher 住人が readings を評価器継続へ流す契約部品 (DR-041 §3-4) |
| `cand_trigger` `pend_value` | fn | A-e | b | matcher/node 住人の候補構築部品 (DR-060 §3 の定型)。命名は暗号的 — リネーム対象 |
| `mkb` `mk_eff` | fn | A-e | b,k / b | 住人が読み枝で Binding / effect 束縛を作る構築部品。リネーム対象 (`mkb` は手掛かりゼロ) |
| `seat_ctx` | fn | A-e | b,k | SeatCtx 構築 (TypeExt 契約の対) |
| `export_key` `export_key_null` `export_key_unset` | fn | A-e | b,k | opaque な ExportKey のコンストラクタ (DR-052)。installer decode が使用 |
| `config_from_json` | fn | A-e | k | config provider 入力の一般構築 (§3-5 の受け口) |
| `compile_regex` | fn | A-e | b | resident-neutral な host 方言 regex compile。pub の設計理由が doc comment に明記 (src/engine/regex.mbt) — 擁護可能 |
| `find_help_entry` `tried_triggers_of` | fn | A-e | k | DR-053 §4 の結末構造部品 (失敗位置基準の解決規則)。help「という綴り」には依存しない (greedy 内 failure-action 走査) — 確認済み、§2-1 違反なし |

#### 実装詳細 (C、9 件 — 層内降格で完結)

| identifier | 種別 | 分類 | 消費 | 根拠 / 措置 |
|---|---|---|---|---|
| `committed` | fn | C | — | EffectOp→Bool。全域 UNUSED。削除 |
| `none_cell` | fn | C | — | NoneCell コンストラクタ、外部消費ゼロ (none_cells だけが正規入口)。priv 化 |
| `rval_scalar` `rval_array` `rval_object` | fn | C | — | RVal は pub(all) で直構築可能、wrapper は全域 UNUSED。削除 |
| `node_consumes_zero_tokens` | fn | C | T | #18 の 0-token 判定は engine 内部機構。priv 化 (テストは wbtest 側で維持可) |
| `parse_context` | fn | C | T | Ctx 構築。matcher 単体検証の便宜。priv 化 (wbtest で足りる) |
| `run_matcher` | fn | C | T | matcher 単体実行。engine 内部 + wbtest のみ。priv 化 |
| `Resume` | type alias | C/Q | — | 外部未使用。契約シグネチャ (MatcherExt::interpret / NodeExt::eval / continue_matcher) に適用して活かすか削除するか — LowerSeat と同じ裁定 (軽微、Phase 3 で統一) |

#### 層跨ぎ消費のある実装詳細 (C†、15 件)

| identifier | 種別 | 分類 | 消費 | 根拠 / 前提 |
|---|---|---|---|---|
| `cat` | fn | C† | b,k | Array 連結の汎用 util (engine 内部 36 回 + b,k)。公開契約ではない — TRI-Q3 (降格方式) |
| `to_chars` `chars_to_str` | fn | C† | b / b | 汎用文字列 util — TRI-Q3 |
| `split_on` | fn | C† | b,k | 汎用 split — TRI-Q3 |
| `value_str` | fn | C† | b,k | Value → String 表示。汎用寄り — TRI-Q3 |
| `value_to_configval` | fn | C† | k | Value → ConfigVal 同型変換。config 席注入部品 — 径路整理と連動 |
| `collect_scopes` `scope_selected` `elem_value` `elem_value_in_subtree` `is_committed` `is_committed_in_subtree` `constraint_err` `none_cells` | fn | C† | k (none_cells は cli も) | resolve/constraint 検証 (現 kuu 実装) の支援走査。値源ラダー・constraint 検証の機構帰属 (TRI-Q6) が決まるまで pub 必須。none_cells の cli 直呼びは玄関迂回 (TRI-Q4) |
| `ScopedCons` | struct | C† | k | collect_scopes の戻り型 (随伴) |

#### 帰属間違い (D、38 件) — DR-110 §2-1 違反の全列挙

**(D-1) installer 語彙 carrier 群 (10 型) — 移動先: builtins (形は TRI-Q1)**

| identifier | 種別 | 消費 | 違反内容 |
|---|---|---|---|
| `ElemDef` | struct (all) | b,k | long/short/env/is_tty/is_dd/is_global/repeat/int_round/bool_config/long_prefix/… 55 フィールド全部が installer 所有語彙 (§2-1 が名指しで禁止する `long`/`short`/`env`/`repeat`)。pub(all) で不正状態を外部構築可能 (コールドレビュー指摘は真の改善分)。decode・lowering は住人所有 (#19/§6) なのに carrier が engine 常駐 |
| `Definition` `CommandDef` `AliasDef` `ElemBody` `OrBranch` `Variant` `LongDecl` `RepeatSpec` `RequiredCandidate` | struct/enum (all) | b,k | 同族 (options/positionals/commands/aliases の区分、long DSL 分解、repeat 仕様、required 候補 — すべて installer 語彙)。**ただし DefsView::definition / InstallBuilder::definition の契約シグネチャが Definition を参照しており、単純移動は依存方向 (engine→builtins 禁止) と衝突 — TRI-Q1 の本体** |

**(D-2) installer 語彙の閉じた列挙 (2 型)**

| identifier | 種別 | 消費 | 違反内容 |
|---|---|---|---|
| `OwnedDecl` | enum (all) | シグネチャ経由 | ODLong/ODShort/ODEnv/ODDd/ODGlobal/ODInherit/ODRepeat/ODMultiple/ODConfig/ODConstraint/ODAlias/ODInheritable/ODCommand — installer 13 種の**閉じた列挙**を engine が保持。#9「installer の閉じた列挙型を廃止し install 契約に開く」の宣言版違反。3rd party installer は自分の decl をこの enum に追加できない — TRI-Q1 |
| `Constraint` | enum (all) | b | CRequires/CConflicts/CExclusive/CRequired… は constraint installer の所有語彙。ただし InstallBuild::push_constraint 契約に現れる — TRI-Q1 |

**(D-3) builtin 型・matcher の config 語彙 (4 型 + fn 2 本) — 移動先: builtins**

| identifier | 種別 | 消費 | 違反内容 |
|---|---|---|---|
| `RoundMode` | enum (all) | b,k | 丸め語彙 (DR-074) は型 descriptor 管掌 (#7)。builtins に `round_mode_of` だけ既に居る非対称が現状の配置ミスを自白している |
| `BoolConfig` | struct (all) | b,k | bool 語彙 (DR-075) — #7 |
| `AttachMode` `EqSepMode` | enum (all) | b,k | short 値付着 / eq separator は matcher config (#7)。opaque data として engine を素通りすべき |
| `attach_mode_of` `eq_sep_mode_of` | fn | k | 上記語彙の decode (「at-require」等の綴り直書き)。#19: decode は住人所有 |

**(D-4) builtin 型の失敗語彙 (1 型 + fn 8 本) — 移動先: builtins (契約形は TRI-Q2)**

| identifier | 種別 | 消費 | 違反内容 |
|---|---|---|---|
| `ParseFail` (+ message/reason) | enum (all) | b | NotANumber/NotAnInteger/IntOutOfRange/NotABool/NoValueSpace — number/int/bool 住人の失敗の**閉じた列挙**。TypeExt::parse_token 契約に焼き込まれ、3rd party 型は独自の失敗 reason を宣言できない (descriptor の reasons 宣言 (DR-061) と非対称) — TRI-Q2 |
| `pe_parse` `pe_parse_bool` `pe_parse_int` `pe_parse_kv` `pe_int_out_of_range` `pe_type_parse` `parse_fail_error` | fn | b | reason/message 文言 ("not_a_number" / "is not a bool"…) ごと engine に直書き (src/engine/value.mbt:390-505)。値プリミティブの評価は builtin (#2) — エラー文言はその一部 |
| `pe_filter` | fn | b | KFilter エラーの一般構築。filter 機構の engine 移動 (builtins D 表) 後は engine 帰属で整合 — 移動でなくリネームのみ (例外的に D-4 から除き A-e 扱いでも可、表では D/Q 注記) |

**(D-5) sentinel 綴り・preset 意味論の直書き (fn 7 本 + 実装 1 箇所) — 移動先: builtins/assembly (TRI-Q9)**

| identifier | 種別 | 消費 | 違反内容 |
|---|---|---|---|
| `action_marker` `depr_marker` | fn | b | `"@act:" + name` / `"@depr:" + element` の綴りを engine が生成 (src/engine/eval.mbt:138 / value.mbt:513)。#3: sentinel 綴りは builtins 内部語彙、engine は meta 束縛の型区分のみ。builtins に deprecation_mark/failure_mark という wrapper が既在 — 実体ごと移す |
| `collect_actions` `argmin_action` | fn | k | `@act:` prefix の scan / fired_action 選定 — 同上 |
| `warnings_of` `warnings_structured` | fn | T / cli | `@depr:` sentinel から warnings を再構成 (src/engine/eval.mbt:149-236)。DR-110 #15 の残骸 — 玄関 (OutputView/resolve) が内部吸収し、kuu-cli の直呼びも玄関経由へ (TRI-Q4/Q9) |
| `classify_merge_piece` / `PieceMark` | fn / enum (all) | b | merge operand の `+`/`-`/`@` 分類 = merge accumulator の意味論 (#13: resolve 段の名前分岐直書きは住人の fold 実装へ) |
| `contains_eq` | fn | b | kv 住人の consume-time gate (DR-091)。kv は builtin 住人 — その構造前提判定が engine に居る |
| `is_integer` | fn | b | number/int 意味論の判定部品 (#2) |
| (identifier なし) `none_cells` 実装 | — | — | `ty.name() == "none"` の型名直書き (B 表の NoneCell 注記参照) — 判定を descriptor dispatch へ |

engine 小計: A-e 40 (trait 7 + 型 16 + fn 17) / B 20 / C 9 / C† 15 / D 37。
検算: 40+20+9+15+37 = 121 = engine top-level 全数 (163 identifier − メソッド 42)。

---

## リネーム一覧

D の移動・C の降格後も公開面に残る identifier の命名揺れ修正案。原則:
(1) 同概念は同語 (marker/mark、depr/deprecation の揺れを潰す)、(2) 暗号略語は
綴り切る、(3) 取り違えペアは役割語で分離。移動対象 (D) は移動先で新名を採用
(= 移動と別に旧名 rename パスを作らない)。

| 現名 (pkg) | 新名 (案) | 根拠 |
|---|---|---|
| ~~`mkb` (engine)~~ | `mk_binding` **(段 4 適用済み 2026-07-18)** | 名前から機能の手掛かりゼロ (コールドレビュー指摘)。`mk_effect` と対で統一 (第一候補側の `binding` は不採用: 動詞派生 `mk_*` を残して対称性優先) |
| ~~`mk_eff` (engine)~~ | `mk_effect` **(段 4 適用済み 2026-07-18)** | 略語解消、mk_binding と対で統一 |
| `pe_parse` `pe_parse_bool` `pe_parse_int` `pe_parse_kv` `pe_int_out_of_range` `pe_type_parse` `pe_filter` `parse_fail_error` (engine→builtins) | `parse_error_*` 接頭で綴り切る (例: `parse_error_not_a_number`)。D-4 移動時に住人 descriptor の reasons 語彙と揃える | `pe_` は parse error の暗号略語 (コールドレビュー指摘)。移動先で reason 名 ("not_a_number" 等) と一致させると grep 性が上がる |
| `depr_marker` (engine→builtins) | builtins 既存の `deprecation_mark` に統合 (wrapper と実体の 2 枚を 1 枚へ) | marker/mark・depr/deprecation の層跨ぎ揺れ (コールドレビュー指摘)。D-5 移動で自然解消 |
| `action_marker` (engine→builtins) | `failure_action_mark` (既存 `failure_mark` の対) または `effect_mark` 系に整列 | mark 系語彙へ統一 |
| ~~`InstallBuild` (engine)~~ | `InstallOutput` **(段 4 適用済み 2026-07-18)** | 「er」有無だけの取り違えペア。InstallBuilder::output の戻り型なので出力を表す語へ (`LoweredParts` は不採用: builder/output の語彙対称優先) |
| ~~`pend_value` (engine)~~ | `pending_value_candidate` **(段 4 適用済み 2026-07-18)** | pend の略語解消 + Pending Branch との関係を名前に (`value_cand` は不採用: 略語 `cand` を残さず綴り切る第一候補側) |
| ~~`cand_trigger` (engine)~~ | `trigger_candidate` **(段 4 適用済み 2026-07-18)** | 語順を英語法に (Cand 構築系で `*_candidate` に統一) |
| `cat` (engine) | 降格 (C†) するので公開名としては消滅。内部名は `concat` へ | 汎用 util 名の公開面ノイズ解消 |
| `lazy_` / `inherit_` (engine、pub フィールド) | `lazy` / `inherit` が予約語衝突なら `is_lazy` / `is_inherit` | trailing underscore の内部事情が公開フィールドに漏れている (コールドレビュー指摘) |
| `warnings_of` / `warnings_structured` (engine) | 玄関吸収 (TRI-Q9) 後、OutputView 側の 1 API に統合 (`warnings`) | 並立 + stringly (コールドレビュー指摘)。D-5 の移動とセット |
| `Warning.kind : String` (engine) | enum 化 (`WarningKind`) | stringly。ただし CONFORMANCE §2 の warnings 面が確定するまで保留可 |
| enum prefix 規約 (`At*`/`Es*`/`K*`/`D*`/`Pk*`/`Ek*`/`OD*`…) | **一括改名はしない**。D 移動で engine から消える enum (AttachMode/EqSepMode/PieceMark/OwnedDecl/RoundMode) が大半で、残る engine enum (ErrKind/DefErrKind/ExportKey) のみ将来課題 | コールドレビュー指摘は妥当だが、移動先で MoonBit の enum 名前空間 (`AttachMode::AtRequire` 修飾) により実害が小さい。改名コスト > 益 |
| `argmin_action` (engine→builtins) | `earliest_fired_action` (意味: 最小 position の action 選定) | argmin は数学語で動作が読めない |
| `node_resident_name` (builtins) | 降格対象 (C†)。残す場合 `node_kind` | resident は説明されない造語 (コールドレビュー指摘)。ただし DR 語彙 (住人) なので docs 側で定義されれば擁護可能 — 降格が先 |
| `AtomicAST` (kuu) | 維持 | 造語だが spec 正式語彙 (DR-023 系)。リネーム対象ではなく doc comment で定義を示す |
| `seat`/`SeatCtx` (engine) | 維持 | DR-031/099 の「席」は spec 語彙。同上 |

kuu-cli 追随が要るのは `warnings_*` 統合のみ (wire.mbt:3 箇所)。他は kuu-cli 未使用。

---

## 裁定が必要な境界ケース (Q ドラフト)

kawaz 裁定は統括が回す前提の下書き。ラベルは TRI-Q# (本バッチ一意)。

**TRI-Q1: installer 語彙 carrier (D-1/D-2、ElemDef/Definition/OwnedDecl 系 12 型) の移動方式**
現状 InstallerExt::decode / DefsView / InstallBuilder の**契約シグネチャ自体**が Definition/
DecodedOwnedDecl/OwnedDecl を参照するため、単純な builtins 移動は依存方向 (builtins→engine の
一方向) と矛盾する。
- a) **契約を opaque 化して carrier を builtins へ**: InstallerExt::decode の戻りを opaque data
  (Json または encode 済み decl) に変え、ElemDef/Definition/OwnedDecl は builtins 所有へ移動。
  DR-110 #9/#19 に最も忠実だが、install 契約の再設計 (Phase 3 最大工数) になる
- b) **engine 残置 + pub(all) 撤廃 (中間形)**: 型は engine に置くが「wire 断面の中立 carrier」
  と再定義し、外部構築を防ぐ (pub(all)→pub + ビルダ)。DR-110 §2-1 には「識別子として現れて
  はならない」に対し語彙フィールド名が残るので**規範完全準拠ではない**旨を DR 側に注記
- c) 現状維持 (擁護): 採らない — 発注の禁則「DR-110 と食い違う既存配置は D に入れて擁護しない」
- 推し: **a を最終形、初回サイクルは b で pub(all) だけ先に潰す 2 段構え** (a は open node 化
  TRI-Q5 と同じ再設計群に属し、単独で急ぐと手戻りする)

**TRI-Q2: TypeExt::parse_token の失敗契約 (D-4、ParseFail の閉じた列挙)**
- a) `Result[Value, ParseFail]` → `Result[Value, TypeParseFail]` で {reason, message} の開いた
  struct へ。builtin の reason 綴り ("not_a_number"…) は各型住人の descriptor へ移動
- b) ParseFail を engine に残し「よくある失敗の便宜列挙 + Custom(String, String) バリアント追加」
- 推し: **a** (descriptor の reasons 宣言 (DR-061) と対称になり、3rd party 型が自前 reason を
  出せる。b は閉じた列挙の延命)

**TRI-Q3: 汎用 util (cat/to_chars/chars_to_str/split_on/value_str) の降格方式**
MoonBit に pkg 間の internal 可視性が無い前提で、層跨ぎ消費 (builtins/kuu) がある。
- a) **各消費 pkg に priv 複製** (数行の全域関数。重複コスト < 公開面コスト)
- b) engine/internal サブ pkg を切って隔離 (mbti は残るが「触るな」が構造化される)
- c) MoonBit core の標準 API (`String::to_array` 等) への置換で消滅させられるものは置換
- 推し: **c を先に適用し、残りは a** (b は pkg 増設の割に mbti 露出が消えない)

**TRI-Q4: kuu 玄関の径路整理 (result/sources/build_result/accum_cells/apply_export_keys/export_map)**
コールドレビュー指摘「径路 3 本が型から読み分け不能」+ kuu-cli の Ambiguous 描画が内部部品
直呼び (wire.mbt:229-235) + `ast.root` フィールド直触り。
- a) **OutputView (output) を唯一の結果径路に**: result/sources は deprecated → 削除、
  Ambiguous 解釈ごとの描画は `output_of_interpretation(ast, interp)` 相当の玄関 API を足して
  kuu-cli の部品直呼びを解消 → build_result/accum_cells/apply_export_keys/export_map/AccumCell/
  DefaultCell を降格、AtomicAST フィールドを opaque 化
- b) 現 3 径路維持 + doc で正道を明示
- 推し: **a** (DR-110 §5「利用者が呼ぶのは assembly の玄関だけ」の残債。issue
  2026-07-17-interpretation-view-filter-front-door と同件なので統合して進める)

**TRI-Q5: Node enum の公開範囲 (open node 化の残作業)**
PKG-Q1=a (open node 契約) は裁定済みだが、現 Node は 18 バリアント pub(all) の閉じた enum。
- a) **本サイクルでは pub(all) → pub (パターンマッチ可・外部構築不可) に絞るだけ**。バリアント
  削減 (DdSat/CmdSat 等の satellite を Ext 移行) は open node 化の実装 issue へ分離
- b) 本サイクルで satellite バリアントの Ext 化まで踏み込む
- 推し: **a** (b は評価器の書き換えを伴い、公開面棚卸しのスコープを超える。MoonBit は
  pub enum でも外部パターンマッチ可能なので、mbti 上の見え方は変わらず破壊面だけ縮む)

**TRI-Q6: resolve 支援走査群 (C†: collect_scopes/elem_value/is_committed 系 + constraint_err) の帰属**
現 resolve (値源ラダー遂行 + constraint 検証) は kuu 実装で、engine の C† fn 群に依存。
DR-110 §3-5 は「ラダー骨格 + 充填の一般機構は engine」とする。
- a) resolve の機構部分を engine へ引き上げ、C† 群は engine 内部化 (pub 降格)
- b) 現配置維持 (resolve は kuu)、C† 群は「resolve 機構の契約」として A-e に格上げ再解釈
- 推し: **a の方向だが本サイクルでは判定保留・pub 維持** (resolve の帰属は径路整理 TRI-Q4 と
  UX-Q7R 系の設計判断で、公開面の裁定だけ先行すると手戻る)

**TRI-Q7: Entity のフィールド絞り (PKG-Q2=a の実施形)**
config_seat/is_config_file/inherit_/flatten/is_multiple_decl/piece_filters×4/separator は
builtin 固有宣言に見える。engine 最小 Entity (名前・席宣言・extension) + descriptor 側へ移す
具体形は境界の引き直しになる。
- a) 本サイクルで最小 Entity へ再設計
- b) **issue 分離** (boundary survey #14 の中間形の設計は独立の設計課題)
- 推し: **b** (ElemDef 構造化 (発注 issue の「別判断」) と同じ理由 — 影響が広い)

**TRI-Q8: lower_definition の extensions? default (組成表の暗黙所有)**
`extensions? = default_extensions()` (= builtins が全部入り registry を暗黙生成、
src/builtins/installer.mbt:3963) は DR-110 §2-3 (組成は assembly 所有) 違反。
- a) **default を外して必須引数化**、組成は kuu の canonical_registry だけが持つ
- b) default 維持 (subset assembly は明示引数で可能なので実害小、と擁護)
- 推し: **a** (「デフォルトで全部入り」は組成表の複製。呼び出し側は kuu と wbtest のみで
  追随コストが小さいことを確認済み)

**TRI-Q9: sentinel/warnings/action の engine 内部残存 (D-5) の解消順序**
`@depr:`/`@act:` 綴り・merge/kv 意味論・`ty.name()=="none"` 判定は、評価器・resolve の実装に
編み込まれており、単純な fn 移動では消えない (meta 束縛の型区分 (DR-110 #3) の導入が要る)。
- a) 本サイクルで meta 束縛の型区分まで実装
- b) **fn の公開面だけ先に処理** (warnings_* は玄関吸収 (TRI-Q4 とセット)、action/depr marker
  fn は builtins へ移して engine 側は内部 fn 化)、綴りの完全排除 (型区分導入) は
  open node 化と同じ後続実装 issue へ
- 推し: **b** (公開面の衛生と内部実装の規範準拠を分離。DR-110 波及の実装 issue が既にこの
  領域をカバーしている)

---

## Phase 3 の実装計画 (移動・降格の依存順序)

原則: **「消費者が先、供給者が後」** — kuu-cli / kuu の呼び替えを先に済ませ、その後で
pub 降格・移動する (逆順だと中間状態がビルド不能)。conformance green を各段で維持。

### 段 0: 裁定待ちなしで着手可能 (即日)

1. **完全 dead の削除** (どこからも参照ゼロ、テスト含め無傷):
   engine `committed`/`rval_*` 3 本/`none_cell` (priv 化)、builtins `configured_short_type`。
   `Resume`/`LowerSeat` は契約シグネチャへの適用 (リネーム一覧の統一方針) と同時に処理
2. **priv 明示化** (mbti ノイズ除去): kuu `ExportCollision`/`ScopeConfig`/`TypeShadow`
3. **テスト専用 pub の wbtest 内取り込み or priv 化**: engine `parse_context`/`run_matcher`/
   `node_consumes_zero_tokens` (`warnings_of` は D-5 の玄関吸収側で処理するのでここでは触らない)。
   builtins のテスト専用住人 factory 群は **subset assembly 材料 (A-b) なので降格しない**
   (テスト専用でも契約)
4. **builtins 内部 pub の降格**: `sep_binds`/`split_colon`/`node_effect_mark`/
   `node_is_failure_mark`、`parse_bool`/`parse_*_ext` 群の optional 引数 1 本化 + 降格

### 段 1: filter 契約の engine 移動 (発注確定分、裁定不要)

5. engine に `FilterExt` 相当の descriptor 契約 (name/signature/reasons/run) + Registry の
   filter 系統 (register_filter/lookup_filter、scalar/array の 2 面) を増設
6. builtins の filter 住人 19 本を新契約の実装に載せ替え、`lookup_filter`/`lookup_array_filter`
   を engine 経由に、`apply_*_filter_chain` 3 本を engine の呼び出し機構へ移動
7. kuu の消費 (installer.mbt の transform 検査、resolve の chain 適用) を engine 径路へ切替、
   builtins 旧 API を削除。**3rd party filter が builtins 非依存で書けることを synthetic 住人の
   wbtest で確認** (発注の受け入れ条件)
8. 組成の是正 (TRI-Q8=a なら同時): `install`/`install_installers` を kuu へ移し、
   `lower_definition` の extensions? default を外す

### 段 2: 径路整理と玄関強化 (TRI-Q4 裁定後)

9. kuu に Ambiguous 解釈描画の玄関 API を追加 → kuu-cli の `build_result`/`accum_cells`/
   `apply_export_keys`/`export_map`/`ast.root`/`@engine.warnings_structured`/`@engine.none_cells`
   直呼びを玄関へ乗り換え (**kuu-cli 追随が必須の段**)
10. kuu の `result`/`sources`/`build_result` 系 6 identifier を降格、AtomicAST フィールド opaque 化
11. D-5 の fn 移動 (warnings_* 玄関吸収、action/depr marker の builtins 移動 — TRI-Q9=b の範囲)

### 段 3: 語彙 config・失敗語彙の移動 (TRI-Q2 裁定後)

12. D-3: RoundMode/BoolConfig/AttachMode/EqSepMode + `attach_mode_of`/`eq_sep_mode_of` を
    builtins へ (ElemDef が参照するため **TRI-Q1 と同時でないと不可** — ElemDef のフィールド型に
    現れる)。TRI-Q1=b (engine 残置) の場合はこの段も engine 残置で pub(all) 撤廃のみ
13. D-4: ParseFail 契約の開放 (TypeExt::parse_token シグネチャ変更 = **全型住人 + synthetic
    テストの一斉追随**) と pe_* の移動・リネーム

### 段 4: 凍結

14. リネーム一覧の適用 (moon ide rename、`--apply` 後は jj diff で誤爆確認 — moonbit-tips rule)
    - **2026-07-18 部分適用**: D 移動 / C 降格 / TRI-Q 裁定と独立な純 rename 5 件のみ (mkb → mk_binding /
      mk_eff → mk_effect / InstallBuild → InstallOutput / pend_value → pending_value_candidate /
      cand_trigger → trigger_candidate)。適用後 moon fmt / check --deny-warn / just test 全 green、
      json-conformance 293/702 mismatches=0 skipped=0。**スコープ外に残した項目**:
      - `pe_*` / `depr_marker` / `action_marker` / `argmin_action` — D-4/D-5 移動 (段 3 / 段 2) が前提
      - `cat` / `node_resident_name` — C†降格 が前提
      - `warnings_of` / `warnings_structured` / `Warning.kind` — TRI-Q4/Q9 裁定 + 玄関吸収が前提
      - `lazy_` / `inherit_` — MoonBit 予約語衝突有無の実機裁定 + `is_*` prefix 統一の裁定が前提
        (findings 記述は条件付き、コメントには MDR-003 で予約語回避明記)
      - enum prefix 一括改名 — 一覧側で「改名しない」と明記済み
      - `AtomicAST` / `seat`/`SeatCtx` — 一覧側で「維持」明記
15. mbti 再生成 + **mbti drift gate で凍結** (受け入れ条件)。moon test / conformance green 確認
    - **2026-07-18**: mbti 再生成のみ完了 (drift gate 凍結は残タスク完了後)
16. kuu-cli pin bump + lockstep push (spec 側変更は無い見込みだが、DR-110 注記 (TRI-Q1=b 採用時)
    が要るなら spec push が先)

### 依存の要点

- 段 0/1 は独立に進められる。段 2 は TRI-Q4、段 3 は TRI-Q1/Q2 の裁定待ち
- **kuu-cli 追随が要るのは段 2 (径路乗り換え) と段 4 (pin bump) のみ**。段 0/1/3 は kuu-cli の
  参照面 (玄関 + 出力型) に触れない
- ElemDef 構造化 (55 フィールドのサブ構造畳み込み) と open node 化・meta 束縛型区分は
  本サイクルから **明示的に除外** (発注 issue の「別判断」+ TRI-Q5/Q7/Q9 の推し) — 後続 issue

