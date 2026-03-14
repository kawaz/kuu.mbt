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
  Exist(() -> T)                    // フラグ: 存在したらTを返す
  Value((String) -> (T, String?))   // 値: CLI文字列からTを生成（エラー時は Some(msg)）
}
```

元スケッチでは `Value((T) -> T)` だったが、CLI文字列→T変換の必要性から `(String) -> T` に変更（DR-001）。
R2 レビューで `abort()` を排除し `Result` 相当のエラー伝搬に変更。`Value` の戻り値を `(T, String?)` にすることで、`on_match` の型を `(String) -> String?`（None=成功、Some(msg)=エラー）に統一。

### vp_custom[T] — Commit[T] を使った汎用 PathEntry 構築

```moonbit
fn[T] vp_custom(name: String, target: Ref[T], commit: Commit[T]) -> PathEntry
```

`Commit::Exist(f)` → `needs_value=false`、`on_match` で `f()` を呼んで `target` に書き込み。
`Commit::Value(f)` → `needs_value=true`、`on_match` で `f(arg)` を呼んで `target` に書き込み、エラーがあればエラー文字列を返す。

既存の `vp_flag`, `vp_string` は `vp_custom` のラッパーとして定義。`vp_int` も `Commit::Value` で `parse_int_simple` を呼び、パースエラーを `String?` として伝搬。

### PathEntry — 型消去されたパスエントリ

```moonbit
struct PathEntry {
  name : String
  needs_value : Bool
  on_match : (String) -> String?   // None=成功、Some(msg)=エラー
}
```

クロージャ `on_match` が `Ref[T]` をキャプチャし、型安全に値を注入。kuu core の ExactNode と同じ戦略（DR-003）。
戻り値 `String?` でエラーを呼び出し元に伝搬し、`abort()` を回避。

### Struct — Ref フィールド

MoonBit に spread syntax がないため、struct フィールドを `Ref[T]` にして直接ミュータブルに注入（DR-002）。

## パースフロー

```
args → vp_parse(global_paths, subcmds) → サブコマンド検出 → vp_parse(sub_paths, sub_subcmds) → ...
```

多段階パース: ルートレベルでサブコマンドを検出し、残り引数をバッファに格納。その後バッファを別の `vp_parse` に渡す。3階層以上（例: `network create`）では、段階ごとにバッファ変数とパース呼出が線形に増加する。

## 検証結果

| 項目 | 結果 |
|------|------|
| Generic enum (Commit[T]) | ✅ 動作（vp_custom でパース時に実使用） |
| vp_custom[T] | ✅ vp_flag/vp_string/vp_int を Commit ベースで構築 |
| 型消去 (クロージャ束縛) | ✅ 動作 |
| Struct update syntax | ❌ MoonBit非対応 → Ref で代替 |
| --flag パース | ✅ 動作 |
| --name value パース | ✅ 動作 |
| --name=value パース | ✅ 動作 |
| count (-v -v -v) | ✅ 動作 |
| append (-f a -f b) | ✅ 動作 |
| サブコマンド (compose up) | ✅ 動作 |
| 3階層ネスト (network create) | ✅ 動作（3段階バッファリレーの煩雑さを実証） |
| 整数パースエラー | ✅ Result で伝搬（abort 不使用） |
| グローバルオプション位置制限 | ✅ エラー検出（制限の実証） |

## 既存 kuu との比較

| 観点 | 既存 kuu | ValuePath |
|------|---------|-----------|
| 値の取り出し | `.get().unwrap()` | `.field.val` |
| 型安全性 | Opt[T] でコンパイル時保証 | Ref[T] でコンパイル時保証 |
| ヘルプ生成 | 自動 (OptMeta) | 未実装（要拡張） |
| サブコマンド | Parser.sub() で宣言的 | 多段階パースで手動構築 |
| エラー報告 | ParseError with context | 簡易エラー文字列 |
| グローバルオプション | `global=true` で宣言的 | 未対応（各レベルに手動追加が必要） |
| short/long エイリアス | `shorts="v"` で統合 | 同じ Ref を共有する別 PathEntry を2つ定義 |
| スケーラビリティ | サブコマンド追加は sub() 1行 | 段階追加ごとにバッファ+パース呼出が線形増加 |

## 結論

### メリット

- `.get().unwrap()` の連鎖が解消され、struct フィールドで直接アクセスできる
- 全パース結果が1つの struct に集約され、見通しがよい
- `Commit[T]` + `vp_custom` で型安全な汎用パスエントリ構築が可能

### デメリット

- 多段階パースの煩雑さ: サブコマンドを追加するたびにバッファ変数 + パース呼出 + マッチ分岐が線形に増加。3階層（`network create`）で既に煩雑
- グローバルオプション未対応: サブコマンド分岐後はグローバルオプションを認識しない。各レベルに手動追加するとオプション重複管理が必要
- ヘルプ自動生成不可: PathEntry にメタデータがなく、`--help` を自動生成できない
- short/long の二重定義: 同じ Ref を共有する PathEntry を別途定義する必要がある

### 判断

struct-first は DX 層のフロントエンドとしては有望だが、kuu core を置き換えるものではない。既存 kuu core をバックエンドとし、struct-first を DX 層として被せる方向が現実的。具体的には:

1. ユーザーは struct を定義する（DX 層）
2. DX 層が struct フィールドから kuu core の Opt[T] 定義を自動生成する
3. kuu core がパースを実行し、結果を struct に注入する
4. ユーザーは struct フィールドで結果にアクセスする

これにより `.get().unwrap()` 解消の UX 改善と、kuu core のヘルプ生成・グローバルオプション・制約検証等の機能を両立できる。

## 未実装・課題

- ヘルプ表示: PathEntry にメタデータ追加が必要
- positional 引数: rest でカバーしているが専用対応なし
- エラー報告: 位置情報やコンテキストなし
- バリデーション: required, exclusive, at_least_one 等の制約
- short オプション結合: `-dit` → `-d -i -t`
- 多段階パースの制約: vp_parse 単体ではネストしたサブコマンド（例: `compose up`）を扱えない。ルートレベルでサブコマンドを検出し残り引数をバッファに格納、その後バッファを別の vp_parse に渡す手動多段階パースが必要。3階層以上では煩雑さが顕著
- グローバルオプションのサブコマンド内での使用が未対応: サブコマンドに分岐した後はグローバルオプション（`--debug` 等）を認識しない。サブコマンド内でもグローバルオプションを使うには paths に含める等の対応が必要
- `--` (dashdash) separator 未対応: `--` 以降を全て positional 引数として扱う機能がない
