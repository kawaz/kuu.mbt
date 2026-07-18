# kuu API コールドレビュー (mbti 3 本のみ・ゼロ知識評価)

> 実施形態: プロジェクト文脈を持たない fresh の最上位 tier reviewer に pkg.generated.mbti 3 本 (engine 685 / builtins 208 / kuu 102 行) **のみ**を渡したゼロ知識・忖度なし評価 (kawaz 依頼 2026-07-18「ゼロ知識の忖度なし第三者目線で kuu コアの API は凄く良いな! となる形になっているか」)。実装 .mbt / docs / DR の参照は禁止した。指摘には DR 裁定済みの意図的設計 (例: engine pub 面は DR-110 の subset assembly 前提) と真の改善点が混在しうる — 採否の仕分けは統括/kawaz が行う。


評価材料: `src/engine/pkg.generated.mbti` / `src/builtins/pkg.generated.mbti` / `src/kuu/pkg.generated.mbti` の 3 ファイルのみ。実装・docs・設計文書は一切見ていない。前提知識は「CLI 引数パースのライブラリ、engine (機構) / builtins (標準搭載) / kuu (玄関) の 3 層らしい」のみ。

行番号は各 mbti ファイルの Read 表示行を指す。

---

## 総合判定: 普通 (5 段階中 3) — ただし層で大きく割れる

- **kuu (玄関) 層単体なら「良い」**。玄関は小さく、コールフローが型から読める
- **engine 層の公開面は「懸念あり」**。内部ユーティリティ・IR・エラーコンストラクタが大量に public で、API としての輪郭が溶けている
- **アーキテクチャの骨格は明確に筋が良い** (純粋関数コア、provenance、曖昧性の第一級扱い、補完の第一級扱い)。問題は骨格でなく**公開面の衛生**

初見ユーザに勧められるか: **kuu パッケージだけ使う前提なら条件付きで勧められる**。拡張を書く人には現状の mbti だけでは無理 (ドキュメント必須)。

---

## 1. 第一印象

engine の mbti を上から読んだ最初の 2 分は正直「うっ」だった。`action_marker` / `argmin_action` / `cat` / `chars_to_str` / `classify_merge_piece` … と、**ドメイン API と内部ヘルパが同じ棚にアルファベット順で混ざって並ぶ**。`argmin_action(Array[(String, Int)]) -> String` (engine:12) や `chars_to_str(Array[Char], Int, Int) -> String` (engine:20)、`to_chars` (engine:114)、`split_on` (engine:112)、`is_integer(Double)` (engine:64) は CLI パーサの公開 API ではなく汎用文字列/数値ユーティリティで、これが公開面に居る時点で「公開面 = 実装の裏口」という印象を与える。

一方 kuu の mbti に移ると空気が変わる。`parse_definition(Json) -> Result[AtomicAST, DefLoadError]` (kuu:26) → `parse(AtomicAST, Array[String], env?, config?, tty?) -> Outcome` (kuu:24) → `result(AtomicAST, Array[Binding]) -> RVal` (kuu:30) と、**典型ユースケースの背骨が 3 関数で見える**。ここは設計者が玄関を意識して絞った形跡がはっきりある。

つまり第一印象は「玄関は綺麗な家だが、機械室の扉が全部開けっ放し」。

## 2. 玄関の明快さ — 概ね良い、ただし parse/resolve の契約が型から読めない

**良い点**:

- 定義ロード → パース → 結果取得の流れが型シグネチャの連鎖 (`AtomicAST` → `Outcome` → `RVal`) で追える。初見でもコールフローを推測できる
- `parse` が `env? : Map[String, String]`、`config? : (String) -> ConfigVal?`、`tty? : Map[String, TtyObs]` を**引数で注入させる** (kuu:24)。グローバル I/O を隠し持たない純粋コアで、テスト容易性・決定性・wasm 等への移植性が型から保証されている。これは CLI パーサとして卓越した設計判断で、この 1 行だけで設計者の力量が分かる
- `Outcome::Ambiguous(AmbiguousData)` (engine:472) — 曖昧解釈を潰さず `interpretations` と `claimants` (engine:137-140) 付きで第一級の結果として返す。ほとんどのパーサが握り潰すか勝手に選ぶところを表に出しており、誠実
- `FailureData` (engine:389) が `tried_triggers` / `help_entry` / `fired_action` を持つ — 「何を試してダメだったか」までエラー UX の材料が揃う
- `sources(AtomicAST, Array[Binding]) -> Array[SourceEntry]` (kuu:32) + `Source` enum (Cli/Env/Config/Inherit/Tty/Default、engine:584) — **値の出所 (provenance) を照会できる**。`--verbose` が CLI 由来か env 由来かを答えられる CLI ライブラリは希少で、明確な強み

**懸念点**:

- **`parse` と `resolve` の分担が型から読めない** (kuu:24, 28)。両方 `Outcome` を返し、両方 `env?/config?/tty?` を取る。`resolve` は追加で `Outcome` と `Array[String]` を取る — 2 段階パースらしいと推測はできるが、「なぜ parse も env を取るのか」「resolve に再度渡す `Array[String]` は何か」が分からない。玄関の最重要 2 関数の契約が曖昧なのは痛い
- **結果取得の径路が 3 つある**: `result` (kuu:30) / `output` (kuu:22) / `build_result` (kuu:14)。`output` は `resolved?` に別の `Array[Binding]` を取り、ユーザが生 bindings と resolved bindings を別々に持ち回る前提に見える。`build_result` に至っては `AccumCell` / `DefaultCell` / 謎の `Array[String]` / `nones?` を要求し、明らかに内部組み立ての露出。どれが正道か初見では選べない
- `accum_cells` / `apply_export_keys` / `export_map` (kuu:10, 12, 20) — ユーザに手動オーケストレーションをさせるための部品に見える。`result` が全部やってくれるなら不要なはずで、公開されている事実が「やってくれないのでは」という不安を生む
- **help 生成が公開面のどこにもない**。`find_help_entry` (engine:58) や `help_entry` フィールドから help の概念があることは分かるが、usage テキスト生成 API が見当たらない。CLI パーサとして意図的スコープ外なのか未実装なのか、mbti からは判別できず、初見ユーザが最初に探すものが無い

## 3. 層の分離 — 責務は読み取れるが、境界は漏れている

責務の読み取り自体は成功している: engine = パース機構 + IR + 拡張トレイト、builtins = 標準の型/installer/accumulator 群 (`install(Registry)` (builtins:80) で一括登録)、kuu = JSON 定義からの組み立てと実行の玄関。3 層の意図は mbti だけで伝わる。

しかし**上位層だけで完結しない**:

- kuu の全シグネチャが `@engine.Outcome` / `@engine.Binding` / `@engine.Cand` / `@engine.RVal` / `@engine.ConfigVal` を露出する。`Outcome::Success(Array[Binding])` を自分でパターンマッチして `result()` に渡す構図なので、**エンドユーザも engine の型を最低 5 つは理解する必要がある**。せめて Outcome と RVal を kuu 層で再エクスポート or ラップしていれば「kuu だけ import すれば済む」体験になった
- `AtomicAST` (kuu:51) が `root : @engine.Scope`、`templates`、`extensions`、`ekmap` を**公開フィールドのまま**晒す。玄関の中核ハンドルが内部表現をそのまま見せており、これらのフィールドは全部破壊的変更の対象になる。opaque にすべき典型例
- engine の `Node` enum (engine:435) は 18 バリアントの**パース IR 全体が `pub` かつパターンマッチ可能**。`DdSat` / `CmdSat` / `Rooted` / `BoundedTail` / `IdxRepeat` のような明らかに内部表現のバリアントを含む。IR の変更 = 破壊的変更となり、進化の自由度を自分で縛っている
- 逆方向の漏れもある: kuu に `type ExportCollision` / `ScopeConfig` / `TypeShadow` (kuu:69, 84, 97) という**メソッドもコンストラクタも無い裸の opaque type** が浮いている。使い道のない公開名で、公開面のノイズ

なお MoonBit のパッケージ間可視性の制約 (builtins が engine の内部を使うには pub にせざるを得ない) が engine の公開過剰の一因である可能性は認識している。だとしても `internal` 系サブパッケージへの隔離や命名規約 (例: `_` プレフィクス相当の明示) で「ここは触るな」を表現する余地はあり、現状はユーザから区別がつかない。

## 4. 命名の一貫性 — 最も弱い軸

- **同義語の揺れが同一コードベース内で衝突している**: engine は `action_marker` / `depr_marker` (engine:10, 44)、builtins は `deprecation_mark` / `effect_mark` / `failure_mark` (builtins:46, 48, 62)。「marker」と「mark」、「depr」と「deprecation」が層をまたいで不統一。同じ概念系の関数群なのに検索性が割れる
- **暗号的略語**: `mkb` (engine:68 — make binding?)、`mk_eff` (engine:66)、`pe_*` 族 (engine:82-94 — parse error?)、`pend_value` (engine:96)、`cand_trigger` (engine:16)。`mkb(String, Value, Source, at_pos?)` は名前から機能を推測する手掛かりがゼロ
- **enum プレフィクスの規約がバラバラ**: `At*` (AttachMode)、`Es*` (EqSepMode)、`K*` (ErrKind)、`D*` (DefErrKind)、`Pk*` (PieceMark — Piece なのになぜ Pk?)、`R*` (RoundMode と RVal で衝突)、`V*` (Value)、`C*` (ConfigVal)、`Ek*` (ExportKey)、`OD*` (OwnedDecl)。コンストラクタ名衝突回避のための prefix だと推測はできるが、規則が型ごとに場当たり的
- **`InstallBuild` と `InstallBuilder`** (engine:401, 413) — 「er」の有無だけで別物の 2 型。これは初見者が確実に取り違える最悪クラスの命名ペア。`InstallBuild` は成果物らしいので `InstallResult` なり `LoweredScope` なり、役割の違う語を当てるべき
- **説明されない造語**: `AtomicAST` の「Atomic」、`node_resident_name` (builtins:108) の「resident」、`SeatCtx` / `config_seat` / `default_seat_resolver` の「seat」、`DdSat` の「Sat」。ドメイン用語として意図的なのだろうが、mbti 面には定義がなく、初見では暗号
- **公開フィールドの trailing underscore**: `inherit_` (engine:351)、`lazy_` (engine:542)。キーワード回避の内部事情が public フィールド名に漏れている
- パッケージ名 `kawaz/kuu/kuu` の stutter も地味に気になる (`@kuu.parse` になるなら実用上は許容範囲)

## 5. 公開面の広さ — engine が過剰、欠けは help と typed builder

**過剰側** (「これ公開する必要ある?」):

- 前述の汎用ユーティリティ群 (`cat` / `to_chars` / `chars_to_str` / `split_on` / `contains_eq` / `is_integer` / `value_str`、builtins の `split_colon`)
- `pe_*` エラーコンストラクタ 7 本 (engine:82-94) — エラーを**作る**側の API は拡張実装者専用のはずで、一般ユーザの面に並べるものではない
- `collect_actions(Array[Binding], Array[(String, Int)]) -> Unit` (engine:24) — out-param 破壊的更新の内部関数がそのまま public
- `warnings_of` と `warnings_structured` (engine:122-124) の並立。しかも `Warning` は `{element : String, kind : String}` (engine:610) で、**「structured」を名乗りながら中身は stringly**。看板倒れ
- `config_from_json` が engine (engine:36) と kuu (kuu:18) に重複して存在
- `parse_bool` / `parse_bool_ext`、`parse_number` / `parse_number_ext`、`parse_int_value` / `parse_int_value_ext` (builtins:120-134) — `_ext` 二重化。同じ builtins 内の `bool_type(config?, value_slot?)` (builtins:24) がラベル付き optional 引数を使えているのだから、`_ext` 側も optional 引数で 1 本化できたはず。スタイルが同一パッケージ内で分裂している

**欠け側** (「これが無いと使えないのでは」):

- **型付き定義ビルダが無い**。定義の入口は `parse_definition(Json)` (kuu:26) のみ。JSON 駆動 (定義 = データ) は設計思想として一貫しているし `encode(Self) -> Json` を全 Ext トレイトに要求している点とも整合するが、MoonBit コードから使う際に定義の typo が全部実行時 `DefLoadError` になる。`Definition` struct (engine:254) は存在するのに、それを kuu 層から食わせる公式径路が見えない (builtins の `lower_definition` (builtins:98) まで降りる必要がありそう)
- help / usage テキスト生成 (前述)

## 6. 型設計 — 光と影が極端

**光**:

- `Outcome` / `Branch` (Accept/Held/Pending、engine:170) / `EffectOp` (engine:269) / `Source` — 意味論を語る enum 群。特に `Branch` は「バックトラック + 補完候補保持」というパース戦略が型から読める
- Errors セクションが 3 パッケージとも空 = **例外を使わず全て値で返す**方針が徹底している。`Result` / `Option` の使い所も一貫して適切
- ほぼ全型に `derive(Eq, Debug)` — golden test・スナップショット比較を最初から意識した作り
- `Ctx` (engine:219) と `DefsView` (engine:261) は private フィールド + 最小メソッドで、opaque 化の意識がある場所には確かにある

**影**:

- **`ElemDef` (engine:286-342) は 55 フィールドの god struct**。tty / dd / env / config / repeat / filter 4 種 / prefix 3 種 / 制約 4 種が全部フラットに同居し、`is_tty : Bool` + `tty_stream : String?` + `tty_cygwin : Bool` のような「フラグ + 付随データがバラバラ」構造だらけ。`is_tty=false` で `tty_stream=Some(..)` のような**不正状態が表現可能**。`TtyConfig?` / `DdConfig?` / `RepeatConfig?` のようなサブ構造に畳めば不正状態が型で消えるのに、しかも `pub(all)` なので外部から任意の組合せで構築できてしまう
- **bool の羅列シグネチャ**: `cand_trigger(String, String, String, TermHint, Bool, Bool, Bool)` (engine:16) — String 3 連 + Bool 3 連。`separated_arg(String, String?, &TypeExt, RoundMode, Bool, BoolConfig, Array[FilterSpelling], Bool)` (builtins:142) — 匿名 Bool 2 個。`configured_type(&TypeExt, RoundMode, Bool, BoolConfig)` (builtins:36-38) の Bool は何? 呼び出し側コードが読めなくなる典型。MoonBit にはラベル付き引数があるのだから使うべき
- **stringly-typed の常用**: `Cand.ty : String` / `Cand.origin : String` (engine:179-180)、`ElemDef.accumulator : String?` / `collector : String?`、`Warning.kind : String`、filter エラーの `(String, String)` タプル (builtins:14-18 — 2 つの String が何なのか型からは不明)、`config_to_value` の `(ErrKind, String, String)` 3 連タプル (builtins:34)。名前による registry lookup 設計 (シリアライズ可能性のため) と読めるが、エラー型のタプルは擁護できない — `FilterError { name, reason }` を切るべき
- 型エイリアス `Resume` (engine:618) を定義しておきながら、`continue_matcher` / `MatcherExt::interpret` / `NodeExt::eval` は全部生の関数型 `(Ctx, Int, Array[Binding]) -> Array[Branch]` を書いている。`LowerSeat` (engine:616) も同様に `AccumulatorExt::resolve_cli` で未使用。**エイリアスを作ったのに使わない**のは公開面の自己矛盾
- `Registry::register_*` が `Bool` を返す (engine:532-537) — 失敗理由なしの error-by-bool。しかも `register_installer` だけ `Unit` (engine:534) で不整合

## 7. 拡張点 — 作法は読めるが、要求理解量は重い

7 つの拡張トレイト (TypeExt / MatcherExt / NodeExt / AccumulatorExt / CollectorExt / InstallerExt / EntityExt) は役割分担が名前から推測でき、共通の `kind() -> String` + `encode() -> Json` + `equal() = _` パターンで統一されている。この統一感は良い。`encode` 必須 = 「拡張も定義としてシリアライズ可能であれ」という契約が読み取れ、JSON 駆動設計と一貫している。

- `TypeExt` (engine:675) は最小で良い形。`parse_token(String) -> Result[Value, ParseFail]` だけ実装すれば動きそうと思わせる。`default_seat_*` の「seat」だけが謎
- `MatcherExt::interpret` / `NodeExt::eval` (engine:659, 672) は CPS 継続渡し。`Ctx` が opaque で `token_at` / `is_complete_mode` の 2 メソッドしか無いのは、matcher 実装者に見せる面としてはむしろ絞れていて良い。ただし `Branch` 3 種の使い分け・`Binding.link : Int` / `at_pos : Int?` の意味・`Int` 引数 (トークン位置?) は mbti からは推測の域を出ず、**ドキュメント無しで書ける拡張は TypeExt 止まり**
- `InstallerExt` (engine:647) + `run_installer_fixpoint` (engine:98) + `DefErrKind::DZeroProgress` (engine:242) — 固定点到達まで installer を回す設計が型から読める。宣言語彙 (`vocab`) の所有権検査 (`DVocabIntersection`) まであり、拡張同士の衝突を定義時に検出する意志が見える。高度だが、`InstallBuilder` / `InstallBuild` / `InstallChild` / `DefsView` / `DecodedOwnedDecl` / `OwnedDecl` (13 バリアント) の理解が前提で、**installer を書く人への要求理解量はかなり重い**

## 8. まとめ

**良い点 (上位 3)**:

1. **効果の全注入** — `parse` が env/config/tty を引数で受ける純粋コア (kuu:24)。テスト・再現・移植の全てに効く、このライブラリ最大の美点
2. **結果意味論の誠実さ** — `Outcome::Ambiguous` の第一級化 (engine:472) + `Source` による provenance (kuu:32, engine:584) + `FailureData.tried_triggers`。エラー/曖昧/出所を握り潰さない
3. **玄関の背骨** — kuu 層の parse_definition → parse → result の 3 段が型の連鎖で発見可能。補完 (`complete`) も玄関に並ぶ第一級市民

**懸念点 (上位 5)**:

1. **engine の公開面崩壊** — 汎用ユーティリティ・IR 全体 (`Node` 18 バリアント)・エラーコンストラクタ・out-param 関数まで public。破壊的変更面が巨大で、ユーザは「触ってよい API」を識別できない
2. **`ElemDef` 55 フィールド god struct + `pub(all)`** — 不正状態が表現可能かつ外部構築可能 (engine:286)
3. **命名の不統一** — marker/mark 揺れ、`mkb`/`pe_*` 等の暗号略語、`InstallBuild`/`InstallBuilder` の取り違え必至ペア、場当たり的 enum prefix
4. **parse/resolve/result/output/build_result の径路多重化** — 玄関の正道が 1 本に見えない (kuu:14-30)
5. **bool 羅列・匿名タプルエラー** — `cand_trigger` の Bool×3、filter エラーの `(String, String)`。ラベル付き引数と専用エラー型という言語機能を使い切れていない

**もし自分が設計者なら**: (a) engine を `engine` (公開契約: Outcome/Binding/Value/Source/Ext トレイト群) と `engine/internal` (IR・ヘルパ) に割り、後者への依存を builtins に限定する。(b) kuu 層に `ParseResult` ラッパを導入して Outcome/RVal/sources を 1 つのハンドルにし、engine 型の直接露出を Ext 実装者向けに限定する。(c) `ElemDef` の機能クラスタを Option サブ構造に畳む。(d) リリース前に mbti を「ユーザに読ませる文書」とみなして 1 identifier ずつ「これは契約か実装か」を仕分けする棚卸しを 1 回やる — 骨格は良いので、公開面の衛生だけで評価が 1〜2 段変わる。
