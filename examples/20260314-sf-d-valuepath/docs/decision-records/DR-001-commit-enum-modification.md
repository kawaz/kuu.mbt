# DR-001: Commit[T] enum の設計変更

## 問題

ユーザースケッチの `Commit[T]` enum:
```
enum Commit[T] {
  Exist(() -> T)      // フラグ的。存在したらTを返す
  Value((T) -> T)     // 変換的。現在の値を受け取って新しい値を返す
}
```

`Value((T) -> T)` は「現在の値を変換する」設計だが、CLI引数文字列の注入経路が不明確:
- `--name foo` の場合、`T=String` なら `Value(fn(current) { ??? })` — "foo" を受け取れない
- `--count 5` の場合、`T=Int` なら入力も Int でなければならないが CLI 引数は String

## 発見経緯

PoC 実装フェーズ1（型定義）で Commit[T] を実際にパースロジックに組み込もうとした際に発覚。

## 解決策

`Value((T) -> T)` を `Value((String) -> T)` に変更:
```moonbit
enum Commit[T] {
  Exist(() -> T)          // フラグ: 存在したらTを返す
  Value((String) -> T)    // 値: CLI文字列からTを生成
}
```

## 選択理由

- CLI引数は常に String 型。String → T 変換はパース層の責務
- `(T) -> T` だと count パターン（`fn(n) { n + 1 }`）には使えるが、String → Int 変換が入る value パターンに対応できない
- `(String) -> T` にすれば flag 以外の全パターンに統一的に対応可能

## R2 追記: Value の戻り値を (T, String?) に拡張

`abort()` を排除するため、`Value((String) -> T)` を `Value((String) -> (T, String?))` に変更。
`String?` が `None` なら成功、`Some(msg)` ならエラー。これにより `on_match` の型が `(String) -> String?` に統一され、エラーが `vp_parse` の `Result` として伝搬される。

## 残課題

- count パターン（`-v -v -v`）は `vp_count` ヘルパーで `PathEntry` を直接構築。`Commit[T]` では表現しきれない（現在値への参照が必要なため）
- 元スケッチの `(T) -> T` が意図していた「現在値の変換」パターンは、`Accumulate((T) -> T)` のような3つ目のバリアントで対応可能だが、このPoC の範囲では見送り
