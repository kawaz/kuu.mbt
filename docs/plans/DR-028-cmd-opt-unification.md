# DR-028: cmd → Opt[CmdResult] 統合

## ゴール

cmd の返り値を `Opt[Bool]` から `Opt[CmdResult]` に変更し、opt と同じ概念に統合する。

## 変更内容

### 1. CmdResult 型追加（types.mbt）

```moonbit
pub(all) struct CmdResult {
  name : String
  parser : Parser
}
```

- `name`: 選択されたコマンド名
- `parser`: 子パーサ（子オプションへのアクセス用）

### 2. cmd の返り値変更（commands.mbt）

```moonbit
// 変更前
pub fn Parser::cmd(...) -> Opt[Bool]

// 変更後
pub fn Parser::cmd(...) -> Opt[CmdResult]
```

内部変更:
- `cell: Ref[Bool]` → `cell: Ref[CmdResult?]`（None = 未選択）
- `getter: fn() -> Bool { cell.val }` → `getter: fn() -> CmdResult { cell.val.unwrap() }`
- commit 時: `cell.val = true` → `cell.val = Some(CmdResult { name: cmd_name, parser: child })`
- reset 時: `cell.val = false` → `cell.val = None`

### 3. sub の内部更新（commands.mbt）

sub は cmd のラッパー。cmd の返り値が変わるので内部の ignore も更新。
sub 自体の返り値（Parser）は変更なし。

### 4. テスト修正（parse_wbtest.mbt）

cmd の `Opt[Bool]` を使っているテストを `Opt[CmdResult]` に更新:
- `p.get(serve)` → `Some(true)` だったのを `Some(CmdResult{...})` に
- `inspect` の content 文字列を更新
- `Opt[Bool]` → `Opt[CmdResult]` での型変更に伴う修正

## 影響範囲

- commands.mbt: cmd, sub
- types.mbt: CmdResult 追加
- parse_wbtest.mbt: cmd 関連テスト
- access.mbt: 変更なし（Opt[T].get() は多相なので対応済み）
- help.mbt: OptKind::Command は変更なし

## sub との関係

sub（Parser を直接返す）は変更なし。sub は子パーサに直接オプション定義できる
convenience API として維持。cmd はコマンド選択の有無を `get() → CmdResult?` で
判定できるセマンティクスを提供。
