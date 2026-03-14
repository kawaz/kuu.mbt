# sf-b-ref: Ref バインド方式 CLIパーサ PoC

## 概要

ユーザーの struct フィールドを `Ref[T]` にし、kuu core のコンビネータと直接バインドする Ref バインド方式。
pure な struct-first ではなく、`Ref[T]` を介した参照バインドアプローチ。

## コンセプト

```
ユーザー struct (Ref[T] フィールド)
       |
   RefBinder (kuu Parser ラッパー)
       | parse(args) → kuu core parse 実行
       | → copiers 実行（Opt[T].get() → Ref[T].val へコピー）
       |
   Ref[T].val に値が反映
```

## 他方式との比較

| 方式 | バインド手段 | Opt[T] の扱い | struct 定義 |
|------|-------------|---------------|------------|
| sf-a-closure | setter クロージャ | 隠蔽 | `mut` フィールド |
| **sf-b-ref** | **Ref[T] 直接バインド** | **隠蔽** | **`Ref[T]` フィールド** |
| sf-c-trait | Parseable trait | 隠蔽 | trait 実装 |
| raw kuu | なし | 直接操作 | なし |

## 設計

### 1. ユーザーの struct 定義

```moonbit
struct GitConfig {
  verbose : Ref[Bool]
  branch : Ref[String]
  depth : Ref[Int]
  tags : Ref[Array[String]]
}
```

フィールドが `Ref[T]` なので、parse 結果が copier 経由で struct に反映される。

### 2. RefBinder ラッパー

```moonbit
struct RefBinder {
  parser : @core.Parser
  copiers : Array[() -> Unit]
}
```

#### トップレベルオプション（RefBinder 直接メソッド）

- `flag(name, target)` — Ref[Bool] にバインド
- `string(name, target)` — Ref[String] にバインド
- `int(name, target)` — Ref[Int] にバインド
- `count(name, target)` — Ref[Int] にバインド（カウンター）
- `append_string(name, target)` — Ref[Array[String]] にバインド
- `sub(name)` — サブコマンド登録（raw Parser を返す）
- `require_cmd()` — サブコマンド必須制約

#### サブコマンド内オプション（parser 引数付きメソッド）

`sub()` で得た Parser をそのまま渡すことで、サブコマンド内のオプションも Ref バインドできる。

- `positional(parser, name, target)` — サブコマンド内 positional を Ref[String] にバインド
- `sub_flag(parser, name, target)` — サブコマンド内 flag を Ref[Bool] にバインド
- `sub_string(parser, name, target, default="")` — サブコマンド内 string_opt を Ref[String] にバインド（デフォルト値指定可能）
- `sub_int(parser, name, target, default=0)` — サブコマンド内 int_opt を Ref[Int] にバインド（デフォルト値指定可能）
- `sub_count(parser, name, target)` — サブコマンド内 count を Ref[Int] にバインド
- `sub_append_string(parser, name, target)` — サブコマンド内 append_string を Ref[Array[String]] にバインド

### 3. パースフロー

核心: **parse 成功後に copiers が一括実行され、Opt[T] → Ref[T] へ値をコピーする。失敗時は copiers が実行されず Ref は初期値のまま。**

```
1. struct 初期化（Ref[T] フィールドにデフォルト値）
2. RefBinder にバインド登録（各メソッドが copier クロージャを内部に蓄積）
   - copier: fn() { match opt.get() { Some(v) => target.val = v; None => () } }
   - この時点では copier は実行されない（遅延登録）
3. binder.parse(args):
   a. kuu core の parser.parse(args) を実行
   b. パース成功後、蓄積された全 copiers を順に実行
   c. 各 copier が Opt[T].get() で値を取得し Ref[T].val に書き込む
4. struct.field.val で値にアクセス
```

パースエラー時は copiers が実行されないため、Ref の値は初期値のまま保持される。

### 4. sf-a-closure との差異

- **setter クロージャ不要**: `target=config.verbose` だけで済む
- **Ref[T] が型安全な橋渡し**: 型不一致はコンパイルエラー
- **値アクセスは `.val`**: `config.verbose.val` で直接取得
- **struct 定義が Ref[T] を含む**: pure な値型 struct ではない（トレードオフ）

## デモアプリ

`git` 風 CLI をモック。以下のコマンド体系:

```
git [--verbose] [--config KEY=VALUE] <command>
  clone [--depth N] [--branch B] <url>
  commit [--message M] [--all]
  log [--oneline] [--count N]
  remote
    add <name> <url>
    remove <name>
```

## テスト方針

TDD で進行。テストケース:
1. Ref[T] の基本動作確認（flag, string, int, count, append_string）
2. git clone サブコマンド（positional + sub_int + sub_string）
3. git commit サブコマンド（sub_string + sub_flag）
4. git log サブコマンド（sub_flag + sub_int）
5. グローバルオプションの伝搬
6. ネストサブコマンド（remote add/remove、positional メソッド）
7. デフォルト値の確認
8. パースエラー時の Ref 状態
9. エッジケース（負の値、ゼロ、空文字列、複数オプション同時、ショートオプション、require_cmd、サブコマンド内 count/append_string）
