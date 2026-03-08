# DR-029: 言語境界を越える Serialize/Deserialize 設計構想

## 背景

kuu は MoonBit core + 多言語 DX レイヤー（DR-027）の構成。各言語の DX レイヤーが core とやりとりする際、言語境界を越えるデータ表現が必要。

## 設計方針

### 1. ParseResult の extract()

- ParseResult から `extract()` で、Parser・Opt・Ref などの参照関係を切った純粋データ構造に変換
- 関数参照（getter, is_set 等のクロージャ）を含まない、値だけのスナップショット
- JSON にマッピング可能な形式

### 2. 境界でやりとりする型

- プリミティブ型（String, Int, Double, Bool）
- 基本的なコンテナ型（Map, List/Array, Date 等）
- これらの組み合わせで十分。カスタム型は DX レイヤー側で変換する

### 3. Opt コンビネータの AST 化

- 各言語の複数種の DX API（例: TS-schema, TS-builder, TS-valibot）が異なるインターフェースを提供しても、最終的にはすべて Opt コンビネータのコンポジションに落とし込む
- そのコンポジション（オプション定義のツリー構造）を AST 的な形で serialize し、言語境界を越える
- core 側は AST を受け取って parse を実行し、結果を serialize して返す
- DX レイヤーは自由に API デザインでき、core との結合は AST 形式で統一される

### 4. デバッグ・テストへの応用

- serialize 形式はデバッグ出力としても有用
- テスト時に期待値を JSON で記述できる
- 内部状態の可視化にも活用可能

## 現状の設計との関係

- 現在の `Opt[T]` は `getter: () -> T` などクロージャを持ち、そのままでは serialize 不可
- `extract()` で値のスナップショットを取る設計なら、現在の Builder パターンを変更する必要はない
- DR-025 の `custom[T]` / `register_option` も阻害要因なし

## 実装タイミング

- 多言語 DX レイヤーの実装フェーズ（DR-027 の具体化時）
- core の API が安定した段階で着手

## 未決事項

- AST の具体的な型定義（OptDef, CmdDef 等のデータ型）
- serialize フォーマット（JSON が第一候補、MessagePack 等も検討余地）
- Wasm 境界での受け渡し方式（線形メモリ上の JSON string か、Wasm component model の型か）
- Date 等の型の serialize 表現
