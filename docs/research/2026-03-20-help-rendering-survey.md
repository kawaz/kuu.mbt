# jj ヘルプレンダリング調査

調査日: 2026-03-20

---

## 1. jj のヘルプレンダリング

### コマンドヘルプ

clap 標準の `StyledStr` → ANSI 変換パイプライン。clap が生成する `StyledStr` をそのままターミナルに出力する。

### キーワードヘルプ

Markdown テキストをそのまま表示。ターミナル向けのリッチレンダリングは TODO 状態。

### formatter.rs: ラベルスタック方式

jj 独自のスタイリングエンジン。ログ出力やテンプレート出力で使用。

- ラベルをスタックに push/pop し、現在のラベルセットに応じたスタイルを適用
- セマンティックなラベル名（`"error"`, `"heading"` 等）で記述し、テーマ側で色を定義
- **ヘルプ出力には未使用**（clap のスタイリングをそのまま利用）

### FormatRecorder

スタイリング操作（テキスト書き込み + push/pop ラベル）を記録し、後から別の出力先に再生するパターン。テスト用途やバッファリングに利用。

---

## 2. clap の unstable-markdown

- v4.5.28 から導入。feature flag `unstable-markdown` で有効化
- ビルド時に Markdown → ANSI 変換。pulldown_cmark を使用
- まだ unstable であり、jj は未採用

---

## 3. 関連ツール

| ツール | 言語 | 概要 |
|--------|------|------|
| termimad | Rust | Markdown → ターミナル直接変換 |
| clap-help | Rust | clap + termimad でリッチなヘルプ出力 |
| glow | Go | glamour ライブラリベースの Markdown ターミナルレンダラ |

---

## 4. kuu への推奨設計

### パイプライン

```
OptMeta → HelpData(構造化) → Renderer(差し替え可能)
```

### 設計方針

- **ラベルベースのセマンティックスタイリング**: jj の formatter.rs 方式に倣い、出力要素にセマンティックなラベルを付与。テーマ側でスタイルを定義
- **--color 3値制御**: `auto | always | never`
- **core は HelpData 生成（純粋関数）**: レンダラは外部から差し替え可能
- **Markdown を内部表現にしない**: 構造化データから直接 styled テキストを生成。Markdown はあくまで出力フォーマットの1つ
