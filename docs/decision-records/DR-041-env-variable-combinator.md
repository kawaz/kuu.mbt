---
type: decision
---

# DR-041: 環境変数コンビネータ設計構想

## ステータス

構想段階

## 動機

CLI ツールでは `--port 8080` の代わりに `PORT=8080` で設定できるのが一般的。
kuu の opt コンビネータに `env` パラメータを追加し、環境変数からの値取得を宣言的に定義できるようにしたい。

## 設計概要

### 2つの関心事の分離

| 関心事 | 型 | 役割 |
|---|---|---|
| 名前解決 | `EnvName` | どの環境変数名を使うか（副作用なし） |
| 値取得 | `EnvSource` | 環境変数の値をどこから取得するか（副作用あり） |

分離の理由:

- **名前** はヘルプ表示 `[env: PORT]` にも必要。パース前に副作用なしで解決できるべき
- **値取得** は `getenv()` 等の副作用を伴う。コア純粋関数主義（DR-027）に従い注入可能にする
- テスト時は Map を注入、WASM 環境では別の取得手段を注入、等

### 解決フロー

```
1. EnvName → 環境変数名を解決（副作用なし）
2. EnvSource + 解決済み名前 → 値を取得（副作用あり、外部注入）
3. コマンドライン引数が未指定の場合に、取得した値をフォールバックとして使用
```

優先順位: コマンドライン引数 > 環境変数 > default/default_fn

## 型設計

### EnvName — 環境変数名の解決

```
enum EnvName {
  Name(String)                  // 直接指定: "PORT"
  Thunk((EnvCtx) -> String)     // 動的生成: ctx => ctx.parent + "_PORT"
}
```

- `Name`: 固定の環境変数名。ヘルプ表示にそのまま使える
- `Thunk`: 親コマンド名等のコンテキストに応じて動的に名前を生成

```
fn resolve(self : EnvName, ctx : EnvCtx) -> String {
  match self {
    Name(name) => name
    Thunk(f) => f(ctx)
  }
}
```

### EnvCtx — 名前解決・値取得のコンテキスト

```
struct EnvCtx {
  parent : String?              // 祖先コマンドから構築されたプレフィックス
  resolved_opts : ???           // 解決済みオプション値へのアクセス（型は未決）
  src : EnvSource?              // 環境変数の取得元
}
```

- `parent`: サブコマンドの階層に応じたプレフィックス生成に使用
  - 例: app="myapp", cmd="serve" → parent="MYAPP_SERVE" → 変数名="MYAPP_SERVE_PORT"
- `resolved_opts`: 他のオプションの解決済み値を参照するためのハンドル
  - 例: `--env=dev` が解決済みなら `MYAPP_DEV_VERBOSE` のように値を組み込める
  - 解決タイミングの詳細は後述
- `src`: 環境変数の値を実際に取得する手段

### EnvSource — 環境変数の値の取得元

```
enum EnvSource {
  Fn((EnvCtx, String) -> String?)    // (ctx, name) -> value
  Map(Map[String, String])           // テスト用の固定マップ
}
```

- `Fn`: 標準的な取得。`getenv` のラッパー等を注入。名前解決済みの変数名を受け取る
- `Map`: テスト用。固定の key-value から取得

※ 元の構想メモに `Thunk((EnvCtx) -> String?)` バリアントがあったが、名前を受け取らないため EnvName の名前解決をバイパスしてしまう。書き漏れで `(EnvCtx, String)` の可能性が高い（= Fn と同じ）。実際のユースケースが明確になった時点で再検討する。

## 使用イメージ

### シンプルな固定名

```moonbit
let port = p.int_opt(name="port", env=Name("PORT"))
// --port 8080 or PORT=8080
// help: --port <INT>  [env: PORT]
```

### 親コマンドに応じた動的命名

```moonbit
let port = p.int_opt(
  name="port",
  env=Thunk(fn(ctx) {
    match ctx.parent {
      Some(prefix) => prefix + "_PORT"
      None => "PORT"
    }
  }),
)
// myapp serve --port 8080 or MYAPP_SERVE_PORT=8080
```

### 他オプションの値に依存する動的命名

```moonbit
// グローバルオプション --env にも環境変数デフォルトがある
let env_opt = p.string_opt(name="env", env=Name("MYAPP_ENV"), global=true)

// --verbose の環境変数名が --env の値に依存する
let verbose = p.flag(
  name="verbose",
  env=Thunk(fn(ctx) {
    // ctx.resolved_opts から --env の解決済み値を取得
    match get_env_prefix(ctx) {
      Some(prefix) => prefix + "_VERBOSE"   // MYAPP_DEV_VERBOSE
      None => "MYAPP_VERBOSE"
    }
  }),
)
```

優先順位の例:
1. `--verbose` / `--no-verbose`（コマンドライン引数、最優先）
2. `MYAPP_DEV_VERBOSE=true`（環境変数、--env=dev のとき）
3. `MYAPP_VERBOSE=true`（環境変数、--env 未指定のとき）
4. default 値

### テスト時の Map 注入

```moonbit
let env_src = EnvSource::Map({ "PORT": "8080", "HOST": "localhost" })
let ctx = EnvCtx(parent=None, src=Some(env_src))
// parse 時に ctx を渡すことで実際の環境変数を使わずにテスト可能
```

## コア純粋関数主義（DR-027）との整合

コアの責務は以下に限定:

1. **メタデータ保持**: opt が「環境変数 X から取得可能」という宣言を保持
2. **名前解決**: EnvName → String の解決（Thunk の場合は EnvCtx が必要）
3. **ヘルプ生成**: `[env: PORT]` の表示

**コアがやらないこと**:

- `getenv()` の呼び出し（副作用）
- 環境変数値のパース（値取得後のフォールバック適用）

EnvSource の注入と値取得はレイヤー2（WASM bridge）またはレイヤー3（KuuCore）の責務。
コアは EnvName の定義と解決までを担当し、実際の値取得は上位レイヤーに委譲する。

## ヘルプ表示

```
Options:
  --port <INT>    Server port [env: PORT]
  --host <STR>    Server host [env: MYAPP_HOST]
```

- `Name(s)`: そのまま表示
- `Thunk(f)`: パース前にコンテキストなしで名前を確定できない場合がある
  → `default_display` パターンと同様に、表示用の名前を別途持つか検討が必要

## 解決タイミングと依存関係

環境変数フォールバックはデフォルト適用と同じ最終フェーズで処理される:

```
1. パースフェーズ: コマンドライン引数の消費（ExactNode マッチング）
2. デフォルト適用フェーズ: 未消費の opt にデフォルト値 or 環境変数値を適用
```

この時点で大半のオプション値は解決済みのため、`resolved_opts` から他オプションの値を参照できる。

### オプション間依存がある場合

```
--env=dev (コマンドライン引数で指定済み)
  ↓
MYAPP_ENV=dev (解決済み)
  ↓
MYAPP_DEV_VERBOSE=true (--env の値を使って名前を解決)
```

通常はパースフェーズで `--env` が消費済みなので問題ない。

環境変数同士が依存する場合（`--env` 自体も環境変数からフォールバック）:
- `MYAPP_ENV=dev` → `--env=dev` → `MYAPP_DEV_VERBOSE` の順に解決
- 環境変数フォールバックを複数パスで処理する（依存なし → 依存あり の順）
- または変化がなくなるまで繰り返す収束方式
- 循環依存はエラー

## 未決事項

### 1. resolved_opts の型と公開範囲

- EnvCtx 経由で他オプションの値を参照する仕組みの具体的な型設計
- 全オプションの値を公開するか、明示的に依存宣言したもののみか
- 型安全性: `Opt[String]` のハンドルをそのまま使えるか、名前ベースのアクセスか

### 2. Thunk の場合のヘルプ表示

- `Name("PORT")` → `[env: PORT]` と表示できる
- `Thunk(f)` → パース前に名前が確定しない
- 解決案: `env_display: String?` パラメータを追加するか、Thunk に display hint を持たせる

### 3. EnvSource の注入ポイント

- パーサ構築時（`Parser::new` のパラメータ）か
- パース実行時（`parse(args, env_source=...)` のパラメータ）か
- 後者の方が柔軟（同じパーサ定義でテスト/本番を切り替え可能）

### 4. append 系コンビネータとの相互作用

- `append_string` で `env="PATHS"` を指定した場合、値の分割ルール（カンマ区切り？PATH区切り？）をどう定義するか
- `env_delimiter: String?` パラメータが必要かもしれない

### 5. WASM bridge（DR-035）への反映

- JSON schema に `env` フィールドを追加
- EnvSource は WASM 側（ホスト言語）から注入する形になる
- opt AST ポータビリティ（DR-030）にも影響: env 定義を JSON export に含める

### 6. 環境変数フォールバックの複数パス処理

- 依存なし env → 依存あり env の2パス方式か、収束ループ方式か
- 循環依存の検出方法（DAG 検証 or ループ上限）
- 実用上は2パスで十分な可能性が高い（深い依存チェーンは稀）
