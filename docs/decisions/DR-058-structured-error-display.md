---
type: implementation
status: draft
---

# DR-058: 構造化エラー表示（clap v4 準拠4層フォーマット）

## 背景

DR-052 で ErrorKind による構造化エラーの基盤を整備した。しかし、エラーの**表示フォーマット**は依然として改善の余地がある:

- `ParseErrorInfo::to_string()` は `"error: " + message + "\n\n" + error_context` のフラット構造
- `error_context` に全ヘルプ出力をダンプしており、不要な情報が多い
- サジェスト（did you mean）が message に埋め込まれている
- Usage 行がエラー表示に含まれない

clap v4 のエラー出力は4層構造で、ユーザーが問題を素早く特定・解決できる設計になっている。kuu もこれに倣う。

## 目標フォーマット

```
error: unexpected argument: --prot
  help: --port <PORT>  ポート番号を指定 [default: 8080]
  tip: a similar option exists: '--port'

Usage: [OPTIONS] <DIR>

For more information, try '--help'.
```

4層:

1. **error**: エラーの説明
2. **help**: 関連オプションのヘルプ行（opt_name から OptMeta を検索）
3. **tip**: サジェスト（did you mean 等）
4. **Usage + footer**

## 設計

### ParseErrorInfo 変更

`tip` フィールドを追加し、サジェスト/ヒント情報を message から分離する:

```moonbit
pub(all) struct ParseErrorInfo {
  kind : ErrorKind
  message : String
  error_context : String  // 構造化エラーコンテキスト
  opt_name : String
  tip : String        // NEW: サジェスト/ヒント用
}
```

`error_context` の用途: 構造化エラーコンテキスト（help 行 + Usage + footer）。旧名 `help_text` からリネーム。

### 新メソッド

1. **`Parser::generate_usage() -> String`** — Usage 行のみ生成（generate_help() から抽出）
2. **`Parser::find_meta_by_opt_name(name: String) -> OptMeta?`** — opt_name から OptMeta を検索
3. **`Parser::format_opt_help_line(meta: OptMeta) -> String`** — 1オプションのヘルプ行を生成
4. **`Parser::format_error_context(info: ParseErrorInfo) -> String`** — 構造化エラーコンテキストを生成

### format_unexpected_with_hint 変更

現在 `format_unexpected_with_hint` はサジェストを message に埋め込んでいる:

- **現在**: `"unexpected argument: X (did you mean Y?)"` を返す
- **変更後**: `(message, tip)` タプルを返す
  - message: `"unexpected argument: X"`
  - tip: `"a similar option exists: 'Y'"`

### to_string() 変更

```
error: {message}
[  help: {opt_help_line}]    // error_context の先頭部分
[  tip: {tip}]               // tip が非空の場合

[Usage: ...]                  // error_context の残り部分

For more information, try '--help'.
```

実装方針: tip を分離してフィールド化。コンテキスト（help 行 + Usage + footer）は `Parser::parse()` で `error_context` に格納。`to_string()` は message + tip + error_context を組み合わせて出力。

### ErrorKind 別のコンテキスト

| ErrorKind | help 行 | tip |
|---|---|---|
| UnknownOption | サジェスト先の OptMeta | a similar option exists: 'X' |
| UnexpectedArgument | サジェスト先の OptMeta | a similar option exists: 'X' |
| MissingRequired | 不足オプションの OptMeta | — |
| InvalidValue | 対象オプションの OptMeta | — |
| MissingValue | 対象オプションの OptMeta | — |
| ArgumentConflict | — | — |
| AmbiguousMatch | — | — |
| MissingSubcommand | — | — |
| AtLeastOneRequired | — | — |
| DependencyMissing | — | — |
| DuplicateDefinition | — | — |
| ParseAlreadyCalled | — | — |

## テスト方針

- 既存テスト705件のエラーメッセージ検証を新フォーマットに更新
- ErrorKind 別の表示テストを追加（各層の有無パターン）
