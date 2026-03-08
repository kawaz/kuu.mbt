# examples/20260307-mygit

2026-03-07 に作成された git 風サンプル CLI の歴史的スナップショット。

kuu.mbt の `sub()` API 導入直後の状態を保存している。
今後の API 変更でビルドが通らなくなる可能性があるため、動作する状態をタグ `examples-20260307-mygit` として固定した。

## ビルド・実行

```bash
moon build
moon test
moon run examples/20260307-mygit
```

## この時点の API の特徴

このスナップショットは以下の3つの API 改善が導入された直後のバージョンを使用している:

| API | 概要 |
|---|---|
| `Parser::sub()` | `cmd()` のラッパー。子 Parser を直接返し、Ref ボイラープレートを不要にした |
| `Opt::get()` | 統一的な値取得メソッド。`Parser::get()` / `ParseResult::get()` は deprecated に |
| `Parser::require_cmd()` | サブコマンド必須化。引数なし実行時に `ParseError` を返す |

## Before/After: cmd() + Ref API → sub() API

このサンプルは最初 `cmd()` API で書かれ、その後 `sub()` API で書き直された。
以下は書き直し時のドッグフーディングで得られた知見の記録。

### Before (cmd + Ref パターン)

```moonbit
// 全サブコマンドの全オプションに Ref 宣言が必要
let clone_url : Ref[@core.Opt[String]?] = { val: None }
let clone_dir : Ref[@core.Opt[String]?] = { val: None }
let clone_depth : Ref[@core.Opt[Int]?] = { val: None }
let clone_branch : Ref[@core.Opt[String]?] = { val: None }

let _clone_cmd = p.cmd(name="clone", setup=fn(child) {
    clone_url.val = Some(child.positional(name="url"))
    clone_dir.val = Some(child.positional(name="directory"))
    clone_depth.val = Some(child.int_opt(name="depth", default=0))
    clone_branch.val = Some(child.string_opt(name="branch", default=""))
})

// 使用時: 4段 unwrap
clone_url.val.unwrap().get().unwrap()
```

### After (sub パターン) -- 現在のコード

```moonbit
let clone = p.sub(name="clone", description="Clone a repository")
let clone_url = clone.positional(name="url", description="Repository URL")
let clone_dir = clone.positional(name="directory", description="Target directory")
let clone_depth = clone.int_opt(name="depth", default=0, value_name="N")
let clone_branch = clone.string_opt(name="branch", default="", short='b')

// 使用時: 1段 unwrap
clone_url.get().unwrap()
```

### 改善効果

| 指標 | Before (cmd + Ref) | After (sub) |
|---|---|---|
| Ref 宣言数 | 24個 | 0個 |
| unwrap チェーン | `.val.unwrap().get().unwrap()` (4段) | `.get().unwrap()` (1段) |
| `let mut` (serial 内) | なし (全て Ref) | 4個 (serial のみ) |
| コード全体に占めるボイラープレート | 約半分 | ほぼゼロ |

## 発見事項: Ref ボイラープレート地獄

ドッグフーディングで発見された最大の問題。

`cmd()` はクロージャ(`setup`)の中で子 Parser を受け取る設計だったため、
クロージャ内で定義した `Opt` を外のスコープで使うには `Ref[@core.Opt[T]?]` による脱出が必要だった。

**具体的な苦痛:**
- 8サブコマンド x 平均3オプション = **24個の Ref 宣言**
- 各 Ref は `{ val: None }` で初期化 → クロージャ内で `Some(...)` に設定 → 使用時に `.val.unwrap()` で取り出し
- アクセスチェーンが `.val.unwrap().get().unwrap()` の4段になり、コードの可読性が著しく低下
- **コード全体の約半分がこのボイラープレートで占められた**

**解決:** `sub()` は `cmd()` の薄いラッパーとして実装された。
内部では同じクロージャ機構を使いつつ、`sub()` が子 Parser を直接返すことで
ユーザーはクロージャを意識する必要がなくなった。

```moonbit
// sub() の内部実装（概念）
pub fn Parser::sub(...) -> Parser {
  let child_ref : Ref[Parser?] = { val: None }
  ignore(self.cmd(name=name, setup=fn(child) { child_ref.val = Some(child) }, ...))
  child_ref.val.unwrap()
}
```

## 網羅している API 機能

このサンプルは kuu.mbt の主要な公開 API をほぼ全て使用している:

- **オプション型:** `flag`, `string_opt`, `int_opt`, `count`, `append_string`, `rest`, `positional`
- **サブコマンド:** `sub()` (ネスト含む: `remote add`, `remote remove`, `stash push/pop/list`)
- **制約:** `exclusive()`, `required()`, `require_cmd()`
- **フィルタ:** `Filter::trim().then(Filter::non_empty())`
- **特殊機能:** `implicit_value`, `choices`, `hidden`, `global`, `aliases`, `serial`, `dashdash`, `default=true` (flag)
- **結果ナビゲーション:** `result.child("name")` によるサブコマンド分岐

## 動作確認方法

このタグにチェックアウトすればビルド・テストが可能:

```bash
# jj の場合
jj new examples-20260307-mygit

# git の場合
git checkout examples-20260307-mygit
```
