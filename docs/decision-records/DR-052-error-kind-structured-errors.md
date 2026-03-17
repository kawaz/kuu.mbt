# DR-052: ErrorKind 構造化エラー

## 背景

現在の `ParseErrorInfo { message, help_text }` はフラット文字列で、エラー種別のプログラム的判別ができない。CLIライブラリとしてエラーハンドリングの基盤が必要。

## 設計

### ErrorKind enum の追加

```moonbit
pub(all) enum ErrorKind {
  UnknownOption       // 未知のオプション（typo hint 付き）
  UnexpectedArgument  // 予期しない位置引数
  MissingRequired     // 必須オプション未指定
  InvalidValue        // 値のパース/バリデーション失敗
  ArgumentConflict    // 排他制約違反
  AmbiguousMatch      // 曖昧なマッチ（複数候補同率）
  MissingValue        // 値が必要だが未提供
  MissingSubcommand   // サブコマンド必須だが未指定
  DuplicateDefinition // オプション定義の重複（プログラミングエラー）
  AtLeastOneRequired  // at_least_one 制約違反
  DependencyMissing   // requires 制約違反
  ParseAlreadyCalled  // Parser::parse の二重呼び出し
} derive(Show, Eq)
```

**不採用: DeprecatedUsage** — deprecated は ParseError を raise せず `deprecated_usages: Array[(String, String)]` に warning として記録する設計。ErrorKind の対象外。

**将来の拡張注意**: ErrorKind は `pub(all) enum` のため、バリアント追加は exhaustive match を壊す。ユーザーにはワイルドカード `_` のフォールバックを推奨。

### ParseErrorInfo の拡張

```moonbit
pub(all) struct ParseErrorInfo {
  kind : ErrorKind    // NEW: エラー種別
  message : String    // 既存: 人間向けメッセージ
  help_text : String  // 既存: ヘルプテキスト
  opt_name : String   // NEW: 関連情報（下記参照）
}
```

### opt_name の付与ポリシー

`opt_name` の意味は ErrorKind により異なる:

| ErrorKind | opt_name の内容 |
|---|---|
| UnknownOption, UnexpectedArgument | ユーザーが入力した引数文字列（例: `"--typo"`） |
| MissingRequired, DependencyMissing | 該当オプションの定義名（例: `"output"`） |
| MissingValue | 値が不足しているオプション名（例: `"--output"`, `"-o"`） |
| その他 | 空文字列（複数オプション関与、または特定オプションに紐づかない） |

### parse_error ヘルパーの拡張

```moonbit
fn parse_error(message : String, kind~ : ErrorKind = InvalidValue, opt_name~ : String = "") -> ParseError
```

既存の `parse_error(message)` 呼び出しは互換性維持（kind=InvalidValue がデフォルト）。filter.mbt のバリデーション系は全て InvalidValue で、kind を明示指定する必要がない。

## 影響

- ParseErrorInfo にフィールド追加 → `pub(all) struct` のため、直接構築している外部コードは breaking change。mooncakes.io 公開前なので許容
- suberror ParseError の構造自体は変更なし
- HelpRequested は suberror の別バリアントとして分離維持（エラーではなく制御フロー的脱出）
- WASM bridge は ParseErrorInfo.message のみ使用 → 影響なし

## テスト

- ErrorKind 12バリアント × kind 検証テスト（11件実パース + 1件 enum 構築確認）
- 既存テスト（49件 message 検証）は変更なし
- テスト: 1194 → 1206件（+12件）
