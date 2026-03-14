# sf-b-ref: Ref バインド方式 struct-first CLIパーサ PoC

## 概要

ユーザーの struct フィールドを `Ref[T]` にし、kuu core のパーサと直接バインドする Ref バインド方式 CLIパーサ PoC なのだ。

## デモ: git 風 CLI

```moonbit
struct GitGlobal {
  verbose : Ref[Bool]
  config_entries : Ref[Array[String]]
}

let g = GitGlobal::new()
let b = RefBinder::new()

// Ref[T] を直接ターゲットにバインド
b.flag(name="verbose", target=g.verbose, global=true)
b.append_string(name="config", target=g.config_entries, global=true)

// サブコマンドのオプションは sub_xxx メソッドでバインド
let clone_parser = b.sub(name="clone")
let url : Ref[String] = { val: "" }
b.positional(parser=clone_parser, name="url", target=url)
b.sub_int(parser=clone_parser, name="depth", target={ val: 0 })

b.parse(["--verbose", "clone", "--depth", "3", "https://example.com/repo.git"])
// g.verbose.val == true, url.val == "https://example.com/repo.git"
```

## RefBinder API

| メソッド | ターゲット型 | 説明 |
|---------|------------|------|
| `flag` | `Ref[Bool]` | ブールフラグ |
| `string` | `Ref[String]` | 文字列オプション |
| `int` | `Ref[Int]` | 整数オプション |
| `count` | `Ref[Int]` | カウンター（-vvv） |
| `append_string` | `Ref[Array[String]]` | 複数値 |
| `sub` | — | サブコマンド（raw Parser を返す） |

## sf-a-closure との違い

```moonbit
// sf-a-closure: setter クロージャを渡す
sf.flag(name="verbose", setter=fn(v) { config.verbose = v })

// sf-b-ref: Ref[T] を直接渡す
b.flag(name="verbose", target=config.verbose)
```

## ビルド・テスト

```bash
just test    # 33テスト実行
just build   # ビルド
just check   # 型検査
```

## ドキュメント

- [DESIGN.md](docs/DESIGN.md) — 設計書
- [DR-001](docs/decision-records/DR-001-ref-bind-approach.md) — Ref バインド方式の設計判断
