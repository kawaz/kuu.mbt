# MDR-006: engine / builtins / kuu の package 分離 — DR-110 の MoonBit 実装設計

Status: Draft (統括審査待ち)

> 由来: kawaz/kuu DR-110 (kuu-core 標準パッケージング — engine / builtins / assembly の
> 3 層、PKG-Q1〜Q4 裁定 2026-07-16)。本 MDR はその参照実装側 (PKG-Q4=a の「実装は spec
> 規範に従う」側) で、実現手段は `docs/findings/2026-07-16-moonbit-open-dispatch-poc.md`
> (以下 PoC findings)、争点の実装箇所は
> `docs/findings/2026-07-16-engine-builtin-boundary-survey.md` (以下 boundary survey、
> 争点番号 PKG-#N の正本) に基づく。里程標 M1〜M5 の分割は統括確定 (2026-07-16)。
>
> 規範 (何が engine / builtins / assembly に属するか) は DR-110 §2〜§6 が正本であり
> 本 MDR は複製しない。本 MDR が決めるのは **MoonBit でどう実現するか** — 物理
> package 構成、可視性、契約シグネチャ、テスト配置、移行手順 — のみ。

## 決定

### 1. 物理 package 構成

`moon.mod` の `source = "src"` は不変。`src/core` 単一 package を 3 package に再編する:

| package dir | import path | 層 (DR-110 §1) | 主な内容 (再編後) |
|---|---|---|---|
| `src/engine` | `kawaz/kuu/engine` | engine | 構造 Node 骨格 + open node 契約 / cont / eval 骨格 / registry 機構 / resolve 骨格 (ladder 席順序・結果構築一般写像・export-key) / outcome 骨格 (complete 走査) / wire 構造骨格 decode + orchestrator |
| `src/builtins` | `kawaz/kuu/builtins` | builtins | canonical installer 13 種 / 値プリミティブ 5 型 + preset 型 (flag/count/tty) / matcher 具象 (eq-split / short-combine) / filter・accumulator・collector 住人 / 各住人の wire decode / sentinel 綴り |
| `src/kuu` | `kawaz/kuu/kuu` | assembly (kuu) | canonical set の組成・登録 (`install`) / front_door (MDR-005 の 3+補助契約) / conformance runner |

依存方向は moon.pkg の import で強制する: `kuu → {builtins, engine}`、`builtins → engine`、
`engine → (moonbitlang/core のみ)`。MDR-002 §3 のファイル依存順 (同一 package 内の
soft convention) は、この package 境界へ**昇格**する — engine 内部に残るファイル群
(node / cont / eval / resolve / outcome の骨格部) の間では従来の順序を維持する。

- **import path の吃音 (`kawaz/kuu/kuu`)**: assembly の import path は module 名との
  重複で `@kuu` に解決される (default alias = 末尾セグメント)。代替として source
  ルート直下 package (`src/moon.pkg`、import path = `kawaz/kuu` そのもの) が module 内
  では成立することを実機確認済みだが、**外部 module からの root package import は
  未検証**のため、検証済みパターンである `src/kuu` を採る (吃音は cosmetic、利用者の
  参照綴りは `@kuu.` で同一)
- **TOML moon.pkg に import alias 構文は無い** (moon 0.1.20260709 実機、`as` / `:` /
  `=` / inline table / `@` / `->` の 6 構文全て parse error。JSON 形式 `moon.pkg.json`
  の `{ "path": ..., "alias": ... }` のみ成立)。従って下流が旧 `@core` 綴りを保つには
  moon.pkg の JSON 化が必要 — 採らない。下流 (kuu-cli) は `@kuu` へ機械 rename する
  (§7)

### 2. 可視性設計 — 実機で確定した MoonBit の可視性意味論の上に組む

**前提の訂正 (実機検証 2026-07-17、moon 0.1.20260709)**: `pub` (read-only) 型は
cross-package で **フィールド読み取り・enum variant のパターンマッチが可能**であり、
禁止されるのは**構築のみ** (Error 4036/4033)。MDR-005 §3 の「フィールドアクセス不可
(abstract type)」および PoC findings の「field/constructor 参照はできない」という
記述は誤り — kuu-cli `wire.mbt:575` が `sc.entities` (pub `Scope` のフィールド) を
読み、`wire.mbt:594-609` が pub `Node` の variant を match して現に compile が通って
いることが production 側の反証。フィールド単位の `priv` 修飾は読み取りも隠す
(Error 4091、実機確認)。

この意味論を踏まえた三分類 (PKG-#17、DR-110 §6 #17 の分類基準に従う):

| 区分 | 消費者 | 可視性 | 対象 (代表) |
|---|---|---|---|
| **利用者玄関** (assembly 契約) | kuu-ux / kuu-cli / runner | `pub(all)` (構築も許す入力型) + `pub` (読むだけの出力型) | `Outcome` / `Binding` / `Value` / `Cand` / `DefError` / `DefLoadError` / `Warning` / `SourceEntry` / `RVal`、入力構築子 (`config_from_json` / `tty_obs`) |
| **extension 実装者** (engine 契約) | builtins + 3rd party 拡張 + RPC proxy | `pub(open)` trait + read-only `pub` 型 + factory / capability method | `NodeExt` / `MatcherExt` / `InstallerExt` / `TypeExt` / 各 descriptor trait、`Ctx` / `Branch` / `Registry` / `Node` (構造 variant) / `Scope` / `Entity` (最小形) |
| **package 内部** | 自 package のみ | `priv` 型 / `priv` フィールド | `Cont` ADT (Resume 関数型の背後に隠蔽)、completes-cache、matcher 具象の構成データ、sentinel 綴り定数 |

- **`Ctx` は read-only `pub` + capability method** (PoC 示唆 3): builtins が必要と
  する能力 (token 参照 `token_at`、mode 判定 `is_complete_mode`、Branch 構築 factory
  `accept` / `held` / `pending`、ParseError 構築子) を method / factory で提供し、
  フィールドは `priv` 修飾。engine 内部状態 (toks / target / memo テーブル) を
  extension ABI から遮断する
- **`pub` enum の variant は match 可能に「漏れる」ことを設計上許容する**: 隠したい
  内部 ADT (`Cont`) は enum を pub にせず、関数型 (`Resume`) の背後に置く (§3)。
  逆に `Node` の構造 variant (Exact / Or / Seq / …) は engine 契約の一部なので
  match 可能で構わない (推移的可視性制約 4046 により、pub 型のフィールド型は最低
  pub が要る — MDR-005 §3 の確認結果は有効)
- **テスト都合の pub は契約に数えない** (DR-110 §6 #17): 現行の wbtest 都合 pub
  (`pub(all) Cand` の内部 3 フィールド等) は M5 の棚卸しで、blackbox からの読み取り
  需要が本当にあるもの (read-only `pub` で足りる) と純内部 (priv フィールド化) に
  仕分ける

### 3. 契約シグネチャ案

DR-110 射程外の明記どおり「言語別シグネチャは各実装の関心」— 以下が MoonBit 実装の
正本案。PoC の最小形からの拡張点は各所に注記する。実装時の細部変更は本 MDR の追記で
記録する。

#### 3.1 open node 契約 (PKG-#1 案 B / PKG-Q1=a、DR-110 §3-2)

```moonbit
// engine — 拡張 node の評価継続。defunctionalized Cont (MDR-002 §1) は
// この関数型の背後に隠蔽され、extension ABI に現れない (PoC 示唆 2)。
pub type Resume = (Ctx, Int, Array[Binding]) -> Array[Branch]

pub(open) trait NodeExt {
  kind(Self) -> String                    // registry 語彙 (ns 付き descriptor identity、例 "builtin/string")
  encode(Self) -> Json                    // 安定直列形: 構造比較・表示・lowering 断面の素材 (DR-110 §3-4 の encode 対称)
  equal(Self, &NodeExt) -> Bool = _       // default = kind 一致 && encode 一致
  consumes_zero_tokens(Self) -> Bool      // 消費数の契約データ (PKG-#18): 0 トークンで束縛のみ寄与する node か
  eval(Self, Ctx, Int, Array[Binding], Resume) -> Array[Branch]
}

enum Node {                               // engine 内蔵は構造骨格のみ (DR-110 §3-1)
  Exact(String)
  Or(Array[Node])
  Seq(Array[Node])
  Ref(String)
  ScopeNode(Scope)
  Bind(String, Value)
  Many(Node, Bool)
  Scoped(String, Node)
  Rooted(Node, Int)
  BoundedTail(...)
  NativeMatch(&MatcherExt)                // matcher は opaque 住人 (§3.2)
  Ext(&NodeExt)                           // 拡張 node の単一 variant (PoC 推奨形)
}
```

- PoC の `fingerprint : String` は `encode : Json` に置き換える: lowering fixture の
  断面比較 (LOWERING §C.5) と wire decode (#19) の対称を 1 契約で兼ね、collision の
  ない identity は `kind + encode` の組で構成する (PoC 示唆 4 の本実装形)
- **trait default method は cross-package impl で動作する** (実機検証 2026-07-17:
  `equal(Self, &Ext) -> Bool = _` + `impl Ext with equal` の default 本体を engine に
  置き、builtins の具象がオーバーライドなしで継承して green)。equal の既定実装を
  engine 側に一本化でき、各住人は kind / encode だけ書けばよい
- `eval` の acc は PoC の `Array[String]` から本実装の `Array[Binding]` へ。mode
  (parse / complete) は `Ctx` 経由 (MDR-002 の EvalMode threading を維持)。Pending
  の Cand 構築は `Ctx` の factory 経由

#### 3.2 matcher 契約 (PKG-#5 / #6、DR-110 §3-4)

```moonbit
pub(open) trait MatcherExt {
  kind(Self) -> String
  encode(Self) -> Json                    // 「matcher = 名前付きデータ」(DR-042) の直列形。LOWERING §C.5 の断面はこれを比較する
  equal(Self, &MatcherExt) -> Bool = _
  interpret(Self, Ctx, Int, Array[Binding], Resume) -> Array[Branch]
}
```

eq-split / short-combine は builtins の住人となり、`LongEntry` / `ShortEntry` /
`Matcher` enum と型別分岐 (TFlag/TCount の presence-only、count の
`Update("increment")` 直書き = boundary survey が最悪の癒着とした箇所) は matcher
具象の内部へ移る。engine の `run_matcher` は interpretation ループ (全 reading 平等、
DR-041 §3) だけ残る。

#### 3.3 型契約 (PKG-#2 / #4 / #7 / #10 / #11)

```moonbit
pub(open) trait TypeExt {
  name(Self) -> String                    // 基底綴り ("string"/"number"/"int"/"float"/"bool"/…、DR-104 §2 の wire 語彙)
  has_value_slot(Self) -> Bool            // presence-only 判定 (旧 TFlag/TCount/TNone 分岐の代替)
  parse_token(Self, String) -> Result[Value, ParseFail]   // 値スロット解釈 (canonical 字句は住人所有、DR-074/075)
  default_seat_resolver(Self, SeatCtx) -> Value?          // 席内解決子 (tty の fold??default / flag/count preset、DR-110 §3-5 の descriptor dispatch)
}
```

- `Ty` enum は engine から**除去** (PKG-#4)。値プリミティブ 5 型 + preset 3 型は
  `NodeExt` + `TypeExt` を実装する builtins 住人になる
- `Entity` は engine 最小形 (PKG-Q2=a): `name` / 席宣言 / accum 名 / `&TypeExt` 参照 /
  完全に opaque な拡張宣言の運搬 slot。型 config (RoundMode / BoolConfig /
  EqSepMode / AttachMode) は各住人の構成データへ移り engine を素通りする (PKG-#7)
- `Cand.ty : Ty` は `Cand.ty : String` (DR-104 §2 の基底綴り) に変わる — 利用者玄関の
  **破壊的変更** (§7 で kuu-cli 移行を扱う)。DR-104 §2 が候補の型情報を基底 5 種の
  綴りで規範化しているため、enum より wire 綴り文字列の方がむしろ仕様に近い

#### 3.4 install 契約と registry (PKG-#8 / #9 / #19、DR-110 §3-6/7/8/11)

```moonbit
pub(open) trait InstallerExt {
  vocab(Self) -> Array[String]                            // 所有語彙 (DR-042 不変則③ の交差検査素材)
  decode(Self, Json, DecodeCtx) -> Result[OwnedDecl, DefError]  // 自所有語彙分の wire decode (PKG-#19 の住人分散)
  apply(Self, Builder) -> Unit                            // lowering 寄与 (不動点反復の 1 step、DR-042 5 不変則)
  collect_defs_errors(Self, DefsView) -> Array[DefError]  // 自所有分の定義時検査 (PKG-#8。generic 2 検査のみ engine)
}

pub struct Registry { priv ... }                          // 名前 → 住人 (node / matcher / installer / type / filter / accumulator / collector)
pub fn Registry::new() -> Registry
pub fn Registry::register_installer(Self, &InstallerExt) -> Unit   // 種別ごとの register 群
...

// builtins — 登録は明示 install 方式 (PoC 示唆 6: package-level side effect は
// reachability 依存で全 target 不発を実機確認済み。暗黙登録は設計として不成立)
pub fn install(reg : @engine.Registry) -> Unit

// kuu — canonical set の組成正本 (DR-110 §2-3)。全部入り以外の subset assembly も
// この関数の差し替えで作れる (DR-110 §7)
fn canonical_registry() -> @engine.Registry
```

`Installer` の閉じた enum と `full_installers()` の hard-coded 列は廃止。wire decode
は「engine = 構造骨格 decode + 各住人へ委譲する orchestrator / 住人 = 自所有語彙の
decode」に分散する (`dec_option` の allowed_keys 一枚表は、登録済み住人の vocab の
和として計算される — DR-061 §2 と同じ所有で decode 可能性が決まる)。

#### 3.5 filter / accumulator / collector (PKG-#12 / #13)

既存の `FilterDescriptor` / `ArrayFilterDescriptor` は struct 形のまま builtins へ
移し、fresh-Map 直書きの `filters_registry()` を engine `Registry` への登録に変える。
resolve 段の accumulator 名分岐直書き (merge → `resolve_merge_accum`、kv_map → RObj、
append → fold) は住人の fold / collect 実装へ移し、engine は cell の descriptor
dispatch だけ持つ。

### 4. テスト配置と既存 wbtest の行き先

PoC 事実「`_wbtest` は package 横断 friend ではない」(Error 4021) を前提に:

- **engine**: package-local `_wbtest.mbt`。**builtin 語彙を前提にできない** (DR-110
  §2 禁止事項 1 の帰結) ため、値プリミティブの代わりに wbtest ファイル内で定義する
  **合成 (synthetic) NodeExt 住人**で spine / CPS / 取り分選好の契約を検証する
- **builtins**: package-local `_wbtest.mbt` (住人の内部 invariant) + engine 公開
  API 経由の blackbox `_test.mbt` (住人が extension interface だけで動く証明 —
  DR-110 §2-2 の差し替え可能性の常設検査を兼ねる)
- **kuu**: conformance runner。fixture 駆動の parse / complete / resolve / def-error
  系は blackbox `_test.mbt` (front_door のみ消費)、lowering fixture の構造断面
  (LOWERING §C.5) は §3 の encode 契約経由で blackbox 化する

既存 10 本の行き先 (boundary survey は「11 本」と書くが、実在は 10 本 — `ls
src/core/*_wbtest.mbt` で確認):

| 現行 wbtest | 行き先 | 備考 |
|---|---|---|
| `json_conformance_wbtest.mbt` | kuu (fixture 系 → `_test.mbt`、lowering 断面 → 経過期は `_wbtest.mbt`) | §6 M1 の罠を参照 |
| `eval_wbtest.mbt` | engine `_wbtest` | 手組み `StrArg`/`NumArg` 葉を合成 NodeExt に置換 (phase16 / REVIEW-H1 等の意図は不変で葉だけ差し替え) |
| `complete_wbtest.mbt` | engine `_wbtest` (走査骨格) + kuu (builtin 語彙込みの候補形) | Pending 収集の骨格と候補メタ運搬は engine 契約 |
| `matcher_wbtest.mbt` | builtins `_wbtest` | eq-split / short-combine は住人 |
| `value_wbtest.mbt` | builtins `_wbtest` | canonical 字句 (DR-074/075) は住人所有 |
| `installer_wbtest.mbt` | builtins `_wbtest` | lowering 具象。engine 型は公開 API 経由で組む |
| `filters_wbtest.mbt` | builtins `_wbtest` | |
| `wire_decode_wbtest.mbt` | engine (構造骨格 decode) + builtins (住人 decode) に分割 | |
| `resolve_wbtest.mbt` | engine (ladder 骨格 / export-key / 衝突検出) + builtins (merge / kv_map / tty 席) に分割 | |
| `front_door_wbtest.mbt` | kuu `_wbtest` (内部) + `_test.mbt` (公開 API e2e) | |

blackbox `_test.mbt` の test 専用 import は `import { ... } for "test"` 構文で通る
(実機確認済み。現行の `for "wbtest"` と対)。KUU_FIXTURES の読み取り
(`moonbitlang/core/env`) と fs は kuu の test import に移る。

### 5. MoonBit 制約の織り込み (PoC findings の設計への昇格)

1. **derive(Eq, Debug) の喪失は Node に留まらず連鎖する**: `Ext(&NodeExt)` を持つ
   `Node` は derive 不可 (Error 4018) → `Node` を含む `Scope`、`Scope` を含む
   `Cont` / `ScopedCons`、`Entity` (&TypeExt 参照を持つ) まで derive(Eq, Debug) が
   連鎖的に外れる。対処: engine が `Node` / `Scope` / `Entity` の Eq を手書きし
   (`Ext` arm は `NodeExt::equal` に委譲)、表示は encode 経由。この Eq は
   (a) DR-042 の順序非依存 permutation test (AST 比較)、(b) `Cont` の構造比較
   (MDR-002 §1.3 の completes-cache のキー。メモ化は未実装だが足場を壊さない) の
   2 消費者を持つ — **手書き Eq は「テスト便宜」でなく engine 契約の一部**として
   扱い、engine `_wbtest` で reflexivity / kind 不一致 / encode 不一致の輪郭を固定する
2. **object safety**: `Self` 戻り値・第 2 `Self` 引数は trait object 化不可 (Error
   4038)。clone 系・具象 factory は trait に入れず住人の inherent method / package
   関数に置く。比較は `equal(Self, &Trait)` 形 (PoC 1d で成立確認)
3. **明示 install**: package-level initializer は reachability 依存で発火しない
   (PoC 6c、3 target 全部で不発)。登録経路は `kuu` の `install` 呼び出しのみ。
   conformance runner・各 blackbox test も同じ `canonical_registry()` を呼ぶ
   (組成表の二重管理を作らない)
4. **orphan rule**: 「engine の open trait × builtins の自型」のみ成立 (Error 4061)。
   3rd party 拡張にも同じ制約が掛かる — extension interface のドキュメントに明記する

### 6. 実施計画 M1〜M5 (統括確定の分割を採用)

各里程標の完了条件 = **moon test green (deny-warn 込み) + conformance
decoded=272 / ran=663 / skipped=0 / mismatches=0 の維持** (移設で件数が変わる場合は
「fixture の増減なしで runner 側の数え方が変わった」ことを里程標の記録に明記) +
対象争点の解消。里程標の末尾ごとに main へ push する (里程標内は複数 commit 可、
main が red の状態を push しない)。

- **M1 — 物理 3 package の骨組み**: `src/{engine,builtins,kuu}` の moon.pkg 新設、
  既存 core の中身は一旦 kuu へ、conformance runner を kuu へ移設 (PKG-#16)。
  - **罠 (runner の private 依存)**: runner は非 pub 関数 (`full_installers` /
    `has_commands` / `collect_sources_flat/tree` / `resolve_scope_*_with_export` /
    `default_scalar`) と pub 型の構築 (`Installer` 値の `dec_installer` 構築、
    `ScopeNode(df.scope)` 直組み) に依存しており、これらは blackbox からは不可能
    (構築は pub でも 4036)。**M1 で全面 blackbox 化はできない** — M1 では runner を
    kuu の `_wbtest.mbt` として移し (同一 package 内なので可視性変更ゼロ)、fixture
    系の blackbox `_test.mbt` 化は M2〜M5 で各断面が公開契約 (encode / registry
    lookup) を得るたびに段階昇格、M5 完了時に blackbox が最終形。統括の里程標文言
    「blackbox _test.mbt へ移設」との差分はこの段階化 — 一括 blackbox 化は M1 時点で
    大量の一時 pub 化 (M5 で剥がすもの) を要し工程が往復するため
  - kuu-cli の import path 断絶がこの時点で発生する (§7)
- **M2 — Node open 化**: `Ext(&NodeExt)` + NodeExt 契約 (§3.1、consumes 契約 =
  PKG-#18 込み)、値プリミティブ 5 型 (Str/Num/Int/Float/Bool arg) を builtins の
  拡張 node へ (PKG-#1 / #2)。eval の値 arm 7 種と `is_zero_token_marker` の variant
  列挙が消える。derive 喪失の手書き Eq (§5-1) はここで入る
- **M3 — matcher opaque 化 + Ty 除去**: eq-split / short-combine を `&MatcherExt`
  住人へ、`Ty` enum 除去、型・matcher config (RoundMode / BoolConfig / EqSepMode /
  AttachMode) を住人構成データへ (PKG-#4 / #5 / #6 / #7)。matcher の count →
  `Update("increment")` 直書きは PKG-Q3=a どおり自然消滅を確認する (独立修正を
  しない)。`Cand.ty : String` 化はここ (kuu-cli 追随第 2 波、§7)
- **M4 — installer trait 化 + decode 分散**: `InstallerExt` (§3.4)、`Installer`
  enum / `full_installers()` 廃止、wire decode の住人分散、`collect_*` 20 本の住人
  分散 (generic 2 検査のみ engine 残留) (PKG-#8 / #9 / #19)
- **M5 — registry 住人化 + 玄関の assembly 化 + 棚卸し**: filter / accumulator /
  collector の registry 住人化 (PKG-#12 / #13)、sentinel 内部化 + `is_sentinel` pub
  廃止 (PKG-#3 / #15)、Entity 最小化と seat / preset / ladder の descriptor dispatch
  (PKG-#10 / #11 / #14)、complete 走査の opaque 運搬 (PKG-#20)、front_door の kuu
  assembly 化 (PKG-#21)、pub 三分類の棚卸し (PKG-#17)、conformance runner の
  blackbox 最終化

### 7. kuu-cli への影響 (破壊的変更の明示) と移行パス

kuu-cli (`impl/mbt/cli`) は `moon.pkg` 2 箇所で `"kawaz/kuu/core"` を import し、
`@core.` 参照 116 箇所 (wire.mbt 104 + main.mbt 12) を持つ。さらに
`deps/kuu.mbt -> ../../../../../kuu.mbt/main` の **symlink で HEAD 直結**のため、
kuu.mbt の M1 push は kuu-cli のローカル build を即座に壊す。破壊は 3 波:

1. **M1 (import path)**: `"kawaz/kuu/core"` → `"kawaz/kuu/kuu"` + `@core.` → `@kuu.`
   の機械 rename。M1 push と**同一窓**で kuu-cli 側 commit を続けて出す (lockstep。
   TOML moon.pkg に alias が無いため rename 以外の吸収手段は moon.pkg の JSON 化のみ
   — 採らない)
2. **M3 (`Cand.ty` の String 化 / `Ty` 消滅)**: `ty_str` / `is_tnone` の match が
   壊れる → `ty_str` は削除して文字列を直接使う (DR-104 §2 綴りが直接届くため簡素化)
3. **M5 (sentinel / 内部走査の玄関吸収)**: `is_sentinel` 消費 (effects 組み立ての
   skip) と `Scope` / `Node` 走査 (`is_dd_cell_scan` / `is_excluded_cell` — dd·
   config_file·TNone セルの内部マーカー除外) が壊れる。**front_door が sentinel と
   内部マーカーを吸収した出力ビューを提供する**のが DR-110 §4/§5 の要請であり、
   kuu-cli の手元走査はそのビューへの乗り換えで消える。task #14 (front_door 経由で
   repeat rows の行集約が落ちる K カテゴリ) と同根 — **M5 の front_door 出力整形の
   設計に「effects / rows / 内部セル除外」の需要を明示的に入れる** (単なる pub 削除
   では kuu-cli が再実装で漏れ穴を掘る)

### 8. 既存 MDR との整合

- **MDR-002 §3**: モジュール依存順は package 依存へ昇格 (§1)。評価器契約 (CPS /
  Pending / KTop 完全性) は不変 — `Cont` の外形が `Resume` 関数型に包まれるのみ
- **MDR-005**: front_door の関数名・引数・意味論 (parse_definition / parse /
  resolve / complete + 補助) は kuu assembly の顔として**維持**。§4「単一 package の
  まま (分割不採用)」は本 MDR が **supersede** する (当時の判断は「公開面
  キュレーションの目的には分割不要」— DR-110 は特権排除という別の目的を導入した)。
  §3 の可視性記述のうち「pub はフィールドアクセス不可」は §2 の実機結果で訂正
- **MDR-001 §4**「公開 API が固まってから分割する」の分割判断が本 MDR で確定

## 採用しなかった案

### assembly を source ルート直下 package (`src/moon.pkg`、import path `kawaz/kuu`) にする

利用者の import が `"kawaz/kuu"` → `@kuu` になり吃音が消える。module 内での root
package + subpackage 共存は実機成立を確認したが、外部 module からの root package
import は未検証で、M1 の骨組みに未検証パターンを混ぜるリスクに見合わない。吃音は
import path のみで参照綴り (`@kuu.`) は同一。後日検証の上で移す余地は残る (import
path の変更は下流 rename 1 回で済む)。

### M1 で conformance runner を一括 blackbox `_test.mbt` 化する

runner の private 依存 (§6 M1 の罠) を一時 pub 化で満たす必要があり、M5 の棚卸しで
剥がす往復工程になる。段階昇格 (M1 = kuu 内 wbtest、M2〜M5 で断面ごとに blackbox へ)
が単調で、各里程標の「何が公開契約になったか」の検査を兼ねる。

### 下流互換のため旧 `src/core` package を残す (re-export shim)

MoonBit に型の re-export 機構が無く、関数 wrapper だけでは型 (Outcome / Cand 等) の
package 帰属が変わって shim にならない。DR-110 §9 の「v1 前の窓で境界を確定する」
趣旨からも、旧 path の延命より lockstep rename (§7) が正。

### `fingerprint : String` (PoC 最小形) を本実装契約にする

lowering 断面 (LOWERING §C.5) と wire decode 対称 (DR-110 §3-4) が別途直列形を要求
するため、fingerprint と encode の 2 契約が重複する。encode 一本に集約し、identity は
kind + encode で構成する (PoC 示唆 4 が本実装への拡張として予告した方向)。

## 射程外

- メモ化 (completes-cache) の実装 — MDR-002 の未実装 TODO のまま。本 MDR は Eq の
  足場を壊さないことだけ保証する
- subset assembly の具体形・RPC クロージャ注入 (DR-110 §7 / 射程外に従う)
- engine 単体の契約検証の fixture 化 (DR-110 §8 の将来課題。engine の合成住人
  wbtest はその代替ではなく各実装の unit の関心)
- kuu-cli 側の実装変更そのもの (§7 は kuu.mbt 側から見た破壊面の列挙。実施は
  kuu-cli リポの作業)

## 関連

- kawaz/kuu DR-110 (3 層の規範、境界裁定表 — 本 MDR はその実装設計)
- `docs/findings/2026-07-16-moonbit-open-dispatch-poc.md` (実現手段の実機検証)
- `docs/findings/2026-07-16-engine-builtin-boundary-survey.md` (争点 21 件、PKG-#N の正本)
- [MDR-001](MDR-001-bootstrap-policy.md) §4 (分割判断の留保 — 本 MDR で確定)
- [MDR-002](MDR-002-evaluator-core-design.md) §3 (モジュール依存順 — package 依存へ昇格)
- [MDR-005](MDR-005-front-door-api.md) (front_door の顔 — 維持。§4 は supersede)
- kawaz/kuu DR-104 §2 (`Cand.ty` の綴り規範 — §3.3 の String 化の根拠)
