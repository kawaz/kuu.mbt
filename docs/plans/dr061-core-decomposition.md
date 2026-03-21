# DR-061 Core 合成的分解 — 実装計画

## 目標

DR-061 の合成モデルを段階的に Core に導入する。外部 API を維持しつつ内部を合成構造に変更。

## MoonBit 制約

- 別パッケージの型にメソッド追加不可 → src/core/ 内でのファイル分割が唯一の選択肢
- 低レイヤ API は core パッケージ内に同居（論理的レイヤ分離のみ）

## codex レビュー指摘（致命的3件）

1. **append_dashdash 削除と外部API維持が矛盾** → deprecated ラッパーとして pub fn を維持し、内部のみ合成に変更
2. **rest の合成化工程が欠落** → Phase 3 に rest を ExactNode レベルで合成可能にするステップを追加
3. **`--` 既定セパレータとの衝突** → Parser::new(dashdash=true) の install_separator_node と、ユーザー定義 dashdash() の register_dashdash_node の二重登録問題を Phase 3 で明示的に解消

## Phase 構成

### Phase 0: 基盤整備（リスク: 低）

**Step 0-1: value() プリミティブ**
- ValCell + Accessor の生成を名前付き内部関数に抽出
- 現在: ValCell::new + ValCell::accessor の組み合わせが各コンビネータに散在
- 対象: types.mbt

**Step 0-2: exact() の独立関数化**
- make_flag_node の最小化版（リテラルマッチのみ、consumed=1）
- 対象: nodes.mbt

### Phase 2: parallel 抽象（リスク: 中）— Phase 1 より先

**Step 2-1: make_parallel_cell 導入**
- Opt[Array[T]] の配列化パターンを抽出: (valcell, push_fn, reset_fn)
- append と rest の共通基盤

**Step 2-2: append を parallel 上に再実装**
- ~30行削減（共通化）

### Phase 1: ExactNode-serial（リスク: 中）

**Step 1-1: make_serial_node 導入**
- 子ノード列を順に走査する ExactNode を生成
- consumed = 全子ノードの consumed 合計

### Phase 3: dashdash の合成分解（リスク: 高）

**Step 3-1: rest を ExactNode レベルで合成可能にする**
- 現在 rest は PositionalEntry ベース（P フェーズ専用）
- ExactNode レベルの rest（OC フェーズで使える）を導入
- dashdash 合成に必要

**Step 3-2: install_separator_node との衝突解消**
- Parser::new(dashdash=true) は install_separator_node で `--` を force_unclaimed に転送
- ユーザー定義 dashdash() は register_dashdash_node で重複チェック付き登録
- 両者が衝突しないよう、dashdash 合成時は install_separator_node を置き換えるか共存させる

**Step 3-3: dashdash を serial(exact, rest) で再実装**

### Phase 4: flag/count の合成化（リスク: 高）

- flag を custom + implicit_value ベースに再実装（variation 処理が要注意）
- count も同様

### Phase 5: append 系シュガー整理（リスク: 低）

- append_dashdash は deprecated ラッパーとして pub fn を維持（内部は parallel + dashdash 合成に変更）
- append_string/int/float は既に append のシュガーなので維持

## 実施順序

Phase 0 → Phase 2 → Phase 1 → Phase 3 → Phase 4 → Phase 5

Phase 2 先行理由: parallel は既存 append の内部リファクタで済み外部 API 不変。

## 行数見込み

| 対象 | 現在 | 分解後 | 備考 |
|---|---|---|---|
| flag | ~148行 | ~80行 | variation を adjust 合成に委譲 |
| count | ~95行 | ~50行 | flag と同構造 |
| append | ~89行 | ~50行 | parallel 基盤への委譲 |
| dashdash | ~78行 | ~30行 | serial + exact + rest |
| append_dashdash | ~42行 | ~15行 | deprecated ラッパー化（内部合成） |
| 新規プリミティブ | 0行 | ~80行 | value, exact, serial-node, parallel |
| **合計** | ~647行 | ~500行 | **約23%削減** |
