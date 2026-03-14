# DR-043: Opt[T] に priv setter を追加

## 背景

DR-040 で clone / full adjust の実装が「Opt[T] に setter がないため保留」とされていた。
現状の Opt[T] は getter のみを公開しており、パース後の値書き換えや、
既存 Opt の値を別名ノード経由で更新する手段がない。

## 問題

1. **clone**: 既存 Opt のファクトリなしに別名ノードを作りたいが、値の書き込み手段がない
2. **adjust**: パース後に Opt の値を変換・加工したいが、post_hook から cell に直接触れない
3. **deprecated の before_accum**: alias + post_hook で代替しているが、setter があればより直接的に実装可能

## 選択肢

### A. `pub(all)` で setter を公開

- ユーザが自由に `(opt.setter)(value)` できてしまう
- `is_set` との整合性が壊れる（setter で書いたのに is_set は false のまま）
- **却下**: API の安全性を損なう

### B. `pub struct` (readonly) にして setter フィールドを含める

- 外部パッケージからフィールドは読めるが構築・変更はできない
- ただし `opt.setter` が読めれば `(opt.setter)(value)` で呼べてしまう
- readonly は「構築禁止」であって「フィールド値の利用禁止」ではない
- **却下**: setter クロージャが見えること自体が問題

### C. `priv setter` フィールド（採用）

- `priv` フィールドは外部パッケージから完全に不可視（読み書き両方不可）
- core パッケージ内からは自由にアクセス可能
- `priv` フィールドがあると外部パッケージから struct literal で構築不可 → Opt[T] は元々 core 内でしか構築しないため問題なし

### D. `pub fn Opt::set()` メソッドで公開

- setter フィールドは priv だが pub メソッド経由で呼べる
- ユーザからも呼べてしまうため A と同じ問題
- **却下**

### E. `internal/` パッケージに setter 操作を配置

- `src/core/internal/` に置けば core と dx だけがアクセス可能
- しかし dx 層は core の public API 消費者であるべき
- internal アクセスに依存すると core/dx の境界が曖昧になる
- **却下**: dx 層を core の内部実装に結合させるべきではない

## 決定

**C. `priv setter` フィールドを採用。**

```moonbit
pub(all) struct Opt[T] {
  id : Int
  name : String
  getter : () -> T
  priv setter : (T) -> Unit   // core 内のみアクセス可
  parsed : Ref[Bool]
  is_set : () -> Bool
}
```

## 設計原則

- **setter は core 内に閉じる** — clone / adjust / deprecated 等のコンビネータ間値操作のみに使用
- **dx 層は影響を受けない** — 引き続き apply_fn パターンで動作
- **ユーザ API は変わらない** — getter + is_set のみが外部から見える

## 実装方針

1. `Opt[T]` に `priv setter : (T) -> Unit` を追加
2. 各コンビネータで setter を設定:
   - flag, custom, custom_append, count, positional, rest, dashdash: `setter=fn(v) { cell.val = v }`
   - cmd: `setter=fn(v) { cell.val = Some(v) }`（内部 cell が `Ref[CmdResult?]` のため Option でラップ）
   - alias: `target.setter` を引き継ぎ（値共有のため）
3. DR-040 で保留の clone / adjust 解禁を検証（別 DR で扱う）

## setter の使用制約

- **setter は cell 値の直接書き換えのみを行う。** `was_set` フラグや `pending` 等の内部状態は更新しない。
- **`is_set` とは連動しない。** setter 呼び出し後に `is_set` を true にする必要がある場合は、呼び出し側が `was_set.val = true` を別途行う。
- **パース後の値変換に使用すること。** OC フェーズ中の投機実行（pending ベース）とは独立した操作であり、パース中に setter を呼ぶと pending との不整合が生じうる。

## dx 層との関係

dx 層（`src/dx/`）は Opt[T] の public API（getter, is_set, as_ref）のみを使用する。
setter は priv のため dx からアクセスできず、これは意図的な設計。
dx の apply_fn クロージャは Opt の setter とは独立した仕組みであり、
ユーザ struct への値注入を担う。両者は責務が異なる:

- **Opt.setter**: core 内部での cell 値操作（コンビネータ間連携）
- **apply_fn**: dx 層でのユーザ struct フィールドへの値注入
