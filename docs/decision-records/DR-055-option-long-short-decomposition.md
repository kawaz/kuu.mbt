# DR-055: register_option の option/long/short 分解

## 背景

DR-053 で構想した option/long/short コンビネータの分解を実装する。現在の `register_option` が long/short/variation の全展開を一体で行っているが、これを独立した内部関数に分解する。

## 現在の構造

```
register_option(name, aliases, shorts, variations, make_main_node, ...)
  → expand_and_register()
    → make_long_nodes(make_main_node) で --name ノード生成 + variation 展開
    → make_long_nodes(make_main_node) で --alias ノード生成 + variation 展開
    → shorts の各 grapheme を -c ノード生成
  → OptMeta 登録
  → NodeTemplate 保存
  → Opt[T] 返却
```

## 分解後の構造

```
register_option（= option の責務）
  → expand_long(name, aliases, variations, make_main, make_var) → Array[ExactNode]
  → expand_short(shorts, make_main) → Array[ExactNode]
  → 全ノードを parser.nodes に登録
  → OptMeta 登録
  → NodeTemplate 保存
  → Opt[T] 返却
```

## 実装計画

### Phase 1: 内部関数の抽出

1. `expand_long(name, aliases, variations, make_main, make_var, committed) -> Array[ExactNode]`
   - `--{name}` の main ノード生成（wrap_node_with_set）
   - variations 展開（expand_variation_nodes）
   - aliases の各 `--{alias}` も同様に処理
   - 戻り値: 全 long ノードの配列

2. `expand_short(shorts, make_main, committed) -> Array[ExactNode]`
   - shorts 文字列を grapheme 分解
   - バリデーション（"-", whitespace, NUL 拒否）
   - 各文字を `-{c}` ノードに変換
   - 戻り値: 全 short ノードの配列

3. `register_option` をリファクタ
   - expand_long + expand_short を呼び出し、結果を nodes に登録
   - OptMeta・NodeTemplate・Opt 生成は従来通り

### Phase 2: テスト

既存テスト（695件）が全て通ることを確認。内部リファクタなので新規テストは不要。

## 設計判断

- **外部 API は変更しない**: 現時点では内部リファクタのみ。将来 public API 化は別 DR
- **expand_long / expand_short は priv 関数**: parser.mbt 内の private ヘルパー
- **段階的**: まず内部分解、その後 public API 化を検討
