# W2-2: value_type 体系のモデル化 — 設計文書 (実装 worker への指示書)

> 対象段: `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 の W2-2。
> 規範の正本: spec `docs/decisions/DR-126-descriptor-record-value-type.md` §1〜§5、
> `DR-127-link-fixed-path-dsl.md` §2.2、`DR-128-type-input-structure-splice.md` §7/§8。
> 実測ベースライン (2026-08-02、`@` = `32b3e6ab` の作業コピー): `just test` = **612 tests / 612 passed**、
> conformance `decoded=394 ran_cases=885 skipped=0 mismatches=0` (W2-1 の fixture 3 本 + pin bump 合流済み)。
> 出口条件: この 612 / 885 / mismatches=0 が**完全不変**のまま、§6 の wbtest が全部 green。

## 0. この段がやること / やらないこと

やること:

1. DR-126 §1 の `value_type` 体系を MoonBit の enum として導入する (新規 `src/abi/value_type.mbt`)
2. `TypeExt` の placeholder `output_shape : TypeOutputShape` を `output_type : ValueType?` へ置換する
   (既定 `None` = 「名乗らない」 = 現 `Opaque` 相当。`TypeOutputShape` enum は削除)
3. record フィールドの type 参照を **registry 空間のみ**で解決する経路
   (`Registry::resolve_type_reference`) と、bare 名 = builtin ns 糖衣 (DR-094 案A) の正規化を置く
4. 型依存グラフの検査 collector を lowering に追加する — 未登録参照 = `unknown-vocab`、
   循環 = `circular-ref` (定義が実際に使う型から到達可能な範囲のみ)
5. `io_type.input` 側の席 (DR-128 §7): `TypeExt::input_type : ValueType` (既定 `String`) を宣言だけ置く

やらないこと (後続段の領分):

- DR-127 §2.2 遷移表の実装 (record/array/union の値空間降下) — **W2-6**。本段は既存の
  2 値分類 (Primitive / Opaque) と同じ挙動を `ValueType?` の上に保存するだけ
- `Value` への Array/Object 追加 — W2-3
- `parse_token` の複合対応・DR-126 §4 の乖離検査 — W2-5
- DR-128 §7 の包含検査 (産出形 ⊆ `io_type.input`) の実装 — DR-128 実装サイクル (W2-5 と同担当)。
  本段は席 (型と規則の引用) のみ
- wire (`definitions.types` / descriptor JSON) から record 宣言を decode する経路 — record を名乗る
  住人は当面コード側 resident (wbtest 内 or 将来の builtin) だけであり、wire 側の席は record 実例が
  descriptor に現れる段で設ける

## 1. 変更対象ファイル一覧

| ファイル | 変更 |
|---|---|
| `src/abi/value_type.mbt` | **新規**。`ValueType` enum + 宣言 well-formedness 検査 |
| `src/abi/value_type_wbtest.mbt` | **新規**。schema と等価な宣言制約 (field 名無制約 / field key 重複 / type 参照 pattern / union 入れ子・要素数・重複) の直接 wbtest |
| `src/extension/node_traits.mbt` | `TypeOutputShape` 削除、`TypeExt::output_shape` → `output_type`、`input_type` 席追加 |
| `src/extension/type_residents.mbt` | builtin 10 residents の `output_shape` impl を `output_type` へ (§4.2 の表) |
| `src/extension/registry.mbt` | `Registry::resolve_type_reference` 追加 |
| `src/extension/abi_aliases.mbt` | `pub using @abi { ... }` ブロック (L4-51) に `type ValueType,` の alias を追記 — extension パッケージは ABI 型を unqualified で使う慣行 (`TypeParseFail` / `Value` 等と同列) |
| `src/internal/engine/layer_aliases.mbt` | `type TypeOutputShape,` の行を削除 (`ValueType` は `@abi` 直参照で足りるか確認、engine の既存 `@abi` alias 慣行に合わせる) |
| `src/internal/engine/lowering.mbt` | `LinkPathResolution::Residual` の carrier 置換、暫定分類関数、`collect_type_reference_errors` 追加 |
| `src/extension/type_residents_wbtest.mbt` | `:77`/`:80` の `output_shape` 表明を `output_type` へ書き換え |
| `src/kuu/value_type_reference_wbtest.mbt` | **新規**。§6.2 の parse_definition レベル wbtest |
| `src/internal/engine/value_type_classification_wbtest.mbt` | **新規**。§6.3 の暫定分類 table-driven wbtest |
| 各 `pkg.generated.mbti` | `moon info` で再生成 |

kuu-node (`src/kuu-node/installer.mbt`) は `lookup_type` の薄い委譲のみで `output_shape` に触れて
いないので変更不要。`src/kuu/help.mbt` 等の `value_type : String?` (help メタデータの型名文字列、
`src/abi/declaration_types.mbt:21`) は**別物**で無関係 — 触らない。

## 2. `ValueType` enum (新規 `src/abi/value_type.mbt`)

DR-126 §1 の文法:

```
value_type :=
    "string" | "number" | "bool" | "null" | "value"
  | { "array": value_type }
  | { "map": value_type }                                  // キーは常に string
  | { "record": { <field_name>: <type 参照>, ... } }
  | [value_type, value_type, ...]                          // union (2 要素以上)
```

MoonBit 表現:

```moonbit
///|
/// DR-126 §1 / DR-107 §3 の value_type 体系。io_type の出力宣言 (DR-126) と入力宣言
/// (DR-128 §7) が共有する 1 つの体系。record のフィールド値だけが type 参照 (registry
/// 綴りの String) で、他の入れ子は value_type 自身である (DR-126 §1 の「2 つの語彙」)。
pub(all) enum ValueType {
  String
  Number
  Bool
  Null
  Value // "value" — JSON 全域 (DR-107 §3)
  Array(ValueType) // {"array": T}
  Map(ValueType) // {"map": T} — キーは常に string
  Record(Array[(String, String)]) // {"record": {field: <type 参照>}} — 宣言順を保存する
  Union(Array[ValueType]) // [T1, T2, ...] — 2 要素以上、重複なし。要素は value_type 全域 (union の入れ子も構文上合法)
} derive(Eq, Debug)
```

設計判断 (決定済み、根拠つき):

- **配置は `src/abi`**。`DefErrorKind` (`src/abi/node_types.mbt`) と同じ「全層が共有する ABI データ」
  であり、extension (trait 署名) / engine (lowering) / kuu (将来の wire) の全 import 元は abi のみ。
  MDR の層規律 (abi は葉) に適合する
- **constructor `Value` は spec 綴り `"value"` と一致させる**。同一パッケージに `Value` /
  `ConfigVal` の同綴り constructor (`String` / `Number` / `Bool`) が既に同居している
  (`src/abi/value.mbt`) ので、型で解決される MoonBit の constructor 名前空間上の問題はない。
  曖昧になる式位置では `ValueType::Value` と修飾する
- **`Record` は `Map` でなく `Array[(String, String)]`**。宣言順の保存は help / codegen /
  effects 観測の決定性に効く (kuu.mbt の `ConfigVal::Object` / `ResultValue::Object` が
  `Array[(String, ...)]` を選んでいる既存慣行と同じ)。フィールドの重複キーは §2.1 の
  well-formedness で弾く
- **union の入れ子は構文上合法**。spec `schema/descriptor.schema.json` `$defs.value_type` の
  union 枝は `items: {"$ref": value_type}` で union 自身を含む — `Union(Union(...))` は
  合法な宣言であり弾かない。§2.1 が union に課すのは要素数 2 以上 (`minItems: 2`) と
  重複 member なし (`uniqueItems: true`) のみ

### 2.1 宣言の well-formedness 検査 (abi 内の純関数)

descriptor JSON なら spec の `schema/descriptor.schema.json` が構文を強制するが、コード側
resident の宣言は schema を通らない。等価なゲートを 1 つ置く:

```moonbit
///|
/// 宣言としての構文健全性。schema/descriptor.schema.json $defs.value_type が wire 側で
/// 強制する制約のコード側等価物:
///   - union は 2 要素以上 (minItems: 2) かつ重複 member なし (uniqueItems: true の等価、
///     構造 Eq での重複検査)
///   - record のフィールド名は重複なし (下記 rationale)
///   - type 参照の綴りは schema pattern ^([a-z][a-z0-9_]*/)?[a-z][a-z0-9_]*$ に一致する
///     (lexical 検査。非空だけでは不足 — 大文字 / 記号 / 先頭数字 / 多段 ns を弾く)
/// 違反箇所を人間可読の径路つきで列挙する。
pub fn ValueType::declaration_violations(self : ValueType) -> Array[String]
```

再帰で全部の入れ子を検査し、`"union has 1 member (needs 2+) at .array"` のような文字列を返す。
lowering の collector (§5) が非空なら `InvalidRange` の DefError に畳む (単一値の内部不正でなく
「宣言の組合せが値域外」なので `InvalidRange`、`repeat min > max` と同じ整理 — DR-082 系)。

Design rationale (schema との対応関係):

- **フィールド名そのものの検査 (非空等) は置かない** — schema の record 枝に propertyNames
  制約は無く、コード側だけの発明になるため。schema に無い制約を足さない
- **重複フィールドキーの検査は置く** — wire の JSON object では重複キーがそもそも表現
  不能なので schema に規定は現れないが、`Array[(String, String)]` 表現では構築できて
  しまう。「wire で表現不能な宣言はコード側でも不正」というコード側等価として正当

## 3. type 参照の解決 — `Registry::resolve_type_reference`

`src/extension/registry.mbt` に追加:

```moonbit
///|
/// record フィールド等の type 参照 (DR-126 §1) を解決する。解決空間は registry のみ —
/// 使用側 definition の definitions.types (TypeShadow) には shadow されない (DR-126 §1、
/// SPL-Q3=a)。bare 名は builtin ns の糖衣 (DR-094 §3 案A): "builtin/<bare>" は "<bare>" へ
/// 正規化してから引く (builtin residents は bare 名で登録されているため)。
pub fn Registry::resolve_type_reference(
  self : Registry,
  spelling : String,
) -> &TypeExt? {
  let canonical = if spelling.has_prefix("builtin/") {
    spelling.substring(start=8)
  } else {
    spelling
  }
  self.types.get(canonical)
}
```

- 「registry 空間のみ」は構造的にも保証される: TypeShadow の map は `src/kuu/wire_decode.mbt`
  の decode ローカルで、engine には `ElementDef.ty` (解決済み resident) しか渡らない。この関数が
  shadow を見る経路は存在しない。wbtest がこの性質を pin する (§6 ケース d2)
- 既存の `dec_ty` (`src/kuu/wire_decode.mbt:1072`) / wire の `type:` 属性解決は**触らない**
  (あちらは DR-035 の使用側解決文脈で、本 DR の関心外)
- `has_prefix` 相当の API 名は MoonBit core の現行綴りに合わせること (実装時に確認)

## 4. `TypeExt` の置換 — `output_shape` → `output_type`

### 4.1 trait の変更 (`src/extension/node_traits.mbt`)

```moonbit
// 削除: pub(all) enum TypeOutputShape { Primitive; Opaque }

pub(open) trait TypeExt {
  fn name(Self) -> String
  fn encode(Self) -> Json = _
  fn has_value_slot(Self) -> Bool
  fn output_type(Self) -> ValueType? = _ // 旧 output_shape の置換
  fn input_type(Self) -> ValueType = _ // DR-128 §7 の席 (§4.3)
  fn parse_token(Self, String) -> Result[Value, TypeParseFail]
  fn completion_values(Self) -> Array[String] = _
  fn default_seat_observation_key(Self) -> String? = _
  fn default_seat_resolver(Self, SeatCtx) -> Value?
}

///|
/// 既定は「名乗らない」— 値の内部構造について何も約束しない。link path の値空間降下
/// (DR-127 §2.2) は名乗らない type の内側へ降りられない (旧 TypeOutputShape::Opaque と
/// 同じ既定位置)。構造を名乗る resident だけが Some を返す。
impl TypeExt with fn output_type(_self) {
  None
}
```

`TypeOutputShape` は第 1 波が置いた placeholder (plan §1.6) であり、v1 前の完備主義に従い
互換レイヤなしで置換する。`output_shape` を override していた実装は本リポの builtin 10 residents
と wbtest のみ (`grep -rn output_shape src/` で全件確認済み、外部消費者なし)。

`ValueType?` の `None` と `Some(Null)` は別物である — `None` = 構造について沈黙 (不透明)、
`Some(Null)` = 「値は常に null」という名乗り。この区別が旧 2 値 enum に対する本質的な追加。

### 4.2 builtin residents の宣言 (`src/extension/type_residents.mbt`)

10 residents の `output_shape` impl を `output_type` へ差し替える。値は spec
`schema/builtin-descriptors.json` の `io_type.output` に一致させる (descriptor 化されていない
resident は DR-107 §3 の値集合から自明に決まる):

| resident | 旧 output_shape | 新 output_type | 出所 |
|---|---|---|---|
| `string` | Primitive | `Some(String)` | 自明 (parse_token が `String` を返す) |
| `number` | Primitive | `Some(Number)` | builtin-descriptors `number_parser.output = "number"` |
| `int` | Primitive | `Some(Number)` | builtin-descriptors `int_parser.output = "number"` (DR-075: int は number の値空間判定) |
| `float` | Primitive | `Some(Number)` | number 系 |
| `bool` | Primitive | `Some(Bool)` | builtin-descriptors `bool_parser.output = "bool"` |
| `flag` | Primitive | `Some(Bool)` | 自明 |
| `count` | Primitive | `Some(Number)` | 自明 (増分カウント) |
| `tty` | Primitive | `Some(Bool)` | builtin-descriptors `tty.output = "bool"` (DR-129 §4 で単一 bool 確定) |
| `completion_script` | Primitive | `Some(String)` | 自明 |
| `none` | Primitive | `Some(Null)` | §7 裁定候補 A (暫定推し。値スロットを持たない mark の「値」は null しかない) |

全行が primitive の名乗りなので、§4.4 の暫定分類の下で**全 residents の挙動は現行と同一**になる。

### 4.3 `input_type` の席 (DR-128 §7)

```moonbit
///|
/// io_type.input の宣言 (DR-128 §7 — string 固定の撤廃)。既定は string: 定義片
/// (input_structure) を持たない type は 1 トークン string 消費へ縮退する (DR-128 §2)。
/// 本段では宣言の席のみ — 消費者 (産出形 ⊆ input の包含検査、DR-128 §7) は DR-128 実装
/// サイクル (W2-5 と同担当) が置く。包含規則は DR-128 §7 が正本: union は成分ごとに包含を
/// 要求 / record は {"map":"value"} に包含される / "value" は全域を包含する。
impl TypeExt with fn input_type(_self) {
  ValueType::String
}
```

engine 側の消費者は本段では**作らない** (呼ぶだけのコードも置かない)。wbtest で既定値だけ pin する。
包含検査 `fn value_type_contains(outer : ValueType, inner : ValueType) -> Bool` の全域規則は
DR-128 §7 が 3 規則しか確定させていない (それ以外のペアの規則は未裁定) ため、本段で署名も
確定させない — 実装段が DR-128 §7 を読んで設計する。

### 4.4 lowering の置換点 (`src/internal/engine/lowering.mbt`)

行番号は 2026-08-02 時点の実測。ズレたら `grep -n "Residual" src/internal/engine/lowering.mbt`。

```moonbit
// :2186
priv enum LinkPathResolution {
  Resolved(...)            // 変更なし (6 フィールド)
  Residual(ValueType?)     // 旧 Residual(TypeOutputShape)。葉セル type の名乗りをそのまま運ぶ
  Missing
}

// :2358 / :2382 (resolve_link_path 内、2 箇所)
Cell | Enum(_) => return Residual(current.ty.output_type())
```

消費側は暫定分類関数 1 本に集約する:

```moonbit
///|
/// W2-2 の暫定分類 — DR-127 §2.2 の遷移表を W2-6 が実装するまで、旧 2 値分類
/// (Primitive / Opaque) と同じ挙動を ValueType? の上に保存する。
/// primitive 行 (残余 segment は恒真不成立 = absent-ref) に落ちるのは、名乗りの全域が
/// primitive で尽きる場合のみ。union は全 variant が primitive なら primitive 扱い
/// (どの variant にもフィールドが無い = 残余は必ず不成立、遷移表 union 行の含有 variant
/// 0 と同じ帰結)。構造を含む名乗り (array/map/record/value) は W2-6 までは降下未実装なので
/// 不透明側 (Unsupported) に倒す。
fn residual_is_primitive_only(declared : ValueType?) -> Bool {
  match declared {
    None => false
    Some(vt) => value_type_primitive_only(vt)
  }
}

fn value_type_primitive_only(vt : ValueType) -> Bool {
  match vt {
    String | Number | Bool | Null => true
    Union(members) => members.iter().all(value_type_primitive_only)
    Array(_) | Map(_) | Record(_) | Value => false
  }
}
```

置換対象の 4 箇所:

| 位置 | 旧 | 新 |
|---|---|---|
| `:4065` (`collect_link_path_errors` 内) | `Residual(Opaque) =>` Unsupported を push | `Residual(declared) => if not(residual_is_primitive_only(declared)) {` 同じ Unsupported を push `}` |
| `:4074` | `Resolved(..) \| Residual(Primitive) \| Missing => ()` | `Resolved(..) \| Missing => ()` (Residual は上の arm が全部受ける) |
| `:4162` (`check_element_absent_link` 内) | `Missing \| Residual(Primitive) => true` | `Missing => true` / `Residual(declared) => residual_is_primitive_only(declared)` |
| `:4163` | `Resolved(..) \| Residual(Opaque) => false` | `Resolved(..) => false` |

**適用順序の保証 — 暫定分類は well-formedness 検査 (§2.1) を通った宣言にのみ適用される。**
malformed な宣言 (例: `Union([])`) は §5 の collector が `InvalidRange` で必ず落とすことが
確定しているため、Residual の消費側 (`:4065` / `:4162`) は宣言が malformed
(`declaration_violations` 非空) の場合は分類関数を呼ばず、link 由来のエラー (Unsupported /
absent-ref) も重畳しない — **malformed union のエラー重畳方針は `InvalidRange` のみ**。
これにより `Union([])` で `all([]) == true` が primitive 側に落ちる穴は到達しない
(到達不能根拠: 分類関数が呼ばれる前提条件が well-formed であること自体を消費側のガードで
保証する。両 collector は同じ全件列挙の窓に居るので実行順には依存しない)。

`:2456` / `:2489` の `Residual(_)` ワイルドカード 2 箇所は無変更で通る。エラーメッセージ
(`"this link path reaches an opaque value structure"` 等) も**一字も変えない** — conformance
`link-parse/absent-target.json` 等が pin している。

挙動保存の証明: 旧 `output_shape` は builtin 全部が `Primitive`、trait 既定が `Opaque` だった。
新体系では builtin 全部が primitive の名乗り (§4.2) → `residual_is_primitive_only = true` =
旧 Primitive 経路、名乗らない (None) → `false` = 旧 Opaque 経路。record 等の構造を名乗る住人は
まだ居ない (これが「既存 885 cases 不変」の根拠) ので、第 3 の経路 (構造名乗り → 暫定 Unsupported)
は wbtest でしか観測されない。

## 5. 型依存グラフの検査 — `collect_type_reference_errors`

### 5.1 位置と呼び出しタイミング

**lowering 時** (decode 時ではない)。理由:

1. record 宣言はコード側 resident に載っており、wire decode には見るものが無い
2. definition-error は `lower_definition_snapshot_impl` (`src/internal/engine/lowering.mbt:5950`)
   が全件列挙する既存の窓 (first-error 打ち切りなし) であり、`unknown-vocab` / `circular-ref` は
   その語彙 (`DefErrorKind::UnknownVocab` / `CircularRef`、`src/abi/node_types.mbt:6`)
3. DR-126 §1 の規範は「解決できない descriptor で当該型は**使えない**」 — 使用サイトのエラーで
   あって registry 全体の健全性検査ではない。定義が使っていない型の壊れた宣言はこの定義の
   エラーにしない (registry 全走査にすると、無関係の resident の不備で全定義が落ちる)

呼び出し位置は `lower_definition_snapshot_impl` 内、`collect_link_path_errors(def, errs)`
(`:5985`) の直後:

```moonbit
collect_link_path_errors(def, errs)
collect_unsupported_link_shape(def, errs)
collect_type_reference_errors(def, extensions, errs) // 追加
```

`extensions : Registry` は同関数の引数として既に手元にある。

### 5.2 アルゴリズム — 純粋 walker と seed collector の 2 層

構成は 2 層に分離する:

**層 1 — 純粋な型グラフ walker** (Definition を知らない):

```moonbit
///|
/// DR-126 §1: value_type 宣言 (root) から type 参照 edge を辿り、未登録参照 = unknown-vocab、
/// 循環 = circular-ref、malformed 宣言 = invalid-range を列挙する純粋 walker。
/// root が ValueType である点が肝 — 呼び手は「どの宣言面 (output_type / 将来の input_type
/// の Record 参照) から検査を始めるか」だけを決め、graph の辿り方はここに一本化する。
fn validate_value_type_references(
  root : ValueType,
  root_type : String, // root seed resident の registry 名。hop 先では解決した resident.name() へ更新
  extensions : Registry,
  element : String, // 診断の表示上の帰属先 (seed の要素名)
  diagnostic_identity : String, // 同名 leaf を区別する collector 内部 seed identity
  out : Array[DefError],
  diagnostic_keys : Map[String, Bool],
) -> Unit
```

edge の辿り方:

- `Record(fields)` → 各 field の参照綴りが edge。**参照先の中へは、参照先 type の
  `output_type()` を通して降りる** (DR-126 §1 の再帰導出と同じ経路)
- `Array(t)` / `Map(t)` → `t` を再帰 (record が入れ子で現れうる: `{"array": {"record": ...}}`)
- `Union(members)` → 各 member を再帰
- primitive / `Value` → edge なし

**層 2 — Definition seed collector** (walker の呼び手):

```moonbit
fn collect_type_reference_errors(
  def : Definition,
  extensions : Registry,
  template_declarations : Map[String, ElementDef],
  out : Array[DefError],
) -> Unit
```

`def.options` / `def.positionals` から `ElementBody` を再帰し、実際に型を持つ
`Cell` / `Enum` leaf の `ElementDef.ty` だけを seed (要素名 + resident の `output_type()`)
として集める。`Group` / `Or` wrapper 自身の `ty` は未使用なので seed にしない。
`def.commands` は `command.body` へ再帰する。

`ref_target` を持つ要素は `template_declarations` から参照先を辿り、**使用サイトから到達する
定義だけ**を同じ leaf 規則で seed 化する。template 内の診断は使用側要素へ帰属させる。
未使用 template は走査しないため、壊れた未使用宣言が無関係の definition を落とさない。
template の再帰展開は path-local stack で同一 template の再訪を止める。wire の
`definitions.templates` は `or` / `seq` / bare leaf の 3 形で、template leaf の `ref` は
`dec_or_leaf` の allowlist 外 (`src/kuu/wire_decode.mbt:1571-1580`, `:1888-1892`) だが、
コード側 `template_declarations` に対する防御として stack guard を持つ。

各 leaf seed には collector 内で一意な `diagnostic_identity` を付ける。診断表示の
`DefError.element` は leaf 名 (匿名 leaf は直近の named wrapper、template 内は使用側要素) を
保ちつつ、同名 leaf が異なる木位置に複数あっても dedup で潰れない。seed ごとに層 1 の
walker を呼ぶ。

この分離の理由: 将来 `input_type` の Record 参照検査 (DR-128 サイクル) も**同じ層 1 walker を
別 seed で受ける** — walker が Definition でなく ValueType を root に取ることで、宣言面の追加が
seed 追加だけで済む。なお DR-128 §8 の `input_structure` DAG は **seed も edge も別の別グラフ**
(定義片の splice 依存であって型宣言依存ではない) であり、層 1 walker の拡張ではなく DR-128
実装サイクルが別途置く。

診断規則:

1. **未登録参照**: `extensions.resolve_type_reference(spelling)` が `None` →
   `DefError { element: <seed の要素名>, kind: UnknownVocab, message: "type '<型名>' field
   '<フィールド名>' references unregistered type '<綴り>'", hint: "register the type or fix
   the reference spelling" }`。message 文言は最終的に実装者が整えてよいが、**型名・フィールド名・
   参照綴りの 3 つを必ず含める** (参照は seed から複数 hop 先にありうるため、要素名だけでは
   位置が特定できない)。型名は root では `root_type`、多段 hop 先では直前に解決した
   `resident.name()` を current owner として更新する
2. **循環**: DFS の on-stack 集合 (正規化済み綴りで持つ) に既在の型へ edge が向いたら
   `CircularRef`。message には循環路を含める (例: `"type dependency cycle: timerange ->
   timestamp -> timerange"`)。自己参照 (`Node.next -> Node`) も同規則で落ちる (DR-126 §1)
3. **走査状態と重複抑制**: on-stack / visited 集合は **seed ごと**に独立に持つ (定義単位で
   共有しない — 共有すると element 帰属が最初の seed に固定され、複数要素が同じ壊れた型を
   使う場合の帰属が欠落する)。診断の dedup は `(diagnostic_identity, element, kind, 対象綴り)`
   の組で行い、同一 seed 内の同じ対象だけを 1 回にする。表示上同じ `element` を持つ leaf が
   異なる木位置にあっても `diagnostic_identity` が違うため、各使用箇所の診断を保持する。
   型グラフは小さい (builtin 10 + テスト数個規模) ので seed ごとの再走査に性能問題はない
4. **well-formedness**: DFS 中に各型の宣言へ §2.1 の `declaration_violations` を 1 回適用し
   (dedup は 3 と同じ組で効く)、非空なら `InvalidRange` で報告する

## 6. wbtest 計画

### 6.1 `src/extension/type_residents_wbtest.mbt` (既存改修)

`:77`/`:80` の `assert_eq(resident.output_shape(), Primitive)` / `Opaque` を置換:

- builtin 各 resident の `output_type()` が §4.2 の表どおり (`string_type().output_type() ==
  Some(String)` 等、10 件)
- override しない外部 resident (テスト内 struct) の `output_type() == None`
- `input_type()` の既定が `ValueType::String` (builtin 1 件 + override なし外部 1 件)
- `input_type()` を **override する** test resident 1 件 (`Record(...)` か `Union(...)` を返す) —
  trait の新席が既定値でなく override 側へ正しく dispatch することを pin (既定値の表明だけでは
  「席が dispatch されない実装」を検出できない)

### 6.2 `src/kuu/value_type_reference_wbtest.mbt` (新規)

registry 構築は `src/kuu/lower_conformance_wbtest.mbt:660` 付近の builtin 登録パターンを写し、
そこへテスト用 resident を追加登録する。テスト用 resident の基本 4 種 (境界ケース h〜p 用の
追加 resident は各ケース行に記す):

```moonbit
// output_type だけが本題。parse_token は Ok(@abi.String(token)) 等の stub でよい
priv struct TimestampType {}   // name "timestamp", output_type Some(Number)
priv struct TimerangeType {}   // name "timerange",
                               //   output_type Some(Record([("since","timestamp"),("until","timestamp")]))
priv struct BrokenRefType {}   // name "brokenref", output_type Some(Record([("x","nosuch")]))
priv struct SelfRefType {}     // name "selfnode", output_type Some(Record([("next","selfnode")]))
```

定義は `parse_definition(definition, extensions=...)` で流し、`Err(Rejected(errors))` の
kind / message を表明する。ケース:

| # | 内容 | 期待 |
|---|---|---|
| a | `{"options":[{"name":"tr","type":"timerange","long":true}]}` (timestamp 登録済み) | `Ok(_)` — 参照解決成功、def error なし |
| b | 同上だが timestamp を**登録しない** | `Rejected` に `UnknownVocab` 1 件、message に `timerange` / `since` / `timestamp` を含む |
| c1 | selfnode を使う定義 | `Rejected` に `CircularRef`、message に循環路 |
| c2 | 2 型相互参照 (`a.f -> b`, `b.g -> a`) を使う定義 | 同上 (2-cycle) |
| d1 | フィールド参照が `"builtin/number"` の record 型を使う定義 | `Ok(_)` (糖衣正規化で builtin `number` に解決) |
| d2 | フィールド参照 `"shadowed"` は registry に無いが、定義の `definitions.types` に `"shadowed"` (int_parser factory) がある | **`Rejected` `UnknownVocab`** — registry 空間のみ、shadow に隠れない (DR-126 §1 / SPL-Q3=a) |
| e1 | 名乗らない type (`output_type = None`) の葉セルへ `link: "cell.field"` の残余 | `Rejected` `Unsupported`、message は現行の `"this link path reaches an opaque value structure"` と同一 |
| e2 | `string` 型の葉セルへ残余つき link | `Rejected` `AbsentRef` (現行どおり) |
| e3 | record を名乗る type (timerange) の葉セルへ `link: "tr.since"` の残余 | **暫定** `Rejected` `Unsupported` — W2-6 が遷移表で置換する予定地。テストコメントに `W2-6 で record 降下 (静的成功) へ置換される暫定 pin` と明記 |
| f | union 全 primitive (`Union([Bool, Null])`) を名乗る type へ残余つき link | `Rejected` `AbsentRef` (§4.4 の primitive-only 分類) |
| g | `Union([Bool])` (1 要素 union) を名乗る type を使う定義 | `Rejected` `InvalidRange` (§2.1 well-formedness) |
| h | brokenref を registry に**登録するが定義は使わない** (options は `string` のみ) | `Ok(_)` — 「使用型から到達可能な範囲のみ」の核心 pin。未使用の壊れた resident が無関係の定義を落とさない |
| i1 | `output_type Some(Array(Record([("x","nosuch")])))` の type を使う定義 | `Rejected` `UnknownVocab` — array の内側の record 参照も辿る |
| i2 | `output_type Some(Map(Record([("x","nosuch")])))` | 同上 (map の内側) |
| i3 | `output_type Some(Union([Bool, Record([("x","nosuch")])]))` | 同上 (union member の内側) |
| j | 2 hop 先の未登録: `hop_a` (Record → `hop_b`) を使い、`hop_b` (Record → `nosuch`) は登録済み | `Rejected` `UnknownVocab`、message の型名は `hop_b` (seed 直下でなく複数 hop 先で位置特定できること) |
| k | array を介した cycle: `cyc_a` (Record → `cyc_b`)、`cyc_b` (`Array(Record([("g","cyc_a")]))`) | `Rejected` `CircularRef` — edge が record 直下でなく array/union 経由でも循環を検出 |
| l | extension ns の参照: `myapp/foo` を registry に登録し、record field が `"myapp/foo"` を参照 | `Ok(_)` — ns 付き綴りが変形されず exact lookup される (糖衣正規化は `builtin/` prefix のみ、m2 と同件) |
| m | 空 record (`Record([])`) を名乗る type を使う定義 | `Ok(_)` — schema 上「常に `{}`」の定まった型で合法 (DR-126 §1) |
| n | 重複 member の union (`Union([Bool, Bool])`) を名乗る type を使う定義 | `Rejected` `InvalidRange` (§2.1、uniqueItems の等価) |
| o | pattern 違反の type 参照 (`Record([("x","Bad-Name")])`) を名乗る type を使う定義 | `Rejected` `InvalidRange` (§2.1、lexical 検査。UnknownVocab より前に宣言自体が不正) |
| p | **2 つの要素** (options 2 本) が同じ brokenref を使う定義 | `Rejected` `UnknownVocab` **2 件** — 両 element へ帰属報告 (§5.2 診断規則 3: 走査状態は seed ごと) |
| q1 | `seq` の先頭 leaf は string、後続 named leaf が brokenref | `Rejected` `UnknownVocab` 1 件、`element` は後続 leaf 名 — wrapper の未使用 `ty` でなく全 leaf を走査 |
| q2 | structural `or` の先頭 leaf は string、後続 named leaf が brokenref | q1 と同じ — 全 branch leaf 走査 + leaf 帰属 |
| q3 | 異なる top-level wrapper 配下に同名 leaf `child` が 2 本あり、両方 brokenref | `Rejected` `UnknownVocab` 2 件 — `diagnostic_identity` が同名 leaf の dedup 衝突を防ぐ |
| r1 | 使用中 template の bare leaf が brokenref | `Rejected` `UnknownVocab` 1 件、`element` は template 使用側要素 |
| r2 | brokenref を持つ template を登録するが definition から参照しない | `Ok(_)` — 到達範囲原則 |
| r3 | 2 要素が同じ broken template を参照 | `Rejected` `UnknownVocab` 2 件 — seed 独立 |
| r4 | 使用中 template leaf が self-cycle 型 / malformed union | それぞれ `CircularRef` / `InvalidRange` のみ |

`resolve_type_reference` 単体 (糖衣正規化・exact 一致) は `src/extension` 側か registry 系
wbtest に 2〜3 表明を足してもよい (b/d1 が実質カバーするので任意)。

### 6.3 `src/internal/engine/value_type_classification_wbtest.mbt` (新規) — 暫定分類の全域固定

`value_type_primitive_only` (§4.4) の table-driven wbtest。全 constructor を全域固定する:

| 入力 | 期待 |
|---|---|
| `String` / `Number` / `Bool` / `Null` | `true` |
| `Value` | `false` |
| `Array(String)` / `Map(String)` / `Record([])` | `false` |
| `Union([Bool, Record([("x","string")])])` (mixed union) | `false` |
| `Union([String, Number, Bool, Null])` (全 primitive union) | `true` |

`residual_is_primitive_only(None) == false` も 1 表明。`Union([])` は入れない — §4.4 の
順序保証どおり malformed 宣言に分類関数は適用されない (到達しない入力の挙動を pin しない)。

### 6.4 出口条件の再確認

- `just fmt` (moon fmt) → `just test`: **612 + 新規分 passed / conformance 885 cases
  mismatches=0 / 両台帳空** — 既存分は 1 件も変化しないこと
- `moon info` で `pkg.generated.mbti` 再生成 (extension の公開面から `TypeOutputShape` が
  消え `ValueType` / `output_type` / `input_type` が載る)

## 7. 裁定 (統括確定済み 2026-08-02 — 実装 worker は再検討不要)

### 7.1 `none` type の名乗り — **案 A `Some(Null)` で確定**

none は値スロットを持たない mark で、その「値」は null しかありえない。primitive-only 分類に
入り現行挙動 (残余 link は absent-ref) を保存する。DR-130 で null は値空間の正規住人なので
名乗りとしても矛盾しない。spec の builtin-descriptors.json `/types` に none は居ないため
spec 追記は不要 (挙動保存のため)。

### 7.2 e3 (record 名乗り + 残余) の暫定挙動 — **wbtest で pin するで確定**

W2-6 着手時に RED になり、置換漏れを検出する網になる。テストコメントで
「W2-6 で record 降下 (静的成功) へ置換される暫定 pin」と明示する。

### 7.3 §2.1 well-formedness を definition-error にすること自体 — **採用で確定**

DR-126 に「コード側 resident の malformed 宣言」の明文規範は無い (wire 側は JSON Schema の
領分)。`InvalidRange` での definition-error 化は「schema が wire で強制する制約のコード側等価」
という整理。二次レビュー反映の統括裁定 (§2.1 の検査項目確定 + §4.4 の順序保証 = malformed は
`InvalidRange` のみで落とす) が本検査の存在を前提に確定しており、採用済み — 実装前の追加裁定は不要。

## 8. 統括の読みとの食い違い (指示書との照合結果)

- 指示の「lowering.mbt の Residual 分岐 :4062 / :4159」は実測 **:4065 / :4074 / :4162 / :4163**
  (計 4 箇所、§4.4 の表)。resolve_link_path 側の産出点は :2358 / :2382
- 指示の「DR-067 が kuu.mbt docs/decisions/ にあるはず」→ kuu.mbt に docs/decisions/ は無い
  (DR は spec リポ集約)。DR-067 は spec 側 (wire well-formedness)。kuu.mbt の「参照層」実体は
  `collect_absent_ref` / `collect_circular_ref` (`src/internal/engine/lowering.mbt:3960` 付近、
  DR-054/DR-032/DR-007 の ref template グラフ)。type edge は**同じ kind 語彙・同じ列挙窓を使う
  別グラフの sibling collector** として足す (§5.2) — ref template の `head_cycles` を拡張する
  形ではない (グラフの節点が違う)
- 指示の「既存 885 cases」は実測一致 (`decoded=394 ran_cases=885 skipped=0 mismatches=0`)。
  plan 記載の 880 は W2-1 合流前の値
- 指示の「TypeExt 実装が無変更で動き続ける」は「override していない実装の既定挙動が不変」の意で
  充足する。`output_shape` を override していた実装 (= 本リポ builtin + wbtest のみ、外部なし)
  は書き換えが要る — placeholder の置換であり v1 前完備主義に従い互換レイヤは設けない

## 9. 規模見積と作業順

plan §5 の 400〜700 行に対し、最終実装は概ね **1,200〜1,350 行** (生成 mbti・wbtest 込み)。
上振れの主因は §6.2 の境界ケース h〜r (テスト用 resident と定義 JSON)、§6.3 の分類全域固定、
§2.1 の ABI 直接 wbtest、型 graph walker の seed-local DFS/dedup、および Definition 側の
ElementBody leaf / 使用中 template 到達走査である。

推奨作業順 (各点で `just test` green を維持):

1. `src/abi/value_type.mbt` (enum + declaration_violations) — 単体で green
2. `TypeExt` 置換 + residents + layer_aliases + lowering の carrier/分類置換 —
   ここが本段最大の一括変更 (trait メソッド削除はコンパイラが全 override 箇所を指す)。
   `moon info` 再生成まで含めて green に戻す
3. `Registry::resolve_type_reference` + `collect_type_reference_errors` — 消費者が居ないうちに
   collector を入れても既存定義は record を使わないので green のまま
4. wbtest 4 ファイル (§2.1 / §6) — ABI 宣言制約、resident trait、e3、型依存 graph、暫定分類を固定
5. `jj commit` はパス指定で固定 (触ったファイルのみ列挙)

## 関連

- spec `docs/decisions/DR-126-descriptor-record-value-type.md` §1〜§5 (体系の正本)
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §2.2 (W2-6 が実装する遷移表 — 本段の
  モデルが表の 6 行を直接表現できることが要件)
- spec `docs/decisions/DR-128-type-input-structure-splice.md` §7/§8 (入力側の席と包含規則の正本)
- spec `docs/decisions/DR-130-null-result-projection.md` / `DR-131-sentinel-reduction.md`
  (record の型導出が `T | null` — W2-2 のモデルには効かないが W2-5/W2-7 の消費者が前提にする)
- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §1.6 / §2 W2-2 行 / §5 / §6
