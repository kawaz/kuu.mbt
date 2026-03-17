# 20260318-tar 設計書

## 概要

GNU tar コマンドの引数パースを kuu で再現するデモ。tar の実機能は未実装で、パース結果の表示に特化する。

## 検証ポイント

- **排他制約**: `exclusive` + `at_least_one` による操作モードの排他的必須選択
- **圧縮オプション排他**: `exclusive` のみ（任意選択）
- **count 重ね掛け**: `-v` の複数指定で詳細度が増す
- **env 環境変数**: `TAR_ARCHIVE` によるデフォルトアーカイブファイル指定
- **deprecated**: 廃止予定オプションの警告表示
- **alias**: `--extract`/`--get`, `--catenate`/`--concatenate` 等の同義オプション
- **variation_false**: `--wildcards`/`--no-wildcards` 等の対称フラグ

## アーキテクチャ

フラット構造（サブコマンドなし）。tar の伝統的な設計をそのまま再現する。

## オプション分類

| 分類 | 数 |
|---|---|
| 動作モード (create/extract/list/append/update) | 5 |
| 圧縮 (gzip/bzip2/xz/compress/zstd/lzip) | 6 |
| ファイル指定 (-f) | 1 |
| 詳細度 (-v) | 1 |
| フィルタ・制御 (exclude/strip-components/transform) | 3 |
| フラグ (preserve-permissions/keep-old-files/touch/verify/interactive/overwrite/no-recursion) | 7 |
| ディレクトリ変更 (-C) | 1 |
| 位置引数 (FILES...) | 1 |
| **合計** | **25** |

## 設計判断

- **Bundled flags** (`tar xvf`): kuu のスコープ外。前処理でバンドルを展開すれば対応可能
- **`-C` の位置依存セマンティクス**: 再現しない。`append_string` で収集しアプリ側で処理する方式で代替
- **`-f` の required 扱い**: 全モードで required として統一（実際の tar は `-r`/`-u` のみ必須）

## 詳細

[DR-001-tar-demo-design.md](docs/decision-records/DR-001-tar-demo-design.md) 参照
