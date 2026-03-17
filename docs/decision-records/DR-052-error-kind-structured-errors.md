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
  DeprecatedUsage     // deprecated オプション使用（warning 級だが記録は必要）
  ParseAlreadyCalled  // Parser::parse の二重呼び出し
} derive(Show, Eq)
```

### ParseErrorInfo の拡張

```moonbit
pub(all) struct ParseErrorInfo {
  kind : ErrorKind    // NEW: エラー種別
  message : String    // 既存: 人間向けメッセージ
  help_text : String  // 既存: ヘルプテキスト
  opt_name : String   // NEW: 関連オプション名（空文字列 = なし）
}
```

### parse_error ヘルパーの拡張

```moonbit
fn parse_error(message : String, kind~ : ErrorKind = InvalidValue, opt_name~ : String = "") -> ParseError
```

既存の `parse_error(message)` 呼び出しは互換性維持（kind=InvalidValue がデフォルト）。

## 実装方針

1. **後方互換**: `parse_error("msg")` の既存呼び出しは変更不要（デフォルト kind=InvalidValue）
2. **段階的移行**: まず型定義とヘルパーを追加、次に各呼び出し箇所の kind を正しく設定
3. **テスト**: 既存テストは message ベースで検証しているため壊れない。kind ベースの新テストを追加
4. **filter のエラー**: filter.mbt のバリデーション系は全て InvalidValue

## 影響

- ParseErrorInfo にフィールド追加 → 構造体を直接参照しているテスト箇所は修正必要
- suberror ParseError の構造自体は変更なし
- WASM bridge は ParseErrorInfo.message を使っているのみ → 影響なし
