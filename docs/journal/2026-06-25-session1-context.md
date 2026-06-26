# 2026-06-25 セッション1 ハンドオフ (旧 CONTEXT.md)

> 第1セッション (DR-001〜037 を積み上げた議論) の終端で書かれたハンドオフ文書。
> 当時の議論スタンス・確定事項・未確定論点 A〜M を凍結記録として保存。
> 現状を知るには `docs/DESIGN.md` と各 DR、第2セッションのハンドオフ (`2026-06-26-session2-dr038-040.md`) を参照。

このドキュメントは、kuu の引数定義 AST 設計議論を別セッションに引き継ぐためのもの。

## 議論の出発点

kuu (https://github.com/kawaz/kuu.mbt) のコア実装は進んでいるが、言語非依存の引数定義 AST をゼロベースで設計し直したい。実装レベルの詳細 (MoonBit コード、コンビネータ実装) は議論の対象外。kuu core は「ボトムアップで書いたプロトタイプ」であり、AST 設計と合わない箇所は変えていく方針。

「**言語によらない引数定義としての JSON**」を作る、というのが目的。

## ユーザー (kawaz) の議論スタンス

- **新しい概念を勝手に増やすことを嫌う**: 既存の道具で表現できないか先に検討する
- **暗黙ルールを警戒**: 「自動でこうなる」が読み手の予測を超えないこと、明示性重視
- **CLI 慣習との整合性を意識**: メジャーパーサの調査・参照を時折求める
- **モバイル環境で書くことが多い**: 長い書き込みは少なめ、概念を素早く書く傾向
- **忖度を嫌う**: 「忖度なしの意見を常にください」と明言
- **「設計が歪んでいるかも」と感じる感覚を重視**: 違和感をそのまま言語化して指摘してくる
- **勝手にまとめない**: 議論の途中で結論に飛ばない、確認しながら進める

## Claude が反省すべきパターン

過去の議論で何度か起きた反省ポイント:

1. **概念を勝手に膨らませる**: 「ついでにこれも一般化できる」と拡張提案するが、ユーザーは元の発想のシンプルさを大事にしていることが多い
2. **新しいフィールドを安易に提案**: `groupRules`、`valueFn` 等を勝手に提案。既存フィールドで表現できないか先に検討する
3. **CLI 慣習を当たり前に持ち込む**: options/positionals/commands の3分割など、慣習にバイアスがかかった整理をしてしまう
4. **暗黙ルールを増やしがち**: 型依存ルール等を安易に提案
5. **責務混在**: parse に複数の役割を詰め込む等
6. **本人の発言を勝手に命名**: kawaz が言ってないフィールド名 (`on_repeat`, `pre_split_filter` 等) を Claude が後付け命名して定着させる罠
7. **既存設計を読まずに局所最適**: 全体を把握する前に一部だけ詰める

## 設計の核となる発想

### a. 「同型」の発見

すべての要素は「name でトリガする可能性のある、children を持つかもしれない要素」として同型。CLI 慣習用語はシュガーへの愛称。

### b. 2層 AST 構造

```
UsefulAST (人間が書く、各言語 DX コード)
    ↓ parseDefinition()
AtomicAST (パーサが走る正規形)
```

### c. 値の発生と伝搬

primitive type / exact / or / seq の構造的セマンティクスで値が tree を伝搬。

### d. レジストリの外部注入

実装の責務は AST 外のレジストリで提供。AST はフィールド名で暗黙参照。

### e. 「あと勝ち」mutation

値プレースホルダは型のゼロ値/null で初期化、CLI 入力順に mutation。

### f. 名前の3層分離 (DR-024)

key name (結果キー) / def name (参照名) / value_name (表示) を独立に管理。

### g. type と multiple は同じ属性平面 (DR-034)

type は peaceProcessor 中心、multiple は累積戦略中心、同じ属性平面の異なる断面への参照。

## 確定したこと (要点)

### 構造

- options / positionals の2分割、commands は positionals 内 or 糖衣 (DR-018)
- name は3層 (key/def/value_name)、配置で役割が決まる (DR-024)
- name がスコープを作る (結果スコープ = lexical スコープ、DR-025/033)
- ref/link は lexical scope chain で解決 (現在 → 外側 → definitions、DR-032)
- 入口を持たない「実体だけノード」(DR-030)

### 構造記法

- 葉/枝の区別、exact は値プリミティブの一種 (DR-026)
- 裸文字列 = exact、裸配列 = seq の糖衣 (DR-026)
- serial → seq 改名 (DR-027)
- object は独立構造でなく露出の帰結 (DR-025)

### 値

- type は1要素分の型、配列型表記なし
- values は or のショートハンド
- multiple の構造: peaceProcessor / separator / mapper / collector (DR-034)
- multiple 無しは縮退ケース (mapper=override、collector=unwrap_single)
- リテラルは primitive + value のシュガー

### type と参照

- type は definitions/registry への参照糖衣 (DR-028)
- ref/link は name 参照、type は型参照 (DR-032)
- 解決順: definitions.X → registry.X → warn+string (DR-028/035)

### multiple とレジストリ

- multiple registry 追加で 8 区分 (DR-036)
- accumulators を属性セットに拡張
- collectors は独立 registry にせず filters で代替
- 組み込み multiple プリセット: append / merge / set / map
- mergeable (kuu DR-023) の +/- 修飾子は mapper の責務

### 値源と継承

- 値源の優先順位 (固定): CLI/link > env > config > inherit > default (DR-031)
- inherit (default の取得先)
- inheritable (祖先 scope からも書ける、prefix 自動付与)
- config フィールドで階層継承可能な設定

### filter chain

- 3段: pre_filters / filters (each 暗黙) / post_filters
- DSL は variant と同じ `<name>:<arg>:...` 形式
- filter は純粋関数 (値→値 or Reject/Error)
- Reject と Error を区別 (DR-037): Reject は脱落、Error は保持
- `@base` sentinel で type/ref 元のデフォルト継承

### パース挙動

- 最長一致パース、解けた枝の数で結末 (0=失敗、1=採用、2+=ambiguous、DR-021/037)
- 露出キー一意性は実行時検査、warn はする reject はしない
- 露出キーの型不一致は union、嫌うなら export_key

### CLI 起動

- long/short、variant DSL (DR-011)
- effect 4種: set/default/unset/empty
- variant は AtomicAST で消える

### 制約

- required (boolean のみ)
- グループ的必須は or + required
- exclusive_group (string[])
- requires (string[])
- groupRules は作らない (DR-012)

### 命名規約

- snake_case 正規形 (DR-022)
- case 変換は pluggable (各言語デフォルト変換器、固定しない)

### 結果

- ParserContext (詳細) と結果オブジェクト (シンプル) の2層
- source 語彙: cli/link/env/config/inherit/default (DR-031)

## 残る論点 (未確定)

### A. AtomicAST の最終形

UsefulAST → AtomicAST の変換規則を網羅的に確定する。これが決まると JSON Schema が書ける。

### B. values 展開ルールの正式仕様

- 配列内が全 literal → or
- 配列内に typed object → seq ブランチ
- 混在 → ?
- ネスト時の name 由来の露出構造化
- 注: name 無しリストの子 name 露出の一意性は DR-021 で実行時検査に整理済み

### C. or の細則

- or の中の name 重複ルール ← DR-021 で実行時 ambiguous に整理。定義時の表記は要確定
- or 自体が scope を作るか
- or の値伝搬 ← DR-015 で確定

### D. 動的名前付きスコープ (keyFrom) の細則

- multiple: "map" + keyFrom の動作
- inheritable との関係
- 結果オブジェクトの形

### E. inheritable の細則

- prefix 生成ルール (案A 直近のみ / 案A+B' 衝突時のみ長いパス)
- ヘルプ表示への影響 (--help-all 等)

### F. visibility / deprecated の表現

- 配列順次差分か宣言型か
- ヘルプ / 補完 / 警告のディメンション

### G. 標準 filter / accumulator セットの確定

- どれをコア / 標準 / 拡張に振り分けるか
- 命名

### H. type registry の最小インターフェース

- parse / accumulator / onSelected / 他のスロット定義
- 各言語実装の推奨ガイド

### I. ヘルプ生成・補完生成

- AST 仕様の付属として規定するか
- 実装側の自由か

### J. エラーメッセージのテンプレ

- 未実装誘導のテンプレ
- diagnose モードの出力
- 複数枝の Error 候補の表示優先順位 (DR-037 で「奥まで進んだ方」と仮置きだが詳細未確定)

### K. JSON Schema

- 全部固まってから書く

### L. registry 区分の最終確定

- DR-010 + DR-036 で 8 区分挙げているが、統合/分離の余地あり
- types と accumulators が両方「属性プリセット」で機構的に同じ
- 区分の名前と数は最終確定していない

### M. ambiguous 詳細出力のフラグ

- パーサ API 層の話、AST 設計の射程外として保留

## 議論を再開するときのチェックリスト

1. このドキュメントと `docs/DESIGN.md` を読み返す
2. DR-* の決定記録を流し読む (確定した経緯と理由を確認)
3. 残る論点 (A-M) から進めたいものを選ぶ
4. kawaz の議論スタンスを意識: 新概念を膨らませない、暗黙ルールを増やさない、慣習にバイアスをかけない
5. 進めながら必要なら DR を追加で記録、AST-SPEC/CONTEXT も追従更新

## 元リポジトリ参考

- kuu 本体: https://github.com/kawaz/kuu.mbt
- kuu 側 DR-023 (mergeable list、+/- 修飾子): 本 AST 設計の DR-034 の mapper シグネチャでサポート
- kuu 側 DR-037 (alias/link/adjust 3 軸プリミティブ): 「振る舞いプリセット」の発想の起源
