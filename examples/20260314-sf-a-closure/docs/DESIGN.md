# struct-first CLI パーサ PoC: A. クロージャ Setter 方式

## 目的

kuu の新しい DX パターン「struct-first」の技術的検証。ユーザーの struct が先にあり、パーサはその struct に値を直接注入する方式。

## 核心アイデア

現行の kuu API:
```moonbit
let opt = p.flag(name="verbose")
p.parse(args)
let verbose = opt.get().unwrap()  // ← 取り出しの嵐
```

struct-first:
```moonbit
p.flag(name="verbose", setter=fn(v) { config.verbose = v })
p.parse(args)
// config.verbose にもう値が入っている
```

## アーキテクチャ

```
StructFirst (ラッパー)
  ├── parser: @core.Parser     ← kuu core そのもの
  └── copiers: Array[() -> Unit]  ← parse 後に実行する setter クロージャ群
```

### データフロー

```
1. StructFirst::flag(setter=...) → 内部で parser.flag() → Opt[T] 生成
2. copier クロージャ登録: fn() { opt.get() → setter(v) }
3. StructFirst::parse(args) → parser.parse(args) → copiers 一括実行
4. ユーザーの struct に値が反映済み
```

## MoonBit の特性（検証済み）

- **struct は参照型**: クロージャが struct を捕捉すると参照共有。`mut` フィールド書き換えが反映される
- **型消去が自然**: `fn() { config.verbose = true }` と `fn() { config.name = "x" }` を `Array[() -> Unit]` に格納可能

## サブコマンド対応

トップレベルのオプションは StructFirst ラッパーで統一的に扱える。
サブコマンドは kuu の raw API（`parser.sub()` → 子 Parser）を直接使い、copiers に手動登録する混合スタイル:

```moonbit
// StructFirst ラッパー（トップレベル）
sf.flag(name="debug", global=true, setter=fn(v) { config.debug = v })

// raw kuu API（サブコマンド）
let run = sf.parser.sub(name="run")
let detach = run.flag(name="detach")
sf.add_copier(fn() {
  copy_opt(detach, fn(v) { config.run.detach = v })
})
```

## テスト構成（20件）

| テスト | 検証内容 |
|---|---|
| Step 1 (2件) | mut struct + クロージャキャプチャ、型消去 |
| Step 2 (9件) | StructFirst ラッパー（flag/string_opt/int_opt/count/positional/rest/append_string/複合/デフォルト） |
| Step 3 (5件) | Docker 風サブコマンド（run/compose up/グローバルオプション伝搬/最小引数/compose最小） |
| Step 4 (2件) | ネスト struct のクロージャ書き換え、パースエラー時のsetter未適用 |
| Step 5 (2件) | エラーパス |

## 制限事項と課題

1. **サブコマンド判定の隠蔽**: StructFirst ラッパーではサブコマンドのマッチ判定を統一的に扱えない（raw API に fallback）
2. **copiers の全実行**: マッチしなかったサブコマンドの copiers も走る（`opt.get()` が `None` を返すだけなので実害なし、パフォーマンスは微小）
3. **parse 中の struct 参照不可**: copiers は parse 後に実行されるため、パース中に struct を参照しても値は入っていない

## 関連 DR

- [DR-001](decision-records/DR-001-closure-setter-poc-results.md): PoC 検証結果の詳細
