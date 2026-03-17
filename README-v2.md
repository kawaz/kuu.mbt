# kuu

MoonBit 製 CLI 引数パースエンジン。

投機実行と最長一致で曖昧さを構造的に解決する。定義順序に依存せず、`-abc` ショート結合も `--color`/`--color=always` の共存も同一アルゴリズムで処理する。

## Quick Start

```moonbit
let p = @core.Parser::new()
p.set_description("myapp - A sample application")

let verbose = p.count(name="verbose", shorts="v", global=true, description="Increase verbosity")
let output = p.string_opt(name="output", default="stdout", shorts="o", description="Output destination", value_name="FILE")
let force = p.flag(name="force", description="Force overwrite")

let file = p.positional(name="FILE", description="Input file")

let result = try? p.parse(args)
match result {
  Err(@core.HelpRequested(text)) => println(text)
  Err(@core.ParseError(info)) => println("Error: " + info.to_string())
  Ok(_) => {
    println(verbose.get().unwrap().to_string())  // 0, 1, 2, ...
    println(output.get().unwrap())                // "stdout" or user value
    println(file.get().unwrap_or("(none)"))       // positional arg
  }
}
```

## なぜ kuu か

**投機実行 + 最長一致**: 各オプションが「自分が消費できるか」を自己判定し、最長消費の候補が勝つ。定義の順序に依存しない。曖昧な入力（同率候補）も検出してエラーにできる。

**統一的な処理**: `-abc` ショート結合、`--color`/`--color=always` の共存、choices バリデーションが全て同一のアルゴリズムで解決される。メインのパースループに特殊分岐が一切ない。

**型安全**: `Opt[T]` が返す値はコンビネータ定義時の型がそのまま保持される。型キャスト不要。

**直交コンビネータ**: alias / clone / link / adjust の合成で、複雑なオプション関係（別名、値転送、値変換、非推奨など）を宣言的に表現できる。

## Features

**コンビネータ:**
`flag`, `string_opt`, `int_opt`, `count`, `append_string`, `append_int`, `custom[T]`, `custom_append[T]`

**位置引数:** `positional`, `rest`, `serial`, `never`

**サブコマンド:** `cmd`, `sub`, `require_cmd` -- ネストしたサブコマンドにも対応

**制約:** `exclusive`, `required`, `at_least_one`

**別名・合成:** `alias` (別名定義、チェーン対応), `deprecated` (非推奨警告付き), `clone` (独立コピー), `link` (値転送), `adjust` (値変換)

**フィルタ:** `FilterChain` -- `map`, `validate`, `parse` を連鎖して型変換やバリデーションを宣言的に合成

**その他:** `dashdash`, `append_dashdash`, `Variation` (Toggle/True/False/Reset/Unset), `choices`, `implicit_value`, `global`, `hidden`, `stop_before`, `default_fn`, 自動ヘルプ生成

## Build & Test

```bash
just          # check + test
just fmt      # format
just test     # run tests
just test-all # all targets (wasm-gc, wasm, js)
just size     # binary size report
```

## Examples

`examples/` にサンプルコードあり:

- `20260308-mydocker` -- MoonBit: Docker CLI サブセット (サブコマンドネスト, exclusive, required)
- `20260309-kubectl` -- MoonBit: kubectl サブコマンド構造

`examples/archives/` には WASM bridge (PoC) 経由で他言語から kuu を利用する実験的なデモも含む:

- `20260309-mydocker-go` -- Go + WASM bridge 経由での Docker CLI パース
- 他: curl, gcc, cargo(Python), spm(Swift), git(TypeScript) 等

> **Note**: 多言語対応 (WASM bridge, 各言語向け DX API) は構想・PoC 段階です。安定した API として MoonBit から直接利用できます。

## Architecture

内部設計の詳細は `docs/DESIGN-v2.md` を参照。

## License

MIT License, Yoshiaki Kawazu (@kawaz)
