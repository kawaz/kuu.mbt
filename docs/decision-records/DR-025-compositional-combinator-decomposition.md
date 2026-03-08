# DR-025: コンビネータの Compositional 分解

現在の6コンビネータ（flag, string_opt, int_opt, count, append_string, append_int）は
内部的に exact/serial/or/custom のプリミティブで構成されているが、ユーザー API としては
モノリシックなコンビネータとして公開されている。

これを明示的な compositional API として分解する方向性を記録する。
現時点では未実装であり、将来の設計課題として位置づける。

## プリミティブ

| プリミティブ | 役割 | 現在の対応 |
|---|---|---|
| `custom(parser)` | 値パース。本質的には Positional 的（文字列→T） | make_value_node の on_match 部分 |
| `exact(literal)` | リテラル文字列マッチ（consumed=1） | make_flag_node |
| `serial([...])` | 複数パーサを直列に適用 | make_value_node（exact + custom の直列） |
| `or([...])` | 子の最長一致で Accept | make_or_node |
| `option(name, ...)` | --name 展開 + variation + kind=Option メタデータ付与 | expand_and_register |

## 分解例

```
int_opt(name="port", default=8080, variation_reset="no")
→ option(name="port", parser=parse_int, variation_reset="no")
→ or([
    serial(name="port", kind=Option, [exact("--port"), custom(parser=parse_int)]),
    exact("--no-port", name="port", kind=Option, reset処理),
  ], name="port", kind=Option)
→ 最終的には生の reducer ツリー
```

```
flag(name="color", variation_false="disable")
→ or([
    custom(name="color", parser=fn(s){ if s=="--color" { Accept(consumed=1, ...) } else { Reject } }, kind=Option),
    (--disable-color の variation ノード),
  ])
```

```
append(string_opt("tag"))
→ accumulator を replace から push に差し替える合成
```

## コンテナノードの metadata

or や serial などのコンテナ系コンビネータも自分自身が `name`, `kind=Option` の情報を持つべき。
これにより子を走査せずにヘルプ構築等が可能になる。

## 課題

### 1. variation の reset 処理

`exact("--no-port")` が cell を default に戻すには cell/was_set への
参照が必要。compositional にするなら `ctx` 的なパラメータが必要だが、具体的な API は未設計。

### 2. flag と option の統合

flag は consumed=1（値引数なし）、option は consumed=2（値引数あり）で
軸が異なる。似た処理の重複は避けたいが、無理に統合すると複雑になる可能性。

### 3. append の合成

`append(string_opt(...))` は accumulator を外から注入する形が自然だが、
型安全に合成する API の設計が必要。

### 4. 現アーキテクチャからの距離

現在の ExactNode ベースのフラット走査から reducer ツリーへの
移行は大きな変更。段階的な移行パスが必要。

## 現在の内部対応関係

現在の実装は既にこの分解に近い構造を持っている:

- `make_flag_node` = exact
- `make_value_node` = serial(exact, custom)
- `make_or_node` = or
- `expand_and_register` = option

差分はユーザー API として公開するかどうか。

## 位置づけ

DR-024 の Variation 再設計を先に完了させ、その後のフェーズで compositional 分解を検討する。
custom コンビネータの位置づけは DR-024 §8 にも記載済み。
