# DR-009: filter chain の3段 (preSplit / per-item / post)

## 決定

filter chain を3段に分ける:

```
[1] raw string
    ↓ preSplitFilters (string → string, 複数可)
[2] cleaned string
    ↓ multiple.kind に応じて分割
[3] string (単一) or string[] (list) or {k,v}[] (map)
    ↓ type.parse (type registry が要素単位で適用)
[4] T (単一) or T[] or Map<string,T>
    ↓ filters (要素単位、"each" は暗黙)
[5] T or T[] or Map
    ↓ accumulator (multiple.onRepeat)
[6] 累積結果
    ↓ postFilters (累積後の最終値)
[7] 最終値
```

### 各 chain

- **preSplitFilters**: 分割前 string 全体に適用 (`trim`, `regex_match` など)
- **filters**: 分割後の各要素に適用 (`trim`, `non_empty`, `in_range` など)。`each` は暗黙
- **postFilters**: 累積後の最終値に適用 (`sort`, `unique` など)

filter は **純粋関数** (`A → B or ParseError throw`)。コンテキストアクセスなし、アクション指示なし。

## DSL 文法

variant と同じ `<name>:<arg>:<arg>...` 形式:

```
"trim"                  // 引数なし
"in_range:1:65535"      // args ["1", "65535"]
"regex_match:^[a-z]+$"  // args ["^[a-z]+$"]
```

args はすべて string、filter registry 側でキャスト。

複雑な引数はオブジェクト形式に逃げる:
```json
[{"name": "complex_validator", "args": ["abc", "with:colon"]}]
```

## `@base` sentinel

type/ref のデフォルト filter chain を継承する sentinel:

```json
"filters": ["@base", "non_empty"]
```

`@base` の解決順序:
1. ref が指定されていれば → ref 元のそのフィールド
2. なければ → type registry のデフォルト
3. どちらもなければ → 空配列

## 経緯

何段階かの整理:

### 第1段階: 2段 (kuu 現状の pre/post)

kuu には既に pre/post の filter chain がある。これだけだと「分割前 vs 分割後の要素レベル」の区別が曖昧。

### 第2段階: 各要素単位の filter (each コンビネータ)

`each:trim` のような書き方で要素単位の filter を表現。kuu の現状実装 (Filter::each)。

### 第3段階: フェーズを明示

kawaz の整理:
> フィルタは分割前と、分割後のeachで完全に分ける？

3段に分けることでフェーズが明確に。「each」は暗黙にする。

### 第4段階: type.parse の位置

split 後、filters の前に type registry が自動で type.parse を各要素に適用。AST 側で明示書きしない。

### 第5段階: type registry の filters デフォルト

kawaz:
> ASTで上書きや追加出来るで良いと思う。parse以外のフィルタは大抵からだろうし

各 type が自分のデフォルト filter chain を持ち、AST 側で `@base` で継承可能。

## filter は純粋関数

検討した拡張:

### A. コンテキストアクセス
filter から他要素や ParserContext を見られるか? → 不要。他要素との整合チェックは post-parse でアプリ側がやる。

### B. アクション指示
filter が「捨てる」「スキップ」等のアクションを返せるか? → 不要。実行制御は別機構 (help/version 等の onSelected で)。

### C. エラー処理の粒度
警告/フォールバック等の細かい制御? → 単純な ParseError throw のみ。警告は DX 層の責務。

filter は **値の変換と検証だけ** に集中。

## `each` を明示しない

kawaz:
> eachの方を長い名前にするのは本末転倒。基本はeach。

`filters` は **暗黙で要素単位**。分割があれば自動で each、なければ単一値に直接。書き手は1要素分の filter chain だけ書けばいい。

## 関連

- DR-008 (multiple フィールド、分割の表現)
- DR-010 (type registry のデフォルト filter)
- DR-011 (variant DSL と同一文法)
