---
type: vision
---

# DR-057: kuu-cli — 言語非依存の独立コマンドとしての kuu

## 日付

2026-03-19

## ステータス

構想 (Vision)

## 背景

kuu の多言語展開を進める中で、以下の認識が形成された:

1. **WASM bridge はワンバイナリにできない**という明確な弱点がある
2. **ネイティブ FFI (.a/.so/.dylib) は PoC 済み**で、Go/Rust からワンバイナリ化可能（MoonBit compiler の lib 出力は fork で実現、本家 PR 予定）
3. kuu core の JSON in/out プロトコルは **WASM bridge で既に安定稼働**しており、言語非依存のインターフェースとして機能している
4. kuu-cli embed パターン (DR-047) で単一バイナリとしての配布も実証済み

これらを踏まえ、kuu をライブラリだけでなく**独立コマンド**として提供する構想が浮上した。

## 核心的な洞察

**「引数パース」だけを担う独立コマンドは、今まで存在しない新ジャンル。**

```
jq      → JSON処理の独立コマンド
sed/awk → テキスト処理の独立コマンド
kuu     → 引数パースの独立コマンド   ← 新ジャンル
```

引数パースは今まで各言語のライブラリに閉じ込められていたが、やっていることは「文字列の配列を受け取って構造化データ（JSON）にする」だけで、本質的に言語依存ではない。

## 利用イメージ

### 基本

```bash
kuu parse schema.json -- "$@"
# → JSON で構造化された結果が stdout に出力
```

### シェルスクリプトから

```bash
result=$(kuu parse schema.json -- "$@")
port=$(echo "$result" | jq -r '.values.port')
verbose=$(echo "$result" | jq -r '.values.verbose')
```

### 活用範囲

- シェルスクリプト
- Makefile
- GitHub Actions
- CI/CD パイプライン
- 言語のラッパースクリプト
- プロトタイピング

## 発展構想: Web UI によるスキーマ生成

JSON スキーマを手書きせず、Web UI でオプション定義をぽちぽち作成 → JSON export → `kuu parse` で即動作、という開発者体験。

- UI 構築が得意な開発者コミュニティとの接点が生まれる
- 「引数パースのコードを書く」という行為自体を不要にする可能性
- export した JSON は kuu-cli でも、ライブラリとしての kuu でもそのまま使える

## 発展構想: 100コマンドパースリポジトリ

世の中の著名な CLI コマンド（curl, git, docker, ffmpeg, kubectl, terraform 等）100個分のスキーマ JSON を集めたショーケースリポジトリ。

### 目的

- **宣伝**: 「kuu はこれだけのコマンドをパースできます」の動く証明
- **ドキュメント**: 「curl みたいなオプションを書きたいなら curl.json を見て」
- **回帰テスト**: 100コマンド分のパースが通り続けることを CI で保証
- **新機能検証**: 新機能追加時に100個全部で再検証

### 特徴

- リポジトリに MoonBit のコードが1行もない（JSON + `kuu parse` だけ）
- `/itumono-example` パイプラインで並列生成可能

## 多言語戦略の全体像（現時点）

| レイヤー | 用途 | 状態 |
|---|---|---|
| **kuu コマンド** | 言語非依存、シェル/CI | 構想 (本 DR) |
| **ネイティブ FFI** (.a/.so/.dylib) | Go/Rust/Swift/C でワンバイナリ | PoC 済み（compiler fork） |
| **WASM-GC** | JS/TS（ブラウザ/Deno/Bun） | 動作中 |
| **kuu-cli embed** (DR-047) | ランタイムなし単一バイナリ配布 | PoC 済み |

kuu コマンドは最上位レイヤーとして、ネイティブ FFI や WASM の上に乗る。内部的には同じ JSON プロトコルを使用。

## MoonBit compiler lib 出力について

- MoonBit の C backend は実行バイナリ用の `.o` を出力できるが、ライブラリ（.a/.so/.dylib）としてのビルドは未サポート
- fork で4ファイル微修正により lib 出力を実現、Go/Rust からのワンバイナリ化を確認
- 本家への PR で正式サポートを目指す
- MoonBit のコンパイラは tree shaking が関数単位で効くため、使った機能の分だけリンクされバイナリサイズも小さい

## タイムライン

- MoonBit 1.0.0 が2026年夏頃リリース予定
- それまでにコア設計の安定化 + 初回 publish を目指す
- kuu-cli はコア安定後の展開として位置づけ

## 関連 DR

- DR-027: core 純粋関数主義 + 多言語 DX レイヤー構想
- DR-029: 言語境界を越える Serialize/Deserialize 設計構想
- DR-030: opt AST の言語間ポータビリティ
- DR-047: kuu-cli embed+extract+exec パターン
- DR-046: LLVM backend ネイティブ FFI 実現可能性調査（不可の結論 → fork で解決）
