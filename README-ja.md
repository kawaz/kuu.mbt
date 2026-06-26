# kuu

> [English](./README.md) | 日本語

MoonBit 製 CLI 引数パーサ。投機実行 + 最長一致による解決で、宣言順に依存しない曖昧さの解消を実現する。

## 特徴

- **投機実行 + 最長一致** -- 候補を全て試し、最も妥当な解釈を採用する。順序非依存、曖昧さを silent に潰さない。
- **宣言からアクセスまで型安全** -- `Opt[T]` が型情報をパース全体で持ち運ぶ。downcast 不要、文字列 map に頼らない。
- **FilterChain** -- 合成可能な `String -> T` パイプライン。`map`, `validate`, `parse` と `then` による Kleisli 合成。
- **直交コンビネータ** -- `clone`, `link`, `adjust` の合成で alias, variation, deprecation, 派生オプションを表現。
- **構造化エラー** -- どのエラーメッセージにも文脈ヘルプ、typo 候補、usage 概要、フッターが含まれる。

## クイックスタート

```bash
moon add kawaz/kuu
```

`moon.pkg` に import を追加:

```json
import {
  "kawaz/kuu/core",
  "moonbitlang/core/env",
}

options("is-main": true)
```

```moonbit
fn main {
  let p = @core.Parser::new()
  let name = p.string(name="name", default="world")
  // @env.args() は argv[0] (バイナリパス) を含むので先頭をスキップ
  let result = try? p.parse(@env.args()[1:].to_array())
  match result {
    Err(@core.HelpRequested(text)) => println(text)
    Err(@core.ParseError(info)) => println(info.to_string())
    Ok(_) => println("Hello, " + name.get().unwrap())
  }
}
```

```
$ hello --name kuu
Hello, kuu
```

## サンプル

### フラグとオプション

```moonbit
let p = @core.Parser::new()
let verbose = p.flag(name="verbose", shorts="v", description="Enable verbose output")
let port = p.int(name="port", default=8080, description="Port number")
let host = p.string(name="host", default="localhost")

let _ = try? p.parse(["--verbose", "--port", "3000"])
verbose.get()  //=> Some(true)
port.get()     //=> Some(3000)
host.get()     //=> Some("localhost")
```

### ショートオプション結合

`-vA1B2` は型情報を使って分解される -- フラグは値を消費せず、値オプションは続く文字を消費する:

```moonbit
let p = @core.Parser::new()
let v = p.flag(name="verbose", shorts="v")
let a = p.string(name="alpha", default="", shorts="A")
let b = p.string(name="beta", default="", shorts="B")

let _ = try? p.parse(["-vA1B2"])
v.get()  //=> Some(true)
a.get()  //=> Some("1")
b.get()  //=> Some("2")
```

### サブコマンド

```moonbit
let p = @core.Parser::new()
let verbose = p.flag(name="verbose", global=true)

let serve = p.sub(name="serve", description="Start server")
let port = serve.int(name="port", default=8080)

let result = try? p.parse(["serve", "--port", "3000", "--verbose"])
match result {
  Ok(r) => {
    verbose.get()      //=> Some(true)    -- global なのでどのスコープでも有効
    port.get()         //=> Some(3000)    -- "serve" スコープ
    r.child("serve")   //=> Some(...)     -- サブコマンドの result
  }
  // ...
}
```

### choices と implicit_value

```moonbit
let p = @core.Parser::new()
let color = p.string(
  name="color",
  default="auto",
  choices=["always", "auto", "never"],
  implicit_value="always",           // --color (値なし) は "always" 扱い
  description="When to use color",
)

let _ = try? p.parse(["--color"])
color.get()  //=> Some("always")

let _ = try? p.parse(["--color=never"])
color.get()  //=> Some("never")
```

### Variation

```moonbit
let p = @core.Parser::new()
let verbose = p.flag(
  name="verbose",
  shorts="v",
  variation_toggle=Some("no"),   // --no-verbose を生成
)
let _ = try? p.parse(["-v", "--no-verbose"])
verbose.get()  //=> Some(false)  -- toggle で戻る
```

### 制約

```moonbit
let p = @core.Parser::new()
let json = p.flag(name="json")
let csv = p.flag(name="csv")
let output = p.string(name="output", default="")

p.exclusive([json.as_ref(), csv.as_ref()])   // 排他: 最大 1 つ
p.required(output.as_ref())                  // 必須
```

### 環境変数

オプションは環境変数から値を読み取れる。優先度は CLI 引数 > 環境変数 > default。

```moonbit
let p = @core.Parser::new()
p.env_prefix("MYAPP")
let port = p.int(name="port", default=8080, env="PORT")

// 優先度: CLI > MYAPP_PORT > default (8080)
let _ = try? p.parse(["--port", "3000"], env={ "MYAPP_PORT": "9090" })
port.get()  //=> Some(3000)  -- CLI が勝つ
```

`auto_env` を有効にすると、すべての `Visible` オプションが name から自動派生した環境変数にバインドされる:

```moonbit
let p = @core.Parser::new()
p.env_prefix("MYAPP")
p.auto_env(true)
let log_level = p.string(name="log-level", default="info")

// MYAPP_LOG_LEVEL に自動バインド (ハイフン → アンダースコア、大文字化)
let _ = try? p.parse([], env={ "MYAPP_LOG_LEVEL": "debug" })
log_level.get()  //=> Some("debug")
```

### シェル補完

bash, zsh, fish 向けの補完スクリプトを生成:

```moonbit
let p = @core.Parser::new()
let _ = p.flag(name="verbose", shorts="v", description="Verbose output")
let _ = p.string(name="output", default="", description="Output file")
p.sub(name="build", description="Build project") |> ignore

let script = p.generate_completion_script(shell="zsh", command_name="myapp")
```

Hidden オプションは補完から除外、Advanced オプションは補完に含まれる。

### Visibility

オプションがヘルプ出力と補完に出るかを制御:

```moonbit
let p = @core.Parser::new()
let verbose = p.flag(name="verbose", description="Verbose output")          // Visible (default)
let debug   = p.flag(name="debug", description="Debug mode", visibility=Advanced) // help からは隠れるが補完には出る
let secret  = p.flag(name="secret", visibility=Hidden)                       // help にも補完にも出ない
```

| レベル | Help | 補完 | パース |
|-------|------|-------------|---------|
| `Visible` | 表示 | 含む | 動作 |
| `Advanced` | 隠す | 含む | 動作 |
| `Hidden` | 隠す | 除外 | 動作 |

### file コンビネータ

ファイルパス用の 3 値パターン -- `--config` (値なし) は default_path、`--config path` は指定パス、未指定は default:

```moonbit
let p = @core.Parser::new()
let config = p.file(name="config", default="", default_path="~/.config/myapp/config.toml")

let _ = try? p.parse(["--config"])
config.get()  //=> Some("~/.config/myapp/config.toml")  -- 暗黙の default_path

let _ = try? p.parse(["--config", "/etc/app.conf"])
config.get()  //=> Some("/etc/app.conf")  -- 明示パス

let _ = try? p.parse([])
config.get()  //=> Some("")  -- 未指定 = default
```

### マージ可能リストフィルタ

`Filter::mergeable_list` は `+`/`-`/`...` 修飾子をサポート、ベースリストへの追加・削除・並び替えを表現できる:

```moonbit
let p = @core.Parser::new()
let fields = p.custom(
  name="fields",
  default=["id", "name"],
  pre=@core.Filter::mergeable_list(base=["id", "name"]),
)

let _ = try? p.parse(["--fields", "+email,-id"])
fields.get()  //=> Some(["name", "email"])

let _ = try? p.parse(["--fields", "email,..."])
fields.get()  //=> Some(["email", "id", "name"])  -- "..." はベースの残りを展開
```

## FilterChain

`String` から任意の型へ変換する型安全パイプライン。`map` (純粋変換), `validate` (検証 + 型保持), `parse` (変換 + 失敗あり) の 3 コンストラクタを `then` で合成:

```moonbit
let p = @core.Parser::new()

// String -> trim -> 空文字検証 -> Int -> 範囲検証
let port = p.custom(
  name="port",
  default=8080,
  pre=@core.Filter::trim()
    .then(@core.Filter::non_empty())
    .then(@core.Filter::parse_int())
    .then(@core.Filter::in_range(1, 65535)),
)

let _ = try? p.parse(["--port", " 443 "])
port.get()  //=> Some(443)
```

32 種の組み込みフィルタ: 文字列変換 (`trim`, `to_lower`, `replace`, ...), 検証 (`non_empty`, `min_length`, `starts_with`, ...), 数値パーサ (`parse_int`, `parse_float`, `parse_bool`), 範囲検証 (`in_range`, `positive`, `clamp`), 選択 (`one_of`), 配列操作 (`split`, `each`), 正規表現 (`regex_match`, `regex_replace`, `regex_split`)。

## エラー表示

エラーメッセージは 4 レイヤーの文脈を含む:

```
error: unexpected argument: --prot
  help: --port <PORT>  Port number [default: 8080]
  tip: a similar option exists: '--port'

Usage: [OPTIONS]

For more information, try '--help'.
```

| レイヤー | 内容 |
|-------|---------|
| error | 何が起きたか |
| help | 関連オプションのヘルプ行 |
| tip | typo 候補 (Levenshtein 距離ベース) |
| usage + footer | より詳しい help の出し方 |

## ライセンス

MIT License -- Yoshiaki Kawazu ([@kawaz](https://github.com/kawaz))
