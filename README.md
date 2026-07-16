# kuu.mbt

[kuu](https://github.com/kawaz/kuu) (言語非依存な CLI 引数定義仕様) の **MoonBit 参照実装**。

- 仕様・API 契約・conformance fixture の正本: [kawaz/kuu](https://github.com/kawaz/kuu)
- **移植の定義**: kawaz/kuu が公開する conformance fixture を pass すること (= 実装が仕様に適合したことの判定基準)
- 立ち上げ方針: [docs/decisions/MDR-001](docs/decisions/MDR-001-bootstrap-policy.md)
- 実装フェーズ: [kuu の ROADMAP](https://github.com/kawaz/kuu/blob/main/ROADMAP.md)
- 初期の実験実装は [`kuu-v0`](https://github.com/kawaz/kuu.mbt/tree/kuu-v0) 枝、垂直スライス PoC は [`slice`](https://github.com/kawaz/kuu.mbt/tree/slice) 枝にアーカイブ

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
