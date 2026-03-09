# DR-037: alias / proxy プリミティブ設計 — name・aliases・単一ダッシュの統合整理

## 背景

「単一ダッシュロングオプション（`-Xcc` 等）未対応」を設計課題として挙げていたが、
議論の結果、これは独立した問題ではなく **name / aliases の設計上の偽の区別** に起因する
表層的な制約であることが判明した。

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

## 解決策

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

**`alias` は target の `Ref[T]` を共有する別エントリ。** 純粋な別名であり、
行動の違いはない。

### proxy: 介入可能なラッパーコンビネータ

行動の違い（deprecated 警告、使用検知、変換等）が必要な場合は `proxy` を使う。

```moonbit
let verbose = p.flag(name="verbose")
let old = p.proxy("--old-verbose", verbose, deprecated="Use --verbose")
```

proxy は Ref を直接共有するのではなく、委譲パターンで介入ポイントを持つ:

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

| 概念 | 役割 | 実装 |
|------|------|------|
| `alias(name, target)` | 基本プリミティブ。target の Ref を共有する別エントリ | ExactNode + Ref 共有 |
| `proxy(name, target, deprecated=...)` | 介入可能ラッパー。行動の違いがあるもの | ExactNode + 委譲 + was_set |
| `aliases=["x","y"]` パラメータ | alias のシュガー | 内部で alias() に展開 |
| `name` パラメータ | 表示ラベル（+ デフォルト alias 生成） | ヘルプ・エラー用 |

## 解消される設計課題

- ~~単一ダッシュロングオプション未対応~~ → alias で任意名登録可能
- ~~aliases に区別がつけられない~~ → proxy で deprecated 等を表現
- name / aliases の偽の区別 → alias プリミティブに統一

## 未決事項

- `proxy` の具体的な API シグネチャ（deprecated 以外にどんな介入が必要か）
- `alias` が `Opt[T]` を返すか `Unit` を返すか（get する必要があるか）
- positional alias の実用的なユースケースの検証
- `aliases` シュガーで `"--"` 自動付加を残すか、呼び出し側が明示するか
