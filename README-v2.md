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

**4層レイヤー**: Sugar（`flag()` 等のユーザーAPI）→ Convention（名前展開）→ Pattern（最長一致統合）→ Core（ExactNode 走査）。各層は ExactNode の生成と登録に統一。

**型安全**: `Opt[T]` が返す値はコンビネータ定義時の型がそのまま保持される。ダウンキャスト不要、ResultMap 不要。

**直交コンビネータ**: alias / clone / link / adjust の合成で、複雑なオプション関係（別名、値転送、値変換、非推奨など）を宣言的に表現できる。

## Features

**コンビネータ:**
`flag`, `string_opt`, `int_opt`, `count`, `append_string`, `append_int`, `custom[T]`, `custom_append[T]`

**位置引数:** `positional`, `rest`, `serial`, `never`

**サブコマンド:** `cmd` (→ `Opt[CmdResult]`), `sub` (→ `Parser`), `require_cmd`

**制約:** `exclusive`, `required`, `at_least_one`

**別名・合成:** `alias` (値共有 + is_set 独立、チェーン対応), `deprecated` (非推奨警告付き), `clone` (構造コピー), `link` (値転送), `adjust` (値変換)

**フィルタ:** `FilterChain` — `map`, `validate`, `parse` + `then` で Kleisli 合成。Accumulator で変換と蓄積を分離

**その他:** `dashdash`, `append_dashdash`, `Variation` (Toggle/True/False/Reset/Unset), `choices`, `implicit_value`, `global`, `hidden`, `stop_before`, `default_fn`, 自動ヘルプ生成

## Architecture

コア内部は4層レイヤー + OC/P 2フェーズパースで構成:

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
