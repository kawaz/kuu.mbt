# kuu

MoonBit 製 CLI 引数パーサライブラリ。

ExactNode ベースのフラット走査アーキテクチャにより、ショートオプション結合 (`-abc`)、`--name=value` 分解、choices + implicit_value の最長一致など、複雑な引数パターンを統一的に処理する。

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

## Features

**コンビネータ:**
`flag`, `string_opt`, `int_opt`, `count`, `append_string`, `append_int`, `custom[T]`, `custom_append[T]`

**位置引数:** `positional`, `rest`, `serial`, `never`

**サブコマンド:** `cmd` (→ `Opt[CmdResult]`), `sub` (→ `Parser`), `require_cmd`

**制約:** `exclusive`, `required`

**別名:** `alias` (値共有 + is_set 独立、チェーン対応)

**フィルタ:** `FilterChain` — `map`, `validate`, `parse` + `then` で Kleisli 合成

**その他:** `dashdash`, `append_dashdash`, `Variation` (Toggle/True/False/Reset/Unset), `choices`, `implicit_value`, `global`, `hidden`, 自動ヘルプ生成

## Build & Test

```bash
just          # check + test
just fmt      # format
just test     # run tests
just test-all # all targets (wasm-gc, wasm, js)
just size     # binary size report
```

## Architecture

4層レイヤー構造 + OC/P 2フェーズパース:

```
Sugar:       flag(), string_opt(), custom[T](), cmd(), ...
Convention:  expand_and_register — name + aliases + shorts + variations 展開
Pattern:     make_or_node — 最長一致で複合ノード統合
Core:        ExactNode (try_reduce) + OC/P 消費ループ
```

詳細は `docs/DESIGN.md` を参照。

## Examples

`examples/` に多言語デモあり:

- `20260308-mydocker` — MoonBit: Docker CLI サブセット (sub nesting, exclusive, required)
- `20260309-mydocker-go` — Go: kuu WASM bridge 経由での Docker CLI パース
- `20260309-kubectl` — MoonBit: kubectl サブコマンド構造
- 他: curl, gcc, cargo(Python), spm(Swift), git(TypeScript) 等

## License

MIT License, Yoshiaki Kawazu (@kawaz)
