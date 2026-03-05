# DR-015: 投機実行モデルによる高度な引数パターン対応

kuu の try_reduce 投機実行 + 最長一致モデルが、他の汎用パーサでは対応困難な引数パターンを自然に処理できるポテンシャルを持つことの記録。

参考: docs/research/cli-argument-edge-cases.md（CLI引数エッジケース調査）

## 核心

各 ExactNode の reducer が自分の消費可能性を自己判定（Accept/Reject/Error）できるため、ショートオプション結合の分解も消費ループの再帰適用として表現可能。**型情報（reducer）が分解の判断材料になる**点が他のパーサにない強み。

## 対応可能なパターン

### 1. ショートオプション結合 + 値付き混在

`-aboArg` → `-a -b -o Arg`

先頭 `-` を剥がして1文字ずつ消費。各ショートの reducer が判定:
- flag → 1文字消費、Accept
- value_opt → 残り文字列を値として try_reduce、Accept(consumed=残り全部)

最後のショートのみ値を取る POSIX GL5/GL6 パターンだけでなく、kuu では reducer の判定により柔軟な組み合わせが可能。

### 2. 型情報による高度な結合分解

`-cA1gcc` → `-c -A 1 -g -c -c` → c=3(count) A=1(int) g(flag)

各ショートの reducer が型を知っている:
- `c` → count のショート → 1文字消費
- `A` → int_opt のショート → 後続 "1" を数値パースして消費
- `g` → flag のショート → 1文字消費
- `c`, `c` → count → 各1文字消費

int_opt の reducer が「次の文字列を数値パースできるか」を自己判定するため、どこまでが値でどこからが次のフラグかを自動決定できる。

### 3. `-vA1B1` パターン

`-vA1B1` → `-v -A 1 -B 1`

調査では「標準パーサでは動作しない」とされたが、kuu では:
- `v` → flag → 1文字消費
- `A` → int_opt → 後続 "1" を消費（"1B1" の先頭を int パース → "1" で成功）
- `B` → int_opt → 後続 "1" を消費
- 全消費成功

reducer が int/regex 等のバリデータを持つため、値の境界を型情報から判定可能。

### 4. 数値引数パターン

`kill -9` / `kill -TERM`

同スコープの positional の reducer が判定:
- int positional → `-9` を int パース → 成功なら Accept
- string positional + regex → `-TERM` を `^[A-Z]+$` マッチ → Accept

ショートオプションとの曖昧さがなければ（同スコープに `-9` にマッチするショートがなければ）自然に処理できる。

### 5. bundling（ロングオプション混在）

Go の `go test -v -run TestFoo -count 3` 的な、ショートとロングの混在。
同階層のショートとのコンフリクト（曖昧さ）がなければ共存可能。判断不能な場合は ParseError(ambiguous)。

## 実装方針

ショートオプション結合の分解は、消費ループ内（またはスコープ認識局所分解）で:

1. `-` で始まり `--` でない引数を検出
2. 先頭 `-` を剥がして文字列を取得
3. 1文字ずつ、そのスコープのショートオプション候補に try_reduce
4. flag → 1文字消費して次の文字へ
5. value_opt → 残り文字列を値として try_reduce。成功なら全消費。失敗なら次の引数を値として消費
6. 全文字消費成功 → 各 commit を順に実行
7. 途中で Reject → 分解失敗。元の引数を丸ごと処理（positional 等）
8. 曖昧 → ParseError

### 前提条件

- 各コンビネータが `short` パラメータで登録済み（DR なし、実装済み）
- reducer が型情報を持つ（既存設計）
- pre-validation / post-validation がある程度実装されると、さらに柔軟な判定が可能

## 曖昧さの処理

投機実行モデルの利点: 曖昧な場合は既存の仕組みで自然に処理される。

- 複数の分解パターンが成立 → 最長一致で勝者決定
- 最長一致が複数 → ParseError(ambiguous)
- 全パターン失敗 → Reject → positional 等にフォールバック

## 将来の拡張

reducer に pre-validation（消費前の型チェック）や post-validation（消費後の検証）が実装されれば、より精密な分解判定が可能になる。例:

- regex バリデータ付き positional → `kill -TERM` の `-TERM` を `^[A-Z]+$` で判定
- range バリデータ付き int → `nice -20` の `-20` を `-20..19` で判定
