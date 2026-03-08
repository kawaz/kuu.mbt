# gmux/shimux 分析（MoonBit 移植検討資料）

## 概要

- **gmux**: Ghostty 上で Claude Code Agent Teams の tmux モードを動作させる tmux 互換 CLI ラッパー
- **shimux**: gmux のリネーム先（作業中）
- **実装言語**: Go 1.25.5、外部依存なし
- **実装言語の最終決定**: 未定（調査段階）

## 主要機能

- tmux CLI パーサ（サブコマンド互換）
- ペイン操作（keysim / osascript）
- PTY プロキシエージェント
- tmux フォーマット変数展開
- 特殊キー変換

## アーキテクチャ

```
cmd/
  gmux/           # メインエントリポイント
  gmux-agent/     # PTYプロキシエージェント
internal/
  tmux/           # tmux CLI互換パーサ
  ghostty/        # Ghosttyターミナル操作
  agent/          # エージェントプロセス管理
  pane/           # ペイン操作
  wrapper/        # tmuxラッパーロジック
```

## MoonBit 移植時の課題

| 課題 | 難易度 | 説明 |
|---|---|---|
| PTY (ioctl) | 高 | POSIX ioctl 呼び出しが必要 |
| Unix ソケット | 高 | プロセス間通信に使用 |
| シグナル処理 | 高 | SIGWINCH 等のハンドリング |
| プロセス制御 | 高 | fork/exec 相当の機能 |
| osascript 連携 | 中 | macOS 固有のスクリプト実行 |

## 推奨アーキテクチャ

MoonBit 単体では POSIX システムコールへのアクセスが困難なため、以下の構成を推奨:

- **MoonBit**: ロジック層（CLI パース、フォーマット展開、キー変換等）
- **Rust**: 薄い FFI レイヤー（PTY、ソケット、シグナル、プロセス制御等のシステムコール）

MoonBit のネイティブバックエンド（C 出力）を経由して Rust と連携する形になる。
