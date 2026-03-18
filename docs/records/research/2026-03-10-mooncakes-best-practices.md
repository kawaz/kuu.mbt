# mooncakes.io ベストプラクティス調査

調査日: 2026-03-10
対象: moonbitlang(公式), tonyfettes, mizchi, moonbit-community, TheWaWaR/clap.mbt

## 調査の背景と目的

kuu.mbt を mooncakes.io に publish するにあたり、パッケージ構成・プロジェクト構造・README・moon.mod.json 等の慣習を事前に把握する必要があった。

mooncakes.io はまだ若いエコシステムで公式ドキュメントだけでは慣習が掴みにくいため、上位ユーザーや公式の実際のパッケージを調査し、実践的なベストプラクティスを抽出する方針とした。

## 調査方法

5グループ・計25リポジトリを対象に、5つのサブエージェントで並列調査を実施。各リポジトリの GitHub 上の以下を確認:

1. moon.mod.json の全フィールド
2. ディレクトリ構造（src/ の有無、パッケージ分割、テスト配置）
3. moon.pkg.json の設定
4. README.md の構成
5. .gitignore
6. CI/CD（GitHub Actions）
7. テストファイルの命名規則
8. ライセンス
9. CONTRIBUTING.md 等の有無

### 調査対象の選定理由

| グループ | 選定理由 |
|---------|---------|
| moonbitlang（公式, 6リポ） | 言語開発元。公式推奨パターンの基準 |
| tonyfettes（77パッケージ, 2位） | mooncakes.io パッケージ数2位。多パッケージ開発者の実践 |
| mizchi（87パッケージ, 1位） | mooncakes.io パッケージ数1位。最も活発な個人開発者 |
| moonbit-community（16パッケージ） | 公式コミュニティ org。コミュニティ標準の参考 |
| TheWaWaR/clap.mbt（1リポ） | kuu の直接競合。API 設計・パッケージ構成の比較材料 |

## 調査サマリー

25リポジトリを調査し、mooncakes.io パッケージの慣習・ベストプラクティスを整理した。

---

## 1. moon.mod.json

### 必須・推奨フィールド

| フィールド | 形式 | 例 | 備考 |
|-----------|------|-----|------|
| `name` | `{user}/{pkg}` | `"moonbitlang/core"` | mooncakes.io 上のパス |
| `version` | semver | `"0.1.0"` | 初期リリースは 0.1.0 が慣例 |
| `deps` | object | `{"moonbitlang/core": "0.1.0"}` | 外部依存（core は省略不可） |
| `description` | string | `"MoonBit standard library"` | 英語の簡潔な説明 |
| `keywords` | string[] | `["parser", "cli"]` | 検索用キーワード |
| `license` | string | `"Apache-2.0"` or `"MIT"` | Apache-2.0 が最多、MIT も一般的 |
| `repository` | string | `"github.com/user/repo"` | `https://` なし、ホスト名から |
| `source` | string | `"github.com/user/repo"` or `"src"` | リポジトリURL or ソースディレクトリ |
| `readme` | string | `"README.md"` | README ファイルパス |

### オプションフィールド

| フィールド | 用途 | 例 |
|-----------|------|-----|
| `warn-list` | 警告の有効/無効 | `""` (全無効), `"-2"`, `"+all-2"` |
| `alert-list` | アラートの有効/無効 | `""` |
| `exclude` | publish 除外ファイル | `["prebuild", "test_directory"]` |
| `preferred-target` | 推奨ビルドターゲット | `"js"`, `"native"` |

### name の命名パターン

- 公式: `moonbitlang/core`, `moonbitlang/x`
- 個人: `mizchi/x`, `tonyfettes/json`, `TheWaWaR/clap`
- コミュニティ: `xbony2/cmark`, `purerosefallen/debug`（GitHub org ではなくユーザー名）

### source フィールドの2つの用法

1. **リポジトリURL**: `"github.com/kawaz/kuu.mbt"` — ソースコードの場所
2. **ディレクトリ指定**: `"src"` — パッケージソースが `src/` 配下にある場合

`source: "src"` の採用率は高い:
- 公式: quickcheck, async
- moonbit-community: cmark, fuzzy_match, js-ffi（3/6）
- tonyfettes: 全リポジトリ

kuu は `src/core/` 構成なので `"source": "src"` が該当する。

### 典型的な moon.mod.json

```json
{
  "name": "kawaz/kuu",
  "version": "0.1.0",
  "deps": {},
  "readme": "README.md",
  "description": "A CLI argument parser for MoonBit",
  "keywords": ["cli", "parser", "argument", "option"],
  "license": "MIT",
  "repository": "github.com/kawaz/kuu.mbt",
  "source": "src",
  "warn-list": "",
  "alert-list": ""
}
```

---

## 2. ディレクトリ構造

### 標準パターン（全調査対象で一貫）

```
repo/
  moon.mod.json
  README.md
  LICENSE
  .gitignore
  .github/workflows/
  {pkg1}/
    moon.pkg.json
    foo.mbt
    foo_test.mbt
  {pkg2}/
    moon.pkg.json
    bar.mbt
    bar_test.mbt
  example/ or examples/
    moon.pkg.json
    main.mbt
```

### 重要な慣習

- **`source: "src"` が主流になりつつある**: ルート直下配置も多いが、`src/` 配下に置いて `source: "src"` を指定するパターンが公式・コミュニティで広く採用
- **テストは同一ディレクトリ内**: `*_test.mbt` をソースと同じディレクトリに配置
- **example/ ディレクトリ**: サンプルコードは `example/` or `examples/` に配置
- **`pkg.generated.mbti` は Git 管理対象**: 全リポジトリで追跡。CI で `moon info` + diff チェックを行い同期を検証

### パッケージ分割パターン

| パターン | 例 | 用途 |
|---------|-----|------|
| 単一パッケージ | `lib/` のみ | 小規模ライブラリ（clap.mbt） |
| 機能別分割 | `json/`, `json5/`, `jsonpath/` | 関連機能のモノリポ |
| ドメイン分割 | `array/`, `string/`, `map/` | 標準ライブラリ（core） |
| 内部パッケージ | `internal/` | テストヘルパー等 |
| サブディレクトリモジュール | `debug/`, `rabbita/` | 1リポに複数独立パッケージ |

---

## 3. moon.pkg.json / moon.pkg

**注意**: `moon.pkg.json`（JSON形式）と `moon.pkg`（MoonBit DSL形式）の2形式が存在。DSL 形式への移行傾向あり。

### 主要フィールド

```json
{
  "import": [
    "moonbitlang/core/json",
    "mypackage/internal"
  ],
  "test-import": [
    "moonbitlang/core/random"
  ],
  "targets": {
    "native": false
  },
  "link": {
    "wasm": {
      "exports": ["parse"]
    }
  },
  "is-main": true
}
```

| フィールド | 用途 |
|-----------|------|
| `import` | ビルド時依存 |
| `test-import` | テスト専用依存 |
| `targets` | ターゲット別有効/無効（`"native": false` 等） |
| `link` | WASM/JS のエクスポート設定 |
| `is-main` | エントリポイントパッケージ |

---

## 4. テスト

### ファイル命名規則

| パターン | 種類 | 可視性 |
|---------|------|--------|
| `*_test.mbt` | white-box test | プライベートAPI にアクセス可能 |
| `*_wbtest.mbt` | black-box test | パブリックAPI のみ |

- `*_test.mbt` が圧倒的主流
- `*_wbtest.mbt` は少数（tonyfettes/c.mbt, moonbitlang/core 等）
- テストファイル名: `{モジュール名}_test.mbt`（例: `parser_test.mbt`）

### 注意: MoonBit の命名規則

MoonBit では一般的な認識と逆:
- `_test.mbt` = **white-box**（同パッケージのプライベートにアクセス可）
- `_wbtest.mbt` = **black-box**（パブリックAPIのみ）

---

## 5. README.md

### 推奨構成

1. **タイトル + 概要**: パッケージの説明（英語）
2. **インストール**: `moon add {user}/{pkg}` 形式
3. **使用例**: 基本的なコード例
4. **API ドキュメントリンク**: mooncakes.io の自動生成ドキュメントへ
5. **ライセンス**: 末尾に記載

### バッジ

- 少数派。core は GitHub バッジあり
- mooncakes.io のバッジは見当たらない（エコシステムがまだ若い）

### API ドキュメント

- **mooncakes.io の自動生成に委ねる**のが主流
- README に全 API を書くのではなく、使用例を中心に記述

---

## 6. .gitignore

### 標準構成

```gitignore
target/
.mooncakes/
```

- `target/`: ビルド成果物（全リポジトリ共通）
- `.mooncakes/`: 依存パッケージのキャッシュ（大半のリポジトリ）

---

## 7. CI/CD (GitHub Actions)

### 基本三点セット

```yaml
- run: moon check --deny-warn
- run: moon test
- run: moon fmt --check
```

### 発展的な構成

- 複数ターゲットでテスト: `wasm`, `wasm-gc`, `js`, `native`
- カバレッジ: `moon test --enable-coverage` + レポート生成
- `moon check --deny-warn`: 警告をエラー扱い
- `moon info` + `git diff --exit-code`: `pkg.generated.mbti` の同期チェック（API 変更の漏れ検出）
- `moon fmt` + `git diff --exit-code`: フォーマット漏れ検出

### publish ワークフロー（公式パターン）

```yaml
# 認証: シークレットから credentials.json を生成
- run: |
    echo '{"MOONBIT_MOONCAKES_USERNAME":"...","MOONBIT_MOONCAKES_TOKEN":"${{ secrets.TOKEN }}"}' > ~/.moon/credentials.json
# publish 実行
- run: moon publish
# クリーンアップ
- run: rm -f ~/.moon/credentials.json
```

- トリガー: `release` イベント + `workflow_dispatch`（手動実行）が最も柔軟
- publish 前チェック: `moon check`, `moon info` diff, `moon fmt` diff を実行

### publish 前のサブパッケージ除外

2つの方法:
1. **`exclude` フィールド**（宣言的、推奨）: moon.mod.json で除外対象を指定
2. **スクリプト**（手続的）: quickcheck は `rm_deps.js`、tonyfettes は `scripts/publish.py`（テストファイル/mbti 削除 → `moon publish`）

### README.mbt.md の2つの用途

1. **ドキュメント内コードテスト**: `moon test README.mbt.md` でコードブロックをテスト（regexp, formatter）
2. **mooncakes 用 README**: CLI 用 `README.md` とは別に mooncakes.io 向けの `README.mbt.md` を用意し、moon.mod.json の `readme` フィールドで指定（mizchi/bit-vcs）

### publish 前チェック（`just` ツール）

mizchi は `just release-check` で publish 前に一括チェック:
```
fmt + info diff + check --deny-warn + test
```

### 利用率

- 公式（moonbitlang）: 積極的に使用
- 個人（mizchi, tonyfettes）: 一部のみ
- コミュニティ: 少数派

---

## 8. ライセンス

| ライセンス | 採用者 |
|-----------|--------|
| Apache-2.0 | moonbitlang, tonyfettes, moonbit-community |
| MIT | mizchi, TheWaWaR |

- ファイル名: `LICENSE`（大半のリポジトリ）
- **LICENSE ファイルは任意**: moon.mod.json の `license` フィールドで代替可能（mizchi の3リポジトリがファイルなし）
- CONTRIBUTING.md: core のみ。他は未設置
- CODE_OF_CONDUCT.md: ほぼ未設置

---

## 9. 競合比較: clap.mbt vs kuu

| 項目 | clap.mbt (TheWaWaR/clap) | kuu |
|------|----------------------|-----|
| API スタイル | `Parser` + `Arg` + `SubCommand`、Observer パターン (`Value` trait) | 宣言的 Opt[T] ベース |
| 型付け | 文字列名参照（型安全性が弱い） | `Opt[T]` → `get()` で型安全（kuu 優位） |
| サブコマンド | 対応 | 対応 |
| バージョン | 0.2.6 | 未publish |
| ライセンス | MIT | MIT |
| テスト | `*_test.mbt`（約12件） | `*_wbtest.mbt` 主体（797件） |
| CI/CD | なし | なし（要追加） |
| パッケージ名 | `TheWaWaR/clap` | `kawaz/kuu`（予定） |
| 環境変数 | 対応（`env_var`） | 未対応 |
| Nargs | `Nargs` enum（Any/One/Fixed/AtLeast/AtMost/Range） | 未対応 |
| `--` セパレータ | 未対応 | 対応 |
| alias | 未対応 | 対応（DR-037） |
| exclusive/required | 未対応 | 対応 |
| WASM bridge | なし | 対応（多言語展開構想あり） |
| `source` | `"src"`（ソースディレクトリ指定） | 要設定 |

---

## 10. kuu publish に向けた推奨アクション

### 必須

1. **moon.mod.json 整備**: name, version, deps, description, keywords, license, repository, source
2. **README.md 作成**: 英語、インストール手順、使用例、mooncakes.io リンク
3. **.gitignore 更新**: `target/`, `.mooncakes/` を確実に除外
4. **LICENSE ファイル**: MIT License, `LICENSE` ファイル名

### 推奨

5. **`source: "src"` の活用**: kuu は `src/core/` 構成なので `"source": "src"` を設定すれば現構成のまま publish 可能
   - 公式 quickcheck, async も `source: "src"` を使用しており、`src/` 配下のパッケージ構成は公式にサポート
   - ルート直下への移行は不要
6. **CI/CD 追加**: `moon check --deny-warn`, `moon test`, `moon fmt --check`
7. **`moon info` + diff チェック**: `pkg.generated.mbti` の同期チェックを CI に追加
8. **warn-list/alert-list**: `""` で不要な警告を抑制
9. **publish ワークフロー**: GitHub Actions で `moon publish` を自動化（release トリガー）
10. **`exclude` フィールド**: poc/, examples/archives/ 等の publish 不要ファイルを除外
11. **README.mbt.md の検討**: ドキュメント内コードのテスト（`moon test README.mbt.md`）

### 注意

- mooncakes.io のパッケージ名は `{user}/{pkg}` 形式で、GitHub の owner 名と異なる場合がある
  - moonbit-community のリポジトリでも `tonyfettes/json`, `xbony2/cmark` 等の個人名が使われる
- `source` フィールドは2つの用法がある（上記「source フィールドの2つの用法」参照）

---

## 調査元データ

- moonbitlang: core, x, quickcheck, regexp.mbt, async, formatter
- tonyfettes: json, uv.mbt, pcre2, url, unicode, c.mbt
- mizchi: x, bit-vcs, sol.mbt, cloudflare.mbt, markdown.mbt, luna
- moonbit-community: cmark, debug, fuzzy_match, ini, rabbita, js-ffi
- TheWaWaR: clap.mbt
