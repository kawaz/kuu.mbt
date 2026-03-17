---
type: decision
---

# DR-040: deprecated コンビネータ実装 + clone/adjust 設計分析

## 背景

DR-037 で設計した3直交プリミティブ（clone, link, adjust）のうち、
alias（= link の実質実装）は完了。残りの clone, adjust, および合成パターンの
deprecated を実装する段階に入った。

## 分析結果

### deprecated: 即実装可能

deprecated は adjust の合成パターン（`adjust(alias(opt, name), before_accum=record)`）として
設計されていたが、**adjust を経由せず直接実装できる**:

```
deprecated(opt, name, msg) = alias(opt, name) + post_hook(record_usage)
```

- `alias()` で値共有する別名を作成
- `post_hook` で使用を検知・記録（パース完了後に実行）
- `deprecated_warnings()` で記録を取得し、呼び出し側が警告表示

### clone: 型消去の壁（実装延期）

**問題**: AliasSource の `make_node: (String) -> ExactNode` は Ref[T]（cell/pending）を
クロージャに捕捉している。clone は新しい Ref[T] で独立した ExactNode を作る必要があるが、
AliasSource は非ジェネリック構造体のため T を持てない。

**検討した解法と課題**:

| 解法 | 課題 |
|------|------|
| save/commit/restore パターン | setter が Opt[T] にない。Array 型は参照コピーのため深いコピーが必要 |
| make_clone ファクトリを AliasSource に追加 | 戻り値に `() -> T` を含むため型消去できない |
| Opt[T] に setter 追加 | API 変更。これ自体は小さいが clone の Array 問題は残る |
| コンビネータ種別記録 + 再構築 | pre フィルタの型消去が必要 |

**結論**: Opt[T] への setter 追加が最も筋がよいが、API 変更を伴うため別途検討。
clone の主要ユースケース（group の雛形複製）は未実装のため、急ぎではない。

### adjust: ノード変更の壁（実装延期）

**問題**: adjust は登録済み ExactNode の振る舞いを変更する。しかし:

1. **after_post（値変換）**: cell への書き込みが必要 → setter なしでは実装不可
2. **before_accum（記録）**: post_hook で代替可能（deprecated はこれで解決）
3. **before_pre/after_pre**: ノードの try_reduce を事後的に差し替える必要あり

**結論**: 実用的なユースケース（deprecated, stricter）は既存機構で代替可能。
フル adjust は Opt[T] setter 追加後に実装する。

## 決定

### 今回実装するもの

1. **deprecated コンビネータ**: alias + post_hook 方式で直接実装
2. **deprecated_usages ストレージ**: Parser に追加
3. **deprecated_warnings() API**: パース後の警告取得

### 延期するもの

1. **clone**: Opt[T] setter 追加と合わせて将来実装
2. **adjust（フル版）**: 同上。before_accum 相当は post_hook で代替

### API 設計

```moonbit
// deprecated コンビネータ
pub fn[T] Parser::deprecated(
  self : Parser,
  name : String,        // 非推奨な別名（生文字列、"--" 自動付加なし）
  target : Opt[T],      // 推奨される本体
  msg~ : String = "",   // 警告メッセージ
) -> Opt[T]

// 警告取得
pub fn Parser::deprecated_warnings(self : Parser) -> Array[(String, String)]
// Returns: [(name, msg), ...]
```

使用例:

```moonbit
let verbose = p.flag(name="verbose")
let old = p.deprecated("--old-verbose", verbose, msg~="Use --verbose instead")

let result = try! p.parse(args)
for pair in p.deprecated_warnings() {
  eprintln("warning: " + pair.0 + " is deprecated. " + pair.1)
}
```

## 将来の展望

### Opt[T] setter 追加で解決できること

```moonbit
pub(all) struct Opt[T] {
  // ... 既存フィールド ...
  setter : (T) -> Unit  // NEW
}
```

- **clone**: save/commit/read/restore パターンが可能に
  - ただし Array[T] 型は参照コピーの問題が残る（Clone トレイト必要）
- **adjust after_post**: `(opt.setter)((filter.run)((opt.getter)()))`
- **adjust before_pre**: ノード差し替えと組み合わせ

setter 追加は API の小さな拡張だが、内部設計には影響が大きいため慎重に検討する。

> **2026-03-14 更新**: DR-043 で `priv setter` として実装済み。clone / adjust の実装解禁が可能。
