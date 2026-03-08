# DR-026: sub() API / require_cmd() / parse 単一呼び出し制約

## sub() — cmd() のシュガー

### 背景

cmd() はコールバック方式で子パーサを構築する:

```moonbit
let serve = p.cmd(name="serve", setup=fn(child) {
  let port = child.int_opt(name="port", default=8080)
  // port は closure 内に閉じる → 外で使うには Ref でエスケープが必要
})
```

この方式では子パーサで定義した Opt を外部から参照するのに Ref ラッパーが必要で、ボイラープレートが増える。

### 決定

cmd() を内部で呼び、子 Parser を直接返す sub() を追加:

```moonbit
pub fn Parser::sub(self, name~, description?, dashdash?) -> Parser

// 使用例:
let clone = p.sub(name="clone", description="Clone a repo")
let url = clone.positional(name="url")
let depth = clone.int_opt(name="depth", default=0)
// parse 後: url.get(), depth.get() — Ref 不要
```

### 実装

cmd() の setup コールバック内で child_ref に子パーサを保存し、返す:

```moonbit
pub fn Parser::sub(self, name~, description?, dashdash?) -> Parser {
  let child_ref : Ref[Parser?] = { val: None }
  ignore(self.cmd(name~, description~, dashdash~, setup=fn(child) {
    child_ref.val = Some(child)
  }))
  child_ref.val.unwrap()
}
```

cmd() の全機能（global ノード伝播、ExactNode 登録、OptMeta 登録）を継承。

### cmd() vs sub() の使い分け

- **sub()**: 通常のサブコマンド定義。Opt をフラットに扱える
- **cmd()**: Opt[Bool] が必要な場合（サブコマンド選択の is_set チェック等）

---

## require_cmd() — サブコマンド必須制約

### 背景

引数なし実行時にヘルプを表示する CLI パターンの実現。サブコマンドが1つも選択されなかった場合にエラーにしたい。

### 決定

post_hooks ベースの制約チェックとして実装:

```moonbit
pub fn Parser::require_cmd(self : Parser) -> Unit {
  self.post_hooks.push(fn() raise ParseError {
    if self.children.length() == 0 {
      raise ParseError(ParseErrorInfo::{
        message: "subcommand required",
        help_text: self.generate_help(),
      })
    }
  })
}
```

### 設計判断

- **post_hooks ベース**: exclusive/required と同じパターン（DR-021）。専用の仕組み不要
- **ParseError（HelpRequested でなく）**: サブコマンド未指定は usage エラーであり、正常なヘルプ要求ではない
- **help_text 自動付与**: エラー時にヘルプを表示するため、generate_help() を呼ぶ

---

## parse() 単一呼び出し制約

### 背景

Parser::parse() を同一インスタンスで2回呼ぶと、install ノード（eq_split, short_combine）が重複登録され、内部状態が不整合になる。

### 決定

parse_raw の冒頭で parsed フラグをチェックし、2回目の呼び出しを禁止:

```moonbit
if self.parsed.val {
  raise parse_error("Parser::parse can only be called once")
}
```

### 理由

- install_eq_split_node / install_short_combine_node は nodes に追加するため、2回目は重複ノードが生成される
- ExactNode の内部状態（Ref[T] の値）がリセットされないため、2回目のパースで前回の値が残る
- 「1 Parser = 1 parse」の単純なライフサイクルを強制することで、状態管理の複雑さを排除
