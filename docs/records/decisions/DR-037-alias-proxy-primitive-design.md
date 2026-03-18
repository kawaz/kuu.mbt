---
type: decision
---

# DR-037: alias プリミティブ設計 — 直交プリミティブによる統合整理

## 背景

「単一ダッシュロングオプション（`-Xcc` 等）未対応」を設計課題として挙げていたが、
議論の結果、これは独立した問題ではなく **name / aliases の設計上の偽の区別** に起因する
表層的な制約であることが判明した。

さらに alias / variation / long / short を機能分解した結果、
3 つの直交プリミティブ（clone, link, adjust）で全てが合成可能であることがわかった。

## 問題

### 1. `--` プレフィックスの暗黙付加

`expand_and_register` が `name` と `aliases` に一律 `"--"` を付加する:

```moonbit
let long_nodes = make_long_nodes("--" + name)
for alt in aliases {
  let alt_nodes = make_long_nodes("--" + alt)
}
```

このため `-Xcc` のような単一ダッシュ名を登録できない。

### 2. name と aliases の偽の区別

内部処理上、`name` と `aliases` は全く同じ — どちらも ExactNode を生成して `self.nodes` に push するだけ。
`name` に特権はない。にもかかわらず API 上は別パラメータとして存在し、
`name` だけが必須で `aliases` は補助的という印象を与える。

### 3. aliases に区別がつけられない

`aliases: Array[String]` では全エイリアスが等価。
deprecated な旧名を残したい場合（`--old-name` → `--new-name`）に
警告を出す・使用を検知するといった区別ができない。

### 4. Variation が long 専用概念になっている

現在の Variation（Toggle/True/False/Reset/Unset）は `--{prefix}-{name}` 形式の
long option に特化している。しかし「振る舞いを変えた別名」は long に限らない汎用概念。

## 解決策: 3 つの直交プリミティブ

### 基本プリミティブ

```
clone(opt, name)      -- アイデンティティ: opt の構造コピー（新 name、新 Ref、フィルタ参照共有）
link(opt, val_source) -- 値: opt.val_ref = val_source.val_ref（Ref 共有）
adjust(opt,           -- 振る舞い: フィルタチェーンの前後に挿入
  before_pre?, after_pre?,
  before_post?, after_post?,
  before_accum?, after_accum?)
```

各プリミティブが管理する関心事:

| プリミティブ | 関心事 | 説明 |
|-------------|--------|------|
| `clone` | アイデンティティ | 新しい名前、新しい Ref を持つ独立コピー |
| `link` | 値 | 書き込み先の Ref を別の opt と共有 |
| `adjust` | 振る舞い | pre/post/accum フィルタの前後にフィルタを挿入 |

3 つは完全に直交する。どの組み合わせも意味を持つ。

### 合成パターン

| パターン | 式 | アイデンティティ | 値 | 振る舞い |
|---------|-----|:---:|:---:|:---:|
| alias | `link(clone(opt, name), opt)` | 新 | 共有 | 同じ |
| variation | `adjust(alias(opt, name), ...)` | 新 | 共有 | 変更 |
| derived | `adjust(clone(opt, name), ...)` | 新 | 独立 | 変更 |
| stricter | `adjust(opt, after_post=...)` | 同一 | 同一 | 変更 |
| deprecated | `adjust(alias(opt, name), before_accum=record_deprecated)` | 新 | 共有 | 記録追加 |

### alias: 汎用別名コンビネータ

`alias` = `link(clone(opt, name), opt)` — clone で独立ノードを作り、link で値を共有する。

opt / cmd / positional を問わず使える。返り値は `Opt[T]`（値は target と共有、is_set は独立）。

```moonbit
// オプションの別名
let verbose = p.flag(name="verbose")
let verb = p.alias("--verb", verbose)

// サブコマンドの別名（子パーサの setup を共有）
let status = p.cmd(name="status", setup~)
let st = p.alias("st", status)

// positional（後勝ちパターン等、汎用的に使える）
p.serial(setup=fn(sub) {
  let file1 = sub.positional(name="file1")
  let file2 = sub.positional(name="file2")
  sub.alias(file1)  // 3番目の positional → file1 の Ref に上書き
})
```

### adjust: 振る舞い調整コンビネータ

フィルタチェーンの前後にフィルタを挿入する。alias なしで単独使用も可能:

```moonbit
// 既存 opt に検証を追加
let stricter = p.adjust(port, after_post=Filter::validate(fn(v) {
  if v > 1024 { () } else { raise parse_error("port must be > 1024") }
}))

// clone して独立した派生を作る
let derived = p.adjust(p.clone(opt, "new-opt"), before_pre=some_transform)
```

### variation = alias + adjust

Variation を「alias + adjust」として再定義する。LongVariation（Toggle/True/False/Reset/Unset）は
adjust の引数プリセット定数でしかない:

```
variation(opt, name, v) = adjust(alias(opt, name), ...v.adjustments)

// LongVariation プリセット
Toggle = { before_accum = fn(cur) { !cur } }
True   = { before_accum = fn(_) { true } }
False  = { before_accum = fn(_) { false } }
Reset  = { before_accum = fn(_) { default } }
Unset  = { before_accum = fn(_) { default }, was_set_override = false }
```

Variation は long に閉じない。任意の名前パターンに対して振る舞い変更を適用できる汎用概念になる。

### deprecated = adjust（記録パターン）

deprecated は独立コンビネータではなく、adjust の一パターン。
トップパーサのスコープに deprecated 記録ストレージを持たせ、
adjust の before_accum で使用記録を収集する:

```
deprecated(opt, name, msg) = adjust(alias(opt, name),
  before_accum = fn(ctx) {
    parser.record_deprecated(opt, msg)  // ストレージに記録
    ctx  // ReduceAction はそのまま通す
  }
)
```

パース中は記録のみ、副作用なし。パース後に呼び出し側が deprecated 記録を確認して警告表示する:

```moonbit
let verbose = p.flag(name="verbose")
let old = p.deprecated("--old-verbose", verbose, msg="Use --verbose")

let result = try! p.parse(args)
// パース後: deprecated 記録を確認
for entry in p.deprecated_warnings() {
  eprintln("warning: " + entry.name + " is deprecated. " + entry.msg)
}
```

proxy という概念は不要。deprecated は adjust のプリセット + パーサの記録ストレージ。

### aliases パラメータ: alias のシュガー

既存の `aliases: Array[String]` は内部で `alias()` に展開するシュガーとして残す。
`aliases` シュガーは `"--"` 自動付加を維持（既存互換）、`p.alias()` は生文字列。

```moonbit
// これは
p.flag(name="verbose", aliases=["verb"])

// 内部的にこうなる
let verbose = p.flag(name="verbose")
p.alias("--verb", verbose)
```

### name パラメータの役割変更

`name` はヘルプ表示・エラーメッセージ用の **表示ラベル** に限定。
トリガーとしてのオプション名は `aliases`（→ alias 展開）と `shorts` で指定。
`name` 自体もデフォルトで `"--" + name` として alias 展開される（既存互換）。

### 単一ダッシュロングオプション

特殊対応不要。`aliases` に `"-Xcc"` を含めるか、`alias("-Xcc", opt)` するだけ:

```moonbit
let compiler = p.string_opt(name="compiler", aliases=["-Xcc"], default="")
// -Xcc は OC フェーズで ExactNode として普通にマッチする
```

ExactNode のマッチングは `args[pos] == name` の単純比較なので、
プレフィックスに関係なく任意の文字列がトリガーになる。

short combining との干渉: `-Xcc` は combine node の対象になるが、
`-X` ショートが未登録なら Reject → ExactNode 側が勝つ。
両方登録されていれば ambiguous error（正しい挙動）。

## long / short の分解

### long の構築

```
long(base, variations) = or([
  require_prefix(base, "--"),              // --name
  ...variations.map(v =>
    variation(base, "--{v.prefix}-{name}", v)
  )                                         // --no-name, --toggle-name 等
])
```

### short の構築

```
short(base, char) = require_prefix(clone(base), "-{char}")
shorts(base, chars) = chars.map(c => short(base, c))
```

結合ショート（`-abc` → `-a -b -c`）と値吸着（`-Xcc` → `-X` + `cc`）は
per-node ではなく **tokenizer 層** の横断的関心事。

```
tokenizer 層（横断的）:  short_combine, eq_split
node 層（per-node）:     exact, clone, link, adjust, or
```

### 最終合体

```
option(name, shorts, variations) = {
  base = exact(name)
  l = long(base, variations)
  s = shorts(base, chars)       // short 版は base の clone
  link(s, val_source=l)         // short → long の Ref に合流
  or([l, ...s])                 // OC で最長一致
}
```

## clone とフィルタの純粋性制約

### 制約: フィルタは pure であること

kuu の設計原則として **フィルタ（pre/post/accum）は純粋関数** とする。

- 値の状態管理は `Ref[T]` で行う（clone 時に新規作成、link で明示的に共有）
- フィルタは入力から出力への変換のみ。内部状態を持たない
- clone はフィルタのクロージャ参照をそのまま共有しても安全

この制約は DR-027（core は純粋関数）の自然な帰結。

### 現状の整合性

現在のビルトインフィルタ（string parse, int parse, choices validation, trim, one_of 等）は
全て pure。状態を持つのは Ref[T] / was_set / pending のみで、全て per-node。

### 将来的な型レベルマーキング（検討）

必要になった場合、FilterChain を Pure/Stateful でマーキングする。
現時点では制約として文書化し、Stateful な振る舞いは reducer/accumulator に誘導する。

## 循環参照ガード

alias は target の Ref chain を辿る。循環参照が発生すると無限ループになる。

基本的な alias（target が既に存在する必要がある）では直接循環は構造的に起きにくいが、
custom reducer、append、グループ化等でユーザーが自由に Ref を触れる以上、
間接的なループ経路は予測しきれない。

**登録時に target chain を辿り、循環を検出して ParseError にする。**

## 設計判断の記録

### alias の返り値: Opt[T]

alias は `Opt[T]` を返す。値は target と共有するが is_set は独立。
alias 側の使用検知も可能。

### aliases シュガーの `"--"` 自動付加: 維持

`aliases=["verb"]` → `"--verb"` の既存挙動を維持。
`p.alias("-Xcc", opt)` は生文字列。2つの API で挙動が異なるが、
シュガー（ロングオプション名の略記）とプリミティブ（任意文字列）の位置づけの違いとして自然。

### deprecated: adjust パターン + パーサ記録ストレージ

独立コンビネータ（proxy）ではなく、adjust の before_accum で使用を記録し、
パーサのストレージに蓄積する方式。パース中は副作用なし、パース後に確認・警告。

### cmd alias: 初回スコープに含める

opt と cmd の両方で alias を使えるようにする。
cmd の場合は clone ではなく同一 setup の共有で実現。

## 設計の全体像

### 直交プリミティブ

| プリミティブ | 関心事 | 役割 |
|-------------|--------|------|
| `clone(opt, name)` | アイデンティティ | 構造コピー（新 Ref、フィルタ参照共有） |
| `link(opt, val_source)` | 値 | Ref 共有（書き込み先を統合） |
| `adjust(opt, ...)` | 振る舞い | フィルタチェーンの前後に挿入 |

補助: `exact(name)` — 文字列完全一致ノード、`or([opts])` — 最長一致統合（既存）

### 合成コンビネータ

| コンビネータ | 定義 | 用途 |
|-------------|------|------|
| `alias(opt, name)` | link(clone(opt, name), opt) | 汎用別名（opt/cmd/positional 問わず） |
| `adjust(opt, ...)` | フィルタ挿入 | 振る舞い変更（alias なしでも単独使用可） |
| `variation(opt, name, v)` | adjust(alias(opt, name), ...) | 振る舞い変更付き別名 |
| `deprecated(opt, name, msg)` | adjust(alias(...), before_accum=record) | 非推奨別名（記録パターン） |

### 合成パターンの直交性

| パターン | 式 | アイデンティティ | 値 | 振る舞い |
|---------|-----|:---:|:---:|:---:|
| alias | `link(clone(opt, name), opt)` | 新 | 共有 | 同じ |
| variation | `adjust(alias(opt, name), ...)` | 新 | 共有 | 変更 |
| derived | `adjust(clone(opt, name), ...)` | 新 | 独立 | 変更 |
| stricter | `adjust(opt, after_post=...)` | 同一 | 同一 | 変更 |
| deprecated | `adjust(alias(opt, name), before_accum=record)` | 新 | 共有 | 記録追加 |

### シュガー

| シュガー | 展開先 |
|---------|--------|
| `aliases=["x","y"]` | `alias("--x", opt)`, `alias("--y", opt)` |
| `shorts="vV"` | `short(opt, 'v')`, `short(opt, 'V')` |
| `variation_toggle="no"` | `variations.push(Toggle("no"))` |

### 層構造

```
tokenizer 層:  short_combine, eq_split（横断的前処理）
node 層:       exact, clone, link, adjust, or（per-node プリミティブ）
convention 層: alias, variation, deprecated, long, short（合成パターン）
sugar 層:      flag, string_opt, cmd 等（ユーザー API）
```

## 解消される設計課題

- ~~単一ダッシュロングオプション未対応~~ → alias で任意名登録可能
- ~~aliases に区別がつけられない~~ → adjust + deprecated パターンで表現
- ~~name / aliases の偽の区別~~ → alias プリミティブに統一
- ~~Variation が long 専用~~ → adjust プリミティブにより汎用化
- ~~proxy が独立概念~~ → adjust に吸収。deprecated は adjust のプリセット

## 未決事項

- positional alias の実用的なユースケースの検証
- tokenizer 層と node 層の境界の詳細設計
- Pure/Stateful の型レベルマーキングの要否判断
- adjust の before/after の型シグネチャ詳細
- deprecated 記録ストレージの Parser 上の具体的な構造
