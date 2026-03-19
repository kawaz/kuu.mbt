---
type: decision
---

# DR-045: ValCell / Accessor 分離 — Opt[T] から値のライフサイクルを独立させる

**ステータス: accepted (Phase 1-4 implemented)**

## 背景

DR-037 で 3 直交プリミティブ（clone, link, adjust）を設計し、DR-043 で `priv setter` を追加、
DR-044 で v1 実装を完了した。しかし実装を進める中で、Opt[T] が「値の格納」と「パース振る舞い」の
2 つの責務を混在して持っていることが、今後のコンビネータ拡張のボトルネックになることが見えてきた。

## 現状の問題

### 1. Opt[T] に値とパース振る舞いが混在している

現在の `Opt[T]` 構造:

```moonbit
pub(all) struct Opt[T] {
  id : Int              // パース振る舞い（識別子）
  name : String          // パース振る舞い（表示名）
  getter : () -> T       // 値の格納（読み取り）
  priv setter : (T) -> Unit  // 値の格納（書き込み）
  parsed : Ref[Bool]     // パース振る舞い（パース済みフラグ）
  is_set : () -> Bool    // 値の格納（設定状態）
}
```

`getter`, `setter`, `is_set` は値のライフサイクルに属し、
`id`, `name`, `parsed` はパース登録・状態管理に属する。
この混在により、値の共有パターン（alias）と値の独立パターン（clone）を
統一的に扱うことが難しい。

### 2. alias での暗黙的な cell 共有

`parser.mbt` の alias 実装（L92-153）では、target の `getter` と `setter` をそのまま
新しい Opt に引き継いでいる:

```moonbit
// alias の返り値（parser.mbt L148-155）
{
  id,
  name,
  getter: target.getter,   // target の cell を暗黙的に共有
  setter: target.setter,   // target の cell を暗黙的に共有
  parsed: target.parsed,
  is_set: fn() { alias_was_set.val },  // is_set だけ独立
}
```

値の共有が「getter/setter クロージャの参照コピー」で暗黙的に実現されている。
この暗黙性は alias の意図（値共有）を型レベルで表現できておらず、
コードを読んだときに「なぜ getter が共有されるのか」が不明瞭。

### 3. clone が alias と同一実装

DR-044 で clone は v1 として alias のラッパーとして実装された:

```moonbit
pub fn[T] Parser::clone(self : Parser, name : String, target : Opt[T]) -> Opt[T] {
  self.alias(name, target)  // alias と完全に同一
}
```

DR-037 の本来の設計では clone は「新 Ref、フィルタ参照共有」— つまり独立した値セルを持つ
構造コピーであるべきだが、現状では値セルの概念が Opt[T] の中に溶け込んでいるため、
「値だけ独立にする」操作を自然に表現できない。

### 4. 各コンビネータで cell / was_set / pending の三点セットが散在

`flag`, `custom`, `custom_append`, `count`, `positional`, `rest`, `dashdash` の各コンビネータで、
値セルに相当する `cell: Ref[T]`, `was_set: Ref[Bool]`, (場合により `pending: Ref[T]`) を
個別にローカル変数として宣言している。

例: `flag` コンビネータ（options.mbt）

```moonbit
let cell : Ref[Bool] = { val: initial_val }
let pending : Ref[Bool] = { val: initial_val }
let was_set : Ref[Bool] = { val: false }
```

例: `custom` コンビネータ（options.mbt）

```moonbit
let cell : Ref[T] = { val: initial_val }
let was_set : Ref[Bool] = { val: false }
```

例: `positional`（positionals.mbt）

```moonbit
let cell : Ref[String] = { val: "" }
let pending : Ref[String] = { val: "" }
let was_set : Ref[Bool] = { val: false }
```

これらは全て「値の実体を保持する」という同一の責務を持つが、共通の抽象が存在しない。
新しいコンビネータを追加するたびに同じパターンを手動で再現する必要がある。

### 5. link / adjust が setter 経由で is_set を更新できない

DR-044 の link 実装では、`setter` が cell 値のみを更新し `was_set` は変更しない
（DR-043 の設計原則: 「setter は cell 値の直接書き換えのみ。was_set は更新しない」）。

```moonbit
// link: setter 経由の値転送（parser.mbt）
pub fn[T] Parser::link(self : Parser, target : Opt[T], source~ : Opt[T]) -> Unit {
  self.post_hooks.push(fn() raise ParseError {
    if (source.is_set)() {
      (target.setter)((source.getter)())  // was_set は変わらない
    }
  })
}
```

これは設計上意図的な判断だが、将来的に「link で値を転送したら target も set 扱いにしたい」
ケースが出てきた場合、setter の仕様変更が必要になる。値操作の API が
`getter` / `setter` / `is_set` とバラバラのクロージャで、統一的な操作セットがない。

## 提案: ValCell / Accessor / Opt の 3 層分離

### ValCell[T] — 値の実体

値の格納・状態管理を担う最小単位。`Ref[T]` + `was_set` + `default` を内包する。

```moonbit
// 概念的な構造（実装時の詳細は別途検討）
struct ValCell[T] {
  cell : Ref[T]
  was_set : Ref[Bool]
  default : T
}
```

ValCell が提供する操作:

- **`.accessor()`** → `Accessor[T]`: この ValCell に紐づいた操作インターフェースを返す。
  同じ ValCell から何度呼んでも同じ cell を操作する（= 共有）。
- **`.clone()`** → `ValCell[T]`: 現在の default 値で新しい独立した ValCell を作る。
  元の ValCell とは独立した cell / was_set を持つ。

### Accessor[T] — 値操作のインターフェース

ValCell への操作をクロージャ束として提供。Opt や post_hook から値を操作する統一 API。

```moonbit
// 概念的な構造
struct Accessor[T] {
  get : () -> T
  set : (T) -> Unit
  is_set : () -> Bool
  reset : () -> Unit      // cell = default, was_set = false
  commit : () -> Unit     // pending → cell（OC フェーズ用、必要に応じて）
}
```

`set` は `cell.val` の更新に加えて `was_set.val = true` も行う。
これにより DR-043 の「setter は was_set を更新しない」制約が解消され、
link/adjust で「値を転送したら set 扱いにする」パターンも自然に表現できる。

ただし `was_set` を変更しない「静かな書き込み」も必要な場面がある（例: default の遅延評価）。
これは `set_quiet` 等の別メソッドで対応するか、`set` のオプション引数で制御するかを検討する。

### Opt[T] — パース振る舞い + Accessor 参照

パースエンジンが認識するオプション定義。値の操作は Accessor 経由。

```moonbit
pub(all) struct Opt[T] {
  id : Int
  name : String
  priv accessor : Accessor[T]  // 値操作は全てこれ経由
  parsed : Ref[Bool]
}
```

ユーザ向けの `getter` / `is_set` は `Opt[T]` のメソッドとして Accessor をラップ:

```moonbit
pub fn[T] Opt::get(self : Opt[T]) -> T? {
  if self.parsed.val { Some((self.accessor.get)()) } else { None }
}

pub fn[T] Opt::is_set(self : Opt[T]) -> Bool {
  (self.accessor.is_set)()
}
```

`setter` は引き続き `priv` 相当（Accessor が priv であることで自動的に外部不可視）。

## clone / link / adjust / alias がどう変わるか

### alias: 同じ ValCell の Accessor を共有

```
alias(target) → target の ValCell.accessor() を新しい Opt に渡す
```

現状の「getter/setter を暗黙コピー」が「同じ ValCell の Accessor を共有」に
明示化される。コードの意図が型レベルで表現できる。

```moonbit
// Before (現状): 暗黙的な cell 共有
{ getter: target.getter, setter: target.setter, is_set: ... }

// After (提案): 明示的な Accessor 共有
{ accessor: target_valcell.accessor(), ... }
```

alias 固有の `alias_was_set` は Opt レベルの `is_set` オーバーライドとして別途保持。
Accessor の `is_set` は ValCell のもの（target と共有）、Opt の `is_set` は alias 固有。

### clone: ValCell.clone() で独立 Accessor

```
clone(target) → target の ValCell.clone().accessor() を新しい Opt に渡す
```

DR-037 の本来の設計「新 Ref、フィルタ参照共有」が自然に実現される。
ValCell.clone() が独立した cell/was_set を持つので、clone 先への書き込みが
元の target に影響しない。

```moonbit
// clone: 独立した値セルを持つ
let cloned_cell = target_valcell.clone()
{ accessor: cloned_cell.accessor(), ... }
```

### link: Accessor 間の値転送

```
link(target, source) → post_hook で source.accessor.get → target.accessor.set
```

Accessor の `set` が `was_set = true` を含むため、link による値転送で
target の is_set も自動的に true になる。これが望ましくない場合は
`set_quiet` を使うか、明示的に `is_set` を操作する。

```moonbit
// Before: setter + was_set 非連動
(target.setter)((source.getter)())

// After: Accessor.set で was_set も連動
(target.accessor.set)((source.accessor.get)())
```

### adjust: Accessor 経由の値変換

```
adjust(target, after_post) → post_hook で target.accessor.get → transform → target.accessor.set
```

現状とほぼ同じだが、Accessor 経由になることで操作が統一される。

## コンテナ系コンビネータでの ValCell.clone() の活用

### serial

serial は位置ごとに独立したパースを行うが、現在は各サブ positional が
独自の cell/was_set を持つ。ValCell を使えば:

```
serial(setup) → setup 内の各 positional が独立した ValCell を持つ（現状と同じ）
```

serial 自体は ValCell.clone() を必要としないが、将来的に
「同じ positional テンプレートを位置ごとに複製する」パターンで
ValCell.clone() が活躍する。

### rest

rest は `Array[String]` を追記していく。ValCell[Array[String]] として:

```
rest → ValCell[Array[String]] を持ち、各 commit で push
```

### group（将来構想）

group は複数の opt をまとめて扱う将来構想。各メンバーの ValCell を
clone して独立インスタンスを作ることで、グループごとの値管理が自然になる:

```
group(opts, n) → 各 opt の ValCell を n 回 clone して n 組の独立値セットを生成
```

### variation

variation は「振る舞いの異なる alias」。同じ ValCell を共有しつつ、
ExactNode の try_reduce で異なる書き込みパターンを実行する。
ValCell の Accessor を共有する alias パターンそのまま。

## dx 層への影響

### 影響は最小限

dx 層（`src/dx/`）は Opt[T] の public API（`get()`, `is_set()`, `as_ref()`）のみを使用する。
ValCell / Accessor は core 内部の実装詳細であり、dx 層には露出しない。

```
dx 層 → Opt[T].get() / Opt[T].is_set() / Opt[T].as_ref()
         ↓（内部で Accessor を参照）
core 層 → Accessor[T] → ValCell[T]
```

FieldRegistry の各メソッド（`flag`, `string`, `int` 等）は Parser のコンビネータを呼んで
Opt[T] を受け取り、`opt.get()` と `opt.is_set()` で値を取得する。
ValCell 導入後もこのインターフェースは変わらない。

### apply_fn との関係

dx 層の `apply_fn` は「ユーザ struct のフィールドに値を注入するクロージャ」であり、
Accessor とは独立した仕組み。両者の責務は明確に分離されている:

| 仕組み | 責務 | 所属 |
|--------|------|------|
| Accessor | core 内でのコンビネータ間値操作 | core |
| apply_fn | ユーザ struct への値注入 | dx |

ValCell 導入は dx 層の apply_fn パターンに一切影響しない。

## 移行戦略

### 段階的に移行可能

ValCell / Accessor の導入は、既存の public API を破壊せずに段階的に進められる。

#### Phase 1: ValCell 型の導入（内部リファクタ）

1. `ValCell[T]` struct を `src/core/types.mbt` に追加
2. `Accessor[T]` struct を `src/core/types.mbt` に追加
3. 各コンビネータ内の `cell: Ref[T]` + `was_set: Ref[Bool]` を `ValCell[T]` に置き換え
4. `register_option` の `getter~` / `setter~` / `was_set~` を `accessor~` に統合

この段階では Opt[T] の構造はまだ変えない。内部で ValCell を使いつつ、
Opt の構築時に `getter: accessor.get, setter: accessor.set, is_set: accessor.is_set`
として互換を保つ。

#### Phase 2: Opt[T] 構造の変更

1. `Opt[T]` から `getter`, `setter`, `is_set` を除去し `accessor: Accessor[T]` に置換
2. `Opt::get()`, `Opt::is_set()` メソッドを Accessor 経由に書き換え
3. alias の実装を「Accessor 共有」パターンに書き換え

`getter` / `is_set` は現在 `pub(all)` フィールドとして直接アクセス可能だが、
`Opt::get()` / `Opt::is_set()` メソッドが既に存在するため、
フィールドアクセスをメソッドアクセスに統一する移行が必要。

#### Phase 3: clone の完全実装 + AliasSource リネーム

1. `Parser::clone` を `ValCell.clone()` ベースに書き換え
2. clone が独立した cell を持つことを検証するテスト追加
3. DR-044 の「clone は alias のラッパー（v1）」制約を解消
4. `AliasSource` → `NodeTemplate` リネーム
   - `target_was_set` の削除は alias の Accessor 統合が必要なため Phase 4 に延期

#### Phase 4: link / adjust の Accessor 統合 + target_was_set 削除

1. `link` を `Accessor.set` ベースに書き換え（was_set 連動の選択肢を提供）
2. `adjust` を `Accessor` ベースに書き換え
3. setter の「was_set 非更新」制約を Accessor の使い分けで解消
4. alias の commit を Accessor 経由に統合し、`NodeTemplate.target_was_set` を削除

### 各フェーズの独立性

各フェーズは独立してマージ可能。Phase 1 だけでもコンビネータ内部の整理として価値がある。
Phase 2 は public API の変更を伴うため慎重に進める必要があるが、
`Opt::get()` / `Opt::is_set()` メソッド経由のアクセスが主流であれば影響は限定的。

## 設計上の検討事項

### pending の扱い

OC フェーズの投機実行では `pending` → `commit` → `cell` の 2 段階書き込みが行われる。
ValCell に pending を含めるかは検討が必要:

- **含める場合**: ValCell が OC フェーズの投機実行を知っている必要がある。責務が増える。
- **含めない場合**: pending は ExactNode の try_reduce クロージャ内のローカル変数のまま。
  ValCell は commit 後の確定値のみを管理する。

現時点では **含めない** 方向を推奨。pending は OC フェーズのメカニクスであり、
値のライフサイクルとは別の関心事。

### AliasSource → NodeTemplate へのリネーム

現在の `AliasSource` は以下を保持している:

| フィールド | 責務 | ValCell 導入後 |
|---|---|---|
| `make_node` | 別名で ExactNode を生成するファクトリ | そのまま残る |
| `target_was_set` | alias 使用時に target の was_set を true にする | ValCell に吸収（不要に） |
| `is_global` | global_nodes への登録判断 | そのまま残る |
| `make_eq_fallback` | implicit_value の eq_split 対応 | そのまま残る |

ValCell 導入で `target_was_set` が不要になり、残るのは ExactNode 生成テンプレート + メタデータ。
実態は「任意の Opt がコピー元となり、別名で同じパース振る舞いの ExactNode を生やすためのテンプレート」
なので、`AliasSource` → `NodeTemplate` にリネームする。

```moonbit
// After: target_was_set が ValCell に吸収され、名前も実態に合わせる
struct NodeTemplate {
  make_node : (String) -> ExactNode
  is_global : Bool
  make_eq_fallback : ((String) -> ExactNode)?
}
```

命名候補として `NodeFactory` も検討したが、Factory は「そいつが他の Opt を生産する専門家」
という印象を与える。実際には全ての Opt がコピー元になりうるため、
「どの Opt からでも別名を生やせるテンプレート」という構造を素直に表現する `NodeTemplate` を採用。

### Accessor の priv 制御

Accessor は core 内部の操作インターフェース。dx 層やユーザからは Opt のメソッド経由で
値にアクセスする。Accessor 自体を `priv` にするか、Opt の `priv accessor` フィールドとして
隠蔽するかは Phase 2 で決定する。

## 関連 DR

- **DR-037**: 3 直交プリミティブ（clone, link, adjust）の設計 — ValCell で clone が本来の姿に
- **DR-043**: `priv setter` — ValCell / Accessor に発展的に吸収される
- **DR-044**: clone/link/adjust v1 実装 — ValCell 導入で v2 へ進化
- **DR-027**: core 純粋関数主義 — ValCell は純粋な値コンテナ、副作用なし
- **DR-042**: struct-first dx 層 — dx は引き続き Opt の public API のみ使用
