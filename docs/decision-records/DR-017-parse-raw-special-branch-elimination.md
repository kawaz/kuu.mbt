# DR-017: parse_raw 特殊分岐の ExactNode 化

type: decision

parse_raw のメインループから特殊分岐を排除し、全ての引数処理を ExactNode の投機実行ループに統一する。

## 背景

DR-016 で install_short_combine_node により短縮結合の特殊分岐を廃止した。同じパターンで残り2つの特殊分岐も ExactNode 化できる:

1. `--name=value` 分解（eq_split）
2. `--` セパレータ（force_positional）

## 変更 1: `--name=value` 分解の ExactNode 化

### Before

parse_raw 内で `--` 始まりの引数に `=` があれば split して各ノードの try_reduce に渡す汎用ロジック。

### After

install_short_combine_node と同じ「install 時に内在パーサ ExactNode を追加する」パターン。

`install_eq_split_node()` で:
- `--` 始まりかつ `needs_value=true` の全ノードを収集
- `=` を含む `--` 引数を検出 → split → 元ノードの try_reduce に委譲する ExactNode を1つ追加
- consumed を 1 に正規化（元の try_reduce は consumed=2 を返すが、実際の args は1つ）

parse_raw の eq_split ロジックが丸ごと削除される。

## 変更 2: `--` セパレータの greedy ExactNode 化

### Before

parse_raw 冒頭の `if args[pos] == "--"` で `force_positional` フラグを立て、以降の ExactNode マッチングをスキップして全引数を positional に流す。

問題点:
- パーサ全体の状態を汚す（`force_positional` フィールド）
- `--` は1回きりで復帰不可
- parse_raw に特殊分岐が必要

### After

`--` を greedy な ExactNode として構築。reducer は:
1. `--` を検出
2. 残りの args を self.positionals で serial に消費
3. P が全部終端（serial 完了 or Reject）したら Accept(consumed=N) で復帰

P が終端すれば自然に復帰するため、`force_positional` が不要になる。

### 復帰の例: `mv -f -- -f dest -- f1 f2 d3 dest2`

P = serial(Append(PATH), DIR) の場合:

```
1. -f → O マッチ (flag)
2. -- → separator が greedy に残りを P で消費
   → -f を PATH、dest を DIR → serial 終端 → consumed=3 で Accept して復帰
3. -- → separator が再度発火
   → f1, f2, d3 を PATH、dest2 を DIR → consumed=5 で Accept
```

通常のパーサでは `--` は1回きりのスイッチだが、kuu では P 終端で自然に復帰するため複数回の `--` が動作する。

### セパレータは `--` に限定されない

`--` は慣習的なセパレータだが、仕組み上は任意の文字列を指定できる。将来的に `separator("⭐")` のようなコンビネータで任意のセパレータを定義可能。

## 結果

parse_raw は「全ノードに try_reduce → 最長一致 → commit or positional フォールバック」だけの純粋なループになる。特殊分岐ゼロ。

## 実装上の注意

### force_positional の除去

- `rest` コンビネータの handler が `force_positional.val` を参照していたが、不要になった
- rest は「何でも受け取る」positional にする。`--` 始まりかどうかのフィルタは parse_raw のループ順序（ExactNode 優先 → positional フォールバック）で制御される
- separator の ExactNode が `--` 以降を全部（P 終端まで）消費して返すため、parse_raw 側の状態管理は不要

### positional の current_positional 管理

- separator の commit 内で `current_positional` を適切に更新する
- 投機実行の原則: commit 前に状態を変えない
