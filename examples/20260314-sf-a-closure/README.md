# struct-first CLI パーサ PoC: A. クロージャ Setter 方式

## 背景

kuu は MoonBit 製 CLI 引数パーサライブラリ。現行は「パーサ定義 → Opt[T] → .get().unwrap()」のボトムアップ方式。

新しいアイデア「struct-first」:
- アプリの struct が先にある
- CLIパーサはその struct に値を直接注入する
- 取り出し問題（.get().unwrap() の嵐）が構造的に消滅
- サブコマンドのネスト = struct のネスト

ユーザーの原文（殴り書き）:
> アプリ作者はみんな、値を渡したいんじゃなくて値を受け取りたいんだよ。つまりアプリが必ず先にある。
> そして欲しいデータの型完全なstructも実は必ずアプリ作者側が持ってるんだよ既に。

## このアプローチ: クロージャ Setter 方式

**核心**: mut struct フィールドへの setter クロージャをパーサに渡す。パーサが引数をパースしたら、setter 経由で直接 struct を書き換える。

```moonbit
let config = { verbose: false, name: "", count: 0 }
let sf = StructFirst::new()
sf.flag(name="verbose", setter=fn(v) { config.verbose = v })
sf.string_opt(name="name", default="world", setter=fn(v) { config.name = v })
sf.int_opt(name="count", default=1, setter=fn(v) { config.count = v })
sf.parse(args)
// → config にもう値が入ってる！
```

## 検証結果

全項目 **成功**。20テスト全PASS。

| 検証項目 | 結果 | 備考 |
|---|---|---|
| mut struct + クロージャキャプチャ | OK | MoonBit の struct は参照型 |
| 型消去（`() -> Unit` 配列） | OK | setter に値を束縛して統一的に扱える |
| kuu Parser + setter ラッパー | OK | StructFirst ラッパーで実現 |
| サブコマンドネスト（Docker 風 3 階層） | OK | run / compose up で検証 |

### 技術的疑問への回答

1. **mut struct フィールドのクロージャキャプチャ**: 動く。MoonBit の struct は参照型
2. **クロージャの型消去**: `() -> Unit` に統一可能。setter に値を束縛するだけ
3. **ライフタイム**: 問題なし。GC 管理で参照関係は自動

## ビルド＆テスト

```bash
just run    # ビルド＋実行
just test   # テスト実行
```

## 詳細

- [DESIGN.md](docs/DESIGN.md) — 設計とアーキテクチャ
- [DR-001](docs/decision-records/DR-001-closure-setter-poc-results.md) — 検証結果の詳細

## 既存 kuu の使い方参考

`examples/20260308-mydocker/main.mbt` を参照。
パッケージ: `import { "kawaz/kuu/src/core" }` + `options("is-main": true)`
