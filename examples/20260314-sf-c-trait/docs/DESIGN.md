# struct-first CLI パーサ PoC: C. Trait ベース方式

## 概要

kuu (MoonBit製CLIパーサ) の DX レイヤーとして「struct-first」アプローチの技術検証。
ユーザーが定義した struct に trait を impl するだけで、CLI引数パースと値注入が完結する方式。

## アーキテクチャ

```
ユーザーコード                    フレームワーク層                kuu core
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐
│ struct定義   │     │ Parseable trait   │     │ Parser      │
│ + mut fields │ ──> │ FieldRegistry    │ ──> │ Opt[T]      │
│ + impl       │     │ parse_into()     │     │ ExactNode   │
└─────────────┘     └──────────────────┘     └─────────────┘
                          │                        │
                    apply クロージャ          parse(args)
                          │                        │
                    struct フィールドに値注入  ◄─────┘
```

## コンポーネント

### Parseable trait

```moonbit
trait Parseable {
  register(Self, FieldRegistry) -> Unit
}
```

ユーザーが struct に impl する唯一のインターフェース。register 内で FieldRegistry のメソッドを呼んでフィールドを登録する。

### FieldRegistry

kuu core の Parser をラップし、以下を提供:

| メソッド | 用途 |
|---|---|
| `flag()` | Bool フラグ |
| `string()` | String オプション |
| `int()` | Int オプション |
| `append_string()` | 複数値収集 |
| `positional()` | 位置引数 |
| `rest()` | 残り全引数 |
| `sub()` | サブコマンド |
| `require_cmd()` | サブコマンド必須 |

内部で applier クロージャを蓄積し、parse 後に一括実行して struct フィールドに値を注入する。

### parse_into

```moonbit
fn[T : Parseable] parse_into(args, target) -> Unit raise ParseError
```

1. Parser 生成
2. FieldRegistry 作成
3. target.register(registry) で定義
4. parser.parse(args) で解析
5. registry.apply_all() で値注入

## 検証結果

| 検証項目 | 結果 |
|---|---|
| mut フィールド | ✅ 動作 |
| trait impl からの mut 変更 | ✅ クロージャ経由で動作 |
| FieldRegistry 橋渡し | ✅ applier パターンで実現 |
| サブコマンドネスト | ✅ 子 applier の親伝搬で動作 |
| global オプション | ✅ kuu core の global 伝搬がそのまま動作 |
| positional + rest | ✅ is_set チェックで未指定も正しく処理 |

## デモ: docker-like CLI

以下のサブコマンドを実装:
- `run`: --detach, --name, --publish(multiple), IMAGE(positional), ARGS(rest)
- `build`: --tag, --no-cache, PATH(positional)
- `ps`: --all, --quiet

グローバルオプション: --verbose, --log-level

全7テストケース PASS。

## 制限事項と今後の課題

1. **pub(open) trait**: 外部パッケージからの impl は未検証
2. **カスタムバリデーション**: FieldRegistry に post/choices 対応なし
3. **derive 自動生成**: 現在は手動 impl。将来的に derive マクロがあれば自動化可能
4. **型安全性**: apply_fn の型チェックはコンパイル時に行われるが、フィールド名との対応は手動
