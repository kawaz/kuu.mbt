# TUI/CLI 関連調査

## 既存ツールの移植検討

### antenna-cli

- **実装**: Bun + TypeScript
- **特徴**: kubectl / az 連携が中核機能
- **MoonBit 移植**: 非現実的（社内ツール、クラウドCLI連携が本質）

### claude-session-analysis

- **実装**: Bun + TypeScript
- **特徴**: JSONL パース + ANSI 出力
- **MoonBit 移植**: 技術的には可能
- **移植メリット**: 起動速度の向上、MoonBit 学習素材として適切

## MoonBit の TUI/CLI エコシステム

### ライブラリ

| ライブラリ | 状態 | 説明 |
|---|---|---|
| onebit-tui | 開発初期 | TUI フレームワーク |
| moonbitlang/async | 安定 | stdio / process / http 対応 |

### C FFI 経由ターミナル制御

ネイティブバックエンドでは C FFI を経由して直接ターミナル制御が可能。termios 操作やエスケープシーケンス出力など。

## ネイティブバックエンドのシステム API

MoonBit ネイティブバックエンドが提供する組み込み API:

| API | 説明 |
|---|---|
| `args_get` | コマンドライン引数の取得 |
| `env_get_var` | 環境変数の取得 |
| `read_char` | 標準入力から1文字読み取り |
| `write_char` | 標準出力に1文字書き込み |
| `flush` | 標準出力のフラッシュ |
| `exit` | プロセス終了 |

## moonbitlang/async

非同期ランタイムライブラリ。CLI ツール開発に必要な機能を提供:

- `process.run()`: 外部プロセス実行
- `stdio`: 標準入出力
- `pipe`: パイプ操作
