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

## 残課題

- count パターン（`-v -v -v` で verbose カウント）は `Value((String) -> T)` では表現しにくい
  - 現在は `vp_count` ヘルパーで `on_match` クロージャ内で直接実装
  - 3つ目のバリアント `Accumulate((T) -> T)` の追加を検討中
- 元スケッチの `(T) -> T` の意図を完全に汲み取れていない可能性あり
