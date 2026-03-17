# brew-swift

Homebrew `brew` コマンドの引数パースデモ。Swift + kuu WASM bridge で実装。

> **Note**: 実際の brew の全オプションを網羅していない近似的なデモです。
> kuu の多言語対応能力と複雑な CLI 構造の扱いを検証する目的で作成しています。

## 必要環境

- Swift 6.0+
- [bun](https://bun.sh/) (WASM bridge ランタイム)
- `wasm/kuu.wasm` — kuu リポジトリルートで `moon build --target wasm-gc --release` 後、
  `_build/wasm-gc/release/build/src/wasm/wasm.wasm` を `wasm/kuu.wasm` にコピー

## ビルド & テスト

```bash
just          # ビルド + 全テストシナリオ実行
just build    # ビルドのみ
just test     # テストシナリオ実行
just run install --verbose --formula node npm  # 任意の引数で実行
```

## 実行例

```bash
# ヘルプ表示
brew-swift --help
brew-swift install --help

# install
brew-swift install --verbose --formula node npm typescript
brew-swift install --force --build-from-source --cask firefox

# search
brew-swift search --desc json
brew-swift search --formula node

# tap
brew-swift tap homebrew/cask
brew-swift tap user/repo https://example.com/repo.git

# upgrade
brew-swift upgrade --dry-run --greedy
brew-swift upgrade --formula node

# list
brew-swift list --versions --formula
brew-swift list --pinned
```

## アーキテクチャ

```
Swift → bun subprocess → kuu.wasm → JSON 結果
```

詳細は [docs/DESIGN.md](docs/DESIGN.md) を参照。

## kuu 検証ポイント

- グローバルオプション (--verbose, --debug, --quiet)
- exclusive 制約 (--formula vs --cask)
- aliases (--formulae → --formula)
- コマンドエイリアス (ls → list)
- rest 引数 (複数パッケージ名)
- 短形式結合 (-fs = -f -s)
- 値付きオプション (--cc=gcc-9)

## ライセンス

`wasm/kuu.wasm` は [kuu](https://github.com/kawaz/kuu.mbt) (MIT License) からビルドしたバイナリです。
