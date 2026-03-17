# DR-001: Terraform Go Example 設計判断

日付: 2026-03-18

## 1. オプションプレフィックス: ダブルダッシュ使用

- **問題**: Terraform は `-var`, `-chdir` 等すべて単一ダッシュを使用するが、kuu は `--` が標準
- **発見経緯**: codex レビュー（計画段階）で致命的問題として指摘
- **解決策**: kuu 標準の `--` を使用し、差異を DESIGN.md に記載
- **選択理由**: kuu の shorts 結合パース（`-abc` → `-a -b -c`）と単一ダッシュ多文字オプションは衝突。根本対応には kuu コア変更が必要でデモのスコープ外

## 2. destroy コマンド: 独立コマンドとして定義

- **問題**: Terraform の `destroy` は内部的に `apply -destroy` だが、kuu の command alias では `-destroy` フラグを自動注入できない
- **発見経緯**: codex レビューで指摘
- **解決策**: `destroy` を独立コマンドとして定義し、apply と同じオプション群を `applyOpts()` で共有
- **選択理由**: command alias は「名前の別名」であり、フラグ自動注入は別実装が必要

## 3. 値レベルの排他制約: Go 側バリデーション

- **問題**: `--refresh=false` と `--refresh-only` の矛盾は kuu の exclusive モデル（オプション名の排他）では表現不可
- **発見経緯**: codex レビューで指摘
- **解決策**: デモでは扱わず、知見として記録
- **選択理由**: 値レベルの排他は kuu の設計思想（パース時制約 vs ランタイム制約）の境界にある問題

## 4. WASM パス: main ワークスペース参照

- **問題**: moon build がワークスペース内の unicodegrapheme 依存で失敗（`for "bench"` 構文未対応）
- **発見経緯**: 実装中に moon build エラー
- **解決策**: main ワークスペースの既存 `_build/` を参照するように justfile と kuu_bridge.mjs のパスを調整
- **選択理由**: moon のバージョン問題であり、WASM 自体は正常にビルド済み

## 5. lockfile choices: "skip" 追加

- **問題**: Terraform 1.7+ では `--lockfile` に "readonly" と "skip" の2値が存在
- **発見経緯**: マルチペルソナレビュー（Terraform CLI 専門家）
- **解決策**: Choices に "skip" を追加

## 6. stdout パイプリーク修正

- **問題**: NewKuuBridge() で cmd.Start() 失敗時に stdout パイプがクローズされない
- **発見経緯**: マルチペルソナレビュー（セキュリティ専門家 + WASM bridge 専門家）
- **解決策**: エラーパスに stdout.Close() を追加
