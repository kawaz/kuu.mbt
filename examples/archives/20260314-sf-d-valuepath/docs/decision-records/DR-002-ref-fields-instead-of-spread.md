# DR-002: Ref フィールドによる struct update 代替

## 問題

ユーザースケッチの ValuePath では `apply: (S, T) -> S` で functional update を想定:
```moonbit
ValuePath {
  pattern: "--verbose",
  commit: Exist(fn() { true }),
  apply: fn(s, v) { { ..s, verbose: v } },  // spread syntax
}
```

MoonBit には `{ ..s, field: v }` のような spread/functional update syntax が存在しない。

## 発見経緯

MoonBit 型システム調査フェーズで判明。kuu core のコードベースを確認した際、全ての struct 構築が全フィールド明示指定であることを確認。

## 解決策

struct のフィールドを `Ref[T]` にして、ミュータブルに値を注入:

```moonbit
struct DockerConfig {
  verbose : Ref[Int]
  debug : Ref[Bool]
  // ...
}

// PathEntry は Ref を直接キャプチャして書き込む
fn vp_flag(name : String, target : Ref[Bool]) -> PathEntry {
  PathEntry::{ name, needs_value: false, on_match: fn(_) { target.val = true } }
}
```

## 選択理由

- `apply: (S, T) -> S` 方式は全フィールド列挙が必要で、フィールド追加時に全 ValuePath の apply を修正しなければならない
- Ref 方式なら PathEntry が対象フィールドのみを知ればよく、疎結合
- kuu core 自体も `Ref[T]` で値を保持する方式（Opt[T] 内部）

## トレードオフ

- Ref 方式は struct が mutable になる（functional purity を失う）
- パース結果が暗黙に共有される可能性（同じ Ref を複数 PathEntry が参照できる）
  - ただしこれは count パターンなど意図的な共有にも使える
