# DR-037: alias / proxy プリミティブ設計 — 機能分解と統合整理

## 背景

「単一ダッシュロングオプション（`-Xcc` 等）未対応」を設計課題として挙げていたが、
議論の結果、これは独立した問題ではなく **name / aliases の設計上の偽の区別** に起因する
表層的な制約であることが判明した。

さらに alias / proxy / variation / long / short を機能分解した結果、
少数のプリミティブ（exact, clone, link, or）で全てが合成可能であることがわかった。

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

## 解決策: プリミティブ分解

### 基本プリミティブ

```
exact(name)           -- 文字列完全一致ノード（ExactNode の核）
clone(opt, name)      -- opt の構造コピー（新しい name、新しい Ref、フィルタは共有）
link(opt, val_source) -- opt.val_ref = val_source.val_ref（Ref 共有）
or([opts])            -- 最長一致（既存の make_or_node）
```

### 合成コンビネータ

```
alias(opt, name) = link(clone(opt, name), val_source=opt)
  // clone で独立ノード作り、link で値を共有

aliases(opt, names) = or(names.map(n => alias(opt, n)))
  // 複数別名の一括展開。既存の aliases パラメータのシュガー

proxy(opt, name, deprecated?, ...) = alias + 介入フック
  // alias と同様だが commit を wrap して副作用（警告等）を差し込める
```

### alias: 汎用プリミティブコンビネータ

`alias` を opt / cmd / positional を問わず使える **Ref 共有コンビネータ** として導入する。

```moonbit
// オプションの別名
let verbose = p.flag(name="verbose")
p.alias("--verb", verbose)

// サブコマンドの別名
let status = p.cmd(name="status", setup~)
p.alias("st", status)

// positional（後勝ちパターン等、汎用的に使える）
p.serial(setup=fn(sub) {
  let file1 = sub.positional(name="file1")
  let file2 = sub.positional(name="file2")
  sub.alias(file1)  // 3番目の positional → file1 の Ref に上書き
})
```

**`alias` = clone + link。** target の構造をコピーし、値の書き込み先を target の Ref に統合する。

### proxy: 介入可能なラッパーコンビネータ

行動の違い（deprecated 警告、使用検知、変換等）が必要な場合は `proxy` を使う。

```moonbit
let verbose = p.flag(name="verbose")
let old = p.proxy("--old-verbose", verbose, deprecated="Use --verbose")
```

proxy は alias と同様に Ref を共有するが、commit を wrap して介入ポイントを持つ:

- `--old-verbose` 使用時: `old.is_set=true`, `verbose.is_set=true`（+ deprecated 警告）
- `--verbose` 使用時: `old.is_set=false`, `verbose.is_set=true`

### aliases パラメータ: alias のシュガー

既存の `aliases: Array[String]` は内部で `alias()` に展開するシュガーとして残す。

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

## long / short / variation の分解

### long の構築

```
long(base, variations) = or([
  require_prefix(base, "--"),              // --name
  ...variations.map(v =>
    variation(require_prefix(base, "--{v.prefix}-"), v)
  )                                         // --no-name, --toggle-name 等
])
```

`require_prefix(opt, prefix)` は opt の pre フィルタにプレフィックスチェックを合成する。
`"--"` 付加はこのプリミティブで実現され、暗黙変換が消える。

### variation の再定義

Variation を「alias + フィルタ合成」として再定義する。
clone して pre/post/accum を variation 固有の振る舞いで wrap する:

```
variation(opt, v) = alias(opt) + フィルタ合成
  // clone して振る舞いを差し替え
```

各 Variation の振る舞い:
- Toggle → `accum = fn(cur) { !cur }`
- True → `accum = fn(_) { true }`
- False → `accum = fn(_) { false }`
- Reset → `accum = fn(_) { default }`
- Unset → `accum = fn(_) { default }` + `was_set = false`

### short の構築

```
short(base, char) = require_prefix(clone(base), "-{char}")
shorts(base, chars) = chars.map(c => short(base, c))
```

結合ショート（`-abc` → `-a -b -c`）と値吸着（`-Xcc` → `-X` + `cc`）は
per-node ではなく **tokenizer 層** の横断的関心事として分離される。

```
tokenizer 層（横断的）:
  - short_combine: -abc → [-a, -b, -c] or [-a, bc(value)]
  - eq_split: --foo=bar → [--foo, bar]

node 層（per-node）:
  - exact, clone, link, or, require_prefix, variation
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

### 問題

clone はフィルタ（pre/post/accum）の振る舞いもコピーしたい。
しかし FilterChain はクロージャであり、内部状態（Ref 等）をキャプチャしていると
clone 間で状態が漏洩する。

### 解決: フィルタは pure であること

kuu の設計原則として **フィルタ（pre/post/accum）は純粋関数** とする。

- 値の状態管理は `Ref[T]` で行う（clone 時に新規作成、link で明示的に共有）
- フィルタは入力から出力への変換のみ。内部状態を持たない
- clone はフィルタのクロージャ参照をそのまま共有しても安全

この制約は DR-027（core は純粋関数）の自然な帰結でもある。

### 現状の整合性

現在のビルトインフィルタ（string parse, int parse, choices validation, trim, one_of 等）は
全て pure。状態を持つのは:
- `Ref[T]` (値セル) → clone 時に新規作成、link で明示的に共有
- `was_set` (使用検知) → per-node で新規作成
- `pending` (reducer 用) → per-node で新規作成

フィルタ自体が状態を持つケースは存在しない。

### 将来的な型レベルマーキング（検討）

必要になった場合、FilterChain を Pure/Stateful でマーキングする:

```moonbit
enum Filter[A, B] {
  Pure((A) -> B raise ParseError)       // clone 安全
  Stateful((A) -> B raise ParseError)   // clone 時にエラー
}
```

現時点では制約として文書化し、Pure をデフォルトとする。
Stateful な振る舞いが必要な場合は reducer/accumulator パターンに誘導する。

## 循環参照ガード

alias / proxy は target の Ref chain を辿る。循環参照が発生すると無限ループになる。

基本的な alias（target が既に存在する必要がある）では直接循環は構造的に起きにくいが、
custom reducer、append、グループ化等でユーザーが自由に Ref を触れる以上、
間接的なループ経路は予測しきれない。

**登録時に target chain を辿り、循環を検出して ParseError にする:**

```
alias(A, B)
  B の chain: B → C → D → 終端  ✓
  B の chain: B → C → A → 循環  ✗ ParseError("circular alias")
```

深さ制限による打ち切りでもよい。

## 設計の全体像

### プリミティブ

| プリミティブ | 役割 |
|-------------|------|
| `exact(name)` | 文字列完全一致ノード |
| `clone(opt, name)` | 構造コピー（新 Ref、フィルタ参照共有） |
| `link(opt, val_source)` | Ref 共有（値の書き込み先を統合） |
| `or([opts])` | 最長一致統合（既存 make_or_node） |

### 合成コンビネータ

| コンビネータ | 定義 | 用途 |
|-------------|------|------|
| `alias(opt, name)` | clone + link | 汎用別名（opt/cmd/positional 問わず） |
| `proxy(opt, name, ...)` | alias + 介入フック | deprecated 警告、使用検知 |
| `variation(opt, v)` | alias + フィルタ合成 | --no-xxx, --toggle-xxx 等 |
| `require_prefix(opt, p)` | pre フィルタ合成 | `"--"` / `"-"` 付加 |

### シュガー

| シュガー | 展開先 |
|---------|--------|
| `aliases=["x","y"]` | `alias("x", opt)`, `alias("y", opt)` |
| `shorts="vV"` | `short(opt, 'v')`, `short(opt, 'V')` |
| `variation_toggle="no"` | `variations.push(Toggle("no"))` |

### 層構造

```
tokenizer 層:  short_combine, eq_split（横断的前処理）
node 層:       exact, clone, link, or, require_prefix, variation（per-node）
convention 層: alias, proxy, long, short（合成パターン）
sugar 層:      flag, string_opt, cmd 等（ユーザー API）
```

## 解消される設計課題

- ~~単一ダッシュロングオプション未対応~~ → alias で任意名登録可能
- ~~aliases に区別がつけられない~~ → proxy で deprecated 等を表現
- ~~name / aliases の偽の区別~~ → alias プリミティブに統一

## 未決事項

- `proxy` の具体的な API シグネチャ（deprecated 以外にどんな介入が必要か）
- `alias` が `Opt[T]` を返すか `Unit` を返すか（get する必要があるか）
- positional alias の実用的なユースケースの検証
- `aliases` シュガーで `"--"` 自動付加を残すか、呼び出し側が明示するか
- tokenizer 層と node 層の境界の詳細設計
- Pure/Stateful の型レベルマーキングの要否判断
