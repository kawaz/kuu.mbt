# kuu

MoonBit 製 CLI 引数パースエンジン。多言語基盤としても設計されている。

全 OptKind を `initial + reducer` で統一し、ExactNode の**投機実行 + 最長一致**で消費する。消費ループは型を知らず、名前解決も持たない。全ての複雑さはコンビネータ層で ExactNode に事前展開される。

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

**投機実行 + 最長一致**: 各 ExactNode が「自分が消費できるか」を自己判定し、最長 consumed の候補が勝つ。PEG の ordered choice とは異なり、順序非依存で曖昧さも検出できる。

**統一的な処理**: `-abc` ショート結合、`--color`/`--color=always` の共存、choices バリデーションが全て同一のアルゴリズムで解決される。個別の特殊分岐が parse_raw のメインループに一切ない。

**4層レイヤー**: Sugar（`flag()` 等）→ Convention（名前展開）→ Pattern（最長一致統合）→ Core（ExactNode 走査）。各層は ExactNode の生成と登録という単一操作に統一。

**型安全**: `Opt[T]` の getter クロージャと ExactNode の try_reduce/commit クロージャが同じ `Ref[T]` を共有。ダウンキャスト不要、ResultMap 不要。

**多言語基盤**: core は純粋パースエンジン。DX 層を言語別に提供（MoonBit: Parseable trait、他言語: WASM bridge 経由）。

## Features

**コンビネータ:**
`flag`, `string_opt`, `int_opt`, `count`, `append_string`, `append_int`, `custom[T]`, `custom_append[T]`

**位置引数:** `positional`, `rest`, `serial`, `never`

**サブコマンド:** `cmd` (→ `Opt[CmdResult]`), `sub` (→ `Parser`), `require_cmd`

**制約:** `exclusive`, `required`, `at_least_one`

**別名:** `alias` (値共有 + is_set 独立、チェーン対応), `deprecated` (非推奨警告付き)

**フィルタ:** `FilterChain` — `map`, `validate`, `parse` + `then` で Kleisli 合成。Accumulator で変換と蓄積を分離

**その他:** `dashdash`, `append_dashdash`, `Variation` (Toggle/True/False/Reset/Unset), `choices`, `implicit_value`, `global`, `hidden`, `stop_before`, `default_fn`, 自動ヘルプ生成

## Architecture

4層レイヤー + OC/P 2フェーズパース:

```
Sugar:       flag(), string_opt(), custom[T](), cmd(), ...
Convention:  expand_and_register — name + aliases + shorts + variations 展開
Pattern:     make_or_node — 最長一致で複合ノード統合
Core:        ExactNode (try_reduce) + OC/P 消費ループ
```

OC Phase で ExactNode を投機実行 + 最長一致マッチ。P Phase で unclaimed 引数を non-greedy positional に割り当て。install ノード（eq_split, short_combine, separator）が特殊構文を ExactNode に変換し、メインループから特殊分岐を完全に排除する。

詳細は `docs/DESIGN-v2.md` を参照。

## Build & Test

```bash
just          # check + test
just fmt      # format
just test     # run tests
just test-all # all targets (wasm-gc, wasm, js)
just size     # binary size report
```

## Examples

`examples/` に多言語デモあり:

- `20260308-mydocker` — MoonBit: Docker CLI サブセット (sub nesting, exclusive, required)
- `20260309-mydocker-go` — Go: kuu WASM bridge 経由での Docker CLI パース
- `20260309-kubectl` — MoonBit: kubectl サブコマンド構造
- 他: curl, gcc, cargo(Python), spm(Swift), git(TypeScript) 等

## License

MIT License, Yoshiaki Kawazu (@kawaz)
