---
type: decision
---

# DR-042: struct-first DX 層設計 — Parseable trait + apply_fn 方式

## ステータス: 採択

## 背景

### 核心的洞察

> アプリ作者はみんな、値を渡したいんじゃなくて値を受け取りたいんだよ。つまりアプリが必ず先にある。
> そして欲しいデータの型完全な struct も実は必ずアプリ作者側が持ってるんだよ既に。

現行 kuu（ボトムアップ）: パーサ定義 → `Opt[T]` → `.get().unwrap()` で手動取り出し。
新発想（トップダウン）: アプリの struct が先 → パーサがそこに値を直接注入 → 取り出し問題が構造的に消滅。

### 位置づけ

```
Layer 4: DX API ← ここ（MoonBit 用 struct-first）
Layer 3: KuuCore（JSON往復隠蔽）
Layer 2: WASM bridge
Layer 1: kuu core（ExactNode パースエンジン）
```

パッケージ: `src/dx/` として提供。core は無改造。依存方向: `dx → core` の一方向。

## 5方式の並列 PoC 検証

5つのアプローチを別ワークスペースで並列に検証した。

| PoC | ワークスペース | テスト | 概要 |
|---|---|---|---|
| A. Closure Setter | struct-first-a-closure | 20 PASS | mut struct + setter クロージャ |
| B. Ref 共有 | struct-first-b-ref | 33 PASS | `target=` 構文で Ref[T] 共有 |
| **C. Trait** | **struct-first-c-trait** | **10 PASS** | **Parseable trait + FieldRegistry** |
| D. ValuePath | struct-first-d-valuepath | 10 PASS | Commit[T] enum + 独自パーサ |
| E. FieldRef+Binder | struct-first-e-fieldref | 22 PASS | Lens パターン + クロージャ型消去 |

### 比較評価

| 評価軸 | A. Closure | B. Ref | **C. Trait** | D. ValuePath | E. FieldRef |
|---|---|---|---|---|---|
| struct 純粋性 | △ mut | ✗ Ref混入 | **◎ plain mut** | △ Ref | ◎ immutable |
| 記述の簡潔さ | ○ | ◎ target= | **◎ 宣言的** | ○ | △ FieldRef手書き |
| サブコマンド | △ raw混合 | ○ | **◎ 自然なネスト** | △ 手動2段 | 未検証 |
| kuu core 活用 | ◎ 無改造 | ◎ 無改造 | **◎ 無改造** | ✗ 独自パーサ | ◎ 無改造 |
| アクセス | self.x | self.x.val | **self.x** | self.x.val | immutable |

### 横断的な発見

全5方式に共通する知見:

1. **MoonBit の struct は参照型** — クロージャキャプチャで mut フィールド書き換えが確実に動く。全 PoC の土台
2. **型消去はクロージャで解決** — kuu core の ExactNode と全く同じパターン。MoonBit ではジェネリック trait が使えないため、クロージャ束縛が王道
3. **derive マクロがない** — 全 PoC でボイラープレートが残る最大の原因。MoonBit に derive が来たら C (Trait) 方式が圧勝する

## 採択: C. Trait ベース（Parseable trait + apply_fn）

### コア API

```moonbit
pub(open) trait Parseable {
  register(Self, FieldRegistry) -> Unit
}

pub fn parse_into[T : Parseable](args : Array[String], target : T) -> Unit!ParseError

pub struct FieldRegistry {
  parser : @core.Parser
  appliers : Array[() -> Unit]
}
```

### 利用例

```moonbit
struct AppConfig {
  mut verbose : Bool
  mut name : String
  mut count : Int
} derive(Default)

impl Parseable for AppConfig with register(self, reg) {
  reg.flag(name="verbose", apply_fn=fn(v) { self.verbose = v })
  reg.string(name="name", apply_fn=fn(v) { self.name = v })
  reg.int(name="count", apply_fn=fn(v) { self.count = v })
}

fn main {
  let config = AppConfig::default()
  parse_into!(args, config)
  // config.verbose, config.name, config.count が直接使える
}
```

### FieldRegistry メソッド（kuu core 全コンビネータ対応）

- `flag`, `string`, `int`, `count` — 基本型
- `append_string`, `append_int` — 配列型
- `positional`, `rest` — 位置引数
- `sub(name~, setup~, on_match?~)`, `require_cmd` — サブコマンド
- `custom[T]`, `set_description` — 汎用・メタ
- 各メソッドに `shorts~`, `description~`, `global~` 等のオプション引数

### 2フェーズ実行（エラー安全）

1. **登録フェーズ**: `register()` で kuu core コンビネータを呼び、`Opt[T]` をクロージャでキャプチャして appliers に蓄積
2. **適用フェーズ**: パース成功時のみ `apply_all()` で全 applier を実行し struct に値注入

パース失敗時は applier が実行されないため、struct は初期状態のまま保たれる。

## 不採択理由

### B. Ref 共有 — target= 構文の簡潔さは魅力だが

`target=self.verbose` と書くだけで登録できる簡潔さは優れているが:

- struct に `Ref[T]` が混入し、値型としての純粋性が失われる
- アクセスが常に `.val` 経由になり、使用箇所の DX が低下
- MoonBit にプロパティアクセスの委譲機構（Kotlin `by`、Swift `@propertyWrapper`）がないため透過化不可能
- `#alias("_[_]")` 等のインデックスアクセスエイリアスもプロパティアクセスには適用不可

**登録は1回、アクセスは何度も** → トータル DX では `mut` + `apply_fn` が勝つ。

### A. Closure Setter — トップレベルは良いがサブコマンドで崩壊

サブコマンドの登録で kuu core の raw API が露出し、DX の統一性が失われる。

### D. ValuePath — kuu core を活用していない

独自パーサを構築しており、kuu core のコンビネータ資産を活用できない。

### E. FieldRef+Binder — 最も厳密だが重い

Lens パターンは理論的に美しいが、FieldRef の手書きが重く実用的ではない。
フラグ（値なしオプション）や `--key=value` 形式も未対応。

## apply_fn のボイラープレートについて

`apply_fn=fn(v) { self.field = v }` は完全に機械的なパターン。

```
型 → メソッド名のマッピング:
  Bool          → reg.flag(...)
  String        → reg.string(...)
  Int           → reg.int(...)
  Array[String] → reg.append_string(...)
```

### 将来の自動化パス

1. **コード生成ツール**: struct 定義 + doc comment からの `impl Parseable` 自動生成（`go:generate` 方式）
2. **カスタム derive**: MoonBit が将来サポートすれば `derive(Parseable)` で完全自動化

どちらの場合も、現在の `apply_fn` 設計はそのまま内部実装として使える。手書きから自動生成への移行が自然に行える設計。

## MoonBit 言語機能の確認事項

| 機能 | 可否 | 備考 |
|---|---|---|
| mut struct + クロージャキャプチャ | ✅ | struct は参照型。apply_fn の基盤 |
| struct update syntax `{ ..s, field: v }` | ✅ | immutable 方式の候補だったが mut で十分 |
| Trait object `&Trait` | ✅ | 型消去に利用可能 |
| ジェネリック trait `trait Foo[T]` | ❌ | Parse error。クロージャ束縛で回避 |
| カスタム derive | ❌ | 組み込み8種のみ。将来に期待 |
| `Ref[T]` | ✅ | B 方式で使用。C では不要 |
| `derive(Default)` | ✅ | struct 初期化に利用 |
| `pub(open) trait` | ✅ | 外部パッケージからの impl 可能 |
| `#alias("_[_]=_")` | ✅ | インデックスアクセス用。プロパティ委譲には使えない |

## 設計判断まとめ

| 判断 | 選択 | 理由 |
|---|---|---|
| mut vs Ref | mut 推奨 | struct が純粋値型のまま、`.val` 不要 |
| apply_fn vs target= | apply_fn | Ref 不要、登録1回 vs アクセス多数 |
| パッケージ | src/dx/ | core 無改造の原則 |
| Trait 名 | Parseable | 直感的、将来 derive 対象 |
| サブコマンド | 再帰 setup | C PoC の実証済みパターン |
| エラー安全 | 2フェーズ | パース失敗時 apply 未実行 |
| 透過アクセス | 不可能と確認 | MoonBit に property delegate なし |

## B+C ハイブリッドの可能性

B の `target=` 構文と C の `Parseable` trait は組み合わせ可能。`Parseable` trait の register 内で `reg.flag(name="verbose", target=config.verbose)` のように B のバインド構文を使えば、`Ref[T]` の代償を受け入れた上で記述を最小化できる。

ただし上記の通り「登録は1回、アクセスは何度も」の原則から、mut + apply_fn をデフォルトとし、B スタイルは opt-in の alternative API として提供するのが適切。
