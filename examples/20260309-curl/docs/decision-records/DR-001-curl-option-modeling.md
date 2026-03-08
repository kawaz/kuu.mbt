# DR-001: curl オプションのモデリング判断

## --no-buffer の扱い

### 問題
curl の `--no-buffer` (`-N`) は「バッファリングを無効にする」オプションで、`--buffer` という肯定形は存在しない。
kuu の `variation_false` は既存フラグの否定形を生成する機能なので、肯定形がないオプションには使えない。

### 解決策
`flag(name="no-buffer", shorts="N")` として単純なフラグで定義。

### 選択理由
- `flag(name="buffer", default=true, variation_false=Some("no"))` だと `-N` が `--buffer`（有効化）のショートになってしまい、curl の仕様と逆になる
- 名前に "no-" を含むのは不自然だが、curl の仕様通りで混乱がない
- kuu の variation ショートオプション対応は将来課題として記録

## タイムアウト値の型選択

### 問題
`--connect-timeout` と `--max-time` は実際の curl では小数値（秒）を受け付ける。
kuu に float_opt は存在しない。

### 解決策
string_opt として定義し、値の解釈はアプリ側に委ねる。

### 選択理由
- int_opt にすると小数が指定できない
- custom[T] + Filter::parse_float() でも実現可能だが、このデモの目的は引数パースの検証であり、値の変換は検証対象外
- string_opt は最も柔軟で、将来 float_opt が追加されても移行容易

## max-redirs のデフォルト値表示

### 問題
`max-redirs` は `default=50` で定義。パース後の表示で、未指定でも `50` と表示される。

### 解決策
print_int ヘルパーが非ゼロ値のみ表示する設計のため、デフォルト50が表示される。
これは意図的な動作。ユーザーが明示的に指定したかは `is_set()` で区別可能。
