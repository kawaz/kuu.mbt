# kuu.mbt

[kuu](https://github.com/kawaz/kuu) (言語非依存な CLI 引数定義仕様) の **MoonBit 参照実装**。

- 仕様・API 契約・conformance fixture の正本: [kawaz/kuu](https://github.com/kawaz/kuu)
- **移植の定義**: kawaz/kuu が公開する conformance fixture を pass すること (= 実装が仕様に適合したことの判定基準)
- [mooncakes.io](https://mooncakes.io/docs/kawaz/kuu) にて `kawaz/kuu` として公開
- 立ち上げ方針: [docs/decisions/MDR-001](docs/decisions/MDR-001-bootstrap-policy.md)
- 実装フェーズ: [kuu の ROADMAP](https://github.com/kawaz/kuu/blob/main/ROADMAP.md)
- 初期の実験実装は [`kuu-v0`](https://github.com/kawaz/kuu.mbt/tree/kuu-v0) 枝、垂直スライス PoC は [`slice`](https://github.com/kawaz/kuu.mbt/tree/slice) 枝にアーカイブ

## インストール

```bash
moon add kawaz/kuu
```

`moon.pkg.json` に front-door パッケージを import する:

```json
{ "import": ["kawaz/kuu/kuu"] }
```

## Hello World

定義 (kuu 仕様に沿った JSON) を `parse_definition` に食わせ、`argv` を `parse`
に流し、`Success` outcome の effects を読む:

```moonbit
let definition : Json = @json.parse(
  #|{
  #|  "options": [
  #|    { "name": "verbose", "type": "flag", "long": true, "short": "v" }
  #|  ]
  #|}
)

let ast = match @kuu.parse_definition(definition) {
  Ok(a) => a
  Err(_) => { println("definition rejected"); return }
}

match @kuu.parse(ast, ["--verbose"]) {
  @engine.Success(binds) =>
    for b in binds {
      println("\{b.key} = \{render_value(b.value)}")
    }
  @engine.Failure(_) => println("parse failed")
  @engine.Ambiguous(_) => println("ambiguous")
}
```

`b.value` は `@engine.Value` 直和 (`String` / `Number` / `Bool`) — 呼び出し側
の都合で pattern match する。argv `["--verbose"]` を渡すと `verbose = true`
が印字される。

## conformance suite の起動

conformance fixture は [kawaz/kuu](https://github.com/kawaz/kuu) 側の正本を
`KUU_FIXTURES` で注入する。kuu.mbt と kawaz/kuu が隣接した checkout であれば
`just test` が `../../kuu/main/fixtures` を自動検出する。それ以外の場合:

```bash
KUU_FIXTURES=/path/to/kawaz/kuu/fixtures moon test --target native
```

runner は `[json-conformance] decoded=317 ran_cases=733 mismatches=0` の
ような 1 行を出す。

## Status

参照実装、pre-1.0。kuu 仕様は未凍結のため `kawaz/kuu` の MoonBit API 面
(front-door `parse_definition` / `parse` / `resolve` 等) は minor バージョン
間でも breaking し得る。現状: conformance suite green (decoded=317,
733 cases, 0 mismatches)。

## 構成

| パス | 内容 |
|---|---|
| `src/engine/` | 構造・評価・解決の汎用 engine |
| `src/builtins/` | canonical builtins |
| `src/kuu/` | kuu assembly (組成・front door・conformance runner) |
| [docs/decisions/](docs/decisions/INDEX.md) | Design Record (MDR-NNN)。仕様 DR とは別系統 |

## DR 番号空間

本リポの DR は **MDR-NNN** (3 桁)。仕様側 DR (kawaz/kuu の DR-NNN) は複製せず「kawaz/kuu の DR-NNN」形式で参照する ([MDR-001 §3](docs/decisions/MDR-001-bootstrap-policy.md))。

## License

MIT © Yoshiaki Kawazu
