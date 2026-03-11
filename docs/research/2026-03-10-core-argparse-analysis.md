# MoonBit 標準ライブラリ argparse 分析

調査日: 2026-03-10
対象: moonbitlang/core v0.8.3 の argparse パッケージ（/Users/kawaz/.moon/lib/core/argparse）

## 調査の背景と目的

MoonBit v0.8.3 (2026-03-10) で標準ライブラリに `argparse` パッケージが追加された。
kuu.mbt の直接競合が公式から出たことになるため、API 設計・機能・差別化ポイントを分析する。

---

## 1. 基本情報

| 項目 | 値 |
|------|-----|
| 設計思想 | clap (Rust) インスパイア（README に明記） |
| 実装規模 | 約3,600行 |
| テスト | 110件（3,877行） |
| 外部依存 | なし（core 内パッケージのみ） |
| ターゲット | JS / Native / WASM |

## 2. ファイル構成

| ファイル | 行数 | 役割 |
|---|---:|---|
| arg_action.mbt | 44 | `FlagAction` / `OptionAction` enum |
| arg_group.mbt | 60 | `ArgGroup` 構造体 |
| arg_spec.mbt | 300 | `FlagArg` / `OptionArg` / `PositionArg` 構造体 |
| command.mbt | 269 | `Command` 構造体 + `parse` / `render_help` |
| error.mbt | 102 | エラー型 |
| help_render.mbt | 455 | ヘルプテキスト生成 |
| matches.mbt | 59 | `Matches` / `ValueSource` 型 |
| parser.mbt | 686 | メインパーサ |
| parser_globals_merge.mbt | 321 | グローバルオプションの親子間マージ |
| parser_lookup.mbt | 118 | long/short インデックス構築 |
| parser_positionals.mbt | 118 | ポジショナル引数の割り当て |
| parser_suggest.mbt | 115 | タイプミスサジェスト（レーベンシュタイン距離） |
| parser_validate.mbt | 614 | コマンド定義のビルド時バリデーション |
| parser_values.mbt | 319 | 値の代入、env/default 適用、制約チェック |
| value_range.mbt | 41 | `ValueRange` 構造体 |
| runtime_exit*.mbt | ~106 | ターゲット別 exit ヘルパー |
| argparse_test.mbt | 797 | ホワイトボックステスト（25件） |
| argparse_blackbox_test.mbt | 3038 | ブラックボックステスト（84件） |
| README.mbt.md | 545 | ドキュメント（テスト付き） |

## 3. API 設計

### 全体アーキテクチャ

clap (Rust) インスパイアの宣言的 Command ベースパーサ。

```moonbit
let cmd = Command("myapp",
  flags=[FlagArg("verbose", short='v')],
  options=[OptionArg("count", short='c')],
  positionals=[PositionArg("file")],
  subcommands=[Command("run")],
)
let matches = cmd.parse(argv=["..."], env={})
// matches.flags["verbose"]  -> Bool
// matches.values["count"]   -> Array[String]
```

### 公開型

| 型 | 役割 |
|---|---|
| `Command` | コマンド定義。引数定義 + サブコマンドをツリー構造で保持 |
| `FlagArg` | ブールフラグ定義（SetTrue/SetFalse/Count/Help/Version） |
| `OptionArg` | 値付きオプション定義（Set/Append） |
| `PositionArg` | 位置引数定義 |
| `ArgGroup` | 引数グループ（required/exclusive 制約） |
| `ValueRange` | ポジショナル引数の値数制約（lower..upper） |
| `Matches` | パース結果（flags, values, flag_counts, sources, subcommand） |
| `FlagAction` | フラグの動作（SetTrue/SetFalse/Count/Help/Version） |
| `OptionAction` | オプションの動作（Set/Append） |
| `ValueSource` | 値の出所（Argv/Env/Default） |

### 型安全性

**文字列名参照方式**。全ての値は `String` として返される。

```moonbit
matches.flags["verbose"]     // -> Bool?
matches.values["count"]      // -> Array[String]?
```

`Int` や `Bool` への変換はユーザー責任。型安全なアクセサは存在しない。

### サブコマンド

完全対応。ネスト可能。`Matches.subcommand` は `(String, Matches)?`。
`help` サブコマンド自動生成。`subcommand_required` ポリシー。

### グローバルオプション

`global=true` で宣言。321行のマージロジックで複雑なケースに対応:
- 親→子、子→親の双方向マージ
- 値の優先度: Argv > Env > Default
- `Count` フラグは親子の出現回数を合算
- `Append` オプションは親子の値を連結

### 入力フォーマット

- `--long value` / `--long=value`
- `-s value` / `-svalue` / `-s=value`
- `-abc` ショートフラグ結合
- `--` セパレータ対応
- `--no-flag` ネガティブフラグ（`negatable=true`）
- 負の数値（`-9`）のポジショナル認識
- `allow_hyphen_values`

### 制約機能

- `requires` / `conflicts_with`（引数間の依存/排他）
- `ArgGroup`（required/exclusive/requires/conflicts_with）
- `required` フラグ（個別引数）
- `num_args` による値数制約（ValueRange）

### エラーハンドリング

- `raise` で伝搬（MoonBit の error handling）
- タイプミスサジェスト（レーベンシュタイン距離）
- ビルドエラーは遅延評価（`parse` 時に raise）
- Help/Version は例外で制御フロー → `print_and_exit_success`

---

## 4. kuu との機能比較

| 機能 | argparse | kuu | 優位 |
|------|----------|-----|------|
| 型安全性 | 文字列キー、全値 String | `Opt[T]` 型付き参照 | **kuu** |
| カスタム型変換 | なし | `custom[T]` | **kuu** |
| 環境変数 | `env` パラメータ | なし | **argparse** |
| ValueSource 追跡 | Argv/Env/Default | なし | **argparse** |
| Count フラグ (-vvv) | `FlagAction::Count` | なし | **argparse** |
| タイプミスサジェスト | レーベンシュタイン距離 | なし | **argparse** |
| ArgGroup 制約 | 対応 | 個別 exclusive | **argparse** |
| hidden フラグ | 対応 | なし | **argparse** |
| --version 自動処理 | 対応 | なし | **argparse** |
| alias | なし | alias コンビネータ | **kuu** |
| choices 制約 | なし | choices パラメータ | **kuu** |
| post フィルタ | なし | post パラメータ | **kuu** |
| implicit_value | なし | 対応 | **kuu** |
| variation (--no-flag) | negatable=true | variation | 同等 |
| global | 対応（手厚いマージ） | 対応 | 同等 |
| `--` セパレータ | 対応 | dashdash() | 同等 |
| サブコマンド | Command ネスト | cmd/sub | 同等 |
| WASM bridge | なし | JSON schema in/out | **kuu** |
| 多言語展開 | なし | 4層アーキテクチャ構想 | **kuu** |
| テスト | 110件 | 797件 | **kuu** |
| serial (累積) | Append のみ | serial パラメータ | **kuu** |

## 5. 設計思想の根本的な違い

### argparse: 完成品としての CLI パーサ

clap の proven な API デザインを忠実に MoonBit に移植。実用的な CLI を素早く作れることを重視。
環境変数、ValueSource 追跡、ArgGroup、Count フラグ、タイプミスサジェスト、hidden、Version 自動処理など「CLI 実用」の機能が充実。
代償として型安全性は犠牲にしている（全値 String、文字列キーアクセス）。

### kuu: パースエンジンとしての基盤

型安全な `Opt[T]` ベースの設計、コンビネータによる拡張性、WASM bridge による多言語展開。
「パーサのパーサ」としての基盤力に注力。機能の網羅性より、コア設計品質と拡張性を重視。

---

## 6. kuu の差別化戦略

標準ライブラリに argparse が入ったことで、kuu は「標準では足りない人向け」のポジション。

### kuu 固有の価値（argparse にないもの）

1. **型安全性** — `Opt[T]` による型付き参照。コンパイル時のタイプミス検出
2. **カスタム型変換** — `custom[T]` コンビネータ
3. **alias コンビネータ** — 値共有 + is_set 独立の3直交プリミティブ
4. **choices 制約** — 値の選択肢を制限
5. **post フィルタ** — パース後変換
6. **implicit_value** — 値省略時のデフォルト
7. **WASM bridge + 4層アーキテクチャ** — 多言語展開構想

### 取り入れるべき機能（argparse にあって kuu にないもの）

1. **環境変数サポート** — `env` パラメータで環境変数からの値取得
2. **Count フラグ** — `-vvv` のようなカウント型フラグ
3. **タイプミスサジェスト** — レーベンシュタイン距離によるサジェスト
4. **hidden フラグ** — ヘルプに表示しないオプション
5. **--version 自動処理** — バージョン表示の標準化
6. **ValueSource 追跡** — 値がどこから来たかの追跡
7. **ArgGroup** — グループ単位の制約

---

## 7. v0.8.3 の他の変更点（kuu に影響するもの）

- **const 宣言で文字列連結・補間サポート**
- **`for { ... }` 構文が非推奨** → `while true { ... }` へ移行
- **メソッドなしトレイトの自動実装が非推奨**
- **パッケージ内 `impl` 呼び出しでドット記号使用不可**（同一パッケージ内のみ）
- **FFI 生存期間管理が警告→エラー昇格**
- **`supported-targets` 構文改善** — `"+js+wasm+wasm-gc"` 形式
- **`moon ide analyze`** — 公開 API 使用状況分析
