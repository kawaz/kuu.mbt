# DR-001: Trait ベース struct-first CLIパーサ方式の技術検証

## 概要

kuu の新しい DX レイヤーとして「struct-first」アプローチを検証。ユーザーが struct を先に定義し、trait impl で CLI パース定義を行い、パース結果が struct に直接注入される方式。

## 検証した技術的疑問と結果

### 1. MoonBit struct の mut フィールド

**疑問**: struct フィールドに `mut` 修飾子を付けて直接変更できるか？

**結果**: **可能** ✅

```moonbit
struct DockerConfig {
  mut verbose : Bool
  mut log_level : String
}
```

MoonBit の `Ref[T]` 自体が `mut val` を持つことから推測通り、ユーザー定義 struct でも `mut` フィールドが使える。

### 2. Trait impl 内から self の mut フィールド変更

**疑問**: `impl Parseable for MyStruct with register(self, reg)` 内で `self.field = value` ができるか？

**結果**: **可能** ✅

```moonbit
impl Parseable for DockerConfig with register(self, reg) {
  reg.flag(
    name="verbose",
    apply_fn=fn(v) { self.verbose = v },  // クロージャで self をキャプチャして変更
  )
}
```

重要な発見: クロージャが `self` をキャプチャし、後から（parse 後に）呼ばれる apply_fn 内で `self.verbose = v` が正しく動作する。

### 3. FieldRegistry による kuu core との橋渡し

**疑問**: kuu core の `Parser` をラップし、trait impl から使いやすい API を提供できるか？

**結果**: **可能** ✅

FieldRegistry は内部で:
1. kuu core の `Parser` にコンビネータを登録
2. パース後に実行する「applier クロージャ」を蓄積
3. `apply_all()` で全 applier を実行し、struct フィールドに値を注入

### 4. サブコマンドのネスト

**疑問**: サブコマンド内の struct フィールドも同じ方式で注入できるか？

**結果**: **可能** ✅

```moonbit
reg.sub(
  name="run",
  on_match=fn() { self.command = Some(Run) },
  setup=fn(r) {
    r.flag(name="detach", apply_fn=fn(v) { self.run.detach = v })
    r.positional(name="IMAGE", apply_fn=fn(v) { self.run.image = v })
  },
)
```

外側の struct のネストしたフィールド（`self.run.detach`）にもクロージャ経由で書き込める。

### 5. positional の is_set 問題

**発見**: kuu core の positional は default="" なので、`opt.get()` だけでは「未指定」と「空文字指定」を区別できない。

**対策**: FieldRegistry の positional applier で `(opt.is_set)()` をチェックし、未指定時は struct のデフォルト値を維持する。

## 設計判断

### FieldRegistry のアプローチ

**選択**: kuu core の Parser をラップする FieldRegistry を中間層として導入。

**理由**:
- kuu core を変更せずに struct-first 体験を提供できる
- applier パターン（クロージャ蓄積 → 一括実行）は kuu core の commit パターンと同じ発想
- サブコマンドの子 applier を親に伝搬させることでネスト対応も自然に実現

### Parseable trait の設計

```moonbit
trait Parseable {
  register(Self, FieldRegistry) -> Unit
}
```

**選択**: register メソッド1つのみ。apply は FieldRegistry 内部で自動処理。

**理由**: ユーザーが書くコードを最小限にする。register だけ impl すれば parse_into が全てやってくれる。

## 制限事項

1. **pub(open) 未検証**: 同一パッケージ内での impl のみ検証。外部パッケージからの impl は未検証（PoC の範囲外）
2. **エラーハンドリング**: parse_into は kuu core の ParseError をそのまま raise。カスタムバリデーションは post_hooks 経由になるが FieldRegistry では未対応
3. **型安全性**: apply_fn のクロージャ型は実行時に確認。コンパイル時にフィールド型と登録型の不一致を検出できない

## 結論

MoonBit の trait + mut フィールドで struct-first CLIパーサは**完全に実現可能**。FieldRegistry パターンにより kuu core を無修正のまま高レベル DX を提供できる。
