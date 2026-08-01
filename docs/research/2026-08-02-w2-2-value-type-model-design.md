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
| `src/extension/node_traits.mbt` | `TypeOutputShape` 削除、`TypeExt::output_shape` → `output_type`、`input_type` 席追加 |
| `src/extension/type_residents.mbt` | builtin 10 residents の `output_shape` impl を `output_type` へ (§4.2 の表) |
| `src/extension/registry.mbt` | `Registry::resolve_type_reference` 追加 |
| `src/internal/engine/layer_aliases.mbt` | `type TypeOutputShape,` の行を削除 (`ValueType` は `@abi` 直参照で足りるか確認、engine の既存 `@abi` alias 慣行に合わせる) |
| `src/internal/engine/lowering.mbt` | `LinkPathResolution::Residual` の carrier 置換、暫定分類関数、`collect_type_reference_errors` 追加 |
| `src/extension/type_residents_wbtest.mbt` | `:77`/`:80` の `output_shape` 表明を `output_type` へ書き換え |
| `src/kuu/value_type_reference_wbtest.mbt` | **新規**。§6 の parse_definition レベル wbtest |
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
  Union(Array[ValueType]) // [T1, T2, ...] — 2 要素以上
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
- **union は平坦**。DR-107 由来の記法上 union の入れ子は書けない (JSON 配列の要素は
  value_type)。enum 上は `Union(Union(...))` が構築できてしまうため §2.1 で弾く

### 2.1 宣言の well-formedness 検査 (abi 内の純関数)

descriptor JSON なら spec の `schema/descriptor.schema.json` が構文を強制するが、コード側
resident の宣言は schema を通らない。等価なゲートを 1 つ置く:

```moonbit
///|
/// 宣言としての構文健全性。schema/descriptor.schema.json が wire 側で強制する制約の
/// コード側等価物: union は 2 要素以上かつ直下に union を含まない、record のフィールド名は
/// 非空かつ重複なし、type 参照の綴りは非空。違反箇所を人間可読の径路つきで列挙する。
pub fn ValueType::declaration_violations(self : ValueType) -> Array[String]
```

再帰で全部の入れ子を検査し、`"union has 1 member (needs 2+) at .array"` のような文字列を返す。
lowering の collector (§5) が非空なら `InvalidRange` の DefError に畳む (単一値の内部不正でなく
「宣言の組合せが値域外」なので `InvalidRange`、`repeat min > max` と同じ整理 — DR-082 系)。

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

### 5.2 アルゴリズム

```moonbit
///|
/// DR-126 §1: record フィールドの type 参照は registry 空間で解決できなければ
/// definition-error unknown-vocab、型依存グラフ (record フィールド経由の type edge) の
/// 循環は circular-ref。検査対象は当該 definition の要素が使う型から到達可能な範囲のみ。
/// DR-067 の参照層 (ref template の collect_absent_ref / collect_circular_ref) と同じ
/// kind 語彙・同じ全件列挙の窓を共有するが、グラフは別 (あちらは ref template の
/// head-position chain、こちらは registry type の宣言依存)。
fn collect_type_reference_errors(
  def : Definition,
  extensions : Registry,
  out : Array[DefError],
) -> Unit
```

1. **seed 集め**: `def.options` / `def.positionals` の各 `ElementDef.ty`、`def.commands` は
   `command.body` へ再帰 (walker の形は `collect_link_path_errors` (`:4026`) を写す)。
   seed は「(要素名, resident)」の組。同一 resident 名は要素ごとに重複させない
2. **各 seed から DFS**: 現在の型の `output_type()` から type 参照を集める:
   - `Record(fields)` → 各 field の参照綴りが edge。**参照先の中へは、参照先 type の
     `output_type()` を通して降りる** (DR-126 §1 の再帰導出と同じ経路)
   - `Array(t)` / `Map(t)` → `t` を再帰 (record が入れ子で現れうる: `{"array": {"record": ...}}`)
   - `Union(members)` → 各 member を再帰
   - primitive / `Value` → edge なし
3. **未登録参照**: `extensions.resolve_type_reference(spelling)` が `None` →
   `DefError { element: <seed の要素名>, kind: UnknownVocab, message: "type '<型名>' field
   '<フィールド名>' references unregistered type '<綴り>'", hint: "register the type or fix
   the reference spelling" }`。message 文言は最終的に実装者が整えてよいが、**型名・フィールド名・
   参照綴りの 3 つを必ず含める** (参照は seed から複数 hop 先にありうるため、要素名だけでは
   位置が特定できない)
4. **循環**: DFS の on-stack 集合 (正規化済み綴りで持つ) に既在の型へ edge が向いたら
   `CircularRef`。message には循環路を含める (例: `"type dependency cycle: timerange ->
   timestamp -> timerange"`)。自己参照 (`Node.next -> Node`) も同規則で落ちる (DR-126 §1)
5. **重複抑制**: 同一 (element, kind, 対象綴り) の DefError は 1 defintion 内で 1 回。
   visited 集合 (検査済みの型) を definition 単位で共有すれば、seed が違っても同じ壊れ方を
   二重報告しない — ただし **element 帰属が変わる場合は seed ごとに報告してよい**
   (`collect_*` 系の「全件収集」慣行に合わせ、実装の単純さを優先)
6. **well-formedness**: DFS 中に各型の宣言へ §2.1 の `declaration_violations` を 1 回適用し、
   非空なら `InvalidRange` で報告する

注意: 検査は `output_type()` の宣言グラフのみを辿る。`input_type` 側の依存
(DR-128 §8 の `input_structure` 経由循環) は定義片の splice 実装 (DR-128 サイクル) の領分で、
本段では辿らない。

## 6. wbtest 計画

### 6.1 `src/extension/type_residents_wbtest.mbt` (既存改修)

`:77`/`:80` の `assert_eq(resident.output_shape(), Primitive)` / `Opaque` を置換:

- builtin 各 resident の `output_type()` が §4.2 の表どおり (`string_type().output_type() ==
  Some(String)` 等、10 件)
- override しない外部 resident (テスト内 struct) の `output_type() == None`
- `input_type()` の既定が `ValueType::String` (builtin 1 件 + override なし外部 1 件)

### 6.2 `src/kuu/value_type_reference_wbtest.mbt` (新規)

registry 構築は `src/kuu/lower_conformance_wbtest.mbt:660` 付近の builtin 登録パターンを写し、
そこへテスト用 resident を追加登録する。テスト用 resident は最小 4 種:

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

`resolve_type_reference` 単体 (糖衣正規化・exact 一致) は `src/extension` 側か registry 系
wbtest に 2〜3 表明を足してもよい (b/d1 が実質カバーするので任意)。

### 6.3 出口条件の再確認

- `just fmt` (moon fmt) → `just test`: **612 + 新規分 passed / conformance 885 cases
  mismatches=0 / 両台帳空** — 既存分は 1 件も変化しないこと
- `moon info` で `pkg.generated.mbti` 再生成 (extension の公開面から `TypeOutputShape` が
  消え `ValueType` / `output_type` / `input_type` が載る)

## 7. 裁定候補 (実装前に統括の裁定が要る点)

### 7.1 `none` type の名乗り — 推し: `Some(Null)`

- **案 A (推し): `Some(Null)`** — none は値スロットを持たない mark で、その「値」は null しか
  ありえない。primitive-only 分類に入り現行挙動 (残余 link は absent-ref) を保存する
- 案 B: `None` (名乗らない) — 「none に output は無い」という読み。ただし残余 link のエラーが
  absent-ref → Unsupported へ**変わる** (挙動変化)。挙動保存の観点で不利
- spec に none type の io_type.output を明記した箇所は見つけていない (builtin-descriptors.json の
  `/types` に none は居ない)。裁定が B に出る場合は spec 側の追記も要る

### 7.2 e3 (record 名乗り + 残余) の暫定挙動を wbtest で pin するか — 推し: pin する

- 推し: pin する (W2-6 着手時に RED になり、置換漏れを検出する網になる)。テストコメントで
  暫定である旨を明示
- 対案: pin しない (W2-6 でのテスト書き換えを省く)。silent hole を許すので不利

### 7.3 §2.1 well-formedness を definition-error にすること自体

DR-126 に「コード側 resident の malformed 宣言」の明文規範は無い (wire 側は JSON Schema の
領分)。`InvalidRange` での definition-error 化は「schema が wire で強制する制約のコード側等価」
という整理での提案。却下 (= 検査しない、構築側 invariant のコメント注記のみ) でも本段は成立する。

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

plan §5 の 400〜700 行に対し、本設計の実装は概ね: abi 90〜130 / extension 60〜90 /
lowering 130〜200 / wbtest 250〜350 = **530〜770 行** (wbtest 込み。やや上振れは e/f/g 系の
定義 JSON が嵩むため)。

推奨作業順 (各点で `just test` green を維持):

1. `src/abi/value_type.mbt` (enum + declaration_violations) — 単体で green
2. `TypeExt` 置換 + residents + layer_aliases + lowering の carrier/分類置換 —
   ここが本段最大の一括変更 (trait メソッド削除はコンパイラが全 override 箇所を指す)。
   `moon info` 再生成まで含めて green に戻す
3. `Registry::resolve_type_reference` + `collect_type_reference_errors` — 消費者が居ないうちに
   collector を入れても既存定義は record を使わないので green のまま
4. wbtest 2 ファイル (§6) — e3 等の暫定 pin を最後に
5. `jj commit` はパス指定で固定 (触ったファイルのみ列挙)

## 関連

- spec `docs/decisions/DR-126-descriptor-record-value-type.md` §1〜§5 (体系の正本)
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §2.2 (W2-6 が実装する遷移表 — 本段の
  モデルが表の 6 行を直接表現できることが要件)
- spec `docs/decisions/DR-128-type-input-structure-splice.md` §7/§8 (入力側の席と包含規則の正本)
- spec `docs/decisions/DR-130-null-result-projection.md` / `DR-131-sentinel-reduction.md`
  (record の型導出が `T | null` — W2-2 のモデルには効かないが W2-5/W2-7 の消費者が前提にする)
- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §1.6 / §2 W2-2 行 / §5 / §6
