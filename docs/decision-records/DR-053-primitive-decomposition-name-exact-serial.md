# DR-053: プリミティブ分解 — name/exact/serial/or によるオプション構造の一般化

## 背景

現在の kuu のコンビネータ（string_opt, int_opt 等）は「名前マッチ + 値消費」を一体で管理している。例えば `string_opt(name="port", value_name="PORT")` は `--port <PORT>` を生成するが、これは本質的に2つのプリミティブの合成:

```
serial(exact("--port"), string("PORT"))
```

value_name は「1引数のシュガー」にすぎない。この分解を進めれば、現在表現できない複合値パターンが自然に表現できる。

## 動機: 複合値パターン

```
--color <NAME> | <R> <G> <B>
```

現在の kuu ではこのパターンを1つのオプションとして定義できない。分解すれば:

```
serial(
  exact("--color", name("color")),
  or(
    name="COLOR",
    [
      str("NAME"),
      serial(
        int(name="R"),
        int(name="G"),
        int(name="B"),
      )
    ]
  )
)
```

## プリミティブの整理

### exact(pattern)
- 引数文字列と完全一致するトークンを1つ消費
- 現在の ExactNode の名前マッチ部分に相当

### name(name)
- 単独では何にもマッチしない（consumed=0）
- メタ情報（名前）を付与するだけの存在
- exact と link されると「名前付きオプショングループ」を形成
- 複数の exact を1つの name にリンクすることで、複数ロングオプション名の共有が可能

### serial(...)
- 子プリミティブを順に消費
- 現在の「名前 + 値」の暗黙的 serial を明示化

### or(...)
- 子パターンのいずれかにマッチ（最長一致）
- 現在の make_or_node に相当
- name を付けられる（ヘルプ表示で段を分ける等に活用）

### 値プリミティブ: str(name), int(name), ...
- FilterChain ベースの値消費
- 位置引数と同じ仕組み

## 現在のコンビネータとの関係

現在の Sugar 層コンビネータは、このプリミティブの組み合わせのシュガー:

| Sugar | 分解 |
|---|---|
| `flag(name="verbose")` | `exact("--verbose", name("verbose"))` |
| `string_opt(name="port", value_name="PORT")` | `serial(exact("--port", name("port")), str("PORT"))` |
| `int_opt(name="count", default=0)` | `serial(exact("--count", name("count")), int("COUNT"))` |
| `count(name="verbose")` | `exact("--verbose", name("verbose"))` （値なし、出現回数カウント） |
| `positional(name="FILE")` | `str("FILE")` （名前なしオプション） |

## コンテナへの名前付与

serial, or 等のコンテナにも名前を付けられる:

```
or(
  name="COLOR",     // このグループ全体の名前
  [str("NAME"), serial(int("R"), int("G"), int("B"))]
)
```

名前は任意（付けなくてもよい）。付けた場合:
- ヘルプ表示で `--color COLOR` + `COLOR: NAME | R G B` のように段を分けて表示可能
- エラーメッセージで `"invalid value for COLOR"` のようにグループ名を参照可能

## 現時点の位置づけ

この分解は kuu の設計の根幹に関わる。現在の ExactNode + 投機実行モデルとの整合性を慎重に検討する必要がある。

**即座に実装する必要はない。** 現在の Sugar 層コンビネータは引き続き有用であり、このプリミティブ分解は「内部実装の一般化」として段階的に進められる。

## 検討事項

- ExactNode の try_reduce シグネチャとの整合性
- serial/or の入れ子が投機実行モデルに自然に載るか
- name コンビネータの consumed=0 が OC/P フェーズで問題にならないか
- ヘルプ生成への影響（現在の OptMeta ベースの生成との互換性）
