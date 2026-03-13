# ValuePath 方式 PoC 設計書

## 概要

struct-first CLI パーサのアプローチ検証。アプリの struct を先に定義し、CLI パーサがその struct に値を直接注入する方式。

## 核心アイデア

```
既存 kuu:  Parser定義 → Opt[T] → .get().unwrap()  （ボトムアップ）
ValuePath: Struct定義 → ValuePath → struct.field.val  （トップダウン）
```

## アーキテクチャ

### Commit[T] — 値注入の戦略

```moonbit
enum Commit[T] {
  Exist(() -> T)          // フラグ: 存在したらTを返す
  Value((String) -> T)    // 値: CLI文字列からTを生成
}
```

元スケッチでは `Value((T) -> T)` だったが、CLI文字列→T変換の必要性から `(String) -> T` に変更（DR-001）。

### PathEntry — 型消去されたパスエントリ

```moonbit
struct PathEntry {
  name : String
  needs_value : Bool
  on_match : (String) -> Unit
}
```

クロージャ `on_match` が `Ref[T]` をキャプチャし、型安全に値を注入。kuu core の ExactNode と同じ戦略（DR-003）。

### Struct — Ref フィールド

MoonBit に spread syntax がないため、struct フィールドを `Ref[T]` にして直接ミュータブルに注入（DR-002）。

## パースフロー

```
args → vp_parse(global_paths, subcmds) → サブコマンド検出 → vp_parse(sub_paths, sub_subcmds)
```

2段階パース: ルートレベルでサブコマンドを検出し、残り引数をサブコマンドに委譲。

## 検証結果

| 項目 | 結果 |
|------|------|
| Generic enum (Commit[T]) | ✅ 動作 |
| 型消去 (クロージャ束縛) | ✅ 動作 |
| Struct update syntax | ❌ MoonBit非対応 → Ref で代替 |
| --flag パース | ✅ 動作 |
| --name value パース | ✅ 動作 |
| --name=value パース | ✅ 動作 |
| count (-v -v -v) | ✅ 動作 |
| append (-f a -f b) | ✅ 動作 |
| サブコマンド (compose up) | ✅ 動作 |

## 既存 kuu との比較

| 観点 | 既存 kuu | ValuePath |
|------|---------|-----------|
| 値の取り出し | `.get().unwrap()` | `.field.val` |
| 型安全性 | Opt[T] でコンパイル時保証 | Ref[T] でコンパイル時保証 |
| ヘルプ生成 | 自動 (OptMeta) | 未実装（要拡張） |
| サブコマンド | Parser.sub() で宣言的 | 2段階パースで手動構築 |
| エラー報告 | ParseError with context | 簡易エラー文字列 |

## 未実装・課題

- ヘルプ表示: PathEntry にメタデータ追加が必要
- positional 引数: rest でカバーしているが専用対応なし
- エラー報告: 位置情報やコンテキストなし
- バリデーション: required, exclusive, at_least_one 等の制約
- short オプション結合: `-dit` → `-d -i -t`
- 2段階パースの制約: vp_parse 単体ではネストしたサブコマンド（例: `compose up`）を扱えない。ルートレベルでサブコマンドを検出し残り引数をバッファに格納、その後バッファを別の vp_parse に渡す手動2段階パースが必要
- グローバルオプションのサブコマンド内での使用が未対応: サブコマンドに分岐した後はグローバルオプション（`--debug` 等）を認識しない。サブコマンド内でもグローバルオプションを使うには paths に含める等の対応が必要
- `--` (dashdash) separator 未対応: `--` 以降を全て positional 引数として扱う機能がない
