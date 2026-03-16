# DR-018: dashdash / append_dashdash + stop_before 設計

type: decision

## 背景

DR-017 で `--` セパレータを greedy ExactNode 化した。この発展として、`--` を汎用コンビネータとして設計し、複数グループ化・カスタムセパレータ・greedy 系の停止条件を統一的に扱う。

## dashdash コンビネータ

### 基本形

```
p.dashdash()        // separator = "--"（POSIX デフォルト）
p.dashdash("⭐")    // カスタムセパレータ
```

dashdash は sugar。内部で `serial(exact(sep), p_opts)` を構築する。
- 現在のスコープの P リスト（positional opts）を取得
- セパレータ検出後、残りの args を P で serial に消費
- P が終端したら consumed=N で Accept して復帰
- 結果型: P の serial の結果型

### append_dashdash — 複数グループ版

```
p.append_dashdash()      // separator = "--"
p.append_dashdash("⭐")  // カスタムセパレータ
```

内部で `append(serial(exact(sep), p_opts), stop_before=[self])` を構築する。
- 自身のセパレータは暗黙に stop_before に含まれる（自己参照の隠蔽）
- 結果型: `Array[P の serial の結果型]`
- rest の結果を先頭グループとして含む

### 例

```
rest = append(str())
dd = append_dashdash("--")
app = cmd("app", [rest, dd])

app ccc -- hoge fuga -- aaa -- bbb
→ rest.val() = [ccc]
→ dd.val() = [[ccc], [hoge, fuga], [aaa], [bbb]]
```

dashdash の commit 時に rest.val() を読んで先頭に unshift。dashdash が解決される時点で rest の処理は必ず終了済み。

## stop_before — greedy 系の停止条件

greedy な positional（rest, dashdash 等）の消費ループを停止させる条件。

### 概要

「このリストの opt が Accept する引数の手前で止まる」パラメータ。opt リスト（ExactNode のリスト）で指定する。

```
dd = dashdash("--")
rest = append(str(), stop_before=[dd])   # dd が食える引数は自分は食わない
```

### 判定は opt リスト（文字列ではない）

```
// OK: opt で判定（型情報を使える）
rest = append(str(), stop_before=[dd])

// NG: 文字列だと ExactNode しか対応できない
rest = append(str(), exclude=["--"])  // int() 等に対応できない
```

### 名前の選定

- `exclude`: 何を除外するか曖昧。exclusion コンビネータとの混同も懸念
- `yield_to`: 意図が不明確
- `stop_before`（仮採用）: 「消費ループをここで止める」という動作がそのまま名前に

### append_dashdash の暗黙 stop_before

```
dashdash()                          // stop_before=[]
dashdash(stop_before=[...])         // stop_before=[...]

append_dashdash()                   // stop_before=[self]（暗黙）
append_dashdash(stop_before=[...])  // stop_before=[self, ...]（self は常に暗黙）
```

append_dashdash は自身のセパレータを stop_before に暗黙に含める。
追加で他の opt を指定する場合は stop_before パラメータで追加分のみ渡す。

## dashdash は sugar

dashdash / append_dashdash はあくまで sugar。パーツとしては:

- `exact(sep)` — セパレータトークン
- `serial(...)` — P の serial 消費
- `append(...)` — 複数回の蓄積
- `stop_before` — greedy 消費の停止条件

ユーザーが必要に応じてこれらを組み合わせて独自のセパレータパターンを構築できる。

## 議論ログ

### P 終端復帰の発見

parse_raw の `--` 特殊分岐を ExactNode 化する議論中に発見。separator の ExactNode が P を greedy に消費し、P が終端したら Accept(consumed=N) で復帰する。force_positional のようなパーサ全体の状態変更が不要。

### 複数 `--` パターン

mv の例: `mv -f -- -f dest -- f1 f2 d3 dest2`
- P = serial(Append(PATH, require=true), DIR) の場合
- 1個目の `--` グループ: PATH=[-f], DIR=[dest] → serial 終端 → 復帰
- 2個目の `--` グループ: PATH=[f1,f2,d3], DIR=[dest2]
- `-- dest` のみでは PATH=[dest] で DIR がないため ParseError

### rest と dashdash の関係

- rest.val() は従来通り独立して使える（cobra 方式）
- dashdash.val() は全グループを含む Array を返す（先頭に rest 結果）
- rest と dashdash は独立した opt。dashdash が rest を「読む」だけで「書く」ことはしない
- ExactNode 分割では Ref[T] 共有で元の opt.val() が正しく取得できる（clonedOpt のコミット伝搬は不要）

### セパレータは任意文字列

`--` は POSIX の慣習だが、仕組み上は任意の文字列を指定可能。
デフォルトは `--`（省略可能な位置パラメータ）。

## 実装状況

### 実装済み

- `Parser::dashdash(separator?="--")` → `Opt[Array[String]]`: セパレータ以降の全 args を収集
- `Parser::append_dashdash(separator?="--")` → `Opt[Array[Array[String]]]`: セパレータで区切った複数グループを収集
- `Parser::new(dashdash?=true)` / `cmd(dashdash?=true)`: デフォルトで install_separator_node を初期化時に登録。dashdash()/append_dashdash() を使う場合は `dashdash=false` にする
- カスタムセパレータ対応
- append_dashdash の self-stop（自身のセパレータで自動グループ分割）

### 設計のみ（未実装）

- `stop_before` パラメータ: dashdash/append_dashdash/rest への汎用停止条件。現在は append_dashdash が自身のセパレータで自動停止する実装のみ
- rest の結果を先頭グループとして含む動作: dashdash の commit 時に rest.val() を unshift する設計。現在は rest と dashdash は完全に独立した opt
- `serial(exact(sep), p_opts)` による positional serial 消費: 現在の dashdash は単純に全残り args を Array に収集する実装

### 設計と実装の差分

設計では dashdash を `serial(exact(sep), p_opts)` の sugar として位置付けているが、実装は positional 管理を介さず直接 args を収集するシンプルな方式。P 終端復帰や positional serial 消費は install_separator_node（デフォルトの POSIX `--` 処理）が担う。ユーザー向けコンビネータは直接的な Array 収集で十分なユースケースをカバーする。
