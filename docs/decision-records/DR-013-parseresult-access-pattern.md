---
type: decision
---

# DR-013: ParseResult アクセスパターン設計

ParseResult ベースの階層的結果アクセスを追加し、複数のアクセス口を提供する設計判断の記録。

## 経緯

Step 1-12 の実装完了後、結果アクセスの API について議論。現行の `Parser::get(opt) -> T` は parse 後なら動くが、追加のアクセス手段が必要:

1. サブコマンドの結果にアクセスする手段が不足
2. パース結果の構造を反映した階層的ナビゲーションがない
3. cobra-style の `opt.get() -> T?` も提供したい

## 議論ログ

### ユーザー発言: ParseResult の提案

> port.get() → T? で、T? なのがcobraスタイルの良さのキモ
> port は Opt[T] で parser に定義のために渡すんだけど例えばport.get()はparserの持つインスタンスIDでの結果取得。
> parserMap みたいなやつ（Map[Int, scope_info]）を持たせてopt.idから自分がスコープに入ってるparserやresultmapを引けばいけるかも？
>
> あとは parseResult.get(port) -> T? はparseResultからも取れる。
> parseResult.get("serve") -> ParseResult? でサブコマンド名(key)でナビゲーション。ネストした.get("sub")でツリーを辿れる。

### ユーザー発言: ParseResult の型

> で ParseResult って内部はflag/single/appendの値を持つ ParseResult::One(T) だったりcmd名からParseResult引くための ParseResult::Map_(Map[String, ParseResult]) だったりポジショナルで indexで引くための ParseResult::List_(Array[ParseResult]) だったりする。enumだけどMoonBitだとenumにメソッド書けないのでstructにする。

### ユーザー発言: sugar メソッドの整理

> ParseResult は as_map() もという話をしたとこですが冗長さを抑えるシュガーとして child(key) {self.as_map().get(key)} ということ？ だとすると as_list()[0] に対応する at(0) とかも用意する？
>
> port.get() と parser.get(port) これは parseresult.get(port) の間違い？
>
> getの名前についてはもっとほかの名前のメソッドで同名ならまだしも、型によって get() / get(key) はよくあることなのでそこは混乱しないでしょう。

## 設計決定

### 1. ParseResult 型

ParseResult は enum を持つ struct（MoonBit で enum にメソッドを書けないため）。

```moonbit
enum ParseResultKind {
  One(???)        // 単一値（flag/single/append 等）
  Map_(Map[String, ParseResult])  // サブコマンド等の名前キー
  List_(Array[ParseResult])       // serial 等の位置キー
}

struct ParseResult {
  kind : ParseResultKind
  // + opt_id → 値 の内部マップ（get(Opt[T]) 用）
}
```

### 2. アクセス API（3つの口）

結果へのアクセス口は3つ。コンテキストに応じて自然に使い分けられる:

| メソッド | 戻り値 | 説明 |
|---------|--------|------|
| `Parser::get(Opt[T])` | `T?` | parse 前は None、parse 後はスコープ内なら Some(T) |
| `Opt[T]::get()` | `T?` | cobra-style。parserMap 経由でスコープ内結果取得 |
| `ParseResult::get(Opt[T])` | `T?` | ParseResult からの型付きアクセス |
| `ParseResult::as_map()` | `Map[String, ParseResult]?` | Map 表現の取得（プリミティブ） |
| `ParseResult::as_list()` | `Array[ParseResult]?` | List 表現の取得（プリミティブ） |
| `ParseResult::child(key)` | `ParseResult?` | `as_map().get(key)` のシュガー |
| `ParseResult::at(index)` | `ParseResult?` | `as_list()[index]` のシュガー |

3つとも `T?` を返す。parse 前やスコープ外なら `None`。

### 3. parserMap 方式

`Opt[T]::get() -> T?` を実現するため、Parser が `Map[Int, scope_info]` を保持。
opt.id からそのスコープの parser/resultmap を引き、スコープ内なら `Some(value)`、スコープ外なら `None` を返す。

### 4. 命名の決定

- MoonBit はメソッドオーバーロード不可 → `ParseResult` 上で `get(Opt[T])` と `get(String)` は共存不可
- `child("serve")` で名前ナビゲーション、`get(port)` で型付き値取得と分離
- `get` の名前: `Opt[T]::get() -> T?` と `ParseResult::get(Opt[T]) -> T?` は別型のメソッドなので混乱しない
- `at(i)` は `as_list()[i]` のシュガー。必要になったら足す方針

### 5. 現行 API との関係

- `Parser::get(opt) -> T`（現行）は維持。parse 後なら問題なく動く
- 新しいアクセス口（`opt.get()`, `result.get(opt)`, `child`/`at`）を追加で提供
- 設計上の問題が出たら削除を検討する方針（リリース前なので後方互換は不要）

## 選択理由

- cobra-style の `opt.get() -> T?` は利用側のコードが簡潔で直感的
- 複数のアクセス口はコンテキストに応じた自然な使い分けを提供
- 階層ナビゲーション（child/at）でサブコマンド結果への自然なアクセスを提供
- as_map/as_list がプリミティブ、child/at がシュガーという明確なレイヤー分け

## 不採用としたもの

- `ParseResult::get(String)` でサブコマンドナビゲーション → `get(Opt[T])` とオーバーロード衝突（MoonBit 制約）

## 実装注記（2026-03-07 更新）

実装は本 DR の設計から以下の点で変更されている。

### parserMap 方式 → Parser.parsed: Ref[Bool] 方式

本 DR で提案した `Map[Int, scope_info]` による parserMap 方式は採用せず、`Parser.parsed: Ref[Bool]` フラグで parse 済みかどうかを管理する方式に変更。各 Opt が自身の Ref[T] セルを直接参照し、parsed フラグで parse 前/後を判定する。

### ParseResultKind::One

`ParseResultKind::One(???)` は値を持たない形で実装。値の保持は Opt 内の Ref[T] セルが担い、ParseResultKind::One は「この位置に単一値が存在する」というマーカーとして機能する。

### アクセス API の現状

| メソッド | 実装状態 |
|---------|---------|
| `opt.get() -> T?` | 実装済み — parsed ベースで parse 前は None |
| `parser.get(opt) -> T?` | 実装済み |
| `result.get(opt) -> T?` | 実装済み — parser.get に委譲 |
