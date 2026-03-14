# struct-first CLI パーサ PoC: C. Trait ベース方式

## 背景

kuu は MoonBit 製 CLI 引数パーサライブラリ。現行は「パーサ定義 → Opt[T] → .get().unwrap()」のボトムアップ方式。

新しいアイデア「struct-first」:
- アプリの struct が先にある
- CLIパーサはその struct に値を直接注入する
- 取り出し問題（.get().unwrap() の嵐）が構造的に消滅

ユーザーの原文:
> アプリ作者はみんな、値を渡したいんじゃなくて値を受け取りたいんだよ。つまりアプリが必ず先にある。
> そして欲しいデータの型完全なstructも実は必ずアプリ作者側が持ってるんだよ既に。

## このアプローチ: Trait ベース方式

`Parseable` trait を定義し、ユーザー struct に impl させる。

```moonbit
trait Parseable {
  register(Self, FieldRegistry) -> Unit
}

struct AppConfig {
  mut verbose : Bool
  mut name : String
}

impl Parseable for AppConfig with register(self, reg) {
  reg.flag(name="verbose", apply_fn=fn(v) { self.verbose = v })
  reg.string(name="name", apply_fn=fn(v) { self.name = v })
}

// 使用
let config = AppConfig::default()
parse_into(args, config)  // config にもう値が入ってる！
```

## 検証結果

全技術的疑問をクリア:

| 項目 | 結果 |
|---|---|
| MoonBit struct の mut フィールド | ✅ |
| Trait impl 内での self.field 変更 | ✅ クロージャキャプチャ経由 |
| FieldRegistry で kuu core と橋渡し | ✅ applier パターン |
| サブコマンドネスト | ✅ 子 applier の親伝搬 |
| positional / rest / append | ✅ |
| global オプション | ✅ |

## デモ内容

docker-like CLI を実装:
- `docker run --detach --name web --publish 8080:80 nginx -- echo hello`
- `docker build --tag myapp:v1.0 --no-cache .`
- `docker ps --all --quiet`
- グローバルオプション: `--verbose`, `--log-level`

## 実行方法

```bash
moon run examples/20260314-sf-c-trait
```

## ファイル構成

```
examples/20260314-sf-c-trait/
  main.mbt     # PoC 実装 + テストケース
  moon.pkg     # パッケージ設定
  README.md    # 本ファイル
  docs/
    DESIGN.md                                  # 設計書
    decision-records/
      DR-001-trait-based-struct-first.md        # 技術検証結果
```

## 結論

MoonBit の trait + mut フィールドで struct-first CLI パーサは**完全に実現可能**。
FieldRegistry パターンにより kuu core を無修正のまま高レベル DX を提供できる。

Rust の `clap::Parser` derive に相当することを、MoonBit では trait の手動 impl で実現できた。
