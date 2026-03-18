---
type: implementation
---

# DR-054: float DX層・WASM bridge 対応

## 背景

DR-050 で `float` / `append_float` コンビネータがコア層 (src/core/options.mbt) に追加されたが、DX層 (src/dx/) と WASM bridge (src/wasm/) への反映が漏れている。

## 現状のギャップ

| レイヤー | float | append_float |
|---|---|---|
| Core (options.mbt) | ✓ 実装済み | ✓ 実装済み |
| Core env Phase 2 | ✓ custom() 経由で自動登録 | ✓ custom_append() 経由で自動登録 |
| DX (registry.mbt) | ✗ 未実装 | ✗ 未実装 |
| DX テスト | ✗ なし | ✗ なし |
| WASM bridge | ✗ 未実装 | ✗ 未実装 |

## 実装計画

### 1. DX層: float / float_ref

int / int_ref (L311-373) と同一パターン。型を Int → Double、parser.int → parser.float に変更するだけ。

```
pub fn FieldRegistry::float(self, name~, default~ = 0.0, ..., apply_fn) -> Unit
pub fn FieldRegistry::float_ref(self, name~, default~ = 0.0, ..., apply_fn) -> @core.OptRef
```

### 2. DX層: append_float / append_float_ref

append_int / append_int_ref (L249-307) と同一パターン。型を Array[Int] → Array[Double]、parser.append_int → parser.append_float に変更。

```
pub fn FieldRegistry::append_float(self, name~, ..., apply_fn) -> Unit
pub fn FieldRegistry::append_float_ref(self, name~, ..., apply_fn) -> @core.OptRef
```

### 3. WASM bridge: kind "float"

"int" kind (L291-330) と同一パターン。

- default: Number → Double（JSON Number はそのまま Double）
- implicit_value: Number → Double
- **post フィルタ: `parse_float_post` を新設** — `float_in_range` を処理。`parse_int_post` の Double 版
- extract: Json::number(val)（Double はそのまま、Int の場合は .to_double() が必要だが不要）

### 4. WASM bridge: kind "append_float"

"append_int" kind (L387-415) と同一パターン。各要素を Json::number() で出力。

### 5. WASM bridge: parse_float_post ヘルパー

`parse_int_post` (L117-139) と同一構造。`in_range` → `float_in_range` に変更:

```
fn parse_float_post(obj) -> FilterChain[Double, Double]? {
  // post.float_in_range: [min, max] → Filter::float_in_range(min, max)
}
```

JSON の Number は Double なので `.to_int()` 変換が不要で、むしろ自然。

### 6. テスト

- DX テスト: float/append_float の基本動作、デフォルト値、制約との組み合わせ
- WASM テスト: float/append_float の JSON スキーマ → パース → JSON 結果の往復
- WASM テスト: float_in_range post フィルタの動作検証

## 設計判断

- **新規プリミティブの追加ではない**: int と完全に並行するパターン。設計的な判断は不要
- **env Phase 2**: core の custom()/custom_append() が内部で register_env_applicator を呼ぶため、DX層は特別な対応不要。ただし WASM bridge は env パラメータを JSON スキーマから読まず parser にも渡していない（これは float 固有ではなく全 kind 共通の既知制限、DR-051 参照）。本 DR では float 固有のスコープに限定し、WASM env 対応は別途対応する
- **TDD で進行**: テストファースト
