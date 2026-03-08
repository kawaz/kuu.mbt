# kuu Rust API 設計書

## 概要

kuu の MoonBit core エンジンを WASM FFI 経由で利用し、Rust のイディオムに沿った型安全な CLI パーサ API を提供する。
derive マクロによる宣言的定義と、サブコマンドの enum ディスパッチにより、ボイラープレートを最小化する。

---

## 設計思想

### 1. 宣言的定義: struct + derive

CLI の引数定義は `#[derive(Args)]` を付けた struct のフィールドで表現する。
各フィールドの属性 (`#[kuu(...)]`) で core API のパラメータを指定する。

**core の問題点を解決する:**
- `get().unwrap()` の繰り返し → required は `T`、optional は `Option<T>` に直接マップ
- `match result.child("xxx")` によるディスパッチ → `#[derive(Subcommand)]` enum で型安全に

### 2. 型が意味を持つ

フィールドの Rust 型から core API の呼び出しを自動推論する:

| Rust 型 | core API | 備考 |
|---|---|---|
| `bool` | `flag()` | |
| `String` | `string_opt()` | |
| `i64` | `int_opt()` | |
| `Vec<String>` | `append_string()` | |
| `Vec<i64>` | `append_int()` | |
| `Vec<String>` + `#[kuu(rest)]` | `rest()` | 位置引数の残り全部 |
| `Vec<String>` + `#[kuu(dashdash)]` | `dashdash()` | `--` 以降 |
| `Option<T>` | optional | `required` 制約なし、`None` で未指定 |
| `T` (非Option) | required | 自動的に `required()` 制約追加 |

### 3. サブコマンドは enum

`#[derive(Subcommand)]` を付けた enum のバリアントがサブコマンドになる。
ネスト（remote add/remove）は enum のバリアントにさらに `#[derive(Subcommand)]` enum を持たせることで表現する。

### 4. core の強みを活かす

- **フィルタチェイン**: `#[kuu(filter = "trim | non_empty")]` で後処理パイプラインを宣言的に記述
- **バリエーション**: `#[kuu(variation_false = "no")]` で `--no-xxx` 自動生成
- **exclusive**: `#[kuu(exclusive_group = "X")]` でグループ指定
- **count**: `#[kuu(count)]` で `-vvv` → 3
- **implicit_value**: `#[kuu(implicit_value = "always")]` で `--color` → `"always"`
- **choices**: `#[kuu(choices = ["a", "b", "c"])]` で選択肢制限

---

## derive マクロ属性一覧

### コンテナ属性 (`#[kuu(...)]` on struct/enum)

| 属性 | 型 | 説明 |
|---|---|---|
| `description = "..."` | `&str` | コマンド説明 |
| `require_cmd` | flag | サブコマンド必須（enum に対して） |

### フィールド属性 (`#[kuu(...)]` on field)

| 属性 | 型 | 説明 | 対応 core API |
|---|---|---|---|
| `name = "..."` | `&str` | オプション名（省略時はフィールド名、`_` → `-`） | 全 API の `name` |
| `short = 'x'` | `char` | ショートオプション | `short` |
| `long = "..."` | `&str` | ロングオプション名（name のエイリアス） | `aliases` |
| `aliases = ["..."]` | `[&str]` | 追加エイリアス | `aliases` |
| `description = "..."` | `&str` | ヘルプ文 | `description` |
| `value_name = "..."` | `&str` | ヘルプ中の値プレースホルダ | `value_name` |
| `default = ...` | リテラル | デフォルト値 | `default` |
| `default_fn = "..."` | `&str` (関数パス) | デフォルト値の遅延計算 | `default_fn` |
| `global` | flag | 全サブコマンドに伝播 | `global` |
| `hidden` | flag | ヘルプ非表示 | `hidden` |
| `count` | flag | 出現回数カウント（`i64` フィールド） | `count()` |
| `positional` | flag | 位置引数 | `positional()` |
| `rest` | flag | 残余位置引数（`Vec<String>` フィールド） | `rest()` |
| `dashdash` | flag | `--` 以降の引数 | `dashdash()` |
| `choices = [...]` | `[&str]` | 選択肢制限 | `choices` |
| `implicit_value = ...` | リテラル | 値なし指定時の暗黙値 | `implicit_value` |
| `filter = "..."` | `&str` | フィルタチェイン式 | `post` (FilterChain) |
| `exclusive_group = "..."` | `&str` | 排他グループ名 | `exclusive()` |
| `required` | flag | 必須フラグ（`Option<T>` でも強制必須にする場合） | `required()` |
| `variation_toggle = "..."` | `&str` | `--{p}-{name}` でトグル | `variation_toggle` |
| `variation_true = "..."` | `&str` | `--{p}-{name}` で true | `variation_true` |
| `variation_false = "..."` | `&str` | `--{p}-{name}` で false | `variation_false` |
| `variation_reset = "..."` | `&str` | `--{p}-{name}` でデフォルトに戻す | `variation_reset` |
| `variation_unset = "..."` | `&str` | `--{p}-{name}` で未設定に戻す | `variation_unset` |

### サブコマンド属性 (`#[kuu(...)]` on enum variant)

| 属性 | 型 | 説明 |
|---|---|---|
| `name = "..."` | `&str` | サブコマンド名（省略時はバリアント名を kebab-case） |
| `description = "..."` | `&str` | サブコマンド説明 |
| `dashdash = false` | `bool` | `--` セパレータ自動登録を無効化 |

---

## フィルタ式

`filter` 属性にはパイプ (`|`) 区切りでフィルタを連結して指定する。
core の `FilterChain::then()` に対応。

```
#[kuu(filter = "trim | non_empty")]
#[kuu(filter = "trim | one_of(a, b, c)")]
#[kuu(filter = "in_range(1, 100)")]
```

### 利用可能なフィルタ

| フィルタ | 引数 | 説明 |
|---|---|---|
| `trim` | なし | 前後の空白を除去 |
| `to_lower` | なし | 小文字化 |
| `non_empty` | なし | 空文字列を拒否 |
| `one_of(a, b, ...)` | 値リスト | 許可値チェック |
| `in_range(min, max)` | 数値2つ | 範囲チェック |

---

## 型マッピング詳細

### 基本型

```
bool                → flag(name, default=false)
bool + default=true → flag(name, default=true)
String              → string_opt(name, default="")
i64                 → int_opt(name, default=0)
```

### コレクション型

```
Vec<String>                 → append_string(name)
Vec<i64>                    → append_int(name)
Vec<String> + #[kuu(rest)]  → rest(name)
Vec<String> + #[kuu(dashdash)] → dashdash()
```

### Optional / Required

```
Option<String>  → string_opt, required 制約なし (None = 未指定)
String          → string_opt + required() 制約自動付与
Option<bool>    → flag, is_set() で判定
bool            → flag (default=false なので required 不要)
```

**位置引数の場合:**
```
#[kuu(positional)]
url: String           → positional(name="url") + required()

#[kuu(positional)]
directory: Option<String>  → positional(name="directory")  // optional
```

### enum → choices

`#[derive(KuuValue)]` を付けた enum で choices を自動生成:

```rust
#[derive(KuuValue)]
enum ColorWhen {
    Always,
    Never,
    Auto,
}
// → choices = ["always", "never", "auto"]
```

---

## core API 対応表

| Rust API | core API |
|---|---|
| `#[derive(Args)]` struct | `Parser::new()` + 各フィールドの定義呼び出し |
| `#[derive(Subcommand)]` enum | `Parser::sub()` × バリアント数 |
| `bool` field | `Parser::flag()` |
| `String` field | `Parser::string_opt()` |
| `i64` field | `Parser::int_opt()` |
| `i64` + `#[kuu(count)]` | `Parser::count()` |
| `Vec<String>` field | `Parser::append_string()` |
| `Vec<i64>` field | `Parser::append_int()` |
| `#[kuu(positional)]` | `Parser::positional()` |
| `#[kuu(rest)]` | `Parser::rest()` |
| `#[kuu(dashdash)]` | `Parser::dashdash()` |
| `#[kuu(exclusive_group)]` | `Parser::exclusive()` |
| non-Option 型 (positional/string_opt) | `Parser::required()` 自動付与 |
| `#[kuu(filter = "...")]` | `FilterChain` 構築 → `post` パラメータ |
| `#[kuu(require_cmd)]` on enum | `Parser::require_cmd()` |
| `#[kuu(variation_false = "no")]` | `variation_false` パラメータ |
| `#[derive(KuuValue)]` enum | `choices` パラメータ自動生成 |

---

## serial パターン

core の `serial()` は複数の位置引数を順序付きで定義する機能。
Rust API では struct のフィールド順がそのまま serial の順序になる:

```rust
#[derive(Args)]
#[kuu(serial)]
struct RemoteAddArgs {
    #[kuu(positional, description = "Remote name")]
    name: String,

    #[kuu(positional, description = "Remote URL")]
    url: String,
}
```

`#[kuu(serial)]` がコンテナに付いている場合、全 positional フィールドを `serial()` でラップし、
最後に `never()` を自動追加する（serial の仕様に合わせて）。

---

## エラーハンドリング

```rust
pub enum KuuError {
    /// パースエラー（メッセージ + ヘルプテキスト）
    ParseError { message: String, help_text: String },
    /// ヘルプ表示リクエスト（--help）
    HelpRequested(String),
}

// KuuError は std::process::Termination を実装し、
// main() から直接返せる
fn main() -> Result<(), KuuError> {
    let args = Mygit::parse()?;
    // ...
    Ok(())
}
```

core の `ParseError::HelpRequested` と `ParseError::ParseError` に対応。

---

## パース実行

### エントリポイント

```rust
// std::env::args() から自動取得
let args = Mygit::parse()?;

// 明示的に引数を渡す（テスト用）
let args = Mygit::parse_from(["mygit", "clone", "--depth", "1", "url"])?;
```

### サブコマンドのディスパッチ

```rust
match args.command {
    Command::Clone(c) => { /* c.url, c.depth, ... */ }
    Command::Commit(c) => { /* c.message, c.all, ... */ }
    // ...
}
```

ネストの場合:
```rust
Command::Remote(r) => match r.command {
    RemoteCommand::Add(a) => { /* a.name, a.url */ }
    RemoteCommand::Remove(r) => { /* r.name */ }
}
```

---

## 設計判断

### clap との差異

| 観点 | clap | kuu-rs |
|---|---|---|
| パースエンジン | Rust ネイティブ | MoonBit WASM |
| derive 構文 | `#[arg(...)]` / `#[command(...)]` | `#[kuu(...)]` |
| フィルタ | validator 関数 | 宣言的フィルタチェイン |
| バリエーション | 手動実装 | `variation_*` 属性で宣言的 |
| exclusive | `conflicts_with` | `exclusive_group` |

### なぜ clap の上に被せないか

kuu は独自の WASM パースエンジンを持っており、Rust/Python/TS 等の多言語で同一の挙動を保証することが目的。
clap の上に被せると、clap 固有の挙動に引きずられ、言語間の一貫性が崩れる。

### Option<bool> の扱い

`bool` フィールドは常に値を持つ（default=false）。
`Option<bool>` は「ユーザーが明示的に指定したか」を `is_set()` で判定する場合に使う:

```rust
#[kuu(variation_false = "no")]
verify: Option<bool>,
// --verify → Some(true), --no-verify → Some(false), 未指定 → None
```

通常の `bool` フィールドは default 付き flag として振る舞い、常に `true` or `false`:

```rust
verify: bool,  // default=false, --verify で true
```

`#[kuu(default = true)]` と組み合わせると:

```rust
#[kuu(default = true, variation_false = "no")]
verify: bool,  // default=true, --no-verify で false
```
