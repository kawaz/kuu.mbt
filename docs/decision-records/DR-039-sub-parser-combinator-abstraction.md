# DR-039: サブパーサコンビネータの抽象化

## 背景

`install_eq_split_node`（`--foo=bar` の `=` 分割）と `install_short_combine_node`（`-abc` の結合ショート分解）は、構造的に同じパターンを持つ：

1. 引数を引っ掛ける（pre: 正規表現的フィルタ）
2. 引数を分解してサブパーサに食わせる（ArgsGenerator + sub_parse）
3. 結果を外の世界向けに調整する（ResultToResult）

これを一般化された共通パーツに分解できないか、という検討。

## 設計

### 全体構造

```
sub_parser_combinator(
  pre_filter: (String) -> String?,    // 引っ掛け + 前処理（slice等）
  args_generator: ArgsGenerator,       // 分解パターン生成
  sub_opts: Lazy[Array[Opt]],          // サブパーサのオプション群
  result_handler: ResultToResult       // 結果の判断・調整
)
```

### ArgsGenerator — 分解パターンの遅延生成

全パターンの2次元配列を事前生成するのは無駄が多い。イテレータ/ジェネレータで遅延生成する。

2段構え：
- **外側**: chunk のどこで分割するかを変えながら、内側ジェネレータを生成する
- **内側**: sub_parse の消費に応じて次の引数を供給する（対話的）

```
enum ArgsGenerator {
  S((String) -> Iter[String])           // 1つの分割パターンの引数供給
  A((String) -> Iter[ArgsGenerator])    // 分割位置を変えながら S を生成
}
```

ショート結合の場合：
- 外側は分割位置をずらしながら内側ジェネレータを生成
- 内側は StringView で 1文字ずつ切り出して yield
- chunk 内を使い切ったら外側の次の引数からも取れる
- 外側の引数も尽きたら終了

### ResultToResult — ストリーミング判定

```
type ResultToResult = fn(TryResult?) -> TryResult?
```

- `cur = Some(result)`: sub_parse 1回分の結果
- `cur = None`: 全パターン試行完了
- 戻り値 `Some(result)`: break（決定）
- 戻り値 `None`: continue（次のパターンへ）
- 全てのコールで None → 最終的に Reject

状態（結果の蓄積等）が必要ならクロージャでキャプチャすればよく、インターフェース自体は最小限に保つ。

#### 判定パターン

| パターン | 動作 |
|---|---|
| find-first（short用） | cur=Accept → 即 Some(Accept(consumed調整)) |
| best-of-all | cur来る間は None → cur=None で蓄積した中から最良を選択 |
| early-abort | cur=Error → 即 Some(Error) |

### 具体例: ショート結合

```
short = sub_parser_combinator(
  pre_filter: fn(arg) {
    // /^-\S+$/ にマッチしたら先頭の - を除去
    if arg.starts_with("-") && !arg.starts_with("--") { Some(arg.slice(1)) } else { None }
  },
  args_generator: ArgsGenerator::A(fn(chunk) {
    // chunk を1文字ずつ分割位置をずらしながら引数ジェネレータを生成
    // 各ジェネレータは sub_parse の消費に応じて次の1文字を切り出す
  }),
  sub_opts: Lazy(fn() { collect_short_opts_in_scope() }),
  result_handler: fn(cur) {
    match cur {
      Some(Accept(consumed)) => Some(Accept(adjust_consumed(...)))
      _ => None
    }
  }
)
```

### 具体例: eq_split

```
eq_split = sub_parser_combinator(
  pre_filter: fn(arg) {
    // --foo=bar → ("--foo", "bar") に分割。= がなければ None
    if let Some(idx) = arg.index_of("=") { Some(arg) } else { None }
  },
  args_generator: ArgsGenerator::S(fn(arg) {
    // = で分割した ["--foo", "bar"] を yield するだけ（1パターンのみ）
  }),
  sub_opts: Lazy(fn() { collect_long_opts_in_scope() }),
  result_handler: fn(cur) {
    match cur {
      Some(Accept(_)) => Some(Accept(consumed=1))  // 元は1引数
      _ => None
    }
  }
)
```

## kuu の設計優位性（関連メモ）

この抽象化は `-` を特別視しない kuu の設計と直交する。他のパーサが専用の仕組みで対処する問題を、kuu は汎用パーツの組み合わせで解決できる：

- **optional arg + サブコマンド衝突**: ExactNode 走査 + implicit_value で3値パターンが自然に表現できる。clap の `require_equals` ワークアラウンドが不要
- **負数値 `--num -1`**: `-` を特別視しないため、int_opt の値として自然に消費される。`allow_negative_numbers` が不要

## ステータス

設計構想段階。実装時に詳細を詰める。
