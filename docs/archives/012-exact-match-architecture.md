# DR-012: ExactNode アーキテクチャへの設計転換

DESIGN.md の ErasedNode/Opts 構造から、ExactNode ベースの4層レイヤーアーキテクチャに転換した設計判断の記録。

## 経緯

実装計画の議論中に、ユーザーから以下の洞察が提示された:

1. **オプションは exact-match の or シュガー**: `flag(name="verbose")` は内部的に `--verbose` と `--no-verbose` の2つの完全一致ノードに展開される。消費ループは完全一致マッチだけを行い、`--no-` やエイリアスの展開はコンビネータ層の責務
2. **serial は再帰的二項構造**: `serial(o1, o2, o3) = serial(o1, serial(o2, serial(o3)))` — 配列ではなく「次の positional を持つ opt」のリンクドリスト
3. **コマンドを特別視しない**: コマンドもオプションも「名前マッチ → 子opts を活性化」する同じ構造
4. **子パーサ方式**: サブコマンドのスコープ切替は子パーサの再帰呼び出し。ID空間は `next_id` クロージャの共有で統一

さらに、これら4つの洞察を統合すると4層レイヤー構造が自然に導出された:

```
flag(name="verbose")                   # Sugar: Bool特化
  → option(name="verbose", ...)        # Convention: --name/--no-name パターン生成
    → or([                             # Pattern: 複数 exact を同一 Ref で束ねる
        exact("--verbose", set_true),  # Core: 単一名マッチ + reducer
        exact("--no-verbose", reset),
      ])
```

## 議論ログ

### ユーザー発言1: 子パーサ方式の提案

> reduce なんだけど、トップでパーサにかけるのもreduce時に次の引数をチェックするのも実は同じで、各オプションが最長先食いする際の自分の引数消費ってその各オプションレベルで新しいparserインスタンスを作ってそれに子optリストを新しいparserの parseにかければ実は良くね？自然とスコープ単位のrefsもパーサについてくるし。
>
> あでもidの名前空間を兼ねてるからそこで子パーサが個別のseqをもつと問題あるか。とすると大元のパーサがまずnewされたら内部にIntを持つnext_id()->Intクロージャが初期化されて、パース時に各optのreducer呼ぶ際にparserから子パーサを生成してそいつはそのスコープ階層の空refsを持ちnext_idは親のそれを引き継ぐようにしたらrootパーサ内で閉じたid名前空間が複数パーサで保てるのでは？

### ユーザー発言2: exact-match と or 展開の提案

> ところで僕はserialはarrayじゃ無いと思ってるんだが。serialは実は一つのオプショナルな追加引数があるoptだと思ってる。serial(o)→o、serial(o1,o2,o3)→serial(o1,serial(o2,serial(o3)))
>
> あとコマンドは特別視しないと設計してたはずOCが同列扱いは区別が不要だからです。子引数を持つオプションと同じに扱って良いはず。
>
> で、コマンドとオプションの違いだが、実はオプションはインスタンス化する際に内部ではnameから、サブコマンド同様に完全一致名の--name,--no-name,--aliase,--no-aliase,-sという名前の反転やハイフン特別視などもクソも無いorのoptを返すシュガーだと認識してるんだが。どう思う?すごくシンプルになりそうじゃ無い？ちなみに--no-とかを生成するときは名前が完全一致なoptだけどリセット用機能を持ったreducerもちのoptが作られてくみたいなイメージ。

### ユーザー発言3: レイヤー化の洞察

> で多分オプションをorに展開するのはパターンができると思うし、そのorへの展開をするシュガー(ユーティリティ関数かoptの一種かみたい）だと思えばさらにシンプルになると思ってる。flag(name)→option(opt[Bool])→or(--name,--no-name)みたいな。

## 変更点

### 1. 4層レイヤー構造

消費ループの責務を最小化し、複雑さをコンビネータ層に押し出す。

| レイヤー | 責務 |
|---------|------|
| Core | `ExactNode`（完全一致名マッチ + reducer）+ 消費ループ |
| Pattern | `or` — 同一Refの複数ExactNodeを束ねる |
| Convention | `option` — --name/--no-name の命名規則パターン生成 |
| Sugar | `flag()`, `int_opt()`, `string_opt()` — 型特化ショートカット |

選択理由: 消費ループが名前解決ロジックを持たなくて済む。`--no-xxx`、エイリアス、短縮形はすべてコンビネータレベルで独立ExactNodeに展開される。

### 2. serial の再帰的二項構造

旧設計: serial は Opts::Array の特殊なバリアント
新設計: serial(o1, o2, o3) = serial(o1, serial(o2, serial(o3)))

選択理由: 「消費されたら次のpositionalを活性化する」という自然なリンクドリスト構造。

### 3. コマンドの非特別視

旧設計: OC（Option/Command）を同列として消費ループ内で区別
新設計: コマンドもオプションも「名前マッチ→子optsを活性化」する同じ構造。違いはkindによるスコープ振る舞いのみ。

選択理由: 消費ループのコードパスが単純化される。

### 4. 子パーサ方式

旧設計: parse関数内でスコープ状態変数を管理
新設計: サブコマンドのスコープ切替は子パーサの再帰呼び出し。ルートパーサの next_id クロージャを子パーサが共有してID空間を統一。

選択理由: 各パーサがスコープ単位のrefsを自然に持つ。Ref[T]はクロージャ経由でどの階層からもアクセス可能。

## 不採用としたもの

- ErasedNode のchildren/metaフィールド → ExactNodeに不要（名前が完全一致なのでメタ情報で名前解決する必要がない）
- TryReduceResult の2値（Accept/Reject）のみ → Error(ParseError) を追加。exact matchで名前確定後の型変換失敗は即エラーにすべき
- プレフィックスマッチ → MVP後に追加レイヤーとして実装可能。初期はexact matchのみ

## 影響範囲

- DESIGN.md の ErasedNode/Opts セクションを全面更新必要
- poc/poc4 の設計（Parser struct + getter方式）は継承
- 消費ループのアルゴリズム（先食い最長一致）は継承
