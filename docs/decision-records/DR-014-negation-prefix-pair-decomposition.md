---
type: decision
---

> **注意**: この DR は DR-024（コンビネータパラメータ共通化）の Variation enum で置き換え済み。2軸分解（negate × prefix_pair）は採用されず、1軸の Variation リストに統合された。

# DR-014: 否定パターンとプレフィックスペアの2軸分解

旧 `FlagInversion` enum を廃止し、否定パターンとプレフィックスペアの2つの直交した機能に分解する。

## 経緯

現行実装は `--no-{name}` を全コンビネータでハードコード生成している（`Reset("no")` 相当）。
`--enable-/--disable-`、`--with-/--without-` 等のパターンや、否定を生成しない選択肢が必要。

## 議論ログ

### ユーザー発言

> そもそも --no- が必要かどうか、ちなみに no パターンの場合の挙動自体も None(--no-を生成しない) / Not("no") / Reset("no") の3種類の挙動が選択できて良さそう。InvertはTがBool限定。Resetはinitial()リセットよね。noじゃなくてNot("not")とかNot("toggle")とかに差し替えも可能。Reset("reset")みたいにもできる。
> 反転展開パターンが必要かどうか、None/TrueFalse(t:String?,f:String?) を受け取るコンピネータで。("enable","disable") とか ("with","without") みたいにキーワード自体を tuple で取れるようにしとくとユーザが好きにできる口にもなって面白い気がする。

> 多分この分解は正しい気がするので設計書にはちゃんと記載して、でもやること自体はコンビネータのユーティリティ関数を作りつつ、ユーザはそれは直接使う必要なくてoptの初期化パラメータ内のnamedParameterで個別指定するインターフェースって感じかな？metaとして持つ必要はなさそうですね最初にExactNodeに分解して終わり。

## 設計決定

### 2軸分解

旧設計の `FlagInversion` enum（`No` / `EnableDisable` / `Custom(String, String)`）を廃止。
以下の2つの直交した機能に分解する:

#### 軸1: 否定パターン（negate）

`--no-{name}` 相当のノード生成を制御。

| 値 | 生成 | 挙動 |
|---|---|---|
| `None` | 生成しない | - |
| `Not(prefix)` | `--{prefix}-{name}` | Bool: 反転。非Bool: エラー |
| `Reset(prefix)` | `--{prefix}-{name}` | initial 値にリセット（型不問） |

prefix は差し替え可能: `Not("no")`, `Not("not")`, `Not("toggle")`, `Reset("reset")` 等。

#### 軸2: プレフィックスペア（prefix_pair）

`--enable-{name}` / `--disable-{name}` 相当のノード生成を制御。

| 値 | 生成 | 挙動 |
|---|---|---|
| `None` | 生成しない | - |
| `TrueFalse(t, f)` | 指定されたもののみ | 強制セット |

`t` / `f` は `String?` で片方のみ指定可能:
- `("enable", "disable")` → 両方生成
- `(Some("enable"), None)` → `--enable-{name}` のみ
- `(None, Some("disable"))` → `--disable-{name}` のみ

### 組み合わせ例

| negate | prefix_pair | initial | 生成されるノード |
|--------|-------------|---------|-----------------|
| `Reset("no")` | `None` | false | `--name`, `--no-name` |
| `None` | `("enable","disable")` | false | `--enable-name`, `--disable-name` |
| `Not("no")` | `("enable","disable")` | false | `--name`, `--no-name`, `--enable-name`, `--disable-name` |
| `None` | `(Some("enable"), None)` | false | `--enable-name` |
| `Reset("reset")` | `(None, Some("disable"))` | true | `--name`, `--reset-name`, `--disable-name` |

### ユーザー API

コンビネータの named parameter として指定。内部のユーティリティ関数で ExactNode に展開。

```moonbit
// デフォルト: negate=Reset("no"), prefix_pair=None（現行動作と同じ）
p.flag(name="verbose")
// --verbose, --no-verbose

// 否定なし
p.flag(name="verbose", negate=None)
// --verbose のみ

// enable/disable パターン
p.flag(name="color", negate=None, prefix_pair=("enable", "disable"))
// --enable-color, --disable-color

// 両方
p.flag(name="color", negate=Reset("no"), prefix_pair=("with", "without"))
// --color, --no-color, --with-color, --without-color
```

### meta に持たない

negate / prefix_pair はコンビネータの Convention レイヤーで処理され、ExactNode に展開されて終わり。
OptMeta には含めない（旧 `inversion` フィールドは廃止）。

## 選択理由

- 2つの直交した概念を1つの enum に押し込めていた旧設計を分解
- ユーザーがプレフィックスを自由にカスタマイズ可能
- ExactNode 展開で完結するため、消費ループに影響なし（4層アーキテクチャの Convention レイヤーの責務）
- meta に持つ必要がない（展開後は完全一致マッチの ExactNode として動作）

## 不採用としたもの

- 旧 `FlagInversion` enum の維持 — 2つの直交した機能が1つの型に混在し、組み合わせの表現力が不足
